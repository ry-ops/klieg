# Introducing Klieg

*A spotlight on my coding agents: one place to see every herdr agent and OpenRig seat, and to know which one is waiting on me.*

![Klieg: a stage light sweeps across four coding agents, one stops to ask for approval, and the menu-bar count shows 1](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/hero.svg)

I run a lot of coding agents now. Some live in [herdr](https://herdr.dev) panes on one machine. Others are seats in [OpenRig](https://www.npmjs.com/package/@openrig/cli) rigs on another: a builder and a reviewer handing work to each other through a queue. On top of that there are the pull requests they open on GitHub, each with its own checks.

That's a lot of terminals to keep an eye on. The hard part isn't the work itself. It's the simple part: noticing that an agent stopped a while ago to ask me a question, and has been sitting there waiting ever since.

So I built Klieg. A klieg light is the bright stage light you point at whoever matters right now. That's the job: point a light at the agent that needs me.

## What Klieg is

Klieg watches and steers herdr agents and OpenRig rigs from one place. It doesn't run agents itself. It reads what herdr, OpenRig and GitHub already know, using the `herdr`, `ssh`, `rig` and `gh` commands I already have set up, and puts it all together: who is working, who is stuck, and who is waiting on me.

Every agent gets one of six states, whatever it runs on: `working`, `blocked`, `idle`, `done`, `unknown` or `stopped`. `blocked` is the one I care about most. It means the agent is waiting on a person: a permission, a question, a folder-trust screen or a usage-credit prompt. When Klieg knows why, it says so.

herdr reports Claude Code's first-run "do you trust this folder" screen as idle, not blocked, so Klieg reads the pane and marks it blocked itself. OpenRig reports a billing screen as an ordinary permission prompt, so Klieg reads each blocked seat's screen and labels those `billing`, because only I should answer them.

Klieg has no server of its own and makes no network requests itself. It uses my existing ssh, herdr and `gh` sign-ins, and never asks for, stores or sends a token or password.

## One core, three surfaces

![One core, three surfaces: the app, klieg status and the MCP server showing the same snapshot](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/surfaces.svg)

Underneath there's one core library. Its Collector builds a single snapshot of herdr agents, OpenRig seats, the OpenRig queue and open pull requests. Three surfaces show that same snapshot.

**The Mac app.** It looks like herdr, not like a typical Mac app: a sidebar of spaces (each herdr workspace or OpenRig rig, with its folder and branch), the agents in the current space with the ones that need me first, and tabs. Every agent tab is a real terminal, so one click opens that agent's live session. There's a timeline, a pull requests panel, settings, and a menu-bar icon that shows how many agents need me.

![The Board: every herdr agent and OpenRig seat with its state](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/board.png)

![Needs You: the agents waiting on me](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/needs-you.png)

![The Timeline](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/timeline.png)

![Open pull requests with CI and signing status](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/pull-requests.png)

(These screenshots show the app's first design. It has since moved to the herdr-style layout I just described, and new screenshots are on the list.)

**The `klieg` CLI.** `klieg status` prints every agent, the open OpenRig queue, open PRs and who needs me, with the command that opens each waiting agent. `klieg timeline --watch` prints what changes as it happens. I can also prompt or read a herdr agent straight from a shell.

**The MCP server.** `klieg mcp` lets Claude see and drive my agents too. It has 12 tools: four that only read (status, timeline, an agent's screen, pull requests) and eight that act (prompt an agent, queue a goal for an OpenRig seat, start and stop agents, bring rigs up and down, answer a prompt, merge a PR). `klieg mcp install` registers it with Claude Code and Claude Desktop in one step.

![How a snapshot is made: herdr, OpenRig and GitHub flow into the Collector, OpenRig drops out and recovers](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/dataflow.svg)

One detail I like: if one source can't be reached, the others keep flowing. When OpenRig dropped out with an ssh "Host key verification failed", Klieg said so, kept showing herdr and GitHub, and kept the OpenRig seats on screen so they didn't suddenly look stopped.

## The guardrails

Giving a model the ability to type into my agents and merge my PRs needs care. These are the rules Klieg follows.

![Klieg's guardrails: merge waits for green and signed, billing prompts are refused, the app asks first](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/guardrails.svg)

- **Read-only mode.** With `readOnly` on (in Settings, the config file or `KLIEG_READ_ONLY=1`), the MCP server refuses every action tool and changes nothing. The app turns its action buttons off. Reading still works.
- **Confirmations.** In the app, stopping a seat and merging a PR each ask me first, and answering a prompt shows me the screen before I type. Over MCP, the four destructive tools are marked destructive so the client can ask me first, and Klieg's server instructions tell Claude to confirm with me.
- **Only green, signed PRs get merged.** Klieg refuses to merge a PR that is closed, a draft, has no checks, has a failed or running check, or whose head commit isn't verified by GitHub. The merge is pinned to the exact commit Klieg checked, so a push in between makes it fail. Over MCP it only merges in the repos I list.
- **Billing prompts are mine.** Before answering a prompt, Klieg reads the agent's screen again and refuses if it mentions things like usage credits, billing or a spending limit.
- **Text on screen can't become a flag.** Values that start with `-` are refused before anything runs, so an agent can't talk a model into slipping an option into a command.

## The fun part: Klieg watched itself being built

Klieg was built by three builders working at the same time:

- **A herdr agent** in a herdr pane on the herdr VM built the herdr client, the Timeline and the CLI.
- **An OpenRig rig** on the OpenRig VM, with a builder seat and a reviewer seat, built the OpenRig and GitHub clients and the MCP server. The reviewer checked each change before it was opened as a PR.
- **Claude Code on my Mac mini** built the skeleton, the app and everything macOS-only.

Each piece arrived as its own pull request against `main`, planned milestone by milestone in [ROADMAP.md](https://github.com/ry-ops/klieg/blob/main/ROADMAP.md), with shared rules in [AGENTS.md](https://github.com/ry-ops/klieg/blob/main/AGENTS.md): stay in your own files, build on Linux, test against recorded output and never a live agent, and never merge your own work.

The best part is that the agents writing Klieg showed up on its own Board and Timeline as they worked. The first PR, the herdr client, timeline and CLI, opened at 19:59 UTC on October 31 and was merged at 20:01. By the evening of November 1, 19 pull requests had been merged: the clients, the MCP server, the app, MCP registration, an icon, the animated visuals in this post, a security hardening pass, and the move to the herdr-style design.

![Klieg's Timeline filling in with the real events of the day it was built](https://raw.githubusercontent.com/ry-ops/klieg/main/docs/images/timeline.svg)

That animation is real: OpenRig seats handing each other queue items, the herdr agent starting work, then the first PRs opening, passing their checks and being merged, in the same words Klieg's Timeline uses.

## Try it

Klieg's app needs a Mac and the Command Line Tools, not the Xcode app. The CLI and MCP server also run on Linux. The README covers setup, configuration and exactly what each action can do.

**https://github.com/ry-ops/klieg**
