--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/block_test_picker_test.lua
--Checks the test picker's reading of a true/false formula in Block Editor/Slots.lua
--without drawing it: a part a registered test reads shows as that test's words and
--values, "and" / "or" / "not" join parts, a part no test reads stays as its formula,
--and the groups the picker lists. Uses two made-up tests, not the Draw Steel ones.

local function readSource(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return source
end

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

--Stand-ins for what the files under test call, set with rawset so the type
--checker does not take them for second definitions of the real globals.
local g_text = {}
rawset(_G, "dmhub", { GetModLoading = function() return {} end, Error = function(message) error(message) end })
rawset(_G, "DeepCopy", Copy)
rawset(_G, "UIText", {
    Define = function() return function(id, text) g_text[id] = text end end,
    T = function(id, args)
        local text = g_text[id] or id
        for key, value in pairs(args or {}) do
            text = string.gsub(text, "{" .. key .. "}", tostring(value))
        end
        return text
    end,
})
for _, path in ipairs({ "DMHub Utils/Block.lua", "DMHub Utils/BlockFormula.lua", "DMHub Utils/BlockStubs.lua", "Block Editor/BlockEditorText.lua", "Block Editor/Slots.lua" }) do
    assert(load(readSource(path), path))()
end

local g_checks = 0
local function Check(condition, what)
    g_checks = g_checks + 1
    if not condition then
        error("FAILED: " .. what, 2)
    end
end

--"the target is an enemy / an ally", saved as Enemy or not Enemy.
Block.RegisterTest{
    id = "t.enemy", group = "Kind of creature", label = "The target is an enemy", order = 10,
    slots = { side = { kind = "choice", default = "enemy", options = { { id = "enemy", text = "an enemy" }, { id = "ally", text = "an ally" } } } },
    make = function() return { k = "id", path = { "Enemy" } } end,
    read = function(node)
        local inner, negated = node, false
        if node.k == "not" then
            inner, negated = node.a, true
        end
        if inner ~= nil and inner.k == "id" and #inner.path == 1 and Block.NormName(inner.path[1]) == "enemy" then
            return { side = negated and "ally" or "enemy" }
        end
        return nil
    end,
    words = function(values) return { "the target is", { slot = "side" } } end,
    write = function(values)
        local node = { k = "id", path = { "Enemy" } }
        if values.side == "ally" then
            return { k = "not", a = node }
        end
        return node
    end,
}
--"the target has the X condition".
Block.RegisterTest{
    id = "t.condition", group = "Check a condition", label = "The target has a condition", order = 20,
    slots = { value = { kind = "text", default = "Prone" } },
    make = function() return { k = "has", l = { k = "id", path = { "Conditions" } }, r = { k = "str", v = "Prone" } } end,
    read = function(node)
        if node.k == "has" and node.l.k == "id" and Block.NormName(node.l.path[#node.l.path]) == "conditions" and node.r.k == "str" then
            return { value = node.r.v }
        end
        return nil
    end,
    words = function(values) return { "the target has the", { slot = "value" }, "condition" } end,
    write = function(values) return { k = "has", l = { k = "id", path = { "Conditions" } }, r = { k = "str", v = values.value } } end,
}

--- The pieces of a formula that must parse.
--- @param text string
--- @return BlockFormulaNode, table[]
local function Pieces(text)
    local parsed, list = BESlots._testPieces(text)
    return assert(parsed), assert(list)
end

local function Texts(pieces)
    local result = {}
    for i, piece in ipairs(pieces) do
        result[i] = piece.text .. "/" .. tostring(piece.edit)
    end
    return table.concat(result, " ")
end

local _, pieces = Pieces("Enemy")
Check(Texts(pieces) == "the target is/test an enemy/slot", "a test reads as its words and its value: " .. Texts(pieces))
_, pieces = Pieces("not enemy")
Check(pieces[2].text == "an ally" and #pieces == 2, "a test can read its own \"not\" (not Enemy is an ally)")

local ast
ast, pieces = Pieces('Enemy and Conditions has "Grabbed"')
Check(Texts(pieces) == "the target is/test an enemy/slot and/join the target has the/test Grabbed/slot condition/test",
    "\"and\" joins two tests: " .. Texts(pieces))
Check(pieces[4].path[1] == "r" and pieces[1].path[1] == "l", "each part knows where it sits in the formula")

--a value changed through its test rewrites only that part.
local condition = pieces[5]
local values = Copy(condition.values)
values.value = "Slowed"
local rewritten = BESlots._replaced(ast, condition.path, condition.test.write(values))
Check(Block.PrintFormula(rewritten) == 'Enemy and Conditions has "Slowed"', "changing one value keeps the rest as written: " .. Block.PrintFormula(rewritten))

_, pieces = Pieces("Target.Stamina <= 0 or not Enemy")
Check(Texts(pieces) == "Target.Stamina <= 0/formula or/join the target is/test an ally/slot",
    "a part no test reads stays as its formula: " .. Texts(pieces))

_, pieces = Pieces("not (Enemy and Minion)")
Check(pieces[1].text == "not" and pieces[1].edit == "join", "a \"not\" no test reads is a joining word")

Check(BESlots._testPieces("Enemy and") == nil, "a formula that does not parse has no pieces (it is typed over instead)")

local titles = {}
for _, group in ipairs(BESlots._testGroups("")) do
    titles[#titles + 1] = group.title
end
Check(table.concat(titles, " | ") == "Kind of creature | Check a condition", "the picker lists groups by order: " .. table.concat(titles, " | "))
Check(#BESlots._testGroups("grab") == 0 and #BESlots._testGroups("condition") == 1, "the search finds tests by their words")

print("block_test_picker_test: " .. g_checks .. " checks passed")
