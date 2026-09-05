local mod = dmhub.GetModLoading()

RuleUtils = {
    HasLineOfEffect = function(toka, tokb)
        --Honor a per-creature line-of-effect square cap (the "Line Of Effect Limit"
        --custom attribute, used by the Dazzled condition). When > 0 on either
        --token, sight is severed once the two tokens are more than that many
        --squares apart -- it doesn't matter which side has the limit, because
        --LoE is mutual.
        local distance
        local function checkLimit(tok)
            if tok == nil or tok.properties == nil then return true end
            local limit = tok.properties:CalculateNamedCustomAttribute("Line Of Effect Limit")
            if limit <= 0 then return true end
            distance = distance or toka:Distance(tokb)
            return distance <= limit
        end
        if not checkLimit(toka) or not checkLimit(tokb) then
            return false
        end

        local pierceWalls = (toka.properties ~= nil) and toka.properties:GetPierceWalls() or 0
        local coverInfo = dmhub.GetCoverInfo(toka, tokb, pierceWalls)
        return coverInfo == nil or coverInfo.coverModifier < 1
    end,

    --Prompt shown when a retarget picker (Goaded, Meat Shield) is limited to the
    --original strike's range. Names the striker and its reach so the player can
    --see why some tokens are greyed out.
    RetargetPromptText = function(sourceToken, range, rangeType)
        if rangeType ~= "ability" or sourceToken == nil or not sourceToken.valid then
            return "Choose a new target for the strike"
        end
        local sourceName = "the attacker"
        if sourceToken.canLocalPlayerSeeName and sourceToken.name ~= nil and sourceToken.name ~= "" then
            sourceName = sourceToken.name
        end
        range = tonumber(range)
        if range == nil or range <= 0 then
            return string.format("Choose a new target within %s's line of effect", sourceName)
        end
        local rangeText = tostring(range)
        if range == math.floor(range) then
            rangeText = tostring(math.floor(range))
        end
        local unit = "squares"
        if range == 1 then unit = "square" end
        return string.format("Choose a new target within %s %s and line of effect of %s", rangeText, unit, sourceName)
    end,

    --Greys out retarget candidates the striker could not actually hit. Adds a
    --tooltip to `reasons` (charid -> text, the shape changeTargetReasonedFilters
    --uses) for any target beyond `range` squares or with no line of effect.
    AddRetargetRangeReasons = function(targets, reasons, sourceToken, range)
        if sourceToken == nil or not sourceToken.valid then
            return
        end
        local sourceName = "The attacker"
        if sourceToken.canLocalPlayerSeeName and sourceToken.name ~= nil and sourceToken.name ~= "" then
            sourceName = sourceToken.name
        end
        range = tonumber(range)
        --whole-number ranges print as "5", not "5.0".
        local rangeText = tostring(range)
        if range ~= nil and range == math.floor(range) then
            rangeText = tostring(math.floor(range))
        end
        for _, tok in ipairs(targets) do
            if reasons[tok.charid] == nil and tok.valid and tok.charid ~= sourceToken.charid then
                if range ~= nil and range > 0 and sourceToken:Distance(tok) > range then
                    reasons[tok.charid] = string.format("%s's strike can only reach targets within %s squares.", sourceName, rangeText)
                elseif not RuleUtils.HasLineOfEffect(sourceToken, tok) then
                    reasons[tok.charid] = string.format("%s has no line of effect to this creature.", sourceName)
                end
            end
        end
    end,
}
