import AppKit

/// Entry point: with arguments, Multiverse works as a command-line tool (for scripts and coding
/// agents); without, it starts the menu bar app.
#if !SNAPSHOT
@main
enum Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }
        guard let command = args.first else { return MultiverseApp.main() }
        exit(CLI.run(command, Array(args.dropFirst())))
    }
}
#endif

enum CLI {
    static let usage = """
    Usage: /Applications/Multiverse.app/Contents/MacOS/Multiverse <command>

      status                  Show universes, apps, and whether links are being routed
      check                   Validate the config file; exit 1 on problems
      build <name>            Create or update the copy called <name>
      build --all             Create every missing copy and update copies of updated apps
      make-default-browser    Ask macOS to make Multiverse the default browser (the user confirms)
      config-path             Print the config file location

    Config: ~/Library/Application Support/Multiverse/config.json (the menu bar app reloads it on change).
    """

    static func run(_ command: String, _ args: [String]) -> Int32 {
        switch command {
        case "status": return status()
        case "check": return check()
        case "build": return build(args)
        case "make-default-browser": return makeDefault()
        case "config-path": print(Config.url.path); return 0
        case "help", "--help", "-h": print(usage); return 0
        default: print(usage); return 2
        }
    }

    static func installedCopy(_ e: AppEntry) -> Bool {
        e.kind == .original
            ? FileManager.default.fileExists(atPath: e.installedPath)
            : e.bundleID != nil && Bundle(url: URL(fileURLWithPath: e.installedPath))?.bundleIdentifier == e.bundleID
    }

    static func status() -> Int32 {
        let c = Config.load()
        let routing = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?
            .standardizedFileURL.path == "/Applications/Multiverse.app"
        print("Link routing: \(routing ? "on" : "OFF (Multiverse is not the default browser)")")
        for u in c.universes {
            let star = c.defaultUniverse?.id == u.id ? " ★ default" : ""
            let browser = appName(u.browser.appPath) + (u.browser.dataDir.map { " (profile \($0))" } ?? "")
            print("\n\(u.emoji) \(u.name)\(star) — links open in \(browser)")
            for e in c.apps where e.universeID == u.id {
                var state = installedCopy(e) ? "ready" : (e.kind == .original ? "MISSING" : "not created")
                if let v = Builder.updateAvailable(e) { state = "original updated to \(v), run: build \"\(e.name)\"" }
                print("  - \(e.name) [\(e.kind.rawValue)] \(state)")
            }
        }
        return 0
    }

    static func check() -> Int32 {
        let c = Config.load()
        var problems: [String] = []
        let ids = Set(c.universes.map(\.id))
        if c.universes.isEmpty { problems.append("No universes.") }
        for u in c.universes where !FileManager.default.fileExists(atPath: expand(u.browser.appPath)) {
            problems.append("\(u.name): browser not found at \(u.browser.appPath)")
        }
        for e in c.apps {
            if !ids.contains(e.universeID) { problems.append("\(e.name): universeID matches no universe") }
            if !FileManager.default.fileExists(atPath: expand(e.sourcePath)) { problems.append("\(e.name): sourcePath not found") }
            if e.kind != .original, FileManager.default.fileExists(atPath: e.installedPath), !installedCopy(e) {
                problems.append("\(e.name): /Applications/\(e.name).app belongs to another app; pick another name")
            }
            if e.kind == .launcher, e.dataDir == nil { problems.append("\(e.name): launcher needs dataDir") }
        }
        if Set(c.apps.map(\.name)).count != c.apps.count { problems.append("Two apps share a name.") }
        problems.forEach { print("✗ \($0)") }
        if problems.isEmpty { print("✓ Config OK (\(c.universes.count) universes, \(c.apps.count) apps)") }
        return problems.isEmpty ? 0 : 1
    }

    static func build(_ args: [String]) -> Int32 {
        var c = Config.load()
        let all = args.first == "--all"
        let targets = c.apps.filter { e in
            guard e.kind != .original else { return false }
            if all { return !installedCopy(e) || Builder.updateAvailable(e) != nil }
            return e.name == args.joined(separator: " ")
        }
        if targets.isEmpty {
            print(all ? "Nothing to build." : "No copy named \"\(args.joined(separator: " "))\". See: status")
            return all ? 0 : 1
        }
        var failed = false
        for e in targets {
            let tint = c.universe(e.universeID).flatMap { NSColor(hex: $0.color ?? "") }
            do {
                let built = try Builder.build(e, tint: tint)
                if let i = c.apps.firstIndex(where: { $0.id == e.id }) { c.apps[i] = built }
                print("✓ \(e.name) → \(built.installedPath)")
            } catch {
                failed = true
                print("✗ \(e.name): \(error.localizedDescription)")
            }
        }
        c.save()
        return failed ? 1 : 0
    }

    static func makeDefault() -> Int32 {
        let me = URL(fileURLWithPath: "/Applications/Multiverse.app")
        var done = false
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { error in
                print(error.map { "✗ \($0.localizedDescription)" } ?? "✓ Multiverse is the default browser")
                done = true
            }
        }
        print("macOS is asking the user to confirm the change…")
        let deadline = Date().addingTimeInterval(120)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        return done ? 0 : 1
    }
}
