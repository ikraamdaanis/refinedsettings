import AppKit

/// Hands a link to the browser (and profile) picked for it. Every path names the target app,
/// so a link is never passed back to the default browser, which is Refined Settings.
@MainActor
enum BrowserLauncher {
    static func open(_ url: URL, with entry: BrowserEntry) {
        guard !AppInfo.isRefinedSettings(entry.appURL) else { return }

        switch entry.launchMethod {
        case .workspace:
            openWithWorkspace(url, entry: entry)
        case .chromiumProfile(let directory):
            // Equivalent to: open -na "<browser>" --args --profile-directory=<dir> <url>
            runOpen(["-na", entry.appURL.path, "--args", "--profile-directory=\(directory)", url.absoluteString], browserName: entry.browserName)
        case .firefoxProfile(let name):
            // Firefox forwards the link to the running instance of this profile, or starts it.
            runOpen(["-na", entry.appURL.path, "--args", "-P", name, url.absoluteString], browserName: entry.browserName)
        case .safariProfile(let name):
            // Safari opens a link from another app in the profile in front, so put a window of this one there first.
            Task {
                _ = await SafariProfiles.bringToFront(profileNamed: name, safariURL: entry.appURL)
                openWithWorkspace(url, entry: entry)
            }
        }
    }

    private static func openWithWorkspace(_ url: URL, entry: BrowserEntry) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        Task {
            do {
                try await NSWorkspace.shared.open([url], withApplicationAt: entry.appURL, configuration: configuration)
            } catch {
                showFailure("Couldn't open \(entry.browserName): \(error.localizedDescription)")
            }
        }
    }

    /// Runs /usr/bin/open with an argument array; nothing in the URL is ever parsed by a shell.
    private static func runOpen(_ arguments: [String], browserName: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.terminationHandler = { finishedProcess in
            let status = finishedProcess.terminationStatus
            guard status != 0 else { return }

            Task { @MainActor in
                showFailure("Couldn't open \(browserName) (open exited with status \(status)).")
            }
        }

        do {
            try process.run()
        } catch {
            showFailure("Couldn't open \(browserName): \(error.localizedDescription)")
        }
    }

    private static func showFailure(_ message: String) {
        log.error("\(message, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Refined Settings"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activateRefinedSettings()
        alert.runModal()
    }
}
