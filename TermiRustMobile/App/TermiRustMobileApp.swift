import SwiftUI

@main
struct TermiRustMobileApp: App {
    @StateObject private var controllerViewModel = ControllerViewModel()

    var body: some Scene {
        WindowGroup {
            ControllerMobileRootView(viewModel: controllerViewModel)
        }
    }
}

private struct ControllerMobileRootView: View {
    @ObservedObject var viewModel: ControllerViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ControllerRootView(viewModel: viewModel)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    viewModel.resume()
                case .background, .inactive:
                    viewModel.suspend()
                @unknown default:
                    viewModel.suspend()
                }
            }
    }
}
