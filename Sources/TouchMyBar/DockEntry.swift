import AppKit

/// One slot in the bar's dock: an app, whether or not it is running.
struct DockEntry {
    let url: URL
    let bundleIdentifier: String?
    let name: String
    /// Non-nil when the app is running, which also gives us the running dot
    /// and makes press-and-hold-to-quit meaningful.
    let runningApplication: NSRunningApplication?

    var isRunning: Bool { runningApplication != nil }

    var icon: NSImage {
        runningApplication?.icon ?? NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Builds the bar's dock from the real Dock's own preferences, so the apps
/// and their order match what the user already knows.
///
/// The `persistent-apps` layout is stable but undocumented:
///     persistent-apps -> [ { tile-data: { bundle-identifier, file-data: { _CFURLString } } } ]
/// A missing or reshaped key means "no pinned apps", never an error.
enum DockModel {

    private static let domain = "com.apple.dock"
    private static let finderBundleIdentifier = "com.apple.finder"
    private static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    /// Apps seen running during this session that are not pinned. Without
    /// this, quitting an unpinned app makes its tile vanish mid-gesture;
    /// keeping it lets it settle into the dimmed not-running state instead.
    /// Session-scoped on purpose: a relaunch gives a clean bar.
    private static var seenUnpinned: [(url: URL, identifier: String, name: String)] = []

    /// Finder, then the pinned apps in Dock order, then anything else that
    /// happens to be running — the same three groups the real Dock shows.
    static func entries() -> [DockEntry] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var byBundleID: [String: NSRunningApplication] = [:]
        for app in running {
            if let id = app.bundleIdentifier { byBundleID[id] = app }
        }

        var entries: [DockEntry] = []
        var claimed = Set<String>()

        // Finder sits outside persistent-apps; the Dock pins it first.
        let finder = byBundleID[finderBundleIdentifier]
        entries.append(DockEntry(url: finder?.bundleURL ?? finderURL,
                                 bundleIdentifier: finderBundleIdentifier,
                                 name: finder?.localizedName ?? "Finder",
                                 runningApplication: finder))
        claimed.insert(finderBundleIdentifier)

        for pinned in pinnedApps() {
            guard let id = pinned.bundleIdentifier else { continue }
            guard !claimed.contains(id) else { continue }
            claimed.insert(id)

            let app = byBundleID[id]
            let url = app?.bundleURL ?? pinned.url
            guard let url else { continue }

            entries.append(DockEntry(url: url,
                                     bundleIdentifier: id,
                                     name: app?.localizedName ?? pinned.name(for: url),
                                     runningApplication: app))
        }

        // Running but not pinned, in launch order, as the real Dock does.
        for app in running.sorted(by: { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }) {
            guard let id = app.bundleIdentifier, !claimed.contains(id) else { continue }
            guard let url = app.bundleURL else { continue }

            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            if !seenUnpinned.contains(where: { $0.identifier == id }) {
                seenUnpinned.append((url: url, identifier: id, name: name))
            }
        }

        // Everything unpinned we have seen this session, running or since
        // quit, in the order it first appeared.
        for seen in seenUnpinned {
            guard !claimed.contains(seen.identifier) else { continue }
            claimed.insert(seen.identifier)
            entries.append(DockEntry(url: seen.url,
                                     bundleIdentifier: seen.identifier,
                                     name: seen.name,
                                     runningApplication: byBundleID[seen.identifier]))
        }

        return entries
    }

    /// A cheap stand-in for "has the Dock changed?" — the pinned bundle
    /// identifiers in order, which covers adding, removing and reordering.
    /// Reading this costs well under a tenth of a millisecond, so it is
    /// affordable to check on a timer.
    static func signature() -> String {
        pinnedApps().map { $0.bundleIdentifier ?? $0.url?.path ?? "?" }.joined(separator: "\n")
    }

    // MARK: - Dock preferences

    private struct PinnedApp {
        let bundleIdentifier: String?
        let url: URL?

        func name(for url: URL) -> String {
            url.deletingPathExtension().lastPathComponent
        }
    }

    private static func pinnedApps() -> [PinnedApp] {
        guard let defaults = UserDefaults(suiteName: domain),
              let tiles = defaults.array(forKey: "persistent-apps") as? [[String: Any]]
        else { return [] }

        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any] else { return nil }

            let identifier = data["bundle-identifier"] as? String
            var url: URL?
            if let file = data["file-data"] as? [String: Any],
               let string = file["_CFURLString"] as? String {
                url = URL(string: string)
            }
            // A pinned app whose bundle has since moved still resolves by id.
            if url == nil, let identifier {
                url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            }

            guard identifier != nil || url != nil else { return nil }
            return PinnedApp(bundleIdentifier: identifier, url: url)
        }
    }
}
