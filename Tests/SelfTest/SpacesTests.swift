import Foundation
import KliegKit

// Checks for the herdr-style redesign's core: Spaces, BranchResolver and ScreenFeed. Recorded fixtures and
// fake runners only; nothing live.

private func herdrFix(_ name: String) -> String {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/herdr")
    return (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
}

private let rigHost = "ubuntu@rig.example"

/// herdr's mixed session (with mypy on the trust screen) plus the recorded OpenRig seats.
private func recordedSnapshot() -> Snapshot {
    let herdr = HerdrClient(target: .local(session: "work"), machine: "herdr", runner: { args, _ in
        let line = args.joined(separator: " ")
        if line.contains("api snapshot") { return CommandResult(status: 0, stdout: herdrFix("api-snapshot-mixed.json"), stderr: "") }
        if line.contains("agent read w4:p1") { return CommandResult(status: 0, stdout: herdrFix("trust-prompt.txt"), stderr: "") }
        return CommandResult(status: 0, stdout: herdrFix("idle-prompt.txt"), stderr: "")
    })
    let h = (try? herdr.agents()) ?? []
    let o = (try? OpenRigClient.parseNodes(Data(openrigFixture("ps-nodes.json").utf8), host: rigHost)) ?? []
    return Snapshot(agents: h + o)
}

/// A clock the test moves by hand.
private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
}

/// Collects handler calls from any thread.
private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    let arrived = DispatchSemaphore(value: 0)
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock(); arrived.signal() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

