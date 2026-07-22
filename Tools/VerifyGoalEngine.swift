import Foundation

// Framework-independent checks for the race-prediction and goal-comparison
// engine. Build and run with:
//
//   swiftc MilePace/Models.swift MilePace/PacePrediction.swift \
//     Tools/VerifyGoalEngine.swift -o /tmp/milepace-goal-check
//   /tmp/milepace-goal-check

@main
enum VerifyGoalEngine {
    static var completedChecks = 0

    static func main() {
        let twoMiles = 2 * metersPerMile
        let goal = RunGoal(distanceMeters: twoMiles, targetDuration: 720)

        // Riegel: doubling the distance costs more than doubling the time.
        let fromMile = PacePrediction.equivalentDuration(
            fromDistanceMeters: metersPerMile,
            duration: 330,
            toDistanceMeters: twoMiles
        )
        check(fromMile != nil, "Riegel predicts a two-mile time from a mile")
        check((fromMile ?? 0) > 660, "Riegel costs more than linear scaling")
        check(nearly(fromMile ?? 0, 330 * pow(2, 1.06)), "Riegel matches 330 * 2^1.06")

        let identity = PacePrediction.equivalentDuration(
            fromDistanceMeters: twoMiles, duration: 800, toDistanceMeters: twoMiles
        )
        check(nearly(identity ?? 0, 800, tolerance: 0.001), "predicting the same distance is the identity")

        check(PacePrediction.equivalentDuration(
            fromDistanceMeters: 0, duration: 500, toDistanceMeters: twoMiles) == nil,
            "zero distance returns nil")
        check(PacePrediction.equivalentDuration(
            fromDistanceMeters: twoMiles, duration: 0, toDistanceMeters: twoMiles) == nil,
            "zero duration returns nil")

        check(PacePrediction.isDependable(fromDistanceMeters: twoMiles, toDistanceMeters: twoMiles),
              "a run at the goal distance is dependable")
        check(!PacePrediction.isDependable(fromDistanceMeters: 400, toDistanceMeters: twoMiles),
              "a very short run is not dependable")

        check(PacePrediction.liveProjection(distanceMeters: 50, elapsed: 20, goal: goal) == nil,
              "live projection is withheld at the start")
        check(PacePrediction.liveProjection(distanceMeters: 800, elapsed: 300, goal: goal) != nil,
              "live projection appears once under way")

        // Attempt classification.
        let directRun = run(meters: twoMiles, seconds: 800, day: 0)
        let directAttempt = GoalEvaluation.attempt(for: directRun, goal: goal)
        check(directAttempt?.isDirectAttempt == true, "a run at the goal distance is a direct attempt")
        check(nearly(directAttempt?.goalDistanceDuration ?? 0, 800), "a direct attempt keeps its own time")

        let shortRun = run(meters: metersPerMile, seconds: 330, day: 1)
        let shortAttempt = GoalEvaluation.attempt(for: shortRun, goal: goal)
        check(shortAttempt?.isDirectAttempt == false, "a one-mile run is not a direct attempt")
        check((shortAttempt?.goalDistanceDuration ?? 0) > 660, "a one-mile run is scaled up")

        // Ordering, best, and comparison.
        let firstID = UUID(), secondID = UUID(), thirdID = UUID()
        let records = [
            run(id: firstID, meters: twoMiles, seconds: 900, day: 0),
            run(id: secondID, meters: twoMiles, seconds: 840, day: 3),
            run(id: thirdID, meters: twoMiles, seconds: 860, day: 6)
        ]
        var populated = goal
        populated.runIDs = [thirdID, firstID, secondID]

        let ordered = GoalEvaluation.attempts(for: populated, in: records)
        check(ordered.map(\.runID) == [firstID, secondID, thirdID], "attempts are ordered oldest first")
        check(GoalEvaluation.best(for: populated, in: records)?.runID == secondID, "best attempt is the fastest")

        guard let third = GoalEvaluation.outcome(forRunID: thirdID, goal: populated, records: records),
              let second = GoalEvaluation.outcome(forRunID: secondID, goal: populated, records: records),
              let first = GoalEvaluation.outcome(forRunID: firstID, goal: populated, records: records) else {
            fputs("Failed: an outcome was missing\n", stderr)
            exit(1)
        }

        check(third.reachedTarget == false, "third run is behind the target")
        check(nearly(third.deltaToTarget, 140), "third run is 2:20 off the target")
        check(nearly(third.deltaToPrevious ?? 0, 20), "third run compares with the run before it")
        check(nearly(third.deltaToBestBefore ?? 0, 20), "third run is slower than the best before it")
        check(third.isPersonalBest == false, "third run is not a personal best")
        check(third.isFirstAttempt == false, "third run is not the first attempt")

        check((second.deltaToPrevious ?? 0) < 0, "second run improves on the first")
        check(second.isPersonalBest, "second run is a personal best")

        check(first.isFirstAttempt, "first run has no previous run")
        check(first.isPersonalBest, "first run counts as a best")
        check(first.deltaToPrevious == nil, "first run has no previous delta")

        let progress = third.progressFraction(firstAttempt: ordered.first)
        check(progress != nil, "progress is measured against the first attempt")
        check((progress ?? -1) > 0 && (progress ?? 2) < 1, "progress lies between zero and one")

        // A run that meets the target reports success.
        let fastID = UUID()
        var metGoal = goal
        metGoal.runIDs = [fastID]
        let metRecords = [run(id: fastID, meters: twoMiles, seconds: 700, day: 9)]
        let met = GoalEvaluation.outcome(forRunID: fastID, goal: metGoal, records: metRecords)
        check(met?.reachedTarget == true, "a fast enough run reaches the target")
        check((met?.deltaToTarget ?? 0) < 0, "beating the target gives a negative delta")

        // Goals saved before the title became derived still carry a title key.
        // Decoding must ignore it rather than fail the whole goals file.
        let legacyGoalJSON = """
        [{"id":"E1F1A1D2-0000-4000-8000-00000000000A","createdAt":770000000,
        "title":"stale name","distanceMeters":3218.688,"targetDuration":720,
        "runIDs":[],"isArchived":false}]
        """
        let legacyGoals = try? JSONDecoder().decode([RunGoal].self, from: Data(legacyGoalJSON.utf8))
        check(legacyGoals?.count == 1, "a goal saved with a title key still decodes")
        check(legacyGoals?.first?.targetDuration == 720, "the legacy target survives")
        check(legacyGoals?.first?.title == "2 mi in 12:00", "the title is derived, not the stale stored one")

        // Editing a goal keeps the runs already added to it.
        var edited = populated
        edited.targetDuration = 690
        edited.distanceMeters = 2 * metersPerMile
        check(edited.runIDs.count == 3, "editing a goal keeps its runs")
        check(GoalEvaluation.attempts(for: edited, in: records).count == 3, "edited goal still evaluates its runs")
        check(nearly(edited.targetPace, 345), "an edited target changes the pace")

        // Formatting and derived values.
        check((-84.0 as TimeInterval).differenceText == "1:24", "difference text drops the sign")
        check((0.0 as TimeInterval).differenceText == "0:00", "difference text handles zero")
        check(nearly(goal.targetPace, 360), "target pace is derived from the goal")

        print("Passed \(completedChecks) goal-engine checks")
    }

    private static func run(
        id: UUID = UUID(),
        meters: Double,
        seconds: TimeInterval,
        day: Double
    ) -> RunRecord {
        let start = Date(timeIntervalSince1970: 1_780_000_000 + day * 86_400)
        return RunRecord(
            id: id,
            startedAt: start,
            endedAt: start.addingTimeInterval(seconds),
            distanceMeters: meters,
            activeDuration: seconds,
            mileSplits: []
        )
    }

    private static func nearly(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.5) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("Failed: \(name)\n", stderr)
            exit(1)
        }
        completedChecks += 1
    }
}
