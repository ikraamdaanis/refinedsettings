import AppKit
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @AppStorage(MenuBarIconSetting.key) private var showsMenuBarIcon = true
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var hasAccessibilityAccess = AXIsProcessTrusted()

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
            Section {
                Toggle("Launch at login", isOn: launchesAtLogin)
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
                Toggle("Show menu bar icon", isOn: $showsMenuBarIcon)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            } footer: {
                if !showsMenuBarIcon {
                    Text("To open Settings while the icon is hidden, open Refined Settings again from Applications or Spotlight.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if hasAccessibilityAccess {
                        Text("Allowed")
                    } else {
                        Button("Allow Access…") {
                            SafariProfiles.requestAccess()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
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
    }
}
