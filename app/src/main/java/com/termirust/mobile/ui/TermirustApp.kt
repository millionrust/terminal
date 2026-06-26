package com.termirust.mobile.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.termirust.mobile.MobileHostViewModel
import com.termirust.mobile.data.MobileAuthKind
import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.data.MobileKnownHost
import com.termirust.mobile.ssh.TerminalConnectionState
import com.termirust.mobile.terminal.encodeTerminalInput
import com.termirust.mobile.terminal.estimateTerminalGrid

private val AppBackground = Color(0xFFF5F7FA)
private val PanelBorder = Color(0xFFE0E6EF)
private val TerminalBackground = Color(0xFF0B1020)
private val TerminalForeground = Color(0xFFE5E7EB)
private val TerminalMuted = Color(0xFF94A3B8)
private val Accent = Color(0xFF2563EB)
private val Success = Color(0xFF0F9F6E)
private val Warning = Color(0xFFB45309)

@Composable
fun TermirustApp(
    viewModel: MobileHostViewModel,
    onImportVault: (String) -> Unit,
    onImportCredentialFile: () -> Unit,
) {
    MaterialTheme {
        var showVaultDialog by remember { mutableStateOf(false) }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(AppBackground)
                .imePadding(),
        ) {
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding(),
            ) {
                val wide = maxWidth >= 900.dp
                val panelSpacing = if (wide) 1.dp else 0.dp
                val hostPanelWidth = (maxWidth * 0.34f).coerceIn(340.dp, 460.dp)
                if (wide) {
                    Row(
                        modifier = Modifier.fillMaxSize(),
                        horizontalArrangement = Arrangement.spacedBy(panelSpacing),
                    ) {
                        HostPanel(
                            viewModel = viewModel,
                            onImportVault = onImportVault,
                            modifier = Modifier
                                .width(hostPanelWidth)
                                .fillMaxHeight(),
                        )
                        SessionPanel(
                            viewModel = viewModel,
                            onImportCredentialFile = onImportCredentialFile,
                            modifier = Modifier.weight(1f),
                            framed = false,
                        )
                    }
                } else {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(0.dp),
                    ) {
                        CompactTopBar(
                            viewModel = viewModel,
                            onOpenVault = { showVaultDialog = true },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        CompactHostStrip(
                            viewModel = viewModel,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        SessionPanel(
                            viewModel = viewModel,
                            onImportCredentialFile = onImportCredentialFile,
                            modifier = Modifier.weight(1f),
                            framed = false,
                        )
                    }
                }
            }
            if (showVaultDialog) {
                VaultDialog(
                    viewModel = viewModel,
                    onImportVault = onImportVault,
                    onDismiss = { showVaultDialog = false },
                )
            }
        }
    }
}

@Composable
private fun HostPanel(
    viewModel: MobileHostViewModel,
    onImportVault: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val vault by viewModel.vault.collectAsState()
    val selectedHost by viewModel.selectedHost.collectAsState()
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = Color.White),
        border = BorderStroke(1.dp, PanelBorder),
        shape = RoundedCornerShape(18.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ProductHeader()
            ImportVaultCard(viewModel = viewModel, onImportVault = onImportVault)
            Text(
                "Hosts",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = Color(0xFF111827),
            )
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(vault?.hosts.orEmpty(), key = { it.id }) { host ->
                    HostCard(
                        host = host,
                        selected = host.id == selectedHost?.id,
                        onClick = { viewModel.selectHost(host) },
                    )
                }
            }
        }
    }
}

@Composable
private fun CompactTopBar(
    viewModel: MobileHostViewModel,
    onOpenVault: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vault by viewModel.vault.collectAsState()
    Surface(
        modifier = modifier,
        color = Color.White,
        border = BorderStroke(1.dp, PanelBorder),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ProductHeader(
                subtitle = if (vault?.hosts.isNullOrEmpty()) {
                    "Import vault to begin"
                } else {
                    "${vault?.hosts?.size ?: 0} hosts available"
                },
                modifier = Modifier.weight(1f),
            )
            OutlinedButton(onClick = onOpenVault) {
                Text("Vault")
            }
        }
    }
}

@Composable
private fun ProductHeader(
    subtitle: String = "Mobile terminal",
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .background(TerminalBackground, RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Text(">", color = Color.White, fontWeight = FontWeight.Bold)
        }
        Column {
            Text("TermiRust", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF64748B),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun VaultDialog(
    viewModel: MobileHostViewModel,
    onImportVault: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Done")
            }
        },
        title = { Text("Vault") },
        text = {
            ImportVaultCard(
                viewModel = viewModel,
                onImportVault = onImportVault,
                compact = true,
            )
        },
        containerColor = Color.White,
    )
}

