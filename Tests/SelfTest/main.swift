// Self-test for KliegKit and KliegServer. Runs with only the Command Line Tools (no XCTest needed),
// on macOS and Linux:
//   swift run klieg-selftest
import Foundation
import KliegKit
import KliegServer

var passed = 0
var failed: [String] = []
var current = ""

func check(_ ok: @autoclosure () throws -> Bool, _ what: String, line: Int = #line) {
    do {
        if try ok() { passed += 1 } else { failed.append("\(current): \(what) (line \(line))") }
    } catch {
        failed.append("\(current): \(what) threw \(error) (line \(line))")
    }
}

func section(_ name: String, _ body: () throws -> Void) {
    current = name
    do { try body() } catch { failed.append("\(name): threw \(error)") }
}

section("models") {
    check(AgentStatus.blocked.needsPerson, "blocked needs a person")
    check(!AgentStatus.working.needsPerson, "working does not")
    let a = Agent(id: "herdr:herdr/w2:p1", source: .herdr, name: "mypy", kind: "claude", status: .blocked)
    let s = Snapshot(agents: [a])
    check(s.needingPerson.count == 1, "snapshot lists agents needing a person")
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(Snapshot.self, from: data)
    check(back.agents.first?.name == "mypy", "snapshot round-trips through JSON")
}

section("shell") {
    let r = try Shell.run(["echo", "hello"])
    check(r.ok && r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello", "runs a command")
    check((try? Shell.run(["definitely-not-a-real-tool-klieg"])) == nil, "missing tool throws")
    let piped = try Shell.run(["cat"], stdin: "abc")
    check(piped.stdout == "abc", "passes stdin")
    // A child that exits without reading a long stdin used to kill the process with SIGPIPE.
    let gone = try Shell.run(["true"], stdin: String(repeating: "x", count: 1 << 20))
    check(gone.ok, "stdin the child never reads is dropped, not fatal")
}

section("config") {
    let c = KliegConfig()
    check(c.herdrSession == "work", "default herdr session")
    check(c.openrigHost == nil, "OpenRig defaults to this computer, not someone's homelab")
    check(!c.readOnly, "actions allowed by default")
}

// Milestone checks live in their own files so the two agent teams never edit the same file.
section("herdr (M1)") { herdrTests() }
section("openrig (M2)") { openrigTests() }
section("collector (M3b)") { collectorTests() }
section("mcp install (M4)") { mcpInstallTests() }
section("spaces, branches, screen feed") { spacesTests() }

print("klieg-selftest: \(passed) passed, \(failed.count) failed")
for f in failed { print("  ✗ \(f)") }
exit(failed.isEmpty ? 0 : 1)
