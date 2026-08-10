---
name: responsive-panel
description: Make a DockablePanel or any codex panel responsive -- survive user resizing (especially horizontal) and the Font Size setting (80%-140%) while staying attractive. Use when asked to "make this panel responsive/resizable", "respect the font size setting", "this panel clips/overflows when resized or at bigger fonts", when registering a panel with resizable width, or when reviewing a panel for resize/font-size robustness. Pairs with dmhub-gui (general GUI authoring), theme-engine-discipline (tokens/classes), and ui-harness (seeing the result).
---

# Responsive Panels: Resizing + the Font Size Setting

## The two forces, and the one doctrine

A panel must survive two things it does not control:

1. **Resize.** The same registered content is mounted in a fixed **364px-wide dock**
   (`DockablePanel.DockWidth`) and in a **floating icon-rail window** the user can drag-resize
   on all 8 edges/corners (`gui.WindowResizePanel`, default content size 380x520). On resize
   the engine writes the *window root's* `selfStyle.width/height` only; your content gets **no
   event** -- it relayouts because it is percent-sized. If it is not percent-sized, it does not
   respond at all.
2. **Font Size.** The `fontsize` setting (General settings, 80%-140%, preference storage,
   `DMHub Titlescreen/Settings.lua`) becomes `GameConfig.fontMagnification` in the engine. It
   multiplies the **rendered point size** of every Label/Input/Dropdown/TextEditor at style-apply
   time (`SheetLabel.cs UpdateLabelStyle`, `SheetInput.cs`, `SheetDropdown.cs`,
   `SheetTextEditor.cs`). It does **not** scale panels, padding, margins, icons, or any pixel
   width/height you wrote -- the exception is the `em`/`sp` dimension forms (grammar table
   below), which exist precisely to opt chrome into this scaling. Changing it dirties every
   panel tree, forcing a full live re-layout (`GameConfig.cs`, search `fontMagnification`).

The engine gives you exactly one bridge between the two worlds, and it is the whole doctrine:

> **`auto`-sized text boxes are measured at the *magnified* font size.**
> (`SheetLabel.CalculateAutoSizeText` keys its cache on the live `label.fontSize`.)
>
> So: **relative widths + `auto` text heights = free responsiveness.** A label with
> `width = "100%", height = "auto", textWrap = true` reflows correctly for BOTH forces with
> zero extra code. A label in a fixed-pixel box handles neither. Every recipe below is a
> restatement of this.

## Step 0: know your geometry contract

Before touching layout, know what the panel will be mounted into:

- **Dock:** width is exactly 364 and not negotiable. Height is negotiated: `fitChildren`
  squeezes/stretches each docked panel between its registered `minHeight`/`maxHeight` to fill
  the dock. Content is auto-wrapped in a scroll parent `width = "100%-4", pad = 2, vscroll =
  true` unless you register `vscroll = false`.
- **Window:** content area is `width = "100%", height = "100%-33"` under a 32px header (which
  grows if tab chips wrap -- the header rewrites the content area height itself). Your content
  root is forced `halign = "left", valign = "top"`. All tabs of one window share the same rect.
- **Registration bounds are CONTENT-relative** -- the window adds the 32px header on top when
  clamping. `minHeight == maxHeight` locks the vertical resize axis entirely (Dice 160, Audio
  470, Clipboard 250 do this).
- Window sizes are remembered per session only (`_tmp_location`); every new session starts at
  the registration defaults, so the defaults must look good on their own.

### Registration recipe

```lua
DockablePanel.Register{
    name = "My Panel",
    icon = mod.images.myIcon,
    minHeight = 200,           -- content-relative; default 40
    maxHeight = 900,           -- default 1080
    minWidth = 320,            -- window only; default 300. Design floor, see below.
    maxWidth = 900,            -- default unbounded. Cap it if unlimited width goes ugly.
    -- resizableWidth = false, -- lock an axis outright if the design demands it
    -- resizableHeight = false,
    -- vscroll = false,        -- only if the panel manages its own scrolling (Chat does)
    content = function()
        return CreateMyPanel()
    end,
}
```

`minWidth` is your promise that the layout works at that width -- pick it by actually looking
(see Verify below), not by guessing. As of 2026-08 **no shipped panel registers
minWidth/maxWidth/resizableWidth yet** -- the plumbing is verified but you are an early
adopter; test the clamps live.

## The layout skeleton

The canonical shape of a responsive panel body. Deviate knowingly, not accidentally:

