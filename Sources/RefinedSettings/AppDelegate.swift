import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var isMenuBarIconShown = MenuBarIconSetting.isShown
    private var hasFinishedLaunching = false
    private var urlsReceivedDuringLaunch: [URL] = []
    private var settingsObserver: NSObjectProtocol?
    private var shortcutRecordingObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var terminationSignal: DispatchSourceSignal?
    private var isCapsLockRemapped: Bool?
    private let settingsWindow = SettingsWindowController()
    private let mouseScrollReversal = EventTapSupervisor(isWanted: { MouseScrollSetting.reversesAnyAxis }, makeTap: ScrollReverser.makeTap)
    private let mouseButtonRemapping = EventTapSupervisor(isWanted: { MouseButtonSetting.remapsAnyButton }, makeTap: ButtonRemapper.makeTap)
    private let desktopCycling = DesktopCycler()
    private let appShortcuts = AppShortcutLauncher()
    private lazy var superKey = EventTapSupervisor(isWanted: { SuperKeySetting.isOn }, makeTap: SuperKey.makeTap) { [weak self] _ in
        self?.syncCapsLockRemap()
    }
    private lazy var picker = PickerController(isSettingsVisible: { [weak self] in
        self?.settingsWindow.isVisible ?? false
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()
        quitCleanlyOnTerminationSignal()
        // On the main queue, because this notification arrives on whichever thread changed a setting.
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncWithSettings() }
        }
        // The HID system can drop the Caps Lock mapping across sleep, so it goes back on afterwards.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isCapsLockRemapped = nil
                self?.syncCapsLockRemap()
            }
        }
        shortcutRecordingObserver = NotificationCenter.default.addObserver(forName: ShortcutRecording.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appShortcuts.sync() }
        }
        mouseScrollReversal.sync()
        mouseButtonRemapping.sync()
        desktopCycling.sync()
        superKey.sync()
        syncCapsLockRemap()
        appShortcuts.sync()
        hasFinishedLaunching = true

        // With no menu bar icon, opening the app is the only way to reach Settings.
        if !MenuBarIconSetting.isShown && urlsReceivedDuringLaunch.isEmpty && !wasLaunchedAtLogin {
            settingsWindow.show()
        }

        picker.enqueue(urlsReceivedDuringLaunch)
        urlsReceivedDuringLaunch = []
    }

    private var wasLaunchedAtLogin: Bool {
        guard let launchEvent = NSAppleEventManager.shared().currentAppleEvent else { return false }

        return launchEvent.eventID == kAEOpenApplication
            && launchEvent.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Caps Lock is a dead key while it's remapped and nothing reads it, so the remap only stays while the super key's
    /// tap is running.
    private func syncCapsLockRemap() {
        let isWanted = SuperKeySetting.key == .capsLock && superKey.isRunning

        // Every settings change lands here, including window sizes being saved, and the remap is a round trip to the
        // HID system. The first call always goes through, to clear a remap a crashed copy left behind.
        guard isWanted != isCapsLockRemapped else { return }

        isCapsLockRemapped = isWanted
        CapsLockRemap.sync(isWanted: isWanted)
    }

    func applicationWillTerminate(_ notification: Notification) {
        CapsLockRemap.sync(isWanted: false)
    }

    /// `kill` and `build.sh` stop the app with SIGTERM, which skips `applicationWillTerminate`. Quitting normally
    /// instead puts Caps Lock back.
    private func quitCleanlyOnTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSignal = source
    }

    private func syncWithSettings() {
        mouseScrollReversal.sync()
        mouseButtonRemapping.sync()
        desktopCycling.sync()
        superKey.sync()
        syncCapsLockRemap()
        appShortcuts.sync()
        syncMenuBarIcon()
    }

    private func syncMenuBarIcon() {
        let isShown = MenuBarIconSetting.isShown

        guard isShown != isMenuBarIconShown else { return }

        // Recorded first: setting isVisible writes to UserDefaults itself, which lands back here.
        isMenuBarIconShown = isShown
        statusItem?.isVisible = isShown
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let supportedURLs = urls.filter(LinkTarget.isSupported)

        // A cold launch can deliver URLs before didFinishLaunching; hold them until the UI is ready.
        guard hasFinishedLaunching else {
            urlsReceivedDuringLaunch.append(contentsOf: supportedURLs)

            return
        }

        picker.enqueue(supportedURLs)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()

        return false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = GearGlyph.image(pointSize: 17, accessibilityDescription: "Refined Settings")
        let menu = NSMenu()
        menu.addItem(makeSettingsItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Refined Settings", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        item.isVisible = MenuBarIconSetting.isShown
        statusItem = item
    }

    /// The menu bar shown while Refined Settings is a regular Dock app (whenever Settings is open).
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Refined Settings", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(makeSettingsItem())
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Refined Settings", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Refined Settings", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        // Text fields take ⌘Z, ⌘X, ⌘C, ⌘V and ⌘A from these items. With no Edit menu the shortcuts do nothing.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    /// From macOS 26, menus show an icon next to standard items; Settings… gets the app's own gear rather than
    /// the system's. Earlier versions show no menu icons, so neither does this item there.
    private func makeSettingsItem() -> NSMenuItem {
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        if #available(macOS 26, *) {
            settingsItem.image = GearGlyph.image(pointSize: 15, accessibilityDescription: nil)
        }

        return settingsItem
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
