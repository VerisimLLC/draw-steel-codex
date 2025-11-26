local mod = dmhub.GetModLoading()

LanguageRelation = RegisterGameType("LanguageRelation")
LanguageRelation.__index = LanguageRelation

LanguageRelation.tableName = "languageRelations"

local function createListItem(options)

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
				XrightClick = function(element)
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
								local newItem = dmhub.DeepCopy(item)
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

--- Transform the target to the source, returning true if we changed anything in the process
--- @param target table The destination array of strings
--- @param source table The source array of strings
--- @return boolean changed Whether we changed the destination array
local function syncArrays(target, source)
    local changed = false

    -- Build a lookup table for fast checking
    local sourceSet = {}
    for _, str in ipairs(source) do
        sourceSet[str] = true
    end
    
    -- Remove items not in source
    for i = #target, 1, -1 do
        if not sourceSet[target[i]] then
            table.remove(target, i)
            changed = true
        end
    end
    
    -- Build lookup of current strings
    local targetSet = {}
    for _, str in ipairs(target) do
        targetSet[str] = true
    end
    
    -- Add items from source that aren't in target
    for _, str in ipairs(source) do
        if not targetSet[str] then
            target[#target + 1] = str
            changed = true
        end
    end

    return changed
end

local function listToFlags(list)
	local flags = {}
	for _, item in ipairs(list) do
		flags[item] = true
	end
	return flags
end

local function flagsToList(flags)
	local list = {}
	for k, _ in pairs(flags) do
		list[#list + 1] = k
	end
	return list
end

local function uploadItem(item)
	local opts = {
		deferUpload = false,
	}
	if item.name == nil or #item.name == 0 then
		item.name = dmhub.GetTable(Language.tableName)[item.id].name
	end
	dmhub.SetAndUploadTableItem(LanguageRelation.tableName, item, opts)
end

local function getActiveLangs(filter)
	local langs = {}
	local langTable = dmhub.GetTableVisible(Language.tableName) or {}

	for k, item in pairs(langTable) do
		if filter == nil or filter(item) then
			langs[k] = item
		end
	end

	return langs
end

--- Synchronize the relationship between the source and
--- related languages. The relationship is 2-way
--- @param sourceLangId string The ID of the source language related to the others
--- @param relatedLangIds string[] The list of languages related to the source
--- @param clearSource? boolean Whether to clear the source from all unrelated (default true)
function LanguageRelation.SyncRelated(sourceLangId, relatedLangIds, clearSource)

	if clearSource == nil then clearSource = true end

	local function filterRelated(lang)
		if lang.id == sourceLangId then return false end
		for _, id in ipairs(relatedLangIds) do
			if lang.id == id then return false end
		end
		return true
	end

	-- Set the source language's relations verbatim
    local langRel = {
        id = sourceLangId,
		name = dmhub.GetTable(Language.tableName)[sourceLangId].name,
        related = listToFlags(relatedLangIds)
    }
    uploadItem(langRel)

	-- Ensure the related langs are related back to the source
	local langRelTable = dmhub.GetTableVisible(LanguageRelation.tableName) or {}
	for _, id in ipairs(relatedLangIds) do
		langRel = langRelTable[id] or {
			id = id,
			name = dmhub.GetTable(Language.tableName)[id].name,
			related = {}
		}
		langRel.related[sourceLangId] = true
		uploadItem(langRel)
	end

	-- Ensure the source id is in no languages other than those related
	if clearSource then
		local candidateLangs = getActiveLangs(filterRelated)
		for _, lang in pairs(candidateLangs) do
			local langRel = langRelTable[lang.id]
			if langRel then
				if langRel.related and langRel.related[sourceLangId] then
					langRel.related[sourceLangId] = nil
					uploadItem(langRel)
				end
			end
		end
	end
end

function LanguageRelation.SetLanguage(editor, langId)
    local langTable = dmhub.GetTableVisible(Language.tableName) or {}
    local lang = langTable[langId]

    -- Languages we'll show in the list are all languages except selected one
    local candidateLangs = {}
    for k, v in pairs(langTable) do
        local isHidden = v:try_get("hidden") or false
        if v.id ~= langId and not isHidden then
            candidateLangs[#candidateLangs + 1] = {
                id = k,
                text = v.name
            }
        end
    end

	local selected = {}
	local langRelTable = dmhub.GetTableVisible(LanguageRelation.tableName) or {}
	local langRelItem = langRelTable[langId]
	if langRelItem then
		selected = langRelItem.related and flagsToList(langRelItem.related) or {}
	end

    local children = {}

    -- Language name - static, read only
    children[#children + 1] = gui.Label {
        text = string.format("Related Languages for %s:", lang.name),
        height = "auto",
        minWidth = "240",
    }

    -- Multiselect = related languages
    children[#children + 1] = gui.Multiselect {
        options = candidateLangs,
        width = 240,
        halign = "left",
        vmargin = 4,
        textDefault = "Select related languages...",
        sort = true,
        data = {
            lastSelected = selected,
        },
		create = function(element)
			-- Convert array to dictionary for UI
			local selectedDict = {}
			for _, id in ipairs(element.data.lastSelected) do
				selectedDict[id] = true
			end
			element.value = selectedDict
		end,
        change = function(element)
            local newSelectedDict = element.value
            local lastSelected = element.data.lastSelected
            -- Convert dictionary to array
            local newSelectedArray = {}
            for id, flag in pairs(newSelectedDict) do
                if flag then
                    newSelectedArray[#newSelectedArray + 1] = id
                end
            end
            local changed = syncArrays(lastSelected, newSelectedArray)
            if changed then
                element.data.lastSelected = newSelectedArray
                LanguageRelation.SyncRelated(langId, newSelectedArray)
            end
        end,
    }

    editor.children = children
end

function LanguageRelation.CreateEditor()
    local editor
    editor = gui.Panel {
        data = {
            SetLanguage = function(langId)
                LanguageRelation.SetLanguage(editor, langId)
            end
        },
        vscroll = true,
        classes = {"class-panel"},
        styles = {
			{
				halign = "left",
			},
			{
				classes = {'class-panel'},
				width = 1200,
				height = '90%',
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
			},
        }
    }
    return editor
end

function LanguageRelation.ShowPanel(parentPanel)

    local editPanel = LanguageRelation.CreateEditor()
    local listPanel = nil
    local languageItems = {}

    listPanel = gui.Panel {
        classes = {"list-panel"},
        vscroll = true,
        monitorAssets = true,
        refreshAssets = function(element)
            local children = {}
            local languages = dmhub.GetTableVisible(Language.tableName) or {}
            local newItems = {}

            for k, item in pairs(languages) do
                newItems[k] = languageItems[k] or createListItem( {
                    select = element.aliveTime > 0.2,
                    tableName = Language.tableName,
                    key = k,
                    click = function()
                        editPanel.data.SetLanguage(k)
                    end,
                })
                newItems[k].text = item.name
                children[#children+1] = newItems[k]
            end

            table.sort(children, function(a,b) return a.text < b.text end)

            languageItems = newItems
            listPanel.children = children
        end
    }

    listPanel:FireEvent("refreshAssets")

    local leftPanel = gui.Panel {
        selfStyle = {
            flow = "vertical",
            height = "100%",
            width = "auto",
        },
        listPanel,
        -- TODO: Refresh button?
    }

    parentPanel.children = {leftPanel, editPanel}

end

Compendium.Register {
    section = "Rules",
    text = "Language Relations",
    contenType = "languageRelations",
    click = function(contentPanel)
        LanguageRelation.ShowPanel(contentPanel)
    end,
}

-- Seed the relations table with Orden languages if it's empty
if dmhub.isDM then

local function loadOrdenRels()
	local langRelTable = dmhub.GetTableVisible(LanguageRelation.tableName) or {}
	if langRelTable and not next(langRelTable) then
		local ordenRels = {
			["Ananjali"] = {"Anjali"},
			["High Rhyvian"] = {"Hyrallic", "Yllyric"},
			["Khamish"] = {"Khoursirian"},
			["Kheltivari"] = {"Yllyric", "Khelt"},
			["Low Rhyvian"] = {"Hyrallic"},
			["Old Variac"] = {"Variac"},
			["Phorialtic"] = {"Low Kuric", "High Kuric"},
			["Rallarian"] = {"Zaliac"},
			["Ullorvic"] = {"Hyrallic", "Yllyric"},
		}

		local langTable = dmhub.GetTableVisible(Language.tableName)
		if langTable then
			local langByName = {}
			local langRels = {}
			for k, item in pairs(langTable) do
				langByName[item.name] = k
				langRels[k] = {
					id = k,
					related = {}
				}
			end

			if next(langByName) then
				-- Build the two-way relationships
				for sourceName, rels in pairs(ordenRels) do
					local sourceId = langByName[sourceName]
					if sourceId and #sourceId > 0 then
						for _, relName in ipairs(rels) do
							if relName and #relName > 0 then
								local relId = langByName[relName]
								if relId and #relId > 0 then
									langRels[sourceId].related[relId] = true
									langRels[relId].related[sourceId] = true
								end
							end
						end
					end
				end

				-- Upload the ones with relationships
				for _, item in pairs(langRels) do
					if next(item.related) then
						uploadItem(item)
					end
				end
			end
		end
	end
end

local function obliterateLangRel()
	local langRelTable = dmhub.GetTableVisible(LanguageRelation.tableName) or {}

	-- The idea here is to clear the data via obliterate.
	for k, _ in pairs(langRelTable) do
		dmhub.ObliterateTableItem(LanguageRelation.tableName, k)
	end

	langRelTable = dmhub.GetTableVisible(LanguageRelation.tableName) or {}
end

local function fixupMissingName()
	local langRels = dmhub.GetTable(LanguageRelation.tableName)
	for _, item in pairs(langRels) do
		if item.name == nil or #item.name == 0 then
			uploadItem(item)
		end
	end
end

local g_oneTimeEventHandler

g_oneTimeEventHandler = dmhub.RegisterEventHandler("refreshTables", function()
    dmhub.DeregisterEventHandler(g_oneTimeEventHandler)

    -- If the language relations table is empty, attempt to load Orden defaults
    local langRelTable = dmhub.GetTableVisible(LanguageRelation.tableName) or {}
    if next(langRelTable) == nil then
        loadOrdenRels()
    else
        fixupMissingName()
    end
end)

Commands.langrelloadorden = function(args)
	loadOrdenRels()
end

Commands.langrelobliterate = function(args)
	obliterateLangRel()
end

Commands.langrelreset = function(args)
	obliterateLangRel()
	loadOrdenRels()
end

end

