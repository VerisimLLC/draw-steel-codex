# Common Modding Patterns

Worked examples for common modding tasks, sourced from real code in the codebase.

---

## 1. Modifying Token Properties

All changes to a token's game state **must** go through `ModifyProperties`. This ensures changes are networked, undo-able, and batched correctly.

```lua
local token = dmhub.GetTokenById(charid)

token:ModifyProperties{
    description = "Apply Ongoing Effect",
    undoable = true,       -- allow Ctrl+Z
    combine = true,        -- batch with adjacent changes
    execute = function()
        token.properties:ApplyOngoingEffect(effectid, "eoe")
    end,
}
```

Batch across multiple tokens:

```lua
for _, charid in ipairs(dmhub.GetSelectedCharacters()) do
    local token = dmhub.GetTokenById(charid)
    if token then
        token:ModifyProperties{
            description = "Resize token",
            execute = function()
                token.properties:SetSizeOverride(sizeid)
            end,
        }
    end
end
```

---

## 2. Applying Conditions and Ongoing Effects

Effects are stored in the `characterOngoingEffects` table. Apply them to a creature via its properties:

```lua
-- Apply with default duration
token.properties:ApplyOngoingEffect(effectid)

-- Apply until end of encounter
token.properties:ApplyOngoingEffect(effectid, "eoe")

-- Apply with stacks
token.properties:ApplyOngoingEffect(effectid, "eoe", casterToken, {
    stacks = 3,
})
```

Creating a new effect programmatically:

```lua
local effect = {
    id = dmhub.GenerateGuid(),
    name = "Burning",
    description = "Takes fire damage each round",
    modifiers = {},       -- list of CharacterModifier objects
    condition = nil,      -- optional condition ID
}

dmhub.SetAndUploadTableItem("characterOngoingEffects", effect)
```

---

## 3. Creating a Custom Ability Behavior

Register a new type that appears in the ability editor:

```lua
-- Register the type
ActivatedAbility.RegisterType{
    id = 'mydamage',
    text = 'Custom Damage',
    canHaveDC = true,
    createBehavior = function()
        return MyDamageBehavior.new{
            roll = "1d6",
        }
    end,
}

-- Define the behavior class
MyDamageBehavior = RegisterGameType("MyDamageBehavior")

-- Summary shown in the ability editor
function MyDamageBehavior:SummarizeBehavior(ability, creatureLookup)
    return string.format("%s Damage",
        dmhub.NormalizeRoll(
            dmhub.EvalGoblinScript(self.roll, creatureLookup, "Damage roll")
        )
    )
end

-- Cast logic (called when the ability is used)
function MyDamageBehavior:Cast(ability, casterToken, targets, options)
    local symbols = DeepCopy(options.symbols or {})

    for _, target in ipairs(targets) do
        if target.token then
            symbols.target = target.token.properties:LookupSymbol()
        end

        local rollStr = dmhub.EvalGoblinScript(self.roll, symbols, "damage")
        -- Apply damage to target...
    end
end
```

---

## 4. Building Form Layouts

The standard form pattern uses horizontal panels with a label and an input:

```lua
gui.Panel{
    flow = "vertical",
    width = "auto",
    height = "auto",

    -- A single form row
    gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 2,

        gui.Label{
            text = "Name:",
            width = 240,
            fontSize = 18,
            textAlignment = "left",
        },

        gui.Input{
            text = currentName,
            width = 200,
            height = 26,
            fontSize = 18,
            change = function(element)
                currentName = trim(element.text)
                UploadChanges()
            end,
        },
    },

    -- A dropdown row
    gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",

        gui.Label{
            text = "Attribute:",
            width = 240,
        },

        gui.Dropdown{
            options = attributeOptions,
            idChosen = selectedAttribute,
            change = function(element)
                selectedAttribute = element.idChosen
                UploadChanges()
            end,
        },
    },
}
```

---

## 5. Styling with Classes

Use `gui.Style` blocks to define CSS-like rules, then apply `classes` to panels:

```lua
local styles = {
    gui.Style{
        selectors = {"form-row"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 2,
    },
    gui.Style{
        selectors = {"form-label"},
        width = 240,
        textAlignment = "left",
        color = "white",
        fontSize = 18,
    },
    gui.Style{
        selectors = {"form-input"},
        width = 200,
        height = 26,
        fontSize = 18,
        borderWidth = 1,
        borderColor = "white",
    },
    -- Pseudo-class for hover
    gui.Style{
        selectors = {"form-input", "hover"},
        brightness = 1.2,
    },
}

-- Apply
gui.Panel{
    styles = styles,

    gui.Panel{
        classes = {"form-row"},
        gui.Label{ classes = {"form-label"}, text = "Name:" },
        gui.Input{ classes = {"form-input"}, text = "" },
    },
}
```

