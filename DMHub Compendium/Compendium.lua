local mod = dmhub.GetModLoading()

local AddButton = function(options)
	local args = {
		style = {
			width = 32,
			height = 32,
			halign = 'right',
			valign = 'top',
		},
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.AddButton(args)
end

local function FindFeaturePathInObject(feature, obj, path)
	if obj == feature then
		return true
	end

	for k,v in pairs(obj) do
		if v == feature then
			path[#path+1] = k
			return true
		end

		if type(v) == "table" and #path < 16 then
			path[#path+1] = k
			local result = FindFeaturePathInObject(feature, v, path)
			if result then
				return result
			end

			path[#path] = nil
		end
	end

	return false
end

--given a feature, finds the path within our assets hierarchy to that feature.
--returns the path, the tableid and the key of the specific object.
local function FindFeaturePath(feature)
	local path = {}
	local tables = dmhub.GetTableTypes()
	for i,tableid in ipairs(tables) do
		local t = dmhub.GetTable(tableid) or {}
		path[#path+1] = tableid
		for key,obj in unhidden_pairs(t) do
			if (not string.starts_with(key, "_tmp")) and type(obj) == "table" then
				path[#path+1] = key

				local result = FindFeaturePathInObject(feature, obj, path)
				if result then
					return path, tableid, key
				end
				path[#path] = nil
			end		
		end
		path[#path] = nil
	end

	return nil
end

local function FindFeatureFromPath(path)
	local t = dmhub.GetTable(path[1]) or {}
	local obj = t[path[2]]
	for i=3,#path do
		if obj == nil or type(obj) ~= "table" then
			return nil
		end

        if string.starts_with(path[i], "_tmp") then
            return nil
        end

		obj = rawget(obj,path[i])
	end

	return obj
end

local g_recentFeatureEdits = {}



local LibraryStyles = {
	{
		classes = {'mainContentPanel'},
		width = 1200,
		height = '95%',
		halign = 'left',
		flow = 'vertical',
		pad = 20,
	},
	{
		classes = {'label'},
		color = 'white',
		fontSize = 22,
		width = 'auto',
		height = 'auto',
	},
	{
		classes = {"formLabel"},
		width = 240,
		textAlignment = "left",
	},
	{
		classes = {'input'},
		width = 200,
		height = 26,
		fontSize = 18,
		color = 'white',
	},
	{
		classes = {'formPanel'},
		flow = 'horizontal',
		width = 'auto',
		height = 'auto',
		halign = 'left',
		vmargin = 2,
	},
}

RegisterGameType("CompendiumPermission")

function CompendiumPermission.TranslateKey(key)
	return string.gsub(key, " ", "_")
end
CompendiumPermission.name = "Compendium Permission"
CompendiumPermission.tableName = "compendiumPermissions"
CompendiumPermission.visible = true

local CreateListHeading = function(options)
	return gui.Label{
		text = options.text,
		hmargin = 3,
		fontSize = 22,
		classes = {'list-item'},
		bold = true,
	}
end

local function generateDuplicateName(name)
    -- Check if the name ends with "(number)"
    local base, num = string.match(name, "^(.-)%s%((%d+)%)$")
    
    if base and num then
        -- If it matches, increment the number and return
        return base .. " (" .. (tonumber(num) + 1) .. ")"
    else
        -- Otherwise, simply append "(1)" to the name and return
        return name .. " (1)"
    end
end

local CreateListItem = function(options)

    local m_search = nil

	local collapsed = nil

	if options.tableName ~= nil and options.key ~= nil then
		local table = dmhub.GetTable(options.tableName)
		local item = table[options.key]
		if (not options.obliterateOnDelete) and item:try_get("hidden") then
			collapsed = cond(dmhub.GetSettingValue("showdeleted"), "deleted", "collapsed")

		end
	end

	local modificationsPanel = nil
	if options.modified then
		local think = nil
		local thinkTime = nil

		if type(options.modified) == "function" then
			thinkTime = 0.5
			think = function(element)
				element.selfStyle.opacity = cond(options.modified(), 1, 0)
			end
		end

		modificationsPanel = gui.Panel{
			bgimage = "icons/icon_tool/icon_tool_79.png",
			bgcolor = "white",
			width = 16,
			height = 16,
			halign = "right",
			valign = "center",
			hmargin = 40,
			think = think,
			thinkTime = thinkTime,
		}

		modificationsPanel:FireEvent("think")
	end

	local permissionPanel = nil
	if options.permissionKey ~= nil then
		local permissionsTable = dmhub.GetTable(CompendiumPermission.tableName) or {}
		local visible = permissionsTable[options.permissionKey] == nil or permissionsTable[options.permissionKey].visible
		if permissionsTable[options.permissionKey] ~= nil then
			print("VISIBLE:: ", permissionsTable[options.permissionKey].visible, "from", options.permissionKey)
		end
		permissionPanel = gui.Panel{
			bgimage = cond(visible, "ui-icons/eye.png", "ui-icons/eye-closed.png"),
			bgcolor = "white",
			width = 16,
			height = 16,
			halign = "right",
			valign = "center",
			hmargin = 20,
			linger = function(element)
				gui.Tooltip(cond(visible, "Visible to Players", "Hidden from Players"))(element)
			end,
			press = function(element)
				local permissionsTable = dmhub.GetTable(CompendiumPermission.tableName) or {}
				local entry = permissionsTable[options.permissionKey]
				if entry == nil then
					entry = CompendiumPermission.new{
						id = options.permissionKey,
					}
				end

				entry.visible = not entry.visible
				visible = entry.visible
				dmhub.SetAndUploadTableItem(CompendiumPermission.tableName, entry)

				element.bgimage = cond(entry.visible, "ui-icons/eye.png", "ui-icons/eye-closed.png")
			end,
		}
	end

    local importedPanel = nil
    local importedClass = nil
    if options.imported then
        importedClass = "imported"
        importedPanel = gui.Label{
            text = "Imported",
            halign = "right",
            valign = "center",
            rmargin = 16,
            color = "#999999",
            fontSize = 10,
            width = "auto",
            height = "auto",
        }
    end

	local lockPanel = nil
	if options.lock then
		lockPanel = gui.Panel{
			bgimage = "icons/icon_tool/icon_tool_30.png",
			bgcolor = "white",
			width = 16,
			height = 16,
			halign = "right",
			valign = "center",
			hmargin = 20,
		}
	end

	local newContentMarker = nil
	if options.contentType ~= nil then
		if module.HasNovelContent(options.contentType) then
			newContentMarker = gui.NewContentAlert{ x = -14 }
		end
	elseif options.tableName ~= nil and options.key ~= nil then
		if module.HasNovelContent(options.tableName) and module.GetNovelContent(options.tableName)[options.key] then
			newContentMarker = gui.NewContentAlert{ x = -14 }
		end
	end
	

	return gui.Label{
			bgimage = 'panels/square.png',
			text = options.text,
			classes = {'list-item', collapsed, importedClass},
            importedPanel,
			permissionPanel,
			lockPanel,
			modificationsPanel,

			newContentMarker,

			data = {
				ord = options.ord,
                RepeatSearch = function(element)
                    if m_search ~= nil then
                        local libraryPanel = element:FindParentWithClass('library-panel')
                        if libraryPanel ~= nil then
                            libraryPanel:FireEventTree("searchCompendium", m_search)
                        end
                    end
                end,
			},
			events = {
				search = options.search,
                searchCompendium = function(element, text)
                    text = string.lower(text)
                    m_search = text
                    if text == "" then
                        element:SetClass("searching", false)
                        element:SetClass("matchSearch", false)
                    else
                        element:SetClass("searching", true)
                        if options.contentType ~= nil then
                            element:SetClass("matchSearch", #SearchTableForText(dmhub.GetTable(options.contentType), text, options.contentType == "charConditions") > 0)

	                    elseif options.tableName ~= nil and options.key ~= nil then
		                    local table = dmhub.GetTable(options.tableName)
		                    local item = table[options.key]
                            element:SetClass("matchSearch", MatchesSearchRecursive(item, text))

                            if string.find(string.lower(options.tableName), text) then
                                element:SetClass("matchSearch", true)
                            end
                        else
                            element:SetClass("matchSearch", false)
                        end

                        --if this is a direct search of the title of this section it obviously matches.
                        if options.text ~= nil and string.find(string.lower(options.text), text) then
                            element:SetClass("matchSearch", true)
                        end
                    end
                end,
				create = function(element)
					if options.select then
						element:FireEvent("press")
					end
				end,
				press = function(element)
					element.popup = nil

					for i,child in ipairs(element.parent.children) do
						child:SetClass('selected', child == element)
					end

					if options.click then
						options.click(element)

                        element.data.RepeatSearch(element)

					end
				end,
				rightClick = function(element)
					if options.rightClick then
						options.rightClick(element)
					end

					local menuItems = {}
					if options.tableName ~= nil and options.key ~= nil then
						menuItems[#menuItems+1] = {
							text = "Duplicate",
							click = function()
								local table = dmhub.GetTable(options.tableName)
								local item = table[options.key]
								local newItem = DeepCopy(item)
								newItem.id = dmhub.GenerateGuid()
								newItem.name = generateDuplicateName(newItem.name)
								dmhub.SetAndUploadTableItem(options.tableName, newItem)

								element.popup = nil
							end,
						}

						menuItems[#menuItems+1] = {
							text = "Delete",
							click = function()
								local table = dmhub.GetTable(options.tableName)
								if options.obliterateOnDelete then
									dmhub.ObliterateTableItem(options.tableName, options.key)
								else
									local item = table[options.key]
									item.hidden = true
									dmhub.SetAndUploadTableItem(options.tableName, item)
									element:SetClass("collapsed", true)
								end

								element.popup = nil
							end,
						}

					end

					if #menuItems > 0 then
						element.popup = gui.ContextMenu{
							entries = menuItems,
						}
					end
				end,
			},
		}
end

mod.shared.CreateListItem = CreateListItem

local ShowPartyPanel = function(parentPanel)
	local partyPanel = Party.CreateEditor()
	local SetData = partyPanel.data.SetData

	local itemsListPanel = nil

	local partyItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(Party.tableName) or {}
			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = partyItems[k] or CreateListItem{
					tableName = Party.tableName,
					key = k,
					select = element.aliveTime > 0.2,
					click = function()
						SetData(Party.tableName, k)
					end,
				}

				newDataItems[k].text = item.name

				children[#children+1] = newDataItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			partyItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{
			click = function(element)
				dmhub.SetAndUploadTableItem(Party.tableName, Party.CreateNew())
			end,
		}
	}

	parentPanel.children = {leftPanel, partyPanel}
end

local ShowCurrencyPanel = function(parentPanel)
	local currencyPanel = Currency.CreateEditor()
	local SetData = currencyPanel.data.SetData

	local itemsListPanel = nil

	local currencyItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(Currency.tableName) or {}
			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = currencyItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = Currency.tableName,
					key = k,
					click = function()
						SetData(Currency.tableName, k)
					end,
				}

				newDataItems[k].text = item.name

				children[#children+1] = newDataItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			currencyItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{
			click = function(element)
				dmhub.SetAndUploadTableItem(Currency.tableName, Currency.CreateNew())
			end,
		}
	}

	parentPanel.children = {leftPanel, currencyPanel}
end

local ShowConditionsPanel = function(parentPanel)
	local conditionsPanel = CharacterCondition.CreateEditor()
	local SetData = conditionsPanel.data.SetData

	local itemsListPanel = nil

	local conditionsItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
			local newConditionsItems = {}

			for k,item in pairs(conditionsTable) do
				newConditionsItems[k] = conditionsItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = CharacterCondition.tableName,
					key = k,
					click = function()
						SetData(CharacterCondition.tableName, k)
					end,
				}

				newConditionsItems[k].text = item.name

				children[#children+1] = newConditionsItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			conditionsItems = newConditionsItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(CharacterCondition.tableName, CharacterCondition.CreateNew())
			end,
		}
	}

	parentPanel.children = {leftPanel, conditionsPanel}
end

local ShowDamageTypesPanel = function(parentPanel)
	local damageTypesPanel = DamageType.CreateEditor()
	local SetData = damageTypesPanel.data.SetData

	local itemsListPanel = nil

	local damageTypeItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local damageTypesTable = dmhub.GetTable(DamageType.tableName) or {}
			local newDamageTypeItems = {}

			for k,item in pairs(damageTypesTable) do
				newDamageTypeItems[k] = damageTypeItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = DamageType.tableName,
					key = k,
					click = function()
						SetData(DamageType.tableName, k)
					end,
				}

				newDamageTypeItems[k].text = item.name

				children[#children+1] = newDamageTypeItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			damageTypeItems = newDamageTypeItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(DamageType.tableName, DamageType.CreateNew())
			end,
		}
	}

	parentPanel.children = {leftPanel, damageTypesPanel}
end

local ShowDamageFlagsPanel = function(parentPanel)
	local damageFlagsPanel = DamageFlag.CreateEditor()
	local SetDamageFlag = damageFlagsPanel.data.SetDamageFlag

	local itemsListPanel = nil

	local damageFlagItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local damageFlagsTable = dmhub.GetTable(DamageFlag.tableName) or {}
			local newDamageFlagItems = {}

			for k,item in pairs(damageFlagsTable) do
				newDamageFlagItems[k] = damageFlagItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = DamageFlag.tableName,
					key = k,
					click = function()
						SetDamageFlag(DamageFlag.tableName, k)
					end,
				}

				newDamageFlagItems[k].text = item.name

				children[#children+1] = newDamageFlagItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			damageFlagItems = newDamageFlagItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(DamageFlag.tableName, DamageFlag.CreateNew())
			end,
		}
	}

	parentPanel.children = {leftPanel, damageFlagsPanel}
