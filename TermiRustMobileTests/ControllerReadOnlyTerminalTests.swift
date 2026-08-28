import Foundation
import XCTest
@testable import TermiRustMobile

final class ControllerReadOnlyTerminalTests: XCTestCase {
    func testLimitsEnforceViewportAndFrameBoundaries() throws {
        let limits = TerminalLimits.controllerDefault
        XCTAssertNoThrow(try limits.validate(viewport: TerminalViewportState(columns: 400, rows: 200)))
        XCTAssertThrowsError(
            try limits.validate(viewport: TerminalViewportState(columns: 401, rows: 200))
        ) { error in
            XCTAssertEqual(error as? ReadOnlyAttachFailure, .invalidViewport)
        }

        var queue = try BoundedTerminalFrameQueue(limits: limits)
        XCTAssertThrowsError(
            try queue.enqueue(frame(sequence: 1, bytes: Data(count: limits.maxFrameBytes + 1)))
        ) { error in
            XCTAssertEqual(error as? ReadOnlyAttachFailure, .frameTooLarge)
        }
    }

    func testQueueRejectsSixtyFifthFrameWithoutDroppingAcceptedOutput() throws {
        var queue = try BoundedTerminalFrameQueue()
        for sequence in 1...64 {
            try queue.enqueue(frame(sequence: UInt64(sequence), bytes: Data([UInt8(sequence)])))
        }

        XCTAssertEqual(queue.count, 64)
        XCTAssertEqual(queue.queuedBytes, 64)
        XCTAssertThrowsError(try queue.enqueue(frame(sequence: 65, bytes: Data([65])))) { error in
            XCTAssertEqual(error as? ReadOnlyAttachFailure, .queueFull)
        }
        XCTAssertEqual(queue.count, 64)
        XCTAssertEqual(queue.dequeue()?.sequence, 1)
        XCTAssertEqual(queue.count, 63)
    }

    func testQueueEnforcesAggregateByteBudget() throws {
        let limits = TerminalLimits(maxFrameBytes: 3, maxQueuedFrameBytes: 4)
        var queue = try BoundedTerminalFrameQueue(limits: limits)
        try queue.enqueue(frame(sequence: 1, bytes: Data([1, 2, 3])))

        XCTAssertThrowsError(try queue.enqueue(frame(sequence: 2, bytes: Data([4, 5])))) { error in
            XCTAssertEqual(error as? ReadOnlyAttachFailure, .queueBytesExceeded)
        }
        XCTAssertEqual(queue.queuedBytes, 3)
    }

    func testReducerDeliversContiguousOutputAndAcceptsOnlyIdenticalDuplicate() throws {
        var reducer = try makeReducer()
        try reducer.beginAuthentication()
        try reducer.beginReplayWithoutSnapshot()
        let first = frame(sequence: 1, bytes: Data("one".utf8))

        XCTAssertEqual(try reducer.observe(first), .deliver)
        XCTAssertEqual(try reducer.observe(first), .duplicate)
        XCTAssertEqual(reducer.cursor.outputSequence, 1)
        XCTAssertThrowsError(
            try reducer.observe(frame(sequence: 1, bytes: Data("changed".utf8)))
        ) { error in
            XCTAssertEqual(error as? ReadOnlyAttachFailure, .conflictingDuplicate)
        }
        XCTAssertEqual(reducer.state, .failed(.conflictingDuplicate))
    }

    func testReducerStopsAtGapWithoutAdvancingCursor() throws {
        var reducer = try makeReducer(fromSequence: 8)
        try reducer.beginAuthentication()
        try reducer.beginReplayWithoutSnapshot()

        XCTAssertEqual(
            try reducer.observe(frame(sequence: 10, bytes: Data("ten".utf8))),
            .gap(expected: 9, received: 10)
        )
        XCTAssertEqual(reducer.state, .gap(expected: 9, received: 10))
        XCTAssertEqual(reducer.cursor.outputSequence, 8)
    }

    func testReducerRejectsOutputForAnotherSession() throws {
        var reducer = try makeReducer()
        try reducer.beginAuthentication()
        try reducer.beginReplayWithoutSnapshot()
        let foreign = TerminalOutputFrame(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            sequence: 1,
            bytes: Data("foreign".utf8)
        )

        XCTAssertThrowsError(try reducer.observe(foreign)) { error in
            XCTAssertEqual(error as? ReadOnlyAttachFailure, .sessionMismatch)
        }
        XCTAssertEqual(reducer.state, .failed(.sessionMismatch))
    }

    func testSnapshotBoundaryResetsReplayCursor() throws {
        var reducer = try makeReducer(fromSequence: 4)
        try reducer.beginAuthentication()
        try reducer.beginSnapshot()
        try reducer.finishSnapshot(boundary: 20)

        XCTAssertEqual(reducer.state, .replaying)
        XCTAssertEqual(reducer.cursor.outputSequence, 20)
        XCTAssertEqual(
            try reducer.observe(frame(sequence: 21, bytes: Data("next".utf8))),
            .deliver
        )
        try reducer.markLive()
        XCTAssertEqual(reducer.state, .live)
    }

    private func makeReducer(fromSequence: UInt64 = 0) throws -> ReadOnlyAttachReducer {
        try ReadOnlyAttachReducer(
            identity: ReadOnlyAttachIdentity(
                hostID: "host-fingerprint",
                sessionID: sessionID,
                occupantGeneration: 7
            ),
            fromSequence: fromSequence
        )
    }

    private func frame(sequence: UInt64, bytes: Data) -> TerminalOutputFrame {
        TerminalOutputFrame(sessionID: sessionID, sequence: sequence, bytes: bytes)
    }

    private var sessionID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }
}
