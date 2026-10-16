local mod = dmhub.GetModLoading()

--Swing Object: a creature shoves a hanging map object (the Incense Censer) and
--it swings like a pendulum. The object goes out up to maxDistance squares in
--a straight line, the creature may shift, then the object swings back to its
--start, the same distance out the opposite way, and back to its start again.
--Every creature whose squares the object's footprint covers along the way is
--a candidate; candidates passing hitFilter take `rule` (once per swing).
--
--The object swung is the one granting the ability (grantedToAdjacentCreatures,
--see ActivatedAbility.GetGrantedAbilitiesFrom), or the caster itself when the
--caster is an object. Give the ability targetType "self": the direction and
--distance are picked by a prompt inside the cast, restricted to the legal
--push squares (see ChooseSwing).
--
--Each leg is a straight-line object move (token:Move with straightline), so a
--leg stops early at a wall. Leg 3 is at most as long as leg 1 actually went.

--- @class ActivatedAbilitySwingObjectBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilitySwingObjectBehavior
--- @field maxDistance string GoblinScript (on the caster): most squares the first leg can go.
--- @field shiftDistance string GoblinScript (on the caster): squares the caster may shift after the first leg. 0 = no shift.
--- @field swingSpeed string GoblinScript (on the caster): slide speed of the object in squares per second.
--- @field rule string Power Table Effect rule applied to each creature hit.
--- @field hitFilter string GoblinScript evaluated on each creature in the object's path; true = hit.
ActivatedAbilitySwingObjectBehavior = RegisterGameType("ActivatedAbilitySwingObjectBehavior", "ActivatedAbilityBehavior")

ActivatedAbilitySwingObjectBehavior.summary = 'Swing Object'
ActivatedAbilitySwingObjectBehavior.maxDistance = "3"
ActivatedAbilitySwingObjectBehavior.shiftDistance = "1"
ActivatedAbilitySwingObjectBehavior.swingSpeed = "6"
ActivatedAbilitySwingObjectBehavior.rule = "10 damage; M<2, prone"
--only a creature that is BOTH prone AND smaller than 1M (Size 3) passes under.
ActivatedAbilitySwingObjectBehavior.hitFilter = 'Size >= 3 or not (Conditions has "Prone")'

ActivatedAbility.RegisterType
{
    id = 'swing_object',
    text = 'Swing Object',
    createBehavior = function()
        return ActivatedAbilitySwingObjectBehavior.new{
        }
    end
}

--the 8 straight-line directions a swing can take.
local g_directions = {
    {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1},
    {x = 1, y = 1}, {x = 1, y = -1}, {x = -1, y = 1}, {x = -1, y = -1},
}

function ActivatedAbilitySwingObjectBehavior:SummarizeBehavior(ability, creatureLookup)
    return string.format("Swing the object up to %s squares and back; creatures in its path: %s", self.maxDistance, self.rule)
end

--The object token this ability swings, or nil. Same lookup as Throw Object.
--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @return nil|CharacterToken
local function SwungObjectToken(ability, casterToken)
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

--- @param x number
--- @param y number
--- @return string
local function Key(x, y)
    return string.format("%d,%d", x, y)
end

--Squares-apart distance between two square lists (min over all pairs). A push
--is legal only while every step makes this grow.
--- @param a {x: number, y: number}[]
--- @param b {x: number, y: number}[]
--- @return number
local function FootprintDistance(a, b)
    local best = nil
    for _, p in ipairs(a) do
        for _, q in ipairs(b) do
            local d = math.max(math.abs(p.x - q.x), math.abs(p.y - q.y))
            if best == nil or d < best then
                best = d
            end
        end
    end
    return best or 0
end

--The object's footprint (its squares at the start) shifted by an offset.
--- @param footprint {x: number, y: number}[]
--- @param ox number
--- @param oy number
--- @return {x: number, y: number}[]
local function Shifted(footprint, ox, oy)
    local result = {}
    for i, sq in ipairs(footprint) do
        result[i] = {x = sq.x + ox, y = sq.y + oy}
    end
    return result
end

