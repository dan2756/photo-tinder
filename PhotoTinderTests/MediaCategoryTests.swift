import Foundation
import Testing
@testable import PhotoTinder

struct MediaCategoryTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    @Test("Categories use actual metadata", arguments: [
        (MediaCategory.screenshots, "screenshot"),
        (.videos, "video"),
        (.selfies, "selfie"),
        (.places, "located"),
        (.livePhotos, "live")
    ])
    func actualMetadata(category: MediaCategory, expected: String) {
        let items = [
            MediaItem(id: "plain"),
            MediaItem(id: "screenshot", isScreenshot: true),
            MediaItem(id: "video", kind: .video, duration: 20),
            MediaItem(id: "selfie", isSelfie: true),
            MediaItem(id: "located", latitude: 37.7, longitude: -122.4),
            MediaItem(id: "live", kind: .livePhoto)
        ]
        #expect(category.filter(items).map(\.id) == [expected])
    }

    @Test("Recent uses capture time, includes its boundary, and excludes future or missing dates")
    func recentBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = try #require(calendar.date(byAdding: .day, value: -30, to: now))
        let items = [
            MediaItem(id: "now", captureDate: now),
            MediaItem(id: "boundary", captureDate: boundary),
            MediaItem(id: "old", captureDate: boundary.addingTimeInterval(-1)),
            MediaItem(id: "future", captureDate: now.addingTimeInterval(1)),
            MediaItem(id: "unknown")
        ]
        #expect(MediaCategory.recent.filter(items, now: now, calendar: calendar).map(\.id) == ["now", "boundary"])
    }

    @Test("Older means strictly more than one calendar year")
    func olderBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = try #require(calendar.date(byAdding: .year, value: -1, to: now))
        let items = [
            MediaItem(id: "old", captureDate: boundary.addingTimeInterval(-1)),
            MediaItem(id: "boundary", captureDate: boundary),
            MediaItem(id: "new", captureDate: now),
            MediaItem(id: "unknown")
        ]
        #expect(MediaCategory.older.filter(items, now: now, calendar: calendar).map(\.id) == ["old"])
    }

    @Test("The all-media category mixes photos, videos, and single Live Photo assets")
    func mixedMedia() {
        let items = [MediaItem(id: "p"), MediaItem(id: "v", kind: .video), MediaItem(id: "l", kind: .livePhoto)]
        #expect(MediaCategory.all.filter(items) == items)
        #expect(MediaCategory.livePhotos.filter(items).count == 1)
    }

    @Test("Places group saved coordinates and do not invent names or include invalid locations")
    func placeGroups() {
        let items = [
            MediaItem(id: "a", latitude: 37.75, longitude: -122.45),
            MediaItem(id: "b", latitude: 37.76, longitude: -122.46),
            MediaItem(id: "c", latitude: 40.71, longitude: -74.02),
            MediaItem(id: "missing"),
            MediaItem(id: "invalid", latitude: 91, longitude: 0)
        ]
        let groups = PlaceGroup.groups(from: items)
        #expect(groups.count == 2)
        #expect(groups[0].ids == ["a", "b"])
        #expect(groups[0].title == "Near 37.7, -122.5°")
        #expect(groups[1].ids == ["c"])
    }

    @Test("Video duration formatting", arguments: [
        (0.0, "0:00"), (9.9, "0:09"), (65.0, "1:05"), (3_661.0, "1:01:01")
    ])
    func duration(seconds: Double, expected: String) {
        #expect(MediaItem(id: "v", kind: .video, duration: seconds).durationLabel == expected)
    }
}
