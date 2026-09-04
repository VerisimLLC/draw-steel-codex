math.randomseed(os.time())

nbsp = '<color=#00000000>.</color>'

traceback = debug.traceback

tr = dmhub.tr

local tostr = tostring

if math.tointeger == nil then
	function math.tointeger(n)
		return math.floor(n)
	end
end

function tostring(s)
	if type(s) == "number" then
		local i = math.tointeger(s)
		if i ~= nil then
			return string.format("%d", i)
		end
	end

	if type(s) == "table" then
		return dmhub.TableToString(s)
	end

	return tostr(s)
end

function toint(s, defaultValue)
	local num = tonumber(s)
	if num == nil then
		return defaultValue
	end

	return math.tointeger(math.floor(num))
end

function numtostr(n, defaultValue)
	local num = tonumber(n)
	if num == nil then
		return defaultValue
	end

	if math.floor(num) == num then
		return string.format("%d", math.tointeger(num))
	end

	return tostring(num)
end

function tonum(s, defaultValue)
	local result = tonumber(s)
	if result == nil then
		if type(s) == "string" then
			local i,j = string.find(s, "^%d+")
			if i ~= nil then
				return math.tointeger(tonumber(string.sub(s, i, j)))
			end
		end

		if defaultValue == nil then
			return 0
		end
		return defaultValue 
	end

	if type(result) == "number" and result == math.floor(result) then
		result = math.floor(result)
	end

	return result
end

