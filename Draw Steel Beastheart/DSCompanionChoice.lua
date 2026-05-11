local mod = dmhub.GetModLoading()

--- @class CharacterCompanionChoice:CharacterChoice
--- A class-feature choice for a Beastheart's companion species. Options are
--- scanned at runtime from the bestiary (any monster with
--- typeName == "AnimalCompanion"), matching the option set offered by the
--- "companion" CharacterModifier. When a player picks an option, FillChoice
--- emits a CharacterFeature wrapping a "companion" modifier with the chosen
--- bestiary id stored as companionType.
CharacterCompanionChoice = RegisterGameType("CharacterCompanionChoice", "CharacterChoice")

CharacterCompanionChoice.name = "Companion"
CharacterCompanionChoice.description = "Choose one companion species."
CharacterCompanionChoice.numChoices = 1
CharacterCompanionChoice.costsPoints = false

function CharacterCompanionChoice.Create(args)
    local params = {
        guid = dmhub.GenerateGuid(),
        numChoices = 1,
    }
    for k,v in pairs(args or {}) do
        params[k] = v
    end
    return CharacterCompanionChoice.new(params)
end

function CharacterCompanionChoice:Describe()
    return "Companion"
end

function CharacterCompanionChoice:GetDescription()
    return self.description
end

function CharacterCompanionChoice:NumChoices(creature)
    return self:try_get("numChoices", 1)
end

function CharacterCompanionChoice:CanRepeat()
    return false
end

function CharacterCompanionChoice:VisitRecursive(fn)
    fn(self)
end

--- Scan the bestiary for AnimalCompanion stat blocks. Mirrors the filter used
--- by the companion CharacterModifier dropdown in DSModifierCompanion.lua.
--- @return {id: string, name: string, description: string}[]
local function ScanCompanionMonsters()
    local result = {}
    for k,monster in pairs(assets.monsters) do
        local node = assets:GetMonsterNode(k)
        if (not node.hidden) and monster.properties.typeName == "AnimalCompanion" then
            result[#result+1] = {
                id = k,
                name = monster.name or "Companion",
                description = monster.properties:try_get("description", "") or "",
            }
        end
    end
    table.sort(result, function(a,b) return a.name < b.name end)
    return result
end

function CharacterCompanionChoice:Choices(numOption, existingChoices, creature)
    local result = {}
    for _,entry in ipairs(ScanCompanionMonsters()) do
        result[#result+1] = {
            id = entry.id,
            text = entry.name,
            description = entry.description,
        }
    end
    return result
end

function CharacterCompanionChoice:GetOptions(choices, creature)
    local options = {}
    for _,entry in ipairs(ScanCompanionMonsters()) do
        options[#options+1] = {
            guid = entry.id,
            name = entry.name,
            description = entry.description,
            unique = true,
        }
    end
    return options
end

--- When a companion has been chosen, emit a synthetic CharacterFeature whose
--- single CharacterModifier is the "companion" behavior with the chosen
--- bestiary id stored as companionType. This gives the character the same
--- modifier shape that DSModifierCompanion.lua produces from its UI editor,
--- so creature:GetCompanionType() returns the chosen id.
function CharacterCompanionChoice:FillChoice(choices, result)
    local choiceidList = choices[self.guid]
    if choiceidList == nil or #choiceidList == 0 then return end

    local companionType = choiceidList[1]
    if companionType == nil or companionType == "" then return end

    local monster = assets.monsters[companionType]
    local monsterName = (monster and monster.name) or "Companion"

    result[#result+1] = CharacterFeature.new{
        guid = string.format("%s:companion-feature", self.guid),
        name = string.format("Companion: %s", monsterName),
        source = "Beastheart",
        description = "Your beastheart's companion.",
        modifiers = {
            CharacterModifier.new{
                behavior = "companion",
                guid = string.format("%s:companion-modifier", self.guid),
                name = "Beastheart Companion",
                source = "Beastheart",
                description = string.format("Your companion is a %s.", monsterName),
                companionType = companionType,
            },
        },
    }
end

CharacterChoice.RegisterChoice{
    id = "companion",
    text = "Beastheart Companion",
    type = CharacterCompanionChoice,
}
