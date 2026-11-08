# Refined Settings: distribution, trust and competitive landscape

Research date: 2026-11-08. Sources are numbered in square brackets and listed under "Sources" at the end. Claims I could not confirm from a primary source are marked **unverified**. Quotes are kept under 15 words.

## Summary of recommendations

1. **Name and tagline are fine as planned.** "Refined Settings" with the tagline "Refined Settings for Mac" matches Apple's referential-use rule: the Apple word mark is not part of the product name, and it appears after "for" [1]. Keep "Mac" in the tagline visibly smaller than the product name [1]. Add the attribution line "Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions." to the website and About window [3]. Settings and help text can name Finder, Safari, Mission Control, Launchpad and Spotlight descriptively; all of them are registered Apple marks [3].
2. **Make the icon look less like System Settings.** A silver gear on a slate tile is close to System Settings' grey gear. Apple's guidelines bar imitating Apple "logos" and "trade dress" [1], and the HIG says to "avoid replicating UI components" in icons [4]. App Review 5.2.5 (App Store only, but it shows Apple's stance) rejects apps "confusingly similar" to an Apple app [2]. Keep the gear idea, but give it a distinct silhouette (not concentric toothed rings), a brand colour that isn't Apple grey, and one ownable motif (for example a link, cursor or slider glyph). Don't use Apple hardware in the icon or the marketing art [4].
3. **Ship outside the Mac App Store, with Developer ID and notarization.** Cost: Apple Developer Program, 99 USD per year [7]. Pipeline: `swift build -c release`, then assemble the `.app`, then sign inside-out with `codesign --options runtime --timestamp`, then put it in a DMG, sign the DMG, then `xcrun notarytool submit --wait`, then `xcrun stapler staple`. All of this works with Command Line Tools only: on this Mac, CLT 26.6 ships `notarytool` and `stapler`, and `codesign`, `hdiutil` and `ditto` are in `/usr/bin` (checked locally). Entitlements: none are needed for event taps or Accessibility. Add `com.apple.security.automation.apple-events` and `NSAppleEventsUsageDescription` only if you send Apple Events to Safari or other apps [8][9].
4. **The Mac App Store is not an option.** Three reasons. The sandbox "blocks use of the Accessibility APIs" [11], and LinearMouse-style active event taps need Accessibility. Hidden Settings writes other apps' preference domains, which needs a temporary exception that App Review scrutinises [12]. And App Store apps can't ship their own updater (2.4.5(vii)) or alter native UI behaviours (2.5.9) [2]. Being the default browser is not a blocker on its own: Velja and OpenIn ship on the Mac App Store [20][23].
5. **Use Sparkle 2 for updates, without XPC services.** Use Sparkle 2.10.1 (released 2026-10-25) through SwiftPM [14]. Generate EdDSA keys with `generate_keys`, and set `SUFeedURL` and `SUPublicEDKey` in Info.plist [13]. Host `appcast.xml` and the archives on GitHub Releases. A non-sandboxed app doesn't need Sparkle's XPC services [15]. Re-sign `Autoupdate`, `Updater.app` and the framework with your Developer ID, and never use `--deep` [15]. Keep system profiling off (the default) [16].
6. **Start with a personal Homebrew tap, then move to homebrew/cask.** homebrew/cask has two requirements. The project needs 75 stars, 30 forks or 30 watchers (225 stars, 90 forks or 90 watchers if you submit it yourself) and a repo at least 30 days old [17]. The app must also pass Gatekeeper [18], because casks that fail Gatekeeper stopped being supported on 2026-09-01 [19]. Set `auto_updates true` once Sparkle ships [21].
7. **Licence:** MIT for your own code is the simplest choice and fits the LinearMouse code you borrow. Whatever licence you choose, keep LinearMouse's copyright and licence text in a `THIRD_PARTY_NOTICES` file and in an Acknowledgements view in the app. **Do not borrow code from Mos (CC BY-NC 4.0), Mac Mouse Fix (custom MMF License) or UnnaturalScrollWheels (GPL-3.0)** unless you accept their terms (section 7).
8. **Trust:** say "no network except update checks, no analytics, no account" plainly. Explain each permission in one sentence before you ask for it, and include the `tccutil reset` fix, as LinearMouse does [27]. Suggested README text is in section 6.

---

## 1. Apple trademark rules

### What the guidelines say

**"Mac" in product names.** Apple's *Guidelines for Using Apple Trademarks and Copyrights* [1] say you may not use the Mac trademark "standing alone except to denote or refer to" Apple's Mac line. "Mac" may appear in a product name only if all of these conditions hold:

- the product "is not a computer, computer system, or operating system software"
- it is Mac-compatible
- "Mac" is paired with a non-generic word
- "Mac" is not more prominent than the rest of the name
- there is no implied association with Apple

So "Mac" in the name is technically allowed under strict conditions. Leaving it out, as planned, is the low-risk path. The guidelines also forbid variations, takeoffs and abbreviations of Apple marks [1]. That means avoiding names like "Macify" or "iSettings".

**Taglines such as "for Mac".** Referential use is explicitly allowed when the Apple word mark is not part of the product name, appears in a phrase "such as 'runs on,' 'for use with,' 'for,'" [1], is less prominent than your product name, the product really is compatible, and there's no implied endorsement [1]. The App Store marketing guidelines say the same for device names: write "app name for iPhone", not "iPhone app name" [5]. "Refined Settings for Mac" and "Refined Settings for macOS" both fit.

**Trademark attribution.** Apple's trademark list includes Mac, macOS, Finder, Safari, Spotlight, Mission Control, Launchpad, Magic Mouse, Magic Trackpad and App Store [3]. Outside the US, Apple asks for an attribution notice rather than ™/® symbols. Its example is "Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions." [3]. "Dock" and "System Settings" are not on the list [3], but treat them as Apple's terms anyway.

**Icons that resemble Apple's.**
- Trademark guidelines: you may not use "any other Apple-owned graphic symbol, logo, or icon" [1], and you may not "imitate the distinctive Apple packaging, web site design, logos, or typefaces" [1].
- HIG (App icons): "Prefer illustrations to photos and avoid replicating UI components." It also says "Don't use replicas of Apple hardware products." [4]
- App Review 5.2.5 (Mac App Store only): "Don't create an app that appears confusingly similar to an existing Apple product, interface (such as Finder), app..." [2]. We aren't on the App Store, but this shows how Apple judges look-alikes.
- **Nothing found** says "do not draw a gear". The risk is a fact question about similarity to the System Settings icon. A silver gear on a slate rounded square is close enough to change (see Recommendation 2). **Unverified:** whether Apple has ever acted against a third-party gear icon.

**Screenshots of macOS.**
- The trademark guidelines don't address software screenshots [1]. Apple's Rights and Permissions page sends requests to use Apple material in publications to Apple's Copyright team [6]. I found no blanket licence for screenshots.
- The App Store marketing guidelines (written for App Store promotion, but a useful norm) say to "Display your app on the screen as it appears when your app is running", to use the latest OS version, and not to imply an association with Apple [5]. They also bar "Rendering in 3D or creating any simulation of an Apple product" [5].
- Practical reading: screenshots of your own app's windows, with macOS window chrome and menu bar around them, are standard practice. Avoid wallpapers that are Apple artwork, Apple hardware mock-ups other than Apple's official bezels, and Apple logos. **Unverified:** whether Apple's default wallpapers in screenshots are a real risk. Using your own or a neutral wallpaper avoids the question.

### Checklist
- Product name: no Mac, macOS, i-prefix, Apple, or variations of them.
- Tagline: "for Mac" in a smaller weight than the wordmark.
- Attribution line in the website footer and the About window [3].
- Icon: distinct silhouette and colour; no Apple hardware; no copy of the System Settings gear [1][4].
- Screenshots: your app only, current macOS, neutral wallpaper, no Apple logo.

## 2. Distribution outside the App Store

### Cost and accounts
- Apple Developer Program: **99 USD per membership year**. Fee waivers exist only for nonprofits, schools and government bodies [7].
- A Developer ID certificate can be generated only by the team's **Account Holder** [10]. You can create it in the Certificates, Identifiers & Profiles web portal without Xcode [10].
- Notarization is required in practice. Since macOS 10.15, Developer ID software built after June 2019 must be notarized [8]. On macOS 15, users can no longer Control-click to bypass Gatekeeper [22]. Since Apple's 2024-08-06 notice [22], unnotarized apps need System Settings > Privacy & Security > Open Anyway, which loses many users.

### Hardened runtime and entitlements
- Notarization requires: a Developer ID certificate, the hardened runtime on every executable, a secure timestamp, and linking against the 10.9 SDK or later [8].
- The hardened runtime "doesn't affect the operation of most apps" and only restricts things like JIT and loading unsigned code [9]. Entitlement values default to false, so include only the keys you set to true [9].
- **Event taps and Accessibility need no entitlement.** They are gated by TCC (user permission in System Settings), not by entitlements. LinearMouse's shipping entitlements file has only `com.apple.security.device.bluetooth` and `files.user-selected.read-only` [26].
- **Apple Events (for example to Safari):** the hardened runtime blocks sending Apple Events to other apps unless you add `com.apple.security.automation.apple-events`, described as whether the app "may prompt the user for permission to send Apple events" [9]. You also need `NSAppleEventsUsageDescription`, which is "required if your app uses APIs that send Apple events" [9b]. Without the entitlement, sends fail with `-1743` and no prompt appears (developer reports [24]; **not stated in Apple's docs**).
- You don't need either key just to open a URL in a chosen browser with `NSWorkspace.open(_:withApplicationAt:configuration:)` (general knowledge, **unverified** in Apple docs). Chrome profiles are chosen with launch arguments, because Chrome's AppleScript "does not know about profiles" (Velja FAQ [20]).
- **Library validation pitfall:** with the hardened runtime on, an ad-hoc-signed local build may refuse to load Sparkle.framework. Sign dev builds with an Apple Development certificate, or disable library validation in debug builds only [13].
- **TCC pitfall:** Accessibility grants are tied to the code signature. Ad-hoc builds get a new identity on every build, so permission seems to "reset". A stable Developer ID signature keeps the grant across updates (third-party docs [25]; consistent with LinearMouse's `tccutil reset` advice [27]).

### Signing and notarization pipeline (Command Line Tools only)
Checked on this Mac: `xcode-select -p` is `/Library/Developer/CommandLineTools`. CLT 26.6 includes `notarytool` and `stapler`, and `codesign`, `hdiutil`, `ditto` and `stapler` are in `/usr/bin`. Apple's docs describe `notarytool` and `stapler` as "included with Xcode" [8]. That they also ship in CLT is from this local check, not from Apple's docs.

```sh
# 1. Build and assemble the bundle (SwiftPM doesn't make .app bundles)
swift build -c release --arch arm64 --arch x86_64
# copy binary to RefinedSettings.app/Contents/MacOS, Info.plist, Resources, Frameworks/Sparkle.framework

# 2. Sign inside-out (Sparkle parts first, see section 3), then the app
codesign -f -s "Developer ID Application: NAME (TEAMID)" -o runtime --timestamp \
  --entitlements RefinedSettings.entitlements RefinedSettings.app
codesign --verify --strict --verbose=2 RefinedSettings.app

# 3. Package: DMG with an /Applications symlink (Sparkle recommends this [13]), then sign the DMG
hdiutil create -volname "Refined Settings" -srcfolder staging -fs APFS -format ULFO RefinedSettings.dmg
codesign -s "Developer ID Application: NAME (TEAMID)" --timestamp RefinedSettings.dmg

# 4. Notarize and staple (store credentials once with notarytool store-credentials)
xcrun notarytool submit RefinedSettings.dmg --keychain-profile notary --wait
xcrun notarytool log <submission-id> --keychain-profile notary   # always read the log [8b]
xcrun stapler staple RefinedSettings.dmg
spctl --assess --type open --context context:primary-signature -v RefinedSettings.dmg
```

- `notarytool` accepts DMGs (UDIF), signed flat pkgs and ZIPs. You can't staple a ZIP: staple the app, then zip it again [8b]. Most submissions finish within 5 minutes, 98% within 15 [8b].
- `altool` notarization stopped working on 2023-11-01 [8].
- **DMG tools:** `sindresorhus/create-dmg` (MIT, about 5.4k stars) signs the DMG automatically but doesn't notarize it [28]. `create-dmg/create-dmg` is a configurable shell script (MIT) [28]. Plain `hdiutil` is enough for a simple DMG.
- **DMG or zip:** use a DMG for first downloads (drag-to-Applications). For Sparkle updates either works. Sparkle recommends lzfse APFS DMGs, or zips made with `ditto -c -k --sequesterRsrc --keepParent` [13b].

### Why not the Mac App Store
| Need | Sandbox / App Review position | Source |
|---|---|---|
| Active event tap that modifies scroll and pointer events (LinearMouse model) | "App Sandbox blocks use of the Accessibility APIs." Listen-only taps (Input Monitoring) and `CGEvent.post` (PostEvent) are allowed, but you can't suppress or rewrite events in place. | [11] |
| Writing `com.apple.dock`, `com.apple.finder`, `com.apple.screencapture` domains | Needs `temporary-exception.shared-preference.read-write`. App Review examines temporary exceptions closely; they are fine outside the store. | [12] |
| Restarting Dock, Finder or SystemUIServer, and any admin-level setting | Mac App Store apps "may not request escalation to root privileges" | [2] 2.4.5(v) |
| Sparkle updater | Mac App Store apps must update via the store only | [2] 2.4.5(vii) |
| Changing scroll direction and other OS behaviours | 2.5.9 rejects apps that alter "native user interface elements or behaviors" | [2] |
| Being the default browser and showing a picker | Allowed: Velja is sold on the Mac App Store [20]. OpenIn ships a sandboxed App Store build and needs a helper for advanced features [23]. | [20][23] |

## 3. Updates

### Sparkle 2 in a SwiftPM-built app (no Xcode)
- **Package:** add `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")`. It is a `binaryTarget` (an XCFramework zip) [14]. Latest release: 2.10.1 (2026-10-25) [14].
- **Bundle it yourself:** `swift build` links the framework but doesn't embed it. Copy `Sparkle.framework` into `Contents/Frameworks`, and add the linker flag `-Wl,-rpath,@loader_path/../Frameworks` ("for non-Xcode projects add the flags", per Sparkle's docs [13]). In `Package.swift` that means `linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]`, or the same flag on the command line (**unverified** exact flag spelling for SwiftPM; check that `otool -l` shows the `LC_RPATH`).
- **Tools:** `generate_keys`, `generate_appcast` and `sign_update` are in the SwiftPM artifact at `../artifacts/sparkle/Sparkle/bin/` [13], or in the `Sparkle-2.x.tar.xz` release.
- **Keys:** `./bin/generate_keys` stores the EdDSA private key in your login keychain and prints the public key for `SUPublicEDKey` [13]. Export a backup with `-x` [13]. If the key is lost, Sparkle supports rotation for Developer ID-signed apps (change the cert or the EdDSA key, never both at once) [13].
- **Info.plist:** set `SUFeedURL`, `SUPublicEDKey`, and a `CFBundleVersion` that always increases [13]. Optional: `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`. Leave `SUEnableSystemProfiling` off (the default, NO). If turned on, it sends OS version, CPU, model, RAM and the app name weekly [16].
- **Code:** create `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` and wire a "Check for Updates..." menu item to `checkForUpdates(_:)` [13]. LinearMouse does exactly this, and uses `allowedChannels` for a beta channel [26].
- **XPC and sandbox:** "If you do not sandbox your application, you should skip this guide" [15]. The Installer and Downloader XPC services are only for sandboxed apps, and you may delete them from the copied framework to save space [15].
- **Signing Sparkle's helpers (manual workflow):** Sparkle ships its helpers ad-hoc signed. Re-sign them in this order [15]:

```sh
codesign -f -s "$ID" -o runtime Sparkle.framework/Versions/B/XPCServices/Installer.xpc   # if kept
codesign -f -s "$ID" -o runtime --preserve-metadata=entitlements Sparkle.framework/Versions/B/XPCServices/Downloader.xpc  # if kept
codesign -f -s "$ID" -o runtime Sparkle.framework/Versions/B/Autoupdate
codesign -f -s "$ID" -o runtime Sparkle.framework/Versions/B/Updater.app
codesign -f -s "$ID" -o runtime Sparkle.framework
```
  Add `--timestamp` for notarization. Sparkle warns: "please do not add `--deep`" [15].
- **Hosting on GitHub Releases:** upload the notarized DMG or zip as a release asset. Run `generate_appcast` over a folder of archives (it also builds deltas and picks up release notes from matching `.html` or `.md` files) [13]. Rewrite enclosure URLs to the release download URL with `--download-url-prefix` (**unverified** flag name in current docs; run `generate_appcast -h`). Publish `appcast.xml` either as a release asset at `https://github.com/OWNER/REPO/releases/latest/download/appcast.xml`, or on GitHub Pages. If you use `sign_update` by hand, it outputs `sparkle:edSignature` and `length` for the `<enclosure>` [13b].
- **Testing:** run an older build twice (Sparkle asks for permission on the second launch), and clear `SULastCheckTime` to force a check [13].

### Alternatives
- **Homebrew only:** users run `brew upgrade --cask`. Casks marked `auto_updates true` are skipped unless the user passes `--greedy` [21b], so Sparkle and Homebrew sit together cleanly.
- **Manual:** check the GitHub Releases API and show "Update available" with a link. This needs no framework but makes users download and replace the app themselves. It suits pre-1.0 only.
- **Mac App Store:** not possible (section 2).

## 4. Homebrew cask

| | homebrew/cask (official) | Personal tap (`ikraam/homebrew-tap`) |
|---|---|---|
| Notability | 75 stars, 30 forks or 30 watchers; **self-submitted: 225 stars, 90 forks or 90 watchers**; repo at least 30 days old [17] | None |
| Gatekeeper | Apps "must pass Homebrew's Gatekeeper checks" [18]. Casks failing Gatekeeper lost support on 2026-09-01, and `--no-quarantine` was proposed for deprecation (issue opened 2025-09-23, closed as done 2025-11-05) [19] | Not enforced, but users still see Gatekeeper, so notarize anyway |
| Requirements | Upstream-published pre-built binary; a stable versioned download URL; `livecheck` (Sparkle strategy works); `auto_updates true` if the app has a working "Check for Updates..." [18][21] | Same file format; you maintain it |
| Install | `brew install --cask refined-settings` | `brew install --cask ikraam/tap/refined-settings` |
| Endorsement | Discoverable in `brew search` | "does not imply Homebrew endorsement or support" [17] |

LinearMouse's official cask is a good template: `livecheck` uses the `:sparkle` strategy on its appcast, with `auto_updates true`, `uninstall quit:` and `login_item:`, and `zap trash:` covering its config and prefs [26b]. Recommendation: ship a personal tap from day one. Submit to homebrew/cask once the repo passes 225 stars (or once someone else submits it at 75).

## 5. Competitive landscape

### 5a. All-in-one tweakers

| App | Price / licence | What it does well | Notes |
|---|---|---|---|
| TinkerTool (Bresink) [29] | Free, closed source | Per-user only, no admin rights, never changes OS components, reset to Apple defaults or the previous state | v11.72 (2026-11-02), separate generations per macOS |
| OnyX (Titanium) [30] | Free (donations), closed | Maintenance plus a "Parameters" tab for Finder, Dock and Safari | One build per major macOS: "There's a specific version of OnyX for each major operating system version." |
| Cocktail (Maintain) [31] | From 19 to 29 USD single user; Family, 10-pack and Business tiers | Maintenance, interface tweaks, scheduled "Pilot" mode | Separate versions per macOS |
| MacPilot (Koingo) [32] | Often sold as a lifetime licence (99 USD list, frequently discounted to about 30 USD); Lite on Mac App Store about 15 USD | Claims more than 1,200 hidden features | Some features dropped as macOS removes them [32] |
| PowerChest (new, 2026) [33][34] | Free, MIT, GitHub Releases | 159 curated settings; presets ("Developer Desk", "Clean Screenshots"); automatic snapshot before every change; change log with old/new value; aborts if the snapshot fails | macOS 26+; small project (7 stars); the closest analogue to Hidden Settings |
| Houston | 4.99 USD reported | | **Unverified**: the site didn't resolve; seen only in search snippets |
| Raycast "macOS Tweaks" extension [33] | Free | Copies the `defaults write` command for each tweak | Not an app |

**Unverified:** Titanium also offers a separate free "Maintenance" app (not checked).

### 5b. Mouse and scrolling

| App | Price / licence | Strengths | Notes |
|---|---|---|---|
| LinearMouse [26][35] | Free, **MIT** (about 7.1k stars) | Per-device, per-app and per-display profiles; separate natural scrolling for mouse vs trackpad; acceleration off; button remapping; Sparkle with a beta channel; official cask | Its own notices credit Firefox (curve reimplemented, MPL referenced, no code copied), libinput (MIT), Mac Mouse Fix (MIT v2 revision, "inspiration"), PermissionFlow (MIT), yabai (MIT) [36] |
| Mos [37] | Free, **CC BY-NC 4.0** (about 21.8k stars) | Smooth scrolling for wheels; per-app direction | NonCommercial licence: don't reuse its code in anything you might sell |
| Mac Mouse Fix [38][39] | 2.99 USD after a 30-day trial ("free days only used up when you actually use the app"); **MMF License** (source-available) | Smooth scrolling, button-hold gestures for Mission Control and Spaces, precise scroll and zoom modifiers | Derived programs may not be sold unless substantially new [39] |
| SteerMouse (Plentycom) [40] | About 20 USD one-time, 30-day trial (**unverified**: no official price page checked) | Deep per-button and per-device control, long track record | Closed |
| USB Overdrive [41] | About 20 USD shareware (**unverified** current price) | Mice, joysticks and gamepads | Last version 5.3.1 (2024-02), Sonoma listed |
| BetterTouchTool [42] | 15 USD (2 years of updates) or 25 USD lifetime | Everything: gestures, mouse buttons, keyboard, Touch Bar, window snapping | A large app; mouse is a small part |
| Scroll Reverser [35] | Free, Apache-2.0 | Per-device scroll direction, tiny | |
| UnnaturalScrollWheels [35] | Free, **GPL-3.0** | Reverses wheel direction while keeping natural trackpad scrolling | GPL: don't copy code into a non-GPL app |
| Logi Options+ [43] | Free, Logitech devices only | Device-specific features | Criticised as bloated; needs Accessibility, Input Monitoring and Bluetooth; an expired certificate stopped it launching (heise, early 2026, **date approximate**) |

### 5c. Links / browser pickers

| App | Price / licence | Rules | Modifiers | URL rewriting | Profiles |
|---|---|---|---|---|---|
| Velja [20] | 10 USD one-time, Mac App Store (current version needs macOS 26), free trial | GUI rules: "Source Apps", "URL Matchers", "URL Prefix", with a sample-URL tester; open in a browser, profile, app, prompt, Shortcut or web-wrapper app | Fn shows the prompt (or opens the alternative browser); Control opens in the background; Option adds copy and share; Command-click in the prompt creates a domain rule | Removes "more than 200" known tracking params; expands short and redirect URLs; per-rule JS "Transform URL"; optional global transform before rule matching | Chromium and Firefox-family; needs profile access granted; no Safari, Arc or Dia profiles |
| Finicky [44][45][46] | Free, **MIT**, about 5.3k stars; cask | JS/TS config at `~/.finicky.js`; `handlers` with wildcards (`"*.google.com*"`), regex or functions; `options.opener` gives the source app's `bundleId` | `finicky.getModifierKeys()` returns shift, option, command, control, capsLock and fn | `rewrite` rules run before handlers and receive standard `URL` objects | `"Google Chrome:Personal"` or `{ name, profile }` |
| Choosy [47] | 10 USD | Behaviour rules, prompt with all or only running browsers | **Unverified** | **Unverified** | Chrome, Edge, Brave, Vivaldi profiles and private windows |
| OpenIn 4 [23] | Paid (Lemon Squeezy), Mac App Store, Setapp; price not listed | Ordered rules per handler (browsers, mail, tel, files) by domain, path, modifier or source app; JS rule scripts | Command, Shift, Option, Fn, Control | App scripts and regex rewrites; sample script strips `utm_`, `fbclid` | Safari profiles; Chromium via an argument |
| Bumpr [48] | 2.99 USD (Mac App Store) | Simple picker for browser and mail | | | |
| Browserosaurus [35] | Free, GPL-3.0 | Picker at the cursor | | | **Archived** (last push 2025-08) |
| Newer small apps [49] | Various | BrowserPort, AltBrowse, Proxly, LinkLane, Openly | | | |

#### How Velja and Finicky implement the v2 features we want
- **Domain rules such as `*.atlassian.net` to the Chrome "Work" profile.**
  - Finicky: `{ match: "*.atlassian.net/*", browser: "Google Chrome:Work" }`. The profile can be given by its display name [46].
  - Velja: a rule whose "Open in" is the Chrome Work profile, with a URL Matcher pattern [20].
  - Lesson: let users pick the profile from a list, not type it. Velja reads the profiles once the user grants access [20]. Chrome's AppleScript can't target profiles, so launch Chrome with the profile directory as an argument [20].
- **Hold ⌥ to skip the picker.**
  - Velja uses Fn as its "alternative" modifier. It warns that some third-party keyboards don't send Fn/Globe correctly and suggests Option instead [20].
  - Finicky reads modifiers inside a browser function [46].
  - Read the modifier state at the moment the URL event arrives (`NSEvent.modifierFlags`, or `CGEventSource.flagsState(.combinedSessionState)`). Make the key configurable, with ⌥ as the default.
- **Stripping tracking parameters.**
  - Velja keeps a built-in list, applies it before rules, and expands short URLs first, because otherwise the parameters are hidden inside the redirect [20].
  - Finicky does it in user JS `rewrite` rules [44].
  - Order the pipeline: unwrap known redirect wrappers, then strip, then match rules, then open.

#### Tracking-parameter lists (with licence notes)
| List | Format | Licence | Notes |
|---|---|---|---|
| ClearURLs Rules [50] | `data.min.json`: 206 providers plus `globalRules` regexes (`utm_*`, `fbclid`, `gclid`, `_ga`, `_gl`, `srsltid`, ...) | **LGPL-3.0** | The most complete; includes per-site rules and redirect unwrapping. You can ship the JSON as a separate, replaceable data file with its licence (**unverified** legal view; LGPL obligations for data are unclear). |
| Brave query filter [51] | C++ set `kSimpleQueryStringTrackers` in brave-core, each entry linked to an issue; some scoped per site | MPL-2.0 (brave-core) | Conservative: only per-user and per-click IDs (`fbclid`, `gclid`, `msclkid`, `yclid`, `twclid`, `gbraid`, `wbraid`, ...); keeps URLs containing "unsubscribe" |
| Firefox query stripping [52] | Remote Settings collection `query-stripping` (3 records today: `gclid`, `dclid`, `msclkid`, `_hsenc`, `mc_eid`, `mkt_tok`, `fbclid`, ...) | Firefox code is MPL-2.0; the licence of the Remote Settings data is **unverified** | Firefox's strip-on-share list mixes an MPL list with an "LGPL licensed" one (likely ClearURLs, **unverified**) [52] |
| AdGuard URL Tracking filter | `$removeparam` rules | GPL-3.0 (AdguardFilters repo) | Large, but the GPL makes embedding awkward |
| Safari Link Tracking Protection [53] | Not published | n/a | On by default in Mail, Messages and Private Browsing (iOS 17 and macOS Sonoma); reportedly strips `gclid` and `fbclid` but not `utm_*` (one tester, anecdotal) |

Suggestion: hand-curate a small built-in MIT list of click IDs (the Brave/Firefox style: `gclid`, `dclid`, `gbraid`, `wbraid`, `fbclid`, `msclkid`, `yclid`, `twclid`, `mc_eid`, `_hsenc`, `mkt_tok`, `igshid`, `utm_*`). Parameter names are facts, not expression (**unverified** legal view). Offer ClearURLs as an optional, separately licensed rule set.

### 5d. Feature ideas and UX patterns worth stealing
1. **Snapshot and undo for every Hidden Setting** (PowerChest): store the old value before every write, keep a change log, abort if the snapshot fails, and offer "Reset to Apple default" per row and "Restore previous" globally (TinkerTool) [29][34].
2. **Presets**: bundles such as "Clean screenshots" or "Developer desk" applied in one click and undoable in one click [34].
3. **OS-version gating**: each Hidden Setting declares the macOS versions it is known to work on, and is hidden or flagged elsewhere. OnyX and Cocktail ship a separate build per macOS for this reason [30][31].
4. **Copy as Terminal command**: show the exact `defaults write` for each toggle (Raycast macOS Tweaks [33]). It builds trust and helps power users.
5. **Command-click in the picker creates a rule** for that domain (Velja [20]). It turns the picker into a rule editor with no settings screen.
6. **Rule tester and log**: paste a sample URL and see which rule matched, and keep a "recent links" log with source app and outcome (Velja [20]).
7. **Source-app rules** (links from Slack go to the Work profile): match on the opener's bundle ID (Velja, Finicky [20][46]).
8. **Separate scroll direction for mouse and trackpad, per device**: the single most requested mouse feature (LinearMouse, Scroll Reverser, UnnaturalScrollWheels [35]).
9. **Drag-to-authorize permission guide**: a floating panel next to System Settings that you drag the app icon into (LinearMouse adapts PermissionFlow, MIT [36]).
10. **Fair trial counting** if we ever charge: count only the days the app is actually used (Mac Mouse Fix [38]).

### 5e. Pitfalls others hit
- **Finicky v4 was a "complete rewrite"** (Go + Svelte + Objective-C by language stats) [45][54]:
  - The menu bar item was removed.
  - It runs on demand, which removed the URL-testing workflow.
  - The bundle ID changed from `net.kassett.finicky` to `se.johnste.finicky`, so default-browser and permission settings had to be granted again.
  - Update checks now call `finicky.johnste.se` [45].
  - On macOS Tahoe, links opened behind other windows when Finicky wasn't running. The fix was to make `keepRunning` default to true (4.2.2) [55].
  - Lessons: never change the bundle ID, and stay resident as an agent app.
- **Velja's limits** [20]:
  - It can't see links clicked inside browsers (that needs an extension).
  - It can't override Universal Links (needs an Apple entitlement it never got).
  - Slack redirect links that need a login token can't be resolved.
  - Source-app detection fails for Terminal and `open` without `--wait-apps`.
  - Profile access had to be granted again on macOS 27.
  - Focus Filters broke on macOS 26.5+.
  - The current version needs macOS 26, which strands users on older systems.
- **In-app sign-in (ASWebAuthenticationSession).** When an app starts an OAuth sign-in on macOS, the system opens the default browser only if it supports web authentication sessions, and Safari otherwise [56]. A picker that is the default browser but doesn't adopt `ASWebAuthenticationSessionWebBrowserSessionHandling` (macOS 10.15+) [57] sends those flows to Safari, which surprises users. Developers also report sessions landing in Safari with "User Cancelled" when Safari is running [56]. **Unverified:** how Velja handles this specifically.
  - For v2: either declare and implement the session handler and pass the request to the chosen browser, or document that sign-in windows open in Safari.
- **Accessibility "granted but not working"**: a stale TCC entry after an update. LinearMouse documents removing and re-adding the app, then `tccutil reset Accessibility <bundle id>` [27]. Signing with a stable Developer ID avoids most of this.
- **Licence traps in the mouse space**: Mos is NonCommercial, Mac Mouse Fix bars selling derived works, and UnnaturalScrollWheels and Browserosaurus are GPL [35][37][39]. LinearMouse is the safe source, and it avoids Firefox's MPL by reimplementing the curve rather than copying it [36].
- **Bloat and certificate expiry** (Logi Options+): users react badly to a background daemon for basic scrolling, and a lapsed signing certificate can brick the app [43]. Keep the app small, and watch your Developer ID certificate's expiry date (**unverified**: Developer ID certificates are valid for 5 years; timestamped signatures keep working after expiry).

## 6. Privacy and trust

### What to disclose
- **Network:** list every connection. Ideally there is one: the Sparkle appcast check to GitHub (it reveals IP address and app version through the HTTP request; Sparkle's exact User-Agent contents are **unverified**). State that system profiling is off [16]. If the Links module ever resolves short URLs over the network (as Velja does [20]), make that opt-in and disclose it, because it contacts the shortener with the link.
- **Analytics and crash reporting:** none. Say so outright, as PowerChest does ("No telemetry, no account required" [34]). Velja shows "No personal data collected" on its page [20].
- **What is stored:** settings in `~/Library/Preferences/<bundle id>.plist` and any logs, stored locally. LinearMouse's policy says logs leave the Mac only if the user attaches them to a bug report [58].
- **Permissions:** for each one, say why it's needed, what it allows, and how to revoke it.
  - LinearMouse's explanation is short ("requires accessibility features to work properly"). It shows the three-step grant flow with a video, and gives the `tccutil reset` fix [27].
  - Logitech publishes which features need which permission (Accessibility for scrolling and buttons, Input Monitoring for app features, Bluetooth for device detection) [43]. Do the same per module.
- **What changes in other apps' settings:** the Hidden Settings module writes Apple's preference domains. Say which ones, and that every change can be undone.

### Suggested README section

```markdown
## Privacy

Refined Settings runs entirely on your Mac.

- **No analytics, no tracking, no account.** The app has no analytics or crash-reporting SDKs.
- **One network request:** checking for updates. Refined Settings downloads a small
  update feed (`appcast.xml`) from GitHub. You can turn this off in Settings > Updates.
  No system information is sent.
- **Links stay local.** When Refined Settings is your default browser, links are matched
  against your rules on your Mac and handed straight to the browser you choose. Links
  are never sent anywhere or logged unless you turn on the local link history.
- **Your settings live in** `~/Library/Preferences/<bundle-id>.plist`. Hidden Settings
  changes are written to Apple's own preference files (for example `com.apple.dock`),
  and every change can be undone from the app.

### Permissions

| Permission | Why | Without it |
|---|---|---|
| Accessibility | Mouse & Scrolling reads and adjusts mouse and scroll events as they happen. Links uses it to pick a Safari profile from Safari's File menu. | Mouse & Scrolling is off, and Safari shows as one row in the picker; everything else works. |
| Default browser | Links opens each link in the browser or profile you choose. | Links is off. |

Revoke any permission in System Settings > Privacy & Security. If Accessibility looks
granted but mouse settings don't apply, remove Refined Settings from the list, add it
back, or run `tccutil reset Accessibility <bundle-id>`.
```

## 7. Licensing our own code

### What the borrowed MIT code requires
- The MIT condition: the copyright notice and permission notice "shall be included in all copies or substantial portions of the Software" (LinearMouse LICENSE, standard MIT text; Copyright (c) 2021-2024 LinearMouse [26c]). That applies to source and to binaries.
- In practice:
  1. Keep the original copyright header in each file you copy or adapt (LinearMouse's own files carry `// MIT License // Copyright (c) 2021-2026 LinearMouse` [26]).
  2. Add `THIRD_PARTY_NOTICES` (or `ThirdPartyNotices/` as LinearMouse does, a table plus one notice file per project [36]) with the full licence text of LinearMouse, Sparkle, and anything else you embed.
  3. Show the same text in the app: an **Acknowledgements** window reached from About, which reads the bundled notices file.
  4. **Chain-of-title check:** if you copy LinearMouse files that themselves adapt libinput, yabai or PermissionFlow code (all MIT), carry those notices too [36].
- **Sparkle's licence** is MIT, plus external licences for bundled components (for example a BSD-style licence for bsdiff by Colin Percival) [59]. Include Sparkle's whole LICENSE file in the notices.

### Options for Refined Settings' own code
| Option | Compatible with the MIT code we include? | Pros | Cons |
|---|---|---|---|
| **MIT** (recommended) | Yes | Matches LinearMouse, Finicky and PowerChest; easiest for contributors; Homebrew-friendly | Anyone can fork and sell it |
| Apache-2.0 | Yes | Explicit patent grant; NOTICE file convention | Slightly more process |
| GPL-3.0 | Yes (MIT code can be included in GPL work) | Forks must stay open | Blocks reuse in closed apps; can't take code from Mos or MMF either way |
| Source-available (for example PolyForm Noncommercial, or a custom licence like Mac Mouse Fix's) | Yes, but the MIT parts stay MIT | Protects a paid version | Not "open source"; contributors are wary; you must still keep the MIT notices |
| Closed source | Yes, as long as the notices ship in the app | Full control, easy to sell | Less trust for an app that asks for Accessibility; no community fixes |

**Do not** include code from Mos (CC BY-NC 4.0 [37]), Mac Mouse Fix (MMF License [39]), UnnaturalScrollWheels or Browserosaurus (GPL-3.0 [35]) unless you adopt licence terms compatible with theirs. Reading their behaviour and reimplementing it is a different matter from copying code (**unverified** legal advice; this is not legal advice).

---

## Sources

1. Apple, Guidelines for Using Apple Trademarks and Copyrights: https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
2. Apple, App Review Guidelines (4.1, 5.2.5, 2.4.5, 2.5.9): https://developer.apple.com/app-store/review/guidelines/
3. Apple, Apple Trademark List: https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html
4. Apple, Human Interface Guidelines, App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
5. Apple, App Store Marketing Guidelines: https://developer.apple.com/app-store/marketing/guidelines/
6. Apple, Rights and Permissions: https://www.apple.com/legal/copyright.html
7. Apple, Apple Developer Program, What's included: https://developer.apple.com/programs/whats-included/
8. Apple, Notarizing macOS software before distribution: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
8b. Apple, Customizing the notarization workflow: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
9. Apple, Hardened Runtime, and the `com.apple.security.automation.apple-events` entitlement: https://developer.apple.com/documentation/security/hardened-runtime and https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events
9b. Apple, NSAppleEventsUsageDescription: https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription
10. Apple, Developer ID: https://developer.apple.com/developer-id/
11. Apple Developer Forums (DTS), Accessibility and event taps in the sandbox: https://developer.apple.com/forums/thread/789896
12. Apple, App Sandbox Temporary Exception Entitlements: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html ; DTS on temporary exceptions outside the store: https://developer.apple.com/forums/thread/709333
13. Sparkle, Basic Setup: https://sparkle-project.org/documentation/ (source: https://github.com/sparkle-project/sparkle-project.github.io/blob/master/documentation/index.md)
13b. Sparkle, Publishing an update: https://sparkle-project.org/documentation/publishing/
14. Sparkle Package.swift and releases: https://github.com/sparkle-project/Sparkle/blob/2.x/Package.swift , https://github.com/sparkle-project/Sparkle/releases
15. Sparkle, Sandboxing (XPC services and manual signing): https://sparkle-project.org/documentation/sandboxing/
16. Sparkle, System Profiling: https://sparkle-project.org/documentation/system-profiling/
17. Homebrew, Package Acceptance Policy: https://docs.brew.sh/Package-Acceptance-Policy
18. Homebrew, Acceptable Casks: https://docs.brew.sh/Acceptable-Casks
19. Homebrew issue #20755, ending support for casks failing Gatekeeper: https://github.com/Homebrew/brew/issues/20755 ; discussion: https://github.com/orgs/Homebrew/discussions/7050
20. Velja product page and FAQ: https://sindresorhus.com/velja
21. Homebrew, Cask Cookbook (`auto_updates`, `livecheck`): https://docs.brew.sh/Cask-Cookbook
21b. Homebrew, Manpage (`--greedy`): https://docs.brew.sh/Manpage
22. Apple Developer News, Gatekeeper in macOS Sequoia (2024-08-06): https://developer.apple.com/news/?id=saqachfa ; AppleInsider: https://appleinsider.com/articles/24/08/06/apple-removes-control-click-option-for-skipping-gatekeeper-in-macos-sequoia
23. OpenIn 4: https://loshadki.app/openin4/
24. Apple Developer Forums, -1743 and hardened runtime Apple Events: https://developer.apple.com/forums/thread/133866 , https://developer.apple.com/forums/thread/106949
25. OpenClaw docs on TCC and ad-hoc signing (third party): https://docs.openclaw.ai/platforms/mac/permissions
26. LinearMouse repository (entitlements, AutoUpdateManager.swift): https://github.com/linearmouse/linearmouse
26b. Homebrew cask `linearmouse`: https://github.com/Homebrew/homebrew-cask/blob/main/Casks/l/linearmouse.rb
26c. LinearMouse LICENSE: https://github.com/linearmouse/linearmouse/blob/main/LICENSE
27. LinearMouse ACCESSIBILITY.md: https://github.com/linearmouse/linearmouse/blob/main/ACCESSIBILITY.md
28. create-dmg tools: https://github.com/sindresorhus/create-dmg , https://github.com/create-dmg/create-dmg
29. TinkerTool: https://www.bresink.com/osx/TinkerTool.html
30. OnyX: https://www.titanium-software.fr/en/onyx.html
31. Cocktail: https://www.maintain.se/cocktail/
32. MacPilot coverage: https://www.macworld.com/article/2968825/unlock-over-1200-hidden-macos-features-with-this-lifetime-macpilot-deal-for-27-97.html , https://apps.apple.com/iq/app/macpilot-lite/id415973444
33. Search results for newer tweak apps (PowerChest, Houston, Raycast macOS Tweaks): https://github.com/scripsweave/PowerChest , https://www.raycast.com/Undolog/macos-tweaks
34. PowerChest site: https://powerchest.app/
35. GitHub API repository metadata (stars, licences, archived state) for linearmouse, Mos, mac-mouse-fix, finicky, browserosaurus, UnnaturalScrollWheels, Scroll-Reverser, ClearURLs/Rules, checked 2026-11-08: https://github.com/linearmouse/linearmouse , https://github.com/Caldis/Mos , https://github.com/noah-nuebling/mac-mouse-fix , https://github.com/johnste/finicky , https://github.com/will-stone/browserosaurus , https://github.com/ther0n/UnnaturalScrollWheels , https://github.com/pilotmoon/Scroll-Reverser
36. LinearMouse ThirdPartyNotices: https://github.com/linearmouse/linearmouse/tree/main/LinearMouse/ThirdPartyNotices
37. Mos LICENSE (CC BY-NC 4.0): https://github.com/Caldis/Mos/blob/master/LICENSE
38. Mac Mouse Fix site: https://macmousefix.com/en/
39. Mac Mouse Fix License: https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License
40. SteerMouse listings: https://alternativeto.net/software/steermouse/about/ , https://formulae.brew.sh/cask/steermouse
41. USB Overdrive: https://www.usboverdrive.com/
42. BetterTouchTool pricing: https://folivora.ai/buy
43. Logi Options+: https://www.cultofmac.com/reviews/logi-options-plus-vs-bettermouse , https://heise.de/-11132623 , https://support.logi.com/hc/zh-cn/articles/1500005514962
44. Finicky README: https://github.com/johnste/finicky
45. Finicky wiki, Migrating from Finicky 3: https://github.com/johnste/finicky/wiki/Migrating-from-Finicky-3
46. Finicky wiki, Configuration (v4): https://github.com/johnste/finicky/wiki/Configuration-(v4)
47. Choosy: https://choosy.app/
48. Bumpr (Mac App Store): https://apps.apple.com/app/bumpr/id1166066070
49. Other pickers: https://apps.apple.com/ph/app/browserport/id6756837263 , https://apps.apple.com/app/id6756844413 , https://apps.apple.com/us/app/proxly/id6748143347 , https://github.com/estruyf/LinkLane
50. ClearURLs Rules (LGPL-3.0): https://github.com/ClearURLs/Rules
51. Brave Query String Filter: https://github.com/brave/brave-browser/wiki/Query-String-Filter , https://github.com/brave/brave-core (components/query_filter)
52. Firefox query stripping: https://firefox-source-docs.mozilla.org/toolkit/components/antitracking/anti-tracking/query-stripping/index.html , https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/query-stripping/records , https://searchfox.org/firefox-main/source/toolkit/components/antitracking/URLQueryStrippingListService.sys.mjs
53. Safari Link Tracking Protection: https://www.macrumors.com/2023/06/17/safari-link-tracking-protection/ , https://9to5mac.com/2023/06/08/ios-17-link-tracking-protection/
54. Finicky releases and languages (GitHub API): https://github.com/johnste/finicky/releases
55. Finicky issue #490: https://github.com/johnste/finicky/issues/490
56. Apple Developer Forums on ASWebAuthenticationSession and default browsers: https://developer.apple.com/forums/thread/786148 , https://developer.apple.com/forums/thread/724366
57. Apple, ASWebAuthenticationSessionWebBrowserSessionHandling: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsessionwebbrowsersessionhandling
58. LinearMouse privacy policy: https://linearmouse.app/privacy.html
59. Sparkle LICENSE: https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE
