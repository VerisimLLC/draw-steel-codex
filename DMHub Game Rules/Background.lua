local mod = dmhub.GetModLoading()

--- @class Background
--- @field tableName string Data table name ("backgrounds").
--- @field name string Display name.
--- @field description string Lore/description text.
--- @field portraitid string Portrait asset id, or "" if unset.
--- @field modifierInfo nil|ClassLevel ClassLevel storing modifiers and features for this background.
Background = RegisterGameType("Background")

Background.tableName = "backgrounds"

Background.name = "New Background"
Background.description = ""
Background.portraitid = ""

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\DSCareer.lua:17
function Background.CreateNew()
	return Background.new{
	}
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\DSCareer.lua:23
function Background:Describe()
	return self.name
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\DSCareer.lua:30
function Background:FillClassFeatures(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do

		if feature.typeName == 'CharacterFeature' then
			result[#result+1] = feature
		else
			feature:FillChoice(choices, result)
		end
	end
end
--]==]

--result is filled with a list of { background = Background object, feature = CharacterFeature or CharacterChoice }
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\DSCareer.lua:45
function Background:FillFeatureDetails(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do
		local resultFeatures = {}
		feature:FillFeaturesRecursive(choices, resultFeatures)

		for i,resultFeature in ipairs(resultFeatures) do
			result[#result+1] = {
				background = self,
				feature = resultFeature,
			}
		end
	end
	
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\DSCareer.lua:61
function Background:FeatureSourceName()
	return string.format("%s Background Feature", self.name)
end
--]==]

--this is where a background stores its modifiers etc, which are very similar to what a class gets.
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\DSCareer.lua:68
function Background:GetClassLevel()
	if self:try_get("modifierInfo") == nil then
		self.modifierInfo = ClassLevel:CreateNew()
	end

	return self.modifierInfo
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\DSCareer.lua:77
function Background.GetDropdownList()
	local result = {
		{
			id = 'none',
			text = 'Choose...',
		}
	}
	local backgroundsTable = dmhub.GetTable(Background.tableName)
	for k,v in pairs(backgroundsTable) do
		result[#result+1] = { id = k, text = v.name }
	end
	table.sort(result, function(a,b)
		return a.text < b.text
	end)
	return result
end
--]==]
