// Adapted from QuotaView/IslandTaskScrolling.swift (MIT), Copyright (c) 2026 Duoasa.
// Pinned source and license: Resources/ThirdPartyNotices.txt.
import AppKit
import SwiftUI

@MainActor
final class ActivityIslandRowVisibility: ObservableObject {
    @Published var sessionIDs: Set<String> = []
}

struct ActivityIslandRowsDocument: View {
    let rows: [ActivitySessionSnapshot]
    let playback: Bool
    let width: CGFloat
    let rowHeight: CGFloat
    var effect: ActivityIslandProgressEffect = .stateSmoke
    var focusedID: String?
    var reduceMotion = false
    var onSelect: ((String) -> Void)?
    var liquidGlassEnabled = true
    var glassActive = true
    @ObservedObject var visibility: ActivityIslandRowVisibility
    var body: some View {
        VStack(spacing: ActivityIslandListLayout.rowSpacing) {
            ForEach(rows) { row in
                Group {
                    if let onSelect {
                        Button { onSelect(row.id) } label: { card(row) }.buttonStyle(.plain)
                    } else { card(row) }
                }
            }
        }.padding(.vertical, ActivityIslandListLayout.verticalInset)
            .frame(width: width).transaction { $0.animation = nil }
            .environment(\.islandLiquidGlassEnabled, liquidGlassEnabled)
            .environment(\.islandGlassActive, glassActive)
            .environment(\.colorScheme, .dark)
    }
    private func card(_ row: ActivitySessionSnapshot) -> some View {
        ActivityIslandTaskCard(row: row,
            animated: playback && visibility.sessionIDs.contains(row.id), rowHeight: rowHeight,
            selected: (focusedID ?? rows.first?.id) == row.id, effect: effect, reduceMotion: reduceMotion)
    }
}

struct ActivityIslandTaskScroll: NSViewRepresentable {
    @Environment(\.islandLiquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.islandGlassActive) private var glassActive
    let rows: [ActivitySessionSnapshot]
    let playback: Bool
    let rowHeight: CGFloat
    var onInteraction: (() -> Void)?
    var effect: ActivityIslandProgressEffect = .stateSmoke
    var focusedID: String?
    var reduceMotion = false
    var onSelect: ((String) -> Void)?
    func makeNSView(context: Context) -> ActivityIslandNativeScroll { ActivityIslandNativeScroll() }
    func updateNSView(_ view: ActivityIslandNativeScroll, context: Context) {
        view.configure(rows: rows, playback: playback, rowHeight: rowHeight,
                       onInteraction: onInteraction, effect: effect, focusedID: focusedID,
                       reduceMotion: reduceMotion, onSelect: onSelect,
                       liquidGlassEnabled: liquidGlassEnabled, glassActive: glassActive)
    }
    static func dismantleNSView(_ view: ActivityIslandNativeScroll, coordinator: ()) { view.stop() }
}

