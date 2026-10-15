local mod = dmhub.GetModLoading()

--Throw Object: moves a map object to the square the ability targeted, e.g. a
--creature throwing the Candelabra standing next to it. The object thrown is
--the one granting the ability (grantedToAdjacentCreatures, see
--ActivatedAbility.GetGrantedAbilitiesFrom), or the caster itself when the
--caster is an object (an operated ability).
--
--The ability's own targeting decides where it can land: give it a square
--target type (Empty Space / Any Space) and a range. Square targeting only
--offers squares the caster has line of effect to, so the object can't be
--thrown through walls.
--
--The object moves through the engine's object move (token:Move on an object
--token -> ObjectComponentTargetable.MovePath), so it needs a Targetable
--component, and it slides to the square on every client. It stays on its own
--floor.

--- @class ActivatedAbilityThrowObjectBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityThrowObjectBehavior
ActivatedAbilityThrowObjectBehavior = RegisterGameType("ActivatedAbilityThrowObjectBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityThrowObjectBehavior.summary = 'Throw Object'

ActivatedAbility.RegisterType
{
    id = 'throw_object',
    text = 'Throw Object',
    createBehavior = function()
        return ActivatedAbilityThrowObjectBehavior.new{
        }
    end
}

function ActivatedAbilityThrowObjectBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Throw the object to the target square"
end

--The object token this ability throws, or nil.
--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @return nil|CharacterToken
local function ThrownObjectToken(ability, casterToken)
    local grantingid = ability:try_get("grantingObjectTokenId")
    if grantingid ~= nil then
        local tok = dmhub.GetTokenById(grantingid)
        if tok ~= nil and tok.valid and tok.isObject then
            return tok
        end
        return nil
    end
    if casterToken ~= nil and casterToken.valid and casterToken.isObject then
        return casterToken
    end
    return nil
end

function ActivatedAbilityThrowObjectBehavior:Cast(ability, casterToken, targets, options)
    local objectToken = ThrownObjectToken(ability, casterToken)
    local target = targets[#targets]
    local dest = target ~= nil and target.loc or nil
    if objectToken == nil or dest == nil then
        print("ThrowObject:: nothing to throw -- object =", objectToken, "dest =", dest, "ability =", ability.name)
        return
    end

    ability:CommitToPaying(casterToken, options)

    --the path only has to reach the square: the object slides there in a
    --straight line whatever route the path took.
    local path = objectToken:Move(dest, { ignorecreatures = true, freeMovement = true, maxCost = 30000 })
    if path == nil then
        print("ThrowObject:: MOVE REFUSED -- object did not move. dest =", dest.str, "ability =", ability.name)
        return
    end

    --A throw counts as forced movement for the object's own "Force Moved"
    --triggers, so "takes damage equal to the squares moved" covers being
    --thrown as well as pushed (exploding barrels). Wait for the object to
    --land first: its location only updates once the slide finishes, and a
    --trigger that destroys it should go off where it landed.
    if coroutine.running() ~= nil then
        local landBy = dmhub.Time() + 3
        while objectToken.valid and objectToken.loc.str ~= path.destination.str and dmhub.Time() < landBy do
            coroutine.yield(0.05)
        end
    end
    if not objectToken.valid or objectToken.properties == nil then
        return
    end

    --The thrower: the creature using a granted throw, or whoever is
    --operating the object when it throws itself.
    local thrower = ability:GetOperatorToken()
    if thrower == nil and casterToken.charid ~= objectToken.charid then
        thrower = casterToken
    end

    objectToken.properties:DispatchEvent("forcemove", {
        attacker = thrower ~= nil and thrower.properties or nil,
        hasattacker = thrower ~= nil,
        type = "throw",
        vertical = false,
        collision = 0,
        collidewithobject = false,
        distance = math.floor(path.numSteps or 0),
        melee = false,
    })
end

function ActivatedAbilityThrowObjectBehavior:EditorItems(parentPanel)
    local result = {}
    result[#result+1] = gui.Label{
        classes = {"formLabel"},
        width = "100%",
        height = "auto",
        textWrap = true,
        text = "Moves the object granting this ability (or the caster, if it is an object) to the target square. Use a square target type and set the range on the ability.",
    }
    return result
end
