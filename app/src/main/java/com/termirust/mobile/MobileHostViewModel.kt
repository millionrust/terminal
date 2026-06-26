package com.termirust.mobile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.termirust.mobile.data.EncryptedVaultStore
import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.data.MobileVaultExport
import com.termirust.mobile.data.MobileVaultImporter
import com.termirust.mobile.security.MobileSecretStore
import com.termirust.mobile.ssh.DirectSshSessionClient
import com.termirust.mobile.ssh.MobileSshSessionClient
import com.termirust.mobile.ssh.TerminalConnectionState
import com.termirust.mobile.terminal.TerminalBuffer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class MobileHostViewModel(
    private val importer: MobileVaultImporter = MobileVaultImporter(),
    private val sshClient: MobileSshSessionClient = DirectSshSessionClient(),
    private val secretStore: MobileSecretStore? = null,
    private val encryptedVaultStore: EncryptedVaultStore? = null,
) : ViewModel() {
    private val _vault = MutableStateFlow<MobileVaultExport?>(null)
    val vault: StateFlow<MobileVaultExport?> = _vault

    private val _selectedHost = MutableStateFlow<MobileHost?>(null)
    val selectedHost: StateFlow<MobileHost?> = _selectedHost

    private val _connectionState = MutableStateFlow<TerminalConnectionState>(TerminalConnectionState.Disconnected)
    val connectionState: StateFlow<TerminalConnectionState> = _connectionState

    private val _status = MutableStateFlow<String?>(null)
    val status: StateFlow<String?> = _status

    private val _hasStoredEncryptedVault = MutableStateFlow(encryptedVaultStore?.hasEncryptedVault() == true)
    val hasStoredEncryptedVault: StateFlow<Boolean> = _hasStoredEncryptedVault

    val terminalBuffer = TerminalBuffer()

    fun reportStatus(message: String) {
        _status.value = message
    }

    fun importPlaintextFixture(bytes: ByteArray) {
        runCatching { importer.importPlaintextFixture(bytes) }
            .onSuccess {
                _vault.value = it
                _selectedHost.value = it.hosts.firstOrNull()
                _status.value = null
            }
            .onFailure { _status.value = it.message }
    }

    fun inspectEncryptedVault(bytes: ByteArray) {
        runCatching { importer.inspectEncryptedEnvelope(bytes) }
            .onSuccess { _status.value = "Encrypted vault recognized. Shared TermiRust vault crypto is required before production import." }
            .onFailure { _status.value = it.message }
    }

    fun importEncryptedVault(bytes: ByteArray, passphrase: CharArray) {
        runCatching { importer.importEncryptedVault(bytes, passphrase) }
            .onSuccess {
                encryptedVaultStore?.saveEncryptedVault(bytes)
                _hasStoredEncryptedVault.value = encryptedVaultStore?.hasEncryptedVault() == true
                _vault.value = it
                _selectedHost.value = it.hosts.firstOrNull()
                _status.value = null
            }
            .onFailure { _status.value = it.message }
    }

    fun unlockStoredEncryptedVault(passphrase: CharArray) {
        val bytes = encryptedVaultStore?.readEncryptedVault()
        if (bytes == null) {
            passphrase.fill('\u0000')
            _hasStoredEncryptedVault.value = false
            _status.value = "No stored encrypted vault is available."
            return
        }
        importEncryptedVault(bytes, passphrase)
    }

    fun forgetStoredEncryptedVault() {
        encryptedVaultStore?.clearEncryptedVault()
        _hasStoredEncryptedVault.value = false
        _vault.value = null
        _selectedHost.value = null
        _status.value = "Stored encrypted vault removed."
    }

    fun selectHost(host: MobileHost) {
        _selectedHost.value = host
    }

    fun saveCredentialForSelectedHost(secret: String) {
        val host = _selectedHost.value ?: return
        val reference = host.auth.secretRef
        if (reference.isNullOrBlank()) {
            _status.value = "This host does not declare a mobile secret reference."
            return
        }
        if (secret.isBlank()) {
            _status.value = "Enter the SSH credential before saving."
            return
        }
        val store = secretStore
        if (store == null) {
            _status.value = "Secure credential storage is unavailable in this build."
            return
        }

        runCatching { store.saveSecret(reference, secret) }
            .onSuccess { _status.value = "Credential saved for ${host.label}." }
            .onFailure { _status.value = it.message }
    }

    fun deleteCredentialForSelectedHost() {
        val host = _selectedHost.value ?: return
        val reference = host.auth.secretRef
        if (reference.isNullOrBlank()) {
            _status.value = "This host does not declare a mobile secret reference."
            return
        }
        val store = secretStore
        if (store == null) {
            _status.value = "Secure credential storage is unavailable in this build."
            return
        }

        runCatching { store.deleteSecret(reference) }
            .onSuccess { _status.value = "Credential removed for ${host.label}." }
            .onFailure { _status.value = it.message }
    }

    fun connectSelectedHost() {
        val host = _selectedHost.value ?: return
        val knownHost = _vault.value?.knownHosts?.firstOrNull { it.endpoint == host.knownHostEndpoint }
        _connectionState.value = TerminalConnectionState.Connecting
        terminalBuffer.clear()
        terminalBuffer.append("Connecting to ${host.username}@${host.host}:${host.port}")

        viewModelScope.launch {
            runCatching {
                sshClient.connect(host, knownHost) { bytes ->
                    terminalBuffer.append(bytes)
                }
            }
                .onSuccess { _connectionState.value = TerminalConnectionState.Connected }
                .onFailure {
                    _connectionState.value = TerminalConnectionState.Failed(it.message ?: "Connection failed.")
                    terminalBuffer.append(it.message ?: "Connection failed.")
                }
        }
    }

    fun sendTerminalInput(input: String) {
        viewModelScope.launch {
            runCatching { sshClient.send("$input\n".encodeToByteArray()) }
                .onFailure { terminalBuffer.append(it.message ?: "Unable to send input.") }
        }
    }

    fun sendTerminalBytes(bytes: ByteArray) {
        viewModelScope.launch {
            runCatching { sshClient.send(bytes) }
                .onFailure { terminalBuffer.append(it.message ?: "Unable to send input.") }
        }
    }

    fun resizeTerminal(columns: Int, rows: Int) {
        terminalBuffer.resize(columns, rows)
        viewModelScope.launch {
            runCatching { sshClient.resize(columns, rows) }
                .onFailure { terminalBuffer.append(it.message ?: "Unable to resize terminal.") }
        }
    }

    fun disconnect() {
        viewModelScope.launch {
            sshClient.disconnect()
            _connectionState.value = TerminalConnectionState.Disconnected
        }
    }
}
