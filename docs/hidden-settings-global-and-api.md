# Hidden Settings: global `defaults` keys and how to read/write them

Research for Refined Settings' "Hidden Settings" module. Machine used for local checks: macOS 26.5.2 (25F84), Apple Silicon, Command Line Tools SDK 26.5. Nothing was written: all local evidence comes from `defaults read`, `defaults read-type`, `ioreg`, `hidutil property --get`, `launchctl print`, read-only Swift probes, and `grep -a` over the macOS 26 dyld shared cache and system binaries (to check that each key string still exists in the OS).

Legend: **[local]** = checked on this Mac. **[cache]** = key string found (or not found) in the macOS 26.5 dyld shared cache or the named binary. **unverified** = not confirmed by a source or test.

How to read "string present in the shared cache": it proves some OS code still names the key on macOS 26, not that the tweak has a visible effect. "String absent" is strong evidence the key is dead on 26 (unless the code builds the name at runtime).

---

## 1. Key reference

### 1.1 Keyboard

| Key | Domain | Type | Unset means | Values / UI | In System Settings? | Apply after | macOS 13 / 14 / 15 / 26 |
|---|---|---|---|---|---|---|---|
| `KeyRepeat` | `-g` (AnyHost) | int | HID default repeat interval of 83.33 ms **[local]** | Lower is faster. Community-cited GUI minimum is 2; CLI accepts 1 (and 0) [gist-zlass, devto] | Yes: Keyboard > Key repeat rate | `defaults write`: log out [gist-nikolasgd, devto]. System Settings applies instantly via HID (see caveat) | Works on all (string present **[cache]**; widely used) |
| `InitialKeyRepeat` | `-g` (AnyHost) | int | HID default delay of 500 ms **[local]** | Lower is shorter. Community-cited GUI minimum is 15; CLI accepts 10 and lower [gist-zlass, til-vegard] | Yes: Keyboard > Delay until repeat | Log out | Works on all |
| `ApplePressAndHoldEnabled` | `-g`, or per app (`com.microsoft.VSCode`, etc.) | bool | `true`: holding a key shows the accent popup [mdc-pressandhold] | toggle | No | Reopen affected apps (macos-defaults says "restarting the application is necessary") [mdc-pressandhold] | Tested on 11 to 13 by macos-defaults; string present on 26 **[cache]** |

**Units of `KeyRepeat` / `InitialKeyRepeat` are disputed.** Community snippets say 15 ms per unit (2 = 30 ms, 15 = 225 ms) [gist-zlass, devto, til-vegard], all tracing back to one Stack Exchange answer. A 2005 Apple cocoa-dev post says the value is in "ticks" (about 1/60 s, 16.67 ms), which is the classic Mac OS `KeyThresh`/`KeyRepThresh` unit [cocoadev-2005, via search summary; page itself returned 502]. Supporting the ticks reading: the HID defaults in effect on this Mac with both keys unset are 500,000,000 ns and 83,333,333 ns **[local, `ioreg` and `hidutil property --get`]**, which are exactly 30 and 5 ticks but not whole multiples of 15 ms. **Unverified** which is right; I could not test without writing. Recommendation: do not show milliseconds in the UI; show the same slider stops as System Settings plus "faster than System Settings allows" stops, and label speed qualitatively.

**System Settings slider stops** (often quoted as KeyRepeat 120, 90, 60, 30, 12, 6, 2 and InitialKeyRepeat 120, 94, 68, 35, 25, 15): **unverified**. No source I could fetch lists them. Quick way to confirm on the dev Mac: step the slider in System Settings and run `defaults read -g KeyRepeat` after each step. The leftmost "Off" position of Key repeat rate: what it writes is **unverified**.

**Values below the GUI minimum:** `KeyRepeat 1` and `InitialKeyRepeat 10` are widely used and reported to work after logout [gist-zlass, devto]. `KeyRepeat 0` is reported as accepted; whether it means "as fast as possible" or causes runaway repeat is **unverified**; cap the UI at 1. Hexnode's MDM script documents KeyRepeat as 1 to 15, which shows these keys are also managed by MDM in the field [hexnode].

**Why `defaults write` needs a logout but System Settings does not:** the effective repeat values live in the HID event system, not in the preference. System Settings' Keyboard extension (`/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex`) references `IOHIDSetParameter`, `IOHIDServiceClientSetProperty`, `KeyRepeatInterval`, `KeyRepeatThreshold` and `InitialKeyRepeat` **[local, strings in binary]**, i.e. it writes the pref and pushes the value into HID. At login the pref is loaded into HID again. A `defaults write` alone changes only the pref. Options for Refined Settings to apply instantly (all **unverified**, would need testing): `IOHIDSetParameter` with `kIOHIDKeyRepeatKey` / `kIOHIDInitialKeyRepeatKey` (public but deprecated since 10.12, values in ns per `IOHIDProperties.h`) **[local, SDK headers]**, or `hidutil property --set '{"HIDKeyRepeat":…}'` (hidutil can read these properties **[local]**). `NSEvent.keyRepeatDelay` / `keyRepeatInterval` reflect the live HID values (0.5 and 0.0833 here) **[local]**, so they are a good "what is in effect right now" readout and let the UI detect "pref changed but not applied yet".