```lua
gui.Panel{
    width = "100%", height = "100%", flow = "vertical",

    -- fixed chrome (toolbar): pins its own height, never the panel's width
    gui.Panel{
        width = "100%", height = "auto", flow = "horizontal", borderBox = true, hpad = 8,
        gui.Label{ classes = {"label"}, text = "Title", width = "auto", height = "auto" },
        -- right-aligned trailing controls pack from the right edge automatically:
        gui.Button{ halign = "right", classes = {"sizeS"}, text = "Add" },
    },

    -- the scroll region absorbs ALL vertical overflow
    gui.Panel{
        width = "100%", height = "100% available",   -- see grammar table
        vscroll = true, flow = "vertical",
        rpad = 12, borderBox = true,                 -- scrollbar gutter; see below
        -- rows: full width, natural height
        gui.Panel{
            width = "100%", height = "auto", flow = "vertical",
            gui.Label{ classes = {"label"}, width = "100%", height = "auto",
                       textWrap = true, text = longBodyText },
        },
    },
}
```

Key properties of this skeleton:

- Nothing names a pixel width except deliberate fixed chrome (an icon, a fixed sidebar).
- Every text row is `height = "auto"` -- so at 140% font the rows get taller and the scroll
  region absorbs it. A fixed-height row is a future clipping bug.
- Vertical overflow has exactly one designated place to go (the vscroll region). Horizontal
  overflow has none -- it must be prevented by relative widths, wrapping, or shrinking.

## Sizing grammar (what width/height actually accept)

Parser: `CharacterSheetWidget.cs DimensionCalculation`. C# is ground truth; the stubs and
UI_BEST_PRACTICES lag it in the places marked (!).

| Form | Meaning |
|---|---|
| `240` | pixels |
| `"auto"` | content size. For labels: measured at the MAGNIFIED font size |
| `"50% auto"` | content size x 0.5 (undocumented but real) |
| `"40%"` | 40% of the parent's CONTENT box (parent padding excluded) |
| `"100%-20"`, `"auto+4"` | one additive offset only -- `"100%-20-5"` does not parse |
| `"width"` / `"height"`, `"50% height"` | relative to the panel's own other axis (aspect ratio) |
| `"1.5em"`, `"1.5em+4"` | 1.5 x the panel's computed `fontSize` x `fontMagnification` -- rows, icons, gutters that scale with text AND the Font Size setting. Resolves against the fontSize as cascaded when its rule applies (a later rule changing only fontSize does not re-resolve it) -- set fontSize in the same or an earlier rule. Landed 2026-08-09, harness-verified at 80/100/140 |
| `"20sp"` | 20px x `fontMagnification` only ("scaled pixel" -- chrome with no local font tie). `available` does not combine with em/sp (warns, flag ignored). Pads stay plain ints -- no em there |
| `"100% available"` | fills the space left over after non-available siblings are measured; works on BOTH axes. On the parent's flow axis the percent is a flex-grow weight: `"200% available"` takes twice the share of `"100% available"`, equal percents split evenly; shares clamp to min/max with remainders redistributed; the additive offset applies after (`"100% available-8"`). On the cross axis or under `flow = "none"` it stretches to the parent content extent (percent ignored). Flow-axis `available` in a `wrap` container falls back to `auto` with a warning. Landed 2026-08-09, NEEDS ENGINE BUILD -- before that build width-available resolves to 0 and height splits evenly |
| `minWidth/maxWidth/minHeight/maxHeight` | accept all the same forms including percent, despite the stubs typing them `number` (!) |

Traps:

- Reading `element.width` back returns the RAW parsed value (`0.4` for `"40%"`), not pixels.
  Use `element.renderedWidth` / `renderedHeight` (scrollbar/padding included, uiscale not).
- A pure `width = "auto"` label NEVER wraps -- it grows sideways forever unless you give it
  `maxWidth`. `width = "auto", maxWidth = 400` is the "size to content but wrap eventually"
  idiom. With a fixed or percent width, `height = "auto"` wraps to that width.
- Percent resolves against the parent content box, so a parent with `borderBox = true` hands
  its children a base already reduced by its padding -- that is what you want. `hpad` WITHOUT
  `borderBox` makes the panel overflow instead (legacy pattern; always pair pad with borderBox).
- `wrap = true` works in BOTH horizontal and vertical flow (docs say horizontal only) (!) --
  but only against a bounded width. `flow = "horizontal", wrap = true, width = "auto"` has
  nothing to wrap against.
- `collapsed` removes a panel from flow AND skips its subtree's layout; `hidden` keeps its
  space reserved with the size frozen at hide time. For responsive show/hide, use `collapsed`.

