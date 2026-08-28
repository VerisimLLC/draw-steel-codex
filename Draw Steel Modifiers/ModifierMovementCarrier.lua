local mod = dmhub.GetModLoading()

local g_grabbedCondition = "70504ebe-3899-41d3-9f60-74b52ce35e39"

local function ActualGrabCarrierId(creatureInfo)
    local inflictedConditions = creatureInfo:try_get("inflictedConditions")
    if inflictedConditions == nil then
        return nil
    end

    local grabbed = inflictedConditions[g_grabbedCondition]
    local casterInfo = grabbed ~= nil and grabbed.casterInfo or nil
    if casterInfo == nil or type(casterInfo.tokenid) ~= "string" then
        return nil
    end

    return casterInfo.tokenid
end

local function ResolveConditionCaster(context, passenger)
    local effect = context ~= nil and context.ongoingEffect or nil
    if effect == nil then
        return nil
    end

    local casterInfo = effect:try_get("casterInfo")
    if casterInfo == nil or type(casterInfo.tokenid) ~= "string" then
        return nil
    end

    local carrierToken = dmhub.GetTokenById(casterInfo.tokenid)
    local passengerToken = dmhub.LookupToken(passenger)
    if carrierToken == nil or not carrierToken.valid or carrierToken.properties == nil or
       passengerToken == nil or not passengerToken.valid or passengerToken.id == carrierToken.id then
        return nil
    end

    local grabRange = tonumber(carrierToken.properties:CalculateNamedCustomAttribute("Grab Range")) or 1
    if carrierToken:Distance(passengerToken) > grabRange then
        return nil
    end

    return casterInfo.tokenid
end


CharacterModifier.RegisterType("movementcarrier", "Movement Carrier")

CharacterModifier.TypeInfo.movementcarrier = {
    init = function(modifier)
        modifier.carrier = "condition_caster"
        modifier.useGrabMovementPenalty = true
        modifier.countsTowardGrabLimit = true
    end,

    resolveMovementCarrier = function(modifier, context, passenger, currentCarrierId)
        if currentCarrierId ~= nil then
            return currentCarrierId
        end

        if modifier:try_get("carrier", "condition_caster") == "condition_caster" then
            return ResolveConditionCaster(context, passenger)
        end

        return nil
    end,

    createEditor = function(modifier, element)
        element.children = {
            modifier:FilterConditionEditor(),
            gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Carrier:",
                },
                gui.Dropdown{
                    options = {
                        { id = "condition_caster", text = "Ongoing Effect Caster" },
                    },
                    idChosen = modifier:try_get("carrier", "condition_caster"),
                    change = function(dropdown)
                        modifier.carrier = dropdown.idChosen
                        element:FireEvent("refreshModifier")
                    end,
                },
            },
            gui.Check{
                text = "Use normal grab movement penalty",
                value = modifier:try_get("useGrabMovementPenalty", true),
                change = function(check)
                    modifier.useGrabMovementPenalty = check.value
                    element:FireEvent("refreshModifier")
                end,
            },
            gui.Check{
                text = "Count toward grab limit",
                value = modifier:try_get("countsTowardGrabLimit", true),
                change = function(check)
                    modifier.countsTowardGrabLimit = check.value
                    element:FireEvent("refreshModifier")
                end,
            },
        }
    end,
}


function CharacterModifier:ResolveMovementCarrier(context, passenger, currentCarrierId)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.resolveMovementCarrier == nil then
        return currentCarrierId
    end

    return typeInfo.resolveMovementCarrier(self, context, passenger, currentCarrierId)
end

function CharacterModifier.GetMovementCarrierFromModifiers(passenger, modifiers)
    -- A real grab owns the spatial relationship even when its grabber differs
    -- from the ongoing effect caster. The generic link remains dormant.
    if ActualGrabCarrierId(passenger) ~= nil then
        return nil, nil, nil
    end

    local carrierId = nil
    local carrierModifier = nil
    local carrierContext = nil

    for _, context in ipairs(modifiers or {}) do
        local resolved = context.mod:ResolveMovementCarrier(context, passenger, carrierId)
        if carrierId == nil and resolved ~= nil then
            carrierModifier = context.mod
            carrierContext = context
        end
        carrierId = resolved
    end

    return carrierId, carrierModifier, carrierContext
end

function CharacterModifier.GetMovementCarrier(passenger)
    return CharacterModifier.GetMovementCarrierFromModifiers(passenger, passenger:GetActiveModifiers())
end

local g_movementCarrierIndexUpdate = -1
local g_movementCarrierIndex = {}
local g_movementCarrierIndexBuilding = false

function CharacterModifier.InvalidateMovementCarrierIndex()
    g_movementCarrierIndexUpdate = -1
    g_movementCarrierIndex = {}
end

