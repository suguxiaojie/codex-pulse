// Adapted from QuotaView (MIT), Copyright (c) 2026 Duoasa.
// IslandConceptBoard.swift / IslandTaskScrolling.swift at f632288fb706b83e691000e365004f6ed9654d94.
// Full license and adaptation details: Resources/ThirdPartyNotices.txt.
import AppKit
import SwiftUI

enum ActivityIslandSurfaceMotion {
    static let duration: Double = 0.38
    static let contentDuration: Double = 0.23
    static var animation: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    }
    static let hoverOpenDelay: TimeInterval = 0.15
    static let hoverCloseDelay: TimeInterval = 0.45
}

/// QuotaView's fixed row geometry, adapted to session IDs and our narrower panel.
struct ActivityIslandListLayout: Equatable {
    let sessionIDs: [String]
    var rowHeight: CGFloat = 62
    var extraHeights: [String: CGFloat] = [:]
    static let rowSpacing: CGFloat = 8
    static let verticalInset: CGFloat = 12

    struct Anchor { let sessionID: String; let inset: CGFloat }
    var contentHeight: CGFloat {
        Self.verticalInset * 2 + CGFloat(sessionIDs.count) * rowHeight
            + CGFloat(max(0, sessionIDs.count - 1)) * Self.rowSpacing + extraHeights.values.reduce(0, +)
    }
    func anchor(at offset: CGFloat) -> Anchor? {
        var cursor = Self.verticalInset
        for (index, id) in sessionIDs.enumerated() {
            if offset < cursor + rowHeight + (extraHeights[id] ?? 0) + Self.rowSpacing || index == sessionIDs.count - 1 {
                return Anchor(sessionID: id, inset: offset - cursor)
            }
            cursor += rowHeight + (extraHeights[id] ?? 0) + Self.rowSpacing
        }
        return nil
    }
    func offset(for anchor: Anchor) -> CGFloat? {
        guard let index = sessionIDs.firstIndex(of: anchor.sessionID) else { return nil }
        return Self.verticalInset + CGFloat(index) * (rowHeight + Self.rowSpacing)
            + sessionIDs.prefix(index).reduce(0) { $0 + (extraHeights[$1] ?? 0) }
            + min(rowHeight + (extraHeights[anchor.sessionID] ?? 0) + Self.rowSpacing, anchor.inset)
    }
    func visibleSessionIDs(offset: CGFloat, viewport: CGFloat) -> Set<String> {
        var result: Set<String> = []
        var cursor = Self.verticalInset
        for id in sessionIDs {
            if cursor < offset + viewport && cursor + rowHeight > offset { result.insert(id) }
            cursor += rowHeight + (extraHeights[id] ?? 0) + Self.rowSpacing
        }
        return result
    }
}

// QuotaView IslandGeometry sizing rules, shared by production and settings.
struct ActivityIslandWidthGeometry {
    let screenWidth: CGFloat
    var cameraWidth: CGFloat = 0
    var compactWidth: CGFloat { cameraWidth > 0 ? cameraWidth + 280 : 340 }
    var maximumExpandedWidth: CGFloat { min(max(680, compactWidth + 64), max(1, screenWidth - 48)) }
    var minimumExpandedWidth: CGFloat { min(maximumExpandedWidth, max(560, cameraWidth + 360)) }
    func expandedWidth(preferred: Double) -> CGFloat {
        let requested = ActivityIslandPreferences.normalizedWidth(preferred)
        return requested == 680 ? maximumExpandedWidth : min(maximumExpandedWidth, max(minimumExpandedWidth, requested))
    }
    var settingsRange: ClosedRange<Double> {
        let upper = min(680, maximumExpandedWidth)
        return min(upper, minimumExpandedWidth)...upper
    }
    static func current() -> Self {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        let width = screen?.frame.width ?? 1440
        let camera = (screen?.safeAreaInsets.top ?? 0) > 0 ? max(0, width - (screen?.auxiliaryTopLeftArea?.width ?? 0) - (screen?.auxiliaryTopRightArea?.width ?? 0)) : 0
        return Self(screenWidth: width, cameraWidth: camera)
    }
}

