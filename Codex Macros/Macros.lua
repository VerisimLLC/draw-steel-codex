local mod = dmhub.GetModLoading()

--- @param str string The criteria to search by.
--- @return CharacterToken[] The list of tokens that match the criteria.
local tokenSearch = function(str, tokens)
    tokens = tokens or dmhub.allTokens

    str = string.lower(str)

    if str == "all" then
        return tokens
    elseif str == "heroes" then
        local matchingTokens = {}

        for _, token in ipairs(tokens) do
            if token.properties:IsHero() then
                matchingTokens[#matchingTokens + 1] = token
            end
        end

        return matchingTokens
    elseif str == "monsters" then
        local matchingTokens = {}

        for _, token in ipairs(tokens) do
            if token.properties:IsMonster() then
                matchingTokens[#matchingTokens + 1] = token
            end
        end

        return matchingTokens
    else
        local matchingTokens = {}

        for _, token in ipairs(tokens) do
            if string.lower(token.name or "") == str then
                matchingTokens[#matchingTokens + 1] = token
            end
        end

        return matchingTokens
    end
end

Commands.SplitArgs = function(str)
    local result = {}

    if string.find(str, "(", 1, true) then
        local currentStr = {}
        local stack = {}
        --handle nested parentheses
        local len = #str
        local i = 1
        while i <= len do
            local char = string.sub(str, i, i)
            if char == "(" or char == '"' then
                if #currentStr > 0 then
                    result[#result + 1] = trim(table.concat(currentStr, ""))
                    currentStr = {}
                end

                stack[#stack + 1] = cond(char == "(", ")", char)
                --find matching )
                local j = i + 1
                while j <= #str do
                    local c = string.sub(str, j, j)
                    if (c == "(" or c == '"') and c ~= stack[#stack] then
                        stack[#stack + 1] = cond(c == "(", ")", c)
                    elseif c == stack[#stack] then
                        stack[#stack] = nil
                        if #stack == 0 then
                            break
                        end
                    end
                    j = j + 1
                end

                if #stack == 0 then
                    --found matching )
                    local arg = string.sub(str, i + 1, j - 1)
                    result[#result + 1] = arg
                    i = j+1
                else
                    local arg = string.sub(str, i + 1, j)
                    result[#result + 1] = arg
                    break
                end
            elseif char == " " then
                if #currentStr > 0 then
                    result[#result + 1] = trim(table.concat(currentStr, ""))
                    currentStr = {}
                end
                i = i+1
            else
                currentStr[#currentStr + 1] = char
                i = i+1
            end
        end

        if #currentStr > 0 then
            result[#result + 1] = trim(table.concat(currentStr, ""))
        end
        return result
    end

    while str ~= nil and str ~= "" do
        local match = regex.MatchGroups(str, "^\\s*((?<arg>[^\" ]+)|\"(?<arg>[^\"]+)\")(?<suffix>.*)$")
        if match == nil then
            break
        end

        result[#result + 1] = match.arg
        str = match.suffix
    end

    return result
end

print("SPLIT::", Commands.SplitArgs("(numheroes + 4) * 3"))

Commands.applyongoingeffect = function(str)
    if str == "help" then
        dmhub.Log("Usage: /applyongoingeffect <effect name>\n Applies given ongoing effect.")
        return
    end

    str = string.lower(str)
    local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
    local effectid = nil
    for k, v in unhidden_pairs(characterOngoingEffects) do
        if string.lower(v.name) == str then
            effectid = k
            break
        end
    end

    if effectid == nil then
        print("No ongoing effect found with name:", str)
        return
    end

    for _, token in ipairs(dmhub.allTokens) do
        token:ModifyProperties {
            description = "Apply Ongoing Effect",
            combine = true,
            execute = function()
                token.properties:ApplyOngoingEffect(effectid, "eoe")
            end,
        }
    end
end

Commands.removeongoingeffect = function(str)
    if str == "help" then
        dmhub.Log("Usage: /removeongoingeffect <effect name>\n Removes given ongoing effect.")
        return
    end

    str = string.lower(str)
    local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
    local effectid = nil
    for k, v in unhidden_pairs(characterOngoingEffects) do
        if string.lower(v.name) == str then
            effectid = k
            break
        end
    end

    if effectid == nil then
        print("No ongoing effect found with name:", str)
        return
    end

    for _, token in ipairs(dmhub.allTokens) do
        token:ModifyProperties {
            description = "Apply Ongoing Effect",
            combine = true,
            execute = function()
                token.properties:RemoveOngoingEffect(effectid)
            end,
        }
    end
end

Commands.collapsefloor = function(str)
    if str == "help" then
        dmhub.Log("Usage: /uncollapsefloor <floor name>\n Collapses given floor.")
        return
    end

    print("SEARCH:: FLOOR", str)
    for _, floor in ipairs(game.currentMap.floors) do
        local obj = floor:GetObject(str)
        if obj ~= nil then
            local map = obj:GetComponent("Map")
            local fields = map.fields
            for i, f in ipairs(fields) do
                if f.id == "scaling" then
                    f:SetValue(0, 1)
                    f:Upload()

                    game.Refresh()

                    dmhub.Schedule(0.2, function()
                        for _, tok in ipairs(dmhub.allTokens) do
                            print("SEARCH:: DROP", tok.name)
                            tok:TryFall()
                        end
                    end)


                    return
                end
            end
        end
    end
end

Commands.uncollapsefloor = function(str)
    if str == "help" then
        dmhub.Log("Usage: /uncollapsefloor <floor name>\n Uncollapses given floor.")
        return
    end

    print("SEARCH:: FLOOR", str)
    for _, floor in ipairs(game.currentMap.floors) do
        local obj = floor:GetObject(str)
        if obj ~= nil then
            local map = obj:GetComponent("Map")
            local fields = map.fields
            for i, f in ipairs(fields) do
                if f.id == "scaling" then
                    f:SetValue(1, 1)
                    f:Upload()

                    game.Refresh()

                    return
                end
            end
        end
    end
end

--award victory points to any heroes on the map.
Commands.awardvp = function(str)
    if str == "help" then
        dmhub.Log("Usage: /awardvp <number>\n Awards victory points to any heroes on the map (given number or 1).")
        return
    end

    if not dmhub.isDM then
        return
    end

    local points = tonumber(str) or 1
    for _, token in ipairs(dmhub.allTokens) do
        if token.properties:IsHero() then
            token:ModifyProperties {
                description = "Award Victories",
                execute = function()
                    token.properties:SetVictories(token.properties:GetVictories() + points)
                end,
            }
        end
    end
end

--take a respite to any heroes on the map.
Commands.dorespite = function(args)
    if args == "help" then
        dmhub.Log("Usage: /dorespite\n Grants a respite to all heroes on the map.")
        return
    end
    if not dmhub.isDM then return end

    for _, t in ipairs(dmhub.allTokens) do
        if t.properties:IsHero() then
            t:ModifyProperties {
                description = "Take a Respite",
                execute = function()
                    t.properties:Rest("long")
                end
            }
        end
    end
end

Commands.showallmaps = function(str)
    for _, map in ipairs(game.maps) do
        print("MAP:", map.id, map.description)
    end
end

--set heroes on this map to a specific 'tutorial' level.
Commands.slowstartlevel = function(str)
    if str == "help" then
        dmhub.Log("Usage: /slowstartlevel <level number> \n Sets heroes on current map to a specific 'tutorial' level.")
        return
    end


    if not dmhub.isDM then
        return
    end
    for _, token in ipairs(dmhub.allTokens) do
        if token.properties:IsHero() then
            token:ModifyProperties {
                description = "Set Slow Start Level",
                execute = function()
                    token.properties.levelOverride = 1
                    local info = token.properties:ExtraLevelInfo()
                    info.encounter = tonumber(str) or 1
                    if info.encounter > 4 then
                        info.encounter = nil
                    end
                    token.properties.extraLevelInfo = info
                end,
            }
        end
    end
end

Commands.objectcommand = function(str)
    local args = string.split(str, " ")
    if (not args[1]) or (not args[2]) then
        return
    end

    local search = args[1]

    local componentid = nil

    if string.find(search, ".", 1, true) then
        local parts = string.split(search, ".")

        search = parts[1]
        componentid = string.lower(parts[2])
    end

    local command = string.lower(args[2])
    local objects = game.currentFloor.objects

    for key, obj in pairs(objects) do
        local keywords = obj.keywords
        if keywords and keywords[search] then
            for key, component in pairs(obj.components) do
                local match = true
                if componentid ~= nil then
                    local name = string.lower(component.name)
                    name = string.gsub(name, " ", "")
                    if name ~= componentid then
                        match = false
                    end
                end

                if match then
                    local commands = component.commands
                    for _, cmd in ipairs(commands) do
                        local s = string.lower(cmd)
                        s = string.gsub(s, " ", "")
                        if s == command then
                            print("COMMAND:: EXECUTE")
                            component:Execute(cmd)
                        end
                    end
                end
            end
        end
    end
end

Commands.activateobjects = function(str)
    local args = string.split(str, " ")
    if not args[1] then
        return
    end

    local search = args[1]

    local componentid = nil

    if string.find(search, ".", 1, true) then
        local parts = string.split(search, ".")

        search = parts[1]
        componentid = string.lower(parts[2])
    end


    local mode = args[2] or "activate"
    local objects = game.currentFloor.objects
    for key, obj in pairs(objects) do
        local keywords = obj.keywords
        if keywords and keywords[search] then
            if componentid ~= nil then
                --search for component.
                for key, component in pairs(obj.components) do
                    local name = string.lower(component.name)
                    name = string.gsub(name, " ", "")
                    if name == componentid then
                        local newValue = cond(mode == "toggle", not component.disabled,
                            cond(mode == "deactivate", true, false))
                        component.disabled = newValue
                    end
                end
            else
                local newValue = cond(mode == "toggle", not obj.inactive, cond(mode == "deactivate", true, false))
                --toggle the entire object.
                if newValue ~= obj.inactive then
                    obj.inactive = newValue
                    obj:Upload()
                end
            end

            print("OBJECT", key, obj, "keywords", obj.keywords)
        end
    end
end

Commands.openurl = function(str)
    if not str or str == "" then
        print("USAGE: /openurl <url>")
        return
    end

    dmhub.OpenURL(str)
end



Commands.screenshake = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /screenshake <duration> <strength> <vibrato> <randomness>\nShakes the screen, runs on the local computer only. Use broadcast to send to other players.")
        return
    end

    local args = Commands.SplitArgs(str)
    dmhub.ScreenShake(tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]))
end

Commands.broadcast = function(str)
    str = string.join(Commands.SplitArgs(str), " ")
    dmhub.Execute(str)
    dmhub.Broadcast("map", str)
end

Commands.floor = function(str)
    if str == "help" then
        dmhub.Log("Usage: /floor <floor name> \n Changes active floor to the given floor.")
        return
    end

    local floors = game.currentMap.floors

    local floor

    for i = 1, #floors do
        if floors[i].description == str then
            floor = floors[i]
        end
    end

    if floor ~= nil then
        game.ChangeMap(game.currentMap, floor)
    end
end




Commands.deletemonsters = function(str)
    if str == "help" then
        dmhub.Log("Usage: /deletemonsters \n Deletes all monsters from current floor.")
        return
    end

    local playertokens = game.currentFloor.playerCharactersOnFloor
    local chartokens = game.currentFloor.charactersOnFloor

    local tobedeleted = {}

    for i, allchar in ipairs(chartokens) do
        local isplayer = false

        for j, player in ipairs(playertokens) do
            if allchar.charid == player.charid then
                isplayer = true
            end
        end

        if not isplayer then
            tobedeleted[#tobedeleted + 1] = allchar.charid
        end
    end

    game.DeleteCharacters(tobedeleted)
end

Commands.elevation = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /elevation <x1> <y1> <x2> <y2> <height>\n Changes elevation in a rectangular area according to the parameters.")
        return
    end

    local args = Commands.SplitArgs(str)

    local x1 = tonumber(args[1])
    local y1 = tonumber(args[2])
    local x2 = tonumber(args[3])
    local y2 = tonumber(args[4])
    local height = tonumber(args[5])

    game.currentFloor:ChangeElevation {
        type = "rectangle",
        p1 = { x = x1, y = y1 },
        p2 = { x = x2, y = y2 },
        opacity = 1,
        height = height,
        add = true,
        recalculateTokenElevation = true,
    }
end

Commands.elevationcircle = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /elevationcircle <x> <y> <radius> <height>\n Changes elevation in a circular area according to the parameters.")
        return
    end

    local args = Commands.SplitArgs(str)

    local x1 = tonumber(args[1])
    local y1 = tonumber(args[2])
    local radius = tonumber(args[3])
    local height = tonumber(args[4])

    game.currentFloor:ChangeElevation {
        type = "ellipse",
        center = { x = x1, y = y1 },
        radius = radius,
        opacity = 1,
        height = height,
        add = true,
        recalculateTokenElevation = true,
    }
end

Commands.move = function(str)
    if str == "help" then
        dmhub.Log("Usage: /move <token name> <x> <y>\n Moves token(s) to given location.")
        return
    end

    local args = Commands.SplitArgs(str)
    local x = tonumber(args[2])
    local y = tonumber(args[3])

    local matchedTokens = tokenSearch(args[1])

    print("MOVE:: TRYING...")
    for _, token in ipairs(matchedTokens) do
        print("MOVE:: CALLING MOVE...")
        token:Move(core.Loc { x = x, y = y, floorIndex = token.floorIndex }:WithGroundLevelAltitude(), { maxCost = 5000, findVacantSpace = true })
    end
end

Commands.hidetoken = function(str)
    if str == "help" then
        dmhub.Log("Usage: /hidetoken <token name>\n Makes given token(s) hidden.")
        return
    end

    local allTokens = dmhub.allTokens

    for _, token in ipairs(allTokens) do
        if token.name == str then
            token.invisibleToPlayers = true
        end
    end
end


Commands.showtoken = function(str)
    if str == "help" then
        dmhub.Log("Usage: /showtoken <token name>\n Makes given token(s) unhidden.")
        return
    end

    local allTokens = dmhub.allTokens

    for _, token in ipairs(allTokens) do
        if token.name == str then
            token.invisibleToPlayers = false
        end
    end
end

Commands.emote = function(str)
    if str == "help" then
        dmhub.Log("Usage: /emote <token name> <emote name>\n Sets emote active on given token(s).")
        return
    end

    local args = Commands.SplitArgs(str)
    local tokens = args[1]
    local emote = args[2]

    if #args < 2 then
        for i, tok in ipairs(dmhub.selectedOrPrimaryTokens) do
            if tok.properties ~= nil then
                tok.properties:Emote(emote, { deleteOthers = true })
            end
        end
    else
        local allTokens = tokenSearch(tokens)
        for _, token in ipairs(allTokens) do
            if token.properties ~= nil then
                token.properties:Emote(emote, { deleteOthers = true })
            end
        end
    end
end

Commands.wall = function(str)
    if str == "help" then
        dmhub.Log("Usage: /wall <x1> <y1> <x2> <y2>\n Draws a wall between two points.")
        return
    end

    local floor = game.currentFloor

    local args = Commands.SplitArgs(str)
    local point1 = tonum(args[1])
    local point2 = tonum(args[2])
    local point3 = tonum(args[3])
    local point4 = tonum(args[4])

    floor:ExecutePolygonOperation {
        points = { { point1, point2, point3, point4 } },
        wallid = "-MGADhKw0vw30yXNF2-e",
    }
end


Commands.erasewall = function(str)
    if str == "help" then
        dmhub.Log("Usage: /erasewall <x1> <y1> <x2> <y2> <x3> <y3> <x4> <y4>\n Erases walls in the given area.")
        return
    end

    local floor = game.currentFloor

    local args = Commands.SplitArgs(str)
    local point1 = tonum(args[1])
    local point2 = tonum(args[2])
    local point3 = tonum(args[3])
    local point4 = tonum(args[4])
    local point5 = tonum(args[5])
    local point6 = tonum(args[6])
    local point7 = tonum(args[7])
    local point8 = tonum(args[8])


    floor:ExecutePolygonOperation {
        points = { { point1, point2, point3, point4, point5, point6, point7, point8 } },
        walls = true,
        erase = true,
        closed = true
    }
end

Commands.spawn = function(str)
    if str == "help" then
        dmhub.Log("Usage: /spawn <token name> <x> <y> \n Spawns any character(s) to given location.")
        return
    end

    local args = Commands.SplitArgs(str)
    local tokenName = args[1]
    local x = tonum(args[2])
    local y = tonum(args[3])

    local characters = game.GetGameGlobalCharacters()

    local tokens = tokenSearch(tokenName, table.values(characters))

    for _, token in pairs(tokens) do
        token:ChangeLocation(core.Loc { x = x, y = y })
    end
end

Commands.relocate = function(str)
    if str == "help" then
        dmhub.Log("Usage: /relocate x1 y1 x2 y2 \n Relocates all tokens from (x1, y1) to (x2, y2).")
    end

    local args = Commands.SplitArgs(str)
    local x1 = tonum(args[1])
    local y1 = tonum(args[2])
    local x2 = tonum(args[3])
    local y2 = tonum(args[4])

    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then
        dmhub.Log("You must provide four numbers: x1 y1 x2 y2")
        return
    end

    for _, token in ipairs(dmhub.allTokens) do
        local locs = token.locsOccupying
        for i,loc in ipairs(locs) do
            if loc.x == x1 and loc.y == y1 then
                token:ChangeLocation(core.Loc { x = x2, y = y2, floorIndex = loc.floorIndex }:WithGroundLevelAltitude())
            end
        end
    end
end

--[[local GetDayTypeKey = function(floorid)
	if game.FloorIsAboveGround(floorid) then
		return 'daynight'
	else
		return 'underground'
	end
end]]

Commands.timeofday = function(str)
    if str == "help" then
        dmhub.Log("Usage: /timeofday <number> \n Changes time of day to the given time (between 0-9).")
        return
    end

    if str == nil then
        str = "0"
    end

    local number = tonumber(str)

    if not number then
        print("You have to give a number to change the time of day")
        return
    end

    number = number / 10

    local time = dmhub.GetSettingValue("gametime")

    dmhub.SetSettingValue("gametime", number)

    dmhub.SetSettingValue("gametimebasis", dmhub.serverTime)
end

Commands.undergroundlight = function(str)
    if str == "help" then
        dmhub.Log("Usage: /undergroundlight <number> \n Changes underground illumination (between 0-10).")
        return
    end

    if str == nil then
        str = "0"
    end

    local number = tonumber(str)

    if not number then
        print("You have to give a number to change the time of day")
        return
    end

    number = number / 10

    dmhub.SetSettingValue("undergroundillumination", number)
end

Commands.audio = function(str)
    local args = Commands.SplitArgs(str)
    local audioID = args[1]
    local volume = tonumber(args[2])

    local audioAsset = assets.audioTable[audioID]

    audio.PlaySoundEvent {
        asset = audioAsset,
        volume = volume or 50,
    }
end

Commands.speak = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /speak <token name> <whatever you want the token to say> <language ID (optional - defaults to Caelian)>\n Makes a character speak with a speech bubble. NOTE: wrap the speech in doublequotes.")
        return
    end

    local args = Commands.SplitArgs(str)
    local tokenName = args[1]
    local speech = args[2]
    local language = args[3]

    if language == nil then
        language = "c3c75399-6654-4ef6-a5f7-10653560f84"
    end

    local allTokens = dmhub.allTokens

    local tokens = tokenSearch(tokenName, allTokens)

    for _, token in pairs(tokens) do
        token:ModifyProperties {
            description = "Speech",
            undoable = false,
            execute = function()
                token.properties:CharacterSpeech {
                    text = speech,
                    langid = language,
                }
            end,
        }
    end
end

Commands.giveitem = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /giveitem <token name> <item ID> <quantity>\n Gives an item(s) to given character(s)")
        return
    end

    local args = Commands.SplitArgs(str)
    local tokenName = args[1]
    local itemID = args[2]
    local quantity = tonum(args[3])

    local allTokens = dmhub.allTokens

    local tokens = tokenSearch(tokenName, allTokens)

    for _, token in pairs(tokens) do
        token:BeginChanges()
        token.properties:GiveItem(itemID, quantity)
        token:CompleteChanges('Receive item')
    end
end

Commands.havehero = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /havehero <token name>\n Checks if a hero with the given name exists in the game.")
        return
    end

    local args = Commands.SplitArgs(str)

    if args[1] == nil then
        return false
    end

    local characters = game.GetGameGlobalCharacters()
    local tokens = tokenSearch(args[1], table.values(characters))
    for tokenid,token in pairs(tokens) do
        return true
    end

    return false
end

Commands.createcharacter = function(str)

    if str == "help" then
        dmhub.Log(
            "Usage: /createcharacter [CopyOf]\nCreates a new character, assigned to the current user. If 'CopyOf' is provided, creates a copy of the given character, finding that character by name.")
        return
    end

    local args = Commands.SplitArgs(str)

    local heroType = nil
    local characterTypes = dmhub.GetTable(CharacterType.tableName)
    for k, v in pairs(characterTypes) do
        if (not (rawget(v, "hidden"))) and v.name == "Hero" then
            heroType = v
            break
        end
    end

    local targetLoc = { x = 0, y = 0 }

    local highestzorder = nil
    local lowestzorder = nil
    local bestobj = nil
    local objects = game.currentFloor.objects
    for key, obj in pairs(objects) do
        local keywords = obj.keywords
        if keywords and keywords["spawn"] then
            if highestzorder == nil or obj.zorder > highestzorder then
                highestzorder = obj.zorder
            end
            if lowestzorder == nil or obj.zorder < lowestzorder then
                lowestzorder = obj.zorder
                bestobj = obj
            end
        end
    end

    if bestobj ~= nil then
        targetLoc = { x = round(bestobj.x), y = round(bestobj.y) }
        bestobj:SetAndUploadZOrder(highestzorder + 1)
    end



    if heroType ~= nil then
        local charid = nil

        if args[1] ~= nil and args[1] ~= "" then
            local characters = game.GetGameGlobalCharacters()
            local tokens = tokenSearch(args[1], table.values(characters))
            for tokenid,token in pairs(tokens) do
                dmhub.CopyTokenToClipboard(token)
                charid = dmhub.PasteTokenFromClipboard(targetLoc)
                break
            end
        end

        if charid == nil then
            charid = game.CreateCharacter("character", heroType)
        end

        dmhub.Coroutine(function()
            for i = 1, 100 do
                local c = dmhub.GetCharacterById(charid)
                if c ~= nil then
                    if not dmhub.isDM then
                        c.ownerId = dmhub.userid
                    end
                    c:ModifyProperties {
                        description = "Create Character",
                        execute = function()
                            c.properties.mtime = ServerTimestamp()
                            c.properties.originalid = charid
                            c.properties.creatorid = dmhub.userid
                        end,
                    }

                    c:ChangeLocation(core.Loc { x = targetLoc.x, y = targetLoc.y })

                    coroutine.yield(0.2)

                    c:ShowSheet("Builder")
                    return
                end

                coroutine.yield(0.01)
            end
        end)
    end
end

Commands.closedocuments = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /closedocuments\n Closes all open journal documents.")
        return
    end

    GameHud.instance.documentsPanel:FireEventTree("closedocuments")
end



Commands.granttitle = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /granttitle <token name> <title ID>\n Grants a title to given character(s)")
        return
    end

    local args = Commands.SplitArgs(str)
    local tokenName = args[1]
    local titleID = args[2]

    local allTokens = dmhub.allTokens

    local tokens = tokenSearch(tokenName, allTokens)

    for _, token in pairs(tokens) do
        token:ModifyProperties {
            description = "Add Title",
            execute = function()
                token.properties:AddTitle(titleID)
            end,
        }
    end
end

local g_varDocId = "variables"

Commands.setvar = function(str)
    local args = Commands.SplitArgs(str)
    if #args ~= 2 then
        return
    end

	local doc = mod:GetDocumentSnapshot(g_varDocId)
    doc:BeginChange()
    doc.data[args[1]] = Commands.query(args[2])
    doc:CompleteChange("Change variable")
end

Commands.var = function(str)
	local doc = mod:GetDocumentSnapshot(g_varDocId)
    return doc.data[str]
end

-- (plus, minus, divide, times) (and, or) (less than, greater than, less equal, greater equal, equal, not equal)
Commands.query = function(str)
    local args = Commands.SplitArgs(str)

    if #args == 1 then
        local arg = args[1]

        if tonumber(arg) ~= nil then
            return arg
        elseif dmhub.HasSetting(arg) then
            return dmhub.GetSettingValue(arg)
        elseif string.starts_with(arg, "?") then
            arg = string.sub(arg, 2)
            local commandResult = dmhub.Execute(arg)
            print("EXECUTE::", arg, "RESULT:", commandResult)
            return commandResult
        else
            local varvalue = Commands.var(arg)
            if varvalue ~= nil then
                return varvalue
            end
            return arg
        end
    elseif #args == 3 then
        local operation = args[2]
        local a = Commands.query(args[1])
        local b = Commands.query(args[3])

        if tonumber(a) ~= nil then
            a = tonumber(a)
        else
            if a == false or a == "" or a == nil then
                a = 0
            else
                a = 1
            end
        end

        if tonumber(b) ~= nil then
            b = tonumber(b)
        else
            if b == false or b == "" or b == nil then
                b = 0
            else
                b = 1
            end
        end

        --plus
        if operation == "+" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                return a + b
            end
        end

        --minus
        if operation == "-" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                return a - b
            end
        end

        --division
        if operation == "/" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                return a / b
            end
        end

        --multiplication
        if operation == "*" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                return a * b
            end
        end

        --equal
        if operation == "=" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                if a == b then
                    return true
                end
                return false
            end
        end

        --not equal
        if operation == "~=" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                if a ~= b then
                    return true
                end
                return false
            end
        end

        --equal or less than
        if operation == "<=" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                if a <= b then
                    return true
                end
                return false
            end
        end

        --equal or greater than
        if operation == ">=" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                if a >= b then
                    return true
                end
                return false
            end
        end

        --greater than
        if operation == ">" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                if a > b then
                    return true
                end
                return false
            end
        end

        --equal or less than
        if operation == "<" then
            if tonumber(a) ~= nil and tonumber(b) ~= nil then
                if a < b then
                    return true
                end
                return false
            end

            --and
            if operation == "and" then
                if a ~= nil and b ~= nil then
                    if a and b then
                        return true
                    end
                    return false
                end
            end

            --or
            if operation == "or" then
                if a ~= nil and b ~= nil then
                    if a or b then
                        return true
                    end
                    return false
                end
            end
        end
    end
end

Commands.link = function(str)
    local args = Commands.SplitArgs(str)
    if #args ~= 1 then
        return
    end
    local doc = CustomDocument.ResolveLink(args[1])
    print("LINK:: RESOLVE", args[1], "DOC:", doc)
    if doc ~= nil then
        CustomDocument.OpenContent(doc)
    end
end

--for testing
Commands.print = function(str)
    local result = Commands.query(str)
    print("RESULT::", result)
    return result
end