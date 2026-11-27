local mod = dmhub.GetModLoading()

--[[
 Stub registrations for the block editor's UI (build phases 0 and 1).

 Every entry here is marked `stub = true`: it has a sentence and slots so the
 shelf, the stack and the slot controls have something to draw, but it reads
 and writes no record. In phase 2 each is replaced by a real declaration
 beside its game type (registering the same id replaces the stub), and this
 file is removed. Nothing outside the block editor should read these.

 The blocks, the ability host and its demo record follow the mockup
 docs/block-editor/lua-preview/ability.html: the Fury's "Out of the Way!".
]]

----------------------------------------------------------------------------
-- Stats and tests, for the "stat" and "test" slots below.
----------------------------------------------------------------------------

Block.RegisterStat{ id = "might", words = "Might", kind = "characteristic", order = 10, stub = true }
Block.RegisterStat{ id = "agility", words = "Agility", kind = "characteristic", order = 20, stub = true }
Block.RegisterStat{ id = "reason", words = "Reason", kind = "characteristic", order = 30, stub = true }
Block.RegisterStat{ id = "intuition", words = "Intuition", kind = "characteristic", order = 40, stub = true }
Block.RegisterStat{ id = "presence", words = "Presence", kind = "characteristic", order = 50, stub = true }

Block.RegisterTest{
    id = "targetwinded",
    prose = "the target is winded",
    toScript = function(values) return "Target.Winded" end,
    order = 10,
    stub = true,
}
Block.RegisterTest{
    id = "targetminion",
    prose = "the target is a minion",
    toScript = function(values) return "Target.Minion" end,
    order = 20,
    stub = true,
}
Block.RegisterTest{
    id = "winded",
    prose = "you are winded",
    toScript = function(values) return "Winded" end,
    order = 30,
    stub = true,
}

----------------------------------------------------------------------------
-- Shared slot options.
----------------------------------------------------------------------------

local WHO = {
    { id = "self", text = "you" },
    { id = "target", text = "the target" },
    { id = "eachtarget", text = "each target" },
    { id = "ally", text = "an ally" },
}

local CONDITIONS = {
    { id = "bleeding", text = "bleeding" },
    { id = "dazed", text = "dazed" },
    { id = "frightened", text = "frightened" },
    { id = "grabbed", text = "grabbed" },
    { id = "prone", text = "prone" },
    { id = "restrained", text = "restrained" },
    { id = "slowed", text = "slowed" },
    { id = "taunted", text = "taunted" },
    { id = "weakened", text = "weakened" },
}

--The suggestions a formula word offers; the author can also type one.
local DAMAGE_FORMULAS = {
    { id = "3 + M", text = "3 + M" },
    { id = "2 + M", text = "2 + M" },
}

----------------------------------------------------------------------------
-- Steps: blocks that go in an ability's list of steps ("Common" on the shelf).
----------------------------------------------------------------------------

