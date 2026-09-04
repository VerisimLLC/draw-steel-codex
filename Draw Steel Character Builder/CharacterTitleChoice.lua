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

--- Draw Steel echelons map onto level bands: 1st echelon is levels 1-3, 2nd is
--- 4-6, 3rd is 7-9, and 4th is level 10. A hero can only hold a title from an
--- echelon they have reached.
--- @param level number
--- @return number
local function _echelonForLevel(level)
    level = tonumber(level) or 1
    if level >= 10 then return 4 end
    if level >= 7 then return 3 end
    if level >= 4 then return 2 end
    return 1
end

function CharacterTitleChoice._optionsAndChoices(hero)
    local options = {}
    local choices = {}

    -- Titles are earned per echelon of play, so a 1st-level hero must not be
    -- offered a 4th-echelon title. Title.echelon defaults to "1", which is why
    -- the 27 title records that omit the field are still handled correctly.
    --
    -- Deliberately NOT filtered on: Title.prerequisite. Unlike complication
    -- prerequisites, which are GoblinScript, title prerequisites are prose
    -- describing a deed the Director adjudicates ("you defeat five non-minion
    -- enemies using weapon abilities..."). It is already shown to the player by
    -- Title:RenderToMarkdown, which is the right treatment for a narrative gate.
    local heroEchelon = _echelonForLevel(hero:CharacterLevel())

    local allTitles = dmhub.GetTableVisible(Title.tableName)
    for id,item in pairs(allTitles) do
        local titleEchelon = tonumber(item.echelon) or 1
        if titleEchelon <= heroEchelon then
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
            -- unique = true stops the SAME title being taken twice. Holding
            -- several DIFFERENT titles remains legal: heroes earn roughly one
            -- per echelon of play.
            options[#options+1] = {
                guid = id,
                name = item.name,
                description = nil,
                unique = true,
                render = renderFn,
            }
            choices[#choices+1] = {
                id = id,
                text = item.name,
                description = nil,
                unique = true,
                render = renderFn,
            }
        end
    end
    table.sort(options, function(a,b) return a.name < b.name end)
    table.sort(choices, function(a,b) return a.text < b.text end)

    return options, choices
end
