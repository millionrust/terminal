package com.termirust.mobile.controller

import android.app.Application
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.SocketException
import java.net.SocketTimeoutException
import java.security.SecureRandom
import java.util.UUID
import kotlin.math.min

class ControllerViewModel(application: Application) : AndroidViewModel(application) {
    private val hostStore = PairedHostStore(application)
    private val cacheStore = ControllerFleetCacheStore(application)
    private val secureBlobs = ControllerSecureBlobStore(application)
    private val connection = ControllerConnection(secureBlobs)
    private val random = SecureRandom()
    private val deviceId = loadDeviceId(application)
    private val _state = MutableStateFlow(ControllerUiState())
    val state: StateFlow<ControllerUiState> = _state.asStateFlow()
    val pairingOffer = MutableStateFlow("")
    val pairingHostName = MutableStateFlow("My Computer")
    val pairingDeviceName = MutableStateFlow("Android ${Build.MODEL}".take(64))
    private var hosts: List<PairedHostRecord> = emptyList()
    private var cache = ControllerCacheDocument()
    private var operation: Job? = null
    private var terminalRender: Job? = null
    private var terminalResize: Job? = null
    private var terminalRuntime: ActiveTerminalRuntime? = null

    init {
        operation = viewModelScope.launch { restore() }
    }

    fun beginPairing() {
        operation?.cancel()
        _state.value = _state.value.copy(connection = ControllerConnectionState.Pairing)
        operation = viewModelScope.launch {
            runCatching {
                connection.beginPairing(
                    offerText = pairingOffer.value,
                    hostName = pairingHostName.value.trim(),
                    deviceName = pairingDeviceName.value.trim(),
                    deviceId = deviceId,
                )
            }.onSuccess { challenge ->
                _state.value = _state.value.copy(
                    connection = ControllerConnectionState.SasReady(
                        challenge.sas,
                        challenge.fingerprintSuffix,
                    ),
                )
            }.onFailure(::showFailure)
        }
    }

    fun finishPairing(matches: Boolean) {
        operation?.cancel()
        _state.value = _state.value.copy(connection = ControllerConnectionState.Pairing)
        operation = viewModelScope.launch {
            runCatching { connection.finishPairing(matches) }
                .onSuccess { host ->
                    hosts = hostStore.upsert(host)
                    pairingOffer.value = ""
                    _state.value = makeState(
                        selectedHostId = host.id,
                        connectionState = ControllerConnectionState.PairedOffline,
                    )
                    refreshSelected(retry = true)
                }
                .onFailure(::showFailure)
        }
    }

    fun cancelPairing() {
        operation?.cancel()
        operation = viewModelScope.launch { connection.cancel() }
        _state.value = makeState(
            selectedHostId = _state.value.selectedHostId,
            connectionState = if (hosts.isEmpty()) {
                ControllerConnectionState.Unpaired
            } else {
                ControllerConnectionState.PairedOffline
            },
        )
    }

    fun selectHost(hostId: String) {
        if (hosts.none { it.id == hostId }) return
        operation?.cancel()
        _state.value = makeState(hostId, ControllerConnectionState.PairedOffline)
        operation = viewModelScope.launch { refreshSelected(retry = true) }
    }

    fun retry() {
        operation?.cancel()
        operation = viewModelScope.launch { refreshSelected(retry = true) }
    }

    fun onForeground() {
        val terminal = terminalRuntime
        operation?.cancel()
        operation = if (terminal != null) {
            viewModelScope.launch {
                connection.cancel()
                terminal.writer.setForeground(true)
                runTerminal(terminal)
            }
        } else {
            viewModelScope.launch { refreshSelected(retry = true) }
        }
    }

    fun onBackground() {
        operation?.cancel()
        terminalRuntime?.let { runtime ->
            val held = runtime.writer.lease == WriterLeaseState.Held
            runtime.writer.setForeground(false)
            runtime.reducer.markOffline()
            publishTerminal(runtime, privacyCovered = true)
            operation = viewModelScope.launch {
                releaseWriterForLifecycle(runtime, held)
                connection.cancel()
            }
            return
        }
        operation = viewModelScope.launch { connection.cancel() }
        val selected = _state.value.selectedHostId
        _state.value = makeState(selected, ControllerConnectionState.PairedOffline)
    }

