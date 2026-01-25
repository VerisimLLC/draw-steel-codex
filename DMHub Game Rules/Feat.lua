local mod = dmhub.GetModLoading()

RegisterGameType("CharacterFeat")

CharacterFeat.name = "New Feat"
CharacterFeat.description = ""
CharacterFeat.tableName = "feats"
CharacterFeat.prerequisite = ""
CharacterFeat.tag = "feat"

CharacterFeat.descriptionEntries = {
    {
        text = "Notes",
        field = "description",
    }
}

function CharacterFeat:Tags()
	local tags = string.split(self.tag, ",")
	local result = {}
	for _,tag in ipairs(tags) do
		result[#result+1] = trim(tag)
	end
	
	return result
end

function CharacterFeat:HasTag(tag)
	tag = string.lower(tag)
	for _,t in ipairs(self:Tags()) do
		if string.lower(t) == tag then
			return true
		end
	end

	return false
end

function CharacterFeat.FillDropdownOptions(options, tableName)
    tableName = tableName or CharacterFeat.tableName
	local result = {}
	local featsTable = dmhub.GetTable(tableName)
	for k,feat in pairs(featsTable) do
		result[#result+1] = {
			id = k,
			text = feat.name,
		}
	end

	table.sort(result, function(a,b) return a.text < b.text end)
	for i,item in ipairs(result) do
		options[#options+1] = item
	end
end

local g_cachedTag = nil

function CharacterFeat.CreateNew()
	return CharacterFeat.new{
        tag = g_cachedTag,
	}
end

function CharacterFeat:Describe()
	return "Feat"
end

--this is where a feat stores its modifiers etc, which are very similar to what a class gets.
function CharacterFeat:GetClassLevel()
	if self:try_get("modifierInfo") == nil then
		self.modifierInfo = ClassLevel:CreateNew()
	end

	return self.modifierInfo
end

function CharacterFeat:FeatureSourceName()
	return "Feat"
end

function CharacterFeat:FillClassFeatures(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do

		if feature.typeName == 'CharacterFeature' then
			result[#result+1] = feature
		else
			if choices[feature.guid] ~= nil then
				feature:FillChoice(choices, result)
			end
		end
	end
end

--result is filled with a list of { feat = CharacterFeat object, feature = CharacterFeature or CharacterChoice }
function CharacterFeat:FillFeatureDetails(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do
		local resultFeatures = {}
		feature:FillFeaturesRecursive(choices, resultFeatures)

		for i,resultFeature in ipairs(resultFeatures) do
			result[#result+1] = {
				feat = self,
				feature = resultFeature,
			}
		end
	end
end

local SetFeat = function(tableName, featPanel, featid)
	local featsTable = dmhub.GetTable(tableName) or {}
	local feat = featsTable[featid]
	local UploadFeat = function()
		dmhub.SetAndUploadTableItem(tableName, feat)
	end

	local children = {}

	--the name of the feat.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = feat.name,
			change = function(element)
				feat.name = element.text
				UploadFeat()
			end,
		},
	}

	--prerequisites for the feat.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Prerequisite:',
			valign = 'center',
			minWidth = 240,
		},
		gui.GoblinScriptInput{
			value = feat.prerequisite,
			change = function(element)
				feat.prerequisite = element.value
				UploadFeat()
			end,

			documentation = {
				help = string.format("This GoblinScript is used to determine whether a creature meets the prerequisite requirements to gain this feat."),
				output = "boolean",
				examples = {
					{
						script = "Strength > 15 or Constitution > 15",
						text = "The creature's Strength or Constitution must be greater than 15.",
					},
					{
						script = "Level >= 3",
						text = "The creature must be level 3 or higher.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature who may get the feat",
			},
		},
	}

	--The feat's tag.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Tag:',
			valign = 'center',
			minWidth = 240,
			hover = gui.Tooltip("A feat's tag categorizes how the feat is used. Separate multiple tags with commas. A regular feat should be given the tag 'feat', but feats that are awarded under special circumstances can be given a different tag. When offering a feat selection, only feats with the matching tag will be shown."),
		},
		gui.Input{
			text = feat.tag,
			change = function(element)
                element.text = trim(element.text)
				feat.tag = element.text
                g_cachedTag = element.text
				UploadFeat()
			end,
		},
	}

    for _,entry in ipairs(feat.descriptionEntries) do

        --feat description/notes.
        children[#children+1] = gui.Panel{
            classes = {'formPanel'},
            height = 'auto',
            gui.Label{
                text = string.format("%s:", entry.text),
                valign = "center",
                minWidth = 240,
            },
            gui.Input{
                text = feat:try_get(entry.field, ""),
                fontSize = 14,
                multiline = true,
                minHeight = 50,
                height = 'auto',
                width = 800,
                minHeight = 140,
                textAlignment = "topleft",
                change = function(element)
                    feat[entry.field] = element.text
                    UploadFeat()
                end,
            }
        }

    end

	children[#children+1] = feat:GetClassLevel():CreateEditor(feat, 0, {
		change = function(element)
			featPanel:FireEvent("change")
			UploadFeat()
		end,
	})
	featPanel.children = children
