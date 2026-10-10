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
/// The step setup was on, so it can pick up there after macOS quits and reopens Multiverse
/// (it does that when you turn on a permission like App Management).
private let resumeStepKey = "onboardingResumeStep"

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
        let resume = UserDefaults.standard.integer(forKey: resumeStepKey)
        window.contentViewController = NSHostingController(rootView: OnboardingView(startAt: resume) { universe in
            UserDefaults.standard.set(true, forKey: onboardedKey)
            UserDefaults.standard.removeObject(forKey: resumeStepKey)
            onboardingWindow?.close()
            onboardingWindow = nil
            updateActivationPolicy()
            Store.shared.showUniverse = universe
            showSettings()
        }.environmentObject(Store.shared))
        window.setContentSize(NSSize(width: 640, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        trackForActivationPolicy(window)
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    onboardingWindow?.makeKeyAndOrderFront(nil)
    onboardingWindow?.orderFrontRegardless()
}

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    @StateObject private var setup: SetupModel
    /// Called with the universe to show in Settings afterwards.
    let finish: (UUID?) -> Void
    @State private var step: Step

    enum Step: Int, CaseIterable { case welcome, universes, build, permissions }

    init(startAt step: Int = 0, setup: SetupModel? = nil, finish: @escaping (UUID?) -> Void) {
        self.finish = finish
        _step = State(initialValue: Step(rawValue: step) ?? .welcome)
        _setup = StateObject(wrappedValue: setup ?? SetupModel(config: Store.shared.config))
    }

    /// The build step only appears when there's something to build.
    private var steps: [Step] { Step.allCases.filter { $0 != .build || !setup.tasks.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .universes: UniversesStep()
                case .build: BuildStep()
                case .permissions: PermissionsStep()
                }
            }
            .environmentObject(setup)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: step) { _, step in
                // Only resume past the universes step once they're saved; building restarts at permissions.
                let resume: Step = step == .build ? .permissions : step
                UserDefaults.standard.set(resume.rawValue, forKey: resumeStepKey)
            }

            Divider().padding(.horizontal, -Space.page).padding(.bottom, Space.group)
            HStack {
                HStack(spacing: 6) {
                    ForEach(steps, id: \.self) { s in
                        Circle().fill(s == step ? Brand.ink : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step == .universes { Button("Back") { step = .welcome }.buttonStyle(.brandQuiet) }
                if step != .permissions {
                    Button(step == .welcome ? "Get started" : "Continue") { advance() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.brand)
                        .disabled(!canContinue)
                } else {
                    Button(store.config.universes.count > 1 ? "Add apps" : "Done") {
                        // Land on a universe other than the main one: that's where apps get added.
                        finish(store.config.universes.first { $0.id != store.config.defaultUniverseID }?.id)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.brand)
                }
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.page + 4)
        .padding(.bottom, Space.group)
        .frame(width: 640, height: 600)
        .background(Brand.background)
        .tint(Brand.ink)
    }

    private var canContinue: Bool {
        switch step {
        case .universes: setup.universesValid
        case .build: !setup.building
        default: true
        }
    }

    private func advance() {
        switch step {
        case .welcome: step = .universes
        case .universes:
            setup.saveUniverses(into: store)
            setup.planBuild(with: store)
            if setup.tasks.isEmpty { step = .permissions } else { step = .build; setup.runBuild(with: store) }
        case .build: step = .permissions
        case .permissions: break
        }
    }
}

// MARK: Step 1

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.group) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: -6) {
                BrandTitle("Same apps.", size: 52)
                BrandTitle("Different universes.", size: 52)
            }
            VStack(alignment: .leading, spacing: Space.group) {
                Point(symbol: "circle.hexagongrid", title: "Universes",
                      text: "Group your apps into universes, like 💼 Work and 🏠 Personal.")
                Point(symbol: "square.on.square", title: "Separate copies",
                      text: "Use the same app in both, with separate logins and its own icon in the Dock.")
                Point(symbol: "link", title: "Links go to the right browser",
                      text: "A link you click in a work app opens in your work browser, and so on.")
            }
            Text("Setup takes a minute. macOS asks you to confirm a few things along the way; the next steps say what and why.")
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Point: View {
    let symbol: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Brand.ink).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
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
        /// An existing profile of that browser (e.g. a hand-made "Dia Personal"), if chosen.
        var profile: ExistingProfile? = nil
        /// Make a separate copy (or profile) of the browser for this universe.
        var separate: Bool
    }

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
    @Published var tasks: [Task] = []
    @Published var building = false

    init(config: Config) {
        fresh = config.universes.isEmpty
        guard fresh else { return }
        let browser = SetupModel.suggestedBrowser()
        let work = Draft(name: "Work", emoji: "💼", color: Universe.palette[0], browserPath: browser, separate: false)
        // Reuse a profile that already exists for this browser (e.g. a "Dia Personal"), else make a separate one.
        let profiles = existingProfiles().filter { expand($0.target.appPath) == expand(browser) }
        let existing = profiles.first { $0.name.localizedCaseInsensitiveContains("personal") } ?? profiles.first
        var personal = Draft(name: "Personal", emoji: "🏠", color: Universe.palette[2], browserPath: browser,
                             separate: existing == nil && Builder.supportsProfiles(URL(fileURLWithPath: browser)))
        personal.profile = existing
        drafts = [work, personal]
    }

    /// The user's own default browser: the current one, the one Multiverse replaced, or the browser
    /// they used most recently.
    static func suggestedBrowser() -> String {
        let browsers = installedBrowsers()
        if let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
           current.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL,
           browsers.contains(current.standardizedFileURL) {
            return current.path
        }
        if let previous = UserDefaults.standard.string(forKey: previousBrowserKey),
           browsers.contains(where: { $0.path == previous }) {
            return previous
        }
        // Otherwise the browser in use: running ones first, newest preferences file first (browsers
        // save it constantly while in use).
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL })
        let ranked = browsers.compactMap { b -> (URL, Bool, Date)? in
            guard let id = Bundle(url: b)?.bundleIdentifier, Bundle(url: b)?.infoDictionary?[Builder.ownerKey] == nil else { return nil }
            let prefs = NSHomeDirectory() + "/Library/Preferences/\(id).plist"
            let date = (try? FileManager.default.attributesOfItem(atPath: prefs))?[.modificationDate] as? Date ?? .distantPast
            return (b, running.contains(b), date)
        }
        if let best = ranked.max(by: { ($0.1 ? 1 : 0, $0.2) < ($1.1 ? 1 : 0, $1.2) }), best.2 != .distantPast {
            return best.0.path
        }
        for name in ["Google Chrome", "Arc", "Dia", "Brave Browser", "Microsoft Edge", "Safari"] {
            if let b = browsers.first(where: { appName($0.path) == name }) { return b.path }
        }
        return browsers.first?.path ?? "/Applications/Safari.app"
    }

    /// The main universe: every app starts here, and links from apps not moved elsewhere open here.
    var mainID: UUID? { fresh ? drafts.first?.id : nil }

    var universesValid: Bool {
        if !fresh { return true }
        return !drafts.isEmpty && drafts.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Two universes opening links in the very same browser profile defeats the point.
    var sharedBrowserWarning: String? {
        let plain = drafts.filter { !$0.separate }
        let dupes = Dictionary(grouping: plain, by: { $0.browserPath + "|" + ($0.profile?.target.dataDir ?? "") })
            .filter { $0.value.count > 1 }
        guard let (_, ds) = dupes.first, let first = ds.first else { return nil }
        let names = ds.map(\.name).joined(separator: " and ")
        let browser = first.profile?.name ?? appName(first.browserPath)
        return "\(names) both open links in the same \(browser), so their links won't be kept apart. Pick a different browser or a new one for one of them."
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
                             browser: d.profile?.target ?? BrowserTarget(appPath: d.browserPath), color: d.color)
            if existing.contains(d.id), let i = store.config.universes.firstIndex(where: { $0.id == d.id }) {
                store.config.universes[i] = u
            } else {
                store.config.universes.append(u)
            }
        }
        let keep = Set(drafts.map(\.id))
        store.config.universes.removeAll { !keep.contains($0.id) }
        store.config.defaultUniverseID = drafts.first?.id
    }

    /// Turns the choices into a list of things to build.
    func planBuild(with store: Store) {
        tasks = []
        let config = store.config
        // Separate browsers
        for d in drafts where d.separate && d.profile == nil && fresh {
            guard let u = config.universe(d.id) else { continue }
            let browser = URL(fileURLWithPath: d.browserPath)
            let name = uniqueName("\(u.name) \(appName(browser.path))", in: config)
            tasks.append(Task(title: "\(name), a separate \(appName(browser.path)) for \(u.name)", iconPath: browser.path,
                              copy: (name, appName(browser.path))) { store in
                try await SetupModel.make(name: name, from: browser, in: u.id, store: store, isBrowser: true)
            })
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
                             universeID: universeID, dataDir: dataDir, icon: .ivory)
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
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.label) {
                    Text("Your universes").font(Brand.heading(34)).tracking(-1)
                    Text("A universe is one side of your life, with its own browser.")
                        .foregroundStyle(Brand.muted)
                }

                VStack(alignment: .leading, spacing: Space.label) {
                    SectionLabel("Main universe")
                    Text("Every app starts here, and links from apps you don't move open in its browser. Name it after the side most of your apps belong to.")
                        .font(.callout).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
                    if let first = setup.drafts.indices.first {
                        DraftCard(draft: $setup.drafts[first], canRemove: false, isMain: true) {}
                            .padding(.top, Space.caption)
                    }
                }

                VStack(alignment: .leading, spacing: Space.label) {
                    SectionLabel("Other universes")
                    Text("After setup you'll add the apps that belong here, or a copy of one you also use in your main universe.")
                        .font(.callout).foregroundStyle(Brand.muted)
                    VStack(spacing: Space.item) {
                        ForEach($setup.drafts.dropFirst()) { $d in
                            DraftCard(draft: $d, canRemove: true, isMain: false) {
                                setup.drafts.removeAll { $0.id == d.id }
                            }
                        }
                    }
                    .padding(.top, Space.caption)
                    Button { setup.addDraft() } label: { Label("Add a universe", systemImage: "plus") }
                        .buttonStyle(.brandQuiet)
                        .padding(.top, Space.caption)
                    if let warning = setup.sharedBrowserWarning {
                        Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, Space.group)
        }
    }

    private var existing: some View {
        VStack(alignment: .leading, spacing: Space.group) {
            Text("Your universes").font(Brand.heading(34)).tracking(-1)
            Text("Check the browser each universe's links open in. Rename, recolour or add universes in Settings.")
                .foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach($store.config.universes) { $u in
                    HStack {
                        SectionLabel("\(u.emoji) \(u.name)")
                        if store.config.defaultUniverse?.id == u.id {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(Brand.muted)
                                .help("Main universe: every app not in another universe belongs here")
                        }
                        Spacer()
                        BrowserPicker(universe: $u)
                    }
                    .padding(.horizontal, Space.rowH).padding(.vertical, Space.rowV)
                    if u.id != store.config.universes.last?.id { Divider() }
                }
            }
            .brandCard(radius: Space.radius)
        }
    }
}