**`ApplePressAndHoldEnabled` scope:** the setting is read through each app's normal defaults search list, so a per-app value (e.g. `defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false`, the VSCodeVim recommendation) overrides the global one [gist-zlass]. On this Mac the global value is `false` and no app domain in `~/Library/Preferences` sets it **[local]**. It is not exposed in System Settings on 13 to 26 (the Keyboard and Text Input pages list no such option) [apple-input-sources].

### 1.2 Typing (text substitution)

| Key | Domain | Type | Unset means | In System Settings (Keyboard > Text Input > Edit) | Apply after | Versions |
|---|---|---|---|---|---|---|
| `NSAutomaticSpellingCorrectionEnabled` | `-g` or per app | bool | on (`NSSpellChecker.isAutomaticSpellingCorrectionEnabled` = true while unset **[local]**) | Yes, "Correct spelling automatically", 1:1 [apple-input-sources] | System Settings: live. `defaults write`: reopen apps (see below) | 13 to 26 |
| `NSAutomaticCapitalizationEnabled` | `-g` or per app | bool | on | Yes, "Capitalize words automatically", 1:1 | same | 13 to 26 |
| `NSAutomaticPeriodSubstitutionEnabled` | `-g` or per app | bool | on (Apple default; reported `false` here because it is set) | Yes, "Add period with double-space", 1:1 [apple-replace-text] | same | 13 to 26 |
| `NSAutomaticQuoteSubstitutionEnabled` | `-g` or per app | bool | on (true while unset **[local]**) | Partly: one toggle "Use smart quotes and dashes" drives both quote and dash keys [apple-replace-text, mpu-dashes] | same | 13 to 26 |
| `NSAutomaticDashSubstitutionEnabled` | `-g` or per app | bool | on (true while unset **[local]**) | Partly (shared toggle above). Splitting quotes from dashes is a real value-add | same | 13 to 26 |
| `NSAutomaticTextCompletionEnabled` | `-g` | bool | on (true while unset **[local]**) | Not on the Text Input page. API is macOS 10.12.2+ [apple-nsspellchecker]. Which UI (if any) drives it, possibly Touch Bar typing suggestions: **unverified** | same | 13 to 26 (string present **[cache]**) |
| `NSAutomaticInlinePredictionEnabled` (extra) | `-g` | bool | on (true while unset **[local]**) | Yes, "Show inline predictive text" (macOS 14+) [apple-input-sources] | same | 14+ only (API introduced 14.0 [apple-nsspellchecker]) |
| `WebAutomaticSpellingCorrectionEnabled` | per app (Safari, Mail) or `-g` | bool | WebKit falls back to `NSSpellChecker.isAutomaticTextReplacementEnabled` (not spelling correction) [webkit-textchecker] | No | Reopen the WebKit app | 13 to 26 |

**Live vs relaunch.** AppKit posts per-process notifications such as `NSSpellChecker.didChangeAutomaticQuoteSubstitutionNotification` when the class property changes, and the shared cache also contains `AppleTextBehaviorPreferencesChangedNotification`, `NSAutomaticSpellingCorrectionEnabledChanged` and `NSAutomaticTextCompletionEnabledChanged` **[cache]**. WebKit forwards `AppleTextBehaviorPreferencesChangedNotification` into its sandboxed processes [gh-webkit-forwarded], which suggests it is the cross-process "text prefs changed" broadcast. My reading: System Settings changes reach running apps live through these broadcasts, while a raw `defaults write` (or our CFPreferences write) does not trigger them, so already-running apps keep the old behaviour until relaunched. Whether posting `AppleTextBehaviorPreferencesChangedNotification` ourselves makes apps reload: **unverified**. Design for "reopen apps".

**Per-app overrides win.** Apps can store their own copy (TextEdit, Slack via `com.tinyspeck.slackmacgap`, any app where the user toggled Edit > Substitutions) [mpu-dashes]. A global change will not affect those apps. On this Mac no app domain in `~/Library/Preferences` sets these keys **[local]**.

**WebKit quirk.** `shouldAutomaticSpellingCorrectionBeEnabled()` reads `WebAutomaticSpellingCorrectionEnabled` from the app's standard defaults and, if unset, returns `NSSpellChecker.isAutomaticTextReplacementEnabled` [webkit-textchecker]. So turning off "Correct spelling automatically" may not stop autocorrect in Safari/Mail web views; writing `WebAutomaticSpellingCorrectionEnabled = false` does. Mathias writes it to `com.apple.Safari` [mathias]; since Safari is sandboxed its prefs live in its container, so writing it to `-g` (which sandboxed apps also read) is the more reliable place (**unverified** for Safari 26).

### 1.3 Windows and animation

