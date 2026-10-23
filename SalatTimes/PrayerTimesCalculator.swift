import Foundation
import CoreLocation
import WidgetKit

// MARK: - Prayer Names
enum Prayer: String, CaseIterable {
    case fajr    = "Fajr"
    case sunrise = "Sunrise"
    case dhuhr   = "Dhuhr"
    case asr     = "Asr"
    case maghrib = "Maghrib"
    case isha    = "Isha"
    
    var arabicName: String {
        switch self {
        case .fajr:    return "الفجر"
        case .sunrise: return "الشروق"
        case .dhuhr:   return "الظهر"
        case .asr:     return "العصر"
        case .maghrib: return "المغرب"
        case .isha:    return "العشاء"
        }
    }
    
    var icon: String {
        switch self {
        case .fajr:    return "moon.stars.fill"
        case .sunrise: return "sunrise.fill"
        case .dhuhr:   return "sun.max.fill"
        case .asr:     return "sun.haze.fill"
        case .maghrib: return "sunset.fill"
        case .isha:    return "moon.fill"
        }
    }
}

// MARK: - Calculation Methods
enum CalculationMethod: String, CaseIterable {
    case muslimWorldLeague = "Muslim World League"
    case egyptian          = "Egyptian Authority"
    case karachi           = "Univ. of Islamic Sciences, Karachi"
    case isna              = "ISNA (North America)"
    case ummAlQura         = "Umm al-Qura (Makkah)"
    case turkey            = "Diyanet (Turkey)"
    case southeastAsia     = "Singapore / Malaysia / Indonesia"
    case uoif              = "France (UOIF, 12°)"

    var fajrAngle: Double {
        switch self {
        case .muslimWorldLeague: return 18.0
        case .egyptian:          return 19.5
        case .karachi:           return 18.0
        case .isna:              return 15.0
        case .ummAlQura:         return 18.5
        case .turkey:            return 18.0
        case .southeastAsia:     return 20.0
        case .uoif:              return 12.0
        }
    }

    var ishaAngle: Double {
        switch self {
        case .muslimWorldLeague: return 17.0
        case .egyptian:          return 17.5
        case .karachi:           return 18.0
        case .isna:              return 15.0
        case .ummAlQura:         return 0      // fixed interval instead, see below
        case .turkey:            return 17.0
        case .southeastAsia:     return 18.0
        case .uoif:              return 12.0
        }
    }

    /// Fixed per-prayer offsets (minutes) that the issuing authority publishes
    /// on top of the astronomical time. Diyanet uses safety margins.
    func minuteOffset(for prayer: Prayer) -> Double {
        guard self == .turkey else { return 0 }
        switch prayer {
        case .sunrise: return -7
        case .dhuhr:   return 5
        case .asr:     return 4
        case .maghrib: return 7
        default:       return 0
        }
    }

    /// Methods that define Isha as a fixed interval after Maghrib.
    var ishaMinutesAfterMaghrib: Double? {
        self == .ummAlQura ? 90 : nil
    }
}

// MARK: - Asr Juristic School
enum AsrSchool: String, CaseIterable {
    case standard = "Standard (Shafi'i, Maliki, Hanbali)"
    case hanafi   = "Hanafi"

    /// Shadow-length multiple at which Asr begins.
    var shadowFactor: Double { self == .hanafi ? 2 : 1 }

