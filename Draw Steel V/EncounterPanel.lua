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
--            --whole-group gate: below it the group contributes no EV and
--            --places nothing, whatever monsterMinHeroes says.
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
    --This panel LISTS the game's encounters and creates new ones; the builder
    --that composes a single encounter is Encounter.Editor. Both used to be
    --called "Encounter creator", which made it impossible to say which one a
    --bug report meant.
    DockablePanel.Register {
        name = "Encounters",
        --Authored encounters are Director-only content: this lists the
        --encounters the director has authored, monster counts and all,
        --long before they are spawned. Players were seeing the whole
        --roster (reports JA9XNYG3, 8B4CZRUA, BUZ6SY69) because this flag
        --was missing while every other director panel had it. Same reason
        --the encounters search provider below returns nothing to players.
        dmonly = true,
        icon = "icons/standard/Icon_App_EncounterCreator.png",
        minHeight = 200,
        vscroll = true,
        content = function()
            track("panel_open", {
                --Deliberately still the old label: this is an analytics key, and
                --changing it would split the panel_open series at the rename
                --rather than continuing it.
                panel = "Encounter creator",
                dailyLimit = 30,
            })
            return CreateEncounterPanel()
        end,
    }
end

--Encounter is defined in Draw Steel Core Rules/MCDMEncounter.lua (data + rules).
--We re-fetch the registered type here so the UI methods below can attach to it.
--- @class Encounter: GameType
--- @field new fun(o?: table): Encounter
Encounter = RegisterGameType('Encounter')

