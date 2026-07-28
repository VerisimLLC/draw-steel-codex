---
name: dmhub-gui
description: Build, modify, or debug Lua GUI in the Draw Steel Codex -- panels, labels, buttons, dialogs, dockable panels, layout, events, state, hover/press behavior, popups, scroll regions, animations. Use when the user asks to "build a UI", "make a panel/dialog", "add a button/dropdown/input", "fix this layout", "this widget isn't responding/recoloring/clicking", "why doesn't my style apply", or any other interaction with the `gui.*` framework. For applying theme tokens/classes correctly to themed UI, defer to theme-engine-discipline. For migrating an entire legacy file onto ThemeEngine, defer to theme-engine-retheme.
---

# DMHub GUI Authoring

## What this skill is

The user is working in `C:\dev\dmhub\draw-steel-codex\` -- Lua code that runs inside the closed-source DMHub engine (Unity / C#). This skill helps you build and debug UI in the `gui.*` framework (Lua-side) while staying aware that the actual rendering, layout, and event system are implemented in the engine's `Sheet*.cs` files.

Your job: write idiomatic, performant, theme-aware GUI Lua; explain why a widget is doing what it's doing; reach for the right documented pattern before inventing one; and when the docs don't cover something, **go read the engine source** rather than guessing.

## Read before authoring or debugging

These four documents in the codex root are authoritative. Open them when you need the answer they cover; don't reconstruct their content from memory.

| Doc | When to read |
|--|--|
| `UI_BEST_PRACTICES.md` | Anything about controls (`gui.Panel`, `gui.Label`, `gui.Input`, `gui.Check`, `gui.Slider`, `gui.Dropdown`, `gui.CollapseArrow`, `gui.ExpandoArrow`, `gui.ProgressBar`, etc.), layout/sizing expressions, the style system mechanics (cascade, selectors, inline-vs-style precedence), events (`FireEvent` / `FireEventTree`, `monitorGame`, `linger`, `think`/`thinkTime`), tooltips, transitions, scrollable lists. The first place to look for "how do I build X." |
| `ThemeEngine.md` | Whenever the work touches color, font, gradient, the active theme/scheme, or a class that lives in the default theme. Covers `GetStyles` / `MergeStyles` / `MergeTokens`, `OnThemeChanged`, `ResolveTokens`, `requireConfirm`, and the deprecated-controls migration table. |
| `DefaultStyles.md` | When you need to pick the right token (`@fg`, `@bgAlt`, `@danger`, ...) or the right class (`{sizeM}`, `{bordered}`, `{formStackedRow}`, `{featureCard}`, `{multiselectChipRemove}`, `{hoverable}`, ...). Catalog of every registered class with prescriptive "reach for this when..." notes. Check this before writing a `selfStyle` block or adding a new style rule. |
| `THEME_PERF_NOTES.md` | When the user reports slowness in a themed panel (class editor and other heavy compendium screens are the known hot spot). Has the diagnosis sequence and the trim/split remediation options. Don't act on it without re-reading first; it's a bookmark, not a finished plan. |

There is a related authoring guide at `GoblinScript_Guide.md` (formula expression language) and an overall codex map at `CLAUDE.md`. Skim them only if the user's request crosses into formulas or general modding.

## Sibling skills -- defer to them when they fit

- **`theme-engine-discipline`** owns the rulebook for applying theme tokens and classes correctly (which selector, inline-vs-class, `@token` rules, popup cascade with `popupsInheritStyles`, deprecated-control migration, anti-patterns). If the user's request is "style this themed widget correctly" or "convert these inline colors to theme tokens," let that skill drive.
- **`theme-engine-retheme`** owns whole-file migrations from legacy/ad-hoc styling onto full `ThemeEngine.GetStyles()` compliance. If the user asks to "re-theme this file" / "migrate X to ThemeEngine," defer.
- **`codexmod`** is the broad DMHub modding skill (chat commands, GoblinScript, extension points, data persistence). Pair with this skill when the UI work also involves registering panels, settings, or event handlers.
- **`ui-harness`** owns actually *running* the UI: launching the app into an isolated harness, mounting a panel over MCP with no file edit, screenshotting it, iterating. Reach for it whenever the work would benefit from seeing the result -- and before you consider telling the user you cannot verify something visually.

This skill is for the GUI-authoring half: hierarchy, layout, controls, events, lifecycle, and the day-to-day "why isn't this panel doing what I want."

## The engine source is fair game -- delegate to research it

The Lua `gui.*` API is a thin wrapper over Unity C# in `C:\dev\dmhub\Assets\Scripts\Sheet*.cs`. When the docs don't cover something -- a property whose behavior isn't obvious, a recently-added option not yet documented, a layout edge case, an event you didn't know existed -- the C# source is the ground truth.

Key engine files (read-only for this skill):

| File | What lives there |
|--|--|
| `Assets/Scripts/SheetPanel.cs` (~9.9k lines) | `LuaSheetPanel` -- every property and method `gui.Panel` exposes to Lua (with `[Documentation]` attributes). Also the layout engine, event dispatch, popup/floating handling, scrollable view wiring, `monitorGame` integration. The biggest single source of truth for panel behavior. |
| `Assets/Scripts/SheetLabel.cs` (~840 lines) | `LuaSheetLabel : LuaSheetPanel` -- adds `text`, `editable`, `numeric`, `placeholderText`, `markdown`, alignment, font handling. Inherits everything from `LuaSheetPanel`. |
| `Assets/Scripts/SheetStyle.cs` | Style cascade, selector matching, `priority`, per-state rules, transitions. The "why doesn't my selector match" answer. |
| `Assets/Scripts/SheetTheme.cs` | Theme/scheme plumbing on the C# side; how `@tokens` resolve. |
| `Assets/Scripts/SheetButton.cs` / `SheetCheckbox.cs` / `SheetDropdown.cs` / `SheetInput.cs` / `SheetIcon.cs` / `SheetScrollView.cs` | One per widget kind. Read when working with that specific control. |
| `Assets/Scripts/SheetController.cs` / `SheetHud.cs` / `SheetRaycaster.cs` | Top-of-tree wiring: how the UI binds to the HUD, raycast/click order, mod-load lifecycle. |
| `draw-steel-codex/Definitions/gui-definitions.lua`, `gui.lua` | LuaLS stub signatures for the same API. Documentation-only; the C# files are authoritative when the stubs lag behind. |

**Strongly prefer delegating engine spelunking to a subagent.** These files are large (`SheetPanel.cs` is ~10k lines) and you don't want their contents in your main context. Use the `Explore` agent for targeted lookups ("find the implementation of `vscroll`," "what does `borderBox` do in layout," "where is `popupsInheritStyles` handled," "what properties are tagged with `[Documentation]` on `LuaSheetLabel`"). Use a `general-purpose` agent when the answer needs synthesis across multiple files. Brief the agent like a colleague who hasn't seen this conversation: give the file paths, the question, and ask for a short report under 200 words.

Example dispatch:

```
Agent({
  description: "Look up gui.Panel scroll behavior",
  subagent_type: "Explore",
  prompt: "In C:/dev/dmhub/Assets/Scripts/SheetPanel.cs, find every property and method
related to scrolling -- vscroll, hscroll, scrollPosition, scrollTo, scrollHandle styling,
mouse-wheel handling. List each one with its [Documentation] string and any behavior
notes from the implementation. The user is debugging a scroll region that auto-scrolls
to bottom when they don't want it to. Under 200 words."
})
```

When the engine source confirms a behavior the docs don't mention, propose adding a one-liner to the relevant `.md` file -- but ask the user before editing the docs.

## Project-specific rules (the things that bite)

These are the gotchas that the docs cover but that show up repeatedly. Internalize them.

1. **ASCII only in Lua source files.** No em dashes, curly quotes, ellipses, or any other non-ASCII byte. Use `-` / `:` / `"` / `...`. This is a hard runtime constraint, not a style preference.
2. **Forward-declare self-referencing locals.** `local x = gui.Panel{ click = function() x:... end }` will fail -- `x` isn't in scope inside the initializer. Split it: `local x; x = gui.Panel{...}`.
3. **`borderBox = true` whenever a panel uses padding.** Without it, `hpad`/`vpad` add to the declared width/height (content-box behavior) and you get overflow. Border-box matches CSS and is what people expect.
4. **Panels must be parented by end-of-frame.** No speculative `gui.Panel{...}` that you might not use. Guard with a conditional or use `nil` entries in a `children` array.
5. **Orphaned panels are destroyed.** Reassigning `element.children = {...}` destroys anything not in the new list. To "swap views," keep both children in the tree and toggle `collapsed`.
6. **Never read state from closure upvalues across event handlers** -- store it in `element.data`, then read it back on the event. Closures get stale.
7. **`floating = true` (and `x`/`y` partners) must be inline.** The cascade ignores them. Same for `rotate` -- it doesn't animate via style cascade in DMHub (`gui.ExpandoArrow` packages the working pattern).
8. **Inline properties always beat styles.** A `bgcolor` set inline can never be overridden by a `:hover` rule. If you want state to flip a property, leave its rest value in styles too.
9. **`@tokens` only resolve inside ThemeEngine-routed rule tables.** `gui.Panel{ bgcolor = "@bg" }` ships the literal string and renders wrong. Use a class, or route a `MergeStyles` block. (For text markup, use `ThemeEngine.ResolveTokens(str)`.)
10. **Popups re-root the cascade.** Set `element.popupsInheritStyles = true` on the parent **before** assigning `element.popup = gui.Panel{...}`, so the popup inherits the host's theme cascade. Only use an explicit `styles = ThemeEngine.GetStyles()` on the popup root if the popup is a self-contained modal with independent lifetime.
11. **Token property mutations go through `token:ModifyProperties{ execute = function() ... end }`.** Outside the character sheet/builder. Direct property assignment doesn't network or undo. (See `CLAUDE.md` for the full pattern.)
12. **Never recreate panels on every refresh.** Use `monitorGame` + a custom event into the existing tree (`existingPanel:FireEventTree("updateData", data)`) instead of rebuilding `element.children = { CreateThing() }` each tick. Recreation is expensive and destroys event subscriptions.
13. **Always check `element.valid` before touching a panel from a deferred callback.** Panels destroy asynchronously.
14. **Reach for `gui.Button` with theme classes** -- not the deprecated `PrettyButton` / `IconButton` / `CloseButton` / etc. See `ThemeEngine.md` for the full migration table.
15. **Don't create new Lua files.** New files won't auto-load -- they must be registered through the DMHub module system. Add code to an existing file in the right module, or ask the user to register a new file. (This is in `CLAUDE.md`.)

