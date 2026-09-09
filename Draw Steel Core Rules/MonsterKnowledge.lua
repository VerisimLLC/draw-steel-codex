local mod = dmhub.GetModLoading()

----------------------------------------------------------------------
-- MonsterKnowledge
--
-- What the players have learned about each monster TYPE over the campaign.
-- Drives the Monster Info dialog (Draw Steel UI/MonsterInfoDialog.lua): by
-- default players see only a monster's name and speed; everything else is
-- "???" until it is revealed, either by the Director's eye toggles or by
-- automatic learning from combat events (see MONSTER_INFO_PLAN.md at the
-- repo root for the rules and the reasoning).
--
-- Storage: the shared game document "monsterKnowledge", one record per
-- monster key:
--
--   doc.data.monsters[key] = {
--       kills = 2,
--       stamina = { tier = 2, estimate = 46 },   -- tier 0..3, 3 = exact
--       revealed = { ["attr:mgt"] = true, ["ability:Spear Charge"] = false, ... },
--   }
--
-- revealed[entry] == true means players see it, false means the Director
-- explicitly hid it (automatic learning never overrides a false), nil means
-- nothing recorded (hidden). Entry keys are built by MonsterKnowledge.EntryKey.
--
-- The key is the token's bestiary id (needs the engine's token.bestiaryId,
-- nil on older builds) or, failing that, "type:<monster_type>".
--
-- The Record* functions are the hooks combat code calls. They run on the
-- client that resolved the event (once per event) and are pcall-wrapped so a
-- bug here can never break damage or casting.
----------------------------------------------------------------------

MonsterKnowledge = {
    documentId = "monsterKnowledge",

    --chance, per kill, of learning one unknown trait.
    traitLearnChance = 0.3,

    --how far off the stamina estimate may be at each knowledge tier.
    --tier 3 is exact.
    staminaBands = {
        [1] = 0.2,
        [2] = 0.1,
    },
}

mod:RegisterDocumentForCheckpointBackups(MonsterKnowledge.documentId)

setting{
    id = "monsterinfo",
    description = "Monster Info: players learn about monsters as they fight them",
    help = "Replaces the View Portrait button on monsters with a Monster Info view showing the monster's portrait and a stat block that starts as unknown and fills in as players learn about the monster. The Director can reveal or hide each entry.",
    classes = {"dmonly"},
    default = false,
    section = "Game",
    storage = "game",
    editor = "check",
}

setting{
    id = "monsterinfoautolearn",
    description = "Players learn monster stats automatically",
    help = "Killing a monster type reveals its stamina (roughly at first, exactly by the third kill) and may reveal a trait. A monster using an ability reveals the ability, testing its characteristic reveals the characteristic, and an immunity or weakness that changes damage reveals that entry. Turn off to reveal only through the Director's eye toggles.",
    classes = {"dmonly"},
    default = true,
    section = "Game",
    storage = "game",
    editor = "check",
    monitorVisible = {"monsterinfo"},
    visible = function()
        return dmhub.GetSettingValue("monsterinfo") == true
    end,
}

function MonsterKnowledge.Enabled()
    return dmhub.GetSettingValue("monsterinfo") == true
end

function MonsterKnowledge.AutoLearnEnabled()
    return MonsterKnowledge.Enabled() and dmhub.GetSettingValue("monsterinfoautolearn") == true
end

function MonsterKnowledge.DocumentPath()
    return mod:GetDocumentPath(MonsterKnowledge.documentId)
end

--True when the local user sees everything: a Director who is not previewing
--the game through a token's eyes or logged in as a token.
function MonsterKnowledge.LocalUserSeesAll()
    return dmhub.isDM and dmhub.tokenVision == nil and dmhub.tokensLoggedInAs == nil
end

----------------------------------------------------------------------
-- Keys
----------------------------------------------------------------------

--Document keys travel through Firebase-style paths, which forbid a few
--characters. Names are otherwise used verbatim so keys stay readable.
local function SanitizeKey(str)
    return (string.gsub(tostring(str), "[%.%$#%[%]/]", "_"))
end

--- The key for one entry of a monster's stat block, e.g.
--- EntryKey("ability", "Spear Charge") -> "ability:Spear Charge".
--- Prefixes in use: attr, feature, ability, resist. Plain entries (role, ev,
--- keywords, size, freestrike, captain, immunities, stamina) have no prefix.
function MonsterKnowledge.EntryKey(prefix, name)
    return prefix .. ":" .. SanitizeKey(name)
end

