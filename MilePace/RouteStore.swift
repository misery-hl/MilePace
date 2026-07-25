import Foundation

/// Local persistence for planned routes, beside the run and goal stores.
@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var routes: [PlannedRoute] = []
    @Published var storageError: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MilePace", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("routes.json")
        }
        load()
    }

    /// Routes the list shows. Archived routes are kept, but set aside.
    var visibleRoutes: [PlannedRoute] {
        routes.filter { !$0.isArchived }
    }

    var archivedRoutes: [PlannedRoute] {
        routes.filter(\.isArchived)
    }

    /// Whether to offer "save this as a route" after a repeated run. A runner
    /// who finds it noisy can turn it off from the suggestion itself, and it
    /// stays off. Defaults to on.
    var suggestsRoutes: Bool {
        get { UserDefaults.standard.object(forKey: Self.suggestKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.suggestKey)
            objectWillChange.send()
        }
    }

    private static let suggestKey = "MilePace.suggestsRoutes"

    func add(_ route: PlannedRoute) {
        routes.insert(route, at: 0)
        persist()
    }

    func rename(_ route: PlannedRoute, to name: String) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func setArchived(_ archived: Bool, for route: PlannedRoute) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[index].isArchived = archived
        persist()
    }

    func delete(_ route: PlannedRoute) {
        routes.removeAll { $0.id == route.id }
        persist()
    }

    func route(withID id: UUID) -> PlannedRoute? {
        routes.first { $0.id == id }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else {
            storageError = "Your saved routes could not be read. The file is still on disk, so nothing was deleted."
            return
        }
        do {
            routes = try JSONDecoder()
                .decode([PlannedRoute].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            storageError = "Your saved routes could not be read. The file is still on disk, so nothing was deleted."
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(routes) else {
            storageError = "This route could not be saved."
            return
        }
        let destination = fileURL
        Task.detached(priority: .utility) {
            do {
                try data.write(to: destination, options: .atomic)
            } catch {
                await MainActor.run { self.storageError = "This route could not be written to storage." }
            }
        }
    }
}
