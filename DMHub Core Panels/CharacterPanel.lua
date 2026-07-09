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

CharacterPanel = {}

--Remembers which party folders the local user has collapsed, on a per-user-per-game
--basis. Value is a map of party key -> collapsed boolean.
setting{
    id = "characterpanel:partycollapsed",
    description = "Remembers which party folders are collapsed in the character list.",
    storage = "pergamepreference",
    default = {},
}

local function PartyCollapsedKey(partyid)
    if partyid == nil then
        return "__unaffiliated__"
    end
    return partyid
end

--Returns the stored collapsed state for a party, or fallback if none has been stored.
local function GetPartyCollapsed(partyid, fallback)
    local t = dmhub.GetSettingValue("characterpanel:partycollapsed")
    if type(t) ~= "table" then
        return fallback
    end
    local v = t[PartyCollapsedKey(partyid)]
    if v == nil then
        return fallback
    end
    return v
end

local function SetPartyCollapsed(partyid, value)
    local t = dmhub.GetSettingValue("characterpanel:partycollapsed")
    local newTable = {}
    if type(t) == "table" then
        for k, val in pairs(t) do
            newTable[k] = val
        end
    end
    newTable[PartyCollapsedKey(partyid)] = value
    dmhub.SetSettingValue("characterpanel:partycollapsed", newTable)
end

local CreateCharacterPanel
local CreateBestiaryPanel

local g_sidebarExtras = {
    {
        selectors = { "bestiaryLabel" },
        color = "@fg",
        bold = true,
        height = "auto",
        width = "auto",
        minWidth = 200,
        halign = "left",
        valign = "center",
    },
    {
        selectors = {"bestiaryLabel", "folder"},
        uppercase = true,
    },
    {
        selectors = { "bestiaryLabel", "focus" },
        color = "@fgInverse",
    },
    {
        selectors = { "bestiaryLabel", "parent:hover", "~noHoverColor" },
        color = "@fgInverse",
    },
    {
        selectors = { "bestiaryLabel", "parent:focus" },
        color = "@fgInverse",
    },
    {
        selectors = { "bestiaryLabel", "parent:selected" },
        color = "@fgInverse",
    },
    {
        selectors = { "bestiaryLabel", "invisible" },
        color = "@fgMuted",
        italics = true,
    },
    {
        selectors = { "headerPanel", "hover" },
        bgcolor = "@bgInverse",
    },
    {
        selectors = {"playerStar"},
        bgcolor = "@accent",
    },
    {
        selectors = { "monsterEntry", "focus" },
        borderWidth = 2,
        borderColor = "@border",
        bgcolor = "@bgInverse",
        color = "@fgInverse",
    },
    {
        selectors = { "monsterEntry", "hover" },
        bgcolor = "@bgInverse",
        color = "@fgInverse",
        brightness = 1.2,
    },
    {
        selectors = { "characterEntry" },
        bgcolor = "clear",
    },
    {
        selectors = { "characterEntry", "selected" },
        bgcolor = "@bgInverse",
        color = "@fgInverse",
    },
    {
        selectors = { "characterEntry", "focus" },
        borderWidth = 2,
        borderColor = "@border",
        bgcolor = "@bgInverse",
        color = "@fgInverse",
    },
    {
        selectors = { "characterEntry", "hover" },
        bgcolor = "@bgInverse",
        color = "@fgInverse",
        brightness = 1.2,
    },
}

DockablePanel.Register {
    name = "Character",
	icon = "icons/standard/Icon_App_Character.png",
    minHeight = 140,
    vscroll = true,
    hideObjectsOutOfScroll = false,
    content = function()
        track("panel_open", {
            panel = "Character",
            dailyLimit = 30,
        })
        return CreateCharacterPanel()
    end,
    hasNewContent = function()
        return module.HasNovelContent("character")
    end,
}

DockablePanel.Register {
    name = "Bestiary",
	icon = "icons/standard/Icon_App_Bestiary.png",
    minHeight = 140,
    dmonly = true,
    vscroll = true,
    hideObjectsOutOfScroll = false,
    content = function()
        track("panel_open", {
            panel = "Bestiary",
            dailyLimit = 30,
        })
        return CreateBestiaryPanel()
    end,
    hasNewContent = function()
        return module.HasNovelContent("monsters")
    end,
}

local CreateBestiaryNode

--character panels selected beyond the focused one.
local characterPanelsSelected = {}

dmhub.GetSelectedMonster = function()
    if gui.GetFocus() == nil or (not gui.GetFocus().data.monsterid) then
        return nil
    end

    local monsterid = gui.GetFocus().data.monsterid
    local monster = assets.monsters[monsterid]
    local quantity = 1
    if monster.properties.minion then
        quantity = 4
    end

    return {
        monsterid = monsterid,
        quantity = quantity,
    }
end