private struct DraftCard: View {
    @Binding var draft: SetupModel.Draft
    let canRemove: Bool
    var isMain = false
    let remove: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        let browserName = appName(draft.browserPath)
        let universeName = draft.name.isEmpty ? "this universe" : draft.name
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                EmojiButton(emoji: $draft.emoji)
                TextField(isMain ? "Name, e.g. Work" : "Name, e.g. Personal", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(Brand.heading(24)).tracking(-0.6)
                    .focused($nameFocused)
                    .onAppear { if draft.name.isEmpty || isMain { DispatchQueue.main.async { nameFocused = true } } }
                Spacer()
                ColorSwatches(color: Binding(get: { draft.color }, set: { draft.color = $0 ?? draft.color }))
                if canRemove {
                    Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.muted) }
                        .buttonStyle(.plain).help("Remove")
                }
            }
            HStack(spacing: 8) {
                Text("Links open in").foregroundStyle(Brand.muted)
                Menu {
                    Section("Your browsers") {
                        ForEach(installedBrowsers(), id: \.self) { b in
                            Button { draft.browserPath = b.path; draft.profile = nil; draft.separate = false } label: {
                                Label { Text(appName(b.path)) } icon: { Image(nsImage: appIcon(b.path, size: 16)) }
                            }
                        }
                    }
                    let profiles = existingProfiles()
                    if !profiles.isEmpty {
                        Section("Profiles already on this Mac") {
                            ForEach(profiles, id: \.self) { p in
                                Button { draft.browserPath = p.target.appPath; draft.profile = p; draft.separate = false } label: {
                                    Label { Text(p.name) } icon: { Image(nsImage: appIcon(p.launcherPath, size: 16)) }
                                }
                            }
                        }
                    }
                    Section("Create a new browser") {
                        ForEach(installedBrowsers().filter { Builder.supportsProfiles($0) }, id: \.self) { b in
                            Button { draft.browserPath = b.path; draft.profile = nil; draft.separate = true } label: {
                                Label { Text("New \(appName(b.path)) just for \(universeName)") } icon: { Image(nsImage: appIcon(b.path, size: 16)) }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(nsImage: appIcon(draft.profile?.launcherPath ?? draft.browserPath, size: 16))
                        Text(draft.profile?.name ?? (draft.separate ? "New \(browserName) just for \(universeName)" : browserName))
                    }
                }
                .fixedSize()
            }
            .font(.callout)
            if draft.separate {
                Text(Builder.copyBlocker(URL(fileURLWithPath: draft.browserPath)) == nil
                     ? "When you continue, Multiverse creates a separate \(browserName) app for \(universeName), with its own Dock icon. It starts empty, with no logins, history or extensions, so \(universeName) stays apart from your other \(browserName)."
                     : "When you continue, Multiverse creates a separate \(browserName) profile for \(universeName), opened from its own app in Applications. It starts empty, with no logins, history or extensions. Its windows share \(browserName)'s Dock icon, because \(browserName) can't run as a copy.")
                    .font(.caption).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.card)
        .brandCard(radius: Space.radius)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: NSColor(hex: draft.color) ?? .gray).opacity(0.5), lineWidth: 1))
    }
}

