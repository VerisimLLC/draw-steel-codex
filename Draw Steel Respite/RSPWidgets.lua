local mod = dmhub.GetModLoading()

--- Controls shared by the Respite steps.
RSPWidgets = {}

--- A "- [n] +" stepper over a bounded integer held in the session.
--- The well never holds the value: it repaints from get() on every
--- respiteChanged, and every edit routes through set().
--- @param args {get: fun(): number, set: fun(n: number), min: number, max: number}
--- @return Panel
function RSPWidgets.Stepper(args)
    local well

    local function Commit(value)
        local n = math.floor(tonumber(value) or args.min)
        n = math.max(args.min, math.min(args.max, n))
        args.set(n)
        if well ~= nil and well.valid then
            well.text = tostring(args.get())
        end
    end

    well = gui.Input{
        classes = {"form"},
        width = RSPConstants.stepperWellWidth,
        halign = "left",
        numeric = true,
        characterLimit = 2,
        textAlignment = "center",
        text = tostring(args.get()),
        respiteChanged = function(element)
            element.text = tostring(args.get())
        end,
        change = function(element)
            Commit(element.text)
        end,
    }

    return gui.Panel{
        classes = {"form"},
        width = RSPConstants.stepperWidth,
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",

        gui.Button{
            classes = {"sizeS"},
            width = RSPConstants.stepperButtonWidth,
            text = "-",
            valign = "center",
            press = function()
                Commit(args.get() - 1)
            end,
        },

        well,

        gui.Button{
            classes = {"sizeS"},
            width = RSPConstants.stepperButtonWidth,
            text = "+",
            valign = "center",
            press = function()
                Commit(args.get() + 1)
            end,
        },
    }
end

--- The pane in which a step explains itself. Runs down the left of the working
--- area, or across the top of it.
--- text may be a function when the copy depends on the session, in which case
--- it is asked again on every respiteChanged.
--- @param args {text: string|fun(): string, orientation: string}
--- @return Panel
function RSPWidgets.Instructions(args)
    local side = args.orientation == RSPConstants.orientSide

    local function Text()
        if type(args.text) == "function" then
            return args.text()
        end
        return args.text
    end

    return gui.Panel{
        width = side and RSPConstants.instructionsSideWidth or "100%",
        height = side and "100%" or RSPConstants.instructionsTopHeight,
        halign = "left",
        valign = "top",
        flow = "vertical",
        rmargin = side and 16 or 0,
        bmargin = side and 0 or 12,

        gui.Label{
            classes = {"sizeS", "noBold", "fgMuted"},
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            textWrap = true,
            text = Text(),
            respiteChanged = function(element)
                element.text = Text()
            end,
        },
    }
end

--- Elf names in this setting run long enough to crowd out everything beside
--- them, so a name past the limit is cut and marked as cut.
--- @param name string
--- @return string
local function ShortName(name)
    local limit = RSPConstants.characterRowNameMaxChars
    if name == nil or #name <= limit then
        return name or ""
    end
    return string.sub(name, 1, limit - 3) .. "..."
end

--- How many widgets sit to the right of the name.
--- @vararg any
--- @return number
local function TrailingCount(...)
    local count = 0
    -- select rather than ipairs: the arguments are sparse, and ipairs would
    -- stop counting at the first widget a row does not use.
    for i = 1, select("#", ...) do
        if select(i, ...) ~= nil then
            count = count + 1
        end
    end
    return count
end

