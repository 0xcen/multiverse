import SwiftUI
import UniformTypeIdentifiers

// MARK: - Window

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Your multiverse") {
                    ForEach(store.config.universes) { u in
                        HStack {
                            Text(u.emoji)
                            Text(u.name)
                            Spacer()
                            if store.config.defaultUniverse?.id == u.id {
                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Brand.muted)
                                    .help("Main universe: every app not in another universe belongs here")
                            }
                            Circle().fill(Color(nsColor: NSColor(hex: u.color ?? "") ?? .tertiaryLabelColor))
                                .frame(width: 8, height: 8)
                        }
                        .tag(u.id)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    selection = newUniverse()
                } label: {
                    Label("New universe", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if !store.routingOn { RoutingBanner() }
                if let i = store.config.universes.firstIndex(where: { $0.id == selection }) {
                    UniversePage(universe: $store.config.universes[i])
                        .id(store.config.universes[i].id)
                } else {
                    ContentUnavailable()
                }
            }
            .background(Brand.background)
        }
        .tint(Brand.ink)
        .onAppear {
            store.refreshRouting()
            if let id = store.showUniverse { selection = id; store.showUniverse = nil }
            if selection == nil { selection = store.config.universes.first?.id }
        }
        .onChange(of: store.showUniverse) { _, id in
            if let id { selection = id; store.showUniverse = nil }
        }
    }

    private func newUniverse() -> UUID {
        let used = Set(store.config.universes.compactMap(\.color))
        let color = Universe.palette.first { !used.contains($0) } ?? Universe.palette[0]
        let browser = store.config.defaultUniverse?.browser
            ?? BrowserTarget(appPath: installedBrowsers().first?.path ?? "/Applications/Safari.app")
        let u = Universe(name: "New universe", emoji: "🪐", browser: browser, color: color)
        store.config.universes.append(u)
        if store.config.defaultUniverseID == nil { store.config.defaultUniverseID = u.id }
        store.renameOnOpen = u.id
        return u.id
    }
}

struct RoutingBanner: View {
    @EnvironmentObject var store: Store
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.ink)
            Text("Links aren't being routed yet. Finish setup to let Multiverse pass each link to the right browser.")
                .font(.callout)
            Spacer()
            Button("Finish setup") { showOnboarding() }.buttonStyle(.brand)
        }
        .padding(.horizontal, Space.page).padding(.vertical, 10)
        .background(Brand.olive.opacity(0.18))
    }
}

struct ContentUnavailable: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            SectionLabel("Your multiverse is empty. Create a universe, like Work or Personal.")
            Text("Put apps in it, and links you open from those apps go to that universe's browser.")
                .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Universe page

struct UniversePage: View {
    @EnvironmentObject var store: Store
    @Binding var universe: Universe
    @State private var adding = false
    @State private var confirmDelete = false
    @State private var renaming = false

