import SwiftUI

/// Automation permission (Apple Events) for sending links to a browser profile.
enum Automation {
    enum State { case allowed, denied, notAsked, notRunning }

    /// With `ask`, macOS shows its "Multiverse wants to control …" prompt if it hasn't yet.
    /// Blocks until the user answers, so call it off the main thread when asking.
    static func state(for bundleID: String, ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .notRunning }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notAsked
        }
    }

    /// Browsers that links are handed to with an Apple Event (universes using a profile folder).
    static func targets(in config: Config) -> [(name: String, bundleID: String, path: String)] {
        var seen = Set<String>()
        return config.universes.compactMap { u in
            guard u.browser.dataDir != nil,
                  let id = Bundle(url: URL(fileURLWithPath: expand(u.browser.appPath)))?.bundleIdentifier,
                  seen.insert(id).inserted else { return nil }
            return (appName(u.browser.appPath), id, u.browser.appPath)
        }
    }
}

private let onboardedKey = "onboardingCompleted"

/// First launch shows setup; afterwards it's in the menu.
@MainActor func showOnboardingIfNeeded() -> Bool {
    guard !UserDefaults.standard.bool(forKey: onboardedKey) else { return false }
    showOnboarding()
    return true
}

@MainActor private var onboardingWindow: NSWindow?

@MainActor func showOnboarding() {
    if onboardingWindow == nil {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = "Set up Multiverse"
        window.contentViewController = NSHostingController(rootView: OnboardingView {
            UserDefaults.standard.set(true, forKey: onboardedKey)
            onboardingWindow?.close()
            showSettings()
        }.environmentObject(Store.shared))
        window.setContentSize(NSSize(width: 640, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
    }
    NSApp.activate()
    onboardingWindow?.makeKeyAndOrderFront(nil)
    onboardingWindow?.orderFrontRegardless()
}

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    @StateObject private var setup: SetupModel
    let finish: () -> Void
    @State private var step: Int
    private let steps = 5

    init(startAt step: Int = 0, setup: SetupModel? = nil, finish: @escaping () -> Void) {
        self.finish = finish
        _step = State(initialValue: step)
        _setup = StateObject(wrappedValue: setup ?? SetupModel(config: Store.shared.config))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: UniversesStep()
                case 2: AppsStep()
                case 3: BuildStep()
                default: PermissionsStep()
                }
            }
            .environmentObject(setup)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task { setup.loadApps(store.config) }

            Divider().padding(.horizontal, -32).padding(.bottom, 14)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 && step != 4 { Button("Back") { step -= 1 }.disabled(setup.building) }
                if step == 2 && setup.placements.isEmpty {
                    Button("Skip") { advance() }
                }
                if step < steps - 1 {
                    Button(continueTitle) { advance() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canContinue)
                } else {
                    Button("Done") { finish() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 640, height: 600)
    }

    private var continueTitle: String {
        switch step {
        case 0: "Get started"
        case 2: setup.placements.isEmpty ? "Continue" : "Set up \(setup.placements.count) app\(setup.placements.count == 1 ? "" : "s")"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: setup.universesValid
        case 3: !setup.building
        default: true
        }
    }

    private func advance() {
        if step == 1 { setup.saveUniverses(into: store) }
        if step == 2 { setup.planBuild(with: store) }
        step += 1
        if step == 3 { setup.runBuild(with: store) }
    }
}