### Flow packing (how to right-align without pixels)

In a flow, leading children with `halign = "left"` (or `valign = "top"`) pack from the start,
trailing `right`/`bottom` children pack from the end, and any centered children in between
split the leftover space. That gives you toolbar left-group/right-group behavior with no
measured widths at all. For a genuinely growing element, `"100% available"` is a real
flex-grow on both axes once the 2026-08-09 engine build lands: `[fixed][available][fixed]`
makes the middle absorb all resize, and the percent is the grow weight. Until that build,
the growing element is either `height = "100% available"` (vertical) or a complement width
like `"100%-388"` next to a 388px fixed column (the Audio panel pattern -- deterministic
complement beats a percent split when one side is genuinely fixed; still fine when the
fixed side truly is fixed).

## Making text respect the Font Size setting

Rules, in priority order:

1. **Give every label an escape axis.** `height = "auto"` (+ `textWrap = true` for prose) or
   `width = "auto"` (+ `maxWidth` cap). Text that can grow somewhere never clips. This is 90%
   of font-size support.
2. **Size hierarchy with percent fontSize, not pixel ladders.** `fontSize = "140%"` in a style
   rule MULTIPLIES the cascaded font size (`fontSizeMult` in the engine) and stacks down the
   tree. A panel whose heading is `"140%"` of a body set once at the root rescales coherently
   from a single knob. Precedents: `chat-message-panel` (`fontSize = '100%'`), tooltip rules in
   Gui.lua (`'60%'`), CharacterSheetFramework heading (`'140%'`). Absolute `fontSize = 14` is
   fine as the single base; ladders of absolutes (24/18/14/12 scattered inline) are not.
   Prefer the theme size classes (`sizeXxs`..`sizeXxl`) over raw numbers where they fit.
3. **`minFontSize` is overflow insurance for one-liners, not a strategy.** For a short label
   locked in a fixed box (buttons, stat chips, column headers):
   `fontSize = 18, minFontSize = 10, width = "auto", maxWidth = 70`. The engine magnifies
   both `maxFontSize` and the `minFontSize` floor (`SheetLabel.cs`, `UpdateLabelStyle`), so
   an autoshrink label at its floor still grows with the user's Font Size setting. (Builds
   before 2026-08-08 magnified only the max, so a floored label silently absorbed the
   user's 140%.)
