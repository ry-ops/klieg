import Foundation
import KliegKit

/// What a tool hands back: text for the model, plus structured JSON when there is some.
struct ToolOutput {
    var text: String
    var structured: Any? = nil
}

/// One MCP tool: its schema and what it does.
struct Tool {
    var name: String
    var title: String
    var description: String
    /// JSON Schema properties, and which are required.
    var properties: [String: Any] = [:]
    var required: [String] = []
    /// Act tools change something and are refused in read-only mode.
    var acts: Bool
    /// Stops agents, merges code or answers prompts: clients should confirm with the person first.
    var destructive: Bool = false
    var run: (KliegBackend, Args) throws -> ToolOutput

    var definition: [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return [
            "name": name, "title": title, "description": description, "inputSchema": schema,
            "annotations": ["title": title, "readOnlyHint": !acts, "destructiveHint": destructive,
                            "idempotentHint": !acts, "openWorldHint": true],
        ]
    }
}

/// Typed access to a tool call's arguments.
struct Args {
    var raw: [String: Any]

    func string(_ key: String) throws -> String {
        guard let s = raw[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KliegError("Missing \(key).")
        }
        return s
    }
    func optionalString(_ key: String) -> String? {
        (raw[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    func int(_ key: String, default d: Int? = nil) throws -> Int {
        if let i = raw[key] as? Int { return i }
        if let n = raw[key] as? Double, n == n.rounded() { return Int(n) }
        if let s = raw[key] as? String, let i = Int(s) { return i }
        if let d, raw[key] == nil { return d }
        throw KliegError("Missing or invalid \(key) (a whole number).")
    }
}

func prop(_ type: String, _ description: String) -> [String: Any] { ["type": type, "description": description] }

let agentProp = prop("string", "Agent id from klieg_status, e.g. openrig:dev-build@my-rig or herdr:<machine>/<pane>.")

/// Encodes a Codable value as plain JSON objects for `structuredContent`.
func jsonObject<T: Encodable>(_ value: T) -> Any {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    guard let data = try? enc.encode(value), let o = try? JSONSerialization.jsonObject(with: data) else { return [:] }
    return o
}

enum KliegTools {
    static let all: [Tool] = [
        // Read
        Tool(name: "klieg_status", title: "Agent status",
             description: "Every herdr agent and OpenRig seat with its state (idle, working, blocked, done, stopped), who needs the person and why, and active OpenRig queue items.",
             acts: false) { b, _ in
            let s = b.snapshot()
            return ToolOutput(text: statusText(s), structured: jsonObject(s))
        },
        Tool(name: "klieg_timeline", title: "Timeline",
             description: "Recent activity, newest first: queue items queued, claimed, handed off and finished, and agent state changes.",
             properties: ["limit": prop("integer", "How many events (default 30).")], acts: false) { b, a in
            let events = b.timeline(limit: try a.int("limit", default: 30))
            let text = events.isEmpty ? "No activity yet." : events.map { "\(iso($0.date))  \($0.text)" }.joined(separator: "\n")
            return ToolOutput(text: text, structured: ["events": jsonObject(events)])
        },
        Tool(name: "klieg_read_agent", title: "Read an agent's screen",
             description: "The last lines of an agent's terminal, to see what it's doing or what it's asking.",
             properties: ["agent": agentProp, "lines": prop("integer", "How many lines (default 40).")],
             required: ["agent"], acts: false) { b, a in
            ToolOutput(text: try b.readAgent(try a.string("agent"), lines: try a.int("lines", default: 40)))
        },
        Tool(name: "klieg_pull_requests", title: "Pull requests",
             description: "Open pull requests in the watched repos (or one repo), with check status and whether the head commit is signed.",
             properties: ["repo": prop("string", "owner/name. Omit for every configured repo.")], acts: false) { b, a in
            let prs = try b.pullRequests(repo: a.optionalString("repo"))
            let text = prs.isEmpty ? "No open pull requests." : prs.map {
                "\($0.id)  \($0.title)  checks: \($0.checks ?? "none")  signed: \($0.signed.map { $0 ? "yes" : "no" } ?? "unknown")\n  \($0.url)"
            }.joined(separator: "\n")
            return ToolOutput(text: text, structured: ["pullRequests": jsonObject(prs)])
        },

        // Act
        Tool(name: "klieg_prompt_agent", title: "Prompt an agent",
             description: "Type a message into an agent's terminal and press Enter. OpenRig refuses if the seat is stopped at a prompt; use klieg_answer_prompt for that.",
             properties: ["agent": agentProp, "text": prop("string", "The message.")], required: ["agent", "text"], acts: true) { b, a in
            ToolOutput(text: done(try b.prompt(try a.string("agent"), text: try a.string("text")), "Sent."))
        },
        Tool(name: "klieg_queue_goal", title: "Queue a goal",
             description: "Hand a goal to an OpenRig seat as a durable queue item. Better than a prompt for real work: it survives restarts and shows on the timeline.",
             properties: ["destination": prop("string", "OpenRig seat, e.g. dev-build@my-rig."), "body": prop("string", "The goal, in plain words. The first line is its summary.")],
             required: ["destination", "body"], acts: true) { b, a in
            ToolOutput(text: done(try b.queueGoal(destination: try a.string("destination"), body: try a.string("body")), "Queued."))
        },
        Tool(name: "klieg_start_agent", title: "Start an agent",
             description: "Start a coding agent in a herdr pane. (OpenRig seats start with their rig: use klieg_rig_up.)",
             properties: ["name": prop("string", "Name for the new agent."), "kind": prop("string", "Runtime, e.g. claude or codex."),
                          "pane": prop("string", "herdr pane to start in. Omit for a new one.")],
             required: ["name", "kind"], acts: true) { b, a in
            ToolOutput(text: done(try b.startAgent(name: try a.string("name"), kind: try a.string("kind"), pane: a.optionalString("pane")), "Started."))
        },
        Tool(name: "klieg_stop_agent", title: "Stop an agent",
             description: "Stop one OpenRig seat. Its session ends and any turn in progress stops. (herdr has no single-agent stop.) Confirm with the person first.",
             properties: ["agent": agentProp], required: ["agent"], acts: true, destructive: true) { b, a in
            ToolOutput(text: done(try b.stopAgent(try a.string("agent")), "Stopped."))
        },
        Tool(name: "klieg_rig_up", title: "Bring a rig up",
             description: "Launch an OpenRig rig from a spec path, library name or bundle link, or bring a stopped rig back with its name.",
             properties: ["spec": prop("string", "Rig spec path, library name or bundle link.")], required: ["spec"], acts: true) { b, a in
            ToolOutput(text: done(try b.rigUp(spec: try a.string("spec")), "Rig is up."))
        },
        Tool(name: "klieg_rig_down", title: "Take a rig down",
             description: "Stop every seat in an OpenRig rig; work in progress stops with them. OpenRig snapshots it first. Confirm with the person first.",
             properties: ["rig": prop("string", "Rig name.")], required: ["rig"], acts: true, destructive: true) { b, a in
            ToolOutput(text: done(try b.rigDown(rig: try a.string("rig")), "Rig is down."))
        },
        Tool(name: "klieg_answer_prompt", title: "Answer a prompt",
             description: "Answer the interactive prompt an agent is stopped at (a permission or a question) by typing keys, e.g. \"1\" or \"y\". Refuses prompts about usage credits or billing. Read the screen with klieg_read_agent and confirm with the person first.",
             properties: ["agent": agentProp, "answer": prop("string", "Keys to type, e.g. 1, y, or a short reply. For herdr agents, space-separated key names such as 1, esc or enter.")],
             required: ["agent", "answer"], acts: true, destructive: true) { b, a in
            ToolOutput(text: done(try b.answerPrompt(try a.string("agent"), answer: try a.string("answer")), "Answered."))
        },
        Tool(name: "klieg_merge_pr", title: "Merge a pull request",
             description: "Squash-merge a pull request. Refuses unless every check passed and the head commit is signed and verified. Confirm with the person first.",
             properties: ["repo": prop("string", "owner/name."), "number": prop("integer", "Pull request number.")],
             required: ["repo", "number"], acts: true, destructive: true) { b, a in
            ToolOutput(text: done(try b.mergePR(repo: try a.string("repo"), number: try a.int("number")), "Merged."))
        },
    ]

    static func named(_ name: String) -> Tool? { all.first { $0.name == name } }

    static func statusText(_ s: Snapshot) -> String {
        var lines: [String] = []
        let needing = s.needingPerson
        lines.append(needing.isEmpty ? "Nobody needs you." : "\(needing.count) need you:")
        for a in needing { lines.append("  ! \(a.id)  \(a.attentionReason ?? "waiting")") }
        lines.append("Agents:")
        for a in s.agents {
            lines.append("  \(a.id)  \(a.status.rawValue)\(a.model.map { "  \($0)" } ?? "")\(a.group.map { "  [\($0)]" } ?? "")")
        }
        let active = s.queue.filter { ["pending", "in-progress", "blocked"].contains($0.state) }
        if !active.isEmpty {
            lines.append("Queue:")
            for q in active { lines.append("  \(q.id)  \(q.state)  \(q.source) → \(q.destination)\(q.summary.map { "  \($0)" } ?? "")") }
        }
        for (src, err) in s.errors.sorted(by: { $0.key < $1.key }) { lines.append("Couldn't read \(src): \(err)") }
        return lines.joined(separator: "\n")
    }

    static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    static func done(_ said: String, _ fallback: String) -> String { said.isEmpty ? fallback : said }
}
