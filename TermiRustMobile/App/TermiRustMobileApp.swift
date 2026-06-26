import SwiftUI

@main
struct TermiRustMobileApp: App {
    @StateObject private var viewModel: HostListViewModel = {
        let secretStore = KeychainSecretStore(service: "com.termirust.mobile")
        let deviceIdentityStore = UserDefaultsMobileDeviceIdentityStore()
        return HostListViewModel(
            vaultImporter: MobileVaultImporter(decryptor: NativeMobileVaultDecryptor()),
            secretStore: secretStore,
            encryptedVaultStore: try? FileEncryptedVaultStore(),
            sshClient: DirectSSHSessionClient(secretStore: secretStore),
            localDeviceId: deviceIdentityStore.deviceId
        )
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
