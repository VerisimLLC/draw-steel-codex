--[[ 
Module: Chat Enhancements (Core)
Author: thc1967
Contact: @thc1967 (Dicord)

Description:
  Functionality for sending styled chat messages, including plain 
  and titled variants.

Public API:
  - WriteChatText(text, [recipients])
  - SendTitledChatMessage(text, title[, titleColor][, recipients])

  Parameter recipients is optional.
   - If empty, the message renders for everyone.
   - If a string, it must be a single or comma-separated list of DMHub user id's (guids)
   - If a table, it can be an array of DMHub user id's or a flag table with keys being DMHub user id's
   - If you pass something else, your message won't render for anyone
--]]

local DEBUG_MODE = false
local function writeDebug(fmt, ...)
    if DEBUG_MODE then
        print("EXTCHAT::", string.format(fmt, ...))
    end
end

local function describeSecondsAgo(secondsAgo)
    if secondsAgo < 6 then
        return "just now"
    elseif secondsAgo < 15 then
        return "a few seconds ago"
    elseif secondsAgo < 40 then
        return "seconds ago"
    elseif secondsAgo < 90 then
        return "a minute ago"
    elseif secondsAgo < 280 then
        return "a few minutes ago"
    elseif secondsAgo < 55 * 60 then
        local minutes = round(secondsAgo / 60)
        return string.format("%d minutes ago", minutes)
    elseif secondsAgo < 90 * 60 then
        return "an hour ago"
    elseif secondsAgo < 60 * 60 * 24 then
        local hours = round(secondsAgo / (60 * 60))
        return string.format("%d hours ago", hours)
    elseif secondsAgo < 2 * 60 * 60 * 24 then
        return "a day ago"
    else
        local days = round(secondsAgo / (60 * 60 * 24))
        return string.format("%d days ago", days)
    end
end

--- Checks if a given string is a valid HTML color name or hex code.
--- Accepts named colors (letters only) and hex codes like #RGB, #RRGGBB, or #RRGGBBAA.
---
--- @param color (string) The color string to validate.
--- @return (boolean) valid True if the color is a valid format; false otherwise.
local function isValidColor(color)
    if not color then return false end
    if color:match("^#%x%x%x%x?%x?%x?$") then return true end   -- #RGB or #RRGGBB or #RRGGBBAA
    if color:match("^[a-zA-Z]+$") then return true end          -- Named colors
    return false
end

--- Normalizes a recipients input into a flag table, or returns nil if result is empty.
--- @param recipients string|table|nil A comma-separated string, array of strings, flag table, or nil.
--- @return table|nil flags A flag table (keys = strings, values = true) or nil if empty or invalid.
local function normalizeRecipients(recipients)
    if not recipients then return nil end

    local flags = {}

    if type(recipients) == "string" then
        for entry in recipients:gmatch("[^,]+") do
            local trimmed = entry:match("^%s*(.-)%s*$")
            if #trimmed > 0 then
                flags[trimmed] = true
            end
        end
        return next(flags) and flags or nil
    end

    if type(recipients) == "table" then
        local isArray = true
        for k, v in pairs(recipients) do
            if type(k) ~= "number" or type(v) ~= "string" then
                isArray = false
                break
            end
        end

        if isArray then
            for _, str in ipairs(recipients) do
                if type(str) == "string" and #str > 0 then
                    flags[str] = true
                end
            end
            return next(flags) and flags or nil
        else
            return next(recipients) and recipients or nil
        end
    end

    return nil
end


--- @class ExtChatMessage
--- ExtChatMessage game type registration for simple text output to chat.
-- Used to display messages in the chat pane.
ExtChatMessage = RegisterGameType("ExtChatMessage")
ExtChatMessage.__index = ExtChatMessage

--- Writes a debug message to the debug log, if we're in debug mode
--- Suports param list like `string.format()`
--- @param fmt string Text to write
--- @param ...? string Tags for filling in the `fmt` string
function ExtChatMessage.WriteDebug(fmt, ...)
    if DEBUG_MODE and fmt and #fmt > 0 then
        writeDebug(fmt, ...)
    end
end

--- Formats a name string with HTML-like color and bold tags.
--- @param name string The name to be formatted.
--- @param color string The color code to apply (e.g., "#ff0000" for red).
--- @return string coloredName A formatted string with the name in bold and the specified color.
function ExtChatMessage.FormatColoredName(name, color)
    return string.format("<color=%s><b>%s</b></color>", color, name)
