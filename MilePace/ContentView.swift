import CoreLocation
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
            .alert("MilePace needs GPS", isPresented: Binding(
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

                Label("Runs stay on this iPhone", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !store.records.isEmpty {
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

            ForEach(store.records.prefix(5)) { record in
                NavigationLink {
                    RunDetailView(record: record)
                } label: {
                    RunRow(record: record)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }
}

private struct RunDashboardView: View {
    @EnvironmentObject private var tracker: RunTracker

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

            HStack(spacing: 10) {
                MetricCard(title: "DISTANCE", value: String(format: "%.2f", record.distanceMiles), unit: "mi")
                MetricCard(title: "TIME", value: record.activeDuration.clockText, unit: "active")
                MetricCard(title: "AVG PACE", value: record.averagePace?.paceText ?? "--:--", unit: "/mi")
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
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }
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
