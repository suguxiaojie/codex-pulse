import Foundation
import SwiftUI

enum ActivityIslandMaterial: String, CaseIterable, Identifiable {
    case liquidGlass, classic
    var id: String { rawValue }
    var title: String { self == .liquidGlass ? "液态玻璃" : "经典纯色" }
}

enum ActivityIslandProgressEffect: String, CaseIterable, Identifiable {
    case stateSmoke, dropField, sloshFlow
    var id: String { rawValue }
    var shaderIndex: Float { self == .stateSmoke ? 0 : self == .dropField ? 2 : 3 }
    var title: String { self == .stateSmoke ? "状态烟雾" : self == .dropField ? "量子噪点" : "液态涌浪" }
    var asset: String { self == .stateSmoke ? "StateSmoke" : self == .dropField ? "QuantumNoise" : "LiquidWave" }
}

enum ActivityIslandGlassDegree {
    static func normalized(_ value: Double) -> Double { value.isFinite ? min(0.8, max(0.2, value)) : 0.45 }
    static func gradientStops(_ value: Double) -> [Gradient.Stop] {
        let blackEnd = 1 - normalized(value)
        let fadeEnd = blackEnd + (1 - blackEnd) * 0.7
        return [.init(color: .black, location: 0)] + (0...16).map { index in
            let t = Double(index) / 16
            let eased = t * t * t * (t * (t * 6 - 15) + 10)
            return .init(color: .black.opacity(1 - eased), location: blackEnd + (fadeEnd - blackEnd) * t)
        } + [.init(color: .clear, location: 1)]
    }
}


extension Notification.Name {
    static let activityIslandPreferencesDidChange = Notification.Name(
        "CodexMonitor.activityIslandPreferencesDidChange"
    )

}

enum ActivityIslandPreferenceSignal {
    static func post() {
        NotificationCenter.default.post(
            name: .activityIslandPreferencesDidChange,
            object: nil
        )
    }
}

enum MenuBarInformationDensity: String, CaseIterable, Identifiable {
    case automatic
    case detailed
    case compact
    case iconOnly

    var id: String { rawValue }
    var settingsValue: String { self == .detailed ? Self.automatic.rawValue : rawValue }
    static let settingsCases: [Self] = [.automatic, .compact, .iconOnly]

    var title: String {
        switch self {
        case .automatic: return "自动"
        case .detailed: return "详细"
        case .compact: return "精简"
        case .iconOnly: return "图标"
        }
    }
}

enum MenuBarOverflow: String, CaseIterable, Identifiable {
    case rotate, compact
    var id: String { rawValue }
    var title: String { self == .rotate ? "轮换信息" : "逐级精简" }
    static let preferenceKey = "activityIsland.menuBarOverflow"
}


// Retired settings keys remain readable for compatibility; saved values are never rewritten.
// The status item now always shows quota as a ring and percentage.
struct MenuBarPreferences: Equatable {
    static let densityKey = "activityIsland.menuBarDensity"
    static let activityKey = "menuBar.showsTaskActivity"
    var menuBarDensity: MenuBarInformationDensity = .automatic
    var menuBarOverflow: MenuBarOverflow = .rotate
    var routesTaskStateToMenuBar = false
    static func load(from defaults: UserDefaults = .standard) -> Self { Self() }
}

enum ActivityIslandPreferenceKey {
    static let floatingUsageEnabled = "activityIsland.floatingUsageEnabled"
    static let glassAppearance = "activityIsland.glassAppearance"
    static let usageCapsuleTone = "activityIsland.usageCapsuleTone"
    static let expandedHold = "activityIsland.expandedHold"
    static let material = "activityIsland.material"
    static let glassDegree = "activityIsland.glassDegree"
    static let expandedWidth = "activityIsland.expandedWidth"
    static let privacyMode = "activityIsland.privacyMode"
    static let automaticPopup = "activityIsland.automaticPopup"
    static let progressEffect = "activityIsland.progressEffect"
}

// Adapted from QuotaView v0.8.3 Build 1 AppPreferences (MIT).
enum ActivityIslandGlassAppearance: String, CaseIterable, Identifiable {
    case light, dark, automatic
    var id: String { rawValue }
    var title: String { self == .light ? "浅色" : self == .dark ? "深色" : "自动" }
    func colorScheme(system: ColorScheme, material: ActivityIslandMaterial = .liquidGlass,
                     reduceTransparency: Bool = false) -> ColorScheme {
        guard material == .liquidGlass && !reduceTransparency else { return .dark }
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .automatic: return system
        }
    }
}

struct ActivityIslandPreferences: Equatable {
    var expandedHold: TimeInterval = 3
    var material: ActivityIslandMaterial = .liquidGlass
    var glassDegree: Double = 0.45
    var expandedWidth: Double = 680
    var progressEffect: ActivityIslandProgressEffect = .dropField
    var privacyMode = false
    var automaticPopup = true
    var floatingUsageEnabled = true
    var glassAppearance: ActivityIslandGlassAppearance = .dark
    static let defaults = Self()
    static func normalizedDuration(_ value: Double) -> Double { value.isFinite ? min(10, max(1, value.rounded())) : 3 }
    static func normalizedWidth(_ value: Double) -> Double { value.isFinite ? min(680, max(560, value)) : 680 }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(expandedHold: normalizedDuration(defaults.object(forKey: ActivityIslandPreferenceKey.expandedHold) as? Double ?? 3),
             material: ActivityIslandMaterial(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.material) ?? "") ?? .liquidGlass,
             glassDegree: ActivityIslandGlassDegree.normalized(defaults.object(forKey: ActivityIslandPreferenceKey.glassDegree) as? Double ?? 0.45),
             expandedWidth: normalizedWidth(defaults.object(forKey: ActivityIslandPreferenceKey.expandedWidth) as? Double ?? 680),
             progressEffect: ActivityIslandProgressEffect(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.progressEffect) ?? "") ?? .dropField,
             privacyMode: defaults.object(forKey: ActivityIslandPreferenceKey.privacyMode) as? Bool ?? false,
             automaticPopup: defaults.object(forKey: ActivityIslandPreferenceKey.automaticPopup) as? Bool ?? true,
             floatingUsageEnabled: defaults.object(forKey: ActivityIslandPreferenceKey.floatingUsageEnabled) as? Bool ?? true,
             glassAppearance: ActivityIslandGlassAppearance(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.glassAppearance) ?? "") ?? .dark)
    }
}
