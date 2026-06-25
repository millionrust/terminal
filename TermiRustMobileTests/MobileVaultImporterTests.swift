import XCTest
@preconcurrency import NIOSSH
@testable import TermiRustMobile

final class MobileVaultImporterTests: XCTestCase {
    private let fixtureEd25519PrivateKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACDXdpIxO9R+jxlETproGCGcxOE4SjX6r+jU8UIg2K5ULgAAAJgxZY5/MWWO
    fwAAAAtzc2gtZWQyNTUxOQAAACDXdpIxO9R+jxlETproGCGcxOE4SjX6r+jU8UIg2K5ULg
    AAAECEhzF5gu5ZhIg/P8PEq/33+dXN8wUMwtU7zIlgJLfC2Nd2kjE71H6PGUROmugYIZzE
    4ThKNfqv6NTxQiDYrlQuAAAAD2NsYXdAak1hYy5sb2NhbAECAwQFBg==
    -----END OPENSSH PRIVATE KEY-----
    """

    private let encryptedEnvelopeData = Data("""
    {
      "version": 1,
      "schema_version": 1,
      "cipher": "AES-256-GCM-SIV",
      "kdf": "Argon2id(m=19456,t=3,p=1)",
      "salt": "salt",
      "nonce": "nonce",
      "ciphertext": "ciphertext"
    }
    """.utf8)

    private let plaintextVaultData = Data("""
    {
      "schema_version": 1,
      "export_id": "export-1",
      "created_at_millis": 1,
      "updated_at_millis": 1,
      "source_device_id": "desktop-1",
      "vaults": [],
      "hosts": [{
        "id": "profile-1",
        "label": "Prod",
        "vault_id": null,
        "group": "Ops",
        "tags": ["prod"],
        "host": "prod.example.com",
        "port": 22,
        "username": "ubuntu",
        "auth": {"kind": "private_key", "identity_id": "identity-1", "secret_ref": null},
        "jump_host_id": null,
        "startup_directory": "/srv/app",
        "startup_command": "uptime",
        "start_in_files": false,
        "persistent_session": {"enabled": true, "session_name": "tr-prod", "detach_others": false},
        "terminal_scrollback_rows": 20000,
        "color_tag": null,
        "environment": [],
        "known_host_endpoint": "prod.example.com:22"
      }],
      "groups": [],
      "tags": [],
      "identities": [],
      "known_hosts": [{"endpoint": "prod.example.com:22", "public_key": "ssh-ed25519 AAAA", "algorithm": null, "fingerprint": null}],
      "sync": {"revision": null, "last_synced_at_millis": null},
      "devices": [{
        "device_id": "desktop-1",
        "label": "TermiRust Desktop",
        "platform": "desktop",
        "public_key": null,
        "revoked_at_millis": null
      }]
    }
    """.utf8)

    func testPlaintextVaultDecodesPersistentTmuxHost() throws {
        let vault = try MobileVaultImporter().importPlaintextVaultData(plaintextVaultData)

        XCTAssertEqual(vault.schemaVersion, 1)
        XCTAssertEqual(vault.hosts.first?.persistentSession.sessionName, "tr-prod")
        XCTAssertEqual(vault.knownHosts.first?.endpoint, "prod.example.com:22")
        XCTAssertEqual(vault.devices.first?.deviceId, "desktop-1")
        XCTAssertEqual(vault.devices.first?.platform, "desktop")
    }

    func testEncryptedVaultRequiresSharedCryptoDecryptor() throws {
        XCTAssertThrowsError(
            try MobileVaultImporter().importEncryptedVaultData(encryptedEnvelopeData, passphrase: "hunter2")
        ) { error in
            XCTAssertEqual(error as? MobileVaultImportError, .encryptedVaultRequiresSharedCrypto)
        }
    }

    func testEncryptedVaultUsesInjectedDecryptor() throws {
        let importer = MobileVaultImporter(decryptor: FixtureDecryptor(plaintext: plaintextVaultData))

        let vault = try importer.importEncryptedVaultData(encryptedEnvelopeData, passphrase: "hunter2")

        XCTAssertEqual(vault.hosts.first?.host, "prod.example.com")
        XCTAssertEqual(vault.hosts.first?.persistentSession.sessionName, "tr-prod")
    }

    @MainActor
    func testCredentialSaveUsesExportedSecretReference() throws {
        let host = MobileHost(
            id: "profile-1",
            label: "Prod",
            vaultId: nil,
            group: "Ops",
            tags: [],
            host: "prod.example.com",
            port: 22,
            username: "ubuntu",
            auth: MobileAuthMetadata(kind: .password, identityId: nil, secretRef: "secret-prod-password"),
            jumpHostId: nil,
            startupDirectory: nil,
            startupCommand: nil,
            startInFiles: false,
            persistentSession: MobilePersistentSession(enabled: false, sessionName: nil, detachOthers: false),
            terminalScrollbackRows: nil,
            colorTag: nil,
            environment: [],
            knownHostEndpoint: "prod.example.com:22"
        )
        let store = FixtureSecretStore()
        let viewModel = HostListViewModel(
            vaultImporter: MobileVaultImporter(),
            secretStore: store,
            sshClient: FixtureSSHClient()
        )

        viewModel.saveCredential("super-secret", for: host)

        XCTAssertEqual(store.saved["secret-prod-password"], "super-secret")
        XCTAssertEqual(viewModel.importError, "Credential saved for Prod.")
    }

    func testTmuxBootstrapDoesNotRunStartupCommandOnAttachPath() throws {
        let host = MobileHost(
            id: "profile-1",
            label: "Prod",
            vaultId: nil,
            group: "Ops",
            tags: [],
            host: "prod.example.com",
            port: 22,
            username: "ubuntu",
            auth: MobileAuthMetadata(kind: .privateKey, identityId: nil, secretRef: nil),
            jumpHostId: nil,
            startupDirectory: "/srv/app",
            startupCommand: "uptime",
            startInFiles: false,
            persistentSession: MobilePersistentSession(enabled: true, sessionName: "tr-prod", detachOthers: true),
            terminalScrollbackRows: nil,
            colorTag: nil,
            environment: [],
            knownHostEndpoint: "prod.example.com:22"
        )

        let script = try XCTUnwrap(TmuxBootstrap(host: host).startupCommand())

        XCTAssertTrue(script.contains("tmux has-session -t 'tr-prod'"))
        XCTAssertTrue(script.contains("exec tmux attach-session -d -t 'tr-prod'"))
        XCTAssertTrue(script.contains("exec tmux new-session -s 'tr-prod' -c '/srv/app' -- \"${SHELL:-/bin/sh}\" -lc 'uptime; exec \"${SHELL:-/bin/sh}\" -l'"))
        let attachIndex = try XCTUnwrap(script.range(of: "exec tmux attach-session")?.lowerBound)
        let startupIndex = try XCTUnwrap(script.range(of: "uptime; exec")?.lowerBound)
        XCTAssertLessThan(script.distance(from: script.startIndex, to: attachIndex), script.distance(from: script.startIndex, to: startupIndex))
    }

    func testOpenSSHEd25519PrivateKeyParserExportsExpectedPublicKey() throws {
        let privateKey = try OpenSSHPrivateKeyParser.parse(fixtureEd25519PrivateKey)

        XCTAssertEqual(
            String(openSSHPublicKey: privateKey.publicKey),
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINd2kjE71H6PGUROmugYIZzE4ThKNfqv6NTxQiDYrlQu"
        )
    }

    func testOpenSSHPrivateKeyParserRejectsInvalidPEM() {
        XCTAssertThrowsError(try OpenSSHPrivateKeyParser.parse("not a key")) { error in
            XCTAssertEqual(error as? OpenSSHPrivateKeyParserError, .invalidPEM)
        }
    }

    @MainActor
    func testTerminalBufferHandlesCommonTerminalRedrawSequences() {
        let buffer = TerminalBuffer()

        buffer.append("progress 1\rprogress 2\n\u{1B}[31mred\u{1B}[0m\nabc\u{8}Z")

        XCTAssertEqual(buffer.lines, ["progress 2", "red", "abZ"])
    }

    @MainActor
    func testTerminalBufferClearsScreenOnAnsiClear() {
        let buffer = TerminalBuffer()

        buffer.append("before\n\u{1B}[2J\u{1B}[Hafter")

        XCTAssertEqual(buffer.lines, ["after"])
    }
}

private struct FixtureDecryptor: MobileVaultDecrypting {
    let plaintext: Data

    func decrypt(encryptedVaultData: Data, passphrase: String) throws -> Data {
        XCTAssertFalse(encryptedVaultData.isEmpty)
        XCTAssertEqual(passphrase, "hunter2")
        return plaintext
    }
}

private final class FixtureSecretStore: SecretStoring {
    var saved: [String: String] = [:]

    func saveSecret(_ secret: String, account: String) throws {
        saved[account] = secret
    }

    func readSecret(account: String) throws -> String? {
        saved[account]
    }

    func deleteSecret(account: String) throws {
        saved.removeValue(forKey: account)
    }
}

private final class FixtureSSHClient: MobileSSHConnecting, @unchecked Sendable {
    func connect(
        host: MobileHost,
        knownHost: MobileKnownHost?,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws {}

    func send(_ bytes: Data) async throws {}

    func resize(columns: Int, rows: Int) async throws {}

    func disconnect() async {}
}
