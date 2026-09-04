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

--The digit value of the i'th char of a key, or nil past the end of the key.
local function key_digit(s, i)
    if s == nil or i > #s then
        return nil
    end
    return g_charToNum[s:sub(i,i)]
end

--Generates a key that sorts strictly between a and b.
--
--b == nil means "no upper bound". r in (0,1) biases the result toward a or b,
--but only shifts it within the room available -- it can never push the key onto
--or past either bound.
--
--Returns nil when no key can exist between a and b. That is only possible when
--b is a followed by minimum chars: nothing sorts between "M" and "MA". Keys
--this function returns never end in the minimum char, so any two of them always
--have room for another key between them; nil is therefore only reachable from
--keys written by the earlier generator, which did not guarantee that.
local function string_tween(a, b, r)
    r = r or 0.5

    if b ~= nil and a >= b then
        return nil
    end

    local prefix = ""

    --Strip the shared prefix, counting positions past the end of `a` as the
    --minimum digit. That padding is what collapses "M" and "MA" into a fully
    --shared prefix, correctly leaving no room between them.
    if b ~= nil then
        local n = 0
        while true do
            local bnum = key_digit(b, n+1)
            if bnum == nil or (key_digit(a, n+1) or 1) ~= bnum then
                break
            end
            n = n + 1
        end

        if n > 0 then
            prefix = b:sub(1, n)
            a = a:sub(n+1)
            b = b:sub(n+1)
            if a >= b then
                return nil
            end
        end
    end

    while true do
        local anum = key_digit(a, 1) or 1
        local bnum = (b ~= nil and key_digit(b, 1)) or (#g_keyChars + 1)

        if bnum - anum > 1 then
            --There is room at this position: land between the two digits.
            local cnum = math.floor(anum + (bnum - anum)*r + 0.5)
            cnum = math.max(anum + 1, math.min(bnum - 1, cnum))
            return prefix .. g_numToKeyChar[cnum]
        end

        if b ~= nil and #b > 1 then
            --The digits are adjacent, but b continues past this one, so b's
            --first digit on its own sorts between a and b.
            return prefix .. b:sub(1,1)
        end

        --b is unbounded, or a lone digit adjacent to a's: keep a's digit and
        --look for room further to the right.
        prefix = prefix .. g_numToKeyChar[anum]
        a = a:sub(2)
        b = nil
    end
end

--Splits str into sections keyed strictly between beginKey and endKey.
--
--Returns nil when the key space between those two bounds cannot hold the
--sections; the caller heals that by re-keying the whole document.
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
        local nextKey = string_tween(key, endKey, r)

        --Check the ordering invariant rather than trusting it. A key that is not
        --strictly between its predecessor and endKey sorts into the wrong place,
        --which silently scrambles the document on save and leaves it corrupt at
        --rest. Bail out instead and let the caller re-key the document.
        if nextKey == nil or nextKey <= key or nextKey >= endKey then
            return nil
        end

        --Keys increase strictly, so this can never overwrite an earlier section.
        key = nextKey
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
    --The full text as requested, kept aside because str is trimmed down to just
    --the changed span below. The re-key path needs the whole document.
    local fullStr = str

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

    if newSections == nil then
        --Documents written before the key generator guaranteed strict ordering
        --can hold neighbouring keys with no room between them (e.g. "M" and
        --"MA"). Re-key the whole document from its full text: the content is
        --unchanged, but the keys come back strictly ordered, so this and every
        --later edit has somewhere to go. Every key changes, so this uploads the
        --whole document -- it happens once, to heal a document, and never for
        --one written by the current generator.
        --
        --Rebuilding against the default bounds cannot fail, but never leave the
        --document empty if it somehow did: one section holding the whole text is
        --always valid, just unsharded.
        self.sections = CreateSections(fullStr) or { B = fullStr }
        return
    end

    --print("MERGE:: startSections =", json(startSections), "endSections =", json(endSections))

    --print("MERGE:: new sections:", json(str), "BECOMES", newSections)

    for k,v in pairs(newSections) do
        self.sections[k] = v
    end
end
