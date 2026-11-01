import SwiftUI
import AppKit
import KliegKit

// The panels (timeline, pull requests, settings) and the boxes (read, prompt, answer, confirm, error).
// All of it follows docs/design.md: mono text, flat panels, words for actions, nothing from macOS.

/// Timeline, pull requests and settings open as tabs in the main area, not as sheets.
enum Panel: String, CaseIterable, Identifiable {
    case timeline, pullRequests, settings
    var id: String { rawValue }
    var title: String { self == .pullRequests ? "pull requests" : rawValue }
}

struct PanelPane: View {
    let panel: Panel
    var body: some View {
        switch panel {
        case .timeline: TimelinePane()
        case .pullRequests: PullRequestsPane()
        case .settings: SettingsPane()
        }
    }
}

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
        case .stopSeat(let a): return "stop \(short(a.name))?"
        case .merge(let p): return "squash-merge \(p.repo)#\(p.number)?"
        }
    }
    var message: String {
        switch self {
        case .stopSeat: return "This ends the seat's session and any turn in progress. Its rig stays up; you can restart the seat from OpenRig."
        case .merge(let p): return "\"\(p.title)\" goes into main as one squashed commit and its branch is deleted. Klieg checks again that CI passed and the commit is signed."
        }
    }
    /// The word on the destructive key-button.
    var verb: String {
        switch self { case .stopSeat(let a): return "stop \(short(a.name))"; case .merge(let p): return "merge #\(p.number)" }
    }
}

/// Whatever box is open right now, drawn over the whole window.
struct Overlays: View {
    @Environment(AppState.self) private var app
    var body: some View {
        ZStack {
            if let s = app.sheet {
                switch s {
                case .read(let a): ReadBox(agent: a)
                case .prompt(let a): PromptBox(agent: a)
                case .answer(let a): AnswerBox(agent: a)
                }
            }
            if let c = app.confirm { ConfirmBox(confirm: c) }
            if let e = app.actionError { ErrorBox(message: e) }
        }
    }
}

// MARK: Boxes

struct ReadBox: View {
    @Environment(AppState.self) private var app
    let agent: Agent
    @ViewState private var text = "reading…"

    var body: some View {
        Modal(title: "\(short(agent.name)) · screen", onClose: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(text).font(Theme.mono(11.5)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 360)
                HStack { Spacer(); TermButton("close", key: "esc", shortcut: .cancelAction) { app.sheet = nil } }
            }
        }
        .task {
            let herdr = app.monitor.herdr, rig = app.monitor.openrig
            let name = agent.name, source = agent.source
            text = await Task.detached { () -> String in
                do {
                    return source == .openrig ? try rig.capture(session: name, lines: 80) : try herdr.read(name, lines: 80)
                } catch { return "couldn't read this screen: \(error)" }
            }.value
        }
    }
}

struct PromptBox: View {
    @Environment(AppState.self) private var app
    let agent: Agent
    @ViewState private var text = ""
    @ViewState private var error: String?
    @ViewState private var sending = false

    var body: some View {
        Modal(title: "prompt \(short(agent.name))", onClose: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("goes straight into the agent's session, as if you typed it there").foregroundStyle(Theme.dim)
                TermEditor(text: $text)
                if let error { Text(error).foregroundStyle(Theme.bad) }
                HStack {
                    Spacer()
                    TermButton("cancel", key: "esc", shortcut: .cancelAction) { app.sheet = nil }
                    TermButton(sending ? "sending…" : "send", key: "⌘↩", color: Theme.accent,
                               enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending,
                               shortcut: KeyboardShortcut(.return, modifiers: .command)) { send() }
                }
            }
        }
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
            if let err { error = err } else { app.sheet = nil }
        }
    }
}

struct AnswerBox: View {
    @Environment(AppState.self) private var app
    let agent: Agent
    @ViewState private var screen = "reading…"
    @ViewState private var answer = ""
    @ViewState private var error: String?
    @ViewState private var sending = false

