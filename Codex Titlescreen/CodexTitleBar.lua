local mod = dmhub.GetModLoading()

local function CreateCodexMenuItem(args)
    local iconPanel

    local m_mainmenu = args.mainmenu
    args.mainmenu = nil

    local name = args.name
    args.name = nil
    local menuItems = args.menuItems
    args.menuItems = nil

    local invertIcon = args.invertIcon
    args.invertIcon = nil

    if args.icon then
        local styles = nil
        if invertIcon then
            styles = {
                {
                    selectors = {"parent:hover"},
                    inversion = 1,
                },
            }
        end
        iconPanel = gui.Panel{
            styles = styles,
            width = 24,
            height = 24,
            bgimage = args.icon,
            bgcolor = "white",
            valign = "center",
            interactable = false,
            seticon = function(element, icon)
                element.bgimage = icon
            end,
        }
        args.icon = nil
    end

    local CollectMenuItems
    CollectMenuItems = function(menuItems, result)
        for _,item in ipairs(menuItems) do
            if item.submenu then
                CollectMenuItems(item.submenu, result)
            else
                result[#result+1] = item
            end
        end
    end

	local resultPanel = {

        classes = {"menuItem", cond(m_mainmenu, "mainmenuOnly", "ingameOnly")},
		popupPositioning = 'panel',

        width = "auto",
        height = "100%",
        flow = "horizontal",

        iconPanel,

        gui.Label{
            classes = {"menuLabel"},
            text = name,
            setname = function(element, newname)
                name = newname
                element.text = newname
            end,
            interactable = false,
        },

        collectMenuItems = function(element, result)
            CollectMenuItems(menuItems(), result)
        end,

        hover = function(element)
            --see if a sibling menu is shown.
            for _,sibling in ipairs(element.parent.children) do
                if sibling ~= element and sibling.popup ~= nil then
                    sibling.popup = nil
                    element:FireEvent("press")
                    return
                end
            end
        end,

		press = function(element)

           	if element.popup ~= nil then
				element.popup = nil
				return
			end

			local menuItems = menuItems()

			element.popup =
			gui.Panel{
				width = "auto",
				height = "auto",
				halign = "right",
				valign = "bottom",
				gui.ContextMenu{
					width = 300,
					x = -element.renderedWidth,
					entries = menuItems,
					click = function()
						element.popup = nil
					end,
				}
			}


		end,
	}

    for k,v in pairs(args) do
        resultPanel[k] = v
    end

	return gui.Panel(resultPanel)

end


local function CreatePresentationBar()
    local resultPanel

    resultPanel = gui.Panel{
        data = {
            presentations = {}

        },
        width = "auto",
        height = 32,
        rmargin = 32,
        halign = "right",
        flow = "horizontal",

        selfStyle = {
            hidden = 1,
        },

        refreshPresentation = function(element)
            local presentationInfo = nil
            for k,v in pairs(element.data.presentations) do
                presentationInfo = v
                break
            end

            print("PRESENTATION:: REFRESH", presentationInfo ~= nil)

            if presentationInfo == nil then
                element.selfStyle.hidden = 1
            else
                element.selfStyle.hidden = 0
                element.children = {
                    gui.Label{
                        fontSize = 16,
                        color = Styles.textColor,
                        width = "auto",
                        height = "auto",
                        text = presentationInfo.text,
                        valign = "center",
                        hmargin = 4,
                    },
                    gui.EnumeratedSliderControl{
                        valign = "center",
                        width = 210,
                        options = presentationInfo.options,
                        value = presentationInfo.value,
                        change = function(element)
                            presentationInfo.onchange(element.value)
                        end,
                    }
                }
            end
        end,
    }

    return resultPanel
end

local function CreateStatusBar()
    local resultPanel

    resultPanel = gui.Panel{
        flow = "horizontal",
        height = "100%",
        width = 600,
        halign = "right",

        gui.Label{
            fontSize = 14,
            minFontSize = 10,
            width = 100,
            height = "100%",
            color = "#aaaaaa",
            text = "Ready",
            thinkTime = 0.01,
            think = function(element)
                if (not dmhub.inGame) or dmhub.isLobbyGame then
                    element.text = ""
                    return
                end
                local undoState = dmhub.undoState
                if undoState.undoPending then
                    element.text = "Syncing..."
                else
                    element.text = "Synced"
                end
            end,
        },

        gui.Label{
            fontSize = 14,
            minFontSize = 10,
            width = 420,
            height = "100%",
            color = "#aaaaaa",
            text = "",
            thinkTime = 0.1,
            think = function(element)
                if (not dmhub.inGame) or dmhub.isLobbyGame then
                    element.text = ""
                    return
                end
                element.text = string.format("%s %s", game.currentMap.description, dmhub.status)
            end,
        }
    }

    return resultPanel
end

local function CreateSearchBar()
    local resultPanel

    local m_searchCache = {}
    local m_intermediateCache = {}

    local searchPDF = function(docid, doc, search)
        local document = doc.doc
        local documentCache = m_searchCache[docid] or {}
        m_searchCache[docid] = documentCache

        local searchCache = documentCache[search] or {}
        documentCache[search] = searchCache
        if searchCache.status == "complete" then
            return searchCache.results
        end

        local infoCache = m_intermediateCache[docid] or { layout = {}, searchResults = {} }
        m_intermediateCache[docid] = infoCache

        local searchResults = infoCache.searchResults[search] or doc.doc:Search(search)
        if searchResults == nil or searchResults == "pending" then
            return "pending"
        elseif type(searchResults) ~= "table" then
            searchCache.status = "complete"
            searchCache.results = {}
            return searchCache.results
        end

        infoCache.searchResults[search] = searchResults

        local status = true

        local matches = {}
        local foundPerfectMatch = false

        for _,result in ipairs(searchResults) do
            local layout = infoCache.layout[result.page]
            if layout == nil then
                infoCache.layout[result.page] = false
                document:TextLayout(result.page, function(layout)
                    infoCache.layout[result.page] = layout
                end)
            end

            layout = infoCache.layout[result.page]
            if layout and status then
                local startingCharIndex = result.index
                local endingCharIndex = startingCharIndex + #search
                for _,rect in ipairs(layout.mergedRects) do
                    --search for the rect we are in, if we dominate the rectangle then
                    --this is a good search result.
                    if rect.a <= startingCharIndex and rect.b >= endingCharIndex then
                        local rectText = layout.text:Substring(rect.a, rect.b)
                        local haystack = string.lower(trim(rectText))
                        local needle = trim(search)
                        if haystack == needle or (string.starts_with(haystack, needle) and string.find(needle, " ") ~= nil) then
                            local perfectMatch = (not foundPerfectMatch) and (haystack == needle)
                            foundPerfectMatch = foundPerfectMatch or perfectMatch
                            --perfect match.
                            local newMatch = {
                                text = string.format("<b>%s, page %d</b>", doc.description, result.page),
                                score = cond(perfectMatch, 100, 50),
                                click = function()
                                    OpenPDFDocument(doc, result.page)
                                end,
                            }

                            local valid = true

                            --see that our font appears larger than others on this page by comparing distance
                            --between breaks. Makes sure we only match on headings.
                            local averageBreakDistance = 0
                            for i=1,#rect.breaks-1 do
                                averageBreakDistance = averageBreakDistance + math.abs(rect.breaks[i+1] - rect.breaks[i])
                            end
                            averageBreakDistance = averageBreakDistance / math.max(1, #rect.breaks-1)

                            local totalAverage = 0
                            local totalCount = 0
                            for _,r in ipairs(layout.mergedRects) do
                                for i=1,#r.breaks-1 do
                                    totalAverage = totalAverage + math.abs(r.breaks[i+1] - r.breaks[i])
                                    totalCount = totalCount + 1
                                end
                            end
                            totalAverage = totalAverage/math.max(1, totalCount)

                            local ratio = averageBreakDistance / math.max(1, totalAverage)

                            if ratio < 1.05 then
                                valid = false
                            else
                                newMatch.score = newMatch.score * ratio
                            end

                            --result de-duplication
                            for _,match in ipairs(matches) do
                                if match.text == newMatch.text then
                                    valid = false
                                    break
                                end
                            end
                            if valid then
                                matches[#matches+1] = newMatch
                            end
                        end
                    end
                end

            else
                status = false
            end
        end

        if not status then
            return "pending"
        end

        table.sort(matches, function(a, b) return a.score > b.score end)
        for i=2,#matches do
            matches[i].score = matches[i].score*0.1
        end

        searchCache.results = matches

        return matches
    end

    local scoreMatch = function(text, search)
        text = string.lower(text)
        search = string.lower(search)

        if text == search then
            return 100
        elseif string.starts_with(text, search) then
            return 75
        elseif string.find(text, search, 1, true) ~= nil then
            return 50
        end

        return 0
    end

    local executeSearch = function(text)
        if TopBar.HasCustomSearch() then
            return TopBar.ExecuteCustomSearch(text)
        end

        local status = true --search is good and complete.
        text = string.trim(string.lower(text))
        if text == "" then
            resultPanel.popup = nil
            return status
        end

        local menuItems = {}
        resultPanel.parent:FireEventTree("collectMenuItems", menuItems)

        local results = {}
        for _,item in ipairs(menuItems) do
            if string.find(string.lower(item.text), text, 1, true) ~= nil then
                local itemCopy = DeepCopy(item)
                itemCopy.score = scoreMatch(itemCopy.text, text)
                results[#results+1] = itemCopy
            end
        end

        --search keybindings.
        for key,bind in pairs(Keybinds.GetBindings()) do
            if string.find(string.lower(bind.name), text, 1, true) ~= nil then
                local itemCopy = DeepCopy(bind)
                itemCopy.score = scoreMatch(itemCopy.name, text)
                itemCopy.text = string.format("<b>%s</b> (Shortcut)", itemCopy.name)
                itemCopy.click = function()
                    dmhub.ShowPlayerSettings{search = itemCopy.name}
                end
                results[#results+1] = itemCopy
            end
        end

        --search settings.
        for key,settingInfo in pairs(Settings) do
            if settingInfo.section ~= nil and string.find(string.lower(settingInfo.description), text, 1, true) ~= nil and (dmhub.isDM or (settingInfo.classes or {})[1] ~= "dmonly") then
                local itemCopy = DeepCopy(settingInfo)
                itemCopy.score = scoreMatch(itemCopy.description, text)
                itemCopy.text = string.format("<b>%s</b> (Setting)", itemCopy.description)
                itemCopy.click = function()
                    dmhub.ShowPlayerSettings{search = itemCopy.description}
                end

                results[#results+1] = itemCopy
            end
        end

        local links = CustomDocument.SearchLinks(text)
        for _,link in ipairs(links) do
            link.score = scoreMatch(link.name, text)
            link.text = string.format("<b>%s</b> (%s)", link.name, link.type)
            link.click = function()
                CustomDocument.OpenContent(CustomDocument.ResolveLink(link.link))
            end
            results[#results+1] = link
        end

        for k,doc in pairs(assets.pdfDocumentsTable) do
            if not doc.hidden then

                local pdfresults = searchPDF(k, doc, text)
                print("ExecuteSearch PDF", doc.description, pdfresults)
                if type(pdfresults) == "table" then
                    for _,r in ipairs(pdfresults) do
                        results[#results+1] = r
                    end
                else
                    status = false --search should be repeated.
                end
            end
        end

        table.stable_sort(results, function(a,b) return a.score > b.score end)
        while #results > 10 do
            table.remove(results)
        end

        if #results == 0 then
            if resultPanel.popup == nil or resultPanel.data.popupResults ~= nil then
                resultPanel.data.popupResults = nil
                resultPanel.popup = gui.Label{
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "bottom",
                    fontSize = 18,
                    bgimage = true,
                    bgcolor = "black",
                    settext = function(element, newtext)
                        element.text = newtext
                    end,
                }
            end

            resultPanel.popup:FireEventTree("settext", cond(status, "No Search Results", "Searching..."))
            return status
        end

        local popupData = {
            status = status,
            results = results,
        }

        if resultPanel.popup ~= nil and resultPanel.data.popupResults ~= nil then
            if popupData.status == resultPanel.data.popupResults.status and #popupData.results == #resultPanel.data.popupResults.results then
                local same = true
                for i=1,#popupData.results do
                    if popupData.results[i].text ~= resultPanel.data.popupResults.results[i].text then
                        same = false
                        break
                    end
                end

                if same then
                    --no need to invalidate menu.
                    return status
                end
            end
        end

        resultPanel.data.popupResults = popupData

        local searchingLabel = nil
        if not status then
            searchingLabel = gui.Label{
                width = "auto",
                height = "auto",
                fontSize = 18,
                text = "Searching for more results...",
            }
        end

		resultPanel.popup =
		gui.Panel{
			width = "auto",
			height = "auto",
			halign = "center",
			valign = "bottom",
            flow = "vertical",
			gui.ContextMenu{
				width = 360,
                valign = "bottom",
				entries = results,
				click = function()
					resultPanel.popup = nil
				end,
			},
            searchingLabel,
		}

        return status
    end

    resultPanel = gui.SearchInput{
        styles = {
            {
                borderColor = "clear",
            },
            {
                selectors = {"~ingame", "~searchoverride"},
                hidden = 1,
            },
            {
                selectors = {"focus"},
                borderWidth = 1,
                borderColor = Styles.textColor,
            },
        },
        bgimage = true,
        bgcolor = "clear",
        width = 368,
        height = 20,
        halign = "right",
        valign = "center",
        borderWidth = 1,
        fontSize = 16,
        pad = 2,
        popupPositioning = "panel",
        placeholderText = cond(dmhub.GetCommandBinding("find"), string.format("Search (%s)...", dmhub.GetCommandBinding("find") or ""), "Search..."),
        inputEvents = { "find" },
        editlag = 0.1,
        edit = function(element)
            local status = executeSearch(element.text)
            if not status then
                element:FireEvent("repeatSearch")
            end
        end,
        change = function(element)
            --element:FireEvent("edit")
        end,
        find = function(element)
            element.hasFocus = true
        end,
        deselect = function(element)
            element.text = ""
        end,
        repeatSearch = function(element)
            if element.data.repeatingSearch then
                return
            end

            element.data.repeatingSearch = true
            element:ScheduleEvent("dorepeatSearch", 0.2)
        end,
        dorepeatSearch = function(element)
            element.data.repeatingSearch = false
            element:FireEvent("edit")
        end,
    }

    return resultPanel
end

local g_adventureDocumentsBar

local g_presentationBar

local g_searchBar

--- @type string[]
local g_searchStack = {}

--- @type table<string, table>
local g_searchHandlers = {}

TopBar = {}


--- @param documentids {string}
TopBar.SetAdventureDocuments = function(info, documentids)
    if g_adventureDocumentsBar ~= nil and g_adventureDocumentsBar.valid then
        if info then
            g_adventureDocumentsBar:FireEventTree("setname", info.name or "Adventure Documents")
            g_adventureDocumentsBar:FireEventTree("seticon", info.icon)
        end
        g_adventureDocumentsBar:FireEventTree("documents", documentids)
    end
end

--- @param info {id: string}
TopBar.SetPresentationInfo = function(info)
    if g_presentationBar == nil  or (not g_presentationBar.valid) then
        return
    end

    g_presentationBar.data.presentations[info.id] = info
    g_presentationBar:FireEventTree("refreshPresentation")
end

--- @param id string
TopBar.ClearPresentationInfo = function(id)
    if g_presentationBar == nil  or (not g_presentationBar.valid) then
        return
    end

    g_presentationBar.data.presentations[id] = nil
    g_presentationBar:FireEventTree("refreshPresentation")
end

TopBar.FocusSearchBar = function()
    if g_searchBar ~= nil and g_searchBar.valid then
        g_searchBar.hasFocus = true
    end
end

TopBar.HasCustomSearch = function()
    return #g_searchStack > 0
end

TopBar.ExecuteCustomSearch = function(text)
    if #g_searchStack == 0 then
        return true
    end

    local guid = g_searchStack[#g_searchStack]
    local handler = g_searchHandlers[guid]
    if handler == nil then
        return true
    end

    return handler(text)
end

TopBar.InstallSearchHandler = function(searchHandler)
    local guid = dmhub.GenerateGuid()
    print("SearchHandler: Install", guid)

    g_searchHandlers[guid] = searchHandler
    g_searchStack[#g_searchStack+1] = guid

    if g_searchBar ~= nil and g_searchBar.valid then
        g_searchBar:SetClassTree("searchoverride", true)
        print("SearchHandler: Set class")
    end

    return guid
end

TopBar.UninstallSearchHandler = function(guid)
    if guid == nil then
        return
    end
    print("SearchHandler: Uninstall", guid)
    g_searchHandlers[guid] = nil

    for i=#g_searchStack,1,-1 do
        if g_searchStack[i] == guid then
            table.remove(g_searchStack, i)
            break
        end
    end

    if #g_searchStack == 0 then
        if g_searchBar ~= nil and g_searchBar.valid then
            g_searchBar:SetClassTree("searchoverride", false)
        end
    end
end 

local function CreateTopBar()
	local dmControlsPanel = nil
	local layersPanel = nil

    local m_inGame = nil
    local m_searchBar = CreateSearchBar()
    local m_presentationBar = CreatePresentationBar()

    g_searchBar = m_searchBar
    g_presentationBar = m_presentationBar


    local m_documents
    local m_adventureDocumentsBar = CreateCodexMenuItem{
        icon = "panels/drawsteel/delian-tomb.png",
        invertIcon = true,
        name = "Delian Tomb",
        create = function(element)
            element.selfStyle.collapsed = 1
        end,
        menuItems = function()
            local result = {}
            local documentsTable = dmhub.GetTable(CustomDocument.tableName) or {}
            for _,docid in ipairs(m_documents or {}) do
                local doc = documentsTable[docid]
                if doc ~= nil then
                    result[#result+1] = {
                        text = doc.name,
                        click = function()
                            doc:ShowDocument()
                        end,
                    }
                end
            end
            return result
        end,
        documents = function(element, documentids)
            m_documents = documentids
            element.selfStyle.collapsed = (#m_documents == 0) or (not dmhub.isDM)
        end,
    }

    g_adventureDocumentsBar = m_adventureDocumentsBar


    local menuBar = gui.Panel{
        id = "menuBarPanel",
        width = "100%",
        height = 32,
        floating = true,
        valign = "top",
        bgimage = true,
        bgcolor = "white",
        gradient = Styles.RichBlackGradient,
        flow = "horizontal",

        styles = {
            {
                selectors = {"mainmenuOnly", "ingame"},
                collapsed = 1,
            },
            {
                selectors = {"ingameOnly", "~ingame"},
                collapsed = 1,
            },
        },

        destroy = function(element)
            g_adventureDocumentsBar = nil
        end,

        thinkTime = 0.2,
        think = function(element)
            if (dmhub.inGame and not dmhub.isLobbyGame) ~= m_inGame then
                m_inGame = (dmhub.inGame and not dmhub.isLobbyGame)
                element:SetClassTree("ingame", m_inGame)
            end
            element:FireEventTree("calculateVisibility")
        end,

        CreateCodexMenuItem{
            name = "Codex",
            icon = "ui-icons/codex-logo.png",
            mainmenu = true,
            menuItems = function()
			    return {
                    {
                        text = "Settings",
                        icon = "panels/hud/gear.png",
                        click = function()
                            dmhub.ShowPlayerSettings()
                        end,
                    },
                    {
                        text = "Quit to Desktop",
                        icon = "game-icons/power-button.png",
                        click = function()
                            dmhub.QuitApplication()
                        end,
                    },
                }
            end,
        },

        CreateCodexMenuItem{
            name = "Codex",
            icon = "ui-icons/codex-logo.png",
            menuItems = function()
			    return table.filter(LaunchablePanel.GetMenuItems(), function(item) return item.menu == nil and item.text ~= "Development Tools" end)
            end,
        },

        CreateCodexMenuItem{
            name = "Game",
            menuItems = function()
			    return table.filter(LaunchablePanel.GetMenuItems(), function(item) return item.menu == "game" end)
            end,
        },

        CreateCodexMenuItem{
            name = "Tools",
            menuItems = function()
			    return table.filter(LaunchablePanel.GetMenuItems(), function(item) return item.menu == "tools" end)
            end,
        },

        CreateCodexMenuItem{
            name = "Panels",
            menuItems = function()
                local dockablePanels = DockablePanel.GetMenuItems()
                dockablePanels = table.filter(dockablePanels, function(item) return item.text ~= "Development Tools" end)

                local locked = dmhub.GetSettingValue("uilocked")

                if locked then
                    for _,p in ipairs(gui.FlattenContextMenuItems(dockablePanels)) do
                        p.disabled = true
                    end
                end

                table.insert(dockablePanels, 1, {
                    text = "Left Dock",
                    check = not dmhub.GetSettingValue("leftdockoffscreen"),
                    group = "panel",

                    click = function()
                        dmhub.SetSettingValue("leftdockoffscreen", not dmhub.GetSettingValue("leftdockoffscreen"))
                    end,
                })

                table.insert(dockablePanels, 1, {
                    text = "Right Dock",
                    check = not dmhub.GetSettingValue("rightdockoffscreen"),
                    group = "panel",

                    click = function()
                        dmhub.SetSettingValue("rightdockoffscreen", not dmhub.GetSettingValue("rightdockoffscreen"))
                    end,
                })

                table.insert(dockablePanels, 1, {
                    text = "Reset Panels",
                    icon = "icons/icon_tool/icon_power.png",
                    group = "panel",

                    click = function()
                        dmhub.ResetSetting(GetDockablePanelsSetting())
                        InitDockablePanels()
                    end,
                })

                table.insert(dockablePanels, 1, {
                    text = cond(locked, "Unlock Panels", "Lock Panels"),
                    icon = cond(locked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png"),
                    check = locked,
                    group = "panel",
                    click = function()
                        dmhub.SetSettingValue("uilocked", not locked)
                    end,
                })

                return dockablePanels
            end,
        },

        m_adventureDocumentsBar,

        CreateCodexMenuItem{
            name = "Developer",
            calculateVisibility = function(element)
                element.selfStyle.collapsed = cond(devmode(), 0, 1)
            end,
            menuItems = function()
                if not devmode() then
                    return {}
                end
                --pillage the "Development Tools" folders from our menu items.
                local menuItems = {}
                for i,items in ipairs({DockablePanel.GetMenuItems(), LaunchablePanel.GetMenuItems()}) do
                    for j,item in ipairs(items) do
                        if item.submenu and item.text == "Development Tools" then
                            for _,entry in ipairs(item.submenu) do
                                menuItems[#menuItems+1] = entry
                            end
                        end
                    end
                end
                return menuItems
            end,
        },

        m_presentationBar,
        CreateStatusBar(),
        m_searchBar,
    }

	local topBarPanel = gui.Panel{
        id = "topBar",
		width = dmhub.titleBarContainer.width,
		height = dmhub.titleBarContainer.height,
		flow = "horizontal",

        screenResized = function (element)
            element.selfStyle.width = dmhub.titleBarContainer.width
            element.selfStyle.height = dmhub.titleBarContainer.height
        end,

        thinkTime = 0.5,
        think = function(element)
            if element.selfStyle.width ~= dmhub.titleBarContainer.width then
                element.selfStyle.width = dmhub.titleBarContainer.width
            end

            if element.selfStyle.height ~= dmhub.titleBarContainer.height then
                element.selfStyle.height = dmhub.titleBarContainer.height
            end
        end,

        styles = {
            {
                selectors = {"menuItem"},
                bgimage = true,
                bgcolor = "clear",
                hpad = 8,
            },
            {
                selectors = {"menuItem", "hover"},
                bgcolor = Styles.textColor,
            },
            {
                selectors = {"menuLabel"},
                fontSize = 16,
                width = "auto",
                height = "auto",
                valign = "center",
                hmargin = 4,
                color = Styles.textColor,
            },
            {
                selectors = {"menuLabel", "parent:hover"},
                color = Styles.backgroundColor,
            }
        },

		--dmControlsPanel,
		--layersPanel,
        menuBar,
	}

	return topBarPanel
end

dmhub.titleBarContainer.sheet = CreateTopBar()