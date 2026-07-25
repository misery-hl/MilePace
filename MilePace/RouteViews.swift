import CoreLocation
import MapKit
import SwiftUI

extension RoutePoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension PlannedRoute {
    var lineCoordinates: [CLLocationCoordinate2D] {
        line.map(\.coordinate)
    }

    var region: MKCoordinateRegion {
        guard let bounds else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLatitude, longitude: bounds.centerLongitude),
            span: MKCoordinateSpan(
                latitudeDelta: max(bounds.latitudeSpan * 1.4, 0.004),
                longitudeDelta: max(bounds.longitudeSpan * 1.4, 0.004)
            )
        )
    }
}

/// Turns the corners a runner places into a path that follows real roads and
/// trails, using MapKit's on-device walking directions. No key, no backend.
///
/// Directions are requested one leg at a time, between consecutive waypoints,
/// then joined. A leg MapKit cannot route — off any path, across water — falls
/// back to a straight line, so a route is always drawable.
enum RouteDirections {
    static func walkingLine(through waypoints: [CLLocationCoordinate2D]) async -> [RoutePoint] {
        guard waypoints.count >= 2 else { return waypoints.map(RoutePoint.init) }

        var line: [RoutePoint] = [RoutePoint(waypoints[0])]

        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            if let leg = await walkingLeg(from: from, to: to) {
                // Drop the first point of each leg; it repeats the previous end.
                line.append(contentsOf: leg.dropFirst())
            } else {
                line.append(RoutePoint(to))
            }
        }
        return line
    }

    private static func walkingLeg(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> [RoutePoint]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let polyline = response.routes.first?.polyline else { return nil }
            var coords = [CLLocationCoordinate2D](
                repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount
            )
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
            return coords.map(RoutePoint.init)
        } catch {
            return nil
        }
    }
}

