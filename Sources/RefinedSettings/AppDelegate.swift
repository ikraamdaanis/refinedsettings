import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var isMenuBarIconShown = MenuBarIconSetting.isShown
    private var hasFinishedLaunching = false
    private var urlsReceivedDuringLaunch: [URL] = []
    private let settingsWindow = SettingsWindowController()
    private let mouseScrollReversal = EventTapSupervisor(isWanted: { MouseScrollSetting.reversesAnyAxis }, makeTap: ScrollReverser.makeTap)
    private let desktopCycling = DesktopCycler()
    private lazy var picker = PickerController(isSettingsVisible: { [weak self] in
        self?.settingsWindow.isVisible ?? false
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(syncWithSettings), name: UserDefaults.didChangeNotification, object: nil)
        mouseScrollReversal.sync()
        desktopCycling.sync()
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

    @objc private func syncWithSettings() {
        mouseScrollReversal.sync()
        desktopCycling.sync()
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
