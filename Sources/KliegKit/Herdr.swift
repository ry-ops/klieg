import Foundation

// HerdrClient: reads and steers herdr through its CLI (milestone M1).
//
// On the herdr host it runs `herdr --session <s> …`; from the Mac it runs `herdr --machine <label> …`
// against a machine saved with `herdr machine add`. Every herdr command prints JSON shaped like
// {"id": …, "result": {…}} on success, or {"error": {"code", "message"}} on stderr with exit 1.

public enum HerdrError: Error, CustomStringConvertible, Equatable {
    /// herdr answered with an error object, e.g. code "agent_not_found" or "agent_blocked".
    case herdr(code: String, message: String)
    /// herdr exited non-zero without a readable error object.
    case failed(String)
    /// herdr's output could not be decoded.
    case badOutput(String)
    /// Klieg is in read-only mode, so actions are refused.
    case readOnly
    /// The agent id isn't a herdr agent, or belongs to another herdr machine.
    case notHerdrAgent(String)

    public var description: String {
        switch self {
        case .herdr(let code, let message): return "herdr: \(message) (\(code))"
        case .failed(let s): return "herdr failed: \(s)"
        case .badOutput(let s): return "herdr gave unexpected output: \(s)"
        case .readOnly: return "Klieg is read-only (KLIEG_READ_ONLY), so this action was refused"
        case .notHerdrAgent(let id): return "\(id) is not an agent on this herdr machine"
        }
    }
}

/// The parts of herdr's JSON that Klieg uses. Field names follow herdr's snake_case.
public enum HerdrJSON {
    public struct AgentInfo: Decodable, Sendable {
        /// Agent kind, e.g. "claude", "codex".
        public var agent: String?
        public var agent_status: String?
        public var name: String?
        public var pane_id: String
        public var tab_id: String?
        public var workspace_id: String?
        public var cwd: String?
        public var foreground_cwd: String?
        public var terminal_title_stripped: String?
    }

    public struct Workspace: Decodable, Sendable {
        public var workspace_id: String
        public var label: String?
        public var number: Int?
        public var agent_status: String?
    }

    public struct Pane: Decodable, Sendable {
        public var pane_id: String
        public var workspace_id: String?
        public var agent: String?
        public var agent_status: String?
        public var cwd: String?
    }

    public struct SessionSnapshot: Decodable, Sendable {
        public var agents: [AgentInfo]
        public var panes: [Pane]?
        public var workspaces: [Workspace]
        public var version: String?
    }

    struct Envelope<R: Decodable>: Decodable { var result: R }
    struct ErrorEnvelope: Decodable {
        struct Body: Decodable { var code: String; var message: String }
        var error: Body
    }
    struct SnapshotResult: Decodable { var snapshot: SessionSnapshot }
    struct AgentListResult: Decodable { var agents: [AgentInfo] }
    struct AgentGetResult: Decodable { var agent: AgentInfo }
    struct WorkspaceListResult: Decodable { var workspaces: [Workspace] }
    struct PaneListResult: Decodable { var panes: [Pane] }
    struct WorkspaceCreateResult: Decodable {
        struct Root: Decodable { var pane_id: String }
        var workspace: Workspace
        var root_pane: Root?
    }

    /// Decodes the `result` of a successful herdr reply.
    static func result<R: Decodable>(_ type: R.Type, from text: String) throws -> R {
        do {
            return try JSONDecoder().decode(Envelope<R>.self, from: Data(text.utf8)).result
        } catch {
            throw HerdrError.badOutput(String(text.prefix(200)))
        }
    }

    /// Turns a failed herdr run into the most specific error available.
    static func error(from r: CommandResult) -> HerdrError {
        for text in [r.stderr, r.stdout] {
            if let e = try? JSONDecoder().decode(ErrorEnvelope.self, from: Data(text.utf8)) {
                return .herdr(code: e.error.code, message: e.error.message)
            }
        }
        let msg = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed("exit \(r.status)" + (msg.isEmpty ? "" : ": \(msg)"))
    }
}

public struct HerdrClient: Sendable {
    /// Where herdr commands go.
    public enum Target: Sendable, Equatable {
        /// This machine's herdr server: `herdr --session <name> …`.
        case local(session: String)
        /// A saved herdr machine: `herdr --machine <label> …`.
        case remote(machine: String, session: String)
    }

    /// Runs one command. Swapped out in the self-test to replay recorded output.
    public typealias Runner = @Sendable (_ args: [String], _ timeout: Double) throws -> CommandResult

    public var target: Target
    /// The machine part of agent ids ("herdr:<machine>/<pane>"). The same agent gets the same id
    /// whether Klieg reads it locally on the herdr host or remotely from the Mac.
    public var machine: String
    /// ssh target used to open a pane from another computer. Defaults to the machine label, which
    /// works when the label is also a host name (as in the homelab, through Tailscale).
    public var sshHost: String?
    public var readOnly: Bool
    public var herdr: String
    public var runner: Runner

