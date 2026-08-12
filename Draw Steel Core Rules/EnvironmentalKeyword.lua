local mod = dmhub.GetModLoading()

--This file implements Environmental Keywords: named environmental conditions
--(e.g. "Dark", "Lava") that are known to the game and attach one or more
--CharacterModifiers to any creature affected by them. They are authored in the
--Compendium under Rules and stored in the "environmentalKeywords" object table.
--
--An EnvironmentalKeyword derives from CharacterFeature, so it carries a list of
--modifiers plus the shared modifier editor (CharacterFeature:EditorPanel). This
--is the same relationship CharacterCondition has with CharacterFeature.

--- @class EnvironmentalKeyword:CharacterFeature
--- @field name string Display name of the keyword (e.g. "Dark", "Lava"). Class default "New Environmental Keyword" applies when absent.
--- @field description string Rules text shown to players. Class default "" applies when absent.
--- @field tableName string Name of the data table this keyword is stored in ("environmentalKeywords"). Class-level default; often absent on serialized instances.
--- @field source string Source label ("Environmental Keyword"). Class-level default; often absent on serialized instances.
--- @field iconid string Icon shown in the UI. Class-level default applies when absent.
--- @field display table Icon display settings (bgcolor/hueshift/saturation/brightness).
--- @field difficultTerrain boolean If true, an area marked with this keyword counts as difficult terrain. Uses the same terrain rule flag name as tiles (asset.rules.difficultTerrain).
--- @field water boolean If true, an area marked with this keyword counts as water. Uses the same terrain rule flag name as tiles (asset.rules.water).
--- @field concealment boolean If true, an area marked with this keyword grants concealment. Uses the same terrain rule flag name as tiles (asset.rules.concealment).
--- @field climbable boolean If true, an area marked with this keyword can be climbed, like a climbable wall: creatures in it may climb up to the ceiling of the floor.
--- @field climbersOnly boolean Only meaningful when climbable is true: restricts climbing to natural climbers (climb speed >= walk speed), matching walls' "Climbable (Climbers Only)". Uses the same terrain rule flag name as tiles (rules.climbersOnly).
--- @field dynamicLight boolean If true, the Map Markup zone palette offers the "Dynamic Light" option for this keyword (its zones/blanket apply only where the map's light level is below a per-map threshold). Purely a UI/eligibility gate: the sampling and carving live in MapMarkupPanel.lua; unchecking disables an already-configured threshold without deleting it.
--- @field dispels string[]|nil Ids (environmentalKeywords table keys) of keywords this keyword dispels. Painting a zone of this keyword deletes the overlap from zones of a dispelled keyword (and a dispelled keyword cannot be painted over this one); an aura carrying this keyword suppresses zones of dispelled keywords beneath it for as long as the aura covers them. No class default: assigned per instance by the editor (a class-level default table would be shared-mutable).
--- @field movedamage string Damage type dealt to creatures moving through an area with this keyword, or "none" for no damage. Uses the same field names as Aura so the values copy straight onto zone auras.
--- @field damage number Damage dealt per tile of the area a creature moves through (only meaningful when movedamage is not "none").
--- @field movementDamageFilter string Which movement the damage applies to: "all", "nonshift" (shifting avoids it), or "forced" (forced movement only).
--- @field powerRollEnabled boolean If true, a 2d10 + powerRollBonus power roll is made against any creature entering the area or starting its turn there. Same field names as Aura; copied onto zone auras.
--- @field powerRollBonus number The X in the 2d10 + X power roll.
--- @field powerRollTiers string[]|nil The three power table tier texts (tier 1 = 11 or less, tier 2 = 12-16, tier 3 = 17+). No class default: assigned per instance by the editor.
--- @field includeAdjacent boolean If true, areas marked with this keyword extend one tile outward (8-way): creatures adjacent to the area count as touching it for enter/start-of-turn triggers (the entry power roll fires for them at the start of their turn, with a bane), but adjacent tiles do not take the keyword's terrain rules, move damage, or modifiers. Same field name as Aura; copied onto zone auras.
--- @field mapid string|nil When set, this keyword is a map-scoped zone type: it was created from that map's Zone Types palette and is hidden from the compendium, other maps' palettes, and keyword dropdowns until promoted ("Make Available to All Maps" clears the field). No class default: absent = a full keyword.
EnvironmentalKeyword = RegisterGameType("EnvironmentalKeyword", "CharacterFeature")

EnvironmentalKeyword.name = "New Environmental Keyword"
EnvironmentalKeyword.description = ""
EnvironmentalKeyword.tableName = "environmentalKeywords"
EnvironmentalKeyword.source = "Environmental Keyword"
EnvironmentalKeyword.iconid = "ui-icons/skills/1.png"
EnvironmentalKeyword.difficultTerrain = false
EnvironmentalKeyword.water = false
EnvironmentalKeyword.concealment = false
EnvironmentalKeyword.climbable = false
EnvironmentalKeyword.climbersOnly = false
EnvironmentalKeyword.dynamicLight = false
EnvironmentalKeyword.movedamage = "none"
EnvironmentalKeyword.damage = 0
EnvironmentalKeyword.movementDamageFilter = "all"
EnvironmentalKeyword.powerRollEnabled = false
EnvironmentalKeyword.powerRollBonus = 0
EnvironmentalKeyword.includeAdjacent = false

--Index of keywords by lower-case name, rebuilt whenever tables refresh. Used by
--runtime code that needs to resolve a keyword from its name.
EnvironmentalKeyword.keywordsByName = {}

function EnvironmentalKeyword.OnDeserialize(self)
	if not self:has_key("guid") then
		self.guid = dmhub.GenerateGuid()
	end
end

--- @return EnvironmentalKeyword
function EnvironmentalKeyword.CreateNew()
	return EnvironmentalKeyword.new{
		guid = dmhub.GenerateGuid(),
		name = "New Environmental Keyword",
		source = "Environmental Keyword",
		description = "",
		modifiers = {},
		iconid = "ui-icons/skills/1.png",
		display = {
			bgcolor = "white",
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		},
	}
end

--- Folds an Environmental Keyword's mechanical effects into an aura definition.
---
--- This is the single place that knows what "an area marked with this keyword"
--- means mechanically. Both aura-creation paths call it, so a keyword means the
--- same thing however the area was made:
---   * painted map-markup zones (MapMarkup BuildZoneAuraInstance), and
---   * ability auras that name a keyword (ActivatedAbilityAuraBehavior:CastOnArea).
---
--- The merge is ADDITIVE ONLY: a keyword can switch an effect on but never off,
--- and never overwrites a value the aura already specifies. That keeps auras that
--- spell out their own flags behaving exactly as before (e.g. the shadow elf
--- darkness auras, which already set concealment directly), and means attaching a
--- keyword to an existing aura can only ever add to it.
---
--- Deliberately NOT copied: name, iconid, display. Those are the aura's own
--- identity -- an ability aura keeps the ability's icon and colour, and a zone
--- aura takes the keyword's separately in BuildZoneAuraInstance.
---
--- @param auraDef Aura The aura definition to mutate. nil is a no-op.
--- @param keywordid string|nil Id in the environmentalKeywords table. nil, or an id
---        that no longer resolves (deleted keyword), is a no-op.
--- @return Aura|nil auraDef The same definition, for call chaining.
function EnvironmentalKeyword.ApplyToAura(auraDef, keywordid)
	if auraDef == nil or keywordid == nil then
		return auraDef
	end

	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
	local keyword = dataTable[keywordid]
	if keyword == nil then
		return auraDef
	end

	--Stamp the id so runtime code can tell which keyword this area came from:
	--the creature and Loc "Environment" symbols, and the darkness test in
	--creature:HasConcealmentIgnoringDarkness, both resolve it against this table.
	auraDef.environmentalKeywordId = keywordid

	--Terrain rule flags, sharing the tile-rule flag names. try_get throughout:
	--older serialized keywords predate some fields, and game-typed instances
	--raise on unknown-field reads.
	pcall(function()
		if keyword:try_get("difficultTerrain", false) == true then
			auraDef.difficult_terrain = true
		end
		if keyword:try_get("water", false) == true then
			auraDef.water = true
		end
		if keyword:try_get("concealment", false) == true then
			auraDef.concealment = true
		end
		--climbersOnly rides along only when this keyword is the one turning
		--climbable on: it is a restriction, so it must never tighten an aura
		--that already declared itself climbable for all creatures.
		if keyword:try_get("climbable", false) == true and auraDef:try_get("climbable", false) ~= true then
			auraDef.climbable = true
			if keyword:try_get("climbersOnly", false) == true then
				auraDef.climbersOnly = true
			end
		end
		--the area extends one tile outward for enter/start-of-turn trigger
		--contact (adjacent tiles never take terrain rules or modifiers, so
		--this is additive-safe like the other flags).
		if keyword:try_get("includeAdjacent", false) == true then
			auraDef.includeAdjacent = true
		end
	end)

	--Modifiers applied to creatures inside the area. Deep-copied because
	--GetModifiers stamps transient symbol state onto modifier objects, and the
	--table's own copies are shared with the compendium editor and every other
	--area built from this keyword. Appended to a FRESH list rather than mutated
	--in place: CharacterFeature.modifiers is a class-level default table, so an
	--aura that never set its own would otherwise append into the shared default.
	pcall(function()
		local keywordModifiers = keyword:try_get("modifiers")
		if keywordModifiers ~= nil and #keywordModifiers > 0 then
			local modifiers = {}
			for _,m in ipairs(auraDef:try_get("modifiers", {})) do
				modifiers[#modifiers+1] = m
			end
			for _,m in ipairs(keywordModifiers) do
				modifiers[#modifiers+1] = dmhub.DeepCopy(m)
			end
			auraDef.modifiers = modifiers
		end
	end)

	--Damage per tile of the area a creature moves through. Skipped when the
	--aura already defines its own move damage, so the two can't compound.
	pcall(function()
		local movedamage = keyword:try_get("movedamage", "none")
		if movedamage ~= nil and movedamage ~= "none" and auraDef:try_get("movedamage", "none") == "none" then
			auraDef.movedamage = movedamage
			auraDef.damage = keyword:try_get("damage", 0)
			auraDef.movementDamageFilter = keyword:try_get("movementDamageFilter", "all")
		end
	end)

	--Power roll against creatures entering the area or starting a turn in it
	--(creature:EnterAura -> Aura:GetSimplePowerRollTrigger). Skipped when the
	--aura already rolls its own, since only one roll can fire per entry.
	pcall(function()
		if keyword:try_get("powerRollEnabled", false) and auraDef:try_get("powerRollEnabled", false) == false then
			local tiers = keyword:try_get("powerRollTiers")
			if tiers ~= nil then
				auraDef.powerRollEnabled = true
				auraDef.powerRollBonus = keyword:try_get("powerRollBonus", 0)
				auraDef.powerRollTiers = dmhub.DeepCopy(tiers)
			end
		end
	end)

	return auraDef
end

--- True if this aura definition, or any of its sub-auras, names an Environmental
--- Keyword. Callers that share an aura definition rather than owning it (e.g. the
--- token-attached aura modifier, whose auras are regenerated on every creature
--- invalidation) use this to decide whether making a copy is worth it at all.
--- @param auraDef Aura|nil
--- @return boolean
function EnvironmentalKeyword.AuraNamesKeyword(auraDef)
	if auraDef == nil then
		return false
	end

	if auraDef:try_get("environmentalKeywordId") ~= nil then
		return true
	end

	for _,childDef in ipairs(auraDef:try_get("subauras", {})) do
		if childDef:try_get("environmentalKeywordId") ~= nil then
			return true
		end
	end

	return false
end

--- Applies each keyword named in an aura definition to the payload that names it:
--- the parent's keyword to the parent, and each sub-aura's own keyword to that
--- sub-aura. Sub-auras carry their own terrain flags, modifiers, and move damage,
--- so they merge independently rather than inheriting the parent's keyword.
---
--- Mutates auraDef in place -- pass a copy if you do not own it.
--- @param auraDef Aura|nil
--- @return Aura|nil auraDef The same definition, for call chaining.
function EnvironmentalKeyword.ApplyToAuraTree(auraDef)
	if auraDef == nil then
		return auraDef
	end

	EnvironmentalKeyword.ApplyToAura(auraDef, auraDef:try_get("environmentalKeywordId"))

	for _,childDef in ipairs(auraDef:try_get("subauras", {})) do
		EnvironmentalKeyword.ApplyToAura(childDef, childDef:try_get("environmentalKeywordId"))
	end

	return auraDef
end

--- Appends {id, text} entries for all environmental keywords into options (sorted by name).
--- Map-scoped zone types (mapid set) are included only when they belong to the current map.
--- @param options DropdownOption[]
function EnvironmentalKeyword.FillDropdownOptions(options)
	local result = {}
	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
	for k,keyword in unhidden_pairs(dataTable) do
		local mapid = keyword:try_get("mapid")
		if mapid == nil or mapid == game.currentMapId then
			result[#result+1] = {
				id = k,
				text = keyword.name,
			}
		end
	end

	table.sort(result, function(a,b) return a.text < b.text end)
	for i,item in ipairs(result) do
		options[#options+1] = item
	end
end

local UploadKeywordWithId = function(id)
	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
	dmhub.SetAndUploadTableItem(EnvironmentalKeyword.tableName, dataTable[id])
end

local SetData = function(tableName, keywordPanel, keyid)
	local dataTable = dmhub.GetTable(tableName) or {}
	local keyword = dataTable[keyid]

	--guard: the id may be stale (e.g. an old palette entry stranded on an id
	--that is not in the table). Leave the panel as-is rather than erroring.
	if keyword == nil then
		dmhub.Debug(string.format("EnvironmentalKeyword:: SetData: no keyword with id %s", tostring(keyid)))
		return
	end

	local UploadKeyword = function()
		dmhub.SetAndUploadTableItem(tableName, keyword)
	end

	--if we were displaying a different keyword and it has unsaved changes, flush it.
	if keywordPanel.data.keyid ~= "" and keywordPanel.data.keyid ~= keyid and dmhub.ToJson(dataTable[keywordPanel.data.keyid]) ~= keywordPanel.data.keywordjson then
		UploadKeywordWithId(keywordPanel.data.keyid)
	end

	keywordPanel.data.keyid = keyid
	keywordPanel.data.keywordjson = dmhub.ToJson(keyword)

	--make sure the icon display info exists (older items may predate it).
	keyword:get_or_add("display", {
		bgcolor = "white",
		hueshift = 0,
		saturation = 1,
		brightness = 1,
	})

	local children = {}

	if devmode() then
		--the id of the keyword.
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "ID:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = keyword.id,
				editable = false,
			},
		}
	end

	--the name of the keyword.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = keyword.name,
			change = function(element)
				keyword.name = element.text
				UploadKeyword()
			end,
		},
	}

	--map-scoped zone types: created from a map's Zone Types palette and hidden
	--from the compendium and other maps until promoted to a full keyword.
	if keyword:try_get("mapid") ~= nil then
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "This zone type is only available on this map.",
			},
			gui.Button{
				classes = {"sizeM"},
				halign = "left",
				text = "Make Available to All Maps",
				click = function(element)
					keyword.mapid = nil
					UploadKeyword()
					element.parent:SetClass("collapsed", true)
				end,
			},
		}
	end

	--the keyword's icon.
	local iconEditor = gui.IconEditor{
		library = "ongoingEffects",
		bgcolor = keyword.display['bgcolor'] or "white",
		margin = 20,
		width = 64,
		height = 64,
		halign = "left",
		value = keyword.iconid,
		change = function(element)
			keyword.iconid = element.value
			UploadKeyword()
		end,
		create = function(element)
			element.selfStyle.hueshift = keyword.display['hueshift']
			element.selfStyle.saturation = keyword.display['saturation']
			element.selfStyle.brightness = keyword.display['brightness']
		end,
	}

	local iconColorPicker = gui.ColorPicker{
		value = keyword.display['bgcolor'] or "white",
		hmargin = 8,
		width = 24,
		height = 24,
		valign = 'center',

		confirm = function(element)
			iconEditor.selfStyle.bgcolor = element.value
			keyword.display['bgcolor'] = element.value
			UploadKeyword()
		end,

		change = function(element)
			iconEditor.selfStyle.bgcolor = element.value
		end,
	}

	children[#children+1] = gui.Panel{
		width = 'auto',
		height = 'auto',
		flow = 'horizontal',
		halign = 'left',
		iconEditor,
		iconColorPicker,
	}

	--keyword description.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Details:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = keyword.description,
			multiline = true,
			textAlignment = "topLeft",
			height = 60,
			characterLimit = 600,
			change = function(element)
				keyword.description = element.text
				UploadKeyword()
			end,
		}
	}

	--an area marked with this keyword is difficult terrain.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("difficultTerrain", false),
			text = "Difficult Terrain",
			change = function(element)
				keyword.difficultTerrain = element.value
				UploadKeyword()
			end,
		},
	}

	--an area marked with this keyword is water.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("water", false),
			text = "Water",
			change = function(element)
				keyword.water = element.value
				UploadKeyword()
			end,
		},
	}

	--an area marked with this keyword grants concealment.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("concealment", false),
			text = "Concealment",
			change = function(element)
				keyword.concealment = element.value
				UploadKeyword()
			end,
		},
	}

	--an area marked with this keyword can be climbed (like a climbable wall:
	--creatures in it may climb up to the ceiling of the floor). The second
	--checkbox restricts it to natural climbers (climb speed >= walk speed),
	--matching walls' "Climbable (Climbers Only)"; it only shows while
	--Climbable is checked.
	local climbersOnlyCheck
	climbersOnlyCheck = gui.Check{
		value = keyword:try_get("climbersOnly", false),
		text = "Climbers Only",
		hmargin = 24,
		change = function(element)
			keyword.climbersOnly = element.value
			UploadKeyword()
		end,
	}
	if keyword:try_get("climbable", false) ~= true then
		climbersOnlyCheck:SetClass("collapsed", true)
	end

	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("climbable", false),
			text = "Climbable",
			change = function(element)
				keyword.climbable = element.value
				climbersOnlyCheck:SetClass("collapsed", not element.value)
				UploadKeyword()
			end,
		},
		climbersOnlyCheck,
	}

	--the area extends one tile outward: creatures adjacent to it count as
	--touching it for enter/start-of-turn triggers (the entry power roll fires
	--for them at the start of their turn, with a bane), but adjacent tiles do
	--not take the keyword's terrain rules, move damage, or modifiers.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("includeAdjacent", false),
			text = "Affects Adjacent Squares",
			tooltip = "The area extends one square outward. Creatures adjacent to the area count as touching it for enter and start-of-turn triggers - the entry power roll fires for them at the start of their turn, with a bane - but adjacent squares do not take the keyword's terrain rules, movement damage, or modifiers.",
			change = function(element)
				keyword.includeAdjacent = element.value
				UploadKeyword()
			end,
		},
	}

	--whether the Map Markup zone palette offers the "Dynamic Light" option for
	--this keyword (zones apply only where map light is below a threshold).
	--Eligibility only: most keywords (Water, Difficult Terrain) have no use for
	--it, so the palette stays uncluttered unless a keyword opts in.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			value = keyword:try_get("dynamicLight", false),
			text = "Can Use Dynamic Light",
			tooltip = "Zones of this type can be set (in the map's Zone Types palette) to only apply where the light level on the map is below a threshold - e.g. Darkness that recedes around a carried torch. Unchecking hides the option and disables any configured threshold without deleting it.",
			change = function(element)
				keyword.dynamicLight = element.value
				UploadKeyword()
			end,
		},
	}

	--keywords this keyword dispels. Painting this keyword over a zone of a
	--dispelled keyword deletes the overlap (and a dispelled keyword cannot be
	--painted over this one); an aura carrying this keyword suppresses zones
	--of dispelled keywords beneath it until the aura moves on or expires.
	--The list and its add-dropdown live in a self-refreshing sub-panel.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Dispels:",
		},
		gui.Panel{
			classes = {"formStacked"},
			flow = "vertical",
			height = "auto",

			create = function(element)
				element:FireEvent("refreshDispels")
			end,

			refreshDispels = function(element)
				local listPanel = element
				local liveTable = dmhub.GetTable(tableName) or {}
				local rows = {}
				local dispels = keyword:try_get("dispels", {})

				for i,dispelledId in ipairs(dispels) do
					local target = liveTable[dispelledId]
					local targetName = "(deleted keyword)"
					if target ~= nil and target.name ~= nil then
						targetName = target.name
					end

					local index = i
					rows[#rows+1] = gui.Panel{
						flow = "horizontal",
						width = "100%",
						height = "auto",
						vmargin = 2,
						gui.Label{
							fontSize = 18,
							width = "80%",
							height = "auto",
							halign = "left",
							valign = "center",
							text = targetName,
						},
						gui.DeleteItemButton{
							width = 16,
							height = 16,
							halign = "right",
							valign = "center",
							click = function()
								local items = keyword:try_get("dispels", {})
								table.remove(items, index)
								if #items == 0 then
									--nil-assignment removes the field from serialization.
									keyword.dispels = nil
								else
									keyword.dispels = items
								end
								UploadKeyword()
								listPanel:FireEvent("refreshDispels")
							end,
						},
					}
				end

				--keywords that can be added: everything except this keyword,
				--those already listed, and zone types scoped to another map.
				local have = {}
				for _,dispelledId in ipairs(dispels) do
					have[dispelledId] = true
				end

				local options = {}
				for k,other in unhidden_pairs(liveTable) do
					local mapid = other:try_get("mapid")
					if k ~= keyid and have[k] == nil and (mapid == nil or mapid == game.currentMapId) then
						options[#options+1] = { id = k, text = other.name }
					end
				end
				table.sort(options, function(a,b) return a.text < b.text end)

				if #options > 0 then
					table.insert(options, 1, { id = "none", text = "Add Keyword..." })
					rows[#rows+1] = gui.Dropdown{
						classes = {"formStacked"},
						vmargin = 2,
						idChosen = "none",
						options = options,
						change = function(dropdown)
							if dropdown.idChosen == "none" then
								return
							end
							local items = keyword:get_or_add("dispels", {})
							items[#items+1] = dropdown.idChosen
							keyword.dispels = items
							UploadKeyword()
							listPanel:FireEvent("refreshDispels")
						end,
					}
				elseif #rows == 0 then
					rows[#rows+1] = gui.Label{
						classes = {"formStacked"},
						fontSize = 14,
						text = "No other keywords available.",
					}
				end

				listPanel.children = rows
			end,
		},
	}

	--damage dealt to creatures that move through an area with this keyword.
	--The amount/filter rows only show while a damage type is chosen.
	local moveDamageDetails
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Move Damage:",
		},
		gui.Dropdown{
			classes = {"formStacked"},
			idChosen = keyword:try_get("movedamage", "none"),
			options = table.append_arrays({{id = "none", text = "none"}}, map(rules.damageTypesAvailable, function(a) return {id = a, text = a} end)),
			change = function(element)
				keyword.movedamage = element.idChosen
				moveDamageDetails:SetClass("collapsed", element.idChosen == "none")
				UploadKeyword()
			end,
		},
	}

	moveDamageDetails = gui.Panel{
		classes = {"formStackedRow", cond(keyword:try_get("movedamage", "none") == "none", "collapsed")},
		gui.Label{
			classes = {"formStacked"},
			text = "Damage Per Tile:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = tostring(keyword:try_get("damage", 0)),
			characterLimit = 4,
			change = function(element)
				local num = tonumber(element.text)
				if num == nil then
					element.text = tostring(keyword:try_get("damage", 0))
				else
					keyword.damage = num
					UploadKeyword()
				end
			end,
		},
		gui.Label{
			classes = {"formStacked"},
			text = "Applies To:",
		},
		gui.Dropdown{
			classes = {"formStacked"},
			idChosen = keyword:try_get("movementDamageFilter", "all"),
			options = {
				{id = "all", text = "All Movement"},
				{id = "nonshift", text = "Non-Shifting Movement"},
				{id = "forced", text = "Forced Movement Only"},
			},
			change = function(element)
				keyword.movementDamageFilter = element.idChosen
				UploadKeyword()
			end,
		},
	}
	children[#children+1] = moveDamageDetails

	--optional power roll made against any creature that enters the area or
	--starts its turn there (shared editor section with the Aura dialog).
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		Aura.CreateSimplePowerRollEditor{
			obj = keyword,
			change = UploadKeyword,
		},
	}

	--list of modifiers that this keyword applies to affected creatures.
	children[#children+1] = gui.Panel{
		width = 800,
		height = "auto",
		halign = "left",
		styles = {
			{
				selectors = {"namePanel"},
				collapsed = 1,
			},
			{
				selectors = {"sourcePanel"},
				collapsed = 1,
			},
			{
				selectors = {"descriptionPanel"},
				collapsed = 1,
			},
		},

		keyword:EditorPanel{
			noscroll = true,
			modifierRefreshed = function(element)
				UploadKeyword()
			end,
		},
	}

	keywordPanel.children = children
