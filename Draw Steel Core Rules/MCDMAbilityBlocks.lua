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
    if type(saved) == "number" and tonumber(value) ~= nil then
        value = tonumber(value)
    end
    record[fieldName] = value
end

--- A field codec that reads and writes one record field as it is.
--- @param fieldName string
--- @param default any what an absent field reads as
--- @return BlockField
local function _plainField(fieldName, default)
    return {
        touches = { fieldName },
        read = function(record)
            local value = rawget(record, fieldName)
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

local TARGET_TYPE_FOR = {
    self = "self", melee = "target", ranged = "target", burst = "all",
    cube = "cube", line = "line", space = "emptyspace", map = "map",
}

--- @param record table
--- @return string
local function _readDistance(record)
    local targetType = rawget(record, "targetType") or "self"
    if targetType == "target" then
        return tonumber(rawget(record, "range")) == 1 and "melee" or "ranged"
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
            if dmhub.DeepEqual(value or {}, original or {}) then
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
        touches = { "targetType", "range" },
        read = _readDistance,
        write = function(record, value, original)
            if value == original then
                return
            end
            record.targetType = TARGET_TYPE_FOR[value] or "self"
            if value == "melee" then
                record.range = 1
            end
        end,
    },
    target = {
        touches = { "targetAllegiance" },
        read = function(record)
            local allegiance = rawget(record, "targetAllegiance")
            if allegiance == "ally" or allegiance == "enemy" then
                return allegiance
            end
            return "creature"
        end,
        write = function(record, value, original)
            if value == original then
                return
            end
            record.targetAllegiance = value ~= "creature" and value or nil
        end,
    },
}

--- The text of a header value, as its row shows it.
--- @param model table
--- @param slotId string
--- @return string
local function _text(model, slotId)
    local value = (model.values or {})[slotId]
    return Block.SlotText({ id = "ability", sentence = {}, slots = SLOTS } --[[@as BlockDecl]], slotId, value)
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

Block.RegisterHost{
    id = "ability",
    tableName = "abilities",
    title = "Edit Ability",
    claims = function(record)
        local typeName = nil
        pcall(function() typeName = record.typeName end)
        return typeName == "ActivatedAbility"
    end,
    fields = FIELDS,
    stepsField = "behaviors",
    advancedBlock = "ability.advanced",
    sections = {
        {
            id = "what",
            title = "What it is",
            rows = {
                { id = "name", sentence = { { slot = "name" }, " is a ", { slot = "category" }, " that takes a ", { slot = "action" } }, slots = SLOTS },
                { id = "cost", sentence = { "which costs ", { slot = "cost" }, " ", { slot = "resource" } }, slots = SLOTS },
                { id = "keywords", sentence = { "and has the keywords ", { slot = "keywords" } }, slots = SLOTS },
                { id = "flavor", sentence = { { text = "Flavor:", style = "aside" }, " ", { slot = "flavor" } }, slots = SLOTS },
            },
        },
        {
            id = "who",
            title = "Who it targets",
            rows = {
                { id = "distance", sentence = { "Distance: ", { slot = "distance" }, " ", { slot = "range" } }, slots = SLOTS },
                { id = "target", sentence = { "Target: ", { slot = "count" }, " ", { slot = "target" } }, slots = SLOTS },
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
        --until the power roll has its own block (milestone 2b), the card reads the saved roll.
        for _, behavior in ipairs(record ~= nil and rawget(record, "behaviors") or {}) do
            local typeName = nil
            pcall(function() typeName = behavior.typeName end)
            if typeName == "ActivatedAbilityPowerRollBehavior" then
                local roll = tostring(rawget(behavior, "roll") or "")
                card.roll = string.gsub(roll, "^2d10%s*%+%s*", "Power Roll + ") .. ":"
                card.tiers = {}
                for i, tier in ipairs(rawget(behavior, "tiers") or {}) do
                    card.tiers[i] = { parts = _tierParts(tostring(tier)) }
                end
                break
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
        local advanced = 0
        for _, instance in ipairs(model.blocks or {}) do
            if instance.block == "ability.advanced" then
                advanced = advanced + 1
            end
        end
        if advanced > 0 then
            result[#result + 1] = { severity = "warning", text = string.format("No block reads %d of the steps yet: they open as Advanced blocks and save back unchanged.", advanced) }
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
