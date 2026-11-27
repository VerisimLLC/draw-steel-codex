--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/block_amount_test.lua
--Checks the amount picker's logic in Block Editor/Slots.lua without drawing it:
--the kinds it lists (one per kind, never one per value), that a searched stat
--changes the examples, and that the numbers, stats and signs of a formula are
--pieces that can each be changed on the block.

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

local amount = { kind = "formula", default = "2", amount = true, dice = true }

local names = {}
for _, kind in ipairs(BESlots._amountKinds(amount, "")) do
    names[#names + 1] = kind.name
end
Check(table.concat(names, " | ") == "A number | A stat | A stat with math | More as you level | Depends on a test | A dice roll",
    "the picker lists the kinds of amount: " .. table.concat(names, " | "))
local noDice = BESlots._amountKinds({ kind = "formula", amount = true }, "")
Check(#noDice == 5, "A dice roll is only offered where dice are allowed")

local agility = BESlots._amountKinds(amount, "agi")
Check(agility[2].example == "your Agility" and agility[2].value == "Agility", "searching a stat makes A stat use it")
Check(agility[3].example == "your Agility + 4, your Agility * 2" and agility[3].value == "Agility + 1", "and A stat with math")
local level = BESlots._amountKinds(amount, "lev")
Check(level[2].value == "Level", "Level can be searched like a stat")

--a formula's pieces.
local function Texts(pieces)
    local result = {}
    for i, piece in ipairs(pieces) do
        result[i] = piece.text .. (piece.edit and (":" .. piece.edit) or "")
    end
    return table.concat(result, " ")
end
local ast, pieces = BESlots._formulaPieces("Might * 2")
assert(ast ~= nil and pieces ~= nil)
Check(Texts(pieces) == "Might:stat *:sign 2:number", "Might * 2 is a stat, a sign and a number: " .. Texts(pieces))
Check(Block.PrintFormula(BESlots._replaced(ast, pieces[1].path, { k = "id", path = { "Agility" } })) == "Agility * 2", "the stat changes on the block")
local sign = Copy(ast)
sign.op = "+"
Check(Block.PrintFormula(BESlots._replaced(ast, pieces[2].path, sign)) == "Might + 2", "the sign changes on the block")
Check(Block.PrintFormula(BESlots._replaced(ast, pieces[3].path, Block.ParseFormula("4") --[[@as BlockFormulaNode]])) == "Might * 4", "a number changes on the block")

ast, pieces = BESlots._formulaPieces("2 when Target.Winded else 1")
assert(ast ~= nil and pieces ~= nil)
Check(Texts(pieces) == "2:number if Target.Winded:formula otherwise 1:number", "Depends on a test reads as words: " .. Texts(pieces))

ast, pieces = BESlots._formulaPieces("1 + (1 when Level >= 5 else 0)")
assert(ast ~= nil and pieces ~= nil)
Check(Texts(pieces) == "1:number +:sign ( 1:number if Level >= 5:formula otherwise 0:number )", "More as you level keeps its parentheses: " .. Texts(pieces))
local test = BESlots._replaced(ast, pieces[6].path, Block.ParseFormula("Level >= 10") --[[@as BlockFormulaNode]])
Check(Block.PrintFormula(test) == "1 + (1 when Level >= 10 else 0)", "the test changes without losing the parentheses: " .. Block.PrintFormula(test))

Check(BESlots._formulaPieces("Might +") == nil, "text that is not a formula has no pieces")

print("block_amount_test: " .. g_checks .. " checks passed")
