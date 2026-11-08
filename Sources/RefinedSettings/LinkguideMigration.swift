import Foundation

/// Refined Settings used to be Linkguide (`com.ikraam.linkguide`). On first launch it copies the browser order,
/// the hidden rows and the remembered Safari profiles over, so the picker looks the same as before.
enum LinkguideMigration {
    private static let legacyDomain = "com.ikraam.linkguide"
    private static let completedKey = "didMigrateFromLinkguide"
    private static let keys = ["entryOrder", "hiddenEntryIDs", "safariProfileNames"]

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completedKey) else { return }

        // persistentDomain(forName:) returns only what Linkguide stored, not this app's registered defaults.
        let legacyValues = defaults.persistentDomain(forName: legacyDomain) ?? [:]

        for key in keys where defaults.object(forKey: key) == nil {
            guard let value = legacyValues[key] else { continue }

            defaults.set(value, forKey: key)
        }

        defaults.set(true, forKey: completedKey)

        if !legacyValues.isEmpty {
            log.info("Moved Linkguide's settings over")
        }
    }
}
