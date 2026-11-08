import AppKit
import OSLog

let log = Logger(subsystem: "com.ikraam.linkguide", category: "Linkguide")

/// What Linkguide needs to know about installed apps, and about which one is the default browser.
@MainActor
enum AppInfo {
    /// Any web address: asking macOS which apps open it lists the browsers.
    private static let sampleWebURL = URL(string: "https://example.com")

    static func isLinkguide(_ appURL: URL) -> Bool {
        Bundle(url: appURL)?.bundleIdentifier == Bundle.main.bundleIdentifier
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
    static func makeLinkguideDefaultBrowser() async {
        do {
            for scheme in ["http", "https"] {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
        } catch {
            log.error("Couldn't make Linkguide the default browser: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NSApplication {
    /// Brings Linkguide to the front. It is a menu bar app, so it has to ask explicitly.
    func activateLinkguide() {
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
