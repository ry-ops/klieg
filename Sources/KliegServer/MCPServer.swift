import Foundation
import KliegKit

/// A Model Context Protocol server over stdio: newline-delimited JSON-RPC 2.0, no SDK. Same shape as
/// afm-studio's AFMServer/MCPServer.swift. Requests are handled one at a time, in order.
public final class MCPServer {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    let backend: KliegBackend
    let readOnly: Bool

    public init(backend: KliegBackend, readOnly: Bool) {
        self.backend = backend; self.readOnly = readOnly
    }

    static func log(_ s: String) { FileHandle.standardError.write(Data("[klieg-mcp] \(s)\n".utf8)) }

    /// Reads requests from stdin until it closes.
    public func run() {
        MCPServer.log("ready (klieg \(KliegVersion.string)\(readOnly ? ", read-only" : ""))")
        while let line = readLine(strippingNewline: true) {
            if let reply = handleLine(line) { FileHandle.standardOutput.write(Data((reply + "\n").utf8)) }
        }
    }

    /// Handles one line and returns the reply line, or nil when there's nothing to say (a notification).
    public func handleLine(_ line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let msg = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        if let batch = msg as? [Any] {
            let replies = batch.compactMap { ($0 as? [String: Any]).flatMap(handle) }
            return replies.isEmpty ? nil : encode(replies)
        }
        guard let m = msg as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid request"]])
        }
        return handle(m).map(encode)
    }

    struct RPCError: Error { let code: Int; let message: String }

    func handle(_ m: [String: Any]) -> [String: Any]? {
        guard let id = m["id"], !(id is NSNull) else { return nil } // notification (initialized, cancelled, …)
        guard let method = m["method"] as? String else {
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "Invalid request"]]
        }
        let params = (m["params"] as? [String: Any]) ?? [:]
        do {
            return ["jsonrpc": "2.0", "id": id, "result": try dispatch(method, params)]
        } catch let e as RPCError {
            return ["jsonrpc": "2.0", "id": id, "error": ["code": e.code, "message": e.message]]
        } catch {
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": "\(error)"]]
        }
    }

    func dispatch(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return [
                "protocolVersion": MCPServer.supportedVersions.contains(asked) ? asked : MCPServer.supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": KliegVersion.name, "title": "Klieg", "version": KliegVersion.string],
                "instructions": MCPServer.instructions + (readOnly ? "\nThis server is read-only (KLIEG_READ_ONLY): every act tool is refused." : ""),
            ]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": KliegTools.all.map(\.definition)]
        case "tools/call":
            guard let name = params["name"] as? String else { throw RPCError(code: -32602, message: "Missing tool name") }
            guard let tool = KliegTools.named(name) else { throw RPCError(code: -32602, message: "Unknown tool: \(name)") }
            return call(tool, Args(raw: (params["arguments"] as? [String: Any]) ?? [:]))
        case "resources/list":
            return ["resources": []]
        case "resources/templates/list":
            return ["resourceTemplates": []]
        case "prompts/list":
            return ["prompts": []]
        default:
            throw RPCError(code: -32601, message: "Method not found: \(method)")
        }
    }

    func call(_ tool: Tool, _ args: Args) -> [String: Any] {
        if tool.acts && readOnly {
            return failure("Klieg is read-only (KLIEG_READ_ONLY is set), so \(tool.name) was refused. Nothing was changed.")
        }
        do {
            let out = try tool.run(backend, args)
            var r: [String: Any] = ["content": [["type": "text", "text": out.text]], "isError": false]
            if let s = out.structured { r["structuredContent"] = s }
            return r
        } catch {
            return failure("\(error)")
        }
    }

    func failure(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": true]
    }

    func encode(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Could not encode reply"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    static let instructions = """
    Klieg watches the coding agents running in herdr panes and OpenRig rigs, and the pull requests they open.
    Start with klieg_status: it lists every agent, its state, and which ones are blocked on a person and why. klieg_read_agent shows an agent's screen; klieg_timeline shows recent activity.
    To give an OpenRig seat real work, prefer klieg_queue_goal over klieg_prompt_agent: a queue item survives restarts.
    klieg_stop_agent, klieg_rig_down, klieg_answer_prompt and klieg_merge_pr change things that are hard to undo. Confirm with the person before calling them. klieg_answer_prompt never answers billing or usage-credit prompts, and klieg_merge_pr only merges green, signed pull requests.
    """
}
