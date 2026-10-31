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
                                QueueStrip(items: app.monitor.snapshot.queue.filter { q in
                                    members.contains { $0.name == q.destination || $0.name == q.source } })
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
                .help("Read the agent's recent screen")
            if agent.status == .blocked && agent.source == .openrig {
                Button { app.sheet = .answer(agent) } label: { Label("Answer", systemImage: "hand.raised") }
                    .disabled(app.monitor.config.readOnly || agent.attentionReason == "billing")
                    .help(agent.attentionReason == "billing" ? "Only you answer usage-credit prompts: open the seat" : "Answer the prompt this seat is stopped at")
            } else {
                Button { app.sheet = .prompt(agent) } label: { Label("Prompt", systemImage: "paperplane") }
                    .disabled(app.monitor.config.readOnly || agent.status == .blocked || agent.status == .stopped)
                    .help(app.monitor.config.readOnly ? "Klieg is read-only" : "Send this agent a prompt")
            }
            if agent.source == .openrig && agent.status != .stopped {
                Button(role: .destructive) { app.confirm = .stopSeat(agent) } label: { Image(systemName: "stop.fill") }
                    .disabled(app.monitor.config.readOnly)
                    .help("Stop this seat")
            }
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
    case read(Agent), prompt(Agent), answer(Agent)
    var id: String {
        switch self {
        case .read(let a): return "read:" + a.id
        case .prompt(let a): return "prompt:" + a.id
        case .answer(let a): return "answer:" + a.id
        }
    }
}

/// Actions that need a yes from the person first.
enum Confirmation: Identifiable {
    case stopSeat(Agent), merge(PullRequest)
    var id: String {
        switch self { case .stopSeat(let a): return "stop:" + a.id; case .merge(let p): return "merge:" + p.id }
    }
    var title: String {
        switch self {
        case .stopSeat(let a): return "Stop \(a.name)?"
        case .merge(let p): return "Squash-merge \(p.repo) #\(p.number)?"
        }
    }
    var message: String {
        switch self {
        case .stopSeat: return "This ends the seat's session and any turn in progress. Its rig stays up; you can restart the seat from OpenRig."
        case .merge(let p): return "\"\(p.title)\" goes into main as one squashed commit and its branch is deleted. Klieg checks again that CI passed and the commit is signed."
        }
    }
}

struct QueueStrip: View {
    let items: [QueueItem]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Queue").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(items) { q in
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down").foregroundStyle(.secondary)
                        Text(short(q.source)).bold()
                        Image(systemName: "arrow.right").font(.caption2)
                        Text(short(q.destination)).bold()
                        Text(q.state).font(.caption).padding(.horizontal, 5)
                            .background(.blue.opacity(0.15), in: Capsule())
                        if let s = q.summary { Text(s).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .font(.callout)
                }
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    func short(_ s: String) -> String { s.split(separator: "@").first.map(String.init) ?? s }
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
            let herdr = app.monitor.herdr, rig = app.monitor.openrig
            let name = agent.name, source = agent.source
            text = await Task.detached { () -> String in
                do {
                    return source == .openrig ? try rig.capture(session: name, lines: 80) : try herdr.read(name, lines: 80)
                } catch { return "Couldn't read this agent's screen: \(error)" }
            }.value
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
        let herdr = app.monitor.herdr, rig = app.monitor.openrig
        let name = agent.name, body = text, source = agent.source
        Task {
            let err = await app.monitor.act {
                if source == .openrig { _ = try rig.send(session: name, text: body) } else { try herdr.prompt(name, text: body) }
            }
            sending = false
            if let err { error = err } else { dismiss() }
        }
    }
}

struct AnswerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let agent: Agent
    @ViewState private var screen = "Reading…"
    @ViewState private var answer = ""
    @ViewState private var error: String?
    @ViewState private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Answer \(agent.name)'s prompt").font(.headline)
            ScrollView {
                Text(screen).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 640, minHeight: 260)
            .background(Color(nsColor: .textBackgroundColor))
            Text("Type exactly what you'd press in the seat, for example 1 for the first option. Klieg re-reads the screen first and refuses billing or usage-credit prompts.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Answer", text: $answer).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Open seat instead") { app.openTerminal(for: agent); dismiss() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(sending ? "Sending…" : "Send answer") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(answer.isEmpty || sending)
            }
        }
        .padding()
        .task {
            let rig = app.monitor.openrig, name = agent.name
            screen = await Task.detached { (try? rig.capture(session: name, lines: 40)) ?? "Couldn't read the seat." }.value
        }
    }

    func send() {
        sending = true
        let rig = app.monitor.openrig, name = agent.name, a = answer
        Task {
            let err = await app.monitor.act { _ = try rig.answerPrompt(session: name, answer: a) }
            sending = false
            if let err { error = err } else { dismiss() }
        }
    }
}

// MARK: Pull requests

struct PullRequestsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let prs = app.monitor.snapshot.pullRequests
        VStack(spacing: 0) {
            SourceStrip()
            Divider()
            if app.monitor.config.repos.isEmpty {
                ContentUnavailableView("No repos watched", systemImage: "arrow.triangle.pull",
                                       description: Text("Add repos in Settings to see the PRs your agents open."))
            } else if prs.isEmpty {
                ContentUnavailableView("No open PRs", systemImage: "checkmark.circle",
                                       description: Text("Watching " + app.monitor.config.repos.joined(separator: ", ")))
            } else {
                List(prs) { pr in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pr.title).font(.headline)
                            Text("\(pr.repo) #\(pr.number)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        badge(pr.checks ?? "no checks", color: pr.checks == "success" ? .green : pr.checks == "failure" ? .red : .orange)
                        badge(pr.signed == true ? "signed" : "unsigned", color: pr.signed == true ? .green : .red)
                        Button("Open") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
                        Button("Merge") { app.confirm = .merge(pr) }
                            .disabled(app.monitor.config.readOnly || pr.checks != "success" || pr.signed != true)
                            .help(pr.checks != "success" ? "Waits for CI to pass" : pr.signed != true ? "The head commit isn't signed" : "Squash-merge")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule()).foregroundStyle(color)
    }
}

// MARK: Settings

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @ViewState private var draft = KliegConfig()
    @ViewState private var repos = ""
    @ViewState private var message: String?

    var body: some View {
        Form {
            SwiftUI.Section("herdr") {
                TextField("Saved machine (herdr machine list)", text: Binding(get: { draft.herdrMachine ?? "" }, set: { draft.herdrMachine = $0.isEmpty ? nil : $0 }))
                TextField("Session", text: $draft.herdrSession)
            }
            SwiftUI.Section("OpenRig") {
                TextField("SSH host running the daemon (empty = this Mac)", text: Binding(get: { draft.openrigHost ?? "" }, set: { draft.openrigHost = $0.isEmpty ? nil : $0 }))
            }
            SwiftUI.Section("GitHub") {
                TextField("Repos to watch, comma-separated (owner/name)", text: $repos)
            }
            SwiftUI.Section("Behavior") {
                Stepper("Refresh every \(Int(draft.refreshSeconds)) s", value: $draft.refreshSeconds, in: 2...120, step: 1)
                Toggle("Read-only: refuse every action (prompt, queue, stop, answer, merge)", isOn: $draft.readOnly)
            }
            HStack {
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("Save") {
                    draft.repos = repos.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    do { try app.monitor.save(draft); message = "Saved to \(KliegConfig.file.path)" } catch { message = "\(error)" }
                }
                .keyboardShortcut("s")
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = app.monitor.config; repos = draft.repos.joined(separator: ", ") }
    }
}
