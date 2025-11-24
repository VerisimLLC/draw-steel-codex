--- Business logic and game rule calculations for downtime system
--- Domain-specific operations for projects, characters, and game mechanics
--- @class DTBusinessRules
DTBusinessRules = RegisterGameType("DTBusinessRules")

--- Calculates the language penalty based on whether any known language
--- is in the list of required or related to any in the list of required
--- @param required string[] List of candidate required language ids
--- @param known string[] list of known language ids
--- @return string penalty The penalty level
function DTBusinessRules.CalcLangPenalty(required, known)
    local penalty = DTConstants.LANGUAGE_PENALTY.NONE.key

    if #required > 0 then
        penalty = DTConstants.LANGUAGE_PENALTY.UNKNOWN.key
        local langRels = dmhub.GetTableVisible(LanguageRelation.tableName)
        for _, reqId in ipairs(required) do
            -- Do we know the language?
            if known[reqId]  then
                penalty = DTConstants.LANGUAGE_PENALTY.NONE.key
                break
            -- Or do we have a related language?
            elseif langRels[reqId] then
                for relId, _ in pairs(langRels[reqId].related) do
                    if known[relId] then
                        penalty = DTConstants.LANGUAGE_PENALTY.RELATED.key
                        break
                    end
                end
            end
        end
    end

    return penalty
end

--- Determines whether the character represented has the requisite item
--- Checks ancestry name, class name, subclass name, and career name
--- @param tokenId string The unique identifier of the token to evaluate
--- @param requisite string The string to check for
--- @return boolean hasRequisite Whether the character meets the criteria
function DTBusinessRules.CharacterHasRequisite(tokenId, requisite)
    if not tokenId or #tokenId == 0 or not requisite or #requisite == 0 then return false end
    local lowerRequisite = requisite:lower()
    local hasRequisite = false

    local token = dmhub.GetCharacterById(tokenId)
    if token and token.properties then
        local character = token.properties

        local ancestry = character:AncestryOrInheritedAncestry()
        if ancestry then
            if ancestry.name:lower() == lowerRequisite then return true end
        end

        local classes = character:GetClassesAndSubClasses()
        if classes then
            for _, entry in ipairs(classes) do
                if entry.class.name:lower() == lowerRequisite then return true end
            end
        end

        local career = character:Background()
        if career then
            if career.name:lower() == lowerRequisite then return true end
        end
    end

    return hasRequisite
end

--- Determines if the project meets the requisite.
--- 
--- **Rules:**
---   - If any roller meets the requisite, then the project meets the requisite.
---   - If there are no rollers and the project owner meets the requisite,
---     then the project meets the requisite.
--- @param project DTProject The project to check
--- @param requisite string The string to check for
--- @return boolean meetsRequisite Whether the project meets the requisite
function DTBusinessRules.ProjectMeetsRequisite(project, requisite)
    if not project or not requisite or #requisite == 0 then return false end
    local meetsRequisite = false

    local uniqueRollers = project:GetUniqueRollers()
    if #uniqueRollers > 0 then
        for _, tokenId in ipairs(uniqueRollers) do
            meetsRequisite = DTBusinessRules.CharacterHasRequisite(tokenId, requisite)
            if meetsRequisite then break end
        end
    else
        meetsRequisite = DTBusinessRules.CharacterHasRequisite(project:GetOwnerID(), requisite)
    end

    return meetsRequisite
end

--- Gets all the tokens in the game that are heroes
--- @param filter? function Filter callback to apply, called on token object, added if return is true
--- @return table heroes The list of heroes in the game
function DTBusinessRules.GetAllHeroTokens(filter)
    if filter and type(filter) ~= "function" then error("arg1 must be nil or a function") end

    -- Use iterator with no-op callback that never triggers early exit
    return DTBusinessRules.IterateHeroTokens(function() return false end, filter)
end

