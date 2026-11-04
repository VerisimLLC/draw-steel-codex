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

    ---@type Panel
    local resultPanel = nil
    local description = options.description or 'Create Item'

    --shows and hides the tabs once the fields have refreshed; set with the tabs.
    local RefreshTabs = nil

    local Refresh = function()
        resultPanel:FireEventTree('refresh')
        if RefreshTabs ~= nil then
            RefreshTabs()
        end
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

    --the tab on show: "general", "properties", "behaviors" or "craftable".
    local m_tab = "general"

    --The editor's fields, by name. The tabs below place each one; a field's own
    --refresh still collapses it when it does not apply to this item.
    local fields = {
            typePanel = gui.Panel {
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
                        ---@type EquipmentCategory?
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
                                        ---@cast element Dropdown
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

            id = FormPanel {
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

            name = FormPanel {
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

            availability = FormPanel {
                text = "Availability:",
                collapse = function()
                    return (not EquipmentCategory.IsLightSource(document))
                end,
                child = gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = document:try_get("availability", "available"),
                    change = function(element)
                        ---@cast element Dropdown
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


            implementation = FormPanel {
                text = "Implementation:",
                child = gui.ImplementationStatusPanel {
                    classes = {"formStacked"},
                    value = document:try_get("implementation", 1),
                    change = function(element)
                        document.implementation = element.value
                    end,
                },
            },

            keywords = FormPanel {
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


            echelon = FormPanel {
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
                            ---@cast element Dropdown
                            element.idChosen = document:try_get("echelon", 1)
                        end,
                        change = function(element)
                            ---@cast element Dropdown
                            document.echelon = element.idChosen
                            Refresh()
                        end,
                    }
                },
            },

            imbueTarget = FormPanel {
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
                            ---@cast element Dropdown
                            element.idChosen = document:try_get("imbueTargetType", "armor")
                        end,
                        change = function(element)
                            ---@cast element Dropdown
                            document.imbueTargetType = element.idChosen
                            Refresh()
                        end,
                    }
                },
            },

            imbueLevel = FormPanel {
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
                            ---@cast element Dropdown
                            element.idChosen = document:try_get("imbueLevel", 1)
                        end,
                        change = function(element)
                            ---@cast element Dropdown
                            document.imbueLevel = element.idChosen
                            Refresh()
                        end,
                    }
                },
            },

            itemPrerequisite = FormPanel {
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

            projectSource = FormPanel {
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

            projectRollCharacteristic = FormPanel {
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

            projectGoal = FormPanel {
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


            imbuePrereq = FormPanel {
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
                        ---@cast element Dropdown
                        document.imbuePrereq = element.idChosen
                        Refresh()
                    end,
                },
            },

            imbueReplaces = FormPanel {
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

            hideFromPlayers = FormPanel {
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

            destroyChance = FormPanel {
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

            features = gui.Panel {
                classes = { cond(document:IsAmmoForWeapon() or EquipmentCategory.IsConsumable(document), "collapsed-anim") },
                width = "auto",
                height = "auto",
                halign = "left",
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


            ammoAugment = gui.Panel {
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

            weaponBehavior = gui.Panel {
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

            pack = gui.Panel {
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
                        ---@cast element Dropdown
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



            quantity = FormPanel {
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

            charges = FormPanel {
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



            consumableAbility = FormPanel {
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

            --armor, shield and weapon stats: each row shows only for its type.
            stats = gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",
                data = {group = true},

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
                            local n = tonumber(element.text)
                            if n ~= nil then
                                document.armorClass = math.floor(n)
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
                            local n = tonumber(element.text)
                            if n ~= nil then
                                document.strength = math.floor(n)
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
                            ---@cast element Dropdown
                            if element.parent:HasClass('collapsed-anim') then
                                return
                            end
                            element.optionChosen = document.stealth
                        end,
                        change = function(element)
                            ---@cast element Dropdown
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
                            local n = tonumber(element.text)
                            if n ~= nil then
                                document.dexterityLimit = math.floor(n)
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
                            local n = tonumber(element.text)
                            if n ~= nil then
                                document.armorClassModifier = math.floor(n)
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
                        ---@cast element Dropdown
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
                            ---@cast element Dropdown
                            element.optionChosen = document:try_get('damageType', 'slashing')
                        end,

                        change = function(element)
                            ---@cast element Dropdown
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
                            ---@cast element Dropdown
                            element.optionChosen = document:try_get('hands', 'One-handed')
                        end,

                        change = function(element)
                            ---@cast element Dropdown
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
            },

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

    --The art, how the item shows on the map, and its text, by name as above.
    local media = {

            icon = gui.Panel {
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

            accessory = FormPanel {
                text = "Accessory:",
                child = gui.Dropdown {
                    classes = {"formStacked"},
                    options = emojiOptions,
                    idChosen = document:try_get("accessory", "none"),
                    change = function(element)
                        ---@cast element Dropdown
                        if element.idChosen == "none" then
                            document.accessory = nil
                        else
                            document.accessory = element.idChosen
                        end
                    end,
                },
            },

            inspectionCheck = gui.Check {
                classes = {"sizeM"},
                halign = "left",
                text = "Has Inspection Image",
                refresh = function(element)
                    element.value = document:has_key("inspectionImage")
                end,

                change = function(element)
                    document.inspectionImage = cond(element.value, "")
                    resultPanel:FireEventTree("refresh")
                end,
            },


            inspectionImage = gui.Panel {
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
            flavor = gui.Input {
                classes = {"sizeM"},
                width = "100%",
                height = 140,
                vmargin = 4,
                halign = "left",
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
            description = gui.Input {
                classes = {"sizeM"},
                width = "100%",
                height = 140,
                vmargin = 4,
                halign = "left",
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

            --5th and 9th level increases for leveled treasures, side by side.
            levels = gui.Panel{
                width = "100%", height = "auto", vmargin = 4, halign = "left", flow = "horizontal",
                refresh = function(element)
                    element:SetClass("collapsed", not EquipmentCategory.IsLeveledTreasure(document))
                end,

                gui.Panel{
                    width = "48%", height = "auto", halign = "left", flow = "vertical",

                    gui.Label{
                        classes = {"formStacked"},
                        text = "5th Level",
                    },

                    gui.Input {
                        classes = {"sizeM"},
                        width = "100%",
                        height = 140,
                        vmargin = 4,
                        halign = "left",
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
                },

                gui.Panel{
                    width = "48%", height = "auto", halign = "right", flow = "vertical",

                    gui.Label{
                        classes = {"formStacked"},
                        text = "9th Level",
                    },

                    gui.Input {
                        classes = {"sizeM"},
                        width = "100%",
                        height = 140,
                        vmargin = 4,
                        halign = "left",
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
            },

            displayOnToken = gui.Check {
                classes = {"sizeM", cond(not EquipmentCategory.ShowWieldObjectEditor(document), "collapsed")},
                halign = "left",
                text = "Display on Token",
                value = document:try_get("displayOnToken", true),
                refresh = function(element)
                    element:SetClass("collapsed", not EquipmentCategory.ShowWieldObjectEditor(document))
                end,

                change = function(element)
                    document.displayOnToken = element.value
                    Refresh()
                end,
            },

            editObject = gui.Button {
                classes = {"sizeM", cond(not EquipmentCategory.ShowWieldObjectEditor(document), "collapsed")},
                width = 160,
                halign = "left",
                text = "Edit Object",
                refresh = function(element)
                    element:SetClass("collapsed", not EquipmentCategory.ShowWieldObjectEditor(document))
                end,

                click = function(element)
                    EnsureWieldObject(
                        function()
                            dmhub.EditObjectDialog({ document.itemObjectId })
                        end
                    )
                end,
            },

            --ammo preview panel. Its 3D preview is only built while General is showing.
            ammoPreview = gui.Panel {
                id = "ammoPreviewPanel",
                width = 400,
                height = "auto",
                flow = "vertical",
                classes = {
                    ['collapsed-anim'] = not EquipmentCategory.ShowProjectilePreview(document),
                },
                refresh = function(element)
                    element:SetClass('collapsed-anim',
                        m_tab ~= "general" or not EquipmentCategory.ShowProjectilePreview(document))
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

    }

    --== Craftable: the recipe and components ==================================
    --craftRecipe is the id of the recipe item; craftComponents lists
    --{itemid, quantity}, the shape packItems uses. Both are picked from tbl_Gear.

    --the item picker binds its rows in batches: the first at once, the rest
    --this far apart, so a long list opens without a stall.
    local PICKER_BATCH = 15
    local PICKER_BATCH_DELAY = 0.1

    --- An item's icon in a dark square, for craft tiles and picker rows. Fire
    --- setItem with the item, or with nil for an empty slot's plus.
    --- @param size number
    --- @return Panel
    local function CraftIcon(size)
        local image = gui.Panel {
            classes = {"image", "collapsed"},
            bgimage = "panels/square.png",
            bgcolor = "white",
            width = "100%",
            height = "100%",
            cornerRadius = 6,
            interactable = false,
        }
        local plus = gui.Panel {
            classes = {"iconButton", "collapsed"},
            bgimage = "phosphor/plus-bold.png",
            width = math.floor(size * 0.4),
            height = math.floor(size * 0.4),
            halign = "center",
            valign = "center",
            interactable = false,
        }
        return gui.Panel {
            classes = {"bg"},
            width = size,
            height = size,
            cornerRadius = 6,
            valign = "center",
            flow = "none",
            interactable = false,
            setItem = function(element, item)
                local icon = nil
                if item ~= nil then
                    pcall(function() icon = item:GetIcon() end)
                end
                local has = type(icon) == "string" and icon ~= ""
                image:SetClass("collapsed", not has)
                if has then
                    image.bgimage = icon
                end
                plus:SetClass("collapsed", item ~= nil)
            end,
            image,
            plus,
        }
    end

    --- An item name on one line: left-aligned, cut off with an ellipsis at its
    --- width. It takes no input, so a press reaches the row it sits on.
    --- @param args table gui.Label args; width is required
    --- @return Label
    local function NameLabel(args)
        args.textWrap = false
        args.textOverflow = "ellipsis"
        args.textAlignment = "left"
        args.halign = "left"
        args.height = "auto"
        args.interactable = false
        return gui.Label(args)
    end

    --- A row's linger handler: the whole name as a tooltip when its label has
    --- cut it off.
    --- @param label Label
    --- @return fun(element: Panel)
    local function FullNameTooltip(label)
        return function(element)
            local ok, size = pcall(function() return label:CalculatePreferredSize() end)
            if ok and size ~= nil and size.x > label.renderedWidth + 0.5 then
                gui.Tooltip(label.text)(element)
            end
        end
    end

    --- The delete button on a craft row.
    --- @param onRemove fun(element: Panel)
    --- @return Panel
    local function CraftRemove(onRemove)
        return gui.Button {
            classes = {"deleteButton", "sizeS"},
            valign = "center",
            lmargin = 8,
            swallowPress = true,
            click = onRemove,
        }
    end

    --- A craft row in the shape of the inventory sheet's rows: the icon and the
    --- words at the left, a right-hand group (quantity, delete) at the right.
    --- extra holds the row's own fields: press, refresh, data and the like.
    --- @param icon Panel
    --- @param words Panel[]
    --- @param right Panel[]
    --- @param extra table
    --- @return Panel
    local function CraftRow(icon, words, right, extra)
        icon.selfStyle.halign = "left"
        icon.selfStyle.lmargin = 8
        local args = {
            classes = {"bgAlt"},
            width = "100%",
            height = 48,
            flow = "horizontal",
            tmargin = 4,
            icon,
            gui.Panel {
                width = "62%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                lmargin = 10,
                interactable = false,
                children = words,
            },
            gui.Panel {
                width = "auto",
                height = "100%",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                rmargin = 8,
                children = right,
            },
        }
        for k, v in pairs(extra) do
            args[k] = v
        end
        return gui.Panel(args)
    end

    --- A section header on the Craftable tab: a label with a rule beneath it.
    --- @param text string
    --- @return Panel
    local function CraftHeader(text)
        return gui.Panel {
            classes = {"bordered", "transparent"},
            border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
            cornerRadius = 0,
            width = "100%",
            height = "auto",
            tmargin = 10,
            bmargin = 6,
            gui.Label { classes = {"sizeS", "bold"}, text = text, width = "auto", height = "auto", halign = "left", bmargin = 2 },
        }
    end

    --The item picker: one overlay on the editor, built with it and re-bound on
    --each open. Its rows are pooled for the editor's life: a search or a new
    --open re-binds them, and only a longer list than any before adds rows.
    local pickerCandidates = {}
    local pickerRows = {}
    local pickerOnPick = nil

    local pickerEmpty = gui.Label {
        classes = {"sizeS", "fgMuted", "collapsed"},
        text = "No items match.",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 8,
    }
    local pickerList = gui.Panel {
        width = "100%",
        height = 300,
        vscroll = true,
        flow = "vertical",
        pickerEmpty,
    }
    local pickerTitle = gui.Label { classes = {"sizeL", "bold"}, text = "", width = "auto", height = "auto", halign = "left", valign = "center" }

    ---@type Panel
    local pickerPanel = nil

    --bumped by each open, search and close; a pending batch from an older
    --one sees the change and stops.
    local pickerGeneration = 0

    local function ClosePicker()
        pickerGeneration = pickerGeneration + 1
        pickerOnPick = nil
        pickerPanel.captureEscape = false
        pickerPanel:SetClass("collapsed", true)
    end

    --- One pooled picker row; ShowPicker binds it to an item.
    --- @return Panel
    local function NewPickerRow()
        local icon = CraftIcon(28)
        icon.selfStyle.lmargin = 6
        icon.selfStyle.halign = "left"
        local label = NameLabel { classes = {"sizeS"}, text = "", width = "78%", valign = "center", lmargin = 8 }
        --90% of the list, leaving room on the right for its scroll bar.
        local row = gui.Panel {
            classes = {"hoverable"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "90%",
            height = 40,
            halign = "left",
            flow = "horizontal",
            data = { id = nil },
            linger = FullNameTooltip(label),
            press = function(element)
                local onPick = pickerOnPick
                local id = element.data.id
                ClosePicker()
                if onPick ~= nil and id ~= nil then
                    onPick(id)
                end
            end,
            icon,
            label,
        }
        row.data.icon = icon
        row.data.label = label
        return row
    end

    --- Binds the pooled rows to the candidates the search matches (all of
    --- them with no search), a batch at a time.
    --- @param query string lower case, or ""
    local function ShowPicker(query)
        pickerGeneration = pickerGeneration + 1
        local generation = pickerGeneration

        local matches = {}
        for _, candidate in ipairs(pickerCandidates) do
            if query == "" or string.find(candidate.lower, query, 1, true) ~= nil then
                matches[#matches + 1] = candidate
            end
        end
        pickerEmpty:SetClass("collapsed", #matches > 0)
        for _, row in ipairs(pickerRows) do
            row:SetClass("collapsed", true)
        end

        local bound = 0
        local function BindBatch()
            if mod.unloaded or generation ~= pickerGeneration or not pickerPanel.valid then
                return
            end
            local last = math.min(#matches, bound + PICKER_BATCH)
            for i = bound + 1, last do
                local candidate = matches[i]
                local row = pickerRows[i]
                if row == nil then
                    row = NewPickerRow()
                    pickerRows[i] = row
                    pickerList:AddChild(row)
                end
                row.data.id = candidate.id
                row.data.label.text = candidate.name
                row.data.icon:FireEvent("setItem", candidate.item)
                row:SetClass("collapsed", false)
            end
            bound = last
            if bound < #matches then
                dmhub.Schedule(PICKER_BATCH_DELAY, BindBatch)
            end
        end
        BindBatch()
    end

    --the search box pads 24px each side on top of its width.
    local pickerSearch = gui.SearchInput {
        placeholderText = "Search items",
        width = "85%",
        halign = "left",
        height = 30,
        vmargin = 6,
        search = function(element, query)
            ShowPicker(query)
        end,
    }

    pickerPanel = gui.Panel {
        classes = {"framedPanel", "collapsed"},
        floating = true,
        halign = "center",
        valign = "center",
        width = 360,
        height = "auto",
        flow = "vertical",
        pad = 10,
        captureEscape = false,
        escapePriority = EscapePriority.DMHUB_POPUP,
        escape = function(element)
            ClosePicker()
        end,
        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            pickerTitle,
            gui.Button {
                classes = {"closeButton"},
                halign = "right",
                valign = "center",
                click = function(element)
                    ClosePicker()
                end,
            },
        },
        pickerSearch,
        pickerList,
    }

    --- Opens the item picker: a search box and the items that pass filter, by
    --- name. onPick gets the chosen item's id.
    --- @param title string
    --- @param filter fun(id: string, item: table): boolean
    --- @param onPick fun(id: string)
    local function OpenItemPicker(title, filter, onPick)
        local candidates = {}
        for id, item in unhidden_pairs(dmhub.GetTable("tbl_Gear") or {}) do
            if id ~= document.id and filter(id, item) then
                local name = item.name or ""
                candidates[#candidates + 1] = { id = id, item = item, name = name, lower = string.lower(name) }
            end
        end
        table.sort(candidates, function(a, b) return a.name < b.name end)
        pickerCandidates = candidates
        pickerOnPick = onPick
        pickerTitle.text = title
        --clearing the search through its own edit event resets the search
        --box's memory of the last query, and binds the full list.
        pickerSearch.text = ""
        pickerSearch:FireEvent("edit")
        ShowPicker("")
        pickerPanel:SetClass("collapsed", false)
        pickerPanel.captureEscape = true
    end

    local function GearItem(itemid)
        if itemid == nil then
            return nil
        end
        return (dmhub.GetTable("tbl_Gear") or {})[itemid]
    end

    --the recipe: one row, or "Choose recipe" while none is set.
    local recipeIcon = CraftIcon(36)
    local recipeName = NameLabel { classes = {"bold"}, text = "", width = "95%" }
    local recipeKind = gui.Label { classes = {"sizeXs", "fgMuted"}, text = "Recipe", width = "auto", height = "auto", halign = "left" }
    local recipeRemove = CraftRemove(function(element)
        document.craftRecipe = nil
        Refresh()
    end)
    local recipeTile = CraftRow(recipeIcon, { recipeName, recipeKind }, { recipeRemove }, {
        classes = {"bgAlt", "hoverable"},
        linger = FullNameTooltip(recipeName),
        press = function(element)
            OpenItemPicker("Choose recipe", function(id, item)
                return string.find(string.lower(item.name or ""), "recipe", 1, true) ~= nil
            end, function(id)
                document.craftRecipe = id
                Refresh()
            end)
        end,
        refresh = function(element)
            local item = GearItem(document:try_get("craftRecipe"))
            local chosen = item ~= nil
            recipeIcon:FireEvent("setItem", item)
            recipeKind:SetClass("collapsed", not chosen)
            recipeRemove:SetClass("collapsed", document:try_get("craftRecipe") == nil)
            recipeName:SetClass("fgMuted", not chosen)
            if item ~= nil then
                recipeName.text = item.name
            elseif document:try_get("craftRecipe") ~= nil then
                recipeName.text = "(Missing item)"
            else
                recipeName.text = "Choose recipe"
            end
        end,
    })

    --the components: a row each with its quantity, then "Add component".
    local componentCount = gui.Label { classes = {"sizeXs", "fgMuted"}, text = "", width = "auto", height = "auto", halign = "right", valign = "center" }

    --- One component row, bound to a craftComponents index by setComponent.
    --- @return Panel
    local function NewComponentTile()
        local icon = CraftIcon(36)
        local name = NameLabel { classes = {"bold"}, text = "", width = "95%" }
        --the craftComponents index this row shows; set by setComponent.
        local index = 0
        local quantity = gui.Input {
            classes = {"sizeS", "bordered"},
            width = 44,
            height = 26,
            valign = "center",
            textAlignment = "center",
            characterLimit = 3,
            text = "1",
            change = function(element)
                local entry = (document:try_get("craftComponents", {}))[index]
                local n = tonumber(element.text)
                if entry ~= nil and n ~= nil and n >= 1 then
                    entry.quantity = math.floor(n)
                end
                Refresh()
            end,
        }
        local remove = CraftRemove(function(element)
            local list = document:try_get("craftComponents", {})
            table.remove(list, index)
            document.craftComponents = list
            Refresh()
        end)
        return CraftRow(icon, { name }, { quantity, remove }, {
            linger = FullNameTooltip(name),
            setComponent = function(element, newIndex, entry)
                index = newIndex
                local item = GearItem(entry.itemid)
                icon:FireEvent("setItem", item)
                name.text = item ~= nil and item.name or "(Missing item)"
                if not quantity.hasInputFocus then
                    quantity.text = tostring(entry.quantity or 1)
                end
            end,
        })
    end

    local componentAddIcon = CraftIcon(36)
    local componentAdd = CraftRow(componentAddIcon, {
        gui.Label { classes = {"fgMuted"}, text = "Add component", width = "auto", height = "auto", halign = "left" },
    }, {}, {
        classes = {"bgAlt", "hoverable"},
        refresh = function(element)
            componentAddIcon:FireEvent("setItem", nil)
        end,
        press = function(element)
            local taken = {}
            for _, entry in ipairs(document:try_get("craftComponents", {})) do
                taken[entry.itemid] = true
            end
            --crafting ingredients only, leaving out the recipes filed with them.
            OpenItemPicker("Add component", function(id, item)
                return not taken[id]
                    and EquipmentCategory.IsCraftingIngredient(item)
                    and string.find(string.lower(item.name or ""), "recipe", 1, true) == nil
            end, function(id)
                local list = document:try_get("craftComponents", {})
                list[#list + 1] = { itemid = id, quantity = 1 }
                document.craftComponents = list
                Refresh()
            end)
        end,
    })

    --rows are pooled: one per component, the extras collapsed, Add last.
    local componentTiles = {}
    local componentGrid = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        refresh = function(element)
            local list = document:try_get("craftComponents", {})
            componentCount.text = tostring(#list)
            local grew = false
            while #componentTiles < #list do
                componentTiles[#componentTiles + 1] = NewComponentTile()
                grew = true
            end
            if grew then
                local children = {}
                for _, tile in ipairs(componentTiles) do
                    children[#children + 1] = tile
                end
                children[#children + 1] = componentAdd
                element.children = children
            end
            for i, tile in ipairs(componentTiles) do
                tile:SetClass("collapsed", i > #list)
                if i <= #list then
                    tile:FireEvent("setComponent", i, list[i])
                end
            end
        end,
        componentAdd,
    }

    --== The tabs ===============================================================

    --- A column of fields inside a tab. data.group marks it as a container, so
    --- an empty-tab check looks through it to the fields.
    --- @param width string|number
    --- @param children Panel[]
    --- @return Panel
    local function Column(width, children)
        return gui.Panel {
            width = width,
            height = "auto",
            flow = "vertical",
            valign = "top",
            halign = "left",
            data = { group = true },
            children = children,
        }
    end

    --- Two columns side by side; the right one hugs the right edge.
    --- @param left Panel
    --- @param right Panel
    --- @return Panel
    local function Columns(left, right)
        right.selfStyle.halign = "right"
        return gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            data = { group = true },
            left,
            right,
        }
    end

    --- A tab's body: 94% of the scroll area, inset from the left, which
    --- leaves the right side clear for the scroll bar.
    --- @param children Panel[]
    --- @return Panel
    local function TabRoot(children)
        return gui.Panel {
            width = "94%",
            height = "auto",
            flow = "vertical",
            valign = "top",
            halign = "left",
            lmargin = 16,
            tmargin = 8,
            data = { group = true },
            children = children,
        }
    end

    local tabPanels = {
        general = TabRoot {
            Columns(
                Column("48%", { fields.typePanel, fields.id, fields.name, fields.keywords, fields.availability, fields.hideFromPlayers }),
                Column("48%", {
                    gui.Panel {
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        data = { group = true },
                        media.icon,
                        gui.Panel {
                            width = "66%",
                            height = "auto",
                            flow = "vertical",
                            valign = "top",
                            halign = "right",
                            data = { group = true },
                            media.accessory,
                            media.inspectionCheck,
                            media.displayOnToken,
                            media.editObject,
                        },
                    },
                    media.inspectionImage,
                    media.ammoPreview,
                })
            ),
            Columns(
                Column("48%", { gui.Label { classes = {"formStacked"}, text = "Flavor" }, media.flavor }),
                Column("48%", { gui.Label { classes = {"formStacked"}, text = "Description" }, media.description })
            ),
            media.levels,
        },

        properties = TabRoot {
            Columns(
                Column("48%", { fields.echelon, fields.imbueTarget, fields.imbueLevel, fields.imbuePrereq, fields.imbueReplaces, fields.quantity, fields.charges, fields.destroyChance }),
                Column("48%", { fields.pack, fields.stats })
            ),
        },

        behaviors = TabRoot { fields.implementation, fields.features, fields.ammoAugment, fields.weaponBehavior, fields.consumableAbility },

        craftable = TabRoot {
            Columns(
            Column("48%", { fields.itemPrerequisite, fields.projectSource, fields.projectRollCharacteristic, fields.projectGoal }),
            Column("48%", {
                CraftHeader("RECIPE"),
                recipeTile,
                gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "none",
                    CraftHeader("COMPONENTS"),
                    componentCount,
                },
                componentGrid,
            })
            ),
        },
    }

    local TAB_ORDER = { "general", "properties", "behaviors", "craftable" }
    local TAB_TEXT = { general = "General", properties = "Properties", behaviors = "Behaviors", craftable = "Craftable" }

    --- Whether anything in a tab shows: a field not collapsed, looking through
    --- the tab's columns to the fields inside them.
    --- @param panel Panel
    --- @return boolean
    local function HasVisibleContent(panel)
        for _, child in ipairs(panel.children) do
            if not (child:HasClass("collapsed") or child:HasClass("collapsed-anim")) then
                if not child.data.group or HasVisibleContent(child) then
                    return true
                end
            end
        end
        return false
    end

    local tabLabels = {}

    --- Shows one tab and hides the others.
    --- @param id string
    local function SelectTab(id)
        m_tab = id
        if not pickerPanel:HasClass("collapsed") then
            ClosePicker()
        end
        for _, tabid in ipairs(TAB_ORDER) do
            tabLabels[tabid]:SetClass("selected", tabid == id)
            tabPanels[tabid]:SetClass("collapsed", tabid ~= id)
        end
        Refresh()
    end

    for _, tabid in ipairs(TAB_ORDER) do
        tabLabels[tabid] = gui.Label {
            classes = { "tab", cond(tabid == m_tab, "selected") },
            halign = "left",
            text = TAB_TEXT[tabid],
            press = function(element)
                SelectTab(tabid)
            end,
        }
        tabPanels[tabid]:SetClass("collapsed", tabid ~= m_tab)
    end

    --Craftable shows for items a project can make (the same rule that showed
    --the crafting fields); Properties and Behaviors hide when they would be
    --empty. A tab that goes away while open hands over to General.
    RefreshTabs = function()
        local shown = {
            general = true,
            properties = HasVisibleContent(tabPanels.properties),
            behaviors = HasVisibleContent(tabPanels.behaviors),
            craftable = EquipmentCategory.IsTreasure(document),
        }
        for _, tabid in ipairs(TAB_ORDER) do
            tabLabels[tabid]:SetClass("collapsed", not shown[tabid])
        end
        if not shown[m_tab] then
            SelectTab("general")
        end
    end

    --full width, so the tab bar's base line runs on past the last tab.
    local tabBar = gui.Panel {
        classes = {"tabBar"},
        width = "100%-32",
        halign = "center",
        valign = "top",
        vmargin = 6,
    }
    for _, tabid in ipairs(TAB_ORDER) do
        tabBar:AddChild(tabLabels[tabid])
    end

    resultPanel = gui.Panel {
        id = "MainTableGearForm",
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
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

            tabBar,

            gui.Panel {
                width = "100%",
                height = "100%-90",
                vscroll = true,
                flow = "vertical",
                tabPanels.general,
                tabPanels.properties,
                tabPanels.behaviors,
                tabPanels.craftable,
            },

            --last, so it draws over the tabs while open.
            pickerPanel,
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
