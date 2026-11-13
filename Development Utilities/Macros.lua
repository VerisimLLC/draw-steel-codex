local mod = dmhub.GetModLoading()

local g_checkpoint = nil

Commands.RegisterMacro{
    name = "checkpoint",
    summary = "save combat state",
    doc = "Usage: /checkpoint\nSaves a combat checkpoint that can be restored with /restorecheckpoint.",
    command = function(str)
        g_checkpoint = backup.CreateCombatCheckpoint()
    end,
}

Commands.RegisterMacro{
    name = "restorecheckpoint",
    summary = "restore combat state",
    doc = "Usage: /restorecheckpoint\nRestores the combat state saved by /checkpoint.",
    command = function(str)
        if g_checkpoint == nil then
            print("No checkpoint to restore")
            return
        end

        print("Checkpoint: restoring...")
        local err = g_checkpoint:Restore()
        if err ~= nil then
            print("Checkpoint: not restored: " .. err)
        end
    end,
}

Commands.RegisterMacro{
    name = "despawn",
    summary = "despawn selected tokens",
    doc = "Usage: /despawn\nDespawns all currently selected tokens.",
    command = function(str)
        local selected = dmhub.selectedTokens
        for _,tok in ipairs(selected) do
            tok.despawned = true
        end

        print("Despawned tokens:", dmhub.despawnedTokensCount)
    end,
}

Commands.RegisterMacro{
    name = "recovercompendium",
    summary = "recover from backup",
    doc = "Usage: /recovercompendium\nRecovers compendium data from a backup JSON file.",
    command = function(str)
        print("RECOVER::", str)
        local data = dmhub.ParseJsonFile("c:\\Users\\davew\\Downloads\\gertz-backup.json")
        print("RECOVER::", data.assets.objectTables)
        local objectTables = data.assets.objectTables
        dmhub.Coroutine(function()
            for tableName,tableInfo in pairs(objectTables) do
                for k,v in unhidden_pairs(tableInfo.table) do
                    print("RECOVER:: Uploading", tableName, k, rawget(v, "name"))
                    dmhub.SetAndUploadTableItem(tableName, v, {deferUpload = true})
                    local t = dmhub.Time()
                    while dmhub.Time() < t + 1 do
                        coroutine.yield(1)
                    end
                end
            end
        end)
    end,
}

Commands.RegisterMacro{
    name = "skillfind",
    summary = "find skill by name",
    doc = "Usage: /skillfind <name>\nLooks up a skill by name and prints it.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local skills = dmhub.GetTable("Skills")
        local result = {}
        for k, v in unhidden_pairs(skills) do
            result[#result+1] = v.name
        end
        table.sort(result)
        return result
    end,
    command = function(str)
        local s = Skill.FindByName(str)
        print("SKILL::", s)
    end,
}

Commands.RegisterMacro{
    name = "showtriggers",
    summary = "show token triggers",
    doc = "Usage: /showtriggers <event name>\nPrints all active triggered modifiers matching the given event name on selected tokens.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        return {"damaged", "attack", "attacked", "kill", "power_roll", "forced_move", "start_turn", "end_turn", "spend_recovery", "gain_condition", "lose_condition", "dying"}
    end,
    command = function(str)
        local tokens = dmhub.selectedTokens
        for _,tok in ipairs(tokens) do
            print("TRIGGERS:: TRIGGERS named", str, "for", tok.name)

            local mods = tok.properties:GetActiveModifiers()
            for i,mod in ipairs(mods) do
                if mod.mod:HasTriggeredEvent(tok.properties, str) then
                    print("TRIGGERS::   Mod", json(mod))
                end
            end

        end
    end,
}

Commands.RegisterMacro{
    name = "corrupttest",
    summary = "schema-guard smoke test",
    doc = "Usage: /corrupttest\nOverwrites the selected token's `attributes` field with a scalar string, which is a STRUCTURAL schema violation (attributes is annotated table<string, CharacterAttribute>). The DO staging server's schema guard should reject this write outright. Primitive-type mismatches are only warnings in v1, so this macro deliberately triggers a shape mismatch to exercise the reject path. Watch `wrangler tail --env staging` for [SCHEMA-GUARD] lines. Game must be hosted on DO staging.",
    command = function(str)
        local token = dmhub.selectedOrPrimaryTokens[1]
        if token == nil or token.properties == nil then
            chat.Send("corrupttest: no selected token with properties")
            return
        end
        chat.Send("corrupttest: overwriting attributes with a string (structural violation, should be rejected)...")
        token:ModifyProperties{
            description = "schema-guard test: bad attributes shape",
            undoable = false,
            execute = function()
                --the wrong type is the point: this write must trip the server's schema guard.
                ---@diagnostic disable-next-line: assign-type-mismatch
                token.properties.attributes = "this-should-be-rejected"
            end,
        }
        chat.Send("corrupttest: uploaded. expected server log: [SCHEMA-GUARD] patch rejected ... attributes: expected map, got string")
        chat.Send("corrupttest: local cache may briefly show the bad value; reload the sheet to confirm the server kept the good one.")
    end,
}
--Discord account link + voice chat prototype (DiscordControllerVoice.cs, DISCORD_REFERENCE.md).
local function DiscordStatusText()
    local s = dmhub.discordStatus
    local lines = {}
    lines[#lines+1] = "Discord account: " .. s.account .. (s.displayName ~= nil and (" (" .. s.displayName .. ")") or "")
    if s.accountError ~= nil then
        lines[#lines+1] = "  " .. s.accountError
    end
    lines[#lines+1] = "Voice: " .. s.voice .. (s.muted and " (muted)" or "")
    if s.voiceError ~= nil then
        lines[#lines+1] = "  " .. s.voiceError
    end
    for _,p in ipairs(s.participants) do
        lines[#lines+1] = "  " .. p.name .. (p.speaking and " (speaking)" or "")
    end
    return table.concat(lines, "\n")
end

Commands.RegisterMacro{
    name = "discord",
    summary = "Discord link and voice (prototype)",
    doc = "Usage: /discord [status|link|unlink|join|leave|mute|unmute]\nPrototype of Discord voice chat. link signs in to Discord (once per machine); join joins this game's voice call; leaving the game leaves it.",
    command = function(str)
        local arg = string.lower(string.match(str or "", "^%s*(%S*)") or "")
        if arg == "" or arg == "status" then
            dmhub.Log(DiscordStatusText())
        elseif arg == "link" then
            if dmhub.DiscordLink() then
                dmhub.Log("Discord: approve Codex in the Discord window that opened, then run /discord status.")
            else
                dmhub.Log("Discord: cannot start linking.\n" .. DiscordStatusText())
            end
        elseif arg == "unlink" then
            dmhub.DiscordUnlink()
            dmhub.Log("Discord: unlinked.")
        elseif arg == "join" then
            local err = dmhub.DiscordJoinVoice()
            dmhub.Log(err ~= nil and ("Discord: " .. err) or "Discord: joining voice...")
        elseif arg == "leave" then
            dmhub.DiscordLeaveVoice()
            dmhub.Log("Discord: left voice.")
        elseif arg == "mute" or arg == "unmute" then
            dmhub.DiscordSetVoiceMuted(arg == "mute")
            dmhub.Log("Discord: " .. (arg == "mute" and "muted." or "unmuted."))
        else
            dmhub.Log("Usage: /discord [status|link|unlink|join|leave|mute|unmute]")
        end
    end,
}