    fun attachSession(sessionId: String) {
        val host = selectedHost() ?: return
        val session = _state.value.sessions.firstOrNull { it.id == sessionId } ?: return
        val generation = session.occupantGeneration ?: return
        val identity = ReadOnlyAttachIdentity(
            host.id,
            UUID.fromString(session.id),
            generation,
            session.hostInstanceId?.let(UUID::fromString),
        )
        val viewport = TerminalViewport(120, 40)
        val runtime = ActiveTerminalRuntime(
            host = host,
            session = session,
            reducer = ReadOnlyAttachReducer(identity),
            writer = WriterControlReducer(identity),
            terminal = BoundedControllerTerminal(viewport),
            queue = BoundedTerminalFrameQueue(),
            viewport = viewport,
        )
        operation?.cancel()
        terminalRuntime = runtime
        publishTerminal(runtime)
        operation = viewModelScope.launch {
            connection.cancel()
            runTerminal(runtime)
        }
    }

    fun retryTerminal() {
        val runtime = terminalRuntime ?: return
        if (operation?.isActive == true) return
        operation = viewModelScope.launch {
            connection.cancel()
            runTerminal(runtime)
        }
    }

    fun requestTerminalControl() {
        val runtime = terminalRuntime ?: return
        if (!runtime.supportsWriter || !runtime.writer.isForeground) return
        runtime.acquireAfterAttach = true
        if (runtime.interactive && runtime.reducer.state == ReadOnlyAttachState.Live) {
            runtime.acquireAfterAttach = false
            issueAcquire(runtime)
            return
        }
        runtime.interactive = true
        operation?.cancel()
        operation = viewModelScope.launch {
            connection.cancel()
            runTerminal(runtime)
        }
    }

    fun releaseTerminalControl() {
        val runtime = terminalRuntime ?: return
        if (runtime.writer.lease != WriterLeaseState.Held) return
        val commandId = UUID.randomUUID()
        runtime.pendingMutations[commandId] = TerminalMutation.RELEASE
        runtime.writer.releaseLocally()
        publishTerminal(runtime)
        viewModelScope.launch {
            runCatching { connection.releaseWriter(runtime.host, runtime.writer.identity, commandId) }
                .onFailure { mutationSendFailed(runtime, commandId) }
        }
    }

    fun sendTerminalBytes(bytes: ByteArray) = enqueueTerminalInput(bytes, PendingInputKind.KEYBOARD, true)

    fun requestTerminalPaste(text: String) {
        val runtime = terminalRuntime ?: return
        val bytes = text.encodeToByteArray()
        if (bytes.isEmpty()) return
        if (bytes.size > WriterControlReducer.MAX_QUEUED_BYTES) {
            runtime.writerMessage = "paste_too_large"
            publishTerminal(runtime)
        } else if (runtime.writer.pasteRequiresConfirmation(bytes)) {
            runtime.pendingPaste = bytes
            publishTerminal(runtime)
        } else {
            enqueueTerminalInput(bytes, PendingInputKind.PASTE, true)
        }
    }

    fun confirmTerminalPaste() {
        val runtime = terminalRuntime ?: return
        val bytes = runtime.pendingPaste ?: return
        runtime.pendingPaste = null
        enqueueTerminalInput(bytes, PendingInputKind.PASTE, true)
    }

    fun cancelTerminalPaste() {
        val runtime = terminalRuntime ?: return
        runtime.pendingPaste = null
        publishTerminal(runtime)
    }

    fun detachTerminal() {
        val runtime = terminalRuntime
        val held = runtime?.writer?.lease == WriterLeaseState.Held
        operation?.cancel()
        terminalRender?.cancel()
        terminalResize?.cancel()
        terminalRender = null
        operation = viewModelScope.launch {
            if (runtime != null) releaseWriterForLifecycle(runtime, held)
            connection.cancel()
            refreshSelected(retry = false)
        }
        runtime?.writer?.releaseLocally()
        runtime?.reducer?.detach()
        terminalRuntime = null
        _state.value = _state.value.copy(activeTerminal = null)
    }

