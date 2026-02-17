# Core API Reference

This is an annotated reference for the main APIs available to DMHub modders. Function signatures are sourced from the `Definitions/` directory; descriptions and examples are derived from actual usage in the codebase.

---

## `dmhub` — Engine Interface

The primary API. Provides access to tokens, dice, settings, events, data tables, scheduling, and more.

**Source:** `Definitions/dmhub.lua` (1439 lines)

### Properties

| Property | Type | Description |
|---|---|---|
| `dmhub.isDM` | `boolean` (read-only) | `true` if the current user is the GM |
| `dmhub.isGameOwner` | `boolean` (read-only) | `true` if the user owns the game |
| `dmhub.inGame` | `boolean` (read-only) | `true` if currently in a game session |
| `dmhub.userid` | `string` (read-only) | The current user's ID |
| `dmhub.serverTime` | `number` (read-only) | Server time in seconds (synced across clients) |
| `dmhub.allTokens` | `CharacterToken[]` (read-only) | All tokens on the current map |
| `dmhub.selectedTokens` | `CharacterToken[]` | Currently selected tokens |
| `dmhub.currentToken` | `CharacterToken\|nil` (read-only) | The token the player is presumably controlling |
| `dmhub.selectedOrPrimaryTokens` | `CharacterToken[]` (read-only) | Selected tokens, or the player's primary character |
| `dmhub.primaryCharacter` | `CharacterToken\|nil` (read-only) | The player's primary character (may be off-map) |
| `dmhub.tokenHovered` | `CharacterToken\|nil` (read-only) | Currently hovered token |
| `dmhub.initiativeQueue` | `InitiativeQueue\|nil` | The initiative queue (check `.hidden` for active state) |
| `dmhub.unitsPerSquare` | `number` (read-only) | Measurement units per grid square (typically 5) |
| `dmhub.version` | `string` | Engine version string |
| `dmhub.modKeys` | `{ctrl, alt, shift}` | Which modifier keys are held |
| `dmhub.users` | `string[]` (read-only) | All user IDs in the game |
| `dmhub.frozen` | `boolean` | Whether the game state is frozen |
| `dmhub.editorMode` | `boolean` (read-only) | `true` if user is in map editing mode |
| `dmhub.inCoroutine` | `boolean` | `true` if currently running in a coroutine |

### Module System

```lua
-- Get the current mod being loaded (call at top of every file)
local mod = dmhub.GetModLoading()  --> CodeModInterface
```

### Token & Character Queries

```lua
-- Get all tokens on the map
local tokens = dmhub.allTokens

-- Get tokens matching criteria
local heroes = dmhub.GetTokens({ playerControlled = true })
local nearby = dmhub.GetTokens({ position = { x = 5, y = 3, radius = 10 } })

-- Look up a specific token
local token = dmhub.GetTokenById(tokenid)       -- on current map only
local token = dmhub.GetCharacterById(tokenid)    -- anywhere in the game

-- Find a token from its properties (Creature object)
local token = dmhub.LookupToken(creature)

-- Get tokens at a map location
local tokens = dmhub.GetTokensAtLoc(loc)

-- Get all characters in a party
local ids = dmhub.GetCharacterIdsInParty(partyid)  --> string[]

-- Select / center on a token
dmhub.SelectToken(charid)
dmhub.CenterOnToken(tokenid, function() print("done") end)
```

### Data Tables

Game content (classes, abilities, conditions, items, etc.) is stored in named tables.

```lua
-- Get all entries in a table (includes hidden/deleted items)
local classes = dmhub.GetTable("classes")

-- Get only visible entries
local classes = dmhub.GetTableVisible("classes")

-- Search a table
local results = dmhub.SearchTable("spells", "fire", { fields = {"name"} })

-- Upload a modified item
dmhub.SetAndUploadTableItem("classes", modifiedClass)

-- Delete an item
dmhub.ObliterateTableItem("classes", itemId)

-- List all registered table types
local types = dmhub.GetTableTypes()  --> string[]
```

### Dice Rolling

```lua
-- Instant roll (no UI, returns number)
local result = dmhub.RollInstant("2d10+5", lookupFunction)

-- Instant roll with category breakdown
local results = dmhub.RollInstantCategorized("2d6+1d4")  --> { [""] = 12 }

-- Full roll with UI and animation
dmhub.Roll(rollDefinition)

-- Parse a roll string into components
local info = dmhub.ParseRoll("2d10+5", lookupFunction)

-- Normalize a roll into readable format
local text = dmhub.NormalizeRoll("2d10+5", nil, "Attack roll")

-- Get expected/min/max values
dmhub.RollExpectedValue("2d10")  --> 11
dmhub.RollMinValue("2d10")      --> 2
dmhub.RollMaxValue("2d10")      --> 20
```

