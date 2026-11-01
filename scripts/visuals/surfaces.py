"""surfaces.svg: one core (KliegKit and its Collector) feeding three surfaces: Klieg.app, the klieg CLI,
and `klieg mcp` for Claude. Each surface lights up in turn and shows a real example of what it shows.

The data is one moment of the real build on 2026-10-31: the herdr agent m1, the OpenRig seats from
Tests/SelfTest/Fixtures/openrig/ps-nodes.json, its open queue item, and PR #3. The CLI lines are padded
the way Sources/KliegCLI/main.swift's printTable does it; the MCP reply follows KliegTools.statusText."""
from .common import (ACCENT, AMBER, AMBER_SOFT, CARD2, DIM, EDGE, FAINT, SOURCE, STATUS, TEXT,
                     Timeline, agent_card, badge, dots, esc, frame, svg, window)

W, H = 1280, 690
D = 15.0
PHASES = [(0.0, 5.0), (5.0, 10.0), (10.0, 15.0)]

# One snapshot, used by all three surfaces.
AGENTS = [  # name, source, status, group, id, model, cwd
    ("m1", "herdr", "working", "klieg-m1", "herdr:herdr/w3:p1", None, "/home/ubuntu/src/klieg"),
    ("advisor-lead@kernel", "openrig", "blocked", "kernel", "openrig:advisor-lead@kernel", None, "/home/ubuntu/.openrig/workspace"),
    ("dev-build@klieg-pair", "openrig", "working", "klieg-pair", "openrig:dev-build@klieg-pair", "claude-opus-5-5", "/home/ubuntu/src/klieg"),
    ("dev-review@klieg-pair", "openrig", "idle", "klieg-pair", "openrig:dev-review@klieg-pair", "claude-opus-5-5", "/home/ubuntu/src/klieg"),
]
REASON = {"advisor-lead@kernel": "permission_prompt"}
QITEM = ("qitem-20261031195841-98147cee9e1fdb9a", "in-progress", "ryan@mac", "dev-build@klieg-pair", "")
PR = ("ry-ops/klieg#3", "success", "yes", "M2: OpenRig client, GitHub client and the MCP server")


def table(header, rows):
    """printTable from main.swift: columns padded to the widest cell, two spaces apart, last column unpadded."""
    widths = [max(len(r[i]) for r in [header] + rows) for i in range(len(header))]
    return ["  ".join(v if i == len(r) - 1 else v.ljust(widths[i]) for i, v in enumerate(r)).rstrip() for r in [header] + rows]


def cli_lines():
    rows = [[n, s, "claude", st + (f" ({REASON[n]})" if n in REASON else ""), g, i] for n, s, st, g, i, _, _ in AGENTS]
    out = ["$ klieg status"]
    out += table(["NAME", "SOURCE", "KIND", "STATUS", "GROUP", "ID"], rows)
    out += ["", "Queue (1):"] + table(["ID", "STATE", "FROM", "TO", "SUMMARY"], [list(QITEM)])
    out += ["", "Pull requests (1):"] + table(["PR", "CHECKS", "SIGNED", "TITLE"], [list(PR)])
    out += ["", "Needs you (1):", "  advisor-lead@kernel: permission_prompt  → ssh -t ubuntu@100.67.70.121 tmux attach -t advisor-lead@kernel"]
    return out


def mcp_lines():
    out = ["1 need you:", "  ! openrig:advisor-lead@kernel  permission_prompt", "Agents:"]
    for _, _, st, g, i, model, _ in AGENTS:
        out.append(f"  {i}  {st}" + (f"  {model}" if model else "") + f"  [{g}]")
    out += ["Queue:", f"  {QITEM[0]}  {QITEM[1]}  {QITEM[2]} → {QITEM[3]}"]
    return out


def phase_class(tl, i, at=None, until=None):
    """Visible during phase i. Phase 0 is the resting picture (also what reduced motion shows)."""
    s, e = PHASES[i]
    if i == 0:
        return tl.visible_until(until if until is not None else e - 0.3)
    return tl.appear(at if at is not None else s + 0.7, until=until if until is not None else (e - 0.3 if i < 2 else None))


