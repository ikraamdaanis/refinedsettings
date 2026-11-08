import SwiftUI

/// The sidebar's panes, in the groups System Settings would separate with a gap.
enum SettingsPane: Hashable {
    case general
    case links
    case mouseAndScrolling
    case hiddenSettings

    static let sidebarGroups: [[SettingsPane]] = [
        [.general],
        [.links, .mouseAndScrolling, .hiddenSettings],
    ]

    var title: String {
        switch self {
        case .general: "General"
        case .links: "Links"
        case .mouseAndScrolling: "Mouse & Scrolling"
        case .hiddenSettings: "Hidden Settings"
        }
    }

    var summary: String {
        switch self {
        case .general: "Choose how Refined Settings starts, where it appears and what it's allowed to do."
        case .links: "Choose a browser for every link you open, from a picker that lists each browser and profile."
        case .mouseAndScrolling: "Scrolling and pointer settings for your mouse, kept separate from your trackpad."
        case .hiddenSettings: "Dock, Finder and screenshot options that macOS doesn't show in System Settings."
        }
    }

    /// Unused for `general`, which draws the app's own gear.
    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .links: "link"
        case .mouseAndScrolling: "computermouse.fill"
        case .hiddenSettings: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(white: 0.56)
        case .links: .blue
        case .mouseAndScrolling: .indigo
        case .hiddenSettings: .orange
        }
    }

    /// What sidebar search matches, besides the title.
    private var searchTerms: [String] {
        switch self {
        case .general: ["launch", "login", "startup", "menu bar", "icon", "accessibility", "permission"]
        case .links: ["browser", "default", "picker", "profile", "safari", "chrome", "firefox", "url"]
        case .mouseAndScrolling: ["scroll", "wheel", "pointer", "acceleration", "reverse", "smooth"]
        case .hiddenSettings: ["dock", "finder", "screenshot", "defaults", "tweak", "animation"]
        }
    }

    func matches(_ query: String) -> Bool {
        ([title] + searchTerms).contains { term in term.localizedCaseInsensitiveContains(query) }
    }
}
