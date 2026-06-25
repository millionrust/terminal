package com.termirust.mobile

import com.termirust.mobile.data.MobileAuthKind
import com.termirust.mobile.data.MobileAuthMetadata
import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.data.MobilePersistentSession
import com.termirust.mobile.data.MobileVaultImporter
import com.termirust.mobile.ssh.TmuxBootstrap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MobileVaultImporterTest {
    @Test
    fun plaintextVaultDecodesPersistentTmuxHost() {
        val json = """
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
        """.trimIndent()

        val vault = MobileVaultImporter().importPlaintextFixture(json.encodeToByteArray())

        assertEquals(1, vault.schemaVersion)
        assertEquals("tr-prod", vault.hosts.first().persistentSession.sessionName)
        assertEquals("prod.example.com:22", vault.knownHosts.first().endpoint)
    }

    @Test
    fun tmuxBootstrapDoesNotRunStartupCommandOnAttachPath() {
        val host = MobileHost(
            id = "profile-1",
            label = "Prod",
            host = "prod.example.com",
            port = 22,
            username = "ubuntu",
            auth = MobileAuthMetadata(kind = MobileAuthKind.PrivateKey),
            startupDirectory = "/srv/app",
            startupCommand = "uptime",
            persistentSession = MobilePersistentSession(
                enabled = true,
                sessionName = "tr-prod",
                detachOthers = true,
            ),
            knownHostEndpoint = "prod.example.com:22",
        )

        val script = TmuxBootstrap(host).startupCommand().orEmpty()

        assertTrue(script.contains("tmux has-session -t 'tr-prod'"))
        assertTrue(script.contains("exec tmux attach-session -d -t 'tr-prod'"))
        assertTrue(script.contains("exec tmux new-session -s 'tr-prod' -c '/srv/app' 'uptime'"))
        assertTrue(script.indexOf("exec tmux attach-session") < script.indexOf("'uptime'"))
    }
}
