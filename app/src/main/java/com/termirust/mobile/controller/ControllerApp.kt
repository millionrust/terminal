package com.termirust.mobile.controller

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ControllerApp(viewModel: ControllerViewModel) {
    val state by viewModel.state.collectAsState()
    val lifecycleOwner = LocalLifecycleOwner.current
    var showPairing by remember { mutableStateOf(false) }
    var showScanner by remember { mutableStateOf(false) }
    var showHostDetails by remember { mutableStateOf(false) }
    var confirmForget by remember { mutableStateOf(false) }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> viewModel.onForeground()
                Lifecycle.Event.ON_STOP -> viewModel.onBackground()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    MaterialTheme {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            topBar = {
                TopAppBar(
                    title = {
                        Column {
                            Text(stringResource(com.termirust.mobile.R.string.app_name), fontWeight = FontWeight.Bold)
                            Text(stringResource(com.termirust.mobile.R.string.controller_fleet), style = MaterialTheme.typography.labelMedium)
                        }
                    },
                    actions = {
                        TextButton(onClick = { showPairing = true }) { Text(stringResource(com.termirust.mobile.R.string.pair_host)) }
                        if (state.selectedHostId != null) {
                            TextButton(onClick = { showHostDetails = true }) { Text(stringResource(com.termirust.mobile.R.string.details)) }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ),
                    modifier = Modifier.statusBarsPadding(),
                )
            },
        ) { padding ->
            BoxWithConstraints(
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .navigationBarsPadding(),
            ) {
                if (state.hosts.isEmpty()) {
                    EmptyFleet(onPair = { showPairing = true })
                } else if (maxWidth >= 840.dp) {
                    Row(Modifier.fillMaxSize()) {
                        HostList(
                            state = state,
                            onSelect = viewModel::selectHost,
                            modifier = Modifier.width(340.dp).fillMaxHeight(),
                        )
                        VerticalDivider(modifier = Modifier.fillMaxHeight())
                        FleetDetail(state, viewModel::retry, Modifier.weight(1f))
                    }
                } else {
                    Column(Modifier.fillMaxSize()) {
                        CompactHostStrip(state, viewModel::selectHost)
                        HorizontalDivider()
                        FleetDetail(state, viewModel::retry, Modifier.weight(1f))
                    }
                }
            }
        }
    }

    if (showPairing) {
        PairHostDialog(
            viewModel = viewModel,
            connection = state.connection,
            onDismiss = {
                viewModel.cancelPairing()
                showPairing = false
            },
            onComplete = { showPairing = false },
            onScan = { showScanner = true },
        )
    }
    if (showScanner) {
        ControllerQrScannerDialog(
            onResult = { offer ->
                viewModel.pairingOffer.value = offer
                showScanner = false
                showPairing = true
            },
            onDismiss = { showScanner = false },
        )
    }
    if (showHostDetails) {
        val selected = state.hosts.firstOrNull { it.id == state.selectedHostId }
        if (selected != null) {
            HostDetailsDialog(
                host = selected,
                onDismiss = { showHostDetails = false },
                onReconnect = {
                    showHostDetails = false
                    viewModel.retry()
                },
                onForget = {
                    showHostDetails = false
                    confirmForget = true
                },
            )
        }
    }
    if (confirmForget) {
        AlertDialog(
            onDismissRequest = { confirmForget = false },
            title = { Text(stringResource(com.termirust.mobile.R.string.forget_host_title)) },
            text = { Text(stringResource(com.termirust.mobile.R.string.forget_host_explanation)) },
            confirmButton = {
                Button(onClick = {
                    confirmForget = false
                    viewModel.forgetSelectedHost()
                }) { Text(stringResource(com.termirust.mobile.R.string.forget_on_device)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmForget = false }) { Text(stringResource(com.termirust.mobile.R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun EmptyFleet(onPair: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.padding(28.dp),
        ) {
            Text(stringResource(com.termirust.mobile.R.string.no_paired_hosts), style = MaterialTheme.typography.headlineSmall)
            Text(
                stringResource(com.termirust.mobile.R.string.pair_private_network_hint),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = onPair, modifier = Modifier.size(width = 160.dp, height = 48.dp)) {
                Text(stringResource(com.termirust.mobile.R.string.pair_host))
            }
        }
    }
}

@Composable
private fun HostList(
    state: ControllerUiState,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Text(
                stringResource(com.termirust.mobile.R.string.paired_hosts),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
            )
        }
        items(state.hosts, key = { it.id }) { host ->
            HostRow(host, host.id == state.selectedHostId) { onSelect(host.id) }
        }
    }
}

@Composable
private fun CompactHostStrip(state: ControllerUiState, onSelect: (String) -> Unit) {
    LazyRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(state.hosts, key = { it.id }) { host ->
            CompactHostChip(host, host.id == state.selectedHostId) { onSelect(host.id) }
        }
    }
}

@Composable
private fun CompactHostChip(host: PairedHostRecord, selected: Boolean, onClick: () -> Unit) {
    val hostDescription = stringResource(com.termirust.mobile.R.string.host_accessibility, isolated(host.displayName))
    Card(
        modifier = Modifier
            .width(220.dp)
            .clickable(onClick = onClick)
            .semantics { contentDescription = hostDescription },
        colors = CardDefaults.cardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.secondaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            },
        ),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(
                isolated(host.displayName),
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                isolated("${host.route.address}:${host.route.port}"),
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun HostRow(host: PairedHostRecord, selected: Boolean, onClick: () -> Unit) {
    val hostDescription = stringResource(com.termirust.mobile.R.string.host_accessibility, isolated(host.displayName))
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .semantics { contentDescription = hostDescription },
        colors = CardDefaults.cardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.secondaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            },
        ),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                Modifier.size(36.dp).background(
                    MaterialTheme.colorScheme.primary,
                    MaterialTheme.shapes.small,
                ),
                contentAlignment = Alignment.Center,
            ) { Text(">", color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Bold) }
            Column(Modifier.weight(1f)) {
                Text(isolated(host.displayName), fontWeight = FontWeight.SemiBold, maxLines = 2)
                Text(
                    isolated("${host.route.address}:${host.route.port}"),
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (selected) AssistChip(onClick = onClick, label = { Text(stringResource(com.termirust.mobile.R.string.controller_selected)) })
        }
    }
}

