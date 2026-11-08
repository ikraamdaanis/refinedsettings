import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A standard titled window that can take keyboard focus without activating Refined Settings,
/// so the app you clicked the link in keeps its place.
final class PickerWindow: NSPanel {
    /// Returns true when the key press was handled and should not reach the SwiftUI content.
    var onKeyDown: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: true)
        title = "Open Link"
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true { return }

        super.sendEvent(event)
    }
}

/// Shows one prompt at a time and queues any links that arrive while a prompt is open.
@MainActor
final class PickerController {
    private var queue: [URL] = []
    private var currentURL: URL?
    private let isSettingsVisible: () -> Bool
    private let model = PickerModel()
    private let window = PickerWindow()
    private lazy var hostingView = NSHostingView(rootView: PickerView(
        model: model,
        onOpen: { [weak self] entry in self?.finish(choosing: entry) },
        onCancel: { [weak self] in self?.finish(choosing: nil) }
    ))
    private var globalClickMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    init(isSettingsVisible: @escaping () -> Bool) {
        self.isSettingsVisible = isSettingsVisible
        window.contentView = hostingView
    }

    func enqueue(_ urls: [URL]) {
        // Some apps deliver the same link twice in quick succession; drop exact duplicates.
        for url in urls where url != currentURL && !queue.contains(url) {
            queue.append(url)
        }

        model.queuedCount = queue.count

        if currentURL == nil {
            showNext()
        }
    }

    private func showNext() {
        guard currentURL == nil, !queue.isEmpty else { return }

        let url = queue.removeFirst()
        currentURL = url
        model.headline = LinkTarget.headline(for: url)
        model.fullURL = url.isFileURL ? url.path : url.absoluteString
        model.queuedCount = queue.count
        model.entries = BrowserCatalog.visibleEntries()
        model.selectedIndex = 0

        // SwiftUI applies the new rows on the next pass; measure and centre after that.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentURL == url else { return }

            self.window.setContentSize(self.hostingView.fittingSize)
            self.centreWindow()
            self.window.makeKeyAndOrderFront(nil)
            self.installMonitors()
        }
    }

    private func centreWindow() {
        window.setFrameOrigin(Self.centredOrigin(for: window.frame.size))
    }

    private func finish(choosing entry: BrowserEntry?) {
        guard let url = currentURL else { return }

        removeMonitors()
        window.orderOut(nil)
        currentURL = nil

        // Opening a link activates Refined Settings. With a browser picked, the browser takes focus as it opens. On a
        // cancel, focus goes to the front window on this desktop. Hiding Refined Settings instead would hand focus to
        // the app the link came from, and macOS switches to that app's desktop when its windows are elsewhere.
        if let entry {
            BrowserLauncher.open(url, with: entry)
        } else if NSApp.isActive && !isSettingsVisible() {
            Self.frontAppOnCurrentDesktop()?.activateApp()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showNext()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        let entries = model.entries

        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            finish(choosing: nil)

            return true
        }

        guard modifiers.isEmpty else { return false }

        switch Int(event.keyCode) {
        case kVK_Escape:
            finish(choosing: nil)

            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if entries.indices.contains(model.selectedIndex) {
                finish(choosing: entries[model.selectedIndex])
            }

            return true
        case kVK_DownArrow:
            if !entries.isEmpty {
                model.selectedIndex = min(model.selectedIndex + 1, entries.count - 1)
            }

            return true
        case kVK_UpArrow:
            model.selectedIndex = max(model.selectedIndex - 1, 0)

            return true
        default:
            break
        }

        guard
            let characters = event.charactersIgnoringModifiers,
            let number = Int(characters),
            (1...9).contains(number),
            entries.indices.contains(number - 1)
        else { return false }

        finish(choosing: entries[number - 1])

        return true
    }

    private func installMonitors() {
        removeMonitors()
        window.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        // Clicks in other apps cancel via the global monitor; anything else that takes focus away
        // (another app activating, a click in Settings) cancels via resignKey; the close button via willClose.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finish(choosing: nil)
            }
        }

        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.finish(choosing: nil)
                }
            })
        }

        // Keep the window dead centre if SwiftUI resizes it while it is showing.
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.centreWindow()
            }
        })
    }

    private func removeMonitors() {
        window.onKeyDown = nil

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }

        globalClickMonitor = nil

        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }

        windowObservers = []
    }

    /// The app that owns the frontmost ordinary window on the current desktop, skipping Refined Settings. Nil on an
    /// empty desktop, in which case focus stays where it is.
    private static func frontAppOnCurrentDesktop() -> NSRunningApplication? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        for window in windows {
            guard
                window[kCGWindowLayer as String] as? Int == 0,
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID != ownPID,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                (bounds["Width"] ?? 0) > 40,
                (bounds["Height"] ?? 0) > 40,
                let app = NSRunningApplication(processIdentifier: ownerPID),
                app.activationPolicy == .regular
            else { continue }

            return app
        }

        return nil
    }

    /// Dead centre of the screen the cursor is on.
    private static func centredOrigin(for size: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in NSMouseInRect(cursor, screen.frame, false) } ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(origin: .zero, size: size)

        return NSPoint(x: (frame.midX - size.width / 2).rounded(), y: (frame.midY - size.height / 2).rounded())
    }
}
