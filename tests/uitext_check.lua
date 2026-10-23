--Checks UIText text files against the code that looks their ids up.
--Run from the codex root:
--
--  ../dependencies/lua/bin/lua.exe tests/uitext_check.lua
--  ../dependencies/lua/bin/lua.exe tests/uitext_check.lua --text <file> ... --code <file> ...
--
--With no arguments it checks every Encounter of the Week text file against
--every Encounter of the Week code file. --text / --code replace those lists
--(handy while converting one code file). Exits 1 on any error.
--
--Errors: an id the code uses that no text file defines, an id defined twice,
--a {placeholder} the code gives no value for, a printf-style %s left in the
--text, a non-ASCII character (the Lua runtime cannot read them).
--Warnings: an id nobody uses, a value the code passes that the text never
--shows, a call whose id or values cannot be read statically.

local DEFAULT_TEXT = {
    "Codex Titlescreen/EotwTextTown.lua",
    "Codex Titlescreen/EotwTextHeroes.lua",
    "EncounterOfTheWeek/EncounterText.lua",
    "EncounterOfTheWeek/EncounterAuthoringText.lua",
}

local DEFAULT_CODE = {
    "Codex Titlescreen/EncounterOfTheWeek.lua",
    "Codex Titlescreen/EotwAnalytics.lua",
    "Codex Titlescreen/EotwBuild.lua",
    "Codex Titlescreen/EotwBuilder.lua",
    "Codex Titlescreen/EotwDowntime.lua",
    "Codex Titlescreen/EotwHeroCard.lua",
    "Codex Titlescreen/EotwHeroSheet.lua",
    "Codex Titlescreen/EotwHeroSheetData.lua",
    "Codex Titlescreen/EotwLeads.lua",
    "Codex Titlescreen/EotwMarket.lua",
    "Codex Titlescreen/EotwRoster.lua",
    "EncounterOfTheWeek/EncounterMontage.lua",
    "EncounterOfTheWeek/EncounterMontageBuilder.lua",
    "EncounterOfTheWeek/EncounterMontageStage.lua",
    "EncounterOfTheWeek/EncounterNarrative.lua",
    "EncounterOfTheWeek/EncounterOfTheWeek.lua",
    "EncounterOfTheWeek/EncounterOfTheWeekHud.lua",
    "EncounterOfTheWeek/EncounterPrep.lua",
    "EncounterOfTheWeek/EncounterPresence.lua",
    "EncounterOfTheWeek/EncounterReinforcements.lua",
    "EncounterOfTheWeek/EncounterScript.lua",
    "EncounterOfTheWeek/EncounterScriptBuilder.lua",
    "EncounterOfTheWeek/EncounterScriptEdit.lua",
    "EncounterOfTheWeek/EncounterScriptValidator.lua",
    "EncounterOfTheWeek/EncounterTest.lua",
    "EncounterOfTheWeek/EncounterZones.lua",
}

