import Foundation
import KliegKit
import KliegServer

// klieg: the command-line face of Klieg. Owned by the herdr agent: see ROADMAP.md, milestone M1.
let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    klieg \(KliegVersion.string): watch and steer herdr and OpenRig agents

    Usage:
      klieg version            Print the version
      klieg config             Print the effective configuration (JSON)
      klieg mcp                Run the MCP server on stdio
      klieg status             (M1) Agents, their state, and who needs you
      klieg timeline           (M1) Recent activity
    """)
    exit(0)
}

switch args.first {
case "version", "--version", "-v":
    print("\(KliegVersion.name) \(KliegVersion.string)")
case "config":
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try enc.encode(KliegConfig.load()), as: UTF8.self))
case "mcp":
    exit(KliegServer.runStdio())
case nil, "help", "--help", "-h":
    usage()
default:
    FileHandle.standardError.write(Data("klieg: unknown command '\(args[0])' (try: klieg help)\n".utf8))
    exit(2)
}
