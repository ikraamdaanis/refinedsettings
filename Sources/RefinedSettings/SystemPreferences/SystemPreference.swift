import CoreFoundation

/// A preference that belongs to macOS or another app.
///
/// Uses CFPreferences because it looks in exactly one place, so a key nobody has set reads as nil, and storing nil
/// deletes the key, which is what puts a setting back to the macOS default.
struct SystemPreference: Hashable, Sendable {
    let domain: String
    let key: String

    var storedValue: CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    var isDockPreference: Bool {
        domain == Self.dockDomain
    }

    /// Picks up changes made by other apps, such as System Settings, since this process last looked.
    func synchronize() {
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func store(_ value: CFPropertyList?) -> Bool {
        CFPreferencesSetValue(key as CFString, value, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        return CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

extension SystemPreference {
    private static let dockDomain = "com.apple.dock"
    private static let screenshotDomain = "com.apple.screencapture"
    private static let globalDomain = kCFPreferencesAnyApplication as String

    static let screenshotFormat = SystemPreference(domain: screenshotDomain, key: "type")
    static let screenshotDisablesShadow = SystemPreference(domain: screenshotDomain, key: "disable-shadow")
    static let screenshotIncludesDate = SystemPreference(domain: screenshotDomain, key: "include-date")
    static let screenshotName = SystemPreference(domain: screenshotDomain, key: "name")
    static let dockAutohide = SystemPreference(domain: dockDomain, key: "autohide")
    static let dockAutohideDelay = SystemPreference(domain: dockDomain, key: "autohide-delay")
    static let dockAutohideAnimationTime = SystemPreference(domain: dockDomain, key: "autohide-time-modifier")
    static let pressAndHoldShowsAccents = SystemPreference(domain: globalDomain, key: "ApplePressAndHoldEnabled")

    static let screenshotPreferences = [screenshotFormat, screenshotDisablesShadow, screenshotIncludesDate, screenshotName]
    /// `dockAutohide` is left out because the app only reads it.
    static let dockPreferences = [dockAutohideDelay, dockAutohideAnimationTime]
    static let keyboardPreferences = [pressAndHoldShowsAccents]
}
