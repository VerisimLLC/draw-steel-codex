local mod = dmhub.GetModLoading()

-- The [[puzzle:Name]] journal widget, and Puzzle.CreatePanel: the frame every
-- surface shows a puzzle in. The frame draws the type's own panel plus what the
-- framework owns: the Solved/Failed banner, the status and timer line, the hint,
-- per-player assist toggles, and the Director's controls (Reset, Solve, Bypass,
-- hint, timer, roles). See PuzzleFramework.lua for the model.

---@class RichPuzzle: RichTag
--- @field new fun(o?: table): RichPuzzle
--- @field identifier string|false
RichPuzzle = RegisterGameType("RichPuzzle", "RichTag")
RichPuzzle.tag = "puzzle"
RichPuzzle.identifier = false

function RichPuzzle.Create()
    return RichPuzzle.new{}
end

--Tag keyword -> the prefix of the puzzle id it makes, for every journal tag
--that shows a puzzle.
---@type table<string, string>
Puzzle.JOURNAL_TAGS = { puzzle = "j_", sliderpuzzle = "s_", tornpuzzle = "t_" }

--The page's own puzzle for a tag: owning page + tag name, so two pages never
--share one by accident. Nil while the page is unsaved (it has no id yet).
---@param tag RichTag
---@param prefix string keeps legacy tags apart from [[puzzle:]] tags of the same name
---@return string|nil
function Puzzle.OwnJournalId(tag, prefix)
    local doc = tag:GetDocument()
    local docid = doc ~= nil and doc:try_get("id") or nil
    if docid == nil then
        return nil
    end
    return Puzzle.SafeId(string.format("%s%s_%s", prefix, tostring(docid), tostring(tag.identifier or "default")))
end

--The id of the puzzle a journal tag shows: the puzzle it names (one placed
--from the Puzzles panel or chosen with "Use an existing puzzle"), else the
--page's own.
---@param tag RichTag
---@param prefix string
---@return string|nil
function Puzzle.JournalId(tag, prefix)
    local named = tag:try_get("puzzleid")
    if type(named) == "string" and named ~= "" then
        return named
    end
    return Puzzle.OwnJournalId(tag, prefix)
end

---@param tag RichTag
---@return string
function Puzzle.TagKey(tag)
    return string.format("%s:%s", tostring(tag.tag), tostring(tag.identifier or "default"))
end

--The tags on a page that show a puzzle: tag key -> tag.
---@param doc any
---@param id string
---@return table<string, RichTag>
function Puzzle.PageTags(doc, id)
    local result = {}
    local annotations = doc ~= nil and doc:try_get("annotations") or nil
    for key, tag in pairs(annotations or {}) do
        local prefix = type(tag) == "table" and Puzzle.JOURNAL_TAGS[tostring(tag.tag)] or nil
        if prefix ~= nil then
            tag._tmp_document = doc
            if Puzzle.JournalId(tag, prefix) == id then
                result[key] = tag
            end
        end
    end
    return result
end

--Where a player reading a tag's page is, for presence lines: "on Handout 3".
---@param tag RichTag
---@return string|nil
function Puzzle.OnPageText(tag)
    local doc = tag:GetDocument()
    local name = doc ~= nil and doc:try_get("description") or nil
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return "on " .. name
end

--Record a journal tag's puzzle (and its page) in the puzzle index.
---@param tag RichTag
---@param id string|nil
function Puzzle.IndexJournal(tag, id)
    if id == nil or not Puzzle.Exists(id) then
        return
    end
    local doc = tag:GetDocument()
    local docid = doc ~= nil and doc:try_get("id") or nil
    if docid ~= nil then
        Puzzle.IndexPuzzle(id, { kind = "journal", docid = tostring(docid), tag = Puzzle.TagKey(tag) })
    end
end

--Point a journal tag at another puzzle, or back at the page's own (nil). The
--puzzle it showed loses this page as a home.
---@param tag RichTag
---@param prefix string
---@param id string|nil
function Puzzle.SetJournalPuzzle(tag, prefix, id)
    local old = Puzzle.JournalId(tag, prefix)
    local doc = tag:GetDocument()
    local docid = doc ~= nil and doc:try_get("id") or nil
    if old ~= nil and docid ~= nil then
        local key = Puzzle.HomeKey({ kind = "journal", docid = tostring(docid), tag = Puzzle.TagKey(tag) })
        for homeKey, home in pairs(Puzzle.Homes(old)) do
            if home.kind == "journal" and home.docid == tostring(docid) and (home.tag == nil or homeKey == key) then
                Puzzle.RemoveHome(old, homeKey)
            end
        end
    end
    (tag --[[@as table]]).puzzleid = id or ""
    tag:UploadDocument()
    Puzzle.IndexJournal(tag, Puzzle.JournalId(tag, prefix))
end

--"Use an existing puzzle" for a journal tag's setup.
---@param getTag fun(): RichTag
---@param prefix string
---@return fun(): PuzzlePick|nil
function Puzzle.JournalPick(getTag, prefix)
    return function()
        local own = Puzzle.OwnJournalId(getTag(), prefix)
        if own == nil then
            return nil
        end
        return {
            own = own,
            ownText = "This page's own puzzle",
            choose = function(id)
                Puzzle.SetJournalPuzzle(getTag(), prefix, id)
            end,
        }
    end
end

--Every puzzle frame on this client's screen (journal pages and windows):
--panel -> puzzle id.
---@type table<Panel, string>
local g_frames = {}

