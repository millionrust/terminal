import Foundation
import SwiftUI
import UIKit

@MainActor
final class ControllerViewModel: ObservableObject {
    @Published private(set) var state = ControllerViewState.empty
    @Published private(set) var pairingChallenge: ControllerPairingChallenge?
    @Published var pairingOfferText = ""
    @Published var pairingHostName = "My Mac"
    @Published var pairingDeviceName = UIDevice.current.name
    @Published private(set) var activeTerminal: ControllerTerminalViewModel?

    private let connectionActor: (any ControllerConnecting)?
    private let hostStore: PairedHostStore?
    private let cacheStore: ControllerFleetCacheStore?
    private let retryPolicy: ControllerRetryPolicy
    private var hostRecords: [PairedHostRecord] = []
    private var cache = ControllerFleetCache()
    private let deviceID: UUID
    private var operation: Task<Void, Never>?

    init(
        connectionActor: (any ControllerConnecting)? = nil,
        hostStore: PairedHostStore? = nil,
        cacheStore: ControllerFleetCacheStore? = nil,
        defaults: UserDefaults = .standard,
        retryPolicy: ControllerRetryPolicy = .live
    ) {
        self.deviceID = Self.loadDeviceID(defaults: defaults)
        self.retryPolicy = retryPolicy
        if let connectionActor, let hostStore, let cacheStore {
            self.connectionActor = connectionActor
            self.hostStore = hostStore
            self.cacheStore = cacheStore
        } else {
            let blobStore = ControllerKeychainBlobStore()
            self.connectionActor = try? ControllerConnectionActor(blobStore: blobStore)
            self.hostStore = try? PairedHostStore()
            self.cacheStore = try? ControllerFleetCacheStore()
        }
        guard self.connectionActor != nil, self.hostStore != nil, self.cacheStore != nil else {
            state = ControllerViewState(
                hosts: [],
                selectedHostID: nil,
                sessions: [],
                connection: .failed(.storageUnavailable),
                cacheUpdatedAt: nil,
                isCachedReadOnly: false
            )
            return
        }
        operation = Task { [weak self] in await self?.restore() }
    }

    deinit {
        operation?.cancel()
    }

    var selectedHost: PairedHostRecord? {
        hostRecords.first { $0.id == state.selectedHostID }
    }