dmhub.GetSelectedCharacters = function()
    if gui.GetFocus() == nil or (not gui.GetFocus().data.charid) then
        return {}
    end

    local result = {}
    result[#result + 1] = gui.GetFocus().data.charid

    for _, p in ipairs(characterPanelsSelected) do
        if p.valid and p.data.charid then
            result[#result + 1] = p.data.charid
        end
    end

    return result
end

local AddCharacterPanelToSelection = function(panel)
    for _, p in ipairs(characterPanelsSelected) do
        if p == panel then
            return
        end
    end

    characterPanelsSelected[#characterPanelsSelected + 1] = panel
    panel:SetClass("selected", true)
end

local RemoveCharacterPanelSelection = function(panel)
    panel:SetClass("selected", false)
    for i, p in ipairs(characterPanelsSelected) do
        if p == panel then
            table.remove(characterPanelsSelected, i)
            return
        end
    end
end

local ClearCharacterPanelSelection = function()
    for _, p in ipairs(characterPanelsSelected) do
        if p.valid then
            p:SetClass("selected", false)
        end
    end

    characterPanelsSelected = {}
end


local BestiaryPanelHeight = 24

local IsMonsterNodeSelfOrChildOf
IsMonsterNodeSelfOrChildOf = function(nodeid, childid)
    if nodeid == childid then
        return true
    end

    if childid == '' or childid == nil then
        return false
    end

    local node = assets:GetMonsterNode(childid)
    if node == nil then
        return false
    end

    return IsMonsterNodeSelfOrChildOf(nodeid, node.parentNode)
end

--function which is used when we drag monsters around the bestiary.
mod.shared.CreateDragTargetFunction = function(node, getNodeFunction, refreshType)
    return function(element, target)
        if target ~= nil then
            if target:HasClass("ignoreDrag") then
                return
            end
            target:FireEvent('monsterDraggedOnto', node)
        end
        if target == nil or target.data.nodeid == nil then
            return
        end

        local targetNode = getNodeFunction(target.data.nodeid)
        if targetNode == nil then
            return
        end

        local targetOrd = target.data.ord

        if targetOrd == nil then
            local maxOrd = 0
            for i, v in ipairs(targetNode.children) do
                if v ~= node and v.ord > maxOrd then
                    maxOrd = v.ord
                end
            end

            targetOrd = maxOrd + 1
        end

        for i, v in ipairs(targetNode.children) do
            local newOrd = v.ord
            if newOrd >= targetOrd then
                newOrd = newOrd + 1
            end

            if v ~= node and v.ord ~= newOrd then
                v.ord = newOrd
                v:Upload()
            end
        end

        node.parentNode = target.data.nodeid
        node.ord = targetOrd
        node:Upload()
        assets:RefreshAssets(refreshType)
    end
end

CharacterPanel.CreateCharacterDetailsPanel = function(token)
    return gui.Panel {
        width = "100%",
        height = 1,
    }
end

local g_characterDetailsPanel = nil
local g_displayedAbility = nil

--[==[ DEAD_CODE - overridden by Timeline\AbilitySidebar.lua:1304
function CharacterPanel.DisplayAbility(token, ability, symbols)
    DockablePanel.LaunchPanelByName("Character", "show")
    if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid then
        g_displayedAbility = ability
        g_characterDetailsPanel:FireEventTree("showAbility", token, ability, symbols)
        return true
    end

    return false
end
--]==]

--[==[ DEAD_CODE - overridden by Timeline\AbilitySidebar.lua:1344
function CharacterPanel.HighlightAbilitySection(options)
    if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid then
        g_characterDetailsPanel:FireEventTree("showAbilitySection", options)
    end
end
--]==]

--[==[ DEAD_CODE - overridden by Timeline\AbilitySidebar.lua:1392
function CharacterPanel.HideAbility(ability)
    local ctrl = dmhub.modKeys['ctrl'] or false
    if ctrl then
        dmhub.Coroutine(function()
            while dmhub.modKeys['ctrl'] do
                coroutine.yield(0.1)
            end
            if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid and ability == g_displayedAbility then
                g_characterDetailsPanel:FireEvent("hideAbility")
            end
        end)
        return true
    end
    if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid and ability == g_displayedAbility then
        g_characterDetailsPanel:FireEvent("hideAbility")
        return true
    end

    return false
end
--]==]

local function AbilityDisplayPanel()
    local resultPanel
    resultPanel = gui.Panel {
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        showAbility = function(element, token, ability, symbols)
            local panel = nil

                print("ABILITY:: RENDER TRIGGER START", ability.typeName)
            if ability.typeName == "ActiveTrigger" then
                local triggerInfo = token.properties:GetTriggeredActionInfo(ability:GetText())
                print("ABILITY:: RENDER TRIGGER", ability:GetText(), json(triggerInfo))
                if triggerInfo ~= nil then
                    panel = triggerInfo:Render { width = 340 }
                    panel:SetClass("hidden", false)
                    panel:SetClass("collapsed", false)
                end
            elseif ability.typeName == "TriggeredAbilityDisplay" then
                panel = ability:Render { width = 340 }
            else

                if ability.categorization == "Trigger" then
                    local triggerInfo = token.properties:GetTriggeredActionInfo(ability.name)
                    if triggerInfo ~= nil then
                        panel = triggerInfo:Render { width = 340, token = token, ability = ability, symbols = symbols }
                    end
                end

                if panel == nil then
                    panel = CreateAbilityTooltip(ability:GetActiveVariation(token),
                        { token = token, symbols = symbols, width = 346 })
                end
            end

            if panel ~= nil then
                element.children = { panel }
            end
        end,
    }
    return resultPanel
end

local function CharacterDetailsPanel(token)
    local m_token = token

    local m_abilityDisplay = AbilityDisplayPanel()


    local m_characterPanel = CharacterPanel.CreateCharacterDetailsPanel(token)

    resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 26,
        styles = {
            gui.Style {
                selectors = { "collapsedByAbility" },
                collapsed = 1,
            }
        },
        data = {
            dirty = false,
        },

        create = function(element)
            g_characterDetailsPanel = element
        end,

        destroy = function(element)
            if g_characterDetailsPanel == element then
                g_characterDetailsPanel = nil
            end
        end,

        showAbility = function(element, token, ability, symbols)
            m_characterPanel:SetClass("collapsedByAbility", true)
            m_abilityDisplay:SetClass("collapsed", false)
        end,

        hideAbility = function(element)
            m_characterPanel:SetClass("collapsedByAbility", false)
            m_abilityDisplay:SetClass("collapsed", true)
        end,

        refreshTokenTree = function(element)
            if element.data.dirty == false then
                return
            end

            element.data.dirty = false

            if m_token ~= nil and m_token.valid then
                element:FireEventTree("refreshToken", m_token)
            end
        end,

        dirtyToken = function(element, tok, skipMonitor)
            local delay = 0.3
            if m_token ~= tok then
                delay = 0
            end

            m_token = tok

            if skipMonitor ~= true then
                element.monitorGame = m_token.monitorPath
            end

            if element.data.dirty == false or delay <= 0 then
                element.data.dirty = true
                element:ScheduleEvent("refreshTokenTree", delay)
            end
        end,

        refreshGame = function(element)
            if m_token ~= nil and m_token.properties ~= nil then
                element:FireEvent("dirtyToken", m_token, true)
            end
        end,

        m_characterPanel,
        m_abilityDisplay,

    }

    return resultPanel
end

local function CreateMonsterEntry(nodeid)
    local node = assets:GetMonsterNode(nodeid)
    local monster = node.monster.info

    local searchActive = false
    local matchesSearch = true
    local parentCollapsed = false

    local resultPanel = nil

    resultPanel = gui.Panel({
        classes = { "monsterEntry" },
        id = nodeid,
        bgimage = true,
        valign = "top",
        width = "100%",
        height = BestiaryPanelHeight,
        flow = "horizontal",
        draggable = nodeid ~= '',
        canDragOnto = function(element, target)
            if target:HasClass("ignoreDrag") then
                return true
            end

            return target:HasClass('monster-drag-target') and
                   not IsMonsterNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
        end,

        events = {

            --render a tooltip of the monster.
            linger = function(element)
                local dock = element:FindParentWithClass("dock")

                local monsterEntry = assets.monsters[nodeid]
                if monsterEntry == nil then
                    return
                end

                local lockedHeight = math.floor(dmhub.screenDimensionsBelowTitlebar.y * 0.6)
                local panel = monsterEntry:Render {
                    width = 800,
                    maxHeight = lockedHeight,
                    vscroll = true,
                }

                if panel ~= nil then
                    element.tooltip = gui.TooltipFrame(
                        panel,
                        {
                            halign = dock.data.TooltipAlignment(),
                            valign = "center",
                            interactable = true,
                        }
                    )
                end
            end,

            --When ctrl is held, defer hiding the tooltip until ctrl is released.
            --Mirrors the CharacterPanel.HideAbility pattern in Timeline/AbilitySidebar.lua.
            dehover = function(element)
                if not dmhub.modKeys["ctrl"] then
                    return
                end

                local dock = element:FindParentWithClass("dock")
                local monsterEntry = assets.monsters[nodeid]
                if monsterEntry == nil then
                    return
                end

                local lockedHeight = math.floor(dmhub.screenDimensionsBelowTitlebar.y * 0.6)
                local panel = monsterEntry:Render {
                    width = 800,
                    maxHeight = lockedHeight,
                    vscroll = true,
                }
                if panel == nil then
                    return
                end

                element.popup = gui.TooltipFrame(
                    panel,
                    {
                        halign = dock.data.TooltipAlignment(),
                        valign = "center",
                        interactable = true,
                    }
                )

                dmhub.Coroutine(function()
                    while dmhub.modKeys["ctrl"] do
                        coroutine.yield(0.1)
                    end
                    if mod.unloaded then return end
                    if element.valid then
                        element.popup = nil
                    end
                end)
            end,

            beginDrag = function(element)
                --element:FireEvent('click')
            end,
            drag = mod.shared.CreateDragTargetFunction(node, function(nodeid) return assets:GetMonsterNode(nodeid) end,
                "Monsters"),

            dragging = function(element, target)
                if target == nil then
                    dmhub.SetDraggingMonster()
                end
            end,

            refreshAssets = function(element)
                monster = assets:GetMonsterNode(nodeid).monster.info

                if element:HasClass('focus') then
                    element:FireEvent('focus')
                end

                element.x = element.data.depth * 10
            end,

            press = function(element)
                if gui.GetFocus() == element then
                    gui.SetFocus(nil)
                else
                    gui.SetFocus(element)
                end
                element.popup = nil
            end,

            rightClick = function(element)
                if gui.GetFocus() ~= element then
                    gui.SetFocus(element)
                end

                --create the context menu for this folder.
                local menuItems = {}
                local parentElement = element

                --Delete and duplicate bestiary entries.
                if nodeid ~= '' then
                    menuItems[#menuItems + 1] = {
                        text = 'Edit Monster',
                        click = function(element)
                            local monster = node.monster

                            local token = monster:GetLocalGameBestiaryToken()
                            if token == nil then
                                monster:Upload()
                                dmhub.Coroutine(function()
                                    while token == nil do
                                        coroutine.yield(0.1)
                                        token = monster:GetLocalGameBestiaryToken()
                                    end
                                    token:ShowSheet()
                                end)
                            else
                                token:ShowSheet()
                            end

                            parentElement.popup = nil
                        end,
                    }


                    menuItems[#menuItems + 1] = {
                        text = 'Duplicate Monster',
                        click = function(element)
                            node:Duplicate()
                            parentElement.popup = nil
                        end,
                    }

                    menuItems[#menuItems + 1] = {
                        text = 'Delete Monster',

                        click = function(element)
                            node:Delete()
                            parentElement.popup = nil
                        end,
                    }

                    if devmode() then
                        local monster = node.monster
                        if monster.properties:has_key("import") then
                            menuItems[#menuItems + 1] = {
                                text = cond(monster.properties.import.override, 'Revert Override', 'Override Import'),
                                click = function(element)
                                    monster.properties.import.override = not monster.properties.import.override
                                    monster:Upload()
                                    parentElement.popup = nil
                                end,
                            }
                        end
                    end
                end

                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,
        },

        data = {
            ord = function()
                return "b" .. creature.GetTokenDescription(monster)
            end,

            nodeid = nodeid, --storing the nodeid with the panel for drag and drop.
            monsterid = nodeid, --makes it so this reports the monster id to GetSelectedMonster()

            search = function(text, matchedParent)
                searchActive = text ~= ''
                matchesSearch = matchedParent or text == '' or node:MatchesSearch(text)

                resultPanel:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))

                return matchesSearch
            end,

            --recursively turn search status off, for when we collapse a searched node. This doesn't globally disable
            --the search but makes us stop respecting it on this node.
            setSearchInactive = function(element)
                searchActive = false
            end,

            setParentCollapsed = function(element, newValue)
                parentCollapsed = newValue
                element:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))
            end,

            SetDepth = function(element, depth)
                element.data.depth = depth
            end,

            depth = 0,
        },

        children = {
            gui.Panel({
                classes = {"image"},
                bgimageStreamed = monster.portrait,
                bgimageTokenMask = monster.portraitFrame,

                selfStyle = {
                    imageRect = monster.portraitRect,
                },

                style = {
                    halign = 'left',
                    valign = 'center',
                    width = BestiaryPanelHeight,
                    height = BestiaryPanelHeight,
                },

                events = {
                    refreshAssets = function(element)
                        element.bgimageStreamed = monster.portrait
                        element.bgimageTokenMask = monster.portraitFrame
                        element.selfStyle.imageRect = monster.portraitRect
                    end,
                },

                children = {
                    gui.Panel({
                        classes = {"image"},
                        bgimage = monster.portraitFrame,
                        selfStyle = {
                            hueshift = monster.portraitFrameHueShift,
                            width = BestiaryPanelHeight,
                            height = BestiaryPanelHeight,
                        }
                    })
                },
            }),

            --Implementation status diamond next to the monster's name,
            --mirroring the diamond on ability cards. Styled inline because
            --the implementationDiamond style rules live in SpellRenderStyles,
            --which is scoped to ability rendering. Hover for an explanation
            --of the tiers plus this monster's per-ability/trait accounting.
            --Only shown for creature types with the implementation-status
            --API (Draw Steel monsters).
            gui.Panel({
                classes = { "implementationDiamond" },
                rotate = 45,
                width = 10,
                height = 10,
                bgimage = "panels/square.png",
                halign = "left",
                valign = "center",
                hmargin = 6,
                events = {
                    create = function(element)
                        element:FireEvent("refreshAssets")
                    end,
                    refreshAssets = function(element)
                        local props = monster.properties
                        --Reading an undefined field on a game-type object raises
                        --rather than returning nil, so feature-detect the
                        --monster-only implementation-status API via IsMonster()
                        --(defined on the base creature type) instead of a field read.
                        if props == nil or not props:IsMonster() then
                            element:SetClass("hidden", true)
                            return
                        end
                        element:SetClass("hidden", false)
                        local impl = props:GetImplementationStatus()
                        element.selfStyle.bgcolor = Styles.ImplementationStatusColors[impl]
                            or Styles.ImplementationStatusColors[1]
                    end,
                    hover = function(element)
                        local props = monster.properties
                        if props == nil or not props:IsMonster() then
                            return
                        end
                        local halign = "right"
                        local dock = element:FindParentWithClass("dock")
                        if dock ~= nil then
                            halign = dock.data.TooltipAlignment()
                        end
                        element.tooltip = gui.TooltipFrame(
                            props:RenderImplementationSummaryPanel{ includeExplanation = true },
                            {
                                halign = halign,
                                valign = "center",
                            }
                        )
                    end,
                },
            }),

            gui.Label({
                classes = { "bestiaryLabel" },
                text = creature.GetTokenDescription(monster),
                gui.NewContentAlertConditional("monsters", nodeid),
                refreshAssets = function(element)
                    local desc = creature.GetTokenDescription(monster)
                    local showImportStatus = false --disabled for now.
                    if showImportStatus and devmode() then
                        if monster.properties:has_key("import") then
                            local postfix = " <size=60%><color=#bbbbff>(imported)"
                            if monster.properties.import.override then
                                postfix = " <size=60%><color=#ffbbbb>(overridden)"
                            end
                            element.text = desc .. postfix
                        else
                            element.text = desc
                        end
                    else
                        element.text = desc
                    end
                end
            })
        }
    })

    return resultPanel
end

