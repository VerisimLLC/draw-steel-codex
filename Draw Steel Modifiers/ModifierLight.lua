local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('light', "Light Source")

CharacterModifier.TypeInfo.light = {
    init = function(modifier)
        modifier.itemid = false
    end,

    provideLightSource = function(modifier, result)
        result[modifier.itemid] = true
    end,

    createEditor = function(modifier, element, options)
        options = options or {}

        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            end

            local options = {}
            for key,item in unhidden_pairs(dmhub.GetTable(equipment.tableName) or {}) do
                if EquipmentCategory.IsLightSource(item) and item:try_get("availability") == "restricted" then
                    options[#options+1] = {
                        id = key,
                        text = item.name,
                    }
                end
            end

            local children = {}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Light",
                },
                gui.Dropdown{
                    classes = {"formDropdown"},
                    options = options,
                    idChosen = modifier.itemid,
                    sort = true,
                    hasSearch = true,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.itemid = element.idChosen
                        Refresh()
                    end,
                },
            }

            element.children = children
        end

        Refresh()
    end,
}

function creature:GetDefaultLightSource()
    local customLightSources = self:GetCustomLightSources()
    for lightid,_ in pairs(customLightSources) do
        return lightid
    end

    return "22ab52f5-955b-40c8-80c3-826f823e0a5b"
end

function creature:GetCustomLightSources()
    local result = {}
    for _,mod in pairs(self:GetActiveModifiers()) do
        local modifier = mod.mod
        if CharacterModifier.TypeInfo[modifier.behavior] and CharacterModifier.TypeInfo[modifier.behavior].provideLightSource then
            CharacterModifier.TypeInfo[modifier.behavior].provideLightSource(modifier, result)
        end
    end
    return result
end