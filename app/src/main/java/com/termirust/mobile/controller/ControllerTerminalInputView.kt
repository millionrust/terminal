package com.termirust.mobile.controller

import android.content.Context
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

private class ControllerTerminalInputBridge(context: Context) : View(context) {
    var acceptsInput: Boolean = false
    var onBytes: (ByteArray) -> Unit = {}
    private var composing: String = ""

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        importantForAutofill = IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
            InputType.TYPE_TEXT_FLAG_MULTI_LINE
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_ACTION_NONE
        return object : BaseInputConnection(this@ControllerTerminalInputBridge, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                composing = ""
                text?.toString()?.takeIf(String::isNotEmpty)?.let(::sendText)
                return true
            }

            override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
                composing = text?.toString().orEmpty()
                return true
            }

            override fun finishComposingText(): Boolean {
                composing.takeIf(String::isNotEmpty)?.let(::sendText)
                composing = ""
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                if (beforeLength > 0) send(byteArrayOf(0x7f))
                return true
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean = handleKey(event) || super.sendKeyEvent(event)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = handleKey(event) || super.onKeyDown(keyCode, event)

    fun showKeyboard() {
        if (!acceptsInput) return
        requestFocus()
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun handleKey(event: KeyEvent): Boolean {
        if (!acceptsInput || event.action != KeyEvent.ACTION_DOWN) return false
        val fixed = when (event.keyCode) {
            KeyEvent.KEYCODE_ENTER -> byteArrayOf('\r'.code.toByte())
            KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL -> byteArrayOf(0x7f)
            KeyEvent.KEYCODE_TAB -> byteArrayOf('\t'.code.toByte())
            KeyEvent.KEYCODE_ESCAPE -> byteArrayOf(0x1b)
            KeyEvent.KEYCODE_DPAD_UP -> "\u001b[A".encodeToByteArray()
            KeyEvent.KEYCODE_DPAD_DOWN -> "\u001b[B".encodeToByteArray()
            KeyEvent.KEYCODE_DPAD_RIGHT -> "\u001b[C".encodeToByteArray()
            KeyEvent.KEYCODE_DPAD_LEFT -> "\u001b[D".encodeToByteArray()
            else -> null
        }
        if (fixed != null) {
            send(fixed)
            return true
        }
        val unicode = event.unicodeChar
        if (unicode == 0) return false
        var bytes = if (event.isCtrlPressed && unicode.toChar().uppercaseChar() in 'A'..'Z') {
            byteArrayOf((unicode.toChar().uppercaseChar().code - 'A'.code + 1).toByte())
        } else {
            String(Character.toChars(unicode)).encodeToByteArray()
        }
        if (event.isAltPressed) bytes = byteArrayOf(0x1b) + bytes
        send(bytes)
        return true
    }

    private fun sendText(value: String) = send(value.encodeToByteArray())
    private fun send(bytes: ByteArray) {
        if (acceptsInput && bytes.isNotEmpty()) onBytes(bytes)
    }
}

@Composable
fun ControllerTerminalInputView(
    enabled: Boolean,
    focusRequest: Long,
    onBytes: (ByteArray) -> Unit,
    modifier: Modifier = Modifier,
) {
    val bridge = remember { arrayOfNulls<ControllerTerminalInputBridge>(1) }
    AndroidView(
        modifier = modifier,
        factory = { context -> ControllerTerminalInputBridge(context).also { bridge[0] = it } },
        update = {
            bridge[0] = it
            it.acceptsInput = enabled
            it.onBytes = onBytes
            if (!enabled) it.clearFocus()
        },
    )
    LaunchedEffect(focusRequest, enabled) {
        if (enabled && focusRequest > 0) bridge[0]?.showKeyboard()
    }
}
