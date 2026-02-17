# Extension Points

This document catalogs every registration function available for modders to hook into the DMHub / Draw Steel system. Each entry includes the function signature, a description, and a real code example from the codebase.

---

## Chat Commands

**Function:** `Commands.<name> = function(str) ... end`

Register a slash command that users can type in chat. The function receives the text after the command name as a string.

```lua
-- Source: Codex Macros/TimerMacro.lua
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

Commands can also implement a `help` subcommand pattern:

```lua
-- Source: Codex Macros/Macros.lua
Commands.monster = function(str)
    if str == "help" then
        dmhub.Log("Usage: /monster <name> <x> <y>\n Spawns the named monster.")
        return
    end
    -- ... implementation
end
```

---

## Game Types

**Function:** `RegisterGameType(name [, parentName])`

Creates a serializable class that can be sent over the network (e.g., for custom chat messages). Objects created with `.new{}` are automatically serializable.

```lua
-- Source: Chat Enhancements/Core.lua
ExtChatMessage = RegisterGameType("ExtChatMessage")
ExtChatMessage.__index = ExtChatMessage

function ExtChatMessage.Render(self, message)
    return gui.Panel{
        classes = {"chat-message-panel"},
        children = {
            gui.Label{
                fontSize = "14.5",
                height = "auto",
                text = self.message,
            },
        },
    }
end

-- Creating and sending an instance:
function ExtChatMessage.Send(text, recipients)
    local m = ExtChatMessage.new{
        channel = "chat",
        message = text,
        timestamp = dmhub.serverTime,
    }
    chat.SendCustom(m)
end
```

You can inherit from a parent type:

```lua
RegisterGameType("DTAdjustment", "DTProgressItem")
```

---

## Ability Behaviors

**Function:** `ActivatedAbility.RegisterType(args)`

Registers a new ability behavior type that appears in the ability editor. Each type must provide a factory function that creates a behavior instance.

**Parameters:**
- `id` (string) — unique identifier
- `text` (string) — display name in the editor
- `createBehavior` (function) — factory returning a new behavior instance
- `mono` (boolean, optional) — if `true`, this behavior must be the only one on an ability

```lua
-- Source: DMHub Game Rules/ActivatedAbility.lua
ActivatedAbility.RegisterType{
    id = 'heal',
    text = 'Healing',
    createBehavior = function()
        return ActivatedAbilityHealBehavior.new{
            roll = "1d6",
        }
    end
}

ActivatedAbility.RegisterType{
    id = 'castspell',
    text = 'Cast Spell',
    mono = true,  -- must be used alone on an ability
    createBehavior = function()
        return ActivatedAbilityCastSpellBehavior.new{
            spells = {},
        }
    end,
}
```

To hide a built-in behavior type:

```lua
ActivatedAbility.SuppressType("Attack")  -- by name or id
```

---

## Character Modifiers

**Function:** `CharacterModifier.RegisterType(id, text)`

Registers a new modifier type that can be applied to characters via features or ongoing effects. After registering, define the modifier's behavior in `CharacterModifier.TypeInfo`.

```lua
-- Source: DMHub Game Rules/CharacterModifier.lua
CharacterModifier.RegisterType('light', "Light Source")

CharacterModifier.TypeInfo.light = {
    init = function(modifier)
        -- Initialize modifier-specific fields
        modifier.lightRadius = 20
    end,
    createEditor = function(modifier, element, options)
        -- Return a GUI panel for editing this modifier
        return gui.Panel{ ... }
    end,
}
```

To remove a built-in modifier type:

```lua
CharacterModifier.DeregisterType('damage')
```

---

## Dockable UI Panels

**Function:** `DockablePanel.Register(args)`

Registers a panel that can be docked in the DMHub interface.

**Parameters:**
- `name` (string) — display name
- `icon` (string) — icon path
- `minHeight` (number) — minimum panel height
- `vscroll` (boolean, optional) — enable vertical scrolling
- `dmonly` (boolean, optional) — restrict to GM only
- `content` (function) — returns a `Panel` to display
- `hasNewContent` (function, optional) — returns `true` if the panel has unread content

```lua
-- Source: DMHub Core Panels/CharacterPanel.lua (pattern)
DockablePanel.Register{
    name = "Character",
    icon = "icons/standard/Icon_App_Character.png",
    minHeight = 140,
    vscroll = true,
    content = function()
        return CreateCharacterPanel()
    end,
    hasNewContent = function()
        return module.HasNovelContent("character")
    end,
}
```

---

## Token HUD Icons

**Function:** `TokenUI.RegisterIcon(args)`

Registers a status icon displayed on creature tokens.

**Parameters:**
- `id` (string) — unique identifier
- `icon` (string) — icon image path
- `Filter` (function, optional) — receives `creature`, returns `true` to show the icon
- `Calculate` (function, optional) — receives `creature`, returns an icon entry table or `nil`
- `showToAll` (boolean) — show to all players
- `showToGM` (boolean) — show to the GM
- `showToController` (boolean) — show to the controlling player
- `showToFriends` (boolean) — show to party members
- `showToEnemies` (boolean) — show to enemy players

Use `Filter` for static icons and `Calculate` for dynamic icons:

```lua
-- Source: DMHub Token UI/TokenUIConfig.lua

