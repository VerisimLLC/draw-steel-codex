local mod = dmhub.GetModLoading()


--- @class equipment
--- @field isWeapon boolean
--- @field isArmor boolean
--- @field isShield boolean
--- @field tableName string Name of the data table for all gear ("tbl_Gear").
--- @field unique boolean If true, only one copy can exist in an inventory.
--- @field flavor string Flavor/lore text.
--- @field weight number Item weight.
--- @field costInGold number Base cost in gold pieces.
--- @field description string Rules text/description.
--- @field consumableChargesConsumed number Number of charges spent so far.

--- @class weapon:equipment
--- @field hands string How many hands required: "One-handed", "Two-handed", or "Versatile".
--- @field category string Weapon category: "Simple" or "Martial".
--- @field damage number Base damage die value.
--- @field damageType string Damage type (e.g. "slashing", "piercing", "bludgeoning").

--- @class armor:equipment
--- @field category string Armor category: "Light", "Medium", or "Heavy".
--- @field armorClass number Base armor class provided.
--- @field stealth string Stealth penalty: "None" or "Disadvantage".

--- @class shield:equipment
--- @field armorClassModifier number Armor class bonus from equipping this shield.

--Types defined as core types by DMHub.
equipment = RegisterGameType("equipment")

weapon = RegisterGameType("weapon", "equipment")
armor = RegisterGameType("armor", "equipment")
shield = RegisterGameType("shield", "equipment")

equipment.tableName = "tbl_Gear"
equipment.equipmentTypes = {"Weapon", "Armor", "Shield", "Gear"}

--default image of a crate.
equipment.iconid = 'f5475490-42a4-4c1b-b3c2-40949501d5f3'

equipment.unique = false
equipment.flavor = ""

equipment.isWeapon = false
equipment.isArmor = false
equipment.isShield = false

equipment.weight = 1
equipment.costInGold = 0
equipment.description = ''

equipment.consumableChargesConsumed = 0

weapon.isWeapon = true
armor.isArmor = true
shield.isShield = true

weapon.possibleCategories = {'Simple', 'Martial'}
weapon.handOptions = {'One-handed', 'Two-handed', 'Versatile'}
weapon.hands = 'One-handed'
weapon.category = 'Simple'
weapon.damage = 1
weapon.damageType = 'slashing'

armor.possibleCategories = {'Light', 'Medium', 'Heavy'}
armor.category = 'Light'
armor.armorClass = 10

armor.stealth = 'None'
armor.possibleStealth = {'None', 'Disadvantage'}

shield.armorClassModifier = 2

--- @return string
function equipment:CategoryId()
    return self:try_get("equipmentCategory", "")
end

--- @return boolean
function equipment:IsEquippable()
	return self.isWeapon or self.isArmor or self.isShield or self:try_get("canWield", false) or self:try_get("equipOnBelt", false) or self:try_get("emitLight", false)
end

--- @return boolean
function equipment:HasCharges()
	return self:try_get("consumable") and self:try_get("consumableCharges", 1) > 1
end

--- @return number
function equipment:MaxCharges()
	return self:try_get("consumableCharges", 1)
end

--- @param n number
function equipment:ConsumeCharges(n)
	self.consumableChargesConsumed = self.consumableChargesConsumed + n
end

--- @return number
function equipment:RemainingCharges()
	return self:try_get("consumableCharges", 1) - self.consumableChargesConsumed
end

--- @return boolean
function equipment:MustBeUniqueInInventory()
	return self:HasCharges()
end

--- Returns a map of currency id to quantity cost.
--- @return table<string, number>
--gives a {currencyid -> quantity cost}.
function equipment:GetCurrencyCost()
	if self:has_key("costInCurrency") then
		return self.costInCurrency
	end

	return Currency.CalculateSpend(nil, self.costInGold)
end

--- @param costmap table<string, number>
function equipment:SetCurrencyCost(costmap)
	self.costInCurrency = costmap
end

--- @return number
function equipment:GetCostInGold()
	if self:has_key("costInCurrency") then

		return Currency.CalculatePriceInStandard(self.costInCurrency)
	end

	return self.costInGold
end

