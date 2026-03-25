local mod = dmhub.GetModLoading()

creature.RegisterSymbol{
    symbol = "adjacentallieswithfeature",
    help = {
        name = "AdjacentAlliesWithFeature",
        type = "function",
        desc = "Given the name of a feature, returns the number of adjacent allies with this feature.",
        seealso = {},
    },

    lookup = function(c)
        return function(featurename)
			local token = dmhub.LookupToken(c)
			if token == nil then
				return 0
			end


			local count = 0
			local nearbyTokens = token:GetNearbyTokens(1)
			for i,nearby in ipairs(nearbyTokens) do
				if nearby:IsFriend(token) and (not nearby.properties:IsDownCached()) then
                    local features = nearby.properties:try_get("characterFeatures", {})
                    for _,feature in ipairs(features) do
                        if string.lower(feature.name) == string.lower(featurename) then
                            count = count+1
                        end
                    end
				end
			end

            return count
        end
    end,

}

creature.RegisterSymbol{
    symbol = "victories",
    help = {
        name = "Victories",
        type = "number",
        desc = "The number of victories the hero has. Zero for non-heroes.",
        seealso = {},
    },

    lookup = function(c)
        return c:GetVictoriesWithBonus()
    end
}

--symbols
