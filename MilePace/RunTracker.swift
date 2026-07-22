import Combine
import CoreLocation
import UIKit

@MainActor
final class RunTracker: NSObject, ObservableObject {
    @Published private(set) var phase: RunPhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var mileSplits: [MileSplit] = []
    @Published private(set) var currentMilePace: TimeInterval?
    @Published private(set) var rollingPace: TimeInterval?
    @Published private(set) var averagePace: TimeInterval?
    @Published private(set) var currentMileNumber = 1
    @Published private(set) var currentMileProgress = 0.0
    @Published private(set) var lastRun: RunRecord?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var usesReducedAccuracy = false
    @Published var errorMessage: String?

    private let locationManager = CLLocationManager()
    private let store: RunStore
    private var accumulator = RunAccumulator()
    private var timer: Timer?
    private var pendingStart = false
    private var startedAt: Date?
    private var activeSegmentStartedAt: Date?
    private var accumulatedActiveDuration: TimeInterval = 0
    private var previousLocation: CLLocation?
    private var previousLocationElapsed: TimeInterval?
    private var trackPoints: [TrackPoint] = []
    private var segmentIndex = 0

    init(store: RunStore) {
        self.store = store
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 2
        usesReducedAccuracy = locationManager.accuracyAuthorization == .reducedAccuracy
    }

    var distanceMiles: Double {
        distanceMeters / metersPerMile
    }

    func start() {
        errorMessage = nil
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginRun()
        case .notDetermined:
            pendingStart = true
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Location access is off. Enable Precise Location for MilePace in Settings to track a run."
        @unknown default:
            errorMessage = "Location access is unavailable."
        }
    }

    func pause() {
        guard phase == .running else { return }
        accumulatedActiveDuration = activeElapsed(at: Date())
        activeSegmentStartedAt = nil
        phase = .paused
        stopLocationUpdates()
        stopTimer()
        previousLocation = nil
        previousLocationElapsed = nil
        accumulator.resetRollingWindow(at: accumulatedActiveDuration)
        UIApplication.shared.isIdleTimerDisabled = false
        refreshNow()
    }

    func resume() {
        guard phase == .paused else { return }
        activeSegmentStartedAt = Date()
        segmentIndex += 1
        phase = .running
        previousLocation = nil
        previousLocationElapsed = nil
        accumulator.resetRollingWindow(at: accumulatedActiveDuration)
        startLocationUpdates()
        startTimer()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func finish() {
        guard phase == .running || phase == .paused, let startedAt else { return }
        if phase == .running {
            accumulatedActiveDuration = activeElapsed(at: Date())
        }
        activeSegmentStartedAt = nil
        stopLocationUpdates()
        stopTimer()
        UIApplication.shared.isIdleTimerDisabled = false
        refreshNow()

        let record = RunRecord(
            id: UUID(),
            startedAt: startedAt,
            endedAt: Date(),
            distanceMeters: accumulator.totalDistanceMeters,
            activeDuration: accumulatedActiveDuration,
            mileSplits: accumulator.mileSplits,
            // Thin before saving. Fixes arrive every 2 m, which the distance
            // maths needs but the stored route does not, and the whole history
            // is rewritten on every save.
            trackPoints: RouteThinning.thin(trackPoints)
        )
        store.save(record)
        lastRun = record
        phase = .finished
    }

    func dismissSummary() {
        guard phase == .finished else { return }
        lastRun = nil
        phase = .idle
        resetPublishedMetrics()
    }

    func refreshNow() {
        let currentElapsed = phase == .running ? activeElapsed(at: Date()) : accumulatedActiveDuration
        elapsed = currentElapsed
        distanceMeters = accumulator.totalDistanceMeters
        mileSplits = accumulator.mileSplits
        currentMilePace = accumulator.currentMilePace(at: currentElapsed)
        rollingPace = accumulator.rollingPace()
        averagePace = accumulator.averagePace(at: currentElapsed)
        currentMileNumber = accumulator.currentMileNumber
        currentMileProgress = accumulator.currentMileProgress
    }

    private func beginRun() {
        guard phase == .idle else { return }
        let now = Date()
        accumulator = RunAccumulator()
        startedAt = now
        activeSegmentStartedAt = now
        accumulatedActiveDuration = 0
        previousLocation = nil
        previousLocationElapsed = nil
        trackPoints = []
        segmentIndex = 0
        lastRun = nil
        phase = .running
        resetPublishedMetrics()
        startLocationUpdates()
        startTimer()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func startLocationUpdates() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.startUpdatingLocation()
    }

    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func activeElapsed(at date: Date) -> TimeInterval {
        guard let activeSegmentStartedAt else { return accumulatedActiveDuration }
        return accumulatedActiveDuration + max(0, date.timeIntervalSince(activeSegmentStartedAt))
    }

    private func resetPublishedMetrics() {
        elapsed = 0
        distanceMeters = 0
        mileSplits = []
        currentMilePace = nil
        rollingPace = nil
        averagePace = nil
        currentMileNumber = 1
        currentMileProgress = 0
    }
}

extension RunTracker: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        usesReducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy

        if pendingStart && (authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse) {
            pendingStart = false
            beginRun()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            pendingStart = false
            errorMessage = "Location access is off. Enable Precise Location for MilePace in Settings to track a run."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .running else { return }
        let splitCountBeforeUpdate = accumulator.mileSplits.count

        for location in locations {
            guard location.horizontalAccuracy > 0,
                  location.horizontalAccuracy <= 35,
                  abs(location.timestamp.timeIntervalSinceNow) < 120 else { continue }

            let locationElapsed = activeElapsed(at: location.timestamp)
            guard locationElapsed >= accumulatedActiveDuration else { continue }

            trackPoints.append(
                TrackPoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timestamp: location.timestamp,
                    altitude: location.verticalAccuracy > 0 ? location.altitude : nil,
                    horizontalAccuracy: location.horizontalAccuracy,
                    segment: segmentIndex
                )
            )

            guard let previousLocation, let previousLocationElapsed else {
                self.previousLocation = location
                self.previousLocationElapsed = locationElapsed
                accumulator.resetRollingWindow(at: locationElapsed)
                continue
            }

            let timeDelta = location.timestamp.timeIntervalSince(previousLocation.timestamp)
            guard timeDelta > 0 else { continue }

            var segmentDistance = location.distance(from: previousLocation)
            let derivedSpeed = segmentDistance / timeDelta
            guard derivedSpeed <= 10 else { continue }

            if location.speed >= 0, location.speed < 0.4,
               segmentDistance < max(location.horizontalAccuracy, previousLocation.horizontalAccuracy) {
                segmentDistance = 0
            }

            accumulator.recordSegment(
                distanceMeters: segmentDistance,
                fromElapsed: previousLocationElapsed,
                toElapsed: locationElapsed
            )
            self.previousLocation = location
            self.previousLocationElapsed = locationElapsed
        }

        refreshNow()

        // One buzz per completed mile. A batch of fixes delivered after the
        // screen was locked can cross more than one boundary at once, and a
        // single buzz would leave a mile unmarked.
        for _ in splitCountBeforeUpdate..<accumulator.mileSplits.count {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            return
        }
        errorMessage = "GPS is temporarily unavailable. MilePace will keep trying."
    }
}
