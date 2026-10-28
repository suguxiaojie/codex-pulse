import AppKit
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
    static let confettiIntensity = "activityIsland.confettiIntensity"
    static let completionSound = "activityIsland.completionSound"
    static let completionSoundName = "activityIsland.completionSoundName"
    static let floatingUsageEnabled = "activityIsland.floatingUsageEnabled"
    static let glassAppearance = "activityIsland.glassAppearance"
    static let expandedHold = "activityIsland.expandedHold"
    static let material = "activityIsland.material"
    static let glassDegree = "activityIsland.glassDegree"
    static let expandedWidth = "activityIsland.expandedWidth"
    static let privacyMode = "activityIsland.privacyMode"
    static let automaticPopup = "activityIsland.automaticPopup"
    static let progressEffect = "activityIsland.progressEffect"
    static let effectQuality = "activityIsland.effectQuality"
    static let clawdEnabled = "activityIsland.clawdEnabled"
    static let clawdSize = "activityIsland.clawdSize"
    static let attentionSound = "activityIsland.attentionSound"
    static let expandTrigger = "activityIsland.expandTrigger"
    static let displayTarget = "activityIsland.displayTarget"
    /// Every key the settings page owns; "恢复默认" removes exactly these.
    static let all = [confettiIntensity, completionSound, completionSoundName, floatingUsageEnabled, glassAppearance,
                      expandedHold, material, glassDegree, expandedWidth, privacyMode, automaticPopup, progressEffect,
                      effectQuality, clawdEnabled, clawdSize, attentionSound, expandTrigger, displayTarget]
}

/// How the compact island opens when the pointer reaches it.
enum ActivityIslandExpandTrigger: String, CaseIterable, Identifiable {
    case hover, click
    var id: String { rawValue }
    var title: String { self == .hover ? "悬停" : "点击" }
}

/// Which display hosts the island: a policy, or one specific display by its hardware identity.
enum ActivityIslandDisplayTarget: Equatable {
    case automatic, main
    case display(String)
    init?(rawValue: String) {
        switch rawValue {
        case "automatic": self = .automatic
        case "main": self = .main
        default:
            guard rawValue.hasPrefix("display:"), rawValue.count > 8 else { return nil }
            self = .display(String(rawValue.dropFirst(8)))
        }
    }
    var rawValue: String {
        switch self {
        case .automatic: return "automatic"
        case .main: return "main"
        case .display(let id): return "display:" + id
        }
    }
}

/// A connected display as the settings page and the presenter see it.
struct IslandDisplayInfo: Equatable, Identifiable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let hasNotch: Bool
    let isMain: Bool
    var kindTitle: String {
        ([isBuiltIn ? "内建" : "外接"] + (hasNotch ? ["刘海"] : []) + (isMain ? ["主显示器"] : [])).joined(separator: " · ")
    }
    /// Vendor, model and serial survive reconnects and port changes; the session-scoped number is the last resort.
    static func identity(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return "unknown" }
        let display = CGDirectDisplayID(number.uint32Value)
        let serial = CGDisplaySerialNumber(display)
        return "\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(serial == 0 ? "n\(display)" : String(serial))"
    }
    static func connected() -> [Self] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return Self(id: identity(of: screen), name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(number) != 0,
                        hasNotch: screen.safeAreaInsets.top > 0, isMain: index == 0)
        }
    }
    static func screen(for target: ActivityIslandDisplayTarget) -> NSScreen? {
        switch target {
        case .automatic: return nil
        case .main: return NSScreen.screens.first // The display that carries the menu bar.
        case .display(let id): return NSScreen.screens.first { identity(of: $0) == id }
        }
    }
}

/// Capsule material and appearance shown as one choice; stored in the two existing keys.
enum ActivityIslandCapsuleStyle: String, CaseIterable, Identifiable {
    case darkGlass, lightGlass, systemGlass, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .darkGlass: return "深色玻璃"
        case .lightGlass: return "浅色玻璃"
        case .systemGlass: return "跟随系统"
        case .solid: return "纯色"
        }
    }
    var material: ActivityIslandMaterial { self == .solid ? .classic : .liquidGlass }
    var appearance: ActivityIslandGlassAppearance? {
        switch self {
        case .darkGlass: return .dark
        case .lightGlass: return .light
        case .systemGlass: return .automatic
        case .solid: return nil
        }
    }
    static func current(material: ActivityIslandMaterial, appearance: ActivityIslandGlassAppearance) -> Self {
        guard material == .liquidGlass else { return .solid }
        return appearance == .light ? .lightGlass : appearance == .automatic ? .systemGlass : .darkGlass
    }
}

/// Task-card Metal effect quality: frame rate and drawable scale (fraction of the display's backing pixels).
enum ActivityIslandEffectQuality: String, CaseIterable, Identifiable {
    case smooth, balanced, saver
    var id: String { rawValue }
    var title: String { self == .smooth ? "流畅" : self == .balanced ? "均衡" : "省电" }
    var framesPerSecond: Int { self == .smooth ? 60 : self == .balanced ? 30 : 24 }
    /// Task cards now always fill the whole card, so full-surface uses the same rate as the tier.
    var fullSurfaceFramesPerSecond: Int { framesPerSecond }
    var resolutionScale: CGFloat { self == .smooth ? 1 : self == .balanced ? 0.75 : 0.5 }
}

