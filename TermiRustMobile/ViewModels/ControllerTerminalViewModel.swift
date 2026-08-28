import Foundation
import SwiftUI

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

    private let host: PairedHostRecord
    private let session: ControllerSessionSummary
    private let connection: any ControllerConnecting
    private let viewport: TerminalViewportState
    private var reducer: ReadOnlyAttachReducer
    private var terminal: BoundedTerminalBuffer
    private var queue: BoundedTerminalFrameQueue
    private var operation: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var intentionallyDetached = false

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
            sessionID: session.id,
            occupantGeneration: generation
        )
        self.host = host
        self.session = session
        self.connection = connection
        self.viewport = viewport
        self.hostTitle = host.displayName
        self.sessionTitle = session.title
        self.reducer = try ReadOnlyAttachReducer(identity: identity)
        self.terminal = try BoundedTerminalBuffer(viewport: viewport)
        self.queue = try BoundedTerminalFrameQueue()
        self.screen = terminal.snapshot()
        self.outputSequence = reducer.cursor.outputSequence
    }

    deinit {
        operation?.cancel()
        renderTask?.cancel()
    }

    func start() {
        guard operation == nil else { return }
        intentionallyDetached = false
        do {
            try reducer.beginAuthentication()
            attachState = reducer.state
        } catch {
            attachState = .failed(.invalidTransition)
            return
        }
        let cursor = reducer.cursor
        operation = Task { [weak self, connection, host, viewport] in
            do {
                try await connection.attachReadOnly(
                    host: host,
                    cursor: cursor,
                    viewport: viewport
                ) { [weak self] event in
                    guard let self else { throw CancellationError() }
                    try await self.consume(event)
                }
                self?.finish(error: ControllerConnectionError.malformedResponse)
            } catch {
                self?.finish(error: error)
            }
        }
    }

    func retry() {
        guard operation == nil else { return }
        start()
    }

    func suspend() {
        operation?.cancel()
        operation = nil
        Task { await connection.cancel() }
        reducer.markOffline()
        attachState = .offline
        scheduleRender()
    }

    func resume() {
        guard attachState == .offline else { return }
        start()
    }

    func detach() {
        intentionallyDetached = true
        operation?.cancel()
        operation = nil
        renderTask?.cancel()
        renderTask = nil
        Task { await connection.cancel() }
        queue.removeAll()
        reducer.detach()
        attachState = .detached
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
                    scheduleRender()
                    return
                }
            }
            attachState = reducer.state
        }
        outputSequence = reducer.cursor.outputSequence
        scheduleRender()
    }

    private func finish(error: Error) {
        operation = nil
        guard !intentionallyDetached else { return }
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