    static let key = "selectedAsrSchool"
    static var saved: AsrSchool {
        get { UserDefaults.standard.string(forKey: key).flatMap(AsrSchool.init(rawValue:)) ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - Prayer Time Entry
struct PrayerTime: Identifiable {
    let id = UUID()
    let prayer: Prayer
    let time: Date
    var timeZone: TimeZone = .current
    
    var isNext: Bool = false
    var isCurrent: Bool = false
    
    var timeString: String {
        let fmt = TimeFormatPreference.use24Hour ? Self.formatter24 : Self.formatter12
        fmt.timeZone = timeZone
        return fmt.string(from: time)
    }

    private static let formatter12: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let formatter24: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Time Format Preference
// Read wherever times are rendered; changing it requires refreshPrayerTimes()
// so the list, widget data, and notification bodies are re-rendered.
enum TimeFormatPreference {
    static let key = "use24HourTime"
    static var use24Hour: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Calculator
class PrayerTimesCalculator {

    /// Prayer times for `days` consecutive days starting from `date`'s day
    /// (days are counted in the location's time zone).
    /// Used by the app's refresh and by the background task so notifications
    /// can be rescheduled without a live location fix.
    static func calculateWindow(
        days: Int,
        from date: Date,
        coordinate: CLLocationCoordinate2D,
        method: CalculationMethod,
        asrSchool: AsrSchool = .standard,
        timeZone: TimeZone
    ) -> [PrayerTime] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var all: [PrayerTime] = []
        for offset in 0..<days {
            if let day = cal.date(byAdding: .day, value: offset, to: date) {
                all += calculate(for: day, coordinate: coordinate, method: method,
                                 asrSchool: asrSchool, timeZone: timeZone)
            }
        }
        return all
    }

    static func calculate(
        for date: Date = Date(),
        coordinate: CLLocationCoordinate2D,
        method: CalculationMethod = .muslimWorldLeague,
        asrSchool: AsrSchool = .standard,
        timeZone: TimeZone = .current
    ) -> [PrayerTime] {

        let lat = coordinate.latitude
        let lng = coordinate.longitude

        // Calendar day in the LOCATION's time zone (not the device's).
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = timeZone
        let year  = localCal.component(.year,  from: date)
        let month = localCal.component(.month, from: date)
        let day   = localCal.component(.day,   from: date)

        // UTC offset taken at local noon of that day, and used for BOTH the
        // solar-time formulas and the final conversion. Reading it at any other
        // instant mismatches on DST-change days and shifts every time by 1 hour.
        var noonComps = DateComponents()
        noonComps.year = year; noonComps.month = month; noonComps.day = day; noonComps.hour = 12
        let localNoon = localCal.date(from: noonComps) ?? date
        let tz = Double(timeZone.secondsFromGMT(for: localNoon)) / 3600.0

        // Sun's declination / equation of time at approximate solar noon (UT).
        let jd = julianDay(year: year, month: month, day: day) + (12 - lng / 15.0) / 24.0
        let sun = sunPosition(jd: jd)
        let noon = fixHour(12 - sun.equation - lng / 15.0 + tz)

        func timeForAngle(_ angle: Double, afterNoon: Bool) -> Double? {
            let cosV = (-dsin(angle) - dsin(lat) * dsin(sun.declination)) / (dcos(lat) * dcos(sun.declination))
            guard abs(cosV) <= 1 else { return nil }
            let t = dacos(cosV) / 15.0
            return afterNoon ? noon + t : noon - t
        }

        // Sunrise / sunset; in polar day/night fall back to a 12 h day so the
        // twilight rules below still produce something sensible.
        let sunrise = timeForAngle(0.833, afterNoon: false) ?? (noon - 6)
        let sunset  = timeForAngle(0.833, afterNoon: true)  ?? (noon + 6)

        // Asr: shadow length = factor + noon shadow.
        let asrAngle = datan(1.0 / (asrSchool.shadowFactor + dtan(abs(lat - sun.declination))))
        let asrCos = (dsin(asrAngle) - dsin(lat) * dsin(sun.declination)) / (dcos(lat) * dcos(sun.declination))
        let asr = abs(asrCos) <= 1 ? noon + dacos(asrCos) / 15.0 : sunset

        // High-latitude handling (angle-based rule): where the sun never reaches
        // the twilight angle, or reaches it implausibly early/late, limit the
        // twilight to angle/60 of the night. Without this Fajr/Isha were
        // returned as solar noon on summer days in e.g. London or Berlin.
        let night = 24 - (sunset - sunrise)

        let fajrRaw = timeForAngle(method.fajrAngle, afterNoon: false)
        let fajrLimit = method.fajrAngle / 60.0 * night
        let fajr: Double
        if let t = fajrRaw, sunrise - t <= fajrLimit { fajr = t } else { fajr = sunrise - fajrLimit }

        let isha: Double
        if let mins = method.ishaMinutesAfterMaghrib {
            isha = sunset + mins / 60.0
        } else {
            let ishaLimit = method.ishaAngle / 60.0 * night
            if let t = timeForAngle(method.ishaAngle, afterNoon: true), t - sunset <= ishaLimit {
                isha = t
            } else {
                isha = sunset + ishaLimit
            }
        }

        let pairs: [(Prayer, Double)] = [
            (.fajr,    fajr),
            (.sunrise, sunrise),
            (.dhuhr,   noon),
            (.asr,     asr),
            (.maghrib, sunset),
            (.isha,    isha)
        ]

        return pairs.map { (prayer, hours) in
            PrayerTime(
                prayer: prayer,
                time: hoursToDate(localHours: hours + method.minuteOffset(for: prayer) / 60.0, localYear: year, localMonth: month, localDay: day, utcOffsetHours: tz),
                timeZone: timeZone
            )
        }
    }

    // MARK: - Astronomical Calculations

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100.0)
        let b = 2 - a + floor(a / 4.0)
        return floor(365.25 * (Double(y) + 4716))
             + floor(30.6001 * (Double(m) + 1))
             + Double(day) + b - 1524.5
    }

    private static func sunPosition(jd: Double) -> (declination: Double, equation: Double) {
        let d = jd - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * d)
        let q = fixAngle(280.459 + 0.98564736 * d)
        let l = fixAngle(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g))
        let e = 23.439 - 0.00000036 * d
        let ra = datan2(dcos(e) * dsin(l), dcos(l)) / 15.0
        let decl = dasin(dsin(e) * dsin(l))
        let eqT = q / 15.0 - fixHour(ra)
        return (decl, eqT)
    }