    func beginPairing() {
        guard let connectionActor else { return }
        operation?.cancel()
        pairingChallenge = nil
        state = replacing(connection: .pairing, sessions: state.sessions)
        let offer = pairingOfferText
        let hostName = pairingHostName
        let deviceName = pairingDeviceName
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let challenge = try await connectionActor.beginPairing(
                    offerText: offer,
                    hostName: hostName,
                    deviceName: deviceName,
                    deviceID: deviceID
                )
                guard !Task.isCancelled else { return }
                pairingChallenge = challenge
                state = replacing(connection: .sasReady(challenge.sas), sessions: state.sessions)
            } catch {
                guard !Task.isCancelled else { return }
                state = replacing(connection: .failed(Self.failure(error)), sessions: state.sessions)
            }
        }
    }

    func finishPairing(matches: Bool) {
        guard let connectionActor, let hostStore else { return }
        operation?.cancel()
        state = replacing(connection: .pairing, sessions: state.sessions)
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let record = try await connectionActor.finishPairing(matches: matches)
                hostRecords = try await hostStore.upsert(record)
                pairingChallenge = nil
                pairingOfferText = ""
                state = makeState(
                    selectedHostID: record.id,
                    sessions: [],
                    connection: .pairedOffline,
                    cacheUpdatedAt: nil,
                    isCached: false
                )
                await refresh(host: record)
            } catch {
                guard !Task.isCancelled else { return }
                pairingChallenge = nil
                state = replacing(connection: .failed(Self.failure(error)), sessions: state.sessions)
            }
        }
    }

    func cancelPairing() {
        operation?.cancel()
        operation = nil
        pairingChallenge = nil
        Task { await connectionActor?.cancel() }
        state = makeState(
            selectedHostID: state.selectedHostID,
            sessions: state.sessions,
            connection: hostRecords.isEmpty ? .unpaired : .pairedOffline,
            cacheUpdatedAt: state.cacheUpdatedAt,
            isCached: state.isCachedReadOnly
        )
    }

    func selectHost(id: String?) {
        guard state.selectedHostID != id else { return }
        operation?.cancel()
        let cached = id.flatMap { cache.hosts[$0] }
        state = makeState(
            selectedHostID: id,
            sessions: cached?.sessions ?? [],
            connection: id == nil ? .pairedOffline : .pairedOffline,
            cacheUpdatedAt: cached?.updatedAt,
            isCached: cached != nil
        )
        guard let id, let host = hostRecords.first(where: { $0.id == id }) else { return }
        cache.markViewed(hostFingerprint: id, at: .now)
        operation = Task { [weak self] in await self?.refresh(host: host) }
    }

    func retry() {
        guard let selectedHost else { return }
        operation?.cancel()
        operation = Task { [weak self] in await self?.refresh(host: selectedHost) }
    }

    func suspend() {
        activeTerminal?.suspend()
        operation?.cancel()
        operation = nil
        Task { await connectionActor?.cancel() }
        let cached = state.selectedHostID.flatMap { cache.hosts[$0] }
        state = makeState(
            selectedHostID: state.selectedHostID,
            sessions: cached?.sessions ?? state.sessions,
            connection: hostRecords.isEmpty ? .unpaired : .pairedOffline,
            cacheUpdatedAt: cached?.updatedAt,
            isCached: cached != nil
        )
    }

    func resume() {
        if let activeTerminal {
            activeTerminal.resume()
            return
        }
        guard operation == nil else { return }
        retry()
    }

    func openReadOnlyTerminal(_ session: ControllerSessionSummary) {
        guard activeTerminal == nil,
              !state.isCachedReadOnly,
              state.connection == .readyReadOnly,
              let host = selectedHost,
              let connectionActor,
              host.capabilityBits & (1 << 1) != 0,
              session.capabilities.isEmpty || session.capabilities.contains(.attachOutput),
              session.occupantGeneration != nil else { return }
        activeTerminal = try? ControllerTerminalViewModel(
            host: host,
            session: session,
            connection: connectionActor
        )
    }

    func closeReadOnlyTerminal() {
        activeTerminal?.detach()
        activeTerminal = nil
        retry()
    }

    func forgetSelectedHost() {
        guard let host = selectedHost,
              let connectionActor,
              let hostStore else { return }
        operation?.cancel()
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await connectionActor.forgetDeviceSecret(host: host)
                hostRecords = try await hostStore.remove(id: host.id)
                cache.remove(hostFingerprint: host.id)
                if let cacheStore { try await cacheStore.save(cache) }
                let next = hostRecords.first
                state = makeState(
                    selectedHostID: next?.id,
                    sessions: next.flatMap { cache.hosts[$0.id]?.sessions } ?? [],
                    connection: next == nil ? .unpaired : .pairedOffline,
                    cacheUpdatedAt: next.flatMap { cache.hosts[$0.id]?.updatedAt },
                    isCached: next.flatMap { cache.hosts[$0.id] } != nil
                )
            } catch {
                state = replacing(connection: .failed(Self.failure(error)), sessions: state.sessions)
            }
        }
    }

    private func restore() async {
        guard let hostStore, let cacheStore else { return }
        do {
            async let loadedHosts = hostStore.load()
            async let loadedCache = cacheStore.load()
            hostRecords = try await loadedHosts
            cache = try await loadedCache
            let selected = hostRecords.first
            let cached = selected.flatMap { cache.hosts[$0.id] }
            state = makeState(
                selectedHostID: selected?.id,
                sessions: cached?.sessions ?? [],
                connection: selected == nil ? .unpaired : .pairedOffline,
                cacheUpdatedAt: cached?.updatedAt,
                isCached: cached != nil
            )
            if let selected { await refresh(host: selected) }
        } catch {
            state = replacing(connection: .failed(.storageUnavailable), sessions: [])
        }
    }

    private func refresh(host: PairedHostRecord) async {
        guard let connectionActor, let cacheStore else { return }
        let startedAt = Date()
        var attempt = 1

        while !Task.isCancelled, state.selectedHostID == host.id {
            state = replacing(connection: .connecting, sessions: state.sessions)
            do {
                let snapshot = try await connectionActor.fetchSessions(host: host) { [weak self] progress in
                    await self?.apply(progress: progress, forHostID: host.id)
                }
                guard !Task.isCancelled, state.selectedHostID == host.id else { return }
                if cache.hosts[host.id]?.revision != snapshot.revision
                    || cache.hosts[host.id]?.updateSequence != snapshot.updateSequence {
                    try cache.replace(
                        hostFingerprint: host.id,
                        revision: snapshot.revision,
                        updateSequence: snapshot.updateSequence,
                        sessions: snapshot.sessions,
                        selectedHostFingerprint: host.id,
                        now: .now
                    )
                    try await cacheStore.save(cache)
                }
                let stored = cache.hosts[host.id]
                state = makeState(
                    selectedHostID: host.id,
                    sessions: snapshot.sessions,
                    connection: .readyReadOnly,
                    cacheUpdatedAt: stored?.updatedAt,
                    isCached: false
                )
                return
            } catch {
                guard !Task.isCancelled, state.selectedHostID == host.id else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                guard Self.shouldRetry(error),
                      let delay = retryPolicy.delayAfterFailure(
                          attempt: attempt,
                          elapsedSeconds: elapsed
                      ) else {
                    applyTerminalFailure(error, for: host)
                    return
                }
                attempt += 1
                do {
                    try await retryPolicy.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func apply(progress: ControllerConnectionProgress, forHostID hostID: String) {
        guard !Task.isCancelled, state.selectedHostID == hostID else { return }
        let connection: ControllerConnectionState = switch progress {
        case .authenticating: .authenticating
        case .syncing: .syncing
        }
        state = replacing(connection: connection, sessions: state.sessions)
    }

    private func applyTerminalFailure(_ error: Error, for host: PairedHostRecord) {
        let cached = cache.hosts[host.id]
        let connection: ControllerConnectionState
        if case ControllerBindingError.IncompatibleVersion = error {
            connection = .incompatible
        } else if let error = error as? ControllerConnectionError,
                  case .hostError(let code) = error,
                  Self.isRevocationCode(code) {
            connection = .revoked
        } else {
            connection = .failed(Self.failure(error))
        }
        state = makeState(
            selectedHostID: host.id,
            sessions: cached?.sessions ?? [],
            connection: connection,
            cacheUpdatedAt: cached?.updatedAt,
            isCached: cached != nil
        )
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if error is CancellationError || error is SecureBlobError { return false }
        if let error = error as? ControllerConnectionError {
            switch error {
            case .authenticationFailed, .capabilityDenied, .malformedResponse, .resourceLimit:
                return false
            case .hostError(let code):
                return !isTerminalHostCode(code)
            case .sequenceGap:
                return true
            }
        }
        if let error = error as? ControllerBindingError {
            switch error {
            case .TimedOut, .Unexpected:
                return true
            default:
                return false
            }
        }
        return true
    }

    private static func isTerminalHostCode(_ code: String) -> Bool {
        let normalized = code.lowercased()
        return ["auth", "denied", "forbidden", "incompatible", "policy", "revoked", "unauthorized", "version"]
            .contains { normalized.contains($0) }
    }

    private static func isRevocationCode(_ code: String) -> Bool {
        code.lowercased().contains("revok")
    }

    private func replacing(
        connection: ControllerConnectionState,
        sessions: [ControllerSessionSummary]
    ) -> ControllerViewState {
        ControllerViewState(
            hosts: state.hosts,
            selectedHostID: state.selectedHostID,
            sessions: sessions,
            connection: connection,
            cacheUpdatedAt: state.cacheUpdatedAt,
            isCachedReadOnly: state.isCachedReadOnly
        )
    }

    private func makeState(
        selectedHostID: String?,
        sessions: [ControllerSessionSummary],
        connection: ControllerConnectionState,
        cacheUpdatedAt: Date?,
        isCached: Bool
    ) -> ControllerViewState {
        ControllerViewState(
            hosts: hostRecords.map {
                HostSummary(
                    id: $0.id,
                    title: $0.displayName,
                    route: $0.route,
                    fingerprint: $0.fingerprint,
                    capabilityBits: $0.capabilityBits
                )
            },
            selectedHostID: selectedHostID,
            sessions: sessions,
            connection: connection,
            cacheUpdatedAt: cacheUpdatedAt,
            isCachedReadOnly: isCached
        )
    }

    private static func failure(_ error: Error) -> ControllerFailure {
        if error is CancellationError { return .cancelled }
        if let error = error as? ControllerPairingError {
            switch error {
            case .expiredOrIncompatibleOffer: return .offerExpired
            case .invalidOffer, .publicRouteRejected, .invalidDeviceName: return .invalidOffer
            case .timedOut: return .timedOut
            case .rejected: return .sasMismatch
            case .randomUnavailable: return .keychainUnavailable
            case .acknowledgementUncertain: return .pairingUncertain
            default: return .authenticationFailed
            }
        }
        if let error = error as? ControllerConnectionError {
            switch error {
            case .sequenceGap: return .sequenceGap
            case .resourceLimit: return .resourceLimit
            case .malformedResponse: return .malformedResponse
            case .authenticationFailed, .capabilityDenied, .hostError(_): return .authenticationFailed
            }
        }
        if error is SecureBlobError { return .keychainUnavailable }
        if error is ControllerCacheError || error is PairedHostStoreError {
            return .storageUnavailable
        }
        return .networkUnavailable
    }

    private static func loadDeviceID(defaults: UserDefaults) -> UUID {
        let key = "termirust.controller.device_uuid"
        if let value = defaults.string(forKey: key), let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString.lowercased(), forKey: key)
        return id
    }
}
