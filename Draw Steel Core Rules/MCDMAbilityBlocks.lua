local mod = dmhub.GetModLoading()

--[[
    The ability host for the Block Editor (the "Simple" ability editor): how an
    ActivatedAbility opens as a page of blocks and saves back. Declared beside
    the ability rules, as the plan asks (BLOCK_EDITOR_IMPLEMENTATION_PLAN.md
    section 2): the editor UI reads this and knows nothing about abilities.

    Each header slot has a field codec (read, write, touches). A writer leaves
    the record alone when the value equals the one opened, so the saved
    spelling (a number stored as a string, "none" versus nothing) survives.
    Steps no block reads yet open as Advanced blocks and save back untouched.
]]

--The Draw Steel characteristics as Block stats, read from the game's own
--attribute list when the editor gathers its registries (they replace the stubs).
Block.RegisterSource{
    id = "ds.characteristics",
    kind = "stat",
    gather = function()
        local result = {}
        for i, attrid in ipairs(creature.attributeIds or {}) do
            local info = (creature.attributesInfo or {})[attrid]
            if info ~= nil then
                result[#result + 1] = { id = attrid, words = info.description, kind = "characteristic", order = i * 10 }
            end
        end
        return result
    end,
}

--- The resources of a grouping, as slot options, by name.
--- @param keep fun(resource: table): boolean
--- @param none {id: string, text: string}
--- @return {id: string, text: string}[]
local function _resourceOptions(keep, none)
    local result = {}
    for id, resource in unhidden_pairs(dmhub.GetTable("characterResources") or {}) do
        local ok, kept = pcall(keep, resource)
        if ok and kept then
            result[#result + 1] = { id = id, text = tostring(resource.name) }
        end
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    table.insert(result, 1, none)
    return result
end

--- The grouping a resource is filed under ("Actions", "Hidden", ...).
--- @param resource table
--- @return string|nil
local function _grouping(resource)
    local grouping = nil
    pcall(function() grouping = rawget(resource, "grouping") end)
    return grouping
end

--- Sets a field unless the value equals the one opened, keeping the saved form
--- when only its type differs (a range saved as the string "10").
--- @param record table
--- @param fieldName string
--- @param value any
--- @param original any
local function _set(record, fieldName, value, original)
    if value == original then
        return
    end
    local saved = rawget(record, fieldName)
    if saved ~= nil and value ~= nil and tostring(saved) == tostring(value) then
        return
    end
    --nothing saved and the value is the type's default: leave it unsaved.
    if saved == nil and value == Block.FieldValue(record, fieldName) then
        return
    end
    if type(saved) == "number" and tonumber(value) ~= nil then
        value = tonumber(value)
    end
    record[fieldName] = value
end

--- A field codec that reads and writes one record field as it is.
--- @param fieldName string
--- @param default any what the field reads as when neither the record nor its type has a value
--- @return BlockField
local function _plainField(fieldName, default)
    return {
        touches = { fieldName },
        read = function(record)
            local value = Block.FieldValue(record, fieldName)
            if value == nil then
                return default
            end
            return value
        end,
        write = function(record, value, original)
            _set(record, fieldName, value, original)
        end,
    }
end

--- The distance kinds and how each reads from the targeting fields.
local DISTANCES = {
    { id = "self", text = "Self" },
    { id = "melee", text = "Melee" },
    { id = "ranged", text = "Ranged" },
    { id = "burst", text = "Burst" },
    { id = "cube", text = "Cube" },
    { id = "line", text = "Line" },
    { id = "space", text = "A space" },
    { id = "map", text = "Anywhere on the map" },
}

--the range a melee ability gets when it is made ranged (the most common in the book).
local RANGED_DEFAULT = 10

local TARGET_TYPE_FOR = {
    self = "self", melee = "target", ranged = "target", burst = "all",
    cube = "cube", line = "line", space = "emptyspace", map = "map",
}

--- @param record table
--- @return string
local function _readDistance(record)
    local targetType = Block.FieldValue(record, "targetType") or "self"
    if targetType == "target" then
        return tonumber(Block.FieldValue(record, "range")) == 1 and "melee" or "ranged"
    elseif targetType == "all" then
        return "burst"
    elseif targetType == "emptyspace" or targetType == "anyspace" or targetType == "emptyspacefriend" then
        return "space"
    elseif TARGET_TYPE_FOR[targetType] ~= nil then
        return targetType
    end
    return "self"
end

local TARGETS = {
    { id = "creature", text = "creature" },
    { id = "enemy", text = "enemy" },
    { id = "ally", text = "ally" },
}

--- The header slots, shared by the rows and the card.
local SLOTS = {
    name = { kind = "text", default = "" },
    category = {
        kind = "choice",
        default = "Ability",
        options = {
            { id = "Signature Ability", text = "signature ability" },
            { id = "Heroic Ability", text = "heroic ability" },
            { id = "Ability", text = "ability" },
            { id = "Trigger", text = "triggered ability" },
            { id = "Basic Attack", text = "basic attack" },
            { id = "Move", text = "move" },
            { id = "Skill", text = "skill" },
            { id = "Common Ability", text = "common ability" },
        },
    },
    action = {
        kind = "choice",
        default = "none",
        options = function()
            return _resourceOptions(function(resource) return _grouping(resource) == "Actions" end, { id = "none", text = "no action" })
        end,
    },
    cost = { kind = "number", default = 0 },
    resource = {
        kind = "choice",
        default = "none",
        options = function()
            return _resourceOptions(function(resource)
                local grouping = _grouping(resource)
                return grouping ~= "Actions" and grouping ~= "Hidden"
            end, { id = "none", text = "nothing" })
        end,
    },
    keywords = {
        kind = "many",
        default = {},
        options = function()
            local result = {}
            for keyword, _ in pairs(GameSystem.abilityKeywords or {}) do
                result[#result + 1] = { id = keyword, text = keyword }
            end
            table.sort(result, function(a, b) return a.text < b.text end)
            return result
        end,
    },
    flavor = { kind = "text", default = "" },
    distance = { kind = "choice", default = "self", options = DISTANCES },
    range = { kind = "formula", style = "formula", default = 1, options = {} },
    count = { kind = "formula", style = "formula", default = 1, options = {} },
    target = { kind = "choice", default = "creature", options = TARGETS },
    targetsAre = {
        kind = "choice",
        default = "together",
        options = {
            { id = "together", text = "all picked together" },
            { id = "sequential", text = "picked one at a time, moving between them" },
        },
    },
    limit = {
        kind = "choice",
        default = "none",
        --the game's own periods (Draw Steel registers them in MCDMRules.lua).
        options = function()
            local result = {}
            for _, option in ipairs(CharacterResource.usageLimitOptions or {}) do
                local text = option.id == "none" and "none" or string.lower(option.text or option.id)
                result[#result + 1] = { id = option.id, text = text }
            end
            return result
        end,
    },
    charges = { kind = "formula", style = "formula", default = "1", options = {} },
    filter = { kind = "testFormula", style = "formula", default = "", empty = "+ test" },
}

--- The record's own fields, by the header slot that shows them.
--- @type table<string, BlockField>
local FIELDS = {
    name = _plainField("name", ""),
    category = _plainField("categorization", "Ability"),
    action = _plainField("actionResourceId", "none"),
    cost = _plainField("resourceNumber", 0),
    resource = _plainField("resourceCost", "none"),
    flavor = _plainField("flavor", ""),
    effect = _plainField("description", ""),
    range = _plainField("range", 1),
    count = _plainField("numTargets", 1),
    keywords = {
        touches = { "keywords" },
        read = function(record)
            local result = {}
            for keyword, on in pairs(rawget(record, "keywords") or {}) do
                if on then
                    result[#result + 1] = keyword
                end
            end
            table.sort(result)
            return result
        end,
        write = function(record, value, original)
            if type(original) == "table" and dmhub.DeepEqual(value or {}, original) then
                return
            end
            local map = {}
            for _, keyword in ipairs(value or {}) do
                map[keyword] = true
            end
            record.keywords = map
        end,
    },
    distance = {
        --melee and ranged differ only by range (1 is melee), so the range slot
        --is changed with the distance and saved by its own writer.
        touches = { "targetType" },
        read = _readDistance,
        write = function(record, value, original)
            if value == original then
                return
            end
            local targetType = TARGET_TYPE_FOR[value] or "self"
            if Block.FieldValue(record, "targetType") ~= targetType then
                record.targetType = targetType
            end
        end,
        changed = function(values, previous)
            local range = tonumber(values.range)
            if values.distance == "melee" then
                values.range = 1
            elseif values.distance == "ranged" and (range == nil or range <= 1) then
                values.range = RANGED_DEFAULT
            end
        end,
    },
    target = {
        touches = { "targetAllegiance" },
        read = function(record)
            local allegiance = Block.FieldValue(record, "targetAllegiance")
            if allegiance == "ally" or allegiance == "enemy" then
                return allegiance
            end
            return "creature"
        end,
        write = function(record, value, original)
            if value == original then
                return
            end
            local saved = Block.FieldValue(record, "targetAllegiance")
            if value == "creature" then
                --any creature: keep whatever "no side" form is saved (false, nil, ...).
                if saved == "ally" or saved == "enemy" then
                    record.targetAllegiance = nil
                end
            elseif saved ~= value then
                record.targetAllegiance = value
            end
        end,
    },
}

--- The ability's usage limit as saved, or the type's default ("none").
--- @param record table
--- @return table
local function _limitOptions(record)
    local options = Block.FieldValue(record, "usageLimitOptions")
    if type(options) ~= "table" then
        --some imports saved a string here; the game treats it as no limit.
        return { resourceRefreshType = "none", charges = "0", resourceid = "none" }
    end
    return options
end

--- Writes one part of the usage limit, keeping the rest as saved. A new limit
--- gets its own counter (the ability's guid) unless it already shares one.
--- @param record table
--- @param key string "resourceRefreshType" or "charges"
--- @param value any
local function _writeLimit(record, key, value)
    local saved = rawget(record, "usageLimitOptions")
    local options = type(saved) == "table" and DeepCopy(saved) or DeepCopy(_limitOptions(record))
    options[key] = value
    if options.resourceRefreshType ~= "none" then
        if options.charges == nil or tostring(options.charges) == "0" then
            options.charges = "1"
        end
        if options.resourceid == nil or options.resourceid == "none" then
            options.resourceid = rawget(record, "guid") or dmhub.GenerateGuid()
        end
    end
    record.usageLimitOptions = options
end

--what a filter saved as a table of formulas reads as: shown, never written (the slot locks).
local TABLE_FILTER = "(a formula table: edit it in the Advanced editor)"

FIELDS.filter = {
    touches = { "targetFilter" },
    read = function(record)
        local filter = Block.FieldValue(record, "targetFilter")
        if type(filter) == "table" then
            return TABLE_FILTER
        end
        return filter ~= nil and tostring(filter) or ""
    end,
    write = function(record, value, original)
        if type(rawget(record, "targetFilter")) == "table" then
            error("a target filter saved as a table cannot be written as text")
        end
        if value == original then
            return
        end
        local saved = tostring(Block.FieldValue(record, "targetFilter") or "")
        value = tostring(value or "")
        --a test that means the same keeps its saved spelling ("enemy", "Enemy").
        if Block.SameFormula(saved, value) then
            return
        end
        record.targetFilter = value
    end,
}

FIELDS.targetsAre = {
    touches = { "sequentialTargeting" },
    read = function(record)
        return Block.FieldValue(record, "sequentialTargeting") == true and "sequential" or "together"
    end,
    write = function(record, value)
        if value == "sequential" then
            record.sequentialTargeting = true
        else
            --"together" is the game's default: leave it unsaved.
            record.sequentialTargeting = nil
        end
    end,
}

FIELDS.limit = {
    touches = { "usageLimitOptions" },
    read = function(record)
        local refresh = tostring(_limitOptions(record).resourceRefreshType or "none")
        --"victory:3" (after 3 Victories) is the victory period with a count.
        return (string.match(refresh, "^([^:]+)")) or "none"
    end,
    write = function(record, value)
        _writeLimit(record, "resourceRefreshType", value)
    end,
    changed = function(values, previous)
        --a new limit starts at one use, as the Advanced editor's does.
        if values.limit ~= "none" and (values.charges == nil or tostring(values.charges) == "0") then
            values.charges = "1"
        elseif values.limit == "none" then
            --no limit, no use count: an ability that never had a limit saves without one.
            values.charges = "0"
        end
    end,
}

FIELDS.charges = {
    touches = { "usageLimitOptions" },
    read = function(record)
        local charges = _limitOptions(record).charges
        return charges ~= nil and tostring(charges) or "0"
    end,
    write = function(record, value)
        _writeLimit(record, "charges", tostring(value))
    end,
}

--- The text of a header value, as its row shows it.
--- @param model table
--- @param slotId string
--- @return string
local function _text(model, slotId)
    local value = (model.values or {})[slotId]
    return Block.SlotText({ id = "ability", family = "header", group = "header", label = "", sentence = {}, slots = SLOTS }, slotId, value)
end

local NUMBER_WORDS = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten" }
local TARGET_PLURALS = { creature = "creatures", enemy = "enemies", ally = "allies" }
--the distances whose targets are everyone in an area ("Each enemy in the area").
local AREA_DISTANCES = { burst = true, cube = true, line = true }

--- Whether the author changed any of these header slots since the record opened.
--- @param model table
--- @param slotIds string[]
--- @return boolean
local function _slotsChanged(model, slotIds)
    local values, opened = model.values or {}, model.openValues or {}
    for _, slotId in ipairs(slotIds) do
        if Block.ValueSignature(values[slotId]) ~= Block.ValueSignature(opened[slotId]) then
            return true
        end
    end
    return false
end

--- The card's distance as the book prints it: the saved wording while the
--- distance is as opened (design 4p: saved book wording wins), otherwise
--- "Self", "Melee 1", "Ranged 10", "3 burst".
--- @param model table
--- @param record table|nil
--- @return string
local function _cardDistance(model, record)
    local saved = record ~= nil and rawget(record, "rangeTextOverride") or nil
    if type(saved) == "string" and string.find(saved, "%S") ~= nil and not _slotsChanged(model, { "distance", "range" }) then
        return saved
    end
    local values = model.values or {}
    local distance = values.distance
    local range = tostring(values.range or "")
    if distance == "self" then
        return "Self"
    elseif distance == "map" then
        return "Anywhere on the map"
    elseif AREA_DISTANCES[distance] then
        return string.format("%s %s", range, distance)
    end
    return string.format("%s %s", _text(model, "distance"), range)
end

--- The card's target as the book prints it: the saved wording while the
--- targeting is as opened, otherwise "One creature", "Three enemies", "Each
--- enemy in the area".
--- @param model table
--- @param record table|nil
--- @return string
local function _cardTarget(model, record)
    local saved = record ~= nil and rawget(record, "targetTextOverride") or nil
    if type(saved) == "string" and string.find(saved, "%S") ~= nil and not _slotsChanged(model, { "distance", "count", "target" }) then
        return saved
    end
    local values = model.values or {}
    local target = tostring(values.target or "creature")
    if values.distance == "self" then
        return "Self"
    elseif AREA_DISTANCES[values.distance] then
        return string.format("Each %s in the area", target)
    end
    local count = tonumber(values.count)
    if count == nil then
        --a formula count reads as written.
        return string.format("%s %s", tostring(values.count), TARGET_PLURALS[target] or target)
    end
    local word = NUMBER_WORDS[count] or tostring(count)
    return string.format("%s %s", word, count == 1 and target or (TARGET_PLURALS[target] or target))
end

--- The first placed block of a kind in a list or anywhere inside it, or nil.
--- @param list BlockInstance[]|nil
--- @param blockId string
--- @return BlockInstance|nil
local function _findBlock(list, blockId)
    for _, instance in ipairs(list or {}) do
        if instance.block == blockId then
            return instance
        end
        for _, body in pairs(instance.bodies or {}) do
            local found = _findBlock(body, blockId)
            if found ~= nil then
                return found
            end
        end
    end
    return nil
end

--- How many placed blocks of a kind a list holds, inside other blocks too.
--- @param list BlockInstance[]|nil
--- @param blockId string
--- @return integer
local function _countBlocks(list, blockId)
    local count = 0
    for _, instance in ipairs(list or {}) do
        if instance.block == blockId then
            count = count + 1
        end
        for _, body in pairs(instance.bodies or {}) do
            count = count + _countBlocks(body, blockId)
        end
    end
    return count
end

--- A tier's text as card parts, with a lone characteristic letter as a chip.
--- @param text string
--- @return (string|{chip: string})[]
local function _tierParts(text)
    local parts = {}
    local position = 1
    while true do
        --a potency ("M < weak") is boxed whole, as the book prints it; a lone letter is a chip.
        local pFirst, pLast, pLetter, pWord = string.find(text, "%f[%w]([MARIP])%s*<%s*(%a+)", position)
        local first, last, letter = string.find(text, "%f[%w]([MARIP])%f[%W]", position)
        if first == nil and pFirst == nil then
            break
        end
        if pFirst ~= nil and (first == nil or pFirst <= first) then
            if pFirst > position then
                parts[#parts + 1] = string.sub(text, position, pFirst - 1)
            end
            parts[#parts + 1] = { box = pLetter .. "<" .. string.upper(pWord) }
            position = pLast + 1
        else
            if first > position then
                parts[#parts + 1] = string.sub(text, position, first - 1)
            end
            parts[#parts + 1] = { chip = letter }
            position = last + 1
        end
    end
    if position <= #text then
        parts[#parts + 1] = string.sub(text, position)
    end
    return parts
end

--- The effect text as the book prints it: a paragraph per line, a leading
--- "Label:" (or "**Label:**") as its bold label, "**bold**" as bold, and
--- "Effect:" on the first paragraph that has no label of its own.
--- @param text string
--- @return {label?: string, text: string}[]
local function _effectParagraphs(text)
    local result = {}
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        line = string.gsub(line, "^%s+", "")
        line = string.gsub(line, "%s+$", "")
        if line ~= "" then
            local label, rest = string.match(line, "^%*%*([^*]-:)%*%*%s*(.*)$")
            if label == nil then
                --a short plain "Label:" at the start ("Strained:", "Spend 1 Ferocity:").
                label, rest = string.match(line, "^([%a][%w '%-]-:)%s+(.*)$")
                if label ~= nil and #label > 30 then
                    label, rest = nil, nil
                end
            end
            rest = rest or line
            rest = string.gsub(rest, "%*%*(.-)%*%*", "<b>%1</b>")
            result[#result + 1] = { label = label, text = rest }
        end
    end
    if result[1] ~= nil and result[1].label == nil then
        result[1].label = "Effect:"
    end
    return result
end

----------------------------------------------------------------------------
-- Wrappers: fields every behaviour has that limit when it runs, shown as a
-- block holding the steps they limit (BlockWrapper in DMHub Utils/Block.lua).
-- Outer first: a mode, then Strained, then a tier, then an "Only if" test.
----------------------------------------------------------------------------

--- A list of numbers as a key ("2,3"), or nil for none.
--- @param list any
--- @return string|nil
local function _listKey(list)
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    local parts = {}
    for i, item in ipairs(list) do
        parts[i] = tostring(item)
    end
    return table.concat(parts, ",")
end

--- A key back to its list of numbers.
--- @param key string|nil
--- @return number[]|nil
local function _keyList(key)
    if key == nil then
        return nil
    end
    local list = {}
    for item in string.gmatch(key, "[^,]+") do
        list[#list + 1] = tonumber(item) or item
    end
    return list
end

--- The names of an ability's modes for a key ("Spend 1 Ferocity").
--- @param key string
--- @param record table
--- @return string
local function _modeNames(key, record)
    local modeList = record ~= nil and rawget(record, "modeList") or nil
    local names = {}
    for _, number in ipairs(_keyList(key) or {}) do
        local mode = type(modeList) == "table" and modeList[number] or nil
        local text = mode ~= nil and rawget(mode, "text") or nil
        if number == -1 then
            --the Advanced editor's "Disabled": in no mode at all.
            text = "no mode (turned off)"
        end
        names[#names + 1] = type(text) == "string" and text or ("mode " .. tostring(number))
    end
    return table.concat(names, " or ")
end

Block.RegisterBlock{
    id = "ability.mode",
    family = "logic",
    group = "logic",
    label = "Only in a mode",
    desc = "The steps inside only happen when the ability is used in this mode.",
    sentence = { { text = "Only when used as", bold = true }, " ", { slot = "mode" }, ":" },
    slots = { mode = { kind = "fixed", default = "" } },
    bodies = { { id = "steps", fits = "step" } },
    fits = { "step" },
    shelf = false,
}

--- A mode key after Choose one when used renumbered its options. remap maps an
--- old mode number to its new one, -1 (taken out: the game's "no mode") or
--- false (modes were off: the tag is stale and goes).
--- @param key string "2" or "1,3"
--- @param remap table<integer, integer|false>
--- @return string|nil
local function _remapModes(key, remap)
    local numbers = {}
    for _, number in ipairs(_keyList(key) or {}) do
        local moved = remap[number]
        if moved == nil then
            moved = number
        end
        --a taken-out mode becomes -1 ("no mode") only when nothing else is left.
        if moved ~= false and (moved ~= -1 or #numbers == 0) then
            numbers[#numbers + 1] = moved
        end
    end
    if #numbers > 1 and numbers[1] == -1 then
        table.remove(numbers, 1)
    end
    return _listKey(numbers)
end

Block.RegisterWrapper{
    id = "ability.mode",
    order = 10,
    block = "ability.mode",
    key = function(behavior, ctx)
        --the game only reads a step's modes on an ability that has modes
        --(ActivatedAbilityBehavior:SkippedInMode), so elsewhere they are left as saved.
        local record = ctx ~= nil and ctx.record or nil
        if record == nil or not Block.FieldValue(record, "multipleModes") then
            return nil
        end
        return _listKey(rawget(behavior, "modesSelected"))
    end,
    values = function(key, ctx)
        return { modes = key, mode = _modeNames(key, ctx.record) }
    end,
    keyOf = function(values, ctx)
        --options renumbered or taken out in Choose one when used: follow them.
        local remap = ctx ~= nil and ctx.remap ~= nil and ctx.remap["ability.mode"] or nil
        if remap == nil or values.modes == nil then
            return values.modes
        end
        return _remapModes(values.modes, remap)
    end,
    apply = function(behavior, key)
        behavior.modesSelected = _keyList(key)
    end,
    --a step no block reads (an Advanced block) is never wrapped, but its modes still follow.
    rekey = function(behavior, ctx)
        local remap = ctx ~= nil and ctx.remap ~= nil and ctx.remap["ability.mode"] or nil
        local key = _listKey(rawget(behavior, "modesSelected"))
        if remap == nil or key == nil then
            return false
        end
        local moved = _remapModes(key, remap)
        if moved == key then
            return false
        end
        behavior.modesSelected = _keyList(moved)
        return true
    end,
}

----------------------------------------------------------------------------
-- Choose one when used (ability design 4n): options picked when the ability
-- is used, each with its own steps. Saved as the game's modes: multipleModes,
-- modeList, and modesSelected on each step of an option. An option with a
-- "Targets differently" block saves as an Ability Variation instead: a whole
-- ability with that targeting and the option's steps (multipleModes = "variations").
----------------------------------------------------------------------------

--the condition a mode with an extra cost gets, as Banshee Howl's "Spend 1 Ferocity".
local EXTRA_COST_CONDITION = "Heroic Resources Available to Spend >= %d"

--- The extra cost a mode's condition asks for (0 for none), and the rest of
--- the condition ("" for none): a cost is the whole condition, or joined to the
--- end of another with "and".
--- @param condition any
--- @return integer cost, string rest
local function _extraCost(condition)
    if type(condition) ~= "string" then
        return 0, ""
    end
    local amount = string.match(condition, "^%s*Heroic Resources Available to Spend%s*>=%s*(%d+)%s*$")
    if amount ~= nil then
        return tonumber(amount) or 0, ""
    end
    local rest, joined = string.match(condition, "^(.-)%s+and%s+Heroic Resources Available to Spend%s*>=%s*(%d+)%s*$")
    if joined ~= nil then
        return tonumber(joined) or 0, rest
    end
    return 0, condition
end

--- A mode's condition for a cost, keeping the rest of what it asked.
--- @param rest string the condition without its cost
--- @param cost integer
--- @return string|nil
local function _costCondition(rest, cost)
    local costText = cost > 0 and string.format(EXTRA_COST_CONDITION, cost) or nil
    if string.find(rest, "%S") == nil then
        return costText
    end
    if costText == nil then
        return rest
    end
    --a rest that uses "or" is bracketed, so the cost applies to all of it.
    if string.find(rest, "%f[%w]or%f[%W]") ~= nil and not string.match(rest, "^%(.*%)$") then
        rest = "(" .. rest .. ")"
    end
    return rest .. " and " .. costText
end

local EXTRA_COSTS = { { id = "0", text = "no extra cost" } }
for amount = 1, 5 do
    EXTRA_COSTS[#EXTRA_COSTS + 1] = { id = tostring(amount), text = string.format("costs %d more", amount) }
end

--the targeting slots of an option that targets differently, read and written as the header's.
local TARGETING_SLOTS = { "distance", "range", "count", "target" }

--- Whether a placed step spends the Heroic Resource (an extra cost's own step).
--- @param instance BlockInstance
--- @return boolean
local function _isCostStep(instance)
    local values = instance.values or {}
    return instance.block == "ability.resource" and values.mode == "expend" and values.resource == CharacterResource.heroicResourceId
end

Block.RegisterBlock{
    id = "ability.choose",
    family = "logic",
    group = "logic",
    label = "Choose one when used",
    desc = "Options picked when the ability is used: each option has its own steps, and steps outside this block happen with every option.",
    sentence = { { text = "When you use it, choose one", bold = true }, " ", { slot = "timing" }, ":" },
    slots = {
        timing = {
            kind = "choice",
            default = "before",
            options = {
                { id = "before", text = "before picking targets" },
                { id = "after", text = "after picking the target" },
            },
        },
    },
    bodies = { { id = "options", fits = "option" } },
    fits = { "step" },
    order = 70,
    initial = function(instance)
        for _ = 1, 2 do
            instance.bodies.options[#instance.bodies.options + 1] = Block.Instantiate("ability.option")
        end
    end,
    split = {
        body = "options",
        steps = "steps",
        wrapper = "ability.mode",
        gather = function(list, behaviors, ctx)
            local record = ctx.record
            local modeList = record ~= nil and rawget(record, "modeList") or nil
            if record == nil or not Block.FieldValue(record, "multipleModes") or type(modeList) ~= "table" or #modeList == 0 then
                return list
            end
            local options = {}
            for index, mode in ipairs(modeList) do
                local option = Block.Instantiate("ability.option") --[[@as BlockInstance]]
                option.values.name = tostring(rawget(mode, "text") or "")
                option.values.cost = tostring((_extraCost(rawget(mode, "condition"))))
                option.values.rules = tostring(rawget(mode, "rules") or "")
                option.values.number = index
                option.saved = DeepCopy(mode)
                local variation = rawget(mode, "variation")
                if rawget(mode, "hasAbility") and type(variation) == "table" then
                    local targets = Block.Instantiate("ability.optiontargets") --[[@as BlockInstance]]
                    for _, slotId in ipairs(TARGETING_SLOTS) do
                        targets.values[slotId] = FIELDS[slotId].read(variation)
                    end
                    option.bodies.targets = { targets }
                    option.bodies.steps = ctx.OpenSteps(rawget(variation, "behaviors"), variation)
                end
                options[index] = option
            end
            --the first run of single-mode wrappers moves into its options; a step
            --in every mode (or several) ends the run, as moving past it could change
            --what runs first. Steps of an option that targets differently never run
            --with it (the game swaps in the variation), so they stay where they are.
            local result = {}
            local placed = false
            local chooser = Block.Instantiate("ability.choose") --[[@as BlockInstance]]
            chooser.values.timing = Block.FieldValue(record, "chooseModeAfterTargeting") == true and "after" or "before"
            chooser.bodies.options = options
            local running = true
            --- @type table<table, boolean> options whose cost step is already found
            local costMatched = {}
            for _, instance in ipairs(list) do
                local number = instance.block == "ability.mode" and tonumber((instance.values or {}).modes) or nil
                --- @type BlockInstance|nil
                local option = number ~= nil and options[number] or nil
                --- @type BlockInstance[]|nil
                local optionSteps = nil
                if option ~= nil and option.bodies ~= nil and #(option.bodies.targets or {}) == 0 and tostring(number) == instance.values.modes then
                    optionSteps = option.bodies.steps
                end
                local fits = optionSteps ~= nil
                if running and fits and optionSteps ~= nil and option ~= nil then
                    for _, step in ipairs((instance.bodies or {}).steps or {}) do
                        optionSteps[#optionSteps + 1] = step
                        --the Spend step that pays this option's cost is the one a new cost changes.
                        if not costMatched[option] and _isCostStep(step) and tostring((step.values or {}).quantity) == option.values.cost then
                            step.marks = step.marks or {}
                            step.marks.costStep = true
                            costMatched[option] = true
                        end
                    end
                    if not placed then
                        result[#result + 1] = chooser
                        placed = true
                    end
                else
                    if placed and instance.block ~= "ability.mode" then
                        running = false
                    elseif placed and number == nil then
                        running = false
                    end
                    result[#result + 1] = instance
                end
            end
            if not placed then
                table.insert(result, 1, chooser)
            end
            return result
        end,
        prepare = function(instance, ctx)
            --options keep the mode number they were opened with; one moved or taken out
            --renumbers the steps still outside the block (-1: the game's "no mode").
            local remap = {}
            local moved = false
            for index, option in ipairs((instance.bodies or {}).options or {}) do
                local number = (option.values or {}).number
                if number ~= nil then
                    remap[number] = index
                    moved = moved or number ~= index
                end
            end
            local modeList = ctx.record ~= nil and rawget(ctx.record, "modeList") or nil
            --modes were off (the block was taken out earlier): old tags are stale, and
            --must not come back to life on the new options.
            local modesOn = ctx.record ~= nil and Block.FieldValue(ctx.record, "multipleModes")
            for number = 1, type(modeList) == "table" and #modeList or 0 do
                if not modesOn then
                    remap[number] = false
                    moved = true
                elseif remap[number] == nil then
                    remap[number] = -1
                    moved = true
                end
            end
            if moved then
                ctx.remap = ctx.remap or {}
                ctx.remap["ability.mode"] = remap
            end
        end,
        key = function(option, index)
            --an option that targets differently saves its steps in its variation (saveRecord).
            if #((option.bodies or {}).targets or {}) > 0 then
                return false
            end
            return tostring(index)
        end,
        saveRecord = function(instance, ctx)
            local result = ctx.result
            if result == nil then
                return
            end
            if instance == nil then
                --the block was taken out: the ability no longer offers a choice.
                local savedList = rawget(ctx.record, "modeList")
                if Block.FieldValue(ctx.record, "multipleModes") and type(savedList) == "table" and #savedList > 0 then
                    result.multipleModes = false
                end
                return
            end
            if not ctx.forced and Block.InstanceUnchanged(instance) then
                return
            end
            local modeList = {}
            local anyVariation = false
            local newVariation = false
            for index, option in ipairs((instance.bodies or {}).options or {}) do
                local values = option.values or {}
                local entry = DeepCopy(option.saved or {})
                local name = tostring(values.name or "")
                if tostring(rawget(entry, "text") or "") ~= name then
                    entry.text = name
                end
                local rules = tostring(values.rules or "")
                if tostring(rawget(entry, "rules") or "") ~= rules then
                    entry.rules = rules ~= "" and rules or nil
                end
                local cost = tonumber(values.cost) or 0
                local savedCost, rest = _extraCost(rawget(entry, "condition"))
                if savedCost ~= cost then
                    entry.condition = _costCondition(rest, cost)
                end
                local targets = ((option.bodies or {}).targets or {})[1]
                if targets ~= nil then
                    anyVariation = true
                    newVariation = newVariation or not rawget(entry, "hasAbility")
                    local variation = rawget(entry, "variation")
                    if type(variation) ~= "table" then
                        variation = ActivatedAbility.Create{
                            name = rawget(result, "name"),
                            categorization = rawget(result, "categorization"),
                            iconid = rawget(result, "iconid"),
                            description = rules,
                            domains = DeepCopy(rawget(result, "domains")),
                        }
                        --"none" keeps the base ability's cost when the game swaps this in.
                        variation.resourceCost = "none"
                    end
                    for _, slotId in ipairs(TARGETING_SLOTS) do
                        local value = targets.values[slotId]
                        if Block.ValueSignature(FIELDS[slotId].read(variation)) ~= Block.ValueSignature(value) then
                            FIELDS[slotId].write(variation, value, nil)
                        end
                    end
                    local steps, untouched = ctx.SaveSteps((option.bodies or {}).steps or {}, rawget(variation, "behaviors"), variation)
                    if not untouched then
                        variation.behaviors = steps
                    end
                    entry.hasAbility = true
                    entry.variation = variation
                elseif rawget(entry, "hasAbility") then
                    --back to the ability's own targets: its steps are now gated steps here.
                    entry.hasAbility = nil
                    entry.variation = nil
                end
                modeList[index] = entry
            end
            --the game swaps in a variation under either kind (SwitchModes), so a saved
            --kind is kept; it only becomes "variations" when an option newly gets one.
            local savedKind = Block.FieldValue(ctx.record, "multipleModes")
            if not savedKind then
                result.multipleModes = anyVariation and "variations" or true
            elseif newVariation and savedKind ~= "variations" then
                result.multipleModes = "variations"
            end
            --the game only chooses after targeting with plain modes.
            local after = (instance.values or {}).timing == "after" and not anyVariation
            if (Block.FieldValue(ctx.record, "chooseModeAfterTargeting") == true) ~= after then
                result.chooseModeAfterTargeting = after or nil
            end
            if not dmhub.DeepEqual(modeList, rawget(ctx.record, "modeList")) then
                result.modeList = modeList
            end
        end,
    },
}

Block.RegisterBlock{
    id = "ability.option",
    family = "logic",
    group = "logic",
    label = "Option",
    desc = "One option of Choose one when used: its name, any extra cost, and the steps that happen with it.",
    sentence = { { text = "Option:", bold = true }, " ", { slot = "name" }, ", ", { slot = "cost" }, ". ", { slot = "rules" } },
    slots = {
        name = { kind = "text", default = "", empty = "+ name" },
        cost = { kind = "choice", default = "0", options = EXTRA_COSTS },
        rules = { kind = "text", default = "", empty = "+ card text" },
    },
    bodies = {
        { id = "targets", fits = "optiontargets", max = 1, label = "Targets", sublabel = "the ability's own when empty" },
        { id = "steps", fits = "step" },
    },
    fits = { "option" },
    order = 71,
    changed = function(instance, slotId)
        if slotId ~= "cost" then
            return
        end
        --an extra cost spends the Heroic Resource as the option is used.
        local cost = tonumber(instance.values.cost) or 0
        local steps = instance.bodies.steps
        --only the Spend step this cost made (or matched when opened): one the author added stays.
        for index, step in ipairs(steps) do
            if step.marks ~= nil and step.marks.costStep and _isCostStep(step) then
                if cost > 0 then
                    step.values.quantity = tostring(cost)
                else
                    table.remove(steps, index)
                end
                return
            end
        end
        if cost > 0 then
            local spend = Block.Instantiate("ability.resource")
            if spend ~= nil then
                spend.values.mode = "expend"
                spend.values.quantity = tostring(cost)
                spend.values.resource = CharacterResource.heroicResourceId
                spend.values.who = "caster"
                spend.marks = { costStep = true }
                table.insert(steps, 1, spend)
            end
        end
    end,
}

Block.RegisterBlock{
    id = "ability.optiontargets",
    family = "logic",
    group = "logic",
    label = "Targets differently",
    desc = "Put in an option to give it its own distance and targets. The option then replaces the whole ability when picked, so steps outside Choose one when used do not happen with it.",
    sentence = { { text = "Targets differently:", bold = true }, " ", { slot = "distance" }, " ", { slot = "range" }, ", ", { slot = "count" }, " ", { slot = "target" } },
    slots = { distance = SLOTS.distance, range = SLOTS.range, count = SLOTS.count, target = SLOTS.target },
    fits = { "optiontargets" },
    order = 72,
    changed = function(instance, slotId, previous)
        if slotId == "distance" then
            FIELDS.distance.changed(instance.values, previous)
        end
    end,
}

Block.RegisterBlock{
    id = "ability.strained",
    family = "logic",
    group = "logic",
    label = "Only if Strained",
    desc = "The steps inside only happen when you are (or are not) Strained.",
    sentence = { { text = "Only if", bold = true }, " you are ", { slot = "strain" }, ":" },
    slots = {
        strain = { kind = "choice", default = "strained", options = { { id = "strained", text = "Strained" }, { id = "unstrained", text = "not Strained" } } },
    },
    bodies = { { id = "steps", fits = "step" } },
    fits = { "step" },
    order = 72,
}

Block.RegisterWrapper{
    id = "ability.strained",
    order = 20,
    block = "ability.strained",
    key = function(behavior)
        local strain = rawget(behavior, "strainSelection")
        if type(strain) ~= "string" or strain == "" then
            return nil
        end
        return strain
    end,
    values = function(key)
        return { strain = key }
    end,
    keyOf = function(values)
        return values.strain
    end,
    apply = function(behavior, key)
        behavior.strainSelection = key
    end,
}

Block.RegisterBlock{
    id = "ability.ontier",
    family = "logic",
    group = "logic",
    label = "Only on a tier",
    desc = "The steps inside only happen on some power roll results.",
    sentence = { { text = "Only on", bold = true }, " ", { slot = "tiers" }, ":" },
    slots = {
        tiers = {
            kind = "choice",
            default = "3",
            options = {
                { id = "1", text = "a result of 11 or lower" },
                { id = "2", text = "a result of 12 to 16" },
                { id = "3", text = "a result of 17 or higher" },
                { id = "1,2", text = "a result of 16 or lower" },
                { id = "2,3", text = "a result of 12 or higher" },
                { id = "1,3", text = "a result of 11 or lower, or 17 or higher" },
            },
        },
    },
    bodies = { { id = "steps", fits = "step" } },
    fits = { "step" },
    order = 74,
}

Block.RegisterWrapper{
    id = "ability.ontier",
    order = 30,
    block = "ability.ontier",
    key = function(behavior)
        return _listKey(rawget(behavior, "tiersSelected"))
    end,
    values = function(key)
        return { tiers = key }
    end,
    keyOf = function(values)
        return values.tiers
    end,
    apply = function(behavior, key)
        behavior.tiersSelected = _keyList(key)
    end,
}

Block.RegisterBlock{
    id = "ability.onlyif",
    family = "logic",
    group = "logic",
    label = "Only if",
    desc = "The steps inside only happen for targets that pass a test.",
    sentence = { { text = "Only if", bold = true }, " ", { slot = "test" }, ":" },
    slots = { test = { kind = "testFormula", style = "formula", default = "Target.Winded", empty = "+ test" } },
    bodies = { { id = "steps", fits = "step" } },
    fits = { "step" },
    order = 76,
}

--How each Only if test was spelled, by its plain form: steps whose tests mean
--the same share one block, which shows (and writes) the author's spelling.
local g_testSpelling = {}

--- The plain form of a test, remembering how it was spelled.
--- @param test any
--- @return string|nil
local function _testKey(test)
    if type(test) ~= "string" or string.find(test, "%S") == nil then
        return nil
    end
    local key = Block.FormulaCanonical(test) or test
    if g_testSpelling[key] == nil then
        g_testSpelling[key] = test
    end
    return key
end

Block.RegisterWrapper{
    id = "ability.onlyif",
    order = 40,
    block = "ability.onlyif",
    key = function(behavior)
        return _testKey(rawget(behavior, "filterTarget"))
    end,
    values = function(key)
        return { test = g_testSpelling[key] or key }
    end,
    keyOf = function(values)
        local key = _testKey(values.test)
        if key ~= nil then
            --the block's text is how a step moved into it is written.
            g_testSpelling[key] = values.test
        end
        return key
    end,
    apply = function(behavior, key)
        behavior.filterTarget = key ~= nil and (g_testSpelling[key] or key) or nil
    end,
}

--"Can only be used when": the ability's reasoned filters. The game checks each one
--for every target (a bare name is the target's, Caster.X is yours) and tells the
--player the reason when one fails.
Block.RegisterBlock{
    id = "ability.requirement",
    family = "logic",
    group = "logic",
    label = "Requirement",
    desc = "The ability can only be used on a target that passes this test; otherwise the player is told why. A plain name is the target's (Size), Caster.Size is yours.",
    sentence = { { text = "Only if", bold = true }, " ", { slot = "test" }, ", otherwise the player is told: ", { slot = "reason" } },
    slots = {
        test = { kind = "testFormula", style = "formula", default = "", empty = "+ test" },
        reason = { kind = "text", default = "", empty = "+ reason" },
    },
    fits = { "requirement" },
    order = 78,
}

--- The requirements list: reasonedFilters ({formula, reason}) as Requirement blocks.
--- @type BlockList
local REQUIREMENTS = {
    read = function(record)
        local result = {}
        local saved = rawget(record, "reasonedFilters")
        for _, filter in ipairs(type(saved) == "table" and saved or {}) do
            local formula = rawget(filter, "formula")
            result[#result + 1] = {
                block = "ability.requirement",
                values = {
                    test = type(formula) == "table" and TABLE_FILTER or tostring(formula or ""),
                    reason = tostring(rawget(filter, "reason") or ""),
                },
                saved = DeepCopy(filter),
            }
        end
        return result
    end,
    write = function(result, instances, record)
        local list = {}
        for _, instance in ipairs(instances) do
            local values = instance.values or {}
            local test = tostring(values.test or "")
            --a new requirement with no test yet is not saved: an empty formula could fail every target.
            if instance.saved ~= nil or string.find(test, "%S") ~= nil then
                local entry = DeepCopy(instance.saved or {})
                local savedFormula = rawget(entry, "formula")
                if type(savedFormula) == "table" then
                    --a formula table stays as saved unless the author typed a new test over it.
                    if test ~= TABLE_FILTER then
                        entry.formula = test
                    end
                elseif savedFormula == nil then
                    entry.formula = test
                elseif not Block.SameFormula(tostring(savedFormula), test) then
                    --a test that means the same keeps its saved spelling.
                    entry.formula = test
                end
                if tostring(rawget(entry, "reason") or "") ~= tostring(values.reason or "") then
                    entry.reason = tostring(values.reason or "")
                elseif rawget(entry, "reason") == nil then
                    entry.reason = ""
                end
                list[#list + 1] = entry
            end
        end
        local saved = rawget(record, "reasonedFilters")
        if type(saved) == "table" and dmhub.DeepEqual(saved, list) then
            return
        end
        if #list == 0 and type(saved) ~= "table" then
            return
        end
        result.reasonedFilters = list
    end,
}

----------------------------------------------------------------------------
-- Tests for the test picker (design 4z, 4ab): the true/false formulas of
-- Only if, requirements and the target filter, read back as words. In these
-- formulas a bare name is the target's and Caster.X is yours. Each test keeps
-- how the formula was written (Target. or nothing, caster or Caster) and only
-- rewrites the part the author changes.
----------------------------------------------------------------------------

local NormName = Block.NormName

--- Who a name belongs to: the target (bare, or Target.X) or you (Caster.X).
--- @param path string[]|nil
--- @return string|nil who "target" or "you"
--- @return string|nil prefix the prefix as written (nil when bare)
--- @return string|nil field the name as written
local function _subject(path)
    if type(path) ~= "table" then
        return nil, nil, nil
    end
    if #path == 1 then
        return "target", nil, path[1]
    elseif #path == 2 then
        local prefix = NormName(path[1])
        if prefix == "target" then
            return "target", path[1], path[2]
        elseif prefix == "caster" then
            return "you", path[1], path[2]
        end
    end
    return nil, nil, nil
end

--- A name node for a test's values: the prefix as it was written.
--- @param values table
--- @param field string
--- @return BlockFormulaNode
local function _subjectNode(values, field)
    if values.prefix == nil then
        return { k = "id", path = { field } }
    end
    return { k = "id", path = { values.prefix, field } }
end

--- "the target" / "you", and its possessive and verbs.
local WHO_WORDS = {
    target = { name = "the target", whose = "the target's", is = "is", has = "has" },
    you = { name = "you", whose = "your", is = "are", has = "have" },
}

--- A test may arrive wrapped in "not": its inner node, and whether it was.
--- @param node BlockFormulaNode
--- @return BlockFormulaNode, boolean
local function _unwrapNot(node)
    if node.k == "not" and node.a ~= nil then
        return node.a, true
    end
    return node, false
end

--- Wraps a node in "not" when asked.
--- @param node BlockFormulaNode
--- @param negate boolean
--- @return BlockFormulaNode
local function _maybeNot(node, negate)
    if negate then
        return { k = "not", a = node }
    end
    return node
end

--- The yes/no slot of a fact ("is" / "is not"), worded for who it is about.
--- @param verb string "is" or "has"
--- @return BlockSlot, BlockSlot for the target, for you
local function _yesNoSlots(verb)
    local target = verb == "is" and { "is", "is not" } or { "has", "does not have" }
    local you = verb == "is" and { "are", "are not" } or { "have", "do not have" }
    return { kind = "choice", default = "yes", options = { { id = "yes", text = target[1] }, { id = "no", text = target[2] } } },
        { kind = "choice", default = "yes", options = { { id = "yes", text = you[1] }, { id = "no", text = you[2] } } }
end

--- The condition names from the game's table, as a choice's options.
--- @return {id: string, text: string}[]
local function _conditionOptions()
    local result = {}
    for _, row in unhidden_pairs(dmhub.GetTable("charConditions") or {}) do
        local name = nil
        pcall(function() name = row.name end)
        if type(name) == "string" then
            result[#result + 1] = { id = name, text = string.lower(name) }
        end
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    return result
end

local COMPARE_OPS = {
    { id = "<", text = "is less than" },
    { id = "<=", text = "is at most" },
    { id = ">", text = "is more than" },
    { id = ">=", text = "is at least" },
    { id = "=", text = "is" },
    { id = "~=", text = "is not" },
}

--the numbers the "Compare a number" test offers (another, as written, shows as written).
local COMPARE_FIELDS = {}
for _, name in ipairs({ "Level", "Might", "Agility", "Reason", "Intuition", "Presence", "Stamina", "Size", "Speed",
    "Heroic Resources Available to Spend", "Recoveries" }) do
    COMPARE_FIELDS[#COMPARE_FIELDS + 1] = { id = name, text = name }
end

--- A yes/no fact about the target or you ("the target is winded", "you are
--- Strained"): one test per picker group, each reading its own facts.
--- @param spec {id: string, group: string, label: string, example?: string, search?: string, order: number, facts: {id: string, text: string}[], who: string}
local function _factTest(spec)
    local isTarget, isYou = _yesNoSlots("is")
    local known = {}
    for _, fact in ipairs(spec.facts) do
        known[NormName(fact.id)] = fact.id
    end
    Block.RegisterTest{
        id = spec.id,
        group = spec.group,
        label = spec.label,
        example = spec.example,
        search = spec.search,
        order = spec.order,
        slots = { fact = { kind = "choice", default = spec.facts[1].id, options = spec.facts }, isTarget = isTarget, isYou = isYou },
        make = function()
            local prefix = spec.who == "you" and "Caster" or "Target"
            return { k = "id", path = { prefix, spec.facts[1].id } }
        end,
        read = function(node)
            local inner, negated = _unwrapNot(node)
            if inner.k ~= "id" then
                return nil
            end
            local who, prefix, field = _subject(inner.path)
            local fact = field ~= nil and known[NormName(field)] or nil
            if who == nil or fact == nil then
                return nil
            end
            local answer = negated and "no" or "yes"
            --the fact as written stays when unchanged ("winded" keeps its case).
            return { who = who, prefix = prefix, fact = fact, written = field, isTarget = answer, isYou = answer }
        end,
        words = function(values)
            local words = WHO_WORDS[values.who] or WHO_WORDS.target
            return { words.name, { slot = values.who == "you" and "isYou" or "isTarget" }, { slot = "fact" } }
        end,
        write = function(values, node)
            local answer = values.who == "you" and values.isYou or values.isTarget
            local field = (values.written ~= nil and NormName(values.written) == NormName(values.fact)) and values.written or values.fact
            return _maybeNot(_subjectNode(values, field), answer == "no")
        end,
    }
end

--- "the target has the X condition / keyword / effect": a has test on one list.
--- @param spec {id: string, group: string, label: string, example?: string, search?: string, order: number, list: string, noun: string, value: BlockSlot, default: string}
local function _hasTest(spec)
    local hasTarget, hasYou = _yesNoSlots("has")
    Block.RegisterTest{
        id = spec.id,
        group = spec.group,
        label = spec.label,
        example = spec.example,
        search = spec.search,
        order = spec.order,
        slots = { value = spec.value, hasTarget = hasTarget, hasYou = hasYou },
        make = function()
            return { k = "has", l = { k = "id", path = { "Target", spec.list } }, r = { k = "str", v = spec.default } }
        end,
        read = function(node)
            local inner, negated = _unwrapNot(node)
            if inner.k ~= "has" or inner.l == nil or inner.l.k ~= "id" or inner.r == nil or inner.r.k ~= "str" then
                return nil
            end
            local who, prefix, field = _subject(inner.l.path)
            if who == nil or NormName(field) ~= NormName(spec.list) then
                return nil
            end
            local answer = (negated ~= (inner.neg == true)) and "no" or "yes"
            return { who = who, prefix = prefix, field = field, value = inner.r.v, hasTarget = answer, hasYou = answer, notForm = negated }
        end,
        words = function(values)
            local words = WHO_WORDS[values.who] or WHO_WORDS.target
            return { words.name, { slot = values.who == "you" and "hasYou" or "hasTarget" }, "the", { slot = "value" }, spec.noun }
        end,
        write = function(values, node)
            local answer = values.who == "you" and values.hasYou or values.hasTarget
            local has = { k = "has", l = _subjectNode(values, values.field or spec.list), r = { k = "str", v = tostring(values.value or "") } }
            --"not X has" stays that way; otherwise "has not".
            if answer == "no" and values.notForm then
                return { k = "not", a = has }
            end
            has.neg = answer == "no" or nil
            return has
        end,
    }
end

Block.RegisterTest{
    id = "ds.enemy",
    group = "Check what kind of creature",
    label = "The target is an enemy, or an ally",
    example = "Enemy",
    search = "enemy ally friend foe hostile side",
    order = 10,
    slots = { side = { kind = "choice", default = "enemy", options = { { id = "enemy", text = "an enemy" }, { id = "ally", text = "an ally" } } } },
    make = function()
        return { k = "id", path = { "Enemy" } }
    end,
    read = function(node)
        local inner, negated = _unwrapNot(node)
        if inner.k == "id" and #(inner.path or {}) == 1 and NormName(inner.path[1]) == "enemy" then
            return { side = negated and "ally" or "enemy", form = "enemy", written = inner.path[1] }
        end
        --"Target is Enemy" says the same, kept in its own form.
        if inner.k == "is" and inner.l ~= nil and inner.l.k == "id" and #(inner.l.path or {}) == 1 and NormName(inner.l.path[1]) == "target"
            and inner.r ~= nil and inner.r.k == "id" and #(inner.r.path or {}) == 1 and NormName(inner.r.path[1]) == "enemy" then
            local enemy = (inner.neg == true) == negated
            return { side = enemy and "enemy" or "ally", form = "is", isNode = DeepCopy(inner), notForm = negated }
        end
        --Friends(Caster, Target) in either order: allies; "not" makes it enemies.
        if inner.k == "call" and #(inner.path or {}) == 1 and NormName(inner.path[1]) == "friends" and #(inner.args or {}) == 2 then
            return { side = negated and "enemy" or "ally", form = "friends", call = DeepCopy(inner) }
        end
        return nil
    end,
    words = function(values)
        return { "the target is", { slot = "side" } }
    end,
    write = function(values, node)
        if values.form == "friends" and values.call ~= nil then
            return _maybeNot(DeepCopy(values.call), values.side == "enemy")
        end
        if values.form == "is" and values.isNode ~= nil then
            local isNode = DeepCopy(values.isNode)
            isNode.neg = nil
            --"is not" when it was written that way, else a leading "not".
            if values.side == "ally" and not values.notForm then
                isNode.neg = true
                return isNode
            end
            return _maybeNot(isNode, values.side == "ally")
        end
        return _maybeNot({ k = "id", path = { values.written or "Enemy" } }, values.side == "ally")
    end,
}

_factTest{
    id = "ds.kind", group = "Check what kind of creature", label = "The target is a minion, a hero or an object",
    search = "minion hero object leader solo kind type", order = 11, who = "target",
    facts = { { id = "Minion", text = "a minion" }, { id = "Hero", text = "a hero" }, { id = "Object", text = "an object" },
        { id = "Leader", text = "a leader" }, { id = "Solo", text = "a solo creature" } },
}
_hasTest{
    id = "ds.keyword", group = "Check what kind of creature", label = "The target has a keyword (Undead...)",
    search = "keyword undead demon elemental type", order = 12, list = "Keywords", noun = "keyword",
    value = { kind = "text", default = "Undead", empty = "+ keyword" }, default = "Undead",
}
Block.RegisterTest{
    id = "ds.compare",
    group = "Compare a number",
    label = "The target's [Level] is at least [ ]",
    example = "a characteristic, Stamina, size, speed...",
    search = "level might agility reason intuition presence characteristic stamina size speed heroic resource compare number",
    order = 20,
    slots = {
        field = { kind = "choice", default = "Level", options = COMPARE_FIELDS },
        op = { kind = "choice", default = ">=", options = COMPARE_OPS },
        right = { kind = "formula", style = "formula", default = "1", options = {} },
    },
    make = function()
        return { k = "cmp", op = ">=", l = { k = "id", path = { "Target", "Level" } }, r = { k = "num", v = "1" } }
    end,
    read = function(node)
        if node.k ~= "cmp" or node.l == nil or node.l.k ~= "id" or node.r == nil then
            return nil
        end
        local who, prefix, field = _subject(node.l.path)
        if who == nil then
            return nil
        end
        return { who = who, prefix = prefix, field = field, op = node.op, right = Block.PrintFormula(node.r), rightNode = DeepCopy(node.r) }
    end,
    words = function(values)
        local words = WHO_WORDS[values.who] or WHO_WORDS.target
        return { words.whose, { slot = "field" }, { slot = "op" }, { slot = "right" } }
    end,
    write = function(values, node)
        local right = values.rightNode
        if right == nil or Block.PrintFormula(right) ~= tostring(values.right) then
            right = Block.ParseFormula(tostring(values.right)) or { k = "num", v = tostring(values.right) }
        end
        return { k = "cmp", op = values.op, opText = node ~= nil and node.op == values.op and node.opText or nil, l = _subjectNode(values, values.field), r = right }
    end,
}
_hasTest{
    id = "ds.condition", group = "Check a condition", label = "The target has a condition",
    search = "condition prone slowed grabbed restrained frightened taunted dazed weakened bleeding", order = 30,
    list = "Conditions", noun = "condition",
    value = { kind = "choice", default = "Prone", options = _conditionOptions }, default = "Prone",
}
Block.RegisterTest{
    id = "ds.potency",
    group = "Check potency",
    label = "The target fails a potency check (M < strong)",
    example = "the effect lands if the target's characteristic is below the potency",
    search = "potency might agility reason intuition presence fails passes resist",
    order = 40,
    slots = {
        pass = { kind = "choice", default = "fails", options = { { id = "fails", text = "fails" }, { id = "passes", text = "passes" } } },
        char = { kind = "choice", default = "M", options = {
            { id = "M", text = "Might" }, { id = "A", text = "Agility" }, { id = "R", text = "Reason" },
            { id = "I", text = "Intuition" }, { id = "P", text = "Presence" } } },
        n = { kind = "formula", style = "formula", default = "2", options = {} },
    },
    make = function()
        return { k = "not", a = { k = "call", path = { "Cast", "PassesPotency" }, args = { { k = "id", path = { "Target" } }, { k = "str", v = "M" } } } }
    end,
    read = function(node)
        local inner, negated = _unwrapNot(node)
        local path = inner.path or {}
        if inner.k ~= "call" or #path ~= 2 or NormName(path[1]) ~= "cast" or NormName(path[2]) ~= "passespotency" then
            return nil
        end
        local args = inner.args or {}
        if args[2] == nil or args[2].k ~= "str" then
            return nil
        end
        --a potency can be a number or a word ("Average"): a word shows and saves as a word.
        local n, nIsWord = nil, false
        if args[3] ~= nil then
            nIsWord = args[3].k == "str"
            n = nIsWord and args[3].v or Block.PrintFormula(args[3])
        end
        return { pass = negated and "fails" or "passes", char = args[2].v, n = n, nIsWord = nIsWord, call = DeepCopy(inner) }
    end,
    words = function(values)
        local words = { "the target", { slot = "pass" }, "a", { slot = "char" }, "potency check" }
        if values.n ~= nil then
            words[#words + 1] = "of"
            words[#words + 1] = { slot = "n" }
        end
        return words
    end,
    write = function(values, node)
        local call = DeepCopy(values.call)
        call.args = call.args or {}
        call.args[2] = { k = "str", v = values.char }
        if values.n ~= nil and values.nIsWord then
            call.args[3] = { k = "str", v = tostring(values.n) }
        elseif values.n ~= nil then
            call.args[3] = Block.ParseFormula(tostring(values.n)) or { k = "num", v = tostring(values.n) }
        end
        return _maybeNot(call, values.pass == "fails")
    end,
}
_factTest{
    id = "ds.health", group = "Check health", label = "The target is winded, dying or dead",
    search = "winded bloodied half health stamina dying dead", order = 50, who = "target",
    facts = { { id = "Winded", text = "winded" }, { id = "Dying", text = "dying" }, { id = "Dead", text = "dead" } },
}
_hasTest{
    id = "ds.effect", group = "Check effects", label = "The target has an ongoing effect",
    search = "ongoing effect buff marker", order = 60, list = "Ongoing Effects", noun = "effect",
    value = { kind = "text", default = "", empty = "+ effect name" }, default = "",
}
Block.RegisterTest{
    id = "ds.distance",
    group = "Check what's nearby",
    label = "The target is within [1] square of you",
    search = "distance range adjacent near within squares",
    order = 70,
    slots = {
        op = { kind = "choice", default = "<=", options = COMPARE_OPS },
        right = { kind = "formula", style = "formula", default = "1", options = {} },
    },
    make = function()
        return { k = "cmp", op = "<=", l = { k = "call", path = { "Caster", "Distance" }, args = { { k = "id", path = { "Target" } } } }, r = { k = "num", v = "1" } }
    end,
    read = function(node)
        if node.k ~= "cmp" or node.l == nil or node.l.k ~= "call" or node.r == nil then
            return nil
        end
        local path = node.l.path or {}
        if NormName(path[#path]) ~= "distance" then
            return nil
        end
        return { op = node.op, right = Block.PrintFormula(node.r), call = DeepCopy(node.l) }
    end,
    words = function(values)
        return { "the target's distance from you", { slot = "op" }, { slot = "right" } }
    end,
    write = function(values, node)
        local right = Block.ParseFormula(tostring(values.right)) or { k = "num", v = tostring(values.right) }
        return { k = "cmp", op = values.op, l = DeepCopy(values.call), r = right }
    end,
}
_factTest{
    id = "ds.strained", group = "Strained (Talent)", label = "You are Strained",
    search = "strained strain talent psionic", order = 80, who = "you",
    facts = { { id = "Strained", text = "Strained" } },
}

--Steps no block reads: shown by name, saved back untouched.
Block.RegisterBlock{
    id = "ability.advanced",
    family = "step",
    group = "advanced",
    label = "Advanced",
    desc = "A step no block reads yet. It is kept exactly as saved; edit it in the Advanced editor.",
    sentence = { { slot = "summary" } },
    slots = { summary = { kind = "fixed", default = "" } },
    tag = "Advanced",
    shelf = false,
    fits = { "step", "tier" },
}

--the tables listed first (by /blockeditor's name lookup too): the core class content.
local FIRST_TABLES = { "classes", "subclasses" }

--- Every table to look for abilities in: the class tables first, then every
--- other table the game has, by name.
--- @return string[]
local function _abilityTables()
    local result = {}
    local listed = {}
    for _, tableName in ipairs(FIRST_TABLES) do
        result[#result + 1] = tableName
        listed[tableName] = true
    end
    local others = {}
    for _, tableName in ipairs(dmhub.GetTableTypes() or {}) do
        if not listed[tableName] then
            others[#others + 1] = tableName
        end
    end
    table.sort(others)
    for _, tableName in ipairs(others) do
        result[#result + 1] = tableName
    end
    return result
end

--- Where each listed ability was found: its table, row and the keys down to
--- it. Several rows can hold an ability with the same guid (Censor and Conduit
--- share domain abilities), so saving goes back to the row it was opened from.
--- Weak keys: an ability the tables no longer hold is forgotten.
--- @type table<table, {tableid: string, key: string, path: any[]}>
local g_sources = setmetatable({}, { __mode = "k" })

--- Every top-level ability in the game's tables, then every monster's, with
--- where it was found and its group (the table, or "monsters") for the round
--- trip's report. An ability inside another (a follow-up) is checked as part
--- of its parent; Hidden ones are the engine's own helpers.
--- @return {record: table, where: string, group: string}[]
local function _tableAbilities()
    local result = {}
    local seen = {}
    local function Walk(obj, where, depth, source, path)
        if (type(obj) ~= "table" and type(obj) ~= "userdata") or depth > 16 or seen[obj] then
            return
        end
        seen[obj] = true
        local typeName = nil
        pcall(function() typeName = obj.typeName end)
        if typeName == "ActivatedAbility" then
            if rawget(obj, "categorization") ~= "Hidden" then
                result[#result + 1] = { record = obj, where = where, group = source.tableid }
                g_sources[obj] = { tableid = source.tableid, key = source.key, path = path }
            end
            return
        end
        pcall(function()
            for key, value in pairs(obj) do
                if type(value) == "table" then
                    local inner = { table.unpack(path) }
                    inner[#inner + 1] = key
                    Walk(value, where, depth + 1, source, inner)
                end
            end
        end)
    end
    for _, tableName in ipairs(_abilityTables()) do
        for key, row in unhidden_pairs(dmhub.GetTable(tableName) or {}) do
            local name = nil
            pcall(function() name = row.name end)
            Walk(row, string.format("%s/%s", tableName, tostring(name)), 0, { tableid = tableName, key = key }, {})
        end
    end
    --monsters are assets, not table rows: they are checked, but the window
    --cannot save them yet (no row is found, so the change stays waiting).
    for _, monster in pairs(assets.monsters or {}) do
        local name, list = nil, nil
        pcall(function()
            name = monster.name
            list = monster.info.properties.innateActivatedAbilities
        end)
        for _, ability in ipairs(type(list) == "table" and list or {}) do
            local typeName = nil
            pcall(function() typeName = ability.typeName end)
            if typeName == "ActivatedAbility" and rawget(ability, "categorization") ~= "Hidden" then
                result[#result + 1] = { record = ability, where = "monsters/" .. tostring(name), group = "monsters" }
            end
        end
    end
    return result
end

--- Where an ability is stored: the row it was listed from, or (opened some
--- other way) the first row holding its guid, as the Advanced editor finds it.
--- @param ability table
--- @return {tableid: string, key: string, path: any[]}|nil
local function _sourceOf(ability)
    local source = g_sources[ability]
    if source ~= nil then
        return source
    end
    pcall(function() source = ability:FindCompendiumSource() end)
    return source
end

--- A step's name for its Advanced block: the behaviour type without the
--- "ActivatedAbility" and "Behavior" parts ("Apply Riders").
--- @param step table
--- @return string
local function _stepName(step)
    local typeName = "Behavior"
    pcall(function() typeName = step.typeName end)
    local name = string.gsub(typeName, "^ActivatedAbility", "")
    name = string.gsub(name, "Behaviou?r$", "")
    name = string.gsub(name, "(%l)(%u)", "%1 %2")
    if name == "" then
        name = typeName
    end
    return name
end

--- Uploads the compendium entry (class, subclass, ...) that holds an ability
--- the editor has just written into. Abilities are stored inside their owner,
--- so the whole owner is uploaded, as the Advanced editor does
--- (ActivatedAbility:ShowEditCompendiumSourceDialog).
--- @param ability table
--- @return boolean
local function _uploadOwner(ability)
    if rawget(ability, "guid") == nil then
        error("the ability has no guid, so where it is stored cannot be found")
    end
    local source = _sourceOf(ability)
    if source == nil then
        error(string.format("could not find which compendium entry holds '%s'", tostring(rawget(ability, "name"))))
    end
    local rows = dmhub.GetTable(source.tableid)
    local item = rows ~= nil and rows[source.key] or nil
    if type(item) ~= "table" then
        error(string.format("the compendium entry that held '%s' is gone", tostring(rawget(ability, "name"))))
    end
    --the owner already holds this very ability; re-seat it in case it was copied.
    if source.path ~= nil and #source.path > 0 then
        SetObjectAtPath(item, source.path, ability)
    end
    dmhub.SetAndUploadTableItem(source.tableid, item)
    return true
end

--- The ability as its class or subclass holds it now. A change synced from
--- another client replaces the class row, so the object the editor opened
--- may no longer be the one in the table.
--- @param ability table
--- @return table|nil
local function _locate(ability)
    local guid = rawget(ability, "guid")
    if guid == nil then
        return nil
    end
    local source = _sourceOf(ability)
    if source == nil then
        return nil
    end
    local rows = dmhub.GetTable(source.tableid)
    local item = rows ~= nil and rows[source.key] or nil
    if type(item) ~= "table" then
        return nil
    end
    local current = GetObjectAtPath(item, source.path)
    if type(current) == "table" and rawget(current, "guid") == guid then
        --the newer copy is in the same place: remember it, so saving it goes there too.
        g_sources[current] = source
        return current
    end
    return nil
end

Block.RegisterHost{
    id = "ability",
    upload = _uploadOwner,
    locate = _locate,
    title = "Edit Ability",
    claims = function(record)
        local typeName = nil
        pcall(function() typeName = record.typeName end)
        return typeName == "ActivatedAbility"
    end,
    fields = FIELDS,
    stepsField = "behaviors",
    lists = { requirements = REQUIREMENTS },
    advancedBlock = "ability.advanced",
    records = _tableAbilities,
    stepName = _stepName,
    sections = {
        {
            id = "what",
            title = "What it is",
            rows = {
                { id = "name", sentence = { { slot = "name" }, " is a ", { slot = "category" }, " that takes a ", { slot = "action" } }, slots = SLOTS },
                {
                    id = "cost",
                    sentence = { "which costs ", { slot = "cost" }, " ", { slot = "resource" } },
                    slots = SLOTS,
                    when = function(values) return values.resource ~= nil and values.resource ~= "none" end,
                },
                {
                    --with no resource the amount means nothing ("costs 1 nothing"); picking one shows it.
                    id = "free",
                    sentence = { "which costs ", { slot = "resource" } },
                    slots = SLOTS,
                    when = function(values) return values.resource == nil or values.resource == "none" end,
                },
                { id = "keywords", sentence = { "and has the keywords ", { slot = "keywords" } }, slots = SLOTS },
                { id = "limit", sentence = { "Usage limit: ", { slot = "limit" } }, slots = SLOTS },
                {
                    id = "charges",
                    sentence = { "Uses before it refreshes: ", { slot = "charges" } },
                    slots = SLOTS,
                    when = function(values) return values.limit ~= nil and values.limit ~= "none" end,
                },
                { id = "flavor", sentence = { { text = "Flavor:", style = "aside" }, " ", { slot = "flavor" } }, slots = SLOTS },
            },
        },
        {
            id = "who",
            title = "Who it targets",
            rows = {
                { id = "distance", sentence = { "Distance: ", { slot = "distance" }, " ", { slot = "range" } }, slots = SLOTS },
                { id = "target", sentence = { "Target: ", { slot = "count" }, " ", { slot = "target" } }, slots = SLOTS },
                {
                    id = "targetsAre",
                    sentence = { "Targets are ", { slot = "targetsAre" } },
                    slots = SLOTS,
                    --only an ability with more than one target can pick them one at a time.
                    when = function(values)
                        return values.targetsAre == "sequential" or tostring(values.count) ~= "1"
                    end,
                },
                --the target filter: the game skips any creature that fails it (a bare name is the target's).
                { id = "filter", sentence = { "Only affects a creature if ", { slot = "filter" } }, slots = SLOTS },
            },
        },
        { id = "req", title = "Can only be used when", optional = true, stack = "requirements", fits = "requirement", stackAddText = "add a requirement" },
        { id = "used", title = "When it's used", stack = "blocks", fits = "step", stackAddText = "add step" },
    },
    --the add row at the end of each list inside a block, by the kind of list.
    addTexts = {
        step = "add step",
        tier = "add result",
        option = "add option",
        optiontargets = "targets differently",
    },
    shelfSections = {
        { title = "Common", fits = "step" },
        { title = "Inside a power roll tier", fits = "tier", folded = true },
        { title = "Inside Choose one when used", fits = "option" },
        { title = "Inside an option", fits = "optiontargets" },
        { title = "Can only be used when", fits = "requirement" },
    },
    card = function(model, record)
        local values = model.values or {}
        local title = _text(model, "name")
        local cost = tonumber(values.cost) or 0
        --a cost only means something with a resource to pay it in ("1 nothing" otherwise).
        if cost > 0 and values.resource ~= nil and values.resource ~= "none" then
            title = string.format("%s (%d %s)", title, cost, _text(model, "resource"))
        end
        local action = _text(model, "action")
        --- @type BlockCard
        local card = {
            title = title,
            flavor = values.flavor,
            rows = {
                { left = _text(model, "keywords"), right = string.upper(string.sub(action, 1, 1)) .. string.sub(action, 2), bold = true },
                {
                    left = _cardDistance(model, record),
                    leftIcon = "triangle",
                    right = _cardTarget(model, record),
                    rightIcon = "target",
                },
            },
        }
        --the first power roll block, wherever it sits (it may be inside a wrapper).
        local roll = _findBlock(model.blocks, "ability.powerroll")
        if roll ~= nil then
            card.roll = string.format("Power Roll + %s:", ActivatedAbilityPowerRollBehavior.BlockRollWord(roll))
            card.tiers = {}
            for i, text in ipairs(ActivatedAbilityPowerRollBehavior.BlockTierTexts(roll)) do
                --"#" marks words the game skips but the card shows: drop the mark.
                card.tiers[i] = { parts = _tierParts((string.gsub(text, "#%s*", ""))) }
            end
        else
            --a roll no block reads (2d10 + Reason Modifier, ...): the card reads the saved roll.
            for _, behavior in ipairs(record ~= nil and rawget(record, "behaviors") or {}) do
                local typeName = nil
                pcall(function() typeName = behavior.typeName end)
                if typeName == "ActivatedAbilityPowerRollBehavior" then
                    local savedRoll = tostring(rawget(behavior, "roll") or "")
                    local dice, added = Block.SplitRoll(savedRoll)
                    card.roll = (dice == "2d10" and ("Power Roll + " .. tostring(added)) or savedRoll) .. ":"
                    card.tiers = {}
                    for i, tier in ipairs(rawget(behavior, "tiers") or {}) do
                        card.tiers[i] = { parts = _tierParts(tostring(tier)) }
                    end
                    break
                end
            end
        end
        local effect = type(values.effect) == "string" and values.effect or ""
        --with no description, each option with card text reads as the book prints it
        --("Spend 1 Ferocity: ..."); a description already holds them (ledger 2026-11-28).
        local chooser = string.find(effect, "%S") == nil and _findBlock(model.blocks, "ability.choose") or nil
        for _, option in ipairs(chooser ~= nil and (chooser.bodies or {}).options or {}) do
            local optionValues = option.values or {}
            local rules = tostring(optionValues.rules or "")
            --imported abilities often print the options in their effect already.
            if rules ~= "" and string.find(effect, rules, 1, true) == nil then
                local name = tostring(optionValues.name or "")
                local line = name ~= "" and string.format("%s: %s", name, rules) or rules
                effect = effect ~= "" and (effect .. "\n" .. line) or line
            end
        end
        if effect ~= "" then
            card.paragraphs = _effectParagraphs(effect)
        end
        return card
    end,
    checks = function(model, record)
        --- @type BlockCheck[]
        local result = {}
        local advanced = _countBlocks(model.blocks, "ability.advanced")
        if advanced > 0 then
            local text = advanced == 1 and "No block reads one of the steps yet: it opens as an Advanced block and saves back unchanged."
                or string.format("No block reads %d of the steps yet: they open as Advanced blocks and save back unchanged.", advanced)
            result[#result + 1] = { severity = "warning", text = text }
        end
        local words = _countBlocks(model.blocks, Block.TIER_TEXT_BLOCK)
        if words > 0 then
            local text = words == 1 and "One part of the tier text is words no block reads yet: it is kept as written."
                or string.format("%d parts of the tier text are words no block reads yet: they are kept as written.", words)
            result[#result + 1] = { severity = "warning", text = text }
        end
        local untested = 0
        for _, requirement in ipairs(model.requirements or {}) do
            if string.find(tostring((requirement.values or {}).test or ""), "%S") == nil then
                untested = untested + 1
            end
        end
        if untested > 0 then
            local text = untested == 1 and "A requirement has no test yet: it stops nothing, and a new one is not saved until it has one."
                or string.format("%d requirements have no test yet: they stop nothing, and a new one is not saved until it has one.", untested)
            result[#result + 1] = { severity = "warning", text = text }
        end
        local unnamed = 0
        local chooser = _findBlock(model.blocks, "ability.choose")
        for _, option in ipairs(chooser ~= nil and (chooser.bodies or {}).options or {}) do
            if tostring((option.values or {}).name or "") == "" then
                unnamed = unnamed + 1
            end
        end
        if unnamed > 0 then
            local text = unnamed == 1 and "An option has no name: players pick options by name when they use the ability."
                or string.format("%d options have no name: players pick options by name when they use the ability.", unnamed)
            result[#result + 1] = { severity = "warning", text = text }
        end
        if chooser ~= nil and #((chooser.bodies or {}).options or {}) < 2 then
            result[#result + 1] = { severity = "warning", text = "Choose one when used needs at least two options to be a choice." }
        end
        if model.savesUnchanged == true then
            result[#result + 1] = { severity = "success", text = "Saves back unchanged." }
        elseif model.savesUnchanged == false then
            result[#result + 1] = { severity = "danger", text = "Saving would change this ability: report it as a Block Editor bug." }
        end
        return result
    end,
    order = 20,
}