    // MARK: - Degree-based trig helpers
    private static func dsin(_ d: Double) -> Double { sin(d * .pi / 180) }
    private static func dcos(_ d: Double) -> Double { cos(d * .pi / 180) }
    private static func dtan(_ d: Double) -> Double { tan(d * .pi / 180) }
    private static func dasin(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private static func dacos(_ x: Double) -> Double { acos(x) * 180 / .pi }
    private static func datan(_ x: Double) -> Double { atan(x) * 180 / .pi }
    private static func datan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }

    private static func fixAngle(_ a: Double) -> Double { a - 360.0 * floor(a / 360.0) }
    private static func fixHour(_ h: Double) -> Double  { h - 24.0  * floor(h / 24.0)  }

    // MARK: - Convert decimal local hours → Date
    // `localHours` is wall-clock hours since local midnight using `utcOffsetHours`
    // (the same offset the solar formulas used). UTC midnight of the local
    // calendar date plus (hours - offset) is the absolute instant.
    private static func hoursToDate(localHours: Double, localYear: Int, localMonth: Int, localDay: Int, utcOffsetHours: Double) -> Date {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var c = DateComponents()
        c.year = localYear; c.month = localMonth; c.day = localDay
        c.hour = 0; c.minute = 0; c.second = 0
        guard let utcMidnight = utcCal.date(from: c) else { return Date() }
        return utcMidnight.addingTimeInterval((localHours - utcOffsetHours) * 3600.0)
    }
}

// MARK: - Last Known Location
// Persisted so the background refresh task can recompute prayer times and
// reschedule notifications without a live GPS fix.

let calculationMethodKey = "selectedCalculationMethod"

struct SavedLocation: Codable {
    var latitude: Double
    var longitude: Double
    var timeZoneID: String
    var locationName: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .current
    }

    private static let key = "lastKnownLocation"

    static func load() -> SavedLocation? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedLocation.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Widget Data Bridge

private let appGroupID = "group.salatimes.app"


func saveWidgetData(locationName: String, prayerTimes: [PrayerTime]) {
    let widgets = prayerTimes.map { pt in
        WidgetPrayer(
            name:       pt.prayer.rawValue,
            arabicName: pt.prayer.arabicName,
            timeString: pt.timeString,
            isNext:     pt.isNext,
            isCurrent:  pt.isCurrent,
            iconName:   pt.prayer.icon,
            time:       pt.time
        )
    }
    let data = WidgetPrayerData(locationName: locationName, prayers: widgets, updatedAt: Date())
    if let encoded = try? JSONEncoder().encode(data) {
        UserDefaults(suiteName: appGroupID)?.set(encoded, forKey: "widgetData")
    }
    WidgetCenter.shared.reloadAllTimelines()
}
