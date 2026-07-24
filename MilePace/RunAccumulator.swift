import Foundation

/// Pure pace and split math, kept separate from Core Location so it can be unit tested.
struct RunAccumulator {
    private struct DistancePoint {
        let elapsed: TimeInterval
        let distanceMeters: Double
    }

    private(set) var totalDistanceMeters: Double = 0
    private(set) var mileSplits: [MileSplit] = []
    private(set) var elevationGainMeters: Double = 0
    private(set) var elevationLossMeters: Double = 0
    private var lastSplitElapsed: TimeInterval = 0
    private var rollingPoints: [DistancePoint] = [DistancePoint(elapsed: 0, distanceMeters: 0)]
    private var lastCountedAltitude: Double?

    /// GPS altitude is far noisier than GPS position. A stationary phone can
    /// wander several metres vertically, so counting every change would invent
    /// hundreds of feet of climb on a flat road. Only movement past this
    /// threshold counts, measured from the last altitude actually counted
    /// rather than from the previous sample, so a steady climb still
    /// accumulates in full.
    static let elevationThresholdMeters: Double = 3

    mutating func recordAltitude(_ altitude: Double, verticalAccuracy: Double) {
        // A negative vertical accuracy means the reading is invalid. A large
        // one means it is not worth trusting for a 3 m threshold.
        guard verticalAccuracy > 0, verticalAccuracy <= 10, altitude.isFinite else { return }

        guard let last = lastCountedAltitude else {
            lastCountedAltitude = altitude
            return
        }

        let change = altitude - last
        guard abs(change) >= Self.elevationThresholdMeters else { return }

        if change > 0 {
            elevationGainMeters += change
        } else {
            elevationLossMeters -= change
        }
        lastCountedAltitude = altitude
    }

    var currentMileNumber: Int {
        mileSplits.count + 1
    }

    var currentMileDistanceMeters: Double {
        totalDistanceMeters - (Double(mileSplits.count) * metersPerMile)
    }

    var currentMileProgress: Double {
        min(max(currentMileDistanceMeters / metersPerMile, 0), 1)
    }

    mutating func recordSegment(
        distanceMeters: Double,
        fromElapsed: TimeInterval,
        toElapsed: TimeInterval
    ) {
        guard distanceMeters >= 0, distanceMeters.isFinite,
              toElapsed >= fromElapsed, fromElapsed >= 0 else { return }

        let oldDistance = totalDistanceMeters
        let newDistance = oldDistance + distanceMeters
        let segmentDuration = toElapsed - fromElapsed

        while Double(mileSplits.count + 1) * metersPerMile <= newDistance,
              distanceMeters > 0 {
            let boundary = Double(mileSplits.count + 1) * metersPerMile
            let fraction = (boundary - oldDistance) / distanceMeters
            let crossingElapsed = fromElapsed + (segmentDuration * fraction)
            let splitDuration = crossingElapsed - lastSplitElapsed
            mileSplits.append(MileSplit(mile: mileSplits.count + 1, duration: splitDuration))
            lastSplitElapsed = crossingElapsed
        }

        totalDistanceMeters = newDistance
        rollingPoints.append(DistancePoint(elapsed: toElapsed, distanceMeters: newDistance))
        trimRollingPoints(now: toElapsed)
    }

    mutating func resetRollingWindow(at elapsed: TimeInterval) {
        rollingPoints = [DistancePoint(elapsed: elapsed, distanceMeters: totalDistanceMeters)]
    }

    func currentMilePace(at elapsed: TimeInterval) -> TimeInterval? {
        let distance = currentMileDistanceMeters
        let duration = elapsed - lastSplitElapsed
        guard distance >= 30, duration > 0 else { return nil }
        return duration / distance * metersPerMile
    }

    func averagePace(at elapsed: TimeInterval) -> TimeInterval? {
        guard totalDistanceMeters >= 30, elapsed > 0 else { return nil }
        return elapsed / totalDistanceMeters * metersPerMile
    }

    func rollingPace() -> TimeInterval? {
        guard let first = rollingPoints.first, let last = rollingPoints.last else { return nil }
        let duration = last.elapsed - first.elapsed
        let distance = last.distanceMeters - first.distanceMeters
        guard duration >= 5, distance >= 15 else { return nil }
        return duration / distance * metersPerMile
    }

    private mutating func trimRollingPoints(now: TimeInterval) {
        let cutoff = now - 30
        while rollingPoints.count > 2, rollingPoints[1].elapsed < cutoff {
            rollingPoints.removeFirst()
        }
    }
}