--True while this client has the puzzle on screen anywhere, so a push need not
--open a window and a Join notice is not needed.
---@param id string
---@return boolean
function Puzzle.IsShownLocally(id)
    for panel, pid in pairs(g_frames) do
        if not panel.valid then
            g_frames[panel] = nil
        elseif pid == id then
            return true
        end
    end
    return false
end

--How often a frame on screen renews this player's presence, in think ticks.
local FRAME_HEARTBEAT_TICKS = 20

---@param seconds number
---@return string
local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", seconds // 60, seconds % 60)
end

--The places a puzzle lives, by name, that are still there (PuzzlePlace).
---@param id string
---@return string[]
local function LiveHomeNames(id)
    local names = {}
    for _, home in pairs(Puzzle.Homes(id)) do
        if PuzzlePlace.HomeLive(id, home) then
            names[#names + 1] = PuzzlePlace.HomeName(home)
        end
    end
    table.sort(names)
    return names
end

--A puzzle-wide action (Reset, Solve, Bypass, a type change) on a puzzle that
--lives in more than one place asks first, naming every place, who is in it and
--what its locks will do. With one place it runs at once, unless always is set
--(Reset always asks). effects: the lock effects the action runs or undoes.
---@param id string
---@param title string
---@param lines string[] what the action does
---@param confirmText string
---@param onConfirm fun()
---@param opts {always: boolean|nil, effects: "onSolve"|"onFail"|nil, effectsVerb: string|nil, onCancel: (fun())|nil}|nil
function Puzzle.ConfirmWide(id, title, lines, confirmText, onConfirm, opts)
    opts = opts or {}
    local names = LiveHomeNames(id)
    if #names <= 1 and not opts.always then
        onConfirm()
        return
    end
    local all = {}
    for _, line in ipairs(lines) do
        all[#all + 1] = line
    end
    if #names > 1 then
        all[#all + 1] = "It applies in every place: " .. table.concat(names, ", ") .. "."
    end
    local people = {}
    for _, userid in ipairs(Puzzle.PresentUsers(id)) do
        if userid ~= dmhub.userid then
            people[#people + 1] = Puzzle.UserNameWhere(id, userid)
        end
    end
    if #people > 0 then
        all[#all + 1] = "In it now: " .. table.concat(people, ", ") .. "."
    end
    if opts.effects ~= nil then
        local effects = Puzzle.LockEffectLines(id, opts.effects)
        if #effects > 0 then
            all[#all + 1] = (opts.effectsVerb or "Its locks will") .. ": " .. table.concat(effects, "; ") .. "."
        end
    end
    local labels = {}
    for _, line in ipairs(all) do
        labels[#labels + 1] = gui.Label{
            classes = {"modalMessage"},
            width = "100%",
            height = "auto",
            vmargin = 2,
            text = line,
        }
    end
    local cancelled = true
    GameHud.instance:ModalDialog{
        title = title,
        width = 720,
        height = 200 + 40 * #all,
        buttonsHalign = "center",
        buttons = {
            { text = "Cancel", escapeActivates = true, click = function() end },
            { text = confirmText, click = function()
                cancelled = false
                onConfirm()
            end },
        },
        destroy = function(element)
            if cancelled and opts.onCancel ~= nil then
                opts.onCancel()
            end
        end,
        gui.Panel{
            flow = "vertical",
            width = 640,
            height = "auto",
            halign = "center",
            valign = "center",
            children = labels,
        },
    }
end

---@param text string
---@param press fun(element: Panel)
---@return Panel
local function SmallButton(text, press)
    return gui.Button{
        classes = {"sizeXs"},
        text = text,
        width = 72,
        height = 22,
        hmargin = 2,
        vmargin = 2,
        press = press,
    }
end

---@param id string|nil
---@return boolean
local function HasHowToPlay(id)
    local def = id ~= nil and Puzzle.GetType(id) or nil
    return def ~= nil and def.howToPlay ~= nil
end

--Toggle the type's "How to play" popup on the "?" button.
---@param element Panel
---@param id string|nil
local function ToggleHowToPlay(element, id)
    if element.popup ~= nil then
        element.popup = nil
        return
    end
    local def = id ~= nil and Puzzle.GetType(id) or nil
    local help = def ~= nil and def.howToPlay or nil
    if type(help) == "function" then
        help = help(Puzzle.ReadConfig(id --[[@as string]]))
    end
    if def == nil or type(help) ~= "string" or help == "" then
        return
    end
    local children = {
        gui.Label{
            classes = {"sizeM", "bold"},
            width = 420,
            height = "auto",
            vmargin = 2,
            text = string.format("How to play: %s", def.name),
        },
    }
    for paragraph in string.gmatch(help .. "\n\n", "(.-)\n%s*\n") do
        if paragraph:match("%S") then
            children[#children + 1] = gui.Label{
                classes = {"sizeS"},
                width = 420,
                height = "auto",
                vmargin = 3,
                text = paragraph,
            }
        end
    end
    element.popupsInheritStyles = true
    element.popup = gui.Panel{
        classes = {"bordered", "bg"},
        width = "auto",
        height = "auto",
        flow = "vertical",
        pad = 10,
        borderBox = true,
        children = children,
    }
end

--Build the frame for one puzzle. opts.editing() reports whether the page is in
--edit mode (no moves then); opts.atLock marks a window opened at the puzzle's
--lock; opts.where (a string, or a function returning one) says where this
--player has it open, for other players' presence lines; opts.noHelp drops the
--"?" (the window has its own in the corner).
---@param id string|nil nil shows the "save the page first" message
---@param opts {editing: (fun(): boolean)|nil, placeholder: string|nil, atLock: boolean|nil, where: string|(fun(): string|nil)|nil, noHelp: boolean|nil}|nil
---@return Panel
function Puzzle.CreatePanel(id, opts)
    opts = opts or {}
    local m_id = id
    local m_builtType = nil ---@type string|nil
    local m_typePanel = nil ---@type Panel|nil

    local resultPanel
    local content
    local placeholder
    local banner
    local hintLabel
    local statusLabel
    local timerLabel
    local assistRow
    local directorRow
    local timerButtons
    local helpButton
    local directorPill
    local Refresh

    local function Editing()
        return opts.editing ~= nil and opts.editing() == true
    end

    ---@return string|nil
    local function Where()
        local where = opts.where
        if type(where) == "function" then
            return where()
        end
        return where
    end

    --the Director, or the host of a game with no Director (who otherwise has no
    --way to reset a puzzle the table has lost).
    local function IsDirector()
        return dmhub.isDMOrPlayerHost == true
    end

    --a player who opened a lock's puzzle anywhere but the lock: they can look.
    local function Away()
        return m_id ~= nil and not opts.atLock and not IsDirector() and Puzzle.SolveOnlyAtLock(m_id --[[@as string]])
    end
    local m_builtAway = false
    local awayLabel
    local presenceLabel

    local function BuildAssists(def)
        local children = {}
        for _, assist in ipairs(def.assists or {}) do
            local assistid = assist.id
            --no theme minimum width (it widened the whole window), and the
            --frame's own text size rather than the checkbox default.
            children[#children + 1] = gui.Check{
                classes = {"sizeS"},
                width = "auto",
                minWidth = 0,
                fontSize = 14,
                rmargin = 12,
                height = 22,
                halign = "left",
                text = assist.label,
                value = false,
                change = function(element)
                    if m_id ~= nil then
                        Puzzle.SetAssist(m_id, assistid, element.value)
                        Refresh()
                    end
                end,
            }
        end
        assistRow.children = children
        assistRow:SetClass("collapsed", #children == 0)
    end

    local function ShowRoles(element, def)
        if element.popup ~= nil then
            element.popup = nil
            return
        end
        local id = m_id
        if id == nil then
            return
        end
        local config = Puzzle.ReadConfig(id)
        local roles = type(config.roles) == "table" and config.roles or {}
        local options = { { id = "none", text = "No role" } }
        for _, role in ipairs(def.roles or {}) do
            options[#options + 1] = { id = role.id, text = role.name }
        end
        local rows = {}
        for _, userid in ipairs(dmhub.users or {}) do
            local uid = userid
            rows[#rows + 1] = gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                vmargin = 2,
                gui.Label{
                    classes = {"sizeS"},
                    width = 140,
                    height = "auto",
                    valign = "center",
                    text = Puzzle.UserName(uid),
                },
                gui.Dropdown{
                    options = options,
                    idChosen = roles[uid] or "none",
                    change = function(dropdown)
                        ---@cast dropdown Dropdown
                        local current = Puzzle.ReadConfig(id)
                        local newRoles = type(current.roles) == "table" and current.roles or {}
                        newRoles[uid] = cond(dropdown.idChosen == "none", nil, dropdown.idChosen)
                        Puzzle.SetConfig(id, { roles = newRoles })
                    end,
                },
            }
        end
        element.popupsInheritStyles = true
        element.popup = gui.Panel{
            classes = {"bordered", "bg"},
            width = "auto",
            height = "auto",
            flow = "vertical",
            pad = 8,
            borderBox = true,
            children = rows,
        }
    end

    --(Re)build the type's own panel when the puzzle's type changes.
    ---@param def PuzzleTypeDef|nil
    ---@param ctx PuzzleContext|nil
    local function BuildContent(def, ctx)
        local typeid = def ~= nil and def.id or nil
        local away = ctx ~= nil and ctx.away == true
        if typeid == m_builtType and away == m_builtAway then
            return
        end
        m_builtType = typeid
        m_builtAway = away
        m_typePanel = nil
        if def ~= nil and ctx ~= nil then
            local ok, panel = pcall(def.Render, ctx)
            if ok and panel ~= nil then
                m_typePanel = panel
                --away from the lock: the board shows but takes no clicks.
                if away then
                    panel:MakeNonInteractiveRecursive()
                end
            else
                print("PUZZLE:: Render failed for type", typeid, panel)
            end
            BuildAssists(def)
        end
        content.children = { m_typePanel }
    end

    Refresh = function()
        if not resultPanel.valid then
            return
        end
        local def = m_id ~= nil and Puzzle.GetType(m_id) or nil
        if m_id == nil or def == nil then
            BuildContent(nil, nil)
            placeholder.text = cond(m_id == nil,
                "Save the page to set up this puzzle.",
                opts.placeholder or "Puzzle: choose a type in the annotations strip below.")
            placeholder:SetClass("collapsed", false)
            for _, panel in ipairs({banner, hintLabel, statusLabel, timerLabel, assistRow, directorRow, awayLabel, helpButton, directorPill}) do
                panel:SetClass("collapsed", true)
            end
            return
        end
        placeholder:SetClass("collapsed", true)

        local id = m_id --[[@as string]]
        local away = Away()
        local ctx = Puzzle.Context(id, { editing = Editing(), away = away })
        directorPill:SetClass("collapsed", not ctx.isDirector)
        if away then
            local name = Puzzle.LockObjectName(id)
            awayLabel.text = name ~= nil and string.format("Solve this at the %s.", name) or "Solve this at its lock."
        end
        awayLabel:SetClass("collapsed", not away)
        local state = Puzzle.ReadState(id)
        ctx.state = state
        BuildContent(def, ctx)
        ctx.panel = m_typePanel
        if m_typePanel ~= nil and state ~= nil then
            m_typePanel:FireEventTree("refreshPuzzle", ctx)
        end

        local status = ctx.status
        if status.solved then
            banner.text = cond(status.bypassed, "Bypassed", "Solved")
            banner:SetClass("success", true)
            banner:SetClass("danger", false)
        elseif status.failed then
            banner.text = "Failed"
            banner:SetClass("success", false)
            banner:SetClass("danger", true)
        end
        banner:SetClass("collapsed", not status.solved and not status.failed)

        local hint = nil
        if status.hint and def.Hint ~= nil and state ~= nil then
            hint = def.Hint(state, ctx.config)
        end
        hintLabel.text = hint ~= nil and string.format("Hint: %s", hint) or ""
        hintLabel:SetClass("collapsed", hint == nil)

        local line = nil
        if def.Status ~= nil and state ~= nil then
            line = def.Status(state, ctx.config)
        end
        statusLabel.text = line or ""
        statusLabel:SetClass("collapsed", line == nil)
        helpButton:SetClass("collapsed", def.howToPlay == nil or opts.noHelp == true)

        local left = Puzzle.TimeLeft(id)
        local limit = Puzzle.EffectiveLimit(ctx.config)
        if left ~= nil and not status.solved and not status.failed then
            timerLabel.text = string.format("Time left: %s%s", FormatTime(left), cond(Puzzle.TimerPaused(id), " (paused)", ""))
        else
            timerLabel.text = ""
        end
        timerLabel:SetClass("collapsed", timerLabel.text == "")

        directorRow:SetClass("collapsed", not IsDirector())
        timerButtons:SetClass("collapsed", def.noTimeLimit == true or limit <= 0 or status.solved == true or status.failed == true)
        directorRow:FireEventTree("refreshDirector", def, status, left)
    end

    content = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
    }

    placeholder = gui.Label{
        classes = {"collapsed", "sizeS", "bordered"},
        width = 340,
        height = 64,
        halign = "left",
        textAlignment = "center",
        text = "",
    }

    banner = gui.Label{
        classes = {"collapsed", "sizeL", "bold"},
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 2,
        text = "",
    }

    awayLabel = gui.Label{
        classes = {"collapsed", "sizeS", "warning"},
        width = 360,
        height = "auto",
        halign = "left",
        text = "",
    }

    --who else has it open, and where from.
    presenceLabel = gui.Label{
        classes = {"collapsed", "sizeS", "info"},
        width = 360,
        height = "auto",
        halign = "left",
        text = "",
    }

    hintLabel = gui.Label{
        classes = {"collapsed", "sizeS", "info"},
        width = 360,
        height = "auto",
        halign = "left",
        text = "",
    }

    statusLabel = gui.Label{
        classes = {"collapsed", "sizeS"},
        width = "auto",
        height = "auto",
        halign = "left",
        text = "",
    }

    timerLabel = gui.Label{
        classes = {"collapsed", "sizeS", "bold"},
        width = "auto",
        height = "auto",
        halign = "left",
        text = "",
    }

    helpButton = gui.Button{
        classes = {"collapsed", "sizeXs"},
        text = "?",
        width = 22,
        height = 22,
        hmargin = 4,
        valign = "top",
        hover = gui.Tooltip("How to play"),
        press = function(element)
            ToggleHowToPlay(element, m_id)
        end,
    }

    --types draw the Director a board players never see (every page, the answer).
    directorPill = gui.Panel{
        classes = {"collapsed", "multiselectChip"},
        interactable = false,
        hmargin = 0,
        gui.Label{
            classes = {"multiselectChipText", "sizeXs", "bold"},
            hmargin = 4,
            text = "Director view",
        },
    }

    assistRow = gui.Panel{
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
    }

    local timerStart = SmallButton("Start timer", function() if m_id then Puzzle.StartTimer(m_id) end end)
    local timerPause = SmallButton("Pause", function() if m_id then Puzzle.PauseTimer(m_id) end end)
    local timerResume = SmallButton("Resume", function() if m_id then Puzzle.ResumeTimer(m_id) end end)
    local timerExtend = SmallButton("+1 min", function() if m_id then Puzzle.ExtendTimer(m_id, 60) end end)

    timerButtons = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        timerStart,
        timerPause,
        timerResume,
        timerExtend,
        refreshDirector = function(element, def, status, left)
            local running = left ~= nil
            local paused = m_id ~= nil and Puzzle.TimerPaused(m_id)
            timerStart:SetClass("collapsed", running)
            timerPause:SetClass("collapsed", not running or paused)
            timerResume:SetClass("collapsed", not paused)
            timerExtend:SetClass("collapsed", not running)
        end,
    }

    local hintButton = SmallButton("Show hint", function()
        if m_id then Puzzle.RevealHint(m_id) end
    end)
    local rolesButton
    rolesButton = SmallButton("Roles", function(element)
        local def = m_id ~= nil and Puzzle.GetType(m_id) or nil
        if def ~= nil then
            ShowRoles(element, def)
        end
    end)

    directorRow = gui.Panel{
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        SmallButton("Reset", function()
            if m_id == nil then
                return
            end
            local id = m_id --[[@as string]]
            Puzzle.ConfirmWide(id, "Reset the puzzle?", { "Progress, timer and hint start over." }, "Reset", function()
                if not mod.unloaded then
                    Puzzle.Reset(id)
                end
            end, { always = true, effects = "onSolve", effectsVerb = "What its locks did is undone" })
        end),
        SmallButton("Solve", function()
            if m_id == nil then
                return
            end
            local id = m_id --[[@as string]]
            Puzzle.ConfirmWide(id, "Solve the puzzle?", { "It is marked solved for everyone." }, "Solve", function()
                Puzzle.Solve(id)
            end, { effects = "onSolve" })
        end),
        SmallButton("Bypass", function()
            if m_id == nil then
                return
            end
            local id = m_id --[[@as string]]
            Puzzle.ConfirmWide(id, "Bypass the puzzle?", { "It opens as if solved." }, "Bypass", function()
                Puzzle.Bypass(id)
            end, { effects = "onSolve" })
        end),
        hintButton,
        rolesButton,
        timerButtons,
        refreshDirector = function(element, def, status, left)
            hintButton:SetClass("collapsed", def.Hint == nil or status.hint == true or status.solved == true)
            rolesButton:SetClass("collapsed", def.roles == nil or #def.roles == 0)
        end,
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        vmargin = 4,
        monitorGame = m_id ~= nil and Puzzle.MonitorPaths(m_id) or nil,
        refreshGame = function(element)
            Refresh()
        end,
        --re-point the frame at another puzzle (a journal tag whose page got saved).
        setPuzzle = function(element, newId)
            if newId == m_id then
                return
            end
            m_id = newId
            g_frames[element] = newId
            m_builtType = "__rebuild"
            element.monitorGame = newId ~= nil and Puzzle.MonitorPaths(newId) or nil
            Refresh()
        end,
        refreshPuzzleFrame = function(element)
            Refresh()
        end,
        --timers tick and stale holds expire with no write, so re-check now and then.
        thinkTime = 0.5,
        think = function(element)
            if m_id ~= nil and (Puzzle.TimeLeft(m_id) ~= nil or Puzzle.AnyHolds(m_id) or Editing()) then
                Refresh()
            end
            --a puzzle on a journal page counts as being at it, as a window
            --does: the host waits for this player's view of a game's deal.
            element.data.ticks = (element.data.ticks or 0) + 1
            if m_id ~= nil and element.data.ticks % FRAME_HEARTBEAT_TICKS == 1 and not Editing() and Puzzle.Exists(m_id) then
                Puzzle.MarkPresent(m_id, true, Where())
            end
            --who else is in it; players do not see the Director.
            if m_id ~= nil and element.data.ticks % 4 == 1 then
                local names = {}
                for _, userid in ipairs(Puzzle.PresentUsers(m_id)) do
                    if userid ~= dmhub.userid and (dmhub.isDM or not dmhub.IsUserDM(userid)) then
                        names[#names + 1] = Puzzle.UserNameWhere(m_id, userid)
                    end
                end
                local text = #names > 0 and ("Also in it: " .. table.concat(names, ", ") .. ".") or ""
                if presenceLabel.text ~= text then
                    presenceLabel.text = text
                    presenceLabel:SetClass("collapsed", text == "")
                end
            end
        end,
        destroy = function(element)
            local id = g_frames[element]
            g_frames[element] = nil
            if id ~= nil and not Puzzle.IsShownLocally(id) then
                Puzzle.MarkPresent(id, false)
            end
        end,
        data = {},

        directorPill,
        --the "?" sits beside the board's top-right corner, never over the board.
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            content,
            helpButton,
        },
        placeholder,
        awayLabel,
        banner,
        hintLabel,
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            statusLabel,
            gui.Panel{ width = 12, height = 1 },
            timerLabel,
        },
        assistRow,
        presenceLabel,
        directorRow,
    }

    g_frames[resultPanel] = m_id
    Refresh()
    return resultPanel
end

--------------------------------------------------------------------------------
-- Setup editor: the type's declared fields, drawn by the framework
--------------------------------------------------------------------------------

---@param field PuzzleField
---@param config table
---@param setConfig fun(changes: table)
---@return Panel|nil
local function FieldControl(field, config, setConfig)
    local key = field.id
    local value = config[key]
    if field.type == "text" or field.type == "multiline" then
        local multi = field.type == "multiline"
        return gui.Input{
            width = 280,
            height = cond(multi, 120, 26),
            bgimage = "panels/square.png",
            bgcolor = "#00000059",
            border = 1,
            borderColor = "#ffffff47",
            hpad = 6,
            vpad = 4,
            borderBox = true,
            multiline = multi,
            lineType = cond(multi, "MultiLineNewLine", nil),
            textAlignment = cond(multi, "topleft", "left"),
            characterLimit = 4000,
            text = tostring(value or ""),
            change = function(input)
                setConfig({ [key] = input.text })
            end,
        }
    elseif field.type == "number" then
        return gui.Slider{
            width = 200,
            labelWidth = 48,
            height = 20,
            minValue = field.min or 0,
            maxValue = field.max or 100,
            handleSize = "100%",
            value = tonumber(value) or field.min or 0,
            change = function(slider)
                setConfig({ [key] = round(slider.value) })
            end,
        }
    elseif field.type == "toggle" then
        return gui.Check{
            classes = {"sizeS"},
            width = "auto",
            height = 22,
            --sizeS does not reach the check's own label; without this a long
            --label pushes the setup box past its window.
            fontSize = 14,
            text = field.label,
            value = value == true,
            change = function(element)
                setConfig({ [key] = element.value })
            end,
        }
    elseif field.type == "choice" then
        return gui.Dropdown{
            options = field.options or {},
            idChosen = tostring(value),
            change = function(dropdown)
                ---@cast dropdown Dropdown
                setConfig({ [key] = dropdown.idChosen })
            end,
        }
    elseif field.type == "image" then
        return gui.IconEditor{
            width = 64,
            height = 64,
            library = "Avatar",
            value = value or nil,
            change = function(element)
                setConfig({ [key] = element.value })
            end,
        }
    elseif field.type == "custom" and field.Control ~= nil then
        return field.Control(config, setConfig)
    end
    return nil
end

--"Use an existing puzzle" for a place (a lock, a page tag): its own puzzle, or
--any set-up puzzle in the index.
---@class PuzzlePick
---@field own string|nil the puzzle this place has on its own
---@field ownText string
---@field choose fun(id: string|nil) nil: back to its own puzzle

---@param id string
---@param pick PuzzlePick
---@return Panel[]
local function PickRows(id, pick)
    local others = {}
    for otherId in pairs(Puzzle.Index()) do
        if otherId ~= pick.own and Puzzle.Exists(otherId) then
            local def = Puzzle.GetType(otherId)
            others[#others + 1] = { id = otherId, text = string.format("%s (%s)", Puzzle.Title(otherId), def ~= nil and def.name or "") }
        end
    end
    if #others == 0 then
        return {}
    end
    table.sort(others, function(a, b) return a.text < b.text end)
    local options = { { id = "own", text = pick.ownText } }
    for _, o in ipairs(others) do
        options[#options + 1] = o
    end
    return {
        gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", text = "Use an existing puzzle:" },
        gui.Dropdown{
            options = options,
            idChosen = cond(id == pick.own or not Puzzle.Exists(id), "own", id),
            change = function(dropdown)
                ---@cast dropdown Dropdown
                local chosen = tostring(dropdown.idChosen)
                local target = cond(chosen == "own", nil, chosen)
                if target == nil and not Puzzle.Exists(id) then
                    return
                end
                if (target or pick.own) ~= id then
                    pick.choose(target)
                end
            end,
        },
    }
end

--The settings popup's contents: type picker, the type's fields, time limit.
---@param id string
---@param onTypeChosen fun(typeid: string)
---@param skipImages boolean|nil true where the image field is already shown beside the setup (the annotations strip)
---@param pick PuzzlePick|nil offers "Use an existing puzzle" first
---@return Panel
function Puzzle.SetupPanel(id, onTypeChosen, skipImages, pick)
    local def = Puzzle.GetType(id)
    local config = Puzzle.ReadConfig(id)
    local rows = {}

    if pick ~= nil then
        for _, row in ipairs(PickRows(id, pick)) do
            rows[#rows + 1] = row
        end
        if #rows > 0 then
            rows[#rows].selfStyle.bmargin = 6
        end
    end

    local places = LiveHomeNames(id)
    if #places > 1 then
        rows[#rows + 1] = gui.Label{
            classes = {"sizeS", "info"},
            width = 300,
            height = "auto",
            bmargin = 6,
            text = "Changes here apply in every place: " .. table.concat(places, ", ") .. ".",
        }
    end

    local function SetConfig(changes)
        for k, v in pairs(changes) do
            config[k] = v
        end
        Puzzle.SetConfig(id, changes)
    end

    local typeOptions = {}
    for _, t in ipairs(PuzzleType.List()) do
        typeOptions[#typeOptions + 1] = { id = t.id, text = t.name }
    end
    rows[#rows + 1] = gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", text = "Puzzle type:" }
    rows[#rows + 1] = gui.Dropdown{
        options = typeOptions,
        idChosen = def ~= nil and def.id or nil,
        textDefault = "Choose...",
        change = function(dropdown)
            ---@cast dropdown Dropdown
            local typeid = tostring(dropdown.idChosen)
            if def == nil or def.id ~= typeid then
                Puzzle.ConfirmWide(id, "Change the puzzle type?", { "The puzzle starts over as the new type." }, "Change", function()
                    onTypeChosen(typeid)
                end, {
                    onCancel = function()
                        if dropdown.valid and def ~= nil then
                            dropdown.idChosen = def.id
                        end
                    end,
                })
            end
        end,
    }

    if def ~= nil then
        local fieldRows = {}
        for _, field in ipairs(def.fields) do
            if field.type ~= "image" or not skipImages then
                local control = FieldControl(field, config, function(changes)
                    SetConfig(changes)
                    for _, row in ipairs(fieldRows) do
                        row:FireEvent("visibility")
                        --custom controls that depend on other fields (a code built
                        --from the chosen symbols) rebuild on this.
                        row:FireEventTree("setupChanged")
                    end
                end)
                if control ~= nil then
                    local f = field
                    local row = gui.Panel{
                        flow = "vertical",
                        width = "auto",
                        height = "auto",
                        tmargin = 6,
                        gui.Label{
                            classes = {"sizeS", cond(f.type == "toggle", "collapsed", nil)},
                            width = "auto",
                            height = "auto",
                            text = f.label .. ":",
                        },
                        control,
                        visibility = function(element)
                            element:SetClass("collapsed", f.visible ~= nil and not f.visible(config))
                        end,
                    }
                    row:FireEvent("visibility")
                    fieldRows[#fieldRows + 1] = row
                    rows[#rows + 1] = row
                end
            end
        end

        if not def.noTimeLimit then
            rows[#rows + 1] = gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", tmargin = 6, text = "Time limit (minutes, 0 for none):" }
            rows[#rows + 1] = FieldControl({ id = "timeLimit", type = "number", label = "Time limit", default = 0, min = 0, max = 30 }, config, SetConfig)
        end
    end

    return gui.Panel{
        classes = {"bordered", "bg"},
        width = "auto",
        height = "auto",
        flow = "vertical",
        pad = 8,
        borderBox = true,
        children = rows,
    }
end

--The annotations-strip editor for a puzzle: a settings cog with the setup, and
--the first image field (or the type's own CreateEditor) as the strip's tile.
---@param getId fun(): string|nil
---@param onTypeChosen fun(id: string, typeid: string)
---@param setTag fun(tag: any)|nil receives the tag object each refreshEditor hands over
---@param getPick (fun(): PuzzlePick|nil)|nil offers "Use an existing puzzle" in the setup
---@return Panel
function Puzzle.CreateEditor(getId, onTypeChosen, setTag, getPick)
    local tile
    local resultPanel

    local function RebuildTile()
        local id = getId()
        local def = id ~= nil and Puzzle.GetType(id) or nil
        local children = {}
        if id ~= nil and def ~= nil then
            local config = Puzzle.ReadConfig(id)
            local panel = nil
            if def.CreateEditor ~= nil then
                panel = def.CreateEditor(id, config, function(changes) Puzzle.SetConfig(id, changes) end)
            else
                for _, field in ipairs(def.fields) do
                    if field.type == "image" then
                        panel = FieldControl(field, config, function(changes) Puzzle.SetConfig(id, changes) end)
                        break
                    end
                end
            end
            children[1] = panel
        end
        tile.children = children
    end

    tile = gui.Panel{
        width = 64,
        height = 64,
        halign = "center",
        valign = "center",
    }

    resultPanel = gui.Panel{
        flow = "none",
        width = 96,
        height = "100%",
        data = { builtFor = nil },
        refreshEditor = function(element, richTag)
            if richTag ~= nil and setTag ~= nil then
                setTag(richTag)
            end
            local key = tostring(getId()) .. ":" .. tostring(getId() and Puzzle.GetTypeId(getId() --[[@as string]]))
            if element.data.builtFor ~= key then
                element.data.builtFor = key
                RebuildTile()
            end
        end,
        gui.Button{
            classes = {"settingsButton", "sizeXxs"},
            halign = "right",
            valign = "top",
            press = function(element)
                if element.popup ~= nil then
                    element.popup = nil
                    return
                end
                local id = getId()
                if id == nil then
                    return
                end
                element.popupsInheritStyles = true
                local pick = getPick ~= nil and getPick() or nil
                if pick ~= nil then
                    local choose = pick.choose
                    pick.choose = function(otherId)
                        choose(otherId)
                        element.popup = nil
                        resultPanel.data.builtFor = nil
                        resultPanel:FireEvent("refreshEditor")
                    end
                end
                element.popup = Puzzle.SetupPanel(id, function(typeid)
                    onTypeChosen(id, typeid)
                    element.popup = nil
                    resultPanel.data.builtFor = nil
                    resultPanel:FireEvent("refreshEditor")
                end, true, pick)
            end,
        },
        tile,
    }
    return resultPanel
end

--------------------------------------------------------------------------------
-- Floating puzzle window, Join notices and pushes
--------------------------------------------------------------------------------

--How often an open window renews this player's presence.
local HEARTBEAT_SECONDS = 10

---@type table<string, Panel>
local g_windows = {}

--Puzzles this client has already shown a Join notice for, this session.
---@type table<string, boolean>
local g_noticed = {}

--Pushes this client has already acted on (or that predate its arrival).
---@type table<string, string>
local g_pushSeen = {}

---@param id string
---@return boolean
function Puzzle.IsWindowOpen(id)
    local window = g_windows[id]
    return window ~= nil and window.valid
end

--Open a puzzle in a floating window that does not block the map. One window per
--puzzle; opening it again leaves the existing one, unless this opening is at
--the lock and that one was not. opts.header(id) may return a panel for the
--title bar (the map lock adds the Director's setup button there); opts.atLock
--and opts.where go to the frame (Puzzle.CreatePanel).
---@param id string
---@param opts {header: (fun(id: string): Panel|nil)|nil, atLock: boolean|nil, where: string|nil}|nil
---@return Panel|nil
function Puzzle.OpenWindow(id, opts)
    opts = opts or {}
    if Puzzle.IsWindowOpen(id) then
        if not opts.atLock or g_windows[id].data.atLock then
            return g_windows[id]
        end
        g_windows[id]:DestroySelf()
    end
    local window
    local function Close()
        if window ~= nil and window.valid then
            window:DestroySelf()
        end
    end
    local header = opts.header ~= nil and opts.header(id) or nil
    --to the side, not centred: a solve outlines its doors and objects on the map.
    window = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        hmargin = 60,
        flow = "vertical",
        pad = 12,
        borderBox = true,
        draggable = true,
        dragMove = true,
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            Close()
        end,
        data = { atLock = opts.atLock == true, existed = Puzzle.Exists(id) },
        --deleting the puzzle (Puzzle.Forget) closes it on every client.
        monitorGame = Puzzle.MonitorPaths(id),
        refreshGame = function(element)
            if Puzzle.Exists(id) then
                element.data.existed = true
            elseif element.data.existed then
                Close()
            end
        end,
        thinkTime = HEARTBEAT_SECONDS,
        think = function(element)
            if Puzzle.Exists(id) then
                Puzzle.MarkPresent(id, true, opts.where)
            end
        end,
        destroy = function(element)
            g_windows[id] = nil
            if not Puzzle.IsShownLocally(id) then
                Puzzle.MarkPresent(id, false)
            end
        end,
        gui.Button{
            classes = {"sizeXs", cond(HasHowToPlay(id), nil, "collapsed")},
            floating = true,
            text = "?",
            width = 22,
            height = 22,
            halign = "right",
            valign = "top",
            hover = gui.Tooltip("How to play"),
            press = function(element)
                ToggleHowToPlay(element, id)
            end,
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            vmargin = 4,
            --clear of the corner "?".
            rmargin = 30,
            gui.Label{
                classes = {"sizeL", "bold"},
                width = "auto",
                height = "auto",
                valign = "center",
                text = Puzzle.Title(id),
            },
            header,
            gui.Button{
                classes = {"closeButton"},
                valign = "center",
                hmargin = 8,
                click = function(element)
                    Close()
                end,
            },
        },
        Puzzle.CreatePanel(id, { atLock = opts.atLock, where = opts.where, noHelp = true }),
    }
    gui.ShowDialog(mod, window)
    g_windows[id] = window
    g_noticed[id] = true
    Puzzle.MarkPresent(id, true, opts.where)
    return window
end

--Window openers registered by surfaces that know how to open a puzzle with the
--right header (map locks). Falls back to a plain window.
---@type (fun(id: string))|nil
Puzzle.OpenForJoin = nil

---@param id string
local function OpenFromNotice(id)
    if Puzzle.OpenForJoin ~= nil then
        Puzzle.OpenForJoin(id)
    else
        Puzzle.OpenWindow(id)
    end
end

---@param id string
---@param userid string
---@return string
local function JoinText(id, userid)
    local where = Puzzle.PresentWhere(id, userid)
    if where ~= nil then
        return string.format("%s is at %s, %s.", Puzzle.UserName(userid), Puzzle.Title(id), where)
    end
    return string.format("%s is at %s.", Puzzle.UserName(userid), Puzzle.Title(id))
end

--A small notice that someone else is working on a puzzle, with a Join button.
--Shown once per puzzle per session and gone by itself after a while.
---@param id string
---@param userid string
local function ShowJoinNotice(id, userid)
    local notice
    notice = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",
        vmargin = 120,
        flow = "horizontal",
        pad = 8,
        borderBox = true,
        data = { born = dmhub.Time() },
        thinkTime = 1,
        think = function(element)
            if dmhub.Time() - element.data.born > 20 then
                element:DestroySelf()
            end
        end,
        gui.Label{
            classes = {"sizeM"},
            width = "auto",
            height = "auto",
            valign = "center",
            hmargin = 6,
            text = JoinText(id, userid),
        },
        gui.Button{
            classes = {"sizeS"},
            text = "Join",
            valign = "center",
            hmargin = 4,
            click = function(element)
                OpenFromNotice(id)
                notice:DestroySelf()
            end,
        },
        gui.Button{
            classes = {"closeButton"},
            valign = "center",
            click = function(element)
                notice:DestroySelf()
            end,
        },
    }
    gui.ShowDialog(mod, notice)
end

--Every client: notice other players at a puzzle, and open puzzles the Director
--pushes. Pushes already in the document when this client arrives are ignored.
local g_seeded = false
local function PresenceTick()
    local all = Puzzle.AllPresence()
    if not g_seeded then
        g_seeded = true
        for id, entry in pairs(all) do
            g_pushSeen[id] = entry.push
        end
        return
    end
    for id, entry in pairs(all) do
        if entry.push ~= nil and entry.push ~= g_pushSeen[id] then
            g_pushSeen[id] = entry.push
            --already on screen (a journal page): the push has nothing to open.
            if Puzzle.Exists(id) and not Puzzle.IsShownLocally(id) then
                OpenFromNotice(id)
            end
        end
        if not g_noticed[id] and not Puzzle.IsShownLocally(id) and Puzzle.Exists(id) then
            for _, userid in ipairs(Puzzle.PresentUsers(id)) do
                --the Director having it open (preparing it) tells nobody.
                if userid ~= dmhub.userid and not dmhub.IsUserDM(userid) then
                    g_noticed[id] = true
                    ShowJoinNotice(id, userid)
                    break
                end
            end
        end
    end
end

local function SchedulePresenceTick()
    dmhub.Schedule(2, function()
        if mod.unloaded then
            return
        end
        local ok, err = pcall(PresenceTick)
        if not ok then
            print("PUZZLE:: presence tick failed:", err)
        end
        SchedulePresenceTick()
    end)
end
SchedulePresenceTick()

--------------------------------------------------------------------------------
-- The [[puzzle:Name]] tag
--------------------------------------------------------------------------------

local ID_PREFIX = "j_"

function RichPuzzle.CreateDisplay(self)
    local m_token = nil
    local panel
    panel = Puzzle.CreatePanel(Puzzle.JournalId(self, ID_PREFIX), {
        editing = function() return m_token ~= nil and m_token.editor == true end,
        where = function() return Puzzle.OnPageText(self) end,
    })
    local outer
    outer = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        refreshTag = function(element, tag, match, token)
            self = tag or self
            m_token = token
            local id = Puzzle.JournalId(self, ID_PREFIX)
            if id ~= nil and self.identifier then
                if Puzzle.Exists(id) then
                    Puzzle.SetTitle(id, tostring(self.identifier))
                end
            end
            Puzzle.IndexJournal(self, id)
            panel:FireEvent("setPuzzle", id)
            panel:FireEvent("refreshPuzzleFrame")
        end,
        panel,
    }
    return outer
end

function RichPuzzle.CreateEditor(self)
    return Puzzle.CreateEditor(function() return Puzzle.JournalId(self, ID_PREFIX) end, function(id, typeid)
        Puzzle.Create(id, typeid, nil, self.identifier and tostring(self.identifier) or nil)
    end, function(tag) self = tag end, Puzzle.JournalPick(function() return self end, ID_PREFIX))
end

MarkdownDocument.RegisterRichTag(RichPuzzle)
