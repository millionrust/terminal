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
    @StateObject private var controllerViewModel = ControllerViewModel()

    var body: some Scene {
        WindowGroup {
            MobileRootView(
                sshViewModel: viewModel,
                controllerViewModel: controllerViewModel
            )
        }
    }
}

private struct MobileRootView: View {
    @ObservedObject var sshViewModel: HostListViewModel
    @ObservedObject var controllerViewModel: ControllerViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ControllerRootView(viewModel: controllerViewModel)
                .tabItem { Label("Fleet", systemImage: "rectangle.3.group") }
            ContentView(viewModel: sshViewModel)
                .tabItem { Label("SSH", systemImage: "terminal") }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                controllerViewModel.resume()
            case .background, .inactive:
                controllerViewModel.suspend()
            @unknown default:
                controllerViewModel.suspend()
            }
        }
    }
}
