local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('forcedmovement', "Forced Movement")


CharacterModifier.TypeInfo.forcedmovement = {
    init = function(modifier)
        modifier.movementTypes = {}
    end,

    modifyForcedMovementTypes = function(modifier, creature, forcedMovementType, options)
        for _,moveType in ipairs(modifier.movementTypes) do
            if (moveType.from == "any" or moveType.from == forcedMovementType) and (not table.contains(options, moveType.to)) then
                options[#options+1] = moveType.to
            end
        end
    end,

    createEditor = function(modifier, element)
        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local children = {}

            for i,moveType in ipairs(modifier.movementTypes) do
                children[#children+1] = gui.Panel{
                    classes = {'formPanel'},
                    children = {
                        gui.Label{
                            classes = {'formLabel'},
                            text = string.format("%s -> %s", moveType.from, moveType.to),
                        },
                        gui.DeleteItemButton{
                            halign = "right",
                            click = function()
                                table.remove(modifier.movementTypes, i)
                                Refresh()
                            end,
                        },
                    },
                }
            end

            local m_from = nil
            local m_to = nil

            local TryAdd = function()
                if m_from and m_to then
                    local moveType = {
                        from = m_from,
                        to = m_to,
                    }
                    modifier.movementTypes[#modifier.movementTypes+1] = moveType
                    Refresh()
                end
            end

            local fromDropdown = gui.Dropdown{
                options = {
                    { id = "any", text = "Any"},
                    { id = "pull", text = "Pull"},
                    { id = "push", text = "Push"},
                    { id = "slide", text = "Slide"},
                },

                textDefault = "Choose...",
                change = function(element)
                    m_from = element.idChosen
                    TryAdd()
                end,
            }

            local toDropdown = gui.Dropdown{
                options = {
                    { id = "pull", text = "Pull"},
                    { id = "push", text = "Push"},
                    { id = "slide", text = "Slide"},
                },

                textDefault = "Choose...",
                change = function(element)
                    m_to = element.idChosen
                    TryAdd()
                end,
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", "formPanel-inline"},
                fromDropdown,
                gui.Label{
                    text = "->",
                    textAlignment = "center",
                    halign  = "center",
                    valign = "center",
                    fontSize = 26,
                    width = 80,
                    height = "auto",
                },
                toDropdown,
            }

            element.children = children
        end

        Refresh()
    end,
}

function CharacterModifier:ModifyForcedMovementType(creature, forcedMovementType, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.modifyForcedMovementTypes ~= nil then
        typeInfo.modifyForcedMovementTypes(self, creature, forcedMovementType, options)
    end
end

function creature:CanModifyForcedMovementTypes(forcedMovementType)
    local result = {}
    local modifiers = self:GetActiveModifiers()
    for _,mod in ipairs(modifiers) do
        mod.mod:ModifyForcedMovementType(self, forcedMovementType, result)
    end

    return result
end