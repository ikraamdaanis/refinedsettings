# Refined Settings design docs

Research and best practices for turning Linkguide into **Refined Settings**, a native menu bar app that combines small system tweaks ("Refined Settings for Mac"). Researched on 2026-11-08 on the developer Mac: macOS 26.5.2 Tahoe, Apple Silicon, Swift 6.3.3 from the Command Line Tools (no Xcode).

**macOS 27 shipped in September 2026.** The developer Mac is still on 26.5, but users will be on 27, so every module needs testing there too. One known difference: on macOS 27 the Accessibility pane is called "Device Control and Data Access" ([mouse-and-scrolling.md, section 4.1](mouse-and-scrolling.md#41-which-tcc-service)).

The research came from Apple's documentation and SDK headers, Apple Developer Forums (mostly DTS answers), the source code and issue trackers of open-source apps (LinearMouse, Scroll Reverser, Mos, Ice, Rectangle, Stats and others), and read-only checks on the developer Mac. Nothing on the Mac was changed while researching. Throughout the docs, **unverified** marks a claim that rests on one weak source, on memory, or that could not be tested without changing the system.

## Documents

| Document | Covers |
|---|---|
| [architecture.md](architecture.md) | Settings window with a sidebar, menu bar item, launch at login, migrating Linkguide's settings, Accessibility onboarding, module pattern, deployment target, limits of a SwiftPM-only build, testing |
| [mouse-and-scrolling.md](mouse-and-scrolling.md) | How LinearMouse and other tools build their event taps, telling a mouse from a trackpad, reversing and linear scrolling, side buttons, pointer acceleration and speed, permissions, Swift 6 callback shape, OS changes, licences, a proposed architecture and 28 edge cases to test |
| [hidden-settings-dock-finder-screenshots.md](hidden-settings-dock-finder-screenshots.md) | Every Dock, Mission Control, Finder and screenshot key in the plan: domain, type, default, UI, what applies it, version status. Relaunching Dock, Finder and SystemUIServer safely. Reset rules. v2 candidates and keys to avoid |
| [hidden-settings-global-and-api.md](hidden-settings-global-and-api.md) | Keyboard, typing, window and dialog keys in the global domain. How to read and write preferences from Swift (CFPreferences), live updates, managed preferences, a data-driven `Tweak` model, and tracking "needs log out / reopen apps" state |
| [distribution-and-landscape.md](distribution-and-landscape.md) | Apple trademark rules for the name, tagline and icon. Developer ID signing, notarization, Sparkle updates, Homebrew. Why not the Mac App Store. Competing apps per module, how Velja and Finicky do link rules, tracking-parameter lists, privacy text, licensing |

## Decisions and changes to the plan

These are the findings that change or sharpen the plan. Each links to the evidence.

### Whole app

1. **Keep the AppKit-managed Settings window** and put a SwiftUI `NavigationSplitView` in it. The SwiftUI `Settings` scene is unreliable in a menu bar app (`showSettingsWindow:` stopped working in macOS 14, `openSettings` is reported broken on 26). Linkguide's `SettingsWindowController` already handles activation and Spaces correctly. Building against the 26 SDK gives the Liquid Glass sidebar on Tahoe for free. See [architecture.md, section 1](architecture.md#1-settings-window-with-a-sidebar-macos-13).
2. **Consider raising the deployment target from macOS 13 to 14.** It brings `@Observable`, `toolbar(removing: .sidebarToggle)`, window titles and toolbars driven from SwiftUI, and `NSApp.activate()`, and removes most `#available` branches. This is a decision for you; the docs work either way (the mouse design uses `OSAllocatedUnfairLock`, which is available on 13). See [architecture.md, section 6](architecture.md#deployment-target-trade-offs).
3. **Two modules need Accessibility, not one.** The plan says to ask for it only when Mouse & Scrolling is switched on, but Links already uses it to open links in a Safari profile. Ask when a module that needs it is switched on (or when Safari profiles are in use), never at launch. Track it as `requiredPermissions` per module. See [architecture.md, section 5](architecture.md#5-permissions-ux).
4. **Pin the signing identity in `build.sh`.** This Mac has two Apple Development identities, and `build.sh` takes whichever `security find-identity` lists first. TCC ties the Accessibility grant to the certificate's name, so if the order ever changes, the grant silently stops working. Pin it by SHA-1 (for example through `REFINEDSETTINGS_SIGN_IDENTITY`). Ad-hoc builds lose the grant on every rebuild while System Settings still shows it switched on. See [architecture.md, section 5](architecture.md#toggle-is-on-but-still-not-trusted-after-a-rebuild).
5. **Migrate three keys, not two.** Linkguide also stores `safariProfileNames`. Read the old values with `UserDefaults.standard.persistentDomain(forName: "com.ikraam.linkguide")`, not `UserDefaults(suiteName:)`, which can hand back the new app's registered defaults. Copy only keys the new app doesn't have yet, then set a "migrated" flag. Accessibility, the default-browser choice and Tahoe's "Allow in the Menu Bar" entry do not carry over; the user re-grants them, and should delete `Linkguide.app` so it stops claiming http and https. See [architecture.md, section 4](architecture.md#4-migration-from-comikraamlinkguide).
6. **Decide what Links does when switched off.** macOS keeps sending links to the default browser whatever the module state. Recommended: forward every link straight to a fallback browser chosen in the Links pane. See [architecture.md, section 4](architecture.md#url-handling-to-keep).
7. **"Show menu bar icon" off needs a way back in.** Opening the app again from Finder or Spotlight should open Settings (Linkguide already does this in `applicationShouldHandleReopen`), and a cold launch with the icon hidden should too. On Tahoe users can also hide the icon in System Settings, and apps can't read that switch. See [architecture.md, section 2](architecture.md#2-menu-bar).
8. **Launch at login:** use `SMAppService.mainApp`, read `status` every time instead of storing a bool, and handle `.requiresApproval`. Only register the copy in `/Applications`, signed with the stable identity. See [architecture.md, section 3](architecture.md#3-launch-at-login).
9. **Split the package** into a `RefinedSettingsCore` library and a thin executable so logic is testable, and use Swift Testing: its framework ships with the Command Line Tools, XCTest's doesn't. See [architecture.md, section 8](architecture.md#8-testing).

### Hidden Settings

10. **Read and write with `CFPreferencesCopyValue` / `CFPreferencesSetValue` / `CFPreferencesSynchronize`** (current user, any host). Not the `App` variants with `kCFPreferencesAnyApplication` (they leak AppKit's built-in defaults, so an unset key looks set), not `UserDefaults(suiteName: NSGlobalDomain)` (an error), and never by editing plist files (cfprefsd overwrites them). See [hidden-settings-global-and-api.md, section 3](hidden-settings-global-and-api.md#3-reading-and-writing-from-swift).
11. **Reset means deleting the key**, never writing the presumed default. For example, writing "Screenshot" as the screenshot name would break other languages. For keys that System Settings or Finder also exposes, a reset also undoes the user's own choice there, so label it "Reset to macOS default". See [hidden-settings-dock-finder-screenshots.md, section 6](hidden-settings-dock-finder-screenshots.md#6-reset-semantics-delete-vs-write-default).
12. **Relaunch by exact PID, never by name.** Dock, Finder and SystemUIServer are launchd agents that restart only after an *unsuccessful* exit (`KeepAlive.SuccessfulExit = false`, checked in `/System/Library/LaunchAgents`). So send `SIGTERM` to the PID from `NSRunningApplication.runningApplications(withBundleIdentifier:)`; a clean `terminate()` would leave the Dock gone. Finder can quit cleanly and be reopened with `NSWorkspace`. Warn that relaunching Finder stops copies in progress. Batch changes into one relaunch. See [hidden-settings-dock-finder-screenshots.md, section 4](hidden-settings-dock-finder-screenshots.md#4-applying-changes-relaunching-dock-finder-systemuiserver).
13. **Screenshot settings probably need no SystemUIServer restart** on current macOS: the screenshot UI starts fresh for each capture. Test `location` on 13, 26 and 27 before dropping the restart. The ⌘⇧5 toolbar writes to the same domain, so always read values fresh, and read `target` with `location` (if the user picked Clipboard, changing the folder does nothing).
14. **Track pending state properly.** "Needs log out" is cleared when the login session ID changes. "Reopen apps" compares each running app's launch date with the time of the change, so the UI can say "Reopen Safari, Mail and 3 others" instead of a vague warning. See [hidden-settings-global-and-api.md, section 4.4](hidden-settings-global-and-api.md#44-pending-needs-reopen--log-out-state).

### Mouse & Scrolling

15. **One active tap at the HID level on its own thread**, for scroll and other-mouse down/up only. The C callback is a file-scope function with no captures; settings cross threads in an `OSAllocatedUnfairLock`. See [mouse-and-scrolling.md, sections 1 and 5](mouse-and-scrolling.md#5-swift-6-strict-concurrency-and-performance-question-4).
16. **Identify the device per event** from the event's embedded IOHIDEvent sender ID (private SPI that LinearMouse, Scroll Reverser and Mac Mouse Fix all use), not from scroll phases. The Magic Mouse sends trackpad-like events but is a mouse. The sender ID changes on every reconnect, so v2 per-device settings must key on vendor, product and serial.
17. **Reversing must negate four values**, including the embedded IOHIDEvent's ScrollX/Y, or momentum "snaps back" in Safari and every WebKit view.
18. **Back/forward:** post ⌘[ / ⌘] and swallow the button down and up. Offer pass-through for apps that already handle buttons 4 and 5 (Chromium browsers, VS Code, where ⌘[ means outdent). Synthesized swipe gestures, the alternative, broke on macOS 27.
19. **Pointer acceleration and speed** are per-device HID properties (`HIDUseLinearScalingMouseAcceleration` on 14+, acceleration `-1` on 13). Restore the originals when the module stops. Apple trackpads and the Magic Mouse ignore speed changes on Sequoia and later.
20. **Revoking Accessibility while an active tap runs can freeze all input system-wide** (Apple bug FB24619068, Sequoia through 27). Add LinearMouse's watchdog (a probe tap every 10 seconds plus `IOHIDCheckAccess`) and tear the tap down the moment access is gone. See [mouse-and-scrolling.md, section 4.4](mouse-and-scrolling.md#44-what-happens-to-an-existing-tap-on-revocation).
21. **Only copy code from LinearMouse (MIT) and Scroll Reverser (Apache-2.0).** Mos (CC BY-NC), Mac Mouse Fix (its own licence), UnnaturalScrollWheels (GPL-3.0) and SensibleSideButtons (GPL-2.0) are for learning only. Keep LinearMouse's notice in a `ThirdPartyNotices/` folder and an Acknowledgements view, and write our own declarations for the private IOKit functions instead of copying LinearMouse's Apple-licensed header. See [mouse-and-scrolling.md, section 8](mouse-and-scrolling.md#8-licence-obligations-question-7).

### Name, icon and distribution

22. **"Refined Settings" with the tagline "Refined Settings for Mac" fits Apple's trademark rules**, as long as "for Mac" is smaller than the name. Add "Mac and macOS are trademarks of Apple Inc." to the About window and any website. See [distribution-and-landscape.md, section 1](distribution-and-landscape.md#1-apple-trademark-rules).
23. **Redraw the icon.** A silver gear on a slate tile is close to the System Settings icon, which Apple's guidelines (no imitating its logos or trade dress) argue against. Separately, Tahoe shrinks icons that don't fill its rounded-square shape onto a grey plate, so `scripts/make-icon.swift` should draw on Apple's icon grid. See [architecture.md, section 7](architecture.md#app-icon-on-tahoe).
24. **Distribute outside the Mac App Store** with Developer ID, the hardened runtime and notarization; all of it works with the Command Line Tools (`notarytool` and `stapler` are installed). The sandbox rules out active event taps and writing other apps' preferences. Use Sparkle 2.10.1 for updates and start with a personal Homebrew tap. The Apple Developer Program costs 99 USD a year. See [distribution-and-landscape.md, sections 2 to 4](distribution-and-landscape.md#2-distribution-outside-the-app-store).

## Hidden Settings v1 at a glance

Every key from the plan, with what the research found. Details, defaults and sources are in the two Hidden Settings documents.

| Group | Key | Verdict | Applies after |
|---|---|---|---|
| Dock | `autohide-delay`, `autohide-time-modifier` | Ship. Only matter while the Dock hides automatically | Restart Dock |
| Dock | `show-recents` | Ship. Also in System Settings > Desktop & Dock | Restart Dock |
| Dock | `static-only` | **Risky.** A Tahoe 26.2 report says turning it back off didn't restore the Dock. Snapshot `persistent-apps` first, or leave it for v2 | Restart Dock |
| Dock | `showhidden` | Ship. Not yet confirmed on 26 | Restart Dock |
| Finder | `AppleShowAllFiles`, `ShowPathbar`, `ShowStatusBar`, `_FXShowPosixPathInTitle`, `FXEnableExtensionChangeWarning`, `_FXSortFoldersFirst` | Ship. Several are also in Finder's own menus and settings, so read them back | Restart Finder |
| Finder | `AppleShowAllExtensions` | Ship. Lives in the **global** domain; reset deletes it from both the global and Finder domains | Restart Finder; reopen apps for their open and save panels |
| Finder | `DSDontWriteNetworkStores` (`com.apple.desktopservices`) | Ship. Documented by Apple | **Log out** |
| Screenshots | `location`, `type`, `name`, `disable-shadow`, `show-thumbnail` | Ship. Read `target` with `location`; offer png, jpg, heic, pdf and tiff; reset `name` by deleting it | Next screenshot (test `location`) |
| Keyboard | `KeyRepeat`, `InitialKeyRepeat` | Ship. Don't show milliseconds: the units are disputed | **Log out** (System Settings applies instantly by also writing to the HID system; doing the same is untested) |
| Keyboard | `ApplePressAndHoldEnabled` | Ship. Apps that saved their own value ignore the global one | Reopen apps |
| Typing | `NSAutomaticSpellingCorrectionEnabled`, `NSAutomaticQuoteSubstitutionEnabled`, `NSAutomaticDashSubstitutionEnabled` | Ship. System Settings has one switch for quotes and dashes, so splitting them is a real extra. Add `WebAutomaticSpellingCorrectionEnabled` so Safari and Mail follow | Reopen apps |
| Windows | `NSWindowResizeTime` | Low impact: only affects old-style animated resizes. Ship with honest wording or drop | Reopen apps |
| Windows | `NSAutomaticWindowAnimationsEnabled` | Ship. Effect on 26 unconfirmed | Reopen apps |
| Windows | `NSWindowShouldDragOnGesture` | Ship. Confirmed on 15.3; test on 26 and 27. ⌃⌘-click can also open context menus in Electron apps | Reopen apps (log out to be sure) |
| Dialogs | `NSNavPanelExpandedStateForSaveMode` | Ship as "default for apps that haven't remembered their own choice": each app stores its own value, which wins | Reopen apps |
| Dialogs | `NSNavPanelExpandedStateForSaveMode2` | **Drop.** Gone from macOS 26 | |
| Dialogs | `PMPrintingExpandedStateForPrint`, `PMPrintingExpandedStateForPrint2` | **Drop.** The print dialog has had no collapsed mode since Ventura | |
| Dialogs | `NSDocumentSaveNewDocumentsToCloud` | Ship. Only affects document-based apps with iCloud Drive on | Reopen apps |
| Spaces | `mru-spaces`, `expose-group-apps` | Ship. Both are in System Settings > Desktop & Dock > Mission Control. Don't use the old `expose-group-by-app` | Restart Dock |

## Check by hand before shipping

These came up as unverified and can only be settled by changing settings on a real Mac (ideally on 13 or 14, 26 and 27):

- The values System Settings writes for each stop of the Key repeat and Delay until repeat sliders (step the slider, run `defaults read -g KeyRepeat`).
- Whether a new screenshot `location` applies without restarting SystemUIServer.
- Whether `static-only` can be switched back off cleanly on 26 and 27.
- `showhidden`, `NSAutomaticWindowAnimationsEnabled` and `NSWindowShouldDragOnGesture` on 26 and 27.
- Whether quitting Finder with `terminate()` triggers an Automation prompt.
- Whether the public "simple" HID event system client is allowed to set pointer properties, or the private client is needed.
- Whether pointer speed still applies on macOS 13 once acceleration is set to `-1`.
- Whether the `x-apple.systempreferences:` link to the Accessibility pane opens the right place on each supported version.
- Whether `SMAppService.mainApp.register()` misbehaves for a copy outside `/Applications`.

## Mapping to the order of work

1. **Rename and migrate:** [architecture.md, section 4](architecture.md#4-migration-from-comikraamlinkguide), plus pinning the signing identity (section 5) and the trademark checklist ([distribution-and-landscape.md, section 1](distribution-and-landscape.md#checklist)).
2. **Sidebar window and module switches:** [architecture.md, sections 1, 2, 3 and 6](architecture.md#1-settings-window-with-a-sidebar-macos-13).
3. **Hidden Settings:** the table above, then both Hidden Settings documents, starting with the `Tweak` model in [hidden-settings-global-and-api.md, section 4](hidden-settings-global-and-api.md#4-recommended-design).
4. **Mouse & Scrolling:** [mouse-and-scrolling.md, section 9](mouse-and-scrolling.md#9-recommended-architecture) for the design and section 10 for the test list.
