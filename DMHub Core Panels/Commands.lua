local mod = dmhub.GetModLoading()

Commands.Register{
    name = "Zoom In",
    menu = "tools",
    icon = "icons/icon_tool/icon_tool_40.png",
    group = "zoom",
    command = "zoomin",
}

Commands.Register{
    name = "Zoom Out",
    menu = "tools",
    icon = "icons/icon_tool/icon_tool_41.png",
    group = "zoom",
    command = "zoomout",
}

Commands.Register{
    name = "Undo",
    menu = "tools",
    icon = "panels/hud/anticlockwise-rotation.png",
    group = "undo",
    ord = 1,
    command = "undo",
    monitorEvent = "refreshUndo",
    geticon = function()
		if dmhub.undoState.undoPending then
		    return 'game-icons/cloud-upload.png'
		else
			return 'panels/hud/anticlockwise-rotation.png'
		end
    end,
    gettext = function()
        if dmhub.undoState.undoDescription == nil then
            return "Undo"
        end

        return string.format("Undo: %s", dmhub.undoState.undoDescription)
    end,
    disabled = function()
        return dmhub.undoState.undoDescription == nil
    end,
}

Commands.Register{
    name = "Redo",
    menu = "tools",
    icon = "panels/hud/clockwise-rotation.png",
    group = "undo",
    command = "redo",
    monitorEvent = "refreshUndo",
    geticon = function()
		if dmhub.undoState.redoPending then
		    return 'game-icons/cloud-upload.png'
		else
			return 'panels/hud/clockwise-rotation.png'
		end
    end,
    ord = 2,
    gettext = function()
        if dmhub.undoState.redoDescription == nil then
            return "Redo"
        end

        return string.format("Redo: %s", dmhub.undoState.redoDescription)
    end,
    disabled = function()
        return dmhub.undoState.redoDescription == nil
    end,
}

Commands.Register{
    name = "Show Grid",
    icon = "icons/icon_common/icon_common_51.png",
    setting = "showgrid",
    menu = "tools",
}

Commands.Register{
    name = "Snap Edits to Grid",
    menu = "tools",
    icon = mod.images.snapToGridIcon,
    setting = "editor:snaptogrid",
    dmonly = true,
    group = "gm",
}

Commands.Register{
    name = "Director Darkvision",
    menu = "tools",
    icon = "icons/icon_device/icon_device_57.png",
    group = "gm",
    setting = "dmillumination",
    dmonly = true,
}

Commands.Register{
    name = "Leave Game",
    icon = "panels/hud/exit-door.png",
    group = 'zzz',
    ord = 2,
    execute = function()
        if dmhub.tokensLoggedInAs ~= nil then
            dmhub.tokensLoggedInAs = nil
        else
            dmhub.LeaveGame()
        end
    end,
}

Commands.Register{
    name = "Quit to Desktop",
    icon = "game-icons/power-button.png",
    group = 'zzz',
    ord = 3,
    execute = function()
        dmhub.QuitApplication()
    end,
}

Commands.Register{
    name = "Settings",
    icon = "panels/hud/gear.png",
    group = 'zzz',
    execute = function()
        dmhub.ShowPlayerSettings()
    end,
}

--[[
Commands.Register{
	name = "Restore Initiative",
	command = "restoreinitiative",
	dmonly = true,
	icon = "panels/initiative/initiative-icon.png",
    disabled = function()
        if GameHud.instance ~= nil and GameHud.instance:has_key("initiativeInterface") then
            local info = GameHud.instance.initiativeInterface
            if info.initiativeQueue == nil or (not info.initiativeQueue.hidden) then
                return true
            end
        end
        return false
    end,
}
]]

Commands.Register{
	name = "Roll Initiative",
    identifier = "rollinitiative",
	command = "rollinitiative",
	dmonly = true,
	icon = "panels/initiative/initiative-icon.png",
}

Commands.RegisterMacro{
    name = "synccamera",
    summary = "sync player cameras",
    doc = "Syncs the camera to the current view for all players.",
    command = function()
        if not dmhub.isDM then
            return
        end
        dmhub.SyncCamera{
            speed = 1,
        }
        dmhub.Execute("ping")
    end,
}