-- Static icon with a filter:
TokenUI.RegisterIcon{
    id = "wounded",
    icon = "ui-icons/wounded-border.png",
    Filter = function(creature)
        return creature.damage_taken >= creature:MaxHitpoints()/2
    end,
    showToAll = true,
}

-- Dynamic icon with calculation:
TokenUI.RegisterIcon{
    id = "movetype",
    Calculate = function(creature)
        local movetype = creature:CurrentMoveTypeInfo()
        if creature:CurrentMoveType() == "walk" then
            return { id = movetype.id, icon = "ui-icons/token-elevation-icon.png",
                     hasAltitude = true, hideAtZeroAltitude = true }
        end
        return { id = movetype.id, icon = movetype.icon, hasAltitude = true }
    end,
    showToAll = true,
}
```

To remove icons:

```lua
TokenUI.ClearIcon("wounded")   -- remove a specific icon
TokenUI.ClearAllIcons()         -- remove all icons (useful to start fresh)
```

---

## Token Status Bars

**Function:** `TokenUI.RegisterStatusBar(args)`

Registers a status bar displayed on creature tokens (e.g., health/stamina bar).

```lua
-- Source: DMHub Token UI/TokenUIConfig.lua
TokenUI.RegisterStatusBar{
    id = "lifebar",
    height = 9,
    width = 1,
    seek = 10,  -- bar animates at 10 HP/second
    fillColor = {
        { value = 0.5, color = "white", gradient = Styles.healthGradient },
        { color = "white", gradient = Styles.damagedGradient },
    },
    tempColor = "blue",
    showToGM = function() return gmSeesHitpoints:Get() end,
    showToController = function() return playersSeeOwnHitpoints:Get() end,
    Calculate = function(creature)
        return {
            value = creature:CurrentHitpoints(),
            max = creature:MaxHitpoints(),
            temp = creature:TemporaryHitpoints(),
        }
    end
}
```

---

## Token HUD Panels

**Function:** `TokenHud.RegisterPanel(info)`

Registers a panel displayed above or below creature tokens during gameplay.

```lua
-- Source: Draw Steel UI/DrawSteelTokenHud.lua (pattern)
TokenHud.RegisterPanel{
    id = "drawsteel",
    ord = 1,            -- display order
    layer = "top",      -- "top" or "bottom"
    create = function(token, sharedInfo)
        -- Return a Panel, or nil to skip
        return gui.Panel{ ... }
    end,
}
```

---

## Settings

**Function:** `setting{ ... }` or `dmhub.RegisterSetting(info)`

Registers a configurable setting that appears in the settings UI.

**Parameters:**
- `id` (string) — unique identifier
- `description` (string) — display label
- `editor` (string) — UI type: `"check"`, `"slider"`, `"dropdown"`
- `default` (any) — default value
- `storage` (string) — `"game"` (shared) or `"preference"` (per-user)
- `section` (string) — settings section to display in
- `classes` (string[], optional) — e.g., `{"dmonly"}` for GM-only settings

```lua
-- Source: DMHub Token UI/TokenUIConfig.lua
local woundedIconSetting = setting{
    id = "showwoundedicon",
    description = "Show wounded icon",
    editor = "check",
    default = true,
    storage = "game",
    section = "game",
    classes = {"dmonly"},
}