    fun updateTerminalViewport(columns: Int, rows: Int) {
        val runtime = terminalRuntime ?: return
        val viewport = TerminalViewport(columns, rows)
        if (runCatching { TerminalLimits().validate(viewport) }.isFailure) return
        if (runtime.viewport == viewport) return
        runtime.viewport = viewport
        runtime.terminal.resize(viewport)
        if (runtime.supportsResize && runtime.writer.lease == WriterLeaseState.Held) {
            runtime.pendingResize = viewport
            terminalResize?.cancel()
            terminalResize = viewModelScope.launch {
                delay(50)
                sendPendingResize(runtime)
            }
        }
        publishTerminal(runtime)
    }

    fun forgetSelectedHost() {
        val host = selectedHost() ?: return
        operation?.cancel()
        operation = viewModelScope.launch {
            connection.cancel()
            runCatching { secureBlobs.delete(host.deviceStaticKeyId) }
            hosts = hostStore.remove(host.id)
            cache = cacheStore.remove(cache, host.id)
            _state.value = makeState(
                selectedHostId = hosts.firstOrNull()?.id,
                connectionState = if (hosts.isEmpty()) {
                    ControllerConnectionState.Unpaired
                } else {
                    ControllerConnectionState.PairedOffline
                },
            )
        }
    }

    override fun onCleared() {
        operation?.cancel()
        terminalRender?.cancel()
        terminalResize?.cancel()
        connection.close()
        super.onCleared()
    }

    private suspend fun restore() {
        hosts = hostStore.load()
        cache = cacheStore.load()
        val selected = hosts.firstOrNull()?.id
        _state.value = makeState(
            selectedHostId = selected,
            connectionState = if (selected == null) {
                ControllerConnectionState.Unpaired
            } else {
                ControllerConnectionState.PairedOffline
            },
        )
        if (selected != null) refreshSelected(retry = true)
    }

    private suspend fun refreshSelected(retry: Boolean) {
        val host = selectedHost() ?: return
        val started = System.currentTimeMillis()
        var attempt = 0
        while (true) {
            try {
                val snapshot = connection.fetchSessions(host) { state ->
                    _state.value = makeState(host.id, state)
                }
                cache = cacheStore.saveSnapshot(
                    current = cache,
                    selectedHostId = host.id,
                    host = host,
                    snapshot = snapshot,
                    nowMillis = System.currentTimeMillis(),
                )
                _state.value = makeState(host.id, ControllerConnectionState.ReadyReadOnly)
                return
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (!retry || !isRetryable(error) || attempt >= 7 ||
                    System.currentTimeMillis() - started >= 90_000
                ) {
                    _state.value = makeState(
                        host.id,
                        ControllerConnectionState.Failed(classify(error)),
                    )
                    return
                }
                val cap = min(10_000L, 250L shl attempt)
                delay(Math.floorMod(random.nextLong(), cap + 1))
                attempt += 1
            }
        }
    }

    private fun makeState(
        selectedHostId: String?,
        connectionState: ControllerConnectionState,
    ): ControllerUiState {
        val cached = selectedHostId?.let(cache.hosts::get)
        val online = connectionState == ControllerConnectionState.ReadyReadOnly
        return ControllerUiState(
            hosts = hosts,
            selectedHostId = selectedHostId,
            sessions = cached?.snapshot?.sessions.orEmpty(),
            connection = connectionState,
            cachedAtMillis = cached?.updatedAtMillis,
            cachedReadOnly = cached != null && !online,
            activeTerminal = _state.value.activeTerminal,
        )
    }

