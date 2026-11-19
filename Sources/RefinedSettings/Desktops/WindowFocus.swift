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

// Accessibility lists only the windows on the desktop you're on. An element made from a token can reach the rest, the
// way AltTab finds them.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func createElement(withRemoteToken token: CFData) -> Unmanaged<AXUIElement>?

enum WindowFocus {
    private static let frontWindowOnly: UInt32 = 1
    /// An app that has stopped responding shouldn't hold up the windows behind it for long.
    private static let accessibilityTimeout: Float = 1
    /// The token's marker for an element in another app, "coco".
    private static let remoteTokenMarker: Int32 = 0x636F_636F
    /// Element IDs to try when looking for windows on other desktops. Apps number their elements from 0, and windows
    /// come early.
    private static let elementIDsToTry: Range<UInt64> = 0..<1000
    /// How long the search for windows on other desktops may take, so an app that's slow to answer doesn't hold it up.
    private static let otherDesktopsSearchLimit: TimeInterval = 0.25

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
        guard let window = mainWindow(of: processID) else { return false }

        let isOnActiveDesktop = windowID(of: window).map { windowID in DesktopSpaces.window(windowID, isOn: DesktopSpaces.activeID) } ?? false

        if isOnActiveDesktop && NSWorkspace.shared.frontmostApplication?.processIdentifier == processID { return false }

        focus(window, of: processID)

        return true
    }

    /// The window an app would act on, which is the one in front while the app is.
    static func mainWindowID(of processID: pid_t) -> CGWindowID? {
        mainWindow(of: processID).flatMap(windowID(of:))
    }

    /// The windows of an app you'd switch between, on every desktop, oldest first, so the order holds still as each
    /// comes forward. Minimized windows and panels are left out.
    static func switchableWindows(of processID: pid_t) -> [(id: CGWindowID, element: AXUIElement)] {
        var windows = standardWindows(of: processID)
        let unlistedIDs = windowIDsOffActiveDesktop(of: processID).subtracting(windows.keys)

        if !unlistedIDs.isEmpty {
            for (windowID, window) in standardWindowsByElementID(of: processID) where unlistedIDs.contains(windowID) {
                windows[windowID] = window
            }
        }

        return windows
            .filter { _, window in !isMinimized(window) }
            .sorted { a, b in a.key < b.key }
            .map { windowID, window in (id: windowID, element: window) }
    }

    /// Brings a window to the front, and with it its app and the desktop it's on.
    static func focus(_ window: AXUIElement, of processID: pid_t) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        var process = ProcessSerialNumber()

        if getProcess(processID, &process) == noErr {
            _ = setFrontProcess(&process, frontWindowOnly)
        }
    }

    private static func mainWindow(of processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, accessibilityTimeout)
        var windowValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(application, kAXMainWindowAttribute as CFString, &windowValue) == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return nil }

        return unsafeDowncast(windowValue, to: AXUIElement.self)
    }

    private static func windowID(of window: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0

        return getWindowID(window, &windowID) == .success ? windowID : nil
    }

    /// The app's ordinary windows that show on some desktop other than the one you're on.
    private static func windowIDsOffActiveDesktop(of processID: pid_t) -> Set<CGWindowID> {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }

        let activeSpaceID = DesktopSpaces.activeID
        let windowIDs = windowInfos.compactMap { windowInfo -> CGWindowID? in
            guard windowInfo[kCGWindowOwnerPID as String] as? pid_t == processID,
                  windowInfo[kCGWindowLayer as String] as? Int == 0,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID
            else { return nil }

            let spaceIDs = DesktopSpaces.spaceIDs(of: windowID)

            return !spaceIDs.isEmpty && !spaceIDs.contains(activeSpaceID) ? windowID : nil
        }

        return Set(windowIDs)
    }

    /// Finds an app's windows by trying each element ID in turn, which reaches the windows on every desktop.
    private static func standardWindowsByElementID(of processID: pid_t) -> [CGWindowID: AXUIElement] {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: processID) { bytes in Data(bytes) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: remoteTokenMarker) { bytes in Data(bytes) })
        let deadline = Date.now.addingTimeInterval(otherDesktopsSearchLimit)
        var windows: [CGWindowID: AXUIElement] = [:]

        for elementID in elementIDsToTry {
            if Date.now > deadline { break }

            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { bytes in Data(bytes) })

            guard let element = createElement(withRemoteToken: token as CFData)?.takeRetainedValue() else { continue }

            AXUIElementSetMessagingTimeout(element, Float(otherDesktopsSearchLimit))

            if attribute(kAXRoleAttribute, of: element) == kAXWindowRole && isStandard(element), let windowID = windowID(of: element) {
                windows[windowID] = element
            }
        }

        return windows
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var isMinimized: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success else { return false }

        return isMinimized as? Bool ?? false
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }

        return value as? String
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
            if let windowID = windowID(of: window) {
                standardWindows[windowID] = window
            }
        }

        return standardWindows
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        attribute(kAXSubroleAttribute, of: window) == kAXStandardWindowSubrole
    }
}