// MARK: Step 1

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Keep work and personal apart").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 16) {
                Point(symbol: "circle.hexagongrid", title: "Universes",
                      text: "Group your apps into universes, like 💼 Work and 🏠 Personal.")
                Point(symbol: "square.on.square", title: "Separate copies",
                      text: "Use the same app in both, with separate logins and its own icon in the Dock.")
                Point(symbol: "link", title: "Links go to the right browser",
                      text: "A link you click in a work app opens in your work browser, and so on.")
            }
            Text("Setup takes a minute. macOS asks you to confirm a few things along the way; the next steps say what and why.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Point: View {
    let symbol: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Setup model

/// What the user is setting up, before it's written to the config and built.
@MainActor final class SetupModel: ObservableObject {
    struct Draft: Identifiable {
        var id = UUID()
        var name: String
        var emoji: String
        var color: String
        var browserPath: String
        /// Make a separate copy (or profile) of the browser for this universe.
        var separate: Bool
    }

    enum Placement: Hashable { case universe(UUID), every }

    struct Task: Identifiable {
        enum State: Equatable { case waiting, working, done, failed(String) }
        let id = UUID()
        let title: String
        let iconPath: String
        /// For copies: the copy's name and the original app's, for the keychain explanation.
        var copy: (name: String, of: String)? = nil
        var state = State.waiting
        let run: @MainActor (Store) async throws -> Void
    }

    /// True when the user had no universes: step 2 is then an editor of suggested drafts.
    let fresh: Bool
    @Published var drafts: [Draft] = []
    @Published var defaultID: UUID?
    /// App path → where it goes.
    @Published var placements: [String: Placement] = [:]
    @Published var tasks: [Task] = []
    @Published var building = false
    /// Installed apps for the Apps step, loaded in the background as soon as setup opens.
    @Published var appRows: [AppsStep.Row]?

    func loadApps(_ config: Config) {
        guard appRows == nil else { return }
        _Concurrency.Task {
            appRows = await _Concurrency.Task.detached { AppsStep.load(config) }.value
        }
    }

    init(config: Config) {
        fresh = config.universes.isEmpty
        guard fresh else { return }
        let browser = SetupModel.suggestedBrowser()
        let work = Draft(name: "Work", emoji: "💼", color: Universe.palette[0], browserPath: browser, separate: false)
        let personal = Draft(name: "Personal", emoji: "🏠", color: Universe.palette[2], browserPath: browser,
                             separate: Builder.supportsProfiles(URL(fileURLWithPath: browser)))
        drafts = [work, personal]
        defaultID = work.id
    }

    /// The user's browser before Multiverse, or a sensible installed one.
    static func suggestedBrowser() -> String {
        let browsers = installedBrowsers()
        if let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
           current.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL,
           browsers.contains(current.standardizedFileURL) {
            return current.path
        }
        for name in ["Google Chrome", "Arc", "Dia", "Brave Browser", "Microsoft Edge", "Safari"] {
            if let b = browsers.first(where: { appName($0.path) == name }) { return b.path }
        }
        return browsers.first?.path ?? "/Applications/Safari.app"
    }

    var universesValid: Bool {
        if !fresh { return true }
        return !drafts.isEmpty && drafts.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Two universes opening links in the very same browser profile defeats the point.
    var sharedBrowserWarning: String? {
        let plain = drafts.filter { !$0.separate }
        let dupes = Dictionary(grouping: plain, by: \.browserPath).filter { $0.value.count > 1 }
        guard let (path, ds) = dupes.first else { return nil }
        let names = ds.map(\.name).joined(separator: " and ")
        return "\(names) both open links in the same \(appName(path)), so their links won't be kept apart. Turn on “Separate” for one of them."
    }

    func addDraft() {
        let used = Set(drafts.map(\.color))
        drafts.append(Draft(name: "", emoji: "🪐", color: Universe.palette.first { !used.contains($0) } ?? Universe.palette[4],
                            browserPath: drafts.first?.browserPath ?? SetupModel.suggestedBrowser(), separate: true))
    }

    func saveUniverses(into store: Store) {
        guard fresh else { return }
        let existing = Set(store.config.universes.map(\.id))
        for d in drafts {
            let u = Universe(id: d.id, name: d.name.trimmingCharacters(in: .whitespaces), emoji: d.emoji,
                             browser: BrowserTarget(appPath: d.browserPath), color: d.color)
            if existing.contains(d.id), let i = store.config.universes.firstIndex(where: { $0.id == d.id }) {
                store.config.universes[i] = u
            } else {
                store.config.universes.append(u)
            }
        }
        let keep = Set(drafts.map(\.id))
        store.config.universes.removeAll { !keep.contains($0.id) }
        store.config.defaultUniverseID = defaultID ?? drafts.first?.id
    }

    /// Turns the choices into a list of things to build.
    func planBuild(with store: Store) {
        tasks = []
        let config = store.config
        // Separate browsers
        for d in drafts where d.separate && fresh {
            guard let u = config.universe(d.id) else { continue }
            let browser = URL(fileURLWithPath: d.browserPath)
            let name = uniqueName("\(u.name) \(appName(browser.path))", in: config)
            tasks.append(Task(title: "\(name), a separate \(appName(browser.path)) for \(u.name)", iconPath: browser.path,
                              copy: (name, appName(browser.path))) { store in
                try await SetupModel.make(name: name, from: browser, in: u.id, store: store, isBrowser: true)
            })
        }
        // Apps
        let defaultUniverse = config.defaultUniverse
        for (path, placement) in placements.sorted(by: { appName($0.key) < appName($1.key) }) {
            let app = URL(fileURLWithPath: path), name = appName(path)
            switch placement {
            case .universe(let id):
                guard let u = config.universe(id) else { continue }
                tasks.append(Task(title: "\(name) in \(u.emoji) \(u.name)", iconPath: path) { store in
                    store.config.apps.append(AppEntry(name: name, kind: .original, sourcePath: path, universeID: id))
                })
            case .every:
                guard let home = defaultUniverse else { continue }
                tasks.append(Task(title: "\(name) in \(home.emoji) \(home.name)", iconPath: path) { store in
                    store.config.apps.append(AppEntry(name: name, kind: .original, sourcePath: path, universeID: home.id))
                })
                for u in config.universes where u.id != home.id {
                    let copyName = uniqueName("\(u.name) \(name)", in: config)
                    tasks.append(Task(title: "\(copyName), a copy of \(name) for \(u.name)", iconPath: path,
                                      copy: Builder.supportsProfiles(app) ? (copyName, name) : nil) { store in
                        try await SetupModel.make(name: copyName, from: app, in: u.id, store: store, isBrowser: false)
                    })
                }
            }
        }
    }

    func runBuild(with store: Store) {
        guard !tasks.isEmpty, !building else { return }
        building = true
        _Concurrency.Task { @MainActor in
            for i in tasks.indices where tasks[i].state == .waiting {
                tasks[i].state = .working
                do {
                    try await tasks[i].run(store)
                    tasks[i].state = .done
                } catch {
                    tasks[i].state = .failed(error.localizedDescription)
                }
            }
            building = false
        }
    }

    /// A copy, or a separate profile when the app can't run as a copy (e.g. it uses iCloud).
    static func make(name: String, from app: URL, in universeID: UUID, store: Store, isBrowser: Bool) async throws {
        let asProfile = Builder.copyBlocker(app) != nil
        if asProfile && !Builder.supportsProfiles(app) {
            throw BuildError.tool(Builder.copyBlocker(app) ?? "This app can't be copied.")
        }
        let dataDir = asProfile ? Builder.defaultDataDir(for: name) : nil
        let entry = AppEntry(name: name, kind: asProfile ? .launcher : .clone, sourcePath: app.path,
                             universeID: universeID, dataDir: dataDir, icon: .tint)
        let tint = store.config.universe(universeID).flatMap { NSColor(hex: $0.color ?? "") }
        let built = try await _Concurrency.Task.detached { try Builder.build(entry, tint: tint) }.value
        store.config.apps.append(built)
        if isBrowser, let i = store.config.universes.firstIndex(where: { $0.id == universeID }) {
            store.config.universes[i].browser = asProfile
                ? BrowserTarget(appPath: app.path, dataDir: dataDir)
                : BrowserTarget(appPath: built.installedPath)
        }
    }

    private func uniqueName(_ base: String, in config: Config) -> String {
        var name = base, n = 2
        let planned = Set(tasks.map(\.title))
        while FileManager.default.fileExists(atPath: "/Applications/\(name).app")
                || config.apps.contains(where: { $0.name == name })
                || planned.contains(where: { $0.hasPrefix(name + ",") }) {
            name = "\(base) \(n)"; n += 1
        }
        return name
    }
}

// MARK: Step 2 – universes

private struct UniversesStep: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var setup: SetupModel

    var body: some View {
        if setup.fresh { editor } else { existing }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your universes").font(.largeTitle.bold())
                Text("A universe is one side of your life, with its own browser. We've suggested two; change anything you like.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach($setup.drafts) { $d in
                    DraftCard(draft: $d, canRemove: setup.drafts.count > 1) {
                        setup.drafts.removeAll { $0.id == d.id }
                        if setup.defaultID == d.id { setup.defaultID = setup.drafts.first?.id }
                    }
                }
                Button { setup.addDraft() } label: { Label("Add a universe", systemImage: "plus") }
                    .buttonStyle(.borderless)
                if let warning = setup.sharedBrowserWarning {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("Links from other apps open in")
                    Picker("", selection: Binding(get: { setup.defaultID ?? setup.drafts.first?.id ?? UUID() },
                                                  set: { setup.defaultID = $0 })) {
                        ForEach(setup.drafts) { d in Text("\(d.emoji) \(d.name.isEmpty ? "Untitled" : d.name)").tag(d.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .font(.callout)
            }
            .padding(.bottom, 12)
        }
    }

    private var existing: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your universes").font(.largeTitle.bold())
            Text("Check the browser each universe's links open in. Rename, recolour or add universes in Settings.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach($store.config.universes) { $u in
                    HStack {
                        Text("\(u.emoji) \(u.name)").font(.headline)
                        if store.config.defaultUniverse?.id == u.id {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.secondary)
                                .help("Links from apps that aren't in any universe open here")
                        }
                        Spacer()
                        BrowserPicker(universe: $u)
                    }
                    .padding(12)
                    if u.id != store.config.universes.last?.id { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        }
    }
}

private struct DraftCard: View {
    @Binding var draft: SetupModel.Draft
    let canRemove: Bool
    let remove: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        let browserName = appName(draft.browserPath)
        let canSeparate = Builder.supportsProfiles(URL(fileURLWithPath: draft.browserPath))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                EmojiButton(emoji: $draft.emoji)
                TextField("Name, e.g. Side project", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .focused($nameFocused)
                    .onAppear { if draft.name.isEmpty { DispatchQueue.main.async { nameFocused = true } } }
                Spacer()
                ColorSwatches(color: Binding(get: { draft.color }, set: { draft.color = $0 ?? draft.color }))
                if canRemove {
                    Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Remove")
                }
            }
            HStack(spacing: 8) {
                Text("Links open in").foregroundStyle(.secondary)
                Menu {
                    ForEach(installedBrowsers(), id: \.self) { b in
                        Button { draft.browserPath = b.path } label: {
                            Label { Text(appName(b.path)) } icon: { Image(nsImage: appIcon(b.path, size: 16)) }
                        }
                    }
                } label: {
                    HStack {
                        Image(nsImage: appIcon(draft.browserPath, size: 16))
                        Text(browserName)
                    }
                }
                .fixedSize()
                if canSeparate {
                    Toggle("Separate \(browserName) for \(draft.name.isEmpty ? "this universe" : draft.name)", isOn: $draft.separate)
                        .toggleStyle(.checkbox)
                        .help("Its own \(browserName), with its own logins, history and extensions")
                }
            }
            .font(.callout)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: NSColor(hex: draft.color) ?? .gray).opacity(0.5), lineWidth: 1))
    }
}

