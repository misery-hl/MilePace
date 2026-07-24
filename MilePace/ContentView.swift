import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var tracker: RunTracker
    @EnvironmentObject private var store: RunStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch tracker.phase {
                case .idle:
                    StartView()
                case .running, .paused:
                    RunDashboardView()
                case .finished:
                    RunSummaryView(record: tracker.lastRun)
                }
            }
            .tint(.mint)
            // A brief signal drop is not a permission problem. One title for
            // both made a passing glitch read as though access had been lost.
            .alert(tracker.authorizationStatus == .denied
                   ? "MilePace needs GPS"
                   : "GPS signal problem",
                   isPresented: Binding(
                get: { tracker.errorMessage != nil },
                set: { if !$0 { tracker.errorMessage = nil } }
            )) {
                if tracker.authorizationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(tracker.errorMessage ?? "")
            }
            .alert("Run history problem", isPresented: Binding(
                get: { store.storageError != nil },
                set: { if !$0 { store.storageError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.storageError ?? "")
            }
        }
    }
}

private struct StartView: View {
    @EnvironmentObject private var tracker: RunTracker
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 36)

                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(.mint)

                VStack(spacing: 8) {
                    Text("MilePace")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Your pace. Your miles. No subscription.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: tracker.start) {
                    Label("Start Run", systemImage: "location.fill")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.mint, in: RoundedRectangle(cornerRadius: 22))
                        .foregroundStyle(.black)
                }
                .accessibilityHint("Starts GPS tracking")

                if tracker.usesReducedAccuracy {
                    Label("Precise Location is off, so pace may be less accurate.", systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                GoalsSection()

                CompactMetricPicker()

                Label("Runs stay on this iPhone", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !store.visibleRecords.isEmpty {
                    recentRuns
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT RUNS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1.2)

            ForEach(store.visibleRecords.prefix(5)) { record in
                RunRowLink(record: record)
            }

            if store.visibleRecords.count > 5 || !store.archivedRecords.isEmpty {
                NavigationLink {
                    AllRunsScreen()
                } label: {
                    HStack {
                        Text("See all \(store.visibleRecords.count) runs")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }
}

/// A run row with its long-press actions.
///
/// Deleting is guarded and archiving is not, because archiving is reversible
/// and deleting is not: the history is local-first with no backup.
private struct RunRowLink: View {
    let record: RunRecord

    @EnvironmentObject private var store: RunStore
    @EnvironmentObject private var goalStore: GoalStore
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationLink {
            SavedRunScreen(record: record)
        } label: {
            RunRow(record: record)
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(goalStore.activeGoals) { goal in
                if goalStore.contains(runID: record.id, in: goal) {
                    Button {
                        goalStore.detach(runID: record.id, from: goal)
                    } label: {
                        Label("Remove from \(goal.displayName)", systemImage: "minus.circle")
                    }
                } else {
                    Button {
                        goalStore.attach(runID: record.id, to: goal)
                    } label: {
                        Label("Add to \(goal.displayName)", systemImage: "target")
                    }
                }
            }

            Divider()

            Button {
                store.setArchived(!record.isArchived, for: record)
            } label: {
                Label(record.isArchived ? "Unarchive" : "Archive",
                      systemImage: record.isArchived ? "tray.and.arrow.up" : "archivebox")
            }

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete this run?", isPresented: $isConfirmingDelete) {
            Button("Delete run", role: .destructive) {
                // Detach first, so no goal is left counting a run that is gone.
                goalStore.detachFromAllGoals(runID: record.id)
                store.delete(record)
            }
            Button("Keep run", role: .cancel) {}
        } message: {
            Text(deleteWarning)
        }
    }

    private var deleteWarning: String {
        let distance = String(format: "%.2f mi", record.distanceMiles)
        let goals = goalStore.goalsContaining(runID: record.id)
        var message = "This deletes your \(distance) run from \(record.startedAt.formatted(date: .abbreviated, time: .shortened)). "

        if !goals.isEmpty {
            let names = goals.map(\.displayName).joined(separator: ", ")
            message += "It also stops counting towards \(names). "
        }
        return message + "This cannot be undone. Archive it instead to hide it and keep it."
    }
}

/// A saved run opened from the history.
///
/// `RunDetailView` is a plain stack. The summary screen supplies its own
/// scrolling, but a pushed screen does not inherit it, so the route map and
/// everything under it used to be clipped off the bottom with no way to reach
/// the Share button. This screen also carries the goal controls, so a run can
/// join a goal that did not exist when the run was recorded.
private struct SavedRunScreen: View {
    let record: RunRecord

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    GoalApplyView(record: record)
                    RunDetailView(record: record)
                }
                .padding(20)
            }
        }
    }
}