    private suspend fun runTerminal(runtime: ActiveTerminalRuntime) {
        if (terminalRuntime !== runtime) return
        if (runtime.reducer.state != ReadOnlyAttachState.Detached &&
            runtime.reducer.state != ReadOnlyAttachState.Offline
        ) runtime.reducer.markOffline()
        try {
            runtime.reducer.beginAuthentication()
            publishTerminal(runtime)
            val consume: suspend (ReadOnlyWireEvent) -> Unit = { event ->
                if (terminalRuntime !== runtime) throw CancellationException()
                withContext(Dispatchers.Main.immediate) {
                    if (terminalRuntime !== runtime) throw CancellationException()
                    consumeTerminalEvent(runtime, event)
                }
            }
            if (runtime.interactive) {
                connection.attachInteractive(runtime.host, runtime.reducer.cursor, runtime.viewport, consume)
            } else {
                connection.attachReadOnly(runtime.host, runtime.reducer.cursor, runtime.viewport, consume)
            }
        } catch (error: CancellationException) {
            if (terminalRuntime === runtime && runtime.reducer.state != ReadOnlyAttachState.Detached) {
                runtime.reducer.markOffline()
                publishTerminal(runtime, privacyCovered = _state.value.activeTerminal?.privacyCovered == true)
            }
            throw error
        } catch (error: Throwable) {
            if (terminalRuntime !== runtime) return
            if (runtime.writer.lease == WriterLeaseState.Held ||
                runtime.writer.lease is WriterLeaseState.Requesting
            ) {
                runtime.writer.markLeaseLost()
                runtime.pendingMutations.clear()
                runtime.inputInFlight = null
                runtime.writerMessage = "connection_failed_no_replay"
            }
            if (runtime.reducer.state !is ReadOnlyAttachState.Gap) {
                if (error is ControllerConnectionException.HostError && error.code.contains("exit", true)) {
                    runtime.reducer.markExited()
                } else if (error is IllegalArgumentException) {
                    runtime.reducer.fail("malformed_or_resource_limit")
                } else {
                    runtime.reducer.markOffline()
                }
            }
            publishTerminal(runtime)
        }
    }

    private fun consumeTerminalEvent(runtime: ActiveTerminalRuntime, event: ReadOnlyWireEvent) {
        when (event) {
            is ReadOnlyWireEvent.Snapshot -> {
                if (event.chunk.chunkIndex == 0) {
                    runtime.reducer.beginSnapshot()
                    runtime.terminal.reset(event.chunk.viewport)
                    runtime.viewport = event.chunk.viewport
                }
                runtime.terminal.process(event.chunk.bytes)
                runtime.reducer.observeSnapshot(event.chunk)
            }
            is ReadOnlyWireEvent.Attached -> {
                runtime.reducer.bindReplayBarrier(event.replayThroughSequence)
                runtime.hasWriterElsewhere = event.hasWriterLease
                if (runtime.acquireAfterAttach) {
                    runtime.acquireAfterAttach = false
                    issueAcquire(runtime)
                }
            }
            is ReadOnlyWireEvent.Output -> {
                runtime.queue.enqueue(event.frame)
                while (true) {
                    val frame = runtime.queue.removeFirstOrNull() ?: break
                    when (runtime.reducer.observe(frame)) {
                        OutputDisposition.DELIVER -> runtime.terminal.process(frame.bytes)
                        OutputDisposition.DUPLICATE -> Unit
                        OutputDisposition.GAP -> throw ControllerConnectionException.SequenceGap
                    }
                }
            }
            is ReadOnlyWireEvent.HostError -> failMutation(runtime, event.commandId, event.code, event.completionUnknown)
            is ReadOnlyWireEvent.Completed -> completeMutation(runtime, event.commandId, event.applied)
        }
        if (event is ReadOnlyWireEvent.Output) {
            scheduleTerminalPublish(runtime)
        } else {
            publishTerminal(runtime)
        }
    }

    private fun scheduleTerminalPublish(runtime: ActiveTerminalRuntime) {
        if (terminalRender?.isActive == true) return
        terminalRender = viewModelScope.launch {
            delay(16)
            publishTerminal(runtime)
        }
    }

    private fun publishTerminal(runtime: ActiveTerminalRuntime, privacyCovered: Boolean = false) {
        if (terminalRuntime !== runtime) return
        _state.value = _state.value.copy(
            activeTerminal = ControllerTerminalUiState(
                hostTitle = runtime.host.displayName,
                sessionTitle = runtime.session.title,
                attachState = runtime.reducer.state,
                screen = runtime.terminal.snapshot(),
                outputSequence = runtime.reducer.cursor.outputSequence,
                hasWriterElsewhere = runtime.hasWriterElsewhere,
                writerLease = runtime.writer.lease,
                writerMessage = runtime.writerMessage,
                pendingPasteBytes = runtime.pendingPaste?.size ?: 0,
                supportsWriter = runtime.supportsWriter,
                supportsResize = runtime.supportsResize,
                privacyCovered = privacyCovered,
            ),
        )
    }

