import SwiftUI

@main
struct TermiRustMobileApp: App {
    @StateObject private var viewModel: HostListViewModel = {
        let secretStore = KeychainSecretStore(service: "com.termirust.mobile")
        return HostListViewModel(
            vaultImporter: MobileVaultImporter(decryptor: NativeMobileVaultDecryptor()),
            secretStore: secretStore,
            encryptedVaultStore: try? FileEncryptedVaultStore(),
            sshClient: DirectSSHSessionClient(secretStore: secretStore)
        )
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
