package com.termirust.mobile.ssh

import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.data.MobileKnownHost

sealed interface TerminalConnectionState {
    data object Disconnected : TerminalConnectionState
    data object Connecting : TerminalConnectionState
    data object Connected : TerminalConnectionState
    data class Failed(val message: String) : TerminalConnectionState
}

interface MobileSshSessionClient {
    suspend fun connect(host: MobileHost, knownHost: MobileKnownHost?)
    suspend fun send(bytes: ByteArray)
    suspend fun resize(columns: Int, rows: Int)
    suspend fun disconnect()
}

class DirectSshSessionClient : MobileSshSessionClient {
    override suspend fun connect(host: MobileHost, knownHost: MobileKnownHost?) {
        requireNotNull(knownHost) { "No known-host pin exists for ${host.knownHostEndpoint ?: host.host}." }
        TmuxBootstrap(host).startupCommand()
        error("Direct SSHJ transport is scaffolded but not wired yet.")
    }

    override suspend fun send(bytes: ByteArray) {
        error("Direct SSHJ transport is scaffolded but not wired yet.")
    }

    override suspend fun resize(columns: Int, rows: Int) {
        error("Direct SSHJ transport is scaffolded but not wired yet.")
    }

    override suspend fun disconnect() = Unit
}