| Key | Domain | Type | Unset means | Values / UI | In System Settings? | Apply after | Versions / status |
|---|---|---|---|---|---|---|---|
| `NSWindowResizeTime` | `-g` | float (s) | 0.20 s per 150 px of resize, "may be different in different releases" [apple-animationresizetime] | e.g. 0.001 [mathias]; 0 reportedly ignored, use 0.001 [gist-jj1bdx] | No | Reopen apps (**unverified**) | Still read by AppKit (`NSWindow.animationResizeTime(_:)` documents it; string present **[cache]**). Only affects `setFrame(_:display:animate: true)` style animated resizes; modern sheets and most system animations use Core Animation, so the visible effect is small. Rate it "low impact" |
| `NSAutomaticWindowAnimationsEnabled` | `-g` | bool | on | toggle (off disables the zoom-in when new windows/popovers open) [gist-jj1bdx] | No (Reduce Motion is the official near-equivalent) | Reopen apps | String present on 26 **[cache]**; no 2023+ test report found (**unverified** effect on 26) |
| `NSWindowShouldDragOnGesture` | `-g` | bool | off | on: ⌃⌘-drag anywhere in a window moves it | No | Log out (or reopen apps) [ifun, obsidian] | Works on 15.3 (Obsidian report, Darwin 24.3, March 2025) [obsidian]. String plus `sNSWindowShouldDragOnGestureComputedValue` present on 26.5 **[cache]**. Tahoe behaviour not tested (**unverified**) |
| `NSScrollAnimationEnabled` | `-g` | bool | on (AppKit registers `NSScrollAnimationEnabled = 1` in the registration domain **[local]**) | toggle; off disables smooth scrolling for keyboard/page scrolling [mathias] | No | Reopen apps | Present on 26 **[cache]** |
| `QLPanelAnimationDuration` | `-g` | float (s) | system default | 0 disables the Quick Look zoom [gist-jj1bdx] | No | Relaunch Finder / reopen apps (**unverified**) | String present on 26 **[cache]**; effect **unverified** |
| `com.apple.dock expose-animation-duration` | `com.apple.dock` | float | n/a | | No | n/a | **Broken.** Reported not working since Sierra (2016) and on Mojave [mathias-711]. The string is absent from the macOS 26.5 Dock binary and the whole shared cache **[cache]**. Do not ship |

**Extra key found while checking:** `NSWindowShouldDragOnGestureFeedback` (with its own `ComputedValue`) sits next to `NSWindowShouldDragOnGesture` in the macOS 26.5 cache **[cache]**. Meaning **unverified**; do not ship until tested.

**"ComputedValue" pattern:** `NSWindowShouldDragOnGesture`, `NSScrollAnimationEnabled` and `NSDocumentSaveNewDocumentsToCloud` each have a `…ComputedValue` static next to them **[cache]**. That naming points to a value computed once per process and cached, which matches the community advice to relaunch apps or log out. Treat all of them as "reopen apps", and suggest logout as the one-step way to reopen everything.

**Known side effect:** with `NSWindowShouldDragOnGesture` on, ⌃⌘-click in Obsidian (Electron) also opens the context menu [obsidian]. Expect similar oddities in apps that treat ⌃-click as right-click.

### 1.4 Dialogs

| Key | Domain | Type | Unset means | In System Settings? | Apply after | Status on 13 to 26 |
|---|---|---|---|---|---|---|
| `NSNavPanelExpandedStateForSaveMode` | `-g`, plus per-app copies | bool | collapsed save panel | No | Reopen apps | **Works as a fallback only.** AppKit writes the user's last expand/collapse choice into each app's own domain, which then shadows `-g`. On this Mac four apps (Claude, 1Password, Xcode, Chrome) already have their own `NSNavPanelExpandedStateForSaveMode = 1` **[local]**. Reports since Big Sur say the global value is unreliable for this reason [mpu-bigsur, macformat-2022]. String present on 26 **[cache]** |
| `NSNavPanelExpandedStateForSaveMode2` | `-g` | bool | | No | | **Likely dead on 26.** The literal is absent from the macOS 26.5 shared cache, while the neighbouring `NSNavPanelFileListModeForSaveMode2` is present **[cache]**. Writing it is harmless but pointless |
| `PMPrintingExpandedStateForPrint` | `-g` | bool | | No | | **Likely dead on 13+.** Ventura redesigned the print dialog into a single mode that shows all options [macmost-ventura]; a Catalina report already says it stopped working [macrumors-catalina]. The literal is absent from the 26.5 shared cache and from `PrintingUI.bundle` / `PrintingCocoaPDEs.bundle` **[cache]** |
| `PMPrintingExpandedStateForPrint2` | `-g` | bool | | No | | Same as above: absent **[cache]**. Do not ship |
| `NSDocumentSaveNewDocumentsToCloud` | `-g` | bool | `true`: new documents default to iCloud Drive [mdc-savetocloud] | No | Reopen apps (AppKit caches it, see ComputedValue) | Present on 26 **[cache]**; macos-defaults only lists Catalina as tested [mdc-savetocloud]. Only affects `NSDocument`-based apps when iCloud Drive is on |

### 1.5 ByHost (`-currentHost`)

None of the keys above are ByHost: every one read `nil` from `kCFPreferencesCurrentHost` on this Mac **[local]**. The ByHost global domain here holds trackpad gesture keys (`com.apple.trackpad.*`) and Apple Intelligence availability keys **[local]**. Known ByHost global tweaks to keep in mind for other modules: `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` (menu bar spacing) [ss64]. The `Tweak` model therefore needs a `host` field, even though this module's keys all use AnyHost.

