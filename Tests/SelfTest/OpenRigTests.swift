import Foundation
import KliegKit
import KliegServer

// M2 (OpenRig rig): checks for OpenRigClient, GitHubClient and the MCP server. Uses the recorded JSON in
// Fixtures/openrig (see its README) and a fake command runner: nothing here touches a live rig or GitHub.

let openrigFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/openrig")

func openrigFixture(_ name: String) -> String {
    (try? String(contentsOf: openrigFixtures.appendingPathComponent(name), encoding: .utf8)) ?? ""
}

/// Answers commands from recorded output and remembers every command it was asked to run.
/// Thread-safe, because the Collector reads its sources at the same time.
final class FakeRunner: @unchecked Sendable {
    private let lock = NSLock()
    var calls: [[String]] = []
    var stdins: [String?] = []
    /// First matching rule wins: if every word in `when` appears in the command, reply with `stdout`.
    var rules: [(when: [String], stdout: String, status: Int32)] = []

    func on(_ when: String..., reply stdout: String, status: Int32 = 0) { rules.append((when, stdout, status)) }

    var runner: CommandRunner {
        { [self] args, stdin, _ in
            lock.lock(); defer { lock.unlock() }
            calls.append(args); stdins.append(stdin)
            let line = args.joined(separator: " ")
            for r in rules where r.when.allSatisfy({ line.contains($0) }) {
                return CommandResult(status: r.status, stdout: r.stdout, stderr: r.status == 0 ? "" : "failed")
            }
            return CommandResult(status: 1, stdout: "", stderr: "no fixture for: \(line)")
        }
    }

    func ran(_ words: String...) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return calls.contains { c in let line = c.joined(separator: " "); return words.allSatisfy { line.contains($0) } }
    }
}

/// A fake rig host with every recorded fixture wired up.
func recordedRig() -> FakeRunner {
    let f = FakeRunner()
    f.on("ps", "--nodes", reply: openrigFixture("ps-nodes.json"))
    f.on("queue", "list", reply: openrigFixture("queue-list.json"))
    f.on("capture", "operator-agent@kernel", reply: openrigFixture("capture-credits.json"))
    f.on("capture", "advisor-lead@kernel", reply: openrigFixture("capture-credits.json"))
    f.on("capture", "dev-build@example-pair", reply: openrigFixture("capture-permission.json"))
    // A seat at a prompt in a pane too small for rig to be sure the prompt is shown whole.
    f.on("capture", "small-pane@example-pair",
         reply: #"{"ok":true,"content":"Do you want to proceed?\n ❯ 1. Yes","promptPane":{"width":60,"height":12,"hint":"try --readable"}}"#)
    f.on("send", reply: "Sent to target.")
    f.on("seat", "stop", reply: "Stopped.")
    f.on("queue", "create", reply: "Created qitem-20261031210000-abc")
    return f
}

/// Sends one JSON-RPC request through the server and decodes the reply.
func rpc(_ server: MCPServer, _ id: Int, _ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
    let req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    let line = String(decoding: try! JSONSerialization.data(withJSONObject: req), as: UTF8.self)
    guard let reply = server.handleLine(line),
          let o = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any] else { return [:] }
    return o
}

