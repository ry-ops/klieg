"""hero.svg: a stage light sweeps across four agent cards while their states change.
One cycle tells the story Klieg is for: agents work, one stops to ask you something,
the light finds it, the menu-bar beacon counts it, you answer, it finishes."""
from .common import (AMBER, AMBER_SOFT, ACCENT, BG, CARD2, CREAM, DIM, EDGE, FAINT, STATUS, TEXT,
                     Timeline, agent_card, badge, dots, esc, frame, svg)

W, H = 1280, 440
D = 12.0


def build():
    tl = Timeline(D, fade=0.4, prefix="h")
    b = []
    b.append(frame(W, H))
    b.append(dots(W, H))

    # --- Left: name and pitch.
    b.append(f'<text x="64" y="150" class="sans" font-size="64" font-weight="800" fill="{TEXT}" letter-spacing="-1.5">Klieg</text>')
    b.append(f'<text x="66" y="194" class="sans" font-size="22" fill="{AMBER_SOFT}">A spotlight on your coding agents.</text>')
    lines = ["Watch and steer herdr agents and OpenRig rigs", "from a Mac app, a CLI, and an MCP server for Claude."]
    for i, ln in enumerate(lines):
        b.append(f'<text x="66" y="{236 + i * 26}" class="sans" font-size="16" fill="{DIM}">{esc(ln)}</text>')
    chips = [("herdr", "#5ac8fa"), ("OpenRig", "#ff6fae"), ("GitHub", "#b9c0d0")]
    x = 66
    for name, c in chips:
        w = 26 + 8.6 * len(name)
        b.append(f'<rect x="{x}" y="304" width="{w:.0f}" height="30" rx="15" fill="{c}" fill-opacity=".12" stroke="{c}" stroke-opacity=".45"/>'
                 f'<circle cx="{x + 14}" cy="319" r="4" fill="{c}"/>'
                 f'<text x="{x + 24}" y="324" class="sans" font-size="13" font-weight="600" fill="{TEXT}">{name}</text>')
        x += w + 10

    # --- Menu-bar beacon (top right): count of agents needing you.
    bx, by = 1190, 44
    b.append(f'<rect x="{bx - 46}" y="{by - 18}" width="92" height="34" rx="9" fill="{CARD2}" stroke="{EDGE}"/>')
    b.append(f'<path d="M{bx - 30} {by + 6} l8 -18 h6 l8 18 z" fill="{FAINT}"/>')   # dim beacon
    lit = tl.appear(4.6, until=8.4)
    b.append(f'<g class="{lit}"><path d="M{bx - 30} {by + 6} l8 -18 h6 l8 18 z" fill="{STATUS["blocked"]}"/>'
             f'<text x="{bx}" y="{by + 5}" class="sans" font-size="15" font-weight="800" fill="{STATUS["blocked"]}">1</text></g>')
    b.append(f'<text x="{bx}" y="{by + 5}" class="sans {tl.visible_until(4.6)}" font-size="13" fill="{DIM}">0</text>')

    # --- The stage: four agent cards.
    cards = [
        ("m1", "herdr", "~/src/klieg", 640, 120, [(0, "idle"), (1.2, "working"), (9.6, "done")]),
        ("dev-build@klieg-pair", "openrig", "~/src/klieg", 940, 120, [(0, "working"), (6.8, "idle"), (8.8, "working")]),
        ("dev-review@klieg-pair", "openrig", "~/src/klieg", 640, 268, [(0, "idle"), (2.4, "working"), (4.4, "blocked"), (7.4, "working"), (10.4, "done")]),
        ("queue-worker@kernel", "openrig", "~/.openrig/workspace", 940, 268, [(0, "idle")]),
    ]
    cw, ch = 280, 120
    for name, src, cwd, x, y, states in cards:
        b.append(agent_card(x, y, cw, ch, name, src, cwd=cwd))
        for i, (t, st) in enumerate(states):
            end = states[i + 1][0] if i + 1 < len(states) else None
            if t == 0 and end is None:
                b.append(badge(x + cw - 14, y + 52, st))
            elif t == 0:
                b.append(badge(x + cw - 14, y + 52, st, tl.visible_until(end, ease=0.15)))
            else:
                b.append(badge(x + cw - 14, y + 52, st, tl.appear(t, until=end, ease=0.15)))
    # The card that needs you glows, and says why.
    gx, gy = 640, 268
    glow = tl.pulse(4.4, 7.4)
    b.append(f'<rect class="{glow}" x="{gx - 3}" y="{gy - 3}" width="{cw + 6}" height="{ch + 6}" rx="14" fill="none" stroke="{STATUS["blocked"]}" stroke-width="2.5"/>')
    why = tl.appear(4.6, until=7.4)
    b.append(f'<text class="sans {why}" x="{gx + 20}" y="{gy + 100}" font-size="12.5" font-weight="600" fill="{STATUS["blocked"]}">It\'s asking to approve a command.</text>')
    # You answer it: a cursor click and an "Answer" chip.
    ans = tl.appear(6.6, until=7.6)
    b.append(f'<g class="{ans}"><rect x="{gx + 186}" y="{gy + 84}" width="78" height="26" rx="7" fill="{ACCENT}"/>'
             f'<text x="{gx + 225}" y="{gy + 102}" text-anchor="middle" class="sans" font-size="12.5" font-weight="700" fill="white">Answer</text></g>')

    # --- The light: a lamp top-centre-right and a beam that sweeps from card to card,
    # lingering on the blocked one.
    lx, ly = 900, 30
    beam = tl.rotate([(0, 32), (1.2, 32), (2.4, -8), (3.6, -8), (4.4, 22), (7.6, 22), (8.6, -26), (9.6, 32), (D, 32)], lx, ly)
    b.append('<defs><linearGradient id="beam" x1="0" y1="0" x2="0" y2="1">'
             f'<stop offset="0" stop-color="{CREAM}" stop-opacity=".55"/><stop offset="1" stop-color="{AMBER}" stop-opacity=".05"/>'
             '</linearGradient>'
             f'<radialGradient id="pool"><stop offset="0" stop-color="{AMBER}" stop-opacity=".35"/><stop offset="1" stop-color="{AMBER}" stop-opacity="0"/></radialGradient>'
             '</defs>')
    b.append(f'<g class="{beam}" style="mix-blend-mode:screen">'
             f'<path d="M{lx - 12} {ly + 8} L{lx - 110} {ly + 295} L{lx + 110} {ly + 295} L{lx + 12} {ly + 8} Z" fill="url(#beam)"/>'
             f'<ellipse cx="{lx}" cy="{ly + 290}" rx="140" ry="40" fill="url(#pool)"/></g>')
    b.append(f'<g transform="translate({lx} {ly}) rotate(0)"><rect x="-26" y="-14" width="52" height="24" rx="6" fill="#cfd3dc"/>'
             f'<rect x="-18" y="8" width="36" height="5" rx="2" fill="{CREAM}"/></g>')
    b.append(f'<line x1="{lx}" y1="0" x2="{lx}" y2="{ly - 14}" stroke="{EDGE}" stroke-width="3"/>')

    return {"hero.svg": svg(W, H, "\n".join(b), tl.css(), "Klieg",
                            "A stage light sweeps across four coding agents from herdr and OpenRig. One stops to ask for approval: "
                            "its card glows orange, the menu-bar beacon shows 1, you answer, and it goes back to work and finishes.")}
