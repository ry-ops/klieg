import SwiftUI
import AppKit
import KliegKit

// The herdr-style window: spaces and agents on the left, tabs and live panes on the right,
// a key-hint bar along the bottom.

/// A herdr workspace or an OpenRig rig, with its agents.
struct SpaceItem: Identifiable, Hashable {
    let id: String
    let source: Source
    let name: String
    let subtitle: String
    let status: AgentStatus
    let agents: [Agent]

    /// Spaces from the shared core (KliegKit.Spaces), with each space's agents in urgency order.
    static func group(_ snap: Snapshot, branches: [String: String], config: KliegConfig) -> [SpaceItem] {
        Spaces.group(snap, branches: branches, openrigHost: config.openrigHost).map { sp in
            SpaceItem(id: sp.id, source: sp.source, name: sp.name, subtitle: sp.subtitle, status: sp.status,
                      agents: Spaces.agentsOrdered(in: sp, snapshot: snap))
        }
    }
}

enum TabID: Hashable {
    case overview
    case agent(String)
    case shell(UUID)
    case panel(Panel)
}

struct ShellView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Sidebar().frame(width: 290)
                Rectangle().fill(Theme.border).frame(width: 1)
                MainArea()
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            KeyHintBar()
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .overlay { Overlays() }
        .overlay { if app.paletteOpen { CommandPalette() } }
        .onChange(of: app.monitor.lastRefresh) { _, _ in app.applyLaunchFocus() }
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let spaces = app.spaces
        VStack(spacing: 0) {
            // The window has no title bar, so the traffic lights float here.
            header("spaces").padding(.top, 22)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(spaces) { s in
                        Button { app.select(space: s.id) } label: {
                            row(dot: s.status, title: s.name, subtitle: s.subtitle,
                                subColor: Theme.accent.opacity(0.85), selected: s.id == app.currentSpace?.id)
                        }
                        .buttonStyle(.plain)
                    }
                    if spaces.isEmpty {
                        Text("no agents yet").font(Theme.mono(12)).foregroundStyle(Theme.faint).padding()
                    }
                }
                .padding(.horizontal, 8)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            header("agents")
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(app.currentSpace?.agents ?? []) { a in
                        Button { app.selectedTab = .agent(a.id) } label: {
                            row(dot: a.status, title: short(a.name), subtitle: "\(a.status.rawValue) · \(a.kind)",
                                subColor: a.status == .idle || a.status == .stopped ? Theme.dim : Theme.color(a.status),
                                selected: app.selectedTab == .agent(a.id))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { AgentMenu(agent: a) }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: .infinity)
        }
        .background(Theme.panel)
    }

    func header(_ t: String) -> some View {
        HStack { Text(t).font(Theme.mono(14)).foregroundStyle(Theme.dim); Spacer() }
            .padding(.horizontal, 20).padding(.vertical, 12)
    }

    func row(dot: AgentStatus, title: String, subtitle: String, subColor: Color, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StatusDot(status: dot).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.mono(15, .semibold)).lineLimit(1)
                Text(subtitle).font(Theme.mono(12.5)).foregroundStyle(subColor).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(selected ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}

func short(_ name: String) -> String { name.split(separator: "@").first.map(String.init) ?? name }

struct AgentMenu: View {
    @Environment(AppState.self) private var app
    let agent: Agent
    var body: some View {
        Button("Open live terminal") { app.selectedTab = .agent(agent.id) }
        Button("Read screen…") { app.sheet = .read(agent) }
        if agent.status == .blocked && agent.source == .openrig {
            Button("Answer prompt…") { app.sheet = .answer(agent) }.disabled(app.monitor.config.readOnly || agent.attentionReason == "billing")
        } else {
            Button("Send prompt…") { app.sheet = .prompt(agent) }.disabled(app.monitor.config.readOnly || agent.status == .stopped)
        }
        if agent.source == .openrig && agent.status != .stopped {
            Divider()
            Button("Stop seat…", role: .destructive) { app.confirm = .stopSeat(agent) }.disabled(app.monitor.config.readOnly)
        }
    }
}

// MARK: Tabs and panes

