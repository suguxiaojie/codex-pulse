import Foundation

enum GlanceLayout {
    static let width: CGFloat = 296
    static let height: CGFloat = 806
    static let resetPageHeight: CGFloat = 748
    static let cornerRadius: CGFloat = 26
    static let contentInset: CGFloat = 12
    static let headerHeight: CGFloat = 50
    static let footerHeight: CGFloat = 48
    static let readingInset: CGFloat = 8
    static let moduleSpacing: CGFloat = 10

    static func preferredHeight(readingHeight: CGFloat?, estimatedHeight: CGFloat) -> CGFloat {
        let contentHeight = readingHeight.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let requested = contentHeight.map { ceil($0) + headerHeight + footerHeight } ?? estimatedHeight
        return min(height, max(230, requested))
    }

    static func readingViewportHeight(panelHeight: CGFloat) -> CGFloat {
        max(0, panelHeight - headerHeight - footerHeight)
    }
}
