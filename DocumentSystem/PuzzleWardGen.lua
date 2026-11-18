-- The warded seal's generator and solver (split-info-coop-brief.md, templates in
-- warded-seal-codex-templates.md). Runs no engine code: it takes a seeded random(k) and
-- returns plain data, so tests/puzzle_ward_gen_test.lua runs it with the bundled lua.exe.
--
-- A ward is { depth, face = {rim, candles}, lex = {...}, modules = { module, ... } }.
-- Every codex page is a first-match list: the first rule whose condition holds decides,
-- and the last line is always "Otherwise". Rules are data ({id = ..., params}); the tables
-- below give each id its condition, its action and its text.

PuzzleWardGen = {}

local RUNE_COUNT = 10
local COLOUR_COUNT = 6
local PATTERN_COUNT = 3
local GLYPH_COUNT = 4
local COLUMN_COUNT = 6
local COLUMN_SIZE = 5

PuzzleWardGen.depths = { plain = 1, conditional = 2, chained = 3 }
--Rules per page, not counting "Otherwise".
PuzzleWardGen.rulesPerPage = { plain = 3, conditional = 4, chained = 5 }
PuzzleWardGen.letters = { "A", "B", "C", "D" }

local MAX_ATTEMPTS = 400

---@alias WardRandom fun(k: integer): integer

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function RuneName(i) return PuzzleRunes.Name(i) end
local function ColourName(i) return PuzzleRunes.threadColours[i].name end
local function PatternName(i) return PuzzleRunes.threadPatterns[i].name end

---@param n integer
---@return integer[]
local function Range(n)
    local r = {}
    for i = 1, n do
        r[i] = i
    end
    return r
end

---@param random WardRandom
---@param list any[]
---@return any[]
local function Shuffle(random, list)
    for i = #list, 2, -1 do
        local j = random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

--A random permutation of 1..n with no element in its own place.
---@param random WardRandom
---@param n integer
---@return integer[]
local function Derangement(random, n)
    while true do
        local p = Shuffle(random, Range(n))
        local ok = true
        for i = 1, n do
            if p[i] == i then
                ok = false
                break
            end
        end
        if ok then
            return p
        end
    end
end

---@param random WardRandom
---@param lo integer
---@param hi integer
---@return integer
local function Between(random, lo, hi)
    return lo + random(hi - lo + 1) - 1
end

---@param list any[]
---@param value any
---@return boolean
local function Contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- The face and the Lexicon
--------------------------------------------------------------------------------

---@param random WardRandom
local function MakeLexicon(random)
    local runes = Shuffle(random, Range(RUNE_COUNT))
    local colours = Shuffle(random, Range(COLOUR_COUNT))
    local candleRunes = Shuffle(random, Range(RUNE_COUNT))
    return {
        --the warden's colour, first-match on the rim rune
        colourRules = {
            { runes = { runes[1], runes[2] }, colour = colours[1] },
            { runes = { runes[3], runes[4] }, colour = colours[2] },
        },
        colourOtherwise = colours[3],
        --the warden's rune, by the number of lit candles (1-5)
        candleRunes = { candleRunes[1], candleRunes[2], candleRunes[3], candleRunes[4], candleRunes[5] },
        ring = Shuffle(random, Range(RUNE_COUNT)),
    }
end

---@param ward table
---@return integer
function PuzzleWardGen.WardenColour(ward)
    for _, rule in ipairs(ward.lex.colourRules) do
        if Contains(rule.runes, ward.face.rim) then
            return rule.colour
        end
    end
    return ward.lex.colourOtherwise
end

---@param ward table
---@return integer
function PuzzleWardGen.WardenRune(ward)
    return ward.lex.candleRunes[ward.face.candles]
end

