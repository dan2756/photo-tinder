import AVFoundation
import Observation
import Photos
import XCTest
@testable import PhotoTinder

@MainActor
final class PhotoKitIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == "34C20ACC-6657-467B-BAF1-CF34097AE244",
            "Real PhotoKit tests run only on the dedicated disposable simulator."
        )
        #else
        throw XCTSkip("Real PhotoKit integration tests never run on a physical device.")
        #endif
        try XCTSkipUnless(
            PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
            "Grant full Photos access through the app's UI before running the seeded-library checks."
        )
    }

    func testImportedCaptureDatesLocationsAndVideoDuration() async throws {
        let (_, fixtures) = try await fixtureLibrary()
        let items = fixtures.map(\.item)
        XCTAssertFalse(MediaCategory.recent.filter(items).isEmpty, "Imported capture dates must include media captured within the past 30 days.")
        XCTAssertFalse(MediaCategory.older.filter(items).isEmpty, "Older JPEG capture dates must survive the simulator import.")
        XCTAssertGreaterThanOrEqual(PlaceGroup.groups(from: items).count, 2, "Imported GPS metadata must produce both fixture location groups.")
        let video = try XCTUnwrap(items.first(where: { $0.kind == .video }), "Seed the disposable four-second MOV first.")
        XCTAssertEqual(video.duration, 4, accuracy: 0.1)
        XCTAssertTrue(items.contains { item in
            guard let latitude = item.latitude, let longitude = item.longitude else { return false }
            return abs(latitude - 46.58) < 0.001 && abs(longitude - 7.96) < 0.001
        })
        XCTAssertTrue(items.contains { item in
            guard let latitude = item.latitude, let longitude = item.longitude else { return false }
            return abs(latitude - 36.24) < 0.001 && abs(longitude + 116.82) < 0.001
        })
    }

    func testSmartCategoriesUseActualPhotoKitClassification() async throws {
        let (_, fixtures) = try await fixtureLibrary()
        for fixture in fixtures {
            XCTAssertEqual(fixture.item.isScreenshot, fixture.isScreenshot, "Screenshot classification must come from PhotoKit.")
            XCTAssertEqual(fixture.item.isSelfie, fixture.isSelfie, "Selfie classification must come from the system smart album.")
            XCTAssertEqual(fixture.item.kind == .livePhoto, fixture.isLivePhoto, "A Live Photo remains a single PhotoKit asset.")
        }
        let screenGraphic = try XCTUnwrap(fixtures.first { $0.filename == "13-disposable-screen-like.png" })
        XCTAssertEqual(screenGraphic.item.kind, .photo)
        XCTAssertFalse(screenGraphic.item.isScreenshot, "A picture that resembles a screenshot must not become a screenshot category fixture.")
        XCTAssertFalse(screenGraphic.item.isSelfie)
    }

    func testShuffleCombinesRealPhotosAndVideoWithoutDuplicates() async throws {
        let (_, fixtures) = try await fixtureLibrary()
        let items = fixtures.map(\.item)
        var review = ReviewState()
        let overlap = items + MediaCategory.recent.filter(items) + MediaCategory.videos.filter(items)
        review.startSession(ids: overlap.map(\.id), title: "Real PhotoKit shuffle", shuffle: true)
        let session = try XCTUnwrap(review.session)
        XCTAssertEqual(Set(session.orderedIDs), Set(items.map(\.id)))
        XCTAssertEqual(session.orderedIDs.count, Set(items.map(\.id)).count)
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        XCTAssertTrue(session.orderedIDs.contains { itemByID[$0]?.kind == .photo })
        XCTAssertTrue(session.orderedIDs.contains { itemByID[$0]?.kind == .video })
    }

    func testRealPhotoLoadsAndCanBeCancelled() async throws {
        let (library, fixtures) = try await fixtureLibrary()
        let item = try XCTUnwrap(fixtures.first(where: { $0.item.kind == .photo })?.item)
        let loader = library.makeLoader()
        defer { loader.cancel() }
        loader.load(item: item, targetSize: CGSize(width: 300, height: 300), kind: .thumbnail)
        try await waitForMedia(loader)
        let image = try XCTUnwrap(loader.image)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertEqual(loader.progress, 1)
        loader.cancel()
        XCTAssertNil(loader.image)
        XCTAssertFalse(loader.isLoading)
        XCTAssertEqual(loader.progress, 0)
    }

    func testCardSizedPhotoContainsRealPixels() async throws {
        let (library, fixtures) = try await fixtureLibrary()
        let fixture = try XCTUnwrap(
            fixtures.first { $0.filename == "06-disposable-forest-stillness.jpg" }
                ?? fixtures.first { $0.item.kind == .photo }
        )
        let loader = library.makeLoader()
        defer { loader.cancel() }

        loader.load(item: fixture.item, targetSize: CGSize(width: 300, height: 300), kind: .thumbnail)
        try await waitForMedia(loader)
        let thumbnail = try XCTUnwrap(loader.image)
        let thumbnailAttachment = XCTAttachment(image: thumbnail)
        thumbnailAttachment.name = "PhotoKit-thumbnail-\(fixture.filename)"
        thumbnailAttachment.lifetime = .keepAlways
        add(thumbnailAttachment)

        loader.load(item: fixture.item, targetSize: CGSize(width: 1_200, height: 1_600), kind: .card)
        try await waitForMedia(loader)
        let card = try XCTUnwrap(loader.image)
        let cardAttachment = XCTAttachment(image: card)
        cardAttachment.name = "PhotoKit-card-\(fixture.filename)"
        cardAttachment.lifetime = .keepAlways
        add(cardAttachment)
        let cgImage = try XCTUnwrap(card.cgImage)
        let distinctColors = try sampledColorCount(cgImage)
        let diagnostic = XCTAttachment(string: """
        Filename: \(fixture.filename)
        PhotoKit asset dimensions: \(fixture.pixelWidth)x\(fixture.pixelHeight)
        Thumbnail UIImage: \(thumbnail.size), scale \(thumbnail.scale)
        Card UIImage: \(card.size), scale \(card.scale), orientation \(card.imageOrientation.rawValue), rendering mode \(card.renderingMode.rawValue)
        Card CGImage: \(cgImage.width)x\(cgImage.height), \(cgImage.bitsPerComponent) bits/component, \(cgImage.bitsPerPixel) bits/pixel
        Color space: \(String(describing: cgImage.colorSpace?.name)); bitmap info: \(cgImage.bitmapInfo.rawValue)
        Distinct quantized colors in 32x32 sample: \(distinctColors)
        """)
        diagnostic.name = "PhotoKit-card-bitmap-diagnostics"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)

        XCTAssertGreaterThan(distinctColors, 12, "The scenic drawing must contain varied pixels, not a uniform green bitmap.")
        XCTAssertEqual(
            Double(cgImage.width) / Double(cgImage.height),
            Double(fixture.pixelWidth) / Double(fixture.pixelHeight),
            accuracy: 0.02,
            "An aspect-fit card must preserve the original photo's aspect ratio."
        )
    }

    func testRealVideoLoadsPlaysMutesAndPauses() async throws {
        let (library, fixtures) = try await fixtureLibrary()
        let item = try XCTUnwrap(fixtures.first(where: { $0.item.kind == .video })?.item)
        let loader = library.makeLoader()
        defer { loader.cancel() }
        loader.load(item: item, targetSize: CGSize(width: 720, height: 1_080), kind: .card)
        try await waitForMedia(loader)
        let player = try XCTUnwrap(loader.player)
        XCTAssertTrue(player.isMuted)
        loader.setMuted(false)
        XCTAssertFalse(player.isMuted)

        let progressed = expectation(description: "The disposable video playback clock advances")
        progressed.assertForOverFulfill = false
        let timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { @Sendable time in
            if time.seconds > 0.1 { progressed.fulfill() }
        }
        defer { player.removeTimeObserver(timeObserver) }
        loader.togglePlayback()
        let playbackResult = await XCTWaiter.fulfillment(of: [progressed], timeout: 10)
        XCTAssertEqual(playbackResult, .completed)
        loader.pause()
        XCTAssertEqual(player.rate, 0)
        XCTAssertFalse(loader.isPlaying)
        loader.cancel()
        XCTAssertNil(loader.player)
        XCTAssertNil(player.currentItem)
    }

    private func fixtureLibrary() async throws -> (PhotoLibrary, [ImportedFixture]) {
        let library = PhotoLibrary()
        await library.refresh()
        XCTAssertNil(library.errorMessage)
        XCTAssertFalse(library.isLoading)
        let fixtures = await ImportedFixtureReader().read(items: library.items)
        try XCTSkipIf(fixtures.isEmpty, "Import test-support/media into the disposable simulator before running these checks.")
        return (library, fixtures)
    }

    private func waitForMedia(_ loader: MediaLoader) async throws {
        let loaded = expectation(description: "PhotoKit finishes its media request")
        let observer = MediaCompletionObservation(loader: loader, expectation: loaded)
        defer { observer.stop() }
        let result = await XCTWaiter.fulfillment(of: [loaded], timeout: 15)
        XCTAssertEqual(result, .completed)
        XCTAssertNil(loader.errorMessage)
        XCTAssertFalse(loader.isLoading)
    }

    private func sampledColorCount(_ image: CGImage) throws -> Int {
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                bytesPerRow: 32 * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var colors = Set<Int>()
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                colors.insert(Int(bytes[offset] / 16) << 8 | Int(bytes[offset + 1] / 16) << 4 | Int(bytes[offset + 2] / 16))
            }
            return colors.count
        }
    }
}

