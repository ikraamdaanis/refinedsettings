import AppKit
import Foundation
import SwiftUI

/// Reads through to macOS every time rather than keeping copies, so the page can't disagree with what is really set.
@MainActor
final class SystemPreferenceStore: ObservableObject {
    static let shared = SystemPreferenceStore()

    private static let tightMenuBarSpacing = 6

    var screenshotName: String? {
        SystemPreference.screenshotName.storedValue as? String
    }

    var usesTightMenuBar: Binding<Bool> {
        Binding(
            get: { self.isChanged(.menuBarItemSpacing) },
            set: { isOn in
                let value = isOn ? NSNumber(value: Self.tightMenuBarSpacing) : nil

                self.write(value, to: .menuBarItemSpacing)
                self.write(value, to: .menuBarItemPadding)
            }
        )
    }

    func isChanged(_ preference: SystemPreference) -> Bool {
        preference.storedValue != nil
    }

    func changedCount(in preferences: [SystemPreference]) -> Int {
        preferences.filter { preference in isChanged(preference) }.count
    }

    /// Terminal guides often store these as the text "YES", which macOS treats the same as a real boolean.
    func bool(_ preference: SystemPreference, whenUnset unsetValue: Bool) -> Bool {
        let storedValue = preference.storedValue

        if let text = storedValue as? String { return (text as NSString).boolValue }

        return storedValue as? Bool ?? unsetValue
    }

    func double(_ preference: SystemPreference, whenUnset unsetValue: Double) -> Double {
        preference.storedValue as? Double ?? unsetValue
    }

    func string(_ preference: SystemPreference, whenUnset unsetValue: String) -> String {
        preference.storedValue as? String ?? unsetValue
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

    func choiceBinding(for preference: SystemPreference, whenUnset unsetValue: String) -> Binding<String> {
        Binding(
            get: { self.string(preference, whenUnset: unsetValue) },
            set: { choice in self.write(choice == unsetValue ? nil : choice as CFString, to: preference) }
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

        if preference == .menuBarItemSpacing {
            write(nil, to: .menuBarItemPadding)
        }
    }

    func refresh() {
        objectWillChange.send()

        for preference in SystemPreference.everyPreference {
            preference.synchronize()
        }
    }

    /// True while the process that was running when one of its settings changed is still the one running.
    func needsRestart(_ app: RestartableApp) -> Bool {
        guard let running = running(app) else { return false }

        return UserDefaults.standard.integer(forKey: awaitingRestartKey(app)) == Int(running.processIdentifier)
    }

    /// launchd only brings these back after an unsuccessful exit, so a normal quit could leave them gone. This signals
    /// the one process by its ID, which is what `killall` does without matching on a name.
    func restart(_ app: RestartableApp) {
        guard let running = running(app) else { return }

        guard kill(running.processIdentifier, SIGTERM) == 0 else {
            log.error("Couldn't restart \(app.name, privacy: .public): \(String(cString: strerror(errno)), privacy: .public)")

            return
        }

        objectWillChange.send()
        UserDefaults.standard.removeObject(forKey: awaitingRestartKey(app))
    }

    private func running(_ app: RestartableApp) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.rawValue).first
    }

    private func awaitingRestartKey(_ app: RestartableApp) -> String {
        "systemPreferences.awaitingRestart.\(app.rawValue)"
    }

    private func write(_ value: CFPropertyList?, to preference: SystemPreference) {
        objectWillChange.send()

        guard preference.store(value) else {
            log.error("Couldn't save \(preference.key, privacy: .public)")

            return
        }

        if let app = preference.appNeedingRestart, let running = running(app) {
            UserDefaults.standard.set(Int(running.processIdentifier), forKey: awaitingRestartKey(app))
        }
    }
}
