import Foundation
import KliegKit

// M4: checks for `klieg mcp install|uninstall|status` (MCPInstaller). Everything happens in a temp HOME
// with every path passed in, and a fake `claude` CLI. The real ~/.claude.json is never read or written.

private func readJSON(_ url: URL) -> [String: Any]? {
    (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

private func writeJSON(_ url: URL, _ o: [String: Any]) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]).write(to: url)
}

/// A fake `claude` CLI: records calls and applies `mcp add/remove --scope user` to the temp ~/.claude.json,
/// the way the real one does.
private final class FakeClaude: @unchecked Sendable {
    let file: URL
    var calls: [[String]] = []
    init(file: URL) { self.file = file }

    var runner: CommandRunner {
        { [self] args, _, _ in
            calls.append(args)
            var root = readJSON(file) ?? [:]
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            if args.count > 5, args[1...4] == ["mcp", "add", "--scope", "user"], let dash = args.firstIndex(of: "--") {
                var env: [String: String] = [:]
                var i = 6
                while i < dash { if args[i] == "-e" { let kv = args[i + 1].split(separator: "=", maxSplits: 1); env[String(kv[0])] = String(kv[1]); i += 2 } else { i += 1 } }
                servers[args[5]] = ["type": "stdio", "command": args[dash + 1], "args": Array(args[(dash + 2)...]), "env": env]
            } else if args.count == 6, args[1...4] == ["mcp", "remove", "--scope", "user"] {
                guard servers.removeValue(forKey: args[5]) != nil else {
                    return CommandResult(status: 1, stdout: "", stderr: "No user-scoped MCP server found with name: \(args[5])")
                }
            } else {
                return CommandResult(status: 1, stdout: "", stderr: "unexpected: \(args)")
            }
            root["mcpServers"] = servers
            writeJSON(file, root)
            return CommandResult(status: 0, stdout: "ok", stderr: "")
        }
    }
}

