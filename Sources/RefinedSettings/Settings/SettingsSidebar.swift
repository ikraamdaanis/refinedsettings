import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?
    let searchText: String

    private var visiblePanes: [SettingsPane] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return SettingsPane.allCases }

        return SettingsPane.allCases.filter { pane in pane.matches(query) }
    }

    var body: some View {
        List(visiblePanes, id: \.self, selection: $selection) { pane in
            Label {
                Text(pane.title)
            } icon: {
                PaneIcon(pane: pane, size: 20)
            }
            .tag(pane)
        }
        .listStyle(.sidebar)
        .overlay {
            if visiblePanes.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