local CreateBestiaryFolder = function(nodeid)
    local matchesSearch = true
    local searchActive = false
    local isCollapsed = true
    local parentCollapsed = false

    local node = assets:GetMonsterNode(nodeid)

    local folderPane = nil

    --the root folder gets additional UI, such as a search and ways to add objects.
    local clearSearchButton = nil
    local rootPanel = nil
    if nodeid == '' then
        isCollapsed = false

        local updateSearch = function(element)
            clearSearchButton:SetClass("hidden", element.text == "")
            folderPane.data.search(element.text)
            if element.text ~= '' then
                local ok, ids = pcall(function() return node:GetNodeIdsMatchingSearch(element.text) end)
                local hasResults = nil
                local resultCount = nil
                if ok and type(ids) == 'table' then
                    resultCount = 0
                    for _ in pairs(ids) do resultCount = resultCount + 1 end
                    hasResults = resultCount > 0
                end
                track('search_monsters', {
                    query = element.text,
                    hasResults = hasResults,
                    resultCount = resultCount,
                    deduplicate = 0.5,
                    dailyLimit = 50,
                })
            end
        end

        local searchInput = gui.SearchInput {
            id = 'MonsterSearch',
            classes = {"bordered"},
            placeholderText = 'Search for Monsters...',
            editlag = 0.25,
            width = '65%',
            height = "100%-8",
            halign = 'left',
            valign = 'center',
            edit = updateSearch,
            change = updateSearch,
        }

        clearSearchButton = gui.Button {
            icon = "ui-icons/close.png",
            classes = {"hidden"},
            valign = "center",
            pad = 4,

            events = {
                press = function(element)
                    searchInput.text = ""
                    updateSearch(searchInput)
                end,
            }
        }

        local createBestiaryFolderButton = gui.Button {
            id = "CreateBestiaryFolderButton",
            icon = "game-icons/open-folder.png",
            valign = "center",
            hover = gui.Tooltip("Create a bestiary folder"),
            press = function(element)
                local maxOrd = 0
                for i, entry in ipairs(node.children) do
                    if entry.ord > maxOrd then
                        maxOrd = entry.ord
                    end
                end

                assets:UploadNewMonsterFolder({
                    description = "New Folder",
                    parentFolder = "",
                    ord = maxOrd + 1,
                })
            end,
        }

        local addBestiaryEntryButton = gui.Button {
            id = "AddBestiaryEntryButton",
            classes = {"addButton"},
            valign = "center",
            hover = gui.Tooltip("Create a bestiary entry"),
            press = function(element)
                local menuItems = {}
                local parentElement = element

                menuItems[#menuItems + 1] = {
                    text = 'Create Monster',
                    click = function(element)
                        local guid = assets:CreateBestiaryEntry()

                        local newMonster = assets.monsters[guid]
                        newMonster.properties = monster.CreateNew()

                        newMonster:Upload()

                        local token = newMonster:GetLocalGameBestiaryToken()
                        if token == nil then
                            dmhub.Coroutine(function()
                                while token == nil do
                                    coroutine.yield(0.1)
                                    token = newMonster:GetLocalGameBestiaryToken()
                                end
                                token:ShowSheet()
                            end)
                        else
                            token:ShowSheet()
                        end

                        parentElement.popup = nil
                    end,
                }
                menuItems[#menuItems + 1] = {
                    text = "Create Follower",
                    click = function(element)
                        local guid = assets:CreateBestiaryEntry()

                        local newFollower = assets.monsters[guid]
                        newFollower.properties = follower.CreateNew()

                        newFollower:Upload()

                        local token = newFollower:GetLocalGameBestiaryToken()
                        if token == nil then
                            dmhub.Coroutine(function()
                                while token == nil do
                                    coroutine.yield(0.1)
                                    token = newFollower:GetLocalGameBestiaryToken()
                                end
                                token:ShowSheet()
                            end)
                        else
                            token:ShowSheet()
                        end

                        parentElement.popup = nil
                    end,
                }

                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,
        }


        rootPanel =
            gui.Panel {
                id = 'RootUIPanel',
                x = 10,
                style = {
                    height = 'auto',
                    width = '90%',
                    flow = 'vertical',
                },

                children = {
                    gui.Panel {
                        id = 'ObjectSearchPanel',
                        style = {
                            height = 30,
                            width = '100%',
                            flow = 'horizontal',
                        },
                        children = {
                            searchInput,
                            clearSearchButton,
                            createBestiaryFolderButton,
                            addBestiaryEntryButton,
                        },
                    },
                },
            }
    end

    local triangle = nil
    triangle = gui.ExpandoArrow({
        halign = "left",
        margin = 5,
        valign = "center",
        styles = {
            {
                selectors = { "search" },
                transitionTime = 0,
                rotate = 0,
            },
        },

        swallowPress = true,

        events = {
            create = function(element)
                if nodeid == "" then
                    element:SetClass("collapsed", true)
                end
                element:SetClass("expanded", not isCollapsed)
                element:SetClass("empty", #node.children < 1)
            end,
            refreshAssets = function(element)
                element:SetClass('empty', #node.children < 1)
            end,
            press = function(element)
                if element:HasClass("collapsed") then
                    --the triangle itself isn't usable.
                    return
                end

                isCollapsed = not isCollapsed

                if searchActive then
                    isCollapsed = true
                    folderPane.data.setSearchInactive(folderPane)
                    element:SetClass('search', false)
                    searchActive = false

                    if clearSearchButton ~= nil then --is root panel, clear search.
                        clearSearchButton:FireEvent('press')
                    end
                end

                triangle:SetClass('expanded', not isCollapsed)
                folderPane.data.refreshCollapsed(folderPane)

                if not isCollapsed then
                    folderPane:FireEvent('expand')
                end
            end,
        },
    })


    local headerPanel = gui.Panel({

        bgimage = true,
        classes = { 'headerPanel', 'monster-drag-target' },
        dragTarget = true,

        draggable = nodeid ~= '',
        canDragOnto = function(element, target)
            return target:HasClass('monster-drag-target') and
            not IsMonsterNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
        end,

        selfStyle = {
            valign = 'top',
            halign = 'left',
            width = "100%",
            height = BestiaryPanelHeight,
            flow = 'horizontal',
        },

        data = {
            nodeid = nodeid, --store the node id here so it can be conveniently accessed when dragging.
        },

        events = {
            refreshAssets = function(element)
            end,

            drag = mod.shared.CreateDragTargetFunction(node, function(nodeid) return assets:GetMonsterNode(nodeid) end,
                "Monsters"),
        },

        children = {
            triangle,

            gui.Label({
                text = 'Bestiary',
                classes = { "bestiaryLabel", "folder", cond(nodeid == '', "noHoverColor") },
                x = 4,
                editableOnDoubleClick = (nodeid ~= ''), --all folders except the root Bestiary folder can be renamed.
                characterLimit = 24,
                events = {
                    change = function(element)
                        node.description = element.text
                        node:Upload()
                    end,
                    refreshAssets = function(element)
                        element.text = node.description
                    end,
                    press = function()
                        triangle:FireEvent('press')
                    end,
                    editname = function(element)
                        element:BeginEditing()
                    end,
                },
            }),
        },
    })

    local dragPanels = {}

    local elements = {}

    folderPane = gui.Panel({
        selfStyle = {
            pivot = { x = 0, y = 1 },
            pad = 0,
            margin = 0,
            width = "100%",
            height = 'auto',
            valign = 'top',
            flow = 'vertical',
        },

        classes = { cond(isCollapsed, "collapsed-anim"), "bestiaryPanel", "ignoreDrag" },

        data = {
            ord = function()
                return "a" .. node.description
            end,

            toggleCollapsed = function(element)
                triangle.events.press(triangle)
            end,
            isCollapsed = function()
                return isCollapsed
            end,

            setParentCollapsed = function(element, newValue)
                parentCollapsed = newValue
                element:SetClass('collapsed-anim', (parentCollapsed and not searchActive) or (not matchesSearch))
            end,

            --recursively turn search status off, for when we collapse a searched node. This doesn't globally disable
            --the search but makes us stop respecting it on this node.
            setSearchInactive = function(element)
                searchActive = false
                for k, v in pairs(elements) do
                    v.data.setSearchInactive(v)
                end
            end,

            refreshCollapsed = function(element)
                if rootPanel ~= nil then
                    rootPanel:SetClass('collapsed-anim', isCollapsed)
                end

                for k, v in pairs(elements) do
                    v.data.setParentCollapsed(v, isCollapsed)
                end

                for i, v in ipairs(dragPanels) do
                    v:SetClass('collapsed-anim', isCollapsed or searchActive)
                end

                --element.selfStyle.height = (BestiaryPanelHeight+4) * numElements
            end,

            search = function(text, matchedParent)
                local selfMatches = matchedParent or node:MatchesSearch(text)
                matchesSearch = selfMatches or (nodeid == '') --root node always matches searches.
                for k, el in pairs(elements) do
                    if el.data.search(text, selfMatches) then
                        matchesSearch = true
                    end
                end

                searchActive = text ~= ''

                folderPane:SetClass('collapsed-anim', (parentCollapsed and not searchActive) or (not matchesSearch))

                triangle:SetClass('search', searchActive)

                for i, v in ipairs(dragPanels) do
                    v:SetClass('collapsed-anim', isCollapsed or searchActive)
                end

                return matchesSearch
            end,

            SetDepth = function(element, depth)
                element.data.depth = depth
            end,

            depth = 0,
        },

        events = {
            press = function(element)
                element.popup = nil --clear any context menu on click.
            end,
            rightClick = function(element)
                --no context menu on the Bestiary root label.
                if nodeid == "" then
                    return
                end

                --create the context menu for this folder.
                local menuItems = {}
                local parentElement = element

                if nodeid ~= "" then
                    --Create a new folder as a child of this one.
                    menuItems[#menuItems + 1] = {
                        text = 'Rename Folder',
                        click = function(element)
                            headerPanel:FireEventTree("editname")
                            parentElement.popup = nil
                        end,
                    }
                end

                --Create a new folder as a child of this one.
                menuItems[#menuItems + 1] = {
                    text = 'Create Folder',

                    click = function(element)
                        local maxOrd = 0
                        for i, entry in ipairs(node.children) do
                            if entry.ord > maxOrd then
                                maxOrd = entry.ord
                            end
                        end

                        assets:UploadNewMonsterFolder({
                            description = 'New Folder',
                            parentFolder = nodeid,
                            ord = maxOrd + 1,
                        })

                        parentElement.popup = nil
                    end,
                }

                --Delete folder option.
                if nodeid ~= '' then
                    menuItems[#menuItems + 1] = {
                        text = 'Delete Folder',

                        click = function(element)
                            local CountMonsterEntries = nil
                            CountMonsterEntries = function(n)
                                local result = 0
                                for i, v in ipairs(n.children) do
                                    if v.folder ~= nil then
                                        result = result + CountMonsterEntries(v)
                                    else
                                        result = result + 1
                                    end
                                end

                                return result
                            end

                            local numChildren = CountMonsterEntries(node)

                            if numChildren == 0 then
                                --delete an empty folder without prompting.
                                node:Delete()
                            else
                                local msg = string.format(
                                'Do you really want to delete %s and the %d monster entries within?', node.description,
                                    numChildren)
                                if numChildren == 1 then
                                    msg = string.format('Do you really want to delete %s and the monster entry within?',
                                        node.description)
                                end

                                gamehud:ModalMessage({
                                    title = 'Delete Folder',
                                    message = msg,
                                    options = {
                                        {
                                            text = 'Okay',
                                            execute = function()
                                                node:Delete()
                                            end,
                                        },
                                        {
                                            text = 'Cancel',
                                        },
                                    }
                                })
                            end

                            parentElement.popup = nil
                        end,
                    }
                end


                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,

            refreshAssets = function(element)
                node = assets:GetMonsterNode(nodeid)


                local newElements = {}
                for i, v in ipairs(node.children) do
                    if not v.hidden then
                        if elements[v.id] == nil then
                            newElements[v.id] = CreateBestiaryNode(v)
                        else
                            newElements[v.id] = elements[v.id]
                        end

                        newElements[v.id].data.SetDepth(newElements[v.id], element.data.depth + 1)
                    end
                end

                local newChildren = { headerPanel, rootPanel }

                local newNodes = {}
                for i, v in ipairs(node.children) do
                    if not v.hidden then
                        newNodes[#newNodes + 1] = newElements[v.id]
                    end
                end

                table.sort(newNodes, function(a, b) return a.data.ord() < b.data.ord() end)

                for _, c in ipairs(newNodes) do
                    newChildren[#newChildren + 1] = c
                end

                elements = newElements

                element.children = newChildren

                element.x = element.data.depth * 10

                element.data.refreshCollapsed(element)
            end,
        },

        children = {
            headerPanel,
            rootPanel,
        }
    })

    return folderPane
end

CreateBestiaryNode = function(node)
    if node.folder ~= nil then
        return CreateBestiaryFolder(node.id)
    else
        return CreateMonsterEntry(node.id)
    end
end

--similar to a bestiary entry but is an entry for a live character.
CharacterPanel.CreateCharacterEntry = function(charid, party)
    local token = dmhub.GetCharacterById(charid)
    local creature = token.properties

    if creature == nil then
        return
    end

    local resultPanel = nil

    local novelContentAlert = nil
    if module.HasNovelContent("character", charid) then
        novelContentAlert = gui.NewContentAlert { x = -14 }
    end

    local playerStar = gui.Panel {
        bgimage = "icons/icon_simpleshape/icon_simpleshape_31.png",
        width = 16,
        height = 16,
        valign = "center",
        classes = {"playerStar"},
        prepareRefresh = function(element)
            resultPanel.data.primaryCharacter = token.playerControlledAndPrimary
            element:SetClass("hidden", not resultPanel.data.primaryCharacter)
        end,
    }

    local clickTime = nil


    resultPanel = gui.Panel {
        classes = { "characterEntry" },
        bgimage = true,
        valign = "top",
        width = "100%-6",
        height = BestiaryPanelHeight,
        flow = "horizontal",
        draggable = true,
        canDragOnto = function(element, target)
            return target ~= nil and target:HasClass('party-drag-target')
        end,

        events = {

            dragging = function(element, target)
                if target == nil then
                    dmhub.SetDraggingMonster()
                end
            end,

            drag = function(element, target)
                if target ~= nil and target:HasClass("partyPanel") then
                    target = target.data.header
                end
                if target == nil or not target:HasClass('party-drag-target') then
                    return
                end
                local newPartyId = target.data.partyid
                if newPartyId == nil then
                    return
                end

                local charids = { element.data.charid }
                for _, c in ipairs(characterPanelsSelected) do
                    if c.data.charid and c.data.charid ~= element.data.charid then
                        charids[#charids + 1] = c.data.charid
                    end
                end

                for _, cid in ipairs(charids) do
                    local tok = dmhub.GetCharacterById(cid)
                    if tok ~= nil then
                        tok.partyId = newPartyId
                    end
                end
            end,

            --render a tooltip of the character.
            hover = function(element)
                local dock = element:FindParentWithClass("dock")

                local panel = token:Render {}
                if panel ~= nil then
                    element.tooltip = gui.TooltipFrame(
                        panel,
                        {
                            halign = dock.data.TooltipAlignment(),
                            valign = "center",
                        }
                    )
                end
            end,

            refresh = function(element)

            end,

            moduleInstalled = function(element)
                local hasNovel = module.HasNovelContent("character", charid)
                if hasNovel and novelContentAlert == nil then
                    novelContentAlert = gui.NewContentAlert { x = -14 }
                    resultPanel:AddChild(novelContentAlert)
                elseif (not hasNovel) and novelContentAlert ~= nil then
                    novelContentAlert:DestroySelf()
                    novelContentAlert = nil
                end
            end,

            --fired by the 'sheet' command (i.e. 'c button')
            command = function(element, cmd)
                if cmd == "sheet" then
                    local tok = dmhub.GetCharacterById(charid)
                    if tok ~= nil then
                        tok:ShowSheet()
                    end
                end
            end,

            select = function(element, click)
                local forceAdd = not click

                local addSelection = forceAdd or dmhub.modKeys['ctrl'] or dmhub.modKeys['shift']
                if addSelection and element:HasClass("selected") then
                    RemoveCharacterPanelSelection(element)
                elseif gui.GetFocus() == element then
                    if addSelection and #characterPanelsSelected > 0 then
                        gui.SetFocus(characterPanelsSelected[#characterPanelsSelected])
                        RemoveCharacterPanelSelection(gui.GetFocus())
                    else
                        ClearCharacterPanelSelection()
                        gui.SetFocus(nil)
                    end
                else
                    if addSelection then
                        if gui.GetFocus() ~= nil and gui.GetFocus().data.charid then
                            AddCharacterPanelToSelection(gui.GetFocus())

                            --if shift is held, then select all characters between.
                            if dmhub.modKeys['shift'] and gui.GetFocus().parent == element.parent then
                                local selecting = false
                                for _, child in ipairs(gui.GetFocus().parent.children) do
                                    if child == gui.GetFocus() or child == element then
                                        selecting = not selecting
                                    elseif selecting then
                                        AddCharacterPanelToSelection(child)
                                    end
                                end
                            end
                        end
                    else
                        ClearCharacterPanelSelection()
                    end

                    gui.SetFocus(element)
                end
                element.popup = nil

            end,

            press = function(element)
                if clickTime ~= nil and clickTime > dmhub.Time() - 0.4 then
                    --double-click
                    clickTime = nil
                    dmhub.CenterOnToken(charid, function()
                        dmhub.SelectToken(charid)
                    end)
                    gui.SetFocus(nil)
                    return
                end

                clickTime = dmhub.Time()

                element:FireEvent("select", true)

            end,

            rightClick = function(element)
                if gui.GetFocus() ~= element and not element:HasClass("selected") then
                    --if this isn't selected, then treat it as a selection click.
                    element:FireEvent("press")
                end

                --create the context menu for this folder.
                local menuItems = {}
                local parentElement = element

                --go to the token's character sheet.
                menuItems[#menuItems + 1] = {
                    text = "Character Sheet",

                    click = function(element)
                        local tok = dmhub.GetCharacterById(charid)
                        if tok ~= nil then
                            tok:ShowSheet()
                        end
                        parentElement.popup = nil
                    end,
                }

                --Teleport to token, same as double click.
                local tok = dmhub.GetCharacterById(charid)
                if tok ~= nil and tok.valid and tok.hasTokenOnAnyMap then
                    menuItems[#menuItems + 1] = {
                        text = "Select Token",

                        click = function(element)
                            local canCenter = dmhub.CenterOnToken(charid, function()
                                dmhub.SelectToken(charid)
                            end)
                            gui.SetFocus(nil)
                            parentElement.popup = nil
                        end,
                    }
                end

                menuItems[#menuItems + 1] = {
                    text = cond(token.invisibleToPlayers, 'Make Visible to Players', 'Make Invisible to Players'),

                    click = function(element)
                        local invisible = not token.invisibleToPlayers

                        --make this operate on all selected characters.
                        for _, charid in ipairs(dmhub.GetSelectedCharacters()) do
                            local tok = dmhub.GetCharacterById(charid)
                            if tok ~= nil then
                                tok.invisibleToPlayers = invisible
                            end
                        end

                        parentElement.popup = nil
                    end,
                }


                --party settings.
                local tok = dmhub.GetCharacterById(charid)
                local tokenPartyId = tok ~= nil and tok.partyId
                if tokenPartyId then
                    menuItems[#menuItems + 1] = {
                        text = "Party Settings",
                        click = function(element)
                            Compendium.ShowModalEditDialog(Party, tokenPartyId)
                            parentElement.popup = nil
                        end,
                    }
                end

                --reset the character to its state in the module it came from.
                if module.IsCharacterAvailableInModule(charid) then
                    menuItems[#menuItems + 1] = {
                        text = "Reset Character",

                        click = function(element)
                            gamehud:ModalMessage {
                                title = "Reset Character?",
                                message = "Are you sure you want to reset this character to its state in the module? Any changes made to it will be lost.",
                                options = {
                                    {
                                        text = "Reset",
                                        execute = function()
                                            module.ReinstallCharacter(charid, function(success)
                                                print("ReinstallCharacter::", success)
                                            end)
                                        end,
                                    },
                                    {
                                        text = "Cancel",
                                        execute = function()
                                        end,
                                    },
                                }
                            }
                            parentElement.popup = nil
                        end,
                    }
                end

                --delete the token.
                menuItems[#menuItems + 1] = {
                    text = "Delete Character",

                    click = function(element)
                        local charids = {charid}
                        for _, c in ipairs(characterPanelsSelected) do
                            if c.data.charid ~= charid then
                                charids[#charids + 1] = c.data.charid
                            end
                        end
                        gamehud:ModalMessage {
                            title = cond(#charids == 1, "Delete Character?", "Delete Characters?"),
                            message = cond(#charids == 1, "Are you sure you want to delete this character? They will be gone forever.",
                              string.format("Are you sure you want to delete these %d characters? They will be gone forever.", #charids)),
                            options = {
                                {
                                    text = "Delete",
                                    execute = function()
                                        for _, cid in ipairs(charids) do
                                            local tok = dmhub.GetCharacterById(cid)
                                            if tok ~= nil then
                                                local classInfo = tok.properties:IsHero() and tok.properties:GetClass() or nil
                                                track("character_delete", {
                                                    class = classInfo and classInfo.name or "",
                                                    ancestry = tok.properties:RaceOrMonsterType() or "",
                                                    level = tok.properties:CharacterLevel(),
                                                    dailyLimit = 5,
                                                })
                                            end
                                        end
                                        game.DeleteCharacters(charids)
                                        gui.SetFocus(nil)
                                    end,
                                },
                                {
                                    text = "Cancel",
                                    execute = function()
                                    end,
                                },
                            }
                        }
                        parentElement.popup = nil
                    end,
                }


                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,

            focus = function(element)
            end,

            defocus = function(element, newFocus)
                if (not newFocus) or not newFocus.data.charid then
                    --if we aren't transferring focus to another character panel then clear the selection.
                    ClearCharacterPanelSelection()
                end
            end,
        },

        data = {
            charid = charid,
            token = token,
            primaryCharacter = false,
        },

        children = {

            playerStar,
            novelContentAlert,

            gui.CreateTokenImage(token, {
                width = BestiaryPanelHeight,
                height = BestiaryPanelHeight,
                halign = "left",

                refresh = function(element)
                    if token == nil or not token.valid then
                        return
                    end

                    element:FireEventTree("token", token)
                end,
            }),

            gui.Label({
                classes = { "bestiaryLabel" },
                halign = "left",
                text = creature.GetTokenDescription(token),
                refresh = function(element)
                    local desc = creature.GetTokenDescription(token)
                    local playerName = token.playerNameOrNil
                    if playerName ~= nil then
                        local color = token.playerColor.tostring
                        desc = string.format("%s (<color=%s>%s</color>)", desc, color, playerName)
                    end
                    element.text = desc
                    element:SetClass("invisible", token.invisibleToPlayers)
                end,
            })
        }
    }

    return resultPanel
end

CharacterPanel.PopulatePartyMembers = function(element, party, partyMembers, memberPanes)

    local children = {}
    local newMemberPanes = {}

    for _, charid in ipairs(partyMembers) do
        local child = memberPanes[charid] or CharacterPanel.CreateCharacterEntry(charid, party)
        newMemberPanes[charid] = child
        child:FireEventTree("prepareRefresh")
        children[#children + 1] = child
    end

    table.sort(children, function(a, b)
        local aname = a.data.token.playerNameOrNil
        local bname = b.data.token.playerNameOrNil
        if aname == nil and bname == nil then
            return a.data.token.description < b.data.token.description
        end

        if aname == nil then
            return false
        end

        if bname == nil then
            return true
        end

        if aname == bname then
            return cond(a.data.primaryCharacter, 0, 1) < cond(b.data.primaryCharacter, 0, 1)
        end

        return aname < bname
    end)

    element.children = children

    return newMemberPanes
end

--create a folder with character entries for all characters in a party.
--If partyid is nil it will create a 'party' for all monsters on the map.
CharacterPanel.CreatePartyCharacters = function(partyid)
    local resultPanel

    local isCollapsed = GetPartyCollapsed(partyid, partyid == nil or partyid == "graveyard")

    local party
    local partyMembers
    local partyName = ""

    local RefreshParty = function()
        if partyid == nil then
            party = nil
            local tokens = dmhub.GetTokens {
                unaffiliated = true,
            }
            partyMembers = {}
            for _, tok in ipairs(tokens) do
                partyMembers[#partyMembers + 1] = tok.charid
            end

            partyName = "Director Controlled (This map)"
        elseif partyid == "graveyard" then
            party = nil
            local tokens = dmhub.despawnedTokens
            partyMembers = {}
            for _, tok in ipairs(tokens) do
                partyMembers[#partyMembers + 1] = tok.charid
            end

            partyName = "Dead Monsters"
        else
            party = dmhub.GetTable(Party.tableName)[partyid]
            partyMembers = dmhub.GetCharacterIdsInParty(partyid)
            partyName = party.name
        end
    end

    RefreshParty()

    local folderPane
    local selectAllPanel = nil

    local triangle = nil
    triangle = gui.ExpandoArrow({
        -- width = 8,
        -- height = 8,
        halign = "left",
        margin = 5,
        valign = "center",

        swallowPress = true,

        events = {
            create = function(element)
                element:SetClass('expanded', not isCollapsed)
                element:SetClass('empty', #partyMembers < 1)
            end,
            refresh = function(element)
                element:SetClass('empty', #partyMembers < 1)
            end,
            press = function(element)
                print("PRESS:: TRIANGLE PRESSED")
                if element:HasClass("collapsed") then
                    --the triangle itself isn't usable.
                    return
                end

                if #partyMembers == 0 then
                    return
                end

                isCollapsed = not isCollapsed
                SetPartyCollapsed(partyid, isCollapsed)

                triangle:SetClass('expanded', not isCollapsed)
                folderPane:FireEvent("refreshCollapsed")
                if selectAllPanel ~= nil then
                    selectAllPanel:FireEvent("refreshCollapsed")
                end

                if not isCollapsed then
                    folderPane:FireEvent('expand')
                end
            end,
        },
    })

    local memberPanes = {}

    local headerPanel = gui.Panel {

        bgimage = true,
        classes = { 'monster-drag-target', cond(party ~= nil, 'party-drag-target'), 'headerPanel' },
        dragTarget = true,

        data = {
            partyid = party and party.id,
        },

        draggable = false,
        canDragOnto = function(element, target)
            return false --target:HasClass('monster-drag-target') and not IsMonsterNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
        end,

        selfStyle = {
            valign = 'top',
            halign = 'left',
            width = "100%",
            height = BestiaryPanelHeight,
            flow = 'horizontal',
        },

        events = {
            refreshAssets = function(element)
            end,

            press = function(element, synthetic)
                if not synthetic then
                    element.parent:FireEventTree("select")
                end
            end,

            rightClick = function(element)
                if party ~= nil then
                    local entries = {
                        {
                            text = "Party Settings",
                            click = function()
                                Compendium.ShowModalEditDialog(Party, party.id)
                                element.popup = nil
                            end,
                        },
                    }
                    local DeleteParty = function()
                        party.hidden = true
                        dmhub.SetAndUploadTableItem(Party.tableName, party)
                        --rebuild the party list so the now-deleted party
                        --disappears immediately instead of only on reload.
                        element:FireEventOnParents("refreshAssets")
                    end

                    entries[#entries + 1] = {
                        text = "Delete Party",
                        click = function()
                            element.popup = nil

                            local memberCount = #dmhub.GetCharacterIdsInParty(party.id)
                            if memberCount == 0 then
                                DeleteParty()
                                return
                            end

                            gamehud:ModalMessage {
                                title = "Delete Party?",
                                message = string.format("This party still has %d %s in it. Are you sure you want to delete it? The %s will not be deleted.", memberCount, cond(memberCount == 1, "character", "characters"), cond(memberCount == 1, "character", "characters")),
                                options = {
                                    {
                                        text = "Delete",
                                        execute = function()
                                            DeleteParty()
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
                    element.popup = gui.ContextMenu { entries = entries }
                elseif partyid == "graveyard" then
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Clear Dead Monsters",
                                click = function()
                                    local tokens = dmhub.despawnedTokens
                                    local charids = {}
                                    local objectTokens = dmhub.allObjectTokens
                                    for _,tok in ipairs(tokens) do
                                        charids[#charids+1] = tok.charid

                                        local corpse = tok:FindCorpse()
                                        if corpse ~= nil then
                                            corpse.objectInstance:Destroy()
                                        end

                                        local classInfo = tok.properties:IsHero() and tok.properties:GetClass() or nil
                                        track("character_delete", {
                                            class = classInfo and classInfo.name or "",
                                            ancestry = tok.properties:RaceOrMonsterType() or "",
                                            level = tok.properties:CharacterLevel(),
                                            dailyLimit = 5,
                                        })
                                    end
                                    game.DeleteCharacters(charids)
                                    element.popup = nil
                                end,
                            }
                        }
                    }
                end
            end,

        },

        children = {
            triangle,

            gui.Label {
                text = partyName,
                classes = { "bestiaryLabel", "folder" },
                editableOnDoubleClick = false,
                characterLimit = 24,
                events = {
                    change = function(element)
                        party.name = element.text
                        dmhub.SetAndUploadTableItem(Party.tableName, party)
                    end,
                    refresh = function(element)
                        element.text = partyName
                    end,
                },
            },

        },
    }


    folderPane = gui.Panel {
        classes = { cond(isCollapsed, "collapsed"), "ignoreDrag" },
        flow = "vertical",
        width = "auto",
        height = "auto",

        refreshCollapsed = function(element)
            element:SetClass("collapsed", isCollapsed)
        end,

        create = function(element)
            element:FireEvent("refresh")
        end,

        refresh = function(element)
            if isCollapsed or resultPanel.data.parentCollapsed then
                return
            end

            memberPanes = CharacterPanel.PopulatePartyMembers(element, party, partyMembers, memberPanes)
            if selectAllPanel ~= nil then
                selectAllPanel:FireEvent("refreshCollapsed")
            end
        end,

        expand = function(element)
            element:FireEvent("refresh")
        end,

    }



    resultPanel = gui.Panel {
        classes = {"partyPanel", "ignoreDrag"},
        flow = "vertical",
        width = "auto",
        height = "auto",
        bgimage = true,
        bgcolor = "clear",

        data = {
            parentCollapsed = false,
            ord = function()
                if party == nil then
                    return 999999
                end
                return party.ord
            end,
            header = headerPanel,
        },


        --events accepted to change selection of characters.
        AddCharacterPanelToSelection = function(element, panel)
            AddCharacterPanelToSelection(panel)
        end,

        ClearCharacterPanelSelection = function(element)
            ClearCharacterPanelSelection()
        end,

        refresh = function(element)
            RefreshParty()
        end,

        headerPanel,
        folderPane,

    }

    return resultPanel
end


local CreateBestiaryAndPartyPanel = function(noBestiary)
    local partyPanels = {}

    local bestiaryPanel = nil
    if not noBestiary then
        bestiaryPanel = CreateBestiaryFolder('')
    end
    local resultPanel
    resultPanel = gui.Panel {
        flow = "vertical",
        width = "auto",
        height = "auto",

        refresh = function(element)
            if element:HasClass("collapsed") then
                --we don't allow refresh events through if we are collapsed.
                element:HaltEventPropagation()
            end
        end,

        refreshAssets = function(element)
            local newPartyPanels = {}
            local allParties = GetAllParties()
            local children = {}
            for _, k in ipairs(allParties) do
                newPartyPanels[k] = partyPanels[k] or CharacterPanel.CreatePartyCharacters(k)

                children[#children + 1] = newPartyPanels[k]
            end

            newPartyPanels['unaffiliated'] = partyPanels['unaffiliated'] or CharacterPanel.CreatePartyCharacters(nil)
            newPartyPanels['graveyard'] = partyPanels['graveyard'] or CharacterPanel.CreatePartyCharacters('graveyard')
            children[#children + 1] = newPartyPanels['unaffiliated']
            children[#children + 1] = newPartyPanels['graveyard']

            table.sort(children, function(a, b) return a.data.ord() < b.data.ord() end)


            children[#children + 1] = gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                rmargin = 8,

                gui.Button {
                    icon = "icons/icon_app/icon_app_18.png",
                    halign = "right",
                    hover = gui.Tooltip("Create a party"),
                    press = function(element)
                        local newParty = Party.CreateNew()
                        dmhub.SetAndUploadTableItem(Party.tableName, newParty)
                        Compendium.ShowModalEditDialog(Party, newParty.id)
                        resultPanel:FireEventTree("refreshAssets")
                    end,
                },

                gui.Button {
                    classes = {"addButton"},
                    id = "AddCharacterButton",
                    halign = "right",
                    hover = gui.Tooltip("Create a character"),

                    data = {
                        newchar = "",
                        newcharTime = 0,
                    },
                    press = function(element)
                        local createChar = function(chartype)
                            local charid = game.CreateCharacter("character", chartype)
                            element.data.newchar = charid
                            element.data.newcharTime = dmhub.Time()
                            element.monitorGame = string.format("/characters/%s", charid)
                            mod.shared.CompleteTutorial("Create a Character")
                        end

                        local menuItems = {}

                        local characterTypes = dmhub.GetTable(CharacterType.tableName)
                        for k, v in pairs(characterTypes) do
                            if not v:try_get("hidden", false) then
                                local chartype = k
                                menuItems[#menuItems + 1] = {
                                    text = string.format("Create %s", v.name),
                                    click = function()
                                        element.popup = nil
                                        createChar(chartype)
                                    end,
                                }
                            end
                        end

                        if #menuItems == 0 then
                            createChar()
                        elseif #menuItems == 1 then
                            menuItems[1].click()
                        else
                            element.popup = gui.ContextMenu {
                                entries = menuItems,
                            }
                        end
                    end,
                    refreshGame = function(element)
                        if element.data.newchar ~= "" and element.data.newcharTime > dmhub.Time() - 2 then
                            local tok = dmhub.GetCharacterById(element.data.newchar)
                            if tok ~= nil then
                                tok:ShowSheet("Appearance")

                                -- Track character_create after the sheet closes so
                                -- ancestry/class/kit reflect actual player choices.
                                local trackToken = tok
                                local handler
                                handler = dmhub.RegisterEventHandler("characterSheetClosed", function()
                                    dmhub.DeregisterEventHandler(handler)
                                    handler = nil
                                    local c = trackToken
                                    if c ~= nil and c.valid then
                                        local classInfo = c.properties:GetClass()
                                        local kitTable = dmhub.GetTable("kits")
                                        local kitId = c.properties:try_get("kitid")
                                        track("character_create", {
                                            ancestry = c.properties:RaceOrMonsterType() or "",
                                            class = classInfo and classInfo.name or "",
                                            kit = (kitId and kitTable[kitId]) and kitTable[kitId].name or "",
                                            method = "panel",
                                            dailyLimit = 5,
                                        })
                                    end
                                end)
                            end
                        end

                        element.data.newchar = ""
                        element.monitorGame = nil
                    end,
                },
            }


            children[#children + 1] = bestiaryPanel
            partyPanels = newPartyPanels

            element.children = children
        end,

        bestiaryPanel,
    }

    return resultPanel
end

CreateCharacterPanel = function()
    local multiEditPanel = nil
    local tokenPanels = {}
    local singleTokenDetailsPanel = nil
    local bestiaryPanel = nil
    if dmhub.isDM then
        bestiaryPanel = CreateBestiaryAndPartyPanel(true) --no actual bestiary
        bestiaryPanel:FireEventTree("refreshAssets")
        bestiaryPanel:FireEventTree("refresh")
    end
    local resultPanel
    resultPanel = gui.Panel {
        styles = ThemeEngine.MergeStyles(g_sidebarExtras),

        flow = "vertical",
        width = "100%",
        height = "auto",
        monitorAssets = cond(bestiaryPanel ~= nil, "Monsters"),
        refreshAssets = function(element)
            if bestiaryPanel ~= nil then
                bestiaryPanel:FireEventTree("refreshAssets")
            end
        end,
        refresh = function(element)
            local hasVisible = false
            local newChildren = {}
            local createdNew = false
            local tokens = dmhub.tokenInfo.selectedOrPrimaryTokens
            if #tokens > 1 then
                if multiEditPanel == nil then
                    createdNew = true
                    multiEditPanel = CharacterPanel.CreateMultiEdit()
                end
            end

            if multiEditPanel ~= nil then
                newChildren[#newChildren + 1] = multiEditPanel
                multiEditPanel:FireEvent("tokens", tokens)
            end

            table.sort(tokens, function(a,b)
                return creature.GetTokenDescription(a) < creature.GetTokenDescription(b)
            end)

            for i, token in ipairs(tokens) do
                local panel = tokenPanels[i]
                if panel == nil then
                    panel = CharacterPanel.SingleCharacterDisplaySidePanel(token)
                    tokenPanels[i] = panel
                    createdNew = true
                end

                panel:SetClass("collapsed", not token.valid)

                if token.valid then
                    hasVisible = true
                    panel:FireEvent("setToken", token)
                end
            end

            for i = 1, #tokenPanels do
                if i > #tokens then
                    tokenPanels[i]:SetClass("collapsed", true)
                end
                newChildren[#newChildren + 1] = tokenPanels[i]
            end

            local panelTitle = nil

            if #tokens == 1 then
                if singleTokenDetailsPanel == nil then
                    singleTokenDetailsPanel = CharacterDetailsPanel(tokens[1])
                    createdNew = true
                end

                singleTokenDetailsPanel:SetClass("collapsed", false)
                if tokens[1] ~= nil and tokens[1].properties ~= nil then
                    singleTokenDetailsPanel:FireEvent("dirtyToken", tokens[1])
                end

                panelTitle = creature.GetTokenDescription(tokens[1])
            elseif singleTokenDetailsPanel ~= nil then
                singleTokenDetailsPanel:SetClass("collapsed", true)
            end

            element:FireEventOnParents("title", panelTitle)

            if singleTokenDetailsPanel ~= nil then
                newChildren[#newChildren + 1] = singleTokenDetailsPanel
            end

            if bestiaryPanel ~= nil then
                bestiaryPanel:SetClass("collapsed", hasVisible)
                newChildren[#newChildren + 1] = bestiaryPanel
            end

            --if createdNew or #newChildren ~= #element.children then
            element.children = newChildren
            --end

        end,

        bestiaryPanel,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.MergeStyles(g_sidebarExtras)
        end
    end)

    return resultPanel
end

CreateBestiaryPanel = function()
    local tokenPanels = {}
    local singleTokenDetailsPanel = nil
    local bestiaryPanel = nil
    bestiaryPanel = CreateBestiaryFolder('')
    bestiaryPanel:FireEventTree("refreshAssets")
    bestiaryPanel:FireEventTree("refresh")
    local resultPanel
    resultPanel = gui.Panel {
        styles = ThemeEngine.MergeStyles(g_sidebarExtras),

        flow = "vertical",
        width = "100%",
        height = "auto",
        monitorAssets = cond(bestiaryPanel ~= nil, "Monsters"),
        refreshAssets = function(element)
            if bestiaryPanel ~= nil then
                bestiaryPanel:FireEventTree("refreshAssets")
            end
        end,
        refresh = function(element)

        end,

        bestiaryPanel,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.MergeStyles(g_sidebarExtras)
        end
    end)

    return resultPanel
end

-- =============================================================================
-- Bestiary global-search provider + place-on-map.
--
-- Monsters live in assets.monsters (an ASSET table keyed by id, not a
-- dmhub.GetTable), so the compendium-content provider never sees them. This
-- provider surfaces them in global search; activating a result enters the
-- ENGINE'S OWN placement mode: the engine polls dmhub.GetSelectedMonster
-- (see top of this file), and whenever the focused panel carries
-- data.monsterid it renders the cursor preview and spawns the monster on a
-- map click - exactly what pressing a bestiary row does. We just focus a
-- small proxy panel carrying the monster id, so placement from search is
-- pixel-identical to placement from the bestiary (preview, naming, minion
-- squad quantity, repeat placement, right-click/escape to exit).
-- Right-clicking a result offers the bestiary's other affordance: opening the
-- monster's sheet for editing.
-- =============================================================================

--Fire a "revealCapability" event on the open sheet once it exists, so the
--sheet expands the section holding the matched ability (action list) or
--selects the Features sub-tab holding the matched trait. Retries briefly
--while the sheet builds, mirroring
--FeatureCategoriser.OpenSheetAtFeaturesTab's trySelect. A no-op when no
--capability was threaded through (e.g. right-click "Edit Monster").
local function RevealCapabilityOnSheet(capName, categorization)
    if type(capName) ~= "string" or capName == "" then
        return
    end
    local attempts = 0
    local function tryReveal()
        if mod.unloaded then
            return
        end
        local sheet = rawget(CharacterSheet, "instance")
        if sheet ~= nil and sheet ~= false and sheet.valid then
            sheet:FireEventTree("revealCapability", capName, categorization)
            return
        end
        attempts = attempts + 1
        if attempts < 20 then
            dmhub.Schedule(0.1, tryReveal)
        end
    end
    tryReveal()
end

--Open the monster's character sheet for editing. Same pattern as the
--bestiary right-click "Edit Monster" menu item above: the sheet works on the
--monster's local-game bestiary token, which may need an upload to exist.
--capName/categorization (optional) come from a search result: after the
--sheet opens we reveal that capability (expand its section / select its tab).
local function EditBestiaryMonster(monsterid, capName, categorization)
    local monster = assets.monsters[monsterid]
    if monster == nil or not dmhub.inGame then
        return
    end

    local token = monster:GetLocalGameBestiaryToken()
    if token == nil then
        monster:Upload()
        dmhub.Coroutine(function()
            while token == nil do
                coroutine.yield(0.1)
                if mod.unloaded then
                    return
                end
                token = monster:GetLocalGameBestiaryToken()
            end
            token:ShowSheet()
            RevealCapabilityOnSheet(capName, categorization)
        end)
    else
        token:ShowSheet()
        RevealCapabilityOnSheet(capName, categorization)
    end
end

--Enter the engine's bestiary placement mode for a monster. gui.ShowPlacementBanner
--focuses a banner carrying data.monsterid; the engine polls dmhub.GetSelectedMonster
--(top of this file) against the focused panel and spawns that monster on each map
--click (cursor preview, naming, minion squads, repeat placement). Monsters omit the
--completion predicate so they keep the bestiary's repeat placement.
local function BeginPlacingMonster(monsterid)
    if not dmhub.inGame then
        return
    end

    local monster = assets.monsters[monsterid]
    if monster == nil then
        return
    end

    gui.ShowPlacementBanner{name = monster.name, data = {monsterid = monsterid}}
end

--Enter the engine's character placement mode for an existing (unplaced)
--character token - the same deploy flow as pressing a character's row in the
--character panel and clicking the map.
local function BeginPlacingCharacter(charid)
    if not dmhub.inGame then
        return
    end

    local tok = dmhub.GetCharacterById(charid)
    if tok == nil then
        return
    end

    --exit placement once the token lands on the map. Membership of allTokens
    --matches the provider's definition of "unplaced" (hasTokenOnThisMap is
    --true for despawned tokens, which would end the mode before the click).
    --Characters are single-placement (the click MOVES the one token rather than
    --stamping copies), so the mode ends on landing via the completion predicate.
    gui.ShowPlacementBanner{
        name = tok.name,
        data = {charid = charid},
        complete = function()
            for _,token in ipairs(dmhub.allTokens) do
                if token.id == charid then
                    return true
                end
            end
            return false
        end,
    }
end

--Global-search provider: party characters NOT placed on the current map (the
--tokens provider in CodexTitleBar covers placed ones, so a hero is never
--listed twice). Activation mirrors the bestiary: left-click enters the
--engine's character placement mode (click the map to deploy); the right-click
--menu offers placement and the character sheet. Players see only player-
--controlled heroes; the DM sees every party member.
Search.RegisterProvider{
    id = "partyCharacters",
    bucket = "ingame",
    enumerate = function(needle)
        -- Director-only: activation enters the engine's placement mode, which
        -- is a director action. Players were offered a "place on map" prompt
        -- they cannot fulfil, so unplaced-character search is gated to the DM.
        if (not dmhub.inGame) or (not dmhub.isDM) then
            return {}
        end
        local placed = {}
        for _,token in ipairs(dmhub.allTokens) do
            placed[token.id] = true
        end
        local results = {}
        local seen = {}
        local parties = dmhub.GetTable(Party.tableName) or {}
        for partyid,_ in unhidden_pairs(parties) do
            for _,charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
                if not placed[charid] and not seen[charid] then
                    seen[charid] = true
                    local tok = dmhub.GetCharacterById(charid)
                    if tok ~= nil then
                        local name = tok.name
                        if type(name) == "string" and name ~= "" and Search.MatchesText(name, needle) then
                            local capturedTok = tok
                            local capturedId = charid
                            results[#results+1] = {
                                name = name,
                                score = Search.Score(name, needle),
                                typeLabel = cond(tok.playerControlled, "Hero", "NPC"),
                                activate = function()
                                    BeginPlacingCharacter(capturedId)
                                end,
                                -- Ordered actions (primary first). The search UI
                                -- shows these as chips under the row; the first
                                -- mirrors the row press.
                                actions = {
                                    {
                                        text = "Place on Map",
                                        click = function()
                                            BeginPlacingCharacter(capturedId)
                                        end,
                                    },
                                    {
                                        text = "Character Sheet",
                                        click = function()
                                            capturedTok:ShowSheet()
                                        end,
                                    },
                                },
                            }
                        end
                    end
                end
            end
        end
        return results
    end,
}

--Global-search provider over the bestiary. DM-only: the bestiary is GM
--content and players should not discover unrevealed monsters through search.
Search.RegisterProvider{
    id = "monsters",
    bucket = "compendium",
    typeLabel = "Monster",
    enumerate = function(needle)
        if (not dmhub.isDM) or (not dmhub.inGame) then
            return {}
        end

        local results = {}
        for monsterid,monster in pairs(assets.monsters) do
            local name = monster.name
            local props = monster.properties

            --Name match first; otherwise try the monster's attributes - role
            --("Platoon Brute"), keywords (Undead, Goblin, ...) and "level N" -
            --so a director building an encounter can search "level 3 brute" or
            --"horde undead", not just names. Attribute-only hits score below
            --any name match and carry a "Level N Role" subhead so the row
            --explains why it matched.
            local score = 0
            local subLabel = nil
            if (not monster.hidden) and type(name) == "string" then
                if Search.MatchesText(name, needle) then
                    score = Search.Score(name, needle)
                elseif props ~= nil then
                    local role = props:try_get("role")
                    local level = props:try_get("cr")
                    local parts = {}
                    if type(role) == "string" then
                        parts[#parts+1] = role
                    end
                    for kw,v in pairs(props:try_get("keywords") or {}) do
                        if v == true and type(kw) == "string" and kw ~= "_luaTable" then
                            parts[#parts+1] = kw
                        end
                    end
                    if level ~= nil then
                        parts[#parts+1] = string.format("level %s", tostring(level))
                    end
                    if #parts > 0 and Search.MatchesText(table.concat(parts, " "), needle) then
                        score = 20
                        if level ~= nil and type(role) == "string" then
                            subLabel = string.format("Level %s %s", tostring(level), role)
                        elseif type(role) == "string" then
                            subLabel = role
                        elseif level ~= nil then
                            subLabel = string.format("Level %s", tostring(level))
                        end
                    end
                end
            end

            if score > 0 then
                local capturedId = monsterid

                --Beastheart animal companions live in the bestiary too; label
                --them honestly rather than as monsters.
                local typeLabel = "Monster"
                if props ~= nil and (not props:IsMonster()) then
                    typeLabel = "Companion"
                end

                results[#results+1] = {
                    name = name,
                    score = score,
                    subLabel = subLabel,
                    typeLabel = typeLabel,
                    activate = function()
                        BeginPlacingMonster(capturedId)
                    end,
                    -- Ordered actions (primary first); shown as chips, the first
                    -- mirrors the row press.
                    actions = {
                        {
                            text = "Place on Map",
                            click = function()
                                BeginPlacingMonster(capturedId)
                            end,
                        },
                        {
                            text = "Edit Monster",
                            click = function()
                                EditBestiaryMonster(capturedId)
                            end,
                        },
                    },
                }
            end
        end
        return results
    end,
}

-- Hero/NPC/Monster label for a placed token, mirroring CodexTitleBar's
-- TokenKindLabel (a file-local there, so duplicated here for the map context
-- provider). IsMonster is the discriminator; player-controlled = Hero. The
-- "(on Map)" suffix marks these as deployed -- it distinguishes a placed token
-- from the same kind of UNPLACED creature (partyCharacters provider, plain
-- "Hero"/"NPC") when both can land in the "In this Campaign" bucket.
local function MapTokenKindLabel(token)
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

-- Title for a map note (info bubble): the backing document's title -- which is
-- what the user names the note -- not the bubble's own .description (that can
-- be a stale section heading). Every engine read is pcall-guarded: reading a
-- missing method/field on these userdata objects ERRORS rather than returning
-- nil. Falls back to the bubble description.
local function MapNoteTitle(bubble)
    local ok, doc = pcall(function() return bubble.document end)
    if ok and doc ~= nil then
        local okm, md = pcall(function() return doc:GetMarkdownDocument() end)
        if okm and md ~= nil then
            local okd, desc = pcall(function() return md.description end)
            if okd and type(desc) == "string" and desc ~= "" then
                return desc
            end
        end
    end
    local okb, d = pcall(function() return bubble.description end)
    if okb and type(d) == "string" and d ~= "" then
        return d
    end
    return nil
end

-- Forward declaration: the per-token capability matcher used by the map-view
-- provider below. Defined (with its short-TTL cache) alongside the bestiary
-- capability index further down -- after MONSTER_ABILITY_CATEGORIES -- so the
-- global index and the on-map matcher share one ExtractMonsterCapabilities
-- classifier.
local GetMonsterTokenCapabilities

-- Context-sensitive search provider: the open battle map. While in a game,
-- global search pins an "On this map" group, scoped to what is on the CURRENT
-- map -- the deployed tokens (dmhub.allTokens is already current-map-only) and
-- the map notes (dmhub.infoBubbles, also current-map-only). Token rows carry
-- the live token so they render the creature's portrait and activate by
-- selecting + centring the camera; note rows render the bubble's numbered pin
-- and activate by opening the note in place (gamehud:DisplayDocument), exactly
-- as clicking the on-map marker does.
--
-- LOWEST priority (10) in the context stack: any focused full-screen artifact
-- that registers its own context -- the Compendium (~50), a modal PDF viewer
-- (~100) -- outranks the map, so "On this map" is the fallback context behind
-- everything. The map has no discrete open/close panel (it is the persistent
-- game background), so unlike the PDF/compendium providers this one stays
-- registered and enumerate self-gates on dmhub.inGame -- out of game it returns
-- nothing and the group never shows. Each result stamps a dedupKey so the
-- aggregator can keep the same item from ALSO appearing in the "In this
-- Campaign" bucket while it is pinned here (tokens by id; notes by title vs the
-- journal-document twin). When this context is suppressed (an artifact is open)
-- those items fall back to the bucket, so global reach is never lost.
Search.RegisterContextProvider{
    id = "map-view",
    priority = 10,
    label = "On this map",
    enumerate = function(needle)
        -- Director-only: token results lead to selection/placement and map
        -- notes are GM content, both director concerns. Gating the whole
        -- provider keeps "On this map" off the player's search entirely
        -- (consistent with the director-only "In this Campaign" token results).
        if (not dmhub.inGame) or (not dmhub.isDM) then
            return {}
        end
        local results = {}
        for _,token in ipairs(dmhub.allTokens) do
            local name = token.name
            if type(name) == "string" and name ~= "" and Search.MatchesText(name, needle) then
                local capturedId = token.id
                results[#results+1] = {
                    name = name,
                    score = Search.Score(name, needle),
                    typeLabel = MapTokenKindLabel(token),
                    token = token,
                    actionLabel = "Center on token",
                    dedupKey = "token:" .. capturedId,
                    activate = function()
                        dmhub.SelectToken(capturedId)
                        dmhub.CenterOnToken(capturedId)
                    end,
                }
            end

            -- Capability match: a placed MONSTER whose ability or trait matches.
            -- The director is probably about to USE it, so the row selects and
            -- centres the token (its abilities are then on the action bar). It
            -- carries the token portrait and the "Monster (on Map)" header, with
            -- the ability kind as the sub-label, mirroring the bestiary row. No
            -- dedupKey: unlike the name row we deliberately LEAVE the bestiary
            -- copy in the compendium bucket too, so the director can still place
            -- another of this monster from the same search.
            local props = token.properties
            local okMon, isMonster = pcall(function() return props ~= nil and props:IsMonster() end)
            if okMon and isMonster then
                local capturedId = token.id
                -- Name the SPECIFIC placed token (e.g. "Lumbering Egress (on Map)")
                -- rather than the generic kind, so the director knows exactly which
                -- token the row selects. Fall back to the kind label if unnamed.
                local tokenName = token.name
                local onMapLabel = (type(tokenName) == "string" and tokenName ~= "")
                    and string.format("%s (on Map)", tokenName)
                    or MapTokenKindLabel(token)
                for _,cap in ipairs(GetMonsterTokenCapabilities(token)) do
                    if Search.MatchesText(cap.name, needle) then
                        local capName = cap.name
                        local capCategorization = cap.categorization
                        results[#results+1] = {
                            name = cap.name,
                            score = Search.Score(cap.name, needle),
                            typeLabel = onMapLabel,
                            subLabel = cap.categorization,
                            token = token,
                            actionLabel = "Center on token",
                            activate = function()
                                dmhub.SelectToken(capturedId)
                                dmhub.CenterOnToken(capturedId)
                                -- An ABILITY also lands on the action bar once
                                -- the token is selected; point the director at
                                -- it (open its drawer + pulse the slot). Traits
                                -- are not abilities, so they never route here.
                                if capCategorization ~= "Trait" and Search.RevealActionBarAbility ~= nil then
                                    Search.RevealActionBarAbility(capturedId, capName)
                                end
                            end,
                        }
                    end
                end
            end
        end

        -- Map notes (info bubbles). The row icon is the bubble's own numbered
        -- pin (result.bubbleIcon); activation re-fetches the bubble by id (the
        -- HUD objects are transient) and opens it in place.
        for id,bubble in pairs(dmhub.infoBubbles or {}) do
            local title = MapNoteTitle(bubble)
            if type(title) == "string" and title ~= "" and Search.MatchesText(title, needle) then
                local capturedId = id
                local okIcon, icon = pcall(function() return bubble.icon end)
                results[#results+1] = {
                    name = title,
                    score = Search.Score(title, needle),
                    typeLabel = "Map Note",
                    bubbleIcon = (okIcon and type(icon) == "string") and icon or "",
                    actionLabel = "Open note",
                    dedupKey = "mapdoc:" .. string.lower(title),
                    activate = function()
                        local b = (dmhub.infoBubbles or {})[capturedId]
                        if b ~= nil and gamehud ~= nil then
                            gamehud:DisplayDocument(b)
                        end
                    end,
                }
            end
        end
        return results
    end,
}

-- Global-search provider: a monster's DISTINCTIVE abilities and its traits.
-- DM-only (bestiary is GM content). Lets a director find "Biokinetic Ballista"
-- or "Lethe" -> the monster(s) that have it, not just monster names. Only
-- Signature / Villain Action / Heroic abilities are indexed: these are
-- per-monster (verified live -- "Biokinetic Ballista"/"Kill Zone" each resolve
-- to a single monster). The generic shared actions (Basic Attack / Common
-- Ability / Move / Hidden) AND Malice are excluded -- Malice is a faction-wide
-- shared menu, so "Malicious Strike" alone hits 555 monsters; indexing it would
-- bury the distinctive abilities in noise. Traits (passive features) are
-- indexed in full -- a shared trait surfaces once per monster, bounded by the
-- result cap + "See all".
--
-- props:GetActivatedAbilities{} compiles GoblinScript per ability, so sweeping
-- all ~574 monsters is far too heavy to run on a keystroke. The index is built
-- ONCE in a background coroutine (yielding every few monsters so no frame
-- hitches) and cached; a long TTL lets it self-heal after monster edits without
-- needing an asset-monitor panel. While the first build is in flight the
-- provider returns nothing, so monster abilities appear a moment later (by then
-- the director is usually still typing the name); a stale index keeps serving
-- the previous results while a refresh builds, so there is no empty gap.
local MONSTER_ABILITY_CATEGORIES = {
    ["Signature Ability"] = true,
    ["Villain Action"] = true,
    ["Heroic Ability"] = true,
}
local MONSTER_ABILITY_INDEX_TTL = 300
local g_monsterAbilityIndex = nil
local g_monsterAbilityIndexTime = 0
local g_monsterAbilityIndexBuilding = false

-- Extract a monster's searchable capabilities from its creature properties: its
-- distinctive abilities (Signature / Villain Action / Heroic, deduped by name)
-- plus every named trait (passive feature, classed as "Trait"). Returns a flat
-- list of {name, categorization}. Shared by the global bestiary index build
-- below AND the per-token on-map matcher, so both classify a monster's
-- capabilities identically. GetActivatedAbilities compiles GoblinScript (heavy);
-- GetFeatures is cheap pre-loaded data. Each engine read is pcall-guarded: a
-- malformed entry must not abort the sweep.
local function ExtractMonsterCapabilities(props)
    local caps = {}
    if props == nil then
        return caps
    end
    pcall(function()
        local abils = props:GetActivatedAbilities{}
        if type(abils) == "table" then
            local seen = {}
            for _,a in ipairs(abils) do
                local okn, aname = pcall(function() return a.name end)
                local okc, cat = pcall(function() return a.categorization end)
                if okn and okc and type(aname) == "string" and aname ~= ""
                    and MONSTER_ABILITY_CATEGORIES[cat] and not seen[aname] then
                    seen[aname] = true
                    -- Capture the villain-action slot, implementation status, and
                    -- whether the ability carries real behaviors during this single
                    -- scan, so the villain-action picker can reuse the cached index
                    -- (slot-lock, status dot, behaviors cross-check) without a second
                    -- GoblinScript pass. Cheap field reads, individually guarded.
                    local slot, status, hasBehaviors = nil, nil, false
                    pcall(function() slot = a:try_get("villainAction") end)
                    pcall(function() status = a:try_get("implementation", 1) end)
                    pcall(function() hasBehaviors = #a:try_get("behaviors", {}) > 0 end)
                    caps[#caps+1] = {
                        name = aname,
                        categorization = cat,
                        villainAction = slot,
                        implementation = status,
                        hasBehaviors = hasBehaviors,
                    }
                end
            end
        end
    end)
    pcall(function()
        local feats = props:GetFeatures()
        if type(feats) == "table" then
            local seenTrait = {}
            for _,f in ipairs(feats) do
                local okn, fname = pcall(function() return f.name end)
                if okn and type(fname) == "string" and fname ~= ""
                    and not seenTrait[fname] then
                    seenTrait[fname] = true
                    caps[#caps+1] = { name = fname, categorization = "Trait" }
                end
            end
        end
    end)
    return caps
end

-- Per-token capability cache for the "On this map" matcher. Recomputing a placed
-- token's capabilities (GoblinScript-compiling GetActivatedAbilities) on every
-- keystroke would be too heavy, so each token's list is cached with a short TTL
-- and rebuilt lazily. Weak-keyed so removed tokens are collected. Assigns the
-- GetMonsterTokenCapabilities forward-declared above the map-view provider.
local MONSTER_TOKEN_CAP_TTL = 5
local g_tokenCapCache = setmetatable({}, { __mode = "k" })
GetMonsterTokenCapabilities = function(token)
    if token == nil or token.properties == nil then
        return {}
    end
    local now = dmhub.Time()
    local cached = g_tokenCapCache[token]
    if cached ~= nil and (now - cached.time) < MONSTER_TOKEN_CAP_TTL then
        return cached.caps
    end
    local caps = ExtractMonsterCapabilities(token.properties)
    g_tokenCapCache[token] = { time = now, caps = caps }
    return caps
end

local function MonsterAbilityIndexFresh()
    return g_monsterAbilityIndex ~= nil
        and (dmhub.Time() - g_monsterAbilityIndexTime) < MONSTER_ABILITY_INDEX_TTL
end

local function EnsureMonsterAbilityIndex()
    if g_monsterAbilityIndexBuilding or MonsterAbilityIndexFresh() then
        return
    end
    g_monsterAbilityIndexBuilding = true
    dmhub.Coroutine(function()
        local index = {}
        local n = 0
        for monsterid, monster in pairs(assets.monsters) do
            if not monster.hidden then
                local mname = monster.name
                local props = monster.properties
                if props ~= nil and type(mname) == "string" and mname ~= "" then
                    -- Monster level, read once per monster (cheap; the villain-action
                    -- picker surfaces it and searches by it).
                    local mlevel = nil
                    pcall(function() mlevel = tonumber(props:CharacterLevel()) end)
                    -- Abilities (deduped) + every named trait, classified once by
                    -- the shared extractor and tagged with the owning monster.
                    for _,cap in ipairs(ExtractMonsterCapabilities(props)) do
                        index[#index+1] = {
                            name = cap.name,
                            categorization = cap.categorization,
                            monsterName = mname,
                            monsterId = monsterid,
                            level = mlevel,
                            villainAction = cap.villainAction,
                            implementation = cap.implementation,
                            hasBehaviors = cap.hasBehaviors,
                        }
                    end
                end
            end
            n = n + 1
            if n % 20 == 0 then
                if mod.unloaded then
                    g_monsterAbilityIndexBuilding = false
                    return
                end
                coroutine.yield()
            end
        end
        g_monsterAbilityIndex = index
        g_monsterAbilityIndexTime = dmhub.Time()
        g_monsterAbilityIndexBuilding = false
    end)
end

Search.RegisterProvider{
    id = "monster-abilities",
    bucket = "compendium",
    enumerate = function(needle)
        if (not dmhub.isDM) or (not dmhub.inGame) then
            return {}
        end
        EnsureMonsterAbilityIndex()
        local index = g_monsterAbilityIndex
        if index == nil then
            return {}
        end
        local results = {}
        for _,e in ipairs(index) do
            if Search.MatchesText(e.name, needle) then
                local entry = e
                results[#results+1] = {
                    name = entry.name,
                    score = Search.Score(entry.name, needle),
                    -- Bestiary glyph (the monsters provider's icon) so a monster
                    -- ability reads as bestiary content; the monster it belongs
                    -- to is the right-hand chip, its kind the subhead.
                    icon = "icons/standard/Icon_App_Bestiary.png",
                    typeLabel = entry.monsterName,
                    subLabel = entry.categorization,
                    -- Searching an ability means "show me this ability", so the
                    -- primary (left-click) action opens the monster's sheet, where
                    -- the ability is read in full. Right-click offers the bestiary's
                    -- other affordance: placing the monster on the map.
                    activate = function()
                        EditBestiaryMonster(entry.monsterId, entry.name, entry.categorization)
                    end,
                    -- Ordered actions (primary first): View Ability opens the
                    -- monster's editor at this ability (mirrors the row press);
                    -- Place on Map is the secondary action.
                    actions = {
                        {
                            text = "View Ability",
                            click = function()
                                EditBestiaryMonster(entry.monsterId, entry.name, entry.categorization)
                            end,
                        },
                        {
                            text = "Place on Map",
                            click = function()
                                BeginPlacingMonster(entry.monsterId)
                            end,
                        },
                    },
                }
            end
        end
        return results
    end,
}

-- Villain-action picker support (Draw Steel). The picker reuses this cached
-- bestiary index rather than running its own GoblinScript scan: every villain
-- action across the bestiary is already classified here with its slot, level,
-- implementation status, and whether it carries real behaviors. Returns the
-- index entries matching a slot ("Villain Action 1|2|3"; nil = all slots) plus a
-- readiness flag, so a caller that opens before the build coroutine finishes can
-- re-poll instead of showing an empty list.
function GetBestiaryVillainActions(slot)
    EnsureMonsterAbilityIndex()
    local index = g_monsterAbilityIndex
    if index == nil then
        return {}, false
    end
    local out = {}
    for _,e in ipairs(index) do
        if e.categorization == "Villain Action"
            and (slot == nil or e.villainAction == slot) then
            out[#out+1] = e
        end
    end
    return out, true
end

-- Fetch the live ability object behind an index entry, for previewing the real
-- ability card or duplicating it onto another creature. Re-reads just the one
-- owning monster's abilities (cheap -- one monster, not the whole bestiary) and
-- matches by name. Returns nil if the monster or ability can no longer be found.
function GetBestiaryAbilityObject(monsterId, abilityName)
    local monster = assets.monsters[monsterId]
    if monster == nil or monster.properties == nil then
        return nil
    end
    local result = nil
    pcall(function()
        for _,a in ipairs(monster.properties:GetActivatedAbilities{}) do
            if a.name == abilityName then
                result = a
                return
            end
        end
    end)
    return result
end
