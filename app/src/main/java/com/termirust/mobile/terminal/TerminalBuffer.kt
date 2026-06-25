package com.termirust.mobile.terminal

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class TerminalBuffer(private val maxLines: Int = 2_000) {
    private val _lines = MutableStateFlow<List<String>>(emptyList())
    val lines: StateFlow<List<String>> = _lines

    fun append(text: String) {
        val updated = _lines.value + text.split('\n')
        _lines.value = if (updated.size > maxLines) {
            updated.takeLast(maxLines)
        } else {
            updated
        }
    }

    fun clear() {
        _lines.value = emptyList()
    }
}
