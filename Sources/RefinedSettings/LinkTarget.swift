import Foundation

enum LinkTarget {
    static func isSupported(_ url: URL) -> Bool {
        if url.isFileURL { return true }

        guard let scheme = url.scheme?.lowercased() else { return false }

        return scheme == "http" || scheme == "https"
    }

    /// The host for web links, the file name for local files.
    static func headline(for url: URL) -> String {
        if url.isFileURL { return url.lastPathComponent }

        let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? ""
        let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        return trimmedHost.isEmpty ? url.absoluteString : trimmedHost
    }
}
