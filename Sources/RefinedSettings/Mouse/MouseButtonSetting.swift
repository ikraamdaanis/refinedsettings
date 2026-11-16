import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// What a mouse button does in place of its usual job.
enum MouseButtonAction: String, Codable, CaseIterable {
    case off
    case back
    case forward
    case missionControl
    case appWindows
    case showDesktop
    case keyboardShortcut
    case modifierKey

    var title: String {
        switch self {
        case .off: "Nothing"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appWindows: "App Windows"
        case .showDesktop: "Show Desktop"
        case .keyboardShortcut: "Keyboard Shortcut"
        case .modifierKey: "Modifier Key"
        }
    }
}

/// A shortcut recorded in Settings for a button to press.
struct RecordedShortcut: Codable, Hashable {
    let keyCode: CGKeyCode
    let modifierBits: UInt64
    /// What the key types with no modifiers, kept for showing the shortcut.
    let character: String?

    var modifiers: CGEventFlags {
        CGEventFlags(rawValue: modifierBits).intersection(KeyPress.modifierMask)
    }

    var displayName: String {
        KeyPress.displayName(keyCode: keyCode, character: character, modifiers: modifiers)
    }

    func post() {
        KeyPress.post(keyCode: keyCode, modifiers: modifiers)
    }
}

/// A modifier key a button holds down for as long as the button is held. The shortcut recorder can't catch these on
/// their own, and some apps, such as dictation apps, listen for one side's key alone.
enum ModifierKey: String, Codable, CaseIterable {
    case rightCommand
    case leftCommand
    case rightOption
    case leftOption
    case rightControl
    case leftControl
    case rightShift
    case leftShift

    var title: String {
        switch self {
        case .rightCommand: "Right Command ⌘"
        case .leftCommand: "Left Command ⌘"
        case .rightOption: "Right Option ⌥"
        case .leftOption: "Left Option ⌥"
        case .rightControl: "Right Control ⌃"
        case .leftControl: "Left Control ⌃"
        case .rightShift: "Right Shift ⇧"
        case .leftShift: "Left Shift ⇧"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .rightCommand: CGKeyCode(kVK_RightCommand)
        case .leftCommand: CGKeyCode(kVK_Command)
        case .rightOption: CGKeyCode(kVK_RightOption)
        case .leftOption: CGKeyCode(kVK_Option)
        case .rightControl: CGKeyCode(kVK_RightControl)
        case .leftControl: CGKeyCode(kVK_Control)
        case .rightShift: CGKeyCode(kVK_RightShift)
        case .leftShift: CGKeyCode(kVK_Shift)
        }
    }

    /// The modifier plus the bit that says which side's key is down, as a real keyboard sets them (`NX_DEVICE…KEYMASK`
    /// in IOLLEvent.h).
    var flags: CGEventFlags {
        switch self {
        case .rightCommand: [.maskCommand, CGEventFlags(rawValue: 0x10)]
        case .leftCommand: [.maskCommand, CGEventFlags(rawValue: 0x08)]
        case .rightOption: [.maskAlternate, CGEventFlags(rawValue: 0x40)]
        case .leftOption: [.maskAlternate, CGEventFlags(rawValue: 0x20)]
        case .rightControl: [.maskControl, CGEventFlags(rawValue: 0x2000)]
        case .leftControl: [.maskControl, CGEventFlags(rawValue: 0x01)]
        case .rightShift: [.maskShift, CGEventFlags(rawValue: 0x04)]
        case .leftShift: [.maskShift, CGEventFlags(rawValue: 0x02)]
        }
    }

    func post(isDown: Bool) {
        KeyPress.postModifier(keyCode: keyCode, flags: flags, isDown: isDown)
    }
}

struct MouseButtonMapping: Codable, Hashable {
    var action: MouseButtonAction
    var shortcut: RecordedShortcut?
    var modifierKey: ModifierKey?

    /// A shortcut action with nothing recorded yet leaves the button as it is.
    var takesOverButton: Bool {
        switch action {
        case .keyboardShortcut: shortcut != nil
        case .modifierKey: modifierKey != nil
        default: true
        }
    }
}

/// The action picked for each button, keyed by macOS's button number (0 is the left button). A button with no entry
/// does its usual job, which is everything by default.
enum MouseButtonSetting {
    static let mappingsKey = "mouseButtonMappings"
    /// Buttons past forward that the tester has seen, so they can be given an action too.
    static let extraButtonsKey = "seenMouseButtonNumbers"
    static let middleButton = 2
    static let backButton = 3
    static let forwardButton = 4

    /// Read on the tap thread for every button press. A press is rare enough for the decode not to matter.
    static func mappings() -> [Int: MouseButtonMapping] {
        decode(UserDefaults.standard.data(forKey: mappingsKey))
    }

    static func decode(_ data: Data?) -> [Int: MouseButtonMapping] {
        guard let data, let mappings = try? JSONDecoder().decode([Int: MouseButtonMapping].self, from: data) else { return [:] }

        return mappings
    }

    static func encode(_ mappings: [Int: MouseButtonMapping]) -> Data {
        (try? JSONEncoder().encode(mappings)) ?? Data()
    }

    static var remapsAnyButton: Bool {
        mappings().values.contains { mapping in mapping.takesOverButton }
    }

    static var extraButtons: [Int] {
        (UserDefaults.standard.array(forKey: extraButtonsKey) as? [Int] ?? []).sorted()
    }

    static func rememberExtraButton(_ button: Int) {
        let known = extraButtons

        // Only when it's new: every write tells the whole app its settings changed.
        guard button > forwardButton, !known.contains(button) else { return }

        UserDefaults.standard.set((known + [button]).sorted(), forKey: extraButtonsKey)
    }

    /// The names apps and macOS use, counting from 1, for buttons past the usual five.
    static func name(of button: Int) -> String {
        switch button {
        case 0: "Left"
        case 1: "Right"
        case middleButton: "Middle"
        case backButton: "Back"
        case forwardButton: "Forward"
        default: "Button \(button + 1)"
        }
    }
}
