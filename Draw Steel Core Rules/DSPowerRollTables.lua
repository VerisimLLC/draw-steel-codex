local mod = dmhub.GetModLoading()

--- @class PowerRollTable
--- @field name string Display name for this power roll tier table.
--- @field entries table[] List of tier entries with outcome descriptions and thresholds.
--- A single power roll table (e.g. "Tier 1 / Tier 2 / Tier 3 results") within a PowerRollTableGroup.
PowerRollTable = RegisterGameType("PowerRollTable")

--- @class PowerRollTableGroup
--- @field name string Display name for this group of power roll tables.
--- @field tableName string Data table name ("powerRolls").
--- @field tables PowerRollTable[] Ordered list of PowerRollTable entries in this group.
--- A named collection of PowerRollTable entries (e.g. "Easy", "Medium", "Hard" encounter tables).
PowerRollTableGroup = RegisterGameType("PowerRollTableGroup")

PowerRollTableGroup.name = "Power Rolls"
PowerRollTableGroup.tableName = "powerRolls"

function PowerRollTableGroup.Create(args)
    return PowerRollTableGroup.new(args)
end

function PowerRollTableGroup.CreateDropdownOptions()
    local result = {}

    for k,v in pairs(dmhub.GetTable(PowerRollTableGroup.tableName) or {}) do
        if not v:try_get("hidden") then
            for i=1,#v.tables do
                result[#result+1] = {
                    id = string.format("%s:%d", k, i),
                    text = string.format("%s - %s", v.name, v.tables[i].name),
                    tableName = v.name,
                }
            end
        end
    end

    --sort by group name, but keep the order within the group so e.g. easy - medium - hard appear in that order.
    table.sort(result, function(a,b)
        return a.tableName < b.tableName
    end)

    return result
end

function PowerRollTableGroup.GetPowerTable(id)
    if type(id) ~= "string" then
        return nil
    end

    local match = regex.MatchGroups(id, "^(?<groupid>.*):(?<tableindex>[0-9]+)$")
    if match == nil then
        return nil
    end

    local group = dmhub.GetTable(PowerRollTableGroup.tableName)[match.groupid]
    if group ~= nil then
        return group.tables[tonumber(match.tableindex)]
    end

    return nil
end

function PowerRollTable.Create(args)
    local params = {
        tiers = {
            "Tier 1 Result",
            "Tier 2 Result",
            "Tier 3 Result",
        },
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    return PowerRollTable.new(params)
end

function PowerRollTableGroup.CreateEditor()
    local m_group

    local function Upload()
        dmhub.SetAndUploadTableItem(PowerRollTableGroup.tableName, m_group)
    end

    local resultPanel

    resultPanel = gui.Panel{
        classes = {"hidden"},
        width = 840,
        height = "95%",
        flow = "vertical",
        vscroll = true,

        setdata = function(element, group)
            m_group = group
        end,

        gui.Input{
            width = 200,
            height = 24,
            fontSize = 22,
            characterLimit = 40,
            bold = true,
            placeholderText = "Enter Name...",

            change = function(element)
                m_group.name = element.text
                Upload()
            end,

            setdata = function(element)
                element.text = m_group.name
            end,
        },

        gui.Panel{
            flow = "vertical",
            width = "100%-40",
            height = "auto",
            halign = "left",
            data = {
                panels = {},
            },
            setdata = function(element)
                local newPanels = {}

                for i=1,#m_group.tables do
                    local index = i
                    newPanels[i] = element.data.panels[i] or gui.Panel{
                        flow = "vertical",
                        halign = "left",
                        lmargin = 8,
                        width = 500,
                        height = "auto",
                        data = {
                            table = m_group.tables[i],
                        },

                        gui.Input{
                            width = 200,
                            height = 24,
                            fontSize = 18,
                            characterLimit = 40,
                            bold = true,
                            placeholderText = "Enter Name...",

                            change = function(element)
                                m_group.tables[index].name = element.text
                                Upload()
                            end,

                            setdata = function(element)
                                element.text = m_group.tables[index].name
                            end,
                        },

                        gui.Table{
                            flow = "vertical",
                            width = 800,
                            height = "auto",
                            create = function(element)
                                local children = {}

                                for j=1,#GameSystem.TierNames do
                                    local tierNumber = j
                                    local name = GameSystem.TierNames[j]
                                    local input = gui.Input{
                                        width = "100%-140",
                                        height = "auto",
                                        minHeight = 22,
                                        wrap = true,
                                        lineType = "multilinenewline",
                                        characterLimit = 200,
                                        fontSize = 18,
                                        text = m_group.tables[index].tiers[tierNumber],
                                        setdata = function(element)
                                            element.text = m_group.tables[index].tiers[tierNumber]
                                        end,
                                        change = function(element)
                                            m_group.tables[index].tiers[tierNumber] = element.text
                                            Upload()
                                        end,
                                    }
        
                                    local panel = gui.TableRow{
                                        width = "100%",
                                        height = "auto",
                                        gui.Label{
                                            width = 120,
                                            height = 22,
                                            valign = "center",
                                            fontSize = 18,
                                            color = Styles.textColor,
                                            text = name,
                                        },
                                        input,
                                    }
        
                                    children[#children+1] = panel
                                end

                                element.children = children
                            end,
                        }

                    }
                end

                element.data.panels = newPanels
                element.children = newPanels
            end,
        },

        gui.Button{
            classes = {"addButton"},
            valign = "top",
            click = function(element)
                m_group.tables[#m_group.tables+1] = PowerRollTable.Create{
                    name = "New Table",
                }

                Upload()
                resultPanel:FireEventTree("setdata", m_group)
            end,
        },
    }

    return resultPanel
end

local function ShowPowerRollPanel(parentPanel)
    local dataItems = {}
    local editPanel = PowerRollTableGroup.CreateEditor()
    local itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(PowerRollTableGroup.tableName) or {}

			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
					select = element.aliveTime > 0.2,
					click = function()
						editPanel:SetClass("hidden", false)
						editPanel:FireEventTree("setdata", dataTable[k])
					end,
                    tableName = PowerRollTableGroup.tableName,
                    key = k,
				}

				newDataItems[k].text = item.name

				children[#children+1] = newDataItems[k]
			end

            table.sort(children, function(a,b) return a.text < b.text end)

			dataItems = newDataItems
			element.children = children
		end,
	}

	itemsListPanel:FireEvent('refreshAssets')

	local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
		Compendium.AddButton{

			click = function(element)
                local newData = PowerRollTableGroup.Create{
                    tables = {},
                }

                dmhub.SetAndUploadTableItem(PowerRollTableGroup.tableName, newData)
			end,
		}
	}

	parentPanel.children = {leftPanel, editPanel}	
end

Compendium.Register{
    section = "Import",
    text = "Power Roll Tables",
    click = function(contentPanel)
        ShowPowerRollPanel(contentPanel)

    end,
}