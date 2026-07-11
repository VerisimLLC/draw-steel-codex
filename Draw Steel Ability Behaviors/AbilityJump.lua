local mod = dmhub.GetModLoading()

--Target-first Jump move action.
--
--The player targets the destination tile FIRST; while targeting, the action
--bar draws one ring per tier showing tier 1/2/3 reach (see
--GetTargetingTierRadii and DrawSteelActionBar). Once a tile is chosen this
--behavior computes the tier actually needed to get there -- distance AND
--height, since a tall height-limited wall inside baseline distance still
--forces a test ("longer or higher"). If tier 1 suffices the jump executes
--immediately with no roll; otherwise a test power roll dialog is shown and
--the rolled tier decides where the jump really lands: on the chosen tile, or
--short along the straight line (possibly falling, e.g. into a chasm the
--player needed tier 3 to clear).
--
--Draw Steel rules: baseline long jump = up to Might or Agility (min 1)
--squares with jump height 1 square, automatic, no test. A test is only for
--jumping longer or higher than baseline: tier 1 = baseline only, tier 2 =
--1 square longer and higher, tier 3 = 2 squares longer and higher. A jump
--can never exceed the movement allowance of the effect granting the move.
--
--The baseline distance and height come from the "Jump Distance" and "Jump
--Height" custom attributes (see tierDistances/tierHeights), so modifiers to
--those attributes flow into targeting, previews, and the executed jump. A
--caster whose jump test cannot roll a tier 1 outcome (a nottierone power
--modifier gated on the jump skill, e.g. the Fury's Mighty Leaps) previews
--only two rings, with the tier 2 ring shown as the guaranteed one.

ActivatedAbilityJumpBehavior = RegisterGameType("ActivatedAbilityJumpBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityJumpBehavior.summary = 'Jump (Roll to Target)'
ActivatedAbilityJumpBehavior.roll = "2d10 + Might or Agility"
ActivatedAbilityJumpBehavior.attrid = "mgt"
ActivatedAbilityJumpBehavior.skillid = "none"

--Per-tier jump distance formulas, evaluated against the caster's symbols.
--"Jump Distance" is the custom attribute (base Max(1, Max(Might, Agility))).
ActivatedAbilityJumpBehavior.tierDistances = {"Jump Distance", "1 + Jump Distance", "2 + Jump Distance"}

--Per-tier jump height formulas, evaluated against the caster's symbols. The
--baseline is the "Jump Height" custom attribute (normally 1), and each tier
--above 1 adds a square ("1 square longer AND higher").
ActivatedAbilityJumpBehavior.tierHeights = {"Jump Height", "1 + Jump Height", "2 + Jump Height"}

--Fallback ring colors during targeting (older engine without
--CalculateJumpReachable): safe/guaranteed (green), then amber, then risky
--(red). Also used to color the shortfall landing markers. Indexed by the
--ring's DISPLAY position, not its tier: when tier 1 cannot be rolled the
--tier 2 ring takes the safe slot.
ActivatedAbilityJumpBehavior.tierColors = {"#63c74dcc", "#f4c542cc", "#e8543fcc"}

--Ring line styles during targeting: solid, dashed, dotted from the safest
--displayed ring outward. All rings render white in reachability mode.
ActivatedAbilityJumpBehavior.tierStyles = {"solid", "dashed", "dotted"}

ActivatedAbility.RegisterType{
    id = 'jump_test',
    text = 'Jump (Roll to Target)',
    createBehavior = function()
        return ActivatedAbilityJumpBehavior.new{}
    end
}

--Returns {h1,h2,h3}: the height in tiles a jump at each tier clears,
--evaluated from the caster's "Jump Height" custom attribute (normally 1,
--giving the rules-default heights 1/2/3).
function ActivatedAbilityJumpBehavior:GetTierHeights(ability, casterToken)
    local lookup = casterToken.properties:LookupSymbol()
    local result = {}
    for i = 1, 3 do
        result[i] = math.max(0, round(ExecuteGoblinScript(self.tierHeights[i], lookup, i, "Jump tier height")))
    end
    return result
end

--The action bar keys jump-specific targeting previews off this.
function ActivatedAbilityJumpBehavior:BehaviorMovementType(symbols)
    return "jump"
end

--Returns {d1,d2,d3}: the jump distance in tiles granted by each tier, each
--clamped to the caster's remaining movement this turn (rules: you can't jump
--farther than the movement allowance of the effect that lets you move).
--Clamp semantics match the "jump N" rule command in MCDMAbilityBehavior.
function ActivatedAbilityJumpBehavior:GetTierDistances(ability, casterToken)
    local creature = casterToken.properties
    local lookup = creature:LookupSymbol()

    local movedThisTurn = 0
    if creature:IsOurTurn() then
        movedThisTurn = creature:DistanceMovedThisTurn()
    end

    local movementAllowed = math.max(0, creature:CurrentMovementSpeed() - movedThisTurn)

    local result = {}
    for i = 1, 3 do
        local dist = round(ExecuteGoblinScript(self.tierDistances[i], lookup, 1, "Jump tier distance"))
        result[i] = math.max(0, math.min(dist, movementAllowed))
    end

    return result
