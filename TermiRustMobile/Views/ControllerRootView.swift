import SwiftUI

struct ControllerRootView: View {
    @ObservedObject var viewModel: ControllerViewModel
    @State private var showingPairing = false
    @State private var showingForgetConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: hostSelection) {
                Section("Paired Hosts") {
                    ForEach(viewModel.state.hosts) { host in
                        ControllerHostRow(
                            host: host,
                            selected: host.id == viewModel.state.selectedHostID
                        )
                        .tag(Optional(host.id))
                    }
                }
            }
            .navigationTitle("Fleet")
            .overlay {
                if viewModel.state.hosts.isEmpty {
                    ContentUnavailableView {
                        Label("No Paired Hosts", systemImage: "desktopcomputer")
                    } description: {
                        Text("Pair with TermiRust Desktop on the same private network.")
                    } actions: {
                        Button("Pair Host") { showingPairing = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingPairing = true } label: {
                        Label("Pair Host", systemImage: "plus")
                    }
                }
            }
        } detail: {
            ControllerSessionFleetView(
                state: viewModel.state,
                onRetry: viewModel.retry,
                onForget: { showingForgetConfirmation = true }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingPairing) {
            PairHostView(viewModel: viewModel, isPresented: $showingPairing)
        }
        .confirmationDialog(
            "Forget this Host on this device?",
            isPresented: $showingForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget on This Device", role: .destructive) {
                viewModel.forgetSelectedHost()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local pairing key and cache. It does not revoke the device on the Host.")
        }
    }

    private var hostSelection: Binding<String?> {
        Binding(
            get: { viewModel.state.selectedHostID },
            set: { viewModel.selectHost(id: $0) }
        )
    }
}

private struct ControllerHostRow: View {
    let host: HostSummary
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(host.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(host.route.address):\(host.route.port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ControllerSessionFleetView: View {
    let state: ControllerViewState
    let onRetry: () -> Void
    let onForget: () -> Void

    var body: some View {
        Group {
            if state.selectedHostID == nil {
                ContentUnavailableView("Select a Host", systemImage: "rectangle.connected.to.line.below")
            } else {
                List {
                    Section {
                        ControllerStatusBanner(state: state, onRetry: onRetry)
                    }
                    if state.sessions.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("No Sessions", systemImage: "terminal")
                            } description: {
                                Text(emptyMessage)
                            }
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section("Sessions") {
                            ForEach(state.sessions) { session in
                                ControllerSessionRow(session: session, cached: state.isCachedReadOnly)
                            }
                        }
                    }
                }
                .navigationTitle(selectedTitle)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: onRetry) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive, action: onForget) {
                            Label("Forget", systemImage: "trash")
                        }
                    }
                }
                .refreshable { onRetry() }
            }
        }
    }

    private var selectedTitle: String {
        state.hosts.first(where: { $0.id == state.selectedHostID })?.title ?? "Sessions"
    }

    private var emptyMessage: String {
        state.isCachedReadOnly
            ? "No sessions were saved in the last complete snapshot."
            : "This Host is not currently reporting durable sessions."
    }
}

private struct ControllerStatusBanner: View {
    let state: ControllerViewState
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var showsRetry: Bool {
        if case .failed = state.connection { return true }
        return state.connection == .pairedOffline
    }

    private var title: String {
        if state.isCachedReadOnly { return "Cached · Read Only" }
        switch state.connection {
        case .readyReadOnly: return "Live · Read Only"
        case .connecting, .authenticating, .syncing: return "Connecting"
        case .failed: return "Host Unavailable"
        case .revoked: return "Pairing Revoked"
        case .incompatible: return "Update Required"
        default: return "Offline"
        }
    }

    private var detail: String {
        if let date = state.cacheUpdatedAt {
            return "Last complete snapshot \(date.formatted(.relative(presentation: .named)))."
        }
        switch state.connection {
        case .readyReadOnly: return "Session status is current. Terminal content is never downloaded."
        case .connecting, .authenticating, .syncing: return "Authenticating directly with the selected Host."
        case .failed(let failure): return failureMessage(failure)
        default: return "Connect to the same LAN or VPN, then retry."
        }
    }

    private var icon: String {
        state.isCachedReadOnly ? "clock.arrow.circlepath" : (state.connection == .readyReadOnly ? "checkmark.shield" : "wifi.exclamationmark")
    }

