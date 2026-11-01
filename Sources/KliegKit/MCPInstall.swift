import Foundation

// Registers Klieg's MCP server ("klieg") with Claude Code and, on macOS, Claude Desktop. Milestone M4.
//
// Claude Code: through `claude mcp add --scope user …` when the claude CLI is installed, so Claude Code's
// config stays its own business; otherwise by editing ~/.claude.json. Claude Desktop: by editing
// claude_desktop_config.json. File edits are atomic (write a temp file next to it, then rename) and
// change only mcpServers["klieg"]; every other key is kept.

public enum MCPClient: String, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case claudeDesktop = "claude-desktop"

    public var title: String { self == .claudeCode ? "Claude Code" : "Claude Desktop" }
}

/// One MCP server entry: what the client runs.
public struct MCPServerEntry: Equatable, Sendable {
    public var command: String
    public var args: [String]
    public var env: [String: String]

    public init(command: String, args: [String] = ["mcp"], env: [String: String] = [:]) {
        self.command = command; self.args = args; self.env = env
    }

    /// Klieg's own entry: `<binary> mcp`, plus KLIEG_READ_ONLY=1 when read-only.
    public static func klieg(binary: String, readOnly: Bool) -> MCPServerEntry {
        MCPServerEntry(command: binary, args: ["mcp"], env: readOnly ? ["KLIEG_READ_ONLY": "1"] : [:])
    }

    /// The JSON both clients use. `type` is what Claude Code writes for stdio servers.
    func json(for client: MCPClient) -> [String: Any] {
        var o: [String: Any] = ["command": command, "args": args]
        if !env.isEmpty { o["env"] = env }
        if client == .claudeCode { o["type"] = "stdio" }
        return o
    }

    init?(json: Any?) {
        guard let o = json as? [String: Any], let command = o["command"] as? String else { return nil }
        self.command = command
        self.args = o["args"] as? [String] ?? []
        self.env = o["env"] as? [String: String] ?? [:]
    }

    /// e.g. "KLIEG_READ_ONLY=1 /usr/local/bin/klieg mcp"
    public var display: String {
        (env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } + [command] + args).joined(separator: " ")
    }
}

public struct MCPInstaller {
    /// What one client looks like right now.
    public struct ClientStatus: Sendable {
        public var client: MCPClient
        /// The client seems to be installed here.
        public var present: Bool
        /// The config file Klieg reads (and edits, when there's no claude CLI).
        public var configFile: URL
        /// The registered "klieg" entry, if any.
        public var entry: MCPServerEntry?
        /// Why the client can't be used here, e.g. Claude Desktop on Linux.
        public var unavailable: String?
    }

    /// One thing install or uninstall did (or, with dry-run, would do).
    public struct Change: Sendable {
        public var client: MCPClient
        /// False when the client was already as asked.
        public var changed: Bool
        public var message: String
    }

    public var name = "klieg"
    public var home: URL
    /// User-scope Claude Code config: $CLAUDE_CONFIG_DIR/.claude.json, else ~/.claude.json.
    public var claudeCodeConfig: URL
    public var desktopConfig: URL
    /// Path of the claude CLI, or nil to edit ~/.claude.json directly.
    public var claudeCLI: String?
    public var isMacOS: Bool
    let run: CommandRunner