end

--Options table for GetModifiersForPowerRoll. Declaring the jump's skill is
--load-bearing: skill-restricted modifiers (e.g. the Fury's Mighty Leaps) are
--deactivated on any test_power_roll that does not declare its skills.
function ActivatedAbilityJumpBehavior:PowerRollOptions(ability)
    local options = { attribute = self.attrid, title = ability.name }
    local skillid = self:try_get("skillid", "none")
    if skillid ~= "none" and skillid ~= "" then
        options.skills = {skillid}
    end
    return options
end

--True when the caster has an auto-activated modifier that forbids a tier 1
--outcome on this jump test (e.g. the Fury's Mighty Leaps), meaning a rolled
--jump is guaranteed at least the tier 2 distance and height.
function ActivatedAbilityJumpBehavior:RollCannotBeTierOne(ability, casterToken)
    local creature = casterToken.properties
    local modifiers = creature:GetModifiersForPowerRoll(self.roll, "test_power_roll", self:PowerRollOptions(ability))
    for _, entry in ipairs(modifiers) do
        if entry.modifier:try_get("modtype") == "nottierone" and entry.hint ~= nil and entry.hint.result == true then
            return true
        end
    end
    return false
end

--Consulted by the action bar (via ActivatedAbility:GetTargetingTierRadii) to
--draw one ring per tier during targeting.
--
--When the engine provides CalculateJumpReachable, each ring carries the exact
--set of tiles that tier's jump can land on -- accounting for walls AND
--elevation, so e.g. a tall pillar top only appears in the ring whose jump
--height reaches it -- and is drawn as a white solid/dashed/dotted outline of
--that set. On an older engine (query missing) the rings fall back to colored
--distance annuli.
--
--Higher tiers strictly contain lower tiers (longer AND higher), so a ring
--identical to the previous one (fully movement-clamped, no extra reach) is
--collapsed into it.
function ActivatedAbilityJumpBehavior:GetTargetingTierRadii(ability, casterToken, symbols)
    local dists = self:GetTierDistances(ability, casterToken)
    if dists[3] <= 0 then
        return nil
    end

    local heights = self:GetTierHeights(ability, casterToken)

    --A caster who cannot roll below tier 2 (e.g. the Fury's Mighty Leaps) is
    --guaranteed the tier 2 jump, so only two rings are DRAWN, restyled so the
    --tier 2 ring reads as the safe one. The tier 1 ring stays in the list
    --marked invisible: the action bar still needs it to tell the baseline
    --auto-jump zone (no roll at all) apart from the guaranteed tier 2 zone
    --(a roll happens, success assured), but it draws no outline and produces
    --no shortfall marker (a tier 1 landing cannot be rolled).
    local hideTierOne = self:RollCannotBeTierOne(ability, casterToken)

    local result = {}
    for i = 1, 3 do
        if dists[i] > 0 then
            local styleIndex = i
            if hideTierOne then
                styleIndex = math.max(1, i - 1)
            end
            local ring = {
                tier = i,
                tiles = dists[i],
                height = heights[i],
                radius = dists[i] * dmhub.unitsPerSquare,
                color = self.tierColors[styleIndex],
                style = ActivatedAbilityJumpBehavior.tierStyles[styleIndex],
                label = string.format(tr("Tier %d"), i),
            }
            if i == 1 and hideTierOne then
                ring.invisible = true
            end

            local ok, locs = pcall(function()
                return casterToken:CalculateJumpReachable(dists[i], heights[i])
            end)
            if ok and locs ~= nil then
                ring.locs = locs
                ring.color = "white"
                ring.count = #locs
                ring.locSet = {}
                for _, l in ipairs(locs) do
                    ring.locSet[l.xyfloorOnly.str] = true
                end
            end

            --collapse: tier sets are monotone (a higher tier reaches everything a
            --lower one does), so equal counts mean identical sets. In fallback
            --mode compare the clamped distances instead. Never collapse into an
            --invisible ring: the visible ring must survive to be drawn.
            local prev = result[#result]
            local identical = false
            if prev ~= nil and (not prev.invisible) then
                if ring.locSet ~= nil and prev.locSet ~= nil then
                    identical = (ring.count == prev.count)
                else
                    identical = (ring.tiles == prev.tiles)
                end
            end

            if not identical then
                result[#result + 1] = ring
            end
        end
    end

    if #result == 0 then
        return nil
    end

    return result
end

--Where a jump capped at dTiles toward targetLoc comes down: the rounded lerp
--along the straight (Chebyshev) line at dTiles tiles out. Returns targetLoc
--itself when dTiles covers the full distance.
function ActivatedAbilityJumpBehavior.ShortLandingLoc(casterLoc, targetLoc, dTiles)
    local dist = casterLoc:DistanceInTiles(targetLoc)
    if dTiles >= dist then
        return targetLoc
    end
    if dTiles <= 0 then
        return casterLoc
    end

    local t = dTiles / dist
    return casterLoc:dir(round((targetLoc.x - casterLoc.x) * t), round((targetLoc.y - casterLoc.y) * t))
end

--Probes what a tier-t jump attempt toward targetLoc actually does, using the
--engine movement arrow to build a real jump path (straight line, clears
--height-limited walls up to the tier's jump height, stops at taller ones).
--The caller is responsible for casterToken:ClearMovementArrow() afterwards.
--Returns landLoc, reachesTarget, path.
function ActivatedAbilityJumpBehavior:ProbeTier(casterToken, targetLoc, tier, dists, heights)
    local attemptLoc = ActivatedAbilityJumpBehavior.ShortLandingLoc(casterToken.loc, targetLoc, dists[tier])
    local info = casterToken:MarkMovementArrow(attemptLoc, {
        jump = true,
        jumpHeight = heights[tier],
    })

    local landLoc = attemptLoc
    local path = nil
    if info ~= nil and info.path ~= nil then
        path = info.path
        if path.destination ~= nil then
            landLoc = path.destination
        end
    end

    --Reaching a SAME-floor target is a horizontal question: a jump that arrives
    --at the target's column and then falls (the player aimed at a chasm tile)
    --still "reached" it. A target on ANOTHER floor additionally requires landing
    --on that floor: the engine only lifts the landing onto an upper floor when
    --the rise is within the tier's jump height, so a too-high ledge leaves the
    --jump at the same x,y on the caster's own floor -- not a reach.
    local reaches = (landLoc.x == targetLoc.x and landLoc.y == targetLoc.y)
    if reaches and targetLoc.floor ~= casterToken.loc.floor then
        reaches = (landLoc.floor == targetLoc.floor)
    end
    return landLoc, reaches, path
end

--The lowest tier whose jump lands on targetLoc, considering both distance and
--the jump height needed to clear walls on the line. nil if even tier 3 cannot
--reach (e.g. a height-limited wall taller than 3 blocks the line).
function ActivatedAbilityJumpBehavior:CalculateRequiredTier(casterToken, targetLoc, dists, heights)
    local distToTarget = casterToken.loc:DistanceInTiles(targetLoc)
    for tier = 1, 3 do
        if dists[tier] >= distToTarget then
            local _, reaches = self:ProbeTier(casterToken, targetLoc, tier, dists, heights)
            if reaches then
                return tier
            end
        end
    end

    return nil
end

--Shows the test power roll dialog and waits for the result. Returns the
--rolled tier (1-3) after committing to paying for the ability, or nil if the
--player canceled (options.abort is set; nothing has been paid or moved).
--
--While the dialog is open a jump movement arrow is kept on the map showing
--where the jump currently lands: initially the chosen tile, then retargeted
--live as the dice tumble (the power table fires "tier" events with the tier
--the currently showing faces produce), settling on the rolled tier once the
--dice land. Every player sees it: PeerToPeerManager broadcasts active map
--arrows automatically, so keeping the local arrow marked is all that is
--needed. The arrow is cleared on cancel; on a completed roll it stays up
--until ExecuteJump clears it as the jump begins.
function ActivatedAbilityJumpBehavior:RollForTier(ability, casterToken, options, dists, heights, requiredTier, targetLoc)
    local creature = casterToken.properties

    --The tier the preview arrow currently shows. Before any dice show faces,
    --preview the tier needed to reach the chosen tile (tier 3 when even that
    --cannot reach: the arrow then shows the attempt stopping short).
    local m_previewTier = requiredTier or 3

    local function MarkPreviewArrow()
        if targetLoc == nil or casterToken == nil or (not casterToken.valid) then
            return
        end
        local landLoc = ActivatedAbilityJumpBehavior.ShortLandingLoc(casterToken.loc, targetLoc, dists[m_previewTier])
        casterToken:MarkMovementArrow(landLoc, {
            jump = true,
            jumpHeight = heights[m_previewTier],
        })
    end

    local roll = dmhub.EvalGoblinScript(self.roll, creature:LookupSymbol(options.symbols), "Jump test roll")

    --Skilled-hint handling matches creature:RollCustomPowerTableTest.
    --PowerRollOptions declares the jump skill, which both routes the Skilled
    --bonus and activates skill-gated modifiers like the Fury's Mighty Leaps
    --(nottierone), whose flag then flows through the roll into the tier.
    local modifiers = creature:GetModifiersForPowerRoll(roll, "test_power_roll", self:PowerRollOptions(ability))
    local skillid = self:try_get("skillid", "none")
    if skillid ~= "none" and skillid ~= "" then
        for _, modEntry in ipairs(modifiers) do
            if modEntry.modifier.name == "Skilled" then
                local skillInfo = dmhub.GetTable(Skill.tableName)[skillid]
                if skillInfo ~= nil and creature:ProficientInSkill(skillInfo) then
                    modEntry.modifier = DeepCopy(modEntry.modifier)
                    modEntry.modifier.name = string.format(tr("Skilled in %s"), skillInfo.name)
                    modEntry.modifier.description = string.format(tr("Skill in %s gives you +2 on this roll"), skillInfo.name)
                    modEntry.modifier.activationCondition = true
                    modEntry.hint.result = true
                elseif skillInfo ~= nil then
                    modEntry.modifier = DeepCopy(modEntry.modifier)
                    modEntry.modifier.description = string.format(tr("Not skilled in %s"), skillInfo.name)
                end
            end
        end
    end

    --Tier rows are display only; they are never parsed as rule commands.
    local tiers = {}
    for i = 1, 3 do
        local text = string.format(tr("Jump up to %d squares"), dists[i])
        if requiredTier == nil or i < requiredTier then
            text = text .. tr(" (lands short)")
        end
        tiers[i] = text
    end

    local rollProperties = RollPropertiesPowerTable.new{
        tiers = tiers,
        fullyImplemented = true,
    }

    local m_result = nil
    local m_canceled = false

    local dialog = CharacterPanel.AcquireAbilityRollDialog(casterToken, ability, options.symbols, {lock = true, renderAsAbility = true}, options)
    if dialog == nil or not dialog.valid then
        dialog = GameHud.instance.rollDialog
    end
    if dialog == nil or not dialog.valid then
        return nil
    end

    dialog.data.ShowDialog{
        title = ability.name,
        description = ability.name .. ": " .. tr("Test"),
        type = "test_power_roll",
        ability = ability,
        roll = roll,
        creature = creature,
        symbols = options.symbols,
        modifiers = modifiers,
        rollProperties = rollProperties,
        showDialogDuringRoll = true,
        amendable = true,

        PopulateCustom = function(parentPanel)
            ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(rollProperties, creature, {
                ability = ability,
            })(parentPanel)

            --Inject an invisible listener under the power table: the table
            --fires "tier" events down its own subtree as the dice tumble,
            --settle, and get amended (boons/overrides), and we retarget the
            --preview arrow to that tier's landing each time.
            local tbl = parentPanel.children[1]
            if tbl ~= nil then
                tbl:AddChild(gui.Panel{
                    width = 0,
                    height = 0,
                    interactable = false,
                    tier = function(element, tierNumber)
                        if type(tierNumber) ~= "number" then
                            return
                        end
                        local t = math.max(1, math.min(3, tierNumber))
                        if t ~= m_previewTier then
                            m_previewTier = t
                            MarkPreviewArrow()
                        end
                    end,
                })
            end
        end,

        completeRoll = function(rollInfo)
            if rollInfo == nil then
                return
            end
            m_result = {
                total = rollInfo.total,
                boons = rollInfo.boons,
                banes = rollInfo.banes,
                tiers = rollInfo.tiers,
                nottierone = rollInfo.nottierone,
                nottierthree = rollInfo.nottierthree,
                autofailure = rollInfo.autofailure,
                autosuccess = rollInfo.autosuccess,
            }

            options.symbols.cast.naturalRoll = rollInfo.naturalRoll
            options.symbols.cast.casterid = casterToken.id
        end,

        cancelRoll = function()
            m_canceled = true
        end,
    }

    while (not m_canceled) and (m_result == nil or m_result.total == nil) do
        --Keep the preview arrow alive: the action bar's targeting teardown
        --clears movement arrows around the time the cast begins, and can run
        --after our initial mark. Re-marking each tick self-heals within 0.1s
        --and keeps the arrow broadcasting to other players.
        MarkPreviewArrow()
        coroutine.yield(0.1)
    end

    --Test hook parity with power rolls: pause between roll-complete and tier
    --read so a harness can deterministically write rollProperties.overrideTier.
    while (not m_canceled) and dmhub.GetSettingValue("test:aiholdroll") do
        coroutine.yield(0.02)
    end

    CharacterPanel.UnlockDisplayAbility()

    if m_canceled then
        casterToken:ClearMovementArrow()
        options.abort = true
        return nil
    end

    local tier = rollProperties:try_get("overrideTier") or RollUtils.DiceResultToTier(m_result)
    if tier < 1 then
        tier = 1
    elseif tier > 3 then
        tier = 3
    end

    --Settle the arrow on the final tier. Usually a no-op (the live dice
    --events already put it there); covers overrideTier and amendments that
    --arrive between the last dice event and here.
    if tier ~= m_previewTier then
        m_previewTier = tier
        MarkPreviewArrow()
    end

    ability:CommitToPaying(casterToken, options)
    return tier
end

--Executes the tier's jump toward targetLoc: lands on the target when the tier
--covers it, otherwise comes down short along the line (the engine appends the
--fall automatically when the landing tile has no ground), then charges the
--distance moved against this turn's movement budget (same semantics as the
--"jump N" rule command in MCDMAbilityBehavior).
function ActivatedAbilityJumpBehavior:ExecuteJump(ability, casterToken, targetLoc, tier, dists, heights, options)
    --The roll-preview arrow lives until the jump actually executes.
    casterToken:ClearMovementArrow()

    local landLoc = ActivatedAbilityJumpBehavior.ShortLandingLoc(casterToken.loc, targetLoc, dists[tier])

    casterToken.properties._tmp_freeMovement = true

    local path = casterToken:Move(landLoc, {
        ignoreFalling = true,
        straightline = true,
        moveThroughFriends = true,
        ignorecreatures = true,
        maxCost = 30000,
        movementType = "jump",
        jumpHeight = heights[tier],
    })

    if path ~= nil and path.numSteps ~= 0 then
        options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + path.numSteps

        local numSteps = path.numSteps
        casterToken:ModifyProperties{
            description = "Jump Move Cost",
            undoable = false,
            execute = function()
                if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                    return
                end
                casterToken.properties.moveDistance = casterToken.properties:DistanceMovedThisTurn() + numSteps
                casterToken.properties.moveDistanceRoundId = dmhub.initiativeQueue:GetTurnId()
            end,
        }
    end
end

function ActivatedAbilityJumpBehavior:Cast(ability, casterToken, targets, options)
    if #targets == 0 or targets[#targets].loc == nil then
        return
    end

    local targetLoc = targets[#targets].loc

    local dists = self:GetTierDistances(ability, casterToken)
    if dists[3] <= 0 then
        return
    end

    local heights = self:GetTierHeights(ability, casterToken)

    local distToTarget = casterToken.loc:DistanceInTiles(targetLoc)
    if distToTarget <= 0 then
        return
    end

    local requiredTier = self:CalculateRequiredTier(casterToken, targetLoc, dists, heights)
    casterToken:ClearMovementArrow()

    local tier
    if requiredTier == 1 then
        --Baseline jump: automatic, no test (rules: a long jump up to your
        --jump distance at baseline height is always successful).
        tier = 1
        ability:CommitToPaying(casterToken, options)
    else
        tier = self:RollForTier(ability, casterToken, options, dists, heights, requiredTier, targetLoc)
        if tier == nil then
            --roll canceled; options.abort already set.
            return
        end
    end

    self:ExecuteJump(ability, casterToken, targetLoc, tier, dists, heights, options)
end

function ActivatedAbilityJumpBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)
    return result
end
