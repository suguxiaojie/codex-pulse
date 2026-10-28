import AppKit
import Foundation
import SwiftUI

@main
struct ActivityIslandPreferencesTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        if !condition() { fatalError(message) }
    }
    static func main() {
        let suite = "ActivityIslandPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(ActivityIslandPreferences.load(from: defaults) == .defaults, "missing preferences use upstream defaults")
        expect(ActivityIslandPreferences.defaults.floatingUsageEnabled && ActivityIslandPreferences.defaults.glassAppearance == .dark,
            "unified glass appearance defaults to dark")
        defaults.set(false, forKey: ActivityIslandPreferenceKey.floatingUsageEnabled)
        defaults.set("light", forKey: "activityIsland.usageCapsuleTone") // retired key, never read
        expect(!ActivityIslandPreferences.load(from: defaults).floatingUsageEnabled && ActivityIslandPreferences.load(from: defaults).glassAppearance == .dark,
            "legacy capsule light does not expand to the footer")
        expect(defaults.string(forKey: "activityIsland.usageCapsuleTone") == "light", "legacy preference remains intact")
        for appearance in ActivityIslandGlassAppearance.allCases {
            defaults.set(appearance.rawValue, forKey: ActivityIslandPreferenceKey.glassAppearance)
            expect(ActivityIslandPreferences.load(from: defaults).glassAppearance == appearance, "new appearance persists")
            expect(appearance.colorScheme(system: .light, material: .classic) == .dark, "classic fallback stays dark")
            expect(appearance.colorScheme(system: .light, reduceTransparency: true) == .dark, "reduced transparency stays dark")
        }
        expect(ActivityIslandGlassAppearance.automatic.colorScheme(system: .light) == .light, "auto resolves system light")
        expect(ActivityIslandGlassAppearance.automatic.colorScheme(system: .dark) == .dark, "auto resolves system dark")
        expect(ActivityIslandGlassAppearance.dark.colorScheme(system: .light) == .dark, "fixed dark ignores system")
        expect(ActivityIslandGlassAppearance.light.colorScheme(system: .dark) == .light, "fixed light ignores system")
        defaults.set("unknown", forKey: ActivityIslandPreferenceKey.glassAppearance)
        expect(ActivityIslandPreferences.load(from: defaults).glassAppearance == .dark, "invalid appearance falls back to dark")
        defaults.removeObject(forKey: ActivityIslandPreferenceKey.floatingUsageEnabled)
        defaults.removeObject(forKey: ActivityIslandPreferenceKey.glassAppearance)
        expect(ActivityIslandPreferences.defaults.effectQuality == .balanced, "effect quality defaults to balanced")
        expect(ActivityIslandEffectQuality.allCases.map(\.framesPerSecond) == [60, 30, 24]
               && ActivityIslandEffectQuality.allCases.map(\.fullSurfaceFramesPerSecond) == [60, 30, 24]
               && ActivityIslandEffectQuality.allCases.map(\.resolutionScale) == [1, 0.75, 0.5], "quality tiers match the agreed values")
        defaults.set("smooth", forKey: ActivityIslandPreferenceKey.effectQuality)
        expect(ActivityIslandPreferences.load(from: defaults).effectQuality == .smooth, "effect quality persists")
        defaults.set("ultra", forKey: ActivityIslandPreferenceKey.effectQuality)
        expect(ActivityIslandPreferences.load(from: defaults).effectQuality == .balanced, "invalid effect quality falls back to balanced")
        defaults.removeObject(forKey: ActivityIslandPreferenceKey.effectQuality)
        let pet = ActivityIslandPreferences.defaults
        expect(pet.clawdEnabled && pet.clawdSize == .medium, "Clawd defaults on, medium")
        expect(IslandClawdSize.allCases.map(\.pixel) == [1.6, 2.2, 2.8], "Clawd sizes match the 18/24/31 pt design")
        defaults.set(false, forKey: ActivityIslandPreferenceKey.clawdEnabled)
        defaults.set("large", forKey: ActivityIslandPreferenceKey.clawdSize)
        let loaded = ActivityIslandPreferences.load(from: defaults)
        expect(!loaded.clawdEnabled && loaded.clawdSize == .large, "Clawd preferences persist")
        defaults.set("huge", forKey: ActivityIslandPreferenceKey.clawdSize)
        expect(ActivityIslandPreferences.load(from: defaults).clawdSize == .medium, "invalid Clawd size falls back to medium")
        for key in [ActivityIslandPreferenceKey.clawdEnabled, ActivityIslandPreferenceKey.clawdSize] {
            defaults.removeObject(forKey: key)
        }
        // Settings consolidation: attention sound, expand trigger, display, capsule style, confetti off, reset keys.
        let fresh = ActivityIslandPreferences.defaults
        expect(fresh.attentionSound == .ping && fresh.expandTrigger == .hover && fresh.displayTarget == .automatic,
               "new settings default to ping, hover and automatic display")
        defaults.set("off", forKey: ActivityIslandPreferenceKey.attentionSound)
        expect(ActivityIslandPreferences.load(from: defaults).attentionSound == nil, "attention sound can be turned off")
        defaults.set("Hero", forKey: ActivityIslandPreferenceKey.attentionSound)
        expect(ActivityIslandPreferences.load(from: defaults).attentionSound == .hero, "attention tone persists")
        defaults.set("click", forKey: ActivityIslandPreferenceKey.expandTrigger)
        defaults.set("main", forKey: ActivityIslandPreferenceKey.displayTarget)
        let chosen = ActivityIslandPreferences.load(from: defaults)
        expect(chosen.expandTrigger == .click && chosen.displayTarget == .main, "expand trigger and display persist")
        defaults.set("tap", forKey: ActivityIslandPreferenceKey.expandTrigger)
        defaults.set("left", forKey: ActivityIslandPreferenceKey.displayTarget)
        let invalid = ActivityIslandPreferences.load(from: defaults)
        expect(invalid.expandTrigger == .hover && invalid.displayTarget == .automatic, "invalid trigger and display fall back")
        defaults.set("display:1552-41178-0", forKey: ActivityIslandPreferenceKey.displayTarget)
        expect(ActivityIslandPreferences.load(from: defaults).displayTarget == .display("1552-41178-0"), "a specific display persists")
        defaults.set("display:", forKey: ActivityIslandPreferenceKey.displayTarget)
        expect(ActivityIslandPreferences.load(from: defaults).displayTarget == .automatic, "empty display identity falls back")
        expect(IslandDisplayInfo.screen(for: .display("missing-display")) == nil, "a disconnected display yields no screen")
        let connected = IslandDisplayInfo.connected()
        expect(connected.count == NSScreen.screens.count && Set(connected.map(\.id)).count == connected.count
               && connected.filter(\.isMain).count == min(1, connected.count), "connected displays have unique identities and one main")
        for style in ActivityIslandCapsuleStyle.allCases {
            expect(ActivityIslandCapsuleStyle.current(material: style.material, appearance: style.appearance ?? .dark) == style,
                   "capsule style round-trips through material and appearance")
        }
        defaults.set("off", forKey: ActivityIslandPreferenceKey.confettiIntensity)
        expect(ActivityIslandPreferences.load(from: defaults).confettiIntensity == .off
               && !ActivityIslandConfettiIntensity.playable.contains(.off), "confetti can be turned off")
        expect(Set(ActivityIslandPreferenceKey.all).count == ActivityIslandPreferenceKey.all.count
               && ActivityIslandPreferenceKey.all.allSatisfy { $0.hasPrefix("activityIsland.") }, "reset touches only island keys")
        for key in ActivityIslandPreferenceKey.all { defaults.removeObject(forKey: key) }
        expect(ActivityIslandPreferences.load(from: defaults) == .defaults, "reset restores every default")
        // Deliberately hostile legacy values must not affect the new island.
        let retired: [String: Any] = ["enabled": false, "mode": "menuBar", "screen": "main", "position": "trailing",
            "visualStyle": "particleOrb", "surfaceOpacity": 0.1, "surfaceScale": 0.25,
            "compactHide": 120, "reduceMotion": true, "showCompletion": false]
        for (key, value) in retired {
            defaults.set(value, forKey: "activityIsland." + key)
            expect(ActivityIslandPreferences.load(from: defaults) == .defaults, "retired \(key) no longer changes runtime preferences")
        }
        defaults.set("detailed", forKey: MenuBarPreferences.densityKey)
        defaults.set("compact", forKey: MenuBarOverflow.preferenceKey)
        defaults.set(true, forKey: MenuBarPreferences.activityKey)
        let menu = MenuBarPreferences.load(from: defaults)
        expect(menu.menuBarDensity == .automatic && menu.menuBarOverflow == .rotate && !menu.routesTaskStateToMenuBar,
               "retired task and density preferences cannot change ring and percentage display")
        expect(MenuBarInformationDensity.detailed.settingsValue == MenuBarInformationDensity.automatic.rawValue,
               "legacy detailed selection maps to the single automatic settings option")
        expect(!MenuBarInformationDensity.settingsCases.contains(.detailed) && MenuBarInformationDensity.settingsCases.count == 3,
               "settings do not expose two choices with identical behavior")
        expect(defaults.string(forKey: MenuBarPreferences.densityKey) == "detailed", "display alias does not rewrite the saved preference")
        expect(ActivityIslandPreferences.load(from: defaults) == .defaults, "menu-bar settings cannot hide or scale the island")
        defaults.set(true, forKey: ActivityIslandPreferenceKey.privacyMode)
        defaults.set(false, forKey: ActivityIslandPreferenceKey.automaticPopup)
        defaults.set("classic", forKey: ActivityIslandPreferenceKey.material)
        defaults.set("sloshFlow", forKey: ActivityIslandPreferenceKey.progressEffect)
        defaults.set(60.0, forKey: ActivityIslandPreferenceKey.expandedHold)
        defaults.set(900.0, forKey: ActivityIslandPreferenceKey.expandedWidth)
        defaults.set(2.0, forKey: ActivityIslandPreferenceKey.glassDegree)
        let changed = ActivityIslandPreferences.load(from: defaults)
        expect(changed.privacyMode && !changed.automaticPopup && changed.material == .classic && changed.progressEffect == .sloshFlow,
               "all current configuration choices persist")
        expect(changed.expandedHold == 10 && changed.expandedWidth == 680 && changed.glassDegree == 0.8, "upstream upper bounds enforced")
        expect(MenuBarPreferences.load(from: defaults) == menu, "island configuration preserves other settings")
        expect(ActivityIslandPreferences.normalizedWidth(.nan) == 680, "invalid width uses default")
        expect(ActivityIslandPreferences.normalizedWidth(-1) == 560, "width lower bound enforced")
        expect(ActivityIslandPreferences.normalizedDuration(.infinity) == 3, "invalid timing uses default")
        expect(ActivityIslandPreferences.normalizedDuration(3.6) == 4, "timing uses whole seconds")
        expect(ActivityIslandPreferences.normalizedDuration(-1) == 1, "timing lower bound enforced")
        expect(ActivityIslandGlassDegree.normalized(.nan) == 0.45, "invalid glass degree uses default")
        defaults.set("retired", forKey: ActivityIslandPreferenceKey.progressEffect)
        expect(ActivityIslandPreferences.load(from: defaults).progressEffect == .dropField, "unknown effect uses upstream default")
        print("Activity Island preference tests passed: \(count)")
    }
}
