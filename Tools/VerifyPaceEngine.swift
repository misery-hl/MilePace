import Foundation

@main
enum VerifyPaceEngine {
    static func main() {
        var completedChecks = 0

        var exactMile = RunAccumulator()
        exactMile.recordSegment(distanceMeters: metersPerMile, fromElapsed: 0, toElapsed: 480)
        check(exactMile.mileSplits == [MileSplit(mile: 1, duration: 480)], "exact mile split")
        completedChecks += 1

        var crossing = RunAccumulator()
        crossing.recordSegment(distanceMeters: 1_500, fromElapsed: 0, toElapsed: 450)
        crossing.recordSegment(distanceMeters: 200, fromElapsed: 450, toElapsed: 510)
        let expectedCrossing = 450 + ((metersPerMile - 1_500) / 200 * 60)
        check(abs(crossing.mileSplits[0].duration - expectedCrossing) < 0.001, "mile-boundary interpolation")
        completedChecks += 1

        var currentMile = RunAccumulator()
        currentMile.recordSegment(distanceMeters: metersPerMile, fromElapsed: 0, toElapsed: 600)
        currentMile.recordSegment(distanceMeters: metersPerMile / 2, fromElapsed: 600, toElapsed: 840)
        check(abs((currentMile.currentMilePace(at: 840) ?? 0) - 480) < 0.001, "current-mile pace")
        completedChecks += 1

        var rolling = RunAccumulator()
        rolling.recordSegment(distanceMeters: 80, fromElapsed: 0, toElapsed: 10)
        rolling.recordSegment(distanceMeters: 80, fromElapsed: 10, toElapsed: 20)
        let expectedRollingPace = 20 / 160 * metersPerMile
        check(abs((rolling.rollingPace() ?? 0) - expectedRollingPace) < 0.001, "rolling pace")
        completedChecks += 1

        var invalid = RunAccumulator()
        invalid.recordSegment(distanceMeters: -1, fromElapsed: 0, toElapsed: 1)
        invalid.recordSegment(distanceMeters: 10, fromElapsed: 2, toElapsed: 1)
        check(invalid.totalDistanceMeters == 0, "invalid-segment rejection")
        completedChecks += 1

        print("Passed \(completedChecks) pace-engine checks")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("Failed: \(name)\n", stderr)
            exit(1)
        }
    }
}
