local mod = dmhub.GetModLoading()

--[[
    ============================================================================
    Modifier Picker Modal
    ============================================================================
    Search-first, keyboard-first modal for adding modifiers to a
    CharacterFeature. Replaces the classic alphabetical dropdown with a
    categorized, searchable picker parallel to the Behavior Picker. Opened by
    CharacterFeature:EditorPanel's "+ Add Modifier" button.

    Public entry point: AbilityEditor.OpenModifierPicker(feature, onAdd).
    Trusts the live CharacterModifier.Types list so Draw Steel's
    DeregisterType strips at MCDMRules.lua:1250-1260 are honored automatically.

    Clipboard-paste is surfaced as a pinned action at the top of the modal
    (not a listed modifier) so it never collides with search results.
]]

local COLORS = AbilityEditor.COLORS

-- ============================================================================
-- Per-type metadata: description, search tags, category group, optional
-- sortOrder for the Common band. Types not listed here fall through to a
-- generic entry in the "other" group so a future RegisterType shows up
-- without code changes. Categorization per MODIFIER_PICKER_CATEGORIES.md.
-- ============================================================================
local MODIFIER_METADATA = {
    -- Common (priority-sorted; lower sortOrder = shown first)
    power = {
        description = "Add custom options or tier effects to a power roll table.",
        tags = {"power", "roll", "tier", "option", "effect"},
        group = "common",
        sortOrder = 1,
    },
    activated = {
        description = "Grant an activated ability the bearer can use.",
        tags = {"ability", "action", "active", "grant"},
        group = "common",
        sortOrder = 2,
    },
    trigger = {
        description = "Grant a triggered ability that fires on specific events.",
        tags = {"trigger", "reaction", "event", "fire", "triggered"},
        group = "common",
        sortOrder = 3,
    },
    attribute = {
        description = "Adjust creature attributes.",
        tags = {"stat", "attribute", "bonus", "modify", "stamina", "speed"},
        group = "common",
        sortOrder = 4,
    },
    proficiency = {
        description = "Grant proficiency in a skill, language, save, or equipment group.",
        tags = {"skill", "language", "save", "proficiency", "grant", "equipment"},
        group = "common",
        sortOrder = 5,
    },
    bestowcondition = {
        description = "Automatically apply a condition to the bearer.",
        tags = {"condition", "status", "apply", "bestow"},
        group = "common",
        sortOrder = 6,
    },
    abilityimprovement = {
        description = "Improve an ability (e.g. increase target count, range or radius).",
        tags = {"improve", "enhance", "upgrade", "boost", "ability"},
        group = "common",
        sortOrder = 7,
    },

    -- Abilities & Triggers
    filter = {
        description = "Run a GoblinScript predicate to gate who the bearer can target.",
        tags = {"filter", "target", "predicate", "exclude", "restrict"},
        group = "abilities",
    },
    modifyability = {
        description = "Modify existing activated abilities on the bearer.",
        tags = {"modify", "ability", "change", "adjust"},
        group = "abilities",
    },
    modifytrigger = {
        description = "Modify an existing triggered ability.",
        tags = {"modify", "trigger", "reaction", "change"},
        group = "abilities",
    },
    powertabletrigger = {
        description = "Add a triggered effect on specific power roll tier results.",
        tags = {"power", "trigger", "tier", "roll", "effect"},
        group = "abilities",
    },
    powertableadditional = {
        description = "Add an additional option to an existing power roll trigger.",
        tags = {"power", "trigger", "option", "extend", "additional"},
        group = "abilities",
    },
    routine = {
        description = "Display a read-only routine for reference.",
        tags = {"routine", "reference", "display", "summon"},
        group = "abilities",
    },
    triggerdisplay = {
        description = "Display a read-only triggered ability for reference.",
        tags = {"trigger", "display", "reference", "readonly"},
        group = "abilities",
    },
    suppressabilities = {
        description = "Hide or disable specified abilities.",
        tags = {"suppress", "disable", "hide", "ability"},
        group = "abilities",
    },

    -- Defenses
    conditionimmunity = {
        description = "Grant immunity to specified conditions.",
        tags = {"immune", "condition", "resist", "prevent"},
        group = "defenses",
    },
    resistance = {
        description = "Grant immunity or resistance to damage types.",
        tags = {"immune", "resist", "damage", "reduce", "weakness"},
        group = "defenses",
    },

    -- Resources
    kitaccess = {
        description = "Grant access to additional kit types.",
        tags = {"kit", "access", "grant", "martial", "caster"},
        group = "resources",
    },
    resource = {
        description = "Grant a tracked resource (uses, charges, heroic-resource pool).",
        tags = {"resource", "uses", "charges", "heroic", "grant"},
        group = "resources",
    },
    growingresources = {
        description = "Provide a resource table that scales with level.",
        tags = {"resource", "scaling", "level", "growing", "table"},
        group = "resources",
    },
    modifyresourcechecklist = {
        description = "Customize the heroic-resource checklist display.",
        tags = {"checklist", "resource", "heroic", "display", "customize"},
        group = "resources",
    },

    -- Conditions & Auras
    aura = {
        description = "Project an aura affecting nearby creatures.",
        tags = {"aura", "zone", "area", "nearby", "emanation"},
        group = "conditions",
    },
    conditionsourcebestow = {
        description = "Apply a condition to creatures that damage the bearer.",
        tags = {"reciprocal", "condition", "damage", "retaliate", "counter"},
        group = "conditions",
    },
    invisibility = {
        description = "Make the bearer invisible to other creatures.",
        tags = {"invisible", "hidden", "unseen", "stealth"},
        group = "conditions",
    },

    -- Movement & Positioning
    castingorigin = {
        description = "Specify where the bearer's ability casts originate.",
        tags = {"cast", "origin", "position", "source"},
        group = "movement",
    },
    forcedmovement = {
        description = "Enable forced movement on the bearer.",
        tags = {"push", "pull", "slide", "forced", "move"},
        group = "movement",
    },
    suspended = {
        description = "Suspend the bearer at a specified altitude.",
        tags = {"fly", "hover", "suspend", "altitude", "air"},
        group = "movement",
    },

    -- Identity & Appearance
    alternateappearance = {
        description = "Present the bearer as a different visual form.",
        tags = {"appearance", "visual", "alternate", "disguise", "form"},
        group = "identity",
    },
    creaturetype = {
        description = "Change the bearer's creature-type classification.",
        tags = {"type", "creature", "undead", "construct", "classification"},
        group = "identity",
    },
    icon = {
        description = "Add a status icon or visual indicator to the bearer.",
        tags = {"icon", "status", "display", "indicator", "badge"},
        group = "identity",
    },
    transform = {
        description = "Allow the bearer to assume an alternate form.",
        tags = {"transform", "polymorph", "shape", "form"},
        group = "identity",
    },

    -- Narrative
    journalexplanation = {
        description = "Append explanatory text to journal entries.",
        tags = {"journal", "text", "explain", "narrative", "note"},
        group = "narrative",
    },
    light = {
        description = "Emit light from the bearer within a radius.",
        tags = {"light", "glow", "radius", "illuminate", "torch"},
        group = "narrative",
    },
    movementtext = {
        description = "Display reminder text when the bearer moves.",
        tags = {"reminder", "text", "movement", "hint", "note"},
        group = "narrative",
    },

    -- Monster Specific
    modrider = {
        description = "Modify mount-rider configurations.",
        tags = {"mount", "rider", "monster", "modify"},
        group = "monster",
    },
    modcaptain = {
        description = "Modify the captain role in a squad.",
        tags = {"captain", "squad", "monster", "modify"},
        group = "monster",
    },
}

