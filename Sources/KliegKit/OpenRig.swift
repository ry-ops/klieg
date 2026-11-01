import Foundation

// Reads and steers an OpenRig daemon through its `rig` CLI, either on this machine or over
// `ssh <openrigHost>`. Owned by the OpenRig rig: see ROADMAP.md, milestone M2.

/// Runs a command for a client: arguments, optional stdin, timeout in seconds. The self-test swaps in a
/// fake that returns recorded output, so nothing here needs a live rig or GitHub.
public typealias CommandRunner = @Sendable (_ args: [String], _ stdin: String?, _ timeout: Double) throws -> CommandResult

public enum Runners {
    /// The real thing: `Shell.run`.
    public static let shell: CommandRunner = { args, stdin, timeout in try Shell.run(args, stdin: stdin, timeout: timeout) }
}

/// An action Klieg refused, or a source that answered with something Klieg can't use.
public struct KliegError: Error, CustomStringConvertible, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Spots prompts that a person must answer themselves, whatever an agent or tool asks.
public enum PromptGuard {
    /// Phrases that mean money: Klieg never answers these for anyone.
    /// A false match only means the person answers it themselves; a missed one could spend money.
    public static let billingPhrases = ["usage credit", "credits", "billing", "extra usage", "extra-usage", "usage limit",
                                        "rate limit", "payment", "purchase", "add funds", "subscription",
                                        "upgrade your plan", "spend limit", "spending limit"]

    /// The billing phrase found near the bottom of a screen (where a live prompt is), or nil.
    public static func billingPhrase(in screen: String, lastLines: Int = 30) -> String? {
        let tail = screen.split(separator: "\n", omittingEmptySubsequences: false).suffix(lastLines).joined(separator: "\n").lowercased()
        return billingPhrases.first { tail.contains($0) }
    }
}

public struct OpenRigClient: Sendable {
    /// ssh target of the OpenRig host; nil runs `rig` here.
    public var host: String?
    /// Name or path of the `rig` executable on that host.
    public var rigPath: String
    let run: CommandRunner

    public init(host: String?, rigPath: String = "rig", runner: @escaping CommandRunner = Runners.shell) {
        self.host = host; self.rigPath = rigPath; self.run = runner
    }

    public init(config: KliegConfig, runner: @escaping CommandRunner = Runners.shell) {
        self.init(host: config.openrigHost, runner: runner)
    }

    /// The full command line that runs `rig <args>` here or on the OpenRig host. Over ssh the remote shell
    /// re-splits the command, so every argument is single-quoted.
    public func command(_ args: [String]) -> [String] {
        let full = [rigPath] + args
        guard let host else { return full }
        return ["ssh", "-o", "BatchMode=yes", host, full.map(RigText.shellQuote).joined(separator: " ")]
    }

    @discardableResult
    func rig(_ args: [String], stdin: String? = nil, timeout: Double = 30) throws -> CommandResult {
        let cmd = command(args)
        let r = try run(cmd, stdin, timeout)
        if !r.ok { throw ShellError.failed(cmd, r) }
        return r
    }

    // MARK: Reading

    /// Every seat on the host, across all rigs. Uses the full node records, because only they carry
    /// `activityState` (needs-input and its reason) and `cwd`.
    ///
    /// OpenRig reports a usage-credits screen as `permission_prompt`, so with `labelBilling` each blocked
    /// seat's screen is read and a billing prompt is reported as `attentionReason: "billing"`.
    public func agents(labelBilling: Bool = true) throws -> [Agent] {
        var list = try Self.parseNodes(Data(rig(["ps", "--nodes", "-A", "--full", "--json"]).stdout.utf8), host: host)
        guard labelBilling else { return list }
        for i in list.indices where list[i].status == .blocked {
            if let screen = try? capture(session: list[i].name, lines: 30), PromptGuard.billingPhrase(in: screen) != nil {
                list[i].attentionReason = "billing"
            }
        }
        return list
    }

