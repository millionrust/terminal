package com.termirust.mobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.termirust.mobile.controller.ControllerApp
import com.termirust.mobile.controller.ControllerViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val controller: ControllerViewModel = viewModel()
            ControllerApp(controller)
        }
    }
}
