import Foundation

// Reads agent pull requests and merges them through the `gh` CLI. Owned by the OpenRig rig: see
// ROADMAP.md, milestone M2.

public struct GitHubClient: Sendable {
    /// Name or path of the `gh` executable.
    public var ghPath: String
    let run: CommandRunner

    public init(ghPath: String = "gh", runner: @escaping CommandRunner = Runners.shell) {
        self.ghPath = ghPath; self.run = runner
    }

    static let prFields = "number,title,url,state,isDraft,headRefOid,statusCheckRollup"

    /// A repo must look like "owner/name": it goes into a `gh api` path and a `--repo` option.
    public static func checkRepo(_ repo: String) throws {
        func word(_ s: Substring) -> Bool {
            if s.isEmpty || s == "." || s == ".." || s.hasPrefix("-") { return false }
            return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
        }
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, word(parts[0]), word(parts[1]) else {
            throw KliegError("\"\(repo.prefix(60))\" isn't a repo name. Use owner/name.")
        }
    }

    @discardableResult
    func gh(_ args: [String], timeout: Double = 30) throws -> CommandResult {
        let cmd = [ghPath] + args
        let r = try run(cmd, nil, timeout)
        if !r.ok { throw ShellError.failed(cmd, r) }
        return r
    }

    /// Open pull requests in `repo` ("owner/name") with their checks and whether the head commit is signed
    /// and verified. A commit whose signature can't be read is reported as `signed: nil`.
    public func pullRequests(repo: String, limit: Int = 30) throws -> [PullRequest] {
        try Self.checkRepo(repo)
        let out = try gh(["pr", "list", "--repo", repo, "--state", "open", "--limit", String(limit), "--json", Self.prFields])
        return try Self.parsePullRequests(Data(out.stdout.utf8), repo: repo).map { pr, sha in
            var pr = pr
            pr.signed = try? verified(repo: repo, sha: sha)
            return pr
        }
    }

    /// True when GitHub shows the commit's signature as verified.
    public func verified(repo: String, sha: String) throws -> Bool {
        try Self.checkRepo(repo)
        guard !sha.isEmpty, sha.allSatisfy(\.isHexDigit) else { throw KliegError("\"\(sha.prefix(60))\" isn't a commit sha.") }
        let out = try gh(["api", "repos/\(repo)/commits/\(sha)", "--jq", ".commit.verification"])
        guard let v = try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any] else {
            throw KliegError("gh api returned no verification for \(sha)")
        }
        return v["verified"] as? Bool ?? false
    }

    /// Squash-merges a pull request. Refuses unless it's open, not a draft, every check passed and the head
    /// commit is verified. The merge is pinned to the head commit that was checked, so a push in between fails it.
    @discardableResult
    public func merge(repo: String, number: Int) throws -> String {
        try Self.checkRepo(repo)
        let out = try gh(["pr", "view", String(number), "--repo", repo, "--json", Self.prFields])
        guard let o = try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any],
              let parsed = Self.pullRequest(from: o, repo: repo) else {
            throw KliegError("gh pr view returned JSON Klieg doesn't recognize")
        }
        let (pr, sha) = parsed
        guard pr.state == "OPEN" else { throw KliegError("\(pr.id) is \(pr.state.lowercased()), not open.") }
        if o["isDraft"] as? Bool == true { throw KliegError("\(pr.id) is a draft.") }
        switch pr.checks {
        case "success": break
        case nil: throw KliegError("\(pr.id) has no checks, so Klieg won't merge it.")
        case let c?: throw KliegError("\(pr.id) checks are \(c), not green.")
        }
        guard try verified(repo: repo, sha: sha) else {
            throw KliegError("\(pr.id) head commit \(sha.prefix(7)) isn't a verified signed commit.")
        }
        let r = try gh(["pr", "merge", String(number), "--repo", repo, "--squash", "--match-head-commit", sha], timeout: 60)
        let said = (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return said.isEmpty ? "Merged \(pr.id) (squash)." : said
    }

    // MARK: Parsing

    /// Pull requests and their head commit SHAs from `gh pr list --json …`.
    public static func parsePullRequests(_ data: Data, repo: String) throws -> [(PullRequest, String)] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw KliegError("gh pr list returned JSON Klieg doesn't recognize")
        }
        return rows.compactMap { pullRequest(from: $0, repo: repo) }
    }

    static func pullRequest(from o: [String: Any], repo: String) -> (PullRequest, String)? {
        guard let number = o["number"] as? Int else { return nil }
        let pr = PullRequest(repo: repo, number: number, title: o["title"] as? String ?? "", url: o["url"] as? String ?? "",
                             state: o["state"] as? String ?? "UNKNOWN",
                             checks: rollup(o["statusCheckRollup"] as? [[String: Any]] ?? []))
        return (pr, o["headRefOid"] as? String ?? "")
    }

    /// One word for a PR's checks: "failure" if any failed, else "pending" if any are still running, else
    /// "success". nil when there are no checks. Skipped and neutral checks count as passing.
    public static func rollup(_ checks: [[String: Any]]) -> String? {
        guard !checks.isEmpty else { return nil }
        var pending = false
        for c in checks {
            if let status = c["status"] as? String {
                // A check run (GitHub Actions and apps).
                guard status.uppercased() == "COMPLETED" else { pending = true; continue }
                let conclusion = (c["conclusion"] as? String ?? "").uppercased()
                if !["SUCCESS", "NEUTRAL", "SKIPPED"].contains(conclusion) { return "failure" }
            } else {
                // A commit status (older CI integrations).
                switch (c["state"] as? String ?? "").uppercased() {
                case "SUCCESS": break
                case "PENDING", "EXPECTED", "": pending = true
                default: return "failure"
                }
            }
        }
        return pending ? "pending" : "success"
    }
}
