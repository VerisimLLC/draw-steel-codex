local mod = dmhub.GetModLoading()

--this file implements summoning behavior for abilities.

--- @class ActivatedAbilitySummonBehavior : ActivatedAbilityBehavior
ActivatedAbilitySummonBehavior = RegisterGameType("ActivatedAbilitySummonBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'summon',
	text = 'Summon Creatures',
	createBehavior = function()
		return ActivatedAbilitySummonBehavior.new{
		}
	end
}

ActivatedAbilitySummonBehavior.summary = 'Summons Creatures'
ActivatedAbilitySummonBehavior.numSummons = "1"
ActivatedAbilitySummonBehavior.allCreaturesTheSame = false
ActivatedAbilitySummonBehavior.bestiaryFilter = "beast.cr = 1 and beast.type is beast"
ActivatedAbilitySummonBehavior.monsterType = "custom"
ActivatedAbilitySummonBehavior.hasReplaceCaster = true --display 'replace caster' in menu.
ActivatedAbilitySummonBehavior.replaceCaster = false
ActivatedAbilitySummonBehavior.casterControls = true
ActivatedAbilitySummonBehavior.casterChoosesCreatures = true
ActivatedAbilitySummonBehavior.groupInitiativeWithCaster = true


setting{
	id = "summoncrcheck",
	storage = "preference",
	default = true,
}

setting{
	id = "summonallsame",
	storage = "preference",
	default = true,
}


function ActivatedAbilitySummonBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Summon Creatures"
end

