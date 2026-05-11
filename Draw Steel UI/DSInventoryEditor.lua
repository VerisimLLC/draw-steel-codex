local mod = dmhub.GetModLoading()

--This file implements the editing sheet for items.


DataTables.tbl_Gear = {}

function DataTables.tbl_Gear.ReadSQL(row)
    local type = row.Get("type")

    local ParseNum = function(item)
        if item == nil then
            return nil
        end

        return tonumber(item)
    end

    if type == "Weapon" then
        return weapon.new {
            name = row.Get("name"),
            type = 'Weapon',
            category = row.Get("category") or 'Simple',
            costInGold = tonumber(row.Get("costInGold")),
            specialDescription = row.Get("specialDescription"),
            iconid = row.Get("iconid") or '',
            description = row.Get("description") or '',
            weight = row.Get("weight"),

            damage = row.Get("damage") or 1,
            damageType = row.Get("damageType") or 'slashing',
            range = row.Get("range"),
            ammo = row.Get("ammo"),
            thrown = row.Get("thrown"),
            hands = row.Get("hands") or 'One-handed',
            loading = row.Get("loading"),
            light = row.Get("light"),
            heavy = row.Get("heavy"),
            versatileDamage = row.Get("versatileDamage"),
            finesse = row.Get("finesse"),
            reach = row.Get("reach"),
        }
    elseif type == "Armor" then
        return armor.new {
            name = row.Get("name"),
            type = 'Armor',
            category = row.Get("category") or 'Light',
            costInGold = tonumber(row.Get("costInGold")),
            specialDescription = row.Get("specialDescription"),
            iconid = row.Get("iconid") or '',
            description = row.Get("description") or '',
            weight = row.Get("weight"),

            armorClass = tonumber(row.Get("armorClass")),
            strength = row.Get("strength"),
            stealth = row.Get("stealth"),
            dexterityLimit = ParseNum(row.Get("ModifierLimit")),
        }
    elseif type == "Shield" then
        return shield.new {
            name = row.Get("name"),
            type = 'Shield',
            category = row.Get("category") or '',
            costInGold = tonumber(row.Get("costInGold")),
            specialDescription = row.Get("specialDescription"),
            iconid = row.Get("iconid") or '',
            description = row.Get("description") or '',
            weight = row.Get("weight"),
            armorClassModifier = tonumber(row.Get("armorClass")),
        }
    else
        return equipment.new {
            name = row.Get("name"),
            type = row.Get("type") or 'Gear',
            category = row.Get("category") or 'Gear',
            costInGold = tonumber(row.Get("costInGold")),
            specialDescription = row.Get("specialDescription"),
            iconid = row.Get("iconid") or '',
            description = row.Get("description") or '',
            weight = row.Get("weight"),
        }
    end
end

function DataTables.tbl_Gear.WriteSQL(obj)
    local category = rawget(obj, "category")
    if category == nil then
        category = 'Adventuring Gear'
    end

    return {
        name = rawget(obj, "name"),
        type = rawget(obj, "type"),
        category = category,
        costInGold = rawget(obj, "costInGold"),
        specialDescription = rawget(obj, "specialDescription"),
        iconid = rawget(obj, "iconid") or '',
        description = rawget(obj, "description"),
        weight = rawget(obj, "weight"),
        damage = rawget(obj, "damage") or '1d6',
        damageType = rawget(obj, "damageType") or 'slashing',
        range = rawget(obj, "range") or "NULL",
        ammo = rawget(obj, "ammo"),
        thrown = rawget(obj, "thrown"),
        hands = rawget(obj, "hands"),
        loading = rawget(obj, "loading"),
        light = rawget(obj, "light"),
        heavy = rawget(obj, "heavy"),
        versatileDamage = rawget(obj, "versatileDamage"),
        finesse = rawget(obj, "finesse"),
        reach = rawget(obj, "reach"),
        armorClass = rawget(obj, "armorClass") or rawget(obj, "armorClassModifier"),
        strength = rawget(obj, "strength"),
        stealth = rawget(obj, "stealth"),

        --in the database it's called "ModifierLimit" (and also has an ostensibly unneeded 'Modifier'
        --field associated with it, but we will call it dexterityLimit since that makes more sense.)
        ModifierLimit = rawget(obj, "dexterityLimit"),
    }
end

function DataTables.tbl_Gear.CreateNew()
    return weapon.new {
        name = 'New Item',
        type = 'Weapon',
        hands = 'One-handed',
        description = '',
        iconid = '',
        category = 'Simple',
        costInGold = 10,
        weight = '2 lbs',
        damage = '1d6',
        damageType = 'slashing',
    }
end

function DataTables.tbl_Gear.Input(document, text, attr, options)
    local x = 0
    local y = 0
    local inputWidth = 200
    if options ~= nil then
        if options['x'] ~= nil then
            x = options['x']
        end
        if options['y'] ~= nil then
            y = options['y']
        end
        if options['width'] ~= nil then
            inputWidth = options['width']
        end
    end

    return gui.Panel({
        id = attr,
        x = x,
        y = y,
        style = {
            flow = 'horizontal',
            width = 400,
            height = 50,
            valign = 'center',
        },
        children = {
            gui.Label({
                text = text,
                style = {
                    width = 200,
                    height = 50,
                }
            }),
            gui.Input({
                text = document:try_get(attr, ''),
                id = 'Input' .. text,
                events = {
                    change = function(element)
                        document[attr] = element.text
                    end,
                },
                style = {
                    width = inputWidth,
                }
            }),
        },
    })
end

function DataTables.tbl_Gear.Dropdown(document, text, attr, options, unused, onchange)
    if onchange == nil then
        onchange = function(element)
            document[attr] = element.optionChosen
            DataTables.tbl_Gear.RecalculateForm(element)
        end
    end

    return gui.Panel({
        style = {
            flow = 'horizontal',
            width = 400,
            height = 50,
        },
        children = {
            gui.Label({
                text = text,
                style = {
                    width = 200,
                    height = 50,
                }
            }),
            gui.Dropdown({
                id = 'TypeDropdown',
                options = options,
                optionChosen = document:try_get(attr, options[1]),
                events = {
                    change = onchange,
                },
                style = {
                    width = 200,
                    height = 50,
                }
            }),
        }
    })
end

