--[[
    CharacterIncidentChoice

    Make a background characteristic / roll table behave like
    a feature choice for purposes of the character builder.
]]
CharacterIncidentChoice = RegisterGameType("CharacterIncidentChoice", "CharacterChoice")
CharacterIncidentOption = RegisterGameType("CharacterIncidentOption")

CharacterIncidentChoice.name = "Incident"
CharacterIncidentChoice.description = "Inciting Incident"
CharacterIncidentChoice.numChoices = 1
CharacterIncidentChoice.costsPoints = false
CharacterIncidentChoice.hasRoll = true

--- Contruct from a background characteristic
--- @param c BackgroundCharacteristic
--- @return CharacterIncidentChoice
function CharacterIncidentChoice.CreateNew(c)

    local options = {}
    local rollTable = c:GetRollTable()
    local rollInfo = rollTable:CalculateRollInfo()
    for i,row in ipairs(rollTable.rows) do
        options[#options+1] = CharacterIncidentOption.CreateNew(row, rollInfo.rollRanges[i])
    end

    return CharacterIncidentChoice.new{
        guid = c.tableid,
        name = c:Name(),
        description = (rollTable.details and #rollTable.details) and rollTable.details or c:Name(),
        options = options,
        characteristic = c,
    }
end

--- Construct from data - a roll table entry
--- @param row
--- @param rollRange
--- @return CharacterIncidentOption
function CharacterIncidentOption.CreateNew(row, rollRange)

    local function parseString(str)
        local name, description

        -- Try bold pattern: **Name:** or **Name:**: or **Name**
        local result = regex.MatchGroups(str, "^(?:\\*\\*|__)(?<name>.+?)(?::)?(?:\\*\\*|__)(?::)?\\s*(?<description>.*)$")
        if result and result.name then
            name = result.name
            description = result.description or ""
        else
            -- Try colon-separated: Name: description
            result = regex.MatchGroups(str, "^(?<name>[^:]+):\\s*(?<description>.*)$")
            if result and result.name then
                name = result.name
                description = result.description or ""
            else
                -- No structure - take first 30 chars
                if #str > 30 then
                    name = str:sub(1, 30)
                    description = str:sub(31)
                else
                    name = str
                    description = ""
                end
            end
        end

        return name, description
    end

    local function rangeText(rollRange)
        if rollRange == nil or rollRange.min == nil then return "--" end
        if rollRange.min == rollRange.max then return tostring(round(rollRange.min)) end
        return string.format("%d%s%d", round(rollRange.min), Styles.emdash, round(rollRange.max))
    end

    local name, description = parseString(row.value:ToString())
    local range = rangeText(rollRange)
    name = string.format("%s: %s", range, name)

    return CharacterIncidentOption.new{
        guid = row.id,
        name = name,
        description = description,
        row = row,
        rollRange = rollRange,
        unique = true,
    }
end

function CharacterIncidentChoice:CanRepeat()
    return false
end

function CharacterIncidentChoice:Choices(numOption, existingChoices, creature)
    return self.options
end

function CharacterIncidentChoice:FillChoices(choices, result)
end

function CharacterIncidentChoice:FillFeaturesRecursive(choices, result)
end

function CharacterIncidentChoice:GetDescription()
    return self.description
end

function CharacterIncidentChoice:GetOptions(choices)
    return self.options
end

function CharacterIncidentChoice:NumChoices(creature)
    return self.numChoices
end

function CharacterIncidentChoice:VisitRecursive(fn)
    fn(self)
    for _,o in ipairs(self.options) do
        o:VisitRecursive(fn)
    end
end

function CharacterIncidentChoice:CreateEditor(classOrRace, params)
    return nil
end

--- @param hero character
--- @param option CharacterIncidentOption
--- @return boolean stopSave Return true to skip default save behavior
function CharacterIncidentChoice:SaveSelection(hero, option)
    hero:RemoveNotesForTable(self.guid)
    local noteItem = hero:GetOrAddNoteForTableRow(self.guid, option.guid)
    if noteItem then
        noteItem.title = self.name
        noteItem.text = option.row.value:ToString()
    end
    return false
end

--- @param hero character
--- @param option CharacterIncidentOption
--- @return boolean stopSave Return true to skip default save behavior
function CharacterIncidentChoice:RemoveSelection(hero, option)
    hero:RemoveNoteForTableRow(self.guid, option.guid)
    return false
end
