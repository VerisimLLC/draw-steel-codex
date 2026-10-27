local mod = dmhub.GetModLoading()

--- Player Step 2: doing the downtime, and saying when you are finished.
--- @class RSPPlayerActPanel: GameType
--- @field new fun(o?: table): RSPPlayerActPanel
RSPPlayerActPanel = RegisterGameType("RSPPlayerActPanel")

local INSTRUCTIONS = [[
### Downtime Activities

The Respite is underway. Spend your downtime, then mark your hero complete.
You may also open your character sheet to make changes there, like changing your kit.
If you lose this window, you can open it again with Game -> Respite.
]]

--- This player's covered heroes, each with its followers beneath it. A hero
--- the non-participants setting excluded still appears when they have
--- followers, since followers may always act.
--- @return table[] entries
local function Entries()
    return RSPSession.ActingEntries(RSPSession.MyCharacters())
end

--- The activities this Respite is offering, alphabetical. An activity the
--- Director switched off is not on the menu.
--- @return table[] activities
local function AvailableActivities()
    local result = {}

    -- Reading an unset global raises, and a client without the registry
    -- simply has nothing to offer.
    local registry = rawget(_G, "RSPActivity")
    if registry ~= nil then
        for _, activity in ipairs(registry.All()) do
            if RSPSession.IsActivityAvailable(activity.key) then
                result[#result + 1] = activity
            end
        end
    end

    return result
end

--- Where the player actually spends their downtime. The activity picker sits
--- on the first row and the chosen activity fills everything under it; the
--- picker hides itself when the Respite offers nothing to choose between.
--- @param selection fun(): table|nil the {charid, owner} entry in the list
--- @return Panel
local function BuildActivityPane(selection)
    local body
    local picker
    local dropdown

    local function Activities()
        return AvailableActivities()
    end

    local function Options()
        local options = {}
        for _, activity in ipairs(Activities()) do
            options[#options + 1] = {id = activity.key, text = activity.name}
        end
        return options
    end

    --- @param key string|nil
    --- @return string
    local function NameFor(key)
        for _, activity in ipairs(Activities()) do
            if activity.key == key then
                return activity.name
            end
        end
        return ""
    end

    local function FirstKey()
        local activities = Activities()
        return #activities > 0 and activities[1].key or ""
    end

    --- @param key string|nil an activity key
    --- @return table|nil
    local function ActivityFor(key)
        for _, activity in ipairs(Activities()) do
            if activity.key == key then
                return activity
            end
        end
        return nil
    end

    -- The activity owns everything below the picker. It is rebuilt only when
    -- the pairing of activity and character actually changes: the activity
    -- paints its own contents and keeps them current from there.
    body = gui.Panel{
        width = "98%",
        height = RSPConstants.activityBodyHeight,
        flow = "vertical",
        halign = "center",
        valign = "top",

        data = {
            activityKey = nil,
            charid = nil,
        },

        showActivity = function(element, key)
            local entry = selection()
            local charid = entry ~= nil and entry.charid or nil

            if element.data.activityKey == key and element.data.charid == charid then
                return
            end

            element.data.activityKey = key
            element.data.charid = charid

            local activity = ActivityFor(key)
            local paint = activity ~= nil and activity:try_get("paintPlayer") or nil

            if paint == nil or entry == nil then
                element.children = {
                    gui.Label{
                        classes = {"sizeL", "noBold", "fgMuted"},
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        valign = "center",
                        tmargin = 24,
                        text = entry == nil and "Select one of your characters."
                            or "No activities available.",
                    },
                }
                return
            end

            element.children = {
                paint{charid = entry.charid, owner = entry.owner, roster = RSPSession.Roster},
            }
        end,
    }

    dropdown = gui.Dropdown{
        classes = {"dropdown", "form"},
        halign = "left",
        lmargin = RSPConstants.activityPickerGap,
        options = Options(),
        idChosen = FirstKey(),
        change = function(element)
            ---@cast element Dropdown
            body:FireEventTree("showActivity", element.idChosen)
        end,
        create = function(element)
            ---@cast element Dropdown
            body:FireEventTree("showActivity", element.idChosen)
        end,
        -- The Director can withdraw an activity mid-Respite, so the menu is
        -- rebuilt on every change and the choice falls back to the first one
        -- still on offer.
        respiteChanged = function(element)
            element.options = Options()

            local stillOffered = NameFor(element.idChosen) ~= ""
            if not stillOffered then
                element.idChosen = FirstKey()
            end

            body:FireEventTree("showActivity", element.idChosen)
        end,
    }

    -- Straight to the sheet for whoever is selected. A hero lands on the
    -- Builder tab, since changing a kit is the usual reason to go there during
    -- a Respite; a follower has no builder, so it opens where it always does.
    local sheetButton = gui.Button{
        classes = {"sizeM"},
        icon = RSPConstants.iconCharacterSheet,
        width = RSPConstants.activitySheetButtonSize,
        height = RSPConstants.activitySheetButtonSize,
        halign = "right",
        valign = "center",
        hover = gui.Tooltip("Open character sheet"),
        press = function()
            local entry = selection()
            if entry == nil then
                return
            end

            local token = dmhub.GetCharacterById(entry.charid)
            if token == nil then
                return
            end

            if entry.owner == nil then
                token:ShowSheet(RSPConstants.sheetTabBuilder)
            else
                token:ShowSheet()
            end
        end,
    }

    -- Every registered activity's own buttons, beside the sheet button and always there like it.
    local actions = {}
    local registry = rawget(_G, "RSPActivity")
    if registry ~= nil then
        for _, activity in ipairs(registry.All()) do
            local paint = activity:try_get("playerActions")
            if paint ~= nil then
                actions[#actions + 1] = paint{
                    selection = selection,
                    host = function()
                        return body:FindParentWithClass("rspShell")
                    end,
                }
            end
        end
    end

    local actionSlot = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        rmargin = RSPConstants.activityActionGap,
        children = actions,
    }

    picker = gui.Panel{
        classes = {"formRow"},
        width = "96%",
        height = "auto",
        halign = "center",
        tmargin = 8,

        -- The form label rule carries a minWidth so labels line up down a
        -- form; this one stands alone, so it is cleared to let auto mean auto.
        gui.Label{
            classes = {"label", "form"},
            width = "auto",
            minWidth = 0,
            halign = "left",
            text = "Activity",
        },

        dropdown,
        actionSlot,
        sheetButton,
    }

    -- No padding on the pane: without border-box it would add to the declared
    -- height and push the pane down through the divider. The children inset
    -- themselves instead.
    return gui.Panel{
        classes = {"bordered"},
        width = RSPConstants.activityPaneWidth,
        height = "100%",
        flow = "vertical",
        halign = "right",
        valign = "top",

        create = function(element)
            element:FireEvent("respiteChanged")
        end,

        respiteChanged = function()
            local offered = #Activities() > 0
            picker:SetClass("collapsed", not offered)

            -- With no picker there is no band to reserve, so the body takes
            -- the pane back.
            body.height = offered and RSPConstants.activityBodyHeight or "100%"
        end,

        -- The player picked a different character, so the activity repaints
        -- for whoever that is now.
        selectionChanged = function()
            body:FireEventTree("showActivity", dropdown.idChosen)
            actionSlot:FireEventTree("rspSelectionChanged")
        end,

        picker,
        body,
    }
end

--- @return Panel
local function BuildMineArea()
    -- Which row the player is looking at. This is one player's view of their
    -- own window, not part of the Respite, so it never reaches the document.
    local list
    local pane

    --- Read fresh rather than captured: this window can be built before the
    --- Director picks participants, and the roster arrives afterwards.
    --- @return table|nil the selected {charid, owner} entry
    local function Selection()
        if list == nil or list.data.selected == nil then
            return nil
        end
        for _, entry in ipairs(Entries()) do
            if entry.charid == list.data.selected then
                return entry
            end
        end
        return nil
    end

    list = RSPWidgets.CharacterList{
        roster = Entries,

        -- A follower's rolls live on the hero it follows, so the entry's
        -- owner is what gets asked.
        rolls = function(charid, owner)
            if owner ~= nil then
                return RSPSession.FollowerRolls(owner, charid)
            end
            return RSPSession.HeroRolls(charid)
        end,

        highlight = function(charid)
            return list ~= nil and list.data.selected == charid
        end,

        -- Selecting a row says "show me this one".
        click = function(charid)
            if list ~= nil and list.valid then
                list.data.selected = charid
                list:FireEventTree("respiteChanged")
            end
            if pane ~= nil and pane.valid then
                pane:FireEvent("selectionChanged")
            end
        end,
    }

    -- Open on the first character rather than an empty pane. The player can
    -- move off it, but there is always something to look at.
    local function SelectFirst()
        if list == nil or not list.valid or list.data.selected ~= nil then
            return
        end

        local entries = Entries()
        if #entries == 0 then
            return
        end

        list.data.selected = entries[1].charid
        if pane ~= nil and pane.valid then
            pane:FireEvent("selectionChanged")
        end
    end

    SelectFirst()

    pane = BuildActivityPane(Selection)

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "top",

        gui.Panel{
            width = RSPConstants.activityListWidth,
            height = "100%",
            flow = "vertical",
            halign = "left",
            valign = "top",

            -- The roster can land after this window was built, so the opening
            -- selection is made when there is one rather than only at build.
            respiteChanged = function()
                SelectFirst()
            end,

            list,
        },

        pane,
    }
