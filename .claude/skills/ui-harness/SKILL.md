---
name: ui-harness
description: Run, see, and iterate on DMHub UI yourself in an isolated harness -- launch the app into a controlled stage, mount a panel over MCP without editing a file, screenshot it, adjust, repeat. Use whenever GUI work would benefit from actually looking at the result: "iterate on this panel", "try a few layouts", "does this look right", "test this widget", "show me what X looks like", "isolate the character sheet / journal editor / action bar so we can work on it", or any time you are about to tell the user "I can't verify this without running it." Pairs with dmhub-gui (which owns how to WRITE the Lua); this skill owns the run-and-look loop.
---

# Iterating on UI in the test harness

## What this changes about how you work

DMHub UI used to be unverifiable from your side: you wrote Lua, the user reloaded, the
user told you what they saw. **That is no longer true.** You can launch the app into an
isolated harness, mount a panel, screenshot it, change it, and look again -- in seconds,
without entering a game and without touching real game data.

So: when GUI work would benefit from seeing the result, run it. Do not hand back UI you
have never looked at and hedge about it.

## Before you take over the app

Driving the harness means restarting DMHub out from under the user. **Check first:**

```
check_connection()
```

- `In game: <name>` -- the user may be mid-session with players. **Ask before restarting.**
- `At title screen` / not in a game -- go ahead.

Note the game name before you stop it, so you can offer to put them back afterwards.

## Launching

```
stop_dmhub()
start_dmhub(extra_args="--harness scratch")
```

**Do NOT use `restart_dmhub` for this.** It relaunches with `--gameid`, so the app boots
into a game, the harness boot hook never finds the titlescreen root, and it retries
forever. Stop-then-start with no `game_id` is the only correct sequence.

Boot takes ~30s. Poll `check_connection()` until it reports ready (it walks through
`CodeModsLoaded`, `GameDetailsSynced`, ...). `TestHarness` is not defined until code mods
have loaded -- an "Attempt to read uninitialized variable TestHarness" error just means
you were early.

Registered harnesses: `scratch` (the general workbench -- start here), `editor`
(gui.TextEditor playground), `seamless` (the real journal editor), `hello` (smoke test).

## The loop

**1. Mount something.** Push panel-building Lua straight in -- no file edit, no reload:

```
execute_lua('return TestHarness.Scratch([==[
    return gui.Panel{
        width = 420, height = "auto", flow = "vertical", halign = "center", valign = "center",
        bgimage = "panels/square.png", bgcolor = "#1a2333ff",
        borderWidth = 2, borderColor = "#5f7396ff", cornerRadius = 10,
        pad = 16, borderBox = true,
        gui.Label{ text = "Hello", fontSize = 26, width = "auto", height = "auto", halign = "center" },
    }
]==])')
```

The chunk **must `return` a panel** (or an array of panels). `Scratch` returns `nil` on
success, or the compile/runtime error string -- so read the return value; you do not need
`get_console_log` for ordinary failures. The error also renders in the stage.

Use `[==[ ... ]==]` long brackets so the Lua inside can contain `[[` and `]]` freely.

**2. Look.** `screenshot()` then Read the PNG. For assertions rather than eyeballing,
`execute_lua("return json(TestHarness.Probe())")`.

**3. Change.** Re-call `TestHarness.Scratch(...)` with the revised code. It remounts in
place. Iterate as many times as you like -- nothing is written to disk.

**4. Graduate.** When the UI is right, write it into the real Lua file.

## Iterating on a REAL panel (the main event)

The point of the harness is working on production panels away from a game. Fixtures build
what those panels take as arguments, inside the lobby game, touching nothing real:

| Fixture | Gives you |
|--|--|
| `TestHarness.Fixture.Document(content)` | a detached `MarkdownDocument`, never saved or uploaded |
| `TestHarness.Fixture.Character(callback[, {forceNew=true}])` | a character token, **via callback** (creation round-trips the local server). Reuses an existing lobby character unless `forceNew` |

Mount the real thing:

```
execute_lua('return TestHarness.Scratch([==[
    local doc = TestHarness.Fixture.Document("# Notes\n\nBody **text**.")
    local panel = doc:SeamlessEditPanel{}
    panel:SetClass("collapsed", false)
    return panel
]==])')
```

**Then the loop that matters:** edit the panel's real source file, `reload_lua()`, and the
scratch **re-runs itself against the freshly loaded code** -- the mounted panel rebuilds
with your change. Edit, reload, screenshot. No relaunch.

