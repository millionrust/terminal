import SwiftUI
import UniformTypeIdentifiers

struct TerminalSessionView: View {
    @ObservedObject var viewModel: HostListViewModel
    let host: MobileHost
    @State private var input = ""
    @State private var credential = ""
    @State private var terminalFontSize: CGFloat = 14
    @State private var pendingMultilinePaste: String?
    @State private var terminalGrid: TerminalGrid?
    @State private var lastSentTerminalGrid: TerminalGrid?
    @State private var showingPrivateKeyImporter = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 700
            ZStack {
                Color.mobileBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    sessionHeader
                    if let failureMessage {
                        ConnectionWarningBanner(message: failureMessage)
                    }
                    credentialPanel
                    terminalSurface
                    terminalControls
                    if pendingMultilinePaste == input, !input.isEmpty {
                        pasteWarning
                    }
                    inputRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : 18, style: .continuous))
                .overlay {
                    if !compact {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.panelBorder)
                    }
                }
                .padding(compact ? 0 : 12)
            }
        }
        .navigationTitle(host.label)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingPrivateKeyImporter,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            importPrivateKey(result)
        }
    }

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(host.label)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text("\(host.username)@\(host.host):\(host.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusPill(statusText, color: statusColor)
            Button("Connect") {
                viewModel.connectSelectedHost()
            }
            .buttonStyle(.borderedProminent)
            Button("Disconnect") {
                viewModel.disconnect()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.connectionState == .disconnected)
        }
        .padding(14)
    }

    private var credentialPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(credentialHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            credentialInput
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Save Credential") {
                        viewModel.saveCredential(credential, for: host)
                        credential = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled((host.auth.secretRef?.isEmpty ?? true) || credential.isEmpty)
                    Button("Remove") {
                        viewModel.deleteCredential(for: host)
                        credential = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(host.auth.secretRef?.isEmpty ?? true)
                    if host.auth.kind == .privateKey {
                        Button("Import Key File") {
                            showingPrivateKeyImporter = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(host.auth.secretRef?.isEmpty ?? true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var failureMessage: String? {
        if case .failed(let message) = viewModel.connectionState {
            return message
        }
        return nil
    }

    @ViewBuilder
    private var credentialInput: some View {
        if host.auth.kind == .privateKey {
            TextField(credentialLabel, text: $credential, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(3...6)
                .font(.system(.caption, design: .monospaced))
                .disabled(host.auth.secretRef?.isEmpty ?? true)
        } else {
            SecureField(credentialLabel, text: $credential)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(host.auth.secretRef?.isEmpty ?? true)
        }
    }

    private var terminalSurface: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if viewModel.terminalBuffer.lines.isEmpty {
                        Text("Terminal output will appear here.")
                            .foregroundStyle(Color.terminalMuted)
                    } else {
                        ForEach(Array(viewModel.terminalBuffer.lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.system(size: terminalFontSize, design: .monospaced))
                .foregroundStyle(Color.terminalForeground)
                .padding(12)
            }
            .background(Color.terminalBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear {
                updateTerminalGrid(size: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateTerminalGrid(size: newSize)
            }
            .onChange(of: terminalFontSize) { _, _ in
                updateTerminalGrid(size: proxy.size)
            }
            .onChange(of: viewModel.connectionState) { _, newState in
                if newState != .connected {
                    lastSentTerminalGrid = nil
                }
                updateTerminalGrid(size: proxy.size, forceResize: newState == .connected)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 220)
    }

    private var terminalControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("A-") {
                    terminalFontSize = max(10, terminalFontSize - 1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("A+") {
                    terminalFontSize = min(24, terminalFontSize + 1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text("\(Int(terminalFontSize)) sp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if host.persistentSession.enabled {
                    StatusPill("tmux", color: .blue)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(accessoryKeys, id: \.label) { key in
                        Button(key.label) {
                            if let bytes = key.bytes {
                                viewModel.sendTerminalBytes(bytes)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var pasteWarning: some View {
        HStack {
            Text("Multiline paste detected.")
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
            Button("Confirm") {
                sendInput(force: true)
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") {
                pendingMultilinePaste = nil
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.28))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Command", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...4)
                .onChange(of: input) { _, newValue in
                    if pendingMultilinePaste != newValue {
                        pendingMultilinePaste = nil
                    }
                }
            Button("Send") {
                sendInput()
            }
            .buttonStyle(.borderedProminent)
            .disabled(input.isEmpty || viewModel.connectionState != .connected)
        }
        .padding(14)
    }

    private func sendInput(force: Bool = false) {
        if !force && input.contains("\n") {
            pendingMultilinePaste = input
            return
        }
        viewModel.sendTerminalInput(input)
        input = ""
        pendingMultilinePaste = nil
    }

    private func importPrivateKey(_ result: Result<[URL], Error>) {
        do {
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let key = try String(contentsOf: url, encoding: .utf8)
            viewModel.saveCredential(key, for: host)
            credential = ""
        } catch {
            viewModel.reportStatus(error.localizedDescription)
        }
    }

    private func updateTerminalGrid(size: CGSize, forceResize: Bool = false) {
        let grid = estimateTerminalGrid(size: size, fontSize: terminalFontSize)
        if terminalGrid != grid {
            terminalGrid = grid
        }
        guard viewModel.connectionState == .connected else {
            return
        }
        guard forceResize || lastSentTerminalGrid != grid else {
            return
        }
        lastSentTerminalGrid = grid
        viewModel.resizeTerminal(columns: grid.columns, rows: grid.rows)
    }

    private var accessoryKeys: [(label: String, bytes: Data?)] {
        [
            ("Esc", Data([0x1b])),
            ("Tab", Data([0x09])),
            ("Ctrl", nil),
            ("Alt", nil),
            ("←", Data("\u{1b}[D".utf8)),
            ("↓", Data("\u{1b}[B".utf8)),
            ("↑", Data("\u{1b}[A".utf8)),
            ("→", Data("\u{1b}[C".utf8)),
            ("/", Data("/".utf8)),
            ("|", Data("|".utf8)),
            ("-", Data("-".utf8))
        ]
    }

    private var credentialLabel: String {
        switch host.auth.kind {
        case .password:
            return "SSH password"
        case .privateKey:
            return "Private key PEM"
        }
    }

    private var credentialHelp: String {
        if let secretRef = host.auth.secretRef, !secretRef.isEmpty {
            return "Credential: \(secretRef)"
        }
        return "No mobile secret reference exported for this host."
    }

    private var statusText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .failed:
            return "Failed"
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .disconnected:
            return .secondary
        case .failed:
            return .red
        }
    }
}

struct StatusPill: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

private struct ConnectionWarningBanner: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connection blocked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color(red: 0.50, green: 0.11, blue: 0.11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.25))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

extension View {
    func mobilePanel() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.panelBorder)
            )
    }
}

extension Color {
    static let mobileBackground = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let panelBorder = Color(red: 0.88, green: 0.90, blue: 0.94)
    static let terminalBackground = Color(red: 0.04, green: 0.06, blue: 0.13)
    static let terminalForeground = Color(red: 0.90, green: 0.92, blue: 0.95)
    static let terminalMuted = Color(red: 0.58, green: 0.64, blue: 0.72)
}