end

function CharacterFeat.CreateEditor()
	local featPanel
	featPanel = gui.Panel{
		data = {
			SetFeat = function(tableName, featid)
				SetFeat(tableName, featPanel, featid)
			end,
		},
		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				halign = "left",
			},
			{
				classes = {'class-panel'},
				width = 1200,
				height = '90%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			{
				classes = {'label'},
				color = 'white',
				fontSize = 22,
				width = 'auto',
				height = 'auto',
			},
			{
				classes = {'input'},
				width = 200,
				height = 26,
				fontSize = 18,
				color = 'white',
			},
			{
				classes = {'formPanel'},
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
				halign = 'left',
				vmargin = 2,
			},

		},
	}

	return featPanel
end

RegisterGameType("CharacterFeatChoice", "CharacterChoice")

CharacterFeatChoice.name = "Feat"
CharacterFeatChoice.description = "Choose a Feat"
CharacterFeatChoice.tag = "feat"

function CharacterFeatChoice:Tags()
	local tags = string.split(self.tag, ",")
	local result = {}
	for _,tag in ipairs(tags) do
		result[#result+1] = trim(tag)
	end
	
	return result
end

function CharacterFeatChoice:HasTag(tag)
	tag = string.lower(tag)
	for _,t in ipairs(self:Tags()) do
		if string.lower(t) == tag then
			return true
		end
	end

	return false
end


function CharacterFeatChoice.CreateNew()
	return CharacterFeatChoice.new{
		guid = dmhub.GenerateGuid(),
	}
end

local g_tagCache = {}
local g_optCache = {}

dmhub.RegisterEventHandler("refreshTables", function(keys)
	g_tagCache = {}
	g_optCache = {}
end)

function CharacterFeatChoice:_cache()
	if g_tagCache[self.tag] ~= nil and g_optCache[self.tag] ~= nil then return end

	local tags = self:Tags()

	local tagCache = {}
	local optCache = {}

	local featsTable = dmhub.GetTable(CharacterFeat.tableName)
	for k,feat in pairs(featsTable) do
		local holdFeature
		for _, feature in ipairs(feat.modifierInfo.features) do 
			if feature:HasCustomDropdownPanel() then
				holdFeature = feature
			end
		end
        for _,tag in ipairs(tags) do
            if feat:HasTag(tag) then
                tagCache[#tagCache+1] = {
                    id = feat.id,
                    text = feat.name,
					description = feat.description,
                    unique = true, --this means there will be checking in the builder so if we already have this id selected somewhere it won't be shown here.
                    prerequisite = cond(feat.prerequisite ~= "", feat.prerequisite),
                    hidden = feat:try_get("hidden"),
					hasCustomPanel = holdFeature ~= nil,
					
					panel = function()
                    	return holdFeature:CreateDropdownPanel(feat.name)
                	end,
                }
				if feat:try_get("hidden", false) == false then
					optCache[#optCache+1] = {
						guid = feat.id,
						name = feat.name,
						description = feat.description,
						unique = true,
						prerequisite = cond(feat.prerequisite ~= "", feat.prerequisite),
						hasCustomPanel = holdFeature ~= nil,
						panel = function()
                    		return holdFeature:CreateDropdownPanel(feat.name)
                		end,
					}
				end
                break
            end
        end
	end

	g_tagCache[self.tag] = tagCache
	g_optCache[self.tag] = optCache
end

function CharacterFeatChoice:Choices(numOption, existingChoices, creature)
	if g_tagCache[self.tag] == nil then self:_cache() end
	return g_tagCache[self.tag]
end

function CharacterFeatChoice:GetOptions(choices)
	if g_optCache[self.tag] == nil then self:_cache() end
	return g_optCache[self.tag]
end

function CharacterFeatChoice:GetDescription()
	return self.description
end

function CharacterFeatChoice:NumChoices(creature)
	return 1
end

function CharacterFeatChoice:CanRepeat()
	return false
end

function CharacterFeatChoice:FillFeats(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

	local featsTable = dmhub.GetTable(CharacterFeat.tableName)
	for j,choiceid in ipairs(choiceidList) do
		local feat = featsTable[choiceid]
		result[#result+1] = feat
	end
end

function CharacterFeatChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end
	
	local featsTable = dmhub.GetTable(CharacterFeat.tableName)
	for j,choiceid in ipairs(choiceidList) do
		local feat = featsTable[choiceid]
		if feat ~= nil then
			for i,feature in ipairs(feat:GetClassLevel().features) do
				feature:FillChoice(choices, result)
			end
		end
	end
end

function CharacterFeatChoice:FillFeaturesRecursive(choices, result)
	result[#result+1] = self

	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

	local featsTable = dmhub.GetTable(CharacterFeat.tableName)
	for j,choiceid in ipairs(choiceidList) do
		local feat = featsTable[choiceid]
		if feat ~= nil then
			for i,feature in ipairs(feat:GetClassLevel().features) do
				feature:FillFeaturesRecursive(choices, result)
			end
		end
	end
end

function CharacterFeatChoice:VisitRecursive(fn)
	fn(self)
end


--variant of feats for creature templates.
RegisterGameType("CharacterTemplate", "CharacterFeat")
CharacterTemplate.name = "New Template"
function CharacterTemplate.CreateNew()
	return CharacterTemplate.new{
	}
end

function CharacterTemplate:Describe()
	return "Creature Template"
end

function CharacterTemplate:FeatureSourceName()
	return "Creature Template"
end

--a single feat granted in a class editor.
RegisterGameType("CharacterSingleFeat")

CharacterSingleFeat.featid = "none"
CharacterSingleFeat.name = "Single Feat"

function CharacterSingleFeat.CreateNew()
	return CharacterSingleFeat.new{
		guid = dmhub.GenerateGuid(),
	}
end

function CharacterSingleFeat:GetSummaryText()
	local feat = self:GetFeat()
	if feat == nil then
		return ""
	end

	return string.format("<b>%s</b>.  You have the <i>%s</i> feat.", feat.name, feat.name)
end

function CharacterSingleFeat:CharacterUniqueID()
	return self.guid
end

function CharacterSingleFeat:Describe()
	local feat = self:GetFeat()
	if feat == nil then
		return "Unknown feat"
	end
	return feat.name
end

function CharacterSingleFeat:GetDescription()
	local feat = self:GetFeat()
	if feat == nil then
		return "Unknown"
	end

	return feat.description
end

function CharacterSingleFeat:SetDomain(domainid)
end

function CharacterSingleFeat:ForceDomains(domains)
end

function CharacterSingleFeat:GetFeat()
	local featsTable = dmhub.GetTable(CharacterFeat.tableName)
	return featsTable[self.featid]
end

function CharacterSingleFeat:Choices(numOption, existingChoices, creature)
	return nil
end

function CharacterSingleFeat:NumChoices(creature)
	return 0
end

function CharacterSingleFeat:CanRepeat()
	return false
end

function CharacterSingleFeat:FillFeats(choices, result)
	local feat = self:GetFeat()
	if feat ~= nil then
		result[#result+1] = feat
	end
end

function CharacterSingleFeat:FillChoice(choices, result)
	local feat = self:GetFeat()
	if feat == nil then
		return
	end

	feat:FillClassFeatures(choices, result)
end

function CharacterSingleFeat:FillFeaturesRecursive(choices, result)

	result[#result+1] = self

	local feat = self:GetFeat()
	if feat ~= nil then
		for i,feature in ipairs(feat:GetClassLevel().features) do
			feature:FillFeaturesRecursive(choices, result)
		end
	end
end

function CharacterSingleFeat:VisitRecursive(fn)
	fn(self)

	local feat = self:GetFeat()
	if feat ~= nil then
		for i,feature in ipairs(feat:GetClassLevel().features) do
			feature:VisitRecursive(fn)
		end
	end
end