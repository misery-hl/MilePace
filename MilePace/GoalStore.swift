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

    /// The goal a new run measures itself against. The app keeps one goal active
    /// at a time, so the live screen never has to ask which one the runner means.
    var activeGoal: RunGoal? {
        goals.first { !$0.isArchived }
    }

    func add(_ goal: RunGoal) {
        goals.insert(goal, at: 0)
        persist()
    }

    func archive(_ goal: RunGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].isArchived = true
        persist()
    }

    func delete(_ goal: RunGoal) {
        goals.removeAll { $0.id == goal.id }
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
