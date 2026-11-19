import AppKit
import Carbon.HIToolbox

/// Opens the app given a shortcut in Settings, or brings it forward if it's already open. With the app already in front
/// each press brings its next window forward, on any desktop, going round them again once each has had a turn. Apps
/// that share a shortcut take turns: once the app in front has shown each window, the next press moves on to the next
/// app in the list.
///
/// Hot keys rather than an event tap, so the shortcuts need no permission and keep working while an app has Secure
/// Input on. The super key reaches them as ⌃⌥⇧⌘ because its tap changes the flags before macOS matches hot keys.
@MainActor
final class AppShortcutLauncher {
    /// "RSAS", so the handler only answers this app's own hot keys.
    fileprivate nonisolated static let signature: OSType = 0x5253_4153
    /// How long an app that's been asked to come forward has to get there. A second press inside this time moves on
    /// from it, even if macOS hasn't brought it to the front yet.
    private static let activationGrace: Duration = .seconds(1.5)

    private var handler: EventHandlerRef?
    private var hotKeys = [EventHotKeyRef]()
    private var registeredGroups = [AppShortcutGroup]()
    private var lastOpened: (bundleID: String, at: ContinuousClock.Instant)?
    /// The windows of the app in front that have been in front since it came forward, so each gets one turn.
    private var windowTurns: (bundleID: String, windowIDs: Set<CGWindowID>)?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = activatedApp?.bundleIdentifier

            MainActor.assumeIsolated {
                // Another app in front starts the turns over, so coming back later begins with a full round.
                guard let self, self.windowTurns?.bundleID != bundleID else { return }

                self.windowTurns = nil
            }
        }
    }

    func sync() {
        let groups = ShortcutRecording.isActive ? [] : AppShortcutSetting.groups(of: AppShortcutSetting.load())

        guard groups != registeredGroups else { return }

        unregisterHotKeys()
        registeredGroups = groups

        guard !groups.isEmpty else { return }

        installHandlerIfNeeded()

        for (index, group) in groups.enumerated() {
            var newHotKey: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            let status = RegisterEventHotKey(UInt32(group.keyCode), group.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &newHotKey)

            guard status == noErr, let newHotKey else {
                log.error("Couldn't register the shortcut for \(group.bundleIDs, privacy: .public): \(status)")

                continue
            }

            hotKeys.append(newHotKey)
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData, let hotKeyIndex = ownHotKeyIndex(event) else { return OSStatus(eventNotHandledErr) }

            let launcher = Unmanaged<AppShortcutLauncher>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { launcher.hotKeyPressed(hotKeyIndex) }

            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        if status != noErr {
            log.error("Couldn't install the app shortcut handler: \(status)")
        }
    }

    private func unregisterHotKeys() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }

        hotKeys = []
        registeredGroups = []
    }

    private func hotKeyPressed(_ hotKeyIndex: Int) {
        guard registeredGroups.indices.contains(hotKeyIndex) else { return }

        let bundleIDs = registeredGroups[hotKeyIndex].bundleIDs
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        guard let firstBundleID = bundleIDs.first else { return }

        guard let currentBundleID = currentBundleID(frontmostApp), let currentIndex = bundleIDs.firstIndex(of: currentBundleID) else {
            open(firstBundleID)

            return
        }

        if focusNextWindow(of: currentBundleID) { return }

        windowTurns = nil

        // An app with the shortcut to itself stays in front: its windows go round again. Opening it covers an app
        // that has no window to switch to, which then gets one, as it would from its Dock icon.
        if bundleIDs.count == 1 {
            if !focusNextWindow(of: currentBundleID) {
                open(currentBundleID)
            }

            return
        }

        open(bundleIDs[(currentIndex + 1) % bundleIDs.count])
    }

    /// Brings forward the app's next window that hasn't had a turn yet, counting on from the one in front. Returns
    /// false once every window has had one, or when there's no window to switch to.
    private func focusNextWindow(of bundleID: String) -> Bool {
        guard AXIsProcessTrusted(), let app = runningApp(bundleID) else { return false }

        let windows = WindowFocus.switchableWindows(of: app.processIdentifier)
        let frontWindowID = WindowFocus.mainWindowID(of: app.processIdentifier)
        var turns = windowTurns?.bundleID == bundleID ? windowTurns?.windowIDs ?? [] : []

        if let frontWindowID {
            turns.insert(frontWindowID)
        }

        let nextIndex = windows.firstIndex { window in window.id == frontWindowID }.map { frontIndex in frontIndex + 1 } ?? 0
        let windowsFromNext = windows[nextIndex...] + windows[..<nextIndex]

        guard let nextWindow = windowsFromNext.first(where: { window in !turns.contains(window.id) }) else { return false }

        turns.insert(nextWindow.id)
        windowTurns = (bundleID, turns)
        WindowFocus.focus(nextWindow.element, of: app.processIdentifier)

        return true
    }

    /// The app's copy that's in front, or else any copy of it that's running.
    private func runningApp(_ bundleID: String) -> NSRunningApplication? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { runningApp in !runningApp.isTerminated }

        return runningApps.first { runningApp in runningApp.isActive } ?? runningApps.first
    }

    /// The app in front, or the one just asked to come forward if it's still on its way.
    private func currentBundleID(_ frontmostApp: NSRunningApplication?) -> String? {
        if let lastOpened, ContinuousClock.now - lastOpened.at < Self.activationGrace {
            return lastOpened.bundleID
        }

        return frontmostApp?.bundleIdentifier
    }

    private func open(_ bundleID: String) {
        let appShortcut = AppShortcutSetting.load().first { candidate in candidate.bundleID == bundleID }

        guard let appURL = appShortcut?.appURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.error("Couldn't find \(bundleID, privacy: .public) to open it")
            NSSound.beep()

            return
        }

        lastOpened = (bundleID, ContinuousClock.now)
        AppActivation.open(appURL, bundleID: bundleID)
    }
}

/// The index this app gave the hot key that was pressed, or nil for another part of the app's hot keys.
private func ownHotKeyIndex(_ event: EventRef) -> Int? {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr, hotKeyID.signature == AppShortcutLauncher.signature else { return nil }

    return Int(hotKeyID.id)
}
