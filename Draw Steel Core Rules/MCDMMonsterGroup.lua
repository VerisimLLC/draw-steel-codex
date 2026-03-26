local mod = dmhub.GetModLoading()

--- @class MonsterGroup
--- @field name string Display name.
--- @field tableName string Data table name ("MonsterGroup").
--- @field reach number Default reach in world units.
--- @field size string Size code (e.g. "1M", "2L").
--- @field weight number Weight category.
--- @field commonTraits table[] Traits shared by all monsters in this group.
--- @field languages string[] Language ids spoken by monsters in this group.
--- @field keywords string[] Keyword tags (e.g. "humanoid", "undead").
--- @field attacks table[] Attack definitions for monsters in this group.
--- @field traits table[] Special trait entries.
--- @field maliceAbilities MaliceAbility[] Malice-cost special abilities for this group.
MonsterGroup = RegisterGameType("MonsterGroup")

function MonsterGroup.CreateNew(args)
    local params = {
        attacks = {},
        traits = {},
        maliceAbilities = {},
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    return MonsterGroup.new(params)
end

MonsterGroup.tableName = "MonsterGroup"

MonsterGroup.name = "Monster Group"
MonsterGroup.reach = 5
MonsterGroup.size = "1M"
MonsterGroup.weight = 1

MonsterGroup.commonTraits = {}
MonsterGroup.languages = {}
MonsterGroup.keywords = {}
MonsterGroup.attacks = {}
MonsterGroup.traits = {}
MonsterGroup.maliceAbilities = {}

function MonsterGroup.Get(id)
    local t = GetTableCached(MonsterGroup.tableName)
    return t[id]
end

function MonsterGroup:Render(args, options)
	args = args or {}

    local panelParams = {
        styles = Styles.Default,
        width = 500,
        height = "auto",
        flow = "vertical",

        gui.Label{
            classes = {"title"},
            text = self.name,
            width = "auto",
            height = "auto",
        }
    }

	for k,v in pairs(args or {}) do
		panelParams[k] = v
	end

    return gui.Panel(panelParams)

end

--- @class MaliceAbility:ActivatedAbility
MaliceAbility = RegisterGameType("MaliceAbility", "ActivatedAbility")

MaliceAbility.categorization = "Malice"
MaliceAbility.minLevel = 1

function MaliceAbility.Create(options)
	local args = ActivatedAbility.StandardArgs()

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return MaliceAbility.new(args)
end

--[[
function MaliceAbility:GenerateEditor()
    local resultPanel

    resultPanel = gui.Panel{
        classes = {"abilityEditor"},
        styles = {
            Styles.Form,

			{
				classes = {"formPanel"},
				width = 340,
			},
			{
				classes = {"formLabel"},
				halign = "left",
			},
			{
				classes = {"abilityEditor"},
				width = '100%',
				height = 'auto',
				flow = "horizontal",
				valign = "top",
			},
        },

        gui.Panel{
            width = "50%",
            halign = "left",
            height = "auto",
            flow = "vertical",
            valign = "top",

			gui.Panel{
				classes = {"abilityInfo", "formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Name:",
				},
				gui.Input{
					classes = "formInput",
					text = self.name,
					change = function(element)
						self.name = element.text
					end,
				},
			},
        }
    }

    return resultPanel
end
    --]]
