local mod = dmhub.GetModLoading()

--an additional modifier that tacks onto an existing power roll modifier, usually
--from a trigger. Example: "Too Slow" Black Ash trigger that tags onto "In All This Confusion"
--allowing additional options for an additional cost.

CharacterModifier.RegisterType("powertableadditional", "Power Roll Trigger Addition")


CharacterModifier.TypeInfo.powertableadditional = {
    init = function(modifier)
        modifier.original = ""
        modifier.additionalModifier = CharacterModifier.new {
            behavior = 'power',
            guid = dmhub.GenerateGuid(),
            name = "Triggered Modifier",
            rules = "",
            source = "Trigger",
            rollType = "ability_power_roll",
            modtype = "none",
            activationCondition = false,
            keywords = {},
        }
    end,

    fillAdditionalCostModifiers = function(self, triggerName, modifiers)
        if string.lower(triggerName) == string.lower(self.original) then
            modifiers[#modifiers+1] = self.additionalModifier
        end
    end,

    --- @param modifier CharacterModifier
    --- @param element Panel
    createEditor = function(modifier, element)
        local Refresh
        local firstRefresh = true
        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local powerRollModifier = modifier.additionalModifier

            local children = {}

            children[#children + 1] = gui.Panel {
                classes = { "formPanel" },
                gui.Label {
                    classes = { "formLabel" },
                    text = "Original Trigger:",
                },
                gui.Input {
                    classes = { "formInput" },
                    characterLimit = 30,
                    text = modifier.original,
                    change = function(element)
                        modifier.original = element.text
                        Refresh()
                    end,
                }
            }

            children[#children+1] = gui.Check{
                styles = ThemeEngine.GetStyles(),
                classes = { "formCheck" },
                text = "Go before existing modifier",
                value = modifier.additionalModifier:try_get("gobefore", false),
                change = function(element)
                    modifier.additionalModifier.gobefore = element.value
                    Refresh()
                end,
            }

            local rollModifierEditor = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
            }

            local rollModifierTypeInfo = CharacterModifier.TypeInfo.power
            rollModifierTypeInfo.createEditor(modifier.additionalModifier, rollModifierEditor)
            children[#children+1] = rollModifierEditor

            element.children = children
        end

        Refresh()
    end,

}

function CharacterModifier:FillAdditionalCostModifiers(triggerName, modifiers)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.fillAdditionalCostModifiers ~= nil then
        typeInfo.fillAdditionalCostModifiers(self, triggerName, modifiers)
    end
end

function creature:GetAdditionalCostModifiersForPowerTableTrigger(modifier)
    local result = {}
    for _,mod in ipairs(modifier:try_get("additionalCostModifiers", {})) do
        result[#result+1] = mod
    end

    local allModifiers = self:GetActiveModifiers()
    for _,mod in ipairs(allModifiers) do
        mod.mod:FillAdditionalCostModifiers(modifier.name, result)
    end

    return result
end