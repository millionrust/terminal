import Foundation

enum TerminalTruncationReason: Equatable, Sendable {
    case frameLimit
    case parserCarryLimit
    case retainedRowsLimit
    case retainedCellsLimit
    case graphemeArenaLimit
    case styleArenaLimit
    case modelLimit
}

enum TerminalMouseMode: String, Equatable, Sendable {
    case none
    case press
    case pressRelease = "press_release"
    case buttonMotion = "button_motion"
    case anyMotion = "any_motion"
}

enum TerminalMouseEncoding: String, Equatable, Sendable {
    case `default`
    case utf8
    case sgr
}

struct BoundedTerminalSnapshot: Equatable, Sendable {
    let lines: [String]
    let cursorRow: Int
    let cursorColumn: Int
    let retainedCells: Int
    let accountedBytes: Int
    let truncation: TerminalTruncationReason?
    let cursorVisible: Bool
    let applicationCursor: Bool
    let alternateScreen: Bool
    let bracketedPaste: Bool
    let mouseMode: TerminalMouseMode
    let mouseEncoding: TerminalMouseEncoding
    let scrollbackRows: Int
}

struct BoundedTerminalBuffer: Sendable {
    private enum ParserMode: Sendable {
        case ground
        case escape
        case csi([UInt8])
        case osc(count: Int, escapePending: Bool)
    }

    private struct StoredScreen: Sendable {
        let rows: [[String]]
        let cursorRow: Int
        let cursorColumn: Int
        let savedCursor: (row: Int, column: Int)
        let retainedCellCount: Int
        let graphemeByteCount: Int
        let styleByteCount: Int
    }

    private let limits: TerminalLimits
    private(set) var viewport: TerminalViewportState
    private var rows: [[String]]
    private var cursorRow = 0
    private var cursorColumn = 0
    private var savedCursor = (row: 0, column: 0)
    private var mode: ParserMode = .ground
    private var utf8Carry = Data()
    private var retainedCellCount = 0
    private var graphemeByteCount = 0
    private var styleByteCount = 0
    private(set) var truncation: TerminalTruncationReason?
    private var primaryScreen: StoredScreen?
    private var cursorVisible = true
    private var applicationCursor = false
    private var alternateScreen = false
    private var bracketedPaste = false
    private var mouseMode = TerminalMouseMode.none
    private var mouseEncoding = TerminalMouseEncoding.default

    init(
        viewport: TerminalViewportState,
        limits: TerminalLimits = .controllerDefault
    ) throws {
        try limits.validate(viewport: viewport)
        self.limits = limits
        self.viewport = viewport
        self.rows = Array(repeating: [], count: viewport.rows)
    }

    mutating func reset(viewport: TerminalViewportState? = nil) throws {
        let next = viewport ?? self.viewport
        try limits.validate(viewport: next)
        self.viewport = next
        rows = Array(repeating: [], count: next.rows)
        cursorRow = 0
        cursorColumn = 0
        savedCursor = (0, 0)
        mode = .ground
        utf8Carry.removeAll(keepingCapacity: true)
        retainedCellCount = 0
        graphemeByteCount = 0
        styleByteCount = 0
        truncation = nil
        primaryScreen = nil
        cursorVisible = true
        applicationCursor = false
        alternateScreen = false
        bracketedPaste = false
        mouseMode = .none
        mouseEncoding = .default
    }

    mutating func resize(_ viewport: TerminalViewportState) throws {
        try limits.validate(viewport: viewport)
        self.viewport = viewport
        while rows.count < viewport.rows { rows.append([]) }
        cursorRow = min(cursorRow, rows.count - 1)
        cursorColumn = min(cursorColumn, viewport.columns - 1)
        enforceLimits()
    }

    mutating func process(_ data: Data) throws {
        guard !data.isEmpty else { return }
        guard data.count <= limits.maxFrameBytes else {
            truncation = .frameLimit
            throw ReadOnlyAttachFailure.frameTooLarge
        }
        for byte in data {
            consume(byte)
            guard parserCarryBytes <= limits.maxParserCarryBytes else {
                mode = .ground
                utf8Carry.removeAll(keepingCapacity: true)
                truncation = .parserCarryLimit
                enforceLimits()
                return
            }
        }
        enforceLimits()
    }

    func snapshot() -> BoundedTerminalSnapshot {
        BoundedTerminalSnapshot(
            lines: rows.map { $0.joined() },
            cursorRow: max(0, cursorRow - scrollbackRows),
            cursorColumn: cursorColumn,
            retainedCells: retainedCellCount,
            accountedBytes: accountedBytes,
            truncation: truncation,
            cursorVisible: cursorVisible,
            applicationCursor: applicationCursor,
            alternateScreen: alternateScreen,
            bracketedPaste: bracketedPaste,
            mouseMode: mouseMode,
            mouseEncoding: mouseEncoding,
            scrollbackRows: scrollbackRows
        )
    }

