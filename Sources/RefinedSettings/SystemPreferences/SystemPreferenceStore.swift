import AppKit
import Foundation
import SwiftUI

/// Reads through to macOS every time rather than keeping copies, so the page can't disagree with what is really set.
@MainActor
final class SystemPreferenceStore: ObservableObject {
    static let shared = SystemPreferenceStore()

    /// The Dock process running when a Dock setting last changed. If that one is still running, it hasn't applied it.
    private static let dockAwaitingRestartKey = "systemPreferences.dockProcessAwaitingRestart"
    private static let dockBundleIdentifier = "com.apple.dock"

    private var runningDock: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleIdentifier).first
    }

    var needsDockRestart: Bool {
        guard let runningDock else { return false }

        return UserDefaults.standard.integer(forKey: Self.dockAwaitingRestartKey) == Int(runningDock.processIdentifier)
    }

    var screenshotFormat: ScreenshotFormat {
        guard let stored = SystemPreference.screenshotFormat.storedValue as? String else { return .macOSDefault }

        return ScreenshotFormat(rawValue: stored) ?? .macOSDefault
    }

    var screenshotName: String? {
        SystemPreference.screenshotName.storedValue as? String
    }

    func isChanged(_ preference: SystemPreference) -> Bool {
        preference.storedValue != nil
    }

    func changedCount(in preferences: [SystemPreference]) -> Int {
        preferences.filter { preference in isChanged(preference) }.count
    }

    func bool(_ preference: SystemPreference, whenUnset unsetValue: Bool) -> Bool {
        preference.storedValue as? Bool ?? unsetValue
    }

    func double(_ preference: SystemPreference, whenUnset unsetValue: Double) -> Double {
        preference.storedValue as? Double ?? unsetValue
    }

    /// A switch that is on when the preference holds `valueWhenOn`. Moving it to the macOS default deletes the key, so
    /// only settings that differ from macOS count as changed.
    func switchBinding(for preference: SystemPreference, whenUnset unsetValue: Bool, valueWhenOn: Bool = true) -> Binding<Bool> {
        Binding(
            get: { self.bool(preference, whenUnset: unsetValue) == valueWhenOn },
            set: { isOn in
                let newValue = isOn == valueWhenOn

                self.write(newValue == unsetValue ? nil : NSNumber(value: newValue), to: preference)
            }
        )
    }

    func sliderBinding(for preference: SystemPreference, whenUnset unsetValue: Double) -> Binding<Double> {
        Binding(
            get: { self.double(preference, whenUnset: unsetValue) },
            set: { newValue in self.write(NSNumber(value: newValue), to: preference) }
        )
    }

    var screenshotFormatBinding: Binding<ScreenshotFormat> {
        Binding(
            get: { self.screenshotFormat },
            set: { format in self.write(format == .macOSDefault ? nil : format.rawValue as CFString, to: .screenshotFormat) }
        )
    }

    /// Slashes and colons can't be used in a file name. A blank name goes back to macOS's own, in the user's language.
    func cleanedScreenshotName(_ name: String) -> String? {
        let cleaned = name
            .filter { character in character != "/" && character != ":" }
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    func setScreenshotName(_ name: String) {
        let cleaned = cleanedScreenshotName(name)

        guard cleaned != screenshotName else { return }

        write(cleaned.map { cleanedName in cleanedName as CFString }, to: .screenshotName)
    }

    func reset(_ preference: SystemPreference) {
        write(nil, to: preference)
    }

    func refresh() {
        objectWillChange.send()

        for preference in SystemPreference.screenshotPreferences + SystemPreference.dockPreferences + SystemPreference.keyboardPreferences + [.dockAutohide] {
            preference.synchronize()
        }
    }

    /// launchd only brings the Dock back after an unsuccessful exit, so a normal quit would leave it gone. This signals
    /// the one process by its ID, which is what `killall Dock` does without matching on a name.
    func restartDock() {
        guard let runningDock else { return }

        guard kill(runningDock.processIdentifier, SIGTERM) == 0 else {
            log.error("Couldn't restart the Dock: \(String(cString: strerror(errno)), privacy: .public)")

            return
        }

        objectWillChange.send()
        UserDefaults.standard.removeObject(forKey: Self.dockAwaitingRestartKey)
    }

    private func write(_ value: CFPropertyList?, to preference: SystemPreference) {
        objectWillChange.send()

        guard preference.store(value) else {
            log.error("Couldn't save \(preference.key, privacy: .public)")

            return
        }

        if preference.isDockPreference, let runningDock {
            UserDefaults.standard.set(Int(runningDock.processIdentifier), forKey: Self.dockAwaitingRestartKey)
        }
    }
}