// MARK: Step 3 – build

private struct BuildStep: View {
    @EnvironmentObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.group) {
            Text(setup.building ? "Setting up…" : (setup.tasks.isEmpty ? "Nothing to build" : "All set")).font(Brand.heading(34)).tracking(-1)
            if setup.tasks.isEmpty {
                Text("Nothing to build.").foregroundStyle(Brand.muted)
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
                                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.olive)
                                case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, Space.rowV).padding(.horizontal, Space.rowH)
                            if case .failed(let reason) = t.state {
                                Text(reason).font(.caption).foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 46).padding(.bottom, 8)
                            }
                            if t.id != setup.tasks.last?.id { Divider() }
                        }
                    }
                    .brandCard(radius: Space.radius)
                }
                .frame(maxHeight: 250)
                if let example = setup.tasks.first(where: { $0.copy != nil }), let copy = example.copy {
                    VStack(alignment: .leading, spacing: Space.label) {
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

// MARK: Step 4 – permissions

private struct PermissionsStep: View {
    @EnvironmentObject var store: Store
    @State private var automation: [String: Automation.State] = [:]
    @State private var asking: String?

    var body: some View {
        let targets = Automation.targets(in: store.config)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.group) {
                Text("Permissions").font(Brand.heading(34)).tracking(-1)
                Text("Multiverse only asks for what it uses. Each of these is a one-time macOS prompt.")
                    .foregroundStyle(Brand.muted)

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

                VStack(alignment: .leading, spacing: 10) {
                    Label("What your copies will ask", systemImage: "info.circle").font(.headline)
                    Text("macOS treats each copy as a new app, so the first time a copy opens you'll see prompts like these:")
                        .font(.callout).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 12) {
                        PromptSketch(
                            symbol: "lock.fill", tint: .yellow,
                            text: "“Work Slack” wants to use “Slack Safe Storage” in your keychain.",
                            password: true, buttons: ["Always Allow", "Deny", "Allow"], highlight: "Always Allow",
                            caption: "Enter your Mac password, then **Always Allow**. It's where the app keeps your logins.")
                        PromptSketch(
                            symbol: "folder.fill", tint: .blue,
                            text: "“Work Slack” would like to access files in your Documents folder.",
                            password: false, buttons: ["Don't Allow", "Allow"], highlight: "Allow",
                            caption: "Folders, camera, microphone, screen: allow what you'd allow the original.")
                    }
                }
                .padding(Space.card)
                .brandCard(radius: Space.radius)
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

/// A small drawing of a macOS prompt, with the button to press highlighted.
private struct PromptSketch: View {
    let symbol: String
    let tint: Color
    let text: String
    let password: Bool
    let buttons: [String]
    let highlight: String
    let caption: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol).font(.title2).foregroundStyle(tint).frame(width: 26)
                    Text(text).font(.caption.bold()).fixedSize(horizontal: false, vertical: true)
                }
                if password {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 16)
                        .overlay(Text("••••••••").font(.caption2).padding(.leading, 6), alignment: .leading)
                }
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    ForEach(buttons, id: \.self) { b in
                        Text(b).font(.caption2.weight(b == highlight ? .bold : .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(b == highlight ? Brand.ink.opacity(0.2) : Color.secondary.opacity(0.15)))
                            .overlay(Capsule().stroke(b == highlight ? Brand.ink : .clear, lineWidth: 2))
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            Text(caption).font(.caption).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            Image(systemName: symbol).font(.title3).foregroundStyle(Brand.ink).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.headline)
                    pill
                }
                Text(why).font(.callout).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView().controlSize(.small)
            } else if status != .done {
                Button(status == .denied ? "Open Settings" : actionTitle, action: action).buttonStyle(.brandQuiet)
            }
        }
        .padding(Space.card)
        .brandCard(radius: Space.radius)
    }

    @ViewBuilder private var pill: some View {
        switch status {
        case .done: Label("Done", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(Brand.olive)
        case .needed: Text("Needed").font(.caption.bold()).foregroundStyle(.orange)
        case .denied: Text("Turned off").font(.caption.bold()).foregroundStyle(.red)
        case .optional: Text("Optional").font(.caption.bold()).foregroundStyle(Brand.muted)
        }
    }
}
