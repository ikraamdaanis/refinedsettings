import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// A window's ID has no public route from Accessibility, and bringing just one window forward has no public API.
@_silgen_name("_AXUIElementGetWindow")
private func getWindowID(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("GetProcessForPID")
private func getProcess(_ processID: pid_t, _ process: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("SetFrontProcessWithOptions")
private func setFrontProcess(_ process: UnsafePointer<ProcessSerialNumber>, _ options: UInt32) -> OSStatus

enum WindowFocus {
    private static let frontWindowOnly: UInt32 = 1
    /// An app that has stopped responding shouldn't hold up the windows behind it for long.
    private static let accessibilityTimeout: Float = 1

    /// Focuses the window at the back of a desktop. It comes to the front, so the next call finds a different one and
    /// repeated calls rotate through them all.
    static func focusBackmostWindow(on spaceID: UInt64) {
        guard let frontToBack = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        var windowsByProcess: [pid_t: [CGWindowID: AXUIElement]] = [:]

        for windowInfo in frontToBack.reversed() {
            guard windowInfo[kCGWindowLayer as String] as? Int == 0,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let processID = windowInfo[kCGWindowOwnerPID as String] as? pid_t
            else { continue }

            let windows = windowsByProcess[processID] ?? standardWindows(of: processID)
            windowsByProcess[processID] = windows

            guard let window = windows[windowID], DesktopSpaces.window(windowID, isOn: spaceID) else { continue }

            focus(window, of: processID)

            return
        }
    }

    /// Brings an app's main window to the front, and with it the desktop that window is on, unless the app is already
    /// in front with that window on the desktop you're on. Returns whether it had to.
    @MainActor
    @discardableResult
    static func bringMainWindowForward(of processID: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, accessibilityTimeout)
        var windowValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(application, kAXMainWindowAttribute as CFString, &windowValue) == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return false }

        let window = unsafeDowncast(windowValue, to: AXUIElement.self)
        var windowID: CGWindowID = 0
        let isOnActiveDesktop = getWindowID(window, &windowID) == .success && DesktopSpaces.window(windowID, isOn: DesktopSpaces.activeID)

        if isOnActiveDesktop && NSWorkspace.shared.frontmostApplication?.processIdentifier == processID { return false }

        focus(window, of: processID)

        return true
    }

    private static func standardWindows(of processID: pid_t) -> [CGWindowID: AXUIElement] {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, accessibilityTimeout)
        var windowsValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else { return [:] }

        var standardWindows: [CGWindowID: AXUIElement] = [:]

        for window in windows where isStandard(window) {
            var windowID: CGWindowID = 0

            if getWindowID(window, &windowID) == .success {
                standardWindows[windowID] = window
            }
        }

        return standardWindows
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success else { return false }

        return subrole as? String == kAXStandardWindowSubrole
    }

    private static func focus(_ window: AXUIElement, of processID: pid_t) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        var process = ProcessSerialNumber()

        if getProcess(processID, &process) == noErr {
            _ = setFrontProcess(&process, frontWindowOnly)
        }
    }
}
