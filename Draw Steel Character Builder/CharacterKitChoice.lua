--[[
    CharacterKitChoice

    Make a Kit behave like a feature choice for purposes
    of the character builder. This is not used as a class
    feature choice but could maybe be dropped in like one.
    This supports CBKitDetail.
]]
CharacterKitChoice = RegisterGameType("CharacterKitChoice", "CharacterChoice")

--- Construct from a hero
--- @param hero character
--- @return CharacterKitChoice|nil
function CharacterKitChoice.CreateNew(hero)

    if hero == nil then return nil end
    if not hero:CanHaveKits() then return nil end

    local classItem = hero:GetClass()
    if classItem == nil then return nil end

    local options = {}
    local choices = {}
    local validKitTypes = hero:KitTypesAllowed()
    local kitsTable = dmhub.GetTableVisible(Kit.tableName)
    for id,kit in pairs(kitsTable) do
        if validKitTypes[kit.type] then
            options[#options+1] = {
                guid = id,
                name = kit.name,
                description = kit.description,
                unique = true,
            }
            choices[#choices+1] = {
                id = id,
                text = kit.name,
                description = kit.description,
                unique = true,
            }
        end
    end
    if #options == 0 then return nil end
    table.sort(options, function(a,b) return a.name < b.name end)
    table.sort(choices, function(a,b) return a.text < b.text end)

    local numChoices = hero:GetNumberOfKits()
    local description = numChoices == 2 and "You can use and gain the benefits of two kits, including both their signature abilities."
        or "You can use and gain the benefits of a kit."

    return CharacterKitChoice.new{
        guid = classItem.id,
        name = "Kit",
        numChoices = numChoices,
        costsPoints = false,
        hasRoll = false,
        description = description,
        options = options,
        choices = choices,
    }
end

function CharacterKitChoice:CanRepeat()
    return false
end

function CharacterKitChoice:Choices()
    return self.choices or {}
end

function CharacterKitChoice:GetDescription()
    return self.description
end

function CharacterKitChoice:GetOptions()
    return self.options or {}
end

--- Return the currently selected option, if there is one
--- @param hero character
--- @return table selected List of option guids
function CharacterKitChoice:GetSelected(hero)
    local kitid = hero:try_get("kitid")
    local kitid2 = hero:try_get("kitid2")
    local selected = {}
    if kitid then selected[#selected+1] = kitid end
    if kitid2 then selected[#selected+1] = kitid2 end
    return selected
end

function CharacterKitChoice:NumChoices()
    return self:try_get("numChoices", 1)
end

--- Remove the selection from the hero.
--- @param hero character
--- @param option table
--- @return boolean haltSavePropagation
function CharacterKitChoice:RemoveSelection(hero, option)
    local optionId = option.guid
    local kitid = hero:try_get("kitid")
    local kitid2 = hero:try_get("kitid2")
    if kitid == optionId then
        if kitid2 then
            hero.kitid = kitid2
            hero.kitid2 = nil
        else
            hero.kitid = nil
        end
    elseif kitid2 == optionId then
        hero.kitid2 = nil
    end
    return true
end

--- Save the selected option to the hero.
--- @param hero character
--- @param option table
--- @return boolean haltSavePropagation
function CharacterKitChoice:SaveSelection(hero, option)
    local optionId = option.guid
    local numChoices = self:NumChoices(hero)
    if numChoices == 1 then
        hero.kitid = optionId
    else
        local kitid = hero:try_get("kitid")
        local kitid2 = hero:try_get("kitid2")
        if optionId ~= kitid and optionId ~= kitid2 then
            if kitid == nil then
                hero.kitid = optionId
            elseif kitid2 == nil then
                hero.kitid2 = optionId
            end
        end
    end
    return true
end

--- The panel(s) to inject into the feature builder
--- @return table
function CharacterKitChoice:UIInjections()
    -- TODO:
end

function CharacterKitChoice:VisitRecursive(fn)
    fn(self)
    for _,o in ipairs(self:GetOptions()) do
        fn(o)
    end
end