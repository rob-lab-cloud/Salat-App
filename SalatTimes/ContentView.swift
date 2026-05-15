import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel = PrayerTimesViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            BackgroundView()

            VStack(spacing: 0) {
                HeaderView(
                    locationName: viewModel.locationName,
                    date: viewModel.currentDate,
                    showSettings: $showSettings
                )

                if viewModel.locationStatus == .denied {
                    LocationDeniedView()
                } else if let next = viewModel.nextPrayer {
                    NextPrayerHeroView(
                        prayer: next,
                        countdown: viewModel.timeUntilNext,
                        coordinate: viewModel.userCoordinate
                    )
                } else {
                    LoadingHeroView()
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.prayerTimes) { prayerTime in
                            PrayerTimeRowView(prayerTime: prayerTime)
                        }
                        if viewModel.prayerTimes.isEmpty && viewModel.locationStatus == .loading {
                            ForEach(0..<6, id: \.self) { _ in SkeletonRowView() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
}

// MARK: - Background
struct BackgroundView: View {
    var body: some View {
        ZStack {
            Color(hex: "0A0E1A").ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Color(hex: "1A2444").opacity(0.8), Color.clear]),
                           center: .top, startRadius: 0, endRadius: 400).ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Color(hex: "B8860B").opacity(0.06), Color.clear]),
                           center: .bottom, startRadius: 0, endRadius: 300).ignoresSafeArea()
            GeometricPatternView().opacity(0.04).ignoresSafeArea()
        }
    }
}

// MARK: - Geometric Pattern
struct GeometricPatternView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 60
            let gold = Color(hex: "D4AF37")
            for row in 0...Int(size.height / step) + 1 {
                for col in 0...Int(size.width / step) + 1 {
                    let x = CGFloat(col) * step + (row % 2 == 0 ? 0 : step / 2)
                    let y = CGFloat(row) * step
                    let center = CGPoint(x: x, y: y)
                    var path = Path()
                    let r1: CGFloat = 8, r2: CGFloat = 4
                    for i in 0..<16 {
                        let angle = CGFloat(i) * .pi / 8
                        let r = i % 2 == 0 ? r1 : r2
                        let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .color(gold), lineWidth: 0.5)
                }
            }
        }
    }
}

// MARK: - Header  (Qibla compass on the left)
struct HeaderView: View {
    let locationName: String
    let date: Date
    @Binding var showSettings: Bool

    var dateString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM yyyy"; return f.string(from: date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "D4AF37"))
                    Text(locationName)
                        .font(.custom("Georgia", size: 15))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text(dateString)
                    .font(.custom("Georgia-Italic", size: 12))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

            Button(action: { showSettings = true }) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.07)).frame(width: 40, height: 40)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "D4AF37"))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 8)
    }
}

// MARK: - Next Prayer Hero
struct NextPrayerHeroView: View {
    let prayer: PrayerTime
    let countdown: String
    let coordinate: CLLocationCoordinate2D?
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color(hex: "D4AF37").opacity(0.12)).frame(width: 78, height: 78).blur(radius: 14)
                Image(systemName: prayer.prayer.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "F5D07A"), Color(hex: "B8860B")], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(hex: "D4AF37").opacity(0.5), radius: 10)
                    .scaleEffect(appear ? 1 : 0.6).opacity(appear ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appear)
            }.padding(.top, 2)

            Text("Next Prayer")
                .font(.custom("Georgia-Italic", size: 11)).foregroundColor(.white.opacity(0.45))
                .tracking(2).textCase(.uppercase).padding(.top, 8)

            HStack(spacing: 10) {
                Text(prayer.prayer.arabicName).font(.custom("Georgia", size: 16)).foregroundColor(Color(hex: "D4AF37").opacity(0.7))
                Text(prayer.prayer.rawValue).font(.custom("Georgia-Bold", size: 22)).foregroundColor(.white)
                Text(prayer.prayer.arabicName).font(.custom("Georgia", size: 16)).foregroundColor(Color(hex: "D4AF37").opacity(0.7))
            }
            .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 10)
            .animation(.easeOut(duration: 0.5).delay(0.15), value: appear)

            Text(prayer.timeString)
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "F5D07A"), Color(hex: "C9A227")], startPoint: .leading, endPoint: .trailing))
                .tracking(-1).padding(.top, 2)
                .opacity(appear ? 1 : 0).animation(.easeOut(duration: 0.5).delay(0.25), value: appear)

            if !countdown.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 10))
                    Text("in \(countdown)").font(.custom("Georgia-Italic", size: 13))
                }
                .foregroundColor(.white.opacity(0.55)).padding(.top, 6)
                .opacity(appear ? 1 : 0).animation(.easeOut(duration: 0.5).delay(0.35), value: appear)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(
                    LinearGradient(colors: [Color(hex: "D4AF37").opacity(0.4), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        )
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 2) {
                QiblaCompassView(coordinate: coordinate)
                Text("Qibla")
                    .font(.custom("Georgia-Italic", size: 9))
                    .foregroundColor(Color(hex: "D4AF37").opacity(0.6))
                    .tracking(1)
            }
            .padding(.top, 10)
            .padding(.trailing, 12)
        }
        .padding(.horizontal, 20).padding(.bottom, 4)
        .onAppear { appear = true }
        .onChange(of: prayer.prayer) {
            appear = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appear = true }
        }
    }
}

