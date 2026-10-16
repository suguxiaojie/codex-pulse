import SwiftUI

struct MonitorSettingsView: View {
    @ObservedObject var store: MonitorStore
    var initialSection: MonitorCenterSection = .panelSettings

    var body: some View {
        NotchView(store: store, onToggle: {}, onOpenCenter: { _ in }, surface: .center,
                  initialSection: initialSection)
    }
}
