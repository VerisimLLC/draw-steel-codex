local mod = dmhub.GetModLoading()

--[[
    ============================================================================
    Behavior Picker Modal
    ============================================================================
    Search-first, keyboard-first modal for adding behaviors to an ability.
    Replaces the classic alphabetical dropdown with a categorized, searchable
    picker. Opened by AbilityEditor._buildEffectsSection's "Add Behavior"
    button.
]]

local COLORS = AbilityEditor.COLORS

-- ============================================================================
-- Per-type metadata: description, search tags, category group.
-- Types not listed here get a fallback entry in the "scripting" group.
-- ============================================================================
local BEHAVIOR_METADATA = {
    -- Common
    temporary_effect = {
        description = "Apply damage or an effect for the ability's duration.",
        tags = {"damage", "hurt", "harm", "hit", "effect", "duration"},
        group = "conditions",
    },
    damage = {
        description = "Deal direct damage to targets.",
        tags = {"damage", "hurt", "harm", "hit", "attack"},
        group = "common",
        sortOrder = 2,
    },
    heal = {
        description = "Restore stamina to one or more targets.",
        tags = {"restore", "recovery", "hp", "stamina", "health"},
        group = "common",
        sortOrder = 4,
    },
    power_roll = {
        description = "Add a 2d10 power roll with tiered outcomes.",
        tags = {"roll", "dice", "2d10", "tier", "result"},
        group = "common",
        sortOrder = 1,
    },
    draw_steel_save = {
        description = "Force a target to make a resistance roll.",
        tags = {"save", "resist", "end", "condition"},
        group = "common",
        sortOrder = 3,
    },
    grant_temporary_stamina = {
        description = "Grant temporary stamina to targets.",
        tags = {"temp", "hp", "stamina", "shield", "buffer"},
        group = "common",
        sortOrder = 5,
    },
    ongoingEffect = {
        description = "Apply a persistent ongoing effect to targets.",
        tags = {"condition", "buff", "debuff", "status", "ongoing"},
        group = "conditions",
    },
    draw_steel_command = {
        description = "Apply an effect from the power table.",
        tags = {"command", "table", "power", "effect"},
        group = "common",
        sortOrder = 6,
    },
    replenish_resources = {
        description = "Restore or grant resources to targets.",
        tags = {"resource", "replenish", "restore", "gain", "mana"},
        group = "common",
        sortOrder = 7,
    },
    invoke_ability = {
        description = "Trigger another ability as part of this one.",
        tags = {"invoke", "trigger", "chain", "cast", "use"},
        group = "common",
        sortOrder = 8,
    },
    setstamina = {
        description = "Set a target's stamina to a specific value.",
        tags = {"stamina", "hp", "set", "override"},
        group = "modifiers",
    },

    -- Conditions & Effects
    purge_effects = {
        description = "Remove ongoing effects from targets.",
        tags = {"purge", "cleanse", "remove", "dispel", "effect"},
        group = "conditions",
    },
    condition_source = {
        description = "Set the source creature for a condition.",
        tags = {"condition", "source", "origin", "cause"},
        group = "conditions",
    },
    conditionriders = {
        description = "Attach additional conditions to an existing one.",
        tags = {"rider", "condition", "attach", "add", "stack"},
        group = "conditions",
    },

    -- Movement
    forcedmovementloc = {
        description = "Push, pull, or slide targets from a chosen origin.",
        tags = {"push", "pull", "slide", "move", "forced"},
        group = "movement",
    },
    manipulate_targets = {
        description = "Teleport or reposition targeted creatures.",
        tags = {"teleport", "swap", "reposition", "move"},
        group = "movement",
    },
    manipulate_target_locs = {
        description = "Manipulate remembered target locations.",
        tags = {"teleport", "location", "reposition"},
        group = "movement",
    },
    revertloc = {
        description = "Return targets to their previous locations.",
        tags = {"undo", "return", "snap back", "revert"},
        group = "movement",
    },
    fall = {
        description = "Cause targets to fall.",
        tags = {"drop", "gravity", "prone", "knockdown"},
        group = "movement",
    },
    change_movement_type = {
        description = "Change how a creature moves (fly, burrow, etc.).",
        tags = {"fly", "burrow", "swim", "walk", "speed", "movement"},
        group = "movement",
    },
    relocate_creature = {
        description = "Move a creature to a new location on the map.",
        tags = {"relocate", "move", "place", "teleport"},
        group = "movement",
    },
    change_initiative = {
        description = "Move creatures in the initiative order.",
        tags = {"initiative", "turn", "order", "combat"},
        group = "movement",
    },

    -- Creatures
    summon = {
        description = "Summon creatures onto the battlefield.",
        tags = {"summon", "spawn", "create", "creature", "minion"},
        group = "creatures",
    },
    summon_companion = {
        description = "Summon a companion creature.",
        tags = {"summon", "companion", "pet", "ally"},
        group = "creatures",
    },
    remove_creature = {
        description = "Remove a creature from the battlefield.",
        tags = {"remove", "banish", "dismiss", "creature"},
        group = "creatures",
    },
    transform = {
        description = "Transform creatures into a different form.",
        tags = {"transform", "polymorph", "shapeshift", "morph"},
        group = "creatures",
    },
    raise_corpse = {
        description = "Raise a defeated creature as an ally.",
        tags = {"undead", "raise", "corpse", "necromancy"},
        group = "creatures",
    },
    destroy = {
        description = "Destroy a creature or object.",
        tags = {"remove", "kill", "destroy", "eliminate"},
        group = "creatures",
    },

    -- Terrain & Objects
    create_object = {
        description = "Summon an object or terrain feature on the map.",
        tags = {"summon", "spawn", "object", "wall", "terrain"},
        group = "terrain",
    },
    terraform_elevation = {
        description = "Change the elevation of map squares.",
        tags = {"height", "raise", "lower", "elevation"},
        group = "terrain",
    },
    terraform_terrain = {
        description = "Change the terrain type of map squares.",
        tags = {"difficult", "hazardous", "terrain", "ground"},
        group = "terrain",
    },
    aura = {
        description = "Create a persistent aura around the caster.",
        tags = {"aura", "zone", "area", "persistent", "field"},
        group = "terrain",
    },
    create_item = {
        description = "Create an item and add it to inventory.",
        tags = {"item", "create", "craft", "loot"},
        group = "terrain",
    },

    -- Modifiers & Resources
    mod_power_roll = {
        description = "Add a bonus or penalty to a power roll.",
        tags = {"bonus", "penalty", "modifier", "edge", "bane"},
        group = "modifiers",
    },
    modify_cast = {
        description = "Modify how the ability is cast or targeted.",
        tags = {"cast", "override", "modify", "change"},
        group = "modifiers",
    },
    pay_ability_cost = {
        description = "Pay an additional resource cost.",
        tags = {"cost", "spend", "resource", "pay"},
        group = "modifiers",
    },
    recoverySelection = {
        description = "Allow target to spend or gain a recovery.",
        tags = {"recovery", "heal", "rest", "spend"},
        group = "modifiers",
    },
    persistenceControl = {
        description = "End or extend a persistent ability.",
        tags = {"persist", "end", "extend", "duration", "channel"},
        group = "modifiers",
    },
    limit = {
        description = "Limit how many times this ability can be used.",
        tags = {"limit", "uses", "count", "restrict", "charges"},
        group = "modifiers",
    },
    augmentedability = {
        description = "Turn this ability into a modifier for another.",
        tags = {"augment", "enhance", "modify", "combo"},
        group = "modifiers",
    },
    recast = {
        description = "Recast another ability as part of this one.",
        tags = {"recast", "chain", "combo", "follow-up"},
        group = "modifiers",
    },
    drop_items = {
        description = "Force targets to discard items.",
        tags = {"drop", "discard", "item", "disarm"},
        group = "modifiers",
    },

    -- Narrative
    character_speech = {
        description = "Display character speech or narration.",
        tags = {"talk", "say", "speech", "narrate", "text"},
        group = "narrative",
    },
    floattext = {
        description = "Show floating text above a creature.",
        tags = {"float", "text", "display", "label", "popup"},
        group = "narrative",
    },
    disguise = {
        description = "Change the visual appearance of a token.",
        tags = {"disguise", "illusion", "appearance", "polymorph"},
        group = "narrative",
    },
    play_sound = {
        description = "Play a sound effect.",
        tags = {"audio", "sfx", "sound", "music"},
        group = "narrative",
    },
    show_journal = {
        description = "Display a journal entry to the player.",
        tags = {"journal", "document", "show", "read", "note"},
        group = "narrative",
    },

    -- Scripting & Advanced
    Macro = {
        description = "Execute a Lua macro script.",
        tags = {"script", "lua", "code", "macro", "custom"},
        group = "scripting",
    },
    lua = {
        description = "Run arbitrary Lua code.",
        tags = {"script", "lua", "code", "custom", "execute"},
        group = "scripting",
    },
    rouitineControl = {
        description = "Control a summon's routine actions.",
        tags = {"routine", "summon", "minion", "control"},
        group = "scripting",
    },
    stealAbility = {
        description = "Copy or steal an ability from a target.",
        tags = {"steal", "copy", "mimic", "ability"},
        group = "scripting",
    },
    opposed = {
        description = "Initiate an opposed power roll contest.",
        tags = {"contest", "opposed", "versus", "vs"},
        group = "scripting",
    },
    remember = {
        description = "Store state for later use by other behaviors.",
        tags = {"store", "save", "state", "variable", "data"},
        group = "scripting",
    },
    customtrigger = {
        description = "Fire a custom event trigger.",
        tags = {"trigger", "event", "custom", "fire"},
        group = "scripting",
    },
    fizzle = {
        description = "Cancel or fizzle the current ability.",
        tags = {"cancel", "fizzle", "abort", "stop"},
        group = "scripting",
    },
    resetrollstatus = {
        description = "Reset the roll status of the ability.",
        tags = {"reset", "roll", "status", "clear"},
        group = "scripting",
    },
    roll = {
        description = "Roll dice and store the result.",
        tags = {"roll", "dice", "random", "d20"},
        group = "scripting",
    },
    table_roll = {
        description = "Roll on a random table.",
        tags = {"table", "roll", "random", "loot"},
        group = "scripting",
    },
    creature_set = {
        description = "Build a list of creatures for later use.",
        tags = {"creature", "list", "set", "group", "targets"},
        group = "scripting",
    },
    skill_check = {
        description = "Prompt a skill check from a creature.",
        tags = {"skill", "check", "test", "ability"},
        group = "scripting",
    },
    delay = {
        description = "Pause execution for a duration.",
        tags = {"delay", "wait", "pause", "timer"},
        group = "scripting",
    },
    ordertargets = {
        description = "Reorder the target list.",
        tags = {"order", "sort", "targets", "sequence"},
        group = "scripting",
    },
    debug_behavior = {
        description = "Debug output for development.",
        tags = {"debug", "test", "dev", "log"},
        group = "scripting",
    },
}

