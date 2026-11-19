import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The apps that open with a shortcut, in the order shared shortcuts go through them.
struct AppShortcutsSection: View {
    let hasAccessibilityAccess: Bool
    @AppStorage(AppShortcutSetting.key) private var shortcutsData = Data()

    private let rowHeight: CGFloat = 44

    private var appShortcuts: Binding<[AppShortcut]> {
        Binding(
            get: { AppShortcutSetting.decode(shortcutsData) },
            set: { updated in shortcutsData = AppShortcutSetting.encode(updated) }
        )
    }

    var body: some View {
        Section {
            if appShortcuts.wrappedValue.isEmpty {
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("No app shortcuts")
                    Text("Add an app, then record the shortcut that opens it.")
                }
            } else {
                ReorderableList(items: appShortcuts, rowHeight: rowHeight, dividerInset: 30) { appShortcut, displayedOrder in
                    appShortcutRow(for: appShortcut, in: displayedOrder)
                } menu: { appShortcut in
                    Divider()
                    Button("Remove") { remove(appShortcut) }
                }
            }
            if !hasAccessibilityAccess && !appShortcuts.wrappedValue.isEmpty {
                AccessibilityAccessRow(reason: "Without it, a shortcut can't bring an app's other windows forward, so each press goes to the next app.")
            }
            HStack {
                Spacer()
                Button("Add App…", action: addApps)
            }
        } header: {
            PaneSectionHeader(title: "App Shortcuts", help: "A shortcut opens its app, or brings it to the front. Pressed again, it brings each of the app's other windows forward in turn. Give several apps the same shortcut and each press moves on to the next, in this order, once the app in front has shown its windows. Drag to reorder.")
        }
    }

    private func appShortcutRow(for appShortcut: AppShortcut, in displayedOrder: [AppShortcut]) -> some View {
        let appURL = appShortcut.appURL
        let name = Self.name(of: appShortcut, at: appURL)

        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL?.path ?? appShortcut.appPath))
                .resizable()
                .frame(width: 20, height: 20)
                .opacity(appURL == nil ? 0.45 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .foregroundStyle(appURL == nil ? Color.secondary : Color.primary)
                if let caption = caption(for: appShortcut, appURL: appURL, in: displayedOrder) {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer()
            ShortcutRecorder(shortcut: shortcutBinding(for: appShortcut.id), isAllowed: AppShortcutSetting.canUse)
            Button {
                remove(appShortcut)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(name)")
            .accessibilityLabel("Remove \(name)")
        }
    }

    /// Says where a row sits among the apps sharing its shortcut, and which one the next press goes to.
    private func caption(for appShortcut: AppShortcut, appURL: URL?, in displayedOrder: [AppShortcut]) -> String? {
        if appURL == nil { return "Not installed" }

        guard let shortcut = appShortcut.shortcut else { return nil }

        let carbonModifiers = KeyPress.carbonModifiers(shortcut.modifiers)
        let sharing = displayedOrder.filter { candidate in
            guard let candidateShortcut = candidate.shortcut else { return false }

            return candidateShortcut.keyCode == shortcut.keyCode && KeyPress.carbonModifiers(candidateShortcut.modifiers) == carbonModifiers
        }

        guard sharing.count > 1, let position = sharing.firstIndex(where: { candidate in candidate.id == appShortcut.id }) else { return nil }

        let next = sharing[(position + 1) % sharing.count]

        return "\(position + 1) of \(sharing.count), then \(Self.name(of: next, at: next.appURL))"
    }

    private func shortcutBinding(for id: UUID) -> Binding<RecordedShortcut?> {
        Binding(
            get: { appShortcuts.wrappedValue.first { candidate in candidate.id == id }?.shortcut },
            set: { newShortcut in
                var updated = appShortcuts.wrappedValue

                guard let index = updated.firstIndex(where: { candidate in candidate.id == id }) else { return }

                updated[index].shortcut = newShortcut
                appShortcuts.wrappedValue = updated
            }
        )
    }

    private func remove(_ appShortcut: AppShortcut) {
        appShortcuts.wrappedValue = appShortcuts.wrappedValue.filter { candidate in candidate.id != appShortcut.id }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose the apps to open with a shortcut."

        guard panel.runModal() == .OK else { return }

        let added = panel.urls.compactMap { appURL in
            Bundle(url: appURL)?.bundleIdentifier.map { bundleID in AppShortcut(bundleID: bundleID, appPath: appURL.path) }
        }
        appShortcuts.wrappedValue += added
    }

    private static func name(of appShortcut: AppShortcut, at appURL: URL?) -> String {
        AppInfo.name(of: appURL ?? URL(fileURLWithPath: appShortcut.appPath))
    }
}
