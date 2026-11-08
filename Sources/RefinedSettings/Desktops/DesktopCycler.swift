import CoreGraphics
import Foundation

/// Takes over the "Switch to Desktop N" shortcut for the desktop you're already on, where macOS would do nothing, and
/// uses it to cycle through that desktop's windows. Only the tap thread touches the stored state.
final class DesktopCycler: @unchecked Sendable {
    private var shortcuts: [DesktopShortcut] = []
    private var shortcutsExpiry = ContinuousClock.now

    static func makeTap() -> EventTap {
        let cycler = DesktopCycler()

        return EventTap(location: .cgSessionEventTap, eventType: .keyDown, threadName: "com.ikraam.refinedsettings.desktop-tap") { event in
            cycler.shouldKeep(event)
        }
    }

    private func shouldKeep(_ event: CGEvent) -> Bool {
        guard DesktopCyclingSetting.isOn else { return true }

        refreshShortcutsIfExpired()

        guard let shortcut = shortcuts.first(where: { candidate in candidate.matches(event) }) else { return true }

        let desktopIDs = DesktopSpaces.desktopIDs()

        guard shortcut.desktopNumber <= desktopIDs.count else { return true }

        let spaceID = desktopIDs[shortcut.desktopNumber - 1]

        guard spaceID == DesktopSpaces.activeID else { return true }

        // Once per physical press; key repeat is swallowed without cycling. Off this thread, so a slow app can't stall
        // typing, and on the main one because Accessibility calls on this app's own Settings window run inside AppKit.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { WindowFocus.focusBackmostWindow(on: spaceID) }
        }

        return false
    }

    /// So a shortcut changed in System Settings takes effect without restarting anything.
    private func refreshShortcutsIfExpired() {
        guard ContinuousClock.now >= shortcutsExpiry else { return }

        shortcuts = DesktopShortcut.loadAll()
        shortcutsExpiry = ContinuousClock.now.advanced(by: .seconds(5))
    }
}
