"""board.svg: the herdr-style Klieg window at work. Spaces and agents on the left, tabs on top,
m1's live Claude Code session in a titled frame. Partway through, dev-review stops to ask for
approval: its dot turns pink, it jumps to the top of the agents list, the key-hint bar says
"1 needs you", the tab switches to it, it's answered, and it goes back to work."""
from .common import MONO, Timeline, esc, svg

W, H = 1280, 640
D = 14.0
BG, PANEL, RAISED, BORDER = "#131418", "#17181d", "#1d1e25", "#2b2d38"
TEXT, DIM, FAINT = "#e4e4ea", "#8b8d9b", "#555867"
LAV, INK = "#c3a6ff", "#1a1426"
WORK, BLOCK, DONE, IDLE = "#f2c94c", "#f06292", "#6fdc8c", "#9aa0ad"
LIME = "#c3e88d"
SIDEBAR = 300


def t(x, y, s, size=14, fill=TEXT, weight="400", cls=""):
    c = f' class="{cls}"' if cls else ""
    return f'<text{c} x="{x}" y="{y}" font-family="{esc(MONO)}" font-size="{size}" font-weight="{weight}" fill="{fill}">{esc(s)}</text>'


def dot(cx, cy, color, hollow=False, cls=""):
    c = f' class="{cls}"' if cls else ""
    if hollow:
        return f'<circle{c} cx="{cx}" cy="{cy}" r="5" fill="none" stroke="{color}" stroke-width="1.6"/>'
    return f'<circle{c} cx="{cx}" cy="{cy}" r="5" fill="{color}"/>'


