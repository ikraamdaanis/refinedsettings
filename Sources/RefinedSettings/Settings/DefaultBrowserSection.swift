import AppKit
import SwiftUI

/// Leads the Links pane because nothing else on it takes effect until Refined Settings is the default browser.
struct DefaultBrowserSection: View {
    let defaultBrowserURL: URL?
    let refresh: () -> Void

    private var isDefault: Bool {
        AppInfo.isDefaultBrowser(defaultBrowserURL)
    }

    private var currentBrowserSentence: String {
        guard let defaultBrowserURL else { return "" }

        return "Links open in \(AppInfo.name(of: defaultBrowserURL)) right now. "
    }

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isDefault ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(isDefault ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDefault ? "Refined Settings is your default browser" : "Make this your default browser")
                    Text(isDefault ? "Click a link in an app such as Mail or Messages and a small window asks which browser or profile to open it in. Links inside a browser stay in that browser." : "\(currentBrowserSentence)macOS only sends links to your default browser, so Refined Settings has to be the default before it can ask where each one should go. Your browsers stay as they are.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 12)
                if !isDefault {
                    Button("Set as Default…") {
                        Task {
                            await AppInfo.makeRefinedSettingsDefaultBrowser()
                            refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            LabeledContent {
                Button("Try It", action: showSamplePicker)
            } label: {
                Text("See what it looks like")
                Text("Shows the window you get when you click a link, using a sample link.")
            }
            if isDefault {
                LabeledContent {
                    Button("Open Desktop & Dock…") {
                        AppInfo.openSystemSettings(paneID: "com.apple.Desktop-Settings.extension")
                    }
                } label: {
                    Text("Stop choosing for every link")
                    Text("Pick another default web browser in System Settings.")
                }
            }
        }
    }

    private func showSamplePicker() {
        guard let sampleLink = URL(string: "https://example.com") else { return }

        NSWorkspace.shared.open([sampleLink], withApplicationAt: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
