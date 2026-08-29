import SwiftUI

struct ControllerReadOnlyTerminalView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: ControllerTerminalViewModel
    let onClose: () -> Void
    @State private var followsOutput = true
    @State private var keyboardFocusRequest: UInt64 = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                terminalSurface
                if viewModel.canSendInput { inputBar }
            }
            .background(Color.black)
            .navigationTitle(ControllerPresentation.isolated(viewModel.sessionTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Label("Detach", systemImage: "xmark")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !viewModel.visibleHTTPURLs.isEmpty {
                        Menu {
                            ForEach(viewModel.visibleHTTPURLs, id: \.absoluteString) { url in
                                Button(url.absoluteString) { openURL(url) }
                            }
                        } label: {
                            Label("Open Link", systemImage: "link")
                        }
                    }
                    if viewModel.canSendInput {
                        Button { keyboardFocusRequest &+= 1 } label: {
                            Label("Show Keyboard", systemImage: "keyboard")
                        }
                    }
                    Button { followsOutput.toggle() } label: {
                        Label(
                            followsOutput ? "Following Output" : "Follow Output",
                            systemImage: followsOutput
                                ? "arrow.down.to.line.compact" : "arrow.down"
                        )
                    }
                }
            }
        }
        .tint(.green)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.detach() }
        .confirmationDialog(
            "Send pasted text to this terminal?",
            isPresented: Binding(
                get: { viewModel.pendingPasteByteCount > 0 },
                set: { if !$0 { viewModel.cancelPaste() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Send Paste") { viewModel.confirmPaste() }
            Button("Cancel", role: .cancel) { viewModel.cancelPaste() }
        } message: {
            Text("The paste contains multiple lines or is large (\(viewModel.pendingPasteByteCount) bytes). Review the destination before sending it.")
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { primaryStatusContent }
                VStack(alignment: .leading, spacing: 8) { primaryStatusContent }
            }
            if let message = viewModel.writerMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Terminal control warning. \(message)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var primaryStatusContent: some View {
        Label(writerLabel, systemImage: writerIcon)
            .font(.caption.weight(.bold))
            .foregroundStyle(writerColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(writerColor.opacity(0.12), in: Capsule())
            .accessibilityLabel("Terminal control status: \(writerLabel)")
        VStack(alignment: .leading, spacing: 2) {
            Text(ControllerPresentation.isolated(viewModel.hostTitle))
                .font(.subheadline.weight(.semibold))
            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        Spacer(minLength: 4)
        Text("Seq \(viewModel.outputSequence)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        if viewModel.writerLease == .held {
            Button("Release") { viewModel.releaseControl() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Returns this terminal to view-only mode")
        } else if viewModel.canRequestControl {
            Button("Request Control") { viewModel.requestControl() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Requests the single writer lease for this exact session")
        }
        if showsRetry {
            Button("Retry") { viewModel.retry() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var terminalSurface: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { reader in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if viewModel.screen.lines.allSatisfy(\.isEmpty) {
                                Text(emptyText)
                                    .foregroundStyle(Color.white.opacity(0.55))
                                    .padding(16)
                            } else {
                                ForEach(
                                    Array(viewModel.screen.contentCells.enumerated()),
                                    id: \.offset
                                ) { index, row in
                                    Text(attributedRow(row))
                                        .frame(minHeight: 15.5)
                                        .id(index)
                                }
                            }
                            Color.clear.frame(width: 1, height: 1).id("terminal-bottom")
                        }
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.black)
                    .onChange(of: viewModel.renderRevision) { _, _ in
                        guard followsOutput else { return }
                        withAnimation(.none) {
                            reader.scrollTo("terminal-bottom", anchor: .bottom)
                        }
                    }
                }
                ControllerTerminalInputView(
                    enabled: viewModel.canSendInput,
                    focusRequest: keyboardFocusRequest,
                    applicationCursor: viewModel.screen.applicationCursor,
                    onBytes: viewModel.sendKeyboardBytes,
                    onPaste: viewModel.requestPaste
                )
                .frame(width: 2, height: 2)
                .opacity(0.01)
                .accessibilityHidden(!viewModel.canSendInput)
                if viewModel.privacyCovered {
                    privacyCover
                }
            }
            .onAppear { updateViewport(for: geometry.size) }
            .onChange(of: geometry.size) { _, size in updateViewport(for: size) }
            .accessibilityElement(children: .contain)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Label("You control this session", systemImage: "hand.tap")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Spacer()
            Button { keyboardFocusRequest &+= 1 } label: {
                Label("Keyboard", systemImage: "keyboard")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private var privacyCover: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            Label("Terminal hidden while TermiRust is inactive", systemImage: "eye.slash")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Terminal content hidden for privacy")
    }

    private func updateViewport(for size: CGSize) {
        let columns = max(20, Int((size.width - 24) / 7.9))
        let rows = max(5, Int((size.height - 24) / 15.5))
        viewModel.updateViewport(columns: columns, rows: rows)
    }

    private func attributedRow(_ cells: [BoundedTerminalCell]) -> AttributedString {
        var row = AttributedString()
        for cell in cells where cell.width != .continuation {
            var segment = AttributedString(cell.text)
            let colors = resolvedColors(for: cell.style)
            segment.foregroundColor = colors.foreground
            segment.backgroundColor = colors.background
            var font = Font.system(size: 13, design: .monospaced)
            if cell.style.bold { font = font.weight(.bold) }
            if cell.style.italic { font = font.italic() }
            segment.font = font
            if cell.style.underline { segment.underlineStyle = .single }
            row.append(segment)
        }
        return row
    }

    private func resolvedColors(
        for style: TerminalCellStyle
    ) -> (foreground: Color, background: Color) {
        let normalForeground = terminalColor(style.foreground, default: Color(white: 0.92))
        let normalBackground = terminalColor(style.background, default: .black)
        let foreground = style.inverse ? normalBackground : normalForeground
        let background = style.inverse ? normalForeground : normalBackground
        return (
            style.dim ? foreground.opacity(0.55) : foreground,
            background
        )
    }

    private func terminalColor(_ color: TerminalCellColor, default fallback: Color) -> Color {
        switch color {
        case .default:
            fallback
        case .indexed(let value):
            ansiColor(Int(value))
        case .rgb(let red, let green, let blue):
            Color(
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255
            )
        }
    }

    private func ansiColor(_ index: Int) -> Color {
        let base: [(Double, Double, Double)] = [
            (0, 0, 0), (0.80, 0, 0), (0, 0.80, 0), (0.80, 0.80, 0),
            (0, 0, 0.80), (0.80, 0, 0.80), (0, 0.80, 0.80), (0.75, 0.75, 0.75),
            (0.50, 0.50, 0.50), (1, 0, 0), (0, 1, 0), (1, 1, 0),
            (0.35, 0.35, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)
        ]
        if base.indices.contains(index) {
            let value = base[index]
            return Color(red: value.0, green: value.1, blue: value.2)
        }
        if (16...231).contains(index) {
            let cube = index - 16
            let levels = [0, 95, 135, 175, 215, 255]
            return Color(
                red: Double(levels[cube / 36]) / 255,
                green: Double(levels[(cube / 6) % 6]) / 255,
                blue: Double(levels[cube % 6]) / 255
            )
        }
        let gray = Double(8 + max(0, min(23, index - 232)) * 10) / 255
        return Color(red: gray, green: gray, blue: gray)
    }

    private var writerLabel: String {
        guard viewModel.supportsWriterControl else { return "View Only" }
        switch viewModel.writerLease {
        case .none: return viewModel.hasWriterElsewhere ? "Controlled Elsewhere" : "View Only"
        case .requesting: return "Requesting Control"
        case .held: return "You Control"
        case .busy: return "Controlled Elsewhere"
        case .lost: return "Control Lost"
        }
    }

    private var writerIcon: String {
        switch viewModel.writerLease {
        case .held: "hand.tap.fill"
        case .requesting: "clock"
        case .busy: "person.crop.circle.badge.exclamationmark"
        case .lost: "exclamationmark.shield"
        case .none: "eye"
        }
    }

    private var writerColor: Color {
        switch viewModel.writerLease {
        case .held: .green
        case .requesting: .blue
        case .busy, .lost: .orange
        case .none: viewModel.hasWriterElsewhere ? .orange : .blue
        }
    }

    private var showsRetry: Bool {
        switch viewModel.attachState {
        case .offline, .gap, .failed: true
        default: false
        }
    }

    private var statusText: String {
        switch viewModel.attachState {
        case .detached: "Detached"
        case .authenticating: "Authenticating"
        case .snapshot: "Restoring retained screen"
        case .replaying: "Replaying output"
        case .live: viewModel.hasWriterElsewhere ? "Live - writer active elsewhere" : "Live"
        case .gap(let expected, let received):
            "Output gap - expected \(expected), received \(received)"
        case .exited: "Session exited - retained output"
        case .offline: "Offline - showing last screen"
        case .failed: "Terminal stopped at a safety limit"
        }
    }

    private var statusColor: Color {
        switch viewModel.attachState {
        case .live: .green
        case .gap, .failed: .orange
        case .offline, .exited: .secondary
        default: .blue
        }
    }

    private var emptyText: String {
        switch viewModel.attachState {
        case .authenticating, .snapshot, .replaying: "Waiting for terminal output..."
        case .live: "The session has not produced visible output."
        case .offline: "No retained screen is available while this Host is offline."
        case .failed: "Terminal output could not be rendered safely."
        default: "No terminal output."
        }
    }
}
