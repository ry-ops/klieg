import Foundation
import KliegKit
import KliegServer

// M3b: checks for Collector (herdr + OpenRig + GitHub in one snapshot) and for herdr agents behind the
// MCP tools. Uses the recorded herdr and OpenRig fixtures and FakeRunner; nothing live is called.

private func herdrFixture(_ name: String) -> String {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/herdr")
    return (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
}

/// A fake world: herdr (the mixed session), a rig host, and GitHub. herdr rules go first, because
/// FakeRunner's first match wins and rig rules such as "send" would also match "send-keys".
private func world(herdrSnapshot: String = "api-snapshot-mixed.json", herdrUp: Bool = true, rigUp: Bool = true,
                   brokenRepo: String? = nil) -> FakeRunner {
    let f = FakeRunner()
    f.on("herdr", "machine list", reply: "[]")
    if herdrUp {
        f.on("herdr", "api snapshot", reply: herdrFixture(herdrSnapshot))
        f.on("herdr", "agent read w4:p1", reply: herdrFixture("trust-prompt.txt"))
        f.on("herdr", "agent read", reply: herdrFixture("idle-prompt.txt"))
        f.on("herdr", "agent get", reply: herdrFixture("agent-get.json"))
        f.on("herdr", "workspace create", reply: herdrFixture("workspace-create.json"))
        f.on("herdr", reply: #"{"id":"cli","result":{}}"#)
    } else {
        f.on("herdr", reply: "", status: 1)
    }
    if rigUp {
        for r in recordedRig().rules { f.rules.append(r) }
    }
    if let brokenRepo { f.on("gh", "pr list", "--repo \(brokenRepo)", reply: "", status: 1) }
    f.on("gh", "pr list", reply: openrigFixture("gh-pr-list.json"))
    f.on("gh", "api", reply: openrigFixture("gh-commit-verification.json"))
    return f
}

private let repo = "ry-ops/unifi-mcp-server"
private func config(repos: [String] = [repo], readOnly: Bool = false) -> KliegConfig {
    KliegConfig(herdrMachine: "herdr", herdrSession: "work", openrigHost: nil, repos: repos, readOnly: readOnly)
}

func collectorTests() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // Everything answers.
    let f = world()
    let c = Collector(config: config(), runner: f.runner)
    check(f.calls.isEmpty, "making a Collector runs nothing")
    let s = c.snapshot(now: t0)
    let herdrAgents = s.agents.filter { $0.source == .herdr }, rigAgents = s.agents.filter { $0.source == .openrig }
    check(s.errors.isEmpty, "no errors when every source answers: \(s.errors)")
    check(herdrAgents.count == 5 && rigAgents.count == 4, "herdr agents and OpenRig seats together")
    check(s.agents.first?.source == .herdr && s.agents.last?.source == .openrig, "herdr first, then OpenRig")
    check(herdrAgents.contains { $0.id == "herdr:herdr/w4:p1" && $0.attentionReason == "trust_prompt" }, "herdr trust prompt still detected")
    check(rigAgents.contains { $0.attentionReason == "billing" }, "OpenRig billing prompt still labeled")
    check(!s.queue.isEmpty, "queue items come from OpenRig")
    check(s.pullRequests.map(\.number) == [56, 57, 58, 59], "open PRs for the configured repo")
    check(s.pullRequests.allSatisfy { $0.signed == true }, "PR signatures are checked")
    check(s.taken == t0, "snapshot time is the collection time")
    check(s.needingPerson.count >= 3, "needs-you covers both sources")

    // Each source failing on its own leaves the others in place.
    let noHerdr = Collector(config: config(), runner: world(herdrUp: false).runner).snapshot(now: t0)
    check(noHerdr.errors.keys.sorted() == ["herdr"], "herdr down: only errors[\"herdr\"]")
    check(noHerdr.agents.count == 4 && noHerdr.pullRequests.count == 4 && !noHerdr.queue.isEmpty, "herdr down: seats, queue and PRs still there")

    let noRig = Collector(config: config(), runner: world(rigUp: false).runner).snapshot(now: t0)
    check(noRig.errors.keys.sorted() == ["openrig"], "rig down: only errors[\"openrig\"]")
    check(noRig.errors["openrig"]?.contains("seats") == true && noRig.errors["openrig"]?.contains("queue") == true, "the openrig error says which parts failed")
    check(noRig.agents.count == 5 && noRig.queue.isEmpty && noRig.pullRequests.count == 4, "rig down: herdr agents and PRs still there")

    let twoRepos = config(repos: ["ry-ops/broken", repo])
    let oneRepo = Collector(config: twoRepos, runner: world(brokenRepo: "ry-ops/broken").runner).snapshot(now: t0)
    check(oneRepo.errors.keys.sorted() == ["github"] && oneRepo.errors["github"]?.contains("ry-ops/broken") == true,
          "one repo failing: errors[\"github\"] names it")
    check(oneRepo.pullRequests.count == 4 && oneRepo.agents.count == 9, "one repo failing: the other repo's PRs and every agent still there")

    let none = Collector(config: config(), runner: world(herdrUp: false, rigUp: false, brokenRepo: repo).runner).snapshot(now: t0)
    check(none.errors.keys.sorted() == ["github", "herdr", "openrig"], "everything down: one error per source")

    let quiet = world()
    _ = Collector(config: config(), runner: quiet.runner, includePullRequests: false).snapshot(now: t0)
    check(!quiet.ran("gh"), "without pull requests, gh isn't called")
    let noRepos = world()
    _ = Collector(config: config(repos: []), runner: noRepos.runner).snapshot(now: t0)
    check(!noRepos.ran("gh"), "no repos configured, gh isn't called")

    // An outage and recovery give no timeline noise, for agents, queue items or PRs.
    let t1 = t0.addingTimeInterval(5), t2 = t1.addingTimeInterval(5)
    let outage = Collector(config: config(), runner: world(herdrUp: false, rigUp: false, brokenRepo: repo).runner).snapshot(now: t1)
    check(Timeline.diff(from: s, to: outage).isEmpty, "outage: no stopped events")
    let carried = Timeline.carryOver(from: s, to: outage)
    check(carried.agents.count == 9 && carried.queue.count == s.queue.count && carried.pullRequests.count == 4,
          "outage: carryOver keeps agents, queue items and PRs")
    let back = Collector(config: config(), runner: world().runner).snapshot(now: t2)
    check(Timeline.diff(from: carried, to: back).isEmpty, "recovery: no appeared, queued or opened events")

    mcpHerdrTests()
}

private func mcpHerdrTests() {
    let f = world(herdrSnapshot: "api-snapshot.json")
    let backend = LiveBackend(config: config(), runner: f.runner)
    check(f.calls.isEmpty, "starting the MCP backend runs nothing")
    let server = MCPServer(backend: backend, readOnly: false)
    func call(_ id: Int, _ name: String, _ args: [String: Any]) -> [String: Any] {
        rpc(server, id, "tools/call", ["name": name, "arguments": args])
    }

    // klieg_status covers herdr too, and doesn't fetch PRs (klieg_pull_requests does).
    let status = call(1, "klieg_status", [:])
    let agents = ((status["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["agents"] as? [[String: Any]] ?? []
    check(agents.count == 5 && agents.contains { $0["id"] as? String == "herdr:herdr/w3:p1" }, "klieg_status lists the herdr agent with the seats")
    check(!f.ran("gh"), "klieg_status leaves PRs to their own tool")

    // The herdr session changes; the timeline sees it.
    f.rules.removeAll { $0.when == ["herdr", "api snapshot"] }
    f.rules.insert((["herdr", "api snapshot"], herdrFixture("api-snapshot-mixed.json"), 0), at: 0)
    let timeline = toolText(call(2, "klieg_timeline", ["limit": 50]))
    check(timeline.contains("mypy (claude) appeared in mypy"), "klieg_timeline has herdr agent events")
    check(timeline.contains("trust the folder"), "klieg_timeline says when a herdr agent needs you")

    // Read: at least the whole visible pane.
    let read = call(3, "klieg_read_agent", ["agent": "herdr:herdr/w4:p1", "lines": 5])
    check(toolText(read).contains("Yes, I trust this folder"), "klieg_read_agent reads a herdr pane")
    check(f.ran("herdr", "agent read w4:p1 --source visible"), "reads the visible pane")
    _ = call(4, "klieg_read_agent", ["agent": "herdr:herdr/w3:p1", "lines": 200])
    check(f.ran("herdr", "agent read w3:p1 --source recent-unwrapped --lines 200"), "asking for more lines reads history too")

    // Acts.
    check(!toolFailed(call(5, "klieg_prompt_agent", ["agent": "herdr:herdr/w3:p1", "text": "run the tests"])), "klieg_prompt_agent works for herdr")
    check(f.ran("herdr", "agent prompt w3:p1 run the tests"), "prompt goes to herdr")
    check(!toolFailed(call(6, "klieg_answer_prompt", ["agent": "herdr:herdr/w4:p1", "answer": "1"])), "klieg_answer_prompt answers the trust screen")
    check(f.ran("herdr", "agent send-keys w4:p1 1"), "the answer is sent as keys")
    check(!toolFailed(call(7, "klieg_stop_agent", ["agent": "herdr:herdr/w4:p2"])) && f.ran("herdr", "pane close w4:p2"), "stop closes the agent's pane")
    _ = call(8, "klieg_stop_agent", ["agent": "herdr:herdr/m1"])
    check(f.ran("herdr", "agent get m1") && f.ran("herdr", "pane close w3:p1"), "stop by name finds the pane first")
    check(!toolFailed(call(9, "klieg_start_agent", ["name": "fixer", "kind": "codex", "pane": "w6:p1"])), "klieg_start_agent in a pane")
    check(f.ran("herdr", "agent start fixer --kind codex --pane w6:p1"), "start goes to herdr")
    let fresh = call(10, "klieg_start_agent", ["name": "scout", "kind": "claude"])
    check(f.ran("herdr", "workspace create --no-focus --label scout") && f.ran("herdr", "agent start scout --kind claude --pane w6:p1"),
          "start without a pane makes a workspace and uses its pane")
    check(toolText(fresh).contains("herdr:herdr/w6:p1"), "start says the new agent's id")
    check(toolFailed(call(11, "klieg_prompt_agent", ["agent": "herdr:elsewhere/w1:p1", "text": "x"])), "another herdr machine's id is refused")
    check(toolFailed(call(12, "klieg_queue_goal", ["destination": "herdr:herdr/w3:p1", "body": "x"])), "queue goals still refuse herdr agents")

    // The billing guard covers herdr panes too.
    let billing = world()
    billing.rules.insert((["herdr", "agent read"], "You've hit your usage limit.\n❯ 1. Buy extra usage\n  2. Wait", 0), at: 0)
    let bserver = MCPServer(backend: LiveBackend(config: config(), runner: billing.runner), readOnly: false)
    let refused = rpc(bserver, 1, "tools/call", ["name": "klieg_answer_prompt", "arguments": ["agent": "herdr:herdr/w4:p1", "answer": "1"]])
    check(toolFailed(refused) && toolText(refused).contains("billing"), "klieg_answer_prompt refuses a herdr billing prompt")
    check(!billing.ran("send-keys"), "and sends no keys")

    // Read-only: the server refuses herdr acts before anything runs, as for OpenRig.
    let ro = world()
    let roServer = MCPServer(backend: LiveBackend(config: config(readOnly: true), runner: ro.runner), readOnly: true)
    let acts: [(String, [String: Any])] = [
        ("klieg_prompt_agent", ["agent": "herdr:herdr/w3:p1", "text": "x"]),
        ("klieg_answer_prompt", ["agent": "herdr:herdr/w4:p1", "answer": "1"]),
        ("klieg_stop_agent", ["agent": "herdr:herdr/w3:p1"]),
        ("klieg_start_agent", ["name": "n", "kind": "claude", "pane": "w1:p1"]),
    ]
    for (i, (name, args)) in acts.enumerated() {
        let r = rpc(roServer, 20 + i, "tools/call", ["name": name, "arguments": args])
        check(toolFailed(r) && toolText(r).contains("read-only"), "read-only refuses \(name) for herdr")
    }
    check(ro.calls.isEmpty, "read-only runs no herdr commands")
    // And the herdr client itself refuses, if a backend is driven directly.
    let direct = world()
    let roBackend = LiveBackend(config: config(readOnly: true), runner: direct.runner)
    check((try? roBackend.prompt("herdr:herdr/w3:p1", text: "x")) == nil && !direct.ran("agent prompt"), "read-only config refuses herdr acts in the backend too")
}
