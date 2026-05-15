import WidgetKit
import SwiftUI

// MARK: - Shared data store (App Group)
// In Xcode, add App Group "group.com.salatimes.app" to both targets.
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
    var timeString: String     // "5:23 AM"
    var isNext: Bool
    var isCurrent: Bool
    var iconName: String
}

func loadWidgetData() -> WidgetPrayerData? {
    guard let raw  = UserDefaults(suiteName: appGroupID)?.data(forKey: "widgetData"),
          let data = try? JSONDecoder().decode(WidgetPrayerData.self, from: raw) else { return nil }
    return data
}

// MARK: - Timeline Entry
struct SalatEntry: TimelineEntry {
    let date: Date
    let data: WidgetPrayerData?
}

// MARK: - Provider
struct SalatProvider: TimelineProvider {
    func placeholder(in context: Context) -> SalatEntry {
        SalatEntry(date: Date(), data: sampleData())
    }

    func getSnapshot(in context: Context, completion: @escaping (SalatEntry) -> Void) {
        completion(SalatEntry(date: Date(), data: loadWidgetData() ?? sampleData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SalatEntry>) -> Void) {
        let entry = SalatEntry(date: Date(), data: loadWidgetData() ?? sampleData())
        // Refresh every 30 min so next/current stays accurate
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func sampleData() -> WidgetPrayerData {
        WidgetPrayerData(
            locationName: "Your City",
            prayers: [
                WidgetPrayer(name: "Fajr",    arabicName: "الفجر", timeString: "5:12 AM",  isNext: false, isCurrent: false, iconName: "moon.stars.fill"),
                WidgetPrayer(name: "Sunrise",  arabicName: "الشروق", timeString: "6:38 AM", isNext: false, isCurrent: false, iconName: "sunrise.fill"),
                WidgetPrayer(name: "Dhuhr",   arabicName: "الظهر", timeString: "12:15 PM", isNext: true,  isCurrent: false, iconName: "sun.max.fill"),
                WidgetPrayer(name: "Asr",     arabicName: "العصر", timeString: "3:44 PM",  isNext: false, isCurrent: false, iconName: "sun.haze.fill"),
                WidgetPrayer(name: "Maghrib", arabicName: "المغرب", timeString: "6:18 PM", isNext: false, isCurrent: false, iconName: "sunset.fill"),
                WidgetPrayer(name: "Isha",    arabicName: "العشاء", timeString: "7:46 PM",  isNext: false, isCurrent: false, iconName: "moon.fill"),
            ],
            updatedAt: Date()
        )
    }
}

// MARK: - Widget Views

// Small widget: next prayer
struct SmallWidgetView: View {
    let data: WidgetPrayerData?

    var next: WidgetPrayer? { data?.prayers.first(where: { $0.isNext }) }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.055, blue: 0.102)  // #0A0E1A

            LinearGradient(
                colors: [Color(red: 0.1, green: 0.14, blue: 0.27).opacity(0.9), .clear],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8))
                        .foregroundColor(goldColor)
                    Text(data?.locationName ?? "—")
                        .font(.custom("Georgia", size: 9))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                if let p = next {
                    Image(systemName: p.iconName)
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(colors: [goldLight, goldDark], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: goldColor.opacity(0.5), radius: 6)

                    Text(p.name)
                        .font(.custom("Georgia-Bold", size: 15))
                        .foregroundColor(.white)

                    Text(p.arabicName)
                        .font(.custom("Georgia", size: 10))
                        .foregroundColor(goldColor.opacity(0.7))

                    Text(p.timeString)
                        .font(.system(size: 20, weight: .thin))
                        .foregroundStyle(
                            LinearGradient(colors: [goldLight, goldDark], startPoint: .leading, endPoint: .trailing)
                        )

                    Label("Next", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(goldColor.opacity(0.8))
                } else {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 22))
                        .foregroundColor(goldColor.opacity(0.5))
                    Text("Loading...")
                        .font(.custom("Georgia-Italic", size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// Medium widget: all 6 prayers in two columns
struct MediumWidgetView: View {
    let data: WidgetPrayerData?

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.055, blue: 0.102)

            LinearGradient(
                colors: [Color(red: 0.1, green: 0.14, blue: 0.27).opacity(0.8), .clear],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                        .foregroundColor(goldColor)
                    Text(data?.locationName ?? "—")
                        .font(.custom("Georgia", size: 10))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("Salat Times")
                        .font(.custom("Georgia-Italic", size: 10))
                        .foregroundColor(goldColor.opacity(0.7))
                }
                .padding(.bottom, 8)

                // Two columns
                let prayers = data?.prayers ?? []
                let half = prayers.count / 2
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 5) {
                        ForEach(prayers.prefix(half)) { p in
                            PrayerMiniRow(prayer: p)
                        }
                    }
                    VStack(spacing: 5) {
                        ForEach(prayers.suffix(from: half)) { p in
                            PrayerMiniRow(prayer: p)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

struct PrayerMiniRow: View {
    let prayer: WidgetPrayer

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: prayer.iconName)
                .font(.system(size: 10))
                .foregroundColor(prayer.isNext ? goldLight : prayer.isCurrent ? Color(hex: "7ED89A") : .white.opacity(0.35))
                .frame(width: 14)

            Text(prayer.name)
                .font(.custom("Georgia", size: 10))
                .foregroundColor(prayer.isNext ? .white : prayer.isCurrent ? Color(hex: "7ED89A") : .white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(prayer.timeString)
                .font(.system(size: 10, weight: prayer.isNext ? .semibold : .light))
                .foregroundColor(prayer.isNext ? goldLight : prayer.isCurrent ? Color(hex: "7ED89A") : .white.opacity(0.45))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(prayer.isNext
                    ? Color(red: 0.11, green: 0.11, blue: 0.05).opacity(0.8)
                    : prayer.isCurrent
                        ? Color(red: 0.04, green: 0.1, blue: 0.06).opacity(0.8)
                        : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(prayer.isNext ? goldColor.opacity(0.35) : .clear, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Color helpers (Widget can't use extensions with hex strings in some Xcode versions)
private let goldColor = Color(red: 0.831, green: 0.686, blue: 0.216)  // #D4AF37
private let goldLight = Color(red: 0.961, green: 0.816, blue: 0.478)  // #F5D07A
private let goldDark  = Color(red: 0.722, green: 0.525, blue: 0.043)  // #B8860B

// MARK: - Widget Definition
@main
struct SalatTimesWidget: Widget {
    let kind = "SalatTimesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SalatProvider()) { entry in
            SalatWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Salat Times")
        .description("Prayer times at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SalatWidgetEntryView: View {
    let entry: SalatEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(data: entry.data)
        case .systemMedium: MediumWidgetView(data: entry.data)
        default:            SmallWidgetView(data: entry.data)
        }
    }
}

// Needed for MediumWidgetView Color(hex:) usage  
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
