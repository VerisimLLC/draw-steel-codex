local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local g_devInventorySetting = setting{
    id = "dev:storepreview",
    default = false,
    storage = "preference",
}

-- Open the shop/inventory screen. The screen needs a host panel that has a
-- .data.dialog (for sizing) and that it can be parented to. On the
-- titlescreen/lobby that host is CodexTitlescreenRoot; once in a real game
-- the titlescreen is gone, so we host it on the game hud's dedicated
-- fullscreen shopPanel instead.
local function OpenShopScreen(inventory)
    if dmhub.inGame and not dmhub.isLobbyGame and GameHud.instance and GameHud.instance.shopPanel then
        local host = GameHud.instance.shopPanel
        host:AddChild(CreateShopScreen{ titlescreen = host, inventory = inventory })
    elseif CodexTitlescreenRoot ~= nil and CodexTitlescreenRoot.valid then
        CodexTitlescreenRoot:AddChild(CreateShopScreen{ titlescreen = CodexTitlescreenRoot, inventory = inventory })
    end
end

-- Shop/Inventory menu entries, gated behind the dev:storepreview setting.
-- Returned for both the main-menu Codex menu and the in-game Codex menu so
-- the options are reachable everywhere in the app.
local function GetStoreMenuItems()
    if not g_devInventorySetting:Get() then
        return {}
    end

    return {
        {
            text = "Shop",
            icon = "icons/icon_shopping/shopping-cart.png",
            click = function()
                OpenShopScreen(false)
            end,
        },
        {
            text = "Inventory",
            icon = "ui-icons/gift-icon.png",
            click = function()
                OpenShopScreen(true)
            end,
        },
    }
end