---

## 3. Reading and writing from Swift

### 3.1 Which API

**Use the primitive CFPreferences functions for anything outside your own app.**

- Read exactly what is stored: `CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)`. Only that exact location is searched [cf-header].
- Write: `CFPreferencesSetValue(key, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)`, then `CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)`. Passing `nil` as the value removes the key [cf-header]. This is the same user/any-host location that `defaults write -g` uses.
- Other app domains: same calls with the bundle ID (`"com.apple.dock"`) as `applicationID`.

**Do not use the `App` functions with `kCFPreferencesAnyApplication`.** The header says the App functions "should never be called with kCFPreferencesAnyApplication" [cf-header]. Probe result: in an AppKit process, `CFPreferencesCopyAppValue("NSScrollAnimationEnabled", kCFPreferencesAnyApplication)` returned `1` even though the key is not set anywhere. It leaked AppKit's registration-domain default **[local]**. That breaks "is this tweak set?" detection.

**`UserDefaults(suiteName: NSGlobalDomain)` does not work.** The header says passing `NSGlobalDomain` "is an error" [nsuserdefaults-header]. At runtime it logs "Using NSGlobalDomain as an NSUserDefaults suite name does not make sense and will not work", and in the probe it returned `nil` for a key that exists globally **[local]**. `UserDefaults.standard` can *read* global keys (the global domain is in every search list), but the values mix in your app's own domain, the argument domain and AppKit's registered defaults. Never use `setPersistentDomain(_:forName: NSGlobalDomain)`: it replaces the whole global domain [nsuserdefaults-header]. `UserDefaults(suiteName: "com.apple.dock")` is fine for other apps' domains when not sandboxed [apple-suitename].

**Shelling out to `/usr/bin/defaults`** goes through the same cfprefsd path and works. Downsides: a process spawn per call, parsing text output, and mapping types to `-bool`/`-int`/`-float` flags. It is a fine debugging cross-check, not the main path.

**Never edit plist files directly.** Since cfprefsd (10.8/10.9) the daemon owns and caches the data. Apple: modifying the files "may cause data loss, a delay in changes being available, or an app crash"; use `defaults` or the API [apple-userdefaults]. Prefs Editor gives the same reason for using CFPreferences [prefseditor].

**Write the right type.** Match what `defaults read-type` reports and what Apple writes: `kCFBooleanTrue` / `kCFBooleanFalse` for bools (Swift `true as CFBoolean`, or `NSNumber(value: true)` which bridges to a CFBoolean), `Int` for ints, `Double` for floats. AppKit's `bool(forKey:)` tolerates ints, but strict readers may not (**unverified** per key), so do not write `1` for a bool.

### 3.2 Caching, sync, and live updates

- Writes are visible to other processes as soon as cfprefsd has them. `CFPreferencesSynchronize` flushes your pending writes. Reading after someone else's write: Prefs Editor only shows external changes "after a modification, by re-activating the app or by using the Sync command" [prefseditor], so call `CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)` before re-reading on focus. It is cheap, and whether it is still needed on 26 is **unverified**.
- **Other running apps do not reload most of these keys.** AppKit computes many of them once per process (see "ComputedValue" above). There is no general "reload your defaults" broadcast.
- **Distributed notifications are announcements, not commands.** `AppleInterfaceThemeChangedNotification`, `AppleColorPreferencesChangedNotification`, `AppleShowScrollBarsSettingChanged` and `AppleTextBehaviorPreferencesChangedNotification` all exist on 26 **[cache]**, and each is posted by the component that changed the setting. Posting one yourself after a raw write is sometimes enough for listeners that re-read (theme is the known case), but this is undocumented and **unverified** for every key in this module.
- **`com.apple.dock.prefchanged` does not make the Dock reload.** It is a distributed notification the Dock (and its settings pane) posts after a change. yabai and others observe it [gh-yabai]. People who tried posting it to make the Dock reload a `defaults write` report it does nothing; the Dock pane applies changes through private CoreDock calls in HIServices [cocoadev-dock]. The string is still in the 26.5 Dock binary **[cache]**. Use it only to *detect* Dock pref changes.
- There is no `com.apple.KeyRepeat`-style notification. Key repeat goes through HID (section 1.1).

### 3.3 Detecting external changes while our UI is open

1. **Re-read on show and on activation.** On popover/window open and `NSApplication.didBecomeActiveNotification`, synchronize and re-read every visible tweak with `CFPreferencesCopyValue`. Thirty keys cost next to nothing. This alone covers the common case, and it is what Prefs Editor does [prefseditor].
2. **KVO as a trigger while open.** Apple: KVO on a `UserDefaults` object "reports all updates to setting values, regardless of which process made the change" [apple-didchange]. Observe `UserDefaults.standard` for global keys (the global domain is in its search list) and `UserDefaults(suiteName: "com.apple.dock")` for Dock keys. Use the callback only as a "something changed" signal and re-read with CFPreferences, because `standard` returns the merged value (for example `NSScrollAnimationEnabled` reads 1 when unset). Cross-process KVO for *global-domain* keys is **unverified** here (testing needs a write). `UserDefaults.didChangeNotification` only fires for changes made in your own process [apple-didchange], so do not rely on it.
3. **Distributed notifications** only for the few keys that have one (theme, Dock prefs). Not a general solution.

