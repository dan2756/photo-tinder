import Foundation
import Testing
@testable import PhotoTinder

struct ReviewStateTests {
    @Test("Buttons and swipes produce one decision for the current asset", arguments: [
        (ReviewAction.keep, Decision.kept),
        (.delete, .pendingDeletion)
    ])
    func decisionsAreGuarded(action: ReviewAction, expected: Decision) {
        var state = ReviewState()
        state.startSession(ids: ["a", "b"], title: "Photos")
        let acceptedAction1 = state.decide(id: "a", action: action)
        #expect(acceptedAction1)
        let acceptedAction2 = state.decide(id: "a", action: action)
        #expect(!acceptedAction2)
        #expect(state.decisions == ["a": expected])
        #expect(state.session?.currentID == "b")
        #expect(state.session?.completedCount == 1)
        #expect(state.session?.undoStack.count == 1)
    }

    @Test("A gesture for a stale card cannot consume the next card")
    func rejectsWrongCard() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b"], title: "Photos")
        let before = state
        let acceptedAction3 = state.decide(id: "b", action: .delete)
        #expect(!acceptedAction3)
        let acceptedAction4 = state.decide(id: "missing", action: .skip)
        #expect(!acceptedAction4)
        #expect(state == before)
    }

    @Test("Repeated undo restores the queue, card order, and skip state")
    func repeatedUndo() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b", "c"], title: "Photos")
        let beginning = state.session
        state.decide(id: "a", action: .delete)
        state.decide(id: "b", action: .skip)
        state.decide(id: "c", action: .keep)
        #expect(state.queueIDs == ["a"])
        #expect(state.session?.completedCount == 2)
        #expect(state.session?.skippedCount == 1)
        let acceptedAction5 = state.undo()
        #expect(acceptedAction5)
        #expect(state.session?.currentID == "c")
        #expect(state.decisions["c"] == nil)
        let acceptedAction6 = state.undo()
        #expect(acceptedAction6)
        #expect(state.session?.currentID == "b")
        #expect(state.session?.skippedIDs == [])
        let acceptedAction7 = state.undo()
        #expect(acceptedAction7)
        #expect(state.session == beginning)
        #expect(state.decisions.isEmpty)
        let acceptedAction8 = state.undo()
        #expect(!acceptedAction8)
    }

    @Test("Undo restores an exact preexisting decision", arguments: [Decision.kept, .pendingDeletion])
    func undoRestoresPriorDecision(prior: Decision) {
        let session = CleanupSession(title: "Restored", orderedIDs: ["a", "b"])
        var state = ReviewState(decisions: ["a": prior], session: session)
        state.decide(id: "a", action: .delete)
        let acceptedAction9 = state.undo()
        #expect(acceptedAction9)
        #expect(state.decisions["a"] == prior)
        #expect(state.session == session)
    }

    @Test("A skip does not recur in the same pass and stays eligible for the next")
    func skippedItemsWaitForNextSession() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b", "a"], title: "Mix")
        state.decide(id: "a", action: .skip)
        state.decide(id: "b", action: .keep)
        #expect(state.session?.isComplete == true)
        #expect(state.session?.completedCount == 1)
        #expect(state.decisions["a"] == nil)
        state.startSession(ids: ["a", "b"], title: "Next pass")
        #expect(state.session?.orderedIDs == ["a"])
        #expect(state.session?.skippedIDs == [])
    }

    @Test("Shuffle is deterministic under an injected generator and contains each eligible asset once")
    func shuffleIsUniqueAndStable() throws {
        let ids = (0..<100).map(String.init) + ["0", "1", "2", "kept", "queued", "deleted"]
        var first = ReviewState(decisions: ["kept": .kept, "queued": .pendingDeletion], deletedIDs: ["deleted"])
        var second = first
        var generatorA = SeededGenerator(seed: 42)
        var generatorB = SeededGenerator(seed: 42)
        first.startSession(ids: ids, title: "Shuffle", shuffle: true, using: &generatorA)
        second.startSession(ids: ids, title: "Shuffle", shuffle: true, using: &generatorB)
        let order = try #require(first.session?.orderedIDs)
        #expect(order == second.session?.orderedIDs)
        #expect(order.count == 100)
        #expect(Set(order) == Set((0..<100).map(String.init)))
        #expect(order != Array(ids.prefix(100)))
        first.decide(id: order[0], action: .keep)
        #expect(first.session?.orderedIDs == order)
    }

    @Test("Review decisions deduplicate across overlapping categories")
    func crossCategoryDeduplication() {
        let screenshot = MediaItem(id: "a", isScreenshot: true, isSelfie: true)
        let photo = MediaItem(id: "b")
        var state = ReviewState()
        state.startSession(ids: MediaCategory.screenshots.filter([screenshot, photo]).map(\.id), title: "Screenshots")
        state.decide(id: "a", action: .delete)
        #expect(state.eligibleItems(MediaCategory.selfies.filter([screenshot, photo])).isEmpty)
        state.startSession(ids: ["a", "b", "b"], title: "All")
        #expect(state.session?.orderedIDs == ["b"])
    }

    @Test("Favorite protection is an explicit eligibility option")
    func favoritesAreOptional() {
        let items = [MediaItem(id: "a", isFavorite: true), MediaItem(id: "b")]
        let state = ReviewState()
        #expect(state.eligibleItems(items).map(\.id) == ["a", "b"])
        #expect(state.eligibleItems(items, protectFavorites: true).map(\.id) == ["b"])
    }

    @Test("Keep Instead changes only queued selections and invalidates swipe undo")
    func keepInstead() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b", "c"], title: "Photos")
        state.decide(id: "a", action: .delete)
        state.decide(id: "b", action: .delete)
        state.keepInstead(ids: ["a", "c", "missing"])
        #expect(state.decisions == ["a": .kept, "b": .pendingDeletion])
        let acceptedAction10 = state.undo()
        #expect(!acceptedAction10)
        #expect(state.session?.currentID == "c")
    }

    @Test("Clearing the queue makes items unreviewed and cannot be reversed by swipe undo")
    func clearQueue() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b"], title: "Photos")
        state.decide(id: "a", action: .delete)
        state.decide(id: "b", action: .keep)
        state.clearQueue()
        #expect(state.decisions == ["b": .kept])
        #expect(state.isEligible(id: "a"))
        let acceptedAction11 = state.undo()
        #expect(!acceptedAction11)
        #expect(state.deletedIDs.isEmpty)
    }

    @Test("Successful selected deletion clears only successful IDs and invalidates undo")
    func selectedDeletion() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b", "c"], title: "Photos")
        state.decide(id: "a", action: .delete)
        state.decide(id: "b", action: .delete)
        state.completeDeletion(ids: ["a"])
        #expect(state.queueIDs == ["b"])
        #expect(state.deletedIDs == ["a"])
        #expect(state.session?.currentID == "c")
        let acceptedAction12 = state.undo()
        #expect(!acceptedAction12)
        #expect(!state.isEligible(id: "a"))
    }

    @Test("An empty successful result leaves the queue and history unchanged")
    func noDeletionSucceeded() {
        var state = ReviewState()
        state.startSession(ids: ["a"], title: "Photos")
        state.decide(id: "a", action: .delete)
        let before = state
        state.completeDeletion(ids: [])
        #expect(state == before)
        #expect(state.queueIDs == ["a"])
        #expect(state.deletedIDs.isEmpty)
    }

    @Test("Limited access changes preserve decisions without recording app deletions")
    func inaccessibleAssetsAreNotDeleted() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b", "c", "d"], title: "Photos")
        state.decide(id: "a", action: .delete)
        state.decide(id: "b", action: .keep)
        state.reconcile(accessibleIDs: ["d"])
        #expect(state.queueIDs == ["a"])
        #expect(state.decisions["b"] == .kept)
        #expect(state.session?.currentID == "d")
        #expect(state.deletedIDs.isEmpty)
        let acceptedAction13 = state.undo()
        #expect(!acceptedAction13)
        state.reconcile(accessibleIDs: ["a", "b", "c", "d", "new"])
        #expect(state.session?.orderedIDs == ["d"])
        #expect(!state.isEligible(id: "a"))
    }

    @Test("New assets do not disrupt an active session")
    func newlyDiscoveredAssetsWait() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b"], title: "Photos")
        let session = state.session
        state.reconcile(accessibleIDs: ["new", "a", "b"])
        #expect(state.session == session)
        #expect(state.isEligible(id: "new"))
    }

    @Test("Resetting review history never records a photo deletion")
    func resetHistory() {
        var state = ReviewState(decisions: ["a": .kept, "b": .pendingDeletion], deletedIDs: ["previously-deleted"])
        state.startSession(ids: ["c"], title: "Photos")
        state.resetReviewHistory()
        #expect(state.decisions.isEmpty)
        #expect(state.session == nil)
        #expect(state.deletedIDs == ["previously-deleted"])
    }

    @Test("Rapid repeated inputs cannot duplicate history or skip cards")
    func rapidInput() {
        var state = ReviewState()
        state.startSession(ids: ["a", "b", "c"], title: "Photos")
        for _ in 0..<100 { state.decide(id: "a", action: .delete) }
        #expect(state.queueCount == 1)
        #expect(state.session?.cursor == 1)
        #expect(state.session?.undoStack.count == 1)
        let acceptedAction14 = state.undo()
        #expect(acceptedAction14)
        #expect(state.queueCount == 0)
        #expect(state.session?.currentID == "a")
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed = 2_862_933_555_777_941_757 &* seed &+ 3_037_000_493
        return seed
    }
}
