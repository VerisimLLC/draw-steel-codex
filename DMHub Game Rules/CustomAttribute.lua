local mod = dmhub.GetModLoading()


--- @class CustomAttribute
--- @field name string Display name of the attribute.
--- @field tableName string Data table name ("customAttributes").
--- @field attributeType string Value type: "number", "string", or "creatureSet".
--- @field category string UI category label (e.g. "Custom").
--- @field classid string Restriction to a class id, or "global" for all classes.
--- @field baseValue string|number|table GoblinScript formula for the base value.
--- @field attributeInfoByLookupSymbol table<string, CustomAttribute> Lookup map by normalized symbol name.
CustomAttribute = RegisterGameType("CustomAttribute")

CustomAttribute.tableName = "customAttributes"
CustomAttribute.attributeType = "number"
CustomAttribute.category = "Custom"
CustomAttribute.classid = "global"
CustomAttribute.baseValue = ""
CustomAttribute.attributeInfoByLookupSymbol = {}

--- @return string[]
function CustomAttribute:GetPossibleStringValues()
	return self:try_get("possibleValues", {})
end

--- @param val string[]
function CustomAttribute:SetPossibleStringValues(val)
	self.possibleValues = val
end

--- @param val string
--- @return boolean
function CustomAttribute:HasPossibleStringValue(val)
	for _,item in ipairs(self:GetPossibleStringValues()) do
		if string.lower(item) == string.lower(val) then
			return true
		end
	end

	return false
end

