import SwiftUI

/// The sidebar's panes, in sidebar order. Named and grouped after System Settings, so each option sits where Apple would
/// put it, with the input devices last. Finder, Links and Screenshots have no System Settings page of their own.
enum SettingsPane: Hashable, CaseIterable {
    case general
    case desktopAndDock
    case menuBar
    case finder
    case links
    case screenshots
    case keyboard
    case mouse

    var title: String {
        switch self {
        case .general: "General"
        case .desktopAndDock: "Desktop & Dock"
        case .menuBar: "Menu Bar"
        case .finder: "Finder"
        case .links: "Links"
        case .screenshots: "Screenshots"
        case .keyboard: "Keyboard"
        case .mouse: "Mouse"
        }
    }

    var summary: String {
        switch self {
        case .general: "Extra settings to go with the ones macOS already has. Nothing changes until you turn it on."
        case .desktopAndDock: "Fine-tune the Dock, move windows more easily, and use your Switch to Desktop shortcuts to go through the windows on the desktop you're already on."
        case .menuBar: "Tidy the menu bar and the menus that drop down from it."
        case .finder: "Show more in Finder windows and choose how folders and search results are laid out."
        case .links: "Choose which browser each link opens in. Click a link in any app and a small window asks where to open it."
        case .screenshots: "Choose the file format and name for your screenshots, and whether captured windows keep their shadow."
        case .keyboard: "Choose what happens when you hold down a key, how fast it repeats, and whether quotes and dashes change as you type."
        case .mouse: "Set your mouse's scroll direction without changing your trackpad, check that each button reaches your Mac, and choose what the buttons do."
        }
    }

    /// The version of `summary` for General's list, short enough to fit on one line beside a row's status.
    var rowSummary: String {
        switch self {
        case .general: summary
        case .desktopAndDock: "Fine-tune the Dock and move windows more easily."
        case .menuBar: "Tidy the menu bar and its menus."
        case .finder: "Show more in Finder and choose default views."
        case .links: "Choose which browser each link opens in."
        case .screenshots: "Choose the format, file name and window shadow."
        case .keyboard: "Set key repeat, smart quotes and smart dashes."
        case .mouse: "Set mouse scrolling and what its buttons do."
        }
    }

    /// Unused for `general`, which draws the app's own gear.
    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .desktopAndDock: "dock.rectangle"
        case .menuBar: "menubar.rectangle"
        case .finder: "folder.fill"
        case .links: "link"
        case .screenshots: "camera.viewfinder"
        case .keyboard: "keyboard.fill"
        case .mouse: "computermouse.fill"
        }
    }

    /// Matches the System Settings icons, sampled on macOS 26. Finder and Links use Network's blue. Screenshots has no
    /// icon there, so it takes the grey of Apple's utility panes.
    var iconGradient: LinearGradient {
        switch self {
        case .general, .menuBar, .screenshots, .keyboard, .mouse:
            Self.iconGradient(top: (175, 175, 181), bottom: (142, 142, 147))
        case .desktopAndDock:
            Self.iconGradient(top: (51, 51, 51), bottom: (0, 0, 0))
        case .finder, .links:
            Self.iconGradient(top: (71, 168, 255), bottom: (0, 136, 255))
        }
    }

    private static func iconGradient(
        top: (red: Double, green: Double, blue: Double),
        bottom: (red: Double, green: Double, blue: Double)
    ) -> LinearGradient {
        let topColor = Color(.sRGB, red: top.red / 255, green: top.green / 255, blue: top.blue / 255)
        let bottomColor = Color(.sRGB, red: bottom.red / 255, green: bottom.green / 255, blue: bottom.blue / 255)

        return LinearGradient(colors: [topColor, bottomColor], startPoint: .top, endPoint: .bottom)
    }

    /// What sidebar search matches, besides the title.
    private var searchTerms: [String] {
        switch self {
        case .general: ["launch", "login", "startup", "menu bar", "icon", "accessibility", "permission", "reopen", "restore", "log out"]
        case .desktopAndDock: ["spaces", "windows", "cycle", "switch", "shortcut", "mission control", "auto-hide", "autohide", "delay", "animation", "lock", "dim", "drag"]
        case .menuBar: ["icons", "menus", "spacing", "notch"]
        case .finder: ["hidden files", "path", "title bar", "view", "search", "ds_store", "network"]
        case .links: ["browser", "default", "picker", "profile", "safari", "chrome", "firefox", "url"]
        case .screenshots: ["capture", "format", "png", "jpg", "heic", "shadow", "file name"]
        case .keyboard: ["accent", "repeat", "hold", "press and hold", "typing", "smart quotes", "dashes", "text input", "delay", "rate", "speed"]
        case .mouse: ["scroll", "wheel", "pointer", "acceleration", "reverse", "smooth", "vertical", "horizontal", "buttons", "back", "forward", "middle", "remap", "test"]
        }
    }

    func matches(_ query: String) -> Bool {
        ([title] + searchTerms).contains { term in term.localizedCaseInsensitiveContains(query) }
    }
}
