import ServiceManagement
import SwiftUI

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var config = Config.load() {
        didSet { config.save(); claimAppSchemes() }
    }
    @Published var recent: [RouteRecord] = []
    @Published var routingOn = false
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var busy: Set<UUID> = []
    @Published var errors: [UUID: String] = [:]
    /// Universe for Settings to show next time it appears (e.g. after setup).
    @Published var showUniverse: UUID?
    /// A just-created universe whose name field should open focused.
    @Published var renameOnOpen: UUID?
    /// Bundle ids of apps (like Notion) seen handing their own links back to Multiverse, which means
    /// the user turned off their "open links in the app" setting and routing them works.
    @Published var linkOwnersConfirmed: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "linkOwnersConfirmed") ?? []) {
        didSet { UserDefaults.standard.set(Array(linkOwnersConfirmed), forKey: "linkOwnersConfirmed") }
    }

    /// Recently activated apps, newest last, to tell which app a bounced link was clicked in.
    private var activations: [(pid: pid_t, date: Date)] = []
    private var configDate = Config.modificationDate
    private var configWatcher: DispatchSourceFileSystemObject?

    init() {
        refreshRouting()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid() else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                Store.shared.activations.append((pid, Date()))
                Store.shared.activations = Array(Store.shared.activations.suffix(8))
            }
        }
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
        for url in urls { route(url, senderPID: senderPID) }
        recent = Array(recent.prefix(10))
    }

    private func route(_ url: URL, senderPID: pid_t) {
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            return routeAppLink(url, scheme: scheme, senderPID: senderPID)
        }
        var pid = senderPID
        var via = ""
        // An app that owns this link (e.g. Notion with "open links in desktop app" off) received it
        // from macOS first and handed it back. Credit it to the app the user actually clicked in.
        if let bouncer = bouncer(of: url, senderPID: senderPID), let clicked = appBefore(bouncer) {
            if let id = bouncer.bundleIdentifier, !linkOwnersConfirmed.contains(id) { linkOwnersConfirmed.insert(id) }
            via = " via \(bouncer.localizedName ?? bouncer.bundleIdentifier ?? "pid:\(bouncer.processIdentifier)")"
            pid = clicked
        }
        let (opener, universe) = Router.universe(forSenderPID: pid, in: config)
        guard let universe else {
            Log.write("\(opener)\(via) -> no universe configured")
            return
        }
        let owner = Router.owner(of: url, in: universe, senderPath: ProcessInfoLite(pid: pid).bundlePath, config: config)
        Log.write("\(opener)\(via) -> \(universe.name)\(owner.map { " (\($0.name))" } ?? "") \(url.host ?? url.scheme ?? "")")
        recent.insert(RouteRecord(opener: opener, universe: "\(universe.emoji) \(universe.name)",
                                  host: url.host ?? url.absoluteString, app: owner?.name), at: 0)
        if let owner { Router.open([url], inApp: owner) } else { Router.open([url], in: universe.browser) }
    }

    /// An app's own link (like notion://, from a web page's "Open in app" button) goes to that app's
    /// copy in the universe it came from: the universe of the browser or app that sent it.
    private func routeAppLink(_ url: URL, scheme: String, senderPID: pid_t) {
        // The sender may be gone already (`open`); then it's the app the user was just in.
        let me = getpid()
        let pid = [owningApp(senderPID)?.processIdentifier, NSWorkspace.shared.frontmostApplication?.processIdentifier,
                   activations.last?.pid].compactMap { $0 }.first { $0 != me } ?? senderPID
        let (opener, universe) = Router.browserUniverse(forPID: pid, in: config)
            .map { ("\($0.emoji) \($0.name)'s browser", Optional($0)) }
            ?? Router.universe(forSenderPID: pid, in: config)
        guard let universe, let target = Router.schemeTarget(scheme, in: universe, config: config) else {
            Log.write("\(opener) -> no app for \(scheme): links")
            return
        }
        Log.write("\(opener) -> \(universe.name) (\(target.name)) \(scheme):")
        recent.insert(RouteRecord(opener: opener, universe: "\(universe.emoji) \(universe.name)",
                                  host: "\(scheme): link", app: target.name), at: 0)
        Router.open([url], inApp: target)
    }

    /// The app behind `senderPID` if it is handing back a link it owns: it isn't in any universe,
    /// claims the link's host, and the user wasn't already working in it.
    private func bouncer(of url: URL, senderPID: pid_t) -> NSRunningApplication? {
        guard let host = url.host else { return nil }
        func handsBack(_ app: NSRunningApplication) -> Bool {
            guard let path = app.bundleURL?.path,
                  Router.entry(for: ProcessInfoLite(pid: app.processIdentifier), in: config) == nil,
                  Router.matches(host, Router.linkHosts(ofApp: path)) else { return false }
            // Frontmost for a while before the link came: the user clicked it inside that app.
            if let last = activations.last, last.pid == app.processIdentifier, Date().timeIntervalSince(last.date) > 2 {
                return false
            }
            return true
        }
        if let app = owningApp(senderPID) { return handsBack(app) ? app : nil }
        // The sender already exited: Notion hands links back through `open -b …`, which is gone by
        // now. Look for a running app that owns this link instead.
        return NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular && handsBack($0) }
    }

    /// The frontmost app if it isn't `app`, else the most recently active other app in the last 30 seconds.
    private func appBefore(_ app: NSRunningApplication) -> pid_t? {
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           front != app.processIdentifier, front != getpid() { return front }
        return activations.last { $0.pid != app.processIdentifier && Date().timeIntervalSince($0.date) < 30 }?.pid
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
        rememberPreviousBrowser()
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
        openAtLogin = SMAppService.mainApp.status == .enabled
        claimAppSchemes()
    }

    /// Takes over app link schemes (notion://) while an app that uses them is in a universe, so
    /// "Open in app" buttons reach the right copy, and gives them back to the app otherwise.
    func claimAppSchemes() {
        let me = Bundle.main.bundleURL.standardizedFileURL
        guard me.path.hasPrefix("/Applications/") else { return }  // not from a dev build
        for scheme in Router.ownSchemes {
            let sources = config.apps.map { URL(fileURLWithPath: expand($0.sourcePath)).standardizedFileURL }
                .filter { Router.schemes(ofApp: $0.path).contains(scheme) }
            let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://")!)?.standardizedFileURL
            let want = sources.isEmpty ? Router.originalHandler(for: scheme) : me
            guard let want, current != want else { continue }
            NSWorkspace.shared.setDefaultApplication(at: want, toOpenURLsWithScheme: scheme) { error in
                Log.write(error.map { "could not hand \(scheme): links to \(want.lastPathComponent): \($0.localizedDescription)" }
                          ?? "\(scheme): links now go to \(want.lastPathComponent)")
            }
        }
    }

    /// Adds or removes Multiverse from the login items (System Settings → General → Login Items).
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("open at login: \(error.localizedDescription)")
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Turns on opening at login once, the first time Multiverse runs from /Applications.
    /// After that it's the user's choice, so switching it off sticks.
    func enableOpenAtLoginOnce() {
        let key = "openAtLoginSet"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        setOpenAtLogin(true)
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
              let url = URL(string: s),
              (["http", "https"] + Router.ownSchemes).contains(url.scheme?.lowercased() ?? "") else {
            Log.write("ignored a link Multiverse doesn't route")
            return
        }
        let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value ?? 0
        // macOS brings the default browser (us) forward for each link; don't let Settings flash up.
        MainActor.assumeIsolated { closeSettings() }
        Task { @MainActor in Store.shared.route([url], senderPID: pid) }
    }

    /// Opening Multiverse again (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.enableOpenAtLoginOnce()
        if !showOnboardingIfNeeded(), Store.shared.config.universes.isEmpty { showSettings() }
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
        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            Image(nsImage: menuBarIcon)
        }

    }
}

