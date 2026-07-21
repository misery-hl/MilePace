import SwiftUI

@main
struct MilePaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var runStore: RunStore
    @StateObject private var runTracker: RunTracker

    init() {
        let store = RunStore()
        _runStore = StateObject(wrappedValue: store)
        _runTracker = StateObject(wrappedValue: RunTracker(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runStore)
                .environmentObject(runTracker)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                runTracker.refreshNow()
            }
        }
    }
}