### GoblinScript Evaluation

```lua
-- Evaluate a formula string to a number
local result = dmhub.EvalGoblinScriptDeterministic(
    "18 + (Level - 1)*6",
    lookupFunction,
    0,         -- default value on error
    "Stamina"  -- context message for debugging
)

-- Evaluate to a Lua object
local obj = dmhub.EvalGoblinScriptToObject("self.weapon", lookupFunction)

-- Evaluate with best-effort string reduction
local str = dmhub.EvalGoblinScript("1d6 + level", lookupFunction, "damage")
```

### Events

```lua
-- Register a global event handler
local id = dmhub.RegisterEventHandler("tokenMoved", function(token)
    print("Token moved:", token.name)
end)

-- Deregister
dmhub.DeregisterEventHandler(id)

-- Fire a global event
dmhub.FireGlobalEvent("myEvent", { data = "hello" })

-- Remote events (peer-to-peer, transient)
dmhub.RegisterRemoteEvent("mySync", function(senderid, args) ... end)
dmhub.BroadcastRemoteEvent("mySync", nil, { state = "updated" })
```

### Settings

```lua
-- Register a setting
dmhub.RegisterSetting({
    id = "mysetting",
    storage = "game",   -- "game" = shared, "preference" = per-user
    default = true,
})

-- Read / write settings
local val = dmhub.GetSettingValue("mysetting")
dmhub.SetSettingValue("mysetting", newValue)
dmhub.HasSetting("mysetting")  --> boolean
dmhub.ResetSetting("mysetting")
```

### Scheduling & Coroutines

```lua
-- Run a function after a delay
dmhub.Schedule(0.5, function()
    print("Half a second later")
end)

-- Wait for a condition
dmhub.ScheduleWhen(
    function() return dmhub.initiativeQueue ~= nil end,
    function() print("Initiative started!") end
)

-- Start a coroutine (can yield with coroutine.yield(seconds))
dmhub.Coroutine(function()
    print("Step 1")
    coroutine.yield(1.0)  -- wait 1 second
    print("Step 2")
end)
```

### Map & Visuals

```lua
-- Mark an area on the map (call :Destroy() to remove)
local marker = dmhub.MarkRadius({ radius = 3, color = "red", center = locs })
marker:Destroy()

-- Mark specific locations
local marker = dmhub.MarkLocs({ color = "blue", locs = locList })

-- Create a UI panel on the map
local canvas = dmhub.CreateCanvasOnMap({ point = vector3, sheet = panel })

-- Calculate a shape (for AoE targeting)
local shape = dmhub.CalculateShape({
    shape = "circle",
    token = casterToken,
    radius = 5,
})

-- Get cover info between two tokens
local cover = dmhub.GetCoverInfo(attacker, target)
-- cover.cover, cover.coverModifier, cover.description

-- Screen effects
dmhub.ScreenShake(0.5, 1.0, 10, 0.5)  -- duration, strength, vibrato, randomness
```

### File I/O

```lua
-- Read a text file
local contents = dmhub.ReadTextFile("/path/to/file.txt", function(err)
    print("Error:", err)
end)

-- Write a text file
dmhub.WriteTextFile("directory", "filename.txt", "contents")

-- Parse a JSON file
local data = dmhub.ParseJsonFile("/path/to/file.json")

-- Open a file dialog
dmhub.OpenFileDialog({
    id = "importData",
    extensions = {"json", "txt"},
    open = function(path)
        local data = dmhub.ParseJsonFile(path)
    end,
})
```

### Utilities

```lua
dmhub.GenerateGuid()           --> unique string
dmhub.DeepCopy(value)          --> deep clone
dmhub.DeepEqual(a, b)          --> boolean
dmhub.ToJson(value)            --> JSON string
dmhub.Time()                   --> seconds since app started
dmhub.Log("message")           --> log to local chat
dmhub.Debug("message")         --> log to debug console
dmhub.CopyToClipboard("text")  --> copy to system clipboard
dmhub.FormatTimestamp(ts)       --> formatted date string
dmhub.GetDisplayName(userid)   --> user's display name
dmhub.IsUserDM(userid)         --> boolean
dmhub.tr("translatable text")  --> translated string
```

---

## `gui` — UI Framework

Create panels, labels, inputs, and other UI elements.

**Source:** `Definitions/gui.lua`, `Definitions/Panel.lua`, `Definitions/gui-definitions.lua`

### Creating UI Elements

