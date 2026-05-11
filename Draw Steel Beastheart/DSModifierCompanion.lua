local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType("companion", "Beastheart Companion")

CharacterModifier.TypeInfo.companion = {
    init = function(modifier)
        modifier.companionType = "none"
    end,

    createEditor = function(modifier, element)
        local children = {}

        children[#children+1] = modifier:FilterConditionEditor()

        local companionOptions = {}
        for key,monster in pairs(assets.monsters) do
            local node = assets:GetMonsterNode(key)
            if (not node.hidden) and monster.properties.typeName == "AnimalCompanion" then
                companionOptions[#companionOptions+1] = {
                    id = key,
                    text = monster.name or monster.properties.monster_type or "Companion",
                }
            end
        end

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Companion:",
            },
            gui.Dropdown{
                classes = {"formDropdown"},
                options = companionOptions,
                textDefault = "None",
                idChosen = modifier.companionType,
                sort = true,
                hasSearch = true,
                change = function(element)
                    modifier.companionType = element.idChosen
                end,
            },
        }

        element.children = children
    end,
}

function creature:GetCompanionType()
    for _,entry in ipairs(self:GetActiveModifiers()) do
        local m = entry.mod
        if m.behavior == "companion" then
            local companionType = m:try_get("companionType")
            if companionType ~= nil and companionType ~= "" and companionType ~= "none" then
                return companionType
            end
        end
    end

    return nil
end
