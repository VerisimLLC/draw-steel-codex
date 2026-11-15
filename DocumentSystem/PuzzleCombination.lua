local mod = dmhub.GetModLoading()

-- The "Combination lock" puzzle type: dials the party turns together to a code
-- found elsewhere (a journal page, a torn note, a mural). Design:
-- combination-lock-brief.md. Everyone turns the same dials; "Try the code"
-- checks what the presser sees, so a half-set dial never counts as a try.
--
-- State, all keyed so two players' moves never overwrite each other:
--   dials    = { d1 = 3, d2 = 7, ... }      symbol index on each dial
--   turnedBy = { d1 = userid, ... }         who last set each dial
--   turns    = { "<userid>_d2" = {at, user, dial, value} }  one log line per person per dial
--   tries    = { "<guid>" = {at, user, code} }              every try of the code
--   opened   = "<code>"                     the right code, once tried

local MIN_DIALS = 3
local MAX_DIALS = 6
local MAX_IMAGES = 10
local LOG_LINES = 6

--The lock's own art, fixed whatever the app's theme (as the terminal's screen).
local FACE_BG = "#1d1914ff"
local FACE_BORDER = "#8a6d42ff"
local FACE_BORDER_CURSOR = "#f2c96bff"
local SYMBOL_COLOR = "#ead9b0ff"

local RUNES = {
    { name = "Flame", icon = "phosphor/flame-fill.png" },
    { name = "Eye", icon = "phosphor/eye-fill.png" },
    { name = "Key", icon = "phosphor/key-fill.png" },
    { name = "Moon", icon = "phosphor/moon-fill.png" },
    { name = "Sun", icon = "phosphor/sun-fill.png" },
    { name = "Skull", icon = "phosphor/skull-fill.png" },
    { name = "Star", icon = "phosphor/star-fill.png" },
    { name = "Sword", icon = "phosphor/sword-fill.png" },
    { name = "Crown", icon = "phosphor/crown-simple-fill.png" },
    { name = "Hourglass", icon = "phosphor/hourglass-fill.png" },
}

---@class ComboSymbol
---@field name string
---@field text string|nil drawn as text (digits, letters)
---@field icon string|nil a built-in icon, tinted
---@field image string|nil a Director's image, untinted

--------------------------------------------------------------------------------
-- Setup: symbols, dials, the code
--------------------------------------------------------------------------------

---@param config table
---@return integer
local function DialCount(config)
    local n = math.tointeger(tonumber(config.dials)) or 4
    return math.max(MIN_DIALS, math.min(MAX_DIALS, n))
end

--The Director's images in order, skipping empty slots.
---@param config table
---@return {image: string, name: string}[]
local function ImageList(config)
    local result = {}
    local images = type(config.images) == "table" and config.images or {}
    for i = 1, MAX_IMAGES do
        local entry = images["s" .. i]
        if type(entry) == "table" and type(entry.image) == "string" and entry.image ~= "" then
            result[#result + 1] = { image = entry.image, name = tostring(entry.name or "") }
        end
    end
    return result
end

---@param config table
---@return ComboSymbol[]
local function Symbols(config)
    local set = config.symbols
    local result = {}
    if set == "letters" then
        for i = 0, 25 do
            local c = string.char(65 + i)
            result[#result + 1] = { name = c, text = c }
        end
    elseif set == "runes" then
        for _, r in ipairs(RUNES) do
            result[#result + 1] = { name = r.name, icon = r.icon }
        end
    elseif set == "images" then
        for i, entry in ipairs(ImageList(config)) do
            local name = entry.name
            if name == "" then
                name = string.format("Image %d", i)
            end
            result[#result + 1] = { name = name, image = entry.image }
        end
    else
        for i = 0, 9 do
            result[#result + 1] = { name = tostring(i), text = tostring(i) }
        end
    end
    return result
end

--The code as symbol indexes, or nil until every dial is set within the set.
---@param config table
---@return integer[]|nil
local function ParseCode(config)
    local n = DialCount(config)
    local count = #Symbols(config)
    local result = {}
    for part in string.gmatch(tostring(config.code or ""), "[^,]+") do
        result[#result + 1] = math.tointeger(tonumber(part))
    end
    if #result ~= n then
        return nil
    end
    for i = 1, n do
        local v = result[i]
        if v == nil or v < 1 or v > count then
            return nil
        end
    end
    return result
end

---@param values integer[]
---@return string
local function CodeString(values)
    local parts = {}
    for i, v in ipairs(values) do
        parts[i] = tostring(v)
    end
    return table.concat(parts, ",")
end

--A code in words: "7 - Flame - 3".
---@param config table
---@param values integer[]
---@return string
local function CodeWords(config, values)
    local symbols = Symbols(config)
    local parts = {}
    for i, v in ipairs(values) do
        local s = symbols[v]
        parts[i] = s ~= nil and s.name or "?"
    end
    return table.concat(parts, " - ")
end

---@param state table
---@return integer
local function TryCount(state)
    local n = 0
    for _, t in pairs(state.tries or {}) do
        if type(t) == "table" then
            n = n + 1
        end
    end
    return n
end

---@param state table
---@param config table
---@return integer|nil left nil when tries are unlimited
local function TriesLeft(state, config)
    local limit = math.tointeger(tonumber(config.attempts)) or 0
    if limit <= 0 then
        return nil
    end
    return math.max(0, limit - TryCount(state))
end

---@param state table
---@param config table
---@return integer[]
local function DialValues(state, config)
    local n = DialCount(config)
    local count = math.max(1, #Symbols(config))
    local result = {}
    local dials = type(state.dials) == "table" and state.dials or {}
    for i = 1, n do
        local v = math.tointeger(tonumber(dials["d" .. i])) or 1
        result[i] = math.max(1, math.min(count, v))
    end
    return result
end

--The setup's image list: up to ten images, each with a name players see in
--words (marks, the log, the confirm).
---@param config table
---@param setConfig fun(changes: table)
---@return Panel
local function ImagesControl(config, setConfig)
    local resultPanel
    local function Rebuild()
        local images = type(config.images) == "table" and config.images or {}
        local rows = {}
        local used = 0
        for i = 1, MAX_IMAGES do
            local key = "s" .. i
            local entry = images[key]
            if type(entry) == "table" then
                used = used + 1
                rows[#rows + 1] = gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    vmargin = 2,
                    gui.IconEditor{
                        width = 48,
                        height = 48,
                        library = "Avatar",
                        value = entry.image or nil,
                        change = function(element)
                            local copy = DeepCopy(config.images or {})
                            copy[key] = copy[key] or {}
                            copy[key].image = element.value
                            setConfig({ images = copy })
                        end,
                    },
                    gui.Input{
                        classes = {"bordered"},
                        width = 150,
                        height = 26,
                        valign = "center",
                        hmargin = 6,
                        characterLimit = 24,
                        placeholderText = "Name (e.g. Owl)",
                        text = tostring(entry.name or ""),
                        change = function(element)
                            local copy = DeepCopy(config.images or {})
                            copy[key] = copy[key] or {}
                            copy[key].name = element.text
                            setConfig({ images = copy })
                        end,
                    },
                    gui.Button{
                        classes = {"sizeXs"},
                        text = "Remove",
                        width = 64,
                        height = 22,
                        valign = "center",
                        click = function(element)
                            local copy = DeepCopy(config.images or {})
                            copy[key] = nil
                            setConfig({ images = copy })
                            Rebuild()
                        end,
                    },
                }
            end
        end
        if used < MAX_IMAGES then
            rows[#rows + 1] = gui.Button{
                classes = {"sizeXs"},
                text = "Add an image",
                width = 110,
                height = 22,
                vmargin = 2,
                click = function(element)
                    local copy = DeepCopy(config.images or {})
                    for i = 1, MAX_IMAGES do
                        if copy["s" .. i] == nil then
                            copy["s" .. i] = { image = "", name = "" }
                            break
                        end
                    end
                    setConfig({ images = copy })
                    Rebuild()
                end,
            }
        end
        resultPanel.children = rows
    end
    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
    }
    Rebuild()
    return resultPanel
end

--The code, one dropdown per dial built from the chosen symbols. Rebuilds when
--the symbols or dial count change above it.
---@param config table
---@param setConfig fun(changes: table)
---@return Panel
local function CodeControl(config, setConfig)
    local resultPanel
    local m_signature = nil

    local function Signature()
        local names = {}
        for i, s in ipairs(Symbols(config)) do
            names[i] = s.name
        end
        return string.format("%s|%d|%s", tostring(config.symbols), DialCount(config), table.concat(names, ","))
    end

    local function Current()
        local values = {}
        local i = 1
        for part in string.gmatch(tostring(config.code or ""), "[^,]+") do
            values[i] = math.tointeger(tonumber(part))
            i = i + 1
        end
        return values
    end

    local warning

    local function RefreshWarning()
        local problem = nil
        if config.symbols == "images" then
            local seen = {}
            for _, s in ipairs(Symbols(config)) do
                local key = string.lower(s.name)
                if seen[key] then
                    problem = "Give each image its own name."
                end
                seen[key] = true
            end
            if #Symbols(config) < 2 then
                problem = "Add at least two images."
            end
        end
        if problem == nil and ParseCode(config) == nil then
            problem = "Set every dial."
        end
        warning.text = problem or ""
        warning:SetClass("collapsed", problem == nil)
    end

    local function Rebuild()
        m_signature = Signature()
        local symbols = Symbols(config)
        local options = {}
        for i, s in ipairs(symbols) do
            options[i] = { id = tostring(i), text = s.name }
        end
        local values = Current()
        local dropdowns = {}
        for d = 1, DialCount(config) do
            local dial = d
            local v = values[d]
            dropdowns[#dropdowns + 1] = gui.Dropdown{
                width = 90,
                hmargin = 2,
                options = options,
                textDefault = "?",
                idChosen = (v ~= nil and v >= 1 and v <= #symbols) and tostring(v) or nil,
                change = function(dropdown)
                    ---@cast dropdown Dropdown
                    local cur = Current()
                    cur[dial] = math.tointeger(tonumber(dropdown.idChosen))
                    local parts = {}
                    for k = 1, DialCount(config) do
                        parts[k] = tostring(cur[k] or "")
                    end
                    setConfig({ code = table.concat(parts, ",") })
                    RefreshWarning()
                end,
            }
        end
        resultPanel.children = {
            gui.Panel{
                flow = "horizontal",
                wrap = true,
                width = 300,
                height = "auto",
                children = dropdowns,
            },
            warning,
            gui.Label{
                classes = {"sizeXs", "fgMuted"},
                width = 300,
                height = "auto",
                tmargin = 2,
                text = "Changing the symbols, dials or code puts the dials back to a new start.",
            },
        }
        RefreshWarning()
    end

    warning = gui.Label{
        classes = {"sizeS", "warning", "collapsed"},
        width = 300,
        height = "auto",
        text = "",
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        --the symbols and dial count are other fields: follow their changes.
        setupChanged = function(element)
            if Signature() ~= m_signature then
                Rebuild()
            else
                RefreshWarning()
            end
        end,
    }
    Rebuild()
    return resultPanel
end

--------------------------------------------------------------------------------
-- Keyboard: a command context while a lock has the GUI focus
--------------------------------------------------------------------------------

local COMMAND_CONTEXT = "combolock"
local KEY_COMMANDS = {}
local g_bindingsReady = false

local function EnsureBindings()
    if g_bindingsReady then
        return
    end
    g_bindingsReady = true
    local function Bind(key, cmd)
        dmhub.SetCommandBinding(key, cmd, COMMAND_CONTEXT)
        KEY_COMMANDS[#KEY_COMMANDS + 1] = cmd
    end
    Bind("left", "combo_left")
    Bind("right", "combo_right")
    Bind("up", "combo_up")
    Bind("down", "combo_down")
    Bind("return", "combo_try")
    Bind("enter", "combo_try2")
    for i = 0, 9 do
        Bind(tostring(i), "combo_k" .. i)
    end
    for i = 0, 25 do
        local c = string.char(97 + i)
        Bind(c, "combo_k" .. c)
    end
end

--------------------------------------------------------------------------------
-- The lock panel
--------------------------------------------------------------------------------

---@param ctx PuzzleContext
---@return Panel
local function Render(ctx)
    EnsureBindings()
    local m_ctx = ctx
    local m_cursor = 1
    local m_confirming = nil ---@type integer[]|nil
    local m_signature = nil
    local m_contextActive = false
    local Refresh
    local resultPanel
    local dialRow
    local dialReading
    local logLabel
    local tryButton
    local confirmRow
    local confirmLabel

    local function Large()
        return m_ctx:Assist("large")
    end

    local function State()
        return m_ctx.state or {}
    end

    ---@param i integer
    ---@param value integer
    local function SetDial(i, value)
        if m_ctx.readonly then
            return
        end
        local userid = m_ctx.userid
        m_ctx:Change(function(state, config)
            if state.opened ~= nil then
                return false
            end
            state.dials = state.dials or {}
            state.turnedBy = state.turnedBy or {}
            state.turns = state.turns or {}
            state.dials["d" .. i] = value
            state.turnedBy["d" .. i] = userid
            state.turns[userid .. "_d" .. i] = { at = dmhub.serverTime, user = userid, dial = i, value = value }
        end, "Turn dial")
    end

    ---@param i integer
    ---@param step integer
    local function Turn(i, step)
        local count = #Symbols(m_ctx.config)
        if count < 1 then
            return
        end
        local values = DialValues(State(), m_ctx.config)
        local v = ((values[i] - 1 + step) % count) + 1
        SetDial(i, v)
    end

    --keys reach the lock only while it holds the GUI focus (see the think below).
    local function SyncContext()
        local want = resultPanel ~= nil and resultPanel.valid and gui.ChildHasFocus(resultPanel)
        if want ~= m_contextActive then
            m_contextActive = want
            if want then
                dmhub.PushCommandContext(COMMAND_CONTEXT)
            else
                dmhub.PopCommandContext(COMMAND_CONTEXT)
            end
        end
    end

    local function Focus()
        if resultPanel ~= nil and resultPanel.valid and not gui.ChildHasFocus(resultPanel) then
            gui.SetFocus(resultPanel)
        end
        SyncContext()
    end

    ---@param values integer[]
    local function SendTry(values)
        local userid = m_ctx.userid
        local code = CodeString(values)
        m_ctx:Change(function(state, config)
            if state.opened ~= nil then
                return false
            end
            local left = TriesLeft(state, config)
            if left ~= nil and left <= 0 then
                return false
            end
            state.tries = state.tries or {}
            state.tries[dmhub.GenerateGuid()] = { at = dmhub.serverTime, user = userid, code = code }
            if ParseCode(config) ~= nil and code == config.code then
                state.opened = code
            end
        end, "Try the code")
    end

    local function TryCode()
        if m_ctx.readonly or ParseCode(m_ctx.config) == nil then
            return
        end
        --the code as this player sees it now, not whatever the dials are by the
        --time the write lands.
        local values = DialValues(State(), m_ctx.config)
        if TriesLeft(State(), m_ctx.config) ~= nil then
            m_confirming = values
            Refresh()
            return
        end
        SendTry(values)
    end

    local function ConfirmTry()
        Focus()
        if m_confirming ~= nil then
            local values = m_confirming
            m_confirming = nil
            SendTry(values)
            Refresh()
        end
    end

    local function CancelTry()
        Focus()
        m_confirming = nil
        Refresh()
    end

    --A typed key: a digit or letter in those sets, a number 1-9/0 for the tenth
    --in runes and images. Sets the dial under the cursor and moves on.
    ---@param key string
    local function TypeKey(key)
        local config = m_ctx.config
        local set = config.symbols
        local count = #Symbols(config)
        local value = nil
        if set == "letters" then
            local b = string.byte(key)
            if b ~= nil and b >= 97 and b <= 122 then
                value = b - 96
            end
        elseif tonumber(key) ~= nil then
            local d = math.tointeger(tonumber(key)) or 0
            if set == "runes" or set == "images" then
                value = cond(d == 0, 10, d)
            else
                value = d + 1
            end
        end
        if value == nil or value > count then
            return
        end
        SetDial(m_cursor, value)
        m_cursor = math.min(DialCount(config), m_cursor + 1)
        Refresh()
    end

    ---@param s ComboSymbol|nil
    ---@param size number
    ---@return Panel
    local function SymbolFace(s, size)
        if s == nil then
            return gui.Panel{ width = size, height = size, interactable = false }
        end
        if s.text ~= nil then
            return gui.Label{
                width = size,
                height = size,
                textAlignment = "center",
                fontSize = math.floor(size * 0.6),
                bold = true,
                color = SYMBOL_COLOR,
                interactable = false,
                text = s.text,
            }
        end
        return gui.Panel{
            width = size * 0.75,
            height = size * 0.75,
            halign = "center",
            valign = "center",
            bgimage = s.icon or s.image,
            bgcolor = cond(s.icon ~= nil, SYMBOL_COLOR, "white"),
            interactable = false,
        }
    end

    --Every symbol in a grid, to pick one for dial i without stepping through.
    ---@param anchor Panel
    ---@param i integer
    local function ShowStrip(anchor, i)
        if anchor.popup ~= nil then
            anchor.popup = nil
            return
        end
        local symbols = Symbols(m_ctx.config)
        local cells = {}
        for v, s in ipairs(symbols) do
            local value = v
            cells[#cells + 1] = gui.Panel{
                flow = "vertical",
                width = 64,
                height = "auto",
                vmargin = 2,
                hmargin = 2,
                gui.Panel{
                    width = 44,
                    height = 44,
                    halign = "center",
                    bgimage = "panels/square.png",
                    bgcolor = FACE_BG,
                    border = 1,
                    borderColor = FACE_BORDER,
                    press = function(element)
                        anchor.popup = nil
                        Focus()
                        SetDial(i, value)
                        m_cursor = i
                    end,
                    SymbolFace(s, 44),
                },
                gui.Label{
                    classes = {"sizeXs"},
                    width = 64,
                    height = "auto",
                    textAlignment = "center",
                    interactable = false,
                    text = cond(s.text ~= nil, "", s.name),
                },
            }
        end
        anchor.popupsInheritStyles = true
        anchor.popup = gui.Panel{
            classes = {"bordered", "bg"},
            flow = "horizontal",
            wrap = true,
            width = 7 * 68 + 16,
            height = "auto",
            pad = 8,
            borderBox = true,
            children = cells,
        }
    end

    local function BuildDials()
        local config = m_ctx.config
        local large = Large()
        local size = cond(large, 84, 60)
        local dials = {}
        for i = 1, DialCount(config) do
            local dial = i
            local face
            face = gui.Panel{
                width = size,
                height = size,
                halign = "center",
                bgimage = "panels/square.png",
                bgcolor = FACE_BG,
                border = 2,
                borderColor = FACE_BORDER,
                press = function(element)
                    m_cursor = dial
                    Focus()
                    if not m_ctx.readonly then
                        ShowStrip(element, dial)
                    end
                    Refresh()
                end,
                data = { shown = nil },
                refreshCombo = function(element)
                    local values = DialValues(State(), m_ctx.config)
                    local s = Symbols(m_ctx.config)[values[dial]]
                    local key = tostring(values[dial])
                    if element.data.shown ~= key then
                        element.data.shown = key
                        element.children = { SymbolFace(s, size) }
                    end
                    local cursor = m_cursor == dial and not m_ctx.readonly
                    element.selfStyle.borderColor = cond(cursor, FACE_BORDER_CURSOR, FACE_BORDER)
                    element.selfStyle.border = cond(cursor, 4, 2)
                end,
            }
            dials[#dials + 1] = gui.Panel{
                flow = "vertical",
                width = size + 24,
                height = "auto",
                hmargin = 4,
                gui.Label{
                    classes = {"sizeS", "fgMuted"},
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                    text = tostring(dial),
                },
                gui.Button{
                    classes = {"sizeXs"},
                    text = "+",
                    width = size,
                    height = 22,
                    halign = "center",
                    refreshCombo = function(element)
                        element:SetClass("collapsed", m_ctx.readonly)
                    end,
                    click = function(element)
                        m_cursor = dial
                        Focus()
                        Turn(dial, 1)
                    end,
                },
                face,
                gui.Button{
                    classes = {"sizeXs"},
                    text = "-",
                    width = size,
                    height = 22,
                    halign = "center",
                    refreshCombo = function(element)
                        element:SetClass("collapsed", m_ctx.readonly)
                    end,
                    click = function(element)
                        m_cursor = dial
                        Focus()
                        Turn(dial, -1)
                    end,
                },
                --the symbol's name, for runes and images when asked for.
                gui.Label{
                    classes = {"sizeS"},
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                    refreshCombo = function(element)
                        local values = DialValues(State(), m_ctx.config)
                        local s = Symbols(m_ctx.config)[values[dial]]
                        local show = m_ctx:Assist("names") and s ~= nil and s.text == nil
                        element:SetClass("collapsed", not show)
                        element.text = show and s.name or ""
                    end,
                },
                gui.Label{
                    classes = {"sizeS", "fgMuted"},
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                    refreshCombo = function(element)
                        local who = (State().turnedBy or {})["d" .. dial]
                        element:SetClass("collapsed", who == nil)
                        element.text = who ~= nil and string.format("by %s", Puzzle.UserName(who)) or ""
                    end,
                },
            }
        end
        dialRow.children = dials
    end

    local function LogText()
        local config = m_ctx.config
        local state = State()
        local symbols = Symbols(config)
        local entries = {}
        for _, t in pairs(state.turns or {}) do
            if type(t) == "table" then
                local s = symbols[math.tointeger(tonumber(t.value)) or 0]
                entries[#entries + 1] = { at = tonumber(t.at) or 0, text = string.format("%s set dial %s to %s.",
                    Puzzle.UserName(t.user), tostring(t.dial), s ~= nil and s.name or "?") }
            end
        end
        for _, t in pairs(state.tries or {}) do
            if type(t) == "table" then
                local values = {}
                for part in string.gmatch(tostring(t.code or ""), "[^,]+") do
                    values[#values + 1] = math.tointeger(tonumber(part)) or 0
                end
                local right = state.opened ~= nil and t.code == state.opened
                entries[#entries + 1] = { at = tonumber(t.at) or 0, text = string.format("%s tried %s: %s",
                    Puzzle.UserName(t.user), CodeWords(config, values), cond(right, "it opens.", "no.")) }
            end
        end
        table.sort(entries, function(a, b) return a.at < b.at end)
        local lines = {}
        for i = math.max(1, #entries - LOG_LINES + 1), #entries do
            lines[#lines + 1] = entries[i].text
        end
        return table.concat(lines, "\n")
    end

    Refresh = function()
        if not resultPanel.valid then
            return
        end
        local config = m_ctx.config
        local signature = string.format("%s|%d|%d|%s", tostring(config.symbols), DialCount(config), #Symbols(config), tostring(Large()))
        if signature ~= m_signature then
            m_signature = signature
            m_cursor = math.min(m_cursor, DialCount(config))
            BuildDials()
        end
        local state = State()
        local values = DialValues(state, config)
        local ready = ParseCode(config) ~= nil
        if not ready then
            dialReading.text = "The Director hasn't set the code yet."
        else
            dialReading.text = "Dials: " .. CodeWords(config, values)
        end
        logLabel.text = LogText()
        logLabel:SetClass("collapsed", logLabel.text == "")
        tryButton:SetClass("collapsed", m_ctx.readonly or m_confirming ~= nil or not ready)
        if m_confirming ~= nil and not m_ctx.readonly then
            local left = TriesLeft(state, config) or 0
            confirmLabel.text = string.format("Try %s? %d %s left.", CodeWords(config, m_confirming), left, cond(left == 1, "try", "tries"))
            confirmRow:SetClass("collapsed", false)
        else
            m_confirming = nil
            confirmRow:SetClass("collapsed", true)
        end
        resultPanel:FireEventTree("refreshCombo")
    end

    dialRow = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
    }

    dialReading = gui.Label{
        classes = {"sizeM"},
        width = 460,
        height = "auto",
        tmargin = 8,
        text = "",
    }

    tryButton = gui.Button{
        classes = {"sizeM"},
        text = "Try the code",
        width = 160,
        tmargin = 6,
        click = function(element)
            Focus()
            TryCode()
        end,
    }

    confirmLabel = gui.Label{
        classes = {"sizeM"},
        width = "auto",
        maxWidth = 300,
        height = "auto",
        valign = "center",
        text = "",
    }

    confirmRow = gui.Panel{
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        tmargin = 6,
        confirmLabel,
        gui.Button{
            classes = {"sizeS"},
            text = "Try it",
            width = 80,
            hmargin = 6,
            valign = "center",
            click = function(element)
                ConfirmTry()
            end,
        },
        gui.Button{
            classes = {"sizeS"},
            text = "Cancel",
            width = 80,
            valign = "center",
            click = function(element)
                CancelTry()
            end,
        },
    }

    logLabel = gui.Label{
        classes = {"sizeS", "collapsed"},
        width = 460,
        height = "auto",
        tmargin = 6,
        textAlignment = "topleft",
        text = "",
    }

    local args = {
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        refreshPuzzle = function(element, newCtx)
            m_ctx = newCtx
            Refresh()
        end,
        --keys come through the "combolock" context only while this lock has
        --the focus, so the arrows go back to moving tokens the moment it doesn't.
        thinkTime = 0.2,
        think = function(element)
            SyncContext()
        end,
        destroy = function(element)
            if m_contextActive then
                m_contextActive = false
                dmhub.PopCommandContext(COMMAND_CONTEXT)
            end
        end,
        commands = KEY_COMMANDS,
        combo_left = function(element)
            m_cursor = math.max(1, m_cursor - 1)
            Refresh()
        end,
        combo_right = function(element)
            m_cursor = math.min(DialCount(m_ctx.config), m_cursor + 1)
            Refresh()
        end,
        combo_up = function(element)
            Turn(m_cursor, 1)
        end,
        combo_down = function(element)
            Turn(m_cursor, -1)
        end,
        combo_try = function(element)
            if m_confirming ~= nil then
                ConfirmTry()
            else
                TryCode()
            end
        end,
        dialRow,
        dialReading,
        tryButton,
        confirmRow,
        logLabel,
    }
    args.combo_try2 = args.combo_try
    for i = 0, 9 do
        local key = tostring(i)
        args["combo_k" .. key] = function(element) TypeKey(key) end
    end
    for i = 0, 25 do
        local key = string.char(97 + i)
        args["combo_k" .. key] = function(element) TypeKey(key) end
    end
    resultPanel = gui.Panel(args)
    return resultPanel
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

---@param config table
---@return boolean
local function UsesImages(config)
    return config.symbols == "images"
end

PuzzleType.Register{
    id = "combination",
    name = "Combination lock",
    fields = {
        { id = "symbols", type = "choice", label = "Symbols", default = "digits", options = {
            { id = "digits", text = "Digits (0-9)" },
            { id = "letters", text = "Letters (A-Z)" },
            { id = "runes", text = "Runes" },
            { id = "images", text = "My own images" },
        } },
        { id = "dials", type = "number", label = "Dials", default = 4, min = MIN_DIALS, max = MAX_DIALS },
        { id = "images", type = "custom", label = "Images (up to ten, each with a name)", default = {}, visible = UsesImages, Control = ImagesControl },
        { id = "code", type = "custom", label = "The code", default = "", Control = CodeControl },
        { id = "attempts", type = "number", label = "Tries before it jams (0 for unlimited)", default = 0, min = 0, max = 10 },
        { id = "hint", type = "text", label = "Hint", default = "" },
    },
    assists = {
        { id = "large", label = "Larger dials" },
        { id = "names", label = "Show symbol names" },
    },
    ConfigKey = function(config)
        return string.format("%s|%d|%d|%s", tostring(config.symbols), DialCount(config), #Symbols(config), tostring(config.code))
    end,
    --a random start, but no dial already on its code symbol.
    NewState = function(config, ctx)
        local code = ParseCode(config)
        local count = #Symbols(config)
        local dials = {}
        for i = 1, DialCount(config) do
            local v
            if count <= 1 then
                v = 1
            elseif code ~= nil then
                v = ctx.random(count - 1)
                if v >= code[i] then
                    v = v + 1
                end
            else
                v = ctx.random(count)
            end
            dials["d" .. i] = v
        end
        return { dials = dials, turnedBy = {}, turns = {}, tries = {} }
    end,
    --solving is an action (trying the right code), so the try writes the code it
    --tried and this compares it; the dials alone never open the lock.
    IsSolved = function(state, config)
        return state.opened ~= nil and ParseCode(config) ~= nil and state.opened == config.code
    end,
    IsFailed = function(state, config, now)
        local left = TriesLeft(state, config)
        return left ~= nil and left <= 0 and state.opened == nil
    end,
    SolvedState = function(config)
        local code = ParseCode(config)
        local dials = {}
        for i, v in ipairs(code or {}) do
            dials["d" .. i] = v
        end
        return { dials = dials, turnedBy = {}, turns = {}, tries = {}, opened = code ~= nil and config.code or nil }
    end,
    Hint = function(state, config)
        local hint = tostring(config.hint or "")
        if hint == "" then
            return nil
        end
        return hint
    end,
    Status = function(state, config)
        if state.opened ~= nil then
            return nil
        end
        local left = TriesLeft(state, config)
        if left ~= nil then
            if left <= 0 then
                return "Out of tries: the lock has jammed."
            end
            return string.format("Tries left: %d", left)
        end
        local n = TryCount(state)
        if n > 0 then
            return string.format("Tries: %d", n)
        end
        return nil
    end,
    Render = Render,
}
