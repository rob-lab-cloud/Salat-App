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
    
    var isNext: Bool = false
    var isCurrent: Bool = false
    
    var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: time)
    }
}

// MARK: - Calculator
class PrayerTimesCalculator {
    
    static func calculate(
        for date: Date = Date(),
        coordinate: CLLocationCoordinate2D,
        method: CalculationMethod = .muslimWorldLeague,
        timeZoneOffset: Double? = nil
    ) -> [PrayerTime] {
        
        // tz = UTC offset in hours for the device's current timezone
        let tz = timeZoneOffset ?? Double(TimeZone.current.secondsFromGMT()) / 3600.0
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        
        // Extract LOCAL date components so calculations use the user's calendar day
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TimeZone.current
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
            PrayerTime(prayer: prayer, time: hoursToDate(localHours: hours, localYear: year, localMonth: month, localDay: day))
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
    private static func hoursToDate(localHours: Double, localYear: Int, localMonth: Int, localDay: Int) -> Date {
        // Build UTC midnight for this local date
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = localYear; c.month = localMonth; c.day = localDay
        c.hour = 0; c.minute = 0; c.second = 0
        guard let utcMidnight = utcCal.date(from: c) else { return Date() }
        
        // localHours is local-time hours since midnight, but we're starting from UTC midnight.
        // So we need to subtract the UTC offset to get back to UTC, then the OS will
        // display it as local time correctly.
        let tzOffsetHours = Double(TimeZone.current.secondsFromGMT()) / 3600.0
        let utcHours = localHours - tzOffsetHours
        return utcMidnight.addingTimeInterval(utcHours * 3600.0)
    }
}

// MARK: - Widget Data Bridge

private let appGroupID = "group.com.salatimes.app"

struct WidgetPrayerData: Codable {
    var locationName: String
    var prayers: [WidgetPrayer]
    var updatedAt: Date
}

struct WidgetPrayer: Codable, Identifiable {
    var id: String { name }
    var name: String
    var arabicName: String
    var timeString: String
    var isNext: Bool
    var isCurrent: Bool
    var iconName: String
}

func saveWidgetData(locationName: String, prayerTimes: [PrayerTime]) {
    let widgets = prayerTimes.map { pt in
        WidgetPrayer(
            name:       pt.prayer.rawValue,
            arabicName: pt.prayer.arabicName,
            timeString: pt.timeString,
            isNext:     pt.isNext,
            isCurrent:  pt.isCurrent,
            iconName:   pt.prayer.icon
        )
    }
    let data = WidgetPrayerData(locationName: locationName, prayers: widgets, updatedAt: Date())
    if let encoded = try? JSONEncoder().encode(data) {
        UserDefaults(suiteName: appGroupID)?.set(encoded, forKey: "widgetData")
    }
    WidgetCenter.shared.reloadAllTimelines()
}