    public init(home: URL? = nil, claudeCodeConfig: URL? = nil, desktopConfig: URL? = nil,
                claudeCLI: String?? = nil, isMacOS: Bool? = nil, runner: @escaping CommandRunner = Runners.shell) {
        let env = ProcessInfo.processInfo.environment
        let h = home ?? URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory())
        self.home = h
        self.claudeCodeConfig = claudeCodeConfig
            ?? URL(fileURLWithPath: env["CLAUDE_CONFIG_DIR"] ?? h.path).appendingPathComponent(".claude.json")
        self.desktopConfig = desktopConfig
            ?? h.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        self.claudeCLI = claudeCLI ?? Shell.which("claude")
        #if os(macOS)
        self.isMacOS = isMacOS ?? true
        #else
        self.isMacOS = isMacOS ?? false
        #endif
        self.run = runner
    }

    /// The absolute path of the running klieg binary.
    public static func currentBinary() -> String {
        let raw = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let abs = raw.hasPrefix("/") ? raw : FileManager.default.currentDirectoryPath + "/" + raw
        return URL(fileURLWithPath: abs).standardizedFileURL.path
    }

    // MARK: Status

    public func status(_ client: MCPClient) -> ClientStatus {
        let file = configFile(client)
        let fm = FileManager.default
        switch client {
        case .claudeCode:
            let present = claudeCLI != nil || fm.fileExists(atPath: file.path)
                || fm.fileExists(atPath: home.appendingPathComponent(".claude").path)
            return ClientStatus(client: client, present: present, configFile: file, entry: registered(in: file))
        case .claudeDesktop:
            guard isMacOS else {
                return ClientStatus(client: client, present: false, configFile: file, entry: nil, unavailable: "Claude Desktop is macOS only")
            }
            let present = fm.fileExists(atPath: file.deletingLastPathComponent().path)
                || fm.fileExists(atPath: "/Applications/Claude.app")
                || fm.fileExists(atPath: home.appendingPathComponent("Applications/Claude.app").path)
            return ClientStatus(client: client, present: present, configFile: file, entry: registered(in: file))
        }
    }

    public func configFile(_ client: MCPClient) -> URL { client == .claudeCode ? claudeCodeConfig : desktopConfig }

    /// The clients to act on: the ones asked for, or every client that's present.
    public func clients(_ asked: [MCPClient]?) throws -> [MCPClient] {
        if let asked {
            for c in asked { if let why = status(c).unavailable { throw KliegError("\(why).") } }
            return asked
        }
        let found = MCPClient.allCases.filter { status($0).present }
        if found.isEmpty { throw KliegError("Neither Claude Code nor Claude Desktop was found here. Pick one with --client.") }
        return found
    }

    func registered(in file: URL) -> MCPServerEntry? {
        guard let root = try? readJSON(file) else { return nil }
        return MCPServerEntry(json: (root["mcpServers"] as? [String: Any])?[name])
    }

    // MARK: Install and uninstall

    @discardableResult
    public func install(_ entry: MCPServerEntry, clients asked: [MCPClient]? = nil, dryRun: Bool = false) throws -> [Change] {
        try clients(asked).map { client in
            let current = status(client).entry
            if current == entry { return Change(client: client, changed: false, message: "already registered: \(entry.display)") }
            let verb = current == nil ? "register" : "update"
            if client == .claudeCode, let cli = claudeCLI {
                var cmds: [[String]] = []
                if current != nil { cmds.append([cli, "mcp", "remove", "--scope", "user", name]) }
                var add = [cli, "mcp", "add", "--scope", "user", name]
                // -e takes several values, so it goes after the name, then `--` ends the options.
                for (k, v) in entry.env.sorted(by: { $0.key < $1.key }) { add += ["-e", "\(k)=\(v)"] }
                add += ["--", entry.command] + entry.args
                cmds.append(add)
                if dryRun {
                    return Change(client: client, changed: true, message: "would run: " + cmds.map { $0.map(RigText.shellQuote).joined(separator: " ") }.joined(separator: " && "))
                }
                for c in cmds { try runChecked(c) }
                return Change(client: client, changed: true, message: "\(verb)ed with the claude CLI: \(entry.display)")
            }
            let file = configFile(client)
            if dryRun { return Change(client: client, changed: true, message: "would \(verb) \(name) in \(file.path): \(entry.display)") }
            try edit(file) { servers in servers[name] = entry.json(for: client) }
            let restart = client == .claudeDesktop ? " Restart Claude Desktop to load it." : ""
            return Change(client: client, changed: true, message: "\(verb)ed in \(file.path): \(entry.display).\(restart)")
        }
    }

    @discardableResult
    public func uninstall(clients asked: [MCPClient]? = nil, dryRun: Bool = false) throws -> [Change] {
        try clients(asked).map { client in
            guard status(client).entry != nil else { return Change(client: client, changed: false, message: "not registered") }
            if client == .claudeCode, let cli = claudeCLI {
                let cmd = [cli, "mcp", "remove", "--scope", "user", name]
                if dryRun { return Change(client: client, changed: true, message: "would run: " + cmd.map(RigText.shellQuote).joined(separator: " ")) }
                try runChecked(cmd)
                return Change(client: client, changed: true, message: "removed with the claude CLI")
            }
            let file = configFile(client)
            if dryRun { return Change(client: client, changed: true, message: "would remove \(name) from \(file.path)") }
            try edit(file) { servers in servers.removeValue(forKey: name) }
            return Change(client: client, changed: true, message: "removed from \(file.path)")
        }
    }

    func runChecked(_ cmd: [String]) throws {
        let r = try run(cmd, nil, 60)
        if !r.ok { throw ShellError.failed(cmd, r) }
    }

    // MARK: Atomic JSON edit

    func readJSON(_ file: URL) throws -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KliegError("\(file.path) isn't a JSON object, so Klieg left it alone.")
        }
        return root
    }

    /// Reads `file` (or starts from {}), changes only its mcpServers, writes a temp file in the same
    /// folder with the same permissions, then renames it over the original.
    func edit(_ link: URL, _ change: (inout [String: Any]) -> Void) throws {
        let fm = FileManager.default
        // Edit the real file when the config is a symlink (say, into a dotfiles repo), so the link stays.
        let file = link.resolvingSymlinksInPath()
        var root = try readJSON(file) ?? [:]
        if let existing = root["mcpServers"], !(existing is [String: Any]) {
            throw KliegError("mcpServers in \(file.path) isn't a JSON object, so Klieg left the file alone.")
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        change(&servers)
        root["mcpServers"] = servers

        let dir = file.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let tmp = dir.appendingPathComponent(".\(file.lastPathComponent).klieg-\(UUID().uuidString).tmp")
        // Same permissions as the original (~/.claude.json is often private); new files are private.
        let mode = (try? fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.int16Value ?? 0o600
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: mode]) else {
            throw KliegError("Couldn't write \(tmp.path).")
        }
        if rename(tmp.path, file.path) != 0 {
            let err = String(cString: strerror(errno))
            try? fm.removeItem(at: tmp)
            throw KliegError("Couldn't replace \(file.path): \(err)")
        }
    }
}
