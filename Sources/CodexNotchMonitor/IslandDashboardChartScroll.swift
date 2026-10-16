// Reused from QuotaView f779531 (MIT), Copyright (c) 2026 Duoasa.
import AppKit
import SwiftUI

final class DashboardChartScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let slot = rect(for: .knobSlot)
        NSColor(white: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: slot.minX, y: bounds.midY - 1.5,
            width: slot.width, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        let knob = rect(for: .knob)
        NSColor(white: 0.48, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: knob.minX, y: bounds.midY - 2,
            width: knob.width, height: 4), xRadius: 2, yRadius: 2).fill()
    }
}

struct DashboardChartScrollStyle: NSViewRepresentable {
    final class Probe: NSView {
        weak var scroll: NSScrollView?
        var original: NSScroller?
        var rail: DashboardChartScroller?
        var originalStyle: NSScroller.Style = .legacy
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); attach() }
        override func layout() { super.layout(); attach() }
        func attach() {
            guard let found = enclosingScrollView, found !== scroll else { return }
            detach()
            scroll = found
            original = found.horizontalScroller
            originalStyle = found.scrollerStyle
            let rail = DashboardChartScroller(frame: CGRect(x: 0, y: 0, width: 100, height: 12))
            rail.controlSize = .small
            rail.target = original?.target
            rail.action = original?.action
            self.rail = rail
            found.scrollerStyle = .legacy
            found.horizontalScroller = rail
        }
        func detach() {
            if let scroll, scroll.horizontalScroller === rail {
                scroll.horizontalScroller = original
                scroll.scrollerStyle = originalStyle
            }
            scroll = nil; original = nil; rail = nil
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.attach() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }
}

/// Preserve readable marks and put the newest column at the trailing edge.
/// Data-value refreshes do not disturb a user who is browsing older history.
struct DashboardRecentChartScroll<Content: View>: View {
    let plotWidth: CGFloat
    let viewportWidth: CGFloat
    let plotHeight: CGFloat
    let resetID: String
    @ViewBuilder let content: () -> Content
    var overflows: Bool { plotWidth > viewportWidth + 0.5 }

    var body: some View {
        Group {
            if overflows {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        content().frame(width: plotWidth, height: plotHeight)
                            .background(DashboardChartScrollStyle()).id("recent-chart")
                    }
                    .scrollIndicators(.visible)
                    .onAppear { scroll.scrollTo("recent-chart", anchor: .trailing) }
                    .onChange(of: resetID) { _ in scroll.scrollTo("recent-chart", anchor: .trailing) }
                    .onChange(of: viewportWidth) { _ in scroll.scrollTo("recent-chart", anchor: .trailing) }
                }
            } else {
                content().frame(width: plotWidth, height: plotHeight)
            }
        }
        .frame(width: viewportWidth, height: plotHeight + (overflows ? 14 : 0), alignment: .trailing)
    }
}
