# Draw Steel Editor Styling Guide

Reference for any Draw Steel editor UI work — the Ability Editor, the forthcoming Feature Panel + Modifier Picker, the Triggered Ability editor rewrite, and the wider compendium restyling.

This doc is the accumulated practical knowledge from building the sectioned Ability Editor. Read it before touching any editor surface. Repo-level UI patterns live in [UI_BEST_PRACTICES.md](UI_BEST_PRACTICES.md); this doc is DS-editor-specific.

---

## Palette

Eight colors, used consistently across every DS editor. The canonical source is `AbilityEditor.COLORS` in `Draw Steel Ability Editor/AbilityEditor.lua`.

| Token | Hex | Role |
|---|---|---|
| `BG` | `#080B09` | Outer dialog background |
| `PANEL_BG` | `#10110F` | Control backgrounds (dropdown, input, button) |
| `GOLD` | `#966D4B` | Borders, dividers (neutral state) |
| `GOLD_BRIGHT` | `#F1D3A5` | Section headings, title, check-mark |
| `GOLD_DIM` | `#E9B86F` | Hover states, nav selected bg |
| `CREAM` | `#BC9B7B` | Neutral body text |
| `CREAM_BRIGHT` | `#DFCFC0` | Emphasis text, control text |
| `GRAY` | `#666663` | Placeholder, disabled |

When a future editor needs a variant (e.g. an alt color for a specific panel type), pass a custom table to `AbilityEditor.GetSharedWidgetStyles(colors)` — the helper is palette-parameterized.

## Shared widget styles (exported)

Call site:

```lua
local styles = AbilityEditor.GetSharedWidgetStyles()  -- returns a fresh table
-- or
local styles = AbilityEditor.GetSharedWidgetStyles(myCustomColors)
```

Drop into the root panel's `styles = { ... }` list. Returns priority-3+ overrides covering:

- `Styles.Form` base + left-anchoring overrides for `formPanel`/`formLabel`/`formDropdown`/`formInput`/`formValue`
- `dropdown` + hover + open + `dropdownLabel`/`dropdownTriangle` on hover + `dropdown-list` + `dropdown-item` + hover
- `input` + hover + focus
- `button` + hover + press + disabled
- `checkbox` + `checkbox-label` + `check-background` + `check-mark`
- `delete-item-button` + hover (priority 11 to beat engine defaults)
- `sliderLabel`

Editor-specific styles (`nae-*` classes, section headings, nav rows, pills, etc.) are NOT in the shared pack — those live inline in `_editorStyles()` in the Ability Editor. The shared pack is for generic widgets only.

## Form row pattern

The **stacked label above, control below** layout is the DS form standard. Every editor row should follow it.

- Row: `flow = "vertical"`, `width = "100%"`, `halign = "left"`, `valign = "top"`, `vmargin = 8`
- Label: 14pt, `bold = true`, color `CREAM_BRIGHT`, `bmargin = 4`
- Control: full-width themed input/dropdown/textarea/checkbox (the shared widget styles already theme these)
- Inline variant (label + small control on one row) reserved for compact fields like 3-digit numbers

`AbilityEditor.GetSharedFormStyles()` carries the `ds-field-row` / `ds-field-label` / `ds-field-row-inline` / `ds-field-label-inline` rules for editors that build their form chrome from scratch.

### `formPanel` (legacy / modifier sub-editors)

Modifier `createEditor` functions emit rows tagged `classes = {"formPanel"}` (with `formLabel`/`formInput` children). The themed style pack `AbilityEditor.GetThemedDialogStyles()` gives these the DS treatment automatically:

- **Default (stacked):** a bare `formPanel` lays out as vertical flow, 100% width, with the `formLabel` stretched above its control. This matches the outer feature panel's Name / Source / Description rows.
- **Opt-in inline:** add `"formPanel-inline"` to the classes list when the row hosts 2+ side-by-side widgets (Replace + New-Text inputs, Label + delete button, dropdown + dropdown, etc.). The `parent:formPanel-inline` selector restores the legacy horizontal flow + 140px label column for descendants, so children don't need their own inline class.

