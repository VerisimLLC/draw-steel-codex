local mod = dmhub.GetModLoading()

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
    if depth > 16 then
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

function MatchesSearchRecursive(obj, search, depth)
    depth = depth or 0
    if depth > 16 then
        return false
    end
    if type(obj) == "table" then
        for k,v in pairs(obj) do
            if MatchesSearchRecursive(k, search, depth+1) or MatchesSearchRecursive(v, search, depth+1) then
                return true
            end
        end
    elseif type(obj) == "string" then
        --search without any pattern matching etc, just verbatim substring match
        if string.find(string.lower(obj), search, 1, true) ~= nil then
            return true
        end
    end

    return false
end

function SearchTableForText(t, search)
    local results = {}
    for k,v in unhidden_pairs(t) do
        if MatchesSearchRecursive(k, search) or MatchesSearchRecursive(v, search) then
            results[#results+1] = k
        end
    end

    return results
end

function DebugSearchTableForText(t, search, debugName)
    local results = {}
    for k,v in pairs(t) do
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
        value = dmhub.EvalGoblinScript(match.formula, symbols, "formula substitution")
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
        if (not info.loggedOut) and info.timeSinceLastContact < 30 then
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