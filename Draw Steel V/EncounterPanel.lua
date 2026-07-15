local mod = dmhub.GetModLoading()

--To go from a monsterid to an actual monster:
-- local monster = assets.monsters[monsterid]

--sample encounter
--encounter = {
--    groups = {
--        {
--            monsters = {
--
--                ["8e2c0f64-0b98-45a2-a7ea-6ff1eae6a5c4"] = 4,
--                ["2f4d8b2e-5f3e-4c60-a4c1-1e37f4ed37b6"] = 1,
--            },
--            --per-monster "appears at N+ heroes" gates.
--            monsterMinHeroes = {
--                ["8e2c0f64-0b98-45a2-a7ea-6ff1eae6a5c4"] = 5,
--            },
--        },
--        {
--            --legacy whole-group gate; the builder migrates this to
--            --monsterMinHeroes when the encounter is edited.
--            minHeroes = 3,
--            monsters = {
--                ["b7122d63-1ac3-4c4d-b7d5-82c5f1ea93d3"] = 1,
--            }
--        }
--    }
--}
--

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local CreateEncounterPanel

--Feature flag for the encounter builder. Registration happens at load, so a
--change takes effect on the next reload. Turning it off hides the panel; the
--Encounter type and any encounters already built stay exactly where they are.
local encounterBuilderSetting = setting{
    id = "encounterBuilder",
    description = "Encounter builder",
    help = "The Encounter creator panel: build encounters, cost them against the party's budget, and drop them into the journal. Takes effect after a reload.",
    storage = "preference",
    section = "general",
    default = true,
    editor = "check",
}

if encounterBuilderSetting:Get() then
    DockablePanel.Register {
        name = "Encounter creator",
        icon = "icons/standard/Icon_App_EncounterCreator.png",
        minHeight = 200,
        vscroll = true,
        content = function()
            track("panel_open", {
                panel = "Encounter creator",
                dailyLimit = 30,
            })
            return CreateEncounterPanel()
        end,
    }
end

--Encounter is defined in Draw Steel Core Rules/MCDMEncounter.lua (data + rules).
--We re-fetch the registered type here so the UI methods below can attach to it.
Encounter = RegisterGameType('Encounter')

EncounterFolder = RegisterGameType('EncounterFolder')

EncounterFolder.tableName = 'encounterfolders'

EncounterFolder.name = 'New Encounter Folder'

--Encounter data/rules methods (MainMonster, AdjustedMonsterQuantity,
--CloneForNumberOfHeroes, AddMonster, AddGroup, CountEDS, Describe,
--PartyStrength, DifficultyTier, DifficultyBands) live in
--Draw Steel Core Rules/MCDMEncounter.lua. The encounter-builder UI methods
--(Encounter.Editor / Encounter.CreateEditorDialog) remain below.

-- ===========================================================================
-- Monster role helpers
-- ===========================================================================

local function Capitalize(word)
    if word == nil or word == "" then
        return ""
    end
    return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
end

--Gather the builder-relevant facts about a bestiary entry. Reads defensively
--(try_get / IsMonster gates) since some compendium assets carry plain
--creature-typed properties.
--Returns { monsterid, name, ev, level, minion, org, role, portraitId, meta }
local function MonsterBuildInfo(monsterid, monsterAsset)
    local info = {
        monsterid = monsterid,
        name = creature.GetTokenDescription(monsterAsset),
        ev = 0,
        level = 0,
        minion = false,
        org = nil,
        role = nil,
    }

    if monsterAsset.appearance ~= nil then
        info.portraitId = monsterAsset.appearance.portraitId
    end

    --the engine's token view of the asset, used to render the portrait inside
    --its token frame (gui.CreateTokenImage), plus the asset itself for
    --implementation-status queries.
    info.token = monsterAsset.info
    info.asset = monsterAsset

    local props = monsterAsset.properties
    if props ~= nil then
        info.ev = props:EV()
        info.minion = props.minion
        if props:IsMonster() then
            info.level = props:Level()
        end

        local words = {}
        for word in string.gmatch(string.lower(props:try_get("role", "")), "%a+") do
            words[#words + 1] = word
        end
        info.org = words[1]
        info.role = words[#words]

        --weakest-link automation status across the monster's own kit (innate
        --abilities and traits). implementation levels: 0/1 = not implemented,
        --2 = bronze, 3 = silver, 4 = gold. Left nil when the kit carries no
        --implementation data at all.
        local worst = nil
        local breakdown = {}
        local function considerImplementation(list)
            for _, item in ipairs(list or {}) do
                local impl = item:try_get("implementation")
                if impl ~= nil then
                    if worst == nil or impl < worst then
                        worst = impl
                    end
                    breakdown[#breakdown + 1] = {
                        name = item.name,
                        implementation = impl,
                    }
                end
            end
        end
        pcall(function() considerImplementation(props:try_get("innateActivatedAbilities")) end)
        pcall(function() considerImplementation(props:try_get("characterFeatures")) end)
        info.implementation = worst
        info.implementationBreakdown = breakdown
    end

    local meta = ""
    if info.role ~= nil then
        meta = Capitalize(info.role)
    end
    meta = string.format("%s%sLvl %d", meta, cond(meta == "", "", " - "), info.level)
    if info.minion then
        meta = meta .. " - Minion"
    elseif info.org == "leader" then
        meta = meta .. " - Leader"
    elseif info.org == "solo" then
        meta = meta .. " - Solo"
    end
    info.meta = meta

    return info
end

--Names for the implementation levels used by gui.ImplementationStatusIcon.
local g_implementationNames = {
    [0] = "Not implemented",
    [1] = "Not implemented",
    [2] = "Bronze",
    [3] = "Silver",
    [4] = "Gold",
}

--Implementation level -> status modifier class (tinted via the scheme's
--@implStatus* tokens, matching the diamonds on rendered stat blocks).
local g_implementationClass = {
    [0] = "wontimplement",
    [1] = "unimplemented",
    [2] = "bronze",
    [3] = "silver",
    [4] = "gold",
}

--Tooltip text summarizing a monster's per-ability automation levels,
--weakest first.
local function ImplementationTooltip(info)
    if info.implementation == nil then
        return "No automation data."
    end
    local lines = {
        string.format("Automation: %s", g_implementationNames[info.implementation] or tostring(info.implementation)),
    }
    local sorted = {}
    for _, entry in ipairs(info.implementationBreakdown or {}) do
        sorted[#sorted + 1] = entry
    end
    table.sort(sorted, function(a, b)
        if a.implementation ~= b.implementation then
            return a.implementation < b.implementation
        end
        return a.name < b.name
    end)
    for _, entry in ipairs(sorted) do
        lines[#lines + 1] = string.format("%s: %s", entry.name, g_implementationNames[entry.implementation] or tostring(entry.implementation))
    end
    return table.concat(lines, "\n")
end

--The EV a single roster entry contributes, using the same minion math as
--Encounter.CountEDS (minions contribute a quarter of their EV each).
local function EntryEV(monsterAsset, quantity)
    local ev = monsterAsset.properties:EV() * quantity
    if monsterAsset.properties.minion then
        ev = round(ev / 4)
    end
    return ev
end

--The EV a group contributes for a given hero count: zero when the group's
--minHeroes gate excludes it, and per-monster balancing deltas applied.
local function AdjustedGroupEV(group, numHeroes)
    if group.minHeroes ~= nil and group.minHeroes > numHeroes then
        return 0
    end

    local total = 0
    for monsterid, quantity in pairs(group.monsters) do
        local monsterAsset = assets.monsters[monsterid]
        if monsterAsset ~= nil then
            local n = Encounter.AdjustedMonsterQuantity(group, monsterid, quantity, numHeroes)
            total = total + EntryEV(monsterAsset, n)
        end
    end
    return total
end

--The number of creatures a group actually places for a given hero count.
local function AdjustedGroupCount(group, numHeroes)
    if group.minHeroes ~= nil and group.minHeroes > numHeroes then
        return 0
    end

    local total = 0
    for monsterid, quantity in pairs(group.monsters) do
        total = total + Encounter.AdjustedMonsterQuantity(group, monsterid, quantity, numHeroes)
    end
    return total
end

--Display name for the group at the given index in the encounter ("Group A").
local function GroupDisplayName(index)
    if index <= 26 then
        return string.format("Group %s", string.char(64 + index))
    end
    return string.format("Group %d", index)
end

--The group's display name: the DM-given name when set (group.name).
--Otherwise reinforcement-wave groups default to their wave's name
--("Reinforcements") and start-of-encounter groups to the positional
--default ("Group A").
local function GroupName(encounter, group, index)
    local name = group.name
    if name ~= nil and name ~= "" then
        return name
    end
    if group.wave ~= nil then
        for _, wave in ipairs(encounter:try_get("waves", {})) do
            if wave.id == group.wave then
                return wave.name or "Reinforcements"
            end
        end
        return "Reinforcements"
    end
    return GroupDisplayName(index)
end

--Whether a group carries any balancing adjustments for any party size.
local function GroupHasBalancing(group)
    for _, entry in pairs(group.balancing or {}) do
        if type(entry) == "table" then
            if entry.stamina ~= nil or entry.disableSolo then
                return true
            end
            if next(entry.monsters or {}) ~= nil then
                return true
            end
        end
    end
    return false
end

--Tokens currently on the map carrying this group's placement tag (stamped
--when the group is placed from the builder), sorted by spawn slot so their
--positions bank back into group.spawnlocs in spawn order.
--Only STAGED tokens count: encounterStaged == true, or nil for tokens staged
--before the flag existed (real combat placements stamp an explicit false).
--Staging is also scoped to the Director who staged it (encounterStagedBy), so
--one Director collecting a group never deletes tokens a colleague is
--arranging; nil (legacy) tokens are treated as ours.
local function PlacedTokensForGroup(group)
    if group.placementid == nil then
        return {}
    end
    local result = {}
    for _, token in ipairs(dmhub.allTokens) do
        if token.properties ~= nil and token.properties:try_get("encounterPlacementId") == group.placementid then
            local staged = token.properties:try_get("encounterStaged")
            local stagedBy = token.properties:try_get("encounterStagedBy")
            if staged ~= false and (stagedBy == nil or stagedBy == dmhub.userid) then
                result[#result + 1] = token
            end
        end
    end
    table.sort(result, function(a, b)
        return a.properties:try_get("encounterSpawnSlot", 0) < b.properties:try_get("encounterSpawnSlot", 0)
    end)
    return result
end

--Bank one group's staged tokens into the group: positions (spawnlocs),
--player-visibility, and (when the encounter opts in) appearances, all in
--spawn-slot order. Also stamps the map the positions belong to -- spawnlocs
--are map-blind coordinates, so consumers must not use them on another map.
--Returns the banked tokens; the CALLER decides whether to delete them.
local function BankGroupPositions(group, saveAppearances)
    local tokens = PlacedTokensForGroup(group)
    if #tokens == 0 then
        return tokens
    end
    group.spawnlocs = {}
    group.appearances = {}
    group.invisibleToPlayers = {}
    group.stagemapid = game.currentMapId
    for slot, token in ipairs(tokens) do
        group.spawnlocs[slot] = token.loc
        group.invisibleToPlayers[slot] = token.invisibleToPlayers or false
        if saveAppearances and token.appearanceChangedFromBestiary then
            group.appearances[slot] = token:SerializeAppearanceToString()
        else
            group.appearances[slot] = false
        end
    end
    return tokens
end

--True when the group's saved positions were banked on a different map than
--the one currently open (nil stagemapid = legacy data, treated as matching).
local function GroupStagedOnOtherMap(group)
    local mapid = group.stagemapid
    return mapid ~= nil and mapid ~= game.currentMapId
end

--Spawn a group's monsters at its saved staging positions (group.spawnlocs),
--restoring saved appearances and player-visibility, and tag them with the
--group's placement id so the builder recognises them as staged. Slots that
--have no saved position are skipped. Returns the spawned tokens.
local function StageGroupAtSavedLocations(group, numHeroes, placementid)
    local tokens = {}
    local slot = 1
    for monsterid, quantity in pairs(group.monsters) do
        quantity = Encounter.AdjustedMonsterQuantity(group, monsterid, quantity, numHeroes)
        for i = 1, quantity do
            local loc = (group.spawnlocs or {})[slot]
            if loc ~= nil then
                if not loc.isValidFloor then
                    loc = loc.withCurrentFloor
                end
                local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true })
                if token ~= nil then
                    token.properties.encounterPlacementId = placementid
                    token.properties.encounterSpawnSlot = slot
                    token.properties.encounterStaged = true
                    token.properties.encounterStagedBy = dmhub.userid
                    local appearance = (group.appearances or {})[slot]
                    if type(appearance) == "string" then
                        token:SerializeAppearanceFromString(appearance)
                    end
                    if (group.invisibleToPlayers or {})[slot] then
                        token.invisibleToPlayers = true
                    end
                    token:UploadToken()
                    tokens[#tokens + 1] = token
                end
            end
            slot = slot + 1
        end
    end
    if #tokens > 0 then
        game.UpdateCharacterTokens()
    end
    return tokens
end

--Defined in the footer-actions section below; forward-declared because the
--group cards offer per-group staging.
local ShowPlacementBanner
local ShowStagingBanner

--The party the builder balances against. Heroes come from the numheroes
--setting; level and victories default from the hero tokens on the current
--map so the budget matches the real party, with manual override via the
--party bar steppers.
local function DefaultParty()
    local numHeroes = dmhub.GetSettingValue("numheroes") or 4

    local totalLevel = 0
    local totalVictories = 0
    local count = 0
    for _, tok in ipairs(dmhub.allTokens) do
        local props = tok.properties
        if props ~= nil and props:IsHero() then
            count = count + 1
            totalLevel = totalLevel + props:CharacterLevel()
            totalVictories = totalVictories + props:GetVictories()
        end
    end

    local level = 1
    local victories = 0
    if count > 0 then
        level = math.max(1, round(totalLevel / count))
        victories = math.max(0, round(totalVictories / count))
    end

    return {
        numHeroes = numHeroes,
        level = level,
        victories = victories,
    }
end

-- ===========================================================================
-- Builder theme extras
-- ===========================================================================

--Difficulty tier -> foreground utility class (for tier readouts). The ramp
--follows the scheme's heat order: gray, green, gold (Standard is the
--designed target), orange, red.
local g_tierColorClass = {
    Trivial = "fgMuted",
    Easy = "success",
    Standard = "info",
    Hard = "warning",
    Extreme = "danger",
}

--Difficulty tier -> meter fill variant class.
local g_tierFillClass = {
    Trivial = "tierTrivial",
    Easy = "tierEasy",
    Standard = "tierStandard",
    Hard = "tierHard",
    Extreme = "tierExtreme",
}

--Swap element to exactly one class out of a tier->class map.
local function SetExclusiveClass(element, classMap, chosen)
    for _, cls in pairs(classMap) do
        element:SetClass(cls, cls == classMap[chosen])
    end
end

--Builder-specific theme rules, resolved against the active scheme. These are
--panel-local extras (tier 2 of the ThemeEngine discipline): the selectors are
--only used inside the encounter builder.
local function BuilderStyles()
    return ThemeEngine.MergeStyles({
        {
            selectors = { "encounterBadge" },
            priority = 5,
            bgimage = true,
            bgcolor = "clear",
            borderWidth = 1,
            borderColor = "@border",
            color = "@fg",
            cornerRadius = 6,
            fontSize = 12,
            hpad = 6,
            vpad = 2,
        },
        {
            selectors = { "encounterDialRing" },
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "encounterDialCut" },
            bgimage = true,
            bgcolor = "@bg",
        },
        {
            selectors = { "encounterDialHub" },
            bgimage = true,
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "encounterDialTick" },
            bgimage = true,
            bgcolor = "@bg",
        },
        {
            selectors = { "encounterMeterFill" },
            bgimage = true,
            bgcolor = "@fgMuted",
            opacity = 0.75,
        },
        {
            selectors = { "encounterMeterFill", "tierEasy" },
            bgcolor = "@success",
        },
        {
            selectors = { "encounterMeterFill", "tierStandard" },
            bgcolor = "@info",
        },
        {
            selectors = { "encounterMeterFill", "tierHard" },
            bgcolor = "@warning",
        },
        {
            selectors = { "encounterMeterFill", "tierExtreme" },
            bgcolor = "@danger",
        },
        {
            selectors = { "encounterBadge", "success" },
            priority = 6,
            color = "@success",
            borderColor = "@success",
        },
        {
            selectors = { "encounterBadge", "warning" },
            priority = 6,
            color = "@warning",
            borderColor = "@warning",
        },
        {
            selectors = { "featureCard", "activeGroup" },
            priority = 5,
            borderColor = "@accent",
            borderWidth = 2,
        },
        --the weakest-link automation diamond on bestiary rows, shaped and
        --tinted to match the implementation diamonds on rendered stat blocks.
        {
            selectors = { "encounterImplDiamond" },
            bgimage = true,
            bgcolor = "@implStatus1",
        },
        {
            selectors = { "encounterImplDiamond", "wontimplement" },
            bgcolor = "@implStatus0",
        },
        {
            selectors = { "encounterImplDiamond", "bronze" },
            bgcolor = "@implStatus2",
        },
        {
            selectors = { "encounterImplDiamond", "silver" },
            bgcolor = "@implStatus3",
        },
        {
            selectors = { "encounterImplDiamond", "gold" },
            bgcolor = "@implStatus4",
        },
        {
            selectors = { "encounterGroupCard", "gatedOff" },
            opacity = 0.55,
        },
        {
            selectors = { "encounterEntryRow", "gatedOff" },
            opacity = 0.55,
        },
    })