@Composable
private fun FleetDetail(
    state: ControllerUiState,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize()) {
        ConnectionBanner(state, onRetry)
        if (state.sessions.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    if (state.connection.isBusy()) stringResource(com.termirust.mobile.R.string.loading_sessions) else stringResource(com.termirust.mobile.R.string.no_durable_sessions),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                Modifier.fillMaxSize().padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(state.sessions, key = { it.id }) { session -> SessionRow(session, state.cachedReadOnly) }
            }
        }
    }
}

@Composable
private fun ConnectionBanner(state: ControllerUiState, onRetry: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (state.connection.isBusy()) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            Column(Modifier.weight(1f)) {
                Text(connectionLabel(state.connection), fontWeight = FontWeight.SemiBold)
                if (state.cachedReadOnly) {
                    Text(
                        stringResource(com.termirust.mobile.R.string.cached_updated, relativeTime(state.cachedAtMillis)),
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
            if (state.connection is ControllerConnectionState.Failed || state.cachedReadOnly) {
                OutlinedButton(onClick = onRetry) { Text(stringResource(com.termirust.mobile.R.string.retry)) }
            }
        }
    }
}

@Composable
private fun SessionRow(session: ControllerSessionSummary, cached: Boolean) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(
            Modifier.fillMaxWidth().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    isolated(session.title),
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                AssistChip(onClick = {}, label = { Text(if (cached) stringResource(com.termirust.mobile.R.string.cached) else session.lifecycle) })
            }
            val location = listOfNotNull(session.project, session.group).joinToString(" / ")
            if (location.isNotEmpty()) {
                Text(isolated(location), style = MaterialTheme.typography.bodySmall)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(session.activity ?: stringResource(com.termirust.mobile.R.string.no_recent_activity), style = MaterialTheme.typography.labelMedium)
                if (session.unreadCount > 0) Text(stringResource(com.termirust.mobile.R.string.unread), color = MaterialTheme.colorScheme.primary)
                if (session.hasWriter) Text(stringResource(com.termirust.mobile.R.string.writer_active), color = MaterialTheme.colorScheme.tertiary)
            }
        }
    }
}