    private fun issueAcquire(runtime: ActiveTerminalRuntime) {
        if (terminalRuntime !== runtime || !runtime.interactive) return
        val commandId = UUID.randomUUID()
        try {
            runtime.writer.beginAcquire(commandId)
        } catch (_: IllegalArgumentException) {
            runtime.writerMessage = "control_unavailable"
            publishTerminal(runtime)
            return
        }
        runtime.pendingMutations[commandId] = TerminalMutation.ACQUIRE
        publishTerminal(runtime)
        viewModelScope.launch {
            runCatching { connection.requestWriter(runtime.host, runtime.writer.identity, commandId) }
                .onFailure { mutationSendFailed(runtime, commandId) }
        }
    }

    private fun enqueueTerminalInput(bytes: ByteArray, kind: PendingInputKind, confirmed: Boolean) {
        val runtime = terminalRuntime ?: return
        if (runtime.writer.lease != WriterLeaseState.Held || bytes.isEmpty()) return
        try {
            var offset = 0
            while (offset < bytes.size) {
                val end = (offset + ControllerWriterWireCodec.MAX_INPUT_CHUNK_BYTES).coerceAtMost(bytes.size)
                runtime.writer.enqueue(bytes.copyOfRange(offset, end), kind, confirmed)
                offset = end
            }
            runtime.writerMessage = null
            drainInput(runtime)
        } catch (_: IllegalArgumentException) {
            runtime.writerMessage = "input_pressure"
        }
        publishTerminal(runtime)
    }

    private fun drainInput(runtime: ActiveTerminalRuntime) {
        if (runtime.inputInFlight != null || runtime.writer.lease != WriterLeaseState.Held) return
        val pending = runtime.writer.removeFirstOrNull() ?: return
        runtime.inputInFlight = pending.commandId
        runtime.pendingMutations[pending.commandId] = TerminalMutation.INPUT
        viewModelScope.launch {
            runCatching {
                connection.sendInput(runtime.host, runtime.writer.identity, pending.commandId, pending.bytes)
            }.onFailure { mutationSendFailed(runtime, pending.commandId) }
        }
    }

    private fun sendPendingResize(runtime: ActiveTerminalRuntime) {
        val viewport = runtime.pendingResize ?: return
        if (runtime.writer.lease != WriterLeaseState.Held) return
        runtime.pendingResize = null
        val commandId = UUID.randomUUID()
        runtime.pendingMutations[commandId] = TerminalMutation.RESIZE
        viewModelScope.launch {
            runCatching {
                connection.sendResize(runtime.host, runtime.writer.identity, commandId, viewport)
            }.onFailure { mutationSendFailed(runtime, commandId) }
        }
    }

    private fun completeMutation(runtime: ActiveTerminalRuntime, commandId: UUID, applied: Boolean) {
        when (runtime.pendingMutations.remove(commandId) ?: return loseWriter(runtime, "stale_response")) {
            TerminalMutation.ACQUIRE -> {
                runCatching { runtime.writer.finishAcquire(commandId, applied) }
                    .onFailure { return loseWriter(runtime, "stale_response") }
                runtime.hasWriterElsewhere = !applied
                runtime.writerMessage = if (applied) null else "controlled_elsewhere"
            }
            TerminalMutation.RELEASE -> Unit
            TerminalMutation.INPUT -> {
                if (runtime.inputInFlight != commandId || !applied) return loseWriter(runtime, "input_rejected")
                runtime.inputInFlight = null
                drainInput(runtime)
            }
            TerminalMutation.RESIZE -> if (!applied) runtime.writerMessage = "resize_rejected"
        }
        publishTerminal(runtime)
    }

    private fun failMutation(
        runtime: ActiveTerminalRuntime,
        commandId: UUID,
        code: String,
        completionUnknown: Boolean,
    ) {
        val mutation = runtime.pendingMutations.remove(commandId) ?: return loseWriter(runtime, "unmatched_error")
        if (runtime.inputInFlight == commandId) runtime.inputInFlight = null
        if (mutation == TerminalMutation.ACQUIRE && !completionUnknown) {
            runCatching { runtime.writer.finishAcquire(commandId, false) }
            runtime.hasWriterElsewhere = code == "writer_lease_required" || code == "writer_busy"
            runtime.writerMessage = "control_unavailable"
            publishTerminal(runtime)
        } else {
            loseWriter(runtime, if (completionUnknown) "completion_unknown" else code)
        }
    }

