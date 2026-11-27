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
        local first, last, letter = string.find(text, "%f[%w]([MARIP])%f[%W]", position)
        if first == nil then
            break
        end
        if first > position then
            parts[#parts + 1] = string.sub(text, position, first - 1)
        end
        parts[#parts + 1] = { chip = letter }
        position = last + 1
    end
    if position <= #text then
        parts[#parts + 1] = string.sub(text, position)
    end
    return parts
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
    keyOf = function(values)
        return values.modes
    end,
    apply = function(behavior, key)
        behavior.modesSelected = _keyList(key)
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
    slots = { test = { kind = "formula", style = "formula", default = "Target.Winded", options = {} } },
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

--the tables whose abilities /blockroundtrip covers: the core class content.
local ROUND_TRIP_TABLES = { "classes", "subclasses" }

--- Every top-level ability in the class tables, with where it was found. An
--- ability inside another (a follow-up) is checked as part of its parent;
--- Hidden ones are the engine's own helpers.
--- @return {record: table, where: string}[]
local function _classAbilities()
    local result = {}
    local seen = {}
    local function Walk(obj, where, depth)
        if (type(obj) ~= "table" and type(obj) ~= "userdata") or depth > 16 or seen[obj] then
            return
        end
        seen[obj] = true
        local typeName = nil
        pcall(function() typeName = obj.typeName end)
        if typeName == "ActivatedAbility" then
            if rawget(obj, "categorization") ~= "Hidden" then
                result[#result + 1] = { record = obj, where = where }
            end
            return
        end
        pcall(function()
            for _, value in pairs(obj) do
                if type(value) == "table" then
                    Walk(value, where, depth + 1)
                end
            end
        end)
    end
    for _, tableName in ipairs(ROUND_TRIP_TABLES) do
        for _, row in unhidden_pairs(dmhub.GetTable(tableName) or {}) do
            Walk(row, string.format("%s/%s", tableName, tostring(row.name)), 0)
        end
    end
    return result
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
    local guid = rawget(ability, "guid")
    if guid == nil then
        error("the ability has no guid, so where it is stored cannot be found")
    end
    local item, tableid, _, path = FindCompendiumItemOwningGuid(guid)
    if item == nil or tableid == nil then
        error(string.format("could not find which compendium entry holds '%s'", tostring(rawget(ability, "name"))))
    end
    --the owner already holds this very ability; re-seat it in case it was copied.
    if path ~= nil and #path > 0 then
        SetObjectAtPath(item, path, ability)
    end
    dmhub.SetAndUploadTableItem(tableid, item)
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
    local source = nil
    pcall(function() source = ability:FindCompendiumSource() end)
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
    advancedBlock = "ability.advanced",
    records = _classAbilities,
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
            },
        },
        { id = "req", title = "Can only be used when", optional = true, addText = "add a requirement" },
        { id = "used", title = "When it's used", stack = "blocks", fits = "step", stackAddText = "add step" },
    },
    shelfSections = {
        { title = "Common", fits = "step" },
        { title = "Inside a power roll tier", fits = "tier" },
    },
    card = function(model, record)
        local values = model.values or {}
        local title = _text(model, "name")
        local cost = tonumber(values.cost) or 0
        if cost > 0 then
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
                    left = _text(model, "distance") .. " " .. _text(model, "range"),
                    leftIcon = "triangle",
                    right = _text(model, "count") .. " " .. _text(model, "target"),
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
        if type(values.effect) == "string" and values.effect ~= "" then
            card.effect = { label = "Effect:", text = values.effect }
        end
        return card
    end,
    checks = function(model, record)
        --- @type BlockCheck[]
        local result = {}
        local advanced = _countBlocks(model.blocks, "ability.advanced")
        if advanced > 0 then
            result[#result + 1] = { severity = "warning", text = string.format("No block reads %d of the steps yet: they open as Advanced blocks and save back unchanged.", advanced) }
        end
        local words = _countBlocks(model.blocks, Block.TIER_TEXT_BLOCK)
        if words > 0 then
            result[#result + 1] = { severity = "warning", text = string.format("%d parts of the tier text are words no block reads yet: they are kept as written.", words) }
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