Block.RegisterBlock{
    id = "stub.powerroll",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "rolls",
    label = "Power roll",
    desc = "Roll 2d10 plus a characteristic; each tier holds its own steps.",
    sentence = { { text = "Power roll", bold = true }, " + ", { slot = "stat" } },
    slots = { stat = { kind = "stat", default = "might" } },
    bodies = {
        { id = "tier1", fits = "tier", label = "11 or lower", sublabel = "tier 1" },
        { id = "tier2", fits = "tier", label = "12 to 16", sublabel = "tier 2" },
        { id = "tier3", fits = "tier", label = "17 or higher", sublabel = "tier 3" },
    },
    fits = { "step" },
    order = 10,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.modifyroll",
    family = "step",
    group = "rolls",
    label = "Modify power roll",
    desc = "Gives this ability's power rolls an edge or a bane.",
    sentence = { "Power rolls for this ability have ", { slot = "edge" }, "." },
    slots = {
        edge = {
            kind = "choice",
            default = "edge",
            options = {
                { id = "edge", text = "an edge" },
                { id = "doubleedge", text = "a double edge" },
                { id = "bane", text = "a bane" },
                { id = "doublebane", text = "a double bane" },
            },
        },
    },
    fits = { "step" },
    order = 20,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.damage",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "harm",
    label = "Deal damage",
    desc = "Deals damage to a creature.",
    sentence = { "Deal ", { slot = "amount" }, " damage to ", { slot = "who" }, "." },
    slots = {
        amount = { kind = "formula", style = "formula", default = "2", options = DAMAGE_FORMULAS },
        who = { kind = "choice", default = "target", options = WHO },
    },
    fits = { "step" },
    order = 30,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.condition",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "conditions",
    label = "Apply condition",
    desc = "Puts a condition on a creature.",
    sentence = { { slot = "who" }, " is ", { slot = "condition" }, " (save ends)." },
    slots = {
        who = { kind = "choice", default = "target", options = WHO },
        condition = { kind = "choice", default = "slowed", options = CONDITIONS },
    },
    capitalize = true,
    fits = { "step" },
    order = 40,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.newability",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "abilities",
    label = "Use a new ability",
    desc = "Someone uses another ability, with its own steps inside.",
    sentence = { { text = "Then", bold = true }, " ", { slot = "who" }, " use a new ability, asking ", { slot = "prompt" }, ":" },
    slots = {
        who = { kind = "choice", default = "self", options = WHO },
        prompt = { kind = "text", default = "\"Choose a square\"" },
    },
    bodies = { { id = "steps", fits = "step" } },
    fits = { "step" },
    order = 50,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.effect",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "effects",
    label = "Apply an effect",
    desc = "Puts an ongoing effect on a creature.",
    sentence = { "Apply ", { slot = "effect" }, " until ", { slot = "ends" }, "." },
    slots = {
        effect = { kind = "choice", default = "effect", options = { { id = "effect", text = "an effect" } } },
        ends = {
            kind = "choice",
            default = "encounter",
            options = {
                { id = "encounter", text = "the end of the encounter" },
                { id = "nextturn", text = "the end of your next turn" },
                { id = "save", text = "save ends" },
            },
        },
    },
    fits = { "step" },
    order = 60,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.onlyif",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "logic",
    group = "logic",
    label = "Logic",
    desc = "The steps inside only happen when a test passes.",
    sentence = { { text = "Only if", bold = true }, " ", { slot = "test" }, ":" },
    slots = { test = { kind = "test", default = "targetwinded" } },
    bodies = { { id = "steps", fits = "step" } },
    fits = { "step" },
    order = 70,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.move",
    family = "step",
    group = "movement",
    label = "Move a creature",
    desc = "A creature moves, shifts or teleports.",
    sentence = { "You ", { slot = "how" }, " into ", { slot = "where" }, ", up to ", { slot = "distance" }, "." },
    slots = {
        how = {
            kind = "choice",
            default = "move",
            options = {
                { id = "move", text = "move" },
                { id = "shift", text = "shift" },
                { id = "teleport", text = "teleport" },
                { id = "jump", text = "jump" },
            },
        },
        where = {
            kind = "choice",
            default = "choice",
            options = {
                { id = "left", text = "a square the target left" },
                { id = "choice", text = "a square of your choice" },
                { id = "adjacent", text = "adjacent to the target" },
            },
        },
        distance = { kind = "formula", style = "formula", default = "your speed", options = { { id = "your speed", text = "your speed" } } },
    },
    fits = { "step" },
    order = 80,
    stub = true,
}

--Card text the game does not apply. It only arrives by reading a record.
Block.RegisterBlock{
    id = "stub.text",
    family = "step",
    group = "advanced",
    label = "Card text",
    desc = "Text on the card that the game does not apply.",
    sentence = { { slot = "text" } },
    slots = { text = { kind = "text", default = "Text the game does not apply." } },
    tag = "Text",
    italic = true,
    shelf = false,
    fits = { "step" },
    order = 90,
    stub = true,
}

