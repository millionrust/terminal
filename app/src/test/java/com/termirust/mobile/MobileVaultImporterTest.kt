package com.termirust.mobile

import com.termirust.mobile.data.MobileAuthKind
import com.termirust.mobile.data.MobileAuthMetadata
import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.data.MobilePersistentSession
import com.termirust.mobile.data.MobileVaultDecryptor
import com.termirust.mobile.data.MobileVaultImporter
import com.termirust.mobile.security.MobileSecretStore
import com.termirust.mobile.ssh.TmuxBootstrap
import com.termirust.mobile.terminal.TerminalBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MobileVaultImporterTest {
    private val encryptedEnvelope = """
        {
          "version": 1,
          "schema_version": 1,
          "cipher": "AES-256-GCM-SIV",
          "kdf": "Argon2id(m=19456,t=3,p=1)",
          "salt": "salt",
          "nonce": "nonce",
          "ciphertext": "ciphertext"
        }
    """.trimIndent().encodeToByteArray()

    private val plaintextVault = """
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
    """.trimIndent().encodeToByteArray()

    @Test
    fun plaintextVaultDecodesPersistentTmuxHost() {
        val vault = MobileVaultImporter().importPlaintextFixture(plaintextVault)

        assertEquals(1, vault.schemaVersion)
        assertEquals("tr-prod", vault.hosts.first().persistentSession.sessionName)
        assertEquals("prod.example.com:22", vault.knownHosts.first().endpoint)
        assertEquals("desktop-1", vault.devices.first().deviceId)
        assertEquals("desktop", vault.devices.first().platform)
    }

    @Test
    fun encryptedVaultRequiresSharedCryptoDecryptor() {
        val error = kotlin.runCatching {
            MobileVaultImporter().importEncryptedVault(encryptedEnvelope, "hunter2".toCharArray())
        }.exceptionOrNull()

        assertEquals("Encrypted production import requires the shared TermiRust vault crypto module.", error?.message)
    }

    @Test
    fun encryptedVaultUsesInjectedDecryptorAndClearsPassphrase() {
        val passphrase = "hunter2".toCharArray()
        val importer = MobileVaultImporter(decryptor = FixtureDecryptor(plaintextVault))

        val vault = importer.importEncryptedVault(encryptedEnvelope, passphrase)

        assertEquals("prod.example.com", vault.hosts.first().host)
        assertEquals("tr-prod", vault.hosts.first().persistentSession.sessionName)
        assertTrue(passphrase.all { it == '\u0000' })
    }

    @Test
    fun credentialSaveUsesExportedSecretReference() {
        val host = MobileHost(
            id = "profile-1",
            label = "Prod",
            host = "prod.example.com",
            port = 22,
            username = "ubuntu",
            auth = MobileAuthMetadata(
                kind = MobileAuthKind.Password,
                secretRef = "secret-prod-password",
            ),
            knownHostEndpoint = "prod.example.com:22",
        )
        val store = FakeSecretStore()
        val viewModel = MobileHostViewModel(secretStore = store)

        viewModel.selectHost(host)
        viewModel.saveCredentialForSelectedHost("super-secret")

        assertEquals("super-secret", store.saved["secret-prod-password"])
        assertEquals("Credential saved for Prod.", viewModel.status.value)
    }

    @Test
    fun privateKeyCredentialSaveUsesExportedSecretReference() {
        val host = MobileHost(
            id = "profile-1",
            label = "Prod",
            host = "prod.example.com",
            port = 22,
            username = "ubuntu",
            auth = MobileAuthMetadata(
                kind = MobileAuthKind.PrivateKey,
                secretRef = "secret-prod-key",
            ),
            knownHostEndpoint = "prod.example.com:22",
        )
        val privateKey = """
            -----BEGIN OPENSSH PRIVATE KEY-----
            key-body
            -----END OPENSSH PRIVATE KEY-----
        """.trimIndent()
        val store = FakeSecretStore()
        val viewModel = MobileHostViewModel(secretStore = store)

        viewModel.selectHost(host)
        viewModel.saveCredentialForSelectedHost(privateKey)

        assertEquals(privateKey, store.saved["secret-prod-key"])
        assertEquals("Credential saved for Prod.", viewModel.status.value)
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
        assertTrue(script.contains("exec tmux new-session -s 'tr-prod' -c '/srv/app' -- \"\${SHELL:-/bin/sh}\" -lc 'uptime; exec \"\${SHELL:-/bin/sh}\" -l'"))
        assertTrue(script.indexOf("exec tmux attach-session") < script.indexOf("uptime; exec"))
    }

    @Test
    fun terminalBufferHandlesCommonTerminalRedrawSequences() {
        val buffer = TerminalBuffer()

        buffer.append("progress 1\rprogress 2\n\u001B[31mred\u001B[0m\nabc\bZ")

        assertEquals(listOf("progress 2", "red", "abZ"), buffer.lines.value)
    }

    @Test
    fun terminalBufferClearsScreenOnAnsiClear() {
        val buffer = TerminalBuffer()

        buffer.append("before\n\u001B[2J\u001B[Hafter")

        assertEquals(listOf("after"), buffer.lines.value)
    }
}

private class FixtureDecryptor(
    private val plaintext: ByteArray,
) : MobileVaultDecryptor {
    override fun decrypt(encryptedVault: ByteArray, passphrase: CharArray): ByteArray {
        assertTrue(encryptedVault.isNotEmpty())
        assertEquals("hunter2", passphrase.concatToString())
        return plaintext
    }
}

private class FakeSecretStore : MobileSecretStore {
    val saved = mutableMapOf<String, String>()

    override fun saveSecret(account: String, secret: String) {
        saved[account] = secret
    }

    override fun readSecret(account: String): String? = saved[account]

    override fun deleteSecret(account: String) {
        saved.remove(account)
    }
}
