local mod = dmhub.GetModLoading()

--- @class Background
--- @field name string Display name of the career/background.
--- @field description string Descriptive text.
--- @field portraitid string Asset id for the career portrait.
--- @field tableName string Data table name ("careers").
Background = RegisterGameType("Background")

Background.tableName = "careers"

Background.name = "New Career"
Background.description = ""
Background.portraitid = ""

--- @return Background
function Background.CreateNew()
	return Background.new{
	}
end

--- @return string
function Background:Describe()
	return self.name
end

--- Fills result with features from this background.
--- @param choices table<string, string[]>
--- @param result CharacterFeature[]
function Background:FillClassFeatures(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do

		if feature.typeName == 'CharacterFeature' then
			result[#result+1] = feature
		else
			feature:FillChoice(choices, result)
		end
	end
end

--- Fills result with feature detail entries wrapping each feature with its source background.
--- @param choices table<string, string[]>
--- @param result {background: Background, feature: CharacterFeature|CharacterChoice}[]
--result is filled with a list of { background = Background object, feature = CharacterFeature or CharacterChoice }
function Background:FillFeatureDetails(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do
		local resultFeatures = {}
		feature:FillFeaturesRecursive(choices, resultFeatures)

		for i,resultFeature in ipairs(resultFeatures) do
			result[#result+1] = {
				background = self,
				feature = resultFeature,
			}
		end
	end
	
end

--- @return string
function Background:FeatureSourceName()
	return string.format("%s Career Feature", self.name)
end

--- Returns the ClassLevel object that stores this background's base modifiers and features.
--- @return ClassLevel
--this is where a background stores its modifiers etc, which are very similar to what a class gets.
function Background:GetClassLevel()
	if self:try_get("modifierInfo") == nil then
		self.modifierInfo = ClassLevel:CreateNew()
	end

	return self.modifierInfo
end

--- @return DropdownOption[]
function Background.GetDropdownList()
	local result = {
		{
			id = 'none',
			text = 'Choose...',
		}
	}
	local backgroundsTable = dmhub.GetTable(Background.tableName)
	for k,v in pairs(backgroundsTable) do
		result[#result+1] = { id = k, text = v.name }
	end
	table.sort(result, function(a,b)
		return a.text < b.text
	end)
	return result
end


local SetBackground = function(tableName, backgroundPanel, backgroundid)
	local backgroundTable = dmhub.GetTable(tableName) or {}
	local background = backgroundTable[backgroundid]
	local UploadBackground = function()
		dmhub.SetAndUploadTableItem(tableName, background)
	end

	local children = {}

	children[#children+1] = gui.Panel{
		flow = "vertical",
		width = 196,
		height = "auto",
		floating = true,
		halign = "right",
		valign = "top",
		gui.IconEditor{
		classes = {"portraitImage"},
		value = background.portraitid,
		library = "Avatar",
		autosizeimage = true,
		allowPaste = true,
		change = function(element)
			background.portraitid = element.value
			UploadBackground()
		end,
		},

		gui.Label{
			text = "1000x1500 image",
			width = "auto",
			height = "auto",
			halign = "center",
			fontSize = 12,
		}
	}


	--the name of the background.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStackedLabel"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStackedControl"},
			text = background.name,
			change = function(element)
				background.name = element.text
				UploadBackground()
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
			placeholderText = "Enter career description...",
			text = background.description,
			change = function(element)
				background.description = element.text
			end,
		},
	}

	BackgroundCharacteristic.EmbedEditor(background, children, function()
		backgroundPanel:FireEvent("change")
		UploadBackground()
	end)

	children[#children+1] = background:GetClassLevel():CreateEditor(background, 0, {
		width = 800,
		change = function(element)
			backgroundPanel:FireEvent("change")
			UploadBackground()
		end,
	})
	backgroundPanel.children = children
end

function Background.CreateEditor()
	local backgroundPanel
	backgroundPanel = gui.Panel{
		data = {
			SetBackground = function(tableName, backgroundid)
				SetBackground(tableName, backgroundPanel, backgroundid)
			end,
		},
		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				classes = {'class-panel'},
				width = 1200,
				height = '90%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
		},
	}

	return backgroundPanel
end

