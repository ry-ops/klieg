import Foundation

// Collector: one Snapshot from every source Klieg watches (herdr, OpenRig, GitHub). Milestone M3b.
//
// The three sources are read at the same time, and each one fails on its own: a failure goes into
// `errors["herdr"]`, `errors["openrig"]` or `errors["github"]` and the other sources still show.
// Those keys match `Source.rawValue`, which is what `Timeline.carryOver` looks for.

public final class Collector: @unchecked Sendable {
    public let config: KliegConfig
    /// Also fetch open pull requests for `config.repos`. The MCP server turns this off for
    /// `klieg_status`, which has its own pull-request tool.
    public var includePullRequests: Bool
    let runner: CommandRunner

    private let lock = NSLock()
    private var herdrClient: HerdrClient?

    public init(config: KliegConfig, runner: @escaping CommandRunner = Runners.shell,
                herdr: HerdrClient? = nil, includePullRequests: Bool = true) {
        self.config = config; self.runner = runner; self.herdrClient = herdr
        self.includePullRequests = includePullRequests
    }

    /// The herdr client. Built the first time it's needed, because choosing local or remote can run
    /// `herdr machine list`, and nothing should run before Klieg is asked for something.
    public var herdr: HerdrClient {
        lock.lock(); defer { lock.unlock() }
        if let herdrClient { return herdrClient }
        let run = runner
        let c = HerdrClient.fromConfig(config, runner: { args, timeout in try run(args, nil, timeout) })
        herdrClient = c
        return c
    }

    public var openrig: OpenRigClient { OpenRigClient(config: config, runner: runner) }
    public var github: GitHubClient { GitHubClient(runner: runner) }

    /// Everything Klieg can see right now.
    public func snapshot(now: Date = Date()) -> Snapshot {
        let herdr = self.herdr, openrig = self.openrig, github = self.github
        let repos = includePullRequests ? config.repos : []
        let box = SnapshotBox()
        let group = DispatchGroup()

        DispatchQueue.global().async(group: group) {
            let h = herdr.snapshot(now: now)
            box.update { s in
                s.agents += h.agents
                for (k, v) in h.errors { s.errors[k] = v }
            }
        }
        DispatchQueue.global().async(group: group) {
            var agents: [Agent] = [], queue: [QueueItem] = [], problems: [String] = []
            do { agents = try openrig.agents() } catch { problems.append("seats: \(error)") }
            do { queue = try openrig.activeQueue() } catch { problems.append("queue: \(error)") }
            box.update { s in
                s.agents += agents
                s.queue = queue
                if !problems.isEmpty { s.errors[Source.openrig.rawValue] = problems.joined(separator: "; ") }
            }
        }
        if !repos.isEmpty {
            DispatchQueue.global().async(group: group) {
                var prs: [PullRequest] = [], problems: [String] = []
                for repo in repos {
                    do { prs += try github.pullRequests(repo: repo) } catch { problems.append("\(repo): \(error)") }
                }
                box.update { s in
                    s.pullRequests = prs
                    if !problems.isEmpty { s.errors[Source.github.rawValue] = problems.joined(separator: "; ") }
                }
            }
        }
        group.wait()

        var s = box.value
        s.taken = now
        // Same order every time, whichever source answered first.
        let rank: [Source: Int] = [.herdr: 0, .openrig: 1, .github: 2]
        s.agents.sort { (rank[$0.source] ?? 9, $0.id) < (rank[$1.source] ?? 9, $1.id) }
        s.pullRequests.sort { ($0.repo, $0.number) < ($1.repo, $1.number) }
        return s
    }
}

/// A snapshot the source readers fill in from different threads.
private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = Snapshot()
    func update(_ body: (inout Snapshot) -> Void) { lock.lock(); body(&snapshot); lock.unlock() }
    var value: Snapshot { lock.lock(); defer { lock.unlock() }; return snapshot }
}
