import SwiftUI

struct ControllerRootView: View {
    @ObservedObject var viewModel: ControllerViewModel
    @State private var showingPairing = false
    @State private var showingForgetConfirmation = false
    @State private var showingHostDetails = false

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
                onForget: { showingForgetConfirmation = true },
                onShowDetails: { showingHostDetails = true }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingPairing) {
            PairHostView(viewModel: viewModel, isPresented: $showingPairing)
        }
        .sheet(isPresented: $showingHostDetails) {
            if let host = viewModel.state.hosts.first(where: {
                $0.id == viewModel.state.selectedHostID
            }) {
                ControllerHostSettingsView(
                    host: host,
                    onReconnect: {
                        showingHostDetails = false
                        viewModel.retry()
                    },
                    onForget: {
                        showingHostDetails = false
                        showingForgetConfirmation = true
                    }
                )
            }
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
                Text(ControllerPresentation.isolated(host.title))
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(ControllerPresentation.isolated("\(host.route.address):\(host.route.port)"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
    let onShowDetails: () -> Void

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
                        Button(action: onShowDetails) {
                            Label("Host Details", systemImage: "info.circle")
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

    private var emptyMessage: LocalizedStringKey {
        state.isCachedReadOnly
            ? "No sessions were saved in the last complete snapshot."
            : "This Host is not currently reporting durable sessions."
    }
}

private struct ControllerStatusBanner: View {
    let state: ControllerViewState
    let onRetry: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                statusContent
                Spacer(minLength: 8)
                retryButton
            }
            VStack(alignment: .leading, spacing: 10) {
                statusContent
                retryButton
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var statusContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                detailText
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var retryButton: some View {
        if showsRetry {
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
        }
    }

    private var showsRetry: Bool {
        if case .failed = state.connection { return true }
        return state.connection == .pairedOffline
    }

    private var title: LocalizedStringKey {
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

    @ViewBuilder
    private var detailText: some View {
        if let date = state.cacheUpdatedAt {
            Text("Last complete snapshot \(date.formatted(.relative(presentation: .named))).")
        } else {
            switch state.connection {
            case .readyReadOnly:
                Text("Session status is current. Terminal content is never downloaded.")
            case .connecting, .authenticating, .syncing:
                Text("Authenticating directly with the selected Host.")
            case .failed(let failure):
                Text(failureMessage(failure))
            default:
                Text("Connect to the same LAN or VPN, then retry.")
            }
        }
    }

    private var icon: String {
        state.isCachedReadOnly ? "clock.arrow.circlepath" : (state.connection == .readyReadOnly ? "checkmark.shield" : "wifi.exclamationmark")
    }

    private var color: Color {
        state.isCachedReadOnly ? .orange : (state.connection == .readyReadOnly ? .green : .secondary)
    }

    private func failureMessage(_ failure: ControllerFailure) -> LocalizedStringKey {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    sessionContent
                    freshnessBadge
                        .padding(.leading, 40)
                }
            } else {
                HStack(spacing: 12) {
                    sessionContent
                    Spacer(minLength: 8)
                    freshnessBadge
                }
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var sessionContent: some View {
        HStack(spacing: 12) {
            Image(systemName: lifecycleIcon)
                .foregroundStyle(lifecycleColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(ControllerPresentation.isolated(session.title))
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if session.project != nil || session.group != nil {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text(session.lifecycle.capitalized)
                    if session.hasWriter { Text("Writer active") }
                    if session.unreadCount > 0 {
                        Text(ControllerPresentation.unreadDescription(session.unreadCount))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var freshnessBadge: some View {
        Text(cached ? LocalizedStringKey("Cached") : LocalizedStringKey("Live"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(cached ? .orange : .green)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((cached ? Color.orange : Color.green).opacity(0.12))
            .clipShape(Capsule())
    }

    private var metadata: String {
        [session.project, session.group]
            .compactMap { $0 }
            .map(ControllerPresentation.isolated)
            .joined(separator: " · ")
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
                        LabeledContent("Host") {
                            Text(ControllerPresentation.isolated(
                                "\(challenge.route.address):\(challenge.route.port)"
                            ))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host Fingerprint")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ControllerPresentation.isolated(challenge.hostFingerprint))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(
                                    "Host fingerprint \(ControllerPresentation.fingerprintForSpeech(challenge.hostFingerprint))"
                                )
                        }
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
                        if viewModel.state.connection == .pairing {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Waiting for Host confirmation…")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityElement(children: .combine)
                        } else {
                            Button("Codes Match") { viewModel.finishPairing(matches: true) }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                            Button("Reject", role: .destructive) {
                                viewModel.finishPairing(matches: false)
                                isPresented = false
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
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

private struct ControllerHostSettingsView: View {
    let host: HostSummary
    let onReconnect: () -> Void
    let onForget: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Host", value: ControllerPresentation.isolated(host.title))
                    LabeledContent("Route") {
                        Text(ControllerPresentation.isolated("\(host.route.address):\(host.route.port)"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Section("Host Identity") {
                    Text(ControllerPresentation.isolated(host.fingerprint))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(
                            "Host fingerprint \(ControllerPresentation.fingerprintForSpeech(host.fingerprint))"
                        )
                }
                Section("Granted Capabilities") {
                    ForEach(Array(ControllerPresentation.capabilityLabels(bits: host.capabilityBits).enumerated()), id: \.offset) { _, label in
                        Label(label, systemImage: "checkmark.circle")
                    }
                    Text("This version only reads session summaries. It cannot display terminal output or send input.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(action: onReconnect) {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive, action: onForget) {
                        Label("Forget on This Device", systemImage: "trash")
                    }
                } footer: {
                    Text("Forgetting removes the local key and cached summaries. It does not revoke this device on the Host.")
                }
            }
            .navigationTitle("Host Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
