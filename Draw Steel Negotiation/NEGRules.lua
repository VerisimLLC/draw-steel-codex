local mod = dmhub.GetModLoading()

--- The published negotiation rules, as data: the trait catalog, the starting
--- attitudes, the offer an interest score buys, and the language rule. Nothing
--- here draws anything.
NEGRules = RegisterGameType("NEGRules")

--- The twelve traits, in the order the rulebook lists them. The same list
--- serves motivations and pitfalls: what motivates one NPC is a pitfall for
--- another, so a trait is one or the other for a given NPC, never both.
NEGRules.traits = {
    { id = "benevolence", text = "Benevolence" },
    { id = "discovery", text = "Discovery" },
    { id = "freedom", text = "Freedom" },
    { id = "greed", text = "Greed" },
    { id = "higherauthority", text = "Higher Authority" },
    { id = "justice", text = "Justice" },
    { id = "legacy", text = "Legacy" },
    { id = "peace", text = "Peace" },
    { id = "power", text = "Power" },
    { id = "protection", text = "Protection" },
    { id = "revelry", text = "Revelry" },
    { id = "vengeance", text = "Vengeance" },
}

--- @param id string
--- @return string
function NEGRules.TraitName(id)
    for _, trait in ipairs(NEGRules.traits) do
        if trait.id == id then
            return trait.text
        end
    end
    return tostring(id)
end

--- @param id string
--- @return boolean
function NEGRules.IsTrait(id)
    for _, trait in ipairs(NEGRules.traits) do
        if trait.id == id then
            return true
        end
    end
    return false
end

--- Resolve a trait by id or by display name, for import.
--- @param value any
--- @return string|nil id
function NEGRules.ResolveTrait(value)
    if type(value) ~= "string" then
        return nil
    end
    local needle = string.lower(trim(value))
    for _, trait in ipairs(NEGRules.traits) do
        if trait.id == needle or string.lower(trait.text) == needle then
            return trait.id
        end
    end
    return nil
end

