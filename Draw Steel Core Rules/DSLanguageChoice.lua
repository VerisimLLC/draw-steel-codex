local mod = dmhub.GetModLoading()

RegisterGameType("CharacterLanguageChoice", "CharacterChoice")

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

dmhub.RegisterEventHandler("refreshTables", function(keys)
	g_tagCache = {}
    g_optCache = {}
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
    if self:try_get("_tmp_languageFeatures") ~= nil and (dmhub.DeepEqual(self:try_get("_tmp_languageFeaturesKey"), self.categories)) then
        return self._tmp_languageFeatures
    end

    self._tmp_languageFeaturesKey = dmhub.DeepCopy(self.categories)

    self._tmp_languageFeatures = {}

    local languagesTable = dmhub.GetTable(Language.tableName)
    for k,lang in pairs(languagesTable) do
        local feature = dmhub.DeepCopy(MCDMImporter.GetStandardFeature("Language"))
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
            if choiceid.guid == choiceid then
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
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Languages",
            },
            gui.Input{
                width = 180,
                text = tonumber(self.numChoices),
                characterLimit = 2,

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