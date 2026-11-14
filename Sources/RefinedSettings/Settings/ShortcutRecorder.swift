import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that records the next shortcut you type. Escape on its own cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: RecordedShortcut?
    @State private var monitor: Any?

    private var title: String {
        if monitor != nil { return "Type a Shortcut…" }

        return shortcut?.displayName ?? "Record Shortcut"
    }

    var body: some View {
        Button(title) {
            if monitor == nil {
                startRecording()
            } else {
                stopRecording()
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }

            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        monitor = nil
    }

    private func record(_ event: NSEvent) {
        let modifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(KeyPress.modifierMask)
        defer { stopRecording() }

        guard event.keyCode != kVK_Escape || !modifiers.subtracting(.maskSecondaryFn).isEmpty else { return }

        shortcut = RecordedShortcut(keyCode: event.keyCode, modifierBits: modifiers.rawValue, character: event.characters(byApplyingModifiers: []))
    }
}