    /// Open queue items (pending, in-progress, blocked) across all rigs, with their bodies so rows without a
    /// summary still read well. Closed history isn't fetched, so it can't push old open work out of the list.
    public func activeQueue(limit: Int = 1000) throws -> [QueueItem] {
        try Self.parseQueue(Data(rig(["queue", "list", "-A", "--full", "--json", "--limit", String(limit)]).stdout.utf8))
    }

    /// The most recent queue items across all rigs, closed ones included, for the timeline.
    public func queueHistory(limit: Int = 50) throws -> [QueueItem] {
        try Self.parseQueue(Data(rig(["queue", "list", "-a", "-A", "--json", "--limit", String(limit)]).stdout.utf8))
    }

    /// What a seat's terminal shows.
    public struct Screen: Sendable {
        public var text: String
        /// rig says the pane is too small to be sure a prompt on it is shown whole.
        public var promptCutOff: Bool
    }

    /// A seat's terminal: the last `lines` lines, or with nil, 20 lines of history plus the whole visible pane.
    /// `readable` has rig read a small pane at a readable size (the seat redraws briefly).
    public func screen(session: String, lines: Int? = 40, readable: Bool = false) throws -> Screen {
        var args = ["capture", try RigText.positional(session, "seat"), "--json"]
        if let lines { args += ["--lines", String(lines)] }
        if readable { args.append("--readable") }
        return try Self.parseScreen(Data(rig(args).stdout.utf8))
    }

    /// The last `lines` lines of a seat's terminal.
    public func capture(session: String, lines: Int = 40) throws -> String {
        try screen(session: session, lines: lines).text
    }

    // MARK: Actions

