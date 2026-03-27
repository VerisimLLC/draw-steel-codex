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

function gui.PopupMovementSpeed(args)
    local element = args.parentElement
    if element.popup ~= nil then
        element.popup = nil
        return
    end

    local currentToken = args.token
    local characterSheet = args.characterSheet
    local isMonster = currentToken.properties:IsMonster()

    local Modify = function(modArgs)
        if currentToken == nil or not currentToken.valid then
            return
        end

        if characterSheet then
            currentToken = CharacterSheet.instance.data.info.token
            modArgs.execute()
            CharacterSheet.instance:FireEvent("refreshAll")
            dmhub.Schedule(0.2, function()
                CharacterSheet.instance:FireEvent("refreshAll")
            end)
        else
            currentToken:ModifyProperties {
                description = modArgs.description or "Modify Movement",
                execute = modArgs.execute,
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
    element.tooltip = nil

    local panels = {}
    local creature = currentToken.properties

    -- Section A: Walking Speed
    local baseSpeed = creature:GetBaseSpeed()
    if isMonster then
        panels[#panels+1] = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            vmargin = 2,
            gui.Label{
                text = "Base Speed:",
                width = "auto",
                height = "auto",
                fontSize = 14,
                valign = "center",
            },
            gui.Input{
                text = string.format("%d", baseSpeed),
                fontSize = 12,
                width = 60,
                height = 16,
                lmargin = 4,
                vpad = 2,
                hpad = 4,
                characterLimit = 4,
                change = function(el)
                    local n = tonumber(el.text)
                    if n == nil or math.floor(n) ~= n then
                        el.text = string.format("%d", baseSpeed)
                        return
                    end
                    n = math.max(0, n)
                    Modify{
                        description = "Modify Base Speed",
                        execute = function()
                            currentToken.properties.walkingSpeed = n
                        end,
                    }
                end,
            },
        }
    else
        panels[#panels+1] = gui.Label{
            text = string.format("Base Speed: %d", baseSpeed),
            width = "auto",
            height = "auto",
            fontSize = 14,
        }
    end

    -- Speed modifications
    local modifications = creature:DescribeSpeedModifications("walk")
    local characterFeatures = currentToken.properties:try_get("characterFeatures", {})

    for _, modification in ipairs(modifications) do
        local featureIndex = nil
        for index, feature in ipairs(characterFeatures) do
            if modification.mod ~= nil and modification.mod:try_get("sourceguid") == feature.guid and modification.mod.source == "Custom" then
                featureIndex = index
                break
            end
        end

        if featureIndex == nil then
            local text = string.format("%s: %s", modification.key, ReadModifierValue(modification))
            panels[#panels+1] = gui.Label{
                text = text,
                width = "auto",
                height = "auto",
                fontSize = 14,
            }
        else
            panels[#panels+1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                vmargin = 2,
                gui.Input{
                    fontSize = 12,
                    width = 180,
                    height = 16,
                    lmargin = 4,
                    vpad = 2,
                    hpad = 4,
                    characterLimit = 32,
                    text = modification.key,
                    change = function(el)
                        Modify{
                            description = "Modify Custom Speed Modification",
                            execute = function()
                                local features = currentToken.properties:get_or_add("characterFeatures", {})
                                features[featureIndex].name = el.text
                                features[featureIndex].modifiers[1].name = el.text
                            end,
                        }
                    end,
                },
                gui.Input{
                    fontSize = 12,
                    width = 60,
                    height = 16,
                    lmargin = 4,
                    vpad = 2,
                    hpad = 4,
                    characterLimit = 4,
                    text = ReadModifierValue(characterFeatures[featureIndex].modifiers[1]),
                    placeholderText = "Value...",
                    change = function(el)
                        local n = tonumber(el.text)
                        if n == nil or math.floor(n) ~= n then
                            el.text = ""
                            return
                        end
                        Modify{
                            description = "Modify Custom Speed Modification",
                            execute = function()
                                local features = currentToken.properties:get_or_add("characterFeatures", {})
                                WriteModifierValue(features[featureIndex].modifiers[1], n)
                            end,
                        }
                    end,
                },
                gui.DeleteItemButton{
                    width = 16,
                    height = 16,
                    halign = "right",
                    valign = "center",
                    press = function()
                        Modify{
                            description = "Remove Custom Speed Modification",
                            execute = function()
                                table.remove(characterFeatures, featureIndex)
                            end,
                        }
                    end,
                },
            }
        end
    end

    -- Custom speed modification input
    if not isMonster then
        panels[#panels+1] = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            vmargin = 2,
            gui.Label{
                width = "auto",
                height = "auto",
                valign = "center",
                fontSize = 14,
                text = "Custom Modification:",
            },
            gui.Input{
                fontSize = 12,
                width = 60,
                height = 16,
                lmargin = 4,
                vpad = 2,
                hpad = 4,
                characterLimit = 4,
                text = "",
                placeholderText = "Value...",
                interactable = true,
                change = function(el)
                    local n = tonumber(el.text)
                    if n == nil or math.floor(n) ~= n then
                        el.text = ""
                        return
                    end

                    local feat = DeepCopy(MCDMImporter.GetStandardFeature("Speed Modification"))
                    if feat ~= nil then
                        feat.guid = dmhub.GenerateGuid()
                        feat.modifiers[1].sourceguid = feat.guid
                        feat.name = "Custom Modification"
                        feat.modifiers[1].name = "Custom Modification"
                        WriteModifierValue(feat.modifiers[1], n)
                        feat.source = "Custom"
                        feat.modifiers[1].source = "Custom"

                        Modify{
                            description = "Add Custom Speed Modification",
                            execute = function()
                                local features = currentToken.properties:get_or_add("characterFeatures", {})
                                features[#features+1] = feat
                            end,
                        }
                    end
                end,
            },
        }
    end

    -- Current speed display
    panels[#panels+1] = gui.Label{
        text = string.format("Current Speed: %d", creature:CurrentMovementSpeed()),
        width = "auto",
        height = "auto",
        fontSize = 14,
        bold = true,
        vmargin = 2,
    }

    -- Section B: Movement Types
    panels[#panels+1] = gui.Label{
        text = "Movement Types",
        width = "auto",
        height = "auto",
        fontSize = 14,
        bold = true,
        vmargin = 4,
    }

    for _, moveInfo in ipairs(creature.movementTypeInfo) do
        if moveInfo.id ~= "walk" then
            local movementType = moveInfo.id
            local baseFromSpeeds = (creature:try_get("movementSpeeds", {})[movementType] or 0) > 0
            local moveModifications = creature:DescribeModifications(movementType, 0)
            local hasFromFeatures = #moveModifications > 0
            -- Check if explicitly granted this movement type, not just able to do it
            -- at a penalty (e.g. everyone can climb at half speed).
            local hasMovement = baseFromSpeeds or hasFromFeatures

            -- Build source text
            local sourceTexts = {}
            if baseFromSpeeds then
                sourceTexts[#sourceTexts+1] = "Innate"
            end
            for _, moveMod in ipairs(moveModifications) do
                -- Find if this is a custom feature we can delete
                local customFeatureIndex = nil
                for index, feature in ipairs(characterFeatures) do
                    if moveMod.mod ~= nil and moveMod.mod:try_get("sourceguid") == feature.guid and moveMod.mod.source == "Custom" then
                        customFeatureIndex = index
                        break
                    end
                end
                if customFeatureIndex ~= nil then
                    sourceTexts[#sourceTexts+1] = string.format("%s (Custom)", moveMod.key)
                else
                    sourceTexts[#sourceTexts+1] = moveMod.key
                end
            end
            local sourceText = table.concat(sourceTexts, ", ")

            local rowChildren = {}

            if isMonster then
                -- Monsters: interactive checkbox to toggle movement flag
                rowChildren[#rowChildren+1] = gui.Check{
                    text = moveInfo.name,
                    value = hasMovement,
                    change = function(el)
                        Modify{
                            description = string.format("Toggle %s movement", moveInfo.name),
                            execute = function()
                                if el.value then
                                    currentToken.properties:SetSpeed(movementType, currentToken.properties:WalkingSpeed())
                                else
                                    currentToken.properties:SetSpeed(movementType, 0)
                                end
                            end,
                        }
                    end,
                }
            else
                -- Characters: show checkbox but handle interactivity based on source
                local hasCustomFlag = false
                local customFlagFeatureIndex = nil
                for _, moveMod in ipairs(moveModifications) do
                    for index, feature in ipairs(characterFeatures) do
                        if moveMod.mod ~= nil and moveMod.mod:try_get("sourceguid") == feature.guid and moveMod.mod.source == "Custom" then
                            hasCustomFlag = true
                            customFlagFeatureIndex = index
                            break
                        end
                    end
                    if hasCustomFlag then break end
                end

                local fromFeaturesOnly = hasFromFeatures and not hasCustomFlag and not baseFromSpeeds

                rowChildren[#rowChildren+1] = gui.Check{
                    text = moveInfo.name,
                    value = hasMovement,
                    interactable = not fromFeaturesOnly,
                    change = function(el)
                        if hasCustomFlag and not el.value then
                            -- Remove custom flag
                            Modify{
                                description = string.format("Remove custom %s movement", moveInfo.name),
                                execute = function()
                                    local features = currentToken.properties:get_or_add("characterFeatures", {})
                                    table.remove(features, customFlagFeatureIndex)
                                end,
                            }
                        elseif not hasMovement and el.value then
                            -- Add custom movement flag via feature
                            local moveMod = CharacterModifier.new{
                                behavior = "attribute",
                                attribute = movementType,
                                operation = "set",
                                value = "1",
                                name = string.format("Custom %s", moveInfo.name),
                                source = "Custom",
                            }
                            local feat = CharacterFeature.Create{
                                name = string.format("Custom %s", moveInfo.name),
                                source = "Custom",
                                modifiers = { moveMod },
                            }
                            moveMod.sourceguid = feat.guid

                            Modify{
                                description = string.format("Add custom %s movement", moveInfo.name),
                                execute = function()
                                    local features = currentToken.properties:get_or_add("characterFeatures", {})
                                    features[#features+1] = feat
                                end,
                            }
                        end
                    end,
                }
            end

            -- Source label
            if sourceText ~= "" then
                rowChildren[#rowChildren+1] = gui.Label{
                    text = string.format("(%s)", sourceText),
                    width = "auto",
                    height = "auto",
                    fontSize = 12,
                    valign = "center",
                    lmargin = 4,
                    color = "#aaaaaa",
                }
            end

            panels[#panels+1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                vmargin = 1,
                children = rowChildren,
            }
        end
    end

    -- Close button
    panels[#panels+1] = gui.CloseButton{
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

    local container = gui.Panel{
        styles = Styles.Default,
        width = "auto",
        height = "auto",
        flow = "vertical",
        swallowPress = true,
        children = panels,
    }

    element.popup = gui.TooltipFrame(container, {
        interactable = true,
    })
end

function gui.PopupMonsterSize(args)
    local element = args.parentElement
    if element.popup ~= nil then
        element.popup = nil
        return
    end

    local currentToken = args.token
    local characterSheet = args.characterSheet

    element.popupPositioning = "panel"
    element.tooltip = nil

    local sizeOptions = {}
    for i, sizeName in ipairs(creature.sizes) do
        sizeOptions[#sizeOptions+1] = { id = sizeName, text = sizeName }
    end

    local currentSize = currentToken.properties:GetBaseCreatureSize() or currentToken.creatureSize

    local container = gui.Panel{
        styles = Styles.Default,
        width = "auto",
        height = "auto",
        flow = "vertical",
        swallowPress = true,

        gui.Label{
            text = "Size",
            width = "auto",
            height = "auto",
            fontSize = 14,
            bold = true,
            vmargin = 2,
        },

        gui.Dropdown{
            options = sizeOptions,
            idChosen = currentSize,
            fontSize = 14,
            change = function(el)
                local newSize = el.idChosen
                if characterSheet then
                    currentToken = CharacterSheet.instance.data.info.token
                    currentToken.properties:SetSizeOverride(newSize)
                    CharacterSheet.instance:FireEvent("refreshAll")
                else
                    currentToken:ModifyProperties{
                        description = "Change creature size",
                        execute = function()
                            currentToken.properties:SetSizeOverride(newSize)
                        end,
                    }
                    game.Refresh{
                        tokens = { currentToken.charid },
                    }
                end
            end,
        },

        gui.CloseButton{
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
        },
    }

    element.popup = gui.TooltipFrame(container, {
        interactable = true,
    })
end
