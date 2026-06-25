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
                EmptySessionView()
            }
        }
        .tint(.blue)
    }
}

private struct EmptySessionView: View {
    var body: some View {
        ZStack {
            Color.mobileBackground.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "terminal")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Select a host")
                    .font(.title2.weight(.bold))
                Text("Import a mobile vault, save the credential, then connect to a tmux-backed terminal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(24)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.panelBorder)
            )
            .padding()
        }
    }
}
