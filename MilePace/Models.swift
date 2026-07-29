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

    /// Evenly thins a plain point list, keeping the first and last. Used to send
    /// a route to the Live Activity small enough to draw and to fit the payload.
    static func thinPoints(_ points: [RoutePoint], limit: Int) -> [RoutePoint] {
        guard limit >= 2, points.count > limit else { return points }
        let stride = Int((Double(points.count) / Double(limit)).rounded(.up))
        guard stride > 1 else { return points }

        var kept: [RoutePoint] = []
        for index in Swift.stride(from: 0, to: points.count, by: stride) {
            kept.append(points[index])
        }
        if kept.last != points.last, let last = points.last { kept.append(last) }
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

/// What kind of activity a record holds. It decides which units and which pace
/// maths the app applies. A record saved before this existed reads as `.run`,
/// which is true: the app could only record a run.
enum ActivityKind: String, Codable, CaseIterable, Identifiable, Equatable {
    case run
    case hike
    case bike
    case swim

    var id: String { rawValue }

    /// Whether the app measures this activity in minutes per mile. A bike is
    /// measured in miles per hour, and a swim in minutes per 100 yards, because
    /// a pace per mile is not how a cyclist or a swimmer states a result.
    var usesPacePerMile: Bool {
        switch self {
        case .run, .hike: return true
        case .bike, .swim: return false
        }
    }
}

/// Where a record came from. A run that the phone recorded holds a full GPS
/// trace and mile splits. An imported workout holds only what Apple Health
/// reports, which may include no route at all.
enum RunSource: String, Codable, Equatable {
    case phoneGPS
    case healthKit
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
    /// Run, hike, bike, or swim. Every record saved before the import feature
    /// existed is a run.
    let activityKind: ActivityKind
    /// Whether the phone recorded this activity, or the app imported it.
    let source: RunSource
    /// The `HKWorkout` identifier, for a record that came from Apple Health.
    /// It stops the app from importing one workout two times. It is `nil` for a
    /// run that the phone recorded.
    let externalIdentifier: String?
    /// Heart rate in beats per minute. Apple Health supplies these. The phone
    /// alone cannot measure them, so a phone-recorded run leaves them `nil`.
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    /// Active energy in kilocalories, as Apple Health reports it.
    let activeEnergyKcal: Double?

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
        isArchived: Bool = false,
        activityKind: ActivityKind = .run,
        source: RunSource = .phoneGPS,
        externalIdentifier: String? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        activeEnergyKcal: Double? = nil
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
        self.activityKind = activityKind
        self.source = source
        self.externalIdentifier = externalIdentifier
        self.averageHeartRate = RunRecord.usableMeasurement(averageHeartRate)
        self.maxHeartRate = RunRecord.usableMeasurement(maxHeartRate)
        self.activeEnergyKcal = RunRecord.usableMeasurement(activeEnergyKcal)
    }

    /// Rejects a measurement that no screen can show. Apple Health is a wider
    /// set of writers than the app's own tracker, so a value can arrive as a
    /// NaN, an infinity, or a negative number. Such a value must not reach the
    /// UI, and it must not reach `runs.json` either.
    private static func usableMeasurement(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
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

        // Decoded from the raw string, not from the enum, so a kind that a
        // later version writes cannot fail the decode. One unreadable record
        // fails the whole `runs.json` array, and the history has no backup.
        let kindName = try container.decodeIfPresent(String.self, forKey: .activityKind)
        activityKind = kindName.flatMap(ActivityKind.init(rawValue:)) ?? .run
        let sourceName = try container.decodeIfPresent(String.self, forKey: .source)
        source = sourceName.flatMap(RunSource.init(rawValue:)) ?? .phoneGPS

        externalIdentifier = try container.decodeIfPresent(String.self, forKey: .externalIdentifier)
        averageHeartRate = RunRecord.usableMeasurement(
            try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        )
        maxHeartRate = RunRecord.usableMeasurement(
            try container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        )
        activeEnergyKcal = RunRecord.usableMeasurement(
            try container.decodeIfPresent(Double.self, forKey: .activeEnergyKcal)
        )
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

    /// The run's path as route points, for comparing runs to routes.
    var routePoints: [RoutePoint] {
        trackPoints.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

/// One point on a planned route. Plain `Double`s, so this file stays free of
/// Core Location and MapKit and the pace checks keep compiling it.
struct RoutePoint: Codable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double
}

/// A route the runner intends to run, drawn on a map or taken from a past run.
///
/// The line is the full drawn or recorded path, dense enough to draw and to
/// measure distance from. Waypoints are only the corners the runner placed, so
/// a custom route can be reopened and edited without re-deriving them.
struct PlannedRoute: Codable, Equatable, Identifiable {
    enum Origin: String, Codable {
        case drawn      // built on the map
        case pastRun    // taken from a recorded run
    }

    let id: UUID
    let createdAt: Date
    var name: String
    let origin: Origin
    /// The corners the runner placed. Empty for a route taken from a past run.
    let waypoints: [RoutePoint]
    /// The full path to draw and follow.
    let line: [RoutePoint]
    /// Hidden from the list but kept, the same as an archived run.
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String = "",
        origin: Origin,
        waypoints: [RoutePoint] = [],
        line: [RoutePoint],
        isArchived: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.origin = origin
        self.waypoints = waypoints
        self.line = line
        self.isArchived = isArchived
    }

    /// Decodes `isArchived` leniently, so routes saved before archiving keep
    /// loading instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        name = try container.decode(String.self, forKey: .name)
        origin = try container.decode(Origin.self, forKey: .origin)
        waypoints = try container.decode([RoutePoint].self, forKey: .waypoints)
        line = try container.decode([RoutePoint].self, forKey: .line)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    var distanceMeters: Double {
        RouteGeometry.length(of: line)
    }

    var distanceMiles: Double {
        distanceMeters / metersPerMile
    }

    var displayName: String {
        name.isEmpty ? String(format: "%.2f mi route", distanceMiles) : name
    }

    var bounds: RouteBounds? {
        RouteGeometry.bounds(of: line)
    }

    /// Builds a route from a recorded run, so a runner can run it again. The
    /// run's own path becomes the line to follow; it has no placed corners.
    init(fromRun record: RunRecord) {
        self.init(
            name: "",
            origin: .pastRun,
            waypoints: [],
            line: record.trackPoints.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) }
        )
    }
}

