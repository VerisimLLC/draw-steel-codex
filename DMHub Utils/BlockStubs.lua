local mod = dmhub.GetModLoading()

--[[
 Stub registrations for the block editor's UI (build phases 0 and 1).

 Every entry here is marked `stub = true`: it has a sentence and slots so the
 shelf, the stack and the slot controls have something to draw, but it reads
 and writes no record. In phase 2 each is replaced by a real declaration
 beside its game type (registering the same id replaces the stub), and this
 file is removed. Nothing outside the block editor should read these.
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
    id = "winded",
    prose = "you are winded",
    toScript = function(values) return "Winded" end,
    order = 10,
    stub = true,
}
Block.RegisterTest{
    id = "targetadjacent",
    prose = "the target is next to you",
    toScript = function(values) return "Distance <= 1" end,
    order = 20,
    stub = true,
}

----------------------------------------------------------------------------
-- Steps: blocks that go in an ability's list of steps.
----------------------------------------------------------------------------

local WHO = {
    { id = "target", text = "the target" },
    { id = "self", text = "you" },
    { id = "allies", text = "each ally" },
}

Block.RegisterBlock{
    id = "stub.powerroll",
    family = "step",
    group = "rolls",
    label = "Power roll",
    desc = "Roll 2d10 plus a characteristic; each tier holds its own steps.",
    sentence = { "Power roll + ", { slot = "stat" } },
    slots = { stat = { kind = "stat", default = "might" } },
    fits = { "step" },
    order = 10,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.damage",
    family = "step",
    group = "harm",
    label = "Deal damage",
    desc = "Deals damage to a creature.",
    sentence = { "Deal ", { slot = "amount" }, " damage to ", { slot = "who" }, "." },
    slots = {
        amount = { kind = "number", default = 2 },
        who = { kind = "choice", default = "target", options = WHO },
    },
    fits = { "step" },
    order = 20,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.condition",
    family = "step",
    group = "conditions",
    label = "Apply condition",
    desc = "Puts a condition on a creature.",
    sentence = { { slot = "who" }, " is ", { slot = "condition" }, " (", { slot = "ends" }, ")." },
    slots = {
        who = { kind = "choice", default = "target", options = WHO },
        condition = {
            kind = "choice",
            default = "slowed",
            options = {
                { id = "slowed", text = "slowed" },
                { id = "dazed", text = "dazed" },
                { id = "weakened", text = "weakened" },
                { id = "prone", text = "prone" },
            },
        },
        ends = {
            kind = "choice",
            default = "save",
            options = {
                { id = "save", text = "save ends" },
                { id = "eot", text = "until the end of their next turn" },
            },
        },
    },
    fits = { "step" },
    order = 30,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.move",
    family = "step",
    group = "movement",
    label = "Move a creature",
    desc = "A creature moves or shifts.",
    sentence = { { slot = "who" }, " ", { slot = "how" }, " up to ", { slot = "distance" }, " squares." },
    slots = {
        who = { kind = "choice", default = "self", options = WHO },
        how = {
            kind = "choice",
            default = "move",
            options = {
                { id = "move", text = "moves" },
                { id = "shift", text = "shifts" },
                { id = "teleport", text = "teleports" },
            },
        },
        distance = { kind = "number", default = 2 },
    },
    fits = { "step" },
    order = 40,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.newability",
    family = "step",
    group = "abilities",
    label = "Use a new ability",
    desc = "Someone uses another ability, with its own steps.",
    sentence = { "Then ", { slot = "who" }, " use a new ability, asking ", { slot = "prompt" }, ":" },
    slots = {
        who = { kind = "choice", default = "self", options = WHO },
        prompt = { kind = "text", default = "\"Choose a square\"" },
    },
    fits = { "step" },
    order = 50,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.onlyif",
    family = "logic",
    group = "logic",
    label = "Only if",
    desc = "The steps inside only happen when a test passes.",
    sentence = { "Only if ", { slot = "test" }, ":" },
    slots = { test = { kind = "test", default = "winded" } },
    fits = { "step" },
    order = 60,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.gainresource",
    family = "step",
    group = "resources",
    label = "Gain a resource",
    desc = "A creature gains a heroic resource or surges.",
    sentence = { { slot = "who" }, " gains ", { slot = "amount" }, " ", { slot = "resource" }, "." },
    slots = {
        who = { kind = "choice", default = "self", options = WHO },
        amount = { kind = "number", default = 1 },
        resource = {
            kind = "choice",
            default = "heroic",
            options = {
                { id = "heroic", text = "of their heroic resource" },
                { id = "surges", text = "surges" },
            },
        },
    },
    fits = { "step" },
    order = 70,
    stub = true,
}

----------------------------------------------------------------------------
-- Tier steps: blocks that only go inside a power roll's tier.
----------------------------------------------------------------------------

Block.RegisterBlock{
    id = "stub.tierdamage",
    family = "step",
    group = "harm",
    label = "Damage (in a tier)",
    desc = "Damage dealt by a power roll tier. Only goes inside a tier.",
    sentence = { { slot = "amount" }, " + ", { slot = "stat" }, " damage" },
    slots = {
        amount = { kind = "number", default = 3 },
        stat = { kind = "stat", default = "might" },
    },
    fits = { "tier" },
    order = 80,
    stub = true,
}

Block.RegisterBlock{
    id = "stub.tierpush",
    family = "step",
    group = "conditions",
    label = "Push (in a tier)",
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
            },
        },
        distance = { kind = "number", default = 2 },
    },
    fits = { "tier" },
    order = 90,
    stub = true,
}
