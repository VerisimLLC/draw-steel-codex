local mod = dmhub.GetModLoading()

--- The player's view of a running Respite: a full-screen stage after the
--- Encounter of the Week montage. The player's characters are cards along the
--- bottom, each activity on offer is a station in the middle, and the party's
--- record runs down the right. Dropping a card on a station hands the middle
--- to that activity for that character until they are done there.
--- @class RSPPlayerActPanel: GameType
--- @field new fun(o?: table): RSPPlayerActPanel
RSPPlayerActPanel = RegisterGameType("RSPPlayerActPanel")

local HELP = "Drag one of your characters onto an activity to begin, or click the character and then the activity.\n\n"
    .. "You can leave an activity once what you started there is finished.\n\n"
    .. "The button on a hero's card opens their character sheet, for example to change a kit.\n\n"
    .. "Step Away hides this screen. Return to Respite, or Game > Respite, brings it back."

local HINT = "Drag one of your characters onto an activity, or click a character and then an activity."

--- The stage on this client, while there is one.
local m_stage = nil

--- The action bar draws over everything, so the stage hides it while it is up
--- and puts back whatever the player had.
local m_holdsActionBar = false
local m_actionBarRestore = false

--- @param hold boolean
--- @param wasShown nil|boolean the bar's value is a stage left over from a reload, not the player's
local function HoldActionBar(hold, wasShown)
    if hold == m_holdsActionBar then
        return
    end
    m_holdsActionBar = hold
    if hold then
        m_actionBarRestore = not wasShown and dmhub.GetSettingValue("hideactionbar") or false
        dmhub.SetSettingValue("hideactionbar", true)
    else
        dmhub.SetSettingValue("hideactionbar", m_actionBarRestore or false)
    end
end

--- @return boolean
local function RespiteRunning()
    local session = RSPSession.Active()
    return session ~= nil and session.phase == RSPConstants.phaseActive
end

--- This player's covered heroes, each with its followers beneath it.
--- @return table[] entries {charid, indent, owner}
local function Entries()
    return RSPSession.ActingEntries(RSPSession.MyCharacters())
end

--- The activities this Respite is offering, alphabetical.
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

--- @param charid string
--- @param owner string|nil
--- @return number
local function Rolls(charid, owner)
    if owner ~= nil then
        return RSPSession.FollowerRolls(owner, charid)
    end
    return RSPSession.HeroRolls(charid)
end

--- A hero the non-participants rule leaves out still shows, for their followers.
--- @param charid string
--- @return boolean
local function Resting(charid)
    return #RSPSession.CoveredHeroes({charid}) > 0
end

--- The activity holding this character until they finish there, and why.
--- @param charid string
--- @param owner string|nil
--- @return table|nil activity, string|nil reason
local function BusyIn(charid, owner)
    for _, activity in ipairs(AvailableActivities()) do
        local busy = activity:try_get("busy")
        if busy ~= nil then
            local held, reason = busy{charid = charid, owner = owner}
            if held then
                return activity, reason
            end
        end
    end
    return nil, nil
end

--- @param charid string
--- @return string
local function NameOf(charid)
    local token = dmhub.GetCharacterById(charid)
    return token ~= nil and token.name or ""
end

