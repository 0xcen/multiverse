import SwiftUI

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var config = Config.load() {
        didSet { config.save() }
    }
    @Published var recent: [RouteRecord] = []
    @Published var routingOn = false
    @Published var busy: Set<UUID> = []
    @Published var errors: [UUID: String] = [:]
    /// A just-created universe whose name field should open focused.
    @Published var renameOnOpen: UUID?

    private var configDate = Config.modificationDate
    private var configWatcher: DispatchSourceFileSystemObject?

    init() {
        refreshRouting()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Store.shared.refreshRouting() }
        }
        // Pick up edits made outside the app (by hand, by an agent, or by `Multiverse build`).
        // Watches the folder (saves replace the file) instead of polling.
        let fd = open(Config.url.deletingLastPathComponent().path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { Task { @MainActor in Store.shared.reloadIfChanged() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            configWatcher = source
        }
    }

    func reloadIfChanged() {
        let date = Config.modificationDate
        guard date != configDate else { return }
        configDate = date
        guard let fresh = Config.loadIfValid() else { return }  // keep what we have; never save over a bad file
        if fresh != config {
            config = fresh
            Log.write("config reloaded from disk")
        }
        configDate = Config.modificationDate
    }

    func route(_ urls: [URL], senderPID: pid_t) {
        let (opener, universe) = Router.universe(forSenderPID: senderPID, in: config)
        guard let universe else {
            Log.write("\(opener) -> no universe configured")
            return
        }
        for url in urls {
            Log.write("\(opener) -> \(universe.name) \(url.host ?? url.scheme ?? "")")
            recent.insert(RouteRecord(opener: opener, universe: "\(universe.emoji) \(universe.name)",
                                      host: url.host ?? url.absoluteString), at: 0)
        }
        recent = Array(recent.prefix(10))
        Router.open(urls, in: universe.browser)
    }

    func tint(for entry: AppEntry) -> NSColor? {
        config.universe(entry.universeID).flatMap { NSColor(hex: $0.color ?? "") }
    }

    /// Creates or updates the app for `entry` off the main thread. Adds the entry to the config on success.
    func build(_ entry: AppEntry, done: ((Bool) -> Void)? = nil) {
        busy.insert(entry.id)
        errors[entry.id] = nil
        let tint = tint(for: entry)
        Task.detached {
            let result = Result { try Builder.build(entry, tint: tint) }
            await MainActor.run {
                self.busy.remove(entry.id)
                switch result {
                case .success(let built):
                    if let i = self.config.apps.firstIndex(where: { $0.id == built.id }) {
                        // Keep edits made while building; take only what the build filled in.
                        self.config.apps[i].bundleID = built.bundleID
                        self.config.apps[i].dataDir = built.dataDir
                    } else {
                        self.config.apps.append(built)
                    }
                    done?(true)
                case .failure(let error):
                    self.errors[entry.id] = error.localizedDescription
                    Log.write("build \(entry.name) failed: \(error)")
                    done?(false)
                }
            }
        }
    }

    func updateAllCopies() {
        config.apps.filter { $0.kind == .clone && Builder.updateAvailable($0) != nil }.forEach { build($0) }
    }

    /// Removes the entry. With `trashCopy`, also moves a copy Multiverse made to the Trash.
    /// Its data folder is left alone.
    func remove(_ entry: AppEntry, trashCopy: Bool) {
        config.apps.removeAll { $0.id == entry.id }
        guard trashCopy, entry.kind != .original else { return }
        let url = URL(fileURLWithPath: entry.installedPath)
        guard Builder.isOurCopy(at: url, of: entry) else { return }
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch {
            Log.write("trash \(url.path) failed: \(error)")
        }
    }

    func removeUniverse(_ u: Universe) {
        config.apps.removeAll { $0.universeID == u.id }
        config.universes.removeAll { $0.id == u.id }
        if config.defaultUniverseID == u.id { config.defaultUniverseID = config.universes.first?.id }
    }

    func makeDefaultBrowser() {
        let me = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { error in
                if let error { Log.write("set default browser failed: \(error)") }
                Task { @MainActor in Store.shared.refreshRouting() }
            }
        }
    }

    func refreshRouting() {
        routingOn = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?.standardizedFileURL
            == Bundle.main.bundleURL.standardizedFileURL
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            Log.write("ignored a link that isn't http(s)")
            return
        }
        let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value ?? 0
        Task { @MainActor in Store.shared.route([url], senderPID: pid) }
    }

    /// Opening Multiverse again (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Store.shared.config.universes.isEmpty { showSettings() }
    }

    /// Local .html files and the like go to the default universe.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            if let u = Store.shared.config.defaultUniverse { Router.open(urls, in: u.browser) }
        }
    }
}

struct MultiverseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra("Multiverse", systemImage: "circle.hexagongrid.circle") {
            MenuContent().environmentObject(store)
        }

    }
}

struct MenuContent: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if !store.routingOn {
            Button("⚠︎ Links aren't being routed – turn on…") { store.makeDefaultBrowser() }
            Divider()
        }
        ForEach(store.config.universes) { u in
            Section("\(u.emoji) \(u.name)") {
                ForEach(store.config.apps.filter { $0.universeID == u.id }) { app in
                    Button {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.installedPath),
                                                           configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: appIcon(app.installedPath, size: 16)) }
                    }
                }
            }
        }
        Divider()
        if !store.recent.isEmpty {
            Menu("Recent links") {
                ForEach(store.recent) { r in Text("\(r.host) → \(r.universe)  (from \(r.opener))") }
            }
        }
        if store.config.apps.contains(where: { Builder.updateAvailable($0) != nil }) {
            Button("Update copies of updated apps") { store.updateAllCopies() }
        }
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Multiverse") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// Settings lives in a plain NSWindow we own: SwiftUI's Settings scene can't be opened reliably
/// from a menu bar app (or from AppKit callbacks like reopen).
@MainActor private var settingsWindow: NSWindow?

@MainActor func showSettings() {
    if settingsWindow == nil {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Multiverse"
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.contentViewController = NSHostingController(
            rootView: SettingsView().environmentObject(Store.shared))
        window.setContentSize(NSSize(width: 820, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("MultiverseSettings")
        settingsWindow = window
    }
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
    // Don't start with a cursor in the first text field.
    DispatchQueue.main.async { settingsWindow?.makeFirstResponder(nil) }
    settingsWindow?.orderFrontRegardless()  // menu bar apps can be refused activation; still show it on top
}

func appIcon(_ path: String, size: CGFloat) -> NSImage {
    let img = NSWorkspace.shared.icon(forFile: expand(path))
    img.size = NSSize(width: size, height: size)
    return img
}
