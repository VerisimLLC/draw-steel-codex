local mod = dmhub.GetModLoading()

--Stawl encounter importer: imports encounter JSON exports from Stawl into the
--Encounters panel. Registered as "Stawl Encounter (JSON)" in the Codex >
--Import dialog (input = files, so the user picks .json files or a folder).
--
--The Stawl export format (top-level keys):
--  name, description : encounter identity
--  heroes            : the party roster (ignored; Codex encounters are
--                      monster plans and the party comes from the game)
--  groups            : the initiative groups. Each group is
--                      { name, inPlay, monsters = { { name, count,
--                        monster = { name, level, organization, minion,
--                        ... } }, ... } }
--  terrainObjects, runState, ids/timestamps : ignored.
--
--Every groups[] entry is treated as a monster initiative group (heroes live
--in their own top-level array, so the groups are monsters by construction).
--
--Monsters are matched against the bestiary in two passes:
--  1. exact case-insensitive name match;
--  2. token-subset fuzzy match: the names are broken into lowercase word
--     sets, and a candidate matches when either set contains the other
--     ("Remasch" matches "Demon Remasch"). Candidates whose minion flag
--     contradicts the Stawl entry are vetoed; among the rest the candidate
--     with the fewest leftover words wins, with matching level and then
--     matching organization as tie-breakers. If no single best candidate
--     remains the entry is treated as unmatched and the near-misses are
--     listed as suggestions.
--Matches whose level differs from the Stawl entry are imported but flagged.
--Anything that cannot be matched (typically Stawl homebrew with no bestiary
--entry) is skipped and reported to the chat panel along with the initiative
--group it belonged to.
--
--On success the encounter is uploaded to the encounters table (so it appears
--in the Encounters panel immediately) and the encounter builder is opened on
--it for review.

local function Trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function NormalizeName(name)
    if type(name) ~= "string" then
        return ""
    end
    return string.lower(Trim(name))
end

--Breaks a name into a set of lowercase words. Returns the set and the number
--of distinct words in it.
local function TokenSet(name)
    local set = {}
    local count = 0
    for word in string.gmatch(string.lower(name), "%w+") do
        if set[word] == nil then
            set[word] = true
            count = count + 1
        end
    end
    return set, count
end

--True if every word of a appears in b.
local function IsSubset(a, b)
    for word in pairs(a) do
        if not b[word] then
            return false
        end
    end
    return true
end

--Sends a titled chat message when the extended chat module is available,
--falling back to a plain chat message. Mirrors the Import chat pattern used
--by the macro importers.
local function StawlChatMessage(text, isError)
    if ExtChatMessage ~= nil and ExtChatMessage.SendTitled ~= nil then
        local color = isError and "#ff4444" or "#44ff88"
        ExtChatMessage.SendTitled(text, "Stawl Import", color, dmhub.userid)
    else
        chat.Send(text)
    end
end

