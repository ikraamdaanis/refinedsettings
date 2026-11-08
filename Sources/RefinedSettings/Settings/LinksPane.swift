import AppKit
import SwiftUI

struct LinksPane: View {
    @State private var entries = BrowserCatalog.allEntries()
    @State private var hiddenIDs = BrowserCatalog.hiddenIDs
    @State private var defaultBrowserURL = AppInfo.defaultBrowserURL()
    @State private var needsSafariAccess = Self.safariNeedsAccess()
    @State private var draggedID: String?
    @State private var dragTranslation: CGFloat = 0

    private let rowHeight: CGFloat = 40

    /// The keyboard shortcut each visible row gets in the picker, following the row being dragged.
    private var shortcuts: [String: String] {
        let visibleIDs = displayedOrder.map { entry in entry.id }.filter { id in !hiddenIDs.contains(id) }

        return Dictionary(uniqueKeysWithValues: visibleIDs.prefix(9).enumerated().map { index, id in (id, "\(index + 1)") })
    }

    private var draggedIndex: Int? {
        guard let draggedID else { return nil }

        return entries.firstIndex { entry in entry.id == draggedID }
    }

    /// The slot the dragged row would land in if it were dropped now.
    private var dropIndex: Int? {
        guard let draggedIndex else { return nil }

        let rowsMoved = Int((dragTranslation / rowHeight).rounded())

        return min(max(draggedIndex + rowsMoved, 0), entries.count - 1)
    }

    /// The order the rows would have if the dragged row were dropped now.
    private var displayedOrder: [BrowserEntry] {
        guard let draggedIndex, let dropIndex else { return entries }

        var reordered = entries
        reordered.move(fromOffsets: IndexSet(integer: draggedIndex), toOffset: dropIndex > draggedIndex ? dropIndex + 1 : dropIndex)

        return reordered
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
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        reorderableRow(for: entry, at: index)
                    }
                }
                // Cancels the form row's own vertical padding, so these rows are spaced like every other 40-point row.
                .padding(.vertical, -10)
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

    /// A row that lifts off the list while it is dragged; the rows it passes slide aside to open a gap for it.
    private func reorderableRow(for entry: BrowserEntry, at index: Int) -> some View {
        let isDragged = entry.id == draggedID
        let slot = displayedSlot(of: index)
        let offset = isDragged
            ? min(max(dragTranslation, -CGFloat(index) * rowHeight), CGFloat(entries.count - 1 - index) * rowHeight)
            : CGFloat(slot - index) * rowHeight

        return browserRow(for: entry)
            .overlay(alignment: .bottom) {
                if !isDragged && slot < entries.count - 1 {
                    Divider()
                        .padding(.leading, 30)
                }
            }
            .background {
                if isDragged {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .padding(.horizontal, -6)
                }
            }
            .offset(y: offset)
            .zIndex(isDragged ? 1 : 0)
            .animation(isDragged ? nil : .easeOut(duration: 0.18), value: dropIndex)
            .gesture(reorderGesture(for: entry))
            .accessibilityAction(named: "Move Up") { move(entry, by: -1) }
            .accessibilityAction(named: "Move Down") { move(entry, by: 1) }
    }

    /// Where a row shows while a drag is under way: rows between the dragged row and its drop slot step aside.
    private func displayedSlot(of index: Int) -> Int {
        guard let draggedIndex, let dropIndex else { return index }

        if index == draggedIndex { return dropIndex }
        if draggedIndex < index && index <= dropIndex { return index - 1 }
        if dropIndex <= index && index < draggedIndex { return index + 1 }

        return index
    }

    private func reorderGesture(for entry: BrowserEntry) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggedID == nil {
                    draggedID = entry.id
                    NSCursor.closedHand.push()
                }

                dragTranslation = value.translation.height
            }
            .onEnded { _ in
                NSCursor.pop()

                withAnimation(.easeOut(duration: 0.18)) {
                    entries = displayedOrder
                    draggedID = nil
                    dragTranslation = 0
                }

                saveOrder()
            }
    }

    private func browserRow(for entry: BrowserEntry) -> some View {
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
            if let shortcut = shortcuts[entry.id] {
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
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move to Top") { move(entry, to: 0) }
                .disabled(entries.first?.id == entry.id)
            Button("Move Up") { move(entry, by: -1) }
                .disabled(entries.first?.id == entry.id)
            Button("Move Down") { move(entry, by: 1) }
                .disabled(entries.last?.id == entry.id)
            Button("Move to Bottom") { move(entry, to: entries.count - 1) }
                .disabled(entries.last?.id == entry.id)
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

    private func move(_ entry: BrowserEntry, by step: Int) {
        guard let index = entries.firstIndex(where: { candidate in candidate.id == entry.id }) else { return }

        move(entry, to: index + step)
    }

    private func move(_ entry: BrowserEntry, to targetIndex: Int) {
        guard let index = entries.firstIndex(where: { candidate in candidate.id == entry.id }) else { return }

        let movedEntry = entries.remove(at: index)
        entries.insert(movedEntry, at: min(max(targetIndex, 0), entries.count))
        saveOrder()
    }

    private func saveOrder() {
        BrowserCatalog.entryOrder = entries.map { entry in entry.id }
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
