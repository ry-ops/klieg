"""timeline.svg: the day Klieg was built, scrolling into the app's Timeline, newest on top.

Every line is a real event from 2026-10-31 in the exact wording Sources/KliegKit/Timeline.swift writes:
OpenRig queue items from Tests/SelfTest/Fixtures/openrig/queue-list.json, the herdr agent m1 (recorded
working at 19:54), and ry-ops/klieg PRs #1, #3 and #5 with their real open, checks and merge times from
`gh pr view`. Times are UTC. The row layout follows the app's TimelineView: time, icon, text, source."""
from .common import (ACCENT, AMBER, CARD2, DIM, EDGE, FAINT, SOURCE, STATUS, TEXT,
                     Timeline, dots, esc, frame, svg, window)

W, H = 1280, 640
D = 16.0

Q1 = "qitem-20261031191525-363261dd"
Q2 = "qitem-20261031195841-98147cee9e1fdb9a"
EVENTS = [  # time (UTC), source, kind, text: oldest first
    ("19:14", "openrig", "queued", "dev-build@unifi-pair handed dev-review@unifi-pair a queue item: Review mcp<2 cap and uv.lock refresh (commit 52b1015) before PR"),
    ("19:15", "openrig", "queued", "dev-review@unifi-pair handed dev-build@unifi-pair a queue item: Approved 52b1015 (mcp<2 cap and lock refresh), one optional Dependabot advisory"),
    ("19:17", "openrig", "queueStateChanged", f"dev-build@unifi-pair's queue item {Q1} is now done"),
    ("19:54", "herdr", "statusChanged", "m1 (claude) started working"),
    ("19:58", "openrig", "queued", "ryan@mac handed dev-build@klieg-pair a queue item"),
    ("19:58", "openrig", "queueStateChanged", f"dev-build@klieg-pair's queue item {Q2} is now in-progress"),
    ("19:59", "github", "prOpened", "ry-ops/klieg#1 opened: M1: herdr client, timeline and CLI"),
    ("20:00", "github", "checksFinished", "ry-ops/klieg#1 checks finished: success"),
    ("20:01", "github", "merged", "ry-ops/klieg#1 was merged"),
    ("20:15", "github", "prOpened", "ry-ops/klieg#3 opened: M2: OpenRig client, GitHub client and the MCP server"),
    ("20:17", "github", "checksFinished", "ry-ops/klieg#3 checks finished: success"),
    ("20:17", "github", "merged", "ry-ops/klieg#3 was merged"),
    ("20:23", "github", "prOpened", "ry-ops/klieg#5 opened: M3b: Collector, and herdr agents behind the MCP tools"),
    ("20:24", "github", "checksFinished", "ry-ops/klieg#5 checks finished: success"),
    ("20:24", "github", "merged", "ry-ops/klieg#5 was merged"),
]
START = 3          # rows already showing when the loop begins
FIRST, STEP = 0.8, 0.95    # the next event arrives every STEP seconds

WRAP = 104         # characters per line before a row wraps, at 13.5 px
ONE, TWO = 40, 60  # row heights


def wrap(text):
    if len(text) <= WRAP:
        return [text]
    cut = text.rfind(" ", 0, WRAP)
    return [text[:cut], text[cut + 1:]]


def icon(kind, x, y):
    """Small stand-ins for the app's SF Symbols: circle.fill, arrow.triangle.pull, arrow.triangle.merge."""
    c = STATUS["blocked"] if kind == "needsPerson" else ACCENT
    if kind == "prOpened":
        return (f'<g fill="none" stroke="{c}" stroke-width="1.8"><circle cx="{x - 4}" cy="{y - 6}" r="2.4"/><circle cx="{x - 4}" cy="{y + 6}" r="2.4"/>'
                f'<path d="M{x - 4} {y - 3.5} v7"/><circle cx="{x + 5}" cy="{y + 6}" r="2.4"/><path d="M{x + 5} {y + 3.5} v-6 q0 -4 -4 -4 h-2"/></g>')
    if kind == "merged":
        return (f'<g fill="none" stroke="{c}" stroke-width="1.8"><circle cx="{x - 4}" cy="{y - 6}" r="2.4"/><circle cx="{x - 4}" cy="{y + 6}" r="2.4"/>'
                f'<circle cx="{x + 5}" cy="{y + 2}" r="2.4"/><path d="M{x - 4} {y - 3.5} v7 M{x - 4} {y - 3} q0 5 6.5 5"/></g>')
    return f'<circle cx="{x}" cy="{y}" r="5" fill="{c}"/>'