4. **Inputs need headroom too.** `gui.Input`/`gui.Dropdown` render text at the magnified size
   inside their box. Give single-line inputs `height = "auto"` (SheetInput's auto keeps one
   line's height) or at least 1.6x the font size; give the Chat-style growing input
   `height = "auto", minHeight = 24, maxHeight = 300`.
5. **Never compute font sizes from character counts.** The `_fitFontSize(baseSize, maxChars,
   len)` helpers (CharacterBuilder, MCDMCharacterPanel) ignore the real box, the real glyphs,
   and the magnification, and are never recomputed on resize. `minFontSize` does the same job
   in the engine, correctly, live.
6. **Chrome that should track text: size it in `em`/`sp`.** Toolbar rows
   `height = "2.2em"`, icon buttons `width/height = "1.4em"`, fixed gutters `"20sp"`.
   This is the mechanism that scales non-text layout with the setting; `height = "auto"`
   remains the right tool for text boxes themselves.
7. **A panel-local size knob copies the Journal.** If a panel wants its OWN font-size setting
   (like `journal:fontsize`), copy DocumentSystem: a `setting{}` + `multimonitor =
   {"journal:fontsize"}` on the panel + a `monitor` handler that rebuilds. Settings monitors
   are polled, so this reacts within a tick. Do NOT invent a competing global -- the global
   knob is the engine's `fontsize`; Lua never needs to read it (and today nothing does).

## Surviving width changes attractively

Handling 364 is necessary; looking good at 1500 is the other half.

- **Cap prose columns.** Full-window-width text lines are unreadable. Wrap body content in
  `gui.Panel{ width = "100%", maxWidth = 760, halign = "center" }` (or left, per design) so
  wide windows get margins instead of 300-character lines.
- **Let card/chip collections wrap.** `flow = "horizontal", wrap = true, width = "100%",
  height = "auto"` (the Multiselect chip pattern) turns extra width into more columns
  naturally. This is the cheapest "designed for resizing" look there is.
- **Two-column layouts:** fixed sidebar + complement (`"100%-388"`), or percent splits
  (`"35%"`/`"65%"`) when both sides genuinely scale. Give the shrinking side a `minWidth` so
  the registration's `minWidth` and the layout's real floor agree.
- **Breakpoints exist if you need them: the `rendered` event.** The engine fires
  `rendered(element, width, height)` on any panel whose rendered size changed
  (`SheetPanel.cs`, end of `UpdateStyle`). It is real but undocumented and unused in the
  codex so far -- treat it as the sharp tool for the rare panel that must switch layouts:

  ```lua
  gui.Panel{
      width = "100%", height = "100%",
      rendered = function(element, width, height)
          -- ONLY toggle classes here; never resize element itself (layout feedback loop)
          element:SetClassTree("narrowHost", width < 420)
      end,
      styles = {
          { selectors = {"sideColumn", "parent:narrowHost"}, collapsed = 1 },
          { selectors = {"detailLabel", "narrowHost"}, collapsed = 1 },
      },
      ...
  }
  ```

  Prefer one layout that flexes (wrap, auto, complements) over two layouts and a breakpoint.
  The only in-tree precedents for size-reactive code are polling `renderedWidth` on `think`
  (Gui.lua slider dragBounds) and clamping a card's `maxHeight` to
  `dmhub.screenDimensionsBelowTitlebar.y` (Timeline AbilitySidebar) -- both positioning-grade,
  not layout-grade. If you use `rendered`, say so in the PR/summary so it gets watched.
- **`uiscale` is the blunt instrument.** It scales a whole subtree (and DOES participate in
  layout, unlike `scale`), which is how `dockscale` shrinks the docks. It is a zoom, not
  responsiveness -- text AND chrome scale together, and it has a pivot trap: set `pivot` via
  `selfStyle` on an ATTACHED panel using the named form (`{x=0, y=0}`), never positionally and
  never only in the constructor, or it silently stays centered. Reach for it only when the
  design really is "the same picture, smaller".

## The vscroll gutter (every scrolling panel)

A `vscroll` panel lays children out at FULL width, but the moment content overflows, the
scrollbar shrinks the viewport ~6px and masks the right edge of `width = "100%"` children.
Reserve the gutter on the scrolling panel: `rpad = 12, borderBox = true`. (Alternatives seen
in-tree: a 12px spacer child in a horizontal row (Audio), or a layout constant
(NewTriggeredAbilityEditor `SCROLL_GUTTER`).) Also: with `hideObjectsOutOfScroll` (default on
for docked panels), offscreen children skip layout and their sizes go stale until scrolled
back in -- do not read `renderedWidth` from them, and expect them to snap to new font sizes
on scroll-in, which is fine.

## Anti-patterns (all currently live in the codebase -- do not copy)

1. **Fixed box + fixed font + `textWrap = false` + no `minFontSize`.** ChatPanel's
   `width = 330, height = 20` speaker row: overruns at 140%. Every one-line label in a fixed
   box needs `minFontSize` or an auto axis.
2. **Hardcoding 364.** `math.floor(364 * ...)` (CodexTitleBar), fixed multi-button rows sized
   to the dock (Audio). Breaks the moment the same content mounts in a resizable window. Use
   percentages/complements of the actual parent; if you must reference the dock, use
   `DockablePanel.DockWidth` -- and then ask whether you should.
3. **Fixed card widths threaded through render options** (`ability:Render{ width = 340 }`,
   AbilitySidebar). The card never tracks its host. Pass percent widths or let the card fill
   and cap with maxWidth.
4. **`hpad` without `borderBox`**, then compensating with `width = "100%-12"` by hand. Works
   until someone changes the pad. `borderBox = true` and plain `"100%"`.
5. **`width = "100% available"` on a pre-2026-08-09 engine build.** Silently zero there
   (GoblinScriptEditor has live instances). On builds with the weighted-available engine
   change it is the correct flex-grow idiom.
6. **`hidden` to "remove" something in a narrow layout.** Its space stays reserved. Use
   `collapsed`.
7. **A `nil` hole in a children array** truncates the list. Build conditional children with
   `collapsed` toggles or append-if patterns, never positional nils.

## Verify -- actually look at it (ui-harness skill owns the mechanics)

Never claim a panel is responsive without this loop. Follow the `ui-harness` skill for
launching (`check_connection` first; `stop_dmhub()` then `start_dmhub(extra_args="--harness
scratch")`), then:

1. **Mount the real content** at dock geometry and theme cascade:
   `TestHarness.SetStage{ size = "dock", cascade = "theme", backdrop = "contrast" }` --
   contrast magenta makes overflow and clipping unmissable.
2. **Sweep widths.** Presets: `dock` (364), `narrow` (420), `tiny` (320x240), `dialog`,
   `wide`, `full`. For arbitrary widths, drive the stage panel directly -- stage settings
   changes do NOT remount your panel, so state survives the sweep:
   ```lua
   local stage = TestHarness.Stage()
   stage.selfStyle.width = 500   -- then 380, 320, 900, 1400...
   ```
3. **Sweep the Font Size setting live** at each interesting width:
   ```lua
   dmhub.SetSettingValue("fontsize", 140)  -- also 80; restore 100 when done
   ```
   The engine re-lays-out every panel immediately. Screenshot at 364/80%, 364/140%,
   minWidth/140% (worst case), and wide/100%. Read the screenshots; look for clipped
   descenders, overrun boxes, orphaned right edges under scrollbars, and 300-char lines.
4. **Test the real window chrome** in a live game: open the panel from the icon rail, drag
   all four edges and corners, confirm the registration clamps land where the layout actually
   still works, and that `minHeight == maxHeight` locks are intentional.
5. **Restore** `fontsize` to 100 and offer to put the user back in their game.

`TestHarness.Probe()` returns live rendered sizes when you want assertions instead of
eyeballs (re-probe in a LATER execute_lua call -- same-call reads are stale).

## Checklist before calling a panel responsive

- [ ] No pixel width on anything that should track the host (chrome exceptions are deliberate)
- [ ] Every label: an auto axis, or wrap, or `minFontSize` -- nothing fully boxed
- [ ] Vertical overflow has a designated vscroll region with an `rpad = 12, borderBox` gutter
- [ ] Prose capped with `maxWidth`; chip/card rows `wrap = true`
- [ ] Registration carries honest `minWidth`/`maxWidth`/`minHeight`/`maxHeight`
- [ ] Padding always paired with `borderBox = true`
- [ ] No hardcoded 364, no char-count font math; `"available"` width only on builds with the 2026-08-09 engine change
- [ ] Verified in harness at dock width AND minWidth AND wide, each at 80%/100%/140% font
- [ ] Verified the floating window drag-resize live, all edges
- [ ] ASCII only, theme classes over ad-hoc styles (see dmhub-gui / theme-engine-discipline)

## Engine facts this skill asserts (for future re-verification)

- `fontsize` setting -> `GameConfig.fontMagnification`; applied per text control in
  `SheetLabel.cs` / `SheetInput.cs` / `SheetDropdown.cs` / `SheetTextEditor.cs`; setting
  change dirties all top-level sheet trees (`GameConfig.cs`).
- Auto label measurement uses the magnified size (`SheetLabel.CalculateAutoSizeText` caches
  on live `label.fontSize`).
- `minFontSize` floor and `maxFontSize` are both magnified (`SheetLabel.cs UpdateLabelStyle`;
  floor magnification fixed 2026-08-08, needs an engine build).
- `rendered(element, w, h)` fires from the end of `SheetPanel.UpdateStyle` on size change.
- `% available` is a weighted flex-grow on both axes: `SheetPanel.DistributeAvailable`
  runs in both flow branches of `LayoutChildrenInternal` (percent = grow weight, min/max
  clamped, remainders redistributed, 16-iteration cap); the cross axis and `flow = "none"`
  stretch via `SheetPanel.StretchAvailable`; flow-axis available in a wrap container falls
  back to auto with a warning (`FallbackAvailableToAuto`). Weight rides
  `Instance.availableWeightX/Y` (stylegen). Landed 2026-08-09, NEEDS ENGINE BUILD --
  before that build, width-available is dead code and height splits evenly.
- Dimension parser: `CharacterSheetWidget.cs DimensionCalculation` (forms table above).
- `em`/`sp` dimension units: parsed in `DimensionCalculation.Init`, resolved in
  `Calculate(baseValue, emBase, ...)` where `emBase = instance.fontSize x
  fontMagnification`, computed per style rule in the generated `Apply`
  (`tools/stylegen/Program.cs` dimension block). Applies to
  width/height/min*/max*/cornerRadius; NOT pads. Landed 2026-08-09; harness-verified same
  day (exact at 80/100/140, live re-resolve on setting change, em transitions lerp).
- Window/dock geometry: `DocumentSystem/DocumentSystem.lua` (`PresentPanel`,
  `WindowResizeOptions`, `ClampHeight`, 32px header, contentArea `100%-33`),
  `DMHub Core UI/DockablePanel.lua` (`DockWidth` 364, `fitChildren`, scroll wrapper),
  `DMHub Core UI/DialogResize.lua` (`gui.WindowResizePanel`).

If any of these drift after an engine change, fix this file rather than trusting it.
