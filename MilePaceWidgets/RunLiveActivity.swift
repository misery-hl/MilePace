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
            LockScreenView(state: context.state, routeLine: context.attributes.routeLine)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.mint)
        } dynamicIsland: { context in
            DynamicIsland {
                // Everything lives in the bottom region, not spread across
                // leading, center, and trailing, and not in center alone. The
                // center region sits between the camera gutters and is not
                // guaranteed the island's full width, so a row placed there can
                // still be narrower than it looks and clip a label at the
                // rounded corners. The bottom region is always the island's
                // full width and always clear of the camera, so it is the only
                // region that reliably keeps three columns aligned on one
                // baseline with no clipping. The metrics sit above the
                // elevation/calories/goal accessory row, both inside the same
                // full-width container and padding.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 0) {
                            IslandMetric(title: "PACE", value: context.state.paceText, unit: "/mi", alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            IslandMetric(title: "TIME", value: context.state.elapsedText, unit: "", alignment: .center)
                                .frame(maxWidth: .infinity, alignment: .center)
                            IslandMetric(title: "DISTANCE", value: context.state.distanceText, unit: "mi", alignment: .trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        HStack {
                            Label(context.state.elevationText, systemImage: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let calories = context.state.caloriesText {
                                Label("\(calories) kcal", systemImage: "flame.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if context.state.isOffRoute {
                                Label(context.state.offRouteText ?? "Off route",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            } else if let goalDelta = context.state.goalDeltaText {
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
                    .padding(.horizontal, 16)
                }
            } compactLeading: {
                Image(systemName: context.state.isOffRoute ? "exclamationmark.triangle.fill"
                      : (context.state.isPaused ? "pause.fill" : "figure.run"))
                    .foregroundStyle(context.state.isOffRoute || context.state.isPaused ? .orange : .mint)
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

/// The Lock Screen presentation: pace largest, then distance and time, and a
/// route map with the runner's dot when a route is being followed.
private struct LockScreenView: View {
    let state: RunActivityAttributes.ContentState
    let routeLine: [RoutePoint]

    private var showsMap: Bool {
        routeLine.count >= 2
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(headerText, systemImage: headerIcon)
                        .font(.caption2.bold())
                        .foregroundStyle(headerColor)
                    Spacer()
                    if let goalName = state.goalName, !state.isOffRoute {
                        Text(goalName)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(state.paceText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("/mi")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let goalDelta = state.goalDeltaText, !state.isOffRoute {
                        Text(goalDelta)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle((state.goalDeltaSeconds ?? 0) <= 0 ? .mint : .orange)
                    }
                }

                HStack(spacing: 0) {
                    LockScreenMetric(title: "DISTANCE", value: state.distanceText, unit: "mi")
                    LockScreenMetric(title: "TIME", value: state.elapsedText, unit: "")
                    // Calories take the third slot when there is one, because a
                    // runner asked for them there. Climb keeps the slot only
                    // when there is no calorie figure and no map.
                    if let calories = state.caloriesText {
                        LockScreenMetric(title: "CAL", value: calories, unit: "kcal")
                    } else if !showsMap {
                        LockScreenMetric(title: "CLIMB", value: state.elevationText, unit: "")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsMap {
                RouteMiniMap(routeLine: routeLine, userPoint: state.userPoint, isOffRoute: state.isOffRoute)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottom) {
                        if let offRoute = state.offRouteText {
                            Text(offRoute)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.orange, in: Capsule())
                                .padding(.bottom, 4)
                        }
                    }
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }

    private var headerText: String {
        if state.isOffRoute { return "OFF ROUTE" }
        return state.isPaused ? "PAUSED" : "MILEPACE"
    }

    private var headerIcon: String {
        if state.isOffRoute { return "exclamationmark.triangle.fill" }
        return state.isPaused ? "pause.circle.fill" : "figure.run"
    }

    private var headerColor: Color {
        state.isOffRoute || state.isPaused ? .orange : .mint
    }
}

/// A schematic map of the followed route with the runner's dot, drawn with a
/// Canvas so it needs no MapKit — a Live Activity cannot host a real map. It
/// shows shape and relative position, which is what a glance needs: am I left
/// or right of the line, and how far. The frame grows to include the runner
/// even when they have strayed off the route, so the dot is always visible.
struct RouteMiniMap: View {
    let routeLine: [RoutePoint]
    let userPoint: RoutePoint?
    let isOffRoute: Bool

    var body: some View {
        Canvas { context, size in
            var points = routeLine
            if let userPoint { points.append(userPoint) }
            guard let bounds = RouteGeometry.bounds(of: points) else { return }

            let inset = 10.0
            let drawWidth = size.width - inset * 2
            let drawHeight = size.height - inset * 2
            let latSpan = max(bounds.latitudeSpan, 0.0001)
            let lonSpan = max(bounds.longitudeSpan, 0.0001)

            func project(_ p: RoutePoint) -> CGPoint {
                let x = (p.longitude - bounds.minLongitude) / lonSpan
                let y = (p.latitude - bounds.minLatitude) / latSpan
                return CGPoint(x: inset + x * drawWidth, y: inset + (1 - y) * drawHeight)
            }

            var path = Path()
            path.addLines(routeLine.map(project))
            context.stroke(path, with: .color(.mint),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if let start = routeLine.first {
                let p = project(start)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(.mint))
            }

            if let userPoint {
                let p = project(userPoint)
                let colour: Color = isOffRoute ? .orange : .white
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(.black))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                             with: .color(colour))
            }
        }
        .background(Color.white.opacity(0.06))
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
    /// How the stacked title and value line up, so the same component can read
    /// left, centre, or right depending on where it sits in the row.
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
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
