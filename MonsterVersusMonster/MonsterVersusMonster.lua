local mod = dmhub.GetModLoading()

MonsterVersusMonster = {}

local g_setupEnabled = false

local function GetLiveEncounter(queue)
    queue = queue or dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return nil
    end

    local liveEncounter = queue:try_get("liveEncounter")
    if type(liveEncounter) ~= "table" then
        return nil
    end

    return liveEncounter
end

function MonsterVersusMonster.IsActive(queue)
    local liveEncounter = GetLiveEncounter(queue)
    return liveEncounter ~= nil
        and liveEncounter:try_get("monsterVersusMonsterRules", false) == true
end

function MonsterVersusMonster.CreateCombatSetupCheckbox()
    if mod.unloaded then
        return nil
    end

    g_setupEnabled = false

    return gui.Check{
        text = "Monster vs Monster Rules",
        value = false,
        width = "auto",
        height = 24,
        hmargin = 16,
        change = function(element)
            g_setupEnabled = element.value
        end,
    }
end

function MonsterVersusMonster.ConfigureLiveEncounter(liveEncounter)
    if mod.unloaded or type(liveEncounter) ~= "table" then
        return
    end

    liveEncounter.monsterVersusMonsterRules = g_setupEnabled == true
    g_setupEnabled = false
end

DrawSteelCombatSetup.RegisterExtension{
    id = "monster-versus-monster",
    createPanel = MonsterVersusMonster.CreateCombatSetupCheckbox,
    configureLiveEncounter = MonsterVersusMonster.ConfigureLiveEncounter,
}


function MonsterVersusMonster.GetMaliceFloor(queue)
    queue = queue or dmhub.initiativeQueue
    local round = 1
    if queue ~= nil then
        round = math.max(1, tonumber(queue:try_get("round", 1)) or 1)
    end

    return -4 - round
end

-- A side may make one Malice expenditure while its balance is nonnegative,
-- taking the shared balance as low as -(4 + round). Once it is negative, that
-- side cannot spend Malice again.
function MonsterVersusMonster.GetMaliceAvailableToSpend(creatureProperties, queue)
    if creatureProperties == nil then
        return 0
    end

    if not MonsterVersusMonster.IsActive(queue)
        or creatureProperties:GetHeroicOrMaliceId() ~= CharacterResource.maliceResourceId then
        return creatureProperties:GetHeroicOrMaliceResources()
    end

    local malice = CharacterResource.GetMalice()
    if malice < 0 then
        return 0
    end

    return malice - MonsterVersusMonster.GetMaliceFloor(queue)
end

function MonsterVersusMonster.CanSpendMalice(cost, queue)
    cost = tonumber(cost) or 0
    if cost <= 0 then
        return true
    end

    local malice = CharacterResource.GetMalice()
    if not MonsterVersusMonster.IsActive(queue) then
        return malice >= cost
    end

    return malice >= 0 and malice - cost >= MonsterVersusMonster.GetMaliceFloor(queue)
end

function MonsterVersusMonster.SpendMalice(cost, note, queue)
    cost = tonumber(cost) or 0
    if cost <= 0 then
        return true
    end

    if not MonsterVersusMonster.CanSpendMalice(cost, queue) then
        return false
    end

    CharacterResource.SetMalice(CharacterResource.GetMalice() - cost, note)
    return true
end

local g_baseCanSpendMalice = CharacterResource.CanSpendMalice
function CharacterResource.CanSpendMalice(cost)
    if not mod.unloaded and MonsterVersusMonster.IsActive() then
        return MonsterVersusMonster.CanSpendMalice(cost)
    end

    return g_baseCanSpendMalice(cost)
end

local g_baseSpendMalice = CharacterResource.SpendMalice
function CharacterResource.SpendMalice(cost, note)
    if not mod.unloaded and MonsterVersusMonster.IsActive() then
        return MonsterVersusMonster.SpendMalice(cost, note)
    end

    return g_baseSpendMalice(cost, note)
end

local function IsMaliceResource(resourceInfo)
    if resourceInfo == nil then
        return false
    end

    local resources = dmhub.GetTable(CharacterResource.tableName)
    return resourceInfo == resources[CharacterResource.maliceResourceId]
        or resourceInfo.name == "Malice"
end

-- ActivatedAbility:GetCost uses this virtual allowance when testing global
-- resources. This keeps normal Malice buttons and Monster AI checks on the
-- standard casting pipeline.
local g_baseAllowResourceBelowZero = CharacterResource.AllowResourceBelowZero
function CharacterResource:AllowResourceBelowZero(caster)
    if not mod.unloaded and IsMaliceResource(self)
        and MonsterVersusMonster.IsActive()
        and caster ~= nil
        and caster:GetHeroicOrMaliceId() == CharacterResource.maliceResourceId
        and CharacterResource.GetMalice() >= 0 then
        return -MonsterVersusMonster.GetMaliceFloor()
    end

    return g_baseAllowResourceBelowZero(self, caster)
end

-- General-purpose affordability used by triggers and roll-dialog additions.
local g_baseGetResourcesAvailableToSpend = creature.GetHeroicOrMaliceResourcesAvailableToSpend
function creature:GetHeroicOrMaliceResourcesAvailableToSpend()
    if not mod.unloaded and MonsterVersusMonster.IsActive()
        and self:GetHeroicOrMaliceId() == CharacterResource.maliceResourceId then
        return MonsterVersusMonster.GetMaliceAvailableToSpend(self)
    end

    return g_baseGetResourcesAvailableToSpend(self)
