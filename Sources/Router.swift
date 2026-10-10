import AppKit

struct RouteRecord: Identifiable {
    let id = UUID()
    let date = Date()
    let opener: String
    let universe: String
    let host: String
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
        guard let exe = Bundle(url: appURL)?.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["--user-data-dir=\(expand(dataDir))"]
        do { try p.run() } catch {
            Log.write("could not start \(target.appPath): \(error)")
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        DispatchQueue.global().async {
            for _ in 0..<40 {
                Thread.sleep(forTimeInterval: 0.25)
                guard let pid = runningInstances(of: target.appPath, dataDir: dataDir).first?.pid else { continue }
                Thread.sleep(forTimeInterval: 2)  // let the first window come up
                DispatchQueue.main.async {
                    urls.forEach { sendGetURL($0, to: pid) }
                    NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
                }
                return
            }
            Log.write("\(target.appPath) profile did not start")
        }
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
