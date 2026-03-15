local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType("castingorigin", "Casting Origin")

CharacterModifier.TypeInfo.castingorigin = {
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

			children[#children+1] = modifier:FilterConditionEditor()

			local addDropdown = gui.Dropdown{
				classes = "formDropdown",
				sort = true,
				textOverride = "Add Keyword Filter...",
				hasSearch = true,
				idChosen = "none",
				create = function(el)
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
					classes = {"formPanel"},
					data = {
						ord = kw,
					},
					gui.Label{
						classes = "formLabel",
						text = kw,
					},
					gui.DeleteItemButton{
						halign = "right",
						width = 16,
						height = 16,
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

function ActivatedAbility:GetCastingOriginTokens(casterToken)
	if mod.unloaded then
		return {}
	end

	local result = {}
	local allTokens = dmhub.GetTokens{haveProperties = true}
	for _, tok in ipairs(allTokens) do
		if tok.valid and tok.charid ~= casterToken.charid and casterToken:IsFriend(tok) then
			local modifiers = tok.properties:GetActiveModifiers()
			for _, modEntry in ipairs(modifiers) do
				if modEntry.mod.behavior == "castingorigin" and KeywordFilterMatches(self, modEntry.mod.keywordFilter) then
					result[#result+1] = tok
					break
				end
			end
		end
	end

	return result
end

function ActivatedAbility:IsTargetInRangeOfCastingOrigins(casterToken, targetToken, range)
	local relayTokens = self:GetCastingOriginTokens(casterToken)
	for _, relayToken in ipairs(relayTokens) do
		if range + dmhub.unitsPerSquare > targetToken:Distance(relayToken) then
			return true
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
