local mod = dmhub.GetModLoading()

--- Director Step 3: the Respite in progress, and how far along everyone is.
RSPDirectorActPanel = {}

local INSTRUCTIONS = [[
### Activities

The Respite is under way. Each hero is marked complete once their player is finished.

Completing the Respite closes it for everyone.
]]

--- The heroes this Respite covers. Followers do not appear here: the hero is
--- the unit of completion.
--- @return string[] charids
local function Roster()
    return RSPSession.CoveredHeroes(RSPSession.Roster())
end

--- Every row here is a hero, so every row carries a completion state.
--- @param charid string
--- @return boolean
local function Completion(charid)
    return RSPSession.IsDone(charid)
end

--- @return Panel
local function BuildWorkingArea()
    -- Which hero the Director is looking at. One viewer's state, so it stays
    -- on the panel rather than in the document. The highlight follows the
    -- selection, never the completion: that is the icon's job.
    local list

    list = RSPWidgets.CharacterList{
        roster = Roster(),
        rolls = RSPSession.CombinedRolls,
        status = Completion,

        highlight = function(charid)
            return list ~= nil and list.data.selected == charid
        end,

        click = function(charid)
            if list ~= nil and list.valid then
                list.data.selected = charid
                list:FireEventTree("respiteChanged")
            end
        end,
    }

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

            list,
        },

        gui.Panel{
            classes = {"bordered"},
            width = RSPConstants.activityPaneWidth,
            height = "100%",
            halign = "right",
            valign = "top",

            gui.Label{
                classes = {"sizeL", "noBold", "fgMuted"},
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                text = "Activities Tracked Here",
            },
        },
    }
end

--- @return string
local function CompletionCountText()
    local roster = Roster()
    local done = 0
    for _, charid in ipairs(roster) do
        if RSPSession.IsDone(charid) then
            done = done + 1
        end
    end

    if #roster > 0 and done >= #roster then
        return "All Characters Complete"
    end
    return string.format("%d/%d Characters Complete", done, #roster)
end

--- Build the Activities step.
--- @param onComplete fun() invoked when the Director finishes the Respite
--- @return table step args for RSPShell
function RSPDirectorActPanel.Step(onComplete)
    return {
        phase = RSPConstants.phaseActive,
        headerInfo = RSPWidgets.RespiteSummary,
        orientation = RSPConstants.orientTop,
        instructions = INSTRUCTIONS,
        working = BuildWorkingArea(),

        footerLeft = gui.Label{
            classes = {"sizeM", "noBold"},
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "center",
            text = CompletionCountText(),
            respiteChanged = function(element)
                element.text = CompletionCountText()
            end,
        },

        footerCenter = gui.Check{
            classes = {"form"},
            halign = "center",
            valign = "center",
            text = "Create Journal Record",
            value = RSPSession.JournalWanted(),
            respiteChanged = function(element)
                element.value = RSPSession.JournalWanted()
            end,
            change = function(element)
                RSPSession.SetJournalWanted(element.value)
            end,
        },

        footerRight = gui.Button{
            classes = {"sizeL"},
            text = "Complete Respite",
            halign = "right",
            valign = "center",
            press = function()
                onComplete()
            end,
        },
    }
end
