import Foundation
import KliegKit

// The MCP server (`klieg mcp`, stdio). Owned by the OpenRig rig: see ROADMAP.md, milestone M2.
// Follow afm-studio's Sources/AFMServer/MCPServer.swift: plain JSON-RPC over stdio, no SDK dependency.
public enum KliegServer {
    public static let toolNames: [String] = []

    public static func runStdio() -> Int32 {
        FileHandle.standardError.write(Data("klieg mcp: not implemented yet (ROADMAP M2)\n".utf8))
        return 1
    }
}
