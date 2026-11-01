import Foundation

// Spaces: agents grouped the way herdr groups them, for the herdr-style app. A herdr space is a herdr
// workspace (Agent.group); an OpenRig space is a rig. Pure functions over a Snapshot.

public struct Space: Codable, Sendable, Hashable, Identifiable {
    /// "herdr:<machine>/<workspace label>" or "openrig:<rig>".
    public var id: String
    public var source: Source
    public var name: String
    /// herdr: "<cwd with ~> · <branch>" (just the cwd when the branch isn't known).
    /// OpenRig: "<host or local> · <n> seats".
    public var subtitle: String
    /// In `Spaces.agentsOrdered` order.
    public var agentIDs: [String]
    /// The most urgent status among its agents.
    public var status: AgentStatus

    public init(id: String, source: Source, name: String, subtitle: String, agentIDs: [String], status: AgentStatus) {
        self.id = id; self.source = source; self.name = name; self.subtitle = subtitle; self.agentIDs = agentIDs; self.status = status
    }
}

public enum Spaces {
    /// Lower is more urgent: blocked > working > done > idle > unknown > stopped.
    public static func urgency(_ s: AgentStatus) -> Int {
        switch s {
        case .blocked: return 0
        case .working: return 1
        case .done: return 2
        case .idle: return 3
        case .unknown: return 4
        case .stopped: return 5
        }
    }

    /// Groups a snapshot's agents into spaces. Spaces with a blocked agent come first, then those with a
    /// working agent, then the rest by name.
    ///
    /// - Parameters:
    ///   - branches: git branch by agent id (what `BranchResolver.branches(for:)` returns) or by cwd.
    ///   - openrigHost: the OpenRig ssh target, for the subtitle; nil means "local".
    public static func group(_ snapshot: Snapshot, branches: [String: String] = [:], openrigHost: String? = nil) -> [Space] {
        var buckets: [String: (source: Source, name: String, agents: [Agent])] = [:]
        var order: [String] = []
        for a in snapshot.agents where a.source != .github {
            let (id, name) = key(for: a)
            if buckets[id] == nil { buckets[id] = (a.source, name, []); order.append(id) }
            buckets[id]!.agents.append(a)
        }
        let spaces = order.map { id -> Space in
            let b = buckets[id]!
            let agents = ordered(b.agents)
            let status = agents.map(\.status).min { urgency($0) < urgency($1) } ?? .unknown
            return Space(id: id, source: b.source, name: b.name,
                         subtitle: subtitle(source: b.source, agents: agents, branches: branches, openrigHost: openrigHost),
                         agentIDs: agents.map(\.id), status: status)
        }
        return spaces.sorted { a, b in
            let ra = min(urgency(a.status), 2), rb = min(urgency(b.status), 2)   // blocked, working, then the rest
            if ra != rb { return ra < rb }
            let c = a.name.localizedCaseInsensitiveCompare(b.name)
            return c != .orderedSame ? c == .orderedAscending : a.id < b.id
        }
    }

    /// The space's agents: those needing a person first, then working ones, then the rest by name.
    public static func agentsOrdered(in space: Space, snapshot: Snapshot) -> [Agent] {
        let ids = Set(space.agentIDs)
        return ordered(snapshot.agents.filter { ids.contains($0.id) })
    }

    static func ordered(_ agents: [Agent]) -> [Agent] {
        func rank(_ a: Agent) -> Int { a.status.needsPerson ? 0 : (a.status == .working ? 1 : 2) }
        return agents.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            let c = a.name.localizedCaseInsensitiveCompare(b.name)
            return c != .orderedSame ? c == .orderedAscending : a.id < b.id
        }
    }

    /// Space id and name for an agent.
    static func key(for a: Agent) -> (String, String) {
        switch a.source {
        case .herdr:
            // Agent ids are "herdr:<machine>/<pane>"; keep the machine so two hosts' "~" don't merge.
            let rest = a.id.dropFirst("herdr:".count)
            let machine = rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            let name = a.group ?? "herdr"
            return ("herdr:\(machine)/\(name)", name)
        case .openrig, .github:
            let name = a.group ?? "openrig"
            return ("openrig:\(name)", name)
        }
    }

    static func subtitle(source: Source, agents: [Agent], branches: [String: String], openrigHost: String?) -> String {
        switch source {
        case .openrig, .github:
            let host = openrigHost.map { h in h.split(separator: "@").last.map(String.init) ?? h } ?? "local"
            return "\(host) · \(agents.count) \(agents.count == 1 ? "seat" : "seats")"
        case .herdr:
            // The cwd most of its agents share (ties go to the first in agent order).
            var counts: [String: Int] = [:]
            for a in agents { if let c = a.cwd { counts[c, default: 0] += 1 } }
            guard let best = counts.values.max(), let first = agents.first(where: { $0.cwd.map { counts[$0] == best } ?? false }),
                  let cwd = first.cwd else { return "" }
            let branch = branches[first.id] ?? branches[cwd]
            return tildePath(cwd) + (branch.map { " · \($0)" } ?? "")
        }
    }

    /// "/home/ubuntu/src/x" or "/Users/ryan/src/x" → "~/src/x"; "/root/x" → "~/x".
    public static func tildePath(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count >= 3, parts[0].isEmpty, ["home", "Users"].contains(parts[1]), !parts[2].isEmpty {
            return (["~"] + parts.dropFirst(3)).joined(separator: "/")
        }
        if parts.count >= 2, parts[0].isEmpty, parts[1] == "root" {
            return (["~"] + parts.dropFirst(2)).joined(separator: "/")
        }
        return path
    }
}
