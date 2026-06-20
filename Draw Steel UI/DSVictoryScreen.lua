local mod = dmhub.GetModLoading()

----------------------------------------------------------------------
-- DSVictoryScreen
--
-- A full-screen "the heroes have won" celebration. When the director presses
-- "Award Victory" on the initiative bar, the live encounter's victoryAwarded flag is
-- flipped (LiveEncounter.victoryAwarded, networked inside the initiative queue). Every
-- client polls that flag; when it is set the normal initiative display is hidden (see
-- MCDMInitiativeBar.lua) and this screen takes over: the screen darkens, a "Victory"
-- title sweeps in across the top, and the heroes fade in one by one with their
-- portraits, names, Stamina, and how their Recoveries changed over the fight. Dead
-- heroes are marked DEAD.
--
-- The director gets a "Proceed" button at the bottom; pressing it ends combat and
-- clears the victory state, which closes the screen for every client.
--
-- The screen is created once and mounted at the top of the game HUD (see GameHud.lua).
-- It reads its state straight from dmhub.initiativeQueue.liveEncounter, so no separate
-- synced document is needed -- the live encounter is already networked to all clients.
----------------------------------------------------------------------

RegisterGameType("DSVictoryScreen")

-- Seconds between each hero fading in.
local g_heroStagger = 0.28

-- The victory (Victories resource) icon, dropped into each hero's card on Award.
local VICTORY_ICON = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png"

----------------------------------------------------------------------
-- Hero roles
--
-- Fun titles awarded from the live encounter's per-round hero stats (see
-- Draw Steel Core Rules/STATS_TRACKING.md for the stats and their layout).
-- Candidate roles are evaluated in priority order, most interesting first;
-- each hero is shown the single highest-priority role they earned, so a hero
-- who is both the top damage dealer and the round-1 Initiator shows only
-- Damage Dealer. A role whose winner earned a better role is simply not shown
-- for anyone (its criteria name a unique winner).
--
-- Stats consumed: damageDealt, damageTaken, damagePrevention, overkill, kills,
-- minionKills, criticals (recorded by the shipped Critical Hit content),
-- tierRolls, edges, banes, spacesMoved, forcedMovementDealt,
-- forcedMovementTaken, standsFirm, allyDamageDealt, enemyTurnDamage,
-- heroicResourcesGained, heroicResourcesSpent, conditionsInflicted.
----------------------------------------------------------------------

