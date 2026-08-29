package com.termirust.mobile.controller

import java.nio.charset.StandardCharsets

enum class TerminalTruncationReason {
    FRAME_LIMIT,
    PARSER_CARRY_LIMIT,
    RETAINED_ROWS_LIMIT,
    RETAINED_CELLS_LIMIT,
    GRAPHEME_ARENA_LIMIT,
    STYLE_ARENA_LIMIT,
    MODEL_LIMIT,
}

enum class TerminalMouseMode(val wireName: String) {
    NONE("none"),
    PRESS("press"),
    PRESS_RELEASE("press_release"),
    BUTTON_MOTION("button_motion"),
    ANY_MOTION("any_motion"),
}

enum class TerminalMouseEncoding(val wireName: String) {
    DEFAULT("default"),
    UTF8("utf8"),
    SGR("sgr"),
}

data class BoundedTerminalSnapshot(
    val lines: List<String>,
    val cursorRow: Int,
    val cursorColumn: Int,
    val retainedCells: Int,
    val accountedBytes: Int,
    val truncation: TerminalTruncationReason?,
    val cursorVisible: Boolean,
    val applicationCursor: Boolean,
    val alternateScreen: Boolean,
    val bracketedPaste: Boolean,
    val mouseMode: TerminalMouseMode,
    val mouseEncoding: TerminalMouseEncoding,
    val scrollbackRows: Int,
)

