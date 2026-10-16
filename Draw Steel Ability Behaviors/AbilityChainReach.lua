local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityChainReachBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityChainReachBehavior
--- Spreads an ability's targeting outward from its first target: every enemy of the caster
--- within `chainRange` squares of any creature already targeted is added, repeating until no
--- new creature is in reach (Shadow "Chain Reaction"). Later behaviors (the power roll) then
--- roll against every creature added, because the list is extended in place.
--- @field chainRange number Squares between one link and the next.
ActivatedAbilityChainReachBehavior = RegisterGameType("ActivatedAbilityChainReachBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType{
    id = 'chain_reach',
    text = 'Chain To Nearby Enemies',
    createBehavior = function()
        return ActivatedAbilityChainReachBehavior.new{
            applyto = "caster",
        }
    end,
}

ActivatedAbilityChainReachBehavior.summary = 'Chain To Nearby Enemies'
ActivatedAbilityChainReachBehavior.chainRange = 3

--True if the chain may jump from `source` to `cand`: same floor, within range, and with
--line of effect from source's square. A wall, or a creature that blocks the caster's line
--of effect, stops the jump just as it would stop the caster targeting cand directly.
--- @param casterToken CharacterToken
--- @param source CharacterToken
--- @param cand CharacterToken
--- @param range number
--- @return boolean
local function CanChainTo(casterToken, source, cand, range)
    if cand.floorid ~= source.floorid or source:Distance(cand) > range then
        return false
    end
    if source:GetLineOfSight(cand, casterToken.properties:GetPierceWalls()) <= 0 then
        return false
    end
    --The jump starts inside source's own square, so source never blocks it.
    local blocker = RuleUtils.LineOfEffectBlocker(casterToken, cand, source.loc)
    return blocker == nil or blocker.charid == source.charid
end

--- Works out which enemies the chain reaches from a starting creature.
--- Returns the newly reached tokens (not including the start) and the links drawn between
--- them: { from = token, to = token } for each creature and the one that reached it.
--- Shared by the cast and by the action bar's hover preview.
--- Only enemies the caster could target are reached: Hidden creatures (against a non-Area
--- ability), Untargetable ones, and creatures the Director has hidden from players are skipped.
--- @param casterToken CharacterToken
--- @param startToken CharacterToken
--- @param range number
--- @param alreadyTargeted nil|table set of charids that are already targets
--- @param ability nil|ActivatedAbility the chaining ability, for the targeting rules
--- @return CharacterToken[], table[]
function ActivatedAbilityChainReachBehavior.ComputeChain(casterToken, startToken, range, alreadyTargeted, ability)
    local included = { [startToken.charid] = true }
    for id,_ in pairs(alreadyTargeted or {}) do
        included[id] = true
    end

    local candidates = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.valid and (not included[tok.charid]) and tok.charid ~= casterToken.charid
           and (not tok:IsFriend(casterToken)) and (not tok.properties:IsDead())
           and (dmhub.isDM or not tok.invisibleToPlayers)
           and tok.properties:CalculateNamedCustomAttribute("Untargetable") <= 0
           and (ability == nil or GameSystem.AllowTargeting(casterToken, tok, ability)) then
            candidates[#candidates+1] = tok
        end
    end

    local reached = {}
    local links = {}
    local frontier = { startToken }

    --Breadth-first spread: each newly added creature may reach more candidates.
    while #frontier > 0 do
        local nextFrontier = {}
        for _, source in ipairs(frontier) do
            for i = #candidates, 1, -1 do
                local cand = candidates[i]
                if CanChainTo(casterToken, source, cand, range) then
                    table.remove(candidates, i)
                    nextFrontier[#nextFrontier+1] = cand
                    reached[#reached+1] = cand
                    links[#links+1] = { from = source, to = cand }
                end
            end
        end
        frontier = nextFrontier
    end

    return reached, links
end

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
function ActivatedAbilityChainReachBehavior:Cast(ability, casterToken, targets, options)
    local list = options.targets
    if list == nil or #list == 0 then
        return
    end

    local range = tonumber(self:try_get("chainRange", 3)) or 3
    local alreadyTargeted = {}
    local startToken = nil
    for _, t in ipairs(list) do
        if t.token ~= nil then
            alreadyTargeted[t.token.charid] = true
            startToken = startToken or t.token
        end
    end
    if startToken == nil then
        return
    end

    local reached, links = ActivatedAbilityChainReachBehavior.ComputeChain(casterToken, startToken, range, alreadyTargeted, ability)
    for _, tok in ipairs(reached) do
        list[#list+1] = { token = tok }
    end

    if options.symbols ~= nil and options.symbols.cast ~= nil then
        options.symbols.cast.targets = list
    end

    if #reached == 0 then
        return
    end

    ability:CommitToPaying(casterToken, options)

    --Show the chained creatures on the action log card too.
    local message = options.chatMessage
    if message ~= nil and message.targetids ~= nil then
        local listed = {}
        for _, id in ipairs(message.targetids) do
            listed[id] = true
        end
        for _, tok in ipairs(reached) do
            if not listed[tok.charid] then
                message.targetids[#message.targetids+1] = tok.charid
            end
        end
        chat.UpdateCustom(options.chatMessageKey, message)
    end

    --Draw red links between the chained creatures until the cast is over.
    local rays = {}
    for _, link in ipairs(links) do
        local ray = dmhub.HighlightLine{ color = "red", a = link.from.pos, b = link.to.pos }
        if ray ~= nil then
            rays[#rays+1] = ray
        end
    end
    if #rays > 0 then
        options.OnFinishCastHandlers = options.OnFinishCastHandlers or {}
        options.OnFinishCastHandlers[#options.OnFinishCastHandlers+1] = function()
            for _, ray in ipairs(rays) do
                pcall(function() ray:Destroy() end)
            end
        end
    end
end

--- @param parentPanel Panel
--- @return Panel[]
function ActivatedAbilityChainReachBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Chain Range:" },
        gui.Input{
            classes = { "formInput" },
            text = tostring(self:try_get("chainRange", 3)),
            change = function(element)
                self.chainRange = tonumber(element.text) or 3
                element.text = tostring(self.chainRange)
            end,
        },
    }
    return result
end
