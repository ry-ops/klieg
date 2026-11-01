import SwiftUI
import AppKit
import KliegKit

@main
struct KliegApp: App {
    @ViewState private var app = AppState()

    init() {
        // Behave like a normal app even when launched as a bare executable (swift run).
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate() }
    }

    var body: some Scene {
        WindowGroup("Klieg", id: "main") {
            ShellView()
                .environment(app)
                .frame(minWidth: 1000, minHeight: 600)
                .preferredColorScheme(.dark)
                .sheet(item: Bindable(app).panel) { p in PanelSheet(panel: p).environment(app) }
                .onAppear { app.monitor.start() }
                .sheet(item: Bindable(app).sheet) { sheet in
                    switch sheet {
                    case .read(let a): ReadSheet(agent: a).environment(app)
                    case .prompt(let a): PromptSheet(agent: a).environment(app)
                    case .answer(let a): AnswerSheet(agent: a).environment(app)
                    }
                }
                .confirmationDialog(app.confirm?.title ?? "", isPresented: Binding(get: { app.confirm != nil }, set: { if !$0 { app.confirm = nil } }),
                                    titleVisibility: .visible, presenting: app.confirm) { c in
                    Button(c.title.replacingOccurrences(of: "?", with: ""), role: .destructive) { app.perform(c) }
                    Button("Cancel", role: .cancel) {}
                } message: { c in Text(c.message) }
                .alert("Klieg couldn't do that", isPresented: Binding(get: { app.actionError != nil }, set: { if !$0 { app.actionError = nil } })) {
                    Button("OK") {}
                } message: { Text(app.actionError ?? "") }
        }
        MenuBarExtra {
            MenuBarContent().environment(app)
        } label: {
            let n = app.monitor.snapshot.needingPerson.count
            Label(n == 0 ? "Klieg" : "\(n)", systemImage: n == 0 ? "light.beacon.min" : "light.beacon.max.fill")
        }
        .commands {
            CommandMenu("Klieg") {
                Button("Commands…") { app.paletteOpen.toggle() }.keyboardShortcut("k")
                Button("New Shell Tab") { app.newShell() }.keyboardShortcut("t")
                Button("Refresh") { Task { await app.monitor.refresh() } }.keyboardShortcut("r")
                Divider()
                Button("Previous Space") { app.moveSpace(-1) }.keyboardShortcut(.upArrow, modifiers: [.command])
                Button("Next Space") { app.moveSpace(1) }.keyboardShortcut(.downArrow, modifiers: [.command])
                Divider()
                ForEach(1..<10) { i in
                    Button("Tab \(i)") { app.selectTab(number: i) }.keyboardShortcut(KeyEquivalent(Character("\(i)")))
                }
                Divider()
                Button("Timeline") { app.panel = .timeline }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Pull Requests") { app.panel = .pullRequests }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Settings…") { app.panel = .settings }.keyboardShortcut(",")
            }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case board = "Board", needsYou = "Needs You", timeline = "Timeline", pullRequests = "Pull Requests", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .board: return "square.grid.2x2"
        case .timeline: return "clock.arrow.circlepath"
        case .needsYou: return "hand.raised"
        case .pullRequests: return "arrow.triangle.pull"
        case .settings: return "gearshape"
        }
    }
}

