import AppKit
import UniformTypeIdentifiers

/// How a picker entry opens a link.
enum LaunchMethod {
    case workspace
    case chromiumProfile(directory: String)
    case firefoxProfile(name: String)
    case safariProfile(name: String)
}

struct BrowserProfile: Identifiable {
    let id: String
    let name: String
    let picture: NSImage?
    let launchMethod: LaunchMethod
}

struct BrowserApp: Identifiable {
    let id: String
    let name: String
    let appURL: URL
    let icon: NSImage
    /// Empty when the browser has no profiles worth choosing between.
    let profiles: [BrowserProfile]
}

/// One row in the picker: a browser, or one profile of a browser.
struct BrowserEntry: Identifiable {
    let id: String
    let appURL: URL
    let browserName: String
    let profileName: String?
    let icon: NSImage
    let profilePicture: NSImage?
    let launchMethod: LaunchMethod
}

@MainActor
enum BrowserCatalog {
    private static let hiddenIDsKey = "hiddenEntryIDs"
    private static let entryOrderKey = "entryOrder"
    private static let firefoxBundleID = "org.mozilla.firefox"

    /// Chromium browsers whose profiles can be targeted with --profile-directory, keyed by bundle ID.
    private static let chromiumDataDirectories = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
        "net.imput.helium": "net.imput.helium",
    ]

    private static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    /// IDs of browsers (bundle ID) and profiles (bundle ID|profile) switched off in Settings.
    static var hiddenIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenIDsKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: hiddenIDsKey) }
    }

    /// Entry IDs in the order chosen in Settings. Entries not listed (new browsers or profiles)
    /// follow the listed ones, in their natural order.
    static var entryOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: entryOrderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: entryOrderKey) }
    }

    /// The rows the picker shows, in the chosen order, without the ones switched off in Settings.
    static func visibleEntries() -> [BrowserEntry] {
        let hidden = hiddenIDs

        return allEntries().filter { entry in !hidden.contains(entry.id) }
    }

    /// Every browser, expanded into one row per profile, in the chosen order (hidden rows included).
    static func allEntries() -> [BrowserEntry] {
        let browsers = installedBrowsers()
        convertBrowserLevelHiddenIDs(for: browsers)
        let naturalEntries = browsers.flatMap(entries(for:))
        let positions = Dictionary(entryOrder.enumerated().map { index, id in (id, index) }, uniquingKeysWith: { first, _ in first })

        // A profile that isn't in the saved order yet takes its browser's place, so Safari's profiles appear
        // where Safari was.
        func position(of entry: BrowserEntry) -> Int {
            positions[entry.id] ?? entry.id.split(separator: "|").first.flatMap { browserID in positions[String(browserID)] } ?? Int.max
        }

        return naturalEntries.enumerated()
            .sorted { a, b in
                (position(of: a.element), a.offset) < (position(of: b.element), b.offset)
            }
            .map { indexedEntry in indexedEntry.element }
    }

    private static func entries(for browser: BrowserApp) -> [BrowserEntry] {
        guard !browser.profiles.isEmpty else {
            return [
                BrowserEntry(
                    id: browser.id,
                    appURL: browser.appURL,
                    browserName: browser.name,
                    profileName: nil,
                    icon: browser.icon,
                    profilePicture: nil,
                    launchMethod: .workspace
                ),
            ]
        }

        return browser.profiles.map { profile in
            BrowserEntry(
                id: profile.id,
                appURL: browser.appURL,
                browserName: browser.name,
                profileName: profile.name,
                icon: browser.icon,
                profilePicture: profile.picture,
                launchMethod: profile.launchMethod
            )
        }
    }

    /// Earlier versions could hide a whole browser by its bundle ID; turn that into hiding each of its profiles,
    /// since Settings now has one switch per row.
    private static func convertBrowserLevelHiddenIDs(for browsers: [BrowserApp]) {
        var hidden = hiddenIDs

        for browser in browsers where !browser.profiles.isEmpty && hidden.contains(browser.id) {
            hidden.remove(browser.id)
            hidden.formUnion(browser.profiles.map { profile in profile.id })
        }

        if hidden != hiddenIDs {
            hiddenIDs = hidden
        }
    }

    /// Apps that open both https URLs and HTML files, minus menu bar utilities (Linkguide itself,
    /// URL routers such as Hammerspoon) and copies tucked away in caches.
    private static func installedBrowsers() -> [BrowserApp] {
        let htmlHandlers = Set(NSWorkspace.shared.urlsForApplications(toOpen: UTType.html).map { appURL in appURL.standardizedFileURL })
        let libraryPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path
        var seenBundleIDs = Set<String>()
        var browsers: [BrowserApp] = []

        // A browser's installer disk image can still be mounted; its copy goes last, so the installed one wins.
        let appURLs = AppInfo.webBrowserURLs()
        let mountedImagePrefix = "/Volumes/"
        let orderedAppURLs = appURLs.filter { appURL in !appURL.path.hasPrefix(mountedImagePrefix) }
            + appURLs.filter { appURL in appURL.path.hasPrefix(mountedImagePrefix) }

        for appURL in orderedAppURLs {
            guard
                htmlHandlers.contains(appURL.standardizedFileURL),
                !appURL.path.hasPrefix(libraryPath),
                !AppInfo.isLinkguide(appURL),
                let bundle = Bundle(url: appURL),
                let bundleID = bundle.bundleIdentifier,
                bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool != true,
                bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true,
                seenBundleIDs.insert(bundleID).inserted
            else { continue }

            browsers.append(BrowserApp(
                id: bundleID,
                name: AppInfo.name(of: appURL),
                appURL: appURL,
                icon: NSWorkspace.shared.icon(forFile: appURL.path),
                profiles: profiles(forBundleID: bundleID)
            ))
        }

        return browsers.sorted { a, b in a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }

    /// Profiles worth offering. A browser with a single profile gets none, so it shows as one plain row.
    private static func profiles(forBundleID bundleID: String) -> [BrowserProfile] {
        var profiles: [BrowserProfile] = []

        if let dataPath = chromiumDataDirectories[bundleID] {
            profiles = chromiumProfiles(bundleID: bundleID, dataDirectory: applicationSupport.appendingPathComponent(dataPath))
        } else if bundleID == firefoxBundleID {
            profiles = firefoxProfiles(bundleID: bundleID)
        } else if bundleID == SafariProfiles.bundleID {
            profiles = SafariProfiles.profileNames().map { name in
                BrowserProfile(id: "\(bundleID)|\(name)", name: name, picture: nil, launchMethod: .safariProfile(name: name))
            }
        }

        return profiles.count > 1 ? profiles : []
    }

    /// Profiles from Chromium's `Local State`, in the browser's own order.
    private static func chromiumProfiles(bundleID: String, dataDirectory: URL) -> [BrowserProfile] {
        guard
            let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("Local State")),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profileSection = root["profile"] as? [String: Any],
            let infoCache = profileSection["info_cache"] as? [String: [String: Any]]
        else { return [] }

        let order = profileSection["profiles_order"] as? [String] ?? []
        let directories = order.filter { directory in infoCache[directory] != nil }
            + infoCache.keys.filter { directory in !order.contains(directory) }.sorted()

        return directories.map { directory in
            let info = infoCache[directory] ?? [:]
            let storedName = info["name"] as? String ?? ""

            return BrowserProfile(
                id: "\(bundleID)|\(directory)",
                name: storedName.isEmpty ? directory : storedName,
                picture: chromiumProfilePicture(info: info, profileDirectory: dataDirectory.appendingPathComponent(directory)),
                launchMethod: .chromiumProfile(directory: directory)
            )
        }
    }

    /// The picture the browser shows for a profile: a custom picture, then the Google account picture, then the
    /// default avatar drawn in the profile's colours. Nil when the profile has none of these.
    private static func chromiumProfilePicture(info: [String: Any], profileDirectory: URL) -> NSImage? {
        let fileNames = [
            info["is_using_custom_avatar"] as? Bool == true ? info["custom_avatar_picture_file_name"] as? String : nil,
            info["gaia_picture_file_name"] as? String,
            "Google Profile Picture.png",
        ].compactMap { fileName in fileName }

        for fileName in fileNames {
            if let picture = NSImage(contentsOf: profileDirectory.appendingPathComponent(fileName)) {
                return picture
            }
        }

        guard
            info["is_using_default_avatar"] as? Bool == true,
            let fill = info["default_avatar_fill_color"] as? Int,
            let stroke = info["default_avatar_stroke_color"] as? Int
        else { return nil }

        return defaultAvatar(fill: color(fromSkia: fill), glyph: color(fromSkia: stroke))
    }

    /// Chromium stores colours as signed 32-bit ARGB integers.
    private static func color(fromSkia value: Int) -> NSColor {
        let argb = UInt32(truncatingIfNeeded: value)

        return NSColor(
            srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A person on a coloured disc, like Chromium's default profile avatar.
    private static func defaultAvatar(fill: NSColor, glyph: NSColor) -> NSImage {
        let side: CGFloat = 64

        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [glyph]))

            if let person = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let size = person.size
                person.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }

            return true
        }
    }

    /// Profiles from Firefox's `profiles.ini` that have actually been used. Firefox creates an empty
    /// placeholder "default" profile on install; it has no browsing history, so it is skipped.
    private static func firefoxProfiles(bundleID: String) -> [BrowserProfile] {
        let firefoxDirectory = applicationSupport.appendingPathComponent("Firefox")
        guard let contents = try? String(contentsOf: firefoxDirectory.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return [] }

        var sections: [[String: String]] = []

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("[") {
                sections.append(line.hasPrefix("[Profile") ? ["section": "profile"] : [:])
            } else if let separator = line.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1][String(line[..<separator])] = String(line[line.index(after: separator)...])
            }
        }

        return sections.compactMap { section -> BrowserProfile? in
            guard section["section"] == "profile", let name = section["Name"], let path = section["Path"] else { return nil }

            let profileDirectory = section["IsRelative"] == "1" ? firefoxDirectory.appendingPathComponent(path) : URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: profileDirectory.appendingPathComponent("places.sqlite").path) else { return nil }

            return BrowserProfile(id: "\(bundleID)|\(name)", name: name, picture: nil, launchMethod: .firefoxProfile(name: name))
        }
    }
}