--- The knowledge key for a token, or nil if it is not a monster players can
--- learn about (heroes, hero summons and retainers are excluded).
--- @param token nil|CharacterToken
--- @return nil|string
function MonsterKnowledge.KeyForToken(token)
    if token == nil or not token.valid then
        return nil
    end

    --object tokens carry non-creature properties without IsHero; treat
    --anything that cannot answer as not learnable.
    local props = token.properties
    if props == nil then
        return nil
    end
    local isHero = true
    pcall(function() isHero = props:IsHero() end)
    if isHero then
        return nil
    end

    local monsterType = props:try_get("monster_type")
    if monsterType == nil or monsterType == "" then
        return nil
    end

    if props:try_get("retainer", false) then
        return nil
    end

    local isHeroSummon = false
    pcall(function() isHeroSummon = props:IsHeroSummon() end)
    if isHeroSummon then
        return nil
    end

    --token.bestiaryId is only exposed by newer engine builds; on older ones an
    --unknown member on engine userdata reads as nil and we fall back to the type.
    local bestiaryId = token.bestiaryId
    if bestiaryId ~= nil and bestiaryId ~= "" then
        return SanitizeKey(bestiaryId)
    end

    return "type:" .. SanitizeKey(monsterType)
end

--- The knowledge key for a creature (token properties), or nil.
function MonsterKnowledge.KeyForCreature(creature)
    if creature == nil then
        return nil
    end
    return MonsterKnowledge.KeyForToken(dmhub.LookupToken(creature))
end

----------------------------------------------------------------------
-- Records
----------------------------------------------------------------------

--- The stored record for a monster key, or nil if nothing has been learned.
function MonsterKnowledge.GetRecord(key)
    if key == nil then
        return nil
    end
    local doc = mod:GetDocumentSnapshot(MonsterKnowledge.documentId)
    local data = doc.data
    if data == nil or data.monsters == nil then
        return nil
    end
    return data.monsters[key]
end

--Mutate (creating if needed) the record for key inside a document change.
local function ModifyRecord(key, description, fn)
    local doc = mod:GetDocumentSnapshot(MonsterKnowledge.documentId)
    doc:BeginChange()
    local monsters = doc.data.monsters or {}
    local record = monsters[key] or {
        kills = 0,
        stamina = { tier = 0 },
        revealed = {},
    }
    record.revealed = record.revealed or {}
    record.stamina = record.stamina or { tier = 0 }
    fn(record)
    monsters[key] = record
    doc.data.monsters = monsters
    doc:CompleteChange(description, {undoable = false})
end