end

local ShowOngoingEffectsPanel = function(parentPanel, tableName)

	local ongoingEffectPanel = CharacterOngoingEffect.CreateEditor(nil, {tableName = tableName})
	local SetOngoingEffect = ongoingEffectPanel.data.SetOngoingEffect

    local createNew = function()
        return CharacterOngoingEffect.Create()
    end

    if tableName == "conditionRiders" then
        createNew = function()
            return ConditionRider.Create()
        end
    end

	local groupByCondition = (tableName == "conditionRiders")

	local itemsListPanel = nil

	local sectionHeadings = {}
	local ongoingEffectItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local ongoingEffectTable = dmhub.GetTable(tableName) or {}
			local newOngoingEffectItems = {}

			local keys = table.keys(ongoingEffectTable)

			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
			if groupByCondition then
				table.sort(keys, function(a,b)
					local ca = ongoingEffectTable[a]
					local cb = ongoingEffectTable[b]
					local conda = conditionsTable[ca.condition] or {name = "Ungrouped"}
					local condb = conditionsTable[cb.condition] or {name = "Ungrouped"}
					return conda.name < condb.name
				end)
			end

			local seenHeadings = {}
			local newSectionHeadings = {}

			for _,k in ipairs(keys) do
				local item = ongoingEffectTable[k]
				if groupByCondition then
					local condition = conditionsTable[item.condition] or {name = "Ungrouped"}
					if not seenHeadings[condition.name] then
						seenHeadings[condition.name] = true

						local heading = sectionHeadings[condition.name] or gui.Label{
							text = condition.name,
							fontSize = 20,
							bold = true,
							width = "auto",
							height = "auto",
							lmargin = 4,
						}

						newSectionHeadings[condition.name] = heading
						children[#children+1] = heading
					end
				end
				newOngoingEffectItems[k] = ongoingEffectItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						SetOngoingEffect(k)
					end,
				}

				newOngoingEffectItems[k].text = item.name

				children[#children+1] = newOngoingEffectItems[k]
			end

            if not groupByCondition then
			    table.sort(children, function(a,b) return a.text < b.text end)
            end

			sectionHeadings = newSectionHeadings
			ongoingEffectItems = newOngoingEffectItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
                local newEffect
                if tableName == "conditionRiders" then
                    newEffect = ConditionRider.Create()
                else
                    newEffect = CharacterOngoingEffect.Create()
                end 
				dmhub.SetAndUploadTableItem(tableName, newEffect)
			end,
		}
	}

	local scrollablePanel = gui.Panel{
		height = "90%",
		width = 1200,
		vscroll = true,
		ongoingEffectPanel,
	}

	parentPanel.children = {leftPanel, scrollablePanel}

end

local ShowCustomAttributesPanel = function(parentPanel)

	local attrPanel = gui.Panel{
		classes = 'attr-panel',
		styles = {
			{
				classes = {'attr-panel'},
				width = 1200,
				height = '100%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			LibraryStyles,
		},
	}

	local SetAttribute = function(attrid)
		local attrTable = dmhub.GetTable(CustomAttribute.tableName) or {}
		local attr = attrTable[attrid]

		attrPanel.children = {
			attr:GenerateEditor{
				change = function(element)
					dmhub.SetAndUploadTableItem(CustomAttribute.tableName, attr)
				end,
			}
		}

	end

	local itemsListPanel = nil

	local attrItems = {}
    local sectionHeadings = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local attrTable = dmhub.GetTable(CustomAttribute.tableName) or {}
			local newAttrItems = {}

			local newHeadings = {}

			for k,item in pairs(attrTable) do

                local section = item.category

				if newHeadings[section] == nil then
					newHeadings[section] = sectionHeadings[section] or gui.Label{
						data = {
							ord = section,
						},
						text = section,
						fontSize = 20,
						bold = true,
						width = "auto",
						height = "auto",
						lmargin = 4,
					}

					children[#children+1] = newHeadings[section]
                end

				newAttrItems[k] = attrItems[k] or CreateListItem{
                    ord = section .. "-" .. item.name,
					select = element.aliveTime > 0.2,
					tableName = CustomAttribute.tableName,
					key = k,
					text = item.name,
					obliterateOnDelete = true,
					click = function()
						SetAttribute(k)
					end,
				}

				newAttrItems[k].text = item.name

				children[#children+1] = newAttrItems[k]
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			attrItems = newAttrItems
            sectionHeadings = newHeadings
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				local attrTable = dmhub.GetTable(CustomAttribute.tableName) or {}
				local newAttr = CustomAttribute.Create()
				dmhub.SetAndUploadTableItem(CustomAttribute.tableName, newAttr)
			end,
		}
	}

	parentPanel.children = {leftPanel, attrPanel}
end

local ShowCustomFieldsPanel = function(parentPanel)
	local editorPanel = gui.Panel{
		width = "auto",
		height = "auto",
	}

	local itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		create = function(element)
			local children = {}
			for _,fieldName in ipairs(CustomFieldCollection.fieldTypes) do

				local label = gui.Label{
					bgimage = 'panels/square.png',
					text = fieldName,
					classes = {'list-item'},
					click = function(element)
						for _,p in ipairs(element.parent.children) do
							p:SetClass("selected", p == element)
						end
						editorPanel.children = {
							CustomFieldCollection.CreateEditor(fieldName)
						}
					end,
				}

				children[#children+1] = label
			end

			element.children = children
		end,
	}

	parentPanel.children = {itemsListPanel, editorPanel}
end

local ShowSkillsPanel = function(parentPanel)

	local skillPanel = gui.Panel{
		classes = 'skills-panel',
		styles = {
			{
				classes = {'skills-panel'},
				width = 1200,
				height = '100%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			LibraryStyles,
		},
	}

	local SetSkill = function(skillid)
		local skillTable = dmhub.GetTable(Skill.tableName) or {}
		local skill = skillTable[skillid]
		local UploadSkill = function()
			dmhub.SetAndUploadTableItem(Skill.tableName, skill)
		end

		local children = {}

		--the ID of the skill.
		if dmhub.GetSettingValue("dev") then
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = 'ID:',
					valign = 'center',
					minWidth = 100,
				},
				gui.Label{
					text = skill.id,
				},
			}
		end

		--the name of the skill.

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = skill.name,
				change = function(element)
					skill.name = element.text
					UploadSkill()
				end,
			},
		}

		--the attribute of the skill.

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Attribute:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Dropdown{
				width = 200,
				height = 40,
				fontSize = 20,
				options = creature.attributeDropdownOptions,
				idChosen = skill.attribute,
				change = function(element)
					skill.attribute = element.idChosen
					UploadSkill()
				end,
			},
		}

		--whether this skill has a passive associated with it.
		children[#children+1] = gui.Check{
			text = "Has Passive",
			halign = "left",
			fontSize = 22,
			value = cond(skill.hasPassive, true, false),
			change = function(element)
				skill.hasPassive = element.value
				UploadSkill()
			end,
		}

		children[#children+1] = gui.Label{
			vmargin = 6,
			fontSize = 24,
			bold = true,
			text = "Specializations",
			width = "auto",
			height = "auto",
		}

		local specializationItems = {}
		children[#children+1] = gui.Panel{
			width = "auto",
			height = "auto",
			flow = "vertical",
			monitorAssets = true,
			create = function(element)
				element:FireEvent("refreshAssets")
			end,
			refreshAssets = function(element)
				local children = {}

				dmhub.Debug(string.format("Refresh specializations: %d", #Skill.GetSpecializations(skill)))
				for i,s in ipairs(Skill.GetSpecializations(skill)) do
					local child = specializationItems[i] or gui.Panel{
						flow = "horizontal",
						width = "auto",
						height = "auto",
						data = {
							id = s.id,
						},
						gui.Label{
							fontSize = 14,
							width = 180,
							height = "auto",
							valign = "center",
							editable = true,
							characterLimit = 24,
							change = function(element)
								local itemPanel = element.parent
								local s = Skill.GetSpecializationById(skill, itemPanel.data.id)
								if s ~= nil then
									s.text = element.text
									UploadSkill()
								end
							end,
						},
						gui.CloseButton{
							valign = "center",
							click = function(element)
								local itemPanel = element.parent

								Skill.DeleteSpecializationById(skill, itemPanel.data.id)

								UploadSkill()
							end
						}
					}

					child.data.id = s.id
					child.children[1].text = s.text

					children[#children+1] = child
				end

				specializationItems = children
				element.children = children
			end,
		}

		children[#children+1] = AddButton{
			halign = "left",
			click = function(element)
				dmhub.Debug("Add Specialization")
				Skill.AddSpecialization(skill)
				UploadSkill()
			end,
		}

		skillPanel.children = children

	end

	local itemsListPanel = nil

	local skillItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local skillTable = dmhub.GetTableVisible(Skill.tableName) or {}
			local newSkillItems = {}

			for k,item in pairs(skillTable) do
				newSkillItems[k] = skillItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = Skill.tableName,
					key = k,
					text = item.name,
					obliterateOnDelete = true,
					click = function()
						SetSkill(k)
					end,
				}

				newSkillItems[k].text = item.name

				children[#children+1] = newSkillItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			skillItems = newSkillItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				local skillTable = dmhub.GetTable(Skill.tableName) or {}
				local newSkill = Skill.CreateNew()
				if skillTable[newSkill.id] == nil then
					dmhub.SetAndUploadTableItem(Skill.tableName, Skill.CreateNew())
				end
			end,
		}
	}

	parentPanel.children = {leftPanel, skillPanel}

end

local ShowSpellsPanel = function(parentPanel)
	local spellsPanel = gui.Panel{
		styles = LibraryStyles,
		width = 1200,
		height = 1000,
		Spell.CompendiumEditor(),
	}

	parentPanel.children = {spellsPanel}
end


local ShowInventoryPanel = function(parentPanel)
	local itemsPanel = gui.Panel{
		styles = LibraryStyles,
		width = 1200,
		height = 1000,
		mod.shared.InventoryCompendiumEditor(),
	}

	parentPanel.children = {itemsPanel}
end

local ShowResourcesPanel = function(parentPanel)

	local resourcePanel = gui.Panel{
		classes = 'resource-panel',
		height = "90%",
		vscroll = true,

		styles = {
			{
				classes = {'resource-panel'},
				width = 1200,
				height = '100%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			LibraryStyles,


		},

	}

	local SetResource = function(resourceid)
		local resourceTable = dmhub.GetTable("characterResources") or {}
		local resource = resourceTable[resourceid]
		local UploadResource = function()
			dmhub.SetAndUploadTableItem("characterResources", resource)
		end

		local children = {}

		--the guid of the resource.
		if devmode() then
		
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = 'Guid:',
					valign = 'center',
					minWidth = 100,
				},
				gui.Input{
					text = resource.id,
				},
			}
		end

		--the name of the resource.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = resource.name,
				change = function(element)
					resource.name = element.text
					UploadResource()
				end,
			},
		}

		--the grouping of the resource.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Grouping:',
				valign = 'center',
				minWidth = 100,
			},
            gui.Dropdown{
                options = CharacterResource.groupingOptions,
                idChosen = resource.grouping,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
                    resource.grouping = element.idChosen
					UploadResource()
                end,

            },
		}

		--whether the resource displays quantity.
		children[#children+1] = gui.Check{
			text = "Use in Quantity",
			halign = "left",
			fontSize = 22,
			value = resource.useQuantity,
			linger = gui.Tooltip("When a spell or ability uses this resource you will specify how many to use."),
			change = function(element)
				resource.useQuantity = element.value
				UploadResource()
			end,
		}

		local quantityLabelPreview = gui.Label{
			width = "auto",
			height = "auto",
			halign = "center",
			valign = "center",
			fontSize = 58,

			create = function(element)
				element.text = cond(resource.usageLimit == "unbounded", "6", "6/8")
				element.selfStyle.color = cond(resource.textColor == "light", "white", "black")

				element:SetClass("collapsed", not resource.largeQuantity)
			end,
		}

		local textColorPanel

		--whether the resource comes in large quantities and should be shown using numbers.
		children[#children+1] = gui.Check{
			text = "Large Quantities",
			halign = "left",
			fontSize = 22,
			value = resource.largeQuantity,
			linger = gui.Tooltip("This resource can come in large quantities and will display as a number instead of individual icons."),
			change = function(element)
				resource.largeQuantity = element.value
				UploadResource()
				quantityLabelPreview:FireEvent("create")
				textColorPanel:FireEvent("create")
			end,
		}

		textColorPanel = gui.Panel{
			classes = {'formPanel', cond(resource.largeQuantity, nil, "collapsed-anim")},
			create = function(element)
				element:SetClass("collapsed-anim", not resource.largeQuantity)
			end,
			gui.Label{
				text = 'Text Color:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.Dropdown{
				options = { { id = "light", text = "Light" }, { id = "dark", text = "Dark" }},
				idChosen = resource.textColor,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					resource.textColor = element.idChosen
					UploadResource()
					quantityLabelPreview:FireEvent("create")
				end,
			},
		}

		children[#children+1] = textColorPanel

		--whether the resource is a reaction action, allowing an ability using it to be used as a reaction.
		children[#children+1] = gui.Check{
			text = "Is Reaction",
			halign = "left",
			fontSize = 22,
			value = resource.isreaction,
			linger = gui.Tooltip("Abilities that use this resource as their action can have trigger conditions causing them to trigger."),
			change = function(element)
				resource.isreaction = element.value
				UploadResource()
			end,
		}

		local largeIconEditor = gui.IconEditor{
			library = 'resources',
			hmargin = 40,
			width = 256,
			height = 256,
			halign = "left",
			value = resource.largeIconid,
			change = function(element)
				resource.largeIconid = element.value
				UploadResource()
			end,
		}

		largeIconEditor:SetClass("collapsed", not resource.hasLargeDisplay)

		--whether the resource is a reaction action, allowing an ability using it to be used as a reaction.
		children[#children+1] = gui.Check{
			text = "Has Large Display",
			halign = "left",
			fontSize = 22,
			value = resource.hasLargeDisplay,
			linger = gui.Tooltip("If checked, this resource will have a large version of the icon to display when a large dialog displays the resource."),
			change = function(element)
				resource.hasLargeDisplay = element.value
				UploadResource()

				largeIconEditor:SetClass("collapsed", not resource.hasLargeDisplay)
			end,
		}

		local currentDisplayMode = 'normal'

		--the resource's icon.
		local iconEditor = gui.IconEditor{
			library = 'resources',
			margin = 80,
			width = 128,
			height = 128,
			halign = "left",
			value = resource.iconid,
			quantityLabelPreview,
			change = function(element)
				if resource.iconid == nil or currentDisplayMode == 'normal' then
					resource.iconid = element.value
				else
					resource.display = DeepCopy(resource.display)
					resource.display[currentDisplayMode]['bgimage'] = element.value
				end
				UploadResource()
			end,
			create = function(element)
				element.selfStyle.hueshift = resource.display[currentDisplayMode]['hueshift']
				element.selfStyle.saturation = resource.display[currentDisplayMode]['saturation']
				element.selfStyle.brightness = resource.display[currentDisplayMode]['brightness']
				element.selfStyle.bgcolor = resource.display[currentDisplayMode]['bgcolor'] or 'white'
				element.SetValue(element, resource.display[currentDisplayMode]['bgimage'] or resource.iconid, false)
			end,
		}

		local iconEditorContainer = gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = "auto",
			halign = "left",

			iconEditor,
			largeIconEditor,
		}

		children[#children+1] = iconEditorContainer

		--color is the same for all display modes.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Color:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.ColorPicker{
				width = 32,
				height = 32,
				value = resource.display[currentDisplayMode].bgcolor or 'white',
				change = function(element)
					resource.display = DeepCopy(resource.display)
					for k,disp in pairs(resource.display) do
						disp.bgcolor = element.value
					end
					iconEditor:FireEvent('create')
				end,

				confirm = function(element)
					UploadResource()
				end,
				
			},
		}

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Blend:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.Dropdown{
				options = { { id = "normal", text = "Normal" }, { id = "add", text = "Add" }},
				idChosen = resource.display.normal.blend or 'normal',
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					for k,displayMode in pairs(resource.display) do
						displayMode.blend = cond(element.idChosen == 'add', 'add', nil)
					end
					UploadResource()
				end,
			},
		}

		local CreateDisplaySlider = function(options)
			return gui.Slider{
				style = {
					height = 40,
					width = 200,
					fontSize = 14,
				},

				sliderWidth = 140,
				labelWidth = 50,
				value = resource.display[currentDisplayMode][options.attr],
				minValue = options.minValue,
				maxValue = options.maxValue,

				formatFunction = function(num)
					return string.format('%d%%', round(num*100))
				end,

				deformatFunction = function(num)
					return num*0.01
				end,

				events = {
					change = function(element)
						resource.display = DeepCopy(resource.display)
						resource.display[currentDisplayMode][options.attr] = element.value
						iconEditor:FireEvent('create')
					end,
					confirm = function(element)
						UploadResource()
					end,
				}
			}
		end
		local sliders = {}
		sliders[#sliders+1] = CreateDisplaySlider{ attr = 'hueshift', minValue = 0, maxValue = 1, }
		sliders[#sliders+1] = CreateDisplaySlider{ attr = 'saturation', minValue = 0, maxValue = 2, }
		sliders[#sliders+1] = CreateDisplaySlider{ attr = 'brightness', minValue = 0, maxValue = 2, }

		--the display mode we are editing.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Display Type:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.Dropdown{
				options = CharacterResource.displayModeOptions,
				idChosen = currentDisplayMode,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					currentDisplayMode = element.idChosen
					sliders[1].data.setValueNoEvent(resource.display[currentDisplayMode]['hueshift'])
					sliders[2].data.setValueNoEvent(resource.display[currentDisplayMode]['saturation'])
					sliders[3].data.setValueNoEvent(resource.display[currentDisplayMode]['brightness'])
					iconEditor:FireEvent('create')
				end,
			}
		}

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Hue:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			sliders[1],
		}

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Saturation:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			sliders[2],
		}

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Brightness:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			sliders[3],
		}

		--can the resource go negative
		children[#children+1] = gui.Check{
			text = "May Be Negative",
			halign = "left",
			fontSize = 22,
			value = resource.mayBeNegative,
			linger = gui.Tooltip("If checked, this resource may become negative"),
			change = function(element)
				resource.mayBeNegative = element.value
				UploadResource()
			end,
		}



		--the resource's refresh frequency.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Refresh:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.Dropdown{
				options = CharacterResource.usageLimitOptions,
				idChosen = resource.usageLimit,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					resource.usageLimit = element.idChosen
					UploadResource()

					quantityLabelPreview:FireEvent("create")
				end,
			}
		}

        if resource.usageLimit == "unbounded" or resource.usageLimit == "global" then
            children[#children+1] = gui.Check{
                text = "Clear Outside of Combat",
                value = resource.clearOutsideOfCombat,
                change = function(element)
                    resource.clearOutsideOfCombat = element.value
                    UploadResource()
                end,
            }
        end


		--the resource's dice type.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Die Type:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.Dropdown{
				options = CharacterResource.diceTypeOptions,
				idChosen = resource.diceType,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					resource.diceType = element.idChosen
					UploadResource()
				end,
			}
		}

		--if the resource can be used to cast spells
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Spell Level:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.Dropdown{
				options = CharacterResource.spellSlotOptions,
				idChosen = resource.spellSlot,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					resource.spellSlot = element.idChosen
					UploadResource()
				end,
			}
		}

		--if the resource is a level up from another resource.
		local resourceChoices = {}

		for k,v in pairs(resourceTable) do
			if k ~= resourceid then
				resourceChoices[#resourceChoices+1] = {
					id = k,
					text = v.name,
				}
			end
		end

		table.sort(resourceChoices, function(a,b) return a.text < b.text end)

		table.insert(resourceChoices, 1, {
			id = 'none',
			text = 'None',
		})

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Improves Upon:',
				valign = "center",
				minWidth = 200,
				width = 'auto',
				height = 'auto',
			},
			gui.Dropdown{
				options = resourceChoices,
				idChosen = resource.levelsFrom,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					resource.levelsFrom = element.idChosen
					UploadResource()
				end,
			}
		}

		resourcePanel.children = children

	end

	local itemsListPanel = nil

	local resourceItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local resourceTable = dmhub.GetTable("characterResources") or {}
			local newResourceItems = {}

			for k,item in pairs(resourceTable) do
				if not item:try_get("hidden") then
					newResourceItems[k] = resourceItems[k] or CreateListItem{
						select = element.aliveTime > 0.2,
						tableName = "characterResources",
						key = k,
						click = function()
							SetResource(k)
						end,
					}

					newResourceItems[k].text = item.name

					children[#children+1] = newResourceItems[k]
				end
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			resourceItems = newResourceItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.Debug('ADD CHARACTER RESOURCE')
				dmhub.SetAndUploadTableItem("characterResources", CharacterResource.CreateNew())
			end,
		}
	}

	parentPanel.children = {leftPanel, resourcePanel}

