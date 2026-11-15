local mod = dmhub.GetModLoading()

-- The "Warded seal" puzzle type: split-information co-op (split-info-coop-brief.md). One
-- player, the hands, sees a generated runic ward and acts on it; the others hold its codex
-- pages and must talk them through. The ward and codex come from PuzzleWardGen; the host
-- deals the parts at Begin and decides every action.
--
-- State:
--   phase   = "gathering" | "playing"
--   ward    = the generated ward (PuzzleWardGen), written once by the host at Begin
--   parts   = { hands = userid, solo = boolean, readers = { <userid> = "m1,L2" } }
--   act     = { m1 = { cut = { t3 = true } }, m2 = { lit = "2,4" }, m3 = { pos = 5, set = 7 } }
--   strikes = number; log = { <guid> = {at, text} }

local LOG_LINES = 6

--The ward's own art, fixed whatever the app's theme.
local WARD_BG = "#15121cff"
local WARD_BORDER = "#6c5a8cff"
local GLYPH_LIT = "#f2c96bff"
local RUNE_TINT = "#e9e2f5ff"

local PRESETS = {
    simple = { count = 0, depth = "plain", strikes = 3 }, --count 0: one or two, by the seed
    vault = { count = 3, depth = "conditional", strikes = 3 },
    archmage = { count = 4, depth = "chained", strikes = 2 },
}

local KIND_NAMES = { threads = "Threads", glyphs = "Glyphs", dial = "Sigil dial" }

---@param config table
---@return {count: integer, depth: string, strikes: integer, kinds: string}
local function Effective(config)
    local preset = PRESETS[config.preset or "vault"]
    if preset ~= nil then
        return { count = preset.count, depth = preset.depth, strikes = preset.strikes, kinds = "mixed" }
    end
    return {
        count = math.max(1, math.min(4, math.tointeger(tonumber(config.modules)) or 3)),
        depth = tostring(config.depth or "conditional"),
        strikes = math.max(1, math.min(5, math.tointeger(tonumber(config.strikes)) or 3)),
        kinds = tostring(config.kinds or "mixed"),
    }
end

--The module kinds for a ward, in order.
---@param eff table
---@param random fun(k: integer): integer
---@return string[]
local function ModuleKinds(eff, random)
    local count = eff.count
    if count == 0 then
        count = random(2)
    end
    if eff.kinds ~= "mixed" then
        local kinds = {}
        for i = 1, count do
            kinds[i] = eff.kinds
        end
        return kinds
    end
    local order = { "threads", "glyphs", "dial" }
    for i = #order, 2, -1 do
        local j = random(i)
        order[i], order[j] = order[j], order[i]
    end
    order[4] = "threads"
    local kinds = {}
    for i = 1, count do
        kinds[i] = order[i]
    end
    return kinds
end

--------------------------------------------------------------------------------
-- Reading the board
--------------------------------------------------------------------------------

---@param state table
---@param i integer
---@return table
local function Act(state, i)
    local act = type(state.act) == "table" and state.act["m" .. i] or nil
    if type(act) ~= "table" then
        return {}
    end
    return act
end

