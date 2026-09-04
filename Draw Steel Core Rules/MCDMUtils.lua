local mod = dmhub.GetModLoading()

MCDMUtils = {
    GetStandardAbility = function(nameorid)
        local abilityTable = dmhub.GetTable("standardAbilities")
        if abilityTable[nameorid] then
            return abilityTable[nameorid]
        end
        local name = string.lower(nameorid)
        for key,ability in unhidden_pairs(abilityTable) do
            --Skip rows with no name. A corrupt/nameless entry used to make
            --string.lower throw here, which aborts every caller -- including
            --monster free strike construction, blanking out the ability list
            --of every monster in the game.
            local abilityName = ability.name
            if type(abilityName) == "string" and string.lower(abilityName) == name then
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