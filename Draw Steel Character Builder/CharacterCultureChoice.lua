--[[
    CharacterAspectChoice

    Make a Culture Aspect choice behave like a feature choice
    for purposes of the character builder.

    CharacterCultureAggregateChoice

    Make a Culture Aggreate choice behave like a feature choice
    for purposes of the character builder.
]]
CharacterAspectChoice = RegisterGameType("CharacterAspectChoice", "CharacterChoice")
CharacterCultureAggregateChoice = RegisterGameType("CharacterCultureAggregateChoice", "CharacterChoice")

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

--- Populate all the culture choices
--- @param hero character
--- @return table
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
    return true
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

--- Create the aggregate choices as feature selections
--- @param hero character
--- @return table features
function CharacterCultureAggregateChoice.CreateAll(hero)

    local culture = hero:try_get("culture")
    if culture == nil then
        hero.culture = Culture.CreateNew()
        culture = hero:try_get("culture")
    end
    if culture and culture.aspects then
        local aspects = culture.aspects
        if aspects.environment ~= nil and #aspects.environment > 0 then return {} end
        if aspects.organization ~= nil and #aspects.organization > 0 then return {} end
        if aspects.upbringing ~= nil and #aspects.upbringing > 0 then return {} end
    end

    culture.aggregate = ""

    -- Split the items in the Culture table up by group
    local items = {}
    local cultureAggregates = dmhub.GetTableVisible(Culture.tableName)
    for id,item in pairs(cultureAggregates) do
        local group = item:try_get("group")
        if group then
            if items[group] == nil then
                items[group] = {}
            end
            items[group][#items[group]+1] = item
        end
    end

    -- For each group, create a new choice item
    local features = {}
    for _,item in pairs(items) do
        features[#features+1] = { feature = CharacterCultureAggregateChoice.CreateNew(item) }
    end

    return features
end

function CharacterCultureAggregateChoice.CreateNew(items)
    local group = items[1].group

    local options = {}
    local choices = {}
    for _,item in ipairs(items) do
        options[#options+1] = {
            guid = item.id,
            name = item.name,
            description = nil,
            unique = true,
            aspects = item.aspects,
        }
        choices[#choices+1] = {
            id = item.id,
            text = item.name,
            description = nil,
            unique = true,
            aspects = item.aspects
        }
    end
    table.sort(options, function(a,b) return a.name < b.name end)
    table.sort(choices, function(a,b) return a.text < b.text end)

    return CharacterCultureAggregateChoice.new{
        guid = "CULTURE-" .. group,
        name = group,
        options = options,
        choices = choices,
        numChoices = 1,
        numSelected = 0,
        selected = {},
    }
end

function CharacterCultureAggregateChoice:CanRepeat()
    return false
end

function CharacterCultureAggregateChoice:Choices()
    return self.choices or {}
end

function CharacterCultureAggregateChoice:GetDescription()
    return self.description
end

function CharacterCultureAggregateChoice:GetOptions()
    return self.options or {}
end

function CharacterCultureAggregateChoice:GetSelected(hero)
    local selected = {}
    local culture = hero:GetCulture()
    if culture then
        local aggregate = culture:try_get("aggregate")
        selected[#selected+1] = aggregate or ""
    end
    return selected
end

function CharacterCultureAggregateChoice:NumChoices()
    return self:try_get("numChoices", 1)
end

function CharacterCultureAggregateChoice:RemoveSelection(hero, option)
    local culture = hero:try_get("culture")
    if culture then
        local aspects = culture:try_get("aspects")
        for k,_ in pairs(aspects) do
            aspects[k] = ""
        end
        culture.aggregate = ""
    end
    return true
end

--- Save the selected option to the hero.
--- @param hero character
--- @param option table
--- @return boolean haltSavePropagation
function CharacterCultureAggregateChoice:SaveSelection(hero, option)
    local culture = hero:try_get("culture")
    if culture == nil then
        culture = Culture.CreateNew()
        hero.culture = culture
    end
    culture.aspects = dmhub.DeepCopy(option.aspects)
    culture.aggregate = option.id
    return true
end

function CharacterCultureAggregateChoice:_optionsAndChoices()
    local options = {}
    local choices = {}

    return options, choices
end