import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

/// Adds the super modifiers to every key while the super key is held, and swallows the super key itself. Only the tap
/// thread touches the state here, apart from `isInterrupted`.
final class SuperKey: @unchecked Sendable {
    /// A press on its own that's held longer than this counts as changing your mind, so it does nothing.
    private static let longestTap: TimeInterval = 0.5
    private static let modifierFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    /// Each modifier with the bits a keyboard sets beside it for the left and right keys (`NX_DEVICE…KEYMASK` in
    /// IOLLEvent.h). A modifier added by software, as this tap adds the super modifiers, has neither.
    private static let sideBits: [(modifier: CGEventFlags, sides: CGEventFlags)] = [
        (.maskControl, CGEventFlags(rawValue: 0x0001 | 0x2000)),
        (.maskShift, CGEventFlags(rawValue: 0x0002 | 0x0004)),
        (.maskAlternate, CGEventFlags(rawValue: 0x0020 | 0x0040)),
        (.maskCommand, CGEventFlags(rawValue: 0x0008 | 0x0010)),
    ]
    private static let allSideBits = sideBits.reduce(CGEventFlags()) { combined, modifier in combined.union(modifier.sides) }
    private static let keyEventTypes: Set<CGEventType> = [.keyDown, .keyUp, .flagsChanged]

    /// The super key while it's down, kept as it was pressed, so its release matches even if the setting changes.
    private var heldKey: SuperKeyChoice?
    private var pressedAt: TimeInterval = 0
    private var wasCombined = false
    /// Set once Secure Input comes on while the key is held. macOS hides keys from every tap until it goes off again,
    /// so the release may happen out of sight.
    private let isInterrupted = OSAllocatedUnfairLock(initialState: false)
    private var secureInputWatch: Task<Void, Never>?

    static func makeTap() -> EventTap {
        let superKey = SuperKey()

        return EventTap(
            location: .cghidEventTap,
            eventTypes: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown],
            threadName: "com.ikraam.refinedsettings.super-key-tap"
        ) { type, event in
            superKey.shouldKeep(type, event)
        }
    }

    private func shouldKeep(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard let choice = heldKey ?? SuperKeySetting.key else { return true }

        let isKeyEvent = Self.keyEventTypes.contains(type)

        if isKeyEvent && event.getIntegerValueField(.keyboardEventKeycode) == Int64(choice.keyCode) {
            handleSuperKey(choice, type: type, event: event)

            return false
        }

        guard heldKey != nil else { return true }

        // A release this tap never saw, such as one made while Secure Input hid keys from it, would otherwise leave
        // every key after it holding the super modifiers.
        guard isStillDown(choice, flags: event.flags) else {
            stopHolding(flags: event.flags)

            return true
        }

        if type == .keyDown || !isKeyEvent {
            wasCombined = true
        }

        // A click only counts as using the key, and keeps just the modifiers really held. With ⌃ added, AppKit would
        // take it for a right-click.
        let heldFlags = withoutSuperKey(event.flags, heldKey: choice)
        event.flags = isKeyEvent ? heldFlags.union(SuperKeySetting.flags) : heldFlags

        return true
    }

    private func handleSuperKey(_ choice: SuperKeyChoice, type: CGEventType, event: CGEvent) {
        let isDown: Bool

        if let modifierKey = choice.modifierKey {
            guard type == .flagsChanged else { return }

            isDown = event.flags.contains(modifierKey.flags.subtracting(Self.modifierFlags))
        } else {
            guard type != .flagsChanged else { return }

            isDown = type == .keyDown
        }

        if isDown {
            press(choice)
        } else {
            release(flags: event.flags)
        }
    }

    /// Key repeats arrive as more presses, and change nothing.
    private func press(_ choice: SuperKeyChoice) {
        guard heldKey == nil else { return }

        heldKey = choice
        pressedAt = ProcessInfo.processInfo.systemUptime
        wasCombined = false
        watchForSecureInput()
    }

    private func release(flags: CGEventFlags) {
        guard heldKey != nil else { return }

        stopHolding(flags: flags)

        guard !wasCombined, ProcessInfo.processInfo.systemUptime - pressedAt <= Self.longestTap else { return }

        switch SuperKeySetting.tapAction {
        case .nothing:
            break
        case .escape:
            KeyPress.post(keyCode: CGKeyCode(kVK_Escape), modifiers: [])
        case .capsLock:
            CapsLockRemap.toggleCapsLock()
        }
    }

    private func stopHolding(flags: CGEventFlags) {
        heldKey = nil
        secureInputWatch?.cancel()
        secureInputWatch = nil
        restoreModifierState(from: flags)
    }

    /// macOS takes the modifier state from the flags of the keys that pass, so after a shortcut it still counts the
    /// super modifiers as held: a click straight after could arrive as a ⌃-click, and `NSEvent.modifierFlags` would
    /// say ⌃⌥⌘. The super key's own release is swallowed, so a modifier release stands in for it.
    private func restoreModifierState(from flags: CGEventFlags) {
        let heldFlags = Self.physicalFlags(flags).intersection(Self.modifierFlags.union(Self.allSideBits))

        guard CGEventSource.flagsState(.hidSystemState).intersection(Self.modifierFlags) != heldFlags.intersection(Self.modifierFlags) else { return }

        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        event?.type = .flagsChanged
        event?.flags = heldFlags.union(.maskNonCoalesced)
        event?.post(tap: .cghidEventTap)
    }

    /// Only while the key is held, so nothing polls the rest of the time.
    private func watchForSecureInput() {
        isInterrupted.withLock { interrupted in interrupted = false }
        secureInputWatch?.cancel()
        secureInputWatch = Task.detached(priority: .utility) { [isInterrupted] in
            while !Task.isCancelled {
                if IsSecureEventInputEnabled() {
                    isInterrupted.withLock { interrupted in interrupted = true }

                    return
                }

                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// A modifier's own flag says whether it's down. F18 has none, and the HID state counts it as up once this tap has
    /// swallowed it, so for Caps Lock the best sign of a lost release is Secure Input having hidden it.
    private func isStillDown(_ choice: SuperKeyChoice, flags: CGEventFlags) -> Bool {
        guard let modifierKey = choice.modifierKey else { return !isInterrupted.withLock { interrupted in interrupted } }

        return flags.contains(modifierKey.flags.subtracting(Self.modifierFlags))
    }

    /// The modifiers really held besides the super key. A modifier used as the super key stands for the super
    /// modifiers alone, so its own side's bit comes out, and with it the modifier unless the other side's key is down.
    private func withoutSuperKey(_ flags: CGEventFlags, heldKey: SuperKeyChoice) -> CGEventFlags {
        let ownSide = heldKey.modifierKey.map { modifierKey in modifierKey.flags.subtracting(Self.modifierFlags) } ?? []

        return Self.physicalFlags(flags.subtracting(ownSide))
    }

    /// The flags with only the modifiers whose keys are down: a modifier without a side bit was added by software.
    private static func physicalFlags(_ flags: CGEventFlags) -> CGEventFlags {
        sideBits.reduce(flags) { physical, modifier in
            flags.intersection(modifier.sides).isEmpty ? physical.subtracting(modifier.modifier) : physical
        }
    }
}
