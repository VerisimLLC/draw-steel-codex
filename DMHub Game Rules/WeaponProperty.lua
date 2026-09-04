local mod = dmhub.GetModLoading()


--- @class WeaponProperty
--- @field tableName string Data table name ("weaponProperties").
--- @field name string Display name.
--- @field details string Rules text describing this property.
--- @field hasValue boolean If true, this property carries a numeric value when applied to equipment.
--- @field hidden boolean If true, this property is not shown in UI menus.
--- @field modifiesAttacks boolean If true, this property modifies attack rolls.
--- @field itemType string Equipment category this property applies to: "weapon", "armor", "shield", "other", or "all".
--- @field features table[] List of features/modifiers granted by this property.
--- These are more correctly called "EquipmentProperty"; "WeaponProperty" is a historical name.
WeaponProperty = RegisterGameType("WeaponProperty")

WeaponProperty.tableName = "weaponProperties"
function WeaponProperty.GetTable()
    return dmhub.GetTable(WeaponProperty.tableName) or {}
end

WeaponProperty.name = "Property"
WeaponProperty.details = ""
WeaponProperty.hasValue = false
WeaponProperty.hidden = false

WeaponProperty.builtins = {}

WeaponProperty.modifiesAttacks = false

WeaponProperty.itemType = "weapon"

WeaponProperty.itemTypes = {
    {
        id = "weapon",
        text = "Weapon",
    },
    {
        id = "armor",
        text = "Armor",
    },
    {
        id = "shield",
        text = "Shield",
    },
    {
        id = "other",
        text = "Other",
    },
    {
        id = "all",
        text = "All",
    },
}

function WeaponProperty.CreateNew(args)
    args = args or {}

    args.features = args.features or {}

    return WeaponProperty.new(args)
end

function WeaponProperty.Get(key)
    return WeaponProperty.builtins[key] or WeaponProperty.GetTable()[key]
end

function WeaponProperty.DropdownOptions(item)
    local result = {}

    local itemType = "other"
    if item.isWeapon then
        itemType = "weapon"
    elseif item.isShield then
        itemType = "shield"
    elseif item.isArmor then
        itemType = "armor"
    end


    for k,v in pairs(WeaponProperty.GetTable()) do
        if (not v.hidden) and (v.itemType == "all" or v.itemType == itemType) then
            result[#result+1] = {
                id = k,
                text = v.name,
            }
        end
    end

    table.sort(result, function(a,b) return a.text < b.text end)

    return result
end


function WeaponProperty.CreateEditor()
    local resultPanel
    local m_item = nil
    local m_itemOriginal = nil

    local Upload = function()
        printf("UPLOAD:: %s", traceback())
        dmhub.SetAndUploadTableItem(WeaponProperty.tableName, m_item)
        m_itemOriginal = DeepCopy(m_item)
    end

    local OnChange = function()
        Upload()
        resultPanel:FireEventTree("editItem", m_item)
    end


    resultPanel = gui.Panel{
        classes = {"hidden"},

        flow = "vertical",
        width = 1000,
        maxHeight = 1000,
        height = "auto",
        vscroll = true,

        destroy = function(element)
            if m_item ~= nil and not dmhub.DeepEqual(m_item, m_itemOriginal) then
                Upload()
            end
        end,

        editItem = function(element, item)
            if item == m_item then
                return
            end

            if m_item ~= nil and not dmhub.DeepEqual(m_item, m_itemOriginal) then
                Upload()
            end

            m_item = item
            m_itemOriginal = DeepCopy(m_item)
            element:SetClass("hidden", false)
        end,

        gui.Label{
            classes = {"sizeM"},
            text = "This is a built-in property.",
            width = "auto",
            height = "auto",
            halign = "left",
            editItem = function(element, item)
                element:SetClass("hidden", WeaponProperty.builtins[item.id] == nil)
            end,
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "Equipment Type:",
            },

            gui.Dropdown{
                classes = {"formStacked"},
                options = WeaponProperty.itemTypes,
                editItem = function(element, item)
                    element.idChosen = item.itemType
                end,
                change = function(element)
                    m_item.itemType = element.idChosen
                    OnChange()
                end,
            },
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "Name:",
            },

            gui.Input{
                classes = {"formStacked"},
                editItem = function(element, item)
                    element.text = item.name
                end,
                change = function(element)
                    m_item.name = element.text
                    OnChange()
                end,
            }
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "Details:",
            },

            gui.Input{
                classes = {"formStacked"},
                multiline = true,
                placeholderText = "Enter rules text...",
                editItem = function(element, item)
                    element.text = item.details
                end,
                change = function(element)
                    m_item.details = element.text
                end,
            },
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Check{
                text = "Has Value",
                editItem = function(element, item)
                    element.value = item.hasValue
                end,
                change = function(element)
                    m_item.hasValue = element.value
                end,
            },
        },



        gui.Panel{
            classes = {"formStackedRow"},
            editItem = function(element, item)
                element:SetClass("collapsed", item.itemType ~= "weapon")
            end,
            gui.Check{
                text = "Modifies Attacks",
                editItem = function(element, item)
                    element.value = item.modifiesAttacks
                end,
                change = function(element)
                    if m_item.modifiesAttacks == element.value then
                        return
                    end

                    m_item.modifiesAttacks = element.value

                    if m_item.modifiesAttacks and m_item:try_get("attackModifier") == nil then

                        local augmentation = CharacterModifier.new{
                            behavior = 'modifyability',
                            guid = dmhub.GenerateGuid(),
                            name = "Weapon Modification",
                            source = "Weapon Property",
                            description = "Weapon modifiers",
                            unconditional = true,
                        }

                        CharacterModifier.TypeInfo.modifyability.init(augmentation)
                        m_item.attackModifier = augmentation
                    end

                    OnChange()
                end,
            },
        },

		gui.Panel{
			id = "weaponBehaviorPanel",
			classes = {"bordered"},
			styles = {
				CharacterFeature.ModifierStyles,
				{
					classes = {"formLabel"},
					halign = "left",
					width = 180,
				},
				{
					classes = {"formPanel"},
					width = "100%",
				},
			},
			width = 700,
			height = "auto",
			halign = "left",
			flow = "vertical",
			pad = 4,

            editItem = function(element, item)
                element:SetClass("collapsed", (not item.modifiesAttacks) or item.itemType ~= "weapon")

                if item.modifiesAttacks then
				    CharacterModifier.TypeInfo.modifyability.createEditor(item.attackModifier, element.children[2])
                end
            end,

			gui.Label{
				classes = {"form-heading"},
				text = "Modify Attacks",
				bold = true,
				halign = "left",
				hmargin = 2,
			},

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
			},
		},

		gui.Panel{
			width = "auto",
			height = "auto",
			halign = "right",
			editItem = function(element, item)
                element.children = {
                    CharacterFeature.ListEditor(item, "features", {
                        dialog = resultPanel.root,
                        createOptions = {
                            addText = "Add Special Properties",
                            itemAttached = true,
                            name = "Item Feature",
                            source = "Item",
                        }
                    }),
                }
			end,

		},


    }

    return resultPanel
end

dmhub.RegisterEventHandler("refreshTables", function()
    --[[ --not needed in Draw Steel?
    local tbl = WeaponProperty.GetTable()

    for _,p in ipairs(weapon.builtinWeaponProperties) do
        if tbl[p.attr] == nil then
            local entry = WeaponProperty.CreateNew{
                id = p.attr,
                name = p.text,
            }
            dmhub.SetAndUploadTableItem(WeaponProperty.tableName, entry)
        end
    end
    ]]
end)