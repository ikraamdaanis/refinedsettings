# Refined Settings: app architecture research

Research for the rename of Linkguide to Refined Settings (`RefinedSettings`, `com.ikraam.refinedsettings`), its sidebar Settings window, optional modules, permissions, launch at login and the build setup. Researched 2026-11-08 on macOS 26.5 with Swift 6.3.3 from the Command Line Tools.

Facts marked **(verified locally)** were checked read-only on the developer machine. Facts marked **unverified** come from a single non-authoritative source, from memory, or could not be confirmed.

## Summary of recommendations

1. **Keep the AppKit-managed Settings window** (an `NSWindowController` hosting a SwiftUI `NavigationSplitView`). Do not move to the SwiftUI `Settings` scene: in an `LSUIElement` app it needs a hidden-window workaround, the private `showSettingsWindow:` selector stopped working in macOS 14, and `openSettings` is reported broken again on 26. The current `SettingsWindowController` already solves activation and Spaces correctly; extend it rather than replace it.
2. **Raise the deployment target to macOS 14.** It unlocks `@Observable`, `toolbar(removing: .sidebarToggle)`, `NSHostingController.sceneBridgingOptions` (window title and toolbar bridged from SwiftUI), `contentMargins` and cooperative `NSApp.activate()`, and removes most `#available` forks. Go to macOS 15 only if nobody else will run it. Staying on 13 is workable but costs a hand-rolled sidebar-toggle removal and `ObservableObject` everywhere.
3. **Keep `NSStatusItem`, not `MenuBarExtra`.** The app is AppKit-lifecycle (`main.swift`), and `MenuBarExtra` gives no access to the status item, no programmatic open and a run-loop-blocking menu style. For "Show menu bar icon": set `autosaveName`, add `.removalAllowed`, KVO `isVisible`, and always open Settings from `applicationShouldHandleReopen` (Rectangle and Stats do this). On a manual cold launch with the icon hidden, open Settings too. Tell users in the UI that reopening the app from Finder or Spotlight brings Settings back. On Tahoe, the "Allow in the Menu Bar" switch can hide the icon and apps cannot read it (Apple DTS).
4. **Launch at login with `SMAppService.mainApp`**, read `status` every time (on Settings appear and on app activation), never store a bool. Handle `.requiresApproval` with `SMAppService.openSystemSettingsLoginItems()`. Only register from the copy in `/Applications`, and only with the stable Apple Development signature, to avoid duplicate "Login Item Added" entries.
5. **Migrate defaults once** by reading `UserDefaults.standard.persistentDomain(forName: "com.ikraam.linkguide")` (non-sandboxed, so allowed), copying only missing keys, then setting a `didMigrateFromLinkguide` flag. There is nothing else to migrate on this machine (no Application Support folder, no login item, no status item position keys) **(verified locally)**. Accessibility, default-browser registration and Tahoe menu bar permission do **not** carry over; the user must re-grant and re-choose, and should delete `/Applications/Linkguide.app` and unregister it.
6. **Accessibility UX:** request only when a module that needs it is switched on. Call `AXIsProcessTrustedWithOptions` with the prompt (this also adds the app to the list), open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` as a fallback, and detect the grant with the `com.apple.accessibility.api` distributed notification plus a short debounce, polling once a second only while a request is pending or Settings is open. A mouse/scroll module that modifies events needs **Accessibility**; a listen-only tap would need **Input Monitoring**.
7. **Pin the signing identity by SHA-1 in `build.sh`.** The installed Linkguide's designated requirement pins the leaf certificate CN, and there are **two** Apple Development identities in the keychain **(verified locally)**. "First Apple Development identity" can silently flip and break the TCC grant.
8. **Module pattern:** a `ModuleID` enum, a `@MainActor` `AppModule` protocol (`requiredPermissions`, `isRunning`, `start()`, `stop()`), a typed `SettingsStore` over an injected `UserDefaults`, and a coordinator that reconciles "enabled AND permitted" into start/stop. A module that is off holds no event tap, timer, observer or Task; `init` does nothing.
9. **Decide what the Links module does when it is off while the app is still the default browser.** macOS keeps sending links to the app. Either forward them straight to a fallback browser, or offer to change the default browser when the module is switched off.
10. **Stay on SwiftPM for now**, but know the limits: no `actool`/`ictool` without Xcode **(verified locally)**, so no asset catalogs, no Icon Composer `.icon`, no String Catalogs. Ship the `.icns` drawn on Apple's squircle grid so Tahoe does not put it in a grey plate. Install Xcode (and optionally XcodeGen) only when a Tahoe `.icon`, notarisation or localisation is needed.
11. **Testing:** split into a `RefinedSettingsCore` library (logic, `package` access level) plus a thin executable, and use Swift Testing. `Testing.framework` ships in the Command Line Tools; XCTest.framework does not **(verified locally)**.

---

## 1. Settings window with a sidebar (macOS 13+)

### Options compared

| Approach | Verdict for an `LSUIElement` AppKit-lifecycle app |
| --- | --- |
| SwiftUI `Settings` scene | Avoid. Needs `@main App`, and opening it from AppKit is the problem below. |
| SwiftUI `Window` scene (`openWindow(id:)`) | Works (Ice does it) but needs SwiftUI-lifecycle plumbing, delays and swizzling. |
| `NSWindowController` + `NSHostingController(rootView: NavigationSplitView)` | **Recommended.** Full control over activation, Spaces, size and lifetime. What Linkguide already does. |

**Why the `Settings` scene is unreliable in menu bar apps:**

- macOS 13 apps opened Settings with `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`; on macOS 14 this "does not work anymore" and you must use `SettingsLink` ([Apple forums 739831](https://developer.apple.com/forums/thread/739831)). The log message is "Please use SettingsLink for opening the Settings scene." ([steipete, 2025](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/)).
- `SettingsLink` opens Settings but does not bring an already-open window to the front, and clicking a `MenuBarExtra` does not activate the app ([orchetect/SettingsAccess](https://github.com/orchetect/SettingsAccess)). It also cannot run code before or after opening ([sspai](https://sspai.com/post/105243)).
- `openSettings` (macOS 14+, [Apple docs](https://developer.apple.com/documentation/swiftui/opensettingsaction)) needs an existing SwiftUI render tree, works on 15, and is reported **not** to work on 26 Tahoe. The workaround is a hidden window declared before the `Settings` scene, an activation-policy switch and 100 to 200 ms delays ([steipete, 2025](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/); 26 breakage is that author's report, **unverified** elsewhere).
- Accessory apps are not brought to the front by the system, so Settings opens behind other apps unless you switch to `.regular` and activate ([steipete](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/), [Hacking with Swift forum](https://www.hackingwithswift.com/forums/macos/how-to-open-settings-from-menu-bar-app-and-show-app-icon-in-dock/26267)).
- Even Ice, which uses a SwiftUI `Window` scene for its settings, opens it after a 0.1 s delay with an explicit `activate(withPolicy: .regular)` and swizzles `NSSplitViewItem` at startup ([Ice `AppDelegate.swift`, `IceApp.swift`](https://github.com/jordanbaird/Ice/tree/main/Ice/Main)).
- Rectangle uses a plain AppKit `NSWindowController` for Settings ([Rectangle `SettingsWindowController.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/SettingsWindow/SettingsWindowController.swift)).

Linkguide's controller already does the right things: switch to `.regular`, `NSApp.activate()` on 14+ (`activate(ignoringOtherApps:)` on 13), `makeKeyAndOrderFront`, and back to `.accessory` plus `NSApp.hide(nil)` on close.

### Window setup for a System Settings look