struct MainArea: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            Group {
                switch app.selectedTab {
                case .overview:
                    if let s = app.currentSpace { SeatColumns(space: s) } else { EmptyPane() }
                case .agent(let id):
                    if let a = app.agent(id) { AgentPane(agent: a) } else { EmptyPane() }
                case .shell(let id):
                    if let t = app.shells.first(where: { $0.id == id }) {
                        TitledFrame(title: t.label, color: Theme.dim) { TerminalHost(tab: t).id(t.id) }.padding(10)
                    } else { EmptyPane() }
                case .panel(let p):
                    TitledFrame(title: p.title, color: Theme.dim) { PanelPane(panel: p) }.padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if case .agent(let id) = app.selectedTab, let a = app.agent(id) { PaneStatusLine(agent: a) }
        }
    }
}

struct TabBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            if let s = app.currentSpace {
                tab(s.source == .openrig ? "seats" : "all", .overview)
                ForEach(s.agents) { a in tab(short(a.name), .agent(a.id), dot: a.status) }
            }
            ForEach(app.shells) { t in tab(t.label, .shell(t.id)) { app.closeShell(t.id) } }
            ForEach(app.openPanels) { p in tab(p.title, .panel(p)) { app.closePanel(p) } }
            Button { app.newShell() } label: {
                Text("+").font(Theme.mono(15)).foregroundStyle(Theme.dim).frame(width: 46, height: 36)
            }
            .buttonStyle(.plain).help("New shell tab (⌘T)")
            Spacer()
        }
        .frame(height: 36)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    func tab(_ title: String, _ id: TabID, dot: AgentStatus? = nil, close: (() -> Void)? = nil) -> some View {
        let on = app.selectedTab == id
        return HStack(spacing: 7) {
            if let dot, !on { StatusDot(status: dot, size: 7) }
            Text(title).font(Theme.mono(14, on ? .semibold : .regular)).lineLimit(1)
            if let close {
                Button(action: close) { Text("×").font(Theme.mono(13)) }
                    .buttonStyle(.plain).foregroundStyle(on ? Theme.accentInk : Theme.dim)
            }
        }
        .padding(.horizontal, 22).frame(height: 36)
        .foregroundStyle(on ? Theme.accentInk : Theme.dim)
        .background(on ? Theme.accent : .clear)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { app.selectedTab = id }
    }
}

struct EmptyPane: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("no agent selected").font(Theme.mono(14)).foregroundStyle(Theme.dim)
            Text("pick a space and an agent on the left · ⌘K for commands").font(Theme.mono(12)).foregroundStyle(Theme.faint)
        }
    }
}

/// One agent's live, interactive terminal inside a herdr-style titled frame.
struct AgentPane: View {
    @Environment(AppState.self) private var app
    let agent: Agent

