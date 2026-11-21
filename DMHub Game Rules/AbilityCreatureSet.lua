local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityCreatureSetBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityCreatureSetBehavior
--- @field summary string Short label shown in behavior lists.
ActivatedAbilityCreatureSetBehavior = RegisterGameType("ActivatedAbilityCreatureSetBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType{
    id = 'creature_set',
    text = 'Creature List',
    createBehavior = function()
        return ActivatedAbilityCreatureSetBehavior.new{
            listName = "creatures",
            refresh = "encounter",
            expression = "",
        }
    end
}

ActivatedAbilityCreatureSetBehavior.summary = 'Creature List'

function ActivatedAbilityCreatureSetBehavior:Cast(ability, casterToken, targets, options)

    local obj = dmhub.EvalGoblinScriptToObject(self.expression, casterToken.properties:LookupSymbol(options.symbols), "Append creature set")
    if type(obj) == "table" and (obj.typeName == "creature" or obj.typeName == "character" or obj.typeName == "monster") then
        for _,target in ipairs(targets) do
            local tok = target.token
            if tok ~= nil then
                local targetCreature = tok.properties
                tok:ModifyProperties{
                    description = "Modify creature list",
                    execute = function()
                        if targetCreature:has_key("creatureSets") == false then
                            targetCreature.creatureSets = {}
                        end

                        local sets = targetCreature.creatureSets

                        if sets[self.listName] == nil then
                            sets[self.listName] = CreatureSet.new{}
                        end

                        --Only restamp when the list is reset, so window-based refreshes
                        --(victory) count from the first add rather than the latest.
                        local creatureSet = sets[self.listName]
                        if not targetCreature:IsResourceUsageCurrent(self.refresh, creatureSet:try_get("refreshid")) then
                            creatureSet:Clear()
                            creatureSet.refreshid = targetCreature:GetResourceRefreshId(self.refresh)
                        end

                        local added = creatureSet:Add(obj)
                        if added then
                            options.symbols.cast.numberofaddedcreatures = options.symbols.cast.numberofaddedcreatures + 1
                        end

                        options.symbols.cast.creaturelistsize = #creatureSet.creatures
                    end,
                }
            end

        end
        
    end
end

function ActivatedAbilityCreatureSetBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "List Name:",
        },

        gui.Input{
            classes = {"formInput"},
            characterLimit = 32,
            text = self.listName,
            change = function(element)
                local text = element.text:gsub("[^%a]", "")
                if text == "" then
                    text = self.listName
                end
                self.listName = text
                element.text = text
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Refresh:",
        },
        CharacterResource.RefreshTypeEditor{
            value = self.refresh,
            change = function(refreshType)
                self.refresh = refreshType
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Creature:",
        },

		gui.GoblinScriptInput{
			classes = "formInput",
			value = self.expression,
			change = function(element)
				self.expression = element.value
			end,

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = string.format("This GoblinScript is used to determine Which creature should be added to the creature list."),
				output = "creature",
				subject = creature.helpSymbols,
				subjectDescription = "The creature casting the ability.",

				symbols = ActivatedAbility.CatHelpSymbols(ActivatedAbility.helpCasting, {
					subject = {
						name = "Subject",
						type = "creature",
						desc = "The subject of the triggered ability. Only valid within a triggered ability.",
					},
				}),
			},
		},
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
    }

    return result
end
