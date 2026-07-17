local mod = dmhub.GetModLoading()

--Field mappings for the official MCDM Draw Steel character sheet PDFs. Four sheets are
--supported, all sharing a common core (BaseFields/BaseChecks/BaseMulti):
--  * Simple    -- DrawSteel_CharacterSheetBlank.pdf
--  * Expanded  -- Expanded Character Sheet (Form Fillable).pdf   (core + list blocks)
--  * Summoner  -- Summoner Character Sheet (Form Fillable).pdf   (expanded, class-matched)
--  * Beastheart-- Beastheart Expanded Character Sheet (Form Fillable).pdf (expanded, class-matched)
--
--Field names come from each PDF's AcroForm dictionary; use
--CharSheetPDFExport.DumpFields("<templateid>") against the imported asset to audit them.
--Extractors that set a field name not present in the target PDF are harmlessly ignored,
--so a single shared extractor can set both a sheet's single-box and another sheet's
--split "... 1"/"... 2" field names.
--
--The repeating ability CARD blocks ("Ability Name"/"Ability Type"/...) are still deferred;
--the Expanded sheets instead get plain-text action/maneuver/trigger lists.

local FormatSigned = CharSheetPDFExport.FormatSigned
local Join = CharSheetPDFExport.Join
local SplitIntoTwo = CharSheetPDFExport.SplitIntoTwo
local MergeFields = CharSheetPDFExport.MergeFields
local ConcatMulti = CharSheetPDFExport.ConcatMulti

local g_characteristicNames = {
    mgt = "Might",
    agl = "Agility",
    rea = "Reason",
    inu = "Intuition",
    prs = "Presence",
}

--The victory track boxes; note the PDF names box 5 with a capital V.
local function VictoryFieldName(i)
    if i == 5 then
        return "Victory 5"
    end
    return string.format("victory %d", i)
end

--The standard conditions that have "<name> EoT"/"<name> SE" tick pairs on the sheets.
local g_conditionNames = {
    "Bleeding", "Dazed", "Frightened", "Grabbed", "Prone",
    "Restrained", "Slowed", "Taunted", "Weakened",
}

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------

local function EquippedKit(creature)
    if not creature:CanHaveKits() then
        return nil
    end
    return creature:Kit()
end

local function KitDamageTier(creature, damageType, tier)
    local kit = EquippedKit(creature)
    if kit == nil then
        return nil
    end
    local bonuses = kit:DamageBonuses()[damageType]
    if bonuses == nil or bonuses[tier] == nil then
        return nil
    end
    return FormatSigned(bonuses[tier])
end

local function KitBonus(creature, key)
    local kit = EquippedKit(creature)
    if kit == nil then
        return nil
    end
    local value = kit:try_get(key)
    if value == nil or value == 0 then
        return nil
    end
    return FormatSigned(value)
end