    private var apps: [AppEntry] { store.config.apps.filter { $0.universeID == universe.id } }
    private var isDefault: Bool { store.config.defaultUniverse?.id == universe.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                header

                VStack(alignment: .leading, spacing: Space.label) {
                    SectionLabel("Links open in")
                    BrowserPicker(universe: $universe)
                    Text(isDefault
                         ? "Main universe: used for links from every app that isn't in another universe."
                         : "Used for links you open from the apps below.")
                        .font(.callout).foregroundStyle(Brand.muted)
                        .padding(.top, Space.caption - Space.label)
                }

                VStack(alignment: .leading, spacing: Space.label) {
                    HStack(alignment: .center) {
                        SectionLabel("Apps")
                        Spacer()
                        Button { adding = true } label: { Label("Add app", systemImage: "plus") }
                            .buttonStyle(.brandQuiet)
                    }
                    if apps.isEmpty {
                        Text(isDefault
                             ? "Every app that isn't in another universe is in \(universe.name). Add an app here only to give it a separate copy."
                             : "Every app is in \(store.config.defaultUniverse.map { "\($0.emoji) \($0.name)" } ?? "your main universe") until you add it here. Add apps that belong to \(universe.name), or a separate copy of one you use in both.")
                            .font(.callout).foregroundStyle(Brand.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 0) {
                        ForEach(apps) { app in
                            AppRow(entry: app)
                            if app.id != apps.last?.id { Divider() }
                        }
                    }
                    .brandCard(radius: Space.radius)
                }
            }
            .padding(.horizontal, Space.page).padding(.vertical, Space.page - 4)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .sheet(isPresented: $adding) { AddAppSheet(universe: universe) }
        .onAppear {
            if store.renameOnOpen == universe.id { renaming = true; store.renameOnOpen = nil }
        }
        .confirmationDialog("Delete \(universe.name)?", isPresented: $confirmDelete) {
            Button("Delete universe", role: .destructive) { store.removeUniverse(universe) }
        } message: {
            Text("Its apps are removed from Multiverse. Copies stay in /Applications and no data is deleted.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            EmojiButton(emoji: $universe.emoji)
                .offset(y: -2)  // emoji glyphs sit low next to cap-height text
            UniverseTitle(name: $universe.name, editing: $renaming)
            Spacer()
            ColorSwatches(color: $universe.color)
                .help("Colour, used for tinted app icons")
                .padding(.trailing, 6)
            Menu {
                Button("Rename") { renaming = true }
                Button("Make this the main universe") { store.config.defaultUniverseID = universe.id }
                    .disabled(isDefault)
                Divider()
                Button("Delete universe…", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// The universe name as plain text (so it lines up with the emoji); click to rename.
struct UniverseTitle: View {
    @Binding var name: String
    @Binding var editing: Bool
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("Name", text: $draft)
                .font(Brand.heading(34)).tracking(-1)
                .textFieldStyle(.plain)
                .focused($focused)
                .onAppear {
                    draft = name
                    DispatchQueue.main.async { focused = true }  // after the view is in the window
                }
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onExitCommand { editing = false }
        } else {
            Text(name.isEmpty ? "Untitled" : name)
                .font(Brand.heading(34)).tracking(-1)
                .foregroundStyle(name.isEmpty ? .secondary : .primary)
                .onTapGesture { draft = name; editing = true }
                .help("Click to rename")
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { name = trimmed }
        editing = false
    }
}

/// Shows the universe's emoji; click to pick another. A button rather than a text field, so the window
/// doesn't put a cursor in it on open and a stray key can't wipe it.
struct EmojiButton: View {
    @Binding var emoji: String
    @State private var picking = false
    @State private var custom = ""

    static let choices = Array("💼🏠🏢👨‍💻🧑‍💻🎨🎮🎵📚🔬🧪💰📈🛠️🚀🌱🌍🏖️❤️⭐️🔥⚡️🌙☀️🪐🐙🦊🐼🍀🍕☕️🎯🧠🔒🧳🏃🧘✈️🎬📷").map(String.init)

    var body: some View {
        Button { picking = true } label: {
            Text(emoji.isEmpty ? "🙂" : emoji)
                .font(.system(size: 30))
                .opacity(emoji.isEmpty ? 0.4 : 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(picking ? 1 : 0)).padding(-4))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Change emoji")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 8), spacing: 6) {
                    ForEach(Self.choices, id: \.self) { e in
                        Button { emoji = e; picking = false } label: {
                            Text(e).font(.system(size: 22)).frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Or type any emoji", text: $custom)
                        .onSubmit { useCustom() }
                    Button("Use") { useCustom() }.disabled(custom.isEmpty)
                }
            }
            .padding(12)
            .frame(width: 300)
        }
    }

    private func useCustom() {
        guard let first = custom.trimmingCharacters(in: .whitespaces).first else { return }
        emoji = String(first)
        custom = ""
        picking = false
    }
}

// MARK: - App row

struct AppRow: View {
    @EnvironmentObject var store: Store
    let entry: AppEntry
    @State private var confirmRemove = false

    /// The copy Multiverse made is in place (not just any app with the same name).
    private var exists: Bool {
        entry.kind == .original
            ? FileManager.default.fileExists(atPath: entry.installedPath)
            : Bundle(url: URL(fileURLWithPath: entry.installedPath))?.bundleIdentifier == entry.bundleID && entry.bundleID != nil
    }
    /// Another app already has this copy's name, so the copy can't be created under it.
    private var nameTaken: Bool {
        entry.kind != .original && !exists && FileManager.default.fileExists(atPath: entry.installedPath)
    }
    private var sourceName: String { appName(entry.sourcePath) }
    private var update: String? { Builder.updateAvailable(entry) }
    private var busy: Bool { store.busy.contains(entry.id) }
    /// The original claims some links as its own (universal links), like Notion does notion.so.
    private var ownsLinks: Bool { !Router.linkHosts(of: entry).isEmpty }
    private var opensOwnLinks: Binding<Bool> {
        Binding(get: { entry.opensOwnLinks == true }, set: { on in
            if let i = store.config.apps.firstIndex(where: { $0.id == entry.id }) { store.config.apps[i].opensOwnLinks = on }
        })
    }
    /// Multiverse has seen the original hand one of its links back, so its setting is off.
    private var linksConfirmed: Bool {
        Bundle(url: URL(fileURLWithPath: expand(entry.sourcePath)))?.bundleIdentifier
            .map(store.linkOwnersConfirmed.contains) ?? false
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon(exists ? entry.installedPath : entry.sourcePath, size: 36))
                .opacity(exists ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(Brand.muted)
                if ownsLinks && exists && !nameTaken {
                    Toggle(isOn: opensOwnLinks) {
                        Text("Open \(sourceName) links here instead of the browser").font(.caption)
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                    .padding(.top, 2)
                }
                if exists && !nameTaken && Router.ownSchemes.contains(where: Router.schemes(ofApp: entry.sourcePath).contains),
                   let u = store.config.universe(entry.universeID) {
                    Text("**Open in app** on \(sourceName) pages in \(appName(u.browser.appPath))\(u.browser.dataDir == nil ? "" : " (\(u.name))") opens \(entry.name).")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                if nameTaken {
                    Text("There's already an app called \(entry.name), so this copy can't use that name. Remove it and add it again with another name.")
                        .font(.caption).foregroundStyle(.red)
                } else if let err = store.errors[entry.id] {
                    Text(err).font(.caption).foregroundStyle(.red)
                } else if let update {
                    Text("\(sourceName) was updated to \(update). Update this copy to match.")
                        .font(.caption).foregroundStyle(.orange)
                } else if ownsLinks && !linksConfirmed {
                    LinkSettingCallout(source: sourceName, sourcePath: entry.sourcePath)
                }
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if nameTaken {
                EmptyView()
            } else if entry.kind != .original && !exists {
                Button("Create") { store.build(entry) }.buttonStyle(.brand)
            } else if update != nil {
                Button("Update") { store.build(entry) }.buttonStyle(.brand)
            } else {
                Button("Open") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: entry.installedPath),
                                                       configuration: NSWorkspace.OpenConfiguration())
                }
                .buttonStyle(.brandQuiet)
            }
            Menu {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.installedPath)])
                }
                if entry.kind != .original && exists {
                    Button("Recreate copy") { store.build(entry) }
                }
                Divider()
                Button("Remove…", role: .destructive) { confirmRemove = true }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, Space.rowH)
        .padding(.vertical, Space.rowV)
        .confirmationDialog("Remove \(entry.name)?", isPresented: $confirmRemove) {
            Button("Remove from Multiverse") { store.remove(entry, trashCopy: false) }
            if entry.kind != .original && exists {
                Button("Remove and move the copy to Trash", role: .destructive) { store.remove(entry, trashCopy: true) }
            }
        } message: {
            Text(entry.kind == .original
                 ? "\(entry.name) stays installed. Its links will open in the default universe."
                 : "Logins and data for \(entry.name) are kept either way.")
        }
    }

    private var subtitle: String {
        switch entry.kind {
        case .original: "Installed app"
        case .launcher: "Separate \(sourceName) · own logins"
        case .clone:
            "Copy of \(sourceName) · " + (entry.dataDir != nil || !entry.env.isEmpty
                                            ? "own logins" : "shares logins with \(sourceName)")
        }
    }
}

