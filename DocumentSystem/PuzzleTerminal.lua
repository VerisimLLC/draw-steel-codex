local mod = dmhub.GetModLoading()

-- The "Computer terminal" puzzle type, and the worked example for anyone writing
-- their own type (see PUZZLE_REFERENCE.md at the codex root). Players type a
-- password; a wrong one costs an attempt, and running out of attempts fails the
-- puzzle. The Director can write a code sheet that only players given the
-- "Code sheet" role can see -- the other players have to be talked through it.

--Passwords compare without case or surrounding spaces.
---@param text any
---@return string
local function Normalize(text)
    return string.lower((string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1")))
end

---@param state table
---@param config table
---@return integer|nil left nil when attempts are unlimited
local function AttemptsLeft(state, config)
    local limit = math.tointeger(tonumber(config.attempts)) or 0
    if limit <= 0 then
        return nil
    end
    return math.max(0, limit - (math.tointeger(state.tries) or 0))
end

--The screen's colours are the puzzle's own art, like the torn note's paper, so
--they stay fixed whatever the app's theme.
local SCREEN_BG = "#07120aff"
local SCREEN_FG = "#3dff7aff"
local SCREEN_DIM = "#1f7a3cff"

---@param ctx PuzzleContext
---@return Panel
local function Render(ctx)
    local m_ctx = ctx
    local resultPanel
    local screen
    local codeSheet
    local input
    local inputRow

    local function Submit()
        local typed = input.text or ""
        if Normalize(typed) == "" or m_ctx.readonly then
            return
        end
        input.text = ""
        local who = m_ctx.userName
        m_ctx:Change(function(state, config)
            state.tries = (math.tointeger(state.tries) or 0) + 1
            local line
            if Normalize(typed) == Normalize(config.password) then
                state.unlocked = true
                line = "> ******** ACCESS GRANTED"
            else
                line = string.format("> %s ACCESS DENIED (%s)", string.rep("*", math.min(#typed, 12)), who)
                local left = AttemptsLeft(state, config)
                if left ~= nil and left <= 0 then
                    state.lockedOut = true
                    line = line .. "\n> TERMINAL LOCKED"
                end
            end
            --one string, not a list: a list would be uploaded whole on every entry.
            state.log = (state.log or "") .. line .. "\n"
        end, "Terminal entry")
    end

    local function Refresh()
        if not resultPanel.valid then
            return
        end
        local ctx = m_ctx
        local config = ctx.config
        local state = ctx.state or {}
        local large = ctx:Assist("large")

        local boot = tostring(config.bootText or "")
        if boot == "" then
            boot = "TERMINAL READY\nENTER PASSWORD"
        end
        screen.text = boot .. "\n\n" .. tostring(state.log or "")
        screen.selfStyle.fontSize = cond(large, 26, 18)

        --the code sheet: Director, and players holding the Code sheet role.
        local sheet = tostring(config.codeSheet or "")
        local canSeeSheet = sheet ~= "" and (ctx.isDirector or ctx.role == "sheet")
        codeSheet.text = cond(canSeeSheet, "CODE SHEET\n" .. sheet, "")
        codeSheet:SetClass("collapsed", not canSeeSheet)
        codeSheet.selfStyle.fontSize = cond(large, 22, 15)

        inputRow:SetClass("collapsed", ctx.readonly)
    end

    screen = gui.Label{
        classes = {"monospace"},
        width = 460,
        height = "auto",
        bgimage = "panels/square.png",
        bgcolor = SCREEN_BG,
        color = SCREEN_FG,
        border = 2,
        borderColor = SCREEN_DIM,
        pad = 12,
        borderBox = true,
        textAlignment = "topleft",
        text = "",
    }

    codeSheet = gui.Label{
        classes = {"monospace", "collapsed"},
        width = 460,
        height = "auto",
        tmargin = 6,
        bgimage = "panels/square.png",
        bgcolor = "#e8dcc0ff",
        color = "#2b1d10ff",
        pad = 10,
        borderBox = true,
        textAlignment = "topleft",
        text = "",
    }

    input = gui.Input{
        classes = {"monospace"},
        width = 340,
        height = 30,
        bgimage = "panels/square.png",
        bgcolor = SCREEN_BG,
        color = SCREEN_FG,
        border = 1,
        borderColor = SCREEN_DIM,
        hpad = 8,
        borderBox = true,
        placeholderText = "Type the password...",
        characterLimit = 64,
        text = "",
        --Enter fires "submit" on a single-line input (SheetInput.cs).
        submit = function(element)
            Submit()
        end,
    }

    inputRow = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        tmargin = 6,
        input,
        gui.Button{
            classes = {"sizeS"},
            text = "Enter",
            hmargin = 6,
            click = function(element)
                Submit()
            end,
        },
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
        screen,
        inputRow,
        codeSheet,
    }
    return resultPanel
end

PuzzleType.Register{
    id = "terminal",
    name = "Computer terminal",
    fields = {
        { id = "password", type = "text", label = "Password", default = "" },
        { id = "attempts", type = "number", label = "Attempts (0 for unlimited)", default = 3, min = 0, max = 10 },
        { id = "bootText", type = "multiline", label = "Screen text", default = "" },
        { id = "codeSheet", type = "multiline", label = "Code sheet (only the Code sheet role sees it)", default = "" },
        { id = "hint", type = "text", label = "Hint", default = "" },
    },
    roles = {
        { id = "sheet", name = "Code sheet" },
    },
    assists = {
        { id = "large", label = "Larger text" },
    },
    NewState = function(config, ctx)
        return { tries = 0, log = "", unlocked = false, lockedOut = false }
    end,
    --solving is an action (the right password), so the move writes a flag and
    --this reads it. The host's re-check cannot catch a forged flag; see the doc.
    IsSolved = function(state, config)
        return state.unlocked == true
    end,
    IsFailed = function(state, config, now)
        return state.lockedOut == true and state.unlocked ~= true
    end,
    SolvedState = function(config)
        return { tries = 0, log = "> ******** ACCESS GRANTED\n", unlocked = true, lockedOut = false }
    end,
    Hint = function(state, config)
        local hint = tostring(config.hint or "")
        if hint == "" then
            return nil
        end
        return hint
    end,
    Status = function(state, config)
        local left = AttemptsLeft(state, config)
        if left == nil or state.unlocked then
            return nil
        end
        return string.format("Attempts left: %d", left)
    end,
    Render = Render,
}
