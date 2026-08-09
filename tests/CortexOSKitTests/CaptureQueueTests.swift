import Foundation
import XCTest
@testable import CortexOSKit

final class CaptureQueueTests: XCTestCase {
    private func makeQueue() throws -> (CaptureQueue, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (CaptureQueue(storageDirectory: directory), directory)
    }

    func testPendingCaptureAbsorbsEditsBeforeUpload() async throws {
        let (queue, directory) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: directory) }

        await queue.enqueueNote(localNoteID: "local-note", title: "First title")
        let absorbed = await queue.updatePendingNote(
            localNoteID: "local-note",
            with: NoteUpdateRequest(title: "Refined title", action: "Ship the focused flow")
        )

        XCTAssertTrue(absorbed)
        let actions = await queue.pendingActions()
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, "Capture")
        XCTAssertEqual(actions.first?.title, "Refined title")
    }

    func testDeletingPendingCaptureCancelsItsUpload() async throws {
        let (queue, directory) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: directory) }

        await queue.enqueueNote(localNoteID: "local-note", title: "Temporary thought")
        let wasCancelled = await queue.cancelPendingNote(localNoteID: "local-note")
        XCTAssertTrue(wasCancelled)

        let counts = await queue.pendingCounts()
        XCTAssertEqual(counts.notes, 0)
        XCTAssertEqual(counts.total, 0)
    }

    func testNoteDeletionSupersedesQueuedUpdate() async throws {
        let (queue, directory) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: directory) }

        await queue.enqueueNoteUpdate(
            noteID: "server-note",
            title: "Updated locally",
            with: NoteUpdateRequest(title: "Updated locally")
        )
        await queue.enqueueNoteUpdate(
            noteID: "server-note",
            title: "Updated locally",
            with: NoteUpdateRequest(action: "Take the next step")
        )
        await queue.enqueueNoteDeletion(noteID: "server-note", title: "Updated locally")

        let counts = await queue.pendingCounts()
        let actions = await queue.pendingActions()
        XCTAssertEqual(counts.notes, 1)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, "Note removal")
    }

    func testQueuedChangesSurviveRelaunch() async throws {
        let (queue, directory) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: directory) }

        await queue.enqueueNoteUpdate(
            noteID: "server-note",
            title: "Kept safely",
            with: NoteUpdateRequest(title: "Kept safely")
        )
        let reloadedQueue = CaptureQueue(storageDirectory: directory)

        let counts = await reloadedQueue.pendingCounts()
        XCTAssertEqual(counts.notes, 1)
    }
}