--- One line of the Party Record, built empty and handed its entry by position.
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

    -- The activity's own picture for the line (a fish, say), when it gives one.
    local art = gui.Panel{
        classes = {"collapsed"},
        width = RSPConstants.recordArtSize,
        height = RSPConstants.recordArtSize,
        halign = "left",
        valign = "center",
        rmargin = 6,
        data = {
            image = nil,
            color = nil,
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
        vmargin = 3,

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

            -- Untinted pictures take the theme's text colour.
            local hasArt = entry.icon ~= nil
            art:SetClass("collapsed", not hasArt)
            if hasArt then
                if art.data.image ~= entry.icon then
                    art.data.image = entry.icon
                    art.bgimage = entry.icon
                end
                local color = entry.iconColor or ThemeEngine.ResolveTokens("@fg")
                if art.data.color ~= color then
                    art.data.color = color
                    art.selfStyle.bgcolor = color
                end
            end

            local taken = size + RSPConstants.eventIconSize + 12
            if hasArt then
                taken = taken + RSPConstants.recordArtSize + 6
            end
            label.selfStyle.width = "100%-" .. tostring(taken)

            label:SetClass("success", good)
            label:SetClass("warning", alert)
            label:SetClass("fg", not (good or alert))
            if label.text ~= entry.text then
                label.text = entry.text
            end
        end,

        portrait,
        art,
        label,
        icon,
    }
end

--- The Party Record: everything the players on the Respite have done, newest
--- first. Each activity reports its own lines; the Respite only merges them.
--- @return Panel
local function BuildPartyRecord()
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
                        icon = entry.icon,
                        iconColor = entry.iconColor,
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
        if rows == nil or not rows.valid then
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

    return gui.Panel{
        classes = {"rspStagePanel"},
        width = RSPConstants.stageWatchWidth,
        height = "100%",
        flow = "vertical",
        halign = "right",
        valign = "top",

        create = function()
            Bind()
        end,

        respiteChanged = function()
            Bind()
        end,

        watchers,

        gui.Label{
            classes = {"sizeL", "bold", "fgStrong"},
            width = "100%-24",
            height = "auto",
            halign = "center",
            tmargin = 12,
            bmargin = 6,
            text = "Party Record",
        },

        gui.Panel{
            width = "100%-8",
            height = "100% available",
            flow = "vertical",
            halign = "center",
            valign = "top",
            bmargin = 8,
            vscroll = true,

            gui.Panel{
                width = "100%-24",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",
                lmargin = 8,

                empty,
                rows,
            },
        },
    }
end

--- @param image string|nil
--- @return boolean whether the stage can show it: a still, since a video
--- would play once and go blank
local function UsableStill(image)
    return image ~= nil and image ~= "" and not FullscreenDisplay.IsVideo(image)
end

--- The art behind the stage, cropped to cover: what the Director chose at
--- Setup, else the campaign's own cover art.
--- @return Panel
local function BuildBackdrop()
    local image = RSPSession.Backdrop()
    if not UsableStill(image) then
        image = game.coverart
    end
    if not UsableStill(image) then
        image = RSPConstants.stageFallbackArt
    end

    --- Cover the parent, cropping whichever way the art overflows.
    --- @param element Panel
    local function Fit(element)
        local sprite = element.bgsprite
        local parent = element.parent
        if sprite == nil or parent == nil then
            return
        end

        local imageAspect = sprite.dimensions.y / sprite.dimensions.x
        local w = parent.renderedWidth
        local h = parent.renderedHeight
        if imageAspect <= 0 or w == 0 or h == 0 then
            return
        end

        if h / w > imageAspect then
            element.selfStyle.height = "100%"
            element.selfStyle.width = string.format("%f%% height", 100 / imageAspect)
        else
            element.selfStyle.width = "100%"
            element.selfStyle.height = string.format("%f%% width", 100 * imageAspect)
        end
    end

    return gui.Panel{
        classes = {"image"},
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = image,
        bgcolor = "white",
        interactable = false,
        imageLoaded = Fit,
        screenResized = function(element)
            element:ScheduleEvent("imageLoaded", 0.5)
        end,
    }
end

--- @param activity table
--- @return Panel
local function DefaultStationContent(activity)
    return gui.Label{
        classes = {"sizeXl", "bold", "fgStrong"},
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        text = activity.name,
    }
end

--- Build the stage. Everything here is one player's view and never reaches a
--- document: who is selected, who is inside which activity.
--- @return Panel root
local function BuildStage()
    local root
    local content
    local scaler
    local stations
    local work
    local strip

    -- Who was clicked and is waiting for a station, who is being dragged, and
    -- who is inside an activity: {charid, owner} entries, plus the key there.
    local m_selected = nil
    local m_dragging = nil
    local m_working = nil

    local function Broadcast()
        if root ~= nil and root.valid then
            root:FireEventTree("stageChanged")
        end
    end

    --- May this character go into this activity (any activity, when key is nil)?
    --- @param charid string
    --- @param owner string|nil
    --- @param key string|nil
    --- @return boolean
    local function CanEnter(charid, owner, key)
        if m_working ~= nil then
            return false
        end
        if owner == nil and not Resting(charid) then
            return false
        end

        -- Part way through something: back into that, and only that.
        local held = BusyIn(charid, owner)
        if held ~= nil then
            return key == nil or held.key == key
        end

        return Rolls(charid, owner) > 0
    end

    --- @param key string
    --- @return table|nil
    local function ActivityFor(key)
        for _, activity in ipairs(AvailableActivities()) do
            if activity.key == key then
                return activity
            end
        end
        return nil
    end

    --- @param charid string
    --- @param owner string|nil
    --- @param key string
    local function Enter(charid, owner, key)
        local activity = ActivityFor(key)
        if activity == nil or not CanEnter(charid, owner, key) then
            return
        end

        m_selected = nil
        m_dragging = nil
        m_working = {charid = charid, owner = owner, key = key}

        stations:SetClass("collapsed", true)
        work:SetClass("collapsed", false)
        work:FireEvent("open", activity, charid, owner)
        Broadcast()
    end

    local function Exit()
        if m_working == nil then
            return
        end
        if BusyIn(m_working.charid, m_working.owner) ~= nil then
            return
        end

        m_working = nil
        work:SetClass("collapsed", true)
        work:FireEvent("close")
        stations:SetClass("collapsed", false)
        Broadcast()
    end

    --- The character a station would take right now: dragged, else clicked.
    --- @return table|nil
    local function Offered()
        return m_dragging or m_selected
    end

    -- One tile per activity on offer. The Director sets the menu before the
    -- Respite starts, so the tiles are built once.
    local tiles = {}
    for _, activity in ipairs(AvailableActivities()) do
        local paint = activity:try_get("paintStation")
        local painted = paint ~= nil and paint{roster = RSPSession.Roster} or DefaultStationContent(activity)

        local hint = gui.Label{
            classes = {"rspStationHint", "sizeS", "bold", "hidden"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "bottom",
            bmargin = 10,
            floating = true,
            interactable = false,
            text = "Drop here",
        }

        tiles[#tiles + 1] = gui.Panel{
            classes = {"rspStation"},
            width = RSPConstants.stationWidth,
            height = RSPConstants.stationHeight,
            halign = "center",
            valign = "center",
            hmargin = RSPConstants.stationGap / 2,
            vmargin = RSPConstants.stationGap / 2,
            flow = "vertical",
            dragTarget = true,
            dragTargetPriority = 10,
            data = {
                key = activity.key,
            },

            press = function()
                local offered = m_selected
                if offered ~= nil then
                    Enter(offered.charid, offered.owner, activity.key)
                end
            end,

            stageChanged = function(element)
                local offered = Offered()
                local droppable = offered ~= nil and CanEnter(offered.charid, offered.owner, activity.key)
                element:SetClass("droppable", droppable)
                hint:SetClass("hidden", not droppable)
            end,

            gui.Panel{
                width = "100%-24",
                height = "100%-40",
                flow = "vertical",
                halign = "center",
                valign = "top",
                tmargin = 12,
                interactable = false,

                painted,
            },

            hint,
        }
    end

    if #tiles == 0 then
        tiles[1] = gui.Label{
            classes = {"sizeL", "fgMuted"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            text = "This Respite offers no activities.",
        }
    end

    stations = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "center",
        valign = "top",

        -- On a plate of its own: plain text could vanish into the backdrop, and
        -- the engine's text outline draws as a plate anyway.
        gui.Panel{
            classes = {"rspHintPlate"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "top",
            tmargin = 12,
            hpad = 16,
            vpad = 6,

            gui.Label{
                classes = {"sizeM", "fgStrong"},
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                text = HINT,
            },
        },

        gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "horizontal",
            wrap = true,
            halign = "center",
            valign = "center",
            children = tiles,
        },
    }

    -- The activity's own space, with the way out across its top.
    local workTitle = gui.Label{
        classes = {"sizeL", "bold", "fgStrong"},
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        text = "",
    }

    -- The arrow is its own child, hard left, as the roll dialog's Re-roll
    -- carries its cost glyph: the theme's button icon is for icon-only buttons.
    local backButton = gui.Button{
        classes = {"sizeM"},
        text = "Back",
        width = 120,
        halign = "left",
        valign = "center",
        lmargin = 8,
        data = {
            enabled = true,
            tip = nil,
        },
        hover = function(element)
            if element.data.tip ~= nil then
                gui.Tooltip(element.data.tip)(element)
            end
        end,
        refreshExit = function(element)
            local held, reason = nil, nil
            if m_working ~= nil then
                held, reason = BusyIn(m_working.charid, m_working.owner)
            end
            element.data.enabled = held == nil
            element:SetClass("disabled", held ~= nil)
            element.data.tip = held ~= nil and (reason or "Finish what you started here first.") or nil
        end,
        press = function(element)
            if element.data.enabled then
                Exit()
            end
        end,

        gui.Panel{
            classes = {"rspBackIcon"},
            bgimage = RSPConstants.iconBack,
            width = 18,
            height = 18,
            halign = "left",
            valign = "center",
            lmargin = 10,
            interactable = false,
        },
    }

    -- Whoever is doing the activity, at the right of the title bar. The token
    -- is a slot, remade only when the actor changes.
    local actorToken = gui.Panel{
        width = RSPConstants.workActorTokenSize,
        height = RSPConstants.workActorTokenSize,
        halign = "right",
        valign = "center",
        data = {
            charid = nil,
        },
    }

    local actorName = gui.Label{
        classes = {"sizeL", "bold", "fgStrong"},
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        rmargin = 8,
        text = "",
    }

    local actor = gui.Panel{
        width = "auto",
        height = "100%",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        rmargin = 12,

        actorName,
        actorToken,
    }

    local workBody = gui.Panel{
        width = "100%-24",
        height = "100% available",
        flow = "vertical",
        halign = "center",
        valign = "top",
        bmargin = 12,
    }

    -- Whatever moves the activity can move whether its character may leave.
    local function WorkWatchPaths()
        local paths = {}
        if m_working ~= nil then
            local holder = dmhub.GetCharacterById(m_working.owner or m_working.charid)
            if holder ~= nil then
                paths[#paths + 1] = holder.monitorPath
            end
        end
        for _, activity in ipairs(AvailableActivities()) do
            local watch = activity:try_get("partyWatch")
            if watch ~= nil then
                for _, path in ipairs(watch{roster = RSPSession.Roster} or {}) do
                    paths[#paths + 1] = path
                end
            end
        end
        return paths
    end

    local workWatchers = RSPWidgets.Watchers{
        paths = WorkWatchPaths,
        changed = function()
            if backButton.valid then
                backButton:FireEvent("refreshExit")
            end
        end,
    }

    work = gui.Panel{
        classes = {"rspStagePanel", "collapsed"},
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "center",
        valign = "top",

        open = function(element, activity, charid, owner)
            workTitle.text = activity.name
            actorName.text = NameOf(charid)

            if actorToken.data.charid ~= charid then
                actorToken.data.charid = charid
                local token = dmhub.GetCharacterById(charid)
                local size = RSPConstants.workActorTokenSize
                actorToken.children = token == nil and {} or {
                    gui.CreateTokenImage(token, {
                        width = size,
                        height = size,
                        halign = "center",
                        valign = "center",
                    }),
                }
            end

            local paint = activity:try_get("paintPlayer")
            workBody.children = {
                paint ~= nil and paint{charid = charid, owner = owner, roster = RSPSession.Roster}
                    or gui.Label{
                        classes = {"sizeL", "fgMuted"},
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        valign = "center",
                        text = "Nothing to do here.",
                    },
            }

            backButton:FireEvent("refreshExit")
            workWatchers:FireEvent("rewatch")
        end,

        close = function()
            workBody.children = {}
        end,

        respiteChanged = function()
            backButton:FireEvent("refreshExit")
        end,

        workWatchers,

        gui.Panel{
            width = "100%",
            height = RSPConstants.workHeaderHeight,
            flow = "none",
            halign = "center",
            valign = "top",
            tmargin = 6,

            backButton,
            workTitle,
            actor,
        },

        workBody,
    }

    --- The cards, rebuilt only when the household itself changes.
    --- @return string
    local function StripSignature()
        local parts = {}
        for _, entry in ipairs(Entries()) do
            parts[#parts + 1] = entry.charid
        end
        return table.concat(parts, ",")
    end

    --- The playerActions buttons for one hero's card.
    --- @param heroId string
    --- @return Panel[]
    local function HeroActions(heroId)
        local actions = {}
        local registry = rawget(_G, "RSPActivity")
        if registry == nil then
            return actions
        end
        for _, activity in ipairs(registry.All()) do
            local paint = activity:try_get("playerActions")
            if paint ~= nil then
                actions[#actions + 1] = paint{
                    selection = function()
                        return {charid = heroId}
                    end,
                    host = function()
                        return content
                    end,
                }
            end
        end
        return actions
    end

    local function BuildCards()
        local cards = {}
        local first = true

        for _, entry in ipairs(Entries()) do
            local card = RSPWidgets.StageCard{
                charid = entry.charid,
                owner = entry.owner,
                canAct = function(charid, owner)
                    return CanEnter(charid, owner, nil)
                end,
                resting = Resting,
                selected = function(charid)
                    return m_selected ~= nil and m_selected.charid == charid
                end,
                working = function(charid)
                    if m_working == nil or m_working.charid ~= charid then
                        return nil
                    end
                    local activity = ActivityFor(m_working.key)
                    return activity ~= nil and activity.name or nil
                end,
                rolls = Rolls,
                click = function(charid, owner)
                    if not CanEnter(charid, owner, nil) then
                        return
                    end
                    if m_selected ~= nil and m_selected.charid == charid then
                        m_selected = nil
                    else
                        m_selected = {charid = charid, owner = owner}
                    end
                    Broadcast()
                end,
                beginDrag = function(charid, owner)
                    m_selected = nil
                    m_dragging = {charid = charid, owner = owner}
                    Broadcast()
                end,
                canDragOnto = function(charid, owner, target)
                    return target:HasClass("rspStation") and CanEnter(charid, owner, target.data.key)
                end,
                drop = function(charid, owner, target)
                    m_dragging = nil
                    if target ~= nil and target:HasClass("rspStation") then
                        Enter(charid, owner, target.data.key)
                    else
                        Broadcast()
                    end
                end,
                sheet = function(charid)
                    local token = dmhub.GetCharacterById(charid)
                    if token ~= nil then
                        token:ShowSheet(RSPConstants.sheetTabBuilder)
                    end
                end,
                actions = entry.owner == nil and HeroActions(entry.charid) or nil,
            }

            if card ~= nil then
                -- A gap between households, so followers read as their hero's.
                if entry.owner == nil and not first then
                    card.selfStyle.lmargin = RSPConstants.cardHouseholdGap
                end
                first = false
                cards[#cards + 1] = card
            end
        end

        if #cards == 0 then
            cards[1] = gui.Label{
                classes = {"sizeM", "fgMuted"},
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                text = "You have no characters on this Respite.",
            }
        end

        return cards
    end

    local cardRow = gui.Panel{
        width = "auto",
        height = "100%",
        flow = "horizontal",
        halign = "center",
        valign = "bottom",
        data = {
            signature = StripSignature(),
        },
        children = BuildCards(),
    }

    local function RebuildStripIfMoved()
        if not cardRow.valid then
            return
        end
        local signature = StripSignature()
        if signature ~= cardRow.data.signature then
            cardRow.data.signature = signature
            cardRow.children = BuildCards()
        end
    end

    -- Gaining or losing a follower writes the hero's token and nothing else.
    local heroWatchers = RSPWidgets.Watchers{
        paths = function()
            local paths = {}
            for _, charid in ipairs(RSPSession.MyCharacters()) do
                local token = dmhub.GetCharacterById(charid)
                if token ~= nil then
                    paths[#paths + 1] = token.monitorPath
                end
            end
            return paths
        end,
        changed = RebuildStripIfMoved,
    }

    -- Layered rather than a row, so the cards centre in the width beside the
    -- Party Record whatever the watchers alongside them take.
    strip = gui.Panel{
        width = "100%",
        height = RSPConstants.stageStripHeight,
        flow = "none",
        halign = "center",
        valign = "bottom",
        tmargin = RSPConstants.stageGutter,

        respiteChanged = function()
            RebuildStripIfMoved()
            heroWatchers:FireEvent("rewatch")
        end,

        heroWatchers,
        cardRow,
    }

    local summary = gui.Label{
        classes = {"sizeS", "noBold", "fg"},
        width = "auto",
        maxWidth = 900,
        height = "auto",
        halign = "center",
        valign = "center",
        markdown = true,
        textWrap = true,
        text = RSPWidgets.RespiteSummary(),
        respiteChanged = function(element)
            element.text = RSPWidgets.RespiteSummary()
        end,
    }

    local header = gui.Panel{
        classes = {"rspStageBand"},
        width = "100%",
        height = RSPConstants.stageHeaderHeight,
        flow = "none",
        halign = "center",
        valign = "top",
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},

        gui.Panel{
            width = "auto",
            height = "100%",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            lmargin = 20,

            gui.Panel{
                classes = {"rspStageIcon"},
                bgimage = RSPConstants.icon,
                width = 32,
                height = 32,
                valign = "center",
                rmargin = 10,
            },
            gui.Label{
                classes = {"sizeXl", "bold", "fgStrong"},
                width = "auto",
                height = "auto",
                valign = "center",
                text = RSPConstants.panelName,
            },
        },

        summary,

        gui.Panel{
            width = "auto",
            height = "100%",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            rmargin = 20,

            gui.Panel{
                classes = {"rspStageIcon"},
                bgimage = RSPConstants.iconHelp,
                width = 24,
                height = 24,
                valign = "center",
                rmargin = 16,
                hover = gui.Tooltip(HELP),
            },
            gui.Button{
                classes = {"sizeM"},
                text = "Step Away",
                width = 140,
                valign = "center",
                press = function()
                    RSPPlayerActPanel.StepAway()
                end,
            },
        },
    }

    scaler = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "center",
        valign = "center",

        -- Laid out at its true size down to the floor, and scaled whole below it.
        fit = function(element)
            local parent = content
            local w = parent ~= nil and parent.renderedWidth or 0
            local h = parent ~= nil and parent.renderedHeight or 0
            if w == 0 or h == 0 then
                return
            end
            local scale = math.min(1, w / RSPConstants.stageMinWidth, h / RSPConstants.stageMinHeight)
            element.selfStyle.uiscale = scale
            element.selfStyle.width = w / scale
            element.selfStyle.height = h / scale
        end,

        screenResized = function(element)
            element:ScheduleEvent("fit", 0.1)
        end,

        header,

        gui.Panel{
            width = "100%-" .. tostring(RSPConstants.stageGutter * 2),
            height = "100% available",
            flow = "horizontal",
            halign = "center",
            valign = "top",
            vmargin = RSPConstants.stageGutter,

            gui.Panel{
                width = "100%-" .. tostring(RSPConstants.stageWatchWidth + RSPConstants.stageGutter),
                height = "100%",
                flow = "vertical",
                halign = "left",
                valign = "top",

                gui.Panel{
                    width = "100%",
                    height = "100% available",
                    flow = "none",
                    halign = "center",
                    valign = "top",

                    stations,
                    work,
                },

                strip,
            },

            BuildPartyRecord(),
        },
    }

    content = gui.Panel{
        classes = {"rspStage"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        swallowPress = true,

        BuildBackdrop(),

        gui.Panel{
            classes = {"rspStageDim"},
            floating = true,
            width = "100%",
            height = "100%",
            interactable = false,
        },

        scaler,
    }

    local chip = gui.Panel{
        classes = {"rspChip", "collapsed"},
        floating = true,
        width = RSPConstants.stageChipWidth,
        height = RSPConstants.stageChipHeight,
        halign = "center",
        valign = "top",
        tmargin = 8,
        flow = "horizontal",
        press = function()
            RSPPlayerActPanel.ReturnToStage()
        end,

        gui.Panel{
            classes = {"rspStageIcon"},
            bgimage = RSPConstants.icon,
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            lmargin = 12,
            interactable = false,
        },
        gui.Label{
            classes = {"sizeM", "bold", "fgStrong"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            interactable = false,
            text = "Return to Respite",
        },
    }

    local themeSub = nil

    root = gui.Panel{
        classes = {"rspStageRoot"},
        styles = ThemeEngine.MergeStyles(RSPWidgets.StageStyles()),
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        monitorGame = RSPSession.DocPath(),

        data = {
            away = false,
        },

        create = function(element)
            root = element
            themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(RSPWidgets.StageStyles())
                end
            end)
            scaler:ScheduleEvent("fit", 0.05)

            -- Someone part way through an activity, say after a reload, goes
            -- straight back into it.
            for _, entry in ipairs(Entries()) do
                local held = BusyIn(entry.charid, entry.owner)
                if held ~= nil then
                    Enter(entry.charid, entry.owner, held.key)
                    break
                end
            end
            Broadcast()
        end,

        -- After a reload the new load owns the bar; this one leaves it alone.
        destroy = function()
            if themeSub ~= nil then
                themeSub:Deregister()
                themeSub = nil
            end
            if not mod.unloaded then
                HoldActionBar(false)
            end
        end,

        -- The Respite this stage was following is over: it goes with it.
        refreshGame = function(element)
            if not RespiteRunning() then
                RSPPlayerActPanel.CloseStage()
                return
            end
            element:FireEventTree("respiteChanged")
            Broadcast()
        end,

        away = function(element, away)
            element.data.away = away
            content:SetClass("collapsed", away)
            chip:SetClass("collapsed", not away)
            HoldActionBar(not away)
        end,

        content,
        chip,
    }

    return root
end

--- @return Panel|nil
local function Layer()
    local hud = GameHud.instance
    if hud == nil then
        return nil
    end
    local layer = hud.documentsPanel
    if layer == nil or not layer.valid then
        return nil
    end
    return layer
end

--- Stages left behind by an earlier load of this file.
--- @param layer Panel
--- @return number how many there were
local function ClearOrphans(layer)
    local count = 0
    for _, child in ipairs(layer.children) do
        if child ~= m_stage and child:HasClass("rspStageRoot") then
            child:DestroySelf()
            count = count + 1
        end
    end
    return count
end

--- @return boolean the stage is up and the player has not stepped away from it
local function StageShowing()
    return m_stage ~= nil and m_stage.valid and not m_stage.data.away
end

--- Apply the takeover now: the rails swap, and the table's windows hide or
--- come back, rather than waiting for them to notice.
local function SwapRails()
    pcall(function()
        PanelDocument.RailCustomInterfaceRebuild()
    end)
    pcall(function()
        GameHud.SyncInterfaceSuppression()
    end)
end

-- The stage owns the screen while it shows, so the icon rails and the
-- table's windows go with the rest of the table: a custom interface with no
-- rail widgets of its own. pcall: an older core without the hook just
-- leaves them up.
pcall(function()
    GameHud.RegisterCustomInterface{
        id = "respite",
        active = function()
            return not dmhub.isDM and StageShowing()
        end,
        suppressRails = true,
        suppressWindows = true,
    }
end)

--- Put the stage up on this client if a Respite is running and it is not
--- already there. A stage the player stepped away from is left stepped away.
function RSPPlayerActPanel.ShowStage()
    if dmhub.isDM or not RespiteRunning() then
        return
    end
    if m_stage ~= nil and m_stage.valid then
        return
    end

    local layer = Layer()
    if layer == nil then
        return
    end
    local orphaned = ClearOrphans(layer) > 0

    m_stage = BuildStage()
    -- Kept above a maximized map window, as a presented dialog is.
    m_stage:SetClass("presentedDialog", true)
    layer:AddChild(m_stage)
    HoldActionBar(true, orphaned)
    SwapRails()
end

--- Hide the stage behind the Return to Respite chip.
function RSPPlayerActPanel.StepAway()
    if m_stage ~= nil and m_stage.valid then
        m_stage:FireEvent("away", true)
        SwapRails()
    end
end

--- Bring the stage back, putting it up first if it is not there.
function RSPPlayerActPanel.ReturnToStage()
    RSPPlayerActPanel.ShowStage()
    if m_stage ~= nil and m_stage.valid then
        m_stage:FireEvent("away", false)
        SwapRails()
    end
end

--- Take the stage down.
function RSPPlayerActPanel.CloseStage()
    local stage = m_stage
    m_stage = nil
    if stage ~= nil and stage.valid then
        stage:DestroySelf()
    end
    HoldActionBar(false)
    SwapRails()
end

--- Whether this client should be looking at the stage rather than the window.
--- @return boolean
function RSPPlayerActPanel.StageApplies()
    return not dmhub.isDM and RespiteRunning()
end

-- A reload replaces this file's state but not the stage it put up, so the
-- old one is cleared and, if the Respite is still running, built again.
dmhub.Schedule(0.5, function()
    if mod.unloaded or dmhub.isDM then
        return
    end
    if RSPPlayerActPanel.StageApplies() then
        RSPPlayerActPanel.ShowStage()
        return
    end
    local layer = Layer()
    if layer ~= nil and ClearOrphans(layer) > 0 then
        dmhub.SetSettingValue("hideactionbar", false)
    end
end)