    public init(target: Target, machine: String, sshHost: String? = nil, readOnly: Bool = false,
                herdr: String = "herdr", runner: @escaping Runner = { try Shell.run($0, timeout: $1) }) {
        self.target = target; self.machine = machine; self.sshHost = sshHost; self.readOnly = readOnly
        self.herdr = herdr; self.runner = runner
    }

    /// Builds a client from the config. Uses the local herdr server when there's no machine set, when
    /// running inside a herdr pane, or when the machine label isn't one of this herdr's saved machines
    /// (that is, we are probably on the herdr host itself).
    public static func fromConfig(_ c: KliegConfig = .load(),
                                  runner: @escaping Runner = { try Shell.run($0, timeout: $1) }) -> HerdrClient {
        let hostname = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "local"
        guard let label = c.herdrMachine, !label.isEmpty else {
            return HerdrClient(target: .local(session: c.herdrSession), machine: hostname, readOnly: c.readOnly, runner: runner)
        }
        let insideHerdr = ProcessInfo.processInfo.environment["HERDR_ENV"] == "1"
        let saved = insideHerdr ? false : savedMachines(runner: runner).contains(label)
        let target: Target = saved ? .remote(machine: label, session: c.herdrSession) : .local(session: c.herdrSession)
        return HerdrClient(target: target, machine: label, readOnly: c.readOnly, runner: runner)
    }

    /// Labels and ids from `herdr machine list --json`; empty when herdr is missing or has none.
    static func savedMachines(herdr: String = "herdr", runner: Runner) -> Set<String> {
        guard let r = try? runner([herdr, "machine", "list", "--json"], 10), r.ok,
              let list = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [[String: Any]] else { return [] }
        var names = Set<String>()
        for m in list {
            for key in ["label", "id", "name"] { if let v = m[key] as? String { names.insert(v) } }
        }
        return names
    }

    // MARK: Running herdr

    /// `herdr --session <s>` or `herdr --machine <m>`, ready for a subcommand.
    public var prefix: [String] {
        switch target {
        case .local(let s): return [herdr, "--session", s]
        case .remote(let m, _): return [herdr, "--machine", m]
        }
    }

    /// Runs a herdr subcommand and returns stdout, or throws herdr's error.
    @discardableResult
    func call(_ sub: [String], timeout: Double = 20) throws -> String {
        let r = try runner(prefix + sub, timeout)
        guard r.ok else { throw HerdrJSON.error(from: r) }
        return r.stdout
    }

    func requireWritable() throws { if readOnly { throw HerdrError.readOnly } }

    // MARK: Reading

    public func rawSnapshot() throws -> HerdrJSON.SessionSnapshot {
        try HerdrJSON.result(HerdrJSON.SnapshotResult.self, from: call(["api", "snapshot"])).snapshot
    }

    public func workspaces() throws -> [HerdrJSON.Workspace] {
        try HerdrJSON.result(HerdrJSON.WorkspaceListResult.self, from: call(["workspace", "list"])).workspaces
    }

    public func panes() throws -> [HerdrJSON.Pane] {
        try HerdrJSON.result(HerdrJSON.PaneListResult.self, from: call(["pane", "list"])).panes
    }

    public func agentInfo(_ agent: String) throws -> HerdrJSON.AgentInfo {
        try HerdrJSON.result(HerdrJSON.AgentGetResult.self, from: call(["agent", "get", herdrTarget(agent)])).agent
    }

    /// The agent's terminal text. `source` is one of visible, recent, recent-unwrapped, detection.
    public func read(_ agent: String, lines: Int? = nil, source: String = "recent-unwrapped") throws -> String {
        var sub = ["agent", "read", try herdrTarget(agent), "--source", source]
        if let lines { sub += ["--lines", String(lines)] }
        return try call(sub)
    }

    /// Every agent herdr can see, as Klieg agents.
    ///
    /// herdr reports Claude Code's first-run folder-trust screen as `idle`. So for each idle Claude
    /// agent this also reads the bottom of its screen, and reports `blocked` with
    /// `attentionReason: "trust_prompt"` when that screen is showing.
    public func agents(now: Date = Date()) throws -> [Agent] {
        let snap = try rawSnapshot()
        var screens: [String: String] = [:]
        for a in snap.agents where HerdrClient.mightHideTrustPrompt(a) {
            screens[a.pane_id] = try? call(["agent", "read", a.pane_id, "--source", "detection", "--lines", "40"])
        }
        return mapAgents(snap, screens: screens, now: now)
    }

    /// Everything Klieg knows from herdr right now. herdr failures land in `errors["herdr"]`.
    public func snapshot(now: Date = Date()) -> Snapshot {
        do { return Snapshot(taken: now, agents: try agents(now: now)) }
        catch { return Snapshot(taken: now, errors: ["herdr": "\(error)"]) }
    }

    // MARK: Mapping (pure, tested with fixtures)

    /// True when herdr's status could be hiding the folder-trust screen.
    static func mightHideTrustPrompt(_ a: HerdrJSON.AgentInfo) -> Bool {
        (a.agent ?? "") == "claude" && ["idle", "unknown"].contains(a.agent_status ?? "unknown")
    }