--Builds the bestiary lookup used for matching:
--  byName : normalized full name -> entry (exact matching)
--  list   : all entries with precomputed token sets and stats (fuzzy
--           matching). Each entry is { monsterid, asset, hidden, name,
--           tokens, tokenCount, minion, level, org }.
--Preference is given to non-hidden entries when several share a name. The
--stat fields are read defensively (pcall) since some compendium assets carry
--plain creature-typed properties where monster-only methods raise on read.
local function BuildBestiaryIndex()
    local byName = {}
    local list = {}

    for monsterid, monsterAsset in pairs(assets.monsters) do
        local displayName = creature.GetTokenDescription(monsterAsset)
        local name = NormalizeName(displayName)
        if name ~= "" then
            local hidden = false
            pcall(function()
                local node = assets:GetMonsterNode(monsterid)
                hidden = node ~= nil and node.hidden == true
            end)

            local tokens, tokenCount = TokenSet(name)

            local minion = nil
            local level = nil
            local org = nil
            pcall(function()
                local props = monsterAsset.properties
                if props ~= nil then
                    minion = props.minion == true
                    if props:IsMonster() then
                        level = props:Level()
                    end
                    local role = props:try_get("role")
                    if type(role) == "string" then
                        local firstWord = string.match(string.lower(role), "%a+")
                        if firstWord ~= nil then
                            org = firstWord
                        end
                    end
                end
            end)

            local entry = {
                monsterid = monsterid,
                asset = monsterAsset,
                hidden = hidden,
                name = Trim(displayName),
                tokens = tokens,
                tokenCount = tokenCount,
                minion = minion,
                level = level,
                org = org,
            }

            local existing = byName[name]
            if existing == nil or (existing.hidden and not hidden) then
                byName[name] = entry
            end

            list[#list + 1] = entry
        end
    end

    return { byName = byName, list = list }
end

--Finds the bestiary entry for a Stawl monster name.
--  bestiaryIndex : from BuildBestiaryIndex
--  name          : the Stawl monster name
--  stawlMonster  : the Stawl monster record (level/organization/minion), or nil
--Returns entry, matchKind ("exact"|"fuzzy"), suggestions.
--On no match, entry is nil and suggestions is a (possibly empty) list of
--near-miss bestiary names worth showing to the user.
local function FindBestiaryMatch(bestiaryIndex, name, stawlMonster)
    local normalized = NormalizeName(name)
    if normalized == "" then
        return nil, nil, {}
    end

    local exact = bestiaryIndex.byName[normalized]
    if exact ~= nil then
        return exact, "exact", nil
    end

    local stawlTokens, stawlTokenCount = TokenSet(normalized)
    if stawlTokenCount == 0 then
        return nil, nil, {}
    end

    local stawlMinion = nil
    local stawlLevel = nil
    local stawlOrg = nil
    if stawlMonster ~= nil then
        if type(stawlMonster.minion) == "boolean" then
            stawlMinion = stawlMonster.minion
        end
        stawlLevel = tonumber(stawlMonster.level)
        if type(stawlMonster.organization) == "string" then
            stawlOrg = string.match(string.lower(stawlMonster.organization), "%a+")
        end
    end

    --collect token-subset candidates, vetoing minion-flag contradictions.
    local candidates = {}
    for _, entry in ipairs(bestiaryIndex.list) do
        if IsSubset(stawlTokens, entry.tokens) or IsSubset(entry.tokens, stawlTokens) then
            local vetoed = stawlMinion ~= nil and entry.minion ~= nil and stawlMinion ~= entry.minion
            if not vetoed then
                candidates[#candidates + 1] = entry
            end
        end
    end

    if #candidates == 0 then
        return nil, nil, {}
    end

    --narrow: fewest leftover words, then matching level, then matching
    --organization, then prefer non-hidden entries.
    local function Narrow(pool, better)
        if #pool <= 1 then
            return pool
        end
        local best = nil
        local kept = {}
        for _, entry in ipairs(pool) do
            local score = better(entry)
            if best == nil or score < best then
                best = score
                kept = { entry }
            elseif score == best then
                kept[#kept + 1] = entry
            end
        end
        return kept
    end

    candidates = Narrow(candidates, function(entry)
        local leftover = entry.tokenCount - stawlTokenCount
        if leftover < 0 then
            leftover = -leftover
        end
        return leftover
    end)
    candidates = Narrow(candidates, function(entry)
        if stawlLevel ~= nil and entry.level ~= nil and stawlLevel == entry.level then
            return 0
        end
        return 1
    end)
    candidates = Narrow(candidates, function(entry)
        if stawlOrg ~= nil and entry.org ~= nil and stawlOrg == entry.org then
            return 0
        end
        return 1
    end)
    candidates = Narrow(candidates, function(entry)
        return entry.hidden and 1 or 0
    end)

    if #candidates == 1 then
        return candidates[1], "fuzzy", nil
    end

    --ambiguous: report the near-misses as suggestions rather than guessing.
    local suggestions = {}
    for i, entry in ipairs(candidates) do
        if i > 3 then
            break
        end
        suggestions[#suggestions + 1] = entry.name
    end
    return nil, nil, suggestions
end

--The display name used to reference a Stawl group in reports: the group's
--own name when set, otherwise its position ("Group 2").
local function GroupDisplayName(stawlGroup, index)
    if type(stawlGroup.name) == "string" and Trim(stawlGroup.name) ~= "" then
        return Trim(stawlGroup.name)
    end
    return string.format("Group %d", index)
end

--Builds the chat/log report for an import.
--stats: { encounterName, groupCount, monsterCount, failures, mismatches,
--         fuzzyMatches }
local function BuildReport(stats)
    local lines = {}

    if stats.groupCount > 0 then
        lines[#lines + 1] = string.format("Imported \"%s\" from Stawl: %d initiative group%s (%d monster%s).",
            stats.encounterName,
            stats.groupCount, stats.groupCount == 1 and "" or "s",
            stats.monsterCount, stats.monsterCount == 1 and "" or "s")
    else
        lines[#lines + 1] = string.format("Could not import \"%s\" from Stawl: no monsters matched the bestiary.",
            stats.encounterName)
    end

    if #stats.fuzzyMatches > 0 then
        lines[#lines + 1] = "Matched by name similarity:"
        for _, matchInfo in ipairs(stats.fuzzyMatches) do
            lines[#lines + 1] = string.format(" - %s -> %s (%s)", matchInfo.stawlName, matchInfo.bestiaryName, matchInfo.group)
        end
    end

    if #stats.failures > 0 then
        lines[#lines + 1] = "Could not import (not found in the bestiary):"
        for _, failure in ipairs(stats.failures) do
            local line = string.format(" - %s x%d (%s)", failure.name, failure.count, failure.group)
            if failure.suggestions ~= nil and #failure.suggestions > 0 then
                line = line .. " - did you mean: " .. table.concat(failure.suggestions, ", ") .. "?"
            end
            lines[#lines + 1] = line
        end
    end

    if #stats.mismatches > 0 then
        lines[#lines + 1] = "Level differs from the bestiary:"
        for _, mismatch in ipairs(stats.mismatches) do
            lines[#lines + 1] = string.format(" - %s: Stawl level %s, bestiary level %s (%s)",
                mismatch.name, tostring(mismatch.stawlLevel), tostring(mismatch.codexLevel), mismatch.group)
        end
    end

    return table.concat(lines, "\n")
end

--Imports one parsed Stawl encounter document. Returns true if the document
--was recognized as a Stawl encounter export (even if nothing could be
--matched), false otherwise.
local function ImportStawlEncounter(doc)
    if type(doc) ~= "table" or type(doc.groups) ~= "table" then
        import:Log("This does not look like a Stawl encounter export (no groups array).")
        return false
    end

    local bestiaryIndex = BuildBestiaryIndex()

    local encounterName = "Imported Encounter"
    if type(doc.name) == "string" and Trim(doc.name) ~= "" then
        encounterName = Trim(doc.name)
    end

    local groups = {}
    local failures = {}
    local mismatches = {}
    local fuzzyMatches = {}
    local monsterCount = 0

    for groupIndex, stawlGroup in ipairs(doc.groups) do
        if type(stawlGroup) == "table" and type(stawlGroup.monsters) == "table" then
            local groupName = GroupDisplayName(stawlGroup, groupIndex)
            local monsters = {}
            local haveMonsters = false

            --Stawl expresses minion squads as the row count (a row of count 8
            --is one squad of 8). Codex stores one squadSize per group
            --(default 4; spawning breaks quantity into ceil(quantity /
            --squadSize) squads), so carry over the largest minion row count
            --as the group's squad size. Mixed row sizes of the same minion in
            --one group (e.g. rows of 8 and 4) cannot be represented exactly;
            --the largest row wins.
            local maxMinionRowCount = 0

            for _, entry in ipairs(stawlGroup.monsters) do
                if type(entry) == "table" then
                    local stawlMonster = nil
                    if type(entry.monster) == "table" then
                        stawlMonster = entry.monster
                    end

                    local name = entry.name
                    if type(name) ~= "string" or Trim(name) == "" then
                        name = stawlMonster ~= nil and stawlMonster.name or nil
                    end

                    local count = tonumber(entry.count) or 1
                    if count < 1 then
                        count = 1
                    end

                    local match = nil
                    local matchKind = nil
                    local suggestions = nil
                    if name ~= nil then
                        match, matchKind, suggestions = FindBestiaryMatch(bestiaryIndex, name, stawlMonster)
                    end

                    if match ~= nil then
                        --duplicate rows of the same monster within a group sum together.
                        monsters[match.monsterid] = (monsters[match.monsterid] or 0) + count
                        haveMonsters = true
                        monsterCount = monsterCount + count

                        if matchKind == "fuzzy" then
                            fuzzyMatches[#fuzzyMatches + 1] = {
                                stawlName = Trim(name),
                                bestiaryName = match.name,
                                group = groupName,
                            }
                        end

                        local isMinion = match.minion == true
                        if not isMinion and stawlMonster ~= nil and stawlMonster.minion == true then
                            isMinion = true
                        end
                        if isMinion and count > maxMinionRowCount then
                            maxMinionRowCount = count
                        end

                        local stawlLevel = stawlMonster ~= nil and tonumber(stawlMonster.level) or nil
                        if stawlLevel ~= nil and match.level ~= nil and stawlLevel ~= match.level then
                            mismatches[#mismatches + 1] = {
                                name = Trim(name),
                                stawlLevel = stawlLevel,
                                codexLevel = match.level,
                                group = groupName,
                            }
                        end
                    else
                        failures[#failures + 1] = {
                            name = name ~= nil and Trim(name) or "(unnamed monster)",
                            count = count,
                            group = groupName,
                            suggestions = suggestions,
                        }
                    end
                end
            end

            if haveMonsters then
                local group = { monsters = monsters }
                if type(stawlGroup.name) == "string" and Trim(stawlGroup.name) ~= "" then
                    group.name = Trim(stawlGroup.name)
                end
                if maxMinionRowCount > 4 then
                    group.squadSize = maxMinionRowCount
                end
                groups[#groups + 1] = group
            end
        end
    end

    local stats = {
        encounterName = encounterName,
        groupCount = #groups,
        monsterCount = monsterCount,
        failures = failures,
        mismatches = mismatches,
        fuzzyMatches = fuzzyMatches,
    }

    local report = BuildReport(stats)
    for line in string.gmatch(report, "[^\n]+") do
        import:Log(line)
    end

    if #groups == 0 then
        --nothing matched: report the failure to chat so the Director sees it
        --without digging into the import dialog log.
        StawlChatMessage(report, true)
        return true
    end

    local encounter = Encounter.new{
        name = encounterName,
        groups = groups,
    }
    if type(doc.description) == "string" and Trim(doc.description) ~= "" then
        encounter.description = doc.description
    end

    --upload immediately so the encounter appears in the Encounters panel; the
    --returned id is stored on the object so saves from the builder update this
    --entry rather than creating a duplicate.
    encounter.id = dmhub.SetAndUploadTableItem(Encounter.tableName, encounter)

    StawlChatMessage(report, #failures > 0)

    --open the encounter builder on the imported encounter for review. "Save"
    --labels the save button correctly for an already-persisted encounter.
    if GameHud.instance ~= nil and Encounter.CreateEditorDialog ~= nil then
        Encounter.CreateEditorDialog(encounter, { mode = "Save" })
    end

    return true
end

if import ~= nil and import.Register ~= nil then
    import.Register{
        id = "stawlencounter",
        description = "Stawl Encounter (JSON)",
        input = "files",
        priority = 200,

        json = function(importer, doc)
            return ImportStawlEncounter(doc)
        end,
    }
end