```lua
-- Stacked (default): Label above, input below.
gui.Panel{
    classes = {"formPanel"},
    gui.Label{ classes = {"formLabel"}, text = "Name:" },
    gui.Input{ classes = {"formInput"}, text = entry.name, ... },
}

-- Inline: Label + multiple widgets on one row (delete + dropdown + input, etc.).
gui.Panel{
    classes = {"formPanel", "formPanel-inline"},
    gui.Label{ classes = {"formLabel"}, text = info.text },
    gui.DeleteItemButton{ ... },
}
```

When in doubt, default to stacked -- it is the lead-dev-blessed standard. Only add `formPanel-inline` when horizontal layout is intentional.

**Gotcha -- conditionally-hidden children need `formPanel-inline`.** If a row's children use `SetClass('hidden', ...)` or `hidden = cond(...)` to hide/show widgets dynamically (rather than the whole row), that row must be inline. `hidden` suppresses rendering but keeps the layout slot -- in a vertical flow the hidden child reserves a blank row of dead space. Horizontal flow absorbs the width cleanly. `CharacterModifier:UsageLimitEditor()` is the canonical example: its "Uses:" label + GoblinScriptInput + "ID:" label + Input hide when refresh type is "none", and the row was horizontal by design.

Classic mode (`classicAbilityEditor = true`) keeps the old `Styles.Form` pack and is unaffected by either default.

## Conditional disclosure

Fields that appear/disappear based on a parent toggle (e.g. Persistence sub-cluster) should use the `collapsed-anim` engine class for smooth expand/collapse, not rebuild on toggle.

```lua
classes = { "your-row-class", cond(isEnabled(), nil, "collapsed-anim") },
refreshAbility = function(element)
    element:SetClass("collapsed-anim", not isEnabled())
end,
```

---

## Gotchas

Things that bit during the Ability Editor build. Read before the same wall of pain bites again.

### Styling cascades

- **Priority 3 beats engine defaults.** Priority 4 needed for dropdown hover overrides — the engine sets `dropdownLabel parent:hover color=black` and `dropdownTriangle parent:hover bgcolor=black` at `DMHub Titlescreen/Styles.lua:295`.
- **Don't put `width = "100%"` on the base `dropdown` selector** — it overrides `formDropdown`'s 240px inside SourceReference.
- **Class-toggled `width` on a panel doesn't always take.** Use direct `panel.width = N` assignment for column sizing (preview/detail columns do this).
- **`scale` IS restylable** via class-based rules (used for chevron flips in collapsible sections).
- **`delete-item-button` uses priority-10 internal styles** (`bgcolor=white` normal, `bgcolor=red` hover) — beat at priority 11.
- **Textarea `textAlignment`** needs priority 3 so `"topleft"` beats the base `input` style's `"left"`.

### Styles.Form integration

- **Include `Styles.Form` first** in the root panel's `styles = { ... }`. Required for SourceReference widgets (they use `formPanel`/`formLabel`/`formDropdown`/`formInput` classes internally).
- **Left-aligning Styles.Form descendants** requires `formPanel width="auto" halign="left"` + `formLabel minWidth=0` at priority 5. The base pack right-aligns them and overriding halign alone is not enough.
- **SourceReference:Editor emits its own "Source:" label.** Don't wrap it in another label row or you get a duplicate.

### Panel layout

- **`collapsed = 1` zeros the layout slot.** `hidden = 1` only suppresses rendering and keeps the slot.
- **`collapsed` is an engine-reserved class name.** `SetClassTree("collapsed", true)` nukes the entire subtree. Use private class names (`nae-narrow`, `nae-collapsed`, etc.) for state toggles.
- **Always `borderBox = true`** with any `hpad`/`vpad`/`pad` — padding is otherwise added on top of the declared width.
- **Do NOT rebuild panels on data change.** Use `SetClass` + `refresh*` events (`refreshAbility`, `refreshKeywords`, etc.). Dynamic children rebuilds should be change-guarded with a key derived from list-identity (see the behavior list key pattern in `AbilityEditor.lua`).
- **Lazy section construction:** for big sectioned editors, construct only the active section's content on first activation. Building all sections upfront is the biggest source of open lag.

### Lua language

- **Forward-declared locals must be initialized to `nil`.** DMHub's Lua env errors on reads of uninitialized locals — `local x; if x ~= nil` throws "Attempt to read uninitialized variable". Always write `local x = nil`.
- **Forward-declare self-referencing locals** for closures. `local p = gui.Panel{ click = function() p:SetClass(...) end }` is a bug — `p` is not in scope inside the initializer. Split into `local p` then `p = gui.Panel{...}`.
- **`_tmp_` prefix** on a game-type field marks it as transient — the engine skips it during serialization. Reading a never-set `_tmp_` field errors; use `obj:try_get("_tmp_foo")` for safe access.
- **`rawget(_G, "SomeGlobal")`** for cross-module global reads when the other module might not have loaded yet (handles nil safely).

