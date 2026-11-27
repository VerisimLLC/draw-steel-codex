local mod = dmhub.GetModLoading()

--[[
    BERecordCache: opens a record into the editor's model, and saves a model
    back into a record. The contract (ported from the design prototype, and
    what /blockroundtrip checks):

      * Open: each header slot reads its value through the host's field codec
        (host.fields), and each step is offered to the block declarations that
        claim its typeName. A block's read gives its values and, for a block
        that holds others, the lists in its bodies (a power roll's tiers, the
        steps of a nested ability). A step no block reads opens as an Advanced
        block. Every piece remembers what it was when opened (openSignature).
      * Wrappers (Block.RegisterWrapper: Only if, Strained, modes, ...) group
        steps by a field every behaviour has; neighbours with the same key
        share one wrapper block. Advanced blocks are never wrapped.
      * Save: starts from a copy of the record. A header slot writes only when
        its value changed; a step that did not change writes back the saved
        behaviour as it was; a changed step is written by its block from a
        copy of the saved behaviour, so fields the block does not claim stay.
        A step moved into or out of a wrapper has only that wrapper's field
        set. An Advanced block always writes back its saved behaviour.
      * So an untouched record saves back identical, by construction.

    "forced" (for /blockroundtrip) treats every piece as changed, to test the
    writers' merge path.
]]

--- @class BERecordCache
BERecordCache = {}

--- Whether two plain values are the same (nil-safe; tables compared deeply).
--- @param a any
--- @param b any
--- @return boolean
local function _same(a, b)
    if a == nil or b == nil then
        return a == b
    end
    if type(a) == "table" and type(b) == "table" then
        return dmhub.DeepEqual(a, b)
    end
    return a == b
end

--- A readable name for a behaviour no block reads: its typeName without the
--- "ActivatedAbility" and "Behavior" parts, split into words.
--- @param behavior table
--- @return string
function BERecordCache.BehaviorName(behavior)
    local typeName = "Behavior"
    pcall(function() typeName = behavior.typeName end)
    local name = string.gsub(typeName, "^ActivatedAbility", "")
    name = string.gsub(name, "Behaviou?r$", "")
    name = string.gsub(name, "(%l)(%u)", "%1 %2")
    if name == "" then
        name = typeName
    end
    return name
end

--- Whether a list holds a value.
--- @param list string[]|nil
--- @param value string
--- @return boolean
local function _contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

--- The registered wrappers, outer first.
--- @return BlockWrapper[]
local function _wrappers()
    return Block.All("wrapper") --[[@as BlockWrapper[] ]]
end

--- The wrapper a placed block stands for, or nil for an ordinary block.
--- @param blockId string
--- @return BlockWrapper|nil
local function _wrapperFor(blockId)
    for _, wrapper in ipairs(_wrappers()) do
        if wrapper.block == blockId then
            return wrapper
        end
    end
    return nil
end

--- Records what a freshly read block (and everything inside it) looks like,
--- so saving can tell whether the author changed it.
--- @param instance BlockInstance
local function _remember(instance)
    for _, list in pairs(instance.bodies or {}) do
        for _, inner in ipairs(list) do
            _remember(inner)
        end
    end
    instance.openSignature = Block.InstanceSignature(instance)
end

--- Reads one saved behaviour into a placed block.
--- @param behavior table
--- @param host BlockHost
--- @param ctx BlockContext
--- @return BlockInstance
local function _openStep(behavior, host, ctx)
    local typeName = nil
    pcall(function() typeName = behavior.typeName end)
    if typeName ~= nil then
        for _, decl in ipairs(Block.All("block")) do
            --- @cast decl BlockDecl
            if decl.read ~= nil and _contains(decl.claims, typeName) then
                local ok, values, bodies = pcall(decl.read, behavior, ctx)
                if not ok then
                    dmhub.Error(string.format("BlockEditor: block '%s' failed to read a %s: %s", decl.id, typeName, tostring(values)))
                elseif values ~= nil then
                    return { block = decl.id, values = values, bodies = bodies }
                end
            end
        end
    end
    return {
        block = host.advancedBlock or "",
        values = { summary = BERecordCache.BehaviorName(behavior) },
    }
end

