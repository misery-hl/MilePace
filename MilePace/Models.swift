import Foundation

let metersPerMile = 1_609.344

struct MileSplit: Codable, Equatable, Identifiable {
    let mile: Int
    let duration: TimeInterval

    var id: Int { mile }
}

/// One recorded GPS sample. Coordinates stay plain `Double` values so this file
/// remains free of Core Location and MapKit and can be compiled by the
/// framework-independent pace checks in `Tools/`.
struct TrackPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let altitude: Double?
    let horizontalAccuracy: Double
    /// Increments on each resume so the drawn route does not connect across a pause.
    let segment: Int
}

/// Latitude/longitude extent of a recorded route.
struct RouteBounds: Equatable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    var centerLatitude: Double { (minLatitude + maxLatitude) / 2 }
    var centerLongitude: Double { (minLongitude + maxLongitude) / 2 }
    var latitudeSpan: Double { maxLatitude - minLatitude }
    var longitudeSpan: Double { maxLongitude - minLongitude }
}

struct RunRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let activeDuration: TimeInterval
    let mileSplits: [MileSplit]
    /// Recorded route. Empty for runs saved before route recording existed.
    let trackPoints: [TrackPoint]

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        activeDuration: TimeInterval,
        mileSplits: [MileSplit],
        trackPoints: [TrackPoint] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.activeDuration = activeDuration
        self.mileSplits = mileSplits
        self.trackPoints = trackPoints
    }

    /// Decodes `trackPoints` leniently so run histories written before route
    /// recording existed keep loading instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        activeDuration = try container.decode(TimeInterval.self, forKey: .activeDuration)
        mileSplits = try container.decode([MileSplit].self, forKey: .mileSplits)
        trackPoints = try container.decodeIfPresent([TrackPoint].self, forKey: .trackPoints) ?? []
    }

    var distanceMiles: Double {
        distanceMeters / metersPerMile
    }

    var hasRoute: Bool {
        routeSegments.isEmpty == false
    }

    /// The route split into continuous stretches, one per active segment, so a
    /// pause does not draw a straight line between where the runner stopped and
    /// where they resumed.
    var routeSegments: [[TrackPoint]] {
        var segments: [[TrackPoint]] = []
        var current: [TrackPoint] = []

        for point in trackPoints {
            if let last = current.last, last.segment != point.segment {
                if current.count >= 2 { segments.append(current) }
                current = []
            }
            current.append(point)
        }
        if current.count >= 2 { segments.append(current) }

        return segments
    }

    var routeBounds: RouteBounds? {
        let latitudes = trackPoints.map(\.latitude)
        let longitudes = trackPoints.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else { return nil }

        return RouteBounds(
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude
        )
    }

    var averagePace: TimeInterval? {
        guard distanceMeters >= 30 else { return nil }
        return activeDuration / distanceMeters * metersPerMile
    }

    var fastestMile: MileSplit? {
        mileSplits.min(by: { $0.duration < $1.duration })
    }
}

enum RunPhase: Equatable {
    case idle
    case running
    case paused
    case finished
}

extension TimeInterval {
    var clockText: String {
        guard isFinite, self >= 0 else { return "--:--" }
        let totalSeconds = Int(self.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var paceText: String {
        guard isFinite, self > 0, self < 3_600 else { return "--:--" }
        let roundedSeconds = Int(rounded())
        return String(format: "%d:%02d", roundedSeconds / 60, roundedSeconds % 60)
    }
}
