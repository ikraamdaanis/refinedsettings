import SwiftUI

/// The centred banner at the top of General, as in System Settings > General.
struct PaneHeader: View {
    /// Where the window's toolbar ends, in window coordinates.
    nonisolated private static let toolbarBottom: CGFloat = 52

    let pane: SettingsPane
    @EnvironmentObject private var navigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            PaneIcon(pane: pane, size: 52)
                .padding(.bottom, 10)
            Text(pane.title)
                .font(.title.bold())
                .padding(.bottom, 3)
            Text(pane.summary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .global).maxY > Self.toolbarBottom
        } action: { isVisible in
            navigation.isHeaderVisible = isVisible
        }
    }
}
