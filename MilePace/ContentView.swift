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

            if record.hasRoute {
                RouteMapView(record: record)
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

            RunShareButton(record: record)
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
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
