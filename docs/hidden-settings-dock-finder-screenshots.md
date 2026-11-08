# Hidden Settings research: Dock, Mission Control, Finder, Screenshots

Research for Refined Settings (macOS 13+ deployment target, dev machine macOS 26.5.2 Tahoe, build 25F84, Apple Silicon). Researched 2026-11-08.

How claims were checked:

- **Web sources**: macos-defaults.com source repo (`yannbertrand/macos-defaults`, last commit 2026-07-03), mathiasbynens/dotfiles `.macos` (the file was last changed in 2020, so it is stale), ss64, Apple Support, Apple Developer docs, Apple Community threads and GitHub issues from 2023 to 2026.
- **Local, read-only checks on this Mac**:
  - `defaults read` / `defaults read-type` for current values.
  - `launchctl list` / `launchctl print` and the launchd plists in `/System/Library/LaunchAgents`.
  - `strings` on the macOS 26.5 Dock, Finder, screencaptureui and System Settings (DesktopSettings.appex) binaries, plus a byte search of the arm64e dyld shared cache, to see whether each key name still appears in shipping code.
- **Limits of the binary check**: when a key name is found, some code on 26.5 still references it. When it is not found, that is only a hint, because Swift stores strings of 15 bytes or fewer inline in instructions where `strings` cannot see them. So a missing short key (`showhidden`, `mru-spaces`, `show-thumbnail`) proves nothing. A missing long key (`expose-animation-duration`, `DSDontWriteUSBStores`) is a meaningful signal.
- Nothing was written, deleted or restarted.

Legend: **unverified** = I could not confirm it from a source or local evidence. "macos-defaults tested on" lists the versions that site's page claims were tested. Only one page on the whole site (`_FXEnableColumnAutoSizing`) lists Tahoe, so Tahoe support below rests on local binary evidence, not on someone's test.

---

## 1. Dock (`com.apple.dock`)

| Key | Type | Default (unset means) | UI | Applies after | System Settings exposes it? | Notes |
|---|---|---|---|---|---|---|
| `autohide-delay` | float (seconds) | 0.2 s per macos-defaults [1]; some guides say 0.5 (**unverified**) | Slider 0 to 2 s, step 0.05, plus "Instant" preset (0) | `killall Dock` | No | Only matters when `autohide` = true [1]. Key present in Dock binary on 26.5. macos-defaults tested Mojave to Sequoia. Old Big Sur reports said it had no effect on some M1 Macs [9]; no Tahoe breakage reports found. |
| `autohide-time-modifier` | float | 0.5 per macos-defaults [2] | Slider 0 to 2, step 0.05 (0 = no animation) | `killall Dock` | No | Requires `autohide` = true. Present in Dock binary on 26.5. Tested Mojave to Sequoia [2]. |
| `show-recents` | bool | true | Toggle | `killall Dock` | Yes: System Settings > Desktop & Dock > Dock > "Show suggested and recent apps in Dock" (that is the 26.x label, from the DesktopSettings strings; older versions say "Show recent applications in Dock") | Present in Dock and Settings binaries. Turning it off does not hide running apps that are not pinned; they still show until quit. People report that as a bug, but it is how the Dock works [13]. |
| `static-only` | bool | false | Toggle with a strong warning, or leave out of v1 | `killall Dock` | No | **Risky.** Hides every pinned app; only running apps show. macos-defaults warns "this command empties your Dock" [3][4]. Its broken.md lists it under "not sure" [5]. A Feb 2026 Apple Community thread on Tahoe 26.2 says setting it back to false did not bring the full Dock back [12]. Replies disagree: some say it is one-way on recent 26 builds, the top reply says false just restores normal behaviour and you re-pin apps, or run `defaults delete com.apple.dock; killall Dock` to reset everything. Unresolved. If we ship it, snapshot `persistent-apps` and `persistent-others` before enabling. |
| `showhidden` | bool | false | Toggle ("Dim icons of hidden apps") | `killall Dock` | No | In dotfiles [6]. Not on macos-defaults. The name is too short for the `strings` check, so 26.5 support is **unverified** (no breakage reports found either). |
| `mru-spaces` | bool | true | Toggle (inverted label: "Keep Spaces in fixed order") | `killall Dock` | Yes: Desktop & Dock > Mission Control > "Automatically rearrange Spaces based on most recent use" | Tested Mojave to Sequoia [7]. System Settings writes it explicitly (it is `0` on this Mac). |
| `expose-group-apps` | bool | false | Toggle | `killall Dock` | Yes: Desktop & Dock > Mission Control > "Group windows by application" | **Confirmed in `com.apple.dock`**: the string is in the 26.5 Dock binary, and the Settings binary has a matching `groupWindowsByApplication` label. macos-defaults maps it to that toggle [8] (tested Big Sur, Ventura, Sonoma). The older key `expose-group-by-app` (still in dotfiles [6]) is gone from the 26.5 Dock binary and shared cache, so do not use it. |

