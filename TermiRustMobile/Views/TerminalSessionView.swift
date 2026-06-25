import SwiftUI

struct TerminalSessionView: View {
    @ObservedObject var viewModel: HostListViewModel
    let host: MobileHost
    @State private var input = ""
    @State private var credential = ""
    @State private var terminalFontSize: CGFloat = 14
    @State private var pendingMultilinePaste: String?
    @State private var terminalGrid: TerminalGrid?
    @State private var lastSentTerminalGrid: TerminalGrid?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.terminalBuffer.lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: terminalFontSize, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                }
                .background(Color(.systemBackground))
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
            terminalControls
            accessoryRow
            inputRow
        }
        .navigationTitle(host.label)
        .toolbar {
            Button("Connect") {
                viewModel.connectSelectedHost()
            }
            Button("Disconnect") {
                viewModel.disconnect()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(host.username)@\(host.host):\(host.port)")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if host.persistentSession.enabled {
                    Text("tmux")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
            credentialEditor
        }
    }

    private var credentialEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(credentialHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            credentialInput
            HStack {
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
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var credentialInput: some View {
        if host.auth.kind == .privateKey {
            TextField(credentialLabel, text: $credential, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(4...10)
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
            return "Credential secret_ref: \(secretRef)"
        }
        return "No mobile secret reference exported for this host."
    }

    private var terminalControls: some View {
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
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var accessoryRow: some View {
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
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pendingMultilinePaste == input, !input.isEmpty {
                Text("Multiline paste detected. Tap Confirm Paste to send it.")
                    .font(.caption)
                    .foregroundStyle(.red)
                HStack {
                    Button("Confirm Paste") {
                        sendInput(force: true)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") {
                        pendingMultilinePaste = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            HStack {
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
        }
        .padding()
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

    private var statusText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .failed(let message):
            return message
        }
    }
}
