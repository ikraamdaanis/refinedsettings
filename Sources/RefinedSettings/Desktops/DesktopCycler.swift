import AppKit
import Carbon.HIToolbox

/// Takes over the "Switch to Desktop N" shortcut for the desktop you're already on, where macOS would do nothing, and
/// uses it to cycle through that desktop's windows. A hot key rather than an event tap, because macOS hides key presses
/// from every event tap while any app has Secure Input on (a focused password field, say), and hot keys still fire.
@MainActor
final class DesktopCycler {
    /// "RSDC", so the handler only answers this app's own hot key.
    fileprivate nonisolated static let signature: OSType = 0x5253_4443
    /// Picks up a shortcut changed in System Settings, which sends no notification.
    private static let shortcutRefreshInterval: Duration = .seconds(5)

    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var registeredShortcut: DesktopShortcut?
    private var spaceObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?

    func sync() {
        guard DesktopCyclingSetting.isOn else {
            stop()

            return
        }

        installHandlerIfNeeded()
        startWatchingIfNeeded()
        registerShortcutForActiveDesktop()
    }

    private func stop() {
        unregisterHotKey()
        refreshTask?.cancel()
        refreshTask = nil

        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }

        spaceObserver = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData, isOwnHotKey(event) else { return OSStatus(eventNotHandledErr) }

            let cycler = Unmanaged<DesktopCycler>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { cycler.hotKeyPressed() }

            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        if status != noErr {
            log.error("Couldn't install the desktop hot key handler: \(status)")
        }
    }

    private func startWatchingIfNeeded() {
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.registerShortcutForActiveDesktop() }
            }
        }

        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.shortcutRefreshInterval)
                self?.registerShortcutForActiveDesktop()
            }
        }
    }

    /// Only the active desktop's shortcut is taken, so the others keep switching desktops as usual.
    private func registerShortcutForActiveDesktop() {
        let desktopIDs = DesktopSpaces.desktopIDs()
        let activeNumber = desktopIDs.firstIndex(of: DesktopSpaces.activeID).map { index in index + 1 }
        let shortcut = DesktopShortcut.loadAll().first { candidate in candidate.desktopNumber == activeNumber }

        guard shortcut != registeredShortcut else { return }

        unregisterHotKey()

        guard let shortcut else { return }

        var newHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(shortcut.desktopNumber))
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &newHotKey)

        guard status == noErr, let newHotKey else {
            log.error("Couldn't register \(shortcut.displayName, privacy: .public) for Desktop \(shortcut.desktopNumber): \(status)")

            return
        }

        hotKey = newHotKey
        registeredShortcut = shortcut
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }

        hotKey = nil
        registeredShortcut = nil
    }

    private func hotKeyPressed() {
        guard let shortcut = registeredShortcut else { return }

        let desktopIDs = DesktopSpaces.desktopIDs()
        let spaceID = shortcut.desktopNumber <= desktopIDs.count ? desktopIDs[shortcut.desktopNumber - 1] : nil

        guard spaceID == DesktopSpaces.activeID, let spaceID else {
            passToMacOS(shortcut)

            return
        }

        WindowFocus.focusBackmostWindow(on: spaceID)
    }

    /// The desktop changed before the hot key moved with it, so the press was meant to switch desktops. Hands it back
    /// to macOS by pressing it again with the hot key out of the way.
    private func passToMacOS(_ shortcut: DesktopShortcut) {
        unregisterHotKey()
        shortcut.post()
        registerShortcutForActiveDesktop()
    }
}

private func isOwnHotKey(_ event: EventRef) -> Bool {
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

    return status == noErr && hotKeyID.signature == DesktopCycler.signature
}
