import Foundation
import XCTest
@testable import TermiRustMobile

@MainActor
final class ControllerPairingFleetTests: XCTestCase {
    func testPairingPersistsHostThenLoadsAuthoritativeReadOnlyFleet() async throws {
        let fixture = try Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let connection = FixtureConnection(record: fixture.record)
        let viewModel = ControllerViewModel(
            connectionActor: connection,
            hostStore: fixture.hostStore,
            cacheStore: fixture.cacheStore,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        viewModel.pairingOfferText = "bounded-offer"
        viewModel.pairingHostName = "Office Mac"
        viewModel.pairingDeviceName = "Test iPhone"

        viewModel.beginPairing()
        try await waitUntil { viewModel.pairingChallenge?.sas == "ABCD-1234" }
        viewModel.finishPairing(matches: true)
        try await waitUntil { viewModel.state.connection == .readyReadOnly }

        XCTAssertEqual(viewModel.state.hosts.map(\.title), ["Office Mac"])
        XCTAssertEqual(viewModel.state.sessions.map(\.title), ["Build agent"])
        XCTAssertFalse(viewModel.state.isCachedReadOnly)
        let storedHosts = try await fixture.hostStore.load()
        let storedCache = try await fixture.cacheStore.load()
        XCTAssertEqual(storedHosts.count, 1)
        XCTAssertEqual(storedCache.hosts[fixture.record.id]?.sessions.count, 1)
    }

    func testOfflineRefreshPreservesAndMarksLastCompleteCacheReadOnly() async throws {
        let fixture = try Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var cache = ControllerFleetCache()
        try cache.replace(
            hostFingerprint: fixture.record.id,
            revision: 3,
            updateSequence: 3,
            sessions: [Fixture.session],
            selectedHostFingerprint: fixture.record.id,
            now: Date(timeIntervalSince1970: 5)
        )
        _ = try await fixture.hostStore.upsert(fixture.record)
        try await fixture.cacheStore.save(cache)
        let connection = FixtureConnection(record: fixture.record, failures: [.networkUnavailable])
        let viewModel = ControllerViewModel(
            connectionActor: connection,
            hostStore: fixture.hostStore,
            cacheStore: fixture.cacheStore,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            retryPolicy: .immediateTestPolicy(maxAttempts: 1)
        )

        try await waitUntil {
            viewModel.state.isCachedReadOnly && viewModel.state.connection == .failed(.networkUnavailable)
        }

        XCTAssertEqual(viewModel.state.sessions, [Fixture.session])
        XCTAssertEqual(viewModel.state.cacheUpdatedAt, Date(timeIntervalSince1970: 5))
    }

    func testTransientFailuresRetryThenRecover() async throws {
        let fixture = try Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.hostStore.upsert(fixture.record)
        let connection = FixtureConnection(
            record: fixture.record,
            failures: [.networkUnavailable, .timedOut]
        )
        let viewModel = ControllerViewModel(
            connectionActor: connection,
            hostStore: fixture.hostStore,
            cacheStore: fixture.cacheStore,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            retryPolicy: .immediateTestPolicy(maxAttempts: 8)
        )

        try await waitUntil { viewModel.state.connection == .readyReadOnly }

        let fetchCount = await connection.fetchCount
        XCTAssertEqual(fetchCount, 3)
    }

    func testRetryStopsAtConfiguredAttemptLimit() async throws {
        let fixture = try Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.hostStore.upsert(fixture.record)
        let connection = FixtureConnection(record: fixture.record, repeatingFailure: .networkUnavailable)
        let viewModel = ControllerViewModel(
            connectionActor: connection,
            hostStore: fixture.hostStore,
            cacheStore: fixture.cacheStore,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            retryPolicy: .immediateTestPolicy(maxAttempts: 8)
        )

        try await waitUntil { viewModel.state.connection == .failed(.networkUnavailable) }

        let fetchCount = await connection.fetchCount
        XCTAssertEqual(fetchCount, 8)
    }

    func testAuthenticationFailureDoesNotRetry() async throws {
        let fixture = try Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        _ = try await fixture.hostStore.upsert(fixture.record)
        let connection = FixtureConnection(record: fixture.record, repeatingFailure: .authenticationFailed)
        let viewModel = ControllerViewModel(
            connectionActor: connection,
            hostStore: fixture.hostStore,
            cacheStore: fixture.cacheStore,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            retryPolicy: .immediateTestPolicy(maxAttempts: 8)
        )

        try await waitUntil { viewModel.state.connection == .failed(.authenticationFailed) }

        let fetchCount = await connection.fetchCount
        XCTAssertEqual(fetchCount, 1)
    }

    func testFullJitterDelayIsBoundedByBackoffAndDeadline() {
        let policy = ControllerRetryPolicy(
            maxAttempts: 8,
            maxElapsedSeconds: 90,
            baseDelaySeconds: 1,
            maxDelaySeconds: 30,
            randomUnit: { 0.75 },
            sleep: { _ in }
        )

        XCTAssertEqual(policy.delayAfterFailure(attempt: 1, elapsedSeconds: 0), 0.75)
        XCTAssertEqual(policy.delayAfterFailure(attempt: 6, elapsedSeconds: 0), 22.5)
        XCTAssertEqual(policy.delayAfterFailure(attempt: 6, elapsedSeconds: 89), 1)
        XCTAssertNil(policy.delayAfterFailure(attempt: 8, elapsedSeconds: 0))
        XCTAssertNil(policy.delayAfterFailure(attempt: 1, elapsedSeconds: 90))
    }

    func testUnreconciledPairingAcknowledgementHasExplicitRecoveryState() async throws {
        let fixture = try Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let connection = FixtureConnection(
            record: fixture.record,
            finishFailure: .acknowledgementUncertain
        )
        let viewModel = ControllerViewModel(
            connectionActor: connection,
            hostStore: fixture.hostStore,
            cacheStore: fixture.cacheStore,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            retryPolicy: .immediateTestPolicy(maxAttempts: 1)
        )
        viewModel.pairingOfferText = "bounded-offer"
        viewModel.pairingHostName = "Office Mac"
        viewModel.pairingDeviceName = "Test iPhone"

        viewModel.beginPairing()
        try await waitUntil { viewModel.pairingChallenge != nil }
        viewModel.finishPairing(matches: true)
        try await waitUntil { viewModel.state.connection == .failed(.pairingUncertain) }

        let storedHosts = try await fixture.hostStore.load()
        XCTAssertTrue(storedHosts.isEmpty)
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition did not become true before timeout")
    }
}

private actor FixtureConnection: ControllerConnecting {
    let record: PairedHostRecord
    private var failures: [ControllerFailure]
    private let repeatingFailure: ControllerFailure?
    private let finishFailure: ControllerPairingError?
    private(set) var fetchCount = 0

    init(
        record: PairedHostRecord,
        failures: [ControllerFailure] = [],
        repeatingFailure: ControllerFailure? = nil,
        finishFailure: ControllerPairingError? = nil
    ) {
        self.record = record
        self.failures = failures
        self.repeatingFailure = repeatingFailure
        self.finishFailure = finishFailure
    }

    func beginPairing(
        offerText: String,
        hostName: String,
        deviceName: String,
        deviceID: UUID
    ) async throws -> ControllerPairingChallenge {
        ControllerPairingChallenge(
            hostFingerprint: record.id,
            route: record.route,
            sas: "ABCD-1234",
            expiresAt: .now.addingTimeInterval(60)
        )
    }

    func finishPairing(matches: Bool) async throws -> PairedHostRecord {
        guard matches else { throw ControllerPairingError.rejected }
        if let finishFailure { throw finishFailure }
        return record
    }

    func fetchSessions(
        host: PairedHostRecord,
        progress: @escaping @Sendable (ControllerConnectionProgress) async -> Void
    ) async throws -> ControllerFleetSnapshot {
        fetchCount += 1
        await progress(.authenticating)
        if !failures.isEmpty { throw failures.removeFirst() }
        if let repeatingFailure { throw repeatingFailure }
        await progress(.syncing)
        return ControllerFleetSnapshot(revision: 1, updateSequence: 1, sessions: [Fixture.session])
    }

    func forgetDeviceSecret(host: PairedHostRecord) async throws {}
    func cancel() async {}
}

private extension ControllerRetryPolicy {
    static func immediateTestPolicy(maxAttempts: Int) -> Self {
        Self(
            maxAttempts: maxAttempts,
            maxElapsedSeconds: 90,
            baseDelaySeconds: 1,
            maxDelaySeconds: 30,
            randomUnit: { 0 },
            sleep: { _ in }
        )
    }
}

private struct Fixture {
    let directory: URL
    let record: PairedHostRecord
    let hostStore: PairedHostStore
    let cacheStore: ControllerFleetCacheStore

    static let session = ControllerSessionSummary(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Build agent",
        project: nil,
        group: nil,
        lifecycle: "running",
        occupantGeneration: 1,
        lastOutputSequence: 4,
        hasWriter: false,
        unreadCount: 0
    )

    static func make() throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = try PairedHostRecord(
            id: "host-fixture",
            displayName: "Office Mac",
            route: HostRoute(address: "192.168.1.20", port: 55_555),
            hostStaticPublicKey: Data(repeating: 4, count: 32),
            deviceStaticKeyId: "controller.device.fixture",
            deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            identityGeneration: 1,
            revocationEpoch: 0,
            sessionGeneration: 0,
            capabilityBits: 1,
            pairedAt: Date(timeIntervalSince1970: 1)
        )
        return try Self(
            directory: directory,
            record: record,
            hostStore: PairedHostStore(fileURL: directory.appendingPathComponent("hosts.json")),
            cacheStore: ControllerFleetCacheStore(fileURL: directory.appendingPathComponent("cache.json"))
        )
    }
}
