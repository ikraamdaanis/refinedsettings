import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A "Switch to Desktop N" shortcut from System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
struct DesktopShortcut: Equatable {
    /// AppleSymbolicHotKeys IDs 118 to 126 are "Switch to Desktop 1" to "Switch to Desktop 9".
    private static let firstHotKeyID = 118
    /// Stored in place of a character for keys that don't type one, such as the arrow keys.
    private static let noCharacter = 65535

    let desktopNumber: Int
    let character: Int
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags

    /// Written like a menu shortcut, for example ⇧⌘1.
    var displayName: String {
        let typedKey = character == Self.noCharacter ? nil : UnicodeScalar(character).map { scalar in String(scalar) }

        return KeyPress.displayName(keyCode: keyCode, character: typedKey, modifiers: modifiers)
    }

    /// The modifiers in the form hot keys take. Hot keys can't include fn, which macOS adds by itself to the arrow and
    /// function keys anyway.
    var carbonModifiers: UInt32 {
        let carbonEquivalents: [(flag: CGEventFlags, modifier: Int)] = [
            (.maskCommand, cmdKey),
            (.maskShift, shiftKey),
            (.maskAlternate, optionKey),
            (.maskControl, controlKey),
        ]

        return carbonEquivalents
            .filter { equivalent in modifiers.contains(equivalent.flag) }
            .reduce(0) { combined, equivalent in combined | UInt32(equivalent.modifier) }
    }

    /// Presses the shortcut as if from the keyboard.
    func post() {
        KeyPress.post(keyCode: keyCode, modifiers: modifiers)
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
                  parameters.count == 3,
                  // A shortcut with no key stores 65535 here. Anything else out of range is a damaged file, and
                  // converting it unchecked would crash.
                  let keyCode = CGKeyCode(exactly: parameters[1]),
                  keyCode != CGKeyCode.max,
                  let modifierBits = UInt64(exactly: parameters[2])
            else { return nil }

            return DesktopShortcut(
                desktopNumber: desktopNumber,
                character: parameters[0],
                keyCode: keyCode,
                modifiers: CGEventFlags(rawValue: modifierBits).intersection(KeyPress.modifierMask)
            )
        }
    }
}