## Decision flow when building or modifying GUI

1. **What's the goal?** A new panel? Adding a control to an existing panel? Fixing a behavior? Restate it in one sentence before touching code.
2. **Is there an existing widget that does this?** Check `UI_BEST_PRACTICES.md` controls reference. `gui.ExpandoArrow` exists; don't roll a custom triangle. `gui.MCDMDivider` exists; don't draw a thin panel. `gui.Multiselect` exists; don't reimplement chips.
3. **Does the cascade root already exist?** If you're inside a `DockablePanel` (or any host that called `styles = ThemeEngine.GetStyles()`), theme classes will resolve automatically -- don't add a second root. If you're authoring a standalone dialog, the root needs `styles = ThemeEngine.GetStyles()` plus an `OnThemeChanged` subscription guarded with `panel.valid`. See `theme-engine-retheme` Step 0 for the classification rules.
4. **Is there a class for the visual you need?** Check `DefaultStyles.md`. Classes like `{bordered}`, `{hoverable}`, `{sizeM}`, `{bgDanger}`, `{formStackedRow}`, `{featureCard}` already exist for almost every common need. A `selfStyle` block is a last resort -- ask the user first.
5. **What's the smallest thing I can change?** Don't refactor surrounding code. Don't add abstractions. A bug fix is a bug fix.
6. **Did I introduce any of the project-specific gotchas above?** Walk the checklist.

