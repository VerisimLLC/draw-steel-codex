local mod = dmhub.GetModLoading()

--This file implements the core rules for spells. Note that spells are a type of Activated Ability and so they
--build on many things from that ActivatedAbility file.

--- @class Spell:ActivatedAbility
--- An ActivatedAbility variant that represents a castable spell, with spell level and slot tracking.
Spell = RegisterGameType("Spell", "ActivatedAbility")

--- @class SpellList
--- @field hidden boolean If true, this list is not shown in UI menus.
--- @field tableName string Data table name ("SpellLists").
--- @field name string Display name.
--- @field spells table<string, boolean> Set of spell ids included in this list.
--- A named collection of spell ids that can be assigned to spellcasting classes.
SpellList = RegisterGameType("SpellList")

SpellList.hidden = false
SpellList.tableName = "SpellLists"
SpellList.name = "New Spell List"

function SpellList.Create(options)
	local args = {
		id = dmhub.GenerateGuid(),
		spells = {}, --map of spell id -> true.
	}

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end
	
	return SpellList.new(args)
end

function SpellList.GetOptions()
	local result = {}
	local t = dmhub.GetTable(SpellList.tableName) or {}
	for k,v in pairs(t) do
		if not v.hidden then
			result[#result+1] = {
				id = k,
				text = v.name,
			}
		end
	end

	table.sort(result, function(a,b) return a.text < b.text end)

	return result
end

--Does this spell use conventional spell slots?
Spell.usesSpellSlots = true

Spell.durationTypes = {
	{
		id = "instant",
		text = "Instantaneous",
		textSingle = "Instantaneous",
		noquantity = true,
	},
	{
		id = "rounds",
		text = "Rounds",
		textSingle = "Round",
	},
	{
		id = "minutes",
		text = "Minutes",
		textSingle = "Minute",
	},
	{
		id = "hours",
		text = "Hours",
		textSingle = "Hour",
	},
	{
		id = "days",
		text = "Days",
		textSingle = "Day",
	},
	{
		id = "indefinite",
		text = "Until Dispelled",
		textSingle = "Until Dispelled",
		noquantity = true,
	},
}

function Spell.OnDeserialize(self)
	ActivatedAbility.OnDeserialize(self)
end

Spell.tableName = "Spells"

Spell.durationTypesById = GetDropdownEnumById(Spell.durationTypes)

Spell.durationType = "instant"
Spell.durationLength = 1

Spell.concentration = false

Spell.isSpell = true

Spell.schools = {
	{
		id = "abjuration",
		text = "Abjuration",
		char = "A",
	},
	{
		id = "conjuration",
		text = "Conjuration",
		char = "C",
	},
	{
		id = "divination",
		text = "Divination",
		char = "D",
	},
	{
		id = "enchantment",
		text = "Enchantment",
		char = "E",
	},
	{
		id = "evocation",
		text = "Evocation",
		char = "V",
	},
	{
		id = "illusion",
		text = "Illusion",
		char = "I",
	},
	{
		id = "necromancy",
		text = "Necromancy",
		char = "N",
	},
	{
		id = "transmutation",
		text = "Transmutation",
		char = "T",
	},
}

Spell.schoolsById = GetDropdownEnumById(Spell.schools)

Spell.schoolsByChar = {}

Spell.componentCost = 0

for _,school in ipairs(Spell.schools) do
	Spell.schoolsByChar[school.char] = school
end

function Spell.Create(options)
	local args = {
		id = dmhub.GenerateGuid(),
		iconid = "ui-icons/skills/1.png",
		name = 'New Ability',
		description = '',
		modifiers = {},
		display = {
			bgcolor = '#ffffffff',
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		},

		actionResourceId = "standardAction",

		--can contain v/s/m pointing to true/true/description of component
		components = {},

		level = 0,
		school = "abjuration",

		range = 5,
		numTargets = 1,
		repeatTargets = false,

		abilityType = ActivatedAbility.TypesById.none,

		behaviors = {},
	}

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return Spell.new(args)
end

local levelDescriptions = {
	"cantrip",
	"1st level",
	"2nd level",
	"3rd level",
	"4th level",
	"5th level",
	"6th level",
	"7th level",
	"8th level",
	"9th level",
}

