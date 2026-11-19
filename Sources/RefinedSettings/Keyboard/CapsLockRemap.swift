import Foundation
import IOKit
import IOKit.hidsystem

/// Turns Caps Lock into F18 below the event taps, the way `hidutil` does, so the super key tap gets a key it can hold
/// without Caps Lock switching itself on. Other key mappings stay as they are. Needs no permission: macOS only asks for
/// one when a letter or number key is remapped.
enum CapsLockRemap {
    /// HID usage page 7 (keyboard) codes, from the USB HID usage tables.
    private static let capsLockUsage: UInt64 = 0x7_0000_0039
    private static let f18Usage: UInt64 = 0x7_0000_006D
    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"
    /// Another tool's Caps Lock mapping (from `hidutil`, say) set aside while the super key has the key, so it comes
    /// back when the super key lets go.
    private static let displacedMappingKey = "displacedCapsLockMapping"
    /// What System Settings > Keyboard > Modifier Keys stores for each keyboard, in the current host's global domain.
    private static let modifierKeysPrefix = "com.apple.keyboard.modifiermapping."

    /// Adds or removes the mapping. The mapping outlives the app until you log out, so removing also clears one left
    /// behind by a copy that crashed.
    static func sync(isWanted: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let currentMappings = IOHIDEventSystemClientCopyProperty(client, kIOHIDUserKeyUsageMapKey as CFString) as? [[String: Any]] ?? []
        let isMapped = currentMappings.contains(where: isCapsLockToF18)

        guard isMapped != isWanted else { return }

        let otherMappings = currentMappings.filter { mapping in !isCapsLockToF18(mapping) }
        let updatedMappings: [[String: Any]]

        if isWanted {
            let displacedMapping = otherMappings.first { mapping in usage(mapping[sourceKey]) == capsLockUsage }
            UserDefaults.standard.set(displacedMapping, forKey: displacedMappingKey)
            let capsLockToF18: [String: Any] = [sourceKey: capsLockUsage, destinationKey: f18Usage]
            updatedMappings = otherMappings.filter { mapping in usage(mapping[sourceKey]) != capsLockUsage } + [capsLockToF18]
        } else {
            let displacedMapping = UserDefaults.standard.dictionary(forKey: displacedMappingKey)
            UserDefaults.standard.removeObject(forKey: displacedMappingKey)
            updatedMappings = otherMappings + [displacedMapping].compactMap { mapping in mapping }
        }

        IOHIDEventSystemClientSetProperty(client, kIOHIDUserKeyUsageMapKey as CFString, updatedMappings as CFArray)

        // macOS turns down the whole list without saying so if it remaps a letter or number key this app has no
        // permission for, so read it back.
        let appliedMappings = IOHIDEventSystemClientCopyProperty(client, kIOHIDUserKeyUsageMapKey as CFString) as? [[String: Any]] ?? []

        guard appliedMappings.contains(where: isCapsLockToF18) == isWanted else {
            log.error("Couldn't \(isWanted ? "remap" : "restore", privacy: .public) Caps Lock")

            return
        }

        // With the super key on Caps Lock, Caps Lock left on would have no way to come off unless tapping the super
        // key toggles it.
        if isWanted {
            withCapsLockState { _ in false }
        }
    }

    /// True when System Settings > Keyboard > Modifier Keys sends Caps Lock somewhere else on any keyboard. macOS
    /// applies that before this mapping, so Caps Lock never reaches it.
    static func isChangedInSystemSettings() -> Bool {
        guard let keys = CFPreferencesCopyKeyList(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? [String] else { return false }

        return keys.filter { key in key.hasPrefix(modifierKeysPrefix) }.contains { key in
            let mappings = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? [[String: Any]] ?? []

            return mappings.contains { mapping in usage(mapping[sourceKey]) == capsLockUsage && usage(mapping[destinationKey]) != capsLockUsage }
        }
    }

    /// Switches Caps Lock on or off, as pressing it would with no super key.
    static func toggleCapsLock() {
        withCapsLockState { isOn in !isOn }
    }

    /// Hands the current Caps Lock state to `change`, and sets it to what that returns.
    private static func withCapsLockState(_ change: (Bool) -> Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))

        guard service != 0 else { return }

        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0

        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return }

        defer { IOServiceClose(connection) }

        var isOn = false

        guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &isOn) == KERN_SUCCESS else { return }

        let wantsOn = change(isOn)

        guard wantsOn != isOn else { return }

        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), wantsOn)
    }

    private static func isCapsLockToF18(_ mapping: [String: Any]) -> Bool {
        usage(mapping[sourceKey]) == capsLockUsage && usage(mapping[destinationKey]) == f18Usage
    }

    private static func usage(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}
