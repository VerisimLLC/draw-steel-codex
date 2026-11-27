--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/block_editor_test.lua
--Checks the block editor's two gui-free pieces without the app: the Block
--registries (DMHub Utils/Block.lua, with the stubs) and the editing state's
--undo, redo and upload timing (Block Editor/State.lua), and the block colour
--rules (Block Editor/Styles.lua).

local g_errors = {}
local g_now = 0
local g_failUpload = false

--Stand-ins for what the files under test call, set with rawset so the type
--checker does not take them for second definitions of the real globals.
rawset(_G, "dmhub", {
    GetModLoading = function() return {} end,
    Error = function(msg) g_errors[#g_errors + 1] = msg end,
    Time = function() return g_now end,
})

--- The codex's DeepCopy, for the plain tables the state holds.
local function Copy(t)
    if type(t) ~= "table" then
        return t
    end
    local result = {}
    for k, v in pairs(t) do
        result[k] = Copy(v)
    end
    return result
end
rawset(_G, "DeepCopy", Copy)

local g_checks = 0
local function Check(condition, what)
    g_checks = g_checks + 1
    if not condition then
        error("FAILED: " .. what, 2)
    end
end

dofile("DMHub Utils/Block.lua")
dofile("DMHub Utils/BlockStubs.lua")
Check(#g_errors == 0, "the shared groups and the stubs register without a report: " .. tostring(g_errors[1]))

----------------------------------------------------------------------------
--Registries

local groups = Block.All("group")
Check(#groups >= 20, "the shared colour groups are registered")
for i = 2, #groups do
    Check((groups[i - 1].order or 1000) <= (groups[i].order or 1000), "groups come back in order")
end
for _, group in ipairs(groups) do
    Check(string.match(group.color, "^#%x%x%x%x%x%x$") ~= nil, "group " .. group.id .. " has a literal hex colour")
end

for _, decl in ipairs(Block.All("block")) do
    Check(decl.stub == true, "block " .. decl.id .. " is marked as a stub")
    Check(Block.GetGroup(decl.group) ~= nil, "block " .. decl.id .. " names a registered group")
    Check(#Block.SentenceText(decl) > 0, "block " .. decl.id .. " has a sentence")
end

--registering an id again replaces the entry and keeps its place.
local firstId = groups[1].id
local before = #groups
Block.RegisterGroup{ id = firstId, text = "Replaced", color = "#000000", order = groups[1].order }
Check(#Block.All("group") == before, "re-registering a group does not add one")
Check(Block.GetGroup(firstId).text == "Replaced", "re-registering a group replaces it")
Check(Block.All("group")[1].id == firstId, "a replaced group keeps its place")

--a bad registration is reported and skipped, never thrown.
g_errors = {}
--deliberately missing its text and colour.
---@diagnostic disable-next-line: missing-fields
Block.RegisterGroup{ id = "bad" }
Block.RegisterBlock{ id = "bad", family = "step", group = "harm", label = "Bad", sentence = { { slot = "missing" } } }
Check(#g_errors == 2, "bad registrations are reported")
Check(Block.GetGroup("bad") == nil and Block.GetBlock("bad") == nil, "bad registrations are skipped")

--lists are built when asked for, so a later registration is included.
Block.RegisterBlock{ id = "test.late", family = "step", group = "harm", label = "Late", sentence = { "Late ", { slot = "n" } }, slots = { n = { kind = "number", default = 4 } } }
Check(Block.GetBlock("test.late") ~= nil, "a later registration is found")
local found = false
for _, decl in ipairs(Block.All("block")) do
    found = found or decl.id == "test.late"
end
Check(found, "a later registration is in the list")

--a source's entries are gathered with the direct ones.
Block.RegisterSource{ id = "test.source", kind = "block", gather = function()
    return { { id = "test.sourced", family = "step", group = "harm", label = "Sourced", sentence = { "Sourced" } } }
end }
Check(Block.GetBlock("test.sourced") ~= nil, "a source's block is found")

--sentences: slot values read as words.
local instance = Block.Instantiate("test.late")
Check(instance ~= nil and instance.values.n == 4, "a new instance takes the slot defaults")
local late = assert(Block.GetBlock("test.late"))
Check(Block.SentenceText(late, { n = 7 }) == "Late 7", "a slot value shows in the sentence")
local runs = Block.Sentence(late)
Check(#runs == 2 and runs[1].slot == nil and runs[2].slot == "n", "the sentence's runs mark their slots")

--hosts: the first that claims a record edits it.
Block.RegisterHost{ id = "test.host", tableName = "tests", claims = function(record) return record.kind == "test" end }
Check(Block.FindHost({ kind = "test" }).id == "test.host", "a host claims its record")
Check(Block.FindHost({ kind = "other" }) == nil, "no host claims another record")

--styled text parts and bodies.
local roll = Block.Instantiate("stub.powerroll")
Check(roll ~= nil and roll.bodies ~= nil and roll.bodies.tier1 ~= nil and #roll.bodies.tier1 == 0, "a block with bodies starts with each body empty")
local rollRuns = Block.Sentence(assert(Block.GetBlock("stub.powerroll")))
Check(rollRuns[1].bold == true and rollRuns[1].text == "Power roll", "a styled text part keeps its look")
local condRuns = Block.Sentence(assert(Block.GetBlock("stub.condition")))
Check(string.sub(condRuns[1].text, 1, 1) == "T", "a capitalised sentence starts with a capital")
local chips = assert(Block.GetBlock("stub.text"))
Check(chips.shelf == false and chips.tag == "Text", "a card-text block stays off the shelf")

--the stub ability host: its page, card and checks come from the model.
local abilityHost = Block.Get("host", "stub.ability") --[[@as BlockHost]]
Check(abilityHost ~= nil and abilityHost.demo ~= nil and #abilityHost.sections == 4, "the stub ability host declares its page and demo")
local card = abilityHost.card(abilityHost.demo)
Check(card.title == "Out of the Way! (3 Ferocity)" and #card.tiers == 3, "the card is built from the demo record")
Check(#abilityHost.checks(abilityHost.demo) == 2, "the checks are built from the demo record")

----------------------------------------------------------------------------
--State: undo, redo and uploads

rawset(_G, "BlockEditor", { UNDO_LIMIT = 100, UPLOAD_DELAY = 2 })
dofile("Block Editor/State.lua")

local uploads = {}
local host = {
    id = "test",
    canWrite = function() return true end,
    upload = function(record, model)
        if g_failUpload then
            return false
        end
        uploads[#uploads + 1] = #model.blocks
    end,
}
local state = BEState.CreateNew(host)
state:AddRecord({ id = "a", name = "A", blocks = {} })
state:AddRecord({ id = "b", name = "B", blocks = {} })

local function Add(recordIds)
    return state:Change("Add", function(s)
        for _, id in ipairs(recordIds or { "a" }) do
            local blocks = s:Model(id).blocks
            blocks[#blocks + 1] = { block = "test.late", values = {} }
        end
    end, recordIds)
end

Check(not state:CanUndo() and not state:IsDirty(), "a new state is clean")
Add()
Add()
Check(#state:Model("a").blocks == 2 and #state.undoStack == 2, "each action is one undo step")
Check(state:IsDirty(), "a change marks the record dirty")

state:Undo()
Check(#state:Model("a").blocks == 1 and state:CanRedo(), "undo restores the model")
state:Redo()
Check(#state:Model("a").blocks == 2 and not state:CanRedo(), "redo puts it back")
state:Undo()
Add()
Check(not state:CanRedo(), "a new change clears redo")

--one step can touch two records, and undo restores both.
Add({ "a", "b" })
Check(#state:Model("b").blocks == 1, "one action changed the second record")
local changed = state:Undo()
Check(#state:Model("b").blocks == 0 and #changed == 2, "undo restores every record the step touched")

--a failing action changes nothing and adds no step.
local steps = #state.undoStack
g_errors = {}
local result = state:Change("Break", function(s)
    s:Model("a").blocks = {}
    error("boom")
end)
Check(result == nil and #state.undoStack == steps and #state:Model("a").blocks == 2 and #g_errors == 1, "a failing action is rolled back")

--the stack keeps the last 100 steps.
for _ = 1, 120 do
    Add()
end
Check(#state.undoStack == 100, "the undo stack is limited to 100")

--uploads: two seconds after the last change, or at once when forced.
uploads = {}
state.dirty = {}
Add()
g_now = g_now + 1
Check(state:Think() == true and #uploads == 0, "nothing uploads before the delay")
g_now = g_now + 1.5
Check(state:Think() == false and #uploads == 1, "the record uploads after the delay, and the timer can stop")
Add()
Check(state:UploadDirty(true) == 1 and #uploads == 2 and not state:IsDirty(), "a forced upload sends at once")
state:Undo()
Check(state:IsDirty(), "undo marks the record dirty, so the earlier state uploads too")
g_failUpload = true
Check(state:UploadDirty(true) == 0 and state:IsDirty() and state.failedUploads == 1, "a failed upload keeps the record dirty")
g_failUpload = false
g_now = g_now + 3
Check(state:Think() == false and #uploads == 3, "the failed record is sent again after the delay")

--nested lists: every placed block has a uid, and a body is reached by its owner.
local nested = { id = "n", name = "N", blocks = { Block.Instantiate("stub.powerroll") } }
state:AddRecord(nested)
local ownerUid = nested.blocks[1].uid
Check(type(ownerUid) == "string", "opening a record gives its blocks uids")
local tierRef = { field = "blocks", owner = ownerUid, body = "tier1" }
Check(BEState.Insert(nested, tierRef, 1, Block.Instantiate("stub.tierdamage") --[[@as BlockInstance]]), "a block goes into a body")
local placed = nested.blocks[1].bodies.tier1[1]
Check(placed.uid ~= nil and BEState.FindInstance(nested, placed.uid) == placed, "a nested block is found by uid")
Check(BEState.Insert(nested, { field = "blocks" }, 2, Block.Instantiate("stub.damage") --[[@as BlockInstance]]), "a block goes into the top list")
Check(BEState.Move(nested, nested.blocks[2].uid, -1) and nested.blocks[1].block == "stub.damage", "a block moves up its list")
Check(BEState.Remove(nested, placed.uid) == placed and #nested.blocks[2].bodies.tier1 == 0, "a nested block is removed")

----------------------------------------------------------------------------
--Styles: one fixed colour rule and one hover rule per group

dofile("Block Editor/Styles.lua")
Check(BEStyles._lighten("#000000", 0.5) == "#808080" and BEStyles._lighten("#ffffff", 0.5) == "#ffffff", "hover colours move towards white")
local rest, hover = 0, 0
for _, rule in ipairs(BEStyles.GetStyles()) do
    local selectors = rule.selectors
    if selectors[1] == "beBlock" and selectors[2] ~= nil and string.find(selectors[2], "^beGroup%-") ~= nil then
        Check(type(rule.bgcolor) == "string" and string.find(rule.bgcolor, "@", 1, true) == nil, "a block colour is literal, never a theme token")
        if selectors[3] == "hover" then
            hover = hover + 1
        else
            rest = rest + 1
        end
    end
end
Check(rest == #Block.All("group") and hover == rest, "every group has a colour rule and a hover rule")

--real stats from a source replace the stub stats in the list; the stubs stay reachable by id.
Check(#Block.All("stat") == 5, "the stub stats are listed while nothing real is declared")
Block.RegisterSource{
    id = "test.characteristics",
    kind = "stat",
    gather = function()
        return { { id = "mgt", words = "Might", kind = "characteristic", order = 10 }, { id = "might", words = "Might (real)", kind = "characteristic", order = 20 } }
    end,
}
Block.Gather()
local stats = Block.All("stat")
Check(#stats == 2 and stats[1].id == "mgt" and not stats[2].stub, "real stats replace the stubs, and a real entry beats a stub with its id")
Check(Block.Get("stat", "agility") ~= nil, "a stub stat is still found by id")

print(string.format("block_editor_test: %d checks passed", g_checks))
