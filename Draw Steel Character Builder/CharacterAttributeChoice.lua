--[[
    CharacterCharacteristicChoice

    Make the baseAttributes selection behave like a
    feature choice for purposes of the character builder.
]]
CharacterCharacteristicChoice = RegisterGameType("CharacterCharacteristicChoice", "CharacterChoice")
CharacterCharacteristicChoice.__index = CharacterCharacteristicChoice

-- It's not configurable; there's always only one for the hero
CharacterCharacteristicChoice.guid = "7f3c8a2e-5b14-4d9a-9e61-3c7f2a8b5d4e"

--- Construct from a hero
--- @param classItem Class
--- @return CharacterCharacteristicChoice
function CharacterCharacteristicChoice:new(classItem)
    local instance = setmetatable({}, self)

    local function formatArrayLabel(array)
        table.sort(array, function(a,b) return b < a end)
        return table.concat(array, ", ")
    end

    local baseChars, description = CharacterCharacteristicChoice._getBaseCharacteristics(classItem)

    instance.guid = classItem.id
    instance.name = "Characteristics"
    instance.description = "Base Characteristics"
    instance.numChoices = 1
    instance.costsPoints = false
    instance.hasRoll = false
    instance.baseChars = baseChars
    instance.description = description or "Choose your Starting Characteristics."
    instance.options = {}
    instance.choices = {}

    if baseChars then
        local options = {}

        for i,array in ipairs(baseChars.arrays) do
            local guid = dmhub.GenerateGuid()
            local name = formatArrayLabel(array)
            local sum = 0
            for _,v in ipairs(array) do
                sum = sum + v
            end
            local order = CharacterBuilder._formatOrder(sum, name)
            options[#options+1] = {
                guid = guid,
                name = name,
                unique = true,
                arrayIndex = i,
                order = order,
            }
        end
        local choices = {}
        table.sort(options, function(a,b) return b.order < a.order end)
        for i,item in ipairs(options) do
            item.order = CharacterBuilder._formatOrder(i, item.name)
            choices[#choices+1] = {
                id = item.guid,
                text = item.name,
                unique = true,
                arrayIndex = item.arrayIndex,
                order = item.order,
            }
        end

        instance.options = options
        instance.choices = choices
    end

    return instance
end

function CharacterCharacteristicChoice:CanRepeat()
    return false
end

function CharacterCharacteristicChoice:Choices()
    return self.choices or {}
end

function CharacterCharacteristicChoice:GetDescription()
    return self.description
end

function CharacterCharacteristicChoice:GetOptions()
    return self.options or {}
end

function CharacterCharacteristicChoice:NumChoices()
    return self:try_get("numChoices", 1)
end

--- The panel(s) to inject into the feature builder
--- @return table
function CharacterCharacteristicChoice:UIInjections()
    return {
        afterHeader = CBClassDetail._characteristicPanel,
    }
end

function CharacterCharacteristicChoice:VisitRecursive(fn)
    fn(self)
    for _,o in ipairs(self:GetOptions()) do
        fn(o)
    end
end

function CharacterCharacteristicChoice._getBaseCharacteristics(classItem)
    local baseChars = classItem.baseCharacteristics
    local description = baseChars and CharacterBuilder._parseStartingCharacteristics(baseChars) or CharacterCharacteristicChoice.description
    return baseChars, description
end

--- Save the selected option to the hero, setting the attributeBuild
--- property and the base values for each attribute.
--- @param hero character
--- @param option table
--- @return boolean haltSavePropagation
function CharacterCharacteristicChoice:SaveSelection(hero, option)

    local classItem = hero:GetClass()
    if classItem == nil then return true end

    local attrInfo = creature.attributesInfo
    local baseChars = CharacterCharacteristicChoice._getBaseCharacteristics(classItem)
    if baseChars == nil then return true end

    local scoreArray = baseChars.arrays[option.arrayIndex]
    local attributeBuild = { array = option.arrayIndex }
    local attrs = {}
    local nextIndex = 1
    for _,attr in pairs(attrInfo) do
        if baseChars[attr.id] ~= nil then
            attrs[attr.id] = baseChars[attr.id]
        else
            attrs[attr.id] = scoreArray[nextIndex]
            attributeBuild[attr.id] = nextIndex
            nextIndex = nextIndex + 1
        end
    end

    hero.attributeBuild = attributeBuild
    local heroAttrs = hero:try_get("attributes")
    if heroAttrs then
        for k,v in pairs(attrs) do
            heroAttrs[k].baseValue = v
        end
    end

    return true
end

--- Remove the selection from the hero, clearing the
--- attributeBuild property and setting the base
--- attribute values to the defaults for the class.
--- @param hero character
--- @param option table
--- @return boolean haltSavePropagation
function CharacterCharacteristicChoice:RemoveSelection(hero, option)

    hero.attributeBuild = {}

    local classItem = hero:GetClass()
    if classItem == nil then return true end
    local heroAttrs = hero:try_get("attributes")
    local baseChars = CharacterCharacteristicChoice._getBaseCharacteristics(classItem)
    if heroAttrs and baseChars then
        for k,v in pairs(heroAttrs) do
            v.baseValue = self.baseChars[k] or 0
        end
    end

    return true
end

--- Return the currently selected option, if there is one
--- @param hero character
--- @return table selected List of option guids
function CharacterCharacteristicChoice:GetSelected(hero)
    local selected = {}

    local attrBuild = hero:try_get("attributeBuild", {})
    local arrayIndex = attrBuild and attrBuild.array
    if arrayIndex ~= nil then
        for _,option in ipairs(self:GetOptions()) do
            if option.arrayIndex == arrayIndex then
                selected[#selected+1] = option.guid
                break
            end
        end
    end

    return selected
end