local textFiles, codeFiles = {}, {}
do
    local target = nil
    for _, a in ipairs(arg) do
        if a == "--text" then
            target = textFiles
        elseif a == "--code" then
            target = codeFiles
        elseif target ~= nil then
            target[#target + 1] = a
        else
            error("usage: uitext_check.lua [--text file ...] [--code file ...]")
        end
    end
    if #textFiles == 0 then textFiles = DEFAULT_TEXT end
    if #codeFiles == 0 then codeFiles = DEFAULT_CODE end
end

local nerrors, nwarnings = 0, 0
local function Err(where, msg)
    nerrors = nerrors + 1
    print("ERROR   " .. where .. ": " .. msg)
end
local function Warn(where, msg)
    nwarnings = nwarnings + 1
    print("warning " .. where .. ": " .. msg)
end

local function ReadFile(path)
    local f = io.open(path, "rb")
    if f == nil then
        return nil
    end
    local s = f:read("a")
    f:close()
    return s
end

--Placeholders in a text, as a set.
local function Placeholders(text)
    local result = {}
    for name in string.gmatch(text, "{([%a_][%w_]*)}") do
        result[name] = true
    end
    return result
end

----------------------------------------------------------------------------
--Load the text files with a recording stand-in for UIText.Define.

local defs = {}       --id -> { text, where }
local currentFile = nil

---@diagnostic disable-next-line: lowercase-global
dmhub = { GetModLoading = function() return {} end }
UIText = {
    Define = function(sourceName)
        return function(id, text)
            local info = debug.getinfo(2, "l")
            local where = currentFile .. ":" .. tostring(info and info.currentline or "?")
            if type(id) ~= "string" or type(text) ~= "string" then
                Err(where, "text(id, text) needs two strings")
                return
            end
            if defs[id] ~= nil then
                Err(where, string.format("'%s' is already defined at %s", id, defs[id].where))
                return
            end
            defs[id] = { text = text, where = where }

            if not string.match(id, "^[a-z0-9_]+%.[a-z0-9_%.]+$") or string.find(id, "..", 1, true) then
                Warn(where, string.format("id '%s' should be lower_case words joined by dots", id))
            end
            if string.find(text, "[\128-\255]") then
                Err(where, string.format("'%s' has a non-ASCII character (curly quote, dash, ...?)", id))
            end
            if string.find(text, "%%[-+ #0]*%d*%.?%d*[sdifgx]") then
                Err(where, string.format("'%s' still has a %%s-style format code; use {name}", id))
            end
            if string.find(text, "\\n", 1, true) then
                Warn(where, string.format("'%s' has a literal \\n; inside [[ ]] use a real line break", id))
            end
        end
    end,
}

for _, path in ipairs(textFiles) do
    currentFile = path
    local src = ReadFile(path)
    if src == nil then
        Err(path, "cannot read")
    else
        if string.find(src, "[\128-\255]") then
            Err(path, "the file has a non-ASCII character")
        end
        local chunk, err = load(src, "@" .. path)
        if chunk == nil then
            Err(path, "does not parse: " .. tostring(err))
        else
            local ok, runErr = pcall(chunk)
            if not ok then
                Err(path, "failed to run: " .. tostring(runErr))
            end
        end
    end
end

----------------------------------------------------------------------------
--Scan the code for lookups: T("id", {...}), UIText.T(...), TP("id", n, {...})
--and UIText.Plural(...).

local used = {}   --id -> true

local function LineAt(src, pos)
    local n = 1
    for _ in string.gmatch(string.sub(src, 1, pos), "\n") do
        n = n + 1
    end
    return n
end

--Given src and the position of an opening bracket, returns the position of
--its matching close, skipping strings and comments (roughly: enough for
--argument lists).
local function MatchClose(src, openPos)
    local open = string.sub(src, openPos, openPos)
    local close = ({ ["("] = ")", ["{"] = "}" })[open]
    local depth = 0
    local i = openPos
    local n = #src
    while i <= n do
        local c = string.sub(src, i, i)
        if c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = string.sub(src, j, j)
                if d == "\\" then
                    j = j + 1
                elseif d == c then
                    break
                end
                j = j + 1
            end
            i = j
        elseif c == "[" and string.match(src, "^%[=*%[", i) then
            local eq = string.match(src, "^%[(=*)%[", i)
            local _, e = string.find(src, "]" .. eq .. "]", i, true)
            i = e or n
        elseif c == "-" and string.sub(src, i, i + 1) == "--" then
            local e = string.find(src, "\n", i, true)
            i = e or n
        elseif c == "(" or c == "{" then
            depth = depth + 1
        elseif c == ")" or c == "}" then
            depth = depth - 1
            if depth == 0 then
                if c ~= close then
                    return nil
                end
                return i
            end
        end
        i = i + 1
    end
    return nil
end

--The top-level keys of a table constructor's source text ("{ a = 1, b = x }").
local function TableKeys(tsrc)
    --blank out nested brackets and strings so only depth-1 keys remain
    local out = {}
    local depth = 0
    local i = 1
    local n = #tsrc
    while i <= n do
        local c = string.sub(tsrc, i, i)
        if c == '"' or c == "'" then
            local j = i + 1
            while j <= n and string.sub(tsrc, j, j) ~= c do
                if string.sub(tsrc, j, j) == "\\" then j = j + 1 end
                j = j + 1
            end
            out[#out + 1] = " "
            i = j
        elseif c == "{" or c == "(" or c == "[" then
            depth = depth + 1
            out[#out + 1] = (depth == 1) and "," or " "
        elseif c == "}" or c == ")" or c == "]" then
            depth = depth - 1
            out[#out + 1] = (depth == 0) and "," or " "
        else
            out[#out + 1] = (depth == 1) and c or " "
        end
        i = i + 1
    end
    local flat = table.concat(out)
    local keys = {}
    for k in string.gmatch(flat, "[,;]%s*([%a_][%w_]*)%s*=[^=]") do
        keys[k] = true
    end
    return keys
end

--The source text of the first top-level table constructor in an argument
--list, and whether the list has more arguments than the id (and count).
local function FirstTableArg(argsrc)
    --argsrc runs from just after "(" to just before ")"
    local depth = 0
    local i = 1
    local n = #argsrc
    local sawComma = false
    while i <= n do
        local c = string.sub(argsrc, i, i)
        if c == '"' or c == "'" then
            local j = i + 1
            while j <= n and string.sub(argsrc, j, j) ~= c do
                if string.sub(argsrc, j, j) == "\\" then j = j + 1 end
                j = j + 1
            end
            i = j
        elseif c == "{" and depth == 0 and sawComma then
            local e = MatchClose(argsrc, i)
            if e ~= nil then
                return string.sub(argsrc, i, e)
            end
            return nil
        elseif c == "(" or c == "{" then
            depth = depth + 1
        elseif c == ")" or c == "}" then
            depth = depth - 1
        elseif c == "," and depth == 0 then
            sawComma = true
        end
        i = i + 1
    end
    return nil
end

--Number of top-level commas in an argument list (= arguments - 1).
local function CountArgs(argsrc)
    local depth, count, i, n = 0, 0, 1, #argsrc
    while i <= n do
        local c = string.sub(argsrc, i, i)
        if c == '"' or c == "'" then
            local j = i + 1
            while j <= n and string.sub(argsrc, j, j) ~= c do
                if string.sub(argsrc, j, j) == "\\" then j = j + 1 end
                j = j + 1
            end
            i = j
        elseif c == "(" or c == "{" or c == "[" then
            depth = depth + 1
        elseif c == ")" or c == "}" or c == "]" then
            depth = depth - 1
        elseif c == "," and depth == 0 then
            count = count + 1
        end
        i = i + 1
    end
    return count + 1
end

local function CheckCall(path, src, pos, isPlural, openPos)
    local where = path .. ":" .. LineAt(src, pos)
    local closePos = MatchClose(src, openPos)
    if closePos == nil then
        Warn(where, "could not read this call")
        return
    end
    local argsrc = string.sub(src, openPos + 1, closePos - 1)
    local id = string.match(argsrc, '^%s*"([^"]*)"') or string.match(argsrc, "^%s*'([^']*)'")
    if id == nil then
        Warn(where, "id is not a literal string; cannot be checked")
        return
    end

    local texts = {}
    if isPlural then
        for _, suffix in ipairs({ ".one", ".other" }) do
            used[id .. suffix] = true
            if defs[id .. suffix] == nil then
                Err(where, string.format("no text for '%s'", id .. suffix))
            else
                texts[#texts + 1] = defs[id .. suffix].text
            end
        end
    else
        used[id] = true
        if defs[id] == nil then
            Err(where, string.format("no text for '%s'", id))
            return
        end
        texts[1] = defs[id].text
    end
    if #texts == 0 then
        return
    end

    local wanted = {}
    for _, t in ipairs(texts) do
        for k in pairs(Placeholders(t)) do
            wanted[k] = true
        end
    end
    if isPlural then
        wanted.count = nil
    end

    local nargs = CountArgs(argsrc)
    local valueArgIndex = isPlural and 3 or 2
    local tsrc = FirstTableArg(argsrc)
    if tsrc == nil then
        if nargs >= valueArgIndex then
            --values given as a variable: cannot check statically
            return
        end
        for k in pairs(wanted) do
            Err(where, string.format("'%s' needs {%s} but the call gives no values", id, k))
        end
        return
    end

    local given = TableKeys(tsrc)
    for k in pairs(wanted) do
        if not given[k] then
            Err(where, string.format("'%s' needs {%s} but the call does not give it", id, k))
        end
    end
    for k in pairs(given) do
        if not wanted[k] and not (isPlural and k == "count") then
            Warn(where, string.format("'%s' is given '%s' but its text never shows it", id, k))
        end
    end
end

for _, path in ipairs(codeFiles) do
    local src = ReadFile(path)
    if src == nil then
        Err(path, "cannot read")
    else
        --the four call forms; %f keeps "x.T(" / "x:T(" / "MyT(" out
        local FORMS = {
            { pattern = "%f[%w_%.:]T%s*%(", plural = false },
            { pattern = "%f[%w_%.:]UIText%.T%s*%(", plural = false },
            { pattern = "%f[%w_%.:]TP%s*%(", plural = true },
            { pattern = "%f[%w_%.:]UIText%.Plural%s*%(", plural = true },
        }
        for _, form in ipairs(FORMS) do
            local i = 1
            while true do
                local s, e = string.find(src, form.pattern, i)
                if s == nil then
                    break
                end
                --skip function definitions and commented-out lines
                local lineStart = s
                while lineStart > 1 and string.sub(src, lineStart - 1, lineStart - 1) ~= "\n" do
                    lineStart = lineStart - 1
                end
                local before = string.sub(src, lineStart, s - 1)
                if not string.find(before, "%-%-") and not string.match(before, "function%s*$") then
                    CheckCall(path, src, s, form.plural, e)
                end
                i = e + 1
            end
        end
    end
end

for id, d in pairs(defs) do
    if not used[id] then
        Warn(d.where, string.format("'%s' is not used by the code", id))
    end
end

local ndefs = 0
for _ in pairs(defs) do ndefs = ndefs + 1 end
print(string.format("uitext_check: %d entries, %d errors, %d warnings", ndefs, nerrors, nwarnings))
if nerrors > 0 then
    os.exit(1)
end
