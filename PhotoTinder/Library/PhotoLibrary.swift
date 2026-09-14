import Foundation
import Observation
import Photos
import PhotosUI
import UIKit

enum PhotoLibraryError: LocalizedError {
    case accessRequired
    case selectionUnavailable
    case deletionInProgress

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            "Photo access is required. Your deletion queue has been kept."
        case .selectionUnavailable:
            "Some selected items are no longer accessible. Refresh your library or manage photo access, then try again. Your queue has been kept."
        case .deletionInProgress:
            "A deletion request is already in progress."
        }
    }
}

actor PhotoMetadataReader {
    func readItems() async throws -> [MediaItem] {
        try Task.checkCancellation()
        let selfies = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
        var selfieIDs = Set<String>()
        for index in 0..<selfies.count {
            let assets = PHAsset.fetchAssets(in: selfies.object(at: index), options: nil)
            for assetIndex in 0..<assets.count {
                try Task.checkCancellation()
                selfieIDs.insert(assets.object(at: assetIndex).localIdentifier)
                if assetIndex.isMultiple(of: 256) { await Task.yield() }
            }
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: options)
        var items: [MediaItem] = []
        items.reserveCapacity(result.count)
        for index in 0..<result.count {
            try Task.checkCancellation()
            let item: MediaItem = autoreleasepool {
                let asset = result.object(at: index)
                let kind: MediaKind = asset.mediaType == .video ? .video : (asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo)
                let coordinate = asset.location?.coordinate
                return MediaItem(
                    id: asset.localIdentifier,
                    kind: kind,
                    captureDate: asset.creationDate,
                    duration: asset.duration,
                    isFavorite: asset.isFavorite,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    isSelfie: selfieIDs.contains(asset.localIdentifier),
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude
                )
            }
            items.append(item)
            if index.isMultiple(of: 256) { await Task.yield() }
        }
        return items
    }

    func asset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func assets(ids: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        return (0..<result.count).map { result.object(at: $0) }
    }
}

@MainActor
@Observable
final class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var authorization: PHAuthorizationStatus
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var isDeleting = false
    private(set) var errorMessage: String?
    private(set) var revision = 0

    @ObservationIgnored private let metadata = PhotoMetadataReader()
    @ObservationIgnored private let imageManager = PHCachingImageManager()
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var metadataTask: Task<[MediaItem], Error>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchedAssets: [PHAsset] = []
    @ObservationIgnored private var prefetchSize = CGSize.zero

    var canRead: Bool { authorization == .authorized || authorization == .limited }

    override init() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
    }

    isolated deinit {
        metadataTask?.cancel()
        prefetchTask?.cancel()
        imageManager.stopCachingImagesForAllAssets()
        if isObserving { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    func requestAuthorization() async {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        await refresh()
    }

    func refresh() async {
        refreshGeneration += 1
        metadataTask?.cancel()
        metadataTask = nil
        let generation = refreshGeneration
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canRead else {
            items = []
            isLoading = false
            errorMessage = nil
            clearPrefetch()
            revision += 1
            return
        }
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        isLoading = true
        errorMessage = nil
        let task = Task { @concurrent [metadata] in
            try await metadata.readItems()
        }
        metadataTask = task
        do {
            let updated = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard generation == refreshGeneration else { return }
            authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            items = canRead ? updated : []
            revision += 1
        } catch is CancellationError {
            // A cancelled refresh leaves the last completed snapshot intact.
        } catch {
            guard generation == refreshGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == refreshGeneration {
            metadataTask = nil
            isLoading = false
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    func manageLimitedSelection() {
        guard authorization == .limited,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { @Sendable [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func delete(ids: Set<String>) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        guard !isDeleting else { throw PhotoLibraryError.deletionInProgress }
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .authorized || current == .limited else { throw PhotoLibraryError.accessRequired }
        isDeleting = true
        defer { isDeleting = false }
        try Task.checkCancellation()
        let assets = await metadata.assets(ids: Array(ids))
        let accessible = Set(assets.map(\.localIdentifier))
        guard accessible == ids else { throw PhotoLibraryError.selectionUnavailable }
        try Task.checkCancellation()
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        // Once PhotoKit commits, task cancellation cannot undo the library change.
        // The caller must record these exact IDs even if its view has disappeared.
        return accessible
    }

    func makeLoader() -> MediaLoader {
        MediaLoader(manager: imageManager, metadata: metadata)
    }

    func prefetch(ids: [String], targetSize: CGSize) {
        clearPrefetch()
        let boundedIDs = Array(ids.prefix(3))
        guard !boundedIDs.isEmpty else { return }
        let size = MediaLoader.boundedSize(targetSize, kind: .card)
        prefetchTask = Task { [weak self, metadata] in
            let assets = await metadata.assets(ids: boundedIDs)
            guard !Task.isCancelled, let self else { return }
            self.prefetchedAssets = assets
            self.prefetchSize = size
            self.imageManager.startCachingImages(for: assets, targetSize: size, contentMode: .aspectFit, options: MediaLoader.imageOptions())
        }
    }

    func clearPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        if !prefetchedAssets.isEmpty {
            imageManager.stopCachingImages(for: prefetchedAssets, targetSize: prefetchSize, contentMode: .aspectFit, options: MediaLoader.imageOptions())
            prefetchedAssets = []
        }
    }
}