Toggle classes dynamically:

```lua
panel:SetClass("selected", true)
panel:AddClass("active")
panel:RemoveClass("active")
panel:PulseClass("flash")   -- briefly add then remove (for animations)
```

---

## 6. Data Persistence: Edit → Upload

The standard pattern for editing game data:

```lua
local function CreateEditor(itemId)
    local table = dmhub.GetTable("myDataTable")
    local item = table[itemId]
    local originalJson = dmhub.ToJson(item)  -- snapshot for change detection

    local function Upload()
        dmhub.SetAndUploadTableItem("myDataTable", item)
    end

    return gui.Panel{
        flow = "vertical",

        gui.Input{
            text = item.name,
            change = function(element)
                item.name = trim(element.text)
                Upload()
            end,
        },

        -- Save on destroy if anything changed
        destroy = function(element)
            if dmhub.ToJson(item) ~= originalJson then
                Upload()
            end
        end,
    }
end
```

---

## 7. Monitoring External Changes

Use `monitorGame` to react when data changes from another client:

```lua
gui.Panel{
    monitorGame = "/path/to/data",

    create = function(element)
        -- Initial load
        RefreshDisplay(element)
    end,

    __onMonitorChange__ = function(element, monitor)
        -- Another client changed the data
        element:FireEventTree("refresh")
    end,

    events = {
        refresh = function(element)
            RefreshDisplay(element)
        end,
    },
}
```

---

## 8. Event-Driven UI Communication

### Fire down the tree

```lua
parentPanel:FireEventTree("refresh")
```

Every descendant panel with a `refresh` handler will be called.

### Fire up to parents

```lua
childPanel:FireEventOnParents("selectionChanged", selectedItem)
```

### Fire on a single panel

```lua
panel:FireEvent("customEvent", arg1, arg2)
```

### Delayed events

```lua
panel:ScheduleEvent("expire", 2.0)  -- fires "expire" after 2 seconds
```

### Pattern: Controller + Children

```lua
-- Controller (parent)
local controller = gui.Panel{
    events = {
        selectionChanged = function(element, item)
            -- Update state
            currentItem = item
            -- Propagate to children
            element:FireEventTree("refreshItem", item)
        end,
    },
}

-- Child
local detail = gui.Panel{
    events = {
        refreshItem = function(element, item)
            element:Get("nameLabel").text = item.name
        end,
    },
}
```

---

## 9. Coroutines for Animations

Use `dmhub.Coroutine` for multi-step timed sequences:

```lua
dmhub.Coroutine(function()
    panel:SetClassTree("shine", true)
    coroutine.yield(0.8)   -- wait 0.8 seconds

    panel:SetClassTree("finishing", true)
    coroutine.yield(0.5)

    panel:DestroySelf()
end)
```

### Periodic updates with `thinkTime`

```lua
gui.Panel{
    thinkTime = 0.01,  -- called every 10ms
    think = function(self)
        local doc = mod:GetDocumentSnapshot("drawsteel")
        if doc.data.finished then
            self.thinkTime = nil  -- stop thinking
            -- do final action
        end
    end,
}
```

---

## 10. Inter-Module Communication

### Export a public API via `mod.shared`

```lua
-- In your module:
local mod = dmhub.GetModLoading()

mod.shared.MyPublicFunction = function(arg)
    return doSomething(arg)
end
```

### Consume another module's API

```lua
local otherMod = dmhub.GetMod("OtherModName")
local result = otherMod.shared.MyPublicFunction("hello")
```

---

## 11. Custom Roll Workflows

### Define a roll check

```lua
local rollRequest = RollRequest.new{
    contest = false,
    checks = {
        RollCheck.new{
            type = "test_power_roll",
            id = "might",
            text = "Might",
            explanation = "Power Roll for your ability",
            options = {
                casterid = casterToken.charid,
                skills = {skillId},
            },
            modifiers = modifierList,
        },
    },
    tokens = {
        [tokenid] = {
            outcome = nil,
            result = nil,
        },
    },
}
```

### Register a custom roll type

```lua
RollCheck.RegisterCustom{
    id = "my_custom_roll",
    Describe = function(check, isPlayer)
        return "My Custom Roll"
    end,
    GetRoll = function(check, creature)
        return "2d10"
    end,
}
```

