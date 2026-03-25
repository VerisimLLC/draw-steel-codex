local mod = dmhub.GetModLoading()

RuleUtils = {
    HasLineOfEffect = function(toka, tokb)
        local pierceWalls = (toka.properties ~= nil) and toka.properties:GetPierceWalls() or 0
        local coverInfo = dmhub.GetCoverInfo(toka, tokb, pierceWalls)
        return coverInfo == nil or coverInfo.coverModifier < 1
    end,
}