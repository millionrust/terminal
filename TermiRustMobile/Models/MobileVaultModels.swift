import Foundation

let mobileVaultSchemaVersion = 1

struct EncryptedMobileVaultEnvelope: Decodable, Equatable {
    let version: Int
    let schemaVersion: Int
    let cipher: String
    let kdf: String
    let salt: String
    let nonce: String
    let ciphertext: String

    enum CodingKeys: String, CodingKey {
        case version
        case schemaVersion = "schema_version"
        case cipher
        case kdf
        case salt
        case nonce
        case ciphertext
    }
}

struct MobileVaultExport: Codable, Hashable {
    let schemaVersion: Int
    let exportId: String
    let createdAtMillis: UInt64
    let updatedAtMillis: UInt64
    let sourceDeviceId: String
    let vaults: [MobileVault]
    let hosts: [MobileHost]
    let groups: [MobileGroup]
    let tags: [String]
    let identities: [MobileIdentityMetadata]
    let knownHosts: [MobileKnownHost]
    let sync: MobileSyncMetadata
    let devices: [MobileDeviceRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportId = "export_id"
        case createdAtMillis = "created_at_millis"
        case updatedAtMillis = "updated_at_millis"
        case sourceDeviceId = "source_device_id"
        case vaults
        case hosts
        case groups
        case tags
        case identities
        case knownHosts = "known_hosts"
        case sync
        case devices
    }
}

struct MobileVault: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let description: String
    let kind: String
}

struct MobileHost: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let vaultId: String?
    let group: String
    let tags: [String]
    let host: String
    let port: UInt16
    let username: String
    let auth: MobileAuthMetadata
    let jumpHostId: String?
    let startupDirectory: String?
    let startupCommand: String?
    let startInFiles: Bool
    let persistentSession: MobilePersistentSession
    let terminalScrollbackRows: UInt32?
    let colorTag: String?
    let environment: [MobileEnvironmentVariable]
    let knownHostEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case vaultId = "vault_id"
        case group
        case tags
        case host
        case port
        case username
        case auth
        case jumpHostId = "jump_host_id"
        case startupDirectory = "startup_directory"
        case startupCommand = "startup_command"
        case startInFiles = "start_in_files"
        case persistentSession = "persistent_session"
        case terminalScrollbackRows = "terminal_scrollback_rows"
        case colorTag = "color_tag"
        case environment
        case knownHostEndpoint = "known_host_endpoint"
    }
}

struct MobileAuthMetadata: Codable, Hashable {
    let kind: MobileAuthKind
    let identityId: String?
    let secretRef: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case identityId = "identity_id"
        case secretRef = "secret_ref"
    }
}

enum MobileAuthKind: String, Codable, Hashable {
    case password
    case privateKey = "private_key"
}

struct MobilePersistentSession: Codable, Hashable {
    let enabled: Bool
    let sessionName: String?
    let detachOthers: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case sessionName = "session_name"
        case detachOthers = "detach_others"
    }
}

struct MobileEnvironmentVariable: Codable, Hashable {
    let name: String
    let value: String
}

struct MobileIdentityMetadata: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let vaultId: String?
    let kind: String
    let publicKey: String?
    let fingerprint: String?
    let secretRef: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case vaultId = "vault_id"
        case kind
        case publicKey = "public_key"
        case fingerprint
        case secretRef = "secret_ref"
    }
}

struct MobileKnownHost: Codable, Hashable, Identifiable {
    var id: String { endpoint }

    let endpoint: String
    let publicKey: String
    let algorithm: String?
    let fingerprint: String?

    enum CodingKeys: String, CodingKey {
        case endpoint
        case publicKey = "public_key"
        case algorithm
        case fingerprint
    }
}

struct MobileGroup: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct MobileSyncMetadata: Codable, Hashable {
    let revision: UInt64?
    let lastSyncedAtMillis: UInt64?

    enum CodingKeys: String, CodingKey {
        case revision
        case lastSyncedAtMillis = "last_synced_at_millis"
    }
}

struct MobileDeviceRecord: Codable, Hashable, Identifiable {
    var id: String { deviceId }

    let deviceId: String
    let label: String
    let platform: String?
    let publicKey: String?
    let revokedAtMillis: UInt64?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case label
        case platform
        case publicKey = "public_key"
        case revokedAtMillis = "revoked_at_millis"
    }
}
