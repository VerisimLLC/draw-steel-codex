local mod = dmhub.GetModLoading()

--- Director Step 2: who is taking the Respite, while the players answer.
RSPDirectorPartPanel = {}

local INSTRUCTIONS = [[
### Participants

Click a character to take them in or out of the Respite.

Players are choosing for their own characters at the same time. Their choices and yours are the same setting, so the last one made is the one that stands.

The count below tracks how many players have committed. You should probably wait for all of them.
]]

--- @return Panel
local function BuildWorkingArea()
    return RSPWidgets.CharacterList{
        roster = RSPSession.Roster(),
        highlight = RSPSession.IsParticipating,
        lock = RSPSession.IsCommittedFor,
        click = function(charid)
            RSPSession.SetParticipating(charid, not RSPSession.IsParticipating(charid))
        end,
    }
end

--- @return string
local function CommittedText()
    local committed = RSPSession.CommittedCount()
    local total = RSPSession.ConnectedPlayerCount()
    if committed >= total then
        return "All Players Committed"
    end
    return string.format("%d/%d Players Committed", committed, total)
end

--- @return Panel
local function BuildCommittedLabel()
    return gui.Label{
        classes = {"sizeM", "noBold"},
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        text = CommittedText(),
        respiteChanged = function(element)
            element.text = CommittedText()
        end,
    }
end

--- Build the Participants step.
--- @param onStart fun() invoked when the Director starts the Respite
--- @return table step args for RSPShell
function RSPDirectorPartPanel.Step(onStart)
    return {
        phase = RSPConstants.phaseOffered,
        headerInfo = RSPWidgets.RespiteSummary,
        orientation = RSPConstants.orientSide,
        instructions = INSTRUCTIONS,
        working = BuildWorkingArea(),

        footerLeft = gui.Button{
            classes = {"sizeL"},
            text = "Back",
            halign = "left",
            valign = "center",
            press = function()
                RSPSession.ReturnToSetup()
            end,
        },

        footerCenter = BuildCommittedLabel(),

        footerRight = gui.Button{
            classes = {"sizeL"},
            text = "Start Respite",
            halign = "right",
            valign = "center",
            press = function()
                onStart()
            end,
        },
    }
end