local BEHAVIOR_GROUPS = {
    {id = "common",     label = "Common"},
    {id = "conditions", label = "Conditions & Effects"},
    {id = "movement",   label = "Movement"},
    {id = "creatures",  label = "Creatures"},
    {id = "terrain",    label = "Terrain & Objects"},
    {id = "modifiers",  label = "Modifiers & Resources"},
    {id = "narrative",  label = "Narrative"},
    {id = "scripting",  label = "Scripting & Advanced"},
}

-- IDs to exclude from the picker. Shapes are internal, "none" is a
-- placeholder entry at index 1 of ActivatedAbility.Types.
local EXCLUDED_IDS = {
    sphere = true, cylinder = true, cone = true,
    none = true,
}

-- ============================================================================
-- Search / filter
-- ============================================================================
local function _filterTypes(query, types)
    local results = {}
    for _, typeEntry in ipairs(types) do
        if typeEntry.hidden or EXCLUDED_IDS[typeEntry.id] then
            -- skip
        else
            local meta = BEHAVIOR_METADATA[typeEntry.id]
                or {description = typeEntry.text, tags = {}, group = "scripting"}

            local match = true
            if query ~= nil and query ~= "" then
                match = false
                local q = string.lower(query)
                if string.find(string.lower(typeEntry.text), q, 1, true) then
                    match = true
                elseif string.find(string.lower(typeEntry.id), q, 1, true) then
                    match = true
                elseif string.find(string.lower(meta.description), q, 1, true) then
                    match = true
                else
                    for _, tag in ipairs(meta.tags) do
                        if string.find(string.lower(tag), q, 1, true) then
                            match = true
                            break
                        end
                    end
                end
            end

            if match then
                results[#results + 1] = {typeEntry = typeEntry, meta = meta}
            end
        end
    end
    return results
end

-- ============================================================================
-- Card + group rendering
-- ============================================================================
local function _makeResultCard(typeEntry, meta, onSelect)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 10,
        vpad = 6,
        bmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 3,
        borderBox = true,

        press = function()
            onSelect(typeEntry.id)
        end,

        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            text = typeEntry.text,
        },
        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 12,
            italics = true,
            color = COLORS.GRAY,
            textAlignment = "left",
            text = meta.description,
        },
    }