function Spell:DescribeLevel()
	local level = self.level
	local upcasting = false
	if self:has_key("castingLevel") and self.castingLevel > level then
		level = self.castingLevel
		upcasting = true
	end

	local result = levelDescriptions[level+1] or string.format("level %d", level)

	if upcasting then
		result = string.format("<color=#ffaaaa><b>%s</b></color>", result)
	end

	return result
end

function Spell:DescribeCastingTime()
	local resourceid = self:ActionResource()
	if resourceid ~= nil then
		local resourceTable = dmhub.GetTable("characterResources") or {}
		local resourceInfo = resourceTable[resourceid]
		if resourceInfo ~= nil then
			return string.format("%d %s", self:GetNumberOfActionsCost(), resourceInfo.name)
		end
	end

	if self.castingTime == "action" then
		return "1 action"
	elseif self.castingTime == "bonus" then
		return "1 bonus action"
	else
		return self:try_get("castingTimeDuration", "instant")
	end
end

function Spell:GenerateTextDescription(token)
	return string.format(tr("Level %d %s spell"), self.level, self.school)

end

function ActivatedAbility:DescribeRange()
	if self.targetType == 'self' then
		return 'Self'
	end

	if tonumber(self.range) then

		return string.format("%s %s", MeasurementSystem.NativeToDisplayString(self.range), string.lower(MeasurementSystem.UnitName()))
	else
		local range = self:GetRange() --gets the numeric range in native.
		if range == nil then
			return self.range
		end

		return string.format("%s %s", MeasurementSystem.NativeToDisplayString(range), string.lower(MeasurementSystem.UnitName()))
	end
end

function Spell:DescribeComponents()
	local result = ""
	if self.components.v then
		result = "V"
	end

	if self.components.s then
		if result ~= "" then
			result = result .. ", "
		end

		result = result .. "S"
	end

	if self.components.m then
		if result ~= "" then
			result = result .. ", "
		end

		result = string.format("%sM (%s)", result, self.components.m)
	end

	return result
end

function Spell:DescribeDuration()
	local durationType = self.durationTypesById[self.durationType]
	if durationType.noquantity then
		return durationType.text
	end

	local textType = "text"
	if self.durationLength == 1 then
		textType = "textSingle"
	end

	local concentrationText = ""

	if self.concentration then
		concentrationText = "Concentration, up to "
	end

	return string.format("%s%d %s", concentrationText, self.durationLength, durationType[textType])
end