@Composable
private fun ImportVaultCard(
    viewModel: MobileHostViewModel,
    onImportVault: (String) -> Unit,
    compact: Boolean = false,
) {
    val status by viewModel.status.collectAsState()
    val hasStoredEncryptedVault by viewModel.hasStoredEncryptedVault.collectAsState()
    val clipboard = LocalClipboardManager.current
    var vaultPassphrase by remember { mutableStateOf("") }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!compact) {
            Text("Vault", style = MaterialTheme.typography.labelLarge, color = Color(0xFF334155))
        }
        OutlinedTextField(
            value = vaultPassphrase,
            onValueChange = { vaultPassphrase = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Vault passphrase") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
        )
        Button(
            onClick = { onImportVault(vaultPassphrase) },
            enabled = vaultPassphrase.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Accent),
        ) {
            Text("Import Encrypted Vault")
        }
        OutlinedButton(
            onClick = {
                runCatching { viewModel.pairingRequestText() }
                    .onSuccess {
                        clipboard.setText(AnnotatedString(it))
                        viewModel.reportStatus("Pairing request copied. Import it on desktop to authorize this device.")
                    }
                    .onFailure { viewModel.reportStatus(it.message ?: "Unable to create pairing request.") }
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Copy Pairing Request")
        }
        if (hasStoredEncryptedVault) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                FilledTonalButton(
                    onClick = {
                        viewModel.unlockStoredEncryptedVault(vaultPassphrase.toCharArray())
                        vaultPassphrase = ""
                    },
                    enabled = vaultPassphrase.isNotBlank(),
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Unlock Saved Vault")
                }
                OutlinedButton(onClick = { viewModel.forgetStoredEncryptedVault() }) {
                    Text("Forget")
                }
            }
        }
        status?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = Color(0xFF475569))
        }
    }
}

@Composable
private fun CompactHostStrip(viewModel: MobileHostViewModel, modifier: Modifier = Modifier) {
    val vault by viewModel.vault.collectAsState()
    val selectedHost by viewModel.selectedHost.collectAsState()
    val hosts = vault?.hosts.orEmpty()
    if (hosts.isEmpty()) {
        return
    }

    LazyRow(
        modifier = modifier
            .height(52.dp)
            .background(Color.White)
            .padding(horizontal = 14.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(hosts, key = { it.id }) { host ->
            HostChip(
                host = host,
                selected = host.id == selectedHost?.id,
                onClick = { viewModel.selectHost(host) },
            )
        }
    }
}

@Composable
private fun HostCard(host: MobileHost, selected: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        color = if (selected) Color(0xFFEFF6FF) else Color(0xFFF8FAFC),
        border = BorderStroke(1.dp, if (selected) Accent else PanelBorder),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    host.label,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (host.persistentSession.enabled) {
                    StatusPill("tmux", Accent)
                }
            }
            Text(
                "${host.username}@${host.host}:${host.port}",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF64748B),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            host.persistentSession.sessionName?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = Color(0xFF2563EB))
            }
        }
    }
}