// MARK: - Loading Hero
struct LoadingHeroView: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill").font(.system(size: 44))
                .foregroundColor(Color(hex: "D4AF37").opacity(pulse ? 0.8 : 0.3))
                .animation(.easeInOut(duration: 1.2).repeatForever(), value: pulse)
            Text("Calculating Prayer Times...").font(.custom("Georgia-Italic", size: 16)).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60).onAppear { pulse = true }
    }
}

// MARK: - Location Denied
struct LocationDeniedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash.fill").font(.system(size: 40)).foregroundColor(Color(hex: "D4AF37").opacity(0.6))
            Text("Location Access Required").font(.custom("Georgia-Bold", size: 18)).foregroundColor(.white)
            Text("Please enable location access in Settings to calculate prayer times for your location.")
                .font(.custom("Georgia-Italic", size: 13)).foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.custom("Georgia", size: 14)).foregroundColor(Color(hex: "D4AF37")).padding(.top, 8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

// MARK: - Prayer Time Row
struct PrayerTimeRowView: View {
    let prayerTime: PrayerTime
    @State private var appear = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconBackground).frame(width: 36, height: 36)
                Image(systemName: prayerTime.prayer.icon).font(.system(size: 15)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(prayerTime.prayer.rawValue).font(.custom("Georgia-Bold", size: 15)).foregroundColor(nameColor)
                Text(prayerTime.prayer.arabicName).font(.custom("Georgia", size: 11)).foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(prayerTime.timeString).font(.system(size: 16, weight: prayerTime.isNext ? .semibold : .light)).foregroundColor(timeColor)
                if prayerTime.isCurrent {
                    Label("Current", systemImage: "circle.fill").font(.system(size: 9))
                        .foregroundColor(Color(hex: "4CAF50").opacity(0.9)).labelStyle(.titleAndIcon)
                } else if prayerTime.isNext {
                    Label("Next", systemImage: "arrow.right.circle.fill").font(.system(size: 9))
                        .foregroundColor(Color(hex: "D4AF37").opacity(0.9)).labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14).fill(rowBackground)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(rowBorder, lineWidth: 1)))
        .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 12)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appear = true } }
    }

    var iconBackground: Color {
        prayerTime.isNext ? Color(hex: "D4AF37").opacity(0.18) :
        prayerTime.isCurrent ? Color(hex: "1A4A2A").opacity(0.8) : Color.white.opacity(0.05)
    }
    var iconColor: Color {
        prayerTime.isNext ? Color(hex: "F5D07A") :
        prayerTime.isCurrent ? Color(hex: "4CAF50") : Color.white.opacity(0.4)
    }
    var nameColor: Color {
        prayerTime.isNext ? .white :
        prayerTime.isCurrent ? Color(hex: "7ED89A") : Color.white.opacity(0.7)
    }
    var timeColor: Color {
        prayerTime.isNext ? Color(hex: "F5D07A") :
        prayerTime.isCurrent ? Color(hex: "7ED89A") : Color.white.opacity(0.55)
    }
    var rowBackground: Color {
        prayerTime.isNext ? Color(hex: "1C1E0E").opacity(0.6) :
        prayerTime.isCurrent ? Color(hex: "0A1A0F").opacity(0.8) : Color.white.opacity(0.04)
    }
    var rowBorder: Color {
        prayerTime.isNext ? Color(hex: "D4AF37").opacity(0.35) :
        prayerTime.isCurrent ? Color(hex: "4CAF50").opacity(0.25) : Color.white.opacity(0.07)
    }
}