end

-- ===========================================================================
-- Widgets
-- ===========================================================================

--A compact numeric stepper: [-] value [+].
--args: value, min, max, step (default 1), change(newValue),
--      format(value) -> display string (optional), editable (default true)
local function CreateStepper(args)
    local value = args.value or 0
    local step = args.step or 1
    local minValue = args.min
    local maxValue = args.max

    local formatValue = args.format or function(v)
        return string.format("%d", v)
    end

    local valueLabel

    local function setValue(v)
        if minValue ~= nil and v < minValue then
            v = minValue
        end
        if maxValue ~= nil and v > maxValue then
            v = maxValue
        end
        if v == value then
            valueLabel.text = formatValue(value)
            return
        end
        value = v
        valueLabel.text = formatValue(value)
        if args.change ~= nil then
            args.change(value)
        end
    end

    valueLabel = gui.Label {
        classes = { "number" },
        width = "auto",
        minWidth = args.valueMinWidth or 26,
        height = "auto",
        hpad = 4,
        valign = "center",
        textAlignment = "center",
        text = formatValue(value),
        editable = args.editable ~= false,
        characterLimit = 3,
        change = function(element)
            local n = tonumber(element.text)
            if n == nil then
                element.text = formatValue(value)
                return
            end
            setValue(math.floor(n))
        end,
    }

    return gui.Panel {
        flow = "horizontal",
        width = args.width or "auto",
        height = 28,
        valign = args.valign or "center",
        halign = args.halign,

        gui.Button {
            classes = { "sizeXs" },
            text = "-",
            width = 26,
            height = 26,
            valign = "center",
            press = function()
                setValue(value - step)
            end,
        },

        valueLabel,

        gui.Button {
            classes = { "sizeXs" },
            text = "+",
            width = 26,
            height = 26,
            valign = "center",
            press = function()
                setValue(value + step)
            end,
        },
    }
end

--A small uppercase-ish field caption used above party bar controls. Columns
--center their children horizontally by default; pass halign to override.
local function FieldCaption(text, halign)
    return gui.Label {
        classes = { "fgMuted", "sizeXxs", "bold" },
        width = "auto",
        height = "auto",
        halign = halign,
        bmargin = 4,
        text = text,
    }
end

-- ===========================================================================
-- Balancing popup
-- ===========================================================================

--Per-hero-count balancing for one group: stamina override, disable solo
--action, and per-monster-type count adjustments for party sizes 3-7.
--Attached as a popup to the "Balancing" link; changes are committed to
--group.balancing when the popup closes, then refresh() re-runs the budget.
local function ShowBalancingPopup(element, group, refresh)
    local balancing = DeepCopy(group.balancing or {})
    for _, i in ipairs({ 3, 4, 5, 6, 7 }) do
        balancing[i] = balancing[i] or {}
        balancing[i].monsters = balancing[i].monsters or {}
    end

    local balancingBaseline = DeepCopy(balancing)
    local children = {}

    children[#children + 1] = gui.Label {
        classes = { "bold" },
        width = "100%",
        height = "auto",
        bmargin = 2,
        text = "Balancing by party size",
    }

    children[#children + 1] = gui.Label {
        classes = { "fgMuted", "sizeXxs" },
        width = "100%",
        height = "auto",
        bmargin = 6,
        text = "Adjustments apply only when the party has that many heroes.",
    }

    for _, i in ipairs({ 3, 4, 5, 6, 7 }) do
        local heroCount = i

        local rightChildren = {
            gui.Panel {
                halign = "right",
                flow = "horizontal",
                width = "auto",
                height = "auto",
                vmargin = 4,
                gui.Label {
                    classes = { "sizeXs" },
                    text = "Stamina:",
                    width = "auto",
                    height = "auto",
                    hmargin = 4,
                },
                gui.Input {
                    classes = { "form" },
                    fontSize = 12,
                    width = 50,
                    height = 16,
                    hmargin = 4,
                    text = balancing[heroCount].stamina or "",
                    characterLimit = 4,
                    change = function(element)
                        local val = tonumber(element.text)
                        if val ~= nil then
                            balancing[heroCount].stamina = val
                        else
                            balancing[heroCount].stamina = nil
                        end

                        element.text = balancing[heroCount].stamina or ""
                    end,
                }
            },

            gui.Check {
                classes = { "form" },
                text = "Disable Solo Action",
                height = 14,
                minWidth = 100,
                value = balancing[heroCount].disableSolo or false,
                halign = "right",
                fontSize = 10,
                change = function(element)
                    balancing[heroCount].disableSolo = element.value
                end,
            },
        }

        --per-monster-type count adjustments for this number of heroes.
        for monsterid, baseQuantity in pairs(group.monsters) do
            local monsterAsset = assets.monsters[monsterid]
            local monsterName = (monsterAsset ~= nil and creature.GetTokenDescription(monsterAsset)) or "Unknown"
            local quantity = baseQuantity

            local valueLabel
            valueLabel = gui.Label {
                classes = { "sizeXs" },
                width = "auto",
                height = "auto",
                valign = "center",
                hmargin = 3,
                text = string.format("%+d %s", balancing[heroCount].monsters[monsterid] or 0, monsterName),
            }

            local function adjust(delta)
                local cur = (balancing[heroCount].monsters[monsterid] or 0) + delta
                --never let the adjusted count drop below zero monsters.
                if quantity + cur < 0 then
                    cur = -quantity
                end
                if cur == 0 then
                    balancing[heroCount].monsters[monsterid] = nil
                else
                    balancing[heroCount].monsters[monsterid] = cur
                end
                valueLabel.text = string.format("%+d %s", cur, monsterName)
            end

            rightChildren[#rightChildren + 1] = gui.Panel {
                halign = "right",
                flow = "horizontal",
                width = "auto",
                height = "auto",
                vmargin = 1,

                valueLabel,

                gui.Label {
                    classes = { "link" },
                    fontSize = 14,
                    text = "[-]",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    hmargin = 2,
                    press = function()
                        adjust(-1)
                    end,
                },

                gui.Label {
                    classes = { "link" },
                    fontSize = 14,
                    text = "[+]",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    hmargin = 2,
                    press = function()
                        adjust(1)
                    end,
                },
            }
        end

        children[#children + 1] = gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "auto",
            gui.Label {
                width = 80,
                height = "auto",
                fontSize = 12,
                valign = "center",
                text = string.format("%d Heroes", heroCount),
            },

            gui.Panel {
                width = 250,
                flow = "vertical",
                height = "auto",
                children = rightChildren,
            },
        }
    end

    local panel = gui.Panel {
        classes = { "dialog" },
        width = 380,
        height = "auto",
        flow = "vertical",
        hpad = 10,
        vpad = 10,
        borderBox = true,
        children = children,
        destroy = function(element)
            if not dmhub.DeepEqual(balancingBaseline, balancing) then
                group.balancing = balancing
                refresh()
            end
        end,
    }

    element.popupsInheritStyles = true
    element.popup = panel
end

-- ===========================================================================
-- Party bar
-- ===========================================================================

