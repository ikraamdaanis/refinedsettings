import CoreGraphics
import Foundation

/// A "Switch to Desktop N" shortcut from System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
struct DesktopShortcut {
    /// The modifier bits macOS stores for a shortcut are the same as `CGEventFlags`.
    private static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
    /// AppleSymbolicHotKeys IDs 118 to 126 are "Switch to Desktop 1" to "Switch to Desktop 9".
    private static let firstHotKeyID = 118
    /// Stored in place of a character for keys that don't type one, such as the arrow keys.
    private static let noCharacter = 65535

    let desktopNumber: Int
    let character: Int
    let keyCode: Int64
    let modifiers: CGEventFlags

    /// Written like a menu shortcut, for example ⇧⌘1.
    var displayName: String {
        let symbols: [(flag: CGEventFlags, symbol: String)] = [
            (.maskSecondaryFn, "fn "),
            (.maskControl, "⌃"),
            (.maskAlternate, "⌥"),
            (.maskShift, "⇧"),
            (.maskCommand, "⌘"),
        ]
        let modifierSymbols = symbols.filter { candidate in modifiers.contains(candidate.flag) }.map { candidate in candidate.symbol }.joined()
        let key = character == Self.noCharacter ? "key \(keyCode)" : UnicodeScalar(character).map { scalar in String(scalar).uppercased() } ?? "key \(keyCode)"

        return modifierSymbols + key
    }

    func matches(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == keyCode && event.flags.intersection(Self.modifierMask) == modifiers
    }

    /// Reads the file itself because CFPreferences would keep serving this process a cached copy.
    static func loadAll() -> [DesktopShortcut] {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")

        guard let data = try? Data(contentsOf: fileURL),
              let preferences = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let hotKeys = preferences["AppleSymbolicHotKeys"] as? [String: Any]
        else { return [] }

        return (1...9).compactMap { desktopNumber in
            guard let hotKey = hotKeys[String(firstHotKeyID + desktopNumber - 1)] as? [String: Any],
                  hotKey["enabled"] as? Bool == true,
                  let value = hotKey["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int],
                  parameters.count == 3
            else { return nil }

            return DesktopShortcut(
                desktopNumber: desktopNumber,
                character: parameters[0],
                keyCode: Int64(parameters[1]),
                modifiers: CGEventFlags(rawValue: UInt64(parameters[2])).intersection(modifierMask)
            )
        }
    }
}
