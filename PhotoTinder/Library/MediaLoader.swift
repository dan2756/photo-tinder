import AVFoundation
import Observation
import Photos
import UIKit

enum MediaRequestKind: Sendable {
    case thumbnail
    case card
    case inspection
}

@MainActor
@Observable
final class MediaLoader {
    private(set) var image: UIImage?
    private(set) var player: AVPlayer?
    private(set) var livePhoto: PHLivePhoto?
    private(set) var progress: Double = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isPlaying = false
    private(set) var isMuted = true

    @ObservationIgnored private let manager: PHCachingImageManager
    @ObservationIgnored private let metadata: PhotoMetadataReader
    @ObservationIgnored private var requestIDs: [PHImageRequestID] = []
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastRequest: (item: MediaItem, size: CGSize, kind: MediaRequestKind)?
    @ObservationIgnored private var playerObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerItemObservation: NSKeyValueObservation?
    @ObservationIgnored private var imagePending = false
    @ObservationIgnored private var playbackPending = false

    init(manager: PHCachingImageManager, metadata: PhotoMetadataReader) {
        self.manager = manager
        self.metadata = metadata
    }

    isolated deinit {
        fetchTask?.cancel()
        for requestID in requestIDs { manager.cancelImageRequest(requestID) }
        player?.pause()
        playerObservation?.invalidate()
        playerItemObservation?.invalidate()
    }

    func load(item: MediaItem, targetSize: CGSize, kind: MediaRequestKind = .card) {
        cancel()
        lastRequest = (item, targetSize, kind)
        isLoading = true
        imagePending = true
        playbackPending = kind != .thumbnail && item.kind != .photo
        let token = generation
        fetchTask = Task { [weak self, metadata] in
            guard !Task.isCancelled else { return }
            let asset = await metadata.asset(id: item.id)
            guard !Task.isCancelled, let self, self.generation == token else { return }
            guard let asset else {
                self.errorMessage = "This item is no longer accessible. You can skip it or update photo access."
                self.isLoading = false
                return
            }
            let size = Self.boundedSize(targetSize, kind: kind)
            self.requestImage(asset: asset, size: size, token: token)
            if kind != .thumbnail {
                switch item.kind {
                case .photo: break
                case .video: self.requestVideo(asset: asset, token: token)
                case .livePhoto: self.requestLivePhoto(asset: asset, size: size, token: token)
                }
            }
        }
    }

    func retry() {
        guard let lastRequest else { return }
        load(item: lastRequest.item, targetSize: lastRequest.size, kind: lastRequest.kind)
    }

    func cancel() {
        generation += 1
        fetchTask?.cancel()
        fetchTask = nil
        for requestID in requestIDs { manager.cancelImageRequest(requestID) }
        requestIDs.removeAll()
        pause()
        playerObservation?.invalidate()
        playerObservation = nil
        playerItemObservation?.invalidate()
        playerItemObservation = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        livePhoto = nil
        image = nil
        progress = 0
        errorMessage = nil
        isLoading = false
        imagePending = false
        playbackPending = false
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        guard let player else { return }
        if player.rate != 0 {
            pause()
        } else {
            if let item = player.currentItem,
               item.duration.isNumeric,
               player.currentTime() >= item.duration {
                player.seek(to: .zero)
            }
            player.play()
            isPlaying = true
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
    }

    static func boundedSize(_ size: CGSize, kind: MediaRequestKind) -> CGSize {
        let cap: CGFloat = switch kind {
        case .thumbnail: 360
        case .card: 1600
        case .inspection: 3000
        }
        let width = max(1, size.width.isFinite ? size.width : cap)
        let height = max(1, size.height.isFinite ? size.height : cap)
        let ratio = min(1, cap / max(width, height))
        return CGSize(width: min(cap, (width * ratio).rounded(.up)), height: min(cap, (height * ratio).rounded(.up)))
    }

    static func imageOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        return options
    }

    private func requestImage(asset: PHAsset, size: CGSize, token: Int) {
        let options = Self.imageOptions()
        options.progressHandler = { @Sendable [weak self] progress, error, _, _ in
            let message = error?.localizedDescription
            Task { @MainActor in self?.receiveProgress(progress, message: message, token: token) }
        }
        let requestID = manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { @Sendable [weak self] image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let message = (info?[PHImageErrorKey] as? Error)?.localizedDescription
            Task { @MainActor in
                guard let self, self.generation == token, !cancelled else { return }
                guard !degraded || self.imagePending else { return }
                if let image { self.image = image }
                if !degraded {
                    self.imagePending = false
                    if image == nil { self.errorMessage = message ?? "Could not load this item. Check your connection and try again, or skip it for now." }
                    self.updateLoadingState()
                }
            }
        }
        requestIDs.append(requestID)
    }

    private func requestVideo(asset: PHAsset, token: Int) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        options.progressHandler = { @Sendable [weak self] progress, error, _, _ in
            let message = error?.localizedDescription
            Task { @MainActor in self?.receiveProgress(progress, message: message, token: token) }
        }
        let requestID = manager.requestPlayerItem(forVideo: asset, options: options) { @Sendable [weak self] item, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let message = (info?[PHImageErrorKey] as? Error)?.localizedDescription
            Task { @MainActor in
                guard let self, self.generation == token, !cancelled else { return }
                self.playbackPending = false
                if let item {
                    let player = AVPlayer(playerItem: item)
                    player.isMuted = self.isMuted
                    self.player = player
                    self.playerObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
                        Task { @MainActor in
                            guard let self, self.generation == token else { return }
                            self.isPlaying = self.player?.timeControlStatus == .playing
                        }
                    }
                    self.playerItemObservation = item.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] _, _ in
                        Task { @MainActor in
                            guard let self, self.generation == token,
                                  let item = self.player?.currentItem,
                                  item.status == .failed else { return }
                            self.pause()
                            let detail = item.error?.localizedDescription ?? "The video could not be played."
                            self.errorMessage = "\(detail) Check your connection and tap Retry, or skip this item for now."
                            self.playbackPending = false
                            self.updateLoadingState()
                        }
                    }
                } else {
                    self.errorMessage = message ?? "Could not load this video. Check your connection and try again, or skip it for now."
                }
                self.updateLoadingState()
            }
        }
        requestIDs.append(requestID)
    }

    private func requestLivePhoto(asset: PHAsset, size: CGSize, token: Int) {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.progressHandler = { @Sendable [weak self] progress, error, _, _ in
            let message = error?.localizedDescription
            Task { @MainActor in self?.receiveProgress(progress, message: message, token: token) }
        }
        let requestID = manager.requestLivePhoto(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { @Sendable [weak self] livePhoto, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let message = (info?[PHImageErrorKey] as? Error)?.localizedDescription
            Task { @MainActor in
                guard let self, self.generation == token, !cancelled else { return }
                guard !degraded || self.playbackPending else { return }
                if let livePhoto { self.livePhoto = livePhoto }
                if !degraded {
                    self.playbackPending = false
                    if livePhoto == nil { self.errorMessage = message ?? "Could not load Live Photo motion. Try again, or skip this item for now." }
                    self.updateLoadingState()
                }
            }
        }
        requestIDs.append(requestID)
    }

    private func receiveProgress(_ progress: Double, message: String?, token: Int) {
        guard generation == token else { return }
        self.progress = min(1, max(self.progress, progress))
        if let message { errorMessage = message }
    }

    private func updateLoadingState() {
        isLoading = imagePending || playbackPending
        if !isLoading && errorMessage == nil { progress = 1 }
    }
}
