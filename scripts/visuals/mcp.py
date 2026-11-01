"""mcp.svg: Claude calling Klieg's MCP server in read-only mode.

Left: the 12 real tools from Sources/KliegServer/Tools.swift, split into read and act, with the four
destructive ones marked. Right: a read call (klieg_status) goes through and answers with statusText's
format, then an act call (klieg_prompt_agent) is refused with MCPServer.call's exact wording."""
from .common import (ACCENT, AMBER, AMBER_SOFT, CARD, CARD2, DIM, EDGE, FAINT, STATUS, TEXT,
                     Timeline, dots, esc, frame, svg)

W, H = 1280, 600
D = 14.0
RED = "#ff6b6b"
GREEN = STATUS["done"]

# (name, title) exactly as in KliegTools.all.
READ = [("klieg_status", "Agent status"), ("klieg_timeline", "Timeline"),
        ("klieg_read_agent", "Read an agent's screen"), ("klieg_pull_requests", "Pull requests")]
ACT = [("klieg_prompt_agent", "Prompt an agent", False), ("klieg_queue_goal", "Queue a goal", False),
       ("klieg_start_agent", "Start an agent", False), ("klieg_stop_agent", "Stop an agent", True),
       ("klieg_rig_up", "Bring a rig up", False), ("klieg_rig_down", "Take a rig down", True),
       ("klieg_answer_prompt", "Answer a prompt", True), ("klieg_merge_pr", "Merge a pull request", True)]

# KliegTools.statusText for a snapshot from the build (2026-10-31): herdr's m1, the klieg-pair rig,
# and the kernel operator stopped at the usage-credits prompt.
STATUS_LINES = [
    "1 need you:",
    "  ! openrig:operator-agent@kernel  billing",
    "Agents:",
    "  herdr:herdr/w3:p1  working  [klieg-m1]",
    "  openrig:dev-build@klieg-pair  working  claude-opus-5-5  [klieg-pair]",
    "  openrig:dev-review@klieg-pair  idle  claude-opus-5-5  [klieg-pair]",
    "  openrig:operator-agent@kernel  blocked  [kernel]",
]
# MCPServer.call: "Klieg is read-only (KLIEG_READ_ONLY is set), so \(tool.name) was refused. Nothing was changed."
REFUSAL = ["Klieg is read-only (KLIEG_READ_ONLY is set), so klieg_prompt_agent",
           "was refused. Nothing was changed."]


def chip(x, y, text, color, mono=False, cls=""):
    w = 22 + (7.8 if mono else 7.4) * len(text)
    c = f' class="{cls}"' if cls else ""
    font = "mono" if mono else "sans"
    return (f'<g{c}><rect x="{x}" y="{y}" width="{w:.0f}" height="26" rx="13" fill="{color}" fill-opacity=".14" stroke="{color}" stroke-opacity=".5"/>'
            f'<text x="{x + 11}" y="{y + 17.5}" class="{font}" font-size="13" font-weight="600" fill="{color}">{esc(text)}</text></g>'), w


