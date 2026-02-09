local mod = dmhub.GetModLoading()

local function ReadModifierValue(modifier)
    if modifier.behavior == "resource" then
        return string.format("%d", tonumber(modifier.num) or 0)
    else
        return modifier.value or "0"
    end
end

local function WriteModifierValue(modifier, n)
    if modifier.behavior == "resource" then
        modifier.num = n
    else
        modifier.value = n
    end
end

function gui.PopupOverrideAttribute(args)
    local element = args.parentElement
    if element.popup ~= nil then
        element.popup = nil
        return
    end

    local currentToken = args.token
    local characterSheet = args.characterSheet
    local attributeName = args.attributeName
    local baseValue = args.baseValue or args.token.properties:BaseNamedCustomAttribute(attributeName)
    local baseValueEdit = args.baseValueEdit
    local modifications = args.modifications or args.token.properties:DescribeModificationsToNamedCustomAttribute(attributeName)
    local namingTable = args.namingTable or {}

    local Modify = function(args)
        if currentToken == nil or not currentToken.valid then
            return
        end

        if characterSheet then
            currentToken = CharacterSheet.instance.data.info.token
            args.execute()
            CharacterSheet.instance:FireEvent("refreshAll")
            dmhub.Schedule(0.2, function()
                CharacterSheet.instance:FireEvent("refreshAll")
            end)
        else
            currentToken:ModifyProperties {
                description = string.format("Modify Custom %s Modification", attributeName),
                execute = args.execute,
            }

            game.Refresh {
                tokens = { currentToken.charid },
            }
        end

        --rebuild the popup.
        element.popup = nil
        element:FireEvent("press")
    end


    element.popupPositioning = "panel"

    local parentElement = element
    element.tooltip = nil

    local panels = {}


    local characterFeatures = currentToken.properties:try_get("characterFeatures", {})

    local panels = {}
    if baseValue ~= "hide" then
        if args.baseValueEdit ~= nil then
            panels[#panels+1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                vmargin = 2,
                gui.Label{
                    text = string.format("Base %s:", attributeName),
                    width = "auto",
                    height = "auto",
                    fontSize = 14,
                    valign = "center",
                },
                gui.Input{
                    text = namingTable[baseValue] or string.format("%d", baseValue),
                    fontSize = 12,
                    width = 80,
                    height = 16,
                    lmargin = 4,
                    vpad = 2,
                    hpad = 4,
                    characterLimit = 8,
                    change = function(element)
                        element.text = args.baseValueEdit(tonumber(element.text) or baseValue) or element.text
                    end,
                }

            }
        else

            panels[#panels + 1] = gui.Label {
                text = string.format("Base %s: %s", attributeName, namingTable[baseValue] or string.format("%d", baseValue)),
                width = "auto",
                height = "auto",
                fontSize = 14,
            }
        end

    end
    for _, modification in ipairs(modifications) do
        local featureIndex = nil
        for index, feature in ipairs(characterFeatures) do
            if modification.mod ~= nil and modification.mod:try_get("sourceguid") == feature.guid and modification.mod.source == "Custom" then
                featureIndex = index
                break
            end
        end


        if featureIndex == nil then
            local text = string.format("%s: %s", modification.key, namingTable[tonumber(ReadModifierValue(modification)) or 0] or ReadModifierValue(modification))
            panels[#panels + 1] = gui.Label {
                text = text,
                width = "auto",
                height = "auto",
                fontSize = 14,
            }
        else
            panels[#panels + 1] = gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                vmargin = 2,
                gui.Input {

                    fontSize = 12,
                    width = 180,
                    height = 16,
                    lmargin = 4,
                    vpad = 2,
                    hpad = 4,
                    characterLimit = 32,
                    text = modification.key,
                    change = function(element)

                        if currentToken == nil or not currentToken.valid then
                            return
                        end

                        Modify {
                            description = string.format("Modify Custom %s Modification", attributeName),
                            execute = function()
                                local characterFeatures = currentToken.properties:get_or_add("characterFeatures", {})
                                characterFeatures[featureIndex].name = element.text
                                characterFeatures[featureIndex].modifiers[1].name = element.text
                            end
                        }

                    end,
                },

                gui.Input {
                    fontSize = 12,
                    width = 120,
                    height = 16,
                    lmargin = 4,
                    vpad = 2,
                    hpad = 4,
                    characterLimit = 4,
                    text = ReadModifierValue(characterFeatures[featureIndex].modifiers[1]),
                    placeholderText = "Enter Value...",
                    change = function(element)
                        local str = element.text
                        local n = tonumber(element.text)
                        if n == nil or math.floor(n) ~= n then
                            element.text = ""
                            return
                        end

                        if currentToken == nil or not currentToken.valid then
                            return
                        end

                        Modify{
                            description = string.format("Modify Custom %s Modification", attributeName),
                            execute = function()
                                local characterFeatures = currentToken.properties:get_or_add("characterFeatures", {})
                                WriteModifierValue(characterFeatures[featureIndex].modifiers[1], n)
                            end
                        }

                    end,
                },

                gui.DeleteItemButton {
                    width = 16,
                    height = 16,
                    halign = "right",
                    valign = "center",
                    press = function()
                        if currentToken == nil or not currentToken.valid then
                            return
                        end

                        Modify {
                            description = string.format("Remove Custom %s Modification", attributeName),
                            execute = function()
                                table.remove(characterFeatures, featureIndex)
                            end,
                        }
                    end,
                }
            }
        end
    end

    panels[#panels + 1] = gui.Panel {
        width = "auto",
        height = "auto",
        flow = "horizontal",
        vmargin = 2,
        gui.Label {
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 14,
            text = "Custom Modification:",
        },

        gui.Input {
            fontSize = 12,
            width = 120,
            height = 16,
            lmargin = 4,
            vpad = 2,
            hpad = 4,
            characterLimit = 4,
            text = "",
            placeholderText = "Enter Value...",
            interactable = true,
            change = function(element)
                local str = element.text
                local n = tonumber(element.text)
                if n == nil or math.floor(n) ~= n then
                    element.text = ""
                    return
                end

                local mod = DeepCopy(MCDMImporter.GetStandardFeature(string.format("%s Modification", attributeName)))
                if mod ~= nil then
                    mod.guid = dmhub.GenerateGuid()
                    mod.modifiers[1].sourceguid = mod.guid
                    mod.name = "Custom Modification"
                    mod.modifiers[1].name = "Custom Modification"

                    WriteModifierValue(mod.modifiers[1], n)

                    mod.source = "Custom"
                    mod.modifiers[1].source = "Custom"

                    Modify {
                        description = string.format("Add Custom %s Modification", attributeName),
                        execute = function()
                            local features = currentToken.properties:get_or_add("characterFeatures", {})
                            features[#features + 1] = mod
                        end,
                    }
                end

                --rebuild the popup.
                parentElement.popup = nil
                parentElement:FireEvent("press")
            end,
        }

    }

    panels[#panels + 1] = gui.CloseButton {
        floating = true,
        width = 16,
        height = 16,
        x = 8,
        y = -8,
        halign = "right",
        valign = "top",
        press = function()
            element.popup = nil
        end,
    }

    local container = gui.Panel {
        styles = Styles.Default,
        width = "auto",
        height = "auto",
        flow = "vertical",
        swallowPress = true,
        children = panels,
    }

    element.popup = gui.TooltipFrame(container, {
        interactable = true,                                 --important to make it so the popup doesn't close when clicked on.
    })
end
