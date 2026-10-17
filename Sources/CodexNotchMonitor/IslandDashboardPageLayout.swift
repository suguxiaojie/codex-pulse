// Reused from QuotaView f779531 (MIT), Copyright (c) 2026 Duoasa.
import SwiftUI
struct DashboardPageLayout<Content: View, Footer: View>: View {
    let maximumHeight: CGFloat?
    let onHeightChange: (CGFloat) -> Void
    let content: Content
    let footer: Footer
    @State private var contentHeight: CGFloat = 400
    init(maximumHeight: CGFloat?, onHeightChange: @escaping (CGFloat) -> Void,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.maximumHeight = maximumHeight; self.onHeightChange = onHeightChange
        self.content = content(); self.footer = footer()
    }
    private var measuredContent: some View {
        content.fixedSize(horizontal: false, vertical: true)
            .background { GeometryReader { proxy in
                Color.clear.preference(key: DashboardPageContentHeightKey.self, value: proxy.size.height)
            } }
            .onPreferenceChange(DashboardPageContentHeightKey.self) {
                if $0.isFinite && $0 > 0 { contentHeight = ceil($0) }
            }
    }
    var body: some View {
        VStack(spacing: 10) {
            if let maximumHeight {
                ScrollView(.vertical) { measuredContent }
                    .scrollIndicators(.automatic)
                    .frame(height: min(contentHeight, max(0, maximumHeight - 36 - 10)))
            } else { measuredContent }
            footer.modifier(IslandGlassChrome())
        }.fixedSize(horizontal: false, vertical: true)
            .background { GeometryReader { proxy in
                Color.clear.preference(key: DashboardPageHeightKey.self, value: proxy.size.height)
            } }
            .onPreferenceChange(DashboardPageHeightKey.self, perform: onHeightChange)
    }
}
private struct DashboardPageContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct DashboardPageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
