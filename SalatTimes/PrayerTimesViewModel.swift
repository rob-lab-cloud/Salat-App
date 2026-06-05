import Foundation
import CoreLocation
import UserNotifications

class PrayerTimesViewModel: NSObject, ObservableObject {

    private static let methodKey = "selectedCalculationMethod"

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

        #if targetEnvironment(simulator)
        // In simulator, lock to Dubai so prayer times align with the Mac's clock
        // (the simulator GPS would otherwise default to Cupertino, mismatching the timezone).
        let simCoord = CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708)
        userLocation = simCoord
        userCoordinate = simCoord
        userTimeZone = TimeZone(identifier: "Asia/Dubai") ?? .current
        locationName = "Dubai, UAE"
        locationStatus = .authorized
        refreshPrayerTimes()
        #else
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        #endif
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
        for offset in 1...6 {
            if let day = Calendar.current.date(byAdding: .day, value: offset, to: now) {
                allTimes += PrayerTimesCalculator.calculate(
                    for: day, coordinate: location, method: selectedMethod, timeZone: userTimeZone
                )
            }
        }

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
            DispatchQueue.main.async {
                self.locationName = city.isEmpty ? country : (country.isEmpty ? city : "\(city), \(country)")
                if let tz = placemarkTZ, tz != self.userTimeZone {
                    self.userTimeZone = tz
                    self.refreshPrayerTimes()
                }
                if !self.prayerTimes.isEmpty {
                    saveWidgetData(locationName: self.locationName, prayerTimes: self.prayerTimes)
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
            locationManager.requestLocation()
        case .denied, .restricted:
            locationStatus = .denied
            locationName = "Location denied"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
        userCoordinate = location.coordinate
        reverseGeocode(location: location)
        refreshPrayerTimes()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationStatus = .denied
        locationName = "Location unavailable"
    }
}