--- @return boolean
function equipment:CanWield()
	return self.isWeapon or self.isShield or self:try_get("emitLight") ~= nil or self:try_get("canWield")
end

--- @return boolean
function equipment:Magic()
	return self:try_get("magicalItem")
end

function equipment:GetWieldObject()
	local assetid = self:try_get("itemObjectId")
	if assetid ~= nil then
		return {
			assetid = assetid,
			zorder = 1,
			pos = {
				x = 0,
				y = 0,
			}
		}
	end

	local light = nil
	if self:has_key("emitLight") then
		light = {
			["@class"] = "ObjectComponentLight",
			radius = self.emitLight.radius,
			angle = 360,
			flicker = 0.2,
			color = {
				r = self.emitLight.color.r,
				g = self.emitLight.color.g,
				b = self.emitLight.color.b,
				a = self.emitLight.color.a,
			}
		}
	end

	return {
		asset = {
			description = "Item",
			imageId = dmhub.GetRawImageId(self.iconid),
			hidden = false,
		},
		components = {
			CORE = {
				["@class"] = "ObjectComponentCore",
				hasShadow = true,
				height = 3,
				pivot_x = 0.5,
				pivot_y = 0.5,
				rotation = 0,
				scale = 0.2,
				sprite_invisible_to_players = false,
				sublayer = "EffectsAboveTokens",
			},
			LIGHT = light,
			WIELD = {
				["@class"] = "ObjectComponentWield",
				offsetx = 0,
				offsety = 0,
			},
		},
		assetid = "none",
		inactive = false,
		zorder = 1,
		pos = {
			x = 0,
			y = 0,
		}
	}
end

equipment.rarities = {
	{
		id = "common",
		text = "Common",
	},
	{
		id = "uncommon",
		text = "Uncommon",
	},
	{
		id = "rare",
		text = "Rare",
	},
	{
		id = "very rare",
		text = "Very Rare",
	},
	{
		id = "legendary",
		text = "Legendary",
	},
}

equipment.rarityToIndex = {}
for i,entry in ipairs(equipment.rarities) do
	equipment.rarityToIndex[entry.id] = i
end

equipment.rarityColors = {
	common = "white",
	uncommon = "#256f5a",
	rare = "#313baa",
	["very rare"] = "#6c146e",
	legendary = "#f1cc46",
}

function equipment:TranslationStrings()
	return {
		self:try_get("name"),
		self:try_get("description"),
		self:try_get("hands"),
		self:Rarity(),
	}
end

--- @return boolean
function equipment:DisplayOnToken()
	return self:try_get("displayOnToken", true) and self.iconid ~= ""

end

--- @return string Color string for this item's rarity.
function equipment:RarityColor()
	return equipment.rarityColors[self:Rarity()] or "white"
end

--- @return string Rarity string (e.g. "common", "uncommon", "rare").
function equipment:Rarity()
	return self:try_get("rarity", "common")
end

--- @return integer
function equipment:RarityOrd()
	return equipment.rarityToIndex[self:try_get("rarity", "common")]
end

--- @return number Probability (0-1) that ammo is destroyed on use.
function equipment:AmmoDestroyChance()
	if self:has_key("destroyChance") then
		return self.destroyChance/100
	end

	--missiles such as arrows have a 50% chance to be destroyed, while thrown weapons such as daggers or javelins are not destroyed.
	if self.isWeapon and self:HasProperty("thrown") then
		return 0
	end

	return 0.5
end

--- @return string
function equipment:Domain()
	return string.format("item:%s", self.id)
end

equipment._tmp_ensured_domain = false

equipment.EnsureDomains = CharacterFeature.EnsureDomains
equipment.SetDomain = CharacterFeature.SetDomain

