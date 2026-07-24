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

/// Reduces a recorded route to a size worth storing and drawing.
///
/// Core Location is asked for a fix every 2 m, which is the right resolution for
/// measuring distance but far more than a map needs. Kept in full, a six month
/// history reaches tens of megabytes, and the whole file is rewritten on every
/// save. Thinning at save time fixes the file size, the save cost, and the
/// number of points handed to the map.
///
/// The first and last point of every segment survive, so the route still starts
/// and ends where the runner did, and a pause still reads as a gap.
enum RouteThinning {
    /// Enough to draw a smooth route at any zoom a phone screen offers.
    static let maximumPoints = 500

    static func thin(_ points: [TrackPoint], limit: Int = maximumPoints) -> [TrackPoint] {
        guard limit > 0 else { return [] }
        guard points.count > limit else { return points }

        let stride = Int((Double(points.count) / Double(limit)).rounded(.up))
        guard stride > 1 else { return points }

        var kept: [TrackPoint] = []
        kept.reserveCapacity(limit + 8)

        for (index, point) in points.enumerated() {
            let startsSegment = index == 0 || points[index - 1].segment != point.segment
            let endsSegment = index == points.count - 1 || points[index + 1].segment != point.segment

            if startsSegment || endsSegment || index % stride == 0 {
                kept.append(point)
            }
        }

        return kept
    }
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
    /// Climb and descent in metres. Zero for runs saved before elevation was
    /// recorded, which is indistinguishable from a genuinely flat run.
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    /// Hidden from the run lists, but kept. A run worth setting aside is not
    /// the same as a run worth destroying, and the history has no backup.
    var isArchived: Bool

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        activeDuration: TimeInterval,
        mileSplits: [MileSplit],
        trackPoints: [TrackPoint] = [],
        elevationGainMeters: Double = 0,
        elevationLossMeters: Double = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.activeDuration = activeDuration
        self.mileSplits = mileSplits
        self.trackPoints = trackPoints
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.isArchived = isArchived
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
        elevationGainMeters = try container.decodeIfPresent(Double.self, forKey: .elevationGainMeters) ?? 0
        elevationLossMeters = try container.decodeIfPresent(Double.self, forKey: .elevationLossMeters) ?? 0
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
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

    var elevationGainFeet: Double {
        elevationGainMeters * 3.280839895
    }

    /// Whether the run climbed enough to be worth reporting. A flat road run
    /// accumulates a little noise even after filtering, and "4 ft" is clutter.
    var hasMeaningfulElevation: Bool {
        elevationGainFeet >= 20
    }
}

/// What kind of effort a goal describes.
///
/// A run and a sprint are stated in different units, and only one of them has a
/// meaningful pace per mile. Splitting them keeps each editor short and stops
/// the app offering a pace per mile for a 40 yard dash.
///
/// This is derived from the unit rather than stored, so no saved goal needs to
/// change and there is no way for the two to disagree.
enum GoalKind: String, CaseIterable, Identifiable, Equatable {
    case run
    case sprint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: return "Run"
        case .sprint: return "Sprint"
        }
    }

    var units: [DistanceUnit] {
        switch self {
        case .run: return [.miles, .kilometers]
        case .sprint: return [.meters, .yards]
        }
    }

    /// A pace per mile describes a run. Over a sprint it is a number nobody
    /// races to, so a sprint goal is stated as a total time only.
    var allowsPaceEntry: Bool {
        self == .run
    }
}

