local mod = dmhub.GetModLoading()

--- @class CultureAspect
--- @field name string Display name of the aspect.
--- @field description string Descriptive text.
--- @field tableName string Data table name ("cultureAspects").
--- @field category string Aspect category id: "environment", "organization", or "upbringing".
CultureAspect = RegisterGameType("CultureAspect")

CultureAspect.tableName = "cultureAspects"

CultureAspect.name = "New Culture Aspect"
CultureAspect.description = ""

CultureAspect.category = "environment"

CultureAspect.categories = {
    {
        id = "environment",
        text = "Environment",
        description = "Your culture's environment aspect describes where the people of that culture spend most of their time. Is your culture centered in a bustling city or a small village? Did you spend your early life in an isolated monastery? Or did you wander the wilderness, never staying in one place for long?",
    },
    {
        id = "organization",
        text = "Organization",
        description = "Your culture's organization aspect determines the functioning and leadership of your community. You might come from a place with an officially recognized government and a system of laws. Or your culture might have enjoyed a less formal organization, with the people in charge having naturally gravitated toward their positions without any official offices or oaths.",
    },
    {
        id = "upbringing",
        text = "Upbringing",
        description = "Your culture's upbringing aspect is a more specific and personal part of your hero's story, describing how you were individually raised within your culture. Were you trained to become the newest archmage in a secret order of wizards, or to be a sword-wielding bodyguard who protected that arcane organization? Did you learn to delve deep into mines looking for ore in a mountain kingdom, or did you build machines meant to dig faster and deeper than any person could alone? Whatever your culture, your upbringing makes you special within that culture. ",
    },
}

--- @return CultureAspect
function CultureAspect.CreateNew()
    return CultureAspect.new{
        modifierInfo = ClassLevel:CreateNew()
    }
end

--- @return string
function CultureAspect:Describe()
    return self.name
end

--- @param choices table<string, string[]>
--- @param result CharacterFeature[]
function CultureAspect:FillClassFeatures(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do
		if feature.typeName == 'CharacterFeature' then
			result[#result+1] = feature
		else
			feature:FillChoice(choices, result)
		end
    end
end

--- Fills result with feature detail entries; the key in each entry is the category id (e.g. "environment").
--- @param choices table<string, string[]>
--- @param result table[]
--result is filled with a list of { environment/organization/upbringing = CultureAspect object, feature = CharacterFeature or CharacterChoice }
function CultureAspect:FillFeatureDetails(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do
		local resultFeatures = {}
		feature:FillFeaturesRecursive(choices, resultFeatures)

		for i,resultFeature in ipairs(resultFeatures) do
			result[#result+1] = {
				[self.category] = self,
				feature = resultFeature,
			}
		end
	end
end

--- @return string
function CultureAspect:FeatureSourceName()
	return string.format("%s Culture Feature", self.name)
end

--- Returns the ClassLevel object that stores this aspect's modifiers and features.
--- @return ClassLevel
--this is where a cultureAspect stores its modifiers etc, which are very similar to what a class gets.
function CultureAspect:GetClassLevel()

	return self.modifierInfo
end

local SetCultureAspect = function(cultureAspectPanel, cultureAspectid)
    local tableName = CultureAspect.tableName
	local cultureAspectTable = dmhub.GetTable(tableName) or {}
	local cultureAspect = cultureAspectTable[cultureAspectid]
	local UploadCultureAspect = function()
		dmhub.SetAndUploadTableItem(tableName, cultureAspect)
	end

	local children = {}

	--the name of the culture aspect.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStackedLabel"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStackedControl"},
			text = cultureAspect.name,
			change = function(element)
				cultureAspect.name = element.text
				UploadCultureAspect()
			end,
		},
	}

	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStackedLabel"},
			text = "Category:",
		},
		gui.Dropdown{
			classes = {"formStackedControl"},
			options = CultureAspect.categories,
			idChosen = cultureAspect.category,
			change = function(element)
				cultureAspect.category = element.idChosen
				UploadCultureAspect()
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
			placeholderText = string.format("Enter %s description...", cultureAspect.category),
			text = cultureAspect.description,
			change = function(element)
				cultureAspect.description = element.text
				UploadCultureAspect()
			end,
		},
	}

	children[#children+1] = cultureAspect:GetClassLevel():CreateEditor(cultureAspect, 0, {
		width = 800,
		change = function(element)
			cultureAspectPanel:FireEvent("change")
			UploadCultureAspect()
		end,
	})
	cultureAspectPanel.children = children
end

function CultureAspect.CreateEditor()
	local cultureAspectPanel
	cultureAspectPanel = gui.Panel{
		data = {
			SetCultureAspect = function(cultureAspectid)
				SetCultureAspect(cultureAspectPanel, cultureAspectid)
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

	return cultureAspectPanel
end

local ShowCultureAspectPanel = function(parentPanel)
	local tableName = CultureAspect.tableName

	local editorPanel = CultureAspect.CreateEditor()

	local itemsListPanel = nil

    local m_headingPanels = {}

	local m_cultureAspectPanels = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)


			local children = {}
			local cultureAspectsTable = dmhub.GetTable(tableName) or {}
			local newPanels = {}

			local categoryOrd = {}
			for i,v in ipairs(CultureAspect.categories) do
				categoryOrd[v.id] = i

				--heading for culture aspect section.
				children[#children+1] = m_cultureAspectPanels[i] or gui.Label{
					classes = {"labelLg", "bold"},
					width = "auto",
					height = "auto",
					hmargin = 4,
					text = v.text,
					data = {
						ord = string.format("%d", i),
					},
				}

				newPanels[i] = children[#children]
			end

			for k,item in pairs(cultureAspectsTable) do
				newPanels[k] = m_cultureAspectPanels[k] or Compendium.CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
                    imported = item:try_get("imported"),
					click = function()
						editorPanel.data.SetCultureAspect(k)
					end,
				}

				newPanels[k].data.ord = string.format("%d-%s", categoryOrd[item.category] or 1, item.name)
				newPanels[k].text = item.name

				children[#children+1] = newPanels[k]
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			m_cultureAspectPanels = newPanels
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
				dmhub.SetAndUploadTableItem(tableName, CultureAspect.CreateNew{
				})
			end,
		}
	}

	parentPanel.children = {leftPanel, editorPanel}
end

Compendium.Register{
	section = "Character",
	text = 'Culture Aspect',
	contentType = "cultureAspects",
	click = function(contentPanel)
		ShowCultureAspectPanel(contentPanel)
	end,
}