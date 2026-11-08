# Refined Settings

Refined Settings for Mac: small system tweaks in one menu bar app, for macOS 13+.

Today it does one thing, links. Set it as the default browser and every link opens an "Open Link" window in the centre of the screen, listing each installed browser, and each profile for Chrome-family browsers, Firefox (only Firefox profiles that have been used) and Safari (once there's more than one). Mouse & Scrolling and Hidden Settings are planned; the research behind them is in [docs](docs/README.md).

Press `1` to `9` to open straight away, or pick with the arrow keys and press Return, double-click a row, or click Open. Press `Esc`, click Cancel or the close button, or click outside the window to cancel.

## Build and install

```bash
./build.sh
```

Compiles a release build with the Command Line Tools, assembles `Refined Settings.app`, signs it, installs it to `/Applications` and registers it with Launch Services.

It signs with the first Apple Development certificate in your keychain, so every build has the same identity and macOS keeps Refined Settings' Accessibility permission across rebuilds. Set `REFINEDSETTINGS_SIGN_IDENTITY` to pick a different identity (needed if you have more than one, so the choice can't change between builds). With no certificate it signs ad-hoc, and the permission needs granting again after each build.

## Set up

1. Open **System Settings > Desktop & Dock > Default web browser** and choose **Refined Settings** (or use **Use Refined Settings** in Refined Settings' Settings and confirm the macOS prompt).
2. Optional: click the menu bar icon and choose **Settings…**. Settings opens on the current desktop, and Refined Settings shows in the Dock while it's open, so you can assign it to a specific desktop from the Dock icon's **Options** menu. The list under **Links** matches the picker row for row: drag rows (or right-click one) to change the order, and switch off any browser or profile you don't want to see.

## Moving from Linkguide

Refined Settings used to be called Linkguide. On first launch it copies Linkguide's browser order, hidden rows and Safari profiles, so the picker looks the same. macOS treats it as a new app, so:

1. Make Refined Settings the default browser (see Set up).
2. Allow Accessibility again if you use Safari profiles (see below).
3. Quit Linkguide, then remove it so it stops offering itself as a browser:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/Linkguide.app
rm -rf /Applications/Linkguide.app
defaults delete com.ikraam.linkguide
```

## Safari profiles

Safari has no way for another app to open a link in a given profile, so Refined Settings uses Safari's own menu through the Accessibility API. It reads the profiles from the File menu's **New … Window** items. To open a link, it brings a window of that profile to the front (opening one if there's none), then hands Safari the link, which Safari opens in the profile in front.

This needs Accessibility access: click **Allow Access…** in Refined Settings' Settings, then switch Refined Settings on in **System Settings > Privacy & Security > Accessibility**. Without it, Safari shows as a single row and opens links in whichever profile it picks. Refined Settings remembers the profiles for when Safari isn't running, and updates the list each time it can read Safari's menu.

## Known limitation

In-app sign-in windows (apps using `ASWebAuthenticationSession`, such as a mail app's Google sign-in) open in Safari while Refined Settings is the default browser. macOS only hands those to a browser that can finish the sign-in itself, which a picker that forwards links can't do.

## Uninstall

1. Set another default browser in **System Settings > Desktop & Dock > Default web browser**.
2. Quit Refined Settings from its menu bar icon.
3. Remove the app and its preferences:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/Applications/Refined Settings.app"
rm -rf "/Applications/Refined Settings.app"
defaults delete com.ikraam.refinedsettings
```

Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.
