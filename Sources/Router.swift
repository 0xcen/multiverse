import AppKit

struct RouteRecord: Identifiable {
    let id = UUID()
    let date = Date()
    let opener: String
    let universe: String
    let host: String
    /// The app the link opened in, when the universe sends links to the apps that own them.
    var app: String? = nil
}

/// Decides which universe a link belongs to and opens it in that universe's browser.
enum Router {
    /// The configured app (if any) that `opener` is an instance of.
    static func entry(for opener: ProcessInfoLite, in config: Config) -> AppEntry? {
        let path = opener.bundlePath
        let dataDir = opener.userDataDir.map(expand)
        func same(_ p: String) -> Bool { URL(fileURLWithPath: expand(p)).standardizedFileURL.path == path }

        // Launchers share the original's bundle, so tell them apart by --user-data-dir first.
        if let e = config.apps.first(where: {
            $0.kind == .launcher && same($0.sourcePath) && $0.dataDir.map(expand) == dataDir && dataDir != nil
        }) { return e }
        if let e = config.apps.first(where: { $0.kind == .clone && same($0.installedPath) }) {
            return e
        }
        return config.apps.first { $0.kind == .original && same($0.sourcePath) && dataDir == nil }
    }

    static func universe(forSenderPID pid: pid_t, in config: Config) -> (opener: String, universe: Universe?) {
        let opener = ProcessInfoLite(pid: pid)
        let name = opener.bundleID ?? "pid:\(pid)"
        if let e = entry(for: opener, in: config), let u = config.universe(e.universeID) {
            return ("\(e.name) (\(name))", u)
        }
        return (name, config.defaultUniverse)
    }

    // MARK: Apps that own links

    private static var hostCache: [String: (Date?, Set<String>)] = [:]
    private static let hostLock = NSLock()

    /// Hosts an installed app claims as universal links (`applinks:` associated domains), e.g.
    /// Notion's www.notion.so. macOS hands these links to that app before the default browser.
    static func linkHosts(ofApp path: String) -> Set<String> {
        let p = expand(path)
        let date = (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date
        hostLock.lock()
        if let (d, v) = hostCache[p], d == date { hostLock.unlock(); return v }
        hostLock.unlock()
        let domains = Builder.entitlements(of: URL(fileURLWithPath: p))["com.apple.developer.associated-domains"] as? [String] ?? []
        let hosts = Set(domains.compactMap { d -> String? in
            guard d.hasPrefix("applinks:") else { return nil }
            let h = d.dropFirst("applinks:".count).split(separator: "?").first.map(String.init) ?? ""
            return h.isEmpty ? nil : h.lowercased()
        })
        hostLock.lock(); hostCache[p] = (date, hosts); hostLock.unlock()
        return hosts
    }

    /// Copies lose the entitlement when re-signed, so ask the original.
    static func linkHosts(of entry: AppEntry) -> Set<String> { linkHosts(ofApp: entry.sourcePath) }

    static func matches(_ host: String, _ claimed: Set<String>) -> Bool {
        let h = host.lowercased()
        return claimed.contains { c in
            if c.hasPrefix("*.") { return h.hasSuffix(c.dropFirst(1)) }
            return h == c || (c.hasPrefix("www.") && h == c.dropFirst(4))
        }
    }

    static func open(_ urls: [URL], in target: BrowserTarget) {
        let appURL = URL(fileURLWithPath: expand(target.appPath))
        if appURL.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            Log.write("a universe's browser is Multiverse itself; pick a real browser")
            return
        }
        guard let dataDir = target.dataDir, !dataDir.isEmpty else {
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        // A running Chromium profile ignores URLs passed on argv, so hand them to that exact process.
        if let running = runningInstances(of: target.appPath, dataDir: dataDir).first {
            urls.forEach { sendGetURL($0, to: running.pid) }
            NSRunningApplication(processIdentifier: running.pid)?.activate(options: [.activateAllWindows])
            return
        }
        // Start the profile through LaunchServices (some browsers, like Arc, relaunch themselves
        // without the profile flag when started any other way), then hand over the link once that
        // profile's process is up and has stayed up.
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--user-data-dir=\(expand(dataDir))"]
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error { Log.write("could not start \(target.appPath) profile: \(error.localizedDescription)") }
        }
        DispatchQueue.global().async {
            var seen: pid_t?
            for _ in 0..<60 {
                Thread.sleep(forTimeInterval: 0.5)
                guard let pid = runningInstances(of: target.appPath, dataDir: dataDir).first?.pid else { seen = nil; continue }
                if seen != pid { seen = pid; continue }  // wait one more tick: same process still there
                Thread.sleep(forTimeInterval: 1.5)      // let its first window come up
                DispatchQueue.main.async {
                    guard let live = runningInstances(of: target.appPath, dataDir: dataDir).first?.pid else {
                        Log.write("\(target.appPath) profile quit before the link could be handed over")
                        return
                    }
                    urls.forEach { sendGetURL($0, to: live) }
                    NSRunningApplication(processIdentifier: live)?.activate(options: [.activateAllWindows])
                }
                return
            }
            Log.write("\(target.appPath) profile did not start")
        }
    }


