local mod = dmhub.GetModLoading()

--Behaviors for triggers that act on a creature in the middle of its move (the Tactician's
--Overwatch). The engine finishes the whole move before a "move" trigger resolves, so
--these work from the triggering path in symbols.path (creature:OnMove puts it there).

--Draw Steel extra costs a path step can carry: each adds 1 square to entering it.
local g_extraCostFlags = {
    Difficult = true,
    Squeeze = true,
}

--Squares it costs to enter steps[i] (1-based; steps[1] is where the move began).
--- @param path LuaPath
--- @param i integer
--- @return number
local function StepCost(path, i)
    local cost = 1
    local ok, flags = pcall(function() return path:GetStepFlags(i - 1) end)
    if ok and type(flags) == "table" then
        for _, flag in ipairs(flags) do
            if g_extraCostFlags[flag] then
                cost = cost + 1
            end
        end
    end
    return cost
end

--True if tok could stand at loc without sharing a square with another token.
--- @param tok CharacterToken
--- @param loc Loc
--- @return boolean
local function LocIsFreeForToken(tok, loc)
    local locs = tok:LocsOccupyingWhenAt(loc)
    if locs == nil or #locs == 0 then
        return false
    end
    for _, occLoc in ipairs(locs) do
        if not occLoc.isOnMap then
            return false
        end
        for _, other in ipairs(dmhub.GetTokensAtLoc(occLoc) or {}) do
            if other.charid ~= tok.charid then
                return false
            end
        end
    end
    return true
end

--- @param a Loc
--- @param b Loc
--- @return boolean
local function SameSquare(a, b)
    return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.floor == b.floor
end

----------------------------------------------------------------------------
-- Slowed: Cut Short Move
--
-- If the target is slowed, its triggering move ends where a slowed creature's would
-- have: the furthest square along the path it could pay for with its (slowed) speed,
-- less what it had already moved this turn before this move. It is put there with a
-- silent teleport (no move, teleport or opportunity-attack triggers), sliding back
-- along the line on every client, and its movement used this turn is corrected.
----------------------------------------------------------------------------

--A hidden teleport style that slides the token from where it stands to its new square,
--so being stopped short does not look like a teleport.
local SLIDE_BACK_STYLE = "slowedslideback"
local SLIDE_BACK_SECONDS = 0.35

dmhub.tokenAnimations:RegisterTeleport{
    id = SLIDE_BACK_STYLE,
    name = "Slide Back",
    hidden = true,
    animation = function(token, targetLoc, opts)
        token.animation:Tween{ translate = targetLoc, duration = SLIDE_BACK_SECONDS, easing = "easeOut" }
        sleep(SLIDE_BACK_SECONDS)
    end,
}