```lua
-- Basic panel (invisible container)
gui.Panel{
    width = 200,
    height = 100,
    flow = "vertical",   -- "horizontal" or "vertical"
    children = { ... },
}

-- Panel with background
gui.Panel{
    bgimage = true,  -- plain white square (style with bgcolor)
    width = "100%",
    height = 50,
    selfStyle = { bgcolor = "#1a1a2e" },
}

-- Label
gui.Label{
    text = "Hello World",
    fontSize = 18,
    bold = true,
    color = "white",
    width = "auto",
    height = "auto",
}

-- Text input
gui.Input{
    text = "default value",
    width = 200,
    height = 30,
    change = function(element)
        print("New value:", element.text)
    end,
}

-- Styled panel
gui.Style{
    selectors = {"my-class"},
    bgcolor = "#333333",
    color = "white",
    fontSize = 14,
}
```

### Panel Properties

| Property | Type | Description |
|---|---|---|
| `id` | `string` | Unique panel ID (auto-generated if not set) |
| `children` | `Panel[]` | Child panels |
| `parent` | `Panel` | Parent panel |
| `bgimage` | `string\|boolean` | Background image (`true` = white square) |
| `x`, `y` | `number` | Position offset in pixels |
| `width`, `height` | `number\|string` | Size (pixels or `"auto"`, `"100%"`) |
| `flow` | `string` | Child layout direction: `"horizontal"` or `"vertical"` |
| `classes` | `string[]` | CSS-like classes for styling |
| `data` | `table` | Arbitrary user data attached to the panel |
| `valid` | `boolean` (read-only) | `false` if the panel has been destroyed |
| `enabled` | `boolean` (read-only) | `true` if visible and active |
| `renderedWidth` | `number` (read-only) | Actual rendered width in pixels |
| `renderedHeight` | `number` (read-only) | Actual rendered height in pixels |
| `value` / `text` | `any` | Current value (for input controls) |
| `tooltip` | `string\|Panel` | Set a tooltip on hover |
| `popup` | `Panel\|nil` | Show a popup panel (persists until clicked away) |
| `interactable` | `boolean` | `false` to disable mouse interaction |
| `draggable` | `boolean` | Allow dragging |
| `dragTarget` | `boolean` | Accept dragged panels |
| `vscroll` / `hscroll` | `boolean` | Enable scrolling |
| `clip` | `boolean` | Clip children to panel bounds |
| `thinkTime` | `number\|nil` | Interval for `think` event (seconds) |
| `monitor` | `string\|string[]` | Setting IDs to watch for changes |
| `mapfocus` | `boolean` | Receive map interaction events |

### Panel Events

Set event handlers inline or via the `events` table:

```lua
gui.Panel{
    -- Inline event handlers
    create = function(element) ... end,        -- panel created
    click = function(element) ... end,         -- left click
    rightClick = function(element) ... end,    -- right click
    press = function(element) ... end,         -- mouse down
    hover = function(element) ... end,         -- mouse enters
    dehover = function(element) ... end,       -- mouse leaves
    change = function(element) ... end,        -- value changed (inputs)
    think = function(element) ... end,         -- periodic tick (set thinkTime)
    rendered = function(element) ... end,      -- after rendering
    destroy = function(element) ... end,       -- panel destroyed

    -- Or use events table
    events = {
        myCustomEvent = function(element, arg) ... end,
    },
}
```

### Panel Methods

```lua
panel:AddChild(childPanel)
panel:RemoveChild(childPanel)
panel:DestroySelf()
panel:Unparent()  -- must immediately reparent

-- Class manipulation
panel:HasClass("highlighted")
panel:SetClass("highlighted", true)
panel:AddClass("active")
panel:RemoveClass("active")
panel:PulseClass("flash")  -- briefly add then remove (for animations)

-- Events
panel:FireEvent("myEvent", arg)
panel:FireEventTree("refresh")           -- fire on self + all children
panel:FireEventOnParents("notify")       -- fire on parent chain
panel:ScheduleEvent("expire", 2.0)       -- fire after delay

-- Searching
panel:GetChildrenWithClass("item")
panel:GetChildrenWithClassRecursive("button")
panel:FindChildRecursive(function(p) return p.data.id == "target" end)
panel:Get("panelId")  -- find by ID in the hierarchy

-- Tree-wide class operations
panel:SetClassTree("disabled", true)
panel:AddClassTree("loading")
panel:PulseClassTree("highlight")

-- Interaction
panel:HaltEventPropagation()             -- stop press from bubbling
panel:MakeNonInteractiveRecursive()
```

---

## `chat` — Chat System

Send messages, custom panels, and share game data in chat.

**Source:** `Definitions/chat.lua`

