local mod = dmhub.GetModLoading()

--[[
 BlockTiers: reads a power roll tier ("3 + M damage; M < weak, slowed (save ends)")
 into segments the Block Editor shows as blocks, and writes segments back to text.

 A tier is split on ";". Each part is offered to the tier rules in order; the
 first whose match returns values wins. A part no rule reads becomes a "todo"
 segment holding its words, so nothing is ever lost:

     local segments = Block.ParseTier("3 + M damage; slide 2")
     -- { {kind = "damage", values = {base = "3", characteristic = "M", ...}, text = "3 + M damage"},
     --   {kind = "forced", values = {movement = "slide", distance = "2"}, text = " slide 2"} }
     Block.CompileTier(segments) --> "3 + M damage; slide 2" (exactly what was read)

 A segment whose values were not changed writes back its original text, so an
 unedited tier always saves byte-identical. A changed one is written by its
 rule's compile, keeping the spaces and period that were around it.

 The second half shows the segments as tier blocks (Block.TierInstances and
 Block.TierText), for the power roll block and any block that holds tiers.

 It is Draw Steel's grammar, so it lives in Draw Steel Core Rules and loads
 before the files that declare tier blocks (MCDMAbilityBehavior.lua,
 MCDMAbilityRollBehavior.lua).

 Rules are data: a rules file can add or replace one (by id) with
 Block.RegisterTierRule. The grammar here is ported from the design prototype
 (ui-mockup/ability-blocks-stack.html, parseTierText and compileTier).
]]

--- One part of a tier, between semicolons.
--- @class BlockTierSegment
--- @field kind string the id of the rule that read it, "todo" for words no rule reads, "empty" for nothing
--- @field values table what the rule read; the editor changes these
--- @field text? string the part exactly as it was saved, spaces and period included; nil for a new segment
--- @field lead? string the spaces before the part's words ("" for a new segment)
--- @field trail? string the period and spaces after its words
--- @field openSignature? string the values as read, so an unchanged segment writes back its text

--- A way to read one kind of tier part.
--- @class BlockTierRule
--- @field id string also the kind of the segments it reads
--- @field order? number tried low first (absent = 1000)
--- @field match fun(text: string): table|nil the values for a part's words (trimmed, no final period), or nil when it does not read them
--- @field compile fun(values: table): string the words for values

--id -> rule.
--- @type table<string, BlockTierRule>
local g_rules = {}
--id -> when first registered, so re-registering keeps its place among equal orders.
--- @type table<string, number>
local g_ruleSequence = {}
local g_nextSequence = 1
--the rules in the order they are tried; rebuilt after any registration.
--- @type BlockTierRule[]|nil
local g_ruleList = nil

--- @param message string
local function Report(message)
    dmhub.Error("BlockTiers: " .. message)
end

--- Adds a tier rule, or replaces the one with the same id.
--- @param rule BlockTierRule
function Block.RegisterTierRule(rule)
    if type(rule) ~= "table" or type(rule.id) ~= "string" or rule.id == "" then
        Report("RegisterTierRule needs a table with an id")
        return
    end
    if type(rule.match) ~= "function" or type(rule.compile) ~= "function" then
        Report(string.format("tier rule '%s' needs match and compile functions", rule.id))
        return
    end
    if rule.id == "todo" or rule.id == "empty" then
        Report(string.format("tier rule id '%s' is reserved", rule.id))
        return
    end
    if g_ruleSequence[rule.id] == nil then
        g_ruleSequence[rule.id] = g_nextSequence
        g_nextSequence = g_nextSequence + 1
    end
    g_rules[rule.id] = rule
    g_ruleList = nil
end