end

local function _buildGroupPanel(groupDef, entries, onSelect)
    -- Sort entries: Common group uses sortOrder for priority ordering,
    -- all other groups sort alphabetically by display name.
    if groupDef.id == "common" then
        table.sort(entries, function(a, b)
            local sa = a.meta.sortOrder or 99
            local sb = b.meta.sortOrder or 99
            if sa ~= sb then return sa < sb end
            return a.typeEntry.text < b.typeEntry.text
        end)
    else
        table.sort(entries, function(a, b)
            return a.typeEntry.text < b.typeEntry.text
        end)
    end

    local cards = {}
    for _, entry in ipairs(entries) do
        cards[#cards + 1] = _makeResultCard(entry.typeEntry, entry.meta, onSelect)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bmargin = 12,
        bgcolor = "clear",
        children = {
            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 16,
                bold = true,
                color = COLORS.GOLD_DIM,
                textAlignment = "left",
                bmargin = 4,
                text = groupDef.label,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                bgcolor = "clear",
                children = cards,
            },
        },
    }
end

-- ============================================================================
-- Public API
-- ============================================================================
function AbilityEditor.OpenBehaviorPicker(ability, onAdd)
    -- Read the type list via the instance so TriggeredAbility (which has its
    -- own Types with the extra "momentary" entry; see TriggeredAbility.lua:90)
    -- reaches the picker. ActivatedAbility callers still resolve to the base
    -- list via inheritance.
    local types = {}
    local excludeMono = #(ability.behaviors or {}) > 0
    for _, t in ipairs(ability.Types) do
        if not excludeMono or not t.mono then
            types[#types + 1] = DeepCopy(t)
        end
    end

    -- Selection callback: close modal and pass the type ID back.
    local function onSelect(typeId)
        gui.CloseModal()
        onAdd(typeId)
    end

    -- Forward-declare so the search input and results panel can reference
    -- each other.
    local searchInput
    local resultsPanel

    searchInput = gui.Input{
        width = "100%",
        height = 30,
        placeholderText = "Search behaviors...",
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 3,
        hpad = 8,
        vpad = 4,
        borderBox = true,
        fontSize = 14,
        color = COLORS.CREAM_BRIGHT,
        bmargin = 8,
        textAlignment = "left",

        editlag = 0.15,
        edit = function(element)
            resultsPanel:FireEvent("updateResults")
        end,
        create = function(element)
            element.hasFocus = true
        end,
    }

    resultsPanel = gui.Panel{
        width = "100%",
        height = "100%-80",
        flow = "vertical",
        vscroll = true,
        bgcolor = "clear",
        halign = "left",
        valign = "top",

        create = function(element)
            element:FireEvent("updateResults")
        end,

        updateResults = function(element)
            local rawQuery = searchInput.text or ""
            -- Note: `(x == "") and nil or x` returns "" not nil when x is "",
            -- because Lua's `A and B or C` collapses to C when B is falsy.
            -- Use an explicit branch so empty search correctly yields nil.
            local query = rawQuery
            if query == "" then query = nil end

            local children = {}

            -- Recently-used band (when search is empty)
            if query == nil and #AbilityEditor._recentBehaviors > 0 then
                children[#children + 1] = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 16,
                    bold = true,
                    color = COLORS.GOLD_DIM,
                    textAlignment = "left",
                    bmargin = 4,
                    text = "Recently Used",
                }
                for _, recentId in ipairs(AbilityEditor._recentBehaviors) do
                    local typeEntry = ability.TypesById[recentId]
                    if typeEntry and not typeEntry.hidden then
                        local meta = BEHAVIOR_METADATA[recentId]
                            or {description = typeEntry.text, tags = {}, group = "scripting"}
                        children[#children + 1] = _makeResultCard(typeEntry, meta, onSelect)
                    end
                end
                -- Divider after recently-used
                children[#children + 1] = gui.Panel{
                    width = "100%",
                    height = 1,
                    bgimage = "panels/square.png",
                    bgcolor = COLORS.GOLD .. "66",
                    vmargin = 8,
                }
            end

            -- Filtered + grouped results
            local filtered = _filterTypes(query, types)

            for _, groupDef in ipairs(BEHAVIOR_GROUPS) do
                local groupEntries = {}
                for _, entry in ipairs(filtered) do
                    if entry.meta.group == groupDef.id then
                        groupEntries[#groupEntries + 1] = entry
                    end
                end
                if #groupEntries > 0 then
                    children[#children + 1] = _buildGroupPanel(groupDef, groupEntries, onSelect)
                end
            end

            -- Empty state
            if #filtered == 0 and query ~= nil then
                children[#children + 1] = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 14,
                    italics = true,
                    color = COLORS.GRAY,
                    textAlignment = "center",
                    vmargin = 24,
                    text = "No behaviors match \"" .. rawQuery .. "\"",
                }
            end

            element.children = children
        end,
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        styles = {Styles.Default, Styles.Panel},
        width = 600,
        height = 600,
        flow = "vertical",
        pad = 16,
        borderBox = true,
        halign = "center",
        valign = "center",
        fontFace = "Berling",

        children = {
            -- Title row
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                bmargin = 8,
                bgcolor = "clear",
                children = {
                    gui.Label{
                        width = "auto",
                        height = "auto",
                        fontSize = 20,
                        bold = true,
                        color = COLORS.GOLD_BRIGHT,
                        textAlignment = "left",
                        text = "Add Behavior",
                    },
                },
            },

            searchInput,
            resultsPanel,

            -- Close button
            gui.CloseButton{
                halign = "right",
                valign = "top",
                floating = true,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    gui.CloseModal()
                end,
            },
        },
    }

    gui.ShowModal(dialogPanel)
end
