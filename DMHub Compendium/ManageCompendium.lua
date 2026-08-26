local mod = dmhub.GetModLoading()

--this file implements the 'manage compendium' section of the compendium.
local function DescribeModuleName(moduleid)
	if moduleid == "Core" then
		return "DMHub"
	elseif moduleid == "CurrentGame" then
		return "Current Game"
	else
		return moduleid
	end
end

--collect the row's action buttons into a dense array. Either may be nil, and a
--nil in the middle of a positional child list holes the array and silently
--drops everything after it, so build the list explicitly.
local function ActionButtons(...)
	local result = {}
	for i=1,select("#", ...) do
		local button = select(i, ...)
		if button ~= nil then
			result[#result+1] = button
		end
	end
	return result
end

local function CreateMonsterTableView()
	local guids = {}

	local expanded = false

	local resultPanel
	local bodyPanel

	local headingCountText = gui.Label{
		classes = {"headingCountText"},
		text = "0",

		guids = function(element, guids)
			local t = assets.monsters
			local num = 0
			local selected = 0
			for k,entry in pairs(t) do
				num = num + 1
				if guids[k] then
					selected = selected + 1
				end
			end

			element.text = string.format("%d/%d", selected, num)

			resultPanel:SetClass("collapsed", selected == 0)
		end,
	}


	local headingPanel = gui.Panel{
		classes = {"header"},

		gui.Panel{
			classes = {"triangle"},
			styles = {
				{
					selectors = {"~expanded"},
					rotate = 90,
				}
			},

			press = function(element)
				expanded = not expanded
				element:SetClass("expanded", expanded)
				bodyPanel:SetClass("collapsed", not expanded)

				if not bodyPanel:HasClass("collapsed") then
					bodyPanel:FireEvent("expose")
				end
			end,
		},

		gui.Label{
			classes = {"headingText"},
			text = "Monsters",
		},

		headingCountText,
	}

	local childPanels = {}

	bodyPanel = gui.Panel{
		classes = {"body", cond(expanded, nil, "collapsed")},
		create = function(element)
		end,

		guids = function(element, newGuids)
			guids = newGuids
			if element:HasClass("collapsed") == false then
				element:FireEvent("expose")
			end
		end,

		expose = function(element)
			local children = {}
			local t = assets.monsters
			local newChildPanels = {}
			for k,entry in pairs(t) do
				
				local panel = childPanels[k]
				if panel == nil and guids[k] then
					local history = module.GetMonsterEntryChanges(k)

					local GenerateHistoryDesc = function()
						local historyDesc = ""
						if #history == 0 then
							historyDesc = "NO HISTORY"
						elseif #history == 1 then
							historyDesc = string.format("%s (%s)", DescribeModuleName(history[1].moduleid), dmhub.FormatTimestamp(history[1].ctime))

						else
							for i,item in ipairs(history) do
								if i ~= 1 then
									historyDesc = historyDesc .. " -> "
								end

								historyDesc = historyDesc .. string.format("%s (%s)", DescribeModuleName(item.moduleid), dmhub.FormatTimestamp(history[i].ctime))
							end

							--now check to see if there are 'conflicts'.
							for i,item in ipairs(history) do
								local hasChanges = false
								for j=i+1,#history do
									local newItem = history[j]
									if tonumber(newItem.ctime) ~= nil and tonumber(item.mtime) ~= nil and tonumber(item.mtime) > tonumber(newItem.ctime) then
										hasChanges = true
									end
								end

								if hasChanges then
									historyDesc = string.format("%s <color=#ff0000>-> %s", historyDesc, DescribeModuleName(item.moduleid))
								end
							end
						end
						return historyDesc
					end

					local revertButton = nil
					if #history > 1 then
						for i,item in ipairs(history) do
							if item.moduleid == "CurrentGame" then
								local index = i
								revertButton = gui.Button{
									text = "Revert",
									hmargin = 4,
									width = 80,
									height = 20,
									fontSize = 14,
									click = function(element)
                                        local monster = assets.monsters[k]
                                        if monster ~= nil then
                                            monster:ObliterateGameChanges()
                                        end
										table.remove(history, index)
										--panel:FireEventTree("regenhistory")
										panel:SetClass("collapsed", true)
										element:DestroySelf()
									end,
								}
							end
						end
					end

					local undeleteButton = nil
					if entry.hidden then
						undeleteButton = gui.Button{
							text = "Undelete",
							hmargin = 4,
							width = 80,
							height = 20,
							fontSize = 14,
							click = function(element)
								entry.hidden = false
                                entry:Upload()
								panel:FireEventTree("regenhistory")
								element:DestroySelf()
								undeleteButton = nil
							end,
						}
					end

					panel = gui.Panel{
						classes = {"entryPanel"},
						data = {
							ord = string.lower(entry.name or "")
						},
						--gui.Label{
						--	classes = {"entryLabel", "id"},
						--	text = entry.id,
						--},
						gui.Label{
							classes = {"entryLabel", "name"},
							text = entry.name or "Unknown",
						},
						gui.Label{
							classes = {"entryLabel", "history"},
							height = "auto",
							text = GenerateHistoryDesc(),
							regenhistory = function(element)
								element.text = GenerateHistoryDesc()
							end,

						},
						gui.Label{
							classes = {"entryLabel", "status"},
							text = cond(entry.hidden, "deleted", ""),
							regenhistory = function(element)
								element.text = cond(entry.hidden, "deleted", "")
							end,
						},
						gui.Panel{
							classes = {"entryActions"},
							children = ActionButtons(revertButton, undeleteButton),
						},
					}
				end

				if panel ~= nil then
					panel:SetClass("collapsed", not guids[k])
					newChildPanels[k] = panel
					children[#children+1] = panel
				end

			end

			childPanels = newChildPanels

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			element.children = children
		end,
	}

	resultPanel = gui.Panel{
		classes = {"tableView"},
		headingPanel,
		bodyPanel,
	}

	return resultPanel
end

local function CreateObjectTableView(tableName)
	local guids = {}

	local expanded = false

	local resultPanel
	local bodyPanel

	local headingCountText = gui.Label{
		classes = {"headingCountText"},
		text = "0",

		guids = function(element, guids)
			local t = dmhub.GetTable(tableName)
			local num = 0
			local selected = 0
			for k,entry in pairs(t) do
				num = num + 1
				if guids[k] then
					selected = selected + 1
				end
			end

			element.text = string.format("%d/%d", selected, num)

			resultPanel:SetClass("collapsed", selected == 0)
			
		end,
	}


	local headingPanel = gui.Panel{
		classes = {"header"},

		gui.Panel{
			classes = {"triangle"},
			styles = {
				{
					selectors = {"~expanded"},
					rotate = 90,
				}
			},

			press = function(element)
				expanded = not expanded
				element:SetClass("expanded", expanded)
				bodyPanel:SetClass("collapsed", not expanded)

				if not bodyPanel:HasClass("collapsed") then
					bodyPanel:FireEvent("expose")
				end
			end,
		},

		gui.Label{
			classes = {"headingText"},
			text = tableName,
		},

		headingCountText,
	}

	local childPanels = {}

	bodyPanel = gui.Panel{
		classes = {"body", cond(expanded, nil, "collapsed")},
		create = function(element)
		end,

		guids = function(element, newGuids)
			guids = newGuids
			if element:HasClass("collapsed") == false then
				element:FireEvent("expose")
			end
		end,

		expose = function(element)
			local children = {}
			local t = dmhub.GetTable(tableName)
			local newChildPanels = {}
			for k,entry in pairs(t) do
				
				local panel = childPanels[k]
				if panel == nil and guids[k] then
					local history = module.GetObjectTableChanges(tableName, k)

					local GenerateHistoryDesc = function()
						local historyDesc = ""
						if #history == 0 then
							historyDesc = "NO HISTORY"
						elseif #history == 1 then
							historyDesc = string.format("%s (%s)", DescribeModuleName(history[1].moduleid), dmhub.FormatTimestamp(history[1].ctime))

						else
							for i,item in ipairs(history) do
								if i ~= 1 then
									historyDesc = historyDesc .. " -> "
								end

								historyDesc = historyDesc .. string.format("%s (%s)", DescribeModuleName(item.moduleid), dmhub.FormatTimestamp(history[i].ctime))
							end

							--now check to see if there are 'conflicts'.
							for i,item in ipairs(history) do
								local hasChanges = false
								for j=i+1,#history do
									local newItem = history[j]
									if tonumber(rawget(newItem, "ctime")) ~= nil and tonumber(rawget(item, "mtime")) ~= nil and tonumber(item.mtime) > tonumber(newItem.ctime) then
										hasChanges = true
									end
								end

								if hasChanges then
									historyDesc = string.format("%s <color=#ff0000>-> %s", historyDesc, DescribeModuleName(item.moduleid))
								end
							end
						end
						return historyDesc
					end

					local revertButton = nil
					if #history > 1 then
						for i,item in ipairs(history) do
							if item.moduleid == "CurrentGame" then
								local index = i
								revertButton = gui.Button{
									text = "Revert",
									hmargin = 4,
									width = 80,
									height = 20,
									fontSize = 14,
									click = function(element)
										dmhub.ObliterateTableItem(tableName, k)
										table.remove(history, index)
										--panel:FireEventTree("regenhistory")
										panel:SetClass("collapsed", true)
										element:DestroySelf()
									end,
								}
							end
						end
					end

					local undeleteButton = nil
					if rawget(entry, "hidden") then
						undeleteButton = gui.Button{
							text = "Undelete",
							hmargin = 4,
							width = 80,
							height = 20,
							fontSize = 14,
							click = function(element)
								entry.hidden = nil
								dmhub.SetAndUploadTableItem(tableName, entry)
								panel:FireEventTree("regenhistory")
								element:DestroySelf()
								undeleteButton = nil
							end,
						}
					end

					panel = gui.Panel{
						classes = {"entryPanel"},
						data = {
							ord = string.lower(entry.name)
						},
						--gui.Label{
						--	classes = {"entryLabel", "id"},
						--	text = entry.id,
						--},
						gui.Label{
							classes = {"entryLabel", "name"},
							text = entry.name,
						},
						gui.Label{
							classes = {"entryLabel", "history"},
							height = "auto",
							text = GenerateHistoryDesc(),
							regenhistory = function(element)
								element.text = GenerateHistoryDesc()
							end,

						},
						gui.Label{
							classes = {"entryLabel", "status"},
							text = cond(rawget(entry, "hidden"), "deleted", ""),
							regenhistory = function(element)
								element.text = cond(rawget(entry, "hidden"), "deleted", "")
							end,
						},
						gui.Panel{
							classes = {"entryActions"},
							children = ActionButtons(revertButton, undeleteButton),
						},
					}
				end

				if panel ~= nil then
					panel:SetClass("collapsed", not guids[k])
					newChildPanels[k] = panel
					children[#children+1] = panel
				end

			end

			childPanels = newChildPanels

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			element.children = children
		end,
	}

	resultPanel = gui.Panel{
		classes = {"tableView"},
		headingPanel,
		bodyPanel,
	}

	return resultPanel
end

local function CreateAssetTableView(assetName)
	local guids = {}

	local expanded = false

	local resultPanel
	local bodyPanel

	local headingCountText = gui.Label{
		classes = {"headingCountText"},
		text = "0",

		guids = function(element, guids)
			local selected = 0
			local num = 0
			local allAssets = assets.allAssets
			for k,assetInfo in pairs(allAssets) do
				if assetInfo.assetType == assetName then
					num = num+1

					if guids[k] then
						selected = selected + 1
					end
				end
			end

			element.text = string.format("%d/%d", selected, num)
			resultPanel:SetClass("collapsed", selected == 0)
		end,
	}


	local headingPanel = gui.Panel{
		classes = {"header"},

		gui.Panel{
			classes = {"triangle"},
			styles = {
				{
					selectors = {"~expanded"},
					rotate = 90,
				}
			},

			press = function(element)
				expanded = not expanded
				element:SetClass("expanded", expanded)
				bodyPanel:SetClass("collapsed", not expanded)

				if not bodyPanel:HasClass("collapsed") then
					bodyPanel:FireEvent("expose")
				end
			end,
		},

		gui.Label{
			classes = {"headingText"},
			text = assetName,
		},

		headingCountText,
	}

	local childPanels = {}

	bodyPanel = gui.Panel{
		classes = {"body", cond(expanded, nil, "collapsed")},
		create = function(element)
		end,

		guids = function(element, newGuids)
			guids = newGuids
			if element:HasClass("collapsed") == false then
				element:FireEvent("expose")
			end
		end,

		expose = function(element)
			local children = {}

			local newChildPanels = {}

			local allAssets = assets.allAssets
			for k,assetInfo in pairs(allAssets) do
				if assetInfo.assetType == assetName and guids[k] then
					local panel = childPanels[k]
					if panel == nil and guids[k] then
						local revertButton = nil
						local undeleteButton = nil

						panel = gui.Panel{
							classes = {"entryPanel"},
							data = {
								ord = string.lower(assetInfo.description)
							},
							--gui.Label{
							--	classes = {"entryLabel", "id"},
							--	text = entry.id,
							--},
							gui.Label{
								classes = {"entryLabel", "name"},
								text = assetInfo.description,
							},
							--gui.Label{
							--	classes = {"entryLabel", "history"},
							--	height = "auto",
							--	text = GenerateHistoryDesc(),
							--	regenhistory = function(element)
							--		element.text = GenerateHistoryDesc()
							--	end,

							--},
							gui.Label{
								classes = {"entryLabel", "status"},
								text = cond(assetInfo.hidden, "deleted", ""),
								regenhistory = function(element)
									element.text = cond(assetInfo.hidden, "deleted", "")
								end,
							},
							revertButton,
							undeleteButton,
						}

					end

					newChildPanels[k] = panel
					children[#children+1] = panel
					
				end
			end

			childPanels = newChildPanels

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			element.children = children
		end,
	}

	resultPanel = gui.Panel{
		classes = {"tableView"},
		headingPanel,
		bodyPanel,
	}

	return resultPanel
end

local function GetDataSources(dependenciesList)
	local dataSources = {}

	dataSources[#dataSources+1] = {
		moduleid = "Core",
		name = "DMHub",
	}

	for _,dependencyEntry in ipairs(dependenciesList) do
		local m = module.GetModule(dependencyEntry.moduleid)
		local indent = 0
		printf("DependencyEntry: %s; parent = %s", dependencyEntry.moduleid, json(dependencyEntry.parentModuleId))
		if dependencyEntry.parentModuleId ~= nil and dependencyEntry.parentModuleId ~= "" then
			printf("DependencyEntry: searching for matching parent...")
			for _,entry in ipairs(dataSources) do
				printf("DependencyEntry: try %s", entry.moduleid)
				if entry.moduleid == dependencyEntry.parentModuleId then
					printf("DependencyEntry: match!")
					indent = entry.indent + 1
				end
			end
		end

		dataSources[#dataSources+1] = {
			moduleid = m.fullid,
			name = m.name,
			version = m.loadedVersion,
			latest = m.latestVersion or "?",
			ismodule = true,
			deprecated = m.deprecated,
			deprecationMessage = m.deprecationMessage,
			indent = indent,
		}
	end

	dataSources[#dataSources+1] = {
		moduleid = "CurrentGame",
		name = "Current Game",
	}

	return dataSources
end

local CreateSourcesPanel = function(options)

	local args = {
		width = 320,
		height = "100%-16",
		vmargin = 8,
		vscroll = true,
		hmargin = 16,
		flow = "vertical",

		styles = {
			{
				selectors = {"label", "row"},
				bgcolor = "black",
				color = "white",
			},
			{
				selectors = {"label", "row", "disabled"},
				color = "#888888",
			},
			{
				selectors = {"label", "row", "selected"},
				bgcolor = "#990000",
			},
			{
				selectors = {"label", "row", "hover"},
				bgcolor = "#bb0000",
			},
		},
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	local sourcesPanel = gui.Panel(args)

	module.GetModuleDependencies(function(dependenciesList)

		local dataSources = GetDataSources(dependenciesList)

		local dataSourceRows = {}

		for i,source in ipairs(dataSources) do
			local name = source.moduleid
			if source.version ~= nil then
				name = string.format("%s (ver %s/%s)", name, source.version, source.latest)
			end
			if source.deprecated then
				name = string.format("%s [DEPRECATED]", name)
			end
			dataSourceRows[#dataSourceRows+1] = gui.Label{
				classes = {"row"},
				width = "100%-16",
				fontSize = 14,
				height = 18,
				bgimage = "panels/square.png",
				text = name,
				lmargin = 6 + (source.indent or 0)*6,

				data = {
					moduleid = source.moduleid,
				},

				create = function(element)
					if i == 1 then
						element:FireEvent("press")
					end
				end,

				thinkTime = 0.1,
				think = function(element)
					if source.ismodule then
						element:SetClass("disabled", module.GetModule(source.moduleid).isdisabled)
					end
				end,

				press = function(element)
					local shift = dmhub.modKeys["shift"]
					local ctrl = dmhub.modKeys["ctrl"]

					if shift or ctrl then
						element:SetClass("selected", not element:HasClass("selected"))
					else
						for _,el in ipairs(element.parent.children) do
							el:SetClass("selected", el == element)
						end
					end

					local items = {}
					for _,el in ipairs(element.parent.children) do
						if el:HasClass("selected") then
							items[#items+1] = el.data.moduleid
						end
					end

					sourcesPanel:FireEvent("change", items)
				end,

				hover = function(element)
					if not source.deprecated then
						return
					end

					--deprecation only sets the default: say so, and say which
					--side of it this game is currently on.
					local m = module.GetModule(source.moduleid)
					local suffix = "\n\nIt is disabled in your games. Right click to enable it again anyway."
					if source.ismodule and m ~= nil and m.deprecationOverridden then
						suffix = "\n\nYou have chosen to enable it in this game anyway. Right click to disable it."
					end

					gui.Tooltip(string.format("DEPRECATED: %s%s", source.deprecationMessage, suffix))(element)
				end,

				rightClick = function(element)
					if not source.ismodule then
						return
					end

					element.popup = gui.ContextMenu{
						entries = {
							{
								text = cond(module.GetModule(source.moduleid).isdisabled, "Enable Module", "Disable Module"),
								click = function()
									module.GetModule(source.moduleid):SetDisabled(not module.GetModule(source.moduleid).isdisabled)
									element.popup = nil
								end,
							},
						}
					}
				end,

			}
		end

		sourcesPanel.children = dataSourceRows
	end)

	return sourcesPanel
end


local CreateModManager = function()
	local resultPanel
	local objectsTree

	local sourcesPanel = CreateSourcesPanel{
		change = function(element, moduleids)
			local guids = module.GuidsLoaded(moduleids, {
				includeAllTouches = true
			})
			objectsTree:FireEventTree("guids", guids)
		end,
	}

	local nodes = {}

	for _,tableName in ipairs(dmhub.GetTableTypes()) do
		nodes[#nodes+1] = CreateObjectTableView(tableName)
	end

    nodes[#nodes+1] = CreateMonsterTableView()

	local assetNames = {}
	local assetNamesSorted = {}
	for _,assetEntry in pairs(assets.allAssets) do
		if not assetNames[assetEntry.assetType] then
			assetNames[assetEntry.assetType] = true
			assetNamesSorted[#assetNamesSorted+1] = assetEntry.assetType
		end
	end

	table.sort(assetNamesSorted)

	for _,k in ipairs(assetNamesSorted) do
		--nodes[#nodes+1] = CreateAssetTableView(k)
	end

	objectsTree = gui.Panel{
		vscroll = true,
		width = "100%-352",
		height = "100%",
		valign = "top",
		halign = "left",
		vscroll = true,
		flow = "vertical",
		children = nodes,
	}

	resultPanel = gui.Panel{
		width = "100%-32",
		height = "100%-32",
		valign = "top",
		halign = "left",
		vmargin = 16,
		hmargin = 16,
		flow = "horizontal",

		styles = {
			{
				selectors = {"header"},
				width = "100%",
				flow = "horizontal",
				height = 18,
			},
			{
				selectors = {"body"},
				width = "100%",
				flow = "vertical",
				height = "auto",
			},
			{
				selectors = {"entryPanel"},
				width = "100%-16",
				hmargin = 8,
				vmargin = 2,
				minHeight = 22,
				height = "auto",
				flow = "horizontal",
			},
			{
				selectors = {"entryLabel"},
				fontSize = 14,
				minFontSize = 8,
				height = 18,
				width = 180,
				halign = "left",
				textAlignment = "left",
			},
			{
				selectors = {"entryLabel", "history"},
				width = "100%-436",
			},
			{
				selectors = {"entryLabel", "status"},
				width = 64,
			},
			{
				selectors = {"entryActions"},
				flow = "horizontal",
				width = 176,
				height = 20,
				halign = "left",
				valign = "center",
			},
			{
				selectors = {"triangle"},
				bgimage = "panels/triangle.png",
				bgcolor = "#ffffffaa",
				halign = "left",
				valign = "center",
				width = 8,
				height = 8,
			},

			{
				selectors = {"triangle", "hover"},
				bgcolor = "white",
			},
			{
				selectors = {"headingText"},
				fontSize = 14,
				color = "white",
				width = 200,
				height = "auto",
				halign = "left",
				valign = "center",
				hmargin = 6,
			},
			{
				selectors = {"headingCountText"},
				fontSize = 12,
				color = "white",
				width = "auto",
				height = "auto",
				halign = "left",

			},
			{
				selectors = {"tableView"},
				flow = "vertical",
				width = "100%",
				height = "auto",
				valign = "top",
			},
		},

		sourcesPanel,

		objectsTree,
	}
	return resultPanel
end


function ShowModManager(parentPanel)
	parentPanel.children = {CreateModManager()}

end