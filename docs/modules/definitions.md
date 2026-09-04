# Engine API -- Definitions

The `Definitions/` directory contains **208 LuaLS type-stub files** that document the closed-source DMHub engine API. These files are never executed at runtime -- they exist purely to give your editor (VS Code + Sumneko Lua, IntelliJ EmmyLua, etc.) accurate type information for autocompletion, hover docs, and go-to-definition.

!!! warning "Stubs only -- no real logic"
    Every function body in `Definitions/` is a placeholder:
    ```lua
    function gui.Panel(args)
        -- dummy implementation for documentation purposes only
    end
    ```
    Do **not** add real code here. The engine provides the actual implementations at runtime.

## What the stubs document

The stubs declare the **global objects** injected by the DMHub engine before any mod code runs:

| Global | Stub file | Purpose |
|--------|-----------|---------|
| `dmhub` | `dmhub.lua` | Main engine interface -- game state, tokens, scheduling, file I/O, events, user info |
| `gui` | `gui.lua`, `gui-definitions.lua` | UI factory (`gui.Panel`, `gui.Label`, `gui.Input`, `gui.Table`, etc.) and Panel class fields |
| `game` | `game.lua` | Live game session interface |
| `creature` | `core-definitions.lua` | Base creature type used by Characters and Monsters |
| `GameRules` | `core-definitions.lua` | Global rules configuration object |
| `module` | `module.lua` | Mod lifecycle, `GetModLoading()`, document snapshots |

## Key stub files at a glance

| File | What it covers |
|------|---------------|
| `dmhub.lua` | ~100 fields on the `dmhub` global: `version`, `userid`, `isDM`, `isGameOwner`, `GetSelectedCharacters`, token vision, upload quotas, scheduling, etc. |
| `gui.lua` | Factory functions: `gui.Style`, `gui.Panel`, `gui.Label`, `gui.Input`, `gui.Table`, `gui.Carousel`, `gui.RegisterTheme`, `gui.Gradient`, `gui.MarkdownStyle` |
| `gui-definitions.lua` | The `Panel` class fields, style properties, and event callbacks (`click`, `change`, `create`, `think`, `refreshGame`) |
| `game.lua` | The `game` global for live session queries |
| `enums.lua` | Engine-level enum values (alignment, flow direction, visibility, etc.) |
| `CharacterToken.lua` | The `CharacterToken` class -- methods for token movement, vision, modification |
| `assets.lua` | Asset loading and management interfaces |
| `audio.lua` | Audio playback and asset types |
| `chat.lua` | Chat message types and sending interface |
| `dice.lua` | Dice rolling and parsing API |
| `editor.lua` | Map editor callbacks and editing state |
| `net.lua` | Networking, cloud data, write receipts |
| `import.lua` | Data import interfaces |

## How to use the stubs for code navigation

1. **Open the workspace root** in VS Code with the Lua Language Server extension installed.
2. The extension automatically picks up the `Definitions/` directory and indexes every `@class`, `@field`, and `@return` annotation.
3. Hover over any global like `dmhub.isDM` or `gui.Panel` to see its type and doc comment.
4. Use **Go to Definition** (F12) on a global to jump straight to the stub file.

!!! tip "Reading the annotations"
    The stubs use standard EmmyLua / LuaLS annotations:
    ```lua
    --- @field isDM boolean (read-only) true if the current user has GM status.
    ```
    The `@class`, `@field`, `@param`, `@return`, and `@alias` tags all feed into your editor's type checker.

## Relationship to runtime code

```
Definitions/          <-- Type stubs (documentation only)
    dmhub.lua              Describes the dmhub global
    gui.lua                Describes gui.Panel, gui.Label, ...
    ...
DMHub Game Rules/     <-- Real code that USES these globals
Draw Steel Core Rules/<-- Real code that USES these globals
```

The stubs describe what the engine provides; the other modules contain the actual game logic that calls those engine APIs. When you see `dmhub.GetTable("charConditions")` in a Game Rules file, the stub in `dmhub.lua` tells your editor the return type and parameter expectations.