--- @param val string
function CustomAttribute:RemovePossibleStringValue(val)
	local newValues = {}
	
	for _,s in ipairs(self:GetPossibleStringValues()) do
		if s ~= val then
			newValues[#newValues+1] = s
		end
	end

	self:SetPossibleStringValues(newValues)
end

--- @class AttributeType
AttributeType = RegisterGameType("AttributeType")

--- @class AttributeTypeNumber:AttributeType
AttributeTypeNumber = RegisterGameType("AttributeTypeNumber", "AttributeType")

--- @class AttributeTypeStringSet:AttributeType
AttributeTypeStringSet = RegisterGameType("AttributeTypeStringSet", "AttributeType")

--- @class AttributeTypeCreatureSet:AttributeType
AttributeTypeCreatureSet = RegisterGameType("AttributeTypeCreatureSet", "AttributeType")

--- @class CreatureSet
--- @field creatures string[] List of token ids in this set.
CreatureSet = RegisterGameType("CreatureSet")
CreatureSet.creatures = {}
CreatureSet.helpSymbols = {}

--- Removes all creatures from the set.
function CreatureSet:Clear()
    self.creatures = {}
end

--- Adds a creature (by token id) to the set. Returns true if added, false if already present.
--- @param creature creature|string
--- @return boolean
function CreatureSet:Add(creature)
    local id = dmhub.LookupTokenId(creature)
    if id == nil then
        return false
    end

    if #self.creatures == 0 then
        self.creatures = {}
    end

    if table.contains(self.creatures, id) then
        return false
    end

    self.creatures[#self.creatures+1] = id
    return true
end

--interrogated by GoblinScript to provide an iterable sequence.
function CreatureSet:GoblinScriptSequence()
    return self.creatures
end

--- Returns true if the creature (or token id) is in this set.
--- @param creature creature|string|fun(): string
--- @return boolean
function CreatureSet:Has(creature)
    if type(creature) == "function" then
        creature = creature("self")
    end
    for _,val in ipairs(self.creatures) do
        if val == creature then
            return true
        end
    end

    return false
end

CreatureSet.lookupSymbols = {
	debuginfo = function(c)
		return string.format("{%d creatures}", #c.creatures)
	end,
    size = function(c)
        return #c.creatures
    end,
    __is__ = function(c)
        return function(other)
            if type(other) == "function" then
                other = other("self")
            end

            if type(other) == "table" then
                local tokenid = dmhub.LookupTokenId(other)
                if tokenid == nil then
                    return false
                end

                return c:Has(tokenid)
            end

            return false
        end
    end,
}

RegisterGoblinScriptSymbol(CreatureSet, {
    name = "Highest",
    type = "number",
    desc = "Find the highest attribute of any creature in the set.",
    examples = {"set.Highest('Recovery Value')", "set.Highest('Might')"},
    calculate = function(c)
        return function(s)
            local result = nil

            for _,creatureid in ipairs(c.creatures) do
                local cr = dmhub.GetTokenById(creatureid)
                if cr ~= nil then
                    local val = ExecuteGoblinScript(s, GenerateSymbols(cr.properties), 0, "CreatureSet:Highest")
                    if result == nil or val > result then
                        result = val
                    end
                end
            end

            return result or 0
        end
    end,
})

--- @class StringSet
--- @field strings string[] The strings in this set.
StringSet = RegisterGameType("StringSet")
StringSet.strings = {}

--- Returns the strings list for GoblinScript iteration.
--- @return string[]
--interrogated by GoblinScript to provide an iterable sequence.
function StringSet:GoblinScriptSequence()
    return self.strings
end

--- @param s string
--- @return boolean
function StringSet:Has(s)
	for _,val in ipairs(self.strings) do
		if string.lower(val) == string.lower(s) then
			return true
		end
	end

	return false
end

function StringSet:Add(s)
	if #self.strings == 0 then
		self.strings = {}
	end

	if self:Has(s) then
		return
	end

	self.strings[#self.strings+1] = s
end

StringSet.lookupSymbols = {
	debuginfo = function(c)
		return string.format("{%s}", pretty_join_list(c.strings))
	end,

	__is__ = function(c)
		return function(other)
			if type(other) == "string" then
				for _,s in ipairs(c.strings) do
					if string.lower(s) == string.lower(other) then
						return true
					end
				end
			end

			return false
		end
	end,

    size = function(c)
        return #c.strings
    end,

}

--The default value for attributes of this type.
function AttributeType:DefaultValue()
	return 0
end

function AttributeTypeCreatureSet:DefaultValue()
	return CreatureSet.new{}
end

function AttributeTypeStringSet:DefaultValue()
	return StringSet.new{}
end

--The default modifier value is the default value to append.
function AttributeType:DefaultModifierValue()
	return 1
end

function AttributeTypeCreatureSet:DefaultModifierValue()
	return self.dropdownOptions[1].id
end

function AttributeTypeStringSet:DefaultModifierValue()
	return ""
end

function AttributeType:ApplyOperation(currentValue, mod, op)
	if op == "add" then
		return (currentValue or 0) + (mod or 0)
	elseif op == "max" then
		return math.max(currentValue or 0, mod or 0)
	elseif op == "min" then
		return math.min(currentValue or 0, mod or 0)
	elseif op == "set" then
		return mod
	else
		return currentValue
	end
end

function AttributeTypeCreatureSet:ApplyOperation(currentValue, mod, op)
	currentValue[mod] = true
	return currentValue
end

function AttributeTypeStringSet:ApplyOperation(currentValue, mod, op)
	currentValue:Add(mod)
	return currentValue
end

CustomAttribute.types = {
	{
		id = "number",
		text = "Number",
		info = AttributeTypeNumber.new{},
	},
	{
		id = "stringset",
		text = "String Set",
		info = AttributeTypeStringSet.new{},
	},
	{
		id = "creatureset",
		text = "Creature Set",
		info = AttributeTypeCreatureSet.new{},
	},
}

CustomAttribute.typeInfo = {}

for _,info in ipairs(CustomAttribute.types) do
	CustomAttribute.typeInfo[info.id] = info
end

function CustomAttribute.Create()
	return CustomAttribute.new{
		name = "New Attribute",
		id = dmhub.GenerateGuid(),
	}
end

function CustomAttribute:CalculateBaseValue(creature)
	local typeInfo = self.GetAttributeType(self.id)
	if typeInfo == nil then
		return 0
	end
	if type(self.baseValue) == "string" and trim(self.baseValue) == "" then
		return typeInfo:DefaultValue()
	end


	local result = ExecuteGoblinScript(self.baseValue, GenerateSymbols(creature), typeInfo:DefaultValue(), string.format("Calculate custom attribute %s", self.name))
    return result
end



function CustomAttribute:GenerateEditor(options)
	local resultPanel

	local children = {}

	if devmode() then
		--the category of the attribute.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'GUID:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = self.id,
				editable = false,
			},
		}
	end

	--the category of the attribute.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Category:',
			valign = 'center',
			minWidth = 100,
		},
		gui.Input{
			text = self.category,
			change = function(element)
                element.text = trim(element.text)
                if element.text == "" then
                    element.text = "Custom"
                end
				self.category = element.text
				resultPanel:FireEvent("change")
			end,
		},
	}

	--the name of the attribute.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 100,
		},
		gui.Input{
			text = self.name,
			change = function(element)
				self.name = element.text
				resultPanel:FireEvent("change")
			end,
		},
	}

	--the type of the attribute.

	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Type:',
			valign = 'center',
			minWidth = 100,
		},
		gui.Dropdown{
			width = 200,
			height = 40,
			fontSize = 20,
			options = self.types,
			idChosen = self.attributeType,
			change = function(element)
				self.attributeType = element.idChosen
				resultPanel:FireEvent("change")
				resultPanel:FireEventTree("refreshType")
			end,
		},
	}

	local classOptions = {
		{
			id = "global",
			text = "Global",
		},
	}

	local classesTable = dmhub.GetTable("classes")
	for k,classInfo in pairs(classesTable) do
		classOptions[#classOptions+1] = {
			id = k,
			text = classInfo.name,
		}
	end

	table.sort(classOptions, function(a,b)
		return a.text < b.text
	end)

	--the class for the attribute. Hidden until we fix this and make it work.
	children[#children+1] = gui.Panel{
		classes = {'formPanel', 'collapsed'},
		gui.Label{
			text = 'Class:',
			valign = 'center',
			minWidth = 100,
		},
		gui.Dropdown{
			width = 200,
			height = 40,
			fontSize = 20,
			options = classOptions,
			idChosen = self.classid,
			change = function(element)
				self.classid = element.idChosen
				resultPanel:FireEvent("change")
			end,
		},
	}

	children[#children+1] = gui.Panel{
		classes = {"formPanel", cond(self.attributeType ~= "number", "collapsed-anim")},
		refreshType = function(element)
			element:SetClass("collapsed-anim", self.attributeType ~= "number")
		end,
		gui.Label{
			text = "Base Value:",
			valign = "center",
			minWidth = 100,
		},

		gui.GoblinScriptInput{
			value = self.baseValue,
			change = function(element)
				self.baseValue = element.value
				resultPanel:FireEvent("change")
			end,
			documentation = {
				help = string.format("This GoblinScript is used to determine the base value of the %s attribute.", self.name),
				output = "number",
				subject = creature.helpSymbols,
				subjectDescription = "The creature who the attribute is being calculated for.",
				symbols = {},
			},
		}
	}

	children[#children+1] = gui.Panel{
		classes = {cond(self.attributeType ~= "stringset", "collapsed-anim")},
		flow = "vertical",
		width = 400,
		height = "auto",

		styles = {
			{
				selectors = {"optionLabel"},
				width = 300,
				height = "auto",
				fontSize = 16,
			}
		},

		data = {
			labelPanels = {}
		},

		refreshType = function(element)
			element:SetClass("collapsed-anim", self.attributeType ~= "stringset")
		end,

		create = function(element)
			element:FireEvent("refreshSet")
		end,

		refreshSet = function(element)
			if self.attributeType ~= "stringset" then
				return
			end

			local currentChildren = element.children
			local children = {}
			local labelPanels = element.data.labelPanels
			local newLabelPanels = {}

			for _,val in ipairs(self:GetPossibleStringValues()) do
				local label = labelPanels[val] or gui.Label{
					classes = {"optionLabel"},
					text = val,

					gui.DeleteItemButton{
						halign = "right",
						width = 12,
						height = 12,
						click = function(element)
							self:RemovePossibleStringValue(val)
							resultPanel:FireEventTree("refreshSet")
							resultPanel:FireEvent("change")
						end,
					}
				}

				newLabelPanels[val] = label
				children[#children+1] = label
			end

			table.sort(children, function(a,b) return a.text < b.text end)
			
			children[#children+1] = currentChildren[#currentChildren]

			element.data.labelPanels = newLabelPanels

			element.children = children
		end,

		gui.Input{
			width = 300,
			height = 22,
			fontSize = 16,
			placeholderText = "Enter possible value...",
			change = function(element)
				if element.text == "" or self:HasPossibleStringValue(element.text) then
					element.text = ""
					element.hasFocus = true
					return
				end

				local items = self:GetPossibleStringValues()
				items[#items+1] = element.text
				self:SetPossibleStringValues(items)
				resultPanel:FireEventTree("refreshSet")
				element.text = ""
				element.hasFocus = true
				resultPanel:FireEvent("change")
			end,
		}
	}

    children[#children+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Documentation:",
        },
        gui.Input{
            width = 400,
            textAlignment = "topleft",
            halign = "left",
            classes = {"formInput"},
            multiline = true,
            height = "auto",
            minHeight = 60,
            characterLimit = 512,
            text = self:try_get("documentation", ""),
            change = function(element)
                self.documentation = element.text
				resultPanel:FireEvent("change")
            end,
        },
    }

	local args = {
		width = "100%",
		height = "auto",
		flow = "vertical",
		children = children,
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)
	return resultPanel
end

AttributeType.enum = false

AttributeTypeStringSet.enum = true
AttributeTypeStringSet.dropdownOptions = {}

function AttributeTypeStringSet:GetDropdownOptions(customAttribute)
	local result = {}
	local values = customAttribute.attr:GetPossibleStringValues()
	for _,s in ipairs(values) do
		result[#result+1] = {
			id = s,
			text = s,
		}
	end

	return result
end



AttributeTypeCreatureSet.enum = true

AttributeTypeCreatureSet.monsterTypes = {}
AttributeTypeCreatureSet.monsterSubtypes = {}
AttributeTypeCreatureSet.races = {}
AttributeTypeCreatureSet.dropdownOptions = {}

function AttributeTypeCreatureSet:GetDropdownOptions(customAttribute)
	return self.dropdownOptions
end

--our list of all attributes.
CustomAttribute.modifiableAttributes = {
	{ id = "hitpoints", text = "Hitpoints", attributeType = "number", category = "Basic Attributes" },
	{ id = "armorClass", text = "Armor Class", attributeType = "number", category = "Basic Attributes" },
	{ id = "initiativeBonus", text = "Initiative Bonus", attributeType = "number", category = "Basic Attributes" },
	{ id = "proficiencyBonus", text = "Proficiency Bonus", attributeType = "number", category = "Basic Attributes" },
	{ id = "spellLevel", text = "Spell Level", attributeType = "number", category = "Spellcasting" },
	{ id = "spellcastingClasses", text = "Spellcasting Classes", attributeType = "number", category = "Spellcasting" },
	{ id = "spellsavedc", text = "Spellcasting DC", attributeType = "number", category = "Spellcasting" },
	{ id = "spellattackmod", text = "Spell Attack Modifier", attributeType = "number", category = "Spellcasting" },
	{ id = "darkvision", text = "Darkvision", attributeType = "number", category = "Senses" },
	{ id = "visionrange", text = "Vision Range", attributeType = "number", category = "Senses" },
	{ id = "speed", text = "Walking Speed", attributeType = "number", category = "Movement" },
	{ id = "swim", text = "Can Swim", attributeType = "number", category = "Movement" },
	{ id = "fly", text = "Can Fly", attributeType = "number", category = "Movement" },
	{ id = "climb", text = "Can Climb", attributeType = "number", category = "Movement" },
	{ id = "burrow", text = "Can Burrow", attributeType = "number", category = "Movement" },
	{ id = "teleport", text = "Can Teleport", attributeType = "number", category = "Movement" },
	{ id = "movementDifficulty", text = "Movement Difficulty", attributeType = "number", category = "Movement" },
	{ id = "movementMultiplier", text = "Movement Multiplier", attributeType = "number", category = "Movement" },
	{ id = "creatureSize", text = "Creature Size", attributeType = "number", category = "Basic Attributes" },
	{ id = "disguised", text = "Disguised", attributeType = "number", category = "Basic Attributes" },
}


function CustomAttribute.RegisterAttribute(attr)
	local found = false
	for i,existing in ipairs(CustomAttribute.modifiableAttributes) do
		if existing.id == attr.id then
			CustomAttribute.modifiableAttributes[i] = attr
			found = true
			break
		end
	end

	if not found then
		CustomAttribute.modifiableAttributes[#CustomAttribute.modifiableAttributes+1] = attr
	end

	CustomAttribute.attributeInfoById = {}
	for i,attr in ipairs(CustomAttribute.modifiableAttributes) do
		CustomAttribute.attributeInfoById[attr.id] = attr
	end
end

function CustomAttribute.DeregisterAttribute(attrid)
	for i,existing in ipairs(CustomAttribute.modifiableAttributes) do
		if existing.id == attrid then
            existing.hidden = true
            break
        end
    end
end

function CustomAttribute.ModifiableAttributesForDomains(domains)
	if domains == nil then
		return CustomAttribute.modifiableAttributes
	end

	local result = {}
	for _,attr in ipairs(CustomAttribute.modifiableAttributes) do
		if attr.domain == nil or domains[attr.domain] then
			result[#result+1] = attr
		end
	end

	return result
end


local initCategories = false

function CustomAttribute.LookupCustomAttributeBySymbol(attr)
    local result = CustomAttribute.attributeInfoByLookupSymbol[attr]
    if result == nil then
        print("CustomAttribute.LookupCustomAttributeBySymbol: No attribute found for " .. attr)
    end
    return result
end

dmhub.RegisterEventHandler("refreshTables", function(keys)
	printf("RefreshTables:: %s", json(keys))
	--if initCategories then --TODO: Work out when it's safe to cache.
	--	return
	--end

	local sw = dmhub.Stopwatch()

	--list out all attributes.
	for k,v in pairs(creature.attributesInfo) do
		CustomAttribute.modifiableAttributes[#CustomAttribute.modifiableAttributes+1] =
		{
			id = k,
			text = v.description,
			attributeType = "number",
			category = "Basic Attributes",
		}
	end

	VisionType.PopulateAttributes(CustomAttribute.modifiableAttributes)
	
	local attrTable = dmhub.GetTable(CustomAttribute.tableName) or {}
	for k,attr in pairs(attrTable) do
		if not attr:try_get("hidden", false) then
			local domain = nil
			if attr.classid ~= "global" then
				domain = string.format("class:%s", attr.classid)
			end
			CustomAttribute.modifiableAttributes[#CustomAttribute.modifiableAttributes+1] =
			{
				id = k,
				attr = attr,
				text = attr.name,
				attributeType = attr.attributeType,
				domain = domain,
				category = attr.category,
			}
		end
	end

    --make sure we don't have duplicate attributes.
    local modifiableAttributesSeen = {}
    local modifiableAttributesWithoutDuplicates = {}
    for i,entry in ipairs(CustomAttribute.modifiableAttributes) do
        local index = modifiableAttributesSeen[entry.id] or (#modifiableAttributesWithoutDuplicates + 1)
        modifiableAttributesSeen[entry.id] = index
        modifiableAttributesWithoutDuplicates[index] = entry
    end

    CustomAttribute.modifiableAttributes = modifiableAttributesWithoutDuplicates

	CustomAttribute.attributeInfoById = {}

	for i,attr in ipairs(CustomAttribute.modifiableAttributes) do
		CustomAttribute.attributeInfoById[attr.id] = attr
	end

	--modify creature lookup symbols.
	for k,attr in pairs(attrTable) do
		local key = attr.name
		key = string.gsub(key, "%s+", "")
		key = string.lower(key)
		local fn = function(c)
			return c:GetCustomAttribute(attr)
		end

        CustomAttribute.attributeInfoByLookupSymbol[key] = attr
        print("Registered Custom Attribute:", key, attr ~= nil)

		creature.lookupSymbols[key] = fn
		character.lookupSymbols[key] = fn
		monster.lookupSymbols[key] = fn

		local domain = nil
		if attr.classid ~= "global" then
			domain = string.format("class:%s", attr.classid)
		end

		creature.helpSymbols[key] = {
			name = attr.name,
			type = attr.attributeType,
			desc = string.format("The %s of the creature.", attr.name),
			domain = domain,
		}
	end


    if initCategories then
        print("Custom Attributes: Refresh in", sw.milliseconds)
        return
    end
	initCategories = true

    AttributeTypeCreatureSet.monsterTypes = {}
    AttributeTypeCreatureSet.monsterSubtypes = {}
    AttributeTypeCreatureSet.races = {}
    AttributeTypeCreatureSet.dropdownOptions = {}

	local bestiary = assets.monsters
	for k,monster in pairs(bestiary) do
		local properties = monster.properties
		if properties ~= nil and properties:has_key("monster_category") then
			for _,cat in ipairs(properties:GetMonsterCategoryList(true)) do
				AttributeTypeCreatureSet.monsterTypes[string.lower(cat)] = {
					text = cat,
				}

				if properties:has_key("monster_subtype") then
					AttributeTypeCreatureSet.monsterSubtypes[string.lower(properties.monster_subtype)] = {
						text = properties.monster_subtype,
						parent = string.lower(cat)
					}
				end
			end
		end
	end

	local racesTable = dmhub.GetTable(Race.tableName)
	for k,race in pairs(racesTable) do
		local raceName = string.lower(race.name)
		AttributeTypeCreatureSet.races[raceName] = {
			text = race.name,
			raceid = k
		}
	end

	for k,info in pairs(AttributeTypeCreatureSet.monsterTypes) do
		AttributeTypeCreatureSet.dropdownOptions[#AttributeTypeCreatureSet.dropdownOptions+1] = {
			id = k,
			text = info.text,
		}
	end

	for k,info in pairs(AttributeTypeCreatureSet.monsterSubtypes) do
		local monsterType = AttributeTypeCreatureSet.monsterTypes[info.parent]
		AttributeTypeCreatureSet.dropdownOptions[#AttributeTypeCreatureSet.dropdownOptions+1] = {
			id = k,
			text = string.format("%s--%s", monsterType.text, info.text),
		}
	end

	for k,race in pairs(racesTable) do
		AttributeTypeCreatureSet.dropdownOptions[#AttributeTypeCreatureSet.dropdownOptions+1] = {
			id = k,
			text = race.name,
		}
	end

	table.sort(AttributeTypeCreatureSet.dropdownOptions, function(a,b) return a.text < b.text end)



    print("Custom Attributes: Refresh in", sw.milliseconds)
end)

function CustomAttribute.GetAttributeType(attrid)
	local attrInfo = CustomAttribute.attributeInfoById[attrid]
	if attrInfo ~= nil then
		local typeInfo = CustomAttribute.typeInfo[attrInfo.attributeType]
		if typeInfo ~= nil then
			return typeInfo.info
		end
	end

	print("CustomAttribute.GetAttributeType: No attribute type found for " .. attrid)

	return nil
end

AttributeType.operationOptions = {
	{
		id = "add",
		text = "Add",
	},
	{
		id = "set",
		text = "Override",
	},
	{
		id = "max",
		text = "Override (set min value)",
	},
	{
		id = "min",
		text = "Override (set max value)",
	},
}

AttributeTypeCreatureSet.operationOptions = {
	{
		id = "add",
		text = "append",
	},
}
