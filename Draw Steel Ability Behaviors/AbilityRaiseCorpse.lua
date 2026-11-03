local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRaiseCorpseBehavior: ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityRaiseCorpseBehavior
ActivatedAbilityRaiseCorpseBehavior = RegisterGameType("ActivatedAbilityRaiseCorpseBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'raise_corpse',
	text = 'Raise Corpse',
	createBehavior = function()
		return ActivatedAbilityRaiseCorpseBehavior.new{
		}
	end
}

ActivatedAbilityRaiseCorpseBehavior.summary = 'Raise Corpse'
ActivatedAbilityRaiseCorpseBehavior.restoreStamina = true

function ActivatedAbilityRaiseCorpseBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Raise Corpse"
end

--Minions share one squad Stamina pool, derived from the member carrying the
--highest damage_taken_seq (RefreshSquadInfo in MCDMCreature.lua). Resetting a
--raised minion's own damage_taken leaves that record, and the deaths it owed,
--in force, so the raised minions came back showing death skulls. This reads
--the squad's pool before the raise: its live members (excluding the minion
--being raised), their current pool damage and the highest seq seen.
local function SquadPoolBeforeRaise(squadName, raisedToken)
    local pool = {live = {}, raised = {}, damage = 0, seq = 0}
    local raisedSquad = raisedToken.properties:try_get("_tmp_minionSquad")
    if raisedSquad ~= nil then
        pool.seq = raisedSquad.damage_taken_seq or 0
    end
    for _, tok in ipairs(dmhub.GetTokens{ haveProperties = true }) do
        local props = tok.properties
        if tok.valid and tok.charid ~= raisedToken.charid and props.minion and (not props.minionDead) and props:MinionSquad() == squadName then
            pool.live[#pool.live+1] = tok
            pool.seq = math.max(pool.seq, props:try_get("damage_taken_seq", 0))
            local squad = props:try_get("_tmp_minionSquad")
            if squad ~= nil then
                pool.damage = squad.damage_taken or 0
                pool.seq = math.max(pool.seq, squad.damage_taken_seq or 0)
            end
        end
    end
    return pool
end

function ActivatedAbilityRaiseCorpseBehavior:Cast(ability, casterToken, targets, options)
    local tokenids = {}
    local added = false
    local squadPools = {}
    for i,target in ipairs(targets) do
        local creatureToken = nil
        local charid = nil
        if target.token ~= nil and target.token.isCorpse and target.token.objectInstance ~= nil then
            local object = target.token.objectInstance
            local corpse = object:GetComponent("Corpse")
            if corpse ~= nil then
                creatureToken = corpse.properties:DeadCreatureToken()
                charid = corpse.properties.charid
                if creatureToken ~= nil then
                    if self.restoreStamina and creatureToken.properties.minion then
                        local squadName = creatureToken.properties:MinionSquad()
                        if squadName ~= nil then
                            if squadPools[squadName] == nil then
                                squadPools[squadName] = SquadPoolBeforeRaise(squadName, creatureToken)
                            end
                            local pool = squadPools[squadName]
                            pool.raised[#pool.raised+1] = creatureToken
                            pool.seq = math.max(pool.seq, creatureToken.properties:try_get("damage_taken_seq", 0))
                        end
                    end
                    creatureToken:ModifyProperties{
                        description = "Raised",
                        execute = function()
                            if self.restoreStamina then
                                creatureToken.properties.damage_taken = 0
                                creatureToken.properties.inflictedConditions = {}
                            end
                            creatureToken.properties.activeOngoingEffects = {}
                        end
                    }
                    creatureToken.despawned = false
                    object:Destroy()
                else
                    print("Corpse:: could not find creature token")
                end

            else
                print("Corpse:: no corpse component found on object")
            end
        else
            print("Corpse:: target is not a corpse")
        end

        if creatureToken ~= nil then
            tokenids[i] = charid
            added = true
        end
    end

    if not added then
        print("Corpse:: No corpses found to raise")
        return
    end

    ability:CommitToPaying(casterToken, options)

    --The raised minions return at full Stamina, so the pool keeps only the
    --survivors' damage (none if the whole squad had died), spread over the new
    --member count. A fresh seq makes this record win over the old one.
    for _, pool in pairs(squadPools) do
        local damage = #pool.live > 0 and pool.damage or 0
        local seq = pool.seq + 1
        local count = #pool.live + #pool.raised
        local members = {}
        for _, tok in ipairs(pool.live) do
            members[#members+1] = tok
        end
        for _, tok in ipairs(pool.raised) do
            members[#members+1] = tok
        end
        for _, tok in ipairs(members) do
            tok:ModifyProperties{
                description = "Raised minion rejoins squad",
                combine = true,
                undoable = false,
                execute = function()
                    tok.properties.damage_taken = damage
                    tok.properties.damage_taken_seq = seq
                    tok.properties.damage_taken_minion_count = count
                end,
            }
        end
    end

    game.UpdateCharacterTokens()
    coroutine.yield(0.1)

    for i,target in ipairs(targets) do
        local charid = tokenids[i]
        if charid ~= nil then
            local token = dmhub.GetTokenById(charid)
            if token ~= nil then
                target.token = token
                print("Corpse:: found token", charid)
            else
                print("Corpse:: Could not find token with charid", charid)
            end
        end
    end
end

function ActivatedAbilityRaiseCorpseBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Check{
        text = "Restore Stamina",
        value = self.restoreStamina,
        change = function(element)
            self.restoreStamina = element.value
        end,
    }

    return result
end