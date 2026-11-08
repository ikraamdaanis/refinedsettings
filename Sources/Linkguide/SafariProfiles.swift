import AppKit
import ApplicationServices

/// Safari has no command-line flag, AppleScript command or Shortcuts action for opening a link in a given
/// profile, so Linkguide works through Safari's own interface with the Accessibility API. It reads the profiles
/// from the File menu's "New <Profile> Window" items. To open a link, it brings a window of that profile to the
/// front (opening one from that menu if there is none), then hands Safari the link, which Safari opens in the
/// profile in front.
@MainActor
enum SafariProfiles {
    static let bundleID = "com.apple.Safari"
    private static let namesKey = "safariProfileNames"
    /// Safari identifies each profile's menu item as `New<Profile>Window?isDefaultProfile=<true|false>`.
    private static let menuItemPrefix = "New"
    private static let menuItemMarker = "Window?isDefaultProfile="
    /// With more than one profile, Safari starts each window title with the profile name and an em dash.
    private static let titleSeparator = " \u{2014} "
    /// How long to wait on Safari for each Accessibility call, so a hung Safari can't stall Linkguide.
    private static let messagingTimeout: Float = 1

    private struct MenuProfile {
        let name: String
        let isDefault: Bool
        let menuItem: AXUIElement
    }

    static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Shows macOS's Accessibility prompt, which also adds Linkguide to the list in System Settings.
    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Safari's profiles in its own order, read from its menu while it's running and remembered for when it
    /// isn't. Empty when Safari has a single profile.
    static func profileNames() -> [String] {
        if hasAccess, let safari = runningSafari(), let profiles = menuProfiles(of: element(for: safari)) {
            let names = profiles.map { profile in profile.name }
            UserDefaults.standard.set(names, forKey: namesKey)

            return names
        }

        return UserDefaults.standard.stringArray(forKey: namesKey) ?? []
    }

    /// Brings a window of the named profile to the front, opening Safari and a window of that profile when needed.
    /// Returns false when that couldn't be done, in which case Safari opens the link in whichever profile it picks.
    static func bringToFront(profileNamed name: String, safariURL: URL) async -> Bool {
        guard hasAccess else {
            requestAccess()

            return false
        }

        let wasRunning = runningSafari() != nil

        guard let safari = await launchedSafari(at: safariURL) else { return false }

        let app = element(for: safari)
        let readProfiles = { menuProfiles(of: app).flatMap { profiles in profiles.isEmpty ? nil : profiles } }
        // A Safari that's just launching builds its menu over the first moments, so give it time; a running one has it.
        let profiles = wasRunning ? readProfiles() : await poll(readProfiles)

        guard let profiles, let profile = profiles.first(where: { candidate in candidate.name == name }) else {
            log.error("Safari has no profile named \(name, privacy: .public)")

            return false
        }

        safari.activate()

        if let window = window(of: profile, among: profiles, in: app) {
            raise(window)
        } else {
            guard AXUIElementPerformAction(profile.menuItem, kAXPressAction as CFString) == .success,
                  await poll({ window(of: profile, among: profiles, in: app) }) != nil
            else {
                log.error("Couldn't open a window for Safari profile \(name, privacy: .public)")

                return false
            }
        }

        return true
    }

    private static func runningSafari() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { app in !app.isTerminated }
    }

    private static func launchedSafari(at safariURL: URL) async -> NSRunningApplication? {
        if let safari = runningSafari() {
            return safari
        }

        do {
            return try await NSWorkspace.shared.openApplication(at: safariURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            log.error("Couldn't launch Safari: \(error.localizedDescription, privacy: .public)")

            return nil
        }
    }

    private static func element(for app: NSRunningApplication) -> AXUIElement {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        return element
    }

    /// The profile items in Safari's File menu, or nil when the menu can't be read. Safari only lists profiles
    /// there once there's more than one, so a single profile gives an empty list.
    private static func menuProfiles(of app: AXUIElement) -> [MenuProfile]? {
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, of: app) else { return nil }

        let menuBarItems = children(of: menuBar)
        // The File menu is third, after the Apple and Safari menus; look further only if that ever changes.
        let fileMenuIndex = 2
        let searchOrder = menuBarItems.indices.contains(fileMenuIndex)
            ? [fileMenuIndex] + menuBarItems.indices.filter { index in index != fileMenuIndex }
            : Array(menuBarItems.indices)

        for index in searchOrder {
            let profiles = children(of: menuBarItems[index]).flatMap(children(of:)).compactMap(menuProfile(from:))

            if !profiles.isEmpty {
                return profiles
            }
        }

        return []
    }

    private static func menuProfile(from menuItem: AXUIElement) -> MenuProfile? {
        guard let identifier = stringAttribute(kAXIdentifierAttribute, of: menuItem),
              identifier.hasPrefix(menuItemPrefix),
              let markerRange = identifier.range(of: menuItemMarker)
        else { return nil }

        let name = String(identifier[identifier.index(identifier.startIndex, offsetBy: menuItemPrefix.count)..<markerRange.lowerBound])

        guard !name.isEmpty else { return nil }

        return MenuProfile(name: name, isDefault: identifier[markerRange.upperBound...] == "true", menuItem: menuItem)
    }

    /// The frontmost window of `profile`. Windows whose title names no profile belong to the default one.
    private static func window(of profile: MenuProfile, among profiles: [MenuProfile], in app: AXUIElement) -> AXUIElement? {
        let windows = (attribute(kAXWindowsAttribute, of: app) as? [AXUIElement] ?? []).filter { window in
            stringAttribute(kAXSubroleAttribute, of: window) == kAXStandardWindowSubrole
        }
        let profileWindows = windows.filter { window in
            let title = stringAttribute(kAXTitleAttribute, of: window) ?? ""
            let owner = profiles.first { candidate in title == candidate.name || title.hasPrefix(candidate.name + titleSeparator) }

            return owner.map { owner in owner.name == profile.name } ?? profile.isDefault
        }

        return profileWindows.first { window in attribute(kAXMinimizedAttribute, of: window) as? Bool != true } ?? profileWindows.first
    }

    private static func raise(_ window: AXUIElement) {
        if attribute(kAXMinimizedAttribute, of: window) as? Bool == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Checks `condition` every tenth of a second for up to five seconds, while Safari launches or opens a window.
    private static func poll<Value>(_ condition: () -> Value?) async -> Value? {
        for _ in 0..<50 {
            if let value = condition() {
                return value
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        return nil
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?

        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element) as? String
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }
}