private struct AllRunsScreen: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.visibleRecords) { record in
                        RunRowLink(record: record)
                    }

                    if !store.archivedRecords.isEmpty {
                        NavigationLink {
                            ArchivedRunsScreen()
                        } label: {
                            HStack {
                                Label("Archived", systemImage: "archivebox")
                                Spacer()
                                Text("\(store.archivedRecords.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("All runs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Archived runs, kept out of the way but never lost.
private struct ArchivedRunsScreen: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.archivedRecords.isEmpty {
                        Text("No archived runs.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Archived runs stay out of your lists, and still count towards any goal they were added to.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(store.archivedRecords) { record in
                            RunRowLink(record: record)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RunDashboardView: View {
    @EnvironmentObject private var tracker: RunTracker
    @EnvironmentObject private var goalStore: GoalStore

    private var primaryPace: TimeInterval? {
        tracker.currentMilePace ?? tracker.rollingPace ?? tracker.averagePace
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Label(
                    tracker.phase == .paused ? "PAUSED" : "GPS ACTIVE",
                    systemImage: tracker.phase == .paused ? "pause.circle.fill" : "location.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(tracker.phase == .paused ? .orange : .mint)
                Spacer()
                Text("MILE \(tracker.currentMileNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(spacing: 4) {
                Text("CURRENT MILE PACE")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(primaryPace?.paceText ?? "--:--")
                        .font(.system(size: 78, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    Text("/mi")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }
                if primaryPace == nil {
                    Text("Pace settles after the first 30 meters")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current mile pace \(primaryPace?.paceText ?? "not available") per mile")

            VStack(spacing: 8) {
                ProgressView(value: tracker.currentMileProgress)
                    .tint(.mint)
                    .scaleEffect(x: 1, y: 2.2)
                HStack {
                    Text(String(format: "%.2f mi", tracker.currentMileProgress))
                    Spacer()
                    Text("1.00 mi")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                MetricCard(title: "DISTANCE", value: String(format: "%.2f", tracker.distanceMiles), unit: "mi")
                MetricCard(title: "TIME", value: tracker.elapsed.clockText, unit: "active")
                MetricCard(title: "LIVE PACE", value: tracker.rollingPace?.paceText ?? "--:--", unit: "/mi")
            }

            if let warning = tracker.trackingWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Tracking problem. \(warning)")
            }

            if let goal = goalStore.trackedGoal {
                LiveGoalRow(
                    goal: goal,
                    distanceMeters: tracker.distanceMeters,
                    elapsed: tracker.elapsed
                )
            }

            if let lastSplit = tracker.mileSplits.last {
                HStack {
                    Label("Mile \(lastSplit.mile)", systemImage: "flag.checkered")
                    Spacer()
                    Text(lastSplit.duration.paceText)
                        .font(.title3.bold().monospacedDigit())
                }
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }

            Spacer()

            HStack(spacing: 14) {
                Button(action: tracker.phase == .running ? tracker.pause : tracker.resume) {
                    Label(tracker.phase == .running ? "Pause" : "Resume",
                          systemImage: tracker.phase == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                }

                Button(role: .destructive, action: tracker.finish) {
                    Label("Finish", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.white)
                }
            }
            .font(.headline)
        }
        .padding(20)
        .onAppear { publishGoalContext() }
        .onChange(of: goalStore.trackedGoal?.id) { _, _ in publishGoalContext() }
    }

    /// Hands the followed goal to the tracker, so the Lock Screen can show the
    /// same ahead or behind figure this screen does.
    private func publishGoalContext() {
        if let goal = goalStore.trackedGoal {
            tracker.goalContext = (goal.displayName, goal.targetDuration, goal.distanceMeters)
        } else {
            tracker.goalContext = nil
        }
    }
}

private struct RunSummaryView: View {
    @EnvironmentObject private var tracker: RunTracker
    let record: RunRecord?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(.mint)
                Text("Run saved")
                    .font(.largeTitle.bold())

                if let record {
                    GoalApplyView(record: record)
                    RunDetailView(record: record, showsDate: false)
                }

                Button("Done", action: tracker.dismissSummary)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.mint, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.black)
            }
            .padding(20)
        }
    }
}

private struct RunDetailView: View {
    let record: RunRecord
    var showsDate = true

    var body: some View {
        VStack(spacing: 20) {
            if showsDate {
                Text(record.startedAt.formatted(date: .complete, time: .shortened))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if record.hasRoute {
                RouteMapView(record: record)
            }

            HStack(spacing: 10) {
                MetricCard(title: "DISTANCE", value: String(format: "%.2f", record.distanceMiles), unit: "mi")
                MetricCard(title: "TIME", value: record.activeDuration.clockText, unit: "active")
                MetricCard(title: "AVG PACE", value: record.averagePace?.paceText ?? "--:--", unit: "/mi")
            }

            if record.hasMeaningfulElevation {
                HStack {
                    Label("Elevation gain", systemImage: "arrow.up.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f ft", record.elevationGainFeet))
                        .font(.headline.monospacedDigit())
                }
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            if record.mileSplits.isEmpty {
                Text("Complete a mile to record your first split.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MILE SPLITS")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    ForEach(record.mileSplits) { split in
                        HStack {
                            Text("Mile \(split.mile)")
                            Spacer()
                            Text(split.duration.paceText)
                                .font(.headline.monospacedDigit())
                        }
                        .padding()
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            RunShareButton(record: record)
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Chooses the single figure the Dynamic Island shows while collapsed.
private struct CompactMetricPicker: View {
    @EnvironmentObject private var tracker: RunTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DYNAMIC ISLAND")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1.2)

            Picker("Dynamic Island shows", selection: Binding(
                get: { tracker.compactMetric },
                set: { tracker.compactMetric = $0 }
            )) {
                ForEach(CompactMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            Text("The collapsed island fits one figure. The Lock Screen shows pace, distance, time, and climb.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GoalsSection: View {
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var store: RunStore

    @State private var editingGoal: RunGoal?
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GOALS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Spacer()
                if !goalStore.activeGoals.isEmpty {
                    Button { isCreating = true } label: {
                        Label("New", systemImage: "plus")
                            .font(.caption.bold())
                    }
                }
            }

            if goalStore.activeGoals.isEmpty {
                Button { isCreating = true } label: {
                    Label("Set a goal", systemImage: "target")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                }
                Text("Choose a distance and a target. Add runs to a goal to see how close you are.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(goalStore.activeGoals) { goal in
                    GoalCard(
                        goal: goal,
                        records: store.records,
                        isTracked: goalStore.trackedGoal?.id == goal.id,
                        onSelect: { goalStore.trackedGoalID = goal.id },
                        onEdit: { editingGoal = goal }
                    )
                }

                if goalStore.activeGoals.count > 1 {
                    Label(
                        "Tap a goal to follow it while you run.",
                        systemImage: "location.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isCreating) { GoalEditorView(goal: nil) }
        .sheet(item: $editingGoal) { goal in GoalEditorView(goal: goal) }
    }
}

private struct GoalCard: View {
    let goal: RunGoal
    let records: [RunRecord]
    let isTracked: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    private var attempts: [GoalAttempt] {
        GoalEvaluation.attempts(for: goal, in: records)
    }

    private var best: GoalAttempt? {
        attempts.min { $0.goalDistanceDuration < $1.goalDistanceDuration }
    }

    private var gap: TimeInterval? {
        best.map { $0.goalDistanceDuration - goal.targetDuration }
    }

    /// A sprint has no useful pace per mile, so the card names the kind instead
    /// of printing a number nobody races to.
    private var subtitle: String {
        // A named goal still has to say what it is, so the distance moves here.
        let pace = goal.showsPace ? "Target pace \(goal.targetPace.paceText) /mi" : "Sprint target"
        return goal.name.isEmpty ? pace : "\(goal.distanceText) · \(pace)"
    }

    private var bestLabel: String {
        best?.isDirectAttempt == false ? "BEST, ESTIMATED" : "BEST SO FAR"
    }

    private var bestLabelColor: Color {
        best?.isDirectAttempt == false ? .orange : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // A name when there is one, otherwise the distance. The target
                // time is already shown on the right, so repeating it here
                // would read as noise.
                Text(goal.name.isEmpty ? goal.distanceText : goal.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                if isTracked {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.mint)
                        .accessibilityLabel("Followed while running")
                }
                Spacer()
                Text(goal.targetDuration.clockText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.mint)
            }

            HStack {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                // A separate control, so tapping the card can mean "follow this
                // one" without the edit screen appearing by accident.
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(goal.displayName)")
            }

            if let best, let gap {
                Divider().overlay(.white.opacity(0.15))

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        // A best that came from a scaled run is an estimate,
                        // and the card is where it is read from then on. The
                        // summary caveats it once; without this the number
                        // reads as measured fact forever after.
                        // A best that came from a scaled run is an estimate,
                        // and the card is where it is read from then on. The
                        // summary caveats it once; without this the number
                        // reads as measured fact forever after.
                        Text(bestLabel)
                            .font(.caption2.bold())
                            .foregroundStyle(bestLabelColor)
                        Text(best.goalDistanceDuration.clockText)
                            .font(.headline.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(gap <= 0 ? "RESULT" : "TO GO")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(gap <= 0 ? "Reached" : gap.differenceText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(gap <= 0 ? .mint : .orange)
                    }
                }

                Text(attempts.count == 1 ? "1 run added" : "\(attempts.count) runs added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No runs added yet. Finish a run, then add it to this goal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.white.opacity(isTracked ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isTracked ? Color.mint.opacity(0.5) : .clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onSelect)
        // Without these the card is a plain stack: VoiceOver reads each figure
        // separately and never says the card is the control that chooses which
        // goal the running screen follows.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(isTracked
                           ? "Already followed while running"
                           : "Double tap to follow this goal while running")
        .accessibilityAction(named: "Edit goal", onEdit)
    }

    private var accessibilitySummary: String {
        var parts = [goal.name.isEmpty ? goal.title : "\(goal.name), \(goal.title)"]
        if let best {
            parts.append("best so far \(best.goalDistanceDuration.clockText)")
        } else {
            parts.append("no runs added yet")
        }
        if isTracked { parts.append("followed while running") }
        return parts.joined(separator: ", ")
    }
}

private struct GoalEditorView: View {
    /// Nil creates a goal. A value edits that goal.
    let goal: RunGoal?

    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var store: RunStore
    @Environment(\.dismiss) private var dismiss

    @State private var distanceMeters: Double
    @State private var unit: DistanceUnit
    @State private var kind: GoalKind
    @State private var mode: EntryMode
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var name: String
    @State private var isConfirmingDelete = false
    @State private var isSaving = false

    /// A two-mile target is natural to state as a total time. A half marathon
    /// is natural to state as a pace, and nobody wants to count 111 minutes on
    /// a wheel. Both describe the same goal, so the editor accepts either.
    enum EntryMode: String, CaseIterable, Identifiable {
        case totalTime = "Total time"
        case pace = "Pace per mile"

        var id: String { rawValue }
    }

    init(goal: RunGoal?) {
        self.goal = goal

        let meters = goal?.distanceMeters ?? (2 * metersPerMile)
        let startingUnit = goal?.distanceUnit ?? .miles
        let miles = meters / metersPerMile
        let total = goal?.targetDuration ?? 720
        // Longer runs open in pace mode, because that is how runners say them.
        // A sprint is always a total time, so it never opens in pace mode.
        let startsInPace = startingUnit.kind.allowsPaceEntry && miles >= 6
        let shown = startsInPace ? total / miles : total

        // Round once, then split. Truncating the minutes while rounding the
        // seconds loses a whole minute whenever the seconds carry: 359.5 s
        // became 5 min 00 s rather than 6 min 00 s, silently shrinking the goal.
        let wholeSeconds = Int(shown.rounded())

        _name = State(initialValue: goal?.name ?? "")
        _distanceMeters = State(initialValue: startingUnit.sensibleOption(forMeters: meters))
        _unit = State(initialValue: startingUnit)
        _kind = State(initialValue: startingUnit.kind)
        _mode = State(initialValue: startsInPace ? .pace : .totalTime)
        _minutes = State(initialValue: wholeSeconds / 60)
        _seconds = State(initialValue: wholeSeconds % 60)
    }

    private var miles: Double {
        distanceMeters / metersPerMile
    }

    private var enteredSeconds: TimeInterval {
        TimeInterval(minutes * 60 + seconds)
    }

    private var targetDuration: TimeInterval {
        // A sprint has no pace entry, so its wheels are always a total time.
        guard kind.allowsPaceEntry, mode == .pace else { return enteredSeconds }
        return enteredSeconds * miles
    }

    private var targetPace: TimeInterval {
        guard miles > 0 else { return 0 }
        return targetDuration / miles
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The goal as currently entered, so the editor can judge it before saving.
    private var candidate: RunGoal {
        RunGoal(distanceMeters: distanceMeters, targetDuration: targetDuration, distanceUnit: unit)
    }

    private var summaryHeadline: String {
        // A sprint is stated as a time. Showing it a pace per mile would be
        // true and useless: a 5 second 40 yard dash is a 3:40 mile pace.
        guard kind.allowsPaceEntry else {
            return unit.text(forMeters: distanceMeters) + " in " + targetDuration.clockText
        }
        return mode == .pace
            ? "Total time \(targetDuration.clockText)"
            : "Target pace \(targetPace.paceText) /mi"
    }

    private var attachedRunCount: Int {
        goal.map { GoalEvaluation.attempts(for: $0, in: store.records).count } ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    TextField("Name (optional)", text: $name)
                        .textInputAutocapitalization(.words)
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .submitLabel(.done)

                    Picker("Kind", selection: $kind) {
                        ForEach(GoalKind.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Distance unit", selection: $unit) {
                        // Only the units that belong to this kind. A sprint in
                        // miles and a marathon in yards are both nonsense.
                        ForEach(kind.units) { option in
                            Text(option.shortName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Distance", selection: $distanceMeters) {
                        ForEach(unit.options, id: \.self) { option in
                            Text(unit.text(forMeters: option)).tag(option)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)

                    if kind.allowsPaceEntry {
                        Picker("Enter as", selection: $mode) {
                            ForEach(EntryMode.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 4) {
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<240, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 120)
                        Text("min").foregroundStyle(.secondary)

                        Picker("Seconds", selection: $seconds) {
                            ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 120)
                        Text("sec").foregroundStyle(.secondary)
                    }

                    // Always show the value the runner did not type, so the
                    // whole goal is visible however it was entered.
                    if targetDuration > 0 {
                        VStack(spacing: 4) {
                            Text(summaryHeadline)
                                .font(.headline)
                                .foregroundStyle(.mint)
                            if kind.allowsPaceEntry {
                                Text(unit.text(forMeters: distanceMeters) + " in " + targetDuration.clockText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let reason = candidate.implausibleReason, targetDuration > 0 {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if goal != nil {
                        Divider().overlay(.white.opacity(0.15)).padding(.top, 4)
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete goal", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!candidate.isPlausible || isSaving)
                }
            }
            .onChange(of: mode) { previous, _ in
                convertEnteredValue(from: previous)
            }
            .onChange(of: kind) { _, newKind in
                // Move to a unit that belongs to the new kind, and drop pace
                // entry, which only describes a run.
                if !newKind.units.contains(unit) {
                    unit = newKind.units[0]
                }
                if !newKind.allowsPaceEntry, mode == .pace {
                    convertEnteredValue(from: .pace)
                    mode = .totalTime
                }
            }
            .onChange(of: unit) { _, newUnit in
                // Keep the same goal when the distance fits the new unit, and
                // fall back to a sensible distance when it does not. Snapping to
                // the nearest option alone parked a 5 km goal at 1,600 m, the
                // far end of the sprint wheel.
                distanceMeters = newUnit.sensibleOption(forMeters: distanceMeters)
            }
            .alert("Delete this goal?", isPresented: $isConfirmingDelete) {
                Button("Delete goal", role: .destructive) {
                    if let goal { goalStore.delete(goal) }
                    dismiss()
                }
                Button("Keep goal", role: .cancel) {}
            } message: {
                Text(deleteWarning)
            }
        }
    }

    /// Says exactly what is lost, and what is not. Losing a goal by a mistaken
    /// tap should never leave the runner guessing about their run history.
    private var deleteWarning: String {
        guard let goal else { return "" }
        if attachedRunCount == 0 {
            return "This removes \(goal.displayName). You have not added any runs to it."
        }
        let runs = attachedRunCount == 1 ? "1 run" : "\(attachedRunCount) runs"
        return "This removes \(goal.displayName) and its progress, including the \(runs) you added to it. "
            + "The runs themselves stay in your history. This cannot be undone."
    }

    /// Keeps the goal the same when the runner switches how they state it.
    private func convertEnteredValue(from previous: EntryMode) {
        guard miles > 0 else { return }
        let total = previous == .pace ? enteredSeconds * miles : enteredSeconds
        let shown = mode == .pace ? total / miles : total
        // Round once, then split. See the note in init.
        let wholeSeconds = Int(shown.rounded())
        minutes = wholeSeconds / 60
        seconds = wholeSeconds % 60
    }

    private func save() {
        // A second tap during the dismiss animation would otherwise mint a
        // second goal with a new identifier and identical values.
        guard !isSaving else { return }
        isSaving = true

        if var existing = goal {
            // Editing keeps runIDs, so correcting a target never costs history.
            existing.name = trimmedName
            existing.distanceMeters = distanceMeters
            existing.targetDuration = targetDuration
            existing.distanceUnit = unit
            goalStore.update(existing)
        } else {
            let created = RunGoal(
                name: trimmedName,
                distanceMeters: distanceMeters,
                targetDuration: targetDuration,
                distanceUnit: unit
            )
            goalStore.add(created)
            // Only adopt the new goal if the runner was not already following
            // one. Creating a goal should not quietly change what the running
            // screen shows.
            if goalStore.trackedGoalID == nil {
                goalStore.trackedGoalID = created.id
            }
        }
        dismiss()
    }
}

private struct LiveGoalRow: View {
    let goal: RunGoal
    let distanceMeters: Double
    let elapsed: TimeInterval

    private var projection: TimeInterval? {
        PacePrediction.liveProjection(distanceMeters: distanceMeters, elapsed: elapsed, goal: goal)
    }

    private var delta: TimeInterval? {
        projection.map { $0 - goal.targetDuration }
    }

    private var hasPassedGoal: Bool {
        PacePrediction.hasPassedGoalDistance(distanceMeters: distanceMeters, goal: goal)
    }

    private var detailText: String {
        if hasPassedGoal { return "Goal distance is behind you" }
        return projection.map { "Projected \($0.clockText)" } ?? "Projection settles shortly"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.displayName.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(delta.map { $0 <= 0 ? "AHEAD BY" : "BEHIND BY" } ?? "TARGET")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(delta?.differenceText ?? goal.targetDuration.clockText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(deltaColor)
            }
        }
        .padding()
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var deltaColor: Color {
        guard let delta else { return .secondary }
        return delta <= 0 ? .mint : .orange
    }
}

private struct GoalApplyView: View {
    let record: RunRecord

    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var store: RunStore

    var body: some View {
        if !goalStore.activeGoals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("GOALS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                // Every goal is offered. A run can count towards more than one,
                // and only the runner knows which ones it was meant for.
                ForEach(goalStore.activeGoals) { goal in
                    if goalStore.contains(runID: record.id, in: goal) {
                        if let current = goalStore.goal(withID: goal.id),
                           let outcome = GoalEvaluation.outcome(
                               forRunID: record.id, goal: current, records: store.records
                           ) {
                            GoalOutcomeBlurb(
                                outcome: outcome,
                                attempts: GoalEvaluation.attempts(for: current, in: store.records)
                            )
                        } else {
                            // The run is attached, but carries no usable
                            // distance or time, so no comparison exists. Saying
                            // so beats re-offering a button that does nothing.
                            Label(
                                "This run is too short to count towards \(goal.displayName).",
                                systemImage: "exclamationmark.circle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        Button {
                            goalStore.attach(runID: record.id, to: goal)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "target")
                                Text("Add to \(goal.displayName)")
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .frame(maxWidth: .infinity)
                            .background(.mint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.mint)
                        }
                        .accessibilityHint("Counts this run towards the goal and shows how close you were")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The summary shown once a run joins a goal: the result against the target,
/// then the movement against the previous run and the best run before it.
private struct GoalOutcomeBlurb: View {
    let outcome: GoalOutcome
    let attempts: [GoalAttempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // A personal best is good news even when the target is still
                // ahead, so it does not get the warning colour.
                Image(systemName: outcome.reachedTarget ? "checkmark.seal.fill" : "target")
                    .foregroundStyle(isGoodNews ? .mint : .orange)
                Text(headline)
                    .font(.headline)
            }

            Text(resultLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(.white.opacity(0.15))

            Text(comparisonLine)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if let progressLine {
                Text(progressLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !outcome.attempt.isDirectAttempt {
                Text(estimateNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var isGoodNews: Bool {
        outcome.reachedTarget || (outcome.isPersonalBest && !outcome.isFirstAttempt)
    }

    private var headline: String {
        if outcome.reachedTarget { return "Goal reached" }
        if outcome.isPersonalBest && !outcome.isFirstAttempt { return "Your best yet" }
        return "Added to \(outcome.goal.displayName)"
    }

    private var resultLine: String {
        let distance = String(format: "%.2f mi", outcome.attempt.distanceMeters / metersPerMile)
        let actual = outcome.attempt.duration.clockText

        if outcome.attempt.isDirectAttempt {
            return "You ran \(distance) in \(actual)."
        }
        let equivalent = outcome.attempt.goalDistanceDuration.clockText
        return "You ran \(distance) in \(actual). That is worth about \(equivalent) for \(outcome.goal.distanceText)."
    }

    private var comparisonLine: String {
        let target = outcome.goal.targetDuration.clockText
        let gap = outcome.deltaToTarget.differenceText

        if outcome.deltaToTarget == 0 {
            return "That matches your \(target) target exactly."
        }

        if outcome.reachedTarget {
            return "That beats your \(target) target by \(gap)."
        }

        var line = "That is \(gap) off your \(target) target."

        if outcome.isFirstAttempt {
            return line + " This is your first run for this goal."
        }

        if let toPrevious = outcome.deltaToPrevious {
            if toPrevious < 0 {
                line += " You took \(toPrevious.differenceText) off your last run."
            } else if toPrevious > 0 {
                line += " That is \(toPrevious.differenceText) slower than your last run."
            } else {
                line += " That matches your last run."
            }
        }

        if outcome.isPersonalBest {
            line += " It is also your best run for this goal."
        } else if let toBest = outcome.deltaToBestBefore, let best = outcome.bestBefore {
            line += " Your best is still \(best.goalDistanceDuration.clockText), by \(toBest.differenceText)."
        }

        return line
    }

    /// Progress is measured against the runner's own first attempt. MilePace has
    /// no population data and does not need any: the useful question is whether
    /// this runner is closing their own gap.
    private var progressLine: String? {
        guard attempts.count >= 2,
              let fraction = outcome.progressFraction(firstAttempt: attempts.first),
              fraction > 0 else { return nil }
        let percent = Int((fraction * 100).rounded())
        return "You have closed \(percent)% of the gap since your first run for this goal."
    }

    private var estimateNote: String {
        // Riegel was fitted on races from about 1500 m upwards. Scaling a
        // longer run down to a sprint is outside the formula entirely, so say
        // so plainly rather than implying the estimate is merely approximate.
        if outcome.goal.kind == .sprint {
            return "This run was not \(outcome.goal.distanceText). A sprint cannot be estimated from a longer run, so time a real one to measure this goal."
        }

        let base = "This run was not \(outcome.goal.distanceText), so the comparison uses Riegel's formula to estimate the equivalent time."
        return outcome.attempt.isDependable
            ? base
            : base + " The distance was far from the goal, so treat it as a rough guide."
    }
}

private struct RouteMapView: View {
    let record: RunRecord

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
            ForEach(Array(record.routeSegments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.coordinate))
                    .stroke(
                        .mint,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }

            if let start = record.trackPoints.first {
                Annotation("Start", coordinate: start.coordinate) {
                    RouteEndpoint(fill: .mint)
                }
                .annotationTitles(.hidden)
            }

            if let end = record.trackPoints.last {
                Annotation("Finish", coordinate: end.coordinate) {
                    RouteEndpoint(fill: .white)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel("Map of your run route")
    }

    /// Frames the whole route with a margin, and keeps a floor on the span so a
    /// very short run does not zoom in to a meaningless level of detail.
    private var region: MKCoordinateRegion {
        guard let bounds = record.routeBounds else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: bounds.centerLatitude,
                longitude: bounds.centerLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(bounds.latitudeSpan * 1.4, 0.0025),
                longitudeDelta: max(bounds.longitudeSpan * 1.4, 0.0025)
            )
        )
    }
}

private struct RouteEndpoint: View {
    let fill: Color

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 16, height: 16)
            .overlay {
                Circle().strokeBorder(.black.opacity(0.75), lineWidth: 3)
            }
    }
}

private extension TrackPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct RunShareButton: View {
    let record: RunRecord

    @State private var shareItem: ShareItem?
    @State private var renderFailed = false

    var body: some View {
        Button {
            shareRun()
        } label: {
            Label("Share Run", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.black)
        }
        .accessibilityHint("Creates a MilePace summary image and opens the iOS share sheet")
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.image, item.caption])
        }
        .alert("Couldn’t create share image", isPresented: $renderFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try sharing the run again.")
        }
    }

    @MainActor
    private func shareRun() {
        let card = RunShareCard(record: record)
            .frame(width: 1_080, height: 1_350)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.isOpaque = true

        guard let image = renderer.uiImage else {
            renderFailed = true
            return
        }

        let distance = String(format: "%.2f", record.distanceMiles)
        let pace = record.averagePace?.paceText ?? "--:--"
        let caption = "I ran \(distance) miles in \(record.activeDuration.clockText) at \(pace)/mi with MilePace — a free, open-source running app. https://github.com/misery-hl/MilePace"

        shareItem = ShareItem(image: image, caption: caption)
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let caption: String
}

private struct RunShareCard: View {
    let record: RunRecord

    private var completedMilesText: String {
        let count = record.mileSplits.count
        return count == 1 ? "1 completed mile" : "\(count) completed miles"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.065, blue: 0.050),
                    Color(red: 0.025, green: 0.15, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.mint.opacity(0.12))
                .frame(width: 760, height: 760)
                .offset(x: 420, y: -520)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 24) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 112, height: 112)
                        .background(.mint, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MilePace")
                            .font(.system(size: 62, weight: .bold, design: .rounded))
                        Text("RUN COMPLETE")
                            .font(.system(size: 27, weight: .bold))
                            .tracking(5)
                            .foregroundStyle(.mint)
                    }
                }

                Spacer()

                Text(String(format: "%.2f", record.distanceMiles))
                    .font(.system(size: 224, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text("MILES")
                    .font(.system(size: 42, weight: .bold))
                    .tracking(10)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    ShareMetric(
                        title: "ACTIVE TIME",
                        value: record.activeDuration.clockText,
                        unit: ""
                    )
                    ShareMetric(
                        title: "AVG PACE",
                        value: record.averagePace?.paceText ?? "--:--",
                        unit: "/mi"
                    )
                    ShareMetric(
                        title: "FASTEST MILE",
                        value: record.fastestMile?.duration.paceText ?? "--:--",
                        unit: record.fastestMile == nil ? "" : "/mi"
                    )
                }
                .padding(.top, 54)

                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(record.startedAt.formatted(date: .long, time: .omitted))
                            .font(.system(size: 31, weight: .semibold))
                        Text(completedMilesText)
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Text("NO SUBSCRIPTION")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.mint)
                        Text("github.com/misery-hl/MilePace")
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(82)
        }
        .clipped()
    }
}

private struct ShareMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 55, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct RunRow: View {
    let record: RunRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(.mint)
                .frame(width: 38, height: 38)
                .background(.mint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text(String(format: "%.2f mi  •  %@ active", record.distanceMiles, record.activeDuration.clockText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.averagePace?.paceText ?? "--:--")
                    .font(.headline.monospacedDigit())
                Text("avg /mi")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}