--- The context a block's read and write are given, for one list of steps.
--- @param host BlockHost
--- @param record table the record (or nested ability) the steps belong to
--- @param forced? boolean
--- @return BlockContext
local function _context(host, record, forced)
    --- @type BlockContext
    local ctx
    ctx = {
        host = host,
        record = record,
        forced = forced,
        OpenSteps = function(behaviors, nested)
            return BERecordCache.OpenSteps(behaviors, host, _context(host, nested, forced))
        end,
        SaveSteps = function(instances, saved, nested)
            return BERecordCache.SaveSteps(instances, saved, host, _context(host, nested, forced))
        end,
    }
    return ctx
end

--- Reads a list of saved behaviours into placed blocks, grouping neighbours
--- that share a wrapper key into one wrapper block.
--- @param behaviors table[]|nil
--- @param host BlockHost
--- @param ctx BlockContext
--- @return BlockInstance[]
function BERecordCache.OpenSteps(behaviors, host, ctx)
    local top = {}
    --the wrapper blocks the last step went into, outer first: {wrapper, key, list}.
    local chain = {}
    for index, behavior in ipairs(behaviors or {}) do
        local instance = _openStep(behavior, host, ctx)
        instance.src = index
        local keys = {}
        local context = {}
        if instance.block ~= host.advancedBlock then
            for _, wrapper in ipairs(_wrappers()) do
                local ok, key = pcall(wrapper.key, behavior, ctx)
                if ok and key ~= nil then
                    keys[#keys + 1] = { wrapper = wrapper, key = key }
                    context[wrapper.id] = key
                end
            end
        end
        instance.openContext = context
        _remember(instance)

        --keep the wrappers this step shares with the one before it; open the rest.
        local depth = 0
        while depth < #chain and depth < #keys and chain[depth + 1].wrapper == keys[depth + 1].wrapper and chain[depth + 1].key == keys[depth + 1].key do
            depth = depth + 1
        end
        for i = #chain, depth + 1, -1 do
            chain[i] = nil
        end
        for i = depth + 1, #keys do
            local wrapper, key = keys[i].wrapper, keys[i].key
            local bodyId = wrapper.body or "steps"
            local list = {}
            local holder = { block = wrapper.block, values = wrapper.values(key, ctx), bodies = { [bodyId] = list } }
            local parent = #chain > 0 and chain[#chain].list or top
            parent[#parent + 1] = holder
            chain[#chain + 1] = { wrapper = wrapper, key = key, list = list }
        end
        local target = #chain > 0 and chain[#chain].list or top
        target[#target + 1] = instance
    end
    return top
end

--- Writes placed blocks back to a list of behaviours.
--- @param instances BlockInstance[]
--- @param source table[]|nil the saved list they were opened from
--- @param host BlockHost
--- @param ctx BlockContext
--- @return table[] behaviors, boolean untouched (the saved list can be kept as it is)
function BERecordCache.SaveSteps(instances, source, host, ctx)
    source = source or {}
    local out = {}
    local untouched = true
    local function Walk(list, context)
        for _, instance in ipairs(list or {}) do
            local wrapper = _wrapperFor(instance.block)
            if wrapper ~= nil then
                local inner = {}
                for wrapperId, key in pairs(context) do
                    inner[wrapperId] = key
                end
                inner[wrapper.id] = wrapper.keyOf(instance.values or {}, ctx)
                Walk((instance.bodies or {})[wrapper.body or "steps"], inner)
            else
                local decl = Block.GetBlock(instance.block)
                local saved = instance.src ~= nil and source[instance.src] or nil
                local unchanged = saved ~= nil and not ctx.forced and Block.InstanceUnchanged(instance)
                local behavior = nil
                if saved ~= nil and (unchanged or decl == nil or decl.write == nil) then
                    behavior = DeepCopy(saved)
                    if instance.src ~= #out + 1 then
                        untouched = false
                    end
                elseif decl ~= nil and decl.write ~= nil then
                    behavior = decl.write(instance.values, saved ~= nil and DeepCopy(saved) or nil, ctx, instance.bodies or {})
                    untouched = false
                end
                if behavior ~= nil then
                    --only a wrapper the step was moved into or out of sets its field.
                    local opened = instance.openContext or {}
                    for _, candidate in ipairs(_wrappers()) do
                        if context[candidate.id] ~= opened[candidate.id] then
                            candidate.apply(behavior, context[candidate.id], ctx)
                            untouched = false
                        end
                    end
                    out[#out + 1] = behavior
                end
            end
        end
    end
    Walk(instances, {})
    if #out ~= #source then
        untouched = false
    end
    return out, untouched
end

--- How many placed blocks would be lost on save: blocks the author added that
--- have no way to be written (no write, not a wrapper, not part of a tier).
--- The side panel warns about them, so nothing vanishes silently.
--- @param list BlockInstance[]|nil
--- @return integer
function BERecordCache.CountUnsaveable(list)
    local count = 0
    for _, instance in ipairs(list or {}) do
        local decl = Block.GetBlock(instance.block)
        local writable = decl ~= nil and (decl.write ~= nil or decl.tier ~= nil or _wrapperFor(instance.block) ~= nil)
        if not writable and instance.src == nil and instance.saved == nil then
            count = count + 1
        end
        for _, body in pairs(instance.bodies or {}) do
            count = count + BERecordCache.CountUnsaveable(body)
        end
    end
    return count
end

--- Opens a record into a model for the editor.
--- @param record table the engine record (an ActivatedAbility, ...)
--- @param host BlockHost
--- @return BERecordModel
function BERecordCache.Open(record, host)
    local values, locked = {}, {}
    for slotId, field in pairs(host.fields or {}) do
        local ok, value = pcall(field.read, record)
        if not ok then
            locked[slotId] = true
            dmhub.Error(string.format("BlockEditor: reading '%s' failed: %s", slotId, tostring(value)))
        else
            values[slotId] = value
            --a slot is locked when writing its own value back would change the
            --record: it is shown, but never written.
            local probe = {}
            for _, fieldName in ipairs(field.touches or {}) do
                probe[fieldName] = DeepCopy(rawget(record, fieldName))
            end
            local wrote = pcall(field.write, probe, value, value)
            local same = wrote
            for _, fieldName in ipairs(field.touches or {}) do
                if same and not _same(probe[fieldName], rawget(record, fieldName)) then
                    same = false
                end
            end
            if not same then
                locked[slotId] = true
            end
        end
    end

    local source = host.stepsField ~= nil and rawget(record, host.stepsField) or nil
    local steps = BERecordCache.OpenSteps(source, host, _context(host, record))

    local id, name = nil, nil
    pcall(function() id = record.guid end)
    pcall(function() name = record.name end)
    return {
        id = type(id) == "string" and id or "record",
        name = type(name) == "string" and name or "",
        values = values,
        openValues = DeepCopy(values),
        locked = locked,
        blocks = steps,
    }
end

--- Saves a model back into a copy of the record it was opened from.
--- @param model BERecordModel
--- @param record table the record it was opened from (not changed)
--- @param host BlockHost
--- @param forced? boolean treat every piece as changed (the round-trip test of the writers)
--- @return table saved the new record
function BERecordCache.Save(model, record, host, forced)
    local result = DeepCopy(record)
    local locked = model.locked or {}
    local openValues = model.openValues or {}
    --a fixed order, so two slots that touch one field always save the same way.
    local slotIds = {}
    for slotId, _ in pairs(host.fields or {}) do
        slotIds[#slotIds + 1] = slotId
    end
    table.sort(slotIds)
    for _, slotId in ipairs(slotIds) do
        local field = host.fields[slotId]
        if not locked[slotId] then
            local value, original = model.values[slotId], openValues[slotId]
            if forced or not _same(value, original) then
                field.write(result, value, original)
            end
        end
    end

    if host.stepsField ~= nil then
        local source = rawget(record, host.stepsField) or {}
        local out, untouched = BERecordCache.SaveSteps(model.blocks, source, host, _context(host, record, forced))
        --only a list that changed is replaced, so an untouched one keeps its own form.
        if not untouched then
            result[host.stepsField] = out
        end
    end
    return result
end

--- Whether a model saves back to exactly the record it was opened from.
--- @param model BERecordModel
--- @param record table
--- @param host BlockHost
--- @param forced? boolean
--- @return boolean same, table|nil diff
function BERecordCache.SavesUnchanged(model, record, host, forced)
    local saved = BERecordCache.Save(model, record, host, forced)
    if dmhub.DeepEqual(saved, record) then
        return true, nil
    end
    return false, dmhub.GetDiff(record, saved)
end
