local mod = dmhub.GetModLoading()

--- @class BackgroundCharacteristic
--- @field tableid string Id of the RollTable stored in characteristicsTable.
--- @field characteristicsTable string Data table name where the roll tables are stored ("characteristicsTable").
--- Embeds a named roll table into a background or character type, used for personality traits, bonds, etc.
BackgroundCharacteristic = RegisterGameType("BackgroundCharacteristic")


BackgroundCharacteristic.characteristicsTable = "characteristicsTable"

function BackgroundCharacteristic:GetRollTable()
    local rollData = dmhub.GetTable(BackgroundCharacteristic.characteristicsTable)
    return rollData[self.tableid]
end

function BackgroundCharacteristic:Name()
    return self:GetRollTable().name
end

function BackgroundCharacteristic:GetRulesText()
    return self:GetRollTable().details
end

function BackgroundCharacteristic.CreateNew()

    local rollTable = RollTable.CreateNew{
        text = true,
        items = false,
    }

    dmhub.SetAndUploadTableItem(BackgroundCharacteristic.characteristicsTable, rollTable)

    return BackgroundCharacteristic.new{
        tableid = rollTable.id,
    }
end

function BackgroundCharacteristic:CreateEditor(args)
    local resultPanel
    local tableEditor = RollTable.CreateEditor{
        styles = {
            {
                selectors = {"plusButton"},
                hidden = 1,
            },
            {
                selectors = {"input", "variantInput"},
                width = "90%",
            }
        },
        changename = function(element)
            resultPanel:FireEvent("change")
        end,
		change = function(element)
		end,
    }
    tableEditor.data.SetData(BackgroundCharacteristic.characteristicsTable, self.tableid, {
        hasDetails = true,
    })

    resultPanel = {
        width = 800,
        height = "auto",
        flow = "vertical",

        tableEditor,
    }

    for k,v in pairs(args or {}) do
        resultPanel[k] = v
    end

    resultPanel = gui.Panel(resultPanel)

    return resultPanel
end

--embed a background characteristic editor in a "parentFeature" like a background or a character type.
--children is a list of panels.
function BackgroundCharacteristic.EmbedEditor(parentFeature, children, onchange)
    
	local characteristicsPanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "vertical",
	}

	children[#children+1] = characteristicsPanel

	local m_expandedCharacteristics = {}

	local RefreshCharacteristics
	RefreshCharacteristics = function()

		local characteristicsPanels = {}

		for i,characteristic in ipairs(parentFeature:try_get("characteristics", {})) do
			local index = i

			local tri = gui.Panel{
				classes = {"triangle"},
				floating = true,
				halign = "left",
				valign = "center",
				x = 2,
				styles = {
					{
						selectors = {"triangle"},
						rotate = 90,
						transitionTime = 0.2,
					},
					{
						selectors = {"triangle", "expanded"},
						rotate = 0,
						transitionTime = 0.2,
					},
				},
			}

			local body
			body = gui.Panel{
				classes = {"featureCardBody", "collapsed-anim"},
				characteristic:CreateEditor{
					change = function(element)
						onchange()
						RefreshCharacteristics()
					end,
				},
			}

			characteristicsPanels[#characteristicsPanels+1] = gui.Panel{
				classes = {"featureCard"},
				gui.Panel{
					classes = {"featureCardHeader"},
					tri,
					gui.Label{
						fontSize = 18,
						bold = true,
						width = 320,
						lmargin = 20,
						height = "auto",
						halign = "left",
						valign = "center",
						textWrap = true,
						textAlignment = "left",
						text = string.format("Characteristic: %s", characteristic:Name()),
					},
					gui.DeleteItemButton{
						halign = "right",
						valign = "center",
						hmargin = 4,
						width = 16,
						height = 16,
						requireConfirm = true,
						click = function(element)
							m_expandedCharacteristics = {}
							table.remove(parentFeature.characteristics, index)
							onchange()
							RefreshCharacteristics()
						end,
					},
					click = function(element)
						body:SetClass("collapsed-anim", not body:HasClass("collapsed-anim"))
						tri:SetClass("expanded", not tri:HasClass("expanded"))
						m_expandedCharacteristics[index] = tri:HasClass("expanded")
					end,
					rightClick = function(element)
						element.popup = gui.ContextMenu{
							entries = {
								{
									text = "Delete",
									click = function()
										m_expandedCharacteristics = {}
										table.remove(parentFeature.characteristics, index)
										onchange()
										RefreshCharacteristics()
										element.popup = nil
									end,
								}
							}
						}
					end,
				},
				body,
			}

			if m_expandedCharacteristics[i] then
				body:SetClass("collapsed-anim", false)
				tri:SetClass("expanded", true)
			end
		end

		characteristicsPanel.children = characteristicsPanels
	end

	RefreshCharacteristics()
	
	children[#children+1] = gui.Button{
		classes = {"btn-sm"},
		width = "auto",
		hpad = 8,
		text = "Add Characteristic",
		click = function(element)
			local newCharacteristic = BackgroundCharacteristic.CreateNew()

			local characteristics = parentFeature:get_or_add("characteristics", {})
			characteristics[#characteristics+1] = newCharacteristic

            onchange()
            RefreshCharacteristics()
		end,
	}
end