@Composable
private fun PairHostDialog(
    viewModel: ControllerViewModel,
    connection: ControllerConnectionState,
    onDismiss: () -> Unit,
    onComplete: () -> Unit,
    onScan: () -> Unit,
) {
    val offer by viewModel.pairingOffer.collectAsState()
    val hostName by viewModel.pairingHostName.collectAsState()
    val deviceName by viewModel.pairingDeviceName.collectAsState()
    val sas = connection as? ControllerConnectionState.SasReady
    val spokenSas = sas?.sas?.toCharArray()?.joinToString(" ")
    val sasDescription = spokenSas?.let {
        stringResource(com.termirust.mobile.R.string.security_code_accessibility, it)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (sas == null) stringResource(com.termirust.mobile.R.string.pair_host) else stringResource(com.termirust.mobile.R.string.compare_security_code)) },
        text = {
            if (sas == null) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(com.termirust.mobile.R.string.pairing_offer_hint))
                    OutlinedButton(onClick = onScan, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(com.termirust.mobile.R.string.scan_qr_code))
                    }
                    OutlinedTextField(
                        value = offer,
                        onValueChange = { if (it.toByteArray().size <= 4 * 1_024) viewModel.pairingOffer.value = it },
                        label = { Text(stringResource(com.termirust.mobile.R.string.pairing_offer)) },
                        minLines = 4,
                        maxLines = 8,
                    )
                    OutlinedTextField(
                        value = hostName,
                        onValueChange = { viewModel.pairingHostName.value = it.take(256) },
                        label = { Text(stringResource(com.termirust.mobile.R.string.host_name)) },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = deviceName,
                        onValueChange = { viewModel.pairingDeviceName.value = it.take(64) },
                        label = { Text(stringResource(com.termirust.mobile.R.string.this_device)) },
                        singleLine = true,
                    )
                    if (connection is ControllerConnectionState.Failed) {
                        Text(stringResource(com.termirust.mobile.R.string.pairing_failed, connection.code), color = MaterialTheme.colorScheme.error)
                    }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(stringResource(com.termirust.mobile.R.string.confirm_security_code))
                    Text(
                        sas.sas,
                        style = MaterialTheme.typography.headlineMedium,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics {
                            contentDescription = requireNotNull(sasDescription)
                        },
                    )
                    Text(stringResource(com.termirust.mobile.R.string.fingerprint_ending, sas.fingerprintSuffix))
                }
            }
        },
        confirmButton = {
            if (sas == null) {
                Button(
                    onClick = viewModel::beginPairing,
                    enabled = offer.isNotBlank() && connection !is ControllerConnectionState.Pairing,
                ) { Text(stringResource(com.termirust.mobile.R.string.continue_action)) }
            } else {
                Button(onClick = {
                    viewModel.finishPairing(true)
                    onComplete()
                }) { Text(stringResource(com.termirust.mobile.R.string.codes_match)) }
            }
        },
        dismissButton = {
            TextButton(onClick = {
                if (sas != null) viewModel.finishPairing(false)
                onDismiss()
            }) { Text(if (sas == null) stringResource(com.termirust.mobile.R.string.cancel) else stringResource(com.termirust.mobile.R.string.reject)) }
        },
    )
}

