local mod = dmhub.GetModLoading()

--- Player Step 2: doing the downtime, and saying when you are finished.
RSPPlayerActPanel = RegisterGameType("RSPPlayerActPanel")

local INSTRUCTIONS = [[
### Downtime Activities

The Respite is underway. Spend your downtime, then mark your hero complete.
You may also open your character sheet to make changes there, like changing your kit.
If you lose this window, you can open it again with Game -> Respite.
]]

--- This player's covered heroes, each with its followers beneath it.
--- @return table[] entries
local function Entries()
    local heroes = RSPSession.CoveredHeroes(RSPSession.MyCharacters())
    return RSPSession.EntriesWithFollowers(heroes)
end

--- Only heroes carry a completion state, so a follower's row shows no icon.
--- @param charid string
--- @return boolean|nil
local function Completion(charid)
    if not RSPSession.IsHeroInRespite(charid) then
        return nil
    end
    return RSPSession.IsDone(charid)
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
                            or string.format("%s goes here", NameFor(key)),
                    },
                }
                return
            end

            element.children = {
                paint{charid = entry.charid, owner = entry.owner},
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
            body:FireEventTree("showActivity", element.idChosen)
        end,
        create = function(element)
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
        end,

        picker,
        body,
    }
end

--- @return Panel
local function BuildWorkingArea()
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
        status = Completion,

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

        -- Selecting a row says "show me this one"; the icon is what marks
        -- work finished, and it swallows its own press so the two never
        -- collide.
        click = function(charid)
            if list ~= nil and list.valid then
                list.data.selected = charid
                list:FireEventTree("respiteChanged")
            end
            if pane ~= nil and pane.valid then
                pane:FireEvent("selectionChanged")
            end
        end,

        statusClick = function(charid)
            if RSPSession.IsHeroInRespite(charid) then
                RSPSession.SetDone(charid, not RSPSession.IsDone(charid))
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
