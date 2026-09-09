---
name: rail-button
description: |
  Author, edit, restyle, or debug a custom icon-rail script button in a live DMHub
  instance over the MCP bridge -- the user-programmable buttons created in-app via
  Panel Library > "New button" (or on a toolkit strip). Their Lua code and definitions
  live in per-game SETTINGS (iconrailscriptbuttons / iconrailtoolkits), NOT in codex
  source files -- never create a codex .lua file for one. Use whenever the user asks to
  "make me a button", "code a custom button", "add a rail/toolkit/macro button",
  "change what my button does", "edit my button's code", style a button face
  (@slots, @bgcolor, @label, @tooltip, @disabled directives), or wire a quick personal
  automation like "a button that rolls dice / posts to chat / spends a recovery /
  toggles a setting". Trigger on "/rail-button", "script button", "custom button",
  "rail button", "toolkit button".
metadata:
  author: draw-steel-codex
  version: "1.0.0"
---

# Custom Rail Script Buttons (/rail-button)

You author **script buttons** for the DMHub icon rail: small user-programmable buttons
whose click runs a Lua chunk with full engine access. You drive a **live, running**
DMHub over the MCP bridge (`mcp__dmhub__*`), reading and writing the settings that hold
button definitions. The implementation you are scripting against is
`DocumentSystem/DocumentSystem.lua` (search for `RunToolkitScriptButton`,
`ScriptButtonStyle`, `SCRIPT_BUTTON_TEMPLATE`, `RailScriptButtonDialog`).

**The one fact that shapes everything: button code is DATA, not source.** A button's
Lua lives inside a per-game preference setting. Editing repo files does nothing to a
button; deploying does nothing; there is no file to register. You edit buttons by
rewriting the setting value over `execute_lua`.

## Where buttons live

Two homes, both `pergamepreference` settings (per user, per game -- a button made in
one game does not exist in another):

1. **Standalone rail buttons** -- setting `iconrailscriptbuttons`:
   ```lua
   { [guid] = { type = "script", name = "...", icon = "phosphor/lightning.png",
                script = "...lua...", description = "...",   -- description optional
                mode = "script"|"command", command = "...",  -- see mode trap below
                pack = "...", packid = "..." } }             -- only on shared/community buttons
   ```
   The button appears on a rail via an entry in the `iconraillayout` setting keyed
   `"button:" .. guid` (keys are lowercase) with value `{ side = "left"|"right", slot = N }`.
   Slots are 0-based from the top; holes render as gaps; the drop clamp is slot 16.

2. **Toolkit strip items** -- setting `iconrailtoolkits`:
   `{ [guid] = { name, icon, items = { <same item shape as above> }, x, y } }`.
   Items are an array; edit `rec.items[idx]` in place.

## The execution contract

- Click runs `load(script)` as a **plain chunk, standard global environment, full
  engine API** -- same trust posture as mod code. `chat`, `dmhub`, `game`, `gui`,
  `import`, GoblinScript helpers: all available. There is no `mod` local; do not call
  `dmhub.GetModLoading()` in a button.
- While the chunk runs, the clicked button's panel is published as the
  `scriptButtonElement` global (read it with `rawget(_G, "scriptButtonElement")` and
  check `.valid`; nil on non-click paths). Use it to anchor UI to the button itself:
  `anchor.popupPositioning = "panel"; anchor.popup = gui.Panel{...}` gives a panel
  that pops out from the button and dismisses on click-away/Escape.
- **The definition is re-read from the setting at every click.** A script-body edit
  you write via MCP is live on the very next click -- no rebuild, no reload.
- Failures are **loud by design**: the button flashes red and the error opens in a
  modal. Never wrap the whole body in pcall to hide errors.
- Buttons from community packs run under a kill switch + instruction watchdog; the
  user's own buttons do not. When editing an existing def, **mutate it in place and
  preserve `pack`/`packid`** -- dropping them breaks pack updates/sharing.

### The mode trap

`mode = "command"` buttons run a recorded command pipe (`dmhub.Execute`) and **skip
the Lua script entirely** (unless `command` is empty, which falls through). A missing
`mode` means legacy script. The in-app dialog defaults NEW buttons to command mode --
so when you author code, always set `mode = "script"` explicitly, and when converting
a command button to code, flip its mode (keep `command` around unless asked to drop it).

