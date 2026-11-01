"""builtby.svg: how Klieg was built.

Three builders worked at once: the herdr agent m1, the OpenRig rig klieg-pair (dev-build building,
dev-review checking, work handed back and forth), and Claude Code on Ryan's Mac. Each one's pull
requests land on main in the order they merged, from the M0 skeleton (committed straight to main)
to the v0.1.0 release. Numbers and titles are from `gh pr list -R ry-ops/klieg --state merged`,
short SHAs from `git log main`. #10 (the visuals setup) merged after the release, so it isn't here.

Who built what: herdr agent #1, #5 (built on the herdr VM), #7; klieg-pair #3, #9;
the Mac M0, #2, #4, #6 (its PR says it picks up #5's "left for the Mac"), #8."""
from .common import (AMBER, AMBER_SOFT, CARD, CARD2, DIM, EDGE, FAINT, SOURCE, STATUS, TEXT,
                     Timeline, badge, dots, esc, frame, svg)

W, H = 1280, 640
D = 16.0
MAC = "#ffc861"
COLOR = {"herdr": SOURCE["herdr"], "pair": SOURCE["openrig"], "mac": MAC}

# (builder, label, short sha on main, PR title), in merge order.
LANDED = [
    ("mac", "M0", "4e8d5e5", "Klieg skeleton"),
    ("herdr", "#1", "8bbf864", "M1: herdr client, timeline and CLI"),
    ("mac", "#2", "558911e", "M3 (part 1): live Board, Needs You and Timeline"),
    ("pair", "#3", "422dbb6", "M2: OpenRig client, GitHub client and the MCP server"),
    ("mac", "#4", "62732f1", "M3 (part 2): OpenRig, PRs, Settings and actions in the app"),
    ("herdr", "#5", "123555f", "M3b: Collector, and herdr agents behind the MCP tools"),
    ("mac", "#6", "6a890d4", "App: read through the shared Collector"),
    ("herdr", "#7", "5f52300", "M4: klieg mcp install, uninstall and status"),
    ("mac", "#8", "034d542", "M4: app icon and screenshots"),
    ("pair", "#9", "ce05f14", "M4: README for 0.1.0"),
]
# The reviewer's approvals that cleared klieg-pair's two PRs.
APPROVED = {"#3": "e20ecd5", "#9": "39a5ccb"}

CW, CY, CH = 394, 64, 206
CX = {"herdr": 28, "pair": 443, "mac": 858}
T0, STEP = 0.6, 1.15
LOG_X, LOG_Y, LOG_STEP = 28, 292, 24


def pill(x, y, text, color, mono=False, cls=""):
    w = 22 + (7.8 if mono else 7.4) * len(text)
    c = f' class="{cls}"' if cls else ""
    return (f'<g{c}><rect x="{x}" y="{y}" width="{w:.0f}" height="26" rx="13" fill="{color}" fill-opacity=".14" stroke="{color}" stroke-opacity=".5"/>'
            f'<text x="{x + 11}" y="{y + 17.5}" class="{"mono" if mono else "sans"}" font-size="13" font-weight="600" fill="{color}">{esc(text)}</text></g>'), w


def card(key, title, sub):
    x, c = CX[key], COLOR[key]
    return (f'<rect x="{x}" y="{CY}" width="{CW}" height="{CH}" rx="14" fill="{CARD}" stroke="{EDGE}"/>'
            f'<rect x="{x}" y="{CY + 14}" width="4" height="40" rx="2" fill="{c}"/>'
            f'<text x="{x + 22}" y="{CY + 36}" class="sans" font-size="16" font-weight="700" fill="{TEXT}">{esc(title)}</text>'
            f'<text x="{x + 22}" y="{CY + 56}" class="sans" font-size="12" fill="{DIM}">{esc(sub)}</text>')


