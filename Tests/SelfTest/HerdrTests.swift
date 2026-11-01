import Foundation
import KliegKit

// M1 (herdr agent): checks for HerdrClient and Timeline. Use recorded JSON fixtures, not a live herdr.
// The fixtures are described in Fixtures/herdr/README.md.

private let herdrFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/herdr")

private func fixture(_ name: String) -> String {
    (try? String(contentsOf: herdrFixtures.appendingPathComponent(name), encoding: .utf8)) ?? ""
}

/// A fake herdr: answers from fixtures and remembers every command it was given.
private final class FakeHerdr: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    /// Fixture file per subcommand, matched against the args after the session/machine prefix.
    var replies: [String: (status: Int32, file: String)] = [:]

    var runner: HerdrClient.Runner {
        { [self] args, _ in
            lock.lock(); calls.append(args); lock.unlock()
            let sub = Array(args.drop { $0 == "herdr" }.dropFirst(2))
            // Longest matching key wins, so "agent read w4:p1" beats "agent read".
            let key = replies.keys.filter { sub.joined(separator: " ").hasPrefix($0) }.max { $0.count < $1.count }
            guard let key, let reply = replies[key] else { return CommandResult(status: 0, stdout: "{\"id\":\"x\",\"result\":{}}", stderr: "") }
            let text = fixture(reply.file)
            return reply.status == 0 ? CommandResult(status: 0, stdout: text, stderr: "")
                                     : CommandResult(status: reply.status, stdout: "", stderr: text)
        }
    }
    var lastCall: [String] { lock.lock(); defer { lock.unlock() }; return calls.last ?? [] }
}

private func agent(_ id: String, _ status: AgentStatus, reason: String? = nil, name: String? = nil) -> Agent {
    Agent(id: id, source: .herdr, name: name ?? id, kind: "claude", status: status, attentionReason: reason, group: "ws")
}

