import Foundation

// BranchResolver: the git branch an agent is on, from `git -C <cwd> branch --show-current` run where the
// agent runs: here, on the OpenRig host over ssh, or on the herdr machine over ssh. Answers (and failures)
// are cached for a minute, so the app can ask on every refresh.

public final class BranchResolver: @unchecked Sendable {
    public typealias Clock = @Sendable () -> Date

    /// ssh target for OpenRig seats; nil runs git here.
    public let openrigHost: String?
    /// ssh target for herdr agents; nil runs git here (Klieg is on the herdr host).
    public let herdrHost: String?
    public let ttl: TimeInterval
    let run: CommandRunner
    let now: Clock

    private let lock = NSLock()
    private var cache: [String: (branch: String?, expires: Date)] = [:]

    public init(openrigHost: String?, herdrHost: String?, ttl: TimeInterval = 60,
                runner: @escaping CommandRunner = Runners.shell, now: @escaping Clock = { Date() }) {
        self.openrigHost = openrigHost; self.herdrHost = herdrHost; self.ttl = ttl; self.run = runner; self.now = now
    }

    /// Hosts from the config and the herdr client: a remote herdr client's machine is reached with its
    /// `sshHost`, or the machine label when that's not set (the same host `attachCommand` uses).
    public convenience init(config: KliegConfig, herdr: HerdrClient, ttl: TimeInterval = 60,
                            runner: @escaping CommandRunner = Runners.shell, now: @escaping Clock = { Date() }) {
        var herdrHost: String? = nil
        if case .remote(let machine, _) = herdr.target { herdrHost = herdr.sshHost ?? machine }
        self.init(openrigHost: config.openrigHost, herdrHost: herdrHost, ttl: ttl, runner: runner, now: now)
    }

    /// Where an agent's git runs: nil for this machine.
    public func host(for agent: Agent) -> String? {
        switch agent.source {
        case .openrig: return openrigHost
        case .herdr: return herdrHost
        case .github: return nil
        }
    }

    /// The agent's branch, or nil (no cwd, not a git repo, detached HEAD, host unreachable).
    public func branch(for agent: Agent) -> String? {
        guard let cwd = agent.cwd, !cwd.isEmpty else { return nil }
        return branch(cwd: cwd, host: host(for: agent))
    }

    /// Branch by agent id, for every agent whose branch is known. Pass it to `Spaces.group(_:branches:)`.
    public func branches(for agents: [Agent]) -> [String: String] {
        var out: [String: String] = [:]
        for a in agents { if let b = branch(for: a) { out[a.id] = b } }
        return out
    }

    public func branch(cwd: String, host: String?) -> String? {
        let key = "\(host ?? "")\u{0}\(cwd)"
        let t = now()
        lock.lock()
        if let hit = cache[key], hit.expires > t { lock.unlock(); return hit.branch }
        lock.unlock()

        let found = lookup(cwd: cwd, host: host)
        lock.lock()
        cache[key] = (found, t.addingTimeInterval(ttl))
        lock.unlock()
        return found
    }

    /// The command line that asks git, here or over ssh. The remote shell re-splits it, so every
    /// argument is quoted (as OpenRigClient does).
    public func command(cwd: String, host: String?) -> [String] {
        let git = ["git", "-C", cwd, "branch", "--show-current"]
        guard let host else { return git }
        return ["ssh", "-o", "BatchMode=yes", host, git.map(RigText.shellQuote).joined(separator: " ")]
    }

    func lookup(cwd: String, host: String?) -> String? {
        guard let r = try? run(command(cwd: cwd, host: host), nil, 10), r.ok else { return nil }
        let b = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty || b.contains("\n") ? nil : b
    }
}
