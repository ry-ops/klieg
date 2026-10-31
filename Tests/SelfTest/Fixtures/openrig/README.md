# OpenRig and GitHub fixtures

Recorded on the open-rig VM on 2026-10-31 with read-only commands, then trimmed by hand. Resume tokens,
resume commands, process ids and the credit balance were removed.

| File | From | Notes |
|---|---|---|
| `ps-nodes.json` | `rig ps --nodes -A --full --json` | Five of the eight seats, keeping the fields Klieg reads. Covers needs-input, working, idle, an infrastructure terminal and an exited seat. |
| `ps-nodes-compact.json` | `rig ps --nodes -A --json` | The compact shape, which has no `activityState`, so the client's fallback is tested too. |
| `queue-list.json` | `rig queue list -a -A --json` | Real rows: in progress, done and handed off. |
| `capture-credits.json` | `rig capture operator-agent@kernel --lines 15 --json` | A real "usage credits" prompt. Balance replaced with `$XX.XX`. |
| `capture-permission.json` | hand-written | A Claude Code Bash permission prompt in the same JSON shape. No seat showed one while recording. |
| `gh-pr-list.json` | `gh pr view 56 --json …` on ry-ops/unifi-mcp-server | #56 is the real record, set to `OPEN` with one check changed to `SKIPPED`. #57–#59 are made up to cover pending, failing and no checks. |
| `gh-commit-verification.json` | `gh api repos/…/commits/<sha> -q .commit.verification` | Payload and signature dropped. |
