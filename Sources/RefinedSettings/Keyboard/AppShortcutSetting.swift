import AppKit
import Carbon.HIToolbox

/// An app picked in Settings, and the shortcut that opens it.
struct AppShortcut: Codable, Hashable, Identifiable {
    var id = UUID()
    let bundleID: String
    /// Where the app was when it was picked, for showing it if macOS can no longer find it by its bundle ID.
    let appPath: String
    var shortcut: RecordedShortcut?

    /// Where the app is now, or nil when it's been removed.
    @MainActor
    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? (FileManager.default.fileExists(atPath: appPath) ? URL(fileURLWithPath: appPath) : nil)
    }
}

/// The apps that share one shortcut, in the order its presses go through them.
struct AppShortcutGroup: Equatable {
    let keyCode: CGKeyCode
    let carbonModifiers: UInt32
    let bundleIDs: [String]
}

/// The apps given shortcuts in Settings, in the order they're listed there. Apps that share a shortcut take turns, in
/// that order.
enum AppShortcutSetting {
    static let key = "appShortcuts"

    static func load() -> [AppShortcut] {
        decode(UserDefaults.standard.data(forKey: key))
    }

    static func decode(_ data: Data?) -> [AppShortcut] {
        guard let data, let shortcuts = try? JSONDecoder().decode([AppShortcut].self, from: data) else { return [] }

        return shortcuts
    }

    static func encode(_ shortcuts: [AppShortcut]) -> Data {
        (try? JSONEncoder().encode(shortcuts)) ?? Data()
    }

    /// One group per shortcut, in the order each shortcut first appears. An app listed twice under the same shortcut
    /// takes one turn.
    static func groups(of shortcuts: [AppShortcut]) -> [AppShortcutGroup] {
        var groups = [AppShortcutGroup]()

        for appShortcut in shortcuts {
            guard let shortcut = appShortcut.shortcut else { continue }

            let carbonModifiers = KeyPress.carbonModifiers(shortcut.modifiers)
            let existingIndex = groups.firstIndex { group in group.keyCode == shortcut.keyCode && group.carbonModifiers == carbonModifiers }

            guard let existingIndex else {
                groups.append(AppShortcutGroup(keyCode: shortcut.keyCode, carbonModifiers: carbonModifiers, bundleIDs: [appShortcut.bundleID]))

                continue
            }

            let group = groups[existingIndex]

            guard !group.bundleIDs.contains(appShortcut.bundleID) else { continue }

            groups[existingIndex] = AppShortcutGroup(keyCode: group.keyCode, carbonModifiers: group.carbonModifiers, bundleIDs: group.bundleIDs + [appShortcut.bundleID])
        }

        return groups
    }

    /// Whether a shortcut can open an app without getting in the way of typing: it needs ⌃ or ⌘, unless it's a function
    /// key. ⌥ and ⇧ on their own type characters, and macOS 15 refuses hot keys held with only those.
    static func canUse(_ shortcut: RecordedShortcut) -> Bool {
        let modifiers = shortcut.modifiers

        if modifiers.contains(.maskControl) || modifiers.contains(.maskCommand) { return true }

        return functionKeyCodes.contains(Int(shortcut.keyCode))
    }

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]
}