@Composable
private fun HostChip(host: MobileHost, selected: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        color = if (selected) Color(0xFFEFF6FF) else Color.White,
        border = BorderStroke(1.dp, if (selected) Accent else PanelBorder),
        shape = RoundedCornerShape(999.dp),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(host.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (host.persistentSession.enabled) {
                Text("tmux", color = Accent, style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

@Composable
private fun SessionPanel(
    viewModel: MobileHostViewModel,
    onImportCredentialFile: () -> Unit,
    modifier: Modifier = Modifier,
    framed: Boolean = true,
) {
    val selectedHost by viewModel.selectedHost.collectAsState()
    val vault by viewModel.vault.collectAsState()
    val lines by viewModel.terminalBuffer.lines.collectAsState()
    val state by viewModel.connectionState.collectAsState()
    var command by remember { mutableStateOf("") }
    var credential by remember(selectedHost?.id) { mutableStateOf("") }
    var terminalFontSize by remember { mutableStateOf(14) }
    var pendingMultilinePaste by remember { mutableStateOf<String?>(null) }
    var terminalWidthPx by remember { mutableStateOf(0) }
    var terminalHeightPx by remember { mutableStateOf(0) }
    var controlModifierActive by remember { mutableStateOf(false) }
    var altModifierActive by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    val terminalGrid = remember(terminalWidthPx, terminalHeightPx, terminalFontSize, density.density) {
        if (terminalWidthPx > 0 && terminalHeightPx > 0) {
            estimateTerminalGrid(terminalWidthPx, terminalHeightPx, terminalFontSize, density.density)
        } else {
            null
        }
    }

    LaunchedEffect(terminalGrid, state) {
        if (terminalGrid != null && state == TerminalConnectionState.Connected) {
            viewModel.resizeTerminal(terminalGrid.columns, terminalGrid.rows)
        }
    }

    fun sendCommandWithPasteGuard(force: Boolean = false) {
        val value = command
        val modifierActive = controlModifierActive || altModifierActive
        if (!force && !modifierActive && value.lineSequence().take(2).count() > 1) {
            pendingMultilinePaste = value
            return
        }
        if (modifierActive) {
            viewModel.sendTerminalBytes(
                encodeTerminalInput(
                    input = value,
                    control = controlModifierActive,
                    alt = altModifierActive,
                ),
            )
        } else {
            viewModel.sendTerminalInput(value)
        }
        command = ""
        controlModifierActive = false
        altModifierActive = false
        pendingMultilinePaste = null
    }

    val content: @Composable () -> Unit = {
        Column(modifier = Modifier.fillMaxSize()) {
            SessionHeader(
                host = selectedHost,
                state = state,
                onConnect = { viewModel.connectSelectedHost() },
                onDisconnect = { viewModel.disconnect() },
            )
            state.failureMessage()?.let { message ->
                ConnectionWarningBanner(message = message)
            }
            selectedHost?.let { host ->
                HostKeyPinPanel(
                    host = host,
                    knownHost = vault?.knownHosts?.firstOrNull { it.endpoint == host.knownHostEndpoint },
                )
                CredentialEditor(
                    host = host,
                    credential = credential,
                    onCredentialChange = { credential = it },
                    onSave = {
                        viewModel.saveCredentialForSelectedHost(credential)
                        credential = ""
                    },
                    onDelete = {
                        viewModel.deleteCredentialForSelectedHost()
                        credential = ""
                    },
                    onImportCredentialFile = onImportCredentialFile,
                )
            }
            TerminalSurface(
                lines = lines,
                terminalFontSize = terminalFontSize,
                onSizeChanged = { width, height ->
                    terminalWidthPx = width
                    terminalHeightPx = height
                },
                modifier = Modifier.weight(1f),
                edgeToEdge = !framed,
            )
            TerminalToolbar(
                terminalFontSize = terminalFontSize,
                onDecreaseFont = { terminalFontSize = (terminalFontSize - 1).coerceAtLeast(10) },
                onIncreaseFont = { terminalFontSize = (terminalFontSize + 1).coerceAtMost(24) },
                controlModifierActive = controlModifierActive,
                altModifierActive = altModifierActive,
                onToggleControl = { controlModifierActive = !controlModifierActive },
                onToggleAlt = { altModifierActive = !altModifierActive },
                onSend = viewModel::sendTerminalBytes,
            )
            if (pendingMultilinePaste == command && command.isNotEmpty()) {
                MultilinePasteWarning(
                    onConfirm = { sendCommandWithPasteGuard(force = true) },
                    onCancel = { pendingMultilinePaste = null },
                )
            }
            CommandInput(
                command = command,
                connected = state == TerminalConnectionState.Connected,
                onCommandChange = {
                    command = it
                    if (pendingMultilinePaste != it) {
                        pendingMultilinePaste = null
                    }
                },
                onSend = { sendCommandWithPasteGuard() },
            )
        }
    }

    if (framed) {
        Card(
            modifier = modifier.fillMaxSize(),
            colors = CardDefaults.cardColors(containerColor = Color.White),
            border = BorderStroke(1.dp, PanelBorder),
            shape = RoundedCornerShape(18.dp),
        ) {
            content()
        }
    } else {
        Surface(
            modifier = modifier.fillMaxSize(),
            color = Color.White,
        ) {
            content()
        }
    }
}

@Composable
private fun SessionHeader(
    host: MobileHost?,
    state: TerminalConnectionState,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .padding(14.dp),
    ) {
        if (maxWidth >= 560.dp) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SessionTitle(host = host, modifier = Modifier.weight(1f))
                StatusPill(state.label(), state.color())
                SessionActions(
                    host = host,
                    state = state,
                    onConnect = onConnect,
                    onDisconnect = onDisconnect,
                )
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SessionTitle(host = host, modifier = Modifier.weight(1f))
                    StatusPill(state.label(), state.color())
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SessionActions(
                        host = host,
                        state = state,
                        onConnect = onConnect,
                        onDisconnect = onDisconnect,
                        modifier = Modifier.fillMaxWidth(),
                        expanded = true,
                    )
                }
            }
        }
    }
}

