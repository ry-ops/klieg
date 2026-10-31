import Foundation
import KliegKit

// The MCP server (`klieg mcp`, stdio). Owned by the OpenRig rig: see ROADMAP.md, milestone M2.
// Plain JSON-RPC 2.0 over stdio with no SDK, following afm-studio's Sources/AFMServer/MCPServer.swift.
public enum KliegServer {
    public static var toolNames: [String] { KliegTools.all.map(\.name) }

    /// Runs the server on stdin/stdout with the user's configuration. `KLIEG_READ_ONLY=1` refuses every act tool.
    public static func runStdio() -> Int32 {
        let config = KliegConfig.load()
        MCPServer(backend: LiveBackend(config: config), readOnly: config.readOnly).run()
        return 0
    }
}