end

--- One line of the Watch record, built empty and handed its entry by position.
--- @return Panel
local function BuildRecordRow()
    local size = RSPConstants.recordPortraitSize

    -- A slot rather than the portrait itself: the image is remade only when the actor changes.
    local portrait = gui.Panel{
        width = size,
        height = size,
        halign = "left",
        valign = "center",
        rmargin = 6,
        data = {
            charid = nil,
        },
    }

    local label = gui.Label{
        classes = {"sizeS", "noBold", "fg"},
        width = "100%-" .. tostring(size + RSPConstants.eventIconSize + 12),
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = true,
        text = "",
    }

    local icon = gui.Panel{
        classes = {"hidden"},
        bgimage = RSPConstants.iconAttention,
        width = RSPConstants.eventIconSize,
        height = RSPConstants.eventIconSize,
        halign = "left",
        valign = "center",
        lmargin = 6,
        data = {
            image = RSPConstants.iconAttention,
        },
    }

    return gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        vmargin = 2,

        setEntry = function(element, entry)
            element:SetClass("collapsed", entry == nil)
            if entry == nil then
                return
            end

            if portrait.data.charid ~= entry.charid then
                portrait.data.charid = entry.charid
                local token = entry.charid ~= nil and dmhub.GetCharacterById(entry.charid) or nil
                portrait.children = token == nil and {} or {
                    gui.CreateTokenImage(token, {
                        width = size,
                        height = size,
                        halign = "center",
                        valign = "center",
                    }),
                }
            end

            local good = entry.tone == RSPConstants.toneGood
            local alert = entry.tone == RSPConstants.toneAlert

            icon:SetClass("hidden", not (good or alert))
            icon:SetClass("rspEventGood", good)
            icon:SetClass("rspEventAlert", alert)
            local image = good and RSPConstants.iconComplete or RSPConstants.iconAttention
            if icon.data.image ~= image then
                icon.data.image = image
                icon.bgimage = image
            end

            label:SetClass("success", good)
            label:SetClass("warning", alert)
            label:SetClass("fg", not (good or alert))
            if label.text ~= entry.text then
                label.text = entry.text
            end
        end,

        portrait,
        label,
        icon,
    }
