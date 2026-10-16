--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/journal_text_roundtrip_test.lua [seed] [steps]
--Fuzzes the journal's text persistence against the production code: TextStorage
--sharding, CustomDocument Get/SetTextContent, and the in-place control path
--(MarkdownDocument MutateLine / PatchToken). Every run is deterministic for its
--seed, and a failure names the seed and step to replay.
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true), "marker not found: " .. first)
    local finish = assert(source:find(last, start + #first, true), "marker not found: " .. last)
    return source:sub(start, finish - 1)
end

local function loadSection(path, first, last)
    assert(load(section(path, first, last), "@" .. path))()
end

local g_types = {}
function RegisterGameType(name, base)
    local class = {}
    class.__index = class
    if base ~= nil then
        setmetatable(class, { __index = g_types[base] })
    end
    class.new = function(o)
        return setmetatable(o or {}, class)
    end
    g_types[name] = class
    return class
end

dmhub = { GetModLoading = function() return {} end }

loadSection("DMHub Utils/Utils.lua", "function table.keys(t)", "function table.mapped_keys")
loadSection("DMHub Utils/Utils.lua", "function string.split_allow_duplicates", "function string.split_with_square_brackets")
dofile("DocumentSystem/TextStorage.lua")

CustomDocument = RegisterGameType("CustomDocument")
CustomDocument.textStorage = false
loadSection("DocumentSystem/DocumentSystem.lua", "function CustomDocument.OnDeserialize(self)", "function CustomDocument:Render()")
loadSection("DocumentSystem/DocumentSystem.lua", "local function NormalizeDocumentText", "--Default creation behaviour")

MarkdownDocument = RegisterGameType("MarkdownDocument", "CustomDocument")
loadSection("DocumentSystem/MarkdownDocument.lua", "function MarkdownDocument:MutateLine", "function MarkdownDocument:GetRollableTableFromTokens")

local seed = tonumber(arg and arg[1]) or 20261005
local steps = tonumber(arg and arg[2]) or 4000
math.randomseed(seed)

local passed = 0
local g_where = "setup"
local function check(condition, message)
    if not condition then
        error(string.format("FAILED (seed %d, %s): %s", seed, g_where, tostring(message)), 2)
    end
    passed = passed + 1
end

local function rnd(n) return math.random(n) end
local function chance(p) return math.random() < p end
local function pick(list) return list[rnd(#list)] end

----------------------------------------------------------------------
-- Shared invariants
----------------------------------------------------------------------

local g_keyPattern = "^[A-Za-z]+$"

--What a save and reload does to a TextStorage: the sections survive as a plain
--map, in no particular order.
local function Persisted(storage)
    local sections = {}
    for k, v in pairs(storage.sections) do
        sections[k] = v
    end
    return TextStorage.new{ sections = sections }
end

local function CheckStorage(storage, expected)
    check(storage:GetContent() == expected, "content does not round-trip")
    check(Persisted(storage):GetContent() == expected, "content does not survive a save and reload")
    for k, v in pairs(storage.sections) do
        check(type(k) == "string" and k:match(g_keyPattern) ~= nil, "malformed section key " .. tostring(k))
        check(type(v) == "string" and v ~= "", "empty or non-string section at " .. tostring(k))
    end
end

----------------------------------------------------------------------
-- 1. TextStorage round-trip
----------------------------------------------------------------------

local g_words = {
    "the", "heroes", "a", "", "## Heading", "x", "[[encounter]]", "{spoiler}", "|row|cell|",
    "Negotiation", "caf\195\169", "\226\128\148", "   ", "\t", "*italic*", "[ ] task", "ok", "no",
}

local function RandomLine()
    if chance(0.12) then return "" end
    if chance(0.05) then return string.rep(pick(g_words) .. " ", 80 + rnd(120)) end
    local parts = {}
    for i = 1, rnd(9) do
        parts[i] = pick(g_words)
    end
    return table.concat(parts, " ")
end

local function RandomLines(n)
    local lines = {}
    for i = 1, n do
        --Repeated lines are deliberate: SetContent matches unchanged sections
        --from both ends, and identical neighbours are where that can go wrong.
        lines[i] = (i > 1 and chance(0.15)) and lines[rnd(i - 1)] or RandomLine()
    end
    return lines
end

local function EditLines(lines)
    local op = rnd(10)
    local n = #lines
    if op == 1 or n == 0 then
        table.insert(lines, rnd(n + 1), RandomLine())
    elseif op == 2 then
        table.remove(lines, rnd(n))
    elseif op == 3 then
        lines[rnd(n)] = RandomLine()
    elseif op == 4 then
        local i = rnd(n)
        local at = rnd(#lines[i] + 1) - 1
        lines[i] = lines[i]:sub(1, at) .. pick(g_words) .. lines[i]:sub(at + 1 + rnd(3) - 1)
    elseif op == 5 then
        local i, j = rnd(n), rnd(n)
        lines[i], lines[j] = lines[j], lines[i]
    elseif op == 6 then
        local from = rnd(n)
        for k = from, math.min(n, from + rnd(6)) do
            table.insert(lines, rnd(#lines + 1), lines[k])
        end
    elseif op == 7 then
        local from = rnd(n)
        for _ = 1, math.min(n - from + 1, rnd(8)) do
            table.remove(lines, from)
        end
    elseif op == 8 then
        table.insert(lines, 1, RandomLine())
    elseif op == 9 then
        lines[#lines + 1] = RandomLine()
    elseif chance(0.1) then
        for i = n, 1, -1 do lines[i] = nil end
    end
    return lines
end

local function Join(lines)
    return table.concat(lines, "\n")
end

do
    local lines = RandomLines(40)
    local storage = TextStorage.Create(Join(lines))
    CheckStorage(storage, Join(lines))

    for step = 1, steps do
        g_where = "storage step " .. step
        if chance(0.02) then
            lines = RandomLines(rnd(120))
        else
            EditLines(lines)
        end
        local text = Join(lines)

        --The same edit on a second copy of the same document must produce the
        --same keys. Two clients writing identical text then collide and
        --overwrite, where differing keys would leave both copies' sections in
        --the document.
        local twin = Persisted(storage)

        storage:SetContent(text)
        CheckStorage(storage, text)

        --Sections the edit did not reach keep their keys, so a save uploads
        --only what changed. Losing this means every edit re-keys the document.
        local oldKeys = table.keys(twin.sections)
        table.sort(oldKeys)
        local rest = text
        for _, k in ipairs(oldKeys) do
            local value = twin.sections[k]
            if value ~= rest:sub(1, #value) then
                break
            end
            check(storage.sections[k] == value, "an untouched leading section lost its key " .. k)
            rest = rest:sub(#value + 1)
        end

        twin:SetContent(text)
        for k, v in pairs(storage.sections) do
            check(twin.sections[k] == v, "the same edit produced different sections at " .. k)
        end
        for k, _ in pairs(twin.sections) do
            check(storage.sections[k] ~= nil, "the same edit produced an extra section at " .. k)
        end

        if chance(0.05) then
            storage = Persisted(storage)
        end
    end
end

--Documents written by the earlier key generator can hold neighbouring keys
--with no room between them. Editing one must heal it, never lose text.
do
    local g_keyChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    for round = 1, math.max(1, steps // 20) do
        g_where = "legacy keys round " .. round
        local keys, seen = {}, {}
        local count = 1 + rnd(30)
        while #keys < count do
            local key = ""
            for _ = 1, rnd(3) do
                local c = chance(0.4) and 1 or rnd(#g_keyChars)
                key = key .. g_keyChars:sub(c, c)
            end
            if not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)

        local sections, lines = {}, {}
        for i, key in ipairs(keys) do
            lines[i] = RandomLine()
            sections[key] = lines[i] .. "\n"
        end
        lines[#lines + 1] = ""

        local storage = TextStorage.new{ sections = sections }
        CheckStorage(storage, Join(lines))

        for _ = 1, 12 do
            EditLines(lines)
            storage:SetContent(Join(lines))
            CheckStorage(storage, Join(lines))
        end
    end
end

----------------------------------------------------------------------
-- 2. CustomDocument text access
----------------------------------------------------------------------

do
    g_where = "document text"
    local legacy = CustomDocument.new{ content = "# Old\r\nbody\r" }
    check(legacy:GetTextContent() == "# Old\nbody", "legacy content is not read with carriage returns removed")

    for round = 1, math.max(1, steps // 20) do
        g_where = "document text round " .. round
        local doc = CustomDocument.new{}
        check(doc:GetTextContent() == "", "a new document is not empty")
        for _ = 1, 8 do
            local raw = table.concat(RandomLines(rnd(30)), pick{ "\n", "\r\n", "\n", "\r" })
            local expected = (raw:gsub("\r", ""))
            doc:SetTextContent(raw)
            check(doc:GetTextContent() == expected, "document text does not round-trip")
            check(rawget(doc, "content") == nil, "SetTextContent wrote the legacy content field")
            CheckStorage(doc.textStorage, expected)
        end

        --A reload that loses the TextStorage metatable must not lose the text.
        local text = doc:GetTextContent()
        local reloaded = CustomDocument.new{ textStorage = { sections = Persisted(doc.textStorage).sections } }
        CustomDocument.OnDeserialize(reloaded)
        check(reloaded:GetTextContent() == text, "text lost when textStorage reloads as a plain table")
    end
end

----------------------------------------------------------------------
-- 3. In-place controls
--
-- The model is a list of lines, each a run of literal text and tokens. A token
-- is addressed by the line's id and its position on the line, never by where
-- it was drawn, so the model always knows which token a click meant. After
-- every click the document must equal the model with that one token changed
-- (the click landed) or the model unchanged (the click was refused). Any other
-- outcome is a splice in the wrong place.
----------------------------------------------------------------------

local g_nextLineId = 0

local function RandomToken()
    if chance(0.5) then
        return pick{ "[ ]", "[x]" }
    end
    return "[[" .. (rnd(121) - 1) .. "]]"
end

local function ChangedToken(token)
    if token == "[ ]" then return "[x]" end
    if token == "[x]" then return "[ ]" end
    local value
    repeat
        --Mostly neighbours, so 9 <-> 10 and 99 <-> 100 length changes come up.
        value = chance(0.7) and (tonumber(token:match("%d+")) + pick{ -1, 1 }) or (rnd(121) - 1)
    until value >= 0 and ("[[" .. value .. "]]") ~= token
    return "[[" .. value .. "]]"
end

local g_plainWords = { "Guard", "the", "gate", "", "Interest", "x", "caf\195\169", "Patience:", "and" }

local function RandomModelLine()
    g_nextLineId = g_nextLineId + 1
    local line = { id = g_nextLineId, parts = {} }
    if chance(0.15) then
        --No tokens, so nothing addresses it and it may repeat (blank lines do).
        line.parts[1] = chance(0.5) and "" or pick(g_plainWords)
        return line
    end
    --The id makes every line with a token unique. MutateLine tells lines apart
    --by their text, so two identical lines cannot be told apart by design.
    line.parts[1] = "L" .. line.id .. " "
    for _ = 1, rnd(4) do
        line.parts[#line.parts + 1] = { text = RandomToken() }
        line.parts[#line.parts + 1] = " " .. pick(g_plainWords)
    end
    return line
end

local function RenderLine(line)
    local out = {}
    for i, part in ipairs(line.parts) do
        out[i] = type(part) == "table" and part.text or part
    end
    return table.concat(out)
end

local function RenderModel(model)
    local out = {}
    for i, line in ipairs(model) do
        out[i] = RenderLine(line)
    end
    return table.concat(out, "\n")
end

--What a render hands its controls: one shared `lines` table, and per token the
--line it was on and its byte span on that line.
local function TakeSnapshot(model)
    local lines = string.split_allow_duplicates(RenderModel(model), "\n")
    local tokens = {}
    for lineIndex, line in ipairs(model) do
        local pos = 0
        for partIndex, part in ipairs(line.parts) do
            if type(part) == "table" then
                tokens[#tokens + 1] = {
                    lines = lines, lineIndex = lineIndex, linepos = pos, length = #part.text,
                    lineId = line.id, partIndex = partIndex,
                }
                pos = pos + #part.text
            else
                pos = pos + #part
            end
        end
    end
    return tokens
end

local function FindLine(model, id)
    for i, line in ipairs(model) do
        if line.id == id then
            return line, i
        end
    end
    return nil
end

--Another client, or the open editor, changing the document under the controls.
local function OutsideEdit(model)
    local op = rnd(5)
    if op == 1 or #model == 0 then
        table.insert(model, rnd(#model + 1), RandomModelLine())
    elseif op == 2 then
        table.remove(model, rnd(#model))
    else
        local line = model[rnd(#model)]
        local i = rnd(#line.parts)
        local part = line.parts[i]
        if type(part) == "table" then
            part.text = ChangedToken(part.text)
        elseif i > 1 then
            line.parts[i] = " " .. pick(g_plainWords)
        end
    end
end

local function NewDocument(model)
    local doc = MarkdownDocument.new{}
    doc:SetTextContent(RenderModel(model))
    return doc
end

--Clicks a control. Returns whether the click landed.
local function Click(doc, model, token, replacement)
    local before = RenderModel(model)
    local line, lineIndex = FindLine(model, token.lineId)
    ---@type {text: string}|nil
    local part = line ~= nil and line.parts[token.partIndex] or nil
    local current = part ~= nil and part.text or nil
    local snapshotIsCurrent = line ~= nil and lineIndex == token.lineIndex
        and RenderLine(line) == token.lines[token.lineIndex]

    local applied = doc:PatchToken(token, replacement)

    if applied then
        check(part ~= nil, "a click landed for a token whose line is gone")
        ---@cast part -nil
        part.text = replacement
        check(doc:GetTextContent() == RenderModel(model), "a click wrote somewhere other than its own token")
    else
        check(doc:GetTextContent() == before, "a refused click changed the document")
        check(not (snapshotIsCurrent and current ~= replacement), "a click against an up-to-date render was refused")
    end
    CheckStorage(doc.textStorage, doc:GetTextContent())
    return applied
end

do
    g_where = "controls: two ticks from one render"
    local model = { RandomModelLine(), RandomModelLine() }
    model[1].parts = { "L" .. model[1].id .. " ", { text = "[ ]" }, " one" }
    model[2].parts = { "L" .. model[2].id .. " ", { text = "[ ]" }, " two ", { text = "[[9]]" }, " ", { text = "[[4]]" } }
    local doc = NewDocument(model)
    local tokens = TakeSnapshot(model)
    check(Click(doc, model, tokens[1], "[x]"), "first tick refused")
    check(Click(doc, model, tokens[2], "[x]"), "second tick from the same render refused")

    g_where = "controls: repeat clicks on one control"
    check(Click(doc, model, tokens[1], "[ ]"), "second click on the same control refused")
    check(Click(doc, model, tokens[1], "[x]"), "third click on the same control refused")

    g_where = "controls: self-patch is a no-op"
    check(not Click(doc, model, tokens[2], "[x]"), "patching a token with its own text reported a write")

    g_where = "controls: length change strands its neighbours"
    check(Click(doc, model, tokens[3], "[[10]]"), "length-changing click refused on a fresh line")
    check(not Click(doc, model, tokens[4], "[[5]]"), "a control behind a length change wrote at a stale offset")
    check(not Click(doc, model, tokens[3], "[[11]]"), "a second length-changing click landed before a re-render")

    g_where = "controls: outside edit, then a tick"
    tokens = TakeSnapshot(model)
    table.insert(model, RandomModelLine())
    doc:SetTextContent(RenderModel(model))
    check(Click(doc, model, tokens[1], "[ ]"), "tick refused after an edit to a different line")

    g_where = "controls: line changed underneath"
    tokens = TakeSnapshot(model)
    model[2].parts[3] = " changed "
    doc:SetTextContent(RenderModel(model))
    check(not Click(doc, model, tokens[2], "[ ]"), "tick landed on a line that changed underneath it")

    g_where = "controls: blank lines and a trailing newline survive"
    model = { RandomModelLine(), { id = -1, parts = { "" } }, { id = -2, parts = { "" } }, RandomModelLine(), { id = -3, parts = { "" } } }
    model[1].parts = { "L" .. model[1].id .. " ", { text = "[ ]" } }
    doc = NewDocument(model)
    tokens = TakeSnapshot(model)
    check(Click(doc, model, tokens[1], "[x]"), "tick refused")
    check(doc:GetTextContent():sub(-1) == "\n", "trailing newline lost")
end

do
    local model = {}
    for i = 1, 12 do
        model[i] = RandomModelLine()
    end
    local doc = NewDocument(model)
    local tokens = TakeSnapshot(model)
    local landed, refused = 0, 0

    for step = 1, steps do
        g_where = "controls step " .. step
        local roll = math.random()
        if roll < 0.12 then
            OutsideEdit(model)
            doc:SetTextContent(RenderModel(model))
            check(doc:GetTextContent() == RenderModel(model), "outside edit did not round-trip")
        elseif roll < 0.22 then
            tokens = TakeSnapshot(model)
        elseif roll < 0.24 then
            --Save and reload under the controls.
            doc.textStorage = Persisted(doc.textStorage)
        elseif #tokens > 0 then
            local token = pick(tokens)
            local line = FindLine(model, token.lineId)
            local part = line ~= nil and line.parts[token.partIndex] or nil
            local replacement = type(part) == "table" and ChangedToken(part.text) or RandomToken()
            if chance(0.05) and type(part) == "table" then
                replacement = part.text
            end
            if Click(doc, model, token, replacement) then
                landed = landed + 1
            else
                refused = refused + 1
            end
        end

        if #model > 40 then
            table.remove(model, rnd(#model))
            doc:SetTextContent(RenderModel(model))
        end
    end

    g_where = "controls summary"
    check(landed > steps // 20, "too few clicks landed to mean anything: " .. landed)
    check(refused > steps // 20, "too few clicks were refused to mean anything: " .. refused)
    print(string.format("  controls: %d clicks landed, %d refused", landed, refused))
end

print(string.format("journal_text_roundtrip_test: %d checks passed (seed %d, %d steps)", passed, seed, steps))
