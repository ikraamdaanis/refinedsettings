import Foundation

/// Whether the shortcut for the desktop you're already on cycles through its windows, off by default.
enum DesktopCyclingSetting {
    static let key = "cyclesDesktopWindows"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
