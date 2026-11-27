local mod = dmhub.GetModLoading()

--[[
 BlockFormula: the GoblinScript parser and printer the block editor uses to
 open a formula (a test like "Target has Bleeding", an amount like
 "2 + Might") as blocks, and to write it back.

     local ast, err = Block.ParseFormula("Self.Stamina <= 5 and not Target is Ally")
     local text = Block.PrintFormula(ast)  -- the same text again

 A port of the parser in the design prototype (ui-mockup/ability-blocks-stack.html).
 Precedence, loosest first: + - ; when ... else ; and / or ; not and comparisons ;
 * / ; has / is [not] ; unary minus ; names, numbers, strings, ( ).

 Printing a parsed formula gives back the source text up to spacing: the
 parser remembers the parentheses the author wrote and how keywords and
 operators were spelled. Blocks built in the editor have none of that, and
 print with only the parentheses the meaning needs.

 GoblinScriptProse.lua is a separate parser that only reads formulas into
 prose; this one does not depend on it.
]]

--- One node of a parsed formula. Which fields are set depends on k:
---  num, dice, str, param: v (the text; a str without its quotes, a param without << >>)
---  id: path (the dotted names, "Self.Maximum Stamina" is {"Self", "Maximum Stamina"})
---  call: path, args (Target.PassesPotency("M", 2))
---  field: of (a call node), name (a field read after a call: Count(x).Total)
---  bin: op ("+", "-", "*", "/"), l, r; unary = true for a leading minus (l is then num 0)
---  cmp: op (">=", "<=", "~=", "=", "<", ">"), l, r
---  and, or: l, r
---  not: a
---  has, is: l, r, neg (true for "is not" / "has not")
---  when: v, c, e (v when c else e; e is nil without an else)
--- @class BlockFormulaNode
--- @field k string
--- @field v? string|BlockFormulaNode
--- @field path? string[]
--- @field args? BlockFormulaNode[]
--- @field of? BlockFormulaNode
--- @field name? string
--- @field op? string
--- @field l? BlockFormulaNode
--- @field r? BlockFormulaNode
--- @field a? BlockFormulaNode
--- @field c? BlockFormulaNode
--- @field e? BlockFormulaNode
--- @field neg? boolean
--- @field unary? boolean
--- @field parens? integer how many ( ) the author wrapped it in; printed back as written
--- @field opText? string the operator as written when it differs from op ("!=" or "<>" for "~=")
--- @field kwText? string the keyword as written when not lower case ("AND")
--- @field notText? string the "not" of "is not" as written when not lower case
--- @field elseText? string the "else" of a when as written when not lower case
--- @field comments? {text: string, before: boolean}[] on the root only: the {notes} in the formula, without braces; before = it came ahead of the formula

--- Words the tokenizer reads as operators, never as part of a name.
local g_keywords = { ["and"] = true, ["or"] = true, ["not"] = true, has = true, is = true, when = true, ["else"] = true, where = true }

--- Operators, two-character ones first so ">=" is not read as ">" then "=".
local g_operators = { ">=", "<=", "~=", "!=", "<>", "=", "<", ">", "+", "-", "*", "/", "(", ")", ",", "." }

--- Raises a parse error with a message for the author (no file position).
local function Fail(message)
    error({ formulaError = message }, 0)
end