end

--- The Watch view: everything the players on the Respite have done, newest first.
--- Each activity reports its own lines; the Respite only merges them by time.
--- @return Panel
local function BuildPartyRecord()
    local m_shown = false
    local rows
    local empty
    local watchers

    --- @return table[] entries newest first
    local function RecordEntries()
        local entries = {}
        local args = {
            roster = RSPSession.Roster,
            since = RSPSession.StartedAt,
        }

        for _, activity in ipairs(AvailableActivities()) do
            local record = activity:try_get("partyRecord")
            if record ~= nil then
                for _, entry in ipairs(record(args) or {}) do
                    entries[#entries + 1] = {
                        at = entry.at or 0,
                        text = string.format("%s: %s", activity.name, entry.text or ""),
                        charid = entry.charid,
                        tone = entry.tone,
                        order = #entries + 1,
                    }
                end
            end
        end

        -- Lines stamped together keep the order their activity gave them.
        table.sort(entries, function(a, b)
            if a.at ~= b.at then
                return a.at > b.at
            end
            return a.order > b.order
        end)

        return entries
    end

    --- @return string[] paths
    local function WatchPaths()
        local paths = {}
        local args = {
            roster = RSPSession.Roster,
        }

        for _, activity in ipairs(AvailableActivities()) do
            local watch = activity:try_get("partyWatch")
            if watch ~= nil then
                for _, path in ipairs(watch(args) or {}) do
                    paths[#paths + 1] = path
                end
            end
        end

        return paths
    end

    local function Bind()
        if not m_shown or rows == nil or not rows.valid then
            return
        end

        local entries = RecordEntries()
        local pool = rows.children

        if #pool < #entries then
            local grown = {}
            for i, row in ipairs(pool) do
                grown[i] = row
            end
            for i = #pool + 1, #entries do
                grown[i] = BuildRecordRow()
            end
            rows.children = grown
            pool = grown
        end

        for i, row in ipairs(pool) do
            row:FireEvent("setEntry", entries[i])
        end

        empty:SetClass("collapsed", #entries > 0)
        watchers:FireEvent("rewatch")
    end

    rows = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }

    empty = gui.Label{
        classes = {"sizeS", "noBold", "fgMuted", "collapsed"},
        width = "100%",
        height = "auto",
        halign = "left",
        tmargin = 4,
        text = "Nothing yet this Respite.",
    }

    watchers = RSPWidgets.Watchers{
        paths = WatchPaths,
        changed = Bind,
    }

    -- Scrolls inside the bordered pane for the same reason the Director's feed does.
    local scroller = gui.Panel{
        width = RSPConstants.feedScrollWidth,
        height = RSPConstants.feedScrollHeight,
        flow = "vertical",
        halign = "left",
        valign = "center",
        vscroll = true,

        gui.Panel{
            width = RSPConstants.feedSectionWidth,
            height = "auto",
            flow = "vertical",
            halign = "left",
            lmargin = RSPConstants.feedSectionInset,
            vmargin = 6,

            empty,
            rows,
        },
    }

    return gui.Panel{
        classes = {"bordered", "collapsed"},
        width = "100%",
        height = RSPConstants.feedPaneHeight,
        flow = "vertical",
        halign = "left",
        valign = "top",

        showRecord = function(element, shown)
            m_shown = shown
            element:SetClass("collapsed", not shown)
            Bind()
        end,

        respiteChanged = function()
            Bind()
        end,

        watchers,
        scroller,
    }
end

local VIEW_ACT = "act"
local VIEW_WATCH = "watch"

--- The step's working area: the Act | Watch toggle over whichever view it picks.
--- Both views are built once and the toggle collapses one, as the shell does steps.
--- @return Panel
local function BuildWorkingArea()
    local mine = BuildMineArea()
    local record = BuildPartyRecord()

    local selector = gui.EnumeratedSliderControl{
        width = RSPConstants.viewSelectorWidth,
        halign = "left",
        valign = "center",
        options = {
            {id = VIEW_ACT, text = "Act"},
            {id = VIEW_WATCH, text = "Watch"},
        },
        value = VIEW_ACT,
        change = function(element)
            local watching = element.value == VIEW_WATCH
            mine:SetClass("collapsed", watching)
            record:FireEvent("showRecord", watching)
        end,
    }

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        gui.Panel{
            width = "100%",
            height = RSPConstants.viewSelectorRowHeight,
            flow = "horizontal",
            halign = "left",
            valign = "top",

            selector,
        },

        gui.Panel{
            width = "100%",
            height = RSPConstants.viewBodyHeight,
            flow = "vertical",
            halign = "left",
            valign = "top",

            mine,
            record,
        },
    }
end

--- Build the player's Downtime Activities step.
--- @return table step args for RSPShell
function RSPPlayerActPanel.Step()
    return {
        phase = RSPConstants.phaseActive,
        headerInfo = RSPWidgets.RespiteSummary,
        orientation = RSPConstants.orientTop,
        instructions = INSTRUCTIONS,
        working = BuildWorkingArea(),

        -- Nothing sits below the working area on this step, so it runs to the
        -- bottom of the window instead of stopping at a rule.
        footerless = true,
    }
end
