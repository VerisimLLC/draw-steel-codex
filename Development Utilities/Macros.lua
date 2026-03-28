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
        g_checkpoint:Restore()
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