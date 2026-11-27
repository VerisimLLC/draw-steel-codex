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
      * Split blocks (BlockDecl.split: Choose one when used) gather their
        options' steps after a list is opened, and save them flat into the
        list again, tagged through a wrapper; the options save as record fields.
      * So an untouched record saves back identical, by construction.

    "forced" (for /blockroundtrip) treats every piece as changed: a header slot
    is written with no opened value to compare against, and a block writes
    every slot it claims. So it tests that each writer reproduces the saved
    form and keeps what it does not claim.
]]

--- @class BERecordCache
BERecordCache = {}

--Given to a header writer as the "opened" value when it must write whatever
--it is given (the lock probe, a forced save): equal to no value.
local NOT_OPENED = {}

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

--- A readable name for a step no block reads: the host's stepName, or the
--- step's typeName split into words.
--- @param behavior table
--- @param host BlockHost
--- @return string
function BERecordCache.BehaviorName(behavior, host)
    if host.stepName ~= nil then
        local ok, name = pcall(host.stepName, behavior)
        if ok and type(name) == "string" then
            return name
        end
    end
    local typeName = "Step"
    pcall(function() typeName = behavior.typeName end)
    return (string.gsub(tostring(typeName), "(%l)(%u)", "%1 %2"))
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

--- The split part of a placed block, when it is one (options holding steps).
--- @param blockId string
--- @return BlockSplit|nil
local function _splitFor(blockId)
    local decl = Block.GetBlock(blockId)
    return decl ~= nil and decl.split or nil
end

--- The registered split blocks.
--- @return BlockDecl[]
local function _splitDecls()
    local result = {}
    for _, decl in ipairs(Block.All("block")) do
        --- @cast decl BlockDecl
        if decl.split ~= nil then
            result[#result + 1] = decl
        end
    end
    return result
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
        values = { summary = BERecordCache.BehaviorName(behavior, host) },
    }
end