## Style directives

Comment lines at the **start of a line** inside the script, parsed by string-match
(never executed, so they are safe on downloaded buttons). Use the `-- @x` form -- a
bare `@x` line also works at runtime (it is commented out before parsing, like the
engine's `@if` preprocessor) but makes `luac -p` and editors complain.

```
-- @slots N               rail slots the button spans, 1-4 (like a character card)
-- @bgcolor #rrggbb[aa]   face background color
-- @bggradient #c1 #c2    top-to-bottom face gradient
-- @opacity 0.05..1       face opacity
-- @label <goblinscript>  live value shown INSTEAD of the icon, evaluated on the
--                        player's current character (GoblinScript, never Lua)
-- @clickanim pop|none    hover-swell/click-squash animation; "pop" is the default
-- @tooltip <text|gs>     hover text replacing the name; plain prose shows as
--                        written, a GoblinScript formula evaluates live, e.g.:
-- @tooltip "AT FULL STAMINA" when Stamina = Maximum Stamina else "USE RECOVERY"
-- @disabled <gs>         grey + inert while the condition is true on the current
--                        character; an unevaluable formula = enabled (errors never
--                        lock a button out)
```

Semantics worth knowing:
- With **no character selected**, a button whose @label/@tooltip/@disabled actually
  reads character state is disabled and its tooltip says "No character selected".
  Prose-only directives keep the button live -- and so do formulas built only from
  GLOBAL symbols (Hero Tokens, Malice; `creature.RegisterSymbol{global = true}`),
  which evaluate against a blank-character context and show the true game-wide value.
- @tooltip prose containing an operator character (`-`, `+`, `/`) can parse as a real
  formula and render a number instead of the text. Quote it as a GoblinScript string
  (`-- @tooltip "SOME TEXT"`) for reliable prose.
- Indented directive-looking lines are inert (anchoring is start-of-line) -- that is
  how the template shows examples without activating them.
- @label/@tooltip/@disabled refresh **live** on the rail's refresh cadence. The
  face-shaping directives (@slots/@bgcolor/@bggradient/@opacity/@clickanim) and the
  def's `name`/`icon` are **baked at rail build time** and need a rail rebuild (below).

## Operating loop

1. `mcp__dmhub__check_connection` first. No app = nothing to edit; say so.
2. **Find the target**: dump `dmhub.GetSettingValue("iconrailscriptbuttons")` (and
   `iconrailtoolkits` if nothing matches) and match on `name`. Print id, name, mode,
   and the current script so you know what you are replacing.
3. **Author the script** (constraints below), then write it back.
4. **Refresh** if the face changed; **verify** (both below).

If the user has the button's edit dialog open with a watched code file, do not race
it -- every save of their file overwrites `def.script`. Ask them to close it first.

### Create a new standalone button

```lua
local id = string.lower(dmhub.GenerateGuid())
local defs = dmhub.GetSettingValue("iconrailscriptbuttons") or {}
defs[id] = { type = "script", mode = "script", name = "Lucky Roll",
             icon = "phosphor/lightning.png", script = [==[ ...code... ]==] }
dmhub.SetSettingValue("iconrailscriptbuttons", defs)
-- put it on the rail: append below the side's lowest occupied slot
local layout = dmhub.GetSettingValue("iconraillayout") or {}
local maxSlot = -1
for _, e in pairs(layout) do
    if type(e) == "table" and e.side == "left" and type(e.slot) == "number" and e.slot > maxSlot then
        maxSlot = e.slot
    end
end
layout["button:" .. id] = { side = "left", slot = maxSlot + 1 }
dmhub.SetSettingValue("iconraillayout", layout)
```

Icons are engine image paths; the in-app picker offers the phosphor set
(`"phosphor/<name>.png"`, e.g. `dice-five.png`, `heart.png`, `sword.png`). Default
to `phosphor/lightning.png` unless something obviously fits better.

### Edit an existing button's code

```lua
local defs = dmhub.GetSettingValue("iconrailscriptbuttons") or {}
local def = defs[targetId]
def.script = [==[ ...new code... ]==]
def.mode = "script"
dmhub.SetSettingValue("iconrailscriptbuttons", defs)
```

Toolkit items: same, but load `iconrailtoolkits`, edit `rec.items[idx]`, write the
whole table back.

### Delete

Remove `defs[id]`, write the setting, and remove the `"button:" .. id` key from
`iconraillayout`. Then rebuild.

### Rebuilding the rail

`RebuildIconRails` is file-local, but `EnsureIconRail()` and `RailModeActive()` are
globals, and the off/on path is the designed rebuild:

```lua
dmhub.SetSettingValue("iconrail", false); EnsureIconRail()
dmhub.SetSettingValue("iconrail", true);  EnsureIconRail()
```

This is only needed for **face/layout** changes (new button, name, icon, @slots,
@bgcolor, deletion). Script-body-only edits are live at next click without it. If the
rail misbehaves after the toggle, `mcp__dmhub__reload_lua` is the blunt reliable reset.

## Writing the script itself

- **ASCII only** (engine runtime constraint), Lua 5.4.
- Prefer the `-- @directive` comment form so the body is valid vanilla Lua.
- Wrap the script in `[==[ ]==]` when embedding it in an `execute_lua` call -- plain
  `[[ ]]` breaks the moment the body contains `[[` or `]]`.
- Token mutations outside the character sheet must use `token:ModifyProperties{
  description = "...", execute = function() ... end }` -- the repo-wide rule applies
  to button code too.
- No state persists between clicks except what you store somewhere real (a setting,
  a shared document). Do not leak globals as scratch state.
- Buttons run on the clicker's machine only. Anything that must reach other players
  needs a networked path (chat, shared docs, `dmhub.Execute("broadcast ...")`).
- The codebase gotchas apply: `cond()` does not short-circuit; missing fields on
  game-typed objects raise (guard with `try_get`/`pcall`); forward-declare locals
  referenced by their own initializer's closures.

Validate before writing back: syntax-check with the bundled interpreter
(`dependencies/lua/bin/luac.exe -p` on a scratch file), or in-app with
`print(select(2, load(script)))` -- nil output = clean.

## Verifying

- **Behavior**: run the body directly via `execute_lua` -- that is exactly what a
  click does (minus the @disabled gate). With the `--` directive form the script is
  runnable verbatim.
- **Directives**: evaluate a formula the way the rail does:
  `ExecuteGoblinScript(formula, dmhub.currentToken.properties:LookupSymbol{}, nil, "test")`.
- **Face**: rebuild, then `mcp__dmhub__screenshot` (rails sit at the screen's left
  and right edges) and confirm icon/label/color/span visually.
- A real click through the UI also exercises the error modal and click-pop; use
  `ui_find`/`ui_click` if end-to-end proof is wanted.

## The in-app path (what the user does by hand)

Know this so you can talk the user through it and stay out of its way:
Panel Library (the + at a rail's foot) > "New button" opens the button dialog
(name, icon, description, Action dropdown). In script mode, **"Edit code..."** calls
`dmhub.OpenTextFileInConnectedEditor`: an engine-owned temp file opens in their
default text editor, seeded from the template, and **every save applies instantly to
an existing button** (a new button still needs Create). Command mode instead records
lightning-bolt steps via the Command Builder. Right-click a button on the rail to
edit or remove it; "Share Your Buttons" publishes to community packs. The connected
editor needs a native user action, so you cannot open it over MCP -- settings writes
are your equivalent, with the same instant-apply behavior.

## Example: a complete button

```lua
-- @bgcolor #223a22
-- @label Recoveries Available To Spend
-- @tooltip "AT FULL STAMINA" when Stamina = Maximum Stamina else "SPEND RECOVERY"
-- @disabled Recoveries Available To Spend < 1
local token = dmhub.currentToken
if token == nil or token.properties == nil then
    gui.ModalMessage{ title = "No character", message = "Select a character first." }
    return
end
token:ModifyProperties{
    description = "Spend a recovery",
    execute = function()
        token.properties:SpendRecovery()
    end,
}
chat.Send(token.name .. " spends a recovery.")
```

Smaller sparks: `dmhub.Roll{ roll = "2d6", description = "Luck" }` rolls dice on
screen; `dmhub.Execute("toggle showgrid")` runs any chat/command-pipe command;
`chat.Send("...")` posts to chat.
