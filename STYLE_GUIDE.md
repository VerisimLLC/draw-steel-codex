# Panel Style Guide

The design language for Codex panels, established during the Floors & Layers and
Maps redesigns (2026-08). This is the *prescriptive composition* guide: which
tokens, sizes, and states to reach for so every panel reads as one system.
For the raw token/class catalog see [DefaultStyles.md](DefaultStyles.md); for
engine mechanics see [UI_BEST_PRACTICES.md](UI_BEST_PRACTICES.md) and
[ThemeEngine.md](ThemeEngine.md). Reference implementations:
`DMHub Core Panels/Floors.lua` and `DMHub Core Panels/MapsPanel.lua`.

## Principles

1. **Quiet dark surface.** Rows and controls are transparent at rest on the
   panel's dark ground. Structure comes from faint hairlines and grouping,
   not fills.
2. **Identity louder than state.** A row's *name* is the brightest thing on
   it. State (selected, current, hovered) is shown with a restrained fill and
   an accent edge - never with a bright inverse fill that outshouts the
   content. (The old parchment `@bgInverse` selected bars are retired; so is
   the `@fgInverse` text special-casing they forced.)
3. **Chrome recedes until approached.** Per-row buttons (gears etc.) sit
   muted at rest and brighten on hover. Nothing interactive is invisible,
   but nothing idle competes with content.
4. **One interaction grammar.** Click a row = its primary action. Double-click
   a name = rename. Gear / right-click = settings and secondary actions.
   Drag always has a non-drag alternative.

## Color usage

Always `@tokens`, resolved via ThemeEngine. Never hex literals in panel code.

| Use | Token |
|---|---|
| Panel ground / input fills | `@bg` |
| Hover fill, selected-row fill | `@bgAlt` |
| Row names, control glyphs at full strength | `@fg` |
| Selected/current row name, focus border | `@fgStrong` |
| Reference info: counts, spans, sublabels, muted glyphs | `@fgMuted` |
| Hairlines, control borders | `@border` (drop opacity for seams, below) |
| Selected-row edge, drag-target hover bars, primary emphasis | `@accent` |
| Destructive text/icons (delete-pending, warnings) | `@danger` |
| New-content markers | `@info` |

**Don't:** use `@accent`/`@bgInverse` as a row fill for state; use `@fgInverse`
anywhere except on a genuine inverse fill; introduce new colors for one panel.

## Type scale

| Role | Size / weight / color |
|---|---|
| Row name | 14-16 regular `@fg` (14 for dense lists, 16 for roomy rows) |
| Row name, selected/current | same size, **bold**, `@fgStrong` |
| Section/folder header | 13 **bold** `@fg`; hover `@fgStrong` |
| Reference info (spans, counts, sublabels) | 10-11 `@fgMuted` (counts may sit at 0.7 opacity) |
| Overflow chips ("+N") | 11 **bold** `@fgMuted` |
| Modal titles | the shared `modalTitle` class |
| Form labels | the shared `formStacked` / `formPanel` classes |

## Row grammar

The core recipe (see `{mapRow}` in MapsPanel.lua, `{floorPanel}` in Floors.lua):

- Transparent at rest: `bgimage = "panels/square.png"`, `bgcolor = "clear"`.
- `hover` -> `bgcolor = "@bgAlt"`, `transitionTime = 0.1`.
- `selected` / current -> `@bgAlt` fill + `border = {x1 = 3}` in `@accent`,
  and the name label goes bold `@fgStrong` (via a `parent:selected` rule).
- Edge-to-edge: rows are `width = "100%"` with their own `hpad = 12` +
  `borderBox = true`; the panel root carries **no** horizontal inset.
- Heights: 34 for single-line rows, ~56 when the row carries a thumbnail.
  Fixed heights - rows never grow with content (cap and chip instead).
- Spacing between rows is PADDING inside the row (or fixed pitch), never
  margins, so a selected row's fill runs the full pitch.

## Separators

