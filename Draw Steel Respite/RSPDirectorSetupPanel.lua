local mod = dmhub.GetModLoading()

--- Director Step 1: the terms of the Respite, before anyone is asked to join.
RSPDirectorSetupPanel = RegisterGameType("RSPDirectorSetupPanel")

local INSTRUCTIONS = [[
### Setup

Set the terms of the Respite.

**Days Elapsed** is how much time passes. Changing it sets **Downtime Activities** to match; change that separately if the two should differ.

**Downtime Activities** is the number of downtime activities granted - one count for heroes, one for their followers. Each Downtime Activity enables a single project roll or fishing trip.

Leave **Non-participants** ticked to let characters who sit the Respite out still run downtime activities.

Offering the Respite offers players the opportunity to participate.
]]

--- One registered activity: whether it is on offer this Respite, and the
--- activity's own fields underneath. The fields are painted once and hidden
--- when the activity is switched off rather than rebuilt.
--- @param activity table an RSPActivity entry
--- @return Panel
local function BuildActivityBlock(activity)
    -- An activity with nothing to configure registers no paint function, and
    -- reading an unset field on a game type raises.
    local paint = activity:try_get("paint")
    local painted = paint ~= nil and paint() or nil

    local body = painted ~= nil and gui.Panel{
        classes = {not RSPSession.IsActivityAvailable(activity.key) and "collapsed" or nil},
        width = "100%",
        height = "auto",
        flow = "vertical",
        lmargin = RSPConstants.activityBodyIndent,
        respiteChanged = function(element)
            element:SetClass("collapsed", not RSPSession.IsActivityAvailable(activity.key))
        end,

        painted,
    } or nil

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        gui.Panel{
            classes = {"formRow"},

            gui.Check{
                classes = {"form"},
                text = activity.name,
                value = RSPSession.IsActivityAvailable(activity.key),
                respiteChanged = function(element)
                    element.value = RSPSession.IsActivityAvailable(activity.key)
                end,
                change = function(element)
                    RSPSession.SetActivityAvailable(activity.key, element.value)
                end,
            },
        },

        body,
    }
end

--- Every registered activity, alphabetical, in a region of its own so a long
--- list scrolls rather than pushing the step out of the window.
--- @return Panel
local function BuildActivityArea()
    local children = {}

    -- Reading an unset global raises. A client that never loaded the registry
    -- still gets a working step, just with nothing on offer.
    local registry = rawget(_G, "RSPActivity")
    if registry ~= nil then
        for _, activity in ipairs(registry.All()) do
            children[#children + 1] = BuildActivityBlock(activity)
        end
    end

    return gui.Panel{
        width = "100%",
        height = RSPConstants.activityAreaHeight,
        flow = "vertical",
        halign = "left",
        valign = "top",
        vscroll = true,
        children = children,
    }
end

--- @return Panel
local function BuildWorkingArea()
    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        RSPWidgets.FormRow("Location", gui.Input{
            classes = {"input", "form"},
            width = RSPConstants.locationWidth,
            height = 22,
            halign = "left",
            valign = "center",
            editlag = 0.5,
            text = RSPSession.Location(),

            --Every step is built up front, so this only takes focus when Setup
            --is the one on screen. Delayed because focus does not stick until
            --the window has laid out.
            create = function(element)
                dmhub.Schedule(0.2, function()
                    if not element.valid then
                        return
                    end

                    local session = RSPSession.Active()
                    local phase = session ~= nil and session.phase
                        or RSPConstants.phaseSetup
                    if phase == RSPConstants.phaseSetup then
                        gui.SetFocus(element)
                    end
                end)
            end,

            edit = function(element)
                element:FireEvent("change")
            end,

            change = function(element)
                if element.text ~= RSPSession.Location() then
                    RSPSession.SetLocation(element.text)
                end
            end,

            --Left alone while it holds what the session holds, so a refresh
            --mid-edit cannot take the caret out from under the Director.
            respiteChanged = function(element)
                local location = RSPSession.Location()
                if element.text ~= location then
                    element.text = location
                end
            end,
        }),

        RSPWidgets.FormRow("# Days Elapsed", RSPWidgets.Stepper{
            get = RSPSession.DaysElapsed,
            set = RSPSession.SetDaysElapsed,
            min = RSPConstants.daysMin,
            max = RSPConstants.daysMax,
        }),

        --Two allowances side by side. The linkage - followers tracks heroes
        --while the two match - lives in the session setters, not here.
        RSPWidgets.FormRow("# Downtime Activities", gui.Panel{
            width = 261,
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",

            RSPWidgets.Stepper{
                label = "HEROES",
                get = RSPSession.ActivityCount,
                set = RSPSession.SetActivityCount,
                min = RSPConstants.activitiesMin,
                max = RSPConstants.activitiesMax,
            },

            RSPWidgets.Stepper{
                label = "FOLLOWERS",
                lmargin = 45,
                get = RSPSession.FollowerActivityCount,
                set = RSPSession.SetFollowerActivityCount,
                min = RSPConstants.activitiesMin,
                max = RSPConstants.activitiesMax,
            },
        }),

        gui.Panel{
            classes = {"formRow"},

            gui.Check{
                classes = {"form"},
                text = "Non-participants can do downtime activities",
                value = RSPSession.NonParticipantsMayAct(),
                respiteChanged = function(element)
                    element.value = RSPSession.NonParticipantsMayAct()
                end,
                change = function(element)
                    RSPSession.SetNonParticipantsMayAct(element.value)
                end,
            },
        },

        gui.Label{
            classes = {"sizeXl", "bold", "fg"},
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = RSPConstants.activityHeaderTopMargin,
            bmargin = RSPConstants.activityHeaderBottomMargin,
            text = "Available Activities",
        },

        BuildActivityArea(),
    }
end

--- Build the Setup step.
--- @param onOffer fun() invoked when the Director offers the Respite
--- @param onClose fun() dismisses the window
--- @return table step args for RSPShell
function RSPDirectorSetupPanel.Step(onOffer, onClose)
    return {
        phase = RSPConstants.phaseSetup,
        orientation = RSPConstants.orientSide,
        instructions = INSTRUCTIONS,
        working = BuildWorkingArea(),

        footerLeft = gui.Button{
            classes = {"sizeL"},
            text = "Close",
            halign = "left",
            valign = "center",
            press = function()
                onClose()
            end,
        },

        footerRight = gui.Button{
            classes = {"sizeL"},
            text = "Offer Respite",
            halign = "right",
            valign = "center",
            press = function()
                onOffer()
            end,
        },
    }
end