local function ComputeHeroRolesInternal(live)
    local roles = {}

    local heroTokens = live:GetBattleHeroTokens()
    if heroTokens == nil or #heroTokens == 0 then
        return roles
    end

    --Gather each hero's whole-encounter totals and numeric-keyed per-round
    --stats once up front, plus the last round anyone recorded a stat in.
    local data = {}
    local partyDamageTaken = 0
    local finalRound = 0
    for _, tok in ipairs(heroTokens) do
        local rounds = {}
        for roundKey, stats in pairs(live:GetStatsForTokenByRound(tok.charid)) do
            local n = tonumber(string.match(tostring(roundKey), "^round(%d+)$"))
            if n ~= nil and type(stats) == "table" then
                rounds[n] = stats
                if n > finalRound then
                    finalRound = n
                end
            end
        end

        local entry = {
            token = tok,
            name = tok.name or "Hero",
            totals = live:GetStatsForToken(tok.charid),
            rounds = rounds,
        }
        partyDamageTaken = partyDamageTaken + (entry.totals.damageTaken or 0)
        data[#data+1] = entry
    end

    --Stat accessors. Totals are whole-encounter sums; RoundStat reads one
    --round's bucket; the Nested variants handle sub-table stats (tierRolls,
    --conditionsInflicted, ...).
    local function Total(d, stat)
        local v = d.totals[stat]
        return type(v) == "number" and v or 0
    end

    local function RoundStat(d, n, stat)
        local r = d.rounds[n]
        local v = r ~= nil and r[stat] or nil
        return type(v) == "number" and v or 0
    end

    local function NestedTotal(d, stat)
        local t = d.totals[stat]
        if type(t) ~= "table" then
            return 0
        end
        local sum = 0
        for _, v in pairs(t) do
            if type(v) == "number" then
                sum = sum + v
            end
        end
        return sum
    end

    local function NestedStat(d, stat, key)
        local t = d.totals[stat]
        if type(t) == "table" and type(t[key]) == "number" then
            return t[key]
        end
        return 0
    end

    --The qualifying heroes for a stat, best first. fn returns the hero's value
    --for the role (or nil to disqualify); values must also be > 0 and >=
    --minValue. Ties keep party order.
    local function RankBy(fn, minValue)
        local list = {}
        for order, d in ipairs(data) do
            local v = fn(d)
            if v ~= nil and v > 0 and v >= (minValue or 1) then
                list[#list+1] = { d = d, value = v, order = order }
            end
        end
        table.sort(list, function(a, b)
            if a.value ~= b.value then
                return a.value > b.value
            end
            return a.order < b.order
        end)
        return list
    end

    --Candidate roles, built in priority order (most interesting first). Each
    --role carries a RANKED list of qualifying heroes: when it is awarded, it
    --goes to the highest-ranked qualifier who has no role yet, so a role whose
    --winner earned something better falls through to the runner-up instead of
    --vanishing. allowDuplicates marks floor roles (Pacifist/Tourist) that may
    --appear on several cards at once.
    local candidates = {}
    local function AddRole(role, entries, allowDuplicates)
        if entries ~= nil and #entries > 0 then
            candidates[#candidates+1] = {
                role = role,
                entries = entries,
                allowDuplicates = allowDuplicates,
            }
        end
    end

    --Damage Dealer: the most damage dealt. Tooltip fun fact: the best OTHER
    --damage dealer.
    do
        local ranked = RankBy(function(d) return Total(d, "damageDealt") end)
        local entries = {}
        for i, e in ipairs(ranked) do
            local other = ranked[cond(i == 1, 2, 1)]
            local tooltip = "Nobody else dealt any damage"
            if other ~= nil then
                tooltip = string.format("%s dealt %d damage", other.d.name, other.value)
            end
            entries[#entries+1] = { d = e.d, text = string.format("Dealt %d damage", e.value), tooltip = tooltip }
        end
        AddRole("Damage Dealer", entries)
    end

    --Initiator: big round-1 damage -- at least 8 per hero level.
    do
        local ranked = RankBy(function(d)
            local amount = RoundStat(d, 1, "damageDealt")
            local level = 1
            if d.token.properties ~= nil then
                level = d.token.properties:CharacterLevel() or 1
            end
            if amount >= 8 * math.max(1, level) then
                return amount
            end
            return nil
        end)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("Dealt %d damage on round 1", e.value),
                tooltip = string.format("You spent %d heroic resources in doing so", RoundStat(e.d, 1, "heroicResourcesSpent")),
            }
        end
        AddRole("Initiator", entries)
    end

    --Big Hitter: the biggest single-round damage total, excluding round 1
    --(round-1 alpha strikes belong to Initiator).
    do
        local ranked = RankBy(function(d)
            local best = 0
            for n, _ in pairs(d.rounds) do
                if n >= 2 then
                    local v = RoundStat(d, n, "damageDealt")
                    if v > best then
                        best = v
                    end
                end
            end
            return best
        end)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("Dealt %d damage in a single round", e.value),
                tooltip = string.format("You dealt %d damage during the encounter", Total(e.d, "damageDealt")),
            }
        end
        AddRole("Big Hitter", entries)
    end

    --Deadeye: the most critical hits, at least 2.
    do
        local ranked = RankBy(function(d) return Total(d, "criticals") end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You got %d critical hits", e.value),
                tooltip = string.format("You dealt %d damage this encounter", Total(e.d, "damageDealt")),
            }
        end
        AddRole("Deadeye", entries)
    end

    --Hat Trick: at least 2 critical hits within a single round.
    do
        local function BestCritRound(d)
            local best = 0
            local bestRound = nil
            for n, _ in pairs(d.rounds) do
                local v = RoundStat(d, n, "criticals")
                if v > best then
                    best = v
                    bestRound = n
                end
            end
            return best, bestRound
        end

        local ranked = RankBy(function(d) return (BestCritRound(d)) end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            local _, roundNum = BestCritRound(e.d)
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You got %d critical hits in round %d", e.value, roundNum),
                tooltip = string.format("You dealt %d damage on round %d", RoundStat(e.d, roundNum, "damageDealt"), roundNum),
            }
        end
        AddRole("Hat Trick", entries)
    end

    --The Shield: the most damage prevention, at least 10.
    do
        local ranked = RankBy(function(d) return Total(d, "damagePrevention") end, 10)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You prevented %d damage this encounter", e.value),
                tooltip = string.format("You and your teammates took %d damage this encounter", partyDamageTaken),
            }
        end
        AddRole("The Shield", entries)
    end

    --Executioner: the most kills, at least 2.
    do
        local ranked = RankBy(function(d) return Total(d, "kills") end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You finished off %d enemies", e.value),
                tooltip = string.format("You dealt %d damage this encounter", Total(e.d, "damageDealt")),
            }
        end
        AddRole("Executioner", entries)
    end

    --Minion Mower: the most minion kills, at least 3.
    do
        local ranked = RankBy(function(d) return Total(d, "minionKills") end, 3)
        local entries = {}
        for _, e in ipairs(ranked) do
            local bestRound = nil
            local bestCount = 0
            for n, _ in pairs(e.d.rounds) do
                local v = RoundStat(e.d, n, "minionKills")
                if v > bestCount then
                    bestCount = v
                    bestRound = n
                end
            end
            local tooltip = "They never stood a chance"
            if bestRound ~= nil then
                tooltip = string.format("%d of them in round %d alone", bestCount, bestRound)
            end
            entries[#entries+1] = { d = e.d, text = string.format("You mowed down %d minions", e.value), tooltip = tooltip }
        end
        AddRole("Minion Mower", entries)
    end

    --Overkill: the most overkill damage, at least 10.
    do
        local ranked = RankBy(function(d) return Total(d, "overkill") end, 10)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You dealt %d more damage than strictly necessary", e.value),
                tooltip = "Subtlety is overrated",
            }
        end
        AddRole("Overkill", entries)
    end

    --Closer: the most kills in the final round.
    do
        if finalRound >= 2 then
            local ranked = RankBy(function(d) return RoundStat(d, finalRound, "kills") end)
            local entries = {}
            for _, e in ipairs(ranked) do
                entries[#entries+1] = {
                    d = e.d,
                    text = string.format("You ended %d %s in the final round", e.value, cond(e.value == 1, "enemy", "enemies")),
                    tooltip = "Someone had to finish it",
                }
            end
            AddRole("Closer", entries)
        end
    end

    --Martyr: took the most damage and fell.
    do
        local ranked = RankBy(function(d)
            local dead = d.token.properties ~= nil and d.token.properties:IsDead()
            if dead then
                return Total(d, "damageTaken")
            end
            return nil
        end)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You took %d damage before falling", e.value),
                tooltip = "Your sacrifice will be remembered",
            }
        end
        AddRole("Martyr", entries)
    end

    --Punching Bag: took the most damage (at least 15) and kept standing.
    do
        local ranked = RankBy(function(d)
            local dead = d.token.properties ~= nil and d.token.properties:IsDead()
            if not dead then
                return Total(d, "damageTaken")
            end
            return nil
        end, 15)
        local entries = {}
        for i, e in ipairs(ranked) do
            local other = ranked[cond(i == 1, 2, 1)]
            local tooltip = "Nobody else soaked anywhere near that much"
            if other ~= nil then
                tooltip = string.format("%s took %d and stayed up too", other.d.name, other.value)
            end
            entries[#entries+1] = { d = e.d, text = string.format("You took %d damage and kept standing", e.value), tooltip = tooltip }
        end
        AddRole("Punching Bag", entries)
    end

    --Untouchable: the only hero who took no damage at all (needs a party).
    do
        if #data >= 2 then
            local zeroes = {}
            for _, d in ipairs(data) do
                if Total(d, "damageTaken") == 0 then
                    zeroes[#zeroes+1] = d
                end
            end
            if #zeroes == 1 then
                AddRole("Untouchable", {{
                    d = zeroes[1],
                    text = "You took no damage at all",
                    tooltip = string.format("Your allies took %d between them", partyDamageTaken),
                }})
            end
        end
    end

    --Immovable Object: stood firm against the most forced moves, at least 2.
    do
        local ranked = RankBy(function(d) return Total(d, "standsFirm") end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You stood firm against %d forced moves", e.value),
                tooltip = string.format("Enemies moved you only %d spaces all fight", Total(e.d, "forcedMovementTaken")),
            }
        end
        AddRole("Immovable Object", entries)
    end

    --Ragdoll: took the most forced movement, at least 6 spaces.
    do
        local ranked = RankBy(function(d) return Total(d, "forcedMovementTaken") end, 6)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You got thrown around %d spaces", e.value),
                tooltip = string.format("And took %d damage along the way", Total(e.d, "damageTaken")),
            }
        end
        AddRole("Ragdoll", entries)
    end

    --Battering Ram: force-moved enemies the most spaces, at least 5.
    do
        local ranked = RankBy(function(d) return Total(d, "forcedMovementDealt") end, 5)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You shoved enemies %d spaces", e.value),
                tooltip = "Walls were involved",
            }
        end
        AddRole("Battering Ram", entries)
    end

    --Marathon Runner: moved the most spaces, at least 8.
    do
        local ranked = RankBy(function(d) return Total(d, "spacesMoved") end, 8)
        local entries = {}
        for i, e in ipairs(ranked) do
            local tooltip = "More than anyone else on the field"
            if i > 1 then
                tooltip = string.format("Though %s moved %d", ranked[1].d.name, ranked[1].value)
            end
            entries[#entries+1] = { d = e.d, text = string.format("You moved %d spaces this encounter", e.value), tooltip = tooltip }
        end
        AddRole("Marathon Runner", entries)
    end

    --Statue: never moved (voluntarily or otherwise) yet still dealt damage.
    do
        local ranked = RankBy(function(d)
            if Total(d, "spacesMoved") == 0 and Total(d, "forcedMovementTaken") == 0 then
                return Total(d, "damageDealt")
            end
            return nil
        end)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = "You never moved a single space",
                tooltip = string.format("And still dealt %d damage", e.value),
            }
        end
        AddRole("Statue", entries)
    end

    --Puppet Master: inflicted the most conditions, at least 3. Tooltip calls
    --out their most-used condition.
    do
        local ranked = RankBy(function(d) return NestedTotal(d, "conditionsInflicted") end, 3)
        local entries = {}
        for _, e in ipairs(ranked) do
            local bestName = nil
            local bestCount = 0
            local t = e.d.totals.conditionsInflicted
            if type(t) == "table" then
                for name, v in pairs(t) do
                    if type(v) == "number" and v > bestCount then
                        bestName = name
                        bestCount = v
                    end
                end
            end
            local tooltip = "The battlefield danced to your tune"
            if bestName ~= nil then
                tooltip = string.format("Including %d %s", bestCount, bestName)
            end
            entries[#entries+1] = { d = e.d, text = string.format("You inflicted %d conditions", e.value), tooltip = tooltip }
        end
        AddRole("Puppet Master", entries)
    end

    --Wrestler: grabbed enemies the most, at least 2.
    do
        local ranked = RankBy(function(d) return NestedStat(d, "conditionsInflicted", "grabbed") end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You grabbed enemies %d times", e.value),
                tooltip = "Nobody escapes",
            }
        end
        AddRole("Wrestler", entries)
    end

    --Down You Go: knocked enemies prone the most, at least 2.
    do
        local ranked = RankBy(function(d) return NestedStat(d, "conditionsInflicted", "prone") end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You knocked enemies down %d times", e.value),
                tooltip = string.format("You dealt %d damage this encounter", Total(e.d, "damageDealt")),
            }
        end
        AddRole("Down You Go", entries)
    end

    --Fearmonger: frightened enemies the most, at least 2.
    do
        local ranked = RankBy(function(d) return NestedStat(d, "conditionsInflicted", "frightened") end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You frightened enemies %d times", e.value),
                tooltip = "They were right to be afraid",
            }
        end
        AddRole("Fearmonger", entries)
    end

    --Playmaker: allies dealt the most damage during their turns, at least 10.
    do
        local ranked = RankBy(function(d) return Total(d, "allyDamageDealt") end, 10)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("Allies dealt %d damage during your turns", e.value),
                tooltip = "You set them up; they knocked them down",
            }
        end
        AddRole("Playmaker", entries)
    end

    --Opportunist: dealt the most damage on enemy turns, at least 8.
    do
        local ranked = RankBy(function(d) return Total(d, "enemyTurnDamage") end, 8)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You dealt %d damage on enemy turns", e.value),
                tooltip = "Free strikes add up",
            }
        end
        AddRole("Opportunist", entries)
    end

    --Big Spender: spent the most heroic resources, at least 10.
    do
        local ranked = RankBy(function(d) return Total(d, "heroicResourcesSpent") end, 10)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You spent %d heroic resources", e.value),
                tooltip = string.format("You generated %d this encounter", Total(e.d, "heroicResourcesGained")),
            }
        end
        AddRole("Big Spender", entries)
    end

    --Power Plant: generated the most heroic resources.
    do
        local ranked = RankBy(function(d) return Total(d, "heroicResourcesGained") end)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You generated %d heroic resources", e.value),
                tooltip = string.format("And spent %d of them", Total(e.d, "heroicResourcesSpent")),
            }
        end
        AddRole("Power Plant", entries)
    end

    --Hoarder: gained plenty (at least 8) but spent less than half of it.
    do
        local ranked = RankBy(function(d)
            local gained = Total(d, "heroicResourcesGained")
            local spent = Total(d, "heroicResourcesSpent")
            if gained >= 8 and spent * 2 < gained then
                return gained - spent
            end
            return nil
        end)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You saved up %d unspent heroic resources", e.value),
                tooltip = "They don't carry over, you know",
            }
        end
        AddRole("Hoarder", entries)
    end

    --Hot Streak: rolled tier 3 the most, at least 3 times. The tooltip
    --reminds them how many edges they had.
    do
        local ranked = RankBy(function(d) return NestedStat(d, "tierRolls", "tier3") end, 3)
        local entries = {}
        for _, e in ipairs(ranked) do
            local edges = Total(e.d, "edges")
            local tooltip = "And not a single edge to help you"
            if edges > 0 then
                tooltip = string.format("Maybe the %d %s you got helped you?", edges, cond(edges == 1, "edge", "edges"))
            end
            entries[#entries+1] = { d = e.d, text = string.format("You rolled tier 3 %d times", e.value), tooltip = tooltip }
        end
        AddRole("Hot Streak", entries)
    end

    --Edgelord: rolled with the most edges, at least 4.
    do
        local ranked = RankBy(function(d) return Total(d, "edges") end, 4)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You rolled with %d edges", e.value),
                tooltip = "Your allies kept setting you up",
            }
        end
        AddRole("Edgelord", entries)
    end

    --Against All Odds: suffered the most banes, at least 4, but still dealt
    --damage anyway.
    do
        local ranked = RankBy(function(d)
            if Total(d, "damageDealt") > 0 then
                return Total(d, "banes")
            end
            return nil
        end, 4)
        local entries = {}
        for _, e in ipairs(ranked) do
            entries[#entries+1] = {
                d = e.d,
                text = string.format("You fought through %d banes", e.value),
                tooltip = string.format("And still dealt %d damage", Total(e.d, "damageDealt")),
            }
        end
        AddRole("Against All Odds", entries)
    end

    --Metronome: dealt damage in every round (needs at least 2 rounds).
    do
        if finalRound >= 2 then
            local ranked = RankBy(function(d)
                for n = 1, finalRound do
                    if RoundStat(d, n, "damageDealt") <= 0 then
                        return nil
                    end
                end
                return Total(d, "damageDealt")
            end)
            local entries = {}
            for _, e in ipairs(ranked) do
                entries[#entries+1] = {
                    d = e.d,
                    text = "You dealt damage every round",
                    tooltip = string.format("Totaling %d", e.value),
                }
            end
            AddRole("Metronome", entries)
        end
    end

    --Slow Burn: damage strictly increased every round (needs at least 3
    --rounds).
    do
        if finalRound >= 3 then
            local ranked = RankBy(function(d)
                if RoundStat(d, finalRound, "damageDealt") <= 0 then
                    return nil
                end
                for n = 2, finalRound do
                    if RoundStat(d, n, "damageDealt") <= RoundStat(d, n - 1, "damageDealt") then
                        return nil
                    end
                end
                return RoundStat(d, finalRound, "damageDealt")
            end)
            local entries = {}
            for _, e in ipairs(ranked) do
                entries[#entries+1] = {
                    d = e.d,
                    text = "Your damage went up every round",
                    tooltip = string.format("Round 1: %d, final round: %d",
                        RoundStat(e.d, 1, "damageDealt"), RoundStat(e.d, finalRound, "damageDealt")),
                }
            end
            AddRole("Slow Burn", entries)
        end
    end

    --Grand Finale: the most damage in the final round, at least 10 (needs at
    --least 2 rounds so it is distinct from Initiator).
    do
        if finalRound >= 2 then
            local ranked = RankBy(function(d) return RoundStat(d, finalRound, "damageDealt") end, 10)
            local entries = {}
            for _, e in ipairs(ranked) do
                entries[#entries+1] = {
                    d = e.d,
                    text = string.format("You dealt %d damage in the final round", e.value),
                    tooltip = "Saving the best for last",
                }
            end
            AddRole("Grand Finale", entries)
        end
    end

    --Cold Dice: rolled tier 1 the most, at least 2 times. A sympathy role
    --near the bottom of the list; the tooltip reminds them of their banes.
    do
        local ranked = RankBy(function(d) return NestedStat(d, "tierRolls", "tier1") end, 2)
        local entries = {}
        for _, e in ipairs(ranked) do
            local banes = Total(e.d, "banes")
            local tooltip = "And you can't even blame the banes"
            if banes > 0 then
                tooltip = string.format("Maybe the %d %s you suffered didn't help?", banes, cond(banes == 1, "bane", "banes"))
            end
            entries[#entries+1] = { d = e.d, text = string.format("You rolled tier 1 %d times", e.value), tooltip = tooltip }
        end
        AddRole("Cold Dice", entries)
    end

    --Pacifist: dealt no damage, but contributed in some other tracked way.
    --A floor role: may appear on several cards.
    do
        local entries = {}
        for _, d in ipairs(data) do
            if Total(d, "damageDealt") == 0 then
                local conditions = NestedTotal(d, "conditionsInflicted")
                local prevention = Total(d, "damagePrevention")
                local spent = Total(d, "heroicResourcesSpent")
                local tooltip = nil
                if conditions > 0 then
                    tooltip = string.format("But you inflicted %d %s", conditions, cond(conditions == 1, "condition", "conditions"))
                elseif prevention > 0 then
                    tooltip = string.format("But you prevented %d damage", prevention)
                elseif spent > 0 then
                    tooltip = string.format("But you spent %d heroic resources", spent)
                end
                if tooltip ~= nil then
                    entries[#entries+1] = { d = d, text = "You dealt no damage at all", tooltip = tooltip }
                end
            end
        end
        AddRole("Pacifist", entries, true)
    end

    --Tourist: no damage, no conditions, no prevention, no resources spent.
    --The last-resort floor role: may appear on several cards.
    do
        local entries = {}
        for _, d in ipairs(data) do
            if Total(d, "damageDealt") == 0
                and NestedTotal(d, "conditionsInflicted") == 0
                and Total(d, "damagePrevention") == 0
                and Total(d, "heroicResourcesSpent") == 0 then
                entries[#entries+1] = { d = d, text = "You were there", tooltip = "And that counts for something" }
            end
        end
        AddRole("Tourist", entries, true)
    end

    --How many times a hero has previously been awarded a given role, read from
    --the persistent per-hero history written by RecordHeroRoles at end of
    --combat. Used to bias selection toward roles a hero has earned less often.
    --Read-only here; missing/never-played heroes read 0 and so behave exactly
    --as they did before any history existed.
    local function RoleCount(d, roleName)
        local props = d.token ~= nil and d.token.properties or nil
        local history = props ~= nil and props:try_get("dsVictoryRoleHistory") or nil
        if type(history) ~= "table" then
            return 0
        end
        local n = history[roleName]
        return type(n) == "number" and n or 0
    end

    --Soft-bias tuning weights (all integers; bigger = stronger pull). Selection
    --is deterministic -- every client computes the same roles from the same
    --stats + history -- so these just shape which qualifying role a hero lands
    --on, never introduce randomness:
    --  INTEREST: each step down the (in-play) priority list a role sits costs
    --            this much, so a more interesting role still wins all else equal.
    --  FATIGUE : each past time THIS hero earned THIS role pushes it down by
    --            this much. With FATIGUE < INTEREST a hero keeps a strictly more
    --            interesting role through one repeat and only rotates onto a
    --            nearby alternative after earning it "over and over". Raise
    --            FATIGUE (or lower INTEREST) to rotate more aggressively.
    --  RANK    : pure tiebreak below -- prefer the better-ranked qualifier
    --            within a role; never crosses a priority step.
    local INTEREST_WEIGHT = 4
    local FATIGUE_WEIGHT = 3

    --Award the interesting (non-floor) roles first, then the floor roles. Floor
    --roles (Pacifist/Tourist, flagged allowDuplicates) are deliberately kept out
    --of the biased pool: we never steer anyone toward a "boring" role, so they
    --only ever land as a last resort, below.
    local interestingCandidates = {}
    local floorCandidates = {}
    for _, candidate in ipairs(candidates) do
        if candidate.allowDuplicates then
            floorCandidates[#floorCandidates+1] = candidate
        else
            interestingCandidates[#interestingCandidates+1] = candidate
        end
    end

    --Build one scored hero<->role edge per (interesting role, qualifier), then
    --assign greedily by score. Each interesting role goes to a single hero and
    --each hero takes at most one, so a role shadowed for its best qualifier
    --still falls through to a runner-up, exactly as the old priority loop did --
    --and with no history the scores collapse to plain priority order, so the
    --behavior is unchanged until a hero has actually repeated a role.
    local edges = {}
    for priorityIdx, candidate in ipairs(interestingCandidates) do
        for rank, entry in ipairs(candidate.entries) do
            edges[#edges+1] = {
                candidate = candidate,
                entry = entry,
                charid = entry.d.token.charid,
                priorityIdx = priorityIdx,
                rank = rank,
                score = -(priorityIdx - 1) * INTEREST_WEIGHT
                        - RoleCount(entry.d, candidate.role) * FATIGUE_WEIGHT,
            }
        end
    end

    --Highest score first; deterministic tiebreaks (priority, then rank within a
    --role, then charid) so every client resolves ties identically. Rank lives
    --only here, never in the score, so it orders qualifiers and breaks ties but
    --can never let a worse-ranked hero leapfrog a more interesting role.
    table.sort(edges, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        if a.priorityIdx ~= b.priorityIdx then
            return a.priorityIdx < b.priorityIdx
        end
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.charid < b.charid
    end)

    local roleTaken = {}
    for _, edge in ipairs(edges) do
        local charid = edge.charid
        if roles[charid] == nil and not roleTaken[edge.candidate.role] then
            roles[charid] = {
                role = edge.candidate.role,
                text = edge.entry.text,
                tooltip = edge.entry.tooltip,
            }
            roleTaken[edge.candidate.role] = true
        end
    end

    --Floor roles last, in priority order, landing on every still-roleless
    --qualifying hero (they allow duplicates and are never biased).
    for _, candidate in ipairs(floorCandidates) do
        for _, entry in ipairs(candidate.entries) do
            local charid = entry.d.token.charid
            if roles[charid] == nil then
                roles[charid] = {
                    role = candidate.role,
                    text = entry.text,
                    tooltip = entry.tooltip,
                }
            end
        end
    end

    return roles
end

--Compute the fun role each party member played this encounter.
--Returns { [charid] = { role = "Damage Dealer", text = "Dealt 47 damage",
--tooltip = "Mirala dealt 31 damage" } }; heroes who earned no role are simply
--absent. Never throws -- any failure (stats missing, old encounter data)
--returns an empty table so the victory screen renders without roles.
function DSVictoryScreen.ComputeHeroRoles(live)
    if live == nil then
        return {}
    end

    local ok, result = pcall(ComputeHeroRolesInternal, live)
    if not ok or type(result) ~= "table" then
        return {}
    end

    return result
end

--Debugging macro: prints the role each hero would be awarded if the current
--combat ended right now, using the exact logic the victory screen uses.
--Unlike the screen itself it does NOT require victory to have been awarded --
--any active combat with a live encounter works, so it can be run mid-fight to
--watch the roles shift as stats accumulate.
Commands.RegisterMacro{
    name = "roles",
    summary = "Show the victory-screen role each hero would get if combat ended now.",
    doc = "Usage: /roles\nAnalyzes the current combat's live encounter stats and prints, for each hero, the role the victory screen would award them if the encounter ended right now, along with the role's detail line and fun-fact tooltip.",
    command = function()
        local q = dmhub.initiativeQueue
        if q == nil or q:try_get("hidden") then
            print("Roles: no active combat.")
            return
        end

        local live = q:try_get("liveEncounter")
        if type(live) ~= "table" then
            print("Roles: this combat has no live encounter (stats are only recorded in live encounters).")
            return
        end

        local heroTokens = live:GetBattleHeroTokens()
        if heroTokens == nil or #heroTokens == 0 then
            print("Roles: no heroes are participating in this encounter.")
            return
        end

        local roles = DSVictoryScreen.ComputeHeroRoles(live)

        print(string.format("Roles: if the encounter ended now (round %d):", q.round or 0))
        for _, tok in ipairs(heroTokens) do
            local name = tok.name or "Hero"
            local info = roles[tok.charid]
            if info ~= nil then
                --show how many times this hero has earned this role before, so the
                --less-often-achieved bias is visible as stats/history accumulate.
                local history = tok.properties ~= nil and tok.properties:try_get("dsVictoryRoleHistory") or nil
                local prior = (type(history) == "table" and type(history[info.role]) == "number") and history[info.role] or 0
                print(string.format("  %s: %s (earned %dx before) -- \"%s\" (tooltip: \"%s\")", name, info.role, prior, info.text, info.tooltip))
            else
                print(string.format("  %s: (no role)", name))
            end
        end
    end,
}

-- Returns the live encounter if and only if it is currently in the victory state
-- (combat active + victory awarded); otherwise nil.
local function GetActiveVictory()
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return nil
    end
    local live = q:try_get("liveEncounter")
    if type(live) ~= "table" or not live:try_get("victoryAwarded", false) then
        print("VICTORY:: GetActiveVictory -> nil")
        return nil
    end
        print("VICTORY:: GetActiveVictory -> live", live)
    return live
end

-- Record the role each hero was awarded this encounter into their persistent
-- per-hero history (character.dsVictoryRoleHistory, a map of role name -> times
-- earned). ComputeHeroRolesInternal reads this back to bias future encounters
-- away from roles a hero has earned often. Run once, DM-only, at end of combat:
-- the role assignment is deterministic, so recomputing it here yields the same
-- roles every client saw on the victory screen. Floor roles (Tourist/Pacifist)
-- are recorded too but never bias selection, so counting them is harmless.
local function RecordHeroRoles(live)
    if type(live) ~= "table" or not dmhub.isDM then
        return
    end
    -- Guard against a double-proceed re-recording the same encounter (transient:
    -- it only needs to hold for this client's session, which is all that can
    -- re-enter ProceedEndCombat before the live encounter is torn down).
    if live:try_get("_tmp_dsRolesRecorded", false) then
        return
    end
    live._tmp_dsRolesRecorded = true

    local roles = DSVictoryScreen.ComputeHeroRoles(live)
    for _, token in ipairs(live:GetBattleHeroTokens()) do
        local info = token ~= nil and roles[token.charid] or nil
        if info ~= nil and token.properties ~= nil then
            token:ModifyProperties{
                description = "Record victory role",
                undoable = false,
                execute = function()
                    -- Assign a fresh table so the field-level change is observed
                    -- and uploaded (in-place nested mutation may not diff).
                    local history = {}
                    local old = token.properties:try_get("dsVictoryRoleHistory")
                    if type(old) == "table" then
                        for k, v in pairs(old) do
                            history[k] = v
                        end
                    end
                    history[info.role] = (history[info.role] or 0) + 1
                    token.properties.dsVictoryRoleHistory = history
                end,
            }
        end
    end
end

-- End combat and clear the victory state, mirroring the initiative bar's "End Combat"
-- menu item. Setting the queue hidden + clearing victoryAwarded and uploading is what
-- closes this screen (and re-hides the bar) on every client.
local function ProceedEndCombat()
    local q = dmhub.initiativeQueue
    if q == nil then
        return
    end

    local live = q:try_get("liveEncounter")
    if type(live) == "table" then
        -- Record awarded roles while the queue is still live (GetBattleHeroTokens
        -- reads it) and before victoryAwarded is cleared.
        RecordHeroRoles(live)
        live.victoryAwarded = false
    end

    q.hidden = true
    q.gameMode = "exploration"
    dmhub:UploadInitiativeQueue()

    CharacterResource.SetMalice(0, "End of Combat")

    local hud = GameHud.instance
    if hud ~= nil then
        for initiativeid, _ in pairs(q.entries) do
            local tokens = hud:GetTokensForInitiativeId(hud.initiativeInterface, initiativeid)
            for _, tok in ipairs(tokens) do
                if tok.properties ~= nil then
                    tok.properties:EndCombat()
                    tok.properties:DispatchEvent("endcombat", {})
                end
            end
        end
    end
end

-- Build a single hero's card: portrait, name, Stamina bar, Recoveries change, the fun
-- role they earned (if any -- see ComputeHeroRoles; roleInfo may be nil and the role
-- lines render blank), and a DEAD marker for fallen heroes. Every visible element
-- carries the "victoryFade" class so the card-level "shown" class can fade the whole
-- card in via the descendant style rules on the card (opacity does not cascade in this
-- engine, so each leaf is faded individually).
local function BuildHeroCard(live, token, roleInfo)
    local props = token and token.properties
    local name = (token and token.name) or "Hero"

    local dead = props ~= nil and props:IsDead()
    local curHp = (props ~= nil and props:CurrentHitpoints()) or 0
    local maxHp = (props ~= nil and props:MaxHitpoints()) or 0
    local fillPct = 0
    if maxHp > 0 and curHp > 0 then
        fillPct = math.min(1, curHp / maxHp) * 100
    end

    -- For fallen heroes the portrait itself carries the death treatment: a 50%
    -- red wash covering the whole portrait with the DEAD marker centered on it.
    -- The wash's 50% comes from the bgcolor alpha (not opacity) so the
    -- victoryFade opacity animation can still fade it in without overriding it.
    local deadChildren = nil
    if dead then
        deadChildren = {
            gui.Panel{
                classes = {"victoryFade"},
                interactable = false,
                bgimage = "panels/square.png",
                bgcolor = "#ff000080",
                width = "100%",
                height = "100%",
                halign = "center",
                valign = "center",
            },
            gui.Label{
                classes = {"victoryFade", "victoryDead"},
                interactable = false,
                text = "DEAD",
                width = "100%",
                height = "auto",
                halign = "center",
                valign = "center",
                textAlignment = "center",
                color = "white",
                fontFace = "Book",
                fontSize = 18,
                fontWeight = "black",
                uppercase = true,
            },
        }
    end

    -- Portrait. Fills the full width of the card and grows tall to match the
    -- 3:4 portrait aspect (height = width * 100/portraitWidthPercentOfHeight).
    -- A negative top margin pulls it flush to the card's top inner edge, past
    -- the card's vpad, so it reads as a header image rather than an inset.
    local portraitPanel = gui.Panel{
        -- borderInfo paints the gold accent frame from the active scheme;
        -- bgcolor "white" stays inline (image-tint-neutral for the portrait).
        classes = {"victoryFade", "victoryPortrait", "borderInfo"},
        interactable = false,
        flow = "none",
        width = "100%",
        height = string.format("%f%% width", 10000 / Styles.portraitWidthPercentOfHeight),
        halign = "center",
        valign = "top",
        tmargin = -12,
        bgcolor = "white",
        borderWidth = 2,
        cornerRadius = 4,
        children = deadChildren,
    }
    if token ~= nil then
        local portrait = token.inspectPortrait
        portraitPanel.bgimage = portrait
        if token.hasSpineAnimation then
            portraitPanel.selfStyle.imageRect = nil
        else
            portraitPanel.selfStyle.imageRect = token:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight * 0.01, portrait)
        end
    end

    local nameLabel = gui.Label{
        classes = {"victoryFade", "victoryHeroName"},
        interactable = false,
        text = name,
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 8,
        textAlignment = "center",
        textWrap = true,
        fontFace = "Book",
        fontSize = 20,
        fontWeight = "bold",
    }

    -- Stamina bar: a dark track with a coloured fill and "current/max" overlaid.
    -- The fill takes the scheme's danger (dead) or success (alive) token.
    local staminaFill = gui.Panel{
        classes = {"victoryFade", cond(dead, "bgDanger", "bgSuccess")},
        interactable = false,
        halign = "left",
        valign = "center",
        height = "100%",
        width = string.format("%f%%", fillPct),
    }

    local staminaText = gui.Label{
        classes = {"victoryFade"},
        interactable = false,
        text = string.format("%d/%d", curHp, maxHp),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontFace = "Book",
        fontSize = 13,
    }

    local staminaBar = gui.Panel{
        -- bg = dark track surface, border = themed frame.
        classes = {"victoryFade", "bg", "border"},
        interactable = false,
        flow = "none",
        width = 150,
        height = 18,
        halign = "center",
        tmargin = 6,
        borderWidth = 1,
        cornerRadius = 3,
        children = { staminaFill, staminaText },
    }

    -- Recoveries: "Recoveries: onset -> current/max" (or just "current/max" if unchanged).
    local onset, curRec, maxRec = live:GetHeroRecoveries(token)
    local recText
    if onset ~= nil and onset ~= curRec then
        recText = string.format("Recoveries: %d -> %d/%d", onset, curRec, maxRec)
    else
        recText = string.format("Recoveries: %d/%d", curRec, maxRec)
    end

    local recoveriesLabel = gui.Label{
        classes = {"victoryFade", "fg"},
        interactable = false,
        text = recText,
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 6,
        textAlignment = "center",
        textWrap = false,
        fontFace = "Book",
        fontSize = 14,
    }

    -- The fun role the hero earned this encounter: the role name as a small
    -- accent header with the detail line under it, and the role's fun-fact on
    -- a hover tooltip. When the hero earned no role both labels render blank
    -- (auto height collapses them to nothing). The title label is the one
    -- interactable element on an otherwise click-through card, so the tooltip
    -- can receive hover.
    local roleTitleLabel = gui.Label{
        classes = {"victoryFade", "info"},
        interactable = roleInfo ~= nil,
        text = (roleInfo ~= nil and roleInfo.role) or "",
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 8,
        textAlignment = "center",
        textWrap = false,
        fontFace = "Book",
        fontSize = 16,
        fontWeight = "bold",
        uppercase = true,
        hover = (roleInfo ~= nil and roleInfo.tooltip ~= nil) and gui.Tooltip(roleInfo.tooltip) or nil,
    }

    local roleTextLabel = gui.Label{
        classes = {"victoryFade", "fg"},
        interactable = false,
        text = (roleInfo ~= nil and roleInfo.text) or "",
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 2,
        textAlignment = "center",
        textWrap = true,
        fontFace = "Book",
        fontSize = 13,
    }

    -- "Victories: old -> new" line, hidden until the Award animation finishes.
    local victoriesLabel = gui.Label{
        classes = {"victoryFade", "scalein", "info"},
        interactable = false,
        text = "",
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 8,
        textAlignment = "center",
        textWrap = false,
        fontFace = "Book",
        fontSize = 16,
        fontWeight = "bold",
    }
    victoriesLabel:SetClass("collapsed", true)

    -- Floating overlay that holds the victory icons as they drop into the card.
    local dropLayer = gui.Panel{
        interactable = false,
        floating = true,
        flow = "none",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        children = {},
    }

    local victoriesOld = (props ~= nil and props:GetVictories()) or 0

    return gui.Panel{
        --"victoryFade" so the card's own gradient background fades in along with its
        --contents (opacity does not cascade, so the card needs the class too).
        -- panel + surfaceRadial paints the scheme's vignette "hero" surface so
        -- transparent character art reads against a solid backdrop; border adds
        -- the themed frame. All track the active color scheme.
        classes = {"panel", "surfaceRadial", "border", "victoryHeroCard", "scalein", "victoryFade"},
        interactable = false,
        flow = "vertical",
        width = 200,
        -- minHeight + auto height + valign top: all cards align at the same top and
        -- normally match at the min height, but a card can grow if its content (e.g.
        -- a long wrapped hero name) needs more room rather than overflowing.
        height = "auto",
        minHeight = 380,
        halign = "center",
        valign = "top",
        hmargin = 12,

        cornerRadius = 8,
        borderWidth = 1,
        vpad = 12,
        borderBox = true,

        data = { token = token, victoriesOld = victoriesOld },

        styles = {
            -- Every leaf starts transparent and fades to full once the card gains the
            -- "shown" class (descendant rule -- ancestor "shown" + element "victoryFade").
            { selectors = {"victoryFade"}, opacity = 0, transitionTime = 0.6 },
            { selectors = {"shown", "victoryFade"}, opacity = 1, transitionTime = 0.6 },
            --scale up from 2x only on the way IN (before "shown"). On exit we strip the
            --"scalein" class entirely (see fadeOut) so this rule can't match and the card
            --fades at scale 1 instead of ballooning.
            { selectors = {"scalein", "~shown"}, transitionTime = 0.6, scale = 1.3,},
        },

        -- dropLayer is LAST so it draws on top of the card content (in DMHub later
        -- siblings render above earlier ones), letting the icons land over the card.
        children = { portraitPanel, nameLabel, staminaBar, recoveriesLabel, roleTitleLabel, roleTextLabel, victoriesLabel, dropLayer },

        -- Drop `amount` victory icons into this card one at a time, then reveal the
        -- "Victories: old -> new" line. Orchestrated per-card by the screen's playAward.
        awardVictories = function(card, amount)
            if amount == nil or amount <= 0 then
                card:FireEvent("finishAward", 0)
                return
            end
            local icons = {}
            for i = 1, amount do
                icons[i] = gui.Panel{
                    classes = {"victoryDropIcon", "dropStart"},
                    interactable = false,
                    bgimage = VICTORY_ICON,
                    bgcolor = "white",
                    width = 96,
                    height = 96,
                    halign = "center",
                    valign = "center",
                    styles = {
                        --non-floating children animate y via class toggles (the swords
                        --in DSInitiativeRoll use the same pattern).
                        { classes = {"dropStart"}, y = -600, opacity = 0, transitionTime = 0.45, easing = "EaseInCubic" },
                        { classes = {"dropLand"}, opacity = 1, transitionTime = 0.45, easing = "EaseOutCubic" },
                        --fade out where it landed (keep y) over a slower, graceful fade
                        --rather than snapping away.
                        { classes = {"dropGone"}, opacity = 0, transitionTime = 0.7 },
                        { y = -140 },
                    },
                }
            end
            dropLayer.children = icons

            local stagger = 0.35
            for i, icon in ipairs(icons) do
                card:ScheduleEvent("dropIcon", (i - 1) * stagger, icon)
                card:ScheduleEvent("fadeIcon", (i - 1) * stagger + 0.5, icon)
            end
            card:ScheduleEvent("finishAward", amount * stagger + 0.3, amount)
        end,

        dropIcon = function(card, icon)
            if icon ~= nil and icon.valid then
                icon:SetClass("dropStart", false)
                icon:SetClass("dropLand", true)
            end
        end,

        fadeIcon = function(card, icon)
            if icon ~= nil and icon.valid then
                icon:SetClass("dropLand", false)
                icon:SetClass("dropGone", true)
            end
        end,

        finishAward = function(card, amount)
            local newV = card.data.victoriesOld + amount
            victoriesLabel.text = string.format("Victories: %d -> %d", card.data.victoriesOld, newV)
            victoriesLabel:SetClass("collapsed", false)
            victoriesLabel:SetClass("shown", false)
            victoriesLabel:SetClass("shown", true)
        end,

        -- Fade the whole card out (its gradient background fades via "victoryFade" on the
        -- card itself, its leaves via the same class) plus any icons still in flight, so
        -- nothing snaps away when the screen dismisses.
        fadeOut = function(card)
            --strip "scalein" across the tree first so the {scalein, ~shown} scale-up rule
            --can no longer match; the card then fades at scale 1 rather than growing to 2x.
            --card:SetClassTree("scalein", false)
            card:SetClassTree("shown", false)
            for _, icon in ipairs(dropLayer.children) do
                if icon ~= nil and icon.valid then
                    icon:SetClass("dropStart", false)
                    icon:SetClass("dropLand", false)
                    icon:SetClass("dropGone", true)
                end
            end
        end,
    }
end

-- Create the victory screen overlay. Mounted once by the game HUD.
function DSVictoryScreen.Create()
    local heroRow
    local titleLabel
    local titleGroup
    local proceedButton
    local rootPanel
    local victoriesSection
    local victoryAmountInput

    ------------------------------------------------------------------
    -- Full-screen dim. Interactable so it swallows clicks to the map
    -- underneath while the celebration is up. blurBackground (toggled on
    -- in showVictory / off in finishHide, since this panel persists hidden
    -- between victories) makes MainCamera render a blurred copy of the map
    -- that this full-screen panel composites behind its tint, so the whole
    -- map blurs. The dim is kept light enough that the blur reads through.
    ------------------------------------------------------------------
    local dimPanel = gui.Panel{
        classes = {"dim-out"},
        interactable = true,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "black",
        styles = {
            { classes = {"dim-out"}, opacity = 0, transitionTime = 0.4 },
            { classes = {"dim-in"}, opacity = 0.55, transitionTime = 0.5 },
        },
    }

    ------------------------------------------------------------------
    -- VICTORY title, flanked by two swords that sweep apart to reveal
    -- it -- the same reveal used by the Draw Steel initiative banner
    -- (Draw Steel UI/DSInitiativeRoll.lua) and the DramaticBanner
    -- (DMHub Game Hud/FullscreenDisplay.lua). The title itself is drawn
    -- twice: a black copy offset down-right behind the white face gives
    -- it a hard drop-shadow.
    ------------------------------------------------------------------
    local titleFontSize = 80

    -- Build a title label. The shadow copy is the same glyphs in black,
    -- nudged a few px down-right and rendered behind the white face.
    local function MakeTitleLabel(isShadow)
        return gui.Label{
            classes = {"victoryTitle"},
            interactable = false,
            text = "Victory",
            halign = "center",
            valign = "center",
            x = cond(isShadow, 6, 0),
            y = cond(isShadow, 6, 0),
            width = "auto",
            height = "auto",
            textAlignment = "center",
            -- Never wrap: the clip window can be narrower than the text mid-
            -- reveal, and a wrapping label would reflow instead of clipping.
            textWrap = false,
            fontFace = "Book",
            fontSize = titleFontSize,
            fontWeight = "black",
            uppercase = true,
            -- Face uses the themed @fgStrong (label default); the shadow copy
            -- stays black -- a drop shadow is intentionally scheme-independent.
            color = cond(isShadow, "black", nil),
            styles = {
                { selectors = {"victoryTitle"}, opacity = 0, transitionTime = 0.7 },
                { selectors = {"victoryTitle", "shown"}, opacity = 1, transitionTime = 0.7 },
            },
        }
    end

    local titleShadow = MakeTitleLabel(true)
    titleLabel = MakeTitleLabel(false)

    -- Two swords that rest crossed at the title's centre and sweep apart
    -- to either side, wiping the (clipped) title into view between them.
    -- The right sword mirrors the left (negative x scale).
    local swordOpenOffset = 380

    local function MakeVictorySword(isLeft)
        local closedClass = cond(isLeft, "lsw-closed", "rsw-closed")
        local openClass = cond(isLeft, "lsw-open", "rsw-open")
        local openX = cond(isLeft, -swordOpenOffset, swordOpenOffset)
        return gui.Panel{
            classes = {closedClass},
            interactable = false,
            width = 240,
            height = "50% width",
            halign = "center",
            valign = "center",
            y = -10,
            bgimage = "panels/initiative/drawsteel-sword.png",
            bgcolor = "white",
            scale = cond(isLeft, nil, {x = -1, y = 1}),
            styles = {
                -- Visible while crossed so they read as crossed swords that
                -- wipe the title open. easeInBack winds them back in slightly
                -- before they settle; easeOutCubic gives the sweep a smooth tail.
                { selectors = {closedClass}, x = 0, opacity = 1, transitionTime = 0.45, easing = "EaseInBack" },
                { selectors = {openClass}, x = openX, opacity = 1, transitionTime = 0.6, easing = "EaseOutCubic" },
            },
        }
    end

    local leftSword = MakeVictorySword(true)
    local rightSword = MakeVictorySword(false)

    -- The title is revealed by a horizontally-growing clip window rather
    -- than just sitting under the swords: like the DramaticBanner, the text
    -- stays hidden behind the crossed swords and is wiped into view from the
    -- centre out as they part, so the swords never appear over it. clip=true
    -- makes this panel's bgimage a mask for its children (clipHidden hides
    -- the mask itself); the window grows symmetrically about the centre.
    -- EaseInCubic makes the reveal trail the (EaseOutCubic) swords, so the
    -- text only emerges in space the swords have already cleared.
    local titleClip = gui.Panel{
        classes = {"titleClip-closed"},
        interactable = false,
        flow = "none",
        halign = "center",
        valign = "center",
        height = 150,
        bgimage = "panels/square.png",
        clip = true,
        clipHidden = true,
        children = { titleShadow, titleLabel },
        styles = {
            { selectors = {"titleClip-closed"}, width = 0,   transitionTime = 0.6, easing = "EaseInCubic" },
            { selectors = {"titleClip-open"},   width = 760, transitionTime = 0.6, easing = "EaseInCubic" },
        },
    }

    -- Flow "none" overlay so the swords animate in x relative to the shared
    -- centre. Child order is draw order: the clipped title behind, swords on
    -- top, so the swords visibly part to wipe the title open.
    titleGroup = gui.Panel{
        interactable = false,
        flow = "none",
        width = "100%",
        height = 160,
        halign = "center",
        valign = "top",
        y = 40,
        children = { titleClip, leftSword, rightSword },
    }

    -- The cards rest at a stable top within this row (fixed height + valign top), so a
    -- card growing -- e.g. when its "Victories" line appears -- never shifts the others.
    heroRow = gui.Panel{
        interactable = false,
        flow = "horizontal",
        width = "auto",
        height = 400,
        maxWidth = 1760,
        halign = "center",
        valign = "top",
        y = 210,
        wrap = true,
        children = {},
    }

    -- Director-only "Proceed" button: ends combat and clears the victory state.
    -- Themed text button; the local styles only drive the fade-in (the themed
    -- button rules supply rest/hover/press chrome from the active scheme).
    proceedButton = gui.Button{
        classes = {"sizeL", "victoryProceed"},
        text = "Proceed",
        interactable = true,
        width = 220,
        height = 56,
        halign = "center",
        valign = "bottom",
        y = -70,

        styles = {
            { selectors = {"victoryProceed"}, opacity = 0, transitionTime = 0.5 },
            { selectors = {"victoryProceed", "shown"}, opacity = 1, transitionTime = 0.5 },
        },

        hover = function(element)
            gui.Tooltip{ text = "End combat and dismiss the victory screen for everyone." }(element)
        end,

        click = function(element)
            ProceedEndCombat()
        end,
    }

    ------------------------------------------------------------------
    -- Director-only "Victories" controls, sitting just above Proceed.
    -- An editable count of how many Victories to grant each hero, plus
    -- an Award button that grants them and triggers the icon-drop
    -- animation on every client.
    ------------------------------------------------------------------
    local victoriesTitleLabel = gui.Label{
        interactable = false,
        text = "Victories:",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textAlignment = "center",
        fontFace = "Book",
        fontSize = 18,
    }

    victoryAmountInput = gui.Input{
        classes = {"form"},
        interactable = true,
        width = 60,
        height = 32,
        halign = "center",
        valign = "center",
        hmargin = 8,
        fontSize = 16,
        numeric = true,
        characterLimit = 3,
        text = "1",
        change = function(element)
            local n = tonumber(element.text)
            if n == nil then
                element.text = "1"
                return
            end
            n = math.floor(n)
            if n < 0 then n = 0 end
            element.text = tostring(n)
        end,
    }

    -- Themed text button; rest/hover/press chrome comes from the active scheme.
    local awardVictoriesButton = gui.Button{
        classes = {"sizeM"},
        text = "Award",
        interactable = true,
        width = 120,
        height = 40,
        halign = "center",
        valign = "center",
        hmargin = 10,

        hover = function(element)
            gui.Tooltip{ text = "Grant this many Victories to each hero." }(element)
        end,

        click = function(element)
            if not dmhub.isDM then return end
            local live = GetActiveVictory()
            if live == nil then return end
            local n = tonumber(victoryAmountInput.text) or 1
            n = math.floor(n)
            if n < 0 then n = 0 end

            for _, token in ipairs(live:GetBattleHeroTokens()) do
                token:ModifyProperties{
                    description = "Award Victories",
                    combine = true,
                    execute = function()
                        token.properties:SetVictories(token.properties:GetVictories() + n)
                    end,
                }
            end

            --record the awarded amount + flag on the live encounter and network it so
            --every client plays the drop animation and shows the change.
            live.victories = n
            live.victoriesAwarded = true
            dmhub:UploadInitiativeQueue()
            if rootPanel ~= nil then
                rootPanel:FireEvent("checkVictory")
            end
        end,
    }

    victoriesSection = gui.Panel{
        classes = {"victoryAwardSection", "collapsed"},
        interactable = true,
        flow = "horizontal",
        width = "auto",
        height = 44,
        halign = "center",
        valign = "bottom",
        y = -150,
        children = { victoriesTitleLabel, victoryAmountInput, awardVictoriesButton },
    }

    rootPanel = gui.Panel{
        -- This overlay owns its cascade root, so the theme classes applied to
        -- the dim, cards, buttons, and labels below resolve against the active
        -- scheme. Re-resolved on theme change via OnThemeChanged below.
        styles = ThemeEngine.GetStyles(),
        classes = {"hidden"},
        floating = true,
        flow = "none",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        -- interactable so the dim child and the Proceed button receive clicks (a parent
        -- with interactable=false would block its whole subtree from raycasts).
        interactable = true,

        children = { dimPanel, titleGroup, heroRow, victoriesSection, proceedButton },

        data = {
            -- Bumped on every show/hide so a stale scheduled callback can tell that a
            -- newer state change has superseded it.
            generation = 0,
            shown = false,
            awardPlayed = false,
        },

        -- Build + stagger the hero cards, then fade everything in.
        showVictory = function(element, live)
            element.data.generation = element.data.generation + 1
            local g = element.data.generation

            element:SetClass("hidden", false)
            dimPanel.blurBackground = true
            dimPanel:SetClass("dim-out", false)
            dimPanel:SetClass("dim-in", true)

            titleLabel:SetClass("shown", false)
            titleShadow:SetClass("shown", false)
            titleClip:SetClass("titleClip-open", false)
            titleClip:SetClass("titleClip-closed", true)
            leftSword:SetClass("lsw-open", false)
            leftSword:SetClass("lsw-closed", true)
            rightSword:SetClass("rsw-open", false)
            rightSword:SetClass("rsw-closed", true)
            proceedButton:SetClass("shown", false)
            proceedButton:SetClass("collapsed", not dmhub.isDM)

            --reset the Director victories controls for this showing.
            element.data.awardPlayed = false
            victoryAmountInput.text = tostring(live:try_get("victories", 1))
            victoriesSection:SetClass("collapsed", true)

            --build a card per hero in the battle (enumerated live from the initiative
            --queue, so heroes always appear; the onset snapshot is only used to show how
            --their Recoveries changed).
            local heroTokens = live:GetBattleHeroTokens()
            print("VICTORY:: building cards for", #heroTokens, "heroes")

            --compute every hero's fun role once for the whole party; heroes
            --with no role get nil and their card renders the role lines blank.
            local heroRoles = DSVictoryScreen.ComputeHeroRoles(live)

            local cards = {}
            for _, token in ipairs(heroTokens) do
                cards[#cards + 1] = BuildHeroCard(live, token, heroRoles[token.charid])
            end
            heroRow.children = cards

            --title sweeps in first.
            element:ScheduleEvent("showTitle", 0.15, g)

            --then the heroes, one by one.
            for i, card in ipairs(cards) do
                element:ScheduleEvent("showHero", 0.4 + (i - 1) * g_heroStagger, g, card)
            end

            --finally the proceed button, after the last hero.
            local proceedDelay = 0.4 + (#cards) * g_heroStagger + 0.2
            element:ScheduleEvent("showProceed", proceedDelay, g)
        end,

        showTitle = function(element, g)
            if g ~= element.data.generation then return end
            --play the same dramatic-banner sword sound as the swords sweep apart.
            audio.FireSoundEvent(DramaticBanner.defaultSound)
            titleLabel:SetClass("shown", true)
            titleShadow:SetClass("shown", true)
            titleClip:SetClass("titleClip-closed", false)
            titleClip:SetClass("titleClip-open", true)
            leftSword:SetClass("lsw-closed", false)
            leftSword:SetClass("lsw-open", true)
            rightSword:SetClass("rsw-closed", false)
            rightSword:SetClass("rsw-open", true)
        end,

        showHero = function(element, g, card)
            if g ~= element.data.generation then return end
            if card ~= nil and card.valid then
                --SetClassTree so every leaf (which carries "victoryFade") gets "shown" on
                --ITSELF -- the fade rule {"victoryFade","shown"} matches same-element, like
                --the title. A plain SetClass would only mark the card, leaving leaves hidden.
                card:SetClassTree("shown", true)
            end
        end,

        showProceed = function(element, g)
            if g ~= element.data.generation then return end
            proceedButton:SetClass("shown", true)
            --reveal the Director victories controls alongside Proceed (unless already
            --awarded, or this is a player).
            local live = GetActiveVictory()
            local awarded = live ~= nil and live:try_get("victoriesAwarded", false)
            victoriesSection:SetClass("collapsed", (not dmhub.isDM) or awarded)
        end,

        hideVictory = function(element)
            element.data.generation = element.data.generation + 1
            titleLabel:SetClass("shown", false)
            titleShadow:SetClass("shown", false)
            titleClip:SetClass("titleClip-open", false)
            titleClip:SetClass("titleClip-closed", true)
            leftSword:SetClass("lsw-open", false)
            leftSword:SetClass("lsw-closed", true)
            rightSword:SetClass("rsw-open", false)
            rightSword:SetClass("rsw-closed", true)
            proceedButton:SetClass("shown", false)
            victoriesSection:SetClass("collapsed", true)
            --fade each card (gradient background + contents + any icons) out alongside
            --the dim, rather than letting them snap away at finishHide.
            for _, card in ipairs(heroRow.children) do
                if card ~= nil and card.valid then
                    card:FireEvent("fadeOut")
                end
            end
            dimPanel:SetClass("dim-in", false)
            dimPanel:SetClass("dim-out", true)
            --hide the whole tree after the cards + dim have faded.
            element:ScheduleEvent("finishHide", 0.7, element.data.generation)
        end,

        finishHide = function(element, g)
            if g ~= element.data.generation then return end
            element:SetClass("hidden", true)
            --stop generating the full-screen blur texture now that the dim has
            --fully faded out; otherwise MainCamera keeps blurring every frame.
            dimPanel.blurBackground = false
            heroRow.children = {}
        end,

        -- Compare the current victory state to what we are showing and flip if needed.
        -- Driven by monitorGame (fires on every initiative-queue change, even while this
        -- panel is hidden -- a plain think would not fire while hidden) and once on create
        -- so a client that loads mid-victory shows the screen immediately.
        checkVictory = function(element)
            local live = GetActiveVictory()
            local active = live ~= nil
            if active and not element.data.shown then
                element.data.shown = true
                element:FireEvent("showVictory", live)
            elseif not active and element.data.shown then
                element.data.shown = false
                element:FireEvent("hideVictory")
            end

            --once the Director awards Victories, play the icon-drop animation (once).
            if active and element.data.shown and not element.data.awardPlayed
                and live:try_get("victoriesAwarded", false) then
                element.data.awardPlayed = true
                element:FireEvent("playAward", live)
            end
        end,

        -- Drop victory icons into each hero card in turn, one card after another.
        playAward = function(element, live)
            local g = element.data.generation
            local n = live:try_get("victories", 1)
            --the controls have done their job; hide them.
            victoriesSection:SetClass("collapsed", true)
            local cards = heroRow.children
            local perCard = 0.7
            for i, card in ipairs(cards) do
                element:ScheduleEvent("awardCard", (i - 1) * perCard, g, card, n)
            end
        end,

        awardCard = function(element, g, card, n)
            if g ~= element.data.generation then return end
            if card ~= nil and card.valid then
                --pickup sound as each player is awarded their victory.
                audio.FireSoundEvent("UI.Inv_Item_Pickup_Special")
                card:FireEvent("awardVictories", n)
            end
        end,

        --Re-check whenever the initiative queue changes (victory awarded / combat ended).
        monitorGame = "/initiativeQueue",
        refreshGame = function(element)
            element:FireEvent("checkVictory")
        end,

        create = function(element)
            element:FireEvent("checkVictory")
        end,
    }

    -- Re-resolve the cascade when the user switches theme / color scheme so the
    -- whole victory screen recolors live.
    ThemeEngine.OnThemeChanged(mod, function()
        if rootPanel ~= nil and rootPanel.valid then
            rootPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return rootPanel
end