### 3.4 Sandbox and App Store

- Sandboxed apps need `com.apple.security.temporary-exception.shared-preference.read-write` listing each domain [apple-temp-exceptions]. Apple says to justify each temporary exception in App Store Connect, and in practice such requests are frequently refused ("not appropriate and will not be granted") [gh-container-348]. Whether the entitlement even grants writes to `kCFPreferencesAnyApplication` is **unverified**.
- Even with the entitlement the core feature fails App Review: guideline 2.4.5(i) requires sandboxing and limits changes to other apps' data to "appropriate macOS APIs", 2.5.1 requires public APIs used for their intended purpose (these keys are private, undocumented defaults), and relaunching Dock/Finder or logging the user out needs Apple Events or signals outside the sandbox [app-review]. Conclusion: Developer ID plus notarization, not sandboxed, as planned.
- Hardened runtime is fine for CFPreferences. Sending Apple Events (quit Finder, ask loginwindow to log out) needs `com.apple.security.automation.apple-events` and an `NSAppleEventsUsageDescription`, and triggers a TCC prompt for the target app (**unverified** for loginwindow).

### 3.5 Managed preferences (MDM)

- `CFPreferencesAppValueIsForced(key, appID)` returns true when the value "has been imposed on the user", and Apple says to disable the matching UI [cf-header, apple-isforced]. `UserDefaults.objectIsForced(forKey:)` and `objectIsForced(forKey:inDomain:)` are the Foundation equivalents [nsuserdefaults-header]. Do not pass `kCFPreferencesAnyApplication` (an App function).
- For global keys, call it with `kCFPreferencesCurrentApplication`: managed global prefs are part of our app's search list ("Managed (forced) preferences" come first [nsuserdefaults-header]). For app domains, pass the bundle ID. Not testable here (no profiles installed, empty `/Library/Managed Preferences`), so **unverified** in practice. As a fallback, read `/Library/Managed Preferences/<user>/.GlobalPreferences.plist` and `/Library/Managed Preferences/.GlobalPreferences.plist` (read only).
- UI: show a lock and "Managed by your organization", disable the control and the reset button. When the value is forced, the effective value is the forced one, not what we wrote.

### 3.6 Showing the effective default for an unset key

There is no API that says "what would the OS use if this key were absent". What works:

- **Curated default per tweak** in the data table, versioned by macOS major (Apple says the `NSWindowResizeTime` default "may be different in different releases" [apple-animationresizetime]). This is what every defaults GUI ends up doing.
- **Public effective-value APIs where they exist** (evaluated in our own process, which never sets these keys): `NSSpellChecker.isAutomaticSpellingCorrectionEnabled`, `…QuoteSubstitution…`, `…DashSubstitution…`, `…Capitalization…`, `…PeriodSubstitution…`, `…TextCompletion…`, `…TextReplacement…`, `…InlinePrediction…` (14+). `NSEvent.keyRepeatDelay` / `keyRepeatInterval` give live HID values. `NSWindow.animationResizeTime(_:)` reflects `NSWindowResizeTime`. All confirmed callable on 26 **[local]**.
- **AppKit's registration domain**, `UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)`, reveals AppKit's own registered defaults (18 entries here, for example `NSScrollAnimationEnabled = 1`) **[local]**.
- UI convention: show "Default (On)" with the default in secondary text, and treat "unset" as a distinct state from "explicitly set to the default value". Reset removes the key.

### 3.7 How existing tools do it

- **Prefs Editor** (Thomas Tempelmann): uses CFPreferences, not plist edits; picks up external changes on re-activation or a manual Sync command [prefseditor].
- **defaults edit** (ThatsJustCheesy, Swift, MIT, last push 2024): GUI editor that shows "all the defaults currently effective in a domain, regardless of where they are set" [defaults-edit]. Internals not checked (**unverified**).
- **swift-prefs** (scriptingosx `prefs`): a CLI that prints composited keys with the domain/level each comes from; known issue: it does not read sandboxed apps' container preferences [swift-prefs]. A good model for a "where is this value coming from" inspector.
- **yabai / Aerial / Docky**: observe `com.apple.dock.prefchanged` to react to Dock changes [gh-yabai].

---

## 4. Recommended design

### 4.1 Model

```swift
import CoreFoundation
import Foundation

enum PreferenceDomain: Hashable, Sendable {
    case global
    case app(String)

    var applicationID: CFString {
        switch self {
        case .global:
            return kCFPreferencesAnyApplication
        case .app(let bundleIdentifier):
            return bundleIdentifier as CFString
        }
    }
}

enum TweakValue: Hashable, Sendable {
    case bool(Bool)
    case integer(Int)
    case double(Double)
}

enum ApplyRequirement: Int, Comparable, Sendable, Codable {
    case immediately
    case reopenApps
    case relaunchSystemUIServer
    case relaunchFinder
    case relaunchDock
    case logOut

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum TweakControl: Sendable {
    case toggle(inverted: Bool)
    case stops([TweakValue])
    case slider(range: ClosedRange<Double>, step: Double)
}

struct Tweak: Identifiable, Sendable {
    let id: String
    let title: String
    let help: String
    let domain: PreferenceDomain
    let key: String
    let isCurrentHost: Bool
    let control: TweakControl
    let unsetBehavesLike: TweakValue
    let appliesAfter: ApplyRequirement
    let affectedBundleIdentifiers: [String]
    let minimumMacOS: Int
    let maximumMacOS: Int?
    let systemSettingsPath: String?
    let caveat: String?
}
```