function Spell:GenerateEditor(options)


	local spellGuidField = nil
	if devmode() then
		spellGuidField = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "GUID:",
			},
			gui.Input{
				classes = "formInput",
				text = self.id,
				editable = false,
			},
		}
	end

	local castEffectOptions = {
		{
			id = "none",
			text = "School Effect",
		},
		{
			id = "empty",
			text = "(None)",
		},
	}

	for k,emoji in pairs(assets.emojiTable) do
		if emoji.emojiType == "Spellcasting" then
			castEffectOptions[#castEffectOptions+1] = {
				id = emoji.description,
				text = emoji.description,
			}
		end
	end

	local ActionHasQuantity = function()
		local resourceid = self:ActionResource() or "none"
		local resourceTable = dmhub.GetTable("characterResources") or {}
		local resourceInfo = resourceTable[resourceid]
		if resourceInfo ~= nil then
			return resourceInfo.useQuantity
		end

		return false
	end

	local resultPanel
	resultPanel = gui.Panel{
		classes = "spellEditor",
		styles = {
			Styles.Form,

			{
				classes = {"formPanel"},
				width = 340,
			},
			{
				classes = {"formLabel"},
				halign = "left",
			},
			{
				classes = {"spellEditor"},
				width = '100%',
				height = 'auto',
				flow = "horizontal",
				valign = "top",
			},
			{
				classes = "mainPanel",
				width = "40%",
				height = "auto",
				flow = "vertical",
				valign = "top",
			},
			{
				classes = "checkbox",
				minWidth = 360,
			},

		},

		gui.Panel{
			id = "leftPanel",
			classes = "mainPanel",
			spellGuidField,

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Name:",
				},
				gui.Input{
					classes = "formInput",
					text = self.name,
					change = function(element)
						self.name = element.text
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Implementation:",
				},
				gui.ImplementationStatusPanel{
					value = self:try_get("implementation", 1),
					change = function(element)
						self.implementation = element.value
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Level:",
				},
				gui.Input{
					classes = "formInput",
					characterLimit = 1,
					text = string.format("%d", math.tointeger(self.level)),
					change = function(element)
						local num = round(tonumber(element.text))
						if num == nil then
							num = self.level
						end

						self.level = num
						element.text = tostring(self.level)
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "School:",
				},

				gui.Dropdown{
					classes = "formDropdown",
					options = Spell.schools,
					idChosen = self.school,
					change = function(element)
						self.school = element.idChosen
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",

				gui.Check{
					id = "verbal-spell-component-check",
					text = "Verbal",
					minWidth = 100,
					value = self.components.v,
					halign = "right",
					change = function(element)
						self.components.v = cond(element.value, true)
					end,
				},

				gui.Check{
					id = "somatic-spell-component-check",
					text = "Somatic",
					minWidth = 100,
					value = self.components.s,
					halign = "right",
					change = function(element)
						self.components.s = cond(element.value, true)
					end,
				},

				gui.Check{
					id = "material-spell-component-check",
					text = "Material",
					minWidth = 100,
					value = self.components.m,
					halign = "right",
					change = function(element)
						self.components.m = cond(element.value, "")
						resultPanel:FireEventTree("refreshSpell")
					end,
				},
			},

			gui.Input{
				classes = "formInput",
				width = "100%",
				halign = "center",
				text = self.components.m or "",
				placeholderText = "Describe spell materials...",
				change = function(element)
					self.components.m = element.text
				end,
				refreshSpell = function(element)
					element:SetClass("hidden", not self.components.m)
				end,
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Casting Time:",
				},

				gui.Dropdown{
					classes = "formDropdown",
					options = CharacterResource.GetActionOptions(),
					idChosen = self:ActionResource(),
					change = function(element)
						self.actionResourceId = element.idChosen
						self:get_or_add("castingTimeDuration", "1 minute")
						resultPanel:FireEventTree("refreshSpell")
					end,
				},
			},

			gui.Panel{
				classes = {"formPanel", cond(not ActionHasQuantity(), "collapsed-anim")},
				refreshAbility = function(element)
					element:SetClass("collapsed-anim", not ActionHasQuantity())
				end,

				gui.Label{
					classes = "formLabel",
					text = "Num. Actions:",
				},

				gui.GoblinScriptInput{
					classes = "formInput",
					value = tostring(self.actionNumber),
					width = 200,
					change = function(element)
						if type(element.value) == "string" and tonumber(element.value) ~= nil then
							self.actionNumber = tonumber(element.value)
							element.value = tostring(self.actionNumber)
						else
							self.actionNumber = element.value
						end
						resultPanel:FireEventTree("refreshAbility")
					end,


					documentation = {
						domains = self.domains,
						help = "This GoblinScript is used to determine how many actions an <color=#00FFFF><link=ability>ability</link></color> costs. It is typically a flat number, but sometimes you may want to calculate the number of actions based on a formula or table.",
						output = "number",
						examples = {
							{
								script = "1",
								text = "The ability costs 1 action to use.",
							},
							{
								script = "1 + 1 when level <= 5",
								text = "The ability costs 2 to use when the character's level is 5 or less, otherwise it only costs one action to use.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature that is using the ability.",
					},
				},

			},

			gui.Input{
				classes = "formInput",
				refreshSpell = function(element)
					element.text = self:try_get("castingTimeDuration", "")
					element:SetClass('hidden', self.castingTime ~= 'duration')
				end,
				change = function(element)
					self.castingTimeDuration = element.text
				end,
			},

			CustomFieldInstance.CreateEditor(self, "spells"),

			self:BehaviorEditor(),
		},

		gui.Panel{
			id = "rightPanel",
			classes = "mainPanel",

			self:IconEditorPanel(),

			gui.Input{
				classes = "formInput",
				placeholderText = "Enter Spell Details...",
				multiline = true,
				width = "80%",
				height = "auto",
				halign = "center",
				margin = 8,
				minHeight = 100,
				textAlignment = "topleft",
				text = self.description,
				change = function(element)
					self.description = element.text
				end,
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Cast Effect:",
				},
				gui.Dropdown{
					classes = "formDropdown",
					options = castEffectOptions,
					idChosen = self:try_get("castingEmote", "none"),
					change = function(element)
						if element.idChosen == "none" then
							self.castingEmote = nil
						else
							self.castingEmote = element.idChosen
						end
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Impact Effect:",
				},
				gui.Dropdown{
					classes = "formDropdown",
					options = castEffectOptions,
					idChosen = self:try_get("impactEmote", "empty"),
					change = function(element)
						if element.idChosen == "empty" then
							self.impactEmote = nil
						else
							self.impactEmote = element.idChosen
						end
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Projectile:",
				},
				gui.Dropdown{
					classes = "formDropdown",
					create = function(element)
						local options = {
							{
								id = "none",
								text = "Choose Projectile...",
							},
						}

						local projectileFolderId = "14d073f8-d00a-4ab4-b184-0545124c9940"
						local objectProjectilesFolder = assets:GetObjectNode(projectileFolderId);
						for i,projectileObject in ipairs(objectProjectilesFolder.children) do
							if not projectileObject.isfolder then
								options[#options+1] = {
									id = projectileObject.id,
									text = projectileObject.description,
								}
							end
						end

						element.options = options
						element.idChosen = self.projectileObject

					end,
					change = function(element)
						self.projectileObject = element.idChosen
					end,
				},
			},
		},

	}

	resultPanel:FireEventTree("refreshSpell")

	return resultPanel

