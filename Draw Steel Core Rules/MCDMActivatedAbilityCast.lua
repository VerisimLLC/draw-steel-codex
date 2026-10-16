local mod = dmhub.GetModLoading()

ActivatedAbilityCast.boonsApplied = 0
ActivatedAbilityCast.banesApplied = 0
ActivatedAbilityCast.potencyApplied = {}

function ActivatedAbilityCast:SetPotencyApplied(targetToken, potency)
	self.potencyApplied = self:get_or_add("potencyApplied", {})
	self.potencyApplied[targetToken.charid] = potency
end

--Kill tracking behind Cast.Kills / Cast.Killed. killCount is the total for the
--cast; killTable maps a victim token's charid to its kill count (one minion hit
--can empty several single-minion bands of the squad pool, so it can exceed 1).
ActivatedAbilityCast.killCount = 0

--- Credits this cast with killing count creatures via damage against victim.
--- Called from creature.TakeDamage (MCDMCreature.lua) synchronously as the
--- damage lands, so behaviors later in the same ability can read the result.
--- Objects are not creatures and are never counted.
--- @param victim creature the creature whose damage caused the kill(s)
--- @param count number kills to credit (minions: bands emptied; others: 1)
function ActivatedAbilityCast:RecordKill(victim, count)
	if count == nil or count <= 0 then
		return
	end
	local tok = dmhub.LookupToken(victim)
	if tok == nil or tok.isObject then
		return
	end
	self.killCount = self.killCount + count
	local killTable = self:get_or_add("killTable", {})
	killTable[tok.charid] = (killTable[tok.charid] or 0) + count
end

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Kills",
    type = "number",
    desc = "The number of creatures killed by damage from this ability so far. Each minion that dies counts as one kill. A hero only counts once actually dead, not when dying. Objects never count.",
    seealso = {"Killed", "Damage Dealt"},
    examples = {"Cast.Kills > 0", "Cast.Kills >= 2"},
    calculate = function(c)
        return c.killCount
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Killed",
    type = "function",
    desc = "Given a creature, returns true if damage from this ability killed it. For a minion, true if this ability's damage against that minion emptied at least one minion's worth of the squad's shared Stamina (the hit killed a minion, even if a different squad member is the one removed). For any other creature, true if the damage took it from alive to dead (for a monster, 0 Stamina or below; for a hero, actually dead, not just dying).",
    seealso = {"Kills", "Damage Dealt Against"},
    examples = {"Cast.Killed(Cast.Primary Target)", "Cast.Killed(Target)"},
    calculate = function(c)
        return function(target)
            if type(target) == "function" then
                target = target("self")
            end
            if type(target) ~= "table" then
                return false
            end
            local tok = dmhub.LookupToken(target)
            if tok == nil then
                return false
            end
            return (c:try_get("killTable", {})[tok.charid] or 0) > 0
        end
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Boons",
    type = "number",
    desc = "Deprecated name for Edges. The number of edges applied while using this ability.",
    deprecated = true,
    seealso = {"Edges"},
    examples = {},
    calculate = function(c)
        return c.boonsApplied
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Edges",
    type = "number",
    desc = "The number of edges applied while using this ability.",
    seealso = {"Banes"},
    examples = {"Cast.Edges > Cast.Banes", "Cast.Edges >= 1"},
    calculate = function(c)
        return c.boonsApplied
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Banes",
    type = "number",
    desc = "The number of banes applied while using this ability.",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c.banesApplied
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "PassesPotency",
    type = "function",
    desc = "Given a target, characteristic id,and a potency value, returns true if this creature passes the potency check for that characteristic. If not given a potency value uses Power Roll tier outcome 1 = weak, 2 = average, 3 = strong",
    seealso = {},
    examples = {'Cast.PassessPotency(Target, "P", "Strong")', 'Cast.PassesPotency(Target, "M")'},
    calculate = function(c)
        local casterToken = dmhub.GetTokenById(c.casterid)
        if casterToken == nil then
            return function() return false end
        end
        local caster = casterToken.properties
        return function(target, characteristicid, potency)
            local targetToken = dmhub.LookupToken(target)
            if targetToken == nil then
                return false
            end
            local targetid = targetToken.charid
            local potencyApplied = c.potencyApplied and c.potencyApplied[targetid] or 0
            local value = caster:Potency()
            if potency ~= nil and type(potency) == "string" then
                value = caster:CalculatePotencyValue(potency)
            elseif potency ~= nil and type(potency) == "number" then
                value = potency
            else
                if c.tier == 1 then
                    value = value - 2
                elseif c.tier == 2 then
                    value = value - 1
                end
            end

            value = value + potencyApplied

            local attrid = GameSystem.AttributeByFirstLetter[string.lower(characteristicid)] or "-"

            local result = (target:AttributeForPotencyResistance(attrid) or 0) >= (value or 0)
            return result
        end
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "OngoingEffectsPurgedChosen",
    type = "table",
    desc = "A list of ongoing effect IDs the player chose to purge ('Chosen Effects' or 'One Chosen Effect' purge type) during this ability cast.",
    seealso = {},
    examples = {"Cast.OngoingEffectsPurgedChosen"},
    calculate = function(c)
        return c:try_get("purgedOngoingEffectsChosen", {})
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Has Rolled Damage",
    type = "boolean",
    desc = "True if this ability cast dealt damage from a dice roll rather than flat damage.",
    seealso = {},
    examples = {"Cast.Has Rolled Damage"},
    calculate = function(c)
        return c.hasRolledDamage
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "NumAttackers",
    type = "function",
    desc = "Given a target, returns the number of creatures attacking that target during this ability. Generally used for Minion attacks.",
    seealso = {},
    examples = {"Cast.NumAttackers(Target) > 1", "Cast.NumAttackers(Target)"},
    calculate = function(c)
        return function(target)
            local targetToken = dmhub.LookupToken(target)
            if targetToken == nil then
                return 1
            end
            local targets = c:try_get("targets")
            if targets == nil then
                return 1
            end
            for _, t in ipairs(targets) do
                if t.token ~= nil and t.token.id == targetToken.charid then
                    return t.numAttackers or 1
                end
            end
            return 1
        end
    end,
}