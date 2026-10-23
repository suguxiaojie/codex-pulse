import AppKit

@MainActor
enum ActivityIslandCompletionAudio {
    static func play(_ tone: ActivityIslandCompletionSound) {
        guard let sound = NSSound(named: NSSound.Name(tone.rawValue)) else { return }
        sound.volume = 0.7
        sound.play()
    }
}
