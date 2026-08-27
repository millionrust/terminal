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
        let connection = FixtureConnection(record: fixture.record, failure: .networkUnavailable)
        let viewModel = ControllerViewModel(
            connectionActor: connection,
            hostStore: fixture.hostStore,
            cacheStore: fixture.cacheStore,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )

        try await waitUntil {
            viewModel.state.isCachedReadOnly && viewModel.state.connection == .failed(.networkUnavailable)
        }

        XCTAssertEqual(viewModel.state.sessions, [Fixture.session])
        XCTAssertEqual(viewModel.state.cacheUpdatedAt, Date(timeIntervalSince1970: 5))
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
    let failure: ControllerFailure?

    init(record: PairedHostRecord, failure: ControllerFailure? = nil) {
        self.record = record
        self.failure = failure
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
        return record
    }

    func fetchSessions(host: PairedHostRecord) async throws -> ControllerFleetSnapshot {
        if let failure { throw failure }
        return ControllerFleetSnapshot(revision: 1, updateSequence: 1, sessions: [Fixture.session])
    }

    func forgetDeviceSecret(host: PairedHostRecord) async throws {}
    func cancel() async {}
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
