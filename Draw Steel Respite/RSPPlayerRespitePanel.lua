local mod = dmhub.GetModLoading()

--- Player Step 1: which of my heroes are taking the Respite, and am I done
--- saying so. The mirror of the Director's Participants step.
RSPPlayerRespitePanel = RegisterGameType("RSPPlayerRespitePanel")

local INSTRUCTIONS = [[
### Participate

Click one of your characters to take them in or out of the Respite. Including the hero in the Respite means the game's mechanics like converting Victories to XP and resetting Recoveries and Stamina will apply to them.

Heroes that do not participate in the Respite will%s be able to participate in downtime activities.

Commit to let your Director know that you're happy with your answer.
]]

local IDLE_INSTRUCTIONS = [[
### Inactive

No respite is being offered right now.

When the Director offers one, this window will fill in.
]]

--- @param charid string
--- @return string
local function ParticipationText(charid)
    if RSPSession.IsParticipating(charid) then
        return "Participating"
    end
    return "Not participating"
end

--- @return Panel
local function BuildWorkingArea()
    return RSPWidgets.CharacterList{
        roster = RSPSession.MyCharacters(),
        highlight = RSPSession.IsParticipating,
        indicator = ParticipationText,
        click = function(charid)
            RSPSession.SetParticipating(charid, not RSPSession.IsParticipating(charid))
        end,
    }
end

--- @return Panel
local function BuildCommitButton()
    return gui.Button{
        classes = {"sizeL"},
        text = RSPSession.IsCommitted(dmhub.userid) and "Uncommit" or "Commit",
        halign = "right",
        valign = "center",
        respiteChanged = function(element)
            element.text = RSPSession.IsCommitted(dmhub.userid) and "Uncommit" or "Commit"
        end,
        press = function()
            RSPSession.SetCommitted(dmhub.userid, not RSPSession.IsCommitted(dmhub.userid))
        end,
    }
end

--- What a player sees with no Respite on offer. The Game menu entry is always
--- there, so this is what it opens onto between Respites.
--- @param onClose fun() dismisses the window on this client
--- @return table step args for RSPShell
function RSPPlayerRespitePanel.IdleStep(onClose)
    return {
        phase = RSPConstants.phaseSetup,
        orientation = RSPConstants.orientSide,
        instructions = IDLE_INSTRUCTIONS,
        working = gui.Panel{
            width = "100%",
            height = "100%",
        },

        footerRight = gui.Button{
            classes = {"sizeL"},
            text = "Close",
            halign = "right",
            valign = "center",
            press = function()
                onClose()
            end,
        },
    }
end

--- Build the player's Respite step.
--- The standing copy plus a line per registered activity, so a player can see
--- what this Respite is offering before they commit.
--- @return string markdown
local function Instructions()
    local available = {}

    -- Reading an unset global raises. A client that never loaded the registry
    -- still gets a working window, just with nothing on offer.
    local registry = rawget(_G, "RSPActivity")
    if registry ~= nil then
        for _, activity in ipairs(registry.All()) do
            if RSPSession.IsActivityAvailable(activity.key) then
                available[#available + 1] = string.format("- %s", activity.name)
            end
        end
    end

    if #available == 0 then
        available[1] = "None"
    end

    -- The sentence about non-participants reads either way round, so it takes
    -- a " not" rather than being written out twice.
    local negation = RSPSession.NonParticipantsMayAct() and "" or " **not**"

    return string.format("%s\n\n**Available Activities**\n%s",
        string.format(INSTRUCTIONS, negation),
        table.concat(available, "\n"))
end

--- @return table step args for RSPShell
function RSPPlayerRespitePanel.Step()
    return {
        phase = RSPConstants.phaseOffered,
        headerInfo = RSPWidgets.RespiteSummary,
        orientation = RSPConstants.orientSide,
        instructions = Instructions,
        working = BuildWorkingArea(),

        footerRight = BuildCommitButton(),
    }
end
