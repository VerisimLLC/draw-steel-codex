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

creature.RegisterSymbol{
    symbol = "complications",
    help = {
        name = "Complications",
        type = "set",
        desc = "The names of complications this hero has. Empty for monsters and heroes with no complication.",
        seealso = {},
        examples = {
            'Complications has "Primordial Sickness"',
        },
    },

    lookup = function(c)
        local result = {}
        local complicationIds = c:try_get("complications", {})
        local complicationsTable = dmhub.GetTable(CharacterComplication.tableName) or {}
        for id, _ in pairs(complicationIds) do
            local complication = complicationsTable[id]
            if complication ~= nil then
                result[#result+1] = complication.name
            end
        end
        return StringSet.new{
            strings = result,
        }
    end,
}

creature.RegisterSymbol{
    symbol = "getpointsspent",
    help = {
        name = "GetPointsSpent",
        type = "function",
        desc = "Given the name of a points pool, returns how many points of that type have been spent building this creature. Points pools are named on feature choices that cost points; choices left unnamed belong to the default pool called \"Points\". Returns zero for unknown pool names.",
        seealso = {},
        examples = {
            'GetPointsSpent("Points")',
            'GetPointsSpent("Animal Traits Points")',
        },
    },

    lookup = function(c)
        return function(pointsName)
            return c:GetPointsSpentByName(pointsName)
        end
    end,
}

----------------------------------------------------------------------
-- Portent Affinity Type (custom attribute + GoblinScript symbol)
----------------------------------------------------------------------

PORTENT_AFFINITY_ATTRIBUTE_ID = "e8a6cced-9eca-43a2-9fc9-4298167044dd"

--Returns the creature's chosen Portent affinity as a lowercase damage-type
--keyword ("acid" / "cold" / "corruption" / "lightning" / "poison" / "fire"),
--defaulting to "acid" when unset. 
function creature:PortentAffinityType()
    local rec = CustomAttribute.attributeInfoById and CustomAttribute.attributeInfoById[PORTENT_AFFINITY_ATTRIBUTE_ID]
    if rec == nil then
        return "acid"
    end
    local attrInfo = rec.attr or rec
    if attrInfo == nil or type(attrInfo.CalculateBaseValue) ~= "function" then
        return "acid"
    end

    local value = self:GetCustomAttribute(attrInfo)
    if type(value) == "string" and value ~= "" then
        return string.lower(value)
    end
    if type(value) == "table" then
        --StringSet shape: { strings = { "Acid" } }
        local strings = rawget(value, "strings")
        if type(strings) == "table" and strings[1] ~= nil and tostring(strings[1]) ~= "" then
            return string.lower(tostring(strings[1]))
        end
    end
    return "acid"
end

RegisterGoblinScriptSymbol(creature, {
	name = "Affinity Type",
	type = "text",
	desc = "The Creature's Chosen Affinity",
	examples = {'Affinity Type = "acid"'},
	calculate = function(c)
        return c:PortentAffinityType()
	end,
})
