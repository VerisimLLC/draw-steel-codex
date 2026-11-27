local mod = dmhub.GetModLoading()

--[[
 BlockBehaviors: helpers for declaring the Block Editor's blocks beside the
 ability behaviours they read (an ActivatedAbility's steps). Loads after
 Block.lua and BlockTiers.lua, before the game rules, so a behaviour's file
 can declare its block right under the type:

     Block.RegisterBehaviorBlock{
         id = "ability.heal", family = "step", group = "help", label = "Heal",
         claims = { "ActivatedAbilityHealBehavior" },
         sentence = { "Heal ", { slot = "who" }, " for ", { slot = "amount" }, "." },
         slots = { who = Block.WhoSlot(), amount = { kind = "formula", style = "formula", default = "1" } },
         fields = { who = Block.WhoField(), amount = { field = "roll" } },
     }

 Each slot reads one field (or a codec's read). A field that is not saved
 reads as the type's own default, as the game reads it (Block.FieldValue);
 a codec's default is only for a field neither has. Writing starts from the saved
 behaviour and sets only the fields whose value differs from what the saved
 one reads as, so an untouched field keeps its saved spelling.

 The second half turns power roll tier text (the tier grammar in
 BlockTiers.lua) into tier blocks and back, for the power roll and for rule
 text (DrawSteelCommand).
]]

--- How one slot reads and writes a behaviour.
--- @class BlockFieldCodec
--- @field field? string the behaviour field it shows
--- @field default? any what an absent field reads as
--- @field read? fun(behavior: table): any the slot value, when it is not one field as it is
--- @field write? fun(behavior: table, value: any) sets the behaviour for a value

--- A block declaration with its fields: Block.RegisterBehaviorBlock builds its read and write.
--- @class BlockBehaviorSpec: BlockDecl
--- @field fields table<string, BlockFieldCodec> by slot id
--- @field accept? fun(behavior: table, ctx: BlockContext): boolean whether this block can show a behaviour (otherwise it opens as an Advanced block)
--- @field new? fun(): table a new behaviour for a block dragged from the shelf; the claimed type's new{} when absent
--- @field readBodies? fun(behavior: table, ctx: BlockContext): table<string, BlockInstance[]>|nil the lists in its bodies
--- @field writeBodies? fun(behavior: table, bodies: table<string, BlockInstance[]>, ctx: BlockContext) writes its bodies back into the behaviour

--- Whether two plain values are equal (tables compared deeply).
--- @param a any
--- @param b any
--- @return boolean
local function _same(a, b)
    if type(a) == "table" and type(b) == "table" then
        return Block.ValueSignature(a) == Block.ValueSignature(b)
    end
    return a == b
end

--- A slot's value for a behaviour.
--- @param behavior table
--- @param codec BlockFieldCodec
--- @return any
local function _readField(behavior, codec)
    local value
    if codec.read ~= nil then
        value = codec.read(behavior)
    else
        value = Block.FieldValue(behavior, codec.field)
    end
    if value == nil then
        value = codec.default
    end
    if type(value) == "table" then
        value = DeepCopy(value)
    end
    return value
end

--- @param behavior table
--- @param codec BlockFieldCodec
--- @param value any
local function _writeField(behavior, codec, value)
    if codec.write ~= nil then
        codec.write(behavior, value)
    elseif codec.field ~= nil then
        --nothing saved and the value is the type's default: leave it unsaved.
        if rawget(behavior, codec.field) == nil and _same(value, Block.FieldValue(behavior, codec.field)) then
            return
        end
        behavior[codec.field] = type(value) == "table" and DeepCopy(value) or value
    end
end

--- Registers a block that reads and writes a behaviour's fields slot by slot.
--- @param spec BlockBehaviorSpec
function Block.RegisterBehaviorBlock(spec)
    local fields = spec.fields or {}
    spec.read = function(behavior, ctx)
        if spec.accept ~= nil and not spec.accept(behavior, ctx) then
            return nil
        end
        local values = {}
        for slotId, codec in pairs(fields) do
            values[slotId] = _readField(behavior, codec)
        end
        local bodies = nil
        if spec.readBodies ~= nil then
            bodies = spec.readBodies(behavior, ctx)
        end
        return values, bodies
    end
    spec.write = function(values, saved, ctx, bodies)
        local behavior = saved
        if behavior == nil then
            if spec.new ~= nil then
                behavior = spec.new()
            else
                local typeTable = rawget(_G, (spec.claims or {})[1] or "")
                behavior = typeTable.new{}
            end
        end
        --forced (the round-trip test) writes every slot, to prove each codec
        --writes back the form it read.
        local forced = ctx ~= nil and ctx.forced
        for slotId, codec in pairs(fields) do
            local value = values[slotId]
            if forced or not _same(value, _readField(behavior, codec)) then
                _writeField(behavior, codec, value)
            end
        end
        if spec.writeBodies ~= nil then
            spec.writeBodies(behavior, bodies or {}, ctx)
        end
        return behavior
    end
    Block.RegisterBlock(spec)
end

----------------------------------------------------------------------------
-- Who a step applies to (ActivatedAbilityBehavior.applyto).
----------------------------------------------------------------------------

local WHO_OPTIONS = {
    { id = "targets", text = "the targets" },
    { id = "caster", text = "you" },
    { id = "caster_and_targets", text = "you and the targets" },
    { id = "first_target", text = "the first target" },
    { id = "other_than_first_target", text = "the targets after the first" },
    { id = "target_proximity", text = "the targets and creatures near them" },
    { id = "proximity_only", text = "creatures near the targets" },
    { id = "caster_summoner", text = "your summoner" },
    { id = "caster_companion", text = "your companion" },
    { id = "caster_including_squad", text = "you and your squad" },
    { id = "caster_minions", text = "your minions" },
    { id = "caster_riders", text = "your riders" },
    { id = "caster_mount", text = "your mount" },
    { id = "original_targets", text = "the original targets" },
    { id = "subject", text = "the triggering creature" },
    { id = "winner_opposed", text = "the winner of the opposed roll" },
    { id = "none", text = "no one" },
}

--- The "who" slot: the creatures a step applies to.
--- @return BlockSlot
function Block.WhoSlot()
    return {
        kind = "choice",
        default = "targets",
        options = function()
            local result = {}
            for i, option in ipairs(WHO_OPTIONS) do
                result[i] = option
            end
            --roll groups and other targets the rules add (hit targets, ...).
            for _, applyto in ipairs((GameSystem ~= nil and GameSystem.ApplyToTargetsList) or {}) do
                if type(applyto.id) == "string" and type(applyto.text) == "string" then
                    result[#result + 1] = { id = applyto.id, text = string.lower(applyto.text) }
                end
            end
            return result
        end,
    }
end

--- The codec for the "who" slot.
--- @return BlockFieldCodec
function Block.WhoField()
    return { field = "applyto", default = "targets" }
end

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

----------------------------------------------------------------------------
-- Slot options read from data tables.
----------------------------------------------------------------------------

--- Options listing a data table's rows by name (asked each time the slot's
--- menu opens, so new rows show up).
--- @param tableName string
--- @param none? {id: string, text: string} an option for nothing, first
--- @return fun(): {id: string, text: string}[]
function Block.TableOptions(tableName, none)
    return function()
        local result = {}
        for id, row in unhidden_pairs(dmhub.GetTable(tableName) or {}) do
            local name = nil
            pcall(function() name = row.name end)
            if type(name) == "string" then
                result[#result + 1] = { id = id, text = name }
            end
        end
        table.sort(result, function(a, b) return a.text < b.text end)
        if none ~= nil then
            table.insert(result, 1, none)
        end
        return result
    end
end
