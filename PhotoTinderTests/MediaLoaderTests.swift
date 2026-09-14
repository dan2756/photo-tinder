import CoreGraphics
import Photos
import Testing
@testable import PhotoTinder

@MainActor
struct MediaLoaderTests {
    @Test("Image requests limit decoded pixels and retain portrait or panorama proportions", arguments: [
        (MediaRequestKind.thumbnail, CGSize(width: 1_200, height: 1_800), CGSize(width: 240, height: 360)),
        (.card, CGSize(width: 12_000, height: 3_000), CGSize(width: 1_600, height: 400)),
        (.card, CGSize(width: 1_200, height: 1_600), CGSize(width: 1_200, height: 1_600)),
        (.inspection, CGSize(width: 4_800, height: 6_000), CGSize(width: 2_400, height: 3_000)),
        (.inspection, CGSize(width: 80, height: 60), CGSize(width: 80, height: 60))
    ])
    func boundedDecodeSize(kind: MediaRequestKind, requested: CGSize, expected: CGSize) {
        #expect(MediaLoader.boundedSize(requested, kind: kind) == expected)
    }

    @Test("Transient invalid layout geometry cannot request a zero or unbounded bitmap", arguments: [
        CGSize.zero,
        CGSize(width: -20, height: -100),
        CGSize(width: CGFloat.infinity, height: CGFloat.nan),
        CGSize(width: CGFloat.greatestFiniteMagnitude, height: 1),
        CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
    ])
    func malformedGeometry(requested: CGSize) {
        let size = MediaLoader.boundedSize(requested, kind: .card)
        #expect(size.width.isFinite && size.height.isFinite)
        #expect(size.width >= 1 && size.width <= 1_600)
        #expect(size.height >= 1 && size.height <= 1_600)
    }

    @Test("Cancelling a scheduled load immediately clears its loading and playback state")
    func cancelBeforeAssetFetch() {
        let loader = MediaLoader(manager: PHCachingImageManager(), metadata: PhotoMetadataReader())
        loader.load(item: MediaItem(id: "never-fetched-test-identifier", kind: .video), targetSize: CGSize(width: 1_200, height: 1_600))
        #expect(loader.isLoading)
        loader.cancel()
        #expect(!loader.isLoading)
        #expect(!loader.isPlaying)
        #expect(loader.image == nil)
        #expect(loader.player == nil)
        #expect(loader.livePhoto == nil)
        #expect(loader.errorMessage == nil)
        #expect(loader.progress == 0)
        loader.cancel()
        #expect(!loader.isLoading)
    }
}
