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
    case mwlEurope         = "MWL (Europe)"
    
    var fajrAngle: Double {
        switch self {
        case .muslimWorldLeague: return 18.0
        case .egyptian:          return 19.5
        case .karachi:           return 18.0
        case .isna:              return 15.0
        case .mwlEurope:         return 12.0
        }
    }
    
    var ishaAngle: Double {
        switch self {
        case .muslimWorldLeague: return 17.0
        case .egyptian:          return 17.5
        case .karachi:           return 18.0
        case .isna:              return 15.0
        case .mwlEurope:         return 12.0
        }
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
        let fmt = Self.cachedFormatter
        fmt.timeZone = timeZone
        return fmt.string(from: time)
    }

    private static let cachedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Calculator
class PrayerTimesCalculator {

    /// Prayer times for `days` consecutive days starting from `date`'s day.
    /// Used by the app's refresh and by the background task so notifications
    /// can be rescheduled without a live location fix.
    static func calculateWindow(
        days: Int,
        from date: Date,
        coordinate: CLLocationCoordinate2D,
        method: CalculationMethod,
        timeZone: TimeZone
    ) -> [PrayerTime] {
        var all: [PrayerTime] = []
        for offset in 0..<days {
            if let day = Calendar.current.date(byAdding: .day, value: offset, to: date) {
                all += calculate(for: day, coordinate: coordinate, method: method, timeZone: timeZone)
            }
        }
        return all
    }

    static func calculate(
        for date: Date = Date(),
        coordinate: CLLocationCoordinate2D,
        method: CalculationMethod = .muslimWorldLeague,
        timeZone: TimeZone = .current
    ) -> [PrayerTime] {
        
        // tz = UTC offset in hours for the LOCATION's timezone (not necessarily the device's)
        let tz = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        
        // Extract date components in the LOCATION's timezone so calculations use the
        // location's calendar day rather than the device's.
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = timeZone
        let year  = localCal.component(.year,  from: date)
        let month = localCal.component(.month, from: date)
        let day   = localCal.component(.day,   from: date)
        
        let jd = julianDay(year: year, month: month, day: day)
        
        let fajrHrs    = prayerTime(jd: jd, lat: lat, lng: lng, tz: tz, angle: method.fajrAngle, afterNoon: false)
        let sunriseHrs = prayerTime(jd: jd, lat: lat, lng: lng, tz: tz, angle: 0.833, afterNoon: false)
        let dhuhrHrs   = midDay(jd: jd, lng: lng, tz: tz)
        let asrHrs     = calcAsrTime(jd: jd, lat: lat, lng: lng, tz: tz, factor: 1)
        let maghribHrs = prayerTime(jd: jd, lat: lat, lng: lng, tz: tz, angle: 0.833, afterNoon: true)
        let ishaHrs    = prayerTime(jd: jd, lat: lat, lng: lng, tz: tz, angle: method.ishaAngle, afterNoon: true)
        
        let pairs: [(Prayer, Double)] = [
            (.fajr,    fajrHrs),
            (.sunrise, sunriseHrs),
            (.dhuhr,   dhuhrHrs),
            (.asr,     asrHrs),
            (.maghrib, maghribHrs),
            (.isha,    ishaHrs)
        ]
        
        return pairs.map { (prayer, hours) in
            PrayerTime(
                prayer: prayer,
                time: hoursToDate(localHours: hours, localYear: year, localMonth: month, localDay: day, timeZone: timeZone),
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
    
    private static func midDay(jd: Double, lng: Double, tz: Double) -> Double {
        let sun = sunPosition(jd: jd)
        return fixHour(12 - sun.equation - lng / 15.0 + tz)
    }
    
    private static func prayerTime(jd: Double, lat: Double, lng: Double, tz: Double, angle: Double, afterNoon: Bool) -> Double {
        let sun  = sunPosition(jd: jd)
        let noon = midDay(jd: jd, lng: lng, tz: tz)
        let cosV = (-dsin(angle) - dsin(lat) * dsin(sun.declination)) / (dcos(lat) * dcos(sun.declination))
        guard abs(cosV) <= 1 else { return noon }
        let t = dacos(cosV) / 15.0
        return afterNoon ? noon + t : noon - t
    }
    
    private static func calcAsrTime(jd: Double, lat: Double, lng: Double, tz: Double, factor: Double) -> Double {
        let sun  = sunPosition(jd: jd)
        let noon = midDay(jd: jd, lng: lng, tz: tz)
        let angle = datan(1.0 / (factor + dtan(abs(lat - sun.declination))))
        let cosV = (dsin(angle) - dsin(lat) * dsin(sun.declination)) / (dcos(lat) * dcos(sun.declination))
        guard abs(cosV) <= 1 else { return noon }
        return noon + dacos(cosV) / 15.0
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
    // "localHours" is already in the device timezone (the tz offset was baked in above).
    // We build the date by taking UTC midnight of the LOCAL calendar day, then
    // subtracting the UTC offset and adding the hours, which lands us at the
    // correct wall-clock time in the local timezone.
    private static func hoursToDate(localHours: Double, localYear: Int, localMonth: Int, localDay: Int, timeZone: TimeZone) -> Date {
        // Build UTC midnight for this local date
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var c = DateComponents()
        c.year = localYear; c.month = localMonth; c.day = localDay
        c.hour = 0; c.minute = 0; c.second = 0
        guard let utcMidnight = utcCal.date(from: c) else { return Date() }
        
        // localHours is wall-clock hours in the location's timezone since its midnight.
        // Subtract the location's UTC offset to get the absolute UTC instant.
        let tzOffsetHours = Double(timeZone.secondsFromGMT(for: utcMidnight)) / 3600.0
        let utcHours = localHours - tzOffsetHours
        return utcMidnight.addingTimeInterval(utcHours * 3600.0)
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
