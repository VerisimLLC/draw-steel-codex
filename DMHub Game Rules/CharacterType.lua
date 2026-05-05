local mod = dmhub.GetModLoading()

--- @class CharacterType
--- @field tableName string Data table name ("characterTypes").
--- @field name string Display name.
--- @field description string Rules/lore text.
--- @field modifierInfo nil|ClassLevel ClassLevel storing modifiers and features for this character type.
CharacterType = RegisterGameType("CharacterType")

CharacterType.tableName = "characterTypes"

CharacterType.name = "Character"
CharacterType.description = ""

function CharacterType.CreateNew()
	return CharacterType.new{
	}
end

function CharacterType:FillClassFeatures(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do

		if feature.typeName == 'CharacterFeature' then
			result[#result+1] = feature
		else
			feature:FillChoice(choices, result)
		end
	end
end

--result is filled with a list of { characterType = CharacterType object, feature = CharacterFeature or CharacterChoice }
function CharacterType:FillFeatureDetails(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do
		local resultFeatures = {}
		feature:FillFeaturesRecursive(choices, resultFeatures)

		for i,resultFeature in ipairs(resultFeatures) do
			result[#result+1] = {
				characterType = self,
				feature = resultFeature,
			}
		end
	end
	
end

function CharacterType:FeatureSourceName()
	return string.format("%s Feature", self.name)
end

--this is where a characterType stores its modifiers etc, which are very similar to what a class gets.
function CharacterType:GetClassLevel()
	if self:try_get("modifierInfo") == nil then
		self.modifierInfo = ClassLevel:CreateNew()
	end

	return self.modifierInfo
end

function CharacterType.GetDropdownList()
	local result = {
		{
			id = 'none',
			text = 'Choose...',
		}
	}
	local characterTypeTable = dmhub.GetTable(CharacterType.tableName)
	for k,v in pairs(characterTypeTable) do
		result[#result+1] = { id = k, text = v.name }
	end
	table.sort(result, function(a,b)
		return a.text < b.text
	end)
	return result
end

-----------------------------------------------
-- CharacterType Editor.
-----------------------------------------------

local SetCharacterType = function(tableName, characterTypePanel, characterTypeId)
	local characterTypeTable = dmhub.GetTable(tableName) or {}
	local characterType = characterTypeTable[characterTypeId]
	local UploadCharacterType = function()
		dmhub.SetAndUploadTableItem(tableName, characterType)
	end

	local children = {}

	--the name of the characterType.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStackedLabel"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStackedControl"},
			text = characterType.name,
			change = function(element)
				characterType.name = element.text
				UploadCharacterType()
			end,
		},
	}

	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStackedLabel"},
			text = "Description:",
		},
		gui.Input{
			classes = {"formStackedControl"},
			multiline = true,
			height = "auto",
			minHeight = 30,
			maxHeight = 300,
			vscroll = true,
			textAlignment = "topleft",
			placeholderText = "Enter Character Type description...",
			text = characterType.description,
			change = function(element)
				characterType.description = element.text
				UploadCharacterType()
			end,
		},
	}

	--add in characteristics, like backgrounds have, allowing tables to come with character types.
	BackgroundCharacteristic.EmbedEditor(characterType, children, function()
		characterTypePanel:FireEvent("change")
		UploadCharacterType()
	end)

	children[#children+1] = characterType:GetClassLevel():CreateEditor(characterType, 0, {
		width = 800,
		change = function(element)
			characterTypePanel:FireEvent("change")
			UploadCharacterType()
		end,
	})

	characterTypePanel.children = children
end

function CharacterType.CreateEditor()
	local characterTypePanel
	characterTypePanel = gui.Panel{
		data = {
			SetCharacterType = function(tableName, characterTypeId)
				SetCharacterType(tableName, characterTypePanel, characterTypeId)
			end,
		},
		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				classes = {"class-panel"},
				width = 1200,
				height = "90%",
				halign = "left",
				flow = "vertical",
				pad = 20,
			},
		},
	}

	return characterTypePanel
end

--called by DMHub to get the character types that can be created. {id -> text description}
function GetCharacterTypes()
	local result = {}
	local characterTypeTable = dmhub.GetTableVisible(CharacterType.tableName) or {}
	for k,v in pairs(characterTypeTable) do
		result[k] = v.name
	end
	
	return result
end
