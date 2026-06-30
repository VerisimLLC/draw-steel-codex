local mod = dmhub.GetModLoading()

--- @class EncounterRuleSet
--- @field name string Display name of the encounter (e.g. "Volcano").
--- @field tableName string Data table of encounter rule sets ("encounterRuleSets").
--- @field rulesTableName string Data table holding the rules themselves ("encounterRuleMods").
--- A named set of encounter rules. Each set is one entry in the "encounterRuleSets" table. The
--- rules belonging to a set are GlobalRuleMod objects stored in the flat "encounterRuleMods"
--- table, grouped by their encounterId field matching this set's id. Encounter rules behave just
--- like global rules, except they are only meant to be active while their encounter is active (a
--- future phase; for now this only supports authoring them in the compendium).
EncounterRuleSet = RegisterGameType("EncounterRuleSet")

EncounterRuleSet.tableName = "encounterRuleSets"
EncounterRuleSet.rulesTableName = "encounterRuleMods"

EncounterRuleSet.name = "New Encounter"

function EncounterRuleSet.CreateNew(name)
	return EncounterRuleSet.new{
		name = name,
	}
end

--Returns the flat list of rule mods currently in effect, to be applied to creatures in exactly the
--same way as global rules. That is always every global rule (the GlobalRuleMod.TableName table),
--plus -- when an encounter is live in the current map's initiative queue -- every encounter rule
--belonging to a rule-set attached to that live encounter. Encounter rules are ordinary
--GlobalRuleMod objects stored in EncounterRuleSet.rulesTableName, grouped by encounterId, so
--callers can treat every returned entry uniformly (same fields, same FillClassFeatures, etc.).
function GlobalRuleMod.GetActiveRuleMods()
	local result = {}

	for _, ruleMod in pairs(GetTableCached(GlobalRuleMod.TableName) or {}) do
		result[#result + 1] = ruleMod
	end

	--A live encounter is a deep copy of the authored Encounter, so its attached rule-sets ride
	--along in its ruleSets field (a set of EncounterRuleSet ids). Read defensively: liveEncounter
	--can be false, nil, or a table. The initiative queue persists (with hidden=true) after combat
	--ends, so gate on "not hidden" -- the canonical "combat is active" test -- or the encounter
	--rules would keep applying once the fight is over.
	local queue = dmhub.initiativeQueue
	local liveEncounter = queue ~= nil and (not queue.hidden) and queue:try_get("liveEncounter")
	if type(liveEncounter) == "table" then
		local ruleSets = liveEncounter:try_get("ruleSets")
		if type(ruleSets) == "table" and next(ruleSets) ~= nil then
			for _, ruleMod in pairs(GetTableCached(EncounterRuleSet.rulesTableName) or {}) do
				local encounterId = ruleMod:try_get("encounterId")
				if encounterId ~= nil and ruleSets[encounterId] then
					result[#result + 1] = ruleMod
				end
			end
		end
	end

	return result
end
