local mod = dmhub.GetModLoading()

-- GoblinScriptProse
-- ------------------
-- Renders a GoblinScript formula string as plain-English prose. Used by the
-- Triggered Ability Editor's Mechanical View and Trigger Preview card to turn
-- condition formulas ("Damage >= 5 and Path.Forced") into readable sentences
-- ("the damage is at least 5 and the movement was forced").
--
-- Launch scope (per TRIGGERED_ABILITY_EDITOR_DESIGN.md opt-in #4, Option A):
-- 8 pattern shapes -- bare boolean, negated boolean, numeric comparison,
-- string equality, set membership, AND chain, OR chain, function call.
-- Raw-formula fallback for anything that does not match.
--
-- GoblinScript has no AST exposed (design doc gotcha 4), so we roll a minimal
-- tokeniser + recursive-descent shaper here. Whitespace and case insensitive
-- for identifiers and keywords. Multi-word identifiers merge (e.g.
-- "Maximum Stamina" is a single symbol name).

GoblinScriptProse = {}

--------------------------------------------------------------------------
-- Vocabulary registry
--------------------------------------------------------------------------
-- Keys are normalised (lowercased, single-spaced) identifier forms.
-- Value shapes:
--   string                            -- static prose fragment
--   { dynamic = "subject" }           -- render-time lookup on ctx.subject
--   { dynamic = "speed" }             -- render-time lookup on ctx.trigger
--   { dynamic = "quantity" }          -- render-time lookup on ctx.trigger
GoblinScriptProse.symbols = {}
GoblinScriptProse.functions = {}
-- Role symbols are creature-typed (or ability/cast/path-typed) parent
-- symbols used for dotted-access composition fallbacks. If a user writes
-- `Attacker.Level` and no explicit "attacker.level" entry exists, we
-- synthesize "the attacker's level" by combining the role prose with the
-- lowercased tail. Entries follow the same shape as `symbols` (string or
-- { dynamic = "..." }).
GoblinScriptProse.roles = {}

local function normalise(name)
    -- GoblinScript treats multi-word identifiers as space-insensitive --
    -- `Used Ability` and `UsedAbility` are the same symbol (guide: "Multi-
    -- word identifiers are merged"). Strip all whitespace and lowercase
    -- so our lookup tables match either spelling.
    if name == nil then return "" end
    return string.lower(string.gsub(name, "%s+", ""))
end

function GoblinScriptProse.RegisterSymbolProse(name, prose)
    GoblinScriptProse.symbols[normalise(name)] = prose
end

function GoblinScriptProse.RegisterFunctionProse(name, prose)
    GoblinScriptProse.functions[normalise(name)] = prose
end

function GoblinScriptProse.RegisterRoleProse(name, prose)
    GoblinScriptProse.roles[normalise(name)] = prose
end

-- Dynamic-prose tables. Render-time lookups keyed on ability context.
-- Values come from TRIGGER_SYMBOL_PROSE.md (locked 2026-04-24 rev 2).
--
-- Each subject entry has two forms:
--   role       -- noun phrase used in event templates ("you take damage")
--   possessive -- form used for dotted access ("your stamina")
-- The composer reads whichever field the template placeholder asks for
-- (`{subject}` -> role, `{subject-possessive}` -> possessive).
GoblinScriptProse.subjectProse = {
    self           = { role = "you",             possessive = "your" },
    any            = { role = "any creature",    possessive = "that creature's" },
    selfandheroes  = { role = "you or any hero", possessive = "that creature's" },
    otherheroes    = { role = "another hero",    possessive = "that hero's" },
    selfandallies  = { role = "you or any ally", possessive = "that creature's" },
    allies         = { role = "any ally",        possessive = "that ally's" },
    enemy          = { role = "any enemy",       possessive = "that enemy's" },
    other          = { role = "another creature", possessive = "that creature's" },
}

GoblinScriptProse.speedProse = {
    collide = "the remaining speed at collision",
    wallbreak = "the stamina cost of the wall break",
    fall = "the fall distance",
    fallenon = "the fall distance",
}

GoblinScriptProse.quantityProse = {
    earnvictory = "the victories earned",
    gainresource = "the amount gained",
    useresource = "the amount used",
}

--------------------------------------------------------------------------
-- Tokeniser
--------------------------------------------------------------------------
-- Token kinds:
--   IDENT   -- possibly multi-word identifier like "Damage Type" or "Path"
--   NUMBER  -- numeric literal
--   STRING  -- quoted string literal (value is unquoted)
--   OP      -- operator or keyword-op: > >= < <= = != ~= <> + - * /
--             and or not is "is not" has "has not"
--   PUNCT   -- ( ) , .
-- Every token carries a [start, stop] byte range into the original formula
-- so we can re-emit the raw source for sub-expressions we fail to recognise.

local KEYWORD_OPS = {
    ["and"] = true,
    ["or"] = true,
    ["not"] = true,
    ["is"] = true,
    ["has"] = true,
}

-- "when", "else", "where" are GoblinScript keywords but sit outside the
-- launch-tier patterns. Treat them as unknowns so the containing expression
-- falls back to raw text.
local UNSUPPORTED_KEYWORDS = {
    ["when"] = true,
    ["else"] = true,
    ["where"] = true,
}

local function isDigit(c)
    return c >= "0" and c <= "9"
end

local function isWordChar(c)
    if c == nil or c == "" then return false end
    return (c >= "a" and c <= "z")
        or (c >= "A" and c <= "Z")
        or (c >= "0" and c <= "9")
        or c == "_"
end

local function tokenise(src)
    local tokens = {}
    local i = 1
    local n = #src

    local function emit(kind, value, a, b)
        tokens[#tokens + 1] = { kind = kind, value = value, start = a, stop = b }
    end

    while i <= n do
        local c = string.sub(src, i, i)

        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            i = i + 1

        elseif c == "\"" then
            -- Quoted string. No escape handling in GoblinScript.
            local a = i
            i = i + 1
            local startInner = i
            while i <= n and string.sub(src, i, i) ~= "\"" do
                i = i + 1
            end
            local text = string.sub(src, startInner, i - 1)
            if i <= n then i = i + 1 end
            emit("STRING", text, a, i - 1)

        elseif isDigit(c) or (c == "." and i + 1 <= n and isDigit(string.sub(src, i + 1, i + 1))) then
            local a = i
            while i <= n do
                local ch = string.sub(src, i, i)
                if isDigit(ch) or ch == "." then
                    i = i + 1
                else
                    break
                end
            end
            local text = string.sub(src, a, i - 1)
            emit("NUMBER", tonumber(text) or 0, a, i - 1)

        elseif c == ">" or c == "<" or c == "=" or c == "!" or c == "~" then
            local a = i
            local two = string.sub(src, i, i + 1)
            if two == ">=" or two == "<=" or two == "!=" or two == "~=" or two == "<>" then
                emit("OP", two, a, a + 1)
                i = i + 2
            else
                emit("OP", c, a, a)
                i = i + 1
            end

        elseif c == "+" or c == "-" or c == "*" or c == "/" then
            emit("OP", c, i, i)
            i = i + 1

        elseif c == "(" or c == ")" or c == "," then
            emit("PUNCT", c, i, i)
            i = i + 1

        elseif c == "." then
            emit("PUNCT", ".", i, i)
            i = i + 1

        elseif isWordChar(c) then
            local a = i
            while i <= n and isWordChar(string.sub(src, i, i)) do
                i = i + 1
            end
            local word = string.sub(src, a, i - 1)
            local lower = string.lower(word)
            if KEYWORD_OPS[lower] then
                emit("OP", lower, a, i - 1)
            elseif UNSUPPORTED_KEYWORDS[lower] then
                emit("UNSUPPORTED", lower, a, i - 1)
            else
                emit("WORD", word, a, i - 1)
            end

        else
            -- Unknown character; emit as an opaque token so the parser can
            -- bail and the whole expression falls back to raw text.
            emit("UNKNOWN", c, i, i)
            i = i + 1
        end
    end

    -- Pass 1.5: demote OP("has") / OP("is") to WORD when they cannot be
    -- a keyword-operator. GoblinScript treats these as operators only when
    -- a left-hand expression precedes them (symbol like "Has Attacker" is
    -- a legal multi-word identifier). We approximate: if the previous
    -- non-whitespace token isn't an expression-end (IDENT / NUMBER / STRING
    -- / ")" / "."), treat the word as a plain word.
    local function isExprEnd(t)
        if t == nil then return false end
        if t.kind == "IDENT" or t.kind == "WORD" or t.kind == "NUMBER" or t.kind == "STRING" then return true end
        if t.kind == "PUNCT" and t.value == ")" then return true end
        return false
    end
    for k = 1, #tokens do
        local t = tokens[k]
        if t.kind == "OP" and (t.value == "has" or t.value == "is") then
            if not isExprEnd(tokens[k - 1]) then
                t.kind = "WORD"
                t.value = (t.value == "has") and "Has" or "Is"
            end
        end
    end

    -- Second pass: merge adjacent WORDs into multi-word IDENTs, and merge
    -- "is not" / "has not" into a single OP.
    local merged = {}
    local k = 1
    while k <= #tokens do
        local t = tokens[k]
        if t.kind == "WORD" then
            local parts = { t.value }
            local startPos = t.start
            local stopPos = t.stop
            while tokens[k + 1] and tokens[k + 1].kind == "WORD" do
                k = k + 1
                parts[#parts + 1] = tokens[k].value
                stopPos = tokens[k].stop
            end
            merged[#merged + 1] = {
                kind = "IDENT",
                value = table.concat(parts, " "),
                start = startPos,
                stop = stopPos,
            }
        elseif t.kind == "OP" and (t.value == "is" or t.value == "has")
                and tokens[k + 1] and tokens[k + 1].kind == "OP" and tokens[k + 1].value == "not" then
            merged[#merged + 1] = {
                kind = "OP",
                value = t.value .. " not",
                start = t.start,
                stop = tokens[k + 1].stop,
            }
            k = k + 1
        else
            merged[#merged + 1] = t
        end
        k = k + 1
    end

    return merged
end

--------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------
-- Produces a mini-AST. Node shapes:
--   { type = "or",      children = {...} }
--   { type = "and",     children = {...} }
--   { type = "not",     child = ... }
--   { type = "compare", op = ">=", left = <atom>, right = <atom> }
--   { type = "isEq",    negated = bool, left = <atom>, right = <atom> }
--   { type = "hasEq",   negated = bool, left = <atom>, right = <atom> }
--   { type = "bool",    atom = <atom> }
--   { type = "raw",     text = "..." }
-- Atoms:
--   { kind = "ident",  name = "Damage Type", parts = {"Damage Type"} }
--   { kind = "dotted", parts = {"Subject", "Stamina"} }
--   { kind = "number", value = 5 }
--   { kind = "string", value = "fire" }
--   { kind = "call",   name = "Distance", args = {<atom>, ...} }
-- On failure to consume, functions return nil and the caller records a raw
-- span to be rendered as the literal source substring.

local Parser = {}

local function newState(tokens, src)
    return { tokens = tokens, src = src, pos = 1 }
end

local function peek(st, offset)
    return st.tokens[st.pos + (offset or 0)]
end

local function consume(st)
    local t = st.tokens[st.pos]
    st.pos = st.pos + 1
    return t
end

local function rawSpan(src, a, b)
    if a == nil or b == nil then return "" end
    return string.sub(src, a, b)
end

local function parseExpr(st) return Parser.parseOr(st) end

function Parser.parseAtomCall(st)
    -- Parse a qualified identifier (dotted) possibly followed by a call.
    local first = peek(st)
    if first == nil or first.kind ~= "IDENT" then return nil end
    consume(st)
    local parts = { first.value }
    local startPos = first.start
    local stopPos = first.stop
    while peek(st) and peek(st).kind == "PUNCT" and peek(st).value == "." do
        consume(st)
        local nxt = peek(st)
        if nxt == nil or nxt.kind ~= "IDENT" then return nil end
        consume(st)
        parts[#parts + 1] = nxt.value
        stopPos = nxt.stop
    end

    -- Function call?
    if peek(st) and peek(st).kind == "PUNCT" and peek(st).value == "(" then
        consume(st)
        local args = {}
        if peek(st) and not (peek(st).kind == "PUNCT" and peek(st).value == ")") then
            while true do
                local argAtom = Parser.parseAtom(st)
                if argAtom == nil then return nil end
                args[#args + 1] = argAtom
                local nxt = peek(st)
                if nxt and nxt.kind == "PUNCT" and nxt.value == "," then
                    consume(st)
                else
                    break
                end
            end
        end
        local close = peek(st)
        if close == nil or close.kind ~= "PUNCT" or close.value ~= ")" then return nil end
        consume(st)
        stopPos = close.stop
        return {
            kind = "call",
            name = table.concat(parts, "."),
            parts = parts,
            args = args,
            start = startPos,
            stop = stopPos,
        }
    end

    if #parts > 1 then
        return {
            kind = "dotted",
            parts = parts,
            name = table.concat(parts, "."),
            start = startPos,
            stop = stopPos,
        }
    end
    return {
        kind = "ident",
        name = parts[1],
        parts = parts,
        start = startPos,
        stop = stopPos,
    }
end

function Parser.parseAtom(st)
    local t = peek(st)
    if t == nil then return nil end

    if t.kind == "NUMBER" then
        consume(st)
        return { kind = "number", value = t.value, start = t.start, stop = t.stop }
    elseif t.kind == "STRING" then
        consume(st)
        return { kind = "string", value = t.value, start = t.start, stop = t.stop }
    elseif t.kind == "PUNCT" and t.value == "(" then
        -- Parenthesised sub-expression treated as an atom when appearing in
        -- comparison position. But parens can also wrap full boolean
        -- expressions. Strategy: parse the inner expression, require ")",
        -- and wrap in a "paren" atom so comparison-level checks can see it.
        consume(st)
        local inner = parseExpr(st)
        if inner == nil then return nil end
        local close = peek(st)
        if close == nil or close.kind ~= "PUNCT" or close.value ~= ")" then return nil end
        consume(st)
        return {
            kind = "paren",
            inner = inner,
            start = t.start,
            stop = close.stop,
        }
    elseif t.kind == "IDENT" then
        return Parser.parseAtomCall(st)
    end
    return nil
end

local COMPARE_OPS = {
    [">="] = true, ["<="] = true, [">"] = true, ["<"] = true,
    ["="] = true, ["!="] = true, ["~="] = true, ["<>"] = true,
}

function Parser.parseAtomCmp(st)
    local save = st.pos
    local left = Parser.parseAtom(st)
    if left == nil then st.pos = save; return nil end

    local t = peek(st)

    -- If the atom is a parenthesised expression and no comparison operator
    -- follows, unwrap the paren so the inner boolean tree is rendered
    -- through our normal composition rules rather than falling back to raw.
    if left.kind == "paren" then
        local followed = t and t.kind == "OP" and (COMPARE_OPS[t.value]
            or t.value == "is" or t.value == "is not"
            or t.value == "has" or t.value == "has not")
        if not followed then
            return left.inner
        end
    end

    if t == nil then
        -- bare leaf; wrapper decides whether it's a boolean standalone.
        return { type = "atom", atom = left, start = left.start, stop = left.stop }
    end

    if t.kind == "OP" and COMPARE_OPS[t.value] then
        consume(st)
        local right = Parser.parseAtom(st)
        if right == nil then st.pos = save; return nil end
        return {
            type = "compare",
            op = t.value,
            left = left,
            right = right,
            start = left.start,
            stop = right.stop,
        }
    elseif t.kind == "OP" and (t.value == "is" or t.value == "is not") then
        consume(st)
        local right = Parser.parseAtom(st)
        if right == nil then st.pos = save; return nil end
        return {
            type = "isEq",
            negated = (t.value == "is not"),
            left = left,
            right = right,
            start = left.start,
            stop = right.stop,
        }
    elseif t.kind == "OP" and (t.value == "has" or t.value == "has not") then
        consume(st)
        local right = Parser.parseAtom(st)
        if right == nil then st.pos = save; return nil end
        return {
            type = "hasEq",
            negated = (t.value == "has not"),
            left = left,
            right = right,
            start = left.start,
            stop = right.stop,
        }
    end

    return { type = "atom", atom = left, start = left.start, stop = left.stop }
end

function Parser.parseUnary(st)
    local t = peek(st)
    if t and t.kind == "OP" and t.value == "not" then
        consume(st)
        local inner = Parser.parseUnary(st)
        if inner == nil then return nil end
        return { type = "not", child = inner, start = t.start, stop = inner.stop }
    end
    return Parser.parseAtomCmp(st)
end

function Parser.parseAnd(st)
    local first = Parser.parseUnary(st)
    if first == nil then return nil end
    if not (peek(st) and peek(st).kind == "OP" and peek(st).value == "and") then
        return first
    end
    local children = { first }
    local startPos = first.start
    local stopPos = first.stop
    while peek(st) and peek(st).kind == "OP" and peek(st).value == "and" do
        consume(st)
        local nxt = Parser.parseUnary(st)
        if nxt == nil then return nil end
        children[#children + 1] = nxt
        stopPos = nxt.stop
    end
    return { type = "and", children = children, start = startPos, stop = stopPos }
end

function Parser.parseOr(st)
    local first = Parser.parseAnd(st)
    if first == nil then return nil end
    if not (peek(st) and peek(st).kind == "OP" and peek(st).value == "or") then
        return first
    end
    local children = { first }
    local startPos = first.start
    local stopPos = first.stop
    while peek(st) and peek(st).kind == "OP" and peek(st).value == "or" do
        consume(st)
        local nxt = Parser.parseAnd(st)
        if nxt == nil then return nil end
        children[#children + 1] = nxt
        stopPos = nxt.stop
    end
    return { type = "or", children = children, start = startPos, stop = stopPos }
end

local function parseFormula(tokens, src)
    local st = newState(tokens, src)
    local node = parseExpr(st)
    if node == nil then return nil end
    -- Refuse if trailing tokens remain or unsupported keywords encountered.
    while st.pos <= #st.tokens do
        if st.tokens[st.pos].kind == "UNSUPPORTED" or st.tokens[st.pos].kind == "UNKNOWN" then
            return nil
        end
        -- Any leftover tokens we did not expect: bail to raw fallback.
        return nil
    end
    return node
end

--------------------------------------------------------------------------
-- Parse cache
--------------------------------------------------------------------------
-- Public walkers (Render, RenderTriggerSentence -> Render,
-- ListReferencedSymbols, ListReferencedDottedAccesses, WalkLiteralComparisons,
-- ExtractSatisfyingValues, AttributeFailure, RenderDebug) all tokenise the
-- same conditionFormula independently. A single Mech-View / test-card refresh
-- runs 5-7 of them on the same string today, paying tokenise + parseFormula
-- on every call. Both functions are pure with respect to the formula string,
-- and consumers iterate tokens / AST nodes read-only, so memoising the
-- (tokens, ast) pair by formula string is safe.
--
-- Bounded MRU-by-insertion: cap at PARSE_CACHE_CAPACITY entries; on overflow
-- evict the oldest. Hit rate during an editing session is high (the same
-- formula sticks around between keystrokes on other fields).
--
-- INVARIANT (do not break): consumers must NEVER mutate the returned tokens
-- table or AST node tree. They are shared state. All current consumers are
-- read-only by inspection (ipairs / field reads only). Add a fresh-copy step
-- here if a future consumer needs to mutate.
local PARSE_CACHE_CAPACITY = 32
local _parseCache = {}
local _parseCacheOrder = {}

local function getParsed(formula)
    if formula == nil or formula == "" then return nil, nil end
    local cached = _parseCache[formula]
    if cached ~= nil then return cached.tokens, cached.ast end
    local ok, tokens = pcall(tokenise, formula)
    if not ok or tokens == nil then return nil, nil end
    local astOk, ast = pcall(parseFormula, tokens, formula)
    if not astOk then ast = nil end
    if #_parseCacheOrder >= PARSE_CACHE_CAPACITY then
        local victim = table.remove(_parseCacheOrder, 1)
        _parseCache[victim] = nil
    end
    _parseCache[formula] = { tokens = tokens, ast = ast }
    _parseCacheOrder[#_parseCacheOrder + 1] = formula
    return tokens, ast
end

--------------------------------------------------------------------------
-- Prose rendering
--------------------------------------------------------------------------
-- Renders an AST node. Falls back to the literal source substring when a
-- node's shape (or any descendant's) does not match a launch-tier pattern.

local Render = {}

-- Forward declaration so Render.atomNode's De Morgan branch can call
-- joinChain (defined further down). Lua locals don't resolve forward.
local joinChain

local function resolveEntry(entry, ctx)
    if entry == nil then return nil end
    if type(entry) == "string" then return entry end
    if type(entry) == "table" and entry.dynamic then
        if entry.dynamic == "subject" then
            local e = GoblinScriptProse.subjectProse[ctx and ctx.subject or ""]
            return e and e.role
        elseif entry.dynamic == "speed" then
            return GoblinScriptProse.speedProse[ctx and ctx.trigger or ""]
        elseif entry.dynamic == "quantity" then
            return GoblinScriptProse.quantityProse[ctx and ctx.trigger or ""]
        end
    end
    if type(entry) == "table" and entry.role then
        return entry.role
    end
    return nil
end

-- Resolve a role entry specifically for possessive-position use (dotted
-- access fallback). Subject returns its possessive form directly; entries
-- with explicit role/possessive forms (e.g. Self -> you/your) return their
-- possessive directly; other roles are static strings that we suffix with
-- "'s" to produce the possessive form on the fly.
local function resolveRoleAsPossessive(entry, ctx)
    if entry == nil then return nil end
    if type(entry) == "table" and entry.dynamic == "subject" then
        local e = GoblinScriptProse.subjectProse[ctx and ctx.subject or ""]
        return e and e.possessive
    end
    if type(entry) == "table" and entry.possessive then
        return entry.possessive
    end
    local role = resolveEntry(entry, ctx)
    if role == nil then return nil end
    return role .. "'s"
end

--------------------------------------------------------------------------
-- Inline trigger-symbol prose (one-place registration)
--------------------------------------------------------------------------
-- Trigger payload symbols (Damage, Damage Type, Attacker, ...) declare
-- their prose alongside name/type/desc on the trigger.symbols entry in
-- TriggeredAbility.lua, e.g.
--     damage = {
--         name = "Damage",
--         type = "number",
--         desc = "...",
--         prose = "the damage",
--     }
-- For creature-typed roles that compose dotted access ("Attacker.Stamina"
-- -> "the attacker's stamina"), the possessive auto-derives from the
-- noun phrase via "+'s" suffix, or you can set `prosePossessive`
-- explicitly when the auto form is wrong (e.g. irregular pronouns; the
-- {role, possessive} table shape is also accepted on `prose` itself for
-- pronoun cases like Self).
--
-- The lookup at lookupSymbol consults this map BEFORE the centralised
-- `GoblinScriptProse.symbols` / `.roles` tables, so an inline `prose`
-- field always wins over a stale central registration. Existing central
-- entries continue to work unchanged for symbols that haven't been
-- migrated -- migration is opt-in and per-symbol.
--
-- Cache is built lazily on the first lookup that names a trigger we
-- haven't seen yet. Trigger registrations are static after module load
-- in production; hot-reload scenarios can clear via
-- `GoblinScriptProse._invalidateTriggerSymbolsCache()` if needed.
local _triggerSymbolsByName = nil

local function buildTriggerSymbolsCache()
    local cache = {}
    if rawget(_G, "TriggeredAbility") == nil then return cache end
    local triggers = rawget(TriggeredAbility, "triggers")
    if type(triggers) ~= "table" then return cache end
    for _, t in ipairs(triggers) do
        if type(t) == "table" and t.id and type(t.symbols) == "table" then
            local byName = {}
            for k, v in pairs(t.symbols) do
                if type(v) == "table" then
                    -- Symbol identity is the runtime injection key, which
                    -- is always derived from the symbol NAME (lowercased,
                    -- whitespace-stripped). Numeric-key array-form entries
                    -- carry their name in v.name; keyed-map entries may
                    -- have a name distinct from the table key (e.g. key
                    -- "ability" with name "Used Ability"). Always prefer
                    -- v.name when present.
                    local symName = v.name or (type(k) == "string" and k or nil)
                    if symName ~= nil then
                        byName[normalise(symName)] = v
                    end
                end
            end
            cache[t.id] = byName
        end
    end
    return cache
end

local function getTriggerSymbols(triggerId)
    if triggerId == nil or triggerId == "" then return nil end
    if _triggerSymbolsByName == nil then
        _triggerSymbolsByName = buildTriggerSymbolsCache()
    end
    return _triggerSymbolsByName[triggerId]
end

function GoblinScriptProse._invalidateTriggerSymbolsCache()
    _triggerSymbolsByName = nil
end

-- Look up prose for a symbol or dotted name. Returns a string fragment
-- ready to drop into a sentence, or nil if unknown. For dotted names not
-- explicitly registered, falls back to composing "<role prose>'s <tail>"
-- when the first part is a registered role symbol (Attacker, Subject, etc.)
-- -- this covers the long-tail `Attacker.Level`, `Subject.Stamina`, etc.
-- without needing every creature property pre-enumerated.
local function lookupSymbol(parts, ctx)
    if parts == nil or #parts == 0 then return nil end

    -- Inline prose on the active trigger's payload symbols. Co-locates
    -- prose with the symbol declaration in TriggeredAbility.lua so
    -- adding a new symbol is a one-file edit. See the inline-prose block
    -- comment above buildTriggerSymbolsCache for the schema.
    --
    -- Single-part inline check fires BEFORE the central full-key lookup
    -- below; otherwise a single-part name (e.g. "damage") would match
    -- `GoblinScriptProse.symbols[full]` first and the inline override
    -- would never run. Multi-part dotted-access composition is handled
    -- further down (after the central full-key check, so explicit dotted
    -- registrations like "Ability.name" still win).
    local triggerSymbols = ctx and ctx.trigger and getTriggerSymbols(ctx.trigger)
    if #parts == 1 and triggerSymbols then
        local single = normalise(parts[1])
        local entry = triggerSymbols[single]
        if entry and entry.prose then
            local inlineResolved = resolveEntry(entry.prose, ctx)
            if inlineResolved then return inlineResolved end
        end
    end

    local full = normalise(table.concat(parts, "."))
    local resolved = resolveEntry(GoblinScriptProse.symbols[full], ctx)
    if resolved then return resolved end

    if #parts == 1 then
        local single = normalise(parts[1])
        resolved = resolveEntry(GoblinScriptProse.symbols[single], ctx)
        if resolved then return resolved end
        -- A bare role symbol (e.g. just "Attacker") also reads as its
        -- noun-phrase prose.
        return resolveEntry(GoblinScriptProse.roles[single], ctx)
    end

    -- Compose <role-possessive> <tail> if the parent is a known role.
    -- Possessive form is resolved directly (Subject -> `your`/`that enemy's`)
    -- rather than via "+'s" suffix so second-person pronouns compose
    -- correctly (never `"you's stamina"`).
    local parentKey = normalise(parts[1])
    local possessive = nil

    -- Inline composition: honour `prosePossessive` if present, else the
    -- {role, possessive} shape on `prose`, else auto-derive from `prose`
    -- via "+'s" suffix.
    if triggerSymbols then
        local entry = triggerSymbols[parentKey]
        if entry then
            if entry.prosePossessive then
                possessive = entry.prosePossessive
            elseif type(entry.prose) == "table" and entry.prose.possessive then
                possessive = entry.prose.possessive
            elseif entry.prose then
                local noun = resolveEntry(entry.prose, ctx)
                if noun then possessive = noun .. "'s" end
            end
        end
    end

    if possessive == nil then
        possessive = resolveRoleAsPossessive(GoblinScriptProse.roles[parentKey], ctx)
    end
    if possessive == nil then return nil end
    local tailParts = {}
    for i = 2, #parts do tailParts[#tailParts + 1] = string.lower(parts[i]) end
    return possessive .. " " .. table.concat(tailParts, " ")
end

local function lookupFunction(name)
    return GoblinScriptProse.functions[normalise(name)]
end

-- Atom prose in noun-phrase position (left side of a comparison, or a
-- function argument). Returns fragment and whether lookup succeeded.
local function atomNounPhrase(atom, ctx)
    if atom == nil then return nil, false end
    if atom.kind == "number" then
        return tostring(atom.value), true
    elseif atom.kind == "string" then
        return atom.value, true
    elseif atom.kind == "ident" or atom.kind == "dotted" then
        local frag = lookupSymbol(atom.parts, ctx)
        if frag then return frag, true end
        return table.concat(atom.parts, "."), false
    elseif atom.kind == "call" then
        return Render.renderCall(atom, ctx)
    elseif atom.kind == "paren" then
        -- Treat a parenthesised expression in comparison position as a raw
        -- sub-expression -- prose-rendering a nested boolean as a noun
        -- phrase doesn't compose cleanly under the launch grammar.
        return nil, false
    end
    return nil, false
end

-- Render a value on the right-hand side of a string equality / set
-- membership comparison. Strings render unquoted.
local function atomRightSide(atom, ctx)
    if atom == nil then return nil, false end
    if atom.kind == "string" then return atom.value, true end
    if atom.kind == "number" then return tostring(atom.value), true end
    return atomNounPhrase(atom, ctx)
end

-- Function call prose. Uses template with {1}, {2}, ... placeholders filled
-- from the argument atoms. Returns (fragment, ok).
function Render.renderCall(node, ctx)
    local template = lookupFunction(node.name)
    if template == nil and node.parts and #node.parts > 1 then
        -- Try the last component alone. This lets `Self.Distance(X)` reuse
        -- the global `Distance` template when no method-specific prose is
        -- registered -- the implicit self receiver is usually obvious in
        -- context ("the distance to the attacker").
        template = lookupFunction(node.parts[#node.parts])
    end
    if template == nil then return nil, false end
    local args = {}
    for i, a in ipairs(node.args) do
        local f, ok = atomNounPhrase(a, ctx)
        if not ok or f == nil then
            args[i] = "?"
        else
            args[i] = f
        end
    end
    local rendered = string.gsub(template, "{(%d+)}", function(idx)
        return args[tonumber(idx)] or "?"
    end)
    return rendered, true
end

-- Pattern 3: numeric comparison ("Damage >= 5" -> "the damage is at least 5")
local COMPARE_PROSE = {
    [">="] = "is at least",
    ["<="] = "is at most",
    [">"]  = "is more than",
    ["<"]  = "is less than",
    ["="]  = "equals",
    ["!="] = "does not equal",
    ["~="] = "does not equal",
    ["<>"] = "does not equal",
}

function Render.compareNode(node, ctx, src)
    local lhs, lhsOk = atomNounPhrase(node.left, ctx)
    local rhs, rhsOk = atomNounPhrase(node.right, ctx)
    if not lhs or not rhs then return rawSpan(src, node.start, node.stop) end
    local word = COMPARE_PROSE[node.op] or "compared to"
    -- If the lhs lookup failed (unknown symbol), fall back to raw source so
    -- we don't emit half-prose like "Foo is at least 5".
    if not lhsOk then return rawSpan(src, node.start, node.stop) end
    return lhs .. " " .. word .. " " .. rhs
end

-- Pattern 4: string equality ("Damage Type is 'fire'" -> "the damage type is fire")
function Render.isEqNode(node, ctx, src)
    local lhs, lhsOk = atomNounPhrase(node.left, ctx)
    local rhs = atomRightSide(node.right, ctx)
    if not lhs or not rhs or not lhsOk then
        return rawSpan(src, node.start, node.stop)
    end
    return lhs .. (node.negated and " is not " or " is ") .. rhs
end

-- Pattern 5: set membership ("Keywords has 'Melee'" -> "the damage keywords include Melee")
function Render.hasEqNode(node, ctx, src)
    local lhs, lhsOk = atomNounPhrase(node.left, ctx)
    local rhs = atomRightSide(node.right, ctx)
    if not lhs or not rhs or not lhsOk then
        return rawSpan(src, node.start, node.stop)
    end
    return lhs .. (node.negated and " do not include " or " include ") .. rhs
end

-- Pattern 1 & 2: bare boolean and negated boolean.
function Render.atomBoolNode(atom, ctx, src, negated)
    if atom == nil then return rawSpan(src, 0, 0) end
    if atom.kind == "ident" or atom.kind == "dotted" then
        -- Classification-boolean prose for dotted access on a role head.
        -- `Self.Winded`, `Subject.Solo`, `Subject.Leader` etc. previously
        -- rendered as "your winded" / "your solo" via the possessive form,
        -- which reads as if the property were a possession. These are
        -- actually classification states -- "are you winded?", "is the
        -- subject a solo?". Render with copula form when the head is a
        -- role; "Has X"-prefixed tails switch to have-form.
        if atom.kind == "dotted" and atom.parts and #atom.parts >= 2 then
            local parentKey = normalise(atom.parts[1])
            local roleNoun, roleCop, roleCopNeg = nil, nil, nil
            if parentKey == "self" then
                roleNoun, roleCop, roleCopNeg = "you", "are", "are not"
            elseif parentKey == "caster" then
                roleNoun, roleCop, roleCopNeg = "the aura caster", "is", "is not"
            elseif parentKey == "subject" then
                local e = GoblinScriptProse.subjectProse[(ctx and ctx.subject) or ""]
                    or GoblinScriptProse.subjectProse["self"]
                if e then
                    roleNoun = e.role
                    -- Subject phrasings containing "you" take "are";
                    -- singular "any X" / "another X" / "the X" take "is".
                    if string.find(string.lower(roleNoun), "you", 1, true) then
                        roleCop, roleCopNeg = "are", "are not"
                    else
                        roleCop, roleCopNeg = "is", "is not"
                    end
                end
            end
            if roleNoun then
                local tailWords = {}
                for i = 2, #atom.parts do
                    tailWords[#tailWords + 1] = string.lower(atom.parts[i])
                end
                local tail = table.concat(tailWords, " ")
                -- "Has X" tail switches to have-form: "you have a shield"
                -- / "you do not have a shield".
                local hasRest = string.match(tail, "^has%s+(.+)$")
                if hasRest then
                    local haveVerb, haveVerbNeg
                    if roleNoun == "you" or string.find(string.lower(roleNoun), "you", 1, true) then
                        haveVerb, haveVerbNeg = "have", "do not have"
                    else
                        haveVerb, haveVerbNeg = "has", "does not have"
                    end
                    return roleNoun .. " " .. (negated and haveVerbNeg or haveVerb) .. " " .. hasRest
                end
                return roleNoun .. " " .. (negated and roleCopNeg or roleCop) .. " " .. tail
            end
        end
        local frag = lookupSymbol(atom.parts, ctx)
        if frag == nil then return rawSpan(src, atom.start, atom.stop) end
        -- Check for a boolean-specific phrasing. Convention in
        -- TRIGGER_SYMBOL_PROSE.md: boolean prose fragments are written as
        -- noun-verb clauses already ("the movement was forced", "has an
        -- attacker"). Negation adds "not" before the final verb.
        if negated then
            -- Inject " not" after the first auxiliary verb we recognise.
            -- Lua patterns have no alternation so we try each candidate in
            -- turn. Auxiliaries are ordered most-specific-first. "has" is
            -- rewritten to "does not have" since "has not X" reads wrong.
            local AUX_SUBS = {
                {"^(.-)(%s+)is(%s+)",   "%1%2is not%3"},
                {"^(.-)(%s+)was(%s+)",  "%1%2was not%3"},
                {"^(.-)(%s+)were(%s+)", "%1%2were not%3"},
                {"^(.-)(%s+)are(%s+)",  "%1%2are not%3"},
                {"^(.-)(%s+)have(%s+)", "%1%2do not have%3"},
                {"^has(%s+)",           "does not have%1"},
                {"^is(%s+)",            "is not%1"},
            }
            for _, sub in ipairs(AUX_SUBS) do
                local replaced, count = string.gsub(frag, sub[1], sub[2], 1)
                if count > 0 then return replaced end
            end
            return "it is not the case that " .. frag
        end
        return frag
    elseif atom.kind == "call" then
        local frag, ok = Render.renderCall(atom, ctx)
        if not ok then return rawSpan(src, atom.start, atom.stop) end
        return negated and ("it is not the case that " .. frag) or frag
    elseif atom.kind == "paren" then
        return rawSpan(src, atom.start, atom.stop)
    end
    return rawSpan(src, atom.start or 0, atom.stop or 0)
end

-- Main dispatch for a single "atom-level" node (the building block for
-- boolean composition).
function Render.atomNode(node, ctx, src)
    if node.type == "compare" then
        return Render.compareNode(node, ctx, src)
    elseif node.type == "isEq" then
        return Render.isEqNode(node, ctx, src)
    elseif node.type == "hasEq" then
        return Render.hasEqNode(node, ctx, src)
    elseif node.type == "atom" then
        return Render.atomBoolNode(node.atom, ctx, src, false)
    elseif node.type == "not" then
        local inner = node.child
        if inner and inner.type == "atom" then
            return Render.atomBoolNode(inner.atom, ctx, src, true)
        end
        -- not applied to a comparison: negate by flipping the connective.
        if inner and inner.type == "compare" then
            local flip = { [">="] = "<", ["<="] = ">", [">"] = "<=", ["<"] = ">=",
                           ["="] = "!=", ["!="] = "=", ["~="] = "=", ["<>"] = "=" }
            local flipped = {
                type = "compare",
                op = flip[inner.op] or inner.op,
                left = inner.left,
                right = inner.right,
                start = inner.start,
                stop = inner.stop,
            }
            return Render.compareNode(flipped, ctx, src)
        end
        if inner and (inner.type == "isEq" or inner.type == "hasEq") then
            local flipped = {
                type = inner.type,
                negated = not inner.negated,
                left = inner.left,
                right = inner.right,
                start = inner.start,
                stop = inner.stop,
            }
            if inner.type == "isEq" then return Render.isEqNode(flipped, ctx, src) end
            return Render.hasEqNode(flipped, ctx, src)
        end
        -- P5: De Morgan distribution for not(or)/not(and). Real bestiary
        -- formulas like `not (Subject.Leader or Subject.Solo)` would
        -- previously fall through to rawSpan and emit the literal source.
        -- Distributing the negation produces natural prose:
        --   not (A or B) = not A and not B
        --   not (A and B) = not A or not B
        if inner and (inner.type == "or" or inner.type == "and") then
            local newConn = (inner.type == "or") and "and" or "or"
            local parts = {}
            for _, child in ipairs(inner.children or {}) do
                local negated = {
                    type = "not",
                    child = child,
                    start = child.start,
                    stop = child.stop,
                }
                parts[#parts + 1] = Render.node(negated, ctx, src)
            end
            return joinChain(parts, newConn)
        end
        return rawSpan(src, node.start, node.stop)
    end
    return rawSpan(src, node.start or 0, node.stop or 0)
end

-- Assigns the forward-declared joinChain so atomNode's De Morgan branch
-- can resolve it. Note: this is `joinChain = function(...)` (assignment),
-- NOT `local function joinChain` (which would shadow the forward decl).
joinChain = function(parts, connective)
    if #parts == 0 then return "" end
    if #parts == 1 then return parts[1] end
    if #parts == 2 then return parts[1] .. " " .. connective .. " " .. parts[2] end
    local body = {}
    for i = 1, #parts - 1 do body[i] = parts[i] end
    return table.concat(body, ", ") .. ", " .. connective .. " " .. parts[#parts]
end

-- P5: render a child of an and/or node, wrapping it in literal parens
-- when its connective differs from the parent's. English doesn't carry
-- AND/OR precedence the way GoblinScript does, so `(A or B) and C`
-- otherwise reads as `A or B and C` -- ambiguous in English, parses as
-- `A or (B and C)`. Adding visual parens keeps the rendered prose
-- unambiguous without forcing more elaborate rewrites. Atom-level
-- children render without parens.
local function renderChildForBoolean(child, parentConn, ctx, src)
    local rendered = Render.node(child, ctx, src)
    if rendered == nil or rendered == "" then return rendered end
    if (parentConn == "and" and child.type == "or")
            or (parentConn == "or" and child.type == "and") then
        return "(" .. rendered .. ")"
    end
    return rendered
end

-- Render any node (boolean composition or atom-level).
function Render.node(node, ctx, src)
    if node.type == "and" then
        local parts = {}
        for i, child in ipairs(node.children) do
            parts[i] = renderChildForBoolean(child, "and", ctx, src)
        end
        return joinChain(parts, "and")
    elseif node.type == "or" then
        local parts = {}
        for i, child in ipairs(node.children) do
            parts[i] = renderChildForBoolean(child, "or", ctx, src)
        end
        return joinChain(parts, "or")
    end
    return Render.atomNode(node, ctx, src)
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

-- Render a GoblinScript formula string as plain-English prose.
-- ctx fields:
--   subject  -- ability.subject id, for the dynamic Subject symbol
--   trigger  -- trigger id, for dynamic Speed / Quantity symbols
-- Returns the rendered prose, or the raw formula on any failure.
function GoblinScriptProse.Render(formula, ctx)
    if formula == nil or formula == "" then return "" end
    local ok, result = pcall(function()
        local tokens, ast = getParsed(formula)
        if tokens == nil or #tokens == 0 then return formula end
        if ast == nil then return formula end
        return Render.node(ast, ctx or {}, formula)
    end)
    if not ok or result == nil or result == "" then
        return formula
    end
    return result
end

-- Event prose templates, keyed by trigger id. Locked 2026-04-24 rev 2 via
-- TRIGGER_EVENT_PROSE.md. Placeholders:
--   {subject}             -- subject role prose (you / any enemy / ...)
--   {subject-possessive}  -- subject possessive form (your / that enemy's / ...)
--   {s}                   -- -s agreement suffix (empty when subject == "you")
--   {es}                  -- -es agreement suffix (empty when subject == "you")
--   {is}                  -- "is" or "are" agreement (are when subject == "you")
-- Global events (no subject dependency) omit every subject placeholder.
GoblinScriptProse.eventProse = {
    -- Common band
    losehitpoints     = "when {subject} take{s} damage",
    dealdamage        = "when {subject} deal{s} damage to an enemy",
    rollpower         = "when {subject} make{s} a power roll",
    inflictcondition  = "when a condition is applied to {subject}",
    useability        = "when {subject} use{s} an ability",
    beginturn         = "at the start of {subject-possessive} turn",

    -- Combat band
    attack            = "when {subject} attack{s} an enemy",
    dying             = "when {subject} become{s} dying",
    winded            = "when {subject} become{s} winded",
    fallenon          = "when a creature lands on {subject}",
    creaturedeath     = "when {subject} die{s}",
    zerohitpoints     = "when {subject} drop{s} to 0 stamina",
    gaintempstamina   = "when {subject} gain{s} temporary stamina",
    kill              = "when {subject} kill{s} a creature",
    saveagainstdamage = "when {subject} make{s} a reactive roll against damage",
    regainhitpoints   = "when {subject} regain{s} stamina",

    -- Abilities & Power Rolls band
    finishability     = "when {subject} finish{es} using an ability",
    targetwithability = "when {subject} {is} targeted by an ability",
    castsignature     = "when {subject} use{s} a signature ability or area ability",

    -- Movement band
    leaveadjacent     = "when a creature adjacent to {subject} moves away",
    move              = "when {subject} begin{s} moving",
    wallbreak         = "when {subject} break{s} through a wall",
    collide           = "when {subject} collide{s} with a creature or object",
    finishmove        = "when {subject} finish{es} moving",
    forcemove         = "when {subject} {is} force moved",
    fall              = "when {subject} land{s} from a fall",
    movethrough       = "when {subject} move{s} through another creature",
    pressureplate     = "when {subject} step{s} on a pressure plate",
    teleport          = "when {subject} teleport{s}",

    -- Resources & Victory band
    earnvictory       = "when {subject} earn{s} a victory",
    gainresource      = "when {subject} gain{s} a resource",
    useresource       = "when {subject} spend{s} a resource",

    -- Turn & Game Mode band
    prestartturn      = "just before the start of {subject-possessive} turn",
    rollinitiative    = "at the start of combat",
    endcombat         = "at the end of combat",
    endrespite        = "when {subject} end{s} a respite",
    endturn           = "at the end of {subject-possessive} turn",
    startdowntime     = "when {subject} start{s} downtime",
    beginround        = "at the start of each round",
    startrespite      = "when {subject} start{s} a respite",

    -- Custom band
    custom            = "when a custom trigger fires on {subject}",

    -- 5e-derived (dnd5e.lua runs in DS; 7 compendium entries use this)
    attacked          = "when {subject} {is} attacked",
}

-- Compose a full trigger sentence: `[Event phrase][, if [condition phrase]].`
-- Uses the ability's subject + trigger fields to pick the right template and
-- the matching subject prose; optionally appends the condition prose produced
-- by GoblinScriptProse.Render. Used by the Trigger Preview card's Trigger row
-- and the Mechanical View's when-clause.
--
-- Fallbacks, from worst to best:
--   * Unknown trigger id -> synthesised "when {subject} triggers" template so
--     a sentence is still produced.
--   * Unknown subject id -> falls back to a generic "the creature" prose.
--   * Condition formula unrecognised -> prose engine returns raw formula;
--     we still join with "if" so the clause structure stays intact.
function GoblinScriptProse.RenderTriggerSentence(ability, options)
    if ability == nil then return "" end
    options = options or {}

    local subjectId = ability:try_get("subject") or "self"
    local triggerId = ability:try_get("trigger") or ""
    local conditionFormula = ability:try_get("conditionFormula") or ""

    local subjectEntry = GoblinScriptProse.subjectProse[subjectId]
        or { role = "the creature", possessive = "the creature's" }

    local template = GoblinScriptProse.eventProse[triggerId]
    if template == nil or template == "" then
        template = "when {subject} triggers"
    end

    local rendered = template
    rendered = string.gsub(rendered, "{subject%-possessive}", subjectEntry.possessive)
    rendered = string.gsub(rendered, "{subject}", subjectEntry.role)

    -- Verb agreement. Only strip {s}/{es} (and substitute "are" for {is})
    -- when the subject text is exactly "you". Compound subjects like
    -- "you or any ally" keep 3rd-singular via the proximity rule.
    local baseForm = (subjectEntry.role == "you")
    if baseForm then
        rendered = string.gsub(rendered, "{s}", "")
        rendered = string.gsub(rendered, "{es}", "")
        rendered = string.gsub(rendered, "{is}", "are")
    else
        rendered = string.gsub(rendered, "{s}", "s")
        rendered = string.gsub(rendered, "{es}", "es")
        rendered = string.gsub(rendered, "{is}", "is")
    end

    -- Capitalise first letter.
    if #rendered > 0 then
        rendered = string.upper(string.sub(rendered, 1, 1)) .. string.sub(rendered, 2)
    end

    -- Append condition clause if present.
    if conditionFormula ~= "" then
        local conditionProse = GoblinScriptProse.Render(conditionFormula, {
            subject = subjectId,
            trigger = triggerId,
        })
        if conditionProse ~= nil and conditionProse ~= "" then
            rendered = rendered .. ", if " .. conditionProse
        end
    end

    return rendered .. "."
end

-- Debug entry point: returns (prose, ast, tokens) for dry-runs.
function GoblinScriptProse.RenderDebug(formula, ctx)
    local tokens, ast = getParsed(formula or "")
    local prose = GoblinScriptProse.Render(formula, ctx)
    return prose, ast, tokens
end

--------------------------------------------------------------------------
-- ListReferencedSymbols
--------------------------------------------------------------------------
-- Returns a sequence of distinct top-level identifier names referenced by
-- the formula. Used by the Test Trigger panel to discover which event
-- payload symbols and role tokens the author's condition actually touches,
-- so the panel only renders an input row per relevant symbol.
--
-- Top-level only: `Attacker.Keywords` contributes "Attacker", not
-- "Attacker.Keywords". Function names also count (`Distance(Subject)`
-- contributes "Distance" and "Subject"). Numbers, strings, and operator
-- keywords are skipped.
--
-- Returns a list-style table preserving first-seen order, plus a parallel
-- set table keyed by lowercased name for membership checks.
function GoblinScriptProse.ListReferencedSymbols(formula)
    local list, set = {}, {}
    if formula == nil or formula == "" then return list, set end
    local tokens = getParsed(formula)
    if tokens == nil then return list, set end
    for k, t in ipairs(tokens) do
        if t.kind == "IDENT" then
            -- Skip dotted-tail identifiers (Attacker.Keywords -> only
            -- "Attacker" matters; Keywords is a property accessor, not a
            -- symbol the editor needs an input row for).
            local prev = tokens[k - 1]
            local isDottedTail = prev and prev.kind == "PUNCT" and prev.value == "."
            -- Skip function-call identifiers (Distance(...), Friends(...))
            -- -- these are operators, not symbols, and don't need inputs or
            -- declared registrations to be valid.
            local nxt = tokens[k + 1]
            local isCall = nxt and nxt.kind == "PUNCT" and nxt.value == "("
            -- Skip identifiers that appear as the RHS of an is/has comparison.
            -- GoblinScript treats `Resource is Recovery` as equivalent to
            -- `Resource is "Recovery"` -- the bare ident is shorthand for the
            -- string literal, not a symbol reference. Real bestiary content
            -- relies on this shorthand widely (Resource is Recovery / Main
            -- Action, Damage Type is fire/acid/cold/..., Condition is Dazed,
            -- Trigger Name is madesave, subject.type is Gnoll, etc.).
            -- The tokeniser merges multi-word RHS ("Main Action") into a
            -- single IDENT, so a single look-back at the immediate previous
            -- OP token suffices.
            local isRhsLiteral = prev and prev.kind == "OP"
                and (prev.value == "is" or prev.value == "is not"
                     or prev.value == "has" or prev.value == "has not")
            if not isDottedTail and not isCall and not isRhsLiteral then
                local key = string.lower(t.value)
                if set[key] == nil then
                    set[key] = t.value
                    list[#list + 1] = t.value
                end
            end
        end
    end
    return list, set
end

--------------------------------------------------------------------------
-- ListReferencedDottedAccesses
--------------------------------------------------------------------------
-- Walks the formula's tokens and returns a map of dotted-access paths the
-- author has used, keyed by lowercased head. Each value carries the
-- original-cased head/tail strings plus an "opHint" describing what kind
-- of value the leaf is being compared against, so the Test Trigger panel
-- can pick the right input widget without re-parsing.
--
-- Multi-word identifiers (e.g. `Used Ability`) are joined with a single
-- space and lookup keys collapse the space (so `usedability` matches the
-- runtime injection identity that GoblinScript uses). Tails are
-- normalised by `string.lower` to compare identity but we keep the
-- original-case version for display.
--
-- Op-hint logic:
--   - immediately followed by `has` -> "has"          (set/StringSet)
--   - followed by `is`/`=`/`!=`     -> "compare-str"  (text)
--   - followed by `>=`/`<=`/`>`/`<` -> "compare-num"  (number)
--   - bare (followed by `and`/`or`/end) -> "bool"
-- Caller can override the hint per-tail if a different shape is preferred.
--
-- Returns a map of the form:
--   { ["used ability"] = {
--       displayHead = "Used Ability",
--       lookupKey   = "usedability",   -- runtime injection key
--       tails = {
--         keywords = { displayTail = "Keywords", opHint = "has" },
--         name     = { displayTail = "name",     opHint = "compare-str" },
--       },
--     }, ... }
function GoblinScriptProse.ListReferencedDottedAccesses(formula)
    local result = {}
    if formula == nil or formula == "" then return result end
    local tokens = getParsed(formula)
    if tokens == nil then return result end

    -- Multi-word identifiers in GoblinScript are produced by the tokeniser
    -- as a single IDENT token whose value contains spaces (e.g. "Used
    -- Ability"). We don't need to re-coalesce; just consume IDENT tokens
    -- and look one token ahead for the dot.
    local function deriveHint(opTokenValue, opTokenKind)
        if opTokenValue == nil then return "bool" end
        local v = string.lower(opTokenValue or "")
        if v == "has" then return "has" end
        if v == "is" or v == "=" or v == "!=" then return "compare-str" end
        if v == ">=" or v == "<=" or v == ">" or v == "<" then
            return "compare-num"
        end
        if v == "and" or v == "or" then return "bool" end
        if opTokenKind == "PUNCT" and (v == ")" or v == "(") then return "bool" end
        return "bool"
    end

    for k, t in ipairs(tokens) do
        if t.kind == "IDENT" then
            local nextDot = tokens[k + 1]
            if nextDot and nextDot.kind == "PUNCT" and nextDot.value == "." then
                local tail = tokens[k + 2]
                if tail and tail.kind == "IDENT" then
                    local head = t.value
                    local lookupKey = string.lower(string.gsub(head, "%s+", ""))
                    local mapKey = string.lower(head)
                    local entry = result[mapKey]
                    if entry == nil then
                        entry = {
                            displayHead = head,
                            lookupKey = lookupKey,
                            tails = {},
                        }
                        result[mapKey] = entry
                    end

                    local opTok = tokens[k + 3]
                    -- Skip a function-call paren after the tail; e.g.
                    -- `Path.DistanceToCreature(Self) <= 1` -- the tail is
                    -- being CALLED, not compared. Skip emitting an input
                    -- for it. Same for chained dot (e.g. `Cast.X.Y`).
                    local isCall = opTok and opTok.kind == "PUNCT" and opTok.value == "("
                    local isChain = opTok and opTok.kind == "PUNCT" and opTok.value == "."
                    if not isCall and not isChain then
                        local tailKey = string.lower(tail.value)
                        if entry.tails[tailKey] == nil then
                            entry.tails[tailKey] = {
                                displayTail = tail.value,
                                opHint = deriveHint(opTok and opTok.value, opTok and opTok.kind),
                            }
                        end
                    end
                end
            end
        end
    end

    return result
end

--------------------------------------------------------------------------
-- ListReferencedChainedAccesses
--------------------------------------------------------------------------
-- Walks the formula's tokens and returns a list of 3-deep chained dotted
-- accesses (`<a>.<b>.<c>`). Used by the Test Trigger panel to surface
-- per-resource numeric overrides for chains like `Subject.Resources.Recovery`,
-- `Resources.Surges`, and `Self.Resources.Hero Tokens` -- ListReferencedDottedAccesses
-- intentionally skips chains (it only emits 2-deep accesses), so the
-- override system needed a parallel walker for the 3-deep case.
--
-- Returns a list of `{head, mid, tail, opHint, headLookup, midLookup, tailLookup}`
-- where:
--   head/mid/tail = original-cased identifier strings
--   *Lookup       = lowercase + space-stripped form (matches runtime injection
--                   identity)
--   opHint        = same shape as ListReferencedDottedAccesses
-- Chains 4+ deep are NOT emitted (no real-world usage), but each adjacent
-- triple in a longer chain produces its own entry, so a 4-deep chain like
-- `A.B.C.D` would emit two entries (A.B.C and B.C.D) -- callers can dedup
-- on (head, mid, tail).
function GoblinScriptProse.ListReferencedChainedAccesses(formula)
    local result = {}
    if formula == nil or formula == "" then return result end
    local tokens = getParsed(formula)
    if tokens == nil then return result end

    local function deriveHint(opTokenValue, opTokenKind)
        if opTokenValue == nil then return "bool" end
        local v = string.lower(opTokenValue or "")
        if v == "has" then return "has" end
        if v == "is" or v == "=" or v == "!=" then return "compare-str" end
        if v == ">=" or v == "<=" or v == ">" or v == "<" then
            return "compare-num"
        end
        if v == "and" or v == "or" then return "bool" end
        if opTokenKind == "PUNCT" and (v == ")" or v == "(") then return "bool" end
        return "bool"
    end

    local function norm(s)
        if type(s) ~= "string" then return "" end
        return string.lower(string.gsub(s, "%s+", ""))
    end

    for k, t in ipairs(tokens) do
        if t.kind == "IDENT" then
            local d1 = tokens[k + 1]
            local mid = tokens[k + 2]
            local d2 = tokens[k + 3]
            local tail = tokens[k + 4]
            if d1 and d1.kind == "PUNCT" and d1.value == "."
                    and mid and mid.kind == "IDENT"
                    and d2 and d2.kind == "PUNCT" and d2.value == "."
                    and tail and tail.kind == "IDENT" then
                local opTok = tokens[k + 5]
                -- Skip if tail is being called (`A.B.C(...)`) or extended
                -- into a 4+ chain (`A.B.C.D` -- emit per-triple still
                -- handles via the overlapping window).
                local isCall = opTok and opTok.kind == "PUNCT" and opTok.value == "("
                if not isCall then
                    result[#result + 1] = {
                        head = t.value,
                        mid = mid.value,
                        tail = tail.value,
                        headLookup = norm(t.value),
                        midLookup = norm(mid.value),
                        tailLookup = norm(tail.value),
                        opHint = deriveHint(opTok and opTok.value, opTok and opTok.kind),
                    }
                end
            end
        end
    end

    return result
end

--------------------------------------------------------------------------
-- WalkLiteralComparisons
--------------------------------------------------------------------------
-- Walks the AST of a formula and invokes the callback once for each leaf
-- where the RHS is a string literal: hasEq, isEq, and compare(=) shapes.
-- Used by the Mech View to validate string literals against canonical
-- tables (e.g. flag a typo'd ongoing effect name). Skips silently if the
-- formula doesn't parse.
--
-- Callback signature: callback(info) where info = {
--   op      = "has" | "is" | "=" | "!=" -- which operator
--   lhs     = <atom>   -- the LHS atom (kind = "ident" / "dotted" / "call")
--   rhs     = <string> -- the unquoted literal value
--   rhsKind = "string" | "ident" -- "string" for quoted RHS ("Recovery"),
--             "ident" for bare-ident RHS (Recovery). GoblinScript treats
--             the latter as an implicit string literal in is/is-not RHS
--             position, so consumers that validate against canonical tables
--             (resources, conditions, damage types, ongoing effects) should
--             treat both kinds the same. has/has-not don't appear with bare
--             RHS in real content, so this only fires for isEq.
--   negated = bool   -- true for "is not" / "has not" / "!="
-- }
function GoblinScriptProse.WalkLiteralComparisons(formula, callback)
    if formula == nil or formula == "" then return end
    if type(callback) ~= "function" then return end

    pcall(function()
        local tokens, ast = getParsed(formula)
        if tokens == nil or #tokens == 0 then return end
        if ast == nil then return end

        -- Resolve a bare-ident or dotted RHS atom to the implicit string
        -- literal it represents in is/is-not RHS position. Returns the
        -- ident's display name (e.g. "Recovery", "Main Action") -- the
        -- normalisation matches the case-insensitive comparison runtime
        -- semantics. Returns nil for any other atom shape (calls, paren'd
        -- sub-expressions, numbers).
        local function rhsIdentName(atom)
            if atom == nil then return nil end
            if atom.kind == "ident" then return atom.name end
            if atom.kind == "dotted" and atom.parts then
                -- Dotted RHS like `Subject.X` is rare and probably refers
                -- to an actual property -- don't treat as literal.
                return nil
            end
            return nil
        end

        local function visit(node)
            if node == nil then return end
            if node.type == "and" or node.type == "or" then
                for _, child in ipairs(node.children) do visit(child) end
                return
            end
            if node.type == "not" and node.child then
                visit(node.child)
                return
            end
            if node.type == "hasEq" and node.right then
                if node.right.kind == "string" then
                    callback({
                        op = "has",
                        lhs = node.left,
                        rhs = node.right.value,
                        rhsKind = "string",
                        negated = node.negated or false,
                    })
                    return
                end
                local identName = rhsIdentName(node.right)
                if identName ~= nil then
                    callback({
                        op = "has",
                        lhs = node.left,
                        rhs = identName,
                        rhsKind = "ident",
                        negated = node.negated or false,
                    })
                    return
                end
            end
            if node.type == "isEq" and node.right then
                if node.right.kind == "string" then
                    callback({
                        op = "is",
                        lhs = node.left,
                        rhs = node.right.value,
                        rhsKind = "string",
                        negated = node.negated or false,
                    })
                    return
                end
                local identName = rhsIdentName(node.right)
                if identName ~= nil then
                    callback({
                        op = "is",
                        lhs = node.left,
                        rhs = identName,
                        rhsKind = "ident",
                        negated = node.negated or false,
                    })
                    return
                end
            end
            if node.type == "compare" and node.right and node.right.kind == "string"
                and (node.op == "=" or node.op == "!=" or node.op == "~=" or node.op == "<>") then
                callback({
                    op = node.op == "=" and "=" or "!=",
                    lhs = node.left,
                    rhs = node.right.value,
                    rhsKind = "string",
                    negated = node.op ~= "=",
                })
                return
            end
        end

        visit(ast)
    end)
end

--------------------------------------------------------------------------
-- ExtractSatisfyingValues
--------------------------------------------------------------------------
-- Walks a condition formula's AST and returns a map of
-- `{[symbolName] = suggestedValue}` that, if fed into the evaluator,
-- would satisfy the condition. Used by the Test Trigger panel to
-- pre-fill inputs so the "happy path" (Passes) is the default state;
-- the author then edits values to see failure modes.
--
-- Heuristics per leaf shape (skips anything ambiguous):
--   X >= N          -> {X = N}
--   X > N           -> {X = N + 1}
--   X <= N          -> {X = N}
--   X < N           -> {X = N - 1}
--   X = N / X is V  -> {X = N / V}
--   X has "v"       -> {X = {v = true}}
--   not X           -> {X = false}       (X must be an ident)
--   bare X          -> {X = true}
--   X != N          -> skip (no canonical satisfying value)
--   X OP Y (both syms) -> skip (no literal)
--   OR chain        -> pre-fill from FIRST branch only (any branch satisfies)
--   AND chain       -> recurse into every child
--
-- Returns an empty table if the formula doesn't parse cleanly.
function GoblinScriptProse.ExtractSatisfyingValues(formula)
    local out = {}
    if formula == nil or formula == "" then return out end

    local ok = pcall(function()
        local tokens, ast = getParsed(formula)
        if tokens == nil or #tokens == 0 then return end
        if ast == nil then return end

        local function atomIdent(atom)
            if atom == nil then return nil end
            if atom.kind == "ident" then return atom.name end
            if atom.kind == "dotted" and atom.parts and #atom.parts == 2 then
                -- Two-part dotted atoms are pre-fillable when the head
                -- corresponds to an object-typed trigger symbol (ability,
                -- spellcast, path, loc) -- the test panel surfaces a
                -- per-tail input row keyed as `<lookupKey>.<tail_lower>`,
                -- where lookupKey strips whitespace from the head and
                -- both halves are lowercased. Match that key shape so
                -- the prefill latches onto the right input row.
                -- For creature-typed heads (Subject, Attacker, ...) the
                -- caller's prefill is harmless: the synthesised key
                -- won't match any input id (creature heads are role
                -- slots, not symbol inputs) and the entry is ignored.
                local head = string.lower(string.gsub(atom.parts[1], "%s+", ""))
                local tail = string.lower(atom.parts[2])
                return head .. "." .. tail
            end
            return nil
        end

        local function setIfAbsent(key, value)
            if key == nil then return end
            if out[key] ~= nil then return end
            out[key] = value
        end

        local function walkLeaf(node)
            if node.type == "compare" then
                local name = atomIdent(node.left)
                if name == nil then return end
                -- GoblinScript's "=" accepts either numeric or string RHS
                -- ('Damage Type = "fire"' is equivalent to '... is "fire"').
                -- Handle both; skip other combinations as ambiguous.
                if node.right.kind == "number" then
                    local n = node.right.value
                    if node.op == ">=" then setIfAbsent(name, n)
                    elseif node.op == ">" then setIfAbsent(name, n + 1)
                    elseif node.op == "<=" then setIfAbsent(name, n)
                    elseif node.op == "<" then setIfAbsent(name, n - 1)
                    elseif node.op == "=" then setIfAbsent(name, n)
                    end
                elseif node.right.kind == "string" and node.op == "=" then
                    setIfAbsent(name, node.right.value)
                end
            elseif node.type == "isEq" and not node.negated then
                local name = atomIdent(node.left)
                if name == nil then return end
                if node.right.kind == "string" then setIfAbsent(name, node.right.value)
                elseif node.right.kind == "number" then setIfAbsent(name, node.right.value)
                elseif node.right.kind == "ident" and node.right.name then
                    -- Bare-ident RHS is the engine's implicit-string-literal
                    -- shorthand (`Resource is Recovery` ~= `Resource is "Recovery"`).
                    -- Treat it as the literal so the test panel pre-fills the
                    -- dropdown to the named resource. Same intent as quoted RHS.
                    setIfAbsent(name, node.right.name)
                end
            elseif node.type == "hasEq" and not node.negated then
                local name = atomIdent(node.left)
                if name == nil then return end
                if node.right.kind == "string" then
                    setIfAbsent(name, { [node.right.value] = true })
                elseif node.right.kind == "ident" and node.right.name then
                    setIfAbsent(name, { [node.right.name] = true })
                end
            elseif node.type == "atom" then
                local name = atomIdent(node.atom)
                if name ~= nil then setIfAbsent(name, true) end
            elseif node.type == "not" and node.child and node.child.type == "atom" then
                local name = atomIdent(node.child.atom)
                if name ~= nil then setIfAbsent(name, false) end
            end
        end

        local function walk(node)
            if node.type == "and" then
                for _, child in ipairs(node.children) do walk(child) end
            elseif node.type == "or" then
                if #node.children > 0 then walk(node.children[1]) end
            else
                walkLeaf(node)
            end
        end

        walk(ast)
    end)

    if not ok then return {} end
    return out
end

--------------------------------------------------------------------------
-- AttributeFailure
--------------------------------------------------------------------------
-- Walks the AST of a failing condition formula and reports which leaf
-- clause caused the failure. Used by the Test Trigger panel's result block
-- to translate a top-level "false" into actionable feedback like
-- *"`damagetype is "fire"` returned false"* instead of just *"Fails"*.
--
-- evalLeaf is a callback (srcText -> value, errMsg) supplied by the editor.
-- It compiles + executes a substring of the original formula against the
-- same symbol context the parent eval used. Side effects in conditions are
-- vanishingly rare in practice (the launch-grammar leaves are pure: bool
-- symbols, numeric compares, string equality, set membership, function
-- calls without dispatcher mutation).
--
-- Returns one of:
--   nil
--     Formula didn't parse (raw fallback) or had no boolean composition to
--     attribute. Editor falls back to the top-level "fails" message.
--   { kind = "and", failingProse, failingSrc, failingValue, failingError }
--     Top-level (or recursive) AND chain: the named leaf returned false.
--   { kind = "or", clauses = { {prose, src, value, error}, ... } }
--     Top-level OR chain: every leaf returned false; lists each.
--   { kind = "leaf", prose, src, value, error }
--     Single leaf condition that returned false. Lets the editor render the
--     prose form even when there's no chain to traverse.
function GoblinScriptProse.AttributeFailure(formula, ctx, evalLeaf)
    if formula == nil or formula == "" then return nil end
    if type(evalLeaf) ~= "function" then return nil end

    local ok, result = pcall(function()
        local tokens, ast = getParsed(formula)
        if tokens == nil or #tokens == 0 then return nil end
        if ast == nil then return nil end

        local proseCtx = ctx or {}

        -- Lookup units for a function-call atom. Mirrors Render.renderCall:
        -- try the full dotted name (Self.Distance), fall through to the
        -- trailing component (Distance) so method-style and global calls
        -- share registration where it makes sense.
        local function lookupCallUnits(atom)
            if atom == nil or atom.kind ~= "call" then return nil end
            local u = GoblinScriptProse.functionUnits[normalise(atom.name)]
            if u == nil and atom.parts and #atom.parts > 1 then
                u = GoblinScriptProse.functionUnits[normalise(atom.parts[#atom.parts])]
            end
            return u
        end

        -- Detect whether a function-call atom has registered prose. Mirrors
        -- the same dotted -> tail fallback as Render.renderCall.
        local function callHasProse(atom)
            if atom == nil or atom.kind ~= "call" then return false end
            if GoblinScriptProse.functions[normalise(atom.name)] then return true end
            if atom.parts and #atom.parts > 1
                and GoblinScriptProse.functions[normalise(atom.parts[#atom.parts])] then
                return true
            end
            return false
        end

        -- Format a number for prose detail lines. tostring(5.0) -> "5.0";
        -- string.format("%g", 5.0) -> "5". Falls back to raw tostring for
        -- non-numbers so callers can pass through gracefully.
        local function formatNumber(v)
            local n = tonumber(v)
            if n == nil then return tostring(v) end
            return string.format("%g", n)
        end

        -- Build the optional "got" detail string for shapes C2 covers:
        --   Shape A: <funcCall> <op> N        -> "the distance to the attacker was 5 squares."
        --   Shape B: <funcCall>               -> "" (suppress; headline is self-sufficient)
        --   Shape C: not <funcCall>           -> "" (suppress; headline is self-sufficient)
        -- Returns:
        --   nil    -- caller falls back to the generic "Formula clause ... evaluated to ..." line
        --   ""     -- caller intentionally suppresses the detail line
        --   string -- caller uses the string verbatim
        -- Capitalise the first ASCII letter of a string, preserving the
        -- rest verbatim. Used so the detail line reads as a sentence
        -- ("The distance to the attacker was 6 squares.") rather than
        -- starting lowercase ("the distance ...").
        local function capitaliseFirst(s)
            if s == nil or s == "" then return s end
            return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
        end

        local function buildFailingDetail(node)
            if node == nil then return nil end
            if node.type == "compare" and node.left and node.left.kind == "call"
                and callHasProse(node.left) then
                local lhsSrc = rawSpan(formula, node.left.start, node.left.stop)
                if lhsSrc == nil or lhsSrc == "" then return nil end
                local v, err = evalLeaf(lhsSrc)
                if err ~= nil or v == nil then return nil end
                local lhsPhrase = atomNounPhrase(node.left, proseCtx)
                if lhsPhrase == nil then return nil end
                local units = lookupCallUnits(node.left)
                local valueText = formatNumber(v)
                local phrase = capitaliseFirst(lhsPhrase)
                if units and units ~= "" then
                    return phrase .. " was " .. valueText .. " " .. units .. "."
                end
                return phrase .. " was " .. valueText .. "."
            elseif node.type == "atom" and node.atom and node.atom.kind == "call"
                and callHasProse(node.atom) then
                return ""
            elseif node.type == "not" and node.child and node.child.type == "atom"
                and node.child.atom and node.child.atom.kind == "call"
                and callHasProse(node.child.atom) then
                return ""
            end
            return nil
        end

        -- Recursive walker. For AND chains we descend into the first
        -- failing child (recursing into nested ANDs). For OR chains we
        -- collect every child (since OR-fail means all returned false).
        -- Leaves render via the existing prose engine.
        local function leafInfo(node, value, errMsg)
            local prose = Render.node(node, proseCtx, formula)
            local src = rawSpan(formula, node.start, node.stop)
            return {
                prose = prose,
                src = src,
                value = value,
                error = errMsg,
                detail = buildFailingDetail(node),
            }
        end

        local function walk(node)
            if node.type == "and" then
                for _, child in ipairs(node.children) do
                    local childSrc = rawSpan(formula, child.start, child.stop)
                    local v, err = evalLeaf(childSrc)
                    if err ~= nil then
                        local info = leafInfo(child, v, err)
                        return {
                            kind = "and",
                            failingProse = info.prose,
                            failingSrc = info.src,
                            failingValue = info.value,
                            failingError = info.error,
                            failingDetail = info.detail,
                        }
                    end
                    if tonumber(v) == 0 or v == false or v == nil then
                        if child.type == "and" or child.type == "or"
                                or (child.type == "not" and child.child
                                    and (child.child.type == "or" or child.child.type == "and")) then
                            local nested = walk(child)
                            if nested ~= nil then return nested end
                        end
                        local info = leafInfo(child, v, nil)
                        return {
                            kind = "and",
                            failingProse = info.prose,
                            failingSrc = info.src,
                            failingValue = info.value,
                            failingError = info.error,
                            failingDetail = info.detail,
                        }
                    end
                end
                return nil
            elseif node.type == "or" then
                local clauses = {}
                for _, child in ipairs(node.children) do
                    local childSrc = rawSpan(formula, child.start, child.stop)
                    local v, err = evalLeaf(childSrc)
                    local info = leafInfo(child, v, err)
                    -- P6: drill into OR-of-AND. A child that's itself an
                    -- AND has a specific failing leaf inside it -- recurse
                    -- and attach so the consumer can render "needed X
                    -- (A failed inside the AND)" or similar. Other compound
                    -- shapes (nested OR, not-compound) get the same
                    -- recursive lookup. Keep the top-level info so the
                    -- existing renderer keeps working unchanged.
                    if (child.type == "and" or child.type == "or"
                            or (child.type == "not" and child.child
                                and (child.child.type == "or" or child.child.type == "and"))) then
                        local nested = walk(child)
                        if nested ~= nil then
                            info.subAttr = nested
                        end
                    end
                    clauses[#clauses + 1] = info
                end
                return { kind = "or", clauses = clauses }
            elseif node.type == "not" and node.child
                    and (node.child.type == "or" or node.child.type == "and") then
                -- P6: not(or)/not(and) attribution. The outer not failed,
                -- so the inner expression evaluated to TRUE. List the
                -- clauses inside the inner that were truthy -- those are
                -- the ones the user needs to flip off.
                local inner = node.child
                local trueClauses = {}
                for _, child in ipairs(inner.children or {}) do
                    local childSrc = rawSpan(formula, child.start, child.stop)
                    local v, err = evalLeaf(childSrc)
                    if err == nil and not (tonumber(v) == 0 or v == false or v == nil) then
                        trueClauses[#trueClauses + 1] = leafInfo(child, v, nil)
                    end
                end
                return {
                    kind = "not-compound",
                    innerKind = inner.type,
                    trueClauses = trueClauses,
                }
            else
                local nodeSrc = rawSpan(formula, node.start, node.stop)
                local v, err = evalLeaf(nodeSrc)
                local info = leafInfo(node, v, err)
                return {
                    kind = "leaf",
                    prose = info.prose,
                    src = info.src,
                    value = info.value,
                    error = info.error,
                    detail = info.detail,
                }
            end
        end

        return walk(ast)
    end)

    if not ok then return nil end
    return result
end

--------------------------------------------------------------------------
-- Launch-tier vocabulary
--------------------------------------------------------------------------
-- Symbol / function / role prose for the triggered ability condition
-- engine. Sourced verbatim from TRIGGER_SYMBOL_PROSE.md (locked 2026-04-24).
-- DEFER-tagged entries are intentionally omitted -- they fall back to raw
-- formula in real authoring until real-world usage pulls them into scope.
-- The three dynamic-prose symbols (Subject, Speed, Quantity) are declared
-- as { dynamic = "..." } so Render.lookupSymbol swaps in the per-trigger
-- fragment at call time.

do
    local S = GoblinScriptProse.RegisterSymbolProse
    local F = GoblinScriptProse.RegisterFunctionProse
    local R = GoblinScriptProse.RegisterRoleProse

    -- Ambient role tokens. `Self` always renders as second-person ("you" /
    -- "your") to match Draw Steel's player-facing card voice (see
    -- TRIGGER_SYMBOL_PROSE.md voice decision 2026-04-24). `Subject` is
    -- per-trigger dynamic (renders "any enemy" / "any ally" / "you" etc.
    -- depending on ability.subject filter id). When ability.subject="self",
    -- Subject also renders as "you" -- which makes Self and Subject naturally
    -- coreferential in that case (which they are at runtime).
    S("Subject", { dynamic = "subject" })
    S("Self", { role = "you", possessive = "your" })
    R("Subject", { dynamic = "subject" })
    R("Self", { role = "you", possessive = "your" })
    S("Caster", "the aura caster")
    R("Caster", "the aura caster")

    -- Damage-themed event payload.
    S("Damage", "the damage")
    S("Raw Damage", "the raw damage (before immunity)")
    S("Damage Type", "the damage type")
    S("Damage Immunity", "the damage was modified by immunity or weakness")
    S("Keywords", "the damage keywords")
    S("Has Rolled Damage", "the damage was rolled")

    -- Ability-themed event payload.
    S("Ability", "the ability used")
    R("Ability", "the used ability")
    S("Used Ability", "the ability used")
    R("Used Ability", "the used ability")
    S("Has Ability", "the event came from an ability")

    -- Attacker / Target / role tokens.
    S("Attacker", "the attacker")
    R("Attacker", "the attacker")
    S("Has Attacker", "there is an attacker")
    S("Target", "the target")
    R("Target", "the target")

    -- Power roll results.
    S("Natural Roll", "the natural roll")
    S("High Roll", "the high die")
    S("Low Roll", "the low die")
    S("Surges", "the number of surges")
    S("Edges", "the number of edges")
    S("Banes", "the number of banes")
    S("Tier One", "any target got a tier one result")
    S("Tier Two", "any target got a tier two result")
    S("Tier Three", "any target got a tier three result")

    -- Movement-themed event payload.
    S("Path", "the movement path")
    R("Path", "the movement path")
    S("Speed", { dynamic = "speed" })
    S("Movement Type", "the movement type")
    S("Type", "the forced movement type")
    S("Vertical", "the movement was vertical")
    S("Pusher", "the pusher")
    R("Pusher", "the pusher")
    S("With Object", "the collision was with an object")
    S("With Creature", "the collision was with a creature")
    S("Moving Creature", "the moving creature")
    R("Moving Creature", "the moving creature")
    S("Falling Creature", "the falling creature")
    R("Falling Creature", "the falling creature")
    S("Landed on Creature", "the subject landed on a creature")
    S("Wall Type", "the wall type")

    -- Condition / resource / turn flow.
    S("Condition", "the applied condition")
    S("Resource", "the resource")
    S("Quantity", { dynamic = "quantity" })
    S("XP Gained", "the XP gained")
    S("Order", "the turn order position")

    -- Custom trigger.
    S("Trigger Name", "the custom trigger name")
    S("Trigger Value", "the custom trigger value")

    -- Ability property launch subset (accessed via Ability.X / Used Ability.X).
    S("Ability.name", "the used ability's name")
    S("Ability.keywords", "the used ability's keywords")
    S("Ability.doesdamage", "the ability used does damage")
    S("Ability.categorization", "the used ability's categorization")
    S("Ability.heroicresourcecost", "the used ability's heroic resource cost")
    S("Ability.hasforcedmovement", "the ability used has forced movement")
    S("Ability.heroic", "the ability used is heroic")
    S("Ability.malicecost", "the used ability's malice cost")
    S("Ability.freestrike", "the ability used is a free strike")
    S("Ability.hasattack", "the ability used has an attack")
    S("Ability.hasheal", "the ability used heals")
    -- Mirror under Used Ability since authors use both names.
    S("Used Ability.name", "the used ability's name")
    S("Used Ability.keywords", "the used ability's keywords")
    S("Used Ability.doesdamage", "the ability used does damage")
    S("Used Ability.categorization", "the used ability's categorization")
    S("Used Ability.heroicresourcecost", "the used ability's heroic resource cost")
    S("Used Ability.hasforcedmovement", "the ability used has forced movement")
    S("Used Ability.heroic", "the ability used is heroic")
    S("Used Ability.malicecost", "the used ability's malice cost")
    S("Used Ability.freestrike", "the ability used is a free strike")
    S("Used Ability.hasattack", "the ability used has an attack")
    S("Used Ability.hasheal", "the ability used heals")

    -- Cast / Spellcast property launch subset.
    R("Cast", "the cast")
    S("Cast.primarytarget", "the primary target")
    S("Cast.primary", "the primary target")
    S("Cast.tier", "the cast's tier")
    S("Cast.damagedealt", "the damage dealt by the cast")
    S("Cast.damage", "the damage dealt by the cast")
    S("Cast.roll", "the cast's roll")
    F("Cast.passespotency", "{1} passes the potency check")
    F("Cast.memory", "the cast's memory of {1}")
    F("Cast.tierfortarget", "the cast's tier against {1}")
    F("Cast.hastarget", "the cast targets {1}")

    -- Path property launch subset.
    S("Path.forced", "the movement was forced")
    S("Path.squares", "the distance moved")
    S("Path.shift", "the movement was a shift")
    S("Path.verticalonly", "the movement was vertical-only")
    F("Path.DistanceToCreature", "the closest the movement came to {1}")

    -- Global / built-in functions.
    F("Distance", "the distance to {1}")
    F("Friends", "{1} and {2} are friends")
    F("Line of Sight", "there is line of sight to {1}")
    F("Substring", "{2} appears in {1}")
    F("Count Nearby Enemies", "the number of nearby enemies within {1}")
    F("Count Nearby Allies", "the number of nearby allies within {1}")
    F("Stacks", "the number of stacks of {1}")
    F("min", "the smaller of {1} and {2}")
    F("max", "the larger of {1} and {2}")
    F("floor", "{1} rounded down")
    F("ceiling", "{1} rounded up")
end

-- Units annotation for numeric-returning functions. Used by AttributeFailure
-- to produce richer detail lines like "the distance to the attacker was 5
-- squares." Lookup mirrors Render.renderCall: try the full dotted name first,
-- then the trailing component (so Self.Distance reuses Distance's units).
GoblinScriptProse.functionUnits = {}

function GoblinScriptProse.RegisterFunctionUnits(name, units)
    GoblinScriptProse.functionUnits[normalise(name)] = units
end

do
    local U = GoblinScriptProse.RegisterFunctionUnits
    U("Distance", "squares")
    U("Path.DistanceToCreature", "squares")
end

--------------------------------------------------------------------------
-- Behaviour prose
--------------------------------------------------------------------------
-- Per-behaviour-type templates wired in from BEHAVIOUR_PROSE.md (locked
-- 2026-04-24). Renders an ActivatedAbilityBehavior instance as a single
-- prose phrase, or a list of behaviours as a comma-joined sentence with
-- ", then " before the last item per the worksheet's chaining convention.
--
-- Dispatch is keyed by class name (the typeName field set on every
-- behaviour instance), not the Type.id, since typeName is reliably
-- available at runtime while the type id is only on the registry entry.
--
-- Recursive types (power_roll tiers, ongoingEffect formulas, aura
-- triggers, modifier objects) recurse through RenderBehaviour with a
-- depth counter; depth >= MAX_BEHAVIOUR_DEPTH falls back to
-- SummarizeBehavior to avoid pathological structures.

local MAX_BEHAVIOUR_DEPTH = 3

GoblinScriptProse.behaviourProse = {}

local function tryGet(obj, field, default)
    if obj == nil then return default end
    local fn = obj.try_get
    if type(fn) ~= "function" then
        local v = obj[field]
        if v == nil then return default end
        return v
    end
    local ok, v = pcall(fn, obj, field)
    if not ok or v == nil then return default end
    return v
end

local function isNonEmpty(s)
    return type(s) == "string" and s ~= ""
end

-- Lookups against runtime tables, all guarded so prose still renders if
-- the engine globals or tables are missing (e.g. in dry-run / test).
local function lookupOngoingEffectName(id)
    if not isNonEmpty(id) then return nil end
    if rawget(_G, "dmhub") == nil or type(dmhub.GetTable) ~= "function" then return nil end
    local ok, t = pcall(dmhub.GetTable, "characterOngoingEffects")
    if not ok or t == nil then return nil end
    local entry = t[id]
    if entry == nil then return nil end
    return entry.name
end

local function lookupAttributeName(id)
    if not isNonEmpty(id) then return nil end
    local C = rawget(_G, "creature")
    if C == nil or C.attributesInfo == nil then return nil end
    local entry = C.attributesInfo[id]
    if entry == nil then return nil end
    return entry.description or entry.name
end

local function lookupSkillName(id)
    if not isNonEmpty(id) then return nil end
    local S = rawget(_G, "Skill")
    if S == nil or S.SkillsById == nil then return nil end
    local entry = S.SkillsById[id]
    if entry == nil then return nil end
    return entry.name
end

local function lookupResourceName(id)
    if not isNonEmpty(id) then return nil end
    if rawget(_G, "dmhub") == nil or type(dmhub.GetTable) ~= "function" then return nil end
    local ok, t = pcall(dmhub.GetTable, "characterResources")
    if not ok or t == nil then return nil end
    local entry = t[id]
    if entry == nil then return nil end
    return entry.name
end

local function lookupConditionName(id)
    if not isNonEmpty(id) then return nil end
    if rawget(_G, "dmhub") == nil or type(dmhub.GetTable) ~= "function" then return nil end
    local ok, t = pcall(dmhub.GetTable, "charConditions")
    if not ok or t == nil then return nil end
    local entry = t[id]
    if entry == nil then return nil end
    return entry.name
end

local function lookupModifyCastParamLabel(id)
    if not isNonEmpty(id) then return nil end
    local B = rawget(_G, "ActivatedAbilityModifyCastBehavior")
    if B == nil or B.ParamsById == nil or B.Params == nil then return nil end
    local idx = B.ParamsById[id]
    if idx == nil then return nil end
    local entry = B.Params[idx]
    return entry and entry.text
end

-- Render a CharacterModifier nested inside a behaviour as its display name,
-- with a fallback to the modifier's behavior id if name is blank.
local function modifierLabel(modifier)
    if modifier == nil then return nil end
    local name = tryGet(modifier, "name", nil)
    if isNonEmpty(name) then return name end
    local b = tryGet(modifier, "behavior", nil)
    if isNonEmpty(b) then return b end
    return nil
end

-- Single-pair-or-rest renderer for opposed roll attribute lists. Worksheet:
-- "makes an opposed Might vs Might roll" / "Agility (Sleight of Hand) vs
-- Instinct". Multi-pair arrays render the first pair plus a count tail.
local function attrSkillPhrase(entry)
    if entry == nil then return nil end
    local attrName = lookupAttributeName(entry.attribute) or entry.attribute or "?"
    local skillName = lookupSkillName(entry.skill)
    if isNonEmpty(skillName) then
        return attrName .. " (" .. skillName .. ")"
    end
    return attrName
end

-- Pull the "first attribute pair" from either a single {attribute,skill}
-- table or an array of those tables. Defensive about both schemas because
-- the Lua object can hold either shape (createBehavior returns a single
-- table; the editor wraps it in an array).
local function firstAttrEntry(field)
    if field == nil then return nil end
    if field.attribute ~= nil then return field end
    if field[1] ~= nil then return field[1] end
    return nil
end

local function attrEntryCount(field)
    if field == nil then return 0 end
    if field.attribute ~= nil then return 1 end
    return #field
end

--------------------------------------------------------------------------
-- Per-behaviour templates
--------------------------------------------------------------------------
-- Functions return either a string (prose phrase) or nil to signal that
-- the engine should fall back to SummarizeBehavior / type label. Phrases
-- start with a verb ("deals", "applies", "raises") so multiple behaviours
-- chain naturally with commas.

local BP = GoblinScriptProse.behaviourProse

-- TRIVIAL --------------------------------------------------------------

BP.ActivatedAbilityDestroyBehavior = function(b, ability, depth)
    return "destroys the targeted creatures"
end

BP.ActivatedAbilityFallBehavior = function(b, ability, depth)
    return "forces the targets to fall"
end

BP.ActivatedAbilityPayAbilityCostBehavior = function(b, ability, depth)
    return "pays the ability's cost"
end

BP.ActivatedAbilityRaiseCorpseBehavior = function(b, ability, depth)
    if tryGet(b, "restoreStamina", false) then
        return "raises the corpse and restores their stamina"
    end
    return "raises the corpse"
end

BP.ActivatedAbilityForcedMovementLocBehavior = function(b, ability, depth)
    return "sets the forced-movement origin to the aura"
end

BP.ActivatedAbilityChangeTerrainBehavior = function(b, ability, depth)
    local shape = tryGet(b, "shape", "circle")
    local radius = tryGet(b, "radius", 1)
    local tile = tryGet(b, "tileid", "none")
    return string.format("paints a %s of radius %s with %s terrain", tostring(shape), tostring(radius), tostring(tile))
end

BP.ActivatedAbilityManipulateTargetLocs = function(b, ability, depth)
    local mode = tryGet(b, "mode", "floor_down")
    if mode == "floor_up" then return "shifts target locations up one floor" end
    return "shifts target locations down one floor"
end

BP.ActivatedAbilityCharacterSpeechBehavior = function(b, ability, depth)
    return "makes the creature speak"
end

BP.ActivatedAbilityCreateObjectBehavior = function(b, ability, depth)
    local objectid = tryGet(b, "objectid", nil)
    local label = isNonEmpty(objectid) and objectid or "an object"
    if tryGet(b, "randomize", false) then
        return "spawns a " .. label .. " with randomised appearance"
    end
    return "spawns a " .. label
end

-- EASY -----------------------------------------------------------------

BP.ActivatedAbilityPlaySoundBehavior = function(b, ability, depth)
    local s = tryGet(b, "soundEvent", "none")
    if not isNonEmpty(s) or s == "none" then return "plays a sound" end
    return "plays the " .. s .. " sound"
end

BP.ActivatedAbilityChangeElevationBehavior = function(b, ability, depth)
    local shape = tryGet(b, "shape", "circle")
    local radius = tryGet(b, "radius", 1)
    local height = tryGet(b, "height", "0")
    return string.format("changes the elevation of a %s of radius %s by %s",
        tostring(shape), tostring(radius), tostring(height))
end

BP.ActivatedAbilityDisguiseBehavior = function(b, ability, depth)
    local mode = tryGet(b, "mode", "target")
    if mode == "bestiary" then
        local mt = tryGet(b, "monsterType", nil)
        if isNonEmpty(mt) and mt ~= "none" then
            return "disguises the creature as a " .. mt
        end
        return "disguises the creature as a chosen monster"
    end
    return "disguises the creature as the target"
end

BP.ActivatedAbilitySetStaminaBehavior = function(b, ability, depth)
    local roll = tryGet(b, "roll", "0")
    return "sets the target's stamina to " .. tostring(roll)
end

BP.ActivatedAbilityHealBehavior = function(b, ability, depth)
    local roll = tryGet(b, "roll", "0")
    return "restores " .. tostring(roll) .. " stamina to the target"
end

-- MODERATE -------------------------------------------------------------

BP.ActivatedAbilityDamageBehavior = function(b, ability, depth)
    local roll = tryGet(b, "roll", "0")
    local damageType = tryGet(b, "damageType", "")
    local typed = isNonEmpty(damageType) and (" " .. damageType) or ""
    local phrase = "deals " .. tostring(roll) .. typed .. " damage"
    if tryGet(b, "cannotBeReduced", false) then
        phrase = phrase .. ", ignoring resistance"
    end
    if tryGet(b, "doesNotTrigger", false) then
        phrase = phrase .. ", without triggering reactions"
    end
    return phrase
end

BP.ActivatedAbilityOpposedRollBehavior = function(b, ability, depth)
    local atk = firstAttrEntry(tryGet(b, "attackAttributes", nil))
    local def = firstAttrEntry(tryGet(b, "defenseAttributes", nil))
    local atkPhrase = attrSkillPhrase(atk) or "?"
    local defPhrase = attrSkillPhrase(def) or "?"
    local phrase = "makes an opposed " .. atkPhrase .. " vs " .. defPhrase .. " roll"
    local extraAtk = math.max(0, attrEntryCount(tryGet(b, "attackAttributes", nil)) - 1)
    local extraDef = math.max(0, attrEntryCount(tryGet(b, "defenseAttributes", nil)) - 1)
    if extraAtk > 0 or extraDef > 0 then
        phrase = phrase .. " (with additional attribute options)"
    end
    return phrase
end

BP.ActivatedAbilitySaveBehavior = function(b, ability, depth)
    local rollMode = tryGet(b, "rollMode", "roll")
    local condMode = tryGet(b, "conditionsMode", "all")
    local verb = (rollMode == "purge") and "automatically clears" or "makes a save against"
    local target = (condMode == "one") and "one chosen condition" or "all conditions"
    return verb .. " " .. target
end

BP.ActivatedAbilityRememberBehavior = function(b, ability, depth)
    local memoryName = tryGet(b, "memoryName", "value")
    local calc = tryGet(b, "calculation", "0")
    return "stores " .. tostring(calc) .. " as " .. tostring(memoryName)
end

BP.ActivatedAbilityModifyCastBehavior = function(b, ability, depth)
    local paramid = tryGet(b, "paramid", "none")
    local value = tryGet(b, "value", "")
    local name = tryGet(b, "name", "")
    local paramLabel = lookupModifyCastParamLabel(paramid) or paramid
    local phrase = "modifies " .. tostring(paramLabel) .. " by " .. tostring(value)
    if isNonEmpty(name) then
        phrase = phrase .. " (" .. name .. ")"
    end
    return phrase
end

BP.ActivatedAbilityAddNewTargetsBehavior = function(b, ability, depth)
    local mode = tryGet(b, "targetMode", "add")
    if mode == "replace" then
        return "prompts the caster to choose replacement targets"
    end
    return "prompts the caster to add targets"
end

-- RECURSIVE ------------------------------------------------------------

BP.ActivatedAbilityPowerRollBehavior = function(b, ability, depth)
    local rule = tryGet(b, "rule", "")
    local base = isNonEmpty(rule)
        and ("rolls on the power table with rule " .. rule)
        or "rolls on the power table"
    local tiers = tryGet(b, "tiers", nil)
    if type(tiers) ~= "table" or depth >= MAX_BEHAVIOUR_DEPTH then
        return base
    end
    local parts = {}
    local TIER_LABELS = { "Tier 1", "Tier 2", "Tier 3" }
    for i = 1, 3 do
        local t = tiers[i]
        if isNonEmpty(t) then
            -- Strip trailing "." so the period we insert between tier
            -- clauses doesn't double up on author-written "...round." text.
            local trimmed = string.gsub(t, "%.+%s*$", "")
            parts[#parts + 1] = TIER_LABELS[i] .. ": " .. trimmed
        end
    end
    if #parts == 0 then return base end
    return base .. ". " .. table.concat(parts, ". ")
end

BP.ActivatedAbilityDrawSteelCommandBehavior = function(b, ability, depth)
    local rule = tryGet(b, "rule", "")
    if not isNonEmpty(rule) then return "resolves a power-table effect" end
    return "resolves power-table effect: " .. rule
end

BP.ActivatedAbilityApplyAbilityDurationEffect = function(b, ability, depth)
    local name = tryGet(b, "name", nil)
    local label = isNonEmpty(name) and name or "an ability duration effect"
    local moment = tryGet(b, "momentaryEffect", nil)
    local duration = moment and tryGet(moment, "duration", nil) or nil
    if isNonEmpty(duration) then
        return "applies " .. label .. " for " .. duration
    end
    return "applies " .. label
end

BP.ActivatedAbilityApplyOngoingEffectBehavior = function(b, ability, depth)
    local source = tryGet(b, "ongoingEffectSource", "specific")
    local phrase
    if source == "formula" then
        local formula = tryGet(b, "ongoingEffectFormula", "")
        local f = isNonEmpty(formula) and formula or "an unspecified rule"
        phrase = "applies an ongoing effect chosen by " .. f
    else
        local effectId = tryGet(b, "ongoingEffect", nil)
        local name = lookupOngoingEffectName(effectId) or effectId or "an ongoing effect"
        phrase = "applies " .. name
    end
    if tryGet(b, "repeatSave", false) then
        phrase = phrase .. " (save ends)"
    end
    if tryGet(b, "hasTemporaryHitpoints", false) then
        local thp = tryGet(b, "temporaryHitpoints", "0")
        phrase = phrase .. " granting " .. tostring(thp) .. " temporary stamina"
    end
    return phrase
end

BP.ActivatedAbilityAuraBehavior = function(b, ability, depth)
    local aura = tryGet(b, "auraObject", nil)
    local name = aura and tryGet(aura, "name", nil) or nil
    local radius = aura and tryGet(aura, "radius", nil) or nil
    local nameLabel = isNonEmpty(name) and name or "an aura"
    if radius ~= nil then
        return "creates an aura " .. nameLabel .. " with radius " .. tostring(radius)
    end
    return "creates " .. nameLabel
end

BP.ActivatedAbilityModifyPowerRollBehavior = function(b, ability, depth)
    local label = modifierLabel(tryGet(b, "modifier", nil)) or "an unnamed modifier"
    return "applies a power-roll modifier: " .. label
end

BP.ActivatedAbilityAugmentedAbilityBehavior = function(b, ability, depth)
    local label = modifierLabel(tryGet(b, "modifier", nil)) or "an unnamed modifier"
    return "augments the ability via " .. label
end

-- HARD -----------------------------------------------------------------

BP.ActivatedAbilityMacroBehavior = function(b, ability, depth)
    local macro = tryGet(b, "macro", "")
    if not isNonEmpty(macro) then return "executes a custom macro" end
    return "executes the macro: " .. macro
end

BP.ActivatedAbilityRecastBehavior = function(b, ability, depth)
    -- Worksheet status FALLBACK: filter is technical; default to the
    -- generic phrasing rather than dumping a long GoblinScript expression.
    return "allows recasting an eligible ability"
end

BP.ActivatedAbilityStealAbilityBehavior = function(b, ability, depth)
    local phrase = "steals an ability"
    local filter = tryGet(b, "abilityFilter", "")
    if isNonEmpty(filter) then
        phrase = phrase .. " matching " .. filter
    end
    local effectId = tryGet(b, "ongoingEffect", nil)
    if isNonEmpty(effectId) then
        local effectName = lookupOngoingEffectName(effectId) or effectId
        phrase = phrase .. " and applies " .. effectName
    end
    if tryGet(b, "durationUntilEndOfTurn", false) then
        phrase = phrase .. " until end of turn"
    else
        local duration = tryGet(b, "duration", nil)
        if isNonEmpty(duration) then
            phrase = phrase .. " for " .. duration
        end
    end
    return phrase
end

-- IMPOSSIBLE -----------------------------------------------------------

BP.ActivatedAbilityPersistenceControlBehavior = function(b, ability, depth)
    return "prompts for a persistent-cast selection"
end

BP.ActivatedAbilityRecoverySelectionBehavior = function(b, ability, depth)
    return "prompts for a recovery selection"
end

BP.ActivatedAbilityRoutineControlBehavior = function(b, ability, depth)
    return "prompts for a routine-cast selection"
end

BP.ActivatedAbilityRevertLocBehavior = function(b, ability, depth)
    return "reverts targets to their prior location"
end

-- ADDITIONAL DS-ACTIVE TYPES (beyond BEHAVIOUR_PROSE.md, surfaced by the
-- 2026-04-24 real-bestiary sweep -- all heavily used in compendium content
-- but absent from the locked worksheet).

BP.ActivatedAbilityInvokeAbilityBehavior = function(b, ability, depth)
    local custom = tryGet(b, "customAbility", nil)
    local abilityName = custom and tryGet(custom, "name", nil) or nil
    local namedAb = tryGet(b, "namedAbility", nil)
    local stdAb = tryGet(b, "standardAbility", nil)
    local label = (isNonEmpty(abilityName) and abilityName)
        or (isNonEmpty(namedAb) and namedAb)
        or (isNonEmpty(stdAb) and stdAb)
        or "an ability"
    return "invokes " .. label
end

BP.ActivatedAbilityFloatTextBehavior = function(b, ability, depth)
    local txt = tryGet(b, "text", "")
    if isNonEmpty(txt) then
        return 'floats the text "' .. txt .. '"'
    end
    return "floats text over the target"
end

BP.ActivatedAbilityInitiativeBehavior = function(b, ability, depth)
    return "changes the combat order"
end

BP.ActivatedAbilityPurgeEffectsBehavior = function(b, ability, depth)
    local conds = tryGet(b, "conditions", nil)
    if type(conds) == "table" and #conds > 0 then
        local labels = {}
        for _, cid in ipairs(conds) do
            labels[#labels + 1] = lookupConditionName(cid) or cid
        end
        return "purges " .. table.concat(labels, ", ")
    end
    return "purges ongoing effects"
end

-- Replenish has two modes: "replenish" (gain) and "expend" (consume). The
-- editor at AbilityReplenish.lua:741-749 confirms both ids. Quantity may be
-- a literal number or a GoblinScript formula string; render as-is.
BP.ActivatedAbilityReplenishBehavior = function(b, ability, depth)
    local mode = tryGet(b, "mode", "replenish")
    local resourceId = tryGet(b, "resourceid", nil)
    local quantity = tryGet(b, "quantity", "1")
    local resourceName = lookupResourceName(resourceId) or resourceId or "a resource"
    local verb = (mode == "expend") and "expends" or "restores"
    return verb .. " " .. tostring(quantity) .. " " .. resourceName
end

BP.ActivatedAbilityRemoveCreatureBehavior = function(b, ability, depth)
    local phrase = "removes the targeted creatures from play"
    if tryGet(b, "leavesCorpse", false) then
        phrase = phrase .. ", leaving a corpse"
    end
    return phrase
end

BP.ActivatedAbilityApplyRidersBehavior = function(b, ability, depth)
    local cond = tryGet(b, "conditionid", "none")
    local rider = tryGet(b, "riderid", "none")
    local condLabel = (cond == "none") and "the applied condition"
        or (lookupConditionName(cond) or cond)
    local riderLabel = (rider == "none") and "a rider" or rider
    return "adds " .. riderLabel .. " to " .. condLabel
end

--------------------------------------------------------------------------
-- Public API: behaviour rendering
--------------------------------------------------------------------------

-- Render a single behaviour as a prose phrase. depth is the recursion
-- counter (0 at the top of an ability). Returns the rendered string;
-- never nil. Falls back through:
--   1. registered template for behaviour.typeName
--   2. behaviour:SummarizeBehavior(ability)
--   3. ActivatedAbility.TypesById[id].text (display name)
--   4. raw type id string
function GoblinScriptProse.RenderBehaviour(behaviour, ability, depth)
    if behaviour == nil then return "" end
    depth = depth or 0

    -- typeName is class-level (set on the metatable by RegisterGameType),
    -- so try_get returns nil for it. Read it directly.
    local typeName = behaviour.typeName
    if depth < MAX_BEHAVIOUR_DEPTH and isNonEmpty(typeName) then
        local fn = GoblinScriptProse.behaviourProse[typeName]
        if type(fn) == "function" then
            local ok, phrase = pcall(fn, behaviour, ability, depth + 1)
            if ok and isNonEmpty(phrase) then return phrase end
        end
    end

    local fn = behaviour.SummarizeBehavior
    if type(fn) == "function" then
        local ok, phrase = pcall(fn, behaviour, ability)
        if ok and isNonEmpty(phrase) then return phrase end
    end

    local typeId = tryGet(behaviour, "behavior", nil)
    local AA = rawget(_G, "ActivatedAbility")
    if AA ~= nil and AA.TypesById ~= nil and isNonEmpty(typeId) then
        local entry = AA.TypesById[typeId]
        if entry and isNonEmpty(entry.text) then return entry.text end
    end
    return typeId or typeName or "?"
end

-- Render an ability's full behaviour list as a single sentence with the
-- worksheet's chaining convention: ", " between earlier items, ", then "
-- before the last. Returns (text, isEmpty).
function GoblinScriptProse.RenderBehaviourList(ability)
    if ability == nil then return "", true end
    local behaviors = tryGet(ability, "behaviors", nil)
    if behaviors == nil or #behaviors == 0 then return "", true end
    local parts = {}
    for _, b in ipairs(behaviors) do
        local phrase = GoblinScriptProse.RenderBehaviour(b, ability, 0)
        if isNonEmpty(phrase) then
            parts[#parts + 1] = phrase
        end
    end
    if #parts == 0 then return "", true end
    if #parts == 1 then return parts[1], false end
    if #parts == 2 then return parts[1] .. ", then " .. parts[2], false end
    local body = {}
    for i = 1, #parts - 1 do body[i] = parts[i] end
    return table.concat(body, ", ") .. ", then " .. parts[#parts], false
end
