import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A key that acts as ⌃⌥⌘ (or ⌃⌥⇧⌘) while held, so shortcuts made with it don't clash with any app's own.
enum SuperKeyChoice: String, CaseIterable {
    case capsLock
    case rightCommand
    case rightOption
    case rightControl
    case rightShift

    var title: String {
        switch self {
        case .capsLock: "Caps Lock ⇪"
        case .rightCommand: "Right Command ⌘"
        case .rightOption: "Right Option ⌥"
        case .rightControl: "Right Control ⌃"
        case .rightShift: "Right Shift ⇧"
        }
    }

    /// The modifier key this is, or nil for Caps Lock, which reaches the tap as F18 instead (see `CapsLockRemap`).
    /// macOS can't stop Caps Lock switching itself on from an event tap.
    var modifierKey: ModifierKey? {
        switch self {
        case .capsLock: nil
        case .rightCommand: .rightCommand
        case .rightOption: .rightOption
        case .rightControl: .rightControl
        case .rightShift: .rightShift
        }
    }

    /// The key code the tap sees for it.
    var keyCode: CGKeyCode {
        modifierKey?.keyCode ?? CGKeyCode(kVK_F18)
    }
}

/// What the super key does when tapped on its own.
enum SuperKeyTapAction: String, CaseIterable {
    case nothing
    case escape
    case capsLock

    var title: String {
        switch self {
        case .nothing: "Nothing"
        case .escape: "Escape"
        case .capsLock: "Caps Lock"
        }
    }
}

/// The super key picked in Settings, off by default. Read on the tap thread for every key press, which UserDefaults
/// answers from memory.
enum SuperKeySetting {
    static let keyKey = "superKey"
    static let tapActionKey = "superKeyTapAction"
    static let includesShiftKey = "superKeyIncludesShift"

    static var key: SuperKeyChoice? {
        UserDefaults.standard.string(forKey: keyKey).flatMap(SuperKeyChoice.init(rawValue:))
    }

    static var tapAction: SuperKeyTapAction {
        UserDefaults.standard.string(forKey: tapActionKey).flatMap(SuperKeyTapAction.init(rawValue:)) ?? .nothing
    }

    /// Off by default, as in Raycast, which leaves ⇧ for you to add for a second set of shortcuts. macOS keeps a few
    /// ⌃⌥⇧⌘ shortcuts for itself, such as ⌃⌥⇧⌘. for a diagnostics report.
    static var includesShift: Bool {
        UserDefaults.standard.bool(forKey: includesShiftKey)
    }

    static var isOn: Bool {
        key != nil
    }

    static var flags: CGEventFlags {
        includesShift ? [.maskControl, .maskAlternate, .maskShift, .maskCommand] : [.maskControl, .maskAlternate, .maskCommand]
    }
}
