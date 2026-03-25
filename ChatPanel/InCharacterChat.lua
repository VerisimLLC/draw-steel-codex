local mod = dmhub.GetModLoading()

InCharacterChatMessage = RegisterGameType("InCharacterChatMessage")

InCharacterChatMessage.charname = false
InCharacterChatMessage.tokenid = false
InCharacterChatMessage.langid = false

function InCharacterChatMessage:GetToken()
    return dmhub.GetCharacterById(self.tokenid)
end

function InCharacterChatMessage.Render(self, message)
    local language = "Unknown"
    local langid = self.langid
    if langid then
        local langInfo = dmhub.GetTable(Language.tableName)[langid]
        if langInfo then
            language = langInfo.name
        end
    end

    local color = core.Color(message.nickColor)
    if color ~= nil and color.v < 0.5 then
        color.v = 0.5
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        lmargin = 0,
        linger = function(element)
            gui.Tooltip(DescribeServerTimestamp(message.timestamp))(element)
        end,
        gui.Label{
            width = "100%",
            height = "auto",
            lmargin = 0,
            fontSize = 14,
            halign = "left",
            text = string.format("<b>%s</b> (%s, in %s)", self.charname, message.nick, language),
            color = color.tostring,
        },
        gui.Label{
            refreshLanguages = function(element)
                local canUnderstand = (dmhub.isDM or message.userid == dmhub.userid)
                if not canUnderstand then
                    canUnderstand = creature.g_languagesKnownLocally[langid] or false
                end
                if canUnderstand then
                    element.selfStyle.fontFace = "Berling"
                else
                    element.selfStyle.fontFace = "Tengwar"
                end
            end,
            create = function(element)
                element:FireEvent("refreshLanguages")
            end,
            width = "100%",
            height = "auto",
            pad = 12,
            fontSize = 14,
            text = string.format("<i>%s</i>", self.text),
            markdown = true,
            borderWidth = 1,
            borderColor = "#888888",
            bgimage = true,
            bgcolor = "clear",
            beveledcorners = true,
            cornerRadius = 12,
        },
    }
end

Commands.RegisterMacro{
    name = "ic",
    summary = "in-character chat",
    doc = "Usage: /ic <message>\nSends a chat message as your primary character using the language system.",
    command = function(msg)
        chat.SendCustom(
            InCharacterChatMessage.new{
                channel = "chat",
                text = msg,
            }
        )
    end,
}