def build():
    tl = Timeline(D, fade=0.4, prefix="b")
    b = [frame(W, H, "How Klieg was built"), dots(W, H)]

    b.append(card("herdr", "A herdr agent", "m1, in herdr pane w3:p1 on the herdr VM"))
    b.append(card("pair", "An OpenRig rig: klieg-pair", "a builder and a reviewer on the open-rig VM"))
    b.append(card("mac", "Claude Code on the Mac", "on Ryan's Mac mini: everything macOS-only"))

    # herdr: the agent.
    x = CX["herdr"]
    p, _ = pill(x + 22, CY + 78, "m1", COLOR["herdr"], mono=True)
    b.append(p)
    b.append(f'<text x="{x + 76}" y="{CY + 96}" class="sans" font-size="12" fill="{DIM}">herdr · claude</text>')
    b.append(badge(x + CW - 22, CY + 92, "working"))

    # klieg-pair: dev-build and dev-review handing work back and forth.
    x = CX["pair"]
    p, wb = pill(x + 22, CY + 78, "dev-build", COLOR["pair"], mono=True)
    b.append(p)
    p, wr = pill(x + CW - 22 - 112, CY + 78, "dev-review", COLOR["pair"], mono=True)
    b.append(p)
    a0, a1 = x + 22 + wb + 8, x + CW - 22 - 112 - 8
    b.append(f'<path d="M{a0} {CY + 86} H{a1}" stroke="{FAINT}" stroke-width="1.4" fill="none"/>'
             f'<path d="M{a1 - 6} {CY + 82} l6 4 l-6 4" stroke="{FAINT}" stroke-width="1.4" fill="none"/>'
             f'<path d="M{a0} {CY + 98} H{a1}" stroke="{FAINT}" stroke-width="1.4" fill="none"/>'
             f'<path d="M{a0 + 6} {CY + 94} l-6 4 l6 4" stroke="{FAINT}" stroke-width="1.4" fill="none"/>')
    mid = (a0 + a1) / 2
    for i, (key, label, sha, title) in enumerate(LANDED):
        if key != "pair":
            continue
        t = T0 + i * STEP
        go, back = tl.appear(t - 1.0, until=t - 0.5, ease=0.15), tl.appear(t - 0.5, until=t + 0.3, ease=0.15)
        b.append(f'<g class="{go}"><path d="M{a0} {CY + 86} H{a1}" stroke="{AMBER}" stroke-width="2.2"/>'
                 f'<text x="{mid}" y="{CY + 76}" text-anchor="middle" class="sans" font-size="11" font-weight="600" fill="{AMBER}">check {label}</text></g>')
        b.append(f'<g class="{back}"><path d="M{a0} {CY + 98} H{a1}" stroke="{STATUS["done"]}" stroke-width="2.2"/>'
                 f'<text x="{mid}" y="{CY + 116}" text-anchor="middle" class="sans" font-size="11" font-weight="600" fill="{STATUS["done"]}">approved {APPROVED[label]}</text></g>')

    # Mac: Claude Code.
    x = CX["mac"]
    p, _ = pill(x + 22, CY + 78, "Claude Code", COLOR["mac"])
    b.append(p)
    b.append(f'<text x="{x + 136}" y="{CY + 96}" class="sans" font-size="12" fill="{DIM}">the app, icon and screenshots</text>')

    # --- main: the log the PRs land in.
    b.append(f'<rect x="{LOG_X}" y="{LOG_Y}" width="{W - 56}" height="{H - LOG_Y - 28}" rx="14" fill="{CARD}" stroke="{EDGE}"/>')
    b.append(f'<text x="{LOG_X + 22}" y="{LOG_Y + 30}" class="mono" font-size="14" font-weight="700" fill="{TEXT}">main</text>')
    b.append(f'<text x="{LOG_X + 70}" y="{LOG_Y + 30}" class="sans" font-size="12" fill="{FAINT}">in the order things merged, 2026-10-31 to 2026-11-01</text>')

    slots = {k: 0 for k in CX}
    for i, (key, label, sha, title) in enumerate(LANDED):
        t = T0 + i * STEP
        c = COLOR[key]
        # The chip in its builder's card.
        cx = CX[key] + 22 + slots[key] * 64
        slots[key] += 1
        cy = CY + 150
        b.append(f'<g class="{tl.hold(t)}"><rect x="{cx}" y="{cy}" width="56" height="30" rx="8" fill="{c}" fill-opacity=".16" stroke="{c}" stroke-opacity=".6"/>'
                 f'<text x="{cx + 28}" y="{cy + 20}" text-anchor="middle" class="mono" font-size="13.5" font-weight="700" fill="{c}">{label}</text></g>')
        # It travels down to main.
        ly = LOG_Y + 62 + i * LOG_STEP
        dx, dy = (LOG_X + 30) - (cx + 28), (ly - 4) - (cy + 15)
        b.append(f'<g class="{tl.appear(t + 0.1, until=t + 0.75, ease=0.1)}"><circle class="{tl.slide(t + 0.15, t + 0.7, dx, dy)}" '
                 f'cx="{cx + 28}" cy="{cy + 15}" r="6" fill="{c}"/></g>')
        # Its line on main, joined to the one before.
        g = tl.hold(t + 0.65)
        if i:
            b.append(f'<line class="{g}" x1="{LOG_X + 30}" y1="{ly - 4 - LOG_STEP}" x2="{LOG_X + 30}" y2="{ly - 4}" stroke="{EDGE}" stroke-width="2"/>')
        b.append(f'<g class="{g}"><circle cx="{LOG_X + 30}" cy="{ly - 4}" r="5" fill="{c}"/>'
                 f'<text x="{LOG_X + 46}" y="{ly}" class="mono" font-size="12.5" fill="{FAINT}">{sha}</text>'
                 f'<text x="{LOG_X + 116}" y="{ly}" class="mono" font-size="12.5" font-weight="700" fill="{c}">{label}</text>'
                 f'<text x="{LOG_X + 152}" y="{ly}" class="sans" font-size="13" fill="{TEXT}">{esc(title)}</text></g>')
    last = LOG_Y + 62 + (len(LANDED) - 1) * LOG_STEP

    # --- The release.
    tr = T0 + len(LANDED) * STEP + 0.3
    rx, ry = 760, LOG_Y + 62
    g = tl.hold(tr)
    b.append(f'<g class="{g}"><rect x="{rx}" y="{ry - 18}" width="460" height="128" rx="12" fill="{CARD2}" stroke="{AMBER}" stroke-opacity=".6"/>'
             f'<text x="{rx + 22}" y="{ry + 16}" class="mono" font-size="26" font-weight="800" fill="{AMBER}">v0.1.0</text>'
             f'<text x="{rx + 140}" y="{ry + 14}" class="sans" font-size="15" font-weight="700" fill="{TEXT}">Klieg 0.1.0</text>'
             f'<text x="{rx + 22}" y="{ry + 46}" class="sans" font-size="12.5" fill="{DIM}">Tagged at ce05f14 (#9), released 2026-11-01 00:58 UTC,</text>'
             f'<text x="{rx + 22}" y="{ry + 66}" class="sans" font-size="12.5" fill="{DIM}">about five hours after the skeleton (19:49 UTC the day before).</text>'
             f'<text x="{rx + 22}" y="{ry + 92}" class="sans" font-size="12.5" fill="{AMBER_SOFT}">3 builders · 9 pull requests</text></g>')
    b.append(f'<line class="{g}" x1="{LOG_X + 330}" y1="{last - 4}" x2="{rx - 8}" y2="{last - 4}" stroke="{AMBER}" stroke-opacity=".5" stroke-dasharray="3 5"/>')

    # Legend, and the point of the picture.
    ly = LOG_Y + 210
    for j, (key, name, n) in enumerate([("herdr", "herdr agent", "#1 #5 #7"), ("pair", "klieg-pair", "#3 #9"), ("mac", "the Mac", "M0 #2 #4 #6 #8")]):
        yy = ly + j * 22
        b.append(f'<circle cx="{rx + 8}" cy="{yy - 4}" r="5" fill="{COLOR[key]}"/>'
                 f'<text x="{rx + 22}" y="{yy}" class="sans" font-size="12.5" fill="{TEXT}">{name}</text>'
                 f'<text x="{rx + 120}" y="{yy}" class="mono" font-size="12" fill="{DIM}">{n}</text>')
    b.append(f'<text x="{rx}" y="{ly + 84}" class="sans" font-size="12.5" fill="{DIM}">Klieg watched itself being built: these agents were on its own Board.</text>')

    return {"builtby.svg": svg(W, H, "\n".join(b), tl.css(), "How Klieg was built",
                               "Three builders worked on Klieg at once: the herdr agent m1, the OpenRig rig klieg-pair with dev-build "
                               "building and dev-review checking, and Claude Code on the Mac. Their work lands on main in the order it "
                               "merged: the M0 skeleton, then pull requests 1 to 9, ending at the v0.1.0 release on 2026-11-01, "
                               "about five hours after the skeleton.")}
