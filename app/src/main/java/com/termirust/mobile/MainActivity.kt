package com.termirust.mobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.compose.viewModel
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
                val sshClient = DirectSshSessionClient(
                    secretProvider = MobileSshSecretProvider { reference ->
                        secretStore.readSecret(reference)?.toCharArray()
                    },
                )
                MobileHostViewModelFactory(sshClient)
            }
            val viewModel: MobileHostViewModel = viewModel(factory = factory)
            TermirustApp(viewModel = viewModel)
        }
    }
}

private class MobileHostViewModelFactory(
    private val sshClient: DirectSshSessionClient,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
        if (modelClass.isAssignableFrom(MobileHostViewModel::class.java)) {
            return MobileHostViewModel(sshClient = sshClient) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class ${modelClass.name}")
    }
}
