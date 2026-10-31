import Foundation

// Shared vocabulary for everything Klieg watches. The herdr and OpenRig clients map their tools'
// JSON onto these types; the app, CLI and MCP server only ever see these.

/// Where a piece of state came from.
public enum Source: String, Codable, Sendable, CaseIterable {
    case herdr, openrig, github
}

/// An agent's lifecycle, normalized across herdr and OpenRig.
public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    /// Ready for input.
    case idle
    /// Busy with a turn.
    case working
    /// Waiting on a person: an approval, a question, a credit prompt.
    case blocked
    /// Finished a turn the person hasn't looked at yet.
    case done
    /// Present, but its state can't be read with confidence.
    case unknown
    /// The process is gone.
    case stopped

    /// True when a person has to act before the agent can continue.
    public var needsPerson: Bool { self == .blocked }
}

/// One coding agent: a herdr pane occupant or an OpenRig seat.
public struct Agent: Codable, Sendable, Hashable, Identifiable {
    /// Stable across refreshes: "herdr:<machine>/<pane>" or "openrig:<session>".
    public var id: String
    public var source: Source
    /// herdr agent name, or OpenRig seat session ("dev-build@unifi-pair").
    public var name: String
    /// Runtime, e.g. "claude", "codex".
    public var kind: String
    public var status: AgentStatus
    /// Why the source thinks a person is needed (OpenRig `permission_prompt`, etc.), when known.
    public var attentionReason: String?
    /// Model the agent was last seen using, when the source reports it.
    public var model: String?
    public var cwd: String?
    /// Group: herdr workspace label, or OpenRig rig name.
    public var group: String?
    /// Command that opens this agent's live terminal, e.g. `tmux attach -t …` over ssh.
    public var attachCommand: [String]?
    public var updated: Date

    public init(id: String, source: Source, name: String, kind: String, status: AgentStatus,
                attentionReason: String? = nil, model: String? = nil, cwd: String? = nil, group: String? = nil,
                attachCommand: [String]? = nil, updated: Date = Date()) {
        self.id = id; self.source = source; self.name = name; self.kind = kind; self.status = status
        self.attentionReason = attentionReason; self.model = model; self.cwd = cwd; self.group = group
        self.attachCommand = attachCommand; self.updated = updated
    }
}

/// An OpenRig queue item (qitem): a unit of work handed from one seat (or person) to another.
public struct QueueItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var source: String
    public var destination: String
    /// pending, in-progress, blocked, done…
    public var state: String
    public var closureReason: String?
    public var created: Date?
    public var updated: Date?
    /// First line of the body, for display.
    public var summary: String?

    public init(id: String, source: String, destination: String, state: String, closureReason: String? = nil,
                created: Date? = nil, updated: Date? = nil, summary: String? = nil) {
        self.id = id; self.source = source; self.destination = destination; self.state = state
        self.closureReason = closureReason; self.created = created; self.updated = updated; self.summary = summary
    }
}

/// A pull request an agent opened.
public struct PullRequest: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(repo)#\(number)" }
    public var repo: String
    public var number: Int
    public var title: String
    public var url: String
    public var state: String
    /// "success", "failure", "pending", or nil when there are no checks.
    public var checks: String?
    public var signed: Bool?

    public init(repo: String, number: Int, title: String, url: String, state: String, checks: String? = nil, signed: Bool? = nil) {
        self.repo = repo; self.number = number; self.title = title; self.url = url; self.state = state
        self.checks = checks; self.signed = signed
    }
}

/// One line in the activity timeline.
public struct TimelineEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: Date
    public var source: Source
    /// Agent id, qitem id or PR id the event is about.
    public var subject: String
    /// statusChanged, needsPerson, claimed, handedOff, prOpened, checksFinished, merged…
    public var kind: String
    /// One plain sentence for people, e.g. "dev-review handed its verdict back to dev-build".
    public var text: String

    public init(id: String = UUID().uuidString, date: Date = Date(), source: Source, subject: String, kind: String, text: String) {
        self.id = id; self.date = date; self.source = source; self.subject = subject; self.kind = kind; self.text = text
    }
}

/// Everything Klieg knows at one moment.
public struct Snapshot: Codable, Sendable {
    public var taken: Date
    public var agents: [Agent]
    public var queue: [QueueItem]
    public var pullRequests: [PullRequest]
    /// Sources that failed to answer this round, with the reason.
    public var errors: [String: String]

    public init(taken: Date = Date(), agents: [Agent] = [], queue: [QueueItem] = [], pullRequests: [PullRequest] = [], errors: [String: String] = [:]) {
        self.taken = taken; self.agents = agents; self.queue = queue; self.pullRequests = pullRequests; self.errors = errors
    }

    public var needingPerson: [Agent] { agents.filter { $0.status.needsPerson } }
}
