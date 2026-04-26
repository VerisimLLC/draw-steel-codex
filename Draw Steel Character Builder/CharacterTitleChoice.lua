local mod = dmhub.GetModLoading()

--[[
    Character Title Choice

    Make a Title choice behave like a feature choice
    for purposes of the character builder.
]]
CharacterTitleChoice = RegisterGameType("CharacterTitleChoice", "CharacterChoice")

CharacterTitleChoice.description = "Title Choice"
CharacterTitleChoice.numChoices = 1
CharacterTitleChoice.costsPoints = false
CharacterTitleChoice.hasRoll = false

function CharacterTitleChoice.CreateNew(hero)
    local options, choices = CharacterTitleChoice._optionsAndChoices(hero)

    local selected = {}
    for id,_ in pairs(hero:try_get("titles", {})) do
        selected[#selected+1] = id
    end

    return CharacterTitleChoice.new{
        guid = CharacterBuilder.SELECTOR.TITLE,
        name = "Title",
        options = options,
        choices = choices,
        numChoices = #selected + 1,
        numSelected = #selected,
        selected = selected,
    }
end

function CharacterTitleChoice:CanRepeat()
    return false
end

function CharacterTitleChoice:Choices()
    return self.choices or {}
end

function CharacterTitleChoice:GetDescription()
    return self.description
end

function CharacterTitleChoice:GetOptions()
    return self.options or {}
end

function CharacterTitleChoice:GetSelected(hero)
    return self:try_get("selected", {})
end

function CharacterTitleChoice:GetStatus()
    return {
        numChoices = self.numSelected,
        selected = self.numSelected,
        excludeFromTotals = true,
    }
end

function CharacterTitleChoice:NumChoices()
    return self:try_get("numChoices", 1)
end

function CharacterTitleChoice:OfferFilter()
    return true
end

function CharacterTitleChoice:RemoveSelection(hero, option)
    local selected = hero:try_get("titles", {})
    selected[option.guid] = nil
    return true
end

function CharacterTitleChoice:SaveSelection(hero, option)
    local selected = hero:get_or_add("titles", {})
    selected[option.id] = true
    return true
end

function CharacterTitleChoice._optionsAndChoices(hero)
    local options = {}
    local choices = {}

    local allTitles = dmhub.GetTableVisible(Title.tableName)
    for id,item in pairs(allTitles) do
        local renderFn = function()
            return gui.Label{
                classes = {"builder-base", "label", "info"},
                width = "98%",
                height = "auto",
                halign = "left",
                vmargin = 12,
                textAlignment = "topleft",
                markdown = true,
                text = item:RenderToMarkdown{ noninteractive = true }.content,
            }
        end
        options[#options+1] = {
            guid = id,
            name = item.name,
            description = nil,
            unique = false,
            render = renderFn,
        }
        choices[#choices+1] = {
            id = id,
            text = item.name,
            description = nil,
            unique = false,
            render = renderFn,
        }
    end
    table.sort(options, function(a,b) return a.name < b.name end)
    table.sort(choices, function(a,b) return a.text < b.text end)

    return options, choices
end
