import Foundation

enum ReadOnlyAttachFailure: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidLimits
    case invalidTransition
    case invalidViewport
    case emptyFrame
    case frameTooLarge
    case queueFull
    case queueBytesExceeded
    case sessionMismatch
    case conflictingDuplicate
    case sequenceOverflow
}

enum ReadOnlyAttachState: Equatable, Sendable {
    case detached
    case authenticating
    case snapshot
    case replaying
    case live
    case gap(expected: UInt64, received: UInt64)
    case exited
    case offline
    case failed(ReadOnlyAttachFailure)
}

struct ReadOnlyAttachIdentity: Equatable, Hashable, Sendable {
    let hostID: String
    let sessionID: UUID
    let occupantGeneration: UInt64

    func validate() throws {
        guard !hostID.isEmpty,
              hostID.utf8.count <= 256,
              occupantGeneration > 0 else {
            throw ReadOnlyAttachFailure.invalidIdentity
        }
    }
}

struct TerminalStreamCursor: Equatable, Sendable {
    let identity: ReadOnlyAttachIdentity
    fileprivate(set) var outputSequence: UInt64
}

struct TerminalViewportState: Equatable, Sendable {
    let columns: Int
    let rows: Int
}

struct TerminalLimits: Equatable, Sendable {
    static let controllerDefault = Self()

    let maxColumns: Int
    let maxRows: Int
    let maxFrameBytes: Int
    let maxQueuedFrames: Int
    let maxQueuedFrameBytes: Int
    let maxScrollbackRows: Int
    let maxRetainedCells: Int
    let maxGraphemeBytes: Int
    let maxStyleBytes: Int
    let maxParserCarryBytes: Int
    let maxModelBytes: Int

    init(
        maxColumns: Int = 400,
        maxRows: Int = 200,
        maxFrameBytes: Int = 1 * 1_024 * 1_024,
        maxQueuedFrames: Int = 64,
        maxQueuedFrameBytes: Int = 4 * 1_024 * 1_024,
        maxScrollbackRows: Int = 50_000,
        maxRetainedCells: Int = 1_000_000,
        maxGraphemeBytes: Int = 16 * 1_024 * 1_024,
        maxStyleBytes: Int = 8 * 1_024 * 1_024,
        maxParserCarryBytes: Int = 4 * 1_024 * 1_024,
        maxModelBytes: Int = 32 * 1_024 * 1_024
    ) {
        self.maxColumns = maxColumns
        self.maxRows = maxRows
        self.maxFrameBytes = maxFrameBytes
        self.maxQueuedFrames = maxQueuedFrames
        self.maxQueuedFrameBytes = maxQueuedFrameBytes
        self.maxScrollbackRows = maxScrollbackRows
        self.maxRetainedCells = maxRetainedCells
        self.maxGraphemeBytes = maxGraphemeBytes
        self.maxStyleBytes = maxStyleBytes
        self.maxParserCarryBytes = maxParserCarryBytes
        self.maxModelBytes = maxModelBytes
    }

    func validate() throws {
        let values = [
            maxColumns, maxRows, maxFrameBytes, maxQueuedFrames, maxQueuedFrameBytes,
            maxScrollbackRows, maxRetainedCells, maxGraphemeBytes, maxStyleBytes,
            maxParserCarryBytes, maxModelBytes,
        ]
        guard values.allSatisfy({ $0 > 0 }),
              maxFrameBytes <= maxQueuedFrameBytes,
              maxQueuedFrameBytes <= maxModelBytes,
              maxGraphemeBytes <= maxModelBytes,
              maxStyleBytes <= maxModelBytes,
              maxParserCarryBytes <= maxModelBytes else {
            throw ReadOnlyAttachFailure.invalidLimits
        }
    }

    func validate(viewport: TerminalViewportState) throws {
        try validate()
        guard viewport.columns > 0,
              viewport.rows > 0,
              viewport.columns <= maxColumns,
              viewport.rows <= maxRows else {
            throw ReadOnlyAttachFailure.invalidViewport
        }
    }
}

struct TerminalOutputFrame: Equatable, Sendable {
    let sessionID: UUID
    let sequence: UInt64
    let bytes: Data
}

enum ReadOnlyOutputDisposition: Equatable, Sendable {
    case deliver
    case duplicate
    case gap(expected: UInt64, received: UInt64)
}

struct BoundedTerminalFrameQueue: Sendable {
    private let limits: TerminalLimits
    private var frames: [TerminalOutputFrame] = []
    private(set) var queuedBytes = 0

    init(limits: TerminalLimits = .controllerDefault) throws {
        try limits.validate()
        self.limits = limits
    }

    var count: Int { frames.count }
    var isEmpty: Bool { frames.isEmpty }

