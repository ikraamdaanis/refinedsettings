import AppKit
import OSLog

let log = Logger(subsystem: "com.ikraam.refinedsettings", category: "RefinedSettings")

/// What Refined Settings needs to know about installed apps, and about which one is the default browser.
@MainActor
enum AppInfo {
    /// Any web address: asking macOS which apps open it lists the browsers.
    private static let sampleWebURL = URL(string: "https://example.com")

    static func isRefinedSettings(_ appURL: URL) -> Bool {
        Bundle(url: appURL)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static func isDefaultBrowser(_ appURL: URL?) -> Bool {
        guard let appURL else { return false }

        return isRefinedSettings(appURL)
    }

    /// Opens a System Settings pane, given the identifier of its settings extension.
    static func openSystemSettings(paneID: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(paneID)") else { return }

        NSWorkspace.shared.open(url)
    }

    /// The name Finder shows for the app, without the .app extension.
    static func name(of appURL: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: appURL.path)

        return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }

    static func webBrowserURLs() -> [URL] {
        guard let sampleWebURL else { return [] }

        return NSWorkspace.shared.urlsForApplications(toOpen: sampleWebURL)
    }

    static func defaultBrowserURL() -> URL? {
        guard let sampleWebURL else { return nil }

        return NSWorkspace.shared.urlForApplication(toOpen: sampleWebURL)
    }

    /// macOS asks the user to confirm the change in its own dialog; declining it is logged, not shown.
    static func makeRefinedSettingsDefaultBrowser() async {
        do {
            for scheme in ["http", "https"] {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
        } catch {
            log.error("Couldn't make Refined Settings the default browser: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NSApplication {
    /// Brings Refined Settings to the front. It is a menu bar app, so it has to ask explicitly.
    func activateRefinedSettings() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}

extension NSRunningApplication {
    /// Brings this app to the front, without raising all of its windows.
    func activateApp() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(options: .activateIgnoringOtherApps)
        }
    }
}
