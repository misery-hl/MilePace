import Foundation

/// Local persistence for goals, in the same directory as the run history.
@MainActor
final class GoalStore: ObservableObject {
    @Published private(set) var goals: [RunGoal] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MilePace", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("goals.json")
        }
        load()
    }

    /// Every goal the runner is currently working on. A runner can hold several
    /// at once, such as a mile, a two mile, and a half marathon.
    var activeGoals: [RunGoal] {
        goals.filter { !$0.isArchived }
    }

    /// The goal the live screen follows during a run.
    ///
    /// Only one goal can be shown while running, because the running screen has
    /// to stay glanceable. The runner picks which one. If they have not picked,
    /// or the picked goal is gone, this falls back to the first active goal.
    var trackedGoal: RunGoal? {
        if let trackedGoalID,
           let match = activeGoals.first(where: { $0.id == trackedGoalID }) {
            return match
        }
        return activeGoals.first
    }

    var trackedGoalID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.trackedKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.trackedKey)
            objectWillChange.send()
        }
    }

    private static let trackedKey = "MilePace.trackedGoalID"

    func add(_ goal: RunGoal) {
        goals.insert(goal, at: 0)
        persist()
    }

    /// Replaces the target of an existing goal. The runs already added stay
    /// attached, so correcting a goal never costs the runner their history.
    func update(_ goal: RunGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index] = goal
        persist()
    }

    func archive(_ goal: RunGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].isArchived = true
        persist()
    }

    /// Removes the goal and the run associations on it. The runs themselves live
    /// in the run history and are not touched.
    func delete(_ goal: RunGoal) {
        goals.removeAll { $0.id == goal.id }
        if trackedGoalID == goal.id { trackedGoalID = nil }
        persist()
    }

    /// Adds a run to a goal. Does nothing when the run is already applied, so
    /// tapping twice cannot record the same run as two attempts.
    func attach(runID: UUID, to goal: RunGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        guard !goals[index].runIDs.contains(runID) else { return }
        goals[index].runIDs.append(runID)
        persist()
    }

    func detach(runID: UUID, from goal: RunGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].runIDs.removeAll { $0 == runID }
        persist()
    }

    /// Removes a run from every goal, for when the run itself is deleted.
    /// A goal holding a missing identifier would silently drop an attempt and
    /// quietly change its own best time.
    func detachFromAllGoals(runID: UUID) {
        var changed = false
        for index in goals.indices where goals[index].runIDs.contains(runID) {
            goals[index].runIDs.removeAll { $0 == runID }
            changed = true
        }
        if changed { persist() }
    }

    /// Every active goal this run has been added to.
    func goalsContaining(runID: UUID) -> [RunGoal] {
        activeGoals.filter { $0.runIDs.contains(runID) }
    }

    func goal(withID id: UUID) -> RunGoal? {
        goals.first { $0.id == id }
    }

    func contains(runID: UUID, in goal: RunGoal) -> Bool {
        self.goal(withID: goal.id)?.runIDs.contains(runID) ?? false
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RunGoal].self, from: data) else { return }
        goals = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
