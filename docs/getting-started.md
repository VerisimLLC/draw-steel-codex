# Getting Started

This page will help you orient yourself in the Draw Steel Codex codebase. By the end, you'll understand the project layout and know where to look for any piece of functionality.

## Prerequisites

- [DMHub](https://dmhub.app) installed (the VTT engine this mod runs inside)
- A text editor with Lua support (VS Code with the Lua Language Server extension recommended)
- Git (to clone the repository)

## Cloning the repo

```bash
git clone https://github.com/VerisimLLC/draw-steel-codex.git
cd draw-steel-codex
```

## Understanding the project layout

This is not a typical application with a build step. The entire codebase is **Lua source files** that DMHub loads at runtime. There is no compiler, no bundler, and no test runner.

The root of the repo looks like this:

```
draw-steel-codex/
  main.lua                          # Entry point — loads all 517 files
  CLAUDE.md                         # AI development guide
  GoblinScript_Guide.md             # Formula language reference
  UI_BEST_PRACTICES.md              # UI control reference
  monster-reference.md              # Monster stat blocks
  Definitions/                      # Engine API type stubs (209 files)
  DMHub_Utils_5b73/                 # Shared utilities
  DMHub_Core_UI_752e/               # UI framework
  DMHub_Game_Rules_fc51/            # Base game rules (foundation)
  Draw_Steel_Core_Rules_1b8f/       # Draw Steel system (domain)
  Draw_Steel_Character_Builder_45c3/  # Character creation
  Draw_Steel_UI_bd58/               # Draw Steel UI panels
  ... (42 modules total)
```

## The module naming convention

Every directory follows the pattern **`ModuleName_XXXX`** where `XXXX` is a hex module ID assigned by DMHub. For example:

- `DMHub_Game_Rules_fc51` — the base game rules module (ID: `fc51`)
- `Draw_Steel_Core_Rules_1b8f` — the Draw Steel system (ID: `1b8f`)
- `DMHub_Core_UI_752e` — the UI framework (ID: `752e`)

The hex suffix is just an identifier. Don't worry about memorizing them — focus on the human-readable name before the underscore.

## How files are loaded

Open `main.lua`. You'll see 517 `require()` calls like:

```lua
require('DMHub_Utils_5b73.Utils')
require('DMHub_Utils_5b73.CoroutineUtils')
require('DMHub_Utils_5b73.GoblinScript')
require('DMHub_Core_UI_752e.Gui')
require('DMHub_Core_UI_752e.Hud')
-- ... 512 more
```

**Order matters.** Dependencies must be loaded before the files that use them. This is why utilities and core UI load first, game rules load next, and Draw Steel-specific code loads last.

Every Lua file starts with the same line:

```lua
local mod = dmhub.GetModLoading()
```

This gives the file access to its parent module's lifecycle. You'll see `mod` used throughout for things like checking if the module has been unloaded (`mod.unloaded`).

!!! warning "Do not create new Lua files"
    Lua files must be registered through DMHub's module system. Simply placing a file on disk and adding a `require` to `main.lua` will cause a load failure. If you need to add code, add it to an existing file in the appropriate module.

## The four architecture layers

The codebase is organized into four layers, from lowest-level to highest:

1. **Engine API** (`Definitions/`) — Type stubs documenting what DMHub provides. You never edit these, but they're invaluable for understanding what functions are available.

2. **Foundation** (`DMHub_Game_Rules_fc51/`, `DMHub_Core_UI_752e/`, `DMHub_Utils_5b73/`) — Generic, system-agnostic game rules and UI framework. Creatures, abilities, conditions, and the panel system live here.

3. **Domain** (`Draw_Steel_Core_Rules_1b8f/`, `Draw_Steel_Ability_Behaviors_aef5/`, `Draw_Steel_Modifiers_d18e/`) — Draw Steel-specific implementation. This layer extends the foundation with MCDM's game mechanics.

4. **UI/Integration** (`Draw_Steel_UI_bd58/`, `Draw_Steel_Character_Builder_45c3/`, `DMHub_Core_Panels_65a9/`) — User-facing panels, character creation, compendium browsers, and HUD elements.

See [Architecture Overview](architecture/overview.md) for a detailed diagram.

## Where to look for things

| "I want to understand..." | Start here |
|---------------------------|-----------|
| What functions the DMHub engine provides | `Definitions/dmhub.lua`, `Definitions/gui.lua` |
| How creatures and characters work | `DMHub_Game_Rules_fc51/Creature.lua`, `Character.lua` |
| How abilities are defined | `DMHub_Game_Rules_fc51/ActivatedAbility.lua` |
| How Draw Steel overrides the base system | `Draw_Steel_Core_Rules_1b8f/MCDMRules.lua` |
| How the UI panel system works | `DMHub_Core_UI_752e/Gui.lua` |
| How GoblinScript formulas work | `DMHub_Utils_5b73/GoblinScript.lua` + [GoblinScript Guide](https://github.com/VerisimLLC/draw-steel-codex/blob/main/GoblinScript_Guide.md) |
| How character creation works | `Draw_Steel_Character_Builder_45c3/CharacterBuilder.lua` |
| How monster data is structured | [monster-reference.md](https://github.com/VerisimLLC/draw-steel-codex/blob/main/monster-reference.md) |

## Existing documentation

The repo includes several documentation files that predate this wiki:

- **[CLAUDE.md](https://github.com/VerisimLLC/draw-steel-codex/blob/main/CLAUDE.md)** — Comprehensive development guide covering architecture, patterns, and constraints. Originally written for AI assistants but useful for any developer.
- **[GoblinScript_Guide.md](https://github.com/VerisimLLC/draw-steel-codex/blob/main/GoblinScript_Guide.md)** — Full reference for the GoblinScript expression language.
- **[UI_BEST_PRACTICES.md](https://github.com/VerisimLLC/draw-steel-codex/blob/main/UI_BEST_PRACTICES.md)** — UI control reference with examples for every widget type.

## Next steps

- Read the [Architecture Overview](architecture/overview.md) to see how all the pieces fit together
- Browse the [Module Map](architecture/module-map.md) to find specific functionality
- Dive into [Design Patterns](patterns/game-types.md) to understand how code is structured