end

local ShowClassesPanel = function(parentPanel, tableName)

	tableName = tableName or "classes"
	local subclass = tableName ~= "classes"

	local classPanel = Class.CreateEditor()

	local itemsListPanel = nil

	local classItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local classesTable = dmhub.GetTable(tableName) or {}
			local newClassItems = {}

			local headings = {}

			for k,item in pairs(classesTable) do
				local ord = item.name
				if subclass then
					local primaryClassesTable = dmhub.GetTable("classes") or {}
					local primaryClass = primaryClassesTable[item.primaryClassId]
					local primaryClassName = "Unknown"
					if primaryClass then
						primaryClassName = primaryClass.name
					end
					ord = primaryClassName .. "-" .. ord

					if headings[primaryClassName] == nil then
						headings[primaryClassName] = classItems[primaryClassName] or gui.Label{
							data = {
								ord = primaryClassName,
							},
							text = primaryClassName,
							fontSize = 20,
							bold = true,
							width = "auto",
							height = "auto",
							lmargin = 4,
						}

						children[#children+1] = headings[primaryClassName]
					end
				end
				newClassItems[k] = classItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					ord = ord,
					click = function(element)
						classPanel.data.SetClass(tableName, k)
                        dmhub.Schedule(0.01, function()
                            element.data.RepeatSearch(element)
                        end)
					end,
				}

				newClassItems[k].text = item.name

				children[#children+1] = newClassItems[k]
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			classItems = newClassItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.Debug('ADD CHARACTER RESOURCE')
				dmhub.SetAndUploadTableItem(tableName, Class.CreateNew{
					isSubclass = subclass
				})
			end,
		}
	}

	parentPanel.children = {leftPanel, classPanel}
end

local ShowThemesPanel = function(parentPanel, themeType)

	local themeEditorPanel = Theme.CreateEditor()

	local itemsListPanel = nil

	local themeItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)
			local children = {}
			local themesTable = assets.themes
			local newThemeItems = {}

			for k,item in pairs(themesTable) do
				if item.themeType == themeType then

					newThemeItems[k] = themeItems[k] or CreateListItem{
						select = element.aliveTime > 0.2,
						click = function()
							themeEditorPanel.data.SetTheme(themeType, k)
						end,
					}

					newThemeItems[k].text = item.description

					children[#children+1] = newThemeItems[k]
				end
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			themeItems = newThemeItems
			itemsListPanel.children = children

			themeEditorPanel:FireEvent("refreshAssets")
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

		AddButton{

			click = function(element)
				local theme = gui.CreateTheme(themeType)
				theme:Upload()
			end,
		}
	}

	parentPanel.children = {leftPanel, themeEditorPanel}
end

local ShowGlobalModsPanel = function(parentPanel)
	local tableName = GlobalRuleMod.TableName

	local modPanel = GlobalRuleMod.CreateEditor()

	local itemsListPanel = nil

	local modItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local modsTable = dmhub.GetTable(tableName) or {}
			local newModItems = {}

			for k,item in pairs(modsTable) do
				newModItems[k] = modItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						modPanel.data.SetGlobalRuleMod(tableName, k)
					end,
				}

				newModItems[k].text = item.name

				children[#children+1] = newModItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			modItems = newModItems
			itemsListPanel.children = children

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

		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, GlobalRuleMod.CreateNew("New Rule"))
			end,
		}
	}

	parentPanel.children = {leftPanel, modPanel}
end

local ShowRolltablePanel = function(parentPanel, tableName, tableOptions, editOptions)
	local editorPanel = RollTable.CreateEditor()

	local itemsListPanel = nil
	
	local dataItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(tableName) or {}
			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						editorPanel.data.SetData(tableName, k, editOptions)
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
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,

		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, RollTable.CreateNew(tableOptions))
			end,
		}

	}

	local rightPanel = gui.Panel{
		width = "auto",
		height = "100%",
		vscroll = true,
		editorPanel,
	}

	parentPanel.children = {leftPanel, rightPanel}

end

local ShowRacesPanel = function(parentPanel, t)
	local tableName = t or "races"

	local racePanel = Race.CreateEditor()

	local itemsListPanel = nil

	local raceItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local racesTable = dmhub.GetTable(tableName) or {}
			local newRaceItems = {}

			for k,item in pairs(racesTable) do
				newRaceItems[k] = raceItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						racePanel.data.SetRace(tableName, k)
					end,
				}

				newRaceItems[k].text = item.name

				children[#children+1] = newRaceItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			raceItems = newRaceItems
			itemsListPanel.children = children
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

		AddButton{

			click = function(element)
				dmhub.Debug('ADD CHARACTER RESOURCE')
				dmhub.SetAndUploadTableItem(tableName, Race.CreateNew{
					subrace = cond(tableName == "subraces", true)
				})
			end,
		}

	}

	parentPanel.children = {leftPanel, racePanel}

end

local ShowBackgroundsPanel = function(parentPanel)
	local tableName = Background.tableName

	local backgroundPanel = Background.CreateEditor()

	local itemsListPanel = nil

	local backgroundItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local backgroundsTable = dmhub.GetTable(tableName) or {}
			local newBackgroundItems = {}

			for k,item in pairs(backgroundsTable) do
				newBackgroundItems[k] = backgroundItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						backgroundPanel.data.SetBackground(tableName, k)
					end,
				}

				newBackgroundItems[k].text = item.name

				children[#children+1] = newBackgroundItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			backgroundItems = newBackgroundItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, Background.CreateNew{
				})
			end,
		}
	}

	parentPanel.children = {leftPanel, backgroundPanel}
end