```lua
-- Send a plain text message
chat.Send("Hello everyone!")

-- Send a custom rendered object (must be a RegisterGameType with .Render)
local guid = chat.SendCustom(myCustomMessage)

-- Update a previously sent custom message
chat.UpdateCustom(guid, updatedProperties)

-- Share a game object (spell, item, etc.) to chat
chat.ShareData(abilityData)

-- Share an object from a data table
chat.ShareObjectInfo("spells", spellId)

-- Clear the chat
chat.Clear()
```

---

## `game` — Game State

Manage maps, floors, characters, and tokens.

**Source:** `Definitions/game.lua`

```lua
-- Current state
game.currentMap         -- current map object
game.currentFloor       -- current floor object
game.currentFloorIndex  -- floor index number
game.maps               -- all maps

-- Map navigation
game.ChangeMap(map, floor)

-- Character management
local charid = game.CreateCharacter("character", heroType)
game.DeleteCharacters({ charid1, charid2 })
local char = game.GetCharacterById(id)
local allChars = game.GetGameGlobalCharacters()

-- Token interaction
local tokens = game.GetTokensAtLoc(loc)
game.SpawnTokenFromBestiaryLocally(monsterId, loc, { fitLocation = true })
game.UnsummonTokens({ tokenid1, tokenid2 })
game.UpdateCharacterTokens()

-- Floor check
game.FloorIsAboveGround(floorId)  --> boolean

-- Map creation
local mapId = game.CreateMap({ ... })
game.DuplicateMap(mapId, function() print("done") end)

-- Force refresh
game.Refresh()
```

---

## `CharacterToken` — Token on the Map

Represents a character or creature token placed on the map.

**Source:** `Definitions/CharacterToken.lua`

### Properties

| Property | Type | Description |
|---|---|---|
| `charid` | `string` (read-only) | Unique token ID |
| `name` | `string` | Token display name |
| `loc` | `Loc` | Current map location |
| `properties` | `Creature` | Game-specific data (stats, abilities, etc.) |
| `appearance` | `CharacterAppearance` | Visual appearance |
| `portrait` | `string` | Portrait image |
| `playerControlled` | `boolean` | Whether a player controls this token |
| `ownerId` | `string\|nil` | User ID of the owner |
| `creatureSize` | `string` | Size category |
| `locsOccupying` | `Loc[]` | All grid squares occupied |
| `hasTokenOnAnyMap` | `boolean` | Whether the token is placed on any map |
| `invisibleToPlayers` | `boolean` | Hidden from players |

### Modifying Token Properties

All changes to a token's game properties must go through `ModifyProperties`:

```lua
token:ModifyProperties{
    description = "Award Victories",
    undoable = true,      -- optional, allows undo
    combine = true,       -- optional, batch with similar changes
    execute = function()
        token.properties:SetVictories(token.properties:GetVictories() + 1)
    end,
}
```

---

## `module` — Module Management

Query and manage loaded modules.

**Source:** `Definitions/module.lua`

```lua
-- Get all loaded modules
local mods = module.GetLoadedModules()
local disabled = module.GetDisabledModules()

-- Get a specific module
local mod = module.GetModule(fullId)

-- Novel content tracking (for "new content" badges)
module.HasNovelContent("character", key)  --> boolean
local items = module.GetNovelContent("character")
module.RemoveNovelContent("character", id)
```

---

## Common Types

| Type | Description |
|---|---|
| `Loc` | Map grid location (`{x, y, floorIndex}`) |
| `Vector2` | 2D point (`{x, y}`) |
| `Vector3` | 3D point (`{x, y, z}`) |
| `Vector4` | Rectangle / bounds |
| `Color` | Color value (hex string like `"#ff0000"` or name like `"red"`) |
| `Panel` | UI panel element |
| `Creature` | Character game properties (stats, abilities, conditions) |
| `CharacterToken` | Token on the map |
| `Style` | UI styling object |

---

## Further Reference

The complete API stub files are in `Definitions/`:

| File | Lines | Content |
|---|---|---|
| `dmhub.lua` | 1439 | Full engine API |
| `gui.lua` | 111 | GUI creation functions |
| `Panel.lua` | 448 | Panel class (properties + methods) |
| `gui-definitions.lua` | — | Style and panel arg types |
| `game.lua` | 184 | Game state API |
| `chat.lua` | 74 | Chat API |
| `CharacterToken.lua` | 100+ | Token class |
| `module.lua` | 148 | Module system |
| `assets.lua` | 256 | Asset management |
| `import.lua` | 204 | Import system |
| `enums.lua` | — | Enumerations (AssetCategory, InputEvent, Easing, etc.) |