local function MovementCarrierIndex()
    if g_movementCarrierIndexUpdate == dmhub.ngameupdate then
        return g_movementCarrierIndex
    end

    -- A modifier filter can calculate attributes, which can re-enter active
    -- modifier collection. Return the cache accumulated so far in that case.
    if g_movementCarrierIndexBuilding then
        return g_movementCarrierIndex
    end

    local result = {}
    g_movementCarrierIndex = result
    g_movementCarrierIndexBuilding = true
    local effectsTable = dmhub.GetTable(CharacterOngoingEffect.tableName) or {}
    for _, targetToken in ipairs(dmhub.GetTokens()) do
        if targetToken.valid and targetToken.properties ~= nil and
           ActualGrabCarrierId(targetToken.properties) == nil then
            local foundCarrier = false
            for _, effect in ipairs(targetToken.properties:ActiveOngoingEffects()) do
                local effectInfo = effectsTable[effect.ongoingEffectid]
                if effectInfo ~= nil then
                    for _, modifier in ipairs(effectInfo:try_get("modifiers", {})) do
                        if modifier.behavior == "movementcarrier" then
                            local context = {
                                mod = modifier,
                                ongoingEffect = effect,
                                stacks = effect.stacks,
                            }
                            if not modifier:HasFilter() or modifier:PassesFilter(targetToken.properties, context) then
                                local carrierId = modifier:ResolveMovementCarrier(context, targetToken.properties, nil)
                                if carrierId ~= nil then
                                    result[carrierId] = result[carrierId] or {}
                                    result[carrierId][#result[carrierId]+1] = {
                                        token = targetToken,
                                        modifier = modifier,
                                        context = context,
                                    }
                                    foundCarrier = true
                                    break
                                end
                            end
                        end
                    end
                end
                if foundCarrier then
                    break
                end
            end
        end
    end

    g_movementCarrierIndexUpdate = dmhub.ngameupdate
    g_movementCarrierIndexBuilding = false
    return result
end

function CharacterModifier.VisitMovementCarrierPassengers(carrier, visitor)
    local carrierToken = dmhub.LookupToken(carrier)
    if carrierToken == nil or not carrierToken.valid then
        return
    end

    local entries = MovementCarrierIndex()[carrierToken.id] or {}
    for _, entry in ipairs(entries) do
        visitor(entry.token, entry.modifier, entry.context)
    end
end

function CharacterModifier.CountMovementCarrierCapacity(carrier, excludedMovementTargets)
    local carrierToken = dmhub.LookupToken(carrier)
    if carrierToken == nil or not carrierToken.valid then
        return 0
    end

    local occupiedTargets = {}
    for _, targetToken in ipairs(dmhub.GetTokens()) do
        if targetToken.valid and targetToken.properties ~= nil and
           ActualGrabCarrierId(targetToken.properties) == carrierToken.id then
            occupiedTargets[targetToken.id] = true
        end
    end

    CharacterModifier.VisitMovementCarrierPassengers(carrier, function(targetToken, modifier)
        if modifier:try_get("countsTowardGrabLimit", true) and
           (excludedMovementTargets == nil or not excludedMovementTargets[targetToken.id]) then
            occupiedTargets[targetToken.id] = true
        end
    end)

    local result = 0
    for _ in pairs(occupiedTargets) do
        result = result + 1
    end
    return result
end


--- @class ActivatedAbilityMovementCarrierBehavior:ActivatedAbilityBehavior
--- @field ongoingEffect string The caster-tracked effect that marks the passenger.
ActivatedAbilityMovementCarrierBehavior = RegisterGameType(
    "ActivatedAbilityMovementCarrierBehavior",
    "ActivatedAbilityBehavior"
)

ActivatedAbilityMovementCarrierBehavior.summary = "Assign Movement Carrier"
ActivatedAbilityMovementCarrierBehavior.ongoingEffect = "none"

ActivatedAbility.RegisterType{
    id = "movement_carrier",
    text = "Assign Movement Carrier",
    createBehavior = function()
        return ActivatedAbilityMovementCarrierBehavior.new{
            ongoingEffect = "none",
        }
    end,
}

function ActivatedAbilityMovementCarrierBehavior:SummarizeBehavior(ability, creatureLookup)
    local effect = (dmhub.GetTable(CharacterOngoingEffect.tableName) or {})[self:try_get("ongoingEffect", "none")]
    if effect == nil then
        return "Assign Movement Carrier"
    end
    return string.format("Assign Movement Carrier: %s", effect.name)
end

function ActivatedAbilityMovementCarrierBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)

    local effectOptions = {
        { id = "none", text = "(Choose an ongoing effect)" },
    }
    for id, effect in unhidden_pairs(dmhub.GetTable(CharacterOngoingEffect.tableName) or {}) do
        effectOptions[#effectOptions+1] = {
            id = id,
            text = effect.name,
        }
    end
    table.sort(effectOptions, function(a, b) return a.text < b.text end)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Passenger Effect:",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = effectOptions,
            hasSearch = true,
            idChosen = self:try_get("ongoingEffect", "none"),
            change = function(dropdown)
                self.ongoingEffect = dropdown.idChosen
                parentPanel:FireEvent("refreshBehavior")
            end,
        },
    }

    return result
end