def build():
    tl = Timeline(D, fade=0.4, prefix="s")
    b = [frame(W, H, "One core, three surfaces"), dots(W, H)]

    # --- The core.
    cx, cy, cw, ch = 460, 62, 360, 104
    b.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="14" fill="{CARD2}" stroke="{AMBER}" stroke-opacity=".55"/>')
    b.append(f'<text x="{cx + cw / 2}" y="{cy + 36}" text-anchor="middle" class="sans" font-size="24" font-weight="800" fill="{TEXT}">KliegKit</text>')
    b.append(f'<text x="{cx + cw / 2}" y="{cy + 60}" text-anchor="middle" class="sans" font-size="14" fill="{AMBER_SOFT}">Collector → one Snapshot</text>')
    x = cx + 62
    for name, key in [("herdr", "herdr"), ("OpenRig", "openrig"), ("GitHub", "github")]:
        b.append(f'<circle cx="{x}" cy="{cy + 83}" r="4" fill="{SOURCE[key]}"/>'
                 f'<text x="{x + 9}" y="{cy + 87.5}" class="sans" font-size="12.5" fill="{DIM}">{name}</text>')
        x += 86

    # --- The three surfaces, with wires from the core.
    sy, sw, sh = 214, 300, 82
    surfaces = [
        (70, "MAC APP", "Klieg.app", "Board · Needs You · Timeline · Pull Requests"),
        (490, "CLI", "klieg", "status · timeline · herdr prompt · mcp install"),
        (910, "MCP SERVER", "klieg mcp", "12 tools for Claude, over stdio JSON-RPC"),
    ]
    defs = []
    for i, (sx, tag, name, sub) in enumerate(surfaces):
        mx = sx + sw / 2
        d = f"M{cx + cw / 2} {cy + ch} C {cx + cw / 2} {cy + ch + 34}, {mx} {sy - 34}, {mx} {sy}"
        defs.append(f'<path id="w{i}" d="{d}"/>')
        b.append(f'<path d="{d}" fill="none" stroke="{EDGE}" stroke-width="2"/>')
        lit = phase_class(tl, i, at=PHASES[i][0] + 0.1)
        b.append(f'<path class="{lit}" d="{d}" fill="none" stroke="{AMBER}" stroke-width="2.5"/>')
        b.append(f'<rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="12" fill="{CARD2}" stroke="{EDGE}"/>')
        b.append(f'<rect class="{phase_class(tl, i, at=PHASES[i][0] + 0.6)}" x="{sx - 2}" y="{sy - 2}" width="{sw + 4}" height="{sh + 4}" rx="14" fill="{AMBER}" fill-opacity=".07" stroke="{AMBER}" stroke-width="2"/>')
        b.append(f'<text x="{sx + 18}" y="{sy + 24}" class="sans" font-size="11" font-weight="700" fill="{FAINT}" letter-spacing="1.4">{tag}</text>')
        b.append(f'<text x="{sx + 18}" y="{sy + 50}" class="{"mono" if i else "sans"}" font-size="19" font-weight="700" fill="{TEXT}">{esc(name)}</text>')
        b.append(f'<text x="{sx + 18}" y="{sy + 70}" class="sans" font-size="12" fill="{DIM}">{esc(sub)}</text>')
        # A pointer from the lit surface down to the preview.
        b.append(f'<path class="{phase_class(tl, i, at=PHASES[i][0] + 0.6)}" d="M{mx - 10} {sy + sh + 14} h20 l-10 12 z" fill="{AMBER}"/>')
        # A packet (the snapshot) travelling down the wire.
        s = PHASES[i][0]
        b.append(f'<g class="pk"><circle class="{tl.appear(s + 0.1, until=s + 0.75, ease=0.1)}" r="6" fill="{AMBER}">'
                 f'<animateMotion {tl.motion(s + 0.1, s + 0.8)}><mpath href="#w{i}"/></animateMotion></circle></g>')
    b.insert(2, f'<defs>{"".join(defs)}</defs>')

    # --- The preview: one surface at a time.
    px, py, pw, ph = 40, 336, 1200, 330
    b.append(f'<g class="{phase_class(tl, 0)}">{app_preview(tl, px, py, pw, ph)}</g>')
    b.append(f'<g class="{phase_class(tl, 1)}">{cli_preview(tl, px, py, pw, ph)}</g>')
    b.append(f'<g class="{phase_class(tl, 2)}">{mcp_preview(tl, px, py, pw, ph)}</g>')

    css = tl.css() + "\n@media (prefers-reduced-motion: reduce){.pk{display:none}}"
    return {"surfaces.svg": svg(W, H, "\n".join(b), css, "Klieg: one core, three surfaces",
                                "KliegKit's Collector builds one snapshot of herdr agents, OpenRig seats, queue items and pull requests, "
                                "and three surfaces show it. In turn: Klieg.app's Board with four agent cards, one of them blocked "
                                "asking to approve a command; the klieg status command printing the same agents, the queue item, "
                                "PR ry-ops/klieg#3 and who needs you; and Claude calling the klieg_status MCP tool and getting the same picture back.")}


