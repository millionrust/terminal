package com.termirust.mobile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.data.MobileVaultExport
import com.termirust.mobile.data.MobileVaultImporter
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
) : ViewModel() {
    private val _vault = MutableStateFlow<MobileVaultExport?>(null)
    val vault: StateFlow<MobileVaultExport?> = _vault

    private val _selectedHost = MutableStateFlow<MobileHost?>(null)
    val selectedHost: StateFlow<MobileHost?> = _selectedHost

    private val _connectionState = MutableStateFlow<TerminalConnectionState>(TerminalConnectionState.Disconnected)
    val connectionState: StateFlow<TerminalConnectionState> = _connectionState

    private val _status = MutableStateFlow<String?>(null)
    val status: StateFlow<String?> = _status

    val terminalBuffer = TerminalBuffer()

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

    fun selectHost(host: MobileHost) {
        _selectedHost.value = host
    }

    fun connectSelectedHost() {
        val host = _selectedHost.value ?: return
        val knownHost = _vault.value?.knownHosts?.firstOrNull { it.endpoint == host.knownHostEndpoint }
        _connectionState.value = TerminalConnectionState.Connecting
        terminalBuffer.clear()
        terminalBuffer.append("Connecting to ${host.username}@${host.host}:${host.port}")

        viewModelScope.launch {
            runCatching { sshClient.connect(host, knownHost) }
                .onSuccess { _connectionState.value = TerminalConnectionState.Connected }
                .onFailure {
                    _connectionState.value = TerminalConnectionState.Failed(it.message ?: "Connection failed.")
                    terminalBuffer.append(it.message ?: "Connection failed.")
                }
        }
    }
}