function ActivatedAbilitySummonBehavior.ShowCreatureChoiceDialog(choices, dialogOptions)
	dialogOptions = dialogOptions or {}
	local chosenOption = nil
	local canceled = false
	local finished = false
	local optionPanels = {}

	local minCR = nil
	local maxCR = 0
	local maxPrettyCR = "0"

	local allSameCheck = nil
	if dialogOptions.index ~= nil and dialogOptions.index < dialogOptions.numSummons and (not dialogOptions.allCreaturesTheSame) then
		allSameCheck = gui.Check{
			halign = "right",
			valign = "bottom",
			hmargin = 32,
			fontSize = 14,
			width = 460,
			height = 30,
			text = string.format("Use this choice for all %s summons", json(1+dialogOptions.numSummons - dialogOptions.index)),
			value = dmhub.GetSettingValue("summonallsame"),
			change = function(element)
				dmhub.SetSettingValue("summonallsame", element.value)
			end,
		}
	end

	for i,option in ipairs(choices) do
		local cr = option.properties:CR()
		if cr > maxCR then
			maxCR = cr
			maxPrettyCR = option.properties:PrettyCR()
		end

		if minCR == nil or cr < minCR then
			minCR = cr
		end
	end

	for i,option in ipairs(choices) do
		local panel = gui.Panel{
			classes = {"option"},
			bgimage = "panels/square.png",
			flow = "horizontal",
			data = {
				CR = option.properties:CR()
			},
			gui.Label{
				text = option.properties.monster_type,
				textAlignment = "left",
				halign = "left",
				fontSize = 16,
				width = "60%",
				height = "auto",
			},
			gui.Label{
				text = string.format("Level %s", option.properties:PrettyCR()),
				textAlignment = "left",
				halign = "left",
				fontSize = 16,
				width = "auto",
				height = "auto",
			},
			press = function(element)
				for _,p in ipairs(optionPanels) do
					p:SetClass("selected", p == element)
				end

				chosenOption = choices[i]
			end,
		}

		if chosenOption == nil and option.properties:CR() == maxCR then
			panel:SetClass("selected", true)
			chosenOption = option
		end

		optionPanels[#optionPanels+1] = panel
	end

	local ShowMaxCROnly = function(val)
		for _,panel in ipairs(optionPanels) do
			if val then
				panel:SetClass("collapsed", panel.data.CR < maxCR)
			else
				panel:SetClass("collapsed", false)
			end
		end
	end

	ShowMaxCROnly(dmhub.GetSettingValue("summoncrcheck"))

	gamehud:ModalDialog{
		classes = {"framedPanel"},
        bgimage = 'panels/square.png',
        bgcolor = Styles.backgroundColor,
        borderColor = Styles.textColor,
		title = dialogOptions.title or "Summon Creature",
		buttons = {
			{
				text = dialogOptions.buttonText or "Summon",
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

		width = 650,
		height = 700,

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
			gui.Check{
				classes = {cond(minCR == maxCR, "hidden")},
				halign = "right",
				valign = "bottom",
				hmargin = 32,
				fontSize = 14,
				width = 460,
				height = 30,
				text = string.format("Show only Level %s creatures", maxPrettyCR),
				value = dmhub.GetSettingValue("summoncrcheck"),
				change = function(element)
					dmhub.SetSettingValue("summoncrcheck", element.value)
					ShowMaxCROnly(element.value)
				end,
			},
			allSameCheck,
		}
	}

	while not finished do
		coroutine.yield(0.1)
	end

	if canceled then
		return nil
	end

	if allSameCheck ~= nil and allSameCheck.valid then
		dialogOptions.allSame = allSameCheck.value
	end

	return chosenOption
end


function ActivatedAbilitySummonBehavior:Cast(ability, casterToken, targets, args)
    for _,target in ipairs(targets) do
        local newOwner = ""
        if self.casterControls then
            newOwner = casterToken.ownerId
        end

        local finishedRoll = false
        local numSummons = nil

        gamehud.rollDialog.data.ShowDialog{
            title = 'Roll for Number of Summons',
            description = string.format("%s Summons", ability.name),
            roll = dmhub.EvalGoblinScript(self.numSummons, GenerateSymbols(casterToken.properties, args.symbols), 0, string.format("Summons number of creatures for %s", ability.name)),
            creature = casterToken.properties,
            skipDeterministic = true,
            type = 'numSummons',
            cancelRoll = function()
                finishedRoll = true
            end,
            completeRoll = function(rollInfo)
                finishedRoll = true
                numSummons = rollInfo.total
            end
        }

        while not finishedRoll do
            coroutine.yield(0.1)
        end

        dmhub.Debug(string.format("SUMMON:: %s", json(numSummons)))
        if numSummons == nil or numSummons <= 0 then
            return
        end


        local choices = {}
        if self.monsterType == "custom" then
            for k,monster in pairs(assets.monsters) do
                if not assets:GetMonsterNode(k).hidden then
                    args.symbols.beast = GenerateSymbols(monster.properties)
                    if monster.properties:has_key("monster_type") and ExecuteGoblinScript(self.bestiaryFilter, GenerateSymbols(casterToken.properties, args.symbols), 0, string.format("Bestiary filter for %s summons filter %s", ability.name, monster.properties.monster_type)) ~= 0 then
                        choices[#choices+1] = monster
                    end
                end
            end
        else
            local monster = assets.monsters[self.monsterType]
            if monster ~= nil then
                choices[#choices+1] = monster
            end
        end

        args.symbols.beast = nil

        dmhub.Debug(string.format("SUMMON:: CHOICES: %d", #choices))
        if #choices == 0 then
            return
        end

        table.sort(choices, function(a,b) return a.properties.monster_type < b.properties.monster_type end)

        local summonedTokens = {}

        local chosenOption = choices[1]

        local allSame = false

        local initiativeGrouping = nil
        if self.groupInitiativeWithCaster then
            initiativeGrouping = InitiativeQueue.GetInitiativeId(casterToken)
        end

        for j=1,numSummons do

            if j ~= 1 and (self.allCreaturesTheSame or allSame) then
                --all creatures are the same so just maintain the chosen option.

            elseif #choices > 1 and not self.casterChoosesCreatures then
                chosenOption = choices[math.random(#choices)]

            elseif #choices > 1 and self.casterChoosesCreatures then
                local dialogOptions = { index = j, numSummons = numSummons, allCreaturesTheSame = self.allCreaturesTheSame }
                chosenOption = ActivatedAbilitySummonBehavior.ShowCreatureChoiceDialog(choices, dialogOptions)
                if chosenOption == nil then
                    return
                end

                if dialogOptions.allSame then
                    allSame = true
                end
            end

            local loc = target.loc
            if self.replaceCaster then
                loc = casterToken.loc
            end

            local token = game.SpawnTokenFromBestiaryLocally(chosenOption.id, loc, {
                fitLocation = not self.replaceCaster,
            })
            token.ownerId = newOwner

            token.summonerid = casterToken.charid

            if initiativeGrouping ~= nil then
                token.properties.initiativeGrouping = initiativeGrouping
            end

            local notes = token.properties:get_or_add("notes", {})
            notes[#notes+1] = {
                title = "Summoned",
                text = string.format("Summoned by %s", casterToken.description),
            }

            summonedTokens[#summonedTokens+1] = token

            if self.casterControls then
                --if the caster controls the summoned tokens then they mimic its appearance.
                local summonerHasFrame = casterToken.portraitFrame ~= nil and casterToken.portraitFrame ~= ""
                local tokenHasFrame = token.portraitFrame ~= nil and token.portraitFrame ~= ""

                if summonerHasFrame == tokenHasFrame then
                    token.portraitFrame = casterToken.portraitFrame
                    token.portraitFrameHueShift = casterToken.portraitFrameHueShift
                end

                --if the caster controls the summoned tokens then they inherit the caster's party.
                token.partyid = casterToken.partyid
            end

            token:UploadToken("Summon Creature")
            game.UpdateCharacterTokens()

            --assign the token to the target so we can refer to it in subsequent behaviors.
            local tok = dmhub.GetTokenById(token.charid)
            target.token = tok
            print("TOKEN:: ASSIGN", tok)
        end

        if ability:RequiresConcentration() and casterToken.properties:HasConcentration() then
            casterToken:ModifyProperties{
                description = "Concentrate on summons",
                execute = function()
                    local concentration = casterToken.properties:MostRecentConcentration()
                    local summonid = concentration:get_or_add("summonid", {})
                    for _,token in ipairs(summonedTokens) do
                        summonid[#summonid+1] = token.charid
                    end
                end,
            }
        end

        dmhub.Debug(string.format("SUMMON:: DONE"))
        game.UpdateCharacterTokens()

        --we summoned, so consume resources.
        ability:CommitToPaying(casterToken, args)
    end
end

function ActivatedAbilitySummonBehavior:EditorItems(parentPanel)
	local result = {}
	self:SummonEditor(parentPanel, result, {numSummons = true, casterControls = true})
	return result
end

-- @options: { haveTargetCreature = bool? }
function ActivatedAbilityBehavior:SummonEditor(parentPanel, list, options)

	options = options or {}

	if options.numSummons then
		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Num. Summons:",
			},
			gui.GoblinScriptInput{
				value = self.numSummons,
				change = function(element)
					self.numSummons = element.value
				end,

				documentation = {
					domains = parentPanel.data.parentAbility.domains,
					help = string.format("This GoblinScript is used to determine the number of creatures that can be summoned with this ability."),
					output = "number",
					examples = {
						{
							script = "1",
							text = "1 creature will be summoned. Using a simple number is a common use of this script.",
						},
						{
							script = "3 + upcast",
							text = "3 creatures will be summoned with an additional creature for every level the spell slot used for this spell is above the spell's level.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = ActivatedAbility.helpCasting,
				},

			},
		}
	end

    local monsterOptions = {}
    for k,monster in pairs(assets.monsters) do
        if not assets:GetMonsterNode(k).hidden then
			if monster and monster.properties and monster.properties:try_get("monster_type") ~= nil then
				monsterOptions[#monsterOptions+1] = {
					id = k,
					text = monster.properties.monster_type,
				}
			end
        end
    end

    table.sort(monsterOptions, function(a,b) return a.text < b.text end)
    table.insert(monsterOptions, 1, {id = "custom", text = "Custom Filter"})

    list[#list+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Monster Type",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = monsterOptions,
            idChosen = self.monsterType,
            hasSearch = true,
            change = function(element)
                self.monsterType = element.idChosen
                element.parent.parent:FireEventTree("refreshMonsterType")
            end,
        }
    }

	local bestiaryFilterHelpSymbols = DeepCopy(ActivatedAbility.helpCasting)
	bestiaryFilterHelpSymbols[#bestiaryFilterHelpSymbols+1] = {
		name = "Beast",
		type = "creature",
		desc = "This is the monster from the Bestiary that is being examined to see if it is possible to use with this ability.",
		examples = {"Beast.CR <= 1"},
	}

	if options.haveTargetCreature then
		bestiaryFilterHelpSymbols[#bestiaryFilterHelpSymbols+1] = {
			name = "Target",
			type = "creature",
			desc = "The target creature that we are transforming.",
			examples = {"Beast.CR <= Target.CR"},
		}
	end

	list[#list+1] = gui.Panel{
		classes = {"formPanel", cond(self.monsterType ~= "custom", "hidden")},
        refreshMonsterType = function(element)
            if self.monsterType == "custom" then
                element:SetClass("hidden", false)
            else
                element:SetClass("hidden", true)
            end
        end,
		gui.Label{
			classes = "formLabel",
			text = "Bestiary Filter",
		},
		gui.GoblinScriptInput{
			value = self.bestiaryFilter,
			change = function(element)
				self.bestiaryFilter = element.value
			end,

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = string.format("This GoblinScript is used to determine which creatures from the Bestiary can be summoned using this ability. The GoblinScript will be used once for every creature found in the bestiary. If the result is <b>true</b>, then that creature will be included in the list of creatures that can be summoned with this ability. If the result is <b>false</b>, then that creature will not be included."),
				output = "boolean",
				examples = {
					{
						script = "Beast.CR <= 1 and Beast.Type is Fey",
						text = "Creatures with a challenge rating less than or equal to 1 that are Fey can be summoned with this ability.",
					},
					{
						script = "((Beast.CR = 1/2 and mode = 1) or\n(Beast.CR = 1 and mode = 2) or\n(Beast.CR = 2 and mode = 3))\nand Beast.Type is Beast",
						text = "Creatures are included in the list depending upon the mode that the player is choosing to use for this ability. You could use this in conjuction with the Number of Summons field being dependent upon the mode to make an ability where the player could, for instance, summon 8 CR 1/2 creatures, 4 CR 1 creatures, or 2 CR 2 creatures.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature casting the ability is the main subject. The beast that is being considered is found as an additional field, Beast.",
				symbols = bestiaryFilterHelpSymbols,
			},

		},
	}

    if self.hasReplaceCaster then
        list[#list+1] = gui.Check{
            text = "Replace Caster",
            value = self.replaceCaster,
            minWidth = 300,
            change = function(element)
                self.replaceCaster = element.value
            end,
        }
    end

	list[#list+1] = gui.Check{
		text = "Caster Chooses Creature Types",
		value = self.casterChoosesCreatures,
        minWidth = 300,
		change = function(element)
			self.casterChoosesCreatures = element.value
		end,
	}

	list[#list+1] = gui.Check{
		text = "All creatures the same",
		value = self.allCreaturesTheSame,
        minWidth = 300,
		change = function(element)
			self.allCreaturesTheSame = element.value
		end,
	}

	if options.casterControls then
		list[#list+1] = gui.Check{
			text = "Caster controls summons",
            minWidth = 300,
			value = self.casterControls,
			change = function(element)
				self.casterControls = element.value
			end,
		}

        list[#list+1] = gui.Check{
            text = "Group with caster",
            minWidth = 300,
            value = self.groupInitiativeWithCaster,
            change = function(element)
                self.groupInitiativeWithCaster = element.value
            end,
        }
	end

end