def build():
    tl = Timeline(D, fade=0.4, prefix="m")
    b = [frame(W, H, "Klieg's MCP server"), dots(W, H)]

    # --- Left: the tool list.
    lx, ly, lw, lh = 28, 64, 440, 492
    b.append(f'<rect x="{lx}" y="{ly}" width="{lw}" height="{lh}" rx="14" fill="{CARD}" stroke="{EDGE}"/>')
    b.append(f'<text x="{lx + 22}" y="{ly + 34}" class="sans" font-size="17" font-weight="700" fill="{TEXT}">12 tools</text>')

    def section(y, head, note):
        b.append(f'<text x="{lx + 22}" y="{y}" class="sans" font-size="12" font-weight="700" fill="{DIM}" letter-spacing="1.4">{head}</text>')
        b.append(f'<text x="{lx + 72}" y="{y}" class="sans" font-size="12" fill="{FAINT}">{esc(note)}</text>')

    def row(y, name, title, marked=False, hl=None):
        if hl:
            color, t0, t1 = hl
            b.append(f'<rect class="{tl.appear(t0, until=t1)}" x="{lx + 10}" y="{y - 18}" width="{lw - 20}" height="27" rx="7" fill="{color}" fill-opacity=".2" stroke="{color}" stroke-opacity=".6"/>')
        b.append(f'<text x="{lx + 22}" y="{y}" class="mono" font-size="13" fill="{TEXT}">{esc(name)}</text>')
        b.append(f'<text x="{lx + 206}" y="{y}" class="sans" font-size="12" fill="{DIM}">{esc(title)}</text>')
        if marked:
            b.append(f'<rect x="{lx + lw - 92}" y="{y - 14}" width="78" height="19" rx="9.5" fill="{RED}" fill-opacity=".14"/>'
                     f'<text x="{lx + lw - 53}" y="{y - 0.5}" text-anchor="middle" class="sans" font-size="10.5" font-weight="700" fill="{RED}">destructive</text>')

    section(ly + 72, "READ", "change nothing")
    for i, (name, title) in enumerate(READ):
        row(ly + 102 + i * 30, name, title, hl=(ACCENT, 1.0, 5.6) if name == "klieg_status" else None)
    section(ly + 244, "ACT", "refused in read-only mode")
    for i, (name, title, destructive) in enumerate(ACT):
        row(ly + 274 + i * 30, name, title, destructive, hl=(RED, 6.6, 12.4) if name == "klieg_prompt_agent" else None)

    # --- Right: the conversation.
    rx, ry, rw, rh = 492, 64, 760, 492
    b.append(f'<rect x="{rx}" y="{ry}" width="{rw}" height="{rh}" rx="14" fill="{CARD}" stroke="{EDGE}"/>')
    c1, w1 = chip(rx + 22, ry + 18, "Claude", AMBER_SOFT)
    b.append(c1)
    ax = rx + 22 + w1 + 10
    b.append(f'<path d="M{ax} {ry + 31} h34 m-7 -5 l7 5 l-7 5" fill="none" stroke="{DIM}" stroke-width="1.6"/>')
    c2, w2 = chip(ax + 44, ry + 18, "klieg mcp", ACCENT, mono=True)
    b.append(c2)
    c3, _ = chip(ax + 44 + w2 + 10, ry + 18, "KLIEG_READ_ONLY=1", AMBER, mono=True)
    b.append(c3)
    b.append(f'<text x="{rx + rw - 22}" y="{ry + 36}" text-anchor="end" class="sans" font-size="12" fill="{FAINT}">JSON-RPC 2.0 over stdio</text>')

    def call(y, lines, t):
        h = 16 + 20 * len(lines)
        out = f'<g class="{tl.hold(t)}"><rect x="{rx + 20}" y="{y}" width="{rw - 40}" height="{h}" rx="9" fill="{CARD2}" stroke="{EDGE}"/>'
        for i, ln in enumerate(lines):
            out += f'<text x="{rx + 36}" y="{y + 24 + i * 20}" class="mono" font-size="13" fill="{AMBER_SOFT if i == 0 else DIM}">{esc(ln)}</text>'
        return out + "</g>"

    def reply(y, ok, lines, t, step=0.12):
        color = GREEN if ok else RED
        h = 46 + 20 * len(lines)
        out = (f'<g class="{tl.hold(t)}"><rect x="{rx + 20}" y="{y}" width="{rw - 40}" height="{h}" rx="9" fill="{color}" fill-opacity=".07" stroke="{color}" stroke-opacity=".45"/>'
               f'<text x="{rx + 36}" y="{y + 25}" class="mono" font-size="13" font-weight="700" fill="{color}">← isError: {"false" if ok else "true"}</text></g>')
        for i, ln in enumerate(lines):
            fill = STATUS["blocked"] if "!" in ln or "blocked" in ln else (TEXT if ok else RED)
            out += f'<text class="mono {tl.hold(t + 0.2 + i * step)}" x="{rx + 36}" y="{y + 50 + i * 20}" font-size="12.5" fill="{fill}" xml:space="preserve">{esc(ln)}</text>'
        return out

    b.append(call(ry + 62, ["→ tools/call  klieg_status  {}"], 1.0))
    b.append(reply(ry + 110, True, STATUS_LINES, 2.2))
    b.append(call(ry + 318, ["→ tools/call  klieg_prompt_agent",
                             '  {"agent": "openrig:dev-build@klieg-pair", "text": "Run the self-test"}'], 6.6))
    b.append(reply(ry + 386, False, REFUSAL, 8.0, step=0.3))

    b.append(f'<text class="sans {tl.hold(9.6)}" x="{W // 2}" y="{H - 18}" text-anchor="middle" font-size="14" fill="{DIM}">'
             'Read tools always answer. With KLIEG_READ_ONLY=1, every act tool is refused before it runs.</text>')

    return {"mcp.svg": svg(W, H, "\n".join(b), tl.css(), "Klieg's MCP tools",
                           "Klieg's 12 MCP tools, four that read and eight that act, four of them marked destructive. "
                           "Claude calls klieg_status on a read-only Klieg server and gets every agent's state back, then calls "
                           "klieg_prompt_agent and is refused: Klieg is read-only (KLIEG_READ_ONLY is set), so klieg_prompt_agent "
                           "was refused. Nothing was changed.")}