--- One character in a list: token image, name, and whatever the step uses to
--- show that character's standing. The row holds no state - highlight() and
--- indicator() are asked again on every respiteChanged.
--- Set indent to sit the row under the one above it, which is how a follower
--- reads as belonging to its hero.
--- @param args {charid: string, highlight: fun(charid: string): boolean, click: nil|fun(charid: string), indicator: nil|fun(charid: string): string, indent: nil|boolean}
--- @return Panel|nil
function RSPWidgets.CharacterRow(args)
    local token = dmhub.GetCharacterById(args.charid)
    if token == nil then
        return nil
    end

    local indicator = args.indicator ~= nil and gui.Label{
        classes = {"sizeS", "noBold"},
        width = RSPConstants.characterRowIndicatorWidth,
        height = "auto",
        halign = "right",
        valign = "center",
        textAlignment = "right",
        hmargin = 8,
        text = args.indicator(args.charid),
        respiteChanged = function(element)
            element.text = args.indicator(args.charid)
        end,
    } or nil

    -- rolls() is asked for this row's charid and, for a follower, the hero
    -- holding its rolls. Spending a roll never touches the Respite document,
    -- so the count watches the downtime settings the way that module's own
    -- roll counter does: every roll pings it. Assigned on a delay, and only
    -- when that module is installed.
    local rolls = args.rolls ~= nil and gui.Label{
        classes = {"sizeS", "bold"},
        width = RSPConstants.characterRowRollsWidth,
        height = "auto",
        halign = "right",
        valign = "center",
        textAlignment = "right",
        lmargin = 4,
        rmargin = RSPConstants.characterRowRollsRightMargin,
        text = tostring(args.rolls(args.charid, args.owner)),
        create = function(element)
            dmhub.Schedule(0.2, function()
                local settings = rawget(_G, "DTSettings")
                if element.valid and settings ~= nil then
                    element.monitorGame = settings.GetDocumentPath()
                end
            end)
        end,
        refreshGame = function(element)
            element.text = tostring(args.rolls(args.charid, args.owner))
        end,
        respiteChanged = function(element)
            element.text = tostring(args.rolls(args.charid, args.owner))
        end,
    } or nil

    -- status() returns nil for a row that carries no completion of its own,
    -- which is how a follower sits under its hero without claiming a state.
    -- The slot is still built, empty, so every row's trailing widgets line up
    -- in a column rather than shuffling left on the rows that skip it.
    -- The icon swallows its own press so toggling done never doubles as
    -- selecting the row.
    -- Spelled out rather than an and/or chain: a not-done row answers false,
    -- and false collapses to the fallback, which would read as "no state".
    local function StatusOf()
        if args.status == nil then
            return nil
        end
        return args.status(args.charid)
    end

    local status = args.status ~= nil and gui.Panel{
        classes = {"rspStatus",
            StatusOf() == nil and "hidden" or nil,
            args.statusClick ~= nil and "hoverable" or nil,
            StatusOf() and "done" or "pending"},
        bgimage = StatusOf() and RSPConstants.iconDone or RSPConstants.iconNotDone,
        width = RSPConstants.characterRowStatusSize,
        height = RSPConstants.characterRowStatusSize,
        halign = "right",
        valign = "center",
        hmargin = 8,
        swallowPress = args.statusClick ~= nil,
        press = args.statusClick ~= nil and function()
            if StatusOf() ~= nil then
                args.statusClick(args.charid)
            end
        end or nil,
        respiteChanged = function(element)
            local done = StatusOf()
            element.bgimage = done and RSPConstants.iconDone or RSPConstants.iconNotDone
            element:SetClass("hidden", done == nil)
            element:SetClass("done", done == true)
            element:SetClass("pending", done ~= true)
        end,
    } or nil

    local lock = args.lock ~= nil and gui.Panel{
        classes = {"rspLock", not args.lock(args.charid) and "unlocked" or nil},
        bgimage = args.lock(args.charid) and RSPConstants.iconCommitted or RSPConstants.iconUncommitted,
        width = RSPConstants.characterRowLockSize,
        height = RSPConstants.characterRowLockSize,
        halign = "right",
        valign = "center",
        hmargin = 8,
        respiteChanged = function(element)
            local committed = args.lock(args.charid)
            element.bgimage = committed and RSPConstants.iconCommitted or RSPConstants.iconUncommitted
            element:SetClass("unlocked", not committed)
        end,
    } or nil

    return gui.Panel{
        classes = {"row", args.click ~= nil and "hoverable" or nil},
        width = "100%",
        height = RSPConstants.characterRowHeight,
        flow = "horizontal",
        halign = "left",
        valign = "top",

        respiteChanged = function(element)
            element:SetClass("selected", args.highlight ~= nil and args.highlight(args.charid))
        end,

        create = function(element)
            element:SetClass("selected", args.highlight ~= nil and args.highlight(args.charid))
        end,

        press = args.click ~= nil and function()
            args.click(args.charid)
        end or nil,

        -- The indent shifts the image rather than padding the row: padding
        -- would widen the row past 100% and push the last widget off the end.
        gui.CreateTokenImage(token, {
            width = RSPConstants.characterRowImageSize,
            height = RSPConstants.characterRowImageSize,
            halign = "left",
            valign = "center",
            lmargin = args.indent and RSPConstants.characterRowIndent or 0,
        }),

        gui.Label{
            classes = {"sizeM", "noBold"},
            width = RSPConstants.CharacterRowNameWidth(TrailingCount(indicator, rolls, status, lock), args.indent),
            height = "auto",
            halign = "left",
            valign = "center",
            hmargin = 8,
            -- A long name shortens rather than wrapping, which would push the
            -- row taller than the rest of the list.
            textWrap = false,
            text = ShortName(token.name),
        },

        indicator,
        rolls,
        status,
        lock,
    }