--- @class EncounterFolder: GameType
--- @field new fun(o?: table): EncounterFolder
--- @field id string Key of this row in its data table; SetAndUploadTableItem sets it.
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
--Returns { monsterid, name, ev, level, minion, org, role, portraitId, meta,
--           keywords, searchText }
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

        info.roleText = props:try_get("role", "")

        local words = {}
        for word in string.gmatch(string.lower(info.roleText), "%a+") do
            words[#words + 1] = word
        end
        info.org = words[1]
        info.role = words[#words]

        --Keyword tags (Humanoid, Soulless, War Dog, ...) are stored as a SET:
        --the keyword is the key and the value is just true. Gathered here so
        --the search below can match them; the visible meta label is unchanged.
        local keywords = {}
        for kw, v in pairs(props:try_get("keywords") or {}) do
            if v == true and type(kw) == "string" and kw ~= "_luaTable" then
                keywords[#keywords + 1] = kw
            end
        end
        table.sort(keywords)
        info.keywords = keywords

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
    --Level() can come back as a non-integer float for some assets, and Lua's
    --%d rejects a float with no integer representation. Round for the label.
    meta = string.format("%s%sLvl %d", meta, cond(meta == "", "", " - "), math.floor((info.level or 0) + 0.5))
    if info.minion then
        meta = meta .. " - Minion"
    elseif info.org == "leader" then
        meta = meta .. " - Leader"
    elseif info.org == "solo" then
        meta = meta .. " - Solo"
    end
    info.meta = meta

    --Precomputed lowercase haystack for the bestiary search: the name, the
    --visible meta label, the full role string ("Minion Harrier" -- meta only
    --carries the last word plus the org suffix) and the keyword tags. Built
    --once per asset here, since BuildInfos caches these, rather than per
    --keystroke in FilteredInfos.
    local searchParts = { info.name or "", info.meta, info.roleText or "" }
    for _, kw in ipairs(info.keywords or {}) do
        searchParts[#searchParts + 1] = kw
    end
    info.searchText = string.lower(table.concat(searchParts, " "))

    return info
end

--Names for the implementation levels used by gui.ImplementationStatusIcon.
local g_implementationNames = {
    [0] = "Narrative",
    [1] = "Not Automated",
    [2] = "Partly Automated",
    [3] = "Mostly Automated",
    [4] = "Fully Automated",
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

--The stat block's natural width, and the padding gui.TooltipFrame puts on
--each side of it, so the frame that has to fit on screen is width + pad.
local FLYOUT_WIDTH = 800
local FLYOUT_FRAME_PAD = 24 * 2
--Never shrink past this -- a narrower stat block is unreadable, and by the
--time there is this little room beside a row the builder dialog itself
--(1240 wide) no longer fits on screen either.
local FLYOUT_MIN_WIDTH = 420
--Keep the frame off the screen edge.
local FLYOUT_EDGE_MARGIN = 8

--Fly out a monster's full stat block from the hovered element, mirroring the
--bestiary panel's hover preview (CharacterPanel.lua). Call from a `linger`
--handler. `halign` is the PREFERRED side of the anchor to open on -- the
--bestiary list sits on the left edge of the builder so its rows prefer
--"right", while the roster entries sit in the right-hand pane and prefer
--"left" -- but both the side and the width give way to what actually fits.
local function ShowMonsterStatBlockFlyout(element, monsterAsset, halign)
    if monsterAsset == nil then
        return
    end

    --Never let the flyout be clamped on top of the row it is anchored to.
    --The engine lines the flyout's far edge up with the anchor's near edge
    --and then clamps the result back onto the screen, so a flyout wider than
    --the room on its side gets slid back over the anchor. It then takes the
    --hover, the row dehovers, the tooltip is destroyed, the row is hovered
    --again and re-lingers -- an on/off flicker (report F9JP54F6). Passing
    --interactable = false does NOT avoid this: the frame's children still
    --take the hover. So the flyout has to genuinely fit -- open it on the
    --side that has room and shrink it to what is there.
    local width = FLYOUT_WIDTH
    local distances = element.distancesToScreenEdge
    if distances ~= nil then
        --x1/x2 = room to the left/right of the element, in SCREEN pixels,
        --while every width here is in UI units. uiscale converts.
        local preferLeft = (halign == "left")
        local roomLeft = distances.x1 / dmhub.uiscale
        local roomRight = distances.x2 / dmhub.uiscale
        local room = cond(preferLeft, roomLeft, roomRight)
        local roomOther = cond(preferLeft, roomRight, roomLeft)

        if room < FLYOUT_WIDTH + FLYOUT_FRAME_PAD + FLYOUT_EDGE_MARGIN and roomOther > room then
            halign = cond(preferLeft, "right", "left")
            room = roomOther
        end

        width = math.floor(room - FLYOUT_FRAME_PAD - FLYOUT_EDGE_MARGIN)
        width = math.max(FLYOUT_MIN_WIDTH, math.min(FLYOUT_WIDTH, width))
    end

    local lockedHeight = math.floor(dmhub.screenDimensionsBelowTitlebar.y * 0.6)
    --Reserved gutter: once the stat block overflows, the scroll viewport
    --shrinks by the scrollbar's width while children are still laid out at
    --the full width, clipping the right-aligned header text. Mirrors the
    --Bestiary tooltip in CharacterPanel.
    local panel = monsterAsset:Render {
        width = width,
        maxHeight = lockedHeight,
        vscroll = true,
        rpad = 12,
        borderBox = true,
    }

    if panel ~= nil then
        element.tooltip = gui.TooltipFrame(
            panel,
            {
                halign = halign,
                valign = "center",
                interactable = true,
            }
        )
    end
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
--Global on Encounter so headless spawners (Encounter of the Week) can apply
--the same group gating the builder does; aliased locally below.
function Encounter.AdjustedGroupCount(group, numHeroes)
    if group.minHeroes ~= nil and group.minHeroes > numHeroes then
        return 0
    end

    local total = 0
    for monsterid, quantity in pairs(group.monsters) do
        total = total + Encounter.AdjustedMonsterQuantity(group, monsterid, quantity, numHeroes)
    end
    return total
end

local AdjustedGroupCount = Encounter.AdjustedGroupCount

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

--The group's monsters in a stable order.
--
--pairs() over group.monsters has no defined order, and INSERTING a key can
--rehash the whole table -- so a spawn loop driven by pairs() reshuffles every
--monster the moment the roster is edited. Adding a captain to a group whose
--positions were already banked handed the captain a minion's saved tile
--(report BFUBGW59). Sorting by monsterid makes slot assignment reproducible
--across roster edits, app restarts, and the staging/real-placement pair.
local function SortedMonsterIds(group)
    local ids = {}
    for monsterid, _ in pairs(group.monsters or {}) do
        ids[#ids + 1] = monsterid
    end
    table.sort(ids)
    return ids
end

--Regroup the flat banked slots into one queue of saved positions PER MONSTER
--TYPE, so an edit to the roster cannot hand one monster's tile to another.
--Each entry carries the appearance, player-visibility and Hidden state banked
--with it, since those are slot-keyed too and must travel with the position.
--
--Positions banked before spawnmonsters existed carry no monsterid stamp; they
--go into a shared legacy queue any monster may draw from in slot order, which
--reproduces the old flat behaviour for encounters saved by older builds.
local function BankedPositionQueues(group)
    local queues = {}
    local legacy = {}
    local locs = group.spawnlocs or {}
    for slot = 1, #locs do
        local entry = {
            loc = locs[slot],
            appearance = (group.appearances or {})[slot],
            invisible = (group.invisibleToPlayers or {})[slot],
            hidden = (group.startsHidden or {})[slot],
        }
        local monsterid = (group.spawnmonsters or {})[slot]
        if monsterid == nil or monsterid == false then
            legacy[#legacy + 1] = entry
        else
            local queue = queues[monsterid]
            if queue == nil then
                queue = {}
                queues[monsterid] = queue
            end
            queue[#queue + 1] = entry
        end
    end
    return queues, legacy
end

--Draw the next saved position for this monster type, or nil once the group has
--outgrown what was banked (a monster added since, or a quantity raised). nil
--means the caller must fall back -- never that the monster is skipped.
local function TakeBankedPosition(queues, legacy, monsterid)
    local queue = queues[monsterid]
    if queue ~= nil and #queue > 0 then
        return table.remove(queue, 1)
    end
    if #legacy > 0 then
        return table.remove(legacy, 1)
    end
    return nil
end

--Bank one group's staged tokens into the group: positions (spawnlocs),
--player-visibility, the Hidden condition, and (when the encounter opts in) appearances, all in
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
    group.startsHidden = {}
    group.spawnmonsters = {}
    group.stagemapid = game.currentMapId
    for slot, token in ipairs(tokens) do
        group.spawnlocs[slot] = token.loc
        group.invisibleToPlayers[slot] = token.invisibleToPlayers or false
        --a monster staged with the Hidden condition starts every run hidden.
        group.startsHidden[slot] = token.properties:IsHidden()
        --which monster type held this tile, so a later restage can hand it back
        --to the same one even if the roster changed in between. false (never
        --nil) for tokens spawned before the stamp existed: the list has to stay
        --dense or serialization compacts it and shifts every later entry.
        group.spawnmonsters[slot] = token.properties:try_get("encounterSpawnMonster") or false
        if saveAppearances and token.appearanceChangedFromBestiary then
            group.appearances[slot] = token:SerializeAppearanceToString()
        else
            group.appearances[slot] = false
        end
    end
    return tokens
end

--Bank which staged monsters are sitting in which others' saddles, across every
--group of the plan. Separate from BankGroupPositions because a mount is saved as
--the (group, slot) pair it occupies, so it can only be resolved once every
--group's slots are known -- a rider in one group can be riding a monster in
--another. Call it while the tokens are still on the map, and in the same slot
--order BankGroupPositions uses.
local function BankStagedMounts(encounter)
    local entries = {}
    for groupIndex, group in ipairs(encounter.groups) do
        for slot, token in ipairs(PlacedTokensForGroup(group)) do
            entries[#entries + 1] = { group = groupIndex, slot = slot, token = token }
        end
    end
    encounter:RecordMounts(entries)
end

--Seat the monsters of a group that has just been put on the map back onto their
--saved mounts. Tokens already staged from the OTHER groups come along as mounts
--to sit on (mountOnly), so a rider whose mount belongs to a group placed earlier
--still finds it -- without re-seating creatures the Director has since moved.
local function RestoreMountsForPlacedGroup(encounter, groupIndex, entries)
    local all = {}
    for _, entry in ipairs(entries) do
        all[#all + 1] = entry
    end
    for otherIndex, other in ipairs(encounter.groups) do
        if otherIndex ~= groupIndex then
            for slot, token in ipairs(PlacedTokensForGroup(other)) do
                all[#all + 1] = { group = otherIndex, slot = slot, token = token, mountOnly = true }
            end
        end
    end
    encounter:RestoreMounts(all)
end

--True when the group's saved positions were banked on a different map than
--the one currently open (nil stagemapid = legacy data, treated as matching).
local function GroupStagedOnOtherMap(group)
    local mapid = group.stagemapid
    return mapid ~= nil and mapid ~= game.currentMapId
end

--True when the encounter names a map and the group's saved positions were
--banked on a different one. Such positions do not count as staging at all.
local function GroupStagedOffEncounterMap(encounter, group)
    local stagemapid = group.stagemapid
    local mapid = encounter.mapid
    return stagemapid ~= nil and mapid ~= nil and mapid ~= "" and stagemapid ~= mapid
end

--True when the group has saved positions that can be used on the map on
--screen: banked on this map, and on the encounter's own map.
local function GroupHasUsableStaging(encounter, group)
    return group.spawnlocs ~= nil and #group.spawnlocs > 0
        and not GroupStagedOnOtherMap(group)
        and not GroupStagedOffEncounterMap(encounter, group)
end

--Forget a group's saved staging: positions, appearances, visibility, mounts.
local function ClearGroupStaging(group)
    group.spawnlocs = nil
    group.appearances = nil
    group.invisibleToPlayers = nil
    group.startsHidden = nil
    group.spawnmonsters = nil
    group.mounts = nil
    group.stagemapid = nil
end

--Make the encounter's map and its groups' saved staging agree:
--  * no map chosen, but groups were staged on one: that map becomes the
--    encounter's map (the one most groups were staged on, if they differ).
--  * a map chosen: groups staged on any other map lose that staging.
--Returns true if it changed the encounter.
local function ReconcileStagingWithMap(encounter)
    local changed = false

    if encounter.mapid == nil or encounter.mapid == "" then
        local counts = {}
        local best, bestCount = nil, 0
        for _, group in ipairs(encounter.groups) do
            local stagemapid = group.stagemapid
            if stagemapid ~= nil and group.spawnlocs ~= nil and #group.spawnlocs > 0 then
                counts[stagemapid] = (counts[stagemapid] or 0) + 1
                local map = game.GetMap(stagemapid)
                if counts[stagemapid] > bestCount and map ~= nil and map.valid then
                    best, bestCount = stagemapid, counts[stagemapid]
                end
            end
        end
        if best ~= nil then
            encounter.mapid = best
            changed = true
        end
    end

    for _, group in ipairs(encounter.groups) do
        if GroupStagedOffEncounterMap(encounter, group) then
            ClearGroupStaging(group)
            changed = true
        end
    end

    return changed
end

--Spawn a group's monsters at its saved staging positions (group.spawnlocs),
--restoring saved appearances and player-visibility, and tag them with the
--group's placement id so the builder recognises them as staged. A monster with
--no banked position of its own -- one added to the group since it was staged --
--goes to a fallback grid rather than being skipped. Monsters saved riding
--another monster are put back in the saddle. Returns the spawned tokens.
local function StageGroupAtSavedLocations(encounter, groupIndex, group, numHeroes, placementid)
    local tokens = {}
    --the spawned tokens tagged with the slot each went into, for re-seating riders.
    local mountEntries = {}
    local queues, legacy = BankedPositionQueues(group)

    --Where monsters with nothing banked land: beside the group's own saved
    --arrangement, so a captain added after staging appears next to their
    --minions rather than wherever the camera happens to point.
    local fallbackAnchor = (group.spawnlocs or {})[1] or dmhub.cameraPosition
    local baseX = round(fallbackAnchor.x)
    local baseY = round(fallbackAnchor.y)
    local floorIndex = game.currentFloorIndex
    local fallbackIndex = 0

    local slot = 1
    for _, monsterid in ipairs(SortedMonsterIds(group)) do
        local quantity = Encounter.AdjustedMonsterQuantity(group, monsterid, group.monsters[monsterid], numHeroes)
        for i = 1, quantity do
            local entry = TakeBankedPosition(queues, legacy, monsterid)
            local loc = entry ~= nil and entry.loc or nil
            --grid locs have no altitude: the engine stands them on the ground.
            local onGround = false
            if loc ~= nil then
                if not loc.isValidFloor then
                    loc = loc.withCurrentFloor
                end
            else
                onGround = true
                --Same 5-wide grid SpawnGroupForReal uses for unbanked monsters.
                --Skipping instead (as this did) silently lost the monster: the
                --user got a captain and seven of their eight minions, with no
                --indication one had never spawned.
                local col = fallbackIndex % 5
                local row = math.floor(fallbackIndex / 5)
                loc = core.Loc { x = baseX + col, y = baseY + row, floorIndex = floorIndex }
                fallbackIndex = fallbackIndex + 1
            end

            local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true, onGround = onGround })
            if token ~= nil then
                token.properties.encounterPlacementId = placementid
                token.properties.encounterSpawnSlot = slot
                token.properties.encounterSpawnMonster = monsterid
                token.properties.encounterStaged = true
                token.properties.encounterStagedBy = dmhub.userid
                local appearance = entry ~= nil and entry.appearance or nil
                if type(appearance) == "string" then
                    token:SerializeAppearanceFromString(appearance)
                end
                if entry ~= nil and entry.invisible then
                    token.invisibleToPlayers = true
                end
                if entry ~= nil and entry.hidden then
                    token.properties:BecomeHidden(token)
                end
                token:UploadToken()
                tokens[#tokens + 1] = token
                mountEntries[#mountEntries + 1] = { group = groupIndex, slot = slot, token = token }
            end
            slot = slot + 1
        end
    end
    if #tokens > 0 then
        game.UpdateCharacterTokens()
        RestoreMountsForPlacedGroup(encounter, groupIndex, mountEntries)
    end
    return tokens
end

--Defined in the footer-actions section below; forward-declared because the
--group cards offer per-group staging.
local ShowPlacementBanner
local ShowStagingBanner

--The party the builder balances against. See Encounter.CurrentParty.
local function DefaultParty()
    Encounter.SyncAutoPartySize()
    return Encounter.CurrentParty()
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
        --a map token dragged over the builder: the engine puts
        --token-drop-hover on the group card (or the body) a release would join.
        {
            selectors = { "encounterGroupCard", "token-drop-hover" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "encounterTokenDrop", "token-drop-hover" },
            borderColor = "@accent",
            borderWidth = 2,
            cornerRadius = 4,
        },
        --the map card in the header (CreateEncounterMapCard) and its picker.
        {
            selectors = { "encounterMapCard" },
            bgimage = true,
            bgcolor = "@bgAlt",
            borderWidth = 1,
            borderColor = "@border",
            cornerRadius = 4,
        },
        {
            selectors = { "encounterMapCard", "hover" },
            borderColor = "@accent",
        },
        {
            selectors = { "encounterMapCard", "drag-target-hover" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        --the region and start zone badges under the map card.
        {
            selectors = { "encounterAreaBadge", "hover" },
            priority = 6,
            borderColor = "@accent",
        },
        {
            selectors = { "encounterAreaBadge", "drawing" },
            priority = 6,
            color = "@accent",
            borderColor = "@accent",
        },
        --the party bar's outcome group once it has wrapped below the party
        --group: clears the Balance button hanging under the Heroes stepper.
        {
            selectors = { "partyGroupOutcome", "partyWrapped" },
            tmargin = 30,
        },
        {
            selectors = { "encounterMapName" },
            width = "100%",
            height = "auto",
            valign = "bottom",
            hpad = 6,
            vpad = 2,
            borderBox = true,
            bgimage = true,
            bgcolor = "#000000b0",
            color = "white",
            fontSize = 12,
            textAlignment = "left",
            textWrap = false,
        },
        {
            selectors = { "encounterMapOption" },
            width = "100%",
            height = "auto",
            hpad = 6,
            vpad = 3,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            color = "@fg",
            fontSize = 13,
            textAlignment = "left",
        },
        {
            selectors = { "encounterMapOption", "hover" },
            bgcolor = "@bgInverse",
            color = "@fgInverse",
        },
        {
            selectors = { "encounterMapOption", "selected" },
            color = "@accent",
            bold = true,
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
        --args.sync lets the owner change the value from outside the stepper.
        refreshBuilder = args.sync ~= nil and function(element)
            value = args.sync()
            element.text = formatValue(value)
        end or nil,
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
    --Seed every index from 1, not just the 3-7 the UI edits. balancing is keyed
    --by hero count, so a table holding only keys 3-7 is sparse; serialization
    --compacts it to a dense array and the entries come back shifted onto the
    --wrong hero counts (3 heroes reading what was entered for 5, and 6-7
    --reading nothing at all). Keeping it dense from 1 makes index == hero count
    --survive the round trip.
    for i = 1, 7 do
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
-- Encounter script parameters (party bar row)
-- ===========================================================================

--One editor row per attached encounter script that declares parameters,
--appended to the party bar (scripts themselves are attached/detached behind
--the Rule Sets cog). The rebuild is signature-gated so value edits never
--clobber input focus: the signature covers the attachment list, each script's
--declared params, and the wave roster (wave params render a wave dropdown).
local function CreateScriptParamsRow(encounter, refresh)
    local function CommitParamValue(instance, paramid, value)
        local params = instance:get_or_add("params", {})
        params[paramid] = value
        --parameter values can feed the script's victory text; refresh the cache
        --so the victory label updates live.
        pcall(function() instance:RefreshCache() end)
        refresh()
    end

    local function BuildParamEditor(instance, param)
        local values = instance:try_get("params", {})
        local current = values[param.id]
        if current == nil then
            current = param.default
        end

        --booleans carry their own caption inside the check control.
        if param.type == "boolean" then
            return gui.Panel {
                flow = "vertical",
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 18,
                gui.Check {
                    value = (current == true),
                    text = param.name,
                    fontSize = 12,
                    valign = "center",
                    change = function(element)
                        CommitParamValue(instance, param.id, element.value == true)
                    end,
                },
            }
        end

        local editor

        if param.type == "number" then
            editor = gui.Input {
                classes = { "form" },
                width = 60,
                height = 26,
                fontSize = 12,
                numeric = true,
                characterLimit = 6,
                text = tostring(tonumber(current) or tonumber(param.default) or 0),
                change = function(element)
                    local n = tonumber(element.text)
                    if n == nil then
                        local prev = (instance:try_get("params", {}))[param.id]
                        element.text = tostring(tonumber(prev) or tonumber(param.default) or 0)
                        return
                    end
                    if param.min ~= nil and n < param.min then n = param.min end
                    if param.max ~= nil and n > param.max then n = param.max end
                    element.text = tostring(n)
                    CommitParamValue(instance, param.id, n)
                end,
            }
        elseif param.type == "choice" then
            local options = {}
            local found = false
            for _, opt in ipairs(param.options or {}) do
                options[#options + 1] = { id = opt.id, text = opt.text }
                if opt.id == current then
                    found = true
                end
            end
            if not found and #options > 0 then
                current = options[1].id
            end
            editor = gui.Dropdown {
                classes = { "form" },
                width = 140,
                height = 26,
                fontSize = 12,
                options = options,
                idChosen = current,
                change = function(element)
                    ---@cast element Dropdown
                    CommitParamValue(instance, param.id, element.idChosen)
                end,
            }
        elseif param.type == "wave" then
            local options = {}
            for _, wave in ipairs(encounter:try_get("waves", {})) do
                options[#options + 1] = { id = wave.id, text = wave.name or "Reinforcements" }
            end
            if #options == 0 then
                editor = gui.Label {
                    classes = { "fgMuted" },
                    fontSize = 11,
                    width = 150,
                    height = "auto",
                    valign = "center",
                    textWrap = true,
                    text = "Add a Reinforcements wave to use this script",
                }
            else
                table.insert(options, 1, { id = "none", text = "(choose a wave)" })
                local chosen = current
                local waveFound = false
                for _, opt in ipairs(options) do
                    if opt.id == chosen then
                        waveFound = true
                        break
                    end
                end
                if not waveFound then
                    chosen = "none"
                end
                editor = gui.Dropdown {
                    classes = { "form" },
                    width = 170,
                    height = 26,
                    fontSize = 12,
                    options = options,
                    idChosen = chosen,
                    change = function(element)
                        ---@cast element Dropdown
                        local v = element.idChosen
                        if v == "none" then
                            v = nil
                        end
                        CommitParamValue(instance, param.id, v)
                    end,
                }
            end
        else --string
            editor = gui.Input {
                classes = { "form" },
                width = 140,
                height = 26,
                fontSize = 12,
                characterLimit = 100,
                text = tostring(current or ""),
                change = function(element)
                    CommitParamValue(instance, param.id, element.text)
                end,
            }
        end

        return gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 18,
            FieldCaption(param.name),
            editor,
        }
    end

    local function BuildScriptRow(instance, def)
        local children = {}
        children[#children + 1] = gui.Label {
            classes = { "fgMuted", "sizeXxs", "bold" },
            width = 110,
            height = "auto",
            valign = "center",
            rmargin = 8,
            textWrap = true,
            text = instance:try_get("name", "Script"),
        }
        for _, param in ipairs(def.params) do
            children[#children + 1] = BuildParamEditor(instance, param)
        end
        return gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 8,
            children = children,
        }
    end

    return gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        data = { sig = nil },

        create = function(element)
            element:FireEvent("refreshBuilder")
        end,

        refreshBuilder = function(element)
            local entries = {}
            local sigParts = {}
            for _, instance in ipairs(encounter:GetScripts()) do
                local def = nil
                pcall(function() def = select(1, instance:GetDefinition()) end)
                if def ~= nil and #def.params > 0 then
                    entries[#entries + 1] = { instance = instance, def = def }
                    sigParts[#sigParts + 1] = instance:try_get("guid", "?")
                    for _, param in ipairs(def.params) do
                        sigParts[#sigParts + 1] = param.id .. ":" .. param.type
                        if param.type == "wave" then
                            for _, wave in ipairs(encounter:try_get("waves", {})) do
                                sigParts[#sigParts + 1] = wave.id .. "=" .. (wave.name or "")
                            end
                        end
                    end
                end
            end

            local sig = table.concat(sigParts, "|")
            if sig == element.data.sig then
                return
            end
            element.data.sig = sig

            element:SetClass("collapsed", #entries == 0)
            local children = {}
            for _, entry in ipairs(entries) do
                children[#children + 1] = BuildScriptRow(entry.instance, entry.def)
            end
            element.children = children
        end,
    }
end

-- ===========================================================================
-- Party bar
-- ===========================================================================

--The party the encounter is balanced against plus the author's target:
--Heroes / Level / Victories steppers, the live party Encounter Strength
--readout, and the target-difficulty dropdown.
local function CreatePartyBar(encounter, party, refresh, rebuild, budgetDial)
    local esValueLabel = gui.Label {
        classes = { "number", "sizeXl", "bold" },
        width = "auto",
        height = "auto",
        halign = "left",
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
        halign = "left",
        lmargin = 8,
        valign = "bottom",
        bmargin = 4,
        text = "",
        refreshBuilder = function(element)
            local strength = Encounter.PartyStrength(party)
            --the victories bonus goes on its own line so the readout keeps to
            --the column's fixed width.
            local text = string.format("%d ES x %d heroes", strength.singleHero, strength.numHeroes)
            if strength.victoryBonus > 0 then
                text = string.format("%s\n+ %d from victories", text, strength.victoryBonus)
            end
            element.text = text
        end,
    }

    local function partyColumn(caption, stepper, extra)
        return gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 18,
            FieldCaption(caption),
            stepper,
            extra,
        }
    end

    --Rebalance the roster for every other party size, keeping the current
    --one exactly as built. See Encounter.Rebalance for the rules.
    --Floating so the Heroes stepper stays level with the Level and
    --Victories steppers; the button hangs just below it.
    local balanceButton = gui.Button {
        classes = { "sizeXs" },
        floating = true,
        width = 80,
        height = 22,
        fontSize = 12,
        halign = "center",
        valign = "bottom",
        y = 40,
        text = "Balance",
        data = { tip = "" },
        refreshBuilder = function(element)
            element.data.tip = string.format(
                "Keep the encounter as it is for %d heroes and rebuild the balancing for every other party size (3-7) to match its difficulty: whole groups are removed from the highest lettered down for smaller parties, and new groups of the same monster types are added for larger ones.",
                party.numHeroes)
        end,
        create = function(element)
            element:FireEvent("refreshBuilder")
        end,
        hover = function(element)
            gui.Tooltip(element.data.tip)(element)
        end,
        press = function(element)
            local summary = encounter:Rebalance(party)
            local lines = {}
            for _, n in ipairs(Encounter.RebalanceHeroCounts) do
                local entry = summary[n]
                if entry ~= nil then
                    lines[#lines + 1] = string.format("%d heroes: %d EV (target %d), %d groups", n, entry.ev, entry.target, entry.groups)
                end
            end
            print("Encounter rebalanced:\n" .. table.concat(lines, "\n"))
            rebuild()
        end,
    }

    --Any stepper change is an override: save it and stop auto-calculating.
    local function overrideParty()
        party.manual = true
        Encounter.SetManualParty(party)
        refresh()
    end

    --Beneath the Level and Victories steppers, level with the Balance button:
    --where the numbers came from, or (once overridden) the way back to the
    --player party. x backs out the trailing column margin to center them.
    local autoSourceLabel = gui.Label {
        classes = { "fgMuted", "sizeXxs" },
        floating = true,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",
        x = -9,
        y = 24,
        text = "From the player party",
        refreshBuilder = function(element)
            element:SetClass("collapsed", party.manual)
        end,
        create = function(element)
            element:FireEvent("refreshBuilder")
        end,
    }

    local autoButton = gui.Button {
        classes = { "sizeXs" },
        floating = true,
        width = 140,
        height = 22,
        fontSize = 12,
        halign = "center",
        valign = "bottom",
        x = -9,
        y = 40,
        text = "",
        hover = gui.Tooltip("Go back to the Heroes / Level / Victories worked out from the heroes in the player party, and keep them up to date with it."),
        refreshBuilder = function(element)
            element:SetClass("collapsed", not party.manual)
            if party.manual then
                local auto = Encounter.AutoParty()
                element.text = string.format("Use party: %d / %d / %d", auto.numHeroes, auto.level, auto.victories)
            end
        end,
        create = function(element)
            element:FireEvent("refreshBuilder")
        end,
        press = function(element)
            local auto = Encounter.ClearManualParty()
            party.numHeroes = auto.numHeroes
            party.level = auto.level
            party.victories = auto.victories
            party.manual = false
            refresh()
        end,
    }

    --The bar is a vertical stack: the classic horizontal row of columns, plus
    --an encounter-script parameter row beneath it that only appears when an
    --attached script declares parameters.
    local partyBar
    --wraps onto a second line when the builder window is resized narrower
    --than the two column groups' natural width.
    local partyColumnsRow = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,

        --once the two groups no longer fit side by side the outcome group
        --wraps below; it then needs clearance for the Balance button that
        --hangs (floating) under the Heroes stepper.
        rendered = function(element, width, height)
            local groups = element.children
            if #groups < 2 then
                return
            end
            --the groups carry no margins of their own, so the row wraps exactly
            --when their widths add up to more than its own.
            local wrapped = groups[1].renderedWidth + groups[2].renderedWidth > element.renderedWidth + 0.5
            groups[2]:SetClass("partyWrapped", wrapped)
        end,

        --party: who the encounter is balanced for.
        gui.Panel {
            classes = { "partyGroup" },
            flow = "horizontal",
            width = "auto",
            height = "auto",
            valign = "center",

            partyColumn("Heroes", CreateStepper {
                value = party.numHeroes,
                min = 3,
                max = 7,
                sync = function() return party.numHeroes end,
                change = function(v)
                    party.numHeroes = v
                    overrideParty()
                end,
            }, balanceButton),

            gui.Panel {
                flow = "horizontal",
                width = "auto",
                height = "auto",
                valign = "center",

                partyColumn("Level", CreateStepper {
                    value = party.level,
                    min = 1,
                    max = 10,
                    sync = function() return party.level end,
                    change = function(v)
                        party.level = v
                        overrideParty()
                    end,
                }),

                partyColumn("Victories", CreateStepper {
                    value = party.victories,
                    min = 0,
                    max = 15,
                    sync = function() return party.victories end,
                    change = function(v)
                        party.victories = v
                        overrideParty()
                    end,
                }),

                autoSourceLabel,
                autoButton,
            },

            gui.Panel {
                flow = "vertical",
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 18,

                FieldCaption("Party Encounter Strength"),

                --Fixed width, or every stepper press shifts the columns to the
                --right as the readout changes length.
                gui.Panel {
                    flow = "horizontal",
                    width = 170,
                    height = "auto",
                    esValueLabel,
                    esBreakdownLabel,
                },
            },
        },

        --the encounter: how it is won, what it awards, its budget. On its own
        --line when the bar wraps.
        gui.Panel {
            classes = { "partyGroup", "partyGroupOutcome" },
            flow = "horizontal",
            width = "auto",
            height = "auto",
            valign = "center",

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
                        ---@cast element Dropdown
                        local hasLeader = Encounter.HasMonsterWithOrganization(encounter, "leader")
                        if hasLeader ~= element.data.hasLeader then
                            element.data.hasLeader = hasLeader
                            element.options = Encounter.GetVictoryConditions(encounter)
                            element.idChosen = encounter:try_get("victoryCondition", "all_defeated")
                        end
                    end,

                    change = function(element)
                        ---@cast element Dropdown
                        encounter.victoryCondition = element.idChosen
                        partyBar:FireEventTree("refreshDestroy")
                    end,

                    --Collapsed in favor of the script-victory label when an
                    --attached encounter script declares a victory condition.
                    refreshBuilder = function(element)
                        element:SetClass("collapsed", encounter:ScriptVictoryText() ~= nil)
                    end,
                    create = function(element)
                        element:FireEvent("refreshBuilder")
                    end,
                },

                --Shown INSTEAD of the dropdown when an attached encounter script
                --declares a victory condition. The stored victoryCondition field is
                --left untouched underneath, so detaching the script restores the
                --previously-chosen dropdown value.
                gui.Label {
                    classes = { "fgStrong" },
                    width = 260,
                    height = "auto",
                    fontSize = 12,
                    textWrap = true,
                    text = "",
                    data = { tip = nil },

                    refreshBuilder = function(element)
                        local text, scriptInstance = encounter:ScriptVictoryText()
                        element:SetClass("collapsed", text == nil)
                        if text ~= nil then
                            element.text = string.format("%s (set by script)", text)
                            local scriptName = "Encounter Script"
                            if scriptInstance ~= nil then
                                scriptName = scriptInstance:try_get("name", scriptName)
                            end
                            element.data.tip = string.format("Victory condition set by the encounter script \"%s\".", scriptName)
                        end
                    end,
                    create = function(element)
                        element:FireEvent("refreshBuilder")
                    end,
                    hover = function(element)
                        if element.data.tip ~= nil then
                            gui.Tooltip(element.data.tip)(element)
                        end
                    end,
                },

                --Shown only when the "Destroy the Thing!" victory condition is selected. Lets the
                --DM pick which Targetable object keyword identifies the "thing" to destroy, or
                --explains how to add one if the map has no Targetable objects with keywords.
                gui.Panel {
                    width = 260,
                    height = "auto",
                    flow = "vertical",
                    data = { scriptVictory = nil },

                    create = function(element)
                        element:FireEvent("refreshDestroy")
                    end,

                    --rebuild when script-victory presence flips (attach/detach), so
                    --the keyword picker hides along with the dropdown.
                    refreshBuilder = function(element)
                        local hasScriptVictory = encounter:ScriptVictoryText() ~= nil
                        if hasScriptVictory ~= element.data.scriptVictory then
                            element.data.scriptVictory = hasScriptVictory
                            element:FireEvent("refreshDestroy")
                        end
                    end,

                    refreshDestroy = function(element)
                        local isDestroy = encounter:try_get("victoryCondition", "all_defeated") == "destroy_thing"
                        if encounter:ScriptVictoryText() ~= nil then
                            isDestroy = false
                        end
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
                                    ---@cast dropdown Dropdown
                                    encounter.victoryDestroyKeyword = dropdown.idChosen
                                end,
                            },
                        }
                    end,
                },

                --Shown when an attached encounter script declares a defeat
                --condition. Defeat conditions only come from scripts, so unlike
                --victory there is no dropdown underneath to swap out.
                gui.Panel {
                    flow = "vertical",
                    width = "auto",
                    height = "auto",
                    tmargin = 8,

                    create = function(element)
                        element:FireEvent("refreshBuilder")
                    end,
                    refreshBuilder = function(element)
                        element:SetClass("collapsed", encounter:ScriptDefeatText() == nil)
                    end,

                    FieldCaption("Defeat condition"),

                    gui.Label {
                        classes = { "fgStrong" },
                        width = 260,
                        height = "auto",
                        fontSize = 12,
                        textWrap = true,
                        text = "",
                        data = { tip = nil },

                        refreshBuilder = function(element)
                            local text, scriptInstance = encounter:ScriptDefeatText()
                            if text ~= nil then
                                element.text = string.format("%s (set by script)", text)
                                local scriptName = "Encounter Script"
                                if scriptInstance ~= nil then
                                    scriptName = scriptInstance:try_get("name", scriptName)
                                end
                                element.data.tip = string.format("Defeat condition set by the encounter script \"%s\".", scriptName)
                            end
                        end,
                        create = function(element)
                            element:FireEvent("refreshBuilder")
                        end,
                        hover = function(element)
                            if element.data.tip ~= nil then
                                gui.Tooltip(element.data.tip)(element)
                            end
                        end,
                    },
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
        },
    }

    partyBar = gui.Panel {
        classes = { "bordered", "bg" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 14,
        vpad = 10,
        borderBox = true,
        vmargin = 6,

        partyColumnsRow,
        CreateScriptParamsRow(encounter, refresh),
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

--Cached bestiary facts for one editor session. Computing a monster's EV runs
--the attribute pipeline, so doing it for the whole compendium is slow -- pay
--that cost once per open, and invalidate whenever the assets change while the
--pane is up. Deliberately NOT shared across opens: see CreateBestiaryPane.
local g_bestiaryInfoCache = nil

--The always-visible bestiary browser: search plus one row per (non-hidden)
--monster with its portrait, level/EV, and click-to-add.
--addMonster(info) is called when a row is clicked.
local function CreateBestiaryPane(party, addMonster)
    --Start every open from the live compendium.
    --
    --The cache exists to avoid re-running the EV pipeline per KEYSTROKE while
    --the pane is open. Its only other invalidation is the refreshAssets handler
    --below, which requires this pane to be alive -- so a monster created,
    --duplicated or renamed in the Bestiary while the builder was CLOSED never
    --reached the list: new monsters were missing entirely and renamed ones kept
    --showing their old names until the app was restarted.
    --
    --One rebuild per open is exactly the cost already paid on the first open of
    --a session, and it cannot go stale.
    g_bestiaryInfoCache = nil

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

                ShowMonsterStatBlockFlyout(element, rowInfo.asset, "right")
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
            if string.find(info.searchText, state.searchText, 1, true) then
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

    --Removing the last monster removes the group itself: an empty group has
    --nothing to place, and the engine's click-to-place preview cannot handle
    --one (it wedges DMSheetHud in a per-frame error). Mirrors the group
    --delete button below, including the saved-mounts index repair.
    local function RemoveMonsterFromGroup(monsterid)
        group.monsters[monsterid] = nil
        if next(group.monsters) == nil then
            table.remove(encounter.groups, groupIndex)
            encounter:RepairMountsAfterGroupRemoved(groupIndex)
            if state.activeGroup == group then
                state.activeGroup = encounter.groups[1]
            end
        end
        rebuild()
    end

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

                --the token image and the name/meta text together make one
                --hover target that flies out the monster's stat block, the
                --same preview the bestiary rows give. Opens to the LEFT: this
                --pane sits on the right-hand side of the builder.
                gui.Panel {
                    classes = { "hoverable" },
                    flow = "horizontal",
                    width = "100%-314",
                    height = "auto",
                    valign = "center",
                    bgimage = true,
                    bgcolor = "clear",

                    linger = function(element)
                        ShowMonsterStatBlockFlyout(element, monsterAsset, "left")
                    end,

                    entryImagePanel,

                    gui.Panel {
                        flow = "vertical",
                        width = "100%-36",
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
                            RemoveMonsterFromGroup(monsterid)
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
                        RemoveMonsterFromGroup(monsterid)
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

    --group-scoped controls, shown once in the card footer: the whole-group
    --"appears at N+ heroes" gate, per-party-size balancing, and per-group
    --placement. The group gate is an OUTER gate -- below it the group
    --contributes no EV and places nothing, regardless of the per-monster
    --gates on the roster rows, which still apply within a surviving group.
    local groupAppearsLink = gui.Label {
        classes = { "link", "sizeXs" },
        width = "auto",
        height = "auto",
        valign = "center",
        rmargin = 16,
        text = "Appears: Always",
        hover = gui.Tooltip("The minimum party size at which this whole group appears. Below it the group contributes no EV and places no monsters."),
        refreshBuilder = function(element)
            if group.minHeroes == nil then
                element.text = "Appears: Always"
            else
                element.text = string.format("Appears: %d+", group.minHeroes)
            end
        end,
        press = function(element)
            local menuEntries = {}
            for _, i in ipairs({ 0, 3, 4, 5, 6, 7 }) do
                menuEntries[#menuEntries + 1] = {
                    text = cond(i == 0, "Always", string.format("%d+ Heroes", i)),
                    selected = (group.minHeroes or 0) == i,
                    click = function()
                        group.minHeroes = cond(i == 0, nil, i)
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

    --true while Stage on Map waits to arrive on the encounter's map, so a
    --second click does not queue a second staging.
    local travellingToStage = false

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
        --on click (release), not press: staging hides the builder, and on press
        --the release then fell through to the window underneath, which raised
        --itself over the placement banner.
        click = function(element)
            --already on the map: bank the arrangement, then collect the
            --tokens. Discarding instead lives on the card's right-click menu.
            local placed = PlacedTokensForGroup(group)
            if #placed > 0 then
                BankGroupPositions(group, encounter.saveAppearances)
                --no map chosen yet: the map it was staged on becomes it.
                if encounter.mapid == "" then
                    ReconcileStagingWithMap(encounter)
                end
                --while the tokens are still on the map: who was riding whom.
                BankStagedMounts(encounter)
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
                    owner = element,
                    title = "Nothing to Stage",
                    message = "This group has no monsters at the current party size.",
                }
                return
            end

            --set on a Map Library map the game lacks (or holds as a second
            --copy): add it, or move onto the copy, then stage as usual.
            local mapRef = encounter:GetMapRef()
            if mapRef ~= nil then
                local libraryMap = Encounter.FindLibraryMap(mapRef)
                if libraryMap == nil or libraryMap.id ~= encounter.mapid then
                    Encounter.ResolveMapRef(encounter, { inPlace = true }, function()
                        if mod.unloaded or not element.valid then return end
                        refresh()
                        element:FireEvent("click")
                    end)
                    return
                end
            end

            --the encounter's staging belongs on its own map: go there first,
            --then stage once it is the current map (staging banked anywhere
            --else would be dropped as not on the encounter's map).
            if encounter.mapid ~= "" and encounter.mapid ~= game.currentMapId then
                local map = game.GetMap(encounter.mapid)
                if map ~= nil and map.valid then
                    if travellingToStage then
                        return
                    end
                    travellingToStage = true
                    if Tabletop.IsActive() then
                        Tabletop.OpenMap(encounter.mapid)
                    else
                        map:Travel()
                    end
                    --same generous window EotW gives an animated map switch.
                    local deadline = dmhub.Time() + 60
                    local function StageOnArrival()
                        if mod.unloaded or not element.valid then
                            travellingToStage = false
                            return
                        end
                        if game.currentMapId == encounter.mapid then
                            --let the new map's tokens and floors settle first.
                            dmhub.Schedule(0.5, function()
                                travellingToStage = false
                                if mod.unloaded or not element.valid then return end
                                element:FireEvent("click")
                            end)
                            return
                        end
                        if dmhub.Time() < deadline then
                            dmhub.Schedule(0.1, StageOnArrival)
                        else
                            travellingToStage = false
                        end
                    end
                    dmhub.Schedule(0.1, StageOnArrival)
                    return
                end
            end

            if group.placementid == nil then
                group.placementid = dmhub.GenerateGuid()
            end
            local placementid = group.placementid

            --staging happens on the current map, so make sure a window shows
            --it: this restores a minimized window or opens a new one, without
            --taking over a window that holds a frozen snapshot of another map.
            if Tabletop.IsActive() then
                Tabletop.OpenMap(game.currentMapId, { newWindow = true })
            end

            --the link lives on a group card inside the builder, so this is never nil.
            local editorPanel = element:FindParentWithClass("editorPanel") --[[@as Panel]]

            local function ShowArrangeBanner()
                ShowStagingBanner(
                    string.format("%s staged. Arrange the tokens, then return - positions save with the plan.", GroupName(encounter, group, groupIndex)),
                    {
                        onClosed = function()
                            if editorPanel ~= nil and editorPanel.valid then
                                editorPanel:SetClass("hidden", false)
                                --map windows clicked while arranging were
                                --raised over the hidden builder; come back on top.
                                editorPanel:SetAsLastSibling()
                                refresh()
                            end
                        end,
                    })
            end

            --a saved staging exists on THIS map: re-materialize the tokens at
            --their saved positions and bring them into view for arranging.
            --Positions banked on another map are coordinates that mean nothing
            --here, so fall through to click-to-stage instead.
            if GroupHasUsableStaging(encounter, group) then
                local tokens = StageGroupAtSavedLocations(encounter, groupIndex, group, party.numHeroes, placementid)
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
            if GroupStagedOnOtherMap(group) and not GroupStagedOffEncounterMap(encounter, group) then
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
                        --a map window opened for staging sits over the
                        --hidden builder; come back on top.
                        editorPanel:SetAsLastSibling()
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
                and not GroupStagedOffEncounterMap(encounter, group)
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

        --monsters dragged off the map and dropped on the card join THIS
        --group, staged where they stand (Encounter.Editor's AdoptDroppedTokens).
        tokenDropTarget = args.adoptTokens ~= nil,
        dropTokens = function(element, info)
            args.adoptTokens(info.charids, group)
        end,
        tokenDragEnter = function(element, info)
            args.previewTokens(info.charids, group)
        end,
        tokenDragLeave = function(element)
            args.hideTokenPreview()
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
                        copy.startsHidden = nil
                        copy.spawnmonsters = nil
                        copy.mounts = nil
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
                        ClearGroupStaging(group)
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
            --dim the whole card when the group's own gate excludes it at the
            --party size being previewed: it contributes no EV and places
            --nothing, so it should not read as live content.
            element:SetClass("gatedOff", group.minHeroes ~= nil and party.numHeroes < group.minHeroes)
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
                    --saved mounts name their group by index, so the survivors'
                    --references have to shift down with the removal.
                    encounter:RepairMountsAfterGroupRemoved(groupIndex)
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

                    groupAppearsLink,
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
                            adoptTokens = args.adoptTokens,
                            previewTokens = args.previewTokens,
                            hideTokenPreview = args.hideTokenPreview,
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
                            ---@cast element Dropdown
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
-- Encounter scripts list (behind the Rule Sets cog)
-- ===========================================================================

--Attach/detach list for encounter scripts, shown in the header cog popup
--alongside rule sets. Parameter editing lives on the party bar
--(CreateScriptParamsRow); this list is add/remove plus the entry point to the
--custom-code editor.
local function createEncounterScriptsPanel(encounter, onChange)
    local resultPanel

    local function Changed()
        if onChange ~= nil then
            onChange()
        end
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel:FireEvent("rebuildScripts")
        end
    end

    local function EditCustomScript(instance)
        EncounterScript.ShowCodeEditorDialog {
            title = instance:try_get("name", "Custom Script"),
            code = instance:try_get("code", ""),
            filenameHint = instance:try_get("guid", "custom"),
            canSaveToLibrary = true,
            onSave = function(newCode)
                instance.code = newCode
                pcall(function() instance:RefreshCache() end)
                Changed()
            end,
            onSavedToLibrary = function(scriptid)
                --convert the attachment from inline code to a library reference.
                instance.scriptid = scriptid
                instance.code = ""
                pcall(function() instance:RefreshCache() end)
                Changed()
            end,
        }
    end

    resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 4,

        create = function(element)
            element:FireEvent("rebuildScripts")
        end,

        rebuildScripts = function(element)
            local children = {}

            for _, instance in ipairs(encounter:GetScripts()) do
                local scriptInstance = instance
                pcall(function() scriptInstance:RefreshCache() end)
                local def, defError = scriptInstance:GetDefinition()

                local source = "Library"
                if scriptInstance:IsCustom() then
                    source = "Custom"
                elseif EncounterScript.GetBuiltin(scriptInstance:try_get("scriptid", "")) ~= nil then
                    source = "Built-in"
                end

                local rowChildren = {}

                rowChildren[#rowChildren + 1] = gui.Label {
                    fontSize = 14,
                    width = 170,
                    height = "auto",
                    valign = "center",
                    textWrap = true,
                    text = scriptInstance:try_get("name", "Encounter Script"),
                }

                rowChildren[#rowChildren + 1] = gui.Label {
                    classes = { "fgMuted", "sizeXxs" },
                    width = 55,
                    height = "auto",
                    valign = "center",
                    text = source,
                }

                if scriptInstance:IsCustom() then
                    rowChildren[#rowChildren + 1] = gui.Label {
                        classes = { "link" },
                        fontSize = 12,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        hmargin = 4,
                        text = "Edit...",
                        press = function()
                            EditCustomScript(scriptInstance)
                        end,
                    }
                end

                rowChildren[#rowChildren + 1] = gui.DeleteItemButton {
                    width = 16,
                    height = 16,
                    valign = "center",
                    halign = "right",
                    click = function()
                        encounter:RemoveScript(scriptInstance:try_get("guid"))
                        Changed()
                    end,
                }

                children[#children + 1] = gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 2,
                    children = rowChildren,
                }

                if def == nil then
                    children[#children + 1] = gui.Label {
                        fontSize = 11,
                        color = "#ff9999",
                        width = "100%",
                        height = "auto",
                        textWrap = true,
                        bmargin = 4,
                        text = tostring(defError),
                    }
                end
            end

            --the add picker: built-ins + library scripts + custom.
            local addOptions = { { id = "none", text = "Add Script..." } }
            EncounterScript.FillPickerOptions(addOptions)
            addOptions[#addOptions + 1] = { id = "custom", text = "Custom Lua Script..." }

            children[#children + 1] = gui.Dropdown {
                classes = { "form" },
                width = "100%",
                height = 28,
                fontSize = 12,
                tmargin = 6,
                options = addOptions,
                idChosen = "none",
                change = function(element)
                    ---@cast element Dropdown
                    local chosen = element.idChosen
                    if chosen == "none" then
                        return
                    end
                    if chosen == "custom" then
                        local instance = EncounterScriptInstance.CreateCustom()
                        encounter:AddScript(instance)
                        Changed()
                        EditCustomScript(instance)
                    else
                        encounter:AddScript(EncounterScriptInstance.CreateFromLibrary(chosen))
                        Changed()
                    end
                end,
            }

            element.children = children
        end,
    }

    return resultPanel
end

-- ===========================================================================
-- Footer actions: Place on Map
-- ===========================================================================

--Mount a mode banner (placement, staging) in the hud's banner layer, which sits
--over the map and journal windows: a window raised by a click must not hide
--the banner telling the user what mode they are in. The lobby hud has no
--banner layer, so fall back to the documents layer there.
local function MountModeBanner(banner)
    local hud = GameHud.instance --[[@as GameHud]]
    local layer = hud.bannerLayer
    if layer ~= nil and layer.valid then
        layer:AddChild(banner)
    else
        hud.documentsPanel:AddChild(banner)
    end
end

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
        --marker class: this banner holds GUI focus on purpose (that is how it
        --receives the map click), so Encounter.DisarmClickToPlace must leave
        --it alone while it is up.
        classes = { "framedPanel", "encounterPlacementBanner" },
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
            --on click (release), not press: see Back to Builder below.
            click = function(element)
                banner:DestroySelf()
            end,
        },
    }

    MountModeBanner(banner)
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
            --on click (release), not press: closing on press let the release
            --fall through to the window under the banner, which raised itself
            --over the builder we just brought back.
            click = function(element)
                banner:DestroySelf()
            end,
        },
    }

    MountModeBanner(banner)
end

-- ===========================================================================
-- Encounter map: which map the encounter takes place on
-- ===========================================================================

local MAP_CARD_WIDTH = 176
local MAP_CARD_HEIGHT = 99

--The encounter's map, or nil when none is chosen or it has been deleted.
local function EncounterMap(encounter)
    local mapid = encounter.mapid
    if mapid == nil or mapid == "" then
        return nil
    end
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        return nil
    end
    return map
end

--The part of its map an encounter is fought on, as an area for
--dmhub.FrameMapArea (tiles, x2/y2 exclusive; {} = the whole map), and that
--area's shape, width over height (nil when unknown: no region, and the map
--is not in the game yet). A table window opened for the encounter takes
--this shape and zooms to the area.
--- @param encounter Encounter
--- @return {x1: nil|number, y1: nil|number, x2: nil|number, y2: nil|number} area
--- @return number|nil aspect
function Encounter.FrameArea(encounter)
    local region = encounter:GetRegion()
    if region ~= nil then
        --regions are inclusive tile ranges.
        local x1, x2 = math.min(region.x1, region.x2), math.max(region.x1, region.x2)
        local y1, y2 = math.min(region.y1, region.y2), math.max(region.y1, region.y2)
        return { x1 = x1, y1 = y1, x2 = x2 + 1, y2 = y2 + 1 }, (x2 - x1 + 1) / (y2 - y1 + 1)
    end
    local map = EncounterMap(encounter)
    local aspect = nil
    if map ~= nil then
        pcall(function()
            local dim = map.dimensions
            local w, h = dim.x2 - dim.x1, dim.y2 - dim.y1
            if w > 0 and h > 0 then
                aspect = w / h
            end
        end)
    end
    return {}, aspect
end

--The picker the map card opens: Create New Map, a searchable list of this
--game's maps, and No Map. choose(mapid, create) gets "" for No Map and
--create = true for Create New Map.
local function CreateMapPickerPopup(encounter, choose)
    local list = gui.Panel {
        width = "100%",
        height = "auto",
        maxHeight = 320,
        flow = "vertical",
        vscroll = true,
    }

    local function Populate(search)
        search = string.lower(search or "")
        local maps = {}
        for _, map in ipairs(game.maps) do
            if search == "" or string.find(string.lower(map.description), search, 1, true) ~= nil then
                maps[#maps + 1] = map
            end
        end
        table.sort(maps, function(a, b)
            return string.lower(a.description) < string.lower(b.description)
        end)

        local children = {}
        for _, map in ipairs(maps) do
            local mapid = map.id
            children[#children + 1] = gui.Label {
                classes = { "encounterMapOption", cond(mapid == encounter.mapid, "selected") },
                text = map.description,
                press = function(element)
                    choose(mapid)
                end,
            }
        end
        if #children == 0 then
            children[1] = gui.Label {
                classes = { "fgMuted", "sizeXs" },
                width = "100%",
                height = "auto",
                vmargin = 6,
                textAlignment = "center",
                text = "No maps match.",
            }
        end
        list.children = children
    end

    Populate("")

    --the map open right now, first and in bold: usually the one the Director
    --is building the encounter for.
    local currentMap = game.currentMap
    local currentOption = nil
    if currentMap ~= nil and currentMap.valid then
        local currentId = game.currentMapId
        currentOption = gui.Label {
            classes = { "encounterMapOption", cond(currentId == encounter.mapid, "selected") },
            bold = true,
            bmargin = 8,
            text = string.format("Current Map: %s", currentMap.description),
            press = function(element)
                choose(currentId)
            end,
        }
    end

    return gui.Panel {
        classes = { "bordered", "bg" },
        width = 300,
        height = "auto",
        flow = "vertical",
        hpad = 10,
        vpad = 10,
        borderBox = true,

        currentOption,

        gui.Button {
            classes = { "sizeS" },
            width = "100%",
            text = "Create New Map...",
            press = function(element)
                choose(nil, true)
            end,
        },

        gui.Input {
            classes = { "form" },
            width = "100%",
            height = 26,
            vmargin = 8,
            placeholderText = "Search maps...",
            editlag = 0.1,
            edit = function(element)
                Populate(element.text)
            end,
        },

        list,

        gui.Label {
            classes = { "encounterMapOption", cond(encounter.mapid == "", "selected") },
            tmargin = 6,
            italics = true,
            text = "No Map",
            press = function(element)
                choose("")
            end,
        },
    }
end

--The map card in the builder's header: a picture of the encounter's map.
--Click it to choose or create the map, drop a map on it from the Maps panel,
--and drag it onto the table to open that map in a window.
local function CreateEncounterMapCard(encounter, refresh)
    local card

    --the map's picture (MapThumbnails.lua), cover-fit to the card.
    --floating: the picture, the name strip and the empty-state text overlap.
    local image = MapThumbnail.Panel {
        floating = true,
        mapid = encounter.mapid,
        width = MAP_CARD_WIDTH,
        height = MAP_CARD_HEIGHT,
    }

    local nameLabel = gui.Label {
        classes = { "encounterMapName" },
        floating = true,
        text = "",
    }

    local emptyLabel = gui.Label {
        classes = { "fgMuted", "sizeXs" },
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        text = "",
    }

    local function Refresh()
        local map = EncounterMap(encounter)

        card:SetClass("hasMap", map ~= nil)
        card.draggable = map ~= nil

        image:FireEvent("setMap", map ~= nil and map.id or nil)

        --a map with no picture keeps just its name strip along the bottom.
        nameLabel:SetClass("hidden", map == nil)
        if map ~= nil then
            nameLabel.text = map.description
        end

        emptyLabel:SetClass("hidden", map ~= nil)
        local mapRef = encounter:GetMapRef()
        if map == nil and mapRef ~= nil then
            emptyLabel.text = string.format("%s\nMap Library map\nClick to add it", mapRef.name)
        elseif map == nil and encounter.mapid ~= "" then
            emptyLabel.text = "Map deleted\nClick to choose"
        else
            emptyLabel.text = "No map\nClick to choose"
        end
    end

    local function SetMap(mapid)
        if not card.valid then
            return
        end
        encounter.mapid = mapid
        --another map than the library map it was set on: the reference goes.
        local mapRef = encounter:GetMapRef()
        if mapRef ~= nil then
            local libraryMap = Encounter.FindLibraryMap(mapRef)
            if libraryMap == nil or libraryMap.id ~= mapid then
                encounter.mapRef = ""
            end
        end
        if mapid == "" then
            --staging without a map would just be re-inferred as the map, so
            --No Map takes the saved staging with it.
            for _, group in ipairs(encounter.groups) do
                if group.stagemapid ~= nil then
                    ClearGroupStaging(group)
                end
            end
        else
            ReconcileStagingWithMap(encounter)
        end

        --the open map with no thumbnail, or one out of date: capture now, as
        --arriving on it would (a capture only works on the map on screen).
        --The card redraws by itself when the thumbnail lands in /mapManifests.
        local map = (mapid ~= "" and mapid == game.currentMapId) and game.GetMap(mapid) or nil
        if map ~= nil and ((map.thumbnailImage or "") == "" or map.thumbnailStale) then
            MapThumbnail.Refresh(map, {
                error = function(message)
                    print("Encounter map thumbnail capture failed:", message)
                end,
            })
        end

        Refresh()
        refresh()
    end

    card = gui.Panel {
        classes = { "encounterMapCard", "mapDropTarget" },
        width = MAP_CARD_WIDTH,
        height = MAP_CARD_HEIGHT,
        halign = "right",
        valign = "top",
        dragTarget = true,

        image,
        emptyLabel,
        nameLabel,

        create = function(element)
            Refresh()
        end,

        --maps renamed, deleted or added elsewhere.
        monitorGame = "/mapManifests",
        refreshGame = function(element)
            Refresh()
        end,

        --the builder set the map itself (monsters dropped from the map).
        refreshBuilder = function(element)
            Refresh()
        end,

        hover = function(element)
            local text
            if EncounterMap(encounter) == nil and encounter:GetMapRef() ~= nil then
                text = "This encounter takes place on a free Map Library map that is not in this game yet. Click to add it."
            elseif EncounterMap(encounter) == nil then
                text = "The map this encounter takes place on. Click to choose or create one, or drag a map here from the Maps panel."
            else
                text = "Click to change the map, or drag it onto the table to open it in a window."
            end
            gui.Tooltip(text)(element)
        end,

        click = function(element)
            --a library map not added yet: add it. Once it is here, a click
            --opens the picker as usual.
            if EncounterMap(encounter) == nil and encounter:GetMapRef() ~= nil then
                Encounter.ResolveMapRef(encounter, { inPlace = true }, function()
                    if not card.valid then return end
                    Refresh()
                    refresh()
                end)
                return
            end
            element.popupsInheritStyles = true
            element.popup = CreateMapPickerPopup(encounter, function(mapid, create)
                element.popup = nil
                if create then
                    ShowCreateMapDialog {
                        created = function(newid)
                            SetMap(newid)
                        end,
                    }
                    return
                end
                SetMap(mapid)
            end)
        end,

        --a map row dropped here from the Maps panel (MapsPanel.lua).
        dropMap = function(element, mapid)
            SetMap(mapid)
        end,

        --dragged out of the builder: only the bare table takes it (as a
        --window on the map), so nothing in the builder is a target.
        canDragOnto = function(element, target)
            return false
        end,
        dragging = function(element, target)
            local map = EncounterMap(encounter)
            if map ~= nil then
                Tabletop.MapRowDragging(element, map.id)
            end
        end,
        drag = function(element, target)
            Tabletop.MapRowDragEnded(element)
            local map = EncounterMap(encounter)
            if map ~= nil then
                Tabletop.MapRowDropped(map.id)
            end
        end,
    }

    return card
end

--The MapTools id the builder's rectangle tool claims (DMHub Core UI/MapToolArbiter.lua).
local AREA_TOOL_ID = "encounterarea"
local START_ZONE_EDIT_COLOR = "#79d2a0"

--The tiles a closed rectangle stroke covers: those whose centers it contains
--(tile (x, y) is centred on world (x, y)). A click-sized stroke gives the tile
--under it. Returns x1, y1, x2, y2 with the corners inclusive.
local function StrokeTileRect(path)
    local ok, points = pcall(function()
        return path.points
    end)
    if not ok or points == nil or #points < 6 then
        return nil
    end

    local minX, minY = points[1], points[2]
    local maxX, maxY = minX, minY
    for i = 1, #points - 1, 2 do
        minX = math.min(minX, points[i])
        maxX = math.max(maxX, points[i])
        minY = math.min(minY, points[i + 1])
        maxY = math.max(maxY, points[i + 1])
    end

    local x1, x2 = math.ceil(minX), math.floor(maxX)
    local y1, y2 = math.ceil(minY), math.floor(maxY)
    if x2 < x1 then
        x1 = math.floor((minX + maxX) / 2 + 0.5)
        x2 = x1
    end
    if y2 < y1 then
        y1 = math.floor((minY + maxY) / 2 + 0.5)
        y2 = y1
    end
    return x1, y1, x2, y2
end

--Under the map card: the encounter's region ("Entire Map" until one is
--drawn) and its hero start zone. Clicking a badge draws on the encounter's
--map with a rectangle tool, opening the map first if it is not the one on
--screen. While the builder is open on that map, everything outside the region
--is desaturated (dmhub.SetMapFocusRegion) and the start tiles are outlined.
--The region shrinks the map's bounds during combat, and the start zone confines
--the heroes until combat starts: see "Encounter region and hero start zone" in
--MCDMEncounter.lua.
local function CreateEncounterAreaBadges(encounter, refresh)
    local column

    --nil, "region" (one rectangle, then done) or "start" (rectangles add
    --tiles until the badge is pressed again).
    local drawing = nil

    local startMarker = nil
    local startMarkerKey = nil
    --bumped by every start zone edit, so the outline is rebuilt.
    local startVersion = 0

    local function OnEncounterMap()
        return encounter.mapid ~= "" and encounter.mapid == game.currentMapId
    end

    local function StopDrawing()
        if drawing ~= nil then
            drawing = nil
            MapTools.Release(AREA_TOOL_ID)
        end
    end

    local function StartDrawing(mode)
        if encounter.mapid == "" then
            --no map chosen yet: the region is drawn on the map on screen.
            if game.currentMap == nil then
                return
            end
            encounter.mapid = game.currentMapId
        elseif encounter.mapid ~= game.currentMapId then
            if game.GetMap(encounter.mapid) == nil then
                return
            end
            --drawing starts once the map is current (think).
            Tabletop.OpenMap(encounter.mapid)
        end

        drawing = mode
        MapTools.Claim(AREA_TOOL_ID)
        refresh()
    end

    local function ClearStartMarker()
        if startMarker ~= nil then
            pcall(function() startMarker:Destroy() end)
            startMarker = nil
        end
        startMarkerKey = nil
    end

    --the desaturated surround and the start zone outline, kept matching the
    --encounter and whatever map is on screen.
    local function UpdateMapVisuals()
        local region = encounter:GetRegion()
        if region ~= nil and encounter.mapid ~= "" then
            dmhub.SetMapFocusRegion {
                x1 = region.x1,
                y1 = region.y1,
                x2 = region.x2 + 1,
                y2 = region.y2 + 1,
                mapid = encounter.mapid,
            }
        else
            dmhub.SetMapFocusRegion(nil)
        end

        local startLocs = encounter:GetHeroStartLocs()
        local floorCount = 0
        pcall(function() floorCount = #game.currentMap.floors end)
        local key = nil
        if OnEncounterMap() and #startLocs > 0 then
            key = string.format("%s|%d|%d", encounter.mapid, startVersion, floorCount)
        end
        if key == startMarkerKey then
            return
        end

        ClearStartMarker()
        if key == nil then
            return
        end
        startMarkerKey = key

        local locs = Encounter.StartLocsOnCurrentMap(startLocs)
        if #locs > 0 then
            startMarker = dmhub.MarkLocs {
                locs = locs,
                color = START_ZONE_EDIT_COLOR,
            }
        end
    end

    local function DrawRegion(x1, y1, x2, y2)
        local map = game.currentMap
        if map == nil then
            return
        end

        --kept inside the map: the region is the part of it the fight uses.
        local dim = map.dimensions
        local mx1, my1, mx2, my2 = dim.x1, dim.y1, dim.x2 - 1, dim.y2 - 1
        x1, y1 = math.max(x1, mx1), math.max(y1, my1)
        x2, y2 = math.min(x2, mx2), math.min(y2, my2)
        if x2 < x1 or y2 < y1 then
            return
        end

        if x1 == mx1 and y1 == my1 and x2 == mx2 and y2 == my2 then
            encounter:SetRegion(nil)
        else
            encounter:SetRegion { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
        end
        StopDrawing()
        refresh()
    end

    local function DrawStartTiles(x1, y1, x2, y2)
        local floor = game.currentFloor
        if floor == nil then
            return
        end
        local floorid = floor.floorid

        local locs = {}
        local seen = {}
        for _, l in ipairs(encounter:GetHeroStartLocs()) do
            local k = string.format("%s:%d:%d", l.floor, l.x, l.y)
            if not seen[k] then
                seen[k] = true
                locs[#locs + 1] = l
            end
        end
        for y = y1, y2 do
            for x = x1, x2 do
                local k = string.format("%s:%d:%d", floorid, x, y)
                if not seen[k] then
                    seen[k] = true
                    locs[#locs + 1] = { x = x, y = y, floor = floorid }
                end
            end
        end

        encounter:SetHeroStartLocs(locs)
        startVersion = startVersion + 1
        refresh()
    end

    local regionBadge = gui.Label {
        classes = { "encounterBadge", "encounterAreaBadge" },
        width = "100%-22",
        height = "auto",
        textAlignment = "center",
        text = "",

        refreshBuilder = function(element)
            local region = encounter:GetRegion()
            element:SetClass("drawing", drawing == "region")
            if drawing == "region" then
                element.text = "Drag a rectangle..."
            elseif region == nil then
                element.text = "Entire Map"
            else
                element.text = string.format("Region %dx%d", region.x2 - region.x1 + 1, region.y2 - region.y1 + 1)
            end
        end,

        hover = function(element)
            local text
            if drawing == "region" then
                text = "Drag a rectangle on the map to mark where the encounter takes place. Click to cancel."
            elseif encounter:GetRegion() == nil then
                text = "The encounter uses the entire map. Click, then drag a rectangle on the map to limit it to one region: during combat the map's bounds shrink to it."
            else
                text = "The region of the map the encounter takes place in. During combat the map's bounds shrink to it. Click to draw it again."
            end
            gui.Tooltip(text)(element)
        end,

        press = function(element)
            if drawing == "region" then
                StopDrawing()
                refresh()
            else
                StartDrawing("region")
            end
        end,
    }

    local regionClear = gui.DeleteItemButton {
        width = 16,
        height = 16,
        valign = "center",
        lmargin = 6,
        hover = gui.Tooltip("Use the entire map."),
        refreshBuilder = function(element)
            element:SetClass("hidden", encounter:GetRegion() == nil)
        end,
        click = function(element)
            encounter:SetRegion(nil)
            if drawing == "region" then
                StopDrawing()
            end
            refresh()
        end,
    }

    local startBadge = gui.Label {
        classes = { "encounterBadge", "encounterAreaBadge" },
        width = "100%-22",
        height = "auto",
        textAlignment = "center",
        text = "",

        refreshBuilder = function(element)
            local count = #encounter:GetHeroStartLocs()
            element:SetClass("drawing", drawing == "start")
            if drawing == "start" then
                element.text = "Done Drawing"
            elseif count == 0 then
                element.text = "No Starting Zone"
            else
                element.text = string.format("Starting Zone: %d %s", count, cond(count == 1, "tile", "tiles"))
            end
        end,

        hover = function(element)
            local text
            if drawing == "start" then
                text = "Drag rectangles on the map to add the tiles heroes can start on. Click when you are done."
            elseif #encounter:GetHeroStartLocs() == 0 then
                text = "Click, then drag rectangles on the map to mark the tiles heroes can start on. Once the encounter is placed, players can only move their heroes inside it until combat starts."
            else
                text = "The tiles heroes can start on. Once the encounter is placed, players can only move their heroes inside it until combat starts. Click to add more tiles."
            end
            gui.Tooltip(text)(element)
        end,

        press = function(element)
            if drawing == "start" then
                StopDrawing()
                refresh()
            else
                StartDrawing("start")
            end
        end,
    }

    local startClear = gui.DeleteItemButton {
        width = 16,
        height = 16,
        valign = "center",
        lmargin = 6,
        hover = gui.Tooltip("Clear the starting zone."),
        refreshBuilder = function(element)
            element:SetClass("hidden", #encounter:GetHeroStartLocs() == 0)
        end,
        click = function(element)
            encounter:SetHeroStartLocs(nil)
            startVersion = startVersion + 1
            --a zone already showing for this encounter goes too.
            local encounterid = encounter:try_get("id")
            if encounterid ~= nil and encounter.mapid ~= "" then
                Encounter.ClearStartZone(encounter.mapid, encounterid)
            end
            refresh()
        end,
    }

    column = gui.Panel {
        width = MAP_CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        lmargin = 12,

        --keeps the rectangle tool alive (the engine expires a custom map tool
        --after ~1s, and each registration returns a fresh event source to
        --listen to) and the map visuals current.
        thinkTime = 0.2,

        create = function(element)
            --another map tool armed: put this one down.
            MapTools.Register(AREA_TOOL_ID, function()
                if drawing ~= nil and column ~= nil and column.valid then
                    drawing = nil
                    refresh()
                end
            end)
            UpdateMapVisuals()
        end,

        destroy = function(element)
            StopDrawing()
            MapTools.Unregister(AREA_TOOL_ID)
            ClearStartMarker()
            dmhub.SetMapFocusRegion(nil)
        end,

        think = function(element)
            UpdateMapVisuals()

            if drawing ~= nil and OnEncounterMap() then
                local eventSource = editor:SetMapTool {
                    tool = "rectangle",
                    closed = true,
                    expires = 1,
                    stabilization = 0,
                    snapToGrid = true,
                    editorCursor = true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end
        end,

        tool = function(element, path)
            if drawing == nil or path == nil or not OnEncounterMap() then
                return
            end
            local x1, y1, x2, y2 = StrokeTileRect(path)
            if x1 == nil then
                return
            end
            if drawing == "region" then
                DrawRegion(x1, y1, x2, y2)
            else
                DrawStartTiles(x1, y1, x2, y2)
            end
        end,

        CreateEncounterMapCard(encounter, refresh),

        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 6,
            regionBadge,
            regionClear,
        },

        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 4,
            startBadge,
            startClear,
        },
    }

    return column
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
--Returns the initiative groupid, the spawned charids, and each spawned token
--tagged with its slot ({ slot = , token = }) -- the caller pairs those with the
--group's index to restore saved mounts (Encounter.RestoreMounts), which it can
--only do once every group it is placing is down.
--Global on Encounter so headless spawners (Encounter of the Week) reuse this
--walk instead of growing a fourth divergent copy; aliased locally below.
function Encounter.SpawnGroupForReal(group, numHeroes, fallbackAnchor)
    local minionName = nil
    local nsquads = 1
    for _, monsterid in ipairs(SortedMonsterIds(group)) do
        local quantity = group.monsters[monsterid]
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
    --each spawned token tagged with its slot, for restoring saved mounts.
    local mountEntries = {}
    local slot = 1
    local fallbackIndex = 0
    local nsquad = 1

    local queues, legacy = BankedPositionQueues(group)

    for _, monsterid in ipairs(SortedMonsterIds(group)) do
        local quantity = Encounter.AdjustedMonsterQuantity(group, monsterid, group.monsters[monsterid], numHeroes)
        for i = 1, quantity do
            local entry = TakeBankedPosition(queues, legacy, monsterid)
            local loc = entry ~= nil and entry.loc or nil
            --a grid loc has no altitude of its own: the engine stands it on
            --the ground (down into a pit as well as up a cliff). A banked
            --position keeps its saved height.
            local onGround = false
            if loc ~= nil then
                if not loc.isValidFloor then
                    loc = loc.withCurrentFloor
                end
            else
                local col = fallbackIndex % 5
                local row = math.floor(fallbackIndex / 5)
                loc = core.Loc { x = baseX + col, y = baseY + row, floorIndex = floorIndex }
                fallbackIndex = fallbackIndex + 1
                onGround = true
            end

            local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true, onGround = onGround })
            if token ~= nil then
                token.properties.initiativeGrouping = groupid
                token.properties:OnCreateFromBestiary(token, groupid)
                token.properties.minHeroes = (group.monsterMinHeroes or {})[monsterid] or group.minHeroes

                if group.placementid ~= nil then
                    token.properties.encounterPlacementId = group.placementid
                    token.properties.encounterSpawnSlot = slot
                    token.properties.encounterSpawnMonster = monsterid
                    token.properties.encounterStaged = false
                end
                if group.sourceEncounterId ~= nil then
                    token.properties.encounterSourceId = group.sourceEncounterId
                end

                local appearanceInfo = entry ~= nil and entry.appearance or nil
                if type(appearanceInfo) == "string" then
                    token:SerializeAppearanceFromString(appearanceInfo)
                end
                if entry ~= nil and entry.invisible then
                    token.invisibleToPlayers = true
                end
                if entry ~= nil and entry.hidden then
                    token.properties:BecomeHidden(token)
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
                --refresh the token registry so the NEXT monster's generated
                --name can see this one: OnCreateFromBestiary numbers against
                --dmhub.GetTokens{pending=true}, which only sees fresh spawns
                --after an update. Without this every monster in the batch is
                --named "<type> 1" (the journal island's spawn already updates
                --per token for the same reason).
                game.UpdateCharacterTokens()
                charids[#charids + 1] = token.charid
                mountEntries[#mountEntries + 1] = { slot = slot, token = token }
            end

            slot = slot + 1
        end
    end

    return groupid, charids, mountEntries
end

local SpawnGroupForReal = Encounter.SpawnGroupForReal

--The nearest unoccupied tile to anchor on the current floor, searching
--outward ring by ring; anchor itself when everything nearby is taken.
local function FreeTileNear(anchor, taken)
    local floorIndex = game.currentFloorIndex
    local ax = round(anchor.x)
    local ay = round(anchor.y)
    for r = 0, 12 do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local loc = core.Loc { x = ax + dx, y = ay + dy, floorIndex = floorIndex }
                    local key = string.format("%d,%d", loc.x, loc.y)
                    if not taken[key] and #(game.GetTokensAtLoc(loc) or {}) == 0 then
                        taken[key] = true
                        return loc
                    end
                end
            end
        end
    end
    return core.Loc { x = ax, y = ay, floorIndex = floorIndex }
end

--Adds count more of monsterid to a group that is already on the map for
--encounter prep (the balancer, as the hero count rises). The newcomers join
--the group's initiative and minion squad, take the group's next saved
--positions for that monster when they are free (useBanked), and otherwise
--stand on free tiles beside the group. existing: the group's tokens now on
--the map. Returns the spawned charids.
--- @param group table
--- @param monsterid string
--- @param count number
--- @param numHeroes number
--- @param existing CharacterToken[]
--- @param useBanked boolean
--- @param fallbackAnchor table any {x, y}
--- @return string[]
function Encounter.SpawnPrepMonsters(group, monsterid, count, numHeroes, existing, useBanked, fallbackAnchor)
    local groupid = nil
    local nextSlot = 1
    local ofType = 0
    local squads = {}
    local anchor = nil
    for _, tok in ipairs(existing) do
        local props = tok.properties
        groupid = groupid or props:try_get("initiativeGrouping")
        nextSlot = math.max(nextSlot, props:try_get("encounterSpawnSlot", 0) + 1)
        if props:try_get("encounterSpawnMonster") == monsterid then
            ofType = ofType + 1
            anchor = anchor or tok.loc
            local squad = props:try_get("minionSquad")
            if squad ~= nil then
                squads[squad] = (squads[squad] or 0) + 1
            end
        end
        anchor = anchor or tok.loc
    end
    groupid = groupid or dmhub.GenerateGuid()
    anchor = anchor or (useBanked and (group.spawnlocs or {})[1]) or fallbackAnchor

    --join the smallest squad of this minion type, if it has any.
    local squadName = nil
    local squadSize = nil
    for name, n in pairs(squads) do
        if squadSize == nil or n < squadSize then
            squadName, squadSize = name, n
        end
    end
    local monsterAsset = assets.monsters[monsterid]
    if squadName == nil and monsterAsset ~= nil and monsterAsset.properties.minion then
        squadName = monster.FindFreshSquadName(monsterAsset.properties.monster_type)
    end

    --the saved positions this monster type has not used yet.
    local banked = {}
    if useBanked then
        local queues, legacy = BankedPositionQueues(group)
        for i = 1, ofType + count do
            local entry = TakeBankedPosition(queues, legacy, monsterid)
            if entry == nil then
                break
            end
            if i > ofType then
                banked[#banked + 1] = entry
            end
        end
    end

    local taken = {}
    local charids = {}
    for i = 1, count do
        local entry = banked[i]
        local loc = nil
        local onGround = false
        if entry ~= nil and #(game.GetTokensAtLoc(entry.loc.withCurrentFloor) or {}) == 0 then
            loc = entry.loc
            if not loc.isValidFloor then
                loc = loc.withCurrentFloor
            end
        else
            entry = nil
            loc = FreeTileNear(anchor, taken)
            onGround = true
        end

        local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true, onGround = onGround })
        if token ~= nil then
            token.properties.initiativeGrouping = groupid
            token.properties:OnCreateFromBestiary(token, groupid)
            token.properties.minHeroes = (group.monsterMinHeroes or {})[monsterid] or group.minHeroes
            token.properties.encounterPlacementId = group.placementid
            token.properties.encounterSpawnSlot = nextSlot
            token.properties.encounterSpawnMonster = monsterid
            token.properties.encounterStaged = false
            if group.sourceEncounterId ~= nil then
                token.properties.encounterSourceId = group.sourceEncounterId
            end
            nextSlot = nextSlot + 1

            if entry ~= nil and type(entry.appearance) == "string" then
                token:SerializeAppearanceFromString(entry.appearance)
            end
            if entry ~= nil and entry.invisible then
                token.invisibleToPlayers = true
            end
            if entry ~= nil and entry.hidden then
                token.properties:BecomeHidden(token)
            end
            local info = (group.balancing or {})[numHeroes]
            if info ~= nil and type(info.stamina) == "number" then
                token.properties.max_hitpoints = info.stamina
            end
            if squadName ~= nil then
                token.properties.minionSquad = squadName
            end

            token:UploadToken()
            game.UpdateCharacterTokens()
            charids[#charids + 1] = token.charid
        end
    end
    return charids
end

--Whether a group's saved positions may be used on the current map (they
--were banked here, and the plan's map is this one or unset).
--- @param encounter Encounter
--- @param group table
--- @return boolean
function Encounter.GroupHasUsableStaging(encounter, group)
    return GroupHasUsableStaging(encounter, group)
end

--Whether a token fights for the heroes: player-controlled, or in the party or
--an allied party (the test the combat setup uses).
local function IsPlayerSideToken(tok)
    if tok.playerControlled then
        return true
    end
    local partyid = tok.partyId
    if partyid == nil then
        return false
    end
    local playerPartyId = GetDefaultPartyID()
    if partyid == playerPartyId then
        return true
    end
    local party = GetParty(playerPartyId)
    return party ~= nil and party:GetAllyParties()[partyid] ~= nil
end

--Whether an untagged token looks like a stock bestiary copy of one of the
--plan's monsters: same bestiary entry and an unchanged name ("Goblin Assassin"
--or "Goblin Assassin 3"). A renamed token is someone's NPC.
--names: bestiaryId -> list of the names that monster spawns under.
local function LooksLikeBestiaryCopy(tok, names)
    local bases = names[tok.bestiaryId or ""]
    if bases == nil then
        return false
    end
    local name = tok.name or ""
    for _, base in ipairs(bases) do
        if name == base or string.match(name, "^" .. string.gsub(base, "(%W)", "%%%1") .. " %d+$") ~= nil then
            return true
        end
    end
    return false
end

--The monsters on the current map that belong to this plan, so starting it can
--replace them with fresh ones:
--  * tagged with one of the plan's group placement ids (staged or placed);
--  * spawned by an earlier prep of this plan (encounterSourceId);
--  * stock bestiary copies of the plan's monsters tagged with a placement id
--    no saved plan owns (an earlier prep from before encounterSourceId);
--  * untagged stock copies of the plan's monsters standing in its region --
--    e.g. placed by click-to-place.
--Never heroes or their allies, summons, monsters tagged to another plan, or
--renamed creatures (NPCs).
--- @param encounter Encounter the saved plan
--- @return CharacterToken[]
function Encounter.FindEncounterMonstersOnMap(encounter)
    local myId = encounter:try_get("id")
    local ownPids = {}
    local names = {}
    for _, group in ipairs(encounter.groups) do
        if group.placementid ~= nil then
            ownPids[group.placementid] = true
        end
        for monsterid, _ in pairs(group.monsters or {}) do
            local asset = assets.monsters[monsterid]
            if asset ~= nil and names[monsterid] == nil then
                local bases = { asset.name }
                local monsterType = nil
                pcall(function() monsterType = asset.properties:try_get("monster_type") end)
                if type(monsterType) == "string" and monsterType ~= asset.name then
                    bases[#bases + 1] = monsterType
                end
                names[monsterid] = bases
            end
        end
    end

    local otherPids = {}
    for id, other in unhidden_pairs(dmhub.GetTable("encounters") or {}) do
        if id ~= myId then
            for _, group in ipairs(other:try_get("groups", {})) do
                if group.placementid ~= nil then
                    otherPids[group.placementid] = true
                end
            end
        end
    end

    local region = encounter:GetRegion()
    local result = {}
    for _, tok in ipairs(dmhub.allTokens) do
        local props = tok.properties
        local monsterish = false
        pcall(function() monsterish = props ~= nil and props:IsMonster() == true end)
        if monsterish and not IsPlayerSideToken(tok) and (tok.summonerid == nil or tok.summonerid == "") then
            local pid = props:try_get("encounterPlacementId")
            local source = props:try_get("encounterSourceId")
            local mine = false
            if pid ~= nil and ownPids[pid] then
                mine = true
            elseif source ~= nil then
                mine = myId ~= nil and source == myId
            elseif pid ~= nil and not otherPids[pid] then
                --spawned by a play of some encounter whose plan no longer
                --names that id (an earlier prep): ours if it is our monster.
                mine = LooksLikeBestiaryCopy(tok, names)
            elseif pid == nil then
                --never tagged at all: only within the encounter's region.
                local loc = tok.loc
                local inRegion = region == nil or (loc.x >= region.x1 and loc.x <= region.x2 and loc.y >= region.y1 and loc.y <= region.y2)
                mine = inRegion and LooksLikeBestiaryCopy(tok, names)
            end
            if mine then
                result[#result + 1] = tok
            end
        end
    end
    return result
end

--Place the encounter on the map for play. Staged tokens are collected first
--(positions banked, tokens removed) so the freshest arrangement wins and
--nothing double-spawns. Groups with saved positions on THIS map spawn there
--immediately; the rest go through one click-to-place banner. Wave groups are
--never placed up front -- they arrive via the reinforcements strip
--(LiveEncounter:DeployWave), which reads the same banked positions.
--
--opts:
--  start      -- start the encounter once everything is placed: outside
--                combat this puts it into prep (Encounter.BeginPrep), where
--                every group spawns straight away -- unstaged groups beside
--                opts.anchor -- and the Director presses Draw Steel from the
--                prep bar.
--  anchor     -- {x, y} where unstaged groups go when starting (the drop
--                point of a drag); default the region's centre or the camera.
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
        --Mounts first: a mount reference resolves against the OTHER groups'
        --staged tokens, and the loop below deletes them group by group.
        BankStagedMounts(encounter)
        local mutated = false
        --groups whose live arrangement was just banked: it is on this map by
        --construction, so it places directly even if the plan names another map.
        local justBanked = {}
        for _, group in ipairs(encounter.groups) do
            local staged = PlacedTokensForGroup(group)
            if #staged > 0 then
                BankGroupPositions(group, encounter.saveAppearances)
                justBanked[group] = true
                local charids = {}
                for _, token in ipairs(staged) do
                    charids[#charids + 1] = token.charid
                end
                game.DeleteCharacters(charids)
                mutated = true
            end
        end
        if mutated and encounter.mapid == "" then
            ReconcileStagingWithMap(encounter)
        end
        if mutated and opts.persist ~= nil then
            opts.persist()
        end

        --starting into prep replaces the plan's monsters already on the map
        --(an earlier placement or prep of it) with fresh ones. The deletes
        --land before the fresh spawn so new monsters can take the same tiles;
        --this re-enters with oldReplaced set, and persist already ran.
        if opts.start and not queueActive and not opts.oldReplaced then
            local old = Encounter.FindEncounterMonstersOnMap(encounter)
            if #old > 0 then
                local charids = {}
                for _, tok in ipairs(old) do
                    charids[#charids + 1] = tok.charid
                end
                game.DeleteCharacters(charids)
                local again = {}
                for k, v in pairs(opts) do
                    again[k] = v
                end
                again.oldReplaced = true
                again.persist = nil
                dmhub.Schedule(0.3, function()
                    if mod.unloaded then return end
                    game.UpdateCharacterTokens()
                    PlaceEncounterForReal(encounter, party, again)
                end)
                return
            end
        end

        --tokens from a previous real placement of this plan are still on the
        --map (encounterStaged == false): pressing Start twice should not
        --silently double the encounter. Starting into prep replaced them above.
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
        if alreadyPlaced > 0 and not opts.placeAgainConfirmed and not (opts.start and not queueActive) then
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

        --starting outside combat goes into prep, which plays a copy of the
        --plan. Every group gets a NEW placement id for this play: the prep
        --treats tokens carrying its ids as its own (counting, re-balancing,
        --deleting), so it must never share an id with monsters an earlier
        --placement of the same plan left on the map.
        local prepping = opts.start and not queueActive
        local savedEncounter = encounter
        local prepAnchor = nil
        if prepping then
            encounter = DeepCopy(encounter)
            --spawns are stamped with the plan's id (encounterSourceId), so the
            --next start of this plan knows them for its own and replaces them.
            local sourceId = savedEncounter:try_get("id")
            for groupIndex, group in ipairs(encounter.groups) do
                if group.wave == nil then
                    group.placementid = dmhub.GenerateGuid()
                    group.sourceEncounterId = sourceId
                end
            end
            prepAnchor = opts.anchor
            local region = encounter:GetRegion()
            if prepAnchor == nil and region ~= nil then
                prepAnchor = { x = (region.x1 + region.x2) / 2, y = (region.y1 + region.y2) / 2 }
            end
            prepAnchor = prepAnchor or dmhub.cameraPosition
        end

        --unstaged groups in prep sit in a grid of cells around the anchor,
        --each cell one group's 5-wide spawn block, kept inside the region.
        local unstaged = {}
        if prepping then
            for groupIndex, group in ipairs(encounter.groups) do
                if group.wave == nil and AdjustedGroupCount(group, numHeroes) > 0
                    and not (justBanked[savedEncounter.groups[groupIndex]] or GroupHasUsableStaging(encounter, group)) then
                    unstaged[#unstaged + 1] = group
                end
            end
        end
        local cellAnchors = {}
        if prepAnchor ~= nil and #unstaged > 0 then
            local CELL_W, CELL_H = 6, 3
            local region = encounter:GetRegion()
            local cols = 3
            if region ~= nil then
                cols = math.max(1, math.floor((region.x2 - region.x1 + 1) / CELL_W))
            end
            cols = math.min(cols, #unstaged)
            local rows = math.ceil(#unstaged / cols)
            local left = prepAnchor.x - (cols * CELL_W) / 2
            local top = prepAnchor.y - (rows * CELL_H) / 2
            if region ~= nil then
                left = math.max(region.x1, math.min(left, region.x2 + 1 - cols * CELL_W))
                top = math.max(region.y1, math.min(top, region.y2 + 1 - rows * CELL_H))
            end
            for i, group in ipairs(unstaged) do
                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                cellAnchors[group] = { x = left + col * CELL_W, y = top + row * CELL_H }
            end
        end

        --split placeable groups: saved positions on this map spawn
        --directly; everything else goes through click-to-place (or, in prep,
        --to its cell beside the anchor).
        local directGroups = {}
        local clickGroups = {}
        for groupIndex, group in ipairs(encounter.groups) do
            if group.wave == nil and AdjustedGroupCount(group, numHeroes) > 0 then
                if cellAnchors[group] ~= nil then
                    directGroups[#directGroups + 1] = { group = group, index = groupIndex, anchor = cellAnchors[group] }
                elseif justBanked[savedEncounter.groups[groupIndex]] or GroupHasUsableStaging(encounter, group) then
                    --carry the group's index: saved mounts name (group, slot) pairs.
                    directGroups[#directGroups + 1] = { group = group, index = groupIndex }
                else
                    clickGroups[#clickGroups + 1] = group
                end
            end
        end

        local spawnedCharids = {}
        local spawnedGroupids = {}
        --every directly-spawned token tagged with its (group, slot), so riders can
        --be seated once all of the groups are down.
        local mountEntries = {}

        for _, direct in ipairs(directGroups) do
            local group = direct.group
            local anchor = direct.anchor or group.spawnlocs[1] or dmhub.cameraPosition
            local groupid, charids, entries = SpawnGroupForReal(group, numHeroes, anchor)
            spawnedGroupids[#spawnedGroupids + 1] = groupid
            for _, cid in ipairs(charids) do
                spawnedCharids[#spawnedCharids + 1] = cid
            end
            for _, entry in ipairs(entries) do
                mountEntries[#mountEntries + 1] = { group = direct.index, slot = entry.slot, token = entry.token }
            end
        end

        --monsters saved riding another monster go back in the saddle.
        encounter:RestoreMounts(mountEntries)

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

                --the heroes' start zone shows (and confines players) until
                --combat starts; not for monsters joining a running fight.
                if not queueActive then
                    Encounter.ShowStartZone(encounter)
                end

                --we have just placed this encounter ourselves, so the engine's
                --click-to-place must not stay armed behind us: the encounter
                --card still holds GUI focus from being selected, which leaves a
                --ghost of the whole roster following the cursor and one stray
                --map click away from spawning the encounter a second time.
                Encounter.DisarmClickToPlace()

                --queueActive implies queue ~= nil; the extra test lets the checker see it.
                if queueActive and queue ~= nil then
                    --mid-combat: the new arrivals join the running fight,
                    --same as a deployed wave; no combat-setup dialog.
                    for _, groupid in ipairs(spawnedGroupids) do
                        queue:SetInitiative(groupid, 0, 0)
                    end
                    dmhub:UploadInitiativeQueue()
                elseif prepping then
                    --the pre-combat phase: Draw Steel is pressed from its bar.
                    Encounter.BeginPrep(encounter, { numHeroes = numHeroes, savedEncounter = savedEncounter })
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

    --one encounter in prep per map: the prep bar drives it.
    local prep = Encounter.GetPrep(game.currentMapId)
    if opts.start and not queueActive and prep ~= nil then
        gui.ModalMessage {
            title = "Already Preparing an Encounter",
            message = string.format("%s is being prepared on this map. Press Draw Steel or Cancel on the bar at the top of the map first.", prep.name or "An encounter"),
        }
        if opts.onCancel ~= nil then
            opts.onCancel()
        end
        return
    end

    --starting on top of a running combat must not clobber the live queue
    --(round counter, hero stats, deployed waves all live there). Skipped on
    --the place-again re-entry, which already confirmed once.
    if opts.start and queueActive and not opts.placeAgainConfirmed then
        gui.ModalMessage {
            title = "Combat Is Already Running",
            message = "An encounter is already running on this map. Do you want to add to the current encounter or start a new one?",
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
                    --ends the running combat (no Victory Screen), then starts
                    --this encounter fresh: with the queue hidden it goes into prep.
                    text = "New Encounter",
                    execute = function()
                        gui.CloseModal()
                        local endCombat = rawget(_G, "g_drawSteelEndCombat")
                        if endCombat == nil then
                            return
                        end
                        endCombat()
                        dmhub.Schedule(0.3, function()
                            if mod.unloaded then return end
                            game.UpdateCharacterTokens()
                            PlaceEncounterForReal(encounter, party, opts)
                        end)
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

--True once a map just added with mappacks.AddMapToGame is in the game: its
--manifest has arrived and lists its floors. Only that, not the floors'
--details: the engine loads those only for the current map (floor.valid stays
--false for any other), and the callers travel there before using them.
local function MapAdded(mapid)
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        return false
    end
    local count = 0
    pcall(function() count = #map.floors end)
    return count > 0
end

--Moves an encounter onto the game map that holds its library map, when that
--map has another id than the pack's (a second copy): its own map, its groups'
--staging, and start tiles on a floor the map lacks go to its top floor.
--- @param encounter Encounter
--- @param ref EncounterMapRef
--- @param map MapManifestLua
local function MoveEncounterOntoMap(encounter, ref, map)
    local oldid = encounter.mapid
    encounter.mapid = map.id
    for _, group in ipairs(encounter.groups) do
        local stagemapid = group.stagemapid
        if stagemapid ~= nil and (stagemapid == ref.mapid or stagemapid == oldid) then
            group.stagemapid = map.id
        end
    end

    local startLocs = encounter:GetHeroStartLocs()
    if #startLocs > 0 then
        local floorids = {}
        local topFloor = nil
        pcall(function()
            for _, floor in ipairs(map.floors) do
                floorids[floor.floorid] = true
                if topFloor == nil and floor.parentFloor == nil then
                    topFloor = floor.floorid
                end
            end
        end)
        if topFloor ~= nil then
            local moved = {}
            for i, loc in ipairs(startLocs) do
                moved[i] = { x = loc.x, y = loc.y, floor = cond(floorids[loc.floor], loc.floor, topFloor) }
            end
            encounter:SetHeroStartLocs(moved)
        end
    end
end

--Gets an encounter set on a Map Library map (Encounter.mapRef) ready for its
--map: finds the map in this game, or adds it and waits for it to load, then
--calls done(encounter) with the encounter to use. If the add fails,
--opts.onCancel is called instead. An encounter
--with no map ref, or already on its map, goes straight to done.
--opts.inPlace: change the encounter itself when it must move onto another
--copy of the map (an editor's working copy); otherwise a copy moves, so a
--shipped or saved row is never changed by running it.
--opts.loadingWindow: the caller's "Loading map..." stand-in
--(Tabletop.ShowLoadingWindow). It is closed here if the add fails; on
--success the caller closes it. Without one, an add shows its own in the
--middle of the table until done.
--- @param encounter Encounter
--- @param opts nil|{inPlace: nil|boolean, onCancel: nil|fun(), loadingWindow: nil|{Close: fun()}}
--- @param done fun(encounter: Encounter)
function Encounter.ResolveMapRef(encounter, opts, done)
    opts = opts or {}
    local ref = encounter:GetMapRef()
    if ref == nil then
        done(encounter)
        return
    end

    local function Use(map)
        if map.id == encounter.mapid then
            done(encounter)
            return
        end
        local target = encounter
        if not opts.inPlace then
            target = DeepCopy(encounter)
        end
        MoveEncounterOntoMap(target, ref, map)
        done(target)
    end

    local map = Encounter.FindLibraryMap(ref)
    if map ~= nil then
        Use(map)
        return
    end
    if rawget(_G, "mappacks") == nil then
        done(encounter)
        return
    end

    local function Cancelled()
        if opts.onCancel ~= nil then
            opts.onCancel()
        end
    end

    local loading = opts.loadingWindow
    local ownLoading = false
    if loading == nil then
        loading = Tabletop.ShowLoadingWindow { name = ref.name }
        ownLoading = loading ~= nil
    end

    local function Failed(message)
        if loading ~= nil then
            loading.Close()
        end
        gui.ModalMessage {
            title = "Could Not Add the Map",
            message = string.format("%s could not be added to this game: %s", ref.name, message or "unknown error"),
        }
        Cancelled()
    end

    local function Add()
        mappacks.AddMapToGame {
            pack = ref.pack,
            mapid = ref.mapid,
            name = ref.name,
            success = function(newid)
                local deadline = dmhub.Time() + 30
                local function WhenLoaded()
                    if mod.unloaded then
                        return
                    end
                    if MapAdded(newid) then
                        if ownLoading and loading ~= nil then
                            loading.Close()
                        end
                        local added = game.GetMap(newid)
                        if added ~= nil then
                            Use(added)
                        end
                    elseif dmhub.Time() < deadline then
                        dmhub.Schedule(0.2, WhenLoaded)
                    else
                        Failed("it did not finish loading")
                    end
                end
                WhenLoaded()
            end,
            error = Failed,
        }
    end

    --no confirmation: the encounter cannot run without its map, and library
    --maps are free.
    Add()
end

--Shows the encounter's map in a window on the table (opening one if none
--does, travelling there if it is not the current map). Returns true when
--the map is already the current one.
function Encounter.ShowEncounterMap(encounter)
    local mapid = encounter.mapid
    if mapid == nil or mapid == "" then
        mapid = game.currentMapId
    end
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        mapid = game.currentMapId
    end
    if Tabletop.IsActive() then
        Tabletop.OpenMap(mapid, { newWindow = true })
    elseif mapid ~= game.currentMapId and map ~= nil then
        map:Travel()
    end
    return mapid == game.currentMapId
end

--Start Encounter, from anywhere (the list card, the builder, a drag onto the
--board): go to the encounter's map first, then place it and put it into
--prep. opts as PlaceEncounterForReal; opts.anchor is only used when no
--travel was needed (it is a point on the map that was current).
function Encounter.StartEncounterOnItsMap(encounter, party, opts)
    opts = opts or {}

    --set on a Map Library map: add it first if the game lacks it. When the
    --encounter had to move onto a second copy of the map, persist saves the
    --moved encounter (opts.mapRefInPlace: the caller's own working copy moved).
    --opts.tableDrop: it was dropped on the bare table, so its map's window
    --opens there, shaped to and zoomed on the encounter's area.
    local ref = encounter:GetMapRef()
    if not opts.mapRefResolved and ref ~= nil then
        --while the map is added, a "Loading map..." window stands where the
        --map's window will open: at the drop, else in the middle of the table.
        local loading = nil
        if Encounter.FindLibraryMap(ref) == nil then
            local _, aspect = Encounter.FrameArea(encounter)
            loading = Tabletop.ShowLoadingWindow { name = ref.name, aspect = aspect, atMouse = opts.tableDrop }
        end
        Encounter.ResolveMapRef(encounter, { inPlace = opts.mapRefInPlace, onCancel = opts.onCancel, loadingWindow = loading }, function(resolved)
            local again = {}
            for k, v in pairs(opts) do
                again[k] = v
            end
            again.mapRefResolved = true
            if resolved ~= encounter and opts.persist ~= nil then
                again.persist = function()
                    dmhub.SetAndUploadTableItem("encounters", resolved)
                end
            end
            local area, aspect = Encounter.FrameArea(resolved)
            if loading ~= nil then
                Tabletop.MapRowDropped(resolved.mapid, { at = loading, frame = area })
                loading.Close()
            elseif opts.tableDrop then
                --found at once (still inside the drop): open it under the mouse.
                Tabletop.MapRowDropped(resolved.mapid, { aspect = aspect, frame = area })
            end
            Encounter.StartEncounterOnItsMap(resolved, party, again)
        end)
        return
    end

    local mapid = encounter.mapid
    local map = (mapid ~= nil and mapid ~= "") and game.GetMap(mapid) or nil
    local alreadyThere = Encounter.ShowEncounterMap(encounter)
    if alreadyThere or map == nil or not map.valid then
        PlaceEncounterForReal(encounter, party, opts)
        return
    end

    local placeOpts = {}
    for k, v in pairs(opts) do
        placeOpts[k] = v
    end
    placeOpts.anchor = nil

    --same generous window Stage on Map gives an animated map switch.
    local deadline = dmhub.Time() + 60
    local function PlaceOnArrival()
        if mod.unloaded then
            return
        end
        if game.currentMapId == mapid then
            --let the new map's tokens and floors settle first.
            dmhub.Schedule(0.5, function()
                if mod.unloaded then return end
                PlaceEncounterForReal(encounter, party, placeOpts)
            end)
            return
        end
        if dmhub.Time() < deadline then
            dmhub.Schedule(0.1, PlaceOnArrival)
        elseif opts.onCancel ~= nil then
            opts.onCancel()
        end
    end
    dmhub.Schedule(0.1, PlaceOnArrival)
end

-- ===========================================================================
-- Map token drops: the drag preview, and encounters made from map tokens
-- ===========================================================================

--The dragged tokens that can join an encounter -- Bestiary monsters, as
--{token, monsterid} in drag order -- and how many others there were (heroes,
--creatures made on the map): those have no Bestiary entry to add.
local function DroppableMonsters(charids)
    local monsters = {}
    local others = 0
    for _, charid in ipairs(charids or {}) do
        local token = dmhub.GetTokenById(charid)
        if token ~= nil and token.properties ~= nil then
            local monsterid = token.bestiaryId
            if monsterid ~= nil and assets.monsters[monsterid] ~= nil then
                monsters[#monsters + 1] = { token = token, monsterid = monsterid }
            else
                others = others + 1
            end
        end
    end
    return monsters, others
end

--Split DroppableMonsters' list into one list per shared initiative (an
--initiative grouping or a minion squad), in drag order; the monsters with an
--initiative of their own share one list. Each list becomes an encounter group.
local function SplitByInitiative(monsters)
    local lists = {}
    local listsByKey = {}
    for _, entry in ipairs(monsters) do
        local key = InitiativeQueue.GetInitiativeId(entry.token) or ""
        if key == entry.token.id then
            key = ""
        end
        local list = listsByKey[key]
        if list == nil then
            list = {}
            listsByKey[key] = list
            lists[#lists + 1] = list
        end
        list[#list + 1] = entry
    end
    return lists
end

--"Goblin Warrior x2, Goblin Sniper": the monsters by type, in drag order.
local function DescribeMonsters(monsters)
    local order = {}
    local counts = {}
    for _, entry in ipairs(monsters) do
        if counts[entry.monsterid] == nil then
            order[#order + 1] = entry.monsterid
            counts[entry.monsterid] = 0
        end
        counts[entry.monsterid] = counts[entry.monsterid] + 1
    end
    local parts = {}
    for _, monsterid in ipairs(order) do
        local name = creature.GetTokenDescription(assets.monsters[monsterid])
        if counts[monsterid] > 1 then
            name = string.format("%s x%d", name, counts[monsterid])
        end
        parts[#parts + 1] = name
    end
    return table.concat(parts, ", ")
end

--The card following the mouse while map tokens are dragged over a drop target
--(tokenDragEnter/tokenDragLeave): the dragged monsters and what a release does.
local g_dropPreview = nil

local DROP_PREVIEW_MAX_IMAGES = 6

local function HideTokenDropPreview()
    if g_dropPreview ~= nil and g_dropPreview.valid then
        g_dropPreview:DestroySelf()
    end
    g_dropPreview = nil
end

--Screen pixels from the top-left to the layer's own units (the hud layers sit
--below the title bar and may be scaled).
local function ScreenToLayer(layer, px, py)
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    if below.y <= 0 then
        return px, py
    end
    local scale = layer.renderedHeight / below.y
    return px * scale, (py - (screen.y - below.y)) * scale
end

--Show the preview for a drag of charids. describe(list) turns the dragged
--monsters ("Goblin Warrior x2, Goblin Sniper") into the line saying what a drop
--does; a drag with no Bestiary monsters says why nothing will happen instead.
local function ShowTokenDropPreview(charids, describe)
    HideTokenDropPreview()

    local hud = GameHud.instance --[[@as GameHud]]
    if hud == nil then
        return
    end
    --the banner layer sits above every window, the builder included.
    local layer = hud.bannerLayer
    if layer == nil or not layer.valid then
        layer = hud.documentsPanel
    end
    if layer == nil or not layer.valid then
        return
    end

    local monsters, others = DroppableMonsters(charids)

    local images = {}
    for i, entry in ipairs(monsters) do
        if i > DROP_PREVIEW_MAX_IMAGES then
            images[#images + 1] = gui.Label {
                classes = { "fgMuted", "sizeS" },
                interactable = false,
                width = "auto",
                height = "auto",
                valign = "center",
                lmargin = 4,
                text = string.format("+%d", #monsters - DROP_PREVIEW_MAX_IMAGES),
            }
            break
        end
        images[#images + 1] = gui.CreateTokenImage(entry.token, {
            interactable = false,
            width = 36,
            height = 36,
            valign = "center",
            rmargin = 4,
        })
    end

    --the token row, then the text lines.
    local lines = {
        gui.Panel {
            interactable = false,
            width = "auto",
            height = "auto",
            flow = "horizontal",
            children = images,
        },
    }
    if #monsters > 0 then
        lines[#lines + 1] = gui.Label {
            classes = { "sizeS" },
            interactable = false,
            width = "auto",
            maxWidth = 340,
            height = "auto",
            tmargin = 6,
            text = describe(DescribeMonsters(monsters)),
        }
    end
    if others > 0 then
        local text
        if #monsters == 0 then
            text = "Only Bestiary creatures can join an encounter."
        elseif others == 1 then
            text = "1 creature has no Bestiary entry and is left out."
        else
            text = string.format("%d creatures have no Bestiary entry and are left out.", others)
        end
        lines[#lines + 1] = gui.Label {
            classes = { "warning", "sizeXs" },
            interactable = false,
            width = "auto",
            maxWidth = 340,
            height = "auto",
            tmargin = 4,
            text = text,
        }
    end

    local styles = ThemeEngine.MergeStyles({
        {
            selectors = { "encounterDropPreview" },
            borderColor = "@accent",
            borderWidth = 2,
            cornerRadius = 6,
        },
    })

    --where the card sits: below and right of the pointer, clear of the hit
    --test that finds the drop target under the mouse.
    local function Follow(element)
        local mouse = dmhub.mouseScreenPosition
        element.x, element.y = ScreenToLayer(layer, mouse.x + 18, mouse.y + 22)
    end

    local preview = gui.Panel {
        classes = { "encounterDropPreview", "bordered", "bg" },
        styles = styles,
        interactable = false,
        halign = "left",
        valign = "top",
        width = "auto",
        height = "auto",
        flow = "vertical",
        hpad = 10,
        vpad = 8,
        borderBox = true,
        bgimage = true,

        thinkTime = 0.01,
        think = function(element)
            --a drag that ended without a leave (cancelled, say) takes the card with it.
            if mod.unloaded or dmhub.tokenDropTargetUnderMouse == nil then
                HideTokenDropPreview()
                return
            end
            Follow(element)
        end,

        children = lines,
    }

    layer:AddChild(preview)
    preview:SetAsLastSibling()
    Follow(preview)
    g_dropPreview = preview
end

--Tag a token as one of a plan group's staged monsters, exactly as staging tags
--the tokens it spawns, so the builder banks, collects and places it.
local function StampStagedToken(token, group, slot, monsterid)
    token:ModifyProperties {
        description = "Add to encounter",
        undoable = false,
        combine = true,
        execute = function()
            token.properties.encounterPlacementId = group.placementid
            token.properties.encounterSpawnSlot = slot
            token.properties.encounterSpawnMonster = monsterid
            token.properties.encounterStaged = true
            token.properties.encounterStagedBy = dmhub.userid
        end,
    }
end

--Make and save a new encounter from monsters on the map (map tokens dropped on
--the Encounters panel), then open it in the builder. Monsters sharing an
--initiative (an initiative grouping or a minion squad) become one group; the
--monsters with an initiative of their own go into one group together. The
--tokens stay where they are as the plan's staged monsters, with their
--positions already saved. Returns the saved encounter, or nil.
function Encounter.CreateFromTokens(charids)
    local monsters, others = DroppableMonsters(charids)
    if #monsters == 0 then
        if others > 0 then
            gui.ModalMessage {
                title = "Not a Bestiary Monster",
                message = "Only creatures from the Bestiary can join an encounter. Heroes and creatures made on the map have no Bestiary entry to add.",
            }
        end
        return nil
    end

    local encounter = Encounter.new()
    encounter.groups = {}
    encounter.mapid = game.currentMapId

    --the monster list names the encounter while it fits the builder's name field.
    local name = DescribeMonsters(monsters)
    if #name <= 40 then
        encounter.name = name
    end

    for _, list in ipairs(SplitByInitiative(monsters)) do
        local group = { monsters = {}, placementid = dmhub.GenerateGuid() }
        encounter.groups[#encounter.groups + 1] = group
        for slot, entry in ipairs(list) do
            group.monsters[entry.monsterid] = (group.monsters[entry.monsterid] or 0) + 1
            StampStagedToken(entry.token, group, slot, entry.monsterid)
        end
    end

    for _, group in ipairs(encounter.groups) do
        BankGroupPositions(group, encounter.saveAppearances)
    end
    BankStagedMounts(encounter)

    local id = dmhub.SetAndUploadTableItem("encounters", encounter)

    --the builder edits a copy, as the list's own edit button does.
    local copy = DeepCopy(encounter)
    copy.id = id
    Encounter.CreateEditorDialog(copy, { mode = "Save" })
    return encounter
end

--Monsters on the plan's map that it does not account for, as charids in map
--order: Bestiary monsters that are not heroes' allies or summons, not staged
--or placed by this plan (or spawned by an earlier play of it), and not tagged
--to another saved plan. Empty unless the plan's map is the one open, since
--only its tokens are loaded.
local function MonstersOnMapNotInEncounter(encounter)
    local mapid = encounter.mapid
    if mapid == nil or mapid == "" or mapid ~= game.currentMapId then
        return {}
    end

    local myId = encounter:try_get("id")
    local ownPids = {}
    for _, group in ipairs(encounter.groups) do
        if group.placementid ~= nil then
            ownPids[group.placementid] = true
        end
    end

    local otherIds = {}
    local otherPids = {}
    for id, other in unhidden_pairs(dmhub.GetTable("encounters") or {}) do
        if id ~= myId then
            otherIds[id] = true
            for _, group in ipairs(other:try_get("groups", {})) do
                if group.placementid ~= nil then
                    otherPids[group.placementid] = true
                end
            end
        end
    end

    local charids = {}
    for _, tok in ipairs(dmhub.allTokens) do
        local props = tok.properties
        local monsterish = false
        pcall(function() monsterish = props ~= nil and props:IsMonster() == true end)
        if monsterish and not IsPlayerSideToken(tok) and (tok.summonerid == nil or tok.summonerid == "")
            and tok.bestiaryId ~= nil and assets.monsters[tok.bestiaryId] ~= nil then
            local pid = props:try_get("encounterPlacementId")
            local source = props:try_get("encounterSourceId")
            local claimed = (pid ~= nil and (ownPids[pid] or otherPids[pid]))
                or (source ~= nil and (source == myId or otherIds[source]))
            if not claimed then
                charids[#charids + 1] = tok.charid
            end
        end
    end
    return charids
end

--What kind of shared initiative a SplitByInitiative list is on, for its row.
local function InitiativeListKind(list)
    local token = list[1].token
    local key = InitiativeQueue.GetInitiativeId(token)
    if key == nil or key == token.id then
        return cond(#list > 1, "Each on its own initiative", "Own initiative")
    end
    if token.properties.initiativeGrouping then
        return "Shared initiative"
    end
    return "Minion squad"
end

local MAP_MONSTERS_MAX_IMAGES = 6

--The builder's "On the Map" card: monsters standing on the plan's map that are
--not in it (MonstersOnMapNotInEncounter), one row per shared initiative as on
--the map, each with a button that adds it as a group. Adding goes through
--adoptTokens -- the same path as dragging the tokens onto the builder -- so the
--monsters stay where they are as the plan's staged tokens. Polls the map once
--a second; hidden while there is nothing to add.
local function CreateMapMonstersSection(args)
    local encounter = args.encounter
    local adoptTokens = args.adoptTokens

    local m_signature = nil
    local m_charids = {}

    local countBadge = gui.Label {
        classes = { "encounterBadge" },
        width = "auto",
        height = "auto",
        valign = "center",
        text = "",
    }

    local rowsPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local body = gui.Panel {
        classes = { "featureCardBody" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 4,
        borderBox = true,
        rowsPanel,
    }

    local card = gui.Panel {
        classes = { "featureCard", "hidden" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        bmargin = 8,

        gui.Panel {
            classes = { "featureCardHeader", "expanded" },
            width = "100%",
            height = 32,
            flow = "horizontal",

            --the header folds the rows away, for a map crowded with monsters
            --that belong to no plan.
            press = function(element)
                local expanded = not element:HasClass("expanded")
                element:SetClass("expanded", expanded)
                body:SetClass("hidden", not expanded)
            end,

            gui.Label {
                classes = { "sizeS", "bold" },
                width = "auto",
                height = "auto",
                valign = "center",
                lmargin = 10,
                text = "On the Map",
            },

            gui.Label {
                classes = { "fgMuted", "sizeXs" },
                width = "auto",
                height = "auto",
                valign = "center",
                lmargin = 8,
                text = "not in this encounter",
            },

            gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                valign = "center",
                halign = "right",
                rmargin = 8,

                countBadge,

                gui.Button {
                    classes = { "sizeS" },
                    valign = "center",
                    lmargin = 8,
                    text = "Add All",
                    swallowPress = true,
                    hover = gui.Tooltip("Add every monster listed here, one group per initiative group."),
                    press = function(element)
                        adoptTokens(m_charids, nil)
                    end,
                },
            },
        },

        body,
    }

    local function CreateRow(list)
        local charids = {}
        local images = {}
        for i, entry in ipairs(list) do
            charids[#charids + 1] = entry.token.charid
            if i <= MAP_MONSTERS_MAX_IMAGES then
                images[#images + 1] = gui.CreateTokenImage(entry.token, {
                    interactable = false,
                    width = 32,
                    height = 32,
                    valign = "center",
                    rmargin = 4,
                })
            elseif i == MAP_MONSTERS_MAX_IMAGES + 1 then
                images[#images + 1] = gui.Label {
                    classes = { "fgMuted", "sizeXs" },
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    rmargin = 4,
                    text = string.format("+%d", #list - MAP_MONSTERS_MAX_IMAGES),
                }
            end
        end

        --a fixed-height row with single-line, auto-width text: percent-wide
        --labels in an auto-height column measured as wrapping at zero width
        --and blew each row up to hundreds of pixels tall.
        return gui.Panel {
            width = "100%",
            height = 40,
            flow = "horizontal",
            hpad = 10,
            borderBox = true,

            gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                valign = "center",
                children = images,
            },

            gui.Panel {
                width = "auto",
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = 6,

                gui.Label {
                    classes = { "sizeS" },
                    width = "auto",
                    maxWidth = 340,
                    height = "auto",
                    textWrap = false,
                    textOverflow = "ellipsis",
                    text = DescribeMonsters(list),
                },

                gui.Label {
                    classes = { "fgMuted", "sizeXxs" },
                    width = "auto",
                    height = "auto",
                    textWrap = false,
                    text = InitiativeListKind(list),
                },
            },

            gui.Button {
                classes = { "sizeS" },
                valign = "center",
                halign = "right",
                lmargin = 8,
                text = "Add Group",
                hover = gui.Tooltip("Add these monsters to the encounter as an initiative group. They stay where they are, staged with the plan."),
                press = function(element)
                    adoptTokens(charids, nil)
                end,
            },
        }
    end

    --rebuild the rows when the map's unclaimed monsters, or how they share
    --initiative, have changed since last time (or always, when force is set).
    local function Update(force)
        local charids = MonstersOnMapNotInEncounter(encounter)
        local monsters = DroppableMonsters(charids)
        local parts = {}
        for _, entry in ipairs(monsters) do
            parts[#parts + 1] = entry.token.charid .. "=" .. tostring(InitiativeQueue.GetInitiativeId(entry.token))
        end
        local signature = table.concat(parts, ",")
        if signature == m_signature and not force then
            return
        end
        m_signature = signature
        m_charids = charids

        card:SetClass("hidden", #monsters == 0)
        if #monsters == 0 then
            rowsPanel.children = {}
            return
        end

        countBadge.text = string.format("%d monster%s", #monsters, cond(#monsters == 1, "", "s"))

        --shared initiatives first, the monsters on their own last.
        local shared = {}
        local solo = {}
        for _, list in ipairs(SplitByInitiative(monsters)) do
            local token = list[1].token
            local key = InitiativeQueue.GetInitiativeId(token)
            if key == nil or key == token.id then
                solo[#solo + 1] = list
            else
                shared[#shared + 1] = list
            end
        end
        local rows = {}
        for _, list in ipairs(shared) do
            rows[#rows + 1] = CreateRow(list)
        end
        for _, list in ipairs(solo) do
            rows[#rows + 1] = CreateRow(list)
        end
        rowsPanel.children = rows
    end

    --the wrapper is never hidden, so it keeps thinking while the card is.
    --Sized like the wave sections below it, leaving the scrollbar its room.
    return gui.Panel {
        width = "100%-14",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",

        thinkTime = 1,
        think = function(element)
            if mod.unloaded then
                return
            end
            Update(false)
        end,

        create = function(element)
            Update(true)
        end,

        --monsters were just added, or the plan's map changed.
        rebuildGroups = function(element)
            Update(true)
        end,
        refreshBuilder = function(element)
            Update(false)
        end,

        card,
    }
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

    --plans saved before the map and the staging were kept in step: infer a
    --missing map from the staging, drop staging banked on another map. Leaves
    --the plan dirty (m_savedSnapshot below) so Save keeps the repair.
    local reconciledOnOpen = ReconcileStagingWithMap(self)

    --Refresh each attached encounter script's cached name/victory text so
    --library edits made since this encounter was last opened are reflected.
    for _, scriptInstance in ipairs(self:GetScripts()) do
        pcall(function() scriptInstance:RefreshCache() end)
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

    --rule sets and encounter scripts are rarely-used whole-encounter settings:
    --they live behind a small settings cog in the header, with a count label
    --when any are attached, instead of taking a dedicated section in the
    --layout. (Script PARAMETERS surface on the party bar.)
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
            local scriptCount = #self:GetScripts()
            element:SetClass("hidden", count == 0 and scriptCount == 0)
            local parts = {}
            if count > 0 then
                parts[#parts + 1] = string.format("%d rule set%s", count, cond(count == 1, "", "s"))
            end
            if scriptCount > 0 then
                parts[#parts + 1] = string.format("%d script%s", scriptCount, cond(scriptCount == 1, "", "s"))
            end
            element.text = table.concat(parts, ", ")
        end,
    }

    local ruleSetsButton = gui.SettingsButton {
        width = 16,
        height = 16,
        valign = "center",
        lmargin = 12,
        hover = gui.Tooltip("Rule sets and encounter scripts attached to this encounter."),
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

                gui.Panel { width = "100%", height = 12 },

                FieldCaption("Encounter scripts", "left"),

                createEncounterScriptsPanel(self, refresh),
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
        --who was riding whom, banked while every group's tokens are still up.
        BankStagedMounts(self)
        --no map chosen yet: the map the plan was staged on becomes it.
        if self.mapid == "" then
            ReconcileStagingWithMap(self)
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

    local m_savedSnapshot = nil
    if not reconciledOnOpen then
        m_savedSnapshot = SnapshotPlan()
    end

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

    --Monsters dragged off the map and dropped on the builder (the panels are
    --tokenDropTarget, so the engine fires dropTokens): staging in reverse. Each
    --monster joins targetGroup and is tagged exactly as staging tags the tokens
    --it spawns, so it banks, collects and places with the plan from then on.
    --A plan with no map yet takes the map the monsters are on.
    --A drop beside the cards (targetGroup nil) splits the monsters into one
    --group per shared initiative, as a drop on the Encounters list does: the
    --first fills the active group while it is still empty, the rest are new
    --groups. A monster already in another of this plan's groups moves over;
    --one already in targetGroup is left alone.
    local function AdoptDroppedTokens(charids, targetGroup)
        local tokens, skipped = DroppableMonsters(charids)

        if #tokens == 0 then
            if skipped > 0 then
                gui.ModalMessage {
                    title = "Not a Bestiary Monster",
                    message = "Only creatures from the Bestiary can join an encounter. Heroes and creatures made on the map have no Bestiary entry to add.",
                }
            end
            return
        end

        --no map chosen yet (not even a library map still to add): the
        --monsters' map, the one on screen, becomes it.
        if self.mapid == "" and self:GetMapRef() == nil and game.currentMap ~= nil then
            self.mapid = game.currentMapId
        end

        --each group the drop fills, by its index in self.groups, and the
        --monsters it takes. Indices, because AddGroup deep-copies the groups
        --array: every group is made before any group table is held.
        --- @type {index: integer, tokens: table[]}[]
        local batches = {}
        if targetGroup ~= nil then
            for i, g in ipairs(self.groups) do
                if g == targetGroup then
                    batches[1] = { index = i, tokens = tokens }
                end
            end
        else
            local activeIndex = nil
            for i, g in ipairs(self.groups) do
                if g == state.activeGroup and next(g.monsters) == nil then
                    activeIndex = i
                end
            end
            for i, list in ipairs(SplitByInitiative(tokens)) do
                local index = activeIndex
                if i > 1 or index == nil then
                    self:AddGroup()
                    index = #self.groups
                end
                batches[#batches + 1] = { index = index, tokens = list }
            end
        end
        if #batches == 0 then
            return
        end

        local emptiedGroups = {}
        for _, batch in ipairs(batches) do
            local groupIndex = batch.index
            local group = self.groups[groupIndex]

            if group.placementid == nil then
                group.placementid = dmhub.GenerateGuid()
            end

            --A group whose positions are saved but not on the map would bank only
            --the newcomers on the next save, losing everyone else's tile. Bring its
            --saved arrangement back first so the whole group is staged together.
            local live = PlacedTokensForGroup(group)
            if #live == 0 and GroupHasUsableStaging(self, group) then
                for _, token in ipairs(StageGroupAtSavedLocations(self, groupIndex, group, party.numHeroes, group.placementid)) do
                    live[#live + 1] = token
                end
            end

            local nextSlot = 1
            for _, token in ipairs(live) do
                nextSlot = math.max(nextSlot, token.properties:try_get("encounterSpawnSlot", 0) + 1)
            end

            for _, entry in ipairs(batch.tokens) do
                local token = entry.token
                local monsterid = entry.monsterid
                local placementid = token.properties:try_get("encounterPlacementId")

                local oldGroup = nil
                if placementid ~= nil then
                    for _, g in ipairs(self.groups) do
                        if g.placementid == placementid then
                            oldGroup = g
                        end
                    end
                end

                if oldGroup ~= group or token.properties:try_get("encounterStaged") == false then
                    --already counted in this plan's roster: move the count over
                    --rather than adding a second copy.
                    if oldGroup == nil then
                        group.monsters[monsterid] = (group.monsters[monsterid] or 0) + 1
                    elseif oldGroup ~= group then
                        local oldMonster = token.properties:try_get("encounterSpawnMonster") or monsterid
                        local count = (oldGroup.monsters[oldMonster] or 0) - 1
                        oldGroup.monsters[oldMonster] = cond(count > 0, count, nil)
                        if next(oldGroup.monsters) == nil then
                            emptiedGroups[#emptiedGroups + 1] = oldGroup
                        end
                        group.monsters[monsterid] = (group.monsters[monsterid] or 0) + 1
                    end

                    StampStagedToken(token, group, nextSlot, monsterid)
                    nextSlot = nextSlot + 1
                end
            end
        end

        --held before the removals below shift the indices.
        local firstGroup = self.groups[batches[1].index]

        --a group the drop took its last monster from goes, as removing the
        --last monster by hand does (RemoveMonsterFromGroup in the card).
        for _, emptied in ipairs(emptiedGroups) do
            for i = #self.groups, 1, -1 do
                if self.groups[i] == emptied and next(emptied.monsters) == nil then
                    table.remove(self.groups, i)
                    self:RepairMountsAfterGroupRemoved(i)
                end
            end
        end

        state.activeGroup = firstGroup
        rebuild()
    end

    --The drag preview's line for a drop on targetGroup's card, or (nil) beside
    --the cards: the group AdoptDroppedTokens would put the monsters in.
    local function PreviewDroppedTokens(charids, targetGroup)
        local group = targetGroup
        if group == nil then
            group = state.activeGroup
            if group ~= nil and next(group.monsters) ~= nil then
                group = nil
            end
        end

        local groupName = nil
        for i, g in ipairs(self.groups) do
            if g == group then
                groupName = GroupName(self, g, i)
            end
        end

        --beside the cards, monsters on different initiatives split up.
        local numGroups = 1
        if targetGroup == nil then
            numGroups = #SplitByInitiative((DroppableMonsters(charids)))
        end

        ShowTokenDropPreview(charids, function(list)
            if numGroups > 1 then
                return string.format("Split %s into %d groups by initiative", list, numGroups)
            end
            if groupName == nil then
                return string.format("Start a new group with %s", list)
            end
            return string.format("Add %s to %s", list, groupName)
        end)
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
                    refresh()
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

        --optional description, saved with the plan alongside the name, and
        --the map the encounter takes place on beside it.
        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 6,

            gui.Input {
                classes = { "form" },
                width = string.format("100%%-%d", MAP_CARD_WIDTH + 12),
                height = "auto",
                minHeight = MAP_CARD_HEIGHT,
                valign = "top",
                borderBox = true,
                fontSize = 13,
                multiline = true,
                textAlignment = "topleft",
                characterLimit = 2000,
                placeholderText = "Add a description...",
                text = self.description,
                change = function(element)
                    self.description = element.text
                    refresh()
                end,
            },

            CreateEncounterAreaBadges(self, refresh),
        },

        CreatePartyBar(self, party, refresh, rebuild, CreateBudgetDial(self, party)),

        --the two-pane body: bestiary browser left, composition right. Monsters
        --dragged off the map and dropped here join the plan as if staged
        --(AdoptDroppedTokens); a group card takes the drops over it. The clear
        --bgimage makes the gaps between the panes catch the drop too.
        gui.Panel {
            classes = { "encounterTokenDrop" },
            width = "100%",
            height = "100% available",
            flow = "horizontal",
            tmargin = 6,
            bgimage = true,
            bgcolor = "clear",

            tokenDropTarget = true,
            dropTokens = function(element, info)
                AdoptDroppedTokens(info.charids, nil)
            end,
            tokenDragEnter = function(element, info)
                PreviewDroppedTokens(info.charids, nil)
            end,
            tokenDragLeave = function(element)
                HideTokenDropPreview()
            end,

            CreateBestiaryPane(party, addMonster),

            gui.Panel {
                width = "100%-352",
                height = "100%",
                lmargin = 12,
                flow = "vertical",
                vscroll = true,

                CreateMapMonstersSection {
                    encounter = self,
                    adoptTokens = AdoptDroppedTokens,
                },

                CreateWaveSections {
                    encounter = self,
                    party = party,
                    state = state,
                    refresh = refresh,
                    rebuild = rebuild,
                    adoptTokens = AdoptDroppedTokens,
                    previewTokens = PreviewDroppedTokens,
                    hideTokenPreview = HideTokenDropPreview,
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
                    refresh()
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
                                owner = button,
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
                            owner = button,
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
                    hover = gui.Tooltip("Save the plan, place monsters at their saved positions, and get it ready on its map to Draw Steel."),
                    press = function(button)
                        local count = 0
                        for _, group in ipairs(self.groups) do
                            count = count + AdjustedGroupCount(group, party.numHeroes)
                        end
                        if count == 0 then
                            gui.ModalMessage {
                                owner = button,
                                title = "Nothing to Start",
                                message = "Add monsters to the encounter before starting it.",
                            }
                            return
                        end

                        SavePlan()
                        local editorPanel = button:FindParentWithClass("editorPanel")
                        editorPanel:SetClass("hidden", true)
                        Encounter.StartEncounterOnItsMap(self, party, {
                            start = true,
                            persist = PersistPlan,
                            mapRefInPlace = true,
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

--Builder window size: the default it opens at, and the smallest it can be
--resized to (below this the bestiary column and group cards stop fitting).
local EDITOR_DEFAULT_WIDTH = 1240
local EDITOR_DEFAULT_HEIGHT = 920
local EDITOR_MIN_WIDTH = 860
local EDITOR_MIN_HEIGHT = 640

--Where the user last left the builder window this session. gui.WindowResizePanel
--reads and writes _tmp_location through try_get, so this table quacks like a
--document (same trick as CommandBuilder's dialog).
local g_editorLocation = {
    try_get = function(self, key)
        return rawget(self, key)
    end,
}

function Encounter.CreateEditorDialog(encounter, options)
    local editorPanel

    local editorContent = Encounter.Editor(encounter, options)

    --open at the remembered size and place, else the default size centred;
    --clamped so the window fits a screen that may have shrunk since.
    local screen = dmhub.screenDimensionsBelowTitlebar
    local maxWidth = math.max(EDITOR_MIN_WIDTH, screen.x)
    local maxHeight = math.max(EDITOR_MIN_HEIGHT, screen.y)
    local loc = g_editorLocation:try_get("_tmp_location")
    local width = math.min(EDITOR_DEFAULT_WIDTH, maxWidth)
    local height = math.min(EDITOR_DEFAULT_HEIGHT, maxHeight)
    if loc ~= nil then
        width = math.max(EDITOR_MIN_WIDTH, math.min(loc.width or width, maxWidth))
        height = math.max(EDITOR_MIN_HEIGHT, math.min(loc.height or height, maxHeight))
    end
    local x = math.floor((screen.x - width) / 2)
    local y = math.floor((screen.y - height) / 2)
    if loc ~= nil and loc.x ~= nil and loc.y ~= nil then
        x = math.max(0, math.min(loc.x, screen.x - width))
        y = math.max(0, math.min(loc.y, screen.y - height))
    end

    editorPanel = gui.Panel {

        classes = { "editorPanel" },
        styles = BuilderStyles(),

        --gui.WindowResizePanel's contract: anchored top-left with numeric x/y
        --and a numeric selfStyle width/height it can rewrite while dragging.
        --The content inside is percent-sized, so it follows the window.
        style = {
            width = width,
            height = height,
            halign = "left",
            valign = "top",
        },
        x = x,
        y = y,

        --a window like the journal and table windows, in the same layer
        --(GameHud.documentsPanel): a press anywhere brings it to the front,
        --presses stay inside it, and dragging empty space moves it.
        bgimage = true,
        bgcolor = "clear",
        raiseOnPress = true,
        swallowPress = true,
        draggable = true,
        drag = function(element)
            element.x = element.xdrag
            element.y = element.ydrag
            element:SetAsLastSibling()
            g_editorLocation._tmp_location = {
                x = element.x,
                y = element.y,
                width = element.selfStyle.width,
                height = element.selfStyle.height,
                moved = true,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y,
            }
        end,

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
                        owner = editorPanel,
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

        },

        --resize handles on every edge and corner; must stay the last child so
        --they sit above the content (sibling order is z-order).
        gui.WindowResizePanel(g_editorLocation, width, height, {
            minWidth = EDITOR_MIN_WIDTH,
            minHeight = EDITOR_MIN_HEIGHT,
            maxWidth = maxWidth,
            maxHeight = maxHeight,
        }),

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

    --the Delves section's tree nodes by key, and which were open when the
    --list was last rebuilt.
    --- @type table<string, Panel>
    local delveNodes = {}
    --- @type table<string, boolean>
    local openDelveNodes = {}

    --monsters dragged off the map and dropped on the list become a new
    --encounter (Encounter.CreateFromTokens); minHeight keeps a drop zone when
    --the list is short or empty.
    local function ListStyles()
        return ThemeEngine.MergeStyles({
            {
                selectors = { "encounterListDrop", "token-drop-hover" },
                borderColor = "@accent",
                borderWidth = 2,
                cornerRadius = 4,
            },
        })
    end

    inspectorPanel = gui.Panel {
        id = "inspector-panel",
        classes = { "encounterListDrop" },
        styles = ListStyles(),
        hpad = 6,
        width = "100%",
        height = "auto",
        minHeight = 160,
        flow = "vertical",
        monitorAssets = true,
        bgimage = true,
        bgcolor = "clear",

        tokenDropTarget = true,

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

            tokenDragEnter = function(panel, info)
                ShowTokenDropPreview(info.charids, function(list)
                    return string.format("Create a new encounter from %s", list)
                end)
            end,

            tokenDragLeave = function(panel)
                HideTokenDropPreview()
            end,

            dropTokens = function(panel, info)
                HideTokenDropPreview()
                Encounter.CreateFromTokens(info.charids)
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

                --shipped book encounters (Encounter:GetBookInfo) go under a
                --Delves section, grouped by delve, instead of the flat list.
                --Which tree nodes are open survives the rebuild.
                for key, node in pairs(delveNodes) do
                    if node.valid then
                        openDelveNodes[key] = not node.data.isCollapsed()
                    end
                end
                delveNodes = {}
                local delves = {}
                local delveList = {}

                for key, encounter in unhidden_pairs(encounters) do
                    local monstertable = encounter.monsters

                    --choose boss monster to be 'head' of the encounter

                    local highestev = 0
                    local headmonster = nil

                    for key, quantity in pairs(monstertable) do
                        local currentmonster = assets.monsters[key]

                        if currentmonster ~= nil then
                            if headmonster == nil then
                                headmonster = currentmonster
                            end

                            if currentmonster.properties:EV() > highestev then
                                highestev = currentmonster.properties:EV()
                                headmonster = currentmonster
                            end
                        end
                    end

                    local headmonsteravatar = true

                    if headmonster ~= nil then
                        headmonsteravatar = headmonster.appearance.portraitId
                    end

                    --boss/headmonster code over

                    local card = gui.Panel {

                        classes = { "featureCard" },
                        width = "90%",
                        height = 110,
                        halign = "left",
                        flow = "vertical",
                        pad = 1,
                        vmargin = 8,
                        draggable = true,

                        --The engine finds drag targets by rectangle overlap, so a
                        --folder BEHIND a map window would catch a drop on the map:
                        --over the board (panelDropSurface set) nothing else counts.
                        canDragOnto = function(self, target)
                            if dmhub.panelDropSurface ~= nil then
                                return false
                            end
                            return target ~= nil and target:HasClass("folder")
                        end,

                        --over the bare table the card turns into the encounter's
                        --map window, following the mouse (the Maps panel's row
                        --drag: the card steps aside while the preview shows).
                        dragging = function(self, target)
                            --over the chat it is a link to the encounter's map
                            --(the encounter itself stays the Director's); over a
                            --journal document you can edit it adds a copy of the
                            --encounter where it is dropped.
                            ChatItemLinks.Dragging(function()
                                local map = EncounterMap(encounter)
                                return {ChatItemLinks.MapItem(map ~= nil and map.id or nil)}
                            end, {
                                dropItems = function()
                                    ---@type ItemLinkDrop
                                    local item = {kind = "richtag", richTag = RichEncounter.FromEncounter(encounter), name = encounter.name}
                                    return {item}
                                end,
                            })
                            if target == nil then
                                --the preview is the encounter's own map (a
                                --Map Library one the game lacks shows by name),
                                --shaped like the encounter's area.
                                local map = EncounterMap(encounter)
                                local ref = encounter:GetMapRef()
                                local _, aspect = Encounter.FrameArea(encounter)
                                if map ~= nil then
                                    Tabletop.MapRowDragging(self, map.id, { aspect = aspect })
                                elseif ref ~= nil then
                                    local found = Encounter.FindLibraryMap(ref)
                                    Tabletop.MapRowDragging(self, found ~= nil and found.id or nil, { aspect = aspect, name = ref.name })
                                else
                                    Tabletop.MapRowDragging(self, game.currentMapId)
                                end
                            else
                                Tabletop.MapRowDragEnded(self)
                            end
                        end,

                        --dropping on a document adds a copy of this encounter to it
                        --(through ChatItemLinks.Dropped); dropping on the board
                        --starts it there (into prep). On the table, the map's
                        --window goes where it was dropped first.
                        drag = function(self, target)
                            Tabletop.MapRowDragEnded(self)
                            if ChatItemLinks.Dropped() then
                                return
                            end
                            local surface = dmhub.panelDropSurface
                            --a Map Library map is found or added first; its
                            --window then opens at the drop (tableDrop).
                            local tableDrop = false
                            if surface == "table" then
                                local map = EncounterMap(encounter)
                                if map ~= nil then
                                    --the window takes the encounter's shape and
                                    --zooms to it once it shows the map.
                                    local area, aspect = Encounter.FrameArea(encounter)
                                    Tabletop.MapRowDropped(map.id, { aspect = aspect, frame = area })
                                elseif encounter:GetMapRef() ~= nil then
                                    tableDrop = true
                                else
                                    Tabletop.MapRowDropped(game.currentMapId)
                                end
                            end
                            if surface == "map" or surface == "table" then
                                --a drop on the map that is already the encounter's
                                --is where its unstaged groups go.
                                local anchor = nil
                                if surface == "map" and (encounter.mapid == "" or encounter.mapid == game.currentMapId) then
                                    anchor = dmhub.GetMouseWorldPoint()
                                end
                                Encounter.StartEncounterOnItsMap(encounter, DefaultParty(), {
                                    start = true,
                                    tableDrop = tableDrop,
                                    anchor = anchor,
                                    persist = function()
                                        dmhub.SetAndUploadTableItem("encounters", encounter)
                                    end,
                                })
                            end
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
                                    if mainmonster == nil then
                                        return
                                    end

                                    local portrait = mainmonster.appearance:GetPortraitId()
                                    if panel.bgimage ~= portrait then
                                        panel.bgimage = portrait
                                    end

                                    --Crop the portrait to this panel's own
                                    --proportions rather than letting it stretch to
                                    --fill. The panel is a tall slice of the card, so
                                    --an uncropped portrait came out visibly squashed.
                                    --GetPortraitRectForAspect wants width as a
                                    --fraction of height, and lives on the token view
                                    --of the asset (MonsterAsset.info), not on the
                                    --asset itself. Measured from the rendered size so
                                    --the crop stays right at any dock width.
                                    local token = mainmonster.info
                                    local w = panel.renderedWidth
                                    local h = panel.renderedHeight
                                    if token ~= nil and w ~= nil and h ~= nil and w > 0 and h > 0 then
                                        panel.selfStyle.imageRect = token:GetPortraitRectForAspect(w/h, portrait)
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
                        --place at saved positions and get it ready to fight.
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
                            hover = gui.Tooltip("Place monsters at their saved positions on the encounter's map, ready to Draw Steel."),
                            swallowPress = true,
                            press = function(element)
                                Encounter.StartEncounterOnItsMap(encounter, DefaultParty(), {
                                    start = true,
                                    persist = function()
                                        dmhub.SetAndUploadTableItem("encounters", encounter)
                                    end,
                                })
                            end,
                        },

                    }

                    local book = encounter:GetBookInfo()
                    if book ~= nil then
                        local delve = delves[book.delve]
                        if delve == nil then
                            delve = { name = book.delve, level = tonumber(book.level) or 0, cards = {} }
                            delves[book.delve] = delve
                            delveList[#delveList + 1] = delve
                        end
                        delve.cards[#delve.cards + 1] = { area = tostring(book.area or ""), name = encounter.name, card = card }
                    else
                        children[index] = card
                        index = index + 1
                    end
                end

                if #delveList > 0 then
                    table.sort(delveList, function(a, b)
                        if a.level ~= b.level then
                            return a.level < b.level
                        end
                        return a.name < b.name
                    end)

                    local delvePanels = {}
                    for _, delve in ipairs(delveList) do
                        table.sort(delve.cards, function(a, b)
                            if a.area ~= b.area then
                                return a.area < b.area
                            end
                            return a.name < b.name
                        end)
                        local cards = {}
                        for i, entry in ipairs(delve.cards) do
                            cards[i] = entry.card
                        end
                        local key = "delve:" .. delve.name
                        local node = gui.TreeNode {
                            text = cond(delve.level > 0, string.format("Level %d: %s", delve.level, delve.name), delve.name),
                            width = "100%",
                            expanded = openDelveNodes[key] == true,
                            contentPanel = gui.Panel {
                                width = "100%",
                                height = "auto",
                                flow = "vertical",
                                lmargin = 12,
                                children = cards,
                            },
                        }
                        delveNodes[key] = node
                        delvePanels[#delvePanels + 1] = node
                    end

                    local sectionKey = "delves"
                    local section = gui.TreeNode {
                        text = "Delves (Draw Steel: Encounters)",
                        width = "100%",
                        expanded = openDelveNodes[sectionKey] == true,
                        contentPanel = gui.Panel {
                            width = "100%",
                            height = "auto",
                            flow = "vertical",
                            lmargin = 8,
                            children = delvePanels,
                        },
                    }
                    delveNodes[sectionKey] = section
                    children[index] = section
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
            inspectorPanel.styles = ListStyles()
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
