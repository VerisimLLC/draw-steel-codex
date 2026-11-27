--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/block_recordcache_test.lua
--Checks the Block Editor's save rules without the app (Block Editor/RecordCache.lua,
--with DMHub Utils/BlockBehaviors.lua): an untouched record saves back identical,
--an edited block changes only the fields it claims, moving a step out of a wrapper
--clears only that wrapper's field, and unsaved fields read as the type's defaults.
--Uses made-up behaviour types, so it does not depend on the compendium.

local g_errors = {}

--- Deep equality for plain tables, as dmhub.DeepEqual.
--- @param a any
--- @param b any
--- @return boolean
local function Equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not Equal(v, b[k]) then
            return false
        end
    end
    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

--- The codex's DeepCopy: plain tables copied, the metatable (the "type") kept.
--- @param t any
--- @return any
local function Copy(t)
    if type(t) ~= "table" then
        return t
    end
    local result = {}
    for k, v in pairs(t) do
        result[k] = Copy(v)
    end
    return setmetatable(result, getmetatable(t))
end

--Stand-ins for what the files under test call, set with rawset so the type
--checker does not take them for second definitions of the real globals.
rawset(_G, "dmhub", {
    GetModLoading = function() return { unloaded = false } end,
    Error = function(message) g_errors[#g_errors + 1] = message end,
    DeepEqual = Equal,
    GetDiff = function(a, b) return { before = a, after = b } end,
})
rawset(_G, "DeepCopy", Copy)
rawset(_G, "json", function() return "{}" end)

local function readSource(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return source
end
for _, path in ipairs({ "DMHub Utils/Block.lua", "DMHub Utils/BlockFormula.lua", "DMHub Utils/BlockBehaviors.lua", "Block Editor/RecordCache.lua" }) do
    assert(load(readSource(path), path))()
end

local g_checks = 0
local function Check(condition, what)
    g_checks = g_checks + 1
    if not condition then
        error("FAILED: " .. what, 2)
    end
end

--- A made-up game type: a field read that is not saved falls back to the
--- type's defaults, as with RegisterGameType.
--- @param name string
--- @param defaults table
local function FakeType(name, defaults)
    local meta = { __index = defaults }
    local typeTable = {
        new = function(fields)
            local obj = setmetatable({}, meta)
            for k, v in pairs(fields or {}) do
                obj[k] = v
            end
            return obj
        end,
    }
    defaults.typeName = name
    rawset(_G, name, typeTable)
    return typeTable
end

local Damage = FakeType("FakeDamageBehavior", { damageType = "force", roll = "1d6" })
local Heal = FakeType("FakeHealBehavior", { roll = "1d6" })
local Other = FakeType("FakeOtherBehavior", {})

Block.RegisterBlock{
    id = "t.advanced", family = "step", group = "advanced", label = "Advanced",
    sentence = { { slot = "summary" } }, slots = { summary = { kind = "fixed", default = "" } },
    shelf = false, fits = { "step" },
}
Block.RegisterBehaviorBlock{
    id = "t.damage", family = "step", group = "harm", label = "Deal damage",
    sentence = { "Deal ", { slot = "amount" }, " ", { slot = "damageType" }, " damage" },
    slots = { amount = { kind = "formula", default = "2" }, damageType = { kind = "choice", default = "" } },
    fits = { "step" },
    claims = { "FakeDamageBehavior" },
    fields = { amount = { field = "roll" }, damageType = { field = "damageType" } },
}
Block.RegisterBehaviorBlock{
    id = "t.heal", family = "step", group = "help", label = "Heal",
    sentence = { "Heal ", { slot = "amount" } },
    slots = { amount = { kind = "formula", default = "1" } },
    fits = { "step" },
    claims = { "FakeHealBehavior" },
    fields = { amount = { field = "roll" } },
}
Block.RegisterBlock{
    id = "t.onlyif", family = "logic", group = "logic", label = "Only if",
    sentence = { "Only if ", { slot = "test" } },
    slots = { test = { kind = "formula", default = "Target.Winded" } },
    bodies = { { id = "steps", fits = "step" } }, fits = { "step" },
}
Block.RegisterWrapper{
    id = "t.onlyif", order = 10, block = "t.onlyif",
    key = function(behavior) return rawget(behavior, "filterTarget") end,
    values = function(key) return { test = key } end,
    keyOf = function(values) return values.test end,
    apply = function(behavior, key) behavior.filterTarget = key end,
}
--a block a stub might be: on the shelf, but nothing can save it.
Block.RegisterBlock{
    id = "t.nowrite", family = "step", group = "harm", label = "No writer",
    sentence = { "Nothing" }, fits = { "step" },
}

local function NameField()
    return {
        touches = { "name" },
        read = function(record) return rawget(record, "name") or "" end,
        write = function(record, value, original)
            if value ~= original then
                record.name = value
            end
        end,
    }
end

--a field whose writer cannot write what it reads (here it fails), so the slot
--must lock: shown, never written.
local function KindField()
    return {
        touches = { "kind" },
        read = function(record) return rawget(record, "kind") end,
        write = function(record, value, original)
            error("this writer cannot write a kind")
        end,
    }
end

--- @type BlockHost
local host = {
    id = "t.host", tableName = "none", claims = function() return true end,
    fields = { name = NameField(), kind = KindField() },
    stepsField = "behaviors",
    advancedBlock = "t.advanced",
}

local function Record()
    return {
        name = "Test",
        kind = "fancy",
        behaviors = {
            Damage.new{ roll = "2 + M", extra = { keep = true } },
            Heal.new{ roll = "3", filterTarget = "Target.Winded" },
            Damage.new{ roll = "4", damageType = "fire", filterTarget = "Target.Winded" },
            Other.new{ something = 1 },
        },
    }
end

--untouched: identical, and the steps read as their blocks.
local record = Record()
local model = BERecordCache.Open(record, host)
Check(BERecordCache.SavesUnchanged(model, record, host), "an untouched record saves back identical")
Check(#model.blocks == 3 and model.blocks[1].block == "t.damage" and model.blocks[2].block == "t.onlyif"
    and #model.blocks[2].bodies.steps == 2 and model.blocks[3].block == "t.advanced", "steps open as blocks, neighbours share a wrapper")
Check(model.blocks[1].values.damageType == "force", "an unsaved damage type reads as the type's default (force)")
Check(model.locked.kind == true and not model.locked.name, "a slot whose writer fails is locked")
Check(BERecordCache.SavesUnchanged(model, record, host, true), "a forced save of an untouched record is identical")

--editing one value changes only that field.
model = BERecordCache.Open(record, host)
model.blocks[1].values.amount = "5"
local saved = BERecordCache.Save(model, record, host)
Check(saved.behaviors[1].roll == "5" and Equal(saved.behaviors[1].extra, { keep = true }) and rawget(saved.behaviors[1], "damageType") == nil,
    "an edited block writes only its changed field and keeps the rest")
Check(Equal(saved.behaviors[2], record.behaviors[2]) and Equal(saved.behaviors[4], record.behaviors[4]), "the other steps are untouched")
Check(getmetatable(saved.behaviors[1]) == getmetatable(record.behaviors[1]), "an edited step keeps its type")

--a formula retyped with the same meaning keeps its saved spelling.
model = BERecordCache.Open(record, host)
model.blocks[1].values.amount = "2+M"
saved = BERecordCache.Save(model, record, host)
Check(saved.behaviors[1].roll == "2 + M", "a formula that means the same is not rewritten")

--moving a step out of its wrapper clears only that wrapper's field.
model = BERecordCache.Open(record, host)
local moved = table.remove(model.blocks[2].bodies.steps, 1)
table.insert(model.blocks, 1, moved)
saved = BERecordCache.Save(model, record, host)
Check(saved.behaviors[1].roll == "3" and rawget(saved.behaviors[1], "filterTarget") == nil, "a step moved out of Only if loses its test")
Check(saved.behaviors[3].filterTarget == "Target.Winded", "the step left inside keeps its test")

--changing the wrapper's test changes it for every step inside.
model = BERecordCache.Open(record, host)
model.blocks[2].values.test = "Target.Prone"
saved = BERecordCache.Save(model, record, host)
Check(saved.behaviors[2].filterTarget == "Target.Prone" and saved.behaviors[3].filterTarget == "Target.Prone"
    and rawget(saved.behaviors[1], "filterTarget") == nil, "a wrapper's new test is set on its steps only")

--deleting and reordering.
model = BERecordCache.Open(record, host)
table.remove(model.blocks, 1)
saved = BERecordCache.Save(model, record, host)
Check(#saved.behaviors == 3 and Equal(saved.behaviors[1], record.behaviors[2]), "a deleted step is gone and the rest are kept")
model = BERecordCache.Open(record, host)
model.blocks[1], model.blocks[3] = model.blocks[3], model.blocks[1]
saved = BERecordCache.Save(model, record, host)
Check(Equal(saved.behaviors[1], record.behaviors[4]) and Equal(saved.behaviors[4], record.behaviors[1]), "reordered steps save in the new order")

--a new block from the shelf is written from a new behaviour of its type.
model = BERecordCache.Open(record, host)
model.blocks[#model.blocks + 1] = { block = "t.damage", values = { amount = "7", damageType = "" } }
saved = BERecordCache.Save(model, record, host)
local added = saved.behaviors[5]
Check(added ~= nil and added.typeName == "FakeDamageBehavior" and added.roll == "7" and rawget(added, "damageType") == "", "a new block writes a new behaviour")

--a header edit changes only its field.
model = BERecordCache.Open(record, host)
model.values.name = "Renamed"
saved = BERecordCache.Save(model, record, host)
Check(saved.name == "Renamed" and saved.kind == "fancy", "a header edit writes its field; a locked slot is never written")

--a block nothing can save is counted, so the editor can warn.
model = BERecordCache.Open(record, host)
model.blocks[#model.blocks + 1] = { block = "t.nowrite", values = {} }
Check(BERecordCache.CountUnsaveable(model.blocks) == 1, "an added block with no writer is counted as unsaveable")
Check(BERecordCache.CountUnsaveable(BERecordCache.Open(record, host).blocks) == 0, "opened blocks are never unsaveable")

Check(#g_errors == 0, "no errors were reported: " .. table.concat(g_errors, "; "))

--a writer that fails keeps the saved step rather than breaking the save.
local heal = Block.GetBlock("t.heal") --[[@as BlockDecl]]
local realWrite = heal.write
heal.write = function() error("broken") end
model = BERecordCache.Open(record, host)
model.blocks[2].bodies.steps[1].values.amount = "9"
saved = BERecordCache.Save(model, record, host)
Check(Equal(saved.behaviors[2], record.behaviors[2]) and #g_errors == 1, "a failing writer keeps the saved step and reports it")
heal.write = realWrite

--a writer is skipped when what is saved already reads as the value, so a
--spelling it would rebuild differently survives (header slots and steps).
local Roll = FakeType("FakeRollBehavior", { roll = "2d10" })
Block.RegisterBehaviorBlock{
    id = "t.roll", family = "step", group = "rolls", label = "Roll",
    sentence = { "Roll + ", { slot = "stat" } },
    slots = { stat = { kind = "choice", default = "might" }, note = { kind = "text", default = "" } },
    fits = { "step" },
    claims = { "FakeRollBehavior" },
    fields = {
        stat = {
            read = function(behavior) return string.lower((string.match(rawget(behavior, "roll") or "", "(%a+)%s*$"))) end,
            write = function(behavior, value) behavior.roll = "2d10 + " .. value end,
        },
        note = { field = "note" },
    },
}
local spaceHost = {
    id = "t.spacehost", claims = function() return true end,
    fields = {
        distance = {
            touches = { "targetType" },
            read = function(record)
                local targetType = rawget(record, "targetType")
                return (targetType == "anyspace" or targetType == "emptyspace") and "space" or "self"
            end,
            write = function(record, value) record.targetType = value == "space" and "emptyspace" or "self" end,
        },
    },
    stepsField = "behaviors",
    advancedBlock = "t.advanced",
}
local spaced = { targetType = "anyspace", behaviors = { Roll.new{ roll = "2d10 +Agility" } } }
Check(BERecordCache.SavesUnchanged(BERecordCache.Open(spaced, spaceHost), spaced, spaceHost, true),
    "a forced save keeps forms the writers would respell (anyspace, 2d10 +Agility)")
model = BERecordCache.Open(spaced, spaceHost)
model.blocks[1].values.note = "edited"
saved = BERecordCache.Save(model, spaced, spaceHost)
Check(saved.behaviors[1].note == "edited" and saved.behaviors[1].roll == "2d10 +Agility",
    "editing a step rewrites its slots but keeps a roll that reads the same")
model.blocks[1].values.stat = "might"
saved = BERecordCache.Save(model, spaced, spaceHost)
Check(saved.behaviors[1].roll == "2d10 + might", "a changed value is still written")

--a split block (Choose one when used): options hold steps that save flat,
--tagged through a wrapper, and the options save as a record field.
Block.RegisterBlock{
    id = "t.mode", family = "logic", group = "logic", label = "In a mode",
    sentence = { "In mode ", { slot = "mode" } }, slots = { mode = { kind = "fixed", default = "" } },
    bodies = { { id = "steps", fits = "step" } }, fits = { "step" }, shelf = false,
}
Block.RegisterWrapper{
    id = "t.mode", order = 5, block = "t.mode",
    key = function(behavior, ctx)
        local mode = rawget(behavior, "mode")
        return rawget(ctx.record, "modes") ~= nil and mode ~= nil and tostring(mode) or nil
    end,
    values = function(key) return { mode = key } end,
    keyOf = function(values) return values.mode end,
    apply = function(behavior, key) behavior.mode = tonumber(key) end,
}
Block.RegisterBlock{
    id = "t.option", family = "logic", group = "logic", label = "Option",
    sentence = { "Option ", { slot = "name" } }, slots = { name = { kind = "text", default = "" } },
    bodies = { { id = "steps", fits = "step" } }, fits = { "option" },
}
Block.RegisterBlock{
    id = "t.choose", family = "logic", group = "logic", label = "Choose one",
    sentence = { "Choose one" }, bodies = { { id = "options", fits = "option" } }, fits = { "step" },
    initial = function(instance)
        instance.bodies.options = { Block.Instantiate("t.option"), Block.Instantiate("t.option") }
    end,
    split = {
        body = "options", steps = "steps", wrapper = "t.mode",
        gather = function(list, behaviors, ctx)
            local modes = rawget(ctx.record, "modes")
            if modes == nil then
                return list
            end
            local options = {}
            for i, name in ipairs(modes) do
                options[i] = { block = "t.option", values = { name = name }, bodies = { steps = {} } }
            end
            local chooser = { block = "t.choose", values = {}, bodies = { options = options } }
            local result = {}
            for _, instance in ipairs(list) do
                local number = instance.block == "t.mode" and tonumber(instance.values.mode) or nil
                if number ~= nil and options[number] ~= nil then
                    for _, step in ipairs(instance.bodies.steps) do
                        table.insert(options[number].bodies.steps, step)
                    end
                    if chooser.placed == nil then
                        chooser.placed = true
                        result[#result + 1] = chooser
                    end
                else
                    result[#result + 1] = instance
                end
            end
            chooser.placed = nil
            return result
        end,
        key = function(_, index) return tostring(index) end,
        saveRecord = function(instance, ctx)
            if instance == nil then
                if rawget(ctx.record, "modes") ~= nil then
                    ctx.result.modes = nil
                end
                return
            end
            local names = {}
            for i, option in ipairs(instance.bodies.options) do
                names[i] = option.values.name
            end
            if not Equal(names, rawget(ctx.record, "modes")) then
                ctx.result.modes = names
            end
        end,
    },
}
local function Moded()
    --option steps interleaved, with a step for every mode at the end.
    return {
        name = "Moded",
        modes = { "Fire", "Ice" },
        behaviors = {
            Damage.new{ roll = "1", mode = 1 },
            Damage.new{ roll = "2", mode = 2 },
            Heal.new{ roll = "3", mode = 1 },
            Heal.new{ roll = "4" },
        },
    }
end
local moded = Moded()
model = BERecordCache.Open(moded, host)
local chooser = model.blocks[1]
Check(chooser.block == "t.choose" and #chooser.bodies.options == 2 and #chooser.bodies.options[1].bodies.steps == 2
    and #chooser.bodies.options[2].bodies.steps == 1 and model.blocks[2].block == "t.heal", "a split block gathers each option's steps")
Check(BERecordCache.SavesUnchanged(model, moded, host), "an untouched split block saves back identical, interleaved order and all")
Check(BERecordCache.SavesUnchanged(BERecordCache.Open(moded, host), moded, host, true), "a forced save of a split block is identical")

model = BERecordCache.Open(moded, host)
model.blocks[1].bodies.options[2].values.name = "Frost"
saved = BERecordCache.Save(model, moded, host)
Check(Equal(saved.modes, { "Fire", "Frost" }) and Equal(saved.behaviors, moded.behaviors), "renaming an option writes the record field only")

model = BERecordCache.Open(moded, host)
local fireSteps = model.blocks[1].bodies.options[1].bodies.steps
fireSteps[1], fireSteps[2] = fireSteps[2], fireSteps[1]
saved = BERecordCache.Save(model, moded, host)
Check(saved.behaviors[1].roll == "3" and saved.behaviors[2].roll == "1", "steps reordered inside an option keep the author's order")

model = BERecordCache.Open(moded, host)
local step = table.remove(model.blocks[1].bodies.options[1].bodies.steps, 1)
table.insert(model.blocks[1].bodies.options[2].bodies.steps, step)
saved = BERecordCache.Save(model, moded, host)
local movedStep = nil
for _, behavior in ipairs(saved.behaviors) do
    if behavior.roll == "1" then
        movedStep = behavior
    end
end
Check(movedStep ~= nil and movedStep.mode == 2, "a step moved to another option is tagged with that option")

model = BERecordCache.Open(moded, host)
local newStep = { block = "t.damage", values = { amount = "9", damageType = "" } }
table.insert(model.blocks[1].bodies.options[2].bodies.steps, newStep)
saved = BERecordCache.Save(model, moded, host)
Check(#saved.behaviors == 5 and saved.behaviors[4].roll == "9" and saved.behaviors[4].mode == 2 and saved.behaviors[5].roll == "4",
    "a new step in an option is tagged and saved where the block is")

model = BERecordCache.Open(moded, host)
table.insert(model.blocks[1].bodies.options[1].bodies.steps, 1, { block = "t.heal", values = { amount = "8" } })
saved = BERecordCache.Save(model, moded, host)
Check(saved.behaviors[1].roll == "8" and saved.behaviors[1].mode == 1 and saved.behaviors[2].roll == "1",
    "a new step before saved ones in an option keeps the author's order")

model = BERecordCache.Open(moded, host)
table.remove(model.blocks, 1)
saved = BERecordCache.Save(model, moded, host)
Check(rawget(saved, "modes") == nil and #saved.behaviors == 1, "taking the block out drops the options and their steps")

--a host's other list (an ability's requirements): read into its own model
--field, written only when the author changed it.
Block.RegisterBlock{
    id = "t.req", family = "logic", group = "logic", label = "Requirement",
    sentence = { "Only if ", { slot = "test" } }, slots = { test = { kind = "formula", default = "" } }, fits = { "requirement" },
}
local listHost = {
    id = "t.listhost", claims = function() return true end,
    fields = { name = NameField() },
    stepsField = "behaviors",
    advancedBlock = "t.advanced",
    lists = {
        requirements = {
            read = function(rec)
                local result = {}
                for _, filter in ipairs(rawget(rec, "filters") or {}) do
                    result[#result + 1] = { block = "t.req", values = { test = filter.formula }, saved = Copy(filter) }
                end
                return result
            end,
            write = function(result, instances)
                local list = {}
                for i, instance in ipairs(instances) do
                    list[i] = Copy(instance.saved or {})
                    list[i].formula = instance.values.test
                end
                result.filters = list
            end,
        },
    },
}
--the model's list field, which BERecordModel does not declare (it is the host's).
local function Reqs(m)
    return rawget(m, "requirements")
end
local filtered = { name = "Filtered", filters = { { formula = "Size <= 1", extra = true }, { formula = "Winded" } }, behaviors = { Heal.new{ roll = "1" } } }
model = BERecordCache.Open(filtered, listHost)
Check(#Reqs(model) == 2 and Reqs(model)[1].values.test == "Size <= 1" and model.lists[1] == "requirements",
    "a host's other list opens into its own model field")
Check(BERecordCache.SavesUnchanged(model, filtered, listHost), "an untouched list saves back identical")
Check(BERecordCache.SavesUnchanged(BERecordCache.Open(filtered, listHost), filtered, listHost, true), "a forced save of a list is identical")
Reqs(model)[2].values.test = "Prone"
saved = BERecordCache.Save(model, filtered, listHost)
Check(saved.filters[2].formula == "Prone" and saved.filters[1].extra == true and Equal(saved.behaviors, filtered.behaviors),
    "editing a list block writes the list and keeps what it does not show")
model = BERecordCache.Open(filtered, listHost)
table.remove(Reqs(model))
saved = BERecordCache.Save(model, filtered, listHost)
Check(#saved.filters == 1 and saved.filters[1].formula == "Size <= 1", "taking out the last block of a list is saved")
model = BERecordCache.Open({ name = "None", behaviors = {} }, listHost)
Reqs(model)[#Reqs(model) + 1] = { block = "t.req", values = { test = "Winded" } }
saved = BERecordCache.Save(model, { name = "None", behaviors = {} }, listHost)
Check(saved.filters ~= nil and saved.filters[1].formula == "Winded", "a block added to an empty list is saved")

local fresh = Block.Instantiate("t.choose") --[[@as BlockInstance]]
Check(#fresh.bodies.options == 2, "a new split block starts with the options its initial gives")
model = BERecordCache.Open(record, host)
table.insert(model.blocks, fresh)
fresh.bodies.options[1].bodies.steps[1] = { block = "t.choose", values = {}, bodies = { options = {} } }
Check(BERecordCache.CountUnsaveable(model.blocks) == 1, "a split block inside another's options is counted as unsaveable")
print("block_recordcache_test: " .. g_checks .. " checks passed")