    var body: some View {
        Modal(title: "answer \(short(agent.name))", onClose: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(screen).font(Theme.mono(11.5)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                Text("type exactly what you'd press in the seat, e.g. 1 for the first option · klieg re-reads the screen first and refuses billing prompts")
                    .foregroundStyle(Theme.dim)
                TermField("answer", text: $answer, rule: Theme.bad)
                if let error { Text(error).foregroundStyle(Theme.bad) }
                HStack {
                    TermButton("open the seat instead", key: "›") { app.sheet = nil; app.selectedTab = .agent(agent.id) }
                    Spacer()
                    TermButton("cancel", key: "esc", shortcut: .cancelAction) { app.sheet = nil }
                    TermButton(sending ? "sending…" : "send", key: "↩", color: Theme.bad, enabled: !answer.isEmpty && !sending,
                               shortcut: .defaultAction) { send() }
                }
            }
        }
        .task {
            let rig = app.monitor.openrig, name = agent.name
            screen = await Task.detached { (try? rig.capture(session: name, lines: 40)) ?? "couldn't read the seat" }.value
        }
    }

    func send() {
        sending = true
        let rig = app.monitor.openrig, name = agent.name, a = answer
        Task {
            let err = await app.monitor.act { _ = try rig.answerPrompt(session: name, answer: a) }
            sending = false
            if let err { error = err } else { app.sheet = nil }
        }
    }
}

struct ConfirmBox: View {
    @Environment(AppState.self) private var app
    let confirm: Confirmation

    var body: some View {
        Modal(title: confirm.title, width: 560, onClose: { app.confirm = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                Text(confirm.message).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    TermButton("cancel", key: "esc", shortcut: .cancelAction) { app.confirm = nil }
                    TermButton(confirm.verb, key: "y", color: Theme.bad, shortcut: KeyboardShortcut("y", modifiers: [])) {
                        app.confirm = nil
                        app.perform(confirm)
                    }
                }
            }
        }
    }
}

struct ErrorBox: View {
    @Environment(AppState.self) private var app
    let message: String

    var body: some View {
        Modal(title: "klieg couldn't do that", width: 560, onClose: { app.actionError = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                Text(message).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack { Spacer(); TermButton("ok", key: "esc", shortcut: .cancelAction) { app.actionError = nil } }
            }
        }
    }
}

// MARK: Timeline

struct TimelinePane: View {
    @Environment(AppState.self) private var app

    static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        let events = Array(app.monitor.events.reversed())
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if events.isEmpty {
                    Text("no activity yet · the timeline fills in as agents change state").foregroundStyle(Theme.dim).padding(16)
                }
                ForEach(events) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Self.time.string(from: e.date)).foregroundStyle(Theme.faint).frame(width: 64, alignment: .leading)
                        Text(glyph(e)).foregroundStyle(color(e)).frame(width: 12)
                        Text(e.text).foregroundStyle(Theme.text)
                        Spacer(minLength: 12)
                        Text(e.source.rawValue).foregroundStyle(Theme.faint)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 5)
                }
            }
            .padding(.vertical, 8)
        }
        .font(Theme.mono(12.5))
    }

    func glyph(_ e: TimelineEvent) -> String {
        switch e.kind {
        case "needsPerson": return "!"
        case "appeared", "queued": return "+"
        case "stopped": return "×"
        case "prOpened": return "↑"
        case "merged", "checksFinished", "done": return "✓"
        case "claimed", "handedOff": return "›"
        default: return "·"
        }
    }

    func color(_ e: TimelineEvent) -> Color {
        switch e.kind {
        case "needsPerson": return Theme.bad
        case "merged", "done": return Theme.ok
        case "stopped": return Theme.faint
        default: return Theme.accent
        }
    }
}

// MARK: Pull requests