def build():
    tl = Timeline(D, fade=0.4, prefix="t")
    b = [frame(W, H, "Timeline"), dots(W, H)]

    wx, wy, ww, wh = 40, 60, 1200, 556
    b.append(window(wx, wy, ww, wh, "Klieg — Timeline"))
    # Sidebar, as in the app.
    b.append(f'<rect x="{wx + 1}" y="{wy + 35}" width="190" height="{wh - 36}" fill="{CARD2}"/>')
    for i, s in enumerate(["Board", "Needs You", "Timeline", "Pull Requests", "Settings"]):
        ry = wy + 58 + i * 34
        if s == "Timeline":
            b.append(f'<rect x="{wx + 10}" y="{ry - 18}" width="170" height="28" rx="7" fill="{ACCENT}" fill-opacity=".85"/>')
        b.append(f'<text x="{wx + 24}" y="{ry + 1}" class="sans" font-size="13.5" font-weight="{600 if s == "Timeline" else 500}" fill="{TEXT if s == "Timeline" else DIM}">{s}</text>')

    lx, lw = wx + 210, ww - 230
    b.append(f'<text x="{lx}" y="{wy + 72}" class="sans" font-size="22" font-weight="800" fill="{TEXT}">Timeline</text>')
    b.append(f'<text x="{lx + lw}" y="{wy + 72}" text-anchor="end" class="sans" font-size="12" fill="{FAINT}">Oct 31, 2026 · UTC · newest first</text>')
    top = wy + 92
    view_h = wy + wh - 14 - top
    b.append(f'<defs><clipPath id="list"><rect x="{lx - 10}" y="{top}" width="{lw + 20}" height="{view_h}"/></clipPath></defs>')

    # Static layout: newest at the top. Row k's offset from the top of the list.
    order = list(range(len(EVENTS)))[::-1]
    offset, y = {}, 0
    for k in order:
        offset[k] = y
        y += TWO if len(wrap(EVENTS[k][3])) > 1 else ONE

    arrive = {k: FIRST + (k - START) * STEP for k in range(START, len(EVENTS))}
    rows = []
    for k in order:
        t, src, kind, text = EVENTS[k]
        ry = top + offset[k]
        lines = wrap(text)
        rh = TWO if len(lines) > 1 else ONE
        if k in arrive:   # a soft amber wash when the row lands
            rows.append(f'<rect class="{tl.appear(arrive[k] + 0.2, until=arrive[k] + 1.6, ease=0.2)}" x="{lx - 8}" y="{ry + 2}" width="{lw + 16}" height="{rh - 4}" rx="8" fill="{AMBER}" fill-opacity=".09"/>')
        rows.append(f'<text x="{lx}" y="{ry + 25}" class="mono" font-size="12" fill="{DIM}">{t}</text>')
        rows.append(icon(kind, lx + 76, ry + 21))
        for i, ln in enumerate(lines):
            rows.append(f'<text x="{lx + 96}" y="{ry + 25.5 + i * 19}" class="sans" font-size="13.5" fill="{TEXT}">{esc(ln)}</text>')
        rows.append(f'<circle cx="{lx + lw - 62}" cy="{ry + 21}" r="3.5" fill="{SOURCE[src]}"/>'
                    f'<text x="{lx + lw}" y="{ry + 25}" text-anchor="end" class="sans" font-size="12" fill="{DIM}">{src}</text>')
        rows.append(f'<path d="M{lx} {ry + rh} h{lw}" stroke="{EDGE}" stroke-opacity=".7"/>')

    # The list slides down one row each time an event arrives. Its resting position (offset 0) is the
    # full list, which is also what reduced motion shows.
    frames, pct = [], lambda s: f"{max(0.0, min(100.0, s / D * 100)):.3f}%"
    pos = -offset[START - 1]
    frames.append(f"0%{{transform:translate(0,{pos}px)}}")
    for k in range(START, len(EVENTS)):
        a = arrive[k]
        frames.append(f"{pct(a)}{{transform:translate(0,{pos}px)}}")
        pos = -offset[k]
        frames.append(f"{pct(a + 0.45)}{{transform:translate(0,{pos}px)}}")
    frames.append("100%{transform:translate(0,0px)}")
    css = (tl.css() + f"\n@keyframes tscroll{{{''.join(frames)}}}"
           f".tscroll{{animation:tscroll {D}s ease-in-out infinite}}")
    b.append(f'<g clip-path="url(#list)"><g class="tscroll">{"".join(rows)}</g></g>')
    assert arrive[len(EVENTS) - 1] + 0.45 < D - 2, "leave the full list up for a moment before the loop restarts"

    return {"timeline.svg": svg(W, H, "\n".join(b), css, "Klieg: the Timeline",
                                "Klieg's Timeline filling in with the real events of the day it was built, newest on top: OpenRig seats "
                                "handing each other queue items, the herdr agent m1 starting work, then pull requests ry-ops/klieg #1, #3 "
                                "and #5 each opening, finishing their checks with success, and being merged.")}
