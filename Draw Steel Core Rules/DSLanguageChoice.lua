local mod = dmhub.GetModLoading()

--- @class CharacterLanguageChoice:CharacterChoice
--- @field name string Display name ("Language").
--- @field description string Prompt shown to the player.
--- @field categories string[] Language category ids to filter available languages (currently unused).
--- @field numChoices number|string|table Number of languages the player may choose.
CharacterLanguageChoice = RegisterGameType("CharacterLanguageChoice", "CharacterChoice")

CharacterLanguageChoice.name = "Language"
CharacterLanguageChoice.description = "Choose a Language"

--maybe categories will be used for languages in the future? Right now unused.
--perhaps dead vs live languages?
CharacterLanguageChoice.categories = {}
CharacterLanguageChoice.numChoices = 1

function CharacterLanguageChoice.Create(options)
	local result = CharacterLanguageChoice.new{
		guid = dmhub.GenerateGuid(),
	}

    for k,v in pairs(options or {}) do
        result[k] = v
    end

    return result
end

local g_tagCache = {}
local g_optCache = {}
local g_languageVersion = 0

dmhub.RegisterEventHandler("refreshTables", function(keys)
	g_tagCache = {}
    g_optCache = {}
    g_languageVersion = g_languageVersion + 1
end)

function CharacterLanguageChoice:_cache()
    if g_tagCache[self.categories] ~= nil and g_optCache[self.categories] ~= nil then return end

	local tagCache = {}
    local optCache = {}

	local languagesTable = dmhub.GetTable(Language.tableName)
	for k,lang in unhidden_pairs(languagesTable) do
        local text = lang.name
        if lang.speakers ~= "" then
            text = string.format("%s (%s)", lang.name, lang.speakers)
        end
        tagCache[#tagCache+1] = {
            id = k,
            text = text,
            description = lang.description,
            dead = lang.dead,
            unique = true, --this means there will be checking in the builder so if we already have this id selected somewhere it won't be shown here.
        }
        optCache[#optCache+1] = {
            guid = k,
            name = text,
            description = lang.description,
            dead = lang.dead,
            unique = true,
        }
	end

	g_tagCache[self.categories] = tagCache
    g_optCache[self.categories] = optCache
end

function CharacterLanguageChoice:Choices(numOption, existingChoices, creature)
    if g_tagCache[self.categories] == nil then self:_cache() end
    return g_tagCache[self.categories]
end

function CharacterLanguageChoice:GetOptions(choices)
    if g_optCache[self.categories] == nil then self:_cache() end
    return g_optCache[self.categories]
end

function CharacterLanguageChoice:GetDescription()
	return self.description
end

function CharacterLanguageChoice:NumChoices(creature)
	return self.numChoices
end

function CharacterLanguageChoice:CanRepeat()
	return false
end

