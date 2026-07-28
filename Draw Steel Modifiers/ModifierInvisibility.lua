local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('invisibility', "Invisibility")

CharacterModifier.TypeInfo.invisibility = {
    init = function(modifier)
    end,

    onTokenRefresh = function(modifier, creature, token)
        -- Invisible creatures always have concealment from other creatures.
        creature._tmp_concealed = true
    end,

    createEditor = function(modifier, element)
    end,

}