import Foundation

@MainActor
final class RunStore: ObservableObject {
    @Published private(set) var records: [RunRecord] = []
    /// Set when the history could not be read or written. A run that fails to
    /// save is gone at the next launch, and the runner deserves to know before
    /// then rather than after.
    @Published var storageError: String?

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

    /// Loads the history, and distinguishes "no history yet" from "the history
    /// could not be read". An unreadable file used to look exactly like a fresh
    /// install, so six months of runs could appear to have vanished with no
    /// explanation and no hint that the file was still on disk.
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        guard let data = try? Data(contentsOf: fileURL) else {
            storageError = "Your run history could not be read. It has not been deleted, so do not record over it before checking."
            return
        }

        do {
            records = try JSONDecoder()
                .decode([RunRecord].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            storageError = "Your run history could not be read. The file is still on disk, so do not record over it before checking."
        }
    }

    /// Encodes on the main actor, because `records` belongs to it, then writes
    /// off it. Finishing a run should never block the screen on disk I/O, and
    /// the write grows with the whole history rather than the new run.
    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else {
            storageError = "This run could not be saved. It will be lost when you close MilePace."
            return
        }

        let destination = fileURL
        Task.detached(priority: .utility) {
            do {
                try data.write(to: destination, options: .atomic)
            } catch {
                await MainActor.run {
                    self.storageError = "This run could not be written to storage. It will be lost when you close MilePace."
                }
            }
        }
    }
}