--The party the encounter is balanced against plus the author's target:
--Heroes / Level / Victories steppers, the live party Encounter Strength
--readout, and the target-difficulty dropdown.
local function CreatePartyBar(encounter, party, refresh, budgetDial)
    local esValueLabel = gui.Label {
        classes = { "number", "sizeXl", "bold" },
        width = "auto",
        height = "auto",
        text = "",
        refreshBuilder = function(element)
            local strength = Encounter.PartyStrength(party)
            element.text = string.format("%d", strength.total)
        end,
    }

    local esBreakdownLabel = gui.Label {
        classes = { "fgMuted", "sizeXxs" },
        width = "auto",
        height = "auto",
        lmargin = 8,
        valign = "bottom",
        bmargin = 4,
        text = "",
        refreshBuilder = function(element)
            local strength = Encounter.PartyStrength(party)
            local text = string.format("%d ES x %d heroes", strength.singleHero, strength.numHeroes)
            if strength.victoryBonus > 0 then
                text = string.format("%s + %d from victories", text, strength.victoryBonus)
            end
            element.text = text
        end,
    }

    local function partyColumn(caption, stepper)
        return gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 18,
            FieldCaption(caption),
            stepper,
        }
    end

    local partyBar
    partyBar = gui.Panel {
        classes = { "bordered", "bg" },
        width = "100%",
        height = "auto",
        flow = "horizontal",
        hpad = 14,
        vpad = 10,
        borderBox = true,
        vmargin = 6,

        partyColumn("Heroes", CreateStepper {
            value = party.numHeroes,
            min = 3,
            max = 7,
            change = function(v)
                party.numHeroes = v
                dmhub.SetSettingValue("numheroes", v)
                refresh()
            end,
        }),

        partyColumn("Level", CreateStepper {
            value = party.level,
            min = 1,
            max = 10,
            change = function(v)
                party.level = v
                refresh()
            end,
        }),

        partyColumn("Victories", CreateStepper {
            value = party.victories,
            min = 0,
            max = 15,
            change = function(v)
                party.victories = v
                refresh()
            end,
        }),

        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 18,

            FieldCaption("Party Encounter Strength"),

            gui.Panel {
                flow = "horizontal",
                width = "auto",
                height = "auto",
                esValueLabel,
                esBreakdownLabel,
            },
        },

        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 18,

            FieldCaption("Victory condition"),

            gui.Dropdown {
                classes = { "form" },
                width = 260,
                height = 28,
                fontSize = 12,
                options = Encounter.GetVictoryConditions(encounter),
                idChosen = encounter:try_get("victoryCondition", "all_defeated"),

                --The "Leader Defeated" option only exists while the encounter contains a
                --Leader monster, and the roster is edited live in the group cards, so poll
                --for that presence flipping and rebuild the option list (re-asserting the
                --current selection) when it changes. Cheap: only reassigns on a change.
                data = { hasLeader = nil },
                thinkTime = 0.5,
                think = function(element)
                    local hasLeader = Encounter.HasMonsterWithOrganization(encounter, "leader")
                    if hasLeader ~= element.data.hasLeader then
                        element.data.hasLeader = hasLeader
                        element.options = Encounter.GetVictoryConditions(encounter)
                        element.idChosen = encounter:try_get("victoryCondition", "all_defeated")
                    end
                end,

                change = function(element)
                    encounter.victoryCondition = element.idChosen
                    partyBar:FireEventTree("refreshDestroy")
                end,
            },

            --Shown only when the "Destroy the Thing!" victory condition is selected. Lets the
            --DM pick which Targetable object keyword identifies the "thing" to destroy, or
            --explains how to add one if the map has no Targetable objects with keywords.
            gui.Panel {
                width = 260,
                height = "auto",
                flow = "vertical",

                create = function(element)
                    element:FireEvent("refreshDestroy")
                end,

                refreshDestroy = function(element)
                    local isDestroy = encounter:try_get("victoryCondition", "all_defeated") == "destroy_thing"
                    element:SetClass("collapsed", not isDestroy)
                    if not isDestroy then
                        element.children = {}
                        return
                    end

                    local keywords = Encounter.GetTargetableObjectKeywords()

                    if #keywords == 0 then
                        element.children = {
                            gui.Label {
                                classes = { "fgStrong" },
                                width = "100%",
                                height = "auto",
                                halign = "left",
                                valign = "top",
                                tmargin = 6,
                                fontSize = 12,
                                textWrap = true,
                                text = "To select a thing to destroy add an object to the map with the Targetable property and a keyword",
                            },
                        }
                        return
                    end

                    local keywordOptions = {}
                    for _, keyword in ipairs(keywords) do
                        keywordOptions[#keywordOptions + 1] = { id = keyword, text = keyword }
                    end

                    local chosen = encounter:try_get("victoryDestroyKeyword")
                    if chosen == nil or not table.contains(keywords, chosen) then
                        chosen = keywords[1]
                        encounter.victoryDestroyKeyword = chosen
                    end

                    element.children = {
                        gui.Dropdown {
                            classes = { "form" },
                            width = "100%",
                            height = 26,
                            halign = "left",
                            valign = "center",
                            tmargin = 6,
                            fontSize = 12,
                            options = keywordOptions,
                            idChosen = chosen,
                            change = function(dropdown)
                                encounter.victoryDestroyKeyword = dropdown.idChosen
                            end,
                        },
                    }
                end,
            },
        },

        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "center",

            FieldCaption("Victories awarded"),

            gui.Input {
                classes = { "form" },
                width = 60,
                height = 26,
                fontSize = 12,
                numeric = true,
                characterLimit = 3,
                text = tostring(encounter:try_get("victories", 1)),
                change = function(element)
                    --validate as a non-negative integer; revert to the stored value on
                    --bad input.
                    local n = tonumber(element.text)
                    if n == nil then
                        element.text = tostring(encounter:try_get("victories", 1))
                        return
                    end
                    n = math.floor(n)
                    if n < 0 then n = 0 end
                    encounter.victories = n
                    element.text = tostring(n)
                end,
            },
        },

        budgetDial,
    }

    return partyBar
end

-- ===========================================================================
-- Budget dial
-- ===========================================================================

--The encounter-budget gauge: a speedometer-style dial whose needle sweeps
--from Trivial (left) through Extreme (right), with the EV/difficulty readout
--beneath the hub. Sits as the right-most column of the party bar. The arc
--is built from two stacked half-discs (top-rounded panels): the outer dome
--paints the ring and the inner cutout restores the surface color. Ticks cut
--across the ring where each difficulty tier begins.
local function CreateBudgetDial(encounter, party)
    local needleBar = gui.Panel {
        classes = { "encounterMeterFill" },
        width = 4,
        height = 46,
        halign = "center",
        valign = "top",
    }

    --the needle's parent is twice the needle length so its center sits on
    --the dial hub: rotating the parent about its center swings the visible
    --top-half bar like a clock hand, while the bottom half is empty.
    local needle
    needle = gui.Panel {
        width = 8,
        height = 100,
        halign = "center",
        valign = "top",
        y = 15,
        rotate = 0,
        flow = "none",
        needleBar,
    }

    --tier-boundary ticks, swung around the hub the same way as the needle:
    --each parent is centered on the hub and its top-anchored bar spans the
    --ring's thickness, so rotating the parent lays the tick across the arc.
    local ticks = {}
    for i = 1, 4 do
        ticks[i] = gui.Panel {
            width = 3,
            height = 130,
            halign = "center",
            valign = "top",
            y = 0,
            rotate = 0,
            flow = "none",

            gui.Panel {
                classes = { "encounterDialTick" },
                width = "100%",
                height = 20,
                halign = "center",
                valign = "top",
            },
        }
    end

    local readoutLabel = gui.Label {
        classes = { "bold", "sizeS" },
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "top",
        y = 74,
        text = "",
    }

    local dial = gui.Panel {
        width = 150,
        height = 96,
        halign = "center",
        flow = "none",

        --outer dome: rounding the top corners by the full height makes a
        --half-disc.
        gui.Panel {
            classes = { "encounterDialRing" },
            width = 130,
            height = 65,
            halign = "center",
            valign = "top",
            y = 0,
            --x1=top-left, y1=top-right, x2=bottom-right, y2=bottom-left
            cornerRadius = { x1 = 65, y1 = 65, x2 = 0, y2 = 0 },
        },

        --inner cutout dome leaves a 20px arc ring.
        gui.Panel {
            classes = { "encounterDialCut" },
            width = 90,
            height = 45,
            halign = "center",
            valign = "top",
            y = 20,
            cornerRadius = { x1 = 45, y1 = 45, x2 = 0, y2 = 0 },
        },

        ticks[1],
        ticks[2],
        ticks[3],
        ticks[4],

        needle,

        gui.Panel {
            classes = { "encounterDialHub" },
            width = 12,
            height = 12,
            halign = "center",
            valign = "top",
            y = 59,
            cornerRadius = 6,
        },

        readoutLabel,
    }

    return gui.Panel {
        flow = "vertical",
        width = "auto",
        height = "auto",
        valign = "center",

        refreshBuilder = function(element)
            local strength = Encounter.PartyStrength(party)
            local bands = Encounter.DifficultyBands(strength)

            local ev = 0
            for _, group in ipairs(encounter.groups) do
                ev = ev + AdjustedGroupEV(group, party.numHeroes)
            end

            local actualTier = Encounter.DifficultyTier(ev, strength)
            SetExclusiveClass(needleBar, g_tierFillClass, actualTier)
            SetExclusiveClass(readoutLabel, g_tierColorClass, actualTier)

            local scale = math.max(bands.hardMax * 1.15, 1)

            --sweep from pointing left (Trivial/empty) to pointing right
            --(Extreme). Positive rotation is counter-clockwise in this
            --engine, so the sweep runs from +90 down to -90.
            local function sweep(x)
                local f = x / scale
                if f < 0 then f = 0 end
                if f > 1 then f = 1 end
                return 90 - 180 * f
            end

            needle.selfStyle.rotate = sweep(ev)

            --a tick at the EV where each tier above Trivial begins.
            local edges = { bands.trivialBelow, bands.easyBelow, bands.standardBelow, bands.hardMax }
            for i, edge in ipairs(edges) do
                ticks[i].selfStyle.rotate = sweep(edge)
            end

            readoutLabel.text = string.format("%d EV - %s", ev, actualTier)
        end,

        FieldCaption("Encounter Budget"),

        dial,
    }
end

-- ===========================================================================
-- Bestiary pane
-- ===========================================================================

--Cached bestiary facts, shared across editor opens. Computing a monster's
--EV runs the attribute pipeline, so doing it for the whole compendium is
--slow -- pay that cost once and invalidate whenever the assets change.
local g_bestiaryInfoCache = nil

