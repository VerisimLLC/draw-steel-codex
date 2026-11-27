--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/block_formula_test.lua
--Checks the block editor's GoblinScript parser and printer (DMHub Utils/BlockFormula.lua)
--without the app: precedence, error messages, and that printing a parsed formula gives
--its source back.

rawset(_G, "dmhub", {
    GetModLoading = function() return {} end,
    Error = function(msg) error(msg) end,
})
rawset(_G, "Block", {})

dofile("DMHub Utils/BlockFormula.lua")

local g_checks = 0
local function Check(condition, what)
    g_checks = g_checks + 1
    if not condition then
        error("FAILED: " .. what, 2)
    end
end

local function Canonical(text)
    local ast, err = Block.ParseFormula(text)
    Check(ast ~= nil, "parses: " .. text .. " (" .. tostring(err) .. ")")
    --- @cast ast BlockFormulaNode
    return Block.PrintFormula(ast, { canonical = true })
end

--Formulas that must print back exactly as written.
local g_roundTrips = {
    "2",
    "1.5 * Level",
    "2d6 + 3",
    "Might",
    "Maximum Stamina / 2",
    "Self.Maximum Stamina",
    "<<damage>> + 2",
    "Target has Bleeding",
    "Target is not Ally",
    "not Target is Ally",
    "not Stamina = 0",
    "Self.Stamina <= 5 and not Target is Ally",
    "Level >= 4 or Victories > 2",
    "Target.PassesPotency(\"M\", 2)",
    "not Cast.PassesPotency(Target, \"A\", Strong)",
    "Count(Enemies).Total",
    "Max(Might, Agility, 2)",
    "3 when Level >= 7 else 2 when Level >= 4 else 1",
    "(1 + 2) * 3",
    "((Might))",
    "-Might + 1",
    "2 * -Level",
    "Keywords has \"Strike\"",
    "A != B",
    "A <> B",
    "A AND B",
    "X when Y",
    "(X when Y else Z) * 2",
}
for _, text in ipairs(g_roundTrips) do
    local ast, err = Block.ParseFormula(text)
    Check(ast ~= nil, "parses: " .. text .. " (" .. tostring(err) .. ")")
    --- @cast ast BlockFormulaNode
    Check(Block.PrintFormula(ast) == text, "round trip: " .. text .. " printed " .. Block.PrintFormula(ast))
end

--Precedence, shown by the canonical print (only the parentheses meaning needs).
Check(Canonical("1 + 2 * 3") == "1 + 2 * 3", "* binds tighter than +")
Check(Canonical("(1 + 2) * 3") == "(1 + 2) * 3", "needed parentheses kept")
Check(Canonical("((1 * 2)) + 3") == "1 * 2 + 3", "redundant parentheses dropped")
Check(Canonical("1 - (2 - 3)") == "1 - (2 - 3)", "- is left-associative")
Check(Canonical("A != B") == "A ~= B", "!= is ~=")
Check(Canonical("Maximum Stamina") == "MaximumStamina", "canonical names lose spaces")
Check(Canonical("A AND B") == "A and B", "canonical keywords are lower case")