### Evaluate roll formulas

```lua
local symbols = creature:LookupSymbol()
local formula = "1d20 + might modifier"
local result = ExecuteGoblinScript(formula, symbols, 0, "Attack roll")
local normalized = dmhub.NormalizeRoll(result)
```

---

## 12. Working with Data Tables

### Read entries

```lua
-- All entries (includes hidden/deleted)
local classes = dmhub.GetTable("classes")

-- Only visible entries
local classes = dmhub.GetTableVisible("classes")

-- Search
local results = dmhub.SearchTable("spells", "fire", { fields = {"name"} })

-- All table type names
local types = dmhub.GetTableTypes()
```

### Create / update / delete

```lua
-- Upload (create or update)
dmhub.SetAndUploadTableItem("classes", modifiedClass)

-- Delete permanently
dmhub.ObliterateTableItem("classes", itemId)
```

### Build dropdown options from a table

```lua
local options = {}
local resourceTable = dmhub.GetTable("characterResources")
for k, resource in pairs(resourceTable) do
    if not resource:try_get("hidden", false) then
        options[#options+1] = {
            id = k,
            text = resource.name,
        }
    end
end

gui.Dropdown{
    options = options,
    idChosen = currentId,
    change = function(element)
        currentId = element.idChosen
    end,
}
```

---

## 13. Registering a Dockable Panel

```lua
DockablePanel.Register{
    name = "My Panel",
    icon = "icons/my-icon.png",
    minHeight = 140,
    vscroll = true,
    dmonly = false,
    content = function()
        return gui.Panel{
            flow = "vertical",
            width = "100%",

            gui.Label{ text = "Hello from my panel!", fontSize = 18 },
        }
    end,
    hasNewContent = function()
        return module.HasNovelContent("mypanel")
    end,
}
```

---

## 14. Working with Initiative

Access the initiative document via `mod:GetDocumentSnapshot`:

```lua
local doc = mod:GetDocumentSnapshot("drawsteel")

-- As the controller (GM), modify initiative state
if options.controller then
    doc:BeginChange()
    doc.data.guid = dmhub.GenerateGuid()
    doc.data.claims = {}
    doc.data.finished = nil
    doc:CompleteChange("Initialize initiative")
end
```

Check initiative state:

```lua
local queue = dmhub.initiativeQueue
if queue and not queue.hidden then
    -- Initiative is active
end
```

---

## 15. Spawning Tokens

```lua
-- Spawn from the bestiary
game.SpawnTokenFromBestiaryLocally(monsterId, loc, {
    fitLocation = true,
})

-- Remove tokens
game.UnsummonTokens({ tokenid1, tokenid2 })

-- Create a character
local charid = game.CreateCharacter("character", heroType)
```

---

## 16. Scheduling and Delays

```lua
-- Run after a delay
dmhub.Schedule(0.5, function()
    print("Half a second later")
end)

-- Wait for a condition to become true
dmhub.ScheduleWhen(
    function() return dmhub.initiativeQueue ~= nil end,
    function() print("Initiative started!") end
)

-- Coroutine with yields
dmhub.Coroutine(function()
    print("Step 1")
    coroutine.yield(1.0)
    print("Step 2")
    coroutine.yield(2.0)
    print("Step 3")
end)
```

---

## 17. Map Markers and Visuals

```lua
-- Highlight a radius on the map
local marker = dmhub.MarkRadius({
    radius = 3,
    color = "red",
    center = locs,
})
marker:Destroy()  -- remove when done

-- Highlight specific locations
local marker = dmhub.MarkLocs({
    color = "blue",
    locs = locList,
})

-- Calculate an AoE shape
local shape = dmhub.CalculateShape({
    shape = "circle",
    token = casterToken,
    radius = 5,
})

-- Screen shake
dmhub.ScreenShake(0.5, 1.0, 10, 0.5)
```

---

## 18. File I/O

```lua
-- Read a text file
local contents = dmhub.ReadTextFile("/path/to/file.txt", function(err)
    print("Error:", err)
end)

-- Write a text file
dmhub.WriteTextFile("directory", "filename.txt", "contents")

-- Parse JSON
local data = dmhub.ParseJsonFile("/path/to/file.json")

-- Open a file dialog
dmhub.OpenFileDialog({
    id = "importData",
    extensions = {"json", "txt"},
    open = function(path)
        local data = dmhub.ParseJsonFile(path)
        -- process data
    end,
})
```
