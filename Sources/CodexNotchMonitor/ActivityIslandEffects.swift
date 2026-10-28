// QuotaView v0.8.2 adapters. Copyright (c) 2026 Duoasa, MIT.
import AppKit
import SwiftUI
import ImageIO

struct CodexActivityTaskIdentity: Equatable { let sessionID: String; let turnID: String? }

enum ActivityIslandPreviewAssets {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()
    static let codexIcon: NSImage? = {
        let bundle = Bundle.main.url(forResource: "Island-Codex", withExtension: "svg")
        let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Island-Codex.svg")
        return NSImage(contentsOf: bundle ?? local)
    }()
    static func image(_ name: String) -> NSImage? {
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        let file = "IslandPreview-" + name
        let bundled = Bundle.main.url(forResource: file, withExtension: "png")
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/\(file).png")
        guard let source = CGImageSourceCreateWithURL((bundled ?? checkout) as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_560,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
        imageCache.setObject(image, forKey: name as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        return image
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
    var replyCueActive = false
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
        (host as? ActivityIslandTaskEffectHost)?.update(row: row, selectedEffect: effect,
            playback: playback, reduceMotion: reduceMotion, replyCueActive: replyCueActive)
    }
    static func dismantleNSView(_ host: NSView, coordinator: ()) {
        (host as? ActivityIslandTaskEffectHost)?.stop()
        (host as? CodexActivityStateSmokePreviewHostView)?.update(effect: .stateSmoke, reduceMotion: true, playbackEnabled: false)
    }
}