function CharacterLanguageChoice:GetLanguageFeatures()
    local cachedKey = self:try_get("_tmp_languageFeaturesKey")
    if self:try_get("_tmp_languageFeatures") ~= nil
        and cachedKey ~= nil
        and cachedKey.version == g_languageVersion
        and dmhub.DeepEqual(cachedKey.categories, self.categories) then
        return self._tmp_languageFeatures
    end

    self._tmp_languageFeaturesKey = {
        version = g_languageVersion,
        categories = DeepCopy(self.categories),
    }

    self._tmp_languageFeatures = {}

    local languagesTable = dmhub.GetTable(Language.tableName)
    for k,lang in pairs(languagesTable) do
        local feature = DeepCopy(MCDMImporter.GetStandardFeature("Language"))
        if feature ~= nil then
            feature.id = k
            feature.guid = k
            feature.name = lang.name
            feature.modifiers[1].name = lang.name
            feature.modifiers[1].skills = {[k] = true}
            feature.modifiers[1].sourceguid = self.guid

            self._tmp_languageFeatures[#self._tmp_languageFeatures+1] = feature
        end
    end

    return self._tmp_languageFeatures
end

function CharacterLanguageChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    local languageFeatures = self:GetLanguageFeatures()
    for _,choiceid in ipairs(choiceidList) do
        for _,f in ipairs(languageFeatures) do
            if f.guid == choiceid then
                f:FillChoice(choices, result)
            end
        end
    end
end

function CharacterLanguageChoice:FillFeaturesRecursive(choices, result)
	result[#result+1] = self

	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end
    
    local languageFeatures = self:GetLanguageFeatures()
    for _,choiceid in ipairs(choiceidList) do
        for _,f in ipairs(languageFeatures) do
            if f.guid == choiceid then
                f:FillFeaturesRecursive(choices, result)
            end
        end
    end
end

function CharacterLanguageChoice:VisitRecursive(fn)
	fn(self)
end

function CharacterLanguageChoice:CreateEditor(classOrRace, params)
	params = params or {}

    local resultPanel

    resultPanel = {
        width = "100%",
        height = "auto",
        flow = "vertical",

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "Languages:",
            },
            gui.Input{
                classes = {"formStacked"},
                width = 180,
                text = tonumber(self.numChoices),
                characterLimit = 2,
                numeric = true,
                change = function(element)
                    local n = math.max(1, round(tonumber(element.text) or self.numChoices))
                    self.numChoices = n
                    resultPanel:FireEvent("change")
                end,
            }
        },
    }

    for k,v in pairs(params) do
        resultPanel[k] = v
    end

    resultPanel = gui.Panel(resultPanel)

    return resultPanel
end

CharacterChoice.RegisterChoice{
    id = "language",
    text = "Choice of a Language",
    type = CharacterLanguageChoice,
}