    private fun mutationSendFailed(runtime: ActiveTerminalRuntime, commandId: UUID) {
        if (runtime.pendingMutations.remove(commandId) == null) return
        if (runtime.inputInFlight == commandId) runtime.inputInFlight = null
        loseWriter(runtime, "connection_failed_no_replay")
    }

    private fun loseWriter(runtime: ActiveTerminalRuntime, message: String) {
        runtime.writer.markLeaseLost()
        runtime.pendingMutations.clear()
        runtime.inputInFlight = null
        runtime.writerMessage = message
        publishTerminal(runtime)
    }

    private suspend fun releaseWriterForLifecycle(runtime: ActiveTerminalRuntime, wasHeld: Boolean) {
        if (!wasHeld) return
        val commandId = UUID.randomUUID()
        runtime.writer.releaseLocally()
        runCatching { connection.releaseWriter(runtime.host, runtime.writer.identity, commandId) }
    }

    private fun selectedHost(): PairedHostRecord? =
        hosts.firstOrNull { it.id == _state.value.selectedHostId }

    private fun showFailure(error: Throwable) {
        if (error is CancellationException) return
        _state.value = _state.value.copy(connection = ControllerConnectionState.Failed(classify(error)))
    }

    private fun classify(error: Throwable): String = when (error) {
        is ControllerSecretException.Invalidated -> "keystore_invalidated"
        is ControllerSecretException.Corrupt -> "secret_corrupt"
        is ControllerStoreException.ResourceLimit -> "resource_limit"
        is ControllerConnectionException.PairingRejected -> "pairing_rejected"
        is ControllerConnectionException.AcknowledgementUncertain -> "pairing_acknowledgement_uncertain"
        is ControllerConnectionException.SequenceGap -> "sequence_gap"
        is ControllerConnectionException.HostError -> error.code
        is SocketTimeoutException -> "timeout"
        is SocketException -> "offline"
        is IllegalArgumentException -> "invalid_data"
        else -> "operation_failed"
    }

    private fun isRetryable(error: Throwable): Boolean =
        error is SocketTimeoutException || error is SocketException

    private fun loadDeviceId(application: Application): UUID {
        val preferences = application.getSharedPreferences("controller-device", 0)
        val existing = preferences.getString("device_id", null)
        if (existing != null) runCatching { return UUID.fromString(existing) }
        return UUID.randomUUID().also { preferences.edit().putString("device_id", it.toString()).apply() }
    }
}

private data class ActiveTerminalRuntime(
    val host: PairedHostRecord,
    val session: ControllerSessionSummary,
    val reducer: ReadOnlyAttachReducer,
    val writer: WriterControlReducer,
    val terminal: BoundedControllerTerminal,
    val queue: BoundedTerminalFrameQueue,
    var viewport: TerminalViewport,
    var hasWriterElsewhere: Boolean = false,
    var interactive: Boolean = false,
    var acquireAfterAttach: Boolean = false,
    var writerMessage: String? = null,
    var pendingPaste: ByteArray? = null,
    var pendingResize: TerminalViewport? = null,
    var inputInFlight: UUID? = null,
    val pendingMutations: MutableMap<UUID, TerminalMutation> = mutableMapOf(),
)

private enum class TerminalMutation { ACQUIRE, RELEASE, INPUT, RESIZE }

private val ActiveTerminalRuntime.supportsWriter: Boolean
    get() {
        val hostAllows = host.capabilityBits and ((1 shl 1) or (1 shl 2)) == ((1 shl 1) or (1 shl 2))
        val sessionAllows = session.capabilities.isEmpty() || (
            ControllerSessionCapability.ATTACH_OUTPUT in session.capabilities &&
                ControllerSessionCapability.SEND_INPUT in session.capabilities
            )
        return hostAllows && sessionAllows
    }

private val ActiveTerminalRuntime.supportsResize: Boolean
    get() = host.capabilityBits and (1 shl 3) != 0 &&
        (session.capabilities.isEmpty() || ControllerSessionCapability.RESIZE in session.capabilities)
