"""Shared style for Klieg's animated SVGs (docs/images/*.svg). Standard library only.

Every SVG animates with CSS and SMIL only, never script, so it plays inside a GitHub README.
Each one stands still under prefers-reduced-motion. Names, PR numbers and events in the
pictures come from the real build of Klieg on 2026-10-31.

Each visual lives in its own module in scripts/visuals/ with a `build()` that returns
{"name.svg": svg_text}. scripts/make-visuals.py runs them all.
"""
import html

SANS = "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"

# The stage.
BG, CARD, CARD2, EDGE = "#0b0d12", "#12151d", "#171b25", "#262b38"
TEXT, DIM, FAINT = "#e8eaf0", "#8a92a6", "#4a5163"
# The light.
AMBER, AMBER_SOFT, CREAM = "#ffc861", "#ffdf9e", "#fff3d6"
ACCENT = "#3d8cff"            # Klieg blue: the agent in the spotlight
# Agent status colours, matching the app's badges.
STATUS = {
    "working": "#4c9bff",
    "blocked": "#ff9f43",
    "done": "#5be37d",
    "idle": "#8a92a6",
    "unknown": "#b48cff",
    "stopped": "#4a5163",
}
SOURCE = {"herdr": "#5ac8fa", "openrig": "#ff6fae", "github": "#b9c0d0"}


def esc(s):
    return html.escape(str(s), quote=True)


class Timeline:
    """Turns seconds into keyframe percentages for one looping cycle of `duration` seconds.
    Each method returns a CSS class name; css() returns the rules to put in <style>."""

    def __init__(self, duration, fade=0.6, prefix="k"):
        self.d = duration
        self.fade = fade
        self.rules = []
        self.n = 0
        self.prefix = prefix

    def p(self, t):
        return max(0.0, min(100.0, t / self.d * 100))

    def _name(self):
        self.n += 1
        return f"{self.prefix}{self.n}"

    def appear(self, t, until=None, ease=0.25):
        """Fades in at t and stays until `until` (default: just before the cycle ends)."""
        name = self._name()
        end = until if until is not None else self.d - self.fade
        a, b, c, e = self.p(t), self.p(t + ease), self.p(end), self.p(end + (ease if until else self.fade))
        self.rules.append(f"@keyframes {name}{{0%,{a:.3f}%{{opacity:0}}{b:.3f}%,{c:.3f}%{{opacity:1}}{min(e, 100):.3f}%,100%{{opacity:0}}}}"
                          f".{name}{{opacity:0;animation:{name} {self.d}s linear infinite}}")
        return name

    def hold(self, t, ease=0.25):
        """Fades in at t and stays to the end of the cycle. Unlike appear(), it is visible under
        prefers-reduced-motion, so use it for everything that makes up the end state."""
        name = self._name()
        a, b = self.p(t), self.p(t + ease)
        self.rules.append(f"@keyframes {name}{{0%,{a:.3f}%{{opacity:0}}{b:.3f}%,100%{{opacity:1}}}}"
                          f".{name}{{animation:{name} {self.d}s linear infinite}}")
        return name

    def visible_until(self, t, ease=0.25):
        """Shown from the start of the cycle and fades out at t."""
        name = self._name()
        a, b = self.p(t), self.p(t + ease)
        self.rules.append(f"@keyframes {name}{{0%,{a:.3f}%{{opacity:1}}{b:.3f}%,100%{{opacity:0}}}}"
                          f".{name}{{animation:{name} {self.d}s linear infinite}}")
        return name

    def slide(self, t0, t1, dx=0, dy=0):
        """Moves by (dx, dy) between t0 and t1, then holds."""
        name = self._name()
        a, b = self.p(t0), self.p(t1)
        self.rules.append(f"@keyframes {name}{{0%,{a:.3f}%{{transform:translate(0,0)}}{b:.3f}%,100%{{transform:translate({dx:.2f}px,{dy:.2f}px)}}}}"
                          f".{name}{{animation:{name} {self.d}s ease-in-out infinite}}")
        return name

    def grow(self, t0, t1):
        """Scales from 0 to full width (from the left edge) between t0 and t1."""
        name = self._name()
        a, b, c = self.p(t0), self.p(t1), self.p(self.d - self.fade)
        self.rules.append(f"@keyframes {name}{{0%,{a:.3f}%{{transform:scaleX(0)}}{b:.3f}%,{c:.3f}%{{transform:scaleX(1)}}100%{{transform:scaleX(1)}}}}"
                          f".{name}{{transform-box:fill-box;transform-origin:0 50%;transform:scaleX(0);animation:{name} {self.d}s linear infinite}}")
        return name

    def rotate(self, stops, ox, oy):
        """Rotates around (ox, oy) in view-box units through stops [(t, degrees), ...], easing between them."""
        name = self._name()
        frames = [f"{self.p(t):.3f}%{{transform:rotate({deg}deg)}}" for t, deg in stops]
        if stops[0][0] > 0:
            frames.insert(0, f"0%{{transform:rotate({stops[0][1]}deg)}}")
        if stops[-1][0] < self.d:
            frames.append(f"100%{{transform:rotate({stops[-1][1]}deg)}}")
        self.rules.append(f"@keyframes {name}{{{''.join(frames)}}}"
                          f".{name}{{transform-box:view-box;transform-origin:{ox}px {oy}px;animation:{name} {self.d}s ease-in-out infinite}}")
        return name

    def pulse(self, t0, t1, period=1.2):
        """Gently pulses opacity between t0 and t1 (an attention glow), hidden otherwise."""
        name = self._name()
        frames = [f"0%,{self.p(t0):.3f}%{{opacity:0}}"]
        t, on = t0, True
        while t < t1:
            frames.append(f"{self.p(t):.3f}%{{opacity:{1 if on else 0.35}}}")
            t += period / 2
            on = not on
        frames.append(f"{self.p(t1):.3f}%{{opacity:1}}{min(self.p(t1 + 0.3), 100):.3f}%,100%{{opacity:0}}")
        self.rules.append(f"@keyframes {name}{{{''.join(frames)}}}.{name}{{opacity:0;animation:{name} {self.d}s linear infinite}}")
        return name

    def motion(self, t0, t1):
        """SMIL attributes that move an element along an <mpath>/path between t0 and t1, every cycle."""
        assert 0 <= t0 < t1 <= self.d, f"motion {t0}-{t1} doesn't fit a {self.d}s cycle"
        a, b = t0 / self.d, t1 / self.d
        return f'dur="{self.d}s" repeatCount="indefinite" keyPoints="0;0;1;1" keyTimes="0;{a:.4f};{b:.4f};1" calcMode="linear"'

    def css(self):
        return "\n".join(self.rules)


