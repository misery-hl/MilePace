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

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