def build():
    tl = Timeline(D, fade=0.4, prefix="b")
    b = [f'<rect width="{W}" height="{H}" rx="14" fill="{BG}"/>',
         f'<rect x=".5" y=".5" width="{W - 1}" height="{H - 1}" rx="13.5" fill="none" stroke="{BORDER}"/>']
    # Title bar.
    b.append(f'<rect width="{W}" height="34" rx="14" fill="{PANEL}"/><rect y="20" width="{W}" height="14" fill="{PANEL}"/>')
    for i, c in enumerate(["#ff5f57", "#febc2e", "#28c840"]):
        b.append(f'<circle cx="{22 + i * 20}" cy="17" r="6" fill="{c}"/>')
    b.append(t(90, 22, "Klieg", 13, DIM, "600"))
    b.append(f'<line x1="0" y1="34" x2="{W}" y2="34" stroke="{BORDER}"/>')

    # --- Sidebar.
    b.append(f'<rect x="0" y="34" width="{SIDEBAR}" height="{H - 34 - 30}" fill="{PANEL}"/>')
    b.append(f'<line x1="{SIDEBAR}" y1="34" x2="{SIDEBAR}" y2="{H - 30}" stroke="{BORDER}"/>')
    b.append(t(22, 66, "spaces", 13, DIM))
    spaces = [("klieg-pair", "100.67.70.121 · 2 seats"), ("klieg-m1", "~/src/klieg · main"), ("kernel", "100.67.70.121 · 3 seats")]
    for i, (name, sub) in enumerate(spaces):
        y = 92 + i * 56
        if i == 0:
            b.append(f'<rect x="10" y="{y - 18}" width="{SIDEBAR - 20}" height="50" rx="4" fill="{RAISED}"/>')
        b.append(t(46, y, name, 14.5, TEXT, "700"))
        b.append(t(46, y + 21, sub, 12, LAV))
    # klieg-pair's dot: working, then blocked while dev-review waits, then working.
    b.append(dot(28, 87, WORK, cls=tl.visible_until(4.0, 0.2)))
    b.append(dot(28, 87, BLOCK, cls=tl.appear(4.0, until=8.6, ease=0.2)))
    b.append(dot(28, 87, WORK, cls=tl.appear(8.6, ease=0.2)))
    b.append(dot(28, 143, WORK))
    b.append(dot(28, 199, IDLE, hollow=True))

    b.append(f'<line x1="0" y1="262" x2="{SIDEBAR}" y2="262" stroke="{BORDER}"/>')
    b.append(t(22, 292, "agents", 13, DIM))

    def agent_row(y, name, status, color, cls, hollow=False, selected=False):
        out = f'<g class="{cls}">' if cls else "<g>"
        if selected:
            out += f'<rect x="10" y="{y - 18}" width="{SIDEBAR - 20}" height="50" rx="4" fill="{RAISED}"/>'
        out += dot(28, y - 5, color, hollow) + t(46, y, name, 14.5, TEXT, "700")
        out += t(46, y + 21, f"{status} · claude", 12, color if not hollow else DIM) + "</g>"
        return out

    # Before: dev-build on top (working), dev-review below (idle). During: dev-review jumps to the top, blocked.
    before = tl.visible_until(4.0, 0.2)
    during = tl.appear(4.0, until=8.6, ease=0.2)
    after = tl.appear(8.6, ease=0.2)
    b.append(agent_row(318, "dev-build", "working", WORK, before, selected=True))
    b.append(agent_row(374, "dev-review", "idle", IDLE, before, hollow=True))
    b.append(agent_row(318, "dev-review", "blocked", BLOCK, during, selected=True))
    b.append(agent_row(374, "dev-build", "working", WORK, during))
    b.append(agent_row(318, "dev-build", "working", WORK, after))
    b.append(agent_row(374, "dev-review", "working", WORK, after, selected=True))

    # --- Tabs.
    tx = SIDEBAR + 1
    b.append(f'<rect x="{tx}" y="35" width="{W - tx}" height="36" fill="{PANEL}"/><line x1="{tx}" y1="71" x2="{W}" y2="71" stroke="{BORDER}"/>')
    tabs = [("seats", 90), ("dev-build", 130), ("dev-review", 140), ("+", 46)]
    xs, x = [], tx
    for name, w in tabs:
        xs.append((x, w))
        b.append(f'<line x1="{x + w}" y1="35" x2="{x + w}" y2="71" stroke="{BORDER}"/>')
        x += w
    def tab_on(i, cls):
        x0, w = xs[i]
        return (f'<g class="{cls}"><rect x="{x0}" y="35" width="{w}" height="36" fill="{LAV}"/>'
                + t(x0 + w / 2 - len(tabs[i][0]) * 4.3, 58, tabs[i][0], 14, INK, "700") + "</g>")
    for i, (name, w) in enumerate(tabs):
        b.append(t(xs[i][0] + w / 2 - len(name) * 4.3, 58, name, 14, DIM))
    b.append(tab_on(1, tl.visible_until(4.4, 0.15)))
    b.append(tab_on(2, tl.appear(4.4, until=9.4, ease=0.15)))
    b.append(tab_on(1, tl.appear(9.4, ease=0.15)))

    # --- The pane: a titled frame with a live Claude Code session.
    px, py, pw, ph = tx + 16, 92, W - tx - 32, H - 30 - 92 - 16
    def pane(title, color, lines, cls):
        out = f'<g class="{cls}">'
        out += f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="2" fill="none" stroke="{color}" stroke-width="1.6"/>'
        out += f'<rect x="{px + 10}" y="{py - 10}" width="{len(title) * 8.6 + 14}" height="20" fill="{BG}"/>'
        out += t(px + 17, py + 5, title, 14, color, "700")
        for i, (s, fill, cl) in enumerate(lines):
            out += t(px + 24, py + 42 + i * 26, s, 13.5, fill, cls=cl)
        return out + "</g>"

    build_lines = [
        ("❯ Build milestone M2: OpenRigClient, GitHubClient, the MCP server", DIM, ""),
        ("● Reading AGENTS.md and ROADMAP.md, then Sources/KliegKit…", TEXT, tl.appear(0.6, until=4.4)),
        ("● Bash(rig ps --nodes -A --full --json)", WORK, tl.appear(1.4, until=4.4)),
        ("  ⎿ 2 rigs · 6 seats", DIM, tl.appear(1.9, until=4.4)),
        ("● Write(Sources/KliegKit/OpenRig.swift)", WORK, tl.appear(2.6, until=4.4)),
        ("● Handing the change to dev-review@klieg-pair", TEXT, tl.appear(3.3, until=4.4)),
    ]
    b.append(pane("claude", LAV, build_lines, tl.visible_until(4.4, 0.15)))
    review_lines = [
        ("● Bash(swift run klieg-selftest)", WORK, ""),
        ("", TEXT, ""),
        ("  This command requires approval", BLOCK, ""),
        ("  Do you want to proceed?", TEXT, ""),
        ("  ❯ 1. Yes", TEXT, tl.visible_until(7.6, 0.1)),
        ("  ❯ 1. Yes   ← answered from Klieg", LAV, tl.appear(7.6, until=9.4, ease=0.1)),
        ("    2. Yes, and don't ask again", DIM, ""),
        ("    3. No", DIM, ""),
    ]
    b.append(pane("claude", BLOCK, review_lines, tl.appear(4.4, until=9.4, ease=0.15)))
    # Needs-you strip above the blocked pane.
    b.append(f'<g class="{tl.appear(4.6, until=8.4, ease=0.15)}"><rect x="{px}" y="{py + ph - 50}" width="{pw}" height="34" rx="4" fill="{BLOCK}" fill-opacity=".1"/>'
             + dot(px + 18, py + ph - 33, BLOCK) + t(px + 32, py + ph - 28, "needs you · It's asking to approve a command.", 13, BLOCK, "700")
             + f'<rect x="{px + pw - 96}" y="{py + ph - 46}" width="84" height="26" rx="5" fill="{LAV}"/>'
             + t(px + pw - 82, py + ph - 28, "answer…", 13, INK, "700") + "</g>")
    after_lines = [
        ("❯ Build milestone M2: OpenRigClient, GitHubClient, the MCP server", DIM, ""),
        ("● dev-review approved e20ecd5: all six review findings addressed", DONE, ""),
        ("● Bash(git push -u origin m2-openrig)", WORK, tl.appear(10.2, ease=0.2)),
        ("● Bash(gh pr create --base main …)", WORK, tl.appear(11.0, ease=0.2)),
        ("  ⎿ https://github.com/ry-ops/klieg/pull/3", LIME, tl.appear(11.6, ease=0.2)),
    ]
    b.append(pane("claude", LAV, after_lines, tl.appear(9.4, ease=0.15)))

    # --- Key-hint bar.
    b.append(f'<rect x="0" y="{H - 30}" width="{W}" height="30" fill="{PANEL}"/><line x1="0" y1="{H - 30}" x2="{W}" y2="{H - 30}" stroke="{BORDER}"/>')
    x = 18
    for k, what in [("⌘↑↓", "space"), ("⌘1-9", "tab"), ("⌘T", "shell"), ("⌘K", "commands"), ("⌘R", "refresh")]:
        b.append(t(x, H - 10, k, 12, LAV) + t(x + len(k) * 7.4 + 6, H - 10, what, 12, DIM))
        x += len(k) * 7.4 + len(what) * 7.4 + 26
    b.append(t(W - 150, H - 10, "● 1 needs you", 12, BLOCK, "700", tl.appear(4.0, until=8.6, ease=0.2)))

    return {"board.svg": svg(W, H, "\n".join(b), tl.css(), "Klieg's herdr-style window",
                             "Klieg's window: spaces and agents on the left, tabs on top, and the selected agent's live Claude Code "
                             "session in a lavender frame. dev-review stops to ask for approval: its dot turns pink, it moves to the top "
                             "of the agents list, the tab switches to it, it's answered from Klieg, and the builder pushes PR #3.")}