A `NavigationSplitView` inside an `NSHostingController` behaves almost like one in a `WindowGroup`, as long as the window has `.fullSizeContentView` so the sidebar can run full height; a toolbar (with a sidebar tracking separator in pure AppKit) lets the divider extend through the title bar ([full-height sidebar write-up, 2024](https://websnapshot.pages.dev/html/readit.site_a_tWcdh_macos-full-height-sidebar-window-62a214309a80.html)). On macOS 14+, a hosting controller that is a window's `contentViewController` defaults to `sceneBridgingOptions = .all`, so SwiftUI `.navigationTitle` and `.toolbar` drive the window's title and toolbar ([Apple docs](https://developer.apple.com/documentation/swiftui/nshostingcontroller/scenebridgingoptions)). On 13 you set `window.title` yourself.

One guide claims that on macOS 26 `.fullSizeContentView` must be set when the window is created for the Liquid Glass chrome to render, and that adding it later is unreliable ([macos-settings-ui skill](https://skills.cat/skills/fayazara/macos-app-skills/macos-settings-ui)) **unverified**; creating the window in AppKit with the mask set up front sidesteps the question.

```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsRootView())
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        newWindow.toolbar = NSToolbar(identifier: "settings")
        newWindow.toolbarStyle = .unified
        newWindow.title = "Refined Settings"
        newWindow.setContentSize(NSSize(width: 715, height: 520))
        newWindow.contentMinSize = NSSize(width: 640, height: 420)
        newWindow.setFrameAutosaveName("RefinedSettingsWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        window = newWindow

        return newWindow
    }
}
```

### The SwiftUI side

```swift
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case links
    case mouseAndScrolling
    case hiddenSettings
    var id: String { rawValue }
}

struct SettingsRootView: View {
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SidebarIcon(symbolName: pane.symbolName, tint: pane.tint)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
            .modifier(RemoveSidebarToggle())
        } detail: {
            SettingsDetail(pane: selection ?? .general)
                .navigationTitle((selection ?? .general).title)
        }
    }
}

struct SidebarIcon: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct RemoveSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

struct GeneralPane: View {
    var body: some View {
        Form {
            Section("App") {
                Toggle("Launch at login", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
    }
}
```

(`SettingsPane.title`, `symbolName` and `tint` are a `switch` on the enum, omitted.)

Details and evidence:

- **Sidebar width and window size.** Ice uses a 190/210/230 pt sidebar depending on the user's sidebar icon size, a `minWidth: 825, minHeight: 500` frame and a 900 x 625 default ([Ice `SettingsView.swift`, `SettingsWindow.swift`](https://github.com/jordanbaird/Ice/tree/main/Ice/Settings)). A System Settings measurement reports a 215 pt sidebar in a roughly 715 x 470 window ([Medium, schopenlaam](https://medium.com/@schopenlaam/macos-app-settings-9ee3f8d50e57), page not fetchable, figures **unverified**).
- **Coloured rounded-square icons** are not a system style; you draw them (snippet above). Packages exist that do the same ([SettingsIconGenerator](https://swiftpackageregistry.com/sparrowcode/SettingsIconGenerator), [BadgeIcon](https://github.com/danielsaidi/BadgeIcon)). Icon size, corner radius and tints above are eyeballed, **unverified** against System Settings.
- **`toolbar(removing: .sidebarToggle)` is macOS 14+** ([Apple docs](https://developer.apple.com/documentation/swiftui/view/toolbar(removing:))). Apply it to the sidebar's root view; one macOS 26 report says applying it elsewhere left the toggle visible ([Reddit thread](https://www.reddit.com/r/SwiftUI/comments/1leisfx/)). On 13 the only route found is removing the toolbar item `com.apple.SwiftUI.navigationSplitView.toggleSidebar` through SwiftUI-Introspect ([Apple forums 727968](https://developer.apple.com/forums/thread/727968)). Users can still drag the divider closed; fixing that needs `NSSplitViewController`/`NSSplitViewItem` collapse behaviour ([same thread](https://developer.apple.com/forums/thread/727968)), which is likely why Ice swizzles `NSSplitViewItem`.
- **Detail panes:** `Form { }.formStyle(.grouped)` (13+) gives the inset rounded sections. One guide adds `.scrollContentBackground(.hidden)` and, on 14+, `.contentMargins(.top, 8, for: .scrollContent)`; on 26, `scrollEdgeEffectStyle(.soft, for: .all)` ([macos-settings-ui skill](https://skills.cat/skills/fayazara/macos-app-skills/macos-settings-ui)).

### macOS 13 vs 14 vs 15 vs 26

| | 13 Ventura | 14 Sonoma | 15 Sequoia | 26 Tahoe |
| --- | --- | --- | --- | --- |
| `NavigationSplitView`, `formStyle(.grouped)`, `navigationSplitViewColumnWidth` | yes | yes | yes | yes |
| `toolbar(removing: .sidebarToggle)` | no | yes | yes | yes |
| `sceneBridgingOptions` (title/toolbar from SwiftUI) | no | yes | yes | yes |
| `NSApp.activate()` (cooperative) | no, use `activate(ignoringOtherApps:)` | yes | yes | yes |
| Settings scene from AppKit | `showSettingsWindow:` works | broken, `SettingsLink`/`openSettings` | `openSettings` works with hidden window | `openSettings` reported broken |
| Sidebar look | classic vibrancy | classic | classic | Liquid Glass, floating sidebar |

On Tahoe, sidebars float above content and `.backgroundExtensionEffect()` extends detail content under them ([WWDC25 session 323 notes](https://wwdcnotes.com/documentation/wwdc25-323-build-a-swiftui-app-with-the-new-design/), [Apple docs](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect())). The new design is picked up automatically when the app is built against the 26 SDK ([4D blog](https://blog.4d.com/?p=69113)); the CLT here builds for `arm64-apple-macosx26.0` with `MacOSX26.5.sdk` **(verified locally)**, so the window will get Liquid Glass on Tahoe without code changes. The `UIDesignRequiresCompatibility` opt-out is temporary and its macOS behaviour is unclear ([Apple forums 832543](https://developer.apple.com/forums/thread/832543)); do not rely on it. A Tahoe bug report: with `.fullSizeContentView`, a sidebar made with `NSSplitViewItem(sidebarWithViewController:)` is cut off at the top in full screen ([Apple forums 801087](https://developer.apple.com/forums/thread/801087)); disable full screen for Settings (do not add `.fullScreenPrimary`).

### Current Space and focus

- `NSWindow.CollectionBehavior.moveToActiveSpace` moves the window to the active Space when it becomes active instead of switching Spaces ([Apple docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace)). Linkguide instead calls `orderOut` when a visible window is not `isOnActiveSpace` and re-shows it, which also respects a Dock "Assign To Desktop" choice. Keep that.
- On 14+, `activate()` is a request under cooperative activation; it can be refused if the frontmost app has not yielded ([Apple docs](https://developer.apple.com/documentation/appkit/nsapplication/activate())). Activating from a status-menu click or a reopen event works in practice because the user just interacted with the app. If the window sometimes stays behind right after `setActivationPolicy(.regular)`, the Ice-style 0.1 s delay is the known workaround ([Ice `AppDelegate.swift`](https://github.com/jordanbaird/Ice/blob/main/Ice/Main/AppDelegate.swift)).

### Keyboard navigation

- Install the main menu while `.regular` (Linkguide does): Cmd-, opens Settings, Cmd-W closes, Cmd-Q quits, Cmd-M minimises.
- A sidebar `List(selection:)` supports arrow keys when focused. Tab between controls in the `Form` follows the user's "Keyboard navigation" setting (System Settings > Keyboard); that is system behaviour and should not be forced.
- Give buttons `.keyboardShortcut(.defaultAction)` where there is an obvious primary action (for example "Grant Access…"), and keep the sidebar the initial first responder so Up/Down switches panes immediately. Do not add Esc-to-close; System Settings does not close on Esc.

---

## 2. Menu bar

### `NSStatusItem` vs `MenuBarExtra`

| | `NSStatusItem` | `MenuBarExtra` (macOS 13+) |
| --- | --- | --- |
| Lifecycle | Any (works with `main.swift`) | SwiftUI `App` only |
| Programmatic open/close | `button?.performClick` | None first-party; needs MenuBarExtraAccess ([orchetect](https://github.com/orchetect/MenuBarExtraAccess)) |
| Access to the status item/button | Full | None first-party ([MenuBarExtraAccess README](https://github.com/orchetect/MenuBarExtraAccess)) |
| `.menu` style | Normal `NSMenu` | Blocks the run loop while open; `isPresented` changes are ignored ([MenuBarExtraAccess README](https://github.com/orchetect/MenuBarExtraAccess)) |
| Show/hide | `isVisible`, `removeStatusItem` | `isInserted:` binding |
| Detect dismissal | `NSMenuDelegate` | No reliable way ([Apple forums 836113](https://developer.apple.com/forums/thread/836113)) |

Keep `NSStatusItem`.

### Visibility API facts (from the macOS 26.5 SDK header, **verified locally**)

- `isVisible`: "Defaults to YES. Persisted based on the -autosaveName. This is observable through KVO." It stays `true` when the item is hidden for lack of space ([Apple docs](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)).
- `autosaveName`: "If none is specified, one is automatically chosen. Apps with multiple status bar items should set an autosave after creation." Electron recommends an explicit name so a Cmd-drag position persists ([electron#42154](https://github.com/electron/electron/issues/42154)).
- `.removalAllowed`: lets the user Cmd-drag the item off; "It is the application's responsibility to allow the user to re-add the item. Upon removal, -visible is set to NO."
- Linkguide's defaults domain has no status item keys **(verified locally)**, so there is no position to migrate.

### "Show menu bar icon" off: how users get back in

- **Relaunch opens Settings.** Opening a running app again from Finder, Spotlight or Launchpad sends a reopen Apple event, which calls `applicationShouldHandleReopen(_:hasVisibleWindows:)`. Rectangle opens Settings there (or the menu, by preference) ([Rectangle `AppDelegate.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AppDelegate.swift)); Stats opens its settings window ([Stats `AppDelegate.swift`](https://github.com/exelban/stats/blob/master/Stats/AppDelegate.swift)); Maccy toggles its panel ([Maccy `AppDelegate.swift`](https://github.com/p0deje/Maccy/blob/master/Maccy/AppDelegate.swift)). Linkguide already does this. Ice's `AppDelegate` has no reopen handler ([Ice](https://github.com/jordanbaird/Ice/blob/main/Ice/Main/AppDelegate.swift)).
- **Cold launch with the icon hidden** (app not running): `applicationShouldHandleReopen` is not called, so in `applicationDidFinishLaunching` open Settings when the icon is hidden and the launch was not a login launch. LaunchAtLogin-Modern detects a login launch by checking the current Apple event for `keyAELaunchedAsLogInItem` inside `applicationDidFinishLaunching` ([LaunchAtLogin-Modern source](https://github.com/sindresorhus/LaunchAtLogin-Modern/blob/main/Sources/LaunchAtLogin/LaunchAtLogin.swift)).
- **Rectangle's pattern:** a stored `hideMenuBarIcon` setting adds or removes the item; with `.removalAllowed`, a KVO observer on `isVisible` flips the setting when the user Cmd-drags the item off ([Rectangle `RectangleStatusItem.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/General/RectangleStatusItem.swift)).
- Put a footnote under the toggle: "To open Settings while the icon is hidden, open Refined Settings again from Applications or Spotlight."

```swift
import AppKit

@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var visibilityObservation: NSKeyValueObservation?

    init(menu: NSMenu, onUserRemoval: @escaping @MainActor () -> Void) {
        statusItem.autosaveName = "RefinedSettings.main"
        statusItem.behavior = .removalAllowed
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Refined Settings")
        visibilityObservation = statusItem.observe(\.isVisible, options: [.old, .new]) { _, change in
            guard change.oldValue == true, change.newValue == false else { return }

            MainActor.assumeIsolated {
                onUserRemoval()
            }
        }
    }

    func setVisible(_ isVisible: Bool) {
        statusItem.isVisible = isVisible
    }
}
```

`onUserRemoval` writes `showsMenuBarIcon = false` to the settings store, so the Settings toggle stays in sync. Set the visibility from the store right after creating the item so the store, not AppKit's autosave, is the source of truth.

### macOS 26 Tahoe menu bar changes

- System Settings > Menu Bar has an **"Allow in the Menu Bar"** section with a switch per third-party app ([TechRadar](https://www.techradar.com/computing/mac-os/what-is-the-macos-menu-bar-heres-how-new-macbook-neo-users-can-get-the-most-out-of-apples-app-control-bar), [consomac](https://consomac.fr/news-21397-macos-tahoe-26-controle-l-acces-des-applications-a-la-barre-de-menus.html)), letting users hide items even for apps that have no such option ([MacStories review](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3)).
- **Apps cannot read that switch.** Apple DTS (Quinn, June 2025): "Does macOS provide a way for me to determine the 'Allow in the menu bar' state … is 'No.'" The suggested path is `.removalAllowed` plus KVO ([Apple forums 788101](https://developer.apple.com/forums/thread/788101)). So the in-app toggle can read "on" while Tahoe hides the icon; the reopen-opens-Settings path is the safety net.
- Renamed or deleted apps can linger in that list, and both old and new versions of a replaced app have shown up ([Apple Community 256145886](https://discussions.apple.com/thread/256145886)). Expect "Linkguide" to stay listed after the rename.
- Some users found icons hidden without their knowledge, fixed by toggling all third-party apps off, logging out and back in ([Parallels forum](https://forum.parallels.com/threads/asking-how-to-keep-toolbox-icon-on-menu-bar.369594/)).
- Tahoe also adds Control Center controls that can sit in the menu bar; third-party ones come from WidgetKit control extensions ([MacStories](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3)). They need an app extension bundle, which is impractical with a hand-built SwiftPM bundle (**unverified**, not tried).

---

## 3. Launch at login

`SMAppService.mainApp` (macOS 13+) registers the app itself as a login item; no helper bundle is needed ([Apple DTS, forums 777520](https://developer.apple.com/forums/thread/777520)). From the macOS 26.5 SDK header **(verified locally)** and Apple docs:

- Status values: `.notRegistered`, `.enabled`, `.requiresApproval` ("registered … but the user needs to take action in System Settings", also returned after the user revokes consent, [Apple docs](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)), `.notFound` ("An error occurred and the framework couldn't find this service", [Apple docs](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/notfound)).
- `register()` throws `kSMErrorAlreadyRegistered` if already registered and `kSMErrorLaunchDeniedByUser` if not approved ([Apple docs](https://developer.apple.com/documentation/servicemanagement/smappservice/register())); `unregister()` throws `kSMErrorJobNotFound` if already unregistered (header).
- `openSystemSettingsLoginItems()` opens the Login Items pane; the header says to call it after the user confirms they want to re-enable the item.
- LaunchAtLogin-Modern reads `SMAppService.mainApp.status == .enabled` on every access (no cache), unregisters before re-registering when already enabled, and logs errors ([source](https://github.com/sindresorhus/LaunchAtLogin-Modern/blob/main/Sources/LaunchAtLogin/LaunchAtLogin.swift)). It only notifies SwiftUI when changed through its own API, so a change made in System Settings is not reflected until something re-reads `status`.

```swift
import AppKit
import ServiceManagement
import os

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    private let logger = Logger(subsystem: "com.ikraam.refinedsettings", category: "LaunchAtLogin")
    private var activationObserver: NSObjectProtocol?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    init() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ shouldEnable: Bool) {
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }

        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

Also call `refresh()` in the General pane's `.onAppear`. When `needsApproval` is true, show "Approval needed in System Settings" with an "Open Login Items…" button rather than a toggle that lies.

**Notification, signing and location:**

- `register()` makes macOS post a "Login Item Added" (background item) notification. One developer with an unsigned build got `.notFound` and a new notification on every build, ending with 100+ duplicate entries that could not be removed; the reporter suspected missing signing, unconfirmed ([LaunchAtLogin#100](https://github.com/sindresorhus/LaunchAtLogin/issues/100)). Ad-hoc signing is therefore **unverified** but risky; the stable Apple Development signature avoids it.
- Background-item state is persisted deliberately to preserve user consent, so entries for deleted apps can linger; stray copies in build folders have been launched instead of the intended copy ([Apple forums, Platskies](https://developer.apple.com/forums/profile/Platskies/replies)). `sudo sfltool dumpbtm` lists records and `sfltool resetbtm` clears them (user action, not for the app to do).
- Recommendation: only offer the toggle (or only call `register()`) when `Bundle.main.bundleURL` is inside `/Applications`, so `.build` staging copies never register. Whether `register()` itself refuses copies outside `/Applications` is **unverified**; no source found.
- Do not enable launch at login by default; the Mac App Store guidelines require a user action and LaunchAtLogin-Modern repeats that advice ([LaunchAtLogin-Modern README](https://github.com/sindresorhus/LaunchAtLogin-Modern)). Not an App Store app, but the same courtesy applies.

---

## 4. Migration from `com.ikraam.linkguide`

### Reading the old domain

- Apple: "In macOS, specify another app's bundle identifier to search that app's settings. You can't search another app's settings if either app runs in an App Sandbox and you don't have the proper entitlements." `UserDefaults(suiteName:)` is equivalent to `CFPreferencesCopyAppValue(key, domain)` ([Apple docs, `init(suiteName:)`](https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:))). Both apps are unsandboxed, so this works.
- Caveat (from the same doc): every `UserDefaults` instance shares the argument and registration domains, so a suite instance can return a value that Refined Settings registered as a default, not one Linkguide stored. Use `persistentDomain(forName:)`, which returns only the keys stored in that domain.
- Go through the API, not the plist file: `cfprefsd` caches preferences, and a running Linkguide may hold unflushed values. Quit Linkguide before first launching Refined Settings.
- Current contents **(verified locally, `defaults read`)**: `entryOrder` (5 entries), `hiddenEntryIDs` (empty), `safariProfileNames` (empty). No `~/Library/Application Support/Linkguide`, no container. Nothing else to migrate.

```swift
import Foundation

enum LinkguideMigration {
    static let legacyDomain = "com.ikraam.linkguide"
    static let completedKey = "migration.linkguide.completed"
    /// Old key to new key. Rename the right-hand side if the new app namespaces its keys.
    static let keyMap = [
        "entryOrder": "links.entryOrder",
        "hiddenEntryIDs": "links.hiddenEntryIDs",
        "safariProfileNames": "links.safariProfileNames",
    ]

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completedKey) else { return }

        let legacyValues = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        migrate(legacyValues: legacyValues, into: defaults)
    }

    /// Split out so tests can pass a plain dictionary.
    static func migrate(legacyValues: [String: Any], into defaults: UserDefaults) {
        for (legacyKey, newKey) in keyMap where defaults.object(forKey: newKey) == nil {
            guard let value = legacyValues[legacyKey] else { continue }

            defaults.set(value, forKey: newKey)
        }

        defaults.set(true, forKey: completedKey)
    }
}
```

Run it first thing in `applicationDidFinishLaunching`, before any `register(defaults:)` reads matter. Leave the old domain in place (rollback is just relaunching Linkguide); the uninstall steps delete it.

### What does not carry over

| Item | Why | What to do |
| --- | --- | --- |
| **Accessibility (TCC)** | The grant is keyed to the app's identity. The installed Linkguide's designated requirement is `identifier "com.ikraam.linkguide" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: …" …` **(verified locally, `codesign -d -r-`)**, so a new bundle ID is a new app to TCC. | Re-grant on first use of a module that needs it. The old "Linkguide" row stays in the list until the user removes it (minus button) or runs `tccutil reset Accessibility com.ikraam.linkguide` themselves. |
| **Default browser** | Launch Services stores the http/https handler by bundle ID; it still points at `com.ikraam.linkguide`. | In the Links pane, detect `NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com"))` not being this app and offer "Make Refined Settings the default browser". `setDefaultApplication(at:toOpenURLsWithScheme:)` asks for consent asynchronously before calling back ([Apple docs](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:))); the CoreServicesUIAgent dialog can appear behind your window ([Chromium source](https://chromium.googlesource.com/chromium/src/+/711ab9bc/chrome/browser/shell_integration_mac.mm)), so do not keep Settings floating above it. |
| **Login item** | Linkguide never used `SMAppService` **(verified locally, grep)**. | Nothing. |
| **Tahoe "Allow in the Menu Bar"** | Per app. | New row appears; old one may linger (section 2). |
| **Launch Services registration** | `/Applications/Linkguide.app` stays registered and keeps claiming http/https and HTML documents; "Open With" may list both. | Tell the user to quit Linkguide, `lsregister -u /Applications/Linkguide.app`, delete it (the README's uninstall steps already do this). Optionally have `build.sh` do the `lsregister -u` and removal when the old app exists, after asking. Single-app unregister has been flaky on Sequoia (error -10814) and Spotlight can re-add apps it still finds on disk ([Eclectic Light, 2025](https://eclecticlight.co/2025/03/27/controlling-launchservices-in-macos-sequoia/), [engineered.at](https://engineered.at/articles/launchservices-and-spotlight)), so deleting the bundle matters more than unregistering. |

### URL handling to keep

The new `Info.plist` must keep `CFBundleURLTypes` (http, https, role Viewer) and the `public.html`/`public.xhtml` `CFBundleDocumentTypes`, or macOS will not offer Refined Settings as a browser. Keep the cold-launch URL buffering in `application(_:open:)`.

**Links module off but still default browser:** macOS will keep delivering links whatever the module state. Options: (a) when Links is off, forward every URL straight to a fallback browser chosen in the Links pane (cheapest and safest), or (b) when the user switches Links off, offer to make another browser the default. Recommend (a) plus a one-line explanation in the Links pane.

---

## 5. Permissions UX

### Accessibility vs Input Monitoring

- Apple DTS: "'Accessibility' basically grants event posting and listening, while 'Input Monitoring' only grants listening." A `.defaultTap` (can modify or drop events) triggers the Accessibility request; a `.listenOnly` tap triggers Input Monitoring; an app with Accessibility already has Input Monitoring ([Apple forums 828052](https://developer.apple.com/forums/thread/828052), [122492](https://developer.apple.com/forums/thread/122492)).
- Listen-only access has `CGPreflightListenEventAccess()`/`CGRequestListenEventAccess()`; apps often do not appear in the Input Monitoring list after the request, and DTS points to `IOHIDRequestAccess()` ([Apple forums 828052](https://developer.apple.com/forums/thread/828052), [707680](https://developer.apple.com/forums/thread/707680)).
- For this app: **Links** (driving Safari's menus through AX) needs Accessibility. **Mouse & Scrolling** that changes scroll direction, speed or smoothing needs an active tap, so Accessibility (LinearMouse requires Accessibility and also checks `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)`, [LinearMouse `AccessibilityPermission.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/AccessibilityPermission.swift)). A purely observing feature could use Input Monitoring instead. **Hidden Settings** (writing other apps' defaults) needs neither, though writing into sandboxed apps' containers may need Full Disk Access (**unverified**).

### Requesting

- `AXIsProcessTrustedWithOptions` with the prompt option shows the system alert and adds the app to the Accessibility list, the only supported way to pre-populate it ([FineTune `AccessibilityPermissionService.swift`](https://github.com/ronitsingh10/FineTune/blob/main/FineTune/Coordination/AccessibilityPermissionService.swift)).
- In Swift 6, `kAXTrustedCheckOptionPrompt` is a non-concurrency-safe global `var`; pass the literal `"AXTrustedCheckOptionPrompt"` instead (FineTune does; Linkguide already does).
- Deep link: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. Apple does not document these URLs, but current apps use it: Rectangle ([`AccessibilityView.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityAuthorization/AccessibilityView.swift)) and FineTune (above), and it is reported working on Ventura ([CopilotForXcode#53](https://github.com/intitni/copilotforxcode/issues/53)). The Ventura-era form `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` also exists ([PermissionFlow](https://docs.rs/crate/permission-flow/latest/source/PermissionFlow/Sources/SystemSettingsKit/SystemSettingsDestination.swift)). Working on every version 13 through 26 is **unverified** (not opened here, to avoid touching System Settings); open it on each OS you support once.
- Request only from a user action: switching on a module whose `requiredPermissions` are missing, or the "Grant Access…" button in General. Never at launch.

### Detecting the grant

- Hammerspoon, MonitorControl, Shifty and FineTune observe the `com.apple.accessibility.api` distributed notification (GitHub code search). FineTune debounces 250 ms before re-reading `AXIsProcessTrusted()` ([FineTune](https://github.com/ronitsingh10/FineTune/blob/main/FineTune/Coordination/AccessibilityPermissionService.swift)); the notification arrives around the change, not necessarily after TCC has updated.
- Ice and LinearMouse poll every second ([Ice `Permission.swift`](https://github.com/jordanbaird/Ice/blob/main/Ice/Permissions/Permission.swift), [LinearMouse](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/AccessibilityPermission.swift)). lan-mouse also polls once a second and says the AX notification was not suitable for its case ([lan-mouse](https://docs.rs/crate/lan-mouse-gtk/0.3.0/source/src/macos_privacy.rs)).
- `AXIsProcessTrusted()` can stay `true` after the user **removes** the app from the list (rather than unticking it), and a `.defaultTap` running when Accessibility is revoked can block clicks until restart ([Apple forums 735204](https://developer.apple.com/forums/thread/735204)). LinearMouse cross-checks with `IOHIDCheckAccess` for this reason.

Recommendation: observe the notification while the app runs (cheap), debounce, re-read; poll every second only while a request is pending or Settings is open; stop the poll on grant. On revocation, stop modules that need the permission immediately.

```swift
import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isGranted = AXIsProcessTrusted()
    private var changeObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    func startObserving() {
        guard changeObserver == nil else { return }

        changeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        }
    }

    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isGranted = AXIsProcessTrustedWithOptions(options)
        guard !isGranted else { return }

        openSystemSettings()
        startPolling()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }

        NSWorkspace.shared.open(url)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            self?.isGranted = AXIsProcessTrusted()
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let isTrusted = AXIsProcessTrusted()
                self?.isGranted = isTrusted
                if isTrusted { break }
            }

            self?.pollTask = nil
        }
    }
}
```

(`Task.sleep(nanoseconds:)` keeps it macOS 13 compatible; on 14+ use `Task.sleep(for: .seconds(1))`. Cap the poll, for example two minutes, in real code.)

### "Toggle is on but still not trusted after a rebuild"

- TCC stores the code's designated requirement. An ad-hoc signature's requirement is its cdhash, which changes on every build, so the row stays ticked while the grant no longer matches; a stable certificate pins the requirement to the certificate instead and the grant survives rebuilds ([TCC cdhash trap](https://nickboy-github-io.pages.dev/posts/tcc-cdhash-trap/), [skhd.zig CODE_SIGNING.md](https://raw.githubusercontent.com/jackielii/skhd.zig/main/docs/CODE_SIGNING.md), [Stack Overflow 29006379](https://stackoverflow.com/questions/29006379)). No Apple-authored statement of the cdhash rule was found, so the mechanism is well attested but **unverified** officially.
- Fix for a stuck row: quit the app, remove the row, run `tccutil reset Accessibility <bundle id>` (scoped, never unscoped), relaunch from the same path, re-grant; sometimes a reboot is needed ([cua.ai guide](https://cua.ai/docs/how-to-guides/driver/troubleshoot-stale-macos-permissions), [OpenClaw docs](https://docs.openclaw.ai/mac/permissions)). Resets do not always clear stale rows ([Apple forums 724635](https://developer.apple.com/forums/thread/724635)). Document this in the README; the app should not run `tccutil`.
- **Signing in `build.sh`:** with Apple Development, the requirement is the bundle ID plus the leaf certificate CN **(verified locally)**, so rebuilds keep the grant (Linkguide's README already relies on this). Two risks:
  - The keychain has **two** Apple Development identities **(verified locally)**, and `build.sh` takes "the first". If the order changes, the CN changes and every TCC grant breaks. Pin the identity by SHA-1 hash (`codesign --sign <sha1>`), for example from a git-ignored `.signing-identity` file or `REFINEDSETTINGS_SIGN_IDENTITY`.
  - Apple Development certificates expire yearly. A renewed certificate normally keeps the same CN, so the requirement should still match (**unverified**).
- Developer ID gives the same stability and is what notarised distribution needs (section 7).

---

## 6. Module architecture

### Deployment target trade-offs

| | Stay on 13 | Raise to 14 | Raise to 15 |
| --- | --- | --- | --- |
| Observation | `ObservableObject`/`@Published` | `@Observable` (or keep `ObservableObject`) | same as 14 |
| Sidebar toggle removal | Introspect hack | `toolbar(removing:)` | same |
| Window title/toolbar from SwiftUI | manual | `sceneBridgingOptions` | same |
| Activation | `activate(ignoringOtherApps:)` (deprecated in 14) | `activate()` | same |
| Other | | `contentMargins`, `onChange(of:initial:)`, `openSettings` | `Window` launch behaviour, `.containerBackground(for: .window)`, `WindowDragGesture` |
| Who is excluded | nobody | Ventura Macs | Ventura and Sonoma Macs |

`@Observable` needs macOS 14; the Perception backport works on older systems but warns at runtime if a view reads state outside `WithPerceptionTracking` ([Point-Free](https://pointfree.co/blog/posts/129-perception-a-back-port-of-observable)). For a personal utility developed on 26.5, **14** is the sensible floor. If you stay on 13, `ObservableObject` is fine at this scale; do not add Perception.

### Pattern

```swift
import Foundation

enum ModuleID: String, CaseIterable, Identifiable {
    case links
    case mouseAndScrolling
    case hiddenSettings
    var id: String { rawValue }
    var enabledKey: String { "module.\(rawValue).enabled" }
}

enum AppPermission: Hashable {
    case accessibility
    case inputMonitoring
}

@MainActor
protocol AppModule: AnyObject {
    var id: ModuleID { get }
    var requiredPermissions: Set<AppPermission> { get }
    var isRunning: Bool { get }
    /// Creates taps, observers and timers. Must be idempotent.
    func start()
    /// Tears down everything `start()` created. Must be idempotent.
    func stop()
}
```

```swift
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            ModuleID.links.enabledKey: true,
            ModuleID.mouseAndScrolling.enabledKey: false,
            ModuleID.hiddenSettings.enabledKey: false,
            "general.showsMenuBarIcon": true,
        ])
    }

    var showsMenuBarIcon: Bool {
        get { defaults.bool(forKey: "general.showsMenuBarIcon") }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "general.showsMenuBarIcon")
        }
    }

    func isEnabled(_ moduleID: ModuleID) -> Bool {
        defaults.bool(forKey: moduleID.enabledKey)
    }

    func setEnabled(_ isEnabled: Bool, for moduleID: ModuleID) {
        objectWillChange.send()
        defaults.set(isEnabled, forKey: moduleID.enabledKey)
    }
}
```

```swift
import Foundation

@MainActor
final class ModuleCoordinator: ObservableObject {
    private let settings: SettingsStore
    private let accessibility: AccessibilityPermission
    private let modules: [ModuleID: any AppModule]

    init(settings: SettingsStore, accessibility: AccessibilityPermission, modules: [any AppModule]) {
        self.settings = settings
        self.accessibility = accessibility
        self.modules = Dictionary(uniqueKeysWithValues: modules.map { module in (module.id, module) })
    }

    func setEnabled(_ isEnabled: Bool, for moduleID: ModuleID) {
        settings.setEnabled(isEnabled, for: moduleID)
        let needsAccessibility = modules[moduleID]?.requiredPermissions.contains(.accessibility) ?? false
        if isEnabled && needsAccessibility && !accessibility.isGranted { accessibility.request() }

        reconcile()
    }

    /// Call on launch, after any settings change and after any permission change.
    func reconcile() {
        for (moduleID, module) in modules {
            let shouldRun = settings.isEnabled(moduleID) && isPermitted(module.requiredPermissions)

            if shouldRun && !module.isRunning {
                module.start()
            } else if !shouldRun && module.isRunning {
                module.stop()
            }
        }
    }

    private func isPermitted(_ permissions: Set<AppPermission>) -> Bool {
        guard permissions.contains(.accessibility) else { return true }

        return accessibility.isGranted
    }
}
```

Settings views: switch on `ModuleID` in the detail view (`@ViewBuilder`), so there is no `AnyView` and no view code inside modules. Each module pane shows its on/off switch at the top and, when a required permission is missing, a "Needs Accessibility" row with the grant button; the General pane lists the same switches.

### Zero work when off

- `init` stores dependencies only. No `CGEvent.tapCreate`, `Timer`, `NotificationCenter`/`NSWorkspace` observer or long-lived `Task` until `start()`.
- `stop()` disables and invalidates the tap and removes its run loop source, cancels Tasks, invalidates timers and removes observers, and sets every handle to `nil`, so `isRunning` is derived from real state.
- Event taps get disabled by the system on timeout (`.tapDisabledByTimeout`, `.tapDisabledByUserInput`); the callback must re-enable the tap. Keep the callback cheap.
- Stop Accessibility-dependent modules the moment the permission goes away (a live `.defaultTap` after revocation can block input, [Apple forums 735204](https://developer.apple.com/forums/thread/735204)).

```swift
import CoreGraphics
import Foundation

@MainActor
final class ScrollModule: AppModule {
    let id = ModuleID.mouseAndScrolling
    let requiredPermissions: Set<AppPermission> = [.accessibility]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { eventTap != nil }

    func start() {
        guard eventTap == nil else { return }

        let scrollMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollMask,
            callback: { _, eventType, event, _ in
                // Re-enable on .tapDisabledByTimeout here (needs the tap passed through userInfo).
                guard eventType == .scrollWheel else { return Unmanaged.passUnretained(event) }

                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        eventTap = newTap
        runLoopSource = source
    }

    func stop() {
        guard let eventTap else { return }

        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CFMachPortInvalidate(eventTap)
        self.eventTap = nil
        runLoopSource = nil
    }
}
```

(A sketch; not compiled here.)

### Where settings live: `@AppStorage` vs a typed store

- `@AppStorage` is fine for view-only state (selected sidebar pane, a disclosure group). It only updates views, takes stringly keys at each use site, and does not trigger `objectWillChange` inside an `ObservableObject`, so modules and the coordinator cannot rely on it.
- Use the typed `SettingsStore` above for anything a module or the coordinator reads: one place for keys and defaults, observable from both AppKit and SwiftUI, and testable with `UserDefaults(suiteName: "test-\(UUID())")`.
- Do not store state the system owns: launch at login (read `SMAppService.mainApp.status`), Accessibility (read `AXIsProcessTrusted()`), default browser (read `urlForApplication(toOpen:)`).
- Namespace keys (`general.*`, `links.*`, `module.<id>.enabled`, `migration.*`).

### Swift 6 notes

- Mark the store, coordinator, modules and permission objects `@MainActor`; AppKit and SwiftUI APIs they touch are main-actor anyway.
- Callbacks from `NotificationCenter`/`DistributedNotificationCenter` with `queue: .main` and KVO closures are not statically main-actor; wrap the body in `MainActor.assumeIsolated` as above.
- With swift-tools-version 6.2 you can set `.defaultIsolation(MainActor.self)` on the executable target (SE-0466) so unannotated code is main-actor by default ([SE-0466 thread](https://forums.swift.org/t/se-0466-control-default-actor-isolation-inference/78321)). One forum post says SwiftPM did not honour the setting at some point ([amendment thread](https://forums.swift.org/t/accepted-amendment-to-se-0466/81695/4)), so **verify** with a deliberate isolation error before relying on it, and do not use it on the library target.

---

## 7. SwiftPM-only app bundles

What works with `swift build` plus a hand-assembled bundle:

- Compiling, linking, Info.plist, `PkgInfo`, `.icns` via `iconutil` (present at `/usr/bin/iconutil`), `codesign`, `lsregister`, `ditto` (all what `build.sh` does).
- **System SF Symbols** via `NSImage(systemSymbolName:accessibilityDescription:)` and `Image(systemName:)`; no resources needed. Check each symbol's minimum OS in the SF Symbols app; a symbol newer than the running OS returns `nil`/empty.

Limits:

| Need | Status with Command Line Tools only |
| --- | --- |
| Asset catalogs (`.xcassets` to `Assets.car`), named colours, custom SF Symbols, Tahoe `.icon` | **Not possible.** `actool` and `ictool` print "requires Xcode, but active developer directory … is a command line tools instance" **(verified locally)**. Define colours in code; draw custom glyphs in code or ship PDFs. |
| String Catalogs (`.xcstrings`) | Not possible; no `xcstringstool` in the CLT **(verified locally)**. Use `en.lproj/Localizable.strings` copied by `build.sh`, or stay English-only. |
| SwiftPM `resources:` / `Bundle.module` | Avoid for the app target. The generated accessor looks for `<Package>_<Target>.bundle` at the `.app` root (which codesign rejects as unsealed content) or at a hard-coded build path, then `fatalError`s ([CodeEditSymbols#22](https://github.com/CodeEditApp/CodeEditSymbols/issues/22), [Windowpane release notes](https://github.com/jeksn/windowpane/releases/tag/v0.1.3)). Copy files into `Contents/Resources` in `build.sh` and load them with `Bundle.main`. |
| Entitlements | `codesign --entitlements RefinedSettings.entitlements`. A non-sandboxed app using AX, event taps and default-browser APIs needs none. |
| Hardened runtime | `codesign --options runtime`. Required for notarisation; notarytool rejects executables without it ([Xojo blog](https://blog.xojo.com/2024/08/22/macos-apps-from-sandboxing-to-notarization-the-basics/), [WWDC19 703 notes](https://wwdcnotes.com/notes/wwdc19/703)). Not needed for local Apple Development builds. Under the hardened runtime, sending Apple Events needs `com.apple.security.automation.apple-events`; the Safari integration uses AX, not Apple Events, so it should not. |
| Notarisation, Developer ID | Needs a Developer ID certificate. `notarytool` and `stapler` ship in the Command Line Tools too (`/Library/Developer/CommandLineTools/usr/bin`, **verified locally**), so no Xcode is needed. Only matters when sharing the app; see [distribution-and-landscape.md](distribution-and-landscape.md). |
| Debugger/Instruments UI, previews | `lldb` works in the CLT; Instruments and SwiftUI previews need Xcode. |

### App icon on Tahoe

- Tahoe uses an Icon Composer `.icon` compiled by `actool` into `Assets.car`, referenced by `CFBundleIconName`, while `CFBundleIconFile` keeps the `.icns` for older systems ([Xojo forum](https://forum.xojo.com/t/how-to-create-app-icons-for-macos-26-and-maintain-compatibility-with-older-oss/86527?page=3), [Michael Tsai, Aug 2025](https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/)). All pipelines found need Xcode's `actool`, including on CI ([Electron Packager#1831](https://github.com/electron/packager/issues/1831)).
- With only an `.icns`, Tahoe shows the legacy icon, but if it does not match the squircle shape it is shrunk (about 20 %) onto a grey squircle, the "icon jail" ([9to5Mac](https://9to5mac.com/2025/08/08/macos-tahoe-fix-gray-box-icons/), [heise](https://heise.de/-11075561)). Protruding pixels trigger it even on near-square icons ([heise](https://heise.de/-11075561)). An `.icns` that already follows Apple's template reportedly looks fine ([Xojo forum](https://forum.xojo.com/t/how-to-create-app-icons-for-macos-26-and-maintain-compatibility-with-older-oss/86527?page=3)).
- Recommendation: have `scripts/make-icon.swift` draw the tile as Apple's macOS squircle inside the standard padding of the 1024 canvas (roughly an 824 pt rounded square centred, **unverified** from memory; check Apple's macOS icon template), with nothing outside it. If you later want Tahoe's light/dark/tinted/clear variants, install Xcode once, build `Assets.car` from an `.icon`, commit it, and have `build.sh` copy it and set `CFBundleIconName` (the "commit the compiled artifact" approach, [mpv TOOLS notes](https://git.quad4.io/Mirrors/mpv/src/branch/master/TOOLS), [Michael Tsai](https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/)).

### Is an Xcode project worth it?

Not yet. The SwiftPM setup is small, reproducible and already handles signing and installation. XcodeGen or Tuist generate an `.xcodeproj` from YAML/Swift, but building it still needs Xcode installed, so they do not help a CLT-only machine. Revisit when one of these becomes a requirement: a Tahoe `.icon`, localisation with String Catalogs, a WidgetKit Control Center control (app extension), notarised distribution, or Instruments. At that point XcodeGen with a checked-in `project.yml` keeps the project file out of review noise.

---

## 8. Testing

Layout:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RefinedSettings",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RefinedSettingsCore", path: "Sources/RefinedSettingsCore"),
        .executableTarget(
            name: "RefinedSettings",
            dependencies: ["RefinedSettingsCore"],
            path: "Sources/RefinedSettings"
        ),
        .testTarget(
            name: "RefinedSettingsCoreTests",
            dependencies: ["RefinedSettingsCore"],
            path: "Tests/RefinedSettingsCoreTests"
        ),
    ]
)
```

- `RefinedSettingsCore`: settings store, migration, module coordinator, URL routing, browser catalogue ordering, Safari menu-item parsing (behind a protocol so AX is faked). No `main.swift` there.
- `RefinedSettings` (executable): `main.swift`, `AppDelegate`, windows, status item, concrete modules that touch AX/event taps.
- Use the `package` access modifier (Swift 5.9+) for symbols the executable needs from the library. It crosses module boundaries within one package without making anything `public`.
- SwiftPM test targets can also depend on an executable target and `@testable import` it (Swift 5.5+), but the library split keeps tests independent of AppKit start-up.

Swift Testing with only the Command Line Tools:

- `Testing.framework` (plus `_Testing_AppKit`, `_Testing_Foundation` and others) is in `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, and there is no `XCTest.framework` in the CLT, only legacy `libswiftXCTest.dylib`s **(verified locally)**. So write Swift Testing tests; XCTest tests will not run.
- The 2024 "no such module 'Testing'" failure with the CLT came from a SwiftPM search-path bug ([Swift Forums](https://forums.swift.org/t/error-no-such-module-testing/74784)); the fix (swift-package-manager PR #7840) merged to `main` on 2024-08-05 (checked via the GitHub API), so it is in the Swift 6.1+ toolchains and in this 6.3.3. Running `swift test` was **not** tried here (the brief allowed writing only this file); the first `swift test` will confirm it.

```swift
import Foundation
import Testing
@testable import RefinedSettingsCore

struct LinkguideMigrationTests {
    @Test func copiesLegacyKeysOnceWithoutOverwriting() throws {
        let suiteName = "refinedsettings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["com.apple.Safari"], forKey: "links.entryOrder")

        LinkguideMigration.migrate(
            legacyValues: ["entryOrder": ["org.mozilla.firefox"], "hiddenEntryIDs": ["com.google.Chrome"]],
            into: defaults
        )

        #expect(defaults.stringArray(forKey: "links.entryOrder") == ["com.apple.Safari"])
        #expect(defaults.stringArray(forKey: "links.hiddenEntryIDs") == ["com.google.Chrome"])
        #expect(defaults.bool(forKey: LinkguideMigration.completedKey))
    }
}
```

If the store and coordinator are `@MainActor`, mark those tests `@MainActor` too. Fake modules (a class recording `start()`/`stop()` calls) make the coordinator's reconcile rules easy to test: off means never started, on without permission means not started, revocation stops.

---

## Sources

Apple documentation and SDK

- [SwiftUI `OpenSettingsAction`](https://developer.apple.com/documentation/swiftui/opensettingsaction)
- [SwiftUI `toolbar(removing:)`](https://developer.apple.com/documentation/swiftui/view/toolbar(removing:))
- [SwiftUI `NSHostingController.sceneBridgingOptions`](https://developer.apple.com/documentation/swiftui/nshostingcontroller/scenebridgingoptions)
- [SwiftUI `backgroundExtensionEffect()`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect())
- [AppKit `NSStatusItem.isVisible`](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible), [`removalAllowed`](https://developer.apple.com/documentation/appkit/nsstatusitem/behavior-swift.struct/removalallowed)
- [AppKit `NSApplication.activate()`](https://developer.apple.com/documentation/appkit/nsapplication/activate())
- [AppKit `moveToActiveSpace`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace)
- [AppKit `setDefaultApplication(at:toOpenURLsWithScheme:completion:)`](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:))
- [ServiceManagement `register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register()), [`requiresApproval`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval), [`notFound`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/notfound)
- [Foundation `UserDefaults.init(suiteName:)`](https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:))
- macOS 26.5 SDK headers `SMAppService.h` and `NSStatusItem.h` in `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` (read locally)

Apple Developer Forums

- [739831: Opening SwiftUI Settings from AppKit](https://developer.apple.com/forums/thread/739831)
- [788101: Can I determine if the user disallowed my menubar item? (Quinn, DTS)](https://developer.apple.com/forums/thread/788101)
- [777520: SMAppService, how does this work? (Quinn, DTS)](https://developer.apple.com/forums/thread/777520)
- [828052](https://developer.apple.com/forums/thread/828052), [122492](https://developer.apple.com/forums/thread/122492), [707680](https://developer.apple.com/forums/thread/707680): Input Monitoring vs Accessibility (DTS)
- [735204: app hangs if accessibility changed while using CGEventTap](https://developer.apple.com/forums/thread/735204)
- [724635: tccutil reset doesn't remove items](https://developer.apple.com/forums/thread/724635)
- [727968: NavigationSplitView hide sidebar toggle](https://developer.apple.com/forums/thread/727968)
- [801087: Tahoe sidebar cut off in full screen](https://developer.apple.com/forums/thread/801087)
- [832543: UIDesignRequiresCompatibility removal](https://developer.apple.com/forums/thread/832543)
- [836113: NSStatusItem issues](https://developer.apple.com/forums/thread/836113)
- [Platskies replies on background items and sfltool](https://developer.apple.com/forums/profile/Platskies/replies)

WWDC

- [WWDC25 323 Build a SwiftUI app with the new design (notes)](https://wwdcnotes.com/documentation/wwdc25-323-build-a-swiftui-app-with-the-new-design/)
- [WWDC19 703 All About Notarization (notes)](https://wwdcnotes.com/notes/wwdc19/703)

Open-source apps (read via GitHub)

- Ice: [`IceApp.swift`, `AppDelegate.swift`](https://github.com/jordanbaird/Ice/tree/main/Ice/Main), [`SettingsView.swift`, `SettingsWindow.swift`](https://github.com/jordanbaird/Ice/tree/main/Ice/Settings), [`Permission.swift`](https://github.com/jordanbaird/Ice/blob/main/Ice/Permissions/Permission.swift)
- Rectangle: [`AppDelegate.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AppDelegate.swift), [`RectangleStatusItem.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/General/RectangleStatusItem.swift), [`SettingsWindowController.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/SettingsWindow/SettingsWindowController.swift), [`AccessibilityView.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityAuthorization/AccessibilityView.swift)
- Stats: [`AppDelegate.swift`](https://github.com/exelban/stats/blob/master/Stats/AppDelegate.swift)
- Maccy: [`AppDelegate.swift`](https://github.com/p0deje/Maccy/blob/master/Maccy/AppDelegate.swift)
- LinearMouse: [`AccessibilityPermission.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/AccessibilityPermission.swift)
- FineTune: [`AccessibilityPermissionService.swift`](https://github.com/ronitsingh10/FineTune/blob/main/FineTune/Coordination/AccessibilityPermissionService.swift)
- MonitorControl, Hammerspoon, Shifty: `com.apple.accessibility.api` observers (GitHub code search)
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) and [its source](https://github.com/sindresorhus/LaunchAtLogin-Modern/blob/main/Sources/LaunchAtLogin/LaunchAtLogin.swift); [LaunchAtLogin#100](https://github.com/sindresorhus/LaunchAtLogin/issues/100)
- [orchetect/SettingsAccess](https://github.com/orchetect/SettingsAccess), [orchetect/MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess)
- [Chromium `shell_integration_mac.mm`](https://chromium.googlesource.com/chromium/src/+/711ab9bc/chrome/browser/shell_integration_mac.mm)
- [swift-package-manager PR #7840](https://github.com/swiftlang/swift-package-manager/pull/7840)

Blogs, forums and guides

- [Peter Steinberger: Showing Settings from macOS menu bar items (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/)
- [sspai on SettingsLink](https://sspai.com/post/105243), [Hacking with Swift forum 26267](https://www.hackingwithswift.com/forums/macos/how-to-open-settings-from-menu-bar-app-and-show-app-icon-in-dock/26267)
- [Full-height sidebar window write-up (2024)](https://websnapshot.pages.dev/html/readit.site_a_tWcdh_macos-full-height-sidebar-window-62a214309a80.html)
- [macos-settings-ui skill](https://skills.cat/skills/fayazara/macos-app-skills/macos-settings-ui), [Medium: macOS app settings](https://medium.com/@schopenlaam/macos-app-settings-9ee3f8d50e57) (not fetchable)
- [SettingsIconGenerator](https://swiftpackageregistry.com/sparrowcode/SettingsIconGenerator), [BadgeIcon](https://github.com/danielsaidi/BadgeIcon)
- [Reddit: NavigationSplitView collapse on macOS 26](https://www.reddit.com/r/SwiftUI/comments/1leisfx/)
- [4D blog on Tahoe](https://blog.4d.com/?p=69113)
- [MacStories macOS 26 review](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3), [TechRadar menu bar](https://www.techradar.com/computing/mac-os/what-is-the-macos-menu-bar-heres-how-new-macbook-neo-users-can-get-the-most-out-of-apples-app-control-bar), [consomac](https://consomac.fr/news-21397-macos-tahoe-26-controle-l-acces-des-applications-a-la-barre-de-menus.html), [Apple Community 256145886](https://discussions.apple.com/thread/256145886), [Parallels forum](https://forum.parallels.com/threads/asking-how-to-keep-toolbox-icon-on-menu-bar.369594/)
- [electron#42154 status item position](https://github.com/electron/electron/issues/42154)
- [TCC cdhash trap](https://nickboy-github-io.pages.dev/posts/tcc-cdhash-trap/), [skhd.zig CODE_SIGNING.md](https://raw.githubusercontent.com/jackielii/skhd.zig/main/docs/CODE_SIGNING.md), [Stack Overflow 29006379](https://stackoverflow.com/questions/29006379), [cua.ai stale permissions](https://cua.ai/docs/how-to-guides/driver/troubleshoot-stale-macos-permissions), [OpenClaw permissions](https://docs.openclaw.ai/mac/permissions)
- [lan-mouse macos_privacy.rs](https://docs.rs/crate/lan-mouse-gtk/0.3.0/source/src/macos_privacy.rs), [PermissionFlow destinations](https://docs.rs/crate/permission-flow/latest/source/PermissionFlow/Sources/SystemSettingsKit/SystemSettingsDestination.swift), [CopilotForXcode#53](https://github.com/intitni/copilotforxcode/issues/53)
- [Eclectic Light: Controlling LaunchServices in Sequoia](https://eclecticlight.co/2025/03/27/controlling-launchservices-in-macos-sequoia/), [engineered.at: LaunchServices and Spotlight](https://engineered.at/articles/launchservices-and-spotlight)
- [Point-Free: Perception](https://pointfree.co/blog/posts/129-perception-a-back-port-of-observable)
- [SE-0466 review thread](https://forums.swift.org/t/se-0466-control-default-actor-isolation-inference/78321), [SE-0466 amendment](https://forums.swift.org/t/accepted-amendment-to-se-0466/81695/4)
- [Swift Forums: no such module 'Testing'](https://forums.swift.org/t/error-no-such-module-testing/74784)
- [CodeEditSymbols#22](https://github.com/CodeEditApp/CodeEditSymbols/issues/22), [Windowpane v0.1.3](https://github.com/jeksn/windowpane/releases/tag/v0.1.3)
- [Xojo: sandboxing to notarization](https://blog.xojo.com/2024/08/22/macos-apps-from-sandboxing-to-notarization-the-basics/)
- [Xojo forum: macOS 26 icons](https://forum.xojo.com/t/how-to-create-app-icons-for-macos-26-and-maintain-compatibility-with-older-oss/86527?page=3), [Michael Tsai: separate icons for Tahoe](https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/), [mpv TOOLS](https://git.quad4.io/Mirrors/mpv/src/branch/master/TOOLS), [Electron Packager#1831](https://github.com/electron/packager/issues/1831), [9to5Mac grey box icons](https://9to5mac.com/2025/08/08/macos-tahoe-fix-gray-box-icons/), [heise: squircle prison](https://heise.de/-11075561)

Local, read-only checks on the developer machine (2026-11-08)

- `swift --version`: Swift 6.3.3, target `arm64-apple-macosx26.0`; SDKs include `MacOSX26.5.sdk`; `xcode-select -p` is `/Library/Developer/CommandLineTools`.
- `actool --version` and `ictool --version`: "requires Xcode".
- `Testing.framework` present in the CLT; no `XCTest.framework`; no `xcstringstool`.
- `codesign -d -r- /Applications/Linkguide.app`: requirement pins `identifier "com.ikraam.linkguide"` and the Apple Development leaf CN.
- `security find-identity -v -p codesigning`: two Apple Development identities.
- `defaults read com.ikraam.linkguide`: only `entryOrder`, `hiddenEntryIDs`, `safariProfileNames`; no Linkguide folder in Application Support.