local function FindCarrierEffectInstances(effectId, casterId, selectedToken)
    local instances = {}
    local excludedMovementTargets = {}
    local selectedOwned = false

    for _, targetToken in ipairs(dmhub.GetTokens()) do
        if targetToken.valid and targetToken.properties ~= nil then
            for _, effect in ipairs(targetToken.properties:try_get("ongoingEffects", {})) do
                local casterInfo = effect:try_get("casterInfo")
                if effect.ongoingEffectid == effectId and casterInfo ~= nil and casterInfo.tokenid == casterId then
                    instances[#instances+1] = {
                        token = targetToken,
                        seq = effect.seq,
                    }
                    excludedMovementTargets[targetToken.id] = true
                    if targetToken.id == selectedToken.id then
                        selectedOwned = true
                    end
                end
            end
        end
    end

    return instances, excludedMovementTargets, selectedOwned
end

local function RefreshTokens(tokens)
    CharacterModifier.InvalidateMovementCarrierIndex()

    local tokenIds = {}
    local seen = {}
    for _, token in ipairs(tokens) do
        if token ~= nil and token.valid and not seen[token.charid] then
            seen[token.charid] = true
            tokenIds[#tokenIds+1] = token.charid
        end
    end
    if #tokenIds > 0 then
        game.Refresh{ tokens = tokenIds }
    end
end

local function RemoveCarrierEffectInstances(instances, refreshTokens)
    local byToken = {}
    for _, instance in ipairs(instances) do
        local entry = byToken[instance.token.id]
        if entry == nil then
            entry = {
                token = instance.token,
                seqs = {},
            }
            byToken[instance.token.id] = entry
            refreshTokens[#refreshTokens+1] = instance.token
        end
        entry.seqs[#entry.seqs+1] = instance.seq
    end

    for _, entry in pairs(byToken) do
        local token = entry.token
        local seqs = entry.seqs
        token:ModifyProperties{
            description = "Change movement passenger",
            combine = true,
            execute = function()
                for _, seq in ipairs(seqs) do
                    token.properties:RemoveOngoingEffectBySeq(seq)
                end
                token.properties:Invalidate()
            end,
        }
    end
end

function ActivatedAbilityMovementCarrierBehavior:Cast(ability, casterToken, targets, options)
    local targetToken = nil
    for _, target in ipairs(targets or {}) do
        if target.token ~= nil and target.token.valid and target.token.properties ~= nil then
            targetToken = target.token
            break
        end
    end

    if targetToken == nil or casterToken == nil or not casterToken.valid or casterToken.properties == nil or
       targetToken.id == casterToken.id then
        return
    end

    local effectId = self:try_get("ongoingEffect", "none")
    local effectInfo = (dmhub.GetTable(CharacterOngoingEffect.tableName) or {})[effectId]
    if effectInfo == nil then
        ability.RecordTokenMessage(targetToken, options, "Movement carrier effect is not configured")
        return
    end

    if effectInfo:try_get("casterTracking", "none") ~= "one" then
        ability.RecordTokenMessage(targetToken, options, "Movement carrier effect must use one-caster tracking")
        return
    end

    local grabRange = tonumber(casterToken.properties:CalculateNamedCustomAttribute("Grab Range")) or 1
    if casterToken:Distance(targetToken) > grabRange then
        ability.RecordTokenMessage(targetToken, options, "Target is outside grab range")
        return
    end

    local instances, excludedMovementTargets, selectedOwned = FindCarrierEffectInstances(
        effectId,
        casterToken.id,
        targetToken
    )
    local refreshTokens = { casterToken }

    if selectedOwned then
        ability:CommitToPaying(casterToken, options)
        ability.RecordTokenMessage(targetToken, options, "Released")
        RemoveCarrierEffectInstances(instances, refreshTokens)
        RefreshTokens(refreshTokens)
        return
    end

    local capacityUsed = CharacterModifier.CountMovementCarrierCapacity(
        casterToken.properties,
        excludedMovementTargets
    )
    local maximum = tonumber(casterToken.properties:CalculateNamedCustomAttribute("Maximum Grabbed Creatures")) or 1
    if capacityUsed >= maximum then
        ability.RecordTokenMessage(targetToken, options, "Cannot carry another creature")
        return
    end

    ability:CommitToPaying(casterToken, options)
    RemoveCarrierEffectInstances(instances, refreshTokens)

    local sourceDescription = string.format(
        "Applied by %s's <b>%s</b> ability",
        creature.GetTokenDescription(casterToken),
        ability.name
    )
    refreshTokens[#refreshTokens+1] = targetToken
    ability.RecordTokenMessage(targetToken, options, string.format("Apply %s", effectInfo.name))
    targetToken:ModifyProperties{
        description = "Assign movement passenger",
        combine = true,
        execute = function()
            targetToken.properties:ApplyOngoingEffect(effectId, nil, {
                tokenid = casterToken.id,
                abilityName = ability.name,
            }, {
                sourceDescription = sourceDescription,
            })
            targetToken.properties:Invalidate()
        end,
    }

    RefreshTokens(refreshTokens)
end