struct MenuContent: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if !store.routingOn {
            Button("⚠︎ Links aren't being routed – finish setup…") { showOnboarding() }
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
                ForEach(store.recent) { r in
                    Text("\(r.host) → \(r.universe)\(r.app.map { " · \($0)" } ?? "")  (from \(r.opener))")
                }
            }
        }
        if store.config.apps.contains(where: { Builder.updateAvailable($0) != nil }) {
            Button("Update copies of updated apps") { store.updateAllCopies() }
        }
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Button("Setup & permissions…") { showOnboarding() }
        Toggle("Open at login", isOn: Binding(get: { store.openAtLogin }, set: { store.setOpenAtLogin($0) }))
        Divider()
        Button("Quit Multiverse") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// Settings lives in a plain NSWindow we own: SwiftUI's Settings scene can't be opened reliably
/// from a menu bar app (or from AppKit callbacks like reopen).
@MainActor private var settingsWindow: NSWindow?

/// Template image so macOS tints it for light/dark menu bars and the highlighted state.
let menuBarIcon: NSImage = {
    let image = Bundle.main.image(forResource: "MenuBarIcon") ?? NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)!
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    image.accessibilityDescription = "Multiverse"
    return image
}()

let previousBrowserKey = "previousDefaultBrowser"

/// Remember the browser Multiverse is about to replace, to suggest it in setup (and to restore it).
func rememberPreviousBrowser() {
    guard let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
          Bundle(url: current)?.bundleIdentifier != "io.github.0xcen.multiverse" else { return }
    UserDefaults(suiteName: "io.github.0xcen.multiverse")?.set(current.path, forKey: previousBrowserKey)
    UserDefaults.standard.set(current.path, forKey: previousBrowserKey)
}

@MainActor func closeSettings() {
    guard let w = settingsWindow, w.isVisible else { return }
    w.orderOut(nil)
    NSApp.hide(nil)
    updateActivationPolicy()
}

/// With a window open, Multiverse shows in the Dock and Cmd-Tab like a normal app; otherwise it
/// lives only in the menu bar.
@MainActor func updateActivationPolicy() {
    let windowOpen = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
    let policy: NSApplication.ActivationPolicy = windowOpen ? .regular : .accessory
    if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
}

/// Call once a window is created: re-evaluate when it closes.
@MainActor func trackForActivationPolicy(_ window: NSWindow) {
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
        // The window is still visible during willClose; check right after.
        DispatchQueue.main.async { MainActor.assumeIsolated { updateActivationPolicy() } }
    }
}

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
        trackForActivationPolicy(window)
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
    // Don't start with a cursor in the first text field.
    DispatchQueue.main.async { settingsWindow?.makeFirstResponder(nil) }
    settingsWindow?.orderFrontRegardless()  // menu bar apps can be refused activation; still show it on top
}

private let iconCache = NSCache<NSString, NSImage>()

/// An app's icon at a size, cached (SwiftUI asks for it on every redraw).
func appIcon(_ path: String, size: CGFloat) -> NSImage {
    let key = "\(path)|\(size)" as NSString
    if let cached = iconCache.object(forKey: key) { return cached }
    let img = NSWorkspace.shared.icon(forFile: expand(path))
    img.size = NSSize(width: size, height: size)
    iconCache.setObject(img, forKey: key)
    return img
}
