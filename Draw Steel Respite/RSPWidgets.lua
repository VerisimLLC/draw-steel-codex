local mod = dmhub.GetModLoading()

--- Controls shared by the Respite steps.
RSPWidgets = RegisterGameType("RSPWidgets")

--- A "- [n] +" stepper over a bounded integer held in the session.
--- The well never holds the value: it repaints from get() on every
--- respiteChanged, and every edit routes through set().
--- Pass label to cap the well with a small centered header. The header is a
--- fixed line above an untouched strip: well-wide, indented one button, so it
--- spans exactly the well's run and centers over the text box.
--- @param args {get: fun(): number, set: fun(n: number), min: number, max: number, width: nil|number|string, label: nil|string, lmargin: nil|number}
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

    local strip = gui.Panel{
        classes = {"form"},
        width = args.width or RSPConstants.stepperWidth,
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        lmargin = args.label == nil and args.lmargin or nil,

        gui.Button{
            classes = {"sizeS"},
            width = RSPConstants.stepperButtonSize,
            height = RSPConstants.stepperButtonSize,
            text = "-",
            valign = "center",
            press = function()
                Commit(args.get() - 1)
            end,
        },

        well,

        gui.Button{
            classes = {"sizeS"},
            width = RSPConstants.stepperButtonSize,
            height = RSPConstants.stepperButtonSize,
            text = "+",
            valign = "center",
            press = function()
                Commit(args.get() + 1)
            end,
        },
    }

    if args.label == nil then
        return strip
    end

    --The themed input does not honor a requested width, so nothing here is
    --sized from constants. The wrapper hugs whatever the strip really renders
    --as, and the label centers over it as an element - the buttons flanking
    --the well are equal, so the strip's center IS the well's center.
    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        lmargin = args.lmargin,

        gui.Label{
            --Not "form": the {label, form} rule pins color to @fgStrong and,
            --being two selectors, outranks single-selector fgMuted.
            classes = {"label", "fgMuted", "sizeXxs"},
            halign = "center",
            text = args.label,
        },

        strip,
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
        lmargin = 0,
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

    -- The settings document above catches a project roll, which pings it, but
    -- not a fishing trip: that spends the roll by writing the holder's token
    -- and nothing else. A panel carries one monitorGame, so the token gets a
    -- watcher of its own. Zero-sized, so it costs the row no width.
    local rollsWatcher = nil
    if rolls ~= nil then
        local holder = dmhub.GetCharacterById(args.owner or args.charid)
        if holder ~= nil then
            rollsWatcher = gui.Panel{
                width = 0,
                height = 0,
                halign = "left",
                valign = "center",
                monitorGame = holder.monitorPath,
                refreshGame = function()
                    if rolls.valid then
                        rolls.text = tostring(args.rolls(args.charid, args.owner))
                    end
                end,
            }
        end
    end

    -- Something on this character wants the Director. Built even when there is
    -- nothing to say, so the rows either side keep their column.
    local attention = args.attention ~= nil and gui.Panel{
        classes = {"rspAttention", not args.attention(args.charid) and "hidden" or nil},
        bgimage = RSPConstants.iconAttention,
        width = RSPConstants.characterRowAttentionSize,
        height = RSPConstants.characterRowAttentionSize,
        halign = "right",
        valign = "center",
        hmargin = 0,
        -- What raises this lives in the activities, which keep their state in
        -- their own documents. They call RSPSession.Ping when something moves,
        -- which touches the Respite's document and brings every panel here
        -- with it -- so this one handler covers a fishing breakthrough as well
        -- as anything the Respite itself changes.
        respiteChanged = function(element)
            element:SetClass("hidden", not args.attention(args.charid))
        end,
    } or nil

    -- Opens this character's own sheet. Swallows its own press so reaching for
    -- the sheet never doubles as selecting the row.
    -- Heroes only: a follower's sheet is not what anyone wants from this list.
    -- The slot is still built, empty, on a follower's row, so every row's
    -- trailing widgets stay in a column rather than shuffling left.
    local isFollower = args.owner ~= nil

    local sheet = args.sheet ~= nil and gui.Panel{
        classes = {"rspSheet", isFollower and "hidden" or nil},
        bgimage = RSPConstants.iconCharacterSheet,
        width = RSPConstants.characterRowSheetSize,
        height = RSPConstants.characterRowSheetSize,
        halign = "right",
        valign = "center",
        hmargin = 4,
        swallowPress = not isFollower,
        linger = not isFollower and gui.Tooltip("Open character sheet") or nil,
        press = not isFollower and function()
            args.sheet(args.charid, args.owner)
        end or nil,
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

        -- The owner rides along so a caller can act on the hero a follower
        -- belongs to. Rows that are not followers pass nil, and callers that
        -- do not care simply ignore the second argument.
        press = args.click ~= nil and function()
            args.click(args.charid, args.owner)
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
            width = RSPConstants.CharacterRowNameWidth(TrailingCount(indicator, attention, rolls, sheet, lock), args.indent),
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
        attention,
        rolls,
        sheet,
        lock,

        -- Last and zero-sized, and deliberately not counted among the trailing
        -- widgets above: it occupies no column, so the name must not give up
        -- a slot for it.
        rollsWatcher,
    }
