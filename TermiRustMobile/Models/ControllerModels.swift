import Foundation

struct HostRoute: Codable, Hashable, Sendable {
    let address: String
    let port: UInt16

    init(address: String, port: UInt16) throws {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 255, port > 0 else {
            throw ControllerModelError.invalidRoute
        }
        self.address = trimmed
        self.port = port
    }
}

struct PairedHostRecord: Codable, Identifiable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let displayName: String
    let route: HostRoute
    let hostStaticPublicKey: Data
    let deviceStaticKeyId: String
    let deviceId: UUID
    let identityGeneration: UInt64
    let revocationEpoch: UInt64
    let sessionGeneration: UInt64
    let capabilityBits: UInt16
    let pairedAt: Date

    init(
        id: String,
        displayName: String,
        route: HostRoute,
        hostStaticPublicKey: Data,
        deviceStaticKeyId: String,
        deviceId: UUID,
        identityGeneration: UInt64,
        revocationEpoch: UInt64,
        sessionGeneration: UInt64,
        capabilityBits: UInt16,
        pairedAt: Date = .now
    ) throws {
        guard hostStaticPublicKey.count == 32,
              identityGeneration > 0,
              !deviceStaticKeyId.isEmpty,
              deviceStaticKeyId.utf8.count <= 128,
              !displayName.isEmpty,
              displayName.unicodeScalars.count <= 256 else {
            throw ControllerModelError.invalidHost
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.displayName = displayName
        self.route = route
        self.hostStaticPublicKey = hostStaticPublicKey
        self.deviceStaticKeyId = deviceStaticKeyId
        self.deviceId = deviceId
        self.identityGeneration = identityGeneration
        self.revocationEpoch = revocationEpoch
        self.sessionGeneration = sessionGeneration
        self.capabilityBits = capabilityBits
        self.pairedAt = pairedAt
    }

    var fingerprint: String {
        hostStaticPublicKey.map { String(format: "%02x", $0) }.joined()
    }
}

struct HostSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let route: HostRoute
    let fingerprint: String
    let capabilityBits: UInt16
}

struct ControllerSessionSummary: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let project: String?
    let group: String?
    let lifecycle: String
    let occupantGeneration: UInt64?
    let lastOutputSequence: UInt64
    let hasWriter: Bool
    let unreadCount: UInt32

    func validate() throws {
        guard !title.isEmpty,
              title.unicodeScalars.count <= ControllerCacheLimits.maxTitleScalars,
              lifecycle.utf8.count <= 64,
              project?.unicodeScalars.count ?? 0 <= ControllerCacheLimits.maxTitleScalars,
              group?.unicodeScalars.count ?? 0 <= ControllerCacheLimits.maxTitleScalars else {
            throw ControllerModelError.invalidSession
        }
    }
}

struct SessionSummaryPage: Codable, Equatable, Sendable {
    let revision: UInt64
    let updateSequence: UInt64
    let sessions: [ControllerSessionSummary]
    let nextCursor: String?

    func validate(encodedBy encoder: JSONEncoder = JSONEncoder()) throws {
        guard revision > 0,
              updateSequence > 0,
              sessions.count <= ControllerCacheLimits.maxPageRecords,
              nextCursor?.utf8.count ?? 0 <= 256 else {
            throw ControllerModelError.resourceLimit
        }
        try sessions.forEach { try $0.validate() }
        guard try encoder.encode(self).count <= ControllerCacheLimits.maxPageBytes else {
            throw ControllerModelError.resourceLimit
        }
    }
}

struct ControllerFleetSnapshot: Equatable, Sendable {
    let revision: UInt64
    let updateSequence: UInt64
    let sessions: [ControllerSessionSummary]
}

enum ControllerConnectionState: Equatable, Sendable {
    case unpaired
    case pairing
    case sasReady(String)
    case pairedOffline
    case connecting
    case authenticating
    case syncing
    case readyReadOnly
    case revoked
    case incompatible
    case failed(ControllerFailure)
}

enum ControllerFailure: String, Codable, Error, Sendable {
    case cancelled
    case invalidOffer
    case offerExpired
    case sasMismatch
    case networkUnavailable
    case timedOut
    case authenticationFailed
    case keychainUnavailable
    case malformedResponse
    case sequenceGap
    case resourceLimit
    case storageUnavailable
    case pairingUncertain
}

struct ControllerViewState: Equatable, Sendable {
    let hosts: [HostSummary]
    let selectedHostID: String?
    let sessions: [ControllerSessionSummary]
    let connection: ControllerConnectionState
    let cacheUpdatedAt: Date?
    let isCachedReadOnly: Bool

    static let empty = Self(
        hosts: [],
        selectedHostID: nil,
        sessions: [],
        connection: .unpaired,
        cacheUpdatedAt: nil,
        isCachedReadOnly: false
    )
}

enum ControllerModelError: Error, Equatable {
    case invalidRoute
    case invalidHost
    case invalidSession
    case resourceLimit
}

enum ControllerCacheLimits {
    static let maxHosts = 16
    static let maxSessionsPerHost = 5_000
    static let maxSessionsGlobal = 10_000
    static let maxEncodedBytes = 8 * 1_024 * 1_024
    static let maxPageRecords = 1_000
    static let maxPageBytes = 1 * 1_024 * 1_024
    static let maxTitleScalars = 256
}
