local mod = dmhub.GetModLoading()


--This file implements the important Creature type, which is a base type for both characters and monsters.

RegisterGameType("GameSystem")

--- @class StatHistoryEntry
--- @field note string
--- @field disposition string
--- @field set number
--- @field timestamp number
--- @field userid string
--- @field attackerid nil|string
--- @field refreshid nil|string

--- @class StatHistory Keeps history of a stat.
--- @field entries StatHistoryEntry[] The list of entries the stat history has.
RegisterGameType("StatHistory")

function StatHistory.Create()
	return StatHistory.new{
		entries = {}
	}
end

--- append a stat history entry. data is a table which might include note = string description and set = value.
--- @field data StatHistoryEntry
function StatHistory:Append(data)
	data["timestamp"] = ServerTimestamp()
	data["userid"] = dmhub.userid

	--we have a limit of 8 entries, so evict the oldest one.
	local maxEntries = 8
	local evictKey = nil
	local evictTime = nil
	for k,v in pairs(self.entries) do
		maxEntries = maxEntries-1
		if type(v.timestamp) == "number" and (evictKey == nil or v.timestamp < evictTime) then
			evictTime = v.timestamp
			evictKey = k
		end
	end

	if evictKey ~= nil and maxEntries <= 0 then
		self.entries[evictKey] = nil
	end

	self.entries[dmhub.GenerateGuid()] = data
end

