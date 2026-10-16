// QuotaView v0.8.2 adapters. Copyright (c) 2026 Duoasa, MIT.
import AppKit
import SwiftUI

struct CodexActivityTaskIdentity: Equatable { let sessionID: String; let turnID: String? }

enum ActivityIslandPreviewAssets {
    static let codexIcon: NSImage? = {
        let bundle = Bundle.main.url(forResource: "Island-Codex", withExtension: "svg")
        let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Island-Codex.svg")
        return NSImage(contentsOf: bundle ?? local)
    }()
    static func image(_ name: String) -> NSImage? {
        let file = "IslandPreview-" + name
        let bundled = Bundle.main.url(forResource: file, withExtension: "png")
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/\(file).png")
        return (bundled ?? checkout).path.isEmpty ? nil : NSImage(contentsOf: bundled ?? checkout)
    }
}

/// Production uses QuotaView's complete state-driven renderer and cached Metal
/// pipeline. The wave is decorative and never presented as a completion percent.
struct ActivityIslandTaskEffect: NSViewRepresentable {
    let row: ActivitySessionSnapshot
    let effect: ActivityIslandProgressEffect
    let playback: Bool
    let reduceMotion: Bool
    var preview = false
    func makeNSView(context: Context) -> NSView {
        if preview { return CodexActivityStateSmokePreviewHostView(effect: effect) }
        return ActivityIslandTaskEffectHost(frame: .zero)
    }
    func updateNSView(_ host: NSView, context: Context) {
        if let view = host as? CodexActivityStateSmokePreviewHostView {
            view.update(effect: effect, reduceMotion: reduceMotion, cornerRadius: 16, playbackEnabled: playback)
            view.setFallbackImage(ActivityIslandPreviewAssets.image(effect.asset))
            return
        }
        (host as? ActivityIslandTaskEffectHost)?.update(row: row, selectedEffect: effect, playback: playback, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ host: NSView, coordinator: ()) {
        (host as? ActivityIslandTaskEffectHost)?.stop()
        (host as? CodexActivityStateSmokePreviewHostView)?.update(effect: .stateSmoke, reduceMotion: true, playbackEnabled: false)
    }
}