end

function Spell.CalculateUpcast(cost)

	if cost ~= nil then
		for i,entry in ipairs(cost.details) do
			if #entry.paymentOptions > 0 and entry.paymentOptions[1].upcast ~= nil then
				return {
					level = entry.paymentOptions[1].level,
					upcast = entry.paymentOptions[1].upcast,
				}
			end
		end

--	local resourceTable = dmhub.GetTable("characterResources")
--	for i,entry in ipairs(cost.details) do
--		local resource = resourceTable[entry.cost]
--		if resource ~= nil and resource:GetSpellSlot() ~= nil then
--			if entry.paymentOptions[1].resourceid == entry.cost then
--				return {
--					level = resource:GetSpellSlot(),
--					upcast = 0,
--				}
--			elseif #entry.paymentOptions == 0 then
--				return { upcast = 0 } --can't afford.
--			else
--				local otherResource = resourceTable[entry.paymentOptions[1].resourceid]
--				return {
--					level = otherResource:GetSpellSlot(),
--					upcast = otherResource:GetSpellSlot() - resource:GetSpellSlot(),
--				}
--			end
--		end
--	end
	end

	return {
		upcast = 0
	}
end

--returns a { canAfford = bool, details = list }, each item in the list representing a cost that needs to be paid.
--an item in the list is the form { cost = string resourceid, quantity = (optional) number, upcast = (optional) number, level = (optional) number, canAfford = bool, paymentOptions = {{resourceid = string, quantity = number, upcast = (optional)number, level = (optional)number}}, expendedOptions = {{resourceid = string, quantity = number, upcast = (optional)number, level = (optional)number}} }
--the cost+quantity gives the listed resource id cost and quantity, but paymentOptions is a list of resources/quantities the token has which it could use, in preferred order.
--expendedOptions is a list of resources the token has expended which could normally be used to pay.
function Spell.GetCost(self, casterToken, options)

	if not self.usesSpellSlots then
		return ActivatedAbility.GetCost(self, casterToken, options)
	end
	
	local resourcesTable = dmhub.GetTable("characterResources")
	local resourcesAvailable = casterToken.properties:GetResources()

	local result = {}

	local creature = casterToken.properties

	local actionResource = self:ActionResource()
	if actionResource ~= nil and actionResource ~= "none" then
		local max = resourcesAvailable[actionResource] or 0
		local actionResourceInfo = resourcesTable[actionResource]
		local usage = creature:GetResourceUsage(actionResource, actionResourceInfo and actionResourceInfo.usageLimit or "round")
		local available = max - usage

		local numberOfActionsCost = self:GetNumberOfActionsCost(creature, { mode = (options or {}).mode or 1 })

		local canAfford = available >= numberOfActionsCost

		result[#result+1] = {
			cost = actionResource,
			quantity = numberOfActionsCost,
			canAfford = canAfford,
			paymentOptions = cond(canAfford, {{ resourceid = actionResource, quantity = numberOfActionsCost }}, {}),
			expendedOptions = cond(canAfford, {}, {{ resourceid = actionResource, quantity = numberOfActionsCost }}),
		}
	end

	if self:has_key("consumables") then
		result.consumables = self.consumables
	elseif self:has_key("attackOverride") and self.attackOverride:has_key("consumeAmmo") then
		result.consumables = self.attackOverride.consumeAmmo
	end

	if self.level > 0 then
		local canUpcast = true

		local castingLevel = self:try_get("castingLevel") or self.level

		local fixedUpcast = castingLevel - self.level

		local canUseSpellSlots = true

		if self:try_get("spellcastingFeature") ~= nil then
			canUpcast = self.spellcastingFeature.upcastingType == "cast"
			canUseSpellSlots = self.spellcastingFeature.canUseSpellSlots
		end

		local usableSlots = {}
		local expendedSlots = {}
		if canUseSpellSlots then
			for resourceid,quantity in pairs(resourcesAvailable) do
				local resourceInfo = resourcesTable[resourceid]
				if resourceInfo ~= nil and (resourceInfo:GetSpellSlot() or 0) >= castingLevel then
					local entry = {
						resourceid = resourceid,
						level = resourceInfo:GetSpellSlot(),
						available = quantity - casterToken.properties:GetResourceUsage(resourceid, resourceInfo.usageLimit),
					}
					if entry.available > 0 then
						usableSlots[#usableSlots+1] = entry
					else
						expendedSlots[#expendedSlots+1] = entry
					end
				end
			end
		end

		table.sort(usableSlots, function(a,b) return a.level < b.level end)
		table.sort(expendedSlots, function(a,b) return a.level < b.level end)

		local paymentOptions = {}
		local expendedOptions = {}

		for i,option in ipairs(usableSlots) do
			paymentOptions[#paymentOptions+1] = {
				resourceid = option.resourceid,
				quantity = 1,
				upcast = cond(canUpcast, option.level - self.level, fixedUpcast),
				level = option.level,
			}
		end

		for i,option in ipairs(expendedSlots) do
			expendedOptions[#expendedOptions+1] = {
				resourceid = option.resourceid,
				quantity = 1,
				upcast = cond(canUpcast, option.level - self.level, fixedUpcast),
				level = option.level,
			}
		end

		local altPayments = creature:AlternativeSpellcastingCosts(self)
		for _,alt in ipairs(altPayments) do
			local resourceInfo = resourcesTable[alt.resourceid]
			if resourceInfo ~= nil and resourcesAvailable[alt.resourceid] ~= nil then
				local canAfford = (resourcesAvailable[alt.resourceid] - creature:GetResourceUsage(alt.resourceid, resourceInfo.usageLimit)) >= alt.quantity
				if canAfford then
					paymentOptions[#paymentOptions+1] = alt
				else
					expendedOptions[#expendedOptions+1] = alt
				end
			end
		end

		local upcast = 0
		if #paymentOptions > 0 and canUpcast then
			upcast = paymentOptions[1].level - self.level
		else
			upcast = fixedUpcast
		end
		result[#result+1] = {
			cost = string.format("spellSlot-%d", self.level),
			canAfford = #paymentOptions > 0,
			paymentOptions = paymentOptions,
			expendedOptions = expendedOptions,
			upcast = upcast,
		}
	end

	local canAfford = true
	for i,item in ipairs(result) do
		if not item.canAfford then
			canAfford = false
		end
	end

	return { canAfford = canAfford, details = result }
end