private struct ImportedFixture: Sendable {
    let filename: String
    let item: MediaItem
    let isScreenshot: Bool
    let isSelfie: Bool
    let isLivePhoto: Bool
    let pixelWidth: Int
    let pixelHeight: Int
}

private actor ImportedFixtureReader {
    func read(items: [MediaItem]) -> [ImportedFixture] {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
        var selfieIDs = Set<String>()
        for index in 0..<albums.count {
            let selfies = PHAsset.fetchAssets(in: albums.object(at: index), options: nil)
            for assetIndex in 0..<selfies.count { selfieIDs.insert(selfies.object(at: assetIndex).localIdentifier) }
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(itemByID.keys), options: nil)
        return (0..<assets.count).compactMap { index in
            let asset = assets.object(at: index)
            guard let item = itemByID[asset.localIdentifier],
                  let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename,
                  filename.contains("-disposable-") else { return nil }
            return ImportedFixture(
                filename: filename,
                item: item,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                isSelfie: selfieIDs.contains(asset.localIdentifier),
                isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            )
        }
    }
}

@MainActor
private final class MediaCompletionObservation {
    private weak var loader: MediaLoader?
    private let expectation: XCTestExpectation
    private var stopped = false

    init(loader: MediaLoader, expectation: XCTestExpectation) {
        self.loader = loader
        self.expectation = expectation
        track()
    }

    func stop() { stopped = true }

    private func track() {
        guard !stopped, let loader else { return }
        withObservationTracking {
            if !loader.isLoading {
                stopped = true
                expectation.fulfill()
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }
}
