# Klieg's animated SVGs

`python3 scripts/make-visuals.py [module …]` writes docs/images/*.svg. Standard library only.

Rules for every visual:
- One module per visual in this folder, with `build()` returning `{"name.svg": text}`. Don't edit another builder's module.
- Use `common.py` for colours, fonts, `Timeline`, `svg()`, `frame()`, `badge()` and `agent_card()`. Add to `common.py` only when a helper is clearly shared, and say so in the PR.
- CSS and SMIL animation only: no `<script>`, no external fonts or images, nothing GitHub's image proxy would block.
- 1280 px wide, dark stage (`frame()`), 10-16 s loop. Under prefers-reduced-motion everything stops at its end state, which must still read well on its own.
- Real data only: agent names, PR numbers, tool names and events from the actual Klieg build (2026-10-31). Check them against the code and `gh pr list -R ry-ops/klieg --state merged`.
- Keep each file under ~40 KB. Give every SVG a `<title>` and a `<desc>` that says what the animation shows, for screen readers.
