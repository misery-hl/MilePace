import ActivityKit
import Foundation

/// Drives the Lock Screen and Dynamic Island activity for a live run.
///
/// iOS rate limits Live Activity updates, so this deliberately pushes far less
/// often than the running screen redraws. Sending on every GPS fix would waste
/// the budget and get later updates dropped, which is worse than a figure that
/// is a couple of seconds stale.
@MainActor
final class RunActivityController {
    private var activity: Activity<RunActivityAttributes>?
    private var lastPushedAt: Date?

    /// Minimum gap between updates. A pace that has moved by a second is not
    /// worth a push; a runner glancing down wants a number that is roughly now.
    private let minimumUpdateInterval: TimeInterval = 2

    /// Which figure the Dynamic Island shows when collapsed. Stored so the
    /// choice survives between runs.
    var compactMetric: CompactMetric {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.compactMetricKey) ?? ""
            return CompactMetric(rawValue: raw) ?? .time
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.compactMetricKey)
        }
    }

    private static let compactMetricKey = "MilePace.compactMetric"

    var isRunning: Bool {
        activity != nil
    }

    func start(startedAt: Date, state: RunActivityAttributes.ContentState) {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        do {
            activity = try Activity.request(
                attributes: RunActivityAttributes(startedAt: startedAt),
                content: ActivityContent(state: state, staleDate: nil)
            )
            lastPushedAt = Date()
        } catch {
            // A refused activity is not worth interrupting a run over. The app
            // itself keeps working; only the Lock Screen view is missing.
            activity = nil
        }
    }

    /// Pushes a new state, unless one went out moments ago.
    ///
    /// `force` bypasses the interval for changes a runner would notice at once,
    /// such as pausing.
    func update(_ state: RunActivityAttributes.ContentState, force: Bool = false) {
        guard let activity else { return }

        if !force, let lastPushedAt,
           Date().timeIntervalSince(lastPushedAt) < minimumUpdateInterval {
            return
        }
        lastPushedAt = Date()

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(finalState: RunActivityAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        lastPushedAt = nil

        Task {
            // Dismiss immediately. A finished run belongs in the app, not on
            // the Lock Screen for hours afterwards.
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
