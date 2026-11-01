import Foundation
import KliegKit
import KliegServer

// klieg: the command-line face of Klieg. Owned by the herdr agent: see ROADMAP.md, milestone M1.
let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    klieg \(KliegVersion.string): watch and steer herdr and OpenRig agents

    Usage:
      klieg version                      Print the version
      klieg config                       Print the effective configuration (JSON)
      klieg mcp                          Run the MCP server on stdio
      klieg mcp install [--read-only] [--client claude-code|claude-desktop|all] [--dry-run]
                                         Register Klieg's MCP server with Claude Code / Claude Desktop
      klieg mcp uninstall [--client …] [--dry-run]   Remove that registration
      klieg mcp status                   Where Klieg is registered, with which command
      klieg status [--json]              Agents, their state, and who needs you
      klieg timeline [--watch] [--json]  What changed since last time (--watch keeps going)
      klieg herdr prompt <agent> <text>  Send a prompt to a herdr agent
      klieg herdr read <agent> [lines]   Print a herdr agent's recent terminal text

    <agent> is a Klieg id (herdr:<machine>/<pane>), a herdr pane id (w1:p1) or an agent name.
    """)
    exit(0)
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("klieg: \(message)\n".utf8))
    exit(code)
}

func printJSON<T: Encodable>(_ value: T) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    do { print(String(decoding: try enc.encode(value), as: UTF8.self)) } catch { fail("\(error)") }
}

/// Everything Klieg can see right now: herdr agents, OpenRig seats and queue, and open PRs.
func takeSnapshot(_ config: KliegConfig) -> Snapshot {
    Collector(config: config).snapshot()
}

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

/// Prints rows as aligned columns; the last column isn't padded.
func printTable(_ header: [String], _ rows: [[String]]) {
    let widths = (0..<header.count).map { i in ([header] + rows).map { $0[i].count }.max() ?? 0 }
    for r in [header] + rows {
        print(r.enumerated().map { i, v in i == r.count - 1 ? v : pad(v, widths[i]) }.joined(separator: "  "))
    }
}

func printStatus(_ s: Snapshot) {
    for (source, err) in s.errors.sorted(by: { $0.key < $1.key }) { print("! couldn't read \(source): \(err)") }
    if s.agents.isEmpty { print("No agents.") } else {
        let rank: [Source: Int] = [.herdr: 0, .openrig: 1, .github: 2]
        let rows = s.agents.sorted { (rank[$0.source] ?? 9, $0.group ?? "", $0.name) < (rank[$1.source] ?? 9, $1.group ?? "", $1.name) }.map { a in
            [a.name, a.source.rawValue, a.kind, a.status.rawValue + (a.attentionReason.map { " (\($0))" } ?? ""), a.group ?? "-", a.id]
        }
        printTable(["NAME", "SOURCE", "KIND", "STATUS", "GROUP", "ID"], rows)
    }
    if !s.queue.isEmpty {
        print("\nQueue (\(s.queue.count)):")
        printTable(["ID", "STATE", "FROM", "TO", "SUMMARY"],
                   s.queue.map { [$0.id, $0.state, $0.source, $0.destination, $0.summary ?? ""] })
    }
    if !s.pullRequests.isEmpty {
        print("\nPull requests (\(s.pullRequests.count)):")
        printTable(["PR", "CHECKS", "SIGNED", "TITLE"],
                   s.pullRequests.map { [$0.id, $0.checks ?? "none", $0.signed.map { $0 ? "yes" : "no" } ?? "?", $0.title] })
    }
    let needy = s.needingPerson
    print("")
    if needy.isEmpty { print("Nobody needs you.") } else {
        print("Needs you (\(needy.count)):")
        for a in needy {
            print("  \(a.name): \(a.attentionReason ?? "waiting")" + (a.attachCommand.map { "  → \($0.joined(separator: " "))" } ?? ""))
        }
    }
}

let timeFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()

func printEvents(_ events: [TimelineEvent], json: Bool) {
    if json {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for e in events { if let d = try? enc.encode(e) { print(String(decoding: d, as: UTF8.self)) } }
    } else {
        for e in events { print("\(timeFormat.string(from: e.date))  \(e.text)") }
    }
    fflush(stdout)
}

func timeline(_ rest: [String]) {
    let config = KliegConfig.load()
    let watch = rest.contains("--watch") || rest.contains("-w")
    let json = rest.contains("--json")
    let store = TimelineStore()
    var snap = takeSnapshot(config)
    do {
        let fresh = try store.record(snap)
        // Show recent history, which already ends with anything new.
        let history = store.events()
        printEvents(Array((history.isEmpty ? fresh : history).suffix(watch ? 10 : 50)), json: json)
        if history.isEmpty && !watch && !json { print("No activity yet. The timeline fills in each time klieg looks again.") }
    } catch { fail("could not save the timeline: \(error)") }
    guard watch else { return }
    for (source, err) in snap.errors { FileHandle.standardError.write(Data("klieg: \(source): \(err)\n".utf8)) }
    while true {
        Thread.sleep(forTimeInterval: max(1, config.refreshSeconds))
        let next = takeSnapshot(config)
        let fresh = (try? store.record(next)) ?? Timeline.diff(from: snap, to: next)
        printEvents(fresh, json: json)
        snap = Timeline.carryOver(from: snap, to: next)
    }
}

func herdrCommand(_ rest: [String]) {
    let client = HerdrClient.fromConfig()
    do {
        switch rest.first {
        case "prompt":
            guard rest.count >= 3 else { fail("usage: klieg herdr prompt <agent> <text>", code: 2) }
            try client.prompt(rest[1], text: rest[2...].joined(separator: " "))
            print("Sent.")
        case "read":
            guard rest.count >= 2 else { fail("usage: klieg herdr read <agent> [lines]", code: 2) }
            let text = try client.read(rest[1], lines: rest.count > 2 ? Int(rest[2]) : 80)
            print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
        default:
            fail("usage: klieg herdr prompt <agent> <text> | klieg herdr read <agent> [lines]", code: 2)
        }
    } catch { fail("\(error)") }
}

func mcpCommand(_ rest: [String]) {
    let sub = rest[0]
    var readOnly = false, dryRun = false
    var clients: [MCPClient]? = nil
    var i = 1
    while i < rest.count {
        switch rest[i] {
        case "--read-only" where sub == "install": readOnly = true
        case "--dry-run" where sub != "status": dryRun = true
        case "--client" where sub != "status":
            guard i + 1 < rest.count else { fail("--client needs a value: claude-code, claude-desktop or all", code: 2) }
            i += 1
            if rest[i] == "all" { clients = nil }
            else if let c = MCPClient(rawValue: rest[i]) { clients = [c] }
            else { fail("unknown client '\(rest[i])' (use claude-code, claude-desktop or all)", code: 2) }
        default: fail("unknown option '\(rest[i])' for klieg mcp \(sub) (try: klieg help)", code: 2)
        }
        i += 1
    }
    let installer = MCPInstaller()
    do {
        switch sub {
        case "status":
            for c in MCPClient.allCases {
                let st = installer.status(c)
                let state: String
                if let why = st.unavailable { state = why }
                else if let e = st.entry {
                    state = "registered: \(e.command) \(e.args.joined(separator: " "))"
                        + (e.env.isEmpty ? "" : "  env: " + e.env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                } else { state = st.present ? "not registered" : "not found here" }
                print("\(pad(c.title + ":", 16))\(state)")
                if st.unavailable == nil && (st.present || st.entry != nil) { print("\(pad("", 16))\(st.configFile.path)") }
            }
        case "install":
            let binary = MCPInstaller.currentBinary()
            if binary.contains("/.build/") {
                FileHandle.standardError.write(Data("klieg: note: registering a build-folder binary (\(binary)); a rebuild or clean will move it.\n".utf8))
            }
            for ch in try installer.install(.klieg(binary: binary, readOnly: readOnly), clients: clients, dryRun: dryRun) {
                print("\(ch.client.title): \(ch.message)")
            }
        case "uninstall":
            for ch in try installer.uninstall(clients: clients, dryRun: dryRun) { print("\(ch.client.title): \(ch.message)") }
        default:
            fail("unknown command 'klieg mcp \(sub)' (use install, uninstall or status)", code: 2)
        }
    } catch { fail("\(error)") }
}

switch args.first {
case "version", "--version", "-v":
    print("\(KliegVersion.name) \(KliegVersion.string)")
case "config":
    printJSON(KliegConfig.load())
case "mcp":
    if args.count == 1 { exit(KliegServer.runStdio()) }
    mcpCommand(Array(args.dropFirst()))
case "status":
    let s = takeSnapshot(KliegConfig.load())
    if args.contains("--json") { printJSON(s) } else { printStatus(s) }
    exit(s.errors.isEmpty ? 0 : 1)
case "timeline":
    timeline(Array(args.dropFirst()))
case "herdr":
    herdrCommand(Array(args.dropFirst()))
case nil, "help", "--help", "-h":
    usage()
default:
    fail("unknown command '\(args[0])' (try: klieg help)", code: 2)
}
