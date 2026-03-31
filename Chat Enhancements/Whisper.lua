--[[ 
Module: Chat Enhancements (Whisper)
Author: thc1967
Contact: @thc1967 (Dicord)

Description:
  Adds /whisper and /w commands to DMHub / Codex, enabling players to
  directly message each other.

Whisper command syntax:
  /(w|whisper) recipient1[, recipient2...]: message
  Recipient list can include aliases d, director, dm, or gm to whisper all DM's
  End a recipient name with - to do a "starts with" match
  
--]]

--- Lookup table for recipient aliases that map to the GM/Director role.
local GM_ALIASES = { dm=true, gm=true, director=true, d=true }

local WHISPER_DEBUG = false
local function writeDebug(fmt, ...)
    if WHISPER_DEBUG then
        print("WHISPER::", string.format(fmt, ...))
    end
end

--- Sends a usage hint for the whisper command to the chat.
local function usage()
    SendTitledChatMessage("/w[hisper] recipient1[, recipient2...]: message", "usage", "#e09c9c", dmhub.userid)
end

--- Normalizes and sanitizes a string by removing special characters, accents, and separators.
--- Converts accented letters and symbols into their ASCII equivalents, replaces curly and other special
--- characters with standard ASCII equivalents, converts the string to lowercase, replaces various separators
--- (brackets, braces, parentheses, commas) with vertical pipe (|) characters, trims whitespace,
--- and ensures consistent formatting.
---
--- @param s string The string to sanitize.
--- @return string s The sanitized, normalized string.
--- @note This function is used to normalize and sanitize strings being compared to each other.
--- @see fuzzyMatch()
local function sanitizeString(s)

    s = s or ""
    if #s == 0 then return s end

    local replacements = {
        -- Lower-case accents
        ["\195\161"] = "a", ["\195\160"] = "a", ["\195\162"] = "a", ["\195\164"] = "a",
        ["\195\169"] = "e", ["\195\168"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
        ["\195\173"] = "i", ["\195\172"] = "i", ["\195\174"] = "i", ["\195\175"] = "i",
        ["\195\179"] = "o", ["\195\178"] = "o", ["\195\180"] = "o", ["\195\182"] = "o",
        ["\195\186"] = "u", ["\195\185"] = "u", ["\195\187"] = "u", ["\195\188"] = "u",
        ["\195\177"] = "n", ["\195\167"] = "c", ["\195\189"] = "y",

        -- Upper-case accents
        ["\195\129"] = "A", ["\195\128"] = "A", ["\195\130"] = "A", ["\195\132"] = "A",
        ["\195\137"] = "E", ["\195\136"] = "E", ["\195\138"] = "E", ["\195\139"] = "E",
        ["\195\141"] = "I", ["\195\140"] = "I", ["\195\142"] = "I", ["\195\143"] = "I",
        ["\195\147"] = "O", ["\195\146"] = "O", ["\195\148"] = "O", ["\195\150"] = "O",
        ["\195\154"] = "U", ["\195\153"] = "U", ["\195\155"] = "U", ["\195\156"] = "U",
        ["\195\145"] = "N", ["\195\135"] = "C", ["\195\157"] = "Y",

        -- Ligatures
        ["\195\134"] = "AE", ["\195\166"] = "ae",

        -- Icelandic/Old English
        ["\195\144"] = "D",  ["\195\176"] = "d",
        ["\195\158"] = "Th", ["\195\190"] = "th",

        -- French
        ["\197\147"] = "oe", ["\197\146"] = "OE",

        -- German
        ["\195\159"] = "B",

        -- Norwegian
        ["\195\152"] = "O", ["\195\184"] = "o",
        ["\195\133"] = "A", ["\195\165"] = "a",

        -- Special punctuation
        ["\226\128\147"] = "-",  ["\226\128\148"] = "-",
        ["\226\128\152"] = "'",  ["\226\128\153"] = "'",
        ["\226\128\156"] = "\"", ["\226\128\157"] = "\"",
        ["\226\128\166"] = "...",
        ["\194\173"]     = "-",
    }

    -- Replace accented and special characters
    s = s:gsub("[\194-\244][\128-\191]*", replacements)

    -- Replace separators [] {} () and commas with |
    s = s:gsub("[%[%]%(%){}%,]", "|")

    -- Convert to lowercase & trim
    s = s:lower():trim()

    -- Trim whitespace around |
    s = s:gsub("%s*|%s*", "|")

    -- Remove duplicate or leading/trailing pipes
    s = s:gsub("|+", "|"):gsub("^|", ""):gsub("|$", "")

    -- Replace any sequence of whitespace with a single hyphen
    s = s:gsub("%s+", "-")

    return s
end

--- Performs a fuzzy match between two pipe-delimited strings.
--- If `s1` contains a pipe, it is treated as a substring pattern and matched literally in `s2`.
--- If `s1` ends with a hyphen, it is treated as a prefix and matches any token in `s2` that starts with it.
--- Otherwise, performs exact token match against pipe-delimited segments in `s2`.
---
--- @param s1 (string) A value or pipe-delimited string to test.
--- @param s2 (string) A pipe-delimited string of valid reference values.
--- @return boolean matched True if a match is found based on the rules; false otherwise.
local function fuzzyMatch(s1, s2)
    if s1:find("|") then
        -- Full substring match if s1 is compound
        return s2:find(s1, 1, true) ~= nil
    else
        for word in s2:gmatch("[^|]+") do
            if s1:sub(-1) == "-" then
                -- Prefix match if s1 ends with -
                local prefix = s1:sub(1, -2)
                if word:sub(1, #prefix) == prefix then
                    return true
                end
            elseif word == s1 then
                return true
            end
        end
    end
    return false
end

--- Parses a whisper chat message into recipients and message text.
--- Splits the input message string at the first colon character (`:`), 
--- then trims whitespace from both the recipients and the message text
--- portions.
---
--- @param message (string) The input whisper chat message in the format "recipients:text".
--- @return string|nil recipients The recipient(s) extracted from the message, trimmed of whitespace.
--- @return string|nil text The message text after the colon, also trimmed of whitespace.
--- If the input string does not contain a colon, both values returned will be `nil`.
local function splitRecipientsAndText(message)
    message = message or ""
    local recipients, text = message:match("^(.-):(.*)$")
    return recipients and recipients:trim(), text and text:trim()
end

--- Splits a comma-separated recipients string into an array.
--- Parses the input string containing one or more comma-separated recipient names
--- into a Lua table array.
---
--- @param recipients (string) Comma-separated list of recipient names.
--- @return table recipients Array of recipient strings.
local function splitRecipients(recipients)
    local a = {}
    for e in recipients:gmatch("[^,]+") do
        table.insert(a, sanitizeString(e))
    end
    return a
end

--- Checks if a recipient string corresponds to a director/GM keyword.
--- Returns true if the provided recipient matches any predefined director keys ("dm", "gm", "director", "d").
---
--- @param recipient (string) The recipient string to check.
--- @return boolean isGM True if recipient matches a GM/director keyword; false otherwise.
local function isGM(recipient)
    return GM_ALIASES[recipient:lower()] == true
end

--- Translates a sanitized recipient name into one or more matching user IDs.
--- If the recipient is a GM alias, returns all DMs. Otherwise, matches display or character names.
---
--- @param recipient (string) The sanitized recipient name to translate.
--- @return table matches An array of matching user IDs. Empty if no matches found.
local function translateRecipientToIds(recipient)
    local matches = {}

    -- If the recipient is a GM alias, collect all users marked as DM and
    -- bypass name matching
    if isGM(recipient) then
        for _, userId in ipairs(dmhub.users) do
            local si = dmhub.GetSessionInfo(userId)
            if si and si.dm == true then
                writeDebug("DIRECTOR receiving [%s]", si.displayName)
                table.insert(matches, userId)
            end
        end
        return matches
    end

    -- Name-match resolution
    local recipientSanitized = sanitizeString(recipient)

    for _, userId in ipairs(dmhub.users) do
        local si = dmhub.GetSessionInfo(userId)
        if si then
            -- Match user display name
            local displayNameSanitized = sanitizeString(si.displayName)
            writeDebug("PLAYER [%s] in [%s]->[%s]", recipient, si.displayName, displayNameSanitized)
            if fuzzyMatch(recipientSanitized, displayNameSanitized) then
                writeDebug("PLAYER receiving [%s]", si.displayName)
                table.insert(matches, userId)
            end

            -- Match primary character name
            if si.primaryCharacter then
                local t = dmhub.GetCharacterById(si.primaryCharacter)
                if t then
                    local tokenNameSanitized = sanitizeString(t.name)
                    writeDebug("CHARACTER [%s] in [%s]->[%s]", recipient, t.name, tokenNameSanitized)
                    if fuzzyMatch(recipientSanitized, tokenNameSanitized) then
                        writeDebug("CHARACTER receiving [%s]", t.name)
                        table.insert(matches, userId)
                    end
                end
            end
        end
    end

    return matches
end

--- Parses a raw recipient string into a table of resolved user IDs.
--- Splits input into recipient tokens, translates each to one or more matching IDs,
--- and collates them into a deduplicated lookup table.
---
--- @param recipients (string) The raw input string containing comma-separated recipient names.
--- @return table flagTable A lookup table with user IDs as keys and `true` as values.
local function parseRecipients(recipients)
    local recipientList = splitRecipients(recipients)
    local recipientIds = {}

    for _, recipient in ipairs(recipientList) do
        local ids = translateRecipientToIds(recipient)
        for _, id in ipairs(ids) do
            recipientIds[id] = true
        end
    end

    return recipientIds
end

--- Formats a sender's display name with color and bold styling.
--- If session info is found for the given sender ID, uses their display name and color.
--- Otherwise, returns a default fallback label.
---
--- @param senderId (string) The user ID of the sender.
--- @return string s A formatted name string to show as the sender.
--- @see formatColoredName
local function formatSenderName(senderId)
    local fallback = "<color=#ff8c00>SNF!:</color>"
    local si = dmhub.GetSessionInfo(senderId)
    if si then
        return ExtChatMessage.FormatColoredName(si.displayName, si.displayColor.tostring)
    end
    return fallback
end

--- Builds a formatted, comma-separated string of recipient display names with color formatting.
--- For each user ID in the provided table (as keys), retrieves session info and constructs a colored label.
---
--- @param userIds (table) A table where user IDs are keys (e.g., { [id] = true }).
--- @return string displayNames A comma-separated string of formatted user display names.
local function formatRecipientNames(userIds)
    local parts = {}
    for userId in pairs(userIds) do
        local si = dmhub.GetSessionInfo(userId)
        if si then
            table.insert(parts, string.format("<color=%s>%s</color>", si.displayColor.tostring, si.displayName))
        end
    end
    return table.concat(parts, ", ")
end

--- Formats a message to indicate it was whispered by the current sender to specified recipients.
--- @param text string The message content to be sent.
--- @param recipientIds table A table of dmhub user IDs representing the recipients.
--- @return string text A formatted string including sender name, recipient names, and the message.
local function formatForSender(text, recipientIds)

    local senderName = formatSenderName(dmhub.userid)
    local recipientNames = formatRecipientNames(recipientIds)
    return string.format("%s <color=#a0a0a0><i>/w to %s:</i></color> %s", senderName, recipientNames, text)

end

--- Formats a message to show as a whisper from the current sender to recipients.
--- @param text string The message content being whispered.
--- @return string text A formatted string including the sender name and whisper indication.
local function formatForRecipients(text)

    local senderName = formatSenderName(dmhub.userid)
    return string.format("%s <color=#a0a0a0><i>whispers:</i></color> %s", senderName, text)

end

--- Runs internal unit tests for WhisperChatMessage behavior.
-- Only runs if WHISPER_DEBUG is enabled.
local function unitTest()
    if not WHISPER_DEBUG then 
        SendTitledChatMessage("Enable Debug to run tests. /wdebug [t|f]", "whisper", "#e09c9c")
        return
    end

    writeDebug("UNITTEST Start")

    local passes, fails = 0, 0

    local function testFuzzyMatch()
        local tests = {
            -- Approximates name matching as sent, player or character name, expect to match
            { "tim",        "Tim {DM}",                 true },
            { "tim (dm)",   "Tim {DM}",                 true },
            { "ti",         "Tim {DM}",                 false },
            { "ti",         "Tim",                      false },
            { "jaffe",      "Greg {Jaffé}",             true },
            { "thor",       "\195\158or",               true },
            { "\195\158or", "\195\190or",               true },
            { "\195\190or", "thor",                     true },
            { "thor",       "Thorvald (\195\158or)",    true },
            { "odin",       "o\195\176in",              true },
            { "facion",     "Fa\195\167ion",            true },
            { "t-",         "Tim {DM}",                 true },
            { "t-",         "\195\190or",               true },
            { "once-",      "Once Upon A Time",         true },
            { "u-",         "Once Upon A Time",         false },
            { "once-",      "Once        Time",         true },     -- spaces
            { "once-",      "Once	Upon	A",         true },     -- tabs
            { "upon-",      "Once	Upon	A",         false },    -- tabs
            { "bart",       "\195\159art",              true },
            { "x",          "a|b|c",                    false },
            { "-",          "literally anything",       true },
        }

        for _, test in ipairs(tests) do
            local s1, s2, expected = test[1], test[2], test[3]
            local result = fuzzyMatch(sanitizeString(s1), sanitizeString(s2))
            if result == expected then
                passes = passes + 1
            else
                fails = fails + 1
                writeDebug("FAILED fuzzyMatch: [%s] ?= [%s], expected [%s], got [%s]", s1, s2, tostring(expected), tostring(result))
            end
        end
    end

    testFuzzyMatch()

    writeDebug("UNITTEST Complete %d passes %d fails", passes, fails)

end

Commands.RegisterMacro{
    name = "whisper2test",
    summary = "whisper unit tests",
    doc = "Usage: /whisper2test\nRuns unit tests for whisper matching. Requires debug mode enabled.",
    command = function(args)
        unitTest()
    end,
}

Commands.RegisterMacro{
    name = "w2debug",
    summary = "whisper debug toggle",
    doc = "Usage: /w2debug [t|f]\nToggles or sets the whisper debug flag. Pass t/true or f/false.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        return {{text = "t", summary = "enable debug"}, {text = "f", summary = "disable debug"}}
    end,
    command = function(args)
        local lowered = args and args:lower()
        if lowered == "t" or lowered == "true" then
            WHISPER_DEBUG = true
        elseif lowered == "f" or lowered == "false" then
            WHISPER_DEBUG = false
        end
        SendTitledChatMessage(tostring(WHISPER_DEBUG), "wdebug", "#e09c9c")
    end,
}

--- Handles the sending of a whisper chat message.
--- Takes a raw input argument string, attempts to create a WhisperChatMessage instance,
--- and sends the resulting message if successfully created.
---
--- @param args (string) The raw argument string containing recipient(s) and message text.
--- @see WhisperChatMessage.Create
--- @see chat.SendCustom
local function doWhisper(args)

    local message = args or ""
    writeDebug("WHISPERING [%s]", message)

    local recipients, text = splitRecipientsAndText(message)
    if not (recipients and text and #recipients > 0 and #text > 0) then
        writeDebug("Malformed message, missing recipients or text.")
        usage()
        return nil
    end

    writeDebug("WHISPERING r,t [%s] [%s]", recipients, text)

    local recipientIds = parseRecipients(recipients)
    if next(recipientIds) == nil then
        usage()
        writeDebug("No valid recipients found, message discarded.")
        return nil
    end

    local forSender = formatForSender(text, recipientIds)
    local forRecipients = formatForRecipients(text)

    WriteChatText(forSender, dmhub.userid)
    WriteChatText(forRecipients, recipientIds)

end

Commands.RegisterMacro{
    name = "w",
    summary = "whisper message",
    doc = "Usage: /w <recipients>: <message>\nWhisper to players. Recipients can be names or dm/gm/director. Separate multiple with commas.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {{text = "dm", summary = "the Director"}, {text = "gm", summary = "the Director"}, {text = "director", summary = "the Director"}}
        for _, player in ipairs(dmhub.players) do
            result[#result+1] = {text = player.nick, summary = "player"}
        end
        return result
    end,
    command = function(args)
        doWhisper(args)
    end,
}

Commands.RegisterMacro{
    name = "whisper",
    summary = "whisper message",
    doc = "Usage: /whisper <recipients>: <message>\nWhisper to players. Recipients can be names or dm/gm/director. Separate multiple with commas.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {{text = "dm", summary = "the Director"}, {text = "gm", summary = "the Director"}, {text = "director", summary = "the Director"}}
        for _, player in ipairs(dmhub.players) do
            result[#result+1] = {text = player.nick, summary = "player"}
        end
        return result
    end,
    command = function(args)
        doWhisper(args)
    end,
}

