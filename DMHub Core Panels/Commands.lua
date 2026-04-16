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
    name = "toggleparallax",
    summary = "Toggle Disable Parallax",
    doc = "Toggles the disable parallax state.",
    command = function()
        dmhub.SetSettingValue("disableparallax", not dmhub.GetSettingValue("disableparallax"))
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

------------------------------------------------------------------------
-- Documentation and completions for built-in (C#) engine commands.
-- These are registered via [GameCommand] in CommandController.cs.
-- RegisterBuiltinDoc populates Commands._macros so the ChatPanel UI
-- shows summary, doc, and argument completions without overriding
-- the C# execution path.
------------------------------------------------------------------------

local function settingIdCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {}
    for id, info in pairs(Settings) do
        result[#result+1] = {text = id, summary = info.description or id}
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    return result
end

local function allCommandCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {}
    local seen = {}
    local macros = Commands.GetAllMacros()
    for name, info in pairs(macros) do
        if not seen[name] then
            seen[name] = true
            result[#result+1] = {text = name, summary = info.summary or name}
        end
    end
    for name, fn in pairs(Commands) do
        if type(fn) == "function" and not seen[name] then
            seen[name] = true
            result[#result+1] = name
        end
    end
    table.sort(result, function(a, b)
        local ta = type(a) == "table" and a.text or a
        local tb = type(b) == "table" and b.text or b
        return ta < tb
    end)
    return result
end

-- toggle: Toggle a boolean setting by its ID.
Commands.RegisterBuiltinDoc{
    name = "toggle",
    summary = "toggle a setting",
    doc = "Usage: /toggle <setting id>\nToggles a boolean setting on or off. Use /settingid to find a setting's id by name.",
    completions = settingIdCompletions,
}

-- reset: Reset a setting to its default value.
Commands.RegisterBuiltinDoc{
    name = "reset",
    summary = "reset a setting",
    doc = "Usage: /reset <setting id>\nResets the given setting to its default value.",
    completions = settingIdCompletions,
}

-- broadcastdefaultsetting: (Admin only) set a default setting value.
Commands.RegisterBuiltinDoc{
    name = "broadcastdefaultsetting",
    summary = "set default setting (admin)",
    doc = "Usage: /broadcastdefaultsetting <setting id> <value>\n(Admin only) Sets the default value for a setting across all clients.",
    completions = settingIdCompletions,
}

-- help: Show help for a command or list all commands.
Commands.RegisterBuiltinDoc{
    name = "help",
    summary = "show command help",
    doc = "Usage: /help [command]\nShows help for a specific command, or lists all available commands if no argument is given.",
    completions = allCommandCompletions,
}

-- helpall: List all available commands.
Commands.RegisterBuiltinDoc{
    name = "helpall",
    summary = "list all commands",
    doc = "Usage: /helpall\nLists all available built-in commands.",
}

-- bind: Bind a keystroke to a command.
Commands.RegisterBuiltinDoc{
    name = "bind",
    summary = "bind a key to a command",
    doc = "Usage: /bind <key> <command>\nBinds a keystroke to a command. The binding is saved across sessions.\nExample: /bind f5 synccamera",
    completions = function(args, argIndex)
        if argIndex == 2 then
            return allCommandCompletions(args, 1)
        end
        return {}
    end,
}

-- bindnosave: Bind a keystroke to a command without saving.
Commands.RegisterBuiltinDoc{
    name = "bindnosave",
    summary = "bind a key (no save)",
    doc = "Usage: /bindnosave <key> <command>\nBinds a keystroke to a command without persisting the binding.",
    completions = function(args, argIndex)
        if argIndex == 2 then
            return allCommandCompletions(args, 1)
        end
        return {}
    end,
}

-- unbind: Unbind a keystroke.
Commands.RegisterBuiltinDoc{
    name = "unbind",
    summary = "unbind a key",
    doc = "Usage: /unbind <key>\nRemoves a key binding. The change is saved.",
}

-- unbindnosave: Unbind a keystroke without saving.
Commands.RegisterBuiltinDoc{
    name = "unbindnosave",
    summary = "unbind a key (no save)",
    doc = "Usage: /unbindnosave <key>\nRemoves a key binding without persisting the change.",
}

-- showbinds: List current keybindings.
Commands.RegisterBuiltinDoc{
    name = "showbinds",
    summary = "list keybindings",
    doc = "Usage: /showbinds\nPrints all current keybindings to the console.",
}

-- resetbinds: Reset keybindings to defaults.
Commands.RegisterBuiltinDoc{
    name = "resetbinds",
    summary = "reset keybindings",
    doc = "Usage: /resetbinds\nResets all keybindings to their default values. The change is saved.",
}

-- center: Center camera on the current token.
Commands.RegisterBuiltinDoc{
    name = "center",
    summary = "center on current token",
    doc = "Usage: /center [smooth]\nCenters the camera on your current token. Pass 'smooth' for a smooth transition.",
    completions = function(args, argIndex)
        if argIndex == 1 then
            return {{text = "smooth", summary = "smooth transition"}}
        end
        return {}
    end,
}

-- ping: Ping the location under the mouse.
Commands.RegisterBuiltinDoc{
    name = "ping",
    summary = "ping mouse location",
    doc = "Usage: /ping\nPings the current location under the mouse cursor, visible to all players.",
}

-- rotate: Rotate the current token.
Commands.RegisterBuiltinDoc{
    name = "rotate",
    summary = "rotate current token",
    doc = "Usage: /rotate [degrees]\nRotates your current token by the given number of degrees. With no argument, resets rotation to 0.",
}

-- delay: Delay command execution.
Commands.RegisterBuiltinDoc{
    name = "delay",
    summary = "delay execution",
    doc = "Usage: /delay <seconds>\nDelays command execution by the given number of seconds.",
}

-- console: Toggle the debug console.
Commands.RegisterBuiltinDoc{
    name = "console",
    summary = "toggle debug console",
    doc = "Usage: /console\nShows or hides the debug console.",
}

-- togglevisibility: Toggle visibility of selected objects/tokens.
Commands.RegisterBuiltinDoc{
    name = "togglevisibility",
    summary = "toggle selected visibility",
    doc = "Usage: /togglevisibility\n(DM only) Toggles visibility of all selected objects and tokens.",
}

-- cut/copy/paste: Clipboard operations.
Commands.RegisterBuiltinDoc{
    name = "cut",
    summary = "cut to clipboard",
    doc = "Usage: /cut\nCuts the current selection to the clipboard.",
}

Commands.RegisterBuiltinDoc{
    name = "copy",
    summary = "copy to clipboard",
    doc = "Usage: /copy\nCopies the current selection to the clipboard.",
}

Commands.RegisterBuiltinDoc{
    name = "paste",
    summary = "paste from clipboard",
    doc = "Usage: /paste\nPastes from the clipboard.",
}

-- objectstotop/objectstobottom: Z-order operations.
Commands.RegisterBuiltinDoc{
    name = "objectstotop",
    summary = "move objects to top",
    doc = "Usage: /objectstotop\nMoves all selected map objects to the top, above other objects.",
}

Commands.RegisterBuiltinDoc{
    name = "objectstobottom",
    summary = "move objects to bottom",
    doc = "Usage: /objectstobottom\nMoves all selected map objects to the bottom, below other objects.",
}

-- resetobj: Reset placed object preview.
Commands.RegisterBuiltinDoc{
    name = "resetobj",
    summary = "reset object placement",
    doc = "Usage: /resetobj\nResets the state of the object currently being placed.",
}

-- randrot: Randomize rotation of object being placed.
Commands.RegisterBuiltinDoc{
    name = "randrot",
    summary = "randomize object rotation",
    doc = "Usage: /randrot\nRandomizes the rotation of the object currently being placed.",
}

-- randscale: Randomize scale of object being placed.
Commands.RegisterBuiltinDoc{
    name = "randscale",
    summary = "randomize object scale",
    doc = "Usage: /randscale [scale]\nRandomizes the scale of the object currently being placed. Optionally set a specific scale value.",
}

-- rotateobject: Rotate the object being placed.
Commands.RegisterBuiltinDoc{
    name = "rotateobject",
    summary = "rotate placed object",
    doc = "Usage: /rotateobject <degrees>\nRotates the object currently being placed by the given number of degrees.",
}

-- lua: Execute arbitrary Lua code.
Commands.RegisterBuiltinDoc{
    name = "lua",
    summary = "execute Lua code",
    doc = "Usage: /lua <code>\nExecutes the given Lua code in the console environment.",
}

-- eval: Evaluate a dice expression.
Commands.RegisterBuiltinDoc{
    name = "eval",
    summary = "evaluate dice expression",
    doc = "Usage: /eval <expression>\nEvaluates a dice or GoblinScript expression and prints the result.",
}

-- normalizeroll: Normalize a dice expression.
Commands.RegisterBuiltinDoc{
    name = "normalizeroll",
    summary = "normalize dice expression",
    doc = "Usage: /normalizeroll <expression>\nNormalizes a dice roll expression and prints the canonical form.",
}

-- getpos: Print current camera position.
Commands.RegisterBuiltinDoc{
    name = "getpos",
    summary = "print camera position",
    doc = "Usage: /getpos\nPrints the current camera position (x, y) and zoom level.",
}

-- lockpos: Lock camera to a position.
Commands.RegisterBuiltinDoc{
    name = "lockpos",
    summary = "lock camera position",
    doc = "Usage: /lockpos <x> <y> <zoom>\nLocks the camera to the given position and zoom level.",
}