// MARK: - Browser picker

struct BrowserPicker: View {
    @EnvironmentObject var store: Store
    @Binding var universe: Universe
    @State private var newBrowser: URL?

    private var target: BrowserTarget {
        get { universe.browser }
        nonmutating set { universe.browser = newValue }
    }

    var body: some View {
        let options = browserOptions()
        HStack(spacing: 10) {
            Menu {
                ForEach(options, id: \.target) { o in
                    Button { target = o.target } label: {
                        Label { Text(o.label) } icon: { Image(nsImage: appIcon(o.target.appPath, size: 16)) }
                    }
                }
                Divider()
                Menu("Make a separate browser for \(universe.name)") {
                    ForEach(installedBrowsers().filter { Builder.supportsProfiles($0) }, id: \.self) { b in
                        Button { newBrowser = b } label: {
                            Label { Text("New \(appName(b.path)) with its own logins") } icon: { Image(nsImage: appIcon(b.path, size: 16)) }
                        }
                    }
                }
                Button("Another profile folder…") { chooseProfileFolder() }
            } label: {
                HStack(spacing: 8) {
                    Image(nsImage: appIcon(target.appPath, size: 18))
                    Text(options.first { normalized($0.target) == normalized(target) }?.label ?? label(for: target))
                }
            }
            // macOS draws a menu's label itself, so the pill goes around the control, not inside it.
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 5)
            .background(Capsule().fill(Brand.panel))
            .overlay(Capsule().strokeBorder(Brand.border))
            .contentShape(Capsule())
        }
        .sheet(item: $newBrowser) { b in
            SeparateBrowserSheet(browser: b, universe: universe, suggestedName: suggestedName(for: b))
        }
    }

    /// Suggests "<Universe> <Browser>", numbered if that name is taken.
    private func suggestedName(for browser: URL) -> String {
        let base = "\(universe.name) \(appName(browser.path))"
        var name = base, n = 2
        while FileManager.default.fileExists(atPath: "/Applications/\(name).app")
                || store.config.apps.contains(where: { $0.name == name }) {
            name = "\(base) \(n)"; n += 1
        }
        return name
    }

    private struct Option { let target: BrowserTarget; let label: String }

    private func normalized(_ t: BrowserTarget) -> BrowserTarget {
        BrowserTarget(appPath: expand(t.appPath), dataDir: t.dataDir.map(expand))
    }

    private func label(for t: BrowserTarget) -> String {
        guard let dir = t.dataDir else { return appName(t.appPath) }
        let profile = store.config.apps.first { $0.kind == .launcher && $0.dataDir.map(expand) == expand(dir) }?.name
            ?? (expand(dir) as NSString).lastPathComponent
        return "\(appName(t.appPath)) · \(profile)"
    }

    /// Installed browsers, their known profiles, and copies of browsers made in Multiverse.
    private func browserOptions() -> [Option] {
        let browsers = installedBrowsers()
        var targets: [BrowserTarget] = browsers.map { BrowserTarget(appPath: $0.path) }
        for app in store.config.apps {
            if app.kind == .launcher, let dir = app.dataDir {
                targets.append(BrowserTarget(appPath: app.sourcePath, dataDir: dir))
            }
            if app.kind == .clone, browsers.contains(where: { $0.path == expand(app.sourcePath) }) {
                targets.append(BrowserTarget(appPath: app.installedPath))
            }
        }
        targets += store.config.universes.map(\.browser)
        let profiles = existingProfiles()
        targets += profiles.map(\.target)
        var seen = Set<BrowserTarget>()
        return targets.filter { seen.insert(normalized($0)).inserted }.map { t in
            Option(target: t, label: profiles.first { normalized($0.target) == normalized(t) }?.name ?? label(for: t))
        }
    }

    private func chooseProfileFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the profile folder for \(appName(target.appPath))"
        panel.message = "Chromium-based browsers keep each profile in its own folder (started with --user-data-dir)."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        if panel.runModal() == .OK, let url = panel.url {
            target = BrowserTarget(appPath: target.appPath, dataDir: (url.path as NSString).abbreviatingWithTildeInPath)
        }
    }
}

