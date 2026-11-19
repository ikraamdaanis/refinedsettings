import AppKit
import SwiftUI

struct LinksPane: View {
    @State private var entries = BrowserCatalog.allEntries()
    @State private var hiddenIDs = BrowserCatalog.hiddenIDs
    @State private var defaultBrowserURL = AppInfo.defaultBrowserURL()
    @State private var needsSafariAccess = Self.safariNeedsAccess()

    private let rowHeight: CGFloat = 40

    private var orderedEntries: Binding<[BrowserEntry]> {
        Binding(
            get: { entries },
            set: { reordered in
                entries = reordered
                BrowserCatalog.entryOrder = reordered.map { entry in entry.id }
            }
        )
    }

    /// The keyboard shortcut each visible row gets in the picker, for the order the rows show in.
    private func shortcuts(in displayedOrder: [BrowserEntry]) -> [String: String] {
        let visibleIDs = displayedOrder.map { entry in entry.id }.filter { id in !hiddenIDs.contains(id) }

        return Dictionary(uniqueKeysWithValues: visibleIDs.prefix(9).enumerated().map { index, id in (id, "\(index + 1)") })
    }

    // Laid out like System Settings > Privacy & Security > Accessibility: a grouped list of apps with a switch
    // each, which you can also drag into order, as in Language & Region > Preferred Languages.
    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .links)
            }
            DefaultBrowserSection(defaultBrowserURL: defaultBrowserURL, refresh: refresh)
            Section {
                ReorderableList(items: orderedEntries, rowHeight: rowHeight, dividerInset: 30) { entry, displayedOrder in
                    browserRow(for: entry, shortcut: shortcuts(in: displayedOrder)[entry.id])
                }
            } header: {
                PaneSectionHeader(title: "Browsers", help: "These are your choices when you click a link, in this order. Drag to reorder, or turn one off to hide it. The numbers are the keys that open each one.")
            }
            if needsSafariAccess {
                Section("Safari Profiles") {
                    AccessibilityAccessRow(reason: "To open a link in a particular Safari profile, Refined Settings has to use Safari's menus.")
                }
            }
        }
        .paneFormStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func browserRow(for entry: BrowserEntry, shortcut: String?) -> some View {
        let isShown = !hiddenIDs.contains(entry.id)

        return HStack(spacing: 10) {
            EntryIcon(entry: entry, size: 20)
                .opacity(isShown ? 1 : 0.45)
            HStack(spacing: 5) {
                Text(entry.browserName)
                    .foregroundStyle(isShown ? Color.primary : Color.secondary)
                if let profileName = entry.profileName {
                    Text(profileName)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Press \(shortcut) in the picker")
            }
            Toggle("Show \([entry.browserName, entry.profileName].compactMap { name in name }.joined(separator: " "))", isOn: visibilityBinding(for: entry.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func visibilityBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenIDs.contains(id) },
            set: { isShown in
                if isShown {
                    hiddenIDs.remove(id)
                } else {
                    hiddenIDs.insert(id)
                }

                BrowserCatalog.hiddenIDs = hiddenIDs
            }
        )
    }

    private func refresh() {
        entries = BrowserCatalog.allEntries()
        hiddenIDs = BrowserCatalog.hiddenIDs
        defaultBrowserURL = AppInfo.defaultBrowserURL()
        needsSafariAccess = Self.safariNeedsAccess()
    }

    private static func safariNeedsAccess() -> Bool {
        !SafariProfiles.hasAccess && NSWorkspace.shared.urlForApplication(withBundleIdentifier: SafariProfiles.bundleID) != nil
    }
}
