local mod = dmhub.GetModLoading()

--- @class ActivatedAbilitySummonCompanionBehavior : ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilitySummonCompanionBehavior
ActivatedAbilitySummonCompanionBehavior = RegisterGameType("ActivatedAbilitySummonCompanionBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'summon_companion',
	text = 'Summon Companion',
	createBehavior = function()
		return ActivatedAbilitySummonCompanionBehavior.new{
		}
	end
}

ActivatedAbilitySummonCompanionBehavior.summary = 'Summons Creatures'

function ActivatedAbilitySummonCompanionBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Summon Companion"
end


function ActivatedAbilitySummonCompanionBehavior.ShowCreatureChoiceDialog(choices, dialogOptions)
	dialogOptions = dialogOptions or {}
	local chosenOption = nil
	local canceled = false
	local finished = false
	local optionPanels = {}

	for i,option in ipairs(choices) do
		local panel = gui.Panel{
			classes = {"option"},
			bgimage = "panels/square.png",
			flow = "horizontal",
			gui.Label{
				text = option.properties.monster_type,
				textAlignment = "left",
				halign = "left",
				fontSize = 16,
				width = "60%",
				height = "auto",
			},

			press = function(element)
				for _,p in ipairs(optionPanels) do
					p:SetClass("selected", p == element)
				end

				chosenOption = choices[i]
			end,
		}

		if chosenOption == nil then
			panel:SetClass("selected", true)
			chosenOption = option
		end

		optionPanels[#optionPanels+1] = panel
	end

	gamehud:ModalDialog{
		title = "Choose Companion",
		buttons = {
			{
				text = "Summon",
				click = function()
					finished = true
				end,
			},
			{
				text = "Cancel",
				escapeActivates = true,
				click = function()
					finished = true
					canceled = true
				end,
			},
		},

		styles = {
			{
				selectors = {"option"},
				height = 24,
				width = 500,
				halign = "center",
				valign = "top",
				hmargin = 20,
				vmargin = 0,
				vpad = 4,
				bgcolor = "#00000000",
			},
			{
				selectors = {"option","hover"},
				bgcolor = "#ffff0088",
			},
			{
				selectors = {"option","selected"},
				bgcolor = "#ff000088",
			},
		},

		width = 810,
		height = 768,

		flow = "vertical",

		children = {
			
			gui.Panel{
				flow = "vertical",
				vscroll = true,
				valign = "top",
				width = 600,
				halign = "center",
				height = 500,
				children = optionPanels,
			},
		}
	}

	while not finished do
		coroutine.yield(0.1)
	end

	if canceled then
		return nil
	end

	return chosenOption
end



function ActivatedAbilitySummonCompanionBehavior:Cast(ability, casterToken, targets, options)

    local choices = {}
    for k,monster in pairs(assets.monsters) do
        local node = assets:GetMonsterNode(k)
        if (not node.hidden) and (monster.properties.typeName == "AnimalCompanion") then
            choices[#choices+1] = monster
        end
    end

    local chosenOption = self.ShowCreatureChoiceDialog(choices, {})

    if chosenOption == nil then
        return
    end

    local loc = casterToken.loc
    if #targets > 0 and targets[1].loc then
        loc = targets[1].loc
    end

    local token = game.SpawnTokenFromBestiaryLocally(chosenOption.id, loc, {
        fitLocation = true,
    })
    --nil only for an unknown bestiary id; chosenOption came from assets.monsters.
    ---@cast token -nil

    token.ownerId = casterToken.ownerId
    token.summonerid = casterToken.charid

    token.properties.initiativeGrouping = InitiativeQueue.GetInitiativeId(casterToken)
    token.partyid = casterToken.partyid

    token:UploadToken("Summoned")

    casterToken:ModifyProperties{
        description = "Summoned a companion",
        execute = function()
            casterToken.properties.companionid = token.charid
        end,
    }

    game.UpdateCharacterTokens()

    ability:CommitToPaying(casterToken, options)
end


function ActivatedAbilitySummonCompanionBehavior:EditorItems(parentPanel)
    local result = {}
    return result
end