--- @class ActivatedAbilityCutShortSlowedMoveBehavior: ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityCutShortSlowedMoveBehavior
ActivatedAbilityCutShortSlowedMoveBehavior = RegisterGameType("ActivatedAbilityCutShortSlowedMoveBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityCutShortSlowedMoveBehavior.summary = 'Slowed: Cut Short Move'

ActivatedAbility.RegisterType
{
    id = 'cutshortslowedmove',
    text = 'Slowed: Cut Short Move',
    createBehavior = function()
        return ActivatedAbilityCutShortSlowedMoveBehavior.new{}
    end,
}

function ActivatedAbilityCutShortSlowedMoveBehavior:SummarizeBehavior(ability, creatureLookup)
    return "If slowed, the triggering move stops at slowed speed"
end

--Where along the path a slowed creature's move ends, as an index into path.steps, and
--the squares it pays to get there. nil when it could have made the whole move anyway.
--- @param path LuaPath
--- @param budget number squares the creature could still move when this move began
--- @return nil|integer, number
local function SlowedStopIndex(path, budget)
    local steps = path.steps
    local stopIndex = 1
    local spent = 0
    for i = 2, #steps do
        local cost = StepCost(path, i)
        if spent + cost > budget then
            break
        end
        spent = spent + cost
        stopIndex = i
    end
    if stopIndex >= #steps then
        return nil, spent
    end
    return stopIndex, spent
end

--- @param tok CharacterToken
--- @param loc Loc
local function SlideBackTo(tok, loc)
    local previous = tok.teleportAnimation or ""
    tok.teleportAnimation = SLIDE_BACK_STYLE
    tok:UploadAppearance()

    tok.properties._tmp_suppressTeleportEvent = true
    tok:Teleport(loc)
    tok.properties._tmp_suppressTeleportEvent = nil

    dmhub.Schedule(SLIDE_BACK_SECONDS + 1, function()
        if mod.unloaded or not tok.valid then
            return
        end
        if tok.teleportAnimation == SLIDE_BACK_STYLE then
            tok.teleportAnimation = previous
            tok:UploadAppearance()
        end
    end)
end

--- @param tok CharacterToken
--- @param pathMoved PathMoved
local function CutShort(tok, pathMoved)
    local props = tok.properties
    if props == nil or props:IsDead() or not props:HasNamedCondition("Slowed") then
        return
    end

    ---@type LuaPath|nil
    local path = nil
    pcall(function() path = pathMoved.path end)
    if path == nil or path.forced or path.teleport then
        return
    end
    local steps = path.steps
    if steps == nil or #steps < 2 then
        return
    end

    --Movement this turn from before this move; recorded when the move was made, since
    --by now the engine has already charged the creature for the whole path.
    local movedBefore = nil
    pcall(function() movedBefore = pathMoved:try_get("movedBefore") end)
    if type(movedBefore) ~= "number" then
        movedBefore = math.max(0, props:DistanceMovedThisTurn() - (#steps - 1))
    end

    local budget = math.max(0, props:CurrentMovementSpeed() - movedBefore)
    local stopIndex = SlowedStopIndex(path, budget)
    if stopIndex == nil then
        return
    end

    --Let the move's animation finish before moving the token again.
    local deadline = dmhub.Time() + 8
    while tok.valid and tok.isMoving and dmhub.Time() < deadline do
        coroutine.yield(0.1)
    end
    if not tok.valid then
        return
    end

    --It has moved on since (a Director dragged it again): leave it alone.
    if not SameSquare(tok.loc, steps[#steps]) then
        print("CUTSHORT:: target is no longer where the move ended; not moving it")
        return
    end

    --Back up to the nearest square it can stand in; the start square counts.
    local chosen = nil
    for i = stopIndex, 1, -1 do
        if LocIsFreeForToken(tok, steps[i]) then
            chosen = i
            break
        end
    end
    if chosen == nil then
        print("CUTSHORT:: no free square along the path to stop in")
        return
    end

    local spent = 0
    for i = 2, chosen do
        spent = spent + StepCost(path, i)
    end

    local dest = steps[chosen]
    if props:CurrentMoveType() ~= "fly" then
        dest = dest.withGroundAltitude
    end
    SlideBackTo(tok, dest)

    if props:IsOurTurn() then
        tok:ModifyProperties{
            description = "Move Cost",
            execute = function()
                props.moveDistance = movedBefore + spent
                props.moveDistanceRoundId = dmhub.initiativeQueue:GetTurnId()
            end,
        }
    end

    props:FloatLabel(UIText.T("midmove.cut_short.float"), "white")
end

function ActivatedAbilityCutShortSlowedMoveBehavior:Cast(ability, casterToken, targets, options)
    local pathMoved = options.symbols ~= nil and options.symbols.path or nil
    if pathMoved == nil then
        return
    end

    --The path belongs to the creature that moved (the trigger's subject).
    local mover = nil
    local subject = options.symbols.subject
    if type(subject) == "function" then
        subject = subject("self")
    end
    if subject ~= nil then
        mover = dmhub.LookupToken(subject)
    end

    for _, target in ipairs(targets) do
        local tok = target.token
        if tok ~= nil and tok.valid and (mover == nil or mover.charid == tok.charid) then
            CutShort(tok, pathMoved)
        end
    end
end

function ActivatedAbilityCutShortSlowedMoveBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)
    return result
end

----------------------------------------------------------------------------
-- Direct an Ally to Free Strike
--
-- The caster picks one ally from a list at the bottom of the screen, with the target
-- ringed on the map. Allies who cannot free strike the target from where they stand
-- are listed but greyed out. The chosen ally is then offered a free strike through a
-- custom trigger (by default "Overwatch Strike", whose value is the target's GoblinScript id), and
-- the cast waits for that ally to take or decline it.
----------------------------------------------------------------------------

--- @class ActivatedAbilityDirectAllyFreeStrikeBehavior: ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityDirectAllyFreeStrikeBehavior
--- @field triggerName string The custom trigger fired on the chosen ally.
ActivatedAbilityDirectAllyFreeStrikeBehavior = RegisterGameType("ActivatedAbilityDirectAllyFreeStrikeBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityDirectAllyFreeStrikeBehavior.summary = 'Direct an Ally to Free Strike'
ActivatedAbilityDirectAllyFreeStrikeBehavior.triggerName = "Overwatch Strike"

--How long the caster has to choose before the choice lapses.
local g_chooseTimeout = 600

ActivatedAbility.RegisterType
{
    id = 'directallyfreestrike',
    text = 'Direct an Ally to Free Strike',
    createBehavior = function()
        return ActivatedAbilityDirectAllyFreeStrikeBehavior.new{
            triggerName = "Overwatch Strike",
        }
    end,
}

function ActivatedAbilityDirectAllyFreeStrikeBehavior:SummarizeBehavior(ability, creatureLookup)
    return "An ally makes a free strike against the target"
end

--Distance between two creatures in native units, counting the vertical gap between
--their bodies (as MonsterAI.TargetDistance does).
--- @param a CharacterToken
--- @param b CharacterToken
--- @return number
local function CreatureDistance(a, b)
    local aBottom, bBottom = a.altitude, b.altitude
    local aTop = aBottom + math.max(1, a.tileSize) - 1
    local bTop = bBottom + math.max(1, b.tileSize) - 1
    local vertical = math.max(0, bBottom - aTop, aBottom - bTop)
    return math.max(a:Distance(b) or math.huge, vertical * dmhub.unitsPerSquare)
end

--True when ally has a free strike that reaches target from where it stands, with line of effect.
--- @param ally CharacterToken
--- @param target CharacterToken
--- @return boolean
local function CanFreeStrike(ally, target)
    local props = ally.properties
    local distance = CreatureDistance(ally, target)
    local hasLineOfEffect = nil
    for _, ability in ipairs(props:GetActivatedAbilities() or {}) do
        if ability.categorization == "Basic Attack" then
            local variants = { ability }
            if ability:try_get("meleeAndRanged", false) then
                variants = { ability.meleeVariation, ability.rangedVariation }
            end
            for _, variant in ipairs(variants) do
                if variant ~= nil and distance <= variant:GetRange(props) then
                    if hasLineOfEffect == nil then
                        hasLineOfEffect = (ally:GetLineOfSight(target, props:GetPierceWalls()) or 0) > 0
                    end
                    if hasLineOfEffect then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--Every ally of the caster on the map who could be directed: living creatures, not the
--caster or the target. Allies who can strike come first, then the nearest.
--- @param casterToken CharacterToken
--- @param targetToken CharacterToken
--- @return {token: CharacterToken, canStrike: boolean, distance: number}[]
local function AllyCandidates(casterToken, targetToken)
    local result = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.valid and (not tok.isObject) and tok.properties ~= nil
            and tok.charid ~= casterToken.charid and tok.charid ~= targetToken.charid
            and (not tok.properties:IsDead())
            and casterToken:IsFriend(tok) then
            result[#result+1] = {
                token = tok,
                canStrike = CanFreeStrike(tok, targetToken),
                distance = CreatureDistance(tok, targetToken),
            }
        end
    end
    table.sort(result, function(a, b)
        if a.canStrike ~= b.canStrike then
            return a.canStrike
        end
        return a.distance < b.distance
    end)
    return result
end

--The target's name as the local player may see it.
--- @param tok CharacterToken
--- @return string
local function VisibleName(tok)
    if tok.canLocalPlayerSeeName and tok.name ~= nil and tok.name ~= "" then
        return tok.name
    end
    return UIText.T("midmove.direct_ally.unnamed_target")
end

--Holds the "locate" ring on a token (the same ring the cast prompt uses for hovered choices).
--- @param tok CharacterToken
--- @param on boolean
local function SetLocateRing(tok, on)
    if tok.valid and tok.bottomsheet ~= nil and tok.bottomsheet.valid then
        tok.bottomsheet:SetClassTree("locate", on)
    end
end

--Shows the ally list and waits for the caster's choice. Returns the chosen ally, or nil
--when the caster skipped, the choice lapsed, or the prompt could not be shown.
--- @param casterToken CharacterToken
--- @param targetToken CharacterToken
--- @param candidates {token: CharacterToken, canStrike: boolean, distance: number}[]
--- @return nil|CharacterToken
local function ChooseAlly(casterToken, targetToken, candidates)
    local actionBar = rawget(_G, "DrawSteelActionBar")

    --No prompt to show (no action bar) or nobody at the keyboard (an AI-run caster):
    --pick the nearest ally who can strike.
    if actionBar == nil or creature.IsTokenAIControlled(casterToken.charid) then
        local first = candidates[1]
        if first ~= nil and first.canStrike then
            return first.token
        end
        return nil
    end

    local chosen = nil
    local done = false

    local choices = {}
    for _, candidate in ipairs(candidates) do
        local tok = candidate.token
        local label = tok.name or ""
        if not candidate.canStrike then
            label = UIText.T("midmove.direct_ally.out_of_reach", { name = label })
        end
        choices[#choices+1] = {
            text = label,
            disabled = not candidate.canStrike,
            charids = { tok.charid },
            click = function()
                chosen = tok
                done = true
            end,
        }
    end

    local text
    if #candidates == 0 then
        text = UIText.T("midmove.direct_ally.no_allies", { target = VisibleName(targetToken) })
    else
        text = UIText.T("midmove.direct_ally.choose", { target = VisibleName(targetToken) })
    end

    local shown = actionBar.ShowCastPrompt{
        text = text,
        choices = choices,
        cancel = function()
            done = true
        end,
    }
    if not shown then
        local first = candidates[1]
        if first ~= nil and first.canStrike then
            return first.token
        end
        return nil
    end

    local deadline = dmhub.Time() + g_chooseTimeout
    local nextPulse = 0
    while not done and not mod.unloaded and dmhub.Time() < deadline and targetToken.valid do
        SetLocateRing(targetToken, true)
        if dmhub.Time() >= nextPulse then
            dmhub.PulseHighlightToken(targetToken.charid)
            nextPulse = dmhub.Time() + 1.5
        end
        coroutine.yield(0.1)
    end

    SetLocateRing(targetToken, false)
    actionBar.ShowCastPrompt(nil)
    return chosen
end

function ActivatedAbilityDirectAllyFreeStrikeBehavior:Cast(ability, casterToken, targets, options)
    local target = targets[1]
    local targetToken = target ~= nil and target.token or nil
    if targetToken == nil or not targetToken.valid or targetToken.properties == nil
        or targetToken.properties:IsDead() then
        return
    end

    local ally = ChooseAlly(casterToken, targetToken, AllyCandidates(casterToken, targetToken))
    if ally == nil or not ally.valid or ally.properties == nil then
        return
    end

    --Forward the Monster AI activity this cast belongs to, so a monster whose move
    --provoked Overwatch waits for the ally's strike too (see AbilityCustomTrigger.lua).
    local aiActivityId = options.symbols ~= nil and options.symbols.aiActivityId or nil
    if type(aiActivityId) ~= "string" or aiActivityId == "" then
        aiActivityId = nil
    end

    --The value is the target's GoblinScript id (a number), so the ally's trigger can
    --match it with "target.id = Trigger Value".
    ally.properties:DispatchEvent("custom", {
        triggername = self.triggerName,
        triggervalue = Utils.HashGuidToNumber(targetToken.charid),
        aiActivityId = aiActivityId,
    })

    ActivatedAbilityCustomTriggerBehavior.new{ triggerName = self.triggerName }:WaitForTriggerResolution(ally)
end

function ActivatedAbilityDirectAllyFreeStrikeBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Trigger Name:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.triggerName,
            change = function(element)
                self.triggerName = element.text
            end,
        },
    }

    return result
end
