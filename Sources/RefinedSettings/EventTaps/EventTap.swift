import CoreGraphics
import Foundation

private func handleTapEvent(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

    return tap.handle(type, event) ? Unmanaged.passUnretained(event) : nil
}

/// An active event tap on its own thread, for a single event type. `shouldKeepEvent` runs on that thread and
/// returns false to swallow the event. `port` is set once before the thread starts.
final class EventTap: @unchecked Sendable {
    private let location: CGEventTapLocation
    private let eventType: CGEventType
    private let threadName: String
    private let shouldKeepEvent: @Sendable (CGEvent) -> Bool
    private var port: CFMachPort?

    init(
        location: CGEventTapLocation,
        eventType: CGEventType,
        threadName: String,
        shouldKeepEvent: @escaping @Sendable (CGEvent) -> Bool
    ) {
        self.location = location
        self.eventType = eventType
        self.threadName = threadName
        self.shouldKeepEvent = shouldKeepEvent
    }

    /// Whether macOS will currently allow a tap. Permission APIs can report a stale grant, so this makes a real one.
    static func canCreateTap() -> Bool {
        guard let probe = makePort(location: .cghidEventTap, eventType: .scrollWheel, userInfo: nil) else { return false }

        CGEvent.tapEnable(tap: probe, enable: false)
        CFMachPortInvalidate(probe)

        return true
    }

    private static func makePort(location: CGEventTapLocation, eventType: CGEventType, userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << eventType.rawValue),
            callback: handleTapEvent,
            userInfo: userInfo
        )
    }

    /// False when macOS refuses the tap, which is what happens without Accessibility access.
    func start() -> Bool {
        guard let newPort = Self.makePort(location: location, eventType: eventType, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }

        port = newPort
        let thread = Thread { [self] in runTapLoop() }
        thread.name = threadName
        thread.qualityOfService = .userInteractive
        thread.start()

        return true
    }

    /// Invalidating the port removes its run loop source, which ends the tap thread.
    func stop() {
        guard let port else { return }

        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
    }

    /// macOS can switch a tap off without saying so, for example around sleep.
    func enableIfNeeded() {
        guard let port, !CGEvent.tapIsEnabled(tap: port) else { return }

        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func runTapLoop() {
        guard let port else { return }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        // The callback holds this object unretained, so it has to outlive the loop.
        withExtendedLifetime(self) {
            CFRunLoopRun()
        }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout {
            enableIfNeeded()

            return true
        }

        return type == eventType ? shouldKeepEvent(event) : true
    }
}
