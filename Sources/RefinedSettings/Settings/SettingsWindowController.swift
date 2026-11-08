import AppKit
import SwiftUI

/// Settings is the one place Refined Settings behaves like a normal app: while it is open, Refined Settings sits in the Dock
/// (so it can be assigned to a desktop from the Dock menu) and has a menu bar; closing it puts Refined Settings back
/// in the menu bar only.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// System Settings' window on macOS 26: a fixed width that only resizes vertically.
    private static let contentWidth: CGFloat = 723
    private static let defaultContentHeight: CGFloat = 565
    private static let minimumContentHeight: CGFloat = 420

    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let settingsWindow = window ?? makeWindow()

        // A Settings window left open on another desktop would pull you over to it. Take it off that desktop,
        // so macOS shows it on the current one (or on the desktop Refined Settings is assigned to in the Dock).
        if settingsWindow.isVisible && !settingsWindow.isOnActiveSpace {
            settingsWindow.orderOut(nil)
        }

        if !settingsWindow.isVisible {
            settingsWindow.center()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activateRefinedSettings()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Hand focus back to whatever was in front before Settings opened.
        DispatchQueue.main.async {
            NSApp.hide(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let contentSize = NSSize(width: Self.contentWidth, height: Self.defaultContentHeight)
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let hostingController = NSHostingController(rootView: SettingsRootView(navigation: navigation))
        // The window decides its own size; the panes scroll inside it.
        hostingController.sizingOptions = []

        // SwiftUI fills the toolbar; the title stays with the window so it keeps the pane's name when the toolbar hides it.
        if #available(macOS 14, *) {
            hostingController.sceneBridgingOptions = [.toolbars]
        }

        // At full size before it joins the window, or the split view lays its sidebar out for a zero-width window.
        hostingController.view.setFrameSize(contentSize)
        newWindow.contentViewController = hostingController
        newWindow.setContentSize(contentSize)
        newWindow.contentMinSize = NSSize(width: Self.contentWidth, height: Self.minimumContentHeight)
        newWindow.contentMaxSize = NSSize(width: Self.contentWidth, height: .greatestFiniteMagnitude)
        newWindow.title = navigation.pane.title
        newWindow.toolbarStyle = .unified
        // Like System Settings, and full screen breaks the sidebar on macOS 26.
        newWindow.collectionBehavior.insert(.fullScreenNone)
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        navigation.window = newWindow
        window = newWindow

        return newWindow
    }
}
