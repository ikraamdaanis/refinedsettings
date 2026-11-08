import SwiftUI

/// The compact card at the top of a pane, as in System Settings > Accessibility: icon on the left, title and
/// description beside it.
struct PaneSummary: View {
    let pane: SettingsPane

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            PaneIcon(pane: pane, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                Text(pane.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
