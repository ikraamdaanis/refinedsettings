import AppKit
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @AppStorage(MenuBarIconSetting.key) private var showsMenuBarIcon = true
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var hasAccessibilityAccess = AXIsProcessTrusted()
    @State private var defaultBrowserURL = AppInfo.defaultBrowserURL()
    @ObservedObject private var systemPreferences = SystemPreferenceStore.shared

    /// Registering from anywhere else (a build folder, say) would add a second entry to Login Items.
    private var isInstalled: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    private var launchesAtLogin: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
            set: { isOn in setLaunchesAtLogin(isOn) }
        )
    }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .general)
            }
            Section("Features") {
                FeatureRow(pane: .desktopAndDock, status: DesktopCyclingSetting.isOn || systemPreferences.changedCount(in: SystemPreference.dockPreferences) > 0 ? "On" : "Off")
                FeatureRow(pane: .links, status: AppInfo.isDefaultBrowser(defaultBrowserURL) ? "On" : "Needs Setup")
                FeatureRow(pane: .screenshots, status: changeSummary(of: SystemPreference.screenshotPreferences))
                FeatureRow(pane: .keyboard, status: changeSummary(of: SystemPreference.keyboardPreferences))
                FeatureRow(pane: .mouse, status: MouseScrollSetting.reversesAnyAxis ? "On" : "Off")
            }
            Section("App") {
                Toggle(isOn: launchesAtLogin) {
                    Text("Launch at login")
                    Text("Keeps your mouse and desktop settings working after you restart your Mac.")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isInstalled)
                if loginItemStatus == .requiresApproval {
                    LabeledContent("Waiting for your approval in Login Items") {
                        Button("Open Login Items…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
                Toggle(isOn: $showsMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text(showsMenuBarIcon ? "A quick way to open these settings." : "To open these settings while the icon is hidden, open Refined Settings again from Applications or Spotlight.")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            Section("Permissions") {
                LabeledContent {
                    if hasAccessibilityAccess {
                        Text("Allowed")
                    } else {
                        Button("Allow Access…") {
                            SafariProfiles.requestAccess()
                        }
                    }
                } label: {
                    Text("Accessibility")
                    Text("Needed to change mouse scrolling, respond to desktop shortcuts and open Safari profiles. Only the features you turn on use it.")
                }
            }
        }
        .paneFormStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func changeSummary(of preferences: [SystemPreference]) -> String {
        let changedCount = systemPreferences.changedCount(in: preferences)

        return changedCount == 0 ? "Default" : "\(changedCount) Changed"
    }

    private func setLaunchesAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Couldn't change launch at login: \(error.localizedDescription, privacy: .public)")
        }

        loginItemStatus = SMAppService.mainApp.status
    }

    private func refresh() {
        loginItemStatus = SMAppService.mainApp.status
        hasAccessibilityAccess = AXIsProcessTrusted()
        defaultBrowserURL = AppInfo.defaultBrowserURL()
        systemPreferences.refresh()
    }
}