    /// Hands a goal to a seat as a queue item. Returns what `rig` printed (it includes the qitem id).
    @discardableResult
    public func queueGoal(destination: String, body: String, source: String = "klieg@external", summary: String? = nil) throws -> String {
        // The summary is the body's first line, so it's checked like any other value: a body starting
        // "--dangerously-interact" must not become an option to rig.
        let line = summary ?? RigText.firstLine(body) ?? "Goal from Klieg"
        return try rig(["queue", "create", "--source", try RigText.positional(source, "source"),
                        "--destination", try RigText.positional(destination, "seat"),
                        "--summary", try RigText.positional(String(line.prefix(120)), "summary (the goal's first line)"),
                        "--body-file", "-"], stdin: body).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Types a message into a seat's terminal (rig adds its From/To envelope and refuses if the seat is at a prompt).
    @discardableResult
    public func send(session: String, text: String) throws -> String {
        try rig(["send", try RigText.positional(session, "seat"), try RigText.positional(text, "message")])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Answers the interactive prompt a seat is stopped at, by typing `answer` as keystrokes. Reads the screen
    /// first and refuses billing or usage-credit prompts: only the person answers those.
    @discardableResult
    public func answerPrompt(session: String, answer: String, reason: String = "Answered by the person through Klieg") throws -> String {
        let session = try RigText.positional(session, "seat"), answer = try RigText.positional(answer, "answer")
        // Read the whole visible pane at a readable size: a small window can cut off the prompt's wording,
        // and a guard that can't see the words would let a billing prompt through.
        let shown = try screen(session: session, lines: nil, readable: true)
        if shown.promptCutOff {
            throw KliegError("\(session)'s window is too small to read its whole prompt, so Klieg won't answer it. Open the seat and answer it yourself.")
        }
        if let phrase = PromptGuard.billingPhrase(in: shown.text) {
            throw KliegError("\(session) is showing a prompt about \"\(phrase)\". Klieg doesn't answer billing or usage-credit prompts; open the seat and answer it yourself.")
        }
        // Known gap: the read above and the send below are separate calls. If the prompt changes in between,
        // the keys go to the new prompt. rig audit-logs every --dangerously-interact send with the reason.
        return try rig(["send", session, answer, "--dangerously-interact", "--reason", reason]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stops one live seat (kills only its tmux session).
    @discardableResult
    public func stop(session: String) throws -> String {
        try rig(["seat", "stop", try RigText.positional(session, "seat")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Launches a rig from a spec path, library name or bundle link.
    @discardableResult
    public func up(spec: String) throws -> String {
        try rig(["up", try RigText.positional(spec, "spec")], timeout: 300).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stops every seat in a rig. OpenRig snapshots it first, so `rig up <rig> --existing` can bring it back.
    @discardableResult
    public func down(rig name: String) throws -> String {
        try rig(["down", try RigText.positional(name, "rig")], timeout: 120).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The command that opens a seat's live terminal from where Klieg runs.
    public func attachCommand(session: String) -> [String] {
        Self.attach(tmux: nil, session: session, host: host)
    }

    // MARK: Parsing (static so the self-test can feed recorded JSON straight in)

    public static func parseNodes(_ data: Data, host: String? = nil) throws -> [Agent] {
        let root = try JSONSerialization.jsonObject(with: data)
        let rows = (root as? [[String: Any]]) ?? ((root as? [String: Any])?["entries"] as? [[String: Any]])
        guard let rows else { throw KliegError("rig ps returned JSON Klieg doesn't recognize") }
        return rows.compactMap { node(from: $0, host: host) }
    }

    static func node(from n: [String: Any], host: String?) -> Agent? {
        guard let session = n["canonicalSessionName"] as? String else { return nil }
        // The human's own terminal seat isn't an agent.
        if n["nodeKind"] as? String == "infrastructure" { return nil }
        let (status, reason) = status(of: n)
        let runtime = n["runtime"] as? String ?? "unknown"
        let attach: [String]? = status == .stopped ? nil : attach(tmux: n["tmuxAttachCommand"] as? String, session: session, host: host)
        return Agent(id: "openrig:\(session)", source: .openrig, name: session,
                     kind: runtime == "claude-code" ? "claude" : runtime,
                     status: status, attentionReason: reason, model: model(of: n), cwd: n["cwd"] as? String,
                     group: n["rigName"] as? String, attachCommand: attach,
                     updated: RigText.date(n["lastActivityAt"] ?? n["lastActivity"]) ?? Date())
    }

    /// Normalizes a seat's state. Prefers the full record's `activityState` (what the `rig ps` table shows
    /// as ACTIVITY), then the compact `agentActivity`.
    static func status(of n: [String: Any]) -> (AgentStatus, String?) {
        let session = (n["sessionStatus"] as? String ?? "").lowercased()
        let life = (n["lifecycleState"] as? String ?? "").lowercased()
        if ["exited", "stopped", "dead", "missing"].contains(session) || ["stopped", "recoverable", "exited"].contains(life) {
            return (.stopped, nil)
        }
        let activity = n["agentActivity"] as? [String: Any]
        let activityReason = activity?["reason"] as? String
        if let a = n["activityState"] as? [String: Any], let display = a["display"] as? String {
            switch display {
            case "needs-input":
                let ni = a["needsInput"] as? [String: Any]
                return (.blocked, (ni?["reason"] as? String) ?? activityReason)
            case "working", "running": return (.working, nil)
            case "idle": return (.idle, nil)
            default: break
            }
        }
        switch activity?["state"] as? String {
        case "needs-input", "needs_input", "blocked": return (.blocked, activityReason)
        case _ where n["needsAttention"] as? Bool == true: return (.blocked, activityReason)
        case "running", "working": return (.working, nil)
        case "idle": return (.idle, nil)
        default: return (.unknown, nil)
        }
    }

    /// The model last observed. Full records give an object, compact ones a [model, source, time] array.
    static func model(of n: [String: Any]) -> String? {
        if let o = n["modelObservation"] as? [String: Any], let m = o["model"] as? String { return m }
        if let a = n["modelObservation"] as? [Any], let m = a.first as? String { return m }
        return n["model"] as? String
    }

    /// The attach command runs where Klieg runs, or over `ssh -t`. The far shell re-splits what ssh
    /// sends it, so over ssh every word is quoted, as `command(_:)` does.
    static func attach(tmux: String?, session: String, host: String?) -> [String] {
        let local = tmux.map { $0.split(separator: " ").map(String.init) } ?? ["tmux", "attach", "-t", session]
        guard let host else { return local }
        return ["ssh", "-t", host, local.map(RigText.shellQuote).joined(separator: " ")]
    }

    public static func parseQueue(_ data: Data) throws -> [QueueItem] {
        let root = try JSONSerialization.jsonObject(with: data)
        let d = root as? [String: Any]
        let rows = (root as? [[String: Any]]) ?? (d?["items"] as? [[String: Any]]) ?? (d?["entries"] as? [[String: Any]])
        guard let rows else { throw KliegError("rig queue list returned JSON Klieg doesn't recognize") }
        return rows.compactMap { q in
            guard let id = q["qitemId"] as? String else { return nil }
            return QueueItem(id: id, source: q["sourceSession"] as? String ?? "?", destination: q["destinationSession"] as? String ?? "?",
                             state: q["state"] as? String ?? "unknown", closureReason: q["closureReason"] as? String,
                             created: RigText.date(q["tsCreated"]), updated: RigText.date(q["tsUpdated"]),
                             summary: (q["summary"] as? String).flatMap(RigText.firstLine) ?? (q["body"] as? String).flatMap(RigText.firstLine))
        }
    }

    public static func parseCapture(_ data: Data) throws -> String {
        try parseScreen(data).text
    }

    public static func parseScreen(_ data: Data) throws -> Screen {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KliegError("rig capture returned JSON Klieg doesn't recognize")
        }
        if o["ok"] as? Bool == false {
            throw KliegError("rig capture failed: \(o["error"] as? String ?? o["message"] as? String ?? "no reason given")")
        }
        // rig adds promptPane only when the seat is at a prompt in a pane smaller than 80x24.
        let cutOff = (o["promptPane"].map { !($0 is NSNull) }) ?? false
        return Screen(text: o["content"] as? String ?? "", promptCutOff: cutOff)
    }

    /// One timeline line per queue item, describing where it stands now. Ids include the state, so the
    /// same item produces a new event each time it moves.
    public static func queueEvents(_ items: [QueueItem]) -> [TimelineEvent] {
        items.map { q in
            let what = q.summary ?? q.id
            let (kind, text): (String, String)
            switch q.state {
            case "pending": (kind, text) = ("queued", "\(q.source) queued work for \(q.destination): \(what)")
            case "in-progress": (kind, text) = ("claimed", "\(q.destination) is working on \(what)")
            case "blocked": (kind, text) = ("blocked", "\(q.destination) is blocked on \(what)")
            case "handed-off": (kind, text) = ("handedOff", "\(q.destination) handed off \(what)")
            case "done": (kind, text) = ("done", "\(q.destination) finished \(what)")
            default: (kind, text) = (q.state, "\(q.id) is \(q.state): \(what)")
            }
            return TimelineEvent(id: "\(q.id)#\(q.state)", date: q.updated ?? q.created ?? Date(), source: .openrig,
                                 subject: q.id, kind: kind, text: text)
        }
    }
}

// MARK: Helpers shared with GitHub.swift

/// Small text helpers for reading CLI output. Namespaced so they can't clash with other milestones' code.
public enum RigText {
    /// Quotes one argument for a POSIX shell (plain words are left alone).
    public static func shellQuote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "@%+=:,./_-".contains($0)) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A value that goes to a CLI as a positional argument (a seat, a pane, a message). Refuses one that
    /// starts with "-", which the CLI would read as an option: an agent that prompt-injects the model
    /// could otherwise turn a message into a flag such as `--dangerously-interact`.
    public static func positional(_ value: String, _ what: String) throws -> String {
        if value.hasPrefix("-") {
            throw KliegError("The \(what) can't start with \"-\": a CLI would read it as an option. Got: \(value.prefix(40))")
        }
        return value
    }

    /// The first non-blank line, trimmed.
    public static func firstLine(_ s: String) -> String? {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// An ISO 8601 timestamp, with or without fractional seconds.
    public static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