/// Pure geometry over a route's points. No Core Location, so it is testable and
/// keeps `Models.swift` framework-free.
enum RouteGeometry {
    static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance between two points, in metres. The haversine
    /// formula, so it stays accurate over the short legs a route is made of.
    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    static func length(of line: [RoutePoint]) -> Double {
        guard line.count >= 2 else { return 0 }
        return zip(line, line.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func bounds(of line: [RoutePoint]) -> RouteBounds? {
        let lats = line.map(\.latitude)
        let lons = line.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return RouteBounds(minLatitude: minLat, maxLatitude: maxLat,
                           minLongitude: minLon, maxLongitude: maxLon)
    }

    /// The shortest distance from a point to the route line, in metres. This is
    /// what off-route detection measures: how far the runner has strayed from
    /// the nearest part of the planned path.
    static func distanceToLine(from point: RoutePoint, line: [RoutePoint]) -> Double? {
        guard let first = line.first else { return nil }
        guard line.count >= 2 else { return distance(point, first) }

        var nearest = Double.greatestFiniteMagnitude
        for (a, b) in zip(line, line.dropFirst()) {
            nearest = min(nearest, distanceToSegment(point, a, b))
        }
        return nearest
    }

    /// Distance from a point to a segment, worked in a local flat projection.
    /// Over the tens of metres a route leg spans, treating latitude and
    /// longitude as a plane is accurate to well under the threshold that
    /// off-route detection cares about, and avoids a costly exact solution.
    private static func distanceToSegment(_ p: RoutePoint, _ a: RoutePoint, _ b: RoutePoint) -> Double {
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(a.latitude * .pi / 180)

        let px = p.longitude * lonScale, py = p.latitude * latScale
        let ax = a.longitude * lonScale, ay = a.latitude * latScale
        let bx = b.longitude * lonScale, by = b.latitude * latScale

        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(px - ax, py - ay) }

        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
        return hypot(px - (ax + t * dx), py - (ay + t * dy))
    }
}

/// Decides whether two paths are the same route. Pure and testable.
///
/// Two runs are the same route when they are close to the same length and each
/// stays near the other's line the whole way. Checking both directions matters:
/// a short there-and-back sits on top of a long loop's line, but the loop does
/// not sit on the short line, so a one-directional check would call them equal.
enum RouteSimilarity {
    /// How far a point may sit from the other line and still count as on it.
    /// Wide enough for GPS wander and for running the far side of a street.
    static let toleranceMeters: Double = 50
    /// Lengths must be within this fraction of each other.
    static let lengthTolerance: Double = 0.2