/// Browsers installed as apps: one per bundle id, only from the Applications folders (not test builds
/// in caches), and not background link routers (Multiverse itself, Finicky, Velja…).
func installedBrowsers() -> [URL] {
    let me = Bundle.main.bundleURL.standardizedFileURL
    let roots = ["/Applications/", "/System/Applications/", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/",
                 NSHomeDirectory() + "/Applications/"]
    var byID: [String: URL] = [:]
    for url in NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).map(\.standardizedFileURL) {
        guard url != me, roots.contains(where: { url.path.hasPrefix($0) }),
              !url.deletingLastPathComponent().path.contains(".app"),  // helpers inside another app
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id != "io.github.0xcen.multiverse",
              bundle.infoDictionary?["LSUIElement"] as? Bool != true,
              bundle.infoDictionary?["LSBackgroundOnly"] as? Bool != true else { continue }
        // Same app found twice: keep the one in /Applications (copies keep their original id, so key by path then).
        let key = Bundle(url: url).flatMap { $0.infoDictionary?[Builder.ownerKey] as? String } ?? id
        if let existing = byID[key], existing.path.hasPrefix("/Applications/") { continue }
        byID[key] = url
    }
    return byID.values.sorted { appName($0.path) < appName($1.path) }
}

/// A browser profile that's already set up on this Mac: a small launcher app (like a hand-made
/// "Dia Personal") that starts a browser with its own --user-data-dir.
struct ExistingProfile: Hashable {
    let name: String
    let launcherPath: String
    let target: BrowserTarget
}

