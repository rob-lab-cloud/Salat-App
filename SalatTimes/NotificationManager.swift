import Foundation
import OSLog
import UserNotifications
import CoreLocation
import UIKit

private let log = Logger(subsystem: "com.salatimes.app", category: "notifications")

// MARK: - Reminder Settings stored per prayer
struct PrayerReminderSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var minutesBefore: Int = 0   // 0 = at prayer time, >0 = N minutes before
    var playAdhan: Bool = true
}

// MARK: - NotificationManager
class NotificationManager: ObservableObject {

    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @Published var reminderSettings: [String: PrayerReminderSettings] = [:]

    private let settingsKey = "prayerReminderSettings"

    private init() {
        loadSettings()
        checkAuthorization()
    }

    // MARK: - Authorization
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in self.isAuthorized = granted }
        }
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Settings persistence
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: PrayerReminderSettings].self, from: data) {
            reminderSettings = decoded
        } else {
            // Default: all prayers enabled, at prayer time, with adhan
            for prayer in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"] {
                reminderSettings[prayer] = PrayerReminderSettings()
            }
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(reminderSettings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func updateSetting(for prayer: String, settings: PrayerReminderSettings) {
        reminderSettings[prayer] = settings
        saveSettings()
    }

    // MARK: - Schedule notifications
    // `completion` fires after every request has been handed to the system —
    // needed by the background refresh task to know when it can complete.
    func scheduleNotifications(for prayerTimes: [PrayerTime], completion: (() -> Void)? = nil) {
        // Check authorization fresh rather than relying on the cached flag:
        // in a background launch the async init check may not have landed yet.
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] notifSettings in
            guard let self = self, notifSettings.authorizationStatus == .authorized else {
                completion?()
                return
            }

            // Remove all previously scheduled prayer notifications (any day, any prefix match)
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let salatIDs = requests.map(\.identifier).filter { $0.hasPrefix("salat_") }
                if !salatIDs.isEmpty {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: salatIDs)
                }

                let group = DispatchGroup()
                for pt in prayerTimes {
                    guard pt.prayer != .sunrise else { continue }
                    let settings = self.reminderSettings[pt.prayer.rawValue] ?? PrayerReminderSettings()
                    guard settings.isEnabled else { continue }
                    self.scheduleNotification(for: pt, settings: settings, group: group)
                }
                group.notify(queue: .main) { completion?() }
            }
        }
    }

    private func scheduleNotification(for prayerTime: PrayerTime, settings: PrayerReminderSettings, group: DispatchGroup? = nil) {
        let content = UNMutableNotificationContent()

        let minutesBefore = settings.minutesBefore
        if minutesBefore > 0 {
            content.title = "🕌 \(prayerTime.prayer.rawValue) in \(minutesBefore) min"
            content.body  = "\(prayerTime.prayer.arabicName) — \(prayerTime.timeString)"
        } else {
            content.title = "🕌 \(prayerTime.prayer.rawValue) — \(prayerTime.prayer.arabicName)"
            content.body  = "It is time for \(prayerTime.prayer.rawValue) prayer (\(prayerTime.timeString))"
        }

        // Only use the adhan sound if the asset is actually bundled — otherwise the
        // OS would play nothing instead of falling back to the default sound.
        if settings.playAdhan,
           Bundle.main.url(forResource: "adhan", withExtension: "caf") != nil {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("adhan.caf"))
        } else {
            content.sound = .default
        }
        content.categoryIdentifier = "PRAYER_REMINDER"

        // Fire time
        let fireDate = prayerTime.time.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard fireDate > Date() else { return }  // skip past times

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(
            identifier: notificationID(for: prayerTime.prayer.rawValue, date: prayerTime.time),
            content: content,
            trigger: trigger
        )

        group?.enter()
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.error("Notification scheduling error: \(error.localizedDescription, privacy: .public)")
            }
            group?.leave()
        }
    }

    private static let idDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func notificationID(for prayer: String, date: Date) -> String {
        "salat_\(prayer)_\(Self.idDateFormatter.string(from: date))"
    }

    // MARK: - Cancel all
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Open Settings (call when isAuthorized == false)
    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - PrayerTime extension (needed here)
extension PrayerTime {
    var arabicName: String { prayer.arabicName }
}