function shallow_copy_list(list)
	local result = {}
	for _,item in ipairs(list) do
		result[#result+1] = item
	end

	return result
end

function shallow_copy_table(t)
	local result = {}
	for k,v in pairs(t) do
		result[k] = v
	end

	return result
end

function list_contains(list, item)
	for _,listItem in ipairs(list) do
		if item == listItem then
			return true
		end
	end

	return false
end

function math.pow(a,b)
	return a^b
end

function table.union(a,b)
	local c = {}
	for k,v in pairs(a) do
		c[k] = v
	end
	for k,v in pairs(b) do
		c[k] = v
	end

	return c
end

function table.keys(t)
	if type(t) ~= "table" then
		return nil
	end

	local result = {}

	for k,v in pairs(t) do
		result[#result+1] = k
	end

	return result
end

function table.empty_or_null(t)
	if t == nil then
		return true
	end

	for k,v in pairs(t) do
		return false
	end

	return true
end

function table.empty(t)
	for k,v in pairs(t) do
		return false
	end

	return true
end

function table.size(t)
	local result = 0
	for k,v in pairs(t) do
		result = result+1
	end

	return result
end

---@param str string
---@param Start string
---@return boolean
function string.starts_with(str,Start)
   if str == nil then
        return false
   end
   return string.sub(str,1,string.len(Start))==Start
end

function string.ends_with(str, ending)
	return ending == "" or string.sub(str, -#ending) == ending
end

function string.upper_first(str)
	return (string.gsub(str, "^%l", string.upper))
end


function format_decimal(num)
	return string.gsub(string.format("%f", num), "%.?0+$", "")
end

function pretty_join_list(items)
	if #items == 0 then
		return ""
	elseif #items == 1 then
		return items[1]
	elseif #items == 2 then
		return string.format("%s and %s", items[1], items[2])
	else
		local result = items[1]
		for i=2,#items-1 do
			result = string.format("%s, %s", result, items[i])
		end

		result = string.format("%s, and %s", result, items[#items])
		return result
	end
end

allowUnsafeReads = false

function unsafe_reads(f)
	local oldValue = allowUnsafeReads
	allowUnsafeReads = true
	pcall(f)
	allowUnsafeReads = oldValue
end

local g_registerGameTypes = {}

local IsDerivedFrom
IsDerivedFrom = function(a,b)
	if a == nil or b == nil then
		return false
	end

	if a == b then
		return true
	end

	local info = g_registerGameTypes[a]
	return IsDerivedFrom(info ~= nil and info.base, b)
end

---@param typeName string
---@param baseTypeName string|nil
---@return table
function RegisterGameType(typeName, baseTypeName)

	if baseTypeName ~= nil and baseTypeName ~= typeName and g_registerGameTypes[baseTypeName] == nil then
		RegisterGameType(baseTypeName)
	end

	local existingType = nil
	if g_registerGameTypes[typeName] ~= nil then
		if g_registerGameTypes[typeName].base == baseTypeName then
			return _G[typeName]
		end
		
		existingType = _G[typeName]
	end

	local m_aliases = {}
	
	local newType = {
		new = function(o)
			o = o or {}
			setmetatable(o, _G[typeName].mt)
			return o
		end,

		has_key = function(self, key)
			if type(self) ~= 'table' then
				dmhub.Debug('TRACE:: ' .. debug.traceback())
			end
			return rawget(self, key) ~= nil
		end,

		try_get = function(self, key, defaultValue)
			local result = rawget(self, key)
			if result == nil then
				return defaultValue
			end
			return result
		end,

		get_or_add = function(self, key, defaultValue)
			local result = rawget(self, key)
			if result == nil then
				self[key] = defaultValue
				return defaultValue
			end
			return result
		end,

		TranslationStrings = function(self)
			return nil
		end,

		typeName = typeName,

		IsDerivedFrom = function(t)
			return IsDerivedFrom(typeName, t)
		end,

		AddAlias = function(a, b)
			m_aliases = m_aliases or {}
			m_aliases[a] = b
		end,
	}

	if baseTypeName ~= nil then
		local entry = g_registerGameTypes[baseTypeName]
		if entry and entry.GetAliases() then
			m_aliases = {}
			for k,v in pairs(entry.GetAliases()) do
				m_aliases[k] = v
			end
		end
	end

	if existingType ~= nil then
		for k,v in pairs(newType) do
			existingType[k] = v
		end

		newType = existingType
	end

	if baseTypeName ~= nil then
		setmetatable(newType, {
			__index = function(t, n)
				if m_aliases ~= nil then
					local alias = m_aliases[n]
					if alias ~= nil then
						return t[alias]
					end
				end

				return _G[baseTypeName][n]
			end,

			__newindex = function(t, k, v)
				if m_aliases ~= nil then
					local alias = m_aliases[k]
					if alias ~= nil then
						t[alias] = v
						return
					end
				end

				rawset(t, k, v)
			end,
		})
	else
		setmetatable(newType, {
			__index = function(t, n)
				local alias = m_aliases[n]
				if alias ~= nil then
					return t[alias]
				end

				if allowUnsafeReads then
					return nil
				else
					error("Attempt to read unknown field " .. n .. " in type " .. t.typeName .. " at " .. debug.traceback(), 2)
				end
			end,

			__newindex = function(t, k, v)
				if m_aliases ~= nil then
					local alias = m_aliases[k]
					if alias ~= nil then
						t[alias] = v
						return
					end
				end

				rawset(t, k, v)
			end,

			__tostring = function(self)
				return dmhub.TableToString(self)
			end,
		})
	end

	--this is the actual metatable that gets set on instances.
	newType.mt = {
		__index = function(t,k)
			if m_aliases ~= nil then
				local alias = m_aliases[k]
				if alias ~= nil then
					return t[alias]
				end
			end

			return newType[k]
		end,
		__newindex = function(t, k, v)
			if m_aliases ~= nil then
				local alias = m_aliases[k]
				if alias ~= nil then
					t[alias] = v
					return
				end
			end
			rawset(t, k, v)
		end,
		typeName = typeName,
		baseTypeName = baseTypeName
	}

	_G[typeName] = newType

	g_registerGameTypes[typeName] = { base = baseTypeName, GetAliases = function() return m_aliases end }
	return _G[typeName]
end

function GetRegisteredTypeDocumentation(typeName)
	if g_registerGameTypes[typeName] == nil then
		return nil
	end

	local result = {fields = {}}

	local t = _G[typeName]

	for k,v in pairs(t) do
		if string.starts_with(k, "_") == false then
			result.fields[#result.fields+1] = {
				name = k,
				type = cond(type(v) == "function", "Method", "Field"),
				typeSignature = type(v),
			}
		end
	end

	return result
end

function max(a, b)
	if a == nil or b == nil then
		dmhub.CloudError("Error in max: " .. traceback())
		if a ~= nil then
			return a
		elseif b ~= nil then
			return b
		end
	end

	if a > b then
		return a
	else
		return b
	end
end

function min(a, b)
	if a == nil or b == nil then
		dmhub.CloudError("Error in min: " .. traceback())
		if a ~= nil then
			return a
		elseif b ~= nil then
			return b
		end
	end

	if a < b then
		return a
	else
		return b
	end
end

--- @param x number
--- @param a number
--- @param b number
--- @return number
function clamp(x, a, b)

	if x < a then
		x = a
	end

	if x > b then
		x = b
	end
	return x
end

function lerp(a,b,t)
	return b*t + a*(1-t)
end

---@param n number
---@return number
function round(n)
	return math.floor(n + 0.5)
end

---@param s string
---@return string
function trim(s)
   if type(s) ~= "string" then
       return s
   end
   local a = s:match('^%s*()')
   local b = s:match('()%s*$', a)
   return s:sub(a,b-1)
end


function string.startswith(String,Start)
	return string.sub(String,1,string.len(Start)) == Start
end

function string.split (inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end


function string.join(items, sep)
	if sep == nil then
		sep = ","
	end

	local result = ""
	for i,item in ipairs(items) do
		if i ~= 1 then
			result = result .. sep
		end

		result = result .. item
	end

	return result
end


function math.sign(num)
	if num > 0 then
		return 1
	elseif num < 0 then
		return -1
	else
		return 0
	end
end

function cond(a,b,c)
	if a then
		return b
	else
		return c
	end
end

function ServerTimestamp()
	return "__serverTimestamp"
end

function TimestampAgeInSeconds(timestamp)
	if type(timestamp) ~= "number" then
		--still local, so just happened.
		return 0
	end
	return (dmhub.serverTimeMilliseconds - timestamp)*0.001
end

function DescribeSecondsAgo(secondsAgo)
	if secondsAgo < 6 then
		return "just now"
	elseif secondsAgo < 15 then
		return "a few seconds ago"
	elseif secondsAgo < 40 then
		return "seconds ago"
	elseif secondsAgo < 90 then
		return "a minute ago"
	elseif secondsAgo < 280 then
		return "a few minutes ago"
	elseif secondsAgo < 55*60 then
		local minutes = round(secondsAgo/60)
		return string.format("%d minutes ago", minutes)
	elseif secondsAgo < 90*60 then
		return "an hour ago"
	elseif secondsAgo < 60*60*24 then
		local hours = round(secondsAgo/(60*60))
		return string.format("%d hours ago", hours)
	elseif secondsAgo < 2*60*60*24 then
		return "a day ago"
	else
		local days = round(secondsAgo/(60*60*24))
		return string.format("%d days ago", days)
	end
end

function DescribeServerTimestamp(timestamp)
	if type(timestamp) == "number" then
		local secondsAgo = TimestampAgeInSeconds(timestamp)
		return DescribeSecondsAgo(secondsAgo)
	end

	return "pending"
end

function sRGBToLinear(value)
	if value <= 0.04045 then
		return value/12.92
	else
		return ((value + 0.055)/1.055)^2.4
	end
end

function LinearTosRGB(value)
	if value < 0.0031308 then
		return value*12.92
	else
		return 1.055*(value^(1/2.4)) - 0.055
	end
end

DeepCopy = dmhub.DeepCopy

TokenTypes = {}

DataTables = {}

function devmode()
	return dmhub.GetSettingValue('dev')
end

function json(obj)
	return dmhub.ToJson(obj)
end

function dbg(str, obj)
	dmhub.Debug(string.format("%s: %s", str, dmhub.ToJson(obj)))
end

function printf(str, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q)
	dmhub.Debug(string.format(str, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q))
end

function print(...)
	local args = {...}

	local result = ""
	for i,a in ipairs(args) do
		if type(a) == "string" then
			result = result .. a .. " "
		else
			result = result .. tostring(a) .. " "
		end
	end

	dmhub.Debug(result)
end

print(4, 5, 6)

function GetDropdownEnumById(enum)
	local result = {}
	for i,item in ipairs(enum) do
		result[item.id] = item
	end
	return result
end

--Use CreateTable to create a table which has a basic metatable set on it.
--This is useful to force it to be networked as a table, not an array and patched nicely.
local genericTableMeta = {
	typeName = "_gentable"
}
_G[genericTableMeta.typeName] = { mt = genericTableMeta }
function CreateTable(args)
	local result = {}
	setmetatable(result, genericTableMeta)
	if args ~= nil then
		for k,v in pairs(args) do
			result[k] = v
		end
	end
	return result
end

setmetatable(_G, {
	__index = function(_, n)
		if dmhub.protectedCode then
			error("Attempt to read uninitialized variable "..n, 2)
		end

		return nil
	end,
})

function GoblinScriptTrue(val)
	if val and val ~= 0 then
		return true
	else
		return false
	end
end

local function unpack_with_nil(t, i)
	i = i or 1
	if i <= #t then
		if t[i] == dmhub.PlaceholderNil then
			return nil, unpack_with_nil(t, i+1)
		else
			return t[i], unpack_with_nil(t, i+1)
		end
	end
end

--this is a wrapper for use with CharacterToken.ModifyProperties to 
--allow it to be called while any synchronous coroutine calls are saved up
--and then executed synchronously.
function ModifyTokenProperties(token, options)
	if token == nil or not token.valid then
		return
	end

	if dmhub.inCoroutine then
		dmhub.PushNativeCCallCoroutineContext()
	end

	token:ModifyPropertiesInternal(options)

	--now executed any synchronous coroutines that were called while we
	--were modifying the token properties.
	if dmhub.inCoroutine then
		local context = dmhub.PopNativeCCallCoroutineContext()
		if context ~= nil then
			while #context > 0 do
				local entry = context[1]
				table.remove(context, 1)
				entry[1](unpack_with_nil(entry[2]))
			end
		end
	end
end


--core types.

--RegisterGameType("GoblinScriptTable")
--RegisterGameType("SpellcastingFeature")

--RegisterGameType("DamageType")
--RegisterGameType("DamageFlag")

--RegisterGameType("Faction") --DEPRECATED
--Faction.name = "none"
--Faction.id = "id"

--RegisterGameType("Light")


--RegisterGameType("CustomAttribute")

--RegisterGameType("AttributeType")
--RegisterGameType("AttributeTypeNumber", "AttributeType")
--RegisterGameType("AttributeTypeCreatureSet", "AttributeType")

--RegisterGameType("CreatureSet")

--RegisterGameType("StringSet")

--RegisterGameType("ResistanceEntry")
--RegisterGameType("DamageInstance")
--RegisterGameType("AttackDefinition")

--RegisterGameType("CharacterModifier")

--RegisterGameType("CharacterPrerequisite")
--RegisterGameType("CharacterResource")

--RegisterGameType("CharacterFeature")

--RegisterGameType("Party")
--RegisterGameType("Currency")
--RegisterGameType("CharacterCondition", "CharacterFeature")
--RegisterGameType("CharacterFeat")
--RegisterGameType("CharacterTemplate", "CharacterFeat")
--RegisterGameType("CharacterFeaturePrefabs")
--RegisterGameType("CharacterType")
--RegisterGameType("GlobalRuleMod")
--RegisterGameType("Aura", "CharacterFeature")
--RegisterGameType("Background")
--RegisterGameType("CharacterOngoingEffect", "CharacterFeature")

--RegisterGameType("Class")
--RegisterGameType("ClassLevel") --type which represents the benefits a character gets at a specific level.
--RegisterGameType("CharacterChoice")
--RegisterGameType("CharacterFeatureChoice", "CharacterChoice")
--RegisterGameType("CharacterSubclassChoice", "CharacterChoice")
--RegisterGameType("CharacterFeatChoice", "CharacterChoice")
--RegisterGameType("CharacterFeatureList")

--RegisterGameType("Race")


--RegisterGameType("ActivatedAbility")
--RegisterGameType("AttackTriggeredAbility", "ActivatedAbility")
--RegisterGameType("TriggeredAbility", "ActivatedAbility")


--RegisterGameType("ActivatedAbilityBehavior")
--RegisterGameType("ActivatedAbilityAttackBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityDamageBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityHealBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityAugmentedAbilityBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityApplyOngoingEffectBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityRemoveOngoingEffectBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityAuraBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityMoveAuraBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilitySummonBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityTransformBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityDestroyBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityContestedAttackBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityForcedMovementBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityModifiersBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityRemoveCreatureBehavior", "ActivatedAbilityBehavior")

RegisterGameType("ActivatedAbilityPurgeEffectsBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityRelocateCreatureBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityDropItemsBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityExpendResourceBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityRestoreResourceBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityConsumeItemBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityCreateItemBehavior", "ActivatedAbilityBehavior")

RegisterGameType("ActivatedAbilitySavingThrowBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityFizzleBehavior", "ActivatedAbilityBehavior")
RegisterGameType("ActivatedAbilityRollTableBehavior", "ActivatedAbilityBehavior")

RegisterGameType("BackgroundCharacteristic")



RegisterGameType("ActivatedAbilityApplyMomentaryEffectBehavior", "ActivatedAbilityBehavior")

RegisterGameType("Spell", "ActivatedAbility")

RegisterGameType("SpellList")


RegisterGameType("Theme")

RegisterGameType("loot")

RegisterGameType("equipment")

RegisterGameType("weapon", "equipment")
RegisterGameType("armor", "equipment")
RegisterGameType("shield", "equipment")

RegisterGameType("EquipmentCategory")

RegisterGameType("StatHistory")

RegisterGameType("CharacterAttribute")


RegisterGameType("creature")
RegisterGameType("monster", "creature")

RegisterGameType("character", "creature")

RegisterGameType("Skill")
RegisterGameType("SkillSpecialization")

RegisterGameType("Language")

RegisterGameType("Variant")
RegisterGameType("VariantCollection")
RegisterGameType("RollTable")
RegisterGameType("RollTableRow")

RegisterGameType("AttributeGenerator")
