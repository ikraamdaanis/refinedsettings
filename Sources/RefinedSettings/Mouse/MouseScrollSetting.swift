import Foundation

/// Whether the mouse scrolls the opposite way to the system setting, per axis, off by default.
enum MouseScrollSetting {
    static let verticalKey = "reversesMouseScrolling"
    static let horizontalKey = "reversesMouseHorizontalScrolling"

    static var reversesVertically: Bool {
        UserDefaults.standard.bool(forKey: verticalKey)
    }

    static var reversesHorizontally: Bool {
        UserDefaults.standard.bool(forKey: horizontalKey)
    }

    static var reversesAnyAxis: Bool {
        reversesVertically || reversesHorizontally
    }
}
