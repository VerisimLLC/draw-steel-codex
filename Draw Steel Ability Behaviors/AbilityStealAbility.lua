local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityStealAbilityBehavior:ActivatedAbilityBehavior
ActivatedAbilityStealAbilityBehavior = RegisterGameType("ActivatedAbilityStealAbilityBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityStealAbilityBehavior.summary = "Steal Ability"

ActivatedAbility.RegisterType
{
	id = 'stealAbility',
	text = 'Steal Ability',
	createBehavior = function()
		return ActivatedAbilityStealAbilityBehavior.new{
            stacks = 1,
		}
	end
}

function ActivatedAbilityStealAbilityBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Ability Filter:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("abilityFilter", ""),
            change = function(element)
                self.abilityFilter = element.value
            end,

            documentation = {
                help = "This GoblinScript is used to determine if this modifier filters an ability. If the result is true, the ability will be available, if it is false, the ability will be suppressed.",
                output = "boolean",
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is affected by this modifier",
                symbols = {
                    ability = {
                        name = "Ability",
                        type = "ability",
                        desc = "The ability that is being checked for availability.",
                        examples = {
                            "Ability.Name = 'Hide'",
                            "Ability.Keywords has 'Fire'",
                        },
                    },
                    caster = {
                        name = "Caster",
                        type = "caster",
                        desc = "The original caster of the ability.",
                        examples = {
                            "Caster.Name = 'Bob'",
                            "Caster.Level > 5",
                        },
                    },
                    usedability = {
                        name = "Used Ability",
                        type = "ability",
                        desc = "The ability that triggered this steal, if fired from a triggered ability.",
                        examples = {
                            "Ability.Name = Used Ability.Name",
                        },
                    },
                }
            }
        }
    }

    self:OngoingEffectEditor(parentPanel, result)
	return result
end

function ActivatedAbilityStealAbilityBehavior.ShowChoiceDialog(choices, dialogOptions, casterToken)
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
			data = {
				ability = option,
			},
			gui.Label{
				text = option.name,
				textAlignment = "left",
				halign = "left",
				fontSize = 16,
				width = "100%",
				height = "auto",
			},
			press = function(element)
				for _,p in ipairs(optionPanels) do
					p:SetClass("selected", p == element)
				end

				chosenOption = choices[i]
			end,
			hover = function(element)
				element.tooltip = CreateAbilityTooltip(option, {
					token = casterToken,
					halign = "right",
					width = 500,
					pad = 8,
				})
			end,
		}

		if chosenOption == nil then
			panel:SetClass("selected", true)
			chosenOption = option
		end

		optionPanels[#optionPanels+1] = panel
	end

	gamehud:ModalDialog{
		title = dialogOptions.title or "Steal Ability",
		buttons = {
			{
				text = dialogOptions.buttonText or "Steal",
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
				height = 30,
				width = "100%-8",
				halign = "left",
				valign = "top",
				hmargin = 4,
				vmargin = 2,
				hpad = 8,
				vpad = 6,
				bgcolor = "#00000000",
			},
			{
				selectors = {"option","hover"},
				bgcolor = "#ffff0044",
			},
			{
				selectors = {"option","selected"},
				bgcolor = "#ff000066",
				borderColor = "#ffffff",
				borderWidth = 1,
			},
		},

		width = 500,
		height = 600,
		flow = "vertical",

		children = {
			gui.Panel{
				flow = "vertical",
				vscroll = true,
				valign = "top",
				width = "100%",
				halign = "left",
				height = "100%",
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


--- @param ability ActivatedAbility
--- @param casterToken Token
--- @param targets Token[]
--- @param options table
--- @return 
function ActivatedAbilityStealAbilityBehavior:Cast(ability, casterToken, targets, options)
    if self:try_get("ongoingEffect") == nil then
        printf("STEAL ABILITY:: NO EFFECT")
        return
    end
    
    local results = {}
    local filter = self:try_get("abilityFilter", "")

    for _, target in ipairs(targets) do
        local targetCreature = target.token.properties
        local candidateAbilities = targetCreature:GetActivatedAbilities{ characterSheet = true }
        for _,a in ipairs(candidateAbilities) do
            local passesFilter = true
            if filter ~= "" then
                local symbols = {
                    ability = a,
                    caster = casterToken.properties,
                    usedability = options ~= nil and options.symbols ~= nil and options.symbols.usedability or nil,
                }
                passesFilter = GoblinScriptTrue(ExecuteGoblinScript(filter, targetCreature:LookupSymbol(symbols), 0, "Steal Ability Filter"))
            end

            if passesFilter then
                local synth = DeepCopy(a)
                synth.stolenFrom = target.token.id

                results[#results+1] = synth
            end
        end
    end

    local chosenAbility = nil
    chosenAbility = ActivatedAbilityStealAbilityBehavior.ShowChoiceDialog(results, {
        title = "Steal Ability",
        buttonText = "Steal",
    }, casterToken)
    if chosenAbility == nil then
        return
    end

    local casterInfo = {
        tokenid = casterToken.id
    }

    if casterToken.properties ~= nil then
        casterToken:ModifyProperties{
            description = "Steal Ability",
            execute = function()
                local newEffect = casterToken.properties:ApplyOngoingEffect(self.ongoingEffect, self:try_get("duration"), casterInfo, {
                    stolenAbility = chosenAbility,
                    untilEndOfTurn = self.durationUntilEndOfTurn,
                })
            end
        }
    end

end 