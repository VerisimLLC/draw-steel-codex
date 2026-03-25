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


--end combat command.
Commands.Register{
	name = "End Combat",
    identifier = "endcombat",
    execute = function()
		if dmhub.initiativeQueue ~= nil then
			UploadDayNightInfo()
			dmhub.initiativeQueue.hidden = true
			dmhub.initiativeQueue.gameMode = "exploration"
			dmhub:UploadInitiativeQueue()

            CharacterResource.SetMalice(0, "End of Combat")

			for initiativeid,_ in pairs(dmhub.initiativeQueue.entries) do
				local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, initiativeid)
				for _,tok in ipairs(tokens) do
                    tok.properties:EndCombat()
					tok.properties:DispatchEvent("endcombat", {})
				end
			end
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