--The always-visible bestiary browser: search plus one row per (non-hidden)
--monster with its portrait, level/EV, and click-to-add.
--addMonster(info) is called when a row is clicked.
local function CreateBestiaryPane(party, addMonster)
    local state = {
        searchText = "",
        page = 1,
    }

    --one page of rows at a time: building the whole compendium's rows (and
    --re-filtering them per keystroke) is what made the pane crawl.
    local PAGE_SIZE = 25

    --gather bestiary facts from the live compendium (assets.monsters),
    --memoized in g_bestiaryInfoCache.
    local function BuildInfos()
        if g_bestiaryInfoCache == nil then
            local infos = {}
            for monsterid, monsterAsset in pairs(assets.monsters) do
                if not monsterAsset.hidden then
                    infos[#infos + 1] = MonsterBuildInfo(monsterid, monsterAsset)
                end
            end
            table.sort(infos, function(a, b)
                return a.name < b.name
            end)
            g_bestiaryInfoCache = infos
        end
        return g_bestiaryInfoCache
    end

    local listPanel

    --Build the row panel for one bestiary entry.
    local function BuildRow(rowInfo)
        --the monster's portrait rendered inside its token frame; fall back to
        --a plain bordered portrait if the asset has no token view.
        local imagePanel
        if rowInfo.token ~= nil then
            imagePanel = gui.CreateTokenImage(rowInfo.token, {
                width = 32,
                height = 32,
                valign = "center",
                lmargin = 4,
                rmargin = 8,
            })
        else
            imagePanel = gui.Panel {
                classes = { "image", "bordered" },
                bgimage = rowInfo.portraitId,
                width = 32,
                height = 32,
                valign = "center",
                lmargin = 4,
                rmargin = 8,
            }
        end

        --weakest-link automation diamond for the monster's own kit; hidden
        --when the kit carries no implementation data.
        local implIcon = gui.Panel {
            classes = { "encounterImplDiamond", g_implementationClass[rowInfo.implementation or 1] },
            rotate = 45,
            width = 10,
            height = 10,
            valign = "center",
            hmargin = 7,
            bgimage = true,
            hover = gui.Tooltip(ImplementationTooltip(rowInfo)),
        }
        if rowInfo.implementation == nil then
            implIcon:SetClass("hidden", true)
        end

        return gui.Panel {
            classes = { "hoverable" },
            width = "100%-14",
            height = 40,
            flow = "horizontal",
            valign = "top",
            halign = "left",
            bmargin = 2,
            bgimage = true,
            bgcolor = "clear",

            data = {
                info = rowInfo,
            },

            --click (not press): press also fires when a drag gesture ends,
            --which would double-add dragged monsters.
            click = function(element)
                addMonster(rowInfo)
            end,

            --rows can also be dragged onto a specific group card, which adds
            --the monster there (and makes that group the active one). The
            --engine paints eligible cards with the drag-target classes while
            --the drag is in flight.
            draggable = true,
            canDragOnto = function(element, target)
                return target:HasClass("encounterGroupCard")
            end,
            drag = function(element, target)
                if target ~= nil then
                    target:FireEvent("dropMonster", rowInfo)
                end
            end,

            --a drag is starting: kill any open stat-block flyout so it does
            --not ride along or rebuild mid-drag (Render costs 100-300ms).
            beginDrag = function(element)
                element.tooltip = nil
            end,

            --linger to fly out the monster's full stat block, mirroring the
            --bestiary panel's hover preview (CharacterPanel.lua). Opens to the
            --right since this pane sits on the left edge of the builder.
            linger = function(element)
                if rowInfo.asset == nil then
                    return
                end

                --never build the (expensive) flyout while this row is being
                --dragged: the render is a guaranteed frame hitch.
                if element.dragging then
                    return
                end

                local lockedHeight = math.floor(dmhub.screenDimensionsBelowTitlebar.y * 0.6)
                local panel = rowInfo.asset:Render {
                    width = 800,
                    maxHeight = lockedHeight,
                    vscroll = true,
                }

                if panel ~= nil then
                    element.tooltip = gui.TooltipFrame(
                        panel,
                        {
                            halign = "right",
                            valign = "center",
                            interactable = true,
                        }
                    )
                end
            end,

            imagePanel,

            gui.Panel {
                flow = "vertical",
                width = "100%-164",
                height = "auto",
                valign = "center",

                gui.Label {
                    classes = { "sizeS" },
                    width = "100%",
                    height = "auto",
                    text = rowInfo.name,
                },

                gui.Label {
                    classes = { "fgMuted", "sizeXxs" },
                    width = "100%",
                    height = "auto",
                    text = rowInfo.meta,
                },
            },

            implIcon,

            gui.Label {
                classes = { "warning", "bold", "sizeS" },
                width = 14,
                height = "auto",
                valign = "center",
                textAlignment = "center",
                rmargin = 4,
                text = "!",
                hover = gui.Tooltip("Above the suggested monster level for this party (party level + 2)"),
                refreshBuilder = function(element)
                    element:SetClass("hidden", rowInfo.level <= party.level + 2)
                end,
            },

            gui.Label {
                classes = { "encounterBadge" },
                width = 54,
                height = "auto",
                valign = "center",
                halign = "right",
                textAlignment = "center",
                rmargin = 4,
                text = string.format("EV %d", rowInfo.ev),
            },
        }
    end

    --Search happens at the DATA level (a substring scan over the cached
    --infos is microseconds for a whole compendium); only the current page's
    --rows ever exist as panels.
    local function FilteredInfos()
        local infos = BuildInfos()
        if state.searchText == "" then
            return infos
        end
        local result = {}
        for _, info in ipairs(infos) do
            local haystack = string.lower(info.name .. " " .. info.meta)
            if string.find(haystack, state.searchText, 1, true) then
                result[#result + 1] = info
            end
        end
        return result
    end

    local pagerLabel
    local prevButton
    local nextButton

    --Build the current page's rows and bring the pager controls in line.
    local function RebuildList()
        if listPanel == nil or not listPanel.valid then
            return
        end

        local infos = FilteredInfos()
        local pageCount = math.max(1, math.ceil(#infos / PAGE_SIZE))
        if state.page > pageCount then
            state.page = pageCount
        end
        if state.page < 1 then
            state.page = 1
        end

        local first = (state.page - 1) * PAGE_SIZE + 1
        local last = math.min(first + PAGE_SIZE - 1, #infos)

        local children = {}
        for i = first, last do
            local row = BuildRow(infos[i])
            row:FireEventTree("refreshBuilder")
            children[#children + 1] = row
        end

        if #infos == 0 then
            children[1] = gui.Label {
                classes = { "fgMuted", "sizeXs" },
                width = "100%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vpad = 10,
                text = "No monsters match your search.",
            }
        end

        listPanel.children = children

        if pagerLabel ~= nil and pagerLabel.valid then
            if #infos == 0 then
                pagerLabel.text = "0 monsters"
            else
                pagerLabel.text = string.format("%d-%d of %d", first, last, #infos)
            end
        end
        if prevButton ~= nil and prevButton.valid then
            prevButton:SetClass("hidden", state.page <= 1)
        end
        if nextButton ~= nil and nextButton.valid then
            nextButton:SetClass("hidden", state.page >= pageCount)
        end
    end

    listPanel = gui.Panel {
        width = "100%",
        height = "100% available",
        flow = "vertical",
        vscroll = true,
        monitorAssets = true,

        create = function(element)
            RebuildList()
        end,

        --rebuild whenever the compendium changes so the list always
        --reflects the live bestiary (imports, edits, deletions).
        refreshAssets = function(element)
            g_bestiaryInfoCache = nil
            RebuildList()
        end,
    }

    pagerLabel = gui.Label {
        classes = { "fgMuted", "sizeXs" },
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        minWidth = 110,
        text = "",
    }

    prevButton = gui.Button {
        classes = { "sizeXs" },
        width = 70,
        halign = "left",
        valign = "center",
        text = "Previous",
        press = function(element)
            state.page = state.page - 1
            RebuildList()
        end,
    }

    nextButton = gui.Button {
        classes = { "sizeXs" },
        width = 70,
        halign = "right",
        valign = "center",
        text = "Next",
        press = function(element)
            state.page = state.page + 1
            RebuildList()
        end,
    }

    return gui.Panel {
        classes = { "bordered", "bg" },
        width = 340,
        --the scrolling composition column insets its content ~8px from the
        --top (measured); offset this pane to match so the two boxes' top
        --edges align across the divide.
        tmargin = 8,
        height = "100%-8",
        flow = "vertical",
        hpad = 10,
        vpad = 10,
        borderBox = true,

        gui.SearchInput {
            classes = { "bordered" },
            width = 260,
            height = 24,
            halign = "left",
            bmargin = 8,
            fontSize = 13,
            placeholderText = "Search monsters...",

            edit = function(element)
                state.searchText = string.lower(element.text)
                state.page = 1
                RebuildList()
            end,

            confirm = function(element)
                local query = element.text
                if query ~= "" then
                    track("search_query", {
                        query = query,
                        resultCount = #FilteredInfos(),
                        context = "encounter",
                        dailyLimit = 20,
                    })
                end
            end,
        },

        listPanel,

        --pager: one page of rows at a time keeps the pane fast; search is
        --how anyone realistically finds a monster in a 500-entry bestiary.
        gui.Panel {
            width = "100%",
            height = 26,
            flow = "horizontal",
            tmargin = 6,

            prevButton,
            pagerLabel,
            nextButton,
        },
    }
end

-- ===========================================================================
-- Group cards and wave sections
-- ===========================================================================

--One initiative-group card: header (name, "adds here" tag, band guidance, EV,
--delete) plus a body of roster entries and a footer with the group's
--"appears at N+ heroes" gate and Balancing link.
local function CreateGroupCard(args)
    local encounter = args.encounter
    local party = args.party
    local state = args.state
    local group = args.group
    local groupIndex = args.groupIndex
    local refresh = args.refresh
    local rebuild = args.rebuild

    --sorted roster entries for stable display.
    local entries = {}
    for monsterid, quantity in pairs(group.monsters) do
        local monsterAsset = assets.monsters[monsterid]
        if monsterAsset ~= nil then
            entries[#entries + 1] = {
                monsterid = monsterid,
                quantity = quantity,
                info = MonsterBuildInfo(monsterid, monsterAsset),
                asset = monsterAsset,
            }
        end
    end
    table.sort(entries, function(a, b)
        return a.info.name < b.info.name
    end)

    local entryPanels = {}
    for _, entry in ipairs(entries) do
        local monsterid = entry.monsterid
        local info = entry.info
        local monsterAsset = entry.asset
        local step = cond(info.minion, 4, 1)

        local evBadge = gui.Label {
            classes = { "encounterBadge" },
            width = 54,
            height = "auto",
            valign = "center",
            textAlignment = "center",
            rmargin = 8,
            text = "",
            refreshBuilder = function(element)
                local n = Encounter.AdjustedMonsterQuantity(group, monsterid, group.monsters[monsterid] or 0, party.numHeroes)
                element.text = string.format("EV %d", EntryEV(monsterAsset, n))
            end,
        }

        --per-monster "appears at N+ heroes" gate. The data lives on the group
        --(group.monsterMinHeroes[monsterid]) and is enforced inside
        --Encounter.AdjustedMonsterQuantity, so EV, spawn, and despawn all
        --honor it.
        local appearsLink = gui.Label {
            classes = { "link", "sizeXs" },
            width = 52,
            height = "auto",
            valign = "center",
            rmargin = 8,
            text = "",
            hover = gui.Tooltip("The minimum party size at which this monster appears."),
            refreshBuilder = function(element)
                local minHeroes = (group.monsterMinHeroes or {})[monsterid]
                if minHeroes == nil then
                    element.text = "Always"
                else
                    element.text = string.format("%d+", minHeroes)
                end
            end,
            press = function(element)
                local menuEntries = {}
                for _, i in ipairs({ 0, 3, 4, 5, 6, 7 }) do
                    menuEntries[#menuEntries + 1] = {
                        text = cond(i == 0, "Always", string.format("%d+ Heroes", i)),
                        selected = ((group.monsterMinHeroes or {})[monsterid] or 0) == i,
                        click = function()
                            group.monsterMinHeroes = group.monsterMinHeroes or {}
                            group.monsterMinHeroes[monsterid] = cond(i == 0, nil, i)
                            element.popup = nil
                            refresh()
                        end,
                    }
                end

                element.popup = gui.ContextMenu {
                    entries = menuEntries,
                }
            end,
        }

        local balancingNote = gui.Label {
            classes = { "accent", "sizeXxs" },
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 8,
            text = "",
            refreshBuilder = function(element)
                local base = group.monsters[monsterid] or 0
                local n = Encounter.AdjustedMonsterQuantity(group, monsterid, base, party.numHeroes)
                local notes = {}
                local gate = (group.monsterMinHeroes or {})[monsterid]
                if gate ~= nil and party.numHeroes < gate then
                    notes[#notes + 1] = string.format("not at %d heroes", party.numHeroes)
                elseif n ~= base then
                    notes[#notes + 1] = string.format("%+d at %d heroes", n - base, party.numHeroes)
                end
                local heroBalancing = (group.balancing or {})[party.numHeroes]
                if heroBalancing ~= nil and type(heroBalancing.stamina) == "number" then
                    notes[#notes + 1] = string.format("stamina %d", heroBalancing.stamina)
                end
                if heroBalancing ~= nil and heroBalancing.disableSolo then
                    notes[#notes + 1] = "solo action off"
                end
                element.text = table.concat(notes, " - ")
            end,
        }

        --minions spawn in squads; once there are 8+ the DM can cycle the
        --squad size (4/8/12/...) which wave deployment and spawn honor.
        local squadSizeLabel = nil
        if info.minion then
            squadSizeLabel = gui.Label {
                classes = { "link", "sizeXxs" },
                width = "auto",
                height = "auto",
                valign = "center",
                lmargin = 8,
                text = "",
                press = function(element)
                    local quantity = group.monsters[monsterid] or 0
                    group.squadSize = (group.squadSize or 4) + 4
                    if group.squadSize > quantity then
                        group.squadSize = 4
                    end
                    refresh()
                end,
                refreshBuilder = function(element)
                    local quantity = group.monsters[monsterid] or 0
                    if quantity < 8 then
                        element:SetClass("hidden", true)
                        return
                    end
                    element:SetClass("hidden", false)
                    element.text = string.format("(squads of %d)", group.squadSize or 4)
                end,
            }
        end

        local entryImagePanel
        if info.token ~= nil then
            entryImagePanel = gui.CreateTokenImage(info.token, {
                width = 28,
                height = 28,
                valign = "center",
                rmargin = 8,
            })
        else
            entryImagePanel = gui.Panel {
                classes = { "image", "bordered" },
                bgimage = info.portraitId,
                width = 28,
                height = 28,
                valign = "center",
                rmargin = 8,
            }
        end

        entryPanels[#entryPanels + 1] = gui.Panel {
            classes = { "encounterEntryRow" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            vpad = 6,
            hpad = 10,
            borderBox = true,

            refreshBuilder = function(element)
                local gate = (group.monsterMinHeroes or {})[monsterid]
                element:SetClass("gatedOff", gate ~= nil and party.numHeroes < gate)
            end,

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "horizontal",

                entryImagePanel,

                gui.Panel {
                    flow = "vertical",
                    width = "100%-350",
                    height = "auto",
                    valign = "center",

                    gui.Label {
                        classes = { "sizeS" },
                        width = "100%",
                        height = "auto",
                        text = info.name,
                    },

                    gui.Label {
                        classes = { "fgMuted", "sizeXxs" },
                        width = "100%",
                        height = "auto",
                        text = info.meta,
                    },
                },

                CreateStepper {
                    value = entry.quantity,
                    min = 0,
                    step = step,
                    width = 150,
                    valueMinWidth = 56,
                    format = function(v)
                        if info.minion then
                            return string.format("%d minions", v)
                        end
                        return string.format("x%d", v)
                    end,
                    change = function(v)
                        if v <= 0 then
                            group.monsters[monsterid] = nil
                            rebuild()
                        else
                            group.monsters[monsterid] = v
                            refresh()
                        end
                    end,
                },

                evBadge,

                appearsLink,

                gui.Button {
                    classes = { "deleteButton", "sizeXs" },
                    valign = "center",
                    press = function(element)
                        group.monsters[monsterid] = nil
                        rebuild()
                    end,
                },
            },

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "horizontal",
                lmargin = 26,

                balancingNote,
                squadSizeLabel,
            },
        }
    end

    local emptyHint = nil
    if #entries == 0 then
        emptyHint = gui.Label {
            classes = { "fgMuted", "sizeXs" },
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vpad = 10,
            text = "Drag a monster here from the Bestiary, or select this group and click monsters to add them.",
        }
    end

    --group-scoped controls, shown once in the card footer: per-party-size
    --balancing and per-group placement. (The "appears at N+ heroes" gate is
    --per MONSTER and lives on each roster row.)
    local groupBalancingLink = gui.Label {
        classes = { "link", "sizeXs" },
        width = "auto",
        height = "auto",
        valign = "center",
        rmargin = 16,
        text = "Balancing",
        hover = gui.Tooltip("Per-party-size adjustments for this group: monster counts, stamina, solo actions."),
        refreshBuilder = function(element)
            element.text = cond(GroupHasBalancing(group), "Balancing (set)", "Balancing")
        end,
        press = function(element)
            ShowBalancingPopup(element, group, refresh)
        end,
    }

    local placeLink = gui.Label {
        classes = { "link", "sizeXs" },
        width = "auto",
        height = "auto",
        --reserve room for the longest state so the footer row does not
        --reflow every staging cycle.
        minWidth = 150,
        valign = "center",
        rmargin = 16,
        text = "Stage on Map",
        hover = gui.Tooltip("Stage this group on the map and arrange its starting positions. Collecting the tokens saves their positions with the plan; Start Encounter places them there for real."),
        refreshBuilder = function(element)
            element.text = cond(#PlacedTokensForGroup(group) > 0, "Save Positions & Remove", "Stage on Map")
        end,
        press = function(element)
            --already on the map: bank the arrangement, then collect the
            --tokens. Discarding instead lives on the card's right-click menu.
            local placed = PlacedTokensForGroup(group)
            if #placed > 0 then
                BankGroupPositions(group, encounter.saveAppearances)
                local charids = {}
                for _, token in ipairs(placed) do
                    charids[#charids + 1] = token.charid
                end
                game.DeleteCharacters(charids)
                refresh()
                --token deletion resolves asynchronously; refresh again once
                --it lands so the link and chip flip without another click.
                dmhub.Schedule(0.4, function()
                    if mod.unloaded then return end
                    refresh()
                end)
                return
            end

            if AdjustedGroupCount(group, party.numHeroes) == 0 then
                gui.ModalMessage {
                    title = "Nothing to Stage",
                    message = "This group has no monsters at the current party size.",
                }
                return
            end

            if group.placementid == nil then
                group.placementid = dmhub.GenerateGuid()
            end
            local placementid = group.placementid

            local editorPanel = element:FindParentWithClass("editorPanel")

            local function ShowArrangeBanner()
                ShowStagingBanner(
                    string.format("%s staged. Arrange the tokens, then return - positions save with the plan.", GroupName(encounter, group, groupIndex)),
                    {
                        onClosed = function()
                            if editorPanel ~= nil and editorPanel.valid then
                                editorPanel:SetClass("hidden", false)
                                refresh()
                            end
                        end,
                    })
            end

            --a saved staging exists on THIS map: re-materialize the tokens at
            --their saved positions and bring them into view for arranging.
            --Positions banked on another map are coordinates that mean nothing
            --here, so fall through to click-to-stage instead.
            if group.spawnlocs ~= nil and #group.spawnlocs > 0 and not GroupStagedOnOtherMap(group) then
                local tokens = StageGroupAtSavedLocations(group, party.numHeroes, placementid)
                if #tokens > 0 then
                    editorPanel:SetClass("hidden", true)

                    local firstCharid = tokens[1].charid
                    dmhub.Schedule(0.2, function()
                        if mod.unloaded then return end
                        dmhub.FocusToken(firstCharid)
                    end)

                    ShowArrangeBanner()
                    refresh()
                    return
                end
                --no slot had a usable saved position; fall through to
                --click-to-stage.
            end

            --stage a copy of the encounter holding only this group, ungated
            --and unwaved so the engine spawns all of it right away.
            local placeEncounter = DeepCopy(encounter)
            local groupCopy = DeepCopy(group)
            groupCopy.wave = nil
            groupCopy.minHeroes = nil
            placeEncounter.groups = { groupCopy }
            placeEncounter.waves = {}

            editorPanel:SetClass("hidden", true)

            local stageMessage = string.format("Click on the map to stage %s", GroupName(encounter, group, groupIndex))
            if GroupStagedOnOtherMap(group) then
                stageMessage = string.format("Positions were saved on another map - click to stage %s here", GroupName(encounter, group, groupIndex))
            end

            --when the click resolves we chain straight into the arrange
            --banner (editor stays hidden) so initial staging gets the same
            --arrange moment as re-staging.
            local chainedToArrange = false

            ShowPlacementBanner(placeEncounter, {
                message = stageMessage,

                --tag the tokens once they resolve so the builder can
                --recognise them, offer removal, and bank their positions
                --into the group at save time.
                onSpawned = function(charids)
                    chainedToArrange = true
                    local attempts = 20
                    local function tagWhenReady()
                        if mod.unloaded then return end
                        local allReady = true
                        for _, cid in ipairs(charids) do
                            if dmhub.GetTokenById(cid or "") == nil then
                                allReady = false
                                break
                            end
                        end
                        if not allReady and attempts > 0 then
                            attempts = attempts - 1
                            dmhub.Schedule(0.1, tagWhenReady)
                            return
                        end
                        for slot, cid in ipairs(charids) do
                            local token = dmhub.GetTokenById(cid or "")
                            if token ~= nil then
                                token.properties.encounterPlacementId = placementid
                                token.properties.encounterSpawnSlot = slot
                                token.properties.encounterStaged = true
                                token.properties.encounterStagedBy = dmhub.userid
                                token:UploadToken()
                            end
                        end
                        refresh()
                    end
                    tagWhenReady()
                    ShowArrangeBanner()
                end,

                onClosed = function()
                    if chainedToArrange then
                        --the arrange banner now owns restoring the editor.
                        return
                    end
                    if editorPanel ~= nil and editorPanel.valid then
                        editorPanel:SetClass("hidden", false)
                        refresh()
                    end
                end,
            })
        end,
    }

    local placementChip = gui.Label {
        classes = { "encounterBadge" },
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "right",
        text = "",
        hover = gui.Tooltip("Green: this group's tokens are on the map for staging. Plain: starting positions are saved with the plan. A count mismatch means the roster changed after staging - restage to fix the positions."),
        refreshBuilder = function(element)
            local live = #PlacedTokensForGroup(group)
            local saved = group.spawnlocs ~= nil and #group.spawnlocs > 0
            element:SetClass("hidden", not (live > 0 or saved))
            element:SetClass("success", live > 0)
            if live > 0 then
                local expected = AdjustedGroupCount(group, party.numHeroes)
                if live ~= expected then
                    element.text = string.format("Staged (%d of %d)", live, expected)
                else
                    element.text = string.format("Staged (%d)", live)
                end
            elseif saved then
                if GroupStagedOnOtherMap(group) then
                    element.text = "Positions saved (other map)"
                else
                    element.text = "Positions saved"
                end
            end
        end,
    }

    local card
    card = gui.Panel {
        classes = { "featureCard", "encounterGroupCard" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        --spacing below only: the first card's top edge must align with the
        --top of the bestiary pane across the divide.
        bmargin = 8,

        --bestiary rows dropped on the card add their monster to THIS group
        --and make it the active one for follow-up clicks.
        dragTarget = true,
        dropMonster = function(element, info)
            state.activeGroup = group
            local step = cond(info.minion, 4, 1)
            group.monsters[info.monsterid] = (group.monsters[info.monsterid] or 0) + step
            rebuild()
        end,

        rightClick = function(element)
            local menuEntries = {
                {
                    text = "Duplicate",
                    click = function()
                        element.popup = nil
                        local copy = DeepCopy(group)
                        --placement identity and saved positions belong to the
                        --original group; the copy starts unplaced.
                        copy.placementid = nil
                        copy.spawnlocs = nil
                        copy.appearances = nil
                        copy.invisibleToPlayers = nil
                        encounter.groups[#encounter.groups + 1] = copy
                        rebuild()
                    end,
                },
            }

            if #PlacedTokensForGroup(group) > 0 then
                menuEntries[#menuEntries + 1] = {
                    text = "Remove from Map Without Saving",
                    click = function()
                        element.popup = nil
                        local charids = {}
                        for _, token in ipairs(PlacedTokensForGroup(group)) do
                            charids[#charids + 1] = token.charid
                        end
                        game.DeleteCharacters(charids)
                        refresh()
                        --token deletion resolves asynchronously; refresh again
                        --once it lands so the link and chip flip on their own.
                        dmhub.Schedule(0.4, function()
                            if mod.unloaded then return end
                            refresh()
                        end)
                    end,
                }
            end

            if group.spawnlocs ~= nil and #group.spawnlocs > 0 then
                menuEntries[#menuEntries + 1] = {
                    text = "Clear Saved Staging",
                    click = function()
                        element.popup = nil
                        group.spawnlocs = nil
                        group.appearances = nil
                        group.invisibleToPlayers = nil
                        group.stagemapid = nil
                        refresh()
                    end,
                }
            end

            element.popup = gui.ContextMenu {
                entries = menuEntries,
            }
        end,

        refreshBuilder = function(element)
            element:SetClass("activeGroup", state.activeGroup == group)
        end,

        gui.Panel {
            classes = { "featureCardHeader", "expanded" },
            width = "100%",
            height = 32,
            flow = "horizontal",

            press = function(element)
                state.activeGroup = group
                refresh()
            end,

            --editable group name; clearing it falls back to the positional
            --default ("Group A").
            gui.Label {
                classes = { "sizeS", "bold" },
                width = "auto",
                height = "auto",
                minWidth = 80,
                valign = "center",
                lmargin = 10,
                text = GroupName(encounter, group, groupIndex),
                characterLimit = 24,
                editable = true,
                hover = gui.Tooltip("Click to rename this group."),
                change = function(label)
                    local newName = label.text
                    if newName == nil or newName:match("^%s*$") ~= nil then
                        group.name = nil
                    else
                        group.name = newName
                    end
                    label.text = GroupName(encounter, group, groupIndex)
                end,
            },


            gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                valign = "center",
                halign = "right",
                rmargin = 8,

                gui.Label {
                    classes = { "encounterBadge" },
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    text = "",
                    refreshBuilder = function(element)
                        element.text = string.format("%d EV", AdjustedGroupEV(group, party.numHeroes))
                    end,
                },
            },

            gui.Button {
                classes = { "deleteButton", "sizeXs" },
                valign = "center",
                halign = "right",
                rmargin = 4,
                swallowPress = true,
                press = function(element)
                    table.remove(encounter.groups, groupIndex)
                    if state.activeGroup == group then
                        state.activeGroup = encounter.groups[1]
                    end
                    rebuild()
                end,
            },
        },

        gui.Panel {
            classes = { "featureCardBody" },
            width = "100%",
            height = "auto",
            flow = "vertical",

            emptyHint,

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = entryPanels,
            },

            --group footer: the group-scoped controls plus placement status.
            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "horizontal",
                hpad = 10,
                vpad = 6,
                borderBox = true,

                gui.Panel {
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",

                    groupBalancingLink,
                    placeLink,
                },

                placementChip,
            },
        },
    }

    return card
end

--The right-hand composition column body: the start-of-encounter groups, then
--one section per reinforcement wave (name, arrival round, EV, delete), each
--holding its group cards, an add-group button per section, and an add-wave
--button at the bottom.
local function CreateWaveSections(args)
    local encounter = args.encounter
    local party = args.party
    local state = args.state
    local refresh = args.refresh
    local rebuild = args.rebuild

    local function sectionEVLabel(waveid)
        return gui.Label {
            classes = { "encounterBadge" },
            width = "auto",
            height = "auto",
            valign = "center",
            halign = "right",
            text = "",
            refreshBuilder = function(element)
                local ev = 0
                for _, group in ipairs(encounter.groups) do
                    if group.wave == waveid then
                        ev = ev + AdjustedGroupEV(group, party.numHeroes)
                    end
                end
                element.text = string.format("%d EV", ev)
            end,
        }
    end

    local function addGroupButton(waveid)
        return gui.Button {
            classes = { "sizeS" },
            width = 180,
            halign = "left",
            vmargin = 4,
            text = "Add Initiative Group",
            press = function(element)
                encounter:AddGroup()
                local newGroup = encounter.groups[#encounter.groups]
                newGroup.wave = waveid
                state.activeGroup = newGroup
                rebuild()
            end,
        }
    end

    return gui.Panel {
        width = "100%-14",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",

        rebuildGroups = function(element)
            local children = {}

            --repair dangling wave references before bucketing.
            local wavesById = {}
            for _, wave in ipairs(encounter:try_get("waves", {})) do
                wavesById[wave.id] = wave
            end
            for _, group in ipairs(encounter.groups) do
                if group.wave ~= nil and wavesById[group.wave] == nil then
                    group.wave = nil
                end
            end

            --wave vocabulary stays hidden until the encounter actually uses
            --reinforcement waves: with none, this is just a plain list of
            --initiative groups plus a quiet link to add a wave.
            local hasWaves = #encounter:try_get("waves", {}) > 0

            local function appendCards(waveid)
                for groupIndex, group in ipairs(encounter.groups) do
                    if group.wave == waveid then
                        children[#children + 1] = CreateGroupCard {
                            encounter = encounter,
                            party = party,
                            state = state,
                            group = group,
                            groupIndex = groupIndex,
                            refresh = refresh,
                            rebuild = rebuild,
                        }
                    end
                end
            end

            --start-of-encounter section header. Only shown when waves exist
            --and the sections need telling apart; without waves the group
            --cards speak for themselves (the dialog header carries the EV).
            if hasWaves then
                children[#children + 1] = gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    tmargin = 6,
                    bmargin = 2,

                    gui.Label {
                        classes = { "bold", "sizeS" },
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        text = "Start of Encounter",
                    },

                    sectionEVLabel(nil),
                }
            end

            appendCards(nil)

            --the start-of-encounter actions: add a plain group, or open a
            --reinforcement wave (which renders as its own section below the
            --start groups). Adding a wave also adds its first group and
            --makes it active so it is immediately ready to receive monsters.
            children[#children + 1] = gui.Panel {
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",

                addGroupButton(nil),

                gui.Button {
                    classes = { "sizeS" },
                    width = 180,
                    halign = "left",
                    lmargin = 8,
                    vmargin = 4,
                    text = "Add Reinforcements",
                    hover = gui.Tooltip("Add a reinforcement wave. Its groups arrive on a later round instead of at the start of the encounter."),
                    press = function(element)
                        local wave = encounter:AddWave()
                        encounter:AddGroup()
                        local newGroup = encounter.groups[#encounter.groups]
                        newGroup.wave = wave.id
                        state.activeGroup = newGroup
                        rebuild()
                    end,
                },
            }

            --one section per reinforcement wave.
            for waveIndex, wave in ipairs(encounter:try_get("waves", {})) do
                local thisWave = wave

                children[#children + 1] = gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    tmargin = 12,
                    bmargin = 2,

                    gui.Input {
                        classes = { "form" },
                        width = 170,
                        height = 24,
                        valign = "center",
                        fontSize = 13,
                        text = thisWave.name,
                        characterLimit = 24,
                        change = function(element)
                            local newname = element.text
                            if newname == "" then
                                newname = "Reinforcements"
                            end
                            thisWave.name = newname
                            element.text = newname
                        end,
                    },

                    gui.Dropdown {
                        classes = { "form" },
                        width = 120,
                        height = 24,
                        valign = "center",
                        lmargin = 8,
                        fontSize = 12,
                        options = {
                            { id = "2", text = "Round 2" },
                            { id = "3", text = "Round 3" },
                            { id = "4", text = "Round 4" },
                            { id = "5", text = "Round 5" },
                            { id = "6", text = "Round 6" },
                            { id = "every", text = "Every round" },
                        },
                        idChosen = tostring(thisWave.round),
                        change = function(element)
                            if element.idChosen == "every" then
                                thisWave.round = "every"
                            else
                                thisWave.round = tonumber(element.idChosen)
                            end
                        end,
                    },

                    sectionEVLabel(thisWave.id),

                    gui.Button {
                        classes = { "deleteButton", "sizeXs" },
                        valign = "center",
                        halign = "right",
                        press = function(element)
                            --groups assigned to the removed wave fall back to the
                            --start of the encounter.
                            for _, group in ipairs(encounter.groups) do
                                if group.wave == thisWave.id then
                                    group.wave = nil
                                end
                            end
                            table.remove(encounter.waves, waveIndex)
                            rebuild()
                        end,
                    },
                }

                appendCards(thisWave.id)
                children[#children + 1] = addGroupButton(thisWave.id)
            end

            element.children = children
        end,
    }
end

-- ===========================================================================
-- Details section (victory condition, victories awarded, rule sets)
-- ===========================================================================

--A "Rule Sets" editor for the encounter dialog: attach any number of named encounter rule-sets
--(authored in the compendium under Rules -> Encounter Rules) to this encounter. Stored as a set
--of EncounterRuleSet ids in encounter.ruleSets ({[id]=true}). Built on the standard gui.SetEditor
--control. Actually activating these rules while the encounter runs is a future phase; for now this
--only records the attachments.
local function createRuleSetsPanel(encounter, onChange)
    local options = {}
    for setid, ruleSet in unhidden_pairs(dmhub.GetTable(EncounterRuleSet.tableName) or {}) do
        options[#options + 1] = { id = setid, text = ruleSet.name }
    end
    table.sort(options, function(a, b) return a.text < b.text end)

    --Normalize to the {[id]=true} set form gui.SetEditor expects, tolerating any earlier
    --array-form data so previously-attached sets are not silently dropped.
    local value = {}
    for k, v in pairs(encounter:try_get("ruleSets", {})) do
        if type(k) == "number" then
            value[v] = true
        else
            value[k] = true
        end
    end

    return gui.SetEditor {
        width = "100%",
        halign = "left",
        valign = "top",
        tmargin = 4,
        addItemText = "Add Rule Set...",
        options = options,
        value = value,
        change = function(element, newValue)
            encounter.ruleSets = DeepCopy(newValue)
            if onChange ~= nil then
                onChange()
            end
        end,
    }
end

-- ===========================================================================
-- Footer actions: Place on Map
-- ===========================================================================

--"Place on Map" from the builder uses the engine's click-to-place path: a
--focused panel exposing data.encounter is consulted by the engine (via
--dmhub.GetSelectedEncounter) when the DM clicks the map, which spawns the
--whole roster there and fires the spawnFromBestiary event with the spawned
--charids. We show a small focused banner carrying the encounter, then (like
--DocumentSystem/RichEncounter.lua) tag the reinforcement-wave tokens once
--they resolve and ready the encounter for the combat-setup dialog.
--
--opts (all optional):
--  message   : banner text override.
--  onSpawned : called with the spawned charids INSTEAD of the default
--              ready-the-encounter behavior (used for per-group placement).
--  onClosed  : called when the banner goes away, whether by spawning or
--              cancelling (used to restore a hidden editor).
--(forward-declared above the group cards, which trigger per-group placement)
ShowPlacementBanner = function(encounter, opts)
    opts = opts or {}
    local banner

    banner = gui.Panel {
        classes = { "framedPanel" },
        styles = ThemeEngine.GetStyles(),
        width = 640,
        --auto height with a bounded label: long messages wrap to a second
        --line and the box grows instead of pushing the button outside it.
        height = "auto",
        minHeight = 54,
        halign = "center",
        valign = "top",
        vmargin = 80,
        flow = "horizontal",
        hpad = 14,
        vpad = 12,
        borderBox = true,
        bgimage = true,

        data = {
            encounter = encounter,
            monitorid = nil,
        },

        create = function(element)
            gui.SetFocus(element)

            --the click that opened this banner can still be bubbling: the
            --encounter card's own click handler selects the card (SetFocus)
            --AFTER this banner takes focus, which would deafen the spawn
            --handler below -- every map click then spawns tokens the banner
            --ignores and it never resolves. Re-assert focus once the opening
            --gesture has fully settled.
            dmhub.Schedule(0.1, function()
                if mod.unloaded or not element.valid then
                    return
                end
                if not element:HasClass("focus") then
                    gui.SetFocus(element)
                end
            end)

            element.data.monitorid = dmhub.RegisterEventHandler("spawnFromBestiary", function(charids)
                if not element:HasClass("focus") then
                    return
                end

                gui.SetFocus(nil)

                if opts.onSpawned ~= nil then
                    opts.onSpawned(charids)
                    banner:DestroySelf()
                    return
                end

                --pre-select this encounter in the combat-setup dialog.
                Encounter.SetReadiedEncounter(encounter)

                --The engine places ALL of the encounter's monsters, including
                --reinforcement (wave) groups, as plain tokens. Tag the wave-group
                --tokens so wave deployment bookkeeping recognises them. The tokens
                --are not always queryable the instant this fires, so wait until
                --they resolve before tagging.
                local attempts = 20
                local function tagWhenReady()
                    if mod.unloaded then return end
                    local allReady = true
                    for _, cid in ipairs(charids) do
                        if dmhub.GetTokenById(cid or "") == nil then
                            allReady = false
                            break
                        end
                    end
                    if not allReady and attempts > 0 then
                        attempts = attempts - 1
                        dmhub.Schedule(0.1, tagWhenReady)
                        return
                    end
                    encounter:TagWaveTokensFromSpawn(charids)
                end
                tagWhenReady()

                banner:DestroySelf()
            end)
        end,

        destroy = function(element)
            if element.data.monitorid ~= nil then
                dmhub.DeregisterEventHandler(element.data.monitorid)
                element.data.monitorid = nil
            end
            if opts.onClosed ~= nil then
                opts.onClosed()
            end
        end,

        --clicking the banner re-asserts focus in case the user clicked away.
        press = function(element)
            gui.SetFocus(element)
        end,

        gui.Label {
            classes = { "sizeS" },
            width = "100%-110",
            height = "auto",
            valign = "center",
            text = opts.message or string.format("Click on the map to place %s", encounter:try_get("name", "the encounter")),
        },

        gui.Button {
            classes = { "sizeS" },
            width = 90,
            halign = "right",
            valign = "center",
            text = "Cancel",
            swallowPress = true,
            press = function(element)
                banner:DestroySelf()
            end,
        },
    }

    GameHud.instance.documentsPanel:AddChild(banner)
end

--A small focused banner shown while a staged group's tokens are on the map
--for arranging; the button (or destroying the banner) returns to the builder
--via opts.onClosed.
ShowStagingBanner = function(message, opts)
    opts = opts or {}
    local banner

    banner = gui.Panel {
        classes = { "framedPanel" },
        styles = ThemeEngine.GetStyles(),
        width = 680,
        --auto height with a bounded label: long messages wrap to a second
        --line and the box grows instead of pushing the button outside it.
        height = "auto",
        minHeight = 54,
        halign = "center",
        valign = "top",
        vmargin = 80,
        flow = "horizontal",
        hpad = 14,
        vpad = 12,
        borderBox = true,
        bgimage = true,

        destroy = function(element)
            if opts.onClosed ~= nil then
                opts.onClosed()
            end
        end,

        gui.Label {
            classes = { "sizeS" },
            width = "100%-170",
            height = "auto",
            valign = "center",
            text = message,
        },

        gui.Button {
            classes = { "sizeS" },
            width = 150,
            halign = "right",
            valign = "center",
            text = "Back to Builder",
            press = function(element)
                banner:DestroySelf()
            end,
        },
    }

    GameHud.instance.documentsPanel:AddChild(banner)
end

-- ===========================================================================
-- Real placement: put the encounter on the map for play
-- ===========================================================================

--Spawn one group's monsters for real (combat-grade, mirroring
--LiveEncounter:DeployWave): initiative grouping, minion squads, balancing
--stamina, appears-gates, saved appearances and visibility. Slots with a
--saved position spawn there; slots without one spread in a 5-wide grid
--around fallbackAnchor. Tokens are tagged with the group's placement id
--(encounterStaged = false, so the builder never mistakes them for staging).
--Returns the initiative groupid and the spawned charids.
local function SpawnGroupForReal(group, numHeroes, fallbackAnchor)
    local minionName = nil
    local nsquads = 1
    for monsterid, quantity in pairs(group.monsters) do
        local monsterAsset = assets.monsters[monsterid]
        if monsterAsset ~= nil and monsterAsset.properties:IsMonster() and monsterAsset.properties.minion then
            minionName = monsterAsset.properties.monster_type
            if quantity >= 8 then
                nsquads = math.ceil(quantity / (group.squadSize or 4))
            end
            break
        end
    end

    local squadNames = nil
    if minionName ~= nil then
        squadNames = {}
        for i = 1, nsquads do
            squadNames[#squadNames + 1] = monster.FindFreshSquadName(minionName)
        end
    end

    local baseX = round(fallbackAnchor.x)
    local baseY = round(fallbackAnchor.y)
    local floorIndex = game.currentFloorIndex

    local groupid = dmhub.GenerateGuid()
    local charids = {}
    local slot = 1
    local fallbackIndex = 0
    local nsquad = 1

    for monsterid, quantity in pairs(group.monsters) do
        quantity = Encounter.AdjustedMonsterQuantity(group, monsterid, quantity, numHeroes)
        for i = 1, quantity do
            local loc = (group.spawnlocs or {})[slot]
            if loc ~= nil then
                if not loc.isValidFloor then
                    loc = loc.withCurrentFloor
                end
            else
                local col = fallbackIndex % 5
                local row = math.floor(fallbackIndex / 5)
                loc = core.Loc { x = baseX + col, y = baseY + row, floorIndex = floorIndex }
                fallbackIndex = fallbackIndex + 1
            end

            local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true })
            if token ~= nil then
                token.properties.initiativeGrouping = groupid
                token.properties:OnCreateFromBestiary(token, groupid)
                token.properties.minHeroes = (group.monsterMinHeroes or {})[monsterid] or group.minHeroes

                if group.placementid ~= nil then
                    token.properties.encounterPlacementId = group.placementid
                    token.properties.encounterSpawnSlot = slot
                    token.properties.encounterStaged = false
                end

                local appearanceInfo = (group.appearances or {})[slot]
                if type(appearanceInfo) == "string" then
                    token:SerializeAppearanceFromString(appearanceInfo)
                end
                if (group.invisibleToPlayers or {})[slot] then
                    token.invisibleToPlayers = true
                end

                local balancing = group.balancing
                if balancing ~= nil then
                    local info = balancing[numHeroes]
                    if info ~= nil and type(info.stamina) == "number" then
                        token.properties.max_hitpoints = info.stamina
                    end
                end

                if squadNames ~= nil then
                    token.properties.minionSquad = squadNames[nsquad]
                    nsquad = nsquad + 1
                    if nsquad > #squadNames then
                        nsquad = 1
                    end
                end

                token:UploadToken()
                charids[#charids + 1] = token.charid
            end

            slot = slot + 1
        end
    end

    return groupid, charids
end

--Place the encounter on the map for play. Staged tokens are collected first
--(positions banked, tokens removed) so the freshest arrangement wins and
--nothing double-spawns. Groups with saved positions on THIS map spawn there
--immediately; the rest go through one click-to-place banner. Wave groups are
--never placed up front -- they arrive via the reinforcements strip
--(LiveEncounter:DeployWave), which reads the same banked positions.
--
--opts:
--  start      -- open combat setup (Draw Steel!) once everything is placed
--  persist    -- called if collecting staged tokens mutated the encounter
--  onComplete -- placement finished (start flows may already be underway)
--  onCancel   -- the click-to-place step was cancelled; everything this call
--                spawned has been removed again
local function PlaceEncounterForReal(encounter, party, opts)
    opts = opts or {}
    local queue = dmhub.initiativeQueue
    local queueActive = queue ~= nil and not queue.hidden

    local function Proceed()
        --collect any staged tokens: bank the live arrangement, then clear
        --the props off the map so the real spawn cannot double them.
        local mutated = false
        for _, group in ipairs(encounter.groups) do
            local staged = PlacedTokensForGroup(group)
            if #staged > 0 then
                BankGroupPositions(group, encounter.saveAppearances)
                local charids = {}
                for _, token in ipairs(staged) do
                    charids[#charids + 1] = token.charid
                end
                game.DeleteCharacters(charids)
                mutated = true
            end
        end
        if mutated and opts.persist ~= nil then
            opts.persist()
        end

        --tokens from a previous real placement of this plan are still on the
        --map (encounterStaged == false): pressing Start twice should not
        --silently double the encounter.
        local alreadyPlaced = 0
        local placementids = {}
        for _, group in ipairs(encounter.groups) do
            if group.placementid ~= nil then
                placementids[group.placementid] = true
            end
        end
        for _, token in ipairs(dmhub.allTokens) do
            local pid = nil
            pcall(function() pid = token.properties:try_get("encounterPlacementId") end)
            if pid ~= nil and placementids[pid] then
                local staged = nil
                pcall(function() staged = token.properties:try_get("encounterStaged") end)
                if staged == false then
                    alreadyPlaced = alreadyPlaced + 1
                end
            end
        end
        if alreadyPlaced > 0 and not opts.placeAgainConfirmed then
            gui.ModalMessage {
                title = "Already on the Map",
                message = string.format("%d of this encounter's monsters are already placed on this map. Place another copy anyway?", alreadyPlaced),
                options = {
                    {
                        text = "Cancel",
                        execute = function()
                            gui.CloseModal()
                            if opts.onCancel ~= nil then
                                opts.onCancel()
                            end
                        end,
                    },
                    {
                        text = "Place Again Anyway",
                        execute = function()
                            gui.CloseModal()
                            local optsAgain = {}
                            for k, v in pairs(opts) do
                                optsAgain[k] = v
                            end
                            optsAgain.placeAgainConfirmed = true
                            PlaceEncounterForReal(encounter, party, optsAgain)
                        end,
                    },
                },
            }
            return
        end

        local numHeroes = party.numHeroes

        --split placeable groups: saved positions on this map spawn
        --directly; everything else goes through click-to-place.
        local directGroups = {}
        local clickGroups = {}
        for _, group in ipairs(encounter.groups) do
            if group.wave == nil and AdjustedGroupCount(group, numHeroes) > 0 then
                if group.spawnlocs ~= nil and #group.spawnlocs > 0 and not GroupStagedOnOtherMap(group) then
                    directGroups[#directGroups + 1] = group
                else
                    clickGroups[#clickGroups + 1] = group
                end
            end
        end

        local spawnedCharids = {}
        local spawnedGroupids = {}

        for _, group in ipairs(directGroups) do
            local anchor = group.spawnlocs[1] or dmhub.cameraPosition
            local groupid, charids = SpawnGroupForReal(group, numHeroes, anchor)
            spawnedGroupids[#spawnedGroupids + 1] = groupid
            for _, cid in ipairs(charids) do
                spawnedCharids[#spawnedCharids + 1] = cid
            end
        end

        local function Finish()
            --engine-placed tokens are not always queryable the instant the
            --spawn event fires; opening combat setup before they resolve
            --leaves them out of the participating pool. Wait for them.
            local attempts = 20
            local function proceed()
                if mod.unloaded then return end

                local allReady = true
                for _, cid in ipairs(spawnedCharids) do
                    if dmhub.GetTokenById(cid or "") == nil then
                        allReady = false
                        break
                    end
                end
                if not allReady and attempts > 0 then
                    attempts = attempts - 1
                    dmhub.Schedule(0.1, proceed)
                    return
                end

                game.UpdateCharacterTokens()
                Encounter.SetReadiedEncounter(encounter)

                if queueActive then
                    --mid-combat: the new arrivals join the running fight,
                    --same as a deployed wave; no combat-setup dialog.
                    for _, groupid in ipairs(spawnedGroupids) do
                        queue:SetInitiative(groupid, 0, 0)
                    end
                    dmhub:UploadInitiativeQueue()
                elseif opts.start then
                    Encounter.DrawSteelWithEncounter(encounter, spawnedCharids)
                end

                if opts.onComplete ~= nil then
                    opts.onComplete()
                end
            end
            proceed()
        end

        if #clickGroups == 0 then
            Finish()
            return
        end

        --one click places the remaining groups; cancelling removes
        --everything this action spawned so it stays atomic.
        local placeEncounter = DeepCopy(encounter)
        placeEncounter.groups = {}
        for _, group in ipairs(clickGroups) do
            local copy = DeepCopy(group)
            copy.wave = nil
            placeEncounter.groups[#placeEncounter.groups + 1] = copy
        end
        placeEncounter.waves = {}

        local clickResolved = false
        ShowPlacementBanner(placeEncounter, {
            message = string.format("Click on the map to place the remaining monsters of %s", encounter:try_get("name", "the encounter")),
            onSpawned = function(charids)
                clickResolved = true
                for _, cid in ipairs(charids) do
                    spawnedCharids[#spawnedCharids + 1] = cid
                end
                Finish()
            end,
            onClosed = function()
                if clickResolved then
                    return
                end
                if #spawnedCharids > 0 then
                    game.DeleteCharacters(spawnedCharids)
                end
                if opts.onCancel ~= nil then
                    opts.onCancel()
                end
            end,
        })
    end

    --starting on top of a running combat must not clobber the live queue
    --(round counter, hero stats, deployed waves all live there). Skipped on
    --the place-again re-entry, which already confirmed once.
    if opts.start and queueActive and not opts.placeAgainConfirmed then
        gui.ModalMessage {
            title = "Combat Is Already Running",
            message = "Starting this encounter now adds its monsters to the current combat instead of beginning a new one.",
            options = {
                {
                    text = "Cancel",
                    execute = function()
                        gui.CloseModal()
                        if opts.onCancel ~= nil then
                            opts.onCancel()
                        end
                    end,
                },
                {
                    text = "Add to Current Combat",
                    execute = function()
                        gui.CloseModal()
                        Proceed()
                    end,
                },
            },
        }
        return
    end

    Proceed()
end

-- ===========================================================================
-- The encounter builder editor
-- ===========================================================================

function Encounter.Editor(self, options)
    options = options or {}

    local resultPanel

    local party = DefaultParty()

    --the group new monsters are added to; defaults to the first group. Note
    --AddGroup/AddWave deep-copy their arrays, so state.activeGroup must be
    --re-pointed after any structural change (the rebuild path does this).
    if #self.groups == 0 then
        self:AddGroup()
    end

    --Legacy migration: the appears gate used to live on the whole group
    --(group.minHeroes); it is now scoped per monster. Convert a group-level
    --gate into the equivalent per-monster gates when the encounter is edited.
    --Spawn behavior is identical: every converted monster contributes 0
    --below the gate via Encounter.AdjustedMonsterQuantity.
    for _, group in ipairs(self.groups) do
        if group.minHeroes ~= nil then
            group.monsterMinHeroes = group.monsterMinHeroes or {}
            for monsterid, _ in pairs(group.monsters) do
                if group.monsterMinHeroes[monsterid] == nil then
                    group.monsterMinHeroes[monsterid] = group.minHeroes
                end
            end
            group.minHeroes = nil
        end
    end
    local state = {
        activeGroup = self.groups[1],
    }

    local function refresh()
        if resultPanel == nil or not resultPanel.valid then
            return
        end
        resultPanel:FireEventTree("refreshBuilder")
    end

    local function rebuild()
        if resultPanel == nil or not resultPanel.valid then
            return
        end
        resultPanel:FireEventTree("rebuildGroups")
        resultPanel:FireEventTree("refreshBuilder")
    end

    local function addMonster(info)
        local group = state.activeGroup
        if group == nil then
            self:AddGroup()
            group = self.groups[#self.groups]
            state.activeGroup = group
        end

        local step = cond(info.minion, 4, 1)
        group.monsters[info.monsterid] = (group.monsters[info.monsterid] or 0) + step
        rebuild()
    end

    --header badges: live creature count and EV total.
    local creatureBadge = gui.Label {
        classes = { "encounterBadge" },
        width = "auto",
        height = "auto",
        valign = "center",
        rmargin = 6,
        text = "",
        refreshBuilder = function(element)
            local count = 0
            for _, group in ipairs(self.groups) do
                count = count + AdjustedGroupCount(group, party.numHeroes)
            end
            element.text = string.format("%d creatures", count)
        end,
    }

    local evBadge = gui.Label {
        classes = { "encounterBadge" },
        width = "auto",
        height = "auto",
        valign = "center",
        text = "",
        refreshBuilder = function(element)
            local ev = 0
            for _, group in ipairs(self.groups) do
                ev = ev + AdjustedGroupEV(group, party.numHeroes)
            end
            element.text = string.format("%d EV", ev)
        end,
    }

    --rule sets are a rarely-used whole-encounter setting: they live behind a
    --small settings cog in the header, with a count label when any are
    --attached, instead of taking a dedicated section in the layout.
    local ruleSetsCountLabel = gui.Label {
        classes = { "fgMuted", "sizeXxs" },
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 4,
        text = "",
        refreshBuilder = function(element)
            local count = 0
            for _, v in pairs(self:try_get("ruleSets", {})) do
                if v then
                    count = count + 1
                end
            end
            element:SetClass("hidden", count == 0)
            element.text = string.format("%d rule set%s", count, cond(count == 1, "", "s"))
        end,
    }

    local ruleSetsButton = gui.SettingsButton {
        width = 16,
        height = 16,
        valign = "center",
        lmargin = 12,
        hover = gui.Tooltip("Rule sets attached to this encounter."),
        press = function(element)
            element.popupsInheritStyles = true
            element.popup = gui.Panel {
                classes = { "bordered", "bg" },
                width = 380,
                height = "auto",
                flow = "vertical",
                hpad = 14,
                vpad = 12,
                borderBox = true,

                FieldCaption("Rule sets", "left"),

                createRuleSetsPanel(self, refresh),
            }
        end,
    }

    --Bank any groups placed on the map from this builder: record each tagged
    --token's position (and appearance/visibility) into its group in spawn-slot
    --order. Staged tokens are only removed from the map when deleteTokens is
    --true -- saving the plan mid-arrangement must not yank the tokens out
    --from under the Director (collecting is the per-group action).
    local function BankPlacedGroups(deleteTokens)
        local toDelete = {}
        for _, group in ipairs(self.groups) do
            local tokens = BankGroupPositions(group, self.saveAppearances)
            if deleteTokens then
                for _, token in ipairs(tokens) do
                    toDelete[#toDelete + 1] = token.charid
                end
            end
        end
        if #toDelete > 0 then
            game.DeleteCharacters(toDelete)
        end
    end

    --Upload the plan to wherever it lives (the encounters table, or the
    --journal widget's save callback when the editor was opened from one).
    local function PersistPlan()
        if options.save then
            options.save()
        else
            analytics.Event {
                type = "create_encounter",
                encounter = self.name,
                eds = self:CountEDS(),
            }
            dmhub.SetAndUploadTableItem("encounters", self)
        end
    end

    --Dirty tracking for the Save button: compare a serialized snapshot of the
    --plan against the last-saved baseline. Serialization can fail on exotic
    --values; treat failure as "dirty" so Save is never wrongly disabled.
    local function SnapshotPlan()
        local ok, snapshot = pcall(dmhub.ToJson, self)
        if not ok then
            return nil
        end
        return snapshot
    end

    local m_savedSnapshot = SnapshotPlan()

    local function PlanIsDirty()
        if m_savedSnapshot == nil then
            return true
        end
        local current = SnapshotPlan()
        return current == nil or current ~= m_savedSnapshot
    end

    --Save the plan: bank staged positions (tokens stay out for arranging),
    --persist, and reset the dirty baseline.
    local function SavePlan()
        BankPlacedGroups(false)
        PersistPlan()
        m_savedSnapshot = SnapshotPlan()
    end

    local function StagedGroupNames()
        local names = {}
        for i, group in ipairs(self.groups) do
            if #PlacedTokensForGroup(group) > 0 then
                names[#names + 1] = GroupName(self, group, i)
            end
        end
        return names
    end

    resultPanel = gui.Panel {

        width = "100%",
        height = "100%",
        flow = "vertical",
        hpad = 16,
        vpad = 16,
        borderBox = true,

        --populated after construction with the close-prompt hooks; see the
        --assignments below the constructor.
        data = {},

        --header: editable encounter name + live badges.
        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 4,

            gui.Label {
                classes = { "sizeL", "bold" },
                width = "auto",
                height = "auto",
                minWidth = 200,
                halign = "left",
                valign = "center",
                textAlignment = "left",
                text = self.name,
                characterLimit = 40,
                editable = true,
                change = function(label)
                    self.name = label.text
                end,
            },

            gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                rmargin = 30,

                creatureBadge,
                evBadge,
                ruleSetsButton,
                ruleSetsCountLabel,
            },
        },

        CreatePartyBar(self, party, refresh, CreateBudgetDial(self, party)),

        --the two-pane body: bestiary browser left, composition right.
        gui.Panel {
            width = "100%",
            height = "100% available",
            flow = "horizontal",
            tmargin = 6,

            CreateBestiaryPane(party, addMonster),

            gui.Panel {
                width = "100%-352",
                height = "100%",
                lmargin = 12,
                flow = "vertical",
                vscroll = true,

                CreateWaveSections {
                    encounter = self,
                    party = party,
                    state = state,
                    refresh = refresh,
                    rebuild = rebuild,
                },
            },
        },

        --footer: the appearances option and workflow narration sit above the
        --action buttons.
        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 10,

            gui.Check {
                classes = { "form" },
                text = "Save monster appearances",
                value = self.saveAppearances,
                halign = "left",
                bmargin = 6,
                change = function(element)
                    self.saveAppearances = element.value
                end,
            },

            gui.Label {
                classes = { "fgMuted", "sizeXs" },
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 6,
                text = "Stage groups to set starting positions. Positions save with the plan; Start Encounter places everyone and opens combat setup.",
                refreshBuilder = function(element)
                    local anyMonsters = false
                    for _, group in ipairs(self.groups) do
                        for _ in pairs(group.monsters) do
                            anyMonsters = true
                            break
                        end
                        if anyMonsters then break end
                    end
                    element:SetClass("hidden", not anyMonsters)
                end,
            },

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "horizontal",

                gui.Button {
                    classes = { "sizeM" },
                    halign = "left",
                    text = "Place on Map",
                    hover = gui.Tooltip("Place the monsters at their saved positions without starting combat."),
                    press = function(button)
                        local count = 0
                        for _, group in ipairs(self.groups) do
                            count = count + AdjustedGroupCount(group, party.numHeroes)
                        end
                        if count == 0 then
                            gui.ModalMessage {
                                title = "Nothing to Place",
                                message = "Add monsters to the encounter before placing it on the map.",
                            }
                            return
                        end

                        SavePlan()
                        local editorPanel = button:FindParentWithClass("editorPanel")
                        editorPanel:SetClass("hidden", true)
                        PlaceEncounterForReal(self, party, {
                            persist = PersistPlan,
                            onComplete = function()
                                if editorPanel ~= nil and editorPanel.valid then
                                    editorPanel:DestroySelf()
                                end
                            end,
                            onCancel = function()
                                if editorPanel ~= nil and editorPanel.valid then
                                    editorPanel:SetClass("hidden", false)
                                    refresh()
                                end
                            end,
                        })
                    end,
                },

                gui.Button {
                    classes = { "sizeM" },
                    halign = "left",
                    lmargin = 8,
                    text = "Clear All",
                    press = function(button)
                        gui.ModalMessage {
                            title = "Clear Encounter",
                            message = "Remove every group, wave, and monster from this encounter?",
                            options = {
                                {
                                    text = "Cancel",
                                    execute = function()
                                        gui.CloseModal()
                                    end,
                                },
                                {
                                    text = "Clear",
                                    execute = function()
                                        gui.CloseModal()
                                        self.groups = { { monsters = {} } }
                                        self.waves = {}
                                        state.activeGroup = self.groups[1]
                                        rebuild()
                                    end,
                                },
                            },
                        }
                    end,
                },

                gui.Label {
                    classes = { "fgMuted", "sizeXs", "hidden" },
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    rmargin = 10,
                    text = "Saved",
                    savedFlash = function(element)
                        element:SetClass("hidden", false)
                        element:ScheduleEvent("savedFlashEnd", 1.4)
                    end,
                    savedFlashEnd = function(element)
                        element:SetClass("hidden", true)
                    end,
                },

                gui.Button {
                    classes = { "sizeM" },
                    halign = "right",
                    text = options.mode or "Save",
                    refreshBuilder = function(element)
                        element:SetClass("disabled", not PlanIsDirty())
                    end,
                    press = function(button)
                        SavePlan()
                        refresh()
                        button.parent:FireEventTree("savedFlash")
                    end,
                },

                gui.Button {
                    classes = { "sizeM" },
                    halign = "right",
                    lmargin = 8,
                    text = "Start Encounter",
                    hover = gui.Tooltip("Save the plan, place monsters at their saved positions, and open combat setup."),
                    press = function(button)
                        local count = 0
                        for _, group in ipairs(self.groups) do
                            count = count + AdjustedGroupCount(group, party.numHeroes)
                        end
                        if count == 0 then
                            gui.ModalMessage {
                                title = "Nothing to Start",
                                message = "Add monsters to the encounter before starting it.",
                            }
                            return
                        end

                        SavePlan()
                        local editorPanel = button:FindParentWithClass("editorPanel")
                        editorPanel:SetClass("hidden", true)
                        PlaceEncounterForReal(self, party, {
                            start = true,
                            persist = PersistPlan,
                            onComplete = function()
                                if editorPanel ~= nil and editorPanel.valid then
                                    editorPanel:DestroySelf()
                                end
                            end,
                            onCancel = function()
                                if editorPanel ~= nil and editorPanel.valid then
                                    editorPanel:SetClass("hidden", false)
                                    refresh()
                                end
                            end,
                        })
                    end,
                },
            },
        },
    }

    --hooks for the dialog's close button: it lives outside this function's
    --scope (CreateEditorDialog) but needs to ask about staged tokens.
    resultPanel.data.stagedGroupNames = StagedGroupNames
    resultPanel.data.collectAndSave = function(deleteTokens)
        BankPlacedGroups(deleteTokens)
        PersistPlan()
    end
    resultPanel.data.discardStaged = function()
        local charids = {}
        for _, group in ipairs(self.groups) do
            for _, token in ipairs(PlacedTokensForGroup(group)) do
                charids[#charids + 1] = token.charid
            end
        end
        if #charids > 0 then
            game.DeleteCharacters(charids)
        end
    end

    rebuild()
    return resultPanel
end

function Encounter.CreateEditorDialog(encounter, options)
    local editorPanel

    local editorContent = Encounter.Editor(encounter, options)

    editorPanel = gui.Panel {

        classes = { "editorPanel" },
        styles = BuilderStyles(),

        halign = "center",
        valign = "center",
        width = 1240,
        height = 920,

        gui.Panel {

            classes = { "dialog" },

            halign = "center",
            width = "100%",
            height = "100%",

            editorContent,

            gui.Button {
                classes = { "closeButton" },
                halign = "right",
                valign = "top",
                press = function()
                    --staged tokens still on the map: make the Director decide
                    --what happens to the arrangement before the builder goes
                    --away. "Leave Them" still banks positions and saves so the
                    --staging is never orphaned from the plan that owns it.
                    local stagedNames = editorContent.data.stagedGroupNames()
                    if #stagedNames == 0 then
                        editorPanel:DestroySelf()
                        return
                    end

                    local subject
                    if #stagedNames == 1 then
                        subject = string.format("%s is still staged on the map.", stagedNames[1])
                    else
                        subject = string.format("%d groups are still staged on the map.", #stagedNames)
                    end

                    gui.ModalMessage {
                        title = "Staged Tokens on the Map",
                        message = subject .. " Save those positions before closing?",
                        options = {
                            {
                                text = "Cancel",
                                execute = function()
                                    gui.CloseModal()
                                end,
                            },
                            {
                                text = "Discard Positions",
                                execute = function()
                                    gui.CloseModal()
                                    editorContent.data.discardStaged()
                                    editorPanel:DestroySelf()
                                end,
                            },
                            {
                                text = "Leave Them on the Map",
                                execute = function()
                                    gui.CloseModal()
                                    editorContent.data.collectAndSave(false)
                                    editorPanel:DestroySelf()
                                end,
                            },
                            {
                                text = "Save Positions & Remove",
                                execute = function()
                                    gui.CloseModal()
                                    editorContent.data.collectAndSave(true)
                                    editorPanel:DestroySelf()
                                end,
                            },
                        },
                    }
                end,
            },

        }

    }

    ThemeEngine.OnThemeChanged(mod, function()
        if editorPanel ~= nil and editorPanel.valid then
            editorPanel.styles = BuilderStyles()
        end
    end)

    GameHud.instance.documentsPanel:AddChild(editorPanel)
end

CreateEncounterPanel = function()
    --- @type Panel

    local inspectorPanel

    inspectorPanel = gui.Panel {
        id = "inspector-panel",
        styles = ThemeEngine.GetStyles(),
        hpad = 6,
        width = "100%",
        height = "auto",
        flow = "vertical",
        monitorAssets = true,
        bgimage = true,
        bgcolor = "clear",

        xrightClick = function(panel)
            panel.popup = gui.ContextMenu {
                entries = {

                    {
                        text = "Add folder",
                        click = function()
                            panel.popup = nil
                            local newfolder = EncounterFolder.new {}
                            dmhub.SetAndUploadTableItem(EncounterFolder.tableName, newfolder)
                        end
                    }
                },
            }
        end,

        events = {
            create = function(panel)
                panel:FireEvent("update")
            end,

            refreshAssets = function(panel)
                panel:FireEvent("update")
            end,

            update = function(panel)
                local children = {}

                local encounters = dmhub.GetTable('encounters')
                local encounterfolders = dmhub.GetTable('encounterfolders')

                local index = 1

                for key, encounterfolder in unhidden_pairs(encounterfolders) do
                    local folder = gui.TreeNode {

                        text = encounterfolder.name,
                        width = "100%",
                        editable = true,
                        dragTarget = true,

                        change = function(self, newname)
                            encounterfolder.name = newname
                            dmhub.SetAndUploadTableItem(encounterfolder.tableName, encounterfolder)
                        end,

                        contentPanel = gui.Panel {

                            classes = { "bg" },
                            height = 100,
                            width = 100,
                        }

                    }

                    children[index] = folder
                    index = index + 1
                end

                for key, encounter in unhidden_pairs(encounters) do
                    local monstertable = encounter.monsters

                    --choose boss monster to be 'head' of the encounter

                    local highestev = 0
                    local headmonster = nil

                    for key, quantity in pairs(monstertable) do
                        local currentmonster = assets.monsters[key]

                        if headmonster == nil then
                            headmonster = currentmonster
                        end

                        if currentmonster.properties:EV() > highestev then
                            highestev = currentmonster.properties:EV()
                            headmonster = currentmonster
                        end
                    end

                    local headmonsteravatar = true

                    if headmonster ~= nil then
                        headmonsteravatar = headmonster.appearance.portraitId
                    end

                    --boss/headmonster code over

                    children[index] = gui.Panel {

                        classes = { "featureCard" },
                        width = "90%",
                        height = 110,
                        halign = "left",
                        flow = "vertical",
                        pad = 1,
                        vmargin = 8,
                        draggable = true,

                        canDragOnto = function(self, target)
                            return target ~= nil and target:HasClass("folder")
                        end,

                        drag = function(self, target)
                        end,

                        data = {
                            encounter = encounter,
                        },

                        click = function(self)
                            gui.SetFocus(self)
                            for _, sibling in ipairs(self.parent.children) do
                                sibling:SetClass("selected", false)
                            end
                            self:SetClass("selected", true)
                        end,

                        --king panel for name and difficulty
                        gui.Panel {

                            classes = { "featureCardHeader", "expanded" },
                            width = "100%",
                            height = "23%",
                            flow = "horizontal",

                            gui.Label {

                                text = string.format("%s", encounter.name),
                                halign = "left",
                                valign = "center",
                                height = "auto",
                                width = "auto",
                                fontSize = 16,
                                lmargin = 12,

                            },

                            gui.Label {

                                text = string.format("EV: %d", encounter:CountEDS()),
                                halign = "right",
                                valign = "center",
                                height = "auto",
                                width = "auto",
                                fontSize = 16,
                                rmargin = 12,

                                thinkTime = 0.2,

                                think = function(label)
                                    label.text = string.format("EV: %d", encounter:CountEDS())
                                end

                            },
                        },

                        gui.Panel {

                            classes = { "featureCardBody" },
                            width = "100%",
                            height = "85%",
                            flow = "horizontal",

                            --monster image panel
                            gui.Panel {

                                classes = { "image" },
                                width = "35%",
                                height = "91%",
                                bgimage = headmonsteravatar,
                                halign = "left",

                                thinkTime = 0.2,

                                think = function(panel)
                                    local mainmonster = Encounter.MainMonster(encounter)
                                    if mainmonster ~= nil then
                                        panel.bgimage = mainmonster.appearance:GetPortraitId()
                                    end
                                end

                            },

                            --king panel for monster list
                            gui.Panel {

                                vscroll = true,
                                height = "auto",
                                maxHeight = 80,
                                width = "65%",
                                gui.Label {

                                    width = "100%",
                                    height = "100%",
                                    flow = "vertical",

                                    lmargin = 5,
                                    fontSize = 16,
                                    textAlignment = "TopLeft",
                                    text = Encounter.Describe(encounter),

                                },

                            },

                        },

                        gui.Button {
                            classes = { "deleteButton", "sizeXs" },
                            x = 18,

                            floating = true,
                            halign = "right",
                            valign = "top",
                            press = function(element)
                                encounter.hidden = true
                                dmhub.SetAndUploadTableItem("encounters", encounter)
                                inspectorPanel:FireEvent("update")
                            end,
                        },

                        gui.Button {
                            classes = { "settingsButton", "sizeXs" },
                            x = 18,
                            y = 20,
                            floating = true,
                            halign = "right",
                            valign = "top",

                            swallowPress = true,
                            press = function(element)
                                local encounterCopy = DeepCopy(encounter)
                                encounterCopy:CreateEditorDialog { mode = "Save" }
                            end,
                        },

                        --start the saved plan without reopening the editor:
                        --place at saved positions and open combat setup.
                        --Named in full: a bare "Start" reads as "start the
                        --builder", which is the opposite of what it does.
                        gui.Button {
                            classes = { "sizeXs" },
                            floating = true,
                            halign = "right",
                            valign = "bottom",
                            width = 110,
                            rmargin = 6,
                            bmargin = 4,
                            text = "Start Encounter",
                            hover = gui.Tooltip("Place monsters at their saved positions and open combat setup."),
                            swallowPress = true,
                            press = function(element)
                                PlaceEncounterForReal(encounter, DefaultParty(), {
                                    start = true,
                                    persist = function()
                                        dmhub.SetAndUploadTableItem("encounters", encounter)
                                    end,
                                })
                            end,
                        },

                    }

                    index = index + 1
                end

                panel.children = children
            end,
        }
    }

    local addEncounterButton = gui.Button {

        classes = { "addButton", "sizeXs" },
        halign = "center",

        click = function(element)
            local newEncounter = Encounter.new()
            Encounter.CreateEditorDialog(newEncounter, { mode = "Create" })
        end

    }

    local resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        inspectorPanel,
        addEncounterButton,

    }

    ThemeEngine.OnThemeChanged(mod, function()
        if inspectorPanel ~= nil and inspectorPanel.valid then
            inspectorPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return resultPanel
end

dmhub.GetSelectedEncounter = function()
    if gui.GetFocus() == nil or (not gui.GetFocus().data.encounter) then
        return nil
    end

    local encounter = gui.GetFocus().data.encounter
    return encounter:CloneForNumberOfHeroes()
end

-- Global-search provider: encounters ("In this game"). DM-only content. The
-- Encounter creator selects encounters internally with no per-encounter
-- deep-link, so activation opens the panel (coarse open; exact-select is a
-- later refinement).
Search.RegisterProvider{
    id = "encounters",
    bucket = "ingame",
    typeLabel = "Encounter",
    enumerate = function(needle)
        if not dmhub.isDM then
            return {}
        end
        local results = {}
        local t = dmhub.GetTable("encounters") or {}
        for k,v in unhidden_pairs(t) do
            local name = (type(v) == "table" and rawget(v, "name")) or nil
            if type(name) == "string" and Search.MatchesText(name, needle) then
                results[#results+1] = {
                    name = name,
                    score = Search.Score(name, needle),
                    actionLabel = "Open in Encounter Builder",
                    activate = function()
                        DockablePanel.LaunchPanelByName("Encounter creator", "show")
                    end,
                }
            end
        end
        return results
    end,
}