func herdrTests() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // --- Reading the recorded session (one Claude agent at work, one plain shell)
    let fake = FakeHerdr()
    fake.replies = ["api snapshot": (0, "api-snapshot.json")]
    let local = HerdrClient(target: .local(session: "work"), machine: "herdr", runner: fake.runner)
    check(local.prefix == ["herdr", "--session", "work"], "local client uses --session")
    let real = (try? local.agents(now: t0)) ?? []
    check(real.count == 1, "recorded snapshot has one agent (the plain shell pane is not one)")
    if let m1 = real.first {
        check(m1.id == "herdr:herdr/w3:p1", "agent id is herdr:<machine>/<pane>")
        check(m1.name == "m1" && m1.kind == "claude" && m1.status == .working, "name, kind and status map over")
        check(m1.group == "klieg-m1", "group is the workspace label")
        check(m1.cwd == "/home/ubuntu/src/klieg", "cwd maps over")
        check(m1.attachCommand == ["herdr", "--session", "work", "agent", "attach", "w3:p1"], "local attach command")
        check(m1.updated == t0, "updated is the snapshot time")
    }
    check(!fake.calls.contains { $0.contains("read") }, "working agents don't cost a screen read")

    // Other recorded replies decode.
    fake.replies = ["workspace list": (0, "workspace-list.json"), "pane list": (0, "pane-list.json"),
                    "agent get": (0, "agent-get.json")]
    check((try? local.workspaces().map(\.label)) == ["~", "klieg-m1"], "workspace list decodes")
    check((try? local.panes().count) == 2, "pane list decodes")
    check((try? local.agentInfo("m1").pane_id) == "w3:p1", "agent get decodes")

    // herdr errors come back as JSON on stderr.
    fake.replies = ["agent get": (1, "error-agent-not-found.json")]
    do { _ = try local.agentInfo("nosuch"); check(false, "missing agent throws") }
    catch let e as HerdrError { check(e == .herdr(code: "agent_not_found", message: "agent target nosuch not found"), "herdr error code is kept") }
    catch { check(false, "unexpected error \(error)") }

    // --- The mixed session: idle, blocked, done, unnamed, and Claude's trust screen hidden as idle
    let mixed = FakeHerdr()
    mixed.replies = ["api snapshot": (0, "api-snapshot-mixed.json"),
                     "agent read w4:p1": (0, "trust-prompt.txt"),
                     "agent read w5:p2": (0, "idle-prompt.txt")]
    let client = HerdrClient(target: .local(session: "work"), machine: "herdr", runner: mixed.runner)
    let agents = (try? client.agents(now: t0)) ?? []
    let byName = Dictionary(agents.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    check(agents.count == 5, "mixed snapshot has five agents")
    check(byName["mypy"]?.status == .blocked && byName["mypy"]?.attentionReason == "trust_prompt",
          "idle Claude showing the trust screen is reported blocked with trust_prompt")
    check(byName["reviewer"]?.status == .blocked && byName["reviewer"]?.attentionReason == "approval_or_question",
          "herdr's own blocked is kept")
    check(byName["docs"]?.status == .done, "done maps over")
    check(byName["w5:p2"]?.status == .idle && byName["w5:p2"]?.attentionReason == nil,
          "unnamed agent is named by pane and an ordinary idle prompt stays idle")
    check(byName["mypy"]?.group == "mypy" && byName["docs"]?.group == "docs", "groups follow workspaces")
    let reads = mixed.calls.filter { $0.contains("read") }.compactMap { call in call.firstIndex(of: "read").map { call[$0 + 1] } }
    check(Set(reads) == ["w4:p1", "w5:p2"], "only idle Claude agents get their screen read")
    check(Snapshot(agents: agents).needingPerson.count == 2, "two agents need a person")

    check(HerdrClient.showsTrustPrompt(fixture("trust-prompt.txt")), "trust screen is recognized")
    check(HerdrClient.showsTrustPrompt("Do you trust the files in this folder?\n❯ 1. Yes, proceed"), "older trust wording is recognized")
    check(!HerdrClient.showsTrustPrompt(fixture("agent-read-working.txt")), "a working Claude screen is not a trust screen")
    check(!HerdrClient.showsTrustPrompt(fixture("pane-read-shell.txt")), "a shell prompt is not a trust screen")

    // A failed snapshot becomes an error, not a crash.
    let broken = HerdrClient(target: .local(session: "work"), machine: "herdr",
                             runner: { _, _ in CommandResult(status: 1, stdout: "", stderr: "server not running") })
    let bad = broken.snapshot(now: t0)
    check(bad.agents.isEmpty && bad.errors["herdr"]?.contains("server not running") == true, "herdr failure lands in snapshot.errors")

    // --- Remote (from the Mac)
    let rfake = FakeHerdr()
    rfake.replies = ["api snapshot": (0, "api-snapshot.json")]
    let remote = HerdrClient(target: .remote(machine: "herdr", session: "work"), machine: "herdr", runner: rfake.runner)
    check(remote.prefix == ["herdr", "--machine", "herdr"], "remote client uses --machine")
    let ra = (try? remote.agents(now: t0))?.first
    check(ra?.id == "herdr:herdr/w3:p1", "remote and local give the same agent id")
    check(ra?.attachCommand == ["ssh", "-t", "herdr", "bash -lc 'herdr --session work agent attach w3:p1'"],
          "remote attach goes over ssh")
    check(remote.attachCommand(pane: "w1:p1; rm -rf ~") == ["ssh", "-t", "herdr", #"bash -lc 'herdr --session work agent attach '\''w1:p1; rm -rf ~'\'''"#],
          "a pane id is quoted for the far shell")
    var hosted = remote; hosted.sshHost = "ubuntu@herdr.example"
    check(hosted.attachCommand(pane: "w1:p1")[2] == "ubuntu@herdr.example", "ssh host can be set")

    // fromConfig: no saved machine with that label means we're on the herdr host.
    let noMachines: HerdrClient.Runner = { _, _ in CommandResult(status: 0, stdout: "[]", stderr: "") }
    let saved: HerdrClient.Runner = { _, _ in CommandResult(status: 0, stdout: #"[{"id":"m_1","label":"herdr"}]"#, stderr: "") }
    var cfg = KliegConfig(); cfg.herdrMachine = "herdr"
    if ProcessInfo.processInfo.environment["HERDR_ENV"] != "1" {
        check(HerdrClient.fromConfig(cfg, runner: saved).target == .remote(machine: "herdr", session: "work"), "saved machine → remote")
    }
    check(HerdrClient.fromConfig(cfg, runner: noMachines).target == .local(session: "work"), "unknown machine → local")
    cfg.herdrMachine = nil
    check(HerdrClient.fromConfig(cfg, runner: saved).target == .local(session: "work"), "no machine → local")

    // --- Targets
    check((try? client.herdrTarget("herdr:herdr/w4:p2")) == "w4:p2", "Klieg id resolves to its pane")
    check((try? client.herdrTarget("reviewer")) == "reviewer", "names pass through")
    check((try? client.herdrTarget("herdr:other/w1:p1")) == nil, "another machine's agent is refused")
    check((try? client.herdrTarget("--kind")) == nil && (try? client.herdrTarget("herdr:herdr/-x")) == nil,
          "a name or pane that looks like an option is refused")

    // --- Actions build the right commands
    let act = FakeHerdr()
    act.replies = ["workspace create": (0, "workspace-create.json")]
    let doer = HerdrClient(target: .remote(machine: "herdr", session: "work"), machine: "herdr", runner: act.runner)
    try? doer.prompt("herdr:herdr/w4:p1", text: "run the tests")
    check(act.lastCall == ["herdr", "--machine", "herdr", "agent", "prompt", "w4:p1", "run the tests"], "prompt")
    check((try? doer.prompt("herdr:herdr/w4:p1", text: "--help")) == nil, "a message that looks like an option is refused")
    check((try? doer.sendKeys("reviewer", keys: ["y", "--delay"])) == nil, "so is a key")
    check(act.lastCall.last == "run the tests", "and neither ran")
    try? doer.sendKeys("reviewer", keys: ["esc", "enter"])
    check(act.lastCall.suffix(4) == ["send-keys", "reviewer", "esc", "enter"], "send-keys")
    try? doer.start(agent: "fixer", kind: "codex", pane: "w6:p1")
    check(act.lastCall.suffix(7) == ["agent", "start", "fixer", "--kind", "codex", "--pane", "w6:p1"], "start")
    let created = try? doer.createWorkspace(cwd: "/home/ubuntu/src", label: "scratch")
    check(created?.workspace == "w6" && created?.pane == "w6:p1", "create workspace returns its ids")
    check(act.lastCall.suffix(6) == ["create", "--cwd", "/home/ubuntu/src", "--no-focus", "--label", "scratch"], "create workspace keeps focus")
    try? doer.closeWorkspace("w6")
    check(act.lastCall.suffix(3) == ["workspace", "close", "w6"], "close workspace")

    // herdr refuses prompting a blocked agent; the code comes through.
    let blockedRunner: HerdrClient.Runner = { _, _ in
        CommandResult(status: 1, stdout: "", stderr: #"{"error":{"code":"agent_blocked","message":"agent is blocked"},"id":"cli:agent:prompt"}"#)
    }
    let blockedClient = HerdrClient(target: .local(session: "work"), machine: "herdr", runner: blockedRunner)
    do { try blockedClient.prompt("mypy", text: "hi"); check(false, "prompting a blocked agent throws") }
    catch let e as HerdrError { if case .herdr(let code, _) = e { check(code == "agent_blocked", "agent_blocked is reported") } else { check(false, "wrong error \(e)") } }
    catch { check(false, "unexpected error \(error)") }

    // Read-only refuses every action before running anything.
    let ro = FakeHerdr()
    let readOnly = HerdrClient(target: .local(session: "work"), machine: "herdr", readOnly: true, runner: ro.runner)
    var refused = 0
    for action in [{ try readOnly.prompt("m1", text: "x") }, { try readOnly.sendKeys("m1", keys: ["esc"]) },
                   { try readOnly.start(agent: "a", kind: "claude", pane: "w1:p1") },
                   { _ = try readOnly.createWorkspace(cwd: "/tmp") }, { try readOnly.closeWorkspace("w1") }] as [() throws -> Void] {
        do { try action() } catch let e as HerdrError where e == .readOnly { refused += 1 } catch {}
    }
    check(refused == 5 && ro.calls.isEmpty, "read-only refuses all five actions without calling herdr")

    timelineTests(t0)
}

private func timelineTests(_ t0: Date) {
    let t1 = t0.addingTimeInterval(5)
    let a = agent("herdr:herdr/w1:p1", .idle, name: "a")
    let b = agent("herdr:herdr/w2:p1", .working, name: "b")
    let c = agent("herdr:herdr/w3:p1", .working, name: "c")
    let old = Snapshot(taken: t0, agents: [a, b, c])

    check(Timeline.diff(from: nil, to: old).isEmpty, "first snapshot is a baseline")
    check(Timeline.diff(from: old, to: Snapshot(taken: t1, agents: [a, b, c])).isEmpty, "no change, no events")

    var a2 = a; a2.status = .working
    var b2 = b; b2.status = .blocked; b2.attentionReason = "trust_prompt"
    let d = agent("herdr:herdr/w4:p1", .idle, name: "d")
    let new = Snapshot(taken: t1, agents: [a2, b2, d])
    let ev = Timeline.diff(from: old, to: new)
    let kinds = ev.map { "\($0.subject.split(separator: "/").last!):\($0.kind)" }
    check(kinds == ["w1:p1:statusChanged", "w2:p1:needsPerson", "w4:p1:appeared", "w3:p1:stopped"], "events in order: \(kinds)")
    check(ev.first?.text == "a (claude) started working", "status change reads plainly")
    check(ev[1].text.contains("trust the folder"), "trust prompt explained")
    check(ev[2].text == "d (claude) appeared in ws", "appeared names the group")
    check(ev.allSatisfy { $0.date == t1 }, "events carry the new snapshot's time")
    check(ev.map(\.id) == Timeline.diff(from: old, to: new).map(\.id), "diff is deterministic, ids included")

    var b3 = b2; b3.status = .idle; b3.attentionReason = nil
    let later = Timeline.diff(from: new, to: Snapshot(taken: t1, agents: [a2, b3, d]))
    check(later.map(\.text) == ["b (claude) is no longer waiting on you"], "unblocking reads plainly")
    var b4 = b2; b4.attentionReason = "approval_or_question"
    check(Timeline.diff(from: new, to: Snapshot(taken: t1, agents: [a2, b4, d])).map(\.kind) == ["needsPerson"],
          "a new reason to need a person is a new event")
    var d2 = d; d2.status = .done
    check(Timeline.diff(from: new, to: Snapshot(taken: t1, agents: [a2, b2, d2])).first?.text == "d (claude) finished a turn", "done reads plainly")

    // A herdr outage doesn't look like every agent stopping, nor coming back.
    let outage = Snapshot(taken: t1, errors: ["herdr": "timed out"])
    check(Timeline.diff(from: old, to: outage).isEmpty, "outage gives no stopped events")
    let carried = Timeline.carryOver(from: old, to: outage)
    check(carried.agents.count == 3, "outage keeps the previous agents for the next comparison")
    check(Timeline.diff(from: carried, to: Snapshot(taken: t1, agents: [a, b, c])).isEmpty, "recovery gives no appeared events")

    // Queue items and pull requests.
    let q = QueueItem(id: "q1", source: "dev-build", destination: "dev-review", state: "pending", summary: "review PR 3")
    var q2 = q; q2.state = "done"
    let pr = PullRequest(repo: "ry-ops/klieg", number: 3, title: "M1", url: "u", state: "OPEN", checks: "pending")
    var pr2 = pr; pr2.checks = "success"
    var pr3 = pr2; pr3.state = "MERGED"
    let qs = Timeline.diff(from: Snapshot(taken: t0), to: Snapshot(taken: t1, queue: [q], pullRequests: [pr]))
    check(qs.map(\.kind) == ["queued", "prOpened"], "new qitem and PR")
    check(qs.first?.text == "dev-build handed dev-review a queue item: review PR 3", "handoff reads plainly")
    let qs2 = Timeline.diff(from: Snapshot(taken: t0, queue: [q], pullRequests: [pr]), to: Snapshot(taken: t1, queue: [q2], pullRequests: [pr2]))
    check(qs2.map(\.kind) == ["queueStateChanged", "checksFinished"], "qitem state and checks finishing")
    check(Timeline.diff(from: Snapshot(taken: t0, pullRequests: [pr2]), to: Snapshot(taken: t1, pullRequests: [pr3])).map(\.kind) == ["merged"], "merge")

    // The store remembers between runs.
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("klieg-selftest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TimelineStore(directory: dir, keep: 3)
    check((try? store.record(old))?.isEmpty == true, "store: first record is a baseline")
    check((try? store.record(new))?.count == 4, "store: second record diffs against the first")
    check(store.events().count == 3, "store keeps only the newest events")
    check(store.lastSnapshot()?.agents.map(\.id) == new.agents.map(\.id), "store saves the last snapshot")
    check(store.events().last?.subject == "herdr:herdr/w3:p1", "stored events keep their order")
}
