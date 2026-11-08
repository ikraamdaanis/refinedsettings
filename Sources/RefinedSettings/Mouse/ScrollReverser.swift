import CoreGraphics
import Foundation
import IOKit

// Private functions that LinearMouse and Scroll Reverser also rely on: the HID event inside a CGEvent is the only
// way to tell which device an event came from.
@_silgen_name("CGEventCopyIOHIDEvent")
private func copyHIDEvent(_ event: CGEvent) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetSenderID")
private func senderID(of hidEvent: CFTypeRef) -> UInt64

@_silgen_name("IOHIDEventGetFloatValue")
private func floatValue(of hidEvent: CFTypeRef, field: UInt32) -> Double

@_silgen_name("IOHIDEventSetFloatValue")
private func setFloatValue(of hidEvent: CFTypeRef, field: UInt32, value: Double)

private let hidScrollFieldX: UInt32 = 6 << 16
private let hidScrollFieldY: UInt32 = 6 << 16 | 1

/// Flips scrolling from mice, per axis, and leaves every other device alone. Only the tap thread touches `isMouseBySender`.
final class ScrollReverser: @unchecked Sendable {
    private var isMouseBySender: [UInt64: Bool] = [:]

    static func makeTap() -> EventTap {
        let reverser = ScrollReverser()

        return EventTap(location: .cghidEventTap, eventType: .scrollWheel, threadName: "com.ikraam.refinedsettings.scroll-tap") { event in
            reverser.reverseIfFromMouse(event)

            return true
        }
    }

    private func reverseIfFromMouse(_ event: CGEvent) {
        // Events posted by apps carry no HID event, and have no direction of their own to correct.
        guard let hidEvent = copyHIDEvent(event)?.takeRetainedValue() else { return }
        guard isMouse(sender: senderID(of: hidEvent)) else { return }

        reverse(event, hidEvent: hidEvent)
    }

    private func isMouse(sender: UInt64) -> Bool {
        if let isMouse = isMouseBySender[sender] { return isMouse }

        // A sender that can't be found yet isn't remembered, so it gets looked up again.
        guard let isMouse = MouseDevices.isMouse(registryID: sender) else { return false }

        isMouseBySender[sender] = isMouse

        return isMouse
    }

    /// Every form of the delta has to flip. WebKit reads the HID event's, so without that one Safari scrolls the wrong way.
    private func reverse(_ event: CGEvent, hidEvent: CFTypeRef) {
        let axes: [(isReversed: Bool, lines: CGEventField, fixedPoint: CGEventField, points: CGEventField, hidField: UInt32)] = [
            (MouseScrollSetting.reversesVertically, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1, hidScrollFieldY),
            (MouseScrollSetting.reversesHorizontally, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2, hidScrollFieldX),
        ]

        for axis in axes where axis.isReversed {
            // Read together, because writing the line delta makes macOS recompute the others.
            let lines = event.getIntegerValueField(axis.lines)
            let fixedPoint = event.getDoubleValueField(axis.fixedPoint)
            let points = event.getDoubleValueField(axis.points)
            event.setIntegerValueField(axis.lines, value: -lines)
            event.setDoubleValueField(axis.fixedPoint, value: -fixedPoint)
            event.setDoubleValueField(axis.points, value: -points)
            setFloatValue(of: hidEvent, field: axis.hidField, value: -floatValue(of: hidEvent, field: axis.hidField))
        }
    }
}