-------------------------------------------------------------------------------
-- CharacterForgetLanguageChoice: the player picks a language they currently
-- know and forgets it (e.g. the Shipwrecked complication's drawback). Each pick
-- becomes a 'proficiency' modifier with subtype 'forgetlanguage', which
-- subtracts one from that language's tally in creature:LanguageCounts(); the
-- language stays known if some other feature still grants it.
-------------------------------------------------------------------------------

--- @class CharacterForgetLanguageChoice:CharacterChoice
--- @field name string Display name ("Forget a Language").
--- @field description string Prompt shown to the player.
--- @field numChoices number|string|table Number of languages the player must forget.
CharacterForgetLanguageChoice = RegisterGameType("CharacterForgetLanguageChoice", "CharacterChoice")

CharacterForgetLanguageChoice.name = "Forget a Language"
CharacterForgetLanguageChoice.description = "Choose a language you know to forget"
CharacterForgetLanguageChoice.numChoices = 1

function CharacterForgetLanguageChoice.Create(options)
	local result = CharacterForgetLanguageChoice.new{
		guid = dmhub.GenerateGuid(),
	}

    for k,v in pairs(options or {}) do
        result[k] = v
    end

    return result
end

--- The language ids this choice may offer: everything the creature currently knows,
--- plus whatever is already picked here. A picked language has been subtracted from
--- LanguagesKnown(), so without that union it would vanish from its own dropdown.
--- @param existingChoices string[]|nil ids already chosen for this feature
--- @param creature creature|nil
--- @return table<string, boolean>
function CharacterForgetLanguageChoice:_candidateLanguages(existingChoices, creature)
    local ids = {}
    if creature ~= nil then
        for k,_ in pairs(creature:LanguagesKnown()) do
            if k ~= "all" then
                ids[k] = true
            end
        end
    end

    for _,id in ipairs(existingChoices or {}) do
        ids[id] = true
    end

    return ids
end

--- @return {id: string, text: string, description: string, unique: boolean}[]
function CharacterForgetLanguageChoice:Choices(numOption, existingChoices, creature)
    local languagesTable = dmhub.GetTable(Language.tableName) or {}
    local result = {}
    for langid,_ in pairs(self:_candidateLanguages(existingChoices, creature)) do
        local lang = languagesTable[langid]
        if lang ~= nil then
            result[#result+1] = {
                id = langid,
                text = lang.name,
                description = lang.description,
                --not unique: the builder's uniqueness sweep hides any option chosen
                --elsewhere, which here would hide exactly the languages we want listed.
                unique = false,
            }
        end
    end

    table.sort(result, function(a,b) return a.text < b.text end)
    return result
end

--- @param choices table<string, string[]>|nil the creature's full levelChoices map
--- @param creature creature|nil
function CharacterForgetLanguageChoice:GetOptions(choices, creature)
    local existing = nil
    if choices ~= nil then
        existing = choices[self.guid]
    end

    local languagesTable = dmhub.GetTable(Language.tableName) or {}
    local result = {}
    for langid,_ in pairs(self:_candidateLanguages(existing, creature)) do
        local lang = languagesTable[langid]
        if lang ~= nil then
            result[#result+1] = {
                guid = langid,
                name = lang.name,
                description = lang.description,
                unique = false,
            }
        end
    end

    table.sort(result, function(a,b) return a.name < b.name end)
    return result
end

function CharacterForgetLanguageChoice:GetDescription()
	return self.description
end

function CharacterForgetLanguageChoice:NumChoices(creature)
	return self.numChoices
end

function CharacterForgetLanguageChoice:CanRepeat()
	return false
end

--- Builds (and caches) the synthetic feature that forgets one language: a copy of
--- the standard "Language" feature with its modifier flipped to 'forgetlanguage'.
--- @param langid string
--- @return CharacterFeature|nil
function CharacterForgetLanguageChoice:GetForgetFeature(langid)
    local cache = self:try_get("_tmp_forgetFeatures")
    if cache == nil or cache.version ~= g_languageVersion then
        cache = { version = g_languageVersion, features = {} }
        self._tmp_forgetFeatures = cache
    end

    if cache.features[langid] ~= nil then
        return cache.features[langid]
    end

    local lang = (dmhub.GetTable(Language.tableName) or {})[langid]
    local feature = DeepCopy(MCDMImporter.GetStandardFeature("Language"))
    if lang == nil or feature == nil then
        return nil
    end

    local name = string.format("Forgotten: %s", lang.name)
    feature.id = langid
    --distinct from the "know this language" feature's guid, which is the bare langid.
    feature.guid = langid .. "-forget"
    feature.name = name
    feature.modifiers[1].name = name
    feature.modifiers[1].subtype = "forgetlanguage"
    feature.modifiers[1].skills = {[langid] = true}
    feature.modifiers[1].sourceguid = self.guid

    cache.features[langid] = feature
    return feature
end

function CharacterForgetLanguageChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    for _,choiceid in ipairs(choiceidList) do
        local f = self:GetForgetFeature(choiceid)
        if f ~= nil then
            f:FillChoice(choices, result)
        end
    end
end

function CharacterForgetLanguageChoice:FillFeaturesRecursive(choices, result)
	result[#result+1] = self

	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    for _,choiceid in ipairs(choiceidList) do
        local f = self:GetForgetFeature(choiceid)
        if f ~= nil then
            f:FillFeaturesRecursive(choices, result)
        end
    end
end

function CharacterForgetLanguageChoice:VisitRecursive(fn)
	fn(self)
end

function CharacterForgetLanguageChoice:CreateEditor(classOrRace, params)
	params = params or {}

    local resultPanel

    resultPanel = {
        width = "100%",
        height = "auto",
        flow = "vertical",

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "Languages to forget:",
            },
            gui.Input{
                classes = {"formStacked"},
                width = 180,
                text = tonumber(self.numChoices),
                characterLimit = 2,
                numeric = true,
                change = function(element)
                    local n = math.max(1, round(tonumber(element.text) or self.numChoices))
                    self.numChoices = n
                    resultPanel:FireEvent("change")
                end,
            }
        },
    }

    for k,v in pairs(params) do
        resultPanel[k] = v
    end

    resultPanel = gui.Panel(resultPanel)

    return resultPanel
end

CharacterChoice.RegisterChoice{
    id = "forgetlanguage",
    text = "Forget a Known Language",
    type = CharacterForgetLanguageChoice,
}