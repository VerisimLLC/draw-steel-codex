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
                token.properties.attributes = "this-should-be-rejected"
            end,
        }
        chat.Send("corrupttest: uploaded. expected server log: [SCHEMA-GUARD] patch rejected ... attributes: expected map, got string")
        chat.Send("corrupttest: local cache may briefly show the bad value; reload the sheet to confirm the server kept the good one.")
    end,
}