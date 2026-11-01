"""dataflow.svg: herdr, OpenRig and GitHub on the left, snapshots flowing into the Collector, then out to the
app, the CLI and the MCP server. Midway OpenRig fails: the Collector reports errors["openrig"] while herdr and
GitHub keep flowing, Timeline.carryOver keeps the seats so nothing reads as stopped, and then OpenRig recovers.

That is Collector.swift's real behaviour. The commands are the ones the clients run; the error text is what
`klieg status` printed on the herdr VM on 2026-10-31 when ssh couldn't reach the OpenRig host."""
from .common import (AMBER, AMBER_SOFT, CARD2, DIM, EDGE, FAINT, SOURCE, STATUS, TEXT,
                     Timeline, dots, esc, frame, svg)

W, H = 1280, 520
D = 16.0
ROUNDS = [0.3, 3.8, 7.3, 10.8]      # one Collector refresh per round
FAIL = (3.5, 10.5)                   # OpenRig is unreachable for rounds 2 and 3
RED = "#ff5d5d"


def build():
    tl = Timeline(D, fade=0.4, prefix="f")
    b = [frame(W, H, "How a snapshot is made"), dots(W, H)]
    defs = []

    # --- Sources.
    sx, sw, sh = 40, 320, 104
    sources = [
        ("herdr", "herdr", "local, or herdr --machine from the Mac", ["herdr --machine herdr api snapshot"]),
        ("openrig", "OpenRig", "rig, over ssh to the OpenRig host", ["rig ps --nodes -A --full --json", "rig queue list -A --full --json"]),
        ("github", "GitHub", "gh, for each watched repo", ["gh pr list --repo ry-ops/klieg", "gh api …/commits/<sha> (signed?)"]),
    ]
    ys = [80, 200, 320]
    cx, cy, cw, ch = 470, 146, 370, 246      # the Collector
    for (key, name, how, cmds), y in zip(sources, ys):
        c = SOURCE[key]
        b.append(f'<rect x="{sx}" y="{y}" width="{sw}" height="{sh}" rx="12" fill="{CARD2}" stroke="{EDGE}"/>')
        b.append(f'<circle cx="{sx + 20}" cy="{y + 24}" r="5" fill="{c}"/>'
                 f'<text x="{sx + 33}" y="{y + 29}" class="sans" font-size="16" font-weight="700" fill="{TEXT}">{name}</text>'
                 f'<text x="{sx + 20}" y="{y + 49}" class="sans" font-size="12" fill="{DIM}">{esc(how)}</text>')
        for i, cmd in enumerate(cmds):
            b.append(f'<text x="{sx + 20}" y="{y + 72 + i * 18}" class="mono" font-size="11.5" fill="{FAINT if i else DIM}">{esc(cmd)}</text>')
        d = f"M{sx + sw} {y + sh / 2} C {sx + sw + 60} {y + sh / 2}, {cx - 60} {cy + ch / 2}, {cx} {cy + ch / 2}"
        defs.append(f'<path id="in-{key}" d="{d}"/>')
        b.append(f'<path d="{d}" fill="none" stroke="{EDGE}" stroke-width="2"/>')
    # OpenRig failing: red outline, the exit code, a dashed dead wire.
    oy = ys[1]
    down = tl.appear(FAIL[0], until=FAIL[1])
    b.append(f'<g class="{down}"><rect x="{sx - 1}" y="{oy - 1}" width="{sw + 2}" height="{sh + 2}" rx="13" fill="{RED}" fill-opacity=".06" stroke="{RED}" stroke-width="2"/>'
             f'<rect x="{sx + sw - 96}" y="{oy + 12}" width="84" height="22" rx="11" fill="{RED}" fill-opacity=".18"/>'
             f'<text x="{sx + sw - 54}" y="{oy + 27}" text-anchor="middle" class="mono" font-size="11.5" font-weight="700" fill="{RED}">exit 255</text>'
             f'<path d="M{sx + sw} {oy + sh / 2} C {sx + sw + 60} {oy + sh / 2}, {cx - 60} {cy + ch / 2}, {cx} {cy + ch / 2}" fill="none" stroke="{RED}" stroke-width="2" stroke-dasharray="5 6"/></g>')

    # --- The Collector.
    b.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="14" fill="{CARD2}" stroke="{AMBER}" stroke-opacity=".55"/>')
    b.append(f'<text x="{cx + 22}" y="{cy + 34}" class="sans" font-size="20" font-weight="800" fill="{TEXT}">Collector</text>')
    b.append(f'<text x="{cx + 22}" y="{cy + 56}" class="sans" font-size="12.5" fill="{AMBER_SOFT}">reads all three at once; each fails on its own</text>')
    b.append(f'<path d="M{cx + 1} {cy + 72} h{cw - 2}" stroke="{EDGE}"/>')
    ok_rows = [("agents", "1 herdr · 4 openrig", TEXT), ("queue", "1", TEXT), ("pullRequests", "1", TEXT), ("errors", "[:]", DIM)]
    bad_rows = [("agents", "1 herdr · 0 openrig", TEXT), ("queue", "0", TEXT), ("pullRequests", "1", TEXT),
                ("errors", "", RED), ("", '  ["openrig": "seats: ssh … rig ps --nodes', RED),
                ("", '  … exited 255: Host key verification', RED), ("", '  failed.; queue: …"]', RED)]

    def readout(rows):
        return "".join(f'<text x="{cx + 22}" y="{cy + 98 + i * 21}" class="mono" font-size="12.5" fill="{FAINT}" xml:space="preserve">{esc(k.ljust(13) if k else "")}'
                       f'<tspan fill="{c}">{esc(v)}</tspan></text>' for i, (k, v, c) in enumerate(rows))
    settle = 1.3    # a round's packets reach the Collector this long after it starts
    b.append(f'<g class="{tl.visible_until(ROUNDS[1] + settle)}">{readout(ok_rows)}</g>')
    b.append(f'<g class="{tl.appear(ROUNDS[1] + settle, until=ROUNDS[3] + settle)}">{readout(bad_rows)}</g>')
    b.append(f'<g class="{tl.appear(ROUNDS[3] + settle)}">{readout(ok_rows)}</g>')
    # What the timeline makes of it.
    note_y = cy + ch + 34
    b.append(f'<text class="sans {tl.appear(ROUNDS[1] + settle + 0.4, until=ROUNDS[3] + settle)}" x="{cx + cw / 2}" y="{note_y}" text-anchor="middle" font-size="13" fill="{DIM}">'
             f'Timeline.carryOver keeps the 4 seats, so nothing reads as <tspan fill="{TEXT}">stopped</tspan>.</text>')
    b.append(f'<text class="sans {tl.appear(ROUNDS[3] + settle + 0.4)}" x="{cx + cw / 2}" y="{note_y}" text-anchor="middle" font-size="13" fill="{DIM}">'
             f'OpenRig is back, and nothing reads as <tspan fill="{TEXT}">new</tspan> either.</text>')

    # --- Surfaces.
    ox, ow, oh = 950, 290, 86
    outs = [("Klieg.app", "Board, Needs You, Timeline", "⚠ openrig: seats: ssh … exited 255"),
            ("klieg status", "agents, queue, PRs, who needs you", "! couldn't read openrig: seats: …"),
            ("klieg mcp", "klieg_status for Claude", "Couldn't read openrig: seats: …")]
    oys = [100, 214, 328]
    for i, ((name, what, err), y) in enumerate(zip(outs, oys)):
        b.append(f'<rect x="{ox}" y="{y}" width="{ow}" height="{oh}" rx="12" fill="{CARD2}" stroke="{EDGE}"/>')
        b.append(f'<text x="{ox + 20}" y="{y + 30}" class="{"sans" if i == 0 else "mono"}" font-size="16" font-weight="700" fill="{TEXT}">{name}</text>'
                 f'<text x="{ox + 20}" y="{y + 52}" class="sans" font-size="12" fill="{DIM}">{esc(what)}</text>')
        b.append(f'<text class="{"sans" if i == 0 else "mono"} {tl.appear(ROUNDS[1] + 2.4, until=ROUNDS[3] + 2.4)}" x="{ox + 20}" y="{y + 72}" font-size="11.5" fill="{STATUS["blocked"] if i == 0 else RED}">{esc(err)}</text>')
        d = f"M{cx + cw} {cy + ch / 2} C {cx + cw + 60} {cy + ch / 2}, {ox - 60} {y + oh / 2}, {ox} {y + oh / 2}"
        defs.append(f'<path id="out-{i}" d="{d}"/>')
        b.append(f'<path d="{d}" fill="none" stroke="{EDGE}" stroke-width="2"/>')

    # --- Packets: each round, every source sends one in (unless it's down), then the snapshot goes out.
    pk = []
    for r in ROUNDS:
        failing = FAIL[0] <= r < FAIL[1]
        for key, _, _, _ in sources:
            if key == "openrig" and failing:
                # A dead request: a red cross at the source.
                y = ys[1] + sh / 2
                pk.append(f'<g class="{tl.appear(r, until=r + 1.2, ease=0.1)}"><circle cx="{sx + sw + 18}" cy="{y}" r="10" fill="{RED}" fill-opacity=".2"/>'
                          f'<path d="M{sx + sw + 13} {y - 5} l10 10 m0 -10 l-10 10" stroke="{RED}" stroke-width="2.2"/></g>')
                continue
            pk.append(f'<circle class="{tl.appear(r, until=r + 1.15, ease=0.1)}" r="6" fill="{SOURCE[key]}">'
                      f'<animateMotion {tl.motion(r, r + 1.2)}><mpath href="#in-{key}"/></animateMotion></circle>')
        for i in range(3):
            t0 = r + 1.5
            pk.append(f'<circle class="{tl.appear(t0, until=t0 + 0.95, ease=0.1)}" r="6" fill="{RED if failing else AMBER}" fill-opacity="{.85 if failing else 1}">'
                      f'<animateMotion {tl.motion(t0, t0 + 1.0)}><mpath href="#out-{i}"/></animateMotion></circle>')
        # The Collector flashes as a round lands.
        pk.append(f'<rect class="{tl.appear(r + 1.15, until=r + 1.6, ease=0.12)}" x="{cx - 2}" y="{cy - 2}" width="{cw + 4}" height="{ch + 4}" rx="16" fill="none" stroke="{AMBER}" stroke-width="2.5"/>')
    b.append(f'<g class="pk">{"".join(pk)}</g>')
    b.insert(2, f'<defs>{"".join(defs)}</defs>')

    css = tl.css() + "\n@media (prefers-reduced-motion: reduce){.pk{display:none}}"
    return {"dataflow.svg": svg(W, H, "\n".join(b), css, "Klieg: how a snapshot is made",
                                "herdr, OpenRig and GitHub send their state into Klieg's Collector every round, and the Collector sends one "
                                "snapshot on to Klieg.app, klieg status and klieg mcp. Midway OpenRig becomes unreachable: its box turns red, "
                                "the Collector shows errors[\"openrig\"] with ssh's 'Host key verification failed', herdr and GitHub keep "
                                "flowing, and the timeline keeps the OpenRig seats so nothing reads as stopped. Then OpenRig recovers and "
                                "everything flows again.")}
