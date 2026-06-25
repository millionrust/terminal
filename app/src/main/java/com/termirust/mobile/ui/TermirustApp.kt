package com.termirust.mobile.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.termirust.mobile.MobileHostViewModel
import com.termirust.mobile.data.MobileAuthKind
import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.ssh.TerminalConnectionState

@Composable
fun TermirustApp(
    viewModel: MobileHostViewModel,
    onImportVault: (String) -> Unit,
) {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Row(modifier = Modifier.fillMaxSize()) {
                HostList(
                    viewModel = viewModel,
                    onImportVault = onImportVault,
                    modifier = Modifier.weight(0.42f),
                )
                TerminalPane(viewModel = viewModel, modifier = Modifier.weight(0.58f))
            }
        }
    }
}

@Composable
private fun HostList(
    viewModel: MobileHostViewModel,
    onImportVault: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val vault by viewModel.vault.collectAsState()
    val status by viewModel.status.collectAsState()
    var vaultPassphrase by remember { mutableStateOf("") }
    Column(modifier = modifier.padding(16.dp)) {
        Text("TermiRust", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(12.dp))
        OutlinedTextField(
            value = vaultPassphrase,
            onValueChange = { vaultPassphrase = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Vault passphrase") },
            visualTransformation = PasswordVisualTransformation(),
        )
        Spacer(modifier = Modifier.height(8.dp))
        Button(
            onClick = { onImportVault(vaultPassphrase) },
            enabled = vaultPassphrase.isNotBlank(),
        ) {
            Text("Import Encrypted Vault")
        }
        status?.let {
            Spacer(modifier = Modifier.height(8.dp))
            Text(it, style = MaterialTheme.typography.bodySmall)
        }
        Spacer(modifier = Modifier.height(16.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(vault?.hosts.orEmpty(), key = { it.id }) { host ->
                HostRow(host = host, onClick = { viewModel.selectHost(host) })
            }
        }
    }
}

@Composable
private fun HostRow(host: MobileHost, onClick: () -> Unit) {
    Surface(onClick = onClick, tonalElevation = 1.dp, shape = MaterialTheme.shapes.medium) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp)) {
            Text(host.label, style = MaterialTheme.typography.titleMedium)
            Text("${host.username}@${host.host}:${host.port}", style = MaterialTheme.typography.bodySmall)
            if (host.persistentSession.enabled) {
                AssistChip(onClick = {}, label = { Text(host.persistentSession.sessionName ?: "tmux") })
            }
        }
    }
}

@Composable
private fun TerminalPane(viewModel: MobileHostViewModel, modifier: Modifier = Modifier) {
    val selectedHost by viewModel.selectedHost.collectAsState()
    val lines by viewModel.terminalBuffer.lines.collectAsState()
    val state by viewModel.connectionState.collectAsState()
    var command by remember { mutableStateOf("") }
    var credential by remember(selectedHost?.id) { mutableStateOf("") }

    Column(modifier = modifier.padding(16.dp)) {
        Text(selectedHost?.label ?: "No host selected", style = MaterialTheme.typography.headlineSmall)
        Text(state.label(), style = MaterialTheme.typography.bodySmall)
        Spacer(modifier = Modifier.height(8.dp))
        selectedHost?.let { host ->
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
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { viewModel.connectSelectedHost() }, enabled = selectedHost != null) {
                Text("Connect")
            }
            Button(onClick = { viewModel.disconnect() }, enabled = state != TerminalConnectionState.Disconnected) {
                Text("Disconnect")
            }
        }
        Spacer(modifier = Modifier.height(12.dp))
        LazyColumn(modifier = Modifier.weight(1f).fillMaxWidth()) {
            items(lines) { line ->
                Text(line.ifEmpty { " " }, fontFamily = FontFamily.Monospace)
            }
        }
        AccessoryRow(onSend = viewModel::sendTerminalBytes)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = command,
                onValueChange = { command = it },
                modifier = Modifier.weight(1f),
                label = { Text("Command") },
            )
            Button(
                onClick = {
                    viewModel.sendTerminalInput(command)
                    command = ""
                },
                enabled = command.isNotBlank() && state == TerminalConnectionState.Connected,
            ) {
                Text("Send")
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
) {
    val secretRef = host.auth.secretRef
    val label = when (host.auth.kind) {
        MobileAuthKind.Password -> "SSH password"
        MobileAuthKind.PrivateKey -> "Private key PEM"
    }

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            if (secretRef.isNullOrBlank()) {
                "No mobile secret reference exported for this host."
            } else {
                "Credential secret_ref: $secretRef"
            },
            style = MaterialTheme.typography.bodySmall,
        )
        OutlinedTextField(
            value = credential,
            onValueChange = onCredentialChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(label) },
            minLines = if (host.auth.kind == MobileAuthKind.PrivateKey) 3 else 1,
            visualTransformation = PasswordVisualTransformation(),
            enabled = !secretRef.isNullOrBlank(),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = onSave,
                enabled = !secretRef.isNullOrBlank() && credential.isNotBlank(),
            ) {
                Text("Save Credential")
            }
            Button(
                onClick = onDelete,
                enabled = !secretRef.isNullOrBlank(),
            ) {
                Text("Remove")
            }
        }
    }
}

@Composable
private fun AccessoryRow(onSend: (ByteArray) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(
            "Esc" to "\u001B",
            "Tab" to "\t",
            "Ctrl" to "",
            "Alt" to "",
            "←" to "\u001B[D",
            "↓" to "\u001B[B",
            "↑" to "\u001B[A",
            "→" to "\u001B[C",
            "/" to "/",
            "|" to "|",
            "-" to "-",
        ).forEach { (label, bytes) ->
            AssistChip(
                onClick = {
                    if (bytes.isNotEmpty()) {
                        onSend(bytes.encodeToByteArray())
                    }
                },
                label = { Text(label) },
            )
        }
    }
}

private fun TerminalConnectionState.label(): String = when (this) {
    TerminalConnectionState.Connected -> "Connected"
    TerminalConnectionState.Connecting -> "Connecting"
    TerminalConnectionState.Disconnected -> "Disconnected"
    is TerminalConnectionState.Failed -> message
}