    private var color: Color {
        state.isCachedReadOnly ? .orange : (state.connection == .readyReadOnly ? .green : .secondary)
    }

    private func failureMessage(_ failure: ControllerFailure) -> String {
        switch failure {
        case .authenticationFailed: return "Authentication failed. The device may have been revoked."
        case .sequenceGap: return "The Host changed during sync. Retry for a complete snapshot."
        case .resourceLimit: return "The Host has more data than this device can cache safely."
        case .keychainUnavailable: return "Unlock this device or pair again to restore the device key."
        case .malformedResponse: return "The Host returned an incompatible response."
        case .timedOut: return "The Host did not respond before the secure connection deadline."
        case .pairingUncertain: return "The Host may have saved this device, but confirmation was interrupted. Keep the pairing offer open and try again."
        default: return "Connect to the same LAN or VPN, then retry."
        }
    }
}

private struct ControllerSessionRow: View {
    let session: ControllerSessionSummary
    let cached: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: lifecycleIcon)
                .foregroundStyle(lifecycleColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(session.lifecycle.capitalized)
                    if session.hasWriter { Text("Writer active") }
                    if session.unreadCount > 0 { Text("\(session.unreadCount) unread") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(cached ? "Cached" : "Live")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(cached ? .orange : .green)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background((cached ? Color.orange : Color.green).opacity(0.12))
                .clipShape(Capsule())
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var lifecycleIcon: String {
        switch session.lifecycle {
        case "running": return "play.circle.fill"
        case "stopped", "exited": return "stop.circle"
        default: return "circle.dotted"
        }
    }

    private var lifecycleColor: Color {
        session.lifecycle == "running" ? .green : .secondary
    }
}

private struct PairHostView: View {
    @ObservedObject var viewModel: ControllerViewModel
    @Binding var isPresented: Bool
    @State private var showingScanner = false
    @State private var scannerFailure: ControllerScannerFailure?

    var body: some View {
        NavigationStack {
            Form {
                if let challenge = viewModel.pairingChallenge {
                    Section("Compare on Both Devices") {
                        Text(challenge.sas)
                            .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .textSelection(.enabled)
                            .accessibilityLabel("Security code \(challenge.sas.map(String.init).joined(separator: " "))")
                        Text("Only continue when this exact code is visible in TermiRust Desktop.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Codes Match") { viewModel.finishPairing(matches: true) }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        Button("Reject", role: .destructive) {
                            viewModel.finishPairing(matches: false)
                            isPresented = false
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Section("Names") {
                        TextField("Host name", text: $viewModel.pairingHostName)
                            .textContentType(.name)
                        TextField("This device", text: $viewModel.pairingDeviceName)
                            .textContentType(.name)
                    }
                    Section("Pairing Offer") {
                        Button {
                            scannerFailure = nil
                            showingScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        TextEditor(text: $viewModel.pairingOfferText)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 150)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("In TermiRust Desktop, open Settings, Remote Devices, Add Controller, then copy the pairing offer here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let scannerFailure {
                            Text(scannerFailure == .permissionDenied
                                ? "Camera access is off. Paste the pairing offer instead, or enable Camera in Settings."
                                : "A camera is unavailable. Paste the pairing offer instead.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    Section {
                        Button("Continue") { viewModel.beginPairing() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(
                                viewModel.pairingOfferText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || viewModel.pairingHostName.isEmpty
                                    || viewModel.pairingDeviceName.isEmpty
                            )
                    }
                }
            }
            .navigationTitle("Pair Host")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(viewModel.pairingChallenge != nil)
            .onChange(of: viewModel.state.connection) { _, connection in
                if viewModel.pairingChallenge == nil,
                   viewModel.pairingOfferText.isEmpty,
                   connection != .pairing {
                    isPresented = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelPairing()
                        isPresented = false
                    }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                ZStack(alignment: .topTrailing) {
                    ControllerQRCodeScanner { code in
                        viewModel.pairingOfferText = code
                        showingScanner = false
                    } onFailure: { failure in
                        scannerFailure = failure
                        showingScanner = false
                    }
                    Button {
                        showingScanner = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close Scanner")
                    .padding()
                }
                .ignoresSafeArea()
            }
        }
    }
}
