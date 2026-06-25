import Foundation

@MainActor
final class TerminalBuffer: ObservableObject {
    @Published private(set) var lines: [String] = []

    private let maxLines: Int
    private var rows: [String] = []
    private var row = 0
    private var column = 0

    init(maxLines: Int = 2_000) {
        self.maxLines = maxLines
    }

    func append(_ text: String) {
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\u{1B}" {
                index = consumeEscape(chars, from: index + 1)
                continue
            }

            switch char {
            case "\r":
                column = 0
            case "\n":
                newLine()
            case "\u{8}":
                column = max(0, column - 1)
            default:
                write(char)
            }
            index += 1
        }
        publish()
    }

    func clear() {
        rows.removeAll()
        row = 0
        column = 0
        lines.removeAll()
    }

    private func write(_ char: Character) {
        ensureRow()
        var current = rows[row]
        while current.count < column {
            current.append(" ")
        }
        if column == current.count {
            current.append(char)
        } else {
            let index = current.index(current.startIndex, offsetBy: column)
            current.replaceSubrange(index...index, with: String(char))
        }
        rows[row] = current
        column += 1
    }

    private func newLine() {
        row += 1
        column = 0
        ensureRow()
        trimScrollback()
    }

    private func ensureRow() {
        while rows.count <= row {
            rows.append("")
        }
    }

    private func consumeEscape(_ chars: [Character], from start: Int) -> Int {
        guard start < chars.count else {
            return start
        }
        guard chars[start] == "[" else {
            return start
        }

        var index = start + 1
        var parameters = ""
        while index < chars.count {
            let char = chars[index]
            if let scalar = char.unicodeScalars.first,
                scalar.value >= 0x40,
               scalar.value <= 0x7E {
                handleCsi(parameters: parameters, final: char)
                return index + 1
            }
            parameters.append(char)
            index += 1
        }
        return chars.count
    }

    private func handleCsi(parameters: String, final: Character) {
        let first = parameters
            .split(separator: ";")
            .first
            .map { $0.filter(\.isNumber) }
            .flatMap { Int($0) }

        switch final {
        case "m":
            break
        case "H", "f":
            row = 0
            column = 0
            ensureRow()
        case "J":
            if first == nil || first == 2 {
                rows.removeAll()
                row = 0
                column = 0
            }
        case "K":
            ensureRow()
            let current = rows[row]
            if column < current.count {
                let index = current.index(current.startIndex, offsetBy: column)
                rows[row] = String(current[..<index])
            }
        case "C":
            column += first ?? 1
        case "D":
            column = max(0, column - (first ?? 1))
        case "A":
            row = max(0, row - (first ?? 1))
        case "B":
            row += first ?? 1
            ensureRow()
        default:
            break
        }
    }

    private func trimScrollback() {
        guard rows.count > maxLines else {
            return
        }
        let removeCount = rows.count - maxLines
        rows.removeFirst(removeCount)
        row = max(0, row - removeCount)
    }

    private func publish() {
        trimScrollback()
        lines = Array(rows.suffix(maxLines))
    }
}
