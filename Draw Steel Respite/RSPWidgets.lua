local mod = dmhub.GetModLoading()

--- Controls shared by the Respite steps.
--- @class RSPWidgets: GameType
--- @field new fun(o?: table): RSPWidgets
RSPWidgets = RegisterGameType("RSPWidgets")

--- @class RSPStepperArgs
--- @field get fun(): number
--- @field set fun(n: number)
--- @field min number
--- @field max number
--- @field width? number|string
--- @field label? string
--- @field lmargin? number

--- A "- [n] +" stepper over a bounded integer held in the session.
--- The well never holds the value: it repaints from get() on every
--- respiteChanged, and every edit routes through set().
--- Pass label to cap the well with a small centered header. The header is a
--- fixed line above an untouched strip: well-wide, indented one button, so it
--- spans exactly the well's run and centers over the text box.
--- @param args RSPStepperArgs
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

--- @class RSPInstructionsArgs
--- @field text string|(fun(): string)
--- @field orientation string

--- The pane in which a step explains itself. Runs down the left of the working
--- area, or across the top of it.
--- text may be a function when the copy depends on the session, in which case
--- it is asked again on every respiteChanged.
--- @param args RSPInstructionsArgs
--- @return Panel
function RSPWidgets.Instructions(args)
    local side = args.orientation == RSPConstants.orientSide

    --- @return string
    local function Text()
        local text = args.text
        if type(text) == "function" then
            return text()
        end
        return text
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

--- Per-character callbacks shared by CharacterRow and CharacterList. owner is
--- the hero a follower's row belongs to, nil on a hero's own row.
--- @class RSPCharacterCallbacks
--- @field highlight? fun(charid: string): boolean
--- @field click? fun(charid: string, owner: string|nil)
--- @field indicator? fun(charid: string): string
--- @field check? fun(charid: string): boolean
--- @field attention? fun(charid: string): boolean
--- @field rolls? fun(charid: string, owner: string|nil): number
--- @field sheet? fun(charid: string, owner: string|nil)
--- @field lock? fun(charid: string): boolean

--- @class RSPCharacterRowArgs: RSPCharacterCallbacks
--- @field charid string
--- @field owner? string
--- @field indent? boolean

--- @class RSPCharacterListArgs: RSPCharacterCallbacks
--- @field roster string[]|function

--- One character in a list: token image, name, and whatever the step uses to
--- show that character's standing. The row holds no state - highlight() and
--- indicator() are asked again on every respiteChanged.
--- Set indent to sit the row under the one above it, which is how a follower
--- reads as belonging to its hero.
--- @param args RSPCharacterRowArgs
--- @return Panel|nil
function RSPWidgets.CharacterRow(args)
    local token = dmhub.GetCharacterById(args.charid)
    if token == nil then
        return nil
    end

    -- Opt-in as a checkbox ahead of the token image. gui.Check always builds a
    -- label, and its themed class carries minWidth 200, so both are pinned shut
    -- here: an empty text and an explicit width/minWidth inline, which a style
    -- selector would lose to. Its press is swallowed so ticking the box does not
    -- also count as pressing the row underneath.
    local check = args.check ~= nil and gui.Check{
        text = "",
        value = args.check(args.charid),
        width = RSPConstants.characterRowCheckWidth,
        minWidth = RSPConstants.characterRowCheckWidth,
        height = RSPConstants.characterRowCheckHeight,
        halign = "left",
        valign = "center",
        hpad = 0,
        hmargin = 0,
        swallowPress = args.click ~= nil,
        change = args.click ~= nil and function(element)
            args.click(args.charid, args.owner)
        end or nil,
        respiteChanged = function(element)
            element.value = args.check(args.charid)
        end,
    } or nil

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

        check,

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
            width = RSPConstants.CharacterRowNameWidth(TrailingCount(indicator, attention, rolls, sheet, lock), args.indent, check ~= nil),
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
--- @param args RSPCharacterListArgs
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
                check = args.check,
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
        "Days Elapsed: **%d** | Downtime Activities: %s | Non participants **%s** do activities.",
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

