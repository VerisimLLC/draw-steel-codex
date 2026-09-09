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

----------------------------------------------------------------------
-- Troubadour Melodrama boosted events (GoblinScript symbol)
----------------------------------------------------------------------

--guid of the Melodrama "No Selection" option itself: since it was
--converted from a plain CharacterFeature to a CharacterFeatureChoice,
--its own guid doubles as the key for its nested "which event do you
--already have?" sub-choice in a character's levelChoices table.
local g_melodramaBoostChoiceGuid = "d6a06311-3888-4df0-83e3-8febf6993f2b"

--maps each boost sub-option's guid to the stable key used in the
--matching event's "gain drama" quantity formula (e.g. `... has "natural-2"`).
--Covers both the 5 Melodrama-choice events and the 6 base-class events
--every Troubadour already has (Start of Combat, Start of Turn, etc) --
--the rules text lets you boost "one event you already have", not just
--one gained from this specific feature.
--Keep these two lists in sync if Melodrama's events are ever added to/changed.
local g_melodramaBoostOptionKeys = {
    ["7001fd80-0a4b-42db-96d5-94f2b187e195"] = "natural-2",
    ["c2159366-09e7-47e8-99e6-b08b0009c53f"] = "villain-malice-damage",
    ["605a6c7a-bbc6-4d30-aa38-b8957addf6f5"] = "falls-5-squares",
    ["c5628da4-d87e-4e3a-82d7-a795279fcaf5"] = "3-surges-damage",
    ["5c313cc2-1598-4edc-a14c-a2cce9ade1cc"] = "last-recovery",
    ["824db305-fdf0-45d0-add0-5bde8e0b42c7"] = "start-of-combat",
    ["46ba9e52-22b5-46fb-b961-0bc45e6b551f"] = "start-of-turn",
    ["df8e9f81-c603-4435-8a1f-9d28ff4ef567"] = "3-heroes-ability",
    ["4c7ec3a6-6163-4405-967d-4f8c623be15d"] = "hero-winded",
    ["574e7ef4-4287-41b1-9cf8-84ce78d67f68"] = "natural-19-20",
    ["42f018c0-ab59-4df5-8f57-80f74cde2317"] = "hero-dies",
}

RegisterGoblinScriptSymbol(creature, {
	name = "MelodramaBoostedEvents",
	type = "set",
	desc = "Stable keys of the Troubadour Melodrama events this hero chose to boost (gain 1 additional drama) via the 'No Selection' option, instead of taking a new event.",
	examples = {'MelodramaBoostedEvents has "natural-2"'},
	calculate = function(c)
        if not c:IsHero() then
            return StringSet.new{}
        end

        local choiceidList = c:GetLevelChoices()[g_melodramaBoostChoiceGuid]
        local strings = {}
        if choiceidList ~= nil then
            for _,choiceid in ipairs(choiceidList) do
                local key = g_melodramaBoostOptionKeys[choiceid]
                if key ~= nil then
                    strings[#strings+1] = key
                end
            end
        end

        return StringSet.new{
			strings = strings,
		}
	end,
})

--guid of the top-level Melodrama choice itself (the "choose two events"
--picker that "No Selection" is one option of).
local g_melodramaChoiceGuid = "6848dff3-4931-413d-ac0a-87d85b9f7138"

--maps each real event option's own guid to the same stable keys used
--above, so a boost sub-option's prerequisite can check "did I actually
--pick this event as one of my two selections?"
local g_melodramaEventOptionKeys = {
    ["61e4e1d7-2389-4c0a-abeb-5ec542ba9148"] = "natural-2",
    ["7e0ca04f-f1ea-446c-9939-28daba51f7a5"] = "villain-malice-damage",
    ["6436c956-cd85-44d5-8382-be3cc445b7da"] = "falls-5-squares",
    ["a0b677d6-ad39-4d9e-9641-d0b525185597"] = "3-surges-damage",
    ["fe57c0eb-365f-469c-a293-692367debfee"] = "last-recovery",
}

RegisterGoblinScriptSymbol(creature, {
	name = "MelodramaKnownEvents",
	type = "set",
	desc = "Stable keys of the Troubadour Melodrama events this hero has actually chosen (as one of their two Melodrama selections). Used to gate the 'No Selection' boost options to events the hero already has.",
	examples = {'MelodramaKnownEvents has "natural-2"'},
	calculate = function(c)
        if not c:IsHero() then
            return StringSet.new{}
        end

        local choiceidList = c:GetLevelChoices()[g_melodramaChoiceGuid]
        local strings = {}
        if choiceidList ~= nil then
            for _,choiceid in ipairs(choiceidList) do
                local key = g_melodramaEventOptionKeys[choiceid]
                if key ~= nil then
                    strings[#strings+1] = key
                end
            end
        end

        return StringSet.new{
			strings = strings,
		}
	end,
})
