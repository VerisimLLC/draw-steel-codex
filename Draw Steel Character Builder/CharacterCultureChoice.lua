--[[
    CharacterAspectChoice

    Make a Culture Aspect choice behave like a feature choice
    for purposes of the character builder.
]]
CharacterAspectChoice = RegisterGameType("CharacterAspectChoice", "CharacterChoice")

CharacterAspectChoice.description = "Culture Aspect Choice"
CharacterAspectChoice.numChoices = 1
CharacterAspectChoice.costsPoints = false
CharacterAspectChoice.hasRoll = false

function CharacterAspectChoice.CreateNew(aspect)
    local options, choices = CharacterAspectChoice._optionsAndChoices(aspect.id)

    return CharacterAspectChoice.new{
        guid = aspect.id,
        name = aspect.text,
        description = aspect.description,
        options = options,
        choices = choices,
    }
end

function CharacterAspectChoice.CreateAll()
    local items = {}
    for _,aspect in ipairs(CultureAspect.categories) do
        items[#items+1] = { feature = CharacterAspectChoice.CreateNew(aspect) }
    end
    return items
end

function CharacterAspectChoice:CanRepeat()
    return false
end

function CharacterAspectChoice:Choices()
    return self.choices or {}
end

function CharacterAspectChoice:GetDescription()
    return self.description
end

function CharacterAspectChoice:GetOptions()
    return self.options or {}
end

function CharacterAspectChoice:GetSelected(hero)
    local selected = {}

    local culture = hero:GetCulture()
    if culture then
        local aspects = culture:try_get("aspects", {})
        selected[#selected+1] =  aspects[self.guid] or ""
    end

    return selected
end

function CharacterAspectChoice:NumChoices()
    return self:try_get("numChoices", 1)
end

function CharacterAspectChoice:RemoveSelection(hero, option)
    local culture = hero:GetCulture()
    if culture then
        local aspects = culture:try_get("aspects")
        if aspects then
            aspects[self.guid] = ""
        end
    end
end

--- Save the selected option to the hero.
--- @param hero character
--- @param option table
--- @return boolean haltSavePropagation
function CharacterAspectChoice:SaveSelection(hero, option)
    local culture = hero:try_get("culture")
    if culture == nil then
        culture = Culture.CreateNew()
        hero.culture = culture
    end
    culture.aspects[self.guid] = option.id
    return true
end

function CharacterAspectChoice._optionsAndChoices(aspectId)
    local options = {}
    local choices = {}

    for id,item in pairs(dmhub.GetTableVisible(CultureAspect.tableName)) do
        if item.category == aspectId then
            options[#options+1] = {
                guid = id,
                name = item.name,
                description = item.description,
                unique = true,
            }
            choices[#choices+1] = {
                id = id,
                text = item.name,
                description = item.description,
                unique = true,
            }
        end
    end
    table.sort(options, function(a,b) return a.name < b.name end)
    table.sort(choices, function(a,b) return a.text < b.text end)

    return options, choices
end
