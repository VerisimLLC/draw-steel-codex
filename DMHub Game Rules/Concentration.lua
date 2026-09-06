local mod = dmhub.GetModLoading()

--This file implements some basic rules and utilities for how concentration works. Most concentration-related
--code is inside the Creature file though.

--- @class Concentration: GameType
--- @field name string Name of the spell or ability being concentrated on.
--- @field duration number Duration in rounds.
--- @field time table Timestamp object used to compute rounds elapsed.
--- Tracks an active concentration effect on a creature. Stored in `creature.concentration`.
Concentration = RegisterGameType("Concentration")
function Concentration:HasExpired()
	return self:has_key("duration") and self.time:RoundsSince() >= self.duration
end

function Concentration:CreateTooltip(creature)

	local roundsSince = self.time:RoundsSince()
	local castTimeText = "this round"
	if roundsSince == 1 then
		castTimeText = "last round"
	elseif roundsSince > 1 then
		castTimeText = string.format("%d rounds ago", math.floor(roundsSince))
	end

	local remainingRounds = self.duration - roundsSince
	local expiresText = "this round"
	if remainingRounds == 1 then
		expiresText = "next round"
	elseif remainingRounds > 1 then
		expiresText = string.format("in %d rounds", math.floor(remainingRounds))
	end

	
	
	
	return gui.Panel{
		styles = SpellRenderStyles,
		id = "spellInfo",
		pad = 12,
		bgimage = 'panels/square.png',
		bgcolor = 'black',
		borderWidth = 2,
		borderColor = 'white',
		width = 400,

		gui.Label{
			id = "spellName",
			text = string.format("Concentrating on %s", self:try_get("name", "Spell")),
		},
		
		gui.Label{
			id = "auraInfo",
			text = string.format("Cast %s, expires %s.", castTimeText, expiresText)
		},
	}
end
