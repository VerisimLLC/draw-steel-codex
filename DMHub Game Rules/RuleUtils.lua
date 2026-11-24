local mod = dmhub.GetModLoading()

GameRules = {}


function GameRules.TokenIncapacitated(token)
	if token.properties == nil then
		return false
	end

	return token.properties:CurrentHitpoints() <= 0
end

function GameRules.TokenNearEnemies(token)
	local nearbyTokens = token:GetNearbyTokens()
	for i,nearby in ipairs(nearbyTokens) do
		--Allegiance, not just sides: a creature under Guise isn't an enemy here.
		if nearby.properties ~= creature and IsEnemyOf(token, nearby) and (not GameRules.TokenIncapacitated(nearby)) then
			return true
		end
	end

	return false
end
