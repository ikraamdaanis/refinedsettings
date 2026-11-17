import AppKit

/// Hands a link to the browser (and profile) picked for it. Every path names the target app,
/// so a link is never passed back to the default browser, which is Refined Settings.
@MainActor
enum BrowserLauncher {
    /// How long a running browser gets, once it has the link, to come to the front by itself.
    private static let settleDelay: Duration = .milliseconds(150)
    /// Shows the profile in Ardia's front window, then opens the link as a new tab there. Its arguments are the profile
    /// ID, the link, and whether Ardia is being launched, in which case it gets a moment to restore its windows.
    private static let ardiaScript = """
        on run {profileID, linkURL, launchState}
            tell application id "\(BrowserCatalog.ardiaBundleID)"
                activate
                if launchState is "launching" then
                    repeat 50 times
                        if (count of windows) > 0 then exit repeat
                        delay 0.1
                    end repeat
                end if
                if (count of windows) is 0 then make new window
                focus (first profile whose id is profileID)
                make new tab with properties {URL:linkURL}
            end tell
        end run
        """

    static func open(_ url: URL, with entry: BrowserEntry) {
        guard !AppInfo.isRefinedSettings(entry.appURL) else { return }

        let bundleID = Bundle(url: entry.appURL)?.bundleIdentifier
        let runningProcessIDs = Set(runningInstances(of: bundleID).map { app in app.processIdentifier })
        yieldActivation(to: bundleID)
        let handedOver: @MainActor @Sendable () -> Void = { bringForwardOnceSettled(bundleID: bundleID, runningProcessIDs: runningProcessIDs) }

        switch entry.launchMethod {
        case .workspace:
            openWithWorkspace(url, entry: entry, then: handedOver)
        case .chromiumProfile(let directory):
            // Equivalent to: open -na "<browser>" --args --profile-directory=<dir> <url>
            runOpen(["-na", entry.appURL.path, "--args", "--profile-directory=\(directory)", url.absoluteString], browserName: entry.browserName, then: handedOver)
        case .firefoxProfile(let name):
            // Firefox forwards the link to the running instance of this profile, or starts it.
            runOpen(["-na", entry.appURL.path, "--args", "-P", name, url.absoluteString], browserName: entry.browserName, then: handedOver)
        case .safariProfile(let name):
            // Safari opens a link from another app in the profile in front, so put a window of this one there first.
            Task {
                _ = await SafariProfiles.bringToFront(profileNamed: name, safariURL: entry.appURL)
                openWithWorkspace(url, entry: entry, then: handedOver)
            }
        case .ardiaProfile(let id):
            let launchState = runningProcessIDs.isEmpty ? "launching" : "running"
            run("/usr/bin/osascript", ["-e", ardiaScript, id, url.absoluteString, launchState], browserName: entry.browserName, then: handedOver)
        }
    }

    /// From macOS 14 an app comes to the front only when the active app lets it. Refined Settings is active while the
    /// picker is up, so it hands that over, and the browser can come to the front once the link is in.
    private static func yieldActivation(to bundleID: String?) {
        guard #available(macOS 14, *), let bundleID else { return }

        NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
    }

    /// A browser that was already running doesn't always manage to come to the front with the link: it lands in a
    /// window on another desktop and you're left where you were. Once it has had a moment, bring that window (the one
    /// it made its main window for the link) forward, which takes you to its desktop. A browser that's just been
    /// launched is brought forward by macOS, and with no Accessibility access this can't be done.
    private static func bringForwardOnceSettled(bundleID: String?, runningProcessIDs: Set<pid_t>) {
        guard !runningProcessIDs.isEmpty, AXIsProcessTrusted() else { return }

        Task {
            // A Chromium browser or Firefox gets the link from a second copy of itself, which passes it on and quits.
            for _ in 0..<40 {
                if runningInstances(of: bundleID).allSatisfy({ app in runningProcessIDs.contains(app.processIdentifier) }) { break }

                try? await Task.sleep(for: .milliseconds(50))
            }

            try? await Task.sleep(for: settleDelay)

            guard let browser = runningInstances(of: bundleID).first(where: { app in runningProcessIDs.contains(app.processIdentifier) }) else { return }

            WindowFocus.bringMainWindowForward(of: browser.processIdentifier)
        }
    }

    private static func runningInstances(of bundleID: String?) -> [NSRunningApplication] {
        guard let bundleID else { return [] }

        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { app in !app.isTerminated }
    }

    private static func openWithWorkspace(_ url: URL, entry: BrowserEntry, then handedOver: @escaping @MainActor @Sendable () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        Task {
            do {
                try await NSWorkspace.shared.open([url], withApplicationAt: entry.appURL, configuration: configuration)
                handedOver()
            } catch {
                showFailure("Couldn't open \(entry.browserName): \(error.localizedDescription)")
            }
        }
    }

    private static func runOpen(_ arguments: [String], browserName: String, then handedOver: @escaping @MainActor @Sendable () -> Void) {
        run("/usr/bin/open", arguments, browserName: browserName, then: handedOver)
    }

    /// Runs a tool with an argument array; nothing in the URL is ever parsed by a shell. What it printed as an error,
    /// such as macOS refusing it control of the browser, goes in the alert when it fails.
    private static func run(_ executablePath: String, _ arguments: [String], browserName: String, then handedOver: @escaping @MainActor @Sendable () -> Void) {
        let process = Process()
        let errorOutput = Pipe()
        let toolName = URL(fileURLWithPath: executablePath).lastPathComponent
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput
        process.terminationHandler = { finishedProcess in
            let status = finishedProcess.terminationStatus
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            Task { @MainActor in
                if status == 0 {
                    handedOver()
                } else {
                    let detail = errorText.isEmpty ? "" : "\n\n\(errorText)"
                    showFailure("Couldn't open \(browserName) (\(toolName) exited with status \(status)).\(detail)")
                }
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
