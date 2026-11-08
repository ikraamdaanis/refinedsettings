import SwiftUI

/// A row on General that says what a pane is for and whether it's in use, and opens the pane when clicked.
struct FeatureRow: View {
    let pane: SettingsPane
    let status: String
    @EnvironmentObject private var navigation: SettingsNavigation

    var body: some View {
        Button {
            navigation.select(pane)
        } label: {
            HStack(spacing: 10) {
                PaneIcon(pane: pane, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pane.title)
                    Text(pane.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(status)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
