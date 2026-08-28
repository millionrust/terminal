import SwiftUI

struct ControllerReadOnlyTerminalView: View {
    @ObservedObject var viewModel: ControllerTerminalViewModel
    let onClose: () -> Void
    @State private var followsOutput = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                terminalSurface
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
                ToolbarItem(placement: .primaryAction) {
                    Button { followsOutput.toggle() } label: {
                        Label(
                            followsOutput ? "Following Output" : "Follow Output",
                            systemImage: followsOutput ? "arrow.down.to.line.compact" : "arrow.down"
                        )
                    }
                }
            }
        }
        .tint(.green)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.detach() }
    }

    private var statusBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { statusContent }
            VStack(alignment: .leading, spacing: 8) { statusContent }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var statusContent: some View {
        Label("View Only", systemImage: "eye")
            .font(.caption.weight(.bold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.12), in: Capsule())
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
        if showsRetry {
            Button("Retry") { viewModel.retry() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var terminalSurface: some View {
        ScrollViewReader { reader in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.screen.lines.allSatisfy(\.isEmpty) {
                        Text(emptyText)
                            .foregroundStyle(Color.white.opacity(0.55))
                            .padding(16)
                    } else {
                        ForEach(Array(viewModel.screen.lines.enumerated()), id: \.offset) { index, line in
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
                withAnimation(.none) { reader.scrollTo("terminal-bottom", anchor: .bottom) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Read-only terminal output")
            .accessibilityValue(accessibilityOutput)
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
        case .live: viewModel.hasWriterElsewhere ? "Live · writer active elsewhere" : "Live"
        case .gap(let expected, let received): "Output gap · expected \(expected), received \(received)"
        case .exited: "Session exited · retained output"
        case .offline: "Offline · showing last screen"
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
        case .authenticating, .snapshot, .replaying: "Waiting for terminal output…"
        case .live: "The session has not produced visible output."
        case .offline: "No retained screen is available while this Host is offline."
        case .failed: "Terminal output could not be rendered safely."
        default: "No terminal output."
        }
    }

    private var accessibilityOutput: String {
        let visible = viewModel.screen.lines.suffix(20).joined(separator: "\n")
        return visible.isEmpty ? emptyText : visible
    }
}
