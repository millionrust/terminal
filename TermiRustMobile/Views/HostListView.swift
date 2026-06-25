import SwiftUI
import UniformTypeIdentifiers

struct HostListView: View {
    @ObservedObject var viewModel: HostListViewModel
    @State private var showingImporter = false
    @State private var vaultPassphrase = ""

    var body: some View {
        List(selection: $viewModel.selectedHost) {
            Section("Vault") {
                SecureField("Vault passphrase", text: $vaultPassphrase)
                    .textContentType(.password)
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Encrypted Vault", systemImage: "square.and.arrow.down")
                }
                .disabled(vaultPassphrase.isEmpty)
            }

            if let error = viewModel.importError {
                Section("Status") {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Hosts") {
                ForEach(viewModel.hosts) { host in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(host.label)
                            .font(.headline)
                        Text("\(host.username)@\(host.host):\(host.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if host.persistentSession.enabled {
                            Label(host.persistentSession.sessionName ?? "persistent tmux", systemImage: "rectangle.connected.to.line.below")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .tag(host)
                }
            }
        }
        .navigationTitle("TermiRust")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            viewModel.importEncryptedVault(from: url, passphrase: vaultPassphrase)
            vaultPassphrase = ""
        }
    }
}
