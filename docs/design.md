# Klieg design standards

Klieg's app looks like herdr: a terminal multiplexer, not a Mac app. These are the rules, taken from herdr's own screens. Everything in `Sources/KliegApp` follows them; `Theme.swift` holds the values.

## The one-line version

Monospace everywhere, flat dark surfaces, one-pixel borders, one accent, words instead of icons, lowercase labels, and the keyboard first.

## Surfaces

| Token | Value | Used for |
| --- | --- | --- |
| `bg` | `#131418` | the window |
| `panel` | `#17181d` | sidebar, tab bar, key-hint bar, modal boxes |
| `raised` | `#1d1e25` | the selected row, hovered rows, buttons that look like buttons |
| `border` | `#2b2d38` | every border and rule |
| `text` | `#e4e4ea` | body text |
| `dim` | `#8b8d9b` | labels, headers, secondary lines |
| `faint` | `#555867` | hints, placeholders, disabled |
| `accent` | `#c3a6ff` | the selected tab, the focused frame, keys in buttons, links |
| `accentInk` | `#1a1426` | text on the accent |

- Flat. No shadows, no blur, no translucency, no gradients.
- Corners are square or at most 4 points. Nothing is a capsule.
- Borders are one pixel of `border`. A frame that needs attention uses the status colour instead.
- There is one accent. herdr's is lavender; a theme may swap it (herdr's warm theme uses gold `#e0a438`) but never adds a second one.

## Status colours

| State | Colour | Dot |
| --- | --- | --- |
| working | `#f2c94c` yellow | filled |
| blocked (needs you) | `#f06292` pink | ring with a filled centre |
| done | `#6fdc8c` green | filled |
| idle | `#9aa0ad` grey | hollow ring |
| unknown | `#b48cff` | filled |
| stopped | `#555867` | hollow ring |

Status colours also colour the status word (`working · claude`), a frame border when an agent needs you, and the glyph on a timeline line. They never fill a badge.

## Type

- One family: the system monospace (`Theme.mono`). No proportional text anywhere, including dialogs and settings.
- Sizes: 11 for dense output, 12 and 12.5 for secondary lines and hints, 13 for body, 14 for tabs and headers, 15 for names. Nothing larger.
- Hierarchy comes from colour (`text` › `dim` › `faint`), not size. Names are semibold; everything else is regular.
- Labels and headers are lowercase: `spaces`, `agents`, `grouped`, `new`, `menu`, `needs you`. Proper nouns keep their case (`Claude Code`).

## Words, not icons

- No SF Symbols. A glyph is a character from the terminal: `·` separator, `›` go, `«` collapse, `↑` ahead, `✓` done, `×` stopped, `!` needs you, `+` new, `●` and `○` status.
- Actions are words: `open`, `prompt`, `answer`, `stop`, `merge`, `save`. A destructive word is pink.
- A button that has a key shows it first, in the accent: `[⌘↩] send`, `[esc] cancel`, `[y] stop`.

## Layout

```
┌ sidebar 290 ─┬─ tab bar 36 ───────────────────────────┬─ right column (optional) ─┐
│ spaces       │ [all] [m1] [dev-build] … [shell] [+]    │ ┌ dev-server ───────────┐ │
│  ● herdr     ├─────────────────────────────────────────┤ │ output …              │ │
│    main      │ ┌ claude ──────────────────────────────┐│ │                       │ │
│  ○ docs      │ │                                      ││ │                       │ │
│    feat/x    │ │  the pane: a live terminal, a feed,  ││ │                       │ │
│              │ │  or a panel (timeline, prs, settings)││ │                       │ │
│ new    menu  │ │                                      ││ │                       │ │
│ agents  grpd │ └──────────────────────────────────────┘│ └───────────────────────┘ │
│  ● m1        │ ~/src/klieg · git:main · opus · working │                           │
│    working   ├─────────────────────────────────────────┴───────────────────────────┤
│              │ ⌘↑↓ space  ⌘1-9 tab  ⌘T shell  ⌘K commands  ⌘R refresh   ● 1 needs you │
└──────────────┴─────────────────────────────────────────────────────────────────────┘
```

- **Sidebar**: `spaces` on top (a herdr workspace or an OpenRig rig: bold name, dim second line with the folder and branch), `agents` below (status dot, name, `state · tool`). `grouped` on the agents header toggles grouping by space. The selected row has the `raised` background, nothing else.
- **Tab bar**: one tab per agent in the space plus any shells and panels. The selected tab is `accent` with `accentInk` text. Tabs are numbered by position (⌘1-9). `+` opens a shell.
- **Pane**: a titled frame. The title is cut into the top border (`claude`, `shell`, `timeline`). The frame is `accent` when it holds the focused terminal, `dim` for a panel, the status colour when the agent needs you.
- **Status line**: one line under the pane, mono 12: `cwd · git:branch · model · state`, with a meter on the right when there is one.
- **Key-hint bar**: 30 points at the bottom with the keys that work right now, and on the right the refresh time, `read-only` when set, and `● n need you` in pink.
- **Window**: no title bar. The traffic lights float over the sidebar's top padding. The app fills the window edge to edge.

## Inputs and dialogs

- A text field is plain mono text on `panel` with a one-pixel rule under it (the accent, or pink for an answer to a blocked agent). No rounded border, no focus ring.
- A multi-line field is the same, taller, with the rule above and below.
- A toggle is text: `[x] read-only` / `[ ] read-only`.
- Nothing opens a macOS sheet, alert or confirmation dialog. Dialogs are boxes drawn over the window on a dimmed backdrop, like the command palette: a `panel` box with a `border`, a lowercase title, the content, and a row of key-buttons. `esc` always closes; `⌘↩` or `↩` confirms. A destructive confirmation names what it does in its key-button: `[y] stop dev-build`.
- Errors show in the same box (`klieg couldn't do that` + the message + `[esc] ok`), or inline in red under the field that caused them.

## Copy

Short, lowercase, plain: `no agents yet`, `nobody needs you`, `needs you · it's asking to approve a command`, `reading…`, `couldn't read this screen: …`. Say what Klieg did or couldn't do, never what the user "should" do.

## Motion

None. The cursor blinks; everything else appears.

## What is not herdr

Menus, the menu-bar extra, notifications and the Settings window title use the system's own look: they live outside Klieg's window, and a terminal-styled macOS menu would be stranger than a plain one.