local ShowCharacterTypesPanel = function(parentPanel)
	local tableName = CharacterType.tableName

	local characterTypePanel = CharacterType.CreateEditor()

	local itemsListPanel = nil

	local characterTypeItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local characterTypesTable = dmhub.GetTable(tableName) or {}
			local newCharacterTypeItems = {}

			for k,item in pairs(characterTypesTable) do
				newCharacterTypeItems[k] = characterTypeItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						characterTypePanel.data.SetCharacterType(tableName, k)
					end,
				}

				newCharacterTypeItems[k].text = item.name

				children[#children+1] = newCharacterTypeItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			characterTypeItems = newCharacterTypeItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, CharacterType.CreateNew{
				})
			end,
		}
	}

	parentPanel.children = {leftPanel, characterTypePanel}
end


local ShowFeatsPanel = function(parentPanel, tableName)
	tableName = tableName or CharacterFeat.tableName

	local featsPanel = CharacterFeat.CreateEditor()

	local itemsListPanel = nil

	local collapsedTags = {}

	local m_listPanelsByTag = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)
			local featsTable = dmhub.GetTable(tableName) or {}

			local listPanels = {}

			local newListPanels = {}
			local tagsSeen = {}

			for k,item in pairs(featsTable) do
                if not item:try_get("hidden", false) then
                    local tags = item:Tags()
                    if #tags == 0 then
                        tags = { "untagged" }
                    end
                    for _,t in ipairs(tags) do
                        local tag = string.lower(t)
                        if not tagsSeen[tag] then
                            tagsSeen[tag] = true
                            newListPanels[tag] = m_listPanelsByTag[tag] or gui.Panel{
                                data = {
                                    tag = tag
                                },

                                width = "100%",
                                valign = "center",
                                flow = "vertical",
                                height = "auto",

                                --header.
                                gui.Panel{
                                    width = "100%",
                                    height = 20,
                                    flow = "horizontal",

                                    gui.Panel{
                                        styles = {
                                            Styles.Triangle,
                                            {
                                                selectors = {"triangle", "~expanded"},
                                                transitionTime = 0.2,
                                                rotate = 90,
                                            }
                                        },

                                        classes = {"triangle", cond(collapsedTags[tag], "expanded")},
                                        bgimage = "panels/triangle.png",

                                        press = function(element)
                                            element:SetClass("expanded", not element:HasClass("expanded"))
                                            collapsedTags[tag] = element:HasClass("expanded")
                                            itemsListPanel:FireEventTree("refreshCollapsed")
                                        end,
                                    },

                                    gui.Label{
                                        text = tag,
                                        color = "white",
                                        fontSize = 16,
                                        width = "80%",
                                        height = "100%",
                                        halign = "left",
                                    },
                                },

                                --list.
                                gui.Panel{
                                    width = "90%",
                                    height = "auto",
                                    halign = "center",
                                    flow = "vertical",
                                    data = {
                                        panels = {}
                                    },

                                    create = function(element)
                                        element:FireEvent("refreshCollapsed")
                                    end,

                                    refreshCollapsed = function(element)
                                        element:SetClass("collapsed", not collapsedTags[tag])
                                    end,

                                    beginAccumulate = function(element)
                                        element.data.newPanels = {}
                                    end,

                                    accumulate = function(element, feat)
                                        local p = element.data.panels[feat.id]
                                        
                                        if p == nil then
                                            p = CreateListItem{
                                                select = element.aliveTime > 0.2,
                                                tableName = tableName,
                                                key = feat.id,
                                                click = function(element)
                                                    featsPanel.data.SetFeat(tableName, feat.id)
                                                    itemsListPanel:FireEventTree("selection", element)
                                                end,

                                            }

                                            --CreateListItem doesn't pass all args through so we set this selection event handler here.
                                            p.events.selection = function(element, other)
                                                element:SetClass("selected", element == other)
                                            end
                                        end

                                        p.text = feat.name

                                        element.data.newPanels[feat.id] = p
                                    end,

                                    finishAccumulate = function(element)
                                        element.data.panels = element.data.newPanels
                                        element.data.newPanels = nil

                                        local children = {}

                                        for k,p in pairs(element.data.panels) do
                                            children[#children+1] = p
                                        end

                                        table.sort(children, function(a,b) return a.text < b.text end)

                                        element.children = children
                                    end,
                                }
                            }
                            listPanels[#listPanels+1] = newListPanels[tag]

                            newListPanels[tag]:FireEventTree("beginAccumulate")
                        end

                        local listPanel = newListPanels[tag]
                        listPanel:FireEventTree("accumulate", item)
                    end
                end
			end

			for _,p in ipairs(listPanels) do
				p:FireEventTree("finishAccumulate")
			end

			table.sort(listPanels, function(a,b) return a.data.tag < b.data.tag end)


			m_listPanelsByTag = newListPanels
			element.children = listPanels
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
		AddButton{

			click = function(element)
				local newFeat
				if tableName == "creatureTemplates" then
					newFeat = CharacterTemplate.CreateNew{}
				else
					newFeat = CharacterFeat.CreateNew{}
				end

				dmhub.SetAndUploadTableItem(tableName, newFeat)
			end,
		}
	}

	parentPanel.children = {leftPanel, featsPanel}
end

local ShowPropertyPanel = function(parentPanel, objectType)
	local editorPanel = objectType.CreateEditor()

	local itemsListPanel = nil

	local items = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local tbl = dmhub.GetTable(objectType.tableName) or {}
			local newItems = {}

			for k,item in pairs(tbl) do
				newItems[k] = items[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = objectType.tableName,
					key = k,
					click = function()
						tbl = dmhub.GetTable(objectType.tableName) or {}
						editorPanel:FireEventTree("editItem", tbl[k])
					end,
				}

				newItems[k].text = item.name

				children[#children+1] = newItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			items = newItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				local newItem = objectType.CreateNew{}
				dmhub.SetAndUploadTableItem(objectType.tableName, newItem)
			end,
		}
	}

	parentPanel.children = {leftPanel, editorPanel}
end



local ShowFeaturePrefabsPanel = function(parentPanel)
	local tableName = CharacterFeaturePrefabs.tableName

	local featurePrefabsPanel = CharacterFeaturePrefabs.CreateEditor()

	local itemsListPanel = nil

	local featurePrefabsItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local featurePrefabsTable = dmhub.GetTable(tableName) or {}
			local newFeaturePrefabsItems = {}

			for k,item in pairs(featurePrefabsTable) do
				newFeaturePrefabsItems[k] = featurePrefabsItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						featurePrefabsPanel.data.SetPrefab(tableName, k)
					end,
				}

				newFeaturePrefabsItems[k].text = item.name

				children[#children+1] = newFeaturePrefabsItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			featurePrefabsItems = newFeaturePrefabsItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, CharacterFeaturePrefabs.CreateNew{
				})
			end,
		}
	}

	parentPanel.children = {leftPanel, featurePrefabsPanel}
end

local ShowLanguagesPanel = function(parentPanel)
	local tableName = Language.tableName

	local languagesPanel = Language.CreateEditor()

	local itemsListPanel = nil

	local languageItems = {}
	local sectionHeadings = {}
	local dataItems = {}

	local itemListPanel = gui.Panel{
		classes = {"list-panel"},
		vscroll = true,
		monitorAssets = true,
		create = function(element)
			element:FireEvent("refreshAssets")
		end,
		refreshAssets = function(element)
			local languagesTable = dmhub.GetTable(Language.tableName) or {}
			local children = {}
			local newDataItems = {}
			local newHeadings = {}

			for k,language in unhidden_pairs(languagesTable) do
				local group = language.group or "Custom"

				if newHeadings[group] == nil then
					newHeadings[group] = sectionHeadings[group] or gui.Label{
						data = {
							ord = group,
						},
						text = group,
						fontSize = 20,
						bold = true,
						width = "auto",
						height = "auto",
						lmargin = 4,
					}

					children[#children+1] = newHeadings[group]
				end

				newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
					tableName = Language.tableName,
					key = k,
					select = element.aliveTime > 0.2,
					click = function()
						selectedLanguageId = k
						languagesPanel.data.SetLanguage(Language.tableName, k)
					end,
				}
			
			newDataItems[k].data.ord = group .. "-" .. language.name
			newDataItems[k].text = language.name
			children[#children+1] = newDataItems[k]
		end

		table.sort(children, function(a, b)
			return a.data.ord < b.data.ord
		end)

		sectionHeadings = newHeadings
		dataItems = newDataItems
		element.children = children
	end,
}

local leftPanel = gui.Panel{
	selfStyle = {
		flow = 'vertical',
		height = '100%',
		width = 'auto',
	},

	itemListPanel,
	Compendium.AddButton{
		click = function()
			dmhub.SetAndUploadTableItem(Language.tableName, Language.CreateNew{})
		end,
	}
}

parentPanel.children = {leftPanel, languagesPanel}
end

--vback
local ShowTitlesPanel = function(parentPanel)
	local tableName = Title.tableName

	local titlePanel = Title.CreateEditor()

	local itemsListPanel = nil

	local titleItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local titlesTable = dmhub.GetTable(tableName) or {}
			local newTitleItems = {}

			for k,item in pairs(titlesTable) do
				newTitleItems[k] = titleItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					click = function()
						titlePanel.data.SetTitle(tableName, k)
					end,
				}

				newTitleItems[k].text = item.name

				children[#children+1] = newTitleItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			titleItems = newTitleItems
			itemsListPanel.children = children
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

		AddButton{

			click = function(element)
				dmhub.Debug('ADD CHARACTER RESOURCE')
				dmhub.SetAndUploadTableItem(tableName, Title.CreateNew{
				})
			end,
		}

	}

	parentPanel.children = {leftPanel, titlePanel}
end


--nice generic example panel.
local ShowAttributeGeneratorPanel = function(parentPanel)
	local tableName = AttributeGenerator.tableName

	local editorPanel = AttributeGenerator.CreateEditor()
	local editorContainerPanel = gui.Panel{
		width = 900,
		height = "95%",
		vscroll = true,
		editorPanel,
	}

	local itemsListPanel = nil

	local items = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(tableName) or {}
			local newItems = {}

			for k,item in pairs(dataTable) do
				newItems[k] = items[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					obliterateOnDelete = true,
					click = function()
						editorPanel.data.SetData(k)
					end,
				}

				newItems[k].text = item.name

				children[#children+1] = newItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			items = newItems
			itemsListPanel.children = children
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

		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, AttributeGenerator.CreateNew{
				})
			end,
		}

	}

	parentPanel.children = {leftPanel, editorContainerPanel}
end

