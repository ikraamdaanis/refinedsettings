import SwiftUI

/// The sidebar's panes, in sidebar order.
enum SettingsPane: Hashable, CaseIterable {
    case general
    case links
    case mouseAndScrolling
    case desktops
    case hiddenSettings

    var title: String {
        switch self {
        case .general: "General"
        case .links: "Links"
        case .mouseAndScrolling: "Mouse & Scrolling"
        case .desktops: "Desktops"
        case .hiddenSettings: "Hidden Settings"
        }
    }

    var summary: String {
        switch self {
        case .general: "Small improvements to your Mac that macOS doesn't offer. Nothing changes until you turn it on."
        case .links: "Choose which browser each link opens in. Click a link in any app and a small window asks where to open it."
        case .mouseAndScrolling: "Set your mouse's scroll direction without changing your trackpad. macOS has one setting for both."
        case .desktops: "Use your Switch to Desktop shortcuts to move between the windows on the desktop you're already on."
        case .hiddenSettings: "Options macOS has for the Dock, Finder and screenshots but doesn't show in System Settings."
        }
    }

    /// Unused for `general`, which draws the app's own gear.
    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .links: "link"
        case .mouseAndScrolling: "computermouse.fill"
        case .desktops: "macwindow.on.rectangle"
        case .hiddenSettings: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(white: 0.56)
        case .links: .blue
        case .mouseAndScrolling: .indigo
        case .desktops: .teal
        case .hiddenSettings: .orange
        }
    }

    /// What sidebar search matches, besides the title.
    private var searchTerms: [String] {
        switch self {
        case .general: ["launch", "login", "startup", "menu bar", "icon", "accessibility", "permission"]
        case .links: ["browser", "default", "picker", "profile", "safari", "chrome", "firefox", "url"]
        case .mouseAndScrolling: ["scroll", "wheel", "pointer", "acceleration", "reverse", "smooth", "vertical", "horizontal"]
        case .desktops: ["spaces", "windows", "cycle", "switch", "shortcut", "mission control"]
        case .hiddenSettings: ["dock", "finder", "screenshot", "defaults", "tweak", "animation"]
        }
    }

    func matches(_ query: String) -> Bool {
        ([title] + searchTerms).contains { term in term.localizedCaseInsensitiveContains(query) }
    }
}