---@param ward table
---@param rune integer
---@return integer
function PuzzleWardGen.RingNext(ward, rune)
    local ring = ward.lex.ring
    for i, r in ipairs(ring) do
        if r == rune then
            return ring[i % #ring + 1]
        end
    end
    return ring[1]
end

--------------------------------------------------------------------------------
-- Threads
--------------------------------------------------------------------------------

---@param threads table[]
---@param field string
---@param value integer
---@return integer count, integer|nil first, integer|nil last, integer|nil second
local function Find(threads, field, value)
    local count, first, last, second = 0, nil, nil, nil
    for i, t in ipairs(threads) do
        if t[field] == value then
            count = count + 1
            if first == nil then
                first = i
            elseif second == nil then
                second = i
            end
            last = i
        end
    end
    return count, first, last, second
end

--Each thread rule: depth, make(random, ward, threads) -> params, cond, act (thread number
--or nil), needs (extra check that its named target exists), text.
local THREAD_RULES = {
    noColour = {
        depth = 1,
        make = function(random, ward, th) return { c = random(COLOUR_COUNT), i = random(#th) } end,
        cond = function(r, ward, th) return (Find(th, "colour", r.c)) == 0 end,
        act = function(r, ward, th) return r.i end,
        text = function(r) return string.format("If there is no %s thread, cut Thread %d.", ColourName(r.c), r.i) end,
    },
    moreThanOne = {
        depth = 1,
        make = function(random, ward, th) return { c = random(COLOUR_COUNT) } end,
        cond = function(r, ward, th) return (Find(th, "colour", r.c)) > 1 end,
        act = function(r, ward, th) local _, _, last = Find(th, "colour", r.c) return last end,
        needs = function(r, ward, th) return (Find(th, "colour", r.c)) > 0 end,
        text = function(r) return string.format("If more than one thread is %s, cut the last %s thread.", ColourName(r.c), ColourName(r.c)) end,
    },
    threadIsPattern = {
        depth = 1,
        make = function(random, ward, th) return { i = random(#th), p = random(PATTERN_COUNT) } end,
        cond = function(r, ward, th) return th[r.i].pattern == r.p end,
        act = function(r, ward, th) return r.i end,
        text = function(r) return string.format("If Thread %d is %s, cut Thread %d.", r.i, PatternName(r.p), r.i) end,
    },
    noPattern = {
        depth = 1,
        make = function(random, ward, th) return { p = random(PATTERN_COUNT) } end,
        cond = function(r, ward, th) return (Find(th, "pattern", r.p)) == 0 end,
        act = function(r, ward, th) return #th end,
        text = function(r) return string.format("If no thread is %s, cut the last thread.", PatternName(r.p)) end,
    },
    exactlyCount = {
        depth = 1,
        make = function(random, ward, th) return { k = Between(random, 3, 6), p = random(PATTERN_COUNT) } end,
        cond = function(r, ward, th) return #th == r.k end,
        act = function(r, ward, th) local _, first = Find(th, "pattern", r.p) return first end,
        needs = function(r, ward, th) return (Find(th, "pattern", r.p)) > 0 end,
        text = function(r) return string.format("If there are exactly %d threads, cut the first %s thread.", r.k, PatternName(r.p)) end,
    },
    firstIsColour = {
        depth = 1,
        make = function(random, ward, th) return { c = random(COLOUR_COUNT) } end,
        cond = function(r, ward, th) return th[1].colour == r.c end,
        act = function(r, ward, th) return 2 end,
        text = function(r) return string.format("If the first thread is %s, cut the second thread.", ColourName(r.c)) end,
    },
    onePatternMany = {
        depth = 2,
        make = function(random, ward, th) return { p = random(PATTERN_COUNT), k = Between(random, 3, 5) } end,
        cond = function(r, ward, th) return (Find(th, "pattern", r.p)) == 1 and #th > r.k end,
        act = function(r, ward, th) local _, first = Find(th, "pattern", r.p) return first end,
        needs = function(r, ward, th) return (Find(th, "pattern", r.p)) > 0 end,
        text = function(r) return string.format("If exactly one thread is %s and there are more than %d threads, cut the %s thread.", PatternName(r.p), r.k, PatternName(r.p)) end,
    },
    lastColourNoColour = {
        depth = 2,
        make = function(random, ward, th)
            local c = random(COLOUR_COUNT)
            local c2 = random(COLOUR_COUNT - 1)
            if c2 >= c then
                c2 = c2 + 1
            end
            return { c = c, c2 = c2, p = random(PATTERN_COUNT) }
        end,
        cond = function(r, ward, th) return th[#th].colour == r.c and (Find(th, "colour", r.c2)) == 0 end,
        act = function(r, ward, th) local _, first = Find(th, "pattern", r.p) return first end,
        needs = function(r, ward, th) return (Find(th, "pattern", r.p)) > 0 end,
        text = function(r) return string.format("If the last thread is %s and no thread is %s, cut the first %s thread.", ColourName(r.c), ColourName(r.c2), PatternName(r.p)) end,
    },
    twoColourPattern = {
        depth = 2,
        make = function(random, ward, th) return { c = random(COLOUR_COUNT), i = random(#th), p = random(PATTERN_COUNT), m = random(#th) } end,
        cond = function(r, ward, th) return (Find(th, "colour", r.c)) >= 2 and th[r.i].pattern == r.p end,
        act = function(r, ward, th) return r.m end,
        text = function(r) return string.format("If two or more threads are %s and Thread %d is %s, cut Thread %d.", ColourName(r.c), r.i, PatternName(r.p), r.m) end,
    },
    wardenTwice = {
        depth = 3,
        make = function(random, ward, th) return {} end,
        cond = function(r, ward, th) return (Find(th, "colour", PuzzleWardGen.WardenColour(ward))) >= 2 end,
        act = function(r, ward, th) local _, _, _, second = Find(th, "colour", PuzzleWardGen.WardenColour(ward)) return second end,
        text = function(r) return "If the warden's colour is on two or more threads, cut the second of them." end,
    },
    wardenNone = {
        depth = 3,
        make = function(random, ward, th) return {} end,
        cond = function(r, ward, th) return (Find(th, "colour", PuzzleWardGen.WardenColour(ward))) == 0 end,
        act = function(r, ward, th) return ward.face.candles end,
        needs = function(r, ward, th) return ward.face.candles <= #th end,
        text = function(r) return "If no thread is the warden's colour, cut the thread whose number is the number of lit candles." end,
    },
    rimIs = {
        depth = 3,
        make = function(random, ward, th) return { rune = random(RUNE_COUNT), p = random(PATTERN_COUNT) } end,
        cond = function(r, ward, th) return ward.face.rim == r.rune end,
        act = function(r, ward, th) local _, _, last = Find(th, "pattern", r.p) return last end,
        needs = function(r, ward, th) return (Find(th, "pattern", r.p)) > 0 end,
        text = function(r) return string.format("If the rim bears the %s, cut the last %s thread.", RuneName(r.rune), PatternName(r.p)) end,
    },
}

local THREAD_OTHERWISE = {
    number = {
        make = function(random, th) return { i = random(#th) } end,
        act = function(r, th) return r.i end,
        text = function(r) return string.format("Otherwise, cut Thread %d.", r.i) end,
    },
    first = {
        make = function(random, th) return {} end,
        act = function(r, th) return 1 end,
        text = function(r) return "Otherwise, cut the first thread." end,
    },
    last = {
        make = function(random, th) return {} end,
        act = function(r, th) return #th end,
        text = function(r) return "Otherwise, cut the last thread." end,
    },
}
local THREAD_OTHERWISE_IDS = { "number", "first", "last" }

local function SortedIds(rules)
    local ids = {}
    for id in pairs(rules) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end
local THREAD_RULE_IDS = SortedIds(THREAD_RULES)

--Thread rules that need a Lexicon page (the warden's colour).
local LEXICON_RULES = { wardenTwice = true, wardenNone = true }

--A rule is usable when its named target exists and it resolves whenever it holds.
local function ThreadRuleOk(rule, ward, th)
    local def = THREAD_RULES[rule.id]
    if def.needs ~= nil and not def.needs(rule, ward, th) then
        return false
    end
    if def.cond(rule, ward, th) then
        local target = def.act(rule, ward, th)
        return target ~= nil and target >= 1 and target <= #th
    end
    return true
end

---@param random WardRandom
---@param ward table
---@param depth integer
--lexicon: below chained depth, put exactly one rule on the page that needs the warden's
--colour from the Lexicon, so a spare reader holding that page is needed.
local function MakeThreadsModule(random, ward, depth, perPage, lexicon)
    local th = {}
    for i = 1, Between(random, 3, 6) do
        th[i] = { colour = random(COLOUR_COUNT), pattern = random(PATTERN_COUNT) }
    end
    lexicon = lexicon and depth < 3
    local pool = {}
    for _, id in ipairs(THREAD_RULE_IDS) do
        if THREAD_RULES[id].depth <= depth or (lexicon and LEXICON_RULES[id]) then
            pool[#pool + 1] = id
        end
    end
    --spread which line decides: aim for a random one, the Otherwise line included.
    local target = random(perPage + 1)
    local best = nil
    for _ = 1, MAX_ATTEMPTS do
        local rules = {}
        local seen = {}
        local deepest = 0
        local lexCount = 0
        local tries = 0
        while #rules < perPage and tries < 50 do
            tries = tries + 1
            local id = pool[random(#pool)]
            local rule = THREAD_RULES[id].make(random, ward, th)
            rule.id = id
            --one rule per condition: a repeated condition could never decide.
            local condition = THREAD_RULES[id].text(rule):match("^(.-), cut")
            local isLex = lexicon and LEXICON_RULES[id] == true
            if not seen[condition] and not (isLex and lexCount > 0) and ThreadRuleOk(rule, ward, th) then
                seen[condition] = true
                rules[#rules + 1] = rule
                if isLex then
                    lexCount = lexCount + 1
                else
                    deepest = math.max(deepest, THREAD_RULES[id].depth)
                end
            end
        end
        local oid = THREAD_OTHERWISE_IDS[random(#THREAD_OTHERWISE_IDS)]
        local otherwise = THREAD_OTHERWISE[oid].make(random, th)
        otherwise.id = oid
        if #rules == perPage and deepest == depth and (not lexicon or lexCount == 1) then
            local decides = perPage + 1
            for i, rule in ipairs(rules) do
                if THREAD_RULES[rule.id].cond(rule, ward, th) then
                    decides = i
                    break
                end
            end
            best = { threads = th, rules = rules, otherwise = otherwise }
            if decides == target then
                break
            end
        end
    end
    best.kind = "threads"
    return best
end

--------------------------------------------------------------------------------
-- Glyph order
--------------------------------------------------------------------------------

--The glyphs (as rune numbers) in the deciding order.
local GLYPH_RULES = {
    reverseIf = {
        depth = 2,
        cond = function(r, ward, m) return Contains(m.glyphs, r.rune) end,
        text = function(r) return string.format("If the %s is one of your glyphs, touch them from bottom to top instead.", RuneName(r.rune)) end,
    },
    rimStart = {
        depth = 3,
        cond = function(r, ward, m) return Contains(m.glyphs, ward.face.rim) end,
        text = function(r) return "If the rim rune is one of your glyphs, start with it and carry on down the column, going back to the top when you reach the bottom." end,
    },
    wardenLast = {
        depth = 3,
        cond = function(r, ward, m) return Contains(m.glyphs, PuzzleWardGen.WardenRune(ward)) end,
        text = function(r) return "If the warden's rune is one of your glyphs, touch it last." end,
    },
}

---@param m table
---@return integer[] the module's glyph runes in the order they stand in the answer column
local function ColumnOrder(m)
    local order = {}
    for _, rune in ipairs(m.columns[m.column]) do
        if Contains(m.glyphs, rune) then
            order[#order + 1] = rune
        end
    end
    return order
end

local function GlyphSequence(ward, m, ruleId)
    local order = ColumnOrder(m)
    if ruleId == "reverseIf" then
        local rev = {}
        for i = #order, 1, -1 do
            rev[#rev + 1] = order[i]
        end
        return rev
    elseif ruleId == "rimStart" then
        local start = 1
        for i, rune in ipairs(order) do
            if rune == ward.face.rim then
                start = i
            end
        end
        local seq = {}
        for k = 0, #order - 1 do
            seq[#seq + 1] = order[(start - 1 + k) % #order + 1]
        end
        return seq
    elseif ruleId == "wardenLast" then
        local w = PuzzleWardGen.WardenRune(ward)
        local seq = {}
        for _, rune in ipairs(order) do
            if rune ~= w then
                seq[#seq + 1] = rune
            end
        end
        seq[#seq + 1] = w
        return seq
    end
    return order
end

---@param random WardRandom
local function MakeGlyphsModule(random, ward, depth)
    local runes = Shuffle(random, Range(RUNE_COUNT))
    local glyphs = { runes[1], runes[2], runes[3], runes[4] }
    local column = random(COLUMN_COUNT)
    local columns = {}
    for c = 1, COLUMN_COUNT do
        if c == column then
            local extra = runes[Between(random, GLYPH_COUNT + 1, RUNE_COUNT)]
            columns[c] = Shuffle(random, { glyphs[1], glyphs[2], glyphs[3], glyphs[4], extra })
        else
            --any five runes, but never all four glyphs: only one column may hold them.
            while true do
                local pick = Shuffle(random, Range(RUNE_COUNT))
                local col = { pick[1], pick[2], pick[3], pick[4], pick[5] }
                local held = 0
                for _, g in ipairs(glyphs) do
                    if Contains(col, g) then
                        held = held + 1
                    end
                end
                if held < GLYPH_COUNT then
                    columns[c] = col
                    break
                end
            end
        end
    end
    local rules = {}
    if depth >= 3 then
        rules[#rules + 1] = { id = "rimStart" }
        rules[#rules + 1] = { id = "wardenLast" }
    end
    if depth >= 2 then
        --half the time the reversing rune is one of the glyphs, so the rule decides.
        local rune
        if random(2) == 1 then
            rune = glyphs[random(GLYPH_COUNT)]
        else
            rune = runes[Between(random, GLYPH_COUNT + 1, RUNE_COUNT)]
        end
        rules[#rules + 1] = { id = "reverseIf", rune = rune }
    end
    return { kind = "glyphs", glyphs = glyphs, columns = columns, column = column, rules = rules }
end

--------------------------------------------------------------------------------
-- Sigil dial
--------------------------------------------------------------------------------

---@param random WardRandom
local function MakeDialModule(random, ward, depth)
    return {
        kind = "dial",
        waking = random(RUNE_COUNT),
        left = Derangement(random, RUNE_COUNT),
        right = Derangement(random, RUNE_COUNT),
        twoColumns = depth >= 2,
        afterGlyphs = false, --set by Generate when the ward also has Glyphs at chained depth
    }
end

--------------------------------------------------------------------------------
-- Generate and solve
--------------------------------------------------------------------------------

--Generate a ward. opts.modules: list of kinds in order ("threads", "glyphs", "dial");
--opts.depth: "plain" | "conditional" | "chained"; opts.lexicon: below chained depth, give
--each Threads page one rule that needs the Lexicon (for spare readers).
---@param random WardRandom
---@param opts {modules: string[], depth: string, lexicon: boolean|nil}
---@return table
function PuzzleWardGen.Generate(random, opts)
    local depthName = opts.depth or "plain"
    local depth = PuzzleWardGen.depths[depthName] or 1
    local perPage = PuzzleWardGen.rulesPerPage[depthName] or 3
    local ward = {
        depth = depthName,
        face = { rim = random(RUNE_COUNT), candles = random(5) },
        modules = {},
    }
    ward.lex = MakeLexicon(random)
    local hasGlyphs = false
    for _, kind in ipairs(opts.modules) do
        hasGlyphs = hasGlyphs or kind == "glyphs"
    end
    for i, kind in ipairs(opts.modules) do
        local m
        if kind == "threads" then
            m = MakeThreadsModule(random, ward, depth, perPage, opts.lexicon == true)
        elseif kind == "glyphs" then
            m = MakeGlyphsModule(random, ward, depth)
        else
            m = MakeDialModule(random, ward, depth)
            m.afterGlyphs = depth >= 3 and hasGlyphs
        end
        ward.modules[i] = m
    end
    for i, m in ipairs(ward.modules) do
        m.answer = PuzzleWardGen.Solve(ward, i)
    end
    return ward
end

--Which line of a module's page decides: its index, or #rules + 1 for "Otherwise".
---@param ward table
---@param i integer
---@return integer
function PuzzleWardGen.DecidingLine(ward, i)
    local m = ward.modules[i]
    if m.kind == "threads" then
        for k, rule in ipairs(m.rules) do
            if THREAD_RULES[rule.id].cond(rule, ward, m.threads) then
                return k
            end
        end
        return #m.rules + 1
    elseif m.kind == "glyphs" then
        for k, rule in ipairs(m.rules) do
            if GLYPH_RULES[rule.id].cond(rule, ward, m) then
                return k
            end
        end
        return #m.rules + 1
    end
    if m.afterGlyphs then
        return 1
    end
    if m.twoColumns then
        if ward.face.candles > 3 then
            return 1
        end
        return 2
    end
    return 1
end

--The right action: a thread number, a list of glyph letters (1-4) in order, or a rune.
---@param ward table
---@param i integer
---@return any
function PuzzleWardGen.Solve(ward, i)
    local m = ward.modules[i]
    local line = PuzzleWardGen.DecidingLine(ward, i)
    if m.kind == "threads" then
        if line <= #m.rules then
            local rule = m.rules[line]
            return THREAD_RULES[rule.id].act(rule, ward, m.threads)
        end
        return THREAD_OTHERWISE[m.otherwise.id].act(m.otherwise, m.threads)
    elseif m.kind == "glyphs" then
        local seq = GlyphSequence(ward, m, line <= #m.rules and m.rules[line].id or nil)
        local letters = {}
        for k, rune in ipairs(seq) do
            for pos, g in ipairs(m.glyphs) do
                if g == rune then
                    letters[k] = pos
                end
            end
        end
        return letters
    end
    if m.afterGlyphs then
        for k, other in ipairs(ward.modules) do
            if other.kind == "glyphs" then
                local seq = GlyphSequence(ward, other, (function()
                    local l = PuzzleWardGen.DecidingLine(ward, k)
                    return l <= #other.rules and other.rules[l].id or nil
                end)())
                return PuzzleWardGen.RingNext(ward, seq[#seq])
            end
        end
    end
    if m.twoColumns and ward.face.candles > 3 then
        return m.right[m.waking]
    end
    return m.left[m.waking]
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

PuzzleWardGen.pageHeader = "Check in order. Follow the first rule that fits."

--A module's codex page: {title, intro, lines}, lines numbered in order.
---@param ward table
---@param i integer
---@return {title: string, intro: string, lines: string[]}
function PuzzleWardGen.PageText(ward, i)
    local m = ward.modules[i]
    local lines = {}
    if m.kind == "threads" then
        for k, rule in ipairs(m.rules) do
            lines[k] = string.format("%d. %s", k, THREAD_RULES[rule.id].text(rule))
        end
        lines[#lines + 1] = string.format("%d. %s", #m.rules + 1, THREAD_OTHERWISE[m.otherwise.id].text(m.otherwise))
        return { title = "Threads", intro = "Severed threads still count. Cut exactly one thread.", lines = lines }
    elseif m.kind == "glyphs" then
        local intro = "Touch all four glyphs in order. Correct ones stay lit."
        for k, rule in ipairs(m.rules) do
            lines[k] = string.format("%d. %s", k, GLYPH_RULES[rule.id].text(rule))
        end
        lines[#lines + 1] = string.format("%d. Otherwise, find the column that holds all four of your glyphs and touch them in the order they appear in it, from top to bottom.", #m.rules + 1)
        for c, col in ipairs(m.columns) do
            local names = {}
            for k, rune in ipairs(col) do
                names[k] = RuneName(rune)
            end
            lines[#lines + 1] = string.format("Column %d: %s", c, table.concat(names, ", "))
        end
        return { title = "Glyphs", intro = intro, lines = lines }
    end
    local intro = "Turn the dial and press Set the seal. Only a wrong setting is a strike."
    local n = 0
    if m.afterGlyphs then
        n = n + 1
        lines[#lines + 1] = string.format("%d. If the Glyphs are done, set it to the rune that comes after the last glyph you touched in the Lexicon's ring.", n)
    end
    if m.twoColumns then
        n = n + 1
        lines[#lines + 1] = string.format("%d. If more than 3 candles are lit, use the right-hand column of the table.", n)
    end
    n = n + 1
    lines[#lines + 1] = string.format("%d. Otherwise, use the table%s.", n, m.twoColumns and " (left-hand column)" or "")
    for rune = 1, RUNE_COUNT do
        if m.twoColumns then
            lines[#lines + 1] = string.format("Wakes on %s: %s | %s", RuneName(rune), RuneName(m.left[rune]), RuneName(m.right[rune]))
        else
            lines[#lines + 1] = string.format("Wakes on %s: set it to %s", RuneName(rune), RuneName(m.left[rune]))
        end
    end
    return { title = "Sigil dial", intro = intro, lines = lines }
end

--Which Lexicon pages (1-3) the ward's pages refer to.
---@param ward table
---@return table<integer, boolean>
function PuzzleWardGen.LexiconRefs(ward)
    local refs = {}
    for i in ipairs(ward.modules) do
        for _, line in ipairs(PuzzleWardGen.PageText(ward, i).lines) do
            if line:find("warden's colour", 1, true) then refs[1] = true end
            if line:find("warden's rune", 1, true) then refs[2] = true end
            if line:find("Lexicon's ring", 1, true) then refs[3] = true end
        end
    end
    return refs
end

--The Lexicon's three pages.
---@param ward table
---@return {title: string, intro: string, lines: string[]}[]
function PuzzleWardGen.LexiconText(ward)
    local lex = ward.lex
    local c1, c2 = lex.colourRules[1], lex.colourRules[2]
    local intro = "Other pages ask about these. Read them out when asked."
    local candles = {}
    for k = 1, 5 do
        candles[k] = string.format("%d: %s", k, RuneName(lex.candleRunes[k]))
    end
    local ring = {}
    for k, rune in ipairs(lex.ring) do
        ring[k] = RuneName(rune)
    end
    return {
        { title = "The warden's colour", intro = intro, lines = {
            string.format("1. If the rim bears the %s or the %s, %s.", RuneName(c1.runes[1]), RuneName(c1.runes[2]), ColourName(c1.colour)),
            string.format("2. If it bears the %s or the %s, %s.", RuneName(c2.runes[1]), RuneName(c2.runes[2]), ColourName(c2.colour)),
            string.format("3. Otherwise, %s.", ColourName(lex.colourOtherwise)),
        } },
        { title = "The warden's rune", intro = intro, lines = {
            "Count the lit candles. " .. table.concat(candles, ". ") .. ".",
        } },
        { title = "The ring", intro = intro, lines = {
            string.format("The runes in their ring order: %s, then back to %s.", table.concat(ring, ", "), ring[1]),
        } },
    }
end

--What a reader can ask the hands, built from the rules on one page (key "m<i>", or "L<k>"
--for a Lexicon page). The hands answers in the chat; nothing checks the answer.
---@param ward table
---@param key string
---@return string[]
function PuzzleWardGen.Questions(ward, key)
    local out, seen = {}, {}
    local function Ask(text)
        if not seen[text] then
            seen[text] = true
            out[#out + 1] = text
        end
    end
    local function ColourCount(c) Ask(string.format("How many threads are %s?", ColourName(c))) end
    local function PatternWhich(p) Ask(string.format("Which threads are %s?", PatternName(p))) end
    local n = math.tointeger(tonumber(key:sub(2)))
    if key:sub(1, 1) == "L" then
        if n == 1 then
            Ask("What rune is on the rim?")
        elseif n == 2 then
            Ask("How many candles are lit?")
        else
            Ask("Which glyph did you touch last?")
        end
        return out
    end
    local m = n ~= nil and ward.modules[n] or nil
    if m == nil then
        return out
    end
    if m.kind == "threads" then
        Ask("How many threads are there?")
        for _, r in ipairs(m.rules) do
            local id = r.id
            if id == "noColour" or id == "moreThanOne" then
                ColourCount(r.c)
            elseif id == "threadIsPattern" then
                Ask(string.format("What pattern is Thread %d?", r.i))
            elseif id == "noPattern" or id == "exactlyCount" or id == "onePatternMany" then
                PatternWhich(r.p)
            elseif id == "firstIsColour" then
                Ask("What colour is the first thread?")
            elseif id == "lastColourNoColour" then
                Ask("What colour is the last thread?")
                ColourCount(r.c2)
                PatternWhich(r.p)
            elseif id == "twoColourPattern" then
                ColourCount(r.c)
                Ask(string.format("What pattern is Thread %d?", r.i))
            elseif id == "wardenTwice" then
                Ask("What colours are the threads, in order?")
            elseif id == "wardenNone" then
                Ask("What colours are the threads, in order?")
                Ask("How many candles are lit?")
            elseif id == "rimIs" then
                Ask("What rune is on the rim?")
                PatternWhich(r.p)
            end
        end
    elseif m.kind == "glyphs" then
        Ask("What are your four glyphs?")
        for _, r in ipairs(m.rules) do
            if r.id == "reverseIf" then
                Ask(string.format("Is the %s one of your glyphs?", RuneName(r.rune)))
            elseif r.id == "rimStart" then
                Ask("What rune is on the rim?")
            end
        end
    else
        Ask("What rune did the dial wake on?")
        if m.twoColumns then
            Ask("How many candles are lit?")
        end
        if m.afterGlyphs then
            Ask("Are the Glyphs done?")
            Ask("Which glyph did you touch last?")
        end
    end
    return out
end
