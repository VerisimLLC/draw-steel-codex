local mod = dmhub.GetModLoading()


--- @class ActivatedAbilityModifyCastBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field paramid string Id of the cast parameter to modify (e.g. "ability_damage", "ability_boon").
--- @field value string|number|table GoblinScript formula providing the modifier value.
--- @field name string Display name shown in the ability editor.
--- @field description string Description of the modification.
--- Modifies a parameter of the cast (e.g. damage bonus, number of edges) at the time of casting.
ActivatedAbilityModifyCastBehavior = RegisterGameType("ActivatedAbilityModifyCastBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityModifyCastBehavior.summary = 'Modify Cast'
ActivatedAbilityModifyCastBehavior.paramid = 'none'
ActivatedAbilityModifyCastBehavior.value = ''
ActivatedAbilityModifyCastBehavior.name = ''
ActivatedAbilityModifyCastBehavior.description = ''


ActivatedAbility.RegisterType
{
    id = 'modify_cast',
    text = 'Modify Cast',
    createBehavior = function()
        return ActivatedAbilityModifyCastBehavior.new{
        }
    end
}

ActivatedAbilityModifyCastBehavior.Params = {}
ActivatedAbilityModifyCastBehavior.ParamsById = {}

function ActivatedAbilityModifyCastBehavior.RegisterParam(args)
    local index = ActivatedAbilityModifyCastBehavior.ParamsById[args.id] or #ActivatedAbilityModifyCastBehavior.Params + 1

    ActivatedAbilityModifyCastBehavior.ParamsById[args.id] = index
    ActivatedAbilityModifyCastBehavior.Params[index] = args
end

function ActivatedAbilityModifyCastBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Modify Cast"
end

function ActivatedAbilityModifyCastBehavior:Cast(ability, casterToken, targets, options)
    for _,target in ipairs(targets) do
        local value = ExecuteGoblinScript(self.value, casterToken.properties:LookupSymbol(options.symbols), 0, "Calculate Param")
        options.symbols.cast:AddParam({
            id = self.paramid,
            value = value,
            name = self.name,
            description = self.description,
        })
    end
end



function ActivatedAbilityModifyCastBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Name:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.name,
            change = function(element)
                self.name = element.text
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Description:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.description,
            width = 240,
            change = function(element)
                self.description = element.text
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Parameter",
        },
        gui.Dropdown{
            options = ActivatedAbilityModifyCastBehavior.Params,
            idChosen = self.paramid,
            change = function(element)
                self.paramid = element.idChosen
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Value:",
        },
        gui.GoblinScriptInput{
            value = self.value,
            change = function(element)
                self.value = element.value
            end,
            documentation = {
                help = "This GoblinScript is used to set the value to add to the parameter.",
                output = "number",
                examples = {
                    {
                        script = "3",
                        text = "3 will be added to the parameter",
                    }
                },
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is casting the spell",
                symbols = ActivatedAbility.helpCasting,
            },
        }
    }


    return result
end