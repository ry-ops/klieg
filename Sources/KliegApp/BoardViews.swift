import SwiftUI
import AppKit
import KliegKit

extension AgentStatus {
    var color: Color {
        switch self {
        case .working: return .blue
        case .blocked: return .orange
        case .done: return .green
        case .idle: return .gray
        case .unknown: return .purple
        case .stopped: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .working: return "bolt.fill"
        case .blocked: return "hand.raised.fill"
        case .done: return "checkmark.circle.fill"
        case .idle: return "moon.zzz"
        case .unknown: return "questionmark.circle"
        case .stopped: return "stop.circle"
        }
    }
}

struct StatusBadge: View {
    let status: AgentStatus
    var body: some View {
        Label(status.rawValue, systemImage: status.symbol)
            .font(.caption.bold())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(status.color.opacity(0.18), in: Capsule())
            .foregroundStyle(status.color)
    }
}

/// Header strip shared by the data sections: refresh time and any source errors.
struct SourceStrip: View {
    @Environment(AppState.self) private var app
    var body: some View {
        let m = app.monitor
        HStack(spacing: 10) {
            if m.refreshing { ProgressView().controlSize(.small) }
            Text(m.lastRefresh.map { "Updated \($0.formatted(date: .omitted, time: .standard))" } ?? "Connecting…")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(m.snapshot.errors.sorted(by: { $0.key < $1.key }), id: \.key) { src, err in
                Label("\(src): \(err)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).lineLimit(1).help(err)
            }
            Spacer()
            Button { Task { await m.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh now")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// MARK: Board

struct BoardView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let agents = app.monitor.snapshot.agents
        let groups = Dictionary(grouping: agents, by: { $0.group ?? "Ungrouped" }).sorted { $0.key < $1.key }
        VStack(spacing: 0) {
            SourceStrip()
            Divider()
            if agents.isEmpty {
                ContentUnavailableView("No agents yet", systemImage: "square.grid.2x2",
                                       description: Text("Start an agent in herdr or an OpenRig rig and it shows up here."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.key) { group, members in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group).font(.headline)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                                    ForEach(members.sorted { $0.name < $1.name }) { AgentCard(agent: $0) }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

struct AgentCard: View {
    @Environment(AppState.self) private var app
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: agent.source == .herdr ? "rectangle.split.3x1" : "person.2")
                    .foregroundStyle(.secondary)
                Text(agent.name).font(.headline).lineLimit(1)
                Spacer()
                StatusBadge(status: agent.status)
            }
            Text("\(agent.source.rawValue) · \(agent.kind)" + (agent.model.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            if agent.status.needsPerson {
                Text(reasonText(agent)).font(.callout).foregroundStyle(.orange)
            }
            if let cwd = agent.cwd {
                Text(cwd).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            AgentActions(agent: agent)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(agent.status.color.opacity(agent.status.needsPerson ? 0.8 : 0.15),
                                                          lineWidth: agent.status.needsPerson ? 2 : 1))
    }
}

struct AgentActions: View {
    @Environment(AppState.self) private var app
    let agent: Agent

    var body: some View {
        HStack(spacing: 8) {
            Button { app.openTerminal(for: agent) } label: { Label("Open", systemImage: "terminal") }
                .disabled(agent.attachCommand == nil)
                .help("Open this agent's live session in the built-in terminal")
            Button { app.sheet = .read(agent) } label: { Label("Screen", systemImage: "text.alignleft") }
                .disabled(agent.source != .herdr)
                .help("Read the agent's recent screen")
            Button { app.sheet = .prompt(agent) } label: { Label("Prompt", systemImage: "paperplane") }
                .disabled(agent.source != .herdr || app.monitor.config.readOnly || agent.status == .blocked)
                .help(app.monitor.config.readOnly ? "Klieg is read-only" : "Send this agent a prompt")
        }
        .controlSize(.small)
    }
}

// MARK: Needs You

struct NeedsYouView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let waiting = app.monitor.snapshot.needingPerson
        VStack(spacing: 0) {
            SourceStrip()
            Divider()
            if waiting.isEmpty {
                ContentUnavailableView("Nobody needs you", systemImage: "checkmark.seal",
                                       description: Text("When an agent stops to ask you something, it shows up here and you get a notification."))
            } else {
                List(waiting) { a in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(a.name).font(.headline)
                            Text(a.group ?? "").foregroundStyle(.secondary)
                            Spacer()
                            StatusBadge(status: a.status)
                        }
                        Text(reasonText(a))
                        Text("Answer it in the agent's own terminal. Klieg never answers prompts that spend usage credits.")
                            .font(.caption).foregroundStyle(.secondary)
                        AgentActions(agent: a)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: Timeline

struct TimelineView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let events = app.monitor.events.reversed()
        VStack(spacing: 0) {
            SourceStrip()
            Divider()
            if events.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Status changes, handoffs and PRs appear here as they happen."))
            } else {
                List(Array(events)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(e.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                        Image(systemName: icon(e)).foregroundStyle(color(e)).frame(width: 16)
                        Text(e.text)
                        Spacer()
                        Text(e.source.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    func icon(_ e: TimelineEvent) -> String {
        switch e.kind {
        case "needsPerson": return "hand.raised.fill"
        case "appeared": return "plus.circle"
        case "stopped": return "stop.circle"
        case "prOpened": return "arrow.triangle.pull"
        case "merged": return "arrow.triangle.merge"
        default: return "circle.fill"
        }
    }
    func color(_ e: TimelineEvent) -> Color { e.kind == "needsPerson" ? .orange : .accentColor }
}

// MARK: Sheets

enum AgentSheet: Identifiable {
    case read(Agent), prompt(Agent)
    var id: String {
        switch self { case .read(let a): return "read:" + a.id; case .prompt(let a): return "prompt:" + a.id }
    }
}

struct ReadSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let agent: Agent
    @ViewState private var text = "Reading…"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(agent.name): recent screen").font(.headline)
            ScrollView {
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 640, minHeight: 360)
            .background(Color(nsColor: .textBackgroundColor))
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding()
        .task {
            let client = app.monitor.herdr
            let name = agent.name
            text = await Task.detached { (try? client.read(name, lines: 80)) ?? "Couldn't read this agent's screen." }.value
        }
    }
}

struct PromptSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let agent: Agent
    @ViewState private var text = ""
    @ViewState private var error: String?
    @ViewState private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send a prompt to \(agent.name)").font(.headline)
            Text("It goes straight into the agent's session, as if you typed it there.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.body.monospaced()).frame(minWidth: 520, minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(sending ? "Sending…" : "Send") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
        }
        .padding()
    }

    func send() {
        sending = true
        let client = app.monitor.herdr, name = agent.name, body = text
        Task {
            let err: String? = await Task.detached { () -> String? in
                do { try client.prompt(name, text: body); return nil } catch { return "\(error)" }
            }.value
            sending = false
            if let err { error = err } else { dismiss(); await app.monitor.refresh() }
        }
    }
}
