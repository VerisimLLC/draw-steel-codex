--[[ 
Module: Chat Enhancements (In-Character)
Author: thc1967
Contact: @thc1967 (Dicord)

Description:
  Adds /ic command to Codex, enabling players and DM's to send chat
  messages using character names.

In-character command syntax:
  /ic message
  Sends the message to chat using your primary character's name.
  If you do not have a primary character and you're a GM, uses "Narrator"
  Otherwise, no message is sent.
  
--]]

--- Retrieves the formatted name of the user's primary character or narrator.
--- Uses the user's display color to format the name with bold and color tags.
--- @return string|nil name A formatted name string (e.g., "Alice:") or "Narrator:" if the user is a DM, or nil if no session info is available.
local function getInCharacterName()

    local function iOwnThisToken(t)
        return (
            t.ownerId == dmhub.userid or
            t.ownerId == "PARTY" or
            (dmhub.isDM and (t.ownerId or "") == "")
        )
    end

    local function iOwnMultipleTokens(selectedTokens)
        local count = 0
        for _, token in ipairs(selectedTokens or {}) do
            if iOwnThisToken(token) then
                count = count + 1
                if count >= 2 then return true end
            end
        end
        return false
    end

    local si = dmhub.GetSessionInfo(dmhub.userid)
    if si then
        -- Player or DM, 1 token selected, if we own it, use that name
        if #dmhub.selectedTokens == 1 then
            local t = dmhub.selectedTokens[1]
            if iOwnThisToken(t) then
                return ExtChatMessage.FormatColoredName(t.name .. ": ", si.displayColor.tostring)
            end
        end

        -- DM only, if multiple selections use "Horde" else zero selections therefore use "Narrator"
        if dmhub.isDM then
            if #dmhub.selectedTokens > 1 and iOwnMultipleTokens(dmhub.selectedTokens) then
                return ExtChatMessage.FormatColoredName("Horde: ", si.displayColor.tostring)
            else
                return ExtChatMessage.FormatColoredName("Narrator: ", si.displayColor.tostring)
            end
        end

        -- Player only, if I have a primaryCharacter, use its name
        if si.primaryCharacter then
            local t = dmhub.GetCharacterById(si.primaryCharacter)
            if t then
                return ExtChatMessage.FormatColoredName(t.name .. ": ", si.displayColor.tostring)
            end
        end

        -- Usage: This is always a player
        SendTitledChatMessage("Select one token to chat as or ask your Director to assign a character to you.", "IC-Chat", "#e09c9c", dmhub.userid)
    else
        ExtChatMessage.WriteDebug("IC:: UNABLE TO RETRIEVE SI!")
    end

    return nil
end

--- Sends a chat message as the user's primary character or narrator, if available.
--- Prepends the character's formatted name to the message.
--- @param args string The message content to send in-character.
local function doInCharacter(args)
    if args == nil or #args == 0 then return end

    local icName = getInCharacterName()
    if icName then
        WriteChatText(string.format("%s%s", icName, args))
    end
end

Commands.RegisterMacro{
    name = "icdeprecated",
    summary = "legacy IC chat",
    doc = "Usage: /icdeprecated <message>\nDeprecated in-character chat. Use /ic instead.",
    command = function(args)
        doInCharacter(args)
    end,
}
