local mod = dmhub.GetModLoading()

ActivatedAbilityCast.boonsApplied = 0
ActivatedAbilityCast.banesApplied = 0
ActivatedAbilityCast.potencyApplied = {}

function ActivatedAbilityCast:SetPotencyApplied(targetToken, potency)
	self.potencyApplied = self:get_or_add("potencyApplied", {})
	self.potencyApplied[targetToken.charid] = potency
end

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Boons",
    type = "number",
    desc = "The number of boons applied while using this ability.",
    seealso = {},
    examples = {},
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
        local caster = casterToken:GetCreature()
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