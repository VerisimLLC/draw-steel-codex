local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType("castingorigin", "Casting Origin")

CharacterModifier.TypeInfo.castingorigin = {
	filterRequiresRoll = true, -- prevent standard pipeline from checking filterCondition against bearer; we check it ourselves against the caster

	init = function(modifier)
		modifier.keywordFilter = {}
	end,

	createEditor = function(modifier, element)
		local Refresh
		local firstRefresh = true

		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			local children = {}

			children[#children+1] = gui.Label{
				classes = {"formHelpLabel"},
				text = "The creature with this modifier becomes a casting origin: other creatures that pass the Condition can measure an ability's range from it instead of from themselves. The Condition must be filled in. If it is blank, no one can use this creature as an origin.",
				fontSize = 10,
				color = "#aaaaaa",
				width = "100%",
				height = "auto",
			}

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Condition:",
				},
				gui.GoblinScriptInput{
					value = modifier:try_get("filterCondition", ""),
					change = function(el)
						if type(el.value) == "string" and trim(el.value) == "" then
							modifier.filterCondition = nil
						else
							modifier.filterCondition = el.value
						end
					end,

					documentation = {
						domains = modifier:Domains(),
						help = "Decides which creatures may cast through this one. Self is the creature with this modifier; Caster is the creature using an ability. Produce True to let that caster measure range from this creature. A blank condition lets no one use it.",
						output = "boolean",
						examples = {
							{
								script = "Caster = Self.Summoner",
								text = "Only the creature that summoned this creature can cast through it.",
							},
							{
								script = "Caster = Self.Summoner or Caster.Summoned",
								text = "The summoner, and any summoned creature, can cast through this creature.",
							},
							{
								script = "Caster = Self.Mentor",
								text = "Only this retainer's mentor can cast through it. A condition that never mentions Caster lets every creature through.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature with this modifier (the casting origin)",
						symbols = modifier:HelpAdditionalSymbols{
							caster = {
								name = "Caster",
								type = "creature",
								desc = "The creature using an ability that would measure its range from this creature.",
							},
						},
					},
				},
			}

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Ability Filter:",
				},
				gui.GoblinScriptInput{
					value = modifier:try_get("abilityFilter", ""),
					change = function(el)
						if type(el.value) == "string" and trim(el.value) == "" then
							modifier.abilityFilter = nil
						else
							modifier.abilityFilter = el.value
						end
					end,

					documentation = {
						domains = modifier:Domains(),
						help = "Optional. Decides which abilities may be cast through this creature. Produce True to allow the ability. Leave blank to allow every ability (subject to the keyword filter below).",
						output = "boolean",
						examples = {
							{
								script = "Ability.Keywords has \"Magic\"",
								text = "Only magic abilities can be cast through this creature.",
							},
							{
								script = "Ability.Name = \"Judgment\"",
								text = "Only the Judgment ability can be cast through this creature.",
							},
							{
								script = "Ability.Categorization != \"Heroic Ability\"",
								text = "Heroic abilities cannot be cast through this creature.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature with this modifier (the casting origin)",
						symbols = modifier:HelpAdditionalSymbols{
							caster = {
								name = "Caster",
								type = "creature",
								desc = "The creature using the ability.",
							},
							ability = {
								name = "Ability",
								type = "ability",
								desc = "The ability that would measure its range from this creature.",
							},
						},
					},
				},
			}

			local addDropdown = gui.Dropdown{
				classes = "formDropdown",
				sort = true,
				textOverride = "Add Keyword Filter...",
				hasSearch = true,
				idChosen = "none",
				create = function(el)
					---@cast el Dropdown
					local options = {}
					for keyword, _ in pairs(GameSystem.abilityKeywords) do
						if not modifier.keywordFilter[keyword] then
							options[#options+1] = {
								id = keyword,
								text = keyword,
							}
						end
					end
					el.options = options
					el:SetClass("collapsed", #options == 0)
				end,
				refreshKeywordFilter = function(el)
					el:FireEvent("create")
				end,
				change = function(el)
					---@cast el Dropdown
					if el.idChosen ~= "none" then
						modifier.keywordFilter[el.idChosen] = true
						Refresh()
					end
				end,
			}

			local keywordEntries = {}
			for keyword, _ in pairs(modifier.keywordFilter) do
				local kw = keyword
				keywordEntries[#keywordEntries+1] = gui.Panel{
					classes = {"formPanel", "formPanel-inline"},
					data = {
						ord = kw,
					},
					gui.Label{
						classes = "formLabel",
						text = ActivatedAbility.CanonicalKeyword(kw),
					},
					gui.Button{
						classes = {"deleteButton", "sizeS"},
						halign = "right",
						click = function(el)
							modifier.keywordFilter[kw] = nil
							Refresh()
						end,
					},
				}
			end

			table.sort(keywordEntries, function(a, b) return a.data.ord < b.data.ord end)

			children[#children+1] = gui.Panel{
				flow = "vertical",
				width = "auto",
				height = "auto",
				children = keywordEntries,
			}

			children[#children+1] = addDropdown

			children[#children+1] = gui.Label{
				classes = {"formHelpLabel"},
				text = "If no keywords are added, all abilities match.",
				fontSize = 10,
				color = "#aaaaaa",
				width = "100%",
				height = "auto",
			}

			element.children = children
		end

		Refresh()
	end,
}

local function KeywordFilterMatches(ability, keywordFilter)
	local hasAnyFilter = false
	for k, v in pairs(keywordFilter) do
		if v then
			hasAnyFilter = true
			if ability:HasKeyword(k) then
				return true
			end
		end
	end
	return not hasAnyFilter
end

--Runs a Casting Origin formula with Self = the origin, plus Caster and Ability.
--modContext carries symbols from the modifier's source (e.g. an ongoing effect).
local function EvaluateOriginFormula(formula, label, ability, casterCreature, bearerCreature, modifier, modContext)
	if modContext ~= nil then
		modifier:InstallSymbolsFromContext(modContext)
	end

	local symbols = modifier:try_get("_tmp_symbols", {})
	symbols.caster = casterCreature
	symbols.ability = ability
	return GoblinScriptTrue(ExecuteGoblinScript(formula, bearerCreature:LookupSymbol(symbols), 0, label))
end

--Blank allows every ability, so older modifiers keep working. The Condition is the
--opposite: blank lets no one cast through.
local function AbilityPassesFilter(ability, casterCreature, bearerCreature, modifier, modContext)
	local filter = modifier:try_get("abilityFilter", "")
	if filter == "" then
		return true
	end
	return EvaluateOriginFormula(filter, "Casting Origin: ability filter", ability, casterCreature, bearerCreature, modifier, modContext)
end

local function CasterPassesCondition(ability, casterCreature, bearerCreature, modifier, modContext)
	local condition = modifier:try_get("filterCondition", "")
	if condition == "" then
		return false
	end
	return EvaluateOriginFormula(condition, "Casting Origin: condition", ability, casterCreature, bearerCreature, modifier, modContext)
end

--Relay lookup walks every token on the map and runs a GoblinScript condition
--per casting-origin modifier, and the targeting UI asks for it repeatedly while
--a target is hovered. One frame is short enough that nothing can move in
--between, and long enough to collapse those repeats into a single walk.
local g_relayCacheFrame = -1
local g_relayCache = {}

function ActivatedAbility:GetCastingOriginTokens(casterToken)
	if mod.unloaded then
		return {}
	end

	local frame = dmhub.FrameCount()
	if frame ~= g_relayCacheFrame then
		g_relayCacheFrame = frame
		g_relayCache = {}
	end

	local byCaster = g_relayCache[self]
	if byCaster == nil then
		byCaster = {}
		g_relayCache[self] = byCaster
	elseif byCaster[casterToken.charid] ~= nil then
		return byCaster[casterToken.charid]
	end

	local result = {}
	local allTokens = dmhub.GetTokens{haveProperties = true}
	for _, tok in ipairs(allTokens) do
		if tok.valid and tok.charid ~= casterToken.charid then
			local modifiers = tok.properties:GetActiveModifiers()
			for _, modEntry in ipairs(modifiers) do
				if modEntry.mod.behavior == "castingorigin"
					and KeywordFilterMatches(self, modEntry.mod.keywordFilter)
					and AbilityPassesFilter(self, casterToken.properties, tok.properties, modEntry.mod, modEntry)
					and CasterPassesCondition(self, casterToken.properties, tok.properties, modEntry.mod, modEntry) then
					result[#result+1] = tok
					break
				end
			end
		end
	end

	byCaster[casterToken.charid] = result
	return result
end

function ActivatedAbility:IsTargetInRangeOfCastingOrigins(casterToken, targetToken, range)
	local relayTokens = self:GetCastingOriginTokens(casterToken)
	for _, relayToken in ipairs(relayTokens) do
		if range + dmhub.unitsPerSquare > targetToken:Distance(relayToken) then
			--also check vertical range from the relay token.
			local verticalDist = math.abs(relayToken.altitude - targetToken.altitude) * dmhub.unitsPerSquare
			if verticalDist < range + dmhub.unitsPerSquare then
				return true
			end
		end
	end
	return false
end

local g_prevCustomTargetShape = ActivatedAbility.CustomTargetShape

function ActivatedAbility:CustomTargetShape(casterToken, range, symbols, targets)
	if mod.unloaded then
		return g_prevCustomTargetShape(self, casterToken, range, symbols, targets)
	end

	local relayTokens = self:GetCastingOriginTokens(casterToken)
	if #relayTokens == 0 then
		return g_prevCustomTargetShape(self, casterToken, range, symbols, targets)
	end

	local locations = {}
	local seen = {}

	local baseLocs = g_prevCustomTargetShape(self, casterToken, range, symbols, targets)
	if baseLocs ~= nil then
		for _, loc in ipairs(baseLocs) do
			local key = loc.xyfloorOnly.str
			if not seen[key] then
				locations[#locations+1] = loc
				seen[key] = true
			end
		end
	else
		local shape = dmhub.CalculateShape{
			shape = "radiusfromcreature",
			token = casterToken,
			radius = range,
		}
		for _, loc in ipairs(shape.locations) do
			local key = loc.xyfloorOnly.str
			if not seen[key] then
				locations[#locations+1] = loc
				seen[key] = true
			end
		end
	end

	for _, relayToken in ipairs(relayTokens) do
		local shape = dmhub.CalculateShape{
			shape = "radiusfromcreature",
			token = relayToken,
			radius = range,
		}
		for _, loc in ipairs(shape.locations) do
			local key = loc.xyfloorOnly.str
			if not seen[key] then
				locations[#locations+1] = loc
				seen[key] = true
			end
		end
	end

	return locations
end
