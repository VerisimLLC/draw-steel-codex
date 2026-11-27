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
for _, path in ipairs({ "DMHub Utils/Block.lua", "DMHub Utils/BlockBehaviors.lua", "Block Editor/RecordCache.lua" }) do
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
print("block_recordcache_test: " .. g_checks .. " checks passed")
