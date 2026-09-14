import Foundation
import Testing
@testable import PhotoTinder

struct ReviewStoreTests {
    @Test("An absent store starts empty")
    func newStore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        #expect(try await store.load() == ReviewState())
    }

    @Test("Relaunch restores exact session order, current card, queue, and undo")
    func roundTrip() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "review.json")
        let store = ReviewStore(url: url)
        var state = ReviewState()
        state.startSession(ids: ["c", "a", "b", "d"], title: "Shuffle")
        state.decide(id: "c", action: .delete)
        state.decide(id: "a", action: .skip)
        try await store.save(state)
        var restored = try await ReviewStore(url: url).load()
        #expect(restored == state)
        #expect(restored.session?.currentID == "b")
        #expect(restored.queueIDs == ["c"])
        let acceptedAction1 = restored.undo()
        #expect(acceptedAction1)
        #expect(restored.session?.currentID == "a")
        #expect(restored.session?.skippedCount == 0)
    }

    @Test("An older asynchronous save cannot overwrite newer progress")
    func staleSave() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        var state = ReviewState()
        state.startSession(ids: ["a", "b"], title: "Photos")
        let old = state
        state.decide(id: "a", action: .delete)
        try await store.save(state)
        try await store.save(old)
        #expect(try await store.load() == state)
    }

    @Test("Concurrent saves finish with the newest revision")
    func concurrentSaves() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReviewStore(url: directory.appending(path: "review.json"))
        var state = ReviewState()
        state.startSession(ids: (0..<30).map(String.init), title: "Photos")
        var snapshots = [state]
        for index in 0..<30 {
            state.decide(id: String(index), action: .delete)
            snapshots.append(state)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for snapshot in snapshots.reversed() {
                group.addTask { try await store.save(snapshot) }
            }
            try await group.waitForAll()
        }
        #expect(try await store.load() == state)
    }

    @Test("Corruption is reported and original bytes survive subsequent save attempts")
    func corruptionPreserved() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "review.json")
        let corrupt = Data("{unfinished".utf8)
        try corrupt.write(to: url)
        let store = ReviewStore(url: url)
        await #expect(throws: ReviewStoreError.corruptData) { try await store.load() }
        await #expect(throws: ReviewStoreError.recoveryRequired) { try await store.save(ReviewState()) }
        #expect(try Data(contentsOf: url) == corrupt)
        try await store.replace(with: ReviewState())
        #expect(try await store.load() == ReviewState())
    }

    @Test("Unsupported versions do not silently reset progress")
    func unsupportedVersion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "review.json")
        let store = ReviewStore(url: url)
        try await store.save(ReviewState())
        var contents = try String(contentsOf: url, encoding: .utf8)
        contents = contents.replacingOccurrences(of: "\"version\":1", with: "\"version\":99")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        await #expect(throws: ReviewStoreError.unsupportedVersion(99)) { try await store.load() }
        #expect(try String(contentsOf: url, encoding: .utf8) == contents)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PhotoTinderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
