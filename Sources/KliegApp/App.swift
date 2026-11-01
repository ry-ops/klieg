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
                .onAppear { app.monitor.start() }
        }
        // No title bar: the window is all terminal, like herdr. The traffic lights float over the sidebar.
        .windowStyle(.hiddenTitleBar)
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
                Button("Timeline") { app.open(.timeline) }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Pull Requests") { app.open(.pullRequests) }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Settings…") { app.open(.settings) }.keyboardShortcut(",")
            }
        }
    }
}

@Observable @MainActor
final class AppState {
    let monitor = Monitor(config: KliegConfig.load())
    var sheet: AgentSheet?
    var confirm: Confirmation?
    var actionError: String?
    var paletteOpen = false
    var selectedSpaceID: String?
    var selectedTab: TabID = .overview
    var shells: [TerminalTab] = []
    /// Timeline, pull requests and settings, open as tabs.
    var openPanels: [Panel] = []
    private var live: [String: TerminalTab] = [:]

    init() {
        // `--section timeline|pull-requests|settings` opens that panel at launch (handy for screenshots).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--section"), i + 1 < args.count {
            let asked = args[i + 1].lowercased().replacingOccurrences(of: "-", with: "")
            if let p = Panel.allCases.first(where: { $0.rawValue.lowercased() == asked }) { open(p) }
        }
    }

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
    /// Tabs are numbered left to right: all, the space's agents, shells, then panels.
    func selectTab(number: Int) {
        var tabs: [TabID] = [.overview] + (currentSpace?.agents.map { TabID.agent($0.id) } ?? [])
        tabs += shells.map { TabID.shell($0.id) }
        tabs += openPanels.map { TabID.panel($0) }
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

    func open(_ p: Panel) {
        if !openPanels.contains(p) { openPanels.append(p) }
        selectedTab = .panel(p)
    }
    func closePanel(_ p: Panel) {
        openPanels.removeAll { $0 == p }
        if selectedTab == .panel(p) { selectedTab = .overview }
    }

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
