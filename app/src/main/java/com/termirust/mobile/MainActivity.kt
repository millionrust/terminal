package com.termirust.mobile

import android.os.Bundle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.compose.viewModel
import com.termirust.mobile.data.MobileVaultImporter
import com.termirust.mobile.data.NativeMobileVaultDecryptor
import com.termirust.mobile.security.KeystoreSecretStore
import com.termirust.mobile.ssh.DirectSshSessionClient
import com.termirust.mobile.ssh.MobileSshSecretProvider
import com.termirust.mobile.ui.TermirustApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val context = LocalContext.current.applicationContext
            val factory = remember {
                val secretStore = KeystoreSecretStore(context)
                val vaultImporter = MobileVaultImporter(decryptor = NativeMobileVaultDecryptor())
                val sshClient = DirectSshSessionClient(
                    secretProvider = MobileSshSecretProvider { reference ->
                        secretStore.readSecret(reference)?.toCharArray()
                    },
                )
                MobileHostViewModelFactory(vaultImporter, secretStore, sshClient)
            }
            val viewModel: MobileHostViewModel = viewModel(factory = factory)
            var pendingVaultPassphrase by remember { mutableStateOf("") }
            val vaultPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
                if (uri != null) {
                    runCatching {
                        requireNotNull(context.contentResolver.openInputStream(uri)) {
                            "Unable to open selected vault file."
                        }.use { input -> input.readBytes() }
                    }
                        .onSuccess { bytes ->
                            viewModel.importEncryptedVault(bytes, pendingVaultPassphrase.toCharArray())
                            pendingVaultPassphrase = ""
                        }
                        .onFailure { viewModel.reportStatus(it.message ?: "Unable to import selected vault file.") }
                }
            }
            val keyPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
                if (uri != null) {
                    runCatching {
                        requireNotNull(context.contentResolver.openInputStream(uri)) {
                            "Unable to open selected private key file."
                        }.use { input -> input.bufferedReader().readText() }
                    }
                        .onSuccess { key ->
                            viewModel.saveCredentialForSelectedHost(key)
                        }
                        .onFailure { viewModel.reportStatus(it.message ?: "Unable to import selected private key file.") }
                }
            }
            TermirustApp(
                viewModel = viewModel,
                onImportVault = { passphrase ->
                    pendingVaultPassphrase = passphrase
                    vaultPicker.launch(arrayOf("application/json", "application/octet-stream", "text/*", "*/*"))
                },
                onImportCredentialFile = {
                    keyPicker.launch(arrayOf("application/x-pem-file", "application/octet-stream", "text/*", "*/*"))
                },
            )
        }
    }
}

private class MobileHostViewModelFactory(
    private val vaultImporter: MobileVaultImporter,
    private val secretStore: KeystoreSecretStore,
    private val sshClient: DirectSshSessionClient,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
        if (modelClass.isAssignableFrom(MobileHostViewModel::class.java)) {
            return MobileHostViewModel(
                importer = vaultImporter,
                sshClient = sshClient,
                secretStore = secretStore,
            ) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class ${modelClass.name}")
    }
}
