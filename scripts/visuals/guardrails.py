"""guardrails.svg: three of Klieg's gates, one after another.

1. Merge only when checks passed and the head commit is signed: PR #9 waits on pending CI and
   klieg_merge_pr refuses (GitHubClient.merge's wording), then CI goes green and it merges, pinned to
   the head commit.
2. A billing prompt refused: operator-agent@kernel's real usage-credits screen (the recorded
   fixture, balance redacted) and OpenRigClient.answerPrompt's refusal.
3. The app asks first: the confirmation dialogs for stopping a seat and merging a PR, with the
   titles and messages from Confirmation in BoardViews.swift."""
from .common import (AMBER, CARD, CARD2, DIM, EDGE, FAINT, STATUS, TEXT,
                     Timeline, badge, dots, esc, frame, svg)

W, H = 1280, 580
D = 15.0
RED = "#ff6b6b"
GREEN = STATUS["done"]
PW, PY, PH = 394, 64, 470
XS = [28, 443, 858]


def pill(x, y, text, color, cls=""):
    w = 20 + 7.2 * len(text)
    c = f' class="{cls}"' if cls else ""
    return (f'<g{c}><rect x="{x}" y="{y - 15}" width="{w:.0f}" height="22" rx="11" fill="{color}" fill-opacity=".16"/>'
            f'<text x="{x + 10}" y="{y + 0.5}" class="sans" font-size="12" font-weight="700" fill="{color}">{esc(text)}</text></g>')


def lines(x, y, rows, size, fill, cls="", step=None, mono=True, weight=None):
    step = step or size * 1.55
    c = f"{'mono' if mono else 'sans'} {cls}".strip()
    wt = f' font-weight="{weight}"' if weight else ""
    return "".join(f'<text x="{x}" y="{y + i * step:.1f}" class="{c}" font-size="{size}" fill="{fill}"{wt} xml:space="preserve">{esc(r)}</text>'
                   for i, r in enumerate(rows))


def box(x, y, w, h, color, cls=""):
    c = f' class="{cls}"' if cls else ""
    return f'<rect{c} x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="{color}" fill-opacity=".08" stroke="{color}" stroke-opacity=".5"/>'


def panel(tl, i, title, t0, t1):
    x = XS[i]
    out = f'<rect x="{x}" y="{PY}" width="{PW}" height="{PH}" rx="14" fill="{CARD}" stroke="{EDGE}"/>'
    out += f'<rect class="{tl.appear(t0, until=t1)}" x="{x - 2}" y="{PY - 2}" width="{PW + 4}" height="{PH + 4}" rx="16" fill="none" stroke="{AMBER}" stroke-width="2" stroke-opacity=".8"/>'
    out += (f'<circle cx="{x + 32}" cy="{PY + 32}" r="13" fill="{AMBER}" fill-opacity=".16"/>'
            f'<text x="{x + 32}" y="{PY + 37}" text-anchor="middle" class="sans" font-size="14" font-weight="800" fill="{AMBER}">{i + 1}</text>'
            f'<text x="{x + 56}" y="{PY + 38}" class="sans" font-size="16" font-weight="700" fill="{TEXT}">{esc(title)}</text>')
    return out