## When the docs don't have your answer

This is when the "be flexible and learn as you go" posture matters. Three options, in order:

1. **Read the relevant `Sheet*.cs` engine file via an `Explore` agent.** Quick targeted lookups for "is property X supported," "what's the order of these events," "how does this layout edge case actually resolve." Don't read 10k-line files into your own context.
2. **Read `Definitions/gui-definitions.lua` and `Definitions/gui.lua`.** The LuaLS stubs cover most of the API surface and are short. Good for "what's the signature of X."
3. **Ask the user.** If the engine source confirms behavior that contradicts the user's mental model, or if there's a design decision you can't make without input ("should this hover-tint or stay quiet"), surface it instead of guessing.

When you learn something the docs don't cover, propose a one-line addition to the relevant `.md` -- but only edit the docs with the user's go-ahead.

## Workflow checklist before claiming a GUI change is done

- The change compiles. Check it yourself without disturbing the app: `execute_lua('local f,e = loadfile("<abs path to the .lua>") print(f and "OK" or e)')` compiles without executing.
- ASCII only.
- No inline `@token` references.
- No `gui.PrettyButton` or other deprecated control left in code I touched.
- No `selfStyle` block whose effect could be a class instead.
- No new files created without the user's go-ahead.
- `borderBox = true` is set on any new panel that uses padding.
- Theme switch test: if I touched themed UI, switching the color scheme (devmode Theme Test panel) tracks the change.
- For anything visual, I actually looked at it -- see the `ui-harness` skill, which lets me mount and screenshot a panel myself. "I can't verify this without running it" is now only true for UI that needs a live game (map, tokens, GameHud); for everything else, run it. If I genuinely couldn't run it, I said so explicitly rather than claiming it "should work."

## Reporting back

Tell the user what changed in one or two sentences. If there's something I couldn't verify (live behavior, theme tracking, performance), say so explicitly. If I delegated a research question to an agent, summarize what I learned in one sentence -- don't dump the agent's full report.