end

--- @param options nil|{width: number|string, height: number|string} Optional size overrides (the compendium default is 1200 x 90%).
function EnvironmentalKeyword.CreateEditor(options)
	options = options or {}
	local keywordPanel
	keywordPanel = gui.Panel{
		data = {
			SetData = function(tableName, keyid)
				SetData(tableName, keywordPanel, keyid)
			end,
			keyid = "",
			keywordjson = "",
		},
		destroy = function(element)
			local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}

			--if the keyword changed, then upload it.
			if element.data.keyid ~= "" and dmhub.ToJson(dataTable[element.data.keyid]) ~= element.data.keywordjson then
				UploadKeywordWithId(element.data.keyid)
			end
		end,
		vscroll = true,
		width = options.width or 1200,
		height = options.height or "90%",
		halign = "left",
		flow = "vertical",
		pad = 20,
		borderBox = true,
	}

	return keywordPanel
end

--- Opens the keyword editor in a modal dialog: the same editor the compendium
--- shows, framed for use outside the compendium (the Map Markup panel's Zone
--- Types interface uses this for its settings cog). Changes save as they are
--- made; Close just dismisses.
--- @param keyid string Id of the keyword in the environmentalKeywords table.
function EnvironmentalKeyword.ShowEditDialog(keyid)
	local keywordPanel = EnvironmentalKeyword.CreateEditor{
		width = "100%",
		height = "100%-110",
	}

	local dialogPanel = gui.Panel{
		id = "EnvironmentalKeywordDialog",
		classes = {"framedPanel"},
		styles = ThemeEngine.GetStyles(),
		width = 900,
		height = "90%",
		pad = 16,
		borderBox = true,
		flow = "vertical",
		halign = "center",
		valign = "center",

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			gui.CloseModal()
		end,

		gui.Label{
			classes = {"dialogTitle"},
			text = "Edit Zone Type",
		},

		keywordPanel,

		gui.Button{
			classes = {"sizeM"},
			text = "Close",
			halign = "center",
			valign = "bottom",
			vmargin = 8,
			click = function(element)
				gui.CloseModal()
			end,
		},
	}

	--attach the dialog before populating it: if SetData ever errors, the
	--panel must not be left orphaned.
	gui.ShowModal(dialogPanel)

	keywordPanel.data.SetData(EnvironmentalKeyword.tableName, keyid)