def merge_gate(tl):
    x, y = XS[0], PY
    b = [panel(tl, 0, "Merge only when green and signed", 0.3, 5.2)]
    b.append(f'<rect x="{x + 18}" y="{y + 62}" width="{PW - 36}" height="150" rx="10" fill="{CARD2}" stroke="{EDGE}"/>')
    b.append(f'<text x="{x + 34}" y="{y + 88}" class="mono" font-size="12" fill="{DIM}">ry-ops/klieg#9</text>')
    b.append(f'<text x="{x + 34}" y="{y + 112}" class="sans" font-size="15" font-weight="700" fill="{TEXT}">M4: README for 0.1.0</text>')
    b.append(pill(x + PW - 112, y + 88, "merged", "#b48cff", tl.hold(4.6)))
    b.append(f'<text x="{x + 34}" y="{y + 146}" class="sans" font-size="12.5" fill="{DIM}">checks</text>')
    b.append(pill(x + 130, y + 146, "pending", AMBER, tl.appear(0, until=2.8, ease=0.01)))
    b.append(pill(x + 130, y + 146, "success", GREEN, tl.hold(2.8)))
    b.append(f'<text class="mono {tl.appear(0, until=2.8, ease=0.01)}" x="{x + 222}" y="{y + 146}" font-size="12" fill="{FAINT}">linux running</text>')
    b.append(f'<text class="mono {tl.hold(2.8)}" x="{x + 222}" y="{y + 146}" font-size="12" fill="{FAINT}">linux passed</text>')
    b.append(f'<text x="{x + 34}" y="{y + 180}" class="sans" font-size="12.5" fill="{DIM}">head commit</text>')
    b.append(pill(x + 130, y + 180, "verified", GREEN))
    b.append(f'<text x="{x + 222}" y="{y + 180}" class="mono" font-size="12" fill="{FAINT}">6ff2577</text>')

    # First try, while CI is still running: refused.
    b.append(f'<text class="mono {tl.appear(1.1, until=2.7)}" x="{x + 20}" y="{y + 246}" font-size="11" fill="{AMBER}">→ klieg_merge_pr {esc('{"repo": "ry-ops/klieg", "number": 9}')}</text>')
    t = tl.appear(1.6, until=2.7)
    b.append(box(x + 18, y + 262, PW - 36, 58, RED, t))
    b.append(lines(x + 32, y + 286, ["← ry-ops/klieg#9 checks are pending,", "  not green."], 12.5, RED, t))
    # Second try, green and signed: merged, pinned to the commit that was checked.
    b.append(f'<text class="mono {tl.hold(3.3)}" x="{x + 20}" y="{y + 246}" font-size="11" fill="{AMBER}">→ klieg_merge_pr {esc('{"repo": "ry-ops/klieg", "number": 9}')}</text>')
    t = tl.hold(3.9)
    b.append(box(x + 18, y + 262, PW - 36, 82, GREEN, t))
    b.append(lines(x + 32, y + 286, ["gh pr merge 9 --squash", "  --match-head-commit 6ff2577…", "← merged"], 12.5, GREEN, t))
    b.append(lines(x + 22, y + 384, ["Refused: closed, draft, no checks,", "a failed or running check, or a head", "commit GitHub hasn't verified."],
                   12.5, DIM, mono=False, step=19))
    return b


def billing_gate(tl):
    x, y = XS[1], PY
    b = [panel(tl, 1, "Billing prompts are yours", 5.2, 10.0)]
    b.append(f'<text x="{x + 22}" y="{y + 82}" class="sans" font-size="14" font-weight="700" fill="{TEXT}">operator-agent@kernel</text>')
    b.append(badge(x + PW - 20, y + 78, "blocked"))
    b.append(f'<text x="{x + 22}" y="{y + 102}" class="sans" font-size="12" fill="{DIM}">openrig · claude · reason: billing</text>')
    # The seat's screen, from Tests/SelfTest/Fixtures/openrig/capture-credits.json (balance redacted there).
    b.append(f'<rect x="{x + 18}" y="{y + 116}" width="{PW - 36}" height="168" rx="8" fill="#07080b" stroke="{EDGE}"/>')
    b.append(f'<rect class="{tl.appear(6.6, until=10.0)}" x="{x + 26}" y="{y + 124}" width="{PW - 52}" height="22" rx="4" fill="{AMBER}" fill-opacity=".2"/>')
    screen = ["Fable 5.1 now uses usage credits", "",
              "Fable 5.1 runs on usage credits — you", "have $XX.XX in credits.", "",
              "❯ Switch to Opus 5.5 and continue", "  Manage usage credits on claude.ai", "",
              "Enter to confirm · Esc to cancel"]
    b.append(lines(x + 32, y + 140, screen, 11.5, "#c9ced8", step=16.5))
    b.append(lines(x + 20, y + 310, ["→ klieg_answer_prompt", '  {"agent": "operator-agent@kernel", "answer": "1"}'], 11.5, AMBER,
                   tl.hold(6.0), step=17))
    t = tl.hold(7.2)
    b.append(box(x + 18, y + 338, PW - 36, 98, RED, t))
    b.append(lines(x + 32, y + 362, ["← operator-agent@kernel is showing a", '  prompt about "usage credit". Klieg',
                                     "  doesn't answer billing or usage-credit", "  prompts; open the seat and answer it",
                                     "  yourself."], 12, RED, t, step=16.5))
    b.append(f'<text class="sans {tl.hold(8.4)}" x="{x + 22}" y="{y + 458}" font-size="12.5" fill="{DIM}">In the app, Answer is off for billing prompts.</text>')
    return b


