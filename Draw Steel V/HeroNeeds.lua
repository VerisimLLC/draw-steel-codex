local mod = dmhub.GetModLoading()

--Why a player is needed right now: a trigger waiting, a saving throw, a
--roll the game asked for, or a turn the Heroes can claim. The Hero sheet and
--EotW's top bar both ask these. Each check reads live state, so callers poll
--it (triggers expire by time without any write).

HeroNeeds = rawget(_G, "HeroNeeds") or {}

--- Has this creature a trigger waiting (not hostile, not dismissed, not
--- already used)?
--- @param hero creature
--- @return boolean
function HeroNeeds.HasTrigger(hero)
    for _,t in pairs(hero:GetAvailableTriggers(true) or {}) do
        if not t.hostile and not t.dismissed and not t.triggered then
            return true
        end
    end
    return false
end

--- Has this creature an end-of-turn saving throw waiting (the card is up,
--- or it was accepted and is still rolling)?
--- @param hero creature
--- @return boolean
function HeroNeeds.HasSave(hero)
    for _,t in pairs(hero:GetAvailableTriggers(true) or {}) do
        local inv = t.invocation
        if not t.dismissed and inv ~= nil and inv ~= false and inv:try_get("standardAbility") == "End Turn Saving Throw" then
            return true
        end
    end
    for _,e in pairs(hero:try_get("pendingAIActivityReactions", {})) do
        if type(e) == "table" and e.activityId == "end-turn-save" and e.state ~= "completed" then
            return true
        end
    end
    return false
end

--- Is the game waiting on this character for a roll: a roll request not
--- yet done, or an EotW montage test in its hands?
--- @param charid string
--- @return boolean
function HeroNeeds.HasRoll(charid)
    for _,req in pairs(dmhub.GetPlayerActionRequests() or {}) do
        local info = req.info
        if info ~= nil and info.typeName == "RollRequest" and info.tokens ~= nil then
            local entry = info.tokens[charid]
            if entry ~= nil and entry.status ~= "complete" then
                return true
            end
        end
    end
    local montage = rawget(_G, "EncounterMontage")
    if montage ~= nil then
        local turn = nil
        pcall(function() turn = montage.GetState().turn end)
        if type(turn) == "table" then
            if turn.status == "rolling" and turn.heroid == charid then
                return true
            elseif turn.status == "pardon" and turn.pardon ~= nil and turn.pardon.heroid == charid then
                return true
            end
        end
    end
    return false
end

--- Can the Heroes' side claim the next turn with this character taking it?
--- @param charid string
--- @return boolean
function HeroNeeds.CanAct(charid)
    local result = false
    pcall(function()
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden or not q:ChoosingTurn() or not q:IsPlayersTurn() then
            return
        end
        local tok = dmhub.GetCharacterById(charid)
        local id = tok ~= nil and InitiativeQueue.GetInitiativeId(tok) or nil
        result = id ~= nil and InitiativeQueue.CanClaimTurn(id, { canControlInitiative = false })
    end)
    return result
end

--- What a character is needed for, most urgent first: "trigger", "save",
--- "roll", "turn", or nil. Each check is guarded: a token mid-update must not
--- break the caller's poll.
--- @param tok CharacterToken
--- @return nil|string
function HeroNeeds.Need(tok)
    local hero = tok.properties
    if hero == nil then
        return nil
    end
    local trigger, save, roll = false, false, false
    pcall(function() trigger = HeroNeeds.HasTrigger(hero) end)
    if trigger then
        return "trigger"
    end
    pcall(function() save = HeroNeeds.HasSave(hero) end)
    if save then
        return "save"
    end
    pcall(function() roll = HeroNeeds.HasRoll(tok.charid) end)
    if roll then
        return "roll"
    end
    if HeroNeeds.CanAct(tok.charid) then
        return "turn"
    end
    return nil
end