---@class RSPWatchersArgs
---@field paths fun(): string[] the documents to watch, read again on every rewatch
---@field changed fun() what to do when any of them moves

--- Zero-size watchers over documents that can come and go while the window is
--- open. Pooled by position and re-pointed rather than rebuilt; a watcher past
--- the end of the list stays built but goes quiet.
--- @param args RSPWatchersArgs
--- @return Panel
function RSPWidgets.Watchers(args)
    local function Rewatch(element)
        local paths = args.paths() or {}
        local pool = element.children

        if #pool < #paths then
            local grown = {}
            for i, watcher in ipairs(pool) do
                grown[i] = watcher
            end
            for i = #pool + 1, #paths do
                grown[i] = gui.Panel{
                    width = 0,
                    height = 0,
                    data = {
                        path = nil,
                    },
                    refreshGame = function(watcher)
                        if watcher.data.path ~= nil then
                            args.changed()
                        end
                    end,
                }
            end
            element.children = grown
            pool = grown
        end

        for i, watcher in ipairs(pool) do
            local path = paths[i]
            if path ~= watcher.data.path then
                watcher.data.path = path
                if path ~= nil then
                    watcher.monitorGame = path
                end
            end
        end
    end

    return gui.Panel{
        width = 0,
        height = 0,

        -- Assigned on a delay the way the character sheet does it.
        create = function(element)
            dmhub.Schedule(0.2, function()
                if element.valid then
                    Rewatch(element)
                end
            end)
        end,

        rewatch = function(element)
            Rewatch(element)
        end,
    }
end

--- "Level 3 Fury" from whichever parts the hero has.
--- @param token any
--- @return string
local function HeroLine(token)
    local className = nil
    local level = nil

    pcall(function()
        local classes = dmhub.GetTable("classes")
        for _, entry in ipairs(token.properties:try_get("classes") or {}) do
            local info = classes[entry.classid]
            if info ~= nil and info.name ~= nil then
                className = info.name
            end
        end
    end)

    pcall(function()
        local value = token.properties:CharacterLevel()
        if type(value) == "number" and value >= 1 then
            level = math.floor(value)
        end
    end)

    if level ~= nil and className ~= nil then
        return string.format("Level %d %s", level, className)
    end
    if className ~= nil then
        return className
    end
    if level ~= nil then
        return string.format("Level %d", level)
    end
    return ""
end

--- "Artisan · Kael": what the follower is, and whose.
--- @param token any the follower
--- @param ownerId string the hero they follow
--- @return string
local function FollowerLine(token, ownerId)
    local kind = "Follower"
    local followers = rawget(_G, "DTFollowers")
    if followers ~= nil then
        pcall(function()
            local followerType = followers.FollowerType(token)
            if type(followerType) == "string" and followerType ~= "" then
                kind = followerType:sub(1, 1):upper() .. followerType:sub(2)
            end
        end)
    end

    local owner = dmhub.GetCharacterById(ownerId)
    if owner == nil or owner.name == nil or owner.name == "" then
        return kind
    end
    return string.format("%s · %s", kind, owner.name)
end

---@class RSPStageCardArgs
---@field charid string
---@field owner? string the hero a follower belongs to; nil on a hero
---@field canAct fun(charid: string, owner: string|nil): boolean may this character go into an activity now
---@field resting fun(charid: string): boolean false for a hero sitting the Respite out
---@field selected fun(charid: string): boolean picked by a click, waiting for a station
---@field working fun(charid: string): string|nil the activity's name while inside one
---@field rolls fun(charid: string, owner: string|nil): number
---@field click fun(charid: string, owner: string|nil)
---@field beginDrag fun(charid: string, owner: string|nil)
---@field canDragOnto fun(charid: string, owner: string|nil, target: Panel): boolean
---@field drop fun(charid: string, owner: string|nil, target: Panel|nil)
---@field sheet fun(charid: string)
---@field actions? Panel[] buttons for the hero's top-right corner, under the sheet button