end

--- @param contentPanel Panel
local ShowEnvironmentalKeywordsPanel = function(contentPanel)
	local keywordPanel = EnvironmentalKeyword.CreateEditor()
	local SetData = keywordPanel.data.SetData

	local listItems = {}

	local itemsListPanel
	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)
			local children = {}
			local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
			local newListItems = {}

			for k,item in pairs(dataTable) do
				--map-scoped zone types stay out of the compendium until promoted.
				if item:try_get("mapid") == nil then
					newListItems[k] = listItems[k] or Compendium.CreateListItem{
						select = element.aliveTime > 0.2,
						tableName = EnvironmentalKeyword.tableName,
						key = k,
						click = function()
							SetData(EnvironmentalKeyword.tableName, k)
						end,
					}

					newListItems[k].text = item.name

					children[#children+1] = newListItems[k]
				end
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			listItems = newListItems
			itemsListPanel.children = children
		end,
	}

	itemsListPanel:FireEvent('refreshAssets')

	local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
		Compendium.AddButton{
			click = function(element)
				dmhub.SetAndUploadTableItem(EnvironmentalKeyword.tableName, EnvironmentalKeyword.CreateNew())
			end,
		}
	}

	contentPanel.children = {leftPanel, keywordPanel}
end

Compendium.Register{
	section = "Rules",
	text = "Environmental Keywords",
	contentType = EnvironmentalKeyword.tableName,
	click = function(contentPanel)
		ShowEnvironmentalKeywordsPanel(contentPanel)
	end,
}