Tahoe Dock caveats: Apple Community threads report the Dock disappearing or auto-hiding on its own on 26.0 and 26.1, fixed in 26.1 or 26.2 by some accounts [14]. These are not caused by these keys, but users may blame our app. Mention `killall Dock` / reset in support docs.

## 2. Finder (`com.apple.finder` unless noted)

| Key | Domain | Type | Default | UI | Applies after | Exposed in UI? | Notes |
|---|---|---|---|---|---|---|---|
| `AppleShowAllFiles` | com.apple.finder | bool | false | Toggle | `killall Finder` | Shortcut only: ⌘⇧. in Finder (macos-defaults [15]). No menu item or setting. | Present in Finder binary. Tested Catalina to Sonoma [15]. `NSGlobalDomain AppleShowAllFiles` is a different thing: open/save panels in every app. Whether ⌘⇧. writes the key persistently is **unverified**, so always read back. |
| `ShowPathbar` | com.apple.finder | bool | false | Toggle | `killall Finder` | Yes: Finder View menu > Show Path Bar (⌥⌘P) | Set to 1 on this Mac. Tested Big Sur to Sonoma [16]. |
| `ShowStatusBar` | com.apple.finder | bool | false | Toggle | `killall Finder` | Yes: Finder View menu > Show Status Bar (⌘/) | Set to 1 on this Mac. Tested Sequoia [17]. |
| `_FXShowPosixPathInTitle` | com.apple.finder | bool | false | Toggle | `killall Finder` | No | Present in the 26.5 Finder binary. In dotfiles [6]. How it looks in the Tahoe toolbar title is **unverified** (no Tahoe test found). |
| `AppleShowAllExtensions` | **NSGlobalDomain** (confirmed) | bool | false | Toggle | `killall Finder`; other apps' open/save panels pick it up when relaunched | Yes: Finder > Settings > Advanced > "Show all filename extensions" | macos-defaults and dotfiles both write NSGlobalDomain [18][6]. On this Mac it is set in NSGlobalDomain (1) and unset in com.apple.finder. A value in `com.apple.finder` would override the global one for Finder only, so reset should delete both. |
| `FXEnableExtensionChangeWarning` | com.apple.finder | bool | true | Toggle (inverted: "Don't warn when changing extensions") | `killall Finder` | Yes: Finder > Settings > Advanced > "Show warning before changing an extension" (label confirmed in Finder's PreferencesWindow.nib) | Tested Mojave to Sonoma [19]. |
| `_FXSortFoldersFirst` | com.apple.finder | bool | false | Toggle | `killall Finder` | Yes: Finder > Settings > Advanced > "Keep folders on top: In windows when sorting by name" | Tested Big Sur to Sonoma [20]. |
| `_FXSortFoldersFirstOnDesktop` | com.apple.finder | bool | false | Toggle | `killall Finder` | Yes: Finder > Settings > Advanced > "Keep folders on top: On Desktop" (string confirmed in 26.5 Finder) | macos-defaults lists it under **broken** [5] (page tested Big Sur to Ventura [21]). The key is still in the 26.5 Finder binary. Whether writing it from outside works on 14+ is **unverified**. Because Finder Settings has a checkbox for it, consider skipping it, or just mirroring it. |
| `DSDontWriteNetworkStores` | com.apple.desktopservices | bool | false | Toggle | **Log out and back in** (Apple [10]) | No | Apple documents it in "Adjust SMB browsing behavior in macOS" [10]. It stops .DS_Store files being written to (and, per Apple, read from) SMB shares. It does not remove existing files. The key is present in the 26.5 shared cache (DesktopServicesPriv). Apple turns it off by writing `-bool FALSE`; delete does the same. |
| `DSDontWriteUSBStores` | com.apple.desktopservices | bool | false | Toggle, or leave out | Log out | No | In dotfiles [6] and many blog guides that claim it works through Sequoia (**unverified**, low-quality sources). **Warning from local evidence**: the string `DSDontWriteUSBStores` appears nowhere in the 26.5 arm64e dyld shared cache or the Finder binary, while `DSDontWriteNetworkStores` does. It may be dead on Tahoe. Test it on a real USB stick before shipping. |

Every Finder key is read at Finder launch. Changes made through Finder's own Settings or View menu apply live, but values written from another process need a Finder relaunch.

## 3. Screenshots (`com.apple.screencapture`)

| Key | Type | Default | Valid values / UI | Applies after | Exposed in UI? | Notes |
|---|---|---|---|---|---|---|
| `location` | string (path) | unset = ~/Desktop | Folder picker; write an absolute path | Next capture (see SystemUIServer below) | Yes: ⌘⇧5 > Options > Save to (Desktop, Documents, Other Location...) | Tested Mojave to Sonoma [22]. Use an absolute path. macos-defaults writes `"~/Desktop"` unexpanded, so tildes do work, but an absolute path is safer. Ignored when `target` is not a file destination. |
| `target` | string | unset = file | Picker. `file` and `clipboard` are confirmed by blogs [23][24]. `preview`, `mail`, `messages` match the Save to menu but are **unverified** values. One blog also saw a folder path stored in `target` [24]. | Next capture | Yes: ⌘⇧5 > Options > Save to (Clipboard, Mail, Messages, Preview) | Key name is in the screencaptureui binary. **Our Location UI must read `target` too**: if the user picked Clipboard in ⌘⇧5, changing `location` will seem to do nothing. |
| `type` | string | png | Picker: png, jpg, heic, pdf, tiff, gif, bmp (macos-defaults also lists psd, tga) [25]. `man screencapture` says "png (default), pdf, jpg, tiff and other formats". | Next capture, no restart (macos-defaults gives no killall for it [25]) | No | Tested Mojave to Sonoma [25]. HEIC added in 2021 (#172). Suggest exposing png/jpg/heic/pdf/tiff only. |
| `name` | string | unset = localized "Screenshot" (and "Screen Recording") | Text field with placeholder | Next capture | No | **Reset must delete, not write "Screenshot"**: writing the English word would break localized names for non-English users. Shown in thrysoee [26]. |
| `include-date` | bool | true | Toggle | Next capture | No | Tested Mojave to Sonoma [27]. With false, files are named "Screenshot.png", "Screenshot 1.png"... |
| `disable-shadow` | bool | false | Toggle (inverted: "Window shadow") | Next capture | No (⌥-click when capturing a window does it once) | Tested Mojave to Sonoma [28]. Key present in 26.5 shared cache. |
| `show-thumbnail` | bool | true | Toggle | Next capture | Yes: ⌘⇧5 > Options > Show Floating Thumbnail | Tested Mojave to Sonoma [29]. |

Screenshot app write-back: the ⌘⇧5 toolbar writes to this same domain. On this Mac, `style = display`, `video = 0` and `captureDelay = 5` (float, the timer) are set even though no other key is, so these came from the toolbar. Save to writes `location` / `target`, and Show Floating Thumbnail writes `show-thumbnail` (the exact key for each menu item is **unverified** beyond these). So every screenshot setting must be **read fresh each time the panel is shown**, never cached.

Related keys in another domain: `com.apple.screencaptureui` holds the annotation (markup) settings, and `thumbnailExpiration` (float, seconds the floating thumbnail stays up). `thumbnailExpiration` is confirmed in the 26.5 screencaptureui binary and was reported working on 15.7.5 with no SystemUIServer restart [30]. Its default is **unverified**: that issue says 10 s, but it is often said to be about 5 s.

### Is `killall SystemUIServer` still needed?

Probably not on modern macOS:

- The screenshot UI is `screencaptureui`, an on-demand launchd agent (`com.apple.screencaptureui.agent`, no `KeepAlive`). It is not running between captures on this Mac (launchctl shows no PID), so it reads preferences fresh each time it starts.
- macos-defaults gives no restart for `type`, `name`, `include-date`, `disable-shadow` or `show-thumbnail`. It still adds `killall SystemUIServer` only for `location` [22], and ss64 does the same for location and shadow [31]. Those look like leftovers from older macOS.
- A user on 15.7.5 confirmed a screencaptureui key worked with no restart [30]. Community guides report a new `location` applying immediately [32].
- SystemUIServer still hosts the `com.apple.systemuiserver.screencapture` mach service, so a restart cannot hurt beyond briefly flickering menu extras.

Recommendation: apply with no restart. Test `location` on 13, 14 and 26 (**unverified** on Tahoe). If any version needs it, restart SystemUIServer only for `location` changes.

---

## 4. Applying changes: relaunching Dock, Finder, SystemUIServer

What launchd does (read from `/System/Library/LaunchAgents/*.plist` on 26.5):

| Process | launchd label | KeepAlive | Effect |
|---|---|---|---|
| Dock | `com.apple.Dock.agent` | `SuccessfulExit = false`, `AfterInitialDemand = true` | Restarted by launchd only if it exits **unsuccessfully** (signal or non-zero exit). |
| Finder | `com.apple.Finder` | same | Same. A clean quit (exit 0, e.g. via a quit Apple Event) is **not** auto-restarted. The last exit on this Mac was -15 (SIGTERM, i.e. an earlier `killall Finder`), and launchd restarted it. |
| SystemUIServer | `com.apple.SystemUIServer.agent` | same | Same. |

Recommendations:

- **Use exact PIDs, never name matching.** Get the target with `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")` (also `com.apple.finder`, `com.apple.systemuiserver`), then send `kill(pid, SIGTERM)`. That is exactly what `/usr/bin/killall Dock` does (SIGTERM by default), aimed at one process. Because the exit is "unsuccessful", launchd brings it back within about a second. Avoid spawning `/usr/bin/killall` (name matching, and it hits every user session's Dock if run as root). This also follows Ikraam's no-name-kill rule.
- **`NSRunningApplication.terminate()`** sends a normal quit. Apple's docs say it may return before the app exits (observe `isTerminated`), and it returns false from a sandboxed app [33]. For Dock and SystemUIServer, a clean quit would not be restarted by launchd (KeepAlive only on unsuccessful exit). Whether Dock even honours a quit request is **unverified**. So do not use `terminate()` for Dock or SystemUIServer.
- **Finder**: two options.
  - (a) `terminate()`, wait for `isTerminated`, then relaunch with `NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), ...)`. This is the gentlest: Finder saves its window state on a normal quit.
  - (b) SIGTERM, and launchd restarts it.
  - Whether `terminate()` on Finder triggers an Automation (Apple Events) consent prompt is **unverified**; test it.
- **Finder window state**: Finder has its own browser-window restoration (`-[TGlobalWindowController restoreOneBrowserWindowFromState:...]` is in the 26.5 binary). In practice windows usually come back after `killall Finder`, but reports are mixed, especially for tabs and anything not saved since the last clean quit [34]. **Killing Finder also cancels in-progress copy, move and empty-Trash operations.** The UI should say "Finder will relaunch; any file copies in progress will stop" and ideally ask first.
- **Dock relaunch side effects**: the Dock also runs Mission Control, Spaces and the Notification Center hand-off. Restarting it flashes the Dock and full-screen apps, and briefly resets the Spaces UI. Batch several Dock changes into one restart.
- **`launchctl kickstart -k gui/$UID/com.apple.Dock.agent`** would be the launchd-native restart, but whether SIP allows it for Apple agents is **unverified**. Not tested, because testing would restart the Dock.
- **Why System Settings never restarts the Dock**: the DesktopSettings extension imports `CoreDockSetPreferences`, `CoreDockSetAutoHideEnabled`, `CoreDockSetTileSize` and similar from the private CoreDock API (seen via `nm -u`). It updates the running Dock live. That is private API, so we should use `defaults` plus a restart.
- dotfiles' `.macos` also kills `cfprefsd` [6]. **Do not do this**: it is unnecessary when writing through CFPreferences, and disruptive.

## 5. Permissions and how to write

- **Non-sandboxed app (Developer ID)**: writing `com.apple.dock`, `com.apple.finder`, `com.apple.screencapture`, `com.apple.screencaptureui`, `com.apple.desktopservices` and NSGlobalDomain through CFPreferences needs **no TCC permission**. These live in `~/Library/Preferences` and are owned by the user (checked here: `-rw------- ikraam staff`).
  - Sonoma's "access data from other apps" prompt covers sandboxed apps' `~/Library/Containers` (Sequoia adds Group Containers), not `~/Library/Preferences` [35].
  - "App Management" (Ventura+, `kTCCServiceSystemPolicyAppBundles`) guards changes to **app bundles**, not preferences [36].
  - Exception: `com.apple.universalaccess` (for example `showWindowTitlebarIcons`, reduce motion) needs Full Disk Access to write [37][38]. Avoid that domain in v1.
- **Sandboxed / Mac App Store**: a sandboxed app's writes go to its own container. The only legitimate route is the `com.apple.security.temporary-exception.shared-preference.read-write` entitlement listing each domain [39]. Even then, `terminate()` is blocked [33] and signals cannot be sent to other processes, so the Dock cannot be restarted, and App Review acceptance is doubtful [40]. **Ship outside the App Store, non-sandboxed** (hardened runtime is fine).
- **Write via CFPreferences, never by editing the plist.** cfprefsd caches values and will overwrite direct file edits [41][42]. Use:
  - `CFPreferencesSetValue(key, value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)` then `CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)`. This is what `defaults write` does.
  - Pass `nil` as the value to delete (equivalent to `defaults delete`).
  - Write the correct CF type (CFBoolean, CFNumber as Double for floats).
- **Reading "set vs unset"**:
  - Use `CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)`, which reads only that exact domain.
  - Do not rely on `CFPreferencesCopyAppValue` alone: it falls back to NSGlobalDomain and ByHost values. That would wrongly show `com.apple.finder AppleShowAllExtensions` as "set" when only the global one is.
  - Also check `kCFPreferencesCurrentHost`: a ByHost value overrides the AnyHost one [42]. This Mac has ByHost files for dock (only `LaunchPadDBName`) and screencapture (only `audio-id`), so there are no conflicts today.

## 6. Reset semantics: delete vs write default

Rule: **reset = delete the key** (`CFPreferencesSetValue(key, nil, ...)`, i.e. `defaults delete domain key`), then apply (restart if the key needs it). macos-defaults uses delete for every reset [1-29]. Places where delete and writing the "default" behave differently:

- `com.apple.screencapture name`: unset gives the **localized** "Screenshot" / "Screen Recording". Writing "Screenshot" hard-codes English.
- `com.apple.screencapture location`: unset means Desktop. Writing `~/Desktop` is equivalent but leaves a value behind. Also, deleting `location` does nothing if `target` = clipboard (reset both together under one "Save location" reset).
- `AppleShowAllExtensions`: delete from **NSGlobalDomain and com.apple.finder**. A leftover app-domain value overrides the global one for Finder.
- Keys exposed in System Settings or Finder Settings (`show-recents`, `mru-spaces`, `expose-group-apps`, `AppleShowAllExtensions`, `FXEnableExtensionChangeWarning`, `_FXSortFoldersFirst*`, `ShowPathbar`, `ShowStatusBar`, `show-thumbnail`): those UIs write explicit values. On this Mac `show-recents = 0` and `mru-spaces = 0` are both set. So "reset" undoes the user's own System Settings choice, not just ours. The reset label should say "Reset to macOS default", and the UI should show "Changed in System Settings" vs "Default" based on set/unset.
- `static-only`: deleting the key goes back to false, but see the Tahoe report [12]. Consider also offering "Restore Dock items" from a snapshot.
- `DSDontWriteNetworkStores` / `DSDontWriteUSBStores`: delete and `-bool FALSE` are equivalent [10]. Both need logout.
- `autohide-delay` / `autohide-time-modifier`: delete returns to the built-in default. Writing 0.2 / 0.5 relies on the macos-defaults figures being right (**unverified** as the true compiled defaults), so prefer delete.

---

## 7. v2 candidates

| Key | Domain | Type | Default | UI | Applies after | In System Settings? | Notes |
|---|---|---|---|---|---|---|---|
| `show-recent-count` | com.apple.dock | int | 3 (**unverified**) | Stepper 0 to 10 | `killall Dock` | No | Present in 26.5 Dock binary. Number of recent apps shown when `show-recents` is on. |
| `scroll-to-open` | com.apple.dock | bool | false | Toggle | `killall Dock` | No | Scroll up on a Dock icon for App Exposé / open stack. Tested Mojave to Sequoia [43]. |
| `mineffect` | com.apple.dock | string | genie | Picker: genie, scale, suck | `killall Dock` | Partly: Desktop & Dock > "Minimise windows using" (Genie/Scale only) | The `suck` value string is still in the 26.5 Dock binary [44]. |
| `size-immutable` / `contents-immutable` / `position-immutable` | com.apple.dock | bool | false | Toggles ("Lock Dock size / items / position") | `killall Dock` | No | All three are in the 26.5 Dock binary. Proposed in macos-defaults #413. |
| `mouse-over-hilite-stack` | com.apple.dock | bool | false | Toggle | `killall Dock` | No | Highlight on hover in grid stacks. In dotfiles [6] and Dock binary. |
| `spans-displays` | com.apple.spaces | bool | false | Toggle (inverted of "Displays have separate Spaces") | **Log out** [45] | Yes: Desktop & Dock > Mission Control > "Displays have separate Spaces" | Turning separate Spaces off disables Stage Manager and window tiling (Settings strings). |
| `FXDefaultSearchScope` | com.apple.finder | string | SCev (This Mac) | Picker: SCev / SCcf (current folder) / SCsp (previous scope) | `killall Finder` | Yes: Finder > Settings > Advanced > "When performing a search" | Confirmed working on 14.3.1 [46][47]. |
| `FXPreferredViewStyle` | com.apple.finder | string | icnv | Picker: icnv / Nlsv / clmv / glyv | `killall Finder` | Only via View Options "Use as Defaults" | Per-folder .DS_Store settings override it [48]. Set to Nlsv on this Mac. |
| `CreateDesktop` | com.apple.finder | bool | true | Toggle ("Show desktop icons") | `killall Finder` | No | Tested Big Sur to Sonoma [49]. |
| `_FXEnableColumnAutoSizing` | com.apple.finder | bool | false | Toggle | `killall Finder` | Yes on Tahoe: column view ⌘J > "Resize columns to fit filenames" | Only Tahoe-tested key on macos-defaults [50]. Probably Tahoe-only (**unverified** on 13 to 15). |
| `thumbnailExpiration` | com.apple.screencaptureui | float (s) | **unverified** (5 or 10) | Slider 1 to 60 s | Next capture | No | Confirmed in 26.5 binary; worked on 15.7.5 [30]. |
| `FXRemoveOldTrashItems` | com.apple.finder | bool | false | Toggle | `killall Finder` | Yes: Finder > Settings > Advanced > "Remove items from the Trash after 30 days" | Tested Big Sur to Sonoma [51]. |

**Avoid** (dead or harmful on modern macOS):

- `expose-animation-duration`: reported not working for years, including an Aug 2024 Apple Community thread [52]. The string is absent from the 26.5 Dock binary and shared cache.
- `workspaces-swoosh-animation-off`: absent from 26.5.
- `expose-group-by-app`: replaced by `expose-group-apps`.
- Dashboard keys: Dashboard was removed years ago.
- Launchpad `springboard-*` keys: Tahoe replaced Launchpad with Apps.app. The strings are vestigial; **unverified** whether they do anything.
- `QuitMenuItem`: macos-defaults says it "behaves strangely" and does not recommend it [53].
- `com.apple.universalaccess` keys: need Full Disk Access.

---

## Sources

1. macos-defaults, Dock autohide-delay: https://github.com/yannbertrand/macos-defaults/blob/main/docs/dock/autohide-delay.md (site: https://macos-defaults.com/dock/autohide-delay.html)
2. macos-defaults, autohide-time-modifier: https://macos-defaults.com/dock/autohide-time-modifier.html
3. macos-defaults, static-only: https://macos-defaults.com/dock/static-only.html
4. macos-defaults issue #259 (static-only empties Dock) and #405 (alternatives to static-only): https://github.com/yannbertrand/macos-defaults/issues/259, https://github.com/yannbertrand/macos-defaults/issues/405
5. macos-defaults broken.md: https://github.com/yannbertrand/macos-defaults/blob/main/broken.md
6. mathiasbynens/dotfiles `.macos` (last changed 2020): https://github.com/mathiasbynens/dotfiles/blob/main/.macos
7. macos-defaults, mru-spaces: https://macos-defaults.com/mission-control/mru-spaces.html
8. macos-defaults, expose-group-apps: https://macos-defaults.com/mission-control/expose-group-apps.html
9. 9to5Mac Dock autohide (older reports): https://9to5mac.com/2017/05/09/macos-dock-autohide-animation-video/
10. Apple Support, "Adjust SMB browsing behavior in macOS": https://support.apple.com/en-us/102064
11. (unused)
12. Apple Community, "Can't revert Dock static-only on MacBook M1" (Tahoe 26.2, Feb 2026): https://discussions.apple.com/thread/256236517
13. Apple Community, recent apps still shown with setting off (Jan 2026): https://discussions.apple.com/thread/256234626
14. Apple Community, "Dock disappears randomly on macOS Tahoe 26.0": https://discussions.apple.com/thread/256138247
15. macos-defaults, AppleShowAllFiles: https://macos-defaults.com/finder/appleshowallfiles.html
16. macos-defaults, ShowPathbar: https://macos-defaults.com/finder/showpathbar.html
17. macos-defaults, ShowStatusBar: https://macos-defaults.com/finder/showstatusbar.html
18. macos-defaults, AppleShowAllExtensions: https://macos-defaults.com/finder/appleshowallextensions.html
19. macos-defaults, FXEnableExtensionChangeWarning: https://macos-defaults.com/finder/fxenableextensionchangewarning.html
20. macos-defaults, _FXSortFoldersFirst: https://macos-defaults.com/finder/_fxsortfoldersfirst.html
21. macos-defaults, _FXSortFoldersFirstOnDesktop: https://macos-defaults.com/desktop/_fxsortfoldersfirstondesktop.html
22. macos-defaults, screenshot location: https://macos-defaults.com/screenshots/location.html
23. Gist on screenshot target clipboard/file: https://gist.github.com/Leo7654/477cb8b12982438dc199491253219ff4
24. verityj blog, screencapture target: https://verityj.github.io/2023/06/15/screenshot.html
25. macos-defaults, screenshot type: https://macos-defaults.com/screenshots/type.html
26. thrysoee, macOS Screenshot: https://thrysoee.dk/macos-screenshot/
27. macos-defaults, include-date: https://macos-defaults.com/screenshots/include-date.html
28. macos-defaults, disable-shadow: https://macos-defaults.com/screenshots/disable-shadow.html
29. macos-defaults, show-thumbnail: https://macos-defaults.com/screenshots/show-thumbnail.html
30. macos-defaults issue #448 (thumbnailExpiration, no SystemUIServer restart needed, macOS 15.7.5): https://github.com/yannbertrand/macos-defaults/issues/448
31. ss64, screencapture: https://ss64.com/mac/screencapture.html
32. computingforgeeks, change screenshots directory: https://computingforgeeks.com/how-to-set-change-screenshots-directory-in-macos/
33. Apple Developer, NSRunningApplication.terminate(): https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate()
34. BinaryAge forum, killall Finder window restore: https://discuss.binaryage.com/t/kill-all-tabs-relaunch-finder-relaunch-totalfinder-all-previously-killed-tabs-windows-relaunch-appear/7096
35. Eclectic Light, "What are all those Containers?" (Sonoma/Sequoia container protection): https://eclecticlight.co/2024/08/05/what-are-all-those-containers/
36. Apple Developer Forums, Ventura App Management: https://developer.apple.com/forums/thread/715220
37. macos-defaults, showWindowTitlebarIcons (needs Full Disk Access): https://macos-defaults.com/finder/showwindowtitlebaricons.html
38. dotfiles issue #1027 (com.apple.universalaccess write errors): https://github.com/mathiasbynens/dotfiles/issues/1027
39. Apple, App Sandbox temporary exception entitlements: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html
40. Stack Overflow, restart Dock from sandboxed app: https://stackoverflow.com/questions/31417055
41. Eclectic Light, "Preference settings and Finder misbehaviour": https://eclecticlight.co/2021/01/19/preference-settings-and-finder-misbehaviour/
42. Eclectic Light, "Changing preferences isn't so simple" (ByHost overrides): https://eclecticlight.co/2022/11/25/changing-preferences-isnt-so-simple/
43. macos-defaults, scroll-to-open: https://macos-defaults.com/dock/scroll-to-open.html
44. macos-defaults, mineffect: https://macos-defaults.com/dock/mineffect.html
45. macos-defaults, spans-displays: https://macos-defaults.com/mission-control/spans-displays.html
46. macos-defaults, FXDefaultSearchScope: https://macos-defaults.com/finder/fxdefaultsearchscope.html
47. macos-defaults issue #340: https://github.com/yannbertrand/macos-defaults/issues/340
48. macos-defaults, FXPreferredViewStyle: https://macos-defaults.com/finder/fxpreferredviewstyle.html
49. macos-defaults, CreateDesktop: https://macos-defaults.com/desktop/createdesktop.html
50. macos-defaults, _FXEnableColumnAutoSizing: https://macos-defaults.com/finder/_fxenablecolumnautosizing.html
51. macos-defaults, FXRemoveOldTrashItems: https://macos-defaults.com/finder/fxremoveoldtrashitems.html
52. Apple Community, disable workspace switching animation (expose-animation-duration not working, Aug 2024): https://discussions.apple.com/thread/255703422
53. macos-defaults, QuitMenuItem: https://macos-defaults.com/finder/quitmenuitem.html
54. Local evidence (this Mac, 26.5.2): `strings` on `/System/Library/CoreServices/{Dock,Finder,screencaptureui}.app`, `/System/Library/ExtensionKit/Extensions/DesktopSettings.appex`, byte search of `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*`, `/System/Library/LaunchAgents/com.apple.{Dock,Finder,SystemUIServer,screencaptureui}.plist`, `man screencapture`.
