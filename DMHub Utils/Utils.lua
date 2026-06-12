local mod = dmhub.GetModLoading()

-- Macro registration infrastructure. Defined here in Utils so it is available
-- to every module (Utils loads first in main.lua).
Commands._macros = Commands._macros or {}

function Commands.RegisterMacro(args)
    local name = args.name
    local fn = args.command
    local doc = args.doc
    local summary = args.summary

    if doc ~= nil then
        Commands[name] = function(str)
            if str == "help" then
                dmhub.Log(doc)
                return
            end
            return fn(str)
        end
    else
        Commands[name] = fn
    end

    Commands._macros[name] = {
        doc = doc,
        summary = summary,
        completions = args.completions,
    }
end

function Commands.GetMacroInfo(name)
    return Commands._macros[name]
end

function Commands.GetAllMacros()
    return Commands._macros
end

-- Parse the text after a /command into structured argument info.
-- Returns macroName, args (completed args), partial (current partial arg), argIndex
function Commands.GetCurrentArg(text)
    local macroName = string.match(text, "^/([%w_]+)%s")
    if macroName == nil then
        return nil
    end
    local afterCommand = string.match(text, "^/%S+%s(.*)$") or ""
    local args = {}
    local current = {}
    local inQuote = false
    for i = 1, #afterCommand do
        local c = string.sub(afterCommand, i, i)
        if c == '"' then
            inQuote = not inQuote
            current[#current+1] = c
        elseif c == ' ' and not inQuote then
            if #current > 0 then
                args[#args+1] = table.concat(current)
                current = {}
            end
        else
            current[#current+1] = c
        end
    end
    local partial = table.concat(current)
    local argIndex = #args + 1
    return macroName, args, partial, argIndex
end

-- Register documentation for a built-in (C#) command without overriding its
-- execution. Only populates _macros so the ChatPanel UI shows summary, doc,
-- and argument completions.
function Commands.RegisterBuiltinDoc(args)
    Commands._macros[string.lower(args.name)] = {
        doc = args.doc,
        summary = args.summary,
        completions = args.completions,
    }
end

--- @param table table
--- @param element any
--- @return boolean
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

--- @param t table
--- @return number
function table.count_elements(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- @param t table
--- @param element any
function table.remove_value(t, element)
    local result = false
    for i=#t, 1, -1 do
        if t[i] == element then
            table.remove(t, i)
            result = true
        end
    end

    return result
end

function table.resize_array(t, size)
    for i=#t, size + 1, -1 do
        t[i] = nil
    end
end

function table.empty(t)
    return next(t) == nil
end

function table.keys(t)
    local keys = {}
    for k, _ in pairs(t) do
        keys[#keys+1] = k
    end
    return keys
end

function table.mapped_keys(t, fn)
    local keys = {}
    for k, _ in pairs(t) do
        keys[#keys+1] = fn(k)
    end
    return keys
end

function table.values(t)
    local values = {}
    for _, v in pairs(t) do
        values[#values+1] = v
    end
    return values
end

function table.set_to_ordered_csv(set, emptyText)
    local list = table.keys(set)
    table.sort(list)
    if #list == 0 then
        return emptyText or ""
    end
    return table.concat(list, ", ")
end

function table.shallow_copy_into_dest(src, dest)
    for k,v in pairs(src) do
        dest[k] = v
    end

    for k,v in pairs(dest) do
        if src[k] == nil then
            dest[k] = nil
        end
    end
end

function table.shallow_copy_with_meta(t)
    local result = {}
    for k,v in pairs(t) do
        result[k] = v
    end
    setmetatable(result, getmetatable(t))

    return result
end

function table.shallow_copy(t)
    local result = {}
    for k,v in pairs(t) do
        result[k] = v
    end

    return result
end

function table.sort_and_return(s)
    table.sort(s)
    return s
end

function table.append_arrays(t1, t2)
    local result = {}

    for _, v in ipairs(t1 or {}) do
        result[#result+1] = v
    end

    for _, v in ipairs(t2 or {}) do
        result[#result+1] = v
    end

    return result
end

function map(t, f)
    local result = {}
    for i, v in ipairs(t or {}) do
        result[i] = f(v)
    end
    return result
end

function filter(t, f)
    local result = {}
    for k, v in pairs(t) do
        if f(v) then
            result[k] = v
        end
    end
    return result
end

function sorted_pairs(t)
    local keys = table.keys(t)
    table.sort(keys)
    local nextKey = {}
    for i, key in ipairs(keys) do
        nextKey[key] = keys[i+1]
    end
    nextKey[0] = keys[1]
    return function(a, key)
        key = nextKey[key]
        if key ~= nil then
            local value = t[key]
            return key, value
        end
    end, t, 0
end

local next_unhidden = function(t, key)
    local val
    key, val = next(t, key)
    while val ~= nil and rawget(val, "hidden") do
        key, val = next(t, key)
    end

    return key, val
end

function unhidden_pairs(t)
    return next_unhidden, t, nil
end

---@param s string
---@return string
function string.trim(s)
    if type(s) ~= "string" then
        return s
    end
    local a = s:match('^%s*()')
    local b = s:match('()%s*$', a)
    return s:sub(a,b-1)
 end
 
function string.starts_with(String,Start)
	return string.sub(String,1,string.len(Start)) == Start
end

function string.ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

function math.clamp(x, a, b)
    if x < a then
        return a
    end

    if x > b then
        return b
    end

    return x
end

function math.clamp01(x)
    if x < 0 then
        return 0
    end

    if x > 1 then
        return 1
    end

    return x
end

function DebugMatchesSearchRecursive(obj, search, depth, path)
    if depth > 6 then
        return false
    end
    if type(obj) == "table" then
        for k,v in pairs(obj) do
            local fullpath = path .. "/" .. tostring(k)
            if DebugMatchesSearchRecursive(k, search, depth+1, fullpath) or DebugMatchesSearchRecursive(v, search, depth+1, fullpath) then
                return true
            end
        end
    elseif type(obj) == "string" then
        --search without any pattern matching etc, just verbatim substring match
        if string.find(string.lower(obj), search, 1, true) ~= nil then
            print("SEARCH MATCH:", path, string.lower(obj), "matches", search)
            return true
        end
    end

    return false
end

-- =============================================================================
-- Shared text matcher.
-- One normalisation + substring + highlight path used by every search/filter
-- surface (compendium filter, global search, feature filters) so they all
-- behave consistently. The legacy MatchesSearchRecursive / SearchTableHasMatch
-- / SearchTableForText globals are kept below as thin wrappers over these so
-- existing callers are unchanged.
--
-- Contract: the Matches*/MatchKeys functions assume an already-NORMALISED
-- needle (run it through Search.Normalize once, then reuse) so the lowering is
-- not repeated per candidate. They lower the haystack themselves. The legacy
-- wrappers preserve the old contract (needle used verbatim, not normalised).
-- =============================================================================

Search = {}

--- Normalise a user-entered needle: lowercase + trim surrounding whitespace.
--- @param text string|nil
--- @return string
function Search.Normalize(text)
    if text == nil then
        return ""
    end
    return (string.lower(text):match("^%s*(.-)%s*$"))
end

-- Single-entry memo for term splitting: search sweeps test thousands of
-- candidates against ONE needle, so cache the last split rather than
-- re-splitting per candidate.
local g_lastTermsNeedle = nil
local g_lastTerms = nil

--- Split a needle into its whitespace-separated terms for multi-term AND
--- matching. Returns nil for a single-term needle so callers keep the plain
--- single-substring fast path.
--- @param needle string|nil
--- @return table|nil
function Search.SplitTerms(needle)
    if needle == nil or string.find(needle, " ", 1, true) == nil then
        return nil
    end
    if needle == g_lastTermsNeedle then
        return g_lastTerms
    end
    local terms = {}
    for term in string.gmatch(needle, "%S+") do
        terms[#terms+1] = term
    end
    g_lastTermsNeedle = needle
    if #terms < 2 then
        g_lastTerms = nil
    else
        g_lastTerms = terms
    end
    return g_lastTerms
end

--- Substring test of a single string against a (normalised) needle. An empty
--- needle matches everything so "no filter" shows all rows. A multi-term
--- needle ("fire damage") matches when EVERY term appears, in any order, so
--- word order never hides a result.
--- @param haystack any
--- @param needle string
--- @return boolean
function Search.MatchesText(haystack, needle)
    if needle == nil or needle == "" then
        return true
    end
    if type(haystack) ~= "string" then
        return false
    end
    local h = string.lower(haystack)
    local terms = Search.SplitTerms(needle)
    if terms == nil then
        return string.find(h, needle, 1, true) ~= nil
    end
    for _,term in ipairs(terms) do
        if string.find(h, term, 1, true) == nil then
            return false
        end
    end
    return true
end

-- Single-needle recursive walk; the multi-term AND lives in the public
-- Search.MatchesObject wrapper so recursion never re-splits the needle.
local function MatchesObjectSingle(obj, needle, depth)
    depth = depth or 0
    if depth > 6 then
        return false
    end
    if type(obj) == "table" then
        for k,v in pairs(obj) do
            if MatchesObjectSingle(k, needle, depth+1) or MatchesObjectSingle(v, needle, depth+1) then
                return true
            end
        end
    elseif type(obj) == "string" then
        if string.find(string.lower(obj), needle, 1, true) ~= nil then
            return true
        end
    end

    return false
end

--- Recursive object match: true if any string key or value anywhere in obj (to
--- depth 6) contains the needle. Verbatim substring, no pattern matching. A
--- multi-term needle requires every term to match SOMEWHERE in the object
--- (different fields may satisfy different terms).
--- @param obj any
--- @param needle string
--- @param depth number|nil
--- @return boolean
function Search.MatchesObject(obj, needle, depth)
    local terms = Search.SplitTerms(needle)
    if terms == nil then
        return MatchesObjectSingle(obj, needle, depth)
    end
    for _,term in ipairs(terms) do
        if not MatchesObjectSingle(obj, term, depth) then
            return false
        end
    end
    return true
end

--- Returns the list of keys in table t whose entry (key or value) matches the
--- needle. Iterates unhidden_pairs so soft-deleted rows are skipped.
--- @param t table
--- @param needle string
--- @return table list of keys
function Search.MatchKeys(t, needle)
    local results = {}
    for k,v in unhidden_pairs(t) do
        if Search.MatchesObject(k, needle, 0) or Search.MatchesObject(v, needle, 0) then
            results[#results+1] = k
        end
    end

    return results
end

--- Wrap each case-insensitive occurrence of the (normalised) needle in text
--- with theme-accent emphasis markup, so matched runs stand out in a list. The
--- colour is resolved from a theme token (default @accent) at call time, never
--- hard-coded; if the theme engine is not available the text is returned
--- unchanged (no markup) rather than falling back to a literal colour.
--- @param text string
--- @param needle string
--- @param colorToken string|nil theme token, defaults to "@accent"
--- @return string
function Search.Highlight(text, needle, colorToken)
    if type(text) ~= "string" or needle == nil or needle == "" then
        return text
    end

    if ThemeEngine == nil or ThemeEngine.ResolveTokens == nil then
        return text
    end

    local lower = string.lower(text)
    local terms = Search.SplitTerms(needle)

    -- Collect every match range (per term for multi-term needles), then merge
    -- overlapping/adjacent ranges so nested markup is never emitted.
    local ranges = {}
    for _,term in ipairs(terms or {needle}) do
        local pos = 1
        while true do
            local s = string.find(lower, term, pos, true)
            if s == nil then
                break
            end
            ranges[#ranges+1] = {a = s, b = s + #term - 1}
            pos = s + 1
        end
    end

    if #ranges == 0 then
        return text
    end

    table.sort(ranges, function(x,y) return x.a < y.a end)
    local merged = {ranges[1]}
    for i=2,#ranges do
        local r = ranges[i]
        local last = merged[#merged]
        if r.a <= last.b + 1 then
            if r.b > last.b then
                last.b = r.b
            end
        else
            merged[#merged+1] = r
        end
    end

    local color = ThemeEngine.ResolveTokens(colorToken or "@accent")
    local out = {}
    local pos = 1
    for _,r in ipairs(merged) do
        out[#out+1] = string.sub(text, pos, r.a-1)
        out[#out+1] = "<color=" .. color .. "><b>" .. string.sub(text, r.a, r.b) .. "</b></color>"
        pos = r.b + 1
    end
    out[#out+1] = string.sub(text, pos)

    return table.concat(out)
end

-- Relevance score for a candidate name against a (normalised) needle. Mirrors
-- the title-bar idiom: exact 100, prefix 75, substring 50; a multi-term needle
-- whose terms all appear but not as the contiguous phrase scores 25 (ranks
-- below any whole-phrase match); none 0. Shared so every provider ranks
-- consistently. Assumes the needle is already normalised.
--- @param text any
--- @param needle string
--- @return number
function Search.Score(text, needle)
    if type(text) ~= "string" or needle == nil or needle == "" then
        return 0
    end
    local h = string.lower(text)
    if h == needle then
        return 100
    elseif string.starts_with(h, needle) then
        return 75
    elseif string.find(h, needle, 1, true) ~= nil then
        return 50
    end

    local terms = Search.SplitTerms(needle)
    if terms ~= nil then
        for _,term in ipairs(terms) do
            if string.find(h, term, 1, true) == nil then
                return 0
            end
        end
        return 25
    end
    return 0
end

-- =============================================================================
-- Global-search provider registry.
-- Appearing in global (title-bar) search = registering a PROVIDER. The system
-- cannot auto-derive this (it can't tell user-facing data from internal, nor
-- know the click action), so each domain opts in. Two forms:
--
--   One-liner (standard GetTable content):
--     Search.RegisterProvider{
--         id = "...", bucket = "compendium",
--         tableName = "...", nameField = "name",     -- nameField defaults to "name"
--         typeLabel = "...",                          -- shown as the result's source label
--         activate = function(item, key) ... end,     -- optional click action
--     }
--
--   Full provider (bespoke / computed data):
--     Search.RegisterProvider{
--         id = "...", bucket = "ingame", typeLabel = "...",
--         enumerate = function(needle)                -- needle is normalised
--             return { { name=, score=, typeLabel=, activate=function() end }, ... }
--         end,
--     }
--
-- `bucket` is one of Search.Buckets (display labels are owned by the search UI).
-- Same path for first-party and third-party module devs; no core changes.
-- =============================================================================

-- Stable bucket ids. The title-bar search owns the display labels and order.
Search.Buckets = { "compendium", "rulebooks", "ingame", "apptools" }

-- Providers with a needle shorter than this are skipped: a single character
-- matches almost everything and floods the results / wastes the render budget.
Search.MinProviderQueryLength = 2

local g_searchProviders = {}

--- @param spec table provider spec (see header above); must carry a unique id
function Search.RegisterProvider(spec)
    if spec == nil or spec.id == nil then
        return
    end
    g_searchProviders[spec.id] = spec
end

--- @param id string
function Search.UnregisterProvider(id)
    g_searchProviders[id] = nil
end

--- Run every registered provider against a (normalised) needle and return a
--- flat list of result rows. Each row carries: name, score, bucket, typeLabel,
--- and an activate() click action. A provider that errors is skipped rather
--- than breaking the whole search.
--- @param needle string normalised needle (see Search.Normalize)
--- @return table list of result rows
function Search.CollectProviderResults(needle)
    local results = {}
    if needle == nil or #needle < Search.MinProviderQueryLength then
        return results
    end

    for _,spec in pairs(g_searchProviders) do
        if spec.enumerate ~= nil then
            local ok, list = pcall(spec.enumerate, needle)
            if ok and type(list) == "table" then
                for _,r in ipairs(list) do
                    r.bucket = r.bucket or spec.bucket
                    r.typeLabel = r.typeLabel or spec.typeLabel
                    results[#results+1] = r
                end
            end
        elseif spec.tableName ~= nil then
            local t = dmhub.GetTable(spec.tableName) or {}
            local nameField = spec.nameField or "name"
            for k,v in unhidden_pairs(t) do
                local name = (type(v) == "table" and rawget(v, nameField)) or nil
                if type(name) == "string" and Search.MatchesText(name, needle) then
                    local capturedItem, capturedKey = v, k
                    results[#results+1] = {
                        name = name,
                        score = Search.Score(name, needle),
                        bucket = spec.bucket,
                        typeLabel = spec.typeLabel,
                        activate = function()
                            if spec.activate ~= nil then
                                spec.activate(capturedItem, capturedKey)
                            end
                        end,
                    }
                end
            end
        end
    end

    return results
end

-- =============================================================================
-- Context-sensitive search providers.
-- When an artifact (PDF viewer, map, character sheet, journal, encounter) is
-- open in the main Codex view, it can expose a search scoped to itself.
-- Global search surfaces the results as ONE group pinned ABOVE the intent
-- buckets ("In this document", "On this map", ...). The group is ADDITIVE -
-- it never replaces global reach.
--
-- Registration is PRESENCE-based: register when the artifact's panel is
-- created, unregister in its destroy. Never key off gui focus - the search
-- input itself holds focus while the user types. When several artifacts are
-- open at once the HIGHEST-priority provider wins (topmost artifact):
-- modal viewers (PDF) ~100, sheet/journal/encounter ~50, map ~10.
--
--   Search.RegisterContextProvider{
--       id = "pdf-viewer", priority = 100, label = "In this document",
--       enumerate = function(needle)          -- needle is normalised
--           return { {name=, subLabel=, score=, activate=function() end}, ... },
--                  pendingBoolean             -- true = async search still running
--       end,
--   }
-- =============================================================================

local g_contextProviders = {}

--- @param spec table context provider spec (see header above); unique id required
function Search.RegisterContextProvider(spec)
    if spec == nil or spec.id == nil then
        return
    end
    g_contextProviders[spec.id] = spec
end

--- @param id string
function Search.UnregisterContextProvider(id)
    g_contextProviders[id] = nil
end

--- Run the highest-priority registered context provider against a (normalised)
--- needle. Returns nil when no context is active, otherwise
--- {label, results, pending}; pending=true means the provider is still
--- searching asynchronously and the caller should repeat the search shortly.
--- @param needle string normalised needle (see Search.Normalize)
--- @return table|nil
function Search.CollectContextResults(needle)
    if needle == nil or #needle < Search.MinProviderQueryLength then
        return nil
    end

    local best = nil
    for _,spec in pairs(g_contextProviders) do
        if best == nil or (spec.priority or 0) > (best.priority or 0) then
            best = spec
        end
    end
    if best == nil then
        return nil
    end

    local ok, results, pending = pcall(best.enumerate, needle)
    if not ok or type(results) ~= "table" then
        return nil
    end
    table.sort(results, function(a,b) return (a.score or 0) > (b.score or 0) end)
    return {label = best.label or "In this view", results = results, pending = (pending == true)}
end

-- Legacy wrappers. These keep the historical contract (needle used verbatim,
-- haystack lowered) so existing callers behave identically.

function MatchesSearchRecursive(obj, search, depth)
    return Search.MatchesObject(obj, search, depth)
end

function SearchTableHasMatch(t, search)
    for k,v in unhidden_pairs(t) do
        if Search.MatchesObject(k, search, 0) or Search.MatchesObject(v, search, 0) then
            return true
        end
    end
    return false
end

function SearchTableForText(t, search)
    return Search.MatchKeys(t, search)
end

function DebugSearchTableForText(t, search, debugName)
    local results = {}
    for k,v in unhidden_pairs(t) do
        local path = debugName .. "/" .. tostring(k)
        if DebugMatchesSearchRecursive(k, search, 0, path) or DebugMatchesSearchRecursive(v, search, 0, path) then
            results[#results+1] = k
        end
    end

    return results
end

function debug_and_return(item)
    return item
end

function StringInterpolateGoblinScript(str, symbols, depth)
    if str == nil then
        return nil
    end

    if string.find(str, "\n") ~= nil then
        str = string.gsub(str, "\r\n", "\n")
        local lines = string.split(str, "\n")
        local result = ""
        for _,line in ipairs(lines) do
            result = result .. StringInterpolateGoblinScript(line, symbols, depth) .. "\n"
        end
        return result
    end

    depth = depth or 0
    if depth > 16 then
        return str
    end
    local match = regex.MatchGroups(str, "^(?<prefix>[^{]*)\\{(?<formula>[^}]+?)(?<alt>\\|[^}]+)?\\}(?<postfix>.*)$")
    if match == nil then
        return str
    end

    if type(symbols) == "table" then
        symbols = symbols:LookupSymbol{}
    end

    local value
    if symbols == nil then
        value = match.alt or match.formula
        value = string.gsub(value, "|", "")
    else
        value = ExecuteGoblinScript(match.formula, symbols, value, "formula substitution")
    end

    return string.format("%s%s%s", match.prefix, tostring(value), StringInterpolateGoblinScript(match.postfix, symbols, depth+1))
end

Utils = {}

--- @param guid string
--- @return number
Utils.HashGuidToNumber = function(guid)
    local hash = 0
    for i = 1, #guid do
        hash = (hash * 31 + string.byte(guid, i)) % 2^32
    end
    return hash
end

Utils.DropdownIdToText = function(id, enumEntries)
    for _, entry in ipairs(enumEntries) do
        if entry.id == id then
            return entry.text
        end
    end

    return id
end

Utils.ResolveGoblinScriptObject = function(obj)
    if type(obj) == "function" then
        return obj("self")
    end
    return obj
end

function string.replace_insensitive(s, target, replacement, startIndex)
    local start_index, end_index = string.find(string.lower(s), string.lower(target), startIndex or 1)
    if start_index == nil then
        return s
    end

    local newString = s:sub(1, start_index - 1) .. replacement .. s:sub(end_index + 1)
    return string.replace_insensitive(newString, target, replacement, start_index + #replacement)
end

function string.upper_first(str)
    if str == nil or #str == 0 then
        return str
    end

    return string.upper(str:sub(1, 1)) .. str:sub(2)
end

function CountLoggedInUsers()
    local count = 0
    for i,userid in ipairs(dmhub.users) do
        local info = dmhub.GetSessionInfo(userid)
        if (not info.loggedOut) and info.timeSinceLastContact < 120 then
            count = count + 1
        end
    end

    return count
end

function table.find_self_references(t, visited, path)
    path = path or "/"
    visited = visited or {}

    if type(t) ~= "table" then
        return false
    end

    if visited[t] then
        return path
    end

    visited[t] = true
    for k,v in pairs(t) do
        local result = table.find_self_references(v, visited, path.."/"..tostring(k))
        if result then
            return result
        end
    end

    return false
end

function table.list_to_set(t)
    local result = {}
    for _,v in ipairs(t or {}) do
        result[v] = true
    end
    return result
end

function table.set_to_list(t)
    local result = {}
    for k,_ in pairs(t or {}) do
        result[#result+1] = k
    end
    return result
end

function string.split (inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end

function string.split_allow_duplicates(inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]*)") do
                table.insert(t, str)
        end
        return t
end

function string.split_with_square_brackets(inputstr, sep)
    local result = {}
    local chars = {}
    local depth = 0
    for i = 1, #inputstr do
        local c = inputstr:sub(i,i)
        if depth <= 0 and c == sep then
            result[#result+1] = table.concat(chars)
            chars = {}
        else
            if c == "[" then
                depth = depth+1
            elseif c == "]" then
                depth = depth-1
            end

            chars[#chars+1] = c
        end
    end

    result[#result+1] = table.concat(chars)
    return result
end

function GoblinScriptTrue(val)
    if type(val) == "number" then
        return val > 0
    else
        return val ~= nil and val ~= false
    end
end


function table.filter(t, f)
    local result = {}
    for _, v in ipairs(t or {}) do
        if f(v) then
            result[#result+1] = v
        end
    end
    return result
end

function table.stable_sort(t, cmp)
    -- decorate with original indices
    local decorated = {}
    for i, v in ipairs(t) do
        decorated[i] = { value = v, index = i }
    end

    -- sort with index tie-breaker
    table.sort(decorated, function(a, b)
        if cmp(a.value, b.value) then
            return true
        elseif cmp(b.value, a.value) then
            return false
        else
            return a.index < b.index
        end
    end)

    -- undecorate
    for i = 1, #t do
        t[i] = decorated[i].value
    end
end


function DeepReplaceGuids(obj, guidMap, key)
    key = key or "guid"
    if type(obj) ~= "table" then
        return
    end

    guidMap = guidMap or {}

    local guid = rawget(obj, key)

    if guid ~= nil then
        guidMap[guid] = guidMap[guid] or dmhub.GenerateGuid()
        obj[key] = guidMap[guid]
    end

    for k,v in pairs(obj) do
        if type(v) == "table" then
            DeepReplaceGuids(v, guidMap, key)
        elseif type(v) == "string" and guidMap[v] ~= nil then
            obj[k] = guidMap[v]
        end
    end
end

function safe_toint(val)
    local num = tonumber(val)
    if num == nil then
        return nil
    end

    if type(val) == "string" and not val:match("^%d+$") then
        return nil
    elseif math.floor(num) ~= num then
        return nil
    end

    return num
end

function FindObjectPathByGuid(guid, obj, path)
    path = path or {}
    
    -- Check if current object has matching guid
    if type(obj) == "table" and (rawget(obj, "guid") == guid or rawget(obj, "id") == guid) then
        return true
    end
    
    -- Recursively search nested tables
    if type(obj) == "table" and #path < 16 then
        for k, v in pairs(obj) do
            if k ~= "_luaTable" and type(v) == "table" then
                path[#path+1] = k
                local found = FindObjectPathByGuid(guid, v, path)
                if found then
                    return true
                end
                path[#path] = nil
            end
        end
    end
    
    return false
end

function GetObjectAtPath(obj, path)
    local current = obj
    for i = 1, #path do
        if current == nil or type(current) ~= "table" then
            return nil
        end
        current = rawget(current, path[i])
    end
    return current
end

function SetObjectAtPath(obj, path, value)
    if #path == 0 then
        return false
    end
    
    local current = obj
    for i = 1, #path - 1 do
        if current == nil or type(current) ~= "table" then
            return false
        end
        current = rawget(current, path[i])
    end
    
    if current == nil or type(current) ~= "table" then
        return false
    end
    
    current[path[#path]] = value
    return true
end

function FindAbilityParentByGuid(guid)
    local function FindInObject(obj, targetGuid, visited, parent)

        if type(obj) ~= "table" then
            return nil
        end
        
        --Avoid infinite loops
        if visited[obj] then
            return nil
        end
        visited[obj] = true
        
        --Check if this object has the guid we're looking for (check both guid and id fields)
        if rawget(obj, "guid") == targetGuid or rawget(obj, "id") == targetGuid then
            --Return the parent instead of the object itself
            return parent
        end
        
        --Recursively search in child objects
        for k, v in pairs(obj) do
            if type(v) == "table" and not string.starts_with(tostring(k), "_tmp") then
                local result = FindInObject(v, targetGuid, visited, obj)
                if result then
                    return result
                end
            end
        end
        
        return nil
    end
    
    --Search through all tables in the system
    local tables = dmhub.GetTableTypes()
    for _, tableid in ipairs(tables) do
        local t = dmhub.GetTable(tableid) or {}
        for key, obj in unhidden_pairs(t) do
            --Check if the key itself matches the guid
            --If found at top level, return the object itself as it has no parent
            if key == guid then
                return obj, tableid
            end
            
            --recursively search within the object
            if type(obj) == "table" and not string.starts_with(tostring(key), "_tmp") then
                local visited = {}
                local result = FindInObject(obj, guid, visited, obj)
                if result then
                    return result, tableid
                end
            end
        end
    end
    
    return nil, nil
end

Commands.RegisterMacro{
    name = "updateimplementationvalues",
    summary = "fix implementation flags",
    doc = "Usage: /updateimplementationvalues\nScans all data tables and resets implementation=4 fields to 0.",
    command = function(str)
        local function UpdateInObject(obj, visited)
            if type(obj) ~= "table" then
                return
            end

            -- Avoid infinite loops
            if visited[obj] then
                return
            end
            visited[obj] = true

            -- Check if this object has implementation field with value 4
            if rawget(obj, "implementation") == 4 then
                print("Updating implementation for object:", json(obj))
                obj.implementation = 0
            end

            -- Recursively search in child objects
            for k, v in pairs(obj) do
                if type(v) == "table" and not string.starts_with(tostring(k), "_tmp") then
                    UpdateInObject(v, visited)
                end
            end
        end

        -- Search through all tables in the system
        local tables = dmhub.GetTableTypes()
        for _, tableid in ipairs(tables) do
            local t = dmhub.GetTable(tableid) or {}
            for key, obj in unhidden_pairs(t) do
                if type(obj) == "table" and not string.starts_with(tostring(key), "_tmp") then
                    local visited = {}
                    UpdateInObject(obj, visited)
                end
            end
        end
    end,
}

local function DeepCopyInternal(t, visited)
    local t_type = type(t)
    if t_type ~= "table" then
        if t_type == "userdata" then
            return dmhub.DeepCopy(t)
        end
        return t
    end

    if visited[t] then
        return visited[t]
    end

    local copy = {}
    visited[t] = copy
    for k, v in next, t do
	    if type(k) ~= "string" or string.sub(k,1,5) ~= "_tmp_" then
            copy[k] = DeepCopyInternal(v, visited)
        else
            copy[k] = v
        end
    end

    local mt = getmetatable(t)
    if mt ~= nil then
        setmetatable(copy, mt)
    end

    return copy
end

local g_profileDeepCopy = dmhub.ProfileMarker("LuaDeepCopy")
function DeepCopy(t)
    local _ = g_profileDeepCopy.Begin
    local result = DeepCopyInternal(t, {})
    local _ = g_profileDeepCopy.End
    return result
end

-- Checks whether a table contains any circular references.
-- Returns nil if no self-references are found.
-- Returns a string tracing the path of keys that form the cycle otherwise.
function DebugCheckTableSelfReference(t)
    local visited = {}

    local function check(obj, path)
        if type(obj) ~= "table" then
            return nil
        end

        if visited[obj] then
            return path .. " -> " .. visited[obj] .. " (cycle)"
        end

        visited[obj] = path

        for k, v in pairs(obj) do
            if type(k) == "string" and string.sub(k, 1, 5) == "_tmp_" then
                -- skip transient fields
            elseif type(v) == "table" then
                local key_str = tostring(k)
                local child_path = path .. "." .. key_str
                local result = check(v, child_path)
                if result then
                    return result
                end
            end
        end

        return nil
    end

    return check(t, "root")
end

-- Traceback helpers: parse a string returned by debug.traceback() into numbered frame
-- descriptors and produce a decorated version of the trace suitable for tooltips.
-- Mirrors the parsing in Assets/StyleDebuggerInterface.cs (the F7 panel inspector) so that
-- debug UIs can offer the same "hover to see the trace, press 1..9 to jump to that frame"
-- affordance, via dmhub.OpenModFileAtLine.
--
-- DMHub Lua chunks are loaded with a chunkname of "ModName : FileName", so tracebacks look
-- like:
--     [string "Draw Steel V : HeroesPanel"]:1304: in function ...
-- where the mod/file segment lives between the quotes and the line number is the integer
-- after the closing quote+bracket. Spaces around the inner colon are tolerated (and stripped).
--
-- Input:  any string, typically debug.traceback() output.
-- Output: a table with:
--           .decorated : the trace with each `[string "` rewritten to `[N string "` so the
--                        user can visually associate each frame with a number key.
--           .frames    : array (1-based) of { mod = string, file = string, line = number }
--                        up to 9 entries. Index is the number the user presses.
function FormatTracebackForDebug(trace)
    local result = { decorated = trace, frames = {} }
    if type(trace) ~= "string" or trace == "" then
        return result
    end

    local function trim(s) return (s:match("^%s*(.-)%s*$")) end

    local decoratedParts = {}
    local cursor = 1
    local n = 1

    while true do
        -- Find the next `[string "IDENT"]:LINE` header. IDENT is everything up to the
        -- next closing quote; LINE is the digits after `]:`.
        local headStart, quoteEnd, ident, line = string.find(trace, '%[string "([^"]*)"%]:(%d+)', cursor)
        if headStart == nil then
            decoratedParts[#decoratedParts + 1] = string.sub(trace, cursor)
            break
        end

        -- Emit everything up to the match verbatim.
        decoratedParts[#decoratedParts + 1] = string.sub(trace, cursor, headStart - 1)

        local colonPos = string.find(ident, ":", 1, true)
        local modName = colonPos and trim(string.sub(ident, 1, colonPos - 1)) or nil
        local fileName = colonPos and trim(string.sub(ident, colonPos + 1)) or nil
        local lineNum = tonumber(line)

        if modName and fileName and lineNum and modName ~= "" and fileName ~= "" and n <= 9 then
            result.frames[n] = { mod = modName, file = fileName, line = lineNum }
            -- Rewrite: `[string "IDENT"]:LINE` -> `[N] [string "IDENT"]:LINE`
            decoratedParts[#decoratedParts + 1] = string.format('[%d] [string "%s"]:%d', n, ident, lineNum)
            n = n + 1
        else
            -- Couldn't parse cleanly; leave verbatim.
            decoratedParts[#decoratedParts + 1] = string.sub(trace, headStart, quoteEnd)
        end

        cursor = quoteEnd + 1
    end

    result.decorated = table.concat(decoratedParts)
    return result
end

-- Given a parsed traceback (output of FormatTracebackForDebug), open frame N (1-based) in
-- the user's default editor. Returns true if the open request was issued.
-- Tolerant of older DMHub builds that don't yet have dmhub.OpenModFileAtLine: prints a
-- helpful message and returns false instead of raising a nil-call error.
function OpenTracebackFrame(parsed, n)
    if type(parsed) ~= "table" or type(parsed.frames) ~= "table" then return false end
    local f = parsed.frames[n]
    if f == nil then
        print(string.format("OpenTracebackFrame: no frame #%d (have %d)", n, #parsed.frames))
        return false
    end
    if type(dmhub.OpenModFileAtLine) ~= "function" then
        print("OpenTracebackFrame: dmhub.OpenModFileAtLine is missing -- requires a C# rebuild.")
        return false
    end
    local ok = dmhub.OpenModFileAtLine(f.mod, f.file, f.line)
    print(string.format("OpenTracebackFrame: #%d %s/%s:%d -> %s",
        n, tostring(f.mod), tostring(f.file), f.line, tostring(ok)))
    return ok == true
end