/// The unit a goal distance is stated in.
///
/// A goal is always stored in meters. This only decides the steps the picker
/// offers and how the distance reads back, so a runner who thinks in
/// kilometres is not shown 3.11 mi, and a runner who thinks in track laps is
/// not shown 0.2 mi.
///
/// Pace stays in minutes per mile everywhere, which is what the app is for.
enum DistanceUnit: String, Codable, CaseIterable, Identifiable, Equatable {
    case miles
    case kilometers
    case meters
    case yards

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        case .meters: return "m"
        case .yards: return "yd"
        }
    }

    var metersPerUnit: Double {
        switch self {
        case .miles: return metersPerMile
        case .kilometers: return 1_000
        case .meters: return 1
        case .yards: return 0.9144
        }
    }

    var kind: GoalKind {
        switch self {
        case .miles, .kilometers: return .run
        case .meters, .yards: return .sprint
        }
    }

    /// One step on the picker, in meters.
    ///
    /// Road units step by a tenth, which is fine enough for any run target.
    /// Sprint units step finely, because the distances are short and a few
    /// meters matter: 5 m lands on 55, 60, 100, 200, 400; 10 yd lands on the
    /// 40 yard dash and on 100, 220, 440, 880.
    var stepMeters: Double {
        switch self {
        case .miles: return metersPerMile / 10
        case .kilometers: return 100
        case .meters: return 5
        case .yards: return 0.9144 * 10
        }
    }

    /// The smallest distance the picker offers, in meters.
    ///
    /// Yards start at 40 rather than at one step, because the 40 yard dash is
    /// the reason most people reach for yards at all.
    var firstOptionMeters: Double {
        switch self {
        case .yards: return 0.9144 * 40
        default: return stepMeters
        }
    }

    /// How many steps the picker offers.
    ///
    /// Run units reach well past a marathon. Sprint units stop at roughly a
    /// mile — 1,600 m and 1,760 yd — because that is about as far as anyone
    /// sprints, and a short wheel is far easier to use than a long one.
    var stepCount: Int {
        switch self {
        case .miles: return 500        // 50.0 mi
        case .kilometers: return 800   // 80.0 km
        case .meters: return 320       // 5 m to 1,600 m
        case .yards: return 173        // 40 yd to 1,760 yd
        }
    }

    var usesDecimal: Bool {
        self == .miles || self == .kilometers
    }

    /// The distance written in this unit, without a trailing ".0".
    func text(forMeters meters: Double) -> String {
        let value = meters / metersPerUnit
        if usesDecimal {
            if abs(value.rounded() - value) < 0.05 {
                return String(format: "%.0f %@", value.rounded(), shortName)
            }
            return String(format: "%.1f %@", value, shortName)
        }
        return String(format: "%.0f %@", value.rounded(), shortName)
    }

    /// Every distance the picker offers, in meters.
    var options: [Double] {
        (0..<stepCount).map { firstOptionMeters + Double($0) * stepMeters }
    }

    /// Where the picker opens when the incoming distance does not belong to
    /// this unit at all. These are the distances people most often want.
    var defaultOptionMeters: Double {
        switch self {
        case .miles: return 2 * metersPerMile
        case .kilometers: return 5_000
        case .meters: return 100
        case .yards: return firstOptionMeters   // the 40 yard dash
        }
    }

    /// The offered distance closest to a given one, so switching unit keeps the
    /// goal the runner already had instead of resetting it.
    func nearestOption(toMeters meters: Double) -> Double {
        options.min { abs($0 - meters) < abs($1 - meters) } ?? stepMeters
    }

    /// Where the picker should land when a distance arrives from another unit.
    ///
    /// Only snaps to the nearest option when the distance is actually within
    /// this unit's range. Outside it, "nearest" means the first or last option,
    /// which is why switching a 5 km goal to sprint used to open at 1,600 m —
    /// the far end of the wheel, and a long scroll from the 100 m and 400 m a
    /// sprinter actually wants.
    func sensibleOption(forMeters meters: Double) -> Double {
        guard let smallest = options.first, let largest = options.last else {
            return defaultOptionMeters
        }
        guard meters >= smallest, meters <= largest else { return defaultOptionMeters }
        return nearestOption(toMeters: meters)
    }
}

