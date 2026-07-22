import Foundation

/// Race-time prediction and goal comparison.
///
/// This file stays free of Core Location, MapKit, SwiftUI, and UIKit so that
/// `swift build` and the checks in `Tools/` can compile it directly.
enum PacePrediction {
    /// Peter Riegel's endurance exponent, from his 1977 work on athletic
    /// records. The formula is:
    ///
    ///     T2 = T1 * (D2 / D1) ^ 1.06
    ///
    /// The exponent is greater than 1 because a runner cannot hold a short
    /// distance pace over a longer one. It is the common basis for race
    /// predictors. It fits distances from about 1500 m to the marathon.
    static let riegelExponent = 1.06

    /// A run between half and double the goal distance gives a dependable
    /// prediction. Outside that range the formula still returns a number, but
    /// the error grows, so the caller must tell the user it is less certain.
    static let dependableRatioRange = 0.5...2.0

    /// Predicts the time to cover `toDistanceMeters`, from a performance over
    /// `fromDistanceMeters`.
    ///
    /// The formula assumes the source performance was a maximal effort. An easy
    /// run predicts an easy time, not a race time. The caller must decide
    /// whether the source run was a real attempt.
    static func equivalentDuration(
        fromDistanceMeters: Double,
        duration: TimeInterval,
        toDistanceMeters: Double
    ) -> TimeInterval? {
        guard fromDistanceMeters > 0, toDistanceMeters > 0, duration > 0,
              fromDistanceMeters.isFinite, toDistanceMeters.isFinite, duration.isFinite
        else { return nil }

        let predicted = duration * pow(toDistanceMeters / fromDistanceMeters, riegelExponent)
        return predicted.isFinite ? predicted : nil
    }

    static func isDependable(fromDistanceMeters: Double, toDistanceMeters: Double) -> Bool {
        guard fromDistanceMeters > 0, toDistanceMeters > 0 else { return false }
        return dependableRatioRange.contains(toDistanceMeters / fromDistanceMeters)
    }

    /// Projects the finish time for the goal distance, from the run so far.
    ///
    /// This drives the live display. It needs a minimum distance because GPS
    /// pace is unstable at the start of a run and would make the projection
    /// jump about.
    /// Returns nil once the run has already passed the goal distance. Riegel
    /// estimates a maximal effort at a *different* distance; it is not a way to
    /// read a split back out of a longer run. Past the goal distance it would be
    /// asked to scale downwards, and the answer would keep improving purely
    /// because the runner kept running, describing a performance that already
    /// finished. Better to say nothing than to show a number that drifts.
    static func liveProjection(
        distanceMeters: Double,
        elapsed: TimeInterval,
        goal: RunGoal
    ) -> TimeInterval? {
        guard distanceMeters >= 160, distanceMeters < goal.distanceMeters else { return nil }
        return equivalentDuration(
            fromDistanceMeters: distanceMeters,
            duration: elapsed,
            toDistanceMeters: goal.distanceMeters
        )
    }

    /// True once the run is longer than the goal, so the live row can say the
    /// goal distance is behind the runner rather than showing a blank.
    static func hasPassedGoalDistance(distanceMeters: Double, goal: RunGoal) -> Bool {
        distanceMeters >= goal.distanceMeters && goal.distanceMeters > 0
    }
}

/// One run measured against one goal.
struct GoalAttempt: Equatable, Identifiable {
    let runID: UUID
    let date: Date
    let distanceMeters: Double
    let duration: TimeInterval
    /// The time for the goal distance. This equals `duration` when the run
    /// covered the goal distance. Otherwise Riegel's formula scales it.
    let goalDistanceDuration: TimeInterval
    /// True when the run distance was near enough to the goal distance to count
    /// as a real attempt rather than an estimate.
    let isDirectAttempt: Bool
    let isDependable: Bool

    var id: UUID { runID }
}

enum GoalEvaluation {
    /// A run within this fraction of the goal distance counts as a direct
    /// attempt. GPS distance has error, so an exact match is not realistic.
    static let directAttemptTolerance = 0.05

