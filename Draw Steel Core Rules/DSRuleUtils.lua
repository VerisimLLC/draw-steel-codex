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
}
