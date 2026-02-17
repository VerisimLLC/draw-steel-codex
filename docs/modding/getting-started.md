# Getting Started: Your First DMHub Mod

This guide walks you through creating a minimal mod for the Draw Steel Codex / DMHub platform. By the end, you'll have a working mod that adds a chat command.

## Prerequisites

- A working DMHub installation
- Basic familiarity with [Lua](https://www.lua.org/manual/5.4/)

## Module Structure

A DMHub mod is simply a **directory containing `.lua` files**. There is no manifest, no config file, no metadata — just Lua code.

```
My Awesome Mod/
├── MyFeature.lua
└── MyOtherFeature.lua
```

Every Lua file in your mod **must** start with this line:

```lua
local mod = dmhub.GetModLoading()
```

This tells the engine which mod the file belongs to. Without it, your code won't load correctly.

## Module ID Convention

When DMHub loads modules, each directory gets a **namespaced ID** in the format:

```
ModuleName_xxxx
```

- Spaces in the directory name become underscores
- `xxxx` is a 4-character hex suffix (assigned by the engine)

For example, the directory `Chat Enhancements/` becomes `Chat_Enhancements_6e49`.

In `main.lua`, files are loaded via `require()` using this namespace:

```lua
require('Chat_Enhancements_6e49.Core')
require('Chat_Enhancements_6e49.InCharacter')
require('Chat_Enhancements_6e49.Whisper')
```

## Hello World: A Chat Command

Let's build the simplest possible mod — a `/hello` chat command.

### Step 1: Create Your Module Directory

Create a directory at the project root:

```
Hello World Mod/
└── HelloWorld.lua
```

### Step 2: Write the Code

```lua
-- Hello World Mod/HelloWorld.lua
local mod = dmhub.GetModLoading()

Commands.hello = function(str)
    chat.Send("Hello from my first mod!")
end
```

That's it. When a user types `/hello` in chat, it sends a message.

### Step 3: Register in main.lua

Add a `require` line to `main.lua`. Place it after the core modules have loaded (near the end of the file is safest):

```lua
require('Hello_World_Mod_xxxx.HelloWorld')
```

Replace `xxxx` with the hex suffix the engine assigns to your module.

## A More Complete Example: Timer Command

Here's a real mod from the codebase (`Codex Macros/TimerMacro.lua`) that creates a `/timer` command with a custom chat UI:

```lua
local mod = dmhub.GetModLoading()

-- Register a serializable game type for our custom chat message
TimerChatMessage = RegisterGameType("TimerChatMessage")

-- Define how the message renders in chat
function TimerChatMessage.Render(self, message)
    return gui.Panel{
        width = "100%",
        flow = "horizontal",
        gui.Label{
            fontSize = 18,
            bold = true,
            text = "Timer",
            width = "auto",
            height = "auto",
        },
        gui.Label{
            fontSize = 18,
            text = string.format("%d seconds", self.duration),
            width = "auto",
            height = "auto",
        },
    }
end

-- Register the /timer command
Commands.timer = function(str)
    local duration = tonumber(str) or 5
    local message = TimerChatMessage.new{
        channel = "chat",
        duration = duration,
        timestamp = dmhub.serverTime,
    }
    chat.SendCustom(message)
end
```

Key patterns used:
- **`RegisterGameType("Name")`** — creates a serializable class that can be sent over the network
- **`.new{}`** — constructs an instance of a registered game type
- **`.Render(self, message)`** — defines how the object displays in chat
- **`chat.SendCustom(message)`** — sends a custom object to chat
- **`gui.Panel{}` / `gui.Label{}`** — builds UI elements

## A Data Registration Example: Quotes

The simplest non-command mod in the codebase is `Codex Quotes/`, which registers data entries:

**`CodexQuotesRegistry.lua`** — sets up the registry:
```lua
local mod = dmhub.GetModLoading()

CodexQuotes = {
    quotes = {}
}

CodexQuotes.Register = function(entry)
    CodexQuotes.quotes[entry.id] = entry
end

CodexQuotes.SelectQuote = function()
    local entries = table.values(CodexQuotes.quotes)
    if #entries == 0 then return nil end
    return entries[math.random(1, #entries)]
end
```

**`CodexQuotes.lua`** — registers entries:
```lua
local mod = dmhub.GetModLoading()

CodexQuotes.Register{
    id = "core_fury_001",
    context = "Iconic Fury",
    quote = [["DEATH!"]],
    speaker = "Khorva",
}
```

Key pattern: **define a global table in one file, populate it from other files**. The load order in `main.lua` ensures the registry file is loaded first.

## Load Order

The order of `require()` calls in `main.lua` defines the dependency graph. The general loading sequence is:

1. **DMHub Titlescreen** — app chrome, styles
2. **DMHub Utils** — shared utilities, GoblinScript DSL
3. **DMHub Core UI** — GUI framework, panels, dropdowns
4. **DMHub Core Panels** — built-in panels (chat, terrain, maps)
5. **DMHub Game Rules** — characters, creatures, abilities, modifiers
6. **DMHub Compendium** — content editors
7. **Draw Steel Core Rules** — MCDM-specific rules
8. **Draw Steel UI / Character Builder** — Draw Steel interfaces
9. **Extension modules** — smaller mods (macros, chat enhancements, etc.)

Place your module's `require` lines **after** anything it depends on. If your mod only uses basic APIs (`Commands`, `chat`, `gui`, `dmhub`), placing it near the end of `main.lua` is safe.

## Next Steps

- **[Extension Points](extension-points.md)** — all the registration functions you can use to hook into the system
- **[Core API Reference](core-api-reference.md)** — annotated reference for `dmhub`, `gui`, `chat`, `game`, and more
- **[GoblinScript Reference](goblinscript.md)** — the built-in expression language for game formulas
- **[Common Patterns](patterns.md)** — worked examples for common modding tasks