--- The tier rules in the order they are tried. Do not change the list returned.
--- @return BlockTierRule[]
function Block.TierRules()
    if g_ruleList ~= nil then
        return g_ruleList
    end
    local list = {}
    for _, rule in pairs(g_rules) do
        list[#list + 1] = rule
    end
    table.sort(list, function(a, b)
        local orderA, orderB = a.order or 1000, b.order or 1000
        if orderA ~= orderB then
            return orderA < orderB
        end
        return g_ruleSequence[a.id] < g_ruleSequence[b.id]
    end)
    g_ruleList = list
    return list
end

--- @param id string
--- @return BlockTierRule|nil
function Block.GetTierRule(id)
    return g_rules[id]
end

----------------------------------------------------------------------------
-- Names the rules look up: conditions, their riders and ongoing effects.
-- Each is a function returning a list, so a plain-Lua test can swap in its own
-- (Block.TierLookups.conditions = function() return {...} end).
----------------------------------------------------------------------------

--- @class BlockTierName
--- @field id string
--- @field name string

--- @class BlockTierRider
--- @field id string
--- @field condition string the condition id it belongs to
--- @field words string how it reads after the condition ("and cannot stand")

--- @class BlockTierLookups
--- @field conditions fun(): BlockTierName[]
--- @field riders fun(): BlockTierRider[]
--- @field effects fun(): BlockTierName[]

--- @type BlockTierLookups
Block.TierLookups = {
    conditions = function()
        local result = {}
        for id, row in unhidden_pairs(dmhub.GetTable(CharacterCondition.tableName) or {}) do
            result[#result + 1] = { id = id, name = row.name }
        end
        return result
    end,
    riders = function()
        local result = {}
        for id, row in unhidden_pairs(dmhub.GetTable(CharacterCondition.ridersTableName) or {}) do
            local text = row:try_get("powerTableText")
            if text == nil or text == "" then
                text = row.name
            end
            result[#result + 1] = { id = id, condition = row:try_get("condition") or "", words = text }
        end
        return result
    end,
    effects = function()
        local result = {}
        for id, row in unhidden_pairs(dmhub.GetTable(CharacterOngoingEffect.tableName) or {}) do
            result[#result + 1] = { id = id, name = row.name }
        end
        return result
    end,
}

--The lookups, indexed by lower-case name; built on first use, dropped when tables change.
local g_index = nil

--- Clears the name indexes, so the next parse reads the lookups again.
function Block.TierLookupsChanged()
    g_index = nil
end

if dmhub.RegisterEventHandler ~= nil then
    dmhub.RegisterEventHandler("refreshTables", function()
        if mod.unloaded then
            return
        end
        g_index = nil
    end)
end

--- How a rider reads after its condition: lower case, starting "and " or "with ",
--- and "can't" spelled "cannot" (the spelling both sides are compared in).
--- @param words string
--- @return string
local function RiderWords(words)
    local text = string.lower(words or "")
    text = text:gsub("can't", "cannot"):gsub("can not", "cannot")
    if text:find("^and ") == nil and text:find("^with ") == nil then
        text = "and " .. text
    end
    return text
end

--- @return {conditionsByName: table<string, BlockTierName>, conditionsById: table<string, BlockTierName>, conditionList: BlockTierName[], riders: BlockTierRider[], ridersById: table<string, BlockTierRider>, effectsByName: table<string, BlockTierName>, effectsById: table<string, BlockTierName>}
local function Index()
    if g_index ~= nil then
        return g_index
    end
    local index = { conditionsByName = {}, conditionsById = {}, conditionList = {}, riders = {}, ridersById = {}, effectsByName = {}, effectsById = {} }
    local ok, err = pcall(function()
        for _, entry in ipairs(Block.TierLookups.conditions()) do
            if type(entry.name) == "string" and entry.name ~= "" then
                index.conditionsByName[string.lower(entry.name)] = entry
                index.conditionsById[entry.id] = entry
                index.conditionList[#index.conditionList + 1] = entry
            end
        end
        for _, rider in ipairs(Block.TierLookups.riders()) do
            if type(rider.words) == "string" and rider.words ~= "" then
                index.riders[#index.riders + 1] = rider
                index.ridersById[rider.id] = rider
            end
        end
        for _, entry in ipairs(Block.TierLookups.effects()) do
            if type(entry.name) == "string" and entry.name ~= "" then
                --the first effect of a name wins, so a duplicate never changes which one a tier means.
                local key = string.lower(entry.name)
                if index.effectsByName[key] == nil then
                    index.effectsByName[key] = entry
                end
                index.effectsById[entry.id] = entry
            end
        end
    end)
    if not ok then
        Report("reading the condition and effect tables failed: " .. tostring(err))
    end
    g_index = index
    return index
end

----------------------------------------------------------------------------
-- Parsing and compiling.
----------------------------------------------------------------------------

--- A stable string for a value, so "were these values changed?" is one compare.
--- A nested segment counts by its kind and values only.
--- @param value any
--- @return string
local function Signature(value)
    if type(value) ~= "table" then
        return type(value) .. ":" .. tostring(value)
    end
    if type(value.kind) == "string" and type(value.values) == "table" then
        return "seg(" .. value.kind .. "|" .. Signature(value.values) .. ")"
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i, key in ipairs(keys) do
        parts[i] = tostring(key) .. "=" .. Signature(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- Reads the words of one part (no semicolons) into a segment. Rules that hold
--- other parts (a potency check, "X and Y") call this for the words inside.
--- @param words string
--- @return BlockTierSegment
function Block.ParseTierSegment(words)
    local lead, body, trail = words:match("^(%s*)(.-)(%.?%s*)$")
    local segment
    if body == "" then
        segment = { kind = "empty", values = {} }
    else
        for _, rule in ipairs(Block.TierRules()) do
            local ok, values = pcall(rule.match, body)
            if not ok then
                Report(string.format("tier rule '%s' failed on \"%s\": %s", rule.id, body, tostring(values)))
            elseif type(values) == "table" then
                segment = { kind = rule.id, values = values }
                break
            end
        end
        if segment == nil then
            segment = { kind = "todo", values = { text = body } }
        end
    end
    segment.text = words
    segment.lead = lead
    segment.trail = trail
    segment.openSignature = Signature(segment)
    return segment
end

--- A tier's text as segments, one per part between semicolons.
--- @param text string
--- @return BlockTierSegment[]
function Block.ParseTier(text)
    local segments = {}
    text = text or ""
    local start = 1
    while true do
        local stop = text:find(";", start, true)
        if stop == nil then
            segments[#segments + 1] = Block.ParseTierSegment(text:sub(start))
            break
        end
        segments[#segments + 1] = Block.ParseTierSegment(text:sub(start, stop - 1))
        start = stop + 1
    end
    return segments
end

--- The words of one segment: its saved text when unchanged, else its rule's compile.
--- @param segment BlockTierSegment
--- @param defaultLead? string spaces before a new segment's words
--- @return string
function Block.CompileTierSegment(segment, defaultLead)
    if segment.text ~= nil and segment.openSignature == Signature(segment) then
        return segment.text
    end
    local words
    if segment.kind == "empty" then
        words = ""
    elseif segment.kind == "todo" then
        words = tostring(segment.values.text or "")
    else
        local rule = g_rules[segment.kind]
        if rule == nil then
            Report(string.format("no tier rule '%s' to write a segment", tostring(segment.kind)))
            words = tostring(segment.values.text or "")
        else
            local ok, result = pcall(rule.compile, segment.values)
            if ok and type(result) == "string" then
                words = result
            else
                Report(string.format("tier rule '%s' could not write its values: %s", segment.kind, tostring(result)))
                words = ""
            end
        end
    end
    return (segment.lead or defaultLead or "") .. words .. (segment.trail or "")
end

--- Segments back to tier text. Unedited segments give back exactly what was read.
--- @param segments BlockTierSegment[]
--- @return string
function Block.CompileTier(segments)
    local parts = {}
    for i, segment in ipairs(segments) do
        parts[i] = Block.CompileTierSegment(segment, i > 1 and " " or "")
    end
    return table.concat(parts, ";")
end

--- Whether a segment, or a segment inside it, is words no rule reads.
--- @param segment BlockTierSegment
--- @return boolean
function Block.TierSegmentHasTodo(segment)
    if segment.kind == "todo" then
        return true
    end
    for _, value in pairs(segment.values or {}) do
        if type(value) == "table" and type(value.kind) == "string" and type(value.values) == "table" then
            if Block.TierSegmentHasTodo(value) then
                return true
            end
        end
    end
    return false
end

----------------------------------------------------------------------------
-- The core Draw Steel tier grammar.
----------------------------------------------------------------------------

--- The core damage types, for when the game's own list is not loaded (the
--- plain-Lua tests). "untyped" is written as no word at all.
--- @type string[]
Block.TierDamageTypes = { "fire", "cold", "acid", "poison", "holy", "corruption", "psychic", "lightning", "sonic" }

--- The damage types a tier can name between the amount and "damage": the
--- game's list (custom ones included), lower case, without "untyped".
--- @return string[]
function Block.DamageTypes()
    local available = rawget(_G, "rules") ~= nil and rules.damageTypesAvailable or nil
    if type(available) ~= "table" or #available == 0 then
        return Block.TierDamageTypes
    end
    local result = {}
    for _, damageType in ipairs(available) do
        if damageType ~= "untyped" and damageType ~= "all" then
            result[#result + 1] = damageType
        end
    end
    return result
end

--- @param word string lower case
--- @return boolean
local function IsDamageType(word)
    for _, damageType in ipairs(Block.DamageTypes()) do
        if damageType == word then
            return true
        end
    end
    return false
end

--- Reads what follows a damage amount: "[type] damage [(added)]".
--- @param rest string lower case
--- @return {damageType: string, added: boolean}|nil
local function ReadDamageTail(rest)
    local damageType = "untyped"
    local after = rest:match("^%s*damage(.*)$")
    if after == nil then
        local word
        word, after = rest:match("^%s*(%a+)%s+damage(.*)$")
        if word == nil or not IsDamageType(word) then
            return nil
        end
        damageType = word
    end
    if after == "" then
        return { damageType = damageType, added = false }
    end
    if after:match("^%s*%(added%)$") then
        return { damageType = damageType, added = true }
    end
    return nil
end

--- " fire damage (added)": the words after an amount.
--- @param values {damageType?: string, added?: boolean}
--- @return string
local function DamageTail(values)
    local typeWords = ""
    if values.damageType ~= nil and values.damageType ~= "untyped" then
        typeWords = values.damageType .. " "
    end
    return " " .. typeWords .. "damage" .. (values.added and " (added)" or "")
end

--A potency check: "M < weak, slowed (save ends)". The words after it are read
--as their own segment (values.inner). values.prefix keeps how the check was
--spelled ("M<WEAK, ") while its characteristic and threshold are unchanged.
Block.RegisterTierRule{
    id = "potency",
    order = 10,
    match = function(text)
        local letter, after = text:match("^([MARIPmarip])%s*<%s*(.*)$")
        if letter == nil then
            return nil
        end
        --content sometimes wraps the threshold in [] or {}: "M < {Strong}, grabbed".
        local threshold, rest = after:match("^[%[{]?(%a+)[%]}]?(.*)$")
        if threshold == nil or (threshold:lower() ~= "weak" and threshold:lower() ~= "average" and threshold:lower() ~= "strong") then
            threshold, rest = after:match("^[%[{]?(%d+)[%]}]?(.*)$")
        end
        if threshold == nil then
            return nil
        end
        local separator, inner = rest:match("^(%s*,?%s*)(.+)$")
        if inner == nil then
            return nil
        end
        return {
            characteristic = letter:upper(),
            threshold = threshold:lower(),
            prefix = text:sub(1, #text - #inner),
            inner = Block.ParseTierSegment(inner),
        }
    end,
    compile = function(values)
        local prefix = values.prefix
        if prefix ~= nil then
            --the saved spelling, unless the check itself was changed.
            local letter, threshold = prefix:match("^(%a)%s*<%s*[%[{]?(%w+)")
            if letter == nil or letter:upper() ~= values.characteristic or threshold:lower() ~= values.threshold then
                prefix = nil
            end
        end
        prefix = prefix or (values.characteristic .. " < " .. values.threshold .. ", ")
        return prefix .. Block.CompileTierSegment(values.inner)
    end,
}

--A formula amount in braces: "{2*Reason} damage", "{Might} fire damage (added)".
Block.RegisterTierRule{
    id = "formulaDamage",
    order = 20,
    match = function(text)
        local formula, rest = text:match("^{([^{}|]+)}(.*)$")
        if formula == nil then
            return nil
        end
        local tail = ReadDamageTail(rest:lower())
        if tail == nil then
            return nil
        end
        return { formula = formula, damageType = tail.damageType, added = tail.added }
    end,
    compile = function(values)
        return "{" .. tostring(values.formula) .. "}" .. DamageTail(values)
    end,
}

--- Reads "M or A", "M, R, I, or P": two or more characteristic letters.
--- @param text string
--- @return string[]|nil
local function ReadCharacteristicChoice(text)
    local letters = {}
    local first, rest = text:match("^([MARIP])(.*)$")
    if first == nil then
        return nil
    end
    letters[1] = first
    while rest ~= "" do
        local letter, after = rest:match("^,?%s+or%s+([MARIP])(.*)$")
        if letter == nil then
            letter, after = rest:match("^,?%s+([MARIP])(.*)$")
        end
        if letter == nil then
            return nil
        end
        letters[#letters + 1] = letter
        rest = after
    end
    if #letters < 2 then
        return nil
    end
    return letters
end

--Kit damage: "5 + M or A damage", "3 + M, R, I, or P holy damage" (the
--characteristic the roll used).
Block.RegisterTierRule{
    id = "kitDamage",
    order = 30,
    match = function(text)
        local base, rest = text:match("^(%d+)%s*%+%s*(.*)$")
        if base == nil then
            return nil
        end
        --the letters run up to the last one before the damage words.
        local lettersText, tailText = rest:match("^([MARIP][MARIP,%sor]-[MARIP])(%s+.*)$")
        if lettersText == nil then
            return nil
        end
        local letters = ReadCharacteristicChoice(lettersText)
        local tail = ReadDamageTail(tailText:lower())
        if letters == nil or tail == nil or tail.added then
            return nil
        end
        return { base = base, characteristics = letters, damageType = tail.damageType }
    end,
    compile = function(values)
        local letters = values.characteristics or {}
        local choice
        if #letters <= 2 then
            choice = table.concat(letters, " or ")
        else
            choice = table.concat(letters, ", ", 1, #letters - 1) .. ", or " .. letters[#letters]
        end
        return tostring(values.base) .. " + " .. choice .. DamageTail(values)
    end,
}

--Plain damage: "9 damage", "3 + M fire damage", "2 damage (added)".
Block.RegisterTierRule{
    id = "damage",
    order = 40,
    match = function(text)
        local lower = text:lower()
        local base, rest = lower:match("^(%d+)(.*)$")
        if base == nil then
            return nil
        end
        local letter, after = rest:match("^%s*%+%s*([marip])(.*)$")
        if letter ~= nil then
            rest = after
        end
        local tail = ReadDamageTail(rest)
        if tail == nil then
            return nil
        end
        return { base = base, characteristic = letter and letter:upper() or nil, damageType = tail.damageType, added = tail.added }
    end,
    compile = function(values)
        local amount = tostring(values.base)
        if values.characteristic ~= nil then
            amount = amount .. " + " .. values.characteristic
        end
        return amount .. DamageTail(values)
    end,
}

--Longest first, so "vertical push straight up" is not read as "vertical push".
local g_forcedMovements = { "vertical push straight up", "vertical push", "vertical pull", "vertical slide", "push", "pull", "slide" }

--Forced movement: "push 2", "vertical slide 3", "slide {Might}" (a formula distance).
Block.RegisterTierRule{
    id = "forced",
    order = 50,
    match = function(text)
        local lower = text:lower()
        for _, movement in ipairs(g_forcedMovements) do
            if lower:sub(1, #movement + 1) == movement .. " " then
                local distance = lower:sub(#movement + 2):match("^(%d+)$")
                if distance == nil and text:sub(#movement + 2):match("^{[^{}|]+}$") then
                    distance = text:sub(#movement + 2)
                end
                if distance ~= nil then
                    return { movement = movement, distance = distance }
                end
            end
        end
        return nil
    end,
    compile = function(values)
        return tostring(values.movement) .. " " .. tostring(values.distance)
    end,
}

local g_numberWords = { one = 1, two = 2, three = 3, four = 4 }
local g_surgeWords = { [1] = "one surge", [2] = "two surges", [3] = "three surges" }

--"the target gains two surges".
Block.RegisterTierRule{
    id = "surges",
    order = 60,
    match = function(text)
        local lower = text:lower():gsub("^the ", ""):gsub("^each ", "")
        local count = lower:match("^target gains (%w+) surges?$")
        if count == nil then
            return nil
        end
        local number = g_numberWords[count] or tonumber(count:match("^%d+$") or "")
        if number == nil then
            return nil
        end
        return { count = number }
    end,
    compile = function(values)
        return "the target gains " .. (g_surgeWords[values.count] or (tostring(values.count) .. " surges"))
    end,
}

--Card text the game does not apply: "#Director loses 2 Malice".
Block.RegisterTierRule{
    id = "note",
    order = 70,
    match = function(text)
        local words = text:match("^#%s*(.*)$")
        if words == nil then
            return nil
        end
        return { text = words }
    end,
    compile = function(values)
        return "#" .. tostring(values.text)
    end,
}

local g_durations = { ["save ends"] = "save ends", eot = "EoT", eoe = "EoE" }

--- Splits "slowed (save ends)" into "slowed" and the duration.
--- @param text string
--- @return string words, string|nil duration
local function SplitDuration(text)
    local words, duration = text:match("^(.-)%s*%(([%a ]+)%)$")
    if words ~= nil and g_durations[duration:lower()] ~= nil then
        return words, g_durations[duration:lower()]
    end
    return text, nil
end

--A condition, with an optional rider and duration: "slowed (save ends)",
--"prone and can't stand (EoT)", "taunted".
Block.RegisterTierRule{
    id = "condition",
    order = 80,
    match = function(text)
        local words, duration = SplitDuration(text)
        local lower = words:lower()
        local index = Index()
        local condition = index.conditionsByName[lower]
        if condition ~= nil then
            return { condition = condition.id, duration = duration }
        end
        --"<condition> and/with <rider>": a rider must belong to that condition.
        local wanted = lower:gsub("can't", "cannot"):gsub("can not", "cannot")
        for _, candidate in ipairs(index.conditionList) do
            local name = string.lower(candidate.name)
            if wanted:sub(1, #name + 1) == name .. " " then
                local riderWords = wanted:sub(#name + 2)
                if riderWords:find("^and ") ~= nil or riderWords:find("^with ") ~= nil then
                    local bare = "and " .. riderWords:gsub("^and ", ""):gsub("^with ", "")
                    for _, rider in ipairs(index.riders) do
                        if rider.condition == candidate.id then
                            local known = RiderWords(rider.words)
                            if known == riderWords or known == bare then
                                return { condition = candidate.id, rider = rider.id, duration = duration }
                            end
                        end
                    end
                end
            end
        end
        return nil
    end,
    compile = function(values)
        local index = Index()
        local condition = index.conditionsById[values.condition]
        local words = string.lower(condition ~= nil and condition.name or tostring(values.condition))
        local rider = values.rider ~= nil and index.ridersById[values.rider] or nil
        if rider ~= nil then
            words = words .. " " .. RiderWords(rider.words)
        end
        if values.duration ~= nil then
            words = words .. " (" .. values.duration .. ")"
        end
        return words
    end,
}

--An ongoing effect from the compendium, by name, with a duration:
--"jaws of death (save ends)".
Block.RegisterTierRule{
    id = "effect",
    order = 90,
    match = function(text)
        local words, duration = SplitDuration(text)
        if duration == nil then
            return nil
        end
        local effect = Index().effectsByName[words:lower()]
        if effect == nil then
            return nil
        end
        return { effect = effect.id, duration = duration }
    end,
    compile = function(values)
        local effect = Index().effectsById[values.effect]
        local name = effect ~= nil and effect.name or tostring(values.effect)
        return string.lower(name) .. " (" .. tostring(values.duration) .. ")"
    end,
}

--Two results joined by "and" ("push 4 and prone"): read only when both halves read.
Block.RegisterTierRule{
    id = "both",
    order = 100,
    match = function(text)
        local first, joiner, second = text:match("^(.-)(%s+and%s+)(.+)$")
        if first == nil or second:find("%s+and%s+") ~= nil then
            return nil
        end
        local firstSegment = Block.ParseTierSegment(first)
        local secondSegment = Block.ParseTierSegment(second)
        if Block.TierSegmentHasTodo(firstSegment) or Block.TierSegmentHasTodo(secondSegment)
            or firstSegment.kind == "empty" or secondSegment.kind == "empty" then
            return nil
        end
        return { first = firstSegment, joiner = joiner, second = secondSegment }
    end,
    compile = function(values)
        return Block.CompileTierSegment(values.first) .. (values.joiner or " and ") .. Block.CompileTierSegment(values.second)
    end,
}

----------------------------------------------------------------------------
-- Power roll tiers as blocks. Each segment of a tier (BlockTiers.lua) becomes
-- one tier block, chosen by the segment's kind (BlockDecl.tier). A segment
-- that holds others (a potency check, "X and Y") holds them in bodies named
-- after the value they came from.
----------------------------------------------------------------------------

--- Whether a value is a nested tier segment.
--- @param value any
--- @return boolean
local function _isSegment(value)
    return type(value) == "table" and type(value.kind) == "string" and type(value.values) == "table"
end

--- @param list string[]
--- @param value string
--- @return boolean
local function _has(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

--- The tier block for a segment: the first whose tier info takes its kind.
--- @param segment BlockTierSegment
--- @return BlockDecl|nil
local function _tierBlockFor(segment)
    for _, decl in ipairs(Block.All("block")) do
        --- @cast decl BlockDecl
        local info = decl.tier
        if info ~= nil and _has(info.kinds, segment.kind) then
            local ok, accepted = true, true
            if info.accepts ~= nil then
                ok, accepted = pcall(info.accepts, segment.values)
            end
            if ok and accepted then
                return decl
            end
        end
    end
    return nil
end

--- The id of the block words no tier block reads open as (BlockDecl id).
Block.TIER_TEXT_BLOCK = "tier.text"

--- A placed tier block for one segment.
--- @param segment BlockTierSegment
--- @return BlockInstance
function Block.TierInstance(segment)
    local decl = _tierBlockFor(segment)
    local values, bodies = {}, nil
    if decl == nil then
        --a kind no block shows: its words, kept as written.
        decl = Block.GetBlock(Block.TIER_TEXT_BLOCK)
        values = { text = string.match(segment.text or "", "^%s*(.-)%.?%s*$") }
    else
        for key, value in pairs(segment.values) do
            if _isSegment(value) then
                bodies = bodies or {}
                bodies[key] = { Block.TierInstance(value) }
            else
                values[key] = type(value) == "table" and DeepCopy(value) or value
            end
        end
        if decl.tier.from ~= nil then
            values = decl.tier.from(values)
        end
    end
    local saved = DeepCopy(segment)
    saved.valuesSignature = Block.ValueSignature(values)
    return { block = decl ~= nil and decl.id or Block.TIER_TEXT_BLOCK, values = values, bodies = bodies, saved = saved }
end

--- A tier's text as placed tier blocks.
--- @param text string|nil
--- @return BlockInstance[]
function Block.TierInstances(text)
    local result = {}
    for i, segment in ipairs(Block.ParseTier(text or "")) do
        result[i] = Block.TierInstance(segment)
    end
    return result
end

--- The segment a placed tier block stands for. Values the author did not
--- change keep the segment's saved text (Block.CompileTierSegment decides).
--- @param instance BlockInstance
--- @return BlockTierSegment
function Block.TierSegmentOf(instance)
    local saved = instance.saved
    local decl = Block.GetBlock(instance.block)
    local info = decl ~= nil and decl.tier or nil
    local lead = saved ~= nil and saved.lead or nil
    local trail = saved ~= nil and saved.trail or ""
    if info == nil then
        --not a tier block (an Advanced block dropped in): kept as it was, or nothing.
        if saved ~= nil then
            return DeepCopy(saved)
        end
        return { kind = "empty", values = {} }
    end
    if info.words ~= nil then
        if saved ~= nil and saved.valuesSignature == Block.ValueSignature(instance.values or {}) and instance.bodies == nil then
            return DeepCopy(saved)
        end
        return { kind = "todo", values = { text = info.words(instance.values or {}) }, lead = lead, trail = trail }
    end
    local values = DeepCopy(instance.values or {})
    for bodyId, list in pairs(instance.bodies or {}) do
        if list[1] ~= nil then
            values[bodyId] = Block.TierSegmentOf(list[1])
        else
            values[bodyId] = { kind = "empty", values = {} }
        end
    end
    local kind = info.kinds[1]
    if saved ~= nil and _has(info.kinds, saved.kind) then
        kind = saved.kind
    end
    --an empty part the author typed words into is words now.
    if kind == "empty" and (values.text or "") ~= "" then
        kind = "todo"
    end
    return {
        kind = kind,
        values = values,
        lead = lead,
        trail = trail,
        text = saved ~= nil and saved.text or nil,
        openSignature = saved ~= nil and saved.openSignature or nil,
    }
end

--- Placed tier blocks back to tier text.
--- @param instances BlockInstance[]|nil
--- @return string
function Block.TierText(instances)
    local segments = {}
    for i, instance in ipairs(instances or {}) do
        segments[i] = Block.TierSegmentOf(instance)
    end
    return Block.CompileTier(segments)
end

--- Whether a list of tier blocks (and any inside them) holds words no tier block reads.
--- @param instances BlockInstance[]|nil
--- @return boolean
function Block.TierHasText(instances)
    for _, instance in ipairs(instances or {}) do
        if instance.block == Block.TIER_TEXT_BLOCK then
            return true
        end
        for _, list in pairs(instance.bodies or {}) do
            if Block.TierHasText(list) then
                return true
            end
        end
    end
    return false
end