    static func isSameRoute(
        _ a: [RoutePoint],
        _ b: [RoutePoint],
        toleranceMeters: Double = toleranceMeters
    ) -> Bool {
        guard a.count >= 2, b.count >= 2 else { return false }
        let lengthA = RouteGeometry.length(of: a)
        let lengthB = RouteGeometry.length(of: b)
        guard lengthA > 0, lengthB > 0 else { return false }
        guard min(lengthA, lengthB) / max(lengthA, lengthB) >= 1 - lengthTolerance else { return false }

        return covers(a, by: b, tolerance: toleranceMeters)
            && covers(b, by: a, tolerance: toleranceMeters)
    }

    /// Whether every sampled point of `path` sits within `tolerance` of `other`.
    private static func covers(_ path: [RoutePoint], by other: [RoutePoint], tolerance: Double) -> Bool {
        let maxSamples = 40
        let step = max(1, path.count / maxSamples)
        var index = 0
        while index < path.count {
            guard let distance = RouteGeometry.distanceToLine(from: path[index], line: other),
                  distance <= tolerance else { return false }
            index += step
        }
        return true
    }
}

/// Decides whether to suggest saving a finished run as a route.
///
/// The rule is deliberately quiet: suggest only a run the runner has done
/// before but has not already saved. A route run twice is demonstrably
/// repeatable, and suppressing one-offs means the runner is not asked to
/// decline a suggestion after every ordinary run.
enum RouteSuggestion {
    static func shouldSuggest(
        for finished: RunRecord,
        existingRoutes: [PlannedRoute],
        history: [RunRecord]
    ) -> Bool {
        let path = finished.routePoints
        guard path.count >= 2 else { return false }

        // Already saved as a route: nothing to suggest.
        if existingRoutes.contains(where: { RouteSimilarity.isSameRoute(path, $0.line) }) {
            return false
        }

        // Suggest only if a different past run took the same route.
        return history.contains { other in
            other.id != finished.id
                && other.routePoints.count >= 2
                && RouteSimilarity.isSameRoute(path, other.routePoints)
        }
    }
}

/// Decides when a runner has strayed off a followed route, and when they are
/// back on it. Pure, so it is testable without Core Location.
///
/// Two thresholds, not one. A runner crosses the wider distance to be called
/// off-route, and must come back inside the tighter one to be called on-route
/// again. That gap is hysteresis: it stops the alert flapping on and off while
/// the runner hovers near the edge, which GPS noise alone would cause. The
/// off-route call also waits out a dwell, so a single stray fix or a wide bend
/// in the road does not fire it.
struct OffRouteMonitor {
    /// Past this distance from the route line, the runner is straying.
    var offThresholdMeters: Double = 40
    /// The runner is back on route once inside this tighter distance.
    var onThresholdMeters: Double = 25
    /// How long the runner must be beyond the off threshold before the alert
    /// fires. Long enough to ride out one bad fix or a brief detour.
    var dwellSeconds: TimeInterval = 8

    private(set) var isOffRoute = false
    /// When the current stray began, in run-elapsed seconds. Nil when on route.
    private var strayingSince: TimeInterval?

    enum Event: Equatable {
        case wentOffRoute
        case returnedToRoute
    }

    /// Feeds one position in. `distanceFromLine` is the shortest distance to the
    /// route; `accuracy` is the fix's horizontal accuracy, which widens the off
    /// threshold so a noisy fix does not fire a false alert. Returns an event
    /// only when the state actually changes.
    mutating func update(
        distanceFromLine: Double,
        accuracy: Double,
        elapsed: TimeInterval
    ) -> Event? {
        // A poor fix should not be trusted to say the runner strayed, so give
        // the off threshold the benefit of the fix's own uncertainty.
        let offLimit = offThresholdMeters + max(0, accuracy)

        if isOffRoute {
            if distanceFromLine <= onThresholdMeters {
                isOffRoute = false
                strayingSince = nil
                return .returnedToRoute
            }
            return nil
        }

        if distanceFromLine > offLimit {
            let since = strayingSince ?? elapsed
            strayingSince = since
            if elapsed - since >= dwellSeconds {
                isOffRoute = true
                return .wentOffRoute
            }
        } else {
            // Back inside the line before the dwell elapsed; cancel the stray.
            strayingSince = nil
        }
        return nil
    }

    /// Clears the state, for the start of a run or a resume.
    mutating func reset() {
        isOffRoute = false
        strayingSince = nil
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