func existingProfiles() -> [ExistingProfile] {
    let browsers = installedBrowsers()
    let home = NSHomeDirectory()
    var out: [ExistingProfile] = []
    for dir in ["/Applications", home + "/Applications"] {
        for item in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where item.hasSuffix(".app") {
            let app = URL(fileURLWithPath: dir).appendingPathComponent(item)
            guard let exe = Bundle(url: app)?.executableURL,
                  let size = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.size] as? Int, size < 16_000,
                  let script = try? String(contentsOf: exe, encoding: .utf8), script.hasPrefix("#!"),
                  script.contains("--user-data-dir") else { continue }
            guard let browser = browsers.first(where: { script.contains($0.path + "/Contents/MacOS/") }) else { continue }
            // DATA_DIR="…" or --user-data-dir="…"
            let patterns = [#"DATA_DIR=["']([^"'\n]+)["']"#, #"--user-data-dir=["']([^"'\n]+)["']"#, #"--user-data-dir=([^\s"']+)"#]
            var dataDir: String?
            for pattern in patterns {
                if let r = script.range(of: pattern, options: .regularExpression) {
                    let match = String(script[r])
                    if let q = match.firstIndex(where: { $0 == "\"" || $0 == "'" }) ?? match.firstIndex(of: "=").map({ match.index(after: $0) }) {
                        var value = String(match[match.index(after: q)...])
                        if let last = value.last, last == "\"" || last == "'" { value.removeLast() }
                        if match.hasPrefix("--user-data-dir="), !value.hasPrefix("$"), !value.hasPrefix("/") , !value.hasPrefix("~") { continue }
                        if value.contains("$DATA_DIR") { continue }
                        dataDir = value
                        break
                    }
                }
            }
            guard var dir = dataDir else { continue }
            dir = dir.replacingOccurrences(of: "$HOME", with: home).replacingOccurrences(of: "${HOME}", with: home)
            out.append(ExistingProfile(name: appName(app.path), launcherPath: app.path,
                                       target: BrowserTarget(appPath: browser.path, dataDir: (dir as NSString).abbreviatingWithTildeInPath)))
        }
    }
    return out.sorted { $0.name < $1.name }
}


// MARK: - Add app

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { appName(url.path) }
}

