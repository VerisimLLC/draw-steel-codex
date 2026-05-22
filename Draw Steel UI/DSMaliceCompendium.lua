local mod = dmhub.GetModLoading()

local ShowMalice
local CreateEditorPanel

Compendium.Register{
    section = "Rules",
    text = "Malice",
    contentType = "MonsterGroup",
    click = function(contentPanel)
        ShowMalice(contentPanel)
    end,
}

--- @param contentPanel Panel
ShowMalice = function(contentPanel)
    local dataItems = {}

    local rightPanel = gui.Panel{
        width = 1200,
        height = "90%",
        vscroll = true,
        flow = "vertical",
    }

    local itemsListPanel

    itemsListPanel = gui.Panel{
        classes = {"list-panel"},
        vscroll = true,
        monitorAssets = true,
        refreshAssets = function()
            local t = dmhub.GetTable(MonsterGroup.tableName)

            local newDataItems = {}
            local children = {}

            for k,item in pairs(t) do
                newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
                    tableName = MonsterGroup.tableName,
                    key = k,
                    select = itemsListPanel.aliveTime > 0.2,
                    click = function()
                        rightPanel.children = {
                            CreateEditorPanel(k, t[k])
                        }
                    end,
                }

                newDataItems[k].text = item.name

                children[#children+1] = newDataItems[k]
            end

            table.sort(children, function(a,b) return a.text < b.text end)
            dataItems = newDataItems
            itemsListPanel.children = children
        end,
    }

	itemsListPanel:FireEvent('refreshAssets')

	local leftPanel = gui.Panel{
		flow = "vertical",
		height = "100%",
		width = "auto",

		itemsListPanel,
        
		Compendium.AddButton{
			click = function(element)
				dmhub.SetAndUploadTableItem(MonsterGroup.tableName, MonsterGroup.CreateNew{})
			end,
		}
	}

    contentPanel.children = {leftPanel, rightPanel}
end


--- @param key string
--- @param monsterGroup MonsterGroup
CreateEditorPanel = function(key, monsterGroup)
    local m_dirty = false
    local Invalidate = function()
        m_dirty = true
    end

    local resultPanel
    resultPanel = gui.Panel{
        flow = "vertical",
        width = 800,
        height = "90%",
        vscroll = true,


        destroy = function()
            if m_dirty then
                dmhub.SetAndUploadTableItem(MonsterGroup.tableName, monsterGroup)
                m_dirty = false
            end
        end,
        gui.Panel{
            classes = {"formRow"},
            gui.Label{
                classes = {"form"},
                text = "Name:",
            },
            gui.Input{
                classes = {"form"},
                text = monsterGroup.name,
                change = function(element)
                    monsterGroup.name = element.text
                    dmhub.SetAndUploadTableItem(MonsterGroup.tableName, monsterGroup)
                end,
            }
        },

        gui.Multiselect{
            value = monsterGroup:try_get("inherits", {}),
            addItemText = "Inherits from Band...",
            options = (function()
                local t = dmhub.GetTable(MonsterGroup.tableName)
                local options = {}
                for k,v in unhidden_pairs(t) do
                    if k ~= key then
                        options[#options+1] = {id = k, text = v.name}
                    end
                end
                table.sort(options, function(a,b) return a.text < b.text end)
                return options
            end)(),
            change = function(element, val)
                monsterGroup.inherits = val
                Invalidate()
            end,
        },

        gui.Panel{
            width = 650,
            height = "auto",
            flow = "vertical",

            create = function(element)
                element:FireEvent("refreshAbilities")
            end,

            refreshAbilities = function(element)
                local children = {}
                for i,ability in ipairs(monsterGroup.maliceAbilities) do
                    children[#children+1] = gui.Panel{
                        flow = "vertical",
                        width = 600,
                        height = "auto",
                        vpad = 5,
                        
                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",

                            gui.Label{
                                classes = {"sizeM", "bold"},
                                width = 200,
                                height = 20,
                                text = ability.name,
                                lmargin = 4,
                            },

                            gui.Label{
                                classes = {"sizeS", "fgMuted"},
                                width = "auto",
                                height = 20,
                                text = "Min Level:",
                                lmargin = 10,
                                valign = "center",
                            },

                            gui.Dropdown{
                                width = 60,
                                height = 22,
                                valign = "center",
                                idChosen = tostring(ability:try_get("minLevel", 1)),
                                options = (function()
                                    local opts = {}
                                    for lvl = 1, 10 do
                                        opts[#opts+1] = {id = tostring(lvl), text = tostring(lvl)}
                                    end
                                    return opts
                                end)(),
                                change = function(element)
                                    ability.minLevel = tonumber(element.idChosen)
                                    dmhub.SetAndUploadTableItem(MonsterGroup.tableName, monsterGroup)
                                end,
                            },

                            gui.Button{
                                classes = {"settingsButton"},
                                halign = "right",
                                width = 15,
                                height = 15,
                                x = -15,
                                press = function(element)
                                    m_dirty = true
                                    --Make sure changes made with the ability are immediately shown
                                    element.root:AddChild(ability:ShowEditActivatedAbilityDialog{
                                        close = function()
                                            dmhub.SetAndUploadTableItem(MonsterGroup.tableName, monsterGroup)
                                            element.parent.parent.parent:FireEvent("refreshAbilities")
                                        end,
                                    })
                                end,
                            },

                            gui.Button{
                                classes = {"deleteButton"},
                                halign = "right",
                                hpad = 5,
                                width = 15,
                                height = 15,
                                press = function(element)
                                    table.remove(monsterGroup.maliceAbilities, i)
                                    dmhub.SetAndUploadTableItem(MonsterGroup.tableName, monsterGroup)
                                    element.parent.parent.parent:FireEvent("refreshAbilities")
                                end,
                            }

                        },

                        gui.DocumentDisplay{
                            width = 600,
                            height = "auto",
                            fontSize = 16,
                            text = ability.description,
                        },
                    }
                end

                children[#children+1] = gui.Button{
                    classes = {"addButton", "sizeL"},
                    halign = "right",
                    valign = "bottom",

                    click = function(element)
                        monsterGroup.maliceAbilities[#monsterGroup.maliceAbilities+1] = MaliceAbility.Create{
                            name = "New Malice Ability",
                        }
                        dmhub.SetAndUploadTableItem(MonsterGroup.tableName, monsterGroup)
                        element.parent:FireEvent("refreshAbilities")
                    end,
                }
                element.children = children
            end,

        },
    }

    return resultPanel
end
