import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: HostListViewModel
    @State private var showingImporter = false
    @State private var vaultPassphrase = ""

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 900
            let panelSpacing: CGFloat = wide ? 1 : 0
            let hostPanelWidth = min(max(proxy.size.width * 0.34, 340), 460)
            ZStack {
                Color.mobileBackground.ignoresSafeArea()
                if wide {
                    HStack(spacing: panelSpacing) {
                        HostListView(viewModel: viewModel)
                            .frame(width: hostPanelWidth)
                            .frame(maxHeight: .infinity)
                        sessionDetail(framed: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        compactHeader
                        compactHostStrip
                        sessionDetail(framed: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mobileBackground.ignoresSafeArea())
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
        .tint(.blue)
    }

    @ViewBuilder
    private func sessionDetail(framed: Bool) -> some View {
        if let host = viewModel.selectedHost {
            TerminalSessionView(viewModel: viewModel, host: host, framed: framed)
        } else {
            EmptySessionView(framed: framed)
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.terminalBackground)
                        .frame(width: 36, height: 36)
                    Text(">")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TermiRust")
                        .font(.title2.weight(.bold))
                    Text("Mobile terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            SecureField("Vault passphrase", text: $vaultPassphrase)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
            Button {
                showingImporter = true
            } label: {
                Label("Import Encrypted Vault", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vaultPassphrase.isEmpty)
            Button {
                copyPairingRequest()
            } label: {
                Label("Copy Pairing Request", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if viewModel.hasStoredEncryptedVault {
                HStack(spacing: 8) {
                    Button("Unlock Saved Vault") {
                        viewModel.unlockStoredEncryptedVault(passphrase: vaultPassphrase)
                        vaultPassphrase = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(vaultPassphrase.isEmpty)
                    Button("Forget") {
                        viewModel.forgetStoredEncryptedVault()
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let status = viewModel.importError {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.panelBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var compactHostStrip: some View {
        if !viewModel.hosts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.hosts) { host in
                        CompactHostChip(
                            host: host,
                            selected: viewModel.selectedHost?.id == host.id
                        ) {
                            viewModel.selectedHost = host
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(.white)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.panelBorder)
                    .frame(height: 1)
            }
        }
    }

    private func copyPairingRequest() {
        do {
            UIPasteboard.general.string = try viewModel.pairingRequestText()
            viewModel.reportStatus("Pairing request copied. Import it on desktop to authorize this device.")
        } catch {
            viewModel.reportStatus(error.localizedDescription)
        }
    }
}

private struct CompactHostChip: View {
    let host: MobileHost
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(host.label)
                    .lineLimit(1)
                if host.persistentSession.enabled {
                    Text("tmux")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Color.blue.opacity(0.08) : .white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? Color.blue : Color.panelBorder)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmptySessionView: View {
    let framed: Bool

    init(framed: Bool = true) {
        self.framed = framed
    }

    var body: some View {
        ZStack {
            (framed ? Color.mobileBackground : Color.white).ignoresSafeArea()
            if framed {
                emptyContent
                    .padding(24)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.panelBorder)
                    )
            } else {
                emptyContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyContent: some View {
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
    }
}
