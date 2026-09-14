import Foundation

enum Decision: String, Codable, Sendable {
    case kept
    case pendingDeletion
}

enum ReviewAction: String, Codable, Sendable, CaseIterable {
    case keep
    case delete
    case skip
}

struct ReviewUndo: Codable, Equatable, Sendable {
    let id: String
    let priorDecision: Decision?
    let wasSkipped: Bool
    let cursor: Int
}

struct CleanupSession: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    fileprivate(set) var orderedIDs: [String]
    fileprivate(set) var cursor: Int
    fileprivate(set) var skippedIDs: Set<String>
    fileprivate(set) var undoStack: [ReviewUndo]

    init(title: String, orderedIDs: [String]) {
        id = UUID()
        self.title = title
        var seen: Set<String> = []
        self.orderedIDs = orderedIDs.filter { seen.insert($0).inserted }
        cursor = 0
        skippedIDs = []
        undoStack = []
    }

    var currentID: String? {
        guard orderedIDs.indices.contains(cursor) else { return nil }
        return orderedIDs[cursor]
    }

    var isComplete: Bool { currentID == nil }
    var totalCount: Int { orderedIDs.count }
    var remainingCount: Int { max(0, orderedIDs.count - cursor) }
    var completedCount: Int { orderedIDs.prefix(cursor).filter { !skippedIDs.contains($0) }.count }
    var skippedCount: Int { skippedIDs.count }
    var canUndo: Bool { !undoStack.isEmpty }

    fileprivate mutating func removeIDs(_ ids: Set<String>) {
        let previousPrefix = orderedIDs.prefix(cursor)
        cursor = previousPrefix.filter { !ids.contains($0) }.count
        orderedIDs.removeAll { ids.contains($0) }
        skippedIDs.subtract(ids)
        undoStack.removeAll()
    }
}

struct ReviewState: Codable, Equatable, Sendable {
    private(set) var decisions: [String: Decision]
    private(set) var session: CleanupSession?
    private(set) var deletedIDs: Set<String>
    private(set) var revision: UInt64

    init(
        decisions: [String: Decision] = [:],
        session: CleanupSession? = nil,
        deletedIDs: Set<String> = [],
        revision: UInt64 = 0
    ) {
        self.decisions = decisions.filter { !deletedIDs.contains($0.key) }
        self.session = session
        self.deletedIDs = deletedIDs
        self.revision = revision
    }

    var queueIDs: [String] { decisions.compactMap { $0.value == .pendingDeletion ? $0.key : nil }.sorted() }
    var keptCount: Int { decisions.values.filter { $0 == .kept }.count }
    var queueCount: Int { decisions.values.filter { $0 == .pendingDeletion }.count }
    var canUndo: Bool { session?.canUndo == true }

    func isEligible(id: String) -> Bool {
        decisions[id] == nil && !deletedIDs.contains(id)
    }

    func eligibleItems(_ items: [MediaItem], protectFavorites: Bool = false) -> [MediaItem] {
        var seen: Set<String> = []
        return items.filter {
            isEligible(id: $0.id) && (!protectFavorites || !$0.isFavorite) && seen.insert($0.id).inserted
        }
    }

    mutating func startSession(ids: [String], title: String, shuffle: Bool = false) {
        var generator = SystemRandomNumberGenerator()
        startSession(ids: ids, title: title, shuffle: shuffle, using: &generator)
    }

    mutating func startSession<R: RandomNumberGenerator>(ids: [String], title: String, shuffle: Bool, using generator: inout R) {
        var seen: Set<String> = []
        var order = ids.filter { isEligible(id: $0) && seen.insert($0).inserted }
        if shuffle { order.shuffle(using: &generator) }
        session = order.isEmpty ? nil : CleanupSession(title: title, orderedIDs: order)
        revision += 1
    }

    @discardableResult
    mutating func decide(id: String, action: ReviewAction) -> Bool {
        guard var session, session.currentID == id, !deletedIDs.contains(id) else { return false }
        session.undoStack.append(ReviewUndo(id: id, priorDecision: decisions[id], wasSkipped: session.skippedIDs.contains(id), cursor: session.cursor))
        switch action {
        case .keep: decisions[id] = .kept
        case .delete: decisions[id] = .pendingDeletion
        case .skip: session.skippedIDs.insert(id)
        }
        session.cursor += 1
        self.session = session
        revision += 1
        return true
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard var session, let previous = session.undoStack.popLast(),
              !deletedIDs.contains(previous.id),
              session.orderedIDs.indices.contains(previous.cursor),
              session.orderedIDs[previous.cursor] == previous.id else { return false }
        decisions[previous.id] = previous.priorDecision
        if previous.wasSkipped { session.skippedIDs.insert(previous.id) }
        else { session.skippedIDs.remove(previous.id) }
        session.cursor = previous.cursor
        self.session = session
        revision += 1
        return true
    }

    mutating func clearQueue() {
        let queued = Set(queueIDs)
        guard !queued.isEmpty else { return }
        for id in queued { decisions.removeValue(forKey: id) }
        session?.undoStack.removeAll()
        revision += 1
    }

    mutating func keepInstead(ids: Set<String>) {
        let queued = ids.filter { decisions[$0] == .pendingDeletion }
        guard !queued.isEmpty else { return }
        for id in queued { decisions[id] = .kept }
        session?.undoStack.removeAll()
        revision += 1
    }

    mutating func completeDeletion(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for id in ids { decisions.removeValue(forKey: id) }
        deletedIDs.formUnion(ids)
        session?.removeIDs(ids)
        revision += 1
    }

    mutating func reconcile(accessibleIDs: Set<String>) {
        guard let session else { return }
        let inaccessible = Set(session.orderedIDs).subtracting(accessibleIDs)
        guard !inaccessible.isEmpty else { return }
        self.session?.removeIDs(inaccessible)
        revision += 1
    }

    mutating func resetReviewHistory() {
        decisions.removeAll()
        session = nil
        revision += 1
    }

    func validated() throws -> ReviewState {
        guard revision < UInt64.max, Set(decisions.keys).isDisjoint(with: deletedIDs) else {
            throw ReviewStoreError.corruptData
        }
        if let session {
            let ordered = Set(session.orderedIDs)
            let reviewedPrefix = Set(session.orderedIDs.prefix(max(0, session.cursor)))
            guard ordered.count == session.orderedIDs.count,
                  session.cursor >= 0, session.cursor <= session.orderedIDs.count,
                  session.skippedIDs.isSubset(of: reviewedPrefix),
                  ordered.isDisjoint(with: deletedIDs),
                  zip(session.undoStack, session.undoStack.dropFirst()).allSatisfy({ $0.cursor < $1.cursor }),
                  session.undoStack.allSatisfy({
                      session.orderedIDs.indices.contains($0.cursor)
                          && session.orderedIDs[$0.cursor] == $0.id
                          && $0.cursor < session.cursor
                  }) else { throw ReviewStoreError.corruptData }
        }
        return self
    }
}
