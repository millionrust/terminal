import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HostListViewModel: ObservableObject {
    @Published private(set) var vault: MobileVaultExport?
    @Published private(set) var connectionState: TerminalConnectionState = .disconnected
    @Published var selectedHost: MobileHost?
    @Published var importError: String?

    let terminalBuffer = TerminalBuffer()

    private let vaultImporter: MobileVaultImporter
    private let secretStore: SecretStoring
    private let sshClient: MobileSSHConnecting

    init(
        vaultImporter: MobileVaultImporter,
        secretStore: SecretStoring,
        sshClient: MobileSSHConnecting = DirectSSHSessionClient()
    ) {
        self.vaultImporter = vaultImporter
        self.secretStore = secretStore
        self.sshClient = sshClient
    }

    var hosts: [MobileHost] {
        vault?.hosts ?? []
    }

    func importPlaintextFixture(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            vault = try vaultImporter.importPlaintextVaultData(data)
            selectedHost = hosts.first
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func inspectEncryptedVault(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            _ = try vaultImporter.inspectEncryptedEnvelope(data)
            importError = "Encrypted vault recognized. Shared TermiRust vault crypto is required before production import."
        } catch {
            importError = error.localizedDescription
        }
    }

    func importEncryptedVault(from url: URL, passphrase: String) {
        do {
            let data = try Data(contentsOf: url)
            vault = try vaultImporter.importEncryptedVaultData(data, passphrase: passphrase)
            selectedHost = hosts.first
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func saveCredential(_ secret: String, for host: MobileHost) {
        do {
            try secretStore.saveSecret(secret, account: host.id)
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func connectSelectedHost() {
        guard let host = selectedHost else {
            return
        }
        let knownHost = vault?.knownHosts.first { $0.endpoint == host.knownHostEndpoint }
        connectionState = .connecting
        terminalBuffer.clear()
        terminalBuffer.append("Connecting to \(host.username)@\(host.host):\(host.port)")

        Task {
            do {
                try await sshClient.connect(host: host, knownHost: knownHost)
                connectionState = .connected
            } catch {
                connectionState = .failed(error.localizedDescription)
                terminalBuffer.append(error.localizedDescription)
            }
        }
    }
}