end

--- A scrolling column of characters. The rows are built once from the roster
--- and repainted in place, so a session change never rebuilds the list.
--- @param args {roster: string[], highlight: fun(charid: string): boolean, click: nil|fun(charid: string), indicator: nil|fun(charid: string): string}
--- @return Panel
function RSPWidgets.CharacterList(args)
    local rows = {}
    for _, entry in ipairs(args.roster) do
        -- A roster is either plain charids or {charid, indent} entries, so a
        -- flat list and a hero-with-followers list share this widget.
        local charid = entry
        local indent = false
        local owner = nil
        if type(entry) == "table" then
            charid = entry.charid
            indent = entry.indent == true
            owner = entry.owner
        end

        rows[#rows + 1] = RSPWidgets.CharacterRow{
            charid = charid,
            highlight = args.highlight,
            click = args.click,
            indicator = args.indicator,
            rolls = args.rolls,
            status = args.status,
            statusClick = args.statusClick,
            lock = args.lock,
            indent = indent,
            owner = owner,
        }
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vscroll = true,

        -- Somewhere for a caller to keep which row is selected. That is one
        -- viewer's state, so it stays on the panel and out of the document.
        data = {
            selected = nil,
        },

        children = rows,
    }
end

--- The terms of the Respite, for the right of a step's header. Every surface
--- past Setup shows the same line, so it is written once here.
--- @return string markdown
function RSPWidgets.RespiteSummary()
    local mayText = "may not"
    if RSPSession.NonParticipantsMayAct() then
        mayText = "may"
    end

    return string.format(
        "Days Elapsed: **%d** | Downtime Activities: **%d** | Non participants **%s** do downtime.",
        RSPSession.DaysElapsed(),
        RSPSession.ActivityCount(),
        mayText)
end

--- Rules the theme has no vocabulary for. The lock has to invert with the row
--- it sits on, the way {label, parent:row, parent:selected} already does for
--- text, and the open lock reads as quiet rather than absent.
--- @return table style rules
function RSPWidgets.CustomStyles()
    return {
        {
            selectors = {"rspLock"},
            bgcolor = "@fg",
        },
        {
            selectors = {"rspLock", "parent:selected"},
            bgcolor = "@fgInverse",
        },
        {
            selectors = {"rspLock", "unlocked"},
            opacity = 0.35,
        },
        -- Completion reads at a glance: a quiet circle until the work is
        -- done, then the scheme's success colour.
        {
            selectors = {"rspStatus"},
            bgcolor = "@fg",
        },
        {
            selectors = {"rspStatus", "pending"},
            opacity = 0.35,
        },
        {
            selectors = {"rspStatus", "done"},
            bgcolor = "@success",
        },
        -- The theme dims disabled buttons and checkboxes but has no rule for
        -- a disabled input or dropdown, and Setup needs both greyed while
        -- there is no water open.
        {
            selectors = {"input", "disabled"},
            bgcolor = "@disabled",
            opacity = 0.3,
            priority = 5,
        },
        {
            selectors = {"dropdown", "disabled"},
            bgcolor = "@disabled",
            opacity = 0.3,
            priority = 5,
        },
    }
end

--- Re-fires the shell's refresh when a document outside the session changes.
--- The Respite reads fishing straight from the fishing module's own document,
--- so a change made there has to reach these panels too.
--- @param path string monitorGame path of the foreign document
--- @return Panel
function RSPWidgets.DocumentMonitor(path)
    return gui.Panel{
        width = 0,
        height = 0,
        monitorGame = path,
        refreshGame = function(element)
            local shell = element:FindParentWithClass("rspShell")
            if shell ~= nil then
                shell:FireEventTree("respiteChanged")
            end
        end,
    }
end

--- A label-left, control-right form row. Shared so a registered activity can
--- paint its own fields in the same language as the rest of the step.
--- @param labelText string
--- @param control Panel
--- @return Panel
function RSPWidgets.FormRow(labelText, control)
    return gui.Panel{
        classes = {"formRow"},

        gui.Label{
            classes = {"label", "form"},
            width = RSPConstants.formLabelWidth,
            text = labelText,
        },

        control,
    }
end
