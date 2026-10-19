import AppKit
import Security

enum BuildError: LocalizedError {
    case running(String), missingSource(String), tool(String), notOurs(String), systemApp, sourceUpdating(String)
    var errorDescription: String? {
        switch self {
        case .notOurs(let p): "\(p) already exists and wasn't made by Multiverse. Pick another name."
        case .systemApp: "Apps in /System can't be cloned (macOS won't launch re-signed system apps)."
        case .running(let n): "Quit \(n) first, then update it."
        case .sourceUpdating(let n): "\(n) is being updated right now. Try again in a minute."
        case .missingSource(let p): "Source app not found: \(p)"
        case .tool(let msg): msg
        }
    }
}

extension FileManager {
    func isRunning(_ app: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }
    }
}

/// Creates the bundles for `clone` and `launcher` entries in /Applications.
enum Builder {
    /// Unique, valid bundle id for a new copy: ASCII slug of the name plus a random suffix, so
    /// "Work Slack" and "Work-Slack" (or an all-emoji name) never collide with each other or Multiverse.
    static func defaultBundleID(for name: String) -> String {
        let slug = String(name.lowercased().unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }.prefix(30))
        let suffix = UUID().uuidString.prefix(6).lowercased()
        return "io.github.0xcen.multiverse.copy.\(slug.isEmpty ? "app" : slug)-\(suffix)"
    }

    /// Info.plist key stamped into every app Multiverse builds, holding the entry's id. Only bundles
    /// carrying the matching stamp are ever replaced or moved to the Trash.
    static let ownerKey = "MultiverseCopyOf"

    static func isOurCopy(at url: URL, of entry: AppEntry) -> Bool {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) else { return false }
        return info[ownerKey] as? String == entry.id.uuidString
    }

    /// True for apps that accept `--user-data-dir` (Electron apps and Chromium-based browsers), so a copy
    /// can keep its own logins with no setup.
    /// Results per app path, keyed with the app's modification date so an update re-checks.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var profileCache: [String: (Date?, Bool)] = [:]
    nonisolated(unsafe) private static var blockerCache: [String: (Date?, String?)] = [:]

    private static func modified(_ app: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: app.path))?[.modificationDate] as? Date
    }

    static func supportsProfiles(_ app: URL) -> Bool {
        let date = modified(app)
        cacheLock.lock()
        if let (d, v) = profileCache[app.path], d == date { cacheLock.unlock(); return v }
        cacheLock.unlock()
        let v = computeSupportsProfiles(app)
        cacheLock.lock(); profileCache[app.path] = (date, v); cacheLock.unlock()
        return v
    }

    private static func computeSupportsProfiles(_ app: URL) -> Bool {
        let frameworks = (try? FileManager.default.contentsOfDirectory(
            atPath: app.appendingPathComponent("Contents/Frameworks").path)) ?? []
        return frameworks.contains { f in
            ["Electron Framework", "Chrom", "Browser Framework", "Chrome Framework", "Edge Framework",
             "Vivaldi Framework", "ArcCore", "Codex Framework"].contains { f.contains($0) }
        }
    }

    /// Why an app can't run as a copy, if it can't: iCloud only works in an app signed by its own
    /// developer, so a re-signed copy of an app that uses it (e.g. Arc) crashes.
    static func copyBlocker(_ app: URL) -> String? {
        if app.path.hasPrefix("/System/") { return "macOS doesn't allow copies of its built-in apps." }
        let date = modified(app)
        cacheLock.lock()
        if let (d, v) = blockerCache[app.path], d == date { cacheLock.unlock(); return v }
        cacheLock.unlock()
        let v = computeCopyBlocker(app)
        cacheLock.lock(); blockerCache[app.path] = (date, v); cacheLock.unlock()
        return v
    }

    private static func computeCopyBlocker(_ app: URL) -> String? {
        let ents = entitlements(of: app)
        if ents.keys.contains(where: { $0.hasPrefix("com.apple.developer.icloud") || $0.hasPrefix("com.apple.developer.ubiquity") }) {
            return "\(appName(app.path)) uses iCloud, which only works in the original app, so a copy would crash."
        }
        return nil
    }

    /// An app's entitlements, read in-process (much faster than running codesign per app).
    static func entitlements(of app: URL) -> [String: Any] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return [:] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return [:] }
        return dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    }

    /// Apps registered to open web links.
    static func isBrowser(_ app: URL) -> Bool {
        NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            .contains { $0.standardizedFileURL == app.standardizedFileURL }
    }

    /// Where a copy keeps its data when the app supports profiles.
    static func defaultDataDir(for name: String) -> String { "~/Library/Application Support/Multiverse/\(name)" }

    /// Creates the entry's app, or updates a copy Multiverse made earlier. Never touches an app it
    /// didn't make, and never touches app data (that lives in ~/Library, not in the app).
    /// The new app is built next to the old one first; the old one goes to the Trash only once the
    /// new one is ready. Returns the entry with its bundle id / data folder filled in.
    static func build(_ entry: AppEntry, tint: NSColor? = nil) throws -> AppEntry {
        var entry = entry
        if entry.kind == .original { return entry }
        if let problem = AppEntry.nameProblem(entry.name) { throw BuildError.tool(problem) }
        // One build at a time across the menu bar app and the command line.
        let lock = open(Config.url.deletingLastPathComponent().appendingPathComponent(".build.lock").path,
                        O_CREAT | O_RDWR, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if lock >= 0 { close(lock) }
            throw BuildError.tool("Another copy is being built right now. Try again in a moment.")
        }
        defer { flock(lock, LOCK_UN); close(lock) }
        removeLeftoverStaging()
        let sourceURL = URL(fileURLWithPath: expand(entry.sourcePath))
        if entry.kind == .clone, isBrowser(sourceURL), supportsProfiles(sourceURL) {
            // Chromium browsers keep their own bundle id: some (Dia) hand off to the running original
            // instead of starting when the id differs. Copies are still told apart by path and owner
            // marker. Other apps that merely open links (e.g. ChatGPT) get a new id, so they don't share
            // the original's data or get confused with it.
            entry.bundleID = Bundle(url: URL(fileURLWithPath: expand(entry.sourcePath)))?.bundleIdentifier
        } else if entry.bundleID?.isEmpty ?? true {
            entry.bundleID = defaultBundleID(for: entry.name)
        }
        let fm = FileManager.default
        let src = URL(fileURLWithPath: expand(entry.sourcePath))
        guard fm.fileExists(atPath: src.path) else { throw BuildError.missingSource(src.path) }
        if entry.kind == .clone, src.path.hasPrefix("/System/") { throw BuildError.systemApp }
        if entry.kind == .clone, let reason = copyBlocker(src) { throw BuildError.tool(reason) }
        if entry.kind == .clone, isMidUpdate(src) { throw BuildError.sourceUpdating(appName(src.path)) }
        if entry.kind == .clone, entry.dataDir == nil, entry.env.isEmpty, supportsProfiles(src) {
            entry.dataDir = defaultDataDir(for: entry.name)
        }

        let dest = URL(fileURLWithPath: entry.installedPath)
        guard dest.deletingLastPathComponent().path == "/Applications" else { throw BuildError.tool("Copies go straight into /Applications.") }
        if fm.fileExists(atPath: dest.path) {
            if dest.standardizedFileURL == src.standardizedFileURL || !isOurCopy(at: dest, of: entry) {
                throw BuildError.notOurs(dest.path)
            }
            if fm.isRunning(dest) { throw BuildError.running(entry.name) }
        }

        let staging = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(entry.name).multiverse-\(UUID().uuidString.prefix(8)).app")
        defer { try? fm.removeItem(at: staging) }
        switch entry.kind {
        case .original: return entry
        case .clone: try buildClone(entry, from: src, to: staging, tint: tint)
        case .launcher: try buildLauncher(entry, from: src, to: staging, tint: tint)
        }
        if fm.fileExists(atPath: dest.path) {
            // Check again: the build takes a few seconds and the copy may have been opened meanwhile.
            guard isOurCopy(at: dest, of: entry) else { throw BuildError.notOurs(dest.path) }
            if fm.isRunning(dest) { throw BuildError.running(entry.name) }
            try fm.trashItem(at: dest, resultingItemURL: nil)
        }
        try fm.moveItem(at: staging, to: dest)
        // The clone keeps the original's dates; a new one tells the Dock and Finder to reload the icon.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)

        try run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                ["-f", dest.path])
        Log.write("built \(entry.kind.rawValue) \(dest.path)")
        // A download the copy's updater left behind (not the original's, for copies that share its id).
        if let id = entry.bundleID, id != Bundle(url: src)?.bundleIdentifier {
            let cache = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/\(id).ShipIt")
            if fm.fileExists(atPath: cache.path) { try? fm.trashItem(at: cache, resultingItemURL: nil) }
        }
        return entry
    }

    /// Half-built copies left behind when a build was interrupted (e.g. Multiverse quit mid-build).
    /// Only called while holding the build lock, so no build is using them.
    private static func removeLeftoverStaging() {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        where item.hasPrefix(".") && item.contains(".multiverse-") && item.hasSuffix(".app") {
            let url = URL(fileURLWithPath: "/Applications").appendingPathComponent(item)
            do { try fm.trashItem(at: url, resultingItemURL: nil) } catch { Log.write("couldn't remove \(item): \(error)") }
        }
    }

    /// Version of the app a copy was made from vs. the original now, when they differ.
    /// Reads Info.plist directly: NSBundle caches per path and misses in-place updates.
    static func updateAvailable(_ entry: AppEntry) -> String? {
        guard entry.kind == .clone,
              let made = version(at: URL(fileURLWithPath: entry.installedPath)),
              let now = version(at: URL(fileURLWithPath: expand(entry.sourcePath))),
              made != now else { return nil }
        return now.short
    }

    struct Version: Equatable { let short: String; let build: String }

    static func version(at app: URL) -> Version? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        let short = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return short.isEmpty && build.isEmpty ? nil : Version(short: short.isEmpty ? build : short, build: build)
    }

    /// The original was just changed and its signature doesn't check out: its updater is probably
    /// halfway through replacing it. (An app that fails the check for other reasons, long after its
    /// last change, can still be copied.)
    static func isMidUpdate(_ app: URL) -> Bool {
        let changed = (try? FileManager.default.attributesOfItem(atPath: app.path))?[.modificationDate] as? Date ?? .distantPast
        guard Date().timeIntervalSince(changed) < 300 else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return true }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckNestedCode), nil) != errSecSuccess
    }

    // MARK: clone

    private static let launchScript = "multiverse-launch"

    private static func buildClone(_ entry: AppEntry, from src: URL, to dest: URL, tint: NSColor?) throws {
        let fm = FileManager.default
        try fm.copyItem(at: src, to: dest)  // APFS clone: near-zero extra disk

        let plistURL = dest.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL), format: nil) as? [String: Any] ?? [:]
        // The menu bar shows CFBundleName. Electron finds its helpers as "<CFBundleName> Helper*.app",
        // so those are renamed along with it. (Chromium browsers name their helpers at compile time.)
        var helpers: [URL] = []
        if let oldName = plist["CFBundleName"] as? String, oldName != entry.name {
            helpers = try renameElectronHelpers(in: dest, from: oldName, to: entry.name)
            plist["CFBundleName"] = entry.name
        }
        plist["CFBundleDisplayName"] = entry.name
        plist["CFBundleIdentifier"] = entry.bundleID
        plist[ownerKey] = entry.id.uuidString
        if !isBrowser(src) {
            plist.removeValue(forKey: "CFBundleURLTypes")  // leave custom URL schemes with the original
        }
        if !entry.env.isEmpty {
            var env = plist["LSEnvironment"] as? [String: String] ?? [:]
            for (k, v) in entry.env { env[k] = expand(v) }
            plist["LSEnvironment"] = env
        }
        // Separate logins: start the real binary with its own --user-data-dir. The process still lives
        // inside this bundle, so it keeps its own name and Dock icon.
        var nested: [URL] = []
        if let dataDir = entry.dataDir, let exe = plist["CFBundleExecutable"] as? String {
            let script = dest.appendingPathComponent("Contents/MacOS/\(launchScript)")
            try """
            #!/bin/bash
            exec "$(dirname "$0")"/\(shellQuote(exe)) --user-data-dir=\(shellQuote(expand(dataDir))) "$@"

            """.write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            plist["CFBundleExecutable"] = launchScript
            nested.append(dest.appendingPathComponent("Contents/MacOS/\(exe)"))
        }
        if entry.icon != .original {
            plist.removeValue(forKey: "CFBundleIconName")  // an asset-catalog icon would win over the .icns
            let iconFile = plist["CFBundleIconFile"] as? String ?? "AppIcon"
            plist["CFBundleIconFile"] = iconFile
            let name = iconFile.hasSuffix(".icns") ? iconFile : iconFile + ".icns"
            try Icons.write(Icons.make(for: src, style: entry.icon, tint: tint),
                            to: dest.appendingPathComponent("Contents/Resources/\(name)"))
        }
        let squirrel = try disableUpdaters(in: dest, plist: &plist)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        try renameLocalizations(in: dest, to: entry.name, renameBundle: true)

        // Re-sign ad hoc (editing Info.plist breaks the original signature), keeping entitlements and
        // the hardened runtime, so things like DYLD_INSERT_LIBRARIES injection stay blocked. Library
        // validation is relaxed because the copy is signed for this Mac while its frameworks still
        // carry the original developer's signature.
        let ents = fm.temporaryDirectory.appendingPathComponent("mv-ents-\(UUID().uuidString).plist")
        defer { try? fm.removeItem(at: ents) }
        var dict: [String: Any] = [:]
        if let xml = try? run("/usr/bin/codesign", ["-d", "--entitlements", ":-", src.path]),
           let data = xml.data(using: .utf8),
           let original = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            // Entitlements tied to Apple's or the vendor's signing identity make an ad-hoc binary
            // refuse to launch; drop them and keep the rest (JIT, camera, mic, Apple Events…).
            dict = original.filter { key, _ in !restrictedEntitlementPrefixes.contains { key.hasPrefix($0) } }
        }
        dict["com.apple.security.cs.disable-library-validation"] = true
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: ents)
        let signArgs = ["--force", "-s", "-", "--options", "runtime", "--entitlements", ents.path]
        try? fm.removeItem(at: dest.appendingPathComponent("Contents/embedded.provisionprofile"))
        // Extended attributes (Finder info, resource forks) in some apps, e.g. Arc, make codesign refuse.
        try run("/usr/bin/xattr", ["-cr", dest.path])
        for binary in nested { try run("/usr/bin/codesign", signArgs + [binary.path]) }
        for helper in helpers { try signHelper(helper) }
        if let squirrel { try run("/usr/bin/codesign", ["--force", "-s", "-", squirrel.path]) }
        try run("/usr/bin/codesign", signArgs + [dest.path])
    }

    /// Localized InfoPlist.strings override CFBundleDisplayName, so the clone would still show the
    /// original's name in Finder and the Dock. Point them at the new name too.
    /// A copy can't take the original's updates (they're signed for the original and would undo the
    /// copy's name and settings), so its built-in updater is switched off; Multiverse rebuilds the copy
    /// whenever the original updates instead. Returns Squirrel.framework if it was changed (needs signing).
    private static func disableUpdaters(in bundle: URL, plist: inout [String: Any]) throws -> URL? {
        let fm = FileManager.default
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        // Sparkle: an unreachable feed is the guard that holds even when user defaults (shared with
        // the original when the bundle id is kept) turn automatic checks back on.
        if plist["SUFeedURL"] != nil || fm.fileExists(atPath: frameworks.appendingPathComponent("Sparkle.framework").path) {
            plist["SUFeedURL"] = "https://127.0.0.1:9/multiverse-copy"
            plist["SUEnableAutomaticChecks"] = false
            plist["SUAutomaticallyUpdate"] = false
            plist["SUAllowsAutomaticUpdates"] = false
            plist["SUScheduledCheckInterval"] = 31_536_000
        }
        // Squirrel.Mac (Electron): ShipIt installs downloaded updates. Electron links the framework, so
        // it stays; only the installer becomes a no-op.
        let squirrel = frameworks.appendingPathComponent("Squirrel.framework")
        let shipIt = squirrel.appendingPathComponent("Versions/A/Resources/ShipIt")
        guard fm.fileExists(atPath: shipIt.path) else { return nil }
        try fm.removeItem(at: shipIt)
        try "#!/bin/sh\n# Multiverse: this copy is updated by Multiverse, not by the app.\nexit 1\n"
            .write(to: shipIt, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shipIt.path)
        return squirrel
    }

    /// Renames Electron's helper apps ("Old Helper (Renderer).app" → "New Helper (Renderer).app") and
    /// their executables. Returns the renamed helpers, which need signing again.
    private static func renameElectronHelpers(in bundle: URL, from old: String, to new: String) throws -> [URL] {
        let fm = FileManager.default
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        let prefix = "\(old) Helper"
        let found = ((try? fm.contentsOfDirectory(atPath: frameworks.path)) ?? [])
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".app") }
        var renamed: [URL] = []
        for item in found {
            let helperOld = String(item.dropLast(4))                       // "Old Helper (GPU)"
            let helperNew = new + helperOld.dropFirst(old.count)           // "New Helper (GPU)"
            let app = frameworks.appendingPathComponent("\(helperNew).app")
            try fm.moveItem(at: frameworks.appendingPathComponent(item), to: app)
            let macos = app.appendingPathComponent("Contents/MacOS")
            if fm.fileExists(atPath: macos.appendingPathComponent(helperOld).path) {
                try fm.moveItem(at: macos.appendingPathComponent(helperOld), to: macos.appendingPathComponent(helperNew))
            }
            let plistURL = app.appendingPathComponent("Contents/Info.plist")
            var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any] ?? [:]
            if plist["CFBundleExecutable"] as? String == helperOld { plist["CFBundleExecutable"] = helperNew }
            plist["CFBundleDisplayName"] = helperNew
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
            renamed.append(app)
        }
        return renamed
    }

    /// Signs a helper app ad hoc, keeping its own entitlements (JIT for renderers and so on).
    private static func signHelper(_ app: URL) throws {
        let fm = FileManager.default
        let ents = fm.temporaryDirectory.appendingPathComponent("mv-ents-\(UUID().uuidString).plist")
        defer { try? fm.removeItem(at: ents) }
        var dict: [String: Any] = [:]
        if let xml = try? run("/usr/bin/codesign", ["-d", "--entitlements", ":-", app.path]),
           let data = xml.data(using: .utf8),
           let original = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            dict = original.filter { key, _ in !restrictedEntitlementPrefixes.contains { key.hasPrefix($0) } }
        }
        dict["com.apple.security.cs.disable-library-validation"] = true
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: ents)
        try run("/usr/bin/codesign", ["--force", "-s", "-", "--options", "runtime", "--entitlements", ents.path, app.path])
    }

    private static func renameLocalizations(in bundle: URL, to name: String, renameBundle: Bool) throws {
        let res = bundle.appendingPathComponent("Contents/Resources")
        let lprojs = (try? FileManager.default.contentsOfDirectory(at: res, includingPropertiesForKeys: nil)) ?? []
        for lproj in lprojs where lproj.pathExtension == "lproj" {
            let strings = lproj.appendingPathComponent("InfoPlist.strings")
            guard let data = try? Data(contentsOf: strings),
                  var dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  dict["CFBundleDisplayName"] != nil || dict["CFBundleName"] != nil else { continue }
            dict["CFBundleDisplayName"] = name
            if renameBundle { dict["CFBundleName"] = name } else { dict.removeValue(forKey: "CFBundleName") }
            try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0).write(to: strings)
        }
    }

    private static let restrictedEntitlementPrefixes = [
        "com.apple.private.", "com.apple.developer.", "com.apple.application-identifier",
        "keychain-access-groups", "com.apple.security.application-groups", "platform-application",
    ]

    // MARK: launcher

    private static func buildLauncher(_ entry: AppEntry, from src: URL, to dest: URL, tint: NSColor?) throws {
        let fm = FileManager.default
        guard let exe = Bundle(url: src)?.executableURL?.path else { throw BuildError.missingSource(src.path) }
        guard let dataDir = entry.dataDir, !dataDir.isEmpty else {
            throw BuildError.tool("A launcher needs a data directory.")
        }
        let contents = dest.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)

        // Focus the running profile if there is one, otherwise start it.
        let script = """
        #!/bin/bash
        EXE=\(shellQuote(exe))
        DATA_DIR=\(shellQuote(expand(dataDir)))
        PID=$(pgrep -of \(shellQuote("^" + regexEscape(exe) + " --user-data-dir=" + regexEscape(expand(dataDir)) + "( |$)")))
        if [ -n "$PID" ] && osascript -e "tell application \\"System Events\\" to set frontmost of (first process whose unix id is $PID) to true" 2>/dev/null; then
          exit 0
        fi
        exec "$EXE" --user-data-dir="$DATA_DIR" "$@"

        """
        let launcher = contents.appendingPathComponent("MacOS/Launcher")
        try script.write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        try Icons.write(Icons.make(for: src, style: entry.icon, tint: tint),
                        to: contents.appendingPathComponent("Resources/app.icns"))
        let plist: [String: Any] = [
            "CFBundleName": entry.name,
            "CFBundleDisplayName": entry.name,
            "CFBundleIdentifier": entry.bundleID ?? defaultBundleID(for: entry.name),
            "CFBundleExecutable": "Launcher",
            "CFBundleIconFile": "app.icns",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "NSHighResolutionCapable": true,
            ownerKey: entry.id.uuidString,
            "NSAppleEventsUsageDescription": "Brings the already-running \(entry.name) window to the front.",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try run("/usr/bin/xattr", ["-cr", dest.path])
        try run("/usr/bin/codesign", ["--force", "-s", "-", dest.path])
    }

    // MARK: helpers

    /// Escapes a literal for pgrep's extended regex.
    private static func regexEscape(_ s: String) -> String {
        var out = ""
        for c in s { if "\\^$.|?*+()[]{}".contains(c) { out.append("\\") }; out.append(c) }
        return out
    }

    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw BuildError.tool("\((tool as NSString).lastPathComponent) failed: \(String(decoding: e, as: UTF8.self))")
        }
        return String(decoding: o, as: UTF8.self)
    }
}