function equipment.OnDeserialize(self)
    if self.iconid == "" then
        --clear out iconid to use default.
        self.iconid = nil
    end

	if type(self.weight) ~= "number" then
		if type(self.weight) == "string" then
			local i,j = string.find(self.weight, "%d+")
			if i ~= nil then
				local str = string.sub(self.weight, i, j)
				self.weight = tonumber(str)
			else
				self.weight = nil
			end

		else
			self.weight = nil
		end
	end

	if self:try_get("modifiers") then
		local features = self:get_or_add("features", {})
		local feature = CharacterFeature.Create{
			name = "Imported Feature",
			modifiers = self.modifiers,
		}

		features[#features+1] = feature

		self.modifiers = nil
	end
end

function weapon.OnDeserialize(self)
	equipment.OnDeserialize(self)

	for _,entry in ipairs(weapon.builtinWeaponProperties) do
		if self:try_get(entry.attr) ~= nil then
			self:SetProperty(entry.attr, self[entry.attr])

			--this seems a bit dangerous. Definitely don't clear range.
			--self[entry.attr] = nil
		end
	end
end

--- @return table
function equipment:Properties()
	local result = self:try_get("properties")
	if result == nil then
		result = {}
		self.properties = result
	end

	return result
end

--- @param propid string
--- @param val any
function equipment:SetProperty(propid, val)
	self:Properties()[propid] = val
end

--- @param propid string
--- @return boolean
function equipment:HasProperty(propid)
	local properties = self:try_get("properties")
	if properties == nil then
		return false
	end

	return properties[propid] ~= nil
end

function equipment:RemoveProperty(propid)
	local properties = self:try_get("properties")
	if properties == nil then
		return false
	end

	properties[propid] = nil
end

weapon.builtinWeaponProperties = {
}

function equipment.GetIcon(self)

	return self.iconid
end

--This gives us the number of items that are normally traded for this item type.
--e.g. most items just have 1, but something like arrows might have 20.
function equipment:TradedQuantity()
	if EquipmentCategory.quantityCategories[self:try_get("equipmentCategory", "")] and self:has_key("massQuantity") then
		return math.max(1, self.massQuantity)
	end

	return 1
end

function equipment:IsAmmoForWeapon()
	return self:has_key("equipmentCategory") and EquipmentCategory.quantityCategories[self.equipmentCategory] and not self:HasProperty("thrown")
end

function equipment:AmmoModifyAbility(creature, ability)
	if self:has_key("ammoAugmentation") then
		CharacterModifier.TypeInfo.modifyability.modifyAbility(self.ammoAugmentation, creature, ability)
	end
end

function equipment:WeaponModifyAbility(creature, ability)
	if self:has_key("weaponBehavior") then
		CharacterModifier.TypeInfo.modifyability.modifyAbility(self.weaponBehavior, creature, ability)
	end

	--see if any of the weapon's properties have modifiers on them.
	for k,v in pairs(self:try_get("properties", {})) do
		local propertyInfo = WeaponProperty.Get(k)
		if propertyInfo ~= nil and propertyInfo.modifiesAttacks then
			CharacterModifier.TypeInfo.modifyability.modifyAbility(propertyInfo.attackModifier, creature, ability)
		end
	end
end

function equipment:MatchesSearch(self, str)
	if string.find(string.lower(self.name), str) then
		return true
	end

	if self.isWeapon and string.find("weapon", str) then
		return true
	end

	if self.isArmor and string.find("armor", str) then
		return true
	end

	if self.isShield and string.find("shield", str) then
		return true
	end

	return false
end

--- When worn, fills result with the modifiers this item applies to a creature.
--- @param creature creature
--- @param result CharacterModifier[]
--when worn, this fills in the modifiers it applies to a creature.
function equipment:FillWornArmorModifiers(creature, result)
end

--- @return string
function weapon.DescribeDamageType(self)
	if self:try_get('damageMagical') then
		return 'magical ' .. self.damageType
	end

	return self.damageType
end

--- @return string
function weapon.DescribeDamage(self)
	if self:has_key('versatileDamage') then
		return '<b>' .. self.damage .. '/' .. self.versatileDamage .. '</b> ' .. self:DescribeDamageType() .. ' damage'
	else
		return '<b>' .. self.damage .. '</b> ' .. self:DescribeDamageType() .. ' damage'
	end
end

--- @return boolean
function equipment:Versatile()
	return self:try_get("hands") == "Versatile"
end

--- @return boolean
function equipment:TwoHanded()
	return self:try_get("hands") == "Two-handed"
end

--- @return string
function weapon.GetHands(self)
	return self.hands
end

--- @return string
function weapon.InfoSummary(self)
	local result = ''

	if self.hands == 'Two-handed' then
		result = result .. 'two-handed '
	elseif self.hands == 'Versatile' then
		result = result .. 'versatile '
	end

	if self:has_key('range') then
		result = result .. 'ranged (' .. self.range .. ') '
	end

	for k,v in pairs(self:try_get("properties", {})) do
		result = result .. k .. ' '
	end

	return result
end

--- @return boolean
function weapon.IsRanged(self)
	return self:HasProperty("range") or self:HasProperty("thrown")
end

--- @return nil|string
function weapon.Range(self)
	if self:has_key('range') and self.range ~= false then
		return self.range
	end

	if self:try_get('reach', false) then
		return '10'
	end

	return '5'
end

function weapon.HitBonus(self)
	return self:try_get('hitbonus', 0)
end

function armor.DescribeArmorClass(self)
	return '' .. self.armorClass .. ' Armor Class'
end

function shield.DescribeArmorClass(self)


	--return '+' .. self.armorClassModifier .. ' Armor Class'
	return '+2 Armor Class'
end

function armor.DescribeDetails(self, character)
	local result = ''
	if self:has_key('strength') then
		result = result .. self.strength .. ' Strength '
	end

	if self:has_key('stealth') then
		result = result .. ' Stealth: Disadvantage '
	end

	if self:has_key('dexterityLimit') then
		result = result .. 'Dex. Limit: ' .. self.dexterityLimit
	end

	return result
end

function shield.ArmorClassModifier(self)
	return self:try_get("armorClassModifier", 2)
end

weapon.availableProperties = {
	{ text = 'Range', attr = 'range', value = '60/120' },

	{ text = 'Ammo', attr = 'ammo', value = true },

	{ text = 'Thrown', attr = 'thrown', value = true },

	{ text = 'Loading', attr = 'loading', value = true },

	{ text = 'Light', attr = 'light', value = true },
	{ text = 'Heavy', attr = 'heavy', value = true },

	{ text = 'Finesse', attr = 'finesse', value = true },

	{ text = 'Reach', attr = 'reach', value = true },

	--work out what to do with special abilities later. For now just put anything like that under 'description'.
	--{ text = 'Special', attr = 'specialDescription', value = '' },
}

weapon.propertiesByKey = {}

for i,p in ipairs(weapon.availableProperties) do
	weapon.propertiesByKey[p.attr] = p
end

--Get a list of all the properties this weapon doesn't have yet.
---@return [string]
function weapon:GetAvailableProperties()
	local result = {}
	for i,p in ipairs(weapon.availableProperties) do
		if (not self:has_key(p.attr)) and (not p:try_get("hidden", false)) then
			result[#result+1] = p
		end
	end
	return result
end

equipment.lookupSymbols = {
	self = function(c)
		return c
	end,
	debuginfo = function(c)
		return string.format("equipment: %s", c.name)
	end,

	name = function(weapon)
		if weapon:has_key("baseid") then
			local itemTable = dmhub.GetTable('tbl_Gear')
			local baseItem = itemTable[weapon.baseid]
			if baseItem ~= nil then
				return baseItem.name
			end
		end

		return weapon.name
	end,

	isweapon = function(weapon)
		return false
	end,



	properties = function(item)
		local result = {}

		if item:has_key("properties") then
			for k,v in pairs(item.properties) do
				local propertyInfo = WeaponProperty.Get(k)
				if propertyInfo ~= nil then
					result[#result+1] = propertyInfo.name
				end
			end
		end

		return StringSet.new{
			strings = result,
		}
	end,

	propertyvalue = function(item)
		return function(key)
			if not item:has_key("properties") then
				return 0
			end

			local keyLower = string.gsub(string.lower(key), "%s", "")
			for k,v in pairs(item.properties) do
				local propertyInfo = WeaponProperty.Get(k)
				if propertyInfo ~= nil and string.gsub(string.lower(propertyInfo.name), "%s", "") == keyLower then
					if type(v) == "table" then
						return v.value or 1
					end

					return 1
				end
			end


			return 0
		end
	end,


}

equipment.helpSymbols = {
	name = {
		name = "Name",
		type = "text",
		desc = "Name of the item",
	},

	isweapon = {
		name = "Is Weapon",
		type = "boolean",
		desc = "True if this item is a weapon.",
	},

	properties = {
		name = "Properties",
		type = "set",
		desc = "The names of any properties the item has.",
		examples = {'Armor.Properties Has "Heavy"'}
	},

	propertyvalue = {
		name = "Property Value",
		type = "function",
		desc = "A function which provides the value of the property given to it.",
		examples = {'Armor.PropertyValue("CustomRuneBonus")'},

	},
}


weapon.lookupSymbols = {

	debuginfo = function(c)
		return string.format("weapon: %s", c.name)
	end,

	isweapon = function(weapon)
		return true
	end,

	finesse = function(weapon)
		return weapon:HasProperty("finesse")
	end,

	melee = function(weapon)
		return cond(EquipmentCategory.meleeWeaponCategories[weapon:try_get("equipmentCategory", "")], true, false)
	end,

	ranged = function(weapon)
		return (not cond(EquipmentCategory.meleeWeaponCategories[weapon:try_get("equipmentCategory", "")], true, false)) or weapon:has_key("thrown")
	end,

	thrown = function(weapon)
		return weapon:has_key("thrown")
	end,

	twohanded = function(weapon)
		return weapon.hands == "Two-handed"
	end,

	heavy = function(weapon)
		return weapon:has_key("heavy")
	end,

	martial = function(weapon)
		return cond(EquipmentCategory.martialWeaponCategories[weapon:try_get("equipmentCategory", "")], true, false)
	end,

	simple = function(weapon)
		return not cond(EquipmentCategory.martialWeaponCategories[weapon:try_get("equipmentCategory", "")], true, false)
	end,

}

weapon.helpSymbols = {
	__name = "weapon",
	__sampleFields = {"finesse", "melee"},

	finesse = {
		name = "Finesse",
		type = "boolean",
		desc = "True if this weapon is a finesse weapon.",
	},
	melee = {
		name = "Melee",
		type = "boolean",
		desc = "True if this weapon is a melee weapon.",
		seealso = {"Ranged"},
	},
	ranged = {
		name = "Ranged",
		type = "boolean",
		desc = "True if this weapon is a ranged weapon.",
		seealso = {"Melee"},
	},
	thrown = {
		name = "Thrown",
		type = "boolean",
		desc = "True if this weapon is a thrown weapon.",
		seealso = {"Ranged"},
	},
	heavy = {
		name = "Heavy",
		type = "boolean",
		desc = "True if this weapon is a heavy weapon.",
	},
	twohanded = {
		name = "Twohanded",
		type = "boolean",
		desc = "True if this weapon is a Two-handed weapon.",
	},

	simple = {
		name = "Simple",
		type = "boolean",
		desc = "True if this weapon is a Simple weapon.",
		seealso = {"Martial"},
	},
	martial = {
		name = "Martial",
		type = "boolean",
		desc = "True if this weapon is a Martial weapon.",
		seealso = {"Simple"},
	},
}


for k,sym in pairs(equipment.lookupSymbols) do
	if weapon.lookupSymbols[k] == nil then
		weapon.lookupSymbols[k] = equipment.lookupSymbols[k]
		weapon.helpSymbols[k] = equipment.helpSymbols[k]
	end
end

function equipment:RenderToMarkdown(options)
    local tokens = {}
    tokens[#tokens+1] = string.format("## %s\n", self.name)

    if self.flavor ~= "" then
        tokens[#tokens+1] = string.format("*%s*\n\n", self.flavor)
    else
        tokens[#tokens+1] = "\n"
    end

    local iconid = self:try_get("iconid")

    if iconid then
        tokens[#tokens+1] = "[[image:main]]\n"
    end
    
    if EquipmentCategory.IsTreasure(self) then
        local kwList = table.mapped_keys(self:try_get("keywords", {}), ActivatedAbility.CanonicalKeyword)
        table.sort(kwList)
        tokens[#tokens+1] = string.format("**Keywords:** %s\n", #kwList > 0 and table.concat(kwList, ", ") or "-")
        tokens[#tokens+1] = string.format("**Item Prerequisites:** %s\n", self:try_get("itemPrerequisite", "None"))
        tokens[#tokens+1] = string.format("**Project Source:** %s\n", self:try_get("projectSource", "None"))

        local characteristics = {}
        local characteristicKeys = table.keys(self:try_get("projectRollCharacteristic", {}))
        table.sort(characteristicKeys, function(a,b) return creature.attributesInfo[a].order < creature.attributesInfo[b].order end)
        for _,char in ipairs(characteristicKeys) do
            characteristics[#characteristics+1] = creature.attributesInfo[char].description
        end

        if #characteristics == 0 then
            characteristics = {"-"}
        end

        if #characteristics <= 2 then
            characteristics = table.concat(characteristics, " or ")
        else
            characteristics[#characteristics] = "or " .. characteristics[#characteristics]
            characteristics = table.concat(characteristics, ", ")
        end

        tokens[#tokens+1] = string.format("**Project Roll Characteristic:** %s\n", characteristics)
        tokens[#tokens+1] = string.format("**Project Goal:** %s\n", self:try_get("projectGoal", "-"))

        if EquipmentCategory.IsLeveledTreasure(self) then
            tokens[#tokens+1] = string.format("\n**1st Level:** %s", trim(self.description))
            if self:has_key("level5") then
                tokens[#tokens+1] = string.format("\n\n**5th Level:** %s", trim(self.level5))
            end
            if self:has_key("level9") then
                tokens[#tokens+1] = string.format("\n\n**9th Level:** %s", trim(self.level9))
            end
        else
            tokens[#tokens+1] = string.format("\n**Effect:** %s", self.description)
        end
    else
        tokens[#tokens+1] = self.description
    end

    if (not options.noninteractive) and dmhub.isDM then
        tokens[#tokens+1] = "\n\n:<>"
        for key,token in pairs(Party.GetPlayerCharacters()) do
            if token.name ~= "" then
                tokens[#tokens+1] = string.format("[[/giveitem \"%s\" %s 1|Give to %s]]", token.name, self.id, token.name)
            end
        end

        tokens[#tokens+1] = "\n"
    end


    return MarkdownDocument.new{
        id = dmhub.GenerateGuid(),
        description = self.name,
        content = table.concat(tokens, ""),
        annotations = {
            ["image:main"] = RichImage.new{
                image = iconid,
                maxWidth = 200,
            }
        },
    }
end

MarkdownRender.Register(equipment)
MarkdownRender.RegisterTable{tableName = "tbl_Gear", prefix = "item"}

function equipment:Render(options, token)
    options = options or {}
    options.token = token
    return MarkdownRender.RenderToPanel(self, options)
end

function equipment:RenderOld(options, token)
	options = options or {}
	local summary = options.summary
	options.summary = nil


	local item = self

	local infoItems = {}

	local itemType = item.type

	local catsTable = dmhub.GetTable('equipmentCategories') or {}
	local cat = catsTable[item:try_get("equipmentCategory", '')]
	if cat ~= nil then
		itemType = cat.name
	end

	if item.isWeapon then

		if item:try_get('hitbonus') then
			infoItems[#infoItems+1] = gui.Label{
				text = string.format("%s to hit", ModifierStr(item.hitbonus)),
			}
		end

		infoItems[#infoItems+1] = gui.Label{
			text = item:DescribeDamage(),
		}

		if item:has_key('range') then
			infoItems[#infoItems+1] = gui.Label{
				text = string.format("Ranged (%s feet)", item.range),
			}
		end

		if item:has_key("properties") then
			for k,v in pairs(item.properties) do
				local propertyInfo = WeaponProperty.Get(k)
				if propertyInfo ~= nil then
					local num = ""

					if propertyInfo.hasValue then
						local n = 1
						if type(v) == "table" then
							n = v.value or n
						end

						num = string.format(" %d", n)
					end

					infoItems[#infoItems+1] = gui.Label{
						classes = {cond(propertyInfo.details ~= "", "hasTooltip")},
						text = string.format("%s%s", propertyInfo.name, num),
						hover = function(element)
							if propertyInfo.details ~= "" then
								gui.Tooltip(propertyInfo.details)(element)
							end
						end,
					}

				end
			end
		end

		local keywords = ''
		for key,v in pairs(weapon:try_get("properties", {})) do
			local propertyInfo = WeaponProperty.Get(key)
			if propertyInfo ~= nil then
				if keywords ~= '' then
					keywords = keywords .. ', '
				end

				keywords = keywords .. property.name
			end
		end

		if keywords ~= '' then
			infoItems[#infoItems+1] = gui.Label{
				text = keywords,
			}
		end

	elseif item.isArmor then

		infoItems[#infoItems+1] = gui.Label{
			text = string.format("%d Armor Class", math.tointeger(item.armorClass)),
		}

		if item:has_key('strength') and tonumber(item.strength) ~= nil then
			infoItems[#infoItems+1] = gui.Label{
				text = string.format("%d Strength Required", math.tointeger(tonumber(item.strength))),
			}
		end

		if item:try_get('stealth', 'None') == 'Disadvantage' then
			infoItems[#infoItems+1] = gui.Label{
				text = 'Disadvantage on Stealth Checks',
			}
		end

		if item:has_key('dexterityLimit') then
			infoItems[#infoItems+1] = gui.Label{
				text = string.format('+%d Dexterity modifier limit', math.tointeger(item.dexterityLimit)),
			}
		end
	elseif item.isShield then
		infoItems[#infoItems+1] = gui.Label{
			text = string.format("+%d Armor Class", math.tointeger(item.armorClassModifier)),
		}
	end

	if item:has_key('emitLight') then
		local radius = item.emitLight:RadiusInFeet()
		local angle = item.emitLight.angle
		local angleDesc = 'radius'
		if angle < 100 then
			angleDesc = 'cone'
		end
		infoItems[#infoItems+1] = gui.Label{
			text = string.format("Casts bright light in a %d foot %s and dim light for an additional %d feet.", math.tointeger(item.emitLight:BrightRadiusInFeet()), angleDesc, math.tointeger(item.emitLight:DimRadiusInFeet())),
		}
	end

	local costPanel = nil
	local currencies = options.costOverride or item:GetCurrencyCost()
	options.costOverride = nil
	if currencies ~= nil then
		local panels = {}

		local currencyTable = dmhub.GetTable(Currency.tableName)
		for currencyid,amount in pairs(currencies) do
			local currencyInfo = currencyTable[currencyid]
			if currencyInfo ~= nil and not currencyInfo:try_get("hidden", false) then
				local panel = gui.Panel{
					flow = "horizontal",
					width = "auto",
					height = "auto",
					data = {
						ord = currencyInfo.value
					},
					gui.Panel{
						bgcolor = "white",
						bgimage = currencyInfo.iconid,
						width = 16,
						height = 16,
						valign = "center",
					},
					gui.Label{
						width = "auto",
						height = "auto",
						color = "white",
						fontSize = 14,
						hmargin = 4,
						valign = "center",
						text = string.format("%d", math.tointeger(round(amount)) or 0)
					},
				}

				panels[#panels+1] = panel
			end
		end

		table.sort(panels, function(a,b) return a.data.ord > b.data.ord end)

		costPanel = gui.Panel{
			width = "auto",
			height = "auto",
			children = panels,
			halign = "left",
		}
	end

	local weightPanel = gui.Panel{
		width = "auto",
		height = "auto",
		halign = "left",
		flow = "horizontal",
		gui.Panel{
			bgcolor = Styles.textColor,
			bgimage = mod.images.weight,
			width = 16,
			height = 16,
			valign = "center",
		},
		gui.Label{
			color = "white",
			fontSize = 14,
			hmargin = 4,
			width = "auto",
			height = "auto",
			text = tostring(item:try_get("weight", 0)),
		},
	}

	local effectPanel = nil
	local itemEffect = item:try_get('iconEffect')
	if itemEffect ~= nil and ItemEffects[itemEffect] then
		local effect = ItemEffects[itemEffect]
		effectPanel = gui.Panel{
			bgimage = effect.video,
			bgimageMask = cond(effect.mask, item:GetIcon()),
			style = {
				opacity = effect.opacity,
				width = "100%",
				height = "100%",
			},
		}
	end

	local iconPanel = gui.Panel{
		style = {
			bgcolor = 'white',
			halign = "left",
			width = 160,
			height = 160,
			margin = 0,
			pad = 0,
			flow = 'none',
		},

		children = {
			gui.Panel{
				bgimage = item:GetIcon(),
				style = {
					width = 160,
					height = 160,
				},
				loadingImage = function(element)
					element:AddChild(gui.LoadingIndicator{})
				end,
			},
			effectPanel,
		}
	}

	local uniqueLabel = nil
	if item.unique and item:try_get('baseid') then
		local baseItem = dmhub.GetTable('tbl_Gear')[item.baseid]
		if baseItem ~= nil then
			uniqueLabel = gui.Label{
				text = string.format("(%s)", tr(baseItem.name)),
			}
		end
	end

	local proficientLabel = nil

	if token ~= nil and token.properties ~= nil then
		--see if the token is proficient with this item, if the item has proficiency. Monsters do not list proficiency, and are generally always considered proficient.
		if cat ~= nil and (cat.allowProficiency or cat.allowIndividualProficiency) and token.type == "token" and not token.properties:IsMonster() then
			local proficient = token.properties:ProficientWithItem(item)
			if proficient ~= nil then
				proficientLabel = gui.Label{
					text = cond(proficient, "Proficient", "Not Proficient"),
					color = cond(proficient, "#caffca", "#ffcaca"),
					fontSize = 14,
				}
			end
		end
	end

	local ammoInfoPanel = nil
	if token ~= nil and token.properties ~= nil and item.isWeapon and item:HasProperty("ammo") and item:has_key("ammunitionType") then
		local ammunitionQuantity = 0
		local gearTable = dmhub.GetTable('tbl_Gear')
		local ammoName = nil
		local ammoLabels = {}
		for k,entry in pairs(token.properties:try_get("inventory", {})) do
			local gearEntry = gearTable[k]
			if gearEntry ~= nil then
				if gearEntry:try_get("equipmentCategory") == item.ammunitionType then
					ammunitionQuantity = ammunitionQuantity + entry.quantity

					ammoLabels[#ammoLabels+1] = gui.Label{
						width = "auto",
						height = "auto",
						text = string.format("%s x %d", tr(gearEntry.name), math.tointeger(entry.quantity)),
						color = "#caffca",
						fontSize = 14,
					}

				end
			end
		end

		if #ammoLabels == 0 then
			ammoLabels[#ammoLabels+1] = gui.Label{
				width = "auto",
				height = "auto",
				text = "No ammunition",
				color = "#ffcaca",
				fontSize = 14,
			}
		end

		ammoInfoPanel = gui.Panel{
			flow = "vertical",
			height = "auto",
			width = "auto",
			children = ammoLabels,
		}
	end

	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		styles = Styles.ItemTooltip,

		gui.Label{
			text = tr(item.name),
			classes = {"title"},

			color = equipment.rarityColors[item:try_get("rarity", "common")],
		},

		uniqueLabel,

		proficientLabel,
		ammoInfoPanel,

		gui.Panel{
			bgimage = 'panels/square.png',
			style = {
				bgcolor = 'grey',
				width = '100%',
				height = 1,
				halign = 'center',
				valign = 'top',
			},
		},

		gui.Label{
			text = itemType,
			style = {
				bold = true,
				height = 'auto',
				width = '100%',
				halign = 'left',
				valign = 'top',
			}
		},

		costPanel,
		weightPanel,

		iconPanel,

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			children = infoItems,
		},

		gui.Label{
			text = tr(item.description),
			height = 'auto',
			width = '100%',
			textWrap = true,
			halign = 'left',
			valign = 'top',
		},
	}
end

function equipment.GetMundaneItems()
	local t = dmhub.GetTable(equipment.tableName)

	local result = {}

	for k,item in pairs(t) do
    	if item:try_get("hidden", false) == false and (not item:has_key("uniqueItem")) and (not item:has_key("magicalItem")) and (not EquipmentCategory.IsTreasure(item)) then
			result[k] = item
		end
	end

	return result
end
