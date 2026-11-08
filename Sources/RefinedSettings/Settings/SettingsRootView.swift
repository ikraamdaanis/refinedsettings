import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: navigation.sidebarSelection, searchText: searchText)
                .removingSidebarToggle()
                .navigationSplitViewColumnWidth(min: 215, ideal: 215, max: 215)
        } detail: {
            SettingsDetail(pane: navigation.pane)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: navigation.goBack) {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(!navigation.canGoBack)
                        Button(action: navigation.goForward) {
                            Label("Forward", systemImage: "chevron.forward")
                        }
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(!navigation.canGoForward)
                    }
                }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .hidingToolbarTitle(navigation.isHeaderVisible)
        .environmentObject(navigation)
    }
}

private extension View {
    /// System Settings' sidebar can't be collapsed. Earlier than macOS 14 there's no way to remove the button.
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }

    /// Earlier than macOS 15 the title stays in the toolbar.
    @ViewBuilder
    func hidingToolbarTitle(_ isHidden: Bool) -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: isHidden ? .title : nil)
        } else {
            self
        }
    }
}