-- Read the value:
local showIcon = woundedIconSetting:Get()

-- Dropdown setting:
local displayMode = setting{
    id = "enemystambardisplay",
    description = "Display mode for enemy stamina bars",
    editor = "dropdown",
    default = "none",
    storage = "game",
    section = "game",
    classes = {"dmonly"},
    enum = {
        { value = "none", text = "None (do not show)" },
        { value = "bar", text = "Bar only" },
        { value = "pct", text = "Bar & percentage" },
        { value = "val", text = "Bar & stamina value" },
    }
}
```

---

## Event Handlers

**Function:** `dmhub.RegisterEventHandler(eventName, fn)`

Registers a global event handler. Returns a GUID you can pass to `DeregisterEventHandler` to stop listening.

```lua
local handlerId = dmhub.RegisterEventHandler("tokenMoved", function(token)
    print("Token moved:", token.name)
end)

-- Later, to stop listening:
dmhub.DeregisterEventHandler(handlerId)
```

To fire your own global events:

```lua
dmhub.FireGlobalEvent("myCustomEvent", { data = "hello" })
```

---

## Remote Events (Network)

**Function:** `dmhub.RegisterRemoteEvent(eventid, callback)`
**Function:** `dmhub.BroadcastRemoteEvent(eventid, sessionid, args)`

Send events between connected clients.

```lua
-- Listen for a remote event:
dmhub.RegisterRemoteEvent("myModSync", function(senderid, args)
    print("Received from", senderid, ":", args)
end)

-- Broadcast to all clients:
dmhub.BroadcastRemoteEvent("myModSync", nil, { state = "updated" })
```

---

## Ability Keywords

**Function:** `GameSystem.RegisterAbilityKeyword(name)`

Registers a keyword that can be applied to abilities for categorization and filtering.

```lua
-- Source: Draw Steel Core Rules/MCDMRules.lua (pattern)
GameSystem.RegisterAbilityKeyword("Animal")
GameSystem.RegisterAbilityKeyword("Strike")
GameSystem.RegisterAbilityKeyword("Magic")
```

---

## Ability Categorization

**Function:** `GameSystem.RegisterAbilityCategorization(args)`

Registers a category for organizing abilities in the UI.

```lua
GameSystem.RegisterAbilityCategorization{
    category = "Heroic Ability",
    grouping = "Heroic Abilities",
}
```

---

## GUI Themes

**Function:** `gui.RegisterTheme(themeid, sectionid, styles)`

Registers a visual theme that can be applied to the UI.

```lua
gui.RegisterTheme("darkMode", "panels", {
    gui.Style{
        selectors = {"panel-bg"},
        bgcolor = "#1a1a2e",
        color = "white",
    },
})
```

---

## Summary Table

| What | Function | Defined In |
|---|---|---|
| Chat command | `Commands.name = function(str)` | Any module file |
| Game type (serializable class) | `RegisterGameType(name)` | Any module file |
| Ability behavior | `ActivatedAbility.RegisterType{...}` | `DMHub Game Rules/ActivatedAbility.lua` |
| Character modifier | `CharacterModifier.RegisterType(id, text)` | `DMHub Game Rules/CharacterModifier.lua` |
| Dockable panel | `DockablePanel.Register{...}` | `DMHub Core UI/DockablePanel.lua` |
| Token icon | `TokenUI.RegisterIcon{...}` | `DMHub Token UI/TokenUI.lua` |
| Token status bar | `TokenUI.RegisterStatusBar{...}` | `DMHub Token UI/TokenUI.lua` |
| Token HUD panel | `TokenHud.RegisterPanel{...}` | `DMHub Token UI/TokenUI.lua` |
| Setting | `setting{...}` | Any module file |
| Global event handler | `dmhub.RegisterEventHandler(name, fn)` | Any module file |
| Remote event | `dmhub.RegisterRemoteEvent(id, fn)` | Any module file |
| Ability keyword | `GameSystem.RegisterAbilityKeyword(name)` | Any module file |
| Ability category | `GameSystem.RegisterAbilityCategorization{...}` | Any module file |
| GUI theme | `gui.RegisterTheme(id, section, styles)` | Any module file |