func installedApps(excluding config: Config) -> [InstalledApp] {
    let made = Set(config.apps.filter { $0.kind != .original }.map { URL(fileURLWithPath: $0.installedPath).standardizedFileURL })
    let dirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    var out: [InstalledApp] = []
    for dir in dirs {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for item in items where item.hasSuffix(".app") && !item.hasPrefix(".") {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(item).standardizedFileURL
            guard !made.contains(url), url != Bundle.main.bundleURL.standardizedFileURL else { continue }
            out.append(InstalledApp(url: url))
        }
    }
    return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

struct AddAppSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let universe: Universe

    enum Step { case pick, how, copy, ready }
    @State private var step = Step.pick
    @State private var search = ""
    @State private var apps: [InstalledApp] = []
    @State private var app: InstalledApp?
    @State private var name = ""
    @State private var icon = IconStyle.ivory
    @State private var draftID = UUID()

    init(universe: Universe, app: InstalledApp? = nil, step: Step = .pick) {
        self.universe = universe
        _app = State(initialValue: app)
        _step = State(initialValue: step)
        if let app, step == .copy { _name = State(initialValue: "\(universe.name) \(app.name)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.group) {
            switch step {
            case .pick: pick
            case .how: how
            case .copy: copy
            case .ready:
                if let built = store.config.apps.first(where: { $0.id == draftID }) {
                    CopyReadyView(entry: built) { dismiss() }
                }
            }
        }
        .padding(Space.sheet)
        .frame(width: 520, height: 510)
        .background(Brand.background)
        .tint(Brand.ink)
        .onAppear {
            let config = store.config
            Task.detached {
                let found = installedApps(excluding: config)
                await MainActor.run { apps = found }
            }
        }
    }

    // Step 1
    private var pick: some View {
        VStack(alignment: .leading, spacing: Space.group) {
            Text("Add an app to \(universe.emoji) \(universe.name)").font(Brand.heading(24)).tracking(-0.6)
            TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
            List(apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { a in
                Button {
                    app = a
                    step = .how
                } label: {
                    HStack {
                        Image(nsImage: appIcon(a.url.path, size: 24))
                        Text(a.name)
                        Spacer()
                        if let u = universeUsing(a) { Text("in \(u.emoji) \(u.name)").font(.caption).foregroundStyle(Brand.muted) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.buttonStyle(.brandQuiet).keyboardShortcut(.cancelAction) }
        }
    }

    // Step 2
    private var how: some View {
        let a = app!
        let elsewhere = universeUsing(a)
        let blocker = Builder.copyBlocker(a.url)
        let ownLogins = Builder.supportsProfiles(a.url)
        return VStack(alignment: .leading, spacing: Space.group) {
            HStack {
                Image(nsImage: appIcon(a.url.path, size: 40))
                Text("How should \(a.name) work in \(universe.name)?").font(Brand.heading(24)).tracking(-0.6)
            }
            ChoiceCard(
                title: "Use \(a.name) as it is",
                detail: "Links you open in \(a.name) will open in \(universe.name)'s browser.",
                disabledReason: elsewhere.map { "\(a.name) is already in \($0.emoji) \($0.name). Make a copy to use it in both." },
                recommended: elsewhere == nil
            ) { addAsIs(a) }
            ChoiceCard(
                title: "Make a separate copy for \(universe.name)",
                detail: "A second \(a.name) with its own name, Dock icon"
                    + (ownLogins ? " and its own logins." : ". It will share logins with the original."),
                disabledReason: blocker,
                recommended: elsewhere != nil
            ) {
                name = "\(universe.name) \(a.name)"
                step = .copy
            }
            if blocker != nil && ownLogins {
                ChoiceCard(
                    title: "Make a separate \(a.name) profile for \(universe.name)",
                    detail: "Its own logins and data, opened from a \(universe.name) \(a.name) app in Applications and Spotlight. Its windows share \(a.name)'s Dock icon.",
                    disabledReason: nil,
                    recommended: elsewhere != nil
                ) {
                    name = "\(universe.name) \(a.name)"
                    step = .copy
                }
            }
            Spacer()
            HStack {
                Button("Back") { step = .pick }.buttonStyle(.brandQuiet)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.brandQuiet).keyboardShortcut(.cancelAction)
            }
        }
    }

    // Step 3
    private var copy: some View {
        let a = app!
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let clash = FileManager.default.fileExists(atPath: "/Applications/\(trimmed).app")
            || store.config.apps.contains { $0.name == trimmed }
        let ownLogins = Builder.supportsProfiles(a.url)
        return VStack(alignment: .leading, spacing: Space.group) {
            Text(Builder.copyBlocker(a.url) == nil ? "Your copy of \(a.name)" : "Your \(a.name) profile").font(Brand.heading(24)).tracking(-0.6)
            VStack(alignment: .leading, spacing: Space.label) {
                SectionLabel("Name")
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                if let problem = AppEntry.nameProblem(trimmed), !trimmed.isEmpty {
                    Text(problem).font(.caption).foregroundStyle(.red)
                } else if clash {
                    Text("There's already an app called \(trimmed). Pick another name; nothing gets replaced.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            IconChooser(app: a.url, universeID: universe.id, selection: $icon)
            Label(ownLogins
                  ? "Gets its own logins and data, separate from \(a.name)."
                  : "\(a.name) doesn't support separate profiles, so this copy shares its logins.",
                  systemImage: ownLogins ? "checkmark.circle" : "info.circle")
                .font(.callout).foregroundStyle(ownLogins ? Brand.ink : Brand.muted)
            Label("After \(a.name) updates, Multiverse lets you update the copy with one click.", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout).foregroundStyle(Brand.muted)
            if let err = store.errors[draftID] { Text(err).font(.callout).foregroundStyle(.red) }
            Spacer()
            HStack {
                Button("Back") { step = .how }.buttonStyle(.brandQuiet)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.brandQuiet).keyboardShortcut(.cancelAction)
                if store.busy.contains(draftID) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Create \(trimmed)") {
                        let asProfile = Builder.copyBlocker(a.url) != nil
                        var e = AppEntry(name: trimmed, kind: asProfile ? .launcher : .clone, sourcePath: a.url.path,
                                         universeID: universe.id, dataDir: asProfile ? Builder.defaultDataDir(for: trimmed) : nil)
                        e.id = draftID
                        e.icon = icon
                        store.build(e) { ok in
                            guard ok else { return }
                            if Builder.supportsProfiles(a.url) { step = .ready } else { dismiss() }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.brand)
                    .disabled(trimmed.isEmpty || clash || AppEntry.nameProblem(trimmed) != nil)
                }
            }
        }
    }

    private func universeUsing(_ a: InstalledApp) -> Universe? {
        store.config.apps.first { $0.kind == .original && expand($0.sourcePath) == a.url.path }
            .flatMap { store.config.universe($0.universeID) }
    }

    private func addAsIs(_ a: InstalledApp) {
        store.config.apps.append(AppEntry(name: a.name, kind: .original, sourcePath: a.url.path, universeID: universe.id))
        dismiss()
    }
}

/// Three icon options for a new app, rendered from the real icon: universe colour, inverted, same.
struct IconChooser: View {
    @EnvironmentObject var store: Store

    private func label(_ style: IconStyle) -> String {
        switch style {
        case .ivory: "Ivory"
        case .graphite: "Graphite"
        case .tint: "\(universe.name) colour"
        case .invert: "Inverted"
        case .original: "Same"
        }
    }
    let app: URL
    let universeID: UUID
    @Binding var selection: IconStyle
    @State private var previews: [IconStyle: NSImage] = [:]

    private var universe: Universe {
        store.config.universe(universeID) ?? Universe(name: "", emoji: "", browser: BrowserTarget(appPath: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.label) {
            SectionLabel("Icon")
            HStack(spacing: 16) {
                ForEach([IconStyle.ivory, .graphite, .tint, .original]) { style in
                    VStack {
                        Group {
                            if let img = previews[style] { Image(nsImage: img).resizable() } else { ProgressView() }
                        }
                        .frame(width: 72, height: 72)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .stroke(selection == style ? Brand.ink : .clear, lineWidth: 2))
                        Text(label(style))
                            .font(.caption)
                    }
                    .onTapGesture { selection = style }
                }
            }
            if selection == .tint {
                HStack(spacing: 8) {
                    Text("\(universe.name) colour").font(.caption).foregroundStyle(Brand.muted)
                    ColorSwatches(color: Binding(
                        get: { universe.color },
                        set: { c in
                            if let i = store.config.universes.firstIndex(where: { $0.id == universeID }) {
                                store.config.universes[i].color = c
                            }
                        }))
                }
                .padding(.top, 2)
            }
        }
        .task(id: "\(app.path)|\(universe.color ?? "")") {
            let tint = NSColor(hex: universe.color ?? "") ?? .systemBlue
            let app = app
            previews = await Task.detached {
                var out: [IconStyle: NSImage] = [:]
                for style in IconStyle.allCases { out[style] = Icons.make(for: app, style: style, tint: tint, size: 256) }
                return out
            }.value
        }
    }
}

/// Shown right after creating a copy that macOS will ask about: what the keychain prompt looks like
/// and which button to press, then a button to open the copy so the prompt arrives in context.
struct CopyReadyView: View {
    let entry: AppEntry
    let done: () -> Void

    private var source: String { appName(entry.sourcePath) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.group) {
            HStack(spacing: 12) {
                Image(nsImage: appIcon(entry.installedPath, size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.name) is ready").font(Brand.heading(24)).tracking(-0.6)
                    Text("One thing to expect the first time it opens:").foregroundStyle(Brand.muted)
                }
            }
            Text("macOS will ask whether \(entry.name) may use “\(source) Safe Storage” from your keychain. That's where \(source) keeps the key that encrypts saved passwords and cookies, and macOS checks with you because \(entry.name) is a new app. Enter your Mac password and click **Always Allow**.")
                .fixedSize(horizontal: false, vertical: true)
            KeychainPromptPreview(app: entry.name, item: "\(source) Safe Storage", icon: appIcon(entry.installedPath, size: 28))
            Text("If you click Deny, \(entry.name) can't keep you signed in. You'll see this again after updating the copy.")
                .font(.caption).foregroundStyle(Brand.muted)
            if !Router.linkHosts(of: entry).isEmpty {
                Text("**One more thing for links:** \(source) opens its own links itself, before Multiverse sees them. In \(source)'s settings, turn off **Open links in desktop app**. Then \(source) links go to the browser of the universe you clicked them in, or to \(entry.name) if you switch that on in its row.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Later") { done() }.buttonStyle(.brandQuiet).keyboardShortcut(.cancelAction)
                Button("Open \(entry.name)") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: entry.installedPath),
                                                       configuration: NSWorkspace.OpenConfiguration())
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.brand)
            }
        }
    }
}

/// A small drawing of the macOS keychain dialog with the button to press highlighted.
struct KeychainPromptPreview: View {
    let app: String
    let item: String
    let icon: NSImage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill").font(.system(size: 30)).foregroundStyle(.yellow)
                Image(nsImage: icon).resizable().frame(width: 18, height: 18).offset(x: 6, y: 4)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(app) wants to use your confidential information stored in “\(item)” in your keychain.")
                    .font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("Password:").font(.caption)
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 18)
                        .overlay(Text("••••••••").font(.caption).padding(.leading, 6), alignment: .leading)
                }
                HStack(spacing: 6) {
                    Text("Always Allow").font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.ink.opacity(0.18)))
                        .overlay(Capsule().stroke(Brand.ink, lineWidth: 2))
                    Spacer()
                    Text("Deny").font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                    Text("Allow").font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                }
            }
        }
        .padding(Space.card)
        .brandCard(radius: Space.radius)
    }
}

