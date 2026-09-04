local mod = dmhub.GetModLoading()

--This file implements the rules for in-game Languages (like Orcish, Elvish, etc. See Translation for the file which
--allows translating DMHub into other real-world languages).

--- @class Language
--- @field name string Display name (e.g. "Elvish", "Common").
--- @field type string Language type (e.g. "Standard", "Exotic", "Secret").
--- @field speakers string Description of who speaks this language.
--- @field description string Lore/descriptive text.
--- @field typicalSpeakers table Typical speaker creature types.
--- @field script string Writing system name (e.g. "Common", "Dwarvish").
--- @field group string UI group label (e.g. "Custom", "Standard").
--- @field commonality integer Commonality rating (higher = more common).
--- @field dead boolean If true, this is a dead language not spoken by living creatures.
--- @field tableName string Data table name ("languages").
Language = RegisterGameType("Language")

--standard language fields.
Language.name = "New Language"
Language.type = "Standard"
Language.speakers = ""
Language.description = ""
Language.typicalSpeakers = {}
Language.script = "Common"
Language.group = "Custom"

Language.commonality = 5
Language.dead = false

Language.tableName = "languages"

--- @return Language
function Language.CreateNew()
	return Language.new{
	}
end

--- @return DropdownOption[]
function Language.GetDropdownList()
	local result = {}
	local languagesTable = dmhub.GetTable('languages')
	for k,v in unhidden_pairs(languagesTable) do
		result[#result+1] = { id = k, text = v.name }
	end
	table.sort(result, function(a,b)
		return a.text < b.text
	end)
	return result
end

local SetLanguage = function(tableName, languagePanel, langid)
	local languageTable = dmhub.GetTable(tableName) or {}
	local language = languageTable[langid]
	local UploadLanguage = function()
		dmhub.SetAndUploadTableItem(tableName, language)
	end

	local children = {}

	if devmode() then
        --the id of the language.
        children[#children+1] = gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "ID:",
            },
            gui.Input{
                classes = {"formStacked"},
                text = language.id,
                editable = false,
            },
        }
    end

	--the name of the language.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = language.name,
			change = function(element)
				language.name = element.text
				UploadLanguage()
			end,
		},
	}

	--the group of the language
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Group:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = language.group,
			change = function(element)
				language.group = element.text
				UploadLanguage()
			end,
		},
	}

		--language speakers
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Native Speakers:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = language.speakers,
			change = function(element)
				language.speakers = element.text
				UploadLanguage()
			end,
		},
	}

	--language description..
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Description:",
		},
		gui.Input{
			classes = {"formStacked"},
			height = 80,
			text = language.description,
			multiline = true,
			textAlignment = "topLeft",
			change = function(element)
				language.description = element.text
				UploadLanguage()
			end,
		}
	}
	
	children[#children+1] = gui.Check{

        halign = "left",
        valign = "top",
        text = "Dead Language",
        value = language.dead,

		change = function(element)
			if element.value == true then
				language.dead = true
			else
				language.dead = false
			end
			UploadLanguage()
		end,
    }

    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Commonality:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = language.commonality,
            change = function(element)
                language.commonality = tonumber(element.text)
                element.text = tostring(language.commonality)
                UploadLanguage()
            end,
        }
    }

	

	languagePanel.children = children
end

function Language.CreateEditor()
	local languageEditor
	languageEditor = gui.Panel{
		data = {
			SetLanguage = function(tableName, langid)
				SetLanguage(tableName, languageEditor, langid)
			end,
		},
		vscroll = true,
		width = 1200,
		height = "90%",
		halign = "left",
		flow = "vertical",
		pad = 20,
		borderBox = true,
	}

	return languageEditor

end

