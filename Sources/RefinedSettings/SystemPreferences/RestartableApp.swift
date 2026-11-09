/// A system app that only reads its preferences when it starts. The raw values are both its bundle identifier and the
/// domain its preferences live in.
enum RestartableApp: String {
    case dock = "com.apple.dock"
    case finder = "com.apple.finder"

    var name: String {
        switch self {
        case .dock: "Dock"
        case .finder: "Finder"
        }
    }
}
