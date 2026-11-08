import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?
    let searchText: String

    private var visibleGroups: [[SettingsPane]] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return SettingsPane.sidebarGroups }

        return SettingsPane.sidebarGroups
            .map { group in group.filter { pane in pane.matches(query) } }
            .filter { group in !group.isEmpty }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(visibleGroups, id: \.self) { group in
                Section {
                    ForEach(group, id: \.self) { pane in
                        Label {
                            Text(pane.title)
                        } icon: {
                            PaneIcon(pane: pane, size: 20)
                        }
                        .tag(pane)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if visibleGroups.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
