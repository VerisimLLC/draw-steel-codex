local mod = dmhub.GetModLoading()

--Why a player is needed right now: a trigger waiting, a saving throw, a
--roll the game asked for, or a turn the Heroes can claim. The Hero sheet and
--EotW's top bar both ask these. Each check reads live state, so callers poll
--it (triggers expire by time without any write).

HeroNeeds = rawget(_G, "HeroNeeds") or {}

--- The ids of this creature's waiting triggers (not hostile, not dismissed,
--- not already used), sorted. A new id means a new trigger arrived.
--- @param hero creature
--- @return string[]
function HeroNeeds.TriggerIds(hero)
    local ids = {}
    for id,trigger in pairs(hero:GetAvailableTriggers(true) or {}) do
        if not trigger.hostile and not trigger.dismissed and not trigger.triggered then
            ids[#ids+1] = tostring(id)
        end
    end
    table.sort(ids)
    return ids
end

--- Has this creature a trigger waiting?
--- @param hero creature
--- @return boolean
function HeroNeeds.HasTrigger(hero)
    return #HeroNeeds.TriggerIds(hero) > 0
end

--- The ids of this creature's end-of-turn saving throws still waiting (the
--- card is up, or it was accepted and is still rolling), sorted. A save card
--- is also a trigger, so its id appears in TriggerIds too.
--- @param hero creature
--- @return string[]
function HeroNeeds.SaveIds(hero)
    local ids = {}
    for id,trigger in pairs(hero:GetAvailableTriggers(true) or {}) do
        local inv = trigger.invocation
        if not trigger.dismissed and inv ~= nil and inv ~= false and inv:try_get("standardAbility") == "End Turn Saving Throw" then
            ids[#ids+1] = tostring(id)
        end
    end
    for id,reaction in pairs(hero:try_get("pendingAIActivityReactions", {})) do
        if type(reaction) == "table" and reaction.activityId == "end-turn-save" and reaction.state ~= "completed" then
            ids[#ids+1] = tostring(id)
        end
    end
    table.sort(ids)
    return ids
end

--- Has this creature an end-of-turn saving throw waiting?
--- @param hero creature
--- @return boolean
function HeroNeeds.HasSave(hero)
    return #HeroNeeds.SaveIds(hero) > 0
end

--- The rolls the game is waiting on this character for, sorted: roll
--- requests not yet done (by request id), and an EotW montage test in its
--- hands (by beat and round, so the next test counts as new).
--- @param charid string
--- @return string[]
function HeroNeeds.RollIds(charid)
    local ids = {}
    for id,req in pairs(dmhub.GetPlayerActionRequests() or {}) do
        local info = req.info
        if info ~= nil and info.typeName == "RollRequest" and info.tokens ~= nil then
            local entry = info.tokens[charid]
            if entry ~= nil and entry.status ~= "complete" then
                ids[#ids+1] = tostring(id)
            end
        end
    end
    local montage = rawget(_G, "EncounterMontage")
    if montage ~= nil then
        ---@type table<string, any>|nil
        local state = nil
        pcall(function() state = montage.GetState() end)
        if state ~= nil and type(state.turn) == "table" then
            local turn = state.turn
            local mine = (turn.status == "rolling" and turn.heroid == charid)
                or (turn.status == "pardon" and turn.pardon ~= nil and turn.pardon.heroid == charid)
            if mine then
                ids[#ids+1] = string.format("montage:%s:%s:%s", tostring(state.beatIndex), tostring(state.round), tostring(turn.status))
            end
        end
    end
    table.sort(ids)
    return ids
end

--- Is the game waiting on this character for a roll?
--- @param charid string
--- @return boolean
function HeroNeeds.HasRoll(charid)
    return #HeroNeeds.RollIds(charid) > 0
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

--- Which turn choice is open now ("<round>:<turn>"), so a need closed at
--- one choice can come back at the next. nil when there is no initiative.
--- @return nil|string
function HeroNeeds.TurnChoiceId()
    local result = nil
    pcall(function()
        local q = dmhub.initiativeQueue
        if q ~= nil and not q.hidden then
            result = string.format("%s:%s", tostring(q.round), tostring(q.turn))
        end
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