// MARK: Step 5 – permissions – apps

struct AppsStep: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var setup: SetupModel
    @State private var search = ""

    private var apps: [Row] { setup.appRows ?? [] }
    private var loading: Bool { setup.appRows == nil }

    /// Everything a row needs, worked out once off the main thread so typing in search stays instant.
    struct Row: Identifiable {
        let path: String
        let name: String
        let icon: NSImage
        let suggested: Bool
        let canCopy: Bool
        var id: String { path }
    }

    var body: some View {
        let shown = search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Your apps").font(.largeTitle.bold())
            Text("Links you open in an app go to its universe's browser. Pick “\(bothLabel)” for an app you use in each: you keep the original and get a separate copy with its own logins.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
            if loading {
                ProgressView("Looking at your apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                Text("No apps match “\(search)”.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    let suggested = shown.filter(\.suggested)
                    if !suggested.isEmpty {
                        Section("Suggested") { ForEach(suggested) { row($0) } }
                    }
                    let others = shown.filter { !$0.suggested }
                    if !others.isEmpty {
                        Section(suggested.isEmpty ? "Apps" : "Other apps") { ForEach(others) { row($0) } }
                    }
                }
                .listStyle(.inset)
            }
        }
        .task { setup.loadApps(store.config) }
    }

    nonisolated static func load(_ config: Config) -> [Row] {
        let browsers = Set(installedBrowsers().map(\.path))
        return installedApps(excluding: config)
            .filter { app in
                !browsers.contains(app.url.path) && !config.apps.contains { expand($0.sourcePath) == app.url.path }
            }
            .map { a in
                let profiles = Builder.supportsProfiles(a.url)
                let blocked = Builder.copyBlocker(a.url) != nil
                return Row(path: a.url.path, name: a.name, icon: appIcon(a.url.path, size: 22),
                           suggested: common.contains(a.name) || (!a.url.path.hasPrefix("/System/") && profiles),
                           canCopy: !blocked || profiles)
            }
    }

    private var bothLabel: String { store.config.universes.count > 2 ? "Every universe" : "Both" }

    /// Apps people commonly split between work and personal: chat, mail, notes, meetings, and
    /// Electron apps generally (they can get separate logins).
    nonisolated private static let common: Set<String> = [
        "Slack", "Discord", "Telegram", "WhatsApp", "Signal", "Messages", "Mail", "Messenger", "Microsoft Teams",
        "Zoom", "zoom.us", "Notion", "Notion Calendar", "Linear", "Figma", "Spotify", "Superhuman", "Spark",
        "Obsidian", "Craft", "Things3", "Todoist", "Cursor", "Visual Studio Code", "Microsoft Outlook",
        "Gmail", "Calendar", "Notes", "Granola", "Loom", "Asana", "ClickUp", "Trello", "Airtable", "1Password",
    ]

    private func row(_ a: Row) -> some View {
        HStack {
            Image(nsImage: a.icon)
            Text(a.name)
            Spacer()
            Picker("", selection: Binding(get: { setup.placements[a.path] }, set: { setup.placements[a.path] = $0 })) {
                Text("Not included").tag(Optional<SetupModel.Placement>.none)
                ForEach(store.config.universes) { u in
                    Text("\(u.emoji) \(u.name)").tag(Optional(SetupModel.Placement.universe(u.id)))
                }
                if store.config.universes.count > 1 && a.canCopy {
                    Text(bothLabel).tag(Optional(SetupModel.Placement.every))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

// MARK: Step 4 – build

private struct BuildStep: View {
    @EnvironmentObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(setup.building ? "Setting up…" : (setup.tasks.isEmpty ? "Nothing to build" : "All set")).font(.largeTitle.bold())
            if setup.tasks.isEmpty {
                Text("You can add apps, copies and separate browsers any time in Settings.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(setup.tasks) { t in
                            HStack(spacing: 10) {
                                Image(nsImage: appIcon(t.iconPath, size: 24))
                                Text(t.title)
                                Spacer()
                                switch t.state {
                                case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
                                case .working: ProgressView().controlSize(.small)
                                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            if case .failed(let reason) = t.state {
                                Text(reason).font(.caption).foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 46).padding(.bottom, 8)
                            }
                            if t.id != setup.tasks.last?.id { Divider() }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                }
                .frame(maxHeight: 250)
                if let example = setup.tasks.first(where: { $0.copy != nil }), let copy = example.copy {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("When you first open a copy", systemImage: "key").font(.headline)
                        Text("macOS asks whether it may use “… Safe Storage” from your keychain. That's where the app keeps the key for your saved logins. Enter your Mac password and click **Always Allow**.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        KeychainPromptPreview(app: copy.name, item: "\(copy.of) Safe Storage",
                                              icon: appIcon(example.iconPath, size: 28))
                    }
                }
            }
        }
    }
}

// MARK: Step 5 – permissions

private struct PermissionsStep: View {
    @EnvironmentObject var store: Store
    @State private var automation: [String: Automation.State] = [:]
    @State private var asking: String?

    var body: some View {
        let targets = Automation.targets(in: store.config)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Permissions").font(.largeTitle.bold())
                Text("Multiverse only asks for what it uses. Each of these is a one-time macOS prompt.")
                    .foregroundStyle(.secondary)

                PermissionRow(
                    symbol: "link", title: "Default browser",
                    why: "Multiverse receives every link you click and passes it to the right universe's browser. Nothing else changes about your browsers.",
                    status: store.routingOn ? .done : .needed,
                    actionTitle: "Turn on"
                ) { store.makeDefaultBrowser() }

                ForEach(targets, id: \.bundleID) { t in
                    PermissionRow(
                        symbol: "arrow.up.forward.app", title: "Send links to \(t.name) profiles",
                        why: "To open a link in a specific \(t.name) profile, Multiverse hands it to that window. macOS asks “Multiverse wants to control \(t.name)”: click Allow.",
                        status: status(automation[t.bundleID]),
                        actionTitle: automation[t.bundleID] == .notRunning ? "Open \(t.name)" : "Allow",
                        busy: asking == t.bundleID
                    ) { ask(t) }
                }

                PermissionRow(
                    symbol: "app.badge.checkmark", title: "Update app copies",
                    why: "When you update a copy, macOS may say Multiverse was prevented from modifying apps. Turn Multiverse on under Privacy & Security → App Management, then try again.",
                    status: .optional, actionTitle: "Open Settings"
                ) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("What your copies will ask", systemImage: "info.circle").font(.headline)
                    Text("macOS treats each copy as a new app, so the first time it opens it asks again for what the original had:")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• **“… Safe Storage” in your keychain**: enter your Mac password and click Always Allow, or it can't keep you signed in.")
                        Text("• **Folders, camera, microphone, screen recording**: allow what you'd allow the original.")
                    }
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            }
            .padding(.bottom, 16)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshRouting()
            refresh()
        }
    }

    private func status(_ s: Automation.State?) -> PermissionRow.Status {
        switch s {
        case .allowed: .done
        case .denied: .denied
        default: .needed
        }
    }

    private func refresh() {
        let targets = Automation.targets(in: store.config)
        Task.detached {
            var out: [String: Automation.State] = [:]
            for t in targets { out[t.bundleID] = Automation.state(for: t.bundleID, ask: false) }
            let result = out
            await MainActor.run { automation = result }
        }
    }

    private func ask(_ t: (name: String, bundleID: String, path: String)) {
        if automation[t.bundleID] == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            return
        }
        asking = t.bundleID
        Task.detached {
            // The target has to be running for macOS to ask.
            if Automation.state(for: t.bundleID, ask: false) == .notRunning {
                _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: expand(t.path)),
                                                                  configuration: NSWorkspace.OpenConfiguration())
                try? await Task.sleep(for: .seconds(2))
            }
            let state = Automation.state(for: t.bundleID, ask: true)
            await MainActor.run {
                automation[t.bundleID] = state
                asking = nil
                showOnboarding()  // come back to the front after the prompt
            }
        }
    }
}

private struct PermissionRow: View {
    enum Status { case done, needed, denied, optional }
    let symbol: String
    let title: String
    let why: String
    let status: Status
    var actionTitle = "Allow"
    var busy = false
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.headline)
                    pill
                }
                Text(why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView().controlSize(.small)
            } else if status != .done {
                Button(status == .denied ? "Open Settings" : actionTitle, action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }

    @ViewBuilder private var pill: some View {
        switch status {
        case .done: Label("Done", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
        case .needed: Text("Needed").font(.caption.bold()).foregroundStyle(.orange)
        case .denied: Text("Turned off").font(.caption.bold()).foregroundStyle(.red)
        case .optional: Text("Optional").font(.caption.bold()).foregroundStyle(.secondary)
        }
    }
}
