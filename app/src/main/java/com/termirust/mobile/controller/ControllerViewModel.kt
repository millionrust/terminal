package com.termirust.mobile.controller

import android.app.Application
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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
        if (operation?.isActive == true) return
        operation = viewModelScope.launch { refreshSelected(retry = true) }
    }

    fun onBackground() {
        operation?.cancel()
        operation = viewModelScope.launch { connection.cancel() }
        val selected = _state.value.selectedHostId
        _state.value = makeState(selected, ControllerConnectionState.PairedOffline)
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
        )
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
