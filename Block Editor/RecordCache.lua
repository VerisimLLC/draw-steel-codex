local mod = dmhub.GetModLoading()

--[[
    BERecordCache: opens a record into the editor's model, and saves a model
    back into a record. The contract (ported from the design prototype, and
    what /blockroundtrip checks):

      * Open: each header slot reads its value through the host's field codec
        (host.fields), and each step is offered to the block declarations that
        claim its typeName. A step no block reads opens as an Advanced block.
        Every piece remembers what it was when opened (openValues, src).
      * Save: starts from a copy of the record. A header slot writes only when
        its value changed; a step whose values did not change writes back the
        saved behaviour as it was; a changed step is written by its block from
        a copy of the saved behaviour, so fields the block does not claim stay.
        An Advanced block always writes back its saved behaviour untouched.
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

--- Reads one saved behaviour into a placed block.
--- @param behavior table
--- @param host BlockHost
--- @param ctx table
--- @return BlockInstance
local function _openStep(behavior, host, ctx)
    local typeName = nil
    pcall(function() typeName = behavior.typeName end)
    if typeName ~= nil then
        for _, decl in ipairs(Block.All("block")) do
            --- @cast decl BlockDecl
            if decl.read ~= nil and _contains(decl.claims, typeName) then
                local ok, values = pcall(decl.read, behavior, ctx)
                if not ok then
                    dmhub.Error(string.format("BlockEditor: block '%s' failed to read a %s: %s", decl.id, typeName, tostring(values)))
                elseif values ~= nil then
                    return { block = decl.id, values = values }
                end
            end
        end
    end
    return {
        block = host.advancedBlock or "",
        values = { summary = BERecordCache.BehaviorName(behavior) },
    }
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

    local ctx = { host = host, record = record }
    local steps = {}
    local source = host.stepsField ~= nil and rawget(record, host.stepsField) or nil
    for index, behavior in ipairs(source or {}) do
        local instance = _openStep(behavior, host, ctx)
        instance.src = index
        instance.openValues = DeepCopy(instance.values)
        steps[#steps + 1] = instance
    end

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
    for slotId, field in pairs(host.fields or {}) do
        if not locked[slotId] then
            local value, original = model.values[slotId], openValues[slotId]
            if forced or not _same(value, original) then
                field.write(result, value, original)
            end
        end
    end

    if host.stepsField ~= nil then
        local source = rawget(record, host.stepsField) or {}
        local ctx = { host = host, record = record }
        local out = {}
        local untouched = #model.blocks == #source
        for index, instance in ipairs(model.blocks) do
            local decl = Block.GetBlock(instance.block)
            local saved = instance.src ~= nil and source[instance.src] or nil
            local unchanged = saved ~= nil and not forced and _same(instance.values, instance.openValues)
            if saved ~= nil and (unchanged or decl == nil or decl.write == nil) then
                out[#out + 1] = DeepCopy(saved)
                if instance.src ~= index then
                    untouched = false
                end
            elseif decl ~= nil and decl.write ~= nil then
                out[#out + 1] = decl.write(instance.values, saved ~= nil and DeepCopy(saved) or nil, ctx)
                untouched = false
            end
        end
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