func mcpInstallTests() {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("klieg-mcp-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tmp) }
    func freshHome(_ name: String) -> URL {
        let h = tmp.appendingPathComponent(name)
        try? fm.createDirectory(at: h, withIntermediateDirectories: true)
        return h
    }
    let noCommands: CommandRunner = { args, _, _ in CommandResult(status: 1, stdout: "", stderr: "no commands expected: \(args)") }
    let bin = "/opt/klieg/bin/klieg"
    let plain = MCPServerEntry.klieg(binary: bin, readOnly: false)
    let ro = MCPServerEntry.klieg(binary: bin, readOnly: true)

    check(plain.command == bin && plain.args == ["mcp"] && plain.env.isEmpty, "entry is <binary> mcp")
    check(ro.env == ["KLIEG_READ_ONLY": "1"], "read-only adds KLIEG_READ_ONLY=1")
    check(MCPInstaller.currentBinary().hasPrefix("/"), "the running binary's path is absolute")

    // --- Claude Code without the claude CLI: edit ~/.claude.json
    let home = freshHome("edit")
    let cc = home.appendingPathComponent(".claude.json")
    check(cc.path.hasPrefix(tmp.path), "tests use a temp HOME")
    let original: [String: Any] = [
        "numStartups": 42, "autoUpdates": false, "hasCompletedOnboarding": true, "tipsHistory": ["a": 1, "b": 2.5],
        "projects": ["/home/x/src/app": ["allowedTools": [], "mcpServers": ["proj": ["command": "p"]]]],
        "theme": "dark ✨", "nothing": NSNull(),
        "mcpServers": ["other": ["type": "stdio", "command": "/usr/bin/other", "args": ["serve"], "env": [:]]],
    ]
    writeJSON(cc, original)
    _ = chmod(cc.path, 0o600)
    let parsedBefore = readJSON(cc) ?? [:]
    var inst = MCPInstaller(home: home, claudeCodeConfig: cc, desktopConfig: home.appendingPathComponent("desktop.json"),
                            claudeCLI: .some(nil), isMacOS: false, runner: noCommands)
    check(inst.status(.claudeCode).present && inst.status(.claudeCode).entry == nil, "status: Claude Code present, not registered")
    check((try? inst.clients(nil)) == [.claudeCode], "default clients: only those present (no Desktop on Linux)")

    let changes = (try? inst.install(plain)) ?? []
    check(changes.count == 1 && changes[0].changed, "install registers")
    let after = readJSON(cc) ?? [:]
    let servers = after["mcpServers"] as? [String: Any] ?? [:]
    let k = servers["klieg"] as? [String: Any] ?? [:]
    check(k["command"] as? String == bin && k["args"] as? [String] == ["mcp"] && k["type"] as? String == "stdio", "klieg entry written like Claude Code's own")
    check(servers["other"] != nil, "other MCP servers are kept")
    var rest = after; rest["mcpServers"] = nil
    // Compare as sorted-key JSON text: NSDictionary.isEqual mis-compares parsed booleans on Linux.
    var origRest = parsedBefore; origRest["mcpServers"] = nil
    func canonical(_ o: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) }
    check(canonical(rest) != nil && canonical(rest) == canonical(origRest), "every other key is untouched")
    let text = (try? String(contentsOf: cc, encoding: .utf8)) ?? ""
    check(text.contains("\"autoUpdates\" : false") && text.contains("\"hasCompletedOnboarding\" : true"), "booleans stay booleans")
    check(text.contains("dark ✨") && text.contains("\"nothing\" : null"), "unicode and null survive")
    let mode = (try? fm.attributesOfItem(atPath: cc.path)[.posixPermissions] as? NSNumber)?.intValue
    check(mode == 0o600, "file permissions are kept")
    check((try? fm.contentsOfDirectory(atPath: home.path))?.contains { $0.hasSuffix(".tmp") } == false, "no temp file left behind")
    check(inst.status(.claudeCode).entry == plain, "status reads the entry back")

    check((try? inst.install(plain))?.first?.changed == false, "installing again changes nothing")
    check((try? inst.install(ro))?.first?.message.contains("update") == true, "read-only install updates the entry")
    check(inst.status(.claudeCode).entry?.env == ["KLIEG_READ_ONLY": "1"], "status shows the env")

    let before = try? Data(contentsOf: cc)
    let dry = (try? inst.install(plain, dryRun: true)) ?? []
    check(dry.first?.message.hasPrefix("would") == true && (try? Data(contentsOf: cc)) == before, "dry-run says what it would do and writes nothing")
    check((try? inst.uninstall(dryRun: true))?.first?.changed == true && (try? Data(contentsOf: cc)) == before, "dry-run uninstall writes nothing")

    check((try? inst.uninstall())?.first?.changed == true, "uninstall removes")
    let gone = readJSON(cc)?["mcpServers"] as? [String: Any] ?? [:]
    check(gone["klieg"] == nil && gone["other"] != nil, "uninstall removes only klieg")
    check(((readJSON(cc)?["projects"] as? [String: Any])?["/home/x/src/app"] as? [String: Any])?["mcpServers"] != nil, "project-scope servers untouched")
    check((try? inst.uninstall())?.first?.changed == false, "uninstalling again changes nothing")

    // Broken or odd files are left alone.
    try? Data("{ not json".utf8).write(to: cc)
    check((try? inst.install(plain)) == nil && (try? String(contentsOf: cc, encoding: .utf8)) == "{ not json", "invalid JSON: refused, file untouched")
    try? Data(#"{"mcpServers": []}"#.utf8).write(to: cc)
    check((try? inst.install(plain)) == nil, "mcpServers that isn't an object: refused")

    // Missing file, asked for explicitly: created, private.
    try? fm.removeItem(at: cc)
    check((try? inst.install(plain, clients: [.claudeCode]))?.first?.changed == true && readJSON(cc) != nil, "missing ~/.claude.json is created when asked")
    check((try? fm.attributesOfItem(atPath: cc.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "a new config file is private")

    // A symlinked config stays a symlink; its target is edited.
    let dotfiles = home.appendingPathComponent("dotfiles/claude.json")
    writeJSON(dotfiles, ["keep": 1])
    try? fm.removeItem(at: cc)
    try? fm.createSymbolicLink(at: cc, withDestinationURL: dotfiles)
    _ = try? inst.install(plain)
    check((try? fm.destinationOfSymbolicLink(atPath: cc.path)) != nil, "symlinked config stays a symlink")
    check(readJSON(dotfiles)?["keep"] as? Int == 1 && (readJSON(dotfiles)?["mcpServers"] as? [String: Any])?["klieg"] != nil, "and its target gets the entry")

    // Nothing present: tell the person to pick.
    let empty = MCPInstaller(home: freshHome("empty"), claudeCodeConfig: tmp.appendingPathComponent("empty/.claude.json"),
                             desktopConfig: tmp.appendingPathComponent("empty/desktop.json"), claudeCLI: .some(nil), isMacOS: false, runner: noCommands)
    check((try? empty.clients(nil)) == nil, "no clients found: an error, not a silent no-op")

    // --- Claude Code with the claude CLI
    let home2 = freshHome("cli")
    let cc2 = home2.appendingPathComponent(".claude.json")
    writeJSON(cc2, ["numStartups": 1])
    let fake = FakeClaude(file: cc2)
    inst = MCPInstaller(home: home2, claudeCodeConfig: cc2, desktopConfig: home2.appendingPathComponent("d.json"),
                        claudeCLI: "/fake/bin/claude", isMacOS: false, runner: fake.runner)
    _ = try? inst.install(plain, dryRun: true)
    check(fake.calls.isEmpty, "CLI dry-run runs nothing")
    _ = try? inst.install(ro)
    check(fake.calls.last == ["/fake/bin/claude", "mcp", "add", "--scope", "user", "klieg", "-e", "KLIEG_READ_ONLY=1", "--", bin, "mcp"],
          "uses claude mcp add --scope user, -e after the name")
    check(inst.status(.claudeCode).entry == ro, "status sees what the CLI registered")
    _ = try? inst.install(ro)
    check(fake.calls.count == 1, "already registered: the CLI isn't called again")
    _ = try? inst.install(plain)
    check(fake.calls.suffix(2).map { $0[2] } == ["remove", "add"] && fake.calls.last?.contains("-e") == false, "changing the entry removes then adds")
    _ = try? inst.uninstall()
    check(fake.calls.last == ["/fake/bin/claude", "mcp", "remove", "--scope", "user", "klieg"], "uninstall uses claude mcp remove")
    check(readJSON(cc2)?["numStartups"] as? Int == 1, "the CLI path leaves other keys to Claude Code")
    let failing = MCPInstaller(home: home2, claudeCodeConfig: cc2, desktopConfig: home2.appendingPathComponent("d.json"),
                               claudeCLI: "/fake/bin/claude", isMacOS: false,
                               runner: { _, _, _ in CommandResult(status: 1, stdout: "", stderr: "boom") })
    check((try? failing.install(plain)) == nil, "a failing claude CLI is reported")

    // --- Claude Desktop
    let home3 = freshHome("desktop")
    let desk = home3.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    let linux = MCPInstaller(home: home3, claudeCodeConfig: home3.appendingPathComponent(".claude.json"), desktopConfig: desk,
                             claudeCLI: .some(nil), isMacOS: false, runner: noCommands)
    check(linux.status(.claudeDesktop).unavailable != nil, "Desktop is unavailable off macOS")
    check((try? linux.install(plain, clients: [.claudeDesktop])) == nil && !fm.fileExists(atPath: desk.path), "asking for Desktop off macOS is refused")

    let mac = MCPInstaller(home: home3, claudeCodeConfig: home3.appendingPathComponent(".claude.json"), desktopConfig: desk,
                           claudeCLI: .some(nil), isMacOS: true, runner: noCommands)
    check((try? mac.install(ro, clients: [.claudeDesktop]))?.first?.message.contains("Restart Claude Desktop") == true, "Desktop install asks for a restart")
    let d = readJSON(desk)?["mcpServers"] as? [String: Any]
    let dk = d?["klieg"] as? [String: Any]
    check(dk?["command"] as? String == bin && dk?["env"] as? [String: String] == ["KLIEG_READ_ONLY": "1"] && dk?["type"] == nil,
          "Desktop config created with command, args and env")
    check(mac.status(.claudeDesktop).present, "Desktop counts as present once its folder exists")
    writeJSON(desk, ["globalShortcut": "Cmd+Space", "mcpServers": ["afm": ["command": "/x/afm", "args": ["mcp"]]]])
    _ = try? mac.install(plain, clients: [.claudeDesktop])
    _ = try? mac.uninstall(clients: [.claudeDesktop])
    let dAfter = readJSON(desk) ?? [:]
    check(dAfter["globalShortcut"] as? String == "Cmd+Space" && (dAfter["mcpServers"] as? [String: Any])?["afm"] != nil
          && (dAfter["mcpServers"] as? [String: Any])?["klieg"] == nil, "Desktop: install then uninstall leaves other settings and servers")
}