@Composable
private fun SessionTitle(host: MobileHost?, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Text(
            host?.label ?: "No host selected",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            host?.let { "${it.username}@${it.host}:${it.port}" } ?: "Import a vault and select a host",
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF64748B),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun SessionActions(
    host: MobileHost?,
    state: TerminalConnectionState,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier,
    expanded: Boolean = false,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Button(
            onClick = onConnect,
            enabled = host != null,
            modifier = if (expanded) Modifier.weight(1f) else Modifier,
            colors = ButtonDefaults.buttonColors(containerColor = Accent),
        ) {
            Text("Connect")
        }
        OutlinedButton(
            onClick = onDisconnect,
            enabled = state != TerminalConnectionState.Disconnected,
            modifier = if (expanded) Modifier.weight(1f) else Modifier,
        ) {
            Text("Disconnect")
        }
    }
}

@Composable
private fun ConnectionWarningBanner(message: String) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp),
        color = Color(0xFFFEF2F2),
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, Color(0xFFFECACA)),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                "Connection blocked",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = Color(0xFFB91C1C),
            )
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF7F1D1D),
            )
        }
    }
}

@Composable
private fun HostKeyPinPanel(host: MobileHost, knownHost: MobileKnownHost?) {
    val pinned = knownHost != null
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp),
        color = if (pinned) Color(0xFFEFFDF5) else Color(0xFFFEF2F2),
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, if (pinned) Color(0xFFBBF7D0) else Color(0xFFFECACA)),
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Text(
                if (pinned) "✓" else "!",
                modifier = Modifier.width(18.dp),
                color = if (pinned) Success else Color(0xFFDC2626),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
            )
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    if (pinned) "Host key pinned" else "Host key not pinned",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = if (pinned) Success else Color(0xFFB91C1C),
                )
                Text(
                    knownHost?.endpoint ?: host.knownHostEndpoint ?: "${host.host}:${host.port}",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color(0xFF64748B),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    knownHost?.pinPreview() ?: "Export a known-host pin from desktop before connecting.",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (pinned) Color(0xFF475569) else Color(0xFF7F1D1D),
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun CredentialEditor(
    host: MobileHost,
    credential: String,
    onCredentialChange: (String) -> Unit,
    onSave: () -> Unit,
    onDelete: () -> Unit,
    onImportCredentialFile: () -> Unit,
) {
    val secretRef = host.auth.secretRef
    val label = when (host.auth.kind) {
        MobileAuthKind.Password -> "SSH password"
        MobileAuthKind.PrivateKey -> "Private key PEM"
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            if (secretRef.isNullOrBlank()) "No mobile secret reference exported for this host."
            else "Credential: $secretRef",
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF64748B),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        OutlinedTextField(
            value = credential,
            onValueChange = onCredentialChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(label) },
            minLines = if (host.auth.kind == MobileAuthKind.PrivateKey) 2 else 1,
            maxLines = if (host.auth.kind == MobileAuthKind.PrivateKey) 4 else 1,
            visualTransformation = PasswordVisualTransformation(),
            enabled = !secretRef.isNullOrBlank(),
        )
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilledTonalButton(
                onClick = onSave,
                enabled = !secretRef.isNullOrBlank() && credential.isNotBlank(),
            ) {
                Text("Save Credential")
            }
            OutlinedButton(
                onClick = onDelete,
                enabled = !secretRef.isNullOrBlank(),
            ) {
                Text("Remove")
            }
            if (host.auth.kind == MobileAuthKind.PrivateKey) {
                OutlinedButton(
                    onClick = onImportCredentialFile,
                    enabled = !secretRef.isNullOrBlank(),
                ) {
                    Text("Import Key File")
                }
            }
        }
    }
}