--- Gets a formatted history display.
--- @return {color: string, when: string, who: string, value: number, note: string}
function StatHistory:GetHistory()
	local orderedEntries = {}
	for k,v in pairs(self.entries) do
		orderedEntries[#orderedEntries+1] = v
	end

	table.sort(orderedEntries,
		function(a,b)
			if type(a.timestamp) == "number" and type(b.timestamp) == "number" then
				return a.timestamp < b.timestamp
			end

			return type(b.timestamp) == "number"
		end
	)

	local result = {}
	for i,v in ipairs(orderedEntries) do
		local color = '#ccccccff'
		if v.disposition == 'good' then
			color = '#ccffccff'
		elseif v.disposition == 'bad' then
			color = '#ffccccff'
		end
		result[#result+1] = {
			who = dmhub.GetDisplayName(v.userid),
			color = color,
			when = DescribeServerTimestamp(v.timestamp),
			value = v.set,
			note = v.note or "Manually set",
		}
	end

	return result
end

--- The history entries.
--- @return StatHistoryEntry[]
function StatHistory:Entries()
	return self.entries
end

--- Get the timestamp of the most recent entry with the given attackerid and disposition.
--- @param attackerid string
--- @param disposition string
--- @return nil|number
function StatHistory:MostRecentTimestamp(attackerid, disposition)
	local timestamp = nil
	for _,entry in pairs(self.entries) do
		if entry.attackerid == attackerid and entry.disposition == disposition then
			if timestamp == nil or entry.timestamp > timestamp then
				timestamp = entry.timestamp
			end
		end
	end

	return timestamp
end

--- @class CharacterAttribute
--- @field baseValue number

RegisterGameType("CharacterAttribute")


--- Given a number of a modifier returns it as a string, with a + or - on the front as appropriate.
--- @param num number
--- @return string
function ModifierStr(num)
	if num >= 0 then
		return string.format("+%d", math.tointeger(num))
	else
		return string.format("%d", math.tointeger(num))
	end
end

CharacterAttribute.baseValue = 10

--- Gets the value of the attribute
--- @return number
function CharacterAttribute:Value()
	return math.tointeger(self.baseValue)
end

--- Gets the modifier for the attribute
--- @return number
function CharacterAttribute:Modifier()
	local n = CharacterAttribute.Value(self)
	return GameSystem.CalculateAttributeModifier(self, n)
end

--- Gets the modifier string for the attribute.
--- @return string
function CharacterAttribute.ModifierStr(self)
	local result = CharacterAttribute.Modifier(self)
	if result > 0 then
		return '+' .. result
	else
		return '' .. result
	end
end

--- @class creature
--- @field max_hitpoints number
--- @field sizes string[] @This is populated by the game system to have available creature sizes.
--- @field sizeToNumber table<string,number>
--- @field proficientWithAllWeapons boolean
--- @field movementTypeInfo {id: string, name: string, tense: string, verb: string, icon:string}[]
--- @field movementTypeById table<string, {id: string, name: string, tense: string, verb: string, icon:string}>
--- @field movementTypes string[]
--- @field movementTypesTable table<string, boolean>
--- @field damage_taken number
--- @field selectedLoadout integer
--- @field numLoadouts integer
--- @field creatureSize nil|string
creature = RegisterGameType("creature")

--- @class monster:creature
monster = RegisterGameType("monster", "creature")

--- @alias Creature creature
--- @alias Monster monster

creature._tmp_aicontrol = 0

creature.max_hitpoints = 1

--these will be populated by the game system.
creature.sizes = {
}
creature.sizeToNumber = {}

creature.proficientWithAllWeapons = false

dmhub.SetTokenSize = function(tok, sizeid)
	if tok.properties == nil then
		return
	end

	tok:ModifyProperties{
		description = "Resized token",
		execute = function()
			tok.properties:SetSizeOverride(sizeid)
		end,
	}
end

--- Override the creature's size.
--- @param sizeid string
function creature:SetSizeOverride(sizeid)
	self.creatureSize = sizeid
end

creature.movementTypeInfo = {

	{
		id = "walk",
		text = "Walk",
		name = "Walk",
		tense = "Walks",
		verb = "Walking",
		icon = "panels/character-sheet/walking-boot.png",
	},

	{
		id = "swim",
		text = "Swim",
		name = "Swim",
		tense = "Swims",
		verb = "Swimming",
		icon = "icons/icon_sport/icon_sport_70.png",
		hasAltitude = true,
	},

	{
		id = "fly",
		text = "Fly",
		name = "Fly",
		tense = "Flies",
		verb = "Flying",
		icon = "panels/character-sheet/fluffy-wing.png",
		hasAltitude = true,
	},

	{
		id = "climb",
		text = "Climb",
		name = "Climb",
		tense = "Climbs",
		verb = "Climbing",
		icon = "icons/icon_sport/icon_sport_69.png",
		hasAltitude = true,
	},

	{
		id = "burrow",
		text = "Burrow",
		name = "Burrow",
		tense = "Burrows",
		verb = "Burrowing",
		icon = "panels/character-sheet/burrow.png",
		hasAltitude = true,
	},
    {
        id = "teleport",
        text = "Teleport",
        name = "Teleport",
        tense = "Teleports",
        verb = "Teleporting",
		icon = "panels/character-sheet/burrow.png",
    },
}

creature.damage_taken = 0
creature.movementTypeById = {}
creature.movementTypes = {}
creature.movementTypesTable = {}

for _,info in ipairs(creature.movementTypeInfo) do
	creature.movementTypes[#creature.movementTypes+1] = info.id
	creature.movementTypesTable[info.id] = true
	creature.movementTypeById[info.id] = info
end

creature.currentMoveType = "walk"

creature.innateActivatedAbilities = {}
creature.innateLegendaryActions = {}

--- Returns itself.
--- @return Creature
function creature:GetCreature()
	return self
end


--- returns a list of categories the monster is in. Returns at least one category.
--- @param base_only boolean|nil
--- @return string[]
function creature:GetMonsterCategoryList(base_only)
	local cat = self:try_get("monster_category")
	if cat == nil or (type(cat) == "table" and #cat == 0) then
		local result = {"monster"}
	elseif type(cat) == "string" then
		result = {cat}
	else
		result = cat
	end


    if not base_only then
        local mods = self:GetActiveModifiers()
        local symbols = GenerateSymbols(self)
        for i,mod in ipairs(mods) do
            result = mod.mod:ModifyCreatureTypes(mod, symbols, result)
        end
    end

	return result
end

--- Gets information about the creature's current movement type.
--- @return {id: string, name: string, tense: string, verb: string, icon:string}
function creature:CurrentMoveTypeInfo()
	return creature.movementTypeById[self:CurrentMoveType()]
end

--- The creature's movement type.
--- return string
function creature:CurrentMoveType()
	local token = dmhub.LookupToken(self)
    local groundMoveType = "walk"
	if token ~= nil then
		groundMoveType = token:GetGroundMoveType(self:GetSpeed("swim") >= self:GetSpeed("walk"))
	end

	if self.currentMoveType ~= "walk" and self.currentMoveType ~= "swim" and self:GetSpeed(self.currentMoveType) <= 0 and self:GetSpeed("walk") > 0 then

		return groundMoveType
	end

    if self.currentMoveType == "walk" or self.currentMoveType == "swim" then
        return groundMoveType
    end

	return self.currentMoveType
end

--- Set the creature's current movement type.
--- @param movetype string
function creature:SetCurrentMoveType(movetype)
	self.currentMoveType = movetype
end

--- Set the creature's current movement type and uploads it to the cloud..
--- @param movetype string
function creature:SetAndUploadCurrentMoveType(movetype)
	local tok = dmhub.LookupToken(self)
	if tok ~= nil then
		tok:ModifyProperties{
			description = "Set Move Type",
			undoable = false,
			combine = true,
			execute = function()
				tok.properties:SetCurrentMoveType(movetype)
			end,
		}
	end
end

--- The creature's current movement speed using its current movement type.
--- @return number
function creature:CurrentMovementSpeed()
	local result = self:GetSpeed(self:CurrentMoveType())
	if result == 0 then
		--if we are in a movement mode we can't perform, just return the walking speed.
		--Every foot we move will count as an extra foot though, but that is handled seperately.
		return math.max(0, self:WalkingSpeed())
	end
	return math.max(0, result)
end

--- if we are using this movement type, what will our speed be at it?
--- shown to users but generally not used in rules, as it's not doing the 'proper' thing
--- of making swimming or climbing work like difficult terrain.
--- @param movementType string
--- @return number
function creature:GetEffectiveSpeed(movementType)
	local speed = self:GetSpeed(movementType)
	if speed == 0 then
		return self:WalkingSpeed()/2
	end

	return speed
end

--- something that multiplies our movement based on e.g. dashing or being restrained.
--- @return number
function creature:MovementMultiplier()
	return self:CalculateAttribute("movementMultiplier", 1)
end

--- The creature's base movement speed with the given movement type.
--- @param movementType string
--- @return number
function creature:GetBaseSpeed(movementType)
	if movementType == 'speed' or movementType == 'walk' or movementType == nil then
		return self:BaseWalkingSpeed()
	end

	local result
	if self:has_key('movementSpeeds') then
		result = (self.movementSpeeds[movementType] or 0)*self:MovementMultiplier()
	else
		result = 0
	end

	return result

end

--- If the creature has a fly speed.
--- @return boolean
function creature:CanFly()
	return self:GetSpeed("fly") > 0
end

--- If the creature has a burrow speed.
--- @return boolean
function creature:CanBurrow()
	return self:GetSpeed("burrow") > 0
end

--- If the creature can teleport.
--- @return boolean
function creature:CanTeleport()
    return false
end

--- If the creature has climbing.
--- @return boolean
function creature:CanClimb()
    return self:GetSpeed("climb") > 0
end


function creature:CostToClimb(heightDifference)
    heightDifference = heightDifference - 1
    if heightDifference <= 0 then
        return 0
    end

    if self:CanClimb() then
        return heightDifference
    else
        return heightDifference*2
    end
end

--- Get speed with this movement type.
--- @param movementType string
--- @return number
function creature:GetSpeed(movementType)
	if movementType == 'walk' or movementType == nil then
		return self:WalkingSpeed()
	end

    if self:try_get("_tmp_prone") and movementType ~= "teleport" then
        --non-walking movement is not possible while prone.
        return 0
    end

	local result
	if self:has_key('movementSpeeds') then
		result = (self.movementSpeeds[movementType] or 0)
        --in draw steel if you have flying then you can fly at your full speed.
        if result ~= 0 then
            return self:WalkingSpeed()
        end
	else
		result = 0
	end

    local canUseMovementType = self:CalculateAttribute(movementType, result)
    local result = self:WalkingSpeed()

    if (canUseMovementType or 0) <= 0 then
        if movementType == "climb" then
            result = math.floor(result/2)
        else
            result = 0
        end
    end

	return result
end

--- Sets the creature's movement speed.
--- @param movementType string
--- @param value number
function creature:SetSpeed(movementType, value)
	if type(value) ~= "number" then
		local i1,i2,num = string.find(value, "(%d+)ft")
		if num ~= nil then
			value = num
		end
	end

	if movementType == 'walk' then
		self.walkingSpeed = tonumber(value) or self:try_get("walkingSpeed", 0)
		return
	end

	if not self:has_key('movementSpeeds') then
		self.movementSpeeds = {}
	end

	self.movementSpeeds[movementType] = tonumber(value)
end


--- Get a list of modifications to our speed.
function creature.DescribeSpeedModifications(self, movementType)
	if movementType == 'walk' or movementType == nil then
		movementType = 'speed'
	end
	return self:DescribeModifications(movementType, self:GetBaseSpeed(movementType))
end

--this tells us if there are any difficulties to movement that require every step
--costing extra movement. The default value of 0 means no difficulties.
function creature:MovementDifficulty()
	return self:CalculateAttribute("movementDifficulty", 0)
end

--gets an attribute with all modifications applied.
function creature:GetAttribute(attrid)
	local baseValue = self:GetBaseAttribute(attrid).baseValue

	local val = self:CalculateAttribute(attrid, baseValue)

	local attrAdd = self:try_get("attributesBonusAdd")
	if attrAdd ~= nil and attrAdd[attrid] then
		val = val + attrAdd[attrid]
	end

	local attrOverride = self:try_get("attributesOverride")
	if attrOverride ~= nil and attrOverride[attrid] ~= nil then
		val = attrOverride[attrid]
	end

	return CharacterAttribute.new{
		id = attrid,
		baseValue = val,
	}
end

--- The creature's modifier for the given attribute.
--- @param attrid string
--- @return number
function creature:AttributeMod(attrid)
	return self:GetAttribute(attrid):Modifier()
end

--- @return nil|string
function creature:GetMonsterType()
	return nil
end

--- @param token CharacterToken
--- @return string
function creature.GetTokenDescription(token)
	if token == nil then
		return '(unknown token)'
	end
	if token.name ~= nil and token.name ~= '' then
		return token.name
	elseif token.properties ~= nil and token.properties:GetMonsterType() ~= nil then
		return token.properties:GetMonsterType()
	else
		return '(unnamed token)'
	end
end

--dmhub.DescribeToken = function(token)
--	if token.properties ~= nil and token.properties:GetMonsterType() ~= nil then
--		return token.properties:GetMonsterType()
--	end

--	return nil
--end

--- this function is called by dmhub when the creature is created from the bestiary.
--- It is an opportunity to randomize things like hitpoints, name, etc.
function creature:OnCreateFromBestiary()
	self.damage_taken = 0
	self:ValidateAndRepair(true)
end


--- Clears all registered attributes. Use on the startup of your module if you want to
--- overwrite the creature attributes with your own set.
function creature.ClearAttributes()
	creature.attributesInfo = {
	}

	creature.attributeIds = {}

	creature.attributeDropdownOptions = {}
	creature.attributeDropdownOptionsWithNone = { { id = 'none', text = 'None' } }

	creature.descriptionToAttribute = {}

	creature.attributeDescriptionsWithNone = { 'None' }

	creature.savingThrowInfo = {}
	creature.savingThrowIds = {}
	creature.savingThrowDropdownOptions = {}
end

creature.ClearAttributes()


--- Helper function used to initialize attributes when creating a new creature.
--- @return table<string,CharacterAttribute>
function creature.CreateAttributes()
	local result = {}

	for _,attrid in ipairs(creature.attributeIds) do
		result[attrid] = CharacterAttribute.new{
			id = attrid,
		}
	end

	return result
end

--- Get the attribute object for this attribute id.
--- @param attrid string
--- @return CharacterAttribute
function creature:GetBaseAttribute(attrid)
	local result = self.attributes[attrid]
	if result == nil then
		result = CharacterAttribute.new{
			id = attrid
		}
		self.attributes[attrid] = result
	end

	return result
end

--- Mark that 'targetType' is a type derived from 'derivedType' for GoblinScript.
--- @param targetType table
--- @param derivedType table
function AddGoblinScriptDerived(targetType, derivedType)
	if rawget(targetType, "derivedTypes") == nil then
		targetType.derivedTypes = {}
	end

	targetType.derivedTypes[#targetType.derivedTypes+1] = derivedType
end

--- Register a GoblinScript symbol. It will be a member of targetType, which might be something like 'creature', 'ActivatedAbility', etc.
--- @param targetType table
--- @param info {name: string, type: string, desc: string, seealso: string[], examples: string[], calculate: function}
function RegisterGoblinScriptSymbol(targetType, info)
	local id = string.lower(string.gsub(info.name, "%s+", ""))
	targetType.lookupSymbols[id] = info.calculate

	targetType.helpSymbols[id] = {
		name = info.name,
		type = info.type,
		desc = info.desc,
		seealso = info.seealso,
		examples = info.examples,
	}

	local derivedTypes = rawget(targetType, "derivedTypes")
	if derivedTypes ~= nil then
		for _,t in ipairs(derivedTypes) do
			RegisterGoblinScriptSymbol(t, info)
		end
	end
end

--- Register a creature attribute.
--- @param info {id: string, description: string, order: number}
function creature.RegisterAttribute(info)
	if info.id == nil or info.description == nil then
		printf("RegisterAttribute requires id and description.")
		return
	end

	creature.attributesInfo[info.id] = info
	local index = #creature.attributeIds+1
	for i,attrid in ipairs(creature.attributeIds) do
		if attrid == info.id then
			index = i
		end
	end


	creature.attributeIds[index] = info.id

	table.sort(creature.attributeIds, function(a,b) return (creature.attributesInfo[a].order or 100) < (creature.attributesInfo[b].order or 100) end)

	index = #creature.attributeDropdownOptions+1
	for i,option in ipairs(creature.attributeDropdownOptions) do
		if option.id == info.id then
			index = i
		end
	end

	creature.attributeDropdownOptions[index] = {
		id = info.id,
		text = info.description,
	}

	table.sort(creature.attributeDropdownOptions, function(a,b) return (creature.attributesInfo[a.id].order or 100) < (creature.attributesInfo[b.id].order or 100) end)

	for i,option in ipairs(creature.attributeDropdownOptions) do
		creature.attributeDropdownOptionsWithNone[i+1] = option
	end

	creature.descriptionToAttribute = {}
	for id,attrInfo in pairs(creature.attributesInfo) do
		creature.descriptionToAttribute[attrInfo.description] = id
	end


	--register the attribute in GoblinScript
	local attrid = info.id
	local a = attrid
	local desc = string.lower(creature.attributesInfo[a].description)
	local descModifier = string.format("%smodifier", desc)
	creature.lookupSymbols[a] = function(c)
		return c:GetAttribute(a):Value()
	end
	creature.lookupSymbols[desc] = creature.lookupSymbols[a]
	creature.lookupSymbols[descModifier] = function(c)
		return c:AttributeMod(a)
	end

	creature.helpSymbols[desc] =  {
		name = creature.attributesInfo[a].description,
		type = "number",
		desc = string.format("The %s of the creature.", creature.attributesInfo[a].description),
		seealso = {},
	}

	creature.helpSymbols[descModifier] =  {
		name = string.format("%s Modifier", creature.attributesInfo[a].description),
		type = "number",
		desc = string.format("The %s Modifier of the creature.", creature.attributesInfo[a].description),
		seealso = {},
		examples = {string.format("OBJ.Proficiency Bonus + OBJ.%s Modifier", creature.attributesInfo[a].description)},
	}


	monster.lookupSymbols[a] = creature.lookupSymbols[a]
	character.lookupSymbols[a] = creature.lookupSymbols[a]

	monster.lookupSymbols[desc] = creature.lookupSymbols[desc]
	character.lookupSymbols[desc] = creature.lookupSymbols[desc]

	monster.lookupSymbols[descModifier] = creature.lookupSymbols[descModifier]
	character.lookupSymbols[descModifier] = creature.lookupSymbols[descModifier]

	monster.helpSymbols[desc] = creature.helpSymbols[desc]
	character.helpSymbols[desc] = creature.helpSymbols[desc]

	monster.helpSymbols[descModifier] = creature.helpSymbols[descModifier]
	character.helpSymbols[descModifier] = creature.helpSymbols[descModifier]
end


creature.savingThrowInfo = {}
creature.savingThrowIds = {}
creature.savingThrowDropdownOptions = {}

--- Register a saving throw.
--- @param info {id: string, description: string, order: number}
function creature.RegisterSavingThrow(info)
	local index = #creature.savingThrowIds+1
	for i,existing in ipairs(creature.savingThrowIds) do
		if existing == info.id then
			index = i
		end
	end

	creature.savingThrowInfo[info.id] = info
	creature.savingThrowIds[index] = info.id

	creature.savingThrowDropdownOptions[#creature.savingThrowDropdownOptions+1] = {
		id = info.id,
		text = info.description,
		order = info.order,
	}

	table.sort(creature.savingThrowIds, function(a, b) return creature.savingThrowInfo[a].order < creature.savingThrowInfo[b].order end)
	table.sort(creature.savingThrowDropdownOptions, function(a, b) return a.order < b.order end)
end

--- Clear saving throws. Do this if you want to start from scratch and register your own saving throws (Or if your game system just doesn't have saving throws.)
function creature.ClearSavingThrows()
	creature.savingThrowInfo = {}
	creature.savingThrowIds = {}
end

--- Get a list of saving throw options ready to go in a dropdown.
--- @return DropdownOption[]
function creature.GetSavingThrowDropdownOptions()
	local result = {}

	for _,id in ipairs(creature.savingThrowIds) do
		result[#result+1] = {
			id = id,
			text = creature.savingThrowInfo[id].description,
		}
	end

	return result
end


creature.nameGenerator = 'Default'

--A function which takes an attribute id and returns an index into the attributeDescriptionsWithNone
--array, or to the 'None' element if the id doesn't match any attribute.
function creature.modifierAttrToDescriptionWithNoneIndex(attrid)
	for i,v in ipairs(creature.attributeIds) do
		if v == attrid then
			return i+1
		end
	end

	return 1
end

function creature.modifierDescriptionToIndexWithNone(attrdesc)
	for i,v in ipairs(creature.attributeDescriptionsWithNone) do
		if v == attrdesc then
			return i
		end
	end

	return 1
end


-----------------
--EQUIPMENT PROFICIENCIES AND LANGUAGES
-----------------

local g_defaultNoneProficiency = {
	id = "none",
	text = "Not Proficient",
	multiplier = 0,
	verboseDescription = tr("You are not proficient in %s."),
}

creature.proficiencyKeyToValue = {}
creature.proficiencyMultiplierToValue = {}

local function InstallProficiencyMetatables()
	setmetatable(creature.proficiencyKeyToValue, {
		__index = function(t, key)
			local result = rawget(creature.proficiencyMultiplierToValue, 0)
			if result == nil then
				return g_defaultNoneProficiency
			else
				return result
			end
		end
	})
	setmetatable(creature.proficiencyMultiplierToValue, {
		__index = function(t, key)
			local result = rawget(t, 0)
			if result == nil then
				return g_defaultNoneProficiency
			else
				return result
			end
		end
	})

end

InstallProficiencyMetatables()

function creature.GetProficiencyDropdownOptions()
	local result = {}

	for key,option in pairs(creature.proficiencyKeyToValue) do
		result[#result+1] = option
	end

	table.sort(result, function(a,b) return a.multiplier < b.multiplier end)

	return result
end

function creature.RegisterProficiency(options)
	creature.proficiencyKeyToValue[options.id] = options
	creature.proficiencyMultiplierToValue[options.multiplier] = options
end

function creature.DeregisterProficiency(id)
	creature.proficiencyKeyToValue[id] = nil
end

function creature.ClearProficiencyLevels()
	creature.proficiencyKeyToValue = {}
	creature.proficiencyMultiplierToValue = {}
	InstallProficiencyMetatables()
end

--'inflict' a condition directly on a creature -- doesn't use an ongoing effect.
function creature:InflictCondition(conditionid, args)
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
	local conditionInfo = conditionsTable[conditionid]

	local inflictedConditions = self:get_or_add("inflictedConditions", {})

	local entry = inflictedConditions[conditionid] or {}
	inflictedConditions[conditionid] = entry

	entry.stacks = (entry.stacks or 0) + (args.stacks or 1)

	entry.casterInfo = args.casterInfo

	--the condition expires if it has no stacks.
	if entry.stacks <= 0 then
		inflictedConditions[conditionid] = nil
	end


	self.inflictedConditions = inflictedConditions

    audio.DispatchSoundEvent(conditionInfo:SoundEvent())
end

function creature:FillCalculatedStatusIcons(result)
	local mods = self:GetActiveModifiers()

	local conditions = self:try_get("_tmp_directConditions")
    local explanations = self:try_get("_tmp_conditionExplanations") or {}
	if conditions ~= nil then
		local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
		for k,v in pairs(conditions) do
			local quantityText = ""
			if v > 1 then
				quantityText = string.format(" (%d)", v)
			end
            local explanation = explanations[k] or ""
			local conditionInfo = conditionsTable[k]
			result[#result+1] = {
				id = k,
				icon = conditionInfo.iconid,
				style = conditionInfo.display,
				hoverText = string.format("%s%s: %s\n\n<b>%s</b>", conditionInfo.name, quantityText, conditionInfo.description, explanation),
				quantity = v,
				statusIcon = true,
			}
		end
	end

	--inflicted conditions are attached directly to the creature, add them here.
	if self:has_key("inflictedConditions") then
		local conditions = self.inflictedConditions
		local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
		for k,v in pairs(conditions) do
            local casterid = nil
            local casterInfo = v.casterInfo
            if casterInfo ~= nil then
                casterid = casterInfo.tokenid
            end
			local conditionInfo = conditionsTable[k]
            if conditionInfo ~= nil then
                local sourceDescription = v.sourceDescription or ""
                local hoverText
                if conditionInfo.stackable then
                    hoverText = string.format("%s (%d): %s", conditionInfo.name, v.stacks, sourceDescription)
                else
                    hoverText = string.format("%s: %s", conditionInfo.name, sourceDescription)
                end
                result[#result+1] = {
                    id = k,
                    icon = conditionInfo.iconid,
                    style = conditionInfo.display,
                    hoverText = hoverText,
                    quantity = v.stacks,
                    statusIcon = true,
                    casterid = casterid,
                }

                if conditionInfo:try_get("casterCanDrag", false) and v.casterInfo then
                    local casterToken = dmhub.GetTokenById(v.casterInfo.tokenid)
                    if casterToken ~= nil and casterToken.valid and casterToken.canControl then
                        local tokenid = dmhub.LookupTokenId(self)
                        local casterTokenid = v.casterInfo.tokenid
                        if tokenid ~= nil then
                            local condid = k
                            result[#result].draggable = true
                            result[#result].beginDrag = function()
                                local token = dmhub.GetTokenById(tokenid)
                                if token ~= nil and token.valid then
                                    local condInfo = token.properties:try_get("inflictedConditions", {})[condid]
                                    if condInfo ~= nil and condInfo.casterInfo ~= nil then
                                        local casterToken = dmhub.GetTokenById(condInfo.casterInfo.tokenid)
                                        if casterToken ~= nil and casterToken.valid then
                                            token:BeginDragMovement{
                                                locations = casterToken:GetLocsWithinRadius(1),
                                                overrideText = "Maneuver: Relocate grabbed creature to a space adjacent to you.",
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if conditionInfo:try_get("casterCanClick", false) and v.casterInfo then
                    local casterToken = dmhub.GetTokenById(v.casterInfo.tokenid)
                    local tokenid = dmhub.LookupTokenId(self)
                    if tokenid ~= nil and casterToken ~= nil and casterToken.valid and casterToken.canControl then
                        local condid = k
                        result[#result].hoverCursor = "hand"
                        result[#result].click = function()
                            local token = dmhub.GetTokenById(tokenid)
                            if token ~= nil and token.valid and conditionInfo:has_key("casterClickAbility") then
                                local condInfo = token.properties:try_get("inflictedConditions", {})[condid]
                                if condInfo ~= nil and condInfo.casterInfo ~= nil then
                                    local casterToken = dmhub.GetTokenById(condInfo.casterInfo.tokenid)
                                    if casterToken ~= nil and casterToken.valid and casterToken.canControl then
                                        conditionInfo.casterClickAbility:Cast(casterToken, { { token = token } },
                                        {
                                            symbols = {
                                                mode = 1,
                                            },
                                        }
                                        )
                                    end
                                end
                            end

                        end
                    end
                end
            end
		end
	end


	for i,mod in ipairs(mods) do
		mod.mod:FillStatusIcons(mod, self, result)
	end
end

--returns a {string -> true} of languages the creature knows.
function creature:LanguagesKnown()
    if self:has_key("_tmp_languagesKnown") then
        return self._tmp_languagesKnown
    end
	local mods = self:GetActiveModifiers()
	local result = DeepCopy(self:try_get("innateLanguages", {}))

	for i,mod in ipairs(mods) do
		mod.mod:AccumulateLanguages(mod, self, result)
	end

    self._tmp_languagesKnown = result

	return result
end

--returns a table of equipment or equipment categories the creature is proficient in.
--is a map of equipment id -> { proficiency = proficiency level ('proficient' or 'expertise') }
function creature:EquipmentProficienciesKnown()
	local mods = self:GetActiveModifiers()
	local result = DeepCopy(self:try_get("innateEquipmentProficiencies", {}))

	for pass=1,2 do
		for i,mod in ipairs(mods) do
			mod.mod:AccumulateEquipmentProficiencies(mod, self, result, pass)
		end
	end

	return result
end

function creature:ProficientWithItem(item)
	return self:ProficiencyLevelWithItem(item).multiplier > 0
end

function creature:ProficiencyLevelWithItem(item)
	if type(item) == "string" then
		item = dmhub.GetTable(equipment.tableName)[item]
	end

	if item == nil then
		return GameSystem.NotProficient()
	end

	local profs = self:EquipmentProficienciesKnown()

	local entry = profs[item.id]

	if entry == nil and item:has_key("baseid") then
		entry = profs[item.baseid]
	end

	if entry ~= nil then
		return creature.proficiencyKeyToValue[entry.proficiency]
	end

	local cats = dmhub.GetTable("equipmentCategories") or {}

	local count = 4
	local catid = item:try_get("equipmentCategory")
	while catid ~= nil and cats[catid] and count > 0 do
		if profs[catid] then
			return creature.proficiencyKeyToValue[profs[catid].proficiency]
		end

		catid = cats[catid]:try_get("superset")
		count = count-1
	end

	return GameSystem.NotProficient()
end

function creature:ProficiencyLevelWithCurrentArmor()
	local armor = self:GetArmor()
	if armor ~= nil then
		return self:ProficiencyLevelWithItem(armor)
	end

	local unarmored = EquipmentCategory.GetUnarmoredId()
	if unarmored ~= nil then
		local profs = self:EquipmentProficienciesKnown()
		if profs[unarmored] then
			return creature.proficiencyKeyToValue[profs[unarmored].proficiency]
		end
	end

	return GameSystem.NotProficient()
end

-----------------
--INNATE ACTIVATED ABILITIES
-----------------
function creature:AddInnateActivatedAbility(ability)
	if #self.innateActivatedAbilities == 0 then
		self.innateActivatedAbilities = {}
	end

	self.innateActivatedAbilities[#self.innateActivatedAbilities+1] = ability
end

function creature:RemoveInnateActivatedAbility(ability)
	local newValue = {}
	for i,a in ipairs(self.innateActivatedAbilities) do
		if ability ~= a then
			newValue[#newValue+1] = a
		end
	end

	self.innateActivatedAbilities = newValue
end

-----------------
--LEGENDARY ACTIONS
-----------------
function creature:AddInnateLegendaryAction(ability)
	if #self.innateLegendaryActions == 0 then
		self.innateLegendaryActions = {}
	end

	ability.legendary = true
	self.innateLegendaryActions[#self.innateLegendaryActions+1] = ability
end

function creature:RemoveInnateLegendaryAction(ability)
	local newValue = {}
	for i,a in ipairs(self.innateLegendaryActions) do
		if ability ~= a then
			newValue[#newValue+1] = a
		end
	end

	self.innateLegendaryActions = newValue
end

---------------------
--ATTACKS/WEAPONS
---------------------
function creature.GetAttackFromWeapon(self, weapon, options)
	if weapon.type ~= 'Weapon' then
		return nil
	end

	local melee = cond(EquipmentCategory.meleeWeaponCategories[weapon:try_get("equipmentCategory", "")], true, false)
	local meleeRange = nil

	--attrid can be a string, number, or nil.
	local attrid = GameSystem.CalculateAttackBonus(self, weapon, {melee = melee})
	
	if type(attrid) == "string" then
		local mods = self:GetActiveModifiers()
		for _,mod in ipairs(mods) do
			local alternativeAttrid = mod.mod:ModifyAttackAttribute(mod, self, weapon)
			if alternativeAttrid ~= nil and alternativeAttrid ~= attrid then
				if self:GetAttribute(alternativeAttrid):Modifier() >= self:GetAttribute(attrid):Modifier() then
					attrid = alternativeAttrid
				end
			end
		end
	end

	if melee and weapon:HasProperty("thrown") then
		meleeRange = 5
	end

	local attrBonus = 0

	if type(attrid) == "string" then
		attrBonus = self:GetAttribute(attrid):Modifier()
	elseif type(attrid) == "number" then
		attrBonus = attrid
		attrid = nil
	end

	local damageAttrBonus = GameSystem.CalculateDamageBonus(self, weapon, {melee = melee, attackBonus = attrBonus})

	local modifiers = {}

	local actionType = "standardAction"
	if options.offhand and type(attrid) == "string" then
		if damageAttrBonus > 0 and (not GameSystem.IgnoreOffhandWeaponPenalty(self, weapon)) then
			modifiers[#modifiers+1] = CharacterModifier.new{
				behavior = "damage",
				guid = dmhub.GenerateGuid(),
				name = "Ignore offhand weapon penalty",
				source = "Attack",
				description = string.format("Attacks with your offhand don't add your %s bonus to damage", attrid),
				modifyRoll = string.format("+%d", damageAttrBonus),
				damageFilterCondition = false,
			}
			damageAttrBonus = 0
		end

		actionType = 'bonusAction'
	end

	local strAttrBonus = '+' .. damageAttrBonus
	if damageAttrBonus < 0 then
		strAttrBonus = '' .. damageAttrBonus
	end

	local damage = weapon.damage
	if weapon:Versatile() and weapon:has_key('versatileDamage') and options.twohanded then
		local gearTable = dmhub.GetTable('tbl_Gear')

		damage = weapon.versatileDamage
	end

	local hands = nil
	if options.twohanded and (weapon:Versatile() or weapon:TwoHanded()) then
		hands = 2
	end

	local consumeAmmo = nil
	local outOfAmmo = false
	local ammoType = nil
	if weapon:HasProperty("ammo") and weapon:has_key("ammunitionType") then
		outOfAmmo = true
		ammoType = weapon.ammunitionType
		
		local ammoRarity = nil
		local gearTable = dmhub.GetTable('tbl_Gear')
		
		for k,entry in pairs(self:try_get("inventory", {})) do
			local gearEntry = gearTable[k]
			if gearEntry:try_get("equipmentCategory") == weapon.ammunitionType and (ammoRarity == nil or gearEntry:RarityOrd() < ammoRarity) then
				consumeAmmo = {}
				consumeAmmo[k] = 1
				outOfAmmo = nil
				ammoRarity = gearEntry:RarityOrd()
			end
		end
	elseif weapon:HasProperty("thrown") then
		consumeAmmo = {}
		consumeAmmo[weapon.id] = 1
	end

	local proficiencyBonus = GameSystem.CalculateWeaponProficiencyBonus(self, weapon)

	return Attack.new{
		iconid = weapon.iconid,
		name = weapon.name,
		range = weapon:Range(),
		melee = melee,
		meleeRange = meleeRange,
		hands = hands,
		hit = attrBonus + proficiencyBonus + weapon:HitBonus(),
		weapon = weapon,
		actionType = actionType,
		modifiers = modifiers,
		consumeAmmo = consumeAmmo,
		outOfAmmo = outOfAmmo,
		ammoType = ammoType,
		attrid = attrid,
		properties = weapon:try_get("properties"),
		damageInstances = {
			DamageInstance.new{
				damage = damage .. strAttrBonus,
				damageType = weapon.damageType,
				damageMagical = weapon:try_get('damageMagical'),
			},
		},
	}
end

function creature.AddInnateAttack(self, attackDef)
	if not self:has_key('innateAttacks') then
		self.innateAttacks = {}
	end

	self.innateAttacks[#self.innateAttacks+1] = attackDef
end

function creature.RemoveInnateAttack(self, attackDef)
	if not self:has_key('innateAttacks') then
		return
	end

	for i,v in ipairs(self.innateAttacks) do
		if v == attackDef then
			table.remove(self.innateAttacks, i)
			return
		end
	end
end


function creature.GetEquipmentAttackActions(self, options)
	result = {}
	local gearTable = dmhub.GetTable('tbl_Gear')

	for k,itemid in pairs(self:Equipment()) do
		local item = gearTable[itemid]
		if item ~= nil and item.type == 'Weapon' then
			local slotInfo = creature.EquipmentSlots[k]
			if slotInfo.loadout == self.selectedLoadout or (options or {}).allLoadouts then
				local attack = self:GetAttackFromWeapon(item, {twohanded = (slotInfo.otherhand ~= nil and not self:Equipment()[slotInfo.otherhand]), offhand = (slotInfo.offhand == true) })
				if attack ~= nil then
					attack.weaponid = itemid
					result[k] = attack
				end
			end
			
		end
	end

	return result
end

function creature.GetAttackActions(self, options)
	local result
	
	
	if self:EquipmentPrevented() then
		result = {}
	else
		result = self:GetEquipmentAttackActions(options)
	end

	if self:has_key('innateAttacks') then
		for i,attackDefinition in ipairs(self.innateAttacks) do
			local attack = attackDefinition:GenerateAttackInstance(self)
			if attack ~= nil then
				attack.baseAttackIndex = i
				result[attack.name] = attack
			end
		end
	end

	return result
end

function creature:SpellsPrevented()
	for _,mod in ipairs(self:GetActiveModifiers()) do
		if mod.mod:PreventsSpells(mod, self) then
			return true
		end
	end

	return false
end

function creature:EquipmentPrevented()
	for _,mod in ipairs(self:GetActiveModifiers()) do
		if mod.mod:PreventsEquipment(mod, self) then
			return true
		end
	end

	return false
end

function creature.InitiativeBonus(self)
	local override = self:InitiativeOverride()
	if override ~= nil then
		return override
	end

	local baseValue = GameSystem.CalculateInitiativeModifier(self)
	return self:CalculateAttribute('initiativeBonus', baseValue)
end

function creature.InitiativeBonusStr(self)
	return ModifierStr(self:InitiativeBonus())
end

function creature:InitiativeDetails()
	local dexModifier = 0

	if GameSystem.ArmorClassModifierAttrId ~= false then
		self:GetAttribute(GameSystem.ArmorClassModifierAttrId):Modifier()
	end

	local result = {}

	result[#result+1] = { key = "Dexterity", value = ModifierStr(dexModifier) }
	

	local modifierDescriptions = self:DescribeModifications('initiativeBonus', dexModifier)
	for i,mod in ipairs(modifierDescriptions) do
		result[#result+1] = mod
	end

	result[#result+1] = { key = 'Manual Override', value = self:InitiativeOverride(), edit = 'SetInitiativeOverride', showNotes = self:InitiativeOverride() ~= nil }

	result[#result+1] = { key = 'Total Intiative', value = '' .. self:InitiativeBonus() }

	return result
end

function creature:BaseWalkingSpeed()
	return 5
end

function creature.WalkingSpeed(self)
	local result = self:BaseWalkingSpeed()
	result = self:CalculateAttribute('speed', result) * self:MovementMultiplier()
	return result
end

function creature:GetStatHistory(id)
	local key = id .. '_history'
	local result = self:try_get(key)
	if result == nil or result.typeName ~= "StatHistory" then --for some reason can end up with a raw table that isn't a stat history?
		result = StatHistory.Create()
		self[key] = result
	end
	return result
end

function creature:BaseHitpoints()
	local result = toint(self.max_hitpoints)
	return result
end

function creature:MaxHitpoints(modifiers)
	local result = self:BaseHitpoints()
    local basehp = result
	result = self:CalculateAttribute("hitpoints", result, modifiers)

	return result
end

function creature.SetMaxHitpoints(self, amount, note)
	if type(amount) == 'string' then
		amount = tonumber(amount)
	end

	if type(amount) ~= 'number' then
		return
	end

	self.max_hitpoints = amount

	self:GetStatHistory("max_stamina"):Append{
		note = note,
		set = amount,
	}
end

function creature.CurrentHitpoints(self)
    local maxHitpoints = self:MaxHitpoints()
	local result = maxHitpoints - self.damage_taken
	if GameSystem.allowNegativeHitpoints == false then
		result = math.max(0, result)
	end

	return math.tointeger(result)
end

function creature.SetCurrentHitpoints(self, amount, note)
	if type(amount) == 'string' then
		amount = tonumber(amount)
	end

	if type(amount) ~= 'number' then
		return
	end

	local max_hitpoints = self:MaxHitpoints()
	if amount > max_hitpoints then
		amount = max_hitpoints
	end

	if amount < 0 and GameSystem.allowNegativeHitpoints == false then
		amount = 0
	end

	self.damage_taken = max_hitpoints - amount

	self:GetStatHistory("stamina"):Append{
		note = note,
		set = amount,
	}

	if self:CurrentHitpoints() > 0 then
		self:ResetDeathSavingThrowStatus()		
	end
end

function creature.SetTemporaryHitpoints(self, amount, note, options)
	options = options or {}

	if type(amount) == 'string' then
		if amount == '' then
			--setting temporary hitpoints to an empty string makes it 0.
			amount = '0'
		end
		amount = tonumber(amount)
	end

	if type(amount) ~= 'number' then
		return
	end

	if self:TemporaryHitpoints() <= 0 then
		--clear out any ongoing effect tied to these hitpoints if we didn't start out with temporary hitpoints.
		self.temporary_hitpoints_effect = nil
		self.tempHitpointsEndEffect = nil
	end

	if amount <= 0 and self:has_key("temporary_hitpoints_effect") and self:try_get("tempHitpointsEndEffect", true) then
		self:RemoveOngoingEffect(self.temporary_hitpoints_effect)
		options.temporary_hitpoints_effect = nil
	end

	if amount <= 0 then
		self.temporary_hitpoints = nil
	else
		self.temporary_hitpoints = amount
	end

	--if we have an ongoing effect tied to a current temporary hitpoints grant, then remove it.
	if self:has_key("temporary_hitpoints_effect") and options.ongoingeffectid ~= nil and self.temporary_hitpoints_effect ~= options.ongoingeffectid then
		self:RemoveOngoingEffect(self.temporary_hitpoints_effect)
	end

	--mark which effect is tied to these hitpoints.
	if amount > 0 and options.ongoingeffectid then
		self.temporary_hitpoints_effect = options.ongoingeffectid
		if options.tempHitpointsEndEffect ~= nil then
			self.tempHitpointsEndEffect = options.tempHitpointsEndEffect
		else
			self.tempHitpointsEndEffect = true
		end
	end

	self:GetStatHistory("temporary_stamina"):Append{
		note = note,
		set = amount,
	}
end

--removes temporary hitpoints, returning the overflow amount.
function creature:RemoveTemporaryHitpoints(amount, note)
	local temporary_hitpoints = self:TemporaryHitpoints()
	if temporary_hitpoints <= 0 then
		return amount
	end

	temporary_hitpoints = temporary_hitpoints - amount
	self:SetTemporaryHitpoints(temporary_hitpoints, note, { 
		temporary_hitpoints_effect = self:try_get("temporary_hitpoints_effect"),
		tempHitpointsEndEffect = self:try_get("tempHitpointsEndEffect", true)
	})
	if temporary_hitpoints < 0 then
		return -temporary_hitpoints
	else
		return 0
	end
end

function creature.TemporaryHitpoints(self)
	if self:has_key('temporary_hitpoints') then
		if self:has_key("temporary_hitpoints_effect") then
			--check that the effect that grants these hitpoints is still valid.
			local found = false
			for i,effect in ipairs(self:ActiveOngoingEffects()) do
				if effect.ongoingEffectid == self.temporary_hitpoints_effect then
					found = true
				end
			end

			if not found then
				return 0
			end
		end

		return self.temporary_hitpoints
	else
		return 0
	end
end

function creature.TemporaryHitpointsStr(self)
	local temporary_hitpoints = self:TemporaryHitpoints()
	if temporary_hitpoints > 0 then
		return string.format("%d", math.tointeger(temporary_hitpoints))
	else
		return '--'
	end
end

--called by dmhub when a nearby creature moves.
function creature:OnEnemyMove(enemyToken, distances)
	local abilities = self:GetActivatedAbilities{}
	for i,ability in ipairs(abilities) do
		if ability:GetReactionInfo().type == "move_out_of_reach" then
			local range = ability:GetRange(self)
			for i=1,#distances-1 do
				if distances[i] <= range*2 and distances[i+1] > range*2 then
					self:ActivateReaction(ability, { { tokenid = enemyToken.charid }})
					break
				end
			end
		end

	end
end

local g_seenSpeech = {}
function creature:GetAndRemoveSpeech()
    local speech = self:try_get("speech")
    if speech == nil then
        return nil
    end

    local result = nil

    for _,entry in ipairs(speech) do
        if not g_seenSpeech[entry.guid] and TimestampAgeInSeconds(entry.timestamp) < 10 then
            g_seenSpeech[entry.guid] = true
            result = result or {}
            result[#result+1] = entry
        end
    end

    return result
end

--to make very sure we don't show damage entries multiple times.
local g_seenDamageEntries = {}

--- @return nil|{id: string, attackerid: string|nil, damage: number, damage_type: string|nil, heal: number}[]
function creature:GetAndRemoveDamageEntries()
    local firstTime = not self:has_key("_tmp_seenDamageEntries")
    local handledEntries = self:get_or_add("_tmp_seenDamageEntries", {})
    local result = nil

    if not self:has_key("damageEntries") then
        return nil
    end

    for key,entry in pairs(self.damageEntries) do
        if (not firstTime) and (not handledEntries[key]) and (not g_seenDamageEntries[key]) then
            result = result or {}
            result[#result+1] = entry

            if entry.attackerid and entry.damage > 0 then
                local attackerToken = dmhub.GetCharacterById(entry.attackerid)
                if attackerToken ~= nil then
                    self._tmp_lastattacker = attackerToken.properties
                    self._tmp_lastdamagetype = entry.damage_type
                end
            end
        end

        handledEntries[key] = true
        g_seenDamageEntries[key] = true
    end


    return result
end

--- @param options {id: nil|string, damage: number, attackerid: string|nil, damage_type: string|nil, heal: number, sound: nil|string}
function creature:RecordDamageEntry(options)
    options.id = options.id or dmhub.GenerateGuid()
    options.timestamp = ServerTimestamp()
    print("MANDATORY:: RecordDamageEntry", options)

    local entries = self:get_or_add("damageEntries", {})
    for k,entry in pairs(entries) do
        if type(entry.timestamp) == "number" and TimestampAgeInSeconds(entry.timestamp) > 60 then
            entries[k] = nil
        end
    end

    if entries[options.id] ~= nil then
        if options.damage ~= nil then
            entries[options.id].damage = (entries[options.id].damage or 0) + options.damage
        end

        if options.heal ~= nil then
            entries[options.id].heal = (entries[options.id].heal or 0) + options.heal
        end

        entries[options.id].timestamp = options.timestamp
    else
        entries[options.id] = options
    end
end

function creature:LastDamagedBy(enemyid)
	return self:GetStatHistory("stamina"):MostRecentTimestamp(enemyid, "bad")
end

--inflicts a type of damage to the creature, appropriately accounting for
--the damage type and any resistances.
-- symbols: { criticalhit = true/false }
--
-- returns: { damageDealt = number }
function creature.InflictDamageInstance(self, amount, damageType, keywords, sourceDescription, symbols)
	amount = math.floor(amount)
	local resistanceEntry = self:DamageResistance(damageType, keywords)
	local resistance = resistanceEntry.resistance


    local ignoreImmunity = false

    if symbols ~= nil and symbols.cannotBeReduced then
		ignoreImmunity = true
	end
	
	if symbols.attacker ~= nil and (symbols.attacker:CalculateNamedCustomAttribute(string.format("Ignore %s Immunity", damageType)) or 0) > 0 then
        ignoreImmunity = true
    end

    if symbols ~= nil and symbols.cast ~= nil and #symbols.cast:GetParamModifications("ability_ignore_immunity") > 0 then
        ignoreImmunity = true
    end

	local note = string.format('%d damage from %s', amount, sourceDescription)

	if resistanceEntry.percent ~= nil then
		amount = math.floor(amount * resistanceEntry.percent)
		if amount < 0 then
			amount = 0
		end

		if resistanceEntry.percent < 1 then
			note = string.format('%s; Damage Immunity reduced to %d', note, amount)
		elseif resistanceEntry.percent > 1 then
			note = string.format('%s; Damage Amplification increased to %d', note, amount)
		end
	end

    if resistanceEntry.dr and (ignoreImmunity == false or resistanceEntry.dr <= 0) then
        amount = amount - resistanceEntry.dr
        if amount < 0 then
            amount = 0
        end
        if resistanceEntry.dr > 0 then
            note = string.format('%s; Damage Immunity reduced by %d to %d', note, resistanceEntry.dr, amount)
        else
            note = string.format('%s; Damage Vulnerability increased by %d to %d', note, -resistanceEntry.dr, amount)
        end
    end

	symbols = symbols or {}
	symbols.damagetype = damageType
    symbols.damagesound = symbols.damagesound
	symbols.sourcedescription = sourceDescription
    symbols.keywords = StringSet.new{
        strings = table.keys(keywords or {})
    }
	self:TakeDamage(amount, note, symbols)

	return {
		damageDealt = amount
	}
end

function creature:CheckBelowZeroHitpoints()
	if (not GameSystem.allowNegativeHitpoints) and self.damage_taken > self:MaxHitpoints() then
		--can't really have less than 0 hitpoints.
		self.damage_taken = self:MaxHitpoints()
	end
end

function creature.Heal(self, amount, note)
	if type(amount) == 'string' then
		amount = dmhub.RollInstant(amount)
	end

	if type(amount) ~= 'number' then
		return
	end

	if amount <= 0 then
		return
	end

	self:CheckBelowZeroHitpoints()

	self.damage_taken = self.damage_taken - amount
	if self.damage_taken < 0 then
		self.damage_taken = 0
	end

	self:ResetDeathSavingThrowStatus()

	self:GetStatHistory("stamina"):Append{
		note = note or string.format("%d Healing", amount),
		set = self:CurrentHitpoints(),
		disposition = "good",
	}

	self:RecordDamageEntry{
		heal = amount,
	}


	self:DispatchEvent("regainhitpoints", {})
end

function ModStr(result)
	result = tonum(result)
	if result >= 0 then
		return string.format("+%d", math.floor(result))
	else
		return string.format("%d", math.floor(result))
	end
end


function creature.SavingThrowModStr(self, saveid)
	local result = self:SavingThrowMod(saveid)
	return ModStr(result)
end

--------------------------
--ROLLS
--------------------------

function creature:GetAttributeRoll(attr, advantageType, options)
	return string.format("%s+%d %s", GameSystem.BaseSkillRoll, self:AttributeMod(attr), advantageType or '')
end

function creature:GetModifiersForAttributeRoll(attr, options)
	return self:GetModifiersForD20Roll('skill:' .. attr, options)
end

function creature:ConsumeResourcesForD20Roll(rollid, options)
	local modifiersUsed = self:GetModifiersForD20Roll(rollid, options)
	local resourceConsumed = false
	for i,mod in ipairs(modifiersUsed) do
		resourceConsumed = resourceConsumed or mod.modifier:ConsumeResource(self)
	end
	if resourceConsumed then
		local ourToken = dmhub.LookupToken(self)
		if ourToken ~= nil then
			ourToken:Upload("used resource")
		end
	end
end

function creature.RollAttributeCheck(self, attr, advantageType)
	local rollStr = self:GetAttributeRoll(attr, advantageType)
	rollStr = self:ApplyModifiersToD20Roll("skill:" .. attr, rollStr)
	self:ConsumeResourcesForD20Roll('skill:' .. attr)

	dmhub.Roll{
		roll = rollStr,
		description = creature.attributesInfo[attr].description .. ' Check',
		tokenid = dmhub.LookupTokenId(self),
	}
end

function creature.ShowAttributeRollDialog(self, attr)
	local attrDesc = creature.attributesInfo[attr].description
	local modifiers = self:GetModifiersForD20Roll('skill:' .. attr, {})

	local rollid
	rollid = GameHud.instance.rollDialog.data.ShowDialog{
		title = string.format("%s Check", attrDesc),
		roll = self:GetAttributeRoll(attr, '', {}),
		description = string.format("%s Check", attrDesc),
		creature = self,

		modifiers = modifiers,
		type = 'check',
		subtype = 'skill:' .. attr,

		completeRoll = function(rollInfo)
		end,

		cancelRoll = function()
		end,
	}

	return rollid
end


function creature.SavingThrowProficiencyLevel(self, saveid)
	return creature.proficiencyKeyToValue[self:SavingThrowProficiency(saveid)]
end

function creature:SavingThrowProficiencyMultiplier(saveid)
	return self:SavingThrowProficiencyLevel(saveid).multiplier
end

function creature:ShowSavingThrowRollDialog(saveid)
	local saveInfo = creature.savingThrowInfo[saveid]
	if saveInfo == nil then
		return
	end

	local attrDesc = saveInfo.description
	
	local proficient = self:HasSavingThrowProficiency(saveid)
	local modifiers = self:GetModifiersForD20Roll('save:' .. saveid, { proficient = proficient })

	local rollStr = string.format("%s + %d", GameSystem.BaseSavingThrowRoll, self:SavingThrowMod(saveid))

	local rollid
	rollid = GameHud.instance.rollDialog.data.ShowDialog{
		title = string.format("%s Saving Throw", attrDesc),
		roll = rollStr,
		description = string.format("%s Saving Throw", attrDesc),
		creature = self,

		modifiers = modifiers,
		type = 'd20',
		subtype = string.format("save:%s", saveid),

		completeRoll = function(rollInfo)
		end,

		cancelRoll = function()
		end,
	}

	return rollid
end

function creature:ProficientInSkill(skillInfo)
	return self:SkillProficiencyMultiplier(skillInfo) >= 1
end

function creature:GetCategorizedSkills()
	local categorizedSkills = {}

	for _,cat in ipairs(Skill.categories) do
		local skills = {}
		for _,skill in ipairs(Skill.SkillsInfo) do
			if skill.category == cat.id and self:ProficientInSkill(skill) then
				skills[#skills+1] = { id = skill.id, name = skill.name }
			end
		end
		table.sort(skills, function(a,b) return a.name < b.name end)
		categorizedSkills[#categorizedSkills+1] = {
			id = cat.id,
			skills = skills,
		}
	end
	table.sort(categorizedSkills, function(a,b) return a.id < b.id end)

	return categorizedSkills
end

function creature:ShowSkillRollDialog(skillInfo, args)
	local attrDesc = skillInfo.name

	local modifiers = self:GetModifiersForD20Roll('skill:' .. skillInfo.id, { proficient = self:ProficientInSkill(skillInfo) })

	local rollStr = string.format("%s + %d + ProficiencyBonus*ProficiencyMultiplier where ProficiencyMultiplier = %f", GameSystem.BaseSkillRoll, self:CalculateAttribute(skillInfo.id, self:GetAttribute(skillInfo.attribute):Modifier()), self:SkillProficiencyMultiplier(skillInfo))

	local params = {
		title = string.format("%s Check", attrDesc),
		roll = rollStr,
		description = string.format("%s Check", attrDesc),
		creature = self,

		modifiers = modifiers,
		type = 'd20',
		subtype = string.format("skill:%s", skillInfo.id),

		completeRoll = function(rollInfo)
		end,

		cancelRoll = function()
		end,
	}

	if args ~= nil then
		for k,v in pairs(args) do
			params[k] = v
		end
	end

	local rollid
	rollid = GameHud.instance.rollDialog.data.ShowDialog(params)

	return rollid
end

function creature:GetSavingThrowRoll(saveid, advantageType, options)
	local rollStr = string.format("%s+%d %s", GameSystem.BaseSavingThrowRoll, self:SavingThrowMod(saveid), advantageType or '')
	return self:ApplyModifiersToD20Roll('save:' .. saveid, rollStr, options)
end

function creature:GetModifiersForSavingThrowRoll(saveid, options)

	options = options or {}

	options.proficient = self:HasSavingThrowProficiency(saveid)

	local modifiers = self:GetModifiersForD20Roll('save:' .. saveid, options)

	if options.casterid ~= nil then
		self.casterid = options.casterid
	end

	if saveid == 'dex' and (not options.nocover) then

		local casterToken = nil
		local ourToken = nil
		if options.casterid then
			casterToken = dmhub.GetTokenById(options.casterid)
			ourToken = dmhub.LookupToken(self)
		end

		local coverTooltip = "Choose the amount of cover you have."
		local coverAmount = "none"

		if casterToken ~= nil and ourToken ~= nil then
			local coverInfo = dmhub.GetCoverInfo(casterToken, ourToken)
			if coverInfo ~= nil then
				if coverInfo.cover == 1 then
					coverTooltip = string.format("%s\n<color=#aaffaaff>There is a %s in the way, providing Half Cover.", coverTooltip, coverInfo.description)
					coverAmount = "half"
				elseif coverInfo.cover == 2 then
					coverAmount = "threequarters"
					coverTooltip = string.format("%s\n<color=#aaffaaff>There is a %s in the way, providing Three Quarters Cover.", coverTooltip, coverInfo.description)
				else
					coverAmount = "fullcover"
					coverTooltip = string.format("%s\n<color=#aaffaaff>There is a %s in the way, providing Full Cover.", coverTooltip, coverInfo.description)
				end
			end
		end

		--dex savings throws can have cover.
		modifiers[#modifiers+1] = {
			text = "Cover",
			tooltip = coverTooltip,
			modifierOptions = {
				{
					id = "none",
					text = "No Cover",
					mod = CharacterModifier.StandardModifiers.SavingThrowNoCover,
				},
				{
					id = "half",
					text = "Half Cover",
					mod = CharacterModifier.StandardModifiers.SavingThrowHalfCover,
				},
				{
					id = "threequarters",
					text = "Three Quarters Cover",
					mod = CharacterModifier.StandardModifiers.SavingThrowThreeQuartersCover,
				},
				{
					id = "fullcover",
					text = "Full Cover",
					mod = CharacterModifier.StandardModifiers.SavingThrowThreeQuartersCover,
					disableRoll = "You automatically succeed and don't need to roll since you have full cover.",
				},
			},
			hint = {
				result = coverAmount,
				justification = {"Choose the amount of cover you have."},
			},
		}

	end

	return modifiers
end

function creature.RollSavingThrow(self, saveid, advantageType)
	local rollStr = self:GetSavingThrowRoll(saveid, advantageType)

	self:ConsumeResourcesForD20Roll('save:' .. saveid)

	dmhub.Roll{
		roll = rollStr,
		description = creature.savingThrowInfo[saveid].description .. ' Saving Throw',
		tokenid = dmhub.LookupTokenId(self),
	}
end

--passive modifiers.
function creature.SetBasePassiveModOverride(self, skillInfo, value)
	local passives = self:get_or_add("passives", {})
	passives[skillInfo.id] = value
end

function creature.BasePassiveModNoOverride(self, skillInfo)
	return 10 + self:SkillMod(skillInfo)
end

function creature.BasePassiveModOverride(self, skillInfo)
	local passives = self:try_get("passives")
	if passives == nil then
		return nil
	end

	return passives[skillInfo.id]
end

function creature.BasePassiveMod(self, skillInfo)
	local override = self:BasePassiveModOverride(skillInfo)
	if override ~= nil then
		return override
	end
	return self:BasePassiveModNoOverride(skillInfo)
end

function creature.DescribePassiveModModifications(self, skillInfo)
	return self:DescribeModifications(string.format('PASSIVE-%s', skillInfo.id), self:BasePassiveMod(skillInfo))
end

function creature.PassiveMod(self, skillInfo)
	return self:CalculateAttribute(string.format('PASSIVE-%s', skillInfo.id), self:BasePassiveMod(skillInfo))
end

function creature:GetSkillCheckRoll(skillInfo, advantageType, options)
	local rollStr = string.format("%s+%d %s", GameSystem.BaseSkillRoll, self:SkillMod(skillInfo), advantageType or '')
	return self:ApplyModifiersToD20Roll('skill:' .. skillInfo.id, rollStr, options)
end

function creature:GetModifiersForSkillCheckRoll(skillInfo, options)
	options = options or {}
	options.proficient = self:ProficientInSkill(skillInfo)
	return self:GetModifiersForD20Roll('skill:' .. skillInfo.id, options)
end

function creature.RollSkillCheck(self, skillInfo, advantageType)
	local rollStr = self:GetSkillCheckRoll(skillInfo, advantageType)
	self:ConsumeResourcesForD20Roll('skill:' .. skillInfo.id)
	dmhub.Roll{
		roll = rollStr,
		description = skillInfo.name .. ' Check',
		tokenid = dmhub.LookupTokenId(self),
	}
end

--private function for when we complete initiative.
function creature.CompleteInitiative(self, rollInfo)
	if GameHud.instance and GameHud.instance.tokenInfo.initiativeQueue ~= nil then
		local token = dmhub.LookupToken(self)
		if token ~= nil then
			local initiativeId = InitiativeQueue.GetInitiativeId(token)
			local dexterity = self:GetAttribute('dex'):Value()
			GameHud.instance.tokenInfo.initiativeQueue:SetInitiative(initiativeId, rollInfo.total, dexterity)
			GameHud.instance.tokenInfo.UploadInitiative()

			self:DispatchEvent("rollinitiative", {})
		end
	end
end

--gets when the creature ended its last turn.
function creature:GetEndTurnTimestamp()
	if GameHud.instance and GameHud.instance.tokenInfo.initiativeQueue ~= nil then
		local token = dmhub.LookupToken(self)
		if token ~= nil then
			local initiativeId = InitiativeQueue.GetInitiativeId(token)
			local entry = GameHud.instance.tokenInfo.initiativeQueue.entries[initiativeId]
			if entry ~= nil then
				return rawget(entry, "endTurnTimestamp")
			end
		end
	end

	return nil
end


function creature.ShowInitiativeRollDialog(self)
	local modifiers = self:GetModifiersForD20Roll('initiative', {})
	
	local rollStr = self:GetInitiativeRoll()

	local rollid
	rollid = GameHud.instance.rollDialog.data.ShowDialog{
		title = "Roll for Initiative",
		roll = rollStr,
		description = "Initiative Roll",
		creature = self,

		modifiers = modifiers,
		type = 'check',
		subtype = 'initiative',

		completeRoll = function(rollInfo)
			creature.CompleteInitiative(self, rollInfo)
		end,

		cancelRoll = function()
		end,
	}

	return rollid
end

function creature:GetInitiativeRoll()
	return string.format("%s+%d", GameSystem.BaseInitiativeRoll, self:InitiativeBonus())
end

function creature.RollInitiative(self)


	dmhub.Roll({
		roll = self:ApplyModifiersToD20Roll('initiative', self:GetInitiativeRoll()),
		description = 'Initiative Roll',
		complete = function(rollInfo)
			creature.CompleteInitiative(self, rollInfo)
		end,
		tokenid = dmhub.LookupTokenId(self),
	})
end

function creature:ResetDeathSavingThrowStatus()
	self.deathSavingThrowFailures = 0
	self.deathSavingThrowSuccesses = 0
	self.deathSavingThrowHistory = nil
end

function creature:AddDeathSavingThrowFailure(num)
	if num == nil then
		num = 1
	end
	self.deathSavingThrowFailures = self:GetNumDeathSavingThrowFailures() + num
	local history = self:get_or_add("deathSavingThrowHistory", {})
	history[#history+1] = {
		timestamp = ServerTimestamp(),
		result = "fail",
		num = num,
	}
end

function creature:AddDeathSavingThrowSuccess(num)
	if num == nil then
		num = 1
	end
	self.deathSavingThrowSuccesses = self:GetNumDeathSavingThrowSuccesses() + num
	local history = self:get_or_add("deathSavingThrowHistory", {})
	history[#history+1] = {
		timestamp = ServerTimestamp(),
		result = "success",
		num = num,
	}
end

function creature:GetDeathSavingThrowStatus(index)
	for _,info in ipairs(self:try_get("deathSavingThrowHistory",{})) do
		index = index - info.num
		if index <= 0 then
			return info.result
		end
	end

	return nil
end

function creature:GetNumDeathSavingThrowFailures()
	if self:CurrentHitpoints() <= 0 then
		return self:try_get('deathSavingThrowFailures', 0)
	else
		return 0
	end
end

function creature:GetNumDeathSavingThrowSuccesses()
	if self:CurrentHitpoints() <= 0 then
		return self:try_get('deathSavingThrowSuccesses', 0)
	else
		return 0
	end
end

--args : {completefn = function(RollInfo)?}?
function creature:RollDeathSavingThrow(args)

	local thisCreature = self

	local completefn = function(rollInfo)
		local matchingOutcome = rollInfo.properties:GetOutcome(rollInfo)
		if matchingOutcome == nil then
			return
		end

		if matchingOutcome.outcome == 'Critical Fail' then
			self:AddDeathSavingThrowFailure(2)
		elseif matchingOutcome.outcome == 'Fail' then
			self:AddDeathSavingThrowFailure()
		elseif matchingOutcome.outcome == 'Success' then
			self:AddDeathSavingThrowSuccess()
		else
			thisCreature:Heal(1, 'Critical success on death saving throw')
		end

		local token = dmhub.LookupToken(thisCreature)
		if token ~= nil then
			token:Upload('Death saving throw result')
		end

		if args ~= nil and args.completefn ~= nil then
			args.completefn(rollInfo)
		end
	end

	local rollProperties = GameSystem.GetRollProperties("deathsave")

	local modifiers = self:GetModifiersForD20Roll('save:death', {})

	local rollid
	rollid = GameHud.instance.rollDialog.data.ShowDialog{
		title = 'Death Saving Throw',
		roll = GameSystem.CalculateDeathSavingThrowRoll(self),
		description = "Death Saving Throw",
		creature = self,
		autoroll = true,


		modifiers = modifiers,
		type = 'd20',
		subtype = 'save:death',

		completeRoll = completefn,

		rollProperties = rollProperties,
	}



--local guid = dmhub.GenerateGuid()
--dmhub.Roll{
--	guid = guid,
--	roll = "1d20",
--	description = "Death Saving Throw",
--	tokenid = dmhub.LookupTokenId(self),
--	complete = completefn,
--	properties = rollProperties,
--}

	return rollid
end

--Lua properties that we attach to a dice roll.
RegisterGameType("RollProperties")

RollProperties.displayType = "none"
RollProperties.criticalHitDamage = false
RollProperties.lowerIsBetter = false
RollProperties.changeOutcomeOnCriticalRoll = 0
RollProperties.changeOutcomeOnFumbleRoll = 0

function RollProperties:ResetMods()
end

function RollProperties:CustomPanel(message)
	return nil
end

function RollProperties.UpdateOutcomesAfterEvents(self, castingCreature, targetCreature)
end

function RollProperties:CompareDiceRoll(roll, requirement)
	if self.lowerIsBetter then
		return roll <= requirement
	else
		return roll >= requirement
	end
end

--Allows us to add a possible outcome to a roll. E.g. { outcome = "Hit", value = 8, color = '#00ff00' }.
--value is optional, and always matches if true. We match the last added outcome that
--the dice meet or exceed.
function RollProperties:AddOutcome(outcome)
	local outcomes = self:get_or_add("outcomes", {})
	outcomes[#outcomes+1] = outcome
end

function RollProperties:Outcomes()
	if self:try_get("tableRef") ~= nil then
		local result = {}
		local t = self.tableRef:GetTable()
        if t ~= nil then
            local rollInfo = t:CalculateRollInfo()

            for i,row in ipairs(t.rows) do
                result[#result+1] = {
                    outcome = row.value:ToString(),
                    value = rollInfo.rollRanges[i].min,
                    color = "#ffffff",
                }
            end

            return result
        end
	end
	return self:get_or_add("outcomes", {})
end

--find the roll needed to get a certain outcome. e.g. FindOutcomeRequirement("Hit")
function RollProperties:FindOutcomeRequirement(rollInfo, name)
	for _,outcome in ipairs(self:Outcomes()) do
		if outcome.outcome == name then
			return outcome.value
		end
	end

	return nil
end

function RollProperties:HasOutcomes()
	local outcomes = self:Outcomes()
	return #outcomes > 0
end

--Get the outcome that the roll matches.
function RollProperties:GetOutcome(rollInfo)

    if self:has_key("overrideOutcome") then
        return self.overrideOutcome
    end
	
	local result = nil
	local outcomes = self:Outcomes()

	local criticalRoll = rollInfo.nat20
	local fumbleRoll = rollInfo.nat1

	if fumbleRoll then
		for _,outcome in ipairs(outcomes) do
			if outcome.fumbleRoll then
				return outcome
			end
		end
	end

	if criticalRoll then
		for _,outcome in ipairs(outcomes) do
			if outcome.criticalRoll then
				return outcome
			end
		end
	end

	if rollInfo.autofailure then
		for _,outcome in ipairs(outcomes) do
			if outcome.failure and (outcome.degree or 1) == 1 then
				return outcome
			end
		end

		return {
			outcome = "Failure",
			color = '#ff0000',
			failure = true,
		}
	end

	if rollInfo.autosuccess then
		for _,outcome in ipairs(outcomes) do
			if outcome.success and (outcome.degree or 1) == 1 then
				return outcome
			end
		end

		return {
			outcome = "Success",
			color = '#00ff00',
			success = true,
		}
	end

	local resultIndex = nil
	--go through the possible outcomes and return the latest one that we match.
	for i,outcome in ipairs(outcomes) do
		if tonumber(outcome.value) == nil or (tonumber(rollInfo.total) ~= nil and self:CompareDiceRoll(tonumber(rollInfo.total), tonumber(outcome.value))) then
			result = outcome
			resultIndex = i
		end
	end

	if rollInfo.autocrit and result ~= nil and result.success then
		criticalRoll = true
		for _,outcome in ipairs(outcomes) do
			if outcome.criticalRoll then
				return outcome
			end
		end
	end

	if criticalRoll and self.changeOutcomeOnCriticalRoll ~= 0 and resultIndex ~= nil then
		result = outcomes[resultIndex+self.changeOutcomeOnCriticalRoll] or result
	end

	if fumbleRoll and self.changeOutcomeOnFumbleRoll ~= 0 and resultIndex ~= nil then
		result = outcomes[resultIndex+self.changeOutcomeOnFumbleRoll] or result
	end

	return result
end

function RollProperties:GetOutcomeOfValue(val)
	local result = nil
	local outcomes = self:Outcomes()
	--go through the possible outcomes and return the latest one that we match.
	for i,outcome in ipairs(outcomes) do
		if outcome.value == nil or self:CompareDiceRoll(val, outcome.value) then
			result = outcome
		end
	end

	return result
end

--options can include these functions:
--  completeAttackRoll: when the to-hit roll completes rolling this is called
--  completeAttack: when the entire attack is completed (including damage, or including a miss with no damage roll) this is called. bool argument which is true iff the attack hit. Options argument: {criticalHit = true if a critical hit}
--  cancelAttack: When the user cancels out either on the attack roll or the damage roll.
function creature.RollAttackHit(self, attack, target, options)
	local optionsCopy = dmhub.DeepCopy(options or {})

	--"cast" is the one symbol we want to not deep copy.
	if optionsCopy.symbols ~= nil and optionsCopy.symbols.cast ~= nil then
		optionsCopy.symbols.cast = options.symbols.cast
	end

	options = optionsCopy

	local beginAttack = options.beginAttack
	local completeAttack = options.completeAttack
	local cancelAttack = options.cancelAttack
	local keywords = options.keywords

	options.beginAttack = nil
	options.completeAttack = nil
	options.cancelAttack = nil
	options.keywords = nil

	local completefn
	
	local rollProperties = nil

	local selfToken = dmhub.LookupToken(self)
	local selfName = creature.GetTokenDescription(selfToken)
	local attackName = attack.name
	local targetCreature = nil

	if target ~= nil and target.properties ~= nil then

		targetCreature = target.properties

		rollProperties = GameSystem.GetRollProperties("attack", targetCreature:ArmorClass())

		completefn = function(rollInfo)

			local matchingOutcome = rollInfo.properties:GetOutcome(rollInfo)

			--don't dispatch this event to allow it to immediately alter things.
			targetCreature:TriggerEvent("attacked", {
				outcome = matchingOutcome.outcome,
				roll = rollInfo.total,
				attack = GenerateSymbols(attack),
				attacker = GenerateSymbols(self),
			})

			--update the armor class and make sure this still hits.
			rollInfo.properties:UpdateOutcomesAfterEvents(self, targetCreature)
			matchingOutcome = rollInfo.properties:GetOutcome(rollInfo)

			if options.completeAttackRoll ~= nil then
				options.completeAttackRoll(rollInfo)
				options.completeAttackRoll = nil
			end


			if matchingOutcome ~= nil then
				local args = {
					outcome = matchingOutcome.outcome,
					degree = matchingOutcome.degree,
					attack = GenerateSymbols(attack),
					target = GenerateSymbols(targetCreature),
				}

				self:TriggerEvent("attack", args)

				if matchingOutcome.failure then
					self:TriggerEvent("miss", args)

					if matchingOutcome.degree > 1 then
						self:TriggerEvent("fumble", args)
					end
				end
			end

			if matchingOutcome ~= nil and matchingOutcome.success then

				local criticalHit = matchingOutcome.degree > 1

				options.roll = rollInfo or {}

				--standard modifier descriptions with modifier field and hint.
				local modifiers = self:GetDamageRollModifiers(attack, target, options)

				for _,mod in ipairs(modifiers) do
					if mod.modifier ~= nil then
						mod.modifier:InstallSymbolsFromContext{
							ability = GenerateSymbols(options.ability),
							attack = GenerateSymbols(attack),
						}
					end
				end

				--damage checkboxes can be passed in from the ability. Note that these
				--are not standard modifiers with a "modifier" field. ShowDialog knows what to do with them.
				for _,mod in ipairs(options.damageCheckboxes or {}) do
					modifiers[#modifiers+1] = mod
				end

				local rollid
				rollid = GameHud.instance.rollDialog.data.ShowDialog{
					title = 'Roll for Damage',
					roll = attack:DescribeDamageRoll(),
					description = target:DescribeRollAgainst(string.format("%s Damage Roll", attackName)),
					creature = self,
					targetCreature = targetCreature,

					--hint the target so damage indicators are shown over them.
					targetHints = {
						{
							charid = target.id,
							half = false,
						},
					},
					modifiers = modifiers,
					type = 'damage',
					critical = criticalHit,
					delay = 1,
					completeRoll = function(rollInfo)

						local attackInfo = {
							criticalHit = criticalHit,
							damageRaw = 0,
							damageDealt = 0,
						}

						target:ModifyProperties{
							description = "Damaged",
							execute = function()
								targetCreature:TriggerEvent("hit", {
									attacker = GenerateSymbols(self),
									attack = GenerateSymbols(attack),
								})
								self:RecordDamageEntry{
									id = rollid or dmhub.GenerateGuid(),
									damage = 0,
								}

								for catName,value in pairs(rollInfo.categories) do
									local result = targetCreature:InflictDamageInstance(value, catName, keywords, string.format("%s's %s", selfName, attackName), { criticalhit = rollInfo.properties.criticalHitDamage, attacker = self })
									attackInfo.damageRaw = attackInfo.damageRaw + value
									attackInfo.damageDealt = attackInfo.damageDealt + result.damageDealt
								end

								if targetCreature:HasConcentration() then
									--trigger a concentration roll.
									local saveInfo = GameSystem.ConcentrationSavingThrow(targetCreature, attackInfo.damageDealt)
									if saveInfo ~= nil then
										targetCreature:CheckToMaintainConcentration(saveInfo)
									end
								end

								self:ClearMomentaryOngoingEffects()
								targetCreature:ClearMomentaryOngoingEffects()
							end,
						}

						if completeAttack then
							completeAttack(true, attackInfo)
						end
					end,

					cancelRoll = function()
						if cancelAttack ~= nil then
							cancelAttack()
						end
					end,

				}

			else
				if completeAttack then
					completeAttack(false, {})
				end
			end

			targetCreature:ClearMomentaryOngoingEffects()
			self:ClearMomentaryOngoingEffects()

		end
	end

	local attackSymbols = {
		attack = attack,
		target = targetCreature,
	}

	local modifiers = self:GetModifiersForD20Roll('attack', attackSymbols)

	local attackRanged = attack:IsRanged(selfToken, target) --okay for target of IsRanged to be nil.

	if attackRanged and GameRules.TokenNearEnemies(selfToken) then
		modifiers[#modifiers+1] = {
			modifier = CharacterModifier.DuplicateAndAddContext(CharacterModifier.StandardModifiers.RangedAttackWithEnemiesNearby, attackSymbols),
			hint = {
				result = "true",
				justification = {"Using a ranged weapons with enemies nearby"},
			},
		}

		--clear if there is no modifier for it in our rules.
		if modifiers[#modifiers].modifier == nil then
			modifiers[#modifiers] = nil
		end
	end

	if attackRanged and target ~= nil then
		local range = selfToken:DistanceInFeet(target) - 2.5

		if range > attack:RangeNormal() then
			modifiers[#modifiers+1] = {
				modifier = CharacterModifier.DuplicateAndAddContext(CharacterModifier.StandardModifiers.RangedAttackDistant, attackSymbols),
				hint = {
					result = "true",
					justification = {string.format("This enemy is %d feet away, while the attack's normal range is %d feet.", round(range), round(attack:RangeNormal()))},
				},
			}

			--clear if there is no modifier for it in our rules.
			if modifiers[#modifiers].modifier == nil then
				modifiers[#modifiers] = nil
			end
		end
	end

	if target ~= nil and target.properties ~= nil then
		local targetModifiers = target.properties:GetModifiersForAttackAgainstUs(self, attack)
		dmhub.Debug('TARGET MODIFIERS AGAINST US: ' .. #targetModifiers)
		for i,mod in ipairs(targetModifiers) do
			modifiers[#modifiers+1] = mod
		end
	end

	local rollStr = string.format("%s+%s", GameSystem.BaseAttackRoll, attack.hit)

	local rollDescription
	if targetCreature ~= nil then
		rollDescription = target:DescribeRollAgainst(string.format("%s Attack Roll", attackName))
	else
		rollDescription = string.format("%s Attack Roll", attackName)
	end

	GameHud.instance.rollDialog.data.ShowDialog{
		title = 'Attack With ' .. attack.name,
		description = rollDescription,
		roll = rollStr,
		creature = self,
		targetCreature = targetCreature,
		modifiers = modifiers,
		type = 'd20',
		subtype = 'attack',
		symbols = options.symbols,
		autoroll = options.autoroll,
		beginRoll = beginAttack,
		completeRoll = completefn,

		cancelRoll = function()
			if cancelAttack ~= nil then
				cancelAttack()
			end
		end,
		rollProperties = rollProperties,
	}
end

function creature.RollAttackDamage(self, attack)
	dmhub.Roll({
		roll = attack:DescribeDamageRoll(),
		description = 'Damage With ' .. attack.name,
		tokenid = dmhub.LookupTokenId(self),
	})
end

function creature.SkillModStr(self, skillInfo)
	local result = self:SkillMod(skillInfo)
	return ModStr(result)
end

function creature.SkillProficiencyMultiplier(self, skillInfo)
	return self:SkillProficiencyLevel(skillInfo).multiplier

end

function creature.SkillProficiencyLevel(self, skillInfo)
	return GameSystem.NotProficient()
end

--commands that can be executed on creatures.
creature.commands = {
	initiative = function(self)
		self:RollInitiative()
	end,

	inventory = function(self)
		local tok = dmhub.LookupToken(self)
		if tok ~= nil then
			tok:ShowSheet("Inventory") --'big' inventory
			--gamehud:ShowInventory(tok) --'small' inventory
		end
	end,
}

local ParseAdvantage = function(str)
	if str == nil then
		return nil
	end
	str = string.lower(str)
	if str ~= '' then
		if string.startswith('advantage', str) then
			return 'advantage'
		elseif string.startswith('disadvantage', str) then
			return 'disadvantage'
		end
	end

	return nil
end

for k,v in pairs(creature.attributesInfo) do
	local attr = k
	local commandKey = string.lower(v.description)
	creature.commands[commandKey] = function(self, arg1, arg2)
		local advantage = ParseAdvantage(arg1) or ParseAdvantage(arg2)
		if (arg1 == 'save' or arg2 == 'save') and creature.savingThrowInfo[attr] ~= nil then
			self:RollSavingThrow(attr, advantage)
		else
			self:RollAttributeCheck(attr, advantage)
		end
	end
end

for k,v in pairs(creature.savingThrowInfo) do
	local saveid = k
	local commandKey = string.lower(v.description)
	if creature.attributesInfo[k] == nil then
		creature.commands[commandKey] = function(self, arg1, arg2)
			local advantage = ParseAdvantage(arg1) or ParseAdvantage(arg2)
			self:RollSavingThrow(attr, advantage)
		end
	end

end

--resistances

--damageType is like 'magic slashing' or 'bludgeoning'.
--Returns { resistance = 'Resistant', 'Vulnerable', 'Immune', or nil, dr = number or nil, percent = number or nil }
--percent is the percent of damage that we will ultimately take.
function creature.DamageResistance(self, damageType, keywords)

	local result = {}

	damageType = string.lower(damageType)
	local magical = false
	if string.startswith(damageType, 'magic ') then
		damageType = string.sub(damageType, 7)
		magical = true
	end
	if string.startswith(damageType, 'magical ') then
		damageType = string.sub(damageType, 9)
		magical = true
	end

    print("RESISTANCE:: KEYWORDS =", keywords)

	--this flag is set if we have a combination of vulnerable and resistance which means we can't have either.
	local resistanceCanceled = false

	for i,entry in ipairs(self:CalculateResistances()) do
		local keywordsMatch = true

        local haveKeywords = keywords ~= nil and entry:try_get("keywords") ~= nil
        if haveKeywords then
            for k,_ in pairs(keywords) do
                haveKeywords = true
                break
            end
            if haveKeywords then
                haveKeywords = false
                for k,_ in pairs(entry.keywords) do
                    haveKeywords = true
                    break
                end
            end
        end

		if haveKeywords then
			keywordsMatch = false
			for keyword,_ in pairs(entry.keywords) do
				if keywords[keyword] then
					keywordsMatch = true
				end
			end
		elseif keywords == nil and (entry:has_key("keywords") and #entry.keywords > 0) then
			keywordsMatch = false
		end

		if keywordsMatch then
			local dr = entry.dr

			if (entry.damageType == damageType or entry.damageType == "all") and (magical == false or (not entry.nonmagic)) then
				if entry.apply == 'Damage Reduction' then
                    if entry.stacks then
                        result.stacking_result = (result.stacking_result or 0) + dr
                    elseif dr > 0 then
					    result.dr = math.max((result.dr or 0), dr)
                    else
                        result.weakness = math.min((result.weakness or 0), dr)
                    end
				elseif entry.apply == 'Percent Reduction' then
					if result.percent == nil then
						result.percent = 1
					end
					result.percent = (1 - dr) * result.percent
				else
					if (result.resistance == nil and not resistanceCanceled) or result.resistance == entry.apply then
						result.resistance = entry.apply
					elseif result.resistance == 'Immune' or entry.apply == 'Immune' then
						result.resistance = 'Immune'
					else
						--we have a combination of vulnerable and resistance, which means we can't have either.
						result.resistance = nil
						resistanceCanceled = true
					end
				end
			end
		end
	end

    result.dr = (result.dr or 0) + (result.weakness or 0)
    result.dr = result.dr + (result.stacking_result or 0)
    result.weakness = nil
    result.stacking_result = nil
    if result.dr == 0 then
        result.dr = nil
    end

	return result
end

--calculates the creature's resistances. A combination of innate resistance and from modifiers.
--returns a list of ResistanceEntry objects.
function creature:CalculateResistances()
	local result = dmhub.DeepCopy(self:try_get('resistances', {}))
	local mods = self:GetActiveModifiers()
	for i,mod in ipairs(mods) do
		mod.mod:GetResistance(mod, self, result)
	end
	
	return result
end

--gets innate/builtin resistances.
function creature.GetResistances(self)
	return self:try_get('resistances', {})
end

function creature.SetResistances(self, val)
	self.resistances = val
end

function creature.DeleteResistance(self, deleteEntry)
	local newResistance = {}
	local curResistance = self:GetResistances()
	for i,entry in ipairs(curResistance) do
		if entry ~= deleteEntry then
			newResistance[#newResistance+1] = entry
		end
	end

	self:SetResistances(newResistance)
end

function creature:ConditionImmunityDescription()
	local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)

	local items = {}
	local immunities = self:GetConditionImmunities()
	for k,_ in pairs(immunities) do
		local condition = conditionsTable[k]
		if condition ~= nil then
			items[#items+1] = condition.name
		end
	end

	if #items == 0 then
		return ""
	end

	table.sort(items, function(a,b) return a < b end)
	return string.format(tr("Immune to %s."), pretty_join_list(items))
end

function creature.ResistanceDescription(self)
	local entries = self:CalculateResistances()
	if #entries <= 0 then
		return ""
	end

	local result = ''

	--handle damage reduction portion.
	local damageReductionEntries = {}
	for _,entry in ipairs(entries) do
		if entry.apply == 'Damage Reduction' then
			local matchingEntry = nil
			for _,existing in ipairs(damageReductionEntries) do
				if existing.nonmagic == entry:try_get("nonmagic", false) and existing.dr == entry:try_get("dr", 0) and not existing.damageTypes[entry.damageType] then
					matchingEntry = existing
				end
			end

			if matchingEntry == nil then
				matchingEntry = {
					dr = entry:try_get("dr", 0),
					nonmagic = entry:try_get("nonmagic", false),
					damageTypes = {},
				}
				damageReductionEntries[#damageReductionEntries+1] = matchingEntry
			end

			matchingEntry.damageTypes[entry.damageType] = true
		end
	end

	for _,entry in ipairs(damageReductionEntries) do
		local desc = ""
		if entry.nonmagic then
			desc = desc .. "non-magical "
		end

		local damageTypes = {}
		for k,_ in pairs(entry.damageTypes) do
			damageTypes[#damageTypes+1] = k
		end

		table.sort(damageTypes, function(a,b) return a < b end)

		for i,damageType in ipairs(damageTypes) do
			if i == 1 then
				desc = desc .. damageType
			elseif i == #damageTypes then
				if i > 2 then
					desc = desc .. ", and " .. damageType
				else
					desc = desc .. " and " .. damageType
				end
			else
				desc = desc .. ", " .. damageType
			end
		end

		desc = desc .. " damage is "
		if entry.dr >= 0 then
			desc = desc .. string.format("reduced by %d.\n", round(entry.dr))
		else
			desc = desc .. string.format("increased by %d.\n", round(entry.dr))
		end

		--convert the first character of desc to capital and append.
		result = result .. string.upper(string.sub(desc, 1, 1)) .. string.sub(desc, 2)
	end

	--Now regular resistance
	for _,resistanceType in ipairs(ResistanceEntry.resistanceTypes) do
		local matchingEntries = {}
		local matchingEntriesNonMagical = {}
		for _,entry in ipairs(entries) do
			if entry.apply == resistanceType then
				if entry.nonmagic then
					matchingEntriesNonMagical[#matchingEntriesNonMagical+1] = entry
				else
					matchingEntries[#matchingEntries+1] = entry
				end
			end
		end

		if #matchingEntries > 0 or #matchingEntriesNonMagical > 0 then
			local description = resistanceType .. ' to '
			if #matchingEntries > 0 then
				for i,entry in ipairs(matchingEntries) do
					if i ~= 1 then
						if i == #matchingEntries then
							description = description .. ', and '
						else
							description = description .. ', '
						end
					end

					description = description .. entry.damageType
				end

				if #matchingEntriesNonMagical > 0 then
					description = description .. ' and '
				end
			end

			if #matchingEntriesNonMagical > 0 then
				description = description .. 'non-magical '

				for i,entry in ipairs(matchingEntriesNonMagical) do
					if i ~= 1 then
						if i == #matchingEntriesNonMagical then
							if i == 2 then
								--no oxford comma for lists with just 2 items.
								description = description .. ' and '
							else
								description = description .. ', and '
							end
						else
							description = description .. ', '
						end
					end

					description = description .. entry.damageType
				end
			end

			description = description .. ' damage.'

			if result ~= "" then
				result = result .. '\n'
			end

			result = result .. description
		end
	end

	return result
end

function creature:GetGold()
	if self:has_key('gold') == false then
		return 0
	end

	return self.gold
end

function creature:GetCurrency(currencyid)
	local currencyTable = self:try_get("currency", {})
	local currencyEntry = currencyTable[currencyid]
	if currencyEntry ~= nil then
		return currencyEntry.value or 0
	end

	return 0
end

function creature:SetCurrency(currencyid, value, note)
	local currencyTable = self:get_or_add("currency", {})
	local currencyEntry = currencyTable[currencyid]
	if currencyEntry == nil then
		currencyEntry = {
			history = StatHistory.Create(),
		}
		currencyTable[currencyid] = currencyEntry
	end

	currencyEntry.value = value
	currencyEntry.history:Append{
		set = value,
		note = note,
	}
end

-------------------
-- Spells stuff.
-------------------
function creature:CalculateSpellcastingFeatures()
	local cache = rawget(self, "_tmp_spellcastingFeaturesCache")
	if cache ~= nil and cache.ngameupdate == dmhub.ngameupdate then
		return cache.result
	end

	local result = {}

	local modifiers = self:GetActiveModifiers()
	for _,mod in ipairs(modifiers) do
		proficiencyBonus = mod.mod:AccumulateSpellcastingFeatures(self, result)
	end

	for _,mod in ipairs(modifiers) do
		proficiencyBonus = mod.mod:ModifySpellcastingFeatures(self, result)
	end

	self._tmp_spellcastingFeaturesCache = {
		ngameupdate = dmhub.ngameupdate,
		result = result,
	}
	
	return result
end

function creature:SpellLevel()
	return self:CalculateAttribute('spellLevel', 0)
end

--keyType can be spellsPrepared, cantripsPrepared, or spellbookPrepared
function creature:AddPreparedSpellcastingSpell(spellcastingFeature, spellid, index, keyType)
	keyType = keyType or "spellsPrepared"

	local spellcasting = self:get_or_add("spellcasting", {})

	local featureInfo = spellcasting[spellcastingFeature.id]
	if featureInfo == nil then
		featureInfo = {}
		spellcasting[spellcastingFeature.id] = featureInfo
	end

	local list = featureInfo[keyType]
	if list == nil then
		list = {}
		featureInfo[keyType] = list
	end

	while #list < index do
		list[#list+1] = false
	end

	--see if the list already has this spell somewhere.
	local existingIndex = nil
	if spellid ~= nil then
		for i,existing in ipairs(list) do
			if existing == spellid then
				existingIndex = i
				break
			end
		end
	end

	--if we already have the spell then swap the slots.
	if existingIndex ~= nil then
		list[existingIndex] = list[index]
	end

	if spellid == nil then
		spellid = false
	end

	list[index] = spellid

	if keyType == "spellbookCopied" then
		--copied spells get the list minimized.
		for i=#list,1,-1 do
			if list[i] == false then
				table.remove(list, i)
			end
		end
	end
end

function creature:GetPreparedSpellcastingSpells(spellcastingFeature, keyType)
	keyType = keyType or "spellsPrepared"

	local spellcasting = self:try_get("spellcasting")
	if spellcasting == nil then
		return {}
	end

	local featureInfo = spellcasting[spellcastingFeature.id]
	if featureInfo == nil then
		return {}
	end

	return featureInfo[keyType] or {}
end

function creature:AlternativeSpellcastingCosts(spell)
	local result = {}
	local modifiers = self:GetActiveModifiers()
	for _,mod in ipairs(modifiers) do
		mod.mod:AlternativeSpellcastingCosts(mod, self, spell, result)
	end

	return result
end

function creature:AddPreparedSpell(spellid)
	local preparedSpells = self:get_or_add("preparedSpells", {})
	if not preparedSpells[spellid] then
		preparedSpells[spellid] = {
			timestamp = ServerTimestamp(),
		}
	end
end

function creature:RemovePreparedSpell(spellid)
	local preparedSpells = self:get_or_add("preparedSpells", {})
	preparedSpells[spellid] = nil
end

function creature:SwitchPreparedSpellOrder(s1, s2)
	local preparedSpells = self:get_or_add("preparedSpells", {})
	if preparedSpells[s1] ~= nil and preparedSpells[s2] ~= nil then
		local t1 = preparedSpells[s1].timestamp
		local t2 = preparedSpells[s2].timestamp
		preparedSpells[s1].timestamp = t2
		preparedSpells[s2].timestamp = t1
	end
end

local g_spellTypes = {"cantripsPrepared", "spellsPrepared"}

function creature:ListPreparedSpells()
	local features = self:CalculateSpellcastingFeatures()

	local spellsTable = dmhub.GetTable("Spells")

	local result = {}

	for _,feature in ipairs(features) do
		for _,spellType in ipairs(g_spellTypes) do
			local spells = self:GetPreparedSpellcastingSpells(feature, spellType)
			for _,spellid in ipairs(spells) do
				if spellid then
					local id,level = SpellcastingFeature.DecodeSpellId(spellid)

					local spellInfo = spellsTable[id]
					if spellInfo ~= nil then
						spellInfo = DeepCopy(spellInfo)
						spellInfo._tmp_temporaryClone = true
						spellInfo.spellcastingFeature = feature

						if level ~= nil then
							--the spell is encoded to cast at this level by force.
							spellInfo.castingLevel = tonumber(level)
						end

						result[#result+1] = spellInfo
					end
				end
			end
		end

		local grantedSpells = feature.grantedSpells
		for _,grant in ipairs(grantedSpells) do
			local spellid = grant.spellid
			local spellInfo = spellsTable[spellid]
			if spellInfo ~= nil then
				spellInfo = DeepCopy(spellInfo)
				spellInfo._tmp_temporaryClone = true
				spellInfo.spellcastingFeature = feature

				result[#result+1] = spellInfo
			end
		end
	end

	return result


--local preparedSpells = self:try_get("preparedSpells", {})
--local result = {}
--local spellsTable = dmhub.GetTable("Spells")
--for k,s in pairs(preparedSpells) do
--	local spell = spellsTable[k]
--	result[#result+1] = spell
--end

--table.sort(result, function(a,b)
--	return (tonumber(preparedSpells[a.id].timestamp) or 99999999999999) < (tonumber(preparedSpells[b.id].timestamp) or 99999999999999)

--end)
--
--return result
end

function creature:IsActivatedAbilityInnate(ability)
	for i,a in ipairs(self.innateActivatedAbilities) do
		if a == ability then
			return true
		end
	end

	return false
end

function creature:RemoveInnateActivatedAbility(ability)
	local abilities = {}
	for i,a in ipairs(self.innateActivatedAbilities) do
		if a ~= ability then
			abilities[#abilities+1] = a
		end
	end

	self.innateActivatedAbilities = abilities
end


function creature:IsActivatedAbilityLegendary(ability)
	for i,a in ipairs(self.innateLegendaryActions) do
		if a == ability then
			return true
		end
	end

	return false
end

--options:
--  excludeGlobal: no global modifiers.
--  bindCaster: make sure the abilities all have _tmp_boundCaster set so they can resolve who their caster is.
--  allLoadouts: get abilities from all loadouts, not just the equipped loadout.
--
--An important property is that innate abilities are not clones unless bindCaster is true. This allows the character sheet
--and other parts of the app to modify the innate abilities to update the creature.
function creature:GetActivatedAbilities(options)
	options = options or {}
	local result = {}

	local boundCaster = self
	if not options.bindCaster then
		boundCaster = nil
	end

	for i,a in ipairs(self.innateActivatedAbilities) do
		local ability = a
		if options.bindCaster then
			ability = DeepCopy(a)
			ability._tmp_boundCaster = self
		end
        if ability.categorization == nil then
        end
		result[#result+1] = ability
	end

	if options.legendary or options.legendary == nil then
		for i,a in ipairs(self.innateLegendaryActions) do

			local ability = a
			if options.bindCaster then
				ability = DeepCopy(a)
				ability._tmp_boundCaster = self
			end
			result[#result+1] = ability
		end
	end

	local modifiers = self:GetActiveModifiers()

	local attacks = self:GetAttackActions(options)
	for k,attack in pairs(attacks) do

		local ability = ActivatedAbility.Create{
			weaponid = attack:try_get("weaponid"),
			_tmp_boundCaster = boundCaster,
			name = attack.name,
			iconid = attack.iconid,
			_tmp_temporaryClone = true, --this is local only and can be freely modified.
			attackOverride = attack,
			description = attack:try_get("details", ""),
			targetType = 'target',
			range = attack:RangeNormal(),
			rangeDisadvantage = attack:RangeDisadvantage(),
			actionResourceId = attack:try_get("actionType"),
			behaviors = {
				ActivatedAbilityAttackBehavior.new{
					roll = "",
					attackTriggeredAbility = attack:try_get('attackTriggeredAbility'),
				}
			},
		}


		--if the weapon has ability modifiers, then apply them here.
		if attack:has_key("weapon") then
			attack.weapon:WeaponModifyAbility(self, ability)
		end

		result[#result+1] = ability
	end

	for i,mod in ipairs(modifiers) do
		if (not mod._global) or (not options.excludeGlobal) then
			mod.mod:FillActivatedAbilities(mod, self, result)
		end
	end


	local spellsTable = dmhub.GetTable("Spells")
	local innateSpellcasting = self:GetInnateSpellcasting()
	for _,entry in ipairs(innateSpellcasting) do
		local spell = spellsTable[entry.spellid]
		if spell ~= nil then
			local spellClone = dmhub.DeepCopy(spell)
			spellClone.usesSpellSlots = false
			spellClone.attributeOverride = entry.attrid
			spellClone._tmp_boundCaster = boundCaster
			spellClone.spellcastingFeature = SpellcastingFeature.new{
				attr = entry.attrid,
			}

			if entry.useResources then
				spellClone.usesSpellSlots = true
			elseif entry.usageLimitOptions ~= nil then
				spellClone.usageLimitOptions = entry.usageLimitOptions
			end

			result[#result+1] = spellClone
		end

	end

	local spells = self:ListPreparedSpells()

	for i,spell in ipairs(spells) do
		local s = DeepCopy(spell)
		s._tmp_boundCaster = boundCaster
		result[#result+1] = s
	end

	if self:has_key("ongoingEffects") then
		for i,cond in ipairs(self.ongoingEffects) do
			if cond:try_get('endAbility') ~= nil and not cond:Expired() then
				result[#result+1] = cond.endAbility
			end
		end
	end

	for i,aura in ipairs(self:try_get("auras", {})) do
		aura:FillActivatedAbilities(self, result)
	end

	--lookup any objects existing with affinity to our character (e.g. auras we control) and see if they provide us with abilities.
	local charid = dmhub.LookupTokenId(self)
	if charid ~= nil then
		local objects = game.GetObjectsWithAffinityToCharacter(charid)
		for _,obj in ipairs(objects) do
			for _,entry in ipairs(obj.attachedRulesObjects) do
				entry:FillActivatedAbilities(self, result)
			end
		end
	end

	local gearTable = dmhub.GetTable('tbl_Gear')
	for k,info in pairs(self:try_get('inventory', {})) do
		local itemInfo = gearTable[k]
		if itemInfo ~= nil and itemInfo:has_key("consumable") then
			local ability = DeepCopy(itemInfo.consumable)
			ability._tmp_boundCaster = self
			result[#result+1] = ability
		end
	end

	local removes = nil

	--let our modifiers modify the abilities we are returning.
	for i=1,#result do
		local ability = result[i]
		for i,mod in ipairs(modifiers) do
			ability = mod.mod:ModifyAbility(mod, self, ability)
			if ability == nil then
				break
			end
		end

		if ability == nil then
			removes = removes or {}
			removes[#removes+1] = i
		else
			result[i] = ability
		end
	end

	if removes ~= nil then
		for i=#removes,1,-1 do
			table.remove(result, removes[i])
		end
	end

	if self:SpellsPrevented() then
		--filter out any spells
		local filtered = {}
		for _,ability in ipairs(result) do
			if not ability.isSpell then
				filtered[#filtered+1] = ability
			end
		end

		result = filtered
	end

	return result
end

-----------------------------
-- Custom innate spellcasting
-----------------------------

--returns list of { spellid: string, attrid: string, usageLimitOptions: (optional) {resourceRefreshType: string, charges: number, resourceid: string } }
function creature:GetInnateSpellcasting()
	return self:try_get("innateSpellcasting", {})
end

function creature:SetInnateSpellcasting(index, val)
	local innateSpellcasting = self:get_or_add("innateSpellcasting", {})
	if val == nil then
		table.remove(innateSpellcasting, index)
	else
		innateSpellcasting[index] = val
	end
end

-------------------
-- Inventory stuff.
-------------------

creature.selectedLoadout = 0
creature.numLoadouts = 4


--implement the 'loadout' command to set current loadout.
Commands.loadout = function(str)
	local loadout = toint(str, 0)
	local tokens = dmhub.selectedTokens
	for _,tok in ipairs(tokens) do
		tok:ModifyProperties{
			description = "Change Loadout",
			execute = function()
				tok.properties.selectedLoadout = loadout
			end,
		}

		--instantly refresh the token.
		game.Refresh{
			tokens = {tok.charid},
		}
	end
end

Commands.light = function(str)
    local tokenids = {}
    for _,tok in ipairs(dmhub.selectedTokens) do
        tokenids[#tokenids+1] = tok.charid
        tok:ModifyProperties{
            description = "Change Loadout to Light",
            execute = function()
                if tok.properties.selectedLoadout == 1 then
                    tok.properties.selectedLoadout = 0
                else
                    if not tok.properties:try_get("initLight") then
                        --set to our preferred light if we've never made a different explicit choice.
                        local equipment = tok.properties:Equipment()
                        equipment.mainhand1 = tok.properties:GetDefaultLightSource()
                    end

                    tok.properties.selectedLoadout = 1
                end
            end,
        }
    end

    --instantly refresh the token.
    game.Refresh{
        tokens = tokenids
    }
end

function creature:GetEquippedLightSource()
    if self:try_get("initLight") then
        local equipment = self:Equipment()
        return equipment.mainhand1
    else
        return self:GetDefaultLightSource()
    end
end

creature.EquipmentSlots = {
	armor = { type = 'armor', icon = 'armor', tooltip = "Armor" },
	light = { type = 'light', icon = 'light', light = true, categories = {[EquipmentCategory.LightSourceId] = true} },
	mainhand = { type = 'mainhand', weapon = true, icon = 'hands', otherhand = 'offhand' },
	offhand = { type = 'offhand', shield = true, weapon = true, icon = 'hands',  },

	mainhand1 = { type = 'loadout', loadout = 1, main = true, icon = 'light', otherhand = 'offhand1', tooltip = "Light", categories = {[EquipmentCategory.LightSourceId] = true} },
	offhand1 = { type = 'loadout', loadout = 1, icon = 'hands', offhand = true, otherhand = 'mainhand1', tooltip = "Loadout 1, off hand" },
	mainhand2 = { type = 'loadout', loadout = 2, main = true, icon = 'hands', otherhand = 'offhand2', tooltip = "Loadout 2, main hand" },
	offhand2 = { type = 'loadout', loadout = 2, icon = 'hands', offhand = true, otherhand = 'mainhand2', tooltip = "Loadout 2, off hand" },
	mainhand3 = { type = 'loadout', loadout = 3, main = true, icon = 'hands', otherhand = 'offhand3', tooltip = "Loadout 3, main hand" },
	offhand3 = { type = 'loadout', loadout = 3, icon = 'hands', offhand = true, otherhand = 'mainhand3', tooltip = "Loadout 3, off hand" },

	belt1 = { type = 'belt', accessory = true, icon = 'belt' },
	belt2 = { type = 'belt', accessory = true, icon = 'belt' },
	belt3 = { type = 'belt', accessory = true, icon = 'belt' },
	belt4 = { type = 'belt', accessory = true, icon = 'belt' },

	attune1 = { type = 'attunement', weapon = false, attune = true, icon = 'attunement', tooltip = "Attunement slot for magical items" },
	attune2 = { type = 'attunement', weapon = false, attune = true, icon = 'attunement', tooltip = "Attunement slot for magical items" },
	attune3 = { type = 'attunement', weapon = false, attune = true, icon = 'attunement', tooltip = "Attunement slot for magical items" },
	attune4 = { type = 'attunement', weapon = false, attune = true, icon = 'attunement', tooltip = "Attunement slot for magical items" },
}

for i=1,5 do
    local key = string.format("leveled%d", i)
    creature.EquipmentSlots[key] = { type = 'leveled', leveled = true, tooltip = "Slot for leveled treasures" }
end

for i=1,10 do
    local key = string.format("trinket%d", i)
    creature.EquipmentSlots[key] = { type = 'trinket', trinket = true, tooltip = "Trinket slot" }
end

for slotid,slot in pairs(creature.EquipmentSlots) do
	slot.slotid = slotid
end

function creature.GetMainHandLoadoutSlots()
	local result = {}
	for k,v in pairs(creature.EquipmentSlots) do
		if v.loadout ~= nil and v.main then
			result[#result+1] = v
		end
	end

	table.sort(result, function(a,b) return a.loadout < b.loadout end)
	return result
end

function creature:GetWieldObjects()
	local result = self:GetLoadoutInfo(self.selectedLoadout)
	return result
end

function creature:GetLoadoutInfo(nslot)
	local equip = self:Equipment()
	local belt = {}
	local gearTable = dmhub.GetTable('tbl_Gear')
	for key,slot in pairs(creature.EquipmentSlots) do
		if slot.accessory and equip[key] then
			local gearEntry = gearTable[equip[key]]
			if gearEntry ~= nil and gearEntry:has_key("itemObjectId") and gearEntry:DisplayOnToken() then
				belt[#belt+1] = equip[key]
			end
		end
	end

	local mainhand = equip[string.format("mainhand%d", nslot)]
	local offhand = equip[string.format("offhand%d", nslot)]

	if mainhand ~= nil then
		local gearEntry = gearTable[mainhand]
		if gearEntry == nil or (not gearEntry:DisplayOnToken()) then
			mainhand = nil
		end
	end

	if offhand ~= nil then
		local gearEntry = gearTable[offhand]
		if gearEntry == nil or (not gearEntry:DisplayOnToken()) then
			offhand = nil
		end
	end

	local result = {
		mainhand = mainhand,
		offhand = offhand,
		belt = belt,
	}

	return result
end

function creature:EquipmentInUse()

	local result = {}
	local equip = self:Equipment()
	for k,v in pairs(creature.EquipmentSlots) do
		local item = equip[k]
		if item ~= nil then
			if v.loadout == nil or v.loadout == self.selectedLoadout then
				result[#result+1] = item
			end
		end
	end

	return result
end

--mapping of equipment slots -> itemid
function creature:Equipment()
	return self:get_or_add('equipment', {})
end

--meta information about equipment.
function creature:EquipmentMeta()
	return self:get_or_add('equipmentMeta', {})
end

function creature:ClearEquipmentMetaSlot(slotid)
	local meta = self:get_or_add('equipmentMeta', {})
	meta[slotid] = nil
end

function creature:EquipmentMetaSlot(slotid)
	local meta = self:get_or_add('equipmentMeta', {})
	local result = meta[slotid]
	if result == nil then
		result = {}
		meta[slotid] = result
	end

	return result
end

--unequip an item returning its id.
function creature:Unequip(slotid)

	local metaSlot = self:EquipmentMetaSlot(slotid)
	if metaSlot.twohanded then
		--if we're two handed, then unequip the other hand, be careful not to recurse infinitely.
		metaSlot.twohanded = nil

		local slotInfo = creature.EquipmentSlots[slotid]
		if slotInfo ~= nil and slotInfo.otherhand ~= nil then
			self:EquipmentMetaSlot(slotInfo.otherhand).twohanded = nil

			local itemid = self:Unequip(slotInfo.otherhand)
			if itemid ~= nil then
				return itemid
			end
		end
	end


	local itemid = self:GetEquipmentOrShadowInSlot(slotid)
	if itemid == nil then
		return nil
	end

	if self:HaveNonSharedEquipmentInSlot(slotid, itemid) then
		self:GiveItem(itemid, 1)
	end
	self:SetEquipmentInSlot(slotid, nil)
	self:ClearEquipmentMetaSlot(slotid)
	return itemid
end

function creature:NumberOfWeaponsWielded()
	local item1 = self:GetEquipmentItemInSlot(string.format("mainhand%d", self.selectedLoadout))
	local item2 = self:GetEquipmentItemInSlot(string.format("offhand%d", self.selectedLoadout))

	local result = 0

	if item1 ~= nil and item1.type == "Weapon" then
		result = result+1
	end

	if item2 ~= nil and item2.type == "Weapon" then
		result = result+1
	end

	return result
end

function creature:WieldingTwoHanded()
	local metaSlot = self:EquipmentMetaSlot(string.format("offhand%d", self.selectedLoadout))
	if metaSlot.twohanded then
		return true
	end

	return false
end

function creature.GetShield(self)
	local shield = self:GetEquipmentItemInSlot(string.format("offhand%d", self.selectedLoadout))
	if shield ~= nil and shield.type == "Shield" then
		return shield
	end

	return nil
end

function creature.GetArmorCategory(self)
	local armor = self:GetArmor()
	if armor == nil then
		return nil
	end

	local cat = armor:try_get("equipmentCategory")
	if cat ~= nil then
		local catTable = dmhub.GetTable('equipmentCategories') or {}
		local catInfo = catTable[cat]
		if catInfo ~= nil then
			return catInfo.name
		end
	end
	return nil
end

function creature.GetArmor(self)
	local armor = self:GetEquipmentItemInSlot('armor')
	if armor ~= nil then
		return armor
	end

	return nil
end

function creature.SetEquipmentShadowInSlot(self, slotName, item)
	local itemid = nil
	if item ~= nil then
		itemid = item.id
	end

	local metaSlot = self:EquipmentMetaSlot(slotName)
	metaSlot.shadow = item

end

function creature.SetEquipmentInSlot(self, slotName, item)
	local itemid = nil
	if item ~= nil then
		itemid = item.id
	end

	self:Equipment()[slotName] = itemid
	self:EquipmentMetaSlot(slotName).share = nil
end

function creature.GetEquipmentOrShadowInSlot(self, slotName)
	local result = self:Equipment()[slotName]
	if result == nil then
		local metaSlot = self:EquipmentMetaSlot(slotName)
		return metaSlot.shadow
	end

	return result
end

function creature.GetEquipmentShadowOrTwoHandInSlot(self, slotName)
	local result = self:Equipment()[slotName]
	if result == nil then
		local metaSlot = self:EquipmentMetaSlot(slotName)
		if metaSlot.twohanded then
			local slotInfo = creature.EquipmentSlots[slotName]
			result = self:Equipment()[slotInfo.otherhand]
			if result ~= nil then
				return result
			end
		end

		return metaSlot.shadow
	end

	return result
end

function creature.HaveNonSharedEquipmentInSlot(self, slotName, itemid)
	if self:Equipment()[slotName] ~= itemid then
		return false
	end

	if self:IsEquipmentShared(slotName) then
		return false
	end

	return true
end

function creature.IsEquipmentShared(self, slotName)
	if self:GetEquipmentItemInSlot(slotName) == nil then
		return false
	end

	local meta = self:EquipmentMeta()
	if meta == nil or meta[slotName] == nil or meta[slotName].share == nil then
		return false
	end

	local count = 0
	local share = meta[slotName].share
	for k,v in pairs(meta) do
		if v.share == share then
			count = count + 1
		end
	end

	return count > 1
end

function creature.GetEquipmentInSlot(self, slotName)
	return self:Equipment()[slotName]
end

function creature.GetEquipmentItemInSlot(self, slotName)
	local itemid = self:Equipment()[slotName]
	if itemid == nil then
		return nil
	end
	local gearTable = dmhub.GetTable('tbl_Gear')
	return gearTable[itemid]
end

function creature.SetItemQuantity(self, itemid, quantity, slotIndex)
	if not self:has_key('inventory') then
		self.inventory = {}
	end

	if quantity == nil or quantity <= 0 then
		self.inventory[itemid] = nil

	else
		if self.inventory[itemid] == nil then
			local entry = { quantity = quantity }
			if slotIndex ~= nil then
				entry.slots = {
					{
						slot = slotIndex,
					}
				}
			end

			self.inventory[itemid] = entry
		else
			local entry = self.inventory[itemid]
			local delta = quantity - entry.quantity
			entry.quantity = quantity

			if slotIndex ~= nil then
				for _,slot in ipairs(self.inventory[itemid].slots or {}) do
					if slot.slot == slotIndex and slot.quantity ~= nil then
						slot.quantity = slot.quantity + delta
					end
				end
			end
		end
	end

	self:EnsureInventorySlots(itemid)
end

function creature:GetItemQuantityIncludingEquipment(itemid)
	local result = 0
	local entry = self:try_get("inventory", {})[itemid]
	if entry ~= nil then
		result = entry.quantity
	end


	local meta = self:EquipmentMeta() or {}

	local sharesCounted = {}
	for k,equipid in pairs(self:Equipment()) do
		if itemid == equipid then

			local slotInfo = creature.EquipmentSlots[k]
			local metaSlot = meta[k]

			if metaSlot == nil or metaSlot.share == nil or sharesCounted[metaSlot.share] == nil then
				result = result+1
				if metaSlot ~= nil and metaSlot.share ~= nil then
					sharesCounted[metaSlot.share] = true
				end
			end
		end
	end
	
	return result
end

--returns a { itemid -> quantity } table of unique items held in equipment slots.
function creature:GetEquipmentInAllSlots()
	local result = {}
	local sharesCounted = {}
	local meta = self:EquipmentMeta() or {}
	for k,equipid in pairs(self:Equipment()) do
		local hand = nil
		local slotInfo = creature.EquipmentSlots[k]
		if slotInfo.loadout ~= nil then
			hand = cond(slotInfo.main, true, false)
		end

		local metaSlot = meta[k]
		if metaSlot == nil or metaSlot.share == nil or sharesCounted[metaSlot.share] == nil then
			result[equipid] = (result[equipid] or 0) + 1

			if metaSlot ~= nil and metaSlot.share ~= nil then
				sharesCounted[metaSlot.share] = true
			end
		end
	end

	return result
end

--is this creature considered to be 'using' the given equipment slot.
--Generally true if the slot is filled. For light, will only be
--if the light is turned on.
function creature:IsUsingEquipmentSlot(slotid)
	local equip = self:GetEquipmentItemInSlot(slotid)
	if equip == nil then
		return false
	end

	return true
end



--is this creature currently using a light it has equipped?
function creature:IsUsingLight()
	return false
end

function creature:SetUsingLight(val)
	self.lighton = val
end

--get the light the creature is currently emitting.
function creature:GetLight()
	return nil
end

function creature:GetHeight()
	return 6
end

function creature:GetVisionRange(range)
	range = self:CalculateAttribute("visionrange", range)

	return range
end

--get the creature's darkvision radius.
function creature:GetDarkvision()
	local darkvision = self:try_get("darkvision", 0)
	darkvision = self:CalculateAttribute("darkvision", darkvision)
	
	if darkvision <= 0 then
		return nil
	end

	return darkvision
end

--get the creature's custom senses aside from regular vision.
--this is called by DMHub.
-- returns a {{name = string, radius = number, light = bool, dark = bool, penetrateWalls = bool}}
function creature:GetCustomVisionSenses()
	local result = {}
	local darkvision = self:GetDarkvision()

	if darkvision ~= nil then
		result[#result+1] = {
			name = "Darkvision",
			radius = darkvision,
			light = false,
			dark = true,
			penetrateWalls = false,
			fieldOfView = true,
		}
	end

	local t = dmhub.GetTable(VisionType.tableName) or {}
	for k,v in pairs(t) do
		if not v.hidden and v.type ~= "none" then
			local radius = self:CalculateCustomVision(v)
			if radius ~= nil and radius > 0 then
				result[#result+1] = {
					name = v.name,
					radius = radius,
					light = true,
					dark = (v.type == "dark"),
					penetrateWalls = v.penetrateWalls,
					fieldOfView = v.fieldOfView,
				}
			end
		end
	end


	return result
end

creature._tmp_grabbedby = false

local g_grabbedid = "70504ebe-3899-41d3-9f60-74b52ce35e39"
local g_proneid = "da6867b1-01e3-4570-8d1b-1b94ea1ea343"

function creature:Invalidate()
	self._tmp_modifiers = nil
	self._tmp_modifiersRefresh = nil
	self._tmp_modifiersRefreshExcludingAuras = nil
	self._tmp_attr = nil
	self._tmp_creaturesize = nil
	self._tmp_spellcastingFeaturesCache = nil
	self._tmp_calculatingActiveModifiers = nil
    self._tmp_resources = nil
    self._tmp_languagesKnown = nil
    self._tmp_grabbedby = nil
    self._tmp_aggroColor = nil
    self._tmp_suspended = nil
    self._tmp_prone = nil
    self._tmp_conditionExplanations = nil
end

--all the languages that creatures controlled by the local player know.
creature.g_languagesKnownLocally = {}

local g_languagesKnownRefresh = nil

--local g_playerColor = core.Color{ r = 1, g = 0.301, b = 0.037, a = 1, }
local g_playerColor = core.Color{ r = 0, g = 0.301, b = 1, a = 1, }
local g_monsterColor = core.Color{ r = 1, g = 0, b = 0, a = 1, }

local g_conditionHiddenId = "31daf7f6-f77c-4f73-8eab-43e2d0f123c0"

--called by dmhub whenever tokens are refreshed with a new game state.
function creature:RefreshToken(token)
	self:ValidateAndRepair()

    self:Invalidate()

	local builtinEffects = {}

	if token.squeezed then
		local squeezedEffect = CharacterOngoingEffect.effectsByName["Squeezed"]
		if squeezedEffect ~= nil then
			builtinEffects[#builtinEffects+1] = CharacterOngoingEffectInstance.new{
				ongoingEffectid = squeezedEffect.id,
				duration = 1,
				time = TimePoint.Create(),
			}
		end
	end

	self._tmp_builtinOngoingEffects = builtinEffects

	local modifiers = self:GetActiveModifiers()
    self._tmp_down = self:IsDown()

    for _,modifier in ipairs(modifiers) do
        modifier.mod:OnTokenRefresh(modifier, self, token)
    end

    if dmhub.initiativeQueue ~= nil and (not dmhub.initiativeQueue.hidden) then
        local initiativeid = InitiativeQueue.GetInitiativeId(token)
        local isplayer = dmhub.initiativeQueue:IsEntryPlayer(initiativeid)
        if isplayer then
            self._tmp_aggroColor = g_playerColor
        else
            self._tmp_aggroColor = g_monsterColor
        end
    end

    self._tmp_grabbedby = nil

    --check if grabbed.
    local inflictedConditions = self:try_get("inflictedConditions")
    if inflictedConditions ~= nil then
        local grabbed = inflictedConditions[g_grabbedid]
        if grabbed ~= nil and grabbed.casterInfo ~= nil then
            self._tmp_grabbedby = grabbed.casterInfo.tokenid
        end

        if inflictedConditions[g_proneid] ~= nil then
            self._tmp_prone = true
        end
    end

	--check if any inflicted conditions or ongoing effects no longer sustain.
	if token.activeControllerId == nil then
        if self:has_key("inflictedConditions") then
            local removes
            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for k,v in pairs(self.inflictedConditions) do
                local conditionInfo = conditionsTable[k]
                if conditionInfo ~= nil and conditionInfo.sustainFormula ~= "" then
                    local result = dmhub.EvalGoblinScriptDeterministic(conditionInfo.sustainFormula, GenerateSymbols(self), 1, "Test ongoing effect sustains")
                    if not GoblinScriptTrue(result) then
                        removes = removes or {}
                        removes[#removes+1] = k
                    end
                end
            end

            if removes ~= nil then
                token:ModifyProperties{
                    description = "Remove expired inflicted conditions",
                    execute = function()
                        for _,k in ipairs(removes) do
                            self.inflictedConditions[k] = nil
                        end
                    end,
                }
            end
        end

		local ongoingEffects = self:ActiveOngoingEffects(true)
		if #ongoingEffects > 0 then
			local removes = nil
			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
			for i,entry in ipairs(ongoingEffects) do
				local ongoingEffectInfo = ongoingEffectsTable[entry.ongoingEffectid]
				if ongoingEffectInfo ~= nil and trim(ongoingEffectInfo.sustainFormula) ~= "" then
					local result = dmhub.EvalGoblinScriptDeterministic(ongoingEffectInfo.sustainFormula, GenerateSymbols(self), 1, "Test ongoing effect sustains")
					if not GoblinScriptTrue(result) then
						if removes == nil then
							removes = {}
						end

						removes[#removes+1] = i
					end
				end
			end

			if removes ~= nil then
				for i=#removes,1,-1 do
					local index = removes[i]
					table.remove(ongoingEffects, index)
				end

				token:ModifyProperties{
					description = "Remove expired ongoing effects",
					execute = function()
						self.ongoingEffects = ongoingEffects
					end,
				}
			end
		end
	end

	self:RefreshAnimations(token)

	local triggeredEvents = self:try_get("triggeredEvents")
	if triggeredEvents ~= nil and #triggeredEvents > 0 and triggeredEvents[1] and triggeredEvents[1].userid and triggeredEvents[1].userid == dmhub.userid then
		local token = dmhub.LookupToken(self)
		if token ~= nil then
			for _,eventInfo in ipairs(triggeredEvents) do
				if TimestampAgeInSeconds(eventInfo.timestamp) < 30 then
                    local info = eventInfo.info
                    if info ~= nil then
                        local deserializedInfo = {}
                        for k,v in pairs(info) do
                            if type(v) == "string" and string.starts_with(v, "charid:") then
                                local charid = string.sub(v, 8)
                                local charInfo = dmhub.GetCharacterById(charid)
                                if charInfo ~= nil then
                                    deserializedInfo[k] = charInfo.properties
                                end
                            else
                                deserializedInfo[k] = v
                            end
                        end

                        info = deserializedInfo
                    end

					self:TriggerEvent(eventInfo.eventName, info)
				end
			end

			token:ModifyProperties{
				description = "Clear Triggers",
				execute = function()
					self.triggeredEvents = nil
				end,
			}
		end
	end

    if self:HasCondition(g_conditionHiddenId) then
        local q = dmhub.initiativeQueue
        if q ~= nil and not q.hidden then
            local id = q:GetTurnId()
            self._tmp_hiddenTurnId = id
        end
    end

    if self.currentMoveType == "fly" and (not self:CanFly()) then
        self.currentMoveType = "walk"
    end

    if token.canControl then
        --this token is controlled by the local player, so it contributes toward
        --the languages known by the player.
        if g_languagesKnownRefresh ~= dmhub.ngameupdate then
            g_languagesKnownRefresh = dmhub.ngameupdate
            creature.g_languagesKnownLocally = {}
        end

        for k,_ in pairs(self:LanguagesKnown()) do
            creature.g_languagesKnownLocally[k] = true
        end
    end

	self:PumpRemoteInvokes()
end

function creature:PumpRemoteInvokes()
	local remoteInvokes = self:try_get("remoteInvokes")
	if remoteInvokes == nil or #remoteInvokes == 0 or remoteInvokes[1].userid ~= dmhub.userid then
		return
	end


	if not GameHud.instance then
		return
	end

	if GameHud.instance:AvailableToInteract() == false then
		GameHud.instance:QueueInteraction(function()
			self:PumpRemoteInvokes()
		end)
		return
	end

	local token = dmhub.LookupToken(self)
	if token ~= nil then
		local invoke = DeepCopy(remoteInvokes[1])

		token:ModifyProperties{
			description = "Clear Invoke",
			execute = function()
				if #remoteInvokes == 1 then
					self.remoteInvokes = nil
				else
					table.remove(remoteInvokes, 1)
				end
			end,
		}

		if TimestampAgeInSeconds(invoke.timestamp) < 30 then
			dmhub.Coroutine(function()
				invoke:Invoke()
			end)
		end
	end
end

function creature:GetBaseCreatureSize()
	return self:try_get("creatureSize")
end

function creature:GetBaseCreatureSizeNumber()
	local key = self:GetBaseCreatureSize()
	if not key then
		return nil
	end

	return creature.sizeToNumber[key]
end

function creature:GetCalculatedCreatureSizeAsNumber()
	local result = self:try_get("_tmp_creaturesize") or self:GetBaseCreatureSize()
	return creature.sizeToNumber[result or "Medium"] or 1
end

local g_count = 0

--gets a list of CharacterModifier objects which are currently active on this creature.
function creature:GetActiveModifiers()
	if self:try_get("_tmp_modifiersRefresh") == dmhub.ngameupdate then
		return self._tmp_modifiers
	end

	--protect against recursion.
	if rawget(self, "_tmp_calculatingActiveModifiers") then
		return self._tmp_calculatingActiveModifiers
	end

	self._tmp_appearance = nil
	self._tmp_creaturesize = self:GetBaseCreatureSize()
 
	self._tmp_calculatingActiveModifiers = {}
	local res = self:GetActiveModifiersExcludingAuras(self._tmp_calculatingActiveModifiers)
	self._tmp_calculatingActiveModifiers = nil

	local result = {}
	for i,item in ipairs(res) do
		result[#result+1] = item
	end

    --allow this to query while getting modifiers from auras.
	self._tmp_modifiersRefresh = dmhub.ngameupdate
	self._tmp_modifiers = result

	self:FillModifiersFromAuras(result)

	for i,mod in ipairs(result) do
		mod.mod:RefreshGameState(mod, self)
	end

	if self:has_key("_tmp_creaturesize") then
		local numCreatureSize = creature.sizeToNumber[self._tmp_creaturesize]
		if numCreatureSize ~= nil then
			numCreatureSize = self:CalculateAttribute("creatureSize", numCreatureSize)
			if creature.sizes[numCreatureSize] ~= nil then
				self._tmp_creaturesize = creature.sizes[numCreatureSize]
			end
		end
	end

    self._tmp_disguised = self:CalculateAttribute("disguised", 0)

	return result
end

function creature:GetActiveModifiersExcludingAuras(calculatingModifiers)
	if self:try_get("_tmp_modifiersRefreshExcludingAuras") == dmhub.ngameupdate then
		return self._tmp_modifiers_excluding_auras
	end

	self._tmp_modifiers_excluding_auras = self:CalculateActiveModifiers(calculatingModifiers)
	self._tmp_modifiersRefreshExcludingAuras = dmhub.ngameupdate

	return self._tmp_modifiers_excluding_auras
end

function creature:FillModifiersFromAuras(result)
	local token = dmhub.LookupToken(self)
	if token == nil then
		return
	end

	local auras = self:GetAurasAffecting(token)
	if auras == nil or #auras == 0 then
		return
	end

	local resultCount = #result

	for _,aura in ipairs(auras) do
		local instance = aura.auraInstance
		for _,modifier in ipairs(instance:GetModifiers()) do
			if modifier:PassesFilter(self) then
				result[#result+1] = {
					mod = modifier
				}
			end
		end
	end

	--see if the aura added any conditions and calculated them out.
	local bestowedConditions = {}

	for i=resultCount+1,#result do
		local modifier = result[i]
		if modifier.mod:CanBestowConditions() and modifier.mod:PassesFilter(self, modifier) then
			modifier.mod:BestowConditions(modifier, self, bestowedConditions)
		end
	end


	for k,v in pairs(bestowedConditions) do
		local newCondition = (self._tmp_calculatedConditions[k] or 0) == 0
		self._tmp_directConditions[k] = (self._tmp_directConditions[k] or 0) + v
		self._tmp_calculatedConditions[k] = (self._tmp_calculatedConditions[k] or 0) + v

		if newCondition then
			--add the condition's modifiers here.
			--TODO: add stacks onto existing conditions.
			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
			local conditionInfo = conditionsTable[k]
			conditionInfo:EnsureDomains()
			for _,mod in ipairs(conditionInfo.modifiers) do
				result[#result+1] = {
					mod = mod,
					stacks = v,
				}
			end
		end
	end
end

function creature:FillEquipmentModifiers(result)
	local gearTable = dmhub.GetTable('tbl_Gear')
	for slotid,itemid in pairs(self:EquipmentInUse()) do
		local item = gearTable[itemid]
		if item then
			item:EnsureDomains()
			local features = item:try_get("features")
			if features then
				for i,feature in ipairs(features) do
                    feature:FillModifiers(self, result)
				end
			end

			local itemProperties = item:try_get("properties")
			for k,v in pairs(itemProperties or {}) do
				local propInfo = WeaponProperty.Get(k)
				if propInfo ~= nil and propInfo:has_key("features") then
					for _,feature in ipairs(propInfo.features) do
                        feature:FillModifiers(self, result)
					end
				end
			end
		end
	end

	local armor = self:GetArmor()
	if armor ~= nil then
		armor:FillWornArmorModifiers(self, result)
	end
end

function creature:FillModifiersFromModifiers(modifiers)
	local result = {}
	for i,mod in ipairs(modifiers) do
		mod.mod:FillModifiers(mod, self, result)
	end

	for i,mod in ipairs(result) do
		modifiers[#modifiers+1] = result
	end
end

local g_profileCalculateActiveModifiers = dmhub.ProfileMarker("CalculateActiveModifiers")
local g_profileCalculateActiveModifiersBase = dmhub.ProfileMarker("CalculateActiveModifiers.Base")
local g_profileCalculateActiveModifiersTemporal = dmhub.ProfileMarker("CalculateActiveModifiers.Temporal")
local g_profileCalculateActiveModifiersModifiers = dmhub.ProfileMarker("CalculateActiveModifiers.Modifiers")
local g_profileCalculateActiveModifiersFilters = dmhub.ProfileMarker("CalculateActiveModifiers.Filters")
local g_profileCalculateActiveModifiersCondition = dmhub.ProfileMarker("CalculateActiveModifiers.Condition")

function creature:CalculateActiveModifiers(calculatingModifiers)
    g_profileCalculateActiveModifiers:Begin()
	local result = calculatingModifiers or {}
    g_profileCalculateActiveModifiersBase:Begin()
	self:FillBaseActiveModifiers(result)
    g_profileCalculateActiveModifiersBase:End()
    g_profileCalculateActiveModifiersTemporal:Begin()
	self:FillTemporalActiveModifiers(result)
    g_profileCalculateActiveModifiersTemporal:End()
    g_profileCalculateActiveModifiersModifiers:Begin()
	self:FillModifiersFromModifiers(result)
    g_profileCalculateActiveModifiersModifiers:End()
    g_profileCalculateActiveModifiersFilters:Begin()
	result = self:FilterModifiers(result)
    g_profileCalculateActiveModifiersFilters:End()
    g_profileCalculateActiveModifiersCondition:Begin()
	self:CalculateConditionModifiers(result)
    g_profileCalculateActiveModifiersCondition:End()
    g_profileCalculateActiveModifiers:End()
	return result
end

function creature:FilterModifiers(modifiers)

    local filteringModifiers = {}
    local filteringModifiersIndexes = {}
    local i = 1
    while i <= #modifiers do
        if modifiers[i].mod:HasFilter() then
            filteringModifiersIndexes[#filteringModifiersIndexes+1] = i + #filteringModifiers
            filteringModifiers[#filteringModifiers+1] = modifiers[i]
            table.remove(modifiers, i)
        else
            i = i+1
        end
    end

    self._tmp_attr = nil

    local numFiltered = 0
    for i,mod in ipairs(filteringModifiers) do
        local passed = mod.mod:PassesFilter(self, mod)
        if passed then
            table.insert(modifiers, filteringModifiersIndexes[i] - numFiltered, mod)
        else
            numFiltered = numFiltered + 1
        end
    end

    self._tmp_attr = nil

    return modifiers
end

local g_ZeroHitpointsConditions = {"Unconscious", "Incapacitated", "Prone"}

function creature:CalculateConditionModifiers(modifiers)


	for k,rule in pairs(GameSystem.registeredConditionRules) do
		if rule.rule(self, modifiers) then
			for _,condName in ipairs(rule.conditions) do
				local cond = CharacterCondition.conditionsByName[string.lower(condName)]
				if cond then
					for _,mod in ipairs(cond.modifiers) do
						modifiers[#modifiers+1] = { mod = mod }
					end
				end
			end
		end
	end
end

function creature:GetLevelChoices()
	local result = self:get_or_add("levelChoices", {})
    result.raceid = rawget(self, "raceid")
    return result
end

function creature:AddFeat(featid)
	local feats = self:get_or_add("creatureFeats", {})
	feats[#feats+1] = featid
end

function creature:RemoveFeat(index)
	local feats = self:get_or_add("creatureFeats", {})
	table.remove(feats, index)
end

function creature:AddTemplate(templateid)
	local templates = self:get_or_add("creatureTemplates", {})
	templates[#templates+1] = templateid
end

function creature:RemoveTemplate(index)
	local templates = self:get_or_add("creatureTemplates", {})
	table.remove(templates, index)
end

function creature:GetActiveTemplates()

	local result = {}
	local creatureTemplates = self:try_get("creatureTemplates")
	if creatureTemplates ~= nil and #creatureTemplates > 0 then
		local templatesTable = dmhub.GetTable("creatureTemplates") or {}
		for _,templateid in ipairs(creatureTemplates) do
			local templateInfo = templatesTable[templateid]
			if templateInfo ~= nil then
				result[#result+1] = templateInfo
			end
		end
	end

	return result
end

--system for extensions adding custom ways to add modifiers to creatures.
creature.customFeatureCalculations = {}

function creature.RegisterFeatureCalculation(args)
	creature.customFeatureCalculations[args.id] = args
end

function creature:FillBaseActiveModifiers(result)
	local modTable = dmhub.GetTable(GlobalRuleMod.TableName) or {}
	local globalFeatures = {}
    local isretainer = self:try_get("_tmp_retainer") or false
	local ismonster = (not isretainer) and self:IsMonster()
	local ischaracter = self.typeName == "character"
    local iscompanion = self.typeName == "AnimalCompanion"

	--global features first, to do base-level rules like critical hits etc.
	for k,mod in pairs(modTable) do
		if (not mod:try_get("hidden")) and ((ischaracter and mod.applyCharacters) or (ismonster and mod.applyMonsters) or (isretainer and mod.applyRetainers)) or (iscompanion and mod.applyCompanions) then
			mod:FillClassFeatures(self:GetLevelChoices(), globalFeatures)
		end
	end

	for i,feature in ipairs(globalFeatures) do
        feature:FillModifiers(self, result, {_global = true})
	end

	--add features from custom calculations.
	for k,calc in pairs(self.customFeatureCalculations) do
		local features = {}
		calc.FillFeatures(self, features)
		for i,feature in ipairs(features) do
            feature:FillModifiers(self, result)
		end
	end

	--add features from templates.
	for i,feat in ipairs(self:GetActiveTemplates()) do
		local features = {}
		feat:FillClassFeatures(self:GetLevelChoices(), features)
		for i,feature in ipairs(features) do
            feature:FillModifiers(self, result)
		end
	end

	if self:has_key("monsterSpellcasting") then
		result[#result+1] = {
			mod = self.monsterSpellcasting
		}
	end
end

--record a condition into a 'conditions' table passed in which is a {condid -> stacks} table.
--this traces down into underlying conditions.
function creature:RecordCondition(condid, stacks, conditions, maxdepth)
	local dataTable = dmhub.GetTable(CharacterCondition.tableName) or {}
	local conditionInfo = dataTable[condid]

	if conditionInfo == nil then
		return
	end

	conditions[condid] = (conditions[condid] or 0) + stacks

	if maxdepth > 1 then
		for underlyingid,_ in pairs(conditionInfo:GetUnderlyingConditions()) do
			self:RecordCondition(underlyingid, stacks, conditions, maxdepth-1)
		end
	end
end

function creature:DebugFlag()
	local tok = dmhub.LookupToken(self)
	return tok ~= nil and tok.debugFlag
end

local g_grabbedCondition = "70504ebe-3899-41d3-9f60-74b52ce35e39"

function creature:FillTemporalActiveModifiers(result)
    local startIndex = #result+1

	local conditions = {}

	local tok = dmhub.LookupToken(self)
	self._tmp_calculatedConditions = conditions

	local ongoingEffects = self:ActiveOngoingEffects()
	if #ongoingEffects > 0 then
		local stackable = {}
		local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
		for i,cond in ipairs(ongoingEffects) do
			local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]

			if ongoingEffectInfo == nil then
				if tok ~= nil then
					dmhub.CloudError(string.format("Invalid ongoing effect: %s -> %s", tok.charid, json(cond)))
					printf(string.format("Invalid ongoing effect: %s -> %s", tok.charid, json(cond)))
				end

			elseif stackable[cond.ongoingEffectid] ~= nil then
				local entry = stackable[cond.ongoingEffectid]
				for j=entry.begin, entry.finish do
					result[j].stacks = result[j].stacks + cond.stacks

				end

				if ongoingEffectInfo.condition ~= 'none' then
					self:RecordCondition(ongoingEffectInfo.condition, cond.stacks, conditions, 4)
				end
			else

				local stackableEntry = nil
				if ongoingEffectInfo.stackable then
					stackableEntry = { begin = #result+1 }
				end

				ongoingEffectInfo:EnsureDomains()
				for i,mod in ipairs(ongoingEffectInfo.modifiers) do
					result[#result+1] = {
						mod = mod,
						ongoingEffect = cond,
						stacks = cond.stacks,
					}
				end

				if stackableEntry ~= nil then
					stackableEntry.finish = #result
					stackable[cond.ongoingEffectid] = stackableEntry
				end

				if cond:has_key("repeatSaveModifier") then
					--if this has a modifier that will allow repeating a saving throw every round to remove it.
					result[#result+1] = {
						mod = cond.repeatSaveModifier
					}
				end

				--if this ongoing effect has an underlying condition then record us having that condition since conditions can also have modifiers.
				if ongoingEffectInfo.condition ~= 'none' then
					self:RecordCondition(ongoingEffectInfo.condition, cond.stacks, conditions, 4)
				end
			end
		end
	end


	for i,feature in ipairs(self:try_get('characterFeatures', {})) do
		if feature.EnsureDomains ~= nil then
			feature:EnsureDomains()
		end
        feature:FillModifiers(self, result)
	end

    local mount = tok ~= nil and tok.valid and tok.mount
    if mount then
        local mountCreature = mount.properties
        for i,mod in ipairs(mountCreature:GetActiveModifiers()) do
            mod.mod:FillRiderModifiers(mod, mountCreature, self, result)
        end
    end

	local temporaryEffects = self:try_get("_tmp_temporaryEffects", {})
	for i,effect in ipairs(temporaryEffects) do
		for i,mod in ipairs(effect.modifiers) do
			result[#result+1] = {
				mod = mod
			}
		end
	end

	local momentaryEffects = self:try_get("_tmp_momentaryEffects", {})
	for i,effect in ipairs(momentaryEffects) do
		for i,mod in ipairs(effect.modifiers) do
			result[#result+1] = {
				mod = mod
			}
		end
	end

	local persistentAbilityModifiers = self:PersistentAbilities()
	for i,mod in ipairs(persistentAbilityModifiers) do
		result[#result+1] = {
			mod = mod,
			temporal = true
		}
	end

	--if any modifiers we've accumulated so far themselves offer modifiers...
	local additionalModifiers = {}
	for _,mod in ipairs(result) do
		mod.mod:AddModifiers(self, additionalModifiers)
	end

	for _,mod in ipairs(additionalModifiers) do
		result[#result+1] = {
			mod = mod
		}
	end

    local allowEquipment = true
	for _,mod in ipairs(result) do
		if mod.mod:PreventsEquipment(mod, self) then
            allowEquipment = false
		end
	end

    if allowEquipment then
	    self:FillEquipmentModifiers(result)
    end


    self._tmp_numberOfCreaturesGrabbed = 0
    if self:IsCasterOfConditions() then
        --apply slow down if we are grabbing.
        --TODO: generalize this to make it so conditions can apply
        --modifiers to the source of the condition.
        self:VisitConditionCasterSource(function(condid, targetToken)
            if condid == g_grabbedCondition then
	            local ourSize = self:CalculateNamedCustomAttribute("SizeWhenGrabbing")
                local theirSize = targetToken.properties:GetCalculatedCreatureSizeAsNumber()

                self._tmp_numberOfCreaturesGrabbed = self._tmp_numberOfCreaturesGrabbed + 1

                if ourSize <= theirSize then
                    local grabbingFeature = MCDMImporter.GetStandardFeature("Grabbing")
                    if grabbingFeature ~= nil then
                        for _,modifier in ipairs(grabbingFeature.modifiers) do
                            result[#result+1] = {
                                mod = modifier,
                                stacks = 1,
                            }
                        end
                    end
                end
            end
        end)
    end


    self._tmp_conditionExplanations = {}
	self._tmp_directConditions = {}
	for i,modifier in ipairs(result) do
        --note that bestowing is super sensitive to being late in the process if it's filtered.
        --it will get any modifiers added to this point.
		if modifier.mod:CanBestowConditions() and modifier.mod:PassesFilter(self, modifier) then
			modifier.mod:BestowConditions(modifier, self, self._tmp_directConditions, self._tmp_conditionExplanations)
		end
	end


	for k,v in pairs(self._tmp_directConditions) do
		conditions[k] = (conditions[k] or 0) + v
	end

	--inflicted conditions are attached directly to the creature, calculate them here.
	if self:has_key("inflictedConditions") then
		for k,v in pairs(self.inflictedConditions) do
			conditions[k] = (conditions[k] or 0) + v.stacks
			conditions[k] = (conditions[k] or 0) + (v.stacks or 1)

            if v.riders ~= nil then
                local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                for _,riderid in ipairs(v.riders) do
                    local riderInfo = ridersTable[riderid]
                    if riderInfo ~= nil then
                        for i,mod in ipairs(riderInfo.modifiers) do
                            result[#result+1] = {
                                mod = mod,
                            }
                        end
                    end
                end
            end
		end
	end

	--we have a table of conditions based on ongoing effects, add any of their modifiers.
	local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
	for k,nstacks in pairs(conditions) do
		local conditionInfo = conditionsTable[k]
        if conditionInfo ~= nil then
            conditionInfo:EnsureDomains()
            for _,mod in ipairs(conditionInfo.modifiers) do
                result[#result+1] = {
                    mod = mod,
                    stacks = nstacks,
                }
            end
        end
	end

    --mark these all as being temporal modifiers.
    for i=startIndex,#result do
        result[i].temporal = true
    end
end


--given the name of an attribute and its base value, calculates all modifiers and provides a final value.
function creature:CalculateAttribute(attributeName, baseValue, mods)

	local cache = nil
	local key = nil
	
	if mods == nil then
        if not rawget(self, "_tmp_calculatingActiveModifiers") then
            --if we aren't already calculating modifiers, then we can get the modifiers early, here.
            mods = self:GetActiveModifiers()
        end


		cache = rawget(self, "_tmp_attr")
		key = string.format("%s-%s", attributeName, tostring(baseValue))
		if cache ~= nil and cache.nupdate == dmhub.ngameupdate then
			if cache[key] ~= nil then
				return cache[key]
			end
		else
			cache = {nupdate = dmhub.ngameupdate}
			self._tmp_attr = cache
		end
	end

	if baseValue == nil then
		baseValue = 0
	end

	local attributesCalculating = self:try_get("_tmp_attributesCalculating")
	if attributesCalculating == nil then
		self._tmp_attributesCalculating = {}
		attributesCalculating = self._tmp_attributesCalculating
	end

	if attributesCalculating[attributeName] ~= nil then
        --recursion protection.
        return attributesCalculating[attributeName]
	end

	attributesCalculating[attributeName] = baseValue

	local result = baseValue

	if mods == nil then
		mods = self:GetActiveModifiers()
	end

	for i,mod in ipairs(mods) do
		result = mod.mod:Modify(mod, self, attributeName, result)
		attributesCalculating[attributeName] = result
	end

	attributesCalculating[attributeName] = nil
	if cache ~= nil then
		if rawget(self, "_tmp_calculatingActiveModifiers") then
			--we're in the middle of calculating active modifiers, don't cache this since it will not be completely accurate.
			return result
		end

		cache[key] = result
	end

	return result
end

--given the name of an attribute and its base value, calculate a list of entries describing modifications made along the way.
--will return entries in the form { key = "Ring of Protection", value = "+1", previous = 12, current = 13, temporal = false }
function creature:DescribeModifications(attributeName, baseValue)
	local attributesCalculating = self:try_get("_tmp_attributesCalculatingModifications")
	if attributesCalculating == nil then
		self._tmp_attributesCalculatingModifications = {}
		attributesCalculating = self._tmp_attributesCalculatingModifications
	end

	local result = {}
	if attributesCalculating[attributeName] ~= nil then
		--recursion protection.
		return attributesCalculating[attributeName]
	end

	attributesCalculating[attributeName] = result

	local currentValue = baseValue
	local mods = self:GetActiveModifiers()
	for i,mod in ipairs(mods) do
		local item = mod.mod:DescribeModification(self, attributeName, currentValue)

		local prevValue = currentValue
		currentValue = mod.mod:Modify(mod, self, attributeName, currentValue)


		if item then
            item = table.shallow_copy(item)
            item.mod = mod.mod
            item.previous = prevValue
            item.current = currentValue
            if mod.temporal then
                item.temporal = true
            end
			result[#result+1] = item
		end
		

		if item then
			if prevValue == currentValue then
				item.unchanged = true
			elseif prevValue > currentValue then
				item.debuff = true
			end
		end

		attributesCalculating[attributeName] = currentValue
	end

	attributesCalculating[attributeName] = nil

	return result
end

function creature:DescribeResourceModifications(resourceid)
    local result = {}
    local resources = {}
	local mods = self:GetActiveModifiers()
	for i,mod in ipairs(mods) do
        local before = resources[resourceid] or 0
		mod.mod:GetNamedResources(mod, self, resources)
        local after = resources[resourceid] or 0
        if before ~= after then
            local entry = {
                key = mod.mod.name,
                value = after - before,
                mod = mod.mod,
                previous = before,
                current = after,
            }

            result[#result+1] = entry
        end
    end

    return result
end

--how high priority this creature is for purposes of determining primary token.
function creature.PrimaryTokenRank(self)
	return 0
end


--function called from dmhub to return a ranking as to how
--likely this token is to be a player's primary token.
dmhub.RankPrimaryToken = function(creature)
	if creature == nil then
		return -1000
	end
	return creature:PrimaryTokenRank()
end

--returns a list of damage roll modifiers in the format { mod = (Modifier), hint = (hint), context = (Modifier with context) }
function creature:GetDamageRollModifiers(attack, target, hitOptions)
	local damageRoll
	
	if attack ~= nil then
		damageRoll = attack:DescribeDamageRoll()
	else
		damageRoll = hitOptions.roll
	end

	local mods = shallow_copy_list(self:GetActiveModifiers())

	if attack ~= nil and attack:try_get("modifiers") then
		for i,mod in ipairs(attack.modifiers) do
			mods[#mods+1] = {
				mod = mod
			}
		end
	end

	local targetCreature = nil
	if target ~= nil then
		targetCreature = target.properties
	end

	local result = {}
	for i,mod in ipairs(mods) do

		local modInfo = mod.mod:DescribeModifyDamageRoll(mod, self, attack, targetCreature, hitOptions)

		if modInfo ~= nil then
			if hitOptions ~= nil and hitOptions.symbols ~= nil then
				modInfo.modifier:InstallSymbolsFromContext(hitOptions.symbols)
			end

			--add in the hint for this.
			modInfo.hint = modInfo.modifier:ShouldApplyDamageModifier(mod, self, attack, target, hitOptions)
			if modInfo.hint ~= nil then
				result[#result+1] = modInfo
			end
		end
	end

	if targetCreature ~= nil then
		local targetModifiers = target.properties:GetModifiersForDamageAgainstUs(self, attack)
		for i,mod in ipairs(targetModifiers) do
			result[#result+1] = mod
		end
	end

	return result
end

function creature:GetModifiersForDamageAgainstUs(attacker, attack)

	local result = {}

	local ourToken = dmhub.LookupToken(self)
	local attackerToken = dmhub.LookupToken(attacker)

	local modifiers = self:GetActiveModifiers()
	for i,mod in ipairs(modifiers) do
		local m = mod.mod:DescribeModifyDamageAgainstUs(mod, self, attacker, attack)
		if m ~= nil then
			m.hint = { result = true, justification = {} }
			result[#result+1] = m
		end
	end
	
	return result

end

--returns a list of { modifier = (CharacterModifier), context = (mod context), modFromTarget = true, hint = { result = true/false, justification = {string} }
function creature:GetModifiersForAttackAgainstUs(attacker, attack)

	local result = {}

	local ourToken = dmhub.LookupToken(self)
	local attackerToken = dmhub.LookupToken(attacker)

	if attack ~= nil and attack:IsRanged(attackerToken, ourToken) then


		local coverAmount = "none"
		local coverTooltip = "The amount of cover the target has affects chance to hit."

		if ourToken ~= nil and attackerToken ~= nil then
			local coverInfo = dmhub.GetCoverInfo(attackerToken, ourToken)
			if coverInfo ~= nil then
				if coverInfo.cover == 1 then
					coverTooltip = string.format("%s\n<color=#ffaaaaff>There is a %s in the way, providing the target Half Cover.", coverTooltip, coverInfo.description)
					coverAmount = "half"
				elseif coverInfo.cover == 2 then
					coverAmount = "threequarters"
					coverTooltip = string.format("%s\n<color=#ffaaaaff>There is a %s in the way, providing the target Three Quarters Cover.", coverTooltip, coverInfo.description)
				else
					coverAmount = "fullcover"
					coverTooltip = string.format("%s\n<color=#ffaaaaff>There is a %s in the way, providing the target Full Cover.", coverTooltip, coverInfo.description)
				end
			else
					coverTooltip = string.format("%s\n<color=#aaffaaff>You have a clear shot at the target.", coverTooltip)
			end
		end

		--ranged attacks have to account for cover.
		result[#result+1] = {
			text = "Cover",
			tooltip = coverTooltip,
			modifierOptions = {
				{
					id = "none",
					text = "No Cover",
					mod = CharacterModifier.StandardModifiers.RangedAttackNoCover,
				},
				{
					id = "half",
					text = "Half Cover",
					mod = CharacterModifier.StandardModifiers.RangedAttackHalfCover,
				},
				{
					id = "threequarters",
					text = "Three Quarters Cover",
					mod = CharacterModifier.StandardModifiers.RangedAttackThreeQuartersCover,
				},
				{
					id = "fullcover",
					text = "Full Cover",
					mod = CharacterModifier.StandardModifiers.RangedAttackThreeQuartersCover,
					disableRoll = "Attacks cannot be made against targets with Full Cover.",
				},
			},
			hint = {
				result = coverAmount,
				justification = {"Choose the amount of cover you have."},
			},
		}
	end


	local modifiers = self:GetActiveModifiers()
	for i,mod in ipairs(modifiers) do
		local m = mod.mod:DescribeModifyAttackAgainstUs(mod, self, attacker, attack)
		if m ~= nil then
			m.hint = { result = true, justification = {} }
			result[#result+1] = m
		end
	end
	
	return result
end

--returns a list of { modifier = (CharacterModifier), context = (ModContext), hint = { result = true/false, justification = {string} }
function creature:GetModifiersForD20Roll(rollType, options)
	options = options or {}
	if options.proficient == nil then
		options.proficient = false
	end
	local result = {}
	local modifiers = self:GetActiveModifiers()

	--Adds in any modifiers targeting this specific roll
	if options.forcedmodifiers ~= nil then
		for i,mod in ipairs(options.forcedmodifiers) do
			modifiers[#modifiers+1] = {mod = mod}
		end		
	end

	for i,mod in ipairs(modifiers) do
		local m = mod.mod:DescribeModifyD20Roll(mod, self, rollType, options) 
		if m ~= nil then
			m.hint = m.modifier:ShouldApplyD20Modifier(mod, self, rollType, options)
			result[#result+1] = m
		end
	end

	return result
end

function creature:ApplyModifiersToD20Roll(rollType, rollStr, options)
	local modifiers = self:GetActiveModifiers()
	for i,mod in ipairs(modifiers) do
		rollStr = mod.mod:ModifyD20RollDefaultBehavior(mod, self, rollType, rollStr, options)
	end
	return rollStr
end

function creature:IsDeadOrDying()
	return self:IsDown()
end

function creature:IsDying()
	return false
end

function creature:IsDead()
	return false
end

function monster:IsDead()
    return self:CurrentHitpoints() <= 0
end

function character:IsDead()
    return self:CurrentHitpoints() <= self:MaxHitpoints()/2
end

function creature:IsUnconsciousButStable()
	return self:CurrentHitpoints() <= 0 and self:GetNumDeathSavingThrowSuccesses() >= 3
end

function creature:IsDown()
	return self:IsDead()
end

function creature:IsDownCached()
    return self:try_get("_tmp_down", false)
end

function creature:Destroy(note)
    if self.minion then
	    self:TakeDamage(self:SingleMinionMaxStamina(), note, {doesNotTrigger = true})
    else
	    self:TakeDamage(self:MaxHitpoints(), note, {doesNotTrigger = true})
    end
end

function creature:ProficiencyBonus()
	return GameSystem.CalculateProficiencyBonus(self, GameSystem.Proficient())
end

local g_resourcesRecursion = false

function creature:InvalidateResources()
    self._tmp_resources = nil
    self._tmp_resourcesUpdate = nil
end

--gets a table with {resource_id -> quantity} mapping of maximum resources the creature has.
--- @return table<string, number>
function creature:GetResources()


    local cached = self:try_get("_tmp_resources")
    if cached ~= nil and self:try_get("_tmp_resourcesUpdate") == dmhub.ngameupdate then
        return cached
    end

	local result = GameSystem.BaseCreatureResources(self)

	if g_resourcesRecursion then
		return result
	end

	local spellLevel = self:SpellLevel()
	if spellLevel > 0 then
		local slots = GameSystem.spellSlotsTable[spellLevel] or GameSystem.spellSlotsTable[#GameSystem.spellSlotsTable]
		for i,quantity in ipairs(slots) do
			local resourceid = CharacterResource.spellSlotIds[i]
			if resourceid ~= nil then
				result[resourceid] = quantity
			end
		end
	end

	self:FillHitDice(result)

	g_resourcesRecursion = true
	local modifiers = self:GetActiveModifiers()
	g_resourcesRecursion = false
	for i,mod in ipairs(modifiers) do
		mod.mod:GetNamedResources(mod, self, result)
	end

    local resourcesTable = dmhub.GetTable(CharacterResource.tableName)

	for key,resource in pairs(self:try_get("resources", {})) do
		if resource.unbounded ~= 0 then
            local resourceEntry = resourcesTable[key]
            local ignore = false
            if resourceEntry ~= nil and resourceEntry.clearOutsideOfCombat then
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden or q.guid ~= resource.combatid then
                    ignore = true
                end
            end

            if not ignore then
			    result[key] = (result[key] or 0) + resource.unbounded
            end
		end
	end

	for key,resource in pairs(result) do
		if CharacterResource.resourceToRefreshType[key] == "global" then
			local t = self:GetResourceTable("global")
			local entry = t[key]
			if entry ~= nil then
				result[key] = result[key] + entry.unbounded
			end
		end
	end

    self._tmp_resources = result
    self._tmp_resourcesUpdate = dmhub.ngameupdate
	return result
end

function creature:GetUnboundedResourceQuantity(resourceid)
	local resources = self:try_get("resources", {})
	local entry = resources[resourceid]
	if entry ~= nil and entry.unbounded > 0 then
        local resourcesTable = dmhub.GetTable(CharacterResource.tableName) or {}
        local resourceEntry = resourcesTable[resourceid]
        if resourceEntry == nil then
            return 0
        end

        if resourceEntry.clearOutsideOfCombat then
            local q = dmhub.initiativeQueue
            if q == nil or q.hidden or q.guid ~= entry.combatid then
                return 0
            end
        end

		return entry.unbounded
	end
	
	return 0
end

--called by dmhub when a creature teleports.
function creature:OnTeleport()
	self:DispatchEvent("teleport")
end

function creature:CanUseTriggeredAbilities()
    return (not self:IsDead()) and self:CalculateNamedCustomAttribute("Cannot Use Triggered Abilities") == 0
end

CreatureFilter.Register{
    id = "opportunityattack",
    text = "Can Opportunity Attack",
    description = "This filter controls whether a creature can make an opportunity attack against a target. If any of the filters are false, opportunity attacks cannot be made.",
}

creature._tmp_triggeredOpportunityAttacks = 0

--called by dmhub when the creature moves.
function creature:OnMove(path)

    local ourToken = dmhub.LookupToken(self)
    if ourToken == nil then
        return
    end
	self:DispatchEvent("move", {
        path = PathMoved.new{
            path = path,
            size = ourToken.tileSize,
        }
    })

    if path.shifting or path.forced then
        return
    end

    local immuneFromOpportunityAttacks = self:CalculateNamedCustomAttribute("Immunity from Opportunity Attack") > 0


    local allTokens = dmhub.allTokens
    local steps = path.steps

    --first we find the bounds of the move. This way we can easily filter tokens that
    --are nowhere near adjacent to it.
    local minx, miny, maxx, maxy
    for _,step in ipairs(steps) do
        local x = step.x
        local y = step.y
        minx = (minx == nil) and x or math.min(minx, x)
        miny = (miny == nil) and y or math.min(miny, y)
        maxx = (maxx == nil) and x or math.max(maxx, x)
        maxy = (maxy == nil) and y or math.max(maxy, y)
    end

    --filter down allTokens to a list of tokens that we move through the adjacent squares of.
    local allTokensFiltered = {}

    local occupyingLocationMap = {}
    local adjacentLocationMap = {}
    for i,otherToken in ipairs(allTokens) do
        local adj = otherToken.properties:AdjacentLocations()

        local moveNextTo = false

        for _,a in ipairs(adj) do
            if a.x >= minx and a.x <= maxx and a.y >= miny and a.y <= maxy then
                for _,step in ipairs(steps) do
                    if a.x == step.x and a.y == step.y and a.floor == step.floor then
                        moveNextTo = true
                        break
                    end
                end
                if moveNextTo then
                    break
                end
            end
        end


        if moveNextTo then
            allTokensFiltered[#allTokensFiltered+1] = otherToken
            local occupying = otherToken.locsOccupying
            occupyingLocationMap[#allTokensFiltered] = occupying
            for _,loc in ipairs(occupying) do
                adj[#adj+1] = loc
            end

            adjacentLocationMap[#allTokensFiltered] = adj
        end
    end

    allTokens = allTokensFiltered

    local ourCharid = dmhub.LookupTokenId(self)

    local previousAdjacent = {}

    for i,step in ipairs(steps) do
        local adjacentTokens = {}
        local locs = ourToken:LocsOccupyingWhenAt(step)

        for j,otherToken in ipairs(allTokens) do
            local grabbedBy = otherToken.properties._tmp_grabbedby == ourCharid

            if not grabbedBy then

                --see if we move through a token.
                if otherToken.charid ~= ourToken.charid then
                    local occupying = occupyingLocationMap[j]
                    for _,adjLoc in ipairs(occupying) do
                        for _,loc in ipairs(locs) do
                            if adjLoc.x == loc.x and adjLoc.y == loc.y and adjLoc.floor == loc.floor then
                                --we moved through this token.
                                ourToken.properties:DispatchEvent("movethrough", { target = otherToken.properties })
                            end
                        end
                    end
                end

                if otherToken.charid ~= ourToken.charid and otherToken.properties:CanUseTriggeredAbilities() then
                    local adjacent = false
                    local adj = adjacentLocationMap[j]
                    for _,adjLoc in ipairs(adj) do
                        for _,loc in ipairs(locs) do
                            if adjLoc.x == loc.x and adjLoc.y == loc.y and adjLoc.floor == loc.floor then
                                adjacent = true
                                break
                            end
                        end
                    end

                    if adjacent then
                        adjacentTokens[otherToken.charid] = otherToken
                    end
                end
            end
        end

        if not immuneFromOpportunityAttacks then
            for k,tok in pairs(previousAdjacent) do
                if not adjacentTokens[k] then
                    if (not tok:IsFriend(self)) and tok.properties._tmp_grabbedby ~= ourCharid and not tok.properties:HasBanesOnGenericFreeStrike(ourToken) and tok.properties:TargetPassesFilter("opportunityattack", self) then
                        tok.properties:DispatchEvent("leaveadjacent", { movingcreature = self })
                        self._tmp_triggeredOpportunityAttacks = self._tmp_triggeredOpportunityAttacks + 1
                    end
                end
            end
        end

        previousAdjacent = adjacentTokens
    end
end

--- @class PathMoved
PathMoved = RegisterGameType("PathMoved")
PathMoved.size = 1

PathMoved.helpSymbols = {
	__name = "path",
	__sampleFields = {"squares"},
    squares = {
        name = "Squares",
        type = "number",
        desc = "The number of squares this path has moved.",
    },
    shift = {
        name = "Shift",
        type = "boolean",
        desc = "Whether this path was a shift.",
    },
    forced = {
        name = "Forced",
        type = "boolean",
        desc = "Whether this path was a forced move.",
    },
    distancetocreature = {
        name = "Distance to Creature",
        type = "function",
        desc = "A function which given a creature, returns the distance in tiles the closest point on the path came to that creature.",
    }
}

PathMoved.lookupSymbols = {
	self = function(c)
		return c
	end,

	debuginfo = function(c)
		return string.format("{path: %d}", c.path.numSteps)
	end,

	datatype = function(c)
		return "path"
	end,

    squares = function(c)
        return c.path.numSteps
    end,

    shift = function(c)
        return c.path.shifting
    end,

    forced = function(c)
        return c.path.forced
    end,

    distancetocreature = function(c)
        return function(creature)
            if c.path == nil or c.path.steps == nil then
                return 0
            end

            local other = dmhub.LookupToken(creature)
            if other == nil then
                return 0
            end

            local size = c.size

            local minDistance = math.huge
            for _,step in ipairs(c.path.steps) do
                local distance
                if size == 1 then
                    distance = other:Distance(step)
                    if distance < minDistance then
                        minDistance = distance
                    end
                else
                    for i=1,size do
                        for j=1,size do
                            local loc = step:dir(i-1, j-1)
                            distance = other:Distance(loc)
                            if distance < minDistance then
                                minDistance = distance
                            end
                        end
                    end
                end
            end

            return minDistance
        end
    end,
}

--called by DMHub whenever this creature moves.
function creature:Moved(path)

	local token = dmhub.LookupToken(self)
	if token == nil then
		return
	end

    local p = PathMoved.new{
        path = path,
        size = token.tileSize,
    }

	self:DispatchEvent("finishmove", {
        path = PathMoved.new{
            path = path,
            size = token.tileSize,
        }
    })

	if not self:IsOurTurn() then
		return
	end

	printf("CreatureMove:: numSteps = %s; difficult = %s; water = %s; cost = %s", json(path.numSteps), json(path.difficultSteps), json(path.waterSteps), json(path.cost))



	local cost = path.cost/10

	local newDiagonals = cond(cost > math.floor(cost), 1, 0)

	local diagonals = self:DiagonalsMovedThisTurn()

	cost = math.floor(cost)

	if dmhub.GetSettingValue("truediagonals") then
		if newDiagonals > 0 and (diagonals%2) == 1 then
			--pay for a diagonal cost now.
			cost = cost+1
		end
	end

    if not self:try_get("_tmp_freeMovement") then
        token:ModifyProperties{
            description = "Move Cost",
            execute = function()
                if dmhub.GetSettingValue("truediagonals") then self.moveDiag = diagonals + newDiagonals end
                self.moveDistance = self:DistanceMovedThisTurn() + cost
                self.moveDistanceRoundId = dmhub.initiativeQueue:GetRoundId()
            end,
        }
    end
end

function creature:SpendMovementInFeet(moveCost)
	if not self:IsOurTurn() then
		return 0
	end

    local cost = moveCost/dmhub.FeetPerTile
	self.moveDistance = self:DistanceMovedThisTurn() + cost
	self.moveDistanceRoundId = dmhub.initiativeQueue:GetRoundId()
    return cost
end

function creature:NumberOfMovementActions()
    return self:CalculateNamedCustomAttribute("Number of Movement Actions")
end

function creature:DistanceMovedThisTurnInFeet()
	return self:DistanceMovedThisTurn()*dmhub.FeetPerTile
end

--tells us how far the creature has moved this turn in tiles. Will return 0 if it's not this creature's turn or not in combat.
function creature:DistanceMovedThisTurn()
    if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
        return 0
    end

	if dmhub.initiativeQueue:GetRoundId() ~= self:try_get("moveDistanceRoundId", "") then
		return 0
	end

	return self:try_get("moveDistance", 0)
end

function creature:DiagonalsMovedThisTurn()
	if not self:IsOurTurn() then
		return 0
	end

	if dmhub.initiativeQueue:GetRoundId() ~= self:try_get("moveDistanceRoundId", "") then
		return 0
	end

	return self:try_get("moveDiag", 0)
end

function creature:IsOurTurn()
	if dmhub.initiativeQueue ~= nil and not dmhub.initiativeQueue.hidden then
		local currentInitiative = dmhub.initiativeQueue:GetFirstInitiativeEntry()
		if currentInitiative ~= nil then
			local token = dmhub.LookupToken(self)
			if token ~= nil then
				return InitiativeQueue.GetInitiativeId(token) == currentInitiative.initiativeid
			end
		end
	end

	return false
end

function creature:ApplyOngoingEffect(ongoingEffectid, duration, casterInfo, options)

	--use this as an opportunity to clean up any ongoingEffects that are no longer active.
	self.ongoingEffects = self:ActiveOngoingEffects(true)

	options = options or {}

	if options.transformid ~= nil then
		if self:has_key("transformInfo") then
			self:RemoveOngoingEffect(self.transformInfo.ongoingEffect)
			self:Invalidate()
		end

		self.transformInfo = {
			ongoingEffect = ongoingEffectid,
			transformid = options.transformid,
			hitpoints = self:CurrentHitpoints(),
		}
	end

	local ongoingEffects = self:get_or_add('ongoingEffects', {})

	if duration and type(duration) == "number" and duration >= 1 and (not options.untilEndOfTurn) then
		--the way that ongoingEffect accepts duration is that 0 = this turn,
		--while 0.5 is 'until the start of your next turn', 1 would be 'until the end of your next turn'.
		--so if we have 1 or more rounds subtract 0.5. We don't want to do this if we ever have
		--'end of your next turn' behavior.
		duration = duration - 0.5
	end

	local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
	local ongoingEffect = characterOngoingEffects[ongoingEffectid]
	if ongoingEffect == nil then
		return nil
	end

	if ongoingEffect.condition ~= "none" then
		local immunities = self:GetConditionImmunities()
		if immunities[ongoingEffect.condition] then
			--immune to this effect. Do we trigger some effect as a result?
			return nil
		end
	end

	local result = nil

	local highestSeq = 0
	for i,cond in ipairs(ongoingEffects) do
		highestSeq = math.max(highestSeq, cond.seq)
	end

    --- type nil|{string: boolean} a set of caster tokens.
    local casterSet = nil
    if ongoingEffect.casterTracking == "set" then
        casterSet = {}
        if casterInfo ~= nil and type(casterInfo.tokenid) == "string" then
            casterSet[casterInfo.tokenid] = true
        end
    end

    --- type nil|string the guid of the 'bond' this makes with all other creatures with the same bondid.
    local bondid = nil
    if ongoingEffect.casterTracking == "bond" then
        bondid = options.guid
    end

	local stolenAbility = nil
	if options.stolenAbility ~= nil then
		stolenAbility = options.stolenAbility
	end

	local found = false
	if not ongoingEffect.stackable then
		for i,cond in ipairs(ongoingEffects) do
			if found == false and cond.ongoingEffectid == ongoingEffectid then

                if casterSet ~= nil and cond:has_key("casterInfo") and type(cond.casterInfo.tokenid) == "string" then
                    casterSet[cond.casterInfo.tokenid] = true
                end

				cond.stolenAbility = stolenAbility
				cond.endAbility = ongoingEffect:GetEndAbility()
				cond.casterInfo = casterInfo
				cond.seq = highestSeq + 1
				if options.stacks == nil then
					cond.stacks = 1
				else
					cond.stacks = options.stacks
				end
				cond:Refresh(duration)
				result = cond
				found = true
			end
		end
	else
		for i,cond in ipairs(ongoingEffects) do
			if found == false and cond.ongoingEffectid == ongoingEffectid then
                if casterSet ~= nil and cond:has_key("casterInfo") and type(cond.casterInfo.tokenid) == "string" then
                    casterSet[cond.casterInfo.tokenid] = true
                end

                if ongoingEffect.clearStacksWhenApplying then
    				cond.stacks = math.max((cond.stacks or 1), (options.stacks or 1))
                else
    				cond.stacks = (cond.stacks or 1) + (options.stacks or 1)
                end

				cond.stolenAbility = stolenAbility
				cond.endAbility = ongoingEffect:GetEndAbility()
				cond.casterInfo = casterInfo
                cond.bondid = bondid
				cond.seq = highestSeq + 1
				cond:Refresh(duration)
				result = cond
				found = true
			end
		end
	end

	if found == false then
		ongoingEffects[#ongoingEffects+1] = CharacterOngoingEffectInstance.Create{
			ongoingEffectid = ongoingEffectid,
			duration = duration,
			stolenAbility = stolenAbility,
			endAbility = ongoingEffect:GetEndAbility(),
			casterInfo = casterInfo,
			stacks = cond(options.stacks == nil, 1, options.stacks),
			seq = highestSeq + 1,
            bondid = bondid,
            sourceDescription = options.sourceDescription,
            timestamp = ServerTimestamp(),
		}

		result = ongoingEffects[#ongoingEffects]
	end

    result.casterSet = casterSet

	if options.temporary_hitpoints ~= nil and options.temporary_hitpoints > 0 then
		--TODO: Work out what happens if they already have temporary stamina
		--and it's more than the new offer. For now we just override
		--any previous temporary stamina grant.
		self:SetTemporaryHitpoints(options.temporary_hitpoints, string.format("Applied %s", ongoingEffect.name), {
			ongoingeffectid = ongoingEffectid,
			tempHitpointsEndEffect = options.tempHitpointsEndEffect,
		})

		self:DispatchEvent("gaintempstamina", {})
	end


	if ongoingEffect.condition ~= "none" and casterInfo ~= nil then
        local conditionInfo = dmhub.GetTable(CharacterCondition.tableName)[ongoingEffect.condition]
        if conditionInfo ~= nil then
            audio.DispatchSoundEvent(conditionInfo:SoundEvent())
        end
        if conditionInfo ~= nil and conditionInfo.trackCaster and ongoingEffect.countsTowardInstanceLimit then
            local limitFormula = conditionInfo:try_get("maxInstancesFormula", "")
            if limitFormula ~= "" then
                local casterToken = dmhub.GetTokenById(casterInfo.tokenid)
                if casterToken ~= nil then
                    local maxInstances = dmhub.EvalGoblinScriptDeterministic(conditionInfo.maxInstancesFormula, casterToken.properties:LookupSymbol{}, 1, "Max instances of condition")

                    casterToken.properties:CheckConditionInstances(ongoingEffect.condition, maxInstances, dmhub.LookupTokenId(self))
                end
            end
        end

        if conditionInfo ~= nil then
            local casterToken = nil
            local caster = nil
            if casterInfo ~= nil and type(casterInfo.tokenid) == "string" then
                casterToken = dmhub.GetTokenById(casterInfo.tokenid)
                if casterToken ~= nil then
                    caster = casterToken.properties
                end
            end
            self:DispatchEvent("inflictcondition", {
                condition = conditionInfo.name,
                hasattacker = caster ~= nil,
                attacker = caster,
            })
        end
    end

	return result
end


--Removes the ongoing effect with the given ID. If numStacks is non-nil, it is a number with
--the number of stacks to remove. Otherwise, all stacks are removed.
--If numStacks is given, then it returns the number of stacks remaining to remove.
function creature:RemoveOngoingEffect(ongoingEffectid, numStacks)
	if type(numStacks) == "number" and numStacks <= 0 then
		return 0
	end

	if self:has_key("transformInfo") and self.transformInfo.ongoingEffect == ongoingEffectid then
		self.transformInfo = nil
	end

	local ongoingEffects = self:get_or_add('ongoingEffects', {})
	local newOngoingEffects = {}
	for i,cond in ipairs(ongoingEffects) do
		if cond.ongoingEffectid ~= ongoingEffectid or (type(numStacks) == "number" and numStacks <= 0) then
			newOngoingEffects[#newOngoingEffects+1] = cond
		elseif numStacks ~= nil then
			if numStacks < cond.stacks then
				cond.stacks = cond.stacks - numStacks
				numStacks = 0
				newOngoingEffects[#newOngoingEffects+1] = cond
			else
				numStacks = numStacks - cond.stacks
			end
		end
	end
	
	self.ongoingEffects = newOngoingEffects

	return numStacks
end

--- @param excluteTemporary nil|boolean
--- @return CharacterOngoingEffectInstance[]
function creature:ActiveOngoingEffects(excludeTemporary)
	local result = {}

	if not excludeTemporary then
		local builtinEffects = rawget(self, "_tmp_builtinOngoingEffects")
		if builtinEffects ~= nil then
			for _,v in ipairs(builtinEffects) do
				result[#result+1] = v
			end
		end
	end
	local items = self:try_get('ongoingEffects', {})
	for i,cond in ipairs(items) do
		if cond.typeName ~= "CharacterOngoingEffectInstance" then
			local tok = dmhub.LookupToken(self)
			dmhub.CloudError(string.format("Invalid ongoing effect: %s -> %s", tok.charid, json(cond)))
		else
			if not cond:Expired() then
				result[#result+1] = cond
			end
		end

	end

	return result
end

function creature:ApplyTemporaryEffect(effect)
    local temporaryEffects = self:get_or_add("_tmp_temporaryEffects", {})
    temporaryEffects[#temporaryEffects+1] = effect
    
    local result = {
        cancel = function()
            table.remove_value(self:try_get("_tmp_temporaryEffects", {}), effect)
        end
    }

	self:Invalidate()

    return result
end

function creature:ApplyMomentaryEffect(effect)
	local momentaryEffects = self:get_or_add("_tmp_momentaryEffects", {})
	momentaryEffects[#momentaryEffects+1] = effect

	--force recalculation of modifiers.
	self:Invalidate()

	--float an effect above this token.
	local floatEffects = self:get_or_add("floatEffects", {})

	local deletes = {}
	for k,v in pairs(floatEffects) do
		if TimestampAgeInSeconds(v.timestamp) > 20 then
			deletes[#deletes+1] = k
		end
	end

	for i,d in ipairs(deletes) do
		floatEffects[d] = nil
	end

	floatEffects[dmhub.GenerateGuid()] = {
		iconid = effect.iconid,
		display = effect.display,
		timestamp = ServerTimestamp(),
	}
end

function creature:ClearMomentaryOngoingEffects()
	if self:try_get("_tmp_momentaryEffects") ~= nil then
		self._tmp_momentaryEffects = nil
		self:Invalidate()
	end
end

function creature:SpellSaveDC(spell)
	return GameSystem.CalculateSpellSaveDC(self, spell)
end

function creature:SpellAttackModifier(spell)
	return GameSystem.CalculateSpellAttackModifier(self, spell)
end

function creature:GetAttributeUsedForAbility(ability)
	if ability ~= nil and ability:has_key("attributeOverride") then
		if ability.attributeOverride == "no_attribute" then
			return "none"
		end

		if ability.attributeOverride == "multiple" then
			local best = nil
			local multi = ability:try_get("attributeOverrideMulti", {})
			local result = nil
			for _,item in ipairs(multi) do
				local val = self:GetAttribute(item):Modifier()
				if result == nil or val > best then
					best = val
					result = item
				end
			end

			return result
		end

		return ability.attributeOverride
		
	end

	return nil
end

function creature:GetSpellcastingAbilityModifierOverride(spell)
	local attrid = self:GetAttributeUsedForAbility(spell)
	if attrid == nil then
		return nil
	end

	if attrid == "none" then
		return 0
	end

	return self:GetAttribute(attrid):Modifier()
end

function creature:SpellcastingAbilityModifier(spell)
	local override = self:GetSpellcastingAbilityModifierOverride(spell)
	if override ~= nil then
		return override
	end

	if spell == nil then
		local features = self:CalculateSpellcastingFeatures()
		if #features == 0 then
			return 0
		end

		return self:GetAttribute(features[1].attr):Modifier()
	end

	local feature = spell:try_get("spellcastingFeature")
	if feature ~= nil then
		return self:GetAttribute(feature.attr):Modifier()
	end

	return 0
end

--called by dmhub to get a descriptive summary of the character.
function creature:GetCharacterSummaryText()
	return "creature"
end

--called by dmhub to summarize a creature's info in the lobby.
function creature:GetLobbySummaryText()
	return {}
end

function creature:RaceOrMonsterType()
	return ""
end

function creature:GetCustomAttribute(attrInfo)
	local result = attrInfo:CalculateBaseValue(self)

	--note that attrInfo.id will be a guid.
	result = self:CalculateAttribute(attrInfo.id, result)
	return result
end

--- @param viewingToken nil|CharacterToken
--- @param token nil|CharacterToken
--- @param str string
--- @return boolean
function creature:MatchesString(viewingToken, token, str)

    if string.starts_with(str, "~") then
        str = string.sub(str, 2)
        return not self:MatchesString(viewingToken, token, str)
    end

    str = string.lower(tostring(str))

    if viewingToken ~= nil then
        if str == "enemy" then
            return not viewingToken:IsFriend(token)
        end

        if str == "ally" or str == "friend" then
            return viewingToken:IsFriend(token)
        end
    end

    if self:has_key("monster_type") and string.lower(self.monster_type) == str then
        return true
    end

    if self:has_key("keywords") and self.keywords[str] then
        return true
    end

    if str == string.lower(self:RaceOrMonsterType()) then
        return true
    end

    local monsterGroup = self:MonsterGroup()
    if monsterGroup ~= nil and string.find(string.lower(monsterGroup.name), str) then
        return true
    end

    local features = self:GetFeatures()
    local modifiers = self:GetActiveModifiers()
    if string.find(str, "*") then
        local pattern = string.gsub(str, "%*", ".*")
        for _,feature in ipairs(features) do
            if regex.Match(string.lower(feature.name), pattern) then
                return true
            end
        end
        for _,mod in ipairs(modifiers) do
            if regex.Match(string.lower(mod.mod.name), pattern) then
                return true
            end
        end
    end

    for _,feature in ipairs(features) do
        if string.lower(feature.name) == str then
            print("MATCH:: FEATURE", feature.name, str)
            return true
        end
    end

    if str ~= "hidden" then --hack?
        for _,mod in ipairs(modifiers) do
            if string.lower(mod.mod.name) == str then
                print("MATCH:: MODIFIER", mod.mod.name, str)
                return true
            end
        end
    end


    local condition = CharacterCondition.conditionsByName[string.lower(str)]
    if condition ~= nil then
        if self:HasCondition(condition.id) then
            return true
        end
    end


    return false
end

function creature:GetFeatures()
    local features = self:try_get("characterFeatures", {})
    return features
end

creature.helpSymbols = {
	__name = "creature",
	__sampleFields = {"hitpoints", "level"},

	self = {
		name = "Self",
		type = "creature",
		desc = "The creature this GoblinScript is running on.",
	},

	name = {
		name = "Name",
		type = "text",
		desc = "The monster type of the creature. For instance, Bandit, Goblin, Adult Red Dragon. Only valid for monsters, not characters.",
		seealso = {"Type","Subtype"},
		examples = {"OBJ.Type is Bandit" },
	},

	id = {
		name = "ID",
		type = "text",
		desc = "A unique identifier for the creature. Not intended to be human readable.",
	},

	type = {
		name = "Type",
		type = "text",
		desc = "The type of the creature. For instance, goblin or demon for monsters, or Elf or Human for characters.",
		seealso = {"Subtype"},
		examples = {"OBJ.Type is not undead", "OBJ.Type is Elf or OBJ.Type is Human" },
	},

	subtype = {
		name = "Subtype",
		type = "text",
		desc = "The subtype of the creature. For instance, Goblinoid or High Elf. Will be empty for creatures with no subtype.",
		seealso = {"Type"},
		examples = {"OBJ.Subtype is Goblinoid"},
	},

    altitudeindecitiles = {
        name = "AltitudeInDeciTiles",
        type = "number",
        desc = "The altitude of the creature measured in tenths of a tile high. This is the distance above ground zero of the bottom floor of the map the creature is on. This means that creatures on different floors can have their altitudes compared.",
        seealso = {"Altitude"},
    },

    altitude = {
        name = "Altitude",
        type = "number",
        desc = "The altitude of the creature measured in tiles high. This is the distance above ground zero of the bottom floor of the map the creature is on. This means that creatures on different floors can have their altitudes compared.",
        seealso = {"AltitudeInDeciTiles"},
    },

    height = {
        name = "Height",
        type = "number",
        desc = "The height (stature) of the creature measured in tiles tall.",
    },

	hitpoints = {
		name = "Hitpoints",
		type = "number",
		desc = "The current hitpoints of the creature.",
		seealso = {"Maximum Hitpoints", "Temporary Hitpoints"},
		examples = {"OBJ.Hitpoints > 10", "OBJ.Hitpoints < OBJ.Maximum Hitpoints"},
	},

	maximumhitpoints = {
		name = "Maximum Hitpoints",
		type = "number",
		desc = "The maximum hitpoints of the creature.",
		seealso = {"Hitpoints", "Temporary Hitpoints"},
		examples = {"OBJ.Maximum Hitpoints > 10", "OBJ.Hitpoints < OBJ.Maximum Hitpoints"},
	},

	weaponswielded = {
		name = "Weapons Wielded",
		type = "number",
		desc = "The number of weapons the creature is currently wielding in its hands.",
		examples = {"Weapons Wielded = 1"},
	},

	twohanded = {
		name = "Two Handed",
		type = "boolean",
		desc = "True if the creature is currently wielding a two-handed weapon.",
	},

	hasmainhanditem = {
		name = "Has Main Hand Item",
		type = "boolean",
		desc = "True if the creature is wielding an item in its primary hand.",
	},

	hasoffhanditem = {
		name = "Has Off Hand Item",
		type = "boolean",
		desc = "True if the creature is wielding an item in its off hand.",
	},

	mainhanditem = {
		name = "Main Hand Item",
		type = "equipment",
		desc = "The item the creature is wielding in its main hand, if any. Only valid if Has Main Hand Item is true.",
		seealso = {"Has Main Hand Item", "Off Hand Item"},
	},

	offhanditem = {
		name = "Off Hand Item",
		type = "equipment",
		desc = "The item the creature is wielding in its off hand, if any. Only valid if Has Off Hand Item is true.",
		seealso = {"Has Off Hand Item", "Main Hand Item"},
	},

	hasshield = {
		name = "Has Shield",
		type = "boolean",
		desc = "True if the creature has a shield, false otherwise.",
		seealso = {"Light Armor", "Medium Armor", "Heavy Armor", "Unarmored"},
	},

	shield = {
		name = "Shield",
		type = "equipment",
		desc = "The shield the creature is wielding, if any. Only valid if Has Shield is true.",
		seealso = {"Has Shield"},
	},


	shieldbonus = {
		name = "Shield Bonus",
		type = "number",
		desc = "The armor class increase afforded by the shield the creature is currently wielding. Zero if the creature is not using a shield.",
		seealso = {"Shield", "Has Shield"},
	},

	hasarmor = {
		name = "Has Armor",
		type = "boolean",
		desc = "True if the creature is wearing armor, false otherwise.",
		seealso = {"Has Shield", "Light Armor", "Medium Armor", "Heavy Armor", "Unarmored"},
	},

	armor = {
		name = "Armor",
		type = "equipment",
		desc = "The armor the creature is wearing, if any. Only valid if Has Armor is true.",
		seealso = {"Has Armor"},
	},


	lightarmor = {
		name = "Light Armor",
		type = "boolean",
		desc = "True if the creature is wearing Light Armor, false otherwise.",
		seealso = {"Has Shield", "Has Armor", "Medium Armor", "Heavy Armor", "Unarmored"},
	},

	mediumarmor = {
		name = "Medium Armor",
		type = "boolean",
		desc = "True if the creature is wearing Medium Armor, false otherwise.",
		seealso = {"Has Shield", "Has Armor", "Light Armor", "Heavy Armor", "Unarmored"},
	},

	heavyarmor = {
		name = "Heavy Armor",
		type = "boolean",
		desc = "True if the creature is wearing Heavy Armor, false otherwise.",
		seealso = {"Has Shield", "Has Armor", "Light Armor", "Heavy Armor", "Unarmored"},
	},

	unarmored = {
		name = "Unarmored",
		type = "boolean",
		desc = "True if the creature is not wearing armor, false otherwise. If the creature is using a shield but not wearing any armor, this is true.",
		seealso = {"Has Shield", "Has Armor", "Light Armor", "Medium Armor", "Heavy Armor"},
	},

	armorclass = {
		name = "Armor Class",
		type = "number",
		desc = "The Armor Class of the creature.",
		seealso = {},
		examples = {"OBJ.Armor Class > 10"},
	},

	proficiencybonus = {
		name = "Proficiency Bonus",
		type = "number",
		desc = "The Proficiency Bonus of the creature.",
		seealso = {},
		examples = {"OBJ.Strength Modifier + OBJ.Proficiency Bonus"},
	},

	proficiencymodifier = {
		name = "Proficiency Modifier",
		type = "number",
		desc = "Synonym of Proficiency Bonus",
		seealso = {},
		examples = {"OBJ.Strength Modifier + OBJ.Proficiency Modifier"},
	},

	chargedistance = {
		name = "Charge Distance",
		type = "number",
		desc = "The distance this creature has moved in a straight line to get to its current position, in squares. Only counts movement made on the current turn, and will always be 0 when not in combat. A mix of diagonal and straight-line movement will be counted as part of the charge as long as every step takes the creature closer to the target.",
		seealso = {},
		examples = {"Charge Distance >= 4"},
	},

	movementmultiplier = {
		name = "Movement Multiplier",
		type = "number",
		desc = "The creature's current movement multiplier. This multiplies how far they can move this round.",
		seealso = {},
	},

	movementtype = {
		name = "Movement Type",
		type = "text",
		desc = "The creature's current movement type. May be \"Walk\", \"Swim\", \"Fly\" etc",
		examples = {'Movement Type = "Fly"'},
	},

	inventoryweight = {
		name = "Inventory Weight",
		type = "number",
		desc = "The total weight of the creature's inventory items.",
		examples = {"Inventory Weight >= Carrying Capacity"},
	},

	size = {
		name = "Size",
		type = "number",
		desc = "The size of this creature. 1 = 1T, 2 = 1S, 3 = 1M, 4 = 1L, 5 = 2, 6 = 3, 7 = 4, 8 = 5.",
		seealso = {"tilesize"},
		examples = {"Size <= 4"},
	},

    tilesize = {
        name = "Tile Size",
        type = "number",
        desc = "The size of this creature in terms of tiles occupied",
        seealso = {"size"},
    },

	yourturn = {
		name = "Your Turn",
		type = "boolean",
		desc = "True if combat is active and it is this creature's turn.",
		seealso = {},
		examples = {"5 when OBJ.Your Turn else 0"},
	},

	distance = {
		name = "Distance",
		type = "function",
		desc = "A function which is shown another creature and tells us the distance between them in squares.",
		examples = {"OBJ.Distance(target)"},
	},

	countnearbyenemies = {
		name = "Count Nearby Enemies",
		type = "function",
		desc = "A function which is shown a distance in squares and tells us the number of live enemy creatures within that distance of this creature. This can be given additional parameters after the distance to filter the criteria. Criteria can incldue monster groups and the names of features. Creatures can also be provided as parameters and those specific creatures will be excluded from the match.",
		examples = {"OBJ.Count Nearby Enemies(1)", "OBJ.Count Nearby Enemies(5, \"Goblin\")", "OBJ.Count Nearby Enemies(10, \"ally\")", "OBJ.Count Nearby Enemies(5, \"enemy\", \"Goblin\")"},
	},

	countnearbyfriends = {
		name = "Count Nearby Friends",
		type = "function",
		desc = "A function which is shown a distance in squares and tells us the number of live allied creatures within that distance of this creature. This can be given additional parameters after the distance to filter the criteria. Criteria can incldue monster groups and the names of features. Creatures can also be provided as parameters and those specific creatures will be excluded from the match.",
		examples = {"OBJ.Count Nearby Friends(5)"},
	},

	countnearbycreatures = {
		name = "Count Nearby Creatures",
		type = "function",
		desc = "A function which is shown a distance in squares and tells us the number of live creatures within that distance of this creature. This can be given additional parameters after the distance to filter the criteria. 'ally' and 'enemy' work, as do monster groups and the names of features. Creatures can also be provided as parameters and those specific creatures will be excluded from the match.",
		examples = {"OBJ.Count Nearby Creatures(5)", "OBJ.Count Nearby Creatures(1, \"Enemy\", \"Goblin\") > 2"},
	},

	countriders = {
		name = "Count Riders",
		type = "function",
		desc = "A function which is given a set of string criteria such as 'goblins' or 'crafty' and tells us how many riders we have that match that filter.",
        seealso = "Count Nearby Creatures",
		examples = {"OBJ.Count Riders('goblin', 'crafty')"},
	},

	nexttoanotherenemy = {
		name = "Next to Another Enemy",
		type = "number",
		desc = "Counts the number of creatures next to this creature that are hostile to it. Does not count the currently active creature.",
		seealso = {},
		examples = {"1d6 when OBJ.Next To Another Enemy"}
	},

	level = {
		name = "Level",
		type = "number",
		desc = "The Level of the creature. For monsters this is their Spellcasting Level.",
		seealso = {"Challenge Rating"},
		examples = {"1 when OBJ.Level < 5 else 2 when OBJ.Level < 12 else 3"},
	},

	challengerating = {
		name = "Challenge Rating",
		type = "number",
		desc = "The Challenge Rating of the creature. For characters this is their Character Level.",
		seealso = {"Level"},
		examples = {"1 when OBJ.Challenge Rating < 5 else 2 when OBJ.Challenge Rating < 12 else 3"},
	},

	cr = {
		name = "CR",
		type = "number",
		desc = "Synonym of Challenge Rating.",
		seealso = {"Level"},
		examples = {"1 when OBJ.CR < 5 else 2 when OBJ.CR < 12 else 3"},
	},

	spellsavedc = {
		name = "Spell Save DC",
		type = "number",
		desc = "The creature's Spellcasting Save DC. For multi-class characters this is the highest spellcasting ability modifier of any class they can cast spells in.",
		seealso = {"Spellcasting Ability Modifier"},
	},

	spellcastingabilitymodifier = {
		name = "Spellcasting Ability Modifier",
		type = "number",
		desc = "The creature's Spellcasting Ability Modifier. For multi-class characters this is the highest spellcasting ability modifier of any class they can cast spells in.",
		seealso = {"Proficiency Bonus"},
		examples = {"8 + OBJ.Proficiency Bonus + OBJ.Spellcasting Ability Modifier"},
	},

	spellcastingclasses = {
		name = "Spellcasting Classes",
		type = "number",
		desc = "The number of classes from which the creature has spellcasting abilities from. For instance, a Paladin 4/Wizard 2 would have a value of 2. This is generally used to ensure rules regarding multiclass spellcasting work correctly.",
	},

	multiclass = {
		name = "Multiclass",
		type = "boolean",
		desc = "True for characters that have levels in multiple different classes.",
		seealso = {"Monoclass"},
	},

	subclasses = {
		name = "Subclasses",
		type = "set",
		desc = "The subclasses this character has taken. None for monsters.",
	},

	summoned = {
		name = "Summoned",
		type = "boolean",
		desc = "True if this creature was summoned by another creature.",
	},

	summoner = {
		name = "Summoner",
		type = "creature",
		desc = "The creature that summoned this creature.\n\n<color=#ffaaaa><i>This field is only available for creatures that were summoned by another creature using a spell or ability.</i></color>",
	},

	conditioncaster = {
		name = "ConditionCaster",
		type = "function",
		desc = "Given the name of a condition or ongoing effect, will return the creature that cast that condition or ongoing effect on this creature.",
	},

	conditions = {
		name = "Conditions",
		type = "set",
		desc = "The names of any conditions affecting the creature.",
		examples = {'Conditions has "Poisoned"'},
	},

	ongoingeffects = {
		name = "Ongoing Effects",
		type = "set",
		desc = "The names of any ongoing effects affecting the creature.",
		examples = {'Ongoing Effects has "Rage"'},
	},
	
	stacks = {
		name = "Stacks",
		type = "function",
		desc = "Given the name of an ongoing effect, provides the number of stacks of that effect.",
		examples = {},
	},

    casterset = {
        name = "CasterSet",
        type = "function",
        desc = "The set of creatures that cast this ongoing effect on the creature.",
        examples = {"Self.CasterSet('Pain for Pain') has target"},
    },

	proficient = {
		name = "Proficient",
		type = "function",
		desc = "Given the name of a skill, an item, or item category will be true if the creature has proficiency with it, and false otherwise.",
		examples = {'Proficient("Acrobatics")', 'Proficient("Heavy Armor")', 'Proficient("Longsword")', 'Proficient("Lyre")'},
	},

	skillmodifier = {
		name = "Skill Modifier",
		type = "function",
		desc = "Given the name of a skill, will return the creature's modifier for checks made using that skill.",
		examples = {'Skill Modifier("Acrobatics")'},
	},

	savemodifier = {
		name = "Save Modifier",
		type = "function",
		desc = "Given the name of an attribute, will return the creature's modifier for saving throws made using that attribute.",
		examples = {'Save Modifier("dex")'},
	},

	conditionimmunities = {
		name = "Condition Immunities",
		type = "set",
		desc = "The conditions that this creature is immune to.",
		examples = {'Creature.Condition Immunities has "Paralyzed"'},
	},

	combatround = {
		name = "Combat Round",
		type = "number",
		desc = "The number of the current combat round. 0 if not in combat.",
		examples = {'Combat Round = 1'},
	},

	languages = {
		name = "Languages",
		type = "set",
		desc = "The languages this creature knows.",
		examples = {'Languages has "Common"'},
	},

	mounted = {
		name = "Mounted",
		type = "boolean",
		desc = "True if this creature is mounted on another creature.",
	},

	mount = {
		name = "Mount",
		type = "creature",
		desc = "The mount this creature is riding.\n\n<color=#ffaaaa><i>This field is only available for creatures for which the <b>Mounted</b> field is true.</i></color>",
	},

    hiddenthisturn = {
        name = "Hidden This Turn",
        type = "boolean",
        desc = "True if the creature has been hidden this turn.",
    },

	ongoingdc = {
		name = "Ongoing DC",
		type = "text",
		desc = "The DC of the creatures current ongoing effect",
		examples = {"ongoingDC('Stealth') > target.passive(\"perception\")" },
	},

	passive = {
		name = "Passive",
		type = "text",
		desc = "Get a passive mod of a creature",
		examples = {"target.passive(\"perception\") > 25"},
	},

	lastcaster = {
		name = "Last Caster",
		type = "creature",
		desc = "The creature to last cast a spell causing a saving throw on current creature",
	},

	movementspeed = {
		name = "Movement Speed",
		type = "number",
		desc = "The distance this creature can move in a round, in squares.",
	},

	movedthisturn = {
		name = "Moved This Turn",
		type = "number",
		desc = "The distance this creature has moved this turn. This will be 0 when not in combat, and equal to how far you moved on your last turn otherwise.",
	},

	resources = {
		name = "Resources",
		type = "resources",
		desc = "The resources this creature has available.",
		examples = {"Resources.Standard Action > 0"},
	},

    numberofcreaturesgrabbed = {
        name = "Number of Creatures Grabbed",
        type = "number",
        desc = "The number of creatures currently grabbed by this creature.",
    }
}


--- @param token CharacterToken
--- @param nearby CharacterToken
--- @param criteria string[]
local function NearbyTokenMatchesCriteria(token, nearby, criteria)
    local matches = true
    for j = 1, #criteria do
        if criteria[j] == nil then
            break
        elseif type(criteria[j]) == "string" then
            matches = nearby.properties:MatchesString(token, nearby, criteria[j])
        elseif type(criteria[j]) == "table" then
            --finding a creature means we exclude it from possible targets.
            matches = (criteria[j] ~= nearby.properties)
        end

        if not matches then
            break
        end
    end

    if matches and nearby.properties:IsDead() then
        matches = false
    end

    return matches
end

local countriders = function(c, criteria)
    return function(distance, x, y, w, z, xx, yy, ww, zz)
        local token = dmhub.LookupToken(c)
        if token == nil then
            return 0
        end

        criteria = criteria or {}
        criteria[#criteria+1] = x
        criteria[#criteria+1] = y
        criteria[#criteria+1] = w
        criteria[#criteria+1] = z
        criteria[#criteria+1] = xx
        criteria[#criteria+1] = yy
        criteria[#criteria+1] = ww
        criteria[#criteria+1] = zz

        for i=1,#criteria do
            if type(criteria[i]) == "function" then
                criteria[i] = criteria[i]("self")
            end
        end

        local count = 0
        local nearbyTokens = dmhub.allTokens
        local charid = token.charid
        for i, nearby in ipairs(nearbyTokens) do
            if nearby.mountedOn == charid then
                local matches = NearbyTokenMatchesCriteria(token, nearby, criteria)
                if matches then
                    count = count + 1
                end
            end
        end

        return count
    end
end



local countnearbycreatures = function(c, criteria)
    return function(distance, x, y, w, z, xx, yy, ww, zz)
        local token = dmhub.LookupToken(c)
        if token == nil then
            return 0
        end

        criteria = criteria or {}
        criteria[#criteria+1] = x
        criteria[#criteria+1] = y
        criteria[#criteria+1] = w
        criteria[#criteria+1] = z
        criteria[#criteria+1] = xx
        criteria[#criteria+1] = yy
        criteria[#criteria+1] = ww
        criteria[#criteria+1] = zz

        for i=1,#criteria do
            if type(criteria[i]) == "function" then
                criteria[i] = criteria[i]("self")
            end
        end

        local count = 0
        local nearbyTokens = token:GetNearbyTokens(distance)

        for i, nearby in ipairs(nearbyTokens) do
            local matches = NearbyTokenMatchesCriteria(token, nearby, criteria)

            if matches then
                count = count + 1
            end
        end

        return count
    end
end


--The lookup symbols mapping a creature to goblinscript.
--also see CustomAttributes which modifies this table on table refresh.
creature.lookupSymbols = {
	self = function(c)
		return c
	end,

	debuginfo = function(c)
		return string.format("creature: %s", creature.GetTokenDescription(dmhub.LookupToken(c)))
	end,

	datatype = function(c)
		return "creature"
	end,

	id = function(c)
		local token = dmhub.LookupToken(c)
		if token ~= nil then
			return Utils.HashGuidToNumber(token.charid)
		end

		return nil
	end,

	always = function(c)
		return 1
	end,

	never = function(c)
		return 0
	end,

	name = function(c)
		return c:try_get("monster_type", "")
	end,

	type = function(c)
        return c:RaceOrMonsterType()
	end,

	subtype = function(c)
		return c:try_get("monster_subtype", "")
	end,

    altitudeindecitiles = function(c)
		local token = dmhub.LookupToken(c)
		if token ~= nil then
			return token.altitudeInDeciTiles
		end

        return 0
    end,

    altitude = function(c)
		local token = dmhub.LookupToken(c)
		if token ~= nil then
			return token.altitude
		end

        return 0
    end,

    height = function(c)
		local token = dmhub.LookupToken(c)
		if token ~= nil then
			return token.characterHeight
		end
        
        return 1
    end,

	resources = function(c)
		return CharacterResourceCollection.CreateFromCreature(c)
	end,

    numberofcreaturesgrabbed = function(c)
        return c:try_get("_tmp_numberOfCreaturesGrabbed", 0)
    end,

	hitpoints = function(c)
		return c:CurrentHitpoints()
	end,

	maximumhitpoints = function(c)
		return c:MaxHitpoints()
	end,

	temporaryhitpoints = function(c)
		return c:TemporaryHitpoints()
	end,

	weaponswielded = function(c)
		return c:NumberOfWeaponsWielded()
	end,

	twohanded = function(c)
		return c:WieldingTwoHanded()
	end,

	hasmainhanditem = function(c)
		return c:GetEquipmentItemInSlot(string.format("mainhand%d", c.selectedLoadout)) ~= nil
	end,

	hasoffhanditem = function(c)
		return c:GetEquipmentItemInSlot(string.format("offhand%d", c.selectedLoadout)) ~= nil
	end,

	mainhanditem = function(c)
		return c:GetEquipmentItemInSlot(string.format("mainhand%d", c.selectedLoadout))
	end,

	offhanditem = function(c)
		return c:GetEquipmentItemInSlot(string.format("offhand%d", c.selectedLoadout))
	end,

	hasshield = function(c)
		return c:GetShield() ~= nil
	end,

	shield = function(c)
		return c:GetShield()
	end,

	shieldbonus = function(c)
		local shield = c:GetShield()
		if shield == nil then
			return 0
		end

		return shield.armorClassModifier
	end,

	armor = function(c)
		return c:GetArmor()
	end,

	lightarmor = function(c)
		return c:GetArmorCategory() == "Light Armor"
	end,

	mediumarmor = function(c)
		return c:GetArmorCategory() == "Medium Armor"
	end,

	heavyarmor = function(c)
		return c:GetArmorCategory() == "Heavy Armor"
	end,

	unarmored = function(c)
		return c:GetArmorCategory() == nil
	end,

	hasarmor = function(c)
		return c:GetArmorCategory() ~= nil
	end,

	armorclass = function(c)
		return c:ArmorClass()
	end,

	spellsavedc = function(c)
		return GameSystem.CalculateSpellSaveDC(c)
	end,

	spellcastingabilitymodifier = function(c)
		return c:SpellcastingAbilityModifier()
	end,

	spellcastingclasses = function(c)
		local features = c:CalculateSpellcastingFeatures()
		local result = #features
		return c:CalculateAttribute('spellcastingClasses', result)
	end,
	
	proficiencybonus = function(c)
		return c:ProficiencyBonus()
	end,

	--alias of proficiency bonus.
	proficiencymodifier = function(c)
		return c:ProficiencyBonus()
	end,

	chargedistance = function(c)
		local token = dmhub.LookupToken(c)
		if token ~= nil then
			return token.chargeDistance
		end

		return 0
	end,

	movementspeed = function(c)
		return c:CurrentMovementSpeed()
	end,

	movedthisturn = function(c)
		local result = c:DistanceMovedThisTurnInFeet()
		return c:DistanceMovedThisTurnInFeet()
	end,

	movementmultiplier = function(c)
		return c:MovementMultiplier()
	end,

	movementtype = function(c)
		return c.currentMoveType
	end,

	inventoryweight = function(c)
		return c:GetInventoryWeight()
	end,

	size = function(c)
		local token = dmhub.LookupToken(c)
		if token ~= nil and token.valid then
            return token.creatureSizeNumber
		end

		local num = creature:GetBaseCreatureSizeNumber()

		return num or 1
	end,

	tilesize = function(c)
		local token = dmhub.LookupToken(c)
		if token ~= nil and token.valid then
            return token.tileSize
		end

		local num = creature:GetBaseCreatureSizeNumber()
		if num ~= nil then
			return math.max(1, num - 3)
		end

		return 3
	end,



	yourturn = function(c)
		return cond(c:IsOurTurn(), 1, 0)
	end,

	distance = function(c)
		return function(other)
			local a = dmhub.LookupToken(c)
			local b = dmhub.LookupToken(other)
			if a == nil or b == nil or (not a.valid) or (not b.valid) then
				return nil
			end

			local result = a:Distance(b)
            return result
		end
	end,

	countnearbyenemies = function(c)
        return countnearbycreatures(c, {"enemy"})
    end,

	countnearbyfriends = function(c)
        return countnearbycreatures(c, {"ally"})
    end,

	countnearbycreatures = countnearbycreatures,

    countriders = countriders,

	--if next to an enemy other than the active token.
	nexttoanotherenemy = function(c)
		local token = dmhub.LookupToken(c)
		local count = 0
		
		if token ~= nil then
			local nearbyTokens = token:GetNearbyTokens()
			for i,nearby in ipairs(nearbyTokens) do
				if (not nearby:IsFriend(token)) and (not GameRules.TokenIncapacitated(nearby)) then
					local isUs = false
					for j,obj in ipairs(CurrentGoblinScriptObject) do
						if obj == nearby.properties then
							isUs = true
						end
					end

					if isUs == false then
						count = count+1
					end
				end
			end
		end

		return count
	end,

	summoned = function(c)
		local token = dmhub.LookupToken(c)
		if token == nil then
			return false
		end

		local summonerid = token.summonerid
		return summonerid ~= nil		
	end,

	summoner = function(c)
		local token = dmhub.LookupToken(c)
		if token == nil then
			return nil
		end

		local summonerid = token.summonerid
		if summonerid == nil then
			return nil
		end

		local summoner = dmhub.GetCharacterById(summonerid)
		if summoner ~= nil then
			return summoner.properties
		end

		return nil
	end,

	conditioncaster = function(c)
		return function(condname)
			condname = string.lower(condname)

			local seqFound = -1
			local result = nil

			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
			local ongoingEffects = c:ActiveOngoingEffects()
			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
			for i,effectInfo in ipairs(ongoingEffects) do
				if effectInfo.seq > seqFound and effectInfo:try_get("casterInfo") ~= nil then
					local ongoingEffectInfo = ongoingEffectsTable[effectInfo.ongoingEffectid]
					local cond = conditionsTable[ongoingEffectInfo.condition]
					if (cond ~= nil and string.lower(cond.name) == condname) or string.lower(ongoingEffectInfo.name) == condname then
						seqFound = effectInfo.seq
						local casterTok = dmhub.GetTokenById(effectInfo.casterInfo.tokenid)
						if casterTok ~= nil then
							result = GenerateSymbols(casterTok.properties)
						end
					end
				end
			end

			if result ~= nil then
				return result
			end

			for key,entry in pairs(c:try_get("inflictedConditions") or {}) do
				local cond = conditionsTable[key]
				if cond ~= nil and string.lower(cond.name) == condname  and entry.casterInfo ~= nil then
					local casterTok = dmhub.GetTokenById(entry.casterInfo.tokenid)
					if casterTok ~= nil then
						result = GenerateSymbols(casterTok.properties)
					end
				end
			end

			return result
		end
	end,

	conditions = function(c)

		local result = {}
		local conditions = {}
		local ongoingEffects = c:ActiveOngoingEffects()
		if #ongoingEffects > 0 then
			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
			for i,cond in ipairs(ongoingEffects) do
				local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]
				--if this ongoing effect has an underlying condition then record us having that condition since conditions can also have modifiers.
				if ongoingEffectInfo.condition ~= 'none' then
					conditions[ongoingEffectInfo.condition] = true
				end
			end
		end

        --get bestowed conditions.
        for i,modifier in ipairs(c:GetActiveModifiers()) do
            if modifier.mod:CanBestowConditions() and modifier.mod:PassesFilter(c, modifier) then
                modifier.mod:BestowConditions(modifier, c, conditions)
            end
        end

		--we have a table of conditions based on ongoing effects, add any of their modifiers.
		local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
		for k,_ in pairs(conditions) do
			local conditionInfo = conditionsTable[k]
			result[#result+1] = conditionInfo.name
		end

		local inflictedConditions = c:get_or_add("inflictedConditions", {})
		for condid,_ in pairs(inflictedConditions) do
			result[#result+1] = conditionsTable[condid].name
		end

		return StringSet.new{
			strings = result,
		}

	end,

	ongoingeffects = function(c)

		local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

		local strings = {}
		for i,effect in ipairs(c:ActiveOngoingEffects()) do
			local info = ongoingEffectsTable[effect.ongoingEffectid]
			if info ~= nil then
				strings[#strings+1] = info.name
			end
		end

		return StringSet.new{
			strings = strings,
		}
	end,

	stacks = function(c)
		return function(name)
			name = string.lower(name)
			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

			local strings = {}
			for i,effect in ipairs(c:ActiveOngoingEffects()) do
				local info = ongoingEffectsTable[effect.ongoingEffectid]
				if info ~= nil and string.lower(info.name) == name then
					return effect.stacks or 1
				end
			end	

			return 0
		end
	end,

    casterset = function(c)
        return function(effectName)
            local result = CreatureSet.new{}
            local ongoingEffects = c:try_get('ongoingEffects')
            if ongoingEffects == nil then
                return result
            end

            effectName = string.lower(effectName)

            local effectid = nil

            local effectsTable = dmhub.GetTable("characterOngoingEffects") or {}
            for key,effect in unhidden_pairs(effectsTable) do
                if string.lower(effect.name) == string.lower(effectName) then
                    effectid = key
                    break
                end
            end

            if effectid == nil then
                return result
            end

            for _,effect in ipairs(ongoingEffects) do
                if effect.ongoingEffectid == effectid and effect:has_key("casterSet") then
                    for key,_ in pairs(effect.casterSet) do
                        local caster = dmhub.GetTokenById(key)
                        if caster ~= nil then
                            result:Add(caster.properties)
                        end
                    end
                end
            end

            return result
        end
    end,

	proficient = function(c)
		return function(skillid)			
			--look to see if it's an item we may be proficient in.
			local itemid = LookupObjectIdInTableByName("tbl_Gear", skillid)
			if itemid ~= nil then
				local gearTable = dmhub.GetTable('tbl_Gear')
				local itemInfo = gearTable[itemid]
				if itemInfo ~= nil then
					return c:ProficientWithItem(itemInfo)
				end
			end

			--maybe it's an equipment category -- we also check for supersets.
			itemid = LookupObjectIdInTableByName(EquipmentCategory.tableName, skillid)
			if itemid ~= nil then
				local profs = c:EquipmentProficienciesKnown()
				local dataTable = dmhub.GetTable(EquipmentCategory.tableName) or {}
				local count = 0
				while dataTable[itemid] ~= nil and count < 4 do
					
					if profs[itemid] then
						return true
					end

					itemid = dataTable[itemid]:try_get("superset")
					count = count+1
				end
			end

			itemid = LookupObjectIdInTableByName(Skill.tableName, skillid)
			if itemid ~= nil then
				local skillsTable = dmhub.GetTable(Skill.tableName)
				if skillsTable[itemid] ~= nil then
					return c:ProficientInSkill(skillsTable[itemid])
				end
			end


			return false
			
		end
	end,

	languages = function(c)
		local langs = c:LanguagesKnown()
		local result = {}
		local languagesTable = dmhub.GetTable("languages") or {}
		for k,_ in pairs(langs) do
			local lang = languagesTable[k]
			if lang ~= nil then
				result[#result+1] = lang.name
			end
		end

		return StringSet.new{
			strings = result,
		}
	end,

	mounted = function(c)
		local token = dmhub.LookupToken(c)
		if token == nil then
			return false
		end

		return token.mount ~= nil
	end,

	mount = function(c)
		local token = dmhub.LookupToken(c)
		if token == nil or token.mount == nil then
			return nil
		end

		return token.mount.properties
	end,

    hiddenthisturn = function(c)
        local hiddenid = c:try_get("_tmp_hiddenTurnId")
        if hiddenid == nil then
            return false
        end

        local q = dmhub.initiativeQueue
        if q ~= nil and not q.hidden then
            local id = q:GetTurnId()
            return hiddenid == id
        end

        return false
    end,    

	lastcaster = function(c)
		local casterID = c:try_get("casterid", nil)
		if casterID ~= nil then	
			local casterCreature = dmhub.GetTokenById(casterID).properties
			return casterCreature
		end
		return nil
	end,

	ongoingdc = function(c)
		return function(ongoingName)
			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
	
			local DCout = 0
	
			local strings = {}
			for i, effect in ipairs(c:ActiveOngoingEffects()) do
				local info = ongoingEffectsTable[effect.ongoingEffectid]
				if info ~= nil and info.name == ongoingName then
					DCout = effect:try_get('ongoingDC', DCout)
				end
			end
	
			return DCout
		end
	end,

	passive = function(c)
		return function(passiveName)
			local passiveMod = 0
	
			for i, skillInfo in ipairs(Skill.PassiveSkills) do
				if skillInfo.id == passiveName then
					passiveMod = c:PassiveMod(skillInfo)
				end
			end
	
			return passiveMod
		end
	end,

	skillmodifier = function(c)
		return function(skillName)
			skillName = skillName:gsub("%s+", "")
			skillName = string.lower(skillName)
			for i, skillInfo in ipairs(Skill.SkillsInfo) do
				if skillName == string.lower(skillInfo.name):gsub("%s+", "") then
					return c:SkillMod(skillInfo)
				end
			end

			return 0
		end
	end,

	savemodifier = function(c)
		return function(saveid)
			saveid = string.lower(saveid)
			if creature.savingThrowInfo[saveid] == nil then
				return 0
			end

			return c:SavingThrowMod(saveid)

		end
	end,

	conditionimmunities = function(c)

		local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
		local items = {}
		local immunities = c:GetConditionImmunities()
		for k,_ in pairs(immunities) do
			local condition = conditionsTable[k]
			if condition ~= nil then
				items[#items+1] = condition.name
			end
		end

		return StringSet.new{
			strings = items
		}
	end,

	combatround = function(c)
		local q = dmhub.initiativeQueue
		if q == nil or q.hidden then
			return 0
		end

		return GetCombatRound(q) + 1
	end,

	__is__ = function(c)
		return function(s)
            if type(s) == "string" then
                s = string.lower(s)

                if c:MatchesString(nil, nil, s) then
                    return true
                end

                local conditions = {}
                local ongoingEffects = c:ActiveOngoingEffects()
                if #ongoingEffects > 0 then
                    local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
                    for i,cond in ipairs(ongoingEffects) do
                        local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]
                        --if this ongoing effect has an underlying condition then record us having that condition since conditions can also have modifiers.
                        if ongoingEffectInfo.condition ~= 'none' then
                            conditions[ongoingEffectInfo.condition] = true
                        end

                        if string.lower(ongoingEffectInfo.name) == s then
                            return true
                        end
                    end
                end

                --get bestowed conditions.
                for i,modifier in ipairs(c:GetActiveModifiers()) do
                    if modifier.mod:CanBestowConditions() and modifier.mod:PassesFilter(c, modifier) then
                        modifier.mod:BestowConditions(modifier, c, conditions)
                    end
                end

                --we have a table of conditions based on ongoing effects, add any of their modifiers.
                local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
                for k,_ in pairs(conditions) do
                    local conditionInfo = conditionsTable[k]
                    if string.lower(conditionInfo.name) == s then
                        return true
                    end
                end

                local inflictedConditions = c:get_or_add("inflictedConditions", {})
                for condid,_ in pairs(inflictedConditions) do
                    if string.lower(conditionsTable[condid].name) == s then
                        return true
                    end
                end
            end
            return false
		end
	end,

}

--add movement types.
for _,movementType in ipairs(creature.movementTypeInfo) do
	local key = string.lower(string.format("%sspeed", movementType.verb))
	local name = string.format("%s Speed", movementType.verb)

	creature.lookupSymbols[key] = function(c)
		return c:GetSpeed(movementType.id)
	end

	local seealso = {}
	for _,otherType in ipairs(creature.movementTypeInfo) do
		local otherName = string.format("%s Speed", otherType.verb)
		seealso[#seealso+1] = otherName
	end

	creature.helpSymbols[key] = {
		name = name,
		type = "number",
		desc = string.format("The %s of the creature, in squares per round. 0 if the creature does not have a %s.", name, name),
		seealso = seealso,
	}
end

--mod tool for adding new Goblin Script symbols
--Use the following fields:
-- symbol: string symbol name
-- lookup: function to insert in lookupsymbols, runs in GoblinScript
-- help: (optional) corresponding helpsymbols input
function creature.RegisterSymbol(newSymbol)
	local key = newSymbol.symbol
	creature.lookupSymbols[key] = newSymbol.lookup
	if newSymbol.help ~= nil then
		creature.helpSymbols[key] = newSymbol.help
		character.helpSymbols[key] = creature.helpSymbols[key]
		monster.helpSymbols[key] = creature.helpSymbols[key]
	end
	character.lookupSymbols[key] = creature.lookupSymbols[key]
	monster.lookupSymbols[key] = creature.lookupSymbols[key]
end

--called by dmhub to see the symbols this creature has.
function GenerateSymbols(self, symbolTable)
	if self == nil and symbolTable == nil then
		return nil
	end

	return function(symbol)
		if symbolTable ~= nil then
			local sym = symbolTable[symbol]
			if sym ~= nil then
				return sym
			end
		end

		if self == nil then
			return nil
		end

		local fn = self.lookupSymbols[symbol]
		if fn ~= nil then
			return fn(self)
		end

		return nil
	end
end

function creature:GetLevelInClass(classid)
	for i,classEntry in ipairs(self:try_get("classes", {})) do
		if classEntry.classid == classid then
			return classEntry.level
		end
	end

	return 0
end

function creature:LookupSymbol(symbolTable)
	return GenerateSymbols(self, symbolTable)
end

function creature:BeginTurn()
	--just in case some linger.
	self:ClearMomentaryOngoingEffects()

    self:CheckAuraExpiration("nextturn")
    
	local token = dmhub.LookupToken(self)
    local order = 1

    if token ~= nil then
		local initiativeid = InitiativeQueue.GetInitiativeId(token)
	    local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        if tokens ~= nil then
            for i,tok in ipairs(tokens) do
                if tok.charid == token.charid then
                    order = i
                    break
                end
            end
        end
    end

    print("BeginTurn: order =", order)
	dmhub.Coroutine(function()
        self:DispatchEventAndWait("prestartturn", {})
        self:DispatchEvent("beginturn", {order = order})
    end)


	if token ~= nil then
		local concentrationList = self:try_get("concentrationList")
		if concentrationList ~= nil then
			local hasExpiration = false
			for i,concentration in ipairs(concentrationList) do
				if concentration:HasExpired() then
					hasExpiration = true
				end
			end

			token:ModifyProperties{
				description = "End Concentration",
				undoable = false,
				execute = function()
					for i=#concentrationList,1,-1 do
						if concentrationList[i]:HasExpired() then
							self:CancelConcentration(concentrationList[i])
						end
					end
				end,
			}
		end
	end

	if self:has_key("auras") then
		local expires = false
		for i,aura in ipairs(self.auras) do
			if aura:HasExpired() then
				expires = true
			end
		end

		if expires then
			local newAuras = {}
			for i,aura in ipairs(self.auras) do
				if aura:HasExpired() then
					aura:DestroyAura(self)
				else
					newAuras[#newAuras+1] = aura
				end
			end
			self.auras = newAuras
		end
	end

	if token ~= nil then
	    local auras = self:GetAurasAffecting(token)
		if auras ~= nil then
			for i,auraInfo in ipairs(auras) do
				self:EnterAura(auraInfo)
			end
		end
	end
end

function creature:GetAurasAffecting(token)
    token = token or dmhub.LookupToken(self)
    if token == nil then
        return nil
    end

    local auras = token:GetAurasTouching()
    if auras == nil or #auras == 0 then
        return nil
    end

    local numPass = nil

    for i,aura in ipairs(auras) do
        if aura.auraInstance.aura:CreaturePassesFilter(self, aura.auraInstance) == false then
            numPass = i-1
            break
        end
    end

    if numPass == nil then
        return auras
    end

    local result = {}
    for i=1,numPass do
        result[#result+1] = auras[i]
    end

    for i=numPass+2,#auras do
        local aura = auras[i]
        if aura.auraInstance.aura:CreaturePassesFilter(self, aura.auraInstance) then
            result[#result+1] = aura
        end
    end

    return result
end

function creature:EndTurn(token)

    --end turn before ending effects. This makes it so if e.g. you have an ongoing effect
    --that marks us as being immune to damage, and damage happens at the end of the turn
    --we are still immune to that damage.
	token.properties:DispatchEvent("endturn", {})

	if self:has_key("ongoingEffects") then
		local hasRemoves = false
		for _,effectInstance in ipairs(self.ongoingEffects) do
			if effectInstance.removeAtNextTurnEnd then
				hasRemoves = true
			end
		end

		local newOngoingEffects = {}
		for _,effectInstance in ipairs(self.ongoingEffects) do
			local remove = effectInstance.removeAtNextTurnEnd
			if not remove then
				newOngoingEffects[#newOngoingEffects+1] = effectInstance
			end
		end

		token:ModifyProperties{
			description = "Remove ongoing effects",
			execute = function()
				self.ongoingEffects = newOngoingEffects
			end,
		}
	end
	self:CheckAuraExpiration("endturn")

end

function creature:EndRound(token)

    --remove ongoing effects.
	if self:has_key("ongoingEffects") then
		local hasRemoves = false
		for _,effectInstance in ipairs(self.ongoingEffects) do
			if effectInstance.removeAtRoundEnd then
				hasRemoves = true
			end
		end

        if hasRemoves then

            token:ModifyProperties{
                description = "Remove ongoing effects",
                execute = function()
                    local newOngoingEffects = {}
                    for _,effectInstance in ipairs(self.ongoingEffects) do
                        local remove = effectInstance.removeAtRoundEnd
                        if (not remove) or type(remove) == "number" then
                            if type(remove) == "number" then
                                effectInstance.removeAtRoundEnd = effectInstance.removeAtRoundEnd - 1
                                if effectInstance.removeAtRoundEnd == 1 then
                                    effectInstance.removeAtRoundEnd = true
                                end
                            end
                            newOngoingEffects[#newOngoingEffects+1] = effectInstance
                        end
                    end

                    self.ongoingEffects = newOngoingEffects
                end,
            }
        end
	end

    self:CheckAuraExpiration("endround")

	self:DispatchEvent("beginround")
end

--returns a list in this format:
--{
--    modifier: the modifier this ability is from
--    available: boolean whether this ability can be triggered.
--    resources: text description of resource availability.
--    ability: the TriggeredAbility object.
--}
--
--- @return {modifier: CharacterModifier, available: boolean, resources: string, ability: TriggeredAbility}
function creature:GetTriggeredAbilities()
	local mods = self:GetActiveModifiers()
	local result = {}

	for i,mod in ipairs(mods) do
		mod.mod:FillTriggeredAbilities(mod, self, result)
	end

	return result
end

function creature:RemoveOngoingEffectsOnTrigger(eventName, info)
    if info and info.subject ~= nil then
        return false
    end

	if self:has_key("ongoingEffects") then
		local ongoingEffectsTable = dmhub.GetTable(CharacterOngoingEffect.tableName) or {}
		local removeIndexes = nil
		for i,effectInstance in ipairs(self.ongoingEffects) do
			local ongoingEffect = ongoingEffectsTable[effectInstance.ongoingEffectid]
			if ongoingEffect ~= nil and ongoingEffect.endTrigger == eventName then
				if removeIndexes == nil then
					removeIndexes = {}
				end

				removeIndexes[#removeIndexes+1] = i
			end
		end

		if removeIndexes ~= nil then
			local token = dmhub.LookupToken(self)
			if token ~= nil then
				token:ModifyProperties{
					description = "Remove ongoing effects",
					undoable = false,
					execute = function()
						for i=#removeIndexes,1,-1 do
							table.remove(self.ongoingEffects, removeIndexes[i])
						end
					end,
				}
			end

            return true
		end
	end

    return false
end

function creature:DispatchEventOnOthers(eventName, info)
    info = info or {}
    info.subject = self
    local tokens = dmhub.GetTokens()
    for i,token in ipairs(tokens) do
        if token.properties ~= self then
            token.properties:DispatchEvent(eventName, info)
        end
    end
    info.subject = nil
end

function creature:TriggerEventOnOthers(eventName, info)
    info = info or {}
    info.subject = self
    local tokens = dmhub.GetTokens()
    for i,token in ipairs(tokens) do
        if token.properties ~= self then
            token.properties:TriggerEvent(eventName, info)
        end
    end
    info.subject = nil
end

creature.debugTriggerHandler = false

--an event is triggered which could cause triggered abilities to go off.
function creature:TriggerEvent(eventName, info, alreadyTriggeredOnOthers)

    if (not alreadyTriggeredOnOthers) and (info == nil or info.subject == nil) then
        self:TriggerEventOnOthers(eventName, info)
    end

	local mods = self:GetActiveModifiers()
	local result = false

    local debugLog = nil
    if creature.debugTriggerHandler then
        debugLog = {}
    end

	for i,mod in ipairs(mods) do
		local triggered = mod.mod:TriggerEvent(self, eventName, info, mod, debugLog)
		if triggered then
			result = true
		end
	end

	result = self:RemoveOngoingEffectsOnTrigger(eventName, info) or result

    if creature.debugTriggerHandler then
        creature.debugTriggerHandler(self, eventName, info, debugLog)
    end

	if result then
		self:Invalidate()
	end

	return true
end

function creature:DispatchEvent(eventName, info, onCompleteCallback)

    --print("DISPATCH:: EVENT =", eventName, "SUBJECT", info ~= nil and info.subject ~= nil)


    local triggeredOnOthers = false
    if info == nil or info.subject == nil then
        self:DispatchEventOnOthers(eventName, info)
        triggeredOnOthers = true
    end

	local mods = self:GetActiveModifiers()
	local hasTrigger = false
	for i,mod in ipairs(mods) do
		if mod.mod:HasTriggeredEvent(self, eventName, info ~= nil and info.subject ~= nil) then
			hasTrigger = true
			break
		end
	end

    --print("DISPATCH:: HAVE TRIGGER:", hasTrigger)

	if hasTrigger == false then
		--still remove any ongoing effects.
		self:RemoveOngoingEffectsOnTrigger(eventName, info)
        if creature.debugTriggerHandler then
            creature.debugTriggerHandler(self, eventName, info, false)
        end
		return
	end

	local token = dmhub.LookupToken(self)
	local activecontroller = token.activeControllerId

    --print("DISPATCH:: active controller =", activecontroller, "from event", eventName, "vs", dmhub.userid)

	--we are the best choice to handle this event.
	if activecontroller == nil then
		self:TriggerEvent(eventName, info, triggeredOnOthers)
		return
	end

    if info ~= nil then
        local serializedInfo = {}
        for k,v in pairs(info) do
            if type(v) == "table" then
                local id = dmhub.LookupTokenId(v)
                if id ~= nil then
                    serializedInfo[k] = "charid:" .. id
                else
                    serializedInfo[k] = v
                end
            else
                serializedInfo[k] = v
            end
        end

        info = serializedInfo
    end

	token:ModifyProperties{
		description = "Dispatch Event",
		undoable = false,
		execute = function()
			local triggeredEvents = self:get_or_add("triggeredEvents", {})

            --clear out any old or invalid events.
            while #triggeredEvents > 0 and (triggeredEvents[1].timestamp == nil or TimestampAgeInSeconds(triggeredEvents[1].timestamp) > 30) do
                table.remove(triggeredEvents, 1)
            end

			triggeredEvents[#triggeredEvents+1] = {
				userid = activecontroller,
				timestamp = ServerTimestamp(),
				eventName = eventName,
				info = info,
			}
		end,
	}
end

function creature:TriggeredAbilityEnabled(ability)
	local activeTriggers = self:try_get("activeTriggers", {})
	local value = activeTriggers[ability.guid]
	if value == nil then
		return true
	end

	return value
end

--sets if a triggered ability is set to auto-activate or not. TODO: Keep for Draw Steel?
function creature:SetTriggeredAbilityEnabled(ability, value)
	local activeTriggers = self:get_or_add("activeTriggers", {})
	if value == true then
		value = nil
	end
	activeTriggers[ability.guid] = value
end

--- @class ActiveTrigger
--- @field timestamp number
--- @field id string
--- @field charid string
--- @field free boolean
--- @field heroicResourceCost number
--- @field targets string[]
--- @field powerRollModifier false|CharacterModifier
--- @field triggered boolean|number
--- @field dismissed boolean
--- @field ping false|string
--- @field text string
--- @field retargetid false|string
--- @field rules string
--- @field modes {text: string, rules: string}[]
--- @field casterid false|string The id of the caster of the ability that caused the trigger.
--- @field originalAbilityRange number the range of the original ability that caused the trigger.
ActiveTrigger = RegisterGameType("ActiveTrigger")
ActiveTrigger.id = ""
ActiveTrigger.charid = ""
ActiveTrigger.free = true
ActiveTrigger.timestamp = 0
ActiveTrigger.heroicResourceCost = 0
ActiveTrigger.clearOnDismiss = false
ActiveTrigger.dismissOnTrigger = false
ActiveTrigger.powerRollModifier = false
ActiveTrigger.targets = {}
ActiveTrigger.triggered = false
ActiveTrigger.dismissed = false
ActiveTrigger.ping = false
ActiveTrigger.retargetid = false
ActiveTrigger.text = "Trigger"
ActiveTrigger.activateText = "Activate"
ActiveTrigger.rules = ""
ActiveTrigger.modes = {}
ActiveTrigger.casterid = false
ActiveTrigger.originalAbilityRange = 0
ActiveTrigger.params = {}

function ActiveTrigger:DismissOnTrigger()
    return self.dismissOnTrigger
end

function ActiveTrigger:GetText()
	if self.powerRollModifier then
		return self.powerRollModifier.name
	end

	return self.text
end

function ActiveTrigger:GetRulesText()
	if self.powerRollModifier then
		return self.powerRollModifier:try_get("rules", "")
	end

	return self.rules
end

function ActiveTrigger:IsFreeTriggeredAbility()
    if self.powerRollModifier then
        return self.powerRollModifier.type == "free" or self.powerRollModifier.type == "passive"
    end

    return self.free
end

function ActiveTrigger:EnhancementOptions(token)

	if self.powerRollModifier then
	    local result = {}
		local additionalModifiers = token.properties:GetAdditionalCostModifiersForPowerTableTrigger(self.powerRollModifier)
		for _,modifier in ipairs(additionalModifiers) do
			local amount = dmhub.EvalGoblinScriptDeterministic(modifier:try_get("resourceCostAmount", 1), token.properties:LookupSymbol{}, 1)
			local text = string.format("%d %s", amount, token.properties:GetHeroicResourceName())
			local rules = modifier:try_get("rulesText", "")
			local available = token.properties:GetHeroicOrMaliceResourcesAvailableToSpend()
			if amount <= available then
				result[#result+1] = {
					text = text,
					rules = rules,
                    cost = amount,
				}
			end
		end
        return result
	end

    return self.modes
end


--- @return nil|table<string,ActiveTrigger>
function creature:GetAvailableTriggers(excludeDismissed)
	local availableTriggers = self:try_get("availableTriggers")
	if availableTriggers == nil then
		return nil
	end

	local hasExpired = false
	local hasValid = false
	for key,value in pairs(availableTriggers) do
		local age = TimestampAgeInSeconds(value.timestamp)
		if age > 60 or value.id ~= key then
			hasExpired = true
		elseif (not value.dismissed) or (not excludeDismissed) then
			hasValid = true
		end
	end

	if not hasValid then
		return nil
	end

	if not hasExpired then
		return availableTriggers
	end

	local result = {}
	for key,value in pairs(availableTriggers) do
		if value.id == key and ((not value.dismissed) or (not excludeDismissed)) then
			local age = TimestampAgeInSeconds(value.timestamp)
			if age <= 60 then
				result[key] = value
			end
		end
	end

	return result
end

-- called when another token is deleted.
--- @param charid string The character id of the token being deleted.
function creature:OnTokenDelete(charid)
    local clears = nil
	local availableTriggers = self:get_or_add("availableTriggers", {})
    for key,value in pairs(availableTriggers) do
        if table.contains(value.targets, charid) then
            clears = clears or {}
            clears[#clears+1] = key
        end
    end

    if clears == nil then
        return
    end

    local token = dmhub.LookupToken(self)
    if token ~= nil then
        token:ModifyProperties{
            description = "Clear Available Triggers",
            execute = function()
                for _,key in ipairs(clears) do
                    availableTriggers[key] = nil
                end
            end,
        }
    end
end

--- @param triggerInfo ActiveTrigger
function creature:DispatchAvailableTrigger(triggerInfo)
    if triggerInfo.clearOnDismiss and (triggerInfo.dismissed or (self:get_or_add("_tmp_clearedTriggers", {})[triggerInfo.id] == true)) then
        self:ClearAvailableTrigger(triggerInfo)
        return
    end


	local availableTriggers = self:get_or_add("availableTriggers", {})
	local deletes = {}
	for key,value in pairs(availableTriggers) do
		local age = TimestampAgeInSeconds(value.timestamp)
		if age > 60 then
			deletes[#deletes+1] = key
		elseif triggerInfo ~= nil and availableTriggers[triggerInfo.id] == nil and triggerInfo.powerRollModifier == false and value.powerRollModifier == false then
            --de-duplicate spammy triggers that all do the same thing, e.g. if Tactician Mastermind's Overwatch trigger against the same moving creature.
			if (not value.dismissed) and (not value.triggered) and (value.text == triggerInfo.text) and (value.rules == triggerInfo.rules) and dmhub.DeepEqual(value.modes, triggerInfo.modes) and dmhub.DeepEqual(value.targets, triggerInfo.targets) then
				--just refresh this trigger instead of creating a new one.
				value.timestamp = ServerTimestamp()
				triggerInfo = nil
			end
		end
	end

	for _,key in ipairs(deletes) do
		availableTriggers[key] = nil
	end

    if triggerInfo ~= nil then
	    triggerInfo = DeepCopy(triggerInfo)
	    triggerInfo.timestamp = ServerTimestamp()
	    availableTriggers[triggerInfo.id] = triggerInfo
    end
end

function creature:ClearAvailableTrigger(triggerInfo)
    local clearedTriggers = self:get_or_add("_tmp_clearedTriggers", {})
    clearedTriggers[triggerInfo.id] = true

	local availableTriggers = self:get_or_add("availableTriggers", {})
	local deletes = {}
	for key,value in pairs(availableTriggers) do
		local age = TimestampAgeInSeconds(value.timestamp)
		if age > 60 or key == triggerInfo.id then
			deletes[#deletes+1] = key
		end
	end

	for _,key in ipairs(deletes) do
		availableTriggers[key] = nil
	end
end

function creature:GetTurnId()
	local turnid = nil
	if GameHud.instance and GameHud.instance.tokenInfo ~= nil and GameHud.instance.tokenInfo.initiativeQueue ~= nil then
		turnid = GameHud.instance.tokenInfo.initiativeQueue:GetTurnId()
	end
	return turnid
end

--called by dmhub to see if entering this aura will halt movement.
function creature:EnterAuraHaltsMovement(info)
	local turnid = self:GetTurnId()
	if turnid ~= nil and turnid == self:try_get("aurasEnteredTurnId") and self.aurasEntered[info.auraInstance.guid] then
		return false
	end
	
	return true
end

--called by dmhub when a creature enters an aura.
--returns true if the aura triggered something, false otherwise.
function creature:EnterAura(info)

    if info.auraInstance.aura:CreaturePassesFilter(self, info.auraInstance) == false then
        return
    end

	local result = false
	if self:EnterAuraHaltsMovement(info) == false then
		return result
	end

	local turnid = self:GetTurnId()

	if turnid ~= nil and info.token ~= nil and info.token.valid then
		info.token:ModifyProperties{
			description = "Enter Aura",
			execute = function()
				if self:try_get("aurasEnteredTurnId") ~= turnid then
					self.aurasEnteredTurnId = turnid
					self.aurasEntered = {}
				end

				self.aurasEntered[info.auraInstance.guid] = true
			end,
		}
	end

	for i,triggerInfo in ipairs(info.auraInstance.aura.triggers) do
		if triggerInfo.trigger == "onenter" then
            local auraCasterToken = info.token
            if auraCasterToken == nil or auraCasterToken.valid == false or (not auraCasterToken.uploadable) then
                auraCasterToken = dmhub.LookupToken(self)
            end
			result = true
            print("AURA:: FIRE")
			info.auraInstance:FireTriggeredAbility(triggerInfo.ability, self, auraCasterToken)
            if triggerInfo.destroyaura then
                print("AURA:: DESTROY", info)
                info:Destroy()
            end
		end
	end

	return result
end

function creature:Rest(restType)
	local restid = dmhub.GenerateGuid()

	if restType == 'long' then
		if self.damage_taken > 0 then
			self:Heal(self.damage_taken, "Long rest")
		end

		local victories = self:try_get("victories", 0)
		if victories > 0 then
			local curXp = self:try_get("xp", 0)
			local newXp = curXp + victories
			local level = self:CharacterLevel()
			local xpPerLevel = toint(dmhub.GetSettingValue("xpperlevel") or 16)
			if xpPerLevel == 0 then xpPerLevel = 16 end
			local xpNextLevel = level * xpPerLevel
			local newLevel = level
			local levelingUp = newXp >= xpNextLevel
			if levelingUp then
				newLevel = math.floor(newXp / xpPerLevel) + 1
				if newLevel > level then
					local classes = self:try_get("classes", {})
					if classes and #classes > 0 then
						classes[1].level = newLevel
					end
				end
			end
			self.xp = newXp
			self.victories = 0
		end

		self.longRestId = restid
	end

	self.shortRestId = restid

	if self:has_key("ongoingEffects") then
		local newOngoingEffects = {}
		for _,effectInstance in ipairs(self.ongoingEffects) do
			local remove = effectInstance.removeOnShortRest or (effectInstance.removeOnLongRest and restType == 'long')
			if not remove then
				newOngoingEffects[#newOngoingEffects+1] = effectInstance
			end
		end

		self.ongoingEffects = newOngoingEffects
	end

end

function creature:HasConcentration()
	return self:try_get("concentrationList") ~= nil and #self.concentrationList > 0
end

function creature:MostRecentConcentrationId()
	local concentration = self:MostRecentConcentration()
	if concentration == nil then
		return nil
	end

	return concentration.id
end

function creature:MostRecentConcentration()
	if not self:HasConcentration() then
		return nil
	end

	return self.concentrationList[#self.concentrationList]
end

function creature:CancelConcentration(item)
	if self:try_get("concentrationList") == nil  or #self.concentrationList == 0 then
		return
	end

	for i=#self.concentrationList,1,-1 do
		local concentration = self.concentrationList[i]
		if item == nil or concentration == item then
			table.remove(self.concentrationList, i)

			if concentration:has_key("auraid") then
				self:RemoveAura(concentration.auraid)
			end


			for _,objref in ipairs(concentration:try_get("objects", {})) do
				local obj = game.LookupObject(objref.floorid, objref.objid)
				if obj ~= nil then
					obj:Destroy()
				end
			end

			if concentration:has_key("summonid") then
				game.UnsummonTokens(concentration.summonid)
			end
		end
	end
end

function creature:GetConcentrationById(id)
	for _,concentration in ipairs(self:try_get("concentrationList", {})) do
		if concentration.id == id then
			return concentration
		end
	end

	return nil
end

function creature:BeginConcentration(name)
	if GameSystem.AllowMultipleConcentration == false then
		self:CancelConcentration()
	end

	local concentrationList = self:get_or_add("concentrationList", {})

	local concentration = Concentration.new{
		id = dmhub.GenerateGuid(),
		name = name,
		time = TimePoint.Create()
	}

	concentrationList[#concentrationList+1] = concentration

	return concentration
end

function creature:CheckToMaintainConcentration(saveInfo)
	dmhub.Coroutine(creature.CheckToMaintainConcentrationCo, self, saveInfo)
end

function creature:CheckToMaintainConcentrationCo(saveInfo)

	if saveInfo.autosuccess then
		return
	end

	local dc = saveInfo.dc
	if type(dc) ~= "number" then
		return
	end

	local token = dmhub.LookupToken(self)
	if token == nil then
		return
	end

	if saveInfo.autofailure then
		if token.valid then
			token:ModifyProperties{
				description = "Lose Concentration",
				execute = function()
					token.properties:CancelConcentration()
				end,
			}
		end
		return
	end

	local tokid = token.charid

	local tokenInfo = {}
	tokenInfo[tokid] = {}

	local rollArgs = {
		type = "save",
		id = "con",
		dc = dc,

		text = "Concentration",
		explanation = string.format("DC %d %s check to maintain concentration", dc, string.upper(saveInfo.id or "con")),
		silent = true,
		options = {
			condition = "concentration"
		},
	}

	for k,v in pairs(saveInfo) do
		rollArgs[k] = v
	end

	local actionid = dmhub.SendActionRequest(RollRequest.new{
		checks = {
			RollCheck.new(rollArgs),
		},
		tokens = tokenInfo,
		silent = true, --this makes it so the dialog isn't shown to the requester, since it's an automated action.
	})
	
	local result = AwaitRequestedActionCoroutine(actionid)
	if result.result and result.action ~= nil then
		local info = result.action.info.tokens[tokid]
		if info ~= nil and info.result ~= nil and info.result < dc then
			--concentration lost.

			if token.valid then
				token:ModifyProperties{
					description = "Lose Concentration",
					execute = function()
						token.properties:CancelConcentration()
					end,
				}
			end
		end
	end
end

local g_defaultAuraDisplaySettings = {
    hide = false,
    opacity = 1,
}

--- @param name string
--- @return {hide: boolean, opacity: number}
function creature:GetAuraDisplaySetting(name)
    local settings = rawget(self, "auraDisplaySettings")
    if settings == nil then
        return g_defaultAuraDisplaySettings
    end

    return settings[name] or g_defaultAuraDisplaySettings
end

--- @param name string
--- @param info nil|{hide: boolean, opacity: number}
function creature:SetAuraDisplaySetting(name, info)
    local settings = self:get_or_add("auraDisplaySettings", {})
    settings[name] = info
end

--this is called by DMHub to get the auras currently controlled by an object. 
--returns a list of AuraInstance objects.
function creature:GetAuras()
	local generatedAuras = {}

	self._tmp_calculatingActiveModifiers = {}
	local modifiers = self:GetActiveModifiersExcludingAuras(self._tmp_calculatingActiveModifiers)
	self._tmp_calculatingActiveModifiers = nil

	for i,mod in ipairs(modifiers) do
		mod.mod:FillAuras(mod, self, generatedAuras)
	end

	local result

	if not self:has_key("auras") then
		result = generatedAuras
	else

		if #generatedAuras == 0 then
			result = self.auras
		else
			for _,aura in ipairs(self.auras) do
				generatedAuras[#generatedAuras+1] = aura
			end
			result = generatedAuras
		end
	end

	if #result > 0 then
		local filteredResult = {}
		for _,item in ipairs(result) do
			if rawget(item, "object") == nil or game.LookupObject(item.object.floorid, item.object.objid).valid then
				filteredResult[#filteredResult+1] = item
			end
		end

		result = filteredResult
	end

    for _,auraInstance in ipairs(result) do
        local settings = self:GetAuraDisplaySetting(auraInstance.name)
        if settings ~= nil then
            auraInstance._tmp_displaySettings = settings
        end
    end

	return result
end

function creature:HasInspiration()
	return self:has_key("inspiration")
end

function creature:SetInspiration(val)
	self.inspiration = cond(val, true, nil)
end

function creature:GetConditionImmunities()
	local result = dmhub.DeepCopy(self:try_get("innateConditionImmunities", {}))
	local modifiers = self:GetActiveModifiers()
	for i,mod in ipairs(modifiers) do
		mod.mod:FillConditionImmunities(mod, self, result)
	end
	return result
end




-----------------
--ARMOR CLASS
-----------------
function creature:DexModifierForArmorClass()
	local dexModifier = 0
	if GameSystem.ArmorClassModifierAttrId ~= false then
		self:GetAttribute(GameSystem.ArmorClassModifierAttrId):Modifier()
	end

	if self:Equipment().armor then
		local gearTable = dmhub.GetTable('tbl_Gear')
		local armor = gearTable[self:Equipment().armor]
		if armor:has_key('dexterityLimit') and armor.dexterityLimit < dexModifier then
			dexModifier = armor.dexterityLimit
			if armor.dexterityLimit == 0 then
				return nil
			end
		end
	end

	return dexModifier
end

function creature:ArmorClassDetails()
	local baseArmorClass = self:try_get("armorClass", GameSystem.BaseArmorClass)
	local gearTable = dmhub.GetTable('tbl_Gear')
	local dexModifier = 0
	
	if GameSystem.ArmorClassModifierAttrId then
		dexModifier = self:GetAttribute(GameSystem.ArmorClassModifierAttrId):Modifier()
	end

	local result = {}
	

	if self:Equipment().armor then
		local armor = gearTable[self:Equipment().armor]
		if armor ~= nil then
			baseArmorClass = armor.armorClass
			result[#result+1] = { key = armor.name, value = '' .. baseArmorClass }

			if armor:has_key('dexterityLimit') and armor.dexterityLimit < dexModifier then
				dexModifier = armor.dexterityLimit
			end
		end
	else
		result[#result+1] = { key = cond(self:IsMonster(), 'Natural Armor', 'No Armor'), value = '' .. baseArmorClass, edit = cond(self:IsMonster() and (not self:has_key("armorClassOverride")), "SetBaseArmorClass") }
	end

	if self:has_key("armorClass") == false then
		result[#result+1] = { key = 'Dexterity', value = ModifierStr(dexModifier) }
	end

	baseArmorClass = self:DefaultBaseArmorClass()
	local mods = self:GetActiveModifiers()

	for i,mod in ipairs(mods) do
		local altArmorClass = mod.mod:AlterBaseArmorClass(mod, self, baseArmorClass)
		if altArmorClass ~= baseArmorClass then
			baseArmorClass = altArmorClass
			result[#result+1] = { key = mod.mod.name, value = '' .. baseArmorClass }
		end
	end

	local shield = self:GetShield()
	if shield then
		result[#result+1] = { key = shield.name, value = ModifierStr(shield:ArmorClassModifier()) }
	end

	result[#result+1] = { key = 'Manual Override', value = self:ArmorClassOverride(), edit = 'SetArmorClassOverride', showNotes = self:ArmorClassOverride() ~= nil }

	local modifierDescriptions = self:DescribeModifications('armorClass', self:BaseArmorClass())
	for i,mod in ipairs(modifierDescriptions) do
		result[#result+1] = mod
	end


	result[#result+1] = { key = 'Total Armor Class', value = string.format("%d", self:ArmorClass()) }

	return result
end

function creature:DefaultBaseArmorClass()

	local baseArmorClass = self:try_get("armorClass", GameSystem.BaseArmorClass)
	local gearTable = dmhub.GetTable('tbl_Gear')
	local dexModifier = 0

	--if we have armorClass set then dex modifier is already baked in.
	if self:has_key("armorClass") then
		dexModifier = 0
	elseif GameSystem.ArmorClassModifierAttrId ~= false then
		dexModifier = self:GetAttribute(GameSystem.ArmorClassModifierAttrId):Modifier()
	end


	if self:Equipment().armor then
		local armor = gearTable[self:Equipment().armor]
		if armor ~= nil and armor.isArmor then
			baseArmorClass = armor.armorClass
			if armor:has_key('dexterityLimit') and (armor.dexterityLimit < dexModifier or armor.dexterityLimit == 0) then
				dexModifier = armor.dexterityLimit
			end
		end
	end

	return baseArmorClass + dexModifier
end

function creature:SetBaseArmorClass(val)
	local n = tonumber(val)
	self.armorClass = n
end

--protection against recursion in calculating base armor class.
local g_calculatingBaseArmorClass = false

function creature:BaseArmorClass()

	local baseArmorClass = self:DefaultBaseArmorClass()

	if g_calculatingBaseArmorClass == false then

		g_calculatingBaseArmorClass = true

		local mods = self:GetActiveModifiers()

		for i,mod in ipairs(mods) do
			baseArmorClass = mod.mod:AlterBaseArmorClass(mod, self, baseArmorClass)
		end

		g_calculatingBaseArmorClass = false
	end

	local shield = self:GetShield()
	if shield then
		baseArmorClass = baseArmorClass + shield:ArmorClassModifier()
	end

	return baseArmorClass
end


function creature:ArmorClass()
	local result
	local override = self:ArmorClassOverride()
	if override ~= nil then
		result = override
	else
		result = self:BaseArmorClass()
	end

	result = self:CalculateAttribute('armorClass', result)
	return toint(result)
end

function creature:ArmorClassOverride()
	if self:has_key('armorClassOverride') then
		return self.armorClassOverride
	end

	return nil
end

function creature:SetArmorClassOverride(amount)
	if amount ~= nil then
		amount = tonumber(amount)
	end
	self.armorClassOverride = amount

	self.armorClass = nil --this is to clear out old monster armor class overrides.
end

function creature:ArmorClassNotes()
	if self:has_key('armorClassNotes') then
		return self.armorClassNotes
	end

	return ''
end

function creature:SetArmorClassNotes(notes)
	self.armorClassNotes = notes
end

function creature:InitiativeOverride()
	if self:has_key('initiativeOverride') then
		return self.initiativeOverride
	end

	return nil
end

function creature:SetInitiativeOverride(amount)
	if amount ~= nil then
		amount = tonumber(amount)
	end
	self.initiativeOverride = amount
end


function creature:InitiativeNotes()
	if self:has_key('initiativeNotes') then
		return self.initiativeNotes
	end

	return ''
end

function creature:SetInitiativeNotes(notes)
	self.initiativeNotes = notes
end

----------------------------------------------
-- Expected damage roll.
----------------------------------------------
function creature:ExpectDamage(guid, roll)
	local expectedDamage = self:get_or_add("expectedDamage", {})

	expectedDamage[guid] = {
		roll = roll,
		timestamp = ServerTimestamp(),
		dice = {
			set = dmhub.GetSettingValue("diceequipped"),
			color = dmhub.GetSettingValue("playercolor").tostring,
		},
	}
end

function creature:RemoveExpectedDamage(guid)
	local expectedDamage = self:get_or_add("expectedDamage", {})
	expectedDamage[guid] = nil
	
end

function creature.UploadExpectedCreatureDamage(charid, guid, roll)
	local token = dmhub.GetCharacterById(charid)
	if token ~= nil then
		token:ModifyProperties{
			description = "Expect damage",
			execute = function()
				--remove any damage that is more than 2 minutes old
				local expectedDamage = token.properties:get_or_add("expectedDamage", {})
				local removes = {}
				for k,entry in pairs(expectedDamage) do
					if TimestampAgeInSeconds(entry.timestamp) > 120 then
						removes[#removes+1] = k
					end
				end

				for _,k in ipairs(removes) do
					expectedDamage[k] = nil
				end

				if roll ~= nil then
					token.properties:ExpectDamage(guid, roll)
				else
					token.properties:RemoveExpectedDamage(guid, roll)
				end
			end,
		}
	end
end

function creature:GetNameGeneratorTable()
	return nil
end

--called by dmhub when an image is dropped onto this token.
function creature:EventDropImage(path)
	dmhub.Debug("DROP ON TOKEN... " .. path)
	local token = dmhub.LookupToken(self)
	if token == nil then
		return false
	end

	local rollback = {
		portrait = token.portrait,
		portraitOffset = token.portraitOffset,
		portraitZoom = token.portraitZoom,
	}

	assets:UploadImageAsset{
		path = path,
		imageType = "Avatar",
		error = function(text)
			token = dmhub.LookupToken(self)
			if token ~= nil then
				token.portrait = rollback.portrait
				token.portraitOffset = rollback.portraitOffset
				token.portraitZoom = rollback.portraitZoom
			end

			gui.ModalMessage{
				title = 'Error loading image',
				message = text,
			}
		end,
		upload = function(imageid)
			dmhub.AddAndUploadImageToLibrary("Avatar", imageid)

			token.portrait = imageid
			token.portraitOffset = {x = 0, y = 0}
			token.portraitZoom = 1
			token:UploadAppearance()
			dmhub.Debug("COMPLETED PASTE")
		end,
		addlocal = function(imageid)
			dmhub.AddImageToLibraryLocally("Avatar", imageid)
			token.portrait = imageid
			token.portraitOffset = {x = 0, y = 0}
			token.portraitZoom = 1
			token:RefreshAppearanceLocally()
			dmhub.Debug("ADD LOCAL")
		end,
	}

end

--called by dmhub when a 'paste' event gets triggered on this creature (e.g. press ctrl+v while having the token selected.)
function creature:EventPaste()
	local token = dmhub.LookupToken(self)
	if token == nil then
		return false
	end

	if not dmhub.HaveImageInClipboard() then
		return false
	end

	local rollback = {
		portrait = token.portrait,
		portraitOffset = token.portraitOffset,
		portraitZoom = token.portraitZoom,
	}

	dmhub.Debug("PASTING CREATURE...")

	assets:UploadImageAsset{
		path = "CLIPBOARD",
		imageType = "Avatar",
		error = function(text)
			if token ~= nil then
				token.portrait = rollback.portrait
				token.portraitOffset = rollback.portraitOffset
				token.portraitZoom = rollback.portraitZoom
			end

			gui.ModalMessage{
				title = 'Error loading image',
				message = text,
			}
		end,
		upload = function(imageid)
			uploadComplete = true
			dmhub.AddAndUploadImageToLibrary("Avatar", imageid)

			token.portrait = imageid
			token.portraitOffset = {x = 0, y = 0}
			token.portraitZoom = 1
			token:UploadAppearance()
			dmhub.Debug("COMPLETED PASTE")
		end,
		addlocal = function(imageid)
			dmhub.AddImageToLibraryLocally("Avatar", imageid)

			token.portrait = imageid
			token.portraitOffset = {x = 0, y = 0}
			token.portraitZoom = 1
			token:RefreshAppearanceLocally()
		end
	}

	--make multi-select work.
	return false
end

function creature:DescribeAlignment()
	if self:try_get("customAlignment") then
		return self.customAlignment
	end

	local alignmentid = self:try_get("alignment", "unaligned")
	local alignment = rules.alignments[alignmentid]
	if alignment == nil then
		return alignmentid
	end

	return alignment.name
end

--render a 'statblock' for the creature.
function creature:Render(args, options)
	args = args or {}

	local summary = args.summary
	args.summary = nil

	local asset = options.asset
	options.asset = nil

	local token = options.token
	options.token = nil
	
	if asset == nil and token == nil then
		return
	end

	if token == nil then
		token = asset.info
	end

	local alignmentText = self:DescribeAlignment()

	local speedText = string.format("<b>Speed</b> %s %s", MeasurementSystem.NativeToDisplayString(self:WalkingSpeed()), MeasurementSystem.Abbrev())

	for k,v in pairs(self:try_get("movementSpeeds", {})) do
		if k ~= "walk" then
			local speed = self:GetSpeed(k)
			speedText = string.format("%s, %s %s %s.", speedText, tr(k), MeasurementSystem.NativeToDisplayString(speed), MeasurementSystem.Abbrev())
		end
	end

	local charName
	if asset ~= nil then
		charName = asset.name
	else
		charName = token.name
	end

	--calculate a line that is like Large Dragon, Chaotic Evil for monsters and like Level 3 Hill Dwarf Life Cleric/Fighter for characters.
	local summaryLine
	if self:IsMonster() then
		if charName == "" or charName == nil then
			charName = self:try_get("monster_type")
		end
		summaryLine = string.format("%s %s, %s", self:GetBaseCreatureSize() or token.creatureSize, self:RaceOrMonsterType(), alignmentText)
	else
		summaryLine = self:GetCharacterSummaryText()
	end


	--Actions.
	local actionsTitle = nil
	local reactionsTitle = nil
	local legendaryTitle = nil
	local actionsPanel = nil
	local reactionsPanel = nil
	local legendaryPanel = nil
	
	if self:IsMonster() then
		local abilities = self:GetActivatedAbilities{excludeGlobal = true, allLoadouts = true, bindCaster = true}
		local normalActions = {}
		local reactionActions = {}
		local legendaryActions = {}
		for _,ability in ipairs(abilities) do
			if not ability.isSpell then
				local recharge = ability:try_get("recharge")
				local rechargeStr = ""
				if recharge ~= nil then
					rechargeStr = string.format(" (Recharge %d-6)", recharge)
				end
				local text = string.format("<b>%s%s.</b>  %s", ability.name, rechargeStr, ability:GenerateTextDescription(token))
				local panel = gui.Label{
					vmargin = 10,
					text = text,
				}

				if ability.legendary then
					legendaryActions[#legendaryActions+1] = panel
				elseif ability:ActionResource() == "reaction" then
					reactionActions[#reactionActions+1] = panel
				else
					normalActions[#normalActions+1] = panel
				end
			end
		end

		if #normalActions > 0 then
			actionsTitle = gui.Label{
				classes = {"subheading"},
				text = "Actions",
			}

			actionsPanel = gui.Panel{
				flow = "vertical",
				height = "auto",
				width = "100%",
				children = normalActions,
			}
		end

		if #reactionActions > 0 then
			reactionsTitle = gui.Label{
				classes = {"subheading"},
				text = "Reactions",
			}

			reactionsPanel = gui.Panel{
				flow = "vertical",
				height = "auto",
				width = "100%",
				children = reactionActions,
			}
		end

		if #legendaryActions > 0 then
			legendaryTitle = gui.Label{
				classes = {"subheading"},
				text = "Legendary Actions",
			}

			legendaryPanel = gui.Panel{
				flow = "vertical",
				height = "auto",
				width = "100%",
				children = legendaryActions,
			}
		end

	end
		
	local options = {
		width = 500,
		height = "auto",
		flow = "vertical",
		styles = {Styles.Default, SpellRenderStyles},

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",

			gui.Panel{
				flow = "vertical",
				width = "100%-132",
				height = "auto",
				halign = "left",

				gui.Label{
					id = "spellName",
					text = charName,
					width = "100%",
				},

				gui.Label{
					id = "spellSummary",
					width = "100%",
					text = summaryLine,
				},


				gui.Panel{
					classes = "divider",
				},

				gui.Label{
					classes = {"description", cond(self:ArmorClass() == 0, "collapsed")},
					text = string.format("<b>Armor Class</b> %d", self:ArmorClass()),
				},

				gui.Label{
					classes = "description",
					create = function(element)

						element.text = string.format("<b>%s</b> %d", GameSystem.HitpointsName, self:MaxHitpoints())
					end,
				},

				gui.Label{
					classes = "description",
					text = speedText,
				},


			},

			gui.Panel{
				id = "portrait",
				halign = "right",
				valign = "top",
				autosizeimage = true,
				width = "auto",
				height = "auto",
				maxWidth = 128,
				maxHeight = 128,
				bgcolor = "white",
				bgimage = token.portrait,

				loadingImage = function(element)
					element:AddChild(gui.LoadingIndicator{})
				end,
			},
		},

		gui.Panel{
			classes = "divider",
		},

		gui.Panel{
			flow = "horizontal",
			height = "auto",
			width = "100%",
			create = function(element)
				local children = {}

				for i,attrid in ipairs(creature.attributeIds) do
					children[#children+1] = gui.Panel{
						flow = "vertical",
						width = 50,
						height = "auto",
						halign = "center",
						gui.Label{
							halign = "center",
							width = "auto",
							height = "auto",
							text = "<b>" .. string.upper(attrid) .. "</b>",
						},
						gui.Label{
							halign = "center",
							width = "auto",
							height = "auto",
							text = string.format("%s (%s)", self:GetAttribute(attrid):Value(), ModifierStr(self:AttributeMod(attrid))),
						}
					}
				end

				element.children = children
			end,
		},

		gui.Panel{
			classes = "divider",
		},

		--skills.
		gui.Label{
			classes = "description",
			create = function(element)
				local text = ""

				local skillsTable = dmhub.GetTable(Skill.tableName)
				local items = {}
				for k,skillInfo in pairs(skillsTable) do

					local skillMod = self:SkillModStr(skillInfo)
					local attrMod = ModStr(self:GetAttribute(skillInfo.attribute):Modifier())
					if skillMod ~= attrMod then
						items[#items+1] = string.format("%s %s", skillInfo.name, skillMod)
					end
				end

				if #items == 0 then
					element:SetClass("collapsed", true)
				else
					table.sort(items)
					element.text = string.format("<b>Skills</b> %s", string.join(items, ", "))
				end
			end,
		},

		--resistances.
		gui.Label{
			classes = "description",
			create = function(element)
				local text = self:ResistanceDescription()
				if text == "" then
					element:SetClass("collapsed", true)
				else
					element.text = text
				end
			end,
		},


		--condition immunities.
		gui.Label{
			classes = "description",
			create = function(element)
				local text = self:ConditionImmunityDescription()
				if text == "" then
					element:SetClass("collapsed", true)
				else
					element.text = text
				end
			end,
		},


		--languages.
		gui.Label{
			classes = "description",
			create = function(element)
				local textItems = {}
				local languagesTable = dmhub.GetTable(Language.tableName) or {}
				for langid,b in pairs(self:LanguagesKnown()) do
					local lang = languagesTable[langid]
					if lang ~= nil then
						textItems[#textItems+1] = lang.name
					end
				end

				if self:try_get("customInnateLanguage") ~= nil then
					textItems[#textItems+1] = self.customInnateLanguage
				end

				local text = "None"
				if #textItems > 0 then
					text = string.join(textItems, ", ")
				end

				element.text = string.format("<b>Languages</b> %s", text)
			end,
		},

		--Challenge.
		gui.Label{
			classes = "description",
			create = function(element)
				if self:IsMonster() then
					element.text = string.format("<b>%s</b> %s", GameSystem.ChallengeName, self:PrettyCR())
				else
					element.text = string.format("<b>Level</b> %d", self:CharacterLevel())
				end
			end,
		},

		gui.Panel{
			classes = "divider",
		},

		gui.Panel{
			flow = "vertical",
			height = "auto",
			width = "100%",
			create = function(element)
				local children = {}
				for _,note in ipairs(self:try_get("notes", {})) do
					children[#children+1] = gui.Label{
						vmargin = 10,
						text = string.format("<b>%s.</b>  %s", note.title, note.text)
					}
				end

				element.children = children
			end,
		},

		actionsTitle,

		actionsPanel,

		reactionsTitle,

		reactionsPanel,

		legendaryTitle,

		legendaryPanel,

	}

	for k,v in pairs(args or {}) do
		options[k] = v
	end

	return gui.Panel(options)
end

--called by DMHub to see if this creature can block enemy movement.
--we say it can unless the creature is unconscious/dead.
function creature:CanBlockEnemyMovement()
    if self.minion then
        --minions block enemy movement -- they'll be removed anyway if they are dead.
        return true
    end
	return self:MaxHitpoints() > self.damage_taken
end


--Admin functions.
creature.AdminFunctions = {"RepairInventorySlots"}
function creature:RepairInventorySlots()
	local tok = dmhub.LookupToken(self)
	local maxslot = 0
	for k,info in pairs(self:try_get('inventory', {})) do
		for _,entry in ipairs(info.slots or {}) do
			maxslot = math.max(entry.slot, maxslot)
		end
	end
	local ncorrections = 0
	local nslots = 0
	tok:ModifyProperties{
		description = "Repair Inventory",
		execute = function()
			for k,info in pairs(self:try_get('inventory', {})) do
				for _,entry in ipairs(info.slots or {}) do
					if entry.slot == nil or entry.slot <= 0 then
						printf("Repair: Corrected slot %s -> %d", json(entry.slot), maxslot+1)
						entry.slot = maxslot+1
						maxslot = maxslot+1
						ncorrections = ncorrections+1
					end

					nslots = nslots+1

				end
			end
		end,
	}

	printf("Repair: repaired %d/%d slots", ncorrections, nslots)
end

function creature:ValidateAndRepair(localOnly)
	if not self:IsValid() then
		printf("Creature validation: Creature is invalid")
		self:Repair(localOnly)
	end
end

--detects if there are any errors in this creature.
function creature:IsValid()
    if not self:has_key("attributes") then
        return false
    end

    if getmetatable(self.culture) == nil then
        printf("Creature validation: culture is invalid")
        return false
    end

    if not self:has_key("skillProficiencies") then
        print("Creature validation: skillProficiencies is invalid")
        return false
    end

	local remoteInvokes = self:try_get("remoteInvokes")
    if remoteInvokes ~= nil and getmetatable(remoteInvokes[1]) == nil then
        printf("Creature validation: remoteInvokes is invalid")
        return false
    end

	for i,feature in ipairs(self:try_get('characterFeatures', {})) do
		if CharacterFeature.IsValid(feature) == false then
			printf("Creature validation: invalid feature in creature")
			return false
		end
	end

	local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
	for i,ongoingEffectInstance in ipairs(self:try_get("ongoingEffects", {})) do
		if getmetatable(ongoingEffectInstance) == nil or ongoingEffectsTable[ongoingEffectInstance.ongoingEffectid] == nil then
			return false
		end
	end

	for _,resistanceEntry in ipairs(self:try_get("resistances", {})) do
		if getmetatable(resistanceEntry) == nil then
			return false
		end
	end

	for k,info in pairs(self:try_get('inventory', {})) do
		if type(info) ~= "table" or type(info.quantity) ~= "number" then
			return false
		end
	end

	for _,ability in ipairs(self:try_get("innateActivatedAbilities", {})) do
		if type(ability) ~= "table" or getmetatable(ability) == nil then
			return false
		end
	end

	for k,resource in pairs(self:try_get("resources", {})) do
		if type(resource) ~= "table" or getmetatable(resource) == nil then
			return false
		end
	end

    for _,aura in ipairs(self:try_get("auras", {})) do
        if type(aura) ~= "table" or getmetatable(aura) == nil then
            return false
        end
    end

    for k,trigger in pairs(self:try_get("availableTriggers", {})) do
        if type(trigger) ~= "table" or getmetatable(trigger) == nil then
            return false
        end
    end

	local triggeredEvents = self:try_get("triggeredEvents")
    if triggeredEvents ~= nil and #triggeredEvents > 0 and triggeredEvents[1] == nil then
        --this has happened sometimes, so we repair it in this case.
        return false
    end

	if self:try_get("complicationid") ~= nil then
		return false
	end

	for i, k in pairs(self:GetFollowers()) do
		if k ~= true then
			return false
		end
	end

	return true
end

function creature:Repair(localOnly)
	local tok = nil
	local charid = "none"
	if not localOnly then
		tok = dmhub.LookupToken(self)
		if tok ~= nil then
			charid = tok.charid
			printf("Creature validation: repairing creature %s", tok.charid)
			tok:BeginChanges()
		else
			printf("Creature validation: cannot find token for creature.")
		end
	end

    --reset culture.
    if getmetatable(self.culture) == nil then
        printf("Creature validation: culture is invalid, resetting.")
        self.culture = nil
    end

    --check there are attributes
    if not self:has_key("attributes") then
        printf("Creature validation: attributes missing, resetting.")
        self.attributes = {}
    end

    if not self:has_key("skillProficiencies") then
        print("Creature validation: repair skill proficiencies")
        self.skillProficiencies = {}
    end

	local remoteInvokes = self:try_get("remoteInvokes")
    while remoteInvokes ~= nil and getmetatable(remoteInvokes[1]) == nil do
        table.remove(remoteInvokes, 1)
        if #remoteInvokes == 0 then
            remoteInvokes = nil
            self.removeInvokes = nil
        end
    end

	--remove any character features that are invalid.
	local deleteList = {}
	for i,feature in ipairs(self:try_get('characterFeatures', {})) do
		if CharacterFeature.IsValid(feature) == false then
			deleteList[#deleteList+1] = i
		end
	end

	for i=#deleteList,1,-1 do
		printf("Creature validation: removing invalid feature from character %s", charid)
		table.remove(self.characterFeatures, deleteList[i])
	end

	deleteList = {}
	local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
	for i,ongoingEffectInstance in ipairs(self:try_get("ongoingEffects", {})) do
		if getmetatable(ongoingEffectInstance) == nil or ongoingEffectsTable[ongoingEffectInstance.ongoingEffectid] == nil then
			deleteList[#deleteList+1] = i
		end
	end

	for i=#deleteList,1,-1 do
		printf("Creature validation: removing invalid ongoing effect from character %s", charid)
		table.remove(self.ongoingEffects, deleteList[i])
	end

	deleteList = {}

	for i,resistanceEntry in ipairs(self:try_get("resistances", {})) do
		if getmetatable(resistanceEntry) == nil then
			if type(resistanceEntry) == "table" then
				printf("Creature validation: repair resistance for %s by adding ResistanceEntry for character %s", json(resistanceEntry), charid)
				self.resistances[i] = ResistanceEntry.new(resistanceEntry)
			else
				--unrecognized resistances, just dump them.
				printf("Creature validation: invalid resistances for %s, puring them.", charid)
				self.resistances = {}
			end
		end
	end

	deleteList = {}

	for _,ability in ipairs(self:try_get("innateActivatedAbilities", {})) do
		if type(ability) ~= "table" or getmetatable(ability) == nil then
			printf("Creature validation: repair innate ability for %s by removing it.", charid)
			deleteList[#deleteList+1] = ability
		end
	end

	for _,ability in ipairs(deleteList) do
		self:RemoveInnateActivatedAbility(ability)
	end

	deleteList = {}

	for k,info in pairs(self:try_get('inventory', {})) do
		if type(info) ~= "table" then
			deleteList[#deleteList+1] = k
		elseif type(info.quantity) ~= "number" then
			printf("Creature validation: repair quantity entry for inventory: set character %s itemid %s to 1 quantity.", charid, k)
			info.quantity = 1
		end
	end

	for _,itemid in ipairs(deleteList) do
		printf("Creature validation: remove character %s itemid %s due to corrupt entry.", charid, k)
		self.inventory[itemid] = nil
	end

	deleteList = {}
	for k,info in pairs(self:try_get("resources", {})) do
		if type(info) ~= "table" or getmetatable(info) == nil then
			printf("Creature validation: repair resource for %s by removing it.", k)
			deleteList[#deleteList+1] = k
		end
	end

	for _,key in ipairs(deleteList) do
		self.resources[key] = nil
	end

    deleteList = {}
    for i,aura in ipairs(self:try_get("auras", {})) do
        if type(aura) ~= "table" or getmetatable(aura) == nil then
            deleteList[#deleteList+1] = i
        end
    end

    for i=#deleteList,1,-1 do
        printf("Creature validation: removing invalid aura from character %s", charid)
        table.remove(self.auras, deleteList[i])
    end

    deleteList = {}
    for k,trigger in pairs(self:try_get("availableTriggers", {})) do
        if type(trigger) ~= "table" or getmetatable(trigger) == nil then
            deleteList[#deleteList+1] = k
        end
    end

    for _,key in ipairs(deleteList) do
        self.availableTriggers[key] = nil
    end

	local triggeredEvents = self:try_get("triggeredEvents")
    if triggeredEvents ~= nil and #triggeredEvents > 0 and triggeredEvents[1] == nil then
        self.triggeredEvents = nil
    end

	if self:try_get("complicationid") ~= nil then
		printf("Creature validation: repairing complicationid on character %s", charid)
		self:AddComplication(self.complicationid)
		self.complicationid = nil
	end

	for i, k in pairs(self:GetFollowers()) do
		if k ~= true then
			local followerToken = k.followerToken
			if followerToken == nil then
				followerToken = k.retainerToken
			end

			if followerToken then
				-- Add the follower using the new structure
				self:AddFollowerToMentor(followerToken)
				-- Remove the old entry
				self.followers[i] = nil
			else
				-- No valid token found, attempt to create a follower token
				if tok == nil then
					tok = dmhub.LookupToken(self)
					if tok then
						tok:ModifyProperties{
							description = "Translate followers",
							undoable = false,
							execute = function()
								CreateFollowerMonster(k, k.type, tok)
							end,
						}
					end
				else
					CreateFollowerMonster(k, k.type, tok)
				end
				self.followers[i] = nil
			end
		end
	end

	if tok ~= nil then
		tok:CompleteChanges("Repair character")
	end
end

function creature:CalculateCustomVision(visionInfo)
	local baseValue = visionInfo.defaultValue
	local overrides = self:try_get("customVision")
	if overrides ~= nil and overrides[visionInfo.id] ~= nil then
		baseValue = overrides[visionInfo.id]
	end

	local result = self:CalculateAttribute(visionInfo.id, baseValue)
	return result
end

function creature:HasNamedCondition(conditionName)
    conditionName = string.lower(conditionName)
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
    for condid,condition in unhidden_pairs(conditionsTable) do
        if string.lower(condition.name) == conditionName and self:HasCondition(condid) then
            return true
        end
    end

    return false
end

--if the creature has a condition with a known caster, returns the id of the caster.
--otherwise returns true if the creature has the condition, or false otherwise.
---@param conditionid string
---@return boolean|string
function creature:HasCondition(conditionid)

    local inflictedConditions = self:try_get("inflictedConditions")
    if inflictedConditions ~= nil then
        local info = inflictedConditions[conditionid]
        if info ~= nil then
            if info.casterInfo ~= nil then
                return info.casterInfo.tokenid or true
            else
                return true
            end
        end
    end

	local seqFound = -1
	local result = false

	local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
	local ongoingEffects = self:ActiveOngoingEffects()
	local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
	for i,effectInfo in ipairs(ongoingEffects) do
		if effectInfo.seq > seqFound then
			local ongoingEffectInfo = ongoingEffectsTable[effectInfo.ongoingEffectid]
            if ongoingEffectInfo.condition == conditionid then
                local casterInfo = effectInfo:try_get("casterInfo")
				seqFound = effectInfo.seq
                result = (casterInfo and casterInfo.tokenid) or true
            end
		end
	end

    return result

end

local function ScoreTokenSeniority(token)
    if token.properties.minion then
        return 0
    end

    if token.properties:IsMonster() then
        return 1
    end

    local level = token.properties:Level()

    if token.primaryCharacter then
        return level + 1000
    end

    return level
end

--- returns the most 'senior' from a list of tokens.
--- @param tokens CharacterToken[]
--- @return CharacterToken
function creature.GetSeniorToken(tokens)
    if tokens == nil or #tokens == 0 then
        return nil
    end

    local senior = tokens[1]
    local seniorScore = ScoreTokenSeniority(senior)
    for i=2,#tokens do
        local score = ScoreTokenSeniority(tokens[i])
        if score > seniorScore then
            senior = tokens[i]
            seniorScore = score
        end
    end

    return senior
end

function creature:IsMonster()
    return false
end

function monster:IsMonster()
    return true
end
