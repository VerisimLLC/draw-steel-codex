local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('invisibility', "Invisibility")

CharacterModifier.TypeInfo.invisibility = {
    init = function(modifier)
    end,

    onTokenRefresh = function(modifier, creature, token)
        -- Invisible creatures always have concealment from other creatures.
        creature._tmp_concealed = true
        --stamp the update so the next modifier-list rebuild, which runs before
        --OnTokenRefresh, still counts invisibility toward "Concealed" when
        --evaluating filterConditions. See creature:GetActiveModifiers.
        creature._tmp_concealedInvisibleUpdate = dmhub.ngameupdate
    end,

    createEditor = function(modifier, element)
    end,

}