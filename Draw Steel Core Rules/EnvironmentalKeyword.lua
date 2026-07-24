local mod = dmhub.GetModLoading()

--This file implements Environmental Keywords: named environmental conditions
--(e.g. "Dark", "Lava") that are known to the game and attach one or more
--CharacterModifiers to any creature affected by them. They are authored in the
--Compendium under Rules and stored in the "environmentalKeywords" object table.
--
--An EnvironmentalKeyword derives from CharacterFeature, so it carries a list of
--modifiers plus the shared modifier editor (CharacterFeature:EditorPanel). This
--is the same relationship CharacterCondition has with CharacterFeature.

--- @class EnvironmentalKeyword:CharacterFeature
--- @field name string Display name of the keyword (e.g. "Dark", "Lava"). Class default "New Environmental Keyword" applies when absent.
--- @field description string Rules text shown to players. Class default "" applies when absent.
--- @field tableName string Name of the data table this keyword is stored in ("environmentalKeywords"). Class-level default; often absent on serialized instances.
--- @field source string Source label ("Environmental Keyword"). Class-level default; often absent on serialized instances.
--- @field iconid string Icon shown in the UI. Class-level default applies when absent.
--- @field display table Icon display settings (bgcolor/hueshift/saturation/brightness).
--- @field difficultTerrain boolean If true, an area marked with this keyword counts as difficult terrain. Uses the same terrain rule flag name as tiles (asset.rules.difficultTerrain).
--- @field water boolean If true, an area marked with this keyword counts as water. Uses the same terrain rule flag name as tiles (asset.rules.water).
EnvironmentalKeyword = RegisterGameType("EnvironmentalKeyword", "CharacterFeature")

EnvironmentalKeyword.name = "New Environmental Keyword"
EnvironmentalKeyword.description = ""
EnvironmentalKeyword.tableName = "environmentalKeywords"
EnvironmentalKeyword.source = "Environmental Keyword"
EnvironmentalKeyword.iconid = "ui-icons/skills/1.png"
EnvironmentalKeyword.difficultTerrain = false
EnvironmentalKeyword.water = false

--Index of keywords by lower-case name, rebuilt whenever tables refresh. Used by
--runtime code that needs to resolve a keyword from its name.
EnvironmentalKeyword.keywordsByName = {}

function EnvironmentalKeyword.OnDeserialize(self)
	if not self:has_key("guid") then
		self.guid = dmhub.GenerateGuid()
	end
end

--- @return EnvironmentalKeyword
function EnvironmentalKeyword.CreateNew()
	return EnvironmentalKeyword.new{
		guid = dmhub.GenerateGuid(),
		name = "New Environmental Keyword",
		source = "Environmental Keyword",
		description = "",
		modifiers = {},
		iconid = "ui-icons/skills/1.png",
		display = {
			bgcolor = "white",
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		},
	}
end

