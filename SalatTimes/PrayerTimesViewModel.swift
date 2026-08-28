import Foundation
import CoreLocation
import UserNotifications

@MainActor
class PrayerTimesViewModel: NSObject, ObservableObject {

    private static let methodKey = calculationMethodKey

    @Published var prayerTimes: [PrayerTime] = []
    @Published var nextPrayer: PrayerTime?
    @Published var currentPrayer: PrayerTime?
    @Published var locationName: String = "Locating..."
    @Published var locationStatus: LocationStatus = .requesting
    @Published var selectedMethod: CalculationMethod = .muslimWorldLeague {
        didSet {
            UserDefaults.standard.set(selectedMethod.rawValue, forKey: Self.methodKey)
        }
    }
    @Published var timeUntilNext: String = ""
    @Published var currentDate: Date = Date()
    @Published var userCoordinate: CLLocationCoordinate2D? = nil

    let notificationManager = NotificationManager.shared

    private let locationManager = CLLocationManager()
    private var userLocation: CLLocationCoordinate2D?
    private var userTimeZone: TimeZone = .current
    private var timer: Timer?

    enum LocationStatus {
        case requesting, authorized, denied, loading
    }

    override init() {
        super.init()
        if let raw = UserDefaults.standard.string(forKey: Self.methodKey),
           let saved = CalculationMethod(rawValue: raw) {
            self.selectedMethod = saved
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let next = self.nextPrayer, Date() >= next.time {
                self.refreshPrayerTimes()
            }
            self.updateCountdown()
            self.currentDate = Date()
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
    }

    deinit { timer?.invalidate() }

    func refreshPrayerTimes() {
        guard let location = userLocation else { return }
        let now = Date()

        var todayTimes = PrayerTimesCalculator.calculate(
            for: now, coordinate: location, method: selectedMethod, timeZone: userTimeZone
        )

        // Build a multi-day window so notifications and the hero "next prayer"
        // can survive past midnight without re-opening the app.
        var allTimes: [PrayerTime] = todayTimes
        allTimes += PrayerTimesCalculator.calculateWindow(
            days: 6,
            from: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now,
            coordinate: location, method: selectedMethod, timeZone: userTimeZone
        )

        // Persist the location so the background refresh task can reschedule
        // notifications without a live GPS fix.
        SavedLocation(
            latitude: location.latitude, longitude: location.longitude,
            timeZoneID: userTimeZone.identifier, locationName: locationName
        ).save()

        let nextFuture = allTimes.first { $0.prayer != .sunrise && $0.time > now }

        for i in todayTimes.indices {
            todayTimes[i].isNext = false
            todayTimes[i].isCurrent = false
        }
        if let currentIdx = todayTimes.lastIndex(where: { $0.prayer != .sunrise && $0.time <= now }) {
            todayTimes[currentIdx].isCurrent = true
        }

        var nextForHero: PrayerTime? = nil
        if let nextFuture = nextFuture {
            if let idx = todayTimes.firstIndex(where: {
                $0.prayer == nextFuture.prayer &&
                abs($0.time.timeIntervalSince(nextFuture.time)) < 60
            }) {
                todayTimes[idx].isNext = true
                nextForHero = todayTimes[idx]
            } else {
                nextForHero = nextFuture
            }
        }

        self.prayerTimes = todayTimes
        self.nextPrayer = nextForHero
        self.currentPrayer = todayTimes.first(where: { $0.isCurrent })
        self.locationStatus = .authorized

        notificationManager.scheduleNotifications(for: allTimes)
        saveWidgetData(locationName: locationName, prayerTimes: todayTimes)
        updateCountdown()
    }

    private func updateCountdown() {
        guard let next = nextPrayer else { timeUntilNext = ""; return }
        let remaining = max(0, next.time.timeIntervalSince(Date()))

        let hours   = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        timeUntilNext = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    func reverseGeocode(location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self = self, let placemark = placemarks?.first else { return }
            let city    = placemark.locality ?? ""
            let country = placemark.country ?? ""
            let placemarkTZ = placemark.timeZone
            Task { @MainActor in
                self.locationName = city.isEmpty ? country : (country.isEmpty ? city : "\(city), \(country)")
                if let tz = placemarkTZ, tz != self.userTimeZone {
                    self.userTimeZone = tz
                    self.refreshPrayerTimes()
                }
                if !self.prayerTimes.isEmpty {
                    saveWidgetData(locationName: self.locationName, prayerTimes: self.prayerTimes)
                }
                // Re-save with the resolved city name (the first save happens
                // before geocoding completes).
                if let coord = self.userLocation {
                    SavedLocation(
                        latitude: coord.latitude, longitude: coord.longitude,
                        timeZoneID: self.userTimeZone.identifier, locationName: self.locationName
                    ).save()
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension PrayerTimesViewModel: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationStatus = .loading
            // Continuously listen until the first fix arrives; a one-shot
            // requestLocation() can silently time out (e.g. simulator with
            // no simulated location yet) and never deliver.
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            locationStatus = .denied
            locationName = "Location denied"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        userLocation = location.coordinate
        userCoordinate = location.coordinate
        reverseGeocode(location: location)
        refreshPrayerTimes()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient - Core Location keeps trying,
        // so stay in the loading state instead of giving up.
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        locationStatus = .denied
        locationName = "Location unavailable"
    }
}
