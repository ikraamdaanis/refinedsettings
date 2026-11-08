import CoreGraphics
import Foundation

// Private WindowServer functions, also used by Hammerspoon and yabai. macOS has no public API for desktops.
@_silgen_name("CGSMainConnectionID")
private func mainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
private func activeSpace(_ connection: Int32) -> UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func copyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopySpacesForWindows")
private func copySpaces(_ connection: Int32, _ selector: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>?

enum DesktopSpaces {
    /// Mission Control's type for an ordinary desktop. Full-screen app spaces are 4.
    private static let desktopType = 0
    private static let allSpacesSelector: Int32 = 7

    static var activeID: UInt64 {
        activeSpace(mainConnectionID())
    }

    /// Space IDs for Desktop 1, Desktop 2 and so on, in macOS's numbering: displays in Mission Control order,
    /// full-screen app spaces skipped.
    static func desktopIDs() -> [UInt64] {
        guard let displays = copyManagedDisplaySpaces(mainConnectionID())?.takeRetainedValue() as? [[String: Any]] else { return [] }

        return displays.flatMap { display in
            let spaces = display["Spaces"] as? [[String: Any]] ?? []

            return spaces
                .filter { space in space["type"] as? Int == desktopType }
                .compactMap { space in space["ManagedSpaceID"] as? UInt64 }
        }
    }

    static func window(_ windowID: CGWindowID, isOn spaceID: UInt64) -> Bool {
        let windowIDs = [NSNumber(value: windowID)] as CFArray

        guard let spaceIDs = copySpaces(mainConnectionID(), allSpacesSelector, windowIDs)?.takeRetainedValue() as? [UInt64] else { return false }

        return spaceIDs.contains(spaceID)
    }
}
