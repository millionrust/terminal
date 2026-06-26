import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HostListViewModel: ObservableObject {
    @Published private(set) var vault: MobileVaultExport?
    @Published private(set) var connectionState: TerminalConnectionState = .disconnected
    @Published private(set) var hasStoredEncryptedVault: Bool
    @Published var selectedHost: MobileHost?
    @Published var importError: String?

    let terminalBuffer = TerminalBuffer()

    private let vaultImporter: MobileVaultImporter
    private let secretStore: SecretStoring
    private let encryptedVaultStore: EncryptedVaultStoring?
    private let sshClient: MobileSSHConnecting

    init(
        vaultImporter: MobileVaultImporter,
        secretStore: SecretStoring,
        encryptedVaultStore: EncryptedVaultStoring? = nil,
        sshClient: MobileSSHConnecting = DirectSSHSessionClient()
    ) {
        self.vaultImporter = vaultImporter
        self.secretStore = secretStore
        self.encryptedVaultStore = encryptedVaultStore
        self.sshClient = sshClient
        self.hasStoredEncryptedVault = encryptedVaultStore?.hasEncryptedVault ?? false
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
            try encryptedVaultStore?.saveEncryptedVault(data)
            hasStoredEncryptedVault = encryptedVaultStore?.hasEncryptedVault ?? false
            selectedHost = hosts.first
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func unlockStoredEncryptedVault(passphrase: String) {
        do {
            guard let data = try encryptedVaultStore?.readEncryptedVault() else {
                hasStoredEncryptedVault = false
                importError = "No stored encrypted vault is available."
                return
            }
            vault = try vaultImporter.importEncryptedVaultData(data, passphrase: passphrase)
            selectedHost = hosts.first
            hasStoredEncryptedVault = encryptedVaultStore?.hasEncryptedVault ?? false
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func forgetStoredEncryptedVault() {
        do {
            try encryptedVaultStore?.clearEncryptedVault()
            hasStoredEncryptedVault = false
            vault = nil
            selectedHost = nil
            importError = "Stored encrypted vault removed."
        } catch {
            importError = error.localizedDescription
        }
    }

    func saveCredential(_ secret: String, for host: MobileHost) {
        do {
            guard let secretRef = host.auth.secretRef, !secretRef.isEmpty else {
                importError = "This host does not declare a mobile secret reference."
                return
            }
            guard !secret.isEmpty else {
                importError = "Enter the SSH credential before saving."
                return
            }
            try secretStore.saveSecret(secret, account: secretRef)
            importError = "Credential saved for \(host.label)."
        } catch {
            importError = error.localizedDescription
        }
    }

    func deleteCredential(for host: MobileHost) {
        do {
            guard let secretRef = host.auth.secretRef, !secretRef.isEmpty else {
                importError = "This host does not declare a mobile secret reference."
                return
            }
            try secretStore.deleteSecret(account: secretRef)
            importError = "Credential removed for \(host.label)."
        } catch {
            importError = error.localizedDescription
        }
    }

    func sendTerminalInput(_ input: String) {
        Task {
            do {
                try await sshClient.send(Data((input + "\n").utf8))
            } catch {
                terminalBuffer.append(error.localizedDescription)
            }
        }
    }

    func sendTerminalBytes(_ bytes: Data) {
        Task {
            do {
                try await sshClient.send(bytes)
            } catch {
                terminalBuffer.append(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        Task {
            await sshClient.disconnect()
            connectionState = .disconnected
        }
    }

    func resizeTerminal(columns: Int, rows: Int) {
        terminalBuffer.resize(columns: columns, rows: rows)
        Task {
            do {
                try await sshClient.resize(columns: columns, rows: rows)
            } catch {
                terminalBuffer.append(error.localizedDescription)
            }
        }
    }

    func reportStatus(_ message: String) {
        importError = message
    }

    func credentialReference(for host: MobileHost) -> String? {
        host.auth.secretRef
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
                try await sshClient.connect(host: host, knownHost: knownHost) { [weak self] data in
                    Task { @MainActor in
                        self?.terminalBuffer.append(data)
                    }
                }
                connectionState = .connected
            } catch {
                connectionState = .failed(error.localizedDescription)
                terminalBuffer.append(error.localizedDescription)
            }
        }
    }
}