    /// Converts herdr's snapshot to Klieg agents. `screens` holds pane text for agents that might be
    /// showing the trust screen, keyed by pane id.
    public func mapAgents(_ snap: HerdrJSON.SessionSnapshot, screens: [String: String] = [:], now: Date = Date()) -> [Agent] {
        let labels = Dictionary(snap.workspaces.map { ($0.workspace_id, $0.label ?? $0.workspace_id) }, uniquingKeysWith: { a, _ in a })
        return snap.agents.map { a in
            var status = AgentStatus(rawValue: a.agent_status ?? "") ?? .unknown
            var reason: String? = status == .blocked ? "approval_or_question" : nil
            if HerdrClient.mightHideTrustPrompt(a), let text = screens[a.pane_id], HerdrClient.showsTrustPrompt(text) {
                status = .blocked
                reason = "trust_prompt"
            }
            return Agent(id: agentID(pane: a.pane_id), source: .herdr, name: a.name ?? a.pane_id, kind: a.agent ?? "unknown",
                         status: status, attentionReason: reason, cwd: a.foreground_cwd ?? a.cwd,
                         group: a.workspace_id.flatMap { labels[$0] } ?? a.workspace_id,
                         attachCommand: attachCommand(pane: a.pane_id), updated: now)
        }
    }

    /// True when the text is Claude Code's "do you trust this folder" screen (current or older wording).
    public static func showsTrustPrompt(_ text: String) -> Bool {
        let t = text.lowercased()
        let markers = [
            "yes, i trust this folder",
            "is this a project you created or one you trust",
            "do you trust the files in this folder",
        ]
        return markers.contains { t.contains($0) }
    }

    public func agentID(pane: String) -> String { "herdr:\(machine)/\(pane)" }

    /// The herdr target (pane id or agent name) for a Klieg agent id, a pane id, or an agent name.
    public func herdrTarget(_ agent: String) throws -> String {
        guard agent.hasPrefix("herdr:") else { return agent }
        let rest = agent.dropFirst("herdr:".count)
        guard let slash = rest.firstIndex(of: "/"), rest[..<slash] == machine[...] else { throw HerdrError.notHerdrAgent(agent) }
        let pane = String(rest[rest.index(after: slash)...])
        guard !pane.isEmpty else { throw HerdrError.notHerdrAgent(agent) }
        return pane
    }

    /// The command that opens a pane's live terminal. herdr doesn't forward interactive attach over
    /// `--machine`, so from another computer this goes through ssh.
    public func attachCommand(pane: String) -> [String] {
        switch target {
        case .local(let s):
            return [herdr, "--session", s, "agent", "attach", pane]
        case .remote(let m, let s):
            return ["ssh", "-t", sshHost ?? m, "herdr", "--session", s, "agent", "attach", pane]
        }
    }

    // MARK: Actions (refused in read-only mode)

    /// Starts an agent of `kind` (claude, codex, …) named `agent` in an existing shell pane.
    public func start(agent: String, kind: String, pane: String, timeoutMs: Int? = nil) throws {
        try requireWritable()
        var sub = ["agent", "start", agent, "--kind", kind, "--pane", try herdrTarget(pane)]
        if let timeoutMs { sub += ["--timeout", String(timeoutMs)] }
        try call(sub, timeout: Double(timeoutMs ?? 30_000) / 1000 + 10)
    }

    /// Submits a prompt. herdr refuses with `agent_blocked` if the agent is waiting on a person.
    public func prompt(_ agent: String, text: String) throws {
        try requireWritable()
        try call(["agent", "prompt", try herdrTarget(agent), text])
    }

    /// Sends key presses such as "esc", "enter", "ctrl+c".
    public func sendKeys(_ agent: String, keys: [String]) throws {
        try requireWritable()
        try call(["agent", "send-keys", try herdrTarget(agent)] + keys)
    }

    /// Creates a workspace without stealing focus. Returns its id and its first pane's id.
    @discardableResult
    /// With no `cwd`, herdr picks its default folder.
    public func createWorkspace(cwd: String?, label: String? = nil) throws -> (workspace: String, pane: String?) {
        try requireWritable()
        var sub = ["workspace", "create"]
        if let cwd { sub += ["--cwd", cwd] }
        sub.append("--no-focus")
        if let label { sub += ["--label", label] }
        let r = try HerdrJSON.result(HerdrJSON.WorkspaceCreateResult.self, from: call(sub))
        return (r.workspace.workspace_id, r.root_pane?.pane_id)
    }

    /// Closes one pane, ending whatever runs in it (for an agent pane: the agent).
    public func closePane(_ pane: String) throws {
        try requireWritable()
        try call(["pane", "close", try herdrTarget(pane)])
    }

    /// Closes a workspace and every pane in it.
    public func closeWorkspace(_ workspace: String) throws {
        try requireWritable()
        try call(["workspace", "close", workspace])
    }
}
