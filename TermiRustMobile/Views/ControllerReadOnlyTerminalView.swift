import SwiftUI

struct ControllerReadOnlyTerminalView: View {
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
                                    Array(viewModel.screen.lines.enumerated()),
                                    id: \.offset
                                ) { index, line in
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(Color(white: 0.92))
                                        .textSelection(.enabled)
                                        .id(index)
                                }
                            }
                            Color.clear.frame(width: 1, height: 1).id("terminal-bottom")
                        }
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