end

--- Renders the ExtChatMessage in the chat pane using a default label layout.
--- Called automatically by the chat system.
---
--- @param self (table) The ExtChatMessage instance.
--- @param message (table) The chat message context (unused here).
--- @return table|nil panel A GUI panel containing the formatted chat message or nothing if it's not for the current user.
function ExtChatMessage.Render(self, message)
    if self:try_get("recipients") == nil or self.recipients[dmhub.userid] then
        return gui.Panel {
            classes = {"chat-message-panel"},
            press = function(element)
                writeDebug("PRESS::")
            end,
            children = {
                gui.Label {
                    fontSize = "14.5",  -- match the default chat size
                    height = "auto",    -- trim vertical spacing
                    text = self.message,
                    linger = function(element)
                        if self:try_get("timestamp") and self.timestamp > 0 then
                            gui.Tooltip(describeSecondsAgo(dmhub.serverTime - self.timestamp))(element)
                        end
                    end,
                },
            },
        }
    else
        return nil
    end
end

--- Creates a new ExtChatMessage instance from raw text.
--- This is a static constructor; returns nil if the input is empty or invalid.
---
--- @param text (string) The message text to wrap into a ExtChatMessage object.
--- @param recipients? any A CSV string, table of strings, or flag table with DMHub user id's of recipients
--- @return (table|nil) instance A new ExtChatMessage instance, or nil if text is empty.
function ExtChatMessage.Create(text, recipients)
    if text and #text > 0 then
        return ExtChatMessage.new {
            recipients = normalizeRecipients(recipients),
            channel = "chat",
            message = text,
            timestamp = dmhub.serverTime,
        }
    else
        return nil
    end
end

--- Sends a ExtChatMessage to the chat, if text is provided.
--- This is a static utility method; it does not require an instance.
---
--- @param text (string) The message to send.
--- @param recipients? any A CSV string, table of strings, or flag table with DMHub user id's of recipients
function ExtChatMessage.Send(text, recipients)
    text = text and text:trim()
    if text and #text > 0 then
        writeDebug("Send(%s)", text)
        local m = ExtChatMessage.Create(text, recipients)
        if m then chat.SendCustom(m) end
    end
end

--- Sends a chat message with an optional bold title and color.
--- This is a static utility method for convenience formatting.
---
--- @param text (string) The message body to send.
--- @param title (string) The title to prefix the message.
--- @param titleColor? (string?) Optional hex or named color for the title. Ignored if too short.
--- @param recipients? any A CSV string, table of strings, or flag table with DMHub user id's of recipients
function ExtChatMessage.SendTitled(text, title, titleColor, recipients)
    text = text and text:trim()
    title = title and title:trim()
    titleColor = titleColor and titleColor:trim() or ""

    if text and #text > 0 and title and #title > 0 then
        local formattedTitle

        if isValidColor(titleColor) then
            formattedTitle = string.format("<b><color=%s>%s:</color></b> ", titleColor, title)
        else
            formattedTitle = string.format("<b>%s:</b> ", title)
        end

        local s = string.format("%s%s", formattedTitle, text)
        writeDebug("SendTitled(%s)", s)
        ExtChatMessage.Send(s, recipients)
    end
end

--- Sends a plain message to the chat pane without a title.
---
--- @param text (string) The message to send.
--- @param recipients? any A CSV string, table of strings, or flag table with DMHub user id's of recipients
function WriteChatText(text, recipients)
    ExtChatMessage.Send(text, recipients)
end

--- Sends a chat message with a bold title, optionally styled with a color.
---
--- @param text (string) The message to send.
--- @param title (string) Title to prefix the message.
--- @param titleColor? (string?) Optional color for the title (e.g. \"#ff0000\").
--- @param recipients? any A CSV string, table of strings, or flag table with DMHub user id's of recipients
function SendTitledChatMessage(text, title, titleColor, recipients)
    ExtChatMessage.SendTitled(text, title, titleColor, recipients)
end

if DEBUG_MODE then
    Commands.RegisterMacro{
        name = "corechattest",
        summary = "test chat messages",
        doc = "Usage: /corechattest\nSends test chat messages. Debug only.",
        command = function(args)
            WriteChatText("Chat Ext test message")
            SendTitledChatMessage("test titled message", "chatext", "#cc0000")
        end,
    }
end