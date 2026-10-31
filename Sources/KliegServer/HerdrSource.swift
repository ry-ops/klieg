import Foundation
import KliegKit

/// Puts M1's `HerdrClient` behind the MCP server's `AgentSource`, so every tool works on herdr agents too.
public final class HerdrSource: AgentSource {
    public let client: HerdrClient

    public init(_ client: HerdrClient) { self.client = client }

    public func agents() throws -> [Agent] { try client.agents() }

    public func read(_ id: String, lines: Int) throws -> String { try client.read(id, lines: lines) }

    /// The whole visible pane, so a prompt's wording can't be scrolled or cut out of view.
    public func screen(_ id: String) throws -> String { try client.read(id, source: "visible") }

    public func prompt(_ id: String, text: String) throws -> String {
        try client.prompt(id, text: text)
        return "Sent."
    }

    /// `keys` is space-separated herdr key names, e.g. "1", "y", "esc" or "enter".
    public func sendKeys(_ id: String, keys: String) throws -> String {
        let list = keys.split(separator: " ").map(String.init)
        guard !list.isEmpty else { throw KliegError("No keys to send.") }
        try client.sendKeys(id, keys: list)
        return "Sent keys: \(list.joined(separator: " "))."
    }

    public func start(name: String, kind: String, pane: String?) throws -> String {
        guard let pane else { throw KliegError("herdr starts agents in an existing shell pane. Pass pane, e.g. w2:p1.") }
        try client.start(agent: name, kind: kind, pane: pane)
        return "Started \(name) (\(kind)) in \(pane)."
    }

    public func stop(_ id: String) throws -> String {
        throw KliegError("herdr has no command to stop a single agent. Open its pane and exit it, or close its workspace in herdr.")
    }
}
