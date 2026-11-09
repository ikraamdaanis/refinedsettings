import SwiftUI

struct MenuBarPane: View {
    @ObservedObject private var store = SystemPreferenceStore.shared

    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .menuBar)
            }
            Section {
                if #available(macOS 26, *) {
                    SystemPreferenceToggleRow(
                        title: "Show icons in menus",
                        detail: "macOS 26 added small icons beside menu commands. Turn this off for plain text menus.",
                        preference: .menusShowIcons,
                        unsetValue: true
                    )
                }
                SystemPreferenceRow(
                    title: "Tighter menu bar icons",
                    detail: "Fits more icons into the menu bar, which helps on Macs with a notch.",
                    isChanged: store.isChanged(.menuBarItemSpacing),
                    reset: { store.reset(.menuBarItemSpacing) }
                ) {
                    Toggle("Tighter menu bar icons", isOn: store.usesTightMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            } header: {
                PaneSectionHeader(title: "Appearance", help: "Apps you already have open need reopening. If the menu bar doesn't change, log out and back in.")
            }
        }
        .paneFormStyle()
        .refreshesSystemPreferences()
    }
}
