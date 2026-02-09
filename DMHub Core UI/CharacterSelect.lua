--- @class CharacterSelect:Panel
--- @field value table The list of tokenId's selected

--- @class CharacterSelectArgs:PanelArgs
--- @field allTokens table The list of all tokens to show
--- @field initialSelection table|nil The list of tokens to be selected initially
--- @field layout string|nil The layout style: "grid" or "list" (default list)
--- @field showShortcuts boolean|nil Whether to show the shortcut links below the panel
--- @field displayText function|nil The function to call to set the display text or nil to use token name
--- @field includeFollowers boolean|nil Whether to include followers in the list
--- @field followerFilter function|nil Used to filter followers if including them

--- Creates a character selector with token grid and selection shortcuts
--- @param args CharacterSelectArgs Configuration (allTokens, initialSelection, width, height, showShortcuts, change, classes, data)
--- @return CharacterSelect panel The character selector controller panel with GetValue/SetValue methods
local function _characterSelector(args)
    local opts = (args and shallow_copy_table(args)) or {}

    if not opts.allTokens or type(opts.allTokens) ~= "table" then
        error("CharacterSelector requires args.allTokens")
    end

    -- Store reference to token list and build ID lookup for SetValue validation
    local m_allTokens = opts.allTokens
    local m_validTokenIds = {}
    for _, token in ipairs(m_allTokens) do
        m_validTokenIds[token.id] = true
    end
    opts.allTokens = nil

    local fnChange = type(opts.change) == "function" and opts.change or nil
    opts.change = nil

    local fnDisplayText = type(opts.displayText) == "function" and opts.displayText or nil
    opts.displayText = nil

    local initialSelection = opts.initialSelection or {}
    opts.initialSelection = nil

    local layoutList = opts.layout == nil or opts.layout:lower() ~= "grid"
    opts.layout = nil
    local tokenSize = layoutList and 24 or 64

    local showShortcuts = opts.showShortcuts
    if showShortcuts == nil then showShortcuts = true end
    opts.showShortcuts = nil

    local gridHeight = opts.height or 130
    opts.height = nil

    local gridWidth = opts.width or "96%"
    opts.width = nil

    local additionalClasses = opts.classes or {}
    opts.classes = nil

    local additionalData = opts.data or {}
    opts.data = nil

    local includeFollowers = opts.includeFollowers or false
    opts.includeFollowers = nil

    local fnFollowerFilter = (includeFollowers and opts.followerFilter and type(opts.followerFilter) == "function") and opts.followerFilter
    opts.followerFilter = nil

    local fnFollowerText = (includeFollowers and opts.followerText and type(opts.followerText) == "function") and opts.followerText
    opts.followerText = nil

    local function sortTokensBySelection(tokens, selectedLookup)
        local sorted = {}
        table.move(tokens, 1, #tokens, 1, sorted)
        table.sort(sorted, function(a, b)
            local aSelected = selectedLookup[a.id] == true
            local bSelected = selectedLookup[b.id] == true
            if aSelected ~= bSelected then
                return aSelected  -- selected tokens come first
            end
            -- Both selected or both not selected - sort by name
            local aName = a.name or ""
            local bName = b.name or ""
            return aName < bName
        end)
        return sorted
    end

    local initiallySelected = {}
    if initialSelection then
        for tokenId, value in pairs(initialSelection) do
            if type(value) == "table" and value.selected then
                initiallySelected[tokenId] = true
            end
        end
    end

    local function buildTokenPanel(token, mentor)
        local isSelected = initiallySelected[token.id] == true
        local description = fnDisplayText and fnDisplayText(token, mentor) or (token.name or "Unknown")
        return gui.Panel{
            bgimage = "panels/square.png",
            classes = {"token-panel", isSelected and "selected" or nil},
            data = {
                token = mentor or token,
                follower = mentor and token or nil,
            },
            flow = layoutList and "horizontal" or nil,
            children = {
                gui.CreateTokenImage(token, {
                    width = tokenSize,
                    height = tokenSize,
                    halign = "center",
                    valign = "center",
                    lmargin = mentor and 32 or nil,
                    refresh = function(element)
                        if token == nil or not token.valid then return end
                        element:FireEventTree("token", token)
                    end,
                }),
                layoutList and gui.Label{
                    text = description,
                    classes = {"token-name-label"},
                    valign = "center",
                    hmargin = 8,
                } or nil,
            },
            linger = function(element)
                gui.Tooltip(description)(element)
            end,
            press = function(element)
                element:SetClass("selected", not element:HasClass("selected"))
                local controller = element:FindParentWithClass("characterSelectorController")
                if controller then
                    controller:FireEvent("updateSelection")
                end
            end,
        }
    end

    local function buildTokenPanels()

        local sortedTokens = sortTokensBySelection(m_allTokens, initiallySelected)

        local panels = {}
        for _, token in ipairs(sortedTokens) do
            panels[#panels + 1] = buildTokenPanel(token)

            if includeFollowers then
                local followers = token.properties:try_get("followers") or {}
                for followerId,_ in pairs(followers) do
                    local follower = dmhub.GetCharacterById(followerId)
                    if follower and (fnFollowerFilter == nil or fnFollowerFilter(follower)) then
                        panels[#panels+1] = buildTokenPanel(follower, token)
                    end
                end
            end

        end
        return panels
    end

    local function buildTokenGrid(tokenPanels)
        return gui.Panel {
            classes = {"tokenPool"},
            bgimage = 'panels/square.png',
            bgcolor = 'black',
            cornerRadius = 8,
            border = 2,
            borderColor = '#888888',
            width = "100%",
            height = gridHeight,
            pad = 4,
            vmargin = 8,
            styles = {
                {
                    classes = {'token-panel'},
                    bgcolor = 'black',
                    cornerRadius = 4,
                    width = layoutList and "100%" or 64,
                    height = layoutList and 26 or 64,
                    halign = 'left',
                },
                {
                    classes = {'token-name-label'},
                    color = 'white',
                    fontSize = 16,
                    valign = "center",
                    halign = "left",
                    width = "100%",
                    height = "100%",
                },
                {
                    classes = {'token-panel', 'hover'},
                    borderColor = 'grey',
                    borderWidth = 2,
                    bgcolor = '#441111',
                },
                {
                    classes = {'token-panel', 'selected'},
                    borderColor = 'white',
                    borderWidth = 2,
                    bgcolor = '#882222',
                },
                {
                    classes = { "follower-row" },
                    hmargin = 28,
                },
                {
                    classes = { "follower-label" },
                    fontSize = 14,
                    color = "#cccccc",
                }
            },
            children = {
                gui.Panel {
                    id = "tokenGrid",
                    width = "100%",
                    height = "96%",
                    valign = layoutList and "top" or "center",
                    halign = "center",
                    flow = layoutList and "vertical" or "horizontal",
                    vscroll = true,
                    wrap = not layoutList,
                    children = {tokenPanels}
                }
            }
        }
    end

    local function buildShortcutsPanel(tokenPanels)
        return gui.Panel{
            flow = 'horizontal',
            halign = 'center',
            width = 'auto',
            height = 'auto',
            styles = {
                {
                    classes = {'token-pool-shortcut'},
                    color = '#aaaaaa',
                    fontSize = 16,
                    width = 'auto',
                    height = 'auto',
                    valign = 'center',
                    halign = 'center',
                },
                {
                    classes = {'token-pool-shortcut', 'hover'},
                    color = 'white',
                },
                {
                    classes = {'shortcut-divider'},
                    bgimage = 'panels/square.png',
                    halign = 'center',
                    valign = 'center',
                    margin = 4,
                    width = 2,
                    height = 16,
                    bgcolor = '#aaaaaa',
                },
            },
            children = {
                gui.Label{
                    classes = {'token-pool-shortcut'},
                    text = 'All',
                    click = function(element)
                        for _, panel in ipairs(tokenPanels) do
                            panel:SetClass('selected', true)
                        end
                        local controller = element:FindParentWithClass("characterSelectorController")
                        if controller then controller:FireEvent("updateSelection") end
                    end,
                },
                gui.Panel{ classes = {'shortcut-divider'} },
                gui.Label{
                    classes = {'token-pool-shortcut'},
                    text = 'Party',
                    linger = function(element)
                        local tt = "Select all party members of\nall currently selected tokens"
                        gui.Tooltip(tt)(element)
                    end,
                    click = function(element)
                        -- Collect unique partyIds from currently selected tokens
                        local partyIds = {}
                        local hasSelectedTokens = false

                        for _, panel in ipairs(tokenPanels) do
                            if panel:HasClass("selected") then
                                hasSelectedTokens = true
                                local token = panel.data.token
                                if token and token.partyId ~= nil then
                                    partyIds[token.partyId] = true
                                end
                            end
                        end

                        -- Select all tokens with matching partyIds
                        if hasSelectedTokens and next(partyIds) ~= nil then
                            for _, panel in ipairs(tokenPanels) do
                                local token = panel.data.token
                                if token and token.partyId ~= nil and partyIds[token.partyId] then
                                    panel:SetClass('selected', true)
                                end
                            end
                        end

                        local controller = element:FindParentWithClass("characterSelectorController")
                        if controller then controller:FireEvent("updateSelection") end
                    end,
                },
                gui.Panel{ classes = {'shortcut-divider'} },
                includeFollowers and gui.Label {
                    classes = {'token-pool-shortcut'},
                    text = "Followers",
                    click = function(element)
                        for _, panel in ipairs(tokenPanels) do
                            if panel.data.follower then
                                panel:SetClass('selected', true)
                            end
                        end
                        local controller = element:FindParentWithClass("characterSelectorController")
                        if controller then controller:FireEvent("updateSelection") end
                    end,
                } or nil,
                includeFollowers and gui.Panel{ classes = {'shortcut-divider'} } or nil,
                gui.Label{
                    classes = {'token-pool-shortcut'},
                    text = 'None',
                    click = function(element)
                        for _, panel in ipairs(tokenPanels) do
                            panel:SetClass('selected', false)
                        end
                        local controller = element:FindParentWithClass("characterSelectorController")
                        if controller then controller:FireEvent("updateSelection") end
                    end,
                },
            }
        }
    end

    local tokenPanels = buildTokenPanels()
    local tokenGrid = buildTokenGrid(tokenPanels)

    local children = {tokenGrid}
    if showShortcuts then
        children[#children + 1] = buildShortcutsPanel(tokenPanels)
    end

    local controllerClasses = {"characterSelectorController"}
    table.move(additionalClasses, 1, #additionalClasses, #controllerClasses + 1, controllerClasses)

    local controllerData = {selectedTokenIds = {}}
    additionalData.selectedTokenIds = nil
    for k, v in pairs(additionalData) do
        controllerData[k] = v
    end

    local panelOpts = opts or {}
    panelOpts.classes = controllerClasses
    panelOpts.width = gridWidth
    panelOpts.height = "auto"
    panelOpts.flow = "vertical"
    panelOpts.data = controllerData

    panelOpts.create = function(element)
        -- Initial selection is applied during panel creation
        -- Store directly in keyed format
        if initialSelection and next(initialSelection) then
            element.data.selectedTokenIds = initialSelection
        end
    end

    panelOpts.GetValue = function(element)
        -- Return keyed table where key=tokenID, value={selected=true}
        return element.data.selectedTokenIds
    end

    panelOpts.SetValue = function(element, v)
        element.data.selectedTokenIds = v or {}
        element:FireEventTree("repaintSelection", element.data.selectedTokenIds)
    end

    panelOpts.updateSelection = function(element)
        local newSelection = {}
        local tokenGrid = element:Get("tokenGrid")
        if tokenGrid then
            for _, panel in ipairs(tokenGrid.children) do
                if panel:HasClass('selected') then
                    local tokenId = panel.data.token.id

                    if panel.data.follower then
                        local followerId = panel.data.follower.id
                        if not newSelection[tokenId] then
                            newSelection[tokenId] = {selected = false}
                        end
                        if not newSelection[tokenId].followers then
                            newSelection[tokenId].followers = {}
                        end
                        newSelection[tokenId].followers[followerId] = true
                    else
                        if not newSelection[tokenId] then
                            newSelection[tokenId] = {selected = true}
                        else
                            newSelection[tokenId].selected = true
                        end
                    end
                end
            end
        end

        element.data.selectedTokenIds = newSelection
        element:FireEvent("change", newSelection)
    end

    panelOpts.change = function(element, selectedTokenIds)
        if fnChange then
            fnChange(element, selectedTokenIds)
        end
    end

    panelOpts.repaintSelection = function(element, selectedItems)
        local tokenGrid = element:Get("tokenGrid")
        if tokenGrid then
            for _, panel in ipairs(tokenGrid.children) do
                local isSelected = selectedItems[panel.data.token.id] ~= nil
                panel:SetClass("selected", isSelected)
            end
        end

        element:FireEvent("change", selectedItems)
    end

    panelOpts.children = children

    return gui.Panel(panelOpts)
end

if gui.CharacterSelect == nil then
    gui.CharacterSelect = _characterSelector
end