    var body: some View {
        VStack(spacing: 8) {
            if agent.status.needsPerson { NeedsYouStrip(agent: agent) }
            TitledFrame(title: agent.kind, color: agent.status.needsPerson ? Theme.color(.blocked) : Theme.accent) {
                if let t = app.liveTerminal(for: agent) {
                    TerminalHost(tab: t).id(t.id)
                } else {
                    Text("this agent has no attach command").font(Theme.mono(13)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(10)
    }
}

struct NeedsYouStrip: View {
    @Environment(AppState.self) private var app
    let agent: Agent
    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: .blocked)
            Text("needs you · \(reasonText(agent))").font(Theme.mono(13, .semibold)).foregroundStyle(Theme.color(.blocked))
            Spacer()
            if agent.source == .openrig && agent.attentionReason != "billing" {
                Button("answer…") { app.sheet = .answer(agent) }.disabled(app.monitor.config.readOnly)
            }
        }
        .font(Theme.mono(12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.color(.blocked).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: Seat columns (OpenRig style)

struct SeatColumns: View {
    let space: SpaceItem
    var body: some View {
        GeometryReader { geo in
            let n = max(space.agents.count, 1)
            let w = max(300, (geo.size.width - 20 - CGFloat(min(n, 3) - 1) * 12) / CGFloat(min(n, 3)))
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(space.agents) { a in FeedColumn(agent: a).frame(width: w) }
                }
                .padding(10)
                .frame(minHeight: geo.size.height)
            }
        }
    }
}

/// One seat as a column: tool header, a read-only feed of its screen, a prompt line, model · folder footer.
struct FeedColumn: View {
    @Environment(AppState.self) private var app
    let agent: Agent
    @ViewState private var feed = ScreenPoller()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(toolName).font(Theme.mono(14, .bold))
                Spacer()
                Text(agent.name).font(Theme.mono(13)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .padding(.horizontal, 16).frame(height: 44)
            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(feed.text.isEmpty ? (feed.error.map { "can't read this screen: \($0)" } ?? "reading…") : feed.text)
                        .font(Theme.mono(11)).foregroundStyle(Theme.text.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: feed.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            if agent.status.needsPerson {
                Text("● needs you · \(reasonText(agent))").font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.color(.blocked)).padding(.horizontal, 16).padding(.vertical, 6)
            }
            Button { app.selectedTab = .agent(agent.id) } label: {
                HStack { Text("›").foregroundStyle(Theme.dim); Text("open live terminal").foregroundStyle(Theme.faint); Spacer() }
                    .font(Theme.mono(14)).padding(.horizontal, 16).frame(height: 44)
                    .background(Theme.raised)
            }
            .buttonStyle(.plain)
            HStack(spacing: 0) {
                Text(agent.model ?? agent.kind).foregroundStyle(Color(hex: 0xc3e88d))
                Text(" · ").foregroundStyle(Theme.faint)
                Text((agent.cwd ?? "").replacingOccurrences(of: "/home/ubuntu", with: "~")).foregroundStyle(Color(hex: 0xc3e88d)).lineLimit(1)
                Spacer()
                StatusDot(status: agent.status, size: 8)
                Text(" \(agent.status.rawValue)").foregroundStyle(Theme.color(agent.status))
            }
            .font(Theme.mono(12)).padding(.horizontal, 16).frame(height: 40)
        }
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(agent.status.needsPerson ? Theme.color(.blocked) : Theme.border,
                                                          lineWidth: agent.status.needsPerson ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { feed.start(agent: agent, monitor: app.monitor) }
        .onDisappear { feed.stop() }
        .contextMenu { AgentMenu(agent: agent) }
    }

    var toolName: String {
        switch agent.kind {
        case "claude": return "Claude Code"
        case "codex": return "Codex CLI"
        default: return agent.kind
        }
    }
}

/// Shows an agent's screen through the shared ScreenFeed while its column is on screen.
@Observable @MainActor
final class ScreenPoller {
    var text = ""
    var error: String?
    private var feed: ScreenFeed?

    func start(agent: Agent, monitor: Monitor) {
        stop()
        feed = try? ScreenFeed(agent: agent, herdr: monitor.herdr, openrig: monitor.openrig, interval: 2, lines: 160,
                               onError: { [weak self] e in let msg = "\(e)"; Task { @MainActor in self?.error = msg } },
                               handler: { [weak self] t in Task { @MainActor in self?.text = t; self?.error = nil } })
        feed?.start()
    }

    func stop() { feed?.stop(); feed = nil }
}

// MARK: Key hints

struct KeyHintBar: View {
    @Environment(AppState.self) private var app
    var body: some View {
        let waiting = app.monitor.snapshot.needingPerson.count
        HStack(spacing: 16) {
            hint("⌘↑↓", "space"); hint("⌘1-9", "tab"); hint("⌘T", "shell"); hint("⌘K", "commands"); hint("⌘R", "refresh")
            hint("⌘⇧L", "timeline"); hint("⌘⇧P", "prs"); hint("⌘,", "settings")
            Spacer()
            if !app.monitor.snapshot.errors.isEmpty {
                Text("! " + app.monitor.snapshot.errors.keys.sorted().joined(separator: ", ")).foregroundStyle(Theme.color(.blocked))
                    .help(app.monitor.snapshot.errors.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
            }
            if waiting > 0 {
                Text("● \(waiting) need\(waiting == 1 ? "s" : "") you").foregroundStyle(Theme.color(.blocked))
            }
            if app.monitor.config.readOnly { Text("read-only").foregroundStyle(Theme.dim) }
            Text(app.monitor.lastRefresh.map { $0.formatted(date: .omitted, time: .standard) } ?? "connecting…").foregroundStyle(Theme.faint)
        }
        .font(Theme.mono(12))
        .padding(.horizontal, 16).frame(height: 30)
        .background(Theme.panel)
    }
    func hint(_ k: String, _ what: String) -> some View {
        HStack(spacing: 5) { Text(k).foregroundStyle(Theme.accent); Text(what).foregroundStyle(Theme.dim) }
    }
}

// MARK: Command palette

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let run: () -> Void
}

struct CommandPalette: View {
    @Environment(AppState.self) private var app
    @ViewState private var query = ""
    @ViewState private var index = 0

    var commands: [PaletteCommand] {
        var c: [PaletteCommand] = [
            .init(title: "timeline", detail: "claims, handoffs, PRs and CI, newest first") { app.open(.timeline) },
            .init(title: "pull requests", detail: "the agents' PRs, with CI and signing") { app.open(.pullRequests) },
            .init(title: "settings", detail: "machines, rigs, repos, read-only") { app.open(.settings) },
            .init(title: "new shell", detail: "a local shell tab") { app.newShell() },
            .init(title: "refresh", detail: "read every source now") { Task { await app.monitor.refresh() } },
        ]
        for a in app.monitor.snapshot.needingPerson {
            c.insert(.init(title: "go to \(short(a.name))", detail: "needs you · \(reasonText(a))") { app.focus(a) }, at: 0)
        }
        for a in app.monitor.snapshot.agents where !a.status.needsPerson {
            c.append(.init(title: "open \(short(a.name))", detail: "\(a.status.rawValue) · \(a.kind) · \(a.group ?? "")") { app.focus(a) })
        }
        if case .agent(let id) = app.selectedTab, let a = app.agent(id), !app.monitor.config.readOnly {
            c.insert(.init(title: "prompt \(short(a.name))", detail: "send this agent a message") { app.sheet = .prompt(a) }, at: 0)
        }
        let q = query.lowercased()
        return q.isEmpty ? c : c.filter { $0.title.lowercased().contains(q) || $0.detail.lowercased().contains(q) }
    }

    var body: some View {
        let list = commands
        ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { app.paletteOpen = false }
            VStack(spacing: 0) {
                HStack {
                    Text("›").foregroundStyle(Theme.accent)
                    TextField("type a command or an agent", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { run(list) }
                        .onKeyPress(.downArrow) { index = min(index + 1, max(list.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                        .onKeyPress(.escape) { app.paletteOpen = false; return .handled }
                }
                .font(Theme.mono(15)).padding(14)
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                            HStack {
                                Text(c.title).font(Theme.mono(14, .semibold))
                                Text(c.detail).font(Theme.mono(12)).foregroundStyle(i == index ? Theme.accentInk.opacity(0.7) : Theme.dim).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(i == index ? Theme.accentInk : Theme.text)
                            .background(i == index ? Theme.accent : .clear)
                            .contentShape(Rectangle())
                            .onTapGesture { index = i; run(list) }
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
            .frame(width: 620)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.6)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, 70)
        }
        .onChange(of: query) { _, _ in index = 0 }
    }

    func run(_ list: [PaletteCommand]) {
        guard list.indices.contains(index) else { return }
        app.paletteOpen = false
        list[index].run()
    }
}

/// One line under an agent's pane, like herdr's: folder · branch · model · state.
struct PaneStatusLine: View {
    @Environment(AppState.self) private var app
    let agent: Agent
    var body: some View {
        HStack(spacing: 0) {
            Text(Spaces.tildePath(agent.cwd ?? "")).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
            if let b = app.monitor.branches[agent.id] {
                Text(" · ").foregroundStyle(Theme.faint)
                Text("git:\(b)").foregroundStyle(Theme.accent)
            }
            Text(" · ").foregroundStyle(Theme.faint)
            Text(agent.model ?? agent.kind).foregroundStyle(Theme.model)
            Spacer()
            StatusDot(status: agent.status, size: 8)
            Text(" \(agent.status.rawValue)").foregroundStyle(Theme.color(agent.status))
            if let r = agent.attentionReason, agent.status.needsPerson {
                Text(" · \(r.replacingOccurrences(of: "_", with: " "))").foregroundStyle(Theme.color(.blocked))
            }
        }
        .font(Theme.mono(12))
        .padding(.horizontal, 20).frame(height: 26)
    }
}
