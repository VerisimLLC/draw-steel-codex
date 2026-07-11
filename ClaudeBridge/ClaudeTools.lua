local mod = dmhub.GetModLoading()

-- search_reference tool: searches the Draw Steel reference books for relevant content.
--
-- The reference text is stored in ClaudeRef.heroes and ClaudeRef.monsters as large strings
-- with page markers like "--- Page 42 ---". This tool does case-insensitive keyword search
-- and returns surrounding context for each match.

local g_contextLines = 30   -- lines of context before and after each match
local g_maxResults = 5      -- max number of match regions to return
local g_maxResultLength = 8000 -- max total characters in the result

local function SplitLines(text)
    local lines = {}
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        lines[#lines+1] = line
    end
    return lines
end

-- Search a body of text for a query. Returns a string with matching excerpts.
-- query is split into keywords; lines matching any keyword are included with context.
local function SearchText(lines, query, bookName)
    local keywords = {}
    for word in string.gmatch(string.lower(query), "%S+") do
        -- Skip very short words
        if #word >= 3 then
            keywords[#keywords+1] = word
        end
    end

    if #keywords == 0 then
        return nil
    end

    -- Score each line by how many keywords it contains
    local matchLines = {}
    for i, line in ipairs(lines) do
        local lower = string.lower(line)
        local score = 0
        for _, kw in ipairs(keywords) do
            if string.find(lower, kw, 1, true) then
                score = score + 1
            end
        end
        if score > 0 then
            matchLines[#matchLines+1] = { index = i, score = score }
        end
    end

    -- Sort by score descending
    table.sort(matchLines, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.index < b.index
    end)

    -- Collect context regions around the best matches, merging overlaps
    local regions = {}
    local used = {}

    for _, match in ipairs(matchLines) do
        if #regions >= g_maxResults then
            break
        end

        local startLine = math.max(1, match.index - g_contextLines)
        local endLine = math.min(#lines, match.index + g_contextLines)

        -- Check if this overlaps with an existing region
        local merged = false
        for _, region in ipairs(regions) do
            if startLine <= region.endLine + 5 and endLine >= region.startLine - 5 then
                region.startLine = math.min(region.startLine, startLine)
                region.endLine = math.max(region.endLine, endLine)
                if match.score > region.score then
                    region.score = match.score
                end
                merged = true
                break
            end
        end

        if not merged and not used[match.index] then
            regions[#regions+1] = {
                startLine = startLine,
                endLine = endLine,
                score = match.score,
                matchLine = match.index,
            }
        end

        -- Mark lines as used to avoid near-duplicate regions
        for j = startLine, endLine do
            used[j] = true
        end
    end

    if #regions == 0 then
        return nil
    end

    -- Sort regions by position in the document
    table.sort(regions, function(a, b)
        return a.startLine < b.startLine
    end)

    -- Build output
    local parts = {}
    local totalLen = 0

    for _, region in ipairs(regions) do
        local chunk = {}
        for i = region.startLine, region.endLine do
            chunk[#chunk+1] = lines[i]
        end
        local text = string.format("[%s, around line %d]\n%s", bookName, region.matchLine, table.concat(chunk, "\n"))

        if totalLen + #text > g_maxResultLength then
            break
        end

        parts[#parts+1] = text
        totalLen = totalLen + #text
    end

    return table.concat(parts, "\n\n---\n\n")
end

-- Cached line arrays (built on first search)
local g_heroesLines = nil
local g_monstersLines = nil

local function GetHeroesLines()
    if g_heroesLines == nil and ClaudeRef.heroes then
        g_heroesLines = SplitLines(ClaudeRef.heroes)
    end
    return g_heroesLines
end

local function GetMonstersLines()
    if g_monstersLines == nil and ClaudeRef.monsters then
        g_monstersLines = SplitLines(ClaudeRef.monsters)
    end
    return g_monstersLines
end

claude.RegisterTool{
    name = "search_reference",
    description = "Search the Draw Steel rulebooks for information. Searches through the Heroes book (character creation, ancestries, classes, abilities, rules, equipment, conditions) and the Monsters book (monster stat blocks, abilities, traits, encounter building). Returns relevant excerpts with surrounding context. Use specific keywords for best results -- e.g. 'Goblin Warrior Spear' or 'Tactician Flanking Strike' rather than broad queries.",
    input_schema = {
        type = "object",
        properties = {
            query = {
                type = "string",
                description = "Search keywords. Use specific terms like monster names, ability names, class names, or rule terms.",
            },
            book = {
                type = "string",
                enum = { "heroes", "monsters", "both" },
                description = "Which book to search: 'heroes' for rules/classes/ancestries/equipment, 'monsters' for monster stat blocks and abilities, 'both' to search everything. Default: 'both'.",
            },
        },
        required = { "query" },
    },

    execute = function(input)
        local query = input.query
        if query == nil or query == "" then
            return "Error: query is required"
        end

        local book = input.book or "both"
        local results = {}

        if book == "heroes" or book == "both" then
            local lines = GetHeroesLines()
            if lines then
                local found = SearchText(lines, query, "Heroes")
                if found then
                    results[#results+1] = found
                end
            end
        end

        if book == "monsters" or book == "both" then
            local lines = GetMonstersLines()
            if lines then
                local found = SearchText(lines, query, "Monsters")
                if found then
                    results[#results+1] = found
                end
            end
        end

        if #results == 0 then
            return string.format("No results found for '%s' in %s.", query, book)
        end

        return table.concat(results, "\n\n===\n\n")
    end,
}
