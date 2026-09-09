local mod = dmhub.GetModLoading()

--- @class ProficiencyLevel: GameType
--- @field tableName string Data table name ("proficiencyLevel").
--- @field name string Display label (e.g. "Trained", "Expert", "Not Proficient").
--- @field value number Numeric proficiency bonus multiplier (0 = not proficient, 1 = trained, 2 = expert, etc.).
--- Represents a tier of proficiency used to calculate skill and saving throw bonuses.
ProficiencyLevel = RegisterGameType("ProficiencyLevel")

ProficiencyLevel.tableName = "proficiencyLevel"

function ProficiencyLevel.CreateNew(options)
	local args = {
		id = dmhub.GenerateGuid(),
		name = "Trained",
        value = 1,
	}

    for k,v in pairs(options or {}) do
        args[k] = v
    end

    return ProficiencyLevel.new(args)
end

local g_defaultTable = {
    unskilled = ProficiencyLevel.CreateNew{
        id = "unskilled",
        name = "Not Proficient",
        value = 0,
    },
    half = ProficiencyLevel.CreateNew{
        id = "half",
        name = "Half Proficient",
        value = 0.5,
    },
    proficient = ProficiencyLevel.CreateNew{
        id = "proficient",
        name = "Proficient",
        value = 1,
    },
    expert = ProficiencyLevel.CreateNew{
        id = "expert",
        name = "Expert",
        value = 2,
    },
}

function ProficiencyLevel.Table()
    local t = dmhub.GetTable(ProficiencyLevel.tableName)
    if t == nil then
        t = g_defaultTable
    end

    return t
end

function ProficiencyLevel.GetDropdownOptions(includeNone)
    local result = {}

    if includeNone then
        result[#result+1] = {
            id = "none",
            text = "Choose...",
            ord = -1,
        }
    end

    for k,v in pairs(ProficiencyLevel.Table()) do
        result[#result+1] = {
            id = v.id,
            text = v.name,
            ord = v.level,
        }
    end

    table.sort(result, function(a,b) return a.ord < b.ord end)

    return result
end

local function SetData(editorPanel, profid)
    local tableName = ProficiencyLevel.tableName
	local dataTable = ProficiencyLevel.Table()
    local data = dataTable[profid]
	local UploadData = function()
		dmhub.SetAndUploadTableItem(tableName, data)
	end

    local children = {}

	--the name of the proficiency level.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = data.name,
			change = function(element)
				data.name = element.text
				UploadData()
			end,
		},
	}

	--the skill level
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Value:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = tostring(data.value),
			change = function(element)
                data.value = tonumber(element.text) or data.value
                element.text = tostring(data.value)
				UploadData()
			end,
		},
	}


    editorPanel.children = children
end

function ProficiencyLevel.CreateEditor()
    local editorPanel

    editorPanel = gui.Panel{
        data = {
            SetData = function(tableName, profid)
                SetData(editorPanel, profid)
            end,
        },
		vscroll = true,
        flow = "vertical",
    }

    return editorPanel
end