local ShowEquipmentCategoriesPanel = function(parentPanel)

	local equipmentCatPanel = gui.Panel{
		classes = 'equip-cat-panel',
		styles = {
			{
				classes = {'equip-cat-panel'},
				width = 1200,
				height = '100%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			{
				classes = {'label'},
				color = 'white',
				fontSize = 22,
				width = 'auto',
				height = 'auto',
			},
			{
				classes = {'input'},
				width = 200,
				height = 26,
				fontSize = 18,
				color = 'white',
			},
			{
				classes = {'formPanel'},
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
				halign = 'left',
				vmargin = 2,
			}
		},
	}

	local SetId = function(id)
		local dataTable = dmhub.GetTable("equipmentCategories") or {}
		local data = dataTable[id]
		local UploadData = function()
			dmhub.SetAndUploadTableItem("equipmentCategories", data)
		end

		local children = {}

        children[#children+1] = gui.Panel{
            classes = {"formPanel", "devonly"},
			gui.Label{
				text = 'GUID:',
				valign = 'center',
				minWidth = 100,
			},
            gui.Input{
                classes = {"formInput"},
                text = data.id,
                width = 300,
            },
        }

		--the name of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.name,
				change = function(element)
					data.name = element.text
					UploadData()
				end,
			},
		}

		local supersets = {
			{
				id = 'none',
				text = '(None)',
			}
		}
		for k,cat in pairs(dataTable) do
			if k ~= data.id and (not cat:try_get("hidden")) then
				supersets[#supersets+1] = {
					id = k,
					text = cat.name,
				}
			end
		end

		table.sort(supersets, function(a,b) return a.text < b.text end)

		--the superset of this item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Parent Category:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Dropdown{
				options = supersets,
				idChosen = data:try_get("superset", "none"),
				width = 200,
				height = 40,
				fontSize = 20,

				change = function(element)
					local val = element.idChosen
					if val == 'none' then
						val = nil
					end

					data.superset = val
					UploadData()
				end,
			},
		}

		--the editor type this category uses
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Editor Type:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Dropdown{
				options = {
					{
						id = "Weapon",
						text  = "Weapon",
					},
					{
						id = "Armor",
						text  = "Armor",
					},
					{
						id = "Shield",
						text  = "Shield",
					},
					{
						id = "Gear",
						text  = "Gear",
					},
				},
				idChosen = data.editorType,
				width = 200,
				height = 40,
				fontSize = 20,

				change = function(element)
					data.editorType = element.idChosen
					UploadData()
				end,
			},
		}

		--whether this type of item can have proficiency.
		children[#children+1] = gui.Check{
			text = "Has Proficiency",
			halign = "left",
			fontSize = 22,
			value = data.allowProficiency,
			change = function(element)
				data.allowProficiency = element.value
				UploadData()
			end,
		}

		--whether individual items in this category have proficiency
		children[#children+1] = gui.Check{
			text = "Individual Items have Proficiency",
			halign = "left",
			fontSize = 22,
			value = data.allowIndividualProficiency,
			change = function(element)
				data.allowIndividualProficiency = element.value
				UploadData()
			end,
		}

		--whether items in this category are unarmored
		children[#children+1] = gui.Check{
			text = "Unarmored",
			halign = "left",
			fontSize = 22,
			value = data.isUnarmored,
			change = function(element)
				data.isUnarmored = element.value
				UploadData()
			end,
		}

		--whether items in this category are tools
		children[#children+1] = gui.Check{
			text = "Tools",
			halign = "left",
			fontSize = 22,
			value = data.isTool,
			change = function(element)
				data.isTool = element.value
				UploadData()
			end,
		}

		--whether items in this category are martial weapons
		children[#children+1] = gui.Check{
			text = "Martial Weapons",
			halign = "left",
			fontSize = 22,
			value = data.isMartial,
			change = function(element)
				data.isMartial = element.value
				UploadData()
			end,
		}

		--whether items in this category are melee weapons
		children[#children+1] = gui.Check{
			text = "Melee Weapons",
			halign = "left",
			fontSize = 22,
			value = data.isMelee,
			change = function(element)
				data.isMelee = element.value
				UploadData()
			end,
		}

		--whether items in this category are ranged weapons
		children[#children+1] = gui.Check{
			text = "Ranged Weapons",
			halign = "left",
			fontSize = 22,
			value = data.isRanged,
			change = function(element)
				data.isRanged = element.value
				UploadData()
			end,
		}

		--whether items in this category are ammunition for other weapons.
		children[#children+1] = gui.Check{
			text = "Is Ammunition",
			halign = "left",
			fontSize = 22,
			value = data.isAmmo,
			change = function(element)
				data.isAmmo = element.value
				UploadData()
			end,
		}

		--whether items in this category are light sources.
		children[#children+1] = gui.Check{
			text = "Is Light Source",
			halign = "left",
			fontSize = 22,
			value = data.isLightSource,
			change = function(element)
				data.isLightSource = element.value
				UploadData()
			end,
		}

		--whether items in this category come in mass quantities.
		children[#children+1] = gui.Check{
			text = "Sold in Quantity",
			halign = "left",
			fontSize = 22,
			value = data.isQuantity,
			change = function(element)
				data.isQuantity = element.value
				UploadData()
			end,
		}

		--whether items in this category are considered treasure.
		children[#children+1] = gui.Check{
			text = "Is Treasure",
			halign = "left",
			fontSize = 22,
			value = data.isTreasure,
			change = function(element)
				data.isTreasure = element.value
				UploadData()
			end,
		}

		--whether items in this category are packs of items.
		children[#children+1] = gui.Check{
			text = "Equipment Packs",
			halign = "left",
			fontSize = 22,
			value = data.isPacks,
			change = function(element)
				data.isPacks = element.value
				UploadData()
			end,
		}



		equipmentCatPanel.children = children

	end

	local itemsListPanel = nil

	local dataItems = {}

	--step through the category's parents and return a list of categories.
	local GetCategoryParents = function(k)
		local dataTable = dmhub.GetTable("equipmentCategories") or {}

		local result = {}

		local count = 1
		while k ~= nil and dataTable[k] ~= nil and count < 5 do
			table.insert(result, 1, dataTable[k])
			k = dataTable[k]:try_get('superset')
			count = count + 1
		end

		return result
		
	end


	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable("equipmentCategories") or {}
			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = "equipmentCategories",
					key = k,
					click = function()
						SetId(k)
					end,
					data = {
					},
				}

				newDataItems[k].text = item.name
				newDataItems[k].data.cats = GetCategoryParents(k)
				newDataItems[k].x = 10*#newDataItems[k].data.cats

				children[#children+1] = newDataItems[k]
			end

			table.sort(children, function(a,b)
				for i=1,math.min(#a.data.cats,#b.data.cats) do
					if a.data.cats[i].name < b.data.cats[i].name then
						return true
					elseif a.data.cats[i].name > b.data.cats[i].name then
						return false
					end
				end

				return #a.data.cats < #b.data.cats
			end)

			dataItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem("equipmentCategories", EquipmentCategory.CreateNew())
			end,
		}
	}

	parentPanel.children = {leftPanel, equipmentCatPanel}
end

local ShowArtistsPanel = function(parentPanel)
	
	local dataItems = {}

	local artistsPanel = Artist.CreateEditorPanel()

	artistsPanel:SetClass("hidden", true)

	local itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = assets.artists or {}

			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					click = function()
						artistsPanel:SetClass("hidden", false)
						artistsPanel:FireEventTree("artist", dataTable[k])
					end,
				}

				local desc = item.name
				if desc == nil or desc == "" then
					desc = "(unnamed)"
				end

				newDataItems[k].text = desc

				children[#children+1] = newDataItems[k]
			end

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
		AddButton{

			click = function(element)
				assets:AddAndUploadArtist()
			end,
		}
	}

	parentPanel.children = {leftPanel, artistsPanel}	
end

local ShowImageFoldersPanel = function(parentPanel)
	local imagesPanel = gui.Panel{
		classes = 'mainContentPanel',
		styles = {
			LibraryStyles,
		},
	}

	local itemsListPanel = nil

	local SetId = function(id)
		local dataTable = assets.imageLibrariesTable
		local data = dataTable[id]
		local UploadData = function()
			data:Upload()
		end

		local children = {}

		if dmhub.GetSettingValue("dev") then

			--the guid of the item.
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = 'ID (dev only):',
					valign = 'center',
					minWidth = 100,
				},
				gui.Input{
					text = data.guid,
				},
			}
		end

		--name/description
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.name,
				change = function(element)
					data.name = element.text
					printf("NAME:: x change to (%s) / %s", element.text, data.name)
					UploadData()
				end,
			},
		}

		children[#children+1] = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Image Type:",
				valign = "center",
				minWidth = 100,
			},

			gui.Dropdown{
				idChosen = data.imageType,
				change = function(element)
					data.imageType = element.idChosen
					UploadData()
				end,
				options = {
					{
						id = "none",
						text = "None",
					},
					{
						id = "avatar",
						text = "Avatar",
					},
				}
			}
		}

		--gm only.
		children[#children+1] = gui.Check{
			text = "Hidden from Players",
			halign = "left",
			fontSize = 22,
			value = data.gmonly,
			change = function(element)
				data.gmonly = element.value
				UploadData()
			end,
		}

		if dmhub.isAdminAccount then
			children[#children+1] = gui.Panel{
				classes = {"formPanel"},

				gui.Label{
					classes = {"formLabel"},
					text = "Artist:",
				},

				gui.Dropdown{

					create = function(element)
						local options = {}

						for artistid,artist in pairs(assets.artists) do
							options[#options+1] = {
								id = artistid,
								text = artist.name,
							}
						end

						table.sort(options, function(a,b) return a.text < b.text end)

						table.insert(options, 1, {
							id = "none",
							text = "(None)",
						})

						element.options = options

						local artistid = data.artistid
						if artistid == nil or artistid == "" then
							artistid = "none"
						end
						element.idChosen = artistid


					end,

					change = function(element)
						if element.idChosen == "none" then
							data.artistid = nil
						else
							data.artistid = element.idChosen
						end

						UploadData()
					end,
				},
			}
		end



		imagesPanel.children = children

	end

	local dataItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = assets.imageLibrariesTable

			local newDataItems = {}

			for k,item in pairs(dataTable) do
				if (not item.hidden) and (item.extension) then
					newDataItems[k] = dataItems[k] or CreateListItem{
						select = element.aliveTime > 0.2,
						click = function()
							SetId(k)
						end,
					}

					local desc = item.name
					if desc == nil or desc == "" then
						desc = "(unnamed)"
					end

					newDataItems[k].data.ord = item.name

					newDataItems[k].text = desc

					children[#children+1] = newDataItems[k]
				end
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			dataItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				assets:CreateNewImageLibrary()
			end,
		}
	}

	parentPanel.children = {leftPanel, imagesPanel}

end

local ShowImageAtlasPanel = function(parentPanel)
	local imagesPanel = gui.Panel{
		classes = 'mainContentPanel',
		styles = {
			LibraryStyles,
		},
	}

	local itemsListPanel = nil

	local SetId = function(id)
		local dataTable = assets.imageAtlasTable
		local data = dataTable[id]
		local UploadData = function()
			data:Upload()
		end

		local children = {}

		if dmhub.GetSettingValue("dev") then

			--the guid of the item.
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = 'ID (dev only):',
					valign = 'center',
					minWidth = 100,
				},
				gui.Input{
					text = data.id,
					change = function(element)
						element.text = data.id
					end,
				},
			}
		end

		--name/description
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.description,
				change = function(element)
					data.description = element.text
					UploadData()
				end,
			},
		}

		children[#children+1] = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Tiling:",
				valign = "center",
				minWidth = 100,
			},
			gui.Input{
				text = tostring(data.xdiv),
				valign = "center",
				width = 20,
				characterLimit = 2,
				placeholderText = "",
				change = function(element)
					local n = tonumber(element.text)
					if n == nil or round(n) ~= n or n < 1 or n > 16 then
						element.text = tostring(data.xdiv)
						return
					end

					data.xdiv = n
					UploadData()
				end,
			},
			gui.Label{
				text = "x",
				valign = "center",
				textAlignment = "center",
				width = 10,
			},
			gui.Input{
				text = tostring(data.ydiv),
				valign = "center",
				width = 20,
				characterLimit = 2,
				placeholderText = "",
				change = function(element)
					local n = tonumber(element.text)
					if n == nil or round(n) ~= n or n < 1 or n > 16 then
						element.text = tostring(data.ydiv)
						return
					end

					data.ydiv = n
					UploadData()
				end,
			},
		}

		local m_x = nil
		local m_y = nil

		--show the image.
		children[#children+1] = gui.Panel{
			id = "tokenFrameImage",
			width = 512,
			height = 512,
			halign = "left",
			bgimage = id,
			bgcolor = "white",
			vmargin = 10,
			borderColor = "white",
			borderWidth = 1,
			thinkTime = 0.2,
			think = function(element)
				local x = data.xdiv
				local y = data.ydiv

				if m_x == x and m_y == y then
					return
				end

				m_x = x
				m_y = y

				element.children = {
					gui.Panel{
						flow = "horizontal",
						width = "100%",
						height = "100%",
						create = function(element)
							local children = {}
							for i=1,x-1 do
								children[#children+1] = gui.Panel{
									width = 1,
									height = "100%",
									lmargin = 512/x,
									bgcolor = "white",
									bgimage = "panels/square.png",
									halign = "left",
								}
							end

							element.children = children
						end,
					},
					gui.Panel{
						flow = "vertical",
						width = "100%",
						height = "100%",
						create = function(element)
							local children = {}
							for i=1,y-1 do
								children[#children+1] = gui.Panel{
									width = "100%",
									height = 1,
									tmargin = 512/y,
									bgcolor = "white",
									bgimage = "panels/square.png",
									valign = "top",
								}
							end

							element.children = children
						end,
					},
				}
			end,
			imageLoaded = function(element)
				if element.bgsprite == nil then
					return
				end

				local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
				local xratio = (element.bgsprite.dimensions.x)/maxDim
				local yratio = (element.bgsprite.dimensions.y)/maxDim

				element.selfStyle.width = string.format("%0.2f", 512*xratio)
				element.selfStyle.height = string.format("%0.2f", 512*yratio)
			end,

			rightClick = function(element)
				if dmhub.GetSettingValue("dev") then
					element.popup = gui.ContextMenu{
						entries = {
							{
								text = "Open Image URL",
								click = function()
									data:OpenImageUrl()
									element.popup = nil
								end,
							},
						}
					}
				end
			end,
		}

		children[#children+1] = gui.PrettyButton{
			width = 200,
			height = 50,
			fontSize = 24,
			text = "DELETE",
			halign = "right",
			click = function(element)
				local nextItem = nil
				local found = false
				for i,child in ipairs(itemsListPanel.children) do
					if child == element then
						found = true
					elseif found then
						nextItem = child
						found = false
					end
				end

				if nextItem == nil and itemsListPanel.children[1] ~= element then
					nextItem = itemsListPanel.children[1]
				end

				if nextItem ~= nil then
					nextItem:FireEvent("click")
				end
				data:Delete()
			end,
		}

		imagesPanel.children = children

	end

	local dataItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = assets.imageAtlasTable

			print("RefreshAssets...")

			local newDataItems = {}

			for k,item in pairs(dataTable) do
			print("RefreshAssets", k)
				newDataItems[k] = dataItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					click = function()
						SetId(k)
					end,
				}

				local desc = item.description
				if desc == nil or desc == "" then
					desc = "(unnamed)"
				end

				newDataItems[k].data.ord = item.description

				newDataItems[k].text = desc

				children[#children+1] = newDataItems[k]
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)
			print("RefreshAssets HAVE ", #children)

			dataItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.OpenFileDialog{
					id = "Images",
					extensions = {"jpeg", "jpg", "png", "mp4", "webm", "webp"},
					multiFiles = true,
					prompt = "Choose image or video to use for particle atlas",
					open = function(path)

						assets:UploadImageAtlasAsset{
							error = function(msg)
							end,
							upload = function(guid)
								itemsListPanel:FireEvent('refreshAssets')
							end,
							path = path,
						}
					end,
				}
			end,
		}
	}

	parentPanel.children = {leftPanel, imagesPanel}
end

