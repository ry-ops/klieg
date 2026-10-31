# Rules for agents working on Klieg

You're one of several builders working on this repo at the same time. Read ROADMAP.md for who owns what.

- **Stay in your milestone's files.** If you need a change in a shared file (`Models.swift`, `Shell.swift`, `Config.swift`, `Package.swift`), keep it small and additive and say so in the PR body.
- **KliegKit, KliegServer, the CLI and the self-test must build on Linux.** Use Foundation only: no AppKit, SwiftUI, Combine or Apple-only APIs there.
- **Before every commit:** `swift build --product klieg` and `swift run klieg-selftest` must pass. Tests use recorded JSON fixtures, never a live herdr, rig or GitHub.
- **Branch, PR, never main.** One branch per milestone (`m1-herdr`, `m2-openrig`), opened as a PR with `gh pr create`. Commits are signed automatically. Never merge, force-push someone else's branch, or close PRs.
- **No Xcode.** Nothing may require the Xcode app.
- **Plain language** in docs, comments and PR bodies. End PR bodies with: 🤖 Generated with [Claude Code](https://claude.com/claude-code)