dmhub.RegisterEventHandler("refreshTables", function()
	local byName = {}
	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
	for k,v in unhidden_pairs(dataTable) do
		byName[string.lower(v.name)] = v
	end
	EnvironmentalKeyword.keywordsByName = byName
end)

--------------------------------------------------------------------------------
--Per-square GoblinScript symbols on Loc.
--
--Abilities with targetType "emptyspace"/"anyspace" evaluate their targetFilter
--once per candidate destination square, with the square bound to the "target"
--symbol as a Loc (see ActivatedAbility:TargetLocPassesFilterPredicate). These
--symbols let such filters interrogate the map zones covering a square, e.g. a
--teleport restricted to areas of darkness:
--
--  targetFilter: 'target.Environment has "Darkness"'
--
--Aura membership for a bare square mirrors how a standing size-1 creature on
--the square would be tested by the engine (AuraManager.GetAurasAtLoc +
--Aura.ApplyTo): the aura index is footprint-based (keyed by x/y/floor with
--altitude stripped), and an aura carrying a finite vertical band
--[altitude, altitude + height] only applies when the square's ground altitude
--falls inside the band. A standing size-1 creature occupies exactly its
--ground altitude, so the creature band-overlap test reduces to a point test
--at ground level. Creature-relative aura filters (friends/enemies/applyto)
--are NOT applied: there is no creature standing on the square to test.
--------------------------------------------------------------------------------