struct PullRequestsPane: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let prs = app.monitor.snapshot.pullRequests
        let repos = app.monitor.config.repos
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if repos.isEmpty {
                    Text("no repos watched · add them in settings").foregroundStyle(Theme.dim).padding(16)
                } else if prs.isEmpty {
                    Text("no open pull requests · watching \(repos.joined(separator: ", "))").foregroundStyle(Theme.dim).padding(16)
                }
                ForEach(prs) { pr in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(pr.id).foregroundStyle(Theme.accent).frame(width: 190, alignment: .leading).lineLimit(1)
                        Text(pr.title).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 12)
                        Text(pr.checks ?? "no checks").foregroundStyle(checksColor(pr.checks))
                        Text(pr.signed == true ? "signed" : pr.signed == false ? "unsigned" : "signature?")
                            .foregroundStyle(pr.signed == true ? Theme.ok : Theme.bad)
                        TermButton("open") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
                        TermButton("merge", color: Theme.bad,
                                   enabled: !app.monitor.config.readOnly && pr.checks == "success" && pr.signed == true) { app.confirm = .merge(pr) }
                            .help(pr.checks != "success" ? "waits for CI to pass" : pr.signed != true ? "the head commit isn't signed" : "squash-merge")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
            }
            .padding(.vertical, 8)
        }
        .font(Theme.mono(12.5))
    }

    func checksColor(_ c: String?) -> Color {
        switch c {
        case "success": return Theme.ok
        case "failure": return Theme.bad
        case "pending": return Theme.warn
        default: return Theme.faint
        }
    }
}

// MARK: Settings

struct SettingsPane: View {
    @Environment(AppState.self) private var app
    @ViewState private var draft = KliegConfig()
    @ViewState private var repos = ""
    @ViewState private var refresh = "5"
    @ViewState private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                group("herdr") {
                    row("machine", hint: "label from herdr machine list · empty means this computer",
                        text: Binding(get: { draft.herdrMachine ?? "" }, set: { draft.herdrMachine = $0.isEmpty ? nil : $0 }))
                    row("session", hint: "the herdr session to read", text: $draft.herdrSession)
                }
                group("openrig") {
                    row("host", hint: "ssh target of the host running the daemon · empty means this computer",
                        text: Binding(get: { draft.openrigHost ?? "" }, set: { draft.openrigHost = $0.isEmpty ? nil : $0 }))
                }
                group("github") {
                    row("repos", hint: "owner/name, comma-separated · merges stay in these", text: $repos)
                }
                group("behaviour") {
                    row("refresh", hint: "seconds between refreshes (2 to 120)", text: $refresh)
                    TermToggle("read-only · refuse every action (prompt, queue, stop, answer, merge)", isOn: $draft.readOnly)
                        .padding(.leading, 102)
                }
                HStack {
                    if let message { Text(message).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle) }
                    Spacer()
                    TermButton("save", key: "⌘s", color: Theme.accent, shortcut: KeyboardShortcut("s")) { save() }
                }
                Text("saved to \(KliegConfig.file.path)").foregroundStyle(Theme.faint)
            }
            .padding(16)
        }
        .font(Theme.mono(13))
        .onAppear {
            draft = app.monitor.config
            repos = draft.repos.joined(separator: ", ")
            refresh = String(Int(draft.refreshSeconds))
        }
    }

    func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).foregroundStyle(Theme.accent)
            content()
        }
    }

    func row(_ label: String, hint: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Theme.dim).frame(width: 90, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                TermField(label, text: text)
                Text(hint).font(Theme.mono(11.5)).foregroundStyle(Theme.faint)
            }
        }
    }

    func save() {
        draft.repos = repos.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let n = Double(refresh.trimmingCharacters(in: .whitespaces)) { draft.refreshSeconds = min(120, max(2, n)) }
        do { try app.monitor.save(draft); message = "saved" } catch { message = "\(error)" }
    }
}