do
    local ast = Block.ParseFormula("A and B or C = 1")
    Check(ast ~= nil and ast.k == "or" and ast.l.k == "and" and ast.r.k == "cmp", "and/or chain left to right, comparison inside")
    ast = Block.ParseFormula("not A = B")
    Check(ast ~= nil and ast.k == "not" and ast.a.k == "cmp", "not reads the whole comparison")
    ast = Block.ParseFormula("2 * Target has Bleeding")
    Check(ast ~= nil and ast.k == "bin" and ast.r.k == "has", "has binds tighter than *")
    ast = Block.ParseFormula("1 + 2 when A else 3")
    Check(ast ~= nil and ast.k == "bin" and ast.r.k == "when", "when binds tighter than +")
    ast = Block.ParseFormula("A when B else C when D else E")
    Check(ast ~= nil and ast.k == "when" and ast.e.k == "when" and ast.e.e.k == "id", "when chains through else")
    ast = Block.ParseFormula("Target.PassesPotency(\"M\", 2)")
    Check(ast ~= nil and ast.k == "call" and #ast.path == 2 and #ast.args == 2 and ast.args[1].k == "str", "call with path and args")
    ast = Block.ParseFormula("Target is not Ally")
    Check(ast ~= nil and ast.k == "is" and ast.neg == true, "is not sets neg")
    ast = Block.ParseFormula("-2")
    Check(ast ~= nil and ast.k == "bin" and ast.unary == true and ast.l.v == "0" and ast.r.v == "2", "unary minus is 0 - x")
end

--A tree built by hand (as the block editor builds one) prints with the parentheses it needs.
do
    local sum = { k = "bin", op = "+", l = { k = "num", v = "1" }, r = { k = "num", v = "2" } }
    local product = { k = "bin", op = "*", l = sum, r = { k = "id", path = { "Level" } } }
    Check(Block.PrintFormula(product) == "(1 + 2) * Level", "built tree gets needed parentheses")
    local negated = { k = "not", a = { k = "and", l = { k = "id", path = { "A" } }, r = { k = "id", path = { "B" } } } }
    Check(Block.PrintFormula(negated) == "not (A and B)", "not over and is wrapped")
    local compared = { k = "cmp", op = "=", l = { k = "not", a = { k = "id", path = { "A" } } }, r = { k = "id", path = { "B" } } }
    local reparsed = Block.ParseFormula(Block.PrintFormula(compared))
    Check(reparsed ~= nil and reparsed.k == "cmp", "not on the left of a comparison is wrapped")
end

--{notes} are skipped like the engine does, and kept on the root so they print back.
do
    local ast = Block.ParseFormula("Level >= 2 {an upgrade {nested} at Level 2}")
    Check(ast ~= nil and ast.k == "cmp" and #ast.comments == 1 and ast.comments[1].text == "an upgrade {nested} at Level 2", "trailing note kept")
    --- @cast ast BlockFormulaNode
    Check(Block.PrintFormula(ast) == "Level >= 2 {an upgrade {nested} at Level 2}", "trailing note prints back")
    Check(Block.PrintFormula(ast, { canonical = true }) == "Level >= 2", "canonical print drops notes")
    ast = Block.ParseFormula("{lead} 1 + {mid} 2")
    Check(ast ~= nil and Block.PrintFormula(ast) == "{lead} 1 + 2 {mid}", "a note inside moves to the end")
    ast = Block.ParseFormula("Maximum {x} Stamina")
    Check(ast ~= nil and ast.k == "id" and ast.path[1] == "Maximum Stamina", "a note between words keeps one name")
    ast = Block.ParseFormula("3 {unclosed")
    Check(ast ~= nil and ast.comments[1].text == "unclosed", "an unclosed note runs to the end")
end

--Errors: nil plus a message, never a throw.
local g_errorCases = {
    { "", "ends too early" },
    { "(1 + 2", "not closed" },
    { "\"abc", "quote is not closed" },
    { "1 2", "after the end" },
    { "Self.", "name after" },
    { "Has Attacker", "without spaces" },
    { "1 # 2", "Unexpected character" },
    { "{only a note}", "ends too early" },
    { "Count(A, B", "not closed" },
}
for _, case in ipairs(g_errorCases) do
    local ast, err = Block.ParseFormula(case[1])
    Check(ast == nil and type(err) == "string" and string.find(err, case[2], 1, true) ~= nil,
        "error for '" .. case[1] .. "': " .. tostring(err))
end
--rolls and comparisons read from the syntax tree, not by matching text.
do
    local dice, added, name = Block.SplitRoll("2d10 + Might")
    Check(dice == "2d10" and added == "Might" and name == "Might", "a power roll splits into dice and a characteristic")
    dice, added, name = Block.SplitRoll("2d10+Reason Modifier")
    Check(dice == "2d10" and name == "Reason Modifier", "a name with a space is one name")
    dice, added, name = Block.SplitRoll("2d10 + Might or Agility")
    Check(dice == "2d10" and added == "Might or Agility" and name == nil, "a choice of characteristics is added, not one name")
    Check(Block.SplitRoll("1d6") == nil and Block.SplitRoll("Might + 2d10") == nil, "other rolls do not split")
    Check(Block.SameFormula("Might*2", "Might * 2") and not Block.SameFormula("Might * 2", "Might * 3"), "formulas compare by meaning")
    Check(Block.SameFormula("not a ( formula", "not a ( formula") and not Block.SameFormula("(", ")"), "text that is not a formula compares exactly")
end

--deliberately the wrong type: the parser must refuse it, not raise.
---@diagnostic disable-next-line: param-type-mismatch
Check(Block.ParseFormula(nil) == nil, "non-text is an error")

print("block_formula_test: " .. g_checks .. " checks passed")