--True if the aura instance's vertical band covers a creature standing at
--refAltitude. nil height means unlimited height (the engine skips the
--vertical test entirely in that case too).
local function AuraBandCoversAltitude(auraInstance, refAltitude)
	local height = auraInstance:GetHeight()
	if height == nil then
		return true
	end
	local base = auraInstance:GetAltitude() or 0
	return refAltitude >= base and refAltitude <= base + height
end

--Aura.LocOnlyAdjacent is a newer engine method (includeAdjacent auras); on an
--older engine build the member read raises. Probe once and fall back to
--"never adjacent-only", which matches such builds: they never build adjacent
--extensions either.
local g_hasLocOnlyAdjacent = nil
local function AuraLocOnlyAdjacent(aura, engineLoc)
	if g_hasLocOnlyAdjacent == nil then
		local ok, result = pcall(function() return aura:LocOnlyAdjacent(engineLoc) end)
		g_hasLocOnlyAdjacent = ok
		return ok and result == true
	end

	if g_hasLocOnlyAdjacent then
		return aura:LocOnlyAdjacent(engineLoc) == true
	end

	return false
end

EnvironmentalKeyword.AuraLocOnlyAdjacent = AuraLocOnlyAdjacent

--Returns the (Lua) AuraInstances covering a single square, band-tested at the
--square's ground altitude. engineLoc is an engine Loc userdata.
local function AuraInstancesCoveringSquare(engineLoc)
	local result = {}

	--normalize the query the way the engine does for tokens: the aura index
	--is keyed by x/y/floor with tiny-size and altitude stripped.
	local queryLoc = engineLoc.xyfloorOnly
	local auras = game.GetAurasAtLoc(queryLoc)
	if auras == nil then
		return result
	end

	local refAltitude = engineLoc.withGroundAltitude.altitude

	for _,aura in ipairs(auras) do
		local instance = aura.auraInstance
		--squares on an aura's adjacent extension (includeAdjacent) are next to
		--the area, not covered by it, so they are not part of its Environment.
		if instance ~= nil and not AuraLocOnlyAdjacent(aura, queryLoc) then
			--tolerate aura instances that do not implement the AuraInstance
			--interface: skip them rather than erroring the whole filter.
			local ok, covers = pcall(AuraBandCoversAltitude, instance, refAltitude)
			if ok and covers then
				result[#result+1] = instance
			end
		end
	end

	return result
end

GameSystem.RegisterGoblinScriptField{
	target = Loc,
	name = "Environment",
	type = "set",
	desc = "The names of the Environmental Keywords of the map zones covering this location. Mirrors the creature symbol of the same name: zone display names do not matter; the underlying keyword's name is what appears in the set.",
	seealso = {"Concealment"},
	examples = {"target.Environment has \"Darkness\""},
	calculate = function(c)
		local result = {}
		local engineLoc = rawget(c, "_tmp_loc")
		if engineLoc == nil then
			return StringSet.new{ strings = result }
		end

		--Map-markup zone auras carry the id of the Environmental Keyword they
		--were built from (see MapMarkup BuildZoneAuraInstance); resolve each
		--id to the keyword's live name, the same way the creature-side
		--"Environment" symbol in MCDMCreature.lua does. A deleted or
		--unresolvable keyword contributes nothing; multiple zones of the same
		--keyword contribute its name once.
		local keywordsTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
		local seenIds = {}
		local seenNames = {}
		for _,instance in ipairs(AuraInstancesCoveringSquare(engineLoc)) do
			local auraDef = instance:try_get("aura")
			local keywordid = nil
			if auraDef ~= nil then
				keywordid = auraDef:try_get("environmentalKeywordId")
			end
			if keywordid ~= nil and seenIds[keywordid] == nil then
				seenIds[keywordid] = true
				local keyword = keywordsTable[keywordid]
				if keyword ~= nil and (not keyword:try_get("hidden", false)) then
					local name = keyword.name
					if name ~= nil and seenNames[string.lower(name)] == nil then
						seenNames[string.lower(name)] = true
						result[#result+1] = name
					end
				end
			end
		end

		return StringSet.new{ strings = result }
	end,
}

GameSystem.RegisterGoblinScriptField{
	target = Loc,
	name = "Concealment",
	type = "boolean",
	desc = "True if a creature standing at this location would have concealment from the terrain: tiles flagged as granting concealment, or a concealment area (a marked zone or aura) covering the location.",
	seealso = {"Environment"},
	examples = {"target.Concealment"},
	calculate = function(c)
		local engineLoc = rawget(c, "_tmp_loc")
		if engineLoc == nil then
			return false
		end

		--Tile rules: tile art flagged with concealment. The engine also merges
		--"apply to all" auras (markup zones) into this result, matching the
		--tile-rules half of the engine's token hasConcealment check.
		local rules = dmhub.GetTileRulesAtLoc(engineLoc)
		if rules ~= nil and rules.concealment then
			return true
		end

		--Auras: any concealment aura covering the square, band-tested at
		--ground altitude (catches auras that are not "apply to all" and so
		--are absent from the merged tile rules). Per-creature applyto
		--filters are not evaluated for a bare square.
		for _,instance in ipairs(AuraInstancesCoveringSquare(engineLoc)) do
			local ok, concealed = pcall(function() return instance:GetConcealment() end)
			if ok and concealed then
				return true
			end
		end

		return false
	end,
}
