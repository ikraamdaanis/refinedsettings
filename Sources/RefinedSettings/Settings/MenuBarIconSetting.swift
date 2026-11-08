import Foundation

/// Whether the menu bar icon shows, on by default.
enum MenuBarIconSetting {
    static let key = "showsMenuBarIcon"

    static var isShown: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