### DMHub API quirks

- **`SetFocus` does not exist.** To focus an input, set `element.hasFocus = true` (property assignment, not a method call).
- **`floating = true` must be inline** on the panel constructor, not in a `gui.Style{}` rule. Placing it in a style produces "Unknown style property" at runtime.
- **`gui.panel.data` cleared on destroy.** After a dialog destroys, its panel objects still have Lua refs but their `data` bag is nil — deferred callbacks (debounced timers) that fire after destruction must `pcall` their `data` reads.
- **`class.levels` is string-keyed** (`"level-1"`, `"tutoriallevel-3"`), not sequential. Use `pairs()`, never `ipairs()`. `#class.levels` returns 0.
- **Subclass parent link** is `primaryClassId`, not `parentClass` (which is always empty).
- **Inputs bake initial values at creation time.** After programmatically replacing a model object (e.g. template-apply), firing `refreshAbility` is not enough — rebuild the editor panel in its parent.

### Refresh event scoping

When a field edit should trigger a repaint, scope the refresh event to just the subtree that cares, not the whole editor:

1. `refreshAbility` — tree-wide on the editor root. Use sparingly; many panels listen.
2. Section-scoped events — fired on the owning section's content panel. Keeps handlers local.
3. Direct-firing on a specific slot — e.g. `previewSlot:FireEvent("refreshPreview")` for the preview column. No tree walk at all.

Debounce expensive rebuilds (preview cards, tooltip walks) with a short timer — 150ms coalesces rapid keystrokes to a single rebuild.

### Module lifecycle

- **Hot-reload-safe init:** `AbilityEditor = rawget(_G, "AbilityEditor") or {}` preserves the module table across reloads.
- **Guard against stale closures** using `mod.unloaded`:
  ```lua
  dmhub.Schedule(delay, function()
      if mod.unloaded then return end
      -- ...
  end)
  ```
- **Do NOT use `RegisterGameType` for a module namespace table** — it enforces strict field access and breaks the `rawget` pattern.

---

## MCP bridge (for testing)

The DMHub MCP bridge lets Claude (or any tool) execute Lua inside the running app, reload modules, capture screenshots, and read console logs.

### Starting the bridge

In DMHub chat:
- `/mcp` — start bridge for the current session
- `/mcpauto` — start and persist across sessions

Health check: `curl -s http://localhost:19876/health`

### Tools

Prefix `mcp__dmhub__`:

- `check_connection` — is DMHub running + bridge reachable?
- `execute_lua` — run arbitrary Lua in the global env; prints + return values are captured
- `reload_lua` — equivalent to F4 (hot-reload all mods)
- `get_console_log` — recent Unity console entries; supports `level` filter (`all`/`warning`/`error`), `pattern` substring, `last` N entries
- `screenshot` / `screenshot_region` / `screenshot_panel` — visual verification
- `inspect_ui` — panel hierarchy inspection at a coordinate
- `restart_dmhub` / `start_dmhub` / `stop_dmhub` — process control

### HTTP fallback

If the MCP tools aren't available but the bridge is up:

```bash
curl -s http://localhost:19876/health
curl -s -X POST -H "Content-Length: 0" http://localhost:19876/reload
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"code": "print(\"hello\")"}' http://localhost:19876/execute
curl -s -o /tmp/dmhub.png http://localhost:19876/screenshot
```

Endpoints: `/health` (GET), `/execute` (POST JSON `{code: "..."}`), `/reload` (POST empty), `/screenshot` (GET PNG), `/status` (GET).

### Verification workflow

After every Lua edit:

1. `reload_lua` — no manual F4 needed
2. `get_console_log` with `level = "error"` — catch load-time failures
3. For visual changes, `screenshot_region` with `world`/`left`/`right` then `Read` the PNG

Test-induced errors (from ad-hoc helpers forcing state) are usually distinguishable from production bugs by the `[string "code"]` source tag versus module names like `[string "Draw Steel Ability Editor : AbilityEditor"]`.
