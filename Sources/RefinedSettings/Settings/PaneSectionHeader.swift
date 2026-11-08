import SwiftUI

/// A section title with help text under it, for lists whose rows have no room to explain themselves.
struct PaneSectionHeader: View {
    let title: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(help)
                .font(.callout)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
