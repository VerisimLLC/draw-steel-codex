local mod = dmhub.GetModLoading()

local g_rampageResourceId = "9f418676-96be-402b-92da-0f50294146b3"

RegisterGameType("AnimalCompanion", "monster")

creature.companionid = false

function creature:IsCompanion()
    return false
end

--- Return the beastheart's sticky name override for a given companion type,
--- or nil if none is set. Names are stored keyed by bestiary GUID so that
--- switching companion species swaps the active name without losing the
--- name set for the other species.
--- @param companionType string bestiary id of an AnimalCompanion
--- @return string|nil
function creature:GetCompanionName(companionType)
    if companionType == nil or companionType == "" then
        return nil
    end
    local stored = self:try_get("companionNames", {})[companionType]
    if stored == nil or stored == "" then
        return nil
    end
    return stored
end

--- Write the beastheart's sticky name override for a given companion type.
--- Empty/nil name clears the override (next spawn falls back to the bestiary
--- stat block's default name). Caller is responsible for wrapping this in
--- ModifyProperties when invoked on a live token.
--- @param companionType string bestiary id of an AnimalCompanion
--- @param name string|nil
function creature:SetCompanionName(companionType, name)
    if companionType == nil or companionType == "" then
        return
    end
    self:get_or_add("companionNames", {})[companionType] = name
end

function creature:GetCompanionToken()
    local companionid = self.companionid
    if not companionid then
        return nil
    end

    local token = dmhub.GetTokenById(companionid)
    if token and token.valid then
        return token
    end

    return nil
end

--GoblinScript symbol so formulas can write `Caster.Companion.X` (or
--`Self.Companion.X`) to reach the companion's stats / position. Mirrors
--the existing `Summoner` symbol but in the opposite direction. Returns
--nil for any creature without a summoned companion.
creature.RegisterSymbol {
    symbol = "companion",
    lookup = function(c)
        local companionToken = c:GetCompanionToken()
        if companionToken ~= nil and companionToken.valid then
            return companionToken.properties
        end
        return nil
    end,
    help = {
        name = "Companion",
        type = "creature",
        desc = "The animal companion summoned by this creature (Beastheart class), if any. Use Caster.Companion.X / Self.Companion.X to read companion stats.",
        seealso = {"Summoner"},
    },
}

--GoblinScript symbol used by Beastheart-companion features to gate effects
--on the companion being in its rampaging state. Per the Beastheart rules
--("Rampage"), a companion is rampaging when its Rampage stat is 8 or more.
--Returns false for any non-AnimalCompanion creature (and false when the
--companion has no Rampage resource yet, so it never errors mid-summon /
--for fresh tokens).
creature.RegisterSymbol {
    symbol = "rampaging",
    lookup = function(c)
        if not c:IsCompanion() then
            return false
        end
        local quantity = c:GetUnboundedResourceQuantity(g_rampageResourceId) or 0
        return quantity >= 8
    end,
    help = {
        name = "Rampaging",
        type = "boolean",
        desc = "True when this creature is an animal companion whose Rampage stat is 8 or more (per the Beastheart Rampage rule). False for any other creature.",
        examples = {"Self.Rampaging", "Caster.Companion.Rampaging"},
        seealso = {"Companion"},
    },
}

--GoblinScript symbol: is THIS creature's summoned companion currently
--rampaging? Caster/summoner-side and nil-safe -- returns false when there is
--no summoned companion (GetCompanionToken() == nil), so a summoner-hosted
--filterCondition/activationCondition can gate on "my companion is rampaging"
--without the two-hop `Companion.Rampaging` chain ERRORING on an unsummoned
--companion (which, in a filterCondition, would otherwise fail OPEN to the
--default-pass). Mirrors the `rampaging` symbol's Rampage>=8 check, applied to
--the companion token. Usage: `Self.CompanionRampaging`.
creature.RegisterSymbol {
    symbol = "companionrampaging",
    lookup = function(c)
        local companionToken = c:GetCompanionToken()
        if companionToken == nil or (not companionToken.valid) then
            return false
        end

        local p = companionToken.properties
        if p == nil or (not p:IsCompanion()) then
            return false
        end

        local quantity = p:GetUnboundedResourceQuantity(g_rampageResourceId) or 0
        return quantity >= 8
    end,
    help = {
        name = "Companion Rampaging",
        type = "boolean",
        desc = "True when this creature's summoned companion is currently rampaging (Rampage 8 or more). False when there is no summoned companion. Nil-safe for gating summoner-side effects.",
        examples = {"Self.CompanionRampaging", "Caster.CompanionRampaging"},
        seealso = {"Companion", "Rampaging"},
    },
}

--GoblinScript symbol: is this creature's light source currently switched on?
--The engine treats the light loadout (selectedLoadout == 1) as "light on" (see
--the /light macro in Creature.lua and the light readouts in GameHud /
--MCDMCharacterPanel). Used by the Lightbender "Lightbearer" feature to impose a
--bane on strikes against it while it is glowing (light on) and rampaging.
creature.RegisterSymbol {
    symbol = "sheddinglight",
    lookup = function(c)
        return c:try_get("selectedLoadout", 0) == 1
    end,
    help = {
        name = "Shedding Light",
        type = "boolean",
        desc = "True when this creature's light source is switched on (the light loadout is active). False otherwise.",
        examples = {"Self.SheddingLight", "Target.SheddingLight"},
    },
}

--GoblinScript function symbol: "is the creature I am shown grabbed by MY
--animal companion?". Caster-side and fully nil-safe -- returns false when the
--beastheart has no companion, so callers avoid `Caster.Companion and ...`,
--which the engine evaluates to nil for a bare object operand. Registered as a
--function symbol (the lookup returns a closure) mirroring the built-in
--`Distance` and `Cast.AnyTargetHas` patterns. Usage in a GoblinScript field
--where Target is bound (e.g. a behavior filterTarget):
--`Caster.CompanionIsGrabbing(Target)`.
creature.RegisterSymbol {
    symbol = "companionisgrabbing",
    lookup = function(c)
        return function(other)
            local companionToken = c:GetCompanionToken()
            if companionToken == nil or (not companionToken.valid) then
                return false
            end

            --The argument may arrive as a creature-properties table or as a
            --symbol-resolver function; coerce to properties the same way
            --Cast.AnyTargetHas / Cast.HasTarget do in ActivatedAbilityCast.lua.
            if type(other) == "function" then
                other = other("self")
            end

            local targetToken = dmhub.LookupToken(other)
            if targetToken == nil then
                return false
            end

            local grabbedCond = CharacterCondition.conditionsByName["grabbed"]
            if grabbedCond == nil then
                return false
            end

            --creature:HasCondition returns the grabber's tokenid (== charid)
            --when the caster is known, true when the grabber is unknown, or
            --false when not grabbed. Only an exact companion match counts.
            local grabber = targetToken.properties:HasCondition(grabbedCond.id)
            return grabber == companionToken.charid
        end
    end,
    help = {
        name = "Companion Is Grabbing",
        type = "function",
        desc = "A function shown a creature; returns true if that creature is grabbed by this creature's animal companion (Beastheart partner). False when there is no companion or the grab was applied by anyone else.",
        examples = {"Caster.CompanionIsGrabbing(Target)"},
        seealso = {"Companion"},
    },
}

--GoblinScript symbol: the human-readable name of the companion type this
--creature has chosen, or "" if it has none. GetCompanionType() returns the
--chosen bestiary id from any behavior=="companion" feature (class-agnostic,
--not beastheart-specific); we resolve it to the stat-block name the same way
--the companion picker builds its option text (see DSModifierCompanion.lua).
creature.RegisterSymbol {
    symbol = "companiontype",
    lookup = function(c)
        local companionType = c:GetCompanionType()
        if companionType == nil or companionType == "" then
            return ""
        end

        local monster = assets.monsters[companionType]
        if monster == nil then
            return ""
        end

        return monster.name or monster.properties.monster_type or "Companion"
    end,
    help = {
        name = "Companion Type",
        type = "text",
        desc = "The readable name of the companion this creature has chosen (from any companion feature), or empty if it has none. Use Companion to reach a currently-summoned companion's stats.",
        examples = {"Self.CompanionType is not \"\"", "Caster.CompanionType is \"Wolf\""},
        seealso = {"Companion", "Has Companion"},
    },
}

--GoblinScript symbol: does this creature have a companion type chosen? True
--for any creature with a behavior=="companion" feature that has picked a
--companion; distinct from the Companion symbol, which resolves a currently-
--summoned companion token.
creature.RegisterSymbol {
    symbol = "hascompanion",
    lookup = function(c)
        return c:GetCompanionType() ~= nil
    end,
    help = {
        name = "Has Companion",
        type = "boolean",
        desc = "True when this creature has a companion type chosen (from any companion feature). Use Companion to reach a currently-summoned companion's stats.",
        examples = {"Self.HasCompanion", "Caster.HasCompanion"},
        seealso = {"Companion", "Companion Type"},
    },
}

--- Soft-release the beastheart's currently-summoned companion (if any) and
--- clear the companionid link so the next Call summons a fresh one. The
--- companion token is despawned (token.despawned = true), not destroyed --
--- the underlying bestiary entry and any per-token state survive.
--- @param beastheartToken CharacterToken
function creature:ReleaseCompanion(beastheartToken)
    local companionToken = self:GetCompanionToken()
    if companionToken ~= nil then
        companionToken.despawned = true
    end

    if beastheartToken ~= nil and beastheartToken.valid then
        beastheartToken:ModifyProperties{
            description = "Released companion",
            execute = function()
                beastheartToken.properties.companionid = false
            end,
        }
    end
end

function AnimalCompanion:IsCompanion()
    return true
end

function AnimalCompanion:IsMonster()
    return false
end

-- Animal companions follow the hero death rules rather than the default
-- monster behavior: they enter a dying state at 0 Stamina and only die when
-- pushed past -BloodiedThreshold. Mirrors character:IsDead / character:IsDying
-- (and the retainer branch of monster:IsDead / monster:IsDying).
function AnimalCompanion:IsDead()
    return self:CurrentHitpoints() <= -self:BloodiedThreshold()
end

function AnimalCompanion:IsDying()
    local hp = self:CurrentHitpoints()
    return hp <= 0 and hp > -self:BloodiedThreshold()
end

-- A companion's Stamina (and therefore its bloodied/dying threshold) is
-- derived from its summoner -- see MaxHitpoints above. Delegate the threshold
-- to the summoner too, rather than going through this companion's own
-- CalculateNamedCustomAttribute("dying value"). That cached value is computed
-- from MaxHitpoints(), but the companion is never invalidated when the
-- summoner changes (or when the summoner token finishes loading), so the
-- companion-side cache can latch a stale value. In particular, if it is first
-- computed before the summoner resolves, MaxHitpoints() returns its 1-HP
-- fallback, the threshold caches as floor(1/2) = 0, and IsDead()/IsDying()
-- then treat the companion as dead at 0 Stamina instead of -half. The
-- summoner's own threshold cache is invalidated correctly, so deferring to it
-- always reflects current Stamina.
function AnimalCompanion:BloodiedThreshold()
    local summoner = self:SummonerToken()
    if summoner ~= nil and summoner.properties ~= nil then
        return summoner.properties:BloodiedThreshold()
    end
    return creature.BloodiedThreshold(self)
end

-- Companions level up alongside their summoner (the beastheart). Without this
-- override the monster default returns self.cr, leaving level-gated rampage
-- progression rows (lvl 4 / 7 / 10) permanently locked even for high-level
-- beasthearts.
function AnimalCompanion:CharacterLevel()
    local summoner = self:SummonerToken()
    if summoner ~= nil and summoner.properties ~= nil then
        return summoner.properties:CharacterLevel()
    end
    return monster.CharacterLevel(self)
end

-- The GoblinScript symbol "Level" for monsters is backed by
-- monster.lookupSymbols.level -> c:SpellcastingLevel() (see Monster.lua), which
-- falls through to self.cr (always 1 on a companion stat block). Without this
-- override the GoblinScript "Level" symbol on a companion always reads as 1,
-- breaking any companion ability or modifier formula that scales on level
-- (damage scaling, prereqs, level-gated rampage rows, etc.). Delegate to the
-- summoner's CharacterLevel so the symbol follows the same summoner-aware path
-- used by CharacterLevel(). The Lua-side monster:Level() helper also reads
-- self.cr directly; override it too so any Lua callers stay consistent.
function AnimalCompanion:SpellcastingLevel()
    local summoner = self:SummonerToken()
    if summoner ~= nil and summoner.properties ~= nil then
        return summoner.properties:CharacterLevel()
    end
    return monster.SpellcastingLevel(self)
end

function AnimalCompanion:Level()
    return self:CharacterLevel()
end

-- Free strikes for animal companions are derived (1 + Might modifier) per the
-- Beastheart rules, so the character sheet displays them read-only and the
-- monster-side stored opportunityAttack string is ignored for companions.
function AnimalCompanion:OpportunityAttack()
    return 1 + self:GetAttribute("mgt"):Modifier()
end

-- Animal companions have only a melee free strike (no ranged free strike), per
-- the Beastheart rules. Damage uses OpportunityAttack(), with damage type
-- copied from the signature ability when one is present (mirrors
-- monster:FillFreeStrikes' detection logic).
function AnimalCompanion:FillFreeStrikes(options, result)
    local meleeFreeStrike = MCDMUtils.GetStandardAbility("Melee Free Strike")
    if meleeFreeStrike == nil then return end

    local ability = meleeFreeStrike:MakeTemporaryClone()

    local damageType = "untyped"
    local signature = self:GetSignatureAbility()
    if signature ~= nil then
        for _,behavior in ipairs(signature.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local matchDamageType = regex.MatchGroups(behavior.tiers[3], "[0-9]+ (?<damageType>[a-z]+) damage")
                if matchDamageType ~= nil then
                    damageType = matchDamageType.damageType
                end
                break
            end
        end

        if signature:HasKeyword("Melee") then
            local signatureRange = signature:GetRange(self) or 1
            ability.range = math.max(1, signatureRange)
        end
    end

    local freeStrikeDamage = tostring(self:OpportunityAttack())
    ability.behaviors[1].roll = freeStrikeDamage .. "*Charges"
    ability.behaviors[1].damageType = damageType

    if damageType == "untyped" then
        ability.description = string.format("%s damage", freeStrikeDamage)
    else
        ability.description = string.format("%s %s damage", freeStrikeDamage, damageType)
    end

    --Same wiring as monster:FillFreeStrikes: append the flagged
    --power-modifier applicator after the damage behavior so that
    --modifiers like "Tear You to Ribbons" (Bleeding (EoT) when rampaging)
    --land on companion free strikes too.
    if ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior ~= nil then
        ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior.AppendToFreeStrike(ability)
    end

    result[#result+1] = ability
end

-- Skill sharing: per Beastheart "Shared Skills" rule, the companion has any
-- skill its summoner has and vice versa. We override SkillProficiencyLevel on
-- both sides; the recursion guard breaks the cycle when each side delegates
-- to the partner. SkillProficiencyLevel is the right hook because the
-- character sheet, the skill-check roller, and the expertise UI all read it
-- (whereas HasSkillProficiency is used by the SkillsDialog to edit the
-- explicit override table -- "own skills only" semantics are correct there).
local g_skillshareRecursion = 0

local function PickHigherProficiency(a, b)
    if a == nil or a.multiplier == nil then return b end
    if b == nil or b.multiplier == nil then return a end
    if b.multiplier > a.multiplier then return b end
    return a
end

function AnimalCompanion:SkillProficiencyLevel(skillInfo)
    local own = monster.SkillProficiencyLevel(self, skillInfo)
    if g_skillshareRecursion > 0 then return own end

    local summoner = self:SummonerToken()
    if summoner == nil then return own end

    g_skillshareRecursion = g_skillshareRecursion + 1
    local shared = summoner.properties:SkillProficiencyLevel(skillInfo)
    g_skillshareRecursion = g_skillshareRecursion - 1

    return PickHigherProficiency(own, shared)
end

local g_originalCharacterSkillProficiencyLevel = character.SkillProficiencyLevel
function character.SkillProficiencyLevel(self, skillInfo)
    local own = g_originalCharacterSkillProficiencyLevel(self, skillInfo)
    if g_skillshareRecursion > 0 then return own end

    local companionToken = self:GetCompanionToken()
    if companionToken == nil then return own end

    g_skillshareRecursion = g_skillshareRecursion + 1
    local shared = companionToken.properties:SkillProficiencyLevel(skillInfo)
    g_skillshareRecursion = g_skillshareRecursion - 1

    return PickHigherProficiency(own, shared)
end

-- Per Beastheart "Modify Companion" support: any modifier on the summoner
-- whose behavior implements modifyCompanion gets a chance to contribute extra
-- modifiers to this companion's effective modifier list. Captures
-- monster.FillTemporalActiveModifiers (already wrapped by MCDMMonster.lua to
-- include captain/minion logic) so the base monster behavior is preserved.
local g_animalCompanionFillTemporalActiveModifiersBase = monster.FillTemporalActiveModifiers
function AnimalCompanion:FillTemporalActiveModifiers(result)
    g_animalCompanionFillTemporalActiveModifiersBase(self, result)

    if mod.unloaded then return end

    local summonerToken = self:SummonerToken()
    if summonerToken == nil then return end

    local summonerCreature = summonerToken.properties
    for _,summonerMod in ipairs(summonerCreature:GetActiveModifiers()) do
        summonerMod.mod:FillCompanionModifiers(summonerMod, summonerCreature, self, result)
    end
end

-- The mirror direction -- companion -> summoner via modsummoner -- is
-- dispatched generically for ALL creature types from
-- creature:FillTemporalActiveModifiers in DMHub Game Rules/Creature.lua. That
-- hook scans dmhub.GetTokens() for any token whose summonerid points at this
-- creature's token (so it picks up the beastheart's companion via the
-- summonerid set in DSBeastheart.lua, plus any other summon created via
-- AbilitySummon, AbilityCompanion, or table-roll summons). The recursion guard
-- inside creature:GetActiveModifiers (_tmp_calculatingActiveModifiers) breaks
-- the cycle when summoner and summon ask each other for modifiers
-- mid-calculation.

function AnimalCompanion:RefreshToken(token)
    monster.RefreshToken(self, token)

    local summonerid = token.summonerid
    self._tmp_summonerid = summonerid

    local summonerToken = summonerid and dmhub.GetTokenById(self._tmp_summonerid)
    if summonerToken and summonerToken.valid then
        self._tmp_summonerToken = summonerToken

        -- If the summoner has switched companion species (or this companion was
        -- spawned before the bestiary stamp existed), soft-release it so the
        -- next Call spawns the correct type. Only the controlling client runs
        -- the action to avoid duplicate despawns.
        if (not token.despawned) and summonerToken.canControl then
            local expectedType = summonerToken.properties:GetCompanionType()
            local actualType = self:try_get("companionBestiaryId")
            if expectedType ~= nil and actualType ~= expectedType then
                local capturedSummoner = summonerToken
                dmhub.Schedule(0, function()
                    if mod.unloaded then return end
                    if not capturedSummoner.valid then return end
                    capturedSummoner.properties:ReleaseCompanion(capturedSummoner)
                end)
            end
        end

        -- Sync any in-session rename of this companion back onto the
        -- beastheart's per-type sticky name map, so a despawn/recall (or
        -- session reload) reapplies the player's chosen name. Guarded by the
        -- controlling client flag and a tmp cache of the last value we wrote,
        -- so this is a no-op on every refresh once the name is stable.
        if (not token.despawned) and summonerToken.canControl then
            local bestiaryId = self:try_get("companionBestiaryId")
            local currentName = token.name or ""
            if bestiaryId ~= nil and self:try_get("_tmp_lastSyncedName") ~= currentName then
                local storedName = summonerToken.properties:try_get("companionNames", {})[bestiaryId] or ""
                if storedName ~= currentName then
                    local capturedSummoner = summonerToken
                    local capturedBestiaryId = bestiaryId
                    local capturedName = currentName
                    dmhub.Schedule(0, function()
                        if mod.unloaded then return end
                        if not capturedSummoner.valid then return end
                        capturedSummoner:ModifyProperties{
                            description = "Sync companion name",
                            execute = function()
                                capturedSummoner.properties:SetCompanionName(capturedBestiaryId, capturedName)
                            end,
                        }
                    end)
                end
                self._tmp_lastSyncedName = currentName
            end
        end
    else
        self._tmp_summonerToken = nil
    end
end

function AnimalCompanion:SummonerToken()
    if self:try_get("_tmp_summonerToken") and self._tmp_summonerToken.valid then
        return self._tmp_summonerToken
    end

    -- The transient cache above is only populated by RefreshToken, so it can be
    -- nil right after load or on a client that hasn't refreshed this companion's
    -- token yet. Fall back to resolving the summoner directly from our own
    -- token's summonerid (mirrors creature:GetPotencySummonerToken). Without
    -- this fallback MaxHitpoints() returns its bogus 1-HP default, collapsing
    -- BloodiedThreshold() to 0 and making the companion read as dead at 0
    -- Stamina instead of following the hero rule of dying only at -half.
    local selfToken = dmhub.LookupToken(self)
    if selfToken ~= nil and selfToken.summonerid then
        local summonerToken = dmhub.GetTokenById(selfToken.summonerid)
        if summonerToken ~= nil and summonerToken.valid then
            return summonerToken
        end
    end

    return nil
end

function AnimalCompanion:MaxHitpoints(modifiers)
    local summoner = self:SummonerToken()
    if not summoner then
        return 1
    end

    return summoner.properties:MaxHitpoints()
end

local g_companionSharedResources = {
    "5bd90f9b-46be-4cf2-8ca6-a96430d62949", --recovery
    "d19658a2-4d7b-4504-af9e-1a5410fb17fd", --main action
    "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b", --maneuver
    "8b0ae5fe-0eb3-45fa-9e6d-b9de68f5cc6d", --surges
    "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca", --heroic resources
    "2166c5fe-260e-4691-9743-06cf097a59f3", --hero tokens
    "1c8e3d92-4b5f-4a76-b428-7c1d3e6f5a82", --electric surge once-per-turn limit (Elemental Spark)
    "b9bc06dd-80f1-4f33-bc55-25c114e3300c", --triggered action (per "Companion Actions" rule: one triggered action per round shared between beastheart + companion)
    "9c1e4b7a-2d38-4f60-a915-3c6e0d8f2b41", --This One's Yours once-per-turn limit (Punisher, shared beastheart + companion)
}

local g_companionSharedResourcesKeyed = {}
for _,key in ipairs(g_companionSharedResources) do
    g_companionSharedResourcesKeyed[key] = true
end

function AnimalCompanion:GetResources()

    local cached = self:try_get("_tmp_companionresources")
    if cached ~= nil and self:try_get("_tmp_companionresourcesUpdate") == dmhub.ngameupdate then
        return cached
    end

    local result = table.shallow_copy(monster.GetResources(self))

    local summoner = self:SummonerToken()
    if summoner then
        local summonerResources = summoner.properties:GetResources()
        for _,key in ipairs(g_companionSharedResources) do
            result[key] = summonerResources[key]
        end
    end

    self._tmp_companionresources = result
    self._tmp_companionresourcesUpdate = dmhub.ngameupdate

    return result
end

function AnimalCompanion:GetHeroicOrMaliceResources()
    local summoner = self:SummonerToken()
    if summoner then
        return summoner.properties:GetHeroicOrMaliceResources()
    end

    return 0
end

--Companions pay heroic-resource ability costs from their summoner's shared
--pool (Ferocity), not from Malice. The ability cost pipeline (see
--ActivatedAbility:GetCost and DSAugmentAbilities) remaps a heroic resource
--cost to creature.resourceid / GetHeroicOrMaliceId, which AnimalCompanion
--would otherwise inherit from monster (= Malice). Resolving to the hero
--heroic resource id keeps the cost on the shared pool, where GetResources /
--ConsumeResource above already route reads and writes through the summoner.
AnimalCompanion.resourceid = CharacterResource.heroicResourceId
AnimalCompanion.resourceRefresh = "unbounded"

function AnimalCompanion:GetHeroicOrMaliceId()
    return CharacterResource.heroicResourceId
end


function AnimalCompanion:ConsumeResource(key, refreshType, quantity, note)
    if g_companionSharedResourcesKeyed[key] then
        local summoner = self:SummonerToken()
        if summoner then
            print("RESOURCE:: CONSUME ON SUMMONER", quantity)
            summoner:ModifyProperties {
                description = "Consume Resource from Animal Companion",
                execute = function()
                    summoner.properties:ConsumeResource(key, refreshType, quantity, note)
                end,
            }
        end

        return
    end

    return monster.ConsumeResource(self, key, refreshType, quantity, note)
end


function AnimalCompanion:RefreshResource(key, refreshType, quantity, note)
            print("RESOURCE:: REFRESH...", quantity)
    if g_companionSharedResourcesKeyed[key] then
        local summoner = self:SummonerToken()
        if summoner then
            print("RESOURCE:: REFRESH ON SUMMONER", quantity)
            summoner:ModifyProperties {
                description = "Refresh Resource from Animal Companion",
                execute = function()
                    summoner.properties:RefreshResource(key, refreshType, quantity, note)
                end,
            }
        end

        return
    end

    monster.RefreshResource(self, key, refreshType, quantity, note)
end

function AnimalCompanion:AddUnboundedResource(key, quantity, note)
    if g_companionSharedResourcesKeyed[key] then
        local summoner = self:SummonerToken()
        if summoner then
            summoner:ModifyProperties {
                description = "Add Resource from Animal Companion",
                execute = function()
                    summoner.properties:AddUnboundedResource(key, quantity, note)
                end,
            }
        end

        return
    end

    return monster.AddUnboundedResource(self, key, quantity, note)
end

function AnimalCompanion:GetUnboundedResourceQuantity(resourceid)
    if g_companionSharedResourcesKeyed[resourceid] then
        local summoner = self:SummonerToken()
        if summoner then
            return summoner.properties:GetUnboundedResourceQuantity(resourceid)
        end

        return 0
    end

    return monster.GetUnboundedResourceQuantity(self, resourceid)
end

-- Usage-limit reads must mirror Consume/Refresh: without this override the spark
-- queries its own local usage counter (always 0) for a shared usageLimitOptions
-- resource, so a per-turn limit set up on the beastheart would never fire as
-- "spent" from the spark's side. Two triggers (one on each creature) using the
-- same shared resourceid for usageLimitOptions need both reads and writes to
-- route through the summoner; otherwise only one direction of the share works.
function AnimalCompanion:GetResourceUsage(resourceid, refreshType)
    if g_companionSharedResourcesKeyed[resourceid] then
        local summoner = self:SummonerToken()
        if summoner then
            return summoner.properties:GetResourceUsage(resourceid, refreshType)
        end

        return 0
    end

    return monster.GetResourceUsage(self, resourceid, refreshType)
end

function AnimalCompanion:GetHeroicResourceName()
    local summoner = self:SummonerToken()
    if summoner then
        return summoner.properties:GetHeroicResourceName()
    end

    return "Ferocity"
end


function AnimalCompanion:GetHeroTokens()
    return character.GetHeroTokens(self)
end

--Per-tier damage bonus application for companion melee abilities. Mirrors
--ApplyBonusesFromKit's PowerRollBehavior loop in MCDMKit.lua, but scoped to
--just the damage portion -- the companion never inherits the kit's range,
--reach, or area bonuses. Walks nested InvokeAbility chains so the burst-side
--rolls inside Feral Strike still pick up the bonus.
local function applyCompanionMeleeBonus(ability, bonuses)
    local function recurse(currentAbility)
        --Idempotence stamp: the same ability object can reach this function
        --twice -- once when GetActivatedAbilities merges the summoner's
        --abilities onto the companion (descending into nested InvokeAbility
        --customAbilities), and again when the InvokeAbility behavior clones
        --the nested ability and PostProcessInvokedAbility runs on the clone.
        --_tmp_ fields survive DeepCopy/MakeTemporaryClone/bifurcation but are
        --never serialized, so the stamp follows the clone without polluting
        --saved data.
        if currentAbility:try_get("_tmp_companionMeleeBonusApplied") then
            return
        end
        currentAbility._tmp_companionMeleeBonusApplied = true
        for _, behavior in ipairs(currentAbility.behaviors or {}) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                for i, bonus in ipairs(bonuses) do
                    local tier = behavior.tiers and behavior.tiers[i]
                    if tier ~= nil and bonus ~= 0 then
                        local match = regex.MatchGroups(tier, "(?<damage>\\d+)( [ A-Za-z,+]+)? damage", {indexes = true})
                        if match ~= nil then
                            local index = match.damage.index
                            local length = match.damage.length
                            local before = string.sub(tier, 1, index-1)
                            local after = string.sub(tier, index+length)
                            behavior.tiers[i] = string.format("%s%d%s", before, tonumber(match.damage.value) + bonus, after)
                        end
                    end
                end
            elseif behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" and behavior.customAbility ~= nil then
                recurse(behavior.customAbility)
            end
        end
    end
    recurse(ability)
end

--Looks up the bonus the companion should add to melee+weapon abilities. If
--the summoner has a kit and the player chose "kit", returns the kit's melee
--damage bonus. Otherwise returns the default companion bonus +0/+0/+4.
--@return integer[]|nil three-entry table or nil if no bonus should apply
function AnimalCompanion:GetCompanionMeleeBonus()
    local summoner = self:SummonerToken()
    if summoner == nil or summoner.properties == nil then return nil end
    local summonerCreature = summoner.properties

    local kit = summonerCreature.Kit and summonerCreature:Kit() or nil
    local levelChoices = (summonerCreature.GetLevelChoices and summonerCreature:GetLevelChoices()) or {}
    local bonusChoices = levelChoices["companionBonusChoices"] or {}
    local choice = bonusChoices["melee"] or "kit"

    if choice ~= "default" and kit ~= nil then
        local kitBonus = kit:DamageBonuses()["melee"]
        if kitBonus ~= nil then
            return kitBonus
        end
    end
    return {0, 0, 4}
end

function AnimalCompanion:GetActivatedAbilities(options)
	options = table.shallow_copy(options or {})
    options.excludeKeywords = {"Beastheart"}
    --The beastheart's kit signature ability belongs to the beastheart only;
    --the companion shouldn't pick it up when deriving abilities from the
    --summoner. (Kit features that appear via Companion-keyword channels are
    --intentional and remain.)
    options.excludeKitAbilities = true
    --Same reasoning for the kit's blanket ability modifications (range,
    --reach, area, damage bonuses across all roll types). The companion only
    --gets one specific melee damage bonus -- applied below, after merging.
    options.excludeKitModifications = true

    local result = {}

    local summoner = self:SummonerToken()
    if summoner then
        local g = options.excludeGlobal
        options.excludeGlobal = true
        result = summoner.properties:GetActivatedAbilities(options)
        options.excludeGlobal = g
    end

    local numDerivedAbilities = #result

    local ourAbilities = monster.GetActivatedAbilities(self, options)
    for i,ability in ipairs(ourAbilities) do
        local alreadyExists = false
        for j=1,numDerivedAbilities do
            if result[j].name == ability.name then
                alreadyExists = true
                break
            end
        end

        if not alreadyExists then
            result[#result+1] = ability
        end
    end

    --Apply the chosen companion melee bonus to every melee+weapon ability
    --(both ones derived from the summoner and the companion's innate ones).
    --Keywords-driven, so it correctly skips ranged/supernatural abilities.
    local meleeBonus = self:GetCompanionMeleeBonus()
    if meleeBonus ~= nil then
        for i, ability in ipairs(result) do
            local kw = ability.keywords
            if kw ~= nil and kw["Melee"] and kw["Weapon"] then
                if not ability:try_get("_tmp_temporaryClone") then
                    ability = ability:MakeTemporaryClone()
                    result[i] = ability
                end
                applyCompanionMeleeBonus(ability, meleeBonus)
            end
        end
    end

    return result
end

--Mirror the melee-bonus pass for invoked custom abilities (which bypass
--GetActivatedAbilities entirely). The InvokeAbility behavior bifurcates the
--clone first, so for dual-keyword strikes only the melee variant qualifies
--(the ranged variant has had its Melee keyword stripped).
function AnimalCompanion:PostProcessInvokedAbility(ability)
    if ability == nil or ability.keywords == nil then
        return ability
    end

    local meleeBonus = self:GetCompanionMeleeBonus()
    if meleeBonus == nil then
        return ability
    end

    local function applyToAbility(target)
        if target == nil or target.keywords == nil then return end
        if target.keywords["Melee"] and target.keywords["Weapon"] then
            applyCompanionMeleeBonus(target, meleeBonus)
        end
    end

    applyToAbility(ability)
    local variations = ability:GetVariations()
    if variations ~= nil then
        for i = 1, #variations do
            applyToAbility(variations[i])
        end
    end

    return ability
end

local function CreateCharacterDisplayPanel(element)
    local m_token = nil


    element.data.resourcePanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "horizontal",

        hover = function(element)
            local desc = "Rampage"
            local text = nil
            element.tooltip = gui.StatsHistoryTooltip{ text = text, description = desc, entries = m_token.properties:GetStatHistory(g_rampageResourceId):GetHistory() }
        end,


        gui.Label {
            width = "auto",
            height = "auto",
            halign = "left",
            fontSize = 16,
            color = Styles.textColor,
            text = "<b>Rampage</b>:",
        },
        gui.Label {
            editable = true,
            numeric = true,
            lmargin = 8,
            width = 40,
            characterLimit = 3,
            fontSize = 16,
            height = "auto",
            change = function(element)
                local quantity = tonumber(element.text) or 0
                if quantity < 0 then
                    quantity = 0
                end

                local currentQuantity = m_token.properties:GetUnboundedResourceQuantity(g_rampageResourceId)

                m_token:ModifyProperties {
                    description = "Set Rampage",
                    execute = function()
                        m_token.properties:AddUnboundedResource(g_rampageResourceId, quantity - currentQuantity, "Rampage")
                    end,
                }

                element:FireEvent("refreshCompanion", m_token)
            end,

            refreshCompanion = function(element, token)
                m_token = token

                local quantity = token.properties:GetUnboundedResourceQuantity(g_rampageResourceId)
                element.text = tostring(quantity)
            end,
        }
    }

    element:AddChild(element.data.resourcePanel)

end

local g_refreshGuid = dmhub.GenerateGuid()

function AnimalCompanion:DisplayCharacterPanel(token, element)
    local summoner = self:SummonerToken()
    if not summoner then
        element:SetClass("collapsed", true)
        return
    end

    print("DISPLAY:: CREATING")
    element:SetClass("collapsed", false)

    if element.data.init ~= g_refreshGuid then
        element.data.init = g_refreshGuid
        CreateCharacterDisplayPanel(element)
    end

    element:FireEventTree("refreshCompanion", token)

    return true
end

function creature:GetProgressionResource()
    return self:GetHeroicOrMaliceResources()
end

function creature:GetProgressionResourceHighWaterMark()
    return self:HeroicResourceHighWaterMarkForTurn()
end

function AnimalCompanion:GetProgressionResource()
    return self:GetUnboundedResourceQuantity(g_rampageResourceId)
end

function AnimalCompanion:GetProgressionResourceHighWaterMark()
    return self:GetProgressionResource()
end

--- Returns the token whose Rampage value should be displayed for this creature.
--- For a companion, returns their own token. For a beastheart (has a bound
--- companion), returns the companion's token. Returns nil for any other
--- creature -- callers use that as the cue to hide rampage UI.
--- @return CharacterToken|nil
function creature:GetRampageDisplayToken()
    if self:IsCompanion() then
        return dmhub.LookupToken(self)
    end
    return self:GetCompanionToken()
end

--- Heroic Resources panel display for Rampage. Visible whenever
--- GetRampageDisplayToken() returns non-nil (beastheart or companion).
local function CreateRampageBox()
    return gui.Panel{
        styles = TacPanelStyles.TokenBox,
        classes = {"tokenbox", "rampage"},
        data = { displayToken = nil },

        refreshCharacter = function(element, token)
            local displayToken = token and token.valid and token.properties:GetRampageDisplayToken() or nil
            element.data.displayToken = displayToken
            element:SetClass("collapsed", displayToken == nil)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        refreshValue = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        linger = function(element)
            local displayToken = element.data.displayToken
            if displayToken == nil then return end
            element.tooltip = gui.StatsHistoryTooltip{
                description = "Rampage",
                entries = displayToken.properties:GetStatHistory(g_rampageResourceId):GetHistory(),
            }
        end,

        gui.Label{
            classes = {"tokenbox", "title", "rampage"},
            text = "RAMPAGE",
        },

        gui.Panel{
            classes = {"container"},
            halign = "center",
            flow = "horizontal",
            gui.Input{
                classes = {"tokenbox", "value"},
                text = "0",
                characterLimit = 3,
                selectAllOnFocus = true,
                placeholderText = "--",
                numeric = true,
                refreshCharacter = function(element, token)
                    local displayToken = token and token.valid and token.properties:GetRampageDisplayToken() or nil
                    if displayToken == nil then return end
                    local quantity = displayToken.properties:GetUnboundedResourceQuantity(g_rampageResourceId)
                    element.textNoNotify = string.format("%d", quantity)
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                refreshValue = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                change = function(element)
                    local displayToken = element.parent.parent.data.displayToken
                    if displayToken == nil then return end
                    local n = tonumber(element.text) or 0
                    if n < 0 then n = 0 end
                    local current = displayToken.properties:GetUnboundedResourceQuantity(g_rampageResourceId)
                    if n ~= current then
                        displayToken:ModifyProperties{
                            description = "Set Rampage",
                            execute = function()
                                displayToken.properties:AddUnboundedResource(g_rampageResourceId, n - current, "Rampage")
                            end,
                        }
                    end
                    element.textNoNotify = string.format("%d", n)
                end,
            },
        },
    }
end

if TacPanel ~= nil and TacPanel.RegisterHeroicResourceDisplay ~= nil then
    TacPanel.RegisterHeroicResourceDisplay{
        id = "rampage",
        create = CreateRampageBox,
        ord = 2,
    }
end