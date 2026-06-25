import SwiftUI

struct TerminalSessionView: View {
    @ObservedObject var viewModel: HostListViewModel
    let host: MobileHost
    @State private var input = ""

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
        }
    }

    private var header: some View {
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
    }

    private var accessoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["Esc", "Tab", "Ctrl", "Alt", "←", "↓", "↑", "→", "/", "|", "-"], id: \.self) { key in
                    Button(key) {
                        input += key == "Tab" ? "\t" : key
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
                viewModel.terminalBuffer.append("$ \(input)")
                input = ""
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
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