    static func attempt(for record: RunRecord, goal: RunGoal) -> GoalAttempt? {
        guard let equivalent = PacePrediction.equivalentDuration(
            fromDistanceMeters: record.distanceMeters,
            duration: record.activeDuration,
            toDistanceMeters: goal.distanceMeters
        ) else { return nil }

        let ratio = record.distanceMeters / goal.distanceMeters

        return GoalAttempt(
            runID: record.id,
            date: record.startedAt,
            distanceMeters: record.distanceMeters,
            duration: record.activeDuration,
            goalDistanceDuration: equivalent,
            isDirectAttempt: abs(ratio - 1) <= directAttemptTolerance,
            isDependable: PacePrediction.isDependable(
                fromDistanceMeters: record.distanceMeters,
                toDistanceMeters: goal.distanceMeters
            )
        )
    }

    /// All attempts for a goal, oldest first.
    static func attempts(for goal: RunGoal, in records: [RunRecord]) -> [GoalAttempt] {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return goal.runIDs
            .compactMap { byID[$0] }
            .compactMap { attempt(for: $0, goal: goal) }
            .sorted { $0.date < $1.date }
    }

    static func best(for goal: RunGoal, in records: [RunRecord]) -> GoalAttempt? {
        attempts(for: goal, in: records).min { $0.goalDistanceDuration < $1.goalDistanceDuration }
    }

    /// Builds the comparison shown after a run joins a goal. The goal must
    /// already contain the run.
    static func outcome(forRunID runID: UUID, goal: RunGoal, records: [RunRecord]) -> GoalOutcome? {
        let all = attempts(for: goal, in: records)
        guard let index = all.firstIndex(where: { $0.runID == runID }) else { return nil }

        let earlier = Array(all[..<index])
        return GoalOutcome(
            goal: goal,
            attempt: all[index],
            previous: earlier.last,
            bestBefore: earlier.min { $0.goalDistanceDuration < $1.goalDistanceDuration }
        )
    }
}

/// How one attempt compares with the target, with the attempt before it, and
/// with the best attempt before it.
///
/// A positive delta always means slower. The view chooses the wording.
struct GoalOutcome: Equatable {
    let goal: RunGoal
    let attempt: GoalAttempt
    /// The attempt immediately before this one, by date.
    let previous: GoalAttempt?
    /// The fastest attempt before this one.
    let bestBefore: GoalAttempt?

    var deltaToTarget: TimeInterval {
        attempt.goalDistanceDuration - goal.targetDuration
    }

    var reachedTarget: Bool {
        deltaToTarget <= 0
    }

    var deltaToPrevious: TimeInterval? {
        previous.map { attempt.goalDistanceDuration - $0.goalDistanceDuration }
    }

    var deltaToBestBefore: TimeInterval? {
        bestBefore.map { attempt.goalDistanceDuration - $0.goalDistanceDuration }
    }

    var isFirstAttempt: Bool {
        previous == nil
    }

    var isPersonalBest: Bool {
        guard let bestBefore else { return true }
        return attempt.goalDistanceDuration < bestBefore.goalDistanceDuration
    }

    /// How much of the gap to the target the runner has closed since the first
    /// attempt, from 0 to 1. This is the honest form of "how am I progressing":
    /// it measures the runner against their own starting point, with no
    /// population data behind it.
    func progressFraction(firstAttempt: GoalAttempt?) -> Double? {
        guard let firstAttempt else { return nil }

        let startingGap = firstAttempt.goalDistanceDuration - goal.targetDuration

        // The first attempt already met the target, so there was never a gap to
        // close. Reporting a fraction here would claim progress the runner has
        // not made, and would read as "100% closed" even on a run that missed
        // the target badly. Only a run that also meets the target is complete.
        guard startingGap > 0 else {
            return reachedTarget ? 1 : nil
        }

        let remainingGap = max(0, deltaToTarget)
        return min(max(1 - (remainingGap / startingGap), 0), 1)
    }
}