end

--- A scrolling column of characters. Rows repaint themselves in place, and the
--- list rebuilds them when the roster itself changes - a window built before
--- the Director picked participants would otherwise keep the empty roster it
--- started with for the rest of the Respite.
--- @param args {roster: string[]|function, highlight: fun(charid: string): boolean, click: nil|fun(charid: string), indicator: nil|fun(charid: string): string}
--- @return Panel
function RSPWidgets.CharacterList(args)
    --Forward-declared: the token watchers below are built as children, so they
    --need to reach the list that owns them.
    local listPanel
    local RebuildIfRosterMoved

    --- The roster as it stands now. Callers may pass a fixed list or a function
    --- for a roster that is not known when the list is built.
    --- @return table
    local function Roster()
        local roster = args.roster
        if type(roster) == "function" then
            return roster() or {}
        end
        return roster or {}
    end

    --- Splits a roster entry, which is either a plain charid or a table, so a
    --- flat list and a hero-with-followers list share this widget.
    --- @param entry string|table
    --- @return string charid, boolean indent, string|nil owner
    local function ReadEntry(entry)
        if type(entry) == "table" then
            return entry.charid, entry.indent == true, entry.owner
        end
        return entry, false, nil
    end

    --- Followers are kept on their hero's token, so gaining or losing one
    --- writes that token and nothing else - the Respite document never moves,
    --- and a list that only listens for respiteChanged is never told. One
    --- zero-sized watcher per hero closes that: the token pings it, and the
    --- signature check decides whether the roster actually changed.
    --- @return Panel[] watchers
    local function HeroWatchers()
        local seen = {}
        local watchers = {}

        for _, entry in ipairs(Roster()) do
            local charid, _, owner = ReadEntry(entry)
            local heroId = owner or charid

            if not seen[heroId] then
                seen[heroId] = true
                local token = dmhub.GetCharacterById(heroId)
                if token ~= nil then
                    watchers[#watchers + 1] = gui.Panel{
                        width = 0,
                        height = 0,
                        halign = "left",
                        valign = "top",
                        monitorGame = token.monitorPath,
                        refreshGame = function()
                            RebuildIfRosterMoved()
                        end,
                    }
                end
            end
        end

        return watchers
    end

    local function BuildRows()
        local rows = {}
        for _, entry in ipairs(Roster()) do
            local charid, indent, owner = ReadEntry(entry)

            rows[#rows + 1] = RSPWidgets.CharacterRow{
                charid = charid,
                highlight = args.highlight,
                click = args.click,
                indicator = args.indicator,
                attention = args.attention,
                rolls = args.rolls,
                sheet = args.sheet,
                lock = args.lock,
                indent = indent,
                owner = owner,
            }
        end

        for _, watcher in ipairs(HeroWatchers()) do
            rows[#rows + 1] = watcher
        end

        return rows
    end

    --- Who the rows were built for. Compared on every refresh so the list
    --- rebuilds only when the roster changes, leaving the rows to repaint
    --- themselves the rest of the time.
    --- @return string
    local function Signature()
        local parts = {}
        for _, entry in ipairs(Roster()) do
            local charid, indent = ReadEntry(entry)
            parts[#parts + 1] = string.format("%s:%s", tostring(charid), indent and "1" or "0")
        end
        return table.concat(parts, ",")
    end

    --Rebuilds only when the roster actually moved, so a token ping that changed
    --something else costs a string compare and nothing more.
    RebuildIfRosterMoved = function()
        if listPanel == nil or not listPanel.valid then
            return
        end

        local signature = Signature()
        if signature ~= listPanel.data.signature then
            listPanel.data.signature = signature
            listPanel.children = BuildRows()
        end
    end

    listPanel = gui.Panel{
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
            signature = Signature(),
        },

        respiteChanged = function()
            RebuildIfRosterMoved()
        end,

        children = BuildRows(),
    }

    return listPanel
end

--- The terms of the Respite, for the right of a step's header. Every surface
--- past Setup shows the same line, so it is written once here.
--- @return string markdown
function RSPWidgets.RespiteSummary()
    local mayText = "may not"
    if RSPSession.NonParticipantsMayAct() then
        mayText = "may"
    end

    --One number while the two allowances agree; both spelled out once split.
    local activitiesText = string.format("**%d**", RSPSession.ActivityCount())
    if RSPSession.FollowerActivityCount() ~= RSPSession.ActivityCount() then
        activitiesText = string.format("**%d** heroes / **%d** followers",
            RSPSession.ActivityCount(), RSPSession.FollowerActivityCount())
    end

    local summary = string.format(
        "Days Elapsed: **%d** | Downtime Activities: %s | Non participants **%s** do downtime.",
        RSPSession.DaysElapsed(),
        activitiesText,
        mayText)

    local location = RSPSession.Location()
    if location ~= "" then
        summary = string.format("**%s** | %s", location, summary)
    end

    return summary
end

--- Rules the theme has no vocabulary for. The lock has to invert with the row
--- it sits on, the way {label, parent:row, parent:selected} already does for
--- text, and the open lock reads as quiet rather than absent.
--- @return table style rules
function RSPWidgets.CustomStyles()
    return {
        -- The size ladder does not reach a checkbox: DefaultStyles gives every
        -- one a flat 30 high and defines no size variants, so two stacked in a
        -- footer band overflow it. Completing the ladder here rather than in
        -- DefaultStyles keeps a component-specific rule out of the shared
        -- vocabulary, and rather than reaching into the checkbox itself.
        {
            selectors = {"checkbox", "sizeS"},
            height = 22,
        },
        {
            selectors = {"checkbox", "sizeXs"},
            height = 18,
        },
        -- Opens the character sheet. Dimmed until hovered so it reads as an
        -- affordance rather than another state icon on the row.
        {
            selectors = {"rspSheet"},
            bgcolor = "@fg",
            opacity = 0.5,
        },
        {
            selectors = {"rspSheet", "hover"},
            opacity = 1,
        },
        {
            selectors = {"rspSheet", "parent:selected"},
            bgcolor = "@fgInverse",
        },
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
        -- Something the Director has to act on. Left standing until the
        -- Respite is completed, so it is a state rather than a notification.
        {
            selectors = {"rspAttention"},
            bgcolor = "@warning",
        },
        {
            selectors = {"rspEventAlert"},
            bgcolor = "@warning",
        },
        {
            selectors = {"rspEventGood"},
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
