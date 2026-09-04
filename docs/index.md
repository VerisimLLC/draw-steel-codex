# Draw Steel Codex Wiki

Welcome to the code documentation for the **Draw Steel Codex** — the Lua mod for [DMHub](https://dmhub.app) that implements MCDM's *Draw Steel* tabletop RPG system.

This wiki is for anyone who wants to understand how the codebase works: new contributors, modders looking to extend it, or anyone curious about the architecture.

## What is this project?

Draw Steel Codex is a **Lua mod** that runs inside DMHub, a virtual tabletop (VTT) platform. It implements the full Draw Steel RPG system, including:

- Character creation and progression
- Abilities, conditions, and combat mechanics
- Monster stat blocks and AI
- A rich compendium browser and editors
- Custom UI panels (action bars, character sheets, initiative tracking)
- GoblinScript, a formula expression language for game mechanics
- A document/journal system with embedded dice rolls and encounters

## Tech stack

| Component | Technology |
|-----------|-----------|
| Language | Lua (99.8%), Python (validation tooling) |
| Runtime | DMHub engine |
| UI | Declarative panel system (`gui.Panel{}`, `gui.Label{}`, etc.) |
| Formulas | GoblinScript (custom expression language) |
| Data | Named tables with cloud persistence |
| Modules | 42 modules, 517 files loaded via `main.lua` |

## Quick links

**Start here:**

- [Getting Started](getting-started.md) — How to orient yourself in the codebase
- [Architecture Overview](architecture/overview.md) — The big picture in one diagram

**Understand the code:**

- [Module Map](architecture/module-map.md) — Every module with its purpose and key files
- [Loading System](architecture/loading-system.md) — How `main.lua` boots everything

**Learn the patterns:**

- [Game Types](patterns/game-types.md) — How game objects are defined and extended
- [Data Tables](patterns/data-tables.md) — Reading and writing persistent game data
- [Token Mutations](patterns/token-mutations.md) — The required pattern for changing token state
- [UI Framework](patterns/ui-framework.md) — Building declarative UI panels
- [GoblinScript](patterns/goblinscript.md) — The formula language powering game mechanics

**Explore the modules:**

- [Game Rules](modules/game-rules.md) — The foundation layer (creatures, abilities, conditions)
- [Draw Steel Rules](modules/draw-steel-rules.md) — The MCDM-specific layer
- [Character Builder](modules/character-builder.md) — The creation wizard
- [Abilities](modules/abilities.md) — How abilities work end-to-end

**Reference:**

- [File Index](reference/file-index.md) — Every file in the repo with a description
- [Glossary](reference/glossary.md) — DMHub and Draw Steel terminology