local ShowImagesPanel = function(parentPanel, imageType)
	local imagesPanel = gui.Panel{
		classes = 'mainContentPanel',
		styles = {
			LibraryStyles,
		},
	}

	local itemsListPanel = nil

	local SetId = function(id)
		local dataTable = assets.imagesByTypeTable[imageType] or {}
		local data = dataTable[id]
		local UploadData = function()
			data:Upload()
		end

		local children = {}

		if dmhub.GetSettingValue("dev") then

			--the guid of the item.
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = 'ID (dev only):',
					valign = 'center',
					minWidth = 100,
				},
				gui.Input{
					text = data.id,
					change = function(element)
						element.text = data.id
					end,
				},
			}
		end

		--name/description
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.description,
				change = function(element)
					data.description = element.text
					UploadData()
				end,
			},
		}

		--ordering
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Ordering:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = tostring(data.ord),
				change = function(element)
					data.ord = tonumber(element.text) or 0
					UploadData()
				end,
			},
		}

		--zoom.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Zoom:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = tostring(data.tokenZoom),
				change = function(element)
					data.tokenZoom = tonumber(element.text) or 0
					UploadData()
				end,
			},
		}

		--show the image.
		children[#children+1] = gui.Panel{
			id = "tokenFrameImage",
			width = 256,
			height = 256,
			halign = "left",
			bgimage = id,
			bgcolor = "white",
			vmargin = 10,
			borderColor = "white",
			borderWidth = 1,
			imageLoaded = function(element)
				if element.bgsprite == nil then
					return
				end

				local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
				local xratio = (element.bgsprite.dimensions.x)/maxDim
				local yratio = (element.bgsprite.dimensions.y)/maxDim

				element.selfStyle.width = string.format("%0.2f", 256*xratio)
				element.selfStyle.height = string.format("%0.2f", 256*yratio)
			end,

			rightClick = function(element)
				if dmhub.GetSettingValue("dev") then
					element.popup = gui.ContextMenu{
						entries = {
							{
								text = "Open Image URL",
								click = function()
									data:OpenImageUrl()
									element.popup = nil
								end,
							},
						}
					}
				end
			end,
		}

		children[#children+1] = gui.PrettyButton{
			width = 200,
			height = 50,
			fontSize = 24,
			text = "DELETE",
			halign = "right",
			click = function(element)
				local nextItem = nil
				local found = false
				for i,child in ipairs(itemsListPanel.children) do
					if child == element then
						found = true
					elseif found then
						nextItem = child
						found = false
					end
				end

				if nextItem == nil and itemsListPanel.children[1] ~= element then
					nextItem = itemsListPanel.children[1]
				end

				if nextItem ~= nil then
					nextItem:FireEvent("click")
				end
				data:Delete()
			end,
		}

		imagesPanel.children = children

	end

	local highestOrd = 0

	local dataItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = assets.imagesByTypeTable[imageType] or {}

			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					click = function()
						SetId(k)
					end,
				}

				local desc = item.description
				if desc == nil or desc == "" then
					desc = "(unnamed)"
				end

				if item.ord > highestOrd then
					highestOrd = item.ord
				end

				newDataItems[k].data.ord = item.ord

				newDataItems[k].text = desc

				children[#children+1] = newDataItems[k]
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			dataItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.OpenFileDialog{
					id = "Images" .. imageType,
					extensions = {"jpeg", "jpg", "png", "mp4", "webm", "webp"},
					multiFiles = true,
					prompt = "Choose image or video to use for avatar frame",
					open = function(path)

						highestOrd = highestOrd+1
						assets:UploadImageAsset{
							error = function(msg)
							end,
							upload = function(guid)
								itemsListPanel:FireEvent('refreshAssets')
							end,
							description = string.format("%s-%d", imageType, highestOrd),
							ord = highestOrd,
							path = path,
							imageType = imageType,
						}
					end,
				}
			end,
		}
	}

	parentPanel.children = {leftPanel, imagesPanel}
end

local ShowEmojiPanel = function(parentPanel, emojiType)

	local previewFloor = game.currentMap:CreatePreviewFloor("ObjectPreview")
	previewFloor.cameraPos = {x = -20, y = 0}
	previewFloor.cameraSize = 1

	local previewTokenId = previewFloor:CreateToken(-20, 0)

	game.Refresh()

	local emojiPanel = gui.Panel{
		classes = 'mainContentPanel',
		styles = {
			LibraryStyles,
		},
		destroy = function(element)
			game.currentMap:DestroyPreviewFloor(previewFloor)
			game.Refresh()
		end,
	}

	local SetId = function(id)


		local data = assets.emojiTable[id]

		local emoteRefreshNeeded = true

		local UploadData = function()
			data:Upload()
			emoteRefreshNeeded = true
		end

		if data.styles == nil or #data.styles ~= 3 then
			data.styles = {
				{
					blend = "blend",
				},
				{
					selectors = {'fadein'},
					transitionTime = 0,
					opacity = 0,
				},
				{
					selectors = {'fadeout'},
					transitionTime = 0,
					opacity = 0,
				},
			}
		end

		local children = {}

		if dmhub.GetSettingValue("dev") then

			--the guid of the item.
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = 'ID (dev only):',
					valign = 'center',
					minWidth = 100,
				},
				gui.Input{
					text = data.id,
					change = function(element)
						element.text = data.id
					end,
				},
			}
		end

		--the name of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.description,
				change = function(element)
					data.description = element.text
					UploadData()
				end,
			},
		}

		--the category of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Category:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Dropdown{
				options = {
					{
						id = "Emoji",
						text = "Emoji",
					},
					{
						id = "Accessory",
						text = "Accessory",
					},
					{
						id = "Status",
						text = "Status",
					},
					{
						id = "Spellcasting",
						text = "Spellcasting",
					},
				},
				idChosen = data.emojiType,
				change = function(element)
					data.emojiType = element.idChosen
					UploadData()
				end,
			},
		}

		--preview of the video
		children[#children+1] = gui.Panel{
			halign = "left",
			valign = "top",
			width = 128,
			height = 128,
			bgcolor = 'white',
			bgimage = id,
		}

		--the x value of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'x:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.x,
				change = function(element)
					data.x = element.text
					UploadData()
				end,
			},
		}

		--the y value of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'y:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.y,
				change = function(element)
					data.y = element.text
					UploadData()
				end,
			},
		}

		--the width of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Width:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.displayWidth,
				change = function(element)
					data.displayWidth = element.text
					UploadData()
				end,
			},
		}

		--the height of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Height:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.displayHeight,
				change = function(element)
					data.displayHeight = element.text
					UploadData()
				end,
			},
		}

		--the blend mode of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Blend:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Dropdown{
				options = {
					{
						id = "blend",
						text = "Blend",
					},
					{
						id = "add",
						text = "Add",
					},

				},
				idChosen = data.styles[1].blend or "blend",
				change = function(element)
					data.styles[1].blend = element.idChosen
					UploadData()
				end,
			},
		}

		children[#children+1] = gui.Check{
			text = "Looping",
			halign = "left",
			fontSize = 22,
			value = data.looping,
			change = function(element)
				data.looping = element.value
				data.fadetime = cond(data.looping, 0.5)
				data.styles[2].transitionTime = cond(data.looping, 0.5, 0)
				data.styles[3].transitionTime = cond(data.looping, 0.5, 0)

				UploadData()
				element.parent:FireEventTree("refreshLoop")
			end,
		}

		local finishEmojiOptions = {
			{
				id = "none",
				text = "Choose Finish...",
			}
		}
		for k,emoji in pairs(assets.emojiTable) do
			if emoji.emojiType == emojiType and k ~= id then
				finishEmojiOptions[#finishEmojiOptions+1] = {
					id = k,
					text = emoji.description,
				}
			end
		end

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Finish:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Dropdown{
				classes = {cond(not data.looping, "collapsed-anim")},
				options = finishEmojiOptions,
				idChosen = data.finishEmoji or "none",
				refreshLoop = function(element)
					element:SetClass("collapsed-anim", not data.looping)
				end,

				change  = function(element)
					data.finishEmoji = element.idChosen
					UploadData()
				end,
			},
		}


		children[#children+1] = gui.Check{
			text = "Mask",
			halign = "left",
			fontSize = 22,
			value = data.mask,
			change = function(element)
				data.mask = element.value
				UploadData()
			end,
		}

		children[#children+1] = gui.Check{
			text = "Behind Token",
			halign = "left",
			fontSize = 22,
			value = data.behind,
			change = function(element)
				data.behind = element.value
				UploadData()
			end,
		}

		local childEmojiPanel = gui.Panel{
			halign = "left",
			width = "auto",
			height = "auto",
			flow = "vertical",
			recalculate = function(element)

				local children = {}
				for i,emojiKey in ipairs(data.childEmoji) do
					local index = i
					local childEmoji = assets.emojiTable[emojiKey]
					if childEmoji ~= nil then
						local mypanel
						mypanel = gui.Panel{
							width = 200,
							height = 30,
							halign = "left",
							flow = "horizontal",
							gui.Label{
								width = 180,
								height = 30,
								fontSize = 20,
								text = childEmoji.description,
							},
							gui.CloseButton{
								click = function(element)
									local items = data.childEmoji
									table.remove(items, index)
									data.childEmoji = items
									UploadData()
									mypanel:DestroySelf()
								end
							}
						}

						children[#children+1] = mypanel
					end
				end

				element.children = children

			end,
			create = function(element)
				element:FireEvent("recalculate")
			end,
		}

		children[#children+1] = childEmojiPanel

		local otherEffectOptions = {
			{
				id = "choose",
				text = "Add Emoji...",
			}
		}

		for k,emoji in pairs(assets.emojiTable) do
			if emoji.emojiType == data.emojiType and id ~= k then
				otherEffectOptions[#otherEffectOptions+1] = {
					id = k,
					text = emoji.description,
				}
			end
		end

		table.sort(otherEffectOptions, function(a,b) return a.text < b.text end)

		children[#children+1] = gui.Dropdown{
			options = otherEffectOptions,
			idChosen = "choose",
			halign = "left",
			width = 200,
			height = 40,
			fontSize = 20,
			change = function(element)
				if element.idChosen ~= "choose" then
					local items = data.childEmoji
					items[#items+1] = element.idChosen
					data.childEmoji = items

					UploadData()
					childEmojiPanel:FireEvent("recalculate")

					element.idChosen = "choose"
				end
			end,
		}

		--[[
		--the fade time of the item.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Fade Time:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = data.fadetime,
				change = function(element)
					data.fadetime = element.text
					UploadData()
				end,
			},
		}

		children[#children+1] = gui.Panel{
			bgimage = id,
			bgcolor = "white",
			halign = "left",
			width = data.displayWidth,
			height = data.displayHeight,
		}

		local styleStatusText = gui.Label{
			fontSize = 12,
			halign = "left",
			width = "auto",
			height = "auto",
			minWidth = 20,
			minHeight = 20,
			valign = "top",
			vmargin = 8,
			text = "",
		}

		local styleText = gui.Input{
			valign = "top",
			halign = "left",
			multiline = true,
			width = 400,
			minHeight = 80,
			textAlignment ="topleft",
			height = 'auto',
			fontSize = 18,
			placeholderText = "Enter styles in here...",
			text = "",
			create = function(element)
				if data.styles ~= nil then
					element.text = dmhub.ToJson(data.styles)
					UploadData()
				end
			end,
			edit = function(element)
				styleStatusText.text = ""
			end,
			change = function(element)
				if element.text == '' then
					styleStatusText.text = ""
					data.styles = nil
					UploadData()
					return
				end
				local result = dmhub.EvalWithErrorCode('return ' .. element.text)
				if result.success then
					data.styles = result.data
					styleStatusText.text = ""
					UploadData()
				else
					styleStatusText.text = "Could not recognize styles"
				end
			end,
		}

		children[#children+1] = styleText
		children[#children+1] = styleStatusText

		--]]

		children[#children+1] = gui.Button{
			text = "Delete",
			halign = "left",
			valign = "bottom",
			width = 140,
			height = 40,
			fontSize = 22,
			click = function(element)
				data:Delete()
				UploadData()
			end,
		}

		children[#children+1] = gui.Panel{
			width = "auto",
			height = "auto",
			floating = true,
			x = 400,
			halign = "left",
			valign = "top",
			flow = "vertical",

			gui.Panel{
				bgimage = "#MapPreview" .. previewFloor.floorid,
				bgcolor = "white",
				cornerRadius = 12,
				width = math.floor(1920/2.5),
				height = math.floor(1080/2.5),

				thinkTime = 0.2,

				think = function(element)
					if emoteRefreshNeeded then
						emoteRefreshNeeded = false

						local token = dmhub.GetTokenById(previewTokenId)
						if token == nil then
							return
						end
						token.properties:RemoveLoopingEmotes()
						if token.sheet ~= nil then
							token.sheet:FireEventTree("refresh")
						end

						token.properties:Emote(data.description)
						if token.sheet ~= nil then
							token.sheet:FireEventTree("refresh")
						end
					end
				end,
			},

			gui.Panel{
				halign = "center",
				width = "auto",
				height = "auto",
				vmargin = 4,
				flow = "horizontal",

				gui.Button{
					halign = "center",
					width = 120,
					height = 30,
					fontSize = 22,
					text = "Play",
					click = function(element)
						emoteRefreshNeeded = true
					end,
				},

				gui.Button{
					halign = "center",
					width = 120,
					height = 30,
					fontSize = 22,
					text = "Stop",
					click = function(element)
						emoteRefreshNeeded = false
						local token = dmhub.GetTokenById(previewTokenId)
						if token == nil then
							return
						end
						token.properties:RemoveLoopingEmotes()
						if token.sheet ~= nil then
							token.sheet:FireEventTree("refresh")
						end
					end,
				},

			}
		}


		emojiPanel.children = children

	end

	local itemsListPanel = nil

	local dataItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = assets.emojiTable
			local newDataItems = {}

			for k,item in pairs(dataTable) do
				if item.emojiType == emojiType then
					newDataItems[k] = dataItems[k] or CreateListItem{
						select = element.aliveTime > 0.2,
						click = function()
							SetId(k)
						end,
					}

					newDataItems[k].text = item.description

					children[#children+1] = newDataItems[k]
				end
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			dataItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				dmhub.OpenFileDialog{
					id = "EmojiAsset",
					extensions = {"jpeg", "jpg", "png", "mp4", "webm", "webp", "gif"},
					prompt = "Choose image or video to use for emoji",
					open = function(path)

						assets:UploadEmojiAsset{
							error = function(msg)
								gui.ModalMessage{
									title = "Error",
									message = msg,
								}
							end,
							upload = function(guid)
								itemsListPanel:FireEvent('refreshAssets')
							end,
							path = path,
							emojiType = emojiType,
						}
					end,
				}
			end,
		}
	}

	parentPanel.children = {leftPanel, emojiPanel}

end

local ShowCodeModsPanel = function(parentPanel)
	local itemsListPanel = nil

	local m_search = nil

	local editorPanel = CodeMod.CreateEditor{
		search = function(element, str)
			m_search = str
			itemsListPanel:FireEventTree("search", str)
		end,
	}

	local dataItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)
			element:ScheduleEvent('refreshCode', 0.2)
		end,

		refreshCode = function(element)

			local children = {}
			local newDataItems = {}

			for _,modid in ipairs(code.loadedMods) do
				local mod = code.GetMod(modid)

				newDataItems[modid] = dataItems[modid] or CreateListItem{
					select = element.aliveTime > 0.2,
					lock = not mod.canedit,
					search = function(element, str)
						if str == nil or str == "" then
							element:SetClass("defocused", false)
						else
							local ignorecase = dmhub.GetSettingValue("codemodsearchinsensitive")
							local regex = dmhub.GetSettingValue("codemodsearchregex")
							local wholeword = dmhub.GetSettingValue("codemodsearchwholeword")
							local match = false
							for i,file in ipairs(mod.files) do
								if file:MatchesSearch(str, { ignorecase = ignorecase, wholeword = wholeword, regex = regex}) then
									match = true
									break
								end
							end

							element:SetClass("defocused", not match)
						end
					end,
					modified = function() return mod.isModified end,
					click = function()
						editorPanel:FireEvent("setmod", modid)
					end,

					rightClick = function(element)
						if code.CanDeleteMod(modid) then
							element.popup = gui.ContextMenu{
								entries = {
									{
										text = "Delete",
										click = function()
											code.DeleteMod(modid)
											element.popup = nil
										end,
									},
								}
							}
						end
					end,
				}


				newDataItems[modid].text = mod.name

				children[#children+1] = newDataItems[modid]
				newDataItems[modid]:FireEvent("search", m_search)
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			dataItems = newDataItems
			itemsListPanel.children = children
		end,
	}

	itemsListPanel:FireEvent('refreshCode')

    local addGameButton = nil
    if dmhub.isGameOwner then
        addGameButton = AddButton{
            click = function(element)
                code.CreateMod()
            end,
        }
    else
        addGameButton = gui.Label{
            text = "Only the game owner can create mods.",
            fontSize = 14,
            halign = "center",
            width = 220,
            height = "auto",
        }
    end

	local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
        addGameButton,
	}

	parentPanel.children = {leftPanel, editorPanel}
