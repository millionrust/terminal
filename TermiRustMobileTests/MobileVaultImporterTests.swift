import XCTest
@testable import TermiRustMobile

final class MobileVaultImporterTests: XCTestCase {
    func testPlaintextVaultDecodesPersistentTmuxHost() throws {
        let data = Data("""
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
          "devices": []
        }
        """.utf8)

        let vault = try MobileVaultImporter().importPlaintextVaultData(data)

        XCTAssertEqual(vault.schemaVersion, 1)
        XCTAssertEqual(vault.hosts.first?.persistentSession.sessionName, "tr-prod")
        XCTAssertEqual(vault.knownHosts.first?.endpoint, "prod.example.com:22")
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
        XCTAssertTrue(script.contains("exec tmux new-session -s 'tr-prod' -c '/srv/app' 'uptime'"))
        let attachIndex = try XCTUnwrap(script.range(of: "exec tmux attach-session")?.lowerBound)
        let startupIndex = try XCTUnwrap(script.range(of: "'uptime'")?.lowerBound)
        XCTAssertLessThan(script.distance(from: script.startIndex, to: attachIndex), script.distance(from: script.startIndex, to: startupIndex))
    }
}