--- Return the list of languages applied to all characters via global rules
--- @return table languages Flag table of language ID's
function DTBusinessRules.GetGlobalLanguages()
    local languages = {}
    local globalRules = dmhub.GetTable(GlobalRuleMod.TableName)
    for _, rule in pairs(globalRules) do
        if rule:try_get("modifierInfo") and rule.modifierInfo:try_get("features") then
            for _, feature in pairs(rule.modifierInfo.features) do
                if feature.typeName == "CharacterFeature" and feature:try_get("modifiers") then
                    for _, modifier in ipairs(feature.modifiers) do
                        if modifier:try_get("subtype") and modifier.typeName == "CharacterModifier" and modifier.subtype == "language" and modifier:try_get("skills") then
                            DTHelpers.MergeFlagLists(languages, modifier.skills, true)
                        end
                    end
                end
            end
        end
    end
    return languages
end

--- Adds the item, in the correct quantity, to the character's inventory
--- Parses the item's project goal to determine quantity, which can be as complex as
--- `45 (yields 1d3 darts, or three darts if crafted by a shadow)`.
--- @param project DTProject The project whose completion generated the item
function DTBusinessRules.GiveItemToCharacter(project)
    if not project then return end

    local itemId = project:GetItemID()
    local tokenId = project:GetOwnerID()
    if itemId == nil or #itemId == 0 or tokenId == nil or #tokenId == 0 then return end

    local item = dmhub.GetTableVisible(equipment.tableName)[itemId]
    if item then
        local token = dmhub.GetTokenById(tokenId)
        if token and token.properties then
            local qty = 1

            -- Qty, roll for qty, and other reqs can be buried in the item's project goal
            local projectGoal = item:try_get("projectGoal") or ""
            local projectGoalParser = "(?i)^\\d+\\s*\\(yields\\s+(?<dieRoll>\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?)[^,]*(?:,\\s*or\\s+(?<yield>\\S+))?.*?(?:if\\s+crafted\\s+by\\s+a\\s+(?<condition>[^)]+))?\\)$" --"(?i)^\\d+\\s*\\(yields\\s+(?<dieRoll>\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?).*?(?:,\\s*or\\s+(?<yield>\\S+))?.*?(?:if\\s+crafted\\s+by\\s+a\\s+(?<condition>[^)]+))?\\)$"
            local parseResult = regex.MatchGroups(projectGoal, projectGoalParser)
            if parseResult then
                if parseResult.dieRoll then
                    qty = dmhub.RollInstant(parseResult.dieRoll)
                end
                if parseResult.yield and parseResult.condition then
                    if DTBusinessRules.ProjectMeetsRequisite(project, parseResult.condition) then
                        if DTHelpers.IsNumeric(parseResult.yield) then
                            qty = tonumber(parseResult.yield)
                        else
                            local numbersTable = { ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4, ["five"] = 5, ["six"] = 6, ["seven"] = 7, ["eight"] = 8, ["nine"] = 9, ["ten"] = 10, }
                            local x = numbersTable[parseResult.yield]
                            if x and DTHelpers.IsNumeric(x) then
                                qty = x
                            end
                        end
                    end
                end
            end

            token:ModifyProperties {
                description = "Grant Item from Crafting",
                undoable = false,
                execute = function()
                    token.properties:GiveItem(itemId, qty)
                end
            }
        end
    end
end