class BoundedControllerTerminal(
    viewport: TerminalViewport,
    private val limits: TerminalLimits = TerminalLimits(),
) {
    private sealed interface ParserMode {
        data object Ground : ParserMode
        data object Escape : ParserMode
        data class Csi(val bytes: MutableList<Byte>) : ParserMode
        data class Osc(val count: Int, val escapePending: Boolean) : ParserMode
    }

    private data class StoredScreen(
        val rows: List<List<String>>,
        val cursorRow: Int,
        val cursorColumn: Int,
        val savedCursorRow: Int,
        val savedCursorColumn: Int,
        val retainedCells: Int,
        val graphemeBytes: Int,
        val styleBytes: Int,
    )

    var viewport: TerminalViewport = viewport
        private set
    private val rows = ArrayDeque<MutableList<String>>()
    private var cursorRow = 0
    private var cursorColumn = 0
    private var savedCursorRow = 0
    private var savedCursorColumn = 0
    private var mode: ParserMode = ParserMode.Ground
    private val utf8Carry = mutableListOf<Byte>()
    private var retainedCells = 0
    private var graphemeBytes = 0
    private var styleBytes = 0
    private var truncation: TerminalTruncationReason? = null
    private var primaryScreen: StoredScreen? = null
    private var cursorVisible = true
    private var applicationCursor = false
    private var alternateScreen = false
    private var bracketedPaste = false
    private var mouseMode = TerminalMouseMode.NONE
    private var mouseEncoding = TerminalMouseEncoding.DEFAULT

    init {
        limits.validate(viewport)
        repeat(viewport.rows) { rows.addLast(mutableListOf()) }
    }

    fun reset(nextViewport: TerminalViewport = viewport) {
        limits.validate(nextViewport)
        viewport = nextViewport
        rows.clear()
        repeat(nextViewport.rows) { rows.addLast(mutableListOf()) }
        cursorRow = 0
        cursorColumn = 0
        savedCursorRow = 0
        savedCursorColumn = 0
        mode = ParserMode.Ground
        utf8Carry.clear()
        retainedCells = 0
        graphemeBytes = 0
        styleBytes = 0
        truncation = null
        primaryScreen = null
        cursorVisible = true
        applicationCursor = false
        alternateScreen = false
        bracketedPaste = false
        mouseMode = TerminalMouseMode.NONE
        mouseEncoding = TerminalMouseEncoding.DEFAULT
    }

    fun resize(nextViewport: TerminalViewport) {
        limits.validate(nextViewport)
        viewport = nextViewport
        while (rows.size < nextViewport.rows) rows.addLast(mutableListOf())
        cursorRow = cursorRow.coerceIn(0, rows.lastIndex)
        cursorColumn = cursorColumn.coerceIn(0, nextViewport.columns - 1)
        enforceLimits()
    }

    fun process(bytes: ByteArray) {
        if (bytes.isEmpty()) return
        if (bytes.size > limits.maxFrameBytes) {
            truncation = TerminalTruncationReason.FRAME_LIMIT
            throw IllegalArgumentException("terminal frame exceeds limit")
        }
        for (byte in bytes) {
            consume(byte.toInt() and 0xff)
            if (parserCarryBytes > limits.maxParserCarryBytes) {
                mode = ParserMode.Ground
                utf8Carry.clear()
                truncation = TerminalTruncationReason.PARSER_CARRY_LIMIT
                enforceLimits()
                return
            }
        }
        enforceLimits()
    }

    fun snapshot(): BoundedTerminalSnapshot = BoundedTerminalSnapshot(
        lines = rows.map { it.joinToString("") },
        cursorRow = (cursorRow - scrollbackRows).coerceAtLeast(0),
        cursorColumn = cursorColumn,
        retainedCells = retainedCells,
        accountedBytes = accountedBytes,
        truncation = truncation,
        cursorVisible = cursorVisible,
        applicationCursor = applicationCursor,
        alternateScreen = alternateScreen,
        bracketedPaste = bracketedPaste,
        mouseMode = mouseMode,
        mouseEncoding = mouseEncoding,
        scrollbackRows = scrollbackRows,
    )

    private fun consume(byte: Int) {
        when (val current = mode) {
            ParserMode.Ground -> consumeGround(byte)
            ParserMode.Escape -> mode = when (byte) {
                0x5b -> ParserMode.Csi(mutableListOf())
                0x5d -> ParserMode.Osc(0, false)
                else -> ParserMode.Ground
            }
            is ParserMode.Csi -> {
                if (byte in 0x40..0x7e) {
                    executeCsi(byte, current.bytes)
                    mode = ParserMode.Ground
                } else {
                    current.bytes += byte.toByte()
                }
            }
            is ParserMode.Osc -> {
                mode = if (byte == 0x07 || current.escapePending && byte == 0x5c) {
                    ParserMode.Ground
                } else {
                    ParserMode.Osc(current.count.saturatedAdd(1), byte == 0x1b)
                }
            }
        }
    }

    private fun consumeGround(byte: Int) {
        when (byte) {
            0x1b -> { flushIncompleteUtf8(); mode = ParserMode.Escape }
            0x0a -> { flushIncompleteUtf8(); lineFeed() }
            0x0d -> { flushIncompleteUtf8(); cursorColumn = 0 }
            0x08 -> { flushIncompleteUtf8(); cursorColumn = (cursorColumn - 1).coerceAtLeast(0) }
            0x09 -> {
                flushIncompleteUtf8()
                cursorColumn = (((cursorColumn / 8) + 1) * 8).coerceAtMost(viewport.columns - 1)
            }
            in 0x00..0x1f, 0x7f -> flushIncompleteUtf8()
            else -> {
                utf8Carry += byte.toByte()
                consumeCompleteUtf8()
            }
        }
    }

    private fun consumeCompleteUtf8() {
        while (utf8Carry.isNotEmpty()) {
            val expected = utf8Length(utf8Carry.first().toInt() and 0xff)
            if (expected == 0) {
                utf8Carry.removeAt(0)
                write("\ufffd")
                continue
            }
            if (utf8Carry.size < expected) return
            val prefix = ByteArray(expected) { utf8Carry.removeAt(0) }
            val value = prefix.toString(StandardCharsets.UTF_8)
            if (value.toByteArray(StandardCharsets.UTF_8).contentEquals(prefix)) write(value) else write("\ufffd")
        }
    }

    private fun flushIncompleteUtf8() {
        if (utf8Carry.isEmpty()) return
        utf8Carry.clear()
        write("\ufffd")
    }

    private fun write(grapheme: String) {
        ensureCursorRow()
        if (cursorColumn >= viewport.columns) {
            cursorColumn = 0
            lineFeed()
        }
        ensureCursorRow()
        val row = rows[cursorRow]
        if (isCombining(grapheme) && cursorColumn > 0 && cursorColumn - 1 < row.size) {
            row[cursorColumn - 1] += grapheme
            graphemeBytes = graphemeBytes.saturatedAdd(grapheme.toByteArray().size)
            enforceLimits()
            return
        }
        while (row.size < cursorColumn) appendCell(row, " ")
        if (cursorColumn == row.size) {
            appendCell(row, grapheme)
        } else {
            graphemeBytes -= row[cursorColumn].toByteArray().size
            row[cursorColumn] = grapheme
            graphemeBytes = graphemeBytes.saturatedAdd(grapheme.toByteArray().size)
        }
        cursorColumn += 1
        enforceLimits()
    }

    private fun appendCell(row: MutableList<String>, value: String) {
        row += value
        retainedCells = retainedCells.saturatedAdd(1)
        graphemeBytes = graphemeBytes.saturatedAdd(value.toByteArray().size)
        styleBytes = styleBytes.saturatedAdd(1)
    }

    private fun lineFeed() {
        cursorRow += 1
        ensureCursorRow()
        enforceLimits()
    }

    private fun ensureCursorRow() {
        while (cursorRow >= rows.size) rows.addLast(mutableListOf())
    }

    private fun executeCsi(finalByte: Int, raw: List<Byte>) {
        val parameters = csiParameters(raw)
        val first = parameters.firstOrNull() ?: 0
        when (finalByte) {
            0x41 -> cursorRow = (cursorRow - first.coerceAtLeast(1)).coerceAtLeast(0)
            0x42 -> cursorRow = (cursorRow + first.coerceAtLeast(1)).coerceAtMost(rows.lastIndex)
            0x43 -> cursorColumn = (cursorColumn + first.coerceAtLeast(1)).coerceAtMost(viewport.columns - 1)
            0x44 -> cursorColumn = (cursorColumn - first.coerceAtLeast(1)).coerceAtLeast(0)
            0x45 -> { cursorRow = (cursorRow + first.coerceAtLeast(1)).coerceAtMost(rows.lastIndex); cursorColumn = 0 }
            0x46 -> { cursorRow = (cursorRow - first.coerceAtLeast(1)).coerceAtLeast(0); cursorColumn = 0 }
            0x47 -> cursorColumn = (first.coerceAtLeast(1) - 1).coerceAtMost(viewport.columns - 1)
            0x48, 0x66 -> {
                cursorRow = ((parameters.firstOrNull() ?: 1).coerceAtLeast(1) - 1).coerceAtMost(rows.lastIndex)
                cursorColumn = ((parameters.getOrNull(1) ?: 1).coerceAtLeast(1) - 1).coerceAtMost(viewport.columns - 1)
            }
            0x4a -> if (first == 2) clearScreen()
            0x4b -> clearLine(first)
            0x73 -> { savedCursorRow = cursorRow; savedCursorColumn = cursorColumn }
            0x75 -> {
                cursorRow = savedCursorRow.coerceAtMost(rows.lastIndex)
                cursorColumn = savedCursorColumn.coerceAtMost(viewport.columns - 1)
            }
            0x68 -> if (raw.firstOrNull()?.toInt() == 0x3f) setPrivateModes(parameters, true)
            0x6c -> if (raw.firstOrNull()?.toInt() == 0x3f) setPrivateModes(parameters, false)
        }
    }

    private fun setPrivateModes(modes: List<Int>, enabled: Boolean) {
        for (mode in modes) {
            when (mode) {
                1 -> applicationCursor = enabled
                9 -> updateMouseMode(TerminalMouseMode.PRESS, enabled)
                25 -> cursorVisible = enabled
                1000 -> updateMouseMode(TerminalMouseMode.PRESS_RELEASE, enabled)
                1002 -> updateMouseMode(TerminalMouseMode.BUTTON_MOTION, enabled)
                1003 -> updateMouseMode(TerminalMouseMode.ANY_MOTION, enabled)
                1005 -> updateMouseEncoding(TerminalMouseEncoding.UTF8, enabled)
                1006 -> updateMouseEncoding(TerminalMouseEncoding.SGR, enabled)
                1049 -> if (enabled) enterAlternateScreen() else leaveAlternateScreen()
                2004 -> bracketedPaste = enabled
            }
        }
    }

    private fun updateMouseMode(mode: TerminalMouseMode, enabled: Boolean) {
        if (enabled) mouseMode = mode else if (mouseMode == mode) mouseMode = TerminalMouseMode.NONE
    }

    private fun updateMouseEncoding(encoding: TerminalMouseEncoding, enabled: Boolean) {
        if (enabled) {
            mouseEncoding = encoding
        } else if (mouseEncoding == encoding) {
            mouseEncoding = TerminalMouseEncoding.DEFAULT
        }
    }

    private fun enterAlternateScreen() {
        if (alternateScreen) return
        primaryScreen = StoredScreen(
            rows = rows.map { it.toList() },
            cursorRow = cursorRow,
            cursorColumn = cursorColumn,
            savedCursorRow = savedCursorRow,
            savedCursorColumn = savedCursorColumn,
            retainedCells = retainedCells,
            graphemeBytes = graphemeBytes,
            styleBytes = styleBytes,
        )
        rows.clear()
        repeat(viewport.rows) { rows.addLast(mutableListOf()) }
        cursorRow = 0
        cursorColumn = 0
        savedCursorRow = 0
        savedCursorColumn = 0
        retainedCells = 0
        graphemeBytes = 0
        styleBytes = 0
        alternateScreen = true
    }

    private fun leaveAlternateScreen() {
        if (!alternateScreen) return
        primaryScreen?.let { primary ->
            rows.clear()
            primary.rows.forEach { rows.addLast(it.toMutableList()) }
            cursorRow = primary.cursorRow
            cursorColumn = primary.cursorColumn
            savedCursorRow = primary.savedCursorRow
            savedCursorColumn = primary.savedCursorColumn
            retainedCells = primary.retainedCells
            graphemeBytes = primary.graphemeBytes
            styleBytes = primary.styleBytes
        }
        primaryScreen = null
        alternateScreen = false
    }

    private fun clearScreen() {
        rows.clear()
        repeat(viewport.rows) { rows.addLast(mutableListOf()) }
        retainedCells = 0
        graphemeBytes = 0
        styleBytes = 0
        cursorRow = 0
        cursorColumn = 0
    }

    private fun clearLine(mode: Int) {
        ensureCursorRow()
        val row = rows[cursorRow]
        when (mode) {
            1 -> {
                val end = (cursorColumn + 1).coerceAtMost(row.size)
                repeat(end) { index -> replaceCell(row, index, " ") }
            }
            2 -> removeCells(row, 0, row.size)
            else -> if (cursorColumn < row.size) removeCells(row, cursorColumn, row.size)
        }
    }

    private fun replaceCell(row: MutableList<String>, index: Int, value: String) {
        graphemeBytes -= row[index].toByteArray().size
        row[index] = value
        graphemeBytes = graphemeBytes.saturatedAdd(value.toByteArray().size)
    }

    private fun removeCells(row: MutableList<String>, start: Int, end: Int) {
        if (start >= end) return
        for (index in end - 1 downTo start) {
            val removed = row.removeAt(index)
            retainedCells -= 1
            graphemeBytes -= removed.toByteArray().size
            styleBytes -= 1
        }
    }

    private fun enforceLimits() {
        while (alternateScreen && rows.size > viewport.rows) evictOldestRow()
        var evictedForRows = false
        while (rows.size > viewport.rows && (
                scrollbackRows > limits.maxScrollbackRows ||
                    retainedCells > limits.maxRetainedCells ||
                    graphemeBytes > limits.maxGraphemeBytes ||
                    styleBytes > limits.maxStyleBytes ||
                    accountedBytes > limits.maxModelBytes
                )) {
            if (scrollbackRows > limits.maxScrollbackRows) evictedForRows = true
            evictOldestRow()
        }
        if (evictedForRows) truncation = TerminalTruncationReason.RETAINED_ROWS_LIMIT
        if (retainedCells > limits.maxRetainedCells || graphemeBytes > limits.maxGraphemeBytes ||
            styleBytes > limits.maxStyleBytes || accountedBytes > limits.maxModelBytes
        ) truncateActiveRow()
    }

    private fun evictOldestRow() {
        val removed = rows.removeFirst()
        retainedCells -= removed.size
        graphemeBytes -= removed.sumOf { it.toByteArray().size }
        styleBytes -= removed.size
        cursorRow = (cursorRow - 1).coerceAtLeast(0)
        savedCursorRow = (savedCursorRow - 1).coerceAtLeast(0)
    }

    private fun truncateActiveRow() {
        ensureCursorRow()
        truncation = when {
            retainedCells > limits.maxRetainedCells -> TerminalTruncationReason.RETAINED_CELLS_LIMIT
            graphemeBytes > limits.maxGraphemeBytes -> TerminalTruncationReason.GRAPHEME_ARENA_LIMIT
            styleBytes > limits.maxStyleBytes -> TerminalTruncationReason.STYLE_ARENA_LIMIT
            else -> TerminalTruncationReason.MODEL_LIMIT
        }
        val row = rows[cursorRow]
        while (row.isNotEmpty() && (
                retainedCells > limits.maxRetainedCells || graphemeBytes > limits.maxGraphemeBytes ||
                    styleBytes > limits.maxStyleBytes || accountedBytes > limits.maxModelBytes
                )) {
            val removed = row.removeAt(row.lastIndex)
            retainedCells -= 1
            graphemeBytes -= removed.toByteArray().size
            styleBytes -= 1
        }
        if (row.size < viewport.columns && canAppendReplacement()) appendCell(row, "\ufffd")
        cursorColumn = row.size.coerceAtMost(viewport.columns - 1)
    }

    private fun canAppendReplacement(): Boolean {
        if (retainedCells >= limits.maxRetainedCells || graphemeBytes > limits.maxGraphemeBytes - 3 ||
            styleBytes >= limits.maxStyleBytes
        ) return false
        return accountedBytes <= limits.maxModelBytes - 20
    }

    private val scrollbackRows: Int get() = (rows.size - viewport.rows).coerceAtLeast(0)
    private val parserCarryBytes: Int get() = when (val current = mode) {
        is ParserMode.Csi -> current.bytes.size.saturatedAdd(utf8Carry.size)
        is ParserMode.Osc -> current.count.saturatedAdd(utf8Carry.size)
        else -> utf8Carry.size
    }
    private val accountedBytes: Int get() = graphemeBytes
        .saturatedAdd(styleBytes)
        .saturatedAdd(retainedCells.saturatedMultiply(16))
        .saturatedAdd(parserCarryBytes)

    private fun csiParameters(bytes: List<Byte>): List<Int> = bytes.toByteArray()
        .toString(StandardCharsets.UTF_8)
        .trim('?', '<', '>', '!')
        .split(';')
        .map { it.toIntOrNull() ?: 0 }

    private fun utf8Length(byte: Int): Int = when (byte) {
        in 0x00..0x7f -> 1
        in 0xc2..0xdf -> 2
        in 0xe0..0xef -> 3
        in 0xf0..0xf4 -> 4
        else -> 0
    }

    private fun isCombining(value: String): Boolean {
        if (value.isEmpty()) return false
        return when (Character.getType(value.codePointAt(0))) {
            Character.NON_SPACING_MARK.toInt(),
            Character.COMBINING_SPACING_MARK.toInt(),
            Character.ENCLOSING_MARK.toInt(), -> true
            else -> false
        }
    }
}

private fun Int.saturatedAdd(other: Int): Int = if (this > Int.MAX_VALUE - other) Int.MAX_VALUE else this + other
private fun Int.saturatedMultiply(other: Int): Int = if (this > Int.MAX_VALUE / other) Int.MAX_VALUE else this * other