Commands.RegisterMacro{
    name = "next",
    summary = "cycle between tokens",
    doc = "Cycles between controllable tokens. Prioritizes tokens whose turn it is in initiative.",
    command = function()

    local playerCharactersOffMap = {}

    if dmhub.isDM == false then
        local partyid = GetDefaultPartyID()
        if dmhub.currentToken ~= nil then
            partyid = dmhub.currentToken.partyId or partyid
        end

        playerCharactersOffMap = dmhub.GetCharacterIdsInParty(partyid)
        
    end


    local tokens = dmhub.GetTokens{
        playerControlled = dmhub.isDM == false,
    }

    --make sure playerCharactersOffMap only contains characters that are off the map.
    if #playerCharactersOffMap > 0 then
        for i,token in ipairs(tokens) do
            for j,c in ipairs(playerCharactersOffMap) do
                if c == token.charid then
                    table.remove(playerCharactersOffMap, j)
                    break
                end
            end
        end
    end

    local controllableTokens = {}
    for i,token in ipairs(tokens) do
        if token.canControl then
            controllableTokens[#controllableTokens + 1] = token
        end
    end

    tokens = controllableTokens

    --if there are tokens whose turn it is, cycle only between them.
    local initiativeTokens = {}

    for i,token in ipairs(tokens) do
        if token.initiativeStatus == "OurTurn" and token.canControl then
            initiativeTokens[#initiativeTokens + 1] = token
        end
    end

    if #initiativeTokens == 0 then
        for i,token in ipairs(tokens) do
            if token.initiativeStatus == "ActiveAndReady" and token.canControl then
                initiativeTokens[#initiativeTokens + 1] = token
            end
        end
    end

    if #initiativeTokens > 0 then
        tokens = initiativeTokens
    end

    local curToken = dmhub.currentToken
    local currentTokenId = nil

    if curToken ~= nil then
        currentTokenId = curToken.charid
    else
        local selectedTokens = dmhub.selectedOrPrimaryTokens
        if #selectedTokens > 0 then
            currentTokenId = selectedTokens[1].charid
        end
    end
    
    if tokens == nil then
        return
    end

    table.sort(tokens, function(a, b)
        local desca = creature.GetTokenDescription(a)
        local descb = creature.GetTokenDescription(b)
        if desca ~= descb then
            return desca < descb
        end
        return a.charid < b.charid
    end)

    local cycleToStart = false
    local targetIndex = nil
    for i,token in ipairs(tokens) do
        if token.charid == currentTokenId then
            targetIndex = i + 1
            if targetIndex > #tokens then
                targetIndex = 1
                cycleToStart = true
            end
            break
        end
    end

    local targetCharId = nil
    
    if #tokens > 0 then
        if targetIndex == nil then
            targetIndex = 1
        end
        targetCharId = tokens[targetIndex].charid
    end

    --we reset to the start of the list, so try to see if any off-map tokens match.
    if (cycleToStart or #tokens == 0) and #playerCharactersOffMap > 0 then
        local maps = {game.currentMapId}
        for i,charid in ipairs(playerCharactersOffMap) do
            local token = dmhub.GetCharacterById(charid)

            if token ~= nil and token.canControl then
                if token.mapid ~= nil then
                    maps[#maps + 1] = token.mapid
                end
            end
        end

        table.sort(maps)
        local currentIndex = nil
        for i,mapid in ipairs(maps) do
            if mapid == game.currentMapId then
                currentIndex = i
                break
            end
        end

        if currentIndex ~= nil and #maps > 1 then
            local nextIndex = currentIndex + 1
            if nextIndex > #maps then
                nextIndex = 1
            end

            local currentCharId = nil
            local nextMapId = maps[nextIndex]
            for i,charid in ipairs(playerCharactersOffMap) do
                local token = dmhub.GetCharacterById(charid)
                if token.mapid == nextMapId and (currentCharId == nil or token.charid < currentCharId) then
                    currentCharId = token.charid
                    break
                end
            end

            if currentCharId ~= nil then
                targetCharId = currentCharId
            end
        end
    end


    if targetCharId ~= nil then
        dmhub.CenterOnToken(targetCharId, function()
            dmhub.SelectToken(targetCharId)
        end)
    end

    end,
}

Commands.Register{
    name = "New Player Window",
    group = 'zzz',
    icon = mod.images.newWindow,
    dmonly = true,
    execute = function()
        dmhub.DuplicateWindowInNewProcess{ asplayer = true }
    end,
}

Commands.Register{
    name = "New Director Window",
    group = 'zzz',
    icon = mod.images.newWindow,
    dmonly = true,
    execute = function()
        dmhub.DuplicateWindowInNewProcess()
    end,
}

--Commands.Register{
--    name = "Shop...",
--    icon = "panels/hud/gear.png",
--    group = "shop",
--    execute = function()
--        GameHud.instance.mainDialogPanel:AddChild(CreateShopScreen{ titlescreen = GameHud.instance })
--    end,
--}