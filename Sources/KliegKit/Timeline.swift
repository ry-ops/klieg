import Foundation

// Timeline: turns two snapshots into plain-language events (milestone M1).
// `Timeline.diff` is a pure function: same inputs, same events, ids included.

public enum Timeline {
    /// Events that happened between `old` and `new`. With no `old` there is nothing to compare,
    /// so the first snapshot is only a baseline and gives no events.
    public static func diff(from old: Snapshot?, to new: Snapshot) -> [TimelineEvent] {
        guard let old else { return [] }
        var events: [TimelineEvent] = []
        func add(_ source: Source, _ subject: String, _ kind: String, _ text: String) {
            let stamp = Int(new.taken.timeIntervalSince1970 * 1000)
            events.append(TimelineEvent(id: "\(stamp):\(subject):\(kind)", date: new.taken, source: source,
                                        subject: subject, kind: kind, text: text))
        }

        // Agents. Skip sources that failed this round, so an outage doesn't look like every agent stopping.
        let before = Dictionary(old.agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(new.agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for a in new.agents {
            guard let was = before[a.id] else {
                add(a.source, a.id, "appeared", "\(label(a)) appeared" + (a.group.map { " in \($0)" } ?? ""))
                if a.status.needsPerson { add(a.source, a.id, "needsPerson", needsText(a)) }
                continue
            }
            if a.status == was.status {
                if a.status.needsPerson && a.attentionReason != was.attentionReason {
                    add(a.source, a.id, "needsPerson", needsText(a))
                }
                continue
            }
            if a.status.needsPerson {
                add(a.source, a.id, "needsPerson", needsText(a))
            } else if a.status == .stopped {
                add(a.source, a.id, "stopped", "\(label(a)) stopped")
            } else {
                add(a.source, a.id, "statusChanged", "\(label(a)) \(statusText(a.status, from: was.status))")
            }
        }
        for a in old.agents where after[a.id] == nil && a.status != .stopped && new.errors[a.source.rawValue] == nil {
            add(a.source, a.id, "stopped", "\(label(a)) stopped")
        }

        // Queue items (OpenRig).
        let oldQueue = Dictionary(old.queue.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for q in new.queue {
            let what = q.summary.map { ": \($0)" } ?? ""
            if let was = oldQueue[q.id] {
                if was.state != q.state {
                    add(.openrig, q.id, "queueStateChanged", "\(q.destination)'s queue item \(q.id) is now \(q.state)")
                }
            } else {
                add(.openrig, q.id, "queued", "\(q.source) handed \(q.destination) a queue item\(what)")
            }
        }

        // Pull requests.
        let oldPRs = Dictionary(old.pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in new.pullRequests {
            guard let was = oldPRs[p.id] else {
                add(.github, p.id, "prOpened", "\(p.id) opened: \(p.title)")
                continue
            }
            if was.state != p.state {
                if p.state.lowercased() == "merged" { add(.github, p.id, "merged", "\(p.id) was merged") }
                else { add(.github, p.id, "prStateChanged", "\(p.id) is now \(p.state.lowercased())") }
            }
            if was.checks != p.checks, let c = p.checks, c != "pending" {
                add(.github, p.id, "checksFinished", "\(p.id) checks finished: \(c)")
            }
        }
        return events
    }

    /// The snapshot to compare the next one against: `new`, plus the agents from `old` whose source
    /// failed this round. Without this, every agent would "appear" again once the source recovers.
    public static func carryOver(from old: Snapshot?, to new: Snapshot) -> Snapshot {
        guard let old, !new.errors.isEmpty else { return new }
        var out = new
        let have = Set(new.agents.map(\.id))
        out.agents += old.agents.filter { new.errors[$0.source.rawValue] != nil && !have.contains($0.id) }
        return out
    }

    static func label(_ a: Agent) -> String { a.kind == "unknown" ? a.name : "\(a.name) (\(a.kind))" }

    static func needsText(_ a: Agent) -> String {
        switch a.attentionReason {
        case "trust_prompt": return "\(label(a)) needs you: Claude is asking whether to trust the folder"
        case nil, "approval_or_question": return "\(label(a)) needs you: it is waiting on an approval or a question"
        case let r?: return "\(label(a)) needs you (\(r))"
        }
    }

    static func statusText(_ s: AgentStatus, from old: AgentStatus) -> String {
        switch s {
        case .working: return "started working"
        case .done: return "finished a turn"
        case .idle: return old == .blocked ? "is no longer waiting on you" : "is idle"
        case .unknown: return "is in a state herdr can't read"
        case .blocked: return "needs you"
        case .stopped: return "stopped"
        }
    }
}

/// Keeps the last snapshot and recent events on disk, so `klieg timeline` can show what changed
/// since it last ran. Files live next to the config: last-snapshot.json and timeline.jsonl.
public struct TimelineStore {
    public var directory: URL
    /// Oldest events are dropped past this many.
    public var keep: Int

    public init(directory: URL = KliegConfig.file.deletingLastPathComponent(), keep: Int = 500) {
        self.directory = directory; self.keep = keep
    }

    var snapshotFile: URL { directory.appendingPathComponent("last-snapshot.json") }
    var eventsFile: URL { directory.appendingPathComponent("timeline.jsonl") }

    public static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    public static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public func lastSnapshot() -> Snapshot? {
        guard let d = try? Data(contentsOf: snapshotFile) else { return nil }
        return try? Self.decoder.decode(Snapshot.self, from: d)
    }

    public func events() -> [TimelineEvent] {
        guard let text = try? String(contentsOf: eventsFile, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? Self.decoder.decode(TimelineEvent.self, from: Data($0.utf8)) }
    }

    /// Diffs `new` against the stored snapshot, saves both, and returns the new events.
    @discardableResult
    public func record(_ new: Snapshot) throws -> [TimelineEvent] {
        let fresh = Timeline.diff(from: lastSnapshot(), to: new)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(Timeline.carryOver(from: lastSnapshot(), to: new)).write(to: snapshotFile, options: .atomic)
        if !fresh.isEmpty {
            let all = (events() + fresh).suffix(keep)
            let lines = try all.map { String(decoding: try Self.encoder.encode($0), as: UTF8.self) }
            try (lines.joined(separator: "\n") + "\n").write(to: eventsFile, atomically: true, encoding: .utf8)
        }
        return fresh
    }
}