--Builds the squares the player can click to choose the first leg. For each
--direction and distance k, the clickable squares are the moved footprint's
--leading edge (the squares furthest along the direction): a whole edge for
--straight directions, the corner for diagonals. For a rectangular footprint
--no square belongs to two choices, so a click maps back to one swing.
--- @param objectToken CharacterToken
--- @param footprint {x: number, y: number}[]
--- @param pusherSquares {x: number, y: number}[]
--- @param maxDistance number
--- @return Loc[] candidates, table<string, {dir: {x: number, y: number}, distance: number}> choices
local function SwingCandidates(objectToken, footprint, pusherSquares, maxDistance)
    local candidates = {}
    local choices = {}
    local anchor = objectToken.loc
    for _, dir in ipairs(g_directions) do
        local prevDistance = FootprintDistance(footprint, pusherSquares)
        for k = 1, maxDistance do
            local moved = Shifted(footprint, dir.x * k, dir.y * k)
            local distance = FootprintDistance(moved, pusherSquares)
            if distance <= prevDistance then
                --this step doesn't move it further from the pusher: not a push.
                break
            end
            prevDistance = distance

            local best = nil
            for _, sq in ipairs(moved) do
                local score = sq.x * dir.x + sq.y * dir.y
                if best == nil or score > best then
                    best = score
                end
            end
            for _, sq in ipairs(moved) do
                local key = Key(sq.x, sq.y)
                if sq.x * dir.x + sq.y * dir.y == best and choices[key] == nil then
                    choices[key] = {dir = dir, distance = k}
                    candidates[#candidates + 1] = anchor:dir(sq.x - anchor.x, sq.y - anchor.y)
                end
            end
        end
    end
    return candidates, choices
end

--Prompts the caster's controller to click one of the candidate squares, using
--a throwaway pick ability restricted to them (the same _tmp_restrictLocs pick
--AbilityBuildWall and AbilityRelocateAura use). The pick is centred on the
--caster, so its range is stretched to reach the furthest candidate.
--- @param casterToken CharacterToken
--- @param candidates Loc[]
--- @param prompt string
--- @return nil|Loc
local function ChooseSquare(casterToken, candidates, prompt)
    local capturedLoc = nil

    local captureBehavior = ActivatedAbilityBehavior.new{
        instant = true,
    }
    captureBehavior.Cast = function(behaviorSelf, captureAbility, captureCasterToken, captureTargets, captureOptions)
        if captureTargets ~= nil and #captureTargets > 0 then
            capturedLoc = captureTargets[1].loc
        end
    end

    local maxDist = 1
    for _, loc in ipairs(candidates) do
        local dist = loc:DistanceInTiles(casterToken.loc)
        if dist > maxDist then
            maxDist = dist
        end
    end

    local pickAbility = ActivatedAbility.Create()
    pickAbility.name = "Swing"
    --anyspace: the object can swing over creatures.
    pickAbility.targetType = "anyspace"
    pickAbility.range = tostring((maxDist + 1) * dmhub.unitsPerSquare)
    pickAbility.numTargets = "1"
    pickAbility.countsAsCast = false
    pickAbility.skippable = true
    pickAbility.promptOverride = prompt
    pickAbility.behaviors = { captureBehavior }
    pickAbility._tmp_restrictLocs = candidates

    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(casterToken, pickAbility, casterToken, "prompt", {}, {})

    return capturedLoc
end

--Evaluates a GoblinScript number on the caster.
--- @param formula string
--- @param casterToken CharacterToken
--- @param options table
--- @param default number
--- @param reason string
--- @return number
local function EvalNumber(formula, casterToken, options, default, reason)
    local value = ExecuteGoblinScript(formula, casterToken.properties:LookupSymbol(options.symbols or {}), default, reason)
    return tonumber(value) or default
end

--- @class SwingContext
--- @field ability ActivatedAbility
--- @field behavior ActivatedAbilitySwingObjectBehavior
--- @field casterToken CharacterToken
--- @field objectToken CharacterToken
--- @field sourceToken CharacterToken Who deals the hits: the object when it has properties, else the caster.
--- @field options table
--- @field footprint {x: number, y: number}[] The object's squares at the start of the swing.
--- @field floor number
--- @field offset {x: number, y: number} Where the object is now, relative to its start.
--- @field speed number Squares per second.
--- @field hit table<string, boolean> charids already hit this swing.
--- @field originLoc Loc
--- @field originX number
--- @field originY number

--Hits every creature (not object) the footprint covers at the current offset
--that passes hitFilter and has not been hit yet this swing.
--- @param ctx SwingContext
local function ResolveHits(ctx)
    local covered = {}
    for _, sq in ipairs(Shifted(ctx.footprint, ctx.offset.x, ctx.offset.y)) do
        covered[Key(sq.x, sq.y)] = true
    end

    local victims = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.properties ~= nil and (not ctx.hit[tok.charid]) and tok.floorIndex == ctx.floor then
            for _, occ in ipairs(tok.locsOccupying or {}) do
                if covered[Key(occ.x, occ.y)] then
                    victims[#victims + 1] = tok
                    break
                end
            end
        end
    end

    if #victims == 0 then
        return
    end

    local symbols = ctx.options.symbols
    if symbols == nil or symbols.cast == nil then
        print("SwingObject:: no cast symbols; can't apply hits for", ctx.ability.name)
        return
    end

    --a transient Power Table Effect to borrow ExecuteCommand from, as
    --ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior does.
    local commandHelper = ActivatedAbilityDrawSteelCommandBehavior.new{}

    for _, tok in ipairs(victims) do
        local filterSymbols = table.shallow_copy(symbols)
        filterSymbols.caster = GenerateSymbols(ctx.casterToken.properties)
        filterSymbols.target = GenerateSymbols(tok.properties)
        local passes = GoblinScriptTrue(ExecuteGoblinScript(ctx.behavior.hitFilter, tok.properties:LookupSymbol(filterSymbols), 1, "Swing Object Hit Filter"))
        if passes then
            ctx.hit[tok.charid] = true
            commandHelper:ExecuteCommand(ctx.ability, ctx.sourceToken, tok, ctx.options, ctx.behavior.rule)
        end
    end
end

--Waits until the object's token reports the expected square (the slide has
--landed), giving up after a short timeout so a refused move can't hang the cast.
--- @param objectToken CharacterToken
--- @param expected Loc
local function WaitForArrival(objectToken, expected)
    local waited = 0
    coroutine.yield(0.15)
    while objectToken.valid and (objectToken.loc.x ~= expected.x or objectToken.loc.y ~= expected.y) and waited < 2 do
        coroutine.yield(0.05)
        waited = waited + 0.05
    end
end

--Slides the object `steps` squares along `dir` from where it is, stopping
--early at a wall, resolving hits on each square it reaches in time with the
--slide. Returns how many squares it actually went.
--- @param ctx SwingContext
--- @param dir {x: number, y: number}
--- @param steps number
--- @param ease "linear"|"in"|"out"|"inout" The engine's slide easing (sine). "out" decelerates
--- (a pendulum swinging away from the bottom), "in" accelerates (swinging back down).
--- @return number
local function RunLeg(ctx, dir, steps, ease)
    --whoever is under the object as the leg begins.
    ResolveHits(ctx)

    if steps <= 0 or not ctx.objectToken.valid then
        return 0
    end

    local objectToken = ctx.objectToken
    local startLoc = objectToken.loc
    local goal = startLoc:dir(dir.x * steps, dir.y * steps)

    --straightline stops at walls; "Shift" keeps it from being a push (no
    --wall breaking, no forced-movement flags). The object never collides with
    --creatures. objectSpeed (squares per second) and objectEase shape the slide.
    local path = objectToken:Move(goal, {
        straightline = true,
        movementType = "Shift",
        ignorecreatures = true,
        freeMovement = true,
        maxCost = 30000,
        objectSpeed = ctx.speed,
        objectEase = ease,
    })

    local travelled = 0
    local duration = 0
    if path == nil then
        print("SwingObject:: MOVE REFUSED -- object did not move. goal =", goal.str, "ability =", ctx.ability.name)
    else
        local dest = path.destination
        travelled = math.min(steps, math.max(math.abs(dest.x - startLoc.x), math.abs(dest.y - startLoc.y)))
        duration = (path --[[@as table]]).objectSlideDuration or 0
    end

    --hit each square as the object reaches it: invert the ease curve to get
    --the fraction of the slide's duration at which it has covered i/n of the way.
    local elapsed = 0
    for i = 1, travelled do
        local p = i / travelled
        local t = p
        if ease == "out" then
            t = math.asin(p) * 2 / math.pi
        elseif ease == "in" then
            t = math.acos(1 - p) * 2 / math.pi
        elseif ease == "inout" then
            t = math.acos(1 - 2 * p) / math.pi
        end
        local wait = t * duration - elapsed
        if wait > 0 then
            coroutine.yield(wait)
            elapsed = elapsed + wait
        end
        ctx.offset = {x = ctx.offset.x + dir.x, y = ctx.offset.y + dir.y}
        ResolveHits(ctx)
    end

    WaitForArrival(objectToken, startLoc:dir(dir.x * travelled, dir.y * travelled))
    return travelled
end

--Safety net: puts the object exactly back where it started if it isn't (a
--return leg cut short, or rounding in the engine's slide). The engine keeps
--the object's offset within its square, so normally this does nothing.
--- @param ctx SwingContext
local function ReturnToOrigin(ctx)
    local objectToken = ctx.objectToken
    local obj = objectToken.objectInstance
    if not objectToken.valid or obj == nil then
        return
    end

    ctx.offset = {x = 0, y = 0}
    if math.abs(obj.x - ctx.originX) > 0.01 or math.abs(obj.y - ctx.originY) > 0.01 then
        obj:SetAndUploadPos(ctx.originX, ctx.originY)
        WaitForArrival(objectToken, ctx.originLoc)
    end
end

function ActivatedAbilitySwingObjectBehavior:Cast(ability, casterToken, targets, options)
    local objectToken = SwungObjectToken(ability, casterToken)
    if objectToken == nil or objectToken.objectInstance == nil or casterToken == nil or not casterToken.valid then
        print("SwingObject:: nothing to swing -- object =", objectToken, "ability =", ability.name)
        return
    end

    local maxDistance = math.floor(EvalNumber(self.maxDistance, casterToken, options, 3, "Swing Object Max Distance"))
    local shiftDistance = math.floor(EvalNumber(self.shiftDistance, casterToken, options, 0, "Swing Object Shift Distance"))
    local speed = EvalNumber(self.swingSpeed, casterToken, options, 6, "Swing Object Speed")
    if speed <= 0 then
        speed = 6
    end

    local floor = objectToken.loc.floor
    local footprint = {}
    for _, loc in ipairs(objectToken.locsOccupying) do
        footprint[#footprint + 1] = {x = loc.x, y = loc.y}
    end
    local pusherSquares = {}
    for _, loc in ipairs(casterToken.locsOccupying) do
        pusherSquares[#pusherSquares + 1] = {x = loc.x, y = loc.y}
    end

    local candidates, choices = SwingCandidates(objectToken, footprint, pusherSquares, maxDistance)
    if #candidates == 0 then
        print("SwingObject:: no legal push direction for", ability.name)
        return
    end

    local picked = ChooseSquare(casterToken, candidates, string.format("%s: choose where to push the %s (up to %d square%s)", ability.name, creature.GetTokenDescription(objectToken), maxDistance, cond(maxDistance == 1, "", "s")))
    local choice = picked ~= nil and choices[Key(picked.x, picked.y)] or nil
    if choice == nil then
        --cancelled: nothing happens and the action isn't spent.
        return
    end

    ability:CommitToPaying(casterToken, options)

    local obj = objectToken.objectInstance
    if obj == nil then
        return
    end
    --- @type SwingContext
    local ctx = {
        ability = ability,
        behavior = self,
        casterToken = casterToken,
        objectToken = objectToken,
        sourceToken = cond(objectToken.properties ~= nil, objectToken, casterToken),
        options = options,
        footprint = footprint,
        floor = floor,
        offset = {x = 0, y = 0},
        speed = speed,
        hit = {},
        originLoc = objectToken.loc,
        originX = obj.x,
        originY = obj.y,
    }

    local dir = choice.dir
    local back = {x = -dir.x, y = -dir.y}

    --leg 1: out, as far as the walls allow.
    local outDistance = RunLeg(ctx, dir, choice.distance, "out")

    --the pushing creature may shift, through the standard Shift ability (skippable).
    if shiftDistance > 0 and casterToken.valid then
        local commandHelper = ActivatedAbilityDrawSteelCommandBehavior.new{}
        commandHelper:ExecuteCommand(ability, casterToken, casterToken, options, string.format("shift %d", shiftDistance))
    end

    --leg 2: back to the start.
    RunLeg(ctx, back, outDistance, "in")
    ReturnToOrigin(ctx)

    --leg 3: the opposite way, no further than leg 1 went. Leg 4: home again.
    local oppositeDistance = RunLeg(ctx, back, outDistance, "out")
    RunLeg(ctx, dir, oppositeDistance, "in")
    ReturnToOrigin(ctx)
end

function ActivatedAbilitySwingObjectBehavior:EditorItems(parentPanel)
    local result = {}

    result[#result+1] = gui.Label{
        classes = {"formLabel"},
        width = "100%",
        height = "auto",
        textWrap = true,
        text = "Swings the object granting this ability (or the caster, if it is an object) out and back like a pendulum, then the same distance the other way and back. The caster picks the direction when the ability resolves; use target type Self.",
    }

    local function NumberField(label, field, help)
        return gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = label,
            },
            gui.GoblinScriptInput{
                value = self[field],
                change = function(element)
                    self[field] = element.value
                end,
                documentation = {
                    help = help,
                    output = "number",
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature pushing the object",
                },
            },
        }
    end

    result[#result+1] = NumberField("Max Distance:", "maxDistance", "The most squares the first swing can go. Each square must move the object further from the creature pushing it.")
    result[#result+1] = NumberField("Shift:", "shiftDistance", "Squares the pushing creature may shift after the first swing. 0 for no shift.")
    result[#result+1] = NumberField("Speed:", "swingSpeed", "How fast the object slides, in squares per second.")

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Rule:",
        },
        gui.Input{
            classes = {"formInput"},
            width = 300,
            text = self.rule,
            change = function(element)
                self.rule = element.text
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Hit Filter:",
        },
        gui.GoblinScriptInput{
            value = self.hitFilter,
            change = function(element)
                self.hitFilter = element.value
            end,
            documentation = {
                help = "Evaluated on each creature in the object's path. True means it is hit (once per swing).",
                output = "boolean",
                subject = creature.helpSymbols,
                subjectDescription = "The creature in the object's path",
            },
        },
    }

    return result
end