struct ActivityIslandPanelMetrics: Equatable {
    let hostSize: CGSize
    let compactRect: CGRect
    let expandedRect: CGRect
    let rowHeight: CGFloat
    let visibleRowCount: Int
    let hardwareGap: CGFloat
    let maximumUsageHeight: CGFloat
    var listHeight: CGFloat { expandedRect.height - Self.headerHeight - Self.footerHeight }
    static let headerHeight: CGFloat = 36
    /// Bottom breathing room only; the former footer controls now live in the header.
    static let footerHeight: CGFloat = 4

    static func focusHeight(for row: ActivitySessionSnapshot?) -> CGFloat {
        // Header (44) + metadata (13) + vertical padding (24) + gaps; the timeline adds 34 + gap.
        guard let row else { return 90 }
        if row.isPrivate { return 113 }
        return row.recentSteps.isEmpty ? 90 : 133
    }
    static let railHeight: CGFloat = 38 // 30 pt capsules plus 8 pt separation.
    static func stageHeight(rowCount: Int, focusHeight: CGFloat) -> CGFloat {
        ActivityIslandListLayout.verticalInset * 2 + focusHeight + (rowCount > 1 ? railHeight : 0)
    }

    init(rowCount: Int, availableSize: CGSize, expandedWidth: CGFloat = 680,
         safeAreaTop: CGFloat = 0, hardwareGap: CGFloat = 0, floatingUsage: Bool = false,
         usagePage: Bool = false, reservesUsagePage: Bool = false, usagePageHeight: CGFloat = 580,
         focusHeight: CGFloat = 112) {
        let inset: CGFloat = 10
        let usageHeight: CGFloat = floatingUsage ? 44 : 0
        let geometry = ActivityIslandWidthGeometry(screenWidth: availableSize.width, cameraWidth: hardwareGap)
        let width = geometry.expandedWidth(preferred: expandedWidth)
        rowHeight = focusHeight
        self.hardwareGap = hardwareGap
        let chrome = Self.headerHeight + Self.footerHeight + ActivityIslandListLayout.verticalInset * 2
        visibleRowCount = 1 // One focus card; every other session lives in the horizontal rail.
        let maximumListHeight = max(1, availableSize.height - usageHeight - inset * 2 - Self.headerHeight - Self.footerHeight)
        let maxListHeight = min(maximumListHeight, Self.stageHeight(rowCount: 2, focusHeight: 129))
        let listHeight = min(maximumListHeight, Self.stageHeight(rowCount: rowCount, focusHeight: focusHeight))
        maximumUsageHeight = max(120, availableSize.height - inset * 2 - usageHeight)
        let pageHeight = min(maximumUsageHeight, max(120, usagePageHeight))
        let taskCanvasHeight = chrome - ActivityIslandListLayout.verticalInset * 2 + maxListHeight + inset * 2 + usageHeight
        hostSize = CGSize(width: max(width, min(geometry.compactWidth, availableSize.width - 20)) + inset * 2,
                          height: reservesUsagePage || usagePage ? max(taskCanvasHeight, maximumUsageHeight + inset * 2 + usageHeight) : taskCanvasHeight)
        let compactWidth = min(geometry.compactWidth, hostSize.width)
        compactRect = CGRect(x: (hostSize.width - compactWidth) / 2, y: 0,
                             width: compactWidth, height: safeAreaTop > 0 ? max(32, safeAreaTop) : 40)
        expandedRect = CGRect(x: (hostSize.width - width) / 2, y: 0, width: width,
                              height: usagePage ? pageHeight : Self.headerHeight + Self.footerHeight + listHeight)
    }
}