    /// The app in `universe` set to open links it owns, other than the app that sent the link.
    static func owner(of url: URL, in universe: Universe, senderPath: String?, config: Config) -> AppEntry? {
        guard let host = url.host else { return nil }
        return config.apps.first { e in
            e.universeID == universe.id && e.opensOwnLinks == true
                && URL(fileURLWithPath: expand(e.installedPath)).standardizedFileURL.path != senderPath
                && matches(host, linkHosts(of: e))
        }
    }

    /// Opens links in an app directly. Naming the app skips macOS's universal-link lookup.
    static func open(_ urls: [URL], inApp entry: AppEntry) {
        if entry.kind == .launcher {
            open(urls, in: BrowserTarget(appPath: entry.sourcePath, dataDir: entry.dataDir))
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: URL(fileURLWithPath: expand(entry.installedPath)),
                                configuration: config) { _, error in
            if let error { Log.write("could not open link in \(entry.name): \(error.localizedDescription)") }
        }
    }

    // MARK: App link schemes (notion://)

    /// App schemes Multiverse registers for in Info.plist, besides http and https.
    static let ownSchemes: [String] = {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
            .filter { $0 != "http" && $0 != "https" }
    }()

    /// URL schemes an app registers.
    static func schemes(ofApp path: String) -> Set<String> {
        let types = Bundle(url: URL(fileURLWithPath: expand(path)))?.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return Set(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() })
    }

    /// The universe whose browser is the process `pid` (same app, same --user-data-dir).
    static func browserUniverse(forPID pid: pid_t, in config: Config) -> Universe? {
        let p = ProcessInfoLite(pid: pid)
        guard let path = p.bundlePath else { return nil }
        let dir = p.userDataDir.map(expand)
        return config.universes.first {
            URL(fileURLWithPath: expand($0.browser.appPath)).standardizedFileURL.path == path
                && $0.browser.dataDir.map(expand) == dir
        }
    }

    /// Where a `scheme:` link from `universe` opens: the universe's app for it (a copy or a listed
    /// original), else the original app.
    static func schemeTarget(_ scheme: String, in universe: Universe, config: Config) -> AppEntry? {
        if let e = config.apps.first(where: { $0.universeID == universe.id && schemes(ofApp: $0.sourcePath).contains(scheme) }) {
            return e
        }
        if let e = config.apps.first(where: { schemes(ofApp: $0.sourcePath).contains(scheme) }) {
            return AppEntry(name: appName(e.sourcePath), kind: .original, sourcePath: e.sourcePath, universeID: universe.id)
        }
        return originalHandler(for: scheme).map {
            AppEntry(name: appName($0.path), kind: .original, sourcePath: $0.path, universeID: universe.id)
        }
    }

    /// An installed app other than Multiverse that registers `scheme`.
    static func originalHandler(for scheme: String) -> URL? {
        guard let url = URL(string: "\(scheme)://") else { return nil }
        let me = Bundle.main.bundleURL.standardizedFileURL
        return NSWorkspace.shared.urlsForApplications(toOpen: url).map(\.standardizedFileURL).first { $0 != me }
    }

    static func sendGetURL(_ url: URL, to pid: pid_t) {
        let ev = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        ev.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: keyDirectObject)
        do { _ = try ev.sendEvent(options: [.noReply], timeout: 5) } catch {
            Log.write("GetURL to \(pid) failed: \(error)")
        }
    }
}
