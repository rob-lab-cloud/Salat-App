// SharedModels.swift
// Add this file to BOTH the main app target AND the SalatTimesWidget target
// in Xcode → Target Membership (right panel when file is selected)

import Foundation

// MARK: - Widget Data Bridge
// Shared between main app (writes) and widget (reads) via App Group UserDefaults

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
    // Absolute prayer time - lets the widget flip isNext/isCurrent at the exact
    // minute via timeline entries. Optional so older saved data still decodes.
    var time: Date? = nil
}