Notes:

- `unsetBehavesLike` is for display only. Reset never writes it; it removes the key.
- `affectedBundleIdentifiers` is empty for "all apps" and lists specific apps for app-scoped tweaks (`["com.apple.finder"]` for Quick Look).
- `systemSettingsPath` lets the UI say "Also in System Settings > Keyboard > Text Input". Hide or de-emphasise tweaks that are a 1:1 duplicate of a System Settings toggle, or keep them for completeness with that label.
- Version gating: hide tweaks outside `minimumMacOS...maximumMacOS` (`ProcessInfo.processInfo.operatingSystemVersion.majorVersion`). Mark dead keys (print panel, `…SaveMode2`, `expose-animation-duration`) with `maximumMacOS` or leave them out.
- `ApplyRequirement` is ordered so a batch can take the max.

### 4.2 Store

```swift
struct PreferenceStore {
    func storedValue(of tweak: Tweak) -> CFPropertyList? {
        CFPreferencesCopyValue(tweak.key as CFString, tweak.domain.applicationID, kCFPreferencesCurrentUser, host(for: tweak))
    }

    func write(_ value: TweakValue?, to tweak: Tweak) -> Bool {
        let host = host(for: tweak)
        CFPreferencesSetValue(tweak.key as CFString, value.map(propertyList), tweak.domain.applicationID, kCFPreferencesCurrentUser, host)

        return CFPreferencesSynchronize(tweak.domain.applicationID, kCFPreferencesCurrentUser, host)
    }

    func reset(_ tweak: Tweak) -> Bool {
        write(nil, to: tweak)
    }

    func isForced(_ tweak: Tweak) -> Bool {
        switch tweak.domain {
        case .global:
            return CFPreferencesAppValueIsForced(tweak.key as CFString, kCFPreferencesCurrentApplication)
        case .app(let bundleIdentifier):
            return CFPreferencesAppValueIsForced(tweak.key as CFString, bundleIdentifier as CFString)
        }
    }

    func refresh(_ domain: PreferenceDomain) {
        CFPreferencesSynchronize(domain.applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func host(for tweak: Tweak) -> CFString {
        tweak.isCurrentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
    }

    private func propertyList(from value: TweakValue) -> CFPropertyList {
        switch value {
        case .bool(let isOn):
            return isOn ? kCFBooleanTrue : kCFBooleanFalse
        case .integer(let number):
            return number as CFNumber
        case .double(let number):
            return number as CFNumber
        }
    }
}
```

After `write`, re-read with `storedValue(of:)` to confirm (a forced key or a failed write shows up here).

### 4.3 Reset

