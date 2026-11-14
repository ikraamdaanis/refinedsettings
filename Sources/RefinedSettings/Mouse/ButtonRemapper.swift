import AppKit
import Carbon.HIToolbox
import CoreGraphics
import os

// The Dock's own way in to Mission Control and its relatives, which Mac Mouse Fix also uses. Unlike pressing their
// shortcuts, it keeps working when the shortcut has been changed or switched off.
@_silgen_name("CoreDockSendNotification")
private func sendDockNotification(_ notification: CFString, _ unused: Int32)

/// Gives mouse buttons the actions picked in Settings. Only the tap thread touches `swallowedButtons`.
final class ButtonRemapper: @unchecked Sendable {
    /// Set while the button tester is on screen in front, so presses there show what the mouse really sends.
    static let isTesting = OSAllocatedUnfairLock(initialState: false)
    /// Apps that already go back and forward with the side buttons. There the buttons pass straight through, since ⌘[
    /// means something else in some of them, such as outdenting a line in VS Code.
    private static let appsWithSideButtons: Set<String> = [
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
    ]

    private var swallowedButtons = Set<Int64>()
    private let frontmostBundleID = OSAllocatedUnfairLock<String?>(initialState: nil)
    private let workspaceCenter = NSWorkspace.shared.notificationCenter
    private var activationObserver: NSObjectProtocol?

    @MainActor
    private init() {
        frontmostBundleID.withLock { bundleID in bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        activationObserver = workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [frontmostBundleID] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            frontmostBundleID.withLock { bundleID in bundleID = app?.bundleIdentifier }
        }
    }

    deinit {
        if let activationObserver {
            workspaceCenter.removeObserver(activationObserver)
        }
    }

    @MainActor
    static func makeTap() -> EventTap {
        let remapper = ButtonRemapper()

        return EventTap(
            location: .cghidEventTap,
            eventTypes: [.otherMouseDown, .otherMouseUp, .otherMouseDragged],
            threadName: "com.ikraam.refinedsettings.button-tap"
        ) { type, event in
            remapper.shouldKeep(type, event)
        }
    }

    private func shouldKeep(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        switch type {
        case .otherMouseDown:
            return !takeOver(button)
        case .otherMouseUp:
            return swallowedButtons.remove(button) == nil
        default:
            return !swallowedButtons.contains(button)
        }
    }

    /// True when the press is handled here. Its drags and release are then swallowed too, so apps never see half a click.
    private func takeOver(_ button: Int64) -> Bool {
        guard !Self.isTesting.withLock({ isTesting in isTesting }) else { return false }
        guard let mapping = MouseButtonSetting.mappings()[Int(button)], mapping.takesOverButton else { return false }
        guard !alreadyDoes(mapping.action, button: button) else { return false }

        // Recorded before acting, so the release is swallowed even if the setting changes while the button is down.
        swallowedButtons.insert(button)
        perform(mapping)

        return true
    }

    private func alreadyDoes(_ action: MouseButtonAction, button: Int64) -> Bool {
        let isNativeButton = (action == .back && button == MouseButtonSetting.backButton)
            || (action == .forward && button == MouseButtonSetting.forwardButton)

        guard isNativeButton else { return false }

        let bundleID = frontmostBundleID.withLock { bundleID in bundleID }

        return bundleID.map { identifier in Self.appsWithSideButtons.contains(identifier) } ?? false
    }

    private func perform(_ mapping: MouseButtonMapping) {
        switch mapping.action {
        case .off:
            break
        case .back:
            KeyPress.post(keyCode: CGKeyCode(kVK_ANSI_LeftBracket), modifiers: .maskCommand)
        case .forward:
            KeyPress.post(keyCode: CGKeyCode(kVK_ANSI_RightBracket), modifiers: .maskCommand)
        case .missionControl:
            sendDockNotification("com.apple.expose.awake" as CFString, 0)
        case .appWindows:
            sendDockNotification("com.apple.expose.front.awake" as CFString, 0)
        case .showDesktop:
            sendDockNotification("com.apple.showdesktop.awake" as CFString, 0)
        case .keyboardShortcut:
            mapping.shortcut?.post()
        }
    }
}