--- Whether the PLAYERS can see an entry (the recorded state; ignores the
--- Director's all-seeing view). Use this for the Director's eye icons.
function MonsterKnowledge.PlayersCanSee(key, entry)
    local record = MonsterKnowledge.GetRecord(key)
    if record == nil or record.revealed == nil then
        return false
    end
    return record.revealed[entry] == true
end

--- Whether the LOCAL user sees an entry: the Director always does, players
--- only when it is revealed.
function MonsterKnowledge.IsRevealed(key, entry)
    if MonsterKnowledge.LocalUserSeesAll() then
        return true
    end
    return MonsterKnowledge.PlayersCanSee(key, entry)
end

--- Immunity/weakness entries reveal two ways: the whole line (the Director's
--- "immunities" toggle) or one damage type at a time (automatic learning).
function MonsterKnowledge.PlayersCanSeeResistance(key, damageType)
    if MonsterKnowledge.PlayersCanSee(key, "immunities") then
        return true
    end
    return MonsterKnowledge.PlayersCanSee(key, MonsterKnowledge.EntryKey("resist", string.lower(damageType or "all")))
end

function MonsterKnowledge.IsResistanceRevealed(key, damageType)
    if MonsterKnowledge.LocalUserSeesAll() then
        return true
    end
    return MonsterKnowledge.PlayersCanSeeResistance(key, damageType)
end

--- What players know about a monster's stamina.
--- @return { tier: number, estimate: nil|number, visible: boolean }
function MonsterKnowledge.StaminaKnowledge(key)
    local record = MonsterKnowledge.GetRecord(key)
    local stamina = (record ~= nil and record.stamina) or { tier = 0 }
    local tier = stamina.tier or 0
    local hidden = record ~= nil and record.revealed ~= nil and record.revealed["stamina"] == false
    return {
        tier = tier,
        estimate = stamina.estimate,
        visible = tier > 0 and not hidden,
    }
end

--- Director control: reveal (exactly) or hide the stamina line. A reveal on
--- a monster with no kills jumps straight to the exact value.
function MonsterKnowledge.SetStaminaVisibleToPlayers(key, visible)
    ModifyRecord(key, "Monster knowledge: stamina", function(record)
        if visible then
            record.revealed["stamina"] = true
            if (record.stamina.tier or 0) == 0 then
                record.stamina.tier = 3
                record.stamina.estimate = nil
            end
        else
            record.revealed["stamina"] = false
        end
    end)
end

--- Director control: set one entry's visibility for players.
function MonsterKnowledge.SetRevealed(key, entry, value)
    ModifyRecord(key, "Monster knowledge: reveal", function(record)
        record.revealed[entry] = (value == true)
    end)
end

--- Director control: set many entries at once (Reveal All / Hide All).
--- Also covers the stamina line.
function MonsterKnowledge.SetRevealedMany(key, entries, value)
    ModifyRecord(key, "Monster knowledge: reveal all", function(record)
        for _,entry in ipairs(entries) do
            record.revealed[entry] = (value == true)
        end
        record.revealed["stamina"] = (value == true)
        if value == true and (record.stamina.tier or 0) == 0 then
            record.stamina.tier = 3
            record.stamina.estimate = nil
        end
    end)
end

--- Director control: forget everything learned about a monster type.
function MonsterKnowledge.Reset(key)
    local doc = mod:GetDocumentSnapshot(MonsterKnowledge.documentId)
    doc:BeginChange()
    local monsters = doc.data.monsters or {}
    monsters[key] = nil
    doc.data.monsters = monsters
    doc:CompleteChange("Monster knowledge: reset", {undoable = false})
end

----------------------------------------------------------------------
-- Stat block entries
--
-- Shared by the dialog (to draw them) and the learning rules (to pick what
-- can be learned), so both agree on what counts as a trait or an ability.
----------------------------------------------------------------------

--- The traits shown on a monster's stat block: monster group traits, the
--- creature's own features, and its notes.
--- @return { key: string, name: string, description: string }[]
function MonsterKnowledge.TraitEntries(props)
    local result = {}
    local seen = {}

    local function add(name, description)
        if name == nil or name == "" or description == nil or description == "" then
            return
        end
        local key = MonsterKnowledge.EntryKey("feature", name)
        if seen[key] then
            return
        end
        seen[key] = true
        result[#result+1] = { key = key, name = name, description = description }
    end

    --monster-only method; the properties may bind as a plain creature.
    local groupTraits = {}
    pcall(function() groupTraits = props:GetTraitsFromGroup() end)
    for _,feature in ipairs(groupTraits or {}) do
        add(feature.name, feature.description)
    end

    for _,feature in ipairs(props:try_get("characterFeatures", {})) do
        add(feature.name, feature.description)
    end

    for _,note in ipairs(props:try_get("notes", {})) do
        add(note.title, note.text)
    end

    return result
end

--- The abilities shown on a monster's stat block, keyed by name (the spawned
--- token's abilities are clones of the bestiary's, so names are the stable id).
--- @return { key: string, name: string, ability: ActivatedAbility }[]
function MonsterKnowledge.AbilityEntries(props)
    local result = {}
    local seen = {}
    local abilities = props:GetActivatedAbilities{excludeGlobal = true, allLoadouts = true, bindCaster = true}
    for _,ability in ipairs(abilities or {}) do
        local name = ability:try_get("name", "")
        if name ~= "" then
            local key = MonsterKnowledge.EntryKey("ability", name)
            if not seen[key] then
                seen[key] = true
                result[#result+1] = { key = key, name = name, ability = ability }
            end
        end
    end
    return result
end

----------------------------------------------------------------------
-- Automatic learning
----------------------------------------------------------------------

--A kill counts when a hero (or a hero's summon/companion) did it.
local function IsHeroSide(attacker)
    if attacker == nil then
        return false
    end
    if attacker:IsHero() then
        return true
    end
    local isSummon = false
    pcall(function() isSummon = attacker:IsHeroSummon() end)
    return isSummon == true
end

--Random estimate within +/- band of the actual value, e.g. 46 for 50 at 20%.
local function EstimateStamina(actual, band)
    local factor = 1 + (math.random() * 2 - 1) * band
    local estimate = math.floor(actual * factor + 0.5)
    if estimate < 1 then
        estimate = 1
    end
    return estimate
end

--Only fill entries with no recorded state so a Director's explicit hide sticks.
local function AutoReveal(key, entry, description)
    ModifyRecord(key, description, function(record)
        if record.revealed[entry] == nil then
            record.revealed[entry] = true
        end
    end)
end

local function RecordKillInternal(victim, attacker, count)
    if not MonsterKnowledge.AutoLearnEnabled() then
        return
    end
    if victim == nil or victim:IsHero() or not IsHeroSide(attacker) then
        return
    end

    local key = MonsterKnowledge.KeyForCreature(victim)
    if key == nil then
        return
    end

    count = math.max(1, math.floor(count or 1))

    --the stamina players are estimating: one minion's, not the squad pool's.
    local maxStamina = victim:MaxHitpoints()
    if victim:try_get("minion", false) then
        maxStamina = victim:SingleMinionMaxStamina()
    end

    local traits = MonsterKnowledge.TraitEntries(victim)

    ModifyRecord(key, "Monster knowledge: kill", function(record)
        record.kills = (record.kills or 0) + count

        --each kill moves the stamina estimate one tier closer to exact.
        local stamina = record.stamina
        local oldTier = stamina.tier or 0
        local newTier = math.min(3, oldTier + count)
        if newTier ~= oldTier then
            stamina.tier = newTier
            if newTier >= 3 then
                stamina.estimate = nil
            else
                stamina.estimate = EstimateStamina(maxStamina, MonsterKnowledge.staminaBands[newTier])
            end
        end

        --one trait roll per kill.
        for i = 1, count do
            if math.random() < MonsterKnowledge.traitLearnChance then
                local unknown = {}
                for _,entry in ipairs(traits) do
                    if record.revealed[entry.key] == nil then
                        unknown[#unknown+1] = entry.key
                    end
                end
                if #unknown > 0 then
                    record.revealed[unknown[math.random(#unknown)]] = true
                end
            end
        end
    end)
end

--- Hook: a monster (victim creature) died. count is how many died (minion
--- squads lose several to one hit). Call once per event on the resolving client.
function MonsterKnowledge.RecordKill(victim, attacker, count)
    local ok, err = pcall(RecordKillInternal, victim, attacker, count)
    if not ok then
        dmhub.Debug(string.format("MonsterKnowledge.RecordKill failed: %s", tostring(err)))
    end
end

local function RecordAbilityUseInternal(casterToken, ability)
    if not MonsterKnowledge.AutoLearnEnabled() or ability == nil then
        return
    end
    local key = MonsterKnowledge.KeyForToken(casterToken)
    if key == nil then
        return
    end
    local name = ability:try_get("name", "")
    if name == "" then
        return
    end
    AutoReveal(key, MonsterKnowledge.EntryKey("ability", name), "Monster knowledge: ability")
end

--- Hook: a monster finished casting an ability.
function MonsterKnowledge.RecordAbilityUse(casterToken, ability)
    local ok, err = pcall(RecordAbilityUseInternal, casterToken, ability)
    if not ok then
        dmhub.Debug(string.format("MonsterKnowledge.RecordAbilityUse failed: %s", tostring(err)))
    end
end

local function RecordCharacteristicTestInternal(targetToken, attrid)
    if not MonsterKnowledge.AutoLearnEnabled() or attrid == nil or attrid == "-" then
        return
    end
    local key = MonsterKnowledge.KeyForToken(targetToken)
    if key == nil then
        return
    end
    AutoReveal(key, MonsterKnowledge.EntryKey("attr", attrid), "Monster knowledge: characteristic")
end

--- Hook: an ability tested a monster's characteristic against a potency.
function MonsterKnowledge.RecordCharacteristicTest(targetToken, attrid)
    local ok, err = pcall(RecordCharacteristicTestInternal, targetToken, attrid)
    if not ok then
        dmhub.Debug(string.format("MonsterKnowledge.RecordCharacteristicTest failed: %s", tostring(err)))
    end
end

local function RecordDamageModifierInternal(victim, resistanceEntry)
    if not MonsterKnowledge.AutoLearnEnabled() or resistanceEntry == nil then
        return
    end

    --only innate (stat block) immunities and weaknesses are stat block
    --knowledge; a modifier-granted one carries a source name.
    local source = resistanceEntry:try_get("source")
    if source ~= nil and source ~= "" then
        return
    end

    local key = MonsterKnowledge.KeyForCreature(victim)
    if key == nil then
        return
    end

    local damageType = string.lower(resistanceEntry:try_get("damageType", "all"))
    AutoReveal(key, MonsterKnowledge.EntryKey("resist", damageType), "Monster knowledge: immunity")
end

--- Hook: damage to a monster was changed by one of its resistance entries.
function MonsterKnowledge.RecordDamageModifier(victim, resistanceEntry)
    local ok, err = pcall(RecordDamageModifierInternal, victim, resistanceEntry)
    if not ok then
        dmhub.Debug(string.format("MonsterKnowledge.RecordDamageModifier failed: %s", tostring(err)))
    end
end
