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

    var title: String {
        switch self {
        case .off: "Nothing"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appWindows: "App Windows"
        case .showDesktop: "Show Desktop"
        case .keyboardShortcut: "Keyboard Shortcut"
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

struct MouseButtonMapping: Codable, Hashable {
    var action: MouseButtonAction
    var shortcut: RecordedShortcut?

    /// A shortcut action with nothing recorded yet leaves the button as it is.
    var takesOverButton: Bool {
        action != .keyboardShortcut || shortcut != nil
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
