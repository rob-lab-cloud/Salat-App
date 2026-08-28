# 🕌 Salat Times — Islamic Prayer Times iOS App

A beautiful, minimal iOS app that calculates Islamic prayer times based on your GPS location.

## Features
- 📍 **Automatic geolocation** — prayer times update based on where you are
- ⏱ **Live countdown** to the next prayer (updates every second)
- 🌙 **Current/Next prayer** highlighting with clear visual indicators
- 📐 **5 calculation methods** — Muslim World League, Egyptian, Karachi, ISNA, MWL Europe
- 🎨 **Dark, elegant UI** with gold accents and Islamic geometric patterns
- 🌏 **Reverse geocoding** — shows your city name
- 🧭 **Qibla compass** — animated needle pointing toward the Kaaba
- 🔔 **Prayer reminders** — configurable notifications with optional Adhan sound
- 📱 **Home screen widget** — small and medium sizes showing prayer times at a glance

## Screenshots
The app features:
- A glowing icon for the next prayer with its Arabic name
- Live countdown timer in `HH:MM:SS` format
- A card for each of the 6 prayer times (Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha)
- Highlighted "Current" (green) and "Next" (gold) prayer rows
- Settings sheet to change the calculation method

## Setup

### Requirements
- Xcode 15+
- iOS 17+
- Swift 5.9+

### Steps
1. Open `SalatTimes.xcodeproj` in Xcode
2. Select your development team in **Signing & Capabilities**
3. Change the bundle ID if needed (`com.salatimes.app`)
4. Build & run on a real device or simulator (location works on simulator too with a custom location)

### Permissions
The app requests the following permissions:
- **Location (When In Use)** — to calculate prayer times and Qibla direction for your area. Set in `Info.plist` as `NSLocationWhenInUseUsageDescription`.
- **Motion** — for the Qibla compass needle. Set in `Info.plist` as `NSMotionUsageDescription`.
- **Notifications** — for prayer reminders. Requested at runtime from Settings → Reminders.

## Calculation Methods
| Method | Fajr Angle | Isha Angle | Region |
|--------|-----------|-----------|--------|
| Muslim World League | 18° | 17° | Worldwide |
| Egyptian General Authority | 19.5° | 17.5° | Africa, Middle East |
| Univ. of Islamic Sciences, Karachi | 18° | 18° | South/Central Asia |
| ISNA | 15° | 15° | North America |
| MWL Europe | 12° | 12° | High-latitude Europe |

## File Structure
```
SalatTimes/
├── SalatTimesApp.swift          # App entry point
├── ContentView.swift            # All UI views
├── PrayerTimesCalculator.swift  # Astronomical calculation engine
├── PrayerTimesViewModel.swift   # Location + state management
├── NotificationManager.swift   # Prayer reminders & notifications
├── QiblaCompassView.swift       # Qibla compass component
├── SharedModels.swift           # Shared data models (main app + widget)
├── SalatTimesWidget.swift       # Home screen widget
└── Info.plist                   # Permissions & config
```

## Customization
- **Default method**: Change `selectedMethod` default in `PrayerTimesViewModel`
- **Colors**: All colors use the `Color(hex:)` extension in `ContentView.swift`
- **Asr method**: Change `factor: 1` to `factor: 2` in `asrTime()` for Hanafi madhab

## Potential Enhancements
Ideas for future versions, in rough order of user value:

- **Hijri date** in the header — one-liner with `Calendar(identifier: .islamicUmmAlQura)`
- **Hanafi Asr option** — the Asr shadow factor is currently hardcoded to 1 (Shafi'i); Hanafi users expect factor 2. A settings toggle away.
- **Lock-screen widgets** (`.accessoryRectangular` / `.accessoryCircular`) — cheap to add now that the widget pipeline works
- **Prayer-aware meeting/focus widget** — surface upcoming prayer times around meetings/focus sessions so scheduling can avoid them

## License
MIT — free to use, modify, and distribute.

---

## Additional Features

### 🧭 Qibla Compass
- Compact animated compass in the top-left of the header, right next to the location
- Gold needle always points toward the Kaaba in Mecca
- Uses `CMMotionManager` (device motion / magnetometer) for smooth live rotation
- No API needed — pure astronomical bearing calculation

### 🔔 Prayer Reminders & Adhan Notifications
- Local push notifications for all 5 prayers (Fajr, Dhuhr, Asr, Maghrib, Isha)
- Configurable per-prayer:
  - **On/Off toggle** per prayer
  - **Reminder offset**: At prayer time, 5, 10, 15, 20, or 30 minutes before
  - **Adhan toggle**: Play the bundled `adhan.caf` (falls back to system sound)
- Settings in the "Reminders" tab of the Settings sheet
- Notifications are rescheduled automatically when prayer times recalculate, and a daily background refresh (`BGAppRefreshTask`) keeps the 7-day notification window topped up even if the app isn't opened

**Adhan sound note:** iOS notification sounds must be < 30 seconds and in aiff/wav/caf format; the bundled `adhan.caf` is a 28-second excerpt.

### 📱 Home Screen Widget
- **Small widget**: Next prayer name, time, icon, and "Next" label
- **Medium widget**: All 6 prayers in two columns, with gold/green highlights
- Data shared via `UserDefaults(suiteName:)` App Group

**Widget Setup in Xcode (required):**
1. Add App Group capability to both targets: `group.salatimes.app`
   - Main target → Signing & Capabilities → + App Groups
   - Widget target → same
2. The widget target `SalatTimesWidget` is already added to the project and embedded via "Embed Foundation Extensions"

