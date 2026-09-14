import SwiftUI
import Photos

@MainActor @Observable
final class AppModel {
    let library: PhotoLibrary
    var review = ReviewState()
    var isReady = false
    var isDeleting = false
    private(set) var isUpdatingProgress = false
    var persistenceFailed = false
    var message: String?
    var showSession = false
    var selectedTab = 0
    var haptics = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true {
        didSet { UserDefaults.standard.set(haptics, forKey: "haptics") }
    }
    var protectFavorites = UserDefaults.standard.object(forKey: "protectFavorites") as? Bool ?? true {
        didSet { UserDefaults.standard.set(protectFavorites, forKey: "protectFavorites") }
    }
    private let store: ReviewStore
    private let deletion: @MainActor (Set<String>) async throws -> Set<String>
    private var saveTask: Task<Void, Never>?

    init(
        store: ReviewStore? = nil,
        deletion: (@MainActor (Set<String>) async throws -> Set<String>)? = nil
    ) {
        let library = PhotoLibrary()
        self.library = library
        var filename = "review.json"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { filename = "ui-test-review.json" }
        #endif
        let folder = URL.applicationSupportDirectory.appending(path: "PhotoTinder", directoryHint: .isDirectory)
        self.store = store ?? ReviewStore(url: folder.appending(path: filename))
        self.deletion = deletion ?? { ids in try await library.delete(ids: ids) }
    }

    var hasAccess: Bool { library.authorization == .authorized || library.authorization == .limited }
    var eligible: [MediaItem] { review.eligibleItems(library.items, protectFavorites: protectFavorites) }
    var queue: [MediaItem] { library.items.filter { review.decisions[$0.id] == .pendingDeletion } }
    var unavailableQueueCount: Int { review.queueIDs.count - queue.count }
    var currentItem: MediaItem? {
        guard let id = review.session?.currentID else { return nil }
        return library.items.first { $0.id == id }
    }

    func load() async {
        guard !isReady else { return }
        do {
            review = try await store.load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--reset-review") {
                review.resetReviewHistory()
                try await store.save(review)
            }
            #endif
        } catch {
            persistenceFailed = true
            message = "Your saved review could not be opened. It has been preserved. Retry by reopening the app, or reset review history in Settings. \(error.localizedDescription)"
        }
        await library.refresh()
        reconcile()
        isReady = true
    }

    func persist() {
        let snapshot = review
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            do { try await store.save(snapshot) }
            catch {
                persistenceFailed = true
                message = "Progress could not be saved. Keep the app open and retry in Settings. \(error.localizedDescription)"
            }
        }
    }

    func reconcile() {
        guard !isDeleting, !isUpdatingProgress else { return }
        reconcileWithLibrary()
    }

    private func reconcileWithLibrary() {
        guard hasAccess, library.revision > 0, !library.isLoading, !persistenceFailed else { return }
        let prior = review
        review.reconcile(accessibleIDs: Set(library.items.map(\.id)))
        if prior != review { persist() }
    }

    func start(category: MediaCategory, items: [MediaItem]? = nil, title: String? = nil) {
        guard !isDeleting, !isUpdatingProgress, !persistenceFailed else { return }
        let candidates = review.eligibleItems(items ?? category.filter(eligible), protectFavorites: protectFavorites)
        guard !candidates.isEmpty else { return }
        review.startSession(ids: candidates.map(\.id), title: title ?? category.title, shuffle: true)
        persist()
        showSession = true
    }

    func decide(id: String, action: ReviewAction) {
        guard !isDeleting, !isUpdatingProgress, !persistenceFailed, review.decide(id: id, action: action) else { return }
        if haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        persist()
    }

    func undo() {
        guard !isDeleting, !isUpdatingProgress, !persistenceFailed, review.undo() else { return }
        if haptics { UISelectionFeedbackGenerator().selectionChanged() }
        persist()
    }

    func keepInstead(_ ids: Set<String>) {
        guard !isDeleting, !isUpdatingProgress, !persistenceFailed else { return }
        review.keepInstead(ids: ids)
        persist()
    }

    func clearQueue() {
        guard !isDeleting, !isUpdatingProgress, !persistenceFailed else { return }
        review.clearQueue()
        persist()
    }

    func resetHistory() async {
        guard !isDeleting, !isUpdatingProgress else { return }
        isUpdatingProgress = true
        defer { isUpdatingProgress = false; reconcile() }
        await saveTask?.value
        var reset = review
        reset.resetReviewHistory()
        do {
            try await store.replace(with: reset)
            review = reset
            persistenceFailed = false
            message = nil
        } catch {
            persistenceFailed = true
            message = "Review history could not be reset. Your queue and history are unchanged. \(error.localizedDescription)"
        }
    }

    func retrySave() async {
        guard !isDeleting, !isUpdatingProgress else { return }
        isUpdatingProgress = true
        defer { isUpdatingProgress = false; reconcile() }
        await saveTask?.value
        do {
            try await store.save(review)
            persistenceFailed = false
            message = nil
        }
        catch { message = error.localizedDescription }
    }

    func delete(_ ids: Set<String>) async {
        guard !isDeleting, !isUpdatingProgress, !persistenceFailed, !ids.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false; reconcile() }
        await saveTask?.value
        guard !persistenceFailed else { return }
        do {
            try Task.checkCancellation()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--simulate-delete-failure") {
                throw NSError(domain: "PhotoTinderUITest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated deletion failure. Your queue is unchanged."])
            }
            #endif
            let deleted = try await deletion(ids)
            review.completeDeletion(ids: deleted)
            persist()
            await saveTask?.value
            await library.refresh()
            reconcileWithLibrary()
            await saveTask?.value
            let result = "Deleted \(deleted.count) \(deleted.count == 1 ? "item" : "items") from Photos. You can recover them in Recently Deleted for up to 30 days. Swipe Undo cannot restore deleted items."
            message = persistenceFailed ? result + "\n\n" + (message ?? "Progress could not be saved. Retry saving in Settings.") : result
        } catch {
            message = "Deletion did not complete. Your queue is unchanged. \(error.localizedDescription)"
        }
    }
}

@main
struct PhotoTinderApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup { RootView(model: model).tint(Color("AccentColor")) }
    }
}
