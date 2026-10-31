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

/// Everything Klieg can see right now. M1 reads herdr; M2 adds OpenRig and GitHub here.
func takeSnapshot(_ config: KliegConfig) -> Snapshot {
    HerdrClient.fromConfig(config).snapshot()
}

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

func printStatus(_ s: Snapshot) {
    for (source, err) in s.errors.sorted(by: { $0.key < $1.key }) { print("! \(source): \(err)") }
    if s.agents.isEmpty { print("No agents."); return }
    let rows = s.agents.sorted { ($0.group ?? "", $0.name) < ($1.group ?? "", $1.name) }.map { a in
        [a.name, a.kind, a.status.rawValue + (a.attentionReason.map { " (\($0))" } ?? ""), a.group ?? "-", a.id]
    }
    let header = ["NAME", "KIND", "STATUS", "GROUP", "ID"]
    let widths = (0..<header.count).map { i in ([header] + rows).map { $0[i].count }.max() ?? 0 }
    for r in [header] + rows {
        print(r.enumerated().map { i, v in i == r.count - 1 ? v : pad(v, widths[i]) }.joined(separator: "  "))
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

switch args.first {
case "version", "--version", "-v":
    print("\(KliegVersion.name) \(KliegVersion.string)")
case "config":
    printJSON(KliegConfig.load())
case "mcp":
    exit(KliegServer.runStdio())
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