@Composable
private fun TerminalSurface(
    lines: List<String>,
    terminalFontSize: Int,
    onSizeChanged: (Int, Int) -> Unit,
    modifier: Modifier = Modifier,
    edgeToEdge: Boolean = false,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(
                horizontal = if (edgeToEdge) 0.dp else 14.dp,
                vertical = if (edgeToEdge) 0.dp else 10.dp,
            )
            .onSizeChanged { onSizeChanged(it.width, it.height) },
        color = TerminalBackground,
        shape = RoundedCornerShape(if (edgeToEdge) 0.dp else 14.dp),
    ) {
        SelectionContainer {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(12.dp),
            ) {
                if (lines.isEmpty()) {
                    item {
                        Text(
                            "Terminal output will appear here.",
                            color = TerminalMuted,
                            fontFamily = FontFamily.Monospace,
                            fontSize = terminalFontSize.sp,
                        )
                    }
                } else {
                    items(lines) { line ->
                        Text(
                            line.ifEmpty { " " },
                            color = TerminalForeground,
                            fontFamily = FontFamily.Monospace,
                            fontSize = terminalFontSize.sp,
                            lineHeight = (terminalFontSize + 4).sp,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TerminalToolbar(
    terminalFontSize: Int,
    onDecreaseFont: () -> Unit,
    onIncreaseFont: () -> Unit,
    controlModifierActive: Boolean,
    altModifierActive: Boolean,
    onToggleControl: () -> Unit,
    onToggleAlt: () -> Unit,
    onSend: (ByteArray) -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            AssistChip(onClick = onDecreaseFont, label = { Text("A-") })
            AssistChip(onClick = onIncreaseFont, label = { Text("A+") })
            Text("$terminalFontSize sp", color = Color(0xFF64748B), style = MaterialTheme.typography.bodySmall)
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            item {
                AssistChip(
                    onClick = onToggleControl,
                    label = { Text(if (controlModifierActive) "Ctrl*" else "Ctrl") },
                )
            }
            item {
                AssistChip(
                    onClick = onToggleAlt,
                    label = { Text(if (altModifierActive) "Alt*" else "Alt") },
                )
            }
            items(accessoryKeys, key = { it.label }) { key ->
                AssistChip(
                    onClick = {
                        if (key.bytes.isNotEmpty()) {
                            onSend(key.bytes.encodeToByteArray())
                        }
                    },
                    label = { Text(key.label) },
                )
            }
        }
    }
}

@Composable
private fun MultilinePasteWarning(onConfirm: () -> Unit, onCancel: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 8.dp),
        color = Color(0xFFFFF7ED),
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, Color(0xFFFED7AA)),
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Multiline paste detected.",
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodySmall,
                color = Warning,
            )
            Button(onClick = onConfirm) { Text("Confirm") }
            TextButton(onClick = onCancel) { Text("Cancel") }
        }
    }
}

@Composable
private fun CommandInput(
    command: String,
    connected: Boolean,
    onCommandChange: (String) -> Unit,
    onSend: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        OutlinedTextField(
            value = command,
            onValueChange = onCommandChange,
            modifier = Modifier.weight(1f),
            label = { Text("Command") },
            minLines = 1,
            maxLines = 4,
        )
        Button(
            onClick = onSend,
            enabled = command.isNotBlank() && connected,
            colors = ButtonDefaults.buttonColors(containerColor = Accent),
        ) {
            Text("Send")
        }
    }
}

@Composable
private fun StatusPill(label: String, color: Color) {
    Surface(color = color.copy(alpha = 0.11f), shape = RoundedCornerShape(999.dp)) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp),
            color = color,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
    }
}

private data class AccessoryKey(val label: String, val bytes: String)

private val accessoryKeys = listOf(
    AccessoryKey("Esc", "\u001B"),
    AccessoryKey("Tab", "\t"),
    AccessoryKey("←", "\u001B[D"),
    AccessoryKey("↓", "\u001B[B"),
    AccessoryKey("↑", "\u001B[A"),
    AccessoryKey("→", "\u001B[C"),
    AccessoryKey("/", "/"),
    AccessoryKey("|", "|"),
    AccessoryKey("-", "-"),
)

private fun TerminalConnectionState.label(): String = when (this) {
    TerminalConnectionState.Connected -> "Connected"
    TerminalConnectionState.Connecting -> "Connecting"
    TerminalConnectionState.Disconnected -> "Disconnected"
    is TerminalConnectionState.Failed -> "Failed"
}

private fun TerminalConnectionState.color(): Color = when (this) {
    TerminalConnectionState.Connected -> Success
    TerminalConnectionState.Connecting -> Accent
    TerminalConnectionState.Disconnected -> Color(0xFF64748B)
    is TerminalConnectionState.Failed -> Color(0xFFDC2626)
}

private fun TerminalConnectionState.failureMessage(): String? = when (this) {
    is TerminalConnectionState.Failed -> message
    else -> null
}

private fun MobileKnownHost.pinPreview(): String =
    fingerprint?.takeIf { it.isNotBlank() } ?: publicKey.truncatedMiddle(52)

private fun String.truncatedMiddle(maxLength: Int): String {
    if (length <= maxLength || maxLength <= 8) {
        return this
    }
    val prefixLength = maxLength / 2 - 2
    val suffixLength = maxLength - prefixLength - 3
    return take(prefixLength) + "..." + takeLast(suffixLength)
}