/// App icons: read any app's icon, optionally invert it, write an .icns.
enum Icons {
    static func make(for app: URL, style: IconStyle, tint: NSColor? = nil, size: Int = 1024) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        switch style {
        case .original: return icon
        case .invert: return invert(icon, size: size)
        case .tint: return self.tint(icon, with: tint ?? .systemBlue, size: size)
        case .ivory, .graphite:
            let ivory = style == .ivory
            // Flat icons (a symbol on a plain tile) get the symbol on a Carbon tile. Shaded or
            // illustrated icons have no clean symbol to cut out, so they're recoloured instead.
            guard let mark = glyph(of: icon, bright: brightLineApps.contains(Bundle(url: app)?.bundleIdentifier ?? ""), size: size)
            else { return duotone(icon, ivory: ivory, size: size) }
            return carbonTile(mark, ivory: ivory, size: size)
        }
    }

    /// Apps whose symbol is bright lines over a glow (Arc); their symbol is picked out by brightness.
    static let brightLineApps: Set<String> = ["company.thebrowser.Browser"]

    /// The app's symbol (Notion's N, Slack's hash…) as a white mask: the icon's background colour is
    /// sampled just inside its edge, and whatever differs from it is the symbol.
    /// Nil when the icon has no flat background to tell the symbol apart from.
    static func glyph(of icon: NSImage, bright: Bool = false, size: Int = 1024) -> NSImage? {
        guard let rep = bitmap(icon, size: size), let data = rep.bitmapData else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        func px(_ x: Int, _ y: Int) -> (Float, Float, Float, Float) {
            guard x >= 0, y >= 0, x < w, y < h else { return (0, 0, 0, 0) }
            let p = data + (y * w + x) * 4, a = Float(p[3])
            guard a > 0 else { return (0, 0, 0, 0) }
            return (Float(p[0]) / a, Float(p[1]) / a, Float(p[2]) / a, a / 255)
        }
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h { for x in 0..<w where px(x, y).3 > 0.9 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX > minX else { return nil }
        let inset = Int(Double(maxX - minX) * 0.07)
        var rs: [Float] = [], gs: [Float] = [], bs: [Float] = []
        for t in stride(from: 0.2, through: 0.8, by: 0.02) {
            let xs = minX + inset + Int(Double(maxX - minX - 2 * inset) * t)
            let ys = minY + inset + Int(Double(maxY - minY - 2 * inset) * t)
            for (x, y) in [(xs, minY + inset), (xs, maxY - inset), (minX + inset, ys), (maxX - inset, ys)] {
                let c = px(x, y); if c.3 > 0.9 { rs.append(c.0); gs.append(c.1); bs.append(c.2) }
            }
        }
        func median(_ v: [Float]) -> Float { v.isEmpty ? 1 : v.sorted()[v.count / 2] }
        let bg = (median(rs), median(gs), median(bs))
        // A shaded or gradient background varies along the edge; the cut-out would be noise.
        var spread: [Float] = []
        for i in rs.indices {
            let dr: Float = rs[i] - bg.0, dg: Float = gs[i] - bg.1, db: Float = bs[i] - bg.2
            spread.append((dr * dr + dg * dg + db * db).squareRoot())
        }
        if !bright, median(Array(spread.sorted().suffix(spread.count / 2))) > 0.12 { return nil }
        var marked = 0
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        let o = out.bitmapData!
        let edge = inset * 3 / 4
        for y in 0..<h {
            for x in 0..<w {
                let c = px(x, y)
                let d = sqrt((c.0 - bg.0) * (c.0 - bg.0) + (c.1 - bg.1) * (c.1 - bg.1) + (c.2 - bg.2) * (c.2 - bg.2))
                let lum = 0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2
                let inside = px(x - edge, y).3 > 0.9 && px(x + edge, y).3 > 0.9 && px(x, y - edge).3 > 0.9 && px(x, y + edge).3 > 0.9
                    && px(x - edge, y - edge).3 > 0.9 && px(x + edge, y + edge).3 > 0.9
                    && px(x - edge, y + edge).3 > 0.9 && px(x + edge, y - edge).3 > 0.9
                let strength = bright ? (lum - 0.72) / 0.12 : (d - 0.16) / 0.09
                let v = UInt8(inside ? min(1, max(0, strength)) * c.3 * 255 : 0)
                if v > 128 { marked += 1 }
                let q = o + (y * w + x) * 4
                q[0] = v; q[1] = v; q[2] = v; q[3] = v
            }
        }
        // A symbol covers part of the tile; nearly none or most of it means the cut-out failed.
        let area = max(1, (maxX - minX) * (maxY - minY))
        if !bright, Double(marked) / Double(area) > 0.5 || Double(marked) / Double(area) < 0.005 { return nil }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(out)
        return image
    }

    /// The icon in two Carbon colours by brightness: ivory style keeps light areas ivory and dark
    /// areas graphite; graphite style swaps them. Keeps the icon's shape and shading.
    static func duotone(_ image: NSImage, ivory: Bool, size: Int = 1024) -> NSImage {
        guard let rep = bitmap(image, size: size), let data = rep.bitmapData else { return image }
        func rgb(_ hex: Int) -> [Float] { [Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255] }
        let bright = rgb(ivory ? Brand.ivoryHex : Brand.graphiteHex)  // the icon's light areas
        let dim = rgb(ivory ? 0x161716 : Brand.ivoryHex)              // its dark details
        let n = rep.pixelsWide * rep.pixelsHigh
        func lum(_ i: Int) -> Float {
            let p = data + i * 4, a = Float(p[3])
            return a > 0 ? (0.299 * Float(p[0]) + 0.587 * Float(p[1]) + 0.114 * Float(p[2])) / a : 0
        }
        // Stretch the icon's own brightness range to the full two colours, so it doesn't go muddy.
        let levels = (0..<n).filter { data[$0 * 4 + 3] > 200 }.map(lum).sorted()
        let lo = levels.isEmpty ? 0 : levels[levels.count / 20], hi = levels.isEmpty ? 1 : levels[levels.count * 19 / 20]
        for i in 0..<n {
            let p = data + i * 4, a = Float(p[3])
            guard a > 0 else { continue }
            let t = hi > lo ? (lum(i) - lo) / (hi - lo) : lum(i)
            // Blend by alpha³ like `invert`, so soft drop shadows stay dark instead of a pale halo.
            let k = (a / 255) * (a / 255) * (a / 255)
            for ch in 0..<3 {
                let v = dim[ch] + (bright[ch] - dim[ch]) * min(1, max(0, t))
                p[ch] = UInt8(max(0, min(a, Float(p[ch]) * (1 - k) + v * a * k)))
            }
        }
        let out = NSImage(size: NSSize(width: size, height: size))
        out.addRepresentation(rep)
        return out
    }

    /// A macOS-shaped Carbon tile with the symbol on it: ivory tile and graphite symbol, or the reverse.
    static func carbonTile(_ glyph: NSImage, ivory: Bool, size: Int = 1024) -> NSImage {
        let s = CGFloat(size)
        let tile = NSColor(rgb: ivory ? Brand.ivoryHex : Brand.graphiteHex)
        let mark = NSColor(rgb: ivory ? 0x161716 : Brand.ivoryHex)
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        // Apple's icon grid: an 824-pt rounded square centred in 1024.
        let r = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
        tile.setFill()
        NSBezierPath(roundedRect: r, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024).fill()
        // Tint the white mask by drawing it through a solid colour.
        let tinted = NSImage(size: glyph.size)
        tinted.lockFocus()
        glyph.draw(in: NSRect(origin: .zero, size: glyph.size))
        mark.set()
        NSRect(origin: .zero, size: glyph.size).fill(using: .sourceIn)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        image.unlockFocus()
        return image
    }

    /// Recolours the icon in one hue: shadows go dark, mid-tones take the colour, highlights go pale.
    static func tint(_ image: NSImage, with color: NSColor, size: Int = 1024) -> NSImage {
        guard let rep = bitmap(image, size: size), let data = rep.bitmapData,
              let c = color.usingColorSpace(.deviceRGB) else { return image }
        let tint = [Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent)]
        for i in 0..<(rep.pixelsWide * rep.pixelsHigh) {
            let p = data + i * 4, a = Float(p[3])
            guard a > 0 else { continue }
            let r = Float(p[0]) / a, g = Float(p[1]) / a, b = Float(p[2]) / a
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            let base = min(1, lum * 1.6)           // black → colour
            let pale = max(0, (lum - 0.75) / 0.25)  // colour → white in highlights
            for ch in 0..<3 {
                let v = tint[ch] * base * (1 - pale * 0.7) + pale * 0.7
                p[ch] = UInt8(max(0, min(a, v * a)))
            }
        }
        let out = NSImage(size: NSSize(width: size, height: size))
        out.addRepresentation(rep)
        return out
    }

    /// Inverts colour and keeps alpha, so transparent corners stay transparent.
    static func invert(_ image: NSImage, size: Int = 1024) -> NSImage {
        guard let rep = bitmap(image, size: size), let data = rep.bitmapData else { return image }
        let count = rep.pixelsWide * rep.pixelsHigh
        for i in 0..<count {
            // Premultiplied, so fully inverted is `a - c`. Blend by alpha³ so soft drop shadows
            // stay dark instead of turning into a white halo.
            let p = data + i * 4, a = Float(p[3])
            let t = (a / 255) * (a / 255) * (a / 255)
            for c in 0..<3 {
                let v = Float(p[c])
                p[c] = UInt8(max(0, min(a, v + t * (a - 2 * v))))
            }
        }
        let out = NSImage(size: NSSize(width: size, height: size))
        out.addRepresentation(rep)
        return out
    }

    /// Premultiplied RGBA bitmap of `image` at `size`×`size`.
    static func bitmap(_ image: NSImage, size: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bitmapFormat: [], bytesPerRow: size * 4, bitsPerPixel: 32) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func write(_ image: NSImage, to icns: URL) throws {
        let fm = FileManager.default
        let set = fm.temporaryDirectory.appendingPathComponent("mv-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: set) }
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                guard let png = bitmap(image, size: px)?.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png.write(to: set.appendingPathComponent(name))
            }
        }
        if fm.fileExists(atPath: icns.path) { try fm.removeItem(at: icns) }
        try Builder.run("/usr/bin/iconutil", ["-c", "icns", set.path, "-o", icns.path])
    }
}
