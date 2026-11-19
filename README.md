# Refined Settings

Refined Settings for Mac: small system tweaks in one menu bar app, for macOS 13+.

Today it handles links, your mouse's scrolling direction and buttons, cycling through a desktop's windows, a super key, app shortcuts and options macOS has but doesn't show, placed where System Settings would put them. Set it as the default browser and every link opens an "Open Link" window in the centre of the screen, listing each installed browser, and each profile for Chrome-family browsers, Ardia, Firefox (only Firefox profiles that have been used) and Safari (once there's more than one). More of these options and more mouse settings are planned; the research behind them is in [docs](docs/README.md).

Press `1` to `9` to open straight away, or pick with the arrow keys and press Return, double-click a row, or click Open. Press `Esc`, click Cancel or the close button, or click outside the window to cancel.

## Build and install

```bash
./build.sh
```

Compiles a release build with the Command Line Tools, assembles `Refined Settings.app`, signs it, installs it to `/Applications` and registers it with Launch Services.

It signs with the first Apple Development certificate in your keychain, so every build has the same identity and macOS keeps Refined Settings' Accessibility permission across rebuilds. Set `REFINEDSETTINGS_SIGN_IDENTITY` to pick a different identity (needed if you have more than one, so the choice can't change between builds). With no certificate it signs ad-hoc, and the permission needs granting again after each build.

## Set up

1. Open **System Settings > Desktop & Dock > Default web browser** and choose **Refined Settings** (or click **Set as Default…** under **Links** in Refined Settings' Settings and confirm the macOS prompt).
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

## Ardia profiles

Ardia runs on Chromium but keeps its own list of profiles, so `--profile-directory` doesn't reach them. Refined Settings reads the profiles from Ardia's `session.json` and opens a link through Ardia's AppleScript: it shows the picked profile in Ardia's front window, then opens the link as a new tab there. The first time, macOS asks to let Refined Settings control Ardia; if that's refused, it can be switched back on in **System Settings > Privacy & Security > Automation**.

## Mouse

**Mouse** in Settings shows your connected mouse and can reverse its vertical and horizontal scrolling separately, without changing your trackpad. It needs Accessibility access, and the event tap only runs while a switch is on. Don't reverse the same mouse in another app as well, or the two cancel out. The approach comes from [LinearMouse](https://github.com/linearmouse/linearmouse).

Under **Buttons**, a tester lights up each button and wheel as macOS receives it while the pointer is over the Settings window, so you can see which buttons reach your Mac at all. Buttons past the usual five show up there once pressed. The middle, back and forward buttons, and any extra ones, can each be set to Nothing, Back, Forward, Mission Control, App Windows, Show Desktop, a recorded keyboard shortcut or a modifier key such as Right Command, picked from a list, which stays down for as long as the button is held. Back and forward press ⌘[ and ⌘], except in Chromium browsers, Firefox, VS Code and Cursor, which already handle the side buttons, so there they pass straight through. Remapping needs Accessibility access, and its event tap only runs while a button has an action. Some buttons, such as a Logitech mouse's gesture button, only talk to the maker's own software and never reach macOS.

## Desktops

If you use the **Switch to Desktop N** shortcuts (**System Settings > Keyboard > Keyboard Shortcuts > Mission Control**), **Cycle through windows** under **Desktop & Dock** in Settings makes the shortcut for the desktop you're already on rotate through that desktop's windows, starting from the one at the back. Shortcuts for other desktops still switch desktops. It needs Accessibility access to bring windows forward. While the switch is on, the app registers only the current desktop's shortcut as a hot key and moves it when you change desktops, so it doesn't read your typing, and it keeps working when an app turns on Secure Input for a password field.

## Super key and app shortcuts

Under **Keyboard**, **Super key** turns Caps Lock or a right-hand modifier into a key that holds ⌃⌥⌘ for as long as it's down (⌃⌥⇧⌘ with **Include Shift** on, which is off by default because macOS keeps a few ⌃⌥⇧⌘ shortcuts for itself). Apps leave those combinations free, so shortcuts made with it don't clash. Tapped on its own it can do nothing, press Escape or switch Caps Lock on and off. Clicks while it's held stay plain clicks, since ⌃-click is a right-click.

For Caps Lock, Refined Settings maps the key to F18 the way `hidutil` does, since an event tap can't stop Caps Lock switching on. It sets aside any other Caps Lock mapping while it does, and puts everything back when the super key is turned off or the app quits. If Caps Lock is changed under **System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys**, macOS applies that first and the super key never sees it, so Settings asks you to set it back. The super key needs Accessibility access, and like any event tap it can't see keys typed into a password field.

**App Shortcuts** gives apps a shortcut that opens them or brings them to the front if they're running. Pressed again, it brings the app's other windows forward one at a time, such as each Chrome profile's window, switching desktops when a window is on another one and skipping minimized windows, and goes round them again once each has had a turn. It never hides the app or sends you back to the one you were in. Give several apps the same shortcut and each press moves on to the next one, in the list's order, after the app in front has shown its windows; drag the rows to change the order. These are hot keys, so they need no permission and work anywhere, though going through an app's windows needs Accessibility access; without it each press goes straight to the next app. A shortcut needs ⌃ or ⌘ (or a function key), so it can't get in the way of typing.

## Options macOS doesn't show

Settings is organised like System Settings, so these sit with the things they relate to:

- **General** sets whether windows reopen when you log back in.
- **Desktop & Dock** sets how quickly an auto-hiding Dock appears, dims hidden apps, locks the Dock's size, items or position, and lets ⌃⌘ drag a window from anywhere.
- **Menu Bar** turns off the icons macOS 26 added to menus and tightens the spacing of menu bar icons.
- **Finder** shows the full path and hidden files, picks the default folder and search views, and stops `.DS_Store` files on network drives.
- **Screenshots** sets the file format, window shadow and file name.
- **Keyboard** sets whether holding a key repeats it, how fast it repeats (including faster than System Settings goes), and controls smart quotes and smart dashes separately.

Each row's reset button deletes the preference, so the macOS default comes back. Dock and Finder changes wait for their **Restart** button, and open apps need reopening to pick up window dragging, menu and keyboard changes. Some options, such as menu bar spacing, key repeat speed and `.DS_Store` files, need you to log out and back in. No permissions are needed.

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
