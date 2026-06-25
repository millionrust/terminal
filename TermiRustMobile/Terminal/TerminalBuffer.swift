import Foundation

@MainActor
final class TerminalBuffer: ObservableObject {
    @Published private(set) var lines: [String] = []

    private let maxLines: Int

    init(maxLines: Int = 2_000) {
        self.maxLines = maxLines
    }

    func append(_ text: String) {
        let newLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.append(contentsOf: newLines)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func clear() {
        lines.removeAll()
    }
}
