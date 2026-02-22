local mod = dmhub.GetModLoading()

CharacterResource.heroicResourceId = "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca"
CharacterResource.maliceResourceId = "101bab52-7f7c-4bab-92c2-9f8e0cfb7ec8"
CharacterResource.surgeResourceId = "8b0ae5fe-0eb3-45fa-9e6d-b9de68f5cc6d"
CharacterResource.triggerResourceId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"
CharacterResource.actionResourceId = "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
CharacterResource.maneuverResourceId = "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b"
CharacterResource.heroTokenId = "2166c5fe-260e-4691-9743-06cf097a59f3"
CharacterResource.villainActionId = "67f15a17-523c-4a30-8f1a-a27e4f122605"
CharacterResource.recoveryResourceId = "5bd90f9b-46be-4cf2-8ca6-a96430d62949"
CharacterResource.freeManeuverResourceId = "d81ce1e9-96a3-4705-9180-1c80f72a86cf"
CharacterResource.respiteActivityId = "5758da29-8660-47d3-805b-7c6038f476a1"

monster.resourceid = CharacterResource.maliceResourceId
character.resourceid = CharacterResource.heroicResourceId

monster.resourceRefresh = "global"
creature.resourceRefresh = "unbounded"

function creature:GetHeroicOrMaliceResourcesAvailableToSpend()
    return self:GetHeroicOrMaliceResourcesAvailable()
end

function character:GetHeroicOrMaliceResourcesAvailableToSpend()
    return self:GetHeroicOrMaliceResourcesAvailable() + self:CalculateNamedCustomAttribute("Negative Heroic Resource") + self:ExtraHeroicResource()
end

function creature:GetHeroicOrMaliceResourcesAvailable()
    return self:GetHeroicOrMaliceResources()
end

function creature:GetHeroicOrMaliceResources()
    local resources = self:GetResources()
    return resources[self.resourceid] or 0
end

function character:GetHeroicOrMaliceResources()
    local resources = self:try_get("resources")
    if resources ~= nil then
        local heroicResource = resources[CharacterResource.heroicResourceId]
        if heroicResource ~= nil then
            return heroicResource.unbounded or 0
        end
    end

    return 0
end

function creature:ResourceName()
    local t = dmhub.GetTable(CharacterResource.tableName)
    return t[self.resourceid].name
end

function CharacterResource.GetMalice()
    return CharacterResource.GetGlobalResource(CharacterResource.maliceResourceId)
end

function CharacterResource.SetMalice(amount, message)
    print("SetMalice::", amount)
    CharacterResource.SetGlobalResource(CharacterResource.maliceResourceId, amount, message)
end

function CharacterResource.GetVillainActions()
    return CharacterResource.GetGlobalResource(CharacterResource.villainActionId)
end

function CharacterResource.SetVillainActions(amount, note)
    CharacterResource.SetGlobalResource(CharacterResource.villainActionId, amount, note)
end

function creature:GetHeroTokens()
    return 0
end

function character:GetHeroTokens()
    return CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)
end

function creature:SetHeroTokens(amount, message)
    CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, amount, message)
end

--- @return {color: string, when: string, who: string, value: number, note: string}
function creature:GetHeroTokenHistory()
    return CharacterResource.GetGlobalResourceHistory(CharacterResource.heroTokenId)
end