// MARK: - Skeleton Row
struct SkeletonRowView: View {
    @State private var shimmer = false
    var body: some View {
        HStack(spacing: 16) {
            Circle().fill(Color.white.opacity(0.07)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.07)).frame(width: 80, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04)).frame(width: 50, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.07)).frame(width: 60, height: 16)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
        .opacity(shimmer ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(), value: shimmer)
        .onAppear { shimmer = true }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: PrayerTimesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .calculation

    enum SettingsTab: String, CaseIterable {
        case calculation = "Calculation"
        case notifications = "Reminders"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0A0E1A").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab picker
                    Picker("Settings", selection: $selectedTab) {
                        ForEach(SettingsTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                    if selectedTab == .calculation {
                        CalculationMethodSection(viewModel: viewModel)
                    } else {
                        NotificationsSection(notificationManager: viewModel.notificationManager,
                                             prayerTimes: viewModel.prayerTimes)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("Georgia", size: 15))
                        .foregroundColor(Color(hex: "D4AF37"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Calculation Method Section
struct CalculationMethodSection: View {
    @ObservedObject var viewModel: PrayerTimesViewModel

    var body: some View {
        List {
            Section {
                ForEach(CalculationMethod.allCases, id: \.self) { method in
                    Button(action: {
                        viewModel.selectedMethod = method
                        viewModel.refreshPrayerTimes()
                    }) {
                        HStack {
                            Text(method.rawValue).font(.custom("Georgia", size: 15)).foregroundColor(.white.opacity(0.85))
                            Spacer()
                            if viewModel.selectedMethod == method {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: "D4AF37"))
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
            } header: {
                Text("Calculation Method")
                    .font(.custom("Georgia-Italic", size: 13))
                    .foregroundColor(Color(hex: "D4AF37").opacity(0.8)).textCase(nil)
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundColor(Color(hex: "D4AF37").opacity(0.7))
                    Text("Prayer times are calculated from your GPS location using astronomical formulas. No internet required.")
                        .font(.custom("Georgia-Italic", size: 13)).foregroundColor(.white.opacity(0.5))
                }
                .listRowBackground(Color.white.opacity(0.04))
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Notifications Section
struct NotificationsSection: View {
    @ObservedObject var notificationManager: NotificationManager
    let prayerTimes: [PrayerTime]

    var actionablePrayers: [PrayerTime] {
        prayerTimes.filter { $0.prayer != .sunrise }
    }

    var body: some View {
        List {
            // Permission banner
            if !notificationManager.isAuthorized {
                Section {
                    Button(action: {
                        notificationManager.requestAuthorization()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            notificationManager.checkAuthorization()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color(hex: "D4AF37"))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Enable Notifications").font(.custom("Georgia-Bold", size: 14)).foregroundColor(.white)
                                Text("Tap to allow prayer reminders and adhan alerts.")
                                    .font(.custom("Georgia-Italic", size: 12)).foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .listRowBackground(Color(hex: "1C1A08").opacity(0.8))
                }
            }

            // Per-prayer settings
            Section {
                ForEach(actionablePrayers) { pt in
                    PrayerReminderRow(
                        prayer: pt,
                        settings: notificationManager.reminderSettings[pt.prayer.rawValue] ?? PrayerReminderSettings(),
                        onUpdate: { newSettings in
                            notificationManager.updateSetting(for: pt.prayer.rawValue, settings: newSettings)
                            notificationManager.scheduleNotifications(for: prayerTimes)
                        }
                    )
                    .listRowBackground(Color.white.opacity(0.05))
                }
            } header: {
                Text("Prayer Reminders")
                    .font(.custom("Georgia-Italic", size: 13))
                    .foregroundColor(Color(hex: "D4AF37").opacity(0.8)).textCase(nil)
            }

            // Adhan note
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "speaker.wave.2.fill").foregroundColor(Color(hex: "D4AF37").opacity(0.7))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adhan Sound").font(.custom("Georgia-Bold", size: 13)).foregroundColor(.white.opacity(0.8))
                        Text("Add an audio file named \"adhan.mp3\" to the app bundle to play adhan with notifications. If not present, the default notification sound is used.")
                            .font(.custom("Georgia-Italic", size: 12)).foregroundColor(.white.opacity(0.45))
                    }
                }
                .listRowBackground(Color.white.opacity(0.04))
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Prayer Reminder Row
struct PrayerReminderRow: View {
    let prayer: PrayerTime
    var settings: PrayerReminderSettings
    let onUpdate: (PrayerReminderSettings) -> Void

    @State private var isEnabled: Bool
    @State private var minutesBefore: Int
    @State private var playAdhan: Bool
    @State private var expanded = false

    init(prayer: PrayerTime, settings: PrayerReminderSettings, onUpdate: @escaping (PrayerReminderSettings) -> Void) {
        self.prayer = prayer
        self.settings = settings
        self.onUpdate = onUpdate
        _isEnabled = State(initialValue: settings.isEnabled)
        _minutesBefore = State(initialValue: settings.minutesBefore)
        _playAdhan = State(initialValue: settings.playAdhan)
    }

    var reminderLabel: String {
        minutesBefore == 0 ? "At prayer time" : "\(minutesBefore) min before"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(isEnabled ? Color(hex: "D4AF37").opacity(0.18) : Color.white.opacity(0.05))
                            .frame(width: 36, height: 36)
                        Image(systemName: prayer.prayer.icon)
                            .font(.system(size: 15))
                            .foregroundColor(isEnabled ? Color(hex: "F5D07A") : Color.white.opacity(0.3))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(prayer.prayer.rawValue)
                            .font(.custom("Georgia-Bold", size: 14))
                            .foregroundColor(isEnabled ? .white : .white.opacity(0.4))
                        Text(isEnabled ? reminderLabel : "Off")
                            .font(.custom("Georgia-Italic", size: 11))
                            .foregroundColor(isEnabled ? Color(hex: "D4AF37").opacity(0.7) : Color.white.opacity(0.3))
                    }

                    Spacer()

                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .tint(Color(hex: "D4AF37"))
                        .onChange(of: isEnabled) { _, val in
                            onUpdate(PrayerReminderSettings(isEnabled: val, minutesBefore: minutesBefore, playAdhan: playAdhan))
                        }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)

            // Expanded options
            if expanded && isEnabled {
                VStack(spacing: 14) {
                    Divider().background(Color.white.opacity(0.08))

                    // Minutes before picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remind me")
                            .font(.custom("Georgia-Italic", size: 12))
                            .foregroundColor(.white.opacity(0.45))

                        HStack(spacing: 8) {
                            ForEach([0, 5, 10, 15, 20, 30], id: \.self) { mins in
                                Button(action: {
                                    minutesBefore = mins
                                    onUpdate(PrayerReminderSettings(isEnabled: isEnabled, minutesBefore: mins, playAdhan: playAdhan))
                                }) {
                                    Text(mins == 0 ? "On time" : "\(mins)m")
                                        .font(.custom("Georgia", size: 11))
                                        .foregroundColor(minutesBefore == mins ? Color(hex: "0A0E1A") : Color(hex: "D4AF37"))
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(minutesBefore == mins ? Color(hex: "D4AF37") : Color(hex: "D4AF37").opacity(0.12))
                                        )
                                }
                            }
                        }
                    }

                    // Adhan toggle
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "D4AF37").opacity(0.7))
                        Text("Play Adhan")
                            .font(.custom("Georgia", size: 13))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Toggle("", isOn: $playAdhan)
                            .labelsHidden()
                            .tint(Color(hex: "D4AF37"))
                            .onChange(of: playAdhan) { _, val in
                                onUpdate(PrayerReminderSettings(isEnabled: isEnabled, minutesBefore: minutesBefore, playAdhan: val))
                            }
                    }
                }
                .padding(.bottom, 12)
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: settings) { _, newSettings in
            // Keep local @State in sync if the parent's settings change externally.
            isEnabled = newSettings.isEnabled
            minutesBefore = newSettings.minutesBefore
            playAdhan = newSettings.playAdhan
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

#Preview { ContentView() }