@Composable
private fun HostDetailsDialog(
    host: PairedHostRecord,
    onDismiss: () -> Unit,
    onReconnect: () -> Unit,
    onForget: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(isolated(host.displayName)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(com.termirust.mobile.R.string.route_value, isolated(host.route.address), host.route.port))
                Text(stringResource(com.termirust.mobile.R.string.fingerprint_ending, host.id.takeLast(12)), fontFamily = FontFamily.Monospace)
                Text(stringResource(com.termirust.mobile.R.string.capabilities_value, capabilityLabels(host.capabilityBits).joinToString()))
                Text(stringResource(com.termirust.mobile.R.string.forget_not_revoke))
            }
        },
        confirmButton = { Button(onClick = onReconnect) { Text(stringResource(com.termirust.mobile.R.string.reconnect)) } },
        dismissButton = {
            Row {
                TextButton(onClick = onForget) { Text(stringResource(com.termirust.mobile.R.string.forget)) }
                TextButton(onClick = onDismiss) { Text(stringResource(com.termirust.mobile.R.string.close)) }
            }
        },
    )
}

private fun ControllerConnectionState.isBusy(): Boolean =
    this == ControllerConnectionState.Connecting ||
        this == ControllerConnectionState.Authenticating ||
        this == ControllerConnectionState.Syncing ||
        this == ControllerConnectionState.Pairing

@Composable
private fun connectionLabel(state: ControllerConnectionState): String = when (state) {
    ControllerConnectionState.Unpaired -> stringResource(com.termirust.mobile.R.string.state_not_paired)
    ControllerConnectionState.Pairing -> stringResource(com.termirust.mobile.R.string.state_pairing)
    is ControllerConnectionState.SasReady -> stringResource(com.termirust.mobile.R.string.state_waiting_code)
    ControllerConnectionState.PairedOffline -> stringResource(com.termirust.mobile.R.string.state_host_offline)
    ControllerConnectionState.Connecting -> stringResource(com.termirust.mobile.R.string.state_connecting)
    ControllerConnectionState.Authenticating -> stringResource(com.termirust.mobile.R.string.state_authenticating)
    ControllerConnectionState.Syncing -> stringResource(com.termirust.mobile.R.string.state_syncing)
    ControllerConnectionState.ReadyReadOnly -> stringResource(com.termirust.mobile.R.string.state_live_read_only)
    ControllerConnectionState.Revoked -> stringResource(com.termirust.mobile.R.string.state_device_revoked)
    ControllerConnectionState.Incompatible -> stringResource(com.termirust.mobile.R.string.state_incompatible)
    is ControllerConnectionState.Failed -> stringResource(com.termirust.mobile.R.string.state_connection_failed, state.code)
}

private fun capabilityLabels(bits: Int): List<String> = buildList {
    if (bits and 1 != 0) add("Fleet")
    if (bits and 2 != 0) add("Output")
    if (bits and 4 != 0) add("Input")
    if (bits and 8 != 0) add("Resize")
    if (bits and 16 != 0) add("Approvals")
}

private fun isolated(value: String): String = "\u2068$value\u2069"

@Composable
private fun relativeTime(millis: Long?): String {
    if (millis == null) return stringResource(com.termirust.mobile.R.string.time_unknown)
    val seconds = ((System.currentTimeMillis() - millis).coerceAtLeast(0)) / 1_000
    return when {
        seconds < 60 -> stringResource(com.termirust.mobile.R.string.time_just_now)
        seconds < 3_600 -> stringResource(com.termirust.mobile.R.string.time_minutes, seconds / 60)
        seconds < 86_400 -> stringResource(com.termirust.mobile.R.string.time_hours, seconds / 3_600)
        else -> stringResource(com.termirust.mobile.R.string.time_days, seconds / 86_400)
    }
}