    private mutating func consume(_ byte: UInt8) {
        switch mode {
        case .ground:
            consumeGround(byte)
        case .escape:
            switch byte {
            case 0x5B: mode = .csi([])
            case 0x5D: mode = .osc(count: 0, escapePending: false)
            default: mode = .ground
            }
        case .csi(var bytes):
            if (0x40...0x7E).contains(byte) {
                executeCSI(final: byte, bytes: bytes)
                mode = .ground
            } else {
                bytes.append(byte)
                mode = .csi(bytes)
            }
        case .osc(let count, let escapePending):
            if byte == 0x07 || (escapePending && byte == 0x5C) {
                mode = .ground
            } else {
                mode = .osc(
                    count: count.saturatingAdd(1),
                    escapePending: byte == 0x1B
                )
            }
        }
    }

    private mutating func consumeGround(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            flushIncompleteUTF8()
            mode = .escape
        case 0x0A:
            flushIncompleteUTF8()
            lineFeed()
        case 0x0D:
            flushIncompleteUTF8()
            cursorColumn = 0
        case 0x08:
            flushIncompleteUTF8()
            cursorColumn = max(0, cursorColumn - 1)
        case 0x09:
            flushIncompleteUTF8()
            cursorColumn = min(viewport.columns - 1, ((cursorColumn / 8) + 1) * 8)
        case 0x00...0x1F, 0x7F:
            flushIncompleteUTF8()
        default:
            utf8Carry.append(byte)
            consumeCompleteUTF8()
        }
    }

    private mutating func consumeCompleteUTF8() {
        while let first = utf8Carry.first {
            let expected = utf8Length(first)
            if expected == 0 {
                utf8Carry.removeFirst()
                write("\u{FFFD}")
                continue
            }
            guard utf8Carry.count >= expected else { return }
            let prefix = Data(utf8Carry.prefix(expected))
            utf8Carry.removeFirst(expected)
            guard let value = String(data: prefix, encoding: .utf8), !value.isEmpty else {
                write("\u{FFFD}")
                continue
            }
            for character in value { write(String(character)) }
        }
    }

    private mutating func flushIncompleteUTF8() {
        guard !utf8Carry.isEmpty else { return }
        utf8Carry.removeAll(keepingCapacity: true)
        write("\u{FFFD}")
    }

    private mutating func write(_ grapheme: String) {
        ensureCursorRow()
        if cursorColumn >= viewport.columns {
            cursorColumn = 0
            lineFeed()
        }
        ensureCursorRow()
        let line = rows[cursorRow]
        if isCombining(grapheme), cursorColumn > 0, cursorColumn - 1 < line.count {
            rows[cursorRow][cursorColumn - 1].append(grapheme)
            graphemeByteCount = graphemeByteCount.saturatingAdd(grapheme.utf8.count)
            enforceLimits()
            return
        }
        while rows[cursorRow].count < cursorColumn {
            rows[cursorRow].append(" ")
            retainedCellCount = retainedCellCount.saturatingAdd(1)
            graphemeByteCount = graphemeByteCount.saturatingAdd(1)
            styleByteCount = styleByteCount.saturatingAdd(1)
        }
        if cursorColumn == rows[cursorRow].count {
            rows[cursorRow].append(grapheme)
            retainedCellCount = retainedCellCount.saturatingAdd(1)
            graphemeByteCount = graphemeByteCount.saturatingAdd(grapheme.utf8.count)
            styleByteCount = styleByteCount.saturatingAdd(1)
        } else {
            graphemeByteCount -= rows[cursorRow][cursorColumn].utf8.count
            rows[cursorRow][cursorColumn] = grapheme
            graphemeByteCount = graphemeByteCount.saturatingAdd(grapheme.utf8.count)
        }
        cursorColumn += 1
        enforceLimits()
    }

    private mutating func lineFeed() {
        cursorRow += 1
        if cursorRow >= rows.count { rows.append([]) }
        enforceLimits()
    }

    private mutating func ensureCursorRow() {
        while cursorRow >= rows.count { rows.append([]) }
    }

    private mutating func executeCSI(final: UInt8, bytes: [UInt8]) {
        let parameters = csiParameters(bytes)
        let first = parameters.first ?? 0
        switch final {
        case 0x41: cursorRow = max(0, cursorRow - max(first, 1))
        case 0x42:
            cursorRow = min(rows.count - 1, cursorRow + max(first, 1))
        case 0x43: cursorColumn = min(viewport.columns - 1, cursorColumn + max(first, 1))
        case 0x44: cursorColumn = max(0, cursorColumn - max(first, 1))
        case 0x45:
            cursorRow = min(rows.count - 1, cursorRow + max(first, 1))
            cursorColumn = 0
        case 0x46:
            cursorRow = max(0, cursorRow - max(first, 1))
            cursorColumn = 0
        case 0x47: cursorColumn = min(viewport.columns - 1, max(first, 1) - 1)
        case 0x48, 0x66:
            cursorRow = min(rows.count - 1, max(parameters.first ?? 1, 1) - 1)
            cursorColumn = min(viewport.columns - 1, max(parameters.dropFirst().first ?? 1, 1) - 1)
        case 0x4A where first == 2: clearScreen()
        case 0x4B: clearLine(mode: first)
        case 0x73: savedCursor = (cursorRow, cursorColumn)
        case 0x75:
            cursorRow = min(savedCursor.row, rows.count - 1)
            cursorColumn = min(savedCursor.column, viewport.columns - 1)
        case 0x68 where bytes.first == 0x3F:
            setPrivateModes(parameters, enabled: true)
        case 0x6C where bytes.first == 0x3F:
            setPrivateModes(parameters, enabled: false)
        default: break
        }
    }

    private mutating func setPrivateModes(_ modes: [Int], enabled: Bool) {
        for mode in modes {
            switch mode {
            case 1:
                applicationCursor = enabled
            case 9:
                updateMouseMode(.press, enabled: enabled)
            case 25:
                cursorVisible = enabled
            case 1000:
                updateMouseMode(.pressRelease, enabled: enabled)
            case 1002:
                updateMouseMode(.buttonMotion, enabled: enabled)
            case 1003:
                updateMouseMode(.anyMotion, enabled: enabled)
            case 1005:
                updateMouseEncoding(.utf8, enabled: enabled)
            case 1006:
                updateMouseEncoding(.sgr, enabled: enabled)
            case 1049:
                if enabled { enterAlternateScreen() } else { leaveAlternateScreen() }
            case 2004:
                bracketedPaste = enabled
            default:
                break
            }
        }
    }

    private mutating func updateMouseMode(_ mode: TerminalMouseMode, enabled: Bool) {
        if enabled {
            mouseMode = mode
        } else if mouseMode == mode {
            mouseMode = .none
        }
    }

    private mutating func updateMouseEncoding(
        _ encoding: TerminalMouseEncoding,
        enabled: Bool
    ) {
        if enabled {
            mouseEncoding = encoding
        } else if mouseEncoding == encoding {
            mouseEncoding = .default
        }
    }

    private mutating func enterAlternateScreen() {
        guard !alternateScreen else { return }
        primaryScreen = StoredScreen(
            rows: rows,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            savedCursor: savedCursor,
            retainedCellCount: retainedCellCount,
            graphemeByteCount: graphemeByteCount,
            styleByteCount: styleByteCount
        )
        rows = Array(repeating: [], count: viewport.rows)
        cursorRow = 0
        cursorColumn = 0
        savedCursor = (0, 0)
        retainedCellCount = 0
        graphemeByteCount = 0
        styleByteCount = 0
        alternateScreen = true
    }

    private mutating func leaveAlternateScreen() {
        guard alternateScreen else { return }
        if let primaryScreen {
            rows = primaryScreen.rows
            cursorRow = primaryScreen.cursorRow
            cursorColumn = primaryScreen.cursorColumn
            savedCursor = primaryScreen.savedCursor
            retainedCellCount = primaryScreen.retainedCellCount
            graphemeByteCount = primaryScreen.graphemeByteCount
            styleByteCount = primaryScreen.styleByteCount
        }
        primaryScreen = nil
        alternateScreen = false
    }

    private mutating func clearScreen() {
        rows = Array(repeating: [], count: viewport.rows)
        retainedCellCount = 0
        graphemeByteCount = 0
        styleByteCount = 0
        cursorRow = 0
        cursorColumn = 0
    }

    private mutating func clearLine(mode: Int) {
        ensureCursorRow()
        switch mode {
        case 1:
            let end = min(cursorColumn + 1, rows[cursorRow].count)
            if end > 0 {
                graphemeByteCount -= rows[cursorRow][0..<end].reduce(0) { $0 + $1.utf8.count }
                graphemeByteCount = graphemeByteCount.saturatingAdd(end)
                rows[cursorRow].replaceSubrange(0..<end, with: repeatElement(" ", count: end))
            }
        case 2:
            removeCells(in: 0..<rows[cursorRow].count, from: cursorRow)
        default:
            if cursorColumn < rows[cursorRow].count {
                removeCells(in: cursorColumn..<rows[cursorRow].count, from: cursorRow)
            }
        }
    }

    private mutating func enforceLimits() {
        while alternateScreen && rows.count > viewport.rows {
            evictOldestRow()
        }
        while rows.count > viewport.rows,
              (scrollbackRows > limits.maxScrollbackRows
                  || retainedCellCount > limits.maxRetainedCells
                  || graphemeByteCount > limits.maxGraphemeBytes
                  || styleByteCount > limits.maxStyleBytes
                  || accountedBytes > limits.maxModelBytes) {
            evictOldestRow()
        }
        guard retainedCellCount <= limits.maxRetainedCells,
              graphemeByteCount <= limits.maxGraphemeBytes,
              styleByteCount <= limits.maxStyleBytes,
              accountedBytes <= limits.maxModelBytes else {
            truncateActiveRow()
            return
        }
        if scrollbackRows > limits.maxScrollbackRows { truncation = .retainedRowsLimit }
    }

    private mutating func evictOldestRow() {
        let removed = rows.removeFirst()
        retainedCellCount -= removed.count
        graphemeByteCount -= removed.reduce(0) { $0 + $1.utf8.count }
        styleByteCount -= removed.count
        cursorRow = max(0, cursorRow - 1)
        savedCursor.row = max(0, savedCursor.row - 1)
    }

    private mutating func truncateActiveRow() {
        ensureCursorRow()
        let reason: TerminalTruncationReason
        if retainedCellCount > limits.maxRetainedCells { reason = .retainedCellsLimit }
        else if graphemeByteCount > limits.maxGraphemeBytes { reason = .graphemeArenaLimit }
        else if styleByteCount > limits.maxStyleBytes { reason = .styleArenaLimit }
        else { reason = .modelLimit }
        truncation = reason
        while !rows[cursorRow].isEmpty,
              (retainedCellCount > limits.maxRetainedCells
                  || graphemeByteCount > limits.maxGraphemeBytes
                  || styleByteCount > limits.maxStyleBytes
                  || accountedBytes > limits.maxModelBytes) {
            let removed = rows[cursorRow].removeLast()
            retainedCellCount -= 1
            graphemeByteCount -= removed.utf8.count
            styleByteCount -= 1
        }
        if rows[cursorRow].count < viewport.columns {
            rows[cursorRow].append("\u{FFFD}")
            retainedCellCount = retainedCellCount.saturatingAdd(1)
            graphemeByteCount = graphemeByteCount.saturatingAdd(3)
            styleByteCount = styleByteCount.saturatingAdd(1)
        }
        cursorColumn = min(rows[cursorRow].count, viewport.columns - 1)
    }

    private var scrollbackRows: Int { max(0, rows.count - viewport.rows) }
    private var parserCarryBytes: Int {
        let modeBytes = switch mode {
        case .csi(let bytes): bytes.count
        case .osc(let count, _): count
        default: 0
        }
        return modeBytes.saturatingAdd(utf8Carry.count)
    }
    private var accountedBytes: Int {
        graphemeByteCount
            .saturatingAdd(styleByteCount)
            .saturatingAdd(retainedCellCount.saturatingMultiply(16))
            .saturatingAdd(parserCarryBytes)
    }

    private mutating func removeCells(in range: Range<Int>, from row: Int) {
        guard !range.isEmpty else { return }
        graphemeByteCount -= rows[row][range].reduce(0) { $0 + $1.utf8.count }
        retainedCellCount -= range.count
        styleByteCount -= range.count
        rows[row].removeSubrange(range)
    }

    private func csiParameters(_ bytes: [UInt8]) -> [Int] {
        String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?<>!"))
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
    }

    private func utf8Length(_ byte: UInt8) -> Int {
        switch byte {
        case 0x00...0x7F: 1
        case 0xC2...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF4: 4
        default: 0
        }
    }

    private func isCombining(_ value: String) -> Bool {
        !value.unicodeScalars.isEmpty
            && value.unicodeScalars.allSatisfy {
                CharacterSet.nonBaseCharacters.contains($0)
            }
    }
}

private extension Int {
    func saturatingAdd(_ value: Int) -> Int {
        addingReportingOverflow(value).overflow ? .max : self + value
    }

    func saturatingMultiply(_ value: Int) -> Int {
        multipliedReportingOverflow(by: value).overflow ? .max : self * value
    }
}