struct ColorSwatches: View {
    @Binding var color: String?
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Universe.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(nsColor: NSColor(hex: hex) ?? .gray))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.primary, lineWidth: color == hex ? 2 : 0).padding(-3))
                    .onTapGesture { color = hex }
            }
        }
    }
}

/// Name and icon for a separate browser (its own profile) before creating it.
struct SeparateBrowserSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let browser: URL
    let universeID: UUID
    @State private var name: String
    @State private var icon = IconStyle.ivory
    @State private var draftID = UUID()
    @State private var ready = false
    private let blocker: String?

    init(browser: URL, universe: Universe, suggestedName: String) {
        self.blocker = Builder.copyBlocker(browser)
        self.browser = browser
        self.universeID = universe.id
        _name = State(initialValue: suggestedName)
    }

    private var universe: Universe? { store.config.universe(universeID) }

    var body: some View {
        if ready, let built = store.config.apps.first(where: { $0.id == draftID }) {
            CopyReadyView(entry: built) { dismiss() }
                .padding(Space.sheet)
                .frame(width: 520, height: 500)
        } else {
            form
        }
    }

    @ViewBuilder private var form: some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let clash = FileManager.default.fileExists(atPath: "/Applications/\(trimmed).app")
            || store.config.apps.contains { $0.name == trimmed }
        let browserName = appName(browser.path)
        VStack(alignment: .leading, spacing: Space.group) {
            HStack {
                Image(nsImage: appIcon(browser.path, size: 40))
                Text("A separate \(browserName) for \(universe?.name ?? "")").font(Brand.heading(24)).tracking(-0.6)
            }
            VStack(alignment: .leading, spacing: Space.label) {
                SectionLabel("Name")
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                if let problem = AppEntry.nameProblem(trimmed), !trimmed.isEmpty {
                    Text(problem).font(.caption).foregroundStyle(.red)
                } else if clash && !trimmed.isEmpty {
                    Text("There's already an app called \(trimmed). Pick another name; nothing gets replaced.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            IconChooser(app: browser, universeID: universeID, selection: $icon)
            Label("Its own logins, history and extensions, separate from your other \(browserName).",
                  systemImage: "checkmark.circle")
                .font(.callout).foregroundStyle(Brand.ink)
            if let blocker {
                Label("\(blocker) Instead it opens \(browserName) with its own profile: find \(trimmed.isEmpty ? "it" : trimmed) in Applications, Spotlight and the Multiverse menu, but its windows share \(browserName)'s Dock icon.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(Brand.muted)
            } else {
                Label("A separate app with its own Dock icon. Find it in Applications, Spotlight and the Multiverse menu.",
                      systemImage: "macwindow.on.rectangle")
                    .font(.callout).foregroundStyle(Brand.muted)
            }
            if let err = store.errors[draftID] { Text(err).font(.callout).foregroundStyle(.red) }
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.brandQuiet).keyboardShortcut(.cancelAction)
                if store.busy.contains(draftID) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Create \(trimmed)") { create(trimmed) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.brand)
                        .disabled(trimmed.isEmpty || clash || AppEntry.nameProblem(trimmed) != nil)
                }
            }
        }
        .padding(Space.sheet)
        .frame(width: 520, height: 500)
        .background(Brand.background)
        .tint(Brand.ink)
    }

    private func create(_ name: String) {
        // A real copy when the browser allows it; otherwise a separate profile of the original.
        let asProfile = blocker != nil
        let dataDir = asProfile ? Builder.defaultDataDir(for: name) : nil
        var entry = AppEntry(name: name, kind: asProfile ? .launcher : .clone, sourcePath: browser.path,
                             universeID: universeID, dataDir: dataDir, icon: icon)
        entry.id = draftID
        let universeID = universeID, target = asProfile
            ? BrowserTarget(appPath: browser.path, dataDir: dataDir)
            : BrowserTarget(appPath: entry.installedPath)
        store.build(entry) { ok in
            guard ok else { return }
            if let i = store.config.universes.firstIndex(where: { $0.id == universeID }) {
                store.config.universes[i].browser = target
            }
            ready = true
        }
    }
}

struct ChoiceCard: View {
    let title: String
    let detail: String
    let disabledReason: String?
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    if recommended && disabledReason == nil {
                        Text("Recommended").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Brand.ink.opacity(0.15)))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
                }
                Text(disabledReason ?? detail).font(.callout).foregroundStyle(Brand.muted)
            }
            .padding(Space.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandCard(radius: Space.radius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabledReason != nil)
        .opacity(disabledReason == nil ? 1 : 0.55)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// For apps like Notion that macOS hands their own links to before the default browser: how to
/// turn that off so Multiverse can route those links. Hidden once Multiverse sees it working.
struct LinkSettingCallout: View {
    let source: String
    let sourcePath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(source) opens its own links itself, before Multiverse sees them. Turn off **Open links in desktop app** in \(source)'s settings so Multiverse can send them to the right universe.")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open \(source)") {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: expand(sourcePath)),
                                                   configuration: NSWorkspace.OpenConfiguration())
            }
            .buttonStyle(.brandQuiet).controlSize(.small)
        }
        .padding(.top, 2)
    }
}
