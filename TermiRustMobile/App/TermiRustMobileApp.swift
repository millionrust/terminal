import SwiftUI

@main
struct TermiRustMobileApp: App {
    @StateObject private var viewModel = HostListViewModel(
        vaultImporter: MobileVaultImporter(),
        secretStore: KeychainSecretStore(service: "com.termirust.mobile")
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
