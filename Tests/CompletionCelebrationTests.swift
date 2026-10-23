import Foundation

@main struct CompletionCelebrationTests {
    static func main() {
        let suite = "CompletionCelebrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = ActivityIslandPreferences.load(from: defaults)
        precondition(initial.confettiIntensity == .standard && initial.completionSound && initial.completionSoundName == .glass)
        for intensity in ActivityIslandConfettiIntensity.allCases {
            defaults.set(intensity.rawValue, forKey: ActivityIslandPreferenceKey.confettiIntensity)
            precondition(ActivityIslandPreferences.load(from: defaults).confettiIntensity == intensity)
            let p = intensity.parameters
            precondition(p.cleanupDelay >= p.emissionDuration + Double(p.lifetime) + 0.3 - 0.00001)
        }
        let light = ActivityIslandConfettiIntensity.light.parameters
        precondition(light.emissionDuration == 0.16 && light.birthRate == 55 && light.velocity == 155
            && light.scale == 0.75 && light.lifetime == 1.6 && light.gravity == 180 && light.spin == 4
            && light.alphaSpeed == -0.45 && light.cleanupDelay == 2.2)
        let standard = ActivityIslandConfettiIntensity.standard.parameters
        let festive = ActivityIslandConfettiIntensity.festive.parameters
        precondition(standard.emissionDuration == 0.5 && standard.birthRate == 90 && standard.velocity == 320 && standard.lifetime == 2.6 && standard.scale == 1)
        precondition(festive.emissionDuration == 0.8 && festive.birthRate == 140 && festive.velocity == 420 && festive.lifetime == 3.2 && festive.scale == 1.2)
        for tone in ActivityIslandCompletionSound.allCases {
            defaults.set(tone.rawValue, forKey: ActivityIslandPreferenceKey.completionSoundName)
            precondition(ActivityIslandPreferences.load(from: defaults).completionSoundName == tone)
        }
        defaults.set(false, forKey: ActivityIslandPreferenceKey.completionSound)
        precondition(!ActivityIslandPreferences.load(from: defaults).completionSound)
        defaults.set("invalid", forKey: ActivityIslandPreferenceKey.confettiIntensity)
        defaults.set("invalid", forKey: ActivityIslandPreferenceKey.completionSoundName)
        precondition(ActivityIslandPreferences.load(from: defaults).confettiIntensity == .standard)
        precondition(ActivityIslandPreferences.load(from: defaults).completionSoundName == .glass)
        let now = Date(timeIntervalSince1970: 100)
        func sound(_ elapsed: Double, baseline: Bool = false, enabled: Bool = true, visible: Bool = true) -> Bool {
            ActivityIslandCompletionSound.shouldPlay(now: now.addingTimeInterval(elapsed), lastPlayedAt: now,
                baseline: baseline, enabled: enabled, islandVisible: visible)
        }
        precondition(!sound(0) && !sound(1.999) && sound(2) && !sound(-1))
        precondition(!sound(3, baseline: true) && !sound(3, enabled: false) && !sound(3, visible: false))
        precondition(ActivityIslandCompletionSound.shouldPlay(now: now, lastPlayedAt: nil, baseline: false, enabled: true, islandVisible: true))
        for status in [QuotaNotificationStatus.unknown, .enabled, .denied] {
            for signals in [false, true] {
                for recovery in [false, true] {
                    precondition(NotificationAuthorizationPolicy.shouldRequest(status: status, signals: signals, recovery: recovery)
                        == (status == .unknown && (signals || recovery)))
                }
            }
        }
        print("CompletionCelebrationTests passed: preferences, 3 parameter profiles, sound throttle, 12 authorization cases")
    }
}