/// Hanging Clawd size; one sprite pixel in points (companions use half).
enum IslandClawdSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { self == .small ? "小" : self == .medium ? "中" : "大" }
    var pixel: CGFloat { self == .small ? 1.6 : self == .medium ? 2.2 : 2.8 }
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
    var confettiIntensity: ActivityIslandConfettiIntensity = .standard
    var completionSound = true
    var completionSoundName: ActivityIslandCompletionSound = .glass
    var expandedHold: TimeInterval = 3
    var material: ActivityIslandMaterial = .liquidGlass
    var glassDegree: Double = 0.45
    var expandedWidth: Double = 680
    var progressEffect: ActivityIslandProgressEffect = .dropField
    var privacyMode = false
    var automaticPopup = true
    var floatingUsageEnabled = true
    var glassAppearance: ActivityIslandGlassAppearance = .dark
    var effectQuality: ActivityIslandEffectQuality = .balanced
    var clawdEnabled = true
    var clawdSize: IslandClawdSize = .medium
    /// nil keeps approvals and questions silent.
    var attentionSound: ActivityIslandCompletionSound? = .ping
    var expandTrigger: ActivityIslandExpandTrigger = .hover
    var displayTarget: ActivityIslandDisplayTarget = .automatic
    static let defaults = Self()
    static func normalizedDuration(_ value: Double) -> Double { value.isFinite ? min(10, max(1, value.rounded())) : 3 }
    static func normalizedWidth(_ value: Double) -> Double { value.isFinite ? min(680, max(560, value)) : 680 }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(confettiIntensity: ActivityIslandConfettiIntensity(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.confettiIntensity) ?? "") ?? .standard,
             completionSound: defaults.object(forKey: ActivityIslandPreferenceKey.completionSound) as? Bool ?? true,
             completionSoundName: ActivityIslandCompletionSound(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.completionSoundName) ?? "") ?? .glass,
             expandedHold: normalizedDuration(defaults.object(forKey: ActivityIslandPreferenceKey.expandedHold) as? Double ?? 3),
             material: ActivityIslandMaterial(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.material) ?? "") ?? .liquidGlass,
             glassDegree: ActivityIslandGlassDegree.normalized(defaults.object(forKey: ActivityIslandPreferenceKey.glassDegree) as? Double ?? 0.45),
             expandedWidth: normalizedWidth(defaults.object(forKey: ActivityIslandPreferenceKey.expandedWidth) as? Double ?? 680),
             progressEffect: ActivityIslandProgressEffect(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.progressEffect) ?? "") ?? .dropField,
             privacyMode: defaults.object(forKey: ActivityIslandPreferenceKey.privacyMode) as? Bool ?? false,
             automaticPopup: defaults.object(forKey: ActivityIslandPreferenceKey.automaticPopup) as? Bool ?? true,
             floatingUsageEnabled: defaults.object(forKey: ActivityIslandPreferenceKey.floatingUsageEnabled) as? Bool ?? true,
             glassAppearance: ActivityIslandGlassAppearance(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.glassAppearance) ?? "") ?? .dark,
             effectQuality: ActivityIslandEffectQuality(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.effectQuality) ?? "") ?? .balanced,
             clawdEnabled: defaults.object(forKey: ActivityIslandPreferenceKey.clawdEnabled) as? Bool ?? true,
             clawdSize: IslandClawdSize(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.clawdSize) ?? "") ?? .medium,
             attentionSound: defaults.string(forKey: ActivityIslandPreferenceKey.attentionSound).map {
                 ActivityIslandCompletionSound(rawValue: $0) } ?? .ping,
             expandTrigger: ActivityIslandExpandTrigger(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.expandTrigger) ?? "") ?? .hover,
             displayTarget: ActivityIslandDisplayTarget(rawValue: defaults.string(forKey: ActivityIslandPreferenceKey.displayTarget) ?? "") ?? .automatic)
    }
}

// List retention is independent of compact receipt and automatic expansion timing.
enum ActivityIslandSessionRetention { static let duration: TimeInterval = 60 }
enum ActivityIslandFocusHandoff { static let duration: TimeInterval = 3 }

// Value-only completion policy shared by runtime and isolated tests.
enum ActivityIslandConfettiIntensity: String, CaseIterable, Identifiable {
    case off, light, standard, festive
    var id: String { rawValue }
    var title: String { self == .off ? "关闭" : self == .light ? "轻" : self == .standard ? "标准" : "热烈" }
    /// Bursts that actually play; `off` never emits.
    static let playable: [Self] = [.light, .standard, .festive]
    var parameters: ActivityIslandConfettiParameters {
        switch self {
        case .off, .light: return .init(emissionDuration: 0.16, birthRate: 55, velocity: 155, scale: 0.75, lifetime: 1.6, gravity: 180, spin: 4, alphaSpeed: -0.45, cleanupDelay: 2.2)
        case .standard: return .init(emissionDuration: 0.5, birthRate: 90, velocity: 320, scale: 1, lifetime: 2.6, gravity: 240, spin: 6, alphaSpeed: -0.25, cleanupDelay: 3.5)
        case .festive: return .init(emissionDuration: 0.8, birthRate: 140, velocity: 420, scale: 1.2, lifetime: 3.2, gravity: 280, spin: 8, alphaSpeed: -0.2, cleanupDelay: 4.4)
        }
    }
}
struct ActivityIslandConfettiParameters: Equatable {
    let emissionDuration: Double
    let birthRate: Float
    let velocity: CGFloat
    let scale: CGFloat
    let lifetime: Float
    let gravity: CGFloat
    let spin: CGFloat
    let alphaSpeed: Float
    let cleanupDelay: Double
}
enum ActivityIslandCompletionSound: String, CaseIterable, Identifiable {
    case glass = "Glass", hero = "Hero", ping = "Ping", purr = "Purr", submarine = "Submarine"
    var id: String { rawValue }
    static func shouldPlay(now: Date, lastPlayedAt: Date?, baseline: Bool, enabled: Bool, islandVisible: Bool) -> Bool {
        !baseline && enabled && islandVisible && (lastPlayedAt.map { now.timeIntervalSince($0) >= 2 } ?? true)
    }
}
