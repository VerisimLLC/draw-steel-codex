local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('growingresources', "Growing Resources Table")

CharacterModifier.TypeInfo.growingresources = {
    init = function(modifier)
        modifier.progression = {}
    end,

    createEditor = function(modifier, element, options)
        options = options or {}

        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            end


            local children = {}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Name",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = modifier.name or "",
                    change = function(input)
                        modifier.name = input.text
                        Refresh()
                    end,
                },
            }

            for i,row in ipairs(modifier.progression) do

                children[#children+1] = gui.Panel{
                    classes = {"formPanel", "formPanel-inline"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Level:",
                    },
                    gui.Input{
                        classes = {"formInput"},
                        text = tostring(row.level),
                        characterLimit = 2,
                        change = function(input)
                            row.level = tonumber(input.text) or 0
                            Refresh()
                        end,
                    },
                    gui.DeleteItemButton{
                        click = function(element)
                            table.remove(modifier.progression, i)
                            Refresh()
                        end,
                    },
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Resources:",
                    },
                    gui.Input{
                        classes = {"formInput"},
                        text = tostring(row.resources),
                        characterLimit = 2,
                        change = function(input)
                            row.resources = tonumber(input.text) or 0
                            Refresh()
                        end,
                    }
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Description:",
                    },
                    gui.Input{
                        classes = {"formInput"},
                        placeholderText = "Enter description here...",
                        text = row.description or "",
                        multiline = true,
                        characterLimit = 512,
                        width = 360,
                        height = "auto",
                        minHeight = 50,
                        change = function(input)
                            row.description = input.text
                            Refresh()
                        end,
                    }
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Tooltip:",
                    },
                    gui.Input{
                        classes = {"formInput"},
                        placeholderText = "Enter more detailed description here...",
                        text = row.tooltip or "",
                        multiline = true,
                        characterLimit = 512,
                        width = 360,
                        height = "auto",
                        minHeight = 50,
                        change = function(input)
                            row.tooltip = input.text
                            Refresh()
                        end,
                    }
                }

            end

            children[#children+1] = gui.Button{
                classes = {"formButton"},
                text = "Add Row",
                click = function(element)
                    modifier.progression[#modifier.progression + 1] = {
                        level = 0,
                        resources = 2,
                        description = "",
                        tooltip = "",
                    }
                    Refresh()
                end,
            }

            element.children = children
        end

        Refresh()
    end,
}

function creature:GetGrowingResourcesTable()
    local modifiers = self:GetActiveModifiers()
    for _,modifier in ipairs(modifiers) do
        if modifier.mod.behavior == 'growingresources' then
            return modifier.mod
        end
    end

    return nil
end