--- A character on the player stage, laid out like the montage's hero card: the
--- portrait is the card, with a plate over its foot. A follower's card is the
--- same card drawn smaller. Built once; repaints on respiteChanged and
--- stageChanged.
--- @param args RSPStageCardArgs
--- @return Panel|nil
function RSPWidgets.StageCard(args)
    local token = dmhub.GetCharacterById(args.charid)
    if token == nil then
        return nil
    end

    local isFollower = args.owner ~= nil
    local scale = isFollower and RSPConstants.cardFollowerScale or 1
    local width = math.floor(RSPConstants.cardWidth * scale)
    local height = math.floor(RSPConstants.cardHeight * scale)

    local nameLabel = gui.Label{
        classes = {"rspCardName", isFollower and "sizeS" or "sizeM", "bold"},
        width = "100%",
        height = "auto",
        halign = "left",
        textWrap = false,
        interactable = false,
        text = token.name or "",
    }

    local lineLabel = gui.Label{
        classes = {"rspCardLine", "sizeXs"},
        width = "100%",
        height = "auto",
        halign = "left",
        textWrap = false,
        interactable = false,
        text = "",
    }

    local plate = gui.Panel{
        classes = {"rspCardPlate"},
        floating = true,
        width = "100%",
        height = math.floor(RSPConstants.cardPlateHeight * scale),
        halign = "center",
        valign = "bottom",
        flow = "vertical",
        hpad = 6,
        vpad = 4,
        interactable = false,

        nameLabel,
        lineLabel,
    }

    -- Rolls live with the hero, and a fishing cast spends one by writing the
    -- holder's token alone, so the chip watches that token; a project roll
    -- pings the downtime settings document, watched on a delay.
    local holder = dmhub.GetCharacterById(args.owner or args.charid)

    local rollsLabel = gui.Label{
        classes = {"rspCardChipText", "sizeS", "bold"},
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 3,
        textWrap = false,
        interactable = false,
        text = tostring(args.rolls(args.charid, args.owner)),
        refreshGame = function(element)
            element.parent:FireEvent("refreshRolls")
        end,
    }

    local rollsChip = gui.Panel{
        classes = {"rspCardChip"},
        floating = true,
        width = "auto",
        height = RSPConstants.cardChipHeight,
        halign = "left",
        valign = "top",
        x = 4,
        y = 4,
        flow = "horizontal",
        hpad = 5,
        monitorGame = holder ~= nil and holder.monitorPath or nil,
        linger = gui.Tooltip("Downtime rolls left"),

        create = function(element)
            dmhub.Schedule(0.2, function()
                local settings = rawget(_G, "DTSettings")
                if element.valid and settings ~= nil then
                    rollsLabel.monitorGame = settings.GetDocumentPath()
                end
            end)
        end,
        refreshGame = function(element)
            element:FireEventTree("refreshRolls")
        end,
        refreshRolls = function(element)
            local rolls = args.rolls(args.charid, args.owner)
            rollsLabel.text = tostring(rolls)
            element:SetClass("empty", rolls <= 0)
        end,

        gui.Panel{
            classes = {"rspCardChipIcon"},
            bgimage = RSPConstants.iconRolls,
            width = 14,
            height = 14,
            valign = "center",
            interactable = false,
        },
        rollsLabel,
    }

    -- The sheet and the hero's own buttons, down the top-right corner.
    local corner = nil
    if not isFollower then
        local buttons = {
            gui.Panel{
                classes = {"rspCardButton"},
                width = RSPConstants.cardCornerButton,
                height = RSPConstants.cardCornerButton,
                halign = "right",
                bmargin = 4,
                swallowPress = true,
                linger = gui.Tooltip("Open character sheet"),
                press = function()
                    args.sheet(args.charid)
                end,

                gui.Panel{
                    classes = {"rspCardButtonIcon"},
                    bgimage = RSPConstants.iconCharacterSheet,
                    width = "70%",
                    height = "70%",
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            },
        }

        -- Each action wears the sheet button's backing, so it reads over any portrait.
        for _, action in ipairs(args.actions or {}) do
            action.selfStyle.width = RSPConstants.cardCornerButton
            action.selfStyle.height = RSPConstants.cardCornerButton
            action.selfStyle.halign = "center"
            action.selfStyle.valign = "center"
            buttons[#buttons + 1] = gui.Panel{
                classes = {"rspCardButton"},
                width = RSPConstants.cardCornerButton,
                height = RSPConstants.cardCornerButton,
                halign = "right",
                bmargin = 4,

                action,
            }
        end

        corner = gui.Panel{
            floating = true,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "top",
            x = -4,
            y = 4,
            flow = "vertical",
            children = buttons,
        }
    end

    local function Repaint(element)
        local working = args.working(args.charid)
        local resting = isFollower or args.resting(args.charid)

        local line
        if working ~= nil then
            line = working
        elseif not resting then
            line = "Not Resting"
        elseif isFollower then
            line = FollowerLine(token, args.owner)
        else
            line = HeroLine(token)
        end
        if lineLabel.text ~= line then
            lineLabel.text = line
        end
        lineLabel:SetClass("working", working ~= nil)

        local canAct = args.canAct(args.charid, args.owner)
        element.draggable = canAct
        element:SetClass("cannotAct", not resting)
        element:SetClass("selected", args.selected(args.charid))
        element:SetClass("working", working ~= nil)

        if (token.name or "") ~= nameLabel.text then
            nameLabel.text = token.name or ""
        end

        rollsChip:FireEvent("refreshRolls")
    end

    -- The portrait is the card. Without art the token image stands in.
    local portraitApplied = false
    local heroCard = rawget(_G, "EotwHeroCard")

    local card
    card = gui.Panel{
        classes = {"rspCard"},
        width = width,
        height = height,
        halign = "left",
        valign = "bottom",
        hmargin = math.floor(RSPConstants.cardGap / 2),
        bgimage = "panels/square.png",
        draggable = false,
        swallowPress = true,

        data = {
            charid = args.charid,
            owner = args.owner,
        },

        create = function(element)
            if heroCard ~= nil then
                portraitApplied = heroCard.ApplyPortrait(element, token, width / height) == true
            end
            if not portraitApplied then
                element:AddChild(gui.CreateTokenImage(token, {
                    width = width - 16,
                    height = width - 16,
                    halign = "center",
                    valign = "top",
                    tmargin = 8,
                    interactable = false,
                }))
            end
            Repaint(element)
        end,

        respiteChanged = Repaint,
        stageChanged = Repaint,

        click = function()
            args.click(args.charid, args.owner)
        end,

        beginDrag = function(element)
            element:SetClass("dragging", true)
            args.beginDrag(args.charid, args.owner)
        end,

        canDragOnto = function(element, target)
            return args.canDragOnto(args.charid, args.owner, target)
        end,

        drag = function(element, target)
            element:SetClass("dragging", false)
            args.drop(args.charid, args.owner, target)
        end,

        plate,
        rollsChip,
        corner,
    }

    return card
end

--- The player stage's own rules, in theme tokens so it follows the scheme.
--- Shapes follow the montage's cards; colours are the theme's.
--- @return table style rules
function RSPWidgets.StageStyles()
    local motion = 0.15
    pcall(function()
        if ThemeEngine.GetAccessibility().reduceMotion then
            motion = 0
        end
    end)

    local rules = RSPWidgets.CustomStyles()
    local stage = {
        {
            selectors = {"rspStage"},
            bgimage = true,
            bgcolor = "@bg",
        },
        {
            selectors = {"rspStageDim"},
            bgimage = true,
            bgcolor = "@bg",
            opacity = RSPConstants.stageDimOpacity,
        },
        {
            selectors = {"rspStageBand"},
            bgimage = true,
            bgcolor = "@bg",
            opacity = 0.85,
            borderColor = "@border",
        },
        {
            selectors = {"rspStagePanel"},
            bgimage = true,
            bgcolor = "@bgAlt",
            opacity = 0.92,
            cornerRadius = 10,
            border = 1,
            borderColor = "@border",
        },
        {
            selectors = {"rspStageIcon"},
            bgcolor = "@fg",
        },
        -- Follows its button's caption: inverted on hover, greyed when disabled.
        {
            selectors = {"rspBackIcon"},
            bgcolor = "@fg",
        },
        {
            selectors = {"rspBackIcon", "parent:hover"},
            bgcolor = "@fgInverse",
        },
        {
            selectors = {"rspBackIcon", "parent:disabled"},
            bgcolor = "@disabled",
            priority = 5,
        },
        {
            selectors = {"rspChip"},
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 8,
            border = 1,
            borderColor = "@accent",
        },
        {
            selectors = {"rspChip", "hover"},
            bgcolor = "@bgRaised",
        },
        {
            selectors = {"rspStation"},
            bgimage = true,
            bgcolor = "@bgAlt",
            opacity = 0.94,
            cornerRadius = 10,
            border = 1,
            borderColor = "@border",
            transitionTime = motion,
        },
        {
            selectors = {"rspStation", "hover"},
            borderColor = "@accent",
        },
        {
            selectors = {"rspStation", "droppable"},
            border = 3,
            borderColor = "@accent",
            brightness = 1.1,
        },
        {
            selectors = {"rspStationHint"},
            color = "@accent",
        },
        {
            selectors = {"rspHintPlate"},
            bgimage = true,
            bgcolor = "@bg",
            opacity = 0.8,
            cornerRadius = 8,
            border = 1,
            borderColor = "@border",
        },
        {
            selectors = {"rspCard"},
            bgcolor = "@bgAlt",
            cornerRadius = 8,
            border = 1,
            borderColor = "@border",
            transitionTime = motion,
        },
        {
            selectors = {"rspCard", "hover"},
            brightness = 1.15,
        },
        {
            selectors = {"rspCard", "selected"},
            border = 3,
            borderColor = "@accent",
            brightness = 1.15,
        },
        {
            selectors = {"rspCard", "working"},
            border = 3,
            borderColor = "@accent",
        },
        {
            selectors = {"rspCard", "cannotAct"},
            saturation = 0.15,
            brightness = 0.5,
        },
        {
            selectors = {"rspCard", "dragging"},
            opacity = 0.6,
        },
        {
            selectors = {"rspCardPlate"},
            bgimage = true,
            bgcolor = "@bg",
            opacity = 0.85,
            cornerRadius = 8,
        },
        {
            selectors = {"rspCardName"},
            color = "@fgStrong",
        },
        {
            selectors = {"rspCardLine"},
            color = "@fgMuted",
        },
        {
            selectors = {"rspCardLine", "working"},
            color = "@accent",
        },
        {
            selectors = {"rspCardChip"},
            bgimage = true,
            bgcolor = "@bg",
            cornerRadius = 6,
            border = 1,
            borderColor = "@warning",
        },
        {
            selectors = {"rspCardChipIcon"},
            bgcolor = "@warning",
        },
        {
            selectors = {"rspCardChipText"},
            color = "@warning",
        },
        {
            selectors = {"rspCardChip", "empty"},
            borderColor = "@fgMuted",
        },
        {
            selectors = {"rspCardChipIcon", "parent:empty"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"rspCardChipText", "parent:empty"},
            color = "@fgMuted",
        },
        {
            selectors = {"rspCardButton"},
            bgimage = true,
            bgcolor = "@bg",
            opacity = 0.85,
            cornerRadius = 6,
        },
        {
            selectors = {"rspCardButton", "hover"},
            bgcolor = "@bgRaised",
        },
        {
            selectors = {"rspCardButtonIcon"},
            bgcolor = "@fg",
        },
    }

    for _, rule in ipairs(stage) do
        rules[#rules + 1] = rule
    end
    return rules
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
