import Foundation

/// A browser target. `dataDir` selects a Chromium-style profile (`--user-data-dir`).
struct BrowserTarget: Codable, Hashable {
    var appPath: String
    var dataDir: String?
}

struct Universe: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String
    var browser: BrowserTarget
    /// Hex colour, used for tinted icons and the sidebar.
    var color: String?

    static let palette = ["#5B8DEF", "#E5484D", "#30A46C", "#F5A524", "#8E4EC6", "#12A594"]
}

enum AppKind: String, Codable, CaseIterable, Identifiable {
    /// The app as installed.
    case original
    /// APFS clone with its own name, bundle id, icon and environment. Own Dock icon.
    case clone
    /// Tiny bundle that starts the original with `--user-data-dir`. Shares the original's Dock icon.
    case launcher
    var id: String { rawValue }
}

enum IconStyle: String, Codable, CaseIterable, Identifiable {
    case original, invert, tint
    var id: String { rawValue }
}

struct AppEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: AppKind
    var sourcePath: String
    var universeID: UUID
    /// Bundle id for generated apps; filled in on first build when empty.
    var bundleID: String?
    /// launcher: passed as `--user-data-dir`.
    var dataDir: String?
    /// clone: written to LSEnvironment (e.g. an app-specific data-dir variable).
    var env: [String: String] = [:]
    var icon: IconStyle = .original

    /// Names become file names in /Applications, so keep them to one plain path component.
    static func nameProblem(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Give it a name." }
        if n.contains("/") || n.contains(":") { return "Names can't contain / or :." }
        if n.hasPrefix(".") { return "Names can't start with a dot." }
        if n.count > 60 { return "That name is too long." }
        return nil
    }

    /// Where the runnable bundle lives.
    var installedPath: String {
        kind == .original ? sourcePath : "/Applications/\(name).app"
    }
}

struct Config: Codable, Equatable {
    var universes: [Universe] = []
    var apps: [AppEntry] = []
    /// Universe for links from apps not listed in `apps`.
    var defaultUniverseID: UUID?

    var defaultUniverse: Universe? {
        universes.first { $0.id == defaultUniverseID } ?? universes.first
    }

    func universe(_ id: UUID) -> Universe? { universes.first { $0.id == id } }

    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Multiverse")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// The saved config; an empty one if there's no file yet. Nil if the file exists but can't be
    /// read (e.g. a typo from a hand edit), so callers never overwrite it with an empty config.
    static func loadIfValid() -> Config? {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do { return try JSONDecoder().decode(Config.self, from: data) } catch {
            Log.write("config.json can't be read, leaving it untouched: \(error)")
            return nil
        }
    }

    /// For startup: when the file is unreadable, keep a copy next to it and start empty.
    static func load() -> Config {
        if let c = loadIfValid() { return c }
        let backup = url.deletingPathExtension()
            .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: backup)
        Log.write("kept the unreadable config at \(backup.path)")
        return Config()
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(self).write(to: Config.url, options: .atomic) } catch {
            Log.write("config save failed: \(error)")
        }
    }
}

/// Expands a leading `~`.
func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Multiverse.log")
    private static let queue = DispatchQueue(label: "multiverse.log")
    private static let maxBytes = 1_000_000

    /// Appends a line. Serialised, and the log is cut back to the newest half once it passes ~1 MB.
    static func write(_ line: String) {
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        queue.async {
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes,
               let data = try? Data(contentsOf: url) {
                try? data.suffix(maxBytes / 2).write(to: url)
            }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close()
        }
    }
}

func appName(_ path: String) -> String {
    let p = expand(path)
    if let b = Bundle(url: URL(fileURLWithPath: p)),
       let n = b.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? b.infoDictionary?["CFBundleDisplayName"] as? String {
        return n
    }
    return ((p as NSString).lastPathComponent as NSString).deletingPathExtension
}