local MODIFIER_GROUPS = {
    {id = "common",     label = "Common"},
    {id = "abilities",  label = "Abilities & Triggers"},
    {id = "defenses",   label = "Defenses"},
    {id = "resources",  label = "Resources"},
    {id = "conditions", label = "Conditions & Auras"},
    {id = "movement",   label = "Movement & Positioning"},
    {id = "identity",   label = "Identity & Appearance"},
    {id = "narrative",  label = "Narrative"},
    {id = "monster",    label = "Monster Specific"},
    {id = "other",      label = "Other"},
}

local SUGGESTED_CHIPS = {
    "grant an ability",
    "bestow a condition",
    "immunity",
    "resource",
    "aura",
    "power roll",
}

-- IDs to exclude from the picker. "none" is the placeholder at index 1 of
-- CharacterModifier.Types (shown as "Add Modifier..." in the old dropdown).
local EXCLUDED_IDS = {
    none = true,
}

-- ============================================================================
-- Search / filter
-- ============================================================================
local function _filterTypes(query, types)
    local results = {}
    for _, typeEntry in ipairs(types) do
        if not EXCLUDED_IDS[typeEntry.id] then
            local meta = MODIFIER_METADATA[typeEntry.id]
                or {description = typeEntry.text, tags = {}, group = "other"}

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
    -- Common band uses sortOrder; other bands sort alphabetically by display name.
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
function AbilityEditor.OpenModifierPicker(feature, onAdd)
    local types = DeepCopy(CharacterModifier.Types)

    local function onSelect(typeId)
        gui.CloseModal()
        if typeId ~= "CLIPBOARD" then
            AbilityEditor._trackRecentModifier(typeId)
        end
        onAdd(typeId)
    end

    -- Forward-declare so search input and results panel can reference each other.
    local searchInput
    local resultsPanel

    searchInput = gui.Input{
        width = "100%",
        height = 30,
        placeholderText = "Search modifiers...",
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

            -- Recently-used band (only when search is empty).
            if query == nil and #AbilityEditor._recentModifiers > 0 then
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
                for _, recentId in ipairs(AbilityEditor._recentModifiers) do
                    local typeEntry = CharacterModifier.TypesById[recentId]
                    if typeEntry ~= nil and not EXCLUDED_IDS[recentId] then
                        local meta = MODIFIER_METADATA[recentId]
                            or {description = typeEntry.text, tags = {}, group = "other"}
                        children[#children + 1] = _makeResultCard(typeEntry, meta, onSelect)
                    end
                end
                -- Divider after recently-used.
                children[#children + 1] = gui.Panel{
                    width = "100%",
                    height = 1,
                    bgimage = "panels/square.png",
                    bgcolor = COLORS.GOLD .. "66",
                    vmargin = 8,
                }
            end

            -- Suggested-query chips (when empty search, no recent).
            if query == nil and #AbilityEditor._recentModifiers == 0 then
                local chipChildren = {}
                for _, chipText in ipairs(SUGGESTED_CHIPS) do
                    local ct = chipText
                    chipChildren[#chipChildren + 1] = gui.Panel{
                        width = "auto",
                        height = 22,
                        flow = "horizontal",
                        halign = "left",
                        valign = "center",
                        hpad = 8,
                        rmargin = 6,
                        bmargin = 4,
                        bgcolor = COLORS.PANEL_BG,
                        borderWidth = 1,
                        borderColor = COLORS.GOLD,
                        cornerRadius = 11,
                        borderBox = true,
                        press = function()
                            searchInput.text = ct
                            resultsPanel:FireEvent("updateResults")
                        end,
                        gui.Label{
                            width = "auto",
                            height = "auto",
                            fontSize = 12,
                            color = COLORS.CREAM_BRIGHT,
                            textAlignment = "left",
                            text = ct,
                        },
                    }
                end
                children[#children + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    wrap = true,
                    halign = "left",
                    valign = "top",
                    bmargin = 8,
                    bgcolor = "clear",
                    children = chipChildren,
                }
            end

            -- Filtered + grouped results.
            local filtered = _filterTypes(query, types)

            for _, groupDef in ipairs(MODIFIER_GROUPS) do
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

            -- Empty state.
            if #filtered == 0 and query ~= nil then
                children[#children + 1] = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 14,
                    italics = true,
                    color = COLORS.GRAY,
                    textAlignment = "center",
                    vmargin = 24,
                    text = "No modifiers match \"" .. rawQuery .. "\"",
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
                        text = "Add Modifier",
                    },
                },
            },

            searchInput,
            resultsPanel,

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
