local mod = dmhub.GetModLoading()

--A behavior that will cause roll modifiers to be inserted for this ability.


--- @class ActivatedAbilityModifyPowerRollBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityModifyPowerRollBehavior
--- @field summary string Short label shown in behavior lists.
--- @field guid string Unique identifier.
--- @field modifier CharacterModifier The CharacterModifier (behavior="power") applied during the roll.
--- Injects temporary roll modifiers into a power roll made as part of this ability.
ActivatedAbilityModifyPowerRollBehavior = RegisterGameType("ActivatedAbilityModifyPowerRollBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityModifyPowerRollBehavior.summary = "Modify Power Roll"

ActivatedAbility.RegisterType{
    id = "mod_power_roll",
    text = "Modify Power Roll",
    createBehavior = function()
        local guid = dmhub.GenerateGuid()
        local modifier = CharacterModifier.new{
            guid = dmhub.GenerateGuid(),
            sourceguid = guid,
            name = "Power Roll Modifier",
            description = "",
            behavior = "power",
            domains = {},
        }

        CharacterModifier.TypeInfo.power.init(modifier)

        return ActivatedAbilityModifyPowerRollBehavior.new{
            guid = guid,
            modifier = modifier,
        }
    end,
}

function ActivatedAbilityModifyPowerRollBehavior:Cast(ability, casterToken, targets, options)
end

function ActivatedAbilityModifyPowerRollBehavior:EditorItems(parentPanel)
	local result = {}

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Modifier Name:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.modifier.name,
            placeholderText = "Enter modifier name...",
            change = function(element)
                self.modifier.name = element.text
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
            text = self.modifier.description or "",
            height = "auto",
            minHeight = 40,
            multiline = true,
            placeholderText = "Enter Description...",
            characterLimit = 512,
            change = function(element)
                self.modifier.description = element.text
            end,
        }
    }

    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    result[#result+1] = panel

    local typeInfo = CharacterModifier.TypeInfo[self.modifier.behavior]
    typeInfo.createEditor(self.modifier, panel)


    return result
end