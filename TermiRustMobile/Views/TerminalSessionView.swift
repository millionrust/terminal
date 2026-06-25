import SwiftUI

struct TerminalSessionView: View {
    @ObservedObject var viewModel: HostListViewModel
    let host: MobileHost
    @State private var input = ""
    @State private var credential = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.terminalBuffer.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .background(Color(.systemBackground))
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
            SecureField(credentialLabel, text: $credential)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(host.auth.secretRef?.isEmpty ?? true)
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
        HStack {
            TextField("Command", text: $input)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Send") {
                viewModel.sendTerminalInput(input)
                input = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(input.isEmpty || viewModel.connectionState != .connected)
        }
        .padding()
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