    mutating func enqueue(_ frame: TerminalOutputFrame) throws {
        guard !frame.bytes.isEmpty else { throw ReadOnlyAttachFailure.emptyFrame }
        guard frame.bytes.count <= limits.maxFrameBytes else {
            throw ReadOnlyAttachFailure.frameTooLarge
        }
        guard frames.count < limits.maxQueuedFrames else {
            throw ReadOnlyAttachFailure.queueFull
        }
        guard frame.bytes.count <= limits.maxQueuedFrameBytes - queuedBytes else {
            throw ReadOnlyAttachFailure.queueBytesExceeded
        }
        frames.append(frame)
        queuedBytes += frame.bytes.count
    }

    mutating func dequeue() -> TerminalOutputFrame? {
        guard !frames.isEmpty else { return nil }
        let frame = frames.removeFirst()
        queuedBytes -= frame.bytes.count
        return frame
    }

    mutating func removeAll() {
        frames.removeAll(keepingCapacity: true)
        queuedBytes = 0
    }
}

struct ReadOnlyAttachReducer: Sendable {
    private let limits: TerminalLimits
    private var recentFrames: [UInt64: Data] = [:]
    private var recentOrder: [UInt64] = []
    private var recentBytes = 0

    private(set) var state: ReadOnlyAttachState = .detached
    private(set) var cursor: TerminalStreamCursor

    init(
        identity: ReadOnlyAttachIdentity,
        fromSequence: UInt64 = 0,
        limits: TerminalLimits = .controllerDefault
    ) throws {
        try identity.validate()
        try limits.validate()
        self.limits = limits
        self.cursor = TerminalStreamCursor(identity: identity, outputSequence: fromSequence)
    }

    mutating func beginAuthentication() throws {
        guard state == .detached || state == .offline else {
            throw fail(.invalidTransition)
        }
        state = .authenticating
    }

    mutating func beginSnapshot() throws {
        guard state == .authenticating else { throw fail(.invalidTransition) }
        state = .snapshot
    }

    mutating func finishSnapshot(boundary: UInt64) throws {
        guard state == .snapshot, boundary >= cursor.outputSequence else {
            throw fail(.invalidTransition)
        }
        cursor.outputSequence = boundary
        recentFrames.removeAll(keepingCapacity: true)
        recentOrder.removeAll(keepingCapacity: true)
        recentBytes = 0
        state = .replaying
    }

    mutating func beginReplayWithoutSnapshot() throws {
        guard state == .authenticating else { throw fail(.invalidTransition) }
        state = .replaying
    }

    mutating func markLive() throws {
        guard state == .replaying || state == .live else {
            throw fail(.invalidTransition)
        }
        state = .live
    }

    mutating func observe(_ frame: TerminalOutputFrame) throws -> ReadOnlyOutputDisposition {
        guard state == .replaying || state == .live else {
            throw fail(.invalidTransition)
        }
        guard frame.sessionID == cursor.identity.sessionID else {
            throw fail(.sessionMismatch)
        }
        guard !frame.bytes.isEmpty else { throw fail(.emptyFrame) }
        guard frame.bytes.count <= limits.maxFrameBytes else {
            throw fail(.frameTooLarge)
        }
        guard frame.sequence > 0 else { throw fail(.sequenceOverflow) }

        if frame.sequence <= cursor.outputSequence {
            guard recentFrames[frame.sequence] == frame.bytes else {
                throw fail(.conflictingDuplicate)
            }
            return .duplicate
        }

        guard cursor.outputSequence < UInt64.max else {
            throw fail(.sequenceOverflow)
        }
        let expected = cursor.outputSequence + 1
        guard frame.sequence == expected else {
            state = .gap(expected: expected, received: frame.sequence)
            return .gap(expected: expected, received: frame.sequence)
        }

        cursor.outputSequence = frame.sequence
        remember(frame)
        return .deliver
    }

    mutating func markOffline() {
        state = .offline
    }

    mutating func markExited() {
        state = .exited
    }

    mutating func detach() {
        recentFrames.removeAll(keepingCapacity: false)
        recentOrder.removeAll(keepingCapacity: false)
        recentBytes = 0
        state = .detached
    }

    private mutating func remember(_ frame: TerminalOutputFrame) {
        recentFrames[frame.sequence] = frame.bytes
        recentOrder.append(frame.sequence)
        recentBytes += frame.bytes.count
        while recentOrder.count > limits.maxQueuedFrames
            || recentBytes > limits.maxQueuedFrameBytes {
            let sequence = recentOrder.removeFirst()
            if let removed = recentFrames.removeValue(forKey: sequence) {
                recentBytes -= removed.count
            }
        }
    }

    private mutating func fail(_ failure: ReadOnlyAttachFailure) -> ReadOnlyAttachFailure {
        state = .failed(failure)
        return failure
    }
}