- **Seam hairline** between sibling rows: 1px, `bgcolor = "@border"`,
  `opacity = 0.2`. A hint of structure, not a table grid.
  **Density exception**: lists with row pitch under ~30px (e.g. the
  Character panel's 24px member rows) skip per-row seams entirely - at
  that density they read as a grid; hover and section underlines carry
  the structure instead.
- **Section underline** beneath group headers: same 1px `@border` at
  `opacity = 0.35` - one step louder than seams.
- Suppress a seam where a header/rule already marks the boundary (never
  double up), and where there is nothing above (top of list). Close the
  list with a hairline under the last row.
- Seams must collapse while a search filter is active (rows hide
  individually; orphaned seams read as clutter).

## Section / folder headers

Caret + label + optional count + underline (see `mapFolderHeader`):

- `gui.ExpandoArrow` with `bgimage = "phosphor/caret-down-fill.png"` (the
  default triangle bitmap reads fuzzy at header size).
- Label 13 bold `@fg`, hover `@fgStrong` (headers are live: rename, drag,
  collapse). Height ~30 with a small top margin to give groups air.
- Count (direct children) right-aligned, 10-11 `@fgMuted`.
- Full-width 1px underline at `@border` opacity 0.35 (a separate in-flow
  panel: the layout has no fill-remaining primitive, so a label-to-edge
  rule only works with fixed-width labels like GROUND LEVEL).

## Iconography

- Panel chrome uses **Phosphor masks** (`phosphor/*.png`): caret-down-fill,
  plus-bold, folder-plus-duotone, gear via the `settingsButton` class, etc.
  They match at small sizes; legacy bitmap icons (`ui-icons/Plus.png`,
  `panels/triangle.png`) read fuzzy or dated next to them.
- Sizes: 16px row gears, 26px footer action buttons.
- Per-row gears: `@fgMuted` at ~0.5 opacity at rest, `@fg` full on hover
  (see the buttonIcon rules in MapsPanel.lua). The gear floats at the
  row's right edge, out of the reading path.
- Icon swaps are **scoped to the panel's own style block** so app-wide
  classes (e.g. `addButton`) are untouched elsewhere.

## Controls

- **Search field**: `gui.SearchInput` + the bordered variant:
  `borderWidth = 1, borderColor = "@border"`, focus -> `@fgStrong`,
  `fontSize = 13, bold = false`. ALWAYS pass `borderBox = true` at the
  call site - SearchInput ships `hpad = 24` for its magnifier and will
  overflow its declared width without it.
- **Sliders** inside rows: the muted recipe (`MutedPercentSliderStyles` in
  Floors.lua) - 12px track, `@border` frame, `@fgMuted` fill.
- **Settings dialogs**: `framedPanel` modal, width 480, `modalTitle`,
  `formStackedRow`/`formStacked` pairs, Close button with
  `escapeActivates` + `EscapePriority.EXIT_MODAL_DIALOG`. Opened from the
  row gear and mirrored in the right-click menu (`"<Thing> Settings..."`).
- **Drag targets**: invisible 2px strips at rest (`bgcolor = "clear"`),
  10px `@accent` bar on `drag-target-hover`. Never permanently visible.
- **Token portraits** in rows: 20px, cap at 5, then a "+N" chip.
- **Player-controlled marker**: a small (~9px) pale-yellow dot
  (`icons/icon_simpleshape/icon_simpleshape_31.png`, `#ffffaaff`) floating
  at the portrait's bottom-right corner. This is the ONE glyph for
  "player-controlled primary character" everywhere (the Character panel's
  old in-flow star column is retired).

## Implementation pattern

- Build the panel's custom rules in a `local function BuildXxxStyles()`
  returning a style array; attach with
  `styles = ThemeEngine.MergeStyles(BuildXxxStyles())` at the panel root
  (or `MergeTokens` if a themed ancestor already carries the cascade), and
  re-assign inside `ThemeEngine.OnThemeChanged(mod, ...)` so scheme
  switches recolor live.
- Scope by subtree, not by selector gymnastics: rules attached to the
  panel root only affect that panel. Remember `parent:` in selectors
  matches the DIRECT parent only - there is no ancestor selector.
- Dock panels should pin their height to content where the content is a
  short finite list (see `fitDock` in Floors.lua).

## Panel-pass checklist

When bringing an old panel onto this language:

- [ ] Zebra striping removed; rows transparent with hover/selected per above
- [ ] No `@fgInverse` text patches left behind
- [ ] Seams + section underlines per the separator rules
- [ ] Headers on the section-header grammar with counts where useful
- [ ] One-click primary action; rename via double-click; gear + right-click settings
- [ ] Chrome muted at rest; Phosphor masks; scoped icon swaps
- [ ] Search field bordered + `borderBox`
- [ ] Every capability of the old surface relocated, none silently dropped
- [ ] `luac -p` clean; verified in the running app via screenshot
