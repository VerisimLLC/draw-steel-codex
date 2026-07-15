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
    default = true,
    storage = "preference",
}

g_devInventorySetting:Set(true)

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

    --mainmenu = true shows the item only on the main menu; mainmenu = "always"
    --shows it both on the main menu and in-game; otherwise in-game only.
    local visibilityClass
    if m_mainmenu == "always" then
        visibilityClass = nil
    elseif m_mainmenu then
        visibilityClass = "mainmenuOnly"
    else
        visibilityClass = "ingameOnly"
    end

	local resultPanel = {

        classes = {"menuItem", visibilityClass},
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

        -- Dev-only note: when this game is loading its assets from a local
        -- directory (the "local assets" developer feature -- a custom data
        -- directory that replaces the game's cloud assets), flag it here so it
        -- is obvious at a glance that this is a dev game. Hovering shows the
        -- source directory; clicking reveals it in the OS file browser. Empty
        -- (zero-width) for every normal game. LocalAssetsStatus /
        -- RevealInFileBrowser are read-and-compared-to-nil so an older engine
        -- build (before the bridge exists) simply shows nothing.
        gui.Label{
            minFontSize = 10,
            bold = true,
            color = "#f0a030",
            width = "auto",
            height = "100%",
            valign = "center",
            rmargin = 10,
            text = "",
            data = { dir = nil },
            linger = function(element)
                local dir = element.data.dir
                if dir == nil or dir == "" then
                    return
                end
                gui.Tooltip(string.format("Dev game: assets are loading from a local directory --\n%s\n\nClick to open it in your file browser.", dir))(element)
            end,
            click = function(element)
                local dir = element.data.dir
                if dir ~= nil and dir ~= "" and dmhub.RevealInFileBrowser ~= nil then
                    dmhub.RevealInFileBrowser(dir)
                end
            end,
            multimonitor = {"showstatusbar"},
            monitor = function(element)
                element.thinkTime = cond(g_showStatusBarSetting:Get(), 1, nil)
                element.data.dir = nil
                element.text = ""
            end,
            thinkTime = cond(g_showStatusBarSetting:Get(), 1, nil),
            think = function(element)
                if (not dmhub.inGame) or dmhub.isLobbyGame or dmhub.LocalAssetsStatus == nil then
                    element.data.dir = nil
                    element.text = ""
                    return
                end
                local status = dmhub.LocalAssetsStatus()
                if status ~= nil and status.active and status.directory ~= nil and status.directory ~= "" then
                    element.data.dir = status.directory
                    element.text = "Dev Game"
                else
                    element.data.dir = nil
                    element.text = ""
                end
            end,
        },

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
                    actionLabel = "Center on token",
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
                actionLabel = string.format("Go to page %d", m.page),
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

    -- The ordered action list for a result, primary first. Three sources, in
    -- priority order: an explicit result.actions list (the modern form), a
    -- legacy result.menuItems() function (its first entry is the primary), or a
    -- single synthesised action from result.click/activate labelled by
    -- result.actionLabel (default "Open"). The first action always mirrors what
    -- pressing the row does, so the primary chip and the row press agree.
    local function BuildResultActions(result)
        if type(result.actions) == "table" and #result.actions > 0 then
            return result.actions
        end
        if result.menuItems ~= nil then
            local ok, items = pcall(result.menuItems)
            if ok and type(items) == "table" and #items > 0 then
                return items
            end
        end
        local primaryClick = result.click or result.activate
        if primaryClick ~= nil then
            return { { text = result.actionLabel or "Open", click = primaryClick } }
        end
        return {}
    end

    -- One result row: a leading per-type icon, then a highlighted name
    -- (provider results) or preformatted text (legacy handlers), plus an
    -- optional muted type/source label on the right. Beneath the name sit an
    -- optional context line (e.g. "Signature Ability", "Level 1 Horde", or a
    -- PDF's "doc, page N") and a row of action chips that spell out what each
    -- click does (primary first, then secondaries spaced apart). Pressing the
    -- row runs the primary action; pressing a chip runs that action. Both
    -- dismiss the popup. `opts.noActions` suppresses the chip row (used by the
    -- pinned context group, which stays deliberately clean).
    local function CreateResultRow(result, needle, opts)
        opts = opts or {}
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

        -- Run a result action: record it as recent, dismiss the popup, clear
        -- the query (deselect no longer does this while the pointer is on the
        -- popup), then invoke the action. Shared by the row press and the chips
        -- so they dismiss identically.
        local function activate(clickFn)
            RecordRecentResult(result)
            -- clearing the text fires edit("") - don't let that pop the
            -- recents group right after navigating away.
            resultPanel.data.skipRecentsOnce = true
            resultPanel.popup = nil
            resultPanel.text = ""
            if clickFn ~= nil then
                clickFn()
            end
        end

        -- Name + optional context line + optional action chips, stacked. The
        -- context line (result.subLabel) stays on its OWN line rather than
        -- merged onto the right-hand type chip: Draw Steel villain/signature
        -- ability names are full sentences, so merging would clip the majority
        -- of monster-ability rows at the search box width.
        local blockChildren = { nameLabel }

        if result.subLabel ~= nil then
            blockChildren[#blockChildren+1] = gui.Label{
                classes = {"searchResultSub"},
                text = result.subLabel,
            }
        end

        -- Secondary action buttons are collected here and placed in the RIGHT
        -- column (under the type chip); the primary hint stays under the name.
        local secondaryButtons = {}
        if not opts.noActions then
            local actions = BuildResultActions(result)
            if #actions > 0 then
                -- Primary action: a muted hint ("> Open in Compendium") under
                -- the name spelling out what pressing the ROW does. Descriptive,
                -- not a button -- the row press performs it -- so single-action
                -- rows get just this line and no button at all.
                blockChildren[#blockChildren+1] = gui.Panel{
                    classes = {"searchActionLine"},
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    gui.Panel{ classes = {"searchHintArrow"} },
                    gui.Label{ classes = {"searchHintText"}, text = actions[1].text },
                }

                -- Secondary actions: small outlined buttons. swallowPress stops
                -- the press from also reaching the row (a press hits a panel AND
                -- all its parents by default), so a button runs ONLY its own
                -- action, never the row's primary as well.
                for i=2,#actions do
                    local capturedClick = actions[i].click
                    secondaryButtons[#secondaryButtons+1] = gui.Label{
                        classes = {"searchResultChip"},
                        text = actions[i].text,
                        swallowPress = true,
                        press = function(element)
                            activate(capturedClick)
                        end,
                    }
                end
            end
        end

        local nameBlock
        if #blockChildren == 1 then
            nameBlock = nameLabel
        else
            nameBlock = gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                children = blockChildren,
            }
        end

        -- RIGHT column: the muted type chip on top, then any secondary action
        -- buttons stacked beneath it (e.g. a monster ability's "Place on Map"
        -- sits under the monster name). Omitted when there is neither.
        local rightBlock = nil
        local rightChildren = {}
        if result.typeLabel ~= nil then
            rightChildren[#rightChildren+1] = gui.Label{
                classes = {"searchResultType"},
                text = result.typeLabel,
            }
        end
        for _,btn in ipairs(secondaryButtons) do
            rightChildren[#rightChildren+1] = btn
        end
        if #rightChildren > 0 then
            rightBlock = gui.Panel{
                classes = {"searchResultRight"},
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "top",
                children = rightChildren,
            }
        end

        local rowChildren = { iconPanel, nameBlock }
        if rightBlock ~= nil then
            rowChildren[#rowChildren+1] = rightBlock
        end

        return gui.Panel{
            classes = {"searchResultRow"},
            flow = "horizontal",
            press = function()
                activate(result.click or result.activate)
            end,
            children = rowChildren,
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

        local function AppendGroup(label, list, expandKey, noActions)
            children[#children+1] = gui.Label{
                classes = {"searchGroupHeading"},
                text = string.format("<b>%s</b> (%d)", label, #list),
            }
            local shown = expanded[expandKey] and #list or math.min(#list, SEARCH_BUCKET_SHOWN)
            for i=1,shown do
                local row = CreateResultRow(list[i], needle, {noActions = noActions})
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
            -- Context rows render their action hint like every other row. The
            -- noActions hook remains for any future group that wants to opt out.
            AppendGroup(context.label, context.results, "context", context.noActions)
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
            -- Mirrors the search box's dockscale-tracking width (HB1), but
            -- never shrinks below the old fixed 368 -- cards in this popup
            -- must never wrap at small dock scales. At scale > 1 the popup
            -- grows to match the (now wider) box above it. Rebuilt fresh per
            -- search, so a value computed at construction stays current.
            width = math.max(368, math.floor(364 * (dmhub.GetSettingValue("dockscale") or 1))),
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
                itemCopy.actionLabel = "Open"
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
                itemCopy.actionLabel = "Edit in Settings"
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
                itemCopy.actionLabel = "Open in Settings"
                itemCopy.click = function()
                    dmhub.ShowPlayerSettings{search = itemCopy.description}
                end

                results[#results+1] = itemCopy
            end
        end

        local links = CustomDocument.SearchLinks(text)
        for _,link in ipairs(links) do
            -- Compendium content (markdown-table entries like items/titles, and
            -- monsters) is owned by the dedicated compendium-content / monsters
            -- search providers, which give richer actions ("Open in Compendium",
            -- "Place on Map" / "Edit Monster") and DM-gating. SearchLinks emits
            -- these only for the document link picker; skip them here so the
            -- title-bar search shows no dead duplicate rows (and does not leak
            -- monster names to players). Prefix suggestions ("Search items...")
            -- and rulebook / journal / map links are kept.
            if BucketForLinkType(link.type) == "compendium" and not link.isPrefix then
                goto continue
            end
            link.score = scoreMatch(link.name, text)
            -- Render name + a muted type-label chip (like tokens), instead of
            -- baking "(Map)"/"(Document)" into the text -- so maps/journals tag
            -- consistently with the rest of the grouped results.
            link.typeLabel = link.type
            link.bucket = BucketForLinkType(link.type)
            -- Primary-action copy by link kind (rulebooks, journals, maps); a
            -- prefix suggestion ("Search items...") narrows the query, and any
            -- other markdown-table entry opens its content.
            if link.isPrefix then
                link.actionLabel = "Search this category"
            elseif link.type == "PDF Document" or link.type == "PDF Fragment" then
                link.actionLabel = "Open rulebook"
            elseif link.type == "Document" then
                link.actionLabel = "Open journal"
            elseif link.type == "Map" then
                link.actionLabel = "Go to map"
            else
                link.actionLabel = "Open"
            end
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
            ::continue::
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
        -- Tracks the right dock's rendered width (364 * dockscale, default 1.0)
        -- so the box lines up with the dock below it at any scale (HB1). Kept
        -- live by the think handler below. borderBox is load-bearing:
        -- gui.SearchInput ships hpad=24 WITHOUT borderBox, so the rendered box
        -- would otherwise be 48px wider than the declared width and overhang
        -- the dock (James field report, 2026-07-03).
        borderBox = true,
        width = math.floor(364 * (dmhub.GetSettingValue("dockscale") or 1)),
        height = 20,
        halign = "right",
        valign = "center",
        pad = 2,
        popupPositioning = "panel",
        placeholderText = cond(dmhub.GetCommandBinding("find"), string.format("Search (%s)...", dmhub.GetCommandBinding("find") or ""), "Search..."),
        inputEvents = { "find" },
        -- Trailing debounce: coalesce keystrokes so a fast typist does not run
        -- the provider sweep (all ~574 monsters etc.) on every key. Kept at
        -- 0.1s -- 0.2s felt laggy; the typed text always updates instantly and
        -- only the result computation waits this long.
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
            -- Live-follow the dock scale setting (HB1) so a mid-session
            -- change to the slider is reflected without a reload. Cheap
            -- setting read on a 0.2s tick; only touches .width when it
            -- actually changed.
            local w = math.floor(364 * (dmhub.GetSettingValue("dockscale") or 1))
            if element.data.appliedSearchWidth ~= w then
                element.data.appliedSearchWidth = w
                element.selfStyle.width = w
            end

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

--H-BAR: global audio indicator glyph, left of the search box. Three states
--(muted / playing / idle) polled on a light think; a press opens a compact
--mixer popover built from Audio.lua's exported fader factories so the top
--bar, dock, and Studio Mixer share ONE fader implementation. If Audio.lua's
--export is not loaded (should not happen given load order, but this is a
--cross-module read) the glyph simply does not open a popup.
local function CreateAudioIndicator()
    local resultPanel

    --Safe read of the "localmuted" setting. It is registered by a game mod
    --(AudioMain.lua), so at the title screen and during the mid-Lua-reload
    --teardown window the id does not exist -- GetSettingValue on a missing id
    --both logs "Could not find setting" and throws a native NRE (seen once
    --per boot, 2026-07-03). HasSetting is the non-logging existence probe.
    local function IsLocalMuted()
        return dmhub.HasSetting("localmuted") and dmhub.GetSettingValue("localmuted") == true
    end

    local function ComputeState()
        --The engine audio system (and the GameController backing audio.muted)
        --is not initialized during the title screen / early game load, where
        --this think already runs. MERELY TOUCHING audio.muted or
        --audio.currentlyPlaying there raises a native NullReference that the
        --engine logs/reports even when Lua pcall catches it (player-window
        --error dialog, 2026-07-03) -- so gate on the Audio.lua export, which
        --only exists once the game's audio mods are loaded, and do not call
        --into audio.* at all before then. The pcall stays as a second line of
        --defense for reload teardown windows.
        if rawget(_G, "g_drawSteelAudioBar") == nil then
            return "idle"
        end
        local ok, state = pcall(function()
            if audio.muted or IsLocalMuted() then
                return "muted"
            end
            for _,_ in pairs(audio.currentlyPlaying) do
                return "playing"
            end
            return "idle"
        end)
        if not ok then
            return "idle"
        end
        return state
    end

    --Muted from this client's perspective: its own local mute, or the game-wide
    --mute. Used for glyph/toggle display state; which layer the TOGGLE writes is
    --role-branched at the press site.
    local function IsClientMuted()
        return audio.muted or IsLocalMuted()
    end

    local function BuildPopover()
        local bar = rawget(_G, "g_drawSteelAudioBar")
        if bar == nil then
            return nil
        end

        -- Now-playing line is a snapshot at open time -- this is a transient
        -- popover (same accepted pattern as the Studio's bindings popover),
        -- not a live-refreshing panel.
        local nowPlayingName = bar.PrimaryPlayingName()

        --Muted-cause line (DJ delegation decision 4): the popover top tier is
        --now PERSONAL for every role, so when the glyph shows muted the cause
        --may be either layer - name it. Snapshot popover, but both mute
        --toggles below refresh this line on press so it never contradicts an
        --action taken inside the popover itself.
        local mutedCauseLine
        local function RefreshMutedCause()
            if audio.muted then
                mutedCauseLine.text = "The table is muted for everyone."
                mutedCauseLine:SetClass("collapsed", false)
            elseif IsLocalMuted() then
                mutedCauseLine.text = "Your personal mute is on."
                mutedCauseLine:SetClass("collapsed", false)
            else
                mutedCauseLine:SetClass("collapsed", true)
            end
        end
        mutedCauseLine = gui.Label{
            classes = {"sizeXxs", "fgMuted", "collapsed"},
            width = "100%",
            height = "auto",
            textWrap = true,
        }

        --Personal tier (DJ delegation decision 4): EVERY role, including the
        --Director, gets the personal master + personal mute here - reflex
        --control keeps reflex semantics for every human. The game-wide mute
        --moved into the broadcast block below as a labeled control (PR-note
        --obligation: this repurposes the DM's trained mute-glyph behavior).
        local muteToggle = gui.Panel{
            bgcolor = "white",
            width = 16,
            height = 16,
            valign = "center",
            hmargin = 4,
            press = function(element)
                dmhub.SetSettingValue("localmuted", not IsLocalMuted())
                -- The bar glyph self-heals on its 0.5s think, but this copy
                -- lives in a snapshot popover -- swap it now or it reads
                -- stale until the popover is reopened.
                element:SetClass("muted", IsClientMuted())
                RefreshMutedCause()
            end,
            linger = function(element)
                gui.Tooltip("Mute (only you)")(element)
            end,
            styles = {
                { bgimage = "ui-icons/ph-speaker-high-fill.png" },
                { selectors = {"muted"}, bgimage = "ui-icons/ph-speaker-slash-fill.png" },
                { selectors = {"hover"}, brightness = 2 },
            },
            create = function(element)
                element:SetClass("muted", IsClientMuted())
            end,
        }
        muteToggle:SetClass("muted", IsClientMuted())

        -- Mute rides the RIGHT end of the Master row (its own row read as
        -- orphaned chrome -- James field report, 2026-07-03). Master keeps the
        -- left slot so its slider stays column-aligned with the Levels sliders
        -- below; MakeFaderRow hardcodes width 100%, so the fader row is
        -- narrowed post-construction to make room for the toggle.
        --Personal per-user master for every role - the same "volume" setting
        --as Settings->Audio's Master Volume. (The game-wide master lives in
        --the dock/Studio/Settings; it is no longer in this popover.)
        local masterSlider
        if bar.MakePersonalFader == nil then
            --Fallback for a stale export during partial reloads.
            masterSlider = bar.MakeMasterFader()
        else
            masterSlider = bar.MakePersonalFader("volume")
        end
        local masterFaderRow = bar.MakeFaderRow("Master", masterSlider, false)
        masterFaderRow.selfStyle.width = "100%-26"
        local masterRow = gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 22,
            valign = "center",
            masterFaderRow,
            muteToggle,
        }

        local children = {
            -- "Now Playing" header (bold, pinned white -- the popover bg is
            -- known-dark in every scheme) with the track title on its own
            -- line beneath, mirroring the Studio's Now Playing card.
            gui.Label{
                classes = {"sizeXs", "bold"},
                color = "#ffffff",
                width = "100%",
                height = "auto",
                text = "Now Playing",
            },
            gui.Label{
                classes = {"sizeXs", cond(nowPlayingName == nil, "fgMuted", nil)},
                width = "100%",
                height = "auto",
                textWrap = false,
                textOverflow = "ellipsis",
                text = nowPlayingName or "Nothing playing",
            },
            masterRow,
            mutedCauseLine,
            --Personal-tier caption for EVERY role now (decision 4): the tier
            --above is personal regardless of who you are; the broadcast block
            --below is what plays to the table.
            gui.Label{
                classes = {"sizeXxs", "fgMuted"},
                width = "100%",
                height = "auto",
                textWrap = true,
                text = "These change your mix only.",
            },
        }
        RefreshMutedCause()

        --Broadcast tier: Director or DJ only (DJ delegation decision 4). All
        --game-wide controls live here, including the game-wide mute as a
        --labeled control (promoted from the old master-row glyph tooltip).
        if bar.CanControlAudio ~= nil and bar.CanControlAudio() then
            children[#children+1] = gui.Label{
                classes = {"sizeXs", "fgMuted"},
                width = "100%",
                height = "auto",
                text = "Levels",
                tmargin = 4,
            }
            children[#children+1] = bar.MakeFaderRow("Music", bar.MakeBroadcastFader("music"), false)
            children[#children+1] = bar.MakeFaderRow("Ambience", bar.MakeBroadcastFader("ambience"), false)
            children[#children+1] = bar.MakeFaderRow("Effects", bar.MakeBroadcastFader("effects"), false)
            children[#children+1] = bar.MakeFaderRow("UI Sounds", bar.MakeBroadcastFader("uisounds"), false)
            children[#children+1] = bar.MakeFaderRow("Anthem", bar.MakeBroadcastFader("anthem"), false)

            local gameMuteToggle = gui.Panel{
                bgcolor = "white",
                width = 16,
                height = 16,
                valign = "center",
                hmargin = 4,
                press = function(element)
                    audio.muted = not audio.muted
                    audio.UploadMuted()
                    element:SetClass("muted", audio.muted)
                    muteToggle:SetClass("muted", IsClientMuted())
                    RefreshMutedCause()
                end,
                styles = {
                    { bgimage = "ui-icons/ph-speaker-high-fill.png" },
                    { selectors = {"muted"}, bgimage = "ui-icons/ph-speaker-slash-fill.png" },
                    { selectors = {"hover"}, brightness = 2 },
                },
                create = function(element)
                    element:SetClass("muted", audio.muted)
                end,
            }
            children[#children+1] = gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 22,
                valign = "center",
                tmargin = 4,
                gui.Label{
                    classes = {"sizeXs"},
                    text = "Mute for everyone",
                    width = "100%-26",
                    height = "auto",
                    valign = "center",
                },
                gameMuteToggle,
            }

            children[#children+1] = gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                tmargin = 4,
                gui.Button{
                    classes = {"sizeXs"},
                    text = "Stop all audio",
                    width = "auto",
                    height = 22,
                    hpad = 8,
                    borderBox = true,
                    hmargin = 3,
                    linger = function(element)
                        gui.Tooltip("Stop all audio. Also cancels auto game-mode music.")(element)
                    end,
                    press = function()
                        bar.StopAll()
                        resultPanel.popup = nil
                    end,
                },
                gui.Button{
                    classes = {"sizeXs"},
                    text = "Open Audio Studio",
                    width = "auto",
                    height = 22,
                    hpad = 8,
                    borderBox = true,
                    hmargin = 3,
                    press = function()
                        resultPanel.popup = nil
                        LaunchablePanel.LaunchPanelByName("Audio Studio")
                    end,
                },
            }
        end

        return gui.Panel{
            classes = {"bordered", "bg"},
            flow = "vertical",
            width = 340,
            height = "auto",
            pad = 8,
            borderBox = true,
            halign = "right",
            valign = "bottom",
            children = children,
        }
    end

    resultPanel = gui.Panel{
        classes = {"audioIndicator"},
        width = 18,
        height = 18,
        valign = "center",
        hmargin = 6,
        bgcolor = "white",
        bgimage = "ui-icons/ph-speaker-high-fill.png",

        linger = function(element)
            gui.Tooltip("Audio controls")(element)
        end,

        press = function(element)
            element.popupsInheritStyles = true
            element.popup = BuildPopover()
        end,

        -- Run the state logic once at construction too: without this the
        -- glyph renders its constructor defaults (volume icon, full opacity)
        -- for up to one think period even when muted/idle at build time.
        create = function(element)
            element:FireEvent("think")
        end,

        thinkTime = 0.5,
        think = function(element)
            local state = ComputeState()
            if element.data.audioIndicatorState == state then
                return
            end
            element.data.audioIndicatorState = state

            if state == "muted" then
                element.bgimage = "ui-icons/ph-speaker-slash-fill.png"
                element.selfStyle.opacity = 1
            elseif state == "playing" then
                element.bgimage = "ui-icons/ph-speaker-high-fill.png"
                element.selfStyle.opacity = 1
            else
                element.bgimage = "ui-icons/ph-speaker-none-fill.png"
                element.selfStyle.opacity = 0.4
            end
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
    local m_audioIndicator = CreateAudioIndicator()
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

    --Shows the feedback dialog for a report begun with dmhub.BeginBugReport.
    --The report already holds a screenshot captured before the dialog appeared.
    --feedbackType is "bug", "feature" or "feedback"; the log file is only
    --offered on bug reports.
    local function CreateBugReportDialog(report, feedbackType)
        local kinds = {
            bug = {
                title = "Report a Bug",
                intro = "Describe the bug below and submit it directly to the Codex developers. Please make a separate report for each bug.",
                placeholder = "Describe the bug: what happened, and what you expected to happen instead. If you can, include exact steps to reproduce it.",
                thanks = "Your bug report has been submitted. Thank you!",
            },
            feature = {
                title = "Request a Feature",
                intro = "Describe the feature you would like below and it will be submitted directly to the Codex developers.",
                placeholder = "Describe the feature you would like, and the problem it would solve for you.",
                thanks = "Your feature request has been submitted. Thank you!",
            },
            feedback = {
                title = "Send Feedback",
                intro = "Share your feedback below and it will be submitted directly to the Codex developers.",
                placeholder = "Tell us what you think: what is working well, and what could be better?",
                thanks = "Your feedback has been submitted. Thank you!",
            },
        }

        local kindInfo = kinds[feedbackType]
        if kindInfo == nil then
            feedbackType = "bug"
            kindInfo = kinds.bug
        end

        local isBugReport = (feedbackType == "bug")

        local m_dialog = nil
        local m_titlescreenModal = nil
        local m_attachments = {}
        local m_submitting = false
        local m_submitted = false

        local m_includeLog = isBugReport
        local m_includeScreenshot = false
        local m_allowGameEntry = true
        local m_contactOnDiscord = true
        local m_mood = nil

        --the dialog is hosted in the gamehud modal stack in-game, or as a
        --floating panel on the titlescreen root otherwise.
        local function CloseDialog()
            if m_titlescreenModal ~= nil then
                if m_titlescreenModal.valid then
                    m_titlescreenModal:DestroySelf()
                end
            elseif m_dialog ~= nil and m_dialog.valid then
                m_dialog:FireEvent("close")
            end
        end

        local descriptionInput = gui.Input{
            width = 880,
            height = 150,
            fontSize = 16,
            multiline = true,
            characterLimit = 10000,
            textAlignment = "topleft",
            halign = "left",
            tmargin = 4,
            placeholderText = kindInfo.placeholder,
        }

        local screenshotSection = nil
        if report.screenshotImage ~= nil then
            local aspect = 9 / 16
            if report.screenshotWidth > 0 then
                aspect = report.screenshotHeight / report.screenshotWidth
            end

            screenshotSection = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                tmargin = 8,

                gui.Panel{
                    classes = {"bordered"},
                    bgimage = report.screenshotImage,
                    bgcolor = "white",
                    width = 280,
                    height = math.floor(280 * aspect),
                    halign = "left",
                    valign = "center",
                },

                gui.Check{
                    text = "Include this screenshot of your screen",
                    value = m_includeScreenshot,
                    halign = "left",
                    valign = "center",
                    lmargin = 16,
                    change = function(element)
                        m_includeScreenshot = element.value
                    end,
                },
            }
        end

        --the log file is only relevant to bug reports.
        local logCheck = nil
        if isBugReport then
            logCheck = gui.Check{
                text = "Include my log file (recommended)",
                tooltip = "Your log file helps developers diagnose the problem. If a log from your previous session exists (for example after a crash and restart), it is included too. Logs contain a small amount of personal data, such as your system username, and are compressed before uploading.",
                value = m_includeLog,
                halign = "left",
                tmargin = 12,
                change = function(element)
                    m_includeLog = element.value
                end,
            }
        end

        local gameEntryCheck = gui.Check{
            text = "Allow Codex developers to enter my game if needed",
            value = m_allowGameEntry,
            halign = "left",
            tmargin = cond(isBugReport, 4, 12),
            change = function(element)
                m_allowGameEntry = element.value
            end,
        }

        --Discord follow-up: if the Discord desktop client is running we know the
        --user's Discord handle and can offer to contact them about the report.
        --Otherwise explain that we cannot follow up.
        local discordSection
        if report.discordUsername ~= nil then
            discordSection = gui.Check{
                text = "Contact me on Discord (" .. report.discordUsername .. ") to follow up on this report",
                tooltip = "If checked, your Discord username is included with the report so a Codex developer can reach out to you about it. Leave unchecked to keep your Discord username private.",
                value = m_contactOnDiscord,
                halign = "left",
                tmargin = 12,
                change = function(element)
                    m_contactOnDiscord = element.value
                end,
            }
        else
            discordSection = gui.Label{
                fontSize = 15,
                width = 880,
                height = "auto",
                textWrap = true,
                halign = "left",
                tmargin = 12,
                text = "Discord isn't linked, so we won't be able to follow up with you about this report. Run the Discord app alongside Codex if you would like us to be able to reach out.",
            }
        end

        local m_attachmentsList = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
        }

        local function RefreshAttachments()
            local children = {}
            for i,path in ipairs(m_attachments) do
                local index = i
                local fileName = path
                for j = #path, 1, -1 do
                    local c = path:sub(j, j)
                    if c == "/" or c == "\\" then
                        fileName = path:sub(j + 1)
                        break
                    end
                end

                children[#children + 1] = gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    vmargin = 2,

                    gui.Label{
                        fontSize = 15,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        text = fileName,
                    },

                    gui.Button{
                        classes = {"sizeXs"},
                        text = "Remove",
                        valign = "center",
                        lmargin = 12,
                        width = 60,
                        click = function(element)
                            if m_submitting or m_submitted then
                                return
                            end
                            table.remove(m_attachments, index)
                            RefreshAttachments()
                        end,
                    },
                }
            end

            m_attachmentsList.children = children
        end

        local attachButton = gui.Button{
            classes = {"sizeM"},
            text = "Attach File...",
            halign = "left",
            tmargin = 12,
            click = function(element)
                if m_submitting or m_submitted then
                    return
                end
                dmhub.OpenFileDialog{
                    id = "bugreportattachment",
                    prompt = "Choose files to attach to your bug report",
                    extensions = {},
                    multiFiles = true,
                    openFiles = function(paths)
                        for _,path in ipairs(paths) do
                            local alreadyAdded = false
                            for _,existing in ipairs(m_attachments) do
                                if existing == path then
                                    alreadyAdded = true
                                end
                            end
                            if not alreadyAdded then
                                m_attachments[#m_attachments + 1] = path
                            end
                        end
                        RefreshAttachments()
                    end,
                }
            end,
        }

        local statusLabel = gui.Label{
            fontSize = 16,
            width = "100%",
            height = "auto",
            halign = "left",
            textWrap = true,
            tmargin = 8,
            text = "",
        }

        local submitButton

        submitButton = gui.Button{
            classes = {"sizeL"},
            text = "Submit Report",
            halign = "right",
            hmargin = 8,
            click = function(element)
                if m_submitting or m_submitted then
                    return
                end

                local description = descriptionInput.text
                if description == nil or description == "" then
                    statusLabel.text = "Please enter a description before submitting."
                    return
                end

                m_submitting = true
                statusLabel.text = "Submitting..."

                report:Submit{
                    description = description,
                    type = feedbackType,
                    includeLog = m_includeLog,
                    includeScreenshot = m_includeScreenshot,
                    allowGameEntry = m_allowGameEntry,
                    contactOnDiscord = m_contactOnDiscord,
                    mood = m_mood,
                    attachments = m_attachments,
                    progress = function(ratio)
                        if statusLabel.valid and not m_submitted then
                            statusLabel.text = string.format("Submitting... %d%%", math.floor(ratio * 100 + 0.5))
                        end
                    end,
                    complete = function(reportid)
                        m_submitting = false
                        m_submitted = true
                        if statusLabel.valid then
                            statusLabel.text = kindInfo.thanks
                            submitButton:SetClass("hidden", true)
                        end
                    end,
                    error = function(message)
                        m_submitting = false
                        if statusLabel.valid then
                            statusLabel.text = "Could not submit: " .. message
                        end
                    end,
                }
            end,
        }

        --Standard X close button pinned to the dialog's top-right corner. It
        --doubles as the cancel action: cancels the in-flight report (unless it
        --already submitted) and closes the dialog. Attached to the dialog frame
        --below (in-game modal / titlescreen panel / fallback modal).
        local closeButton = gui.Button{
            classes = {"closeButton"},
            floating = true,
            halign = "right",
            valign = "top",
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                if not m_submitted then
                    report:Cancel()
                end
                CloseDialog()
            end,
        }

        --Optional mood picker: five Fluent emoji (angry -> delighted) so the
        --user can convey how they feel; stored on the report as `mood`. The art
        --lives at Assets/UIImages/emotes/<mood>.png (run import-ui-images.ps1 +
        --build for these to resolve).
        local m_moodButtons = {}
        local function RefreshMoodSelection()
            for _,entry in ipairs(m_moodButtons) do
                entry.panel:SetClass("selected", entry.id == m_mood)
            end
        end

        local moodOrder = {
            { id = "angry", label = "Angry" },
            { id = "frustrated", label = "Frustrated" },
            { id = "sad", label = "Sad" },
            { id = "happy", label = "Happy" },
            { id = "delighted", label = "Delighted" },
        }

        local moodButtonPanels = {}
        for _,opt in ipairs(moodOrder) do
            local optid = opt.id
            local btn = gui.Panel{
                classes = {"moodButton"},
                bgimage = "emotes/" .. optid .. ".png",
                bgcolor = "white",
                --raw gui.Panel does not auto-wrap a string tooltip the way
                --gui.Check/Button do, so attach the lazy hover handler directly
                --(a bare `tooltip = string` eagerly creates an orphan panel).
                hover = gui.Tooltip(opt.label),
                press = function(element)
                    m_mood = cond(m_mood == optid, nil, optid)
                    RefreshMoodSelection()
                end,
            }
            m_moodButtons[#m_moodButtons + 1] = { panel = btn, id = optid }
            moodButtonPanels[#moodButtonPanels + 1] = btn
        end

        local moodPickerSection = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "left",
            vmargin = 4,

            styles = {
                { selectors = {"moodButton"}, width = 44, height = 44, hmargin = 6, valign = "center", bgcolor = "white", opacity = 0.5 },
                { selectors = {"moodButton", "hover"}, opacity = 0.85 },
                { selectors = {"moodButton", "selected"}, opacity = 1.0, scale = 1.15 },
            },

            gui.Label{
                fontSize = 15,
                width = "auto",
                height = "auto",
                halign = "left",
                text = "How are you feeling? (optional)",
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                tmargin = 4,
                children = moodButtonPanels,
            },
        }

        --assemble the form children explicitly; screenshotSection may be nil and
        --a nil hole in a positional children list would truncate it.
        local formChildren = {
            gui.Label{
                width = 880,
                height = "auto",
                fontSize = 15,
                textWrap = true,
                halign = "left",
                vmargin = 4,
                text = kindInfo.intro,
            },

            moodPickerSection,

            descriptionInput,
        }

        if logCheck ~= nil then
            formChildren[#formChildren + 1] = logCheck
        end

        formChildren[#formChildren + 1] = gameEntryCheck
        formChildren[#formChildren + 1] = discordSection

        if screenshotSection ~= nil then
            formChildren[#formChildren + 1] = screenshotSection
        end

        formChildren[#formChildren + 1] = attachButton
        formChildren[#formChildren + 1] = m_attachmentsList

        local bodyPanel = gui.Panel{
                width = 940,
                height = 620,
                flow = "vertical",
                halign = "center",

                gui.Panel{
                    width = "100%",
                    height = 560,
                    vscroll = true,
                    flow = "vertical",
                    halign = "center",

                    children = formChildren,
                },

                statusLabel,

                --Single bottom bar: Open Discord pinned to the bottom-left
                --corner, Submit Report pinned to the bottom-right corner.
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    valign = "bottom",
                    tmargin = 12,

                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "left",
                        valign = "center",

                        gui.Label{
                            fontSize = 14,
                            width = "auto",
                            height = "auto",
                            valign = "center",
                            text = "You can also discuss bugs with us on the Draw Steel Codex Discord:",
                        },

                        gui.Button{
                            classes = {"sizeS"},
                            text = "Open Discord",
                            valign = "center",
                            lmargin = 8,
                            width = 180,
                            click = function(element)
                                dmhub.OpenURL(g_bugReportLink)
                            end,
                        },
                    },

                    submitButton,
                },
        }

        if dmhub.inGame and not dmhub.isLobbyGame then
            m_dialog = gamehud:ModalDialog{
                title = kindInfo.title,

                --we build our own buttons inside the body so Submit can stay open
                --while the report uploads.
                buttons = {},

                bodyPanel,
            }
            m_dialog:AddChild(closeButton)
        else
            --On the titlescreen there is no gamehud modal stack, so host the
            --dialog as a floating framed panel on the titlescreen root, like
            --the other titlescreen dialogs. The panel owns its own theme
            --cascade, mirroring the frame that gamehud:ModalDialog builds.
            local root = rawget(_G, "CodexTitlescreenRoot")
            if root ~= nil and root.valid then
                m_titlescreenModal = gui.Panel{
                    classes = {"framedPanel"},
                    floating = true,
                    width = 1024,
                    height = 768,
                    halign = "center",
                    valign = "center",
                    styles = ThemeEngine.GetStyles(),

                    gui.Panel{
                        width = "100%-32",
                        height = "100%-32",
                        flow = "vertical",
                        halign = "center",
                        valign = "top",

                        gui.Label{
                            classes = {"dialogTitle"},
                            text = kindInfo.title,
                        },

                        bodyPanel,
                    },
                }
                root:AddChild(m_titlescreenModal)
                m_titlescreenModal:AddChild(closeButton)
            else
                --fallback: no titlescreen root available; use the gamehud modal.
                local gh = rawget(_G, "gamehud")
                if gh ~= nil then
                    m_dialog = gh:ModalDialog{
                        title = kindInfo.title,
                        buttons = {},
                        bodyPanel,
                    }
                    m_dialog:AddChild(closeButton)
                else
                    report:Cancel()
                end
            end
        end
    end

    --Survey dialog (Report Feedback > Survey): reads the survey definition
    --from the cloud (/survey) along with the user's previous response
    --(/surveyFeedback/<userid>), then walks the user through the questions
    --one page at a time in a wizard and uploads the answers with
    --dmhub.SubmitSurveyResponse. A user who already responded is thanked and
    --offered the chance to change their answers, which arrive prefilled from
    --their previous response.
    local function CreateSurveyDialog()
        local m_dialog = nil
        local m_titlescreenModal = nil

        local m_survey = nil     --survey definition table from the cloud.
        local m_response = nil   --the user's previous response record, if any.
        local m_answers = {}     --working answers, keyed by question id.
        local m_page = "loading" --"loading", "error", "intro", "finished", or a question index.
        local m_errorMessage = nil
        local m_submitting = false

        local function CloseDialog()
            if m_titlescreenModal ~= nil then
                if m_titlescreenModal.valid then
                    m_titlescreenModal:DestroySelf()
                end
            elseif m_dialog ~= nil and m_dialog.valid then
                m_dialog:FireEvent("close")
            end
        end

        --forward declared; assigned below and captured by the page builder closures.
        local contentPanel
        local RefreshPage

        --gui.Input only delivers its text reliably when read directly, so any
        --page holding an input registers a commit function here that pulls the
        --input's text into m_answers; navigation calls it before leaving the page.
        local m_commitPageInput = nil
        local function CommitPageInput()
            if m_commitPageInput ~= nil then
                m_commitPageInput()
            end
        end

        local function HasAnswer(q)
            local a = m_answers[q.id]
            if a == nil then
                return false
            end
            if q.type == "text" then
                return a ~= ""
            end
            if q.type == "multiselect" then
                if type(a) ~= "table" then
                    return false
                end
                if a.other ~= nil and a.other ~= "" then
                    return true
                end
                if type(a.selected) == "table" then
                    for _,v in pairs(a.selected) do
                        if v then
                            return true
                        end
                    end
                end
                return false
            end
            return true
        end

        --page builders.
        local function BuildMessagePage(text)
            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Label{
                    fontSize = 18,
                    width = 700,
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    textAlignment = "center",
                    textWrap = true,
                    text = text,
                },
            }
        end

        local function BuildIntroPage()
            local alreadyCompleted = (m_response ~= nil)

            local message
            if alreadyCompleted then
                message = m_survey.completedMessage or "You have already completed this survey - thank you! You can review and change your answers at any time."
            else
                message = m_survey.intro or "We would love to hear about your experience with the Codex."
            end

            local startText = "Start Survey"
            if alreadyCompleted then
                startText = "Change My Answers"
            end

            local nquestions = 0
            if type(m_survey.questions) == "table" then
                nquestions = #m_survey.questions
            end

            local children = {
                gui.Label{
                    fontSize = 30,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    text = m_survey.title or "Codex Survey",
                },

                gui.Label{
                    fontSize = 17,
                    width = 640,
                    height = "auto",
                    halign = "center",
                    textAlignment = "center",
                    textWrap = true,
                    tmargin = 20,
                    text = message,
                },

                gui.Label{
                    fontSize = 14,
                    color = "#aaaaaa",
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    tmargin = 14,
                    text = string.format("%d questions - takes a few minutes", nquestions),
                },

                gui.Button{
                    classes = {"sizeL"},
                    text = startText,
                    halign = "center",
                    tmargin = 32,
                    click = function(element)
                        m_page = 1
                        RefreshPage()
                    end,
                },
            }

            if alreadyCompleted then
                children[#children + 1] = gui.Button{
                    classes = {"sizeM"},
                    text = "Close",
                    halign = "center",
                    tmargin = 10,
                    click = function(element)
                        CloseDialog()
                    end,
                }
            end

            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    valign = "center",
                    children = children,
                },
            }
        end

        local function BuildFinishedPage()
            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    valign = "center",

                    gui.Label{
                        fontSize = 30,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        text = "Thank You!",
                    },

                    gui.Label{
                        fontSize = 17,
                        width = 640,
                        height = "auto",
                        halign = "center",
                        textAlignment = "center",
                        textWrap = true,
                        tmargin = 20,
                        text = m_survey.thanks or "Thank you for completing the survey!",
                    },

                    gui.Button{
                        classes = {"sizeL"},
                        text = "Close",
                        halign = "center",
                        tmargin = 32,
                        click = function(element)
                            CloseDialog()
                        end,
                    },
                },
            }
        end

        --builds the interactive answer control for one question. Every control
        --is a centered column so the page reads as a single balanced block.
        local function BuildQuestionControl(q)
            local qid = q.id

            if q.type == "text" then
                local input = gui.Input{
                    width = 700,
                    height = 220,
                    fontSize = 16,
                    multiline = true,
                    characterLimit = 5000,
                    textAlignment = "topleft",
                    halign = "center",
                    tmargin = 28,
                    placeholderText = q.placeholder or "Type your answer here...",
                    text = m_answers[qid] or "",
                }
                m_commitPageInput = function()
                    if input.valid then
                        m_answers[qid] = input.text
                    end
                end
                return input
            end

            if q.type == "rating" then
                local labels = q.labels or {"1", "2", "3", "4", "5"}
                local m_buttons = {}
                local caption

                local function RefreshSelection()
                    for _,entry in ipairs(m_buttons) do
                        entry.panel:SetClassTree("selected", m_answers[qid] == entry.value)
                    end
                    if caption ~= nil and caption.valid then
                        local value = m_answers[qid]
                        if value ~= nil and labels[value] ~= nil then
                            caption.text = labels[value]
                        else
                            caption.text = ""
                        end
                    end
                end

                local buttonPanels = {}
                for i,_ in ipairs(labels) do
                    local value = i
                    local btn = gui.Panel{
                        classes = {"ratingButton"},
                        bgimage = true,
                        press = function(element)
                            m_answers[qid] = value
                            RefreshSelection()
                        end,

                        gui.Label{
                            fontSize = 26,
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            valign = "center",
                            interactable = false,
                            text = tostring(i),
                        },
                    }
                    m_buttons[#m_buttons + 1] = { panel = btn, value = value }
                    buttonPanels[#buttonPanels + 1] = btn
                end

                --the low/high captions anchor the scale under its endpoints;
                --the width matches the button row (N buttons at 64 + 2x5 margin).
                local scaleWidth = #labels * 74

                caption = gui.Label{
                    fontSize = 16,
                    width = 700,
                    height = 24,
                    halign = "center",
                    textAlignment = "center",
                    tmargin = 10,
                    text = "",
                }

                --optional free-text comments accompanying the rating, stored
                --alongside the numeric answer as <questionid>_comments.
                local commentsInput = gui.Input{
                    width = 700,
                    height = 90,
                    fontSize = 15,
                    multiline = true,
                    characterLimit = 2000,
                    textAlignment = "topleft",
                    halign = "center",
                    tmargin = 20,
                    placeholderText = "Comments (optional)...",
                    text = m_answers[qid .. "_comments"] or "",
                }
                m_commitPageInput = function()
                    if commentsInput.valid then
                        local text = commentsInput.text
                        if text == nil or text == "" then
                            m_answers[qid .. "_comments"] = nil
                        else
                            m_answers[qid .. "_comments"] = text
                        end
                    end
                end

                local result = gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    tmargin = 28,

                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",
                        children = buttonPanels,
                    },

                    gui.Panel{
                        width = scaleWidth,
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",
                        tmargin = 6,

                        gui.Label{
                            fontSize = 13,
                            color = "#999999",
                            width = "50%",
                            height = "auto",
                            halign = "left",
                            textAlignment = "left",
                            text = labels[1],
                        },

                        gui.Label{
                            fontSize = 13,
                            color = "#999999",
                            width = "50%",
                            height = "auto",
                            halign = "right",
                            textAlignment = "right",
                            text = labels[#labels],
                        },
                    },

                    caption,

                    commentsInput,
                }

                RefreshSelection()
                return result
            end

            --select and multiselect: one row per option, each with a radio or
            --checkbox indicator. select keeps exactly one row active;
            --multiselect toggles rows independently.
            local multi = (q.type == "multiselect")
            local m_rows = {}

            --multiselect questions may cap how many options can be chosen via
            --q.maxSelections; nil/0 means unlimited. When the cap is reached the
            --remaining options grey out and further presses are ignored.
            local maxSel = nil
            if multi then
                maxSel = tonumber(q.maxSelections)
                if maxSel ~= nil and maxSel <= 0 then
                    maxSel = nil
                end
            end

            --forward declared; created below only when a cap is in effect.
            local hintLabel = nil

            local function CountSelected()
                local a = m_answers[qid]
                if type(a) ~= "table" or type(a.selected) ~= "table" then
                    return 0
                end
                local n = 0
                for _,v in pairs(a.selected) do
                    if v then
                        n = n + 1
                    end
                end
                return n
            end

            local function IsOptionSelected(optid)
                if multi then
                    local a = m_answers[qid]
                    return type(a) == "table" and type(a.selected) == "table" and a.selected[optid] == true
                else
                    return m_answers[qid] == optid
                end
            end

            local function RefreshSelection()
                local atLimit = (maxSel ~= nil and CountSelected() >= maxSel)
                for _,entry in ipairs(m_rows) do
                    local selected = IsOptionSelected(entry.id)
                    entry.panel:SetClassTree("selected", selected)
                    --once the cap is reached, grey out the options that are not
                    --already chosen so it is clear they cannot be added without
                    --deselecting one first. Selected rows stay live to toggle off.
                    entry.panel:SetClass("disabledOption", atLimit and not selected)
                end
                if hintLabel ~= nil and hintLabel.valid then
                    hintLabel.text = string.format("Select up to %d", maxSel)
                end
            end

            local function ToggleOption(optid)
                if multi then
                    local a = m_answers[qid]
                    if type(a) ~= "table" then
                        a = {}
                        m_answers[qid] = a
                    end
                    if type(a.selected) ~= "table" then
                        a.selected = {}
                    end
                    if a.selected[optid] then
                        a.selected[optid] = nil
                    elseif maxSel == nil or CountSelected() < maxSel then
                        a.selected[optid] = true
                    end
                    --at the cap, presses on unselected options are ignored.
                else
                    if m_answers[qid] == optid then
                        m_answers[qid] = nil
                    else
                        m_answers[qid] = optid
                    end
                end
                RefreshSelection()
            end

            local indicatorClass = "surveyRadio"
            if multi then
                indicatorClass = "surveyCheckBox"
            end

            local rowPanels = {}
            for _,option in ipairs(q.options or {}) do
                local optid = option.id
                local row = gui.Panel{
                    classes = {"surveyOption"},
                    bgimage = true,
                    press = function(element)
                        ToggleOption(optid)
                    end,

                    gui.Panel{
                        classes = {indicatorClass},
                        bgimage = true,
                        interactable = false,

                        gui.Panel{
                            classes = {indicatorClass .. "Fill"},
                            bgimage = true,
                            interactable = false,
                        },
                    },

                    gui.Label{
                        fontSize = 16,
                        width = "100%-38",
                        height = "auto",
                        halign = "left",
                        lmargin = 12,
                        valign = "center",
                        interactable = false,
                        textWrap = true,
                        text = option.text or optid,
                    },
                }
                m_rows[#m_rows + 1] = { panel = row, id = optid }
                rowPanels[#rowPanels + 1] = row
            end

            local children = {}

            --when a cap is in effect, a small note above the options tells the
            --user how many they may pick.
            if maxSel ~= nil then
                hintLabel = gui.Label{
                    fontSize = 13,
                    color = "#999999",
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    bmargin = 10,
                    text = string.format("Select up to %d", maxSel),
                }
                children[#children + 1] = hintLabel
            end

            children[#children + 1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                halign = "center",
                children = rowPanels,
            }

            if q.allowOther then
                local otherText = ""
                local a = m_answers[qid]
                if multi then
                    if type(a) == "table" and type(a.other) == "string" then
                        otherText = a.other
                    end
                else
                    local other = m_answers[qid .. "_other"]
                    if type(other) == "string" then
                        otherText = other
                    end
                end

                local otherInput = gui.Input{
                    width = 700,
                    height = 30,
                    fontSize = 16,
                    halign = "center",
                    tmargin = 12,
                    placeholderText = "Other (tell us more)...",
                    text = otherText,
                }
                m_commitPageInput = function()
                    if not otherInput.valid then
                        return
                    end
                    local text = otherInput.text
                    if text == "" then
                        text = nil
                    end
                    if multi then
                        local answer = m_answers[qid]
                        if type(answer) ~= "table" then
                            answer = {}
                            m_answers[qid] = answer
                        end
                        answer.other = text
                    else
                        m_answers[qid .. "_other"] = text
                    end
                end

                children[#children + 1] = otherInput
            end

            local result = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                halign = "center",
                tmargin = 24,
                children = children,
            }

            RefreshSelection()
            return result
        end

        --A prompt too long for one line otherwise wraps wherever it runs out
        --of room, orphaning a couple of words on the second line. Break long
        --prompts explicitly at the word nearest the middle so the two lines
        --come out roughly even. Prompts short enough for one line (the 760px
        --label fits around 72 characters at this size) are left alone.
        local function BalancePromptText(text)
            if text == nil or #text <= 72 then
                return text
            end
            local mid = math.floor(#text / 2)
            local best = nil
            for i = 1, #text do
                if text:sub(i, i) == " " then
                    if best == nil or math.abs(i - mid) < math.abs(best - mid) then
                        best = i
                    end
                end
            end
            if best == nil then
                return text
            end
            return text:sub(1, best - 1) .. "\n" .. text:sub(best + 1)
        end

        local function BuildQuestionPage(index)
            local questions = m_survey.questions
            local q = questions[index]
            local nquestions = #questions
            local isLast = (index >= nquestions)

            local statusLabel = gui.Label{
                fontSize = 15,
                width = 700,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = true,
                bmargin = 8,
                text = "",
            }

            local function TryLeavePage(destination)
                CommitPageInput()
                if destination > index and q.required and not HasAnswer(q) then
                    statusLabel.text = "Please answer this question before continuing."
                    return
                end
                if destination < 1 then
                    m_page = "intro"
                else
                    m_page = destination
                end
                RefreshPage()
            end

            local function Submit()
                CommitPageInput()
                if q.required and not HasAnswer(q) then
                    statusLabel.text = "Please answer this question before continuing."
                    return
                end
                if m_submitting then
                    return
                end
                m_submitting = true
                statusLabel.text = "Submitting..."
                dmhub.SubmitSurveyResponse{
                    surveyId = m_survey.id,
                    answers = m_answers,
                    complete = function()
                        m_submitting = false
                        if contentPanel ~= nil and contentPanel.valid then
                            m_page = "finished"
                            RefreshPage()
                        end
                    end,
                    error = function(message)
                        m_submitting = false
                        if statusLabel.valid then
                            statusLabel.text = "Could not submit: " .. message
                        end
                    end,
                }
            end

            local nextText = "Next"
            if isLast then
                nextText = "Submit"
            end

            --the question block: prompt (plus an Optional note) and the answer
            --control, gathered into one column centered in the page.
            local questionChildren = {
                gui.Label{
                    fontSize = 22,
                    bold = true,
                    width = 760,
                    height = "auto",
                    halign = "center",
                    textAlignment = "center",
                    textWrap = true,
                    text = BalancePromptText(q.prompt or ""),
                },
            }

            if not q.required then
                questionChildren[#questionChildren + 1] = gui.Label{
                    fontSize = 13,
                    color = "#999999",
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    tmargin = 6,
                    text = "Optional",
                }
            end

            questionChildren[#questionChildren + 1] = BuildQuestionControl(q)

            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                --header pinned to the top: position in the survey plus a
                --progress bar that fills as the user advances.
                gui.Panel{
                    floating = true,
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    valign = "top",

                    gui.Label{
                        fontSize = 13,
                        color = "#aaaaaa",
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        text = string.upper(string.format("Question %d of %d", index, nquestions)),
                    },

                    gui.Panel{
                        width = 700,
                        height = 6,
                        halign = "center",
                        tmargin = 10,
                        bgimage = true,
                        bgcolor = "#ffffff22",
                        cornerRadius = 3,

                        gui.Panel{
                            width = string.format("%d%%", math.floor(100 * index / nquestions)),
                            height = "100%",
                            halign = "left",
                            bgimage = true,
                            bgcolor = "#8899eeff",
                            cornerRadius = 3,
                        },
                    },
                },

                --the question itself, centered in the page.
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    valign = "center",
                    children = questionChildren,
                },

                --navigation pinned to the bottom of the page, aligned with the
                --content column.
                gui.Panel{
                    floating = true,
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    valign = "bottom",

                    statusLabel,

                    gui.Panel{
                        width = 700,
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",

                        gui.Button{
                            classes = {"sizeM"},
                            text = "Back",
                            halign = "left",
                            click = function(element)
                                TryLeavePage(index - 1)
                            end,
                        },

                        gui.Button{
                            classes = {"sizeM"},
                            text = nextText,
                            halign = "right",
                            click = function(element)
                                if isLast then
                                    Submit()
                                else
                                    TryLeavePage(index + 1)
                                end
                            end,
                        },
                    },
                },
            }
        end

        contentPanel = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
        }

        RefreshPage = function()
            m_commitPageInput = nil
            local page
            if m_page == "loading" then
                page = BuildMessagePage("Loading...")
            elseif m_page == "error" then
                page = BuildMessagePage(m_errorMessage or "The survey could not be loaded. Please try again later.")
            elseif m_page == "intro" then
                page = BuildIntroPage()
            elseif m_page == "finished" then
                page = BuildFinishedPage()
            else
                page = BuildQuestionPage(m_page)
            end
            contentPanel.children = { page }
        end

        --fetch the survey definition and the user's previous response in
        --parallel; move off the loading page when both have arrived.
        local m_surveyLoaded = false
        local m_responseLoaded = false
        local function CheckLoadingComplete()
            if not (m_surveyLoaded and m_responseLoaded) then
                return
            end
            if contentPanel == nil or not contentPanel.valid then
                return
            end
            if m_survey == nil or type(m_survey.questions) ~= "table" or #m_survey.questions == 0 then
                m_page = "error"
                if m_errorMessage == nil then
                    m_errorMessage = "No survey is available right now. Please check back later."
                end
            else
                --prefill from the previous answers so the user can revise them.
                if m_response ~= nil and type(m_response.answers) == "table" then
                    for k,v in pairs(m_response.answers) do
                        m_answers[k] = v
                    end
                end
                m_page = "intro"
            end
            RefreshPage()
        end

        dmhub.GetSurvey(function(survey, err)
            m_surveyLoaded = true
            m_survey = survey
            if err ~= nil then
                m_errorMessage = "Could not load the survey: " .. err
            end
            CheckLoadingComplete()
        end)

        dmhub.GetSurveyResponse(function(response, err)
            --a response fetch error is not fatal; treat it as no previous response.
            m_responseLoaded = true
            m_response = response
            CheckLoadingComplete()
        end)

        local closeButton = gui.Button{
            classes = {"closeButton"},
            floating = true,
            halign = "right",
            valign = "top",
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                CloseDialog()
            end,
        }

        local bodyPanel = gui.Panel{
            width = 940,
            --tall enough for the longest question (features: 9 options + an
            --Other field) to sit centered without the option list colliding
            --with the floating Back/Next footer. This also drops the footer
            --into the room that was previously empty below it.
            height = 690,
            flow = "vertical",
            halign = "center",

            styles = {
                { selectors = {"surveyOption"}, width = 700, height = "auto", flow = "horizontal", bgcolor = "#00000066", border = 1, borderColor = "#888888", cornerRadius = 6, pad = 10, borderBox = true, halign = "center", vmargin = 3 },
                { selectors = {"surveyOption", "hover"}, bgcolor = "#2a2a2aaa", borderColor = "#cccccc" },
                { selectors = {"surveyOption", "selected"}, bgcolor = "#38386e99", borderColor = "#8899ee" },
                { selectors = {"surveyOption", "disabledOption"}, bgcolor = "#00000033", borderColor = "#555555", opacity = 0.45 },
                { selectors = {"surveyOption", "disabledOption", "hover"}, bgcolor = "#00000033", borderColor = "#555555" },
                { selectors = {"surveyCheckBox"}, width = 20, height = 20, valign = "center", bgcolor = "clear", border = 1, borderColor = "#aaaaaa", cornerRadius = 3 },
                { selectors = {"surveyRadio"}, width = 20, height = 20, valign = "center", bgcolor = "clear", border = 1, borderColor = "#aaaaaa", cornerRadius = 10 },
                { selectors = {"surveyCheckBoxFill"}, width = 12, height = 12, halign = "center", valign = "center", bgcolor = "#aabbff", cornerRadius = 2, opacity = 0 },
                { selectors = {"surveyRadioFill"}, width = 12, height = 12, halign = "center", valign = "center", bgcolor = "#aabbff", cornerRadius = 6, opacity = 0 },
                { selectors = {"surveyCheckBoxFill", "selected"}, opacity = 1 },
                { selectors = {"surveyRadioFill", "selected"}, opacity = 1 },
                { selectors = {"ratingButton"}, width = 64, height = 64, bgcolor = "#00000066", border = 1, borderColor = "#888888", cornerRadius = 6, hmargin = 5 },
                { selectors = {"ratingButton", "hover"}, bgcolor = "#2a2a2aaa", borderColor = "#cccccc" },
                { selectors = {"ratingButton", "selected"}, bgcolor = "#38386e99", borderColor = "#8899ee" },
            },

            contentPanel,
        }

        if dmhub.inGame and not dmhub.isLobbyGame then
            m_dialog = gamehud:ModalDialog{
                title = "Survey",
                buttons = {},
                bodyPanel,
            }
            m_dialog:AddChild(closeButton)
        else
            --On the titlescreen there is no gamehud modal stack, so host the
            --dialog as a floating framed panel on the titlescreen root, like
            --the bug report dialog above.
            local root = rawget(_G, "CodexTitlescreenRoot")
            if root ~= nil and root.valid then
                m_titlescreenModal = gui.Panel{
                    classes = {"framedPanel"},
                    floating = true,
                    width = 1024,
                    height = 768,
                    halign = "center",
                    valign = "center",
                    styles = ThemeEngine.GetStyles(),

                    gui.Panel{
                        width = "100%-32",
                        height = "100%-32",
                        flow = "vertical",
                        halign = "center",
                        valign = "top",

                        gui.Label{
                            classes = {"dialogTitle"},
                            text = "Survey",
                        },

                        bodyPanel,
                    },
                }
                root:AddChild(m_titlescreenModal)
                m_titlescreenModal:AddChild(closeButton)
            else
                --fallback: no titlescreen root available; use the gamehud modal.
                local gh = rawget(_G, "gamehud")
                if gh ~= nil then
                    m_dialog = gh:ModalDialog{
                        title = "Survey",
                        buttons = {},
                        bodyPanel,
                    }
                    m_dialog:AddChild(closeButton)
                end
            end
        end

        RefreshPage()
    end

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
            name = "Report Feedback",
            mainmenu = "always",
            menuItems = function()
                --each entry captures the screenshot before the dialog appears,
                --then shows the dialog for that kind of feedback.
                local function FeedbackMenuItem(text, feedbackType)
                    return {
                        text = text,
                        click = function()
                            dmhub.BeginBugReport(function(report)
                                CreateBugReportDialog(report, feedbackType)
                            end)
                        end,
                    }
                end

                return {
                    FeedbackMenuItem("Bug Report", "bug"),
                    FeedbackMenuItem("Feature Request", "feature"),
                    FeedbackMenuItem("General Feedback", "feedback"),
                    {
                        text = "Survey",
                        click = function()
                            CreateSurveyDialog()
                        end,
                    },
                }
            end,
        },

        m_presentationBar,
        CreateStatusBar(),
        -- Glyph + search travel as ONE right-aligned cluster: the search box
        -- floats right and its width tracks the dock scale, so a sibling at a
        -- flow position drifts away from it as the box narrows. Wrapping both
        -- keeps the glyph pressed against the box's left edge at any scale
        -- (James field report, 2026-07-03).
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "100%",
            halign = "right",
            m_audioIndicator,
            m_searchBar,
        },
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

        -- Audio indicator glyph (H-BAR): same in-game-only visibility as the
        -- search box, driven by the same "ingame" class SetClassTree'd onto
        -- an ancestor (menuBar's think, below). No searchoverride exemption
        -- -- the glyph has no main-menu equivalent to preserve.
        {
            selectors = {"audioIndicator", "~ingame"},
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
            -- The primary-action hint line under the name: a muted lead-in
            -- arrow + text describing what pressing the row does.
            selectors = {"searchActionLine"},
            tmargin = 4,
            valign = "center",
        },
        {
            -- Right column: the type chip plus any secondary action buttons,
            -- stacked. lmargin keeps it off the name when the row is narrow.
            selectors = {"searchResultRight"},
            lmargin = 8,
        },
        {
            -- Small right-pointing lead-in arrow, tinted to match the muted
            -- hint text so it reads as "this happens on click".
            selectors = {"searchHintArrow"},
            width = 11,
            height = 11,
            valign = "center",
            rmargin = 5,
            bgimage = "icons/icon_arrow/icon_arrow_28.png",
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"searchHintText"},
            width = "auto",
            height = "auto",
            valign = "center",
            color = "@fgMuted",
            fontSize = 12,
        },
        {
            -- Secondary action: small outlined button in the right column,
            -- right-aligned under the type chip; tmargin separates it from the
            -- chip above (and from sibling buttons when there is more than one).
            selectors = {"searchResultChip"},
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            color = "@fg",
            fontSize = 11,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            borderWidth = 1,
            borderColor = "@fgMuted",
            cornerRadius = 4,
            pad = 3,
            hpad = 8,
            borderBox = true,
            tmargin = 5,
        },
        {
            selectors = {"searchResultChip", "hover"},
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            color = "@accentHover",
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