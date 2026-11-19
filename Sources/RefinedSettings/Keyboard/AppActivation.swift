import AppKit

/// Brings an app to the front the way clicking it in the Dock does: launched if it isn't running, unhidden if it's
/// hidden, and given a new window if it has none.
@MainActor
enum AppActivation {
    static func open(_ appURL: URL, bundleID: String) {
        // Opening an app normally unhides it as well, but asking outright costs nothing.
        for runningApp in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where runningApp.isHidden {
            runningApp.unhide()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            guard let error else { return }

            log.error("Couldn't open \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