end

-- Global resource consumption normally clamps Malice at zero. Intercept only
-- Malice payments in this mode and validate the floor again at payment time.
local g_baseConsumeResource = creature.ConsumeResource
function creature:ConsumeResource(key, refreshType, quantity, note)
    quantity = quantity or 1
    if not mod.unloaded
        and key == CharacterResource.maliceResourceId
        and refreshType == "global"
        and quantity ~= 0
        and MonsterVersusMonster.IsActive() then
        if quantity > 0 then
            if not MonsterVersusMonster.SpendMalice(quantity, note) then
                dmhub.Debug(string.format(
                    "MonsterVersusMonster: rejected Malice spend of %s at %s (floor %s)",
                    tostring(quantity),
                    tostring(CharacterResource.GetMalice()),
                    tostring(MonsterVersusMonster.GetMaliceFloor())))
                return 0
            end
        else
            --Refunds (notably cancelling a cast) must restore the negative
            --balance rather than passing through the normal zero clamp.
            CharacterResource.SetMalice(CharacterResource.GetMalice() - quantity, note)
        end

        local resourceInfo = dmhub.GetTable(CharacterResource.tableName)[key]
        if resourceInfo ~= nil and quantity > 0 then
            self:DispatchEvent("useresource", {
                resource = string.lower(resourceInfo.name),
                quantity = quantity,
            })
        end
        return
    end

    return g_baseConsumeResource(self, key, refreshType, quantity, note)
end

-- Re-evaluate every Malice detail as one total so a base cost plus a channeled
-- increment cannot cross the floor by passing independently.
local g_baseGetAbilityCost = ActivatedAbility.GetCost
function ActivatedAbility:GetCost(casterToken, options)
    local result = g_baseGetAbilityCost(self, casterToken, options)
    if mod.unloaded or not MonsterVersusMonster.IsActive()
        or casterToken == nil or casterToken.properties == nil
        or casterToken.properties:GetHeroicOrMaliceId() ~= CharacterResource.maliceResourceId
        or result == nil or result.details == nil then
        return result
    end

    local maliceDetails = {}
    local totalMaliceCost = 0
    for _,detail in ipairs(result.details) do
        if detail.cost == CharacterResource.maliceResourceId then
            maliceDetails[#maliceDetails + 1] = detail
            totalMaliceCost = totalMaliceCost + (tonumber(detail.quantity) or 0)
        end
    end

    if #maliceDetails == 0 then
        return result
    end

    local canAffordMalice = MonsterVersusMonster.CanSpendMalice(totalMaliceCost)
    for index,detail in ipairs(maliceDetails) do
        detail.canAfford = canAffordMalice
        detail.paymentOptions = canAffordMalice and index == 1 and {{
            resourceid = CharacterResource.maliceResourceId,
            quantity = totalMaliceCost,
        }} or {}
        detail.expendedOptions = (not canAffordMalice) and index == 1 and {{
            resourceid = CharacterResource.maliceResourceId,
            quantity = totalMaliceCost,
        }} or {}
    end

    local canAfford = not result.cannotMove and not result.outOfAmmo
    for _,detail in ipairs(result.details) do
        canAfford = canAfford and detail.canAfford
    end
    result.canAfford = canAfford

    return result
end

-- Power-roll modifiers use their own resource affordability method.
local g_baseModifierHasResourcesAvailable = CharacterModifier.HasResourcesAvailable
function CharacterModifier:HasResourcesAvailable(creatureProperties)
    local costType = self:try_get("resourceCostType", "none")
    if not mod.unloaded and MonsterVersusMonster.IsActive()
        and creatureProperties ~= nil
        and creatureProperties:GetHeroicOrMaliceId() == CharacterResource.maliceResourceId
        and costType ~= "none" and costType ~= "surges" and costType ~= "epic" then
        local cost = tonumber(ExecuteGoblinScript(
            self:try_get("resourceCostAmount", "1"),
            creatureProperties:LookupSymbol(self:try_get("_tmp_symbols", {})),
            0)) or 0
        return cost <= MonsterVersusMonster.GetMaliceAvailableToSpend(creatureProperties)
    end

    return g_baseModifierHasResourcesAvailable(self, creatureProperties)
end

-- IsPlayersTurn accounts for exhausted sides, so this does not convert Malice
-- when the same side retains control because the opposition has no turns left.
local g_baseNextTurn = InitiativeQueue.NextTurn
function InitiativeQueue.NextTurn(self, initiativeid)
    local endingSide = self:IsEntryPlayer(initiativeid)
    local previousMalice = CharacterResource.GetMalice()
    local result = g_baseNextTurn(self, initiativeid)

    if not mod.unloaded and endingSide ~= nil and MonsterVersusMonster.IsActive(self) then
        local nextSide = self:IsPlayersTurn()
        if nextSide ~= endingSide then
            local nextMalice = previousMalice > 0 and 0 or -previousMalice
            CharacterResource.SetMalice(nextMalice, "Monster vs Monster side switch")
        end
    end

    return result
end