--- Appends {id, text} entries for all environmental keywords into options (sorted by name).
--- @param options DropdownOption[]
function EnvironmentalKeyword.FillDropdownOptions(options)
	local result = {}
	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
	for k,keyword in unhidden_pairs(dataTable) do
		result[#result+1] = {
			id = k,
			text = keyword.name,
		}
	end

	table.sort(result, function(a,b) return a.text < b.text end)
	for i,item in ipairs(result) do
		options[#options+1] = item
	end
end

local UploadKeywordWithId = function(id)
	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
	dmhub.SetAndUploadTableItem(EnvironmentalKeyword.tableName, dataTable[id])
end

local SetData = function(tableName, keywordPanel, keyid)
	local dataTable = dmhub.GetTable(tableName) or {}
	local keyword = dataTable[keyid]
	local UploadKeyword = function()
		dmhub.SetAndUploadTableItem(tableName, keyword)
	end

	--if we were displaying a different keyword and it has unsaved changes, flush it.
	if keywordPanel.data.keyid ~= "" and keywordPanel.data.keyid ~= keyid and dmhub.ToJson(dataTable[keywordPanel.data.keyid]) ~= keywordPanel.data.keywordjson then
		UploadKeywordWithId(keywordPanel.data.keyid)
	end

	keywordPanel.data.keyid = keyid
	keywordPanel.data.keywordjson = dmhub.ToJson(keyword)

	--make sure the icon display info exists (older items may predate it).
	keyword:get_or_add("display", {
		bgcolor = "white",
		hueshift = 0,
		saturation = 1,
		brightness = 1,
	})

	local children = {}

	if devmode() then
		--the id of the keyword.
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "ID:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = keyword.id,
				editable = false,
			},
		}
	end

	--the name of the keyword.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = keyword.name,
			change = function(element)
				keyword.name = element.text
				UploadKeyword()
			end,
		},
	}

	--the keyword's icon.
	local iconEditor = gui.IconEditor{
		library = "ongoingEffects",
		bgcolor = keyword.display['bgcolor'] or "white",
		margin = 20,
		width = 64,
		height = 64,
		halign = "left",
		value = keyword.iconid,
		change = function(element)
			keyword.iconid = element.value
			UploadKeyword()
		end,
		create = function(element)
			element.selfStyle.hueshift = keyword.display['hueshift']
			element.selfStyle.saturation = keyword.display['saturation']
			element.selfStyle.brightness = keyword.display['brightness']
		end,
	}

	local iconColorPicker = gui.ColorPicker{
		value = keyword.display['bgcolor'] or "white",
		hmargin = 8,
		width = 24,
		height = 24,
		valign = 'center',

		confirm = function(element)
			iconEditor.selfStyle.bgcolor = element.value
			keyword.display['bgcolor'] = element.value
			UploadKeyword()
		end,

		change = function(element)
			iconEditor.selfStyle.bgcolor = element.value
		end,
	}

	children[#children+1] = gui.Panel{
		width = 'auto',
		height = 'auto',
		flow = 'horizontal',
		halign = 'left',
		iconEditor,
		iconColorPicker,
	}

	--keyword description.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Details:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = keyword.description,
			multiline = true,
			textAlignment = "topLeft",
			height = 60,
			characterLimit = 600,
			change = function(element)
				keyword.description = element.text
				UploadKeyword()
			end,
		}
	}

	--an area marked with this keyword is difficult terrain.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("difficultTerrain", false),
			text = "Difficult Terrain",
			change = function(element)
				keyword.difficultTerrain = element.value
				UploadKeyword()
			end,
		},
	}

	--an area marked with this keyword is water.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("water", false),
			text = "Water",
			change = function(element)
				keyword.water = element.value
				UploadKeyword()
			end,
		},
	}

	--list of modifiers that this keyword applies to affected creatures.
	children[#children+1] = gui.Panel{
		width = 800,
		height = "auto",
		halign = "left",
		styles = {
			{
				selectors = {"namePanel"},
				collapsed = 1,
			},
			{
				selectors = {"sourcePanel"},
				collapsed = 1,
			},
			{
				selectors = {"descriptionPanel"},
				collapsed = 1,
			},
		},

		keyword:EditorPanel{
			noscroll = true,
			modifierRefreshed = function(element)
				UploadKeyword()
			end,
		},
	}

	keywordPanel.children = children
end

function EnvironmentalKeyword.CreateEditor()
	local keywordPanel
	keywordPanel = gui.Panel{
		data = {
			SetData = function(tableName, keyid)
				SetData(tableName, keywordPanel, keyid)
			end,
			keyid = "",
			keywordjson = "",
		},
		destroy = function(element)
			local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}

			--if the keyword changed, then upload it.
			if element.data.keyid ~= "" and dmhub.ToJson(dataTable[element.data.keyid]) ~= element.data.keywordjson then
				UploadKeywordWithId(element.data.keyid)
			end
		end,
		vscroll = true,
		width = 1200,
		height = "90%",
		halign = "left",
		flow = "vertical",
		pad = 20,
		borderBox = true,
	}

	return keywordPanel
end

--- @param contentPanel Panel
local ShowEnvironmentalKeywordsPanel = function(contentPanel)
	local keywordPanel = EnvironmentalKeyword.CreateEditor()
	local SetData = keywordPanel.data.SetData

	local listItems = {}

	local itemsListPanel
	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)
			local children = {}
			local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
			local newListItems = {}

			for k,item in pairs(dataTable) do
				newListItems[k] = listItems[k] or Compendium.CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = EnvironmentalKeyword.tableName,
					key = k,
					click = function()
						SetData(EnvironmentalKeyword.tableName, k)
					end,
				}

				newListItems[k].text = item.name

				children[#children+1] = newListItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			listItems = newListItems
			itemsListPanel.children = children
		end,
	}

	itemsListPanel:FireEvent('refreshAssets')

	local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
		Compendium.AddButton{
			click = function(element)
				dmhub.SetAndUploadTableItem(EnvironmentalKeyword.tableName, EnvironmentalKeyword.CreateNew())
			end,
		}
	}

	contentPanel.children = {leftPanel, keywordPanel}
end

Compendium.Register{
	section = "Rules",
	text = "Environmental Keywords",
	contentType = EnvironmentalKeyword.tableName,
	click = function(contentPanel)
		ShowEnvironmentalKeywordsPanel(contentPanel)
	end,
}

dmhub.RegisterEventHandler("refreshTables", function()
	local byName = {}
	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
	for k,v in unhidden_pairs(dataTable) do
		byName[string.lower(v.name)] = v
	end
	EnvironmentalKeyword.keywordsByName = byName
end)