local function CreateCodexMenuItem(args)
    local iconPanel

    local m_mainmenu = args.mainmenu
    args.mainmenu = nil

    local name = args.name
    args.name = nil
    local menuItems = args.menuItems
    args.menuItems = nil

    if args.icon then
        iconPanel = gui.Panel{
            classes = {"menuItemIcon"},
            width = 24,
            height = 24,
            bgimage = args.icon,
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

			element.popup = gui.Panel{
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

local g_showStatusBarSetting = setting{
    id = "showstatusbar",
    description = "Show status bar",
    editor = "check",
    default = true,
    storage = "preference",
    section = "General",
}

local function CreateStatusBar()
    local resultPanel

    resultPanel = gui.Panel{
        flow = "horizontal",
        height = "100%",
        width = 600,
        halign = "right",

        rightClick = function(element)
            local menuItems = {
                {
                    text = "Show Status Bar",
                    check = g_showStatusBarSetting:Get(),
                    click = function()
                        g_showStatusBarSetting:Set(not g_showStatusBarSetting:Get())
                        element.popup = nil
                    end,
                },
            }

            element.popup = gui.ContextMenu{
                entries = menuItems,
            }
        end,

        gui.Label{
            minFontSize = 10,
            width = 160,
            height = "100%",
            text = "Ready",
            multimonitor = {"showstatusbar"},
            monitor = function(element)
                element.thinkTime = cond(g_showStatusBarSetting:Get(), 0.01, nil)
                element.text = ""
            end,
            thinkTime = cond(g_showStatusBarSetting:Get(), 0.01, nil),
            think = function(element)
                if (not dmhub.inGame) or dmhub.isLobbyGame then
                    element.text = ""
                    return
                end
                local writeCount = dmhub.pendingWriteCount
                local undoState = dmhub.undoState
                local text
                if undoState.undoPending then
                    text = "Syncing..."
                else
                    text = "Synced"
                end

                if writeCount > 0 then
                    text = string.format("%s (%d)", text, writeCount)
                end

                local seq = dmhub.durableObjectSeq
                if seq and seq > 0 then
                    element.text = string.format("%s  seq:%d", text, seq)
                else
                    element.text = text
                end
            end,
            click = function(element)
                local history = dmhub:GetDurableObjectSeqHistory() or {}
                local lines = {}
                if #history == 0 then
                    lines[1] = "(no seq-tagged messages received yet)"
                else
                    for i = #history, 1, -1 do
                        lines[#lines+1] = history[i]
                    end
                end

                gamehud:ModalDialog{
                    title = string.format("DO Message History (latest seq: %d)", dmhub.durableObjectSeq or 0),
                    width = 600,
                    height = 500,
                    flow = "vertical",
                    halign = "center",
                    valign = "top",
                    gui.Label{
                        width = "95%",
                        height = "auto",
                        halign = "center",
                        valign = "top",
                        fontSize = 14,
                        color = "white",
                        text = "Most recent at top. Inbound lines start with a seq number;\noutbound lines to the game store start with '>>'. Acks include\nthe round-trip time in milliseconds.",
                        vmargin = 4,
                    },
                    gui.Panel{
                        width = "95%",
                        height = "100%-80",
                        halign = "center",
                        flow = "vertical",
                        vscroll = true,
                        styles = {
                            {
                                selectors = {"label"},
                                width = "100%",
                                height = "auto",
                                fontSize = 14,
                                color = "#dddddd",
                                halign = "left",
                                vmargin = 1,
                            },
                        },
                        children = (function()
                            local result = {}
                            for _, line in ipairs(lines) do
                                result[#result+1] = gui.Label{ text = line }
                            end
                            return result
                        end)(),
                    },
                    buttons = {
                        { text = "Close", escapeActivates = true },
                    },
                }
            end,
        },

        gui.Label{
            minFontSize = 10,
            width = 420,
            height = "100%",
            text = "",
            multimonitor = {"showstatusbar"},
            monitor = function(element)
                element.thinkTime = cond(g_showStatusBarSetting:Get(), 0.1, nil)
                element.text = ""
            end,
            thinkTime = cond(g_showStatusBarSetting:Get(), 0.1, nil),
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

-- Label a placed token by kind so its result row reads Hero / NPC / Monster
-- (the leading icon is the token's own portrait, but the text label still
-- splits it the way the unplaced providers do).
-- These rows are all PLACED tokens, so the kind carries an "(on Map)" suffix --
-- it tells a deployed creature apart from the same kind of UNPLACED one (the
-- partyCharacters provider, plain "Hero"/"NPC") when both can share the "In
-- this Campaign" bucket.
local function TokenKindLabel(token)
    local props = token.properties
    if props ~= nil then
        local ok, isMonster = pcall(function() return props:IsMonster() end)
        if ok and isMonster then
            return "Monster (on Map)"
        end
    end
    if token.playerControlled then
        return "Hero (on Map)"
    end
    return "NPC (on Map)"
end

-- Global-search provider: tokens on the current map(s). Full provider (bespoke
-- data, custom activate): clicking selects the token and centres the camera on
-- it. Players only see tokens not hidden from them. Each result carries the
-- live token so the row can render its portrait as the leading icon - a visual
-- cue that this creature is placed on the map (vs the flat Character/Bestiary
-- icon shown for unplaced heroes/monsters).
Search.RegisterProvider{
    id = "tokens",
    bucket = "ingame",
    enumerate = function(needle)
        -- Director-only: token search leads to selection/placement, which are
        -- director actions. A player searching their own party members was
        -- offered a placement prompt they cannot fulfil, so campaign token
        -- search is gated to the DM (matching the unplaced-character provider).
        if (not dmhub.inGame) or (not dmhub.isDM) then
            return {}
        end
        local results = {}
        for _,token in ipairs(dmhub.allTokens) do
            local name = token.name
            if type(name) == "string" and Search.MatchesText(name, needle) then
                local capturedId = token.id
                results[#results+1] = {
                    name = name,
                    score = Search.Score(name, needle),
                    typeLabel = TokenKindLabel(token),
                    token = token,
                    -- Lets the "On this map" context group dedupe this token out
                    -- of the bucket while it is pinned there (same key the
                    -- map-view provider stamps).
                    dedupKey = "token:" .. capturedId,
                    activate = function()
                        dmhub.SelectToken(capturedId)
                        dmhub.CenterOnToken(capturedId)
                    end,
                }
            end
        end
        return results
    end,
}

local function CreateSearchBar()
    local resultPanel

    -- Per-doc heading search lives in JournalPDFViewer.lua (SearchPDFHeadings,
    -- shared with the "In this document" context provider). This wrapper maps
    -- its {page, heading, score} matches onto result rows: the HEADING is the
    -- row's main line, "doc, page N" the subhead. The 0.1 dampening of every
    -- match after the first is global-ranking glue (one PDF must not flood the
    -- flat list); it stays here rather than in the shared search.
    local searchPDF = function(docid, doc, search)
        local matches = SearchPDFHeadings(doc, search)
        if type(matches) ~= "table" then
            return "pending"
        end

        local rows = {}
        for i,m in ipairs(matches) do
            local capturedPage = m.page
            rows[#rows+1] = {
                name = m.heading,
                subLabel = string.format("%s, page %d", doc.description, m.page),
                score = cond(i == 1, m.score, m.score * 0.1),
                click = function()
                    OpenPDFDocument(doc, capturedPage)
                end,
            }
        end
        return rows
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

    -- The 4 intent buckets the flat result list is grouped into. Stable ids
    -- come from Search.Buckets; the labels + order live here (the search UI
    -- owns the display strings).
    local SEARCH_BUCKETS = {
        { id = "compendium", label = "Compendium" },
        { id = "rulebooks", label = "Rulebooks" },
        { id = "ingame", label = "In this Campaign" },
        { id = "apptools", label = "App & tools" },
    }
    -- Per-bucket render budget: how many rows show before "See all N", and the
    -- most we keep in memory per bucket (the rest deep-link to the surface).
    local SEARCH_BUCKET_SHOWN = 5
    local SEARCH_BUCKET_STORE = 50

    -- Map a CustomDocument.SearchLinks result type onto a bucket.
    local function BucketForLinkType(linkType)
        if linkType == "PDF Document" or linkType == "PDF Fragment" then
            return "rulebooks"
        end
        if linkType == "Document" or linkType == "Map" then
            return "ingame"
        end
        -- Markdown-table prefixes (item:, title:, ...) and prefix suggestions
        -- are compendium content.
        return "compendium"
    end

    -- Session-local list of recently activated results, newest first. Shown
    -- as a "Recent" group when the search box is focused while empty - an
    -- empty-state that gets a returning user back to what they were working
    -- with. In-memory only (activation closures cannot be persisted).
    local m_recentResults = {}
    local RECENT_STORE = 20

    local function RecordRecentResult(result)
        local key = (result.name or result.text or "") .. "\1" .. (result.typeLabel or "")
        for i,r in ipairs(m_recentResults) do
            if ((r.name or r.text or "") .. "\1" .. (r.typeLabel or "")) == key then
                table.remove(m_recentResults, i)
                break
            end
        end
        table.insert(m_recentResults, 1, result)
        while #m_recentResults > RECENT_STORE do
            table.remove(m_recentResults)
        end
    end

    -- Per-type leading icons for the result rows. App icons (Icon_App_*) are
    -- full-colour, so they render untinted (bgcolor "white" in the style) -
    -- an INLINE bgcolor of a theme token is NOT resolved by the theme engine,
    -- so a tinted icon would paint invisible.
    local SEARCH_ICON_MONSTER    = "icons/standard/Icon_App_Bestiary.png"
    local SEARCH_ICON_CHARACTER  = "icons/standard/Icon_App_Character.png"
    local SEARCH_ICON_MAP        = "icons/standard/Icon_App_MapSettings.png"
    local SEARCH_ICON_JOURNAL    = "icons/standard/Icon_App_Journal.png"
    local SEARCH_ICON_ENCOUNTER  = "icons/standard/Icon_App_EncounterCreator.png"
    local SEARCH_ICON_SETTINGS   = "panels/hud/gear.png"
    -- The Compendium has no Icon_App_* glyph; reuse the icon that prepends the
    -- Compendium link in the Codex title-bar menu (its LaunchablePanel icon).
    local SEARCH_ICON_COMPENDIUM = "game-icons/bookmarklet.png"

    local SEARCH_ICON_BY_TYPELABEL = {
        ["monster"]   = SEARCH_ICON_MONSTER,
        ["companion"] = SEARCH_ICON_MONSTER,
        ["hero"]      = SEARCH_ICON_CHARACTER,
        ["npc"]       = SEARCH_ICON_CHARACTER,
        ["map"]       = SEARCH_ICON_MAP,
        ["encounter"] = SEARCH_ICON_ENCOUNTER,
    }

    -- Map a result to its leading icon. Providers may set result.icon to
    -- override; otherwise map from typeLabel (most specific) then bucket.
    local function iconForResult(result)
        if result.icon ~= nil then
            return result.icon
        end

        local typeLabel = result.typeLabel
        if typeLabel ~= nil then
            local t = string.lower(typeLabel)
            local byType = SEARCH_ICON_BY_TYPELABEL[t]
            if byType ~= nil then
                return byType
            end
            -- Document / PDF Document / PDF Fragment -> journal.
            if t == "document" or string.find(t, "pdf", 1, true) ~= nil then
                return SEARCH_ICON_JOURNAL
            end
        end

        local bucket = result.bucket
        if bucket == "rulebooks" then
            return SEARCH_ICON_JOURNAL
        elseif bucket == "apptools" then
            return SEARCH_ICON_SETTINGS
        elseif bucket == "ingame" then
            -- tokens / maps / journals / encounters are caught above by
            -- typeLabel; the remainder (creature features) are capabilities
            -- that live on a creature.
            return SEARCH_ICON_CHARACTER
        end

        -- Compendium content (conditions, classes, ...) and anything else.
        return SEARCH_ICON_COMPENDIUM
    end

    -- One result row: a leading per-type icon, then a highlighted name
    -- (provider results) or preformatted text (legacy handlers), plus an
    -- optional muted type/source label, plus an optional subhead line under
    -- the name (e.g. PDF results show the matched heading with "doc, page N"
    -- beneath it). Pressing runs the result's action and dismisses the popup.
    local function CreateResultRow(result, needle)
        -- A placed token renders its own portrait (Hero/retainer/NPC/monster
        -- already on the map); everything else gets a flat per-type glyph. If
        -- the token went invalid since enumeration, fall back to the glyph.
        local iconPanel
        if result.token ~= nil and result.token.valid then
            iconPanel = gui.CreateTokenImage(result.token, {
                width = 20,
                height = 20,
                halign = "left",
                valign = "center",
                rmargin = 8,
                interactable = false,
            })
        elseif result.bubbleIcon ~= nil then
            -- Map note: render the bubble's own numbered pin (dark disc, light
            -- border) as the leading icon, matching the on-map marker and the
            -- documents panel's pin so a note reads as a note at a glance.
            iconPanel = gui.Label{
                classes = {"searchResultBubble"},
                text = result.bubbleIcon,
                interactable = false,
            }
        else
            iconPanel = gui.Panel{
                classes = {"searchResultIcon"},
                bgimage = iconForResult(result),
                interactable = false,
            }
        end

        local nameLabel = gui.Label{
            classes = {"searchResultName"},
            text = result.name ~= nil and Search.Highlight(result.name, needle) or (result.text or ""),
        }

        local nameBlock = nameLabel
        if result.subLabel ~= nil then
            nameBlock = gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                nameLabel,
                gui.Label{
                    classes = {"searchResultSub"},
                    text = result.subLabel,
                },
            }
        end

        local typeLabel = nil
        if result.typeLabel ~= nil then
            typeLabel = gui.Label{
                classes = {"searchResultType"},
                text = result.typeLabel,
            }
        end

        return gui.Panel{
            classes = {"searchResultRow"},
            flow = "horizontal",
            press = function()
                RecordRecentResult(result)
                -- clearing the text fires edit("") - don't let that pop the
                -- recents group right after navigating away.
                resultPanel.data.skipRecentsOnce = true
                resultPanel.popup = nil
                -- deselect no longer clears the query when the pointer is on
                -- the popup, so reset it here on activation.
                resultPanel.text = ""
                if result.click ~= nil then
                    result.click()
                elseif result.activate ~= nil then
                    result.activate()
                end
            end,
            -- Providers can attach secondary actions via a menuItems function
            -- returning {text, click} entries (e.g. monsters: Place on Map /
            -- Edit Monster). Activating an entry dismisses the search popup
            -- the same way a row press does.
            rightClick = function(element)
                if result.menuItems == nil then
                    return
                end
                local entries = {}
                for _,item in ipairs(result.menuItems()) do
                    local capturedClick = item.click
                    entries[#entries+1] = {
                        text = item.text,
                        click = function()
                            RecordRecentResult(result)
                            resultPanel.data.skipRecentsOnce = true
                            element.popup = nil
                            resultPanel.popup = nil
                            resultPanel.text = ""
                            if capturedClick ~= nil then
                                capturedClick()
                            end
                        end,
                    }
                end
                if #entries > 0 then
                    element.popup = gui.ContextMenu{ entries = entries }
                end
            end,
            iconPanel,
            nameBlock,
            typeLabel,
        }
    end

    -- Build the grouped results popup. `expanded` is a per-bucket flag set;
    -- pressing "See all" flips a bucket open and rebuilds in place. Only the
    -- shown rows are rendered (the lazy render budget).
    --
    -- Keyboard navigation: the search input forwards uparrow / downarrow /
    -- activateSelection (Enter) here via FireEventTree (same idiom as the
    -- GoblinScript autocomplete popup). A cursor walks every navigable entry
    -- (result rows AND "See all" labels, so expansion is keyboard-reachable);
    -- the selected entry carries the "searchfocus" class. Enter with no
    -- selection activates the first result.
    local function CreateGroupedPopup(grouped, needle, expanded, searchingLabel, context)
        local children = {}
        local navRows = {}

        local function AppendGroup(label, list, expandKey)
            children[#children+1] = gui.Label{
                classes = {"searchGroupHeading"},
                text = string.format("<b>%s</b> (%d)", label, #list),
            }
            local shown = expanded[expandKey] and #list or math.min(#list, SEARCH_BUCKET_SHOWN)
            for i=1,shown do
                local row = CreateResultRow(list[i], needle)
                children[#children+1] = row
                navRows[#navRows+1] = {panel = row, event = "press"}
            end
            if (not expanded[expandKey]) and #list > SEARCH_BUCKET_SHOWN then
                local seeAll = gui.Label{
                    classes = {"searchSeeAll"},
                    text = string.format("See all %d", #list),
                    -- The historical "expands then disappears" bug was NOT
                    -- this handler: the input's deselect fired on the real
                    -- mousedown, cleared the text, and the resulting
                    -- edit("") dismissed the rebuilt popup ~editlag later.
                    -- deselect now keeps the query when the pointer is on
                    -- the popup, so the expansion survives.
                    click = function()
                        expanded[expandKey] = true
                        resultPanel.popup = CreateGroupedPopup(grouped, needle, expanded, searchingLabel, context)
                    end,
                }
                children[#children+1] = seeAll
                navRows[#navRows+1] = {panel = seeAll, event = "click"}
            end
        end

        -- Context group ("In this document" / "On this map" / ...): pinned
        -- ABOVE the intent buckets, additive - never replaces global reach.
        if context ~= nil and #context.results > 0 then
            AppendGroup(context.label, context.results, "context")
        end

        for _,bucket in ipairs(SEARCH_BUCKETS) do
            local list = grouped[bucket.id]
            if list ~= nil and #list > 0 then
                AppendGroup(bucket.label, list, bucket.id)
            end
        end

        if searchingLabel ~= nil then
            children[#children+1] = gui.Label{
                classes = {"searchSeeAll"},
                text = "Searching for more results...",
            }
        end

        local m_cursor = 0
        local popupPanel

        local function MoveCursor(delta)
            if #navRows == 0 then
                return
            end
            local newCursor = m_cursor + delta
            if newCursor < 1 then
                newCursor = #navRows
            elseif newCursor > #navRows then
                newCursor = 1
            end
            local old = navRows[m_cursor]
            if old ~= nil and old.panel.valid then
                old.panel:SetClass("searchfocus", false)
            end
            m_cursor = newCursor
            local row = navRows[m_cursor]
            if row.panel.valid then
                row.panel:SetClass("searchfocus", true)
            end
            -- Keep the selection in view (vscrollPosition: 1 = top, 0 =
            -- bottom). Approximate by cursor fraction; exact row offsets are
            -- not exposed, and the popup only scrolls once a bucket expands.
            if #navRows > 1 then
                popupPanel.vscrollPosition = 1 - (m_cursor - 1) / (#navRows - 1)
            end
        end

        popupPanel = gui.Panel{
            classes = {"bordered", "bg", "searchResultsPanel"},
            flow = "vertical",
            width = 368,
            height = "auto",
            halign = "center",
            valign = "bottom",
            vscroll = true,
            children = children,

            uparrow = function(element)
                MoveCursor(-1)
            end,
            downarrow = function(element)
                MoveCursor(1)
            end,
            activateSelection = function(element)
                local row = navRows[math.max(m_cursor, 1)]
                if row ~= nil and row.panel.valid then
                    row.panel:FireEvent(row.event)
                end
            end,
        }
        return popupPanel
    end

    -- Empty-state: focusing the search box with no query shows the recently
    -- activated results as a "Recent" group - same popup machinery, so it
    -- gets the cap-5/"See all" idiom and keyboard navigation for free.
    local function ShowRecentResults()
        if #m_recentResults == 0 then
            return false
        end
        resultPanel.data.searchSignature = nil
        resultPanel.data.searchStatus = nil
        resultPanel.data.isNoResultsPopup = false
        resultPanel.popupsInheritStyles = true
        resultPanel.popup = CreateGroupedPopup({}, "", {}, nil, {label = "Recent", results = m_recentResults})
        return true
    end

    local executeSearch = function(text)
        if TopBar.HasCustomSearch() then
            return TopBar.ExecuteCustomSearch(text)
        end

        local status = true --search is good and complete.
        text = string.trim(string.lower(text))
        --Broadcast the live query so echo surfaces (the tac-panel Features
        --glow) can respond in place. Published on every keystroke including
        --the empty/clear case so the glow turns off when the query is cleared.
        Search.SetGlobalQuery(text)
        if text == "" then
            local skip = resultPanel.data.skipRecentsOnce
            resultPanel.data.skipRecentsOnce = false
            if (not skip) and resultPanel.hasInputFocus and ShowRecentResults() then
                return status
            end
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
                itemCopy.bucket = "apptools"
                results[#results+1] = itemCopy
            end
        end

        --search keybindings.
        for key,bind in pairs(Keybinds.GetBindings()) do
            if string.find(string.lower(bind.name), text, 1, true) ~= nil then
                local itemCopy = DeepCopy(bind)
                itemCopy.score = scoreMatch(itemCopy.name, text)
                itemCopy.text = string.format("<b>%s</b> (Shortcut)", itemCopy.name)
                itemCopy.bucket = "apptools"
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
                itemCopy.bucket = "apptools"
                itemCopy.click = function()
                    dmhub.ShowPlayerSettings{search = itemCopy.description}
                end

                results[#results+1] = itemCopy
            end
        end

        local links = CustomDocument.SearchLinks(text)
        for _,link in ipairs(links) do
            link.score = scoreMatch(link.name, text)
            -- Render name + a muted type-label chip (like tokens), instead of
            -- baking "(Map)"/"(Document)" into the text -- so maps/journals tag
            -- consistently with the rest of the grouped results.
            link.typeLabel = link.type
            link.bucket = BucketForLinkType(link.type)
            -- A map note's backing document also surfaces here as a "Document".
            -- Key it by title so that, when the note is pinned in "On this map",
            -- this journal twin is deduped out of the bucket. (When the map
            -- context is suppressed the key is unowned, so the document still
            -- shows -- the note stays reachable.)
            if link.type == "Document" then
                link.dedupKey = "mapdoc:" .. string.lower(link.name or "")
            end
            link.click = function()
                CustomDocument.OpenContent(CustomDocument.ResolveLink(link.link))
            end
            results[#results+1] = link
        end

        for k,doc in pairs(assets.pdfDocumentsTable) do
            if not doc.hidden then

                local pdfresults = searchPDF(k, doc, text)
                if type(pdfresults) == "table" then
                    for _,r in ipairs(pdfresults) do
                        r.bucket = "rulebooks"
                        results[#results+1] = r
                    end
                else
                    status = false --search should be repeated.
                end
            end
        end

        -- Registered global-search providers (compendium content, tokens, ...).
        -- They share the chunk-1 matcher and carry their own bucket + activate.
        local needle = Search.Normalize(text)
        for _,r in ipairs(Search.CollectProviderResults(needle)) do
            results[#results+1] = r
        end

        -- Context-sensitive search: when an artifact (PDF viewer, ...) is
        -- open it contributes its own scoped group, pinned above the
        -- buckets. A pending context (async per-doc search) repeats the
        -- search the same way the global PDF path does.
        local context = Search.CollectContextResults(needle)
        if context ~= nil and context.pending then
            status = false
        end

        -- Option A dedupe: an item already shown in the active context group
        -- (a placed token, a map note) should not ALSO repeat in the intent
        -- buckets below. Providers stamp a dedupKey on comparable results; the
        -- context group is the home, the bucket is the fallback. When no
        -- context is active ownedKeys is empty, so nothing is suppressed and
        -- global reach is preserved.
        local ownedKeys = {}
        if context ~= nil then
            for _,r in ipairs(context.results) do
                if r.dedupKey ~= nil then
                    ownedKeys[r.dedupKey] = true
                end
            end
        end

        -- Group the flat results into the intent buckets, ranked by score, and
        -- cap each bucket to the render/store budget.
        table.stable_sort(results, function(a,b) return (a.score or 0) > (b.score or 0) end)

        local grouped = {}
        for _,r in ipairs(results) do
            if r.dedupKey == nil or not ownedKeys[r.dedupKey] then
                local b = r.bucket or "apptools"
                local list = grouped[b]
                if list == nil then
                    list = {}
                    grouped[b] = list
                end
                if #list < SEARCH_BUCKET_STORE then
                    list[#list+1] = r
                end
            end
        end

        if #results == 0 and (context == nil or #context.results == 0) then
            resultPanel.data.searchSignature = nil
            resultPanel.data.searchStatus = nil
            if resultPanel.popup == nil or not resultPanel.data.isNoResultsPopup then
                resultPanel.data.isNoResultsPopup = true
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
            if status then
                track("search_titlebar", {
                    query = text,
                    hasResults = false,
                    resultCount = 0,
                    deduplicate = 0.5,
                    dailyLimit = 50,
                })
            end
            return status
        end

        -- Flicker guard: re-fire of the same query (e.g. the async PDF
        -- repeat-search) rebuilds nothing if the visible result set is
        -- unchanged. The signature is the ordered names across the context
        -- group + all buckets, so an expanded "See all" state survives an
        -- identical repeat.
        local sigParts = {}
        if context ~= nil then
            for _,r in ipairs(context.results) do
                sigParts[#sigParts+1] = r.name or r.text or ""
            end
        end
        for _,bucket in ipairs(SEARCH_BUCKETS) do
            local list = grouped[bucket.id]
            if list ~= nil then
                for _,r in ipairs(list) do
                    sigParts[#sigParts+1] = r.name or r.text or ""
                end
            end
        end
        local signature = table.concat(sigParts, "\1")

        if resultPanel.popup ~= nil
            and resultPanel.data.searchStatus == status
            and resultPanel.data.searchSignature == signature then
            --no need to invalidate menu.
            return status
        end

        resultPanel.data.searchStatus = status
        resultPanel.data.searchSignature = signature
        resultPanel.data.isNoResultsPopup = false

        resultPanel.popupsInheritStyles = true
        resultPanel.popup = CreateGroupedPopup(grouped, needle, {}, cond(status, nil, true), context)

        if status then
            track("search_titlebar", {
                query = text,
                hasResults = #results > 0,
                resultCount = #results,
                deduplicate = 0.5,
                dailyLimit = 50,
            })
        end

        return status
    end

    resultPanel = gui.SearchInput{
        bgimage = true,
        width = 368,
        height = 20,
        halign = "right",
        valign = "center",
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
            if string.trim(element.text or "") == "" then
                ShowRecentResults()
            end
        end,
        -- Click-to-focus on the empty box shows the recents. The engine has
        -- no input-gained-focus event (deselect has no symmetric select), so
        -- watch for the rising edge of hasInputFocus on a light think.
        thinkTime = 0.2,
        think = function(element)
            local focused = element.hasInputFocus
            if focused and (not element.data.hadInputFocus)
                and element.popup == nil
                and string.trim(element.text or "") == "" then
                ShowRecentResults()
            end
            element.data.hadInputFocus = focused
        end,
        -- Keyboard navigation of the results popup: arrows move the selection,
        -- Enter activates it (or the first result when nothing is selected).
        -- Same forward-to-popup idiom as the GoblinScript autocomplete.
        uparrow = function(element)
            if element.popup ~= nil then
                element.popup:FireEventTree("uparrow")
            end
        end,
        downarrow = function(element)
            if element.popup ~= nil then
                element.popup:FireEventTree("downarrow")
            end
        end,
        submit = function(element)
            if element.popup ~= nil then
                element.popup:FireEventTree("activateSelection")
            end
        end,
        deselect = function(element)
            -- A real click inside the results popup also blurs this input
            -- (deselect fires on the mousedown). Clearing the text here makes
            -- the engine fire edit("") after editlag, which runs
            -- executeSearch("") and dismisses the popup right after the row's
            -- click lands -- "See all" would briefly expand then vanish.
            -- Only treat the blur as a dismissal when the pointer is OUTSIDE
            -- the popup (mousePoint is normalized 0..1 inside a panel). The
            -- engine already closes the popup itself on outside clicks.
            local popup = element.popup
            if popup ~= nil and popup.valid then
                local mp = popup.mousePoint
                if mp ~= nil and mp.x >= 0 and mp.x <= 1 and mp.y >= 0 and mp.y <= 1 then
                    return
                end
            end
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

    local g_bugReportLink = "https://discord.gg/x2yEdNFmUB"

    local menuBar = gui.Panel{
        id = "menuBarPanel",
        classes = {"titleBarSurface"},
        width = "100%",
        height = 32,
        floating = true,
        valign = "top",
        bgimage = true,
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
                local items = {
                    {
                        text = "Settings",
                        icon = "panels/hud/gear.png",
                        click = function()
                            dmhub.ShowPlayerSettings()
                        end,
                    },
                }

                for _,storeItem in ipairs(GetStoreMenuItems()) do
                    items[#items+1] = storeItem
                end

                items[#items+1] = {
                    text = "Quit to Desktop",
                    icon = "game-icons/power-button.png",
                    click = function()
                        dmhub.QuitApplication()
                    end,
                }

                return items
            end,
        },

        CreateCodexMenuItem{
            name = "Codex",
            icon = "ui-icons/codex-logo.png",
            menuItems = function()
			    local items = table.filter(LaunchablePanel.GetMenuItems(), function(item) return item.menu == nil and item.text ~= "Development Tools" end)
                local storeItems = GetStoreMenuItems()
                for i=#storeItems,1,-1 do
                    table.insert(items, 1, storeItems[i])
                end
                return items
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

        CreateCodexMenuItem{
            name = "Bug Reports",
            menuItems = function()
                return {
                    {
                        text = "How to Report a Bug",
                        click = function()
                            gamehud:ModalDialog{
                                styles = ThemeEngine.GetStyles(),
                                title = "Reporting Bugs",
                                gui.Panel{
                                    width = 900,
                                    height = 500,
                                    vscroll = true,
                                    flow = "vertical",

                                    gui.Label{
                                        width = 860,
                                        height = "auto",
                                        fontSize = 20,
                                        bold = true,
                                        textWrap = true,
                                        text = "<b>You will be sent to the Draw Steel Codex Discord where you can report bugs.</b>",
                                        vmargin = 10,
                                    },

                                    gui.Label{
                                        width = 860,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        text = "When you encounter a bug, please follow these steps to make your report as helpful as possible:",
                                        tmargin = 4,
                                        bmargin = 8,
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- Post each bug as a <b>separate post</b> in the #bug-reports channel (click Proceed to go there). This allows us to triage bugs and ensures they are tracked until fixed.",
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- Check if you can <b>consistently reproduce</b> the bug. If so, post an exact set of steps to reproduce it.",
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- Consider posting a video demonstrating the bug for added clarity.",
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- If a bug occurs, immediately press <b>~</b> (tilde) to open the Codex error log. Include any error message with your report -- a screenshot is usually sufficient and makes the full log file unnecessary.",
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- The Codex log file is at <b>C:\\Users\\(your username)\\AppData\\LocalLow\\MCDM\\Codex</b> on Windows (press <b>F1</b> in the Codex to open it in Notepad). On Mac it is at <b>Library/Logs/MCDM/Codex/Player.log</b>. The log can be zipped to reduce size. Note it contains a small amount of personal data, so you may prefer to send it privately to a developer.",
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- If a bug seems specific to one game, post the <b>game invite code</b>. Doing so implicitly gives permission for Codex developers to enter your game to investigate.",
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- Please check back on your bug reports in case a developer asks for additional information.",
                                    },

                                    gui.Label{
                                        width = 840,
                                        height = "auto",
                                        fontSize = 15,
                                        textWrap = true,
                                        lmargin = 16,
                                        vmargin = 4,
                                        text = "- After a bug is resolved, please re-test and reply to confirm whether it is fixed. If not, include the version number you tested with so we can confirm you received the update.",
                                    },
                                },
                                buttons = {
                                    {
                                        text = "Proceed",
                                        click = function()
                                            dmhub.OpenURL(g_bugReportLink)
                                        end,
                                    },
                                    {
                                        text = "Copy Link",
                                        click = function()
                                            dmhub.CopyToClipboard(g_bugReportLink)
                                        end,
                                    },
                                    {
                                        text = "Close",
                                        escapeActivates = true,
                                    },
                                },
                            }
                        end,
                    },
                }
            end,
        },

        m_presentationBar,
        CreateStatusBar(),
        m_searchBar,
    }

    local titleBarStyleExtras = {
        -- Title-bar bar surface paints with the scheme's barTrack
        -- gradient. bgcolor = "white" is the image-tint multiplier:
        -- without it the cascade's @bg tints the gradient down to
        -- near-black on dark schemes.
        {
            selectors = {"titleBarSurface"},
            bgimage = true,
            bgcolor = "white",
            gradient = "@barTrack",
        },

        -- Title-bar search field: bordered variant + behavior visibility.
        -- DefaultStyles' searchInput rule ships borderWidth=0; the title
        -- bar wants a thin frame so we add it here at the surface.
        {
            selectors = {"searchInput"},
            borderWidth = 1,
            borderColor = "@border",
        },
        {
            selectors = {"searchInput", "focus"},
            borderColor = "@fgStrong",
        },
        {
            selectors = {"searchInput", "~ingame", "~searchoverride"},
            hidden = 1,
        },

        -- Grouped global-search results popup.
        {
            selectors = {"searchResultsPanel"},
            pad = 6,
            maxHeight = 600,
            borderBox = true,
        },
        {
            selectors = {"searchGroupHeading"},
            width = "100%-12",
            height = "auto",
            halign = "left",
            color = "@accent",
            fontSize = 13,
            tmargin = 6,
            bmargin = 2,
            hmargin = 6,
        },
        {
            selectors = {"searchResultRow"},
            width = "100%-12",
            height = "auto",
            halign = "left",
            valign = "center",
            bgimage = true,
            bgcolor = "clear",
            pad = 4,
            hmargin = 6,
            borderBox = true,
        },
        {
            selectors = {"searchResultRow", "hover"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"searchResultRow", "searchfocus"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"searchSeeAll", "searchfocus"},
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        {
            -- 20px to line up with the placed-token portraits (CreateTokenImage
            -- at 20) so the name column starts at the same x on every row.
            selectors = {"searchResultIcon"},
            width = 20,
            height = 20,
            halign = "left",
            valign = "center",
            rmargin = 8,
            bgcolor = "white",
        },
        {
            -- Map-note pin: a small dark disc with the bubble's number/glyph,
            -- echoing the on-map info-bubble marker. Same 20px box as the other
            -- leading icons so the name column lines up.
            selectors = {"searchResultBubble"},
            width = 20,
            height = 20,
            halign = "left",
            valign = "center",
            rmargin = 8,
            bgimage = "panels/square.png",
            bgcolor = "black",
            cornerRadius = "50% height",
            borderWidth = 1,
            borderColor = "@fg",
            color = "@fg",
            fontSize = 11,
            textAlignment = "center",
        },
        {
            selectors = {"searchResultName"},
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            color = "@fg",
            fontSize = 16,
        },
        {
            selectors = {"searchResultType"},
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            color = "@fgMuted",
            fontSize = 12,
            lmargin = 8,
        },
        {
            selectors = {"searchResultSub"},
            width = "auto",
            height = "auto",
            halign = "left",
            color = "@fgMuted",
            fontSize = 12,
        },
        {
            selectors = {"searchSeeAll"},
            width = "100%-12",
            height = "auto",
            halign = "left",
            color = "@accentHover",
            fontSize = 13,
            pad = 4,
            hmargin = 6,
            borderBox = true,
        },
    }

    -- Tree-wide invalidation pulse for theme repaints. Reassigning .styles
    -- updates the rule array but doesn't mark descendants dirty, so without
    -- a forced re-cascade the bar keeps painting the previous scheme until
    -- something (e.g. hover) churns a pseudo-class. Toggling a no-op class
    -- across the subtree marks every descendant dirty. The class itself is
    -- not referenced by any rule -- only the flip matters.
    local themeRefreshTick = false

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

        styles = ThemeEngine.MergeStyles(titleBarStyleExtras),

		--dmControlsPanel,
		--layersPanel,
        menuBar,
	}

    -- Force a re-cascade once the engine signals the game is fully loaded
    -- (and therefore every mod's color schemes are registered). The cascade
    -- computed at construction time may resolve before custom-scheme mods
    -- have finished registering, leaving the bar painted with the wrong
    -- scheme until something else invalidates the tree.
    dmhub.RegisterEventHandler("EnterGame", function()
        if topBarPanel and topBarPanel.valid then
            topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
            themeRefreshTick = not themeRefreshTick
            topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
        end
    end)

    -- Subscribe to theme changes so the bar repaints live when the user
    -- switches scheme via Settings instead of waiting for the next reload.
    ThemeEngine.OnThemeChanged(mod, function()
        if topBarPanel and topBarPanel.valid then
            topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
            themeRefreshTick = not themeRefreshTick
            topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
        end
    end)

	return topBarPanel
end

dmhub.titleBarContainer.sheet = CreateTopBar()