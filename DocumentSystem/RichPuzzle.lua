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

--The id of the puzzle a journal tag shows: owning page + tag name, so two pages
--never share a puzzle. Nil while the page is unsaved (it has no id yet).
---@param tag RichTag
---@param prefix string keeps legacy tags apart from [[puzzle:]] tags of the same name
---@return string|nil
function Puzzle.JournalId(tag, prefix)
    local doc = tag:GetDocument()
    local docid = doc ~= nil and doc:try_get("id") or nil
    if docid == nil then
        return nil
    end
    return Puzzle.SafeId(string.format("%s%s_%s", prefix, tostring(docid), tostring(tag.identifier or "default")))
end

---@param seconds number
---@return string
local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", seconds // 60, seconds % 60)
end

---@param title string
---@param message string
---@param confirmText string
---@param onConfirm fun()
local function Confirm(title, message, confirmText, onConfirm)
    GameHud.instance:ModalDialog{
        title = title,
        width = 640,
        height = 280,
        buttonsHalign = "center",
        buttons = {
            { text = "Cancel", escapeActivates = true, click = function() end },
            { text = confirmText, click = onConfirm },
        },
        gui.Panel{
            width = 520,
            height = 80,
            halign = "center",
            valign = "center",
            gui.Label{
                classes = {"modalMessage"},
                text = message,
            },
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

--Build the frame for one puzzle. opts.editing() reports whether the page is in
--edit mode (no moves then); opts.width is the frame's width.
---@param id string|nil nil shows the "save the page first" message
---@param opts {editing: (fun(): boolean)|nil, placeholder: string|nil}|nil
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
    local Refresh

    local function Editing()
        return opts.editing ~= nil and opts.editing() == true
    end

    local function IsDirector()
        return dmhub.isDM == true
    end

    local function BuildAssists(def)
        local children = {}
        for _, assist in ipairs(def.assists or {}) do
            local assistid = assist.id
            children[#children + 1] = gui.Check{
                classes = {"sizeS"},
                width = "auto",
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
        if typeid == m_builtType then
            return
        end
        m_builtType = typeid
        m_typePanel = nil
        if def ~= nil and ctx ~= nil then
            local ok, panel = pcall(def.Render, ctx)
            if ok and panel ~= nil then
                m_typePanel = panel
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
            for _, panel in ipairs({banner, hintLabel, statusLabel, timerLabel, assistRow, directorRow}) do
                panel:SetClass("collapsed", true)
            end
            return
        end
        placeholder:SetClass("collapsed", true)

        local id = m_id --[[@as string]]
        local ctx = Puzzle.Context(id, { editing = Editing() })
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

        local left = Puzzle.TimeLeft(id)
        local limit = Puzzle.EffectiveLimit(ctx.config)
        if left ~= nil and not status.solved and not status.failed then
            timerLabel.text = string.format("Time left: %s%s", FormatTime(left), cond(Puzzle.TimerPaused(id), " (paused)", ""))
        else
            timerLabel.text = ""
        end
        timerLabel:SetClass("collapsed", timerLabel.text == "")

        directorRow:SetClass("collapsed", not IsDirector())
        timerButtons:SetClass("collapsed", limit <= 0 or status.solved == true or status.failed == true)
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
            Confirm("Reset the puzzle?", "The table's progress will be lost, and the timer and hint start over.", "Reset", function()
                if mod.unloaded or m_id == nil then
                    return
                end
                Puzzle.Reset(m_id)
            end)
        end),
        SmallButton("Solve", function()
            if m_id then Puzzle.Solve(m_id) end
        end),
        SmallButton("Bypass", function()
            if m_id then Puzzle.Bypass(m_id) end
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
        end,

        content,
        placeholder,
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
        directorRow,
    }

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
    end
    return nil
end

--The settings popup's contents: type picker, the type's fields, time limit.
---@param id string
---@param onTypeChosen fun(typeid: string)
---@return Panel
local function SetupPanel(id, onTypeChosen)
    local def = Puzzle.GetType(id)
    local config = Puzzle.ReadConfig(id)
    local rows = {}

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
                onTypeChosen(typeid)
            end
        end,
    }

    if def ~= nil then
        local fieldRows = {}
        for _, field in ipairs(def.fields) do
            if field.type ~= "image" then
                local control = FieldControl(field, config, function(changes)
                    SetConfig(changes)
                    for _, row in ipairs(fieldRows) do
                        row:FireEvent("visibility")
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

        rows[#rows + 1] = gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", tmargin = 6, text = "Time limit (minutes, 0 for none):" }
        rows[#rows + 1] = FieldControl({ id = "timeLimit", type = "number", label = "Time limit", default = 0, min = 0, max = 30 }, config, SetConfig)
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
---@return Panel
function Puzzle.CreateEditor(getId, onTypeChosen, setTag)
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
                element.popup = SetupPanel(id, function(typeid)
                    onTypeChosen(id, typeid)
                    element.popup = nil
                    resultPanel.data.builtFor = nil
                    resultPanel:FireEvent("refreshEditor")
                end)
            end,
        },
        tile,
    }
    return resultPanel
end

--------------------------------------------------------------------------------
-- The [[puzzle:Name]] tag
--------------------------------------------------------------------------------

local ID_PREFIX = "j_"

function RichPuzzle.CreateDisplay(self)
    local m_token = nil
    local panel
    panel = Puzzle.CreatePanel(Puzzle.JournalId(self, ID_PREFIX), {
        editing = function() return m_token ~= nil and m_token.editor == true end,
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
    end, function(tag) self = tag end)
end

MarkdownDocument.RegisterRichTag(RichPuzzle)
