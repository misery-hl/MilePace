import XCTest
#if SWIFT_PACKAGE
@testable import MilePaceCore
#else
@testable import MilePace
#endif

final class RunAccumulatorTests: XCTestCase {
    func testOneMileProducesAnExactSplit() {
        var accumulator = RunAccumulator()
        accumulator.recordSegment(distanceMeters: metersPerMile, fromElapsed: 0, toElapsed: 480)

        XCTAssertEqual(accumulator.mileSplits, [MileSplit(mile: 1, duration: 480)])
        XCTAssertEqual(accumulator.totalDistanceMeters, metersPerMile, accuracy: 0.001)
        XCTAssertEqual(accumulator.currentMileNumber, 2)
    }

    func testMileBoundaryIsInterpolatedInsideGPSegment() {
        var accumulator = RunAccumulator()
        accumulator.recordSegment(distanceMeters: 1_500, fromElapsed: 0, toElapsed: 450)
        accumulator.recordSegment(distanceMeters: 200, fromElapsed: 450, toElapsed: 510)

        let expectedCrossing = 450 + ((metersPerMile - 1_500) / 200 * 60)
        XCTAssertEqual(accumulator.mileSplits.count, 1)
        XCTAssertEqual(accumulator.mileSplits[0].duration, expectedCrossing, accuracy: 0.001)
    }

    func testCurrentMilePaceUsesOnlyCurrentMile() {
        var accumulator = RunAccumulator()
        accumulator.recordSegment(distanceMeters: metersPerMile, fromElapsed: 0, toElapsed: 600)
        accumulator.recordSegment(distanceMeters: metersPerMile / 2, fromElapsed: 600, toElapsed: 840)

        XCTAssertEqual(accumulator.currentMilePace(at: 840) ?? 0, 480, accuracy: 0.001)
    }

    func testRollingPaceUsesRecentWindow() {
        var accumulator = RunAccumulator()
        accumulator.recordSegment(distanceMeters: 80, fromElapsed: 0, toElapsed: 10)
        accumulator.recordSegment(distanceMeters: 80, fromElapsed: 10, toElapsed: 20)

        XCTAssertEqual(accumulator.rollingPace() ?? 0, 20 / 160 * metersPerMile, accuracy: 0.001)
    }

    func testInvalidSegmentIsIgnored() {
        var accumulator = RunAccumulator()
        accumulator.recordSegment(distanceMeters: -1, fromElapsed: 0, toElapsed: 1)
        accumulator.recordSegment(distanceMeters: 10, fromElapsed: 2, toElapsed: 1)

        XCTAssertEqual(accumulator.totalDistanceMeters, 0)
        XCTAssertTrue(accumulator.mileSplits.isEmpty)
    }
}
