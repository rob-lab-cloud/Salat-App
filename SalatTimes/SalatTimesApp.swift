import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct SalatTimesApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                AppDelegate.scheduleAppRefresh()
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // Notifications are only scheduled 7 days ahead when the app is opened.
    // This background task re-extends that window periodically so reminders
    // keep firing even if the user doesn't open the app for weeks.
    static let refreshTaskID = "com.salatimes.app.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Authorization is requested user-initiated from Settings → Reminders,
        // not at launch, so the prompt is shown with on-screen context.

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            Self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        return true
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        // Ask to run roughly daily; the system decides the actual moment.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600)
        // Submitting a duplicate identifier just replaces the pending request.
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        // Chain the next refresh regardless of this run's outcome.
        scheduleAppRefresh()

        guard let saved = SavedLocation.load() else {
            task.setTaskCompleted(success: false)
            return
        }
        let method = UserDefaults.standard.string(forKey: calculationMethodKey)
            .flatMap(CalculationMethod.init(rawValue:)) ?? .muslimWorldLeague
        let now = Date()
        let school = AsrSchool.saved

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        let window = PrayerTimesCalculator.calculateWindow(
            days: 7, from: now,
            coordinate: saved.coordinate, method: method,
            asrSchool: school, timeZone: saved.timeZone
        )

        // Keep the widget's data fresh too while we're here.
        var today = PrayerTimesCalculator.calculate(
            for: now, coordinate: saved.coordinate, method: method,
            asrSchool: school, timeZone: saved.timeZone
        )
        if let idx = today.firstIndex(where: { $0.prayer != .sunrise && $0.time > now }) {
            today[idx].isNext = true
        }
        if let idx = today.lastIndex(where: { $0.prayer != .sunrise && $0.time <= now }) {
            today[idx].isCurrent = true
        }
        saveWidgetData(locationName: saved.locationName, prayerTimes: today)

        NotificationManager.shared.scheduleNotifications(for: window) {
            task.setTaskCompleted(success: true)
        }
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
