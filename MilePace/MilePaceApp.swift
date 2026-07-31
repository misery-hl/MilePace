import SwiftUI

@main
struct MilePaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var runStore: RunStore
    @StateObject private var profileStore: ProfileStore
    @StateObject private var runTracker: RunTracker
    @StateObject private var goalStore = GoalStore()
    @StateObject private var routeStore = RouteStore()

    init() {
        let store = RunStore()
        let profiles = ProfileStore()
        _runStore = StateObject(wrappedValue: store)
        _profileStore = StateObject(wrappedValue: profiles)
        _runTracker = StateObject(wrappedValue: RunTracker(store: store, profileStore: profiles))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runStore)
                .environmentObject(profileStore)
                .environmentObject(runTracker)
                .environmentObject(goalStore)
                .environmentObject(routeStore)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                runTracker.refreshNow()
            }
        }
    }
}
