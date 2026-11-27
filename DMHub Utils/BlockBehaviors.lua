local mod = dmhub.GetModLoading()

--[[
 BlockBehaviors: helpers for declaring the Block Editor's blocks beside the
 ability behaviours they read (an ActivatedAbility's steps). Loads after
 Block.lua, before the game rules, so a behaviour's file can declare its
 block right under the type. Nothing here is Draw Steel's: power roll tiers
 as blocks are in Draw Steel Core Rules/BlockTiers.lua.

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