--- The context a block's read and write are given, for one list of steps.
--- @param host BlockHost
--- @param record table the record (or nested ability) the steps belong to
--- @param forced? boolean
--- @param result? table the copy being written, when saving
--- @return BlockContext
local function _context(host, record, forced, result)
    --- @type BlockContext
    local ctx
    ctx = {
        host = host,
        record = record,
        forced = forced,
        result = result,
        OpenSteps = function(behaviors, nested)
            return BERecordCache.OpenSteps(behaviors, host, _context(host, nested, forced))
        end,
        --a nested ability's writer passes its own copy, so record fields go into it.
        SaveSteps = function(instances, saved, nested)
            return BERecordCache.SaveSteps(instances, saved, host, _context(host, nested, forced, nested))
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
    for _, decl in ipairs(_splitDecls()) do
        local ok, gathered = pcall(decl.split.gather, top, behaviors, ctx)
        if not ok then
            dmhub.Error(string.format("BlockEditor: block '%s' failed to gather its steps: %s", decl.id, tostring(gathered)))
        elseif type(gathered) == "table" then
            top = gathered
        end
    end
    for _, instance in ipairs(top) do
        if instance.openSignature == nil and _splitFor(instance.block) ~= nil then
            _remember(instance)
        end
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
    --- @type table<string, boolean> the split blocks this list holds, by block id
    local seen = {}
    local prepared = {}
    for _, instance in ipairs(instances or {}) do
        local split = _splitFor(instance.block)
        if split ~= nil and split.prepare ~= nil and not prepared[instance.block] then
            prepared[instance.block] = true
            local ok, err = pcall(split.prepare, instance, ctx)
            if not ok then
                dmhub.Error(string.format("BlockEditor: block '%s' failed to prepare: %s", instance.block, tostring(err)))
            end
        end
    end

    --- Writes one placed step: the behaviour, and whether it is the saved one as it was.
    --- @param instance BlockInstance
    --- @param context table<string, string>
    --- @return table|nil, boolean
    local function WriteStep(instance, context)
        local decl = Block.GetBlock(instance.block)
        local saved = instance.src ~= nil and source[instance.src] or nil
        local unchanged = saved ~= nil and not ctx.forced and Block.InstanceUnchanged(instance)
        local behavior = nil
        local same = false
        if saved ~= nil and (unchanged or decl == nil or decl.write == nil) then
            behavior = DeepCopy(saved)
            same = true
        elseif decl ~= nil and decl.write ~= nil then
            local ok, written = pcall(decl.write, instance.values, saved ~= nil and DeepCopy(saved) or nil, ctx, instance.bodies or {})
            if ok then
                behavior = written
            else
                --a writer that fails keeps the step as saved (a new one is left out), and says why.
                dmhub.Error(string.format("BlockEditor: block '%s' failed to write: %s", decl.id, tostring(written)))
                behavior = saved ~= nil and DeepCopy(saved) or nil
            end
        end
        if behavior ~= nil then
            --only a wrapper the step was moved into or out of sets its field.
            local opened = instance.openContext or {}
            for _, candidate in ipairs(_wrappers()) do
                if context[candidate.id] ~= opened[candidate.id] then
                    candidate.apply(behavior, context[candidate.id], ctx)
                    same = false
                end
            end
        end
        return behavior, same
    end

    --- Collects {behavior, src, same} for a list, flattening wrappers and split blocks.
    --- @param list BlockInstance[]|nil
    --- @param context table<string, string>
    --- @param into table[]
    --- @param inSplit boolean
    local function Walk(list, context, into, inSplit)
        for _, instance in ipairs(list or {}) do
            local wrapper = _wrapperFor(instance.block)
            local split = _splitFor(instance.block)
            if wrapper ~= nil then
                local inner = {}
                for wrapperId, key in pairs(context) do
                    inner[wrapperId] = key
                end
                inner[wrapper.id] = wrapper.keyOf(instance.values or {}, ctx)
                Walk((instance.bodies or {})[wrapper.body or "steps"], inner, into, inSplit)
            elseif split ~= nil then
                if inSplit or seen[instance.block] then
                    --one per list, never inside its own options (the side panel warns).
                    dmhub.Error(string.format("BlockEditor: a second '%s' block in one list was not saved", instance.block))
                else
                    seen[instance.block] = true
                    local parts = {}
                    local ordered = true
                    for index, option in ipairs((instance.bodies or {})[split.body] or {}) do
                        local first = #parts + 1
                        local ok, key = pcall(split.key, option, index, ctx)
                        if not ok then
                            dmhub.Error(string.format("BlockEditor: block '%s' failed to key an option: %s", instance.block, tostring(key)))
                        elseif key ~= false then
                            local inner = {}
                            for wrapperId, value in pairs(context) do
                                inner[wrapperId] = value
                            end
                            inner[split.wrapper] = key
                            Walk((option.bodies or {})[split.steps], inner, parts, true)
                        end
                        for i = first, #parts do
                            local before = i > first and parts[i - 1].src or nil
                            if parts[i].src == nil or (before ~= nil and before > parts[i].src) then
                                ordered = false
                            end
                        end
                    end
                    --only one option runs, so steps saved before, still in their saved
                    --order within each option, go back in the saved order overall.
                    if ordered then
                        table.sort(parts, function(a, b) return a.src < b.src end)
                    end
                    for _, part in ipairs(parts) do
                        into[#into + 1] = part
                    end
                    local ok, err = pcall(split.saveRecord, instance, ctx)
                    if not ok then
                        dmhub.Error(string.format("BlockEditor: block '%s' failed to save its options: %s", instance.block, tostring(err)))
                    end
                end
            else
                local behavior, same = WriteStep(instance, context)
                if behavior ~= nil then
                    into[#into + 1] = { behavior = behavior, src = instance.src, same = same }
                end
            end
        end
    end
    local parts = {}
    Walk(instances, {}, parts, false)
    for _, part in ipairs(parts) do
        out[#out + 1] = part.behavior
        if not part.same or part.src ~= #out then
            untouched = false
        end
    end
    if #out ~= #source then
        untouched = false
    end
    --a list whose split block was taken out: the record loses those fields.
    for _, decl in ipairs(_splitDecls()) do
        if not seen[decl.id] then
            local ok, err = pcall(decl.split.saveRecord, nil, ctx)
            if not ok then
                dmhub.Error(string.format("BlockEditor: block '%s' failed to clear its options: %s", decl.id, tostring(err)))
            end
        end
    end
    return out, untouched
end

--- @param list BlockInstance[]|nil
--- @param inSplit boolean inside a split block's options
--- @return integer
local function _countUnsaveable(list, inSplit)
    local count = 0
    local splits = {}
    for _, instance in ipairs(list or {}) do
        local decl = Block.GetBlock(instance.block)
        local split = decl ~= nil and decl.split or nil
        if split ~= nil then
            --a second one in a list, or one inside another's options, is not saved.
            if inSplit or splits[instance.block] then
                count = count + 1
            end
            splits[instance.block] = true
            --an option's other bodies (its targets) are saved by the split block itself.
            for _, option in ipairs((instance.bodies or {})[split.body] or {}) do
                count = count + _countUnsaveable((option.bodies or {})[split.steps], true)
            end
        else
            local writable = decl ~= nil and (decl.write ~= nil or decl.tier ~= nil or _wrapperFor(instance.block) ~= nil)
            if not writable and instance.src == nil and instance.saved == nil then
                count = count + 1
            end
            for _, body in pairs(instance.bodies or {}) do
                count = count + _countUnsaveable(body, inSplit)
            end
        end
    end
    return count
end

--- How many placed blocks would be lost on save: blocks the author added that
--- have no way to be written (no write, not a wrapper, not part of a tier).
--- The side panel warns about them, so nothing vanishes silently.
--- @param list BlockInstance[]|nil
--- @return integer
function BERecordCache.CountUnsaveable(list)
    return _countUnsaveable(list, false)
end

--- Opens a record into a model for the editor.
--- @param record table the engine record the host edits
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
            --a slot is locked when its writer cannot write this value so that it
            --reads back the same (a distance the editor has no word for): it is
            --shown, but never written. The writer is given an opened value that
            --matches nothing, so it cannot skip the write by comparing.
            local probe = DeepCopy(record)
            local wrote = pcall(field.write, probe, value, NOT_OPENED)
            local readOk, readBack = false, nil
            if wrote then
                readOk, readBack = pcall(field.read, probe)
            end
            if not readOk or not _same(readBack, value) then
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
            --a record that already reads as the value keeps its own form
            --("anyspace" stays, though the space writer would pick "emptyspace").
            local readsSame = false
            if field.read ~= nil then
                local ok, current = pcall(field.read, result)
                readsSame = ok and current ~= nil and _same(current, value)
            end
            if readsSame then
                --nothing to write
            elseif forced then
                field.write(result, value, NOT_OPENED)
            elseif not _same(value, original) then
                field.write(result, value, original)
            end
        end
    end

    if host.stepsField ~= nil then
        local source = rawget(record, host.stepsField) or {}
        local out, untouched = BERecordCache.SaveSteps(model.blocks, source, host, _context(host, record, forced, result))
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
