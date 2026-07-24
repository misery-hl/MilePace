import ActivityKit
import SwiftUI
import WidgetKit

/// The live run on the Lock Screen and in the Dynamic Island.
///
/// Runs in a separate process from the app, so everything drawn here arrives
/// through `RunActivityAttributes.ContentState`.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.mint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandMetric(title: "PACE", value: context.state.paceText, unit: "/mi")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandMetric(title: "DISTANCE", value: context.state.distanceText, unit: "mi")
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandMetric(title: "TIME", value: context.state.elapsedText, unit: "")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.state.elevationText, systemImage: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let goalDelta = context.state.goalDeltaText {
                            Text(goalDelta)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    (context.state.goalDeltaSeconds ?? 0) <= 0 ? .mint : .orange
                                )
                        } else if context.state.isPaused {
                            Text("Paused")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                    .foregroundStyle(context.state.isPaused ? .orange : .mint)
            } compactTrailing: {
                // One figure only: this is a few characters wide. Which figure
                // is the runner's choice.
                Text(context.state.compactText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.mint)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                    .foregroundStyle(context.state.isPaused ? .orange : .mint)
            }
            .keylineTint(.mint)
        }
    }
}

/// The Lock Screen presentation: pace largest, then distance and time.
private struct LockScreenView: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(state.isPaused ? "PAUSED" : "MILEPACE",
                      systemImage: state.isPaused ? "pause.circle.fill" : "figure.run")
                    .font(.caption2.bold())
                    .foregroundStyle(state.isPaused ? .orange : .mint)
                Spacer()
                if let goalName = state.goalName {
                    Text(goalName)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.paceText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("/mi")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let goalDelta = state.goalDeltaText {
                    Text(goalDelta)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle((state.goalDeltaSeconds ?? 0) <= 0 ? .mint : .orange)
                }
            }

            HStack(spacing: 0) {
                LockScreenMetric(title: "DISTANCE", value: state.distanceText, unit: "mi")
                LockScreenMetric(title: "TIME", value: state.elapsedText, unit: "")
                LockScreenMetric(title: "CLIMB", value: state.elevationText, unit: "")
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

private struct LockScreenMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IslandMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
