local mod = dmhub.GetModLoading()

--rename rollinitiative command to "Draw Steel!"
Commands.Register{
	name = "Draw Steel!",
    identifier = "rollinitiative",
	command = "rollinitiative",
	dmonly = true,
	icon = "panels/initiative/initiative-icon.png",
    menu = "game",
    filtered = function()
        local q = dmhub.initiativeQueue

        --already in combat.
        return q ~= nil and (not q.hidden)
    end,
}

Commands.Register{
	name = "Add Selection to Combat",
    identifier = "addselectiontombat",
    execute = function()
        Commands.rollinitiative()
    end,
	dmonly = true,
	icon = "panels/initiative/initiative-icon.png",
    menu = "game",
    filtered = function()
        local q = dmhub.initiativeQueue

        --not in combat or no selected tokens.
        return q == nil or q.hidden or dmhub.selectedTokens == nil or #dmhub.selectedTokens == 0
    end,
}


--end combat command. Routes through the initiative bar's confirmation dialog
--(Victory Screen / no victory / cancel) instead of ending combat immediately.
--MCDMInitiativeBar.lua loads after this file, so the export is resolved at
--click time via rawget.
Commands.Register{
	name = "End Combat",
    identifier = "endcombat",
    execute = function()
		if dmhub.initiativeQueue == nil then
			return
		end
		local prompt = rawget(_G, "g_drawSteelPromptEndCombat")
		if prompt ~= nil then
			prompt()
		end
    end,
	dmonly = true,
	icon = "panels/initiative/initiative-icon.png",
    menu = "game",
    filtered = function()
        local q = dmhub.initiativeQueue

        --not in combat.
        return q == nil or q.hidden
    end,
}