/// Native gestures retain their own momentum. Only structural updates restore
/// a one-shot row anchor; visibility publishes on row boundaries, not per pixel.
@MainActor
final class ActivityIslandNativeScroll: NSScrollView {
    let visibility = ActivityIslandRowVisibility()
    private var rows: [ActivitySessionSnapshot] = []
    private var playback = false
    private(set) var listLayout = ActivityIslandListLayout(sessionIDs: [])
    private(set) var host: NSHostingView<ActivityIslandRowsDocument>!
    private var observations: [NSObjectProtocol] = []
    private var visibilityWork: DispatchWorkItem?
    private var scheduledVisibility: Set<String>?
    private var documentWidth: CGFloat = 0
    var onInteraction: (() -> Void)?
    private var effect: ActivityIslandProgressEffect = .stateSmoke
    private var focusedID: String?
    private var reduceMotion = false
    private var liquidGlassEnabled = true
    private var glassActive = true
    private var onSelect: ((String) -> Void)?

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        host = NSHostingView(rootView: ActivityIslandRowsDocument(rows: [], playback: false,
            width: 1, rowHeight: 70, visibility: visibility))
        host.sizingOptions = []
        documentView = host
        contentView.postsBoundsChangedNotifications = true
        for (name, object) in [(NSView.boundsDidChangeNotification, contentView as AnyObject),
                               (NSWindow.didChangeOcclusionStateNotification, NSApp as AnyObject),
                               (NSApplication.didHideNotification, NSApp as AnyObject),
                               (NSApplication.didUnhideNotification, NSApp as AnyObject)] {
            observations.append(NotificationCenter.default.addObserver(forName: name,
                object: name == NSWindow.didChangeOcclusionStateNotification ? nil : object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.publishVisibility() }
                })
        }
        setAccessibilityLabel("活动会话列表")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with event: NSEvent) { onInteraction?(); super.scrollWheel(with: event) }

    func configure(rows: [ActivitySessionSnapshot], playback: Bool,
                   rowHeight: CGFloat, onInteraction: (() -> Void)?, effect: ActivityIslandProgressEffect = .stateSmoke,
                   focusedID: String? = nil, reduceMotion: Bool = false, onSelect: ((String) -> Void)? = nil,
                   liquidGlassEnabled: Bool = true, glassActive: Bool = true) {
        let next = ActivityIslandListLayout(sessionIDs: rows.map(\.id), rowHeight: rowHeight)
        let changed = next != listLayout
        let offset = contentView.bounds.minY
        let anchor = changed ? listLayout.anchor(at: offset) : nil
        self.rows = rows; self.playback = playback
        self.liquidGlassEnabled = liquidGlassEnabled; self.glassActive = glassActive
        self.effect = effect; self.focusedID = focusedID; self.reduceMotion = reduceMotion; self.onSelect = onSelect
        self.onInteraction = onInteraction; listLayout = next
        updateDocument(updateContent: true)
        if changed {
            let restored = anchor.flatMap { next.offset(for: $0) } ?? offset
            scroll(to: restored)
        }
        publishVisibility()
    }
    override func layout() {
        super.layout()
        if host != nil { updateDocument(); publishVisibility() }
    }
    private func updateDocument(updateContent: Bool = false) {
        let width = max(1, contentSize.width)
        if updateContent || documentWidth != width {
            documentWidth = width
            host.rootView = ActivityIslandRowsDocument(rows: rows, playback: playback,
                width: width, rowHeight: listLayout.rowHeight, effect: effect, focusedID: focusedID,
                reduceMotion: reduceMotion, onSelect: onSelect,
                liquidGlassEnabled: liquidGlassEnabled, glassActive: glassActive, visibility: visibility)
        }
        let size = CGSize(width: width, height: max(contentSize.height, listLayout.contentHeight))
        if host.frame.size != size { host.setFrameSize(size) }
    }
    func scroll(to offset: CGFloat) {
        let maximum = max(0, listLayout.contentHeight - contentSize.height)
        contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, offset))))
        reflectScrolledClipView(contentView)
        publishVisibility()
    }
    private func publishVisibility() {
        let visible = playback && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
            && !NSApp.isHidden && !isHiddenOrHasHiddenAncestor
        let ids = visible ? listLayout.visibleSessionIDs(offset: contentView.bounds.minY,
                                                        viewport: contentSize.height) : []
        guard scheduledVisibility != ids else { return }
        visibilityWork?.cancel(); visibilityWork = nil; scheduledVisibility = nil
        guard visibility.sessionIDs != ids else { return }
        scheduledVisibility = ids
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.scheduledVisibility == ids else { return }
            self.visibilityWork = nil; self.scheduledVisibility = nil
            self.visibility.sessionIDs = ids
        }
        visibilityWork = work
        DispatchQueue.main.async(execute: work)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); publishVisibility() }
    func stop() {
        visibilityWork?.cancel(); visibilityWork = nil; scheduledVisibility = nil
        observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
        visibility.sessionIDs = []
    }
    deinit {
        visibilityWork?.cancel()
        observations.forEach(NotificationCenter.default.removeObserver)
    }
}
