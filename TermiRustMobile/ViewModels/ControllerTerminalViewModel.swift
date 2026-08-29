import Foundation
import SwiftUI

private enum ControllerTerminalMutation: Sendable {
    case acquire
    case release
    case input
    case resize
}

@MainActor
final class ControllerTerminalViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let hostTitle: String
    let sessionTitle: String

    @Published private(set) var attachState: ReadOnlyAttachState = .detached
    @Published private(set) var screen: BoundedTerminalSnapshot
    @Published private(set) var outputSequence: UInt64
    @Published private(set) var renderRevision: UInt64 = 0
    @Published private(set) var hasWriterElsewhere = false
    @Published private(set) var writerLease: WriterLeaseState = .none
    @Published private(set) var writerMessage: String?
    @Published private(set) var pendingPasteByteCount = 0
    @Published private(set) var privacyCovered = false

    private let host: PairedHostRecord
    private let identity: ReadOnlyAttachIdentity
    private let connection: any ControllerConnecting
    private var viewport: TerminalViewportState
    private var reducer: ReadOnlyAttachReducer
    private var writerReducer: WriterControlReducer
    private var terminal: BoundedTerminalBuffer
    private var queue: BoundedTerminalFrameQueue
    private var operation: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var operationID = UUID()
    private var intentionallyDetached = false
    private var interactiveConnection = false
    private var acquireAfterAttach = false
    private var pendingMutations: [UUID: ControllerTerminalMutation] = [:]
    private var inputInFlight: UUID?
    private var pendingPaste: Data?
    private var pendingResize: TerminalViewportState?
    private let sessionCapabilities: [ControllerSessionCapability]

    init(
        host: PairedHostRecord,
        session: ControllerSessionSummary,
        connection: any ControllerConnecting,
        viewport: TerminalViewportState = TerminalViewportState(columns: 120, rows: 40)
    ) throws {
        guard let generation = session.occupantGeneration, generation > 0 else {
            throw ReadOnlyAttachFailure.invalidIdentity
        }
        let identity = ReadOnlyAttachIdentity(
            hostID: host.id,
            hostInstanceID: session.hostInstanceID,
            sessionID: session.id,
            occupantGeneration: generation
        )
        self.host = host
        self.sessionCapabilities = session.capabilities
        self.identity = identity
        self.connection = connection
        self.viewport = viewport
        self.hostTitle = host.displayName
        self.sessionTitle = session.title
        self.reducer = try ReadOnlyAttachReducer(identity: identity)
        self.writerReducer = try WriterControlReducer(identity: identity)
        self.terminal = try BoundedTerminalBuffer(viewport: viewport)
        self.queue = try BoundedTerminalFrameQueue()
        self.screen = terminal.snapshot()
        self.outputSequence = reducer.cursor.outputSequence
    }

    deinit {
        operation?.cancel()
        renderTask?.cancel()
        resizeTask?.cancel()
    }

    var supportsWriterControl: Bool {
        let required: UInt16 = (1 << 1) | (1 << 2)
        let hostAllows = host.capabilityBits & required == required
        let sessionAllows = sessionCapabilities.isEmpty
            || (sessionCapabilities.contains(.attachOutput)
                && sessionCapabilities.contains(.sendInput))
        return hostAllows && sessionAllows
    }

    var supportsResize: Bool {
        host.capabilityBits & (1 << 3) != 0
            && (sessionCapabilities.isEmpty || sessionCapabilities.contains(.resize))
    }

    var canRequestControl: Bool {
        guard supportsWriterControl, !privacyCovered else { return false }
        switch writerLease {
        case .none, .busy, .lost: return true
        case .requesting, .held: return false
        }
    }

    var canSendInput: Bool {
        writerLease == .held && !privacyCovered && attachState == .live
    }

    func start() {
        guard operation == nil else { return }
        intentionallyDetached = false
        launch(interactive: false, cancelExisting: false)
    }

    func retry() {
        guard operation == nil else { return }
        launch(interactive: interactiveConnection, cancelExisting: true)
    }

    func requestControl() {
        guard canRequestControl else { return }
        writerMessage = nil
        acquireAfterAttach = true
        if interactiveConnection, attachState == .live {
            acquireAfterAttach = false
            issueAcquire()
            return
        }
        launch(interactive: true, cancelExisting: true)
    }

    func releaseControl() {
        guard writerLease == .held else { return }
        let commandID = UUID()
        pendingMutations[commandID] = .release
        writerReducer.releaseLocally()
        publishWriterState()
        Task { [weak self, connection, host, identity] in
            do {
                try await connection.releaseWriter(
                    host: host,
                    identity: identity,
                    commandID: commandID
                )
            } catch {
                self?.mutationSendFailed(commandID: commandID)
            }
        }
    }

    func sendKeyboardBytes(_ bytes: Data) {
        enqueueInput(bytes, kind: .keyboard, confirmed: true)
    }

    func requestPaste(_ string: String) {
        let bytes = TerminalInteraction.normalizePaste(string)
        guard !bytes.isEmpty else { return }
        guard bytes.count <= TerminalInteraction.maximumPastePayload(
            bracketed: screen.bracketedPaste
        ) else {
            writerMessage = "Paste is larger than the 256 KiB safety limit."
            return
        }
        if TerminalInteraction.pasteRequiresConfirmation(bytes) {
            pendingPaste = bytes
            pendingPasteByteCount = bytes.count
        } else {
            sendPastePayload(bytes)
        }
    }

    func confirmPaste() {
        guard let bytes = pendingPaste else { return }
        cancelPaste()
        sendPastePayload(bytes)
    }

    func cancelPaste() {
        pendingPaste = nil
        pendingPasteByteCount = 0
    }

    var visibleHTTPURLs: [URL] {
        TerminalInteraction.visibleHTTPURLs(in: screen.lines.joined(separator: "\n"))
    }

    private func sendPastePayload(_ bytes: Data) {
        let prepared = TerminalInteraction.preparePaste(bytes, bracketed: screen.bracketedPaste)
        enqueueInput(prepared, kind: .paste, confirmed: true)
    }

    func updateViewport(columns: Int, rows: Int, final: Bool = false) {
        let next = TerminalViewportState(columns: columns, rows: rows)
        guard (try? TerminalLimits.controllerDefault.validate(viewport: next)) != nil else {
            writerMessage = "Terminal size was outside the Host safety limits."
            return
        }
        viewport = next
        pendingResize = next
        resizeTask?.cancel()
        let delay: Duration = final ? .zero : .milliseconds(50)
        resizeTask = Task { [weak self] in
            if delay != .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            sendPendingResize()
        }
    }

    func suspend() {
        privacyCovered = true
        resizeTask?.cancel()
        resizeTask = nil
        pendingResize = nil
        cancelPaste()
        let held = writerLease == .held
        writerReducer.setForeground(false)
        publishWriterState()
        let releaseID = UUID()
        operationID = UUID()
        operation?.cancel()
        operation = nil
        Task { [connection, host, identity] in
            if held {
                try? await connection.releaseWriter(
                    host: host,
                    identity: identity,
                    commandID: releaseID
                )
            }
            await connection.cancel()
        }
        reducer.markOffline()
        attachState = .offline
        scheduleRender()
    }

    func resume() {
        guard attachState == .offline else { return }
        privacyCovered = false
        writerReducer.setForeground(true)
        publishWriterState()
        launch(interactive: interactiveConnection, cancelExisting: true)
    }

    func detach() {
        intentionallyDetached = true
        privacyCovered = false
        resizeTask?.cancel()
        resizeTask = nil
        renderTask?.cancel()
        renderTask = nil
        cancelPaste()
        let held = writerLease == .held
        writerReducer.releaseLocally()
        publishWriterState()
        let releaseID = UUID()
        operationID = UUID()
        operation?.cancel()
        operation = nil
        Task { [connection, host, identity] in
            if held {
                try? await connection.releaseWriter(
                    host: host,
                    identity: identity,
                    commandID: releaseID
                )
            }
            await connection.cancel()
        }
        queue.removeAll()
        pendingMutations.removeAll()
        inputInFlight = nil
        reducer.detach()
        attachState = .detached
    }

    private func launch(interactive: Bool, cancelExisting: Bool) {
        operationID = UUID()
        let launchID = operationID
        operation?.cancel()
        interactiveConnection = interactive
        if reducer.state != .detached && reducer.state != .offline {
            reducer.markOffline()
        }
        do {
            try reducer.beginAuthentication()
            attachState = reducer.state
        } catch {
            attachState = .failed(.invalidTransition)
            return
        }
        let cursor = reducer.cursor
        operation = Task { [weak self, connection, host, viewport] in
            if cancelExisting { await connection.cancel() }
            guard let self, self.operationID == launchID, !Task.isCancelled else { return }
            do {
                if interactive {
                    try await connection.attachInteractive(
                        host: host,
                        cursor: cursor,
                        viewport: viewport
                    ) { [weak self] event in
                        guard let self else { throw CancellationError() }
                        try await self.consumeIfCurrent(event, operationID: launchID)
                    }
                } else {
                    try await connection.attachReadOnly(
                        host: host,
                        cursor: cursor,
                        viewport: viewport
                    ) { [weak self] event in
                        guard let self else { throw CancellationError() }
                        try await self.consumeIfCurrent(event, operationID: launchID)
                    }
                }
                self.finish(error: ControllerConnectionError.malformedResponse, id: launchID)
            } catch {
                self.finish(error: error, id: launchID)
            }
        }
    }

    private func consumeIfCurrent(
        _ event: ControllerReadOnlyWireEvent,
        operationID: UUID
    ) throws {
        guard self.operationID == operationID else { throw CancellationError() }
        try consume(event)
    }

    private func consume(_ event: ControllerReadOnlyWireEvent) throws {
        switch event {
        case .snapshot(let chunk):
            if chunk.chunkIndex == 0 {
                try reducer.beginSnapshot()
                try terminal.reset(viewport: chunk.viewport)
            }
            try terminal.process(chunk.bytes)
            _ = try reducer.observeSnapshot(chunk)
            attachState = reducer.state
        case .attached(let replayThroughSequence, let hasWriterLease):
            try reducer.bindReplayBarrier(through: replayThroughSequence)
            hasWriterElsewhere = hasWriterLease
            attachState = reducer.state
            if acquireAfterAttach {
                acquireAfterAttach = false
                issueAcquire()
            }
        case .output(let frame):
            try queue.enqueue(frame)
            while let queued = queue.dequeue() {
                switch try reducer.observe(queued) {
                case .deliver:
                    try terminal.process(queued.bytes)
                case .duplicate:
                    break
                case .gap(let expected, let received):
                    attachState = .gap(expected: expected, received: received)
                    loseWriter(message: "Control ended because terminal output was incomplete.")
                    scheduleRender()
                    return
                }
            }
            attachState = reducer.state
        case .completed(let commandID, let applied):
            completeMutation(commandID: commandID, applied: applied)
        case .error(let commandID, let code, let completionUnknown):
            failMutation(
                commandID: commandID,
                code: code,
                completionUnknown: completionUnknown
            )
        }
        outputSequence = reducer.cursor.outputSequence
        scheduleRender()
    }

    private func issueAcquire() {
        guard interactiveConnection, canRequestControl else { return }
        let commandID = UUID()
        do {
            try writerReducer.beginAcquire(commandID: commandID)
        } catch {
            writerMessage = "Control could not be requested in the current state."
            return
        }
        pendingMutations[commandID] = .acquire
        publishWriterState()
        Task { [weak self, connection, host, identity] in
            do {
                try await connection.requestWriter(
                    host: host,
                    identity: identity,
                    commandID: commandID
                )
            } catch {
                self?.mutationSendFailed(commandID: commandID)
            }
        }
    }

    private func enqueueInput(
        _ bytes: Data,
        kind: PendingInputKind,
        confirmed: Bool
    ) {
        guard canSendInput else {
            writerMessage = "Request control before sending terminal input."
            return
        }
        guard !bytes.isEmpty, bytes.count <= WriterControlReducer.maxQueuedBytes else {
            writerMessage = "Input exceeded the 256 KiB queue limit."
            return
        }
        do {
            for offset in stride(
                from: 0,
                to: bytes.count,
                by: ControllerWriterWireCodec.maxInputChunkBytes
            ) {
                let end = min(
                    offset + ControllerWriterWireCodec.maxInputChunkBytes,
                    bytes.count
                )
                try writerReducer.enqueue(
                    bytes.subdata(in: offset..<end),
                    kind: kind,
                    confirmed: confirmed
                )
            }
            publishWriterState()
            drainInputQueue()
        } catch WriterControlFailure.pasteConfirmationRequired {
            pendingPaste = bytes
            pendingPasteByteCount = bytes.count
        } catch {
            writerMessage = "Input pressure limit reached. Wait before trying again."
        }
    }

    private func drainInputQueue() {
        guard inputInFlight == nil,
              canSendInput,
              let pending = writerReducer.dequeue() else { return }
        inputInFlight = pending.commandID
        pendingMutations[pending.commandID] = .input
        publishWriterState()
        Task { [weak self, connection, host, identity] in
            do {
                try await connection.sendInput(
                    host: host,
                    identity: identity,
                    commandID: pending.commandID,
                    bytes: pending.bytes
                )
            } catch {
                self?.mutationSendFailed(commandID: pending.commandID)
            }
        }
    }

    private func sendPendingResize() {
        guard canSendInput, supportsResize, let next = pendingResize else { return }
        pendingResize = nil
        let commandID = UUID()
        pendingMutations[commandID] = .resize
        Task { [weak self, connection, host, identity] in
            do {
                try await connection.sendResize(
                    host: host,
                    identity: identity,
                    commandID: commandID,
                    viewport: next
                )
            } catch {
                self?.mutationSendFailed(commandID: commandID)
            }
        }
    }

    private func completeMutation(commandID: UUID, applied: Bool) {
        guard let mutation = pendingMutations.removeValue(forKey: commandID) else {
            loseWriter(message: "Control response did not match a pending action.")
            return
        }
        switch mutation {
        case .acquire:
            do {
                try writerReducer.finishAcquire(commandID: commandID, applied: applied)
                hasWriterElsewhere = !applied
                writerMessage = applied ? nil : "This session is controlled from another client."
            } catch {
                loseWriter(message: "Control response was stale.")
                return
            }
        case .release:
            writerReducer.releaseLocally()
        case .input:
            guard inputInFlight == commandID else {
                loseWriter(message: "Input acknowledgement was stale.")
                return
            }
            inputInFlight = nil
            if !applied {
                loseWriter(message: "The Host rejected terminal input.")
                return
            }
        case .resize:
            if !applied { writerMessage = "The Host rejected the terminal resize." }
        }
        publishWriterState()
        if mutation == .input { drainInputQueue() }
    }

    private func failMutation(
        commandID: UUID,
        code: String,
        completionUnknown: Bool
    ) {
        guard let mutation = pendingMutations.removeValue(forKey: commandID) else {
            loseWriter(message: "An unmatched Host error ended control.")
            return
        }
        if mutation == .input { inputInFlight = nil }
        if mutation == .acquire, !completionUnknown {
            do {
                try writerReducer.finishAcquire(commandID: commandID, applied: false)
                hasWriterElsewhere = code == "writer_lease_required" || code == "writer_busy"
                writerMessage = "Control is not available on this session."
                publishWriterState()
                return
            } catch {
                // Fall through to the fail-closed state.
            }
        }
        let message = completionUnknown
            ? "The action result is unknown. Control was disabled without retrying it."
            : "The Host rejected control action: \(code)."
        loseWriter(message: message)
    }

    private func mutationSendFailed(commandID: UUID) {
        guard pendingMutations.removeValue(forKey: commandID) != nil else { return }
        if inputInFlight == commandID { inputInFlight = nil }
        loseWriter(message: "Control connection failed. No input was replayed.")
    }

    private func loseWriter(message: String) {
        writerReducer.markLeaseLost()
        pendingMutations.removeAll()
        inputInFlight = nil
        writerMessage = message
        publishWriterState()
    }

    private func publishWriterState() {
        writerLease = writerReducer.lease
    }

    private func finish(error: Error, id: UUID) {
        guard operationID == id else { return }
        operation = nil
        guard !intentionallyDetached else { return }
        if writerLease == .held || writerLease.isRequesting {
            loseWriter(message: "Control connection ended. No input was replayed.")
        }
        if error is CancellationError {
            reducer.markOffline()
            attachState = .offline
        } else if case ControllerReadOnlyWireError.hostError(let code) = error,
                  code.lowercased().contains("exit") {
            reducer.markExited()
            attachState = .exited
        } else if let failure = error as? ReadOnlyAttachFailure {
            attachState = .failed(failure)
        } else {
            reducer.markOffline()
            attachState = .offline
        }
        scheduleRender()
    }

    private func scheduleRender() {
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            screen = terminal.snapshot()
            renderRevision &+= 1
            renderTask = nil
        }
    }
}

private extension WriterLeaseState {
    var isRequesting: Bool {
        if case .requesting = self { return true }
        return false
    }
}
