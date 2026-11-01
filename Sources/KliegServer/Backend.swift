import Foundation
import KliegKit

/// What the MCP tools call. `LiveBackend` is the real one; the self-test drives it with recorded output.
public protocol KliegBackend: AnyObject {
    func snapshot() -> Snapshot
    func timeline(limit: Int) -> [TimelineEvent]
    func readAgent(_ id: String, lines: Int) throws -> String
    func pullRequests(repo: String?) throws -> [PullRequest]

    func prompt(_ id: String, text: String) throws -> String
    func queueGoal(destination: String, body: String) throws -> String
    func startAgent(name: String, kind: String, pane: String?) throws -> String
    func stopAgent(_ id: String) throws -> String
    func rigUp(spec: String) throws -> String
    func rigDown(rig: String) throws -> String
    func answerPrompt(_ id: String, answer: String) throws -> String
    func mergePR(repo: String, number: Int) throws -> String
}

/// A source of agents other than OpenRig. herdr (milestone M1) plugs in here: give `LiveBackend.herdr` an
/// adapter over `HerdrClient` and the herdr side of every tool lights up.
public protocol AgentSource: AnyObject {
    func agents() throws -> [Agent]
    func read(_ id: String, lines: Int) throws -> String
    func prompt(_ id: String, text: String) throws -> String
    func sendKeys(_ id: String, keys: String) throws -> String
    func start(name: String, kind: String, pane: String?) throws -> String
    func stop(_ id: String) throws -> String
}

/// Which system an agent id belongs to.
enum AgentRef: Equatable {
    case openrig(session: String)
    case herdr(id: String)

    /// Accepts the ids `klieg_status` returns ("openrig:<session>", "herdr:<machine>/<pane>") and, for
    /// convenience, a bare OpenRig session name ("dev-build@my-rig").
    static func parse(_ id: String) throws -> AgentRef {
        if id.hasPrefix("openrig:") { return .openrig(session: String(id.dropFirst("openrig:".count))) }
        if id.hasPrefix("herdr:") { return .herdr(id: id) }
        if id.contains("@") { return .openrig(session: id) }
        throw KliegError("Unknown agent \"\(id)\". Use an id from klieg_status, like openrig:dev-build@my-rig or herdr:<machine>/<pane>.")
    }
}

public final class LiveBackend: KliegBackend, @unchecked Sendable {
    public let config: KliegConfig
    public let openrig: OpenRigClient
    public let github: GitHubClient
    /// Reads herdr, OpenRig and GitHub into one snapshot. Pull requests are left out: they have their own tool.
    public let collector: Collector
    /// herdr agents. nil: herdr ids are refused with a clear message.
    public var herdr: AgentSource?
    /// Turns two snapshots into timeline events. nil: the timeline shows queue activity only.
    public var diff: ((Snapshot, Snapshot) -> [TimelineEvent])?

    private let lock = NSLock()
    private var last: Snapshot?
    private var diffEvents: [TimelineEvent] = []

    public init(config: KliegConfig, runner: @escaping CommandRunner = Runners.shell) {
        self.config = config
        self.openrig = OpenRigClient(config: config, runner: runner)
        self.github = GitHubClient(runner: runner)
        let collector = Collector(config: config, runner: runner, includePullRequests: false)
        self.collector = collector
        // The herdr client is built on first use, so starting the server runs no commands.
        self.herdr = HerdrAgentSource(client: { collector.herdr })
        self.diff = Timeline.diff
    }

    public func snapshot() -> Snapshot {
        let s = collector.snapshot()
        lock.lock(); defer { lock.unlock() }
        if let last, let diff { diffEvents = Array((diffEvents + diff(last, s)).suffix(500)) }
        // Keep what a failed source had, so it doesn't all "appear" again when the source is back.
        last = Timeline.carryOver(from: last, to: s)
        return s
    }

    public func timeline(limit: Int) -> [TimelineEvent] {
        let s = snapshot()
        lock.lock(); let fromDiff = diffEvents; lock.unlock()
        // Open items come from the snapshot; recent closed ones (done, handed off) from the history list.
        let history = (try? openrig.queueHistory()) ?? []
        var seen = Set<String>()
        let all = (fromDiff + OpenRigClient.queueEvents(s.queue + history)).filter { seen.insert($0.id).inserted }
        return Array(all.sorted { $0.date > $1.date }.prefix(limit))
    }

    func herdrSource() throws -> AgentSource {
        guard let herdr else { throw KliegError("herdr agents aren't connected to this Klieg backend.") }
        return herdr
    }

    public func readAgent(_ id: String, lines: Int) throws -> String {
        switch try AgentRef.parse(id) {
        case .openrig(let s): return try openrig.capture(session: s, lines: lines)
        case .herdr(let h): return try herdrSource().read(h, lines: lines)
        }
    }

    public func pullRequests(repo: String?) throws -> [PullRequest] {
        if let repo { try GitHubClient.checkRepo(repo) }
        let repos = repo.map { [$0] } ?? config.repos
        if repos.isEmpty { throw KliegError("No repos to watch. Pass repo, or list repos in \(KliegConfig.file.path).") }
        return try repos.flatMap { try github.pullRequests(repo: $0) }
    }

    public func prompt(_ id: String, text: String) throws -> String {
        switch try AgentRef.parse(id) {
        case .openrig(let s): return try openrig.send(session: s, text: text)
        case .herdr(let h): return try herdrSource().prompt(h, text: text)
        }
    }

    public func queueGoal(destination: String, body: String) throws -> String {
        let session: String
        if case .openrig(let s) = try AgentRef.parse(destination) { session = s } else {
            throw KliegError("Queue goals go to OpenRig seats; \(destination) is a herdr agent. Use klieg_prompt_agent instead.")
        }
        return try openrig.queueGoal(destination: session, body: body)
    }

    public func startAgent(name: String, kind: String, pane: String?) throws -> String {
        try herdrSource().start(name: name, kind: kind, pane: pane)
    }

    public func stopAgent(_ id: String) throws -> String {
        switch try AgentRef.parse(id) {
        case .openrig(let s): return try openrig.stop(session: s)
        case .herdr(let h): return try herdrSource().stop(h)
        }
    }

    public func rigUp(spec: String) throws -> String { try openrig.up(spec: spec) }
    public func rigDown(rig: String) throws -> String { try openrig.down(rig: rig) }

    public func answerPrompt(_ id: String, answer: String) throws -> String {
        switch try AgentRef.parse(id) {
        case .openrig(let s):
            return try openrig.answerPrompt(session: s, answer: answer)
        case .herdr(let h):
            let src = try herdrSource()
            // HerdrAgentSource.read returns at least the whole visible pane, so the prompt's wording is
            // there for this check (the OpenRig path uses rig capture --readable).
            if let phrase = PromptGuard.billingPhrase(in: try src.read(h, lines: 40)) {
                throw KliegError("\(h) is showing a prompt about \"\(phrase)\". Klieg doesn't answer billing or usage-credit prompts; open the pane and answer it yourself.")
            }
            return try src.sendKeys(h, keys: answer)
        }
    }

    /// Merges only in a watched repo: the model's `repo` argument can't reach every repo `gh` is signed in to.
    public func mergePR(repo: String, number: Int) throws -> String {
        try GitHubClient.checkRepo(repo)
        guard config.repos.contains(where: { $0.lowercased() == repo.lowercased() }) else {
            throw KliegError("\(repo) isn't a watched repo, so Klieg won't merge in it. Add it to repos in \(KliegConfig.file.path).")
        }
        return try github.merge(repo: repo, number: number)
    }
}
