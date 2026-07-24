import ActivityKit
import Foundation

/// What the runner wants in the Dynamic Island's compact view.
///
/// The compact view is a few characters wide, so it holds one number. Which one
/// is a real preference: a hiker watches the clock, and a runner watches pace.
enum CompactMetric: String, Codable, CaseIterable, Identifiable, Equatable {
    case time
    case pace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: return "Total time"
        case .pace: return "Mile pace"
        }
    }
}

/// The live run, as shown on the Lock Screen and in the Dynamic Island.
///
/// This file is compiled into both the app and the widget extension, which are
/// separate processes. Everything the widget draws has to arrive through
/// `ContentState`; it cannot reach into `RunTracker`.
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var paceSeconds: Double?
        var distanceMeters: Double
        var elapsed: TimeInterval
        var elevationGainMeters: Double
        var isPaused: Bool
        var compactMetric: CompactMetric
        /// Set when a goal is being followed. Positive is behind the target.
        var goalName: String?
        var goalDeltaSeconds: Double?

        var distanceMiles: Double {
            distanceMeters / metersPerMile
        }

        var elevationGainFeet: Double {
            elevationGainMeters * 3.280839895
        }

        var paceText: String {
            guard let paceSeconds, paceSeconds > 0, paceSeconds.isFinite else { return "--:--" }
            let seconds = Int(paceSeconds.rounded())
            if seconds >= 3_600 {
                return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
            }
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }

        var elapsedText: String {
            guard elapsed.isFinite, elapsed >= 0 else { return "--:--" }
            let total = Int(elapsed.rounded(.down))
            let hours = total / 3_600
            let minutes = (total % 3_600) / 60
            let seconds = total % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%d:%02d", minutes, seconds)
        }

        var distanceText: String {
            String(format: "%.2f", distanceMiles)
        }

        var elevationText: String {
            String(format: "%.0f ft", elevationGainFeet)
        }

        /// The single figure the Dynamic Island shows when collapsed.
        var compactText: String {
            switch compactMetric {
            case .time: return elapsedText
            case .pace: return paceText
            }
        }

        var goalDeltaText: String? {
            guard let goalDeltaSeconds else { return nil }
            let seconds = Int(abs(goalDeltaSeconds).rounded())
            let value = seconds >= 3_600
                ? String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
            return goalDeltaSeconds <= 0 ? "\(value) ahead" : "\(value) behind"
        }
    }

    /// Fixed for the life of the activity. The start time lets the widget label
    /// the run without another update.
    var startedAt: Date
}