def dialog(x, y, w, title, message, confirm, cls):
    h = 74 + 18 * len(message) + 54
    out = f'<g class="{cls}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{CARD2}" stroke="{EDGE}"/>'
    out += f'<text x="{x + w / 2}" y="{y + 30}" text-anchor="middle" class="sans" font-size="14.5" font-weight="700" fill="{TEXT}">{esc(title)}</text>'
    out += "".join(f'<text x="{x + w / 2}" y="{y + 54 + i * 18}" text-anchor="middle" class="sans" font-size="12" fill="{DIM}">{esc(m)}</text>'
                   for i, m in enumerate(message))
    by = y + h - 40
    out += (f'<rect x="{x + 16}" y="{by}" width="{w - 32}" height="28" rx="7" fill="{RED}" fill-opacity=".85"/>'
            f'<text x="{x + w / 2}" y="{by + 19}" text-anchor="middle" class="sans" font-size="12.5" font-weight="700" fill="white">{esc(confirm)}</text>')
    out += (f'<rect x="{x + 16}" y="{by - 34}" width="{w - 32}" height="28" rx="7" fill="{EDGE}"/>'
            f'<text x="{x + w / 2}" y="{by - 15}" text-anchor="middle" class="sans" font-size="12.5" font-weight="600" fill="{TEXT}">Cancel</text>')
    return out + "</g>", h


def confirm_gate(tl):
    x, y = XS[2], PY
    b = [panel(tl, 2, "The app asks first", 10.0, 14.6)]
    d1, h1 = dialog(x + 18, y + 62, PW - 36, "Stop dev-build@klieg-pair?",
                    ["This ends the seat's session and any turn in", "progress. Its rig stays up; you can restart the",
                     "seat from OpenRig."], "Stop dev-build@klieg-pair", tl.hold(10.4))
    b.append(d1)
    d2, _ = dialog(x + 18, y + 62 + h1 + 14, PW - 36, "Squash-merge ry-ops/klieg #9?",
                   ['"M4: README for 0.1.0" goes into main as one', "squashed commit and its branch is deleted.",
                    "Klieg checks again that CI passed and the", "commit is signed."], "Squash-merge ry-ops/klieg #9", tl.hold(12.0))
    b.append(d2)
    return b


def build():
    tl = Timeline(D, fade=0.4, prefix="g")
    b = [frame(W, H, "Guardrails"), dots(W, H)]
    b += merge_gate(tl) + billing_gate(tl) + confirm_gate(tl)
    b.append(f'<text x="{W // 2}" y="{H - 20}" text-anchor="middle" class="sans" font-size="14" fill="{DIM}">'
             'Klieg refuses what only you should decide, and asks before anything that\'s hard to undo.</text>')
    return {"guardrails.svg": svg(W, H, "\n".join(b), tl.css(), "Klieg's guardrails",
                                  "Three gates in turn. One: klieg_merge_pr refuses ry-ops/klieg#9 while its checks are pending, "
                                  "then merges it once CI passed and the head commit is verified, pinned to that commit. Two: "
                                  "operator-agent@kernel is stopped at a usage-credits prompt, and klieg_answer_prompt refuses to "
                                  "answer it. Three: the app asks before stopping a seat and before squash-merging a pull request.")}
