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

local function ongoingEffectCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
    local result = {}
    for k, v in unhidden_pairs(characterOngoingEffects) do
        result[#result+1] = v.name
    end
    table.sort(result)
    return result
end

Commands.RegisterMacro{
    name = "applyongoingeffect",
    summary = "apply an effect",
    doc = "Usage: /applyongoingeffect <effect name>\nApplies given ongoing effect to all tokens.",
    completions = ongoingEffectCompletions,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "removeongoingeffect",
    summary = "remove an effect",
    doc = "Usage: /removeongoingeffect <effect name>\nRemoves given ongoing effect from all tokens.",
    completions = ongoingEffectCompletions,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "dramaticbanner",
    summary = "show a dramatic banner",
    doc = "Usage: /dramaticbanner <title> [ | <subtitle>]\nShows a dramatic banner centred on the currently selected token. Put a vertical bar after the title to add an optional subtitle.",
    command = function(str)
        local tokens = dmhub.selectedTokens
        if tokens == nil or #tokens == 0 then
            print("dramaticbanner: select a token first.")
            return
        end

        local title = str
        local subtitle = nil
        local barIndex = string.find(str, "|", 1, true)
        if barIndex ~= nil then
            title = string.sub(str, 1, barIndex - 1)
            subtitle = string.trim(string.sub(str, barIndex + 1))
            if subtitle == "" then
                subtitle = nil
            end
        end

        DramaticBanner.Show{
            tokenid = tokens[1].id,
            text = string.trim(title),
            subtitle = subtitle,
        }
    end,
}

Commands.RegisterMacro{
    name = "testvictory",
    summary = "fake a victory screen",
    doc = "Usage: /testvictory [off]\nSets up a fake active combat whose LiveEncounter has victory awarded, with every hero on the map added to initiative as the victorious heroes -- so the victory screen (DSVictoryScreen) shows for quick iteration. Onset Recoveries are faked +2 above current so the 'X -> Y/Z' change is visible. Pass 'off' (or 'clear') to end the fake combat and dismiss the screen.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        return {{text = "off", summary = "clear the fake victory"}}
    end,
    command = function(str)
        if not dmhub.isDM then
            print("/testvictory: DM only.")
            return
        end

        local info = GameHud.instance.initiativeInterface

        local arg = string.lower(trim(str or ""))
        if arg == "off" or arg == "clear" then
            local q = dmhub.initiativeQueue
            if q ~= nil then
                local live = q:try_get("liveEncounter")
                if type(live) == "table" then
                    live.victoryAwarded = false
                end
                q.hidden = true
                q.gameMode = "exploration"
                info.UploadInitiative()
            end
            print("/testvictory: cleared.")
            return
        end

        --Build a fresh active initiative queue containing every hero on the map.
        local q = InitiativeQueue.Create()
        q.hidden = false
        q.playersGoFirst = true
        q.playersTurn = true

        local heroTokens = {}
        for _, token in ipairs(dmhub.allTokens) do
            if token.properties ~= nil and token.properties:IsHero() then
                q:SetInitiative(InitiativeQueue.GetInitiativeId(token), 0, 0)
                heroTokens[#heroTokens + 1] = token
            end
        end

        --Attach a fake LiveEncounter already in the victory state.
        local live = LiveEncounter.Create(Encounter.new())
        live.onsetMonsterCount = 3
        live.victoryAwarded = true

        --Fake onset Recoveries 2 above current so the "onset -> current/max" arrow shows.
        local onsetHeroes = {}
        for _, token in ipairs(heroTokens) do
            local _, cur = live:GetHeroRecoveries(token)
            onsetHeroes[#onsetHeroes + 1] = {
                charid = token.charid,
                name = token.name,
                recoveries = (cur or 0) + 2,
            }
        end
        live.onsetHeroes = onsetHeroes

        q.liveEncounter = live

        info.initiativeQueue = q
        info.UploadInitiative()

        print(string.format("/testvictory: faked victory with %d heroes.", #heroTokens))
    end,
}

Commands.RegisterMacro{
    name = "collapsefloor",
    summary = "collapse a floor",
    doc = "Usage: /collapsefloor <floor name>\nCollapses given floor object and drops tokens.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local floors = game.currentMap.floors
        local result = {}
        local seen = {}
        for i = 1, #floors do
            local desc = floors[i].description
            if not seen[desc] then
                seen[desc] = true
                result[#result+1] = {text = desc, summary = "floor"}
            end
        end
        return result
    end,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "uncollapsefloor",
    summary = "uncollapse a floor",
    doc = "Usage: /uncollapsefloor <floor name>\nUncollapses given floor object.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local floors = game.currentMap.floors
        local result = {}
        local seen = {}
        for i = 1, #floors do
            local desc = floors[i].description
            if not seen[desc] then
                seen[desc] = true
                result[#result+1] = {text = desc, summary = "floor"}
            end
        end
        return result
    end,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "awardvp",
    summary = "award victory points",
    doc = "Usage: /awardvp <number>\nAwards victory points to any heroes on the map (given number or 1).",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "dorespite",
    summary = "grant a respite",
    doc = "Usage: /dorespite\nGrants a respite to all heroes on the map.",
    command = function(args)
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
    end,
}

Commands.RegisterMacro{
    name = "showallmaps",
    summary = "list all maps",
    doc = "Prints all map IDs and descriptions to the console.",
    command = function(str)
        for _, map in ipairs(game.maps) do
            print("MAP:", map.id, map.description)
        end
    end,
}

Commands.RegisterMacro{
    name = "tipsclear",
    summary = "clear learned tips",
    doc = "Wipes the local user's record of which tips have been learned/dismissed so they will show again.",
    command = function(str)
        Tip.ResetAll()
        print("Tips reset; eligible tips will re-display.")
    end,
}

Commands.RegisterMacro{
    name = "exportrenderedtoken",
    summary = "export the selected token to PNG",
    doc = "Usage: /exportrenderedtoken [padding] [resolution]\nRenders the currently selected token (frame + character/spine art) on a transparent background and prompts you to save it as a PNG.\n  padding: how much extra room around the token (default 1.5, min 1.0).\n  resolution: square output size in pixels (default 1024).",
    command = function(str)
        local tokens = dmhub.selectedTokens
        if tokens == nil or #tokens == 0 then
            print("/exportrenderedtoken: no token selected; click a token first.")
            return
        end
        local args = Commands.SplitArgs(str or "")
        local padding = tonumber(args[1])
        local resolution = tonumber(args[2])
        dmhub.ExportTokenImage{
            token = tokens[1],
            padding = padding,
            resolution = resolution,
            error = function(msg) print(msg) end,
        }
    end,
}

Commands.RegisterMacro{
    name = "tipsperf",
    summary = "benchmark tip-system overhead",
    doc = "Usage: /tipsperf [iterations]\nTimes the tip driver and its hot subroutines over N iterations (default 2000) and prints per-op costs in microseconds.",
    command = function(str)
        local n = tonumber(str) or 2000
        local gh = GameHud.instance
        if gh == nil then print("No GameHud.instance") return end

        --Snapshot live state so the timed ops behave identically regardless
        --of any tip currently showing.
        local savedActive = gh:try_get("activeTipId")
        local savedScan = gh:try_get("_tipLastScan")
        local savedState = gh:try_get("_tipState")

        local registrySize = 0
        for _ in pairs(Tip.registry) do registrySize = registrySize + 1 end

        --1) Just the modal-block check (panel tree walk).
        local sw1 = dmhub.Stopwatch()
        for i = 1, n do gh:_TipIsBlockedByDialog() end
        local ms1 = sw1.milliseconds

        --2) Full driver tick with NO active tip (scan path forced by
        --   resetting _tipLastScan each iteration so the scan actually runs).
        gh.activeTipId = nil
        gh._tipState = nil
        local sw2 = dmhub.Stopwatch()
        for i = 1, n do
            gh._tipLastScan = nil
            gh:_TipDriverTick()
            --Driver may have picked a tip; reset so next iter re-scans.
            gh.activeTipId = nil
            gh._tipState = nil
        end
        local ms2 = sw2.milliseconds

        --3) Just the registry scan loop (each tip's eligible() once).
        local sw3 = dmhub.Stopwatch()
        for i = 1, n do
            for _, spec in pairs(Tip.registry) do
                if not Tip.IsLearned(spec.id) and spec.eligible ~= nil then
                    pcall(spec.eligible)
                end
            end
        end
        local ms3 = sw3.milliseconds

        --Restore.
        gh.activeTipId = savedActive
        gh._tipLastScan = savedScan
        gh._tipState = savedState

        local function us(totalMs) return (totalMs * 1000) / n end

        print(string.format("Tip perf (%d iterations, %d tips registered):", n, registrySize))
        print(string.format("  ModalBlockCheck:  total %dms, avg %.2f us/call", ms1, us(ms1)))
        print(string.format("  Full driver tick (no active, scan path forced):"))
        print(string.format("                    total %dms, avg %.2f us/call", ms2, us(ms2)))
        print(string.format("  Registry scan (eligible() x %d tips per iter):", registrySize))
        print(string.format("                    total %dms, avg %.2f us/call", ms3, us(ms3)))
        print(string.format("At thinkTime=0.25 (4Hz), full-tick cost = %.4f%% of one core.", us(ms2) * 4 / 10000))
    end,
}

Commands.RegisterMacro{
    name = "slowstartlevel",
    summary = "set tutorial level",
    doc = "Usage: /slowstartlevel <level number>\nSets heroes on current map to a specific 'tutorial' level.",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "objectcommand",
    summary = "run object command",
    doc = "Usage: /objectcommand <keyword[.component]> <command>\nExecutes a command on map objects matching the keyword.",
    completions = function(args, argIndex)
        if argIndex == 1 then
            local result = {}
            local seen = {}
            local objects = game.currentFloor.objects
            for _, obj in pairs(objects) do
                if obj.keywords then
                    for kw, _ in pairs(obj.keywords) do
                        if not seen[kw] then
                            seen[kw] = true
                            result[#result+1] = kw
                        end
                    end
                end
            end
            table.sort(result)
            return result
        end
        return {}
    end,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "printlocs",
    summary = "print test locations",
    doc = "Prints locations of 'test'-tagged objects with area templates.",
    command = function(str)
        local objects = game.currentFloor.objects
        for key, obj in pairs(objects) do
            local keywords = obj.keywords
            if keywords and keywords["test"] then
                for key, component in pairs(obj.components) do
                    local name = string.lower(component.name)
                    if name == "area template" then
                        local locs = component:GetFilledLocs()
                        print("PRINT::", name, locs)

                    end
                end
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "activateobjects",
    summary = "toggle map objects",
    doc = "Usage: /activateobjects <keyword[.component]> [activate|deactivate|toggle]\nActivates, deactivates, or toggles map objects matching the keyword.",
    completions = function(args, argIndex)
        if argIndex == 1 then
            local result = {}
            local seen = {}
            local objects = game.currentFloor.objects
            for _, obj in pairs(objects) do
                if obj.keywords then
                    for kw, _ in pairs(obj.keywords) do
                        if not seen[kw] then
                            seen[kw] = true
                            result[#result+1] = kw
                        end
                    end
                end
            end
            table.sort(result)
            return result
        elseif argIndex == 2 then
            return {{text = "activate", summary = "activate objects"}, {text = "deactivate", summary = "deactivate objects"}, {text = "toggle", summary = "toggle objects"}}
        end
        return {}
    end,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "lockobjects",
    summary = "lock or unlock map objects",
    doc = "Usage: /lockobjects <keyword> [lock|unlock|toggle]\nLocks, unlocks, or toggles the locked state of map objects matching the keyword.",
    completions = function(args, argIndex)
        if argIndex == 1 then
            local result = {}
            local seen = {}
            local objects = game.currentFloor.objects
            for _, obj in pairs(objects) do
                if obj.keywords then
                    for kw, _ in pairs(obj.keywords) do
                        if not seen[kw] then
                            seen[kw] = true
                            result[#result+1] = kw
                        end
                    end
                end
            end
            table.sort(result)
            return result
        elseif argIndex == 2 then
            return {{text = "lock", summary = "lock objects"}, {text = "unlock", summary = "unlock objects"}, {text = "toggle", summary = "toggle objects"}}
        end
        return {}
    end,
    command = function(str)
        local args = string.split(str, " ")
        if not args[1] then
            return
        end

        local search = args[1]
        local mode = args[2] or "lock"
        local objects = game.currentFloor.objects
        for key, obj in pairs(objects) do
            local keywords = obj.keywords
            if keywords and keywords[search] then
                local newValue = cond(mode == "toggle", not obj.locked, cond(mode == "unlock", false, true))
                if newValue ~= obj.locked then
                    obj.locked = newValue
                    obj:Upload()
                end
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "openurl",
    summary = "open a URL",
    doc = "Usage: /openurl <url>\nOpens a URL in the system web browser.",
    command = function(str)
        if not str or str == "" then
            print("USAGE: /openurl <url>")
            return
        end

        dmhub.OpenURL(str)
    end,
}



Commands.RegisterMacro{
    name = "screenshake",
    summary = "shake the screen",
    doc = "Usage: /screenshake <duration> <strength> <vibrato> <randomness>\nShakes the screen locally. Use /broadcast to send to other players.",
    command = function(str)
        local args = Commands.SplitArgs(str)
        dmhub.ScreenShake(tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]))
    end,
}

Commands.RegisterMacro{
    name = "broadcast",
    summary = "broadcast a command",
    doc = "Usage: /broadcast <command>\nExecutes a command locally and broadcasts it to all other players.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {}
        for name, _ in pairs(Commands) do
            if type(Commands[name]) == "table" and Commands[name].command ~= nil then
                result[#result+1] = "/" .. name
            end
        end
        table.sort(result)
        return result
    end,
    command = function(str)
        str = string.join(Commands.SplitArgs(str), " ")
        dmhub.Execute(str)
        dmhub.Broadcast("map", str)
    end,
}

local function floorCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local floors = game.currentMap.floors
    local result = {}
    local seen = {}
    for i = 1, #floors do
        local desc = floors[i].description
        if not seen[desc] then
            seen[desc] = true
            result[#result+1] = {text = desc, summary = "floor"}
        end
    end
    return result
end

Commands.RegisterMacro{
    name = "floor",
    summary = "change active floor",
    doc = "Usage: /floor <floor name>\nChanges active floor to the given floor.",
    completions = floorCompletions,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "togglefloorvisibility",
    summary = "toggle floor visibility",
    doc = "Usage: /togglefloorvisibility [floor name]\nToggles visibility of a floor. If no name is given, toggles the current floor.",
    completions = floorCompletions,
    command = function(str)
        if not dmhub.isDM then return end

        local floor
        if str == nil or str == "" then
            floor = game.currentFloor
        else
            local floors = game.currentMap.floors
            for i = 1, #floors do
                if floors[i].description == str then
                    floor = floors[i]
                end
            end
        end

        if floor ~= nil then
            floor.floorInvisible = not floor.floorInvisible
        end
    end,
}

Commands.RegisterMacro{
    name = "deletemonsters",
    summary = "delete all monsters",
    doc = "Usage: /deletemonsters\nDeletes all monsters from current floor.",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "elevation",
    summary = "set rectangle elevation",
    doc = "Usage: /elevation <x1> <y1> <x2> <y2> <height>\nChanges elevation in a rectangular area.",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "elevationcircle",
    summary = "set circle elevation",
    doc = "Usage: /elevationcircle <x> <y> <radius> <height>\nChanges elevation in a circular area.",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "move",
    summary = "move a token",
    doc = "Usage: /move <token name> <x> <y>\nMoves token(s) to given location.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {{text = "all", summary = "all tokens"}, {text = "heroes", summary = "hero tokens"}, {text = "monsters", summary = "monster tokens"}}
        local seen = {}
        for _, token in ipairs(dmhub.allTokens) do
            local name = token.name or ""
            if name ~= "" and not seen[name] then
                seen[name] = true
                result[#result+1] = name
            end
        end
        return result
    end,
    command = function(str)
        local args = Commands.SplitArgs(str)
        local x = tonumber(args[2])
        local y = tonumber(args[3])

        local matchedTokens = tokenSearch(args[1])

        print("MOVE:: TRYING...")
        for _, token in ipairs(matchedTokens) do
            print("MOVE:: CALLING MOVE...")
            token:Move(core.Loc { x = x, y = y, floorIndex = token.floorIndex }:WithGroundLevelAltitude(), { maxCost = 5000, findVacantSpace = true })
        end
    end,
}

local function tokenNameCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {}
    local seen = {}
    for _, token in ipairs(dmhub.allTokens) do
        local name = token.name or ""
        if name ~= "" and not seen[name] then
            seen[name] = true
            result[#result+1] = name
        end
    end
    table.sort(result)
    return result
end

local function tokenSearchCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {{text = "all", summary = "all tokens"}, {text = "heroes", summary = "hero tokens"}, {text = "monsters", summary = "monster tokens"}}
    local seen = {}
    for _, token in ipairs(dmhub.allTokens) do
        local name = token.name or ""
        if name ~= "" and not seen[name] then
            seen[name] = true
            result[#result+1] = name
        end
    end
    return result
end

local function monsterNameCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {}
    local seen = {}
    for _, monster in pairs(assets.monsters) do
        local name = monster.properties:try_get("monster_type", "")
        if name ~= "" and not seen[name] then
            seen[name] = true
            result[#result+1] = name
        end
    end
    table.sort(result)
    return result
end

local function itemCompletions(args, argIndex)
    local items = dmhub.GetTable("tbl_Gear")
    local result = {}
    for k, v in unhidden_pairs(items) do
        result[#result+1] = {text = k, summary = v.name}
    end
    table.sort(result, function(a, b) return a.summary < b.summary end)
    return result
end

local function titleCompletions(args, argIndex)
    local titles = dmhub.GetTable("titles")
    local result = {}
    for k, v in unhidden_pairs(titles) do
        result[#result+1] = {text = k, summary = v.name}
    end
    table.sort(result, function(a, b) return a.summary < b.summary end)
    return result
end

local function variableCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local doc = mod:GetDocumentSnapshot("variables")
    local result = {}
    for k, _ in pairs(doc.data) do
        result[#result+1] = k
    end
    table.sort(result)
    return result
end

local function audioCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {}
    for k, v in pairs(assets.audioTable) do
        result[#result+1] = {text = k, summary = v.name or k}
    end
    table.sort(result, function(a, b) return a.summary < b.summary end)
    return result
end

local function settingCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {}
    for id, info in pairs(Settings) do
        local desc = info.description or id
        result[#result+1] = {text = desc, summary = id}
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    return result
end

local function languageCompletions(args, argIndex)
    local langTable = dmhub.GetTable(Language.tableName)
    local result = {}
    for k, v in unhidden_pairs(langTable) do
        result[#result+1] = {text = k, summary = v.name}
    end
    table.sort(result, function(a, b) return a.summary < b.summary end)
    return result
end

local function macroNameCompletions(args, argIndex)
    if argIndex ~= 1 then return {} end
    local result = {}
    for name, _ in pairs(Commands) do
        if type(Commands[name]) == "table" and Commands[name].command ~= nil then
            result[#result+1] = "/" .. name
        end
    end
    table.sort(result)
    return result
end

Commands.RegisterMacro{
    name = "hidetoken",
    summary = "hide a token",
    doc = "Usage: /hidetoken <token name>\nMakes given token(s) hidden from players.",
    completions = tokenNameCompletions,
    command = function(str)
        local allTokens = dmhub.allTokens

        for _, token in ipairs(allTokens) do
            if token.name == str then
                token.invisibleToPlayers = true
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "showtoken",
    summary = "show a token",
    doc = "Usage: /showtoken <token name>\nMakes given token(s) visible to players.",
    completions = tokenNameCompletions,
    command = function(str)
        local allTokens = dmhub.allTokens

        for _, token in ipairs(allTokens) do
            if token.name == str then
                token.invisibleToPlayers = false
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "emote",
    summary = "play an emote",
    doc = "Usage: /emote <token name> <emote name>\nSets emote active on given token(s). If only one arg, uses selected tokens.",
    completions = function(args, argIndex)
        if argIndex == 1 then
            local result = {{text = "all", summary = "all tokens"}, {text = "heroes", summary = "hero tokens"}, {text = "monsters", summary = "monster tokens"}}
            local seen = {}
            for _, token in ipairs(dmhub.allTokens) do
                local name = token.name or ""
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    result[#result+1] = name
                end
            end
            return result
        elseif argIndex == 2 then
            local dataTable = assets.emojiTable
            local result = {}
            for k, emoji in pairs(dataTable) do
                if emoji.emojiType == "Emoji" then
                    result[#result+1] = {text = k, summary = emoji.description}
                end
            end
            table.sort(result, function(a, b) return a.summary < b.summary end)
            return result
        end
        return {}
    end,
    command = function(str)
        local args = Commands.SplitArgs(str)
        if #args < 1 then
            return
        end

        if #args == 1 then
            local emote = args[1]
            for i, tok in ipairs(dmhub.selectedOrPrimaryTokens) do
                if tok.properties ~= nil then
                    tok.properties:Emote(emote, { deleteOthers = true })
                end
            end
        else
            local tokens = args[1]
            local emote = args[2]
            local allTokens = tokenSearch(tokens)
            for _, token in ipairs(allTokens) do
                if token.properties ~= nil then
                    token.properties:Emote(emote, { deleteOthers = true })
                end
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "wall",
    summary = "draw a wall",
    doc = "Usage: /wall <x1> <y1> <x2> <y2>\nDraws a wall between two points.",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "erasewall",
    summary = "erase walls",
    doc = "Usage: /erasewall <x1> <y1> <x2> <y2> <x3> <y3> <x4> <y4>\nErases walls in the given area.",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "monster",
    summary = "spawn a monster",
    doc = "Usage: /monster <monster name> <x> <y>\nSpawns the named monster from the bestiary to the given location.",
    completions = monsterNameCompletions,
    command = function(str)
        local args = Commands.SplitArgs(str)
        local monsterName = args[1]
        local x = tonum(args[2])
        local y = tonum(args[3])

        local loc = core.Loc { x = x or 0, y = y or 0, floorIndex = game.currentFloorIndex }
        local id = nil

        for monsterid,monster in pairs(assets.monsters) do
            if string.lower(monster.properties:try_get("monster_type", "")) == string.lower(monsterName) then
                id = monsterid
                break
            end
        end

        if id == nil then
            return
        end

        local token = game.SpawnTokenFromBestiaryLocally(id, loc, {
            fitLocation = true
        })

        if token ~= nil then
            token:UploadToken("Add Token")
            game.UpdateCharacterTokens()
        end
    end,
}

Commands.RegisterMacro{
    name = "spawn",
    summary = "spawn a character",
    doc = "Usage: /spawn <token name> <x> <y> [floor]\nSpawns any character(s) to given location. Floor defaults to the current floor if omitted.",
    completions = tokenSearchCompletions,
    command = function(str)
        local args = Commands.SplitArgs(str)
        local tokenName = args[1]
        local x = tonum(args[2])
        local y = tonum(args[3])
        local floorIndex = tonum(args[4])

        local characters = game.GetGameGlobalCharacters()

        local tokens = tokenSearch(tokenName, table.values(characters))

        for _, token in pairs(tokens) do
            local loc
            if floorIndex ~= nil then
                loc = core.Loc { x = x, y = y, floorIndex = floorIndex }
            else
                loc = core.Loc { x = x, y = y }
            end
            token:ChangeLocation(loc)
        end
    end,
}

Commands.RegisterMacro{
    name = "relocate",
    summary = "relocate tokens",
    doc = "Usage: /relocate x1 y1 x2 y2\nRelocates all tokens from (x1, y1) to (x2, y2).",
    command = function(str)
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
    end,
}

--[[local GetDayTypeKey = function(floorid)
	if game.FloorIsAboveGround(floorid) then
		return 'daynight'
	else
		return 'underground'
	end
end]]

Commands.RegisterMacro{
    name = "timeofday",
    summary = "set time of day",
    doc = "Usage: /timeofday <number>\nChanges time of day to the given time (between 0-9).",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "undergroundlight",
    summary = "set cave lighting",
    doc = "Usage: /undergroundlight <number>\nChanges underground illumination (between 0-10).",
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "audio",
    summary = "play audio",
    doc = "Usage: /audio <audio ID> <volume>\nPlays an audio asset at the given volume (default 50).",
    completions = audioCompletions,
    command = function(str)
        local args = Commands.SplitArgs(str)
        local audioID = args[1]
        local volume = tonumber(args[2])

        local audioAsset = assets.audioTable[audioID]

        audio.PlaySoundEvent {
            asset = audioAsset,
            volume = volume or 50,
        }
    end,
}

Commands.RegisterMacro{
    name = "speak",
    summary = "speech bubble",
    doc = "Usage: /speak <speech>\nMakes the selected token speak with a speech bubble.\nAlternate: /speak \"<token name>\" \"<speech>\" [language ID]\nWrap token name and speech in doublequotes to target a specific token. Language defaults to Caelian.",
    completions = function(args, argIndex)
        if argIndex == 1 then
            return tokenSearchCompletions(args, 1)
        elseif argIndex == 3 then
            return languageCompletions(args, argIndex)
        end
        return {}
    end,
    command = function(str)
        local trimmedStr = trim(str)
        local language = "c3c75399-6654-4ef6-a5f7-10653560f84"

        -- If the input starts with a quote, use explicit "token name" "speech" [language] mode
        if string.sub(trimmedStr, 1, 1) == '"' then
            local args = Commands.SplitArgs(str)
            local tokenName = args[1]
            local speech = args[2]
            if args[3] ~= nil then
                language = args[3]
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
        else
            -- Default mode: use selected/primary token, entire input is speech
            local selected = dmhub.selectedTokens
            if #selected == 0 then
                print("No token selected. Select a token first, or use /speak \"token name\" \"speech\".")
                return
            end

            local speech = trimmedStr

            for _, token in pairs(selected) do
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
    end,
}

Commands.RegisterMacro{
    name = "giveitem",
    summary = "give an item",
    doc = "Usage: /giveitem <token name> <item ID> <quantity>\nGives item(s) to given character(s).",
    completions = function(args, argIndex)
        if argIndex == 1 then
            return tokenSearchCompletions(args, 1)
        elseif argIndex == 2 then
            return itemCompletions(args, argIndex)
        end
        return {}
    end,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "havehero",
    summary = "check hero exists",
    doc = "Usage: /havehero <token name>\nChecks if a hero with the given name exists in the game. Returns true/false.",
    completions = tokenSearchCompletions,
    command = function(str)
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
    end,
}

Commands.RegisterMacro{
    name = "createcharacter",
    summary = "create a character",
    doc = "Usage: /createcharacter [CopyOf]\nCreates a new character assigned to the current user. If 'CopyOf' is provided, copies that character by name.",
    completions = tokenSearchCompletions,
    command = function(str)

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

    local collide = true
    while collide do
        collide = false
        --make sure the target location is unoccupied.
        for _, token in ipairs(dmhub.allTokens) do
            local locs = token.locsOccupying
            for i,loc in ipairs(locs) do
                if loc.x == targetLoc.x and loc.y == targetLoc.y then
                    targetLoc.x = targetLoc.x + 1
                    collide = true
                    break
                end
            end
        end
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
    end,
}

-- /buildchar: parse a freeform description of a hero and report how it was
-- interpreted (class -> level -> subclass -> ancestry -> kit -> class/subclass
-- choices). For now this only PRINTS its interpretation to chat; it does not yet
-- build the character. The matcher does greedy longest-contiguous-run matching of
-- the typed words against each candidate's name words, so fragments like
-- "Black Ash" bind to "College of Black Ash" and multi-word names with filler
-- words like "Cloak and Dagger" match as a unit.
do
    local STOP = { ["of"] = true, ["the"] = true, ["and"] = true, ["a"] = true, ["an"] = true }

    -- Lowercase a string and split it into alphanumeric word tokens.
    local function BuildChar_SplitWords(s)
        local t = {}
        for w in string.gmatch(string.lower(s), "[%w]+") do
            t[#t + 1] = w
        end
        return t
    end

    -- Longest L such that words[i..i+L-1] (all currently unused) appears as a
    -- contiguous run somewhere within candWords.
    -- With prefix=false, each input word must equal the candidate word. With
    -- prefix=true, an input word may instead be a prefix of the candidate word
    -- (e.g. "chrono" matches "chronopathy"); prefix matches require a non-stopword
    -- of at least 3 characters so short/common fragments don't match spuriously.
    local function BuildChar_ContiguousMatchLen(words, used, i, candWords, prefix)
        local best = 0
        for s = 1, #candWords do
            local L = 0
            while true do
                local iw, cw = words[i + L], candWords[s + L]
                if iw == nil or cw == nil or used[i + L] then
                    break
                end
                local matched = (iw == cw)
                if (not matched) and prefix and (not STOP[iw]) and #iw >= 3
                    and string.sub(cw, 1, #iw) == iw then
                    matched = true
                end
                if not matched then
                    break
                end
                L = L + 1
            end
            if L > best then
                best = L
            end
        end
        return best
    end

    -- Find the single best candidate match over the unused words. Prefers a
    -- longer matched run, then higher coverage of the candidate's own name. A
    -- matched run must include at least one non-stopword so "and"/"of" alone
    -- never anchors a match. Returns { cand, i, len, coverage } or nil.
    --
    -- Exact matches always win: only when no candidate matches exactly does it
    -- retry allowing start-of-word (prefix) matches, so e.g. "Talent Chrono"
    -- resolves the Chronopathy subclass once exact matches are exhausted.
    local function BuildChar_BestMatch(words, used, candidates)
        local function scan(prefix)
            local best = nil
            for _, cand in ipairs(candidates) do
                for i = 1, #words do
                    if not used[i] then
                        local L = BuildChar_ContiguousMatchLen(words, used, i, cand.words, prefix)
                        if L > 0 then
                            local hasSig = false
                            for t = 0, L - 1 do
                                if not STOP[words[i + t]] then
                                    hasSig = true
                                    break
                                end
                            end
                            if hasSig then
                                local coverage = L / #cand.words
                                if best == nil or L > best.len or (L == best.len and coverage > best.coverage) then
                                    best = { cand = cand, i = i, len = L, coverage = coverage }
                                end
                            end
                        end
                    end
                end
            end
            return best
        end
        return scan(false) or scan(true)
    end

    local function BuildChar_Consume(used, m)
        for t = 0, m.len - 1 do
            used[m.i + t] = true
        end
    end

    -- Build a candidate list from a data table. filter(v, k) -> bool selects rows.
    local function BuildChar_Candidates(tbl, filter)
        local out = {}
        for k, v in pairs(tbl) do
            if (not rawget(v, "hidden")) and (filter == nil or filter(v, k)) then
                out[#out + 1] = { id = k, name = v.name, obj = v, words = BuildChar_SplitWords(v.name) }
            end
        end
        return out
    end

    -- Collect every CharacterFeatureChoice option offered by a class (or subclass)
    -- up to the given level, as match candidates.
    local function BuildChar_AddChoiceOptions(classObj, level, out)
        if classObj == nil then
            return
        end
        local fill = {}
        classObj:FillLevelsUpTo(level, false, "nonprimary", fill)
        for _, lv in ipairs(fill) do
            for _, feat in ipairs(lv:try_get("features", {})) do
                if feat.typeName == "CharacterFeatureChoice" then
                    for _, opt in ipairs(feat:try_get("options", {})) do
                        local optName = opt:try_get("name", "")
                        out[#out + 1] = {
                            id = opt:try_get("guid", "?"),
                            name = optName,
                            choiceName = feat:try_get("name", "?"),
                            choiceGuid = feat:try_get("guid", "?"),
                            words = BuildChar_SplitWords(optName),
                        }
                    end
                end
            end
        end
    end

    -- Find the guid of the CharacterSubclassChoice in a class's levels up to the
    -- given level (this is the levelChoices key under which the chosen subclass id
    -- is recorded). Returns nil if the class has no subclass choice yet.
    local function BuildChar_FindSubclassChoiceGuid(classObj, level)
        if classObj == nil then
            return nil
        end
        local fill = {}
        classObj:FillLevelsUpTo(level, false, "nonprimary", fill)
        for _, lv in ipairs(fill) do
            for _, feat in ipairs(lv:try_get("features", {})) do
                if feat.typeName == "CharacterSubclassChoice" then
                    return feat:try_get("guid")
                end
            end
        end
        return nil
    end

    -- Shorten a subclass name to its distinctive part for use in a token name,
    -- e.g. "College of Black Ash" -> "Black Ash", "Order of the Mortal Coil" ->
    -- "Mortal Coil". Names without a "<word> of ..." prefix are returned as-is.
    local function BuildChar_ShortSubclass(name)
        return string.match(name, "^%a+ of [Tt]he (.+)$")
            or string.match(name, "^%a+ of (.+)$")
            or name
    end

    -- Normalize a single choice's selectable options to a list of { id, name },
    -- regardless of which option-enumeration method the choice type implements.
    local function BuildChar_OptionList(feature, hero, readLc)
        local out = {}
        if CharacterBuilder._hasFn(feature, "GetEntries") then
            for _, e in ipairs(feature:GetEntries(hero) or {}) do
                local g = e:try_get("guid")
                if g and not e:try_get("hidden", false) then
                    out[#out + 1] = { id = g, name = e:try_get("name", "?") }
                end
            end
        elseif CharacterBuilder._hasFn(feature, "GetOptions") then
            for _, o in ipairs(feature:GetOptions(readLc, hero) or {}) do
                if o.guid and not o.hidden then
                    out[#out + 1] = { id = o.guid, name = o.name or "?" }
                end
            end
        elseif CharacterBuilder._hasFn(feature, "Choices") then
            for _, c in ipairs(feature:Choices(1, readLc[feature.guid] or {}, hero) or {}) do
                if c.id and not c.hidden then
                    out[#out + 1] = { id = c.id, name = c.text or "?" }
                end
            end
        end
        return out
    end

    -- Randomly fill every still-unfilled choice on the hero (subclass, skills,
    -- heroic abilities, perks, ancestry traits, and any subclass-revealed
    -- choices). Iterates to a fixpoint so that choices unlocked by an earlier
    -- random pick (e.g. a subclass's own abilities) also get filled. Must run
    -- inside a ModifyProperties execute. Returns a list of "Choice -> Option"
    -- description strings for reporting. Selections already present (the user's
    -- explicitly matched choices) are left untouched.
    local function BuildChar_RandomFillUnchosen(hero)
        local picks = {}
        local lcWrite = hero:get_or_add("levelChoices", {})
        for _ = 1, 6 do
            local filledAny = false
            for _, entry in ipairs(hero:GetClassFeaturesAndChoicesWithDetails()) do
                local f = entry.feature
                local isChoice = CharacterBuilder._hasFn(f, "GetEntries")
                    or CharacterBuilder._hasFn(f, "GetOptions")
                    or CharacterBuilder._hasFn(f, "Choices")
                if isChoice then
                    local guid = f:try_get("guid")
                    if guid then
                        local selected = lcWrite[guid] or {}
                        local need = f:NumChoices(hero) - #selected
                        if need > 0 then
                            local opts = BuildChar_OptionList(f, hero, hero:GetLevelChoices() or {})
                            local taken = {}
                            for _, s in ipairs(selected) do
                                taken[s] = true
                            end
                            local pool = {}
                            for _, o in ipairs(opts) do
                                if not taken[o.id] then
                                    pool[#pool + 1] = o
                                end
                            end
                            local newsel = {}
                            for _, s in ipairs(selected) do
                                newsel[#newsel + 1] = s
                            end
                            while need > 0 and #pool > 0 do
                                local o = table.remove(pool, math.random(1, #pool))
                                newsel[#newsel + 1] = o.id
                                picks[#picks + 1] = f:try_get("name", "?") .. " -> " .. o.name
                                need = need - 1
                                filledAny = true
                            end
                            lcWrite[guid] = newsel
                        end
                    end
                end
            end
            if not filledAny then
                break
            end
        end

        -- Kit is NOT stored in levelChoices (it lives in the top-level kitid /
        -- kitid2 fields), so the loop above never sees it. Fill it here via the
        -- builder's synthetic CharacterKitChoice, which knows the kit types this
        -- class/subclass allows. Runs after the loop so any randomly-chosen
        -- subclass that changes the kit allowance is already in place, and honors
        -- a kit the user already set (GetSelected reflects kitid/kitid2).
        --
        -- CanHaveKits / KitTypesAllowed are derived from GetActiveModifiers, which
        -- is cached per game-update frame. Since the class was set earlier in this
        -- same execute (and may have been cached empty before that), Invalidate()
        -- forces those modifiers to recompute so the kit allowance is current.
        hero:Invalidate()
        if hero:CanHaveKits() then
            local kitChoice = CharacterKitChoice.CreateNew(hero)
            if kitChoice ~= nil then
                local selected = kitChoice:GetSelected(hero)
                local taken = {}
                for _, s in ipairs(selected) do
                    taken[s] = true
                end
                local pool = {}
                for _, o in ipairs(kitChoice:GetOptions() or {}) do
                    if o.guid and not taken[o.guid] then
                        pool[#pool + 1] = o
                    end
                end
                local need = kitChoice:NumChoices(hero) - #selected
                while need > 0 and #pool > 0 do
                    local o = table.remove(pool, math.random(1, #pool))
                    kitChoice:SaveSelection(hero, { id = o.guid })
                    picks[#picks + 1] = "Kit -> " .. (o.name or "?")
                    need = need - 1
                end
            end
        end

        return picks
    end

    Commands.RegisterMacro{
        name = "buildchar",
        summary = "build the selected hero from a description",
        doc = "Usage: /buildchar <class> [level N] [subclass] [ancestry] [kit] [ability choices...]\n" ..
            "Builds the SELECTED character token from a freeform description, e.g.\n" ..
            "/buildchar Shadow Black Ash Cloak and Dagger. With no token selected, spawns a\n" ..
            "new hero in the middle of the view and builds onto it.\n" ..
            "Matching priority: class -> level -> subclass -> ancestry -> kit -> class/subclass choices.\n" ..
            "Sets class/level, subclass, ancestry, kit and the named ability choices, then posts a\n" ..
            "summary to chat. Add the word 'random' to fill all remaining unfilled choices (subclass,\n" ..
            "skills, heroic abilities, perks, ancestry traits, kit) with random valid picks.\n" ..
            "Characteristics are defaulted only if the token has none yet. The token is renamed to a\n" ..
            "brief description (e.g. \"Lv3 Devil Shadow (Black Ash)\") and given the class portrait.",
        command = function(str)
            str = trim(str or "")
            if str == "" then
                chat.Send("/buildchar: type a description, e.g. /buildchar Shadow Black Ash Cloak and Dagger")
                return
            end

            -- Pull out an explicit level ("level N" / "lvl N"); default to 1.
            local lower = string.lower(str)
            local level = 1
            local lvl = string.match(lower, "level%s+(%d+)") or string.match(lower, "lvl%s+(%d+)")
            if lvl then
                level = tonumber(lvl)
            end
            local cleaned = string.gsub(lower, "level%s+%d+", " ")
            cleaned = string.gsub(cleaned, "lvl%s+%d+", " ")

            local words = BuildChar_SplitWords(cleaned)
            local used = {}

            -- "random" keyword: fill all remaining unfilled choices randomly.
            -- Consume the word so it is not reported as unmatched.
            local wantRandom = false
            for i, w in ipairs(words) do
                if w == "random" then
                    wantRandom = true
                    used[i] = true
                end
            end

            local classes = dmhub.GetTable("classes")
            local subs = dmhub.GetTable("subclasses")
            local races = dmhub.GetTable("races")
            local kits = dmhub.GetTable("kits")

            -- Class (base classes only).
            local classMatch = BuildChar_BestMatch(words, used,
                BuildChar_Candidates(classes, function(v) return not v.isSubclass end))
            local classObj = nil
            if classMatch then
                BuildChar_Consume(used, classMatch)
                classObj = classMatch.cand.obj
            end

            -- Subclass (scoped to the matched class).
            local subMatch = nil
            if classObj then
                subMatch = BuildChar_BestMatch(words, used,
                    BuildChar_Candidates(subs, function(v) return v.primaryClassId == classMatch.cand.id end))
                if subMatch then
                    BuildChar_Consume(used, subMatch)
                end
            end

            -- Ancestry.
            local raceMatch = BuildChar_BestMatch(words, used, BuildChar_Candidates(races))
            if raceMatch then
                BuildChar_Consume(used, raceMatch)
            end

            -- Kit.
            local kitMatch = BuildChar_BestMatch(words, used, BuildChar_Candidates(kits))
            if kitMatch then
                BuildChar_Consume(used, kitMatch)
            end

            -- Class/subclass ability (and other feature) choices. Match as many
            -- as the leftover words support.
            local choiceCands = {}
            BuildChar_AddChoiceOptions(classObj, level, choiceCands)
            if subMatch then
                BuildChar_AddChoiceOptions(subMatch.cand.obj, level, choiceCands)
            end

            local chosen = {}
            while true do
                local m = BuildChar_BestMatch(words, used, choiceCands)
                if m == nil then
                    break
                end
                BuildChar_Consume(used, m)
                chosen[#chosen + 1] = m.cand
            end

            -- Need at least a class to build anything.
            if classObj == nil then
                chat.Send("/buildchar: could not recognize a class in \"" .. str ..
                    "\". Start with a class name, e.g. /buildchar Shadow Black Ash.")
                return
            end

            local subclassChoiceGuid = nil
            if subMatch then
                subclassChoiceGuid = BuildChar_FindSubclassChoiceGuid(classObj, level)
            end

            -- Apply the build to a token (the selected one, or a freshly spawned
            -- hero). Outside the character sheet, so ModifyProperties.
            local function doBuild(token)
            local defaultedAttrs = false
            local randomPicks = nil
            token:ModifyProperties{
                description = "Build " .. classObj.name .. " via /buildchar",
                execute = function()
                    local props = token.properties

                    -- Characteristics: only default when every characteristic is
                    -- still absent or zero (the freshly-created-token signature), so
                    -- re-running /buildchar never clobbers a tuned build. Use the
                    -- class's own array/locked-characteristic system (the same path
                    -- the builder uses) so locked primaries -- e.g. a Censor's
                    -- Presence locked at 2 -- are respected rather than overwritten.
                    local attrs = props:get_or_add("attributes", {})
                    local hasAttrs = false
                    for _, id in ipairs(creature.attributeIds) do
                        local a = attrs[id]
                        if a ~= nil and (a.baseValue or 0) ~= 0 then
                            hasAttrs = true
                            break
                        end
                    end
                    if not hasAttrs then
                        local bc = classObj:try_get("baseCharacteristics")
                        if bc and bc.arrays then
                            -- Pick array 1 (one high score). Locked characteristics
                            -- are filled from baseCharacteristics by
                            -- CalculateBaseAttributes; the remaining ones are
                            -- assigned the array slots in attribute order.
                            local ab = { array = 1 }
                            local slot = 1
                            for _, attrid in ipairs(creature.attributeIds) do
                                if bc[attrid] == nil then
                                    ab[attrid] = slot
                                    slot = slot + 1
                                end
                            end
                            props.attributeBuild = ab
                            classObj:CalculateBaseAttributes(props)
                        else
                            for id, v in pairs({ mgt = 2, agl = 2, rea = 1, inu = 1, prs = -1 }) do
                                attrs[id] = { baseValue = v }
                            end
                        end
                        defaultedAttrs = true
                    end

                    -- Class + level (replace any existing class).
                    local classes = props:get_or_add("classes", {})
                    for i = #classes, 1, -1 do
                        classes[i] = nil
                    end
                    classes[1] = { classid = classMatch.cand.id, level = level }

                    -- Ancestry and kit.
                    if raceMatch then
                        props.raceid = raceMatch.cand.id
                    end
                    if kitMatch then
                        props.kitid = kitMatch.cand.id
                    end

                    -- Subclass + ability choices (levelChoices).
                    local lc = props:get_or_add("levelChoices", {})
                    if subMatch and subclassChoiceGuid then
                        lc[subclassChoiceGuid] = { subMatch.cand.id }
                    end
                    for _, c in ipairs(chosen) do
                        lc[c.choiceGuid] = { c.id }
                    end

                    -- "random": fill everything still unchosen. Runs last so it
                    -- only touches choices the user did not explicitly name, and
                    -- so the class/subclass are already set when it enumerates.
                    if wantRandom then
                        randomPicks = BuildChar_RandomFillUnchosen(props)
                    end
                end,
            }

            -- Name the token from the final build (reads back subclass/ancestry so
            -- random picks are reflected) and apply the class portrait. Name and
            -- portrait are appearance fields, set on the token then uploaded.
            local props = token.properties
            local nameParts = { "Lv" .. level }
            if props:try_get("raceid") then
                local r = races[props.raceid]
                if r then
                    nameParts[#nameParts + 1] = r.name
                end
            end
            nameParts[#nameParts + 1] = classObj.name
            local generatedName = table.concat(nameParts, " ")
            local finalSubs = props:GetSubclasses() or {}
            if finalSubs[1] then
                generatedName = generatedName .. " (" .. BuildChar_ShortSubclass(finalSubs[1].name) .. ")"
            end
            token.name = generatedName

            local classPortrait = classObj:try_get("portraitid", "")
            if classPortrait ~= "" then
                token.portrait = classPortrait
            end
            token:UploadAppearance()

            -- Report what was built.
            local lines = {}
            lines[#lines + 1] = "**/buildchar** built " .. (token.name or "the selected token")
            lines[#lines + 1] = "Class: " .. classObj.name .. " -- Level " .. level
            if subMatch then
                if subclassChoiceGuid then
                    lines[#lines + 1] = "Subclass: " .. subMatch.cand.name
                else
                    lines[#lines + 1] = "Subclass: " .. subMatch.cand.name ..
                        " (matched, but this class has no subclass choice at level " .. level .. " -- not set)"
                end
            end
            if raceMatch then
                lines[#lines + 1] = "Ancestry: " .. raceMatch.cand.name
            end
            if kitMatch then
                lines[#lines + 1] = "Kit: " .. kitMatch.cand.name
            end
            for _, c in ipairs(chosen) do
                lines[#lines + 1] = "Choice [" .. c.choiceName .. "]: " .. c.name
            end
            if defaultedAttrs then
                local labels = { mgt = "M", agl = "A", rea = "R", inu = "I", prs = "P" }
                local parts = {}
                for _, id in ipairs(creature.attributeIds) do
                    parts[#parts + 1] = labels[id] .. tostring(props:GetAttribute(id):Value())
                end
                lines[#lines + 1] = "Characteristics: defaulted (" .. table.concat(parts, " ") ..
                    ") -- adjust on the sheet."
            end
            if randomPicks and #randomPicks > 0 then
                lines[#lines + 1] = "Randomly chose " .. #randomPicks .. ":"
                for _, p in ipairs(randomPicks) do
                    lines[#lines + 1] = "  " .. p
                end
            elseif wantRandom then
                lines[#lines + 1] = "Random: nothing left to fill."
            end
            local leftover = {}
            for i, w in ipairs(words) do
                if not used[i] then
                    leftover[#leftover + 1] = w
                end
            end
            if #leftover > 0 then
                lines[#lines + 1] = "Unmatched: " .. table.concat(leftover, " ")
            end

            chat.Send(table.concat(lines, "\n"))
            end -- doBuild

            -- Build onto the selected/primary token if there is one; otherwise
            -- spawn a fresh hero in the middle of the current view and build that.
            local tokens = dmhub.selectedOrPrimaryTokens or {}
            if tokens[1] ~= nil then
                doBuild(tokens[1])
                return
            end

            local heroType = nil
            for _, ct in pairs(dmhub.GetTable(CharacterType.tableName)) do
                if (not rawget(ct, "hidden")) and ct.name == "Hero" then
                    heroType = ct
                    break
                end
            end
            if heroType == nil then
                chat.Send("/buildchar: no token selected, and could not find the Hero " ..
                    "character type to spawn one.")
                return
            end

            -- World coordinates map 1:1 to Loc tile coordinates, so the camera
            -- center rounds directly to the middle-of-screen tile.
            local cam = dmhub.cameraPosition
            local spawnLoc = core.Loc{
                x = round(cam.x),
                y = round(cam.y),
                floorIndex = game.currentFloorIndex,
            }

            local charid = game.CreateCharacter("character", heroType)
            dmhub.Coroutine(function()
                if mod.unloaded then return end
                local token
                for _ = 1, 200 do
                    coroutine.yield(0.05)
                    token = dmhub.GetCharacterById(charid)
                    if token ~= nil then break end
                end
                if token == nil then
                    chat.Send("/buildchar: timed out creating a new token.")
                    return
                end
                if not dmhub.isDM then
                    token.ownerId = dmhub.userid
                end
                token:ModifyProperties{
                    description = "Create Character",
                    execute = function()
                        token.properties.mtime = ServerTimestamp()
                        token.properties.originalid = charid
                        token.properties.creatorid = dmhub.userid
                    end,
                }
                token:ChangeLocation(spawnLoc)
                coroutine.yield(0.1)
                dmhub.SelectToken(charid)
                doBuild(token)
            end)
        end,
    }
end

Commands.RegisterMacro{
    name = "closedocuments",
    summary = "close all documents",
    doc = "Usage: /closedocuments\nCloses all open journal documents.",
    command = function(str)
        GameHud.instance.documentsPanel:FireEventTree("closedocuments")
    end,
}



Commands.RegisterMacro{
    name = "granttitle",
    summary = "grant a title",
    doc = "Usage: /granttitle <token name> <title ID>\nGrants a title to given character(s).",
    completions = function(args, argIndex)
        if argIndex == 1 then
            return tokenSearchCompletions(args, 1)
        elseif argIndex == 2 then
            return titleCompletions(args, argIndex)
        end
        return {}
    end,
    command = function(str)
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
    end,
}

local g_varDocId = "variables"

Commands.RegisterMacro{
    name = "setvar",
    summary = "set a variable",
    doc = "Usage: /setvar <name> <value>\nSets a shared variable to the given value (evaluated as a query).",
    completions = variableCompletions,
    command = function(str)
        local args = Commands.SplitArgs(str)
        if #args ~= 2 then
            return
        end

        local doc = mod:GetDocumentSnapshot(g_varDocId)
        doc:BeginChange()
        doc.data[args[1]] = Commands.query(args[2])
        doc:CompleteChange("Change variable")
    end,
}

Commands.RegisterMacro{
    name = "var",
    summary = "get a variable",
    doc = "Usage: /var <name>\nReturns the value of a shared variable.",
    completions = variableCompletions,
    command = function(str)
        local doc = mod:GetDocumentSnapshot(g_varDocId)
        return doc.data[str]
    end,
}

local function QueryConvertValue(a)
    if tonumber(a) ~= nil then
        a = tonumber(a)
    else
        if a == false or a == "" or a == nil then
            a = 0
        else
            a = 1
        end
    end

    return a
end

local function Truthy(a)
    if a == false or a == "" or a == nil or a == 0 then
        return false
    end
    return true
end

-- (plus, minus, divide, times) (and, or) (less than, greater than, less equal, greater equal, equal, not equal)
Commands.RegisterMacro{
    name = "query",
    summary = "evaluate expression",
    doc = "Usage: /query <expression>\nEvaluates a query expression. Supports arithmetic, comparisons, boolean logic, settings, and variables.",
    command = function(str)
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
    elseif #args == 2 then
        local operation = args[1]
        local a = Commands.query(args[2])
        a = QueryConvertValue(a)

        if operation == "not" then
            return not Truthy(a)
        end
    elseif #args == 3 then
        local operation = args[2]
        local a = Commands.query(args[1])
        local b = Commands.query(args[3])

        a = QueryConvertValue(a)
        b = QueryConvertValue(b)

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
        end

        --and
        if operation == "and" then
            return Truthy(a) and Truthy(b)
        end

        --or
        if operation == "or" then
            return Truthy(a) or Truthy(b)
        end
    end
    end,
}

Commands.RegisterMacro{
    name = "link",
    summary = "open a link",
    doc = "Usage: /link <link>\nResolves and opens a document link.",
    command = function(str)
        local args = Commands.SplitArgs(str)
        if #args ~= 1 then
            return
        end
        local doc = CustomDocument.ResolveLink(args[1])
        print("LINK:: RESOLVE", args[1], "DOC:", doc)
        if doc ~= nil then
            CustomDocument.OpenContent(doc)
        end
    end,
}

Commands.RegisterMacro{
    name = "tracepanel",
    summary = "debug a panel",
    doc = "Usage: /tracepanel <panel ID>\nTraces a panel and prints debug info about it.",
    command = function(str)
        local args = Commands.SplitArgs(str)
        if #args ~= 1 then
            return
        end

        local panel = gui.GetSheetById(args[1])
        if panel == nil then
            local trace = dmhub.GetPanelTrace(args[1])
            if trace ~= nil then
                print("Trace:", trace)
                return
            end
            print("Trace: No panel found")
            return
        end

        print("Trace: panel info:", panel.classes, panel.debugBacktrace)
    end,
}

local TestGoblinScript = function(symbols)
    --local symbols = GenerateSymbols(properties)
    local a = 18
    local b = 6
    local c = 1
    local d = symbols("level")
    local e = d - c
    local f = e * b
    local g = a + f
    return g
end

Commands.RegisterMacro{
    name = "moveobject",
    summary = "move map object",
    doc = "Usage: /moveobject <keyword> <x> <y>\nMoves objects matching the keyword to the given position.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {}
        local seen = {}
        local objects = game.currentFloor.objects
        for _, obj in pairs(objects) do
            if obj.keywords then
                for kw, _ in pairs(obj.keywords) do
                    if not seen[kw] then
                        seen[kw] = true
                        result[#result+1] = kw
                    end
                end
            end
        end
        table.sort(result)
        return result
    end,
    command = function(str)
        local args = string.split(str, " ")
        if #args ~= 3 then
            return
        end


        local search = args[1]
        local x = tonumber(args[2])
        local y = tonumber(args[3])
        local objects = game.currentFloor.objects

        for key, obj in pairs(objects) do
            if obj.keywords and obj.keywords[search] then
                obj.SetAndUploadPos(obj, x, y)
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "awardherotokens",
    summary = "award hero tokens",
    doc = "Usage: /awardherotokens <number>\nAwards hero tokens to any heroes on the map (given number or 1).",
    command = function(str)
        if not dmhub.isDM then
            return
        end

        local points = tonumber(str) or 1
        for _, token in ipairs(dmhub.allTokens) do
            if token.properties:IsHero() then
                token:ModifyProperties {
                    description = "Award Hero Token",
                    execute = function()
                        token.properties:SetHeroTokens(token.properties:GetHeroTokens() + points)
                    end,
                }

                local classInfo = token.properties:IsHero() and token.properties:GetClass() or nil
                track("hero_token_change", {
                    change = points,
                    source = "manual",
                    class = classInfo and classInfo.name or "unknown",
                    dailyLimit = 30,
                })

                break
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "awardmalice",
    summary = "award malice",
    doc = "Usage: /awardmalice <number>\nAwards malice to the director (given number or 1).",
    command = function(str)
        if not dmhub.isDM then
            return
        end

        local points = tonumber(str) or 1
        CharacterResource.SetMalice(CharacterResource.GetMalice() + points)
    end,
}


Commands.RegisterMacro{
    name = "awardrenown",
    summary = "award renown",
    doc = "Usage: /awardrenown <number>\nAwards renown to any heroes on the map (given number or 1).",
    command = function(str)
        if not dmhub.isDM then
            return
        end

        local points = tonumber(str) or 1
        for _, token in ipairs(dmhub.allTokens) do
            if token.properties:IsHero() then
                token:ModifyProperties {
                    description = "Award Renown",
                    execute = function()
                        local feature = DeepCopy(MCDMImporter.GetStandardFeature("Renown Modification"))
                        if feature ~= nil then
                            feature.guid = dmhub.GenerateGuid()
                            feature.modifiers[1].sourceguid = feature.guid
                            feature.name = "Custom Modification"
                            feature.modifiers[1].name = "Custom Modification"
                            if feature.modifiers[1].behavior == "resource" then
                                feature.modifiers[1].num = points
                            else
                                feature.modifiers[1].value = points
                            end
                            feature.source = "Custom"
                            feature.modifiers[1].source = "Custom"
                            local features = token.properties:get_or_add("characterFeatures", {})
                            features[#features + 1] = feature
                        end
                    end,
                }
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "awardwealth",
    summary = "award wealth",
    doc = "Usage: /awardwealth <number>\nAwards wealth to any heroes on the map (given number or 1).",
    command = function(str)
        if not dmhub.isDM then
            return
        end

        local points = tonumber(str) or 1
        for _, token in ipairs(dmhub.allTokens) do
            if token.properties:IsHero() then
                token:ModifyProperties {
                    description = "Award Wealth",
                    execute = function()
                        local feature = DeepCopy(MCDMImporter.GetStandardFeature("Wealth Modification"))
                        if feature ~= nil then
                            feature.guid = dmhub.GenerateGuid()
                            feature.modifiers[1].sourceguid = feature.guid
                            feature.name = "Custom Modification"
                            feature.modifiers[1].name = "Custom Modification"
                            if feature.modifiers[1].behavior == "resource" then
                                feature.modifiers[1].num = points
                            else
                                feature.modifiers[1].value = points
                            end
                            feature.source = "Custom"
                            feature.modifiers[1].source = "Custom"
                            local features = token.properties:get_or_add("characterFeatures", {})
                            features[#features + 1] = feature
                        end
                    end,
                }
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "languagesknown",
    summary = "list known languages",
    doc = "Prints all locally known languages to the console.",
    command = function(str)
        local languagesTable = dmhub.GetTable(Language.tableName)
        local languagesKnown = creature.g_languagesKnownLocally
        for langid,_ in pairs(languagesKnown) do
            local lang = languagesTable[langid]
            if lang == nil then
                print("Language: Unknown", langid)
            else
                print("Language:", langid, lang.name)
            end
        end
    end,
}


Commands.RegisterMacro{
    name = "print",
    summary = "performance test",
    doc = "Performance test: deep-copies all token properties 100 times and prints elapsed time.",
    command = function(str)
        local tokens = dmhub.allTokens

        local sw = dmhub.Stopwatch()
        sw:Init()
        for i=1,100 do
            for k,v in ipairs(tokens) do
                local copy = DeepCopy(v.properties)
            end
        end
        sw:Stop()
        print("Time:", sw.milliseconds, #tokens)
    end,
}

Commands.RegisterMacro{
    name = "listmaps",
    summary = "list all maps",
    doc = "Usage: /listmaps\nPrints a JSON object mapping map IDs to map names.",
    command = function(str)
        local result = {}
        for _,map in ipairs(game.maps) do
            result[map.id] = map.description
        end
        print(json(result))
    end,
}

Commands.RegisterMacro{
    name = "listmodifiers",
    summary = "list active modifiers",
    doc = "Usage: /listmodifiers\nPrints the JSON for each active modifier on the selected token.",
    command = function(str)
        local selected = dmhub.selectedTokens
        if #selected == 0 then
            print("No token selected.")
            return
        end

        local token = selected[1]
        if token.properties == nil then
            print("Selected token has no properties.")
            return
        end

        local modifiers = token.properties:GetActiveModifiers()
        print(string.format("Active modifiers for %s: %d", token.description, #modifiers))
        for i, entry in ipairs(modifiers) do
            print(string.format("--- Modifier %d ---", i))
            print(json(entry.mod))
        end
    end,
}

if devmode() then

    Commands.RegisterMacro{
        name = "exporttables",
        summary = "export all tables",
        doc = "Usage: /exporttables\nExports all data tables and monsters to files. Dev only.",
        command = function(str)
            dmhub.ExportAllTables()
            dmhub.ExportAllMonsters()
        end,
    }

    Commands.RegisterMacro{
        name = "importtables",
        summary = "import all tables",
        doc = "Usage: /importtables\nImports all data tables and monsters from files. Dev only.",
        command = function(str)
            dmhub.ImportAllTables()
            dmhub.ImportAllMonsters()
        end,
    }

    Commands.RegisterMacro{
        name = "gc",
        summary = "force garbage collect",
        doc = "Usage: /gc\nForces a Lua garbage collection cycle. Dev only.",
        command = function(str)
            collectgarbage("collect")
        end,
    }

    local function ImportChatMessage(text, isError)
        if ExtChatMessage ~= nil and ExtChatMessage.SendTitled ~= nil then
            local color = isError and "#ff4444" or "#44ff88"
            local title = isError and "Import Error" or "Import"
            ExtChatMessage.SendTitled(text, title, color, dmhub.userid)
        else
            chat.Send(text)
        end
    end

    local function ValidateChatMessage(text, level)
        -- level: "error", "warning", "success", "info"
        if ExtChatMessage ~= nil and ExtChatMessage.SendTitled ~= nil then
            local colors = {
                error = "#ff4444",
                warning = "#ffcc44",
                success = "#44ff88",
                info = "#88bbff",
            }
            local titles = {
                error = "Validate: ERROR",
                warning = "Validate: Warning",
                success = "Validate",
                info = "Validate",
            }
            local color = colors[level] or "#88bbff"
            local title = titles[level] or "Validate"
            ExtChatMessage.SendTitled(text, title, color, dmhub.userid)
        else
            chat.Send(text)
        end
    end

    -- Known valid table names (case-sensitive).
    local g_validTableNames = {
        characterOngoingEffects = true,
        charConditions = true,
        standardAbilities = true,
        tbl_Gear = true,
        MonsterGroup = true,
        classes = true,
        subclasses = true,
        kits = true,
        cultures = true,
        feats = true,
        Skills = true,
        damageTypes = true,
        characterResources = true,
        complications = true,
        titles = true,
        races = true,
        globalRuleMods = true,
        customAttributes = true,
        conditionRiders = true,
        encounters = true,
        backgrounds = true,
        equipmentCategories = true,
        documents = true,
        careers = true,
        languages = true,
        Deities = true,
        DeityDomains = true,
        minionWithCaptain = true,
        importerPowerTableEffects = true,
        importerMonsterTraits = true,
        VisionType = true,
        parties = true,
        adventureTables = true,
        compendiumPermissions = true,
        characteristicsTable = true,
        importerAbilityEffects = true,
        pdfReferences = true,
        featurePrefabs = true,
        creatureTemplates = true,
        languageRelations = true,
        importerStandardFeatures = true,
        powerRolls = true,
        weaponProperties = true,
        currency = true,
        characterTypes = true,
        cultureAspects = true,
        nameGenerators = true,
    }

    -- Valid ongoing effect duration values for ApplyOngoingEffectBehavior.
    local g_validEffectDurations = {
        ["none"] = true,
        ["end_of_next_turn"] = true,
        ["eoe"] = true,
        ["save_ends"] = true,
        ["eoe_or_dying"] = true,
        ["endround"] = true,
        ["endnextround"] = true,
        ["until_rest"] = true,
        ["until_long_rest"] = true,
        ["momentary"] = true,
    }

    -- Derive the import directory path from the export infrastructure.
    -- Calls ExportTable on a small table to get the base compendium path,
    -- then replaces the tables subdirectory with import.
    local g_importBasePath = nil
    local function GetImportBasePath()
        if g_importBasePath ~= nil then
            return g_importBasePath
        end
        -- ExportTable returns {directory = "<basePath>/tables/<tableName>"}
        -- We need <basePath> without "/tables/<tableName>", then append "/import"
        local result = dmhub.ExportTable("damageTypes", {individualFiles = false})
        if result ~= nil and result.directory ~= nil then
            local dir = result.directory
            -- dir looks like ".../compendium/tables/damageTypes"
            -- Strip off "/tables/damageTypes" (or similar) to get ".../compendium"
            -- Then append "/import"
            local compendiumDir = string.match(dir, "^(.+)[/\\]tables[/\\]")
            if compendiumDir then
                g_importBasePath = compendiumDir .. "/import/"
                return g_importBasePath
            end
        end
        return nil
    end

    -- Read a YAML file from compendium/import/ and return its text content.
    local function ReadImportFile(filename)
        local basePath = GetImportBasePath()
        if basePath == nil then
            return nil, "Could not determine import directory path"
        end
        local fullPath = basePath .. filename
        local text = nil
        local readErr = nil
        text = dmhub.ReadTextFile(fullPath, function(err)
            readErr = err
        end)
        if text == nil then
            return nil, readErr or string.format("File not found: %s", filename)
        end
        return text, nil
    end

    -- Validate a single YAML file's text content.
    -- Returns errors (list of strings) and warnings (list of strings).
    local function ValidateYamlText(text, filename)
        local errors = {}
        local warnings = {}

        -- Helper to add an error
        local function err(msg)
            errors[#errors+1] = string.format("[%s] %s", filename, msg)
        end
        local function warn(msg)
            warnings[#warnings+1] = string.format("[%s] %s", filename, msg)
        end

        -- Check for non-ASCII characters
        local nonAsciiLine = nil
        local lineNum = 0
        for line in string.gmatch(text, "[^\n]*") do
            lineNum = lineNum + 1
            if string.find(line, "[\128-\255]") then
                nonAsciiLine = lineNum
                break
            end
        end
        if nonAsciiLine then
            err(string.format("Non-ASCII characters found on line %d (files must be ASCII-only)", nonAsciiLine))
        end

        -- Detect if this is a bundle file
        local isBundle = string.find(text, "^_bundle:") ~= nil or string.find(text, "\n_bundle:") ~= nil

        -- Check _table field values
        for tableName in string.gmatch(text, "_table:%s*([%w_]+)") do
            if not g_validTableNames[tableName] then
                -- Check for case-insensitive match to give a better error
                local suggestion = nil
                local lowerName = string.lower(tableName)
                for validName, _ in pairs(g_validTableNames) do
                    if string.lower(validName) == lowerName then
                        suggestion = validName
                        break
                    end
                end
                if suggestion then
                    err(string.format("Invalid table name '%s' - did you mean '%s'? (table names are case-sensitive)", tableName, suggestion))
                else
                    err(string.format("Unknown table name '%s' - check against known table names", tableName))
                end
            end
        end

        -- Check for CharacterOngoingEffect missing required fields
        if string.find(text, "CharacterOngoingEffect") then
            -- Check for missing iconid
            -- Look for entries that have __typeName: CharacterOngoingEffect
            -- In YAML, iconid should appear as a sibling field
            -- Simple heuristic: if CharacterOngoingEffect appears but no iconid in the file
            if not string.find(text, "iconid:") then
                err("CharacterOngoingEffect found but no 'iconid' field -- iconid is required (crashes if missing)")
            elseif string.find(text, "iconid:%s*$") or string.find(text, "iconid:%s*\n") then
                err("CharacterOngoingEffect has empty iconid -- iconid is required (crashes if missing)")
            end
            -- Check for iconid: null or iconid: nil
            if string.find(text, "iconid:%s*null") or string.find(text, "iconid:%s*nil") then
                err("CharacterOngoingEffect has null/nil iconid -- iconid is required (crashes if missing)")
            end
            -- Check for missing display table
            if not string.find(text, "display:") then
                err("CharacterOngoingEffect found but no 'display' table -- display is required")
            end
        end

        -- Check for CharacterCondition missing required fields
        if string.find(text, "__typeName:%s*CharacterCondition") then
            if not string.find(text, "iconid:") then
                err("CharacterCondition found but no 'iconid' field -- iconid is required")
            end
            if not string.find(text, "display:") then
                err("CharacterCondition found but no 'display' table -- display is required")
            end
            if not string.find(text, "domains:") then
                err("CharacterCondition found but no 'domains' field -- domains is required")
            end
        end

        -- Check for CharacterFeatureChoice missing allowDuplicateChoices
        if string.find(text, "CharacterFeatureChoice") then
            if not string.find(text, "allowDuplicateChoices") then
                err("CharacterFeatureChoice found but 'allowDuplicateChoices' is missing -- this field is REQUIRED (crashes if omitted)")
            end
        end

        -- Check for GoblinScript boolean pitfall: activationCondition: "true" or "false"
        if string.find(text, 'activationCondition:%s*"true"') then
            err('activationCondition: "true" found -- GoblinScript does not recognize "true", use "1" instead')
        end
        if string.find(text, 'activationCondition:%s*"false"') then
            err('activationCondition: "false" found -- GoblinScript does not recognize "false", use "0" instead')
        end

        -- Check for invalid duration values on ApplyOngoingEffectBehavior
        -- "nextturn" is aura-only, not valid for ongoing effect durations
        if string.find(text, "ActivatedAbilityApplyOngoingEffectBehavior") then
            if string.find(text, 'duration:%s*"?nextturn"?') then
                err('duration: "nextturn" is invalid for ApplyOngoingEffectBehavior -- use "end_of_next_turn" instead (nextturn is aura-only)')
            end
        end

        -- Check for stability attribute (common mistake)
        if string.find(text, "attribute:%s*stability") then
            warn("attribute: stability found -- 'stability' is not a valid attribute ID, use 'forcedmoveresistance' instead")
        end

        -- Check for empty roll on PowerRollBehavior
        if string.find(text, "ActivatedAbilityPowerRollBehavior") and string.find(text, "roll: ''") then
            err("ActivatedAbilityPowerRollBehavior has empty roll: '' -- must be a dice formula like '2d10 + Might or Agility'")
        end

        -- Check for targetType: enemies (invalid)
        if string.find(text, "targetType:%s*enemies") then
            err("targetType: enemies is not valid -- use targetType: target with targetAllegiance: enemy")
        end

        -- Check for missing id field on entries that need it
        -- For non-bundle files with __typeName, check for id
        if not isBundle then
            if string.find(text, "__typeName:") then
                if not string.find(text, "\nid:") and not string.find(text, "^id:") then
                    warn("Entry has __typeName but no top-level 'id' field -- most types require an id")
                end
            end
        end

        -- Check for missing guid on CharacterFeature
        if string.find(text, "__typeName:%s*CharacterFeature") then
            if not string.find(text, "guid:") then
                warn("CharacterFeature found but no 'guid' field anywhere -- guid is required on features")
            end
        end

        -- Check for missing guid on CharacterModifier
        if string.find(text, "__typeName:%s*CharacterModifier") then
            if not string.find(text, "behavior:") then
                warn("CharacterModifier found but no 'behavior' field -- behavior is required on modifiers")
            end
        end

        -- Check for Class missing levels
        if string.find(text, "__typeName:%s*Class") and string.find(text, "_table:%s*classes") then
            if not string.find(text, "levels:") then
                err("Class entry found but no 'levels' field -- levels is required on classes")
            end
        end

        -- Check for Kit missing type
        if string.find(text, "__typeName:%s*Kit") then
            if not string.find(text, "\ntype:") and not string.find(text, "^type:") then
                warn("Kit found but no 'type' field -- type is required (e.g. martial, caster)")
            end
        end

        -- Check for monster missing info.properties
        if string.find(text, "\ninfo:") or string.find(text, "^info:") then
            if not string.find(text, "properties:") then
                warn("Monster entry found (has 'info') but no 'properties' field inside info")
            end
        end

        -- Check for duplicate ids within the same file
        local ids = {}
        local duplicateIds = {}
        for id in string.gmatch(text, "\nid:%s*([%x%-]+)") do
            if ids[id] then
                if not duplicateIds[id] then
                    err(string.format("Duplicate id '%s' found in the same file", id))
                    duplicateIds[id] = true
                end
            else
                ids[id] = true
            end
        end
        -- Also check the first line
        local firstId = string.match(text, "^id:%s*([%x%-]+)")
        if firstId then
            if ids[firstId] then
                if not duplicateIds[firstId] then
                    err(string.format("Duplicate id '%s' found in the same file", firstId))
                end
            end
        end

        -- Check for empty id or guid fields
        if string.find(text, "\nid:%s*\n") or string.find(text, "\nid:%s*$") or string.find(text, "^id:%s*\n") then
            err("Empty 'id' field found -- id must be a non-empty string")
        end
        if string.find(text, "\nguid:%s*\n") or string.find(text, "\nguid:%s*$") then
            err("Empty 'guid' field found -- guid must be a non-empty string")
        end

        -- Check for _include references in bundles (verify the referenced files exist)
        if isBundle then
            local basePath = GetImportBasePath()
            if basePath then
                for includeFile in string.gmatch(text, "_include:%s*([%w%.%-_/]+)") do
                    local includePath = basePath .. includeFile
                    local includeText = dmhub.ReadTextFile(includePath, function() end)
                    if includeText == nil then
                        err(string.format("_include references '%s' but file not found", includeFile))
                    end
                end
            end
        end

        -- Check for complication/title/race/background missing modifierInfo
        if string.find(text, "__typeName:%s*CharacterComplication") then
            if not string.find(text, "modifierInfo:") then
                warn("CharacterComplication found but no 'modifierInfo' field -- modifierInfo is required")
            end
        end
        if string.find(text, "__typeName:%s*Title") then
            if not string.find(text, "modifierInfo:") then
                warn("Title found but no 'modifierInfo' field -- modifierInfo is required")
            end
        end
        if string.find(text, "__typeName:%s*Race") and string.find(text, "_table:%s*races") then
            if not string.find(text, "modifierInfo:") then
                warn("Race (ancestry) found but no 'modifierInfo' field -- modifierInfo is required")
            end
        end

        -- Check for equipment missing equipmentCategory
        if (string.find(text, "__typeName:%s*equipment") or string.find(text, "__typeName:%s*weapon") or string.find(text, "__typeName:%s*armor")) then
            if string.find(text, "_table:%s*tbl_Gear") then
                if not string.find(text, "equipmentCategory:") then
                    warn("Equipment entry found but no 'equipmentCategory' field")
                end
            end
        end

        return errors, warnings
    end

    -- Validate one or more files. Returns true if all pass, false if any errors.
    local function ValidateFiles(filenames)
        local allErrors = {}
        local allWarnings = {}
        local filesRead = 0

        for _, filename in ipairs(filenames) do
            local text, readErr = ReadImportFile(filename)
            if text == nil then
                allErrors[#allErrors+1] = string.format("[%s] %s", filename, readErr or "Could not read file")
            else
                filesRead = filesRead + 1
                local fileErrors, fileWarnings = ValidateYamlText(text, filename)
                for _, e in ipairs(fileErrors) do
                    allErrors[#allErrors+1] = e
                end
                for _, w in ipairs(fileWarnings) do
                    allWarnings[#allWarnings+1] = w
                end
            end
        end

        -- Report results
        for _, w in ipairs(allWarnings) do
            ValidateChatMessage(w, "warning")
        end
        for _, e in ipairs(allErrors) do
            ValidateChatMessage(e, "error")
        end

        if #allErrors == 0 and #allWarnings == 0 and filesRead > 0 then
            local fileStr = #filenames == 1 and filenames[1] or string.format("%d files", filesRead)
            ValidateChatMessage(string.format("Validation passed for %s -- no issues found", fileStr), "success")
        elseif filesRead > 0 then
            ValidateChatMessage(string.format("Validation: %d error(s), %d warning(s) in %d file(s)", #allErrors, #allWarnings, filesRead), #allErrors > 0 and "error" or "warning")
        end

        return #allErrors == 0
    end

    Commands.RegisterMacro{
        name = "validate",
        summary = "validate YAML import files before importing",
        doc = "Usage: /validate <filename> [filename2 ...]\nValidates one or more YAML files from the compendium/import/ directory without importing them. Checks for common errors: invalid table names, missing required fields, GoblinScript pitfalls, non-ASCII characters, duplicate ids, and more.\n\nExamples:\n  /validate elf-warrior.yaml\n  /validate outlaw.yaml mundane.yaml\n  /validate complications-all.yaml",
        command = function(str)
            str = string.gsub(str, "^%s+", "")
            str = string.gsub(str, "%s+$", "")
            if str == "" then
                ValidateChatMessage("Usage: /validate <filename> [filename2 ...]", "info")
                return
            end

            local files = {}
            for word in string.gmatch(str, "%S+") do
                files[#files+1] = word
            end

            ValidateFiles(files)
        end,
    }

    Commands.RegisterMacro{
        name = "import",
        summary = "import YAML files from compendium/import/",
        doc = "Usage: /import <filename> [filename2 ...]\nImports one or more YAML files from the compendium/import/ directory. Runs validation first and refuses to import if errors are found. Each file can contain a monster, a table entry (with _table metadata), or a bundle of multiple items (with _bundle). Bundles support _include directives to reference other YAML files.\n\nExamples:\n  /import elf-warrior.yaml\n  /import outlaw.yaml mundane.yaml vow-of-duty.yaml\n  /import complications-all.yaml",
        command = function(str)
            str = string.gsub(str, "^%s+", "")
            str = string.gsub(str, "%s+$", "")
            if str == "" then
                ImportChatMessage("Usage: /import <filename> [filename2 ...]", true)
                return
            end

            local files = {}
            for word in string.gmatch(str, "%S+") do
                files[#files+1] = word
            end

            -- Run validation first
            local valid = ValidateFiles(files)
            if not valid then
                ImportChatMessage("Import aborted -- fix validation errors above and retry", true)
                return
            end

            local totalMonsters = 0
            local totalItems = 0
            local totalErrors = {}
            local filesProcessed = 0

            for _, filename in ipairs(files) do
                local result = dmhub.ImportFile(filename)
                if result == nil then
                    totalErrors[#totalErrors+1] = string.format("Failed to resolve: %s", filename)
                else
                    totalMonsters = totalMonsters + (result.monstersImported or 0)
                    totalItems = totalItems + (result.itemsImported or 0)
                    filesProcessed = filesProcessed + 1
                    for _, err in ipairs(result.errors or {}) do
                        totalErrors[#totalErrors+1] = tostring(err)
                    end
                end
            end

            local parts = {}
            if totalMonsters > 0 then
                parts[#parts+1] = string.format("%d monster(s)", totalMonsters)
            end
            if totalItems > 0 then
                parts[#parts+1] = string.format("%d table item(s)", totalItems)
            end

            if #parts > 0 then
                local fileStr = #files == 1 and files[1] or string.format("%d files", filesProcessed)
                ImportChatMessage(string.format("Imported %s from %s", table.concat(parts, ", "), fileStr), false)
            else
                ImportChatMessage(string.format("No items imported from %s", str), true)
            end

            for _, err in ipairs(totalErrors) do
                ImportChatMessage(err, true)
            end
        end,
    }
end

Commands.RegisterMacro{
    name = "settingid",
    summary = "look up a setting's id by name",
    doc = "Usage: /settingid <setting name>\nSearches the settings menu for a setting matching the given name and prints its id.",
    completions = settingCompletions,
    command = function(str)
        local needle = string.lower(str)
        local matches = {}
        for id, info in pairs(Settings) do
            local desc = info.description or ""
            if string.lower(desc) == needle then
                matches[#matches+1] = {id = id, desc = desc, exact = true}
            elseif string.find(string.lower(desc), needle, 1, true) then
                matches[#matches+1] = {id = id, desc = desc, exact = false}
            end
        end

        if #matches == 0 then
            dmhub.Log("No setting found matching: " .. str)
            return
        end

        -- Prefer exact matches
        table.sort(matches, function(a, b)
            if a.exact ~= b.exact then return a.exact end
            return a.desc < b.desc
        end)

        for _, m in ipairs(matches) do
            dmhub.Log(string.format('"%s"  -->  id: %s', m.desc, m.id))
        end
    end,
}

Commands.RegisterMacro{
    name = "opensheet",
    summary = "Open Character Sheet",
    doc = "Usage: /opensheet\nOpens the character sheet. Opens specific tab, when given",
    command = function(str)
        print("Opening character sheet...", str)
        local selected = dmhub.selectedTokens
        if #selected == 0 then
            return
        end

        local token = selected[1]
        if token.properties == nil then
            return
        end

        token:ShowSheet(str)
    end,
}

Commands.RegisterMacro{
    name = "setportrait",
    summary = "set selected token's portrait id",
    doc = "Usage: /setportrait <portraitid>\nSets the portraitid on selected tokens. Testing aid for spine animation wiring, e.g. /setportrait anim:lightbender.",
    command = function(str)
        str = str or ""

        local tokens = dmhub.selectedOrPrimaryTokens
        if #tokens == 0 then
            print("/setportrait: no token selected.")
            return
        end

        for _, token in ipairs(tokens) do
            local snapshot = token:PrepareUploadAppearance()
            token.portrait = str
            token:UploadAppearance(snapshot)
            token:RefreshAppearanceLocally()
        end
    end,
}


spine.register{
    id = "lightbender-small",
    model = "lightbender",

    -- World rendering: how the spine character is placed on top of the token quad.
    scale = 0.038,           -- multiplier on the spine renderer's localScale.
    xoffset = 0,             -- world-space X offset of the spine renderer from the token center.
    yoffset = -0.28,         -- world-space Y offset of the spine renderer from the token center.
    bottomClip = 100,         -- degrees of the bottom arc (centered on -90 deg) where spine is
                             -- forced inside the frame; rest of the circle is the popout zone.

    -- Portrait camera framing (used by the '#spine:tokenid' image lookup).
    portraitZoom = 2,        -- >1 zooms the portrait camera in, <1 zooms it out.
    portraitXOffset = 0,     -- world-space X offset added to the portrait camera's position.
    portraitYOffset = 0.8,     -- world-space Y offset added to the portrait camera's position.

    -- Inspect / up-close portrait framing (used by the '#spineinspect:tokenid' image
    -- lookup, exposed via CharacterToken.inspectPortrait). Independent from portrait*.
    inspectZoom = 0.5,
    inspectXOffset = 0,
    inspectYOffset = 0.6,

    -- Eye / head IK: drive the named controller bone toward the token's lookAt position
    -- each frame. eyeMult scales the offset between the animation pose and the look-at
    -- target (1 = follow exactly, 0 = ignore); eyeRange is the maximum deviation magnitude
    -- in spine local / parent-bone-local units (a circular window around the anim pose).
    eyeik = "bLB_head_CON",
    eyeMult = 1.0,
    eyeRange = 6.3,

    -- Called at the end of CharacterToken.RefreshLua() for every token using this entry.
    -- Decides which animation should be playing based on the token's current state.
    refresh = function(token)
        print("TOKENREFRESH:: REFRESHING")
        local summonerRampage = false
        local summonerid = token.summonerid
        if summonerid ~= nil then
            local summoner = dmhub.GetCharacterById(summonerid)
            if summoner ~= nil and summoner.properties ~= nil then
                summonerRampage = summoner.properties:GetUnboundedResourceQuantity(CharacterResource.rampageId) >= 8
            end
        end
        if summonerRampage then
            token:SetSpineSkin("base")
            token:SetSpineAnimation{ id = "3_RAMPAGE_idle" }
            token:SetSpineIdleFidgets{}
        elseif token.properties:IsWinded() then
            token:SetSpineSkin("winded")
            token:SetSpineAnimation{ id = "2_WINDED_idle" }
            token:SetSpineIdleFidgets{}
        else
            token:SetSpineSkin("base")
            token:SetSpineAnimation{ id = "1_BASE_idle" }
            token:SetSpineIdleFidgets{
                animations = {"1_BASE_fidget1", "1_BASE_fidget2"},
                period = 20,
            }
        end
    end,
}

spine.register{
    id = "lightbender-big",
    model = "lightbender",

    -- World rendering: how the spine character is placed on top of the token quad.
    scale = 0.066,           -- multiplier on the spine renderer's localScale.
    xoffset = 0,             -- world-space X offset of the spine renderer from the token center.
    yoffset = -0.75,         -- world-space Y offset of the spine renderer from the token center.
    bottomClip = 140,         -- degrees of the bottom arc (centered on -90 deg) where spine is
                             -- forced inside the frame; rest of the circle is the popout zone.

    -- Per-segment layer transforms along the spine's draw order. Each entry covers a
    -- contiguous range of slots starting at slots[1] (the cut point); the first entry
    -- implicitly starts at the skeleton's first drawn slot. xoffset/yoffset are in
    -- token-local units (same as the registry's xoffset/yoffset) and scale is a multiplier
    -- (1 = same size as the parent spine). Set frame=true on the entry that begins the
    -- in-front-of-frame range -- entries before it draw BEHIND the token frame, that entry
    -- and after draw IN FRONT.
    transforms = {
        -- podium, light2_glow, light1_glow -> behind frame at identity (no parallax shift).
        { xoffset = 0.0, yoffset = 0.0, scale = 1.0 },
        -- tail_1, tail_2 -> behind frame, shifted up for parallax depth. bottomClip = 0
        -- exempts the tail from the bottom-arc spine suppression so the tail can extend
        -- below the frame without being clipped.
        { slots = {"tail_1"}, xoffset = 0.2, yoffset = 0.45, scale = 1.0, bottomClip = 0 },
        -- "legs_bgbutt" and after -> in front of the frame at identity.
        { slots = {"legs_bgbutt"}, }, -- frame = true },
    },

    -- Portrait camera framing (used by the '#spine:tokenid' image lookup).
    portraitZoom = 1.2,        -- >1 zooms the portrait camera in, <1 zooms it out.
    portraitXOffset = 0,     -- world-space X offset added to the portrait camera's position.
    portraitYOffset = 1.2,     -- world-space Y offset added to the portrait camera's position.

    -- Inspect / up-close portrait framing (used by the '#spineinspect:tokenid' image
    -- lookup, exposed via CharacterToken.inspectPortrait). Independent from portrait*.
    inspectZoom = 0.5,
    inspectXOffset = 0,
    inspectYOffset = 0.6,

    -- Eye / head IK: drive the named controller bone toward the token's lookAt position
    -- each frame. eyeMult scales the offset between the animation pose and the look-at
    -- target (1 = follow exactly, 0 = ignore); eyeRange is the maximum deviation magnitude
    -- in spine local / parent-bone-local units (a circular window around the anim pose).
    eyeik = "bLB_head_CON",
    eyeMult = 0.5,
    eyeRange = 3.3,

    -- Called at the end of CharacterToken.RefreshLua() for every token using this entry.
    -- Decides which animation should be playing based on the token's current state.
    refresh = function(token)
        print("TOKENREFRESH:: REFRESHING")
        local summonerRampage = token.properties:GetUnboundedResourceQuantity(CharacterResource.rampageId) >= 8

        if summonerRampage then
            token:SetSpineSkin("base")
            token:SetSpineAnimation{ id = "3_RAMPAGE_idle" }
            token:SetSpineIdleFidgets{}
        elseif token.properties:IsWinded() then
            token:SetSpineSkin("winded")
            token:SetSpineAnimation{ id = "2_WINDED_idle" }
            token:SetSpineIdleFidgets{}
        else
            token:SetSpineSkin("base")
            token:SetSpineAnimation{ id = "1_BASE_idle" }
            token:SetSpineIdleFidgets{
                animations = {"1_BASE_fidget1", "1_BASE_fidget2"},
                period = 20,
            }
        end
    end,
}