def svg(w, h, body, css, title, desc):
    """A complete SVG document. Under prefers-reduced-motion every animation stops at its end state."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-labelledby="t d">
<title id="t">{esc(title)}</title>
<desc id="d">{esc(desc)}</desc>
<style>
.sans{{font-family:{SANS}}}
.mono{{font-family:{MONO}}}
@media (prefers-reduced-motion: reduce){{*{{animation-duration:0s!important;animation-delay:0s!important;animation-iteration-count:1!important}}}}
{css}
</style>
{body}
</svg>
"""


def frame(w, h, label=None):
    """The rounded dark card every visual sits on, with an optional small caps label."""
    out = f'<rect width="{w}" height="{h}" rx="18" fill="{BG}"/>'
    out += f'<rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="17.5" fill="none" stroke="{EDGE}"/>'
    if label:
        out += f'<text x="28" y="38" class="sans" font-size="13" font-weight="600" fill="{DIM}" letter-spacing="1.6">{esc(label.upper())}</text>'
    return out


def dots(w, h, id_="dots"):
    """Pattern def plus a rect: a faint stage-floor dot grid."""
    return (f'<defs><pattern id="{id_}" width="22" height="22" patternUnits="userSpaceOnUse">'
            f'<circle cx="1" cy="1" r="1" fill="{FAINT}" opacity=".35"/></pattern></defs>'
            f'<rect width="{w}" height="{h}" rx="18" fill="url(#{id_})"/>')


def badge(x, y, status, cls=""):
    """A status pill like the app's (right edge at x)."""
    c = STATUS[status]
    w = 14 + 7.2 * len(status) + 14
    c_attr = f' class="{cls}"' if cls else ""
    return (f'<g{c_attr}><rect x="{x - w:.1f}" y="{y - 13}" width="{w:.1f}" height="22" rx="11" fill="{c}" fill-opacity=".18"/>'
            f'<circle cx="{x - w + 12:.1f}" cy="{y - 2}" r="3.5" fill="{c}"/>'
            f'<text x="{x - w + 21:.1f}" y="{y + 2.5}" class="sans" font-size="12" font-weight="700" fill="{c}">{esc(status)}</text></g>')


def agent_card(x, y, w, h, name, source, kind="claude", cwd=None):
    """The static part of an agent card (name, source line, cwd). Status badges go on top."""
    sc = SOURCE.get(source, DIM)
    out = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{CARD}" stroke="{EDGE}"/>'
    out += f'<circle cx="{x + 20}" cy="{y + 25}" r="5" fill="{sc}"/>'
    out += f'<text x="{x + 34}" y="{y + 30}" class="sans" font-size="15" font-weight="700" fill="{TEXT}">{esc(name)}</text>'
    out += f'<text x="{x + 20}" y="{y + 54}" class="sans" font-size="12" fill="{DIM}">{esc(source)} · {esc(kind)}</text>'
    if cwd:
        out += f'<text x="{x + 20}" y="{y + 74}" class="mono" font-size="11" fill="{FAINT}">{esc(cwd)}</text>'
    return out
