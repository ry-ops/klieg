"""hero.svg: Klieg's searchlight sweeps across four agent cards while their states change.
One cycle tells the story Klieg is for: agents work, one stops to ask you something,
the light finds it, the menu-bar beacon counts it, you answer, it finishes."""
import math

from .common import (AMBER, AMBER_SOFT, ACCENT, CARD2, CREAM, DIM, EDGE, FAINT, STATUS, TEXT,
                     Timeline, agent_card, badge, dots, esc, frame, svg)

W, H = 1280, 440
D = 12.0

# The app icon's metal and lens colours (scripts/make-icon.swift).
M_DARK, M_METAL, M_LIGHT, M_EDGE = "#2b3026", "#454d3d", "#666e59", "#858c75"
LENS = ("#fffff7", "#ffedbd", "#f2c77a")     # glass: white-hot centre to amber rim
RIB, CROSS, BOLT = "#cca86b", "#3a3f33", "#c7ccd1"


def searchlight(tl, px, py, stops, targets):
    """The icon's searchlight in side view, facing right, its yoke pivot at (px, py), standing on a
    round bolted pedestal. `stops` is [(t, target), ...]; at each stop the head points at that
    target and the beam stretches so its pool of light lands on it. Returns SVG fragments."""
    lens_off, beam_len = 26, 100       # lens centre ahead of the pivot; beam path's drawn length

    def aim(name):
        x, y = targets[name]
        return math.degrees(math.atan2(y - py, x - px)), math.hypot(x - px, y - py)

    def keyframes(fmt):
        # One transform per stop, eased between stops. The class's own transform is the end
        # state, so the light still rests on a card if the animation doesn't run.
        name = tl._name()
        frames = "".join(f"{tl.p(t):.3f}%{{transform:{fmt(*aim(n))}}}" for t, n in stops)
        tl.rules.append(f"@keyframes {name}{{{frames}}}"
                        f".{name}{{transform-box:view-box;transform-origin:{px}px {py}px;transform:{fmt(*aim(stops[-1][1]))};"
                        f"animation:{name} {tl.d}s ease-in-out infinite}}")
        return name

    head = keyframes(lambda a, l: f"rotate({a:.2f}deg)")
    beam = keyframes(lambda a, l: f"rotate({a:.2f}deg) translateX({lens_off}px) scaleX({(l - lens_off) / beam_len:.3f})")
    pool = keyframes(lambda a, l: f"rotate({a:.2f}deg) translateX({l:.1f}px)")

    out = ['<defs>'
           f'<linearGradient id="slBeam" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{CREAM}" stop-opacity=".6"/>'
           f'<stop offset=".75" stop-color="{AMBER}" stop-opacity=".16"/><stop offset="1" stop-color="{AMBER}" stop-opacity="0"/></linearGradient>'
           f'<radialGradient id="slPool"><stop offset="0" stop-color="{AMBER}" stop-opacity=".4"/><stop offset="1" stop-color="{AMBER}" stop-opacity="0"/></radialGradient>'
           f'<radialGradient id="slGlow"><stop offset="0" stop-color="{AMBER}" stop-opacity=".45"/><stop offset="1" stop-color="{AMBER}" stop-opacity="0"/></radialGradient>'
           f'<radialGradient id="slLens" cx=".35" cy=".6" r=".75"><stop offset="0" stop-color="{LENS[0]}"/>'
           f'<stop offset=".55" stop-color="{LENS[1]}"/><stop offset="1" stop-color="{LENS[2]}"/></radialGradient>'
           f'<linearGradient id="slDrum" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{M_LIGHT}"/>'
           f'<stop offset=".45" stop-color="{M_METAL}"/><stop offset="1" stop-color="{M_DARK}"/></linearGradient>'
           f'<linearGradient id="slPost" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{M_DARK}"/>'
           f'<stop offset=".4" stop-color="{M_LIGHT}"/><stop offset="1" stop-color="{M_DARK}"/></linearGradient>'
           f'<clipPath id="slLensClip"><ellipse cx="{px + lens_off}" cy="{py}" rx="12" ry="33"/></clipPath>'
           '</defs>']

    # Beam and its pool, drawn along +x from the pivot, then turned and stretched by the keyframes.
    out.append(f'<g style="mix-blend-mode:screen">'
               f'<path class="{beam}" d="M{px} {py - 22} L{px + beam_len} {py - 46} L{px + beam_len} {py + 46} L{px} {py + 22} Z" fill="url(#slBeam)"/>'
               f'<circle class="{pool}" cx="{px}" cy="{py}" r="72" fill="url(#slPool)"/></g>')

    # Pedestal: a floor shadow, a round bolted base, a collar and a post.
    by = py + 80
    out.append(f'<ellipse cx="{px}" cy="{by + 14}" rx="72" ry="9" fill="#000" opacity=".55"/>'
               f'<path d="M{px - 54} {by} v8 a54 11 0 0 0 108 0 v-8 z" fill="{M_DARK}"/>'
               f'<ellipse cx="{px}" cy="{by}" rx="54" ry="11" fill="{M_LIGHT}" stroke="{M_EDGE}" stroke-width="1.5"/>')
    for deg in (200, 235, 270, 305, 340, 25, 65, 115, 155):      # bolts around the rim, as on the icon
        bx, bb = px + 45 * math.cos(math.radians(deg)), by + 8 * math.sin(math.radians(deg))
        out.append(f'<rect x="{bx - 2.5:.1f}" y="{bb - 3:.1f}" width="5" height="5" rx="1" fill="{M_METAL}"/>')
    out.append(f'<rect x="{px - 11}" y="{py + 44}" width="22" height="{by - py - 44}" fill="url(#slPost)"/>'
               f'<ellipse cx="{px}" cy="{by - 1}" rx="17" ry="4.5" fill="{M_LIGHT}" stroke="{M_EDGE}"/>')
    # Yoke: a bar on the post and an arm up to the trunnion.
    out.append(f'<path d="M{px - 22} {py + 46} L{px - 13} {py - 6} Q{px} {py - 18} {px + 13} {py - 6} L{px + 22} {py + 46} Z" '
               f'fill="{M_METAL}" stroke="{M_DARK}" stroke-width="1.5"/>'
               f'<rect x="{px - 30}" y="{py + 42}" width="60" height="8" rx="2" fill="{M_LIGHT}" stroke="{M_DARK}"/>')

    # Head: drum, rim, glowing lens with ribs and a cross, and the trunnion bolt. Turns with the beam.
    lx = px + lens_off
    ribs = "".join(f'<line x1="{x}" y1="{py - 34}" x2="{x}" y2="{py + 34}"/>' for x in range(lx - 10, lx + 11, 4))
    out.append(f'<g class="{head}">'
               f'<ellipse cx="{lx + 8}" cy="{py}" rx="34" ry="54" fill="url(#slGlow)"/>'
               f'<path d="M{px - 40} {py - 30} L{px + 22} {py - 37} L{px + 22} {py + 37} L{px - 40} {py + 30} Z" fill="url(#slDrum)"/>'
               f'<ellipse cx="{px - 40}" cy="{py}" rx="9" ry="30" fill="{M_DARK}"/>'
               f'<path d="M{px - 8} {py - 34} a8 34 0 0 1 0 68" fill="none" stroke="{M_EDGE}" stroke-opacity=".45" stroke-width="2"/>'
               f'<ellipse cx="{lx - 2}" cy="{py}" rx="15" ry="39" fill="{M_LIGHT}" stroke="{M_EDGE}" stroke-width="2"/>'
               f'<ellipse cx="{lx}" cy="{py}" rx="12" ry="33" fill="url(#slLens)"/>'
               f'<g clip-path="url(#slLensClip)" stroke="{RIB}" stroke-opacity=".55" stroke-width="1.2">{ribs}</g>'
               f'<path d="M{lx - 8.5} {py - 23} L{lx + 8.5} {py + 23} M{lx - 8.5} {py + 23} L{lx + 8.5} {py - 23}" stroke="{CROSS}" stroke-width="2.6" stroke-linecap="round"/>'
               f'<ellipse cx="{lx}" cy="{py}" rx="2.6" ry="4.5" fill="{CROSS}"/>'
               f'<ellipse cx="{lx}" cy="{py}" rx="12" ry="33" fill="none" stroke="{M_DARK}" stroke-width="1.5"/>'
               f'<circle cx="{px}" cy="{py}" r="10" fill="{M_DARK}"/><circle cx="{px}" cy="{py}" r="5.5" fill="{BOLT}"/></g>')
    return out


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

    # --- The light: Klieg's searchlight from the app icon, standing at the stage's edge. Its head
    # and beam turn together from card to card and linger on the blocked one.
    b.extend(searchlight(tl, 565, 318,
                         [(0, "m1"), (1.2, "m1"), (2.4, "build"), (3.6, "build"), (4.4, "review"),
                          (7.6, "review"), (8.6, "queue"), (9.6, "m1"), (D, "m1")],
                         {"m1": (780, 180), "build": (1080, 180), "review": (780, 328), "queue": (1080, 328)}))

    return {"hero.svg": svg(W, H, "\n".join(b), tl.css(), "Klieg",
                            "Klieg's searchlight, an olive metal lamp on a yoke and pedestal like the app icon, "
                            "sweeps its beam across four coding agents from herdr and OpenRig. One stops to ask for approval: "
                            "its card glows orange, the menu-bar beacon shows 1, you answer, and it goes back to work and finishes.")}
