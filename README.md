# Klieg

**A spotlight on your coding agents.** Klieg watches and steers [herdr](https://herdr.dev) agents and [OpenRig](https://www.npmjs.com/package/@openrig/cli) rigs from one place: a native macOS app with a built-in terminal, a `klieg` command-line tool, and an MCP server so Claude can see and drive them too.

> Status: early. See [ROADMAP.md](ROADMAP.md). Klieg is being built by the agents it watches.

| Surface | What it gives you |
| --- | --- |
| **Klieg app** | A board of every agent and seat, a timeline of claims, handoffs and PRs, a "Needs You" list with notifications, and a VS Code-style terminal that opens any agent's live session in one click. |
| **`klieg` CLI** | `klieg status`, `klieg timeline --watch`, and actions from the shell. |
| **MCP server** (`klieg mcp`) | Tools for Claude to read state and act: prompt agents, queue goals, start and stop rigs, merge green PRs. `KLIEG_READ_ONLY=1` turns every action off. |

## Requirements

- A Mac running macOS 27 or later, for the app
- **Command Line Tools only.** You don't need the Xcode app: `xcode-select --install`
- herdr and/or OpenRig on the machines you want to watch, reachable over SSH

The core library, CLI and MCP server also build and run on Linux.

## Build

```bash
bash scripts/build-app.sh            # build/Klieg.app
bash scripts/build-app.sh --install  # install to /Applications and link ~/.local/bin/klieg
swift run klieg-selftest             # self-test, no XCTest needed
```

`build-app.sh` sets `DEVELOPER_DIR` to the Command Line Tools, so it works even when `xcode-select` points at Xcode.

## Configure

`~/.config/klieg/config.json` (all optional):

```json
{
  "herdrMachine": "herdr",
  "herdrSession": "work",
  "openrigHost": "ubuntu@100.67.70.121",
  "repos": ["ry-ops/klieg"],
  "refreshSeconds": 5,
  "readOnly": false
}
```

## License

MIT. The built-in terminal uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT).
