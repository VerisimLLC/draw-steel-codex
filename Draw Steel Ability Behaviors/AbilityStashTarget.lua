local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityStashTargetBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityStashTargetBehavior
--- Remembers the ability's (first) target on the caster so a custom trigger fired later in the
--- same cast can ask about it with the "Stashed Target" GoblinScript symbol (the trigger system
--- only passes a name and a number). Used by the Shadow's "You Were Watching the Wrong One".
ActivatedAbilityStashTargetBehavior = RegisterGameType("ActivatedAbilityStashTargetBehavior", "ActivatedAbilityBehavior")

--Caster charid -> charid of the target its latest Remember Target stored. Kept here rather
--than in a _tmp_ field on the creature because the engine clears every _tmp_ field when it
--rebuilds the map's auras, which can happen in the middle of a cast.
--- @type table<string, string>
local g_stashedTargets = {}

ActivatedAbility.RegisterType{
    id = 'stash_target',
    text = 'Remember Target',
    createBehavior = function()
        return ActivatedAbilityStashTargetBehavior.new{
            applyto = "targets",
        }
    end,
}

ActivatedAbilityStashTargetBehavior.summary = 'Remember Target'

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
function ActivatedAbilityStashTargetBehavior:Cast(ability, casterToken, targets, options)
    for _, target in ipairs(targets) do
        if target.token ~= nil then
            g_stashedTargets[casterToken.charid] = target.token.charid
            return
        end
    end
end

--- @param parentPanel Panel
--- @return Panel[]
function ActivatedAbilityStashTargetBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    return result
end

creature.RegisterSymbol{
    symbol = "stashedtarget",
    lookup = function(c)
        local casterid = dmhub.LookupTokenId(c)
        local id = casterid ~= nil and g_stashedTargets[casterid] or nil
        if id == nil then
            return nil
        end
        local tok = dmhub.GetTokenById(id)
        if tok == nil or not tok.valid then
            return nil
        end
        return tok.properties
    end,
    help = {
        name = "Stashed Target",
        type = "creature",
        desc = "The target this creature's most recent Remember Target behavior stored.",
        seealso = {},
    },
}
