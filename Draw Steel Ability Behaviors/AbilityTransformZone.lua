local mod = dmhub.GetModLoading()

--Transform Zone: turns a map-markup zone of one Environmental Keyword into a
--zone of another (or removes it), e.g. igniting a patch of Flammable Oil into
--Burning Oil, or rendering it safe. The WHOLE zone record touching the chosen
--squares is converted -- one painted patch is one record, so "the patch"
--changes as a unit.
--
--Which squares count is set by `location`:
--  "targets"  - the squares of each target (a creature's occupied squares, or
--               the chosen square of a square-targeting ability).
--  "adjacent" - those squares plus every square 8-adjacent to them. A
--               self-targeted "deactivate the trap next to you" uses this.
--  "area"     - every square of the ability's area (options.targetArea, e.g.
--               a cube), whether or not anyone stands there. A non-area
--               ability has no area, so it matches nothing.
--
--When nothing matches, the rest of the ability is skipped (abortIfNone), so a
--"transform, then damage the creature" ability never deals its damage twice
---- a second trigger arriving after the zone already converted finds nothing.

--- @class ActivatedAbilityTransformZoneBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityTransformZoneBehavior
--- @field fromKeyword string Id (environmentalKeywords key) of the keyword whose zones are transformed. Empty = the behavior does nothing.
--- @field toKeyword string Id of the keyword the zones become, or "none" to remove the zones.
--- @field location "targets"|"adjacent"|"area" Which squares pick the zones: the targets' own squares, those plus every adjacent square, or every square of the ability's area.
--- @field reveal boolean When true, a transformed zone becomes visible to players.
--- @field abortIfNone boolean When true, the rest of the ability is skipped if no zone was transformed.
ActivatedAbilityTransformZoneBehavior = RegisterGameType("ActivatedAbilityTransformZoneBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityTransformZoneBehavior.summary = 'Transform Zone'
ActivatedAbilityTransformZoneBehavior.fromKeyword = ""
ActivatedAbilityTransformZoneBehavior.toKeyword = "none"
ActivatedAbilityTransformZoneBehavior.location = "targets"
ActivatedAbilityTransformZoneBehavior.reveal = true
ActivatedAbilityTransformZoneBehavior.abortIfNone = true

ActivatedAbility.RegisterType
{
    id = 'transform_zone',
    text = 'Transform Zone',
    createBehavior = function()
        return ActivatedAbilityTransformZoneBehavior.new{
        }
    end
}

local function KeywordName(keywordid)
    if keywordid == nil or keywordid == "" then
        return nil
    end
    if keywordid == "none" then
        return "nothing"
    end
    local keyword = (dmhub.GetTable(EnvironmentalKeyword.tableName) or {})[keywordid]
    if keyword == nil then
        return nil
    end
    return keyword.name
end

function ActivatedAbilityTransformZoneBehavior:SummarizeBehavior(ability, creatureLookup)
    local fromName = KeywordName(self.fromKeyword) or "(no zone type)"
    if self.toKeyword == "none" then
        return string.format("Remove %s", fromName)
    end
    return string.format("Turn %s into %s", fromName, KeywordName(self.toKeyword) or "(no zone type)")
end

--The squares each target contributes, as engine Locs.
local function TargetSquares(targets, includeAdjacent)
    local result = {}
    local seen = {}
    local function Add(loc)
        local key = string.format("%d,%d,%d", loc.x, loc.y, loc.floor or 0)
        if seen[key] == nil then
            seen[key] = true
            result[#result+1] = loc
        end
    end

    for _,target in ipairs(targets or {}) do
        local squares = {}
        if target.token ~= nil and target.token.valid then
            squares = target.token.locsOccupying or {}
        elseif target.loc ~= nil then
            squares = {target.loc}
        end
        for _,loc in ipairs(squares) do
            if includeAdjacent then
                for dy = -1,1 do
                    for dx = -1,1 do
                        Add(loc:dir(dx, dy))
                    end
                end
            else
                Add(loc)
            end
        end
    end
    return result
end

--The squares of the cast's area (or areas: one cast can cover several, see
--targetAreaList), as engine Locs. Empty for an ability with no area. The
--engine builds the shape on the caster's floor, so an object caster works too.
--- @param options table
--- @return Loc[]
local function AreaSquares(options)
    local areas = options.targetAreaList
    if areas == nil and options.targetArea ~= nil then
        areas = {options.targetArea}
    end

    local result = {}
    local seen = {}
    for _,area in ipairs(areas or {}) do
        for _,loc in ipairs(area.locations or {}) do
            local key = string.format("%d,%d,%d", loc.x, loc.y, loc.floor or 0)
            if seen[key] == nil then
                seen[key] = true
                result[#result+1] = loc
            end
        end
    end
    return result
end

--The floor object storing the given zone record, or nil.
local function FindZoneFloor(zoneid)
    local map = game.currentMap
    if map == nil then
        return nil
    end
    for _,floor in ipairs(map.floors) do
        local zones = floor.markupZones
        if zones ~= nil and zones[zoneid] ~= nil then
            return floor
        end
    end
    return nil
end

--- Transforms every zone of fromKeyword covering any of the squares. Returns
--- the number of zones transformed.
--- @param squares Loc[]
--- @return number
function ActivatedAbilityTransformZoneBehavior:TransformZonesAt(squares)
    local fromKeyword = self.fromKeyword
    if fromKeyword == nil or fromKeyword == "" then
        return 0
    end

    --collect the zone ids first: the squares can share a zone.
    local zoneids = {}
    local orderedZoneids = {}
    for _,loc in ipairs(squares) do
        for _,instance in ipairs(EnvironmentalKeyword.AuraInstancesCoveringSquare(loc)) do
            local auraDef = instance:try_get("aura")
            if auraDef ~= nil and auraDef:try_get("environmentalKeywordId") == fromKeyword then
                local zoneid = instance.guid
                if zoneid ~= nil and zoneids[zoneid] == nil then
                    zoneids[zoneid] = true
                    orderedZoneids[#orderedZoneids+1] = zoneid
                end
            end
        end
    end

    if #orderedZoneids == 0 then
        return 0
    end

    return ActivatedAbilityTransformZoneBehavior.RewriteZoneRecords(orderedZoneids, fromKeyword, self.toKeyword, self.reveal)
end

--- Rewrites the given zone records (ids into the current map's
--- floor.markupZones) from fromKeyword into toKeyword, or removes them when
--- toKeyword is "none". A record whose stored keyword is no longer fromKeyword
--- is skipped, so a second request for an already-converted zone does nothing.
--- Shared by the Transform Zone behavior and the end-of-round zone spread
--- (EnvironmentalKeyword.SpreadZonesAtEndOfRound). Returns the number of
--- records changed.
--- @param zoneids string[]
--- @param fromKeyword string
--- @param toKeyword string
--- @param reveal boolean When true, a rewritten zone becomes visible to players.
--- @return number
function ActivatedAbilityTransformZoneBehavior.RewriteZoneRecords(zoneids, fromKeyword, toKeyword, reveal)
    local newKeyword = nil
    if toKeyword ~= "none" then
        newKeyword = (dmhub.GetTable(EnvironmentalKeyword.tableName) or {})[toKeyword]
        if newKeyword == nil then
            return 0
        end
    end
    local oldName = KeywordName(fromKeyword)

    local count = 0

    --zone records are map data. On a player host the triggering client may not
    --otherwise hold the right to rewrite them.
    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for _,zoneid in ipairs(zoneids) do
            local floor = FindZoneFloor(zoneid)
            if floor ~= nil then
                local stored = floor.markupZones[zoneid]
                if stored ~= nil and stored.keyword == fromKeyword then
                    if newKeyword == nil then
                        floor:RemoveMarkupZone(zoneid)
                    else
                        --build a fresh copy: the getter returns the stored table,
                        --and editing it in place corrupts undo.
                        local record = DeepCopy(stored)
                        record.keyword = toKeyword
                        record.keywordName = newKeyword.name
                        if record.name == nil or record.name == "" or (oldName ~= nil and string.find(record.name, oldName, 1, true) == 1) then
                            record.name = newKeyword.name
                        end
                        record.pattern = record.pattern or {}
                        record.pattern.color = MapMarkupImpl.KeywordColor(toKeyword, newKeyword)
                        if reveal then
                            record.playerVisible = true
                        end
                        if newKeyword:try_get("appearanceDefaultOff", false) == true then
                            record.hideAppearance = true
                        else
                            record.hideAppearance = nil
                        end
                        floor:SetMarkupZone(zoneid, record)
                    end
                    count = count + 1
                end
            end
        end
    end)
    DropHostPermissions()

    if not ok then
        dmhub.CloudError("Transform Zone failed: " .. tostring(err))
    end

    return count
end

function ActivatedAbilityTransformZoneBehavior:Cast(ability, casterToken, targets, options)
    local squares
    if self.location == "area" then
        squares = AreaSquares(options)
    else
        squares = TargetSquares(targets, self.location == "adjacent")
    end
    local count = self:TransformZonesAt(squares)

    if count == 0 then
        if self.abortIfNone then
            options.stopProcessing = true
        end
        return
    end

    ability:CommitToPaying(casterToken, options)
end

function ActivatedAbilityTransformZoneBehavior:EditorItems(parentPanel)
    local result = {}

    local keywordOptions = {}
    EnvironmentalKeyword.FillDropdownOptions(keywordOptions)

    local toOptions = { { id = "none", text = "(Remove the zone)" } }
    for _,option in ipairs(keywordOptions) do
        toOptions[#toOptions+1] = option
    end

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Zone Type:",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = keywordOptions,
            idChosen = self.fromKeyword,
            textDefault = "Choose zone type...",
            hasSearch = true,
            change = function(element)
                ---@cast element Dropdown
                self.fromKeyword = element.idChosen --[[@as string]]
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Becomes:",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = toOptions,
            idChosen = self.toKeyword,
            hasSearch = true,
            change = function(element)
                ---@cast element Dropdown
                self.toKeyword = element.idChosen --[[@as string]]
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Squares:",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = {
                { id = "targets", text = "Targets' squares" },
                { id = "adjacent", text = "Targets' squares and adjacent" },
                { id = "area", text = "Ability Area" },
            },
            idChosen = self.location,
            change = function(element)
                ---@cast element Dropdown
                self.location = element.idChosen --[[@as string]]
            end,
        },
    }

    result[#result+1] = gui.Check{
        text = "Reveal to players",
        value = self.reveal,
        change = function(element)
            self.reveal = element.value
        end,
    }

    result[#result+1] = gui.Check{
        text = "Stop the ability if no zone changed",
        value = self.abortIfNone,
        change = function(element)
            self.abortIfNone = element.value
        end,
    }

    return result
end