--- Iterates through all hero tokens in the game, calling a callback for each
--- Searches party members, unaffiliated tokens, and despawned tokens
--- Stops iteration immediately if callback returns true
--- @param callback function Callback invoked for each hero: callback(hero) - return true to stop iteration
--- @param filter? function Optional filter callback to pre-filter heroes before iteration
--- @return table heroes The list of heroes accumulated before iteration stopped (or all if not stopped)
function DTBusinessRules.IterateHeroTokens(callback, filter)
    if not callback or type(callback) ~= "function" then error("arg1 must be a function") end
    if filter and type(filter) ~= "function" then error("arg2 must be nil or a function") end

    local heroes = {}

    -- Iterate through party members
    local partyTable = dmhub.GetTable(Party.tableName)
    for partyId, _ in pairs(partyTable) do
        local characterIds = dmhub.GetCharacterIdsInParty(partyId)
        for _, characterId in ipairs(characterIds) do
            local character = dmhub.GetCharacterById(characterId)
            if character and character.properties and character.properties:IsHero() then
                if filter == nil or filter(character) then
                    heroes[#heroes + 1] = character
                    if callback(character) then
                        return heroes
                    end
                end
            end
        end
    end

    -- Also get unaffiliated characters (director controlled on current map)
    local unaffiliatedTokens = dmhub.GetTokens{ unaffiliated = true }
    for _, token in ipairs(unaffiliatedTokens) do
        local character = dmhub.GetCharacterById(token.charid)
        if character and character.properties and character.properties:IsHero() then
            if filter == nil or filter(character) then
                heroes[#heroes + 1] = character
                if callback(character) then
                    return heroes
                end
            end
        end
    end

    -- Optionally include despawned characters from graveyard
    local despawnedTokens = dmhub.despawnedTokens or {}
    for _, token in ipairs(despawnedTokens) do
        local character = dmhub.GetCharacterById(token.charid)
        if character and character.properties and character.properties:IsHero() then
            if filter == nil or filter(character) then
                heroes[#heroes + 1] = character
                if callback(character) then
                    return heroes
                end
            end
        end
    end

    return heroes
end

--- Gets all projects shared with a recipient along with owner information
--- @param recipientId string The token ID of the character receiving shares
--- @return table sharedProjects Array of {project, ownerId, ownerName} or empty array if none
function DTBusinessRules.GetSharedProjectsForRecipient(recipientId)
    -- Validate input
    if not recipientId or type(recipientId) ~= "string" or #recipientId == 0 then
        return {}
    end

    -- Get shares for this recipient
    local shares = DTShares:new()
    local sharedWith = shares:GetSharedWith(recipientId)
    if not sharedWith or not next(sharedWith) then
        return {}
    end

    -- Build array of shared projects with owner info
    local sharedProjects = {}
    for projectId, ownerId in pairs(sharedWith) do
        -- Get owner token (may be nil if character was deleted)
        local ownerToken = dmhub.GetCharacterById(ownerId)
        if ownerToken then
            local ownerName = ownerToken.name
            local ownerColor = ownerToken.playerColor and ownerToken.playerColor.tostring or nil

            local ownerDTInfo = ownerToken.properties:GetDowntimeInfo()
            if ownerDTInfo then
                local project = ownerDTInfo:GetProject(projectId)
                if project then
                    sharedProjects[#sharedProjects + 1] = {
                        project = project,
                        ownerId = ownerId,
                        ownerName = ownerName,
                        ownerColor = ownerColor
                    }
                end
            end
        end
    end

    return sharedProjects
end

--- Finds languages in the text and returns their id's
--- @param text string Text that may or may not have language names embedded
--- @return table langIds List of language id's of language names found in the table
function DTBusinessRules.ExtractLanguagesToIds(text)
    local langIds = {}
    if not text or #text == 0 then
        return langIds
    end

    -- Normalize: lowercase and pad with spaces for consistent boundary checking
    local lowerText = " " .. string.lower(text) .. " "

    local langs = dmhub.GetTableVisible(Language.tableName)

    for id, item in pairs(langs) do
        if item.name and #item.name > 0 then
            local lowerLangName = string.lower(item.name)

            -- Escape special pattern characters in the language name
            local escapedName = string.gsub(lowerLangName, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

            -- Build pattern: non-letter before, language name, non-letter after
            -- %A matches any non-letter character (includes spaces, punctuation, etc.)
            local pattern = "%A" .. escapedName .. "%A"

            -- Search for the pattern in normalized text
            if string.find(lowerText, pattern) then
                langIds[#langIds + 1] = id
            end
        end
    end

    return langIds
end
