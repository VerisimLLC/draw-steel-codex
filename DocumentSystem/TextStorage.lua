local mod = dmhub.GetModLoading()

local g_keyChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

local g_numToKeyChar = {}

for i=1,#g_keyChars do
    local c = g_keyChars:sub(i,i)
    g_numToKeyChar[i] = c
end

local g_charToNum = {}
for i=1,#g_keyChars do
    local c = g_keyChars:sub(i,i)
    g_charToNum[c] = i
end

local function split_lines(text)
    local lines = {}
    local pos = 1

    while true do
        local start_pos, end_pos = text:find("\n", pos, true)

        if start_pos then
            -- Include the newline in the returned line
            table.insert(lines, text:sub(pos, end_pos))
            pos = end_pos + 1
        else
            -- No newline found: final chunk
            if pos <= #text then
                -- Add remaining text WITHOUT a newline
                table.insert(lines, text:sub(pos))
            end
            break
        end
    end

    return lines
end


local function common_prefix_length(a, b)
    local len = 0
    local max = math.min(#a, #b)
    for i = 1, max do
        if a:sub(i, i) == b:sub(i, i) then
            len = len + 1
        else
            break
        end
    end
    return len
end

local function common_suffix_length(a, b)
    local len = 0
    local ai, bi = #a, #b

    while ai > 0 and bi > 0 do
        if a:byte(ai) ~= b:byte(bi) then
            break
        end
        len = len + 1
        ai = ai - 1
        bi = bi - 1
    end

    return len
end

---@class TextStorage
TextStorage = RegisterGameType("TextStorage")

local function string_tween(a, b, r)
    r = r or 0.5
    local alist = {}
    local blist = {}
    for i=1,#a do
        alist[i] = g_charToNum[a:sub(i,i)]
    end
    for i=1,#b do
        blist[i] = g_charToNum[b:sub(i,i)]
    end

    local result = {}

    local diffs = 0
    for i=1,math.max(#alist, #blist) do
        local anum = alist[i] or 0
        local bnum = blist[i] or #g_keyChars + 1

        local cnum = math.floor(math.min(#g_keyChars, math.max(1, anum*(1-r) + bnum*r)))

        --make sure we always move toward the target if possible, regardless of the r.
        if cnum == anum and bnum > anum+1 then
            cnum = cnum + 1
        end
        if cnum == bnum and anum < bnum-1 then
            cnum = cnum - 1
        end
        if cnum ~= anum and cnum ~= bnum then
            diffs = diffs + 1
        end

        result[i] = g_numToKeyChar[cnum]
    end

    if diffs == 0 then
        result[#result+1] = g_numToKeyChar[math.min(#g_keyChars, math.max(1, math.floor(#g_keyChars*r)))]
    end

    local resultStr = ""
    for i=1,#result do
        resultStr = resultStr .. result[i]
    end

    --print("CONTENT:: TWEEN", a, b, r, " --> ", resultStr)
    return resultStr
end

local function CreateSections(str, beginKey, endKey)
    beginKey = beginKey or "A"
    endKey = endKey or "z"

    local strings = split_lines(str)

    local sections = {}
    for i=1,#strings do
        if #sections == 0 or #(strings[i]) > 3 or #(sections[#sections]) > 512 then
            sections[#sections+1] = strings[i]
        else
            sections[#sections] = sections[#sections] .. strings[i]
        end
    end

    local result = {}

    local key = beginKey

    for i=1,#sections do
        local remaining = (#sections - i)
        local r = 1/(remaining+2)
        key = string_tween(key, endKey, r)

        --string_tween's heuristic rounding can occasionally land on a key we
        --already placed in this result set. Overwriting it would silently drop
        --a whole section of the document (data loss on save). Instead, nudge the
        --key further toward endKey until it is unique. string_tween grows the
        --key length when it cannot advance within the current length, so it
        --always makes forward progress and keeps keys strictly ordered between
        --beginKey and endKey. The guard is a belt-and-suspenders bound against a
        --pathological non-terminating case; in practice a unique key is found in
        --one or two iterations.
        local guard = 0
        while result[key] ~= nil and guard < 64 do
            key = string_tween(key, endKey, 0.5)
            guard = guard + 1
        end

        result[key] = sections[i]
    end

    return result
end

function TextStorage.Create(str)

    local result = TextStorage.new{
        sections = {},
    }

    if str ~= nil and str ~= "" then
        result:SetContent(str)
    end

    return result
end

function TextStorage:GetContent()
    local keys = table.keys(self.sections)
    table.sort(keys)
    local result = ""
    for i,k in ipairs(keys) do
        result = result .. self.sections[k]
    end
    return result
end

function TextStorage:SetContent(str)
    local keys = table.keys(self.sections)
    table.sort(keys)

    --print("MERGE:: SET TEXT", str)

    local startSections = {}
    local endSections = {}

    local beginKey = nil
    local endKey = nil

    for i,key in ipairs(keys) do
        local sectionLen = #self.sections[key]
        if self.sections[key] == str:sub(1, sectionLen) then
            str = str:sub(sectionLen+1)
            startSections[#startSections+1] = key
            beginKey = key
        else
            break
        end
    end

    for i=#keys,1,-1 do
        local sectionLen = #self.sections[keys[i]]

        local key = keys[i]
        if self.sections[key] == str:sub(-sectionLen) and beginKey ~= key then
            str = str:sub(1, -sectionLen-1)
            endSections[#endSections+1] = key
            endKey = key
        else
            break
        end
    end

    for i=#startSections+1,#keys-#endSections do
        local key = keys[i]
        self.sections[key] = nil
    end


    if str == "" then
        --print("MERGE:: string empty.", self.sections)
        return
    end

    local newSections = CreateSections(str, beginKey, endKey)

    --print("MERGE:: startSections =", json(startSections), "endSections =", json(endSections))

    --print("MERGE:: new sections:", json(str), "BECOMES", newSections)

    for k,v in pairs(newSections) do
        self.sections[k] = v
    end
end
