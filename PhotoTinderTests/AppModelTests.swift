import Foundation
import Testing
@testable import PhotoTinder

@MainActor
struct AppModelTests {
    @Test("Successful deletion records exactly the returned IDs and saves the remaining queue")
    func successfulDeletion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        var requested: [Set<String>] = []
        let model = AppModel(store: store, deletion: { ids in
            requested.append(ids)
            return ["a"]
        })
        model.review = queuedState()
        model.persist()

        await model.delete(["a", "b"])

        #expect(requested == [["a", "b"]])
        #expect(model.review.deletedIDs == ["a"])
        #expect(model.review.queueIDs == ["b"])
        #expect(model.review.decisions["a"] == nil)
        #expect(!model.review.canUndo)
        #expect(!model.isDeleting)
        #expect(!model.persistenceFailed)
        #expect(try await store.load() == model.review)
    }

    @Test("Failed or cancelled deletion preserves decisions, session undo, and deletion history", arguments: [DeletionFailure.failed, .cancelled])
    func unsuccessfulDeletion(failure: DeletionFailure) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        let model = AppModel(store: store, deletion: { _ in throw failure.error })
        model.review = queuedState()
        let original = model.review
        model.persist()

        await model.delete(["a"])

        #expect(model.review == original)
        #expect(model.review.queueIDs == ["a", "b"])
        #expect(model.review.deletedIDs.isEmpty)
        #expect(model.review.canUndo)
        #expect(!model.isDeleting)
        #expect(model.message?.contains("Your queue is unchanged") == true)
        #expect(try await store.load() == original)
    }

    @Test("A queued save failure stops deletion before the library operation")
    func pendingSaveFailurePreventsDeletion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "blocker", directoryHint: .notDirectory)
        try Data("not a directory".utf8).write(to: blocker)
        let store = ReviewStore(url: blocker.appending(path: "review.json"))
        var operationCount = 0
        let model = AppModel(store: store, deletion: { ids in
            operationCount += 1
            return ids
        })
        model.review = queuedState()
        let original = model.review
        model.persist()

        await model.delete(["a"])

        #expect(operationCount == 0)
        #expect(model.review == original)
        #expect(model.persistenceFailed)
        #expect(model.message?.contains("Progress could not be saved") == true)
        #expect(!model.isDeleting)
    }

    @Test("Reset publishes only after its replacement store succeeds")
    func successfulReset() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        let model = AppModel(store: store, deletion: { $0 })
        model.review = queuedState()
        model.persist()

        await model.resetHistory()

        #expect(model.review.decisions.isEmpty)
        #expect(model.review.session == nil)
        #expect(!model.isUpdatingProgress)
        #expect(!model.persistenceFailed)
        #expect(try await store.load() == model.review)
    }

    @Test("A failed reset preserves the live queue and undo history")
    func failedReset() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "blocker", directoryHint: .notDirectory)
        try Data("not a directory".utf8).write(to: blocker)
        let store = ReviewStore(url: blocker.appending(path: "review.json"))
        let model = AppModel(store: store, deletion: { $0 })
        model.review = queuedState()
        let original = model.review

        await model.resetHistory()

        #expect(model.review == original)
        #expect(model.review.queueIDs == ["a", "b"])
        #expect(model.review.canUndo)
        #expect(model.persistenceFailed)
        #expect(model.message?.contains("Your queue and history are unchanged") == true)
        #expect(!model.isUpdatingProgress)
    }

    @Test("Successful deletion retains its result and a subsequent save failure warning")
    func successfulDeletionWithSaveFailure() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeDirectory = directory.appending(path: "progress", directoryHint: .notDirectory)
        let store = ReviewStore(url: storeDirectory.appending(path: "review.json"))
        let model = AppModel(store: store, deletion: { ids in
            try FileManager.default.removeItem(at: storeDirectory)
            try Data("not a directory".utf8).write(to: storeDirectory)
            return ids
        })
        model.review = queuedState()
        model.persist()

        await model.delete(["a"])

        #expect(model.review.deletedIDs == ["a"])
        #expect(model.review.queueIDs == ["b"])
        #expect(model.persistenceFailed)
        #expect(model.message?.contains("Deleted 1 item") == true)
        #expect(model.message?.contains("Progress could not be saved") == true)
    }

    @Test("An in-flight deletion excludes another deletion, reset, and review mutations", .timeLimit(.minutes(1)))
    func deletionExcludesConcurrentMutations() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        let gate = DeletionGate()
        let model = AppModel(store: store, deletion: { ids in try await gate.delete(ids) })
        model.review = queuedState()
        let original = model.review
        model.persist()

        let operation = Task { await model.delete(["a"]) }
        await gate.waitUntilStarted()
        model.clearQueue()
        model.keepInstead(["a"])
        model.decide(id: "c", action: .keep)
        model.undo()
        model.start(category: .all, items: [MediaItem(id: "new")])
        await model.resetHistory()
        await model.delete(["b"])

        #expect(model.review == original)
        #expect(gate.requests == [["a"]])
        gate.finish(with: .failure(CancellationError()))
        await operation.value
        #expect(model.review == original)
        #expect(!model.isDeleting)
    }

    @Test("An empty category or already-reviewed selection preserves the saved session")
    func emptySessionDoesNotReplaceProgress() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        let model = AppModel(store: store, deletion: { $0 })
        model.review = queuedState()
        let original = model.review

        model.start(category: .screenshots, items: [])
        #expect(model.review == original)
        #expect(!model.showSession)

        model.start(category: .all, items: [MediaItem(id: "a"), MediaItem(id: "b")])
        #expect(model.review == original)
        #expect(!model.showSession)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PhotoTinderAppModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func queuedState() -> ReviewState {
        var result = ReviewState()
        result.startSession(ids: ["a", "b", "c"], title: "Test photos")
        result.decide(id: "a", action: .delete)
        result.decide(id: "b", action: .delete)
        return result
    }
}

enum DeletionFailure: Sendable {
    case failed
    case cancelled

    var error: any Error {
        switch self {
        case .failed: ScriptedDeletionError.failed
        case .cancelled: CancellationError()
        }
    }
}

private enum ScriptedDeletionError: Error {
    case failed
}

@MainActor
private final class DeletionGate {
    private(set) var requests: [Set<String>] = []
    private var completion: CheckedContinuation<Set<String>, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func delete(_ ids: Set<String>) async throws -> Set<String> {
        requests.append(ids)
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(with result: Result<Set<String>, any Error>) {
        completion?.resume(with: result)
        completion = nil
    }
}
