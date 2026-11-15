--Run from the codex root: ../dmhubclient/dependencies/lua/bin/lua.exe tests/puzzle_ward_gen_test.lua
--Sweeps the warded seal generator (DocumentSystem/PuzzleWardGen.lua) over many seeds per
--preset. Threads pages are checked by reading their English text with an independent
--interpreter, so a rule whose words and code disagree fails here.
dofile("DocumentSystem/PuzzleRunes.lua")
dofile("DocumentSystem/PuzzleWardGen.lua")

local SEEDS = tonumber(arg and arg[1]) or 1500

--Same generator as Puzzle.SeededRandom (PuzzleFramework.lua).
local function SeededRandom(seedText)
    local seed = 7
    for i = 1, #seedText do
        seed = (seed * 31 + string.byte(seedText, i)) % 2147483648
    end
    return function(k)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed // 65536) % k + 1
    end
end

local failures = 0
local function Fail(fmt, ...)
    failures = failures + 1
    if failures <= 25 then
        print("FAIL: " .. string.format(fmt, ...))
    end
end

local function Serialize(v)
    if type(v) ~= "table" then
        return tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. "=" .. Serialize(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local colourIndex, patternIndex, runeIndex = {}, {}, {}
for i, c in ipairs(PuzzleRunes.threadColours) do colourIndex[c.name] = i end
for i, p in ipairs(PuzzleRunes.threadPatterns) do patternIndex[p.name] = i end
for i, r in ipairs(PuzzleRunes.list) do runeIndex[r.name] = i end

--------------------------------------------------------------------------------
-- An independent reader for Threads pages
--------------------------------------------------------------------------------

local function Count(th, field, v)
    local n, first, last, second = 0, nil, nil, nil
    for i, t in ipairs(th) do
        if t[field] == v then
            n = n + 1
            if first == nil then first = i elseif second == nil then second = i end
            last = i
        end
    end
    return n, first, last, second
end

--Returns holds (boolean) and the thread to cut, or errors on an unknown sentence.
local function ReadRule(text, ward, th)
    local W = PuzzleWardGen.WardenColour(ward)
    local c, i, p, k, m, c2, r
    c, i = text:match("^If there is no (%a+) thread, cut Thread (%d+)%.$")
    if c then return Count(th, "colour", colourIndex[c]) == 0, tonumber(i) end
    c = text:match("^If more than one thread is (%a+), cut the last %a+ thread%.$")
    if c then local n, _, last = Count(th, "colour", colourIndex[c]) return n > 1, last end
    i, p = text:match("^If Thread (%d+) is (%a+), cut Thread %d+%.$")
    if i then return th[tonumber(i)].pattern == patternIndex[p], tonumber(i) end
    p = text:match("^If no thread is (%a+), cut the last thread%.$")
    if p then return Count(th, "pattern", patternIndex[p]) == 0, #th end
    k, p = text:match("^If there are exactly (%d+) threads, cut the first (%a+) thread%.$")
    if k then local _, first = Count(th, "pattern", patternIndex[p]) return #th == tonumber(k), first end
    c = text:match("^If the first thread is (%a+), cut the second thread%.$")
    if c then return th[1].colour == colourIndex[c], 2 end
    p, k = text:match("^If exactly one thread is (%a+) and there are more than (%d+) threads, cut the %a+ thread%.$")
    if p then local n, first = Count(th, "pattern", patternIndex[p]) return n == 1 and #th > tonumber(k), first end
    c, c2, p = text:match("^If the last thread is (%a+) and no thread is (%a+), cut the first (%a+) thread%.$")
    if c then local _, first = Count(th, "pattern", patternIndex[p]) return th[#th].colour == colourIndex[c] and Count(th, "colour", colourIndex[c2]) == 0, first end
    c, i, p, m = text:match("^If two or more threads are (%a+) and Thread (%d+) is (%a+), cut Thread (%d+)%.$")
    if c then return Count(th, "colour", colourIndex[c]) >= 2 and th[tonumber(i)].pattern == patternIndex[p], tonumber(m) end
    if text == "If the warden's colour is on two or more threads, cut the second of them." then
        local n, _, _, second = Count(th, "colour", W) return n >= 2, second
    end
    if text == "If no thread is the warden's colour, cut the thread whose number is the number of lit candles." then
        return Count(th, "colour", W) == 0, ward.face.candles
    end
    r, p = text:match("^If the rim bears the (%a+), cut the last (%a+) thread%.$")
    if r then local _, _, last = Count(th, "pattern", patternIndex[p]) return ward.face.rim == runeIndex[r], last end
    i = text:match("^Otherwise, cut Thread (%d+)%.$")
    if i then return true, tonumber(i) end
    if text == "Otherwise, cut the first thread." then return true, 1 end
    if text == "Otherwise, cut the last thread." then return true, #th end
    error("unknown rule text: " .. text)
end

--The named targets a rule's action points at must exist on this ward.
local function TargetsExist(text, th)
    local c = text:match("cut the last (%a+) thread%.$")
    if c and colourIndex[c] and Count(th, "colour", colourIndex[c]) == 0 then return false end
    local p = text:match("cut the first (%a+) thread%.$") or text:match("cut the last (%a+) thread%.$") or text:match("cut the (%a+) thread%.$")
    if p and patternIndex[p] and Count(th, "pattern", patternIndex[p]) == 0 then return false end
    local n = text:match("cut Thread (%d+)%.$")
    if n and tonumber(n) > #th then return false end
    return true
end

--------------------------------------------------------------------------------
-- The sweep
--------------------------------------------------------------------------------

local setups = {
    { name = "simple-threads", depth = "plain", modules = { "threads" } },
    { name = "simple-glyphs", depth = "plain", modules = { "glyphs" } },
    { name = "simple-dial", depth = "plain", modules = { "dial" } },
    { name = "simple-two", depth = "plain", modules = { "threads", "dial" } },
    { name = "vault", depth = "conditional", modules = { "threads", "glyphs", "dial" } },
    { name = "vault-threads", depth = "conditional", modules = { "threads" } },
    { name = "archmage", depth = "chained", modules = { "threads", "glyphs", "dial", "threads" } },
    { name = "archmage-no-glyphs", depth = "chained", modules = { "threads", "dial" } },
    { name = "simple-lexicon", depth = "plain", modules = { "threads" }, lexicon = true },
    { name = "vault-lexicon", depth = "conditional", modules = { "threads", "glyphs", "dial" }, lexicon = true },
}

for _, setup in ipairs(setups) do
    local perPage = PuzzleWardGen.rulesPerPage[setup.depth]
    local decided = {}
    local started = os.clock()
    for s = 1, SEEDS do
        local seed = setup.name .. ":" .. s
        local opts = { depth = setup.depth, modules = setup.modules, lexicon = setup.lexicon }
        local ok, ward = pcall(PuzzleWardGen.Generate, SeededRandom(seed), opts)
        if not ok then
            Fail("%s seed %d: Generate errored: %s", setup.name, s, tostring(ward))
        else
            --deterministic from the seed
            local again = PuzzleWardGen.Generate(SeededRandom(seed), opts)
            if setup.lexicon and not PuzzleWardGen.LexiconRefs(ward)[1] then
                Fail("%s seed %d: Lexicon option but no page refers to the warden's colour", setup.name, s)
            end
            if Serialize(ward) ~= Serialize(again) then
                Fail("%s seed %d: not deterministic", setup.name, s)
            end
            for i, m in ipairs(ward.modules) do
                local page = PuzzleWardGen.PageText(ward, i)
                for _, line in ipairs(page.lines) do
                    if line:find("nil") or line:find("%?") or line:find("[^\32-\126]") then
                        Fail("%s seed %d: bad text: %s", setup.name, s, line)
                    end
                end
                if m.kind == "threads" then
                    if #m.rules ~= perPage then
                        Fail("%s seed %d: %d rules, want %d", setup.name, s, #m.rules, perPage)
                    end
                    local conditions = {}
                    for _, line in ipairs(page.lines) do
                        local condition = line:gsub("^%d+%. ", ""):match("^(If .-), cut")
                        if condition then
                            if conditions[condition] then
                                Fail("%s seed %d: condition repeated: %s", setup.name, s, condition)
                            end
                            conditions[condition] = true
                        end
                    end
                    --read the page as a player would
                    local answer = nil
                    local decides = nil
                    for n, line in ipairs(page.lines) do
                        local text = line:gsub("^%d+%. ", "")
                        if not TargetsExist(text, m.threads) then
                            Fail("%s seed %d: target missing: %s", setup.name, s, text)
                        end
                        local holds, target = ReadRule(text, ward, m.threads)
                        if holds and answer == nil then
                            answer = target
                            decides = n
                        end
                    end
                    if decides == nil then
                        Fail("%s seed %d: no line holds", setup.name, s)
                    else
                        decided[decides] = (decided[decides] or 0) + 1
                    end
                    if answer ~= m.answer then
                        Fail("%s seed %d: text says cut %s, generator says %s", setup.name, s, tostring(answer), tostring(m.answer))
                    end
                    if answer == nil or answer < 1 or answer > #m.threads then
                        Fail("%s seed %d: answer %s out of range", setup.name, s, tostring(answer))
                    end
                    if setup.lexicon then
                        local lex = 0
                        for _, line in ipairs(page.lines) do
                            if line:find("warden's colour", 1, true) then lex = lex + 1 end
                        end
                        if lex ~= 1 then
                            Fail("%s seed %d: %d warden's-colour rules, want 1", setup.name, s, lex)
                        end
                    end
                    if setup.depth == "chained" then
                        local chained = false
                        for _, line in ipairs(page.lines) do
                            chained = chained or line:find("warden") ~= nil or line:find("rim") ~= nil
                        end
                        if not chained then
                            Fail("%s seed %d: chained page with no chained rule", setup.name, s)
                        end
                    end
                elseif m.kind == "glyphs" then
                    local holding = 0
                    for _, col in ipairs(m.columns) do
                        local seen = {}
                        for _, rune in ipairs(col) do
                            if seen[rune] then Fail("%s seed %d: repeated rune in a column", setup.name, s) end
                            seen[rune] = true
                        end
                        local all = true
                        for _, g in ipairs(m.glyphs) do all = all and seen[g] == true end
                        if all then holding = holding + 1 end
                    end
                    if holding ~= 1 then
                        Fail("%s seed %d: %d columns hold all four glyphs", setup.name, s, holding)
                    end
                    local used = {}
                    for _, pos in ipairs(m.answer) do used[pos] = true end
                    if #m.answer ~= 4 or not (used[1] and used[2] and used[3] and used[4]) then
                        Fail("%s seed %d: glyph answer is not an order of A-D", setup.name, s)
                    end
                    if setup.depth == "plain" then
                        local expect = {}
                        for _, rune in ipairs(m.columns[m.column]) do
                            for pos, g in ipairs(m.glyphs) do
                                if g == rune then expect[#expect + 1] = pos end
                            end
                        end
                        if table.concat(expect, ",") ~= table.concat(m.answer, ",") then
                            Fail("%s seed %d: plain glyph order wrong", setup.name, s)
                        end
                    end
                else
                    for rune = 1, 10 do
                        if m.left[rune] == rune or m.right[rune] == rune then
                            Fail("%s seed %d: dial maps a rune to itself", setup.name, s)
                        end
                    end
                    if m.afterGlyphs then
                        local glyphs
                        for _, other in ipairs(ward.modules) do
                            if other.kind == "glyphs" then glyphs = other end
                        end
                        local last = glyphs.glyphs[glyphs.answer[#glyphs.answer]]
                        if m.answer ~= PuzzleWardGen.RingNext(ward, last) then
                            Fail("%s seed %d: chained dial answer wrong", setup.name, s)
                        end
                    elseif m.twoColumns and ward.face.candles > 3 then
                        if m.answer ~= m.right[m.waking] then Fail("%s seed %d: right column", setup.name, s) end
                    elseif m.answer ~= m.left[m.waking] then
                        Fail("%s seed %d: left column", setup.name, s)
                    end
                end
            end
        end
    end
    local spread = {}
    local hasThreads = false
    for _, kind in ipairs(setup.modules) do hasThreads = hasThreads or kind == "threads" end
    if hasThreads then
        local total = 0
        for line = 1, perPage + 1 do total = total + (decided[line] or 0) end
        for line = 1, perPage + 1 do
            local share = (decided[line] or 0) / math.max(1, total)
            spread[#spread + 1] = string.format("%d:%d%%", line, math.floor(share * 100 + 0.5))
            if share < 0.05 then
                Fail("%s: line %d decides only %.1f%% of the time", setup.name, line, share * 100)
            end
        end
    end
    print(string.format("%-20s %5d seeds  %.2fs  deciding line %s", setup.name, SEEDS, os.clock() - started, table.concat(spread, " ")))
end

if failures > 0 then
    print(string.format("%d FAILURES", failures))
    os.exit(1)
end
print("ALL PASSED")