--- Splits formula text into tokens: {t = "num"|"dice"|"str"|"param"|"op"|"kw"|"id", v = text, src = as written}.
--- Also returns the {comments}: the engine skips {...} (nested braces allowed,
--- an unclosed one runs to the end), and authors use it for notes.
local function Tokenize(src)
    local tokens = {}
    local comments = {}
    local index = 1
    local length = #src
    while index <= length do
        local char = string.sub(src, index, index)
        local rest = string.sub(src, index)
        local matched = nil
        if string.find(char, "^%s") then
            index = index + 1
        elseif char == "{" then
            local depth = 0
            local stop = index
            while stop <= length do
                local inner = string.sub(src, stop, stop)
                if inner == "{" then
                    depth = depth + 1
                elseif inner == "}" then
                    depth = depth - 1
                    if depth == 0 then
                        break
                    end
                end
                stop = stop + 1
            end
            comments[#comments + 1] = { text = string.sub(src, index + 1, stop - 1), before = #tokens == 0 }
            index = stop + 1
        else
            -- <<name>>: a value handed in by the ability that invoked this one.
            local param = string.match(rest, "^<<([^>]*)>>")
            if param ~= nil then
                tokens[#tokens + 1] = { t = "param", v = string.match(param, "^%s*(.-)%s*$") }
                index = index + #param + 4
                goto continue
            end
            matched = string.match(rest, "^%d+[dD]%d+")
            if matched ~= nil then
                tokens[#tokens + 1] = { t = "dice", v = matched }
                index = index + #matched
                goto continue
            end
            matched = string.match(rest, "^%d+%.%d+") or string.match(rest, "^%d+")
            if matched ~= nil then
                tokens[#tokens + 1] = { t = "num", v = matched }
                index = index + #matched
                goto continue
            end
            if char == '"' then
                local closing = string.find(src, '"', index + 1, true)
                if closing == nil then
                    Fail("A quote is not closed")
                end
                tokens[#tokens + 1] = { t = "str", v = string.sub(src, index + 1, closing - 1) }
                index = closing + 1
                goto continue
            end
            for _, operator in ipairs(g_operators) do
                if string.sub(rest, 1, #operator) == operator then
                    local value = operator
                    if operator == "!=" or operator == "<>" then
                        value = "~="
                    end
                    tokens[#tokens + 1] = { t = "op", v = value, src = operator }
                    index = index + #operator
                    goto continue
                end
            end
            matched = string.match(rest, "^[A-Za-z_][A-Za-z0-9_]*")
            if matched ~= nil then
                local lower = string.lower(matched)
                local previous = tokens[#tokens]
                if g_keywords[lower] then
                    tokens[#tokens + 1] = { t = "kw", v = lower, src = matched }
                elseif previous ~= nil and previous.t == "id" then
                    -- Adjacent words are one name: "Maximum Stamina".
                    previous.v = previous.v .. " " .. matched
                else
                    tokens[#tokens + 1] = { t = "id", v = matched }
                end
                index = index + #matched
                goto continue
            end
            Fail("Unexpected character " .. char)
        end
        ::continue::
    end
    return tokens, comments
end

--- The spelling to remember for a keyword token: nil when it is the plain lower-case word.
local function KeywordText(token)
    if token.src ~= token.v then
        return token.src
    end
    return nil
end

--- Parses formula text into a tree. Raises {formulaError = message} on bad input.
--- @param src string
--- @return BlockFormulaNode
local function Parse(src)
    local tokens, comments = Tokenize(src)
    local position = 1

    local function Peek() return tokens[position] end
    local function Take()
        local token = tokens[position]
        position = position + 1
        return token
    end
    local function IsOp(value)
        local token = tokens[position]
        return token ~= nil and token.t == "op" and token.v == value
    end
    local function IsKw(value)
        local token = tokens[position]
        return token ~= nil and token.t == "kw" and token.v == value
    end

    local Add, WhenExpr, Logic, Compare, Multiply, IsHas, Unary, Primary

    Add = function()
        local left = WhenExpr()
        while IsOp("+") or IsOp("-") do
            local operator = Take().v
            left = { k = "bin", op = operator, l = left, r = WhenExpr() }
        end
        return left
    end

    -- "a when x else b when y else c" chains: the else side is itself a when-expression.
    WhenExpr = function()
        local value = Logic()
        if IsKw("when") then
            local node = { k = "when", v = value, kwText = KeywordText(Take()) }
            node.c = Logic()
            if IsKw("else") then
                node.elseText = KeywordText(Take())
                node.e = WhenExpr()
            end
            value = node
        end
        return value
    end

    Logic = function()
        local left = Compare()
        while IsKw("and") or IsKw("or") do
            local token = Take()
            left = { k = token.v, l = left, r = Compare(), kwText = KeywordText(token) }
        end
        return left
    end

    Compare = function()
        if IsKw("not") then
            local token = Take()
            return { k = "not", a = Compare(), kwText = KeywordText(token) }
        end
        local left = Multiply()
        local token = Peek()
        if token ~= nil and token.t == "op" and (token.v == ">=" or token.v == "<=" or token.v == ">" or token.v == "<" or token.v == "=" or token.v == "~=") then
            Take()
            local node = { k = "cmp", op = token.v, l = left, r = Multiply() }
            if token.src ~= token.v then
                node.opText = token.src
            end
            left = node
        end
        return left
    end

    Multiply = function()
        local left = IsHas()
        while IsOp("*") or IsOp("/") do
            local operator = Take().v
            left = { k = "bin", op = operator, l = left, r = IsHas() }
        end
        return left
    end

    IsHas = function()
        local left = Unary()
        if IsKw("has") or IsKw("is") then
            local token = Take()
            local node = { k = token.v, neg = false, l = left, kwText = KeywordText(token) }
            if IsKw("not") then
                node.notText = KeywordText(Take())
                node.neg = true
            end
            node.r = Unary()
            left = node
        end
        return left
    end

    Unary = function()
        if IsOp("-") then
            Take()
            return { k = "bin", op = "-", unary = true, l = { k = "num", v = "0" }, r = Unary() }
        end
        return Primary()
    end

    --- Reads the name after a ".".
    local function NameAfterDot()
        local token = Take()
        if token == nil or token.t ~= "id" then
            Fail("Expected a name after .")
        end
        return token.v
    end

    Primary = function()
        local token = Take()
        if token == nil then
            Fail("The formula ends too early")
        end
        if token.t == "num" or token.t == "dice" or token.t == "str" or token.t == "param" then
            return { k = token.t, v = token.v }
        end
        if token.t == "op" and token.v == "(" then
            local inner = Add()
            if not IsOp(")") then
                Fail("A ( is not closed")
            end
            Take()
            inner.parens = (inner.parens or 0) + 1
            return inner
        end
        if token.t == "id" then
            local path = { token.v }
            while IsOp(".") do
                Take()
                path[#path + 1] = NameAfterDot()
            end
            if IsOp("(") then
                Take()
                local args = {}
                if not IsOp(")") then
                    args[#args + 1] = Add()
                    while IsOp(",") do
                        Take()
                        args[#args + 1] = Add()
                    end
                end
                if not IsOp(")") then
                    Fail("A ( is not closed")
                end
                Take()
                local node = { k = "call", path = path, args = args }
                while IsOp(".") do
                    Take()
                    node = { k = "field", of = node, name = NameAfterDot() }
                end
                return node
            end
            return { k = "id", path = path }
        end
        if token.t == "kw" then
            Fail("Unexpected word '" .. token.v .. "'. Names containing has, is, not, and, or are read as operators; write them without spaces (HasAttacker)")
        end
        Fail("Unexpected '" .. token.v .. "'")
    end

    local result = Add()
    if position <= #tokens then
        Fail("Unexpected '" .. (tokens[position].src or tokens[position].v) .. "' after the end of the formula")
    end
    if #comments > 0 then
        result.comments = comments
    end
    return result
end

--- How tightly a node binds when printed; a child that binds looser than its
--- place needs gets ( ). Primaries and anything already in parentheses are 10.
local function Precedence(node, canonical)
    if (not canonical) and (node.parens or 0) > 0 then
        return 10
    end
    local kind = node.k
    if kind == "bin" then
        if node.unary then
            return 8
        end
        if node.op == "*" or node.op == "/" then
            return 6
        end
        return 2
    end
    if kind == "when" then return 3 end
    if kind == "and" or kind == "or" then return 4 end
    -- "not" reads a whole comparison ("not a = b"), so it sits at the comparison level.
    if kind == "cmp" or kind == "not" then return 5 end
    if kind == "has" or kind == "is" then return 7 end
    return 10
end

local Print

--- Prints a child node, wrapped in ( ) when it binds looser than its place allows.
local function Child(node, needed, canonical)
    local text = Print(node, canonical)
    if Precedence(node, canonical) < needed then
        return "(" .. text .. ")"
    end
    return text
end

--- A name as printed: as written, or without spaces in canonical form.
local function Name(name, canonical)
    if canonical then
        return string.gsub(name, "%s+", "")
    end
    return name
end

local function Path(path, canonical)
    local parts = {}
    for index, name in ipairs(path) do
        parts[index] = Name(name, canonical)
    end
    return table.concat(parts, ".")
end

--- A keyword as printed: as the author spelled it, or lower case in canonical form.
local function Word(written, word, canonical)
    if canonical or written == nil then
        return word
    end
    return written
end

--- @param node BlockFormulaNode
--- @param canonical? boolean
--- @return string
Print = function(node, canonical)
    local kind = node.k
    --- @type string
    local text
    if kind == "num" or kind == "dice" then
        text = node.v --[[@as string]]
    elseif kind == "str" then
        text = '"' .. node.v .. '"'
    elseif kind == "param" then
        text = "<<" .. node.v .. ">>"
    elseif kind == "id" then
        text = Path(node.path, canonical)
    elseif kind == "call" then
        local args = {}
        for index, arg in ipairs(node.args) do
            args[index] = Print(arg, canonical)
        end
        text = Path(node.path, canonical) .. "(" .. table.concat(args, ", ") .. ")"
    elseif kind == "field" then
        text = Print(node.of, canonical) .. "." .. Name(node.name, canonical)
    elseif kind == "bin" and node.unary then
        text = "-" .. Child(node.r, 8, canonical)
    elseif kind == "bin" then
        local own = Precedence(node, true)
        text = Child(node.l, own, canonical) .. " " .. node.op .. " " .. Child(node.r, own + 1, canonical)
    elseif kind == "cmp" then
        text = Child(node.l, 6, canonical) .. " " .. Word(node.opText, node.op, canonical) .. " " .. Child(node.r, 6, canonical)
    elseif kind == "and" or kind == "or" then
        text = Child(node.l, 4, canonical) .. " " .. Word(node.kwText, kind, canonical) .. " " .. Child(node.r, 5, canonical)
    elseif kind == "not" then
        text = Word(node.kwText, "not", canonical) .. " " .. Child(node.a, 5, canonical)
    elseif kind == "has" or kind == "is" then
        text = Child(node.l, 8, canonical) .. " " .. Word(node.kwText, kind, canonical)
        if node.neg then
            text = text .. " " .. Word(node.notText, "not", canonical)
        end
        text = text .. " " .. Child(node.r, 8, canonical)
    elseif kind == "when" then
        text = Child(node.v, 4, canonical) .. " " .. Word(node.kwText, "when", canonical) .. " " .. Child(node.c, 4, canonical)
        if node.e ~= nil then
            text = text .. " " .. Word(node.elseText, "else", canonical) .. " " .. Child(node.e, 3, canonical)
        end
    else
        text = "?"
    end
    if not canonical then
        for _ = 1, node.parens or 0 do
            text = "(" .. text .. ")"
        end
    end
    return text
end

--- Parses a GoblinScript formula into a tree of BlockFormulaNode.
--- Returns nil and a message for the author when the text is not a formula.
--- @param text string
--- @return BlockFormulaNode|nil
--- @return string|nil
function Block.ParseFormula(text)
    if type(text) ~= "string" then
        return nil, "A formula must be text"
    end
    local ok, result = pcall(Parse, text)
    if ok then
        return result, nil
    end
    if type(result) == "table" then
        local failure = result --[[@as {formulaError?: string}]]
        if failure.formulaError ~= nil then
            return nil, failure.formulaError
        end
    end
    return nil, tostring(result)
end

--- Prints a formula tree back to GoblinScript text. A parsed tree prints as
--- its source did (spacing aside). options.canonical prints the plain form
--- instead: names without spaces, lower-case keywords, only the parentheses
--- the meaning needs, no {notes}; two formulas that mean the same print the same.
--- @param ast BlockFormulaNode
--- @param options? {canonical?: boolean}
--- @return string
function Block.PrintFormula(ast, options)
    local canonical = options ~= nil and options.canonical == true
    local text = Print(ast, canonical)
    if ast.comments == nil or canonical then
        return text
    end
    -- Notes from inside the formula move to its end; the engine ignores where they sit.
    local before, after = {}, {}
    for _, comment in ipairs(ast.comments) do
        local list = comment.before and before or after
        list[#list + 1] = "{" .. comment.text .. "}"
    end
    before[#before + 1] = text
    for _, comment in ipairs(after) do
        before[#before + 1] = comment
    end
    return table.concat(before, " ")
end

--- A formula's plain form (Block.PrintFormula canonical), or nil when the text
--- is not a formula. Two spellings of one formula have the same plain form.
--- @param text any
--- @return string|nil
function Block.FormulaCanonical(text)
    if type(text) ~= "string" then
        return nil
    end
    local ast = Block.ParseFormula(text)
    if ast == nil then
        return nil
    end
    return Block.PrintFormula(ast, { canonical = true })
end

--- Whether two formulas mean the same ("Might*2" and "Might * 2"); texts that
--- are not formulas must match exactly.
--- @param a any
--- @param b any
--- @return boolean
function Block.SameFormula(a, b)
    if a == b then
        return true
    end
    local canonicalA, canonicalB = Block.FormulaCanonical(a), Block.FormulaCanonical(b)
    return canonicalA ~= nil and canonicalA == canonicalB
end

--- A roll of dice plus something ("2d10 + Might", "2d10 + Might or Agility"),
--- read from its syntax tree: the dice, what is added as written, and the
--- added name when it is a single name. Nil for any other roll.
--- @param text any
--- @return string|nil dice, string|nil added, string|nil name
function Block.SplitRoll(text)
    if type(text) ~= "string" then
        return nil, nil, nil
    end
    local ast = Block.ParseFormula(text)
    if ast == nil or ast.k ~= "bin" or ast.op ~= "+" or ast.unary or ast.parens then
        return nil, nil, nil
    end
    local dice, added = ast.l, ast.r
    if dice == nil or dice.k ~= "dice" or added == nil then
        return nil, nil, nil
    end
    local name = nil
    if added.k == "id" and added.path ~= nil and #added.path == 1 and not added.parens then
        name = added.path[1]
    end
    return tostring(dice.v), Block.PrintFormula(added), name
end
