# herdr fixtures

Recorded from herdr 0.9.5 on the herdr host with read-only commands (`herdr --session work …`):

- `api-snapshot.json`: `api snapshot`
- `agent-list.json`, `agent-get.json`: `agent list`, `agent get m1`
- `pane-list.json`, `workspace-list.json`: `pane list`, `workspace list`
- `pane-read-shell.txt`: `pane read w1:p1` (a plain shell)
- `agent-read-working.txt`: `agent read m1 --source detection` (Claude Code mid-turn)
- `error-agent-not-found.json`: stderr of `agent get nosuch`

Hand-built, because the session had no such state while recording and we may not create it:

- `api-snapshot-mixed.json`: the recorded snapshot with more agents (idle, blocked, done, unnamed) and workspaces.
- `trust-prompt.txt`: Claude Code's first-run folder-trust screen, using the wording from the installed Claude Code binary.
- `idle-prompt.txt`: Claude Code waiting at its prompt.
- `workspace-create.json`: the `workspace create` reply shape described by `herdr --skill` (`.result.workspace`, `.result.tab`, `.result.root_pane`).