@Observable @MainActor
final class AppState {
    /// `--section <name>` (e.g. --section timeline) opens on that section; handy for screenshots.
    var section: Section = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--section"), i + 1 < args.count,
           let s = Section.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "-") == args[i + 1].lowercased() }) {
            return s
        }
        return .board
    }()
    let monitor = Monitor(config: KliegConfig.load())
    let terminal = TerminalStore()
    var sheet: AgentSheet?
    var confirm: Confirmation?
    var panel: Panel?
    var paletteOpen = false
    var selectedSpaceID: String?
    var selectedTab: TabID = .overview
    var shells: [TerminalTab] = []
    private var live: [String: TerminalTab] = [:]

    var spaces: [SpaceItem] { SpaceItem.group(monitor.snapshot, branches: monitor.branches, config: monitor.config) }
    var currentSpace: SpaceItem? {
        let all = spaces
        return all.first { $0.id == selectedSpaceID } ?? all.first
    }
    func agent(_ id: String) -> Agent? { monitor.snapshot.agents.first { $0.id == id } }

    func select(space id: String) {
        guard id != currentSpace?.id else { return }
        selectedSpaceID = id
        selectedTab = .overview
    }
    func moveSpace(_ delta: Int) {
        let all = spaces
        guard !all.isEmpty else { return }
        let i = all.firstIndex { $0.id == currentSpace?.id } ?? 0
        select(space: all[(i + delta + all.count) % all.count].id)
    }
    func selectTab(number: Int) {
        var tabs: [TabID] = [.overview] + (currentSpace?.agents.map { TabID.agent($0.id) } ?? [])
        tabs += shells.map { TabID.shell($0.id) }
        if number - 1 < tabs.count { selectedTab = tabs[number - 1] }
    }
    /// `--agent <name>` opens that agent's tab once it first appears (handy for screenshots and demos).
    private var launchFocusDone = false
    func applyLaunchFocus() {
        guard !launchFocusDone else { return }
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--agent"), i + 1 < args.count else { launchFocusDone = true; return }
        if let a = monitor.snapshot.agents.first(where: { $0.name == args[i + 1] || short($0.name) == args[i + 1] }) {
            focus(a); launchFocusDone = true
        }
    }

    func focus(_ a: Agent) {
        selectedSpaceID = spaces.first { $0.agents.contains { $0.id == a.id } }?.id
        selectedTab = .agent(a.id)
    }

    /// The agent's live terminal, started on first use and kept while the app runs.
    func liveTerminal(for a: Agent) -> TerminalTab? {
        if let t = live[a.id] { return t }
        guard let cmd = a.attachCommand, !cmd.isEmpty else { return nil }
        let id = a.id
        let t = TerminalTab(directory: nil, fontSize: 13, command: cmd, title: short(a.name)) { [weak self] _ in self?.live[id] = nil }
        t.pinnedTitle = true
        live[a.id] = t
        return t
    }

    func newShell() {
        let t = TerminalTab(directory: nil, fontSize: 13) { [weak self] id in self?.closeShell(id) }
        shells.append(t)
        selectedTab = .shell(t.id)
    }
    func closeShell(_ id: UUID) {
        guard let i = shells.firstIndex(where: { $0.id == id }) else { return }
        shells[i].terminate()
        shells.remove(at: i)
        if selectedTab == .shell(id) { selectedTab = .overview }
    }
    var actionError: String?

    func perform(_ c: Confirmation) {
        let rig = monitor.openrig, gh = monitor.github
        Task {
            let err: String?
            switch c {
            case .stopSeat(let a): err = await monitor.act { _ = try rig.stop(session: a.name) }
            case .merge(let p): err = await monitor.act { _ = try gh.merge(repo: p.repo, number: p.number) }
            }
            actionError = err
        }
    }

    /// Opens an agent's live session in a new terminal tab.
    func openTerminal(for agent: Agent) {
        guard let cmd = agent.attachCommand, !cmd.isEmpty else { return }
        terminal.newTab(running: cmd, title: agent.name)
    }
}

struct MenuBarContent: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let s = app.monitor.snapshot
        let waiting = s.needingPerson
        Text(waiting.isEmpty ? "Nobody needs you" : "\(waiting.count) need\(waiting.count == 1 ? "s" : "") you")
        ForEach(waiting) { a in
            Button("\(a.name): \(reasonText(a))") { app.focus(a); openWindow(id: "main"); NSApp.activate() }
        }
        Divider()
        Text("\(s.agents.filter { $0.status == .working }.count) working · \(s.agents.count) agents")
        Button("Open Klieg") { openWindow(id: "main"); NSApp.activate() }
        Button("Refresh") { Task { await app.monitor.refresh() } }
        Divider()
        Button("Quit Klieg") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(Section.allCases, selection: $app.section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if !(app.terminal.visible && app.terminal.maximized) {
                        SectionView(section: app.section)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if app.terminal.visible {
                        @Bindable var term = app.terminal
                        PanelResizeHandle(height: $term.height, maxHeight: geo.size.height - 80)
                        TerminalPanel()
                            .frame(height: app.terminal.maximized ? nil : app.terminal.height)
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { app.terminal.toggle() } label: { Label("Terminal", systemImage: "terminal") }
                        .help("Show or hide the terminal (⌃`)")
                }
            }
        }
    }
}

struct SectionView: View {
    let section: Section
    var body: some View {
        switch section {
        case .board: BoardView()
        case .needsYou: NeedsYouView()
        case .timeline: TimelineView()
        case .pullRequests: PullRequestsView()
        case .settings: SettingsView()
        }
    }
}

/// Placeholder content until its milestone fills the section in (see ROADMAP.md).
struct PlaceholderView: View {
    let section: Section
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: section.icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(section.rawValue).font(.title2.bold())
            Text(blurb).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .padding()
    }
    var blurb: String {
        switch section {
        case .board: return "Every herdr agent and OpenRig seat, with its state."
        case .timeline: return "Claims, handoffs, verdicts, PRs and CI, in order. (M3)"
        case .needsYou: return "Agents waiting on you: approvals, questions, credit prompts. (M3)"
        case .pullRequests: return "PRs the agents opened, with CI and signing status. (M3)"
        case .settings: return "Machines, rigs and repos Klieg watches. (M3)"
        }
    }
}
