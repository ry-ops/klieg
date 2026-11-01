# Klieg roadmap

Klieg is built by three builders at once, and it watches itself being built:

| Builder | Where | Owns |
|---|---|---|
| **herdr agent** | herdr VM, a herdr pane | M1 |
| **OpenRig rig** (builder + reviewer) | open-rig VM | M2 |
| **Claude Code on the Mac** | Ryan's Mac mini | M0, M3, M4 (everything macOS-only) |

Rules for every builder are in [AGENTS.md](AGENTS.md).

## M0: Skeleton ✅ (Mac)
Package, KliegKit models, `Shell`, `KliegConfig`, CLI stub, MCP stub, app shell with the SwiftTerm terminal, self-test, Linux CI, `scripts/build-app.sh` (Command Line Tools only).

## M1: herdr + timeline + CLI (herdr agent)
Files: `Sources/KliegKit/Herdr.swift`, `Sources/KliegKit/Timeline.swift`, `Sources/KliegCLI/main.swift`, `Tests/SelfTest/HerdrTests.swift`, `Tests/SelfTest/Fixtures/herdr/*`.
- `HerdrClient`: read herdr through its CLI. Local (`herdr --session <s> …`) when running on the herdr host, remote (`herdr --machine <label> …`) from the Mac. Use `herdr api snapshot`, `herdr agent list|get|read`, `herdr pane list|read`, `herdr workspace list`. Map to `Agent` (id `herdr:<machine>/<pane>`, group = workspace label, `attachCommand` = how to open the pane).
- Known gap to handle: herdr reports Claude's first-run folder-trust screen as `idle`, not `blocked`. Detect it from the pane text and report `blocked` with `attentionReason: "trust_prompt"`.
- Actions: `start(agent:kind:pane:)`, `prompt(_:text:)`, `sendKeys`, `createWorkspace(cwd:label:)`, `closeWorkspace`.
- `Timeline`: diff two `Snapshot`s into `TimelineEvent`s (status changes, needs-person, appeared/stopped). Pure function, fully tested.
- CLI: `klieg status [--json]`, `klieg timeline [--watch]`, `klieg herdr prompt <agent> <text>`.
- Self-test with recorded herdr JSON in `Tests/SelfTest/Fixtures/herdr/`.

## M2: OpenRig + GitHub + MCP server (OpenRig rig)
Files: `Sources/KliegKit/OpenRig.swift`, `Sources/KliegKit/GitHub.swift`, `Sources/KliegServer/*`, `Tests/SelfTest/OpenRigTests.swift`, `Tests/SelfTest/Fixtures/openrig/*`.
- `OpenRigClient`: `rig ps --nodes --json`, `rig queue list -A`, `rig capture <session>`; over `ssh <openrigHost>` when set, local otherwise. Map seats to `Agent` (status from activity: needs-input → blocked, with `attentionReason` from ATTN REASON; `model` from the observed model) and qitems to `QueueItem`.
- Actions: `queueGoal(destination:body:)`, `send(session:text:)`, `up(spec:)`, `down(rig:)`, attach command for a seat (`ssh -t <host> tmux attach -t <session>`).
- `GitHubClient` via `gh`: open PRs per configured repo with checks and signature status; `merge(repo:number:)` (squash) refuses unless checks are green and the head commit is verified.
- MCP server (`klieg mcp`, stdio JSON-RPC, no SDK; follow afm-studio's `AFMServer/MCPServer.swift`). Tools:
  - read: `klieg_status`, `klieg_timeline`, `klieg_read_agent`, `klieg_pull_requests`
  - act: `klieg_prompt_agent`, `klieg_queue_goal`, `klieg_start_agent`, `klieg_stop_agent`, `klieg_rig_up`, `klieg_rig_down`, `klieg_answer_prompt`, `klieg_merge_pr`
  - Every act tool refuses when `KLIEG_READ_ONLY` is set; stop/down/answer/merge carry `destructiveHint: true`. `klieg_answer_prompt` refuses prompts that mention usage credits or billing.
- Self-test with recorded `rig` JSON and an in-process MCP round trip (initialize, tools/list, a read tool).

## M3: The app (Mac)
Board, Timeline, Needs You (with macOS notifications), Pull Requests and Settings; one-click "open in terminal" for any agent or seat; confirmations before stop, merge and answering prompts; menu-bar extra with the count of agents needing you.

## M4: Polish (Mac)
Icon, README screenshots, `--install`, MCP registration in Claude Code, release 0.1.0.

## Follow-ups from the security review (Mac)
PR #17 hardened the MCP tools and was verified by the Linux CI build and self-test. These pieces need a Mac or the live `rig` and `herdr` CLIs, which the review session didn't have:
- **Build the app and run the self-test on macOS** after #17. CI covers KliegKit, KliegServer and the CLI on Linux only. #17 changed `Shell.run` (stdin on its own thread, SIGPIPE ignored) and the default `openrigHost`, both of which the app uses, so build with `scripts/build-app.sh` and run `swift run klieg-selftest` on the Mac once.
- **Bump SwiftTerm from 1.99.1 to 1.99.2** in `Package.swift` and `Package.resolved`. Not a security fix (the only SwiftTerm advisory, CVE-2022-23465, was fixed in 1.2.0), so it was left out of #17 rather than ship an app change nobody could compile. Build and open the app to check the terminal still works.
- **Use `--` instead of refusing values that start with `-`**, if `rig` and `herdr` accept `--` to end their options. `RigText.positional` refuses a seat, pane, message, answer or key that starts with `-` so it can't be read as an option. Passing `--` before positional values would be the cleaner fix and would let a message start with `-`. Check both CLIs first: a `--` that a CLI doesn't understand breaks every command.