function DataTables.tbl_Gear.GetAvailableProperties(document)
    local allProperties = WeaponProperty.DropdownOptions(document)
    local options = {}

    for i = 1, #allProperties do
        if not document:HasProperty(allProperties[i].id) then
            options[#options + 1] = allProperties[i]
        end
    end

    return options
end

function DataTables.tbl_Gear.DescribeProperties(document)
    local properties = DataTables.tbl_Gear.GetAvailableProperties(document)
    local result = {}
    for i = 1, #properties do
        result[#result + 1] = properties[i].text
    end

    return result
end

function DataTables.tbl_Gear.DeleteProperty(document, propid)
    document[propid] = nil
end

local SetEquipmentType = function(document, typeStr)
    document.type = typeStr
    if typeStr == 'Weapon' then
        weapon.new(document)
        document.category = 'Simple'
    elseif typeStr == 'Armor' then
        armor.new(document)
        document.category = 'Light'
    elseif typeStr == 'Shield' then
        shield.new(document)
    else
        equipment.new(document)
    end
end

function DataTables.tbl_Gear.GenerateEditor(document, options)
    options = options or {}

    local resultPanel = nil
    local description = options.description or 'Create Item'

    local Refresh = function()
        resultPanel:FireEventTree('refresh')
    end

    local EnsureWieldObject = function(callback)
        if document:try_get("itemObjectId") ~= nil then
            if callback ~= nil then
                callback()
            end
            return
        end

        local objectJson = document:GetWieldObject()
        local guid = assets:UploadNewObject {
            description = document.name,
            previewType = "wield",
            imageId = objectJson.asset.imageId,
            hidden = true,
            components = objectJson.components,
        }


        dmhub.ScheduleWhen(function()
                local result = assets:GetObjectNode(guid) ~= nil
                return result
            end,
            function()
                document.itemObjectId = guid
                if callback ~= nil then
                    callback()
                end
                Refresh()
            end)
    end



    local emojiOptions = {}

    for k, emoji in pairs(assets.emojiTable) do
        if emoji.emojiType == "Accessory" then
            emojiOptions[#emojiOptions + 1] = {
                id = k,
                text = emoji.description,
            }
        end
    end

    table.sort(emojiOptions, function(a, b) return a.text < b.text end)
    table.insert(emojiOptions, 1, { id = "none", text = "None" })

    --function to create a simple Name: <child> panel.
    local FormPanel = function(options)
        local dmOnly = options.dmOnly

        local calculateCollapse = function()
            if dmOnly and not dmhub.isDM then
                return true
            end

            if options.collapse ~= nil and options.collapse() then
                return true
            end

            if options.types == nil then
                return false
            end

            local found = false
            for i, v in ipairs(options.types) do
                if v == document.type then
                    found = true
                end
            end

            return not found
        end

        --make a function to make this collapse if the type it's specified for doesn't exist.
        local shouldCollapse = nil
        if options.types ~= nil or options.collapse ~= nil then
            shouldCollapse = function(element)
                element:SetClass("collapsed-anim", calculateCollapse())
            end
        end

        local rowClasses = {"formStackedRow"}
        if calculateCollapse() then
            rowClasses[#rowClasses + 1] = "collapsed-anim"
        end
        if options.classes then
            for k, v in pairs(options.classes) do
                if type(k) == "string" and v then
                    rowClasses[#rowClasses + 1] = k
                elseif type(k) == "number" then
                    rowClasses[#rowClasses + 1] = v
                end
            end
        end

        if options.child ~= nil then
            options.child:SetClass("formStacked", true)
        end

        return gui.Panel {
            classes = rowClasses,
            events = {
                refresh = shouldCollapse,
            },
            children = {
                gui.Label {
                    classes = {"formStacked"},
                    text = options.text,
                },
                options.child,
            },
        }
    end

    local leftPanel = gui.Panel {
        style = {
            width = '45%',
            height = 'auto',
            halign = 'center',
            valign = 'top',
            flow = 'vertical',
        },
        children = {
            gui.Panel {
                id = "equipmentTypePanel",
                width = "100%",
                height = 'auto',
                flow = 'vertical',
                create = function(element)
                    local parentElement = element

                    local children = {}

                    local catTable = dmhub.GetTable('equipmentCategories') or {}

                    local typeNames = { 'Type:', 'Category:', 'Sub-Category:' }

                    local selection = { '' }

                    local equipmentCat = document:try_get("equipmentCategory")
                    if equipmentCat ~= nil then
                        local catInfo = catTable[equipmentCat]
                        local count = 1
                        while catInfo ~= nil and count < 10 do
                            table.insert(selection, 2, catInfo.id)

                            if catInfo:try_get("superset") ~= nil then
                                catInfo = catTable[catInfo.superset]
                            else
                                catInfo = nil
                            end
                            count = count + 1
                        end
                    end

                    for i, item in ipairs(selection) do
                        local options = {
                            {
                                id = 'choose',
                                text = 'Select Category...',
                                hidden = true,
                            }
                        }
                        for k, cat in pairs(catTable) do
                            if cat:try_get('superset', '') == item and (not cat:try_get("hidden", false)) then
                                options[#options + 1] = {
                                    id = cat.id,
                                    text = cat.name,
                                }
                            end
                        end

                        if #options > 1 then
                            local idchosen = 'choose'
                            if i + 1 <= #selection then
                                idchosen = selection[i + 1]
                            end

                            table.sort(options, function(a, b) return a.text < b.text end)

                            children[#children + 1] = FormPanel {
                                text = typeNames[i] or typeNames[#typeNames],
                                child = gui.Dropdown {
                                    classes = {"formStacked"},
                                    options = options,
                                    idChosen = idchosen,
                                    change = function(element)
                                        if element.idChosen ~= 'choose' then
                                            document.equipmentCategory = element.idChosen
                                            parentElement:FireEvent("create")
                                            local catInfo = catTable[element.idChosen]
                                            SetEquipmentType(document, catInfo.editorType)
                                            Refresh()
                                        end
                                    end,
                                }
                            }
                        end
                    end

                    element.children = children
                end,
            },

            FormPanel {
                text = "ID:",
                collapse = function()
                    return not devmode()
                end,
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "equipment-id-input",
                    text = document:try_get("id", "(unassigned)"),
                    refresh = function(element)
                        element.text = document:try_get("id", "(unassigned)")
                    end,
                },
            },

            FormPanel {
                text = "Name:",
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "equipment-name-input",

                    events = {
                        refresh = function(element)
                            element.text = document.name
                        end,
                        change = function(element)
                            if document:has_key("consumable") then
                                --if we have a consumable ability then remap its name with ours.
                                if document.consumable.name == document.name then
                                    document.consumable.name = element.text
                                end
                            end

                            document.name = element.text
                            Refresh()
                        end,
                    }
                },
            },

            FormPanel {
                text = "Availability:",
                collapse = function()
                    return (not EquipmentCategory.IsLightSource(document))
                end,
                child = gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = document:try_get("availability", "available"),
                    change = function(element)
                        document.availability = element.idChosen
                        Refresh()
                    end,
                    options = {
                        {
                            id = "available",
                            text = "Available",
                        },
                        {
                            id = "monsters",
                            text = "Monsters Only",
                        },
                        {
                            id = "restricted",
                            text = "Restricted",
                        },
                    }
                }
            },


            FormPanel {
                text = "Implementation:",
                child = gui.ImplementationStatusPanel {
                    classes = {"formStacked"},
                    value = document:try_get("implementation", 1),
                    change = function(element)
                        document.implementation = element.value
                    end,
                },
            },

            FormPanel {
                text = "Keywords:",
                child = gui.Multiselect {
                    classes = {"form"},
                    width = "100%",
                    halign = "left",
                    value = document:try_get("keywords", {}),
                    addItemText = "Add Keyword...",
                    options = GameSystem.KeywordsSetToDropdownList{GameSystem.abilityKeywords, GameSystem.itemKeywords},
                    change = function(element, value)
                        document.keywords = value
                        Refresh()
                    end,
                },
            },


            FormPanel {
                text = "Echelon:",
                collapse = function()
                    return (not EquipmentCategory.IsTreasure(document)) or EquipmentCategory.IsLeveledTreasure(document) or EquipmentCategory.IsImbuement(document)
                end,
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    options = {
                        {
                            id = 1,
                            text = "1st Echelon",
                        },
                        {
                            id = 2,
                            text = "2nd Echelon",
                        },
                        {
                            id = 3,
                            text = "3rd Echelon",
                        },
                        {
                            id = 4,
                            text = "4th Echelon",
                        },
                    },

                    events = {
                        refresh = function(element)
                            element.idChosen = document:try_get("echelon", 1)
                        end,
                        change = function(element)
                            document.echelon = element.idChosen
                            Refresh()
                        end,
                    }
                },
            },

            FormPanel {
                text = "Target Item Type:",
                collapse = function()
                    return not EquipmentCategory.IsImbuement(document)
                end,
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    options = {
                        { id = "armor", text = "Armor" },
                        { id = "implement", text = "Implement" },
                        { id = "weapon", text = "Weapon" },
                    },
                    events = {
                        refresh = function(element)
                            element.idChosen = document:try_get("imbueTargetType", "armor")
                        end,
                        change = function(element)
                            document.imbueTargetType = element.idChosen
                            Refresh()
                        end,
                    }
                },
            },

            FormPanel {
                text = "Level:",
                collapse = function()
                    return not EquipmentCategory.IsImbuement(document)
                end,
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    options = {
                        { id = 1, text = "Level 1" },
                        { id = 5, text = "Level 5" },
                        { id = 9, text = "Level 9" },
                    },
                    events = {
                        refresh = function(element)
                            element.idChosen = document:try_get("imbueLevel", 1)
                        end,
                        change = function(element)
                            document.imbueLevel = element.idChosen
                            Refresh()
                        end,
                    }
                },
            },

            FormPanel {
                text = "Item Prerequisite:",
                collapse = function()
                    return (not EquipmentCategory.IsTreasure(document))
                end,

                child = gui.Input {
                    classes = {"formStacked"},
                    text = document:try_get("itemPrerequisite", ""),
                    events = {
                        change = function(element)
                            document.itemPrerequisite = element.text
                            Refresh()
                        end,
                    },
                },
            },

            FormPanel {
                text = "Project Source:",
                collapse = function()
                    return (not EquipmentCategory.IsTreasure(document))
                end,

                child = gui.Input {
                    classes = {"formStacked"},
                    text = document:try_get("projectSource", ""),
                    events = {
                        change = function(element)
                            document.projectSource = element.text
                            Refresh()
                        end,
                    },
                },
            },

            FormPanel {
                text = "Project Roll Characteristic:",
                collapse = function()
                    return (not EquipmentCategory.IsTreasure(document))
                end,

                child = gui.Multiselect {
                    classes = {"formStacked"},
                    value = document:try_get("projectRollCharacteristic", {}),
                    addItemText = "Add Characteristic...",
                    options = creature.attributeDropdownOptions,
                    change = function(element, value)
                        document.projectRollCharacteristic = value
                        Refresh()
                    end,
                },
            },

            FormPanel {
                text = "Project Goal:",
                collapse = function()
                    return (not EquipmentCategory.IsTreasure(document))
                end,

                child = gui.Input {
                    classes = {"formStacked"},
                    text = document:try_get("projectGoal", ""),
                    events = {
                        change = function(element)
                            document.projectGoal = element.text
                            Refresh()
                        end,
                    },
                },
            },


            FormPanel {
                text = "Imbue Prerequisite:",
                collapse = function()
                    return not EquipmentCategory.IsImbuement(document)
                end,

                child = gui.Dropdown {
                    classes = {"formStacked"},
                    options = {},
                    idChosen = document:try_get("imbuePrereq", "none"),
                    hasSearch = true,

                    refresh = function(element)
                        if not EquipmentCategory.IsImbuement(document) then
                            return
                        end

                        local itemOptions = {
                            { id = "none", text = "(None)" },
                        }

                        local inventoryTable = dmhub.GetTable("tbl_Gear")
                        for k, item in pairs(inventoryTable) do
                            if (not item:try_get("hidden", false))
                               and k ~= document.id
                               and EquipmentCategory.IsImbuement(item) then
                                itemOptions[#itemOptions + 1] = {
                                    id = k,
                                    text = item.name,
                                }
                            end
                        end

                        table.sort(itemOptions, function(a, b) return a.text < b.text end)
                        element.options = itemOptions
                        element.idChosen = document:try_get("imbuePrereq", "none")
                    end,

                    change = function(element)
                        document.imbuePrereq = element.idChosen
                        Refresh()
                    end,
                },
            },

            FormPanel {
                text = "Replaces Prerequisite:",
                collapse = function()
                    return not EquipmentCategory.IsImbuement(document)
                        or document:try_get("imbuePrereq", "none") == "none"
                end,

                child = gui.Check {
                    classes = {"formStacked"},
                    text = "Replaces benefit of prerequisite",
                    value = document:try_get("imbueReplacesPrereq", false),
                    refresh = function(element)
                        element.value = document:try_get("imbueReplacesPrereq", false)
                    end,
                    change = function(element)
                        document.imbueReplacesPrereq = element.value
                        Refresh()
                    end,
                },
            },

            FormPanel {
                text = "",
                dmOnly = true,
                child = gui.Check {
                    classes = {"formStacked"},
                    id = "checkbox-hidden-from-players",
                    text = "Hide from Players",

                    events = {
                        hover = gui.Tooltip("Players will not be shown this item in list of all possible items. They will only see it if it is in their inventory."),
                        refresh = function(element)
                            element.value = document:try_get("hiddenFromPlayers", dmhub.GetSettingValue("hideitems"))
                        end,

                        change = function(element)
                            if element.value then
                                document.hiddenFromPlayers = true
                            else
                                document.hiddenFromPlayers = false
                            end
                        end,
                    }
                },
            },

            FormPanel {
                text = "Destroy Chance:",
                collapse = function()
                    return not document:IsAmmoForWeapon()
                end,
                child = gui.Input {
                    classes = {"formStacked"},
                    refresh = function(element)
                        local destroyChance = document:AmmoDestroyChance()
                        element.text = string.format("%d", round(destroyChance * 100))
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n ~= nil and n >= 0 and n <= 100 then
                            document.destroyChance = round(n)
                        end
                        Refresh()
                    end,

                },
            },

            gui.Panel {
                classes = { cond(document:IsAmmoForWeapon() or EquipmentCategory.IsConsumable(document), "collapsed-anim") },
                width = "auto",
                height = "auto",
                halign = "right",
                refresh = function(element)
                    element:SetClass("collapsed-anim",
                        document:IsAmmoForWeapon() or EquipmentCategory.IsConsumable(document))
                end,
                CharacterFeature.ListEditor(document, "features", {
                    dialog = gamehud.dialog.sheet,
                    createOptions = {
                        addText = "Add Magical Property",
                        itemAttached = true,
                        name = "Item Feature",
                        source = "Item",
                    }
                }),
            },


            gui.Panel {
                id = "ammoAugmentPanel",
                styles = {
                    Styles.Form,
                    CharacterFeature.ModifierStyles,
                    {
                        classes = { "form" },
                        halign = "left",
                        width = 180,
                    },
                    {
                        classes = { "formPanel" },
                        width = "100%",
                    },
                },
                width = 540,
                height = "auto",
                halign = "left",
                flow = "vertical",
                pad = 4,
                classes = { "bordered", cond(not document:IsAmmoForWeapon(), "collapsed-anim") },

                refreshModifier = function(element)
                end,

                refresh = function(element)
                    element:SetClass('collapsed-anim', not document:IsAmmoForWeapon())
                    if element:HasClass("collapsed-anim") then
                        return
                    end

                    if document:try_get("ammoAugmentation") == nil then
                        local augmentation = CharacterModifier.new {
                            behavior = 'modifyability',
                            guid = dmhub.GenerateGuid(),
                            name = "Ammo Modification",
                            source = "Ammunition",
                            description = "Ammunition modifies",
                            unconditional = true,
                        }

                        CharacterModifier.TypeInfo.modifyability.init(augmentation)
                        document.ammoAugmentation = augmentation
                    end

                    CharacterModifier.TypeInfo.modifyability.createEditor(document.ammoAugmentation, element.children[2])
                end,

                gui.Label {
                    classes = { "form-heading" },
                    text = "Modify Attacks",
                    bold = true,
                    halign = "left",
                    hmargin = 2,
                },

                gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                },
            },

            gui.Panel {
                id = "weaponBehaviorPanel",
                styles = {
                    Styles.Form,
                    CharacterFeature.ModifierStyles,
                    {
                        classes = { "form" },
                        halign = "left",
                        width = 180,
                    },
                    {
                        classes = { "formPanel" },
                        width = "100%",
                    },
                },
                width = 540,
                height = "auto",
                halign = "left",
                flow = "vertical",
                pad = 4,
                classes = { "bordered", cond(not document.isWeapon, "collapsed-anim") },

                refreshModifier = function(element)
                end,

                refresh = function(element)
                    element:SetClass('collapsed-anim', not document.isWeapon)
                    if element:HasClass("collapsed-anim") then
                        return
                    end

                    if document:try_get("weaponBehavior") == nil then
                        local augmentation = CharacterModifier.new {
                            behavior = 'modifyability',
                            guid = dmhub.GenerateGuid(),
                            name = "Weapon Modification",
                            source = "Weapon",
                            description = "Weapon modifiers",
                            unconditional = true,
                        }

                        CharacterModifier.TypeInfo.modifyability.init(augmentation)
                        document.weaponBehavior = augmentation
                    end

                    CharacterModifier.TypeInfo.modifyability.createEditor(document.weaponBehavior, element.children[2])
                end,

                gui.Label {
                    classes = { "form-heading" },
                    text = "Modify Attacks",
                    bold = true,
                    halign = "left",
                    hmargin = 2,
                },

                gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                },
            },

            gui.Panel {
                id = "packEditor",
                classes = {"bordered"},
                flow = "vertical",
                width = 300,
                height = "auto",
                vmargin = 8,
                hmargin = 8,
                pad = 8,

                gui.Label {
                    classes = {"sizeXl"},
                    halign = "center",
                    valign = "top",
                    width = "auto",
                    height = "auto",
                    text = "Pack Items",
                },

                gui.Dropdown {
                    options = {},
                    idChosen = "add",
                    hasSearch = true,
                    halign = "right",
                    refresh = function(element)
                        if element.parent:HasClass("collapsed") then
                            return
                        end


                        local itemOptions = {}

                        local inventoryTable = dmhub.GetTable("tbl_Gear")
                        for k, item in pairs(inventoryTable) do
                            if (not item:try_get("hidden", false)) and (not EquipmentCategory.IsTreasure(item)) and (not EquipmentCategory.IsMagical(item)) then
                                itemOptions[#itemOptions + 1] = {
                                    id = k,
                                    text = item.name,
                                }
                            end
                        end

                        table.sort(itemOptions, function(a, b) return a.text < b.text end)

                        itemOptions[#itemOptions + 1] = {
                            id = "add",
                            text = "Add Item...",
                        }

                        element.options = itemOptions

                        element.idChosen = "add"
                    end,

                    change = function(element)
                        if element.idChosen ~= "new" then
                            document.packItems = document:try_get("packItems", {})
                            document.packItems[#document.packItems + 1] = {
                                itemid = element.idChosen,
                                quantity = 1,
                            }
                            Refresh()
                        end
                    end,
                },

                refresh = function(element)
                    element:SetClass("collapsed", not EquipmentCategory.IsPack(document))
                    if element:HasClass("collapsed") then
                        return
                    end

                    local children = element.children

                    local label = children[1]

                    table.remove(children, 1)

                    local dropdown = children[#children]
                    children[#children] = nil

                    local newChildren = { label }

                    local packItems = document:try_get("packItems", {})
                    for i, packItem in ipairs(packItems) do
                        local panel = children[i] or gui.Panel {
                            width = "100%",
                            height = 30,
                            flow = "horizontal",
                            gui.Label {
                                classes = {"sizeM"},
                                width = 200,
                                height = "auto",
                                item = function(element, item)
                                    local inventoryTable = dmhub.GetTable("tbl_Gear")
                                    element.text = inventoryTable[item.itemid].name
                                end,
                            },

                            gui.Input {
                                classes = {"sizeM"},
                                width = 60,
                                item = function(element, item)
                                    element.text = tostring(item.quantity)
                                end,
                                change = function(element)
                                    local n = tonumber(element.text)
                                    if n ~= nil then
                                        n = round(n)
                                        if n <= 0 then
                                            table.remove(document.packItems, i)
                                        else
                                            document.packItems[i].quantity = n
                                        end
                                    end

                                    Refresh()
                                end,
                            },

                            gui.Button {
                                classes = {"deleteButton"},
                                click = function(element)
                                    table.remove(document.packItems, i)
                                    Refresh()
                                end,
                            },
                        }

                        newChildren[#newChildren + 1] = panel
                        panel:FireEventTree("item", packItem)
                    end

                    newChildren[#newChildren + 1] = dropdown
                    element.children = newChildren
                end,
            },



            FormPanel {
                text = "Quantity:",
                classes = {
                    ["collapsed-anim"] = (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]),
                },
                child = gui.Input {
                    classes = {"formStacked"},
                    text = string.format("%d", document:try_get("massQuantity", 1)),
                    change = function(element)
                        document.massQuantity = tonumber(element.text)
                        Refresh()
                    end,
                    refresh = function(element)
                        element.text = string.format("%d", document:try_get("massQuantity", 1))
                        element.parent:SetClass("collapsed-anim",
                            (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]))
                    end,
                },
            },

            --gear-specific fields.



            --[[
			FormPanel{
				text = 'Light Color:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get('emitLight') == nil),
				},
				child = gui.ColorPicker{
					id = 'color-picker-light',
					styles = {
						{
							valign = 'center',
							height = 24,
							width = 24,
						},
					},

					events = {
						refresh = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								element.value = light.color
							end
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or light == nil)
						end,
						
						change = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								light.color = element.value
							end
						end,
					}
				},
			},
--]]

            FormPanel {
                text = "Charges",
                types = { "Gear" },
                classes = {
                    ["collapsed"] = not EquipmentCategory.IsConsumable(document),
                },
                child = gui.Input {
                    classes = {"formStacked"},
                    characterLimit = 2,

                    events = {
                        refresh = function(element)
                            element.parent:SetClass("collapsed", not EquipmentCategory.IsConsumable(document))
                            element.text = tostring(document:try_get('consumableCharges', 1))
                        end,

                        change = function(element)
                            local n = tonumber(element.text)
                            if n ~= nil then
                                n = round(n)
                                if n >= 1 and n <= 99 then
                                    document.consumableCharges = n
                                end
                            end

                            element:FireEvent("refresh")
                            Refresh()
                        end,
                    }
                },
            },



            FormPanel {
                types = { 'Gear' },
                classes = {
                    ['collapsed'] = not EquipmentCategory.IsConsumable(document),
                },

                child = gui.Button {
                    classes = {"sizeM"},
                    width = 240,
                    text = "Consumable Ability",
                    click = function(element)
                        if not document:has_key("consumable") then
                            document.consumable = ActivatedAbility.Create {
                                name = document.name,
                                iconid = document.iconid,
                                attributeOverride = "no_attribute",
                                description = "",
                                range = 5,
                                behaviors = {},
                                consumables = { [document.id] = 1 },
                            }
                        end


                        element.root:AddChild(document.consumable:ShowEditActivatedAbilityDialog())
                    end,
                    refresh = function(element)
                        element.parent:SetClass("collapsed", not EquipmentCategory.IsConsumable(document))
                    end,

                }
            },

            --armor-specific fields.
            FormPanel {
                text = "Armor Class:",
                types = { "Armor" },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "armor-class-input",

                    events = {
                        refresh = function(element)
                            if element.parent:HasClass('collapsed-anim') then
                                return
                            end
                            element.text = tostring(document.armorClass)
                        end,
                        change = function(element)
                            if tonumber(element.text) ~= nil then
                                document.armorClass = math.floor(tonumber(element.text))
                            end
                        end,
                    }
                },
            },

            FormPanel {
                text = "Strength Req.:",
                types = { "Armor" },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "armor-strength-req-input",

                    events = {
                        refresh = function(element)
                            if element.parent:HasClass('collapsed-anim') then
                                return
                            end
                            if document:has_key('strength') then
                                element.text = tostring(document.strength)
                            else
                                element.text = ''
                            end
                        end,
                        change = function(element)
                            if tonumber(element.text) ~= nil then
                                document.strength = math.floor(tonumber(element.text))
                            else
                                document.strength = nil
                            end

                            element:FireEvent('refresh') --normalize the value.
                        end,
                    }
                },
            },

            FormPanel {
                text = "Effect on Stealth:",
                types = { "Armor" },
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    id = "armor-stealth-effect-input",

                    options = armor.possibleStealth,

                    events = {
                        refresh = function(element)
                            if element.parent:HasClass('collapsed-anim') then
                                return
                            end
                            element.optionChosen = document.stealth
                        end,
                        change = function(element)
                            document.stealth = element.optionChosen
                        end,
                    }
                },
            },

            FormPanel {
                text = "Dex. Mod. Limit:",
                types = { "Armor" },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "armor-dex-mod-limit-input",

                    events = {
                        refresh = function(element)
                            if element.parent:HasClass('collapsed-anim') then
                                return
                            end

                            if document:has_key('dexterityLimit') then
                                element.text = tostring(document.dexterityLimit)
                            else
                                element.text = ''
                            end
                        end,
                        change = function(element)
                            if tonumber(element.text) ~= nil then
                                document.dexterityLimit = math.floor(tonumber(element.text))
                            else
                                document.dexterityLimit = nil
                            end

                            element:FireEvent('refresh') --normalize the value.
                        end,
                    }
                },
            },

            --shield-specific fields.
            FormPanel {
                text = "AC Modifier:",
                types = { "Shield" },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "shield-armor-class-modifier-input",

                    events = {
                        refresh = function(element)
                            if element.parent:HasClass('collapsed-anim') then
                                return
                            end
                            element.text = tostring(document.armorClassModifier)
                        end,
                        change = function(element)
                            if tonumber(element.text) ~= nil then
                                document.armorClassModifier = math.floor(tonumber(element.text))
                            end

                            element:FireEvent('refresh') --normalize the value.
                        end,
                    }
                },
            },


            --weapon-specific fields.
            FormPanel {
                text = "Bonus to Hit:",
                types = { "Weapon" },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "weapon-bonus-input",
                    events = {
                        refresh = function(element)
                            element.text = tostring(document:try_get('hitbonus', 0))
                        end,
                        change = function(element)
                            document.hitbonus = tonumber(element.text) or nil
                        end,
                    },
                },
            },
            FormPanel {
                text = "Damage:",
                types = { "Weapon" },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "weapon-damage-input",

                    events = {
                        refresh = function(element)
                            element.text = tostring(document:try_get('damage', 1))
                        end,
                        change = function(element)
                            document.damage = element.text
                        end,
                    }
                },
            },

            FormPanel {
                text = "Versatile Damage:",
                classes = {
                    ["collapsed-anim"] = (document.type ~= "Weapon" or document.hands ~= "Versatile"),
                },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "weapon-versatile-damage-input",

                    events = {
                        refresh = function(element)
                            element.text = tostring(document:try_get('versatileDamage', ''))
                            element.parent:SetClass('collapsed-anim',
                                document.type ~= 'Weapon' or document.hands ~= 'Versatile')
                        end,
                        change = function(element)
                            document.versatileDamage = element.text
                        end,
                    }
                },
            },

            FormPanel {
                text = "Range:",
                classes = {
                    ["collapsed-anim"] = (document.type ~= "Weapon" or not document:IsRanged()),
                },
                child = gui.Input {
                    classes = {"formStacked"},
                    id = "weapon-range-input",
                    events = {
                        refresh = function(element)
                            element.text = tostring(document:try_get('range', ''))
                            element.parent:SetClass('collapsed-anim',
                                document.type ~= 'Weapon' or not document:IsRanged())
                        end,
                        change = function(element)
                            document.range = element.text
                        end,
                    }
                },
            },

            FormPanel {
                text = "Ammo:",
                classes = {
                    ["collapsed-anim"] = (document.type ~= "Weapon" or not document:HasProperty("ammo")),
                },
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    options = EquipmentCategory.ammunitionOptions,
                    idChosen = document:try_get("ammunitionType"),

                    refresh = function(element)
                        element.idChosen = document:try_get("ammunitionType")
                        element.parent:SetClass("collapsed-anim",
                            (document.type ~= 'Weapon' or not document:HasProperty('ammo')))
                    end,

                    change = function(element)
                        document.ammunitionType = element.idChosen
                        if document.ammunitionType == "none" then
                            document.ammunitionType = nil
                        end
                        Refresh()
                    end,
                },
            },

            FormPanel {
                text = "Damage Type:",
                types = { "Weapon" },
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    id = "weapon-damage-type",
                    options = rules.damageTypesAvailable,
                    optionChosen = document:try_get('damageType', 'slashing'),

                    events = {
                        refresh = function(element)
                            element.optionChosen = document:try_get('damageType', 'slashing')
                        end,

                        change = function(element)
                            document.damageType = element.optionChosen
                            Refresh()
                        end,
                    }
                },
            },

            FormPanel {
                text = "",
                types = { "Weapon" },
                child = gui.Check {
                    classes = {"formStacked"},
                    id = "weapon-magical-damage-checkbox",
                    text = "Magical Damage",

                    events = {
                        refresh = function(element)
                            element.value = document:has_key('damageMagical')
                        end,

                        change = function(element)
                            if element.value then
                                document.damageMagical = true
                            else
                                document.damageMagical = nil
                            end
                        end,
                    }
                },
            },

            FormPanel {
            },

            FormPanel {
                text = "Hands:",
                types = { "Weapon" },
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    id = "weapon-hands-dropdown",
                    options = weapon.handOptions,
                    optionChosen = document:try_get('hands', 'One-handed'),

                    events = {
                        refresh = function(element)
                            element.optionChosen = document:try_get('hands', 'One-handed')
                        end,

                        change = function(element)
                            document.hands = element.optionChosen
                            Refresh()
                        end,
                    }

                },
            },

            --[[ Are properties needed in Draw Steel?
            FormPanel {
                text = 'Properties:',
                collapse = function()
                    return not document:IsEquippable()
                end,
                child = gui.Dropdown {
                    id = 'weapon-properties-dropdown',

                    textOverride = "Add Property...",

                    events = {
                        refresh = function(element)
                            if document:IsEquippable() then
                                local options = DataTables.tbl_Gear.GetAvailableProperties(document)
                                element.options = options
                            end
                        end,

                        change = function(element)
                            document:SetProperty(element.idChosen, true)
                            element.options = DataTables.tbl_Gear.GetAvailableProperties(document)
                            Refresh()
                        end,
                    }
                },
            },
            --]]

            FormPanel {
                text = "Weapon Properties:",
                collapse = function() return not document:IsEquippable() end,
                child = gui.Multiselect {
                    classes = {"formStacked"},
                    value = (function()
                        local ids = {}
                        for k, _ in pairs(document:try_get("properties", {}) or {}) do
                            ids[#ids + 1] = k
                        end
                        return ids
                    end)(),
                    addItemText = "Add Property...",
                    options = WeaponProperty.DropdownOptions(document),
                    change = function(element, value)
                        local existing = document:try_get("properties", {}) or {}
                        local newProps = {}
                        for _, id in ipairs(value) do
                            newProps[id] = existing[id] or true
                        end
                        document.properties = newProps
                        Refresh()
                    end,
                },
            },

            gui.Panel {
                classes = {"collapsed-anim"},
                flow = "vertical",
                width = "100%",
                height = "auto",
                refresh = function(element)
                    if (not document:IsEquippable()) or document:try_get("properties") == nil then
                        element:SetClass("collapsed-anim", true)
                        element.children = {}
                        return
                    end
                    local rows = {}
                    for k, _ in pairs(document.properties) do
                        local prop = WeaponProperty.Get(k)
                        if prop ~= nil and prop.hasValue then
                            rows[#rows + 1] = FormPanel {
                                text = prop.name .. " value:",
                                child = gui.Input {
                                    classes = {"formStacked", "sizeS"},
                                    characterLimit = 4,
                                    refresh = function(input)
                                        local val = document.properties[k]
                                        local n = (type(val) == "table") and (val.value or 1) or 1
                                        input.text = tostring(n)
                                    end,
                                    change = function(input)
                                        local n = tonumber(input.text)
                                        if n ~= nil and n >= 1 then
                                            document.properties[k] = { value = math.floor(n) }
                                            Refresh()
                                        end
                                    end,
                                },
                            }
                        end
                    end
                    element:SetClass("collapsed-anim", #rows == 0)
                    element.children = rows
                end,
            },

        }
    }

    local iconEffectPanel = gui.Panel {
        style = { width = '100%', height = '100%', bgcolor = 'white' },
        selfStyle = {},
    }

    local UpdateIconEffectPanel = function()
        local iconEffect = document:try_get('iconEffect', 'none')
        iconEffectPanel:SetClass('hidden', iconEffect == 'none')
        if iconEffect ~= 'none' then
            local effect = ItemEffects[iconEffect]
            iconEffectPanel.bgimage = effect.video
            iconEffectPanel.selfStyle.opacity = effect.opacity or 1

            iconEffectPanel.bgimageMask = cond(effect.mask, document:GetIcon())
        end
    end

    UpdateIconEffectPanel()

    local rightPanel = gui.Panel {
        style = {
            width = '45%',
            height = 'auto',
            halign = 'center',
            valign = 'top',
            flow = 'vertical',
        },

        children = {

            gui.Panel {
                style = {
                    width = 128,
                    height = 128,
                    flow = 'none',
                },
                children = {
                    gui.IconEditor {
                        style = { bgcolor = 'white', width = 128, height = 128 },
                        value = document.iconid,
                        events = {
                            change = function(element)
                                if document:has_key("consumable") then
                                    --if we have a consumable ability then remap its icon with ours.
                                    if document.consumable.iconid == document.iconid then
                                        document.consumable.iconid = element.value
                                    end
                                end

                                if document:has_key("itemObjectId") then
                                    local asset = assets:GetObjectNode(document.itemObjectId)
                                    printf("RAW:: TRY GET ASSET...")
                                    if asset ~= nil then
                                        printf("RAW:: GET ASSET...")
                                        asset.imageId = dmhub.GetRawImageId(element.value)
                                        asset:Upload()
                                    end
                                end

                                document.iconid = element.value


                                UpdateIconEffectPanel()
                            end,
                        },
                    },
                    iconEffectPanel,
                }
            },

            --this allowed us to select from different effects to put on items.
            --removed for now until we make our effects system decent.
            --gui.Dropdown{
            --	options = ItemEffectsDropdownOptions(),
            --	idChosen = document:try_get('iconEffect', 'none'),
            --	selfStyle = {
            --		halign = 'center',
            --	},
            --	style = {
            --		width = 200,
            --		height = 50,
            --	},
            --	events = {
            --		change = function(element)
            --			if element.idChosen == 'none' then
            --				document.iconEffect = nil
            --			else
            --				document.iconEffect = element.idChosen
            --			end
            --			UpdateIconEffectPanel()
            --		end,
            --	},
            --},

            FormPanel {
                text = "Accessory:",
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    options = emojiOptions,
                    idChosen = document:try_get("accessory", "none"),
                    change = function(element)
                        if element.idChosen == "none" then
                            document.accessory = nil
                        else
                            document.accessory = element.idChosen
                        end
                    end,
                },
            },

            gui.Check {
                classes = {"sizeM"},
                halign = "center",
                text = "Has Inspection Image",
                refresh = function(element)
                    element.value = document:has_key("inspectionImage")
                end,

                change = function(element)
                    document.inspectionImage = cond(element.value, "")
                    resultPanel:FireEventTree("refresh")
                end,
            },


            gui.Panel {
                classes = { cond(not document:has_key("inspectionImage"), "collapsed") },
                refresh = function(element)
                    element:SetClass("collapsed", not document:has_key('inspectionImage'))
                end,
                style = {
                    width = 128,
                    height = 128,
                    flow = 'none',
                },
                children = {
                    gui.IconEditor {
                        style = { bgcolor = 'white', width = 128, height = 128 },
                        value = document:try_get("inspectionImage", ""),
                        events = {
                            change = function(element)
                                document.inspectionImage = element.value
                            end,
                        },
                    },
                    iconEffectPanel,
                }
            },

            --Item flavor text area.
            gui.Input {
                classes = {"sizeM"},
                width = 400,
                height = 30,
                vmargin = 4,
                halign = "center",
                textAlignment = "topleft",
                placeholderText = "Enter Flavor Text...",
                multiline = true,
                text = document.flavor,
                events = {
                    change = function(element)
                        document.flavor = element.text
                    end,
                }
            },

            --Item description text area.
            gui.Input {
                classes = {"sizeM"},
                width = 400,
                height = 140,
                vmargin = 4,
                halign = "center",
                textAlignment = "topleft",
                characterLimit = 8192,
                placeholderText = "Enter Description...",
                multiline = true,
                text = document.description,
                events = {
                    change = function(element)
                        document.description = element.text
                    end,
                }
            },

            --5th and 9th level increases for leveled treasures.
            gui.Panel{
                width = 400, height = "auto", vmargin = 4, halign = "center", flow = "vertical",
                refresh = function(element)
                    element:SetClass("collapsed", not EquipmentCategory.IsLeveledTreasure(document))
                end,

                gui.Label{
                    classes = {"sizeM"},
                    halign = "left",
                    width = "auto",
                    height = "auto",
                    text = "5th Level.",
                },

                --Item description text area.
                gui.Input {
                    classes = {"sizeM"},
                    width = 400,
                    height = 140,
                    vmargin = 4,
                    halign = "center",
                    textAlignment = "topleft",
                    characterLimit = 8192,
                    placeholderText = "Enter Level 5 effect...",
                    multiline = true,
                    text = document:try_get("level5", ""),
                    events = {
                        change = function(element)
                            document.level5 = element.text
                        end,
                    }
                },

                gui.Label{
                    classes = {"sizeM"},
                    halign = "left",
                    width = "auto",
                    height = "auto",
                    text = "9th Level.",
                },

                --Item description text area.
                gui.Input {
                    classes = {"sizeM"},
                    width = 400,
                    height = 140,
                    vmargin = 4,
                    halign = "center",
                    textAlignment = "topleft",
                    placeholderText = "Enter Level 9 effect...",
                    characterLimit = 8192,
                    multiline = true,
                    text = document:try_get("level9", ""),
                    events = {
                        change = function(element)
                            document.level9 = element.text
                        end,
                    }
                },

            },

            gui.Check {
                classes = {"sizeM", cond(not EquipmentCategory.IsLightSource(document), "collapsed")},
                halign = "center",
                text = "Display on Token",
                value = document:try_get("displayOnToken", true),
                refresh = function(element)
                    element:SetClass("collapsed", not EquipmentCategory.IsLightSource(document))
                end,

                change = function(element)
                    document.displayOnToken = element.value
                    Refresh()
                end,
            },

            gui.Button {
                classes = {"sizeM", cond(not EquipmentCategory.IsLightSource(document), "collapsed")},
                width = 160,
                text = "Edit Object",
                refresh = function(element)
                    element:SetClass("collapsed", not EquipmentCategory.IsLightSource(document))
                end,

                click = function(element)
                    EnsureWieldObject(
                        function()
                            dmhub.EditObjectDialog({ document.itemObjectId })
                        end
                    )
                end,
            },

            --ammo preview panel.
            gui.Panel {
                id = "ammoPreviewPanel",
                width = 400,
                height = "auto",
                flow = "vertical",
                classes = {
                    ['collapsed-anim'] = (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]),
                },
                refresh = function(element)
                    element:SetClass('collapsed-anim',
                        (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]))
                    if element:HasClass("collapsed-anim") then
                        element:FireEvent("destroy")
                    elseif element.data.previewFloor == nil then
                        local previewFloor = game.currentMap:CreatePreviewFloor("ObjectPreview")
                        previewFloor.cameraPos = { x = -20, y = 0 }
                        previewFloor.cameraSize = 1
                        element.data.previewFloor = previewFloor

                        local previewObj = Projectile.CreateProjectileObj(previewFloor, document, -20, 0)

                        local fieldMap = {}
                        local fieldList = previewObj:GetComponent("Core").fields
                        for _, field in ipairs(fieldList) do
                            fieldMap[field.id] = field
                        end

                        element.data.fields = fieldMap

                        game.Refresh {
                            currentMap = true,
                            floors = { previewFloor.floorid },
                            tokens = {},
                        }

                        local children = element.children
                        children[1].bgimage = string.format("#MapPreview%s", previewFloor.floorid)
                    end

                    if element.data.fields ~= nil then
                        element.data.fields["scale"].currentValue = document:try_get("projectileScale",
                            Projectile.DefaultScale)
                        element.data.fields["rotation"].currentValue = document:try_get("projectileRotation", 0)
                    end
                end,

                destroy = function(element)
                    if element.data.previewFloor ~= nil then
                        game.currentMap:DestroyPreviewFloor(element.data.previewFloor)
                        game.Refresh()
                        element.data.previewFloor = nil
                        element.data.previewObj = nil
                        element.data.fields = nil
                    end
                end,

                data = {
                    previewFloor = nil,
                    previewObj = nil,
                    fields = nil,
                },

                gui.Panel {
                    width = 1920 / 6,
                    height = 1080 / 6,
                    cornerRadius = 12,
                    bgcolor = "white",
                    vmargin = 8,
                },

                FormPanel {
                    text = "Scale:",
                    child = gui.Slider {
                        classes = {"formStacked"},
                        id = "slider-light-inner-radius",
                        style = {
                            height = 40,
                            width = 200,
                        },

                        sliderWidth = 140,
                        labelWidth = 50,

                        minValue = 0,
                        maxValue = 1,
                        value = document:try_get("projectileScale", Projectile.DefaultScale),

                        events = {
                            refresh = function(element)
                                element.value = document:try_get("projectileScale", Projectile.DefaultScale)
                            end,

                            change = function(element)
                                document.projectileScale = element.value
                                Refresh()
                            end,
                        }
                    },
                },

                FormPanel {
                    text = "Rotation:",
                    child = gui.Slider {
                        classes = {"formStacked"},
                        id = "slider-light-inner-radius",
                        style = {
                            height = 40,
                            width = 200,
                        },

                        sliderWidth = 140,
                        labelWidth = 50,

                        minValue = 0,
                        maxValue = 360,
                        value = document:try_get("projectileRotation", 0),

                        events = {
                            refresh = function(element)
                                element.value = document:try_get("projectileRotation", 0)
                            end,

                            change = function(element)
                                document.projectileRotation = element.value
                                Refresh()
                            end,
                        }
                    },
                },

            },
        },

    }

    resultPanel = gui.Panel {
        id = "MainTableGearForm",
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
        vscroll = true,
        width = 1060,
        height = 800,
        vpad = 8,
        flow = "vertical",
        valign = "top",
        margin = 0,

        children = {
            gui.Label {
                classes = {"dialogTitle"},
                text = options.description or "Create Item",
                width = "auto",
                height = "auto",
                halign = "center",
            },

            gui.Panel {
                style = {
                    width = '100%',
                    height = 'auto',
                    flow = 'horizontal',
                    valign = "top",
                },
                children = {
                    leftPanel,
                    rightPanel,
                },
            }

        }
    }

    Refresh()

    return resultPanel
end

function DataTables.tbl_Gear.GenerateForm(dialog, document)
    local description = 'Create Item'

    if dialog.isCreating == false then
        description = 'Edit Item'
    end
    dialog.sheet = DataTables.tbl_Gear.GenerateEditor(document, { description = description })
end
