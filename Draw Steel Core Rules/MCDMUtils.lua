local mod = dmhub.GetModLoading()

MCDMUtils = {
    GetStandardAbility = function(nameorid)
        local abilityTable = dmhub.GetTable("standardAbilities")
        if abilityTable[nameorid] then
            return abilityTable[nameorid]
        end
        local name = string.lower(nameorid)
        for key,ability in unhidden_pairs(abilityTable) do
            if string.lower(ability.name) == name then
                return ability
            end
        end
    
        return nil
    end
}

MCDMUtils.DeepReplace = function(node, from, to)
    if type(node) ~= "table" then
        return
    end

    for k,v in pairs(node) do
        if v == from then
            node[k] = to
        elseif type(v) == "string" then
            node[k] = regex.ReplaceAll(v, from, to)
        else
            MCDMUtils.DeepReplace(v, from, to)
        end
    end
end