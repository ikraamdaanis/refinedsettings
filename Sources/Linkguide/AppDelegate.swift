import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hasFinishedLaunching = false
    private var urlsReceivedDuringLaunch: [URL] = []
    private let settingsWindow = SettingsWindowController()
    private lazy var picker = PickerController(isSettingsVisible: { [weak self] in
        self?.settingsWindow.isVisible ?? false
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()
        hasFinishedLaunching = true
        picker.enqueue(urlsReceivedDuringLaunch)
        urlsReceivedDuringLaunch = []
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
        // 15 pt draws the gear at 18 px tall, 2 px up on the default 13 pt.
        let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Linkguide")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Linkguide", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// The menu bar shown while Linkguide is a regular Dock app (whenever Settings is open).
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Linkguide", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Linkguide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Linkguide", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
