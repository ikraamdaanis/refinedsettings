import SwiftUI

struct FinderPane: View {
    private let viewChoices = [
        (storedValue: "icnv", title: "Icons"),
        (storedValue: "Nlsv", title: "List"),
        (storedValue: "clmv", title: "Columns"),
        (storedValue: "glyv", title: "Gallery"),
    ]
    /// Finder has no column view for search results. Its default here isn't documented, so "Automatic" stands for no
    /// stored value rather than claiming to be one of the views. It is never written.
    private let searchViewChoices = [
        (storedValue: "automatic", title: "Automatic"),
        (storedValue: "icnv", title: "Icons"),
        (storedValue: "Nlsv", title: "List"),
        (storedValue: "glyv", title: "Gallery"),
    ]

    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .finder)
            }
            Section {
                SystemPreferenceToggleRow(
                    title: "Show full path in title bar",
                    detail: "Shows where a window is, such as /Users/you/Documents, instead of only the folder's name.",
                    preference: .finderShowsFullPath,
                    unsetValue: false
                )
                SystemPreferenceToggleRow(
                    title: "Show hidden files",
                    detail: "Shows files macOS normally keeps out of view, such as .zshrc. ⌘⇧. does the same in a Finder window.",
                    preference: .finderShowsHiddenFiles,
                    unsetValue: false
                )
                SystemPreferencePickerRow(
                    title: "Default folder view",
                    detail: "Used for folders that don't already have their own view.",
                    preference: .finderDefaultView,
                    unsetValue: "icnv",
                    choices: viewChoices
                )
                SystemPreferencePickerRow(
                    title: "Search results view",
                    detail: "How results are shown when you search in Finder.",
                    preference: .finderSearchView,
                    unsetValue: "automatic",
                    choices: searchViewChoices
                )
                AppRestartRow(app: .finder, detail: "Finder windows close and reopen. Any file copies in progress stop.")
            } header: {
                PaneSectionHeader(title: "Windows", help: "Changes apply when you restart Finder.")
            }
            Section("Network Drives") {
                SystemPreferenceToggleRow(
                    title: "Don't leave .DS_Store files on network drives",
                    detail: "Keeps shared drives free of these hidden files. Existing ones stay. Takes effect after you log out and back in.",
                    preference: .skipsDSStoreOnNetworkDrives,
                    unsetValue: false
                )
            }
        }
        .paneFormStyle()
        .refreshesSystemPreferences()
    }
}
