import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Whether a shortcut recorder is waiting for a shortcut. App shortcuts step aside meanwhile, so typing one you've
/// already set records it rather than opening its app.
@MainActor
enum ShortcutRecording {
    static let didChangeNotification = Notification.Name("com.ikraam.refinedsettings.shortcutRecordingDidChange")
    private static var activeCount = 0

    static var isActive: Bool {
        activeCount > 0
    }

    static func begin() {
        activeCount += 1
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func end() {
        activeCount = max(activeCount - 1, 0)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

/// A button that records the next shortcut you type. Escape on its own cancels. A shortcut `isAllowed` turns down
/// gets a beep, and recording carries on.
struct ShortcutRecorder: View {
    @Binding var shortcut: RecordedShortcut?
    var isAllowed: (RecordedShortcut) -> Bool = { _ in true }
    @State private var monitor: Any?

    private var title: String {
        if monitor != nil { return "Type a Shortcut…" }

        return shortcut?.displayName ?? "Record Shortcut"
    }

    var body: some View {
        Button {
            if monitor == nil {
                startRecording()
            } else {
                stopRecording()
            }
        } label: {
            // Wide enough for most shortcuts, so a column of them lines up.
            Text(title)
                .frame(minWidth: 72)
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        // The app shortcuts are let go first, or a shortcut already in use would never reach the monitor.
        ShortcutRecording.begin()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }

            return nil
        }
    }

    private func stopRecording() {
        guard let monitor else { return }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        ShortcutRecording.end()
    }

    private func record(_ event: NSEvent) {
        let modifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(KeyPress.modifierMask)

        guard event.keyCode != kVK_Escape || !modifiers.subtracting(.maskSecondaryFn).isEmpty else {
            stopRecording()

            return
        }

        let recordedShortcut = RecordedShortcut(keyCode: event.keyCode, modifierBits: modifiers.rawValue, character: event.characters(byApplyingModifiers: []))

        guard isAllowed(recordedShortcut) else {
            NSSound.beep()

            return
        }

        shortcut = recordedShortcut
        stopRecording()
    }
}
