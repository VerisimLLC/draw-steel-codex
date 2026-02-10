local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType("alternateappearance", "Alternate Appearance")

CharacterModifier.TypeInfo.alternateappearance = {
    init = function(modifier)
        modifier.appearance = "Alternate Appearance"
        modifier.monsterDefault = "none"
    end,

    createEditor = function(modifier, element)
        local children = {}

        children[#children+1] = modifier:FilterConditionEditor()

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Appearance Name:",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 64,
                text = modifier.appearance,
                change = function(element)
                    modifier.appearance = element.text
                end,
            }
        }

        local monsterOptions = {}
        for key,monster in pairs(assets.monsters) do
            if not monster.hidden and monster.name ~= nil then
                monsterOptions[#monsterOptions+1] = {
                    id = key,
                    text = monster.name,
                }
            end
        end

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Default Appearance:",
            },
            gui.Dropdown{
                classes = {"formDropdown"},
                options = monsterOptions,
                textDefault = "None",
                idChosen = modifier.monsterDefault,
                sort = true,
                hasSearch = true,
                change = function(element)
                    modifier.monsterDefault = element.idChosen
                end,
            }
        }

        element.children = children
    end,
}

function creature:GetAlternateAppearances()
    local result = nil

    local modifiers = self:GetActiveModifiers()
    for _,mod in ipairs(modifiers) do
        if mod.mod.behavior == "alternateappearance" then
            if result == nil then
                result = {}
            end
            result[mod.mod.appearance] = mod.mod
        end
    end

    return result
end