/// A target time for a target distance, plus the runs the user applied to it.
///
/// The goal owns the list of run identifiers rather than each run naming a goal.
/// A run can therefore be added to a goal long after it was recorded, and a run
/// that is never applied stays untouched.
struct RunGoal: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    /// Editable, so a runner can correct a goal without losing the runs on it.
    var distanceMeters: Double
    var targetDuration: TimeInterval
    var runIDs: [UUID]
    var isArchived: Bool
    /// The unit this goal is stated in. Display only; the distance is meters.
    var distanceUnit: DistanceUnit

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String = "",
        distanceMeters: Double,
        targetDuration: TimeInterval,
        runIDs: [UUID] = [],
        isArchived: Bool = false,
        distanceUnit: DistanceUnit = .miles
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.distanceMeters = distanceMeters
        self.targetDuration = targetDuration
        self.runIDs = runIDs
        self.isArchived = isArchived
        self.distanceUnit = distanceUnit
    }

    /// Decodes `distanceUnit` leniently, so goals saved before units existed
    /// keep loading instead of failing the whole goals file. They were all in
    /// miles, which is the default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        targetDuration = try container.decode(TimeInterval.self, forKey: .targetDuration)
        runIDs = try container.decodeIfPresent([UUID].self, forKey: .runIDs) ?? []
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        distanceUnit = try container.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit) ?? .miles
        // Goals saved before naming existed have no name, which is the same as
        // an unnamed goal, so they need no migration.
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    /// What the goal is for, in the runner's own words. Empty means unnamed.
    ///
    /// Two goals at the same distance are otherwise indistinguishable, and a
    /// name says why a goal exists in a way a distance never can.
    var name: String

    /// The distance and target, always. This is what the goal *is*, and it stays
    /// derived so editing can never leave a stale description behind.
    var title: String {
        "\(distanceText) in \(targetDuration.clockText)"
    }

    /// What to call the goal in a sentence: the name when there is one, and the
    /// distance and target when there is not.
    var displayName: String {
        name.isEmpty ? title : name
    }

    var distanceMiles: Double {
        distanceMeters / metersPerMile
    }

    var kind: GoalKind {
        distanceUnit.kind
    }

    /// The pace the runner must hold to reach the target.
    ///
    /// Only meaningful for a run. A sprint target of 5 seconds over 40 yards is
    /// a 3:40 mile pace, which is true and useless.
    var targetPace: TimeInterval {
        guard distanceMeters > 0 else { return 0 }
        return targetDuration / distanceMeters * metersPerMile
    }

    var showsPace: Bool {
        kind.allowsPaceEntry
    }

    /// Average speed the target demands, in meters per second.
    var targetSpeed: Double {
        guard targetDuration > 0 else { return .infinity }
        return distanceMeters / targetDuration
    }

    /// Whether a human could hold this target.
    ///
    /// Checked as a speed rather than a pace, so one rule covers a 40 yard dash
    /// and a marathon. The upper bound sits just above the fastest sprint ever
    /// recorded, about 12.4 m/s; the lower bound sits below a slow walk. This
    /// only rejects the absurd, such as a 5 km in one second, which used to
    /// save happily and then report a target pace of "0:00 /mi".
    var isPlausible: Bool {
        targetDuration > 0 && distanceMeters > 0 && targetSpeed <= 13 && targetSpeed >= 0.3
    }

    var implausibleReason: String? {
        guard !isPlausible else { return nil }
        if targetDuration <= 0 || distanceMeters <= 0 {
            return "Choose a distance and a time."
        }
        return targetSpeed > 13
            ? "That is faster than anyone has ever run. Give yourself more time."
            : "That is slower than a walk. Try less time."
    }

    var distanceText: String {
        distanceUnit.text(forMeters: distanceMeters)
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

    /// A pace over an hour per mile is slow but real. A runner who stops at a
    /// light without pausing will pass it within a minute, and the current-mile
    /// pace is the largest number on the running screen. Blanking it there
    /// looks identical to having no data at all, so format the hours instead.
    var paceText: String {
        guard isFinite, self > 0 else { return "--:--" }
        let seconds = Int(rounded())
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// The size of a difference, without a sign. The caller supplies the wording
    /// that says which direction it went, because "1:20 faster" reads better
    /// than "-1:20" on a summary screen.
    var differenceText: String {
        guard isFinite else { return "--:--" }
        let seconds = Int(abs(self).rounded())
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