--- Every trait the negotiation has not spent, plus the one this row already
--- holds so its own dropdown can still show it.
--- @param used table<string, boolean>
--- @param keep string|nil the caller's current pick
--- @return {id: string, text: string}[]
function NEGRules.TraitOptions(used, keep)
    used = used or {}
    local options = {}
    for _, trait in ipairs(NEGRules.traits) do
        if used[trait.id] ~= true or trait.id == keep then
            options[#options + 1] = { id = trait.id, text = trait.text }
        end
    end
    return options
end

--- Starting attitudes, with the interest and patience each opens on. The
--- Director may adjust both afterwards.
NEGRules.attitudes = {
    {
        id = "hostile",
        text = "Hostile",
        description = "Openly opposed to the heroes. Barely willing to listen.",
        interest = 1,
        patience = 2,
    },
    {
        id = "suspicious",
        text = "Suspicious",
        description = "Doubts the heroes' motives but is willing to listen.",
        interest = 2,
        patience = 2,
    },
    {
        id = "neutral",
        text = "Neutral",
        description = "Doesn't feel one way or the other. Would probably rather be somewhere else, but doesn't want to be rude.",
        interest = 2,
        patience = 3,
    },
    {
        id = "open",
        text = "Open",
        description = "Willing to listen, willing to help, as long as the heroes aren't asking too much.",
        interest = 3,
        patience = 3,
    },
    {
        id = "friendly",
        text = "Friendly",
        description = "The heroes seem like the NPC's people. The NPC is willing to give them the benefit of the doubt.",
        interest = 3,
        patience = 4,
    },
    {
        id = "trusting",
        text = "Trusting",
        description = "The NPC has reason to take the heroes at their word and will help if the characters don't screw this up.",
        interest = 3,
        patience = 5,
    },
}

--- @return {id: string, text: string}[]
function NEGRules.AttitudeOptions()
    local options = {}
    for _, attitude in ipairs(NEGRules.attitudes) do
        options[#options + 1] = { id = attitude.id, text = attitude.text }
    end
    return options
end

--- @param id string
--- @return table|nil
function NEGRules.AttitudeById(id)
    for _, attitude in ipairs(NEGRules.attitudes) do
        if attitude.id == id then
            return attitude
        end
    end
    return nil
end

--- Resolve an attitude by id or by display name, for import.
--- @param value any
--- @return string|nil id
function NEGRules.ResolveAttitude(value)
    if type(value) ~= "string" then
        return nil
    end
    local needle = string.lower(trim(value))
    for _, attitude in ipairs(NEGRules.attitudes) do
        if attitude.id == needle or string.lower(attitude.text) == needle then
            return attitude.id
        end
    end
    return nil
end

--- What an interest score buys, indexed by that score. Keyed 0..5 rather than
--- an array, because 0 is a real and terminal value here.
NEGRules.offers = {
    [0] = {
        text = "No, and...",
        detail = "Offers nothing, refuses to negotiate further, and seeks to harm the heroes.",
    },
    [1] = {
        text = "No.",
        detail = "Rejects the idea outright, with no counteroffer.",
    },
    [2] = {
        text = "No, but...",
        detail = "Cannot give what was asked, but offers lesser goods or services.",
    },
    [3] = {
        text = "Yes, but...",
        detail = "Gives what was asked, and asks for a little extra on top.",
    },
    [4] = {
        text = "Yes.",
        detail = "Gives everything asked for, on the terms the heroes offered.",
    },
    [5] = {
        text = "Yes, and...",
        detail = "Gives everything asked for, and sweetens the deal.",
    },
}

--- @param interest number
--- @return string
function NEGRules.OfferName(interest)
    local entry = NEGRules.offers[NEGConstants.Clamp(interest,
        NEGConstants.scaleMin, NEGConstants.scaleMax)]
    return entry ~= nil and entry.text or ""
end

--- @param interest number
--- @return string
function NEGRules.OfferDetail(interest)
    local entry = NEGRules.offers[NEGConstants.Clamp(interest,
        NEGConstants.scaleMin, NEGConstants.scaleMax)]
    return entry ~= nil and entry.detail or ""
end

--- What an argument roll does to the NPC, per Appeal to Motivation and No
--- Motivation or Pitfall.
--- @param tier number
--- @param motivation boolean whether the argument appealed to a motivation
--- @param naturalRoll number|nil
--- @return {interest: number, patience: number, text: string}
function NEGRules.ArgumentOutcome(tier, motivation, naturalRoll)
    if motivation then
        if tier >= 3 then
            return { interest = 1, patience = 0, text = "Interest +1. Patience holds." }
        end
        if tier == 2 then
            return { interest = 1, patience = -1, text = "Interest +1, patience -1." }
        end
        return { interest = 0, patience = -1, text = "Patience -1." }
    end

    local spared = (naturalRoll or 0) >= 19
    local patience = cond(spared, 0, -1)
    local sparedNote = cond(spared, " Natural 19+, so patience holds.", "")

    if tier >= 3 then
        return {
            interest = 1,
            patience = patience,
            text = string.format("Interest +1.%s", cond(spared, sparedNote, " Patience -1.")),
        }
    end
    if tier == 2 then
        return {
            interest = 0,
            patience = patience,
            text = cond(spared, "No change." .. sparedNote, "Patience -1."),
        }
    end
    return {
        interest = -1,
        patience = patience,
        text = string.format("Interest -1.%s", cond(spared, sparedNote, " Patience -1.")),
    }
end

--- What a read-the-room roll does, per Uncovering Motivations. Only a failure
--- costs anything; a success is information, which the Director hands over by
--- opening an eye rather than by moving a scale.
--- @param tier number
--- @return {interest: number, patience: number, text: string}
function NEGRules.LearnOutcome(tier)
    if tier >= 3 then
        return {
            interest = 0,
            patience = 0,
            text = "They learn one motivation or pitfall, their choice. Reveal it.",
        }
    end
    if tier == 2 then
        return { interest = 0, patience = 0, text = "Nothing learned." }
    end
    return {
        interest = 0,
        patience = -1,
        text = "Nothing learned, and the NPC noticed the reading. Patience -1.",
    }
end

--- The three tier outcomes a roller can be shown, as real text.
--- @param track string
--- @param motivation boolean
--- @return string[]
function NEGRules.TierText(track, motivation)
    local tiers = {}
    for tier = 1, 3 do
        if track == NEGConstants.trackLearn then
            tiers[tier] = NEGRules.LearnOutcome(tier).text
        else
            tiers[tier] = NEGRules.ArgumentOutcome(tier, motivation, 0).text
        end
    end
    return tiers
end

--- Impression scores with the rulebook's example NPCs, which is what makes the
--- number mean something. The examples lead with the most recognisable so the
--- closed dropdown still reads; none of the book's examples are dropped.
NEGRules.impressions = {
    { value = 1, text = "1 - Commoner, shop owner, brigand leader" },
    { value = 2, text = "2 - Knight, local guildmaster, professor" },
    { value = 3, text = "3 - Noble lord, cult leader, locally known mage" },
    { value = 4, text = "4 - Baron, assassin, locally famous entertainer" },
    { value = 5, text = "5 - Viscount, high priest, captain of the watch" },
    { value = 6, text = "6 - Count, warlord" },
    { value = 7, text = "7 - Marquis, world-renowned entertainer" },
    { value = 8, text = "8 - Duke, spymaster" },
    { value = 9, text = "9 - Prince, archmage" },
    { value = 10, text = "10 - Monarch, demon lord" },
    { value = 11, text = "11 - Archdevil, archfey, demigod" },
    { value = 12, text = "12 - Deity, titan" },
}

--- The score with its example NPCs, which is what makes the number mean
--- something at the table. A bare "1" is nobody's idea of memorable.
--- @param value number
--- @return string
function NEGRules.ImpressionText(value)
    for _, entry in ipairs(NEGRules.impressions) do
        if entry.value == value then
            return entry.text
        end
    end
    return tostring(value)
end

--- @return {id: string, text: string}[]
function NEGRules.ImpressionOptions()
    local options = {}
    for _, entry in ipairs(NEGRules.impressions) do
        options[#options + 1] = { id = tostring(entry.value), text = entry.text }
    end
    return options
end

--- Languages every hero already speaks, and so cannot be an NPC's native
--- language for the purposes of the patience rule. Derived, never hardcoded:
--- a global rule that grants a language proficiency to heroes is what makes a
--- language universal, and today that is Caelian.
--- @return table<string, boolean>
function NEGRules.UniversalLanguageIds()
    local result = {}

    for _, rule in unhidden_pairs(dmhub.GetTable(GlobalRuleMod.TableName) or {}) do
        --A rule that does not reach heroes leaves nothing universal behind,
        --and a disabled one reaches nobody.
        if rule:try_get("applyCharacters", false) then
            local level = rule:try_get("modifierInfo")
            for _, feature in ipairs(level ~= nil and level:try_get("features", {}) or {}) do
                for _, modifier in ipairs(feature:try_get("modifiers", {})) do
                    if modifier:try_get("behavior") == "proficiency"
                        and modifier:try_get("subtype") == "language" then
                        for langid, _ in pairs(modifier:try_get("skills", {})) do
                            result[langid] = true
                        end
                    end
                end
            end
        end
    end

    return result
end

--- Every characteristic. The rules name Reason, Intuition or Presence, which
--- is what a slot opens on; the rest are offered on the same chapter's
--- "another applicable test, as the Director determines".
--- @return {id: string, text: string}[]
function NEGRules.CharacteristicOptions()
    local options = {}
    for _, id in ipairs(creature.attributeIds) do
        local info = creature.attributesInfo[id]
        options[#options + 1] = {
            id = id,
            text = info ~= nil and info.description or id,
        }
    end
    return options
end

--- @param id string
--- @return string
function NEGRules.CharacteristicName(id)
    local info = creature.attributesInfo[id]
    return info ~= nil and info.description or tostring(id)
end

--- This creature's modifier for a characteristic, or nil when it has none.
--- @param charid string
--- @param attrId string
--- @return number|nil
function NEGRules.CharacteristicModifier(charid, attrId)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or token.properties == nil then
        return nil
    end
    local modifier = nil
    pcall(function()
        modifier = token.properties:GetAttribute(attrId):Modifier()
    end)
    return modifier
end

--- @param modifier number|nil
--- @return string
function NEGRules.SignedModifier(modifier)
    if modifier == nil then
        return ""
    end
    return string.format("%s%d", modifier >= 0 and "+" or "", modifier)
end

--- @param id string
--- @return string
function NEGRules.SkillName(id)
    local skill = Skill.SkillsById ~= nil and Skill.SkillsById[id] or nil
    if skill ~= nil then
        return skill.name
    end
    local skillsTable = dmhub.GetTable(Skill.tableName) or {}
    local entry = skillsTable[id]
    return entry ~= nil and entry.name or tostring(id)
end

--- The skills this hero actually has, sorted by name, with an opening entry
--- for making the case on the characteristic alone.
--- @param charid string
--- @return {id: string, text: string}[]
function NEGRules.SkillOptionsFor(charid)
    local options = { { id = "", text = "(no skill)" } }

    local token = dmhub.GetCharacterById(charid)
    if token == nil or token.properties == nil then
        return options
    end

    local owned = {}
    for _, skill in ipairs(Skill.SkillsInfo) do
        local has = false
        pcall(function()
            has = token.properties:ProficientInSkill(skill)
        end)
        if has then
            owned[#owned + 1] = { id = skill.id, text = skill.name }
        end
    end

    table.sort(owned, function(a, b)
        return string.lower(a.text) < string.lower(b.text)
    end)

    for _, entry in ipairs(owned) do
        options[#options + 1] = entry
    end

    return options
end

--- Every language an NPC could natively speak: the game's list, less whatever
--- the heroes all know already. A rule granting "all" would otherwise empty
--- the list, so an empty result falls back to the full one.
--- @return {id: string, text: string}[]
function NEGRules.LanguageOptions()
    local all = Language.GetDropdownList()
    local universal = NEGRules.UniversalLanguageIds()

    local options = {}
    for _, option in ipairs(all) do
        if universal[option.id] ~= true then
            options[#options + 1] = option
        end
    end

    if #options == 0 then
        return all
    end

    return options
end

--- @param langid string|nil
--- @return string
function NEGRules.LanguageName(langid)
    if langid == nil or langid == "" then
        return ""
    end
    local languages = dmhub.GetTable(Language.tableName) or {}
    local entry = languages[langid]
    return entry ~= nil and entry.name or ""
end

--- Every player-controlled hero in the game, on the map or off it. The default
--- party seeds explicitly so a hidden party still contributes; characters in
--- other parties only count when they have a named owner, since
--- playerControlled is also true for party-shared tokens.
--- @return string[] charids
function NEGRules.HeroRoster()
    local result = {}
    local seen = {}
    local partyId = GetDefaultPartyID()

    local function Consider(charid, inDefaultParty)
        if charid == nil or seen[charid] then
            return
        end

        local token = dmhub.GetCharacterById(charid)
        if token == nil or token.properties == nil then
            return
        end

        if not inDefaultParty and token.playerControlledNotShared ~= true then
            return
        end

        --Followers are characters in their own right and would otherwise turn
        --up here. Heroes are who negotiate.
        local isHero = false
        pcall(function()
            isHero = token.properties:IsHero()
        end)
        if not isHero then
            return
        end

        seen[charid] = true
        result[#result + 1] = charid
    end

    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyId) or {}) do
        Consider(charid, true)
    end

    for pid, _ in unhidden_pairs(dmhub.GetTable(Party.tableName) or {}) do
        for _, charid in ipairs(dmhub.GetCharacterIdsInParty(pid) or {}) do
            Consider(charid, pid == partyId)
        end
    end

    for _, token in ipairs(dmhub.allTokens) do
        if token ~= nil and token.valid then
            Consider(token.charid, token.partyId == partyId)
        end
    end

    return result
end

--- The heroes who can hold a conversation in this language, by name. Without
--- charids this answers for every hero in the game, which is the right preview
--- before a roster is known.
--- @param langid string|nil
--- @param charids nil|string[]
--- @return string[]
function NEGRules.HeroesSpeaking(langid, charids)
    local names = {}
    if langid == nil or langid == "" then
        return names
    end

    for _, charid in ipairs(charids or NEGRules.HeroRoster()) do
        local token = dmhub.GetCharacterById(charid)
        if token ~= nil and token.properties ~= nil then
            local known = nil
            pcall(function()
                known = token.properties:LanguagesKnown()
            end)
            if known ~= nil and known[langid] == true then
                names[#names + 1] = token.name or ""
            end
        end
    end

    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    return names
end

--- Patience gained for being addressed in the NPC's own tongue: 1 if any hero
--- can, 2 if three or more can. A universal language earns nothing; the editor
--- cannot offer one, so that guard is for imports.
--- @param langid string|nil
--- @param charids nil|string[] the heroes at the table
--- @return number bonus
--- @return string[] speakers
function NEGRules.LanguagePatienceBonus(langid, charids)
    if langid == nil or langid == "" then
        return 0, {}
    end

    if NEGRules.UniversalLanguageIds()[langid] == true then
        return 0, {}
    end

    local speakers = NEGRules.HeroesSpeaking(langid, charids)
    if #speakers >= 3 then
        return 2, speakers
    end
    if #speakers >= 1 then
        return 1, speakers
    end
    return 0, speakers
end

--- The patience a negotiation actually opens on, capped at the top of the
--- scale.
--- @param basePatience number
--- @param langid string|nil
--- @param charids nil|string[] the heroes at the table
--- @return number patience
--- @return number bonus
--- @return string[] speakers
function NEGRules.OpeningPatience(basePatience, langid, charids)
    local bonus, speakers = NEGRules.LanguagePatienceBonus(langid, charids)
    local base = NEGConstants.Clamp(basePatience,
        NEGConstants.scaleMin, NEGConstants.scaleMax)
    return math.min(NEGConstants.scaleMax, base + bonus), bonus, speakers
end
