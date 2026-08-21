local mod = dmhub.GetModLoading()

--- Generic registry of pre-cast controls. Other mods (e.g. Draw Steel Acolyte) can
--- register cast controls that render in the cast panel and hook into the cast lifecycle.
--- DMHub's Lua runs in strict mode -- reading uninitialized globals errors -- so we
--- bootstrap via rawget(_G,...). Other mods (Acolyte) do the same dance so order
--- of load doesn't matter.
DrawSteelActionBar = rawget(_G, "DrawSteelActionBar") or {}
_G.DrawSteelActionBar = DrawSteelActionBar
DrawSteelActionBar._castControls = DrawSteelActionBar._castControls or {}

--- @class DrawSteelActionBarCastControl
--- @field id string Unique id for the control.
--- @field priority number|nil Display order; lower renders first. Defaults to 0.
--- @field appliesTo function|nil predicate(ability) -> boolean; the control only renders when this returns truthy. If nil, control applies to every ability.
--- @field render function|nil render(parent, ability, castState, ctx) -> Panel|nil. Build UI; mutate castState to record toggle/choice. Return value is ignored - just add children to parent. `ctx` is a table with: { symbols = g_currentSymbols (cast already populated), cast = symbols.cast (an ActivatedAbilityCast you may mutate before the cast commits, e.g. cast.invoked = true), refreshTargeting = function() (call after toggling state to re-evaluate numTargets/range/etc and refresh the targeting UI) }.
--- @field onCommit function|nil onCommit(ability, cast, castState, casterToken, symbols). Called right before the cast resolves. cast is options.symbols.cast (pre-built by the action bar at render time, so non-nil for any control whose appliesTo returned true). Apply pre-cast effects and populate cast symbols here.
--- @field onResolve function|nil onResolve(ability, cast, castState, casterToken). Called after the cast finishes resolving (all behaviors done). Post-cast effects.

--- Register a cast control. See DrawSteelActionBarCastControl for the spec shape.
--- @param spec DrawSteelActionBarCastControl
function DrawSteelActionBar.RegisterCastControl(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" then
        return
    end
    --replace any existing entry with the same id so hot-reloads don't duplicate.
    for i,existing in ipairs(DrawSteelActionBar._castControls) do
        if existing.id == spec.id then
            DrawSteelActionBar._castControls[i] = spec
            return
        end
    end
    DrawSteelActionBar._castControls[#DrawSteelActionBar._castControls+1] = spec
end

--- Returns the registered cast controls sorted by priority (lower first).
function DrawSteelActionBar.GetCastControls()
    local result = {}
    for _,c in ipairs(DrawSteelActionBar._castControls) do
        result[#result+1] = c
    end
    table.sort(result, function(a,b) return (a.priority or 0) < (b.priority or 0) end)
    return result
end

local ActionMenu
local CreateAbilityController

---  @type function
local CalculateSpellTargeting

--- @type nil|Panel
local g_abilityController = nil

--- @type nil|Panel
local g_triggerPanel = nil

--- @type nil|Panel
local g_actionBar = nil

--- @type string[]
local g_targetsChosen = {}

--- @type boolean True once the player has manually clicked a target during the
--- current cast. Distinguishes interactively-chosen targets from targets that
--- arrived pre-selected (e.g. inherited into an invoked ability): a cast with a
--- promptOverride waits for an explicit Confirm when its targets were
--- pre-selected, but completes normally at the target cap when the player
--- chose the targets by clicking.
local g_manualTargetChosen = false

--- @type nil|string The first target chosen by the player, the charid of this token.
local g_firstTarget = nil

--- @type Loc[]
local m_positionTargetsChosen = {} --list of Locs for targets. Used on emptyspace targeting.

--- @type nil|ActivatedAbility
local g_currentAbility

--- @type number
local g_range = 0

--- @type table
local g_currentSymbols = {}

--- @type nil|CharacterToken
local g_token

--- @type nil|Creature
local g_creature

--The WHOLE current selection (every selected token that has properties), in
--selection order, captured alongside g_token in the root refresh. g_token stays
--bound to selectedOrPrimaryTokens[1] exactly as before; this list only feeds
--the director's multi-monster overview ("Unique Abilities" drawer).
--- @type CharacterToken[]
local g_selectedTokens = {}

--Identity of the current selection (charids in selection order). The engine
--only re-fires the bar's "refresh" when the PRIMARY selected token changes;
--adding or removing other tokens behind the same primary is silent (verified
--live 2026-08-17). The root panel compares this at a low poll rate and
--refreshes itself when the set changes, so overview mode tracks the whole
--selection.
local function SelectionSignature()
    local parts = {}
    for _, tok in ipairs(dmhub.selectedOrPrimaryTokens) do
        if tok ~= nil and tok.valid then
            parts[#parts + 1] = tok.charid
        end
    end
    return table.concat(parts, ",")
end

--Is this token one the director's overview is designed for: a monster the
--director runs. Heroes are far more complex than monsters and the overview
--was never designed for them (field test F2-1); followers and hero summons
--are player-side creatures and stay out for now too (they may fit later).
--- @param tok CharacterToken
--- @return boolean
local function IsOverviewCreatureToken(tok)
    if tok == nil or (not tok.valid) or tok.properties == nil then
        return false
    end
    if tok.playerControlled then
        return false
    end
    local props = tok.properties
    local ok = false
    pcall(function()
        ok = props:IsMonster() and (not props:IsFollower()) and (not props:IsHeroSummon())
    end)
    return ok
end

--Overview mode = the local user is the director AND more than one token is
--selected AND every selected token is a director-run monster (a selection
--that includes any hero, follower or hero summon falls back to the classic
--strip; F2-1) AND the selection is not just one minion squad (a squad is a
--single actor, so it keeps the ordinary single-creature strip; Decision 43).
--In this mode the strip shows Trigger | Unique Abilities | Malice: the Main
--Action / Maneuver / Move drawers are identical across creatures so they are
--hidden.
local function InOverviewMode()
    if not dmhub.isDM then
        return false
    end
    if #g_selectedTokens < 2 then
        return false
    end
    for _, tok in ipairs(g_selectedTokens) do
        if not IsOverviewCreatureToken(tok) then
            return false
        end
    end
    local squad = g_selectedTokens[1].properties:MinionSquad()
    if squad ~= nil then
        local sameSquad = true
        for i = 2, #g_selectedTokens do
            if g_selectedTokens[i].properties:MinionSquad() ~= squad then
                sameSquad = false
                break
            end
        end
        if sameSquad then
            return false
        end
    end
    return true
end

--P2-b (Decision 39): select every READY director monster on the current map
--- alive, director-run, and (while an initiative queue is running) not yet
--acted this round; out of combat, every director monster. Sets the selection
--only; it does NOT open the Unique Abilities folder (opening is a separate
--click). Returns the number selected. Called from the initiative bar's
--"Ready Monsters" label (MCDMInitiativeBar.lua) - the one place on screen
--that already means "these monsters have not gone yet".
function DrawSteelActionBar.SelectReadyMonsters()
    if not dmhub.isDM then
        return 0
    end
    local q = dmhub.initiativeQueue
    if q ~= nil and q.hidden then
        q = nil
    end
    local result = {}
    for _, tok in ipairs(dmhub.GetTokens() or {}) do
        if IsOverviewCreatureToken(tok) then
            local ok = true
            pcall(function()
                if tok.properties:IsDown() then
                    ok = false
                end
            end)
            if ok and q ~= nil then
                --Field test 4: only monsters that are actually IN the
                --initiative order. Reinforcements parked in "Ready Monsters"
                --(the A5 Snipers) are not part of the encounter yet and
                --selecting them was noise.
                local initiativeid = nil
                pcall(function() initiativeid = InitiativeQueue.GetInitiativeId(tok) end)
                if initiativeid == nil or q.entries == nil or q.entries[initiativeid] == nil then
                    ok = false
                elseif q:HasHadTurn(initiativeid) then
                    ok = false
                end
            end
            if ok then
                result[#result + 1] = tok
            end
        end
    end
    dmhub.selectedTokens = result
    return #result
end

--Director overview, slice (e): the implicit claim-turn-at-target-confirm.
--
--A chip press in an overview column records WHO the cast is for here
--({token, initiativeid}); nothing is claimed at that point (Decision 47 -
--claiming is a broadcast and irreversible, see MCDMInitiativeQueue.ClaimTurn).
--OverviewClaimBeforeCast, called from the ONE pre-Cast hook the two Cast
--sites share (right after FireCastControlsOnCommit), consumes the record and
--claims the entry's turn only if that is legal at that instant
--(OverviewClaimGate); otherwise the cast proceeds without touching the queue,
--exactly as an off-turn cast does today (Decision 24). The record is one-shot
--(consumed by the first commit) and is cleared by cancelCasting, which every
--exit funnels through (finishCasting, Skip, Esc, opening another menu,
--controller disable, restoreFromBackup), so a later unrelated cast can never
--claim by accident. Ordinary single-token menus never set it.
local g_overviewCastPending = nil

--Is a claim of this initiative entry legal for the Director right now?
--Returns ok, reason, settled. reason is the newcomer-facing text shown inline
--on the disabled button / tooltip. settled (F3-2) is true when taking the
--turn is no longer an OPTION this round at all - nothing is running, or the
--entry is acting now / has already acted - as opposed to merely blocked for
--the moment (heroes' turn, another creature mid-turn): the footer hides the
--button for settled cases (the signal line already says "acting now" /
--"acted") and keeps the greyed button + reason only for the transient ones,
--where the Director might want to know WHY they cannot act yet.
--Stricter than InitiativeQueue.CanClaimTurn on purpose: the Director CAN
--force any turn from the initiative bar, but the overview only offers a claim
--at the genuine start-of-a-director-turn juncture (Phase 0 resolution:
--ChoosingTurn, not the heroes' side, entry unmoved).
local function OverviewClaimGate(initiativeid)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return false, "No initiative running", true
    end
    --Transient, not settled: reinforcements waiting in "Ready Monsters" are a
    --real in-play state (A5 Goblin Snipers) and the Director CAN change it by
    --dragging them into the order - the greyed reason is the hint.
    if initiativeid == nil or q.entries == nil or q.entries[initiativeid] == nil then
        return false, "Not in the initiative order", false
    end
    if q.currentTurn == initiativeid then
        return false, "Turn taken - acting now", true
    end
    if q:HasHadTurn(initiativeid) then
        return false, "Already acted this round", true
    end
    if not q:ChoosingTurn() then
        return false, "Another creature's turn is in progress", false
    end
    if q:IsPlayersTurn() then
        return false, "It's the heroes' turn - browse only", false
    end
    if not InitiativeQueue.CanClaimTurn(initiativeid, { canControlInitiative = dmhub.isDM }) then
        return false, "Cannot take turns right now", false
    end
    return true, nil, false
end

--Action economy of a kit ability for the overview column (field test 2:
--"can this monster do two unique things this turn?" must read structurally).
--Returns group, label: group 0 = main action (label "" - main actions stay
--unmarked, they are the default), group 1 = everything that is NOT a main
--action, labelled "Maneuver" / "Free Maneuver" / "Free Action" (no action
--required) so the chip says so in legible text. Triggers / villain actions
--never reach the column (IsUniqueKitAbility).
local function OverviewActionType(ability)
    local rid = nil
    pcall(function() rid = ability.actionResourceId end)
    if rid == CharacterResource.actionResourceId then
        return 0, ""
    elseif rid == CharacterResource.maneuverResourceId then
        return 1, "Maneuver"
    elseif rid == CharacterResource.freeManeuverResourceId then
        return 1, "Free Maneuver"
    elseif rid == "none" or rid == nil then
        return 1, "Free Action"
    end
    --Anything else (respite activity, a custom resource) is not a main action
    --either; show the resource's own name when it has one.
    local name = nil
    pcall(function()
        local resource = dmhub.GetTable(CharacterResource.tableName)[rid]
        name = resource and resource.name
    end)
    return 1, name or "Maneuver"
end

--Perform the claim through the shared helper. Returns true if the turn was
--taken. Never called from a browse/preview click.
local function OverviewClaimTurn(initiativeid)
    local ok = OverviewClaimGate(initiativeid)
    if not ok then
        return false
    end
    print("OVERVIEW:: claiming turn for", initiativeid)
    return InitiativeQueue.ClaimTurn(initiativeid, { canControlInitiative = dmhub.isDM }) == true
end

--The pre-Cast hook (see g_overviewCastPending). casterToken is the g_token the
--Cast is about to run for; the pending record must name the same token so a
--caster swap between chip press and confirm can never claim for the wrong
--creature.
local function OverviewClaimBeforeCast(casterToken)
    local pending = g_overviewCastPending
    g_overviewCastPending = nil
    if pending == nil or pending.token == nil then
        return
    end
    if casterToken == nil or not casterToken.valid or not pending.token.valid or pending.token.charid ~= casterToken.charid then
        return
    end
    local initiativeid = InitiativeQueue.GetInitiativeId(casterToken)
    if initiativeid == nil or initiativeid ~= pending.initiativeid then
        return
    end
    OverviewClaimTurn(initiativeid)
end

--Minion squad coordinated strike: the minion->target assignment is automatic,
--but the player can hard-lock a specific minion to a specific target by
--clicking the minion and then the target. Locks live in MCDMActivatedAbility
--(ActivatedAbility.LockSquadTargetingPair / ClearSquadTargetingState) and are
--honored by GetTargetingRays; the locked minion becomes that creature's main
--attacker.
--- @type nil|CharacterToken  a squad minion that was clicked and is awaiting a target
local g_squadPendingLockMinion = nil

local function SquadStrikeActive()
    return g_currentAbility ~= nil and g_token ~= nil and g_token.valid
        and g_currentAbility:UsesSquadStrike(g_token)
end

--True if tok is an active (alive, not broken-off) minion in the caster's squad.
local function SquadIsActiveMinionToken(tok)
    if tok == nil or g_token == nil or g_token.properties == nil then
        return false
    end
    local squad = g_token.properties:try_get("_tmp_minionSquad")
    if squad == nil or squad.tokens == nil then
        return false
    end
    for _, member in ipairs(squad.tokens) do
        if member ~= nil and member.valid and member.id == tok.id
            and (not member.properties:IsDead()) and member.properties:IsActiveInSquad() then
            return true
        end
    end
    return false
end

--- @type nil|Panel
local g_channeledResourcePanel

local g_casterTokenStack = {}

--- @type {shapePathEnd: nil|LuaShape[], labelsAtPathEnd: nil|LuaObjectReference[], pathEndOvershoot: nil|number, fallingShape: nil|LuaObjectReference, fallDamageLabel: nil|LuaObjectReference, fallDamageKey: nil|string, shapeRequiresConfirm: nil|boolean, shapeConfirmedLoc: nil|Loc, shape: nil|LuaShape, label: nil|LuaObjectReference, radius: nil|LuaObjectReference, showingMovementArrow: nil|boolean}
local g_pointTargeting = {}

--- Partner burst: pre-create the cast object carrying "caster" retargets for the
--- partner-only targets, so every per-target effect -- taunt source, push
--- direction, prone source -- is sourced from the partner rather than the caster.
--- Both DrawSteelCommandBehavior and PowerRollBehavior consume this via
--- ActivatedAbilityCast:RemapCasterForTarget. Tokens in BOTH bursts get no
--- retarget, leaving them on the original caster ("an enemy in both areas is
--- taunted only by you"). Must be called immediately before EVERY
--- g_currentAbility:Cast site -- there is more than one, and an ability that
--- casts through an uncovered site silently loses the swap.
--- ActivatedAbility:Cast respects a pre-existing options.symbols.cast.
--- @param targets table The resolved target list being cast at.
local function RecordPartnerBurstRetargets(targets)
    if g_pointTargeting.partnerOnlyTokenIds == nil or g_pointTargeting.partnerCasterToken == nil then
        return
    end

    --Attach to the in-flight cast when one already exists. Creating a fresh cast
    --here would discard whatever state that one carries, and refusing outright
    --(the original behaviour) silently dropped the caster swap on every ability
    --whose cast object is built earlier in the flow. RecordRetarget only appends.
    local cast = g_currentSymbols.cast
    if cast == nil then
        cast = ActivatedAbilityCast.new{
            ability = g_currentAbility,
            targets = targets,
            mode = g_currentSymbols.mode or 1,
            _tmp_targetArea = g_currentSymbols.targetArea,
        }
        g_currentSymbols.cast = cast
    end

    for charid, _ in pairs(g_pointTargeting.partnerOnlyTokenIds) do
        cast:RecordRetarget{
            retargetType = "caster",
            tokenid = charid,
            retargetid = charid,
            casterid = g_pointTargeting.partnerCasterToken.charid,
        }
    end
end

--- @type nil|{oncast=nil|function, oncancel=nil|function}
local g_invokerInfo = nil

--tokens we are force targeting based on them being in a radius. A mapping of tokenid -> token
--- @type table<string, CharacterToken>
local g_pointForceTargets = {}

--- @type function[] a list of functions we will call when we cancel casting.
local g_castingDestructors = {}

--Instant "apply on casting" duration effects, keyed by the behavior table that
--produced them. Each entry is { destructor = function|nil }. Tracked separately
--from g_castingDestructors so they can be re-evaluated (applied / removed) when the
--player switches the ability's mode mid-targeting.
--- @type table<table, {destructor: function|nil}>
local g_castingDurationEffects = {}

--Apply (or re-evaluate) the instant "apply on casting" duration effects of the
--current ability. Honors each behavior's filterTarget gate against the current
--`mode` symbol: behaviors whose gate now passes get their effect applied, behaviors
--whose gate no longer passes get their effect removed. Safe to call repeatedly.
local function RefreshCastingDurationEffects()
    if g_currentAbility == nil or g_token == nil then
        return
    end

    --collect the set of behaviors that are still instant duration effects on the
    --current ability, so we can drop tracking for any that no longer exist.
    local liveBehaviors = {}
    for _, behavior in ipairs(g_currentAbility.behaviors) do
        if behavior.typeName == "ActivatedAbilityApplyAbilityDurationEffect" then
            liveBehaviors[behavior] = true

            local shouldApply = behavior:CastingFilterPasses(g_token, g_currentSymbols)
            local entry = g_castingDurationEffects[behavior]
            local currentlyApplied = entry ~= nil and entry.destructor ~= nil

            if shouldApply and not currentlyApplied then
                local destructor = behavior:ApplyOnCasting(g_token, g_currentSymbols)
                g_castingDurationEffects[behavior] = { destructor = destructor }
            elseif (not shouldApply) and currentlyApplied then
                entry.destructor()
                g_castingDurationEffects[behavior] = { destructor = nil }
            end
        end
    end

    --tear down any tracked effects whose behavior is no longer present.
    for behavior, entry in pairs(g_castingDurationEffects) do
        if liveBehaviors[behavior] == nil then
            if entry.destructor ~= nil then
                entry.destructor()
            end
            g_castingDurationEffects[behavior] = nil
        end
    end
end

--Remove all instant duration effects and clear tracking. Called when casting ends.
local function ClearCastingDurationEffects()
    for behavior, entry in pairs(g_castingDurationEffects) do
        if entry.destructor ~= nil then
            entry.destructor()
        end
    end
    g_castingDurationEffects = {}
end

function IsCurrentlyUsingAbility()
    return g_currentAbility ~= nil
end

local function GetHeroicResourceOrMaliceCost(ability, symbols)
    symbols = symbols or g_currentSymbols

    local cost = ability:GetCost(g_token, symbols)
    if cost == nil or cost.details == nil then
        return nil
    end

    local heroicResourceEntry = nil
    for _, entry in ipairs(cost.details) do
        if entry.cost == CharacterResource.heroicResourceId or entry.cost == CharacterResource.maliceResourceId then
            heroicResourceEntry = entry
            break
        end
    end

    if heroicResourceEntry == nil then
        return nil
    end

    return heroicResourceEntry.quantity
end

--Consolidated overview constants/state. The file sits AT Lua 5.4's limit of
--200 locals per chunk (the engine REFUSES the file past it - luac 5.5 on the
--dev machine counts differently and misses it), so overview scalars live as
--fields here rather than as top-level locals. Add new module state HERE.
local OVERVIEW = {
    GUIDE_COLOR = "#7AC77A",
    FOOTER_ROWS = 3,
    FOOTER_ROW_POOL = 6,
    STATUS_ICONS = 2,
    THREAT_COLOR = "#E06464",
    NOREACH_COLOR = "#E0A050",
    CHIP_CONDITION_ICONS = 2,
    LOCATE_PAN_TIME = 0.55,
    LOCATE_HOLD = 1.4,
    locateGeneration = {},
    tierFacetCache = {},
}

--P2-c1: LENSES (Decisions 8/21/27/31/49, X3). A lens is a FACET filter over
--the overview columns: it hides columns with no matching kit ability, dims
--(never hides) the non-matching chips inside the surviving columns, and sorts
--each column's chips by the lens's natural key. Facets are derived, never
--hand-tagged: keywords, behaviour types and the engine's own tier-text parser
--(ActivatedAbilityDrawSteelCommandBehavior.WalkParsedSegments - the regex
--rule matcher, NEVER substring search: "strained" is inside "restrained").
local OVERVIEW_LENSES = {
    { id = "all",     name = "All" },
    { id = "damage",  name = "Damage" },
    { id = "area",    name = "Area" },
    { id = "forced",  name = "Forced Move" },
    { id = "control", name = "Control" },
    { id = "malice",  name = "Malice" },
}
--Session-scoped: the lens survives menu close/open but not a reload.
local g_overviewLens = "all"

local function OverviewLensInfo(id)
    for _, lens in ipairs(OVERVIEW_LENSES) do
        if lens.id == id then
            return lens
        end
    end
    return OVERVIEW_LENSES[1]
end

local function OverviewLensIndex(id)
    for i, lens in ipairs(OVERVIEW_LENSES) do
        if lens.id == id then
            return i
        end
    end
    return 1
end

--Tier-text facets, cached by the exact text (the parser is regex-heavy and
--the same tier strings recur on every populate).
local function OverviewTierFacets(text)
    if type(text) ~= "string" or text == "" then
        return { damage = nil, forced = nil, control = false }
    end
    local cached = OVERVIEW.tierFacetCache[text]
    if cached ~= nil then
        return cached
    end
    local facets = { damage = nil, forced = nil, forcedVerb = nil, control = false, conditions = {} }
    local segments = nil
    pcall(function()
        segments = ActivatedAbilityDrawSteelCommandBehavior.WalkParsedSegments(text)
    end)
    for _, segment in ipairs(segments or {}) do
        local m = segment.match
        if type(m) == "table" then
            if m.damage ~= nil then
                local n = tonumber(string.match(tostring(m.damage), "^%s*(%d+)"))
                if n ~= nil and (facets.damage == nil or n > facets.damage) then
                    facets.damage = n
                end
            end
            if m.movement ~= nil and m.distance ~= nil then
                local n = tonumber(m.distance)
                if n ~= nil and (facets.forced == nil or n > facets.forced) then
                    facets.forced = n
                    facets.forcedVerb = tostring(m.movement)
                end
            end
            if m.condition ~= nil then
                facets.control = true
                local name = tostring(m.condition)
                name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
                local seen = false
                for _, existing in ipairs(facets.conditions) do
                    if existing == name then
                        seen = true
                    end
                end
                if not seen then
                    facets.conditions[#facets.conditions + 1] = name
                end
            end
        end
    end
    OVERVIEW.tierFacetCache[text] = facets
    return facets
end

--Facets of one kit ability: booleans per lens plus the lens sort keys.
--  damage / damageValue (tier 2, Decision 21), area / areaSize,
--  forced / forcedDistance, control, malice / maliceCost.
local function OverviewAbilityFacets(ability)
    local facets = {
        damage = false, damageValue = 0,
        area = false, areaSize = 0,
        forced = false, forcedDistance = 0, forcedVerb = nil,
        control = false, conditions = {},
        malice = false, maliceCost = 0,
    }
    if ability == nil then
        return facets
    end
    pcall(function()
        facets.area = ability:HasKeyword("Area") == true
        if facets.area then
            facets.areaSize = tonumber(ability:try_get("radius")) or tonumber(ability.range) or 0
        end
    end)
    pcall(function()
        local cost = GetHeroicResourceOrMaliceCost(ability) or 0
        facets.malice = cost > 0
        facets.maliceCost = cost
    end)
    pcall(function()
        for _, behavior in ipairs(ability.behaviors or {}) do
            local tn = behavior.typeName or ""
            if tn == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior:try_get("tiers") or {}
                for i, text in ipairs(tiers) do
                    local f = OverviewTierFacets(text)
                    if f.damage ~= nil then
                        facets.damage = true
                        if i == 2 or (i == #tiers and facets.damageValue == 0) then
                            facets.damageValue = f.damage
                        end
                    end
                    if f.forced ~= nil then
                        facets.forced = true
                        if f.forced > facets.forcedDistance then
                            facets.forcedDistance = f.forced
                            facets.forcedVerb = f.forcedVerb
                        end
                    end
                    if f.control then
                        facets.control = true
                        for _, name in ipairs(f.conditions) do
                            local seen = false
                            for _, existing in ipairs(facets.conditions) do
                                if existing == name then
                                    seen = true
                                end
                            end
                            if not seen then
                                facets.conditions[#facets.conditions + 1] = name
                            end
                        end
                    end
                end
            elseif tn == "ActivatedAbilityDamageBehavior" then
                facets.damage = true
            elseif string.find(tn, "ForcedMovement", 1, true) ~= nil then
                facets.forced = true
                local d = tonumber(behavior:try_get("distance"))
                if d ~= nil and d > facets.forcedDistance then
                    facets.forcedDistance = d
                end
            elseif string.find(tn, "InflictCondition", 1, true) ~= nil
                or string.find(tn, "ApplyCondition", 1, true) ~= nil then
                facets.control = true
            elseif string.find(tn, "OngoingEffect", 1, true) ~= nil then
                --Only an ongoing effect that carries a CONDITION is control;
                --plain buffs (Defend's edge, Aid Attack) are not.
                local effectid = behavior:try_get("ongoingEffect")
                local info = nil
                if effectid ~= nil then
                    info = (dmhub.GetTable("characterOngoingEffects") or {})[effectid]
                end
                if info ~= nil and info.condition ~= nil and info.condition ~= "none" then
                    facets.control = true
                    local conditions = dmhub.GetTable(CharacterCondition.tableName) or {}
                    local cond = conditions[info.condition]
                    if cond ~= nil and cond.name ~= nil then
                        local seen = false
                        for _, existing in ipairs(facets.conditions) do
                            if existing == cond.name then
                                seen = true
                            end
                        end
                        if not seen then
                            facets.conditions[#facets.conditions + 1] = cond.name
                        end
                    end
                end
            end
        end
    end)
    return facets
end

local function OverviewAbilityMatchesLens(facets, lens)
    if lens == nil or lens == "all" then
        return true
    end
    return facets[lens] == true
end

--Decision 21: Damage = tier-2 damage desc; Area = size desc; Forced Move =
--distance desc; Malice = cost asc; Control has no magnitude -> damage desc.
--ALL ties broken by tier-2 damage desc, then name.
local function OverviewLensLess(lens, a, fa, b, fb)
    if lens == "malice" and fa.maliceCost ~= fb.maliceCost then
        return fa.maliceCost < fb.maliceCost
    elseif lens == "area" and fa.areaSize ~= fb.areaSize then
        return fa.areaSize > fb.areaSize
    elseif lens == "forced" and fa.forcedDistance ~= fb.forcedDistance then
        return fa.forcedDistance > fb.forcedDistance
    end
    if fa.damageValue ~= fb.damageValue then
        return fa.damageValue > fb.damageValue
    end
    return a.name < b.name
end

--X14: the active lens's sort key, printed on a matching chip so the sort is
--legible ("6 damage per target", "Area 3", "Push 3", "Restrained",
--"1 Malice"). nil for the "All" lens or a non-matching chip.
local function OverviewLensKeyText(facets, lens)
    if facets == nil or lens == nil or lens == "all" or not OverviewAbilityMatchesLens(facets, lens) then
        return nil
    end
    if lens == "damage" then
        if facets.damageValue > 0 then
            return string.format("%d damage per target", facets.damageValue)
        end
        return "Damage"
    elseif lens == "area" then
        if facets.areaSize > 0 then
            return string.format("Area %d", facets.areaSize)
        end
        return "Area"
    elseif lens == "forced" then
        local verb = facets.forcedVerb or "Move"
        verb = string.upper(string.sub(verb, 1, 1)) .. string.sub(verb, 2)
        if facets.forcedDistance > 0 then
            return string.format("%s %d", verb, facets.forcedDistance)
        end
        return "Forced movement"
    elseif lens == "control" then
        if #facets.conditions > 0 then
            return table.concat(facets.conditions, ", ")
        end
        return "Applies an effect"
    elseif lens == "malice" then
        return string.format("%d Malice", facets.maliceCost)
    end
    return nil
end

--Decision 45: the token-UI glyph for each condition an ability can apply
--(charConditions iconid + display, powertable entries preferred - the same
--art players see on tokens). From facets.conditions (parser/effect names),
--matched by lowercased name, never substring.
local function OverviewConditionIcons(facets)
    local result = {}
    if facets == nil or facets.conditions == nil or #facets.conditions == 0 then
        return result
    end
    local table_ = dmhub.GetTable(CharacterCondition.tableName) or {}
    for _, name in ipairs(facets.conditions) do
        local wanted = string.lower(name)
        local best = nil
        for _, cond in unhidden_pairs(table_) do
            if string.lower(cond.name or "") == wanted then
                if best == nil or (cond.powertable and not best.powertable) then
                    best = cond
                end
            end
        end
        if best ~= nil and best.iconid ~= nil then
            result[#result + 1] = {
                name = best.name,
                icon = best.iconid,
                bgcolor = (best.display ~= nil and best.display.bgcolor) or "white",
            }
        end
    end
    return result
end

--Movement cross-section diagram during ability movement targeting.
--
--For any ability-driven movement preview -- forced move (push/pull/slide,
--"straightline"), regular movement/shift (pathfind), or teleport (direct) --
--show the same floating tooltip the manual token-drag uses, including the
--side-on movement cross-section diagram. We fire the SAME "tiletooltip" event
--the drag flow uses (handled in GameHud.lua, which builds the tooltip +
--CreateMovementDiagramPanel from movingToken/movingPath). GameHud gates the
--diagram on whether the path has vertically interesting features (elevation
--changes, walls climbed/flown over, falls, tokens crossed) -- see
--DiagramProfileFromPath -- so flat moves show no diagram regardless of type. We
--tear it down with GameHud.FinishTokenMoving.
--
--We deliberately do NOT call GameHud.TokenMoving to build the text: it reads
--many path fields (difficultSteps, squeezeSteps, waterSteps, hazards, ...) that
--are only populated on a real drag/move path. On a MarkMovementArrow move
--PREVIEW path some of those engine getters NRE (return nil), and TokenMoving then
--crashes on math.floor(nil). We only need movingToken/movingPath to reach the
--diagram, so we build a minimal, preview-safe text ourselves. See
--MOVEMENT_CROSS_SECTION_REFERENCE.md.
local g_movementDiagramShown = false

--- @param token CharacterToken the moving token
--- @param path LuaPath the previewed movement path
--- @param label nil|string already-translated movement-type noun ("Movement",
---        "Shift", "Teleport", "Forced Movement"); defaults to "Movement".
--- @param alternates nil|{path: LuaPath, label: string, tier: integer, loc: Loc, color: string}[]
---        lower-tier shortfall outcomes for tiered jumps; forwarded through the
---        tiletooltip event as movingPathAlternates so the movement diagram can
---        render ghost outcomes (multi-outcome rendering is engine work; the
---        GameHud handler ignores the arg until then).
--- @param damages nil|{collision: nil|number, fall: nil|number} predicted damage
---        numbers (already computed from the game rules); forwarded through the
---        tiletooltip event as movingPathDamages so the movement diagram draws
---        the same red "-N" annotations the map targeting labels show.
local function ShowMovementDiagram(token, path, label, alternates, damages)
    if token == nil or path == nil or GameHud.instance == nil then
        return
    end
    local dialog = GameHud.instance.dialog
    local sheet = dialog and dialog.sheet
    if sheet == nil then
        return
    end

    label = label or tr("Movement")

    --Minimal, preview-path-safe movement text (numSteps / origin / destination
    --are populated on a move preview path; the fields TokenMoving reads are not).
    local text = label
    if path.numSteps ~= nil then
        local distance = path.numSteps * dmhub.FeetPerTile
        text = string.format("%s: %s %s", label, MeasurementSystem.NativeToDisplayString(distance), string.lower(MeasurementSystem.UnitName()))
    end

    if path.origin ~= nil and path.destination ~= nil then
        local altitudeDelta = path.destination.altitude - path.origin.altitude
        if altitudeDelta < 0 then
            text = string.format(tr("%s (%d elevation)"), text, round(altitudeDelta))
        elseif altitudeDelta > 0 then
            text = string.format(tr("%s (+%d elevation)"), text, round(altitudeDelta))
        end
    end

    sheet:FireEvent("tiletooltip", {
        loc = path.destination,
        text = text,
        movingToken = token,
        movingPath = path,
        movingPathAlternates = alternates,
        movingPathDamages = damages,
    })
    g_movementDiagramShown = true
end

local function ClearMovementDiagram()
    if not g_movementDiagramShown then
        return
    end
    g_movementDiagramShown = false
    if GameHud.instance ~= nil then
        GameHud.instance:FinishTokenMoving()
    end
end

--Tiered-jump hover state: markers on the tiles where lower-tier (shortfall)
--jumps land, plus the tier the hovered tile requires (read by the confirm
--label) and whether even the top tier cannot reach it. Rebuilt on every
--hover; cleared when the hover moves or targeting ends.
local g_jumpShortfallMarkers = {}
local g_jumpHoverRequiredTier = nil
local g_jumpHoverUnreachable = false

local function ClearJumpShortfallMarkers()
    for _, marker in ipairs(g_jumpShortfallMarkers) do
        marker:Destroy()
    end
    g_jumpShortfallMarkers = {}
    g_jumpHoverRequiredTier = nil
    g_jumpHoverUnreachable = false
end

local function ClearPointTargeting()
    ClearMovementDiagram()
    ClearJumpShortfallMarkers()

    if g_pointTargeting.labelsAtPathEnd ~= nil then
        for _, label in ipairs(g_pointTargeting.labelsAtPathEnd) do
            label:Destroy()
        end
    end

    if g_pointTargeting.fallingShape ~= nil then
        g_pointTargeting.fallingShape:Destroy()
    end

    if g_pointTargeting.fallDamageLabel ~= nil then
        g_pointTargeting.fallDamageLabel:Destroy()
    end

    if g_pointTargeting.label ~= nil then
        g_pointTargeting.label:Destroy()
    end

    if g_pointTargeting.radius ~= nil then
        g_pointTargeting.radius:Destroy()
    end

    if g_pointTargeting.partnerRadius ~= nil then
        g_pointTargeting.partnerRadius:Destroy()
    end

    if g_pointTargeting.labelsAtThroughCreatures ~= nil then
        for _, marker in ipairs(g_pointTargeting.labelsAtThroughCreatures) do
            marker:Destroy()
        end
    end

    g_pointTargeting = {}
end

--- Fire movementplan on every token but the caster so opportunity-attack warning
--- arrows can compute during ability-targeted movement. Mirrors the drag broadcast
--- in CharacterToken.cs (FireHudEventRecursive("movementplan", ...)). The token-side
--- handler in DrawSteelTokenHud.lua filters by movementType; teleport/shift/forced
--- are no-ops there.
--- @param caster nil|CharacterToken the moving token
--- @param path nil|LuaPath the planned path; nil clears prior warnings
--- @param movementType nil|string "walk"|"move"|"jump"|"teleport"|"shift"|"forced"|nil
local function BroadcastMovementPlan(caster, path, movementType)
    if caster == nil then
        return
    end
    for _, tok in ipairs(dmhub.allTokens) do
        if tok ~= nil and tok.valid and tok.id ~= caster.id and tok.sheet ~= nil then
            tok.sheet:FireEventTree("movementplan", tok, caster, path, movementType)
        end
    end
end

local function PushCasterToken(token)
    if token == nil then
        return
    end

    dmhub.tokenInfo:PushSelectedTokenOverride(token)

    g_casterTokenStack[#g_casterTokenStack + 1] = token
    g_token = token
    print("ActionBar:: push g_token =", g_token)
    g_creature = g_token.properties
end

local function TryPopCasterToken()
    if #g_casterTokenStack == 0 then
        return false
    end

    dmhub.tokenInfo:PopSelectedTokenOverride(g_casterTokenStack[#g_casterTokenStack])
    g_token = dmhub.selectedOrPrimaryTokens[1]
    print("ActionBar:: pop g_token =", g_token)
    g_creature = g_token and g_token.properties or nil

    g_casterTokenStack[#g_casterTokenStack] = nil
    return true
end

--- @type nil|string
local g_prevCharid

--- @type table<string, number>
local g_resources

--- @type ActivatedAbility[]
local g_abilities
local g_initiative

local g_newActionBar = setting {
    id = "newactionbar",
    description = "Use New Action Bar",
    storage = "preference",
    section = "General",
    default = true,
    editor = "check",
}

local g_preferredForcedMovementType = setting {
    id = "preferredforcedmovementtype",
    storage = "preference",
    default = "none",
}

-- Transient highlight for an ability revealed from search (on-map monster
-- ability result). Pulsed via Panel:PulseClass, so the @accent fill applies
-- instantly then fades over transitionTime. Merged into the action bar root
-- cascade so it resolves on the ability headings inside an opened drawer menu.
-- Each reveal pulse fades the accent IN over SEARCH_REVEAL_FADE (eased), HOLDS
-- it, fades OUT over the same time, then a slight SEARCH_REVEAL_GAP pause before
-- the next - a gentle "here I am" breathe rather than a strobe (matches the
-- sheet reveal).
local SEARCH_REVEAL_FADE = 0.8
local SEARCH_REVEAL_HOLD = 0.3
local SEARCH_REVEAL_GAP = 0.1
local SEARCH_REVEAL_PULSES = 3
local SEARCH_REVEAL_RULE = {
    selectors = { "abilityHeading", "searchReveal" },
    bgcolor = "@accent",
    transitionTime = SEARCH_REVEAL_FADE,
    easing = "easeInOutSine",
}

-- True while the director has the game in respite mode. During a respite the
-- initiative queue is hidden and its gameMode is "respite" (same check as the
-- End Respite bar in MCDMInitiativeBar).
--
-- Respite activities are hosted by two different drawers depending on this: the
-- dedicated respite drawer during a respite, and the maneuver drawer outside of
-- one. Every site that routes them has to read the gate the same way, so they
-- all call through here.
local function InRespiteMode()
    local q = dmhub.initiativeQueue
    return q ~= nil and q.hidden and q.gameMode == "respite"
end

-- Which drawer an ability lives in, mirroring the per-type filtering the
-- "menu" event applies to g_abilities. Returns the drawer's `type` string, or
-- nil when the ability is not surfaced by any drawer (then the reveal is a
-- no-op). Used by Search.RevealActionBarAbility below.
local function DrawerTypeForAbility(ability)
    local cat = ability.categorization
    if cat == "Malice" then
        return "malice"
    end
    if cat == "Trigger" or cat == "Villain Action" then
        return "trigger"
    end
    if cat == "Move" then
        return "move"
    end
    local rid = ability.actionResourceId
    if rid == CharacterResource.actionResourceId then
        return "action"
    end
    if rid == CharacterResource.respiteActivityId then
        --Respite activities live in their own drawer during a respite, and under
        --the maneuver drawer outside of one. The novel-ability pip has to follow
        --them, or a newly gained respite activity would flag a hidden drawer.
        if InRespiteMode() then
            return "respite"
        end
        return "maneuver"
    end
    if rid == CharacterResource.maneuverResourceId
        or rid == "none"
        or rid == CharacterResource.freeManeuverResourceId then
        --Free / maneuver abilities all surface in the maneuver drawer.
        return "maneuver"
    end
    return nil
end

-- =============================================================================
-- Novel ability tracking.
--
-- Every time the bar regenerates g_abilities for a creature we diff the list
-- against the last snapshot we took for that creature. Anything that wasn't
-- there before is "novel" and gets flagged, so a hero who just levelled up (or
-- picked up a kit/item, or was granted an ability by an effect mid-combat)
-- gets a nudge toward the new toy instead of having to go hunting for it.
--
-- The record is deliberately temporary: a plain in-memory table, cleared on
-- restart or Lua reload. A creature's FIRST snapshot in a session is a silent
-- baseline - nothing is novel - otherwise every token you select at session
-- start would light up every drawer.
--
-- Three states per ability key:
--   g_seenAbilities[charid][key]   - we have seen this ability before (never
--                                    cleared, so an ability that comes and goes
--                                    with an effect only announces itself once)
--   g_novelAbilities[charid][key]  - novel and unacknowledged. Puts the marker
--                                    on the corner of the owning drawer.
--   g_ackedNovelAbilities[key]     - novel, drawer marker already dismissed by
--                                    opening it. Puts the marker on the ability
--                                    row inside the open menu. Cleared - for
--                                    good - when the menu closes.
-- =============================================================================
local g_seenAbilities = {}
local g_novelAbilities = {}
local g_ackedNovelAbilities = {}
local g_ackedNovelCharid = nil

--Stable per-ability identity. Melee/ranged bifurcations are DeepCopies of one
--parent so they share a guid; the variation flags separate them.
local function NovelAbilityKey(ability)
    local ok, key = pcall(function()
        local guid = ability:try_get("guid") or ability.name
        if ability:try_get("isMeleeVariation") then
            return guid .. ":melee"
        elseif ability:try_get("isRangedVariation") then
            return guid .. ":ranged"
        end
        return guid
    end)

    if not ok then
        return nil
    end

    return key
end

--Diff the freshly generated ability list against our snapshot for this
--creature. Returns true when the set of drawer markers changed.
local function UpdateNovelAbilities(charid, abilities)
    if charid == nil then
        return false
    end

    local current = {}
    local count = 0
    for _, ability in ipairs(abilities or {}) do
        local key = NovelAbilityKey(ability)
        if key ~= nil then
            current[key] = DrawerTypeForAbility(ability) or false
            count = count + 1
        end
    end

    --A creature mid-load can briefly report no abilities at all. Never take
    --that as a baseline, or everything it really has turns up "novel".
    if count == 0 then
        return false
    end

    local seen = g_seenAbilities[charid]
    if seen == nil then
        --First sighting this session: baseline only.
        g_seenAbilities[charid] = current
        return false
    end

    local novel = g_novelAbilities[charid]
    local changed = false
    for key, drawerType in pairs(current) do
        if seen[key] == nil then
            seen[key] = drawerType
            --Abilities no drawer surfaces (drawerType false) are recorded as
            --seen but never flagged - there would be nowhere to show them.
            if drawerType then
                novel = novel or {}
                if novel[key] == nil and g_ackedNovelAbilities[key] == nil then
                    novel[key] = drawerType
                    changed = true
                end
            end
        end
    end

    --Retire flags for abilities that have since gone away again (a granting
    --effect expired before the player ever opened the drawer). Otherwise the
    --badge would sit there pointing at a menu that no longer lists it.
    if novel ~= nil then
        for key, _ in pairs(novel) do
            if current[key] == nil then
                novel[key] = nil
                changed = true
            end
        end
    end

    g_novelAbilities[charid] = novel

    return changed
end

--Does this drawer currently own any unacknowledged novel abilities?
local function DrawerHasNovelAbilities(charid, drawerType)
    if charid == nil or drawerType == nil then
        return false
    end

    local novel = g_novelAbilities[charid]
    if novel == nil then
        return false
    end

    for _, t in pairs(novel) do
        if t == drawerType then
            return true
        end
    end

    return false
end

local function AbilityIsNovel(ability)
    if g_ackedNovelCharid == nil then
        return false
    end

    local key = NovelAbilityKey(ability)
    return key ~= nil and g_ackedNovelAbilities[key] ~= nil
end

--The menu for this drawer is opening: move its novel abilities from
--"drawer marker" to "ability row marker". Returns true if anything moved.
local function AcknowledgeNovelAbilities(charid, drawerType)
    g_ackedNovelAbilities = {}
    g_ackedNovelCharid = charid

    if charid == nil or drawerType == nil then
        return false
    end

    local novel = g_novelAbilities[charid]
    if novel == nil then
        return false
    end

    local moved = false
    for key, t in pairs(novel) do
        if t == drawerType then
            g_ackedNovelAbilities[key] = true
            novel[key] = nil
            moved = true
        end
    end

    return moved
end

--The menu closed: the acknowledged abilities have now been shown to the
--player, so they stop being novel entirely.
local function ClearAcknowledgedNovelAbilities()
    local hadAny = next(g_ackedNovelAbilities) ~= nil
    g_ackedNovelAbilities = {}
    g_ackedNovelCharid = nil
    return hadAny
end

--Marker pip. Used both on the corner of a drawer and on an ability row; the
--"onAbility" variant sits inside the row rather than overhanging the corner.
--Non-interactable so a click lands on the drawer/row underneath it. Drive it
--with the "setNovel" event.
local function NovelContentMarker(extraClass)
    local resultPanel

    resultPanel = gui.Panel {
        classes = { "novelMarker", "collapsed", extraClass },
        floating = true,
        interactable = false,
        bgimage = "panels/square.png",
        rotate = 45,

        gui.Panel {
            classes = { "novelMarkerInner" },
            bgimage = "panels/square.png",
            interactable = false,
        },

        --Slow breathe so it reads as "look here" without strobing. Only ticks
        --while the marker is actually up.
        think = function(element)
            element:SetClass("pulse", not element:HasClass("pulse"))
        end,

        setNovel = function(element, novel)
            if novel == element.data.novel then
                return
            end
            element.data.novel = novel
            element:SetClass("collapsed", not novel)
            element.thinkTime = cond(novel, 0.8, nil)
            if novel then
                element:FireEvent("think")
            else
                element:SetClass("pulse", false)
            end
        end,

        data = { novel = false },
    }

    return resultPanel
end

local NOVEL_MARKER_RULES = {
    {
        selectors = { "novelMarker" },
        width = 14,
        height = 14,
        bgcolor = "@accent",
        borderWidth = 1,
        borderColor = "@fgStrong",
        halign = "right",
        valign = "top",
        margin = -4,
    },
    {
        --On an ability row the pip badges the top-left corner of the ability
        --icon. Top-right is taken there by the cost diamond.
        selectors = { "novelMarker", "onAbility" },
        width = 12,
        height = 12,
        halign = "left",
        valign = "top",
        margin = 3,
    },
    {
        selectors = { "novelMarker", "pulse" },
        brightness = 2,
        transitionTime = 0.8,
        easing = "easeInOutSine",
    },
    {
        selectors = { "novelMarkerInner" },
        width = "45%",
        height = "45%",
        halign = "center",
        valign = "center",
        bgcolor = "@fgStrong",
    },
}


--Director multi-monster overview column footer (slice (d)); see the
--OverviewColumnFooter block above ActionSubMenu for the design notes.
--Merged into the action bar root's cascade like NOVEL_MARKER_RULES so
--the rules resolve on columns inside an open action menu.
--Pooled row count: the signals view shows OVERVIEW.FOOTER_ROWS then "+N
--more"; the owner-selection prompt (slice (e)) may show up to this many
--selectable members before its own "+N more".

local OVERVIEW_FOOTER_RULES = {
    {
        selectors = { "overviewFooter" },
        width = 205,
        height = "auto",
        flow = "vertical",
        halign = "center",
        bgimage = true,
        bgcolor = "#1D1D1D",
        borderColor = "#606060",
        borderWidth = 1.5,
        pad = 4,
        borderBox = true,
    },
    {
        selectors = { "overviewFooter", "hover" },
        borderColor = "white",
        brightness = 1.2,
        transitionTime = 0.1,
    },
    {
        selectors = { "overviewFooterHeader" },
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
    },
    {
        selectors = { "overviewFooterText" },
        width = "100%-40",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "center",
        lmargin = 6,
    },
    --F2-4: every text in the footer sits at the X11 READ floor (12px) or
    --above; 11px was reported unreadable on a laptop. Names never wrap and
    --ellipsize instead of overflowing the column border.
    --P2-c1 lens bar, field-test-4 restyle: flat and quiet (icon-rail
    --spirit) - no box, no border; a row of text tabs, active = gold with a
    --2px underline, zero-count tabs dimmed but pressable. The row keeps a
    --near-black translucent backing so it reads over any map and eats the
    --click (never a click-through to the map).
    {
        selectors = { "overviewLensBar" },
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "bottom",
        bmargin = 6,
    },
    {
        selectors = { "overviewLensRow" },
        width = 6 * 106 + 8,
        height = "auto",
        flow = "horizontal",
        halign = "center",
        valign = "center",
        bgimage = true,
        bgcolor = "#000000AA",
        cornerRadius = 4,
        pad = 2,
        borderBox = false,
    },
    {
        selectors = { "overviewLensTab" },
        width = 106,
        height = "auto",
        halign = "left",
        valign = "center",
        hpad = 4,
        vpad = 3,
        borderBox = true,
        bgcolor = "clear",
    },
    {
        selectors = { "overviewLensTab", "hover" },
        bgcolor = "#ffffff18",
        transitionTime = 0.1,
    },
    {
        selectors = { "overviewLensTabLabel" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        opacity = 0.75,
        textAlignment = "center",
        textWrap = false,
        textOverflow = "ellipsis",
    },
    {
        selectors = { "overviewLensTabLabel", "parent:hover" },
        color = "white",
        opacity = 1,
    },
    {
        selectors = { "overviewLensTabLabel", "parent:active" },
        color = Styles.Ability.goldColor,
        opacity = 1,
        bold = true,
    },
    {
        selectors = { "overviewLensTabLabel", "parent:zero", "~parent:active" },
        opacity = 0.35,
    },
    {
        selectors = { "overviewLensTabLine" },
        width = "100%-8",
        height = 2,
        halign = "center",
        valign = "bottom",
        tmargin = 2,
        bgimage = true,
        bgcolor = Styles.Ability.goldColor,
    },
    {
        selectors = { "overviewLensEmpty" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        textAlignment = "center",
        textWrap = true,
        tmargin = 4,
    },
    --Match side pops (field test 4: the dim alone did not steer the eye to
    --Toxic Winds over Swamp Gas); off-lens dim floors at .45 per X3.
    {
        selectors = { "abilityHeading", "onLens" },
        borderColor = Styles.Ability.goldColor,
        borderWidth = 2.5,
        brightness = 1.15,
    },
    {
        selectors = { "abilityHeading", "offLens" },
        saturation = 0.5,
    },
    --Decision 45 condition glyph row on overview chips (>= 16px, X15).
    {
        selectors = { "overviewConditionRow" },
        width = "100%-20",
        height = 18,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        vmargin = 1,
    },
    {
        selectors = { "overviewConditionIcon" },
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        rmargin = 3,
        bgcolor = "white",
    },
    {
        selectors = { "overviewConditionMore" },
        width = "auto",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        halign = "left",
        valign = "center",
    },
    {
        selectors = { "overviewLensKey" },
        fontSize = 13,
        color = "#C9A86A",
        textWrap = false,
        width = "100%-20",
        height = "auto",
        halign = "left",
        valign = "center",
        vmargin = 1,
    },
    {
        selectors = { "overviewLensKey", "expended" },
        color = Styles.textColor,
    },
    --X6 "Everyone can:" - common abilities (Charge, Grab, Knockback...) that
    --satisfy the active lens, dimmed, under the lens bar.
    {
        selectors = { "overviewLensEveryone" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        opacity = 0.75,
        textAlignment = "center",
        textWrap = true,
        tmargin = 4,
    },
    {
        selectors = { "abilityHeading", "offLens" },
        opacity = 0.45,
    },
    --Field test 10: the DMG badge (red surge + label) on standout damage
    --chips; clear backing so the chip behind still hovers/presses.
    {
        selectors = { "overviewDmgBadge" },
        width = 18,
        height = "auto",
        bgcolor = "clear",
    },
    {
        selectors = { "overviewDmgIcon" },
        width = 16,
        height = 16,
        halign = "center",
        bgcolor = "#E06464",
    },
    --P2-e threat-estimate line: allowed to wrap (reasons can be long).
    {
        selectors = { "overviewFooterRisk" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        textAlignment = "left",
        textWrap = true,
    },
    --P2-a status strip: the token HUD's status icons at >= 16px (X15);
    --threat flags (hero-applied marks/conditions) carry a red ring.
    {
        selectors = { "overviewFooterPortraitColumn" },
        width = 34,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },
    {
        selectors = { "overviewStatusStrip" },
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        valign = "center",
        tmargin = 3,
    },
    {
        selectors = { "overviewStatusIcon" },
        width = 18,
        height = 18,
        halign = "left",
        valign = "center",
        rmargin = 3,
        bgcolor = "white",
        borderWidth = 0,
    },
    {
        selectors = { "overviewStatusIcon", "threat" },
        borderWidth = 2,
        borderColor = "#E06464",
    },
    {
        selectors = { "overviewStatusIcon", "hover" },
        brightness = 1.3,
    },
    {
        selectors = { "overviewStatusMore" },
        width = "auto",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        halign = "left",
        valign = "center",
    },
    --F2-8 dismiss "x" at the footer's top-right (floating; the name label
    --leaves it room).
    {
        selectors = { "overviewDismiss" },
        width = 14,
        height = 14,
        bgcolor = "#9a9a9a",
        opacity = 0.8,
        halign = "right",
        valign = "top",
    },
    {
        selectors = { "overviewDismiss", "hover" },
        bgcolor = "white",
        opacity = 1,
        transitionTime = 0.1,
    },
    {
        selectors = { "overviewDismiss", "press" },
        bgcolor = "#cccccc",
    },
    {
        selectors = { "overviewFooterNameRow" },
        width = "100%-16",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
    },
    {
        selectors = { "overviewCaptainIcon" },
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        lmargin = 4,
        bgcolor = "white",
    },
    {
        selectors = { "overviewFooterName" },
        width = "auto",
        maxWidth = "100%-22",
        height = "auto",
        fontSize = 14,
        bold = true,
        color = Styles.Ability.goldColor,
        textAlignment = "left",
        textWrap = false,
        textOverflow = "ellipsis",
    },
    {
        selectors = { "overviewFooterLine" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        textAlignment = "left",
        textWrap = false,
        textOverflow = "ellipsis",
    },
    {
        selectors = { "overviewFooterRow" },
        width = "100%",
        height = 32,
        flow = "horizontal",
        halign = "left",
        tmargin = 3,
        bgimage = true,
        bgcolor = "clear",
    },
    {
        selectors = { "overviewFooterRow", "hover" },
        bgcolor = "#ffffff22",
        transitionTime = 0.1,
    },
    {
        selectors = { "overviewFooterRowText" },
        width = "100%-28",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "center",
        lmargin = 4,
    },
    {
        selectors = { "overviewFooterRowLabel" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        textAlignment = "left",
        textWrap = false,
        textOverflow = "ellipsis",
        halign = "left",
    },
    {
        selectors = { "overviewFooterRowSignal" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        opacity = 0.85,
        textAlignment = "left",
        textWrap = false,
        textOverflow = "ellipsis",
        halign = "left",
    },
    {
        selectors = { "overviewFooterMore" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        textAlignment = "left",
        tmargin = 3,
        lmargin = 28,
    },
    --Whole-column acted greying (Decision 50 / F2-7): once every member of a
    --column has acted this round, ALL of its chips grey out - title,
    --keywords, icon, action type - so "do not use these" is unmistakable,
    --while the chips stay discoverable and clickable (Decision 4; opacity
    --floor per X3). Driven by an "acted" class tree on each chip (the same
    --mechanism as "expended"); the earlier parent:acted opacity rule was
    --too subtle to see in play.
    {
        selectors = { "abilityHeading", "acted" },
        opacity = 0.55,
        borderColor = "#404040",
    },
    {
        selectors = { "abilityTitle", "acted" },
        color = "#8a8a8a",
    },
    {
        selectors = { "abilityInfoLabel", "acted" },
        color = "#8a8a8a",
    },
    {
        selectors = { "overviewActionType", "acted" },
        color = "#8a8a8a",
    },
    {
        selectors = { "abilityIconPanel", "acted" },
        saturation = 0,
        opacity = 0.6,
    },
    --Action economy on overview chips (field test 2): a legible 12px line
    --under the keywords, gold so it reads as structure, not as a keyword.
    --Community colour coding (field test 4): Maneuver = blue. The WORD is
    --the colour-blind channel (X12) - colour is reinforcement only.
    {
        selectors = { "overviewActionType" },
        fontSize = 13,
        bold = true,
        color = Styles.Ability.goldColor,
        textWrap = false,
        width = "100%-20",
        height = "auto",
        halign = "left",
        valign = "center",
        vmargin = 1,
    },
    {
        selectors = { "overviewActionType", "maneuver" },
        color = "#5B9BD5",
    },
    {
        selectors = { "overviewActionType", "freeaction" },
        color = "#B8B8B8",
    },
    {
        selectors = { "overviewActionType", "expended" },
        color = Styles.textColor,
    },
    --Hairline between a column's main actions (above) and its maneuvers /
    --free actions (below), so "one above + one below" reads at a glance.
    {
        selectors = { "overviewActionDivider" },
        width = 205 - 24,
        height = 2,
        halign = "center",
        vmargin = 5,
        bgimage = true,
        bgcolor = Styles.Ability.goldColor,
        opacity = 0.6,
    },
    --Slice (e): owner-selection prompt (instruction line + selectable member
    --rows) and the "Take <Creature>'s turn" button with its inline reason.
    {
        selectors = { "overviewFooterPrompt" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        bold = true,
        color = Styles.Ability.goldColor,
        textAlignment = "left",
        textWrap = true,
        tmargin = 4,
    },
    {
        selectors = { "overviewFooterRow", "promptOption" },
        bgcolor = "#ffffff11",
        borderColor = "#606060",
        borderWidth = 1,
    },
    {
        selectors = { "overviewFooterRow", "promptOption", "hover" },
        bgcolor = "#ffffff33",
        borderColor = "white",
    },
    {
        selectors = { "overviewTakeTurn" },
        width = "100%",
        height = 26,
        tmargin = 6,
        bgimage = true,
        bgcolor = "#2A2A2A",
        borderColor = Styles.Ability.goldColor,
        borderWidth = 1,
        fontSize = 13,
        bold = true,
        color = Styles.Ability.goldColor,
        textAlignment = "center",
        textWrap = false,
        borderBox = true,
        hpad = 4,
    },
    {
        selectors = { "overviewTakeTurn", "hover" },
        bgcolor = "#3A3A3A",
        borderColor = "white",
        transitionTime = 0.1,
    },
    {
        selectors = { "overviewTakeTurn", "disabled" },
        opacity = 0.5,
        color = Styles.textColor,
        borderColor = "#606060",
    },
    {
        selectors = { "overviewTakeTurn", "disabled", "hover" },
        bgcolor = "#2A2A2A",
        borderColor = "#606060",
    },
    {
        selectors = { "overviewTakeTurnReason" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        color = Styles.textColor,
        textAlignment = "center",
        textWrap = true,
        tmargin = 2,
    },
}

local function ActionBarDrawer(args)
    local m_resourceid
    local m_resourceInfo

    local m_moveBar
    local m_rightInfoText

    local m_costDiamond

    local m_glow


    if args.type == "malice" then
        m_glow = gui.Panel {
            blend = "add",
            floating = true,
            bgimage = true,
            width = "90%",
            height = 80,
            halign = "center",
            valign = "top",
            bgcolor = "white",
            y = -80,
            interactable = false,
            gradient = Styles.Ability.maliceGlowGradient,

            refresh = function(element)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden or q:ChoosingTurn() then
                    element:SetClass("off", true)
                    return
                end

                local malice = CharacterResource.GetMalice()
                local canAfford = false

                for _, ability in ipairs(g_abilities) do
                    if ability.categorization == "Malice" then
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })
                        if cost ~= nil and cost <= malice then
                            canAfford = true
                            break
                        end
                    end
                end

                if not canAfford then
                    element:SetClass("off", true)
                    return
                end

                local currentInitiativeId = dmhub.initiativeQueue.currentTurn
                local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface,
                currentInitiativeId) or {}
                for _, token in ipairs(tokens) do
                    local usage = token.properties:GetResourceUsage(CharacterResource.actionResourceId, "round")
                    if usage ~= nil and usage > 0 then
                        element:SetClass("off", true)
                        return
                    end

                    local usage = token.properties:GetResourceUsage(CharacterResource.maneuverResourceId, "round")
                    if usage ~= nil and usage > 0 then
                        element:SetClass("off", true)
                        return
                    end
                end

                element:SetClass("off", false)
            end,

            styles = {
                {
                    brightness = 3,
                },
                {
                    selectors = { "on" },
                    brightness = 5,
                    transitionTime = 0.6,
                    easing = "easeInOutSine",
                },
                {
                    selectors = { "off" },
                    transitionTime = 0.5,
                    brightness = 0,
                },
            },

            thinkTime = 0.6,
            think = function(element)
                element:SetClass("on", not element:HasClass("on"))
            end,
        }

        m_rightInfoText = gui.Label {
            maxWidth = 100,
            fontSize = 10,
            minFontSize = 6,
            bold = true,
            color = "white",
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            rotate = -135,
            events = {},
        }

        m_costDiamond = gui.Panel {
            styles = { Styles.ActionMenu,

                gui.Style {
                    classes = { "costDiamond" },
                    brightness = 1,
                    borderColor = "grey",
                    priority = 5,
                },

                gui.Style {
                    classes = { "costDiamond", "parent:hover" },
                    brightness = 1.5,
                    borderColor = "grey",
                    priority = 5,
                },

            },
            classes = { "costDiamond", "malice" },
            floating = true,
            rotate = 135,

            halign = "center",
            valign = "top",
            vmargin = -13.5,
            bgcolor = "white",

            border = { x1 = 0, y1 = 2, x2 = 2, y2 = 0 },
            --bgcolor = "#10110F",
            gradient = Styles.Ability.maliceDiamondGradient,



            --vback

            gui.Panel {
                classes = { "costInnerDiamond", "malice" },

                --bgcolor = "#e9b86f",
                --borderWidth = 1,
                --borderColor = "white",

                m_rightInfoText,

            },



        }





        m_rightInfoText.editable = true
        m_rightInfoText.numeric = true
        m_rightInfoText.characterLimit = 2
        m_rightInfoText.swallowPress = true
        m_rightInfoText.selfStyle.minWidth = 30
        m_rightInfoText.selfStyle.textAlignment = "center"
        m_rightInfoText.selfStyle.fontSize = 14
        m_rightInfoText.selfStyle.bold = true
        m_rightInfoText.events.change = function(element)
            local value = tonumber(element.text) or 0
            if value < 0 then
                value = 0
            end
            CharacterResource.SetMalice(value, "Manually set")
        end
        m_rightInfoText.events.hover = function(element)
            local history = CharacterResource.GetGlobalResourceHistory(CharacterResource.maliceResourceId)
            element.tooltip = gui.StatsHistoryTooltip { description = "Malice", entries = history }
        end
        m_rightInfoText.events.refresh = function(element)
            element.text = string.format("%d", CharacterResource.GetMalice())
        end
        -- Malice lives in a shared global-resource document, so it can change
        -- from another client or the [[resource:malice]] journal counter without
        -- the action bar firing its own refresh. Monitor that document so the
        -- displayed value updates live in those cases too.
        m_rightInfoText.monitorGame = CharacterResource.GlobalResourcePath()
        m_rightInfoText.events.refreshGame = function(element)
            element.text = string.format("%d", CharacterResource.GetMalice())
        end
    end

    if args.type == "trigger" then
        m_rightInfoText = gui.Label {
            floating = true,
            maxWidth = 100,
            fontSize = 10,
            minFontSize = 6,
            margin = 6,
            bold = true,
            color = Styles.Ability.accentColor,
            halign = "right",
            valign = "top",
            width = "auto",
            height = "auto",
            events = {},
        }
    end

    if args.type == "trigger" then
        m_resourceid = CharacterResource.triggerResourceId
    elseif args.type == "action" then
        m_resourceid = CharacterResource.actionResourceId
    elseif args.type == "maneuver" then
        m_resourceid = CharacterResource.maneuverResourceId
    elseif args.type == "malice" then
        m_resourceid = CharacterResource.maliceResourceId
    elseif args.type == "free" then
        --pass.
    elseif args.type == "respite" then
        --pass. Respite drawer has no resource counter; it just opens its menu.
    elseif args.type == "unique" then
        --pass. The director's multi-monster "Unique Abilities" drawer spans
        --several tokens, so no single resource counter applies.
    else
        local m_segments = {}
        local m_margin = 2
        m_moveBar = gui.Panel {
            floating = true,
            width = "auto",
            height = 6,
            halign = "center",
            valign = "bottom",
            bmargin = 5,
            flow = "horizontal",
            styles = {
                {
                    selectors = { "segment" },
                    bgcolor = Styles.Ability.accentColor,
                },
                {
                    selectors = { "segment", "otherturn" },
                    bgcolor = "#666666",
                },
                {
                    selectors = { "segment", "expended" },
                    bgcolor = "#333333",
                    borderColor = "#666666",
                    borderWidth = 1,
                },
                {
                    selectors = { "segment", "temporarilyBonused" },
                    bgcolor = "#00ffff",
                },
                {
                    selectors = { "segment", "temporarilyBonused", "expended" },
                    bgcolor = "#00ffff",
                    brightness = 0.4,
                    saturation = 0.5,
                },
                {
                    selectors = { "segment", "temporarilyBonused", "otherturn" },
                    bgcolor = "#00ffff",
                    brightness = 0.4,
                    saturation = 0.5,
                },
                {
                    selectors = { "segment", "temporarilyNegated" },
                    bgcolor = "#666666",
                    borderWidth = 1,
                    borderColor = Styles.Ability.forbiddenColor,
                },
            },

            refresh = function(element)
                local movementSpeed = math.max(0, g_creature:CurrentMovementSpeed())
                local moved = g_creature:DistanceMovedThisTurn()

                --find the movement speed base, without temporary modifiers.
                local movementModifications = g_creature:DescribeSpeedModifications()
                local movementSpeedBeforeTemporary = movementSpeed
                for _, info in ipairs(movementModifications) do
                    if info.temporal then
                        movementSpeedBeforeTemporary = info.previous
                    end
                end


                if movementSpeed > 16 then
                    moved = max(0, moved - (movementSpeed - 16))
                    movementSpeed = 16
                end

                local wantedSegments = math.max(movementSpeed, movementSpeedBeforeTemporary)

                if wantedSegments > #m_segments then
                    for i = #m_segments + 1, wantedSegments do
                        m_segments[i] = gui.Panel {
                            classes = { "segment" },
                            width = 6,
                            height = "100%",
                            hmargin = 1,
                            bgimage = true,
                            halign = "center",
                            valign = "center",
                        }
                    end

                    element.children = m_segments
                end

                for i = 1, movementSpeed do
                    m_segments[i]:SetClass("collapsed", false)
                    m_segments[i]:SetClass("temporarilyNegated", false)
                    m_segments[i]:SetClass("temporarilyBonused", i > movementSpeedBeforeTemporary)
                    m_segments[i]:SetClass("otherturn", not g_creature:IsOurTurn())
                    if i <= movementSpeed - moved then
                        m_segments[i]:SetClass("expended", false)
                    else
                        m_segments[i]:SetClass("expended", true)
                    end
                end

                for i = movementSpeed + 1, movementSpeedBeforeTemporary do
                    m_segments[i]:SetClass("collapsed", false)
                    m_segments[i]:SetClass("temporarilyNegated", true)
                end

                for i = wantedSegments + 1, #m_segments do
                    m_segments[i]:SetClass("collapsed", true)
                end
            end,
        }
    end

    if m_resourceid ~= nil then
        m_resourceInfo = dmhub.GetTable(CharacterResource.tableName)[m_resourceid]
        if m_resourceInfo == nil then
            m_resourceid = nil
        end
    end

    args.resourceid = m_resourceid
    args.resourceInfo = m_resourceInfo

    local m_usedAbilityIcon


    if args.type == "trigger" then
        m_usedAbilityIcon = gui.TriggerPanel {
            styles = Styles.TriggerStyles,
            classes = { "hidden" },
            width = 24,
            height = 24,
            halign = "center",
            valign = "center",
        }
    else
        m_usedAbilityIcon = gui.Panel {
            classes = { "hidden" },
            width = 24,
            height = 24,
            halign = "center",
            valign = "center",
        }
    end

    local m_diamond = gui.Panel {
        classes = { "diamond" },
        rotate = 45,
        width = 12,
        height = 12,
        tmargin = -5,
        floating = true,
        halign = "center",
        valign = "top",
        bgimage = true,
    }

    local m_diamondAccent = gui.Panel {
        classes = { "diamondAccent" },
        width = "100%-20",
        height = 6,
        floating = true,
        tmargin = 5,
        halign = "center",
        valign = "top",

        gui.Panel {
            classes = { "diamondAccentLine" },
            width = "50%-6",
            halign = "left",
            valign = "top",
            height = 1,
            bgimage = true,
        },

        gui.Panel {
            classes = { "diamondAccentLine" },
            width = "50%-6",
            halign = "right",
            valign = "top",
            height = 1,
            bgimage = true,
        },


        gui.Panel {
            classes = { "diamondAccentDot" },
            halign = "center",
            valign = "top",
            y = -4,
            width = 10,
            height = 10,
            rotate = 45,
            border = { x1 = 1, y1 = 1, x2 = 0, y2 = 0 },
            bgimage = true,
        },
    }

    local resultPanel

    --Corner pip shown when this drawer holds abilities the creature has only
    --just gained. Cleared when the drawer's menu is opened.
    local m_novelMarker = NovelContentMarker()

    local resultPanelArgs = {
        classes = { "actionBarDrawer" },

        --Stamped so the search reveal can find this drawer by its type.
        data = { drawerType = args.type },

        press = function(element)

            args.drawer = resultPanel
            element:FindParentWithClass("actionBar"):FireEventTree("menu", args)
        end,

        --Fired across the bar whenever the novel-ability set changes.
        refreshNovelAbilities = function(element)
            local charid = nil
            if g_token ~= nil and g_token.valid then
                charid = g_token.charid
            end
            m_novelMarker:FireEvent("setNovel", DrawerHasNovelAbilities(charid, args.type))
        end,

        menuStatus = function(element, menuInfo)
            local active = menuInfo ~= nil and menuInfo.type == args.type
            element:SetClass("active", active)
            element.captureEscape = active
            element.mapfocus = active
        end,

        mappress = function(element, loc, pos)
            element:FireEvent("escape")
        end,

        closemenu = function(element, reason)
            --See the root refresh: a primary-token change alone does not
            --close the overview menu while overview mode persists (F2-8).
            if reason == "primary" and args.type == "unique" and InOverviewMode() then
                return
            end
            if element:HasClass("active") then
                element:FireEvent("press")
            end
        end,

        escapePriority = EscapePriority.CANCEL_ACTION_BAR,
        escape = function(element)
            element:FireEvent("press")
        end,


        refresh = function(element)
            if g_token == nil then return end
            local newToken = g_token.charid ~= element.data.lastcharid

            element.data.lastcharid = g_token.charid

            --Director multi-monster overview: the "unique" drawer exists only
            --in overview mode, and while it is up the per-creature Main
            --Action / Maneuver / Move drawers step aside (Decision 43). All
            --other drawers (Trigger, Malice, Respite) behave exactly as usual.
            local overview = InOverviewMode()
            if args.type == "unique" then
                resultPanel:SetClass("collapsed", not overview)
                if not overview then
                    return
                end

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", true)
                else
                    resultPanel:SetClassTree("available", true)
                end

                return
            elseif args.type == "action" or args.type == "maneuver" or args.type == "move" then
                resultPanel:SetClass("collapsed", overview)
                if overview then
                    return
                end
            end

            if args.type == "respite" then
                --Only show the respite drawer while the game is in respite mode.
                --Outside of a respite these abilities are still reachable: they
                --are listed under the maneuver drawer's "Respite Activities"
                --heading (see the ActionMenu "menu" handler), so this drawer can
                --stay hidden rather than taking up room on the bar.
                local inRespite = InRespiteMode()
                resultPanel:SetClass("hidden", not inRespite)
                if not inRespite then
                    return
                end

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", true)
                else
                    resultPanel:SetClassTree("available", true)
                end

                return
            end

            if args.type == "free" then
                local haveFree = false
                for _, ability in ipairs(g_abilities) do
                    if ability.actionResourceId == "none" and ability.categorization ~= "Malice" and ability.categorization ~= "Move" and ability.categorization ~= "Hidden" then
                        haveFree = true
                        break
                    end
                end

                resultPanel:SetClass("collapsed", not haveFree)
                if not haveFree then
                    return
                end

                --element.text = "Free actions available"
                if newToken then
                    resultPanel:SetClassTreeImmediate("available", true)
                else
                    resultPanel:SetClassTree("available", true)
                end
            end

            if args.type == "malice" then
                local isMonster = g_creature:IsMonster()
                local isFollower = g_creature:IsFollower()
                local isHeroSummon = g_creature:IsHeroSummon()
                resultPanel:SetClass("collapsed", not isMonster or isFollower or isHeroSummon)
                if not isMonster or isFollower or isHeroSummon then
                    return
                end
            end

            if g_initiative == nil then
                if newToken then
                    resultPanel:SetClassTreeImmediate("available", false)
                else
                    resultPanel:SetClassTree("available", false)
                end

                return
            end

            if args.type ~= "trigger" and (not g_token.properties:IsOurTurn()) then
                if newToken then
                    resultPanel:SetClassTreeImmediate("available", false)
                else
                    resultPanel:SetClassTree("available", false)
                end

                return
            end

            if args.type == "move" then
                local movementSpeed = g_creature:CurrentMovementSpeed()
                local moved = g_creature:DistanceMovedThisTurn()

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", moved < movementSpeed)
                else
                    resultPanel:SetClassTree("available", moved < movementSpeed)
                end

                return
            end

            if args.type == "trigger" then
                local triggersDisabled = g_token.properties:CalculateNamedCustomAttribute(
                    "Cannot Use Triggered Abilities")
                if triggersDisabled > 0 then
                    local reason = "Cannot use triggers"
                    local modifications = g_token.properties:DescribeModificationsToNamedCustomAttribute(
                        "Cannot Use Triggered Abilities")
                    if modifications and #modifications > 0 then
                        reason = string.format("%s: Cannot use triggers", modifications[1].key)
                    end

                    --TODO: find way to show why we can't use triggers.
                    --element.text = reason

                    if newToken then
                        resultPanel:SetClassTreeImmediate("available", false)
                    else
                        resultPanel:SetClassTree("available", false)
                    end

                    return
                end

                local triggers = g_token.properties:GetAvailableTriggers()
                local count = 0
                local freecount = 0
                if triggers ~= nil then
                    for key, trigger in pairs(triggers) do
                        count = count + 1
                        if trigger.free then
                            freecount = freecount + 1
                        end
                    end
                end

                local isAvailable = true
                if m_resourceid ~= nil then
                    local usage = g_creature:GetResourceUsage(m_resourceid, m_resourceInfo.usageLimit)
                    local available = (g_resources[m_resourceid] or 0) - usage
                    isAvailable = count > 0 or available > 0
                end

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", isAvailable)
                else
                    resultPanel:SetClassTree("available", isAvailable)
                end



                --m_usedAbilityIcon:SetClass("free", freecount == count)

                --[[
                if count == 1 then
                    m_usedAbilityIcon:SetClass("hidden", false)
                    m_usedAbilityIcon.text = "!"
                    for key, trigger in pairs(triggers) do
                        if trigger.free then
                            element.text = "Free triggered action available"
                        else
                            element.text = "Triggered action available"
                        end
                        m_rightInfoText.text = trigger.text
                    end
                elseif count > 1 then
                    m_usedAbilityIcon:SetClass("hidden", false)
                    m_usedAbilityIcon.text = "!"
                    m_rightInfoText.text = string.format("%d available", count)

                    if freecount == count then
                        element.text = "Free triggered actions available"
                    else
                        element.text = "Triggered actions available"
                    end
                else
                    m_rightInfoText.text = ""
                    if available > 0 then
                        element.text = "Triggered action available"
                        m_usedAbilityIcon:SetClass("hidden", true)
                    else
                        element.text = "Triggered action used"
                        m_usedAbilityIcon.text = ""
                        m_usedAbilityIcon:SetClass("hidden", false)
                        m_usedAbilityIcon.bgimage = "ui-icons/close.png"
                        m_usedAbilityIcon.selfStyle = {
                            bgcolor = "grey",
                        }
                    end
                end
                --]]
                return
            end

            local hideAbilityIcon = true

            if m_resourceid ~= nil then
                local usage = g_creature:GetResourceUsage(m_resourceid, m_resourceInfo.usageLimit)
                local available = (g_resources[m_resourceid] or 0) - usage

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", available > 0)
                else
                    resultPanel:SetClassTree("available", available > 0)
                end


                --[[
                if args.type == "malice" then
                    element.text = "Use at start of a monster's turn"
                elseif available == 0 then
                    local setIcon = false
                    hideAbilityIcon = false
                    local text = nil
                    local history = g_creature:GetStatHistory(m_resourceid)
                    if history ~= nil then
                        local timestamp = 0
                        local refreshid = g_creature:GetResourceRefreshId("round")
                        local abilityid = nil
                        for key, entry in pairs(history.entries) do
                            local ts = entry.timestamp or 0
                            if type(ts) == "string" then
                                ts = math.huge
                            end
                            if entry.refreshid == refreshid and ts > timestamp and entry.abilityid ~= nil then
                                timestamp = ts
                                abilityid = entry.abilityid
                            end
                        end

                        if abilityid ~= nil then
                            for _, ability in ipairs(g_abilities) do
                                if ability.guid == abilityid then
                                    text = string.format("Used on <b>%s</b>", ability.name)

                                    m_usedAbilityIcon.bgimage = ability:GetIcon()
                                    m_usedAbilityIcon.selfStyle = ability:GetIconDisplay()
                                    setIcon = true
                                    break
                                end
                            end
                        end
                    end

                    if setIcon == false then
                        --we couldn't find a specific icon to set so just
                        --use a generic one.
                        m_usedAbilityIcon.bgimage = "ui-icons/close.png"
                        m_usedAbilityIcon.selfStyle = {
                            bgcolor = "grey",
                        }
                    end


                    text = text or string.format("Your %s has been used", args.type)
                    element.text = text
                elseif available == 1 then
                    element.text = string.format("You have one %s available", args.type)
                elseif available == 2 then
                    element.text = string.format("You have two %ss available", args.type)
                else
                    element.text = string.format("You have %d %ss available", available, args.type)
                end
                --]]
            end

            --m_usedAbilityIcon:SetClass("hidden", hideAbilityIcon)
        end,

        gui.Panel {
            classes = { "drawerTopPanel", "collapsed" },
            gui.Panel {
                classes = { "drawerIconPanel", "collapsed" },
                m_usedAbilityIcon,
                swallowPress = true,
                press = function(element)
                    if g_creature == nil or g_token == nil then return end
                    if m_resourceid ~= nil then
                        local usage = g_creature:GetResourceUsage(m_resourceid, m_resourceInfo.usageLimit)
                        local available = (g_resources[m_resourceid] or 0) - usage

                        local target = available - 1
                        if target < 0 then
                            target = g_resources[m_resourceid]
                        end

                        local diff = target - available
                        if diff == 0 then
                            return
                        end

                        g_token:ModifyProperties {
                            description = "Manually Update Resource",
                            execute = function()
                                if diff > 0 then
                                    g_token.properties:RefreshResource(m_resourceid, m_resourceInfo.usageLimit, diff)
                                else
                                    g_token.properties:ConsumeResource(m_resourceid, m_resourceInfo.usageLimit, -diff)
                                end
                            end,
                        }
                    end
                end,
            },

        },

        m_glow,

        m_diamond,
        m_diamondAccent,

        gui.Label {
            classes = { "drawerTitle" },
            text = args.name,
        },

        m_moveBar,

        cond(args.type ~= "malice", m_rightInfoText),

        m_costDiamond,

        m_novelMarker,

    }

    if args.panel ~= nil then
        for key, value in pairs(args.panel) do
            resultPanelArgs[key] = value
        end
    end

    resultPanel = gui.Panel(resultPanelArgs)

    resultPanel:SetClassTree("available", true)

    return resultPanel
end

local g_triggerReactionPanel

function UpdateTriggerReactionPanel(options)
    if g_triggerReactionPanel == nil or not g_triggerReactionPanel.valid then
        return
    end

    g_triggerReactionPanel:FireEventTree("refreshTriggerReactions", options)
end

local function CreateTriggerReactionPanel()
    local m_stateBaseline = nil
    local m_state = nil
    return gui.Panel{
        classes = {"collapsed"},
        halign = "center",
        valign = "bottom",
        flow = "vertical",
        height = 96,
        width = 400,
        y = -16,
        refreshTriggerReactions = function(element, options)
            m_state = options
            if options == nil then
                element:SetClass("collapsed", true)
                element.thinkTime = nil
                return
            end

            m_stateBaseline = dmhub.Time()
            element:SetClass("collapsed", false)
            element.thinkTime = 0.01
            element:FireEvent("think")
        end,
        think = function(element)
            local time = dmhub.Time()
            local elapsed = time - m_stateBaseline
            local r = ((m_state.current + elapsed) - m_state.start)/(m_state.expire - m_state.start)
            if m_state.paused then
                r = 0
            end

            if r >= 1 then
                m_state = nil
                element:SetClass("collapsed", true)
                return
            end
            element:FireEventTree("progress", 1 - r)
        end,
        gui.ProgressDice{
            width = 92,
            height = 92,
            halign = "center",
            thinkTime = 0.01,
            press = function(element)
                if m_state ~= nil then
                    m_state.callback()
                end
            end,
        },
        gui.Label{
            tmargin = 4,
            fontSize = 16,
            width = "100%",
            height = 18,
            textAlignment = "center",
            bgimage = true,
            bgcolor = "black",
            opacity = 0.7,
            refreshTriggerReactions = function(element, options)
                if options == nil then
                    element.text = ""
                    return
                end

                element.text = options.text
            end,
        }
    }
end


local function CreateActionBar()
    local resultPanel

    local m_triggerPanel = ActionBarDrawer { name = "Trigger", type = "trigger" }
    local m_actionPanel = ActionBarDrawer { name = "Main Action", type = "action" }
    local m_maneuverPanel = ActionBarDrawer { name = "Maneuver", type = "maneuver" }
    local m_movementPanel = ActionBarDrawer { name = "Move", type = "move" }
    local m_freeActionsPanel = nil --[[ActionBarDrawer { name = "Free Action", type = "free", panel = {
        floating = true,
        halign = "left",
        valign = "bottom",
        y = -70,
        lmargin = 19,
    } }]]

    --Respite activities get their own drawer, floating above and centered over
    --the main bar. The drawer hides itself unless the game is in respite mode
    --(see the args.type == "respite" handling in ActionBarDrawer).
    local m_respitePanel = ActionBarDrawer { name = "Respite Activity", type = "respite", panel = {
        floating = true,
        halign = "center",
        valign = "bottom",
        y = -70,
    } }

    local m_malicePanel

    --Director multi-monster overview drawer. Built with the same factory as
    --every other drawer so it is visually identical (Decision 40); it hides
    --itself unless InOverviewMode() (see the drawer's refresh), so the
    --single-selection strip is unchanged. Sits where Main Action sits today,
    --so in overview mode the strip reads Trigger | Unique Abilities | Malice.
    --Created for everyone (players simply never leave the collapsed state,
    --since overview mode requires dmhub.isDM) so the children list below has
    --no extra nil hole.
    local m_uniquePanel = ActionBarDrawer { name = "Unique Abilities", type = "unique", panel = {
        classes = { "actionBarDrawer", "collapsed" },
    } }

    if dmhub.isDM then
        m_malicePanel = ActionBarDrawer { name = "Malice", type = "malice", panel = {
        } }
    end

    local m_actionMenu = ActionMenu()

    g_abilityController = CreateAbilityController()

    g_triggerPanel = mod.shared.CreateTriggerPanel()

    --make the permanent triggers panel appear above the drawer.

    local m_triggerDrawerContainer = gui.Panel {
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",

        g_triggerPanel,
        m_triggerPanel,
    }

    resultPanel = gui.Panel {
        classes = { "actionBar" },
        styles = { ThemeEngine.GetStyles(), ThemeEngine.MergeTokens(Styles.ActionBar), ThemeEngine.MergeTokens{ SEARCH_REVEAL_RULE }, ThemeEngine.MergeTokens(NOVEL_MARKER_RULES), ThemeEngine.MergeTokens(OVERVIEW_FOOTER_RULES) },
        width = "100%",
        height = 50,
        halign = "center",
        valign = "bottom",
        flow = "horizontal",
        bmargin = 8,

        data = {},

        create = function(element)
            element.data.themeListener = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = { ThemeEngine.GetStyles(), ThemeEngine.MergeTokens(Styles.ActionBar), ThemeEngine.MergeTokens{ SEARCH_REVEAL_RULE }, ThemeEngine.MergeTokens(NOVEL_MARKER_RULES), ThemeEngine.MergeTokens(OVERVIEW_FOOTER_RULES) }
                end
            end)
        end,

        destroy = function(element)
            if element.data.themeListener ~= nil then
                element.data.themeListener:Deregister()
                element.data.themeListener = nil
            end
        end,

        --Director only: poll the selection so the overview drawer tracks
        --tokens joining/leaving behind an unchanged primary (see
        --SelectionSignature). Not while a caster is pushed or a cast is in
        --flight -- the strip stays put until the cast pops, as it does for
        --invoke prompts today. Players never enter overview mode, so no poll.
        thinkTime = cond(dmhub.isDM, 0.2, nil),
        think = function(element)
            if mod.unloaded or #g_casterTokenStack ~= 0 or g_currentAbility ~= nil then
                return
            end
            if SelectionSignature() ~= element.data.selectionSignature then
                element:FireEventTree("refresh")
                --F2-8: an open Unique Abilities menu follows the selection
                --live (a column dismissed, a token shift-clicked on the map)
                --instead of going stale. No-op unless that menu is up.
                element:FireEventTree("refreshOverview")
            end
        end,

        refresh = function(element)
            if #g_casterTokenStack == 0 then
                g_token = dmhub.selectedOrPrimaryTokens[1]
            end

            --Capture the whole selection for the director overview. Only
            --while no caster is pushed: during an invoked/overview cast the
            --engine's selection override makes selectedOrPrimaryTokens report
            --the caster, and the strip should stay put until the cast pops.
            if #g_casterTokenStack == 0 then
                local selected = {}
                for _, tok in ipairs(dmhub.selectedOrPrimaryTokens) do
                    if tok ~= nil and tok.valid and tok.properties ~= nil then
                        selected[#selected + 1] = tok
                    end
                end
                g_selectedTokens = selected
                local signature = SelectionSignature()
                if signature ~= element.data.selectionSignature then
                    --Field test 8: a lens is a question about THIS selection;
                    --changing the selection resets to All.
                    g_overviewLens = "all"
                end
                element.data.selectionSignature = signature
            end

            if g_token == nil or not g_token.valid then
                g_abilities = {}
                g_prevCharid = nil
                element:SetClass("hidden", true)
                element:HaltEventPropagation()
                element:FireEventTree("closemenu")
                return
            end

            g_creature = g_token.properties

            --Entering or leaving overview mode swaps which drawers are on the
            --strip; an open menu belonging to a drawer that is about to
            --collapse would otherwise linger. Close it, as a token change does.
            local overview = InOverviewMode()
            if element.data.overviewMode ~= overview then
                element.data.overviewMode = overview
                element:FireEventTree("closemenu")
            end

            --Hide the bar when the selected token is a fixture/object, EXCEPT
            --while an invoked cast is driving us (g_casterTokenStack non-empty).
            if g_creature:try_get("treatAsObject", false) and #g_casterTokenStack == 0 then
                element:SetClass("hidden", true)
                element:HaltEventPropagation()
                element:FireEventTree("closemenu")
                return
            end

            element:SetClass("hidden", false)

            if g_prevCharid ~= g_token.charid then
                g_prevCharid = g_token.charid
                --"primary" tells the Unique Abilities drawer/menu to stay up:
                --in overview mode the columns come from the WHOLE selection,
                --so the primary token changing (F2-8 dismissed the primary's
                --column, or a shift-click) is not a reason to close it. Every
                --other menu closes as before.
                element:FireEventTree("closemenu", "primary")
            end

            g_resources = g_token.properties:GetResources()
            g_abilities = g_token.properties:GetActivatedAbilities { bindCaster = true, manualTriggers = true }

            --break out melee and ranged.
            local abilities = {}
            for _, ability in ipairs(g_abilities) do
                if ability.meleeAndRanged then
                    abilities[#abilities + 1] = ability.meleeVariation
                    abilities[#abilities + 1] = ability.rangedVariation
                else
                    abilities[#abilities + 1] = ability
                end
            end

            g_abilities = abilities

            --Diff the freshly generated list against what this creature had
            --last time we looked, so newly gained abilities can announce
            --themselves on the drawer that holds them.
            UpdateNovelAbilities(g_token.charid, g_abilities)
            element:FireEventTree("refreshNovelAbilities")

            g_initiative = dmhub.initiativeQueue
            if g_initiative ~= nil and g_initiative.hidden then
                g_initiative = nil
            end
        end,

        gui.Panel {
            floating = true,
            width = "100%",
            height = "100%+8",
            valign = "top",
            bgimage = true,
            --bgcolor = Styles.Ability.blurColor,
            --blurBackground = true,

            bgcolor = "white",
            gradient = Styles.Ability.gradientBar,



        },

        --m_respitePanel floats above-center, where drawer menus also pop up.
        --Drawer menus re-parent into their source drawer (see ActionMenu's "menu"
        --handler), so they paint within the drawer subtrees below. Keep the
        --respite button first among these so those menus render on top of it
        --rather than behind it.
        m_respitePanel,

        m_triggerDrawerContainer,
        m_uniquePanel,
        m_actionPanel,
        m_maneuverPanel,
        m_movementPanel,
        m_freeActionsPanel,
        m_malicePanel,

        m_actionMenu,

        g_abilityController,
    }

    g_actionBar = resultPanel

    resultPanel:FireEventTree("refresh")

    g_triggerReactionPanel = CreateTriggerReactionPanel()

    local m_containerPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "bottom",
        g_triggerReactionPanel,
        resultPanel,
    }

    return m_containerPanel
end

-- Ability Improvements: optional targeting bonuses toggled by the player in the ability sidebar.
--- @type {mod: table, checked: boolean}[]
local m_activeImprovements = {}

--- @param args nil|{casterToken: nil|CharacterToken, ability: nil|ActivatedAbility, instantCast: nil|boolean, targets: nil|table, cast: nil|table, symbols: nil|table}
local function AbilityHeading(args)
    local args = args or {}

    local m_ability = nil
    local m_cannotAfford = false
    local m_expended = false
    local m_suppressed = false

    local resultPanel

    --The token this chip represents an ability OF. Normally that is the bar's
    --bound token (g_token), but the director's multi-monster overview shows
    --chips for tokens that are NOT the selected one, so an optional
    --args.casterToken overrides it. Resolved through a function rather than
    --captured once: g_token changes on every refresh while this panel is
    --pooled and reused, and args.casterToken can be re-pointed via the
    --"setCasterToken" event below. A caster that has since died/despawned
    --(.valid == false) falls back to g_token so the chip never dereferences a
    --nil .properties.
    local function CasterToken()
        local caster = args.casterToken
        if caster ~= nil and caster.valid then
            return caster
        end
        return g_token
    end

    local SetCannotAfford = function(cannotAffordResourceCost, expended)
        if cannotAffordResourceCost ~= m_cannotAfford then
            m_cannotAfford = cannotAffordResourceCost
            resultPanel:SetClassTree("cannotAfford", m_cannotAfford)
        end

        if expended ~= m_expended then
            m_expended = expended
            resultPanel:SetClassTree("expended", m_expended)
        end
    end

    --we only show an ability from here if we aren't parented by an action menu.
    local m_showingAbility = false

    --Pip shown on rows the creature has only just gained, once the drawer's
    --marker has been dismissed by opening the menu.
    local m_novelMarker = NovelContentMarker("onAbility")

    --Field test 10: red surge + "DMG" for the standout damage ability in the
    --director overview (never on hero chips - only the overview sets it).
    --Presses bubble through to the chip, so clicking the badge still casts.
    local m_dmgBadge = gui.Panel {
        classes = { "overviewDmgBadge", "collapsed" },
        floating = true,
        bgimage = "panels/square.png",
        halign = "right",
        valign = "center",
        rmargin = 4,
        flow = "vertical",
        hover = gui.Tooltip{ text = "This ability does high damage", valign = "top" },
        --Field test 11: symbol only - the "DMG" word crowded the keywords.
        gui.Panel {
            classes = { "overviewDmgIcon" },
            bgimage = "game-icons/surge.png",
            interactable = false,
        },
    }

    resultPanel = gui.Panel {
        classes = { "abilityHeading" },

        --Re-point a pooled chip at a different owner. Fire this BEFORE the
        --"ability" event, since "ability" computes suppression/cost from the
        --caster. Pass nil to restore the g_token default.
        --overviewPress (slice (e)) is the column's preview-on-click hook,
        --function(ability, casterToken, commit) -> handled; nil (every
        --ordinary menu) leaves the press path exactly as it was.
        setCasterToken = function(element, casterToken, overviewPress)
            args.casterToken = casterToken
            args.overviewPress = overviewPress
        end,

        setDamageBadge = function(element, flag)
            m_dmgBadge:SetClass("collapsed", flag ~= true)
        end,

        ability = function(element, ability)
            local suppressMessage = ability:try_get("suppressExplanation") or
                ability:AbilityFilterFailureMessage(CasterToken().properties)
            m_suppressed = suppressMessage ~= nil
            element:SetClassTree("suppressed", m_suppressed)

            m_novelMarker:FireEvent("setNovel", AbilityIsNovel(ability))
        end,

        --Fired when the menu closes and the acknowledged set is dropped.
        refreshNovelAbilities = function(element)
            m_novelMarker:FireEvent("setNovel", m_ability ~= nil and AbilityIsNovel(m_ability))
        end,

        rightClick = function(element)
            local entries = {}
            entries[#entries + 1] = {
                text = 'Share to Chat',
                click = function()
                    element.popup = nil
                    chat.ShareObjectInfo(nil, nil, { charid = CasterToken().charid, ability = m_ability })
                end,
            }

            if m_ability:has_key("sourceReference") then
                if m_ability.sourceReference:url() ~= nil then
                    entries[#entries + 1] = {
                        text = 'View Source',
                        click = function()
                            element.popup = nil
                            dmhub.OpenDocument(m_ability.sourceReference:url())
                        end,
                    }
                end
            end

            if dmhub.isDM then
                local addedEditEntry = false
                for domain, _ in pairs(m_ability.domains or {}) do
                    if addedEditEntry then
                        break
                    end
                    if domain ~= "_luaTable" then
                        --parse domain information
                        local tableType, guid = string.match(domain, "^([^:]+):(.+)$")
                        if tableType and guid then
                            -- Find the parent object (class/feat/etc) that contains this ability
                            local obj, tableid = FindAbilityParentByGuid(guid)
                            if obj and tableid then
                                local path = {}
                                --Find the path to the ability within the parent object
                                local found = FindObjectPathByGuid(m_ability.guid, obj, path)
                                --if a path is found create an edit option
                                if found then
                                    entries[#entries + 1] = {
                                        text = 'Edit Ability',
                                        click = function()
                                            element.popup = nil

                                            -- Get the original ability from the parent object
                                            local originalAbility = GetObjectAtPath(obj, path)

                                            element.root:AddChild(originalAbility:ShowEditActivatedAbilityDialog{
                                                close = function()
                                                    --Use found path to save edited ability back to parent object
                                                    SetObjectAtPath(obj, path, originalAbility)

                                                    -- Upload the parent object
                                                    dmhub.SetAndUploadTableItem(tableid, obj)
                                                end
                                            })
                                        end,
                                    }
                                    addedEditEntry = true
                                end
                            end
                        end
                    end
                end

                local casterToken = CasterToken()
                if not addedEditEntry and casterToken ~= nil and casterToken.properties ~= nil then
                    local innateAbility = casterToken.properties:IsActivatedAbilityInnate(m_ability)
                    if innateAbility then
                        entries[#entries + 1] = {
                            text = 'Edit Ability',
                            click = function()
                                element.popup = nil

                                element.root:AddChild(innateAbility:ShowEditActivatedAbilityDialog{
                                    close = function()
                                        --resolved at close time, as the original g_token read was.
                                        local tok = CasterToken()
                                        tok:ModifyProperties{
                                            description = "Edit Innate Ability",
                                            execute = function()
                                                tok.properties.innateActivatedAbilities = tok.properties.innateActivatedAbilities
                                            end,
                                        }
                                    end,
                                })
                            end,
                        }
                    end
                end
            end

            element.popup = gui.ContextMenu {
                entries = entries,
            }
        end,

        hover = function(element)
            if dmhub.modKeys['ctrl'] then
                --do not show ability if ctrl is held.
                return
            end
            local menu = element:FindParentWithClass("actionMenu")
            if menu ~= nil then
                print("MENU:: SHOW ABILITY")
                menu:FireEvent("showability", m_ability, CasterToken())
            else
                print("MENU:: DIRECT ABILITY")
                m_showingAbility = CharacterPanel.DisplayAbility(CasterToken(), m_ability)
            end
        end,

        dehover = function(element)
            if m_showingAbility then
                print("MENU:: DEHOVER")
                CharacterPanel.HideAbility(m_ability)
            end
        end,

        press = function(element)
            -- Strict resource enforcement: if a player tries to use an ability
            -- whose icon is greyed out (insufficient resources, action already
            -- expended this round, or the ability filter suppresses it), the
            -- click is silently ignored. Directors bypass this so they can
            -- still demo or override the rules.
            if (not dmhub.isDM) and dmhub.GetSettingValue("strict:resources") then
                if m_cannotAfford or m_expended or m_suppressed then
                    return
                end
            end

            audio.FireSoundEvent("Mouse.Click")
            --this will be adopted by the ability controller
            if g_abilityController == nil then return end
            local menu = element:FindParentWithClass("actionMenu")
            if menu ~= nil then
                print("MENU:: ONCAST")
                menu:FireEvent("oncast")
            elseif m_showingAbility then
                print("MENU:: CALL DEHOVER")
                element:FireEvent("dehover")
            end

            if m_ability == nil then
                print("MENU:: NO ABILITY")
                return
            end

            if args.instantCast then
                m_ability = m_ability:MakeTemporaryClone()
                m_ability.castImmediately = true
            end

            --Casting on behalf of a token that is not the bar's bound token
            --(director multi-monster overview). Mirrors the invokeAbility path
            --(see "invokeAbility" on the ability controller): PushCasterToken
            --rebinds g_token/g_creature and pushes the engine's selected-token
            --override, then a refresh rebinds g_abilities/resources to the
            --caster. The matching pop is NOT done here: every cast ends through
            --cancelCasting (finishCasting, Skip, Esc, menu open, disable,
            --restoreFromBackup all funnel there), and cancelCasting calls
            --TryPopCasterToken exactly once. If a cast is already in flight we
            --cancel it first so its own pushed caster (if any) is popped before
            --ours goes on; otherwise the stack would end one deeper than the
            --number of casts and the bar would stay bound to a stale token
            --(refresh only re-reads the selection while the stack is empty).
            --The commit tail of the press: (optionally) rebind the bar to
            --the caster, then hand the ability to the controller. Split out
            --so the overview's preview-on-click hook can defer it until the
            --Director has picked WHICH member acts (slice (e)); an ordinary
            --menu (no hook) runs it immediately with the chip's own caster and
            --ability, exactly as before.
            local function commit(casterToken, ability)
                ability = ability or m_ability
                if casterToken ~= nil and (g_token == nil or casterToken.charid ~= g_token.charid) then
                    if g_currentAbility ~= nil then
                        g_abilityController:FireEvent("cancelCasting")
                    end
                    PushCasterToken(casterToken)
                    if g_actionBar ~= nil then
                        g_actionBar:FireEvent("refresh")
                    end
                end

                --Overview chip: remember who this cast is for so the pre-Cast
                --hook can claim their turn at target confirm (only if legal
                --then). Set AFTER any in-flight cancel above (which clears
                --it) and before beginCasting. Ordinary chips never set it.
                if args.overviewPress ~= nil and casterToken ~= nil and casterToken.valid then
                    local initiativeid = nil
                    pcall(function() initiativeid = InitiativeQueue.GetInitiativeId(casterToken) end)
                    g_overviewCastPending = { token = casterToken, initiativeid = initiativeid }
                else
                    g_overviewCastPending = nil
                end

                if menu == nil then
                    print("MENU:: DISPLAY ABILITY NEW")
                    CharacterPanel.DisplayAbility(casterToken, ability, { targets = args.targets, cast = args.cast })
                    m_showingAbility = false
                end

                    print("MENU:: HIGHLIGHT")
                -- Collect applicable ability improvements from the caster.
                m_activeImprovements = {}
                if casterToken ~= nil then
                    for _, activeMod in ipairs(casterToken.properties:GetActiveModifiers()) do
                        if activeMod.mod.behavior == "abilityimprovement" then
                            local improvMod = activeMod.mod
                            local passes = true

                            -- Keyword filter: if any keywords set, ability must have at least one match.
                            local keywords = improvMod:try_get("keywords", {})
                            local hasKeywords = false
                            for _ in pairs(keywords) do hasKeywords = true; break end
                            if hasKeywords then
                                local abilityMatch = false
                                for keyword, _ in pairs(keywords) do
                                    if ability.keywords ~= nil and ability.keywords[keyword] then
                                        abilityMatch = true
                                        break
                                    end
                                end
                                if not abilityMatch then passes = false end
                            end

                            -- Ability condition filter.
                            if passes then
                                local abilityFilter = improvMod:try_get("abilityFilter", "")
                                if abilityFilter ~= "" then
                                    local symbols = casterToken.properties:LookupSymbol{ability = ability}
                                    passes = GoblinScriptTrue(ExecuteGoblinScript(abilityFilter, symbols, 1, "Ability improvement filter"))
                                end
                            end

                            if passes then
                                m_activeImprovements[#m_activeImprovements + 1] = {
                                    mod = improvMod,
                                    checked = false,
                                }
                            end
                        end
                    end
                end
                CharacterPanel.HighlightAbilitySection{
                    ability = ability,
                    caster = casterToken,
                    section = "target",
                    improvements = m_activeImprovements,
                }

                g_abilityController:FireEventTree("beginCasting", ability, { targets = args.targets, cast = args.cast, symbols = args.symbols, fromui = true })
            end

            local casterToken = CasterToken()
            if args.overviewPress ~= nil and args.casterToken ~= nil then
                if args.overviewPress(m_ability, casterToken, commit) then
                    return
                end
            end
            commit(casterToken)
        end,

        gui.Label {
            classes = { "abilityIconPanel" },
            ability = function(element, ability)
                m_ability = ability
                --Stamped so the search reveal can find this heading by name.
                resultPanel.data.abilityName = ability.name

                if ability:try_get("manualVersionOfTrigger") or ability.categorization == "Trigger" then
                    element.text = "!"
                    element.bgimage = "panels/square.png"
                    element.selfStyle.gradient = cond(ability.actionResourceId == CharacterResource.triggerResourceId,
                        mod.shared.triggerGradient, mod.shared.freeTriggerGradient)
                    element.selfStyle.gradientMapping = false
                    element.selfStyle.bgcolor = "white"
                    element.selfStyle.hueshift = 0
                    element.selfStyle.saturation = 1
                    element.selfStyle.brightness = 1
                else
                    element.text = ""
                    element.bgimage = ability:GetIcon()
                    element.selfStyle = ability:GetIconDisplay()
                    element.selfStyle.gradient = ability:GetIconGradient()
                    element.selfStyle.gradientMapping = true
                end
            end,
        },

        gui.Panel {
            classes = { "costDiamond", "collapsed" },
            floating = true,
            rotate = 135,
            gui.Panel {
                --vback
                classes = { "costInnerDiamond" },
                gui.Label {
                    classes = { "abilityCostLabel" },
                    rotate = -135,


                    ability = function(element, ability)
                        local resource = ability:ActionResource()
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element.parent.parent:SetClass("collapsed", true)
                            SetCannotAfford(false, false)
                            return
                        end

                        element.parent.parent:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                    end,
                },
            },
        },


        gui.Panel {
            classes = { "abilityInfoPanel" },

            gui.Label {
                classes = { "abilityTitle" },
                text = "Ability Name",
                ability = function(element, ability)
                    local text = ability.name
                    --rely on keywords to show melee/ranged.
                    --if ability:try_get("isMeleeVariation") then
                    --    text = text .. " <size=8>(Melee)"
                    --elseif ability:try_get("isRangedVariation") then
                    --    text = text .. " <size=8>(Ranged)"
                    --end
                    element.text = text
                end,
            },


            --[[
            gui.Panel {
                classes = { "abilityTitleArea" },

                gui.Label {
                    classes = { "abilityCostLabel" },
                    text = "",

                    ability = function(element, ability)
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element:SetClass("collapsed", true)
                            SetCannotAfford(false)
                            return
                        end

                        element:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                    end,

                },
            },
--]]
            gui.Label {
                classes = { "abilityInfoLabel" },
                text = "Ability Info",
                ability = function(element, ability)
                    local costInfo = ability:GetCost(CasterToken())

                    --look for heroic resource or malice cost and see if we can afford it.
                    local cannotAfford = false
                    for _, entry in ipairs(costInfo.details or {}) do
                        if entry.cost == CharacterResource.heroicResourceId or entry.cost == CharacterResource.maliceResourceId then
                            cannotAfford = not entry.canAfford
                            break
                        end
                    end

                    SetCannotAfford(cannotAfford, not costInfo.canAfford)
                    for _, entry in ipairs(costInfo.details) do
                        if entry.description ~= nil and (not entry.canAfford) then
                            --this means there is an 'anonymous' cost, e.g. number of times they can use per round.
                            if entry.refreshType == "long" then
                                element.text = "Already used since respite"
                            else
                                element.text = string.format("Already used this %s", entry.refreshType)
                            end
                            return
                        end
                    end

                    if ability.categorization == "Villain Action" then
                        element.text = ability:try_get("villainAction")
                        return
                    end

                    local keywords = {}
                    for k,_ in pairs(ability.keywords) do
                        keywords[#keywords+1] = ActivatedAbility.CanonicalKeyword(k)
                    end
                    table.sort(keywords)
                    element.text = string.join(keywords, ", ")
                end,
            },

            --Decision 45 (overview only): the conditions this ability can
            --apply, as the token-UI glyphs, up to two then "+N"; always on,
            --not lens-gated, so the Control lens is discoverable from the
            --chips. Inline under the keywords (the chip's right corner is
            --already the cost diamond's and the novelty pip's).
            gui.Panel {
                classes = { "overviewConditionRow", "collapsed" },
                gui.Panel { classes = { "overviewConditionIcon", "collapsed" }, bgimage = "panels/square.png" },
                gui.Panel { classes = { "overviewConditionIcon", "collapsed" }, bgimage = "panels/square.png" },
                gui.Label { classes = { "overviewConditionMore", "collapsed" }, text = "" },
                ability = function(element, ability)
                    local icons = {}
                    if args.overviewPress ~= nil then
                        icons = OverviewConditionIcons(OverviewAbilityFacets(ability))
                    end
                    local children = element.children
                    local names = {}
                    for _, icon in ipairs(icons) do
                        names[#names + 1] = icon.name
                    end
                    for i = 1, OVERVIEW.CHIP_CONDITION_ICONS do
                        local panel = children[i]
                        local icon = icons[i]
                        if icon == nil then
                            panel:SetClass("collapsed", true)
                        else
                            panel:SetClass("collapsed", false)
                            panel.bgimage = icon.icon
                            panel.selfStyle.bgcolor = icon.bgcolor
                        end
                    end
                    local more = children[OVERVIEW.CHIP_CONDITION_ICONS + 1]
                    if #icons > OVERVIEW.CHIP_CONDITION_ICONS then
                        more.text = string.format("+%d", #icons - OVERVIEW.CHIP_CONDITION_ICONS)
                        more:SetClass("collapsed", false)
                    else
                        more:SetClass("collapsed", true)
                    end
                    element.data.tooltip = table.concat(names, ", ")
                    element:SetClass("collapsed", #icons == 0)
                end,
                data = { tooltip = "" },
                hover = function(element)
                    if element.data.tooltip ~= "" then
                        gui.Tooltip("Can apply: " .. element.data.tooltip)(element)
                    end
                end,
            },

            --Director overview only (args.overviewPress set): the action
            --economy in legible text - "Maneuver" / "Free Maneuver" / "Free
            --Action"; main actions stay unmarked. Ordinary menus never show
            --it (the drawer already says which action the menu is).
            gui.Label {
                classes = { "overviewActionType", "collapsed" },
                text = "",
                ability = function(element, ability)
                    local text = ""
                    if args.overviewPress ~= nil then
                        local _, label = OverviewActionType(ability)
                        text = label or ""
                    end
                    element.text = text
                    element:SetClass("maneuver", text == "Maneuver" or text == "Free Maneuver")
                    element:SetClass("freeaction", text == "Free Action")
                    element:SetClass("collapsed", text == "")
                end,
            },

            --P2-c2 / X14: under an active lens, the lens's sort key on a
            --matching overview chip ("6 damage per target", "Push 3").
            gui.Label {
                classes = { "overviewLensKey", "collapsed" },
                text = "",
                ability = function(element, ability)
                    local text = nil
                    if args.overviewPress ~= nil and g_overviewLens ~= "all" then
                        text = OverviewLensKeyText(OverviewAbilityFacets(ability), g_overviewLens)
                    end
                    element.text = text or ""
                    element:SetClass("collapsed", text == nil)
                end,
            },
        },

        m_novelMarker,
        m_dmgBadge,
    }

    if args.ability ~= nil then
        resultPanel:FireEventTree("ability", args.ability)
    end

    return resultPanel
end

local function TriggerPreviewPanel()
    local m_trigger = nil
    local resultPanel

    resultPanel = gui.Panel{
        classes = {"abilityHeading", "nonselectable"},
        hover = function(element)
            if m_trigger ~= nil then
                CharacterPanel.DisplayAbility(g_token, m_trigger, {})
            end
        end,
        dehover = function(element)
            if m_trigger ~= nil then
                CharacterPanel.HideAbility(m_trigger)
            end
        end,

        rightClick = function(element)
            local entries = {}
            entries[#entries + 1] = {
                text = 'Share to Chat',
                click = function()
                    element.popup = nil
                    chat.ShareObjectInfo(nil, nil, { charid = g_token.charid, ability = m_trigger })
                end,
            }

            element.popup = gui.ContextMenu {
                entries = entries,
            }
        end,

        gui.Label{
            classes = {"abilityIconPanel"},
            trigger = function(element, trigger)
                m_trigger = trigger
                local isPassive = trigger.type == "passive"
                local isFree = trigger.type == "free"
                element.selfStyle.gradient = cond(isPassive, mod.shared.passiveTriggerGradient,
                    cond(isFree, mod.shared.freeTriggerGradient, mod.shared.triggerGradient))
            end,

            text = "!",
            bgimage = "panels/square.png",
            bgcolor = "white",
            hueshift = 0,
            saturation = 1,
            brightness = 1,
        },
        gui.Panel{
            classes = {"abilityInfoPanel"},
            gui.Label{
                classes = {"abilityTitle", "expended"},
                hmargin = 6,
                vmargin = 0,
                tmargin = 0,
                trigger = function(element, trigger)
                    element.text = trigger.name
                end,
            },
            gui.Label{
                classes = {"abilityInfoLabel", "expended"},
                hmargin = 6,
                vmargin = 0,
                tmargin = 0,
                trigger = function(element, trigger)
                    if trigger.type == "passive" then
                        element.text = "Passive"
                    elseif trigger.type == "free" then
                        element.text = "Free Triggered Action"
                    else
                        element.text = "Triggered Action"
                    end
                end,
            },
        }
    }

    return resultPanel
end

local function PowerRollTriggersSubmenu(args)
    local m_children = {
        gui.Label {
            classes = { "submenuHeading" },
            text = "All Triggers",
        }
    }

    local resultPanel

    resultPanel = gui.Panel {
        vpad = -4,

        classes = { "abilitySubMenu" },
        floating = true,
        halign = "right",
        hmargin = -200,
        blurBackground = true,
        triggers = function(element, triggers)
            if #triggers == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            local heading = m_children[#m_children]
            m_children[#m_children] = nil

            table.sort(triggers, function(a, b)
                return (a.type .. a.name) < (b.type .. b.name)
            end)

            for i,trigger in ipairs(triggers) do
                m_children[i] = m_children[i] or TriggerPreviewPanel()
                m_children[i]:FireEventTree("trigger", trigger)
                m_children[i]:SetClass("collapsed", false)
            end

            for i = #triggers + 1, #m_children do
                m_children[i]:SetClass("collapsed", true)
            end

            m_children[#m_children+1] = heading
            element.children = m_children
        end,

        children = m_children,
    }

    return resultPanel
end

--Director multi-monster overview: the column FOOTER BAR (slice (d)).
--
--An overview column (see BuildOverviewColumns / the "unique" menu branch)
--replaces the ordinary "submenuHeading" text label at the foot of the column
--with a bar in the same visual position and palette (solid #1D1D1D, gold
--text) that carries the statblock's identity and per-round SIGNALS - never
--a verdict (Decision 48): the representative token's real portrait, the
--statblock name (+ " xN"), the stat-block role line ("Level 1 Horde
--Harrier", from monster.cr/.role exactly as the stat block header prints it;
--nothing is fabricated when that data is missing), the RAW STAMINA
--("13/15", F2-5 - the earlier Low/Moderate/High band was relative to the
--creature's own max and said nothing useful) and the ACTED state from the
--live initiative queue (InitiativeQueue:HasHadTurn): silent while not yet
--acted, red "Turn already taken" once acted, "Acting now" mid-turn. Everything is text;
--colour is never the only channel (Decision 51/X12); text >= 12px (X11 read
--floor; F2-4 raised it from 11 - too small on a laptop).
--
--When a column has more than one member (Goblin Warrior x2), the footer grows
--one compact MINI-ROW per member - per SQUAD for minions, since a squad is one
--actor sharing one initiative slot and one stamina pool - each with a tiny
--portrait and TWO lines: the member's name (ellipsized, F2-4 - one line
--overflowed the column) and "13/15" (+ the acted state) (X7). At most three rows
--are shown, then "+N more".
--
--Clicking the bar LOCATES the column: dmhub.CenterOnToken on the
--representative and dmhub.PulseHighlightToken on every member; clicking a
--mini-row locates that member. NEVER dmhub.FocusToken (it selects, which
--collapses the overview scope - Decision 51/X5); dmhub.selectedTokens is not
--touched.
--
--When EVERY member of a column has acted this round the whole column is
--dimmed (class "acted" on the abilitySubMenu -> chips at 0.5 opacity, still
--clickable/discoverable per Decision 4); nothing else dims a column.
--
--Pooled-panel rule (Field test log): the footer and its mini-rows are created
--ONCE per ActionSubMenu and updated through the "overviewColumn" event; no
--children list is ever reassigned after construction.
--
--Styling lives in OVERVIEW_FOOTER_RULES (next to NOVEL_MARKER_RULES, merged
--into the action bar root's cascade).

--Raw stamina for a token as "13/15" (+ " +T" temporary stamina when any);
--nil when the creature has no usable stamina numbers. F2-5: the earlier
--qualitative band (Low/Moderate/High, relative to the creature's OWN max)
--told the Director nothing about survivability - a 15-max Warrior and an
--80-max Monarch both read "High" - and in practice nearly every column read
--"High". The raw numbers are cheap and unambiguous (Decision 9's "show raw
--numbers"); the survivability question itself is the Phase 2 threat
--estimate. For a minion, CurrentHitpoints/MaxHitpoints already report the
--SQUAD pool (MCDMCreature.lua ~:172/:4710), so this is the squad's pool.
local function OverviewStaminaText(tok)
    local cur, max, temp = nil, nil, nil
    pcall(function()
        cur = tok.properties:CurrentHitpoints()
        max = tok.properties:MaxHitpoints()
    end)
    pcall(function()
        temp = tok.properties:TemporaryHitpoints()
    end)
    if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then
        return nil
    end
    local text = string.format("%d/%d", round(cur), round(max))
    if type(temp) == "number" and temp > 0 then
        text = string.format("%s +%d", text, round(temp))
    end
    return text
end

--P2-a: the status entries a token's HUD shows (conditions, ongoing effects,
--registered status icons) via TokenUI.CalculateStatusIcons, each reduced to
--{id, icon, style, name, hoverText, threat, casterName}. THREAT = the
--effect's caster is NOT a director-run monster, i.e. a hero put it there
--(a Tactician's Mark, a Censor's judgment): deterministic and it says who
--the heroes intend to kill (2026-08-18 play observation) - the footer
--draws those with a red ring and mirrors them in red text. Self-applied
--monster buffs and plain conditions stay neutral.

local function OverviewStatusName(icon)
    if icon.statusText ~= nil and icon.statusText ~= "" then
        return icon.statusText
    end
    local text = icon.hoverText or icon.id or "Status"
    --"Name: description" / "Name (2): description" -> Name
    text = string.gsub(text, "<[^>]*>", "")
    local name = string.match(text, "^([^:\n]+)") or text
    name = string.gsub(name, "%s*%(%d+%)%s*$", "")
    return trim(name)
end

--Returns entries, captain: the squad-captain crown (status id "captain") is
--split out - it is IDENTITY, not a transient status, and the footer shows it
--beside the name (field test 7), never in the status strip.
local function OverviewStatusEntries(tok)
    local entries = {}
    local captain = nil
    if tok == nil or not tok.valid or tok.properties == nil then
        return entries, captain
    end
    local icons = nil
    pcall(function() icons = TokenUI.CalculateStatusIcons(tok) end)
    for _, icon in ipairs(icons or {}) do
        --Skip the director-only eye and the walk-elevation glyph (an altitude
        --readout, not a status; it is hidden at altitude 0 on the HUD).
        if icon ~= nil and icon.id == "captain" then
            captain = icon
        elseif icon ~= nil and icon.icon ~= nil and icon.id ~= "invisible" and not icon.hideAtZeroAltitude then
            local threat = false
            local casterName = nil
            if icon.casterid ~= nil then
                local caster = dmhub.GetTokenById(icon.casterid)
                if caster ~= nil and caster.valid then
                    threat = not IsOverviewCreatureToken(caster)
                    pcall(function()
                        if caster.canLocalPlayerSeeName then
                            casterName = caster.name
                        end
                    end)
                    casterName = casterName or "a hero"
                end
            end
            entries[#entries + 1] = {
                id = icon.id,
                icon = icon.icon,
                style = icon.style,
                name = OverviewStatusName(icon),
                hoverText = icon.hoverText,
                threat = threat,
                casterName = casterName,
                ord = #entries + 1,
            }
        end
    end
    --Threat flags first (stable otherwise), so the strip's "+N" never hides
    --one.
    table.sort(entries, function(a, b)
        if a.threat ~= b.threat then
            return a.threat
        end
        return a.ord < b.ord
    end)
    return entries, captain
end

--Red "Marked by Talent" (+N) mirror of a member's threat flags; nil if none.
--prefixLength = the characters already on the line ("14/15 - "); the caster
--is named only while the whole line still fits the 151px footer text column
--(~26 chars at 12px) - the icon's hover text always names it.
local function OverviewThreatText(entries, prefixLength)
    local threats = {}
    for _, entry in ipairs(entries or {}) do
        if entry.threat then
            threats[#threats + 1] = entry
        end
    end
    if #threats == 0 then
        return nil
    end
    local first = threats[1]
    local text = first.name
    if first.casterName ~= nil then
        local long = string.format("%s by %s", text, first.casterName)
        if (prefixLength or 0) + #long <= 26 then
            text = long
        end
    end
    if #threats > 1 then
        text = string.format("%s +%d", text, #threats - 1)
    end
    return string.format("<color=%s>%s</color>", OVERVIEW.THREAT_COLOR, text)
end

--P2-d (X7 / Decision 48 signal): REACH ESTIMATE - how many heroes this
--member could get at this turn: speed + the longest range among its kit
--abilities that target enemies (melee counts 1), measured in straight-line
--squares (Chebyshev, as Draw Steel counts) from the token; walls, terrain
--and difficult ground are ignored, so it is an ESTIMATE and says so. Heroes
--= live tokens on the map that are not director-run monsters.
local function OverviewHeroTokens()
    local heroes = {}
    for _, tok in ipairs(dmhub.GetTokens() or {}) do
        if tok ~= nil and tok.valid and tok.properties ~= nil and not tok.isObject and not IsOverviewCreatureToken(tok) then
            local down = false
            pcall(function() down = tok.properties:IsDown() end)
            if not down then
                heroes[#heroes + 1] = tok
            end
        end
    end
    return heroes
end

local function OverviewKitRange(tok, abilities)
    local best = 1
    for _, ability in ipairs(abilities or {}) do
        pcall(function()
            local tt = ability.targetType
            if tt ~= "self" and tt ~= "emptyspace" and tt ~= "anyspace" and tt ~= "map" then
                local r = tonumber(ability:GetRange(tok.properties))
                if r ~= nil and r > best then
                    best = r
                end
            end
        end)
    end
    return best
end

local function OverviewReach(tok, abilities, heroes)
    if tok == nil or not tok.valid or tok.properties == nil then
        return nil
    end
    local speed = 0
    pcall(function() speed = tonumber(tok.properties:GetSpeed()) or 0 end)
    local range = OverviewKitRange(tok, abilities)
    local reach = speed + range
    local count = 0
    local ok = pcall(function()
        local locs = tok.locsOccupying
        if locs == nil or #locs == 0 then
            locs = { tok.loc }
        end
        for _, hero in ipairs(heroes or {}) do
            local hloc = hero.loc
            local nearest = nil
            for _, loc in ipairs(locs) do
                local d = math.max(math.abs(loc.x - hloc.x), math.abs(loc.y - hloc.y))
                if nearest == nil or d < nearest then
                    nearest = d
                end
            end
            if nearest ~= nil and nearest <= reach then
                count = count + 1
            end
        end
    end)
    if not ok then
        return nil
    end
    return { count = count, reach = reach, speed = speed, range = range }
end

--"3 heroes in reach" / "1 hero in reach" / "No hero in reach"; short = "3 in
--reach" for the mini-rows.
--Zero reads AMBER + bold (field test 4: white "0 in reach" did not steer -
--zero is the "rule this monster out this turn" cue and must pop the way
--"Turn already taken" does in red).
local function OverviewReachText(reach, short)
    if reach == nil then
        return nil
    end
    --Field test 11 (Ricky's own silent-default rule, applied back at him):
    --being able to reach heroes is the NORMAL state and says nothing worth
    --reading on every chip - only the exception prints. Zero reach = amber
    --"Can't reach any hero" = rule this monster out this turn. This also
    --kills the near-duplicate reading with the risk box's "N heroes within
    --striking range" (that line is the heroes' threat TO the monster and
    --stays, as the WHY under the risk tag).
    if reach.count > 0 then
        return nil
    end
    if short then
        return string.format("<color=%s><b>can reach no hero</b></color>", OVERVIEW.NOREACH_COLOR)
    end
    return string.format("<color=%s><b>Can't reach any hero</b></color>", OVERVIEW.NOREACH_COLOR)
end

--P2-e THREAT ESTIMATE (F2-5c, signed off by Ricky 2026-08-19): "if the
--heroes strike this monster, could it die before it acts?" A risk band with
--REASONS, never a verdict - always "could", crits are luck (Decision 48).
--Silent when safe (never label the default state).
--
--Model, per monster member:
--  * heroes who can STRIKE it: hero speed + the hero's longest damaging
--    range >= straight-line distance (same Chebyshev estimate as P2-d,
--    walls/terrain ignored);
--  * each hero's BURST = best tier-2 damage across their abilities (same
--    parser as the lenses) + a flat RIDER allowance for a triggered action /
--    mark benefit (the Cursespitter died to crit + Mark trigger + a second
--    ability - one hit is never the yardstick);
--  * a hero who has ALREADY ACTED counts at HALF weight, not zero (Ricky:
--    Strike Now can invoke a spent hero, so the risk is lower, not gone);
--  * a monster MARKED/JUDGED by a hero is a declared kill target: red
--    whenever anyone can reach it.
--Bands: RED "High target risk" = marked with a hero in reach, or stamina <=
--best single adjusted burst + rider; AMBER "At risk" = stamina <= the two
--best adjusted bursts + rider, or marked with nobody in reach.
--One local for the whole P2-e feature (the file is near Lua's 200
--top-level-locals limit): constants + the hero-profile cache.
local g_overviewRisk = {
    allowance = 4,
    red = "#E06464",
    amber = "#E0A050",
    cache = { time = -1, list = {} },
}

--Hero combat profiles (speed, longest damaging range, best tier-2 burst,
--acted), cached briefly: several columns x members all ask within one
--populate pass, and hero kits do not change mid-frame.
local function OverviewHeroProfiles()
    local now = dmhub.Time()
    if g_overviewRisk.cache.time == now then
        return g_overviewRisk.cache.list
    end
    local q = dmhub.initiativeQueue
    if q ~= nil and q.hidden then
        q = nil
    end
    local list = {}
    for _, hero in ipairs(OverviewHeroTokens()) do
        local profile = { token = hero, speed = 0, range = 1, burst = 0, spent = false }
        pcall(function() profile.speed = tonumber(hero.properties:GetSpeed()) or 0 end)
        pcall(function()
            local abilities = hero.properties:GetActivatedAbilities { bindCaster = true } or {}
            for _, ability in ipairs(abilities) do
                local variations = { ability }
                if ability.meleeAndRanged then
                    variations = { ability.meleeVariation, ability.rangedVariation }
                end
                for _, variation in ipairs(variations) do
                    local facets = OverviewAbilityFacets(variation)
                    if facets.damageValue > profile.burst then
                        profile.burst = facets.damageValue
                    end
                    if facets.damage then
                        local tt = variation.targetType
                        if tt ~= "self" and tt ~= "emptyspace" and tt ~= "anyspace" and tt ~= "map" then
                            local r = tonumber(variation:GetRange(hero.properties))
                            if r ~= nil and r > profile.range then
                                profile.range = r
                            end
                        end
                    end
                end
            end
        end)
        if q ~= nil then
            pcall(function() profile.spent = q:HasHadTurn(InitiativeQueue.GetInitiativeId(hero)) == true end)
        end
        list[#list + 1] = profile
    end
    g_overviewRisk.cache = { time = now, list = list }
    return list
end

--Field test 6 (reverses F2-5b raw-numbers-only): LOW STAMINA = a typical
--(tier-2) hit from the hardest-hitting hero on the map would drop it -
--roughly "2 rolls in 3 kill it", close to Ricky's 65% intuition but tied to
--the tier system instead of a probability model. Hypothetical ANY hero, not
--just those in reach ("if a hero were to target them"). The raw number
--stays in parentheses.
local function OverviewLowStamina(tok, inCombat)
    if not inCombat or tok == nil or not tok.valid or tok.properties == nil then
        return false
    end
    local cur = nil
    pcall(function() cur = tonumber(tok.properties:CurrentHitpoints()) end)
    if cur == nil or cur <= 0 then
        return false
    end
    local best = 0
    for _, profile in ipairs(OverviewHeroProfiles()) do
        if profile.burst > best then
            best = profile.burst
        end
    end
    return best > 0 and cur <= best
end

--nil when safe (or no queue/stamina data), else {level, text, tooltip}.
--marked = the member carries a hero-applied threat flag (P2-a statuses).
--lowStamina feeds a bullet (computed by the caller so the label and the
--risk box agree).
local function OverviewThreatEstimate(tok, threats, inCombat, lowStamina, turnSpent)
    local marked = threats ~= nil and #threats > 0
    if not inCombat or tok == nil or not tok.valid or tok.properties == nil then
        return nil
    end
    local cur = nil
    pcall(function() cur = tonumber(tok.properties:CurrentHitpoints()) end)
    if cur == nil or cur <= 0 then
        return nil
    end

    local locs = nil
    pcall(function()
        locs = tok.locsOccupying
        if locs == nil or #locs == 0 then
            locs = { tok.loc }
        end
    end)
    if locs == nil then
        return nil
    end

    local inReach = {}
    local spentCount = 0
    for _, profile in ipairs(OverviewHeroProfiles()) do
        local hloc = nil
        pcall(function() hloc = profile.token.loc end)
        if hloc ~= nil then
            local nearest = nil
            for _, loc in ipairs(locs) do
                local d = math.max(math.abs(loc.x - hloc.x), math.abs(loc.y - hloc.y))
                if nearest == nil or d < nearest then
                    nearest = d
                end
            end
            if nearest ~= nil and nearest <= profile.speed + profile.range then
                local adjusted = profile.burst
                if profile.spent then
                    adjusted = adjusted * 0.5
                    spentCount = spentCount + 1
                end
                inReach[#inReach + 1] = { profile = profile, adjusted = adjusted }
            end
        end
    end
    table.sort(inReach, function(a, b) return a.adjusted > b.adjusted end)

    local best1 = inReach[1] ~= nil and inReach[1].adjusted or 0
    local best2 = inReach[2] ~= nil and inReach[2].adjusted or 0

    --Field test 7: RED is a stamina-vs-damage VERDICT, never granted by a
    --mark alone - a marked 80-stamina Monarch is urgent, not dying. A mark
    --raises the damage allowance instead (mark benefits are extra damage)
    --and guarantees at least amber while anyone can reach the monster.
    --Low stamina alone guarantees at least amber, so the fact never
    --disappears when nobody is currently in reach.
    local allowance = g_overviewRisk.allowance
    if marked then
        allowance = allowance * 2
    end
    local level = nil
    if best1 > 0 and cur <= best1 + allowance then
        level = "red"
    elseif (best2 > 0 and cur <= best1 + best2 + allowance)
        or (marked and #inReach > 0)
        or lowStamina then
        level = "amber"
    end
    if level == nil then
        return nil
    end

    --Field test 6 layout: headline tag, then WHY as bullets, then a green
    --guidance line (red only - amber is advisory, not a call to action).
    local bullets = {}
    --Field test 9: name the ACTUAL effects ("Dazed by Human Censor"), never
    --the generic "Marked by heroes" - Marked is a specific mechanic and the
    --Monarch was Dazed, not Marked.
    if marked then
        local seen = {}
        local shown = 0
        for _, entry in ipairs(threats) do
            local text = entry.name or "Marked"
            if entry.casterName ~= nil then
                text = string.format("%s by %s", text, entry.casterName)
            else
                text = text .. " by a hero"
            end
            if not seen[text] then
                seen[text] = true
                if shown < 2 then
                    bullets[#bullets + 1] = text
                end
                shown = shown + 1
            end
        end
        if shown > 2 then
            bullets[#bullets] = string.format("%s +%d more", bullets[#bullets], shown - 2)
        end
    end
    if lowStamina then
        bullets[#bullets + 1] = "Low Stamina"
    end
    if #inReach > 0 then
        local striking = string.format("%d hero%s within striking range", #inReach, #inReach == 1 and "" or "es")
        if spentCount == #inReach and spentCount > 0 then
            striking = striking .. " (all spent)"
        end
        bullets[#bullets + 1] = striking
    end

    local color = level == "red" and g_overviewRisk.red or g_overviewRisk.amber
    local headline = level == "red" and "High Death Risk" or "At Risk"
    local lines = { string.format("<color=%s><b>%s</b></color>", color, headline) }
    for _, bullet in ipairs(bullets) do
        lines[#lines + 1] = "- " .. bullet
    end
    --Guidance is a call to action; once the turn is spent there is nothing
    --to spend, so the tag+bullets stand alone (still useful: it will likely
    --die, plan around it).
    if level == "red" and not turnSpent then
        lines[#lines + 1] = string.format("<color=%s>Use turn before they die</color>", OVERVIEW.GUIDE_COLOR)
    elseif level == "amber" and not turnSpent then
        --Field test 9 ("what should the user DO with At Risk?"): say it.
        lines[#lines + 1] = string.format("<color=%s>Consider using turn soon</color>", OVERVIEW.GUIDE_COLOR)
    end

    local tooltipParts = {}
    tooltipParts[#tooltipParts + 1] = string.format("%s: %s.", headline, table.concat(bullets, "; "))
    if best1 > 0 then
        tooltipParts[#tooltipParts + 1] = string.format(
            "Hardest reachable hit ~%d damage (+%d for a triggered action%s) vs %d Stamina. Spent heroes count at half weight.",
            math.floor(best1), allowance, marked and " and the mark benefit" or "", math.floor(cur))
    end
    tooltipParts[#tooltipParts + 1] = "Straight-line estimate; crits and choices can beat it either way."
    return {
        level = level,
        text = table.concat(lines, "\n"),
        tooltip = table.concat(tooltipParts, "\n"),
    }
end

--Acted-this-round from the live initiative queue: true / false, or nil when
--there is no (visible) queue or the token has no entry in it.
local function OverviewActedState(q, tok)
    if q == nil then
        return nil
    end
    local acted = nil
    pcall(function() acted = q:HasHadTurn(InitiativeQueue.GetInitiativeId(tok)) end)
    if acted == true or acted == false then
        return acted
    end
    return nil
end

--F2-9 / Decision 15: one-line PLAY PATTERN per monster role and per
--organization, shown on hover of the footer's role line so the Director can
--pick which column to read first. Paraphrased play guidance, not rules text.
--Keys are the lowercase words monster:Role() / monster:Organization() yield.
local OVERVIEW_ROLE_PROSE = {
    ambusher   = "Strikes from hiding, then slips away. Open hidden, pick off an isolated hero.",
    artillery  = "Ranged damage from the back line. Keep line of sight, stay out of melee.",
    brute      = "Tough melee damage. Close in, hit hard, soak what comes back.",
    controller = "Shapes the fight: forced movement, hazards, conditions. Decide where the heroes stand.",
    defender   = "Holds the line. Protects allies and punishes heroes who ignore it.",
    harrier    = "Hit and run. Strike, then reposition; never stay pinned.",
    hexer      = "Curses and debuffs from mid range. Weaken heroes so allies' hits land harder.",
    mount      = "Carries a rider. Strongest when ridden; moves allies where they need to be.",
    skirmisher = "Mobile fighter. Darts in and out of the front line.",
    support    = "Buffs, heals and enables allies. Stay behind the line, near friends.",
    leader     = "Commands the battle with villain actions. The others fight better while it stands.",
    solo       = "Fights alone and acts more than once a round. The encounter IS this creature.",
    minion     = "Weak alone, acts as a squad sharing one stamina pool. Swarm, then expect losses.",
    horde      = "Numerous and cheap. Strength in numbers, each one fragile.",
    platoon    = "The standard monster. A few of them make a fight.",
    elite      = "Tough and dangerous, worth two standard monsters. Expect it to last.",
}

--The stat block's role for the footer: line = the role line with the ROLE
--WORD first and emphasised ("<b>Controller</b>  Level 1 Horde"; a
--Leader/Solo has only the organization, so that word leads), prose = the
--hover play pattern (role + organization lines), plain = the stat block's
--own "Level 1 Horde Controller" text. nil for anything without role data.
--Built from monster.cr / monster.role exactly as the stat block header does
--(MCDMMonster.lua ~:637).
local function OverviewRoleInfo(tok)
    local props = tok.properties
    local role = nil
    local level = nil
    local isMinion = false
    local roleWord = nil
    local orgWord = nil
    pcall(function()
        if props:IsMonster() then
            role = props:try_get("role")
            level = tonumber(props:try_get("cr"))
            isMinion = props.minion == true
            roleWord = props:Role()
            orgWord = props:Organization()
        end
    end)
    if role == nil or role == "" then
        return nil
    end
    local plain = role
    if level ~= nil then
        plain = string.format("Level %d %s", round(level), role)
    end
    if isMinion and string.find(string.lower(role), "minion", 1, true) == nil then
        plain = plain .. " minion"
        orgWord = orgWord or "minion"
    end

    --Field test 8: no level on the chip (the tooltip keeps the full stat
    --block line). Natural order, role word emphasised: "Horde Controller",
    --"Minion Harrier", or just "Leader".
    local line = plain
    if roleWord ~= nil then
        local roleText = string.upper(string.sub(roleWord, 1, 1)) .. string.sub(roleWord, 2)
        line = string.format("<color=#C9A86A><b>%s</b></color>", roleText)
        if orgWord ~= nil then
            line = string.upper(string.sub(orgWord, 1, 1)) .. string.sub(orgWord, 2) .. " " .. line
        end
    elseif orgWord ~= nil then
        line = string.format("<color=#C9A86A><b>%s</b></color>", string.upper(string.sub(orgWord, 1, 1)) .. string.sub(orgWord, 2))
    end

    local prose = {}
    if roleWord ~= nil and OVERVIEW_ROLE_PROSE[roleWord] ~= nil then
        prose[#prose + 1] = string.format("%s: %s", string.upper(string.sub(roleWord, 1, 1)) .. string.sub(roleWord, 2), OVERVIEW_ROLE_PROSE[roleWord])
    end
    if orgWord ~= nil and OVERVIEW_ROLE_PROSE[orgWord] ~= nil then
        prose[#prose + 1] = string.format("%s: %s", string.upper(string.sub(orgWord, 1, 1)) .. string.sub(orgWord, 2), OVERVIEW_ROLE_PROSE[orgWord])
    end

    return {
        plain = plain,
        line = line,
        prose = table.concat(prose, "\n"),
    }
end

--Reduce a column record ({tokens, token, name, label}) to its signals:
--  members   = one entry per actor: { token, name, tokens, stamina, acted }
--              (minions of one squad fold into a single entry, its name the
--              squad id, tokens = every selected minion of that squad);
--  actedCount / freshCount over members; allActed = every member acted;
--  inCombat  = a live, non-hidden initiative queue exists.
local function OverviewColumnSignals(column)
    local q = dmhub.initiativeQueue
    if q ~= nil and q.hidden then
        q = nil
    end

    local members = {}
    local byKey = {}
    local heroes = nil
    if q ~= nil then
        heroes = OverviewHeroTokens()
    end
    for _, tok in ipairs(column.tokens or {}) do
        if tok ~= nil and tok.valid and tok.properties ~= nil then
            local squad = nil
            pcall(function() squad = tok.properties:MinionSquad() end)
            local key = squad or tok.charid
            local member = byKey[key]
            if member == nil then
                member = {
                    token = tok,
                    name = squad or tok.name or column.name or "Creature",
                    tokens = {},
                    stamina = OverviewStaminaText(tok),
                    --P2-d: only in combat (heroes nil otherwise -> nil).
                    reach = cond(heroes ~= nil, OverviewReach(tok, column.abilities, heroes), nil),
                    risk = nil,
                    acted = OverviewActedState(q, tok),
                    --Slice (e): mid-turn (HasHadTurn only flips at turn
                    --end), so the signal line can read "acting now".
                    acting = false,
                }
                member.statuses, member.captain = OverviewStatusEntries(tok)
                if q ~= nil then
                    pcall(function() member.acting = q.currentTurn == InitiativeQueue.GetInitiativeId(tok) end)
                end
                --P2-e: threat estimate (nil when safe / out of combat).
                local threats = {}
                for _, entry in ipairs(member.statuses or {}) do
                    if entry.threat then
                        threats[#threats + 1] = entry
                    end
                end
                local lowStamina = OverviewLowStamina(tok, q ~= nil)
                --Field test 7: Low Stamina appears exactly ONCE - as a risk
                --bullet, never doubled on the stamina readout (the raw
                --number stays plain).
                member.risk = OverviewThreatEstimate(tok, threats, q ~= nil, lowStamina,
                    member.acted == true or member.acting == true)
                byKey[key] = member
                members[#members + 1] = member
            end
            member.tokens[#member.tokens + 1] = tok
        end
    end

    local actedCount = 0
    local freshCount = 0
    local knownCount = 0
    for _, member in ipairs(members) do
        if member.acted == true then
            actedCount = actedCount + 1
            knownCount = knownCount + 1
        elseif member.acted == false then
            freshCount = freshCount + 1
            knownCount = knownCount + 1
        end
    end

    return {
        members = members,
        actedCount = actedCount,
        --Only members with a queue entry count as not-yet-acted; a member
        --with no entry (reinforcements in "Ready Monsters") is unknown, and
        --knownCount lets the header stay silent rather than claim "2 of 2
        --not yet acted" about creatures that are not in the order at all.
        freshCount = freshCount,
        knownCount = knownCount,
        allActed = #members > 0 and actedCount == #members,
        inCombat = q ~= nil,
    }
end

--Locate on the map without selecting (Decision 51/X5): pan to one token,
--pulse a set. Never dmhub.FocusToken.
--
--F3-1: the pulse was requested but never SEEN. Two reasons, both measured
--live: dmhub.CenterOnToken{smooth=true} is a fixed ~0.5s eased tween (its
--callback fires synchronously, so it cannot be used to sequence), and the
--engine's PulseHighlightToken is a brief white flash - invisible while the
--camera is still moving, and indistinguishable from the white selection ring
--on a token that is already selected (which every overview token is). So:
--(1) the pulse is deferred until the pan has settled (immediate when the
--camera is already on the token), and (2) it is paired with the sustained
--coloured "locate" ring on the token's bottomsheet (TokenUI.lua), held for
--OVERVIEW.LOCATE_HOLD seconds. A later locate on the same token restarts
--the hold instead of being cut short by the earlier timer.

local function OverviewPulseTokens(tokens)
    for _, tok in ipairs(tokens) do
        if tok ~= nil and tok.valid then
            local charid = tok.charid
            local gen = (OVERVIEW.locateGeneration[charid] or 0) + 1
            OVERVIEW.locateGeneration[charid] = gen
            dmhub.PulseHighlightToken(charid)
            if tok.bottomsheet ~= nil and tok.bottomsheet.valid then
                tok.bottomsheet:SetClassTree("locate", true)
            end
            dmhub.Schedule(OVERVIEW.LOCATE_HOLD, function()
                if mod.unloaded or OVERVIEW.locateGeneration[charid] ~= gen then
                    return
                end
                OVERVIEW.locateGeneration[charid] = nil
                local live = dmhub.GetTokenById(charid)
                if live ~= nil and live.valid and live.bottomsheet ~= nil and live.bottomsheet.valid then
                    live.bottomsheet:SetClassTree("locate", false)
                end
            end)
        end
    end
end

local function OverviewLocate(centerToken, pulseTokens)
    if centerToken == nil or not centerToken.valid then
        return
    end
    local tokens = {}
    for _, tok in ipairs(pulseTokens or { centerToken }) do
        tokens[#tokens + 1] = tok
    end

    --Field test 4: when locating a GROUP (a minion squad's mini-row), pan to
    --the member nearest the group's centroid, not to whichever token happened
    --to be listed first - in A5 one "Squad 4" Sniper is parked with Squad 5,
    --and centering on it read as "panned to the wrong squad".
    if #tokens > 1 then
        local sx, sy, n = 0, 0, 0
        for _, tok in ipairs(tokens) do
            if tok ~= nil and tok.valid then
                pcall(function()
                    sx = sx + tok.loc.x
                    sy = sy + tok.loc.y
                    n = n + 1
                end)
            end
        end
        if n > 0 then
            local cx, cy = sx / n, sy / n
            local best, bestd = nil, nil
            for _, tok in ipairs(tokens) do
                if tok ~= nil and tok.valid then
                    local ok = pcall(function()
                        local d = math.max(math.abs(tok.loc.x - cx), math.abs(tok.loc.y - cy))
                        if bestd == nil or d < bestd then
                            best, bestd = tok, d
                        end
                    end)
                end
            end
            if best ~= nil then
                centerToken = best
            end
        end
    end

    local alreadyThere = false
    pcall(function()
        local cam = dmhub.cameraPosition
        local loc = centerToken.loc
        alreadyThere = math.abs(cam.x - loc.x) < 0.5 and math.abs(cam.y - loc.y) < 0.5
    end)

    dmhub.CenterOnToken(centerToken.charid, { smooth = true })
    if alreadyThere then
        OverviewPulseTokens(tokens)
        return
    end
    dmhub.Schedule(OVERVIEW.LOCATE_PAN_TIME, function()
        if mod.unloaded then
            return
        end
        OverviewPulseTokens(tokens)
    end)
end

--Acted-state copy for one member. Field test 4 (Ricky): NOT having acted
--is the default and is not worth a label - the chips are bright and the
--take-turn button is there; so nil for that case, nil out of combat or with
--no queue entry. Having ACTED is the thing nobody must miss: the column is
--already greyed (F2-7) and the line reads "Turn already taken" in red.
--"Acting now" keeps its own plain text (mid-turn, HasHadTurn not yet set).
local OVERVIEW_ACTED_COLOR = "#E06464"
local function OverviewActedText(member, inCombat)
    if not inCombat then
        return nil
    end
    if member.acting == true then
        return "Acting now"
    elseif member.acted == true then
        return string.format("<color=%s>Turn already taken</color>", OVERVIEW_ACTED_COLOR)
    end
    return nil
end

--"13/15" / "13/15 - Turn already taken" signal text for one member. The stamina is
--the bare current/max readout every token nameplate in the app already uses
--(a "Stamina " prefix pushed the acted state past the 151px text column and
--got it ellipsized - measured live).
--Field test 10: the signal line carries ONLY the acted state. The raw
--stamina number is gone (Low Stamina lives as a risk bullet) and the
--hero-applied effect names live in the risk box bullets - printing either
--here doubled the information.
local function OverviewSignalText(member, inCombat)
    return OverviewActedText(member, inCombat) or ""
end

--Slice (e): the members of a column that could still take a turn, one per
--DISTINCT initiative entry (a minion squad is one member already; several
--tokens sharing an initiativeGrouping fold into one). Each entry is the
--signals member record plus .initiativeid. Empty when no queue is running or
--everyone has acted.
local function OverviewFreshCandidates(signals)
    local result = {}
    if signals == nil or not signals.inCombat then
        return result
    end
    local seen = {}
    for _, member in ipairs(signals.members) do
        if member.acted == false and member.acting ~= true and member.token ~= nil and member.token.valid then
            local initiativeid = nil
            pcall(function() initiativeid = InitiativeQueue.GetInitiativeId(member.token) end)
            if initiativeid ~= nil and not seen[initiativeid] then
                seen[initiativeid] = true
                member.initiativeid = initiativeid
                result[#result + 1] = member
            end
        end
    end
    return result
end

--Slice (e): a column's chips carry the REPRESENTATIVE member's bound copy of
--each ability. When the owner prompt hands the cast to a different member,
--fetch that member's own bound copy of the same ability (same guid, same
--melee/ranged variation) so cost/range/GoblinScript resolve against the
--actual caster. Falls back to the chip's ability if no match is found.
local function OverviewMemberAbility(memberToken, ability)
    if memberToken == nil or not memberToken.valid or memberToken.properties == nil or ability == nil then
        return ability
    end
    local wanted = NovelAbilityKey(ability)
    if wanted == nil then
        return ability
    end
    local found = nil
    pcall(function()
        local kit = memberToken.properties:GetActivatedAbilities { excludeGlobal = true, bindCaster = true }
        for _, candidate in ipairs(kit or {}) do
            local variations = { candidate }
            if candidate.meleeAndRanged then
                variations = { candidate.meleeVariation, candidate.rangedVariation }
            end
            for _, variation in ipairs(variations) do
                if variation ~= nil and NovelAbilityKey(variation) == wanted then
                    found = variation
                    return
                end
            end
        end
    end)
    return found or ability
end

--Plain-English plural of a statblock name for the shared-entry button copy
--("Goblin Assassins'", "Goblin Bosses'", "Harpies'"). Only used in a
--possessive, so the result already carries the apostrophe.
local function OverviewPluralPossessive(name)
    local lower = string.lower(name)
    if string.match(lower, "[sxz]$") or string.match(lower, "[cs]h$") then
        return name .. "es'"
    end
    if string.match(lower, "[^aeiou]y$") then
        return string.sub(name, 1, -2) .. "ies'"
    end
    return name .. "s'"
end

--"Take <Name>'s turn" (single actor) / "Take a <Name>'s turn" (several
--members with their OWN initiative entries - the press then asks which) /
--"Take the <Names>' turn" (F2-3: several members sharing ONE entry via
--initiativeGrouping, e.g. Sneaky + Dizzy Assassin - they act as a unit, so
--say so instead of surprising the Director). Falls back to "Take turn" when
--the name would not fit the 205px footer; the full text always goes in the
--tooltip.
local function OverviewTakeTurnText(column, memberCount, sharedEntry)
    local name = column.name or "Creature"
    local full
    if memberCount > 1 and sharedEntry then
        full = string.format("Take the %s turn", OverviewPluralPossessive(name))
    elseif memberCount > 1 then
        full = string.format("Take a %s's turn", name)
    else
        full = string.format("Take %s's turn", name)
    end
    local short = full
    if #full > 32 then
        short = "Take turn"
    end
    return short, full
end

--One pooled footer bar. Populate/refresh via FireEvent("overviewColumn",
--column, signals) where signals = OverviewColumnSignals(column).
--
--Slice (e) additions, all pooled and created once here:
--  * takeTurnButton + reasonLabel: "Take <Creature>'s turn", enabled only
--    when OverviewClaimGate passes for the representative's entry; when
--    disabled it stays visible, greyed, with the reason inline and in the
--    tooltip. Press: one fresh member -> OverviewClaimTurn directly; several
--    distinct-initiative fresh members -> arm the owner prompt below.
--  * owner-selection prompt (Decisions 32/36): FireEvent("armOwnerPrompt",
--    prompt) with prompt = { members = OverviewFreshCandidates(...), ability
--    = ActivatedAbility|nil, choose = function(member) }, or nil to disarm.
--    While armed the mini-rows list ONLY the fresh members by token name,
--    hovering a row pulses that token, pressing it calls prompt.choose. Esc /
--    click-away close the menu, which disarms (ActionMenu closemenu/toggle),
--    and any repopulate ("overviewColumn") disarms too.
local function OverviewColumnFooter()
    local m_column = nil
    local m_signals = nil
    local m_prompt = nil
    local m_claimId = nil
    local m_claimReason = nil
    local m_takeTurnTooltip = nil

    local portrait = gui.CreateTokenImage(nil, {
        width = 34,
        height = 34,
        halign = "left",
        valign = "center",
        interactable = false,
    })

    local nameLabel = gui.Label {
        classes = { "overviewFooterName" },
        text = "",
    }
    --Field test 7: the squad-captain crown is identity, so it sits beside
    --the name (squad colour preserved), not in the status strip.
    local captainIcon = gui.Panel {
        classes = { "overviewCaptainIcon", "collapsed" },
        bgimage = "panels/hud/crown.png",
        hover = gui.Tooltip("Squad captain"),
    }
    local nameRow = gui.Panel {
        classes = { "overviewFooterNameRow" },
        nameLabel,
        captainIcon,
    }
    --F2-9: role word first and emphasised (overviewFooterRole colours the
    --bold lead via the label's rich text); hover = the role's one-line play
    --pattern (Decision 15). m_roleTooltip is set per column.
    local m_roleTooltip = nil
    local roleLabel = gui.Label {
        classes = { "overviewFooterLine", "overviewFooterRole" },
        text = "",
        hover = function(element)
            if m_roleTooltip ~= nil and m_roleTooltip ~= "" then
                gui.Tooltip(m_roleTooltip)(element)
            end
        end,
    }
    local signalLabel = gui.Label {
        classes = { "overviewFooterLine" },
        text = "",
    }
    --P2-d reach estimate line (single-member columns; mini-rows carry the
    --short form). Hover explains the arithmetic and that it is an estimate.
    local m_reachTooltip = nil
    local reachLabel = gui.Label {
        classes = { "overviewFooterLine", "overviewFooterReach", "collapsed" },
        text = "",
        hover = function(element)
            if m_reachTooltip ~= nil then
                gui.Tooltip(m_reachTooltip)(element)
            end
        end,
    }
    --P2-e: the threat-estimate line ("High target risk - marked by heroes,
    --3 heroes in striking range"); collapsed when safe. Hover = the
    --arithmetic + the hint.
    local m_riskTooltip = nil
    local riskLabel = gui.Label {
        classes = { "overviewFooterRisk", "collapsed" },
        text = "",
        hover = function(element)
            if m_riskTooltip ~= nil then
                gui.Tooltip(m_riskTooltip)(element)
            end
        end,
    }

    --P2-a: status strip - the token HUD's status icons for a single-member
    --column (>= 16px per X15; threat flags red-ringed, hover = the HUD's own
    --hover text). Pooled icon panels + "+N"; collapsed when empty or when the
    --column has several members (their mini-rows mirror the names instead).
    local statusIcons = {}
    for i = 1, OVERVIEW.STATUS_ICONS do
        statusIcons[i] = gui.Panel {
            classes = { "overviewStatusIcon", "collapsed" },
            bgimage = "panels/square.png",
            data = { entry = nil },
            hover = function(element)
                local entry = element.data.entry
                if entry ~= nil and entry.hoverText ~= nil and entry.hoverText ~= "" then
                    gui.Tooltip(entry.hoverText)(element)
                end
            end,
            setStatus = function(element, entry)
                element.data.entry = entry
                if entry == nil then
                    element:SetClass("collapsed", true)
                    return
                end
                element:SetClass("collapsed", false)
                element.bgimage = entry.icon
                local bgcolor = "white"
                if type(entry.style) == "table" and entry.style.bgcolor ~= nil then
                    bgcolor = entry.style.bgcolor
                end
                element.selfStyle.bgcolor = bgcolor
                element:SetClass("threat", entry.threat == true)
            end,
        }
    end
    local statusMore = gui.Label {
        classes = { "overviewStatusMore", "collapsed" },
        text = "",
    }
    local statusStripChildren = {}
    for _, icon in ipairs(statusIcons) do
        statusStripChildren[#statusStripChildren + 1] = icon
    end
    statusStripChildren[#statusStripChildren + 1] = statusMore
    local statusStrip = gui.Panel {
        classes = { "overviewStatusStrip", "collapsed" },
        children = statusStripChildren,
        setStatuses = function(element, entries)
            if entries == nil or #entries == 0 then
                element:SetClass("collapsed", true)
                for _, icon in ipairs(statusIcons) do
                    icon:FireEvent("setStatus", nil)
                end
                statusMore:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)
            for i, icon in ipairs(statusIcons) do
                icon:FireEvent("setStatus", entries[i])
            end
            local overflow = #entries - #statusIcons
            if overflow > 0 then
                statusMore.text = string.format("+%d", overflow)
                statusMore:SetClass("collapsed", false)
            else
                statusMore:SetClass("collapsed", true)
            end
        end,
    }

    --Field test 11: the status glyphs sit DIRECTLY UNDER THE PORTRAIT - the
    --same fact as the risk bullets, on purpose: the image lands faster than
    --the words.
    local header = gui.Panel {
        classes = { "overviewFooterHeader" },
        gui.Panel {
            classes = { "overviewFooterPortraitColumn" },
            portrait,
            statusStrip,
        },
        gui.Panel {
            classes = { "overviewFooterText" },
            nameRow,
            roleLabel,
            signalLabel,
            reachLabel,
            riskLabel,
        },
    }

    --Instruction line of the owner-selection prompt; collapsed until armed.
    local promptLabel = gui.Label {
        classes = { "overviewFooterPrompt", "collapsed" },
        text = "",
    }

    --Fixed pool of member mini-rows plus the overflow line; created once,
    --collapsed when unused, never re-listed. The signals view uses the first
    --OVERVIEW.FOOTER_ROWS; the owner prompt may use the whole pool.
    local rows = {}
    for i = 1, OVERVIEW.FOOTER_ROW_POOL do
        local rowPortrait = gui.CreateTokenImage(nil, {
            width = 24,
            height = 24,
            halign = "left",
            valign = "center",
            interactable = false,
        })
        --F2-4: two lines - the name alone (ellipsized) and the signals -
        --instead of one long line that overflowed the column border.
        local rowLabel = gui.Label {
            classes = { "overviewFooterRowLabel" },
            text = "",
        }
        local rowSignal = gui.Label {
            classes = { "overviewFooterRowSignal" },
            text = "",
        }
        local rowText = gui.Panel {
            classes = { "overviewFooterRowText" },
            rowLabel,
            rowSignal,
        }
        local row
        row = gui.Panel {
            classes = { "overviewFooterRow", "collapsed" },
            --Stop the bubble at the row: without this a real click on a
            --mini-row ALSO fired the footer's own locate.
            swallowPress = true,
            data = { member = nil },
            rowPortrait,
            rowText,

            press = function(element)
                local member = element.data.member
                if member == nil then
                    return
                end
                if m_prompt ~= nil then
                    --Owner prompt armed: this row IS the choice.
                    local prompt = m_prompt
                    element:FindParentWithClass("overviewFooter"):FireEvent("armOwnerPrompt", nil)
                    if prompt.choose ~= nil then
                        prompt.choose(member)
                    end
                    return
                end
                OverviewLocate(member.token, member.tokens)
            end,

            --Decision 36: while the prompt is armed, hovering a member pulses
            --that creature on the map so the Director sees who they are about
            --to activate.
            hover = function(element)
                local member = element.data.member
                if m_prompt ~= nil and member ~= nil then
                    for _, tok in ipairs(member.tokens) do
                        if tok ~= nil and tok.valid then
                            dmhub.PulseHighlightToken(tok.charid)
                        end
                    end
                end
            end,

            setMember = function(element, member, inCombat)
                element.data.member = member
                if member == nil then
                    element:SetClass("collapsed", true)
                    element:SetClass("promptOption", false)
                    return
                end
                --The member list is snapshotted into m_signals when the column
                --is populated, and LayoutRows re-runs from that cache on every
                --menu open/close (DisarmOverviewPrompts fans out to parked
                --columns too). A member's token can be gone by then (a killed
                --minion cleaned up), and the engine's portraitFrame getter NREs
                --on such a token, so drop the row instead of updating it.
                if member.token == nil or not member.token.valid then
                    element:SetClass("collapsed", true)
                    element:SetClass("promptOption", false)
                    return
                end
                element:SetClass("collapsed", false)
                element:SetClass("promptOption", m_prompt ~= nil)
                local ok = pcall(function()
                    rowPortrait:FireEventTree("token", member.token)
                end)
                if not ok then
                    element:SetClass("collapsed", true)
                    element:SetClass("promptOption", false)
                    return
                end
                local text = member.name
                if #member.tokens > 1 then
                    text = string.format("%s (%d)", text, #member.tokens)
                end
                rowLabel.text = text
                local signal = OverviewSignalText(member, inCombat)
                local reach = OverviewReachText(member.reach, true)
                if reach ~= nil then
                    if signal == "" then
                        signal = reach
                    else
                        signal = signal .. " - " .. reach
                    end
                end
                --P2-e short tag on the member row.
                if member.risk ~= nil then
                    local color = member.risk.level == "red" and g_overviewRisk.red or g_overviewRisk.amber
                    local tag = string.format("<color=%s><b>%s</b></color>", color, member.risk.level == "red" and "high risk" or "at risk")
                    if signal == "" then
                        signal = tag
                    else
                        signal = signal .. " - " .. tag
                    end
                end
                rowSignal.text = signal
                rowSignal:SetClass("collapsed", signal == "")
            end,
        }
        rows[i] = row
    end

    local moreLabel = gui.Label {
        classes = { "overviewFooterMore", "collapsed" },
        text = "",
    }

    --"Take <Creature>'s turn" and its inline reason when disabled.
    local takeTurnButton = gui.Label {
        classes = { "overviewTakeTurn", "disabled" },
        swallowPress = true,
        text = "Take turn",

        hover = function(element)
            if m_takeTurnTooltip ~= nil then
                gui.Tooltip(m_takeTurnTooltip)(element)
            end
        end,

        press = function(element)
            if m_column == nil or m_signals == nil then
                return
            end
            local footer = element:FindParentWithClass("overviewFooter")
            if m_prompt ~= nil then
                --Second press while the prompt is up backs out of it.
                footer:FireEvent("armOwnerPrompt", nil)
                return
            end
            if element:HasClass("disabled") or m_claimId == nil then
                return
            end
            audio.FireSoundEvent("Mouse.Click")

            local candidates = OverviewFreshCandidates(m_signals)
            if #candidates > 1 then
                --Several distinct initiative entries share this column
                --(two Goblin Warriors, Sneaky/Dizzy): the Director picks the
                --member whose turn is taken (Decisions 32/36).
                footer:FireEvent("armOwnerPrompt", {
                    members = candidates,
                    ability = nil,
                    choose = function(member)
                        if OverviewClaimTurn(member.initiativeid) then
                            local menu = footer:FindParentWithClass("actionMenu")
                            if menu ~= nil then
                                menu:FireEvent("refreshOverview")
                            end
                        end
                    end,
                })
                return
            end

            --One actor (single monster or a whole minion squad, which shares
            --one initiative id): take the turn now.
            if OverviewClaimTurn(m_claimId) then
                --Confirmation: the column repopulates from the live queue, so
                --the button now reads "Turn taken - acting now" and the
                --signals line flips to acted.
                local menu = footer:FindParentWithClass("actionMenu")
                if menu ~= nil then
                    menu:FireEvent("refreshOverview")
                end
            end
        end,
    }
    local reasonLabel = gui.Label {
        classes = { "overviewTakeTurnReason", "collapsed" },
        text = "",
    }

    --F2-8: dismiss this statblock from the overview - drops the column AND
    --deselects its tokens on the map (the selection poll then repopulates
    --the open menu; with one token left the strip falls back to the classic
    --single-creature bar). A plain panel on purpose, not gui.Button{kind =
    --"closeButton"}: that kind binds Escape, which must keep closing the
    --menu. Floating at the footer's top-right so it never shifts the rows.
    local dismissButton = gui.Panel {
        classes = { "overviewDismiss" },
        swallowPress = true,
        bgimage = "ui-icons/close.png",
        floating = true,
        halign = "right",
        valign = "top",
        hover = gui.Tooltip("Remove from the overview (deselects on the map)"),
        press = function(element)
            if m_column == nil then
                return
            end
            local remove = {}
            for _, tok in ipairs(m_column.tokens or {}) do
                if tok ~= nil and tok.valid then
                    remove[tok.charid] = true
                end
            end
            local remaining = {}
            for _, tok in ipairs(dmhub.selectedTokens or {}) do
                if tok ~= nil and tok.valid and not remove[tok.charid] then
                    remaining[#remaining + 1] = tok
                end
            end
            audio.FireSoundEvent("Mouse.Click")
            dmhub.selectedTokens = remaining
        end,
    }

    local children = { header, promptLabel, dismissButton }
    for _, row in ipairs(rows) do
        children[#children + 1] = row
    end
    children[#children + 1] = moreLabel
    children[#children + 1] = takeTurnButton
    children[#children + 1] = reasonLabel

    --Lay the mini-rows out for the current mode: the signals view (first
    --OVERVIEW.FOOTER_ROWS members, "+N more") or the armed owner prompt
    --(fresh candidates only, whole pool).
    local function LayoutRows()
        if m_signals == nil then
            for _, row in ipairs(rows) do
                row:FireEvent("setMember", nil)
            end
            moreLabel:SetClass("collapsed", true)
            return
        end

        local list = nil
        local cap = OVERVIEW.FOOTER_ROWS
        if m_prompt ~= nil then
            list = m_prompt.members
            cap = #rows
        elseif #m_signals.members > 1 then
            list = m_signals.members
        end

        if list == nil then
            for _, row in ipairs(rows) do
                row:FireEvent("setMember", nil)
            end
            moreLabel:SetClass("collapsed", true)
            return
        end

        for i, row in ipairs(rows) do
            if i <= cap then
                row:FireEvent("setMember", list[i], m_signals.inCombat)
            else
                row:FireEvent("setMember", nil)
            end
        end
        local overflow = #list - cap
        if overflow > 0 then
            moreLabel.text = string.format("+%d more", overflow)
            moreLabel:SetClass("collapsed", false)
        else
            moreLabel:SetClass("collapsed", true)
        end
    end

    --Recompute the take-turn button from the live queue.
    local function LayoutTakeTurn()
        if m_column == nil or m_signals == nil then
            takeTurnButton:SetClass("collapsed", true)
            reasonLabel:SetClass("collapsed", true)
            m_claimId = nil
            return
        end
        --The entry the button acts on: the one still-fresh member's entry
        --when exactly one remains (which need not be the representative's -
        --the representative can be the member acting NOW), the
        --representative's when none is fresh (so the gate reports WHY), or -
        --when several members are still fresh - the press arms the owner
        --prompt and the button is enabled if ANY of them may claim.
        local candidates = OverviewFreshCandidates(m_signals)
        local ok, reason, settled
        if #candidates > 1 then
            ok = false
            settled = true
            for _, member in ipairs(candidates) do
                local memberOk, memberReason, memberSettled = OverviewClaimGate(member.initiativeid)
                if memberOk then
                    ok = true
                    reason = nil
                    settled = false
                    break
                end
                reason = reason or memberReason
                settled = settled and memberSettled
            end
            m_claimId = candidates[1].initiativeid
        elseif #candidates == 1 then
            m_claimId = candidates[1].initiativeid
            ok, reason, settled = OverviewClaimGate(m_claimId)
        else
            m_claimId = nil
            pcall(function() m_claimId = InitiativeQueue.GetInitiativeId(m_column.token) end)
            ok, reason, settled = OverviewClaimGate(m_claimId)
        end

        --F3-2: once the turn is taken / the creature has acted (or nothing is
        --running), taking the turn is not an option any more - the button is
        --noise, not information. The footer signal line carries the state
        --("acting now" / "acted"); hide the button and its reason outright.
        if not ok and settled then
            takeTurnButton:SetClass("collapsed", true)
            reasonLabel:SetClass("collapsed", true)
            m_claimReason = reason
            m_takeTurnTooltip = nil
            return
        end
        takeTurnButton:SetClass("collapsed", false)

        --F2-3: do the column's members all share ONE initiative entry? Count
        --over EVERY member token, not just the representatives - in A5 a
        --squad's tokens can carry different initiativeGrouping ids.
        local sharedEntry = false
        if #m_signals.members > 1 then
            local distinct = {}
            local count = 0
            for _, member in ipairs(m_signals.members) do
                for _, tok in ipairs(member.tokens) do
                    local initiativeid = nil
                    pcall(function() initiativeid = InitiativeQueue.GetInitiativeId(tok) end)
                    if initiativeid ~= nil and not distinct[initiativeid] then
                        distinct[initiativeid] = true
                        count = count + 1
                    end
                end
            end
            sharedEntry = count == 1
        end

        local short, full = OverviewTakeTurnText(m_column, #m_signals.members, sharedEntry)
        takeTurnButton.text = short
        takeTurnButton:SetClass("disabled", not ok)
        m_claimReason = reason
        if ok then
            m_takeTurnTooltip = full
            reasonLabel:SetClass("collapsed", true)
        else
            m_takeTurnTooltip = string.format("%s: %s", full, reason or "unavailable")
            reasonLabel.text = reason or ""
            reasonLabel:SetClass("collapsed", reason == nil)
        end
    end

    local resultPanel
    resultPanel = gui.Panel {
        classes = { "overviewFooter", "collapsed" },
        children = children,
        --Real presses bubble to ancestors (see the lens tab note); the
        --footer is the last stop before the drawer toggle.
        swallowPress = true,

        press = function(element)
            if m_column == nil or m_signals == nil then
                return
            end
            local pulse = {}
            for _, member in ipairs(m_signals.members) do
                for _, tok in ipairs(member.tokens) do
                    pulse[#pulse + 1] = tok
                end
            end
            OverviewLocate(m_column.token, pulse)
        end,

        --Arm (prompt ~= nil) or disarm (nil) the owner-selection prompt.
        armOwnerPrompt = function(element, prompt)
            if prompt ~= nil and (m_column == nil or m_signals == nil or prompt.members == nil or #prompt.members == 0) then
                prompt = nil
            end
            m_prompt = prompt
            if prompt == nil then
                promptLabel:SetClass("collapsed", true)
                takeTurnButton:SetClass("collapsed", m_column == nil)
                LayoutRows()
                if m_column ~= nil then
                    LayoutTakeTurn()
                end
                return
            end

            local name = m_column.name or "creature"
            if prompt.ability ~= nil then
                promptLabel.text = string.format("Choose which %s uses %s", name, prompt.ability.name)
            else
                promptLabel.text = string.format("Choose which %s takes the turn", name)
            end
            promptLabel:SetClass("collapsed", false)
            takeTurnButton.text = "Cancel"
            takeTurnButton:SetClass("collapsed", false)
            takeTurnButton:SetClass("disabled", false)
            m_takeTurnTooltip = "Back out without choosing"
            reasonLabel:SetClass("collapsed", true)
            LayoutRows()

            --Show every candidate on the map at once.
            for _, member in ipairs(prompt.members) do
                for _, tok in ipairs(member.tokens) do
                    if tok ~= nil and tok.valid then
                        dmhub.PulseHighlightToken(tok.charid)
                    end
                end
            end
        end,

        overviewColumn = function(element, column, signals)
            m_column = column
            m_signals = signals
            m_prompt = nil
            promptLabel:SetClass("collapsed", true)
            if column == nil or signals == nil or column.token == nil or not column.token.valid then
                element:SetClass("collapsed", true)
                LayoutRows()
                LayoutTakeTurn()
                return
            end
            element:SetClass("collapsed", false)

            pcall(function()
                portrait:FireEventTree("token", column.token)
            end)
            nameLabel.text = column.label or column.name or ""
            --Crown when the column's single actor is a squad captain (a
            --multi-member statblock column has no single identity to crown).
            local captain = nil
            if #signals.members == 1 and signals.members[1] ~= nil then
                captain = signals.members[1].captain
            end
            if captain ~= nil then
                local bgcolor = "white"
                if type(captain.style) == "table" and captain.style.bgcolor ~= nil then
                    bgcolor = captain.style.bgcolor
                end
                captainIcon.selfStyle.bgcolor = bgcolor
                captainIcon:SetClass("collapsed", false)
            else
                captainIcon:SetClass("collapsed", true)
            end

            local roleInfo = OverviewRoleInfo(column.token)
            roleLabel.text = roleInfo and roleInfo.line or ""
            roleLabel:SetClass("collapsed", roleInfo == nil)
            m_roleTooltip = nil
            if roleInfo ~= nil and roleInfo.prose ~= "" then
                m_roleTooltip = string.format("%s\n%s", roleInfo.plain, roleInfo.prose)
            end

            local members = signals.members
            local text = ""
            if #members <= 1 then
                --Single actor: its own signals on the header line.
                local member = members[1]
                if member ~= nil then
                    text = OverviewSignalText(member, signals.inCombat)
                end
            elseif signals.inCombat and signals.actedCount > 0 then
                --Several actors: the header only speaks up once some of
                --them HAVE acted (field test 4: not-yet-acted is the silent
                --default); one mini-row per actor below (LayoutRows).
                if signals.actedCount == #members then
                    text = string.format("<color=%s>Turn already taken</color>", OVERVIEW_ACTED_COLOR)
                else
                    text = string.format("<color=%s>%d of %d already acted</color>", OVERVIEW_ACTED_COLOR, signals.actedCount, #members)
                end
            end
            signalLabel.text = text
            signalLabel:SetClass("collapsed", text == "")

            --P2-a: status strip for a single actor; mini-rows carry the
            --names when there are several. Field test 4: a hero-applied
            --threat already prints as red TEXT on the signal line, so the
            --strip shows only the OTHER statuses - never both channels for
            --the same fact.
            --Field test 11: ALL statuses (threats red-ringed) - the visual
            --twin of the risk bullets, under the portrait.
            if #members == 1 then
                statusStrip:FireEvent("setStatuses", members[1].statuses)
            else
                statusStrip:FireEvent("setStatuses", nil)
            end

            --P2-e: risk line for a single actor; a multi-member column
            --shows the WORST member's line (its rows carry short tags).
            local risk = nil
            for _, member in ipairs(members) do
                if member.risk ~= nil and (risk == nil or (member.risk.level == "red" and risk.level ~= "red")) then
                    risk = member.risk
                end
            end
            m_riskTooltip = risk and risk.tooltip or nil
            local riskText = risk and risk.text or nil
            --Field test 9: "High damage dealer" rides as a bullet under the
            --risk tag (before the green guidance), or stands alone in gold
            --when the creature is otherwise safe.
            if column.highDamage then
                if riskText == nil then
                    riskText = "<color=#C9A86A><b>High damage dealer</b></color>"
                    m_riskTooltip = "This creature's kit has the best typical (tier-2) damage in the selection."
                else
                    local bullet = "- High damage dealer"
                    local guideAt = string.find(riskText, "<color=" .. OVERVIEW.GUIDE_COLOR, 1, true)
                    if guideAt ~= nil then
                        riskText = string.sub(riskText, 1, guideAt - 1) .. bullet .. "\n" .. string.sub(riskText, guideAt)
                    else
                        riskText = riskText .. "\n" .. bullet
                    end
                    m_riskTooltip = (m_riskTooltip or "") .. "\nBest typical (tier-2) damage among the dying - if several are about to die, burn this one for damage first."
                end
            end
            riskLabel.text = riskText or ""
            riskLabel:SetClass("collapsed", riskText == nil)

            --P2-d: reach line for a single actor (rows carry it otherwise).
            local reachText = nil
            m_reachTooltip = nil
            if #members == 1 and members[1].reach ~= nil then
                local reach = members[1].reach
                reachText = OverviewReachText(reach)
                m_reachTooltip = string.format(
                    "Heroes within %d squares: speed %d + longest range %d. Straight-line estimate; ignores walls and terrain.",
                    reach.reach, reach.speed, reach.range)
            end
            reachLabel.text = reachText or ""
            reachLabel:SetClass("collapsed", reachText == nil)

            LayoutRows()
            LayoutTakeTurn()
        end,
    }

    return resultPanel
end

local function ActionSubMenu(args)
    --The column's foot: the ordinary text heading (every legacy menu) and,
    --for a director-overview column, the identity/signals footer bar (slice
    --(d)) which takes the heading's place. Both are pooled for the life of
    --the column and always sit at the END of m_children, after the chips.
    local m_heading = gui.Label {
        classes = { "submenuHeading" },
        abilities = function(element, abilities, grouping)
            if grouping == "Triggers" then
                grouping = "Manual Use Triggers"
            end
            element.text = grouping
        end,
    }
    local m_footer = OverviewColumnFooter()

    --Pooled chips (AbilityHeading, created on demand, never destroyed) and
    --the pooled hairline an overview column shows between its main actions
    --and its maneuvers. m_children is REBUILT from these on every populate
    --(chips, divider at its slot, heading, footer) - see "abilities" below.
    local m_chips = {}
    local m_divider = gui.Panel {
        classes = { "overviewActionDivider", "collapsed" },
        interactable = false,
    }

    local m_children = { m_divider, m_heading, m_footer }

    local resultPanel

    --Optional owner override for every chip in this column (director
    --multi-monster overview: one column per statblock, chips cast for that
    --statblock's representative token). nil = the bar's bound token, exactly
    --as before. Set via the "setCasterToken" event BEFORE "abilities", since
    --the chips compute suppression/cost from their caster when populated.
    --m_column is the overview column record ({tokens, token, name, label})
    --passed alongside; nil for every ordinary menu, which keeps the plain
    --heading and no footer/greying.
    local m_casterToken = nil
    local m_column = nil

    --Slice (e): preview-on-click for an overview chip. Installed on every
    --chip of an overview column (nil for ordinary menus, whose press path is
    --byte-for-byte the old one). Called from AbilityHeading's press with the
    --ability, the chip's caster and a commit(casterToken) continuation that
    --runs the ordinary push-caster + beginCasting tail. Returns true when it
    --took over the press.
    --
    --  * Always LOCATE the owner first (CenterOnToken + pulse; never
    --    FocusToken, selection untouched) so the Director sees who is about
    --    to act; the targeting overlay beginCasting draws is the reach
    --    preview for now.
    --  * If several DISTINCT initiative entries in this column are still
    --    fresh (two Goblin Warriors, Sneaky/Dizzy), arm the footer's owner
    --    prompt with the ability remembered: pressing a member re-points the
    --    column at that member and commits the cast for it. Nothing is
    --    claimed here; the claim happens at target confirm if legal
    --    (g_overviewCastPending / OverviewClaimBeforeCast).
    --  * One member (or a minion squad, one initiative id) commits at once.
    local function OverviewChipPress(ability, casterToken, commit)
        if m_column == nil or m_casterToken == nil then
            return false
        end
        local signals = OverviewColumnSignals(m_column)
        local candidates = OverviewFreshCandidates(signals)
        print("OVERVIEW:: chip press", ability and ability.name, "candidates", #candidates)
        if #candidates > 1 then
            m_footer:FireEvent("armOwnerPrompt", {
                members = candidates,
                ability = ability,
                choose = function(member)
                    if member == nil or member.token == nil or not member.token.valid then
                        return
                    end
                    m_column.token = member.token
                    m_casterToken = member.token
                    OverviewLocate(member.token, member.tokens)
                    commit(member.token, OverviewMemberAbility(member.token, ability))
                end,
            })
            return true
        end

        --One (or no) fresh entry: cast for the chip's own caster - the
        --representative, which BuildOverviewColumns already points at the
        --first fresh member - unless the queue moved on since the menu was
        --populated, in which case follow the fresh member.
        local owner = casterToken
        local memberAbility = ability
        local fresh = candidates[1]
        if fresh ~= nil and fresh.token ~= nil and fresh.token.valid and (owner == nil or fresh.token.charid ~= owner.charid) then
            owner = fresh.token
            memberAbility = OverviewMemberAbility(owner, ability)
        end
        if owner ~= nil and owner.valid then
            OverviewLocate(owner, { owner })
        end
        commit(owner, memberAbility)
        return true
    end

    resultPanel = gui.Panel {

        vpad = -4,

        children = m_children,
        classes = { "abilitySubMenu" },
        blurBackground = true,
        data = { lensMatchCount = 0 },

        setCasterToken = function(element, casterToken, column)
            m_casterToken = casterToken
            m_column = column
            --The abilitySubMenu style wraps a vertical flow into a second
            --column when it runs out of height (legacy long menus). For an
            --overview column that wrap misfires: the engine resolves the
            --column's auto height and the wrap limit in one pass, and once
            --the footer grew past ~70px (F2-4 two-line rows / 12px text) the
            --footer of EVERY column - even a one-chip column - wrapped to the
            --top-right of its column (seen live, A5). An overview kit is a
            --handful of chips plus the footer and never needs to wrap, so
            --turn wrapping off while a column is bound; restore it when the
            --pooled panel is parked again.
            element.selfStyle.wrap = not (column ~= nil and casterToken ~= nil)
        end,

        --Forwarded to the footer (slice (e) owner prompt); no-op for ordinary
        --menus, whose footer is collapsed and has no column.
        armOwnerPrompt = function(element, prompt)
            m_footer:FireEvent("armOwnerPrompt", prompt)
        end,

        abilities = function(element, abilities)
            if abilities == nil or #abilities == 0 then
                element:SetClass("collapsed", true)
                --A pooled overview column parked with no kit drops its
                --footer state too (disarms any prompt).
                if m_column == nil then
                    m_footer:FireEvent("overviewColumn", nil, nil)
                end
                element:HaltEventPropagation()
                return
            end

            element:SetClass("collapsed", false)

            local overview = m_column ~= nil and m_casterToken ~= nil

            --P2-c1: per-ability facets and the active lens (overview only).
            local lens = "all"
            local facetsByAbility = {}
            local lensMatchCount = 0
            if overview then
                lens = g_overviewLens
                for _, ability in ipairs(abilities) do
                    local facets = OverviewAbilityFacets(ability)
                    facetsByAbility[ability] = facets
                    if OverviewAbilityMatchesLens(facets, lens) then
                        lensMatchCount = lensMatchCount + 1
                    end
                end
            end

            if overview then
                --Overview column (field test 2): main actions ABOVE, then
                --maneuvers / free actions BELOW a hairline; within a group,
                --the "All" lens puts signature first, then cost, then name
                --("Monarch = one above + one below, Warrior = two above"
                --reads structurally across columns); an active lens sorts by
                --its natural key instead (Decision 21 / 49), keeping the
                --action-economy partition.
                table.sort(abilities, function(a, b)
                    local groupA = OverviewActionType(a)
                    local groupB = OverviewActionType(b)
                    if groupA ~= groupB then
                        return groupA < groupB
                    end
                    if lens ~= "all" then
                        return OverviewLensLess(lens, a, facetsByAbility[a], b, facetsByAbility[b])
                    end
                    local sigA = a.categorization == "Signature Ability"
                    local sigB = b.categorization == "Signature Ability"
                    if sigA ~= sigB then
                        return sigA
                    end
                    local costA = GetHeroicResourceOrMaliceCost(a) or 0
                    local costB = GetHeroicResourceOrMaliceCost(b) or 0
                    if costA ~= costB then
                        return costA < costB
                    end
                    return a.name < b.name
                end)
            elseif abilities[1].categorization == "Malice" then
                table.sort(abilities, function(a, b)
                    return (GetHeroicResourceOrMaliceCost(a) or 0) < (GetHeroicResourceOrMaliceCost(b) or 0)
                end)
            elseif abilities[1].categorization == "Villain Action" then
                table.sort(abilities, function(a,b) return a:try_get("villainAction","") < b:try_get("villainAction","") end)
            else
                table.sort(abilities, function(a, b)
                    local costA = GetHeroicResourceOrMaliceCost(a) or 0
                    local costB = GetHeroicResourceOrMaliceCost(b) or 0
                    if costA ~= costB then
                        return costA < costB
                    end
                    return a.name < b.name
                end)
            end

            for i = 1, #abilities do
                m_chips[i] = m_chips[i] or AbilityHeading()
                --Re-point the pooled chip at this column's owner (nil restores
                --the g_token default) before it computes cost/suppression.
                --The overview press hook rides along (nil for ordinary menus).
                local pressHook = nil
                if overview then
                    pressHook = OverviewChipPress
                end
                m_chips[i]:FireEvent("setCasterToken", m_casterToken, pressHook)
                m_chips[i]:FireEventTree("ability", abilities[i])
                m_chips[i]:SetClass("collapsed", false)
                --P2-c1 lens channel (X3): matching chips get a left tick,
                --non-matching chips dim to .45 but stay (kit context). Both
                --cleared for the "All" lens and for ordinary menus.
                local onLens = false
                local offLens = false
                if overview and lens ~= "all" then
                    onLens = OverviewAbilityMatchesLens(facetsByAbility[abilities[i]], lens)
                    offLens = not onLens
                end
                m_chips[i]:SetClass("onLens", onLens)
                m_chips[i]:SetClass("offLens", offLens)
                --Field test 10: red surge DMG badge on (1) the highest-damage
                --ability displayed and (2) the highest among creatures at red
                --death risk (ties share it). Overview monsters only, and only
                --under the All / Damage lenses.
                local dmgBadge = false
                if overview and (lens == "all" or lens == "damage") and m_column ~= nil then
                    local facets = facetsByAbility[abilities[i]]
                    if facets ~= nil and facets.damageValue > 0 then
                        if (m_column.dmgMax ~= nil and facets.damageValue >= m_column.dmgMax)
                            or (m_column.anyRed and m_column.dmgRedMax ~= nil and facets.damageValue >= m_column.dmgRedMax) then
                            dmgBadge = true
                        end
                    end
                end
                m_chips[i]:FireEvent("setDamageBadge", dmgBadge)
            end

            for i = #abilities + 1, #m_chips do
                m_chips[i]:SetClass("collapsed", true)
            end

            --P2-c1 (Decision 31/49): a column with NO matching ability hides
            --under an active lens; the menu re-centers the survivors because
            --it is halign=center. The column stays populated so flipping the
            --lens back is instant.
            if overview and lens ~= "all" and lensMatchCount == 0 then
                element:SetClass("collapsed", true)
            end
            element.data.lensMatchCount = lensMatchCount

            --Hairline after the last main-action chip, only when the column
            --has chips on both sides of it.
            local dividerAfter = nil
            if overview then
                local lastMain = 0
                for i, ability in ipairs(abilities) do
                    if OverviewActionType(ability) == 0 then
                        lastMain = i
                    end
                end
                if lastMain > 0 and lastMain < #abilities then
                    dividerAfter = lastMain
                end
            end
            m_divider:SetClass("collapsed", dividerAfter == nil)

            --Rebuild the child order: every pooled chip (spares collapsed at
            --the end), the divider at its slot (or parked collapsed before
            --the tail), then heading + footer. Every pooled panel is ALWAYS
            --in the list (fa2053b7 rule); the list is only re-assigned when
            --the order actually changed.
            local newChildren = {}
            for i = 1, #m_chips do
                newChildren[#newChildren + 1] = m_chips[i]
                if dividerAfter == i then
                    newChildren[#newChildren + 1] = m_divider
                end
            end
            if dividerAfter == nil then
                newChildren[#newChildren + 1] = m_divider
            end
            newChildren[#newChildren + 1] = m_heading
            newChildren[#newChildren + 1] = m_footer

            local changed = #newChildren ~= #m_children
            if not changed then
                for i = 1, #newChildren do
                    if newChildren[i] ~= m_children[i] then
                        changed = true
                        break
                    end
                end
            end
            m_children = newChildren

            --Overview column: footer bar instead of the text heading, and
            --dim the whole column when every member has acted this round
            --(Decision 50). Ordinary menus: heading shown, footer collapsed,
            --never dimmed - unchanged from before slice (d).
            local allActed = false
            if overview then
                local signals = OverviewColumnSignals(m_column)
                allActed = signals.allActed
                m_footer:FireEvent("overviewColumn", m_column, signals)
            else
                m_footer:FireEvent("overviewColumn", nil, nil)
            end
            m_heading:SetClass("collapsed", overview)
            element:SetClass("acted", overview and allActed)
            --F2-7: grey every chip of an all-acted column (class tree so the
            --title / keywords / icon rules apply); always cleared for
            --ordinary menus, which reuse no overview state.
            for i = 1, #abilities do
                m_chips[i]:SetClassTree("acted", overview and allActed)
            end

            if changed then
                element.children = m_children
            end
        end,

        children = m_children,
    }

    return resultPanel
end



local g_categorizationMapping = {
    ["Basic Attack"] = "Skill",
}

--Director multi-monster overview: does this ability belong in a statblock's
--"unique kit" column? The kit comes from GetActivatedAbilities{excludeGlobal =
--true}, which already drops free strikes, band malice features (MonsterGroup
--maliceAbilities) and every global-modifier ability (Charge/Defend/Grab/Hide,
--Dig, Disengage/Jump...). What remains is filtered again here so the column
--holds ONLY the monster's own turn kit -- signature/heroic/"Ability" main
--actions and maneuvers together (Decision 13):
--  * Trigger / Villain Action are off-turn (Decision 16) and any ability whose
--    action resource is the triggered action goes with them;
--  * Malice-categorized abilities stay in the Malice drawer;
--  * Common Ability / Basic Attack / Move / Hidden are the noise the overview
--    exists to remove (belt-and-braces: excludeGlobal already removes them for
--    every stock monster).
local function IsUniqueKitAbility(ability)
    local cat = ability.categorization
    if cat == "Trigger" or cat == "Villain Action" or cat == "Malice"
        or cat == "Common Ability" or cat == "Basic Attack" or cat == "Move" or cat == "Hidden" then
        return false
    end
    if ability.actionResourceId == CharacterResource.triggerResourceId then
        return false
    end
    return true
end

--Group g_selectedTokens by statblock and build one column description per
--statblock, in order of first appearance in the selection (stable across
--refreshes for as long as the selection stands). Renamed tokens of one
--statblock ("Sneaky"/"Dizzy" Goblin Assassin) share a column. Returns a list
--of { key, label, tokens, token, abilities }:
--  key      = the statblock key (GetMonsterType(), else the token id);
--  label    = statblock name plus " xN" when N > 1 (slice (d) replaces this
--             with the portrait/signals footer bar);
--  tokens   = every selected token of that statblock, selection order;
--  token    = the representative token every chip casts for: the first
--             member that has NOT acted this round (initiative queue
--             HasHadTurn on its initiative id), else the first member;
--  abilities= the representative's unique kit (see IsUniqueKitAbility),
--             melee/ranged bifurcated like g_abilities is.
local function BuildOverviewColumns()
    local columns = {}
    local byKey = {}

    for _, tok in ipairs(g_selectedTokens) do
        if tok ~= nil and tok.valid and tok.properties ~= nil then
            local statblock = nil
            pcall(function() statblock = tok.properties:GetMonsterType() end)
            local key = statblock or tok.id
            local column = byKey[key]
            if column == nil then
                column = {
                    key = key,
                    name = statblock or tok.name or "Creature",
                    tokens = {},
                }
                byKey[key] = column
                columns[#columns + 1] = column
            end
            column.tokens[#column.tokens + 1] = tok
        end
    end

    local q = dmhub.initiativeQueue
    if q ~= nil and q.hidden then
        q = nil
    end

    for _, column in ipairs(columns) do
        --Representative: prefer a member whose turn is still to come.
        local rep = column.tokens[1]
        if q ~= nil then
            for _, tok in ipairs(column.tokens) do
                local acted = false
                pcall(function() acted = q:HasHadTurn(InitiativeQueue.GetInitiativeId(tok)) == true end)
                if not acted then
                    rep = tok
                    break
                end
            end
        end
        column.token = rep

        if #column.tokens > 1 then
            column.label = string.format("%s x%d", column.name, #column.tokens)
        else
            column.label = column.name
        end

        local abilities = {}
        local kit = rep.properties:GetActivatedAbilities { excludeGlobal = true, bindCaster = true }
        for _, ability in ipairs(kit or {}) do
            if IsUniqueKitAbility(ability) then
                --Mirror the root refresh: melee/ranged bifurcations show as
                --two chips.
                local variations = { ability }
                if ability.meleeAndRanged then
                    variations = { ability.meleeVariation, ability.rangedVariation }
                end
                for _, variation in ipairs(variations) do
                    if variation ~= nil and ((not variation:try_get("hideWhenFiltered")) or variation:AbilityFilterFailureMessage(rep.properties) == nil) then
                        abilities[#abilities + 1] = variation
                    end
                end
            end
        end
        column.abilities = abilities
    end

    return columns
end

ActionMenu = function()
    local m_submenus = {}
    --Pooled per-statblock columns for the director overview ("unique"
    --drawer); reused across opens like m_submenus, never rebuilt per frame.
    local m_uniqueColumns = {}
    local m_args
    local resultPanel
    local m_showingAbility = false
    local m_abilitiesSubmenu = nil
    local m_signatureSubmenu = nil
    local m_spacer = nil
    local m_commonSignatureWrapper = nil

    local g_manualSetResourcePanel = gui.Label {
        classes = { "abilityHeading" },
        width = 205,
        height = 20,
        tmargin = 12,
        text = "Set Trigger",
        textAlignment = "center",
        fontSize = 14,
        bold = true,

        press = function(element)
            if g_token == nil then return end
            g_token:ModifyProperties {
                description = "Manually Set Trigger Resource",
                execute = function()
                    local resources = g_token.properties:GetResources()[CharacterResource.triggerResourceId] or 0
                    local resourcesAvailable = resources -
                        g_token.properties:GetResourceUsage(CharacterResource.triggerResourceId, "round")
                    if resourcesAvailable > 0 then
                        g_token.properties:ConsumeResource(CharacterResource.triggerResourceId, "round", 1)
                    else
                        g_token.properties:RefreshResource(CharacterResource.triggerResourceId, "round", 1)
                    end
                end,
            }
        end,
    }

    local m_containerPanel = gui.Panel {
        width = "auto",
        height = "auto",
        minHeight = 200,
        maxHeight = 900,
        flow = "horizontal",
        --Decision 31: lens survivors sit centered (the lens bar above is
        --wider than a single surviving column).
        halign = "center",
    }

    --P2-c1: the LENS BAR above the overview columns (Decision 27: fixed
    --width so the cycle arrows never move; label click = dropdown of every
    --lens with counts). Collapsed for every ordinary menu. Counts = matching
    --kit abilities across the selection. m_lensColumns is the last column
    --list PopulateUniqueColumns produced, so a lens change re-runs it.
    local m_lensCounts = {}
    local m_lensEmptyLabel = gui.Label {
        classes = { "overviewLensEmpty", "collapsed" },
        text = "",
    }
    --X6: "Everyone can: Charge, Knockback" - the COMMON abilities (not in any
    --column's unique kit) that satisfy the active lens, read off the first
    --column's representative. Collapsed for "All" and when none match.
    local m_lensEveryoneLabel = gui.Label {
        classes = { "overviewLensEveryone", "collapsed" },
        text = "",
    }
    local function EveryoneCanText(columns, lens)
        if lens == nil or lens == "all" or columns == nil or columns[1] == nil then
            return nil
        end
        local tok = columns[1].token
        if tok == nil or not tok.valid or tok.properties == nil then
            return nil
        end
        local kitKeys = {}
        for _, column in ipairs(columns) do
            for _, ability in ipairs(column.abilities or {}) do
                local key = NovelAbilityKey(ability)
                if key ~= nil then
                    kitKeys[key] = true
                end
            end
        end
        local names = {}
        local seen = {}
        pcall(function()
            local all = tok.properties:GetActivatedAbilities { bindCaster = true } or {}
            for _, ability in ipairs(all) do
                local variations = { ability }
                if ability.meleeAndRanged then
                    variations = { ability.meleeVariation, ability.rangedVariation }
                end
                for _, variation in ipairs(variations) do
                    local key = NovelAbilityKey(variation)
                    local cat = variation.categorization
                    if variation ~= nil and key ~= nil and not kitKeys[key]
                        and cat ~= "Trigger" and cat ~= "Villain Action" and cat ~= "Malice" and cat ~= "Hidden"
                        and OverviewAbilityMatchesLens(OverviewAbilityFacets(variation), lens) then
                        local name = variation.name or "?"
                        if not seen[name] then
                            seen[name] = true
                            names[#names + 1] = name
                        end
                    end
                end
            end
        end)
        if #names == 0 then
            return nil
        end
        table.sort(names)
        local shown = {}
        for i = 1, math.min(4, #names) do
            shown[#shown + 1] = names[i]
        end
        --Field test 4 copy: name the lens, not "everyone".
        local text = string.format("Common %s abilities: %s",
            string.lower(OverviewLensInfo(lens).name), table.concat(shown, ", "))
        if #names > 4 then
            text = string.format("%s +%d", text, #names - 4)
        end
        return text
    end
    local m_lensBar
    --counts = matching ABILITIES per lens (the number on the tab, Decision
    --8); creatureCounts = columns with at least one match (the tooltip
    --speaks in creatures, field test 8).
    local function LensCountsFromColumns(columns)
        local counts = {}
        local creatureCounts = {}
        for _, lens in ipairs(OVERVIEW_LENSES) do
            counts[lens.id] = 0
            creatureCounts[lens.id] = 0
        end
        for _, column in ipairs(columns or {}) do
            local columnHas = {}
            for _, ability in ipairs(column.abilities or {}) do
                local facets = OverviewAbilityFacets(ability)
                for _, lens in ipairs(OVERVIEW_LENSES) do
                    if OverviewAbilityMatchesLens(facets, lens.id) then
                        counts[lens.id] = counts[lens.id] + 1
                        columnHas[lens.id] = true
                    end
                end
            end
            for id, _ in pairs(columnHas) do
                creatureCounts[id] = creatureCounts[id] + 1
            end
        end
        return counts, creatureCounts
    end
    local m_lensTabs = {}
    local function RefreshLensBar(columns)
        local creatureCounts
        m_lensCounts, creatureCounts = LensCountsFromColumns(columns)
        local lens = OverviewLensInfo(g_overviewLens)
        for _, tab in ipairs(m_lensTabs) do
            local id = tab.data.lensid
            local count = m_lensCounts[id] or 0
            tab:FireEventTree("setLensState", string.format("%s (%d)", OverviewLensInfo(id).name, count), id == lens.id, count == 0 and id ~= "all", creatureCounts[id] or 0)
        end
        local empty = lens.id ~= "all" and (m_lensCounts[lens.id] or 0) == 0
        if empty then
            m_lensEmptyLabel.text = string.format("No %s abilities in this selection", string.lower(lens.name))
        end
        m_lensEmptyLabel:SetClass("collapsed", not empty)
        local everyone = EveryoneCanText(columns, lens.id)
        m_lensEveryoneLabel.text = everyone or ""
        m_lensEveryoneLabel:SetClass("collapsed", everyone == nil)
        --Field test 8: these lines sit directly beneath the ACTIVE tab
        --(left edges aligned; the label wraps in the remaining width).
        --CENTRED under the active tab: keep the label full row width and
        --shift its rendering by x (layout untouched; numeric widths only -
        --a %-width child of the auto-width bar collapses to one character
        --per line, seen live).
        local rowWidth = 6 * 106 + 8
        local index = OverviewLensIndex(g_overviewLens)
        local offset = (index - 0.5) * 106 + 4 - rowWidth / 2
        for _, label in ipairs({ m_lensEveryoneLabel, m_lensEmptyLabel }) do
            label.selfStyle.width = rowWidth
            label.selfStyle.x = offset
            label.selfStyle.lmargin = 0
            label.selfStyle.textAlignment = "center"
            label.selfStyle.halign = "center"
        end
    end
    --Set by the unique-menu branch; a lens change re-populates through it.
    local m_relens = nil
    local function SetLens(id)
        if OverviewLensInfo(id).id == g_overviewLens then
            return
        end
        g_overviewLens = OverviewLensInfo(id).id
        audio.FireSoundEvent("Mouse.Click")
        if m_relens ~= nil then
            m_relens()
        end
    end
    --Field test 4 redesign: no box, no arrows, no dropdown - one quiet row
    --of lens tabs in the flat minimalist style of the icon rail. Every tab
    --is a plain panel (the chips' own construction, proven with real
    --clicks); the active tab is gold with an underline, zero-count tabs dim
    --but stay pressable (their empty state explains itself). The old cycle
    --arrows closed the menu for real mouse clicks and the dropdown died with
    --it, so both are gone; hotkeys (X4) can return cycling later.
    for _, lens in ipairs(OVERVIEW_LENSES) do
        local id = lens.id
        local underline = gui.Panel {
            classes = { "overviewLensTabLine", "hidden" },
            interactable = false,
        }
        local label = gui.Label {
            classes = { "overviewLensTabLabel" },
            text = lens.name,
            interactable = false,
        }
        local tab = gui.Panel {
            classes = { "overviewLensTab" },
            bgimage = "panels/square.png",
            --Field test 8 ROOT CAUSE of "changing lens closes the menu":
            --real input presses BUBBLE to every ancestor (engine default),
            --and the Unique drawer is an ancestor of the menu, so the same
            --click also toggled the drawer - twice, with the same-frame
            --reopen swallowed by the shownMenuTime guard, leaving the menu
            --closed. FireEvent("press") never bubbles, which is why every
            --synthetic test passed. swallowPress stops the bubble here.
            swallowPress = true,
            data = { lensid = id, tooltip = nil },
            flow = "vertical",
            label,
            underline,
            hover = function(element)
                if element.data.tooltip ~= nil then
                    --valign top: below the cursor the tooltip covered the
                    --chips and the neighbouring tabs (field test 8).
                    gui.Tooltip{ text = element.data.tooltip, valign = "top" }(element)
                end
            end,
            press = function(element)
                SetLens(id)
            end,
            setLensState = function(element, text, active, zero, creatureCount)
                label.text = text
                element:SetClass("active", active)
                element:SetClass("zero", zero)
                underline:SetClass("hidden", not active)
                --Field test 8 copy (Ricky's wording).
                if id == "all" then
                    element.data.tooltip = string.format("Shows every creature (%d creature%s)", creatureCount or 0, creatureCount == 1 and "" or "s")
                else
                    element.data.tooltip = string.format("Shows only creatures with %s abilities (%d creature%s)", lens.name, creatureCount or 0, creatureCount == 1 and "" or "s")
                end
            end,
        }
        m_lensTabs[#m_lensTabs + 1] = tab
    end
    local lensTabRow = gui.Panel {
        classes = { "overviewLensRow" },
        swallowPress = true,
        children = m_lensTabs,
    }
    m_lensBar = gui.Panel {
        classes = { "overviewLensBar", "collapsed" },
        lensTabRow,
        m_lensEmptyLabel,
        m_lensEveryoneLabel,
    }

    --Slice (e): back out of any armed owner-selection prompt (Esc, click-away
    --and menu switches all land here). Cheap no-op when none is armed.
    local function DisarmOverviewPrompts()
        for _, submenu in ipairs(m_uniqueColumns) do
            submenu:FireEvent("armOwnerPrompt", nil)
        end
    end

    --Populate the pooled overview columns from the current selection and
    --the live initiative queue. Returns the column list and how many have a
    --non-empty kit. Shared by the "unique" menu open and by refreshOverview
    --(after a take-turn press) so the acted/fresh state, representative and
    --take-turn buttons all follow the queue.
    local function PopulateUniqueColumns()
        local columns = BuildOverviewColumns()

        --Field test 9: flag the HIGH DAMAGE DEALER(s) - the column whose kit
        --carries the selection's best tier-2 damage, AND (separately) the
        --best among columns already at red death risk, so when several are
        --dying the Director knows which one to burn for damage first.
        local maxDamage, redMaxDamage = 0, 0
        for _, column in ipairs(columns) do
            local best = 0
            for _, ability in ipairs(column.abilities or {}) do
                local facets = OverviewAbilityFacets(ability)
                if facets.damageValue > best then
                    best = facets.damageValue
                end
            end
            column.bestDamage = best
            column.anyRed = false
            local signals = OverviewColumnSignals(column)
            for _, member in ipairs(signals.members) do
                if member.risk ~= nil and member.risk.level == "red" then
                    column.anyRed = true
                end
            end
            if best > maxDamage then
                maxDamage = best
            end
            if column.anyRed and best > redMaxDamage then
                redMaxDamage = best
            end
        end
        for _, column in ipairs(columns) do
            column.highDamage = column.bestDamage > 0
                and (column.bestDamage == maxDamage or (column.anyRed and column.bestDamage == redMaxDamage))
            --Field test 10: chip-level DMG badge thresholds (same numbers,
            --checked per ability in the column populate).
            column.dmgMax = maxDamage > 0 and maxDamage or nil
            column.dmgRedMax = redMaxDamage > 0 and redMaxDamage or nil
        end

        local populated = 0
        for i, column in ipairs(columns) do
            m_uniqueColumns[i] = m_uniqueColumns[i] or ActionSubMenu {}
            local submenu = m_uniqueColumns[i]
            --The column record rides along so the footer bar can show the
            --portrait/name/signals, the take-turn button and the owner
            --prompt, and the column can grey itself when every member has
            --acted (slices (d)/(e)).
            submenu:FireEvent("setCasterToken", column.token, column)
            submenu:FireEventTree("abilities", column.abilities, column.label)
            if #column.abilities > 0 then
                populated = populated + 1
            end
        end
        --Any pooled column beyond this selection's count stays parented but
        --collapsed (and unbound).
        for i = #columns + 1, #m_uniqueColumns do
            m_uniqueColumns[i]:FireEvent("setCasterToken", nil, nil)
            m_uniqueColumns[i]:FireEventTree("abilities", nil, "")
        end
        return columns, populated
    end


    resultPanel = gui.Panel {
        styles = Styles.ActionMenu,
        classes = { "actionMenu", "hidden" },
        floating = true,
        flow = "vertical",
        width = "auto",
        height = "auto",
        --wrap = true,
        halign = "center",
        valign = "bottom",
        y = -50,
        bgimage = true,
        bgcolor = "clear",

        g_manualSetResourcePanel,

        --casterToken is optional: an AbilityHeading with an args.casterToken
        --override passes its owner so the card renders for that token; every
        --other caller omits it and gets the bar's bound token as before.
        showability = function(element, ability, casterToken)
            element:FireEvent("dehover")
            local result = CharacterPanel.DisplayAbility(casterToken or g_token, ability)
            if result then
                m_showingAbility = ability
            end
        end,

        hideability = function(element, ability)
            if m_showingAbility == ability or (m_showingAbility and ability and m_showingAbility.typeName == "ActiveTrigger" and ability.typeName == "ActiveTrigger" and m_showingAbility.id == ability.id) then
                CharacterPanel.HideAbility(m_showingAbility)
                m_showingAbility = false
            end
        end,

        oncast = function(element)
            m_showingAbility = false
        end,

        hover = function(element)
        end,

        dehover = function(element)
            if m_showingAbility then
                --destroy fires this during RebuildGameHud, when the
                --CharacterPanel module can be mid-reload and HideAbility
                --briefly nil (seen live: reload while a hover card was up).
                --The card dies with the HUD anyway; never let the guard
                --crash the rebuild.
                if CharacterPanel ~= nil and CharacterPanel.HideAbility ~= nil then
                    CharacterPanel.HideAbility(m_showingAbility)
                end
                m_showingAbility = false
            end
        end,

        destroy = function(element)
            element:FireEvent("dehover")
            ClearAcknowledgedNovelAbilities()
        end,

        closemenu = function(element, reason)
            --Matches the drawer: the Unique Abilities menu rides out a
            --primary-token change in overview mode (F2-8); only its prompts
            --are disarmed, since the columns are about to repopulate.
            if reason == "primary" and m_args ~= nil and m_args.type == "unique" and InOverviewMode() and not element:HasClass("hidden") then
                DisarmOverviewPrompts()
                return
            end
            g_triggerPanel:SetClass("hidden", false)
            ClearAcknowledgedNovelAbilities()
            DisarmOverviewPrompts()
        end,

        --Slice (e): re-read the queue into the open Unique Abilities menu
        --(after a take-turn press). No-op unless that menu is up.
        refreshOverview = function(element)
            if element:HasClass("hidden") or m_args == nil or m_args.type ~= "unique" then
                return
            end
            local columns = PopulateUniqueColumns()
            RefreshLensBar(columns)
        end,

        menu = function(element, args)
            if element.data.shownMenuTime == dmhub.Time() or g_token == nil then
                return
            end

            DisarmOverviewPrompts()

            --Any menu interaction retires the previously acknowledged novel
            --set: those rows have been shown to the player, so they stop being
            --novel for good. Rows are re-marked below if the menu we are about
            --to open has novel abilities of its own. (Headings always get a
            --fresh "ability" event when a menu opens, so nothing goes stale.)
            ClearAcknowledgedNovelAbilities()

            -- Strict-resources hides the manual "Mark Trigger as Used/Unused"
            -- override from players, since it's a way to bypass the action
            -- economy. Directors keep it.
            local strictResources = (not dmhub.isDM) and dmhub.GetSettingValue("strict:resources")
            if args.type ~= "trigger" or strictResources then
                g_manualSetResourcePanel:SetClass("collapsed", args.type ~= "trigger")
                g_manualSetResourcePanel:SetClass("hidden", strictResources)
            else
                g_manualSetResourcePanel:SetClass("collapsed", false)
                g_manualSetResourcePanel:SetClass("hidden", false)

                local resources = g_token.properties:GetResources()[CharacterResource.triggerResourceId] or 0
                local resourcesAvailable = resources -
                    g_token.properties:GetResourceUsage(CharacterResource.triggerResourceId, "round")
                if resourcesAvailable > 0 then
                    g_manualSetResourcePanel.text = "Mark Trigger as Used"
                else
                    g_manualSetResourcePanel.text = "Mark Trigger as Unused"
                end
            end

            element.data.shownMenuTime = dmhub.Time()

            if (not element:HasClass("hidden")) and m_args ~= nil and m_args.drawer == args.drawer then
                element:SetClass("hidden", true)
                element:HaltEventPropagation()
                element:FindParentWithClass("actionBar"):FireEventTree("menuStatus")
                g_triggerPanel:SetClass("hidden", false)
                return
            end

            g_triggerPanel:SetClass("hidden", true)

            if g_abilityController ~= nil then g_abilityController:FireEvent("cancelCasting") end

            --parent to the drawer firing us.
            element:Unparent()
            args.drawer:AddChild(element)

            m_args = args

            --Director multi-monster overview: one column per statblock in
            --the selection, each chip casting for that statblock's
            --representative token (AbilityHeading casterToken override).
            --Nothing here claims a turn; a chip press goes through the
            --ordinary AbilityHeading press path (PushCasterToken +
            --beginCasting).
            if args.type == "unique" then
                local columns, populated = PopulateUniqueColumns()
                --P2-c1: lens bar up, counts from this selection; a lens
                --change re-populates the same columns.
                m_relens = function()
                    local relensed = PopulateUniqueColumns()
                    RefreshLensBar(relensed)
                end
                RefreshLensBar(columns)
                m_lensBar:SetClass("collapsed", false)
                local children = {}
                --EVERY pooled column goes in the list (the ones past this
                --selection's count are collapsed by PopulateUniqueColumns);
                --leaving one out would orphan it - see the pooled-panel rule.
                for _, submenu in ipairs(m_uniqueColumns) do
                    children[#children + 1] = submenu
                end

                if populated == 0 then
                    element:SetClass("hidden", true)
                    element:HaltEventPropagation()
                    element:FindParentWithClass("actionBar"):FireEventTree("menuStatus")
                    return
                end

                element:SetClass("hidden", false)

                --Assigning m_containerPanel.children re-parents: any pooled
                --panel left OUT of the list is orphaned and destroyed by the
                --engine, and the next menu that reaches for it crashes on a
                --dead panel (its .data is nil). The ordinary menu path keeps
                --every pooled submenu in the list and merely collapses the
                --unused ones; do the same here so the two menu kinds can be
                --opened alternately without poisoning each other's pools.
                for _, submenu in pairs(m_submenus) do
                    submenu:SetClass("collapsed", true)
                    children[#children + 1] = submenu
                end
                if m_commonSignatureWrapper ~= nil then
                    m_commonSignatureWrapper:SetClass("collapsed", true)
                    children[#children + 1] = m_commonSignatureWrapper
                end
                if element.data.triggerPanel ~= nil then
                    element.data.triggerPanel:SetClass("collapsed", true)
                    children[#children + 1] = element.data.triggerPanel
                end

                m_containerPanel.children = children

                local actionBar = element:FindParentWithClass("actionBar")
                actionBar:FireEventTree("menuStatus", args)
                actionBar:FireEventTree("refreshNovelAbilities")

                element:SetClassTree("malice", g_token.properties:IsMonster())
                return
            end

            local abilities = {}
            if args.type == "malice" then
                for _, ability in ipairs(g_abilities) do
                    if ability.categorization == "Malice" then
                        abilities[#abilities + 1] = ability
                    end
                end
            elseif args.type == "free" then
                for _, ability in ipairs(g_abilities) do
                    if ability.actionResourceId == "none" and ability.categorization ~= "Malice" and ability.categorization ~= "Move" and ability.categorization ~= "Hidden" and ability.categorization ~= "Trigger" then
                        abilities[#abilities + 1] = ability
                    end
                end
            elseif args.type == "move" then
                for _, ability in ipairs(g_abilities) do
                    if ability.actionResourceId == "none" and ability.categorization == "Move" then
                        abilities[#abilities + 1] = ability
                    end
                end
            elseif args.type == "trigger" then
                for _, ability in ipairs(g_abilities) do
                    if ability.categorization == "Trigger" or ability.categorization == "Villain Action" then
                        abilities[#abilities + 1] = ability
                    end
                end
            elseif args.type == "respite" then
                for _, ability in ipairs(g_abilities) do
                    if ability.actionResourceId == CharacterResource.respiteActivityId and ability.categorization ~= "Hidden" then
                        abilities[#abilities + 1] = ability
                    end
                end
            else
                --Outside of a respite the respite drawer is hidden, so the
                --maneuver drawer hosts respite activities instead. The grouping
                --pass below files them under their own "Respite Activities"
                --heading, so they read as a separate section rather than as
                --maneuvers. The filter matches the respite drawer's own above
                --(everything but "Hidden"), so the same set of abilities shows up
                --either way -- only the host drawer changes.
                local includeRespite = args.type == "maneuver" and (not InRespiteMode())
                for _, ability in ipairs(g_abilities) do
                    local isRespiteActivity = ability.actionResourceId == CharacterResource.respiteActivityId
                    if (ability.actionResourceId == args.resourceid or (args.type == "maneuver" and (ability.actionResourceId == "none" or ability.actionResourceId == CharacterResource.freeManeuverResourceId) and ability.categorization ~= "Malice" and ability.categorization ~= "Move" and ability.categorization ~= "Trigger") or (includeRespite and isRespiteActivity)) and ability.categorization ~= "Hidden" then
                        abilities[#abilities + 1] = ability
                    end
                end
            end

            --Some maneuvers (e.g. Dig) ask to be fully hidden -- rather than
            --greyed out -- when their ability filter is not satisfied. Drop those
            --here so they never appear in the menu while the caster is ineligible.
            --This runs every time the menu opens, so it tracks live state such as
            --the caster's altitude or whether it currently has a burrow speed.
            if #abilities > 0 then
                local visibleAbilities = {}
                for _, ability in ipairs(abilities) do
                    if (not ability:try_get("hideWhenFiltered")) or ability:AbilityFilterFailureMessage(g_token.properties) == nil then
                        visibleAbilities[#visibleAbilities + 1] = ability
                    end
                end
                abilities = visibleAbilities
            end

            local triggers = {}
            if args.type == "trigger" then
                triggers = g_token.properties:GetTriggeredActions()
            end

            if #abilities == 0 and #triggers == 0 then
                element:SetClass("hidden", true)
                element:HaltEventPropagation()
                element:FindParentWithClass("actionBar"):FireEventTree("menuStatus")
                return
            end

            element:SetClass("hidden", false)

            --This drawer is opening, so its corner marker has done its job.
            --Hand its novel abilities over to the rows below, which pick them
            --up in the "ability" events fired when the submenus populate.
            AcknowledgeNovelAbilities(g_token.charid, args.type)

            local abilitiesByGrouping = {}

            for _, ability in ipairs(abilities) do
                local grouping = GameSystem.GetAbilityCategoryInfo(ability.categorization).grouping or "Abilities"
                if g_token.properties.typeName == "monster" and grouping == "Heroic Abilities" then
                    grouping = "Abilities"
                end
                if grouping == "Common Abilities" and ability.actionResourceId == CharacterResource.freeManeuverResourceId then
                    grouping = "Free Maneuvers"
                end
                if grouping == "Common Abilities" and ability.actionResourceId == "none" then
                    grouping = "No Action Required"
                end
                if ability.actionResourceId == CharacterResource.respiteActivityId then
                    grouping = "Respite Activities"
                end
                abilitiesByGrouping[grouping] = abilitiesByGrouping[grouping] or {}
                abilitiesByGrouping[grouping][#abilitiesByGrouping[grouping] + 1] = ability
            end

            for catid, abilities in pairs(abilitiesByGrouping) do
                if catid ~= "Abilities" and catid ~= "Signature Abilities" then
                    m_submenus[catid] = m_submenus[catid] or ActionSubMenu {}
                end
            end

            local children = {}
            for grouping, submenu in pairs(m_submenus) do
                submenu:FireEventTree("abilities", abilitiesByGrouping[grouping], grouping)
                submenu.data.ord = GameSystem.ActionBarGroupings[grouping] or 1000
                children[#children + 1] = submenu
            end

            table.sort(children, function(a, b)
                return a.data.ord < b.data.ord
            end)

            -- Stack Abilities on top of Signature Abilities in one column
            if m_commonSignatureWrapper == nil then
                m_abilitiesSubmenu = ActionSubMenu {}
                m_signatureSubmenu = ActionSubMenu {}
                m_spacer = gui.Panel {
                    width = 205,
                    height = 16,
                    bgimage = true,
                    bgcolor = "clear",
                }
                m_commonSignatureWrapper = gui.Panel {
                    flow = "vertical",
                    width = "auto",
                    height = "auto",
                    valign = "bottom",
                }
                m_commonSignatureWrapper.children = { m_abilitiesSubmenu, m_spacer, m_signatureSubmenu }
            end
            m_abilitiesSubmenu:FireEventTree("abilities", abilitiesByGrouping["Abilities"], "Abilities")
            m_signatureSubmenu:FireEventTree("abilities", abilitiesByGrouping["Signature Abilities"], "Signature Abilities")
            m_spacer:SetClass("collapsed", abilitiesByGrouping["Signature Abilities"] == nil)
            --The overview ("unique") branch parks this wrapper collapsed; the
            --two submenus inside re-open themselves on their "abilities"
            --event but the wrapper is a plain panel and does not, so it must
            --be re-opened here or a single-token Main Action menu opened after
            --any overview menu loses its Abilities / Signature Abilities
            --column (field test F2-2).
            m_commonSignatureWrapper:SetClass("collapsed", false)

            local wrapperOrd = GameSystem.ActionBarGroupings["Signature Abilities"] or 1000
            local inserted = false
            local result = {}
            for _, child in ipairs(children) do
                if not inserted and wrapperOrd < child.data.ord then
                    result[#result + 1] = m_commonSignatureWrapper
                    inserted = true
                end
                result[#result + 1] = child
            end
            if not inserted then
                result[#result + 1] = m_commonSignatureWrapper
            end
            children = result

            if element.data.triggerPanel == nil then
                element.data.triggerPanel = PowerRollTriggersSubmenu()
            end
            children[#children+1] = element.data.triggerPanel

            if args.type == "trigger" then
                element.data.triggerPanel:FireEventTree("triggers", triggers)
            else
                element.data.triggerPanel:SetClass("collapsed", true)
            end

            --Keep the overview's pooled columns parented (collapsed) so an
            --ordinary menu opened after a Unique Abilities menu does not
            --destroy them. Mirror of the same rule in the "unique" branch.
            for _, submenu in ipairs(m_uniqueColumns) do
                submenu:SetClass("collapsed", true)
                children[#children + 1] = submenu
            end
            m_lensBar:SetClass("collapsed", true)

            m_containerPanel.children = children

            local actionBar = element:FindParentWithClass("actionBar")
            actionBar:FireEventTree("menuStatus", args)
            --Drop this drawer's corner marker now that its menu is up.
            actionBar:FireEventTree("refreshNovelAbilities")

            if g_token.properties:IsMonster() then
                element:SetClassTree("malice", true)
            else
                element:SetClassTree("malice", false)
            end
        end,

        m_lensBar,
        m_containerPanel,
        g_manualSetResourcePanel,
    }

    return resultPanel
end

-- Check if an ability deals damage (has Strike keyword, damage behavior, or power roll tiers with damage).
local function AbilityDoesDamage(ability)
    if ability:HasKeyword("Strike") then
        return true
    end

    for _, behavior in ipairs(ability.behaviors) do
        if behavior.typeName == "ActivatedAbilityDamageBehavior" then
            return true
        end
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            for _, entry in ipairs(behavior.tiers) do
                if regex.MatchGroups(entry, " damage") ~= nil then
                    return true
                end
            end
        end
    end

    return false
end

-- Determine arrow color based on the ability and the relationship between caster and target.
-- Red = abilities that deal damage, Green = ally-targeting non-damage abilities, Black = other.
local function GetArrowColor(ability, sourceToken, targetToken)
    if ability == nil or sourceToken == nil or targetToken == nil then
        return "red"
    end

    if AbilityDoesDamage(ability) then
        return "red"
    end

    -- Non-damage ability targeting a friend = green.
    local isFriend = sourceToken:IsFriend(targetToken)
    if isFriend then
        return "green"
    end

    return "black"
end

-- For arrow greying: returns the smaller of the ability range and any active
-- per-creature line-of-effect cap on either token (e.g. Dazzled). LoE limits
-- are stored as a square count, so they're scaled to dmhub units to match
-- range. Returns nil only if range is also nil.
--
-- Draw Steel uses "free diagonals" -- Chebyshev distance in 3D, where the
-- distance between two points is max(|dx|, |dy|, |dz|). So altitude separation
-- by itself does not eat into horizontal reach; it only matters when it alone
-- exceeds the range, at which point the target is out of range entirely
-- regardless of horizontal distance. Return 0 in that case so the arrow greys
-- fully.
local function EffectiveArrowRange(sourceToken, targetToken, range)
    local function loeUnits(tok)
        if tok == nil or tok.properties == nil then return nil end
        local limit = tok.properties:CalculateNamedCustomAttribute("Line Of Effect Limit") or 0
        if limit <= 0 then return nil end
        return limit * dmhub.unitsPerSquare
    end
    local effective = range
    local sourceUnits = loeUnits(sourceToken)
    local targetUnits = loeUnits(targetToken)
    if sourceUnits ~= nil and (effective == nil or sourceUnits < effective) then
        effective = sourceUnits
    end
    if targetUnits ~= nil and (effective == nil or targetUnits < effective) then
        effective = targetUnits
    end
    if effective ~= nil and sourceToken ~= nil and targetToken ~= nil then
        local altDiffUnits = math.abs(sourceToken.altitude - targetToken.altitude) * dmhub.unitsPerSquare
        if altDiffUnits >= effective + dmhub.unitsPerSquare then
            effective = 0
        end
    end
    return effective
end

local function AddModifierLabelsToMarker(markers, sourceToken, targetToken, ability, range)
    if markers == nil or ability == nil or sourceToken == nil or targetToken == nil then
        return
    end

    local pierceWalls = sourceToken.properties:GetPierceWalls()
    if sourceToken:GetLineOfSight(targetToken, pierceWalls) == 0 then
        markers:AddLabel("No Line of Sight", "forbidden")
        return
    end

    -- Per-creature line-of-effect cap (e.g. the Dazzled condition's "line of
    -- effect only within 1 square"). Fires for either token, since LoE is
    -- mutual: a Dazzled caster can't reach distant targets, and distant
    -- attackers can't reach a Dazzled target.
    local function loeLimit(tok)
        if tok == nil or tok.properties == nil then return 0 end
        return tok.properties:CalculateNamedCustomAttribute("Line Of Effect Limit") or 0
    end
    local sourceLoeLimit = loeLimit(sourceToken)
    local targetLoeLimit = loeLimit(targetToken)
    if sourceLoeLimit > 0 or targetLoeLimit > 0 then
        local distSquares = sourceToken:Distance(targetToken) / dmhub.unitsPerSquare
        if (sourceLoeLimit > 0 and distSquares > sourceLoeLimit) or
           (targetLoeLimit > 0 and distSquares > targetLoeLimit) then
            markers:AddLabel("Beyond Line of Effect", "forbidden")
            return
        end
    end

    -- Match the validity check in CalculateSpellTargetFocusing: failReason
    -- fires when distance >= range + unitsPerSquare (i.e. `not (range+1 > d)`).
    -- Draw Steel "free diagonals" makes the 3D distance Chebyshev:
    -- max(horizDist, altDiff). A target on the same floor-plan tile but well
    -- above/below is out of range only when the altitude separation alone
    -- exceeds range; otherwise the horizontal distance is what matters.
    if range ~= nil then
        local horizDist = targetToken:Distance(sourceToken)
        local altDiffUnits = math.abs(sourceToken.altitude - targetToken.altitude) * dmhub.unitsPerSquare
        if math.max(horizDist, altDiffUnits) >= range + dmhub.unitsPerSquare then
            markers:AddLabel("Out of Range", "forbidden")
            return
        end
    end

    local modifiers = sourceToken.properties:DescribeModifiersOnTarget(ability, targetToken)
    printf("LABEL_DEBUG: AddModifierLabelsToMarker called, markers=%s, #modifiers=%d", tostring(markers), #modifiers)
    for _,m in ipairs(modifiers) do
        local modInfo = ActivatedAbilityPowerRollBehavior.s_modificationTypesById[m.modifier.modtype]
        local labelType = "neutral"
        if modInfo ~= nil and (modInfo.value or 0) > 0 then
            labelType = "buff"
        elseif modInfo ~= nil and (modInfo.value or 0) < 0 then
            labelType = "debuff"
        end
        printf("LABEL_DEBUG: AddLabel('%s', '%s') modtype='%s'", m.modifier.name, labelType, tostring(m.modifier.modtype))
        markers:AddLabel(m.modifier.name, labelType)
    end
end

local m_targetLineOfSightRays = {}

local function FreeTargetLineOfSightRays()
    for key, ray in pairs(m_targetLineOfSightRays) do
        ray:DestroyLineOfSight()
    end

    m_targetLineOfSightRays = {}
end

local function SetTargetLineOfSightRayForKey(key, ray)
    if m_targetLineOfSightRays[key] ~= nil then
        m_targetLineOfSightRays[key]:DestroyLineOfSight()
    end

    m_targetLineOfSightRays[key] = ray
end

---@param rays table<{a: Token, b: Token}>[]
---@param ability ActivatedAbility|nil
---@param range number|nil
local function ReplaceTargetLineOfSightRays(rays, ability, range)
    local t = {}
    for i, ray in ipairs(rays) do
        local key = string.format("%s-%s", ray.a.id, ray.b.id)
        if m_targetLineOfSightRays[key] ~= nil then
            t[key] = m_targetLineOfSightRays[key]
        else
            t[key] = dmhub.MarkLineOfSight(ray.a, ray.b, ray.a.properties:GetPierceWalls(), GetArrowColor(ability, ray.a, ray.b), EffectiveArrowRange(ray.a, ray.b, range))
            AddModifierLabelsToMarker(t[key], ray.a, ray.b, ability, range)
            --Mark player-locked attacker->target pairings so they stand out
            --from the auto-assigned ones.
            if ray.locked then
                t[key]:AddLabel("Locked", "buff")
            end
        end
        m_targetLineOfSightRays[key] = nil
    end

    FreeTargetLineOfSightRays()
    m_targetLineOfSightRays = t
end

local function RemoveLineOfSightRaysTargetingToken(tokenid)
    local destroyKeys = {}
    for key, ray in pairs(m_targetLineOfSightRays) do
        if string.ends_with(key, tokenid) then
            ray:DestroyLineOfSight()
            destroyKeys[#destroyKeys + 1] = key
        end
    end

    for _, key in ipairs(destroyKeys) do
        m_targetLineOfSightRays[key] = nil
    end
end

--objects to mark line of sight.

--- @type nil|LuaTargetingMarkers
local m_markLineOfSight = nil

--- @type nil|CharacterToken
local m_markLineOfSightSourceToken = nil

--- @type nil|CharacterToken
local m_markLineOfSightToken = nil

--if m_markLineOfSight is set, it will be adopted as a persistent marking.
local function AdoptLineOfSightMark()
    if m_markLineOfSight == nil then
        return
    end
    SetTargetLineOfSightRayForKey(string.format("%s-%s", m_markLineOfSightSourceToken.id, m_markLineOfSightToken.id),
        m_markLineOfSight)
    m_markLineOfSight = nil
    m_markLineOfSightToken = nil
    m_markLineOfSightSourceToken = nil
end

local function ClearLineOfSightMark()
    if m_markLineOfSight == nil then
        return
    end

    m_markLineOfSight:Destroy()
    m_markLineOfSight = nil
    m_markLineOfSightToken = nil
    m_markLineOfSightSourceToken = nil
end

-- Casting Triggers.
local m_castingTriggersCache = nil
local m_castingTriggers = nil
local m_castingTriggersOwnerPanel = nil


--- Applies checked improvement params, re-runs CalculateSpellTargeting
--- Rebuilds g_currentCostProposal from scratch so improvement resource costs are included.
--- Each param's registered apply() temporarily patches the ability
local function AppendImprovementCosts(costProposal)
    if g_token == nil or costProposal == nil then return end
    local resourceTable = dmhub.GetTable("characterResources")
    for _, entry in ipairs(m_activeImprovements) do
        if entry.checked then
            local costType = entry.mod:try_get("resourceCostType", "none")
            if costType ~= "none" then
                local looksym = g_token.properties:LookupSymbol{ability = g_currentAbility}
                local costAmt = tonumber(ExecuteGoblinScript(
                    entry.mod:try_get("resourceCostAmount", "1"),
                    looksym, 1)) or 1
                if costAmt > 0 then
                    local resourceId = cond(costType == "epic",
                        CharacterResource.epicResourceId,
                        g_token.properties.resourceid)
                    local resourceInfo = resourceTable[resourceId]
                    if resourceInfo ~= nil then
                        local creature = g_token.properties
                        local max = (resourceInfo.usageLimit == "global")
                            and CharacterResource.GetGlobalResource(resourceId)
                            or (creature:GetResources()[resourceId] or 0)
                        local usage = creature:GetResourceUsage(resourceId, resourceInfo.usageLimit)
                        local available = (max - usage) + resourceInfo:AllowResourceBelowZero(creature)
                        local canAfford = available >= costAmt
                        costProposal.canAfford = costProposal.canAfford and canAfford
                        costProposal.details[#costProposal.details + 1] = {
                            cost = resourceId,
                            quantity = costAmt,
                            canAfford = canAfford,
                            refreshType = resourceInfo.usageLimit,
                            paymentOptions = cond(canAfford,
                                {{resourceid = resourceId, quantity = costAmt}}, {}),
                            expendedOptions = cond(not canAfford,
                                {{resourceid = resourceId, quantity = costAmt}}, {}),
                        }
                    end
                end
            end
        end
    end
end

local ApplyImprovements = function()
    if g_token == nil or g_currentAbility == nil then return end

    -- Rebuild the base cost proposal, then append costs for each checked improvement.
    g_currentCostProposal = g_currentAbility:GetCost(g_token, g_currentSymbols)
    AppendImprovementCosts(g_currentCostProposal)

    -- Reset all improvement bonus fields so each call starts fresh.
    g_currentSymbols.abilityRangeBonus = nil
    g_currentSymbols.abilityRadiusBonus = nil
    g_currentSymbols.numtargetsoverride = nil
    g_currentSymbols._abilityTargetCountBonus = nil

    for _, entry in ipairs(m_activeImprovements) do
        if entry.checked then
            local looksym = g_token.properties:LookupSymbol{ability = g_currentAbility}
            for _, param in ipairs(entry.mod:try_get("params", {})) do
                local info = CharacterModifier.ImprovementParamsById[param.id]
                if info ~= nil and info.accumulate ~= nil and param.value ~= nil and param.value ~= "" then
                    local value = ExecuteGoblinScript(param.value, looksym, 0)
                    if value ~= 0 then
                        info.accumulate(g_currentAbility, value, g_token, g_currentSymbols)
                    end
                end
            end
        end
    end

    CalculateSpellTargeting()

    -- Re-fire maphover so point-placed AoE shapes (cube, cone, line, etc.) are
    -- redrawn immediately using the bonus values now in g_currentSymbols.
    if g_abilityController ~= nil then
        local data = g_abilityController.data
        if data.lastHoverLoc ~= nil then
            g_abilityController:FireEvent("maphover", data.lastHoverLoc, data.lastHoverPoint)
        end
    end
end

local ClearCastingTriggers = function()
    if m_castingTriggersOwnerPanel ~= nil and m_castingTriggersOwnerPanel.valid then
        m_castingTriggersOwnerPanel:FireEvent("clearCastingTriggers")
    end
    if m_castingTriggers == nil then
        return
    end

    for _, trigger in ipairs(m_castingTriggers) do
        local controllingToken = dmhub.GetTokenById(trigger.charid)
        if controllingToken ~= nil then
            controllingToken:ModifyProperties {
                description = "Clear casting trigger",
                undoable = false,
                execute = function()
                    controllingToken.properties:ClearAvailableTrigger(trigger)
                end,
            }
        end
    end

    m_castingTriggers = nil
end




--guards against a single physical click on stacked object tokens (wall voxel
--columns) being dispatched once per overlapping token: {time, key}, where key
--identifies the tile and time is the frame timestamp of the last object add.
local m_objectClickGuard = nil

local function CreateTargetInfo(spell)
    local targetInfo = {
        type = string.lower(spell.typeName),
        guid = dmhub.GenerateGuid(),
        action = spell,
        execute = function(targetToken, info) --info has {targetEffect = {list of effect panels}}
            -- Squad coordinated strike: clicking a squad minion arms a lock for
            -- that minion (click again to disarm); the next enemy click locks
            -- the pair, making that minion the creature's main attacker.
            -- Clicking a target with no minion armed is normal, auto-assigned
            -- targeting (falls through below).
            if SquadStrikeActive() then
                if SquadIsActiveMinionToken(targetToken) then
                    if g_squadPendingLockMinion ~= nil and g_squadPendingLockMinion.id == targetToken.id then
                        g_squadPendingLockMinion = nil
                    else
                        g_squadPendingLockMinion = targetToken
                    end
                    CalculateSpellTargeting()
                    return
                elseif g_squadPendingLockMinion ~= nil then
                    local locksOnTarget = ActivatedAbility.LockSquadTargetingPair(g_squadPendingLockMinion, targetToken)
                    g_squadPendingLockMinion = nil

                    --Adopt the hover preview arrow (drawn from the armed
                    --minion, with its Locked label) as the persistent ray for
                    --this pairing so it doesn't flicker on recompute.
                    AdoptLineOfSightMark()

                    -- Make sure the creature has a target slot for each lock
                    -- aimed at it.
                    local slots = 0
                    for _, id in ipairs(g_targetsChosen) do
                        if id == targetToken.id then
                            slots = slots + 1
                        end
                    end
                    while slots < locksOnTarget do
                        g_targetsChosen[#g_targetsChosen + 1] = targetToken.id
                        if g_firstTarget == nil then
                            g_firstTarget = targetToken.id
                        end
                        slots = slots + 1
                    end

                    CalculateSpellTargeting()
                    return
                end
            end

            -- Stacked object tokens (wall voxel columns): the engine dispatches a
            -- single physical click to EVERY overlapping token's reticule, so one
            -- click on a 2-high wall column arrives here once per cube. Swallow
            -- ALL duplicate dispatches for the same tile within the same frame --
            -- unconditionally, or the duplicate dispatch for a token the first
            -- dispatch just selected would toggle it straight back off. When the
            -- clicked token is unselected, redirect the click to the TOPMOST
            -- not-yet-chosen voxel on the tile (clicking again on a later frame
            -- selects the next cube down, and deselect clicks on a fully-chosen
            -- column fall through to the toggle path). The synthetic deselect
            -- click fired by the over-cap swap below is unaffected: it targets a
            -- tile that was not clicked this frame, so the guard passes it.
            if targetToken.isObject then
                local loc = targetToken.loc
                if loc ~= nil then
                    local clickKey = string.format("%d,%d,%d", loc.x, loc.y, loc.floor)
                    local now = dmhub.Time()
                    if m_objectClickGuard == nil or m_objectClickGuard.time ~= now then
                        m_objectClickGuard = { time = now, keys = {} }
                    end
                    if m_objectClickGuard.keys[clickKey] then
                        return
                    end
                    m_objectClickGuard.keys[clickKey] = true

                    if not list_contains(g_targetsChosen, targetToken.id) then
                        local voxelFloor = game.currentMap:GetFloorFromLoc(loc)
                        local voxels = voxelFloor ~= nil and voxelFloor:GetWallVoxelsAt(loc) or nil
                        if voxels ~= nil and #voxels > 0 then
                            for i = #voxels, 1, -1 do
                                local targetable = voxels[i]:GetComponent("Targetable")
                                if targetable ~= nil and targetable.properties ~= nil then
                                    local voxelToken = dmhub.LookupToken(targetable.properties)
                                    if voxelToken ~= nil and voxelToken.valid and not list_contains(g_targetsChosen, voxelToken.id) then
                                        targetToken = voxelToken
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Strict-targeting: players cannot select invalid targets (out of
            -- range, forbidden, etc). The reticule still lights up with the
            -- invalid styling so they get feedback on why, but the click is
            -- ignored, and the arrow's reason label flashes red for emphasis.
            -- Directors bypass this.
            if (not dmhub.isDM) and dmhub.GetSettingValue("strict:targeting") then
                if targetToken.sheet ~= nil and targetToken.sheet.data.targetValid == false then
                    if m_markLineOfSight ~= nil and m_markLineOfSightToken == targetToken then
                        m_markLineOfSight:FlashLabels()
                    else
                        local key = string.format("%s-%s", g_token.id, targetToken.id)
                        local ray = m_targetLineOfSightRays[key]
                        if ray ~= nil then
                            ray:FlashLabels()
                        end
                    end
                    return
                end
            end

            local exists = list_contains(g_targetsChosen, targetToken.id)

            for i, effect in ipairs(info.targetEffect or {}) do
                effect:SetClass('target-selected', true)
                effect:SetClass('two', false)
                effect:SetClass('three', false)
            end
            if not exists then
                -- Enforce the target cap at selection time. Normally reaching the
                -- cap auto-casts so this is unreachable, but abilities with a
                -- promptOverride (e.g. invoked manipulate_targets picks) wait for
                -- an explicit Confirm instead of auto-casting, so extra clicks
                -- land here: swap out the most recent selection by re-dispatching
                -- a click on it (which runs the deselect path and clears its
                -- styling), keeping the selection within the cap.
                local maxTargets = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                print("TARGET:: add", targetToken.id, "ability =", g_currentAbility.name, "chosen =", #g_targetsChosen, "max =", tostring(maxTargets), "(", type(maxTargets), ")")
                if type(maxTargets) == "number" and maxTargets >= 1 and #g_targetsChosen >= maxTargets then
                    print("TARGET:: at capacity; swapping out most recent selection")
                    local lastId = g_targetsChosen[#g_targetsChosen]
                    local lastToken = dmhub.GetTokenById(lastId)
                    if lastToken ~= nil and lastToken.valid and lastToken.sheet ~= nil then
                        lastToken.sheet:FireEvent("tokenClick")
                    end
                    while #g_targetsChosen >= maxTargets do
                        table.remove(g_targetsChosen)
                    end
                    if g_firstTarget ~= nil and not list_contains(g_targetsChosen, g_firstTarget) then
                        g_firstTarget = g_targetsChosen[1]
                    end
                end

                g_targetsChosen[#g_targetsChosen + 1] = targetToken.id
                g_manualTargetChosen = true
                if g_firstTarget == nil then
                    g_firstTarget = targetToken.id
                end

                AdoptLineOfSightMark()
            else
                if spell:CanTargetAdditionalTimes(g_token, g_currentSymbols, g_targetsChosen, targetToken) then
                    g_targetsChosen[#g_targetsChosen + 1] = targetToken.id
                    g_manualTargetChosen = true
                    local ntargets = 0
                    for _, tokenid in ipairs(g_targetsChosen) do
                        if tokenid == targetToken.id then
                            ntargets = ntargets + 1
                        end
                    end

                    for i, effect in ipairs(info.targetEffect or {}) do
                        effect:SetClass('two', ntargets >= 2)
                        effect:SetClass('three', ntargets >= 3)
                    end
                else
                    RemoveLineOfSightRaysTargetingToken(targetToken.id)
                    local newTargetsChosen = {}
                    for _, tokenid in ipairs(g_targetsChosen) do
                        if tokenid ~= targetToken.id then
                            newTargetsChosen[#newTargetsChosen + 1] = tokenid
                        end
                    end
                    g_targetsChosen = newTargetsChosen

                    if g_firstTarget == targetToken.id then
                        g_firstTarget = g_targetsChosen[1]
                    end
                    for i, effect in ipairs(info.targetEffect or {}) do
                        effect:SetClass('target-selected', false)
                    end
                end
            end

            CalculateSpellTargeting()
        end,
    }

    return targetInfo
end

--functionality to mark radiuses.
local g_radiusMarkers = {}

--Strict movement: the exact set of legal forced-move destination tiles, captured from
--the SAME data the forced-move movement radius is drawn from (g_token:CalculateMovementPerimeter
--with the identical args passed to MarkMovementRadius). Keyed by loc.xyfloorOnly.str. nil when
--no forced-move (straightline) targeting is active. Used to confine targeting to the drawn tiles.
local g_forcedMoveLegalLocs = nil

--One-shot guard so the "needs a C# build" warning prints at most once per session.
local g_warnedPerimeterMissing = false

local AddCustomAreaMarker = function(locs, color)
    g_radiusMarkers[#g_radiusMarkers + 1] = dmhub.MarkLocs {
        locs = locs,
        color = color,
    }
end

local AddRadiusMarker = function(locOverride, radius, color, filterFunction)
    --An effectively-unlimited range (the content convention is 999, e.g. the
    --invoked "Forced Free Strike"/"Forced Signature Ability" helpers) would
    --mark every tile on the map. On a large or void map the CalculateShape
    --call, the per-loc Lua filter loop, and MarkLocs below then run over
    --millions of tiles and freeze the app for tens of seconds ("Codex.exe is
    --not responding") the moment the prompt arms. The ring would cover
    --everything anyway, so draw nothing for such ranges.
    if radius ~= nil and radius > 100 * dmhub.unitsPerSquare then
        print(string.format("MovementRadius:: SKIP radius marker for effectively-unlimited radius %s", tostring(radius)))
        return
    end

    local tokenCasting = g_token
    if g_currentAbility ~= nil then
        tokenCasting = g_currentAbility:GetRangeSource(g_token)
    end


    local locs = tokenCasting.locsOccupying

    if locOverride ~= nil then
        if type(locOverride) == "table" then
            locs = locOverride
        else
            locs = { locOverride }
        end
    end


    local shape = dmhub.CalculateShape {
        shape = "radiusfromcreature",
        token = tokenCasting,
        radius = radius,
        locOverride = locs,
    }

    local locs = shape.locations
    if filterFunction ~= nil then
        local newLocs = {}
        for _, loc in ipairs(locs) do
            if filterFunction(loc) then
                newLocs[#newLocs + 1] = loc
            end
        end

        locs = newLocs
    end

    g_radiusMarkers[#g_radiusMarkers + 1] = dmhub.MarkLocs {
        locs = locs,
        color = color,
    }
end

local function ClearRadiusMarkers()
    for i, marker in ipairs(g_radiusMarkers) do
        marker:Destroy()
    end

    g_radiusMarkers = {}
    g_forcedMoveLegalLocs = nil
end

--Distance in tiles from the casting token to a tile (min over the squares the
--token occupies, so size > 1 tokens measure from their nearest edge). Used to
--slice tiered targeting rings into annuli.
local function DistanceFromCasterInTiles(loc)
    local tokenCasting = g_token
    if g_currentAbility ~= nil then
        tokenCasting = g_currentAbility:GetRangeSource(g_token)
    end

    local best = nil
    for _, occLoc in ipairs(tokenCasting.locsOccupying) do
        local dist = occLoc:DistanceInTiles(loc)
        if best == nil or dist < best then
            best = dist
        end
    end

    return best or 0
end

--Strict movement: capture the EXACT legal forced-move destination tiles into
--g_forcedMoveLegalLocs (keyed by loc.xyfloorOnly.str), using the SAME range + args
--passed to MarkMovementRadius. CalculateMovementPerimeter runs the identical engine
--computation that draws the radius, so the legal set and the highlighted radius can
--never disagree -- no separate/duplicated targeting algorithm. Call this right after
--each forced-move MarkMovementRadius draw so the set stays in sync (including the
--multi-step waypoint re-draw). pcall-guarded: if the engine method is missing (Lua
--reloaded before the C# build), leave the set nil and fall open instead of erroring.
local function CaptureForcedMoveLegalLocs(token, range, radiusArgs)
    local ok, perim = pcall(function() return token:CalculateMovementPerimeter(range, radiusArgs) end)
    if ok and type(perim) == "table" then
        local set = {}
        for _, perimLoc in ipairs(perim) do
            set[perimLoc.xyfloorOnly.str] = true
        end
        g_forcedMoveLegalLocs = set
    else
        g_forcedMoveLegalLocs = nil
        if not ok and not g_warnedPerimeterMissing then
            g_warnedPerimeterMissing = true
            print("[STRICTMOVE] CalculateMovementPerimeter unavailable (needs a C# build); forced-move enforcement is OFF until the engine is rebuilt.")
        end
    end
end


local g_currentCostProposal = nil

local g_targetInfo = nil

local function RemoveTokenTargeting()
    if g_targetInfo == nil then
        return
    end

    for _, token in ipairs(dmhub.allTokensIncludingObjects) do
        if token.valid and token.sheet ~= nil and token.sheet.data.targetInfo == g_targetInfo then
            token.sheet:FireEvent("untarget")
            token.sheet.data.targetInfo = nil
        end
    end

    g_targetInfo = nil
end


--- True when strict forced-movement enforcement should currently apply. The
--- "Strictly Enforce Forced Movement Rules" game setting must be on, and the actor must be
--- a PLAYER -- OR a GM who is currently viewing the world as a player (Show Token
--- Vision, or logged in as a token). Plain GM view is exempt, matching
--- strict:resources / strict:targeting. The token-vision/logged-in-as cases let the
--- rules be exercised and tested from the player's perspective.
--- @return boolean
local function ForcedMoveEnforcementActive()
    if not dmhub.GetSettingValue("strict:movement") then
        return false
    end
    if not dmhub.isDM then
        return true
    end
    return dmhub.tokenVision ~= nil or dmhub.tokensLoggedInAs ~= nil
end

--- Strict movement enforcement for forced movement (push/pull/slide/knockback).
--- Returns true when enforcement is active (see ForcedMoveEnforcementActive) and `loc`
--- is NOT one of the tiles the forced-move movement radius highlights. The legal-tile
--- set (g_forcedMoveLegalLocs) is captured from the exact same engine computation that
--- draws the radius, so "what you can target" matches "what is highlighted" tile-for-tile.
--- When the caller rejects a loc it suppresses the preview arrow / "Click to Confirm"
--- text and ignores the click. If the legal set is unavailable (forced-move radius not
--- computed, or the engine method is missing pre-build) we fall OPEN -- do not constrain --
--- so targeting keeps working rather than blocking everything.
--- @param loc nil|Loc
--- @return boolean
local function ForcedMoveLocRejected(loc)
    if not ForcedMoveEnforcementActive() then
        return false
    end
    if g_forcedMoveLegalLocs == nil then
        return false
    end
    if loc == nil then
        return true
    end
    return g_forcedMoveLegalLocs[loc.xyfloorOnly.str] ~= true
end


local g_castingEmoteSet = nil

local g_castButton
local g_skipButton
local g_castMessage
local g_castMessageContainer
local g_tokenSelectionContainer

local g_castModesPanel
local g_forcedMovementTypePanel

--- Panel that hosts all registered DrawSteelActionBar cast controls (e.g. Acolyte's Invoke toggle).
--- @type nil|Panel
local g_castControlsPanel = nil

--- Per-cast state shared between a cast control's render/onCommit/onResolve callbacks.
--- Reset on each beginCasting. Each control may mutate this freely.
--- @type table
local g_castControlState = {}

--- The cast controls (filtered to those whose appliesTo returns true) that are active
--- for the currently-targeting ability. Captured at beginCasting and consumed by
--- onCommit/onResolve at the right lifecycle points so registration changes mid-cast
--- can't desync the lifecycle.
--- @type DrawSteelActionBarCastControl[]
local g_activeCastControls = {}


--- @type nil|function
local m_allowedAltitudeCalculator

--- Which altitude-control flavor is active.
---  nil        = controller is collapsed (no altitude control needed)
---  "movement" = forced-movement targeting; uses m_allowedAltitudeCalculator for min/max
---  "cube"     = cube AoE; default is "On Ground" (track hovered tile altitude), or a fixed altitude
--- @type nil|string
local m_altitudeMode

local m_altitudeController
local m_shiftController

local g_ammoChoicePanel = nil
local g_synthesizedSpellsPanel = nil
local g_castChargesInput = nil

local g_shifting = true

local function CreateShiftController()


    local m_label = gui.Label {
        fontSize = 14,
        width = "auto",
        height = "auto",
        text = "You are shifting. You can choose to move normally instead.",
        vmargin = 2,
    }

    local resultPanel
    local slider = gui.EnumeratedSliderControl {
        styles = ThemeEngine.GetStyles(),
        halign = "center",
        width = 180,
        vmargin = 2,
        options = {
            { id = true,  text = "Shifting" },
            { id = false, text = "Not Shifting" },
        },
        value = g_shifting,
        data = {},
        create = function(element)
            element.data.themeListener = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.GetStyles()
                end
            end)
        end,
        destroy = function(element)
            if element.data.themeListener ~= nil then
                element.data.themeListener:Deregister()
                element.data.themeListener = nil
            end
        end,
        beginCasting = function(element)

            if g_token ~= nil and (g_token.properties:CalculateNamedCustomAttribute("Shift Disabled") or 0) > 0 then
                g_currentSymbols.shiftingOverride = false
                element.value = false
                m_label.text = "<color=#ff0000><b>You cannot shift.</b></color> You may move normally instead."
                return
            end

            m_label.text = "You are shifting. You can choose to move normally instead."
            element.value = true
        end,
        change = function(element)
            g_shifting = element.value
            g_currentSymbols.shiftingOverride = g_shifting
            CalculateSpellTargeting()
        end,
    }

    resultPanel = gui.Panel {
        --starts collapsed like the other cast-specific controllers; only the
        --cast flows that detect a shift movement type un-collapse it.
        classes = { "collapsed" },
        halign = "center",
        width = "auto",
        height = "auto",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = Styles.Ability.blurColor,
        blurBackground = true,
        pad = 4,

        m_label,

        slider,
    }

    return resultPanel
end

local function CreateAltitudeController()
    local resultPanel
    resultPanel = gui.Panel {
        classes = { "collapsed" },
        styles = {
            {
                selectors = { "altitudeArrow" },
                bgcolor = "#999999",
                bgimage = "panels/InventoryArrow.png",
            },
            {
                selectors = { "altitudeArrow", "parent:hover" },
                bgcolor = "white",
            },
        },
        data = {
            target = "max",
            currentLocInfo = {},
        },
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        pad = 4,

        enable = function(element)
            element.thinkTime = 0.01
        end,

        disable = function(element)
            element.thinkTime = nil
        end,

        think = function(element)
            if dmhub.modKeys["alt"] then
                local wheel = dmhub.mouseWheel

                if wheel ~= 0 then
                    local alt = element.data.target
                    if type(alt) ~= "number" then
                        --When transitioning from a non-numeric mode ("ground"/"max"/"min") into a fixed
                        --altitude via the mouse wheel, anchor the starting point at the current display
                        --altitude so the first tick steps up/down from the visible value.
                        if m_altitudeMode == "cube" and element.data.currentLocInfo.loc ~= nil then
                            alt = element.data.currentLocInfo.loc.withGroundAltitude.altitude
                        else
                            alt = 0
                        end
                    end

                    if wheel > 0 then
                        alt = alt + 1
                    else
                        alt = alt - 1
                    end

                    if m_altitudeMode == "movement" and element.data.currentLocInfo.loc ~= nil then
                        if m_allowedAltitudeCalculator == nil then return end
                        local minAltitude, maxAltitude = m_allowedAltitudeCalculator(element.data.currentLocInfo.loc)
                        alt = math.clamp(alt, minAltitude, maxAltitude)
                    end

                    m_altitudeController:FireEventTree("setAltitude", alt)
                end

                if element.data.currentLocInfo.loc ~= nil and element.data.currentLocInfo.panel.valid then
                    --update the altitude.
                    element.data.currentLocInfo.panel:FireEvent("maphover", element.data.currentLocInfo.loc,
                        element.data.currentLocInfo.point)
                end
            end
        end,

        loc = function(element, info)
            element.data.currentLocInfo = info
        end,

        setAltitude = function(element, val)
            element.data.target = val
        end,

        gui.Label {
            width = "auto",
            height = "auto",
            color = Styles.textColor,
            hmargin = 4,
            text = "Vertical:",
            fontSize = 18,
        },
        gui.Label {
            width = 80,
            height = 20,
            fontSize = 14,
            valign = "center",
            textAlignment = "center",
            bold = true,
            color = Styles.textColor,
            text = "max",
            setAltitude = function(element, val)
                element.text = val
            end,
            loc = function(element, info)
                if info.loc == nil then
                    return
                end
                local target = m_altitudeController.data.target

                if m_altitudeMode == "cube" then
                    local groundAlt = info.loc.withGroundAltitude.altitude
                    local alt
                    if type(target) == "number" then
                        alt = target
                        element.text = string.format("%d", alt)
                    else
                        alt = groundAlt
                        element.text = string.format("Ground (%d)", alt)
                    end
                    info.loc = info.loc:WithAltitude(alt)
                    return
                end

                if m_allowedAltitudeCalculator == nil then return end
                local minAltitude, maxAltitude = m_allowedAltitudeCalculator(info.loc)
                local alt = info.loc.altitude
                if target == "max" then
                    alt = maxAltitude
                    element.text = string.format("max (%d)", alt)
                elseif target == "min" then
                    alt = minAltitude
                    element.text = string.format("min (%d)", alt)
                elseif type(target) == "number" then
                    alt = math.clamp(target, minAltitude, maxAltitude)
                    if alt == target then
                        element.text = string.format("%d", alt)
                    else
                        element.text = string.format("%d (%d)", alt, target)
                    end
                end

                info.loc = info.loc:WithAltitude(alt)
            end,
        },

        --up/down container
        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",

            --up button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,
                press = function(element)
                    local alt = m_altitudeController.data.target
                    if type(alt) ~= "number" then
                        --In cube mode, seed from the current ground altitude under the cursor so
                        --the first up/down click steps relative to what the user can see.
                        if m_altitudeMode == "cube" and m_altitudeController.data.currentLocInfo.loc ~= nil then
                            alt = m_altitudeController.data.currentLocInfo.loc.withGroundAltitude.altitude
                        else
                            alt = 0
                        end
                    end
                    m_altitudeController:FireEventTree("setAltitude", alt + 1)
                end,
                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = -90,
                },
            },

            --down button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,

                press = function(element)
                    local alt = m_altitudeController.data.target
                    if type(alt) ~= "number" then
                        if m_altitudeMode == "cube" and m_altitudeController.data.currentLocInfo.loc ~= nil then
                            alt = m_altitudeController.data.currentLocInfo.loc.withGroundAltitude.altitude
                        else
                            alt = 0
                        end
                    end
                    m_altitudeController:FireEventTree("setAltitude", alt - 1)
                end,

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = 90,
                },
            },
        },

        --max/min container - only visible in movement (forced-movement) mode.
        gui.Panel {
            classes = { "collapsed" },
            setAltitudeMode = function(element, mode)
                element:SetClass("collapsed", mode ~= "movement")
            end,
            flow = "vertical",
            width = "auto",
            height = "auto",

            --max button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,

                press = function(element)
                    m_altitudeController:FireEventTree("setAltitude",
                        cond(m_altitudeController.data.target == "max", 0, "max"))
                end,

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = -90,
                    y = -4,
                },

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = -90,
                },
            },

            --min button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,

                press = function(element)
                    m_altitudeController:FireEventTree("setAltitude",
                        cond(m_altitudeController.data.target == "min", 0, "min"))
                end,

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = 90,
                    y = 4,
                },

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = 90,
                },
            },

        },

        --Ground toggle - only visible in cube mode. Clicking returns target to "ground".
        gui.Panel {
            classes = { "collapsed" },
            setAltitudeMode = function(element, mode)
                element:SetClass("collapsed", mode ~= "cube")
            end,
            styles = {
                {
                    selectors = { "groundButton" },
                    bgimage = "panels/square.png",
                    bgcolor = "#444444",
                    border = 1,
                    borderColor = "#888888",
                },
                {
                    selectors = { "groundButton", "selected" },
                    bgcolor = "#777733",
                    borderColor = "#ffcc44",
                },
                {
                    selectors = { "groundButton", "hover" },
                    borderColor = "white",
                },
            },
            flow = "horizontal",
            width = "auto",
            height = "auto",
            valign = "center",
            hmargin = 4,

            gui.Label {
                classes = { "groundButton" },
                width = 60,
                height = 22,
                fontSize = 12,
                valign = "center",
                textAlignment = "center",
                color = Styles.textColor,
                text = "Ground",
                pad = 2,
                press = function(element)
                    m_altitudeController:FireEventTree("setAltitude", "ground")
                end,
                setAltitude = function(element, val)
                    element:SetClass("selected", val == "ground")
                end,
            },
        },


    }

    return resultPanel
end

--- Switch the altitude controller into a given mode and reset its UI state when the
--- mode actually changes. Pass nil to collapse it.
--- @param mode nil|string  -- one of nil, "movement", "cube"
--- @param defaultTargetOverride nil|string|number  -- default target to use instead of the mode's standard default (e.g. "min" for teleports)
local function SetAltitudeMode(mode, defaultTargetOverride)
    if m_altitudeMode == mode then
        --Mode unchanged: re-fire setAltitudeMode so any newly-created sub-panels sync,
        --but don't clobber the user's chosen target.
        if m_altitudeController ~= nil then
            m_altitudeController:FireEventTree("setAltitudeMode", mode)
        end
        return
    end

    m_altitudeMode = mode

    if m_altitudeController == nil then return end

    m_altitudeController:SetClass("collapsed", mode == nil)
    m_altitudeController:FireEventTree("setAltitudeMode", mode)

    --Pick a sensible default target when entering a mode.
    local defaultTarget = defaultTargetOverride
    if defaultTarget == nil then
        if mode == "movement" then
            defaultTarget = "max"
        elseif mode == "cube" then
            defaultTarget = "ground"
        end
    end
    if defaultTarget ~= nil then
        m_altitudeController.data.target = defaultTarget
        m_altitudeController:FireEventTree("setAltitude", defaultTarget)
    end
end

---@return table<{loc: table, token: Token}>[]
local function BuildTargetsList()
    --accumulate our target list based on what is selected.
    local targets = {}

    for _, tokenid in ipairs(g_targetsChosen) do
        local token = dmhub.GetTokenById(tokenid)
        if token ~= nil then
            targets[#targets + 1] = { loc = token.loc, token = token }
        end
    end

    return targets
end

local function CreateSynthesizedSpellsPanel()
    local resultPanel

    resultPanel = gui.Panel {
        idprefix = "synthesizeSpellsPanel",
        styles = Styles.ActionMenu,
        classes = { 'collapsed' },
        width = "auto",
        height = "auto",
        maxWidth = 800,
        halign = "center",
        valign = "bottom",
        flow = "horizontal",
        wrap = true,

        data = {
            synthesized = nil
        },

        refreshSpell = function(element, addedSpellOptions)
            if g_currentAbility == nil then
                element:SetClass("collapsed", true)
                return
            end

            local synth = g_currentAbility:SynthesizeAbilities(g_creature)

            --For invoked abilities the upstream bifurcation in GetActivatedAbilities
            --doesn't run, so a dual-keyword (Melee + Ranged) custom ability arrives here
            --as a single entry. Inject both variants into the synth list so the player
            --gets the same melee/ranged chip picker they'd see on the regular action bar.
            --BifurcateIntoMeleeAndRanged is idempotent (returns self with variants attached
            --after first call), so we always call it and read the variants off the result.
            if g_currentAbility:HasKeyword("Melee") and g_currentAbility:HasKeyword("Ranged")
                and not g_currentAbility:try_get("disableSplitIntoMeleeAndRanged", false) then
                local bifurcated = g_currentAbility:BifurcateIntoMeleeAndRanged(g_creature)
                if bifurcated:try_get("meleeAndRanged", false) then
                    --Propagate OnBeginCast/OnFinishCast from the parent so the InvokeAbility
                    --behavior's finishHandler still fires when the player picks a variant.
                    --Without this the parent's wait loop never sees finishedCasting=true and
                    --the echo prompt re-fires endlessly.
                    local parentOnBegin = g_currentAbility:try_get("OnBeginCast")
                    local parentOnFinish = g_currentAbility:try_get("OnFinishCast")
                    if parentOnBegin ~= nil then
                        bifurcated.meleeVariation.OnBeginCast = parentOnBegin
                        bifurcated.rangedVariation.OnBeginCast = parentOnBegin
                    end
                    if parentOnFinish ~= nil then
                        bifurcated.meleeVariation.OnFinishCast = parentOnFinish
                        bifurcated.rangedVariation.OnFinishCast = parentOnFinish
                    end
                    synth = synth or {}
                    synth[#synth+1] = bifurcated.meleeVariation
                    synth[#synth+1] = bifurcated.rangedVariation
                end
            end

            element.data.synthesized = synth
            if synth == nil then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            local children = {}
            for _, a in ipairs(synth) do
                local cast = nil
                if g_currentSymbols ~= nil then
                    cast = g_currentSymbols.cast
                end

                local spellOptions = {
                    synthesized = true,
                    cast = cast,
                    ability = a,
                    --Forward the current symbol table so flags like `forcedroll` (set by
                    --InvokeAbility with inheritRoll=true) survive the chip-pick handoff.
                    symbols = g_currentSymbols,
                }
                for k, v in pairs(addedSpellOptions or {}) do
                    spellOptions[k] = v
                end
                local panel = AbilityHeading(spellOptions)

                children[#children + 1] = panel
            end

            element.children = children
        end,
    }

    return resultPanel
end

local SetTargetsInRadius = function(tokens)
    for k, tok in pairs(tokens) do
        if tok.valid and tok.sheet ~= nil and g_pointForceTargets[tok.id] == nil then
            tok.sheet:FireEvent("targetnoninteractive", {})
        end
    end

    for k, tok in pairs(g_pointForceTargets) do
        if tok.valid and tok.sheet ~= nil and tokens[k] == nil then
            tok.sheet:FireEvent("untarget")
        end
    end

    g_pointForceTargets = tokens
end

local function CreateTokenSelectionContainer()
    local resultPanel
    
    resultPanel = gui.Panel {
        styles = {
            {
                selectors = {"selectable"},
                opacity = 0,
            },
            {
                selectors = {"selectable", "hover"},
                opacity = 1,
            }
        },
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",
        flow = "horizontal",
        bgimage = true,
		cornerRadius = 10,
		bgcolor = "#000000fa",
		borderColor = "#000000fa",
		borderWidth = 10,
		borderFade = true,
        pad = 10,

        maxWidth = 800,
        wrap = true,
        disable = function(element)
            element.mapfocus = false
        end,
        settokens = function(element, tokens)
            if tokens == nil then
                element.mapfocus = false
                element.children = {}
                element:SetClass("collapsed", true)
                return
            end

            local children = {}

            for _,token in ipairs(tokens) do
                local image = gui.CreateTokenImage(token, {
                    width = 64,
                    height = 64,
                    halign = "center",
                    valign = "center",
                })

                local tok = token


                local child = gui.Panel{
                    classes = {"selectable"},
                    width = "auto",
                    height = "auto",
                    bgimage = true,
                    bgcolor = "#ffffff22",
                    borderWidth = 1,
                    borderColor = "white",
                    image,
                    press = function(element)
                        if tok.valid then
                            dmhub.CenterOnToken(tok.charid)
                        end
                    end,
                    linger = function(element)
                        if tok.valid then
                            gui.Tooltip(creature.GetTokenDescription(tok))(element)
                        end
                    end,
                }


                children[#children + 1] = child
            end

            element.children = children
            element:SetClass("collapsed", #children == 0)
            element.mapfocus = #children > 0
        end,
    }

    return resultPanel
end

--- Ensure symbols.cast is populated with an ActivatedAbilityCast. Used by both the
--- cast-control rendering pipeline (so GoblinScript formulas like `Cast.Invoked` resolve
--- during targeting setup -- numTargets, range, prompts, etc.) and by FireCastControlsOnCommit
--- as a fallback for any code path that bypasses rendering. ActivatedAbility:Cast respects
--- an existing options.symbols.cast (see ActivatedAbility.lua:2498-2514), so the cast
--- object created here flows all the way through to ability behaviors.
--- @param ability ActivatedAbility
--- @param symbols table
--- @param targets table[]|nil
--- @return table The cast object now stored at symbols.cast.
local function EnsureSymbolsCast(ability, symbols, targets)
    if symbols.cast == nil then
        symbols.cast = ActivatedAbilityCast.new{
            ability = ability,
            targets = targets or {},
            mode = symbols.mode or 1,
            _tmp_targetArea = symbols.targetArea,
        }
    end
    return symbols.cast
end

--- Invoke onCommit on all active cast controls. Called right before ability:Cast
--- runs, so controls can apply pre-cast effects (self damage, resource adjustments)
--- and populate symbols (e.g. Cast.Invoked) that ability behaviors will read.
--- Must run BEFORE Cast() because Cast() lazily builds options.symbols.cast and
--- begins invoking behaviors; symbol values must be settled by then.
---
--- Controls receive (ability, cast, castState, casterToken, symbols). symbols.cast
--- is guaranteed non-nil (either pre-built at render time, or built here as a fallback).
--- @param ability ActivatedAbility
--- @param symbols table The g_currentSymbols table that will be passed to Cast.
--- @param casterToken CharacterToken
--- @param targets table[] The target list (after PrepareTargets) about to be passed to Cast.
local function FireCastControlsOnCommit(ability, symbols, casterToken, targets)
    local cast = EnsureSymbolsCast(ability, symbols, targets)
    for _,control in ipairs(g_activeCastControls) do
        if type(control.onCommit) == "function" then
            local ok,err = pcall(control.onCommit, ability, cast, g_castControlState, casterToken, symbols)
            if not ok then
                dmhub.CloudError(string.format("DrawSteelActionBar cast control '%s' onCommit failed: %s", tostring(control.id), tostring(err)))
            end
        end
    end
end

--- Build an OnFinishCast handler that invokes onResolve on every active cast control.
--- Captures castState by reference at the time Cast is called -- this is safe because
--- cancelCasting only clears g_castControlState AFTER Cast() returns (Cast queues a
--- coroutine for behaviors; the controller's finishCasting clears state immediately,
--- but the captured local table reference survives).
--- @return function
local function MakeCastControlsOnResolveHandler(casterToken)
    local capturedControls = {}
    for _,c in ipairs(g_activeCastControls) do capturedControls[#capturedControls+1] = c end
    local capturedState = g_castControlState
    return function(ability, _, options)
        local cast = options and options.symbols and options.symbols.cast
        for _,control in ipairs(capturedControls) do
            if type(control.onResolve) == "function" then
                local ok,err = pcall(control.onResolve, ability, cast, capturedState, casterToken)
                if not ok then
                    dmhub.CloudError(string.format("DrawSteelActionBar cast control '%s' onResolve failed: %s", tostring(control.id), tostring(err)))
                end
            end
        end
    end
end

CreateAbilityController = function()
    local resultPanel

    m_altitudeController = CreateAltitudeController()
    m_shiftController = CreateShiftController()

    --Pre-cast controls registered via DrawSteelActionBar.RegisterCastControl.
    --Each entry's render(parent, ability, castState) builds widgets into this panel.
    g_castControlsPanel = gui.Panel {
        classes = { 'collapsed' },
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        vmargin = 4,

        refreshCastControls = function(element)
            element.children = {}
            g_activeCastControls = {}

            if g_currentAbility == nil then
                element:SetClass("collapsed", true)
                return
            end

            local controls = DrawSteelActionBar.GetCastControls()
            local rendered = {}

            --First pass: determine which controls apply. We need this up front so
            --that if any control applies we can pre-build g_currentSymbols.cast
            --BEFORE rendering -- controls populate cast fields (e.g. cast.invoked)
            --in render and on toggle, and downstream GoblinScript (numTargets,
            --range, prompts) reads those during the targeting flow. Without the
            --pre-built cast, formulas like `1 + Cast.Invoked` crash because
            --symbols("cast") returns nil.
            local applying = {}
            for _,control in ipairs(controls) do
                local apply = true
                if type(control.appliesTo) == "function" then
                    local ok,result = pcall(control.appliesTo, g_currentAbility)
                    apply = ok and result
                end
                if apply then
                    applying[#applying+1] = control
                end
            end

            if #applying > 0 then
                EnsureSymbolsCast(g_currentAbility, g_currentSymbols, nil)
            end

            --refreshTargeting: controls call this when their toggle state changes,
            --so numTargets/range/prompts re-evaluate live. CalculateSpellTargeting is
            --idempotent and reads g_currentSymbols, so callers just mutate the cast
            --object (e.g. cast.invoked = true) before calling.
            local refreshTargeting = function()
                if g_currentAbility ~= nil then
                    CalculateSpellTargeting()
                end
            end

            for _,control in ipairs(applying) do
                g_activeCastControls[#g_activeCastControls+1] = control
                if type(control.render) == "function" then
                    --The control creates panels by passing them as children to a wrapper
                    --panel, OR by appending to a list we own. To keep the API simple, we
                    --hand the control a "parent" panel that it uses as a place to attach
                    --widgets via the children = {...} pattern. We build a sub-panel per
                    --control so each control's render is isolated.
                    local subpanel = gui.Panel {
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",
                        valign = "center",
                        hmargin = 4,
                    }
                    local ctx = {
                        symbols = g_currentSymbols,
                        cast = g_currentSymbols.cast,
                        refreshTargeting = refreshTargeting,
                    }
                    local ok,err = pcall(control.render, subpanel, g_currentAbility, g_castControlState, ctx)
                    if not ok then
                        dmhub.CloudError(string.format("DrawSteelActionBar cast control '%s' render failed: %s", tostring(control.id), tostring(err)))
                    end
                    rendered[#rendered+1] = subpanel
                end
            end

            element.children = rendered
            element:SetClass("collapsed", #rendered == 0)
        end,
    }

    g_castButton = gui.Button {
        classes = {"sizeL", "bold", "collapsed"},
        halign = "center",
        width = 140,
        text = "Confirm",
        press = function(element)
            if g_currentAbility == nil then return end
            if g_abilityController == nil then return end

            if g_currentAbility.targetType == 'all' or g_currentAbility.targetType == 'map' or g_currentAbility.targetType == 'areatemplate' then
                --for 'all' types we have a fake map press. The map parameters don't matter.
                g_abilityController:FireEvent("mappress")
            else
                CalculateSpellTargeting(true)
            end
        end,
    }

    g_castMessage = gui.Label {
        data = {
            promptText = '',
        },
        halign = "center",
        width = "auto",
        minWidth = 200,
        textAlignment = "center",
        height = "auto",
        bold = true,
        fontSize = 16,
        refresh = function(element)
            if element.data.promptText == nil or element.data.promptText == "" then
                g_castMessageContainer:SetClass("collapsed", true)
                return
            end

            element.text = element.data.promptText
            g_castMessageContainer:SetClass("collapsed", false)
        end,
    }

    g_tokenSelectionContainer = CreateTokenSelectionContainer()

    g_castMessageContainer = gui.TooltipFrame(g_castMessage, {
    })

    g_castModesPanel = gui.Panel {
        classes = { 'collapsed' },
        width = "auto",
        height = "auto",
        bgimage = "panels/square.png",
        bgcolor = "#000000bb",
        vmargin = 8,
        flow = "horizontal",

        refreshModes = function(element)
            if g_currentAbility == nil or g_currentAbility.multipleModes == false or g_currentAbility:try_get("modeList") == nil then
                element:SetClass("collapsed", true)
                return
            end

            local changeMode = false
            local children = {}

            for i, mode in ipairs(g_currentAbility.modeList) do
                local available = true
                if mode.condition ~= nil and mode.condition ~= "" then
                    available = ExecuteGoblinScript(mode.condition, g_token.properties:LookupSymbol(), 1,
                        "Mode condition")
                    available = type(available) == "number" and available > 0
                end

                if available then
                    children[#children + 1] = gui.Label {
                        classes = { "enumSliderOption", cond(i == g_currentSymbols.mode, "selected") },
                        text = mode.text,
                        fontSize = 14,
                        textWrap = true,
                        vpad = 1,
                        hpad = 4,
                        width = "auto",
                        minWidth = 120,
                        maxWidth = 140,
                        height = 35,

                        hover = function(element)
                            if mode.rules ~= nil and mode.rules ~= "" then
                                gui.Tooltip{valign = "top", text = StringInterpolateGoblinScript(mode.rules, g_token.properties)}(element)
                            end
                        end,

                        press = function(element)
                            if g_currentAbility == nil then return end
                            g_currentSymbols.mode = i

                            g_currentAbility = g_currentAbility:SwitchModes(i)

                            g_targetInfo = CreateTargetInfo(g_currentAbility)

                            if g_currentAbility.targetType ~= 'self' and g_currentAbility.targetType ~= 'target' and g_currentAbility.targetType ~= 'all' and g_currentAbility.targetType ~= 'areatemplate' then
                                --make this get map events.
                                g_abilityController.mapfocus = true
                            else
                                g_abilityController.mapfocus = false
                            end

                            if g_currentAbility ~= nil and (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") then
                                local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                                local shifting = (movementType == "shift")
                                if shifting then
                                    m_shiftController:FireEventTree("beginCasting")
                                    m_shiftController:SetClass("collapsed", false)
                                else
                                    m_shiftController:SetClass("collapsed", true)
                                end
                            else
                                m_shiftController:SetClass("collapsed", true)
                            end



                            g_currentCostProposal = g_currentAbility:GetCost(g_token, g_currentSymbols)
                            AppendImprovementCosts(g_currentCostProposal)

                            --re-evaluate instant "apply on casting" duration effects for the
                            --newly-selected mode: apply effects whose filterTarget gate now
                            --passes, remove those whose gate no longer holds. Done before
                            --CalculateSpellTargeting so a Movement-Speed bump recalculates the
                            --pathfind reachable area for the new mode.
                            RefreshCastingDurationEffects()

                            CalculateSpellTargeting()
                            --TODO: resourcesBar
                            --resourcesBar:FireEventTree("cost", g_currentCostProposal)
                            g_castMessage:FireEvent("refresh")
                            g_castModesPanel:FireEvent("refreshModes")
                            g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")
                            g_channeledResourcePanel:FireEventTree("focusspell")

                            --If the spell's render varies depending on the mode (a
                            --variation swap or mode-gated power rolls), re-display the
                            --ability card so it shows the switched mode's content
                            --rather than the mode it was first displayed with. This
                            --also covers the auto-switch when the previously selected
                            --mode's condition fails (see the ScheduleEvent press
                            --below), which otherwise leaves a stale card up through
                            --the whole targeting phase.
                            if g_currentAbility ~= nil and g_currentAbility:RenderVariesWithDifferentModes() then
                                CharacterPanel.DisplayAbility(g_token, g_currentAbility, g_currentSymbols)
                            end
                        end,
                    }
                elseif i == g_currentSymbols.mode then
                    changeMode = true
                end
            end

            if changeMode and #children > 0 then
                --need to force a mode change to an available mode.
                children[1]:ScheduleEvent("press", 0.05)
            end


            element.children = children

            element:SetClass("collapsed", false)
        end,
    }

    g_forcedMovementTypePanel = gui.Panel {
        classes = { 'collapsed' },
        width = "auto",
        maxWidth = 800,
        height = "auto",
        halign = "center",
        vmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = Styles.Ability.blurColor,
        flow = "horizontal",
        blurBackground = true,
        wrap = true,

        data = {
            possibleForcedMovementTypes = {},
        },

        refreshForcedMovement = function(element)
            local forcedMovementType = g_currentAbility ~= nil and g_currentAbility:ForcedMovementType()
            if forcedMovementType == nil or g_currentSymbols == nil or g_currentSymbols.invoker == nil then
                element.children = {}
                element:SetClass("collapsed", true)
                return
            end

            local invoker = Utils.ResolveGoblinScriptObject(g_currentSymbols.invoker)

            --see if the invoker is capable of modifying the forced movement type.
            local movementTypes = invoker:CanModifyForcedMovementTypes(forcedMovementType)
            if #movementTypes == 0 then
                element.children = {}
                element:SetClass("collapsed", true)
                return
            end

            local possibleForcedMovementTypes = movementTypes
            table.insert(possibleForcedMovementTypes, 1, forcedMovementType)

            local preferred = g_preferredForcedMovementType:Get()
            if table.contains(possibleForcedMovementTypes, preferred) then
                g_currentSymbols.forcedmovement = preferred
            else
                g_currentSymbols.forcedmovement = possibleForcedMovementTypes[1]
            end

            local children = {}
            for i, moveType in ipairs(possibleForcedMovementTypes) do
                children[#children + 1] = gui.Label {
                    classes = { "enumSliderOption", cond(moveType == g_currentSymbols.forcedmovement, "selected") },
                    text = moveType,

                    --the enumSliderOption class is height = "100%" with no width, which
                    --in this auto-sized container renders as tall, text-width slivers.
                    --Give the options explicit compact chip sizing instead.
                    fontSize = 14,
                    width = "auto",
                    minWidth = 80,
                    maxWidth = 160,
                    height = 24,
                    hpad = 8,
                    vpad = 1,
                    borderBox = true,
                    halign = "center",
                    valign = "center",
                    textAlignment = "center",

                    press = function(element)
                        g_preferredForcedMovementType:Set(moveType)
                        g_currentSymbols.forcedmovement = moveType

                        CalculateSpellTargeting()

                        g_castMessage:FireEvent("refresh")
                        g_castModesPanel:FireEvent("refreshModes")
                        g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")
                    end,
                }
            end

            element.children = children
            element:SetClass("collapsed", false)
        end,
    }

    g_skipButton = gui.Button {
        classes = {"sizeM", "collapsed"},
        width = 80,
        text = "Skip",
        halign = "center",
        press = function(element)
            if g_abilityController == nil then return end
            g_abilityController:FireEvent("cancelCasting")
        end,
    }

    g_ammoChoicePanel = gui.Panel {
        width = 1,
        height = 1,
    }

    g_synthesizedSpellsPanel = CreateSynthesizedSpellsPanel()

    g_castChargesInput = gui.Panel {
        width = 1,
        height = 1,
    }

    --- @type Label
    local channeledResourceTitle = gui.Label {
        text = "Channeled Resource",
        fontSize = 18,
        bold = true,
        markdown = true,
        bmargin = 5,
        color = Styles.textColor,
        halign = "center",
        valign = "top",
        width = "auto",
        maxWidth = 800,
        height = 28,
    }

    --- @type Panel
    local channeledResourceContainer = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
    }

    g_channeledResourcePanel = gui.Panel {
        classes = { "collapsed" },
        width = "auto",
        height = "auto",
        vpad = 8,
        hpad = 16,
        borderFade = true,
        borderWidth = 12,
        tmargin = 2,
        bmargin = 2,
        flow = "vertical",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#00000088",
        borderColor = "#00000088",

        channeledResourceTitle,
        channeledResourceContainer,

        data = {
            children = {},
        },

        styles = {
            {
                selectors = { "levelPanel" },
                width = 22,
                height = 22,
                hmargin = 2,
                valign = "center",
                fontSize = 18,
                color = Styles.textColor,
                textAlignment = "center",
                borderWidth = 1,
                bgimage = "panels/square.png",
                borderWidth = 1,
                borderColor = "#ffffff55",
                bgcolor = "#ffffff22",
            },
            {
                selectors = { "levelPanel", "invalid" },
                color = "red",
                borderColor = "#99999955",
                bgcolor = "#99999922",
            },
            --Levels that would take the resource below zero. Selectable (the
            --creature has the Negative Heroic Resource attribute), but tinted
            --light red so it is clear you are going into the red.
            {
                selectors = { "levelPanel", "negative" },
                color = "#ff9999",
                borderColor = "#ff999955",
                bgcolor = "#ff999922",
            },
            {
                selectors = { "levelPanel", "~invalid", "hover" },
                borderColor = "#ffffffaa",
            },
            {
                selectors = { "levelPanel", "negative", "~invalid", "hover" },
                borderColor = "#ff9999aa",
            },
            {
                selectors = { "levelPanel", "selected" },
                borderColor = "#ffffffff",
                borderWidth = 2,
            },
            {
                selectors = { "levelPanel", "negative", "selected" },
                borderColor = "#ff9999ff",
                borderWidth = 2,
            },
        },

        focusspell = function(element)
            if g_token == nil then return end
            if g_currentAbility == nil or g_currentAbility.channeledResource == "none" then
                element:SetClass("collapsed", true)
                return
            end

            local resourcesTable = dmhub.GetTable(CharacterResource.tableName) or {}
            local resource = resourcesTable[g_currentAbility.channeledResource]
            if resource == nil then
                element:SetClass("collapsed", true)
                return
            end

            local resources = g_token.properties:GetResources()[resource.id] or 0
            local resourcesAvailable = resources - g_token.properties:GetResourceUsage(resource.id, resource.usageLimit)
            local baseCost = 0
            if g_currentAbility.resourceCost == g_currentAbility.channeledResource then
                --what we are channeling is also the base cost of the spell, so factor that in.
                resourcesAvailable = resourcesAvailable - ExecuteGoblinScript(g_currentAbility.resourceNumber, g_token.properties:LookupSymbol(g_currentSymbols), 0, "Determine resource number for " .. g_currentAbility.name)
                baseCost = ExecuteGoblinScript(g_currentAbility.resourceNumber, g_token.properties:LookupSymbol(g_currentSymbols), 0, "Determine resource number for " .. g_currentAbility.name)
            end

            --A creature with the "Negative Heroic Resource" attribute may drive the
            --resource below zero. resourcesAvailable is what they have in hand;
            --resourcesSpendable includes the amount they may go into the red for.
            --Levels between the two are offered but shown in light red.
            local negativeAllowance = resource:AllowResourceBelowZero(g_token.properties)
            local resourcesSpendable = resourcesAvailable + negativeAllowance

            if resourcesSpendable <= 0 then
                element:SetClass("collapsed", true)
                return
            end

            channeledResourceTitle.text = StringInterpolateGoblinScript(g_currentAbility.channelDescription,
                g_token.properties) or ""
            local channelIncrement = g_currentAbility:ChannelIncrement()
            local maxChannel = g_currentAbility:MaxChannel(g_token.properties, g_currentSymbols)

            local added = false
            local children = element.data.children
            while #children * channelIncrement <= resourcesSpendable and #children * channelIncrement <= maxChannel do
                local ncharges = #children
                local nresources = ncharges * channelIncrement
                local panel = gui.Label {
                    classes = { "levelPanel" },
                    text = tostring(ncharges * channelIncrement),
                    data = {
                        nresources = nresources,
                        ncharges = ncharges,
                    },
                    press = function(element)
                        if element:HasClass("invalid") == false then
                            g_channeledResourcePanel:FireEventTree("select", element.data.ncharges)
                        end
                    end,
                }

                children[#children + 1] = panel
                added = true
            end

            for i = 1, #children do
                children[i].text = tostring(baseCost + (i - 1) * channelIncrement)
                children[i].data.nresources = (i - 1) * channelIncrement
                --Collapse if either the player can't afford it OR the ability's
                --maxChannel limit excludes it. The maxChannel check is needed
                --because the add-children loop above only runs once (the while
                --grows children, never shrinks); when mode changes drop the
                --max, those previously-added chips need to hide here.
                children[i]:SetClass("collapsed", (i - 1) * channelIncrement > resourcesSpendable or (i - 1) * channelIncrement > maxChannel)
                children[i]:SetClass("negative", (i - 1) * channelIncrement > resourcesAvailable)
                children[i]:SetClass("selected", (i - 1) == g_currentSymbols.charges)
            end

            if added then
                element.data.children = children

                channeledResourceContainer.children = children
            end

            element:SetClass("collapsed", false)
        end,
        defocusspell = function(element)
            element:SetClass("collapsed", true)
        end,

        select = function(element, charges)
            if g_channeledResourcePanel == nil then return end
            if g_currentAbility == nil then return end

            --recalculate with the new cost proposal.
            g_currentCostProposal = g_currentAbility:GetCost(g_token, { charges = charges, mode = g_currentSymbols.mode })
            AppendImprovementCosts(g_currentCostProposal)
            g_currentSymbols.charges = charges

            CalculateSpellTargeting()
            g_castMessage:FireEvent("refresh")
            g_castModesPanel:FireEvent("refreshModes")
            g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")

            g_channeledResourcePanel:FireEventTree("focusspell")
        end,
    }


    resultPanel = gui.Panel {
        id = "abilityController",
        classes = { "collapsed" },
        floating = true,
        width = "auto",
        height = "auto",
        valign = "bottom",
        halign = "center",
        flow = "vertical",
        y = -70,

        g_castMessageContainer,
        g_tokenSelectionContainer,


        g_forcedMovementTypePanel,

        m_altitudeController,
        m_shiftController,

        g_ammoChoicePanel,
        g_synthesizedSpellsPanel,
        g_castChargesInput,

        g_channeledResourcePanel,

        g_castModesPanel,

        g_castControlsPanel,

        gui.Panel {
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            g_castButton,
            g_skipButton,
        },

        multimonitor = {"targetobjects"},

        monitor = function(element)
            if g_currentAbility ~= nil then
                for _, targetToken in ipairs(dmhub.allTokensIncludingObjects) do
                    if targetToken.valid and targetToken.sheet ~= nil then
                        if targetToken.sheet.data.targetInfo ~= nil then
                            targetToken.sheet:FireEvent("untarget")
                        end
                    end
                end

                CalculateSpellTargeting()
            end
        end,

        create = function(element)
            element.data.oldIsCasting = gamehud.actionBarPanel.data.IsCastingSpell
            gamehud.actionBarPanel.data.IsCastingSpell = function()
                return g_currentAbility
            end
        end,

        destroy = function(element)
            if gamehud and gamehud.actionBarPanel and gamehud.actionBarPanel.valid then
                gamehud.actionBarPanel.data.IsCastingSpell = element.data.oldIsCasting
            end
        end,

        enable = function(element)
        end,

        disable = function(element)
            element:FireEvent("cancelCasting")
        end,

        applyImprovements = function(element)
            ApplyImprovements()
        end,

        beginCasting = function(element, ability, args)
            --if a wall live-placement session from previous targeting is still
            --uncommitted (e.g. the player picked another ability mid-targeting
            --without cancelling), tear those wall squares down now.
            do
                local buildWall = rawget(_G, "ActivatedAbilityBuildWallBehavior")
                if buildWall ~= nil then
                    buildWall.CancelPlacement()
                end
            end

            if g_invokerInfo ~= nil and g_invokerInfo.oncast ~= nil then
                g_invokerInfo.oncast()
            end

            args = args or {}

            if g_actionBar == nil then return end
            --g_token can be non-nil but stale: the selected caster may have been
            --deleted/despawned (or the selection cleared) before this fires, especially
            --on the invoke path (FireEventTree "invokeAbility"). The reference survives
            --but .valid is false and .properties is nil, and everything below reads
            --g_token.properties (range, movement speed, compel attributes), so there is
            --no caster to begin a cast for.
            if g_token == nil or not g_token.valid or g_token.properties == nil then return end
            g_actionBar:FireEventTree("closemenu")

            ability = ability:SwitchModes(1)

            --[[ --code to make a 'charge' ability a charge.
            if args.fromui and ability:HasKeyword("Charge") then
                --find the charge ability and use it instead.
                local chargeAbility = nil
                for _,ability in ipairs(g_abilities) do
                    if ability.name == "Charge" and ability:HasKeyword("Melee") then
                        chargeAbility = DeepCopy(ability:MakeTemporaryClone())
                    end
                end

                if chargeAbility ~= nil then
                    --cook up a special version of the charge ability that always
                    --uses the current ability as the attack at the end of the charge.
                    local invoke = nil
                    for i=#chargeAbility.behaviors, 1, -1 do
                        if chargeAbility.behaviors[i].typeName == "ActivatedAbilityInvokeAbilityBehavior" then
                            invoke = chargeAbility.behaviors[i]
                            break
                        end
                    end

                    if invoke ~= nil then
                        invoke.abilityType = "named"
                        invoke.namedAbility = ability.name
                        invoke.promptText = "Choose target of " .. ability.name
                        ability = chargeAbility
                    end
                end
            end
            ]]

            g_currentAbility = ability
            g_targetsChosen = {}
            g_manualTargetChosen = false
            g_firstTarget = nil

            --transfer any packaged targets over. Token targets go in g_targetsChosen;
            --loc targets (e.g. a forced-move destination resolved by an AI prompt
            --handler) seed m_positionTargetsChosen below so emptyspace/straightline
            --targeting treats them exactly like a player's destination click.
            local packagedLocTargets = {}
            if args.targets ~= nil then
                for _,target in ipairs(args.targets) do
                    if target.token ~= nil then
                        g_targetsChosen[#g_targetsChosen + 1] = target.token.charid
                    elseif target.loc ~= nil then
                        packagedLocTargets[#packagedLocTargets + 1] = { loc = target.loc }
                    end
                end
            end

            if g_targetsChosen ~= nil then
                g_firstTarget = g_targetsChosen[1]
            end
            m_positionTargetsChosen = {}
            for _,target in ipairs(packagedLocTargets) do
                m_positionTargetsChosen[#m_positionTargetsChosen + 1] = target
            end
            g_pointTargeting = {}

            gui.SetFocus(element)

            g_synthesizedSpellsPanel:SetClass("collapsed", true)
            SetAltitudeMode(nil)

            g_currentSymbols = table.union(
                { cast = args.cast, mode = 1, charges = ability:DefaultCharges(), spellname = ability.name },
                args.symbols or {})

            --if we have a 'duration effect' on this ability we apply it while casting,
            --so that we can get its effects during casting. E.g. if their movement increases
            --for pathfinding, or the Charging attribute blocks difficult terrain.
            --This is mode-aware: behaviors with a filterTarget gate apply only when the
            --gate passes for the selected mode. It must run before the movement-speed
            --pathfind clamp below so a Movement-Speed bump widens the reachable area.
            ClearCastingDurationEffects()
            RefreshCastingDurationEffects()

            --limit any pathfinding moves to the creature's current movement speed
            local targetingType = ability:try_get("targeting", "direct")
            if targetingType == "pathfind" then
                local range = ability:GetRange(g_token.properties, g_currentSymbols)
                local movementSpeed = g_token.properties:CurrentMovementSpeed()
                if range > movementSpeed then
                    ability = ability:MakeTemporaryClone()
                    ability.range = movementSpeed
                    g_currentAbility = ability
                    if movementSpeed <= 0 then
                        ability.castImmediately = true
                        ability.targetType = "self"

                        local token = g_token

                        dmhub.Coroutine(function()
                            coroutine.yield(0.01)
                            local abilityBase = MCDMUtils.GetStandardAbility("Float Text")
                            if abilityBase and token.valid then
                                local abilityClone = DeepCopy(abilityBase)
                                MCDMUtils.DeepReplace(abilityClone, "<<text>>", "Cannot Move")
                                abilityClone.behaviors[1].color = "#FF0000"
                                ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(token, abilityClone, token, "prompt", {}, {})
                            end
                        end)

                    end
                end
            end

            local compelToward = g_token.properties:CalculateNamedCustomAttribute("Compel Movement Toward")
            if compelToward ~= 0 then
                local tokens = dmhub.allTokens
                for _,tok in ipairs(tokens) do
                    if Utils.HashGuidToNumber(tok.charid) == compelToward then
                        g_currentSymbols.compeltoward = tok.properties
                        break
                    end
                end
            end

            local compeladjacent = g_token.properties:CalculateNamedCustomAttribute("Compel Movement Adjacent")
            if compeladjacent ~= 0 then
                local tokens = dmhub.allTokens
                for _,tok in ipairs(tokens) do
                    if Utils.HashGuidToNumber(tok.charid) == compeladjacent then
                        g_currentSymbols.compeladjacent = tok.properties
                        break
                    end
                end
            end

            g_currentCostProposal = ability:GetCost(g_token, g_currentSymbols)
            AppendImprovementCosts(g_currentCostProposal)

            g_targetInfo = CreateTargetInfo(g_currentAbility)

            --Clear any squad-strike minion->target locks from a previous cast.
            g_squadPendingLockMinion = nil
            ActivatedAbility.ClearSquadTargetingState()

            g_castMessageContainer:SetClass("collapsed", true)
            g_tokenSelectionContainer:SetClass("collapsed", true)
            g_castButton:SetClass("collapsed", true)

            --Reset cast-control state for this new cast and refresh the controls panel.
            --Each control's render() builds widgets and may mutate g_castControlState.
            g_castControlState = {}
            if g_castControlsPanel ~= nil and g_castControlsPanel.valid then
                g_castControlsPanel:FireEvent("refreshCastControls")
            end

            if ability.targetType ~= 'self' and ability.targetType ~= 'target' and ability.targetType ~= 'all' and ability.targetType ~= 'areatemplate' then
                --make this get map events.
                g_abilityController.mapfocus = true
            else
                g_abilityController.mapfocus = false
            end

            element.captureEscape = true

            element:SetClass("collapsed", false)

            if ability:GetCastingEmote() ~= nil then
                g_castingEmoteSet = ability:GetCastingEmote()
                g_token.properties:Emote(g_castingEmoteSet, { start = true, ttl = 20 })
            end

            dmhub.blockTokenSelection = true

            --Don't force cast when beginning casting
            --Abilities with prompts need to wait for user input
            CalculateSpellTargeting(false, true)

            g_channeledResourcePanel:FireEventTree("focusspell")

            if g_currentAbility ~= nil and g_currentAbility.castImmediately and (not g_castButton:HasClass("collapsed")) then
                g_castButton:FireEvent("press")
            end


            if g_currentAbility ~= nil and (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") then
                local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                local shifting = (movementType == "shift")
                if shifting then
                    m_shiftController:FireEventTree("beginCasting")
                    m_shiftController:SetClass("collapsed", false)
                else
                    m_shiftController:SetClass("collapsed", true)
                end
            else
                m_shiftController:SetClass("collapsed", true)
            end

            --see if there are any triggers that can apply to this cast.
            ClearCastingTriggers()
            if g_currentAbility ~= nil then
                local triggers = {}
                local triggerSymbols = table.shallow_copy(g_currentSymbols)
                triggerSymbols.ability = GenerateSymbols(g_currentAbility)
                triggerSymbols.caster = g_token.properties:LookupSymbol()
                triggerSymbols.targetcount = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                for _, triggerToken in ipairs(dmhub.allTokens) do
                    for _, mod in ipairs(triggerToken.properties:GetActiveModifiers()) do
                        mod.mod:TriggerModsCastingAbility(mod, triggerToken, g_token, g_currentAbility, triggerSymbols,
                            triggers)
                    end
                end

                if #triggers > 0 then
                    m_castingTriggers = {}
                    for _, trigger in ipairs(triggers) do
                        local token = dmhub.GetTokenById(trigger.charid)
                        if token ~= nil then
                            token:ModifyProperties {
                                description = "Trigger Casting",
                                undoable = false,
                                execute = function()
                                    token.properties:DispatchAvailableTrigger(trigger)
                                end,
                            }
                            m_castingTriggers[#m_castingTriggers + 1] = trigger
                        end
                    end
                    m_castingTriggers = triggers
                    m_castingTriggersOwnerPanel = element
                    m_castingTriggersCache = {}
                    element.monitorGame = "/characters"
                end
            end
        end,

        monitorGameEvent = "refreshCharacters",
        refreshCharacters = function(element)
            if m_castingTriggers == nil or #m_castingTriggers == 0 then
                return
            end

            for i = 1, #m_castingTriggers do
                local triggerToken = dmhub.GetTokenById(m_castingTriggers[i].charid)
                if triggerToken ~= nil and triggerToken.valid then
                    local availableTriggers = triggerToken.properties:GetAvailableTriggers() or {}
                    local availableTrigger = availableTriggers[m_castingTriggers[i].id]
                    if availableTrigger == nil then
                        table.remove(m_castingTriggers, i)
                    else
                        m_castingTriggers[i] = availableTrigger

                        if availableTrigger.triggered and (not m_castingTriggersCache[availableTrigger.id]) then
                            m_castingTriggersCache[availableTrigger.id] = true

                            if availableTrigger.params.targetcount ~= nil then
                                g_currentSymbols.targetcount = availableTrigger.params.targetcount
                                g_currentSymbols.numtargetsoverride = availableTrigger.params.targetcount
                                CalculateSpellTargeting()
                            end
                        end
                    end
                end
            end
        end,
        clearCastingTriggers = function(element)
            element.monitorGame = nil
        end,



        finishCasting = function(element)
            element:FireEvent("cancelCasting")
        end,

        cancelCasting = function(element)
            --Director overview (slice (e)): whatever ended this cast, the
            --pending implicit-claim record dies with it.
            g_overviewCastPending = nil

            ClearCastingTriggers()

            ClearCastingDurationEffects()

            for _, destructor in ipairs(g_castingDestructors) do
                destructor()
            end

            g_castingDestructors = {}

            if g_invokerInfo ~= nil and g_invokerInfo.oncancel ~= nil then
                g_invokerInfo.oncancel()
            end

            g_invokerInfo = nil

            -- Clear improvement state so the sidebar can clean up.
            m_activeImprovements = {}

            for k, token in pairs(dmhub.tokenInfo.tokens) do
                if token.valid and token.sheet ~= nil and token.sheet.data.targetInfo ~= g_targetInfo then
                    token.sheet:FireEvent("untarget")
                    token.sheet.data.targetInfo = nil
                end
            end

            if g_token ~= nil and g_token.valid then
                g_token:ClearMovementArrow()
                if g_pointTargeting ~= nil and g_pointTargeting.showingWarningArrows then
                    BroadcastMovementPlan(g_token, nil, nil)
                    g_pointTargeting.showingWarningArrows = false
                end
            end

            dmhub.blockTokenSelection = false

            TryPopCasterToken()

            if gui.GetFocus() == element then
                gui.SetFocus(nil)
            end

            CharacterPanel.HideAbility(g_currentAbility)

            RemoveTokenTargeting()

            g_squadPendingLockMinion = nil
            ActivatedAbility.ClearSquadTargetingState()

            ClearPointTargeting()

            SetTargetsInRadius({})

            g_currentAbility = nil
            g_currentSymbols = {}
            FreeTargetLineOfSightRays()
            element.mapfocus = false
            element.captureEscape = false

            if g_channeledResourcePanel ~= nil then g_channeledResourcePanel:SetClass("collapsed", true) end
            if g_castControlsPanel ~= nil and g_castControlsPanel.valid then
                g_castControlsPanel.children = {}
                g_castControlsPanel:SetClass("collapsed", true)
            end
            g_activeCastControls = {}
            g_castControlState = {}
            m_allowedAltitudeCalculator = nil
            SetAltitudeMode(nil)

            if g_actionBar ~= nil then g_actionBar:SetClassTree("invokingAbility", false) end
            if g_abilityController ~= nil then g_abilityController.mapfocus = false end

            ClearLineOfSightMark()
            ClearRadiusMarkers()

            if g_token ~= nil and g_token.valid and g_castingEmoteSet ~= nil then
                local emote = g_castingEmoteSet
                g_token.properties:Emote(emote, { start = false, ttl = 20 })

                g_castingEmoteSet = nil
            end

            element:SetClass("collapsed", true)
        end,

        chooseTargetToken = function(element, options)
            element:FireEvent("chooseTarget", options)
        end,

        chooseTarget = function(element, options)
            if g_actionBar == nil then return end
            ClearRadiusMarkers()

            --reasons[charid] = reason string for targets that pass the
            --all-inclusive filter but fail a "reasoned" filter. These targets
            --stay visible (with a tooltip) but cannot be chosen by players.
            local reasons = options.reasons or {}

            -- _tmp_aicontrol is a counter (incremented while AI is in control),
            -- so the falsy/truthy check must be against `> 0` -- a plain truthy
            -- check matches `0` and silently auto-picks every prompt target,
            -- defeating the "Prompt When Resolving" option on PowerRollBehavior.
            if options.sourceToken ~= nil and options.sourceToken.properties._tmp_aicontrol > 0 then
                --auto-pick the first target that isn't filtered out with a reason.
                local pick = options.targets[1]
                for _,t in ipairs(options.targets or {}) do
                    if reasons[t.charid] == nil then
                        pick = t
                        break
                    end
                end
                options.choose(pick)
                return
            end

            if options.sourceToken ~= nil and options.radius ~= nil then
                print("MovementRadius:: MARK", options.radius)
                AddRadiusMarker(options.sourceToken.locsOccupying, options.radius)
            end

            local targets = options.targets or {}
            local promptText = options.prompt or "Choose a target"
            local choose = options.choose or function(target) end
            local cancel = options.cancel or function() end

            gui.SetFocus(nil)
            g_actionBar:FireEvent("refresh")

            g_actionBar:SetClassTree("choosingTarget", true)

            g_tokenSelectionContainer:FireEvent("settokens", targets)

            g_castMessage.data.promptText = promptText
            g_castMessage:FireEvent("refresh")
            g_abilityController:SetClass("collapsed", false)
            g_castButton:SetClass("collapsed", true)

            --a bare token pick has no movement: never show the shift toggle,
            --which may have been left visible by a previous shift-move cast.
            m_shiftController:SetClass("collapsed", true)

            local targetChooser = gui.Panel {
                width = 1,
                height = 1,
                escapeActivates = true,
                escapePriority = EscapePriority.CANCEL_ACTION_BAR,
                captureEscape = true,
                escape = function(element)
                    element:DestroySelf()
                end,
                defocus = function(element)
                    element:DestroySelf()
                end,
                destroy = function()
                    if g_castMessage ~= nil then
                        g_castMessage.data.promptText = ''
                        g_castMessage:FireEvent("refresh")
                    end
                    if g_abilityController ~= nil then g_abilityController:SetClass("collapsed", true) end
                    ClearRadiusMarkers()
                    cancel()
                    for _, tok in ipairs(targets) do
                        if tok ~= nil and tok.valid and tok.sheet ~= nil then
                            tok.sheet.data.targetInfo = nil
                            tok.sheet:FireEvent("untarget")
                        end
                    end
                    gui.SetFocus(nil)
                    g_actionBar:SetClassTree("choosingTarget", false)
                end,
            }


            local targetInfo = {
                type = "ActivatedAbility",
                guid = dmhub.GenerateGuid(),
                execute = function(targetToken, info) --info has {targetEffects = {list of effect panels}}
                    --a reasoned filter keeps a target visible (with a tooltip
                    --reason) but blocks players from choosing it under strict
                    --targeting. Directors bypass this.
                    if targetToken ~= nil and reasons[targetToken.charid] ~= nil
                        and (not dmhub.isDM) and dmhub.GetSettingValue("strict:targeting") then
                        return
                    end
                    choose(targetToken)
                    cancel = function() end
                    gui.SetFocus(nil)
                end,
            }

            for _, tok in ipairs(targets) do
                if tok.valid and tok.sheet ~= nil then
                    if tok.sheet.data.targetInfo ~= nil then
                        tok.sheet.data.targetInfo = nil
                        tok.sheet:FireEvent("untarget")
                    end
                    tok.sheet.data.targetInfo = targetInfo
                    local reason = reasons[tok.charid]
                    tok.sheet.data.targetValid = reason == nil
                    if reason ~= nil then
                        tok.sheet:FireEvent("target", { valid = false, reason = reason, classes = { 'invalid' } })
                    else
                        tok.sheet:FireEvent("target", {})
                    end
                end
            end

            g_actionBar:AddChild(targetChooser)
            gui.SetFocus(targetChooser)
        end,

        --- @param invokerInfo nil|{oncast=nil|function, oncancel=nil|function}
        invokeAbility = function(element, casterToken, ability, symbols, invokerInfo, options)
            options = options or {}
            gui.SetFocus(nil)

            if g_actionBar == nil then return end

            --The caster can be removed/despawned before this invoke fires: invokes whose
            --caster is a parent-ability target (invokeOnCaster == false) route through
            --ExecuteInvoke, which yields waiting for the action bar, so the target token can
            --die in between. A gone caster has .valid == false / .properties == nil; there is
            --nothing to cast, and proceeding would hide the drawers via
            --SetClassTree("invokingAbility", true) below and never clear them (only
            --cancelCasting clears it, and no cast begins) -- stranding the bar hidden.
            if casterToken == nil or not casterToken.valid or casterToken.properties == nil then
                return
            end

            --DIAG: anchor invoke prompts in the log for the prompt-hang
            --investigation. Safe to keep.
            print(string.format("PROMPTDIAG:: invokeAbility caster=%s ability=%s instantCast=%s prompt=%s T=%.2f",
                tostring(casterToken.name or casterToken.charid), tostring(ability.name),
                tostring(options.instantCast), tostring(ability:try_get("promptOverride")), dmhub.Time()))

            g_invokerInfo = invokerInfo
            symbols.invoked = true

            PushCasterToken(casterToken)
            g_actionBar:FireEvent("refresh")

            g_actionBar:SetClassTree("invokingAbility", true)

            ability = DeepCopy(ability)
            --instantCast means the invoke already resolved its targets (AI prompt
            --handler or scripted resolution): cast as soon as targeting is satisfied
            --instead of waiting for a manual press of the cast button.
            if options.instantCast then
                ability.castImmediately = true
            end
            CharacterPanel.DisplayAbility(casterToken, ability)
            CharacterPanel.HighlightAbilitySection{
                ability = ability,
                caster = casterToken,
                section = "target",
            }
            element:FireEvent("beginCasting", ability, { symbols = symbols, targets = options.targets })

            --[[
            local spellPanel = GetSpellPanel(nil, nil, ability,
                { destroyOnDefocus = true, invoking = true, forceCasterToken = casterToken, adoptCasterToken = true })
            element:AddChild(spellPanel)
            --spellPanel:SetClass("collapsed", true)
            gui.SetFocus(spellPanel)
            spellPanel.data.stickyFocus = true
            spellPanel.data.blockFocus = true
            --]]

            g_synthesizedSpellsPanel:FireEvent("refreshSpell", { forceCasterToken = casterToken, instantCast = options.instantCast, targets = options.targets })
        end,

        highlightTargetToken = function(element, targetToken)
            if g_token == nil or not g_token.valid then
                return
            end
            element:FireEvent("unhighlightTargetToken")

            --While a squad minion is armed for a lock, preview the ray from
            --THAT minion: clicking will lock this pair, so the hover arrow
            --should show the armed minion attacking, not the auto-assigned
            --(closest) one. Hovering another squad minion falls through to
            --normal handling.
            if SquadStrikeActive() and g_squadPendingLockMinion ~= nil and g_squadPendingLockMinion.valid
                and not SquadIsActiveMinionToken(targetToken) then
                local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                m_markLineOfSight = dmhub.MarkLineOfSight(g_squadPendingLockMinion, targetToken, g_squadPendingLockMinion.properties:GetPierceWalls(), GetArrowColor(g_currentAbility, g_squadPendingLockMinion, targetToken), EffectiveArrowRange(g_squadPendingLockMinion, targetToken, range))
                if m_markLineOfSight ~= nil then
                    AddModifierLabelsToMarker(m_markLineOfSight, g_squadPendingLockMinion, targetToken, g_currentAbility, range)
                    m_markLineOfSight:AddLabel("Locked", "buff")
                    m_markLineOfSightToken = targetToken
                    m_markLineOfSightSourceToken = g_squadPendingLockMinion
                end
                return
            end

            local targets = BuildTargetsList()
            targets[#targets + 1] = {
                token = targetToken,
                loc = targetToken.loc,
            }

            local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
            g_currentSymbols.range = range
            local rays = g_currentAbility:GetTargetingRays(g_token, range, g_currentSymbols, targets)
            local rayCoversTarget = false
            if rays ~= nil then
                --the ability specifies the rays, we try to fish out the
                --new one to highlight and maintain any existing ones.
                for _, ray in ipairs(rays) do
                    if ray.b.id == targetToken.id then
                        rayCoversTarget = true
                        if m_targetLineOfSightRays[string.format("%s-%s", ray.a.id, ray.b.id)] == nil then
                            m_markLineOfSight = dmhub.MarkLineOfSight(ray.a, ray.b, ray.a.properties:GetPierceWalls(), GetArrowColor(g_currentAbility, ray.a, ray.b), EffectiveArrowRange(ray.a, ray.b, range))
                            AddModifierLabelsToMarker(m_markLineOfSight, ray.a, ray.b, g_currentAbility, range)
                            m_markLineOfSightToken = targetToken
                            m_markLineOfSightSourceToken = g_token
                        end
                        break
                    end
                end
            end
            if rays == nil or not rayCoversTarget then
                --either no squad rays at all, or the hovered target wasn't
                --reachable by any squad member -- draw from the caster.
                m_markLineOfSight = dmhub.MarkLineOfSight(g_token, targetToken, g_token.properties:GetPierceWalls(), GetArrowColor(g_currentAbility, g_token, targetToken), EffectiveArrowRange(g_token, targetToken, range))
                if m_markLineOfSight ~= nil then
                    AddModifierLabelsToMarker(m_markLineOfSight, g_token, targetToken, g_currentAbility, range)
                    m_markLineOfSightToken = targetToken
                    m_markLineOfSightSourceToken = g_token
                end
            end
        end,

        unhighlightTargetToken = function(element, targetToken)
            if m_markLineOfSight ~= nil and (targetToken == nil or targetToken == m_markLineOfSightToken) then
                m_markLineOfSight:Destroy()
                m_markLineOfSight = nil
                m_markLineOfSightToken = nil
                m_markLineOfSightSourceToken = nil
            end
        end,

        --map events that we get when in point targeting mode.
        --- @param element Panel
        --- @param loc Loc
        --- @param point table
        maphover = function(element, loc, point)
            element.data.lastHoverLoc = loc
            element.data.lastHoverPoint = point

            --tiered-jump shortfall markers are per-hovered-tile; rebuild below.
            ClearJumpShortfallMarkers()

            --diagnostic: cross-floor targeting trace. Throttled to changes only.
            if g_currentAbility ~= nil and (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") then
                local k = string.format("%s|%s", tostring(loc and loc.str or "nil"), tostring(loc and loc.floor or "nil"))
                if element.data._lastXFloorKey ~= k then
                    element.data._lastXFloorKey = k
                    print(string.format("XFLOOR:: maphover loc=%s loc.floor=%s caster.floor=%s targetType=%s targeting=%s",
                        tostring(loc and loc.str or "nil"),
                        tostring(loc and loc.floor or "nil"),
                        tostring(g_token and g_token.floorIndex or "nil"),
                        tostring(g_currentAbility.targetType),
                        tostring(g_currentAbility:try_get("targeting", "direct"))))
                end
            end

            if g_abilityController == nil then return end
            if g_token == nil or (not g_token.valid) then
                g_abilityController:FireEvent("cancelCasting")
                return
            end

            if g_currentAbility == nil then return end

            if g_pointTargeting == nil then
                return
            end

            local startingLoc = loc

            if g_pointTargeting.shapeConfirmedLoc ~= nil and (loc == nil or loc.str ~= g_pointTargeting.shapeConfirmedLoc.str) then
                g_pointTargeting.shapeConfirmedLoc = nil
            end

            if loc ~= nil and m_altitudeMode ~= nil then
                local info = { loc = loc, point = point, panel = element }
                m_altitudeController:FireEventTree("loc", info)
                loc = info.loc
            end

            --a list of targets we'll highlight.
            local filteredTargets = {}

            local targetColor = "white"
            local clearMovementArrow = g_pointTargeting.showingMovementArrow
            local clearWarningArrows = g_pointTargeting.showingWarningArrows
            local prevShape = g_pointTargeting.shape
            if g_pointTargeting.fallingShape ~= nil then
                g_pointTargeting.fallingShape:Destroy()
                g_pointTargeting.fallingShape = nil
            end
            local destroyLabelsBeforeReturning = g_pointTargeting.labelsAtPathEnd ~= nil
            local destroyThroughCreatureLabels = g_pointTargeting.labelsAtThroughCreatures ~= nil
            local destroyFallDamageLabel = g_pointTargeting.fallDamageLabel ~= nil
            local pathfinding = false
            if point ~= nil and g_currentAbility.targetType ~= "areatemplate" then
                local radius = g_currentAbility:GetRadius(g_token.properties, g_currentSymbols)
                local shape = g_currentAbility.targetType
                local requireEmpty = false

                local locOverride = g_currentAbility:try_get("casterLocOverride")

                local targetingType = g_currentAbility:try_get("targeting", "direct")

                if (shape == 'emptyspace' or shape == 'anyspace') and (targetingType == "pathfind" or targetingType == "vacated" or targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures") then
                    if g_token.creatureDimensions.x > 1 and g_token.creatureDimensions.x % 2 == 1 then
                        for i = 3, g_token.creatureDimensions.x, 2 do
                            loc = loc.west.south
                        end
                    end
                end

                if shape == "line" and #m_positionTargetsChosen == 0 then
                    local lineDistance = g_currentAbility:GetLineDistance(g_token.properties, g_currentSymbols)
                    --still choosing the starting point of the line.
                    g_pointTargeting.shape = dmhub.CalculateShape {
                        shape = "cylinder",
                        targetPoint = point,
                        token = g_token,
                        range = lineDistance,
                        radius = 1,
                        locOverride = g_currentAbility:try_get("casterLocOverride"),
                        requireEmpty = requireEmpty,
                        emptyMayIncludeSelf = true,
                    }
                    
                elseif (shape == "emptyspace" or shape == "anyspace") and (targetingType == "pathfind" or targetingType == "vacated") then
                    pathfinding = true

                    local waypoints = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        waypoints[#waypoints + 1] = pos.loc
                    end

                    local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                    local shifting = (movementType == "shift")

                    local movementInfo = g_token:MarkMovementArrow(loc, { shifting = shifting, waypoints = waypoints })
                    if movementInfo ~= nil then
                        local targets = g_currentAbility:FindTargetsInMovementVicinity(g_token, movementInfo.path) or
                            filteredTargets
                        for _, target in ipairs(targets) do
                            filteredTargets[target.id] = target
                        end

                        --Mirror the drag flow's movementplan broadcast so OA warning
                        --arrows show during ability-targeted movement too. The token-
                        --side handler in DrawSteelTokenHud.lua filters on movementType,
                        --so teleport/shift abilities get a no-op there.
                        BroadcastMovementPlan(g_token, movementInfo.path, movementType)
                        g_pointTargeting.showingWarningArrows = true
                        clearWarningArrows = false
                    end
                    g_pointTargeting.showingMovementArrow = true
                    clearMovementArrow = false

                    --Show the movement cross-section diagram for regular movement and
                    --shifts too, not just forced moves. GameHud gates it on vertical
                    --interest, so flat paths still show nothing.
                    if movementInfo ~= nil then
                        ShowMovementDiagram(g_token, movementInfo.path, cond(shifting, tr("Shift"), tr("Movement")))
                    end
                elseif shape == "emptyspace" and targetingType == "direct" then
                    --Only draw the teleport arrow when the target is on the caster's floor.
                    --For cross-floor teleport the arrow would render on the caster's floor pointing
                    --at the wrong place; leave clearMovementArrow=true so any prior arrow is removed
                    --and the radius shape preview (rendered on the target floor) is the indicator.
                    --
                    --JUMPS are exempt: the engine resolves cross-floor jump targets (the jump line
                    --is walked on the caster's floor and the landing lifted onto the target floor),
                    --draws per-floor arrows, and the cross-section renders the ascend -- so the
                    --full jump preview works across floors.
                    local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)

                    --An emptyspace ability that is NOT the creature moving under its own power sets
                    --suppressMovementArrow -- e.g. choosing the square you fall into after being
                    --shaken off a creature you were climbing. The teleport-style arrow would draw
                    --from the caster's logical position, which for a climber is up on top of its
                    --mount and so renders parallax-shifted away from its sprite, and it would read
                    --as a teleport. The highlighted legal squares are the whole indicator; leaving
                    --clearMovementArrow set removes any arrow drawn before this.
                    if g_currentAbility:try_get("suppressMovementArrow", false) then
                        --no arrow.
                    elseif loc.floor == g_token.floorIndex or movementType == "jump" then

                        --A jump preview is built as a real jump (straightline + clears walls up to the
                        --jump distance) so the cross-section can arc it over those walls; matches the
                        --actual jump cast in AbilityRelocateCreature. Every other emptyspace/direct
                        --ability (teleport) uses the teleport-flag straight-line preview.
                        local markOptions = { teleport = true }
                        local jumpAlternates = nil
                        if movementType == "jump" then
                            local tierRadii = g_currentAbility:GetTargetingTierRadii(g_token, g_currentSymbols)
                            local jumpBehaviorType = rawget(_G, "ActivatedAbilityJumpBehavior")
                            if tierRadii ~= nil and jumpBehaviorType ~= nil then
                                --Tiered jump (roll-to-target): find the lowest tier whose
                                --jump actually lands on the hovered tile (distance AND
                                --height -- a tall wall or pillar inside a tier's distance
                                --still blocks it). When a ring carries a reachability set
                                --(ring.locSet, from CalculateJumpReachable) membership
                                --decides directly; otherwise a movement-arrow probe does.
                                --Lower tiers that fall short become shortfall previews: a
                                --marker on the tile they'd land on, and an alternate path
                                --for the movement diagram. Each probe's MarkMovementArrow
                                --replaces the last, so the final call below draws the
                                --arrow the player should see.
                                local distToTarget = g_token.loc:DistanceInTiles(loc)
                                local hoverKey = loc.xyfloorOnly.str
                                local requiredRing = nil
                                local alternates = {}
                                for _, ring in ipairs(tierRadii) do
                                    if ring.locSet ~= nil and ring.locSet[hoverKey] then
                                        requiredRing = ring
                                        break
                                    end

                                    local attemptLoc = jumpBehaviorType.ShortLandingLoc(g_token.loc, loc, ring.tiles)
                                    local info = g_token:MarkMovementArrow(attemptLoc, { jump = true, jumpHeight = ring.height })
                                    local landLoc = attemptLoc
                                    local path = nil
                                    if info ~= nil and info.path ~= nil then
                                        path = info.path
                                        if path.destination ~= nil then
                                            landLoc = path.destination
                                        end
                                    end

                                    --The probe decides in fallback mode (no reachability sets) and
                                    --for CROSS-FLOOR tiles, which the source-floor sets never contain.
                                    --Reach: arrive at the tile's x,y; for a SAME-floor target that is
                                    --enough (a jump into a chasm tile that falls through still reached
                                    --it), but a target on ANOTHER floor also demands landing on that
                                    --floor -- a jump that can't make the rise lands at the same x,y on
                                    --the caster's own floor (under the ledge), which is not a reach.
                                    local probeDecides = ring.locSet == nil or loc.floor ~= g_token.floorIndex
                                    local landsOnTarget = landLoc.x == loc.x and landLoc.y == loc.y and
                                        (loc.floor == g_token.floorIndex or landLoc.floor == loc.floor)
                                    if probeDecides and ring.tiles >= distToTarget and landsOnTarget then
                                        requiredRing = ring
                                        break
                                    end

                                    --An invisible ring's tier cannot be rolled (e.g. tier 1
                                    --under the Fury's Mighty Leaps), so it never lands short
                                    --there: no shortfall preview for it.
                                    if not ring.invisible then
                                        alternates[#alternates + 1] = { path = path, label = ring.label, tier = ring.tier, loc = landLoc, color = ring.color }
                                    end
                                end

                                if requiredRing == nil then
                                    --not reachable even at the top tier (too far or a
                                    --too-tall wall): the top tier's attempt IS the main
                                    --arrow; keep the lower tiers as shortfall previews.
                                    requiredRing = tierRadii[#tierRadii]
                                    g_jumpHoverUnreachable = true
                                    if #alternates > 0 then
                                        table.remove(alternates)
                                    end
                                end

                                for _, alternate in ipairs(alternates) do
                                    g_jumpShortfallMarkers[#g_jumpShortfallMarkers + 1] = dmhub.MarkLocs {
                                        locs = { alternate.loc },
                                        color = alternate.color,
                                    }
                                end

                                g_jumpHoverRequiredTier = requiredRing.tier
                                if #alternates > 0 then
                                    jumpAlternates = alternates
                                end
                                markOptions = { jump = true, jumpHeight = requiredRing.height }
                            else
                                local jumpHeight = math.floor((g_currentAbility:GetRange(g_token.properties, g_currentSymbols)/dmhub.unitsPerSquare) + 0.5)
                                markOptions = { jump = true, jumpHeight = jumpHeight }
                            end
                        end

                        local movementInfo = g_token:MarkMovementArrow(loc, markOptions)
                        g_pointTargeting.showingMovementArrow = true
                        clearMovementArrow = false

                        if movementInfo ~= nil then
                            if movementType == "move" or movementType == "jump" then
                                BroadcastMovementPlan(g_token, movementInfo.path, movementType)
                                g_pointTargeting.showingWarningArrows = true
                                clearWarningArrows = false
                            end

                            --Show the movement cross-section diagram for teleports and jumps. GameHud
                            --always shows it for jumps (vertically interesting by definition) and gates
                            --teleports on interest; the label reflects the movement type.
                            local diagramLabel = tr("Movement")
                            if movementType == "jump" then
                                diagramLabel = tr("Jump")
                                if g_jumpHoverUnreachable then
                                    diagramLabel = tr("Jump (cannot reach)")
                                elseif g_jumpHoverRequiredTier ~= nil and g_jumpHoverRequiredTier > 1 then
                                    diagramLabel = string.format(tr("Jump (needs Tier %d)"), g_jumpHoverRequiredTier)
                                end
                                --The jump preview path already carries movementType=Jump and its
                                --jumpHeight from the engine, so the diagram arcs it over walls and
                                --rests it on the ground -- no teleport flag needed.
                            elseif movementType == "teleport" then
                                diagramLabel = tr("Teleport")
                                --The teleport preview LuaPath is built at the default "walk" type, so
                                --the cross-section would smooth an aimed-into-the-air landing back down
                                --to the ground (see MovementCrossSection.cs -- the ground-follow
                                --smoothing only skips airborne/teleport/forced paths). Flag the path as
                                --a teleport so the diagram keeps the dialed landing altitude and
                                --synthesizes the arrival fall for a non-flyer.
                                movementInfo.path.teleport = true
                            end
                            ShowMovementDiagram(g_token, movementInfo.path, diagramLabel, jumpAlternates)
                        end
                    end
                elseif (shape == 'emptyspace' or shape == 'anyspace') and (targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures") then
                    local waypoints = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        waypoints[#waypoints + 1] = pos.loc
                    end

                    g_currentSymbols.waypoints = waypoints

                    local throughCreatures = g_currentAbility:try_get("forcedMovementThroughCreatures", false)
                    local reboundOptions = g_token.properties:GetForcedPushOptions()
                    --pass forcedMovementDistance so the preview cost function treats "blocks forced movement"
                    --walls as blocking (same flag the real cast sets in AbilityRelocateCreature.lua).
                    --only applies to the straightline (forced-movement) targeting variant.
                    local previewForcedDist = 0
                    if targetingType == "straightline" then
                        previewForcedDist = g_currentAbility:GetRange(g_token.properties, g_currentSymbols) / dmhub.unitsPerSquare
                    end

                    --[STRICTMOVE] diagnostic: once per hovered square, report whether the
                    --hovered tile is in the captured legal-tile set (the exact tiles the
                    --forced-move radius highlights) and whether enforcement is active.
                    --Throttled by loc to avoid log spam. Safe to remove once verified.
                    do
                        local dk = tostring(loc and loc.str or "nil")
                        if element.data._strictMoveDiagKey ~= dk then
                            element.data._strictMoveDiagKey = dk
                            print(string.format("[STRICTMOVE] hover=%s forcedmove=%s enforceActive=%s legalSet=%s inLegalSet=%s rejected=%s",
                                tostring(loc and loc.str or "nil"),
                                tostring(g_currentSymbols.forcedmovement or g_currentAbility:try_get("forcedMovement", "?")),
                                tostring(ForcedMoveEnforcementActive()),
                                tostring(g_forcedMoveLegalLocs ~= nil and "set" or "nil"),
                                tostring(g_forcedMoveLegalLocs ~= nil and loc ~= nil and (g_forcedMoveLegalLocs[loc.xyfloorOnly.str] == true)),
                                tostring((targetingType == "straightline") and ForcedMoveLocRejected(loc))))
                        end
                    end

                    --Strict movement: a player may not preview a forced move to a square
                    --outside the tiles the forced-move radius highlights (g_forcedMoveLegalLocs,
                    --captured from the identical engine computation that draws the radius).
                    local movementInfo = nil
                    if not ((targetingType == "straightline") and ForcedMoveLocRejected(loc)) then
                        movementInfo = g_token:MarkMovementArrow(loc, {
                            straightline = true,
                            ignorecreatures = (targetingType == "straightpathignorecreatures" or throughCreatures),
                            rebound = reboundOptions.rebound,
                            maxBounces = reboundOptions.maxBounces,
                            forcedMovementDistance = previewForcedDist,
                            slide = (g_currentSymbols.forcedmovement or g_currentAbility:try_get("forcedMovement")) == "vertical_slide",
                        })
                    end

                    if movementInfo ~= nil then
                        local targets = g_currentAbility:FindTargetsInMovementVicinity(g_token, movementInfo.path) or
                            filteredTargets
                        for _, target in ipairs(targets) do
                            filteredTargets[target.id] = target
                        end

                        --Broadcast OA warning arrows for straightpath movement (e.g. Charge),
                        --but NOT for straightline targeting (forced push/pull/slide). The token-
                        --side handler in DrawSteelTokenHud.lua additionally filters by movementType
                        --so teleport/shift abilities are a no-op.
                        if targetingType ~= "straightline" then
                            local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                            BroadcastMovementPlan(g_token, movementInfo.path, movementType)
                            g_pointTargeting.showingWarningArrows = true
                            clearWarningArrows = false
                        end
                    end
                    --Only keep an arrow drawn when one was actually previewed. When a
                    --strict-movement reject suppressed it, leave clearMovementArrow at
                    --its default so any arrow from the previous frame is removed.
                    if movementInfo ~= nil then
                        g_pointTargeting.showingMovementArrow = true
                        clearMovementArrow = false
                    end

                    if movementInfo ~= nil then
                        local path = movementInfo.path

                        --Predicted damage numbers for the movement cross-section diagram,
                        --recorded where the map labels below compute them so the diagram
                        --shows exactly the same red "-N" annotations (see the
                        --ShowMovementDiagram call at the end of this block).
                        local diagramCollisionDamage = nil
                        local diagramFallDamage = nil
                        local abilityDist = g_currentAbility:GetRange(g_token.properties, g_currentSymbols) /
                            dmhub.unitsPerSquare
                        g_currentSymbols.range = abilityDist
                        local requestDist = math.min(loc:DistanceInTiles(path.origin), abilityDist)
                        local pathDist = path.destination:DistanceInTiles(path.origin)

                        -- If the path is actually blocked (collision with wall/creature),
                        -- use full ability distance so collision force preview reflects max available force.
                        if path.hasCollision and requestDist < abilityDist then
                            requestDist = abilityDist
                        end

                        if pathDist < requestDist and (g_currentAbility:try_get("targeting", "direct") == "straightline") and g_token.properties:CalculateNamedCustomAttribute("No Damage From Forced Movement") == 0 then
                            local prevOvershoot = g_pointTargeting.pathEndOvershoot

                            --Prefer the engine-reported force remaining at the collision
                            --(distance travelled and wall-break stamina already deducted).
                            --The tile-distance fallback below is 2D only, so it miscounts
                            --vertical trajectories -- e.g. a vertical pull banging into the
                            --ceiling. Mirrors the cast flow in AbilityRelocateCreature.
                            local overshoot = requestDist - pathDist
                            if path.collisionForce ~= nil and path.collisionForce >= 0 then
                                overshoot = path.collisionForce
                            end
                            g_pointTargeting.pathEndOvershoot = overshoot

                            local prevPathEnd = g_pointTargeting.shapePathEnd
                            destroyLabelsBeforeReturning = false

                            local destPoint = path.destination.point3
                            if g_token.creatureDimensions.x % 2 == 0 then
                                local offset = (g_token.creatureDimensions.x - 1) * 0.5
                                destPoint = core.Vector3(destPoint.x + offset, destPoint.y + offset, destPoint.z)
                            end

                            local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                            g_currentSymbols.range = range

                            g_pointTargeting.shapePathEnd = {
                                dmhub.CalculateShape {
                                    shape = cond(g_token.creatureDimensions.x % 2 == 1, "radius", "cylinder"),
                                    token = g_currentAbility:GetRangeSource(g_token),
                                    targetPoint = destPoint,
                                    range = range,
                                    radius = g_token.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                                }
                            }

                            local collideWith = movementInfo.collideWith or {}

                            --implement increase of collide damage if we collide into an object.
                            local collideDamage = g_pointTargeting.pathEndOvershoot

                            local isObject = true
                            for _, collideToken in ipairs(collideWith) do
                                if not collideToken.isObject then
                                    isObject = false
                                    break
                                end
                            end

                            if isObject then
                                collideDamage = collideDamage + 2
                            end

                            --objects flagged "No Collision Damage" run their own collision
                            --behavior, so no standard collision damage is dealt in either
                            --direction and the preview must not promise any. Mirrors the
                            --suppressCollisionDamage rule in AbilityRelocateCreature.
                            local suppressDamage = #collideWith > 0
                            for _, collideToken in ipairs(collideWith) do
                                if not TargetableObject.TokenSuppressesCollisionDamage(collideToken) then
                                    suppressDamage = false
                                    break
                                end
                            end

                            if not suppressDamage then
                                diagramCollisionDamage = collideDamage
                            end

                            local textLabels = {}
                            if not suppressDamage then
                                textLabels[#textLabels + 1] = {
                                    point = destPoint,
                                    text = string.format("-%d<color=#00000000>-</color>", collideDamage),
                                }
                            end

                            for _, collideToken in ipairs(collideWith) do
                                local targetPoint = collideToken:PosAtLoc()
                                g_pointTargeting.shapePathEnd[#g_pointTargeting.shapePathEnd + 1] = dmhub.CalculateShape {
                                    shape = cond(collideToken.creatureDimensions.x % 2 == 1, "radius", "radiusfromintersection"),
                                    token = collideToken,
                                    targetPoint = collideToken:PosAtLoc(),
                                    range = 0,
                                    radius = collideToken.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                                }

                                if not suppressDamage then
                                    textLabels[#textLabels + 1] = {
                                        point = collideToken:PosAtLoc(),
                                        text = string.format("-%d<color=#00000000>-</color>", collideDamage),
                                    }
                                end
                            end

                            local needRedraw = prevPathEnd == nil or #prevPathEnd ~= #g_pointTargeting.shapePathEnd or
                                prevOvershoot ~= g_pointTargeting.pathEndOvershoot
                            if not needRedraw then
                                for i, loc in ipairs(prevPathEnd) do
                                    if loc.str ~= g_pointTargeting.shapePathEnd[i].str then
                                        needRedraw = true
                                        break
                                    end
                                end
                            end

                            if needRedraw then
                                if g_pointTargeting.labelsAtPathEnd ~= nil then
                                    for _, marker in ipairs(g_pointTargeting.labelsAtPathEnd) do
                                        marker:Destroy()
                                    end
                                    g_pointTargeting.labelsAtPathEnd = nil
                                    destroyLabelsBeforeReturning = false
                                end

                                g_pointTargeting.labelsAtPathEnd = {}
                                for i, loc in ipairs(g_pointTargeting.shapePathEnd) do
                                    g_pointTargeting.labelsAtPathEnd[#g_pointTargeting.labelsAtPathEnd + 1] =
                                        g_pointTargeting.shapePathEnd
                                        [i]:Mark { color = "red", video = "divinationline.webm", showLocs = false }
                            print("MARK:: MARK SHAPE")
                                end

                                for i, info in ipairs(textLabels) do
                                    g_pointTargeting.labelsAtPathEnd[#g_pointTargeting.labelsAtPathEnd + 1] = dmhub
                                        .CreateCanvasOnMap {
                                            point = info.point,
                                            sheet = gui.Label {
                                                interactable = false,
                                                halign = "center",
                                                valign = "center",
                                                color = "red",
                                                width = "auto",
                                                height = "auto",
                                                fontSize = 0.5,
                                                text = info.text,
                                            }
                                        }
                                end
                            end
                        end

                        --show damage indicators at each rebound bounce point.
                        if movementInfo.bounceCollisions ~= nil and #movementInfo.bounceCollisions > 0 and (g_currentAbility:try_get("targeting", "direct") == "straightline") and g_token.properties:CalculateNamedCustomAttribute("No Damage From Forced Movement") == 0 then
                            local prevPathEnd = g_pointTargeting.shapePathEnd
                            destroyLabelsBeforeReturning = false
                            g_pointTargeting.shapePathEnd = g_pointTargeting.shapePathEnd or {}
                            local bounceTextLabels = {}

                            for _, collision in ipairs(movementInfo.bounceCollisions) do
                                local bounceCollideWith = collision.collideWith or {}
                                local bounceDamage = collision.speed
                                local bounceIsObject = #bounceCollideWith == 0
                                if bounceIsObject then
                                    bounceDamage = bounceDamage + 2
                                end

                                --see the note on suppressDamage above.
                                local suppressBounceDamage = #bounceCollideWith > 0
                                for _, collideToken in ipairs(bounceCollideWith) do
                                    if not TargetableObject.TokenSuppressesCollisionDamage(collideToken) then
                                        suppressBounceDamage = false
                                        break
                                    end
                                end

                                local bounceDestPoint = collision.destination.point3
                                if g_token.creatureDimensions.x % 2 == 0 then
                                    local offset = (g_token.creatureDimensions.x - 1) * 0.5
                                    bounceDestPoint = core.Vector3(bounceDestPoint.x + offset, bounceDestPoint.y + offset, bounceDestPoint.z)
                                end

                                g_pointTargeting.shapePathEnd[#g_pointTargeting.shapePathEnd + 1] = dmhub.CalculateShape {
                                    shape = cond(g_token.creatureDimensions.x % 2 == 1, "radius", "cylinder"),
                                    token = g_currentAbility:GetRangeSource(g_token),
                                    targetPoint = bounceDestPoint,
                                    range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols),
                                    radius = g_token.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                                }

                                if not suppressBounceDamage then
                                    bounceTextLabels[#bounceTextLabels + 1] = {
                                        point = bounceDestPoint,
                                        text = string.format("-%d<color=#00000000>-</color>", bounceDamage),
                                    }
                                end

                                for _, collideToken in ipairs(bounceCollideWith) do
                                    g_pointTargeting.shapePathEnd[#g_pointTargeting.shapePathEnd + 1] = dmhub.CalculateShape {
                                        shape = cond(collideToken.creatureDimensions.x % 2 == 1, "radius", "radiusfromintersection"),
                                        token = collideToken,
                                        targetPoint = collideToken:PosAtLoc(),
                                        range = 0,
                                        radius = collideToken.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                                    }
                                    if not suppressBounceDamage then
                                        bounceTextLabels[#bounceTextLabels + 1] = {
                                            point = collideToken:PosAtLoc(),
                                            text = string.format("-%d<color=#00000000>-</color>", bounceDamage),
                                        }
                                    end
                                end
                            end

                            local needRedraw = prevPathEnd == nil or #prevPathEnd ~= #g_pointTargeting.shapePathEnd
                            if needRedraw then
                                if g_pointTargeting.labelsAtPathEnd ~= nil then
                                    for _, marker in ipairs(g_pointTargeting.labelsAtPathEnd) do
                                        marker:Destroy()
                                    end
                                    destroyLabelsBeforeReturning = false
                                end

                                g_pointTargeting.labelsAtPathEnd = g_pointTargeting.labelsAtPathEnd or {}
                                for i, shape in ipairs(g_pointTargeting.shapePathEnd) do
                                    g_pointTargeting.labelsAtPathEnd[#g_pointTargeting.labelsAtPathEnd + 1] =
                                        shape:Mark { color = "red", video = "divinationline.webm", showLocs = false }
                                end
                                for i, info in ipairs(bounceTextLabels) do
                                    g_pointTargeting.labelsAtPathEnd[#g_pointTargeting.labelsAtPathEnd + 1] = dmhub
                                        .CreateCanvasOnMap {
                                            point = info.point,
                                            sheet = gui.Label {
                                                interactable = false,
                                                halign = "center",
                                                valign = "center",
                                                color = "red",
                                                width = "auto",
                                                height = "auto",
                                                fontSize = 0.5,
                                                text = info.text,
                                            }
                                        }
                                end
                            end
                        end

                        --show damage indicators on creatures passed through.
                        if throughCreatures and path.steps ~= nil then
                            local throughTextLabels = {}
                            local throughShapes = {}
                            local hitIds = {}
                            for _, step in ipairs(path.steps) do
                                local tokensAtLoc = game.GetTokensAtLoc(step)
                                for _, tok in ipairs(tokensAtLoc or {}) do
                                    if tok.id ~= g_token.id and hitIds[tok.id] == nil then
                                        hitIds[tok.id] = true
                                        throughShapes[#throughShapes + 1] = dmhub.CalculateShape {
                                            shape = cond(tok.creatureDimensions.x % 2 == 1, "radius", "radiusfromintersection"),
                                            token = tok,
                                            targetPoint = tok:PosAtLoc(),
                                            range = 0,
                                            radius = tok.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                                        }
                                        throughTextLabels[#throughTextLabels + 1] = {
                                            point = tok:PosAtLoc(),
                                            text = string.format("-%d<color=#00000000>-</color>", 1),
                                        }
                                    end
                                end
                            end

                            if #throughShapes > 0 then
                                destroyThroughCreatureLabels = false
                                if g_pointTargeting.labelsAtThroughCreatures ~= nil then
                                    for _, marker in ipairs(g_pointTargeting.labelsAtThroughCreatures) do
                                        marker:Destroy()
                                    end
                                end
                                g_pointTargeting.labelsAtThroughCreatures = {}
                                for i, shape in ipairs(throughShapes) do
                                    g_pointTargeting.labelsAtThroughCreatures[#g_pointTargeting.labelsAtThroughCreatures + 1] =
                                        shape:Mark { color = "red", video = "divinationline.webm", showLocs = false }
                                end
                                for i, info in ipairs(throughTextLabels) do
                                    g_pointTargeting.labelsAtThroughCreatures[#g_pointTargeting.labelsAtThroughCreatures + 1] = dmhub
                                        .CreateCanvasOnMap {
                                            point = info.point,
                                            sheet = gui.Label {
                                                interactable = false,
                                                halign = "center",
                                                valign = "center",
                                                color = "red",
                                                width = "auto",
                                                height = "auto",
                                                fontSize = 0.5,
                                                text = info.text,
                                            }
                                        }
                                end
                            end
                        end

                        --Red damage number when the previewed move ends in a damaging fall --
                        --e.g. a vertical pull upward that leaves the creature in mid-air (or
                        --banging into the ceiling), or a push off a ledge. Shown at the landing
                        --square, offset below so it never overlaps a collision number at the
                        --same square. Flyers don't fall, and the actual damage comes from the
                        --Falling global rule when the move resolves.
                        local fallDamage = 0
                        local fallDist = path.fallDistance or 0
                        if fallDist > 0 and not g_token.properties:CanFly() then
                            fallDamage = g_token.properties:PredictedFallDamage(fallDist, path.landsInWater)
                        end

                        if fallDamage > 0 then
                            diagramFallDamage = fallDamage
                            destroyFallDamageLabel = false
                            local fallKey = path.destination.str .. "|" .. fallDamage
                            if g_pointTargeting.fallDamageKey ~= fallKey then
                                if g_pointTargeting.fallDamageLabel ~= nil then
                                    g_pointTargeting.fallDamageLabel:Destroy()
                                end

                                local landPoint = path.destination.point3
                                if g_token.creatureDimensions.x % 2 == 0 then
                                    local offset = (g_token.creatureDimensions.x - 1) * 0.5
                                    landPoint = core.Vector3(landPoint.x + offset, landPoint.y + offset, landPoint.z)
                                end
                                landPoint = core.Vector3(landPoint.x, landPoint.y - 0.7, landPoint.z)

                                g_pointTargeting.fallDamageLabel = dmhub.CreateCanvasOnMap {
                                    point = landPoint,
                                    sheet = gui.Label {
                                        interactable = false,
                                        halign = "center",
                                        valign = "center",
                                        color = "red",
                                        width = "auto",
                                        height = "auto",
                                        fontSize = 0.5,
                                        text = string.format("-%d<color=#00000000>-</color>", fallDamage),
                                    }
                                }
                                g_pointTargeting.fallDamageKey = fallKey
                            end
                        end

                        --Forced-move targeting (push/pull/slide): show the same floating
                        --movement tooltip + cross-section diagram the manual token-drag
                        --uses, annotated with the predicted collision/fall damage numbers
                        --computed above so the diagram draws the same red "-N" labels as
                        --the map. Only for straightline (true forced movement) --
                        --straightpath (Charge) and other movement previews are left alone.
                        --Cleared below when the movement arrow is cleared (mouse off a
                        --valid square) and on targeting teardown via ClearPointTargeting.
                        if targetingType == "straightline" then
                            ShowMovementDiagram(g_token, path, tr("Forced Movement"), nil,
                                { collision = diagramCollisionDamage, fall = diagramFallDamage })
                        end

                        --falling.
                        local fallInfo = g_token:GetFallInfoFromLoc(loc)
                        if fallInfo ~= nil then
                            local fallShape = dmhub.CalculateShape {
                                shape = "radius",
                                token = g_token,
                                locOverride = fallInfo.loc,
                                targetPoint = g_token:PosAtLoc(fallInfo.loc),
                                radius = g_token.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                            }

                            g_pointTargeting.fallingShape = fallShape:Mark { color = "red", video = "divinationline.webm" }
                            print("MARK:: MARK SHAPE")
                        end
                    end
                end

                if point == 'all' then
                    --this is for the 'all' target type, targeting within the caster.
                    radius = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                    g_currentSymbols.range = radius
                    point = nil
                    shape = "RadiusFromCreature"
                end
                if shape == 'emptyspace' or shape == 'emptyspacefriend' or shape == 'anyspace' then
                    radius = dmhub.unitsPerSquare * 0.5
                    requireEmpty = (shape == 'emptyspace')

                    --Forced movement (straightline targeting): a square occupied by
                    --another creature is a legal destination click
                    if requireEmpty and targetingType == "straightline" then
                        requireEmpty = false
                    end

                    if (shape == "emptyspace" or shape == "anyspace") then
                        radius = g_token.creatureDimensions.x * dmhub.unitsPerSquare * 0.5
                        if g_token.creatureDimensions.x % 2 == 1 then
                            shape = "radius"
                        else
                            --if we are an even number of tiles wide, we want to target a tile intersection
                            --we offset the target point to match creature movement behavior.
                            shape = "cylinder"
                            local offset = (g_token.creatureDimensions.x - 1) * 0.5
                            point = core.Vector3(point.x + offset, point.y + offset, point.z)
                        end
                    else
                        shape = "radius"
                    end

                    if #m_positionTargetsChosen > 0 and (g_currentAbility.targeting == "contiguous" or g_currentAbility.targeting == "contiguous_wall") then
                        shape = "locations"
                    end
                end

                local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                g_currentSymbols.range = range
                if shape == "line" and g_currentAbility.canChooseLowerRange then
                    local pos = g_token:PosAtLoc(g_token.loc)
                    local dist = math.ceil(math.max(math.abs(point.x - pos.x), math.abs(point.y - pos.y)))
                    range = math.min(range, dist)
                end

                local numTargets = 1
                if g_currentAbility ~= nil then
                    numTargets = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                end

                if numTargets > 1 or targetingType == "pathfind" or (g_pointTargeting.shapeConfirmedLoc ~= nil and g_pointTargeting.shapeConfirmedLoc.str == startingLoc.str) then
                    g_pointTargeting.shapeRequiresConfirm = false
                else
                    g_pointTargeting.shapeRequiresConfirm = true
                end

                local locOverride = nil
                if shape == "line" and #m_positionTargetsChosen == 0 then
                    shape = "radius"
                    radius = 0
                elseif shape == "line" then
                    locOverride = m_positionTargetsChosen[1]
                end

                local locations = nil
                if shape == "locations" then
                    locations = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        locations[#locations + 1] = pos.loc
                    end
                    --add the current location in too, provisionally.
                    locations[#locations+1] = loc
                end

                --For direct emptyspace/anyspace targeting (teleport-style), let the cursor rest on
                --whichever floor it's hovering and render the radius preview there. Movement-style
                --targeting (pathfind/vacated/straightline) stays floor-bound -- the engine's
                --pathfinding doesn't traverse floors.
                local targetFloorIndex = nil
                if loc ~= nil and targetingType == "direct" and (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") then
                    targetFloorIndex = loc.floor
                end

                --diagnostic: cross-floor targeting trace - throttled to floor changes only.
                if g_currentAbility ~= nil and (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") then
                    local k = string.format("%s|%s|%s", tostring(targetFloorIndex), tostring(point and point.z or "nil"), tostring(shape))
                    if element.data._lastXFloorShapeKey ~= k then
                        element.data._lastXFloorShapeKey = k
                        print(string.format("XFLOOR:: pre-CalculateShape shape=%s targetPoint=(%s,%s,%s) targetFloorIndex=%s caster.floor=%s",
                            tostring(shape),
                            tostring(point and point.x or "nil"),
                            tostring(point and point.y or "nil"),
                            tostring(point and point.z or "nil"),
                            tostring(targetFloorIndex),
                            tostring(g_token and g_token.floorIndex or "nil")))
                    end
                end

                --For cube targeting, anchor the cube's bottom at the altitude the
                --altitude controller has resolved on the hovered loc (ground by default,
                --or a fixed value the user dialed in). Engine expects altitude in game
                --units. Other shapes leave altitude nil so engine defaults apply.
                local shapeAltitude = nil
                if shape == "cube" and loc ~= nil then
                    shapeAltitude = loc.altitude * dmhub.unitsPerSquare
                end

                g_pointTargeting.shape = dmhub.CalculateShape {
                    shape = shape,
                    targetPoint = point,
                    token = g_token,
                    range = range,
                    radius = radius,
                    --contiguous selection ("locations" shape): do NOT line-of-sight
                    --filter the preview. The shape's LOS origin is the first chosen
                    --square, and with live wall building that square contains the
                    --wall cube just built -- its own walls gave Full cover to every
                    --orthogonally adjacent square, silently filtering the chosen and
                    --legal squares out of the outline. Adjacency/range are validated
                    --on click instead.
                    checklos = (shape ~= "locations"),
                    locOverride = locOverride or g_currentAbility:try_get("casterLocOverride"),
                    requireEmpty = requireEmpty,
                    emptyMayIncludeSelf = requireEmpty and (targetingType == "pathfind" or targetingType == "vacated" or targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures"),
                    locations = locations,
                    targetFloorIndex = targetFloorIndex,
                    altitude = shapeAltitude,
                }

                -- Partner burst: if the ability declares partnerBurst (a GoblinScript
                -- condition formula that evaluates true) and we're doing a
                -- RadiusFromCreature burst around the caster, also build a second
                -- RadiusFromCreature shape around the caster's summoner so e.g.
                -- companion abilities can extend a burst to both the companion and
                -- the player character ("This ability also affects a 2 burst
                -- originating from you" -- Beastheart's Bring the Thunder).
                g_pointTargeting.partnerShape = nil
                g_pointTargeting.partnerCasterToken = nil
                if shape == "RadiusFromCreature" then
                    local partnerBurst = g_currentAbility:try_get("partnerBurst", "")
                    if partnerBurst ~= "" then
                        local condResult = ExecuteGoblinScript(partnerBurst, g_token.properties:LookupSymbol(g_currentSymbols), 0, "Partner burst condition")
                        if tonumber(condResult) ~= 0 then
                            -- Resolve the "partner" token. The partner burst works
                            -- in either direction along the beastheart/companion
                            -- link:
                            --   * If the caster is a summoned creature (a companion
                            --     casting Bring the Thunder), the partner is its
                            --     summoner -- the beastheart. summonerid lives on
                            --     the TOKEN (mirrors applyto:caster_summoner in
                            --     ActivatedAbility.lua's ApplyToTargets).
                            --   * Otherwise the partner is the caster's companion
                            --     (the beastheart casting All of You Versus All of
                            --     Me). companionid lives on the creature props;
                            --     GetCompanionToken returns nil when there is none.
                            local partnerToken = nil
                            local summonerid = g_token.summonerid
                            if summonerid ~= nil and summonerid ~= "" then
                                partnerToken = dmhub.GetTokenById(summonerid)
                            elseif g_token.properties.GetCompanionToken ~= nil then
                                partnerToken = g_token.properties:GetCompanionToken()
                            end
                            if partnerToken ~= nil and partnerToken.valid then
                                g_pointTargeting.partnerShape = dmhub.CalculateShape {
                                    shape = "RadiusFromCreature",
                                    token = partnerToken,
                                    range = range,
                                    radius = radius,
                                    checklos = true,
                                }
                                g_pointTargeting.partnerCasterToken = partnerToken
                                --Membership is computed from this radius rather than
                                --from the shape: TokensInShape on a companion-centred
                                --RadiusFromCreature returns only the companion itself
                                --(verified against the live map), so the shape is kept
                                --for rendering only. See the union below.
                                g_pointTargeting.partnerBurstRadius = radius
                            end
                        end
                    end
                end
            elseif g_currentAbility.targetType == "map" then
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shape = dmhub.CalculateShape {
                    shape = "map",
                    token = g_token,
                }
            elseif g_currentAbility.targetType == "areatemplate" then
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shape = dmhub.CalculateShape {
                    shape = "areatemplate",
                    token = g_token,
                    objectTemplate = g_currentAbility:try_get("areaTemplateObjectId"),
                }
            else
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shape = nil
            end

            g_currentSymbols.targetArea = g_pointTargeting.shape

            local selfTarget = g_currentAbility.selfTarget
            local targetTokens = dmhub.tokenInfo.TokensInShape(g_pointTargeting.shape)

            -- Partner burst: union tokens from the partner shape into the target dict.
            -- Same-key entries dedupe automatically -- "An enemy in both areas is
            -- only affected once" (Bring the Thunder rules). Also track which
            -- tokens are ONLY in the partner shape (not in the caster's shape) so
            -- that forced movement against them is sourced from the partner caster
            -- (the beastheart) rather than the original caster (the panther) --
            -- pushes go "away from the right creature."
            g_pointTargeting.partnerOnlyTokenIds = nil
            if g_pointTargeting.partnerShape ~= nil then
                --Membership by distance from the partner, NOT TokensInShape: the
                --engine returns an empty set for a companion-centred
                --RadiusFromCreature, so every partner-only enemy silently fell out
                --of the target list. DistanceInTiles is Chebyshev, which is the
                --burst's own metric. Line of sight from the partner mirrors the
                --shape's checklos so a burst still does not reach through a wall.
                local partnerTokens = {}
                local partnerCaster = g_pointTargeting.partnerCasterToken
                local burstRadius = g_pointTargeting.partnerBurstRadius
                if partnerCaster ~= nil and partnerCaster.valid and burstRadius ~= nil then
                    local pierceWalls = partnerCaster.properties:GetPierceWalls()
                    for _, tok in ipairs(dmhub.GetTokens()) do
                        if tok.valid and tok.floorIndex == partnerCaster.floorIndex
                            and partnerCaster.loc:DistanceInTiles(tok.loc) <= burstRadius
                            and partnerCaster:GetLineOfSight(tok, pierceWalls) > 0 then
                            partnerTokens[tok.charid] = tok
                        end
                    end
                end
                local partnerOnly = {}
                local anyPartnerOnly = false
                for k, tok in pairs(partnerTokens) do
                    if targetTokens[k] == nil then
                        partnerOnly[tok.charid] = true
                        anyPartnerOnly = true
                    end
                    targetTokens[k] = tok
                end
                if anyPartnerOnly then
                    g_pointTargeting.partnerOnlyTokenIds = partnerOnly
                end
            end

            --if we target the entire map or burst, do not target creatures on other floors unless they are in initiative.
            if (g_currentAbility.targetType == "map" or g_currentAbility.targetType == "all") and dmhub.initiativeQueue ~= nil and (not dmhub.initiativeQueue.hidden) then
                local casterFloorIndex = g_token.floorIndex
                for tokenid,targetToken in pairs(targetTokens) do
                    if not targetToken.isObject then
                        local isOtherFloor = targetToken.floorIndex ~= casterFloorIndex
                        local requireInitiative = g_currentAbility.targetType == "map" or isOtherFloor

                        if requireInitiative then
                            local initiativeid = InitiativeQueue.GetInitiativeId(targetToken)
                            if not dmhub.initiativeQueue:HasInitiative(initiativeid) then
                                targetTokens[tokenid] = nil
                            end
                        end
                    end
                end
            end
            if not pathfinding then
                for k, tok in pairs(targetTokens) do
                    -- "Can Target Self" flag lets the caster appear among its own candidates
                    -- alongside others (self OR adjacent in one prompt); see ActivatedAbility:TargetPassesFilter.
                    if (selfTarget or tok.charid ~= g_token.charid or g_token.properties:CalculateNamedCustomAttribute("Can Target Self") > 0) and g_currentAbility:TargetPassesFilter(g_token, tok, g_currentSymbols) then
                        filteredTargets[k] = tok
                    end
                end
            end
            SetTargetsInRadius(filteredTargets)

            if g_pointTargeting.radius ~= nil then
                if g_pointTargeting.shape ~= nil and g_pointTargeting.shape:Equal(prevShape) then
                    --shape unchanged.
                    --return
                end

                g_pointTargeting.radius:Destroy()
                g_pointTargeting.radius = nil
            end

            -- Destroy any prior partner-burst marker; re-marked below if still applicable.
            if g_pointTargeting.partnerRadius ~= nil then
                g_pointTargeting.partnerRadius:Destroy()
                g_pointTargeting.partnerRadius = nil
            end

            if g_pointTargeting.label ~= nil then
                g_pointTargeting.label:Destroy()
                g_pointTargeting.label = nil
            end

            --draw the shape, disabled for 'all creatures on map'
            if g_pointTargeting.shape ~= nil and g_currentAbility.targetType ~= "map" then
                local video = "divinationline.webm"
                local school = string.lower(g_currentAbility:try_get("school", ""))
                if school == "Evocation" then
                    video = "fire-radius.webm"
                elseif school == "Illusion" then
                    video = "illusionline.webm"
                end

                if g_pointTargeting.shapeRequiresConfirm then
                    targetColor = "#444444"
                end

                g_pointTargeting.radius = g_pointTargeting.shape:Mark { color = targetColor, video = video }

                -- Render the partner-burst with the same styling so the player can see
                -- both areas at once.
                if g_pointTargeting.partnerShape ~= nil then
                    g_pointTargeting.partnerRadius = g_pointTargeting.partnerShape:Mark { color = targetColor, video = video }
                end

                --Strict movement: suppress the "Click to Confirm" affordance when a
                --player is hovering a square outside the tiles the forced-move radius
                --highlights, so it doesn't invite a click that will be rejected. The
                --radius itself still renders.
                local strictConfirmReject = (g_currentAbility ~= nil)
                    and (g_currentAbility:try_get("targeting", "direct") == "straightline")
                    and ForcedMoveLocRejected(loc)
                if g_currentAbility ~= nil and loc ~= nil and g_pointTargeting.shape ~= nil and (not strictConfirmReject) then
                    local numTargets = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)

                    local clickText = cond(numTargets == 1, "Click to Confirm", "")
                    local targetingType = g_currentAbility:try_get("targeting", "direct")
                    if g_currentAbility.targetType == "line" and #m_positionTargetsChosen == 0 then
                        clickText = "Select Line Start"
                    elseif targetingType == "pathfind" then
                        local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                        clickText = string.upper_first(movementType or "Move")

                        if m_positionTargetsChosen ~= nil and #m_positionTargetsChosen > 0 then
                            local lastPos = m_positionTargetsChosen[#m_positionTargetsChosen].loc
                            if lastPos.x == loc.x and lastPos.y == loc.y then
                                clickText = "Click to Confirm"
                            end
                        end
                    elseif g_pointTargeting.shapeRequiresConfirm then
                        clickText = g_currentAbility:DescribeTargetText(g_currentSymbols)
                    end

                    --Tiered jump: tell the player this tile needs a test (lower
                    --tiers land short -- on the marked shortfall tiles), or that
                    --no tier reaches it at all.
                    if g_jumpHoverUnreachable and clickText ~= "" then
                        clickText = tr("Cannot Reach")
                    elseif g_jumpHoverRequiredTier ~= nil and g_jumpHoverRequiredTier > 1 and clickText ~= "" then
                        clickText = string.format(tr("Needs Tier %d - Click to Roll"), g_jumpHoverRequiredTier)
                    end

                    --Wall building: the hovered square's voxel column already
                    --reaches the floor's ceiling, so a click will be refused --
                    --tell the player why.
                    if g_currentAbility.targeting == "contiguous_wall" and loc ~= nil then
                        local buildWall = rawget(_G, "ActivatedAbilityBuildWallBehavior")
                        if buildWall ~= nil and buildWall.StackedToCeiling ~= nil and buildWall.StackedToCeiling(loc) then
                            clickText = tr("Walls Stacked to Ceiling")
                        end
                    end

                    local locs = g_pointTargeting.shape.locations
                    if locs == nil or #locs == 0 then
                        locs = { { withGroundAltitude = { point3 = point } } }
                    end
                    local point = locs[1].withGroundAltitude.point3
                    local minx = point.x
                    local miny = point.y
                    local maxx = point.x
                    local maxy = point.y
                    for i = 2, #locs do
                        point.x = point.x + locs[i].withGroundAltitude.point3.x
                        point.y = point.y + locs[i].withGroundAltitude.point3.y
                        point.z = point.z + locs[i].withGroundAltitude.point3.z

                        minx = math.min(minx, locs[i].withGroundAltitude.point3.x)
                        miny = math.min(miny, locs[i].withGroundAltitude.point3.y)
                        maxx = math.max(maxx, locs[i].withGroundAltitude.point3.x)
                        maxy = math.max(maxy, locs[i].withGroundAltitude.point3.y)
                    end

                    local w = 1 + maxx - minx
                    local h = 1 + maxy - miny

                    point.x = point.x / #locs
                    point.y = point.y / #locs
                    point.z = point.z / #locs

                    --pass loc.floor so the canvas's z is offset by the target floor's base
                    --altitude (cross-floor targeting renders the label on the right floor).
                    --For cube targeting, also pass the cube's altitude (in tiles) so the
                    --label parallaxes up with the cube outline (HighlightPerimeter pins the
                    --cube perimeter mesh Z to the same altitude). loc.altitude is already
                    --whatever the altitude controller resolved (ground or fixed value).
                    --Override point.z to the cube altitude so the canvas lives at the cube
                    --in 3D world space (point.z averaged ground altitude otherwise, which
                    --would put the label below the cube outline).
                    local labelAltitude = nil
                    if loc ~= nil and g_currentAbility.targetType == "cube" then
                        labelAltitude = loc.altitude
                        point.z = loc.altitude
                    end
                    g_pointTargeting.label = dmhub.CreateCanvasOnMap {
                        point = point, --loc.point3,
                        floorIndex = loc and loc.floor or nil,
                        altitude = labelAltitude,
                        sheet = gui.Panel {
                            interactable = false,
                            halign = "center",
                            valign = "center",
                            width = w,
                            height = h,
                            gui.Label {
                                interactable = false,
                                floating = true,
                                valign = "center",
                                halign = "center",
                                width = "80%",
                                height = "auto",
                                fontSize = 0.15,
                                color = "white",
                                text = clickText,
                                textAlignment = "center",
                            },
                            gui.Label {
                                interactable = false,
                                floating = true,
                                valign = "bottom",
                                halign = "center",
                                width = "auto",
                                height = 0.1,
                                y = 0.15,
                                fontSize = 0.15,
                                color = "white",
                                text = g_currentSymbols.spellname or g_currentAbility.name,
                            },
                        }
                    }
                end
            end

            if clearMovementArrow then
                if g_token ~= nil then
                    g_token:ClearMovementArrow()
                    g_pointTargeting.showingMovementArrow = false
                end
                --tear down the movement cross-section tooltip whenever the movement
                --arrow is cleared (no valid destination square under the cursor).
                ClearMovementDiagram()
            end

            if clearWarningArrows and g_token ~= nil then
                BroadcastMovementPlan(g_token, nil, nil)
                g_pointTargeting.showingWarningArrows = false
            end

            if destroyLabelsBeforeReturning then
                for _, marker in ipairs(g_pointTargeting.labelsAtPathEnd) do
                    marker:Destroy()
                end


                if g_pointTargeting.fallingShape ~= nil then
                    g_pointTargeting.fallingShape:Destroy()
                end

                g_pointTargeting.fallingShape = nil
                g_pointTargeting.labelsAtPathEnd = nil
                g_pointTargeting.shapePathEnd = nil
            end

            if destroyThroughCreatureLabels and g_pointTargeting ~= nil and g_pointTargeting.labelsAtThroughCreatures ~= nil then
                for _, marker in ipairs(g_pointTargeting.labelsAtThroughCreatures) do
                    marker:Destroy()
                end
                g_pointTargeting.labelsAtThroughCreatures = nil
            end

            if destroyFallDamageLabel and g_pointTargeting ~= nil and g_pointTargeting.fallDamageLabel ~= nil then
                g_pointTargeting.fallDamageLabel:Destroy()
                g_pointTargeting.fallDamageLabel = nil
                g_pointTargeting.fallDamageKey = nil
            end
        end,

        mappress = function(element, loc, point)
            if g_pointTargeting == nil then
                return
            end

            if g_token == nil or not g_token.valid then return end
            if g_currentAbility == nil then return end

            local shape = g_currentAbility.targetType

            --diagnostic: cross-floor targeting trace.
            print(string.format("XFLOOR:: mappress entry loc=%s loc.floor=%s caster.floor=%s shape=%s targeting=%s shapeRequiresConfirm=%s",
                tostring(loc and loc.str or "nil"),
                tostring(loc and loc.floor or "nil"),
                tostring(g_token and g_token.floorIndex or "nil"),
                tostring(shape),
                tostring(g_currentAbility:try_get("targeting", "direct")),
                tostring(g_pointTargeting.shapeRequiresConfirm)))

            --set the starting point of the line.
            if shape == "line" and #m_positionTargetsChosen == 0 then
                m_positionTargetsChosen[#m_positionTargetsChosen + 1] = loc
                return
            end

            if loc ~= nil and (g_pointTargeting.shapeRequiresConfirm) and g_pointTargeting.shape ~= nil then
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shapeConfirmedLoc = loc
                print(string.format("XFLOOR:: mappress shape-confirm stored loc.floor=%s", tostring(loc.floor)))
                return
            end

            if m_allowedAltitudeCalculator ~= nil and loc ~= nil then
                local info = { loc = loc, point = point, panel = element }
                m_altitudeController:FireEventTree("loc", info)
                loc = info.loc
                print(string.format("XFLOOR:: mappress after altitude controller loc.floor=%s", tostring(loc and loc.floor or "nil")))
            end

            local locOverride = g_currentAbility:try_get("casterLocOverride")
            local targetingType = g_currentAbility:try_get("targeting", "direct")

            if (shape == 'emptyspace' or shape == 'anyspace') and (targetingType == "direct" or targetingType == "pathfind" or targetingType == "vacated" or targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures") then
                --adjust the position of the location if we are moving with a large creature.
                if g_token.creatureDimensions.x > 1 and g_token.creatureDimensions.x % 2 == 1 then
                    for i = 3, g_token.creatureDimensions.x, 2 do
                        loc = loc.west.south
                    end
                end
            end

            --Strict movement: a player (not the DM) may not target a forced-move square
            --outside the tiles the forced-move radius highlights (g_forcedMoveLegalLocs,
            --captured from the same engine computation that draws the radius). Tested after
            --the large-creature offset so it matches the loc the preview/append use.
            if targetingType == "straightline" and ForcedMoveLocRejected(loc) then
                return
            end

            print("WAYPOINT:: PRESS SHAPE:", g_pointTargeting.shape)
            if g_pointTargeting.shape ~= nil then
                local targets = m_positionTargetsChosen
                if g_currentAbility.targetType == "line" then
                    --line doesn't include the starting point as a target.
                    targets = {}
                end

                if g_currentAbility.targetType == 'emptyspace' or g_currentAbility.targetType == 'emptyspacefriend' or g_currentAbility.targetType == 'anyspace' then
                    print(string.format("XFLOOR:: mappress building emptyspace target loc.floor=%s", tostring(loc and loc.floor or "nil")))

                    --For multi-target emptyspace/anyspace abilities, clicking an already
                    --selected space deselects it instead of adding a duplicate.
                    --contiguous_wall targeting with wallStacking is the exception:
                    --re-clicking a chosen square STACKS another wall cube on it, so
                    --duplicates are welcome.
                    if (g_currentAbility.targetType == 'emptyspace' or g_currentAbility.targetType == 'anyspace')
                        and not (g_currentAbility.targeting == "contiguous_wall" and g_currentAbility.wallStacking)
                        and g_currentAbility:GetNumTargets(g_token, g_currentSymbols) > 1 and loc ~= nil then
                        local deselectedIndex = nil
                        for i, t in ipairs(targets) do
                            if t.loc ~= nil and t.loc.str == loc.str then
                                deselectedIndex = i
                                break
                            end
                        end
                        if deselectedIndex ~= nil then
                            local removed = targets[deselectedIndex]
                            table.remove(targets, deselectedIndex)

                            --wall abilities build live: deselecting a square removes
                            --the voxel that was placed there during targeting.
                            if g_currentAbility.targeting == "contiguous_wall" then
                                local buildWall = rawget(_G, "ActivatedAbilityBuildWallBehavior")
                                if buildWall ~= nil then
                                    buildWall.RemoveSquare(loc)
                                end
                            end

                            --only destroy the marker if we still track it: contiguous
                            --targeting calls ClearRadiusMarkers after every click, so
                            --the reference stored on the target may already be dead
                            --and destroying it again errors.
                            if removed.marker ~= nil then
                                for i = #g_radiusMarkers, 1, -1 do
                                    if g_radiusMarkers[i] == removed.marker then
                                        removed.marker:Destroy()
                                        table.remove(g_radiusMarkers, i)
                                        break
                                    end
                                end
                            end
                            local promptText = g_currentAbility:PromptText(g_token, targets, g_currentSymbols)
                            g_castMessage.data.promptText = promptText
                            g_castMessage:FireEvent("refresh")
                            return
                        end
                    end

                    --contiguous targeting ("wall N" and connected-spaces abilities):
                    --each square after the first must share a side with a square
                    --already chosen; the first square must be within the ability's
                    --range of the caster.
                    if loc ~= nil and (g_currentAbility.targeting == "contiguous" or g_currentAbility.targeting == "contiguous_wall") then
                        if #targets == 0 then
                            local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                            local rangeSource = g_currentAbility:GetRangeSource(g_token)
                            if rangeSource:Distance(loc) > range then
                                return
                            end
                        else
                            local adjacent = false
                            for _,t in ipairs(targets) do
                                if t.loc ~= nil and t.loc.floor == loc.floor then
                                    local dx = math.abs(t.loc.x - loc.x)
                                    local dy = math.abs(t.loc.y - loc.y)
                                    --same square (dx+dy == 0) means stacking another
                                    --cube there; allowed for wall targeting with stacking.
                                    if dx + dy == 1 or (dx + dy == 0 and g_currentAbility.targeting == "contiguous_wall" and g_currentAbility.wallStacking) then
                                        adjacent = true
                                        break
                                    end
                                end
                            end
                            if not adjacent then
                                return
                            end
                        end
                    end

                    --wall building: a column that already reaches the floor's
                    --ceiling cannot take another cube. Refuse the click; the
                    --hover label explains with "Walls Stacked to Ceiling".
                    if loc ~= nil and g_currentAbility.targeting == "contiguous_wall" then
                        local buildWall = rawget(_G, "ActivatedAbilityBuildWallBehavior")
                        if buildWall ~= nil and buildWall.StackedToCeiling ~= nil and buildWall.StackedToCeiling(loc) then
                            return
                        end
                    end

                    targets[#targets + 1] = { loc = loc }

                    --wall abilities build live: place the voxel for this square
                    --immediately so the wall rises as squares are chosen. A casting
                    --destructor tears the placed squares down if targeting is
                    --cancelled; a committed cast keeps them (see CommitPlacement).
                    if g_currentAbility.targeting == "contiguous_wall" then
                        local buildWall = rawget(_G, "ActivatedAbilityBuildWallBehavior")
                        if buildWall ~= nil and buildWall.PlaceSquare(g_currentAbility, g_token, g_currentSymbols, loc) then
                            g_castingDestructors[#g_castingDestructors + 1] = function()
                                buildWall.CancelPlacement()
                            end
                        end
                    end
                else
                    for k, target in pairs(g_pointForceTargets) do
                        if g_currentAbility.targetType ~= 'all' or target ~= g_token or g_currentAbility.selfTarget then
                            targets[#targets + 1] = { loc = target.loc, token = target }
                        end
                    end
                end
                if g_castingEmoteSet and g_token.valid then
                    g_token.properties:Emote(g_castingEmoteSet .. 'cast', { start = true, ttl = 20 })
                end

                if g_currentAbility.sequentialTargeting and g_currentSymbols.targetnumber == nil then
                    g_currentSymbols.targetnumber = 1
                end

                local numTargets = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                if (g_currentAbility.targetType == 'emptyspace' or g_currentAbility.targetType == 'anyspace') and #targets < numTargets then
                    --allow selection of more targets.
                    AddCustomAreaMarker({ loc }, 'white')
                    --Remember the marker for this target so we can destroy it
                    --if the same space is later clicked to deselect.
                    if #targets > 0 and targets[#targets].loc ~= nil and targets[#targets].loc.str == loc.str then
                        targets[#targets].marker = g_radiusMarkers[#g_radiusMarkers]
                    end

                    if g_currentAbility.targeting == "Contiguous" or g_currentAbility.targeting == "contiguous_wall" then
                        --targeting must be contiguous of current targets.
                        ClearRadiusMarkers()

                        if g_currentAbility.targeting == "contiguous" then
                            local duplicates = false
                            for i=#targets,2,-1 do
                                for j=1,i-1 do
                                    local a = targets[i].loc
                                    local b = targets[j].loc
                                    if a.str == b.str then
                                        --no duplicates.
                                        table.remove(targets, i)
                                        table.remove(targets, j)
                                        duplicates = true
                                        break
                                    end
                                end
                                if duplicates then
                                    break
                                end
                            end
                        end

                        local locs = {}

                        for _,target in ipairs(targets) do
                            if target.loc ~= nil then
                                locs[#locs + 1] = target.loc
                                locs[#locs+1] = target.loc.north
                                locs[#locs+1] = target.loc.south
                                locs[#locs+1] = target.loc.east
                                locs[#locs+1] = target.loc.west
                            end
                        end


                        print("MARK:: MARK LOCS")
                        g_radiusMarkers[#g_radiusMarkers + 1] = dmhub.MarkLocs{
                            locs = locs,
                            color = "#444444",
                        }
                    end

                    local promptText = g_currentAbility:PromptText(g_token, targets, g_currentSymbols)
                    g_castMessage.data.promptText = promptText
                    g_castMessage:FireEvent("refresh")
                    return
                end

                if targetingType == "pathfind" or targetingType == "vacated" then
                    --allow waypoint selection.

                    ClearRadiusMarkers()

                    local waypoints = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        waypoints[#waypoints + 1] = pos.loc
                    end

                    if #waypoints < 2 or waypoints[#waypoints].x ~= waypoints[#waypoints - 1].x or waypoints[#waypoints].y ~= waypoints[#waypoints - 1].y then
                        local mask = nil
                        if targetingType == "vacated" and g_currentSymbols.cast then
                            mask = g_currentSymbols.cast:GetVacatedSpaces()
                        end


                        local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                        local shifting = (movementType == "shift")
                        local moveFlags = {}
                        if shifting then
                            moveFlags[#moveFlags + 1] = "shifting"
                        end

                        local forcedMovement = g_currentAbility:try_get("targeting", "direct") == "straightline"
                        if forcedMovement then
                            moveFlags[#moveFlags+1] = "IgnoreMovementType"
                        end

                        local filterTargetPredicate = g_currentAbility:TargetLocPassesFilterPredicate(g_token, g_currentSymbols)
                        if not forcedMovement then
                            local restrictionFilter = g_token.properties:GetMovementRestrictionFilter(g_token)
                            if restrictionFilter ~= nil then
                                local baseFilter = filterTargetPredicate
                                filterTargetPredicate = function(loc) return baseFilter(loc) and restrictionFilter(loc) end
                            end
                        end
                        local radiusArgs = { moveFlags = moveFlags, waypoints = waypoints, mask = mask, filter = filterTargetPredicate}
                        local radiusMarker = g_token:MarkMovementRadius(g_range, radiusArgs)

                        if radiusMarker ~= nil then
                        print("MARK:: MARK LOCS")
                            g_radiusMarkers[#g_radiusMarkers + 1] = radiusMarker

                            --Strict movement: keep the legal-tile set in sync with this
                            --freshly-drawn forced-move radius (multi-step path case).
                            if forcedMovement then
                                CaptureForcedMoveLegalLocs(g_token, g_range, radiusArgs)
                            end
                            return
                        end
                    end

                    if #waypoints >= 2 and waypoints[#waypoints].x == waypoints[#waypoints - 1].x and waypoints[#waypoints].y == waypoints[#waypoints - 1].y then
                        --last waypoint is the same as the previous one, so remove it.
                        waypoints[#waypoints] = nil
                        targets[#targets] = nil
                    end

                    while #waypoints > 0 and waypoints[#waypoints].x == targets[#targets].loc.x and waypoints[#waypoints].y == targets[#targets].loc.y do
                        waypoints[#waypoints] = nil
                    end

                    g_currentSymbols.waypoints = waypoints

                    --we don't have any movement left, so cast.
                end

                g_token.lookAtMouse = false

                for i,t in ipairs(targets) do
                    print(string.format("XFLOOR:: mappress pre-PrepareTargets target[%d].loc.floor=%s",
                        i, tostring(t.loc and t.loc.floor or "nil")))
                end

                targets = g_currentAbility:PrepareTargets(g_token, g_currentSymbols, targets)

                for i,t in ipairs(targets) do
                    print(string.format("XFLOOR:: mappress post-PrepareTargets target[%d].loc.floor=%s",
                        i, tostring(t.loc and t.loc.floor or "nil")))
                end

                if m_markLineOfSight ~= nil then
                    SetTargetLineOfSightRayForKey(
                        string.format("%s-%s", m_markLineOfSightSourceToken.id, m_markLineOfSightToken.id),
                        m_markLineOfSight)
                    m_markLineOfSight = nil
                    m_markLineOfSightToken = nil
                    m_markLineOfSightSourceToken = nil
                end

                CharacterPanel.HighlightAbilitySection{
                    ability = g_currentAbility,
                    caster = g_token,
                    section = "main",
                }

                AppendImprovementCosts(g_currentCostProposal)

                local clearAbility = g_currentAbility

                --wall live-placement: mark the session committed so the casting
                --destructors (run by finishCasting, BEFORE behaviors execute on
                --their coroutine) don't tear down the already-built wall.
                if g_currentAbility.targeting == "contiguous_wall" then
                    local buildWall = rawget(_G, "ActivatedAbilityBuildWallBehavior")
                    if buildWall ~= nil then
                        buildWall.CommitPlacement(g_currentAbility)
                    end
                end

                --Fire pre-cast controls (e.g. Acolyte Invoke: deal Presence to caster,
                --add Patron's Gaze, set Cast.Invoked = 1). Must happen before Cast()
                --so symbol values are visible to behaviors and resource changes are
                --applied as part of this user-initiated action.
                FireCastControlsOnCommit(g_currentAbility, g_currentSymbols, g_token, targets)
                local castControlsResolveHandler = MakeCastControlsOnResolveHandler(g_token)

                --Director overview (slice (e)): the cast is now irreversible,
                --so take the owner's turn first if that is legal (no-op for
                --every ordinary cast). Same hook as the CalculateSpellTargeting
                --commit below.
                OverviewClaimBeforeCast(g_token)

                RecordPartnerBurstRetargets(targets)

                g_currentAbility:Cast(g_token, targets, {
                    targetArea = g_pointTargeting.shape,
                    costOverride = g_currentCostProposal,
                    symbols = g_currentSymbols,
                    markLineOfSight = m_targetLineOfSightRays,
                    OnFinishCastHandlers = {
                        function()
                            CharacterPanel.HideAbility(clearAbility)
                        end,
                        castControlsResolveHandler,
                    }
                })

                g_currentAbility = nil

                m_targetLineOfSightRays = {}

                m_markLineOfSight = nil
                m_markLineOfSightToken = nil
                m_markLineOfSightSourceToken = nil
                if g_abilityController ~= nil then g_abilityController:FireEvent("finishCasting") end
            end
        end,

        escapePriority = EscapePriority.CANCEL_ACTION_BAR,
        escape = function(element)
            if g_currentAbility ~= nil and g_currentAbility.targetType == "line" and #m_positionTargetsChosen > 0 then
                local loc = m_positionTargetsChosen[#m_positionTargetsChosen]
                --clear the line start point.
                m_positionTargetsChosen = {}
                CalculateSpellTargeting()
                element:FireEvent("maphover", element.data.lastHoverLoc, element.data.lastHoverPoint)
                return
            end
            
            element:FireEvent("cancelCasting")
        end,
    }

    return resultPanel
end

local g_potentialTargetTokens = {}

--DIAG: last targeting-state summary printed, so the trace below only logs changes.
local g_lastTargetDiagLine = nil

local function CalculateSpellTargetFocusing(symbols)

    local range = symbols.range

    local potentialTargetTokens = {}
    if g_currentAbility == nil then return potentialTargetTokens end
    local spell = g_currentAbility
    if (spell.targetType == 'self' or spell.targetType == 'target' or spell.targetType == 'all' or spell.targetType == 'areatemplate') and g_synthesizedSpellsPanel:HasClass("collapsed") then

        local locs = nil
        if spell.targetType == "areatemplate" then

            local shape = dmhub.CalculateShape {
                shape = "areatemplate",
                token = g_token,
                objectTemplate = g_currentAbility:try_get("areaTemplateObjectId"),
            }

            if shape ~= nil and shape.locations ~= nil then
                locs = shape.locations
            end
        end

        local allTokens = nil
        local targeting = dmhub.GetSettingValue("targetobjects")
        if g_currentAbility.targetAllegiance == "dead" then
            allTokens = dmhub.allTokensIncludingObjects
        elseif g_currentAbility.objectTarget == false then
            --Objects can still grant targeting to non-object abilities via
            --their additionalTargetFilter (ObjectGrantsTargeting), so include
            --object tokens and let TargetPassesFilter sort them out.
            allTokens = dmhub.allTokensIncludingObjects
        elseif g_currentAbility.targetAllegiance == "none" then
            allTokens = dmhub.allTokensIncludingObjects
        else
            if targeting == "all" or g_currentAbility.objectTarget == "conditional" then
                allTokens = dmhub.allTokensIncludingObjects
            elseif targeting == false then
                allTokens = dmhub.allTokens
            else
                -- targeting == true (Objects): use allTokensIncludingObjects so that
                -- creatures tagged treatAsObject appear as valid targets.
                allTokens = dmhub.allTokensIncludingObjects
            end
        end

        for _, targetToken in ipairs(allTokens) do
            if targetToken.valid and targetToken.sheet ~= nil then
                if targetToken.sheet.data.targetInfo ~= nil then
                    targetToken.sheet:FireEvent("untarget")
                end

                local canTarget = true

                -- For objectTarget abilities, respect the Creatures/Objects/Both setting.
                -- Object-only abilities (targetAllegiance == "none") don't show that
                -- slider at all, so a stale preference must not filter their candidates.
                if g_currentAbility.objectTarget == true and g_currentAbility.targetAllegiance ~= "none" then
                    local treatAsObject = (not targetToken.isObject) and
                                          targetToken.properties ~= nil and
                                          targetToken.properties:try_get("treatAsObject", false)
                    if targeting == false and treatAsObject then
                        -- "Creatures" mode: exclude creature-objects.
                        canTarget = false
                    elseif targeting == true and (not treatAsObject) and (not targetToken.isObject) then
                        -- "Objects" mode: exclude regular creatures.
                        canTarget = false
                    end
                end

                if (spell.targetType == 'self' or spell.targetType == 'all') and targetToken.charid ~= g_token.charid then
                    canTarget = false
                end

                if g_creature == targetToken.properties and (spell.targetType == 'target' or spell.targetType == 'all') then
                    -- "Can Target Self" flag lets the caster target itself alongside its other
                    -- candidates even when the ability is not selfTarget (e.g. a compelled free
                    -- strike that may hit an adjacent creature OR itself). TargetPassesFilter
                    -- (called below) also waives the allegiance filter for the flagged self target.
                    if spell.selfTarget == false and g_creature:CalculateNamedCustomAttribute("Can Target Self") <= 0 then
                        canTarget = false
                    end
                end

                if symbols ~= nil and symbols.forbiddentargets ~= nil and symbols.forbiddentargets[targetToken.charid] then
                    canTarget = false
                end

                if symbols ~= nil and symbols.allowedtargets ~= nil and not symbols.allowedtargets[targetToken.charid] then
                    canTarget = false
                end

                if locs ~= nil and canTarget then
                    canTarget = false
                    local locsOccupying = targetToken.locsOccupying
                    for _,loc in ipairs(locsOccupying) do
                        for _,shapeLoc in ipairs(locs) do
                            if loc.x == shapeLoc.x and loc.y == shapeLoc.y then
                                canTarget = true
                                break
                            end
                        end
                        if canTarget then
                            break
                        end
                    end
                end

                local failReason = nil

                if canTarget then
                    canTarget, failReason = spell:TargetPassesFilter(g_token, targetToken, symbols)
                    if failReason ~= nil then
                        canTarget = true
                    end
                end

                if canTarget and targetToken.properties:HasNamedCondition("Hidden") and g_currentAbility:HasKeyword("Strike") then
                    local ignoreRange = g_token.properties:CalculateNamedCustomAttribute("Ignore Hidden Within Range") or 0
                    local bypass = false
                    if ignoreRange > 0 then
                        local dist = g_token:Distance(targetToken)
                        if dist <= ignoreRange then
                            bypass = true
                        end
                    end
                    if not bypass then
                        failReason = "Cannot target a hidden creature with a strike"
                    end
                end

                if targetToken.properties:CalculateNamedCustomAttribute("Untargetable") > 0 then
                    failReason = "Target is untargetable"
                end

                local casterLocOverride = g_currentAbility:try_get("casterLocOverride")
                local rangeSource = g_currentAbility:GetRangeSource(g_token)
                local directRangeSource = casterLocOverride or rangeSource
                local checkStrictRange = (not g_token.properties.minion) or rangeSource ~= g_token

                if canTarget then
                    --give us an extra square of range to account for diagonals.
                    if failReason == nil and spell.targetType ~= "areatemplate" and checkStrictRange and not (range + dmhub.unitsPerSquare > targetToken:Distance(directRangeSource)) then
                        --An explicit range source is the complete origin contract. Casting-
                        --origin relays still apply to ordinary casts, but must not widen an
                        --invoked ability centered on its parent cast's primary target.
                        if rangeSource ~= g_token or not spell:IsTargetInRangeOfCastingOrigins(g_token, targetToken, range) then
                            failReason = "Out of range"
                        end
                    end

                    --altitude range check under Draw Steel "free diagonals": the 3D distance is
                    --Chebyshev -- max(horizDist, altDiff) -- so altitude only takes a target out
                    --of range when it alone exceeds the range. Mirrors EffectiveArrowRange and
                    --AddModifierLabelsToMarker so arrow greying, the "Out of Range" label, and
                    --the strict-targeting block all agree.
                    if failReason == nil and spell.targetType ~= "areatemplate" and checkStrictRange then
                        local altDiff = math.abs(rangeSource.altitude - targetToken.altitude)
                        if altDiff > 0 then
                            local horizDist = targetToken:Distance(directRangeSource)
                            local altDiffUnits = altDiff * dmhub.unitsPerSquare
                            if math.max(horizDist, altDiffUnits) >= range + dmhub.unitsPerSquare then
                                failReason = string.format("Out of range (altitude difference: %d)", altDiff)
                            end
                        end
                    end

                    local valid = failReason == nil

                    if targetToken.valid and targetToken.sheet ~= nil then
                        if targetToken.sheet.data.targetInfo ~= nil then
                            targetToken.sheet.data.targetInfo = nil
                            targetToken.sheet:FireEvent("untarget")
                        end

                        --count if there are multiple rays for this target.
                        local raycount = 0
                        for key, ray in pairs(m_targetLineOfSightRays) do
                            if string.ends_with(key, targetToken.charid) then
                                raycount = raycount + 1
                            end
                        end

                        local classes = cond(valid, {}, { 'invalid' })
                        if raycount >= 2 then
                            classes[#classes + 1] = "two"
                            if raycount >= 3 then
                                classes[#classes + 1] = "three"
                            end
                        end

                        targetToken.sheet.data.targetInfo = g_targetInfo
                        --record validity so click handlers can reject invalid
                        --targets when strict-targeting is enforced for players.
                        targetToken.sheet.data.targetValid = valid
                        --out-of-range is shown as an arrow label instead of a token tooltip.
                        local tooltipReason = failReason
                        if tooltipReason ~= nil and string.starts_with(tooltipReason, "Out of range") then
                            tooltipReason = nil
                        end
                        targetToken.sheet:FireEvent('target', { valid = valid, classes = classes, reason = tooltipReason })

                        potentialTargetTokens[#potentialTargetTokens + 1] = targetToken
                    end
                end
            end
        end
    end

    --Squad coordinated strike: make the squad's own minions clickable so the
    --player can lock a specific minion to a target (click the minion, then the
    --target). Auto-assignment still handles every unlocked minion.
    if SquadStrikeActive() then
        local squad = g_token.properties:try_get("_tmp_minionSquad")
        if squad ~= nil and squad.tokens ~= nil then
            for _, tok in ipairs(squad.tokens) do
                if tok ~= nil and tok.valid and tok.sheet ~= nil
                    and (not tok.properties:IsDead()) and tok.properties:IsActiveInSquad() then
                    if tok.sheet.data.targetInfo ~= nil and tok.sheet.data.targetInfo ~= g_targetInfo then
                        tok.sheet:FireEvent("untarget")
                    end
                    tok.sheet.data.targetInfo = g_targetInfo
                    tok.sheet.data.targetValid = true
                    tok.sheet:FireEvent("target", { valid = true })
                end
            end
        end
    end

    --DIAG: compact targeting-state trace for the invoke-prompt hang
    --investigation. Logs once per state change: which ability is targeting,
    --as whom, and how many candidate tokens were armed/valid. Safe to keep.
    local validCount = 0
    for _, tok in ipairs(potentialTargetTokens) do
        if tok.valid and tok.sheet ~= nil and tok.sheet.data.targetValid then
            validCount = validCount + 1
        end
    end
    local diagLine = string.format("TARGETDIAG:: ability=%s caster=%s armed=%d valid=%d chosen=%d",
        tostring(spell.name),
        tostring(g_token ~= nil and (g_token.name or g_token.charid) or "nil"),
        #potentialTargetTokens, validCount, #g_targetsChosen)
    if diagLine ~= g_lastTargetDiagLine then
        g_lastTargetDiagLine = diagLine
        print(string.format("%s T=%.2f", diagLine, dmhub.Time()))
    end

    return potentialTargetTokens
end

CalculateSpellTargeting = function(forceCast, initialSetup)
    if g_currentAbility == nil then
        dmhub.Debug("ActionBar: CalculateSpellTargeting called with nil g_currentAbility")
        return
    end
    if g_skipButton == nil then return end

    if g_token == nil then
        dmhub.CloudError("nil token: " .. traceback())
        return
    end

    if g_currentAbility.targetType == 'point' then

    else
        local targets = BuildTargetsList()

        local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
        g_currentSymbols.range = range

        --if this spell dictates specific targeting rays to use.
        local rays = g_currentAbility:GetTargetingRays(g_token, range, g_currentSymbols, targets)
        if rays ~= nil then
            ReplaceTargetLineOfSightRays(rays, g_currentAbility, range)

            --record the targeting as symbols.
            local targetPairs = {}
            for i, ray in ipairs(rays) do
                targetPairs[#targetPairs + 1] = { a = ray.a.id, b = ray.b.id }
            end

            g_currentSymbols.targetPairs = targetPairs
        else
            g_currentSymbols.targetPairs = nil
        end

        g_skipButton:SetClass("collapsed", not g_currentAbility:try_get("skippable", false))

        -- Don't auto-cast on initial setup unless requested.
        -- When a promptOverride is set (e.g. an invoke-ability prompt), fall through to the
        -- confirmation UI so the player can read the prompt and click Confirm when the
        -- targets arrived PRE-SELECTED via the inherited target list. If the player chose
        -- the targets by clicking them (g_manualTargetChosen), reaching the target cap
        -- completes the cast normally -- the prompt was visible throughout targeting, and
        -- requiring an extra Confirm after an explicit click just adds friction (e.g. the
        -- one-creature picks invoked per wall square by manipulate_targets). An explicit
        -- Confirm click (forceCast = true) always goes through regardless.
        local hasPromptOverride = g_currentAbility:try_get("promptOverride") ~= nil and not g_manualTargetChosen
        if forceCast or ((not g_currentAbility:CanSelectMoreTargets(g_token, targets, g_currentSymbols)) and not hasPromptOverride) then --temporarily disabled -David -- and not initialSetup then
            --we can't select more targets, so cast the spell in here.
            g_token.lookAtMouse = false
            if g_castingEmoteSet and g_token.valid then
                g_token.properties:Emote(g_castingEmoteSet .. 'cast', { start = true, ttl = 20 })
            end

            if g_currentAbility.sequentialTargeting and g_currentSymbols.targetnumber == nil then
                g_currentSymbols.targetnumber = 1
                g_currentSymbols.targetcount = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
            end

            --make any active targeted tokens keep their targeting until the spell is done.
            local adoptedTargets = {}
            for k, token in pairs(dmhub.allTokensIncludingObjects) do
                if token.valid and token.sheet ~= nil and token.sheet.data.targetInfo == g_targetInfo then
                    token.sheet:FireEvent('adoptSelectedTargets', adoptedTargets)
                end
            end

            targets = g_currentAbility:PrepareTargets(g_token, g_currentSymbols, targets)

            AdoptLineOfSightMark()

            --any triggers created while casting are attached to the spell.
            local attachedTriggers = nil
            if m_castingTriggers ~= nil then
                for _, trigger in ipairs(m_castingTriggers) do
                    if trigger.triggered then
                        attachedTriggers = attachedTriggers or {}
                        attachedTriggers[#attachedTriggers + 1] = DeepCopy(trigger)
                    end
                end
            end

            CharacterPanel.HighlightAbilitySection{
                ability = g_currentAbility,
                caster = g_token,
                section = "main",
            }

            AppendImprovementCosts(g_currentCostProposal)

            RecordPartnerBurstRetargets(targets)

            local clearAbility = g_currentAbility

            --wall live-placement: mark the session committed so the casting
            --destructors don't tear down the already-built wall (behaviors run on
            --a coroutine after finishCasting fires the destructors).
            if g_currentAbility.targeting == "contiguous_wall" then
                local buildWall = rawget(_G, "ActivatedAbilityBuildWallBehavior")
                if buildWall ~= nil then
                    buildWall.CommitPlacement(g_currentAbility)
                end
            end

            --Fire pre-cast controls (e.g. Acolyte Invoke). See FireCastControlsOnCommit
            --for the rationale on ordering: it must run before Cast() so symbols (e.g.
            --Cast.Invoked) are visible to behaviors and pre-cast effects (self damage,
            --resource adjustments) post-commit cleanly.
            FireCastControlsOnCommit(g_currentAbility, g_currentSymbols, g_token, targets)
            local castControlsResolveHandler = MakeCastControlsOnResolveHandler(g_token)

            --Director overview (slice (e)): implicit claim at target confirm,
            --only when legal; see g_overviewCastPending. No-op otherwise.
            OverviewClaimBeforeCast(g_token)

            g_currentAbility:Cast(g_token, targets, {
                attachedTriggers = attachedTriggers,
                costOverride = g_currentCostProposal,
                symbols = g_currentSymbols,
                markLineOfSight = m_targetLineOfSightRays,
                OnFinishCastHandlers = {
                    function()
                        CharacterPanel.HideAbility(clearAbility)
                        for _, panel in ipairs(adoptedTargets) do
                            if panel ~= nil and panel.valid then
                                panel:FireEvent("destroy")
                            end
                        end
                    end,
                    castControlsResolveHandler,
                },
            })
            m_targetLineOfSightRays = {}

            g_currentAbility = nil

            if g_abilityController == nil then return end
            g_abilityController:FireEvent("finishCasting")
        else
            if g_ammoChoicePanel == nil or g_synthesizedSpellsPanel == nil or g_castChargesInput == nil then return end
            g_ammoChoicePanel:FireEvent("refreshSpell")
            g_synthesizedSpellsPanel:FireEvent("refreshSpell")
            g_castChargesInput:FireEvent("refreshSpell")

            local synthesizedSpells = g_synthesizedSpellsPanel.data.synthesized
            g_castButton:SetClass('collapsed',
                (not g_currentAbility:CanCastAsIs(g_token, targets, g_currentSymbols)) or
                (synthesizedSpells ~= nil and #synthesizedSpells > 0))


            local promptText = g_currentAbility:PromptText(g_token, targets, g_currentSymbols, synthesizedSpells)
            --While a minion is armed for a lock, prompt for its target.
            --Otherwise, during squad targeting, add a hint that clicking a
            --minion lets the player choose its target instead of using the
            --automatic closest-minion assignment.
            if SquadStrikeActive() then
                if g_squadPendingLockMinion ~= nil and g_squadPendingLockMinion.valid then
                    promptText = string.format("Choose a target to lock for %s", creature.GetTokenDescription(g_squadPendingLockMinion))
                else
                    local hint = "<size=75%><i>Click one of your minions to choose which minion attacks which target</i></size>"
                    if promptText == nil or promptText == "" then
                        promptText = hint
                    else
                        promptText = promptText .. "\n" .. hint
                    end
                end
            end
            g_castMessage.data.promptText = promptText
            g_castMessage:FireEvent("refresh")

            g_castModesPanel:FireEvent("refreshModes")
            g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")

            local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
            print("MovementRadius:: RANGE", range)
            g_currentSymbols.numberoftargets = #targets
            g_currentSymbols.range = range
            g_range = range

            g_potentialTargetTokens = CalculateSpellTargetFocusing(g_currentSymbols)

            --refresh the radius marker.
            if g_currentAbility.targetType == "line" then
                ClearRadiusMarkers()

                if #m_positionTargetsChosen == 0 then
                    local loc = g_currentAbility:try_get("casterLocOverride")
                    local lineDistance = g_currentAbility:GetLineDistance(g_token.properties, g_currentSymbols)
                    AddRadiusMarker(loc, lineDistance, 'white')
                end
                
            elseif (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") and (g_currentAbility:try_get("targeting", "direct") == "pathfind" or g_currentAbility:try_get("targeting", "direct") == "vacated" or g_currentAbility:try_get("targeting", "direct") == "straightline") then
                ClearRadiusMarkers()

                local waypoints = {}
                for _, pos in ipairs(m_positionTargetsChosen) do
                    waypoints[#waypoints + 1] = pos.loc
                end

                local mask = nil
                if g_currentAbility:try_get("targeting", "direct") == "vacated" and g_currentSymbols.cast then
                    mask = g_currentSymbols.cast:GetVacatedSpaces()
                end

                local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                local shifting = (movementType == "shift")
                local moveFlags = {}
                if shifting then
                    moveFlags[#moveFlags + 1] = "shifting"
                end
                -- For forced movement (straightline targeting), show all tiles in range
                -- regardless of walls so the player can target "into" a wall.
                if g_currentAbility:try_get("targeting", "direct") == "straightline" then
                    moveFlags[#moveFlags + 1] = "IgnoreWalls"
                    moveFlags[#moveFlags + 1] = "IgnoreMovementType"
                end

                m_allowedAltitudeCalculator = g_currentAbility:TargetLocMaxElevationChangeFunction(g_token, g_currentSymbols)
                --Teleports default to landing on the ground ("min"); forced movement keeps "max".
                SetAltitudeMode(m_allowedAltitudeCalculator ~= nil and "movement" or nil,
                    cond(movementType == "teleport", "min", nil))
                print("ALT:: CALC ALT:", m_allowedAltitudeCalculator)


                local filterTargetPredicate = g_currentAbility:TargetLocPassesFilterPredicate(g_token, g_currentSymbols)
                if g_currentAbility:try_get("targeting", "direct") ~= "straightline" then
                    local restrictionFilter = g_token.properties:GetMovementRestrictionFilter(g_token)
                    if restrictionFilter ~= nil then
                        local baseFilter = filterTargetPredicate
                        filterTargetPredicate = function(loc) return baseFilter(loc) and restrictionFilter(loc) end
                    end
                end

                print("MARK:: MovementRadius:: MARK", range)
                local radiusArgs = { moveFlags = moveFlags, waypoints = waypoints, mask = mask, filter = filterTargetPredicate }
                g_radiusMarkers[#g_radiusMarkers + 1] = g_token:MarkMovementRadius(range, radiusArgs)

                --Strict movement: for forced movement (straightline), capture the EXACT
                --tiles this radius is drawn from so targeting can be confined to them.
                --Other targeting variants (pathfind/vacated normal movement) are not
                --forced movement -> leave the set nil (no forced-move gating).
                if g_currentAbility:try_get("targeting", "direct") == "straightline" then
                    CaptureForcedMoveLegalLocs(g_token, range, radiusArgs)
                else
                    g_forcedMoveLegalLocs = nil
                end
            elseif (g_currentAbility.targetType ~= 'line' or g_currentAbility.canChooseLowerRange) and g_currentAbility.targetType ~= 'cone' and g_currentAbility.targetType ~= 'self' and g_currentAbility.targetType ~= 'all' and g_currentAbility.targetType ~= 'map' and g_currentAbility.targetType ~= 'areatemplate' then
                local loc = g_currentAbility:try_get("casterLocOverride")

                if g_currentAbility.proximityTargeting and g_firstTarget ~= nil then
                    local targetToken = nil

                    if g_currentAbility:try_get("proximityChain") and #g_targetsChosen > 0 then
                        -- For proximity chain, use the last target
                        targetToken = dmhub.GetTokenById(g_targetsChosen[#g_targetsChosen])
                    else
                        -- For normal proximity, use the first target
                        targetToken = dmhub.GetTokenById(g_firstTarget)
                    end
                    
                    if targetToken ~= nil then
                        loc = targetToken.locsOccupying
                        range = ExecuteGoblinScript(g_currentAbility.proximityRange,
                            g_token.properties:LookupSymbol(), dmhub.unitsPerSquare,
                            "Calculate proximity")
                    end
                end

                ClearRadiusMarkers()

                m_allowedAltitudeCalculator = nil
                local customLocs = g_currentAbility:CustomTargetShape(g_token, range, g_currentSymbols, targets)

                if customLocs == nil then
                    local filterTargetPredicate = g_currentAbility:TargetLocPassesFilterPredicate(g_token,
                        g_currentSymbols)

                    local tierRadii = g_currentAbility:GetTargetingTierRadii(g_token, g_currentSymbols)
                    if tierRadii ~= nil then
                        --Tiered targeting (e.g. Jump): one ring per tier. When the
                        --ring carries a reachability-accurate tile set (ring.locs,
                        --from CalculateJumpReachable) it is drawn as a white
                        --solid/dashed/dotted outline of exactly the tiles that
                        --tier can land on. Fallback (older engine): colored
                        --distance annuli.
                        local prevTiles = 0
                        for _, ring in ipairs(tierRadii) do
                            --An invisible ring (e.g. the tier 1 ring of a caster
                            --who cannot roll below tier 2) exists only for the
                            --hover required-tier logic: draw nothing, and leave
                            --prevTiles alone so the next visible ring's annulus
                            --covers its zone.
                            if ring.invisible then
                            elseif ring.locs ~= nil then
                                local ringLocs = ring.locs
                                if filterTargetPredicate ~= nil then
                                    local filtered = {}
                                    for _, l in ipairs(ringLocs) do
                                        if filterTargetPredicate(l) then
                                            filtered[#filtered + 1] = l
                                        end
                                    end
                                    ringLocs = filtered
                                end
                                if #ringLocs > 0 then
                                    g_radiusMarkers[#g_radiusMarkers + 1] = dmhub.MarkLocs {
                                        locs = ringLocs,
                                        color = ring.color,
                                        style = ring.style,
                                    }
                                end
                                prevTiles = ring.tiles
                            else
                                local minTiles = prevTiles
                                AddRadiusMarker(loc, ring.radius, ring.color, function(l)
                                    if filterTargetPredicate ~= nil and (not filterTargetPredicate(l)) then
                                        return false
                                    end
                                    return DistanceFromCasterInTiles(l) > minTiles
                                end)
                                prevTiles = ring.tiles
                            end
                        end
                    else
                        print("MovementRadius:: MARK", range)
                        AddRadiusMarker(loc, range, 'white', filterTargetPredicate)
                    end

                    m_allowedAltitudeCalculator = g_currentAbility:TargetLocMaxElevationChangeFunction(g_token, g_currentSymbols)
                    --Cube targeting opts into the controller in "cube" mode (no min/max
                    --calculator; default is "On Ground"). Forced-movement abilities use
                    --"movement" mode with a calculator that bounds min/max. Teleports also
                    --use "movement" mode but default to landing on the ground ("min").
                    if m_allowedAltitudeCalculator ~= nil then
                        local defaultTarget = nil
                        if g_currentAbility:GetMovementType(g_token, g_currentSymbols) == "teleport" then
                            defaultTarget = "min"
                        end
                        SetAltitudeMode("movement", defaultTarget)
                    elseif g_currentAbility.targetType == "cube" then
                        SetAltitudeMode("cube")
                    else
                        SetAltitudeMode(nil)
                    end
                else
                    AddCustomAreaMarker(customLocs, 'white')
                end
            elseif g_currentAbility.targetType == 'all' or g_currentAbility.targetType == 'areatemplate' then
                --synthesize a map hover event to highlight the area.
                if g_abilityController == nil then return end
                g_abilityController:FireEvent("maphover", nil, 'all')
            end
        end
    end
end

RegisterCustomActionBar(CreateActionBar)

--On reset-turn / backup-restore, cancel any in-progress cast on this client.
--cancelCasting is the same event the escape key fires; it runs the full action
--bar cleanup (HideAbility, RemoveTokenTargeting, ClearPointTargeting, clears
--g_currentAbility, collapses cast controls, clears LoS markers, etc.).
dmhub.RegisterEventHandler("restoreFromBackup", function()
    if g_currentAbility ~= nil and g_abilityController ~= nil and g_abilityController.valid then
        g_abilityController:FireEvent("cancelCasting")
    end
end)
--RegisterCustomActionBar(nil)

-- =============================================================================
-- On-map search reveal: open an ability's drawer menu and pulse its row.
--
-- When the director searches an on-map monster's ability (the map-view context
-- provider in CharacterPanel.lua), the result selects + centres the token; its
-- abilities then populate this bar. This points the director at the matched
-- ability: open the drawer dropdown it lives in and pulse its row. Exposed on
-- the shared Search table (field access is nil-safe across modules). A no-op
-- when the ability is not on the bar (traits route here as nil; an ability that
-- no drawer surfaces is skipped). Every panel read is pcall-guarded.
-- =============================================================================
Search.RevealActionBarAbility = function(tokenid, abilityName)
    if type(abilityName) ~= "string" or abilityName == "" then
        return
    end

    --g_abilities populates asynchronously after SelectToken, so retry until the
    --bar is showing the right token and the matched ability is present.
    local openAttempts = 0
    local function openDrawer()
        if mod.unloaded then
            return
        end
        if g_actionBar == nil or not g_actionBar.valid or g_token == nil or g_token.id ~= tokenid then
            openAttempts = openAttempts + 1
            if openAttempts < 30 then dmhub.Schedule(0.1, openDrawer) end
            return
        end

        local matched = nil
        for _, ability in ipairs(g_abilities or {}) do
            local ok, nm = pcall(function() return ability.name end)
            if ok and nm == abilityName then
                matched = ability
                break
            end
        end
        if matched == nil then
            openAttempts = openAttempts + 1
            if openAttempts < 30 then dmhub.Schedule(0.1, openDrawer) end
            return
        end

        local drawerType = DrawerTypeForAbility(matched)
        if drawerType == nil then
            return
        end

        --Find the drawer of that type and open its dropdown. press toggles, so
        --only press when it is not already the active (open) drawer.
        local drawer = nil
        local function walkDrawer(p, depth)
            if p == nil or depth > 10 or drawer ~= nil then return end
            local dt = nil
            pcall(function() dt = p.data and p.data.drawerType or nil end)
            if dt == drawerType then drawer = p return end
            local ok, ch = pcall(function() return p.children end)
            if ok and type(ch) == "table" then
                for _, c in ipairs(ch) do walkDrawer(c, depth + 1) end
            end
        end
        walkDrawer(g_actionBar, 0)
        if drawer == nil then
            return
        end
        if not drawer:HasClass("active") then
            drawer:FireEvent("press")
        end

        --The menu builds its headings synchronously but needs a frame to lay
        --out; retry locating the matched heading, then pulse it a few times so
        --it is easy to see (finite scheduled chain, no persistent think).
        local pulseAttempts = 0
        local function pulse()
            if mod.unloaded or not g_actionBar.valid then
                return
            end
            local heading = nil
            local function walkHeading(p, depth)
                if p == nil or depth > 25 or heading ~= nil then return end
                local an = nil
                pcall(function() an = p.data and p.data.abilityName or nil end)
                if an == abilityName and p:HasClass("abilityHeading") and not p:HasClass("collapsed") then
                    heading = p
                    return
                end
                local ok, ch = pcall(function() return p.children end)
                if ok and type(ch) == "table" then
                    for _, c in ipairs(ch) do walkHeading(c, depth + 1) end
                end
            end
            walkHeading(g_actionBar, 0)
            if heading ~= nil then
                --Fade the accent in, hold, fade out (both over the rule's
                --transitionTime), then a slight pause before the next - a
                --gentle reminder breathe, not a strobe.
                local remaining = SEARCH_REVEAL_PULSES
                local function cycle()
                    if mod.unloaded or heading == nil or not heading.valid then return end
                    heading:SetClass("searchReveal", true)
                    dmhub.Schedule(SEARCH_REVEAL_FADE + SEARCH_REVEAL_HOLD, function()
                        if mod.unloaded or heading == nil or not heading.valid then return end
                        heading:SetClass("searchReveal", false)
                        remaining = remaining - 1
                        if remaining > 0 then dmhub.Schedule(SEARCH_REVEAL_FADE + SEARCH_REVEAL_GAP, cycle) end
                    end)
                end
                cycle()
                return
            end
            pulseAttempts = pulseAttempts + 1
            if pulseAttempts < 20 then dmhub.Schedule(0.05, pulse) end
        end
        pulse()
    end
    openDrawer()
end
