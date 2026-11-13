local mod = dmhub.GetModLoading()

--UIText: user-facing text kept out of the code, keyed by stable ids, so a
--writer can rewrite it without touching the code that shows it.
--
--  Text files define the words:
--
--      local text = UIText.Define("EotwTextTown")
--      text("inn.carouse.title", [[Carouse at the Blue Fish Inn]])
--      text("inn.carouse.tier2", [[{total} (natural {natural}). {hero} trades stories all night.]])
--
--  Code looks them up:
--
--      local T = UIText.T
--      label.text = T("inn.carouse.title")
--      label.text = T("inn.carouse.tier2", { total = 14, natural = 9, hero = name })
--
--  * Placeholders are {name}: letters, digits and underscores. The code
--    passes every value already formatted (a "+2" bonus, a colored name).
--  * Counted text uses two entries, "<id>.one" and "<id>.other", looked up
--    with UIText.Plural(id, count, args); {count} is filled in for you.
--  * A text file must load before any code that uses its ids, because code
--    may look text up while it loads (tables of locations, projects, ...).
--  * A missing id shows as "[id]" and is reported once in the DebugConsole.
--
--tests/uitext_check.lua checks the text files against the code that uses
--them: every id exists, the placeholders match, nothing is defined twice.

UIText = {}

--Set true (e.g. over MCP) to prefix every looked-up string with its id, so a
--reviewer can see which entry is which on screen. Rebuild the UI after.
UIText.showIds = false

--id -> text, and id -> the name of the file that defined it.
local g_text = {}
local g_source = {}

--ids already reported missing or broken, so each is reported once.
local g_reported = {}

local function Report(key, message)
    if g_reported[key] then
        return
    end
    g_reported[key] = true
    dmhub.Error("UIText: " .. message)
end

--- Returns the function a text file uses to define its entries.
--- @param sourceName string The text file's name, for duplicate reports.
--- @return fun(id: string, text: string)
function UIText.Define(sourceName)
    return function(id, text)
        if g_source[id] ~= nil and g_source[id] ~= sourceName then
            Report("dup:" .. id, string.format("'%s' is defined in both %s and %s", id, g_source[id], sourceName))
        end
        g_text[id] = text
        g_source[id] = sourceName
    end
end

--- True if the id has text.
--- @param id string
--- @return boolean
function UIText.Has(id)
    return g_text[id] ~= nil
end

--Fills {name} placeholders from args. A placeholder with no value is left
--as written, so the gap is visible, and reported.
local function Fill(id, text, args)
    if string.find(text, "{", 1, true) == nil then
        return text
    end
    return (string.gsub(text, "{([%a_][%w_]*)}", function(name)
        local value = args ~= nil and args[name] or nil
        if value == nil then
            Report("arg:" .. id .. ":" .. name, string.format("'%s' has {%s} but the code gave no value for it", id, name))
            return nil
        end
        return tostring(value)
    end))
end

--- The text for an id, with its {placeholders} filled from args.
--- @param id string
--- @param args? table<string, any>
--- @return string
function UIText.T(id, args)
    local text = g_text[id]
    if text == nil then
        Report("missing:" .. id, string.format("no text for '%s'", id))
        return "[" .. id .. "]"
    end
    local result = Fill(id, text, args)
    if UIText.showIds then
        return "[" .. id .. "] " .. result
    end
    return result
end

--- Counted text: "<id>.one" when count is 1, "<id>.other" otherwise.
--- {count} is filled with count unless args gives it.
--- @param id string
--- @param count number
--- @param args? table<string, any>
--- @return string
function UIText.Plural(id, count, args)
    local filled = { count = count }
    if args ~= nil then
        for k, v in pairs(args) do
            filled[k] = v
        end
    end
    if count == 1 then
        return UIText.T(id .. ".one", filled)
    end
    return UIText.T(id .. ".other", filled)
end

--- Every id and its text, for exports and checks.
--- @return table<string, string>
function UIText.All()
    local result = {}
    for k, v in pairs(g_text) do
        result[k] = v
    end
    return result
end