end

local ShowTranslationsPanel = function(parentPanel)
	local itemsListPanel = nil

	local editorPanel = Translation.CreateEditor()

	local dataItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)


			local children = {}
			local newDataItems = {}

			for _,transid in ipairs(i18n.translations) do
				local translation = i18n.GetTranslation(transid)

				newDataItems[transid] = dataItems[transid] or CreateListItem{
					select = element.aliveTime > 0.2,
					click = function()
						editorPanel:FireEvent("setid", transid)
					end,

					rightClick = function(element)
						element.popup = gui.ContextMenu{
							entries = {
								{
									text = "Delete",
									click = function()
										i18n.DeleteTranslation(transid)
										element.popup = nil
									end,
								},
							}
						}
					end,
				}


				newDataItems[transid].text = translation.name

				children[#children+1] = newDataItems[transid]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			dataItems = newDataItems
			itemsListPanel.children = children
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
		AddButton{

			click = function(element)
				i18n.CreateTranslation()
			end,
		}
	}

	parentPanel.children = {leftPanel, editorPanel}
end

local CompendiumSectionsRegistry = {

}

local CompendiumRegistry = {

}


local LibraryPanel = function()


	local contentPanel = gui.Panel{
		classes = {'content-panel'},
	}

	local recentsCache = nil
	local recentsHeading = nil
	local recentPanels = {}

	local recentsPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
        classes = {"collapsed"}, --disable until we make it accurate.

		thinkTime = 0.5,
		think = function(element)
			if dmhub.DeepEqual(recentsCache, g_recentFeatureEdits) then
				return
			end

			if g_recentFeatureEdits == nil then
				recentsCache = nil
				recentsHeading = nil
				element.children = {}
				return
			end

			while #g_recentFeatureEdits > 6 do
				table.remove(g_recentFeatureEdits, 1)
			end

			recentsCache = DeepCopy(g_recentFeatureEdits)

			if #g_recentFeatureEdits == 0 then
				recentsHeading = nil
				element.children = {}
				return
			end

			recentsHeading = recentsHeading or CreateListHeading{
				text = "Recents",
			}

			local children = {recentsHeading}
			local newRecentPanels = {}

			for i=#g_recentFeatureEdits,1,-1 do
				local panel = recentPanels[g_recentFeatureEdits[i].path] or CreateListItem{
					text = "Unknown feature",
					click = function(element)
						if element.data.click ~= nil then
							element.data.click(element)
						end
					end,
					data = {
						index = i,
						click = nil,
					},
				}

				panel.data.index = i

				local entry = g_recentFeatureEdits[i]
				local f = FindFeatureFromPath(g_recentFeatureEdits[i].path)
				if f == nil then
					panel:SetClass("collapsed", true)
				else
					panel:SetClass("collapsed", false)
					panel.text = f.name
					panel.data.click = function(element)


                        entry.editor(element, f, function()

                            --get the object that this is inside.
                            local objTable = dmhub.GetTable(entry.tableid) or {}
                            local obj = objTable[entry.key]

                            if obj ~= nil then
                                dmhub.SetAndUploadTableItem(entry.tableid, obj)
                                print("Compendium: Save", entry.tableid, obj)
                            else
                                print("Compendium: Could not find object", entry.tableid, entry.key)
                            end
                        end)
					end
				end

				newRecentPanels[g_recentFeatureEdits[i].path] = panel

				children[#children+1] = panel
			end

			recentPanels = newRecentPanels

			element.children = children
		end,
	}

	recentsPanel:FireEvent("think")

	local children = {recentsPanel}

	local permissionsTable = dmhub.GetTable(CompendiumPermission.tableName) or {}

    local sections = {}
    table.sort(CompendiumSectionsRegistry, function(a,b) return a.ord < b.ord end)

    for _,section in ipairs(CompendiumSectionsRegistry) do
        sections[#sections+1] = section.text
    end

	for _,section in ipairs(sections) do

		local keys = {}
		for k,v in pairs(CompendiumRegistry) do
			if v.section == section and ((not v.admin) or dmhub.isAdminGame) then
				keys[#keys+1] = k
			end
		end


		if #keys > 0 then
			children[#children+1] = CreateListHeading{
				text = section
			}
		end

		table.sort(keys)

		for _,key in ipairs(keys) do
			--shallow copy the table so we can change the click function.
			local info = {}
			for k,v in pairs(CompendiumRegistry[key]) do
				info[k] = v
			end

			if info.click ~= nil then
				local fn = info.click
				info.click = function()
					fn(contentPanel)
				end
			end

			local permissionKey = CompendiumPermission.TranslateKey(key)
			local showItem = true
			if dmhub.isDM then
				info.permissionKey = permissionKey
			elseif permissionsTable[permissionKey] ~= nil then
				if permissionsTable[permissionKey].visible == false then
					showItem = false
				end
			end

			if showItem then
				children[#children+1] = CreateListItem(info)
			end
		end
	end

	local uploadStatus = gui.Label{
		classes = {"hidden"},
		floating = true,
		halign = "right",
		valign = "bottom",

		width = 160,
		height = "auto",
		vpad = 20,
		hpad = 20,

		bgimage = "panels/square.png",
		bgcolor = "black",
		cornerRadius = 18,

		fontSize = 18,

		text = "Status",

		data = {
			eventHandlerGuids = {},
			expiryGuid = nil,
		},

		thinkTime = 0.5,

		scheduleExpire = function(element, delay)
			element:SetClass("hidden", false)
			local guid = dmhub.GenerateGuid()
			element.data.expiryGuid = guid
			dmhub.Schedule(delay, function()
				if element.valid and element.data.expiryGuid == guid then
					element:SetClass("hidden", true)
				end
			end)
		end,

		clearExpire = function(element)
			element:SetClass("hidden", false)
			element.data.expiryGuid = nil
		end,

		create = function(element)
			local guids = element.data.eventHandlerGuids
			guids[#guids+1] = dmhub.RegisterEventHandler("BeginUploadTableItems", function(tableName, uploadGuid)
				element.text = "Saving..."
				element:FireEvent("clearExpire")
			end)
			guids[#guids+1] = dmhub.RegisterEventHandler("SuccessUploadTableItems", function(tableName)
				element.text = "Saved."
				element:FireEvent("scheduleExpire", 3)
			end)
			guids[#guids+1] = dmhub.RegisterEventHandler("ErrorUploadTableItems", function(tableName)
				element.text = "Error saving"
				element:FireEvent("scheduleExpire", 5)
			end)
		end,

		destroy = function(element)
			for _,guid in ipairs(element.data.eventHandlerGuids) do
				dmhub.DeregisterEventHandler(guid)
			end
			element.data.eventHandlerGuids = {}
		end,
	}


	resultPanel = gui.Panel{
		classes = {'library-panel'},
		styles = {
			Styles.Default,
			{
				selectors = {'library-panel'},
				pad = 16,
				width = '100%-40',
				height = '100%-40',
				flow = 'horizontal',
				halign = "center",
				valign = "center",
			},
			{
				selectors = {'content-panel'},
				flow = 'horizontal',
				width = "70%",
				maxWidth = 1400,
				height = '100%',
				halign = 'left',
			},
			{
				selectors = {'list-panel'},
				flow = 'vertical',
				width = 260,
				height = 'auto',
				vpad = 20,
				maxHeight = 800,
				halign = 'left',
				valign = 'top',
			},
			{
				selectors = {'list-item'},
				width = '100%',
                height = "auto",
                minHeight = 22,
				fontSize = 16,
				hmargin = 8,
				color = 'white',
				bgcolor = 'clear',
			},
			{
				selectors = {'list-item', 'defocused'},
				color = '#888888',
			},
			{
				selectors = {'list-item', 'imported'},
				color = '#888888',
			},
			{
				selectors = {'list-item', 'deleted'},
				color = 'red',
			},
			{
				selectors = {'list-item', 'hover'},
				bgcolor = '#880000',
			},
			{
				selectors = {'list-item', 'selected'},
				bgcolor = '#880000',
			},
			{
				selectors = {'list-item', 'searching'},
				color = '#888888',
			},
			{
				selectors = {'list-item', 'matchSearch'},
				color = '#ffffff',
			},
            {
                selectors = {'searchableLabel'},
                color = 'white',
            },
            {
                selectors = {'searchableLabel'},
                color = 'white',
            },
            {
                selectors = {'searchableLabel', 'searching', '~matchSearch'},
                color = '#666666',
            },
            {
                selectors = {'hideOnSearchMismatch', 'searching', '~matchSearch'},
                collapsed = 1,
            }
		},

        create = function(element)
            --force parent's opacity to 1 even if blurred.
            local parentPanel = element:FindParentWithClass("framedPanel")
            if parentPanel ~= nil then
                parentPanel.selfStyle.opacity = 1
                parentPanel.selfStyle.borderWidth = 2.3
            end
        end,

		editCompendiumFeature = function(element, feature, fn)
			local path, tableid, key = FindFeaturePath(feature)
			if path ~= nil then
				g_recentFeatureEdits[#g_recentFeatureEdits+1] = {
					path = path,
					editor = fn,
                    tableid = tableid,
                    key = key,
				}
			end
		end,

        gui.Panel{
            height = "95%",
            width="auto",
            flow = "vertical",
            gui.SearchInput{
                width = 240,
                height = 20,
                fontSize = 16,
                placeholderText = "Search Compendium...",
                editlag = 0.4,
                edit = function(element)
                    resultPanel:FireEventTree("searchCompendium", trim(element.text))
                end,
            },
            gui.Panel{
                classes = {'list-panel'},
                vscroll = true,
                height = "100%-24",
                maxHeight = 1080,

                children = children,

            },
        },

		contentPanel,

		uploadStatus,

	}


	return resultPanel
end

local g_LibraryContentTypes = {"characterTypes", "classes", "subclasses", "races", "subraces", "backgrounds", "feats", "parties", "charConditions", "characterOngoingEffects", "creatureTemplates", "currency", "customAttributes", "damageTypes", "equipmentCategories", "featurePrefabs", "globalRuleMods", "languages", "characterResources", "Skills", "lootTables", "VisionType"}

LaunchablePanel.Register{
	name = "Compendium",
	icon = "game-icons/bookmarklet.png",
    presence = "Browsing Compendium",
	halign = "center",
	valign = "center",
	draggable = false,
	overdocks = true,
	filtered = function()
		return (not dmhub.GetSettingValue("permissions.playerlibrary")) and (not dmhub.isDM)
	end,

	content = function()

		return LibraryPanel()
	end,

	hasNewContent = function()
		for _,item in ipairs(g_LibraryContentTypes) do
			if module.HasNovelContent(item) then
				return true
			end
		end
		
		return false
	end,
}

Compendium = {

	Styles = LibraryStyles,
	AddButton = AddButton,
	CreateListItem = CreateListItem,

	--export show rolltable panel so others can use it.
	ShowRolltablePanel = ShowRolltablePanel,

	rollableTables = {},

    RegisterSection = function(t)
        CompendiumSectionsRegistry[#CompendiumSectionsRegistry+1] = {
            text = t.text,
            ord = t.ord or 0,
        }
    end,

	--pass in a {section: string, text: string, contentType: string?, admin: boolean?, click: function(Panel)}
	Register = function(options)
        if CompendiumRegistry[options.text] ~= nil and (CompendiumRegistry[options.text].priority or 0) > (options.priority or 0) then
            return
        end

		CompendiumRegistry[options.text] = options

		if options.section == "Tables" then
			Compendium.rollableTables[options.contentType] = {
				text = options.text,
				tableName = options.contentType,
			}
		end
	end,

	ShowModalEditDialog = function(dataType, dataid)
		local editor = dataType.CreateEditor()
		local SetData = editor.data.SetData
		local dataTable = dmhub.GetTable(Party.tableName) or {}
		local dataEntry = dataTable[dataid]
		if dataEntry == nil then
			return
		end

		SetData(dataType.tableName, dataid)

		local dialogPanel = gui.Panel{
			classes = {"framedPanel"},
			width = 1200,
			height = 940,
			pad = 8,
			flow = "vertical",
			styles = {
				Styles.Default,
				Styles.Panel,
				{
					classes = {"formPanel"},
					valign = "top",
				}
			},

			gui.Label{
				classes = {"dialogTitle"},
				text = string.format("Edit %s", dataEntry.name)
			},

			gui.Panel{
				width = "90%",
				height = "90%",
				halign = "center",
				valign = "top",
				vscroll = true,
				styles = {
					{
						valign = "top",
					}
				},
				editor,
			},

			gui.CloseButton{
				halign = "right",
				valign = "top",
				floating = true,
				escapeActivates = true,
				escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
				click = function()
					gui.CloseModal()
				end,
			},
		}

		gui.ShowModal(dialogPanel)
	end,

	--args : {contentPanel : Panel, tableid : string, createInstance : function(), createEditor : function(string)}
	ObjectTableEditor = function(args)
		local dataTable = dmhub.GetTable(args.tableid) or {}

		local m_editorPanel

		local dataItems = {}

		local itemsListPanel
		local leftPanel

		itemsListPanel = gui.Panel{
			classes = {'list-panel'},
			vscroll = true,
			monitorAssets = true,
			refreshAssets = function(element)

				dataTable = dmhub.GetTable(args.tableid) or {}

				local children = {}
				local newDataItems = {}

				for key,item in pairs(dataTable) do
					if item:try_get("hidden", false) == false then

						newDataItems[key] = dataItems[key] or CreateListItem{
							select = element.aliveTime > 0.2,
							click = function()
								args.contentPanel.children = {leftPanel, args.createEditor(key)}
							end,

							rightClick = function(element)
								element.popup = gui.ContextMenu{
									entries = {
										{
											text = "Delete",
											click = function()
												item.hidden = true
												dmhub.SetAndUploadTableItem(args.tableid, item)
												element.popup = nil
											end,
										},
									}
								}
							end,
						}

						newDataItems[key].text = item.name

						children[#children+1] = newDataItems[key]
					end
				end

				table.sort(children, function(a,b) return a.text < b.text end)

				dataItems = newDataItems
				itemsListPanel.children = children
			end,
		}

		itemsListPanel:FireEvent('refreshAssets')

		leftPanel = gui.Panel{
			selfStyle = {
				flow = 'vertical',
				height = '100%',
				width = 'auto',
			},

			itemsListPanel,
			AddButton{
				click = function(element)
					local newInstance = args.createInstance()
					dmhub.SetAndUploadTableItem(args.tableid, newInstance)
				end,
			}
		}

		args.contentPanel.children = {leftPanel}

	end,
}

Compendium.RegisterSection{
    text = "Character",
    ord = 0,
}
Compendium.RegisterSection{
    text = "Rules",
    ord = 10,
}
Compendium.RegisterSection{
    text = "Import",
    ord = 20,
}
Compendium.RegisterSection{
    text = "Tables",
    ord = 30,
}
Compendium.RegisterSection{
    text = "Assets",
    ord = 40,
}
Compendium.RegisterSection{
    text = "Modding",
    ord = 50,
}

Compendium.GenericEditor = function(parentPanel, entryType)
	local tableName = entryType.tableName

	local editorPanel = entryType.CreateEditor()
	local editorContainerPanel = gui.Panel{
		width = 900,
		height = "95%",
		vscroll = true,
		editorPanel,
	}

	local itemsListPanel = nil

	local items = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(tableName) or {}
			local newItems = {}

			for k,item in pairs(dataTable) do
				newItems[k] = items[k] or CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
					obliterateOnDelete = true,
					click = function()
						editorPanel.data.SetData(k)
					end,
				}

				newItems[k].text = item.name

				children[#children+1] = newItems[k]
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			items = newItems
			itemsListPanel.children = children
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

		AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, entryType.CreateNew{
				})
			end,
		}

	}

	parentPanel.children = {leftPanel, editorContainerPanel}
end



Compendium.CreateListItem = CreateListItem

local g_registeredPanels = false

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if g_registeredPanels then
        return
    end

    g_registeredPanels = true;

    Compendium.Register{
        section = "Character",
        text = "Attribute Generation",
        contentType = "attributeGenerator",
        click = function(contentPanel)
            ShowAttributeGeneratorPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Character",
        text = 'Character Types',
        contentType = "characterTypes",
        click = function(contentPanel)
            ShowCharacterTypesPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Character",
        text = 'Classes',
        contentType = "classes",
        click = function(contentPanel)
            ShowClassesPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Character",
        text = 'Subclasses',
        contentType = "subclasses",
        click = function(contentPanel)
            ShowClassesPanel(contentPanel, "subclasses")
        end,
    }

    Compendium.Register{
        section = "Character",
        text = GameSystem.RaceNamePlural,
        contentType = "races",
        click = function(contentPanel)
            ShowRacesPanel(contentPanel, "races")
        end,
    }

    Compendium.Register{
        section = "Character",
        text = GameSystem.BackgroundNamePlural,
        contentType = "backgrounds",
        click = function(contentPanel)
            ShowBackgroundsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Character",
        text = 'Perks',
        contentType = "feats",
        click = function(contentPanel)
            ShowFeatsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Character",
        text = 'Parties',
        contentType = "parties",
        click = function(contentPanel)
            ShowPartyPanel(contentPanel)
        end,
    }

    --Compendium.Register{
    --	section = "Rules",
    --	text = 'Game System',
        --contentType = "characterOngoingEffects",
    --	click = function(contentPanel)
    --		mod.shared.GameSystemCompendium(contentPanel)
    --	end,
    --}

    Compendium.Register{
        section = "Rules",
        text = 'Conditions',
        contentType = "charConditions",
        click = function(contentPanel)
            ShowConditionsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Condition Riders',
        contentType = CharacterCondition.ridersTableName,
        click = function(contentPanel)
            ShowOngoingEffectsPanel(contentPanel, "conditionRiders")
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'OngoingEffects',
        contentType = "characterOngoingEffects",
        click = function(contentPanel)
            ShowOngoingEffectsPanel(contentPanel, "characterOngoingEffects")
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Creature Templates',
        contentType = "creatureTemplates",
        click = function(contentPanel)
            ShowFeatsPanel(contentPanel, 'creatureTemplates')
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Currencies',
        contentType = "currency",
        click = function(contentPanel)
            ShowCurrencyPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Custom Attributes',
        contentType = "customAttributes",
        click = function(contentPanel)
            ShowCustomAttributesPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Custom Fields',
        contentType = "customfields",
        click = function(contentPanel)
            ShowCustomFieldsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Damage Types',
        contentType = "damageTypes",
        click = function(contentPanel)
            ShowDamageTypesPanel(contentPanel)
        end,
    }
    Compendium.Register{
        section = "Rules",
        text = 'Damage Flags',
        click = function(contentPanel)
            ShowDamageFlagsPanel(contentPanel)
        end,
    }
    Compendium.Register{
        section = "Rules",
        text = 'Equipment Categories',
        contentType = "equipmentCategories",
        click = function(contentPanel)
            ShowEquipmentCategoriesPanel(contentPanel)
        end,
    }
    Compendium.Register{
        section = "Rules",
        text = "Equipment Properties",
        contentType = WeaponProperty.tableName,
        click = function(contentPanel)
            ShowPropertyPanel(contentPanel, WeaponProperty)
        end,
    }
    Compendium.Register{
        section = "Rules",
        text = 'Feature Prefabs',
        contentType = "featurePrefabs",
        click = function(contentPanel)
            ShowFeaturePrefabsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Global Rules',
        contentType = "globalRuleMods",
        click = function(contentPanel)
            ShowGlobalModsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Inventory',
        contentType = "tbl_Gear",
        click = function(contentPanel)
            ShowInventoryPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = 'Languages',
        contentType = "languages",
        click = function(contentPanel)
            ShowLanguagesPanel(contentPanel)
        end,
    }
	Compendium.Register{
        section = "Rules",
        text = 'Titles',
        contentType = "titles",
        click = function(contentPanel)
            ShowTitlesPanel(contentPanel)
        end,
    }
    Compendium.Register{
        section = "Rules",
        text = 'Resources',
        contentType = "characterResources",
        click = function(contentPanel)
            ShowResourcesPanel(contentPanel)
        end,
    }
    Compendium.Register{
        section = "Rules",
        text = 'Skills',
        contentType = "Skills",
        click = function(contentPanel)
            ShowSkillsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Tables",
        text = 'Adventure Tables',
        contentType = "adventureTables",
        click = function(contentPanel)
            ShowRolltablePanel(contentPanel, "adventureTables", {
                text = true,
            })
        end,
    }

    Compendium.Register{
        section = "Tables",
        text = 'Encounter Tables',
        contentType = "encounterTables",
        click = function(contentPanel)
            ShowRolltablePanel(contentPanel, "encounterTables", {
                text = true,
                monsters = true,
            })
        end,
    }

    Compendium.Register{
        section = "Tables",
        text = 'Loot Tables',
        contentType = "lootTables",
        click = function(contentPanel)
            ShowRolltablePanel(contentPanel, "lootTables", {
                text = false,
                items = true,
            }, {
                showValue = true,
            })
        end,
    }

    Compendium.Register{
        section = "Tables",
        text = 'Name Generators',
        contentType = "nameGenerators",
        click = function(contentPanel)
            ShowRolltablePanel(contentPanel, "nameGenerators", {
                text = true,
                items = false,
            })
        end,
    }


    Compendium.Register{
        section = "Assets",
        text = 'Emotes (Cosmetic)',
        click = function(contentPanel)
            ShowEmojiPanel(contentPanel, 'Emoji')
        end,
    }
    Compendium.Register{
        section = "Assets",
        text = 'Emotes (Status Effects)',
        click = function(contentPanel)
            ShowEmojiPanel(contentPanel, 'Status')
        end,
    }
    Compendium.Register{
        section = "Assets",
        text = 'Emotes (Spellcasting)',
        click = function(contentPanel)
            ShowEmojiPanel(contentPanel, 'Spellcasting')
        end,
    }
    Compendium.Register{
        section = "Assets",
        text = 'Accessories',
        click = function(contentPanel)
            ShowEmojiPanel(contentPanel, 'Accessory')
        end,
    }
    Compendium.Register{
        section = "Assets",
        text = 'Token Frames',
        click = function(contentPanel)
            ShowImagesPanel(contentPanel, 'AvatarFrame')
        end,
    }
    Compendium.Register{
        section = "Assets",
        text = "Image Folders",
        click = function(contentPanel)
            ShowImageFoldersPanel(contentPanel)
        end,
    }
    --Compendium.Register{
    --	text = 'Token Ribbons',
    --	click = function()
    --		ShowImagesPanel(contentPanel, 'AvatarRibbon')
    --	end,
    --},

    Compendium.Register{
        section = "Assets",
        text = "Particle Images",
        click = function(contentPanel)
            ShowImageAtlasPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Assets",
        text = 'Translations',
        click = function(contentPanel)
            ShowTranslationsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Modding",
        text = 'Code Mods',
        click = function(contentPanel)
            ShowCodeModsPanel(contentPanel)
        end,
    }
    Compendium.Register{
        section = "Modding",
        text = 'Manage Compendium',
        click = function(contentPanel)
            ShowModManager(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Modding",
        text = 'Artists',
        click = function(contentPanel)
            ShowArtistsPanel(contentPanel)
        end,
    }

    Compendium.Register{
        section = "Rules",
        text = "Vision",
        contentType = VisionType.tableName,
        click = function(contentPanel)
            Compendium.GenericEditor(contentPanel, VisionType)
        end,
    }

    --Compendium.Register{
    --	text = 'Themes (Character Sheet)',
    --	click = function(contentPanel)
    --		ShowThemesPanel(contentPanel, "charsheet")
    --	end,
    --}
end)