local function WeaponNames(creature)
    local kit = EquippedKit(creature)
    if kit == nil then
        return nil
    end
    local names = {}
    for weaponName,_ in pairs(kit:try_get("weapons", {})) do
        names[#names+1] = weaponName
    end
    table.sort(names)
    return Join(names, ", ")
end

local function DisengageValue(creature)
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
    return creature:GetCustomAttribute(customAttr)
end

local function CultureAspectInfo(creature, categoryId)
    local culture = creature:GetCulture()
    if culture == nil then
        return nil
    end
    local aspectId = culture.aspects[categoryId]
    if aspectId == nil or aspectId == "" then
        return nil
    end
    return dmhub.GetTable(CultureAspect.tableName)[aspectId]
end

--Feature names sourced from a given origin key ("class", "race", "background").
local function FeatureNamesFromOrigin(creature, originKey)
    local names = {}
    local seen = {}
    for _,entry in ipairs(creature:GetClassFeaturesAndChoicesWithDetails()) do
        if rawget(entry, originKey) ~= nil and entry.feature ~= nil and entry.feature.typeName ~= "CharacterChoice" then
            local name = entry.feature.name
            if name ~= nil and not seen[name] then
                seen[name] = true
                names[#names+1] = name
            end
        end
    end
    return names
end

--Resolves an ability's action type: "action" (main action), "maneuver", "triggered",
--"move", or "malice". Mirrors DrawSteelActionBar.DrawerTypeForAbility.
local function ActionTypeOf(ability)
    local cat = ability:try_get("categorization")
    if cat == "Malice" then return "malice" end
    if cat == "Trigger" or cat == "Villain Action" then return "triggered" end
    if cat == "Move" then return "move" end
    local rid = ability:try_get("actionResourceId")
    if rid == CharacterResource.actionResourceId then return "action" end
    if rid == CharacterResource.maneuverResourceId or rid == "none" or rid == CharacterResource.freeManeuverResourceId then return "maneuver" end
    return nil
end

--Fills the standard-condition tick grid from a source creature (hero or companion).
--fieldSuffix is "" for the hero and " B" for the beastheart companion's grid. When
--allowCustom is true, non-standard conditions are written to the two free-text
--"Condition 1/2" rows (hero only; the companion grid has no name fields).
local function FillConditionGrid(sourceCreature, fields, fieldSuffix, allowCustom)
    local standard = {}
    for _,name in ipairs(g_conditionNames) do
        standard[string.lower(name)] = name
    end

    local effectsTable = dmhub.GetTable("characterOngoingEffects") or {}
    local customIndex = 0

    for _,cond in ipairs(sourceCreature:ActiveOngoingEffects()) do
        local info = effectsTable[cond:try_get("ongoingEffectid")]
        if info ~= nil then
            local eotse = "EoT"
            if cond:try_get("duration") == "save_ends" then
                eotse = "SE"
            end

            local standardName = standard[string.lower(info.name or "")]
            if standardName ~= nil then
                fields[string.format("%s %s%s", standardName, eotse, fieldSuffix)] = true
            elseif allowCustom then
                customIndex = customIndex + 1
                if customIndex <= 2 then
                    fields[string.format("Condition %d", customIndex)] = info.name
                    fields[string.format("Condition %d %s", customIndex, eotse)] = true
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Base (shared) field set: everything common to all four sheets
--------------------------------------------------------------------------------

local BaseFields = {

    -- Identity
    ["Character Name"] = function(token, creature)
        return token.name
    end,
    ["Ancestry"] = function(token, creature)
        return creature:RaceOrMonsterType()
    end,
    ["Career"] = function(token, creature)
        local background = creature:Background()
        return background ~= nil and background.name or nil
    end,
    ["Career Name"] = function(token, creature)
        local background = creature:Background()
        return background ~= nil and background.name or nil
    end,
    ["Class"] = function(token, creature)
        local names = {}
        local classesTable = dmhub.GetTable("classes")
        for _,entry in ipairs(creature:get_or_add("classes", {})) do
            local classInfo = classesTable[entry.classid]
            if classInfo ~= nil then
                names[#names+1] = classInfo.name
            end
        end
        return Join(names, " / ")
    end,
    ["Subclass"] = function(token, creature)
        local names = {}
        for _,subclass in ipairs(creature:GetSubclasses()) do
            names[#names+1] = subclass.name
        end
        return Join(names, " / ")
    end,
    ["Level"] = function(token, creature)
        return creature:CharacterLevel()
    end,
    ["XP"] = function(token, creature)
        return creature:try_get("xp", 0)
    end,
    ["Wealth"] = function(token, creature)
        return creature:CalculateNamedCustomAttribute("Wealth")
    end,
    ["Renown"] = function(token, creature)
        return creature:CalculateNamedCustomAttribute("Renown")
    end,

    -- Characteristics and potencies
    ["Might"] = function(token, creature)
        return FormatSigned(creature:GetAttribute("mgt"):Modifier())
    end,
    ["Agility"] = function(token, creature)
        return FormatSigned(creature:GetAttribute("agl"):Modifier())
    end,
    ["Reason"] = function(token, creature)
        return FormatSigned(creature:GetAttribute("rea"):Modifier())
    end,
    ["Intuition"] = function(token, creature)
        return FormatSigned(creature:GetAttribute("inu"):Modifier())
    end,
    ["Presence"] = function(token, creature)
        return FormatSigned(creature:GetAttribute("prs"):Modifier())
    end,
    ["Potency Strong"] = function(token, creature)
        return creature:CalculatePotencyValue("Strong")
    end,
    ["Potency Average"] = function(token, creature)
        return creature:CalculatePotencyValue("Average")
    end,
    ["Potency Weak"] = function(token, creature)
        return creature:CalculatePotencyValue("Weak")
    end,
    --Draw Steel saving throws succeed on a 6+.
    ["Save Value"] = function(token, creature)
        return 6
    end,

    -- Stamina, recoveries, resources
    ["stamina max"] = function(token, creature)
        return creature:MaxHitpoints()
    end,
    ["Current Stamina"] = function(token, creature)
        return creature:CurrentHitpoints()
    end,
    ["stamina temp"] = function(token, creature)
        local temp = creature:TemporaryHitpoints()
        if temp == nil or temp == 0 then
            return nil
        end
        return temp
    end,
    ["winded count"] = function(token, creature)
        return math.floor(creature:MaxHitpoints() / 2)
    end,
    ["dying count"] = function(token, creature)
        return creature:KillThresholdStamina()
    end,
    ["recov max"] = function(token, creature)
        return creature:GetResources()[CharacterResource.recoveryResourceId] or 0
    end,
    ["Recoveries"] = function(token, creature)
        local recoveryid = CharacterResource.recoveryResourceId
        local recoveryInfo = dmhub.GetTable(CharacterResource.tableName)[recoveryid]
        local maxRecoveries = creature:GetResources()[recoveryid] or 0
        local used = creature:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
        return math.max(0, maxRecoveries - used)
    end,
    ["recov stamina"] = function(token, creature)
        return creature:RecoveryAmount()
    end,
    ["resource name"] = function(token, creature)
        return creature:GetHeroicResourceName()
    end,
    ["Resource Count"] = function(token, creature)
        return creature:GetResources()[CharacterResource.heroicResourceId] or 0
    end,
    ["Surges"] = function(token, creature)
        return creature:GetAvailableSurges()
    end,
    ["Surge Damage"] = function(token, creature)
        return FormatSigned(creature:HighestCharacteristic())
    end,

    -- Combat statistics
    ["Speed"] = function(token, creature)
        return creature:CurrentMovementSpeed()
    end,
    ["Size"] = function(token, creature)
        return token.creatureSize
    end,
    ["Stability"] = function(token, creature)
        return creature:Stability()
    end,
    ["Disengage"] = function(token, creature)
        return DisengageValue(creature)
    end,

    -- Equipment modifier (kit) block
    ["Modifier Name"] = function(token, creature)
        local kit = EquippedKit(creature)
        return kit ~= nil and kit.name or nil
    end,
    ["Modifier Benefits"] = function(token, creature)
        local kit = EquippedKit(creature)
        if kit == nil then
            return nil
        end
        return kit:try_get("description")
    end,
    ["Weapon/Implement"] = function(token, creature)
        return WeaponNames(creature)
    end,
    ["Armor"] = function(token, creature)
        local kit = EquippedKit(creature)
        return kit ~= nil and kit:try_get("armor") or nil
    end,
    ["Speed Modifier"] = function(token, creature)
        return KitBonus(creature, "speed")
    end,
    ["Melee Modifier"] = function(token, creature)
        return KitBonus(creature, "reach")
    end,
    ["Ranged Modifier"] = function(token, creature)
        return KitBonus(creature, "range")
    end,
    ["Disengage Modifier"] = function(token, creature)
        return KitBonus(creature, "disengage")
    end,
    ["Stability Modifier"] = function(token, creature)
        return KitBonus(creature, "stability")
    end,
    ["Stamina Modifier"] = function(token, creature)
        return KitBonus(creature, "health")
    end,
    ["Melee Weapon Damage T1"] = function(token, creature)
        return KitDamageTier(creature, "melee", 1)
    end,
    ["Melee Weapon Damage T2"] = function(token, creature)
        return KitDamageTier(creature, "melee", 2)
    end,
    ["Melee Weapon Damage T3"] = function(token, creature)
        return KitDamageTier(creature, "melee", 3)
    end,
    ["Ranged Weapon Damage T1"] = function(token, creature)
        return KitDamageTier(creature, "ranged", 1)
    end,
    ["Ranged Weapon Damage T2"] = function(token, creature)
        return KitDamageTier(creature, "ranged", 2)
    end,
    ["Ranged Weapon Damage T3"] = function(token, creature)
        return KitDamageTier(creature, "ranged", 3)
    end,

    -- Languages
    ["Languages"] = function(token, creature)
        local names = {}
        local languagesTable = dmhub.GetTable("languages")
        for langid,_ in pairs(creature:LanguagesKnown()) do
            local lang = languagesTable[langid]
            if lang ~= nil then
                names[#names+1] = lang.name
            end
        end
        table.sort(names)
        return Join(names, ", ")
    end,

    -- Culture
    ["Culture Environment"] = function(token, creature)
        local aspect = CultureAspectInfo(creature, "environment")
        return aspect ~= nil and aspect.name or nil
    end,
    ["Environment Details"] = function(token, creature)
        local aspect = CultureAspectInfo(creature, "environment")
        return aspect ~= nil and aspect.description or nil
    end,
    ["Culture Organization"] = function(token, creature)
        local aspect = CultureAspectInfo(creature, "organization")
        return aspect ~= nil and aspect.name or nil
    end,
    ["Organization Details"] = function(token, creature)
        local aspect = CultureAspectInfo(creature, "organization")
        return aspect ~= nil and aspect.description or nil
    end,
    ["Culture Upbringing"] = function(token, creature)
        local aspect = CultureAspectInfo(creature, "upbringing")
        return aspect ~= nil and aspect.name or nil
    end,
    ["Upbringing Details"] = function(token, creature)
        local aspect = CultureAspectInfo(creature, "upbringing")
        return aspect ~= nil and aspect.description or nil
    end,

    -- Career details and complication
    ["Career Benefit"] = function(token, creature)
        return Join(FeatureNamesFromOrigin(creature, "background"), "\n")
    end,
    --Career Inciting Incident: the incident is one of the career's choices; resolving
    --the chosen option's display name is deferred to a follow-up.
    ["Complication Name"] = function(token, creature)
        local complications = creature:Complications()
        if #complications == 0 then
            return nil
        end
        return complications[1].name
    end,
    ["Complication Details"] = function(token, creature)
        local complications = creature:Complications()
        if #complications == 0 then
            return nil
        end
        return complications[1]:try_get("description")
    end,
}

local BaseChecks = {
    ["Winded Tick"] = function(token, creature)
        return creature:IsWinded()
    end,
    ["Dying Tick"] = function(token, creature)
        return creature:CurrentHitpoints() <= 0 and not creature:IsDead()
    end,
    --The kit is the hero's equipment modifier; check the "Kit" type box when one is equipped.
    ["Modifier Kit"] = function(token, creature)
        return EquippedKit(creature) ~= nil
    end,
}

local BaseMulti = {

    --Victory track: the boxes are checkboxes; box N is ticked for each victory earned.
    function(token, creature, fields)
        local victories = math.min(creature:GetVictories(), 15)
        for i = 1,victories do
            fields[VictoryFieldName(i)] = true
        end
    end,

    --Skill checkboxes: the PDF's checkbox names match the skill names.
    function(token, creature, fields)
        for _,skill in ipairs(Skill.SkillsInfo) do
            if creature:ProficientInSkill(skill) then
                fields[skill.name] = true
            end
        end
    end,

    --Titles and perks.
    function(token, creature, fields)
        local names = {}
        for _,title in ipairs(creature:Titles()) do
            names[#names+1] = title.name
        end
        fields["Titles 1"], fields["Titles 2"] = SplitIntoTwo(names, 120)
    end,
    function(token, creature, fields)
        local names = {}
        local featTable = dmhub.GetTable(CharacterFeat.tableName) or {}
        for _,featid in ipairs(creature:try_get("creatureFeats", {})) do
            local featInfo = featTable[featid]
            if featInfo ~= nil then
                names[#names+1] = featInfo.name
            end
        end
        fields["Perks 1"], fields["Perks 2"] = SplitIntoTwo(names, 120)
    end,

    --Class features across the sheet's two Class Features boxes.
    function(token, creature, fields)
        local names = FeatureNamesFromOrigin(creature, "class")
        fields["Class Features 1"], fields["Class Features 2"] = SplitIntoTwo(names, 350)
    end,

    --Inventory: trinkets, leveled treasures, and consumables by category.
    function(token, creature, fields)
        local trinkets = {}
        local leveled = {}
        local consumables = {}

        local gearTable = dmhub.GetTable("tbl_Gear")
        for itemid,entry in pairs(creature:try_get("inventory", {})) do
            local gear = gearTable[itemid]
            if gear ~= nil then
                local name = gear.name
                if entry.quantity ~= nil and entry.quantity > 1 then
                    name = string.format("%s (x%d)", name, entry.quantity)
                end

                if EquipmentCategory.IsTrinket(gear) then
                    trinkets[#trinkets+1] = name
                elseif EquipmentCategory.IsLeveledTreasure(gear) then
                    leveled[#leveled+1] = name
                elseif EquipmentCategory.IsConsumable(gear) then
                    consumables[#consumables+1] = name
                end
            end
        end

        table.sort(trinkets)
        table.sort(leveled)
        table.sort(consumables)

        fields["Trinkets 1"], fields["Trinkets 2"] = SplitIntoTwo(trinkets, 160)
        fields["Leveled Treasures 1"], fields["Leveled Treasures 2"] = SplitIntoTwo(leveled, 160)
        fields["Consumables"] = Join(consumables, "\n")

        --the three "carry three safely" slot checkboxes tick one per leveled treasure carried.
        for i = 1,math.min(#leveled, 3) do
            fields[string.format("Treasure Slot %d", i)] = true
        end
    end,

    --Downtime projects: one sheet row per active project, up to 7.
    function(token, creature, fields)
        local dti = creature:GetDowntimeInfo()
        if dti == nil then
            return
        end

        local index = 0
        for _,project in ipairs(dti:GetSortedProjects()) do
            index = index + 1
            if index > 7 then
                break
            end

            fields[string.format("project %d", index)] = project.title

            local characteristics = {}
            for _,attrid in ipairs(project:GetTestCharacteristics() or {}) do
                characteristics[#characteristics+1] = g_characteristicNames[attrid] or attrid
            end
            fields[string.format("characteristic %d", index)] = Join(characteristics, "/")
            fields[string.format("current point %d", index)] = project:GetProgress()
            fields[string.format("goal point %d", index)] = project:GetProjectGoal()
        end
    end,

    --Conditions: standard conditions tick their EoT/SE box; anything else goes in the
    --two free-text rows.
    function(token, creature, fields)
        FillConditionGrid(creature, fields, "", true)
    end,
}

--------------------------------------------------------------------------------
-- Expanded additions: text-list blocks shared by all "expanded" family sheets
--------------------------------------------------------------------------------

local ExpandedMulti = {

    --Class features and traits list blocks. Sets both the single-box name and the
    --split "... 1"/"... 2" names so it works across the Expanded/Beastheart (single
    --box) and Summoner (numbered) layouts.
    function(token, creature, fields)
        local classFeatures = FeatureNamesFromOrigin(creature, "class")
        fields["Class Features List"] = Join(classFeatures, "\n")
        fields["Class Features List 1"], fields["Class Features List 2"] = SplitIntoTwo(classFeatures, 300)
        --Beastheart's class feature area.
        fields["Beastheart Features"] = Join(classFeatures, "\n")

        local traits = FeatureNamesFromOrigin(creature, "race")
        fields["Traits List"] = Join(traits, "\n")
    end,

    --Abilities grouped by action type into the Main Actions / Maneuvers / Triggered
    --Actions list blocks.
    function(token, creature, fields)
        local byType = { action = {}, maneuver = {}, triggered = {} }
        local abilities = creature:GetActivatedAbilities{ bindCaster = true, characterSheet = true, manualTriggers = true }
        for _,ability in ipairs(abilities) do
            local t = ActionTypeOf(ability)
            if byType[t] ~= nil then
                byType[t][#byType[t]+1] = ability.name
            end
        end

        fields["Main Actions List"] = Join(byType.action, "\n")
        fields["Main Actions List 1"], fields["Main Actions List 2"] = SplitIntoTwo(byType.action, 300)
        fields["Maneuvers List"] = Join(byType.maneuver, "\n")
        fields["Triggered Actions List"] = Join(byType.triggered, "\n")
    end,

    --Heroic resource "how you gain it" rules from the class's checklist.
    function(token, creature, fields)
        local checklist = creature:GetHeroicResourceChecklist()
        if checklist == nil then
            return
        end

        local lines = {}
        for _,entry in ipairs(checklist) do
            local nm = entry.name or ""
            local details = entry.details or ""
            if details ~= "" then
                lines[#lines+1] = string.format("%s: %s", nm, details)
            elseif nm ~= "" then
                lines[#lines+1] = nm
            end
        end

        fields["Heroic Resource Rules 1"], fields["Heroic Resource Rules 2"] = SplitIntoTwo(lines, 300)
        fields["Heroic Resource Rules"] = Join(lines, "\n")
    end,
}

--------------------------------------------------------------------------------
-- Beastheart additions: companion stat block, rampage, companion conditions
--------------------------------------------------------------------------------

--Returns the beastheart's companion token (or nil), guarded against non-beastheart heroes.
local function CompanionToken(creature)
    local tok = nil
    pcall(function()
        tok = creature:GetCompanionToken()
    end)
    return tok
end

local function CompanionAttr(creature, attrid)
    local tok = CompanionToken(creature)
    if tok == nil then
        return nil
    end
    return FormatSigned(tok.properties:GetAttribute(attrid):Modifier())
end

local BeastheartFields = {
    ["Weapon"] = function(token, creature)
        return WeaponNames(creature)
    end,

    ["Companion"] = function(token, creature)
        local companionType = creature:GetCompanionType()
        if companionType == nil then
            return nil
        end
        local asset = assets.monsters[companionType]
        return asset ~= nil and asset.name or nil
    end,
    ["Companion Name"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.name or nil
    end,
    ["Companion Might"] = function(token, creature) return CompanionAttr(creature, "mgt") end,
    ["Companion Agility"] = function(token, creature) return CompanionAttr(creature, "agl") end,
    ["Companion Reason"] = function(token, creature) return CompanionAttr(creature, "rea") end,
    ["Companion Intuition"] = function(token, creature) return CompanionAttr(creature, "inu") end,
    ["Companion Presence"] = function(token, creature) return CompanionAttr(creature, "prs") end,
    ["Companion Size"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.creatureSize or nil
    end,
    ["Companion Speed"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.properties:CurrentMovementSpeed() or nil
    end,
    ["Companion Disengage"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and DisengageValue(tok.properties) or nil
    end,
    ["Companion Stability"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.properties:Stability() or nil
    end,
    ["Companion Current Stamina"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.properties:CurrentHitpoints() or nil
    end,
    ["Companion stamina max"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.properties:MaxHitpoints() or nil
    end,
    ["Companion stamina temp"] = function(token, creature)
        local tok = CompanionToken(creature)
        if tok == nil then
            return nil
        end
        local temp = tok.properties:TemporaryHitpoints()
        if temp == nil or temp == 0 then
            return nil
        end
        return temp
    end,
    ["Companion winded count"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and math.floor(tok.properties:MaxHitpoints() / 2) or nil
    end,
    ["Companion dying count"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.properties:KillThresholdStamina() or nil
    end,
    ["Companion Free Strike"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.properties:OpportunityAttack() or nil
    end,
    ["Melee Companion Damage T1"] = function(token, creature)
        local tok = CompanionToken(creature)
        if tok == nil then return nil end
        local bonus = tok.properties:GetCompanionMeleeBonus()
        return bonus ~= nil and FormatSigned(bonus[1]) or nil
    end,
    ["Melee Companion Damage T2"] = function(token, creature)
        local tok = CompanionToken(creature)
        if tok == nil then return nil end
        local bonus = tok.properties:GetCompanionMeleeBonus()
        return bonus ~= nil and FormatSigned(bonus[2]) or nil
    end,
    ["Melee Companion Damage T3"] = function(token, creature)
        local tok = CompanionToken(creature)
        if tok == nil then return nil end
        local bonus = tok.properties:GetCompanionMeleeBonus()
        return bonus ~= nil and FormatSigned(bonus[3]) or nil
    end,
}

local BeastheartChecks = {
    ["Companion Winded Tick"] = function(token, creature)
        local tok = CompanionToken(creature)
        return tok ~= nil and tok.properties:IsWinded() or nil
    end,
    ["Companion Dying Tick"] = function(token, creature)
        local tok = CompanionToken(creature)
        if tok == nil then return nil end
        return tok.properties:CurrentHitpoints() <= 0 and not tok.properties:IsDead()
    end,
}

local BeastheartMulti = {
    --Rampage counter and the 8/12/16/20/24 threshold ticks.
    function(token, creature, fields)
        local tok = CompanionToken(creature)
        if tok == nil then
            return
        end

        local rampage = tok.properties:GetUnboundedResourceQuantity(CharacterResource.rampageId)
        if rampage == nil then
            return
        end

        fields["Rampage Count"] = rampage
        for _,threshold in ipairs({8, 12, 16, 20, 24}) do
            if rampage >= threshold then
                fields[string.format("%d Rampage Tick", threshold)] = true
            end
        end
    end,

    --Companion's active conditions in the " B"-suffixed grid.
    function(token, creature, fields)
        local tok = CompanionToken(creature)
        if tok ~= nil then
            FillConditionGrid(tok.properties, fields, " B", false)
        end
    end,

    --Companion traits and abilities list.
    function(token, creature, fields)
        local tok = CompanionToken(creature)
        if tok == nil then
            return
        end
        local names = {}
        for _,ability in ipairs(tok.properties:GetActivatedAbilities{ characterSheet = true }) do
            names[#names+1] = ability.name
        end
        fields["Companion Traits and Features"] = Join(names, "\n")
    end,
}

--------------------------------------------------------------------------------
-- Summoner additions
-- NOTE: the codex does not model a summoner's minion portfolio / known-minion stat
-- blocks, squads, formations, Summoner's Range, Wards, or Implement -- those exist
-- only as free-text class-feature descriptions. So the per-minion stat grid, P1-P7
-- slots, and squad blocks are left blank for hand-entry; only what is derivable is set.
--------------------------------------------------------------------------------

local SummonerFields = {
    ["Implement Name"] = function(token, creature)
        return WeaponNames(creature)
    end,
    ["Modifier Effects"] = function(token, creature)
        local kit = EquippedKit(creature)
        return kit ~= nil and kit:try_get("description") or nil
    end,
    ["Melee Damage"] = function(token, creature)
        local kit = EquippedKit(creature)
        return kit ~= nil and kit:FormatDamageBonus("melee") or nil
    end,
    ["Ranged Damage"] = function(token, creature)
        local kit = EquippedKit(creature)
        return kit ~= nil and kit:FormatDamageBonus("ranged") or nil
    end,
    ["Minion Total"] = function(token, creature)
        local info = creature:GetSummonerLimitInfo()
        return info ~= nil and info.minionCount or nil
    end,
    ["Minion Maximum"] = function(token, creature)
        local info = creature:GetSummonerLimitInfo()
        return info ~= nil and info.maxMinions or nil
    end,
}

--------------------------------------------------------------------------------
-- Ability cards
-- Each sheet has a grid of ability cards (Name/Type/Action/Cost/Target/Distance/
-- Keywords/Details). The card TEXT fills work in pure Lua; the "Ability Type" radio
-- needs the engine's radio support (FillForm radio handling).
--------------------------------------------------------------------------------

--Non-ASCII punctuation the ability text uses, mapped to ASCII. The sheet's embedded
--font (BerlingskeSlab) has no glyphs for these, so they render as "?" or mangled
--spacing in the PDF. Keys are the UTF-8 byte sequences, written as decimal escapes so
--this file stays ASCII-only per the codex rule.
local g_textReplacements = {
    { "\226\128\152", "'" },   -- U+2018 left single quote
    { "\226\128\153", "'" },   -- U+2019 right single quote / apostrophe
    { "\226\128\156", '"' },   -- U+201C left double quote
    { "\226\128\157", '"' },   -- U+201D right double quote
    { "\226\128\147", "-" },   -- U+2013 en dash
    { "\226\128\148", "-" },   -- U+2014 em dash
    { "\226\128\162", "-" },   -- U+2022 bullet
    { "\226\128\166", "..." }, -- U+2026 ellipsis
}

--Reduces engine/authoring text to plain ASCII suitable for a PDF form field: strips
--Unity rich-text tags, unwraps markdown emphasis (ability descriptions are markdown
--source), and maps non-ASCII punctuation to ASCII.
local function CleanText(s)
    if s == nil then
        return nil
    end
    s = tostring(s)
    s = string.gsub(s, "<[^>]*>", "")        -- Unity rich-text tags
    s = string.gsub(s, "%*%*(.-)%*%*", "%1") -- markdown **bold**
    s = string.gsub(s, "__(.-)__", "%1")     -- markdown __bold__
    for _,pair in ipairs(g_textReplacements) do
        s = string.gsub(s, pair[1], pair[2])
    end
    return s
end

--Maps an ability to the "Ability Type" radio option {Free Strike, Signature, Heroic, Other}.
local g_categoryRadio = {
    ["Basic Attack"] = "Free Strike",
    ["Signature Ability"] = "Signature",
    ["Heroic Ability"] = "Heroic",
}
local function AbilityRadioType(ability)
    return g_categoryRadio[ability:try_get("categorization")] or "Other"
end

--The action-type label ("Main Action", "Maneuver", "Triggered Action", "Free", ...).
local function AbilityActionLabel(ability)
    local rid = nil
    pcall(function() rid = ability:ActionResource() end)
    if rid == nil then
        return "Free"
    end
    local resourceInfo = dmhub.GetTable(CharacterResource.tableName)[rid]
    return resourceInfo ~= nil and resourceInfo.name or nil
end

--The ability's resource cost as a bare number (3, 5, ...) or nil. The sheet's Cost
--field is a small circle and the resource is implied by the hero's heroic resource,
--so the resource name is deliberately omitted.
local function AbilityCost(ability, creature)
    if not ability:has_key("resourceCost") then
        return nil
    end
    --a "none" cost has no entry in the resource table.
    if dmhub.GetTable(CharacterResource.tableName)[ability.resourceCost] == nil then
        return nil
    end

    local num = ability:try_get("resourceNumber", 1)
    local n = tonumber(num)
    if n == nil then
        --resourceNumber can be a GoblinScript expression; try to resolve it.
        pcall(function()
            n = tonumber(dmhub.EvalGoblinScript(num, creature:LookupSymbol()))
        end)
    end
    if n == nil or n == 0 then
        return nil
    end
    return n
end

local function AbilityKeywords(ability)
    local kws = {}
    for kw,_ in pairs(ability:try_get("keywords", {})) do
        kws[#kws+1] = ActivatedAbility.CanonicalKeyword(kw)
    end
    table.sort(kws)
    return Join(kws, ", ")
end

--Finds the ability's power-roll behavior, if any.
local function PowerRollBehavior(ability)
    for _,b in ipairs(ability:try_get("behaviors", {})) do
        if b.typeName == "ActivatedAbilityPowerRollBehavior" then
            return b
        end
    end
    return nil
end

--The power-roll table as plain text: the roll line plus the three resolved tiers
--labeled "11 or lower" / "12-16" / "17+". Returns nil when the ability has no roll.
local function PowerRollText(ability, creature)
    local behavior = PowerRollBehavior(ability)
    if behavior == nil then
        return nil
    end

    local lines = {}

    local rollFormula = behavior:try_get("roll")
    if rollFormula ~= nil and rollFormula ~= "" then
        lines[#lines+1] = "Roll: " .. CleanText(rollFormula)
    end

    local tiers = behavior:try_get("tiers")
    if tiers ~= nil then
        local resolved = {}
        for i,t in ipairs(tiers) do
            local r = t
            pcall(function()
                r = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creature, t, {}, true)
            end)
            resolved[i] = r
        end

        --Bake creature tier damage (monster level scaling; usually a no-op for heroes).
        pcall(function()
            local rp = RollPropertiesPowerTable.new{ tiers = resolved }
            rp:ApplyCreatureTierDamage(creature, ability)
            resolved = rp.tiers
        end)

        local labels = { "11 or lower", "12-16", "17+" }
        for i = 1,3 do
            if resolved[i] ~= nil then
                lines[#lines+1] = string.format("%s: %s", labels[i], CleanText(resolved[i]))
            end
        end
    end

    if #lines == 0 then
        return nil
    end
    return table.concat(lines, "\n")
end

local function AbilityEffect(ability, creature)
    local parts = {}
    for _,key in ipairs({"preDescription", "description"}) do
        local text = ability:try_get(key)
        if text ~= nil and text ~= "" then
            local s = text
            pcall(function() s = StringInterpolateGoblinScript(text, creature) end)
            s = CleanText(s)
            if key == "preDescription" then
                s = "Effect: " .. s
            end
            parts[#parts+1] = s
        end
    end
    return Join(parts, "\n")
end

--The Details box: the power-roll table followed by the effect text.
local function AbilityDetails(ability, creature)
    local parts = {}
    local pr = PowerRollText(ability, creature)
    if pr ~= nil then
        parts[#parts+1] = pr
    end
    local eff = AbilityEffect(ability, creature)
    if eff ~= nil then
        parts[#parts+1] = eff
    end
    return Join(parts, "\n")
end

--Builds the ordered list of ability records for the sheet's cards. Global/universal
--maneuvers (Grab, Hide, Charge, ...) are excluded so only the hero's own abilities
--land on the cards; they are grouped signature -> heroic -> other -> triggers ->
--free strikes, alphabetical within each group.
local g_categoryRank = {
    ["Signature Ability"] = 1,
    ["Heroic Ability"] = 2,
    ["Ability"] = 3,
    ["Common Ability"] = 3,
    ["Trigger"] = 4,
    ["Basic Attack"] = 5,
}
local function AbilityRecords(token, creature)
    local abilities = creature:GetActivatedAbilities{ bindCaster = true, characterSheet = true, excludeGlobal = true }

    table.sort(abilities, function(a, b)
        local ra = g_categoryRank[a:try_get("categorization")] or 6
        local rb = g_categoryRank[b:try_get("categorization")] or 6
        if ra ~= rb then
            return ra < rb
        end
        return a:DisplayOrder() < b:DisplayOrder()
    end)

    local records = {}
    for _,ability in ipairs(abilities) do
        local target = nil
        pcall(function() target = ability:DescribeTarget(token) end)
        local distance = nil
        pcall(function() distance = ability:DescribeRange(creature) end)

        records[#records+1] = {
            name = ability.name,
            typeRadio = AbilityRadioType(ability),
            action = AbilityActionLabel(ability),
            cost = AbilityCost(ability, creature),
            target = CleanText(target),
            distance = CleanText(distance),
            keywords = AbilityKeywords(ability),
            details = AbilityDetails(ability, creature),
        }
    end
    return records
end

--The base sheet's ability-card layout: 6 groups x 3 slots = 18 cards, text fields
--"Ability <Kind>.<group>.<slot>", radios "Ability Type.<slot>" (group 0) or
--"Ability Type<group>.<slot>". The Expanded/Beastheart sheets share this pattern for
--their main cards (per the PDF field dumps); confirm each via DumpFields after import.
local BaseAbilityLayout = {
    capacity = 18,
    slot = function(index)
        return math.floor(index / 3), index % 3
    end,
    text = function(kind, g, s)
        return string.format("Ability %s.%d.%d", kind, g, s)
    end,
    typeRadio = function(g, s)
        if g == 0 then
            return string.format("Ability Type.%d", s)
        end
        return string.format("Ability Type%d.%d", g, s)
    end,
}

--Returns a multi-extractor that fills the ability cards using the given layout.
local function MakeAbilityFiller(layout)
    return function(token, creature, fields)
        local records = AbilityRecords(token, creature)
        for i,rec in ipairs(records) do
            local index = i - 1
            if index >= layout.capacity then
                break
            end
            local g, s = layout.slot(index)
            fields[layout.text("Name", g, s)] = rec.name
            fields[layout.text("Action", g, s)] = rec.action
            fields[layout.text("Cost", g, s)] = rec.cost
            fields[layout.text("Target", g, s)] = rec.target
            fields[layout.text("Distance", g, s)] = rec.distance
            fields[layout.text("Keywords", g, s)] = rec.keywords
            fields[layout.text("Details", g, s)] = rec.details
            if rec.typeRadio ~= nil then
                fields[layout.typeRadio(g, s)] = rec.typeRadio
            end
        end
    end
end

local AbilityMulti = { MakeAbilityFiller(BaseAbilityLayout) }

--------------------------------------------------------------------------------
-- Template registration
--------------------------------------------------------------------------------

CharSheetPDFExport.RegisterTemplate{
    id = "mcdm-hero-sheet",
    name = "Simple Sheet",
    variant = "simple",
    docName = "draw steel character sheet",
    fields = BaseFields,
    checks = BaseChecks,
    multi = ConcatMulti(BaseMulti, AbilityMulti),
}

CharSheetPDFExport.RegisterTemplate{
    id = "mcdm-hero-sheet-expanded",
    name = "Expanded Sheet",
    variant = "expanded",
    docName = "expanded character sheet",
    fields = BaseFields,
    checks = BaseChecks,
    multi = ConcatMulti(BaseMulti, ExpandedMulti, AbilityMulti),
}

CharSheetPDFExport.RegisterTemplate{
    id = "mcdm-hero-sheet-summoner",
    name = "Summoner Sheet",
    variant = "expanded",
    classMatch = "Summoner",
    docName = "summoner character sheet",
    fields = MergeFields(BaseFields, SummonerFields),
    checks = BaseChecks,
    multi = ConcatMulti(BaseMulti, ExpandedMulti, AbilityMulti),
}

CharSheetPDFExport.RegisterTemplate{
    id = "mcdm-hero-sheet-beastheart",
    name = "Beastheart Sheet",
    variant = "expanded",
    classMatch = "Beastheart",
    docName = "beastheart expanded character sheet",
    fields = MergeFields(BaseFields, BeastheartFields),
    checks = MergeFields(BaseChecks, BeastheartChecks),
    multi = ConcatMulti(BaseMulti, ExpandedMulti, BeastheartMulti, AbilityMulti),
}