----------------------------------------------------------------------------
-- Tier steps: blocks that only go inside a power roll's tier.
----------------------------------------------------------------------------

Block.RegisterBlock{
    id = "stub.tierdamage",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "harm",
    label = "Damage",
    desc = "Damage dealt by a power roll tier. Only goes inside a tier.",
    sentence = { { slot = "amount" }, " damage" },
    slots = { amount = { kind = "formula", style = "formula", default = "2 + M", options = DAMAGE_FORMULAS } },
    fits = { "tier" },
    order = 110,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.tierpush",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "conditions",
    label = "Push, pull or slide",
    desc = "Forced movement from a power roll tier. Only goes inside a tier.",
    sentence = { { slot = "how" }, " ", { slot = "distance" } },
    slots = {
        how = {
            kind = "choice",
            default = "push",
            options = {
                { id = "push", text = "push" },
                { id = "pull", text = "pull" },
                { id = "slide", text = "slide" },
                { id = "vpush", text = "vertical push" },
                { id = "vslide", text = "vertical slide" },
            },
        },
        distance = { kind = "number", default = 1 },
    },
    fits = { "tier" },
    order = 120,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.tiercondition",
    --a real block replaces it on the shelf; the demo record still uses this one.
    shelf = false,
    family = "step",
    group = "conditions",
    label = "Condition",
    desc = "A condition from a power roll tier. Only goes inside a tier.",
    sentence = { { slot = "condition" }, " (save ends)" },
    slots = { condition = { kind = "choice", default = "bleeding", options = CONDITIONS } },
    fits = { "tier" },
    order = 130,
    stub = true,
}

----------------------------------------------------------------------------
-- The ability host: the page, the card and the checks for an ability.
----------------------------------------------------------------------------

local CATEGORIES = {
    { id = "signature", text = "signature ability" },
    { id = "heroic", text = "heroic ability" },
    { id = "freestrike", text = "free strike" },
    { id = "triggered", text = "triggered action" },
}

local ACTIONS = {
    { id = "main", text = "main action" },
    { id = "maneuver", text = "maneuver" },
    { id = "move", text = "move action" },
    { id = "freemaneuver", text = "free maneuver" },
    { id = "triggered", text = "triggered action" },
    { id = "none", text = "no action" },
}

local RESOURCES = {
    { id = "ferocity", text = "Ferocity" },
    { id = "malice", text = "Malice" },
    { id = "recoveries", text = "Recoveries" },
    { id = "nothing", text = "nothing" },
}

local KEYWORDS = {
    { id = "melee", text = "Melee" },
    { id = "strike", text = "Strike" },
    { id = "weapon", text = "Weapon" },
    { id = "area", text = "Area" },
    { id = "charge", text = "Charge" },
    { id = "magic", text = "Magic" },
    { id = "psionic", text = "Psionic" },
    { id = "ranged", text = "Ranged" },
}

local DISTANCES = {
    { id = "melee", text = "Melee" },
    { id = "ranged", text = "Ranged" },
    { id = "meleeranged", text = "Melee or ranged" },
    { id = "burst", text = "Burst" },
    { id = "cube", text = "Cube" },
    { id = "line", text = "Line" },
    { id = "self", text = "Self" },
}

local TARGETS = {
    { id = "creature", text = "creature" },
    { id = "enemy", text = "enemy" },
    { id = "ally", text = "ally" },
    { id = "creatureobject", text = "creature or object" },
    { id = "self", text = "self" },
}

--The header rows' slots, shared by the page and the card.
local HEADER_SLOTS = {
    name = { kind = "text", default = "New ability" },
    category = { kind = "choice", default = "signature", options = CATEGORIES },
    action = { kind = "choice", default = "main", options = ACTIONS },
    cost = { kind = "number", default = 0 },
    resource = { kind = "choice", default = "nothing", options = RESOURCES },
    keywords = { kind = "many", default = {}, options = KEYWORDS },
    flavor = { kind = "text", default = "" },
    distance = { kind = "choice", default = "melee", options = DISTANCES },
    range = { kind = "number", default = 1 },
    count = { kind = "number", default = 1 },
    target = { kind = "choice", default = "creature", options = TARGETS },
}

