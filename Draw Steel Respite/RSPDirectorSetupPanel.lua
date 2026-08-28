local mod = dmhub.GetModLoading()

--- Director Step 1: the terms of the Respite, before anyone is asked to join.
RSPDirectorSetupPanel = RegisterGameType("RSPDirectorSetupPanel")

local INSTRUCTIONS = [[
### Setup

Set the terms of the Respite.

**Days Elapsed** is how much time passes. Changing it sets **Downtime Activities** to match; change that separately if the two should differ.

**Downtime Activities** is the number of downtime activities each participant and their followers will be granted. Each Downtime Activity enables a single project roll or fishing trip.

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

        RSPWidgets.FormRow("# Days Elapsed", RSPWidgets.Stepper{
            get = RSPSession.DaysElapsed,
            set = RSPSession.SetDaysElapsed,
            min = RSPConstants.daysMin,
            max = RSPConstants.daysMax,
        }),

        RSPWidgets.FormRow("# Downtime Activities", RSPWidgets.Stepper{
            get = RSPSession.ActivityCount,
            set = RSPSession.SetActivityCount,
            min = RSPConstants.activitiesMin,
            max = RSPConstants.activitiesMax,
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