If you created a character with `forceNew`, clean it up:
`game.DeleteCharacters({ token.charid })`.

## The stage

Harness content mounts in a **stage** -- a sized, styled, backdropped box -- so you can
judge a panel at the geometry and cascade it will really get:

```
execute_lua('return json(TestHarness.SetStage{ size = "dock", cascade = "theme", backdrop = "contrast" })')
```

| Setting | Values |
|--|--|
| `size` | `full`, `dock` (real `DockablePanel.DockWidth`, 364), `dialog` (800x600), `wide` (1200x720), `narrow` (420), `tiny` (320x240) |
| `cascade` | `default` (`Styles.Default`), `theme` (`ThemeEngine.GetStyles()` -- what a docked panel gets), `none` |
| `backdrop` | `dark`, `mid`, `light`, `contrast` |

Reach for these deliberately:

- **`size = "dock"`** before claiming a panel works -- most panels live in a 364px dock and
  break there, not at 1920.
- **`backdrop = "contrast"`** (magenta) to see a panel's true bounds. It makes overflow and
  unintended transparency obvious; against `dark` at full width both are invisible.
- **`cascade`** to check a panel isn't secretly depending on the wrong style root.

Changing a stage setting mutates the live stage -- `create()` is **not** re-run, so the
panel under test keeps its state while you resize it. The chrome dropdowns follow.

## Reading state without screenshots

`TestHarness.Probe()` returns the active harness id, stage settings, live rendered pixel
size, and the harness's own `probe()` output. Prefer it over screenshot-diffing for
anything numeric. `TestHarness.ActiveContext()` returns the harness's ctx table for ad-hoc
poking.

## Graduating a scratch into a registered harness

Scratch is ephemeral. When a setup is worth keeping, add it to the TestHarness section of
`Development Utilities/DevTools.lua`:

```lua
TestHarness.Register{
    id = "myPanel",
    stage = { size = "dock", cascade = "theme", backdrop = "dark" }, --optional defaults
    create = function(args, ctx) ... return panel end,
    probe = function(ctx) return { ... } end,   --optional, machine-readable assertions
}
```

Then `--harness myPanel` or `TestHarness.Show("myPanel")`.

## Gotchas that cost time

1. **gui panels are `userdata`, not tables.** `type(gui.Label{...}) == "userdata"`
   (`LuaSheetPanel`/`LuaSheetLabel`); `rawget` on one throws "table expected". Any
   "is this a panel" check written as `type(x) == "table"` silently rejects every panel.
2. **`Probe()` in the same `execute_lua` as `Show`/`SetStage` reports stale
   `renderedWidth/Height`** (often 100) -- layout has not run yet. Re-probe in a later call.
3. **The harness only exists at the titlescreen.** The shell parents to
   `CodexTitlescreenRoot`, so it cannot be shown inside a real game, and there is no
   `GameHud`, no map, no tokens. Panels needing those are out of scope here.
4. **The app's version text and "Manage Assets" button overlay the bottom ~50px** in their
   own canvas, above any Lua panel. Keep content clear of it.
5. **`gui.TextEditor` inherits `characterLimit = 256`** from the SheetInput prefab. Longer
   content makes every keystroke silently fail while arrows still work. Set it explicitly.
6. **File edits need `reload_lua()`; scratch does not.** The dev-mod gitfolder points at
   this repo, so editing a `.lua` here is what the app loads -- but only after a reload.
   Verify a file compiles without reloading -- note the doubled backslashes, which are
   Lua's escape for a single one:

   ```lua
   local f, e = loadfile("c:\\dev\\dmhub\\draw-steel-codex\\Development Utilities\\DevTools.lua")
   print(f ~= nil and "COMPILE OK" or e)
   ```
7. **A failed mount can orphan a panel** the chunk already built, logging "was created but
   not attached to a parent." Harmless; it means your chunk built a panel and did not
   return it.

## Putting the user back

When you are done, offer to return them to what they were doing:

```
stop_dmhub()
start_dmhub(game_id="<the game they were in>")
```

## Where the rest is documented

- `mcp-server/README.md`, "Test Harness Mode" -- the full API/driving reference.
- `TEST_HARNESS_PLAN.md` (engine repo root) -- design rationale and history.
- Sibling skill **`dmhub-gui`** -- how to write the Lua you are mounting. This skill only
  owns running and looking at it.