def app_preview(tl, x, y, w, h):
    out = [window(x, y, w, h, "Klieg — Board")]
    # Sidebar.
    out.append(f'<rect x="{x + 1}" y="{y + 35}" width="190" height="{h - 36}" fill="{CARD2}"/>')
    for i, s in enumerate(["Board", "Needs You", "Timeline", "Pull Requests", "Settings"]):
        ry = y + 58 + i * 34
        if i == 0:
            out.append(f'<rect x="{x + 10}" y="{ry - 18}" width="170" height="28" rx="7" fill="{ACCENT}" fill-opacity=".85"/>')
        out.append(f'<text x="{x + 24}" y="{ry + 1}" class="sans" font-size="13.5" font-weight="{600 if i == 0 else 500}" fill="{TEXT if i == 0 else DIM}">{s}</text>')
        if s == "Needs You":
            out.append(f'<rect x="{x + 148}" y="{ry - 13}" width="22" height="18" rx="9" fill="{STATUS["blocked"]}"/>'
                       f'<text x="{x + 159}" y="{ry + 0.5}" text-anchor="middle" class="sans" font-size="11" font-weight="800" fill="#1a1205">1</text>')
    # Cards.
    cw, chh, gap = 228, 128, 12
    for i, (name, src, st, g, _, model, cwd) in enumerate(AGENTS):
        cx, cy = x + 214 + i * (cw + gap), y + 64
        out.append(agent_card(cx, cy, cw, chh, name, src, cwd=cwd.replace("/home/ubuntu", "~")))
        out.append(badge(cx + cw - 12, cy + 52, st))
        if st == "blocked":
            out.append(f'<rect class="{tl.pulse(0.6, 4.6)}" x="{cx - 3}" y="{cy - 3}" width="{cw + 6}" height="{chh + 6}" rx="14" fill="none" stroke="{STATUS["blocked"]}" stroke-width="2.5"/>')
            out.append(f'<text x="{cx + 20}" y="{cy + 104}" class="sans" font-size="11" font-weight="600" fill="{STATUS["blocked"]}">It\'s asking to approve a command.</text>')
        else:
            out.append(f'<text x="{cx + 20}" y="{cy + 104}" class="sans" font-size="12" fill="{FAINT}">{esc(g)}{" · " + model if model else ""}</text>')
    out.append(f'<text x="{x + 214}" y="{y + 240}" class="sans" font-size="13" fill="{DIM}">Every card opens its live terminal in one click. Stop, merge and answering prompts ask first.</text>')
    return "".join(out)


def cli_preview(tl, x, y, w, h):
    out = [window(x, y, w, h, "klieg status")]
    s = PHASES[1][0] + 0.9
    for i, ln in enumerate(cli_lines()):
        colour = AMBER_SOFT if i == 0 else (STATUS["blocked"] if ln.startswith(("Needs you", "  advisor")) else TEXT)
        if ln.isupper() or ln.startswith(("NAME", "ID ", "PR ")):
            colour = DIM
        cls = tl.appear(s + i * 0.13, until=PHASES[1][1] - 0.3, ease=0.1)
        out.append(f'<text x="{x + 22}" y="{y + 56 + i * 16}" class="mono {cls}" font-size="11.5" fill="{colour}" xml:space="preserve">{esc(ln)}</text>')
    return "".join(out)


def mcp_preview(tl, x, y, w, h):
    out = [window(x, y, w, h, "Claude → klieg mcp")]
    s = PHASES[2][0] + 0.9
    # The call.
    out.append(f'<text x="{x + 26}" y="{y + 64}" class="sans" font-size="12" font-weight="700" fill="{FAINT}" letter-spacing="1.2">CLAUDE CALLS</text>')
    out.append(f'<rect x="{x + 24}" y="{y + 76}" width="360" height="124" rx="10" fill="{CARD2}" stroke="{ACCENT}" stroke-opacity=".6"/>')
    call = ['{"method": "tools/call",', ' "params": {', '   "name": "klieg_status",', '   "arguments": {}', ' }}']
    for i, ln in enumerate(call):
        out.append(f'<text x="{x + 42}" y="{y + 102 + i * 19}" class="mono" font-size="13" fill="{ACCENT if "klieg_status" in ln else TEXT}" xml:space="preserve">{esc(ln)}</text>')
    out.append(f'<text x="{x + 26}" y="{y + 228}" class="sans" font-size="12.5" fill="{DIM}">Read tool: readOnlyHint. Act tools are</text>'
               f'<text x="{x + 26}" y="{y + 246}" class="sans" font-size="12.5" fill="{DIM}">refused when KLIEG_READ_ONLY is set.</text>')
    # The reply.
    rx = x + 420
    out.append(f'<path class="{tl.appear(s, until=None, ease=0.2)}" d="M{x + 390} {y + 138} h20 m-7 -6 l7 6 l-7 6" fill="none" stroke="{AMBER}" stroke-width="2"/>')
    out.append(f'<text x="{rx}" y="{y + 64}" class="sans" font-size="12" font-weight="700" fill="{FAINT}" letter-spacing="1.2">KLIEG REPLIES</text>')
    for i, ln in enumerate(mcp_lines()):
        colour = STATUS["blocked"] if "!" in ln or ln.startswith("1 need") else (DIM if ln.endswith(":") else TEXT)
        cls = tl.appear(s + 0.3 + i * 0.16, until=None, ease=0.1)
        out.append(f'<text x="{rx}" y="{y + 92 + i * 21}" class="mono {cls}" font-size="13" fill="{colour}" xml:space="preserve">{esc(ln)}</text>')
    return "".join(out)
