import Foundation

@MainActor
final class RunStore: ObservableObject {
    @Published private(set) var records: [RunRecord] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MilePace", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("runs.json")
        }
        load()
    }

    func save(_ record: RunRecord) {
        records.insert(record, at: 0)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RunRecord].self, from: data) else { return }
        records = decoded.sorted(by: { $0.startedAt > $1.startedAt })
    }

    /// Encodes on the main actor, because `records` belongs to it, then writes
    /// off it. Finishing a run should never block the screen on disk I/O, and
    /// the write grows with the whole history rather than the new run.
    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let destination = fileURL
        Task.detached(priority: .utility) {
            try? data.write(to: destination, options: .atomic)
        }
    }
}
