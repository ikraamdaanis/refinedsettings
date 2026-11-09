import CoreFoundation

/// A preference that belongs to macOS or another app.
///
/// Uses CFPreferences because it looks in exactly one place, so a key nobody has set reads as nil, and storing nil
/// deletes the key, which is what puts a setting back to the macOS default.
struct SystemPreference: Hashable, Sendable {
    let domain: String
    let key: String
    var isForThisMacOnly = false

    private var host: CFString {
        isForThisMacOnly ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
    }

    var storedValue: CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesCurrentUser, host)
    }

    var appNeedingRestart: RestartableApp? {
        RestartableApp(rawValue: domain)
    }

    /// Picks up changes made by other apps, such as System Settings, since this process last looked.
    func synchronize() {
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, host)
    }

    func store(_ value: CFPropertyList?) -> Bool {
        CFPreferencesSetValue(key as CFString, value, domain as CFString, kCFPreferencesCurrentUser, host)

        return CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, host)
    }
}

extension SystemPreference {
    private static let dockDomain = RestartableApp.dock.rawValue
    private static let finderDomain = RestartableApp.finder.rawValue
    private static let screenshotDomain = "com.apple.screencapture"
    private static let globalDomain = kCFPreferencesAnyApplication as String

    static let screenshotFormat = SystemPreference(domain: screenshotDomain, key: "type")
    static let screenshotDisablesShadow = SystemPreference(domain: screenshotDomain, key: "disable-shadow")
    static let screenshotIncludesDate = SystemPreference(domain: screenshotDomain, key: "include-date")
    static let screenshotName = SystemPreference(domain: screenshotDomain, key: "name")
    static let dockAutohide = SystemPreference(domain: dockDomain, key: "autohide")
    static let dockAutohideDelay = SystemPreference(domain: dockDomain, key: "autohide-delay")
    static let dockAutohideAnimationTime = SystemPreference(domain: dockDomain, key: "autohide-time-modifier")
    static let dockDimsHiddenApps = SystemPreference(domain: dockDomain, key: "showhidden")
    static let dockLocksSize = SystemPreference(domain: dockDomain, key: "size-immutable")
    static let dockLocksItems = SystemPreference(domain: dockDomain, key: "contents-immutable")
    static let dockLocksPosition = SystemPreference(domain: dockDomain, key: "position-immutable")
    static let windowsDragOnGesture = SystemPreference(domain: globalDomain, key: "NSWindowShouldDragOnGesture")
    static let pressAndHoldShowsAccents = SystemPreference(domain: globalDomain, key: "ApplePressAndHoldEnabled")
    static let smartQuotes = SystemPreference(domain: globalDomain, key: "NSAutomaticQuoteSubstitutionEnabled")
    static let smartDashes = SystemPreference(domain: globalDomain, key: "NSAutomaticDashSubstitutionEnabled")
    static let finderShowsFullPath = SystemPreference(domain: finderDomain, key: "_FXShowPosixPathInTitle")
    static let finderShowsHiddenFiles = SystemPreference(domain: finderDomain, key: "AppleShowAllFiles")
    static let finderDefaultView = SystemPreference(domain: finderDomain, key: "FXPreferredViewStyle")
    static let finderSearchView = SystemPreference(domain: finderDomain, key: "FXPreferredSearchViewStyle")
    static let skipsDSStoreOnNetworkDrives = SystemPreference(domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores")
    static let menusShowIcons = SystemPreference(domain: globalDomain, key: "NSMenuEnableActionImages")
    static let menuBarItemSpacing = SystemPreference(domain: globalDomain, key: "NSStatusItemSpacing", isForThisMacOnly: true)
    static let menuBarItemPadding = SystemPreference(domain: globalDomain, key: "NSStatusItemSelectionPadding", isForThisMacOnly: true)
    static let reopensWindowsAtLogin = SystemPreference(domain: "com.apple.loginwindow", key: "TALLogoutSavesState")

    static let screenshotPreferences = [screenshotFormat, screenshotDisablesShadow, screenshotIncludesDate, screenshotName]
    /// `dockAutohide` is left out because the app only reads it.
    static let dockPreferences = [dockAutohideDelay, dockAutohideAnimationTime, dockDimsHiddenApps, dockLocksSize, dockLocksItems, dockLocksPosition]
    static let keyboardPreferences = [pressAndHoldShowsAccents, smartQuotes, smartDashes]
    static let finderPreferences = [finderShowsFullPath, finderShowsHiddenFiles, finderDefaultView, finderSearchView, skipsDSStoreOnNetworkDrives]
    /// The padding always changes along with the spacing, so the pair counts as one change.
    static let menuBarPreferences = [menusShowIcons, menuBarItemSpacing]
    static let everyPreference = screenshotPreferences + dockPreferences + keyboardPreferences + finderPreferences + menuBarPreferences + [dockAutohide, windowsDragOnGesture, reopensWindowsAtLogin]
}
