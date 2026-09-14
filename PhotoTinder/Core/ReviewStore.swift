import Foundation

enum ReviewStoreError: Error, LocalizedError, Equatable, Sendable {
    case corruptData
    case unsupportedVersion(Int)
    case recoveryRequired

    var errorDescription: String? {
        switch self {
        case .corruptData: "Saved review progress could not be read. The saved file has been preserved."
        case .unsupportedVersion: "Saved review progress was created by an unsupported app version."
        case .recoveryRequired: "Review progress cannot be saved until the saved-data problem is resolved."
        }
    }
}

actor ReviewStore {
    private struct Envelope: Codable {
        let version: Int
        let state: ReviewState
    }

    let url: URL
    private var lastSavedRevision: UInt64?
    private var recoveryRequired = false

    init(url: URL) {
        self.url = url
    }

    func load() throws -> ReviewState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastSavedRevision = nil
            recoveryRequired = false
            return ReviewState()
        }
        do {
            let data = try Data(contentsOf: url)
            let envelope: Envelope
            do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
            catch { throw ReviewStoreError.corruptData }
            guard envelope.version == 1 else { throw ReviewStoreError.unsupportedVersion(envelope.version) }
            let state = try envelope.state.validated()
            lastSavedRevision = state.revision
            recoveryRequired = false
            return state
        } catch {
            recoveryRequired = true
            throw error
        }
    }

    func save(_ state: ReviewState) throws {
        guard !recoveryRequired else { throw ReviewStoreError.recoveryRequired }
        if let lastSavedRevision, state.revision < lastSavedRevision { return }
        try write(state)
    }

    func replace(with state: ReviewState) throws {
        try write(state)
        recoveryRequired = false
    }

    private func write(_ state: ReviewState) throws {
        _ = try state.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: 1, state: state))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lastSavedRevision = state.revision
    }
}
