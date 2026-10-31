import Foundation
import KliegKit

/// Connects herdr agents to the MCP tools: `LiveBackend.herdr` is one of these. Milestone M3b.
///
/// Read-only mode works as it does for OpenRig: the MCP server refuses every act tool before it gets
/// here. The herdr client is also built with the config's `readOnly`, so a direct caller is refused too.
public final class HerdrAgentSource: AgentSource, @unchecked Sendable {
    private let client: () -> HerdrClient

    /// `client` is called on each use, so the client can be built lazily (see `Collector.herdr`).
    public init(client: @escaping () -> HerdrClient) { self.client = client }

    public convenience init(_ client: HerdrClient) { self.init(client: { client }) }

    public func agents() throws -> [Agent] { try client().agents() }

    /// At least the whole visible pane, so a prompt can't be cut off at the top, and more history when
    /// `lines` asks for more than the pane shows.
    public func read(_ id: String, lines: Int) throws -> String {
        let c = client()
        let visible = try c.read(id, source: "visible")
        let shown = visible.split(separator: "\n", omittingEmptySubsequences: false).count
        if lines <= shown { return visible }
        return try c.read(id, lines: lines, source: "recent-unwrapped")
    }

    public func prompt(_ id: String, text: String) throws -> String {
        try client().prompt(id, text: text)
        return "Sent to \(id)."
    }

    /// `keys` is herdr key names separated by spaces, e.g. "1", "y enter", "esc".
    public func sendKeys(_ id: String, keys: String) throws -> String {
        let list = keys.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !list.isEmpty else { throw KliegError("No keys to send.") }
        try client().sendKeys(id, keys: list)
        return "Sent \(list.joined(separator: " ")) to \(id)."
    }

    /// Starts an agent in `pane`, or in a new workspace named after it when `pane` is nil.
    public func start(name: String, kind: String, pane: String?) throws -> String {
        let c = client()
        var target = pane
        var note = ""
        if target == nil {
            let made = try c.createWorkspace(cwd: nil, label: name)
            guard let root = made.pane else { throw KliegError("herdr made workspace \(made.workspace) but didn't say which pane it has.") }
            target = root
            note = " (new workspace \(made.workspace))"
        }
        do {
            try c.start(agent: name, kind: kind, pane: target!)
        } catch {
            throw KliegError("Couldn't start \(name) in \(target!)\(note): \(error)")
        }
        return "Started \(name) (\(kind)) in \(c.agentID(pane: target!))\(note)."
    }

    /// Closes the agent's pane. herdr has no gentler stop that works for every agent kind.
    public func stop(_ id: String) throws -> String {
        let c = client()
        var pane = try c.herdrTarget(id)
        if !HerdrAgentSource.looksLikePane(pane) { pane = try c.agentInfo(pane).pane_id }
        try c.closePane(pane)
        return "Closed pane \(pane)."
    }

    /// herdr pane ids look like "w1:p1"; agent names can't contain a colon.
    static func looksLikePane(_ s: String) -> Bool { s.contains(":") }
}