func toolText(_ reply: [String: Any]) -> String {
    let r = reply["result"] as? [String: Any]
    return ((r?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
}

func toolFailed(_ reply: [String: Any]) -> Bool { (reply["result"] as? [String: Any])?["isError"] as? Bool == true }

func openrigTests() {
    // Seats from the full `rig ps --nodes -A --full --json` record.
    let agents = (try? OpenRigClient.parseNodes(Data(openrigFixture("ps-nodes.json").utf8))) ?? []
    let byName = Dictionary(agents.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    check(agents.count == 4, "maps seats to agents, skipping the human's terminal seat")
    check(byName["operator-human@kernel"] == nil, "infrastructure seat is not an agent")
    let advisor = byName["advisor-lead@kernel"]
    check(advisor?.status == .blocked, "needs-input seat is blocked")
    check(advisor?.attentionReason == "permission_prompt", "attention reason comes from needsInput")
    check(advisor?.id == "openrig:advisor-lead@kernel" && advisor?.source == .openrig, "agent id and source")
    let build = byName["dev-build@klieg-pair"]
    check(build?.status == .working, "working seat")
    check(build?.model == "claude-opus-5-5", "observed model")
    check(build?.kind == "claude", "claude-code runtime is reported as claude")
    check(build?.group == "klieg-pair", "group is the rig name")
    check(build?.cwd == "/home/ubuntu/src/klieg", "cwd")
    check(build?.attachCommand == ["tmux", "attach", "-t", "dev-build@klieg-pair"], "local attach command")
    check(byName["dev-review@klieg-pair"]?.status == .idle, "idle seat")
    let exited = byName["dev-build@unifi-pair"]
    check(exited?.status == .stopped && exited?.attachCommand == nil, "exited seat is stopped with nothing to attach")

    // The compact shape (no activityState) still gives a usable answer.
    let compact = (try? OpenRigClient.parseNodes(Data(openrigFixture("ps-nodes-compact.json").utf8), host: "ubuntu@rig-host")) ?? []
    check(compact.count == 2, "reads the compact {entries:[…]} shape")
    check(compact.first?.status == .blocked && compact.first?.attentionReason == "stale_runtime_hook", "compact: needsAttention is blocked")
    check(compact.last?.model == "claude-opus-5-5", "compact: model from the observation array")
    check(compact.last?.attachCommand == ["ssh", "-t", "ubuntu@rig-host", "tmux", "attach", "-t", "dev-build@klieg-pair"], "remote attach goes over ssh -t")

    // Queue items.
    let queue = (try? OpenRigClient.parseQueue(Data(openrigFixture("queue-list.json").utf8))) ?? []
    check(queue.count == 4, "maps qitems")
    check(queue.first?.state == "in-progress" && queue.first?.source == "ryan@mac", "qitem state and source")
    check(queue.first?.summary == nil, "no summary when the row has none")
    check(queue[safe: 1]?.summary?.hasPrefix("Approved 52b1015") == true, "summary when present")
    check(queue[safe: 1]?.closureReason == "no-follow-on", "closure reason")
    check(queue.first?.created != nil, "parses fractional-second timestamps")
    let events = OpenRigClient.queueEvents(queue)
    check(events.map(\.kind) == ["claimed", "done", "handedOff", "done"], "one timeline event per qitem state")
    check(events.first?.text == "dev-build@klieg-pair is working on qitem-20261031195841-98147cee9e1fdb9a", "timeline text")

    // Captures and the billing guard.
    let credits = (try? OpenRigClient.parseCapture(Data(openrigFixture("capture-credits.json").utf8))) ?? ""
    check(credits.contains("now uses usage credits"), "reads captured pane text")
    check(PromptGuard.billingPhrase(in: credits) != nil, "spots the usage-credits prompt")
    let permission = (try? OpenRigClient.parseCapture(Data(openrigFixture("capture-permission.json").utf8))) ?? ""
    check(PromptGuard.billingPhrase(in: permission) == nil, "a permission prompt is not a billing prompt")
    check(PromptGuard.billingPhrase(in: "You've hit your usage limit.\n /extra-usage to keep going") != nil, "spots usage-limit prompts")
    check((try? OpenRigClient.parseScreen(Data(openrigFixture("capture-permission.json").utf8)))?.promptCutOff == false, "a normal pane is not cut off")
    check((try? OpenRigClient.parseCapture(Data(#"{"ok":false,"error":"no such session"}"#.utf8))) == nil, "failed capture throws")

    // Commands, locally and over ssh.
    let local = OpenRigClient(host: nil)
    check(local.command(["ps", "--nodes"]) == ["rig", "ps", "--nodes"], "local runs rig directly")
    let remote = OpenRigClient(host: "ubuntu@100.67.70.121")
    check(remote.command(["send", "dev@r", "it's done; $HOME"]) == ["ssh", "-o", "BatchMode=yes", "ubuntu@100.67.70.121", #"rig send dev@r 'it'\''s done; $HOME'"#],
          "remote quotes every argument for the far shell")

    // Actions run the right rig commands.
    let fake = recordedRig()
    let client = OpenRigClient(host: nil, runner: fake.runner)
    check((try? client.agents())?.count == 4, "agents() reads rig ps --nodes -A --full --json")
    check(fake.ran("rig ps --nodes -A --full --json"), "uses the full node records")
    check((try? client.agents())?.first { $0.name == "advisor-lead@kernel" }?.attentionReason == "billing",
          "a blocked seat showing a usage-credits screen is labelled billing, not permission_prompt")
    check((try? client.agents(labelBilling: false))?.first { $0.name == "advisor-lead@kernel" }?.attentionReason == "permission_prompt",
          "without labelling, the reason is rig's own")
    check((try? client.activeQueue())?.count == 4 && fake.ran("rig queue list -A --full --json --limit 1000"), "open work is read without closed history")
    check(!fake.calls.contains { $0.contains("--full") && $0.contains("-a") }, "and never mixes in closed rows")
    _ = try? client.queueGoal(destination: "dev-build@x", body: "Fix the login bug\n\nDetails here.")
    check(fake.ran("queue create", "--destination dev-build@x", "--summary Fix the login bug", "--body-file -"), "queueGoal creates a qitem")
    check(fake.stdins.last == "Fix the login bug\n\nDetails here.", "queueGoal sends the body on stdin")
    check((try? client.answerPrompt(session: "operator-agent@kernel", answer: "1")) == nil, "answerPrompt refuses a usage-credits prompt")
    check(!fake.ran("send operator-agent@kernel"), "and types nothing into it")
    check((try? client.answerPrompt(session: "dev-build@example-pair", answer: "1")) != nil, "answers a permission prompt")
    check(fake.ran("send dev-build@example-pair 1 --dangerously-interact --reason"), "answers through rig's audited prompt override")
    check(fake.calls.contains { $0 == ["rig", "capture", "dev-build@example-pair", "--json", "--readable"] },
          "reads the whole pane at a readable size before answering")
    check((try? client.answerPrompt(session: "small-pane@example-pair", answer: "1")) == nil, "refuses when the prompt may be cut off")
    check(!fake.ran("send small-pane@example-pair"), "and types nothing into it")
    check(client.attachCommand(session: "a@b") == ["tmux", "attach", "-t", "a@b"], "attach command for a seat")
    check(remote.attachCommand(session: "a@b") == ["ssh", "-t", "ubuntu@100.67.70.121", "tmux", "attach", "-t", "a@b"], "remote attach command")

    githubTests()
    mcpTests()
}

func githubTests() {
    let list = openrigFixture("gh-pr-list.json")
    let parsed = (try? GitHubClient.parsePullRequests(Data(list.utf8), repo: "ry-ops/unifi-mcp-server")) ?? []
    check(parsed.map { $0.0.checks } == ["success", "pending", "failure", nil], "check rollup: success, pending, failure, none")
    check(parsed.first?.1 == "52b1015978435a40a65faadd135308ee34f11c20", "head commit sha")
    check(parsed.first?.0.id == "ry-ops/unifi-mcp-server#56", "PR id")

    let rows = (try? JSONSerialization.jsonObject(with: Data(list.utf8)) as? [[String: Any]]) ?? []
    func view(_ i: Int) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: rows[i])) ?? Data(), as: UTF8.self) }
    let verified = openrigFixture("gh-commit-verification.json")

    let f = FakeRunner()
    f.on("pr list", reply: list)
    f.on("api", "commits/", reply: verified)
    let gh = GitHubClient(runner: f.runner)
    let prs = (try? gh.pullRequests(repo: "ry-ops/unifi-mcp-server")) ?? []
    check(prs.count == 4 && prs.first?.signed == true, "lists PRs with signature status")

    // Merge: only green and verified.
    let green = FakeRunner()
    green.on("pr view 56", reply: view(0)); green.on("api", reply: verified); green.on("pr merge", reply: "")
    check((try? GitHubClient(runner: green.runner).merge(repo: "ry-ops/unifi-mcp-server", number: 56)) != nil, "merges a green, verified PR")
    check(green.ran("pr merge 56 --repo ry-ops/unifi-mcp-server --squash --match-head-commit 52b1015978435a40a65faadd135308ee34f11c20"),
          "squash merge pinned to the checked head commit")

    let red = FakeRunner()
    red.on("pr view 58", reply: view(2)); red.on("api", reply: verified); red.on("pr merge", reply: "")
    check((try? GitHubClient(runner: red.runner).merge(repo: "r/x", number: 58)) == nil, "refuses failing checks")
    check(!red.ran("pr merge"), "and never calls merge")

    let pending = FakeRunner()
    pending.on("pr view 57", reply: view(1)); pending.on("pr merge", reply: "")
    check((try? GitHubClient(runner: pending.runner).merge(repo: "r/x", number: 57)) == nil && !pending.ran("pr merge"), "refuses pending checks")

    let unsigned = FakeRunner()
    unsigned.on("pr view 56", reply: view(0)); unsigned.on("api", reply: #"{"verified":false,"reason":"unsigned"}"#); unsigned.on("pr merge", reply: "")
    check((try? GitHubClient(runner: unsigned.runner).merge(repo: "r/x", number: 56)) == nil && !unsigned.ran("pr merge"), "refuses an unverified head commit")
}

func mcpTests() {
    let fake = recordedRig()
    let backend = LiveBackend(config: KliegConfig(openrigHost: nil, repos: []), runner: fake.runner)
    let server = MCPServer(backend: backend, readOnly: false)

    // Handshake.
    let initReply = rpc(server, 1, "initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "selftest", "version": "0"]])
    let initResult = initReply["result"] as? [String: Any]
    check(initResult?["protocolVersion"] as? String == "2025-06-18", "initialize echoes a supported protocol version")
    check((initResult?["serverInfo"] as? [String: Any])?["name"] as? String == "klieg", "initialize names the server")
    check(server.handleLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil, "notifications get no reply")
    check((rpc(server, 2, "nope")["error"] as? [String: Any])?["code"] as? Int == -32601, "unknown method is -32601")
    check(server.handleLine("{not json")?.contains("-32700") == true, "bad JSON is a parse error")

    // Tools.
    let tools = ((rpc(server, 3, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
    let names = Set(tools.compactMap { $0["name"] as? String })
    let expected: Set = ["klieg_status", "klieg_timeline", "klieg_read_agent", "klieg_pull_requests",
                         "klieg_prompt_agent", "klieg_queue_goal", "klieg_start_agent", "klieg_stop_agent",
                         "klieg_rig_up", "klieg_rig_down", "klieg_answer_prompt", "klieg_merge_pr"]
    check(names == expected, "tools/list has all twelve tools")
    check(Set(KliegServer.toolNames) == expected, "KliegServer.toolNames matches")
    let destructive = Set(tools.filter { (($0["annotations"] as? [String: Any])?["destructiveHint"] as? Bool) == true }.compactMap { $0["name"] as? String })
    check(destructive == ["klieg_stop_agent", "klieg_rig_down", "klieg_answer_prompt", "klieg_merge_pr"], "stop, down, answer and merge are destructive")
    let readOnlyHinted = tools.filter { (($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool) == true }.count
    check(readOnlyHinted == 4, "the four read tools carry readOnlyHint")

    // A read tool, end to end through LiveBackend and the recorded rig output.
    let status = rpc(server, 4, "tools/call", ["name": "klieg_status", "arguments": [:]])
    check(!toolFailed(status), "klieg_status succeeds")
    check(toolText(status).contains("! openrig:advisor-lead@kernel  billing"), "klieg_status says who needs the person, and why")
    let structured = (status["result"] as? [String: Any])?["structuredContent"] as? [String: Any]
    check((structured?["agents"] as? [Any])?.count == 4, "klieg_status returns structured agents")
    let timeline = rpc(server, 5, "tools/call", ["name": "klieg_timeline", "arguments": ["limit": 2]])
    check(toolText(timeline).contains("is working on qitem-20261031195841"), "klieg_timeline shows queue activity, newest first")
    check(fake.ran("queue list -a -A --json"), "klieg_timeline adds closed history")
    let read = rpc(server, 6, "tools/call", ["name": "klieg_read_agent", "arguments": ["agent": "openrig:operator-agent@kernel"]])
    check(toolText(read).contains("usage credits"), "klieg_read_agent returns the screen")
    check(toolFailed(rpc(server, 7, "tools/call", ["name": "klieg_read_agent", "arguments": [:]])), "missing argument is a tool error")
    _ = rpc(server, 8, "tools/call", ["name": "klieg_read_agent", "arguments": ["agent": "herdr:herdr/w1:p1"]])
    check(fake.ran("herdr", "agent read w1:p1"), "herdr ids reach herdr (M3b wired it in)")

    // Guards.
    let answer = rpc(server, 9, "tools/call", ["name": "klieg_answer_prompt", "arguments": ["agent": "openrig:operator-agent@kernel", "answer": "1"]])
    check(toolFailed(answer) && toolText(answer).contains("billing"), "klieg_answer_prompt refuses a usage-credits prompt")
    check(!fake.ran("send operator-agent@kernel"), "and types nothing")

    let roFake = recordedRig()
    let ro = MCPServer(backend: LiveBackend(config: KliegConfig(openrigHost: nil), runner: roFake.runner), readOnly: true)
    for (i, name) in expected.filter({ !["klieg_status", "klieg_timeline", "klieg_read_agent", "klieg_pull_requests"].contains($0) }).enumerated() {
        let r = rpc(ro, 100 + i, "tools/call", ["name": name, "arguments": ["agent": "openrig:dev-build@x", "text": "hi", "destination": "dev-build@x",
                                                                            "body": "b", "name": "n", "kind": "claude", "spec": "s", "rig": "r",
                                                                            "answer": "1", "repo": "o/r", "number": 1]])
        check(toolFailed(r) && toolText(r).contains("read-only"), "read-only refuses \(name)")
    }
    check(roFake.calls.isEmpty, "read-only runs no commands at all")
    check(!toolFailed(rpc(ro, 200, "tools/call", ["name": "klieg_status", "arguments": [:]])), "read tools still work when read-only")
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
