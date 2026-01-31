--[[
    Character Complication Choice

    Make a Complication choice behave like a feature choice
    for purposes of the character builder.
]]
CharacterComplicationChoice = RegisterGameType("CharacterComplicationChoice", "CharacterChoice")

CharacterComplicationChoice.description = "Complication Choice"
CharacterComplicationChoice.numChoices = 1
CharacterComplicationChoice.costsPoints = false
CharacterComplicationChoice.hasRoll = false

function CharacterComplicationChoice.CreateNew(hero)
    local options, choices = CharacterComplicationChoice._optionsAndChoices(hero)

    local selected = {}
    for id,_ in pairs(hero:try_get("complications", {})) do
        selected[#selected+1] = id
    end

    return CharacterComplicationChoice.new{
        guid = CharacterBuilder.SELECTOR.COMPLICATION,
        name = "Complication",
        options = options,
        choices = choices,
        numChoices = #selected + 1,
        numSelected = #selected,
        selected = selected,
    }
end

function CharacterComplicationChoice:CanRepeat()
    return false
end

function CharacterComplicationChoice:Choices()
    return self.choices or {}
end

function CharacterComplicationChoice:GetDescription()
    return self.description
end

function CharacterComplicationChoice:GetOptions()
    return self.options or {}
end

function CharacterComplicationChoice:GetSelected(hero)
    return self:try_get("selected", {})
end

function CharacterComplicationChoice:GetStatus()
    return {
        numChoices = math.max(self.numSelected, 1),
        selected = self.numSelected,
    }
end

function CharacterComplicationChoice:NumChoices()
    return self:try_get("numChoices", 1)
end

function CharacterComplicationChoice:OfferFilter()
<<<<<<< HEAD
    -- TODO: This throws the list height off. Need to resolve that.
=======
>>>>>>> 5023b65f8da1d2d7f38a535abf3c7e6e5ecdca90
    return true
end

function CharacterComplicationChoice:RemoveSelection(hero, option)
    local selected = hero:try_get("complications", {})
    selected[option.guid] = nil
    return true
end

function CharacterComplicationChoice:SaveSelection(hero, option)
    local selected = hero:get_or_add("complications", {})
    selected[option.id] = true
    return true
end

function CharacterComplicationChoice._optionsAndChoices(hero)
    local options = {}
    local choices = {}

    for id,item in pairs(dmhub.GetTableVisible(CharacterComplication.tableName)) do
        local passFilter = true
        if item.prerequisite ~= nil and (trim(item.prerequisite) ~= "") then
            passFilter = GoblinScriptTrue(ExecuteGoblinScript(item.prerequisite, hero:LookupSymbol(), 0, string.format("Complication %s prerequisite", item.name)))
        end
        if passFilter then
            options[#options+1] = {
                guid = id,
                name = item.name,
                description = nil,
                unique = true,
            }
            choices[#choices+1] = {
                id = id,
                text = item.name,
                description = nil,
                unique = true,
                hasCustomPanel = true,
                panel = function() return item:Render() end,
            }
        end
    end
    table.sort(options, function(a,b) return a.name < b.name end)
    table.sort(choices, function(a,b) return a.text < b.text end)

    return options, choices
end