---@param text any
---@return integer[]
local function Numbers(text)
    local result = {}
    for part in string.gmatch(tostring(text or ""), "[^,]+") do
        result[#result + 1] = math.tointeger(tonumber(part)) or 0
    end
    return result
end

---@param state table
---@param i integer
---@return boolean
local function ModuleDone(state, i)
    local ward = state.ward
    local m = ward ~= nil and ward.modules[i] or nil
    if m == nil then
        return false
    end
    local act = Act(state, i)
    if m.kind == "threads" then
        return type(act.cut) == "table" and act.cut["t" .. m.answer] == true
    elseif m.kind == "glyphs" then
        return #Numbers(act.lit) >= 4
    end
    return act.set ~= nil and act.set == m.answer
end

--A dial that waits on the Glyphs is sealed until every Glyphs module is done.
---@param state table
---@param i integer
---@return boolean
local function ModuleSealed(state, i)
    local m = state.ward.modules[i]
    if m.kind ~= "dial" or not m.afterGlyphs then
        return false
    end
    for k, other in ipairs(state.ward.modules) do
        if other.kind == "glyphs" and not ModuleDone(state, k) then
            return true
        end
    end
    return false
end

---@param ward table
---@return string[] page keys: "m1".."mN", plus "L1".."L3" when the rules refer to the Lexicon
local function PageKeys(ward)
    local keys = {}
    for i in ipairs(ward.modules) do
        keys[#keys + 1] = "m" .. i
    end
    if ward.depth == "chained" then
        for k = 1, 3 do
            keys[#keys + 1] = "L" .. k
        end
    end
    return keys
end

---@param ward table
---@param key string
---@return {title: string, intro: string, lines: string[]}|nil
local function PageFor(ward, key)
    local kind, n = key:sub(1, 1), math.tointeger(tonumber(key:sub(2)))
    if n == nil then
        return nil
    end
    if kind == "m" and ward.modules[n] ~= nil then
        return PuzzleWardGen.PageText(ward, n)
    elseif kind == "L" then
        return PuzzleWardGen.LexiconText(ward)[n]
    end
    return nil
end

--What this player holds: "hands", "reader", "solo", "director" or "watching".
---@param state table
---@param userid string
---@param isDirector boolean
---@return string role, string[] pages
local function RoleOf(state, userid, isDirector)
    local parts = type(state.parts) == "table" and state.parts or {}
    if parts.hands == userid then
        return cond(parts.solo == true, "solo", "hands"), {}
    end
    local pages = type(parts.readers) == "table" and parts.readers[userid] or nil
    if type(pages) == "string" then
        local keys = {}
        for key in string.gmatch(pages, "[^,]+") do
            keys[#keys + 1] = key
        end
        return "reader", keys
    end
    if isDirector then
        return "director", {}
    end
    return "watching", {}
end

---@param userid string
---@return boolean
local function IsDirectorUser(userid)
    local dm = false
    pcall(function() dm = dmhub.GetSessionInfo(userid).dm == true end)
    return dm
end

--Players at the seal who can be dealt a part: present, not a Director.
---@param id string
---@return string[]
local function PlayersAtSeal(id)
    local result = {}
    for _, userid in ipairs(Puzzle.PresentUsers(id)) do
        if not IsDirectorUser(userid) then
            result[#result + 1] = userid
        end
    end
    return result
end

---@param ward table
---@param i integer
---@param n integer
---@return string
local function ThreadWords(ward, i, n)
    local t = ward.modules[i].threads[n]
    return string.format("Thread %d (%s, %s)", n, PuzzleRunes.threadColours[t.colour].name, PuzzleRunes.threadPatterns[t.pattern].name)
end

--------------------------------------------------------------------------------
-- The host: dealing and judging
--------------------------------------------------------------------------------

---@param state table
---@param text string
local function Log(state, text)
    state.log = state.log or {}
    --several lines can land in one host tick, so they carry their order.
    state.logSeq = (tonumber(state.logSeq) or 0) + 1
    state.log[dmhub.GenerateGuid()] = { at = dmhub.serverTime, seq = state.logSeq, text = text }
end

---@param id string
---@param state table
---@param config table
---@param requester string
local function Deal(id, state, config, requester)
    local players = PlayersAtSeal(id)
    table.sort(players)
    --nobody but the presser (a Director testing alone): they play solo.
    if #players == 0 then
        players = { requester }
    end
    local random = Puzzle.SeededRandom(dmhub.GenerateGuid())
    local eff = Effective(config)
    local ward = PuzzleWardGen.Generate(random, { modules = ModuleKinds(eff, random), depth = eff.depth })
    for i = #players, 2, -1 do
        local j = random(i)
        players[i], players[j] = players[j], players[i]
    end
    local parts = { hands = players[1], solo = #players == 1, readers = {} }
    if #players > 1 then
        local keys = PageKeys(ward)
        local held = {}
        local readers = {}
        for k = 2, #players do
            readers[#readers + 1] = players[k]
            held[players[k]] = {}
        end
        for k, key in ipairs(keys) do
            local reader = readers[(k - 1) % #readers + 1]
            held[reader][#held[reader] + 1] = key
        end
        --more readers than pages: the extra readers get copies, spread round the pages.
        for k = #keys + 1, #readers do
            local reader = readers[k]
            held[reader][#held[reader] + 1] = keys[(k - 1) % #keys + 1]
        end
        for reader, pages in pairs(held) do
            parts.readers[reader] = table.concat(pages, ",")
        end
    end
    state.phase = "playing"
    state.ward = ward
    state.parts = parts
    state.act = {}
    state.strikes = 0
    if parts.solo then
        Log(state, string.format("%s faces the ward alone.", Puzzle.UserName(parts.hands)))
    else
        Log(state, string.format("%s has the ward in hand; the others hold the codex.", Puzzle.UserName(parts.hands)))
    end
end

---@param state table
---@param config table
---@param userid string
---@param words string what was done, for the strike line
local function Strike(state, config, userid, words)
    state.strikes = (state.strikes or 0) + 1
    local limit = Effective(config).strikes
    if state.strikes >= limit then
        Log(state, string.format("%s %s: the ward bursts!", Puzzle.UserName(userid), words))
    else
        Log(state, string.format("Strike %d of %d: %s %s.", state.strikes, limit, Puzzle.UserName(userid), words))
    end
end

---@type PuzzleRequestHandler
local function HandleRequest(id, state, req, userid, after)
    local config = Puzzle.ReadConfig(id)
    if req.kind == "begin" then
        if state.phase ~= "playing" then
            Deal(id, state, config, userid)
        end
        return
    end
    if state.phase ~= "playing" or state.ward == nil then
        return
    end
    local parts = state.parts or {}
    if parts.hands ~= userid then
        return
    end
    local limit = Effective(config).strikes
    if (state.strikes or 0) >= limit then
        return
    end
    local i = math.tointeger(tonumber(req.module))
    local m = i ~= nil and state.ward.modules[i] or nil
    if i == nil or m == nil or ModuleDone(state, i) or ModuleSealed(state, i) then
        return
    end
    state.act = state.act or {}
    state.act["m" .. i] = state.act["m" .. i] or {}
    local act = state.act["m" .. i]
    if req.kind == "cut" and m.kind == "threads" then
        local n = math.tointeger(tonumber(req.thread))
        if n == nil or n < 1 or n > #m.threads then
            return
        end
        act.cut = act.cut or {}
        if act.cut["t" .. n] then
            return
        end
        act.cut["t" .. n] = true
        if n == m.answer then
            Log(state, string.format("%s cut %s. The threads go dark.", Puzzle.UserName(userid), ThreadWords(state.ward, i, n)))
        else
            Strike(state, config, userid, "cut " .. ThreadWords(state.ward, i, n))
        end
    elseif req.kind == "touch" and m.kind == "glyphs" then
        local pos = math.tointeger(tonumber(req.glyph))
        if pos == nil or pos < 1 or pos > 4 then
            return
        end
        local lit = Numbers(act.lit)
        for _, p in ipairs(lit) do
            if p == pos then
                return
            end
        end
        local name = string.format("Glyph %s (%s)", PuzzleWardGen.letters[pos], PuzzleRunes.Name(m.glyphs[pos]))
        if m.answer[#lit + 1] == pos then
            lit[#lit + 1] = pos
            act.lit = table.concat(lit, ",")
            if #lit >= 4 then
                Log(state, string.format("%s touched %s. The glyphs burn out.", Puzzle.UserName(userid), name))
            end
        else
            Strike(state, config, userid, "touched " .. name)
        end
    elseif req.kind == "set" and m.kind == "dial" then
        local rune = math.tointeger(tonumber(req.rune))
        if rune == nil or rune < 1 or rune > #PuzzleRunes.list then
            return
        end
        if rune == m.answer then
            act.set = rune
            Log(state, string.format("%s set the dial to %s. The sigil sinks into the stone.", Puzzle.UserName(userid), PuzzleRunes.Name(rune)))
        else
            Strike(state, config, userid, "set the dial to " .. PuzzleRunes.Name(rune))
        end
    end
end

---@param id string
local function HostTick(id)
    local status = Puzzle.Status(id)
    if status.solved or status.failed then
        return
    end
    local after = {}
    Puzzle.Change(id, function(state)
        if not Puzzle.ProcessRequests(id, state, HandleRequest, after) then
            return false
        end
    end, "Warded seal")
    for _, fn in ipairs(after) do
        pcall(fn)
    end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

--Private pencil marks: puzzle id -> "key:line" -> true. Never synced.
---@type table<string, table<string, boolean>>
local g_pencil = {}

---@param ctx PuzzleContext
---@return Panel
local function Render(ctx)
    local m_ctx = ctx
    local m_confirmSolo = false
    local m_gatherKey = nil
    local resultPanel
    local body

    local function State()
        return m_ctx.state or {}
    end

    local function Request(args)
        Puzzle.Request(m_ctx.id, args)
    end

    local Refresh

    ---@param text string
    ---@param classes string[]|nil
    ---@param extra table|nil
    ---@return Panel
    local function Label(text, classes, extra)
        local args = { classes = classes or {"sizeS"}, width = "auto", maxWidth = 520, height = "auto", text = text }
        for k, v in pairs(extra or {}) do
            args[k] = v
        end
        return gui.Label(args)
    end

    local function RuneIcon(rune, size, color)
        local r = PuzzleRunes.list[rune]
        return gui.Panel{
            width = size,
            height = size,
            valign = "center",
            bgimage = r ~= nil and r.icon or "panels/square.png",
            bgcolor = color or RUNE_TINT,
            interactable = false,
        }
    end

    local function Gathering()
        local players = PlayersAtSeal(m_ctx.id)
        local names = {}
        for i, userid in ipairs(players) do
            names[i] = Puzzle.UserName(userid)
        end
        local children = {}
        if #names == 0 then
            children[#children + 1] = Label("Nobody is at the seal yet.", {"sizeM"})
        else
            children[#children + 1] = Label(string.format("At the seal: %s.", table.concat(names, ", ")), {"sizeM"})
        end
        children[#children + 1] = Label("Waiting for the others. Anyone can begin; the parts are dealt then.", {"sizeS", "fgMuted"})
        if m_ctx.isDirector then
            children[#children + 1] = Label("Directors are not dealt a part.", {"sizeS", "fgMuted"})
        end
        if m_confirmSolo then
            children[#children + 1] = Label("You alone will see the ward and its codex. Begin?", {"sizeM"}, { tmargin = 6 })
            children[#children + 1] = gui.Panel{
                flow = "horizontal", width = "auto", height = "auto",
                gui.Button{ classes = {"sizeS"}, text = "Begin alone", width = 120, hmargin = 4,
                    click = function() m_confirmSolo = false Request({ kind = "begin" }) end },
                gui.Button{ classes = {"sizeS"}, text = "Cancel", width = 90,
                    click = function() m_confirmSolo = false Refresh() end },
            }
        else
            children[#children + 1] = gui.Button{
                classes = {"sizeM"},
                text = "Begin",
                width = 140,
                tmargin = 8,
                click = function()
                    if #players <= 1 then
                        m_confirmSolo = true
                        Refresh()
                        return
                    end
                    Request({ kind = "begin" })
                end,
            }
        end
        return children
    end

    --The shared view everyone gets: the modules, their state and who holds each page.
    local function ModuleList()
        local state = State()
        local holders = {}
        for userid, pages in pairs((state.parts or {}).readers or {}) do
            for key in string.gmatch(tostring(pages), "[^,]+") do
                holders[key] = holders[key] or {}
                holders[key][#holders[key] + 1] = Puzzle.UserName(userid)
            end
        end
        local lines = {}
        for i, m in ipairs(state.ward.modules) do
            local status
            if ModuleDone(state, i) then
                status = "done"
            elseif ModuleSealed(state, i) then
                status = "sealed until the Glyphs are done"
            else
                status = "unbroken"
            end
            local who = holders["m" .. i]
            lines[#lines + 1] = string.format("%d. %s -- %s%s", i, KIND_NAMES[m.kind], status,
                who ~= nil and (" -- page: " .. table.concat(who, ", ")) or "")
        end
        for k = 1, 3 do
            local who = holders["L" .. k]
            if who ~= nil then
                lines[#lines + 1] = string.format("Lexicon %d -- page: %s", k, table.concat(who, ", "))
            end
        end
        return Label(table.concat(lines, "\n"), {"sizeS"}, { tmargin = 4 })
    end

    local function WardFace()
        local face = State().ward.face
        return gui.Panel{
            flow = "horizontal", width = "auto", height = "auto", vmargin = 4,
            Label("Rim:", {"sizeM"}, { valign = "center" }),
            RuneIcon(face.rim, 28),
            Label(string.format("%s.   Candles lit: %d", PuzzleRunes.Name(face.rim), face.candles), {"sizeM"}, { valign = "center", hmargin = 6 }),
        }
    end

    local function ThreadsView(i, m, canAct)
        local act = Act(State(), i)
        local rows = {}
        for n, t in ipairs(m.threads) do
            local severed = type(act.cut) == "table" and act.cut["t" .. n] == true
            local words = string.format("Thread %d: %s, %s%s", n, PuzzleRunes.threadColours[t.colour].name,
                PuzzleRunes.threadPatterns[t.pattern].name, severed and " (severed)" or "")
            local thread = n
            rows[#rows + 1] = gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", vmargin = 1,
                gui.Panel{
                    width = 260, height = 20, valign = "center", opacity = severed and 0.35 or 1,
                    PuzzleRunes.ThreadPanel(t.colour, t.pattern, 260, 8),
                },
                Label(words, {"sizeS"}, { width = 220, valign = "center", hmargin = 8 }),
                (canAct and not severed) and gui.Button{
                    classes = {"sizeXs"}, text = "Cut", width = 50, height = 22, valign = "center",
                    click = function() Request({ kind = "cut", module = i, thread = thread }) end,
                } or nil,
            }
        end
        return rows
    end

    local function GlyphsView(i, m, canAct)
        local lit = {}
        for _, p in ipairs(Numbers(Act(State(), i).lit)) do
            lit[p] = true
        end
        local cells = {}
        for pos, rune in ipairs(m.glyphs) do
            local p = pos
            cells[#cells + 1] = gui.Panel{
                flow = "vertical", width = 96, height = "auto", hmargin = 4,
                gui.Panel{
                    width = 56, height = 56, halign = "center",
                    bgimage = "panels/square.png", bgcolor = WARD_BG,
                    border = lit[pos] and 3 or 1, borderColor = lit[pos] and GLYPH_LIT or WARD_BORDER,
                    press = function()
                        if canAct and not lit[p] then
                            Request({ kind = "touch", module = i, glyph = p })
                        end
                    end,
                    gui.Panel{ width = 40, height = 40, halign = "center", valign = "center",
                        bgimage = PuzzleRunes.list[rune].icon, bgcolor = lit[pos] and GLYPH_LIT or RUNE_TINT, interactable = false },
                },
                Label(string.format("%s: %s%s", PuzzleWardGen.letters[pos], PuzzleRunes.Name(rune), lit[pos] and " (lit)" or ""),
                    {"sizeS"}, { halign = "center", textAlignment = "center", width = 96 }),
            }
        end
        return { gui.Panel{ flow = "horizontal", width = "auto", height = "auto", children = cells } }
    end

    local function DialView(i, m, canAct)
        local state = State()
        local act = Act(state, i)
        local pos = math.tointeger(tonumber(act.pos)) or m.waking
        local live = canAct and not ModuleSealed(state, i)
        local function Turn(step)
            local n = #PuzzleRunes.list
            local v = ((pos - 1 + step) % n) + 1
            m_ctx:Change(function(st)
                st.act = st.act or {}
                st.act["m" .. i] = st.act["m" .. i] or {}
                st.act["m" .. i].pos = v
            end, "Turn the dial")
        end
        local rows = {
            Label(string.format("Woke on %s.", PuzzleRunes.Name(m.waking)), {"sizeS"}),
            gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", vmargin = 2,
                live and gui.Button{ classes = {"sizeXs"}, text = "-", width = 30, height = 24, valign = "center", click = function() Turn(-1) end } or nil,
                gui.Panel{ width = 56, height = 56, hmargin = 6, bgimage = "panels/square.png", bgcolor = WARD_BG, border = 2, borderColor = WARD_BORDER,
                    RuneIcon(pos, 40) },
                live and gui.Button{ classes = {"sizeXs"}, text = "+", width = 30, height = 24, valign = "center", click = function() Turn(1) end } or nil,
                Label(PuzzleRunes.Name(pos), {"sizeM"}, { valign = "center", hmargin = 8 }),
                live and gui.Button{ classes = {"sizeS"}, text = "Set the seal", width = 120, valign = "center", hmargin = 8,
                    click = function() Request({ kind = "set", module = i, rune = pos }) end } or nil,
            },
        }
        if ModuleSealed(state, i) then
            rows[#rows + 1] = Label("Sealed until the Glyphs are done.", {"sizeS", "fgMuted"})
        end
        return rows
    end

    --The ward itself: face and every module, for the hands (and solo, and the Director).
    local function WardView(canAct)
        local state = State()
        local children = { WardFace() }
        for i, m in ipairs(state.ward.modules) do
            local done = ModuleDone(state, i)
            children[#children + 1] = Label(string.format("%d. %s%s", i, KIND_NAMES[m.kind], done and " (done)" or ""), {"sizeM", "bold"}, { tmargin = 6 })
            local rows = {}
            if not done then
                if m.kind == "threads" then
                    rows = ThreadsView(i, m, canAct)
                elseif m.kind == "glyphs" then
                    rows = GlyphsView(i, m, canAct)
                else
                    rows = DialView(i, m, canAct)
                end
            end
            for _, row in ipairs(rows) do
                children[#children + 1] = row
            end
        end
        return gui.Panel{
            flow = "vertical", width = "auto", height = "auto", pad = 10, borderBox = true, tmargin = 4,
            bgimage = "panels/square.png", bgcolor = WARD_BG, border = 1, borderColor = WARD_BORDER,
            children = children,
        }
    end

    --A codex page: click a rule to pencil it out (only you see it).
    local function PageView(key)
        local page = PageFor(State().ward, key)
        if page == nil then
            return nil
        end
        local pencil = g_pencil[m_ctx.id] or {}
        g_pencil[m_ctx.id] = pencil
        local children = {
            Label(page.title, {"sizeM", "bold"}),
            Label(page.intro, {"sizeS", "fgMuted"}),
        }
        if key:sub(1, 1) == "m" then
            children[#children + 1] = Label(PuzzleWardGen.pageHeader, {"sizeS", "bold"})
        end
        for n, line in ipairs(page.lines) do
            local mark = key .. ":" .. n
            local out = pencil[mark] == true
            children[#children + 1] = gui.Label{
                classes = {"sizeS", out and "fgMuted" or "fg"},
                width = 480, height = "auto", vmargin = 1,
                text = out and ("<s>" .. line .. "</s>") or line,
                press = function()
                    pencil[mark] = (not out) or nil
                    Refresh()
                end,
            }
        end
        return gui.Panel{ flow = "vertical", width = "auto", height = "auto", tmargin = 8, children = children }
    end

    local function LogText()
        local entries = {}
        for _, e in pairs(State().log or {}) do
            if type(e) == "table" then
                entries[#entries + 1] = e
            end
        end
        table.sort(entries, function(a, b) return (tonumber(a.seq) or 0) < (tonumber(b.seq) or 0) end)
        local lines = {}
        for i = math.max(1, #entries - LOG_LINES + 1), #entries do
            lines[#lines + 1] = entries[i].text
        end
        return table.concat(lines, "\n")
    end

    local function Playing()
        local state = State()
        local role, pages = RoleOf(state, m_ctx.userid, m_ctx.isDirector)
        local canAct = (role == "hands" or role == "solo") and not m_ctx.readonly
        local children = {}
        local card
        if role == "hands" then
            card = "You are the hands. Only you can see the ward and act. Describe it; the others hold the rules."
        elseif role == "solo" then
            card = "You alone hold the ward and its codex."
        elseif role == "reader" then
            local titles = {}
            for k, key in ipairs(pages) do
                local page = PageFor(state.ward, key)
                titles[k] = page ~= nil and page.title or key
            end
            card = string.format("You hold the %s page%s. Ask the hands about what they see.", table.concat(titles, " and "), #pages > 1 and "s" or "")
        elseif role == "director" then
            card = "Director's view: you see the ward and every page. The players hold the parts."
        else
            card = "You are watching. The players hold the parts."
        end
        children[#children + 1] = Label(card, {"sizeM", "bold"})
        children[#children + 1] = ModuleList()
        if role == "hands" or role == "solo" or role == "director" then
            children[#children + 1] = WardView(canAct)
        end
        local show = pages
        if role == "solo" or role == "director" then
            show = PageKeys(state.ward)
        end
        for _, key in ipairs(show) do
            local page = PageView(key)
            if page ~= nil then
                children[#children + 1] = page
            end
        end
        local log = LogText()
        if log ~= "" then
            children[#children + 1] = Label(log, {"sizeS"}, { tmargin = 8 })
        end
        return children
    end

    Refresh = function()
        if not resultPanel.valid then
            return
        end
        if State().phase == "playing" and State().ward ~= nil then
            body.children = Playing()
        else
            body.children = Gathering()
        end
    end

    body = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        vscroll = true,
        maxHeight = 720,
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        refreshPuzzle = function(element, newCtx)
            m_ctx = newCtx
            Refresh()
        end,
        --the gathering list follows presence, which changes without a board write.
        thinkTime = 2,
        think = function(element)
            if State().phase ~= "playing" then
                local key = table.concat(PlayersAtSeal(m_ctx.id), ",")
                if key ~= m_gatherKey then
                    m_gatherKey = key
                    Refresh()
                end
            end
        end,
        body,
    }
    return resultPanel
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

---@param config table
---@return boolean
local function IsCustom(config)
    return config.preset == "custom"
end

PuzzleType.Register{
    id = "wardedseal",
    name = "Warded seal",
    fields = {
        { id = "preset", type = "choice", label = "Seal", default = "vault", options = {
            { id = "simple", text = "Simple ward (1-2 modules, plain rules)" },
            { id = "vault", text = "Warded vault (3 modules, some conditions)" },
            { id = "archmage", text = "Archmage's seal (4 modules, chained rules, 2 strikes)" },
            { id = "custom", text = "Customize" },
        } },
        { id = "modules", type = "number", label = "Modules", default = 3, min = 1, max = 4, visible = IsCustom },
        { id = "kinds", type = "choice", label = "Module kinds", default = "mixed", visible = IsCustom, options = {
            { id = "mixed", text = "Mixed" },
            { id = "threads", text = "Threads only" },
            { id = "glyphs", text = "Glyphs only" },
            { id = "dial", text = "Sigil dials only" },
        } },
        { id = "depth", type = "choice", label = "Rules", default = "conditional", visible = IsCustom, options = {
            { id = "plain", text = "Plain" },
            { id = "conditional", text = "Some conditions" },
            { id = "chained", text = "Chained (uses the Lexicon)" },
        } },
        { id = "strikes", type = "number", label = "Strikes before it bursts", default = 3, min = 1, max = 5, visible = IsCustom },
        { id = "hint", type = "text", label = "Hint", default = "" },
    },
    --changing what the ward is made of makes a new ward.
    ConfigKey = function(config)
        local eff = Effective(config)
        return string.format("%s|%d|%s|%d|%s", tostring(config.preset), eff.count, eff.depth, eff.strikes, eff.kinds)
    end,
    NewState = function(config, ctx)
        return { phase = "gathering", act = {}, strikes = 0, log = {} }
    end,
    IsSolved = function(state, config)
        if state.phase ~= "playing" or type(state.ward) ~= "table" then
            return false
        end
        for i in ipairs(state.ward.modules) do
            if not ModuleDone(state, i) then
                return false
            end
        end
        return true
    end,
    IsFailed = function(state, config, now)
        return state.phase == "playing" and (state.strikes or 0) >= Effective(config).strikes
    end,
    Hint = function(state, config)
        local hint = tostring(config.hint or "")
        if hint == "" then
            return nil
        end
        return hint
    end,
    Status = function(state, config)
        if state.phase ~= "playing" then
            return nil
        end
        return string.format("Strikes: %d of %d", state.strikes or 0, Effective(config).strikes)
    end,
    HostTick = HostTick,
    Render = Render,
}
