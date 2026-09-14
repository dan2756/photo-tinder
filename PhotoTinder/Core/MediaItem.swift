import Foundation

enum MediaKind: String, Codable, Sendable, CaseIterable {
    case photo
    case video
    case livePhoto

    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .livePhoto: "Live Photo"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .livePhoto: "livephoto"
        }
    }
}

struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: MediaKind
    let captureDate: Date?
    let duration: Double
    let isFavorite: Bool
    let isScreenshot: Bool
    let isSelfie: Bool
    let latitude: Double?
    let longitude: Double?

    init(
        id: String,
        kind: MediaKind = .photo,
        captureDate: Date? = nil,
        duration: Double = 0,
        isFavorite: Bool = false,
        isScreenshot: Bool = false,
        isSelfie: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.captureDate = captureDate
        self.duration = duration
        self.isFavorite = isFavorite
        self.isScreenshot = isScreenshot
        self.isSelfie = isSelfie
        self.latitude = latitude
        self.longitude = longitude
    }

    var hasLocation: Bool {
        guard let latitude, let longitude else { return false }
        return latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    var durationLabel: String {
        guard duration.isFinite, duration > 0 else { return "0:00" }
        let seconds = Int(min(duration.rounded(.down), Double(Int.max / 2)))
        return seconds >= 3_600
            ? "\(seconds / 3_600):" + String(format: "%02d:%02d", seconds / 60 % 60, seconds % 60)
            : "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

enum MediaCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case screenshots
    case videos
    case selfies
    case places
    case livePhotos
    case recent
    case older

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Shuffle Library"
        case .screenshots: "Screenshots"
        case .videos: "Videos"
        case .selfies: "Selfies"
        case .places: "Places"
        case .livePhotos: "Live Photos"
        case .recent: "Recent"
        case .older: "Older"
        }
    }

    var symbol: String {
        switch self {
        case .all: "shuffle"
        case .screenshots: "viewfinder.rectangular"
        case .videos: "video"
        case .selfies: "person.crop.square"
        case .places: "map"
        case .livePhotos: "livephoto"
        case .recent: "clock"
        case .older: "calendar"
        }
    }

    var subtitle: String {
        switch self {
        case .all: "A random mix of your photos and videos."
        case .screenshots: "Captured from your screen"
        case .videos: "Clips in your library"
        case .selfies: "From the system Selfies album"
        case .places: "Grouped by saved photo locations"
        case .livePhotos: "A moment, with motion"
        case .recent: "Captured in the past 30 days"
        case .older: "Captured more than a year ago"
        }
    }

    func matches(_ item: MediaItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: return true
        case .screenshots: return item.isScreenshot
        case .videos: return item.kind == .video
        case .selfies: return item.isSelfie
        case .places: return item.hasLocation
        case .livePhotos: return item.kind == .livePhoto
        case .recent:
            guard let date = item.captureDate,
                  let boundary = calendar.date(byAdding: .day, value: -30, to: now) else { return false }
            return date >= boundary && date <= now
        case .older:
            guard let date = item.captureDate,
                  let boundary = calendar.date(byAdding: .year, value: -1, to: now) else { return false }
            return date < boundary
        }
    }

    func filter(_ items: [MediaItem], now: Date = .now, calendar: Calendar = .current) -> [MediaItem] {
        items.filter { matches($0, now: now, calendar: calendar) }
    }
}

struct PlaceGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [MediaItem]

    var ids: [String] { items.map(\.id) }

    static func groups(from items: [MediaItem]) -> [PlaceGroup] {
        var buckets: [String: [MediaItem]] = [:]
        for item in items where item.hasLocation {
            guard let latitude = item.latitude, let longitude = item.longitude else { continue }
            let latitudeCell = (latitude * 10).rounded(.down) / 10
            let longitudeCell = (longitude * 10).rounded(.down) / 10
            let key = String(format: "%.1f, %.1f", locale: Locale(identifier: "en_US_POSIX"), latitudeCell, longitudeCell)
            buckets[key, default: []].append(item)
        }
        return buckets.map { key, value in
            PlaceGroup(id: key, title: "Near \(key)°", items: value)
        }.sorted { $0.id < $1.id }
    }
}
