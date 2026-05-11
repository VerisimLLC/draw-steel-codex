local mod = dmhub.GetModLoading()

RegisterGameType("AnimalCompanion", "monster")

creature.companionid = false

function creature:IsCompanion()
    return false
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

-- Mirror of modifyCompanion in the opposite direction: any modifier on the
-- companion whose behavior implements modifySummoner contributes modifiers
-- back onto the beastheart. Used by traits like the bear's Strong Like Bear,
-- whose stat-block "you" refers to the beastheart per the Companion rules.
-- The recursion guard inside creature:GetActiveModifiers
-- (_tmp_calculatingActiveModifiers) breaks the cycle when each side asks the
-- other for modifiers mid-calculation.
local g_characterFillTemporalActiveModifiersBase = character.FillTemporalActiveModifiers
function character:FillTemporalActiveModifiers(result)
    g_characterFillTemporalActiveModifiersBase(self, result)

    if mod.unloaded then return end

    local companionToken = self:GetCompanionToken()
    if companionToken == nil then return end

    local companionCreature = companionToken.properties
    for _,companionMod in ipairs(companionCreature:GetActiveModifiers()) do
        companionMod.mod:FillSummonerModifiers(companionMod, companionCreature, self, result)
    end
end

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
    else
        self._tmp_summonerToken = nil
    end
end

function AnimalCompanion:SummonerToken()
    if self:try_get("_tmp_summonerToken") and self._tmp_summonerToken.valid then
        return self._tmp_summonerToken
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

local g_rampageResourceId = "9f418676-96be-402b-92da-0f50294146b3"

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