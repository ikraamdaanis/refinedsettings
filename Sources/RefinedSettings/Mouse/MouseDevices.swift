import IOKit

/// Finds mice in the IORegistry, without counting trackpads, which also present themselves as pointing devices.
enum MouseDevices {
    private static let genericDesktopUsagePage = 1
    private static let mouseUsage = 2

    /// The names of the connected mice, from each one's HID event service.
    static func connectedNames() -> [String] {
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }

        defer { IOObjectRelease(iterator) }

        var names = Set<String>()
        var service = IOIteratorNext(iterator)

        while service != 0 {
            if isMouse(service), let name = property("Product", of: service) as? String {
                names.insert(name)
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return names.sorted()
    }

    /// Whether a scroll event's sender is a mouse. A sender is the registry ID of its HID event service.
    /// Nil when it isn't in the registry, which is true of virtual devices such as Universal Control's.
    static func isMouse(registryID: UInt64) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))

        guard service != 0 else { return nil }

        defer { IOObjectRelease(service) }

        return isMouse(service)
    }

    private static func isMouse(_ service: io_service_t) -> Bool {
        guard
            property("PrimaryUsagePage", of: service) as? Int == genericDesktopUsagePage,
            property("PrimaryUsage", of: service) as? Int == mouseUsage
        else { return false }

        return IOObjectConformsTo(service, "AppleMultitouchTrackpadHIDEventDriver") == 0
            && property("HIDScrollAccelerationType", of: service) as? String != "HIDTrackpadScrollAcceleration"
    }

    private static func property(_ key: String, of service: io_service_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