func spacesTests() {
    // --- Spaces
    let snap = recordedSnapshot()
    check(snap.agents.count == 9, "recorded snapshot: 5 herdr agents and 4 OpenRig seats")
    let spaces = Spaces.group(snap, openrigHost: rigHost)
    let names = spaces.map(\.name)
    check(Set(names) == ["klieg-m1", "mypy", "docs", "kernel", "klieg-pair", "unifi-pair"], "one space per herdr workspace and per rig: \(names)")
    let blockedFirst = spaces.prefix { $0.status == .blocked }.map(\.name)
    check(blockedFirst == ["kernel", "mypy"], "spaces with a blocked agent first, by name: \(names)")
    let afterBlocked = spaces.dropFirst(blockedFirst.count)
    check(afterBlocked.prefix { $0.status == .working }.map(\.name) == ["klieg-m1", "klieg-pair"], "then working spaces: \(names)")
    let rest = afterBlocked.drop { $0.status == .working }.map(\.name)
    check(rest == rest.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, "then the rest by name: \(rest)")

    let byName = Dictionary(spaces.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    let mypy = byName["mypy"]
    check(mypy?.id == "herdr:herdr/mypy" && mypy?.source == .herdr, "herdr space id carries the machine")
    check(mypy?.status == .blocked, "space status is its most urgent agent (two blocked)")
    check(byName["docs"]?.status == .done, "done beats idle")
    check(byName["klieg-m1"]?.subtitle == "~/src/klieg", "herdr subtitle: cwd with ~ (no branch known)")
    check(byName["kernel"]?.subtitle == "rig.example · 1 seat", "OpenRig subtitle: host and seat count (singular)")
    check(byName["klieg-pair"]?.subtitle == "rig.example · 2 seats", "OpenRig subtitle: plural")
    check(byName["klieg-pair"]?.id == "openrig:klieg-pair" && byName["klieg-pair"]?.source == .openrig, "OpenRig space id is the rig")
    check(Spaces.group(snap).first { $0.name == "kernel" }?.subtitle == "local · 1 seat", "no OpenRig host: local")
    check(spaces.flatMap(\.agentIDs).count == 9, "every agent is in exactly one space")

    let withBranch = Spaces.group(snap, branches: ["herdr:herdr/w3:p1": "m1-herdr"])
    check(withBranch.first { $0.name == "klieg-m1" }?.subtitle == "~/src/klieg · m1-herdr", "herdr subtitle adds the branch (by agent id)")
    let byCwd = Spaces.group(snap, branches: ["/home/ubuntu/src/docs": "main"])
    check(byCwd.first { $0.name == "docs" }?.subtitle == "~/src/docs · main", "branches can also be keyed by cwd")

    if let m = mypy {
        let ordered = Spaces.agentsOrdered(in: m, snapshot: snap).map(\.name)
        check(ordered == ["mypy", "reviewer"], "agents: needs-person first, by name: \(ordered)")
        check(m.agentIDs == Spaces.agentsOrdered(in: m, snapshot: snap).map(\.id), "agentIDs are in agentsOrdered order")
    }
    if let pair = byName["klieg-pair"] {
        check(Spaces.agentsOrdered(in: pair, snapshot: snap).map(\.name) == ["dev-build@klieg-pair", "dev-review@klieg-pair"], "working before idle")
    }
    if let docs = byName["docs"] {
        check(Spaces.agentsOrdered(in: docs, snapshot: snap).map(\.name) == ["docs", "w5:p2"], "otherwise by name")
    }
    let urgencyOrder: [AgentStatus] = [.blocked, .working, .done, .idle, .unknown, .stopped]
    check(urgencyOrder.map(Spaces.urgency) == [0, 1, 2, 3, 4, 5], "urgency: blocked > working > done > idle > unknown > stopped")
    check(Spaces.tildePath("/Users/ryan/src/klieg") == "~/src/klieg" && Spaces.tildePath("/root") == "~"
          && Spaces.tildePath("/home/ubuntu") == "~" && Spaces.tildePath("/opt/x") == "/opt/x", "tildePath")
    check(Spaces.group(Snapshot()).isEmpty, "no agents, no spaces")

    // --- BranchResolver
    let clock = FakeClock()
    let git = FakeRunner()
    git.on("ssh", "BatchMode=yes", "ubuntu@rig.example", "'/home/ubuntu/src/it'\\''s here'", reply: "feature/quoted\n")
    git.on("ssh", "ubuntu@rig.example", "/home/ubuntu/src/klieg", reply: "m2-openrig\n")
    git.on("ssh", "herdr-host", "/home/ubuntu/src/klieg", reply: "m1-herdr\n")
    git.on("git -C /Users/ryan/src/klieg branch --show-current", reply: "main\n")
    git.on("git -C /tmp/detached", reply: "\n")
    let resolver = BranchResolver(openrigHost: rigHost, herdrHost: "herdr-host", runner: git.runner, now: { clock.now })
    let seat = Agent(id: "openrig:dev-build@klieg-pair", source: .openrig, name: "dev-build@klieg-pair", kind: "claude", status: .working, cwd: "/home/ubuntu/src/klieg")
    let pane = Agent(id: "herdr:herdr/w3:p1", source: .herdr, name: "m1", kind: "claude", status: .working, cwd: "/home/ubuntu/src/klieg")
    check(resolver.branch(for: seat) == "m2-openrig", "OpenRig agent: git over ssh to the OpenRig host")
    check(resolver.branch(for: pane) == "m1-herdr", "herdr agent: git over ssh to the herdr host")
    check(git.calls.last == ["ssh", "-o", "BatchMode=yes", "herdr-host", "git -C /home/ubuntu/src/klieg branch --show-current"], "remote command is one quoted string")
    check(resolver.branch(cwd: "/home/ubuntu/src/it's here", host: rigHost) == "feature/quoted", "awkward paths are quoted for the remote shell")
    check(resolver.branch(cwd: "/Users/ryan/src/klieg", host: nil) == "main", "no host: git runs here")
    check(git.calls.last == ["git", "-C", "/Users/ryan/src/klieg", "branch", "--show-current"], "local command needs no quoting")
    check(resolver.branch(cwd: "/tmp/detached", host: nil) == nil, "detached HEAD (empty answer) is nil")

    let before = git.calls.count
    check(resolver.branch(for: seat) == "m2-openrig" && git.calls.count == before, "answers are cached")
    check(resolver.branch(cwd: "/nowhere", host: nil) == nil, "a failing git is nil")
    let afterFail = git.calls.count
    _ = resolver.branch(cwd: "/nowhere", host: nil)
    check(git.calls.count == afterFail, "failures are cached too")
    clock.advance(61)
    _ = resolver.branch(for: seat)
    _ = resolver.branch(cwd: "/nowhere", host: nil)
    check(git.calls.count == afterFail + 2, "the cache expires after 60 s")
    check(resolver.branch(for: Agent(id: "openrig:x", source: .openrig, name: "x", kind: "claude", status: .idle)) == nil, "no cwd: nil, nothing run")
    check(resolver.branches(for: [seat, pane]) == ["openrig:dev-build@klieg-pair": "m2-openrig", "herdr:herdr/w3:p1": "m1-herdr"], "branches(for:) is keyed by agent id")

    let localHerdr = HerdrClient(target: .local(session: "work"), machine: "herdr")
    var remoteHerdr = HerdrClient(target: .remote(machine: "herdr", session: "work"), machine: "herdr")
    let cfg = KliegConfig(openrigHost: rigHost)
    check(BranchResolver(config: cfg, herdr: localHerdr).herdrHost == nil, "local herdr: git runs here")
    check(BranchResolver(config: cfg, herdr: remoteHerdr).herdrHost == "herdr", "remote herdr: the machine label")
    remoteHerdr.sshHost = "ubuntu@herdr.tail"
    check(BranchResolver(config: cfg, herdr: remoteHerdr).herdrHost == "ubuntu@herdr.tail", "remote herdr: its sshHost when set")
    check(BranchResolver(config: cfg, herdr: localHerdr).openrigHost == rigHost, "OpenRig host from the config")

    // --- ScreenFeed.normalize
    check(ScreenFeed.normalize("a  \r\nb\t\n\n  \n\n") == "a\nb", "CRLF, trailing spaces and trailing blank lines go")
    check(ScreenFeed.normalize("\n\nx") == "\n\nx", "leading blank lines stay")
    check(ScreenFeed.normalize((1...300).map(String.init).joined(separator: "\n")).split(separator: "\n").first == "101", "keeps the last 200 lines")
    check(ScreenFeed.normalize("1\n2\n3\n\n", lines: 2) == "2\n3", "lines counts after trimming")
    check(ScreenFeed.normalize("") == "" && ScreenFeed.normalize("   \n \n") == "", "blank screens are empty")

    // --- ScreenFeed polling
    final class Screens: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String]; private var i = 0
        init(_ l: [String]) { list = l }
        func next() throws -> String {
            lock.lock(); defer { lock.unlock() }
            let s = list[min(i, list.count - 1)]; i += 1
            if s == "FAIL" { throw KliegError("pane gone") }
            return s
        }
    }
    let screens = Screens(["one\n", "one  \n\n", "two", "FAIL", "FAIL", "two", "three"])
    let got = Inbox(), errors = Inbox()
    let feed = ScreenFeed(interval: 10, read: { try screens.next() }, onError: { errors.add("\($0)") }, handler: { got.add($0) })
    let calls = (0..<7).map { _ in feed.poll() }
    check(calls == [true, false, true, false, false, false, true], "handler only when the text changed: \(calls)")
    check(got.all == ["one", "two", "three"], "the handler gets normalized text")
    check(errors.all == ["pane gone"], "a repeated error is reported once")

    let live = Screens(["a", "a", "b", "b", "c"])
    let seen = Inbox()
    let timed = ScreenFeed(interval: 0.02, read: { try live.next() }, handler: { seen.add($0) })
    check(!timed.isRunning, "not running until started")
    timed.start(); timed.start()
    check(timed.isRunning, "start is idempotent")
    for _ in 0..<3 { _ = seen.arrived.wait(timeout: .now() + 2) }
    timed.stop(); timed.stop()
    check(seen.all == ["a", "b", "c"], "polls on its own queue until stopped: \(seen.all)")
    check(!timed.isRunning, "stop is idempotent")
    let count = seen.all.count
    Thread.sleep(forTimeInterval: 0.1)
    check(seen.all.count == count, "nothing arrives after stop")

    // Stopping from inside the handler is safe.
    let selfStop = Inbox()
    final class Box: @unchecked Sendable { var feed: ScreenFeed? }
    let box = Box()
    box.feed = ScreenFeed(interval: 0.02, read: { "x" }, handler: { selfStop.add($0); box.feed?.stop() })
    box.feed?.start()
    check(selfStop.arrived.wait(timeout: .now() + 2) == .success && box.feed?.isRunning == false, "a handler may call stop()")

    // Readers come from the agent's source, through the existing clients.
    let fh = FakeRunner()
    fh.on("herdr", "agent read", reply: "hello from herdr\n")
    let fr = FakeRunner()
    fr.on("capture", reply: #"{"ok":true,"content":"hello from rig\n\n"}"#)
    let hclient = HerdrClient(target: .local(session: "work"), machine: "herdr", runner: { args, t in try fh.runner(args, nil, t) })
    let oclient = OpenRigClient(host: rigHost, runner: fr.runner)
    let hGot = Inbox(), oGot = Inbox()
    let hFeed = try? ScreenFeed(agent: pane, herdr: hclient, openrig: oclient, handler: { hGot.add($0) })
    let oFeed = try? ScreenFeed(agent: seat, herdr: hclient, openrig: oclient, lines: 120, handler: { oGot.add($0) })
    hFeed?.poll(); oFeed?.poll()
    check(fh.calls.last == ["herdr", "--session", "work", "agent", "read", "w3:p1", "--source", "recent-unwrapped", "--lines", "200"], "herdr agent: herdr agent read, last 200 lines")
    check(fr.ran("ssh", rigHost, "rig capture dev-build@klieg-pair --json --lines 120"), "OpenRig seat: rig capture over ssh")
    check(hGot.all == ["hello from herdr"] && oGot.all == ["hello from rig"], "both feeds deliver trimmed text")
    check((try? ScreenFeed(agent: pane, herdr: nil, openrig: oclient, handler: { _ in })) == nil, "no herdr client for a herdr agent: refused")
}