- Reset deletes the key (`CFPreferencesSetValue(key, nil, …)`), never writes the presumed default, so Apple's real default (which can change between releases) applies.
- Offer "Reset all Hidden Settings" that only removes keys in our catalogue and only if the stored value differs from "unset".
- Keep a small local journal (our own app's defaults): `{tweakID, previousStoredValue, newValue, changedAt}`. It powers "undo", "you changed this 3 days ago", and restoring a value the user had set by hand before Refined Settings touched it. The reset button removes the key; a separate "Restore previous value" uses the journal.

### 4.4 Pending "needs reopen / log out" state

Persist one record per tweak changed during the current login session:

```swift
struct PendingChange: Codable, Sendable {
    let tweakID: String
    let requirement: ApplyRequirement
    let changedAt: Date
    let loginSessionID: String
    let valueAtSessionStart: String?
}

func currentLoginSessionID() -> String {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    let uniqueID = session?["CGSSessionUniqueSessionUUID"] as? String
    let auditID = session?["kCGSSessionAuditIDKey"] as? Int ?? 0

    return uniqueID ?? "\(auditID)-\(bootTime())"
}
```

(`bootTime()` reads `sysctlbyname("kern.boottime")`.) `CGSSessionUniqueSessionUUID` and `kCGSSessionAuditIDKey` were present on 26.5 **[local]** but are not public constants, hence the fallback to the BSD audit session ID plus boot time, since audit IDs can repeat after a reboot.

Resolution rules, evaluated on launch and whenever the UI opens:

- `logOut`: resolved when `loginSessionID != currentLoginSessionID()`. This survives app relaunches and is cleared by a logout or a reboot.
- `relaunchDock` / `relaunchFinder` / `relaunchSystemUIServer`: resolved when `NSRunningApplication.runningApplications(withBundleIdentifier:)` shows a process whose `launchDate` is after `changedAt` (or a new login session).
- `reopenApps`: for each running regular app (`activationPolicy == .regular`) with `launchDate < changedAt`, list it as "still using the old setting". This gives a precise "Reopen Safari, Mail and 3 others" message instead of a vague warning. Resolved when the list is empty.
- If the user changes the value back to `valueAtSessionStart`, drop the pending record: nothing needs applying.
- For key repeat, also compare `NSEvent.keyRepeatInterval` against the stored pref so the UI can say "takes effect after log out" truthfully, and clear it once HID matches.

### 4.5 Batching relaunches

- Accumulate pending records; show a single banner with the max requirement and one button: "Log out…", "Restart Dock", "Restart Finder", or "Reopen 4 apps". Never relaunch automatically on each toggle; debounce until the user presses the button or closes the panel.
- If any pending record needs `logOut`, hide the Dock/Finder buttons; logout covers them.
- Dock, Finder and SystemUIServer are launchd agents (`com.apple.Dock.agent`, `com.apple.Finder`, `com.apple.SystemUIServer.agent`) with `KeepAlive = {AfterInitialDemand = true; SuccessfulExit = false}` **[local, `/System/Library/LaunchAgents`]**. launchd only respawns them after an *unsuccessful* exit, which is why `killall Dock` works and a clean quit may leave Finder closed. Options in the product, all targeting an exact PID or job label, never a name match:
  - Dock / SystemUIServer: `launchctl kickstart -k gui/<uid>/com.apple.Dock.agent`, or `kill(pid, SIGTERM)` on the `processIdentifier` from `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")`. Warn that restarting the Dock drops minimized-window state in some versions [cocoadev-dock-restart].
  - Finder: `NSRunningApplication.terminate()` (graceful), then relaunch with `NSWorkspace.shared.openApplication(at:configuration:)` if it does not come back. Behaviour on 26 is **unverified**.
  - Apps: offer "Quit and reopen" per app via `terminate()` + `openApplication`, only after confirming (unsaved documents).
  - Log out: sending `kAELogOut` to `loginwindow` shows the standard confirmation, but needs Apple Events permission (**unverified** on 26). The safe fallback is text: "Choose Apple menu > Log Out".

---

## 5. Things that are broken or behave unexpectedly (summary)

- `com.apple.dock expose-animation-duration`: broken since Sierra; string gone from the macOS 26 Dock. Drop it.
- `PMPrintingExpandedStateForPrint` and `…2`: the print dialog has had no collapsed mode since Ventura, and neither string exists on 26. Drop them.
- `NSNavPanelExpandedStateForSaveMode2`: string gone on 26. `NSNavPanelExpandedStateForSaveMode` still exists, but per-app saved state overrides it (4 apps here already do). Label it "Default for apps that haven't remembered their own choice".
- `KeyRepeat` / `InitialKeyRepeat`: need logout after a pref write; units disputed (15 ms vs 1/60 s ticks). Applying instantly via HID is possible in principle (System Settings does it) but untested.
- `NSWindowResizeTime`: still read, but only affects legacy animated frame changes. Low impact; label it honestly.
- Smart quotes vs dashes: System Settings has one toggle for both; separate keys let us split them.
- `WebAutomaticSpellingCorrectionEnabled`: when unset, WebKit follows text *replacement*, not spelling correction, so autocorrect can persist in Safari/Mail after turning off "Correct spelling automatically".
- `NSWindowShouldDragOnGesture`: works through 15.3; present in 26.5 but untested; ⌃⌘-click can also open context menus in Electron apps. There is a new, unexplained `NSWindowShouldDragOnGestureFeedback` key.
- `CFPreferencesCopyAppValue(…, kCFPreferencesAnyApplication)` returns AppKit's registered defaults for unset keys; `UserDefaults(suiteName: NSGlobalDomain)` is an error. Use `CFPreferencesCopyValue` / `SetValue` / `Synchronize`.

---

## Sources

- [mathias] mathiasbynens/dotfiles `.macos`: https://raw.githubusercontent.com/mathiasbynens/dotfiles/main/.macos
- [mathias-711] mathiasbynens/dotfiles issue #711, "Disabling Mission Control animation in Sierra?" (2016 to 2018): https://github.com/mathiasbynens/dotfiles/issues/711
- [mdc-pressandhold] macos-defaults.com, Key held down behavior: https://macos-defaults.com/keyboard/applepressandholdenabled.html
- [mdc-savetocloud] macos-defaults.com, Save to disk location: https://macos-defaults.com/finder/nsdocumentsavenewdocumentstocloud.html
- [ss64] ss64 `defaults` reference: https://ss64.com/mac/syntax-defaults.html
- [gist-zlass] Increase key repeat rate on macOS (gist, cites Apple SE answer 83923): https://gist.github.com/Zlass/36b2ca8a2b3d658f8018a6d44829eb5b
- [gist-nikolasgd] Set faster key repeat (gist, "Log out and back in again"): https://gist.github.com/nikolasgd/e04700be7583c7400fa8129fdf07d717
- [devto] "The 30-second hack…" (Dec 2025): https://dev.to/ackshaey/the-30-second-hack-that-will-speed-up-your-coding-more-than-any-framework-2men
- [til-vegard] Changing the keyboard repeat rate on macOS (2021): https://til.vegardstikbakke.com/posts/macos-keyboard-rate
- [cocoadev-2005] cocoa-dev, "Obtaining keyboard rate & delay metrics" (2005, ticks): https://lists.apple.com/archives/cocoa-dev/2005/Feb/msg01752.html
- [hexnode] Hexnode script to configure keyboard settings: https://www.hexnode.com/mobile-device-management/help/script-to-configure-keyboard-settings-on-mac.md
- [apple-input-sources] Apple, Change Input Sources settings (macOS 26): https://support.apple.com/en-au/guide/mac-help/mchl84525d76/26/mac
- [apple-replace-text] Apple, Replace text and punctuation (macOS 26): https://support.apple.com/en-mide/guide/mac-help/mh35735/26/mac
- [mpu-dashes] MPU forum, smart dashes vs quotes: https://talk.macpowerusers.com/t/turn-off-smart-dashes-but-leave-on-smart-quotes-in-macos/30905
- [apple-nsspellchecker] Apple docs, `NSSpellChecker.isAutomaticTextCompletionEnabled` (10.12.2) and `isAutomaticInlinePredictionEnabled` (14.0): https://developer.apple.com/documentation/appkit/nsspellchecker
- [webkit-textchecker] WebKit `TextCheckerMac.mm`: https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/TextCheckerMac.mm
- [gh-webkit-forwarded] WebKit `ForwardedNotifications.def` (lists `AppleTextBehaviorPreferencesChangedNotification`): https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Resources/cocoa/NotificationAllowList/ForwardedNotifications.def
- [apple-animationresizetime] Apple docs, `NSWindow.animationResizeTime(_:)`: https://developer.apple.com/documentation/appkit/nswindow/animationresizetime(_:)
- [gist-jj1bdx] macOS animation-disabling defaults gist: https://gist.github.com/jj1bdx/14c65d2b87359624dae8c359d7646512
- [ifun] ifun.de on `NSWindowShouldDragOnGesture` (May 2022): https://www.ifun.de/irgendwo-klicken-und-bewegen-geheime-fenster-einstellung-in-macos-186708
- [obsidian] Obsidian forum, "Context menu interferes with window dragging" (March 2025, Darwin 24.3): https://forum.obsidian.md/t/context-menu-interferes-with-window-dragging/98700
- [mpu-bigsur] MPU forum, Big Sur open/save dialog size: https://talk.macpowerusers.com/t/big-sur-and-open-save-dialog-box-size/20997
- [macformat-2022] Mac Format, Oct 2022 (global save-panel default no longer global): https://www.pressreader.com/australia/mac-format/20221018/283059828283025
- [macmost-ventura] MacMost, Tips for Using the Ventura Print Dialog: https://macmost.com/tips-for-using-the-ventura-print-dialog.html
- [macrumors-catalina] MacRumors, "always show print details not working on Catalina": https://forums.macrumors.com/threads/always-show-print-details-not-working-on-catalina.2208389
- [cf-header] `CFPreferences.h`, macOS 26.5 SDK (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreFoundation.framework/Headers/CFPreferences.h`)
- [nsuserdefaults-header] `NSUserDefaults.h`, macOS 26.5 SDK
- [apple-userdefaults] Apple docs, `UserDefaults`: https://developer.apple.com/documentation/foundation/userdefaults
- [apple-suitename] Apple docs, `UserDefaults.init(suiteName:)`: https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:)
- [apple-didchange] Apple docs, `UserDefaults.didChangeNotification`: https://developer.apple.com/documentation/foundation/userdefaults/didchangenotification
- [apple-isforced] Apple docs, `CFPreferencesAppValueIsForced` / `UserDefaults.objectIsForced(forKey:)`: https://developer.apple.com/documentation/foundation/userdefaults/objectisforced(forkey:)
- [apple-temp-exceptions] Apple, App Sandbox Temporary Exception Entitlements: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html
- [gh-container-348] apple/container issue #348 (temporary exceptions rejected by review): https://github.com/apple/container/issues/348
- [app-review] App Store Review Guidelines 2.4.5, 2.5.1, 2.5.2: https://developer.apple.com/app-store/review/guidelines/
- [prefseditor] Prefs Editor: https://apps.tempel.org/PrefsEditor/
- [defaults-edit] ThatsJustCheesy/defaults-edit: https://github.com/ThatsJustCheesy/defaults-edit
- [swift-prefs] scriptingosx/swift-prefs: https://github.com/scriptingosx/swift-prefs
- [gh-yabai] yabai `src/workspace.m` (observes `com.apple.dock.prefchanged`): https://github.com/asmvik/yabai/blob/master/src/workspace.m
- [cocoadev-dock] CocoaDev, HowToMakeDockReloadPreferenceFile: https://github.com/jnozzi/cocoadev.com/blob/master/markdown/HowToMakeDockReloadPreferenceFile.md
- [cocoadev-dock-restart] cocoa-dev, "What's the friendliest way to restart the Dock?" (2009): https://lists.apple.com/archives/Cocoa-dev/2009/Oct/msg02121.html
- Local evidence: macOS 26.5.2 `defaults`, `ioreg`, `hidutil`, `launchctl print`, `/System/Library/LaunchAgents/*.plist`, `KeyboardSettings.appex`, `Dock.app`, `PrintingPrivate.framework`, and the dyld shared cache at `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/`.
