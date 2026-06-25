import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: HostListViewModel

    var body: some View {
        NavigationSplitView {
            HostListView(viewModel: viewModel)
        } detail: {
            if let host = viewModel.selectedHost {
                TerminalSessionView(viewModel: viewModel, host: host)
            } else {
                ContentUnavailableView("Import a Vault", systemImage: "lock.rectangle.stack", description: Text("Select a TermiRust mobile vault to list hosts."))
            }
        }
    }
}
