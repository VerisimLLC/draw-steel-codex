local mod = dmhub.GetModLoading()

local CreateMapNodePanel
local CreateMapFolderPanel
local CreateMapFolderChildPanel

local createCheck = function(element)
	element:FireEventOnParents("createasset", element)

	--debug show guid of object.
	--element.data.SetText(element.data.GetText() .. " " .. element.data.assetid)
end

local changeCheck = function(element)
	element:FireEventOnParents("selectasset", element)
end

local countCheck = function(element, counts)
	if element:HasClass("silent") then
		return
	end

	counts.total = counts.total + 1
	if element.value then
		counts.selected = counts.selected + 1
	end
end

local selectionCheck = function(element, t)
	if element:HasClass("silent") then
		return
	end

	element.value = (t == "all")
end

local collectManifestCheck = function(element, entries)
	if not element.value then
		return
	end

	local t = element.data.type
	for _,entry in ipairs(entries) do
		if entry.type == t then
			entry.items[#entry.items+1] = element.data.displayName
			return
		end
	end

	entries[#entries+1] = {
		type = t,
		items = {element.data.displayName}
	}
end

setting{
	id = "module:exportignoredependencies",
	description = "When exporting modules, you can ignore dependency checking.",
	storage = "preference",
	default = false,
}

local includedAssets = function(element, includedAssets, dependencyAssets, signal)
    --note dependents only include if the element is not a modify, since we don't
    --have to ship the dependent if we only modified it rather than created it.
	local dependents = (not element:HasClass("modify")) and dependencyAssets[element.data.assetid]

	local val = cond(includedAssets[element.data.assetid] or dependents, true, false)

	local canOverride = not dmhub.GetSettingValue("module:exportignoredependencies")


	if canOverride then
		element.SetValue(element, val, signal)
	end

	element.data.dependents = dependents

	element:SetClassTree(cond(canOverride, "disabled", "error"), cond(dependents, true, false))
end

local checkTooltip = function(element)
	if (element:HasClass("disabled") or element:HasClass("error")) and element.data.dependents and element.data.dependents[1] then
		local dependentInfo = element.data.allAssets[element.data.dependents[1]]
		if dependentInfo ~= nil then
			local displayName = dependentInfo.check.data.displayName
			local text
			if #element.data.dependents > 1 then
				text = string.format("Required by %d other entries, such as %s.", #element.data.dependents, displayName)
			else
				text = string.format("Required by %s.", displayName)
			end

			gui.Tooltip(text)(element)
		end
	end
end

CreateMapNodePanel = function(map)
	local resultPanel
	local check = gui.Check{
		idprefix = "map-label",
		text = map.description,
		value = false,
		width = 340,
		height = 20,
		halign = "left",
		create = createCheck,
		change = changeCheck,
		count = countCheck,
		linger = checkTooltip,
		includedAssets = includedAssets,
		collectManifest = collectManifestCheck,
		selection = function(element, t)
			local val = (t == "all")
			if t == "this" and map.id == game.currentMapId then
				val = true
			end

			element.value = val
		end,
		data = {
			assetid = map.id,
			displayName = map.description or "(unknown map)",
			data = map,
			type = "map",
		}
	}

	return check
end

local triangleStyles = {
	gui.Style{
		classes = {"triangle"},
		bgimage = "panels/triangle.png",
		bgcolor = "white",
		hmargin = 4,
		halign = "left",
		height = 12,
		width = 12,
		rotate = 90,
	},
	gui.Style{
		classes = {"triangle", "expanded"},
		rotate = 0,
		transitionTime = 0.2,
	},
	gui.Style{
		classes = {"triangle", "hover"},
		bgcolor = "yellow",
	},
	gui.Style{
		classes = {"triangle", "press"},
		bgcolor = "gray",
	},
}

CreateMapFolderPanel = function(folder, isroot, optionsPanel)

	local text = folder.description

	if isroot then
		text = "Maps"

	end

	local childPanel = CreateMapFolderChildPanel(folder)

	if optionsPanel ~= nil then
		local children = childPanel.children

		table.insert(children, 1, optionsPanel)

		childPanel.children = children
	end

	local triangle = gui.Panel{
		idprefix = "map-triangle",
		classes = {"triangle", "expanded"},
		styles = triangleStyles,

		press = function(element)
			element:SetClass("expanded", not element:HasClass("expanded"))
			childPanel:SetClass("collapsed", not element:HasClass("expanded"))
		end,
	}

	local countLabel = gui.Label{
		text = "",
		updatecounts = function(element)
			local counts = { total = 0, selected = 0 }
			childPanel:FireEventTree("count", counts)
			element.text = string.format("(%d/%d)", counts.selected, counts.total)
		end,
	}

	countLabel:FireEvent("updatecounts")

	local headerPanel = gui.Panel{
		idprefix = "map-header",
		classes = {"row"},
		bgimage = "panels/square.png",
		data = {
			data = folder,
			isfolder = true,
		},

		triangle,
		gui.Label{
			idprefix = "folder-label",
			text = text,
			bold = cond(isroot, true, false),
		},
		countLabel,
	}

	return gui.Panel{
		idprefix = "map-folder-body",
		flow = "vertical",
		width = "100%",
		height = "auto",
		halign = "left",
		data = {
			data = folder,
			isfolder = true,
		},
		headerPanel,
		gui.Panel{
			idprefix = "map-folder-body-main",
			width = "100%-16",
			halign = "right",
			height = "auto",
			childPanel,
		},
	}
end

local CreateCharacterFolderChildPanel = function()
	local chars = game.GetGameGlobalCharacters()

	local resultPanel
	local children = {}

	children[#children+1] = gui.Panel{
		classes = {"linkContainer"},

		data = {
			ord = "0",
		},

		gui.Label{
			classes = {"link"},
			text = "Select All",
			click = function(element)
				resultPanel:FireEventTree("selection", "all")
			end,
		},
		gui.Panel{
			classes = {"linkDivider"},
		},
		gui.Label{
			classes = {"link"},
			text = "Clear All",
			click = function(element)
				resultPanel:FireEventTree("selection", "none")
			end,
		},
	}



	for k,c in pairs(chars) do
		local name = c.name or "(unnamed)"
		local ord
		if c.playerControlledNotShared then
			ord = '1' .. name
		elseif c.playerControlled then
			ord = '2' .. name
		else
			ord = '3' .. name
		end

		children[#children+1] = gui.Check{

			customPanel = gui.CreateTokenImage(c, {
				width = 20,
				height = 20,
				hmargin = 2,
				halign = "left",
			}),

			classes = {"row"},
			text = string.format("%s (%s)", name, k),
			value = false,
			width = 340,
			height = 20,
			halign = "left",
			create = createCheck,
			change = changeCheck,
			count = countCheck,
			linger = checkTooltip,
			includedAssets = includedAssets,
			collectManifest = collectManifestCheck,
			selection = selectionCheck,
			data = {
				assetid = k,
				displayName = c.name or "(unknown token)",
				ord = ord,
				type = "character",
			},
		}
	end

	table.sort(children, function(a,b)
			return a.data.ord < b.data.ord
	end)

	resultPanel = gui.Panel{
		idprefix = "char-folder-child",
		width = "80%",
		height = "auto",
		flow = "vertical",
		valign = "top",
		halign = "left",
		children = children,
	}

	return resultPanel
end



local CreateCharacterSelectionPanel = function()
	local childPanel = CreateCharacterFolderChildPanel()

	local triangle = gui.Panel{
		idprefix = "map-triangle",
		classes = {"triangle", "expanded"},
		styles = triangleStyles,

		press = function(element)
			element:SetClass("expanded", not element:HasClass("expanded"))
			childPanel:SetClass("collapsed", not element:HasClass("expanded"))
		end,
	}

	local countLabel = gui.Label{
		text = "",
		updatecounts = function(element)
			local counts = { total = 0, selected = 0 }
			childPanel:FireEventTree("count", counts)
			element.text = string.format("(%d/%d)", counts.selected, counts.total)
		end,
	}

	countLabel:FireEvent("updatecounts")

	local headerPanel = gui.Panel{
		idprefix = "char-header",
		classes = {"row"},
		bgimage = "panels/square.png",

		triangle,
		gui.Label{
			idprefix = "folder-label",
			text = "Characters",
			bold = true,
		},
		countLabel,
	}

	return gui.Panel{
		idprefix = "char-folder-body",
		flow = "vertical",
		width = "100%",
		height = "auto",
		halign = "left",
		headerPanel,
		gui.Panel{
			idprefix = "char-folder-body-main",
			width = "100%-16",
			halign = "right",
			height = "auto",
			childPanel,
		},
	}

end

CreateMapFolderChildPanel = function(folder)
	local childNodes = {}
	local resultPanel = gui.Panel{
		idprefix = "map-folder-child",
		width = "80%",
		height = "auto",
		flow = "vertical",
		valign = "top",
		halign = "left",
		init = function(element)
			local newChildNodes = {}
			local children = {}
			for _,map in ipairs(folder.childMaps) do
				local newChild = childNodes[map.mapid] or CreateMapNodePanel(map)
				children[#children+1] = newChild
				newChildNodes[map.mapid] = newChild
			end

			for _,f in ipairs(folder.childFolders) do
				local newChild = childNodes[f.folderid] or CreateMapFolderPanel(f)
				children[#children+1] = newChild
				newChildNodes[f.folderid] = newChild
			end
			table.sort(children, function(pa,pb)
				local a = pa.data.data
				local b = pb.data.data
				if (not a.valid) and (not a.valid) then
					return false
				end

				if not a.valid then
					return true
				end

				if not b.valid then
					return false
				end

				if a.ord ~= b.ord then
					return a.ord < b.ord
				end

				return a.description < b.description
			end)

			local newChildren = element.children
			for _,c in ipairs(children) do
				newChildren[#newChildren+1] = c
			end

			element.children = newChildren
			childNodes = newChildNodes
		end,
	}

	resultPanel:FireEvent("init")

	return resultPanel
end

local g_tableDisplayNames = {
	tbl_Gear = "Equipment",
	classes = "Classes",
	feats = "Feats",
	backgrounds = "Backgrounds",
	charConditions = "Character Conditions",
	characterOngoingEffects = "Ongoing Effects",
	characterResources = "Character Resources",
	characterTypes = "Character Types",
	creatureTemplates = "Creature Templates",
	currency = "Currency",
	customAttributes = "Character Attributes",
	damageTypes = "Damage Types",
	equipmentCategories = "Equipment Categories",
	featurePrefabs = "Character Feature Prefabs",
	globalRuleMods = "Global Rules",
	languages = "Languages",
	lootTables = "Loot Tables",
	nameGenerators = "Name Generators",
	parties = "Parties",
	races = "Races",
	subclasses = "Subclasses",
	subraces = "Subraces",
}

local g_tableDisplayNamesSingular = {
	tbl_Gear = "Equipment",
	classes = "Class",
	feats = "Feat",
	backgrounds = "Background",
	charConditions = "Character Condition",
	characterOngoingEffects = "Ongoing Effect",
	characterResources = "Character Resource",
	characterTypes = "Character Type",
	creatureTemplates = "Creature Template",
	currency = "Currency",
	customAttributes = "Character Attribute",
	damageTypes = "Damage Type",
	equipmentCategories = "Equipment Category",
	featurePrefabs = "Character Feature Prefab",
	globalRuleMods = "Global Rule",
	languages = "Language",
	lootTables = "Loot Table",
	nameGenerators = "Name Generator",
	parties = "Party",
	races = "Race",
	subclasses = "Subclass",
	subraces = "Subrace",
}

local DescribeModuleContentType = function(contentType, quantity)
	local result
	if string.starts_with(contentType, "object:") then
		local subs = string.sub(contentType, 8)
		if quantity == 1 then
			result = g_tableDisplayNamesSingular[subs] or subs
		else
			result = g_tableDisplayNames[subs] or subs
		end
	else
		result = contentType
	end

	--starts with an upper case character.
	return string.upper(string.sub(result, 1, 1)) .. string.sub(result, 2)
end

local DescribeModuleContents = function(entries)
	if entries == nil or #entries == 0 then
		return nil
	end

	table.sort(entries, function(a,b)
		return DescribeModuleContentType(a.type) < DescribeModuleContentType(b.type)
	end)

	local result = ""
	for _,entry in ipairs(entries) do
		result = string.format("%s%d %s\n", result, #entry.items, DescribeModuleContentType(entry.type, #entry.items))
	end

	return result
end

local GetTableDisplayName = function(tableName)
	return g_tableDisplayNames[tableName] or tableName

end

local CreateObjectTableView = function(tableName, knownAssetsInCore)

	local expanded = false

	local resultPanel
	local bodyPanel

	local headingCountText = gui.Label{
		classes = {"headingCountText"},
		text = "0",
	}

	local selectionOptions

	local headingPanel = gui.Panel{
		classes = {"row"},

		gui.Panel{
			classes = {"triangle"},
			styles = triangleStyles,

			press = function(element)
				expanded = not expanded
				element:SetClass("expanded", expanded)
				bodyPanel:SetClass("collapsed", not expanded)
				selectionOptions:SetClass("collapsed", not expanded)
			end,
		},

		gui.Label{
			classes = {"headingText"},
			text = GetTableDisplayName(tableName),
		},

		headingCountText,
	}

	selectionOptions = gui.Panel{
		classes = {"linkContainer", "collapsed"},

		gui.Label{
			classes = {"link"},
			text = "Select All",
			click = function(element)
				bodyPanel:FireEventTree("selection", "all")
			end,
		},
		gui.Panel{
			classes = {"linkDivider"},
		},
		gui.Label{
			classes = {"link"},
			text = "Clear All",
			click = function(element)
				bodyPanel:FireEventTree("selection", "none")
			end,
		},
	}



	local numChildren = 0

	bodyPanel = gui.Panel{
		classes = {cond(expanded, nil, "collapsed")},
		width = "100%",
		height = "auto",
		flow = "vertical",
		init = function(element)
			local children = {}
			local t = dmhub.GetTable(tableName)
			for k,entry in pairs(t) do
				local incore = knownAssetsInCore[k]
				local hidden = rawget(entry, "hidden") == true
				--if (not hidden) or incore then
					local op = "create"
					if hidden then
						op = "delete"
					elseif incore then
						op = "modify"
					end

                    print("ENTRY::", entry.name, type(entry.name), json(entry))

					local panel = gui.Check{
						classes = {"row", op}, --cond(hidden, "silent")},
						text = string.format("%s (%s -- %s)", entry.name, op, k),
						value = false,
						width = 340,
						height = 20,
						halign = "left",
						create = createCheck,
						change = changeCheck,
						count = countCheck,
						linger = checkTooltip,
						includedAssets = includedAssets,
						collectManifest = collectManifestCheck,
						selection = selectionCheck,
						data = {
							assetid = k,
							displayName = entry.name or "(unknown object)",
							ord = string.lower(entry.name),
							type = string.format("object:%s", tableName),
						},
					}

					children[#children+1] = panel
				--end
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			numChildren = #children

			element.children = children

			element:FireEvent("updatecounts")
		end,

		updatecounts = function(element)
			local counts = { total = 0, selected = 0 }
			element:FireEventTree("count", counts)

			headingCountText.text = string.format("(%d/%d)", counts.selected, counts.total)
		end,

	}

	bodyPanel:FireEvent("init")

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		headingPanel,
		selectionOptions,
		bodyPanel,
	}

	if numChildren == 0 then
		resultPanel:SetClass("collapsed", true)
	end

	return resultPanel
end

local function GatherAllAssetsChildren(children, knownAssetsInCore)

	local all = assets.allAssets

	local assetsByType = {}

	for k,v in pairs(all) do
		local items = assetsByType[v.assetType] or {}
		items[k] = v
		assetsByType[v.assetType] = items
	end

	for t,items in pairs(assetsByType) do
		local expanded = false

		local resultPanel
		local bodyPanel
		local selectionOptions

		local headingCountText = gui.Label{
			classes = {"headingCountText"},
			text = "0",
		}


		local headingPanel = gui.Panel{
			classes = {"row"},

			gui.Panel{
				classes = {"triangle"},
				styles = triangleStyles,

				press = function(element)
					expanded = not expanded
					element:SetClass("expanded", expanded)
					bodyPanel:SetClass("collapsed", not expanded)
					selectionOptions:SetClass("collapsed", not expanded)
				end,
			},

			gui.Label{
				classes = {"headingText"},
				text = t,
			},

			headingCountText,
		}

		selectionOptions = gui.Panel{
			classes = {"linkContainer", "collapsed"},

			gui.Label{
				classes = {"link"},
				text = "Select All",
				click = function(element)
					bodyPanel:FireEventTree("selection", "all")
				end,
			},
			gui.Panel{
				classes = {"linkDivider"},
			},
			gui.Label{
				classes = {"link"},
				text = "Clear All",
				click = function(element)
					bodyPanel:FireEventTree("selection", "none")
				end,
			},
		}



		local numChildren = 0

		bodyPanel = gui.Panel{
			classes = {cond(expanded, nil, "collapsed")},
			width = "100%",
			height = "auto",
			flow = "vertical",
			init = function(element)
				local children = {}
				for k,entry in pairs(items) do
					local incore = knownAssetsInCore[k]

					local description = entry.description
					if (description == nil or description == "") and entry.assetType == "Monster" then
						local monster = assets.monsters[k]
						if monster ~= nil then
							description = creature.GetTokenDescription(monster)
						end
					end

					--if entry.hidden == false or incore then
						local op = "create"
						if entry.hidden then
							op = "delete"
						elseif incore then
							op = "modify"
						end

						local panel = gui.Check{
							classes = {"row"}, -- cond(entry.hidden, "silent")},
							text = string.format("%s (%s)", description or "(unnamed)", op),
							value = false,
							width = 340,
							height = 20,
							halign = "left",
							create = createCheck,
							change = changeCheck,
							count = countCheck,
							linger = checkTooltip,
							includedAssets = includedAssets,
							collectManifest = collectManifestCheck,
							selection = selectionCheck,
							data = {
								assetid = k,
								displayName = description or "(unnamed)",
								folderid = entry.folderid,
								ord = string.lower(description or "(unnamed)"),
								type = t,
							},
						}

						children[#children+1] = panel
					--end
				end

				numChildren = #children

				table.sort(children, function(a,b) return (a.data.folderid or "") < (b.data.folderid or "") or (a.data.folderid == b.data.folderid and a.data.ord < b.data.ord) end)
				local currentFolder = nil
				local newChildren = {}
				for _,child in ipairs(children) do
					if t == "Object" and child.data.folderid ~= nil and child.data.folderid ~= currentFolder then
						currentFolder = child.data.folderid

						local folderid = child.data.folderid

						local parentElement = element
						local description = child.data.folderid
						if all[child.data.folderid] ~= nil then
							description = all[child.data.folderid].description
						end

						local triangle = gui.Panel{
							idprefix = "compendium-triangle",
							classes = {"triangle"},
							styles = triangleStyles,

							press = function(element)
								element:SetClass("expanded", not element:HasClass("expanded"))
								for _,child in ipairs(parentElement.children) do
									if child.data.folderid == folderid then
										child:SetClass("collapsed", not child:HasClass("collapsed"))
									end
								end
							end,
						}

						newChildren[#newChildren+1] = gui.Panel{
							flow = "horizontal",
							height = "auto",
							width = "auto",
							halign = "left",
							hmargin = 8,
							triangle,
							gui.Label{
								width = "auto",
								height = 20,
								halign = "left",
								fontSize = 14,
								text = description,
							}
						}

						local selectionOptions = gui.Panel{
							classes = {"linkContainer", "collapsed"},

							data = {
								folderid = folderid,
							},

							gui.Label{
								classes = {"link"},
								text = "Select All",
								click = function(element)
									for _,child in ipairs(parentElement.children) do
										if child.data.folderid == folderid then
											child:FireEventTree("selection", "all")
										end
									end
								end,
							},
							gui.Panel{
								classes = {"linkDivider"},
							},
							gui.Label{
								classes = {"link"},
								text = "Clear All",
								click = function(element)
									for _,child in ipairs(parentElement.children) do
										if child.data.folderid == folderid then
											child:FireEventTree("selection", "none")
										end
									end
								end,
							},
						}

						newChildren[#newChildren+1] = selectionOptions
					end

					if currentFolder ~= nil then
						child:SetClass("collapsed", true)
					end

					newChildren[#newChildren+1] = child
				end

				children = newChildren

				element.children = children

				element:FireEvent("updatecounts")
			end,

			updatecounts = function(element)
				local counts = { total = 0, selected = 0 }
				element:FireEventTree("count", counts)

				headingCountText.text = string.format("(%d/%d)", counts.selected, counts.total)
			end,

		}

		bodyPanel:FireEvent("init")

		resultPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			headingPanel,
			selectionOptions,
			bodyPanel,
		}

		if numChildren == 0 or t == "Folder" or t == "GenericImage" then
			if not dmhub.GetSettingValue("module:exportignoredependencies") then
				resultPanel:SetClassTree("silent", true)
				resultPanel:SetClass("collapsed", true)
			end
		end

		children[#children+1] = resultPanel
		
	end
end


local function CreateCodeModView(modid, modInfo)

	local resultPanel = gui.Check{
		text = string.format("%s", modInfo.name),
		value = false,
		width = 340,
		height = 20,
		halign = "left",
		create = createCheck,
		change = changeCheck,
		count = countCheck,
		linger = checkTooltip,
		includedAssets = includedAssets,
		collectManifest = collectManifestCheck,
		selection = selectionCheck,
		data = {
			assetid = modid,
			displayName = modInfo.name or "(unknown mod)",
			addressable = false,
			type = "code",
		}
	}

	return resultPanel

end



local function CreateModuleDependencyView(moduleInstance)

	local resultPanel = gui.Check{
		text = string.format("%s", moduleInstance.fullid),
		value = false,
		width = 340,
		height = 20,
		halign = "left",
		create = createCheck,
		change = changeCheck,
		count = countCheck,
		linger = checkTooltip,
		includedAssets = includedAssets,
		collectManifest = collectManifestCheck,
		selection = selectionCheck,
		data = {
			assetid = moduleInstance.fullid,
			displayName = moduleInstance.fullid or "(unknown module)",
			addressable = true,
			type = "module",
		}
	}

	return resultPanel

end

local function CreateImageLibraryView(assetid, imageLibrary, coreImageLibrary)
	local coreTable = {}
	if coreImageLibrary ~= nil then
		coreTable = coreImageLibrary.table
	end

	local add = 0
	local modify = 0
	local deletes = 0
	for k,entry in pairs(imageLibrary.table) do
		local incore = coreTable[k] ~= nil
		if (not entry.hidden) or incore then
			if entry.hidden then
				deletes = deletes + 1
			elseif incore then
				modify = modify + 1
			else
				add = add + 1
			end
		end
	end

	if add + modify + deletes == 0 then
		return nil
	end

	local desc = ""
	local sep = ""
	if add ~= 0 then
		desc = string.format("create %d", add)
		sep = ", "
	end

	if modify ~= 0 then
		desc = string.format("%s%smodify %d", desc, sep, modify)
		sep = ", "
	end

	if deletes ~= 0 then
		desc = string.format("%s%sdeletes %d", desc, sep, deletes)
	end

	local name = imageLibrary.name

	local resultPanel = gui.Check{
		text = string.format("%s (%s)", name, desc),
		value = false,
		width = 340,
		height = 20,
		halign = "left",
		create = createCheck,
		change = changeCheck,
		count = countCheck,
		linger = checkTooltip,
		includedAssets = includedAssets,
		selection = selectionCheck,
		collectManifest = collectManifestCheck,
		data = {
			assetid = assetid,
			displayName = name or "(unknown images)",
			addressable = false,
			type = "image library",
		}
	}

	return resultPanel
end

local CreateAssetsHierarchy = function(moduleInstance)
	local resultPanel

	local children = {}

	local knownAssetsInCore = {}

	local coreImageLibraries = nil

	local populateCore = function()
		local numobj = 0
		for _,tableName in ipairs(dmhub.GetTableTypes()) do
			local table = dmhub.GetTable(tableName)
			for k,v in pairs(table) do
				knownAssetsInCore[k] = true
				numobj = numobj + 1
			end
		end

		for k,v in pairs(assets.allAssets) do
			knownAssetsInCore[k] = true
		end

		coreImageLibraries = assets.imageLibrariesTable
	end

	dmhub.RunWithModuleAssets("Core", populateCore)
    dmhub.RunWithModuleAssets("mcdm-drawsteel", populateCore)

	local populateTables = function()

		local compendiumChildren = {}
		for _,tableName in ipairs(dmhub.GetTableTypes()) do
			compendiumChildren[#compendiumChildren+1] = CreateObjectTableView(tableName, knownAssetsInCore)
		end

		if #compendiumChildren > 0 then

			local compendiumPanel

			local triangle = gui.Panel{
				idprefix = "compendium-triangle",
				classes = {"triangle", "expanded"},
				styles = triangleStyles,

				press = function(element)
					element:SetClass("expanded", not element:HasClass("expanded"))
					compendiumPanel:SetClass("collapsed", not element:HasClass("expanded"))
				end,
			}


			local countLabel = gui.Label{
				text = "",
				updatecounts = function(element)
					local counts = { total = 0, selected = 0 }
					compendiumPanel:FireEventTree("count", counts)
					element.text = string.format("(%d/%d)", counts.selected, counts.total)
				end,
			}


			local compendiumLabel = gui.Panel{
				classes = {"row"},
				triangle,
				gui.Label{
					text = "Compendium",
					width = "auto",
					height = "auto",
					bold = true,
				},
				countLabel,
			}

			children[#children+1] = compendiumLabel


			local selectionOptions = gui.Panel{
				classes = {"linkContainer"},

				gui.Label{
					classes = {"link"},
					text = "Select All",
					click = function(element)
						compendiumPanel:FireEventTree("selection", "all")
					end,
				},
				gui.Panel{
					classes = {"linkDivider"},
				},
				gui.Label{
					classes = {"link"},
					text = "Clear All",
					click = function(element)
						compendiumPanel:FireEventTree("selection", "none")
					end,
				},
			}

			table.insert(compendiumChildren, 1, selectionOptions)

			compendiumPanel = gui.Panel{
				width = "100%-16",
				height = "auto",
				halign = "right",
				flow = "vertical",
				hmargin = 4,
				children = compendiumChildren,
			}

			children[#children+1] = compendiumPanel

			countLabel:FireEvent("updatecounts")


		end

		local assetsChildren = {}
		GatherAllAssetsChildren(assetsChildren, knownAssetsInCore)

		if #assetsChildren > 0 then
			local assetsPanel

			local triangle = gui.Panel{
				idprefix = "assets-triangle",
				classes = {"triangle", "expanded"},
				styles = triangleStyles,

				press = function(element)
					element:SetClass("expanded", not element:HasClass("expanded"))
					assetsPanel:SetClass("collapsed", not element:HasClass("expanded"))
				end,
			}

			local countLabel = gui.Label{
				text = "",
				updatecounts = function(element)
					local counts = { total = 0, selected = 0 }
					assetsPanel:FireEventTree("count", counts)
					element.text = string.format("(%d/%d)", counts.selected, counts.total)
				end,
			}

			local assetsLabel = gui.Panel{
				classes = {"row"},
				triangle,
				gui.Label{
					text = "Assets",
					width = "auto",
					height = "auto",
					bold = true,
				},
				countLabel,
			}

			children[#children+1] = assetsLabel


			local selectionOptions = gui.Panel{
				classes = {"linkContainer"},

				gui.Label{
					classes = {"link"},
					text = "Select All",
					click = function(element)
						assetsPanel:FireEventTree("selection", "all")
					end,
				},
				gui.Panel{
					classes = {"linkDivider"},
				},
				gui.Label{
					classes = {"link"},
					text = "Clear All",
					click = function(element)
						assetsPanel:FireEventTree("selection", "none")
					end,
				},
			}

			table.insert(assetsChildren, 1, selectionOptions)


			assetsPanel = gui.Panel{
				width = "100%-16",
				height = "auto",
				flow = "vertical",
				halign = "right",
				hmargin = 4,
				children = assetsChildren,
			}

			children[#children+1] = assetsPanel

			countLabel:FireEvent("updatecounts")
		end


		local imageLibrariesChildren = {}

		local imageLibraries = assets.imageLibrariesTable
		for k,v in pairs(imageLibraries) do
			imageLibrariesChildren[#imageLibrariesChildren+1] = CreateImageLibraryView(k, v, coreImageLibraries[k])
		end


		if #imageLibrariesChildren > 0 then

			local imageLibrariesPanel

			local triangle = gui.Panel{
				idprefix = "assets-triangle",
				classes = {"triangle", "expanded"},
				styles = triangleStyles,

				press = function(element)
					element:SetClass("expanded", not element:HasClass("expanded"))
					imageLibrariesPanel:SetClass("collapsed", not element:HasClass("expanded"))
				end,
			}

			local countLabel = gui.Label{
				text = "",
				updatecounts = function(element)
					local counts = { total = 0, selected = 0 }
					imageLibrariesPanel:FireEventTree("count", counts)
					element.text = string.format("(%d/%d)", counts.selected, counts.total)
				end,
			}

			local imageLibrariesLabel = gui.Panel{
				classes = {"row"},
				triangle,
				gui.Label{
					text = "Image Libraries",
					width = "auto",
					height = "auto",
					bold = true,
				},
				countLabel,
			}

			children[#children+1] = imageLibrariesLabel

			imageLibrariesPanel = gui.Panel{
				width = "100%-16",
				height = "auto",
				halign = "right",
				flow = "vertical",
				hmargin = 4,
				children = imageLibrariesChildren,
			}

			children[#children+1] = imageLibrariesPanel
			countLabel:FireEvent("updatecounts")
		end


		local modulesChildren = {}

		local moduleDependencies = module.GetEligibleDependentModules(moduleInstance.fullid)
		for k,v in pairs(moduleDependencies) do
			modulesChildren[#modulesChildren+1] = CreateModuleDependencyView(v)
		end

		if #modulesChildren > 0 then

			local modulesPanel

			local triangle = gui.Panel{
				idprefix = "module-triangle",
				classes = {"triangle", "expanded"},
				styles = triangleStyles,

				press = function(element)
					element:SetClass("expanded", not element:HasClass("expanded"))
					modulesPanel:SetClass("collapsed", not element:HasClass("expanded"))
				end,
			}

			local countLabel = gui.Label{
				text = "",
				updatecounts = function(element)
					local counts = { total = 0, selected = 0 }
					modulesPanel:FireEventTree("count", counts)
					element.text = string.format("(%d/%d)", counts.selected, counts.total)
				end,
			}

			local modulesLabel = gui.Panel{
				classes = {"row"},
				triangle,
				gui.Label{
					text = "Modules",
					width = "auto",
					height = "auto",
					bold = true,
				},
				countLabel,
			}

			children[#children+1] = modulesLabel

			modulesPanel = gui.Panel{
				width = "100%-16",
				height = "auto",
				halign = "right",
				flow = "vertical",
				hmargin = 4,
				children = modulesChildren,
			}

			children[#children+1] = modulesPanel
			countLabel:FireEvent("updatecounts")

		end

		local codemodsChildren = {}
		local codemodsPresent = code.loadedModsLocalToGame
		for _,modid in ipairs(codemodsPresent) do
			local modInfo = code.GetMod(modid)
			codemodsChildren[#codemodsChildren+1] = CreateCodeModView(modid, modInfo)
			
		end

		dmhub.Debug(string.format("CODEMOD:: %d", #codemodsChildren))

		if #codemodsChildren > 0 then
			local modulesPanel

			local triangle = gui.Panel{
				idprefix = "codemod-triangle",
				classes = {"triangle", "expanded"},
				styles = triangleStyles,

				press = function(element)
					element:SetClass("expanded", not element:HasClass("expanded"))
					modulesPanel:SetClass("collapsed", not element:HasClass("expanded"))
				end,
			}

			local countLabel = gui.Label{
				text = "",
				updatecounts = function(element)
					local counts = { total = 0, selected = 0 }
					modulesPanel:FireEventTree("count", counts)
					element.text = string.format("(%d/%d)", counts.selected, counts.total)
				end,
			}

			local modulesLabel = gui.Panel{
				classes = {"row"},
				triangle,
				gui.Label{
					text = "Code Mods",
					width = "auto",
					height = "auto",
					bold = true,
				},
				countLabel,
			}

			children[#children+1] = modulesLabel

			modulesPanel = gui.Panel{
				width = "100%-16",
				height = "auto",
				halign = "right",
				flow = "vertical",
				hmargin = 4,
				children = codemodsChildren,
			}

			children[#children+1] = modulesPanel
			countLabel:FireEvent("updatecounts")
		end


	end


	dmhub.RunWithModuleAssets("CurrentGame", populateTables)

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		valign = "top",

		children = children,

	}

	return resultPanel
end

local showShareModuleDialog = function(options)
	--nil for a new module.
	local moduleid = options.moduleid

	local isNewModule = options.moduleInfo == nil
	local versionNotesInput
	
	local conditionsAgreed = false

	local npage = 1

	local dialogPanel
	local sharingMap = 'thismap'

	local allAssets = {}

	local includedAssets = {}
	local addressableAssets = {}
	local m_dependencyAssets = {}

	local moduleInstance = options.moduleInfo or module.CreateModule()

	if moduleInstance.publishingProperties.includedAssets ~= nil then
		includedAssets = DeepCopy(moduleInstance.publishingProperties.includedAssets)
	end


	if moduleInstance.authorid == nil or moduleInstance.authorid == "" then
		moduleInstance.authorid = module.savedAuthorid or dmhub.GetDisplayName(dmhub.userid)
	end

	local authorIdsAvailable = {}
	local authorIdsUnavailable = {}

	local moduleIdsAvailable = {}
	local moduleIdsUnavailable = {}

	local contentPanel
	local publishingPanel

	local shareInput
	local sharePanel
	local assetsPanel
	local statusLabel
	local moduleCodePanel

	local footerPanel

	local localCoverArt = nil

	local downloadSizeLabel = gui.Label{
		classes = {"downloadSizeLabel"},
		text = "",
		calculate = function(element)
			local items = DeepCopy(includedAssets)
			for k,_ in pairs(m_dependencyAssets) do
				items[k] = true
			end

			local size = module.CalculateDownloadSizeInKBytes(items)
			element.text = string.format("Module Size: %.1fMB", size/1024)
		end,
	}

	local shareButton
	local backButton
	backButton = gui.PrettyButton{
		text = '<<< Back',
		width = 240,
		height = 70,
		halign = 'left',
		valign = 'center',
		fontSize = 20,

		events = {
			click = function(element)
				if npage == 2 then
					npage = 1
					assetsPanel:SetClass("collapsed", false)
					publishingPanel:SetClass("collapsed", true)
					shareButton:SetClass("hidden", false)
					shareButton.text = "Proceed >>>"
					return
				end

				gui.CloseModal()

				mod.shared.ShowShareDialog()
			end,
		},
	}

	shareButton = gui.PrettyButton{

		text = 'Proceed >>>',
		width = 240,
		height = 70,
		halign = 'right',
		valign = 'center',
		fontSize = 20,

		events = {
			refreshModule = function(element)
				shareButton:SetClass("hidden", npage == 2 and isNewModule and ((not moduleInstance.idvalid) or (not authorIdsAvailable[moduleInstance.authorid])) or (npage == 2 and (not conditionsAgreed)))
			end,

			click = function(element)
				npage = npage+1
				if npage == 2 then
					assetsPanel:SetClass("collapsed", true)
					publishingPanel:SetClass("collapsed", false)
					shareButton.text = cond(isNewModule, "Create Module", "Update Module")
					element:FireEvent("refreshModule")
					return
				end

				shareButton:SetClass('hidden', true)
				statusLabel:SetClass('hidden', false)
				backButton:SetClass('hidden', true)

				contentPanel:SetClass("hidden", true)
				footerPanel:SetClass("hidden", true)

				if localCoverArt ~= nil then
					localCoverArt:Upload()
				end

				local success = function()
					local assetsIncludingDependencies = {}
					for k,_ in pairs(includedAssets) do
						assetsIncludingDependencies[k] = true
					end

					if not dmhub.GetSettingValue("module:exportignoredependencies") then
						for k,_ in pairs(m_dependencyAssets) do
							assetsIncludingDependencies[k] = true
						end
					end

					local notes = nil
					if versionNotesInput ~= nil then
						notes = versionNotesInput.text
					end

					local contentSummary = {}
					dialogPanel:FireEventTree("collectManifest", contentSummary)

					moduleInstance.contentSummary = contentSummary

					moduleInstance:UploadModuleVersion{
						includedAssets = assetsIncludingDependencies,

						notes = notes,

						success = function(guid)
							dmhub.Debug(string.format("Module:: Uploaded to %s", guid))
							moduleInstance.publishingProperties.includedAssets = includedAssets
							moduleInstance:Upload{
								success = function()
									statusLabel.text = "Your module has been uploaded"
									moduleCodePanel:FireEventTree("moduleUploaded")

									moduleInstance:UploadModulePublishProperties{
									}
								end,
								failure = function()
									statusLabel.text = "Uploading the module failed"
								end,
							}
						end,

						failure = function(msg)
							statusLabel.text = string.format("Uploading the module failed: %s", msg)
							dmhub.Debug(string.format("Module:: Upload failed: %s", msg))
						end,
					}
				end

                if dmhub.isAdminAccount then
                    success()
                else
                    moduleInstance:ReserveAuthorID{
                        success = success,

                        failure = function()
                            statusLabel.text = "The author ID you chose is no longer available."
                        end,
                    }
                end

				
			--assets.ShareMap{
			--	allMaps = sharingMap == 'allmaps',
			--	shareName = mapName,
			--	--author = authorName,
			--	description = contentDescription,
			--	error = function(msg)
			--		statusLabel.text = string.format("Error uploading: %s", msg)
			--	end,
			--	complete = function(id)
			--		dmhub.Debug(string.format("Uploaded: %s", id))
			--		statusLabel:SetClass('hidden', true)
			--		sharePanel:SetClass('hidden', false)
			--		shareInput.text = id
			--	end
			--}
			end,
		}
	}

	statusLabel = gui.Label{
		classes = {'status-label', 'hidden'},
		halign = "center",
		valign = "center",
		floating = true,
		text = "Uploading...",
	}

	moduleCodePanel =
		gui.Panel{
			classes = {"collapsed"},
			halign = "center",
			valign = "center",
			flow = "horizontal",
			width = "auto",
			height = "auto",
			y = 30,
			moduleUploaded = function(element)
				element:SetClass("collapsed", false)
			end,

			gui.Label{
				fontSize = 14,
				text = "Module ID:",
				width = 100,
				textAlignment = "left",
			},

			gui.Panel{
				halign = "center",
				width = "auto",
				height = "auto",
				flow = "horizontal",

				click = function(element)
					local tooltip = gui.Tooltip{text = "Copied to Clipboard", valign = "top", borderWidth = 0}(element)
					dmhub.CopyToClipboard(moduleInstance.fullid)
				end,

				gui.Label{
					fontFace = "cambria",
					fontSize = 18,
					width = "auto",
					height = "auto",
					halign = "center",
					valign = "center",
					vmargin = 20,
					moduleUploaded = function(element)
						element.text = moduleInstance.fullid
					end,
				},

				gui.Panel{
					bgimage = "icons/icon_app/icon_app_108.png",
					bgcolor = Styles.textColor,
					styles = {
						{
							classes = "parent:hover",
							brightness = 1.8,
						}
					},

					width = "100% height",
					height = 24,
					valign = "center",
					hmargin = 4,
				},
			}
		}



	shareInput = gui.Input{
		classes = {'share-input'},
		editable = false,
		text = "",
	}

	sharePanel = gui.Panel{
		classes = {'share-panel', 'hidden'},
		gui.Label{
			selfStyle = {
				maxWidth = 300,
				width = 'auto',
				textAlignment = 'center',
				textWrap = true,
				height = 60,
				fontSize = 20,
			},
			text = 'Give others this code to give them access to your map:',
		},
		gui.Panel{
			selfStyle = {
				width = 'auto',
				height = 'auto',
				flow = 'horizontal',
				halign = 'center',
			},
			shareInput,
			gui.Button{
				text = 'Copy',
				selfStyle = {
					hmargin = 4,
					width = 50,
					height = 30,
					fontSize = 14,
				},
				events = {
					click = function(element)
						dmhub.CopyToClipboard(shareInput.text)
					end,
				},
			}
		}
	}


	if not isNewModule then
		versionNotesInput = gui.Input{
			multiline = true,
			text = "",
			placeholderText = string.format("Update notes for version %d", tonumber(moduleInstance.latestVersion)+1),
			characterLimit = 200,
			classes = {'description-input'},
		}
	end

	local previewImage = gui.Panel{
		classes = {"hidden"},
		bgimage = "panels/square.png",
		bgcolor = "white",
		halign = "center",
		valign = "center",
		cornerRadius = 12,
		autosizeimage = true,
		width = "auto",
		height = "auto",
		maxWidth = 200,
		maxHeight = 200,
		minWidth = 20,
		minHeight = 20,
		interactable = false,
	}

	if moduleInstance.coverart ~= nil then
		previewImage.bgimage = moduleInstance.coverart
		previewImage:SetClass("hidden", false)
	end


	local previewImageStatusLabel = gui.Label{
		width = "auto",
		height = "auto",
		maxWidth = 200,
		fontSize = 14,
		text = "",
		vmargin = 8,
		color = "red",
	}

	local rightPublishingPanel

	local pastePreviewImageButton = gui.PrettyButton{
		text = 'Paste Image',
		classes = {cond(dmhub.HaveImageInClipboard(), nil, 'collapsed')},
		width = 160,
		height = 40,
		fontSize = 14,
		halign = "center",
		click = function(element)
			if not dmhub.HaveImageInClipboard() then
				return
			end

			rightPublishingPanel:FireEventTree("dropfiles", {"CLIPBOARD"})
		end,
	}

	rightPublishingPanel = gui.Panel{
		width = "30%",
		height = "auto",
		flow = "vertical",
		valign = "top",
		gui.Panel{
			bgimage = "panels/square.png",
			width = 200,
			height = 200,
			bgcolor = "black",
			flow = "none",
			cornerRadius = 12,
			valign = "top",

			thinkTime = 0.2,
			think = function(element)
				pastePreviewImageButton:SetClass("collapsed", not dmhub.HaveImageInClipboard())
			end,

			previewImage,

			gui.Label{
				interactable = false,
				halign = "center",
				valign = "center",
				textAlignment = "center",
				width = "100%",
				height = 30,
				fontSize = 14,
				bgimage = "panels/square.png",
				bgcolor = "black",
				text = "Upload a preview image",
				styles = {
					{
						color = "#999999ff",
						opacity = 0.9,
					},
					{
						selectors = {"hasimage"},
						hidden = 1,
					},
					{
						selectors = {"parent:hover"},
						color = "white",
						opacity = 0.9,
						hidden = 0,
					}
				},
			},

			dragAndDropExtensions = {".png", ".jpg", ".jpeg", ".webm", ".webp", ".mp4"},

			dropfiles = function(element, files)
				if files[1] ~= nil then
					element:FireEvent("loadfile", files[1])
				end
			end,

			click = function(element)
				dmhub.OpenFileDialog{
					id = "ModuleCover",
					extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4"},
					prompt = "Choose image or video file for module",
					multiFiles = false,
					open = function(path)
						element:FireEvent("loadfile", path)
					end,
				}
			end,

			loadfile = function(element, path)
				localCoverArt = assets:LoadImageOrVideoFileLocally(path)
				if localCoverArt ~= nil then
					element:SetClassTree("hasimage", true)
					previewImage.bgimage = localCoverArt.image
					previewImage:SetClass("hidden", false)

					if localCoverArt.error == nil then
						previewImageStatusLabel.text = ""
						moduleInstance.coverart = localCoverArt.image
					else
						previewImageStatusLabel.text = localCoverArt.error
					end
				else
					previewImage:SetClass("hidden", true)
					previewImageStatusLabel.text = "The file you chose could not be loaded"
				end
			end,
		},

		pastePreviewImageButton,

		previewImageStatusLabel,
	}

    local coverDocumentOptions = {}
    coverDocumentOptions[#coverDocumentOptions+1] = {
        id = "none",
        text = "None",
    }
    local documents = dmhub.GetTable(CustomDocument.tableName) or {}
    for _, doc in pairs(documents) do
        if not doc.hidden then
            coverDocumentOptions[#coverDocumentOptions+1] = {
                id = doc.id,
                text = doc.name,
            }
        end
    end

    local officialModulePanel = nil

    if dmhub.isAdminAccount then
        officialModulePanel = gui.Panel{
            flow = "vertical",
            width = "auto",
            gui.Check{
                text = "Official Module",
                value = moduleInstance.authorid == "codex",
                change = function(element)
                    if element.value then
                        moduleInstance.authorid = "codex"
                    else
                        moduleInstance.authorid = module.savedAuthorid
                    end
                    dialogPanel:FireEventTree("refreshModule")
                end,
            }
        }
    end

	local leftPublishingPanel = gui.Panel{
		flow = "vertical",
		width = "70%",
		height = "auto",
		valign = "top",

        officialModulePanel,

		gui.Panel{
			classes = {'form-entry'},

			gui.Label{
				classes = {'formLabel'},
				text = 'Author Name:',
			},

			gui.Input{
				classes = {cond((not isNewModule) or module.savedAuthorid ~= nil, "collapsed")},
				text = moduleInstance.authorid,
				characterLimit = 12,
				events = {
					change = function(element)
						moduleInstance.authorid = element.text
						element.text = moduleInstance.authorid
						dialogPanel:FireEventTree("refreshModule")
					end
				}
			},

			gui.Label{
				classes = {"formLabel", cond(isNewModule and module.savedAuthorid == nil, "collapsed")},
				text = moduleInstance.authorid,
                refreshModule = function(element)
					element.text = moduleInstance.authorid
                end,
			},
		},


		gui.Label{
			classes = {cond((not isNewModule) or module.savedAuthorid ~= nil, "collapsed")},

			text = "Choose your author name carefully. It will be shared with others when you make a module public online. Once you choose an author name it will be saved to your account and will be used for all modules you create.",

			fontSize = 14,
			halign = "center",
			valign = "top",
			width = "auto",
			height = "auto",
			maxWidth = 500,

		},


		gui.Panel{
			classes = {'form-entry'},

			gui.Label{
				classes = {'formLabel'},
				text = 'Module ID:',
			},

			gui.Input{
				classes = {cond(not isNewModule, "collapsed")},
				text = "",
				placeholderText  = "Enter module id...",
				characterLimit = 18,
				events = {
					change = function(element)
						moduleInstance.moduleid = element.text
						element.text = moduleInstance.moduleid
						dialogPanel:FireEventTree("refreshModule")

						publishingPanel:FireEventTree("updateid")
					end
				}
			},

			gui.Label{
				classes = {"formLabel", cond(isNewModule, "collapsed")},
				text = moduleInstance.moduleid,
			},
		},

		gui.Label{
			fontSize = 14,
			halign = "center",
			valign = "top",
			width = "auto",
			height = "auto",
			maxWidth = 500,
			create = function(element)
				element:FireEvent("refreshModule")
			end,
			refreshModule = function(element)
				if not isNewModule then
					element.text = ""
				elseif moduleInstance.idvalid and authorIdsAvailable[moduleInstance.authorid] and moduleIdsAvailable[moduleInstance.fullid] then
					element.text = "Your module will be published with the unique ID <b>" .. moduleInstance.fullid .. "</b>"
				elseif authorIdsAvailable[moduleInstance.authorid] == nil and authorIdsUnavailable[moduleInstance.authorid] == nil then
					element.text = "Checking availability of author name..."

                    if moduleInstance.authorid == "codex" and dmhub.isAdminAccount then
                        authorIdsAvailable["codex"] = true
                        dialogPanel:FireEventTree("refreshModule")
                    else
                        moduleInstance:CheckAuthorIDAvailable(function(id, val)
                            if val then
                                authorIdsAvailable[id] = true
                            else
                                authorIdsUnavailable[id] = true
                            end

                            dialogPanel:FireEventTree("refreshModule")
                        end)
                    end
				elseif authorIdsUnavailable[moduleInstance.authorid] then
					element.text = "The author name you chose has already been used by another user. Please choose a different name."
				elseif moduleInstance.idvalid and moduleIdsAvailable[moduleInstance.fullid] == nil and moduleIdsUnavailable[moduleInstance.fullid] == nil then
					element.text = "Checking availability of module name..."
					moduleInstance:CheckModuleIDAvailable{
						success = function(id)
							moduleIdsAvailable[id] = true
							dialogPanel:FireEventTree("refreshModule")
						end,
						failure = function(id, msg)
							if id ~= nil then
								moduleIdsUnavailable[id] = true
								dialogPanel:FireEventTree("refreshModule")
							end
						end,
					}
				elseif moduleInstance.idvalid and moduleIdsUnavailable[moduleInstance.fullid] then
					element.text = "You already published a module with this name. Select it to update it with a new version."
				else
					element.text = "Your author name and module id will uniquely identify your module. They may contain the characters a-z, 0-9, and _."
				end
			end,
		},



		gui.Panel{
			classes = {'form-entry'},

			gui.Label{
				classes = {'formLabel'},
				text = 'Module Display Name:',
			},

			gui.Input{
				text = moduleInstance.name,
				characterLimit = 32,
				events = {
					change = function(element)
						moduleInstance.name = element.text
					end,
					updateid = function(element, id)
						if moduleInstance.name == nil or moduleInstance.name == "" then
							local id = moduleInstance.moduleid
							element.text = id
							moduleInstance.name = id

						end
					end,
				}
			}
		},


		gui.Panel{
			classes = {'form-entry'},

			gui.Label{
				classes = {'formLabel'},
				text = 'Keywords:',
			},

			gui.Input{
				text = moduleInstance.keywordsAsJoinedString,
				characterLimit = 64,
				events = {
					change = function(element)
						moduleInstance.keywords = element.text
					end
				}
			}
		},


		gui.Input{
			multiline = true,
			text = moduleInstance.details,
			placeholderText = 'Describe your module...',
			characterLimit = 800,
			classes = {'description-input'},
			events = {
				change = function(element)
					moduleInstance.details = element.text
				end,
			}
		},

		versionNotesInput,

        gui.Panel{
            classes = {'form-entry'},
            gui.Label{
                classes = {'formLabel'},
                text = 'Cover Document:',
            },
            gui.Dropdown{
                idChosen = moduleInstance.coverDocumentId or "none",
                options = coverDocumentOptions,
                hasSearch = true,
                sort = true,
                change = function(element)
                    moduleInstance.coverDocumentId = element.idChosen ~= "none" and element.idChosen or nil
                end,
            },
        },


		gui.Panel{
			classes = {'form-entry'},

			gui.Label{
				classes = {'formLabel'},
				text = 'Listing Status:',
			},

			gui.Dropdown{
				options = {
					{
						id = "unlisted",
						text  = "Private",
					},
					{
						id = "public",
						text = "Public"
					},
					{
						id = "premium",
						text = "Premium",
						hidden = not dmhub.isAdminAccount,
					}
				},
				idChosen = cond(moduleInstance.published, "public", "unlisted"),
				events = {
					change = function(element)
						moduleInstance.published = element.idChosen == "public"
						moduleInstance.premium = element.idChosen == "premium"
						dialogPanel:FireEventTree("refreshModule")
					end
				}
			}
		},

		gui.Label{
			fontSize = 14,
			maxWidth = 600,
			width = "auto",
			height = "auto",
			valign = "top",
			refreshModule = function(element)
				if moduleInstance.published then
					element.text = "Others will be able to search for and install your module."
				elseif moduleInstance.premium then
					element.text = "Your module will be available in the store. It must have a corresponding store entry to unlock it."
				else
					element.text = "Your module can only be installed by those who you share its ID with. Choose an ID that cannot be guessed to ensure this module remains private."
				end
			end,
		},

		gui.Label{
			fontSize = 14,
			width = "auto",
			height = "auto",
			maxWidth = 600,
			valign = "top",
			vmargin = 8,
			text = "The DMHub module system is for distributing content that you are legally entitled to share. You retain ownership of any content you have created, but by sharing it in a module you grant permission for other DMHub users to use and share it within DMHub.",
		},

		gui.Check{
			valign = "top",
			halign = "left",
			value = conditionsAgreed,
			text = "I agree to these terms",
			width = 400,
			fontSize = 14,
			change = function(element)
				conditionsAgreed = element.value
				shareButton:FireEvent("refreshModule")
			end,
		},

		gui.Check{
			classes = {cond(moduleInstance.published == false, "collapsed")},
			valign = "top",
			halign = "left",
			value = moduleInstance.dmhubCanUse,
			text = "Submit to be included with DMHub",
			hover = gui.Tooltip("Check this if you think DMHub would be improved if this module was included as part of DMHub by default. By checking this you agree that the DMHub developers may use the contents of this module however they please. You must have created the contents of the module yourself and be willing for DMHub's developers to include it in DMHub."),
			change = function(element)
				moduleInstance.dmhubCanUse = element.value
			end,
			refreshModule = function(element)
				element:SetClass("collapsed", not moduleInstance.published)
			end,
		},
	}

	publishingPanel = gui.Panel{
		classes = {"collapsed"},
		width = "100%",
		height = "auto",
		flow = "horizontal",
		valign = "top",
		leftPublishingPanel,
		rightPublishingPanel,
	}


	local mapFolderHierarchy

	local folderOptions = gui.Panel{
		classes = {"linkContainer"},

		gui.Label{
			classes = {"link"},
			text = "All Maps",
			click = function(element)
				mapFolderHierarchy:FireEventTree("selection", "all")
			end,
		},
		gui.Panel{
			classes = {"linkDivider"},
		},
		gui.Label{
			classes = {"link"},
			text = "Current Map",
			click = function(element)
				mapFolderHierarchy:FireEventTree("selection", "this")
			end,
		},
		gui.Panel{
			classes = {"linkDivider"},
		},
		gui.Label{
			classes = {"link"},
			text = "No Maps",
			click = function(element)
				mapFolderHierarchy:FireEventTree("selection", "none")
			end,
		},
	}

	mapFolderHierarchy = CreateMapFolderPanel(game.rootMapFolder, true, folderOptions)


	assetsPanel = gui.Panel{
		height = "auto",
		width = 300,
		halign = "center",
		flow = "vertical",
		valign = "top",

		styles = {
			{
				classes = {"row"},
				height = 24,
				width = "100%",
				halign = "left",
				valign = "top",
				flow = "horizontal",
				bgcolor = "#00000044",
			},
			{
				classes = {"row", "map"},
				height = "auto",
				minHeight = 24,
			},
			{
				classes = {"row", "hover"},
				transitionTime = 0.1,
				bgcolor = "#88000077",
			},
			{
				classes = {"row", "dragging"},
				bgcolor = "#88000077",
			},
			{
				classes = {"label"},
				halign = "left",
				width = "auto",
				height = "auto",
				fontSize = 16,
				margin = 4,
				color = "#aaaaaa",
			},
			{
				classes = {"checkbox-label"},
				width = "auto",
				maxWidth = 310,
				textOverflow = "truncate",
				textWrap = false,
			},
		},





		gui.Panel{
			classes = {"linkContainer"},

			gui.Label{
				classes = {"link"},
				text = "Select All",
				click = function(element)
					assetsPanel:FireEventTree("selection", "all")
				end,
			},
			gui.Panel{
				classes = {"linkDivider"},
			},
			gui.Label{
				classes = {"link"},
				text = "Clear All",
				click = function(element)
					assetsPanel:FireEventTree("selection", "none")
				end,
			},
		},

		mapFolderHierarchy,
		CreateCharacterSelectionPanel(),
		CreateAssetsHierarchy(moduleInstance),

	}


	local createModuleLabel = gui.Label{
		fontSize = 24,
		width = "auto",
		height = "auto",
		halign = "center",
		valign = "top",
		text = cond(isNewModule, "Create a Module", "Update Module"),
	}


	footerPanel = gui.Panel{
		classes = {'footer-panel'},
		downloadSizeLabel,
	}

	contentPanel = gui.Panel{
		classes = {'content-panel'},
		vscroll = true,

		createModuleLabel,

		publishingPanel,

		assetsPanel,
	}

	local m_dependenciesDirty = true

	local m_dependencySearcher = nil



	dialogPanel = gui.Panel{
		id = 'ShareDialog',
		classes = {"framedPanel"},
		styles = {
			Styles.Default,
			Styles.Panel,

			{
				selectors = {"framedPanel"},
				width = 1024,
				height = 980,
			},

			{
				selectors = {'content-panel'},
				width = '90%',
				height = '78%',
				valign = 'top',
				halign = 'center',
				vmargin = 16,
				flow = 'vertical',
			},
			{
				selectors = {'footer-panel'},
				width = '90%',
				height = '5%',
				valign = 'top',
				halign = 'center',
				vmargin = 6,
				flow = 'vertical',
			},
			{
				selectors = {'form-entry'},
				width = '60%',
				height = 40,
				valign = 'top',
				halign = 'center',
				flow = 'horizontal',
				vmargin = 8,
			},
			{
				selectors = {'formLabel'},
				width = '40%',
				height = 40,
				fontSize = 14,
				color = 'white',
			},
			{
				selectors = {'dropdown'},
				width = 200,
				height = 40,
				fontSize = 18,
				color = 'white',
			},
			{
				selectors = {'dropdown-option'},
				priority = 20,
				width = 200,
				height = 40,
				fontSize = 18,
				color = 'white',
			},
			{
				selectors = {'input'},
				fontSize = 18,
				width = 200,
				height = 24,
			},
			{
				selectors = {'share-input'},
				textAlignment = 'left',
				width = 400,
				height = 24,
				fontSize = 20,
			},
			{
				selectors = {'description-input'},
				textAlignment = 'topleft',
				valign = 'top',
				width = '60%',
				height = 80,
				vmargin = 8,
			},
			{
				selectors = {'status-label'},
				fontSize = 20,
				width = 'auto',
				height = 'auto',
				valign = 'center',
				halign = 'center',
				maxWidth = 400,
				color = 'white',
			},
			{
				selectors = {'share-panel'},
				flow = 'vertical',
				height = 'auto',
				width = '100%',
			},
			{
				selectors = {'link'},
				fontSize = 11,
				width = "auto",
				height = "auto",
			},
			{
				selectors = {'linkContainer'},
				width = "auto",
				height = "auto",
				halign = "left",
				flow = "horizontal",
				vmargin = 0,
			},
			{
				selectors = {'linkDivider'},
				width = 1,
				height = 12,
				bgimage = "panels/square.png",
				bgcolor = "white",
				valign = "center",
				hmargin = 4,
			},
			{
				classes = {"downloadSizeLabel"},
				fontSize = 14,
				width = "auto",
				height = "auto",
				halign = "center",
			},
		},

		thinkTime = 0.1,

		think = function(element)
			if m_dependenciesDirty then
				local count = 0
				for k,item in pairs(addressableAssets) do
					count = count+1
				end
				dmhub.Debug(string.format("ASSETS:: HAVE %d", count))
				if m_dependencySearcher == nil then
					m_dependencySearcher = module.CreateDependencySearcher(allAssets)
				end

				m_dependencyAssets = m_dependencySearcher:Search(addressableAssets)
				m_dependenciesDirty = false

				dialogPanel:FireEventTree("includedAssets", includedAssets, m_dependencyAssets, false)
				element:FireEventTree("updatecounts")


				downloadSizeLabel:FireEvent("calculate")
			end
		end,

		createasset = function(element, check)
			dmhub.Debug(string.format("CREATE ASSET:: %s", check.data.assetid))
			if check.data.addressable ~= false then
				allAssets[check.data.assetid] = {
					check = check
				}

				check.data.allAssets = allAssets
			end
		end,

		selectasset = function(element, check)
			includedAssets[check.data.assetid] = cond(check.value, true, nil)
			if check.data.addressable ~= false then
				addressableAssets[check.data.assetid] = cond(check.value, true, nil)
			end

			local naddress = 0
			local nall = 0
			for _,v in pairs(addressableAssets) do
				naddress = naddress+1
			end

			for _,v in pairs(allAssets) do
				nall = nall+1
			end

			m_dependenciesDirty = true
		end,

		gui.Panel{
			width = "100%",
			height = "100%",
			flow = "vertical",
			contentPanel,
			footerPanel,
		},


		gui.Panel{

			selfStyle = {
				width = '60%',
				height = 100,
				valign = 'bottom',
				halign = 'center',
			},

			backButton,
			shareButton,
			sharePanel,
		},

		statusLabel,
		moduleCodePanel,

		gui.CloseButton{
			halign = "right",
			valign = "top",
			floating = true,
			escapeActivates = true,
			escapePriority = EscapePriority.EXIT_DIALOG,
			events = {
				click = function(element)
					gui.CloseModal()
				end,
			},
		},

	}


	gui.ShowModal(dialogPanel, {nofade = true})
	dialogPanel:FireEventTree("refreshModule")

	if not isNewModule then
		dialogPanel:FireEventTree("includedAssets", includedAssets, m_dependencyAssets, true)
	end
end

mod.shared.ShowShareDialog = function()

	local dialogPanel
	local shareButton
	local statusLabel

	local downloadedModulesById = {}

	local moduleOptions = {}



	local modulesIncluded = {}
	for _,info in ipairs(module.GetModulesPublishedFromThisGame()) do
		moduleOptions[#moduleOptions+1] = {
			id = info.id,
			text = info.id,
			mtime = info.mtime,
		}

		modulesIncluded[info.id] = true

	end

	for _,key in ipairs(module.GetOurPublishedModules()) do
		local moduleInfo = module.GetModule(key)
		if moduleInfo ~= nil and (not modulesIncluded[key]) then
			moduleOptions[#moduleOptions+1] = {
				id = key,
				text = key,
			}
		end
		modulesIncluded[key] = true
	end

	moduleOptions[#moduleOptions+1] = {
		id = "new",
		text = "Create a New Module",
	}

	--try to work out which module to default to. Prefer to whichever one we published last time.
	local defaultModuleSelected = dmhub.GetSettingValue("module:lastpublished")
	local foundModule = false
	for _,info in ipairs(moduleOptions) do
		if defaultModuleSelected == info.id then
			foundModule = true
		end
	end

	if foundModule == false then
		defaultModuleSelected = "new"
	end

	local infoDisplay = gui.Label{
		fontSize = 16,
		textAlignment = "center",
		width = "60%",
		height = "auto",
		halign = "center",
		valign = "top",
		wrap = true,
		text = "",
		display = function(element, moduleInfo)
			if moduleInfo == nil then
				element.text = ""
				return
			end

			element.text = string.format("%s by %s", moduleInfo.name or moduleInfo.moduleid, moduleInfo.authorid)
		end,
	}

	local GetModuleInfo = function(dropdown)
		dmhub.SetSettingValue("module:lastpublished", dropdown.idChosen)
		infoDisplay:FireEvent("display", downloadedModulesById[dropdown.idChosen])
		if dropdown.idChosen ~= "new" and downloadedModulesById[dropdown.idChosen] == nil then

			local id = dropdown.idChosen
			module.DownloadModuleInfo{
				moduleid = dropdown.idChosen,
				success = function(info)
					if downloadedModulesById[id] == nil then
						downloadedModulesById[id] = info

						if id == dropdown.idChosen then
							infoDisplay:FireEvent("display", info)
						end
					end
				end,
			}
		end
	end


	moduleSelectionDropdown = gui.Dropdown{
		options = moduleOptions,
		idChosen = defaultModuleSelected,
		create = GetModuleInfo,
		change = GetModuleInfo,
		width = 200,
	}

	local moduleSelection = gui.Panel{
		classes = {"formPanel"},
		valign = "top",
		width = "40%",
		gui.Label{
			classes = {"formLabel"},
			text = "Module:",
		},

		moduleSelectionDropdown,
	}

	shareButton = gui.PrettyButton{
		text = 'Proceed >>>',
		width = 240,
		height = 70,
		halign = 'right',
		valign = 'center',
		fontSize = 20,
		floating = true,
		events = {
			click = function(element)
				if moduleSelectionDropdown.idChosen ~= "new" and downloadedModulesById[moduleSelectionDropdown.idChosen] == nil then
					--didn't get to download the module yet. Should be here soon? Fire a change event to try to force a redownload.
					moduleSelectionDropdown:FireEvent("change")
					return
				end

				statusLabel.text = "Scanning your game for content. This may take a few moments..."
				shareButton:SetClass("hidden", true)
				moduleSelection:SetClass("hidden", true)

				dmhub.Schedule(0.1,
					function()
						gui.CloseModal()

						showShareModuleDialog{
							moduleid = cond(moduleSelectionDropdown.idChosen ~= "new", moduleSelectionDropdown.idChosen),
							moduleInfo = downloadedModulesById[moduleSelectionDropdown.idChosen],
						}
					end
				)
			end,
		}
	}

	statusLabel = gui.Label{
		fontSize = 16,
		width = "60%",
		height = "auto",
		valign = "center",
		wrap = true,
		text = "Create a module from this game that can be imported into other games. On the next screen you will be able to pick which aspects of this game you want to put in your module. Anything from a single spell, item, or map, to the entire contents of the game.",
	}


	local displayPanel = gui.Panel{
		flow = "vertical",
		halign = "center",
		valign = "center",
		width = 900,
		height = 700,

		moduleSelection,
		infoDisplay,
		statusLabel,
	}

	dialogPanel = gui.Panel{
		id = 'ShareDialog',
		classes = {"framedPanel"},
		styles = {
			Styles.Default,
			Styles.Panel,
			Styles.Form,

			{
				selectors = {"framedPanel"},
				width = 1024,
				height = 900,
			},
		},

		flow = "vertical",

		displayPanel,


		gui.Panel{

			floating = true,

			selfStyle = {
				width = '60%',
				height = 100,
				valign = 'bottom',
				halign = 'center',
			},

			shareButton,
		},


		gui.CloseButton{
			halign = "right",
			valign = "top",
			floating = true,
			escapeActivates = true,
			escapePriority = EscapePriority.EXIT_DIALOG,
			events = {
				click = function(element)
					gui.CloseModal()
				end,
			},
		},

	}

	gui.ShowModal(dialogPanel, {nofade = true})
	dialogPanel:FireEventTree("refreshModule", {nofade = true})

end


mod.shared.ShowDownloadShareDialog = function()
	local m_moduleIndex
	local m_displayedItemIds = {}

	local moduleGrid
	local moduleGridContainer
	local moduleDetailedDisplay

	local statusLabel = gui.Label{
		classes = {"status-label"},
		text = "Loading module data...",
	}

	local searchFailedLabel = gui.Label{
		classes = {"status-label", "collapsed"},
		text = "No matching modules found",
	}


	local CreateModuleDisplaySlot = function()
		local resultPanel
		local moduleHeading = gui.Label{
			classes = {"moduleHeading"},
			color = Styles.textColor,
		}

		local newBadge = gui.Panel{
			bgimage = "ui-icons/newbadge.png",
			bgcolor = "white",
			x = -8,
			y = -8,
			width = 32,
			height = 32,
			floating = true,
			halign = "left",
			valign = "top",
		}

		local installCheck = gui.Panel{
			classes = {"installCheck"},
		}

		local headingAndInstall = gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "top",
			moduleHeading,
			installCheck,
		}

		local headingPanel = gui.Panel{
			flow = "vertical",
			halign = "left",
			valign = "top",
			width = "auto",
			height = "auto",
			hmargin = 4,
			headingAndInstall,
			gui.Panel{
				width = 240,
				height = 1,
				vmargin = 1,
				bgcolor = Styles.textColor,
				bgimage = "panels/square.png",
				halign = "left",
			}
		}

		local authorLabel = gui.Label{
			classes = {"moduleAuthor"},
			valign = "bottom",
		}

		local iconContainer = gui.Panel{
			classes = {"framedPanel"},
			width = 96,
			height = 96,
			hmargin = 4,
			vmargin = 8,
			data = {
				imageid = nil,
			},
			setimage = function(element, imageid)
				if element.data.imageid == imageid then
					return
				end
				element.data.imageid = imageid
				element.children = {
					gui.Panel{
						classes = {"moduleIcon"},
						autosizeimage = true,
						bgimageStreamed = imageid,
					}
				}
			end,
		}

		local detailsLabel = gui.Label{
			classes = {"moduleDetails"},
		}

		local detailsPanel = gui.Panel{
			flow = "horizontal",
			halign = "left",
			valign = "top",
			width = "auto",
			height = "auto",
			iconContainer,
			detailsLabel,
		}

		local publishedLabel = gui.Label{
			classes = {"publishedLabel"},
			floating = true,
			text = "Published",
		}

		local installCountLabel = gui.Label{
			classes = {"installCountLabel"},
			text = "0",
		}

		local installCountIcon = gui.Panel{
			classes = {"installCountIcon"},
			hover = function(element)
				gui.Tooltip(string.format("This module has been installed by %s users.", installCountLabel.text))(element)
			end,
		}

		local installCountPanel = gui.Panel{
			classes = {"installCountPanel"},
			valign = "bottom",
			halign = "right",
			installCountLabel,
			installCountIcon,
		}


		local upvoteCountLabel = gui.Label{
			classes = {"installCountLabel"},
			text = "0",
		}

		local upvoteCountIcon = gui.Panel{
			classes = {"upvoteCountIcon"},
			valign = "center",
			halign = "right",
			bgimage = "icons/icon_arrow/icon_arrow_29.png",
		}

		local upvoteCountPanel = gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = "auto",
			valign = "top",
			halign = "right",
			upvoteCountLabel,
			upvoteCountIcon,
		}

		local statsPanel = gui.Panel{
			flow = "vertical",
			floating = true,
			halign = "right",
			valign = "center",
			width = "auto",
			height = "100%",

			upvoteCountPanel,

			installCountPanel,
			authorLabel,
		}

		resultPanel = gui.Panel{
			classes = {"framedPanel", "moduleItem", "collapsed"},
			headingPanel,
			detailsPanel,
			publishedLabel,

			statsPanel,

			newBadge,

			data = {
				moduleInfo = nil,
			},

			press = function(element)
				moduleGridContainer:SetClass("collapsed", true)
				moduleDetailedDisplay:SetClass("collapsed", false)
				moduleDetailedDisplay:FireEvent("displayModule", element.data.moduleInfo)
			end,

			setmodule = function(element, moduleInfo)
				element.data.moduleInfo = moduleInfo

				if moduleInfo == nil then
					element:SetClass("collapsed", true)
					return
				end

				if moduleInfo.coverart ~= nil then
					iconContainer:FireEvent("setimage", moduleInfo.coverart)
				else
					iconContainer:FireEvent("setimage", "panels/logo/DMHubLogo.png")
				end

				element:SetClass("collapsed", false)
				moduleHeading.text = moduleInfo.name or moduleInfo.fullid
				authorLabel.text = string.format("by %s", moduleInfo.authorid)
				detailsLabel.text = moduleInfo.details

				element:SetClassTree("published", cond(moduleInfo.publishedFromThisGame, true, false))
				element:SetClassTree("installed", cond(moduleInfo.installedVersion, true, false))
				element:SetClassTree("loaded", cond(moduleInfo.loadedVersion, true, false))

				installCountPanel:SetClass("hidden", true)

				newBadge:SetClass("hidden", true)

				moduleInfo:QueryStats(function(modid, stats)
					if element.valid and modid == moduleInfo.fullid then
						local versions = moduleInfo.versions

						local moduleAge = math.max(1, TimestampAgeInSeconds(versions[1].createTimestamp))

						if moduleAge < 24*60*60*3 then
							--modules less than 3 days old get a new badge.
							newBadge:SetClass("hidden", false)
						end

						installCountPanel:SetClass("hidden", false)
						installCountLabel.text = string.format("%d", stats.installs)
						upvoteCountLabel.text = string.format("%d", stats.votes+1)
						upvoteCountIcon:SetClass("upvoted", moduleInfo.vote > 0)
					end
				end)
			end,

			refreshModule = function(element)
				element:FireEvent("setmodule", element.data.moduleInfo)
			end,
		}

		return resultPanel
	end

	local pageLeft
	local pageRight
	local pageLabel

	local nrows = 5
	local ncols = 4

	local numPages = 0
	local pageNum = 1

	local gridItems = {}
	for i=1,nrows*ncols do
		gridItems[#gridItems+1] = CreateModuleDisplaySlot()
	end

	local SetDisplayedModules = function(items)
		m_displayedItemIds = items

		numPages = math.ceil(#items / (nrows*ncols))

		if pageNum > numPages then
			pageNum = numPages
		end

		if pageNum < 1 then
			pageNum = 1
		end

		dmhub.Debug(string.format("MODULES:: GET %d", #items))

		for i,gridItem in ipairs(gridItems) do
			gridItem:FireEvent("setmodule", m_displayedItemIds[i + (pageNum-1) * (nrows*ncols)])
		end

		pageLabel.text = string.format("Page %d/%d", pageNum, numPages)
		pageLeft:SetClass("hidden", pageNum == 1)
		pageRight:SetClass("hidden", pageNum == numPages)
	end

	local m_tabSelected = "hot"
	local m_latestSearch = nil

	local ShowSearch = function(search)
		if m_moduleIndex == nil then
			return
		end

		m_latestSearch = search
			index = m_tabSelected,

		m_moduleIndex:Search{
			text = search,
			maxResults = 10000,
			success = function(result)
				if result.search ~= m_latestSearch then
					return
				end

				local items = {}
				
				for _,item in ipairs(result.items) do
					local versions = item.versions
					local stats = item.cachedStats
					if stats == nil then
						stats = {votes = 0, installs = 0}
					end
					local moduleAge = math.max(1, TimestampAgeInSeconds(versions[1].createTimestamp))
					local latestVersionAge = math.max(1, TimestampAgeInSeconds(versions[#versions].createTimestamp))

					local score
					
					if m_tabSelected == "hot" then
						score = (20 + stats.votes*20 + stats.installs)/moduleAge + 0.4*(20 + stats.votes*20 + stats.installs)/latestVersionAge
					elseif m_tabSelected == "new" then
						score = -moduleAge
					else
						score = stats.votes + stats.installs/10000
					end

					items[#items+1] = {
						module = item,
						stats = item.cachedStats,
						age = moduleAge,
						update = latestVersionAge,
						score = score
					}
				end

				table.sort(items, function(a,b)
					return a.score > b.score
				end)

				local sortedModules = {}
				for _,entry in ipairs(items) do
					sortedModules[#sortedModules+1] = entry.module
				end

				SetDisplayedModules(sortedModules)

				searchFailedLabel:SetClass("collapsed", true)

				if #result.items == 0 then
					
					searchFailedLabel:SetClass("collapsed", false)
					moduleGridContainer:SetClass("collapsed", true)
					moduleDetailedDisplay:SetClass("collapsed", true)
				elseif result.mono then
					gridItems[1]:FireEvent("press")
				else
					moduleGridContainer:SetClass("collapsed", false)
					moduleDetailedDisplay:SetClass("collapsed", true)
				end
			end,
			failure = function()
			end,
		}
	end

	local detailedDisplayTitle = gui.Label{
		classes = {"titleLabel"},
	}
	local detailedDisplayAuthor = gui.Label{
		classes = {"authorLabel", "link"},
		click = function(element)
			ShowSearch(element.data.search)

		end,
		data = {
			search = "",
		}
	}
	local detailedDisplayID = gui.Label{
		classes = {"idLabel"},

		data = {
			id = "",
		},

		press = function(element)
			local tooltip = gui.Tooltip{text = tr("Copied to Clipboard"), valign = "top", borderWidth = 0}(element)
			dmhub.CopyToClipboard(element.data.id)
		end,

		gui.Panel{
			bgimage = "icons/icon_app/icon_app_108.png",
			bgcolor = Styles.textColor,
			x = 20,
			width = 16,
			height = 16,
			valign = "center",
			halign = "right",
			styles = {
				{
					selectors = {"parent:hover"},
					brightness = 1.5,
				}
			}
		},

	}
	local detailedDisplayBody = gui.Label{
		classes = {"bodyLabel"},
	}

	local detailedDisplayImage = gui.Panel{
		valign = "top",
		autosizeimage = true,
		bgcolor = "white",
		width = "auto",
		height = "auto",
		maxWidth = 400,
		maxHeight = 400,
		minWidth = 50,
		minHeight = 50,
	}

	local detailedDisplayPanel = gui.Panel{
		flow = "horizontal",
		width = "auto",
		height = "auto",

		valign = "top",
		halign = "left",

		detailedDisplayImage,
		detailedDisplayBody,
	}


	local installCountLabel = gui.Label{
		fontFace = "Inter",
		fontSize = 24,
		color = "white",
		width = "auto",
		height = "auto",
		hmargin = 6,
		text = "0",
	}

	local installCountIcon = gui.Panel{
		width = 40,
		height = 40,
		halign = "right",
		bgcolor = "white",
		bgimage = "ui-icons/downloadicon.png",
		hover = function(element)
			gui.Tooltip(string.format("This module has been installed by %s users.", installCountLabel.text))(element)
		end,
	}

	local installCountPanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "horizontal",
		halign = "right",
		installCountLabel,
		installCountIcon,
	}

	local upvoteCountLabel = gui.Label{
		fontFace = "Inter",
		fontSize = 24,
		color = "white",
		width = "auto",
		height = "auto",
		hmargin = 6,
		text = "0",
	}

	local upvoteCountIcon = gui.Panel{
		width = 40,
		height = 40,
		halign = "right",
		styles = {
			{
				bgcolor = "white",
				bgimage = "ui-icons/heartunclicked.png",
			},
			{
				selectors = {"upvoted"},
				bgimage = "ui-icons/heartclicked.png",
			},
			{
				selectors = {"hover"},
				brightness = 2,
			},
		},
		linger = function(element)
			gui.Tooltip(string.format("%s Likes", upvoteCountLabel.text))(element)
		end,

		refreshUpvote = function(element)
			local moduleInfo = moduleDetailedDisplay.data.moduleInfo
			element:SetClass("upvoted", moduleInfo.vote > 0)
		end,

		press = function(element)
			local moduleInfo = moduleDetailedDisplay.data.moduleInfo
			if moduleInfo.ourModule then
				return
			end

			moduleInfo.vote = cond(moduleInfo.vote == 0, 1, 0)
			element:FireEvent("refreshUpvote")
			moduleDetailedDisplay:FireEvent("refreshModuleStats")
		end,
	}

	local upvoteCountPanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "horizontal",
		halign = "right",
		vmargin = 4,
		upvoteCountLabel,
		upvoteCountIcon,
	}

	local statsPanel = gui.Panel{
		classes = {"hidden"},
		floating = true,
		halign = "right",
		valign = "top",
		flow = "vertical",
		width = "auto",
		height = "auto",
		hmargin = 26,

		installCountPanel,
		upvoteCountPanel,
	}

	local m_moduleErrors = {}


	local m_installing = false

	local installLabel
	local uninstallButton

	local installButton =
		gui.PrettyButton{
			styles = {
				{
					selectors = {"label"},
					halign = "center",
					valign = "center",
				},
			},
			halign = "right",
			valign = "bottom",
			width = 180,
			height = 52,
			fontSize = 24,
			text = "Install",
			click = function(element)
				m_installing = moduleDetailedDisplay.data.moduleInfo.fullid
				local modInstalling = m_installing
                local coverdocid = moduleDetailedDisplay.data.moduleInfo.coverDocumentId
				moduleDetailedDisplay.data.moduleInfo:Install{
					success = function()
						m_installing = false
						GameHud.instance.dialog.sheet:FireEventTree("moduleInstalled")

                                print("DOC:: COVERDOC:", coverdocid)
                        if coverdocid ~= nil then

                            local nattempts = 0
                            local showdoc
                            showdoc = function()
                                    local doc = dmhub.GetTable(CustomDocument.tableName)[coverdocid]
                                    print("DOC:: SEARCH FOR", coverdocid, doc)
                                    if doc ~= nil then
                                        gui.CloseModal()
                                        print("DOC:: SHOW")
                                        doc:ShowDocument()
                                        return
                                    end

                                    if nattempts < 64 then
                                        nattempts = nattempts+1
                                        dmhub.Schedule(0.2, showdoc)
                                    else
                                        print("DOC:: GIVE UP")
                                    end
                                end
                            showdoc()
                        end
					end,
					error = function(message)
						m_moduleErrors[modInstalling] = message
					end,
				}

				installLabel:FireEvent("think")
			end,
		}
	
	uninstallButton = gui.Panel{
		classes = {"collapsed"},
		width = 16,
		height = 16,
		bgimage = "icons/icon_tool/icon_tool_44.png",
		styles = {
			{
				bgcolor = "white",
			},
			{
				selectors = {"hover"},
				bgcolor = "red",
			}
		},

		press = function(element)
			gui.ModalMessage{
				title = "Uninstall Module",
				message = "Uninstalling this module will remove all its compendium content from your game. Any maps or characters imported will remain and have to be manually deleted. If any compendium content from this module is being used in your game, uninstalling the module may result in instability.",
				options = {
					{
						text = "Uninstall",
						execute = function()
							local mod = moduleDetailedDisplay.data.moduleInfo
							mod:Uninstall{}
						end,
					},
					{
						text = "Cancel",
						execute = function()
						end,
					},
				}
			}
		end,
	}

	installLabel =
		gui.Label{
			text = "",
			halign = "right",
			valign = "bottom",
			fontSize = 16,
			thinkTime = 0.1,
			newModule = function(element)
				element:FireEvent("think")
			end,
			think = function(element)
				local mod = moduleDetailedDisplay.data.moduleInfo
				if mod.fullid == m_installing then
					installButton:SetClass("collapsed", true)
					element.text = "Installing..."
					uninstallButton:SetClass("collapsed", true)
					if m_moduleErrors[m_installing] then
						element.text = m_moduleErrors[m_installing]
					end
					return;
				end

				if mod.publishedFromThisGame then
					installButton:SetClass("collapsed", true)
					element.text = "This module is published from this game."
					uninstallButton:SetClass("collapsed", true)
					return
				end

				if mod.premium and (not mod.owned) then
					installButton:SetClass("collapsed", true)
					element.text = "This module is a premium module and must be purchased in the store"
					uninstallButton:SetClass("collapsed", true)
					return
				end

				if mod.installedVersion ~= mod.latestVersion and mod.installationBandwidthInKBytes > dmhub.uploadQuotaRemaining/1024 then
					installButton:SetClass("collapsed", true)
					element.text = "Not enough bandwidth to install"
					uninstallButton:SetClass("collapsed", true)
					return
				end

				if mod.installedVersion == nil then
					installButton:SetClass("collapsed", false)
					uninstallButton:SetClass("collapsed", true)
					installButton.text = "Install"
					element.text = ""
					return
				end

				if mod.installedVersion ~= mod.latestVersion then
					uninstallButton:SetClass("collapsed", true)
					installButton:SetClass("collapsed", false)
					installButton.text = "Update"
					element.text = string.format("Version %s is installed", mod.installedVersion, mod.latestVersion)
				else
					installButton:SetClass("collapsed", true)
					uninstallButton:SetClass("collapsed", false)
					element.text = "Installed"
				end
				

			end,
		}
	
	local bandwidthLabel = gui.Label{
		width = "auto",
		height = "auto",
		halign = "left",
		valign = "bottom",
		fontSize = 14,

		thinkTime = 0.5,

		think = function(element)
			element:FireEvent("newModule")
		end,

		newModule = function(element)
			local mod = moduleDetailedDisplay.data.moduleInfo
			local operation = cond(mod.installedVersion ~= nil, "update", "install")
			if mod.installedVersion == mod.latestVersion or mod.publishedFromThisGame then
				element.text = ""
			elseif mod.installationBandwidthInKBytes == 0 then
				element.text = string.format("This module requires no bandwidth to %s", operation)
			else
				element.text = string.format("Bandwidth required to %s module: %.1fMB\nBandwidth remaining this month: %.1fMB", operation, mod.installationBandwidthInKBytes/1024, dmhub.uploadQuotaRemaining/(1024*1024))

			end
		end,
	}

	local bandwidthPanel = gui.Panel{
		floating = true,
		width = "auto",
		height = "auto",
		flow = "vertical",
		halign = "left",
		valign = "bottom",
		bandwidthLabel,
		gui.Label{
			text = "Support us on Patreon for more bandwidth",
			classes = {"link"},
			fontSize = 14,
			click = function(element)
				dmhub.OpenRegisteredURL("Patreon")
			end,
		}
	}

	local installPanel = gui.Panel{
		height = "auto",
		width = "auto",
		flow = "vertical",
		floating = true,
		halign = "right",
		valign = "bottom",
		margin = 8,
		gui.Panel{
			width = "auto",
			height = "auto",
			flow = "horizontal",
			halign = "right",
			valign = "bottom",
			installLabel,
			uninstallButton,
		},
		installButton,
	}


	moduleDetailedDisplay = gui.Panel{
		classes = {"moduleDetailedDisplay", "framedPanel", "collapsed"},
		bgimage = "panels/square.png",
		width = 340*ncols,
		height = 800,

		styles = {
			{
				selectors = {"moduleDetailedDisplay"},
				flow = "vertical",
			},
			{
				selectors = {"detailsPanel"},
				width = "95%",
				height = "86%",
				valign = "top",
				vmargin = 16,
				flow = "vertical",
			},
			{
				selectors = {"label"},
				width = "auto",
				height = "auto",
				halign = "left",
				valign = "top",
				hmargin = 16,
				vmargin = 4,
			},
			{
				selectors = {"titleLabel"},
				fontSize = 24,
				maxWidth = 800,
				textWrap = false,
				bold = true,
				textOverflow = "truncate",
			},
			{
				selectors = {"authorLabel"},
				fontSize = 16,
				italics = true,
				maxWidth = 800,
				textWrap = false,
				textOverflow = "truncate",
			},
			{
				selectors = {"idLabel"},
				fontSize = 16,
				width = "auto",
				height = "auto",
				textAlignment = "left",
			},
			{
				selectors = {"bodyLabel"},
				maxWidth = 1100,
				textWrap = true,
				fontSize = 16,
				valign = "top",
			},
			{
				selectors = {"bodyLabel", "withimage"},
				maxWidth = 800,

			},

		},

		data = {
			moduleInfo = nil,
		},

		displayModule = function(element, moduleInfo)
			element.data.moduleInfo = moduleInfo

			detailedDisplayTitle.text = moduleInfo.name or moduleInfo.fullid
			detailedDisplayAuthor.text = string.format("by %s", moduleInfo.authorid)
			detailedDisplayAuthor.data.search = string.format("author:%s", moduleInfo.authorid)
			detailedDisplayID.data.id = moduleInfo.fullid
			detailedDisplayID.text = string.format("Unique ID: %s", moduleInfo.fullid)

			local details = moduleInfo.details or ""

			local moduleContents = DescribeModuleContents(moduleInfo.contentSummary)
			if moduleContents ~= nil then
				details = string.format("%s\n\n<b>Contents</b>\n%s", details, moduleContents)
			end

			local versions = moduleInfo.versions
			for i=#versions,1,-1 do
				local ver = versions[i]

				details = string.format("%s\n\n<b>Version %s</b>\n<i>%s</i>\n%s", details, ver.version, DescribeServerTimestamp(ver.createTimestamp), ver.notes or "")
			end

			detailedDisplayBody.text = details

			if moduleInfo.coverart ~= nil then
				detailedDisplayImage.bgimage = moduleInfo.coverart
				detailedDisplayImage:SetClass("collapsed", false)
				detailedDisplayBody:SetClass("withimage", true)
			else
				detailedDisplayImage:SetClass("collapsed", true)
				detailedDisplayBody:SetClass("withimage", false)
			end


			element:FireEvent("refreshModuleStats")


			element:FireEventTree("newModule")

		end,

		refreshModuleStats = function(element)
			local moduleInfo = element.data.moduleInfo
			statsPanel:SetClass("hidden", true)
			moduleInfo:QueryStats(function(modid, stats)
				if element.valid and modid == moduleInfo.fullid then
					statsPanel:SetClass("hidden", false)
					installCountLabel.text = string.format("%d", stats.installs)
					upvoteCountLabel.text = string.format("%d", stats.votes+1)

					upvoteCountIcon:FireEvent("refreshUpvote")
				end
			end)
		end,

		gui.Panel{
			classes = {"detailsPanel"},
			vscroll = true,
			detailedDisplayTitle,
			detailedDisplayAuthor,
			detailedDisplayID,
			detailedDisplayPanel,
			statsPanel,
		},

		installPanel,
		bandwidthPanel,

		gui.CloseButton{
			halign = "right",
			valign = "top",
			floating = true,
			click = function(element)
				moduleDetailedDisplay:SetClass("collapsed", true)
				moduleGridContainer:SetClass("collapsed", false)
				moduleGridContainer:FireEventTree("refreshModule")
			end,
		},
	}

	local moduleDisplayPanel

	QueryModuleIndex = function()
		module.QueryModuleIndex{
			index = m_tabSelected,
			success = function(moduleIndex)
				m_moduleIndex = moduleIndex

				statusLabel:SetClass("collapsed", true)
				moduleDisplayPanel:SetClass("collapsed", false)

				ShowSearch("")

			end,

			failure = function(msg)
				statusLabel.text = string.format("Querying modules failed: %s", msg)
			end,
		}
	end


	pageLabel = gui.Label{
		width = "auto",
		height = "auto",
		fontSize = 12,
		halign = "center",
		text = "Page 1/1",
	}

	pageLeft = gui.Panel{
		classes = {"pagingArrow"},
		press = function(element)
			pageNum = pageNum - 1
			SetDisplayedModules(m_displayedItemIds)
		end,
	}

	pageRight = gui.Panel{
		classes = {"pagingArrow"},
		scale = {x = -1, y = 1},

		press = function(element)
			pageNum = pageNum + 1
			SetDisplayedModules(m_displayedItemIds)
		end,
	}

	local pagingArrows = gui.Panel{
		flow = "horizontal",
		width = "auto",
		height = "auto",
		halign = "center",
		pageLeft,
		pageRight,
	}

	local pagingSection = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		halign = "right",
		valign = "bottom",
		pagingArrows,
		pageLabel,
	}

	moduleGrid = gui.Panel{
		flow = "horizontal",
		wrap = true,
		width = 340*ncols,
		height = 834,
		children = gridItems,
		valign = "top",
	}

	moduleGridContainer = gui.Panel{
		width = "auto",
		height = 750,
		flow = "vertical",
		valign = "top",
		moduleGrid,
		pagingSection,
	}

	moduleDisplayPanel = gui.Panel{
		classes = {"collapsed"},
		width = "100%",
		height ="100%",
		flow = "vertical",

		styles = {

			{
				selectors = {"moduleItem"},
				width = 312,
				height = 138,
				pad = 6,
				halign = "left",
				valign = "top",
				margin = 8,
				flow = "vertical",
			},
			{
				selectors = {"moduleItem", "loaded"},
			},
			{
				selectors = {"moduleItem", "installed"},
			},
			{
				selectors = {"moduleItem", "published"},
			},
			{
				selectors = {"moduleItem", "hover"},
				brightness = 1.8,
				transitionTime = 0.1,
			},
			{
				selectors = {"moduleHeading"},
				color = Styles.textColor,
				fontFace = "Inter",
				fontSize = 18,
				minFontSize = 14,
				fontWeight = "light",
				maxWidth = 230,
				width = "auto",
				halign = "left",
				valign = "top",
				height = 24,
				wrap = false,
				textOverflow = "truncate",
			},
			{
				selectors = {"installCheck"},
				hidden = 1,
				bgcolor = "white",
				width = 20,
				height = 20,
				hmargin = 6,
				valign = "center",
				bgimage = "ui-icons/module-checkmark.png",
			},
			{
				selectors = {"installCheck", "installed"},
				hidden = 0,
			},
			{
				selectors = {"moduleAuthor"},
				color = Styles.textColor,
				fontSize = 12,
				width = "auto",
				maxWidth = 160,
				height = 14,
				halign = "right",
				valign = "bottom",
				italics = true,
				wrap = false,
				textOverflow = "ellipsis",
			},
			{
				selectors = {"moduleIcon"},
				bgcolor = "white",
				width = "auto",
				height = "auto",
				maxWidth = 92,
				maxHeight = 92,
				cornerRadius = 2,
				valign = "center",
				halign = "center",
			},
			{
				selectors = {"moduleDetails"},
				color = Styles.textColor,
				fontFace = "Inter",
				fontSize = 12,
				width = "auto",
				height = "auto",
				vmargin = 4,
				maxWidth = 160,
				maxHeight = 90,
				halign = "left",
				valign = "top",
				textOverflow = "ellipsis",
			},

			{
				selectors = {"publishedLabel"},
				hidden = 1,
			},
			{
				selectors = {"publishedLabel", "published"},
			--	hidden = 0,
				color = "white",
				fontSize = 12,
				halign = "right",
				valign = "bottom",
				width = "auto",
				height = "auto",
			},
			{
				selectors = {"installCountLabel"},
				fontSize = 16,
				minFontSize = 12,
				color = Styles.textColor,
				width = "auto",
				height = "auto",
				valign = "center",
				hmargin = 2,
			},

			{
				selectors = {"installCountIcon"},
				width = 16,
				height = 16,
				bgcolor = "white",
				bgimage = "ui-icons/downloadicon.png",

			},

			{
				selectors = {"upvoteCountIcon"},
				width = 16,
				height = 16,
				bgcolor = "white",
				bgimage = "ui-icons/heartunclicked.png",

			},

			{
				selectors = {"upvoteCountIcon", "upvoted"},
				bgimage = "ui-icons/heartclicked.png",
			},

			{
				selectors = {"installCountPanel"},
				width = "auto",
				height = "auto",
				flow = "horizontal",
			},

			{
				selectors = {"pagingArrow"},
				bgimage = "panels/InventoryArrow.png",
				bgcolor = "white",
				height = 40,
				width = 20,
				hmargin = 4,
				halign = "center",
			},

			{
				selectors = {"pagingArrow", "hover"},
				brightness = 1.5,
			},

		},

		gui.Input{
			valign = "top",
			vmargin = 20,
			placeholderText = "Search for modules...",
			editlag = 0.3,
			edit = function(element)
				local text = element.text

			--	moduleGridContainer:SetClass("collapsed", false)
			--	moduleDetailedDisplay:SetClass("collapsed", true)


				ShowSearch(text)

			end,
			changetab = function(element)
				element.text = ""
			end,
		},

		gui.Panel{
			styles = Styles.AdvantageBar,
			classes = {"advantage-bar"},
			valign = "top",
			width = "auto",

			select = function(element, childSelected)
				local children = element.children
				for _,child in ipairs(children) do
					child:SetClass("selected", childSelected == child)
				end

				m_tabSelected = childSelected.data.tab
				element.parent:FireEventTree("changetab")
				QueryModuleIndex()
			end,

			gui.Label{
				classes = {"advantage-element", "selected"},
				text = "Hot",
				data = {
					tab = "hot",
				},

				press = function(element)
					element.parent:FireEvent("select", element)
				end,
			},


			gui.Label{
				classes = {"advantage-element"},
				text = "New",
				data = {
					tab = "new",
				},

				press = function(element)
					element.parent:FireEvent("select", element)
				end,
			},

			gui.Label{
				classes = {"advantage-element"},
				text = "Best",
				data = {
					tab = "best",
				},

				press = function(element)
					element.parent:FireEvent("select", element)
				end,
			},

			gui.Label{
				classes = {"advantage-element"},
				text = "Installed",
				data = {
					tab = "installed",
				},

				press = function(element)
					element.parent:FireEvent("select", element)
				end,
			},
			gui.Label{
				classes = {"advantage-element", cond(#module.GetOurPurchasedModules() == 0, "collapsed")},
				text = "Purchased",
				data = {
					tab = "purchased",
				},

				press = function(element)
					element.parent:FireEvent("select", element)
				end,
			},
			gui.Label{
				classes = {"advantage-element", cond(#module.GetOurPublishedModules() == 0, "collapsed")},
				text = "Published Modules",
				data = {
					tab = "published",
				},

				press = function(element)
					element.parent:FireEvent("select", element)
				end,
			},
		},

		moduleGridContainer,
		moduleDetailedDisplay,
		searchFailedLabel,
	}


    local aspectRatio = dmhub.screenDimensionsBelowTitlebar.x/dmhub.screenDimensionsBelowTitlebar.y


	local dialogPanel = gui.Panel{
		id = 'DownloadShareDialog',
		classes = {'framedPanel'},
		styles = {
			Styles.Default,
			Styles.Panel,
			{
				selectors = {'framedPanel'},
				width = (1080-32)*aspectRatio,
				height = (1080-32),
				flow = 'none',
			},
			{
				selectors = {'center-panel'},
				width = 1804,
				height = (990-32),
				halign = 'center',
				valign = 'center',
				flow = 'vertical',
			},
			{
				selectors = {'input'},
				priority = 10,
				width = 400,
				height = 'auto',
				fontSize = 18,
				valign = 'center',
			},
			{
				selectors = {'status-label'},
				fontSize = 22,
				maxWidth = 600,
				minHeight = 80,
				textWrap = true,
				color = 'white',
				width = 'auto',
				height = 'auto',
				halign = 'center',
				valign = 'center',
			},
		},

		gui.Panel{
			classes = {"center-panel"},

			statusLabel,

			moduleDisplayPanel,
		},


		gui.CloseButton{
			halign = "right",
			valign = "top",
			floating = true,
			escapeActivates = true,
			escapePriority = EscapePriority.EXIT_DIALOG,
			events = {
				click = function(element)
					gui.CloseModal()
				end,
			},
		},
	}

	gui.ShowModal(dialogPanel)

	module.PrepareModuleStats(QueryModuleIndex)
end


mod.shared.ShowExportDialog = function()

	local MapExport = dmhub.MapExport

	MapExport:SetFullMapExport()

	local exportType = "image"
	local duration = 5
	local hz = "60"

	local settingsContainer

	local exportButton
	exportButton = gui.PrettyButton{
		text = 'Export Map',
		width = 240,
		height = 70,
		halign = 'center',
		valign = 'center',
		fontSize = 28,
		events = {
			click = function(element)
				if exportType == "image" then
					dmhub.SaveImageDialog{
						texture = "#MapExport",
						error = function(text)
						end,
						filename = "dmhub-map.png",
					}
				else
					settingsContainer.children = {
						gui.ProgressBar{
							width = 600,
							height = 64,
							value = 0,
						},
						gui.Label{
							text = "Rendering Video...",
							halign = "center",
							export = function(element)
								element.text = "Finalizing..."
							end,
						},
					}
					MapExport:ExportVideo{
						hz = tonumber(hz),
						tour = exportType == "tour",
						duration = duration,
						progress = function(amount)
							settingsContainer:FireEventTree("progress", amount)
							if amount >= 0.99 then
								settingsContainer:FireEventTree("export")
							end
						end,
						error = function(msg)
							msg = msg or "Could not save file"
							gui.ModalMessage{
								title = "Could not save video",
								message = msg,
							}
						end,
						complete = function()
							settingsContainer.children = {
								gui.Label{
									fontSize = 14,
									text = "Export Complete",
									width = "auto",
									height = "auto",
								}
							}
						end,
					}
				end
			end,
		}
	}

	local tourWidth = 1920
	local tourHeight = 1080

	local statusLabel

	local tourSettingsPanel
	tourSettingsPanel = gui.Panel{
		classes = {"collapsed"},

		width = "auto",
		height = "auto",
		flow = "horizontal",

		refreshTour = function(element)
			MapExport:SetMapTourExport{
				width = tourWidth,
				height = tourHeight,
				duration = duration,
				startDuration = 2,
				sheet = function()
					return gui.Panel{
						id = "exportHud",
						styles = Styles.default,
						flow = "none",
						width = 1920,
						height = 1080,
						gui.Panel{
							bgimageAlpha = "panels/gamescreen/loadingscreen4.png",
							width = "100%",
							height = "100%",

							styles = {
								{
									opacity = 0,
								},
								{
									classes = {"open"},
									bgimage = cond(game.currentMap.loadingScreenImage ~= nil, game.currentMap.loadingScreenImage, "panels/square.png"),
									bgcolor = cond(game.currentMap.loadingScreenImage ~= nil, "white", "black"),
									alphaThreshold = 1,
									alphaThresholdFade = 0.1,
									opacity = 1,
								},
								{
									classes = {"endopen"},
									bgcolor = cond(game.currentMap.loadingScreenImage ~= nil, "#ffffff00", "#00000000"),
									alphaThreshold = -0.1,
									transitionTime = 0.8,
								},

							},


							thinkOpen = function(element, t)
								element:SetClass("open", true)
								element:SetClass("endopen", t >= 0.6)
							end,
							thinkClose = function(element)
								element:SetClass("open", false)
							end,
							think = function(element)
								element:SetClass("open", false)
							end,


						},

						gui.Label{
							id = "exportLabel",
							halign = "center",
							valign = "center",
							fontSize = 96,
							fontFace = "SellYourSoul",
							text = game.currentMap.description,
							width = "auto",
							height = "auto",
							styles = {
								{
									color = "#ffffffff",
								},
								{
									classes = {"~shown"},
									color = "#00000000",
									transitionTime = 0.2,
								},

							},
							thinkOpen = function(element, t)
								element:SetClass("shown", t < 0.7)
							end,
							thinkClose = function(element)
								element:SetClass("shown", false)
							end,
							think = function(element)
								element:SetClass("shown", false)
							end,
						},



						gui.Panel{
							bgimage = "panels/square.png",
							bgcolor = "black",
							width = "100%",
							height = "100%",

							styles = {
								{
									opacity = 0,
								},
								{
									classes = {"shown"},
									transitionTime = 0.2,
									opacity = 1,
								}
							},

							thinkOpen = function(element, t)
								element:SetClassTree("shown", false)
							end,
							thinkClose = function(element)
								element:SetClassTree("shown", true)
							end,
							think = function(element)
								element:SetClassTree("shown", false)
							end,

							gui.Panel{
								width = "auto",
								height = "auto",
								flow = "vertical",
								halign = "center",
								valign = "center",
								styles = {
									{
										opacity = 0,
										color = "#ffffff00",
									},
									{
										classes = {"shown"},
										opacity = 1,
										color = "white",
										transitionTime = 0.2,
									}

								},
								gui.Panel{
									width = 768,
									height = 768,
									halign = "center",
									bgimage = "panels/logo/DMHubLogo.png",
									bgcolor = "white",
								},
								gui.Label{
									fontFace = "cambria",
									fontSize = 40,
									width = "auto",
									height = "auto",
									halign = "center",
									text = "www.dmhubapp.com",
								}
							}

						},
					}
				end,
			}
		end,

		gui.Label{
			text = "Width:",
		},
		gui.Input{
			width = 100,
			text = tostring(tourWidth),
			change = function(element)
				if tonumber(element.text) == nil then
					element.text = tostring(tourWidth)
				else
					tourWidth = math.floor(tonumber(element.text))
				end

				tourSettingsPanel:FireEvent("refreshTour")
			end,
		},

		gui.Label{
			text = "Height:",
		},
		gui.Input{
			width = 100,
			text = tostring(tourHeight),
			change = function(element)
				if tonumber(element.text) == nil then
					element.text = tostring(tourHeight)
				else
					tourHeight = math.floor(tonumber(element.text))
				end

				tourSettingsPanel:FireEvent("refreshTour")
			end,
		},
	}

	local videoSettingsPanel = gui.Panel{
		classes = {"collapsed"},

		width = "auto",
		height = "auto",
		flow = "horizontal",
		gui.Label{
			text = "FPS:",
		},

		gui.Dropdown{
			idChosen = hz,
			options = {
				{
					id = "60",
					text = "60Hz",
				},
				{
					id = "30",
					text = "30Hz",
				},
			},
			change = function(element)
				hz = element.idChosen
			end,

		},

		gui.Label{
			text = "Duration:",
		},

		gui.Input{
			width = 40,
			height = 22,
			fontSize = 18,
			text = tostring(duration),
			change = function(element)
				local val = tonumber(element.text)
				if val == nil then
					element.text = tostring(duration)
				else
					duration = val
				end

				tourSettingsPanel:FireEvent("refreshTour")

			end,
		},
		gui.Label{
			text = "seconds",
			width = "auto",
			height = "auto",
			color = "white",
			fontSize = 18,
		},
	}

	local ppuPanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "horizontal",
		gui.Label{
			text = "Pixels-per-tile:",
			width = 'auto',
			height = 'auto',
			color = 'white',
			fontSize = 18,
		},
		gui.Input{
			width = 40,
			height = 22,
			fontSize = 18,
			text = tostring(MapExport.ppu),
			change = function(element)
				MapExport.ppu = tonumber(element.text)
				element.text = tostring(MapExport.ppu)
			end,
		}
	}

	local exportTypePanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "horizontal",
		gui.Label{
			text = "Export Type:",
			width = 'auto',
			height = 'auto',
			color = 'white',
			fontSize = 18,
		},

		gui.Dropdown{
			idChosen = exportType,
			options = {
				{
					id = "image",
					text = "Image",
				},
				{
					id = "video",
					text = "Video",
				},
				{
					id = "tour",
					text = "Map Preview Video",

				},
			},
			change = function(element)
				exportType = element.idChosen
				if exportType == "tour" then
					tourSettingsPanel:FireEvent("refreshTour")
				else
					MapExport:SetFullMapExport()
				end
				tourSettingsPanel:SetClass("collapsed", element.idChosen ~= "tour")
				videoSettingsPanel:SetClass("collapsed", element.idChosen == "image")
				ppuPanel:SetClass("collapsed", element.idChosen == "tour")
			end,
		},

	}

	local dim = game.currentMap.dimensions
	local w = dim.width/max(dim.width,dim.height)
	local h = dim.height/max(dim.width,dim.height)

	statusLabel = gui.Label{
		text = '',
		halign = 'center',
		valign = 'center',
		vmargin = 4,

		create = function(element)
			element:FireEvent("think")
		end,

		thinkTime = 0.2,
		think = function(element)
			statusLabel.text = string.format("Dimensions: %dx%d tiles, %dx%d px image", dim.width, dim.height, MapExport.width, MapExport.height)
		end,
	}

	local previewImage
	previewImage = gui.Panel{
		bgimage = '#MapExport',
		autosizeimage = true,
		maxWidth = 600,
		maxHeight = 600,
		width = "auto",
		height = "auto",
		halign = "center",
		valign = "center",
		bgcolor = "white",
		borderWidth = 2,
		borderColor = "black",
	}

	local previewImageContainer = gui.Panel{
		width = 600,
		height = 600,
		halign = "center",
		valign = "center",
		previewImage,
	}

	settingsContainer = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "vertical",

		styles = {
			{
				selectors = {"label"},
				color = "white",
				fontSize = 18,
				width = "auto",
				height = "auto",
			}

		},

		exportTypePanel,
		videoSettingsPanel,
		tourSettingsPanel,
		ppuPanel,
		statusLabel,
		exportButton,

	}

	local dialogPanel = gui.Panel{
		id = 'ShareDialog',
		classes = {'framedPanel'},
		styles = {
			Styles.Default,
			Styles.Panel,
			{
				selectors = {'framedPanel'},
				width = 1000,
				height = 900,
				flow = 'none',
			},
			{
				selectors = {'content-panel'},
				width = '90%',
				height = '80%',
				valign = 'top',
				halign = 'center',
				flow = 'vertical',
				vmargin = 20,
			},
			{
				selectors = {'form-entry'},
				width = '60%',
				height = 40,
				valign = 'top',
				halign = 'center',
				flow = 'horizontal',
				vmargin = 8,
			},
			{
				selectors = {'formLabel'},
				width = '40%',
				height = 40,
				fontSize = 18,
				color = 'white',
			},
			{
				selectors = {'dropdown'},
				width = 200,
				height = 40,
				fontSize = 18,
				color = 'white',
			},
			{
				selectors = {'dropdown-option'},
				priority = 20,
				width = 200,
				height = 40,
				fontSize = 18,
				color = 'white',
			},
			{
				selectors = {'input'},
				fontSize = 18,
				width = 200,
				height = 24,
			},
			{
				selectors = {'share-input'},
				textAlignment = 'left',
				width = 400,
				height = 24,
				fontSize = 20,
			},
			{
				selectors = {'description-input'},
				textAlignment = 'topleft',
				valign = 'top',
				width = '60%',
				height = 100,
				vmargin = 8,
			},
			{
				selectors = {'status-label'},
				fontSize = 20,
				width = 'auto',
				height = 'auto',
				valign = 'center',
				halign = 'center',
				maxWidth = 400,
				color = 'white',
			},
			{
				selectors = {'share-panel'},
				flow = 'vertical',
				height = 'auto',
				width = '100%',
			},
		},

		gui.Panel{
			classes = {'content-panel'},

			previewImageContainer,
			settingsContainer,

		},

		gui.Panel{
			classes = {'modal-button-panel'},

			gui.PrettyButton{
				text = 'Close',
				escapeActivates = true,
				escapePriority = EscapePriority.EXIT_DIALOG,
				width = 140,
				height = 60,
				halign = 'right',
				events = {
					click = function(element)
						MapExport:CancelVideoExport()
						gui.CloseModal()
					end,
				},
			},

		}
	}

	gui.ShowModal(dialogPanel)
end


Commands.downloadcontent = mod.shared.ShowDownloadShareDialog
Commands.Register{
	name = "Download Module...",
	group = "share",
	command = "downloadcontent",
	ord = 1,
	dmonly = true,
}

Commands.exportmap = mod.shared.ShowExportDialog
Commands.Register{
	name = "Export Map...",
	group = "share",
	command = "exportmap",
	ord = 3,
	dmonly = true,
}

Commands.sharecontent = mod.shared.ShowShareDialog
Commands.Register{
	name = "Publish Module...",
	group = "share",
	command = "sharecontent",
	ord = 2,
	dmonly = true,
}