/// Builds a custom route by tapping corners on the map. Each tap adds a
/// waypoint; MapKit fills in the walking path between them.
struct RouteBuilderView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var waypoints: [CLLocationCoordinate2D] = []
    @State private var line: [RoutePoint] = []
    @State private var name = ""
    @State private var isRouting = false
    /// Bumped on every waypoint change, so a slow directions result knows it is
    /// stale. CLLocationCoordinate2D is not Equatable, so the arrays cannot be
    /// compared directly.
    @State private var routingGeneration = 0
    @State private var position: MapCameraPosition = .userLocation(
        fallback: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0855, longitude: -75.0330),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    )

    private var distanceMiles: Double {
        RouteGeometry.length(of: line) / metersPerMile
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                MapReader { proxy in
                    Map(position: $position, interactionModes: [.pan, .zoom]) {
                        UserAnnotation()

                        if line.count >= 2 {
                            MapPolyline(coordinates: line.map(\.coordinate))
                                .stroke(.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        }

                        ForEach(Array(waypoints.enumerated()), id: \.offset) { index, point in
                            Annotation("\(index + 1)", coordinate: point) {
                                WaypointDot(number: index + 1)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .environment(\.colorScheme, .dark)
                    .onTapGesture { location in
                        if let coordinate = proxy.convert(location, from: .local) {
                            addWaypoint(coordinate)
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                controls
            }
            .navigationTitle("New route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(line.count < 2 || isRouting)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(waypoints.isEmpty ? "Tap the map to place your start" : "Tap to add the next turn")
                        .font(.subheadline.weight(.semibold))
                    if line.count >= 2 {
                        Text(String(format: "%.2f mi", distanceMiles))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.mint)
                    } else if isRouting {
                        Text("Finding the path…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    undoLastWaypoint()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .padding(10)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .disabled(waypoints.isEmpty)

                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 150)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(.white)
        .padding(16)
    }

    private func addWaypoint(_ coordinate: CLLocationCoordinate2D) {
        waypoints.append(coordinate)
        recomputeLine()
    }

    private func undoLastWaypoint() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()
        recomputeLine()
    }

    private func recomputeLine() {
        routingGeneration += 1
        let generation = routingGeneration

        guard waypoints.count >= 2 else {
            line = waypoints.map(RoutePoint.init)
            return
        }
        let current = waypoints
        isRouting = true
        Task {
            let newLine = await RouteDirections.walkingLine(through: current)
            // Ignore a stale result if the runner changed the route meanwhile.
            guard generation == routingGeneration else { return }
            line = newLine
            isRouting = false
        }
    }

    private func save() {
        routeStore.add(
            PlannedRoute(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                origin: .drawn,
                waypoints: waypoints.map(RoutePoint.init),
                line: line
            )
        )
        dismiss()
    }
}

private struct WaypointDot: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption2.bold())
            .foregroundStyle(.black)
            .frame(width: 22, height: 22)
            .background(.mint, in: Circle())
            .overlay { Circle().strokeBorder(.black.opacity(0.6), lineWidth: 2) }
    }
}

/// The routes section on the start screen: saved routes, and a way to make one.
struct RoutesSection: View {
    @EnvironmentObject private var routeStore: RouteStore
    @State private var isBuilding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ROUTES")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Spacer()
                if !routeStore.routes.isEmpty {
                    Button { isBuilding = true } label: {
                        Label("New", systemImage: "plus").font(.caption.bold())
                    }
                }
            }

            if routeStore.routes.isEmpty {
                Button { isBuilding = true } label: {
                    Label("Build a route", systemImage: "map")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                }
                Text("Tap out a route on the map, or run a past route again from a saved run.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(routeStore.routes) { route in
                    NavigationLink {
                        RouteDetailView(route: route)
                    } label: {
                        RouteRow(route: route)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isBuilding) { RouteBuilderView() }
    }
}

private struct RouteRow: View {
    let route: PlannedRoute

    var body: some View {
        HStack(spacing: 14) {
            RoutePreviewMap(route: route)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(route.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(route.origin == .drawn ? "Custom route" : "From a past run")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.2f mi", route.distanceMiles))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A small, non-interactive map that draws a route's line. Used as a thumbnail.
struct RoutePreviewMap: View {
    let route: PlannedRoute

    var body: some View {
        Map(initialPosition: .region(route.region), interactionModes: []) {
            if route.line.count >= 2 {
                MapPolyline(coordinates: route.lineCoordinates)
                    .stroke(.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}

/// A saved route: a full map, the distance, and the actions on it.
struct RouteDetailView: View {
    let route: PlannedRoute

    @EnvironmentObject private var routeStore: RouteStore
    @EnvironmentObject private var tracker: RunTracker
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    RoutePreviewMap(route: route)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }

                    HStack {
                        Label(String(format: "%.2f mi", route.distanceMiles), systemImage: "figure.walk")
                        Spacer()
                        Text(route.origin == .drawn ? "Custom route" : "From a past run")
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline)

                    Button {
                        tracker.followedRoute = route
                        dismiss()
                    } label: {
                        Label("Follow this route", systemImage: "location.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.mint, in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(.black)
                    }

                    Button { draftName = route.name; isRenaming = true } label: {
                        Label("Rename", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    }

                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Label("Delete route", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(route.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this route?", isPresented: $isConfirmingDelete) {
            Button("Delete route", role: .destructive) { routeStore.delete(route); dismiss() }
            Button("Keep route", role: .cancel) {}
        } message: {
            Text("This removes the route. Your runs are not affected.")
        }
        .alert("Name this route", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Save") { routeStore.rename(route, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// The followed route on the running screen, with the runner's live position on
/// it so they can see where to go next.
struct FollowedRouteMap: View {
    let route: PlannedRoute

    var body: some View {
        Map(initialPosition: .region(route.region), interactionModes: [.pan, .zoom]) {
            UserAnnotation()

            if route.line.count >= 2 {
                MapPolyline(coordinates: route.lineCoordinates)
                    .stroke(.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let start = route.line.first {
                Annotation("Start", coordinate: start.coordinate) {
                    Circle().fill(.mint).frame(width: 14, height: 14)
                        .overlay { Circle().strokeBorder(.black.opacity(0.7), lineWidth: 2) }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("Map of the route you are following")
    }
}

/// Offered on a saved run that has a recorded path: run the same route again.
struct RunAgainButton: View {
    let record: RunRecord

    @EnvironmentObject private var routeStore: RouteStore
    @EnvironmentObject private var tracker: RunTracker
    @State private var saved = false

    var body: some View {
        if record.hasRoute {
            Button {
                let route = PlannedRoute(fromRun: record)
                routeStore.add(route)
                tracker.followedRoute = route
                saved = true
            } label: {
                Label(saved ? "Following this route" : "Run this route again",
                      systemImage: saved ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.mint.opacity(saved ? 0.12 : 0.18), in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.mint)
            }
            .disabled(saved)
            .accessibilityHint("Saves this run's path as a route and follows it on your next run")
        }
    }
}
