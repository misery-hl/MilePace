import Foundation

let metersPerMile = 1_609.344

struct MileSplit: Codable, Equatable, Identifiable {
    let mile: Int
    let duration: TimeInterval

    var id: Int { mile }
}

struct RunRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let activeDuration: TimeInterval
    let mileSplits: [MileSplit]

    var distanceMiles: Double {
        distanceMeters / metersPerMile
    }

    var averagePace: TimeInterval? {
        guard distanceMeters >= 30 else { return nil }
        return activeDuration / distanceMeters * metersPerMile
    }

    var fastestMile: MileSplit? {
        mileSplits.min(by: { $0.duration < $1.duration })
    }
}

enum RunPhase: Equatable {
    case idle
    case running
    case paused
    case finished
}

extension TimeInterval {
    var clockText: String {
        guard isFinite, self >= 0 else { return "--:--" }
        let totalSeconds = Int(self.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var paceText: String {
        guard isFinite, self > 0, self < 3_600 else { return "--:--" }
        let roundedSeconds = Int(rounded())
        return String(format: "%d:%02d", roundedSeconds / 60, roundedSeconds % 60)
    }
}