--- The text of a header value, as its row would show it.
--- @param model table
--- @param slotId string
--- @return string
local function HeaderText(model, slotId)
    local values = model.values or {}
    local value = values[slotId]
    if value == nil then
        value = HEADER_SLOTS[slotId].default
    end
    return Block.SlotText({ id = "header", sentence = {}, slots = HEADER_SLOTS } --[[@as BlockDecl]], slotId, value)
end

--- The first block of a kind in a list, or nil.
--- @param list BlockInstance[]
--- @param blockId string
--- @return BlockInstance|nil
local function FindBlock(list, blockId)
    for _, instance in ipairs(list or {}) do
        if instance.block == blockId then
            return instance
        end
    end
    return nil
end

--- A tier's blocks as card text: each block's sentence, joined by "; ", with
--- a lone characteristic letter ("M") turned into a chip.
--- @param list BlockInstance[]
--- @return (string|{chip: string})[]
local function TierParts(list)
    local texts = {}
    for _, instance in ipairs(list or {}) do
        local decl = Block.GetBlock(instance.block)
        if decl ~= nil then
            texts[#texts + 1] = Block.SentenceText(decl, instance.values)
        end
    end
    local text = table.concat(texts, "; ")
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

Block.RegisterHost{
    id = "stub.ability",
    tableName = "stub",
    title = "Edit Ability",
    --a stub never claims a real record; the editor opens it by id for its demo.
    claims = function(record) return false end,
    toolbar = {
        label = "Belongs to",
        field = "classid",
        options = {
            { id = "none", text = "no class" },
            { id = "fury", text = "Fury" },
            { id = "censor", text = "Censor" },
            { id = "conduit", text = "Conduit" },
            { id = "shadow", text = "Shadow" },
            { id = "tactician", text = "Tactician" },
        },
    },
    kindChoice = {
        label = "This is",
        field = "kind",
        options = {
            { id = "ability", text = "an ability" },
            { id = "trigger", text = "a triggered ability" },
        },
    },
    sections = {
        {
            id = "what",
            title = "What it is",
            rows = {
                { id = "name", sentence = { { slot = "name" }, " is a ", { slot = "category" }, " that takes a ", { slot = "action" } }, slots = HEADER_SLOTS },
                { id = "cost", sentence = { "which costs ", { slot = "cost" }, " ", { slot = "resource" } }, slots = HEADER_SLOTS },
                { id = "keywords", sentence = { "and has the keywords ", { slot = "keywords" } }, slots = HEADER_SLOTS },
                { id = "flavor", sentence = { { text = "Flavor:", style = "aside" }, " ", { slot = "flavor" } }, slots = HEADER_SLOTS },
            },
        },
        {
            id = "who",
            title = "Who it targets",
            rows = {
                { id = "distance", sentence = { "Distance: ", { slot = "distance" }, " ", { slot = "range" } }, slots = HEADER_SLOTS },
                { id = "target", sentence = { "Target: ", { slot = "count" }, " ", { slot = "target" } }, slots = HEADER_SLOTS },
            },
            summary = function(model)
                local count = tonumber((model.values or {}).count) or 1
                local target = HeaderText(model, "target")
                local range = HeaderText(model, "range")
                local article = string.find(target, "^[aeiou]") ~= nil and "An " or "A "
                local who = count == 1 and (article .. target) or (tostring(count) .. " " .. target .. "s")
                return string.format("%s within %s square%s of you.", who, range, range == "1" and "" or "s")
            end,
        },
        { id = "req", title = "Can only be used when", optional = true, addText = "add a requirement" },
        { id = "used", title = "When it's used", stack = "blocks", fits = "step", stackAddText = "add step" },
    },
    shelfSections = {
        { title = "Common", fits = "step" },
        { title = "Inside a power roll tier", fits = "tier" },
    },
    templates = {
        label = "Start from:",
        items = { "Paste ability text...", "Strike", "Ranged strike", "Area attack", "Heal an ally" },
    },
    card = function(model)
        local values = model.values or {}
        local cost = tonumber(values.cost) or 0
        local title = HeaderText(model, "name")
        if cost > 0 then
            title = string.format("%s (%d %s)", title, cost, HeaderText(model, "resource"))
        end
        local action = HeaderText(model, "action")
        --- @type BlockCard
        local card = {
            title = title,
            flavor = values.flavor,
            rows = {
                { left = HeaderText(model, "keywords"), right = string.upper(string.sub(action, 1, 1)) .. string.sub(action, 2), bold = true },
                {
                    left = HeaderText(model, "distance") .. " " .. HeaderText(model, "range"),
                    leftIcon = "triangle",
                    right = (tonumber(values.count) or 1) == 1 and ("One " .. HeaderText(model, "target")) or (HeaderText(model, "count") .. " " .. HeaderText(model, "target") .. "s"),
                    rightIcon = "target",
                },
            },
        }
        local roll = FindBlock(model.blocks, "stub.powerroll")
        if roll ~= nil then
            local stat = Block.Get("stat", tostring(roll.values.stat)) --[[@as BlockStat|nil]]
            card.roll = string.format("Power Roll + %s:", stat ~= nil and stat.words or "?")
            card.tiers = {}
            for i, tierId in ipairs({ "tier1", "tier2", "tier3" }) do
                card.tiers[i] = { parts = TierParts((roll.bodies or {})[tierId]) }
            end
        end
        if type(values.effect) == "string" and values.effect ~= "" then
            card.effect = { label = "Effect:", text = values.effect }
        end
        return card
    end,
    checks = function(model)
        --- @type BlockCheck[]
        local result = {}
        if FindBlock(model.blocks, "stub.text") ~= nil then
            result[#result + 1] = { severity = "warning", text = "One sentence is card text only: the game won't deal the opportunity-attack damage back." }
        end
        result[#result + 1] = { severity = "success", text = "Saves back unchanged." }
        return result
    end,
    demo = {
        id = "demo.outoftheway",
        name = "Out of the Way!",
        values = {
            classid = "fury",
            kind = "ability",
            name = "Out of the Way!",
            category = "heroic",
            action = "main",
            cost = 3,
            resource = "ferocity",
            keywords = { "melee", "strike", "weapon" },
            flavor = "Your enemies will clear your path, whether they want to or not.",
            distance = "melee",
            range = 1,
            count = 1,
            target = "creature",
            effect = "When you slide the target, you can move into any square they leave. If you take damage from an opportunity attack by moving this way, the target takes the same damage.",
        },
        blocks = {
            {
                block = "stub.powerroll",
                values = { stat = "might" },
                bodies = {
                    tier1 = {
                        { block = "stub.tierdamage", values = { amount = "3 + M" } },
                        { block = "stub.tierpush", values = { how = "slide", distance = 2 } },
                    },
                    tier2 = {
                        { block = "stub.tierdamage", values = { amount = "5 + M" } },
                        { block = "stub.tierpush", values = { how = "slide", distance = 3 } },
                    },
                    tier3 = {
                        { block = "stub.tierdamage", values = { amount = "8 + M" } },
                        { block = "stub.tierpush", values = { how = "slide", distance = 5 } },
                    },
                },
            },
            {
                block = "stub.newability",
                values = { who = "self", prompt = "\"Move into a square that the target was pushed through\"" },
                bodies = {
                    steps = {
                        { block = "stub.move", values = { how = "move", where = "left", distance = "your speed" } },
                    },
                },
            },
            {
                block = "stub.text",
                values = { text = "If you take damage from an opportunity attack by moving this way, the target takes the same damage." },
            },
        },
    },
    order = 10,
    stub = true,
}
