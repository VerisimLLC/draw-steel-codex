# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

This is the **draw-steel-codex** repository — the Lua mod source code for [DMHub](https://dmhub.app), a tabletop RPG virtual tabletop (VTT). Specifically, it implements the **Draw Steel** (MCDM) game system on top of the DMHub engine. The code runs inside the DMHub app; there is no standalone build process, test runner, or linter to invoke from the command line.

## How the Code is Loaded

`main.lua` at the root is the module entry point. It contains a flat list of `require(...)` calls that load every file in the project. Each `require` uses the pattern `ModuleName_XXXX.FileName`, where `ModuleName_XXXX` is a subdirectory name (with a hex suffix that acts as a module ID). Files are loaded in order — dependencies must come before the files that use them.

Each Lua file begins with:
```lua
local mod = dmhub.GetModLoading()
```
This gives access to the current module interface. The `mod` object is used to track module lifecycle (e.g., `mod.unloaded`).

## Repository Structure

Each top-level directory is a "mod" (module) loaded by DMHub. Key layers:

| Directory | Purpose |
|---|---|
| `Definitions/` | LuaLS type stubs for the DMHub engine API (not executed — documentation only). All engine globals (`dmhub`, `gui`, `game`, `creature`, etc.) are declared here. |
| `DMHub Utils/` | Shared utility library: `Utils.lua` (table/string helpers), `GoblinScript.lua` (formula expression evaluator), `CoroutineUtils.lua`, `MarkdownRenderUtils.lua`. |
| `DMHub Core UI/` | Core UI framework: `Gui.lua` wraps the engine `gui` global, `Hud.lua`, `DockablePanel.lua`, `Scrollable.lua`, etc. |
| `DMHub Core Panels/` | Application panels: Chat, Character panel, Map tools, Compendium, Dev tools, etc. |
| `DMHub Game Rules/` | Base game rules system: `BasicRules.lua`, `ActivatedAbility.lua`, `Creature.lua`, `Character.lua`, `Class.lua`, `Condition.lua`, `Equipment.lua`, etc. This layer is generic/system-agnostic. |
| `Draw Steel Core Rules/` | The Draw Steel (MCDM) game system implementation built on top of DMHub Game Rules. `MCDMRules.lua` calls `GameSystem.ClearRules()` then sets DS-specific names (Stamina, Characteristics, Power Rolls, etc.). Most `MCDM*.lua` and `DS*.lua` files here extend or override base game types. |
| `Draw Steel Character Builder/` | New character creation wizard UI and state machine. |
| `Draw Steel UI/` | DS-specific UI panels (action bar, character sheet, class/kit editors, initiative, etc.). |
| `Draw Steel V/` | Newer DS feature panels (encounter, heroes, negotiation, downtime, fishing, chessboard, etc.). |
| `Draw Steel Ability Behaviors/` | Individual ability behavior implementations (`AbilityDamage`, `AbilityForcedMovementLoc`, `AbilityTemporaryEffects`, etc.). |
| `Draw Steel Modifiers/` | Modifier implementations (`ModifierCaptain`, `ModifierForcedMovement`, `ModifierInvisibility`, etc.). |
| `Downtime Projects/` | Downtime project system (rules + UI). |
| `DMHub Compendium/` | Compendium browser and editors for game content. |
| `DMHub CharacterSheet Base/` | Base character sheet framework. |
| `DocumentSystem/` | Rich document/journal system with Markdown, images, embedded dice rolls, etc. |

## Core Architecture Patterns

### Game Types
Game objects are declared with `RegisterGameType("TypeName")` or `RegisterGameType("TypeName", "ParentType")`. This registers a type in the engine's serialization system. You then add default fields and methods directly on the global:
```lua
CharacterCondition = RegisterGameType("CharacterCondition", "CharacterFeature")
CharacterCondition.name = "New Condition"
CharacterCondition.tableName = "charConditions"
function CharacterCondition:SoundEvent() ... end
```

Extending a type from another file (common in `Draw Steel Core Rules/`):
```lua
-- Extend creature with Draw Steel fields
creature.minion = false
local g_base = creature.Invalidate
function creature:Invalidate()
    g_base(self)
    -- DS-specific invalidation
end
```

### Data Tables
Game data is stored in named tables accessed via `dmhub.GetTable("tableName")`. Iterate with `unhidden_pairs(t)` (skips soft-deleted entries). Write with `dmhub.SetAndUploadObject(tableName, id, obj)`.

### Shared Documents
Shared cloud documents provide key-value storage that syncs across all clients in a game session. They are used for real-time shared state such as chat events, audio grid slots, global resources, initiative data, and downtime project shares. Unlike Data Tables (which store game content definitions), documents hold live session state.

**Getting a snapshot:**
```lua
local doc = mod:GetDocumentSnapshot("myDocId")
```
The `docid` is any unique string. The returned snapshot has a `.data` table (the document contents) and a `.path` string (for monitoring).

**Reading data:**
```lua
local value = doc.data.someKey
```

**Writing data** (must wrap mutations in `BeginChange`/`CompleteChange`):
```lua
local doc = mod:GetDocumentSnapshot("myDocId")
doc:BeginChange()
doc.data.someKey = newValue
doc:CompleteChange("Description of change")
```
`CompleteChange` accepts an optional second argument table, e.g. `{undoable = false}`.

**Monitoring for changes in UI panels** -- set `monitorGame` to the document path so `refreshGame` fires when any client changes the document:
```lua
gui.Panel{
    monitorGame = mod:GetDocumentSnapshot("myDocId").path,
    refreshGame = function(element)
        local doc = mod:GetDocumentSnapshot("myDocId")
        -- update UI from doc.data
    end,
}
```

**Checkpoint backups** -- register a document so it is included in game-state checkpoint saves:
```lua
mod:RegisterDocumentForCheckpointBackups("myDocId")
```

**Helper for path** -- `mod:GetDocumentPath("myDocId")` returns the monitoring path string directly (equivalent to `mod:GetDocumentSnapshot("myDocId").path`).

### UI (gui panels)
UI is built with `gui.Panel(args)`, `gui.Label(args)`, `gui.Input(args)`, etc. Panels are declarative tables with style properties and event callbacks (`click`, `change`, `create`, `think`, `refreshGame`). Panels that need to react to data changes use `monitorstate` or `monitor` fields.

### GoblinScript
GoblinScript is an expression language (evaluates formula strings) used for ability costs, damage formulas, prerequisites, etc. Compile with `GoblinScript.Compile(formula, symbolTable)` and evaluate with `GoblinScript.Execute(compiled, context)`.

### Module Lifecycle
Guard against stale closures using `mod.unloaded`:
```lua
local mod = dmhub.GetModLoading()
dmhub.Schedule(delay, function()
    if mod.unloaded then return end
    -- do work
end)
```

### Settings
Persistent settings use the `setting{}` constructor:
```lua
local mySetting = setting{
    id = "mysettingid",
    name = "My Setting",
    default = true,
    onchange = function() ... end,
}
```

## Lua File Constraints

**ASCII only.** The DMHub Lua runtime does not handle non-ASCII characters in source files. All Lua files — including comments and EmmyLua annotations — must contain only ASCII characters (bytes 0–127). Never use em dashes (`—`), curly quotes (`""`), ellipses (`…`), or any other Unicode punctuation. Use plain ASCII equivalents instead: `-` or `:` instead of `—`, `"` instead of curly quotes, `...` instead of `…`.

## `Definitions/` Files

These are **LuaLS stub files** (LSP type annotations) for the closed-source DMHub engine API. They define the types and signatures of engine globals but contain only dummy `-- dummy implementation` bodies. Do not add real logic here. When the engine API has a function you want to call, its signature will be in one of these files.

Key stubs:
- `dmhub.lua` — the main `dmhub` global (game state, tokens, scheduling, file I/O, events)
- `gui.lua` / `gui-definitions.lua` — UI panel constructors and Panel class fields/events
- `game.lua` — the `game` global
- `GameRules.lua` — `GameRules` global
- `module.lua` — `module` global for mod management
