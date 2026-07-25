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

        // A pace of an hour or more per mile is slow but real. Blanking it hid
        // the largest number on the running screen whenever a runner stopped
        // mid-mile without pausing.
        check((3_599.0 as TimeInterval).paceText == "59:59", "a pace just under an hour formats")
        check((3_600.0 as TimeInterval).paceText == "1:00:00", "a pace of exactly an hour formats")
        check((3_661.0 as TimeInterval).paceText == "1:01:01", "a pace over an hour formats")
        check((0.0 as TimeInterval).paceText == "--:--", "a zero pace is still blank")
        check((-5.0 as TimeInterval).paceText == "--:--", "a negative pace is still blank")

        // The projection must stop once the goal distance is behind the runner.
        // Riegel scaled downwards keeps improving as the run continues, which
        // describes a performance that already finished.
        check(PacePrediction.liveProjection(
            distanceMeters: twoMiles + 1, elapsed: 900, goal: goal) == nil,
            "no live projection once the goal distance is passed")
        check(PacePrediction.liveProjection(
            distanceMeters: twoMiles - 100, elapsed: 700, goal: goal) != nil,
            "a live projection exists just before the goal distance")
        check(PacePrediction.hasPassedGoalDistance(distanceMeters: twoMiles, goal: goal),
              "reaching the goal distance counts as passed")
        check(!PacePrediction.hasPassedGoalDistance(distanceMeters: 500, goal: goal),
              "a short run has not passed the goal distance")

        // Progress must not claim credit the runner has not earned.
        let fastFirstID = UUID(), slowLaterID = UUID()
        var beatenGoal = RunGoal(distanceMeters: metersPerMile, targetDuration: 300)
        beatenGoal.runIDs = [fastFirstID, slowLaterID]
        let beatenRecords = [
            run(id: fastFirstID, meters: metersPerMile, seconds: 290, day: 0),
            run(id: slowLaterID, meters: metersPerMile, seconds: 360, day: 4)
        ]
        let beatenAttempts = GoalEvaluation.attempts(for: beatenGoal, in: beatenRecords)
        guard let regression = GoalEvaluation.outcome(
            forRunID: slowLaterID, goal: beatenGoal, records: beatenRecords) else {
            fputs("Failed: regression outcome missing\n", stderr)
            exit(1)
        }
        check(regression.deltaToTarget > 0, "the later run missed the target")
        check(regression.progressFraction(firstAttempt: beatenAttempts.first) == nil,
              "a run that misses reports no progress when the first attempt already won")
        guard let firstWin = GoalEvaluation.outcome(
            forRunID: fastFirstID, goal: beatenGoal, records: beatenRecords) else {
            fputs("Failed: first-win outcome missing\n", stderr)
            exit(1)
        }
        check(firstWin.progressFraction(firstAttempt: beatenAttempts.first) == 1,
              "a run that meets the target reports full progress")

        // Thinning keeps the shape of a route and the boundaries of a pause.
        var dense: [TrackPoint] = []
        for i in 0..<4_000 {
            dense.append(TrackPoint(
                latitude: 40 + Double(i) * 0.00001, longitude: -75,
                timestamp: Date(timeIntervalSince1970: 1_780_000_000 + Double(i)),
                altitude: nil, horizontalAccuracy: 5, segment: i < 2_000 ? 0 : 1))
        }
        let thinned = RouteThinning.thin(dense)
        check(thinned.count < dense.count, "a dense route is thinned")
        check(thinned.count <= RouteThinning.maximumPoints + 8, "thinning respects the limit")
        check(thinned.first == dense.first, "thinning keeps the first point")
        check(thinned.last == dense.last, "thinning keeps the last point")
        check(thinned.contains(dense[1_999]), "thinning keeps the end of a segment")
        check(thinned.contains(dense[2_000]), "thinning keeps the start of the next segment")
        check(Set(thinned.map(\.segment)) == [0, 1], "thinning keeps both segments")
        check(zip(thinned, thinned.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp },
              "thinning keeps the points in order")
        let sparse = Array(dense.prefix(20))
        check(RouteThinning.thin(sparse) == sparse, "a short route is left alone")
        check(RouteThinning.thin([]).isEmpty, "an empty route stays empty")

        // Distance units: even steps, exact conversion, and no odd intervals.
        check(DistanceUnit.miles.options.count == 500, "the mile picker offers 500 steps")
        check(nearly(DistanceUnit.miles.options[0], metersPerMile / 10, tolerance: 0.001),
              "the first mile step is a tenth of a mile")
        check(DistanceUnit.miles.text(forMeters: 3.1 * metersPerMile) == "3.1 mi",
              "a 5 km distance reads as 3.1 mi")
        check(DistanceUnit.miles.text(forMeters: 2 * metersPerMile) == "2 mi",
              "a whole number of miles drops the decimal")
        check(DistanceUnit.kilometers.text(forMeters: 5_000) == "5 km", "5000 m reads as 5 km")
        check(DistanceUnit.meters.text(forMeters: 400) == "400 m", "400 m reads exactly")
        check(DistanceUnit.yards.text(forMeters: 0.9144 * 220) == "220 yd", "220 yd reads exactly")

        // Yards start at the 40 yard dash, which is why most people use yards.
        check(DistanceUnit.yards.text(forMeters: DistanceUnit.yards.options[0]) == "40 yd",
              "the yard picker starts at 40 yd")
        check(DistanceUnit.yards.text(forMeters: DistanceUnit.yards.options[1]) == "50 yd",
              "the yard picker then steps by 10")
        for yards in [40.0, 100.0, 220.0, 440.0, 880.0, 1_760.0] {
            check(DistanceUnit.yards.options.contains { nearly($0, 0.9144 * yards, tolerance: 0.001) },
                  "\(Int(yards)) yd is on the picker")
        }
        check(DistanceUnit.yards.text(forMeters: DistanceUnit.yards.options.last ?? 0) == "1760 yd",
              "the yard picker stops at a mile of yards")
        check(DistanceUnit.meters.text(forMeters: DistanceUnit.meters.options.last ?? 0) == "1600 m",
              "the metre picker stops at a mile of metres")

        // Run and sprint are separate kinds, with separate units.
        check(GoalKind.run.units == [.miles, .kilometers], "a run is stated in miles or kilometres")
        check(GoalKind.sprint.units == [.meters, .yards], "a sprint is stated in metres or yards")
        check(GoalKind.run.allowsPaceEntry, "a run can be entered as a pace")
        check(!GoalKind.sprint.allowsPaceEntry, "a sprint cannot be entered as a pace")
        check(DistanceUnit.miles.kind == .run && DistanceUnit.kilometers.kind == .run,
              "road units belong to the run kind")
        check(DistanceUnit.meters.kind == .sprint && DistanceUnit.yards.kind == .sprint,
              "sprint units belong to the sprint kind")
        for unit in DistanceUnit.allCases {
            check(unit.kind.units.contains(unit), "\(unit.shortName) belongs to its own kind")
        }

        // The kind is derived, so a goal and its unit can never disagree.
        let sprintGoal = RunGoal(distanceMeters: 0.9144 * 40, targetDuration: 5, distanceUnit: .yards)
        check(sprintGoal.kind == .sprint, "a yard goal is a sprint")
        check(!sprintGoal.showsPace, "a sprint goal hides its pace per mile")
        check(sprintGoal.title == "40 yd in 0:05", "a sprint goal reads as a distance and a time")
        let runGoal = RunGoal(distanceMeters: 5_000, targetDuration: 1_500, distanceUnit: .kilometers)
        check(runGoal.kind == .run, "a kilometre goal is a run")
        check(runGoal.showsPace, "a run goal shows its pace per mile")

        // Sprint distances people actually race are all reachable.
        for meters in [60.0, 100.0, 200.0, 400.0, 800.0, 1_500.0, 1_600.0] {
            check(DistanceUnit.meters.options.contains { nearly($0, meters, tolerance: 0.001) },
                  "\(Int(meters)) m is on the sprint picker")
        }

        // Every other unit still starts at one step.
        check(nearly(DistanceUnit.meters.options[0], 5, tolerance: 0.001), "metres start at 5 m")
        check(DistanceUnit.kilometers.text(forMeters: DistanceUnit.kilometers.options[0]) == "0.1 km",
              "kilometres start at a tenth")

        // Every step is the same size, which is what the curated list got wrong.
        let mileSteps = DistanceUnit.miles.options
        let gaps = zip(mileSteps, mileSteps.dropFirst()).map { $1 - $0 }
        check(gaps.allSatisfy { nearly($0, metersPerMile / 10, tolerance: 0.001) },
              "every mile step is the same size")

        // Track distances up to a mile are reachable exactly. Anything longer
        // is a run, set in kilometres or miles, not a sprint.
        for distance in [400.0, 800.0, 1_500.0] {
            check(DistanceUnit.meters.options.contains { nearly($0, distance, tolerance: 0.001) },
                  "\(Int(distance)) m is on the sprint picker")
        }
        check(!DistanceUnit.meters.options.contains { nearly($0, 5_000, tolerance: 0.001) },
              "5000 m is not a sprint; it is a run in kilometres")
        check(nearly(DistanceUnit.kilometers.nearestOption(toMeters: 5_000), 5_000, tolerance: 0.001),
              "5000 m is exact on the kilometre picker instead")

        // Switching unit keeps the goal rather than resetting it.
        let fiveKm = 5_000.0
        let asMiles = DistanceUnit.miles.nearestOption(toMeters: fiveKm)
        check(abs(asMiles - fiveKm) < metersPerMile / 20, "5 km maps to the nearest mile step")
        check(DistanceUnit.miles.text(forMeters: asMiles) == "3.1 mi", "and that step reads as 3.1 mi")
        check(nearly(DistanceUnit.kilometers.nearestOption(toMeters: fiveKm), fiveKm, tolerance: 0.001),
              "5 km is exact in kilometres")

        // Goals saved before units existed still load, and read as miles.
        let unitlessJSON = """
        [{"id":"E1F1A1D2-0000-4000-8000-00000000000B","createdAt":770000000,
        "distanceMeters":3218.688,"targetDuration":720,"runIDs":[],"isArchived":false}]
        """
        let unitless = try? JSONDecoder().decode([RunGoal].self, from: Data(unitlessJSON.utf8))
        check(unitless?.count == 1, "a goal saved without a unit still decodes")
        check(unitless?.first?.distanceUnit == .miles, "a goal without a unit defaults to miles")
        check(unitless?.first?.title == "2 mi in 12:00", "and still reads the same")

        // A distance from another unit must not park the wheel at its far end.
        // Switching a 5 km goal to sprint used to open at 1,600 m.
        check(nearly(DistanceUnit.meters.sensibleOption(forMeters: 5_000), 100, tolerance: 0.001),
              "a 5 km goal opens the metre wheel at 100 m, not 1600 m")
        check(nearly(DistanceUnit.yards.sensibleOption(forMeters: 5_000), 0.9144 * 40, tolerance: 0.001),
              "a 5 km goal opens the yard wheel at the 40 yard dash")
        check(nearly(DistanceUnit.miles.sensibleOption(forMeters: 0.9144 * 40), 2 * metersPerMile, tolerance: 0.001),
              "a 40 yard goal opens the mile wheel at 2 mi, not 0.1 mi")
        check(nearly(DistanceUnit.kilometers.sensibleOption(forMeters: 0.9144 * 40), 5_000, tolerance: 0.001),
              "a 40 yard goal opens the kilometre wheel at 5 km")

        // A distance that does fit is still kept exactly.
        check(nearly(DistanceUnit.meters.sensibleOption(forMeters: 400), 400, tolerance: 0.001),
              "400 m is kept when switching to metres")
        check(nearly(DistanceUnit.kilometers.sensibleOption(forMeters: 5_000), 5_000, tolerance: 0.001),
              "5 km is kept when switching to kilometres")
        check(nearly(DistanceUnit.miles.sensibleOption(forMeters: 5_000), DistanceUnit.miles.nearestOption(toMeters: 5_000), tolerance: 0.001),
              "a 5 km goal still maps onto the nearest mile step")

        // Every default is a real option on its own wheel.
        for unit in DistanceUnit.allCases {
            check(unit.options.contains { nearly($0, unit.defaultOptionMeters, tolerance: 0.001) },
                  "the \(unit.shortName) default is on its own wheel")
        }

        // A name never replaces what the goal is; it only adds why it exists.
        let named = RunGoal(name: "Turkey Trot", distanceMeters: 5_000,
                            targetDuration: 1_500, distanceUnit: .kilometers)
        check(named.title == "5 km in 25:00", "a named goal keeps its distance and target as its title")
        check(named.displayName == "Turkey Trot", "a named goal is called by its name")
        let unnamed = RunGoal(distanceMeters: 5_000, targetDuration: 1_500, distanceUnit: .kilometers)
        check(unnamed.displayName == "5 km in 25:00", "an unnamed goal falls back to its title")
        check(unnamed.name.isEmpty, "an unnamed goal has an empty name")

        // Goals saved before naming existed decode as unnamed.
        let unnamedJSON = """
        [{"id":"E1F1A1D2-0000-4000-8000-00000000000C","createdAt":770000000,
        "distanceMeters":3218.688,"targetDuration":720,"runIDs":[],"isArchived":false}]
        """
        let older = try? JSONDecoder().decode([RunGoal].self, from: Data(unnamedJSON.utf8))
        check(older?.count == 1, "a goal saved before naming still decodes")
        check(older?.first?.name.isEmpty == true, "it decodes as unnamed")
        check(older?.first?.displayName == "2 mi in 12:00", "and still reads the same")

        // Elevation is filtered: GPS altitude wanders several metres even when
        // the phone is still, so counting every change would invent climb.
        var climb = RunAccumulator()
        climb.recordAltitude(100, verticalAccuracy: 5)
        climb.recordAltitude(101, verticalAccuracy: 5)
        climb.recordAltitude(102, verticalAccuracy: 5)
        check(climb.elevationGainMeters == 0, "noise below the threshold is not counted as climb")
        climb.recordAltitude(105, verticalAccuracy: 5)
        check(nearly(climb.elevationGainMeters, 5, tolerance: 0.001), "a real climb is counted in full")
        climb.recordAltitude(100, verticalAccuracy: 5)
        check(nearly(climb.elevationLossMeters, 5, tolerance: 0.001), "a descent is counted separately")
        check(nearly(climb.elevationGainMeters, 5, tolerance: 0.001), "a descent does not reduce the climb")

        var invalid = RunAccumulator()
        invalid.recordAltitude(100, verticalAccuracy: -1)
        invalid.recordAltitude(200, verticalAccuracy: -1)
        check(invalid.elevationGainMeters == 0, "an invalid altitude reading is ignored")
        var imprecise = RunAccumulator()
        imprecise.recordAltitude(100, verticalAccuracy: 50)
        imprecise.recordAltitude(200, verticalAccuracy: 50)
        check(imprecise.elevationGainMeters == 0, "an imprecise altitude reading is ignored")

        // A steady climb accumulates even in small steps, because the threshold
        // is measured from the last counted altitude, not the previous sample.
        var steady = RunAccumulator()
        for i in 0...40 { steady.recordAltitude(100 + Double(i), verticalAccuracy: 5) }
        check(steady.elevationGainMeters >= 36, "a steady climb accumulates in full")

        // A run reports elevation only when there is enough to be worth saying.
        let flat = RunRecord(id: UUID(), startedAt: Date(), endedAt: Date(), distanceMeters: 5_000,
                             activeDuration: 1_500, mileSplits: [], elevationGainMeters: 2)
        check(!flat.hasMeaningfulElevation, "a flat run reports no elevation")
        let hilly = RunRecord(id: UUID(), startedAt: Date(), endedAt: Date(), distanceMeters: 5_000,
                              activeDuration: 1_500, mileSplits: [], elevationGainMeters: 120)
        check(hilly.hasMeaningfulElevation, "a hilly run reports its elevation")
        check(nearly(hilly.elevationGainFeet, 393.7, tolerance: 0.5), "metres convert to feet")

        // Runs saved before elevation existed decode as flat.
        let preElevationJSON = """
        [{"id":"E1F1A1D2-0000-4000-8000-00000000000D","startedAt":770000000,"endedAt":770000900,
        "distanceMeters":5000,"activeDuration":900,"mileSplits":[]}]
        """
        let preElevation = try? JSONDecoder().decode([RunRecord].self, from: Data(preElevationJSON.utf8))
        check(preElevation?.count == 1, "a run saved before elevation still decodes")
        check(preElevation?.first?.elevationGainMeters == 0, "it decodes as flat")

        // Deleting a run must not leave a goal counting it. A goal holding a
        // missing identifier silently drops the attempt and changes its best.
        let keptID = UUID(), goneID = UUID()
        var withBoth = RunGoal(distanceMeters: twoMiles, targetDuration: 720)
        withBoth.runIDs = [keptID, goneID]
        let bothRecords = [
            run(id: keptID, meters: twoMiles, seconds: 900, day: 0),
            run(id: goneID, meters: twoMiles, seconds: 780, day: 3)
        ]
        check(GoalEvaluation.attempts(for: withBoth, in: bothRecords).count == 2,
              "a goal counts both of its runs")
        check(GoalEvaluation.best(for: withBoth, in: bothRecords)?.runID == goneID,
              "the faster run is the best")

        // Simulate the run being deleted without detaching it.
        let onlyKept = [bothRecords[0]]
        check(GoalEvaluation.attempts(for: withBoth, in: onlyKept).count == 1,
              "a deleted run silently vanishes from the goal")
        check(withBoth.runIDs.count == 2,
              "but the goal still holds its identifier, which is why detaching matters")

        // Detaching leaves the goal honest.
        var detached = withBoth
        detached.runIDs.removeAll { $0 == goneID }
        check(detached.runIDs == [keptID], "detaching removes only the deleted run")
        check(GoalEvaluation.best(for: detached, in: onlyKept)?.runID == keptID,
              "the remaining run becomes the best")

        // Archiving keeps a run and its goal membership.
        let archived = RunRecord(id: keptID, startedAt: Date(), endedAt: Date(),
                                 distanceMeters: twoMiles, activeDuration: 900,
                                 mileSplits: [], isArchived: true)
        check(archived.isArchived, "a run can be archived")
        check(GoalEvaluation.attempts(for: detached, in: [archived]).count == 1,
              "an archived run still counts towards its goal")

        // Runs saved before archiving decode as not archived.
        let preArchiveJSON = """
        [{"id":"E1F1A1D2-0000-4000-8000-00000000000E","startedAt":770000000,"endedAt":770000900,
        "distanceMeters":5000,"activeDuration":900,"mileSplits":[]}]
        """
        let preArchive = try? JSONDecoder().decode([RunRecord].self, from: Data(preArchiveJSON.utf8))
        check(preArchive?.count == 1, "a run saved before archiving still decodes")
        check(preArchive?.first?.isArchived == false, "it decodes as not archived")

        // Route geometry: distance, and how far a point strays from the line.
        // Two points ~111 m apart in latitude (0.001 deg).
        let a = RoutePoint(latitude: 40.000, longitude: -75.000)
        let b = RoutePoint(latitude: 40.001, longitude: -75.000)
        check(nearly(RouteGeometry.distance(a, b), 111.2, tolerance: 1), "haversine measures a short leg")
        let square = [
            RoutePoint(latitude: 40.000, longitude: -75.000),
            RoutePoint(latitude: 40.001, longitude: -75.000),
            RoutePoint(latitude: 40.001, longitude: -74.999)
        ]
        check(nearly(RouteGeometry.length(of: square), 111.2 + 85.3, tolerance: 3), "length sums the legs")
        check(RouteGeometry.length(of: []) == 0, "an empty line has no length")
        check(RouteGeometry.length(of: [a]) == 0, "a single point has no length")

        // A point on the line is zero from it; a point beside it is its offset.
        let onLine = RoutePoint(latitude: 40.0005, longitude: -75.000)
        check((RouteGeometry.distanceToLine(from: onLine, line: [a, b]) ?? 99) < 1,
              "a point on the line is on the line")
        let beside = RoutePoint(latitude: 40.0005, longitude: -74.9993)
        let offset = RouteGeometry.distanceToLine(from: beside, line: [a, b]) ?? 0
        check(nearly(offset, 60, tolerance: 8), "a point beside the line reports how far off it is")

        // Straying past the end of a segment measures to the endpoint, not the
        // infinite line, so a runner past the finish is not called on-route.
        let pastEnd = RoutePoint(latitude: 40.002, longitude: -75.000)
        check(nearly(RouteGeometry.distanceToLine(from: pastEnd, line: [a, b]) ?? 0, 111.2, tolerance: 2),
              "distance clamps to the segment ends")

        // A route from a run takes the run's path as its line.
        let runWithRoute = RunRecord(
            id: UUID(), startedAt: Date(), endedAt: Date(),
            distanceMeters: 1_000, activeDuration: 300, mileSplits: [],
            trackPoints: [
                TrackPoint(latitude: 40.0, longitude: -75.0, timestamp: Date(), altitude: nil, horizontalAccuracy: 5, segment: 0),
                TrackPoint(latitude: 40.001, longitude: -75.0, timestamp: Date(), altitude: nil, horizontalAccuracy: 5, segment: 0)
            ])
        let fromRun = PlannedRoute(fromRun: runWithRoute)
        check(fromRun.line.count == 2, "a route from a run takes its path")
        check(fromRun.origin == .pastRun, "and is marked as coming from a run")
        check(nearly(fromRun.distanceMeters, 111.2, tolerance: 1), "and measures the run's path")

        // A saved route round-trips through JSON.
        let drawn = PlannedRoute(name: "Loop", origin: .drawn,
                                 waypoints: square, line: square)
        let roundTripped = (try? JSONEncoder().encode(drawn))
            .flatMap { try? JSONDecoder().decode(PlannedRoute.self, from: $0) }
        check(roundTripped == drawn, "a route round-trips through JSON")
        check(roundTripped?.displayName == "Loop", "a named route shows its name")
        let unnamedRoute = PlannedRoute(origin: .drawn, line: square)
        check(unnamedRoute.displayName.contains("mi route"), "an unnamed route shows its distance")

        // Archiving a route keeps it. Routes saved before archiving decode as
        // not archived, so an old routes.json keeps loading.
        check(drawn.isArchived == false, "a new route is not archived")
        let archivedRouteJSON = """
        [{"id":"E1F1A1D2-0000-4000-8000-00000000000F","createdAt":770000000,"name":"Old",
        "origin":"drawn","waypoints":[],"line":[{"latitude":40.0,"longitude":-75.0},{"latitude":40.001,"longitude":-75.0}]}]
        """
        let oldRoutes = try? JSONDecoder().decode([PlannedRoute].self, from: Data(archivedRouteJSON.utf8))
        check(oldRoutes?.count == 1, "a route saved before archiving still decodes")
        check(oldRoutes?.first?.isArchived == false, "it decodes as not archived")
        check(oldRoutes?.first?.name == "Old", "and keeps its name")

        // Route similarity, and the twice-run suggestion rule.
        func routeRun(id: UUID = UUID(), _ points: [RoutePoint], day: Double) -> RunRecord {
            let start = Date(timeIntervalSince1970: 1_784_000_000 + day * 86_400)
            return RunRecord(id: id, startedAt: start, endedAt: start.addingTimeInterval(600),
                             distanceMeters: RouteGeometry.length(of: points), activeDuration: 600,
                             mileSplits: [],
                             trackPoints: points.map { TrackPoint(latitude: $0.latitude, longitude: $0.longitude,
                                 timestamp: start, altitude: nil, horizontalAccuracy: 5, segment: 0) })
        }
        // A straight kilometre north, and the same path with slight GPS wander.
        let pathA = (0...20).map { RoutePoint(latitude: 40.0 + Double($0) * 0.0005, longitude: -75.0) }
        let pathAWander = (0...20).map { RoutePoint(latitude: 40.0 + Double($0) * 0.0005,
                                                    longitude: -75.0 + ($0 % 2 == 0 ? 0.0002 : -0.0002)) }
        // A different path, a kilometre east.
        let pathB = (0...20).map { RoutePoint(latitude: 40.0, longitude: -75.0 + Double($0) * 0.0006) }

        check(RouteSimilarity.isSameRoute(pathA, pathAWander), "the same path with GPS wander is the same route")
        check(!RouteSimilarity.isSameRoute(pathA, pathB), "a different path is a different route")
        check(!RouteSimilarity.isSameRoute(pathA, Array(pathA.prefix(6))), "a much shorter path is not the same route")
        check(!RouteSimilarity.isSameRoute(pathA, []), "an empty path matches nothing")

        // Suggest only a run done before and not already saved.
        let firstRun = routeRun(pathA, day: 0)
        let secondRun = routeRun(pathAWander, day: 3)
        let otherRun = routeRun(pathB, day: 1)
        check(!RouteSuggestion.shouldSuggest(for: firstRun, existingRoutes: [], history: [firstRun]),
              "a first-time run is not suggested")
        check(RouteSuggestion.shouldSuggest(for: secondRun, existingRoutes: [], history: [firstRun, otherRun, secondRun]),
              "a run done a second time is suggested")
        let alreadySaved = PlannedRoute(origin: .pastRun, line: pathA)
        check(!RouteSuggestion.shouldSuggest(for: secondRun, existingRoutes: [alreadySaved], history: [firstRun, secondRun]),
              "a run already saved as a route is not suggested again")
        check(!RouteSuggestion.shouldSuggest(for: routeRun([], day: 5), existingRoutes: [], history: [firstRun]),
              "a run with no path is never suggested")

        // Off-route detection: threshold, dwell, and hysteresis.
        var monitor = OffRouteMonitor()   // off at 40 m, on at 25 m, dwell 8 s
        // On the line: nothing happens.
        check(monitor.update(distanceFromLine: 5, accuracy: 5, elapsed: 0) == nil,
              "a runner on the route triggers nothing")
        // Straying starts the dwell but does not fire immediately.
        check(monitor.update(distanceFromLine: 60, accuracy: 5, elapsed: 10) == nil,
              "crossing the threshold does not fire at once")
        check(monitor.isOffRoute == false, "still on route during the dwell")
        // Still straying, but not long enough.
        check(monitor.update(distanceFromLine: 60, accuracy: 5, elapsed: 15) == nil,
              "still within the dwell, still quiet")
        // Past the dwell: fires.
        check(monitor.update(distanceFromLine: 60, accuracy: 5, elapsed: 19) == .wentOffRoute,
              "straying past the dwell fires off-route")
        check(monitor.isOffRoute, "now off route")
        // A little closer, but not inside the on threshold: stays off.
        check(monitor.update(distanceFromLine: 30, accuracy: 5, elapsed: 22) == nil,
              "between the thresholds the alert holds, so it does not flap")
        check(monitor.isOffRoute, "still off route in the hysteresis band")
        // Back inside the tighter on threshold: returns.
        check(monitor.update(distanceFromLine: 20, accuracy: 5, elapsed: 25) == .returnedToRoute,
              "coming back inside the on threshold clears it")
        check(monitor.isOffRoute == false, "back on route")

        // A single stray fix, then back, never fires.
        var flicker = OffRouteMonitor()
        check(flicker.update(distanceFromLine: 80, accuracy: 5, elapsed: 0) == nil, "one stray fix")
        check(flicker.update(distanceFromLine: 5, accuracy: 5, elapsed: 2) == nil, "then back on route")
        check(flicker.update(distanceFromLine: 5, accuracy: 5, elapsed: 12) == nil, "no delayed false alarm")
        check(flicker.isOffRoute == false, "a brief stray never fires")

        // A poor fix widens the threshold, so noise alone does not fire.
        var noisy = OffRouteMonitor()
        check(noisy.update(distanceFromLine: 55, accuracy: 30, elapsed: 0) == nil, "a 55 m stray with a 30 m fix")
        check(noisy.update(distanceFromLine: 55, accuracy: 30, elapsed: 20) == nil,
              "stays quiet, because 40 + 30 accuracy is not exceeded")
        check(noisy.isOffRoute == false, "an inaccurate fix does not raise a false alarm")

        // Reset clears everything.
        monitor.reset()
        check(monitor.isOffRoute == false, "reset clears the off-route state")

        // Only the absurd is rejected. Checked as a speed so one rule covers
        // a 40 yard dash and a marathon.
        check(RunGoal(distanceMeters: twoMiles, targetDuration: 720).isPlausible,
              "a 2 mi in 12:00 is plausible")
        check(RunGoal(distanceMeters: 0.9144 * 40, targetDuration: 4, distanceUnit: .yards).isPlausible,
              "a 4 second 40 yard dash is plausible")
        check(RunGoal(distanceMeters: 42_195, targetDuration: 7_200).isPlausible,
              "a two hour marathon is plausible")
        check(!RunGoal(distanceMeters: 5_000, targetDuration: 1).isPlausible,
              "a 5 km in one second is rejected")
        check(!RunGoal(distanceMeters: 42_195, targetDuration: 60).isPlausible,
              "a one minute marathon is rejected")
        check(!RunGoal(distanceMeters: metersPerMile, targetDuration: 36_000).isPlausible,
              "a ten hour mile is rejected")
        check(!RunGoal(distanceMeters: twoMiles, targetDuration: 0).isPlausible,
              "a zero target is rejected")
        check(RunGoal(distanceMeters: 5_000, targetDuration: 1).implausibleReason != nil,
              "an implausible goal explains itself")
        check(RunGoal(distanceMeters: twoMiles, targetDuration: 720).implausibleReason == nil,
              "a plausible goal has nothing to explain")

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
