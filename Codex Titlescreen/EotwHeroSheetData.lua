local mod = dmhub.GetModLoading()

--The EotW hero sheet's data layer: everything the sheet shows, read from one
--Hero into one plain table by EotwHeroSheet.Data(token). The sheet's UI (C2-C5
--of docs/eotw-hero-sheet/brief.md) renders this table and never reaches into
--the creature itself, so what the sheet shows can be dumped, diffed against the
--mock and tested in one place.
--
--Each section is read inside its own pcall: a section that fails is left out
--and its error is listed in data.errors, so one broken rule never blanks the
--whole sheet. Values are plain (strings, numbers, booleans, arrays); the only
--non-plain fields are the `ability` / `trigger` / `feature` / `item`
--references the UI hands to the codex's own tooltips, all named so a dump can
--skip them.

--Shared with EotwHeroSheet.lua; either file may run first or alone (a reload).
EotwHeroSheet = rawget(_G, "EotwHeroSheet") or {}

local CHARACTERISTIC_IDS = { "mgt", "agl", "rea", "inu", "prs" }

--Ability groups in display order (A2). Free strikes and Standard actions are
--every Hero's global abilities; the rest are the Hero's own.
local ABILITY_GROUPS = {
    { id = "main", name = "Main actions" },
    { id = "maneuver", name = "Maneuvers" },
    { id = "triggered", name = "Triggered actions" },
    { id = "other", name = "Other" },
    { id = "freestrike", name = "Free strikes" },
    { id = "standard", name = "Standard actions" },
}

--Feature sections in display order (F4). "core" holds the class's Core
--Feature pins, wherever they came from.
local FEATURE_SECTIONS = {
    { id = "core", name = "Core feature" },
    { id = "class", name = "Class" },
    { id = "ancestry", name = "Ancestry" },
    { id = "complication", name = "Complication" },
    { id = "kit", name = "Kit" },
    { id = "title", name = "Titles" },
    { id = "perk", name = "Perks" },
    { id = "career", name = "Career" },
    { id = "culture", name = "Culture" },
    { id = "treasure", name = "Treasures" },
}

--Index buckets the Features list never shows: skills and languages have the
--stats band; conditions and ongoing effects live on the character panel; custom
--features are director-side additions EotW does not allow.
local FEATURE_SKIP_BUCKETS = {
    skill = true, language = true, condition = true, effect = true, custom = true, other = true,
}

--Whether a tag is one of the game-mode pillars (Combat, Exploration...), from
--the registered feature tags.
---@param tag string
---@return boolean
local function IsPillar(tag)
    for _,t in ipairs(GameSystem.featureTags or {}) do
        if t.name == tag then
            return t.gameMode == true
        end
    end
    return false
end

--Whether an index entry is a choice slot (a perk, domain or ward pick...).
---@param e table
---@return boolean
local function IsChoice(e)
    if e.chosen ~= nil and #e.chosen > 0 then
        return true
    end
    local tn = nil
    pcall(function() tn = e.feature.typeName end)
    return type(tn) == "string" and string.find(tn, "Choice", 1, true) ~= nil
end

--Treasure keyword -> the kit gear it needs, from the kit editor's own lists
--(Kit.weaponTypes: "Light Weapon" needs a Light weapon, "Bow" a Bow;
--Kit.armorTypes: "Heavy Armor" needs Heavy armor).
---@return table<string, string> weapons
---@return table<string, string> armor
local function GearKeywords()
    local weapons, armor = {}, {}
    for _,w in ipairs(Kit.weaponTypes or {}) do
        weapons[w.pattern or w.id] = w.id
    end
    for _,a in ipairs(Kit.armorTypes or {}) do
        if a.id ~= "None" then
            armor[a.text] = a.id
        end
    end
    return weapons, armor
end

--- text helpers -------------------------------------------------------------

--Codex text carries markup the sheet draws itself: <tags> and **bold**.
---@param s any
---@return string|nil
local function Clean(s)
    if s == nil then
        return nil
    end
    s = tostring(s)
    s = string.gsub(s, "<[^>]*>", "")
    s = string.gsub(s, "%*%*(.-)%*%*", "%1")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

---@param n number
---@return string
local function Signed(n)
    if n >= 0 then
        return string.format("+%d", n)
    end
    return string.format("%d", n)
end

---@param t table
---@return string[]
local function SortedKeys(t)
    local result = {}
    for k,v in pairs(t or {}) do
        if v then
            result[#result+1] = k
        end
    end
    table.sort(result)
    return result
end

--A feature's tags as a sorted list, without the display-kind tags.
---@param feature any
---@return string[]
local function FeatureTags(feature)
    local tags = {}
    pcall(function()
        for t,on in pairs(feature:try_get("tags") or {}) do
            if on and t ~= "Hidden" and t ~= "Ability" and t ~= "Trigger" then
                tags[#tags+1] = t
            end
        end
    end)
    table.sort(tags)
    return tags
end

--- the stat sources (DescribeModifications) -----------------------------------

--One stat's base value and the sources that change it, for the stat hovers.
---@param base number|nil
---@param mods table|nil DescribeModifications entries
---@return table { base, sources = { {name, value} } }
local function Sources(base, mods)
    local result = { base = base, sources = {} }
    for _,m in ipairs(mods or {}) do
        if m.key ~= nil and not m.unchanged then
            result.sources[#result.sources+1] = { name = Clean(m.key), value = Clean(m.value) }
        end
    end
    return result
end

--- sections -----------------------------------------------------------------

local Sections = {}

function Sections.identity(d, tok, p)
    d.name = EotwHeroCard.HeroDisplayName(tok)
    d.portrait = nil
    pcall(function() d.portrait = tok.offTokenPortrait end)
    d.ownerId = tok.ownerId
    d.mine = tok.ownerId ~= nil and tok.ownerId == dmhub.loginUserid
    d.ownerName = nil
    if tok.ownerId ~= nil and tok.ownerId ~= "" and tok.ownerId ~= "PARTY" then
        pcall(function() d.ownerName = dmhub.GetDisplayName(tok.ownerId) end)
    end
    d.level = p:CharacterLevel()
    d.ancestry = p:RaceOrMonsterType()

    local classNames = {}
    local classesTable = dmhub.GetTable("classes") or {}
    for _,entry in ipairs(p:get_or_add("classes", {})) do
        local classInfo = classesTable[entry.classid]
        if classInfo ~= nil then
            classNames[#classNames+1] = classInfo.name
        end
    end
    d.className = table.concat(classNames, " / ")

    local subclassNames = {}
    for _,subclass in ipairs(p:GetSubclasses()) do
        subclassNames[#subclassNames+1] = subclass.name
    end
    d.subclass = table.concat(subclassNames, " / ")

    local career = p:Background()
    d.career = career ~= nil and career.name or nil

    d.culture = {}
    local culture = p:GetCulture()
    if culture ~= nil then
        local aspects = dmhub.GetTable(CultureAspect.tableName) or {}
        for _,cat in ipairs({ "environment", "organization", "upbringing" }) do
            local aspect = aspects[culture.aspects[cat] or ""]
            if aspect ~= nil then
                d.culture[#d.culture+1] = aspect.name
            end
        end
    end

    d.complications = {}
    for _,c in ipairs(p:Complications()) do
        d.complications[#d.complications+1] = c.name
    end
end

--Titles, with the benefit each one's choice picked (C14/C15: name, echelon,
--flavour, the deed, the benefit). A title with no choice shows its effect text.
function Sections.titles(d, tok, p, ctx)
    --benefits come from the feature index: a title's chosen benefit is an
    --entry in the "title" bucket whose origin is the title.
    local benefits = {}
    local hasChoice = {}
    for _,e in ipairs(ctx.index.features) do
        if e.bucket == "title" and e.originName ~= nil then
            local list = benefits[e.originName] or {}
            benefits[e.originName] = list
            if IsChoice(e) then
                hasChoice[e.originName] = true
            end
            local chosen = e.chosen
            if chosen ~= nil and #chosen > 0 then
                for _,c in ipairs(chosen) do
                    local text = nil
                    pcall(function() text = Clean(c:GetDescription()) end)
                    list[#list+1] = { name = c.name, text = text }
                end
            elseif e.displayKind == "normal" and not IsChoice(e) then
                local text = nil
                pcall(function() text = Clean(e.feature:GetDescription()) end)
                --a title entry carries the title as its name and the benefit as subName
                list[#list+1] = { name = e.subName or e.name, text = text }
            end
        end
    end

    d.titles = {}
    for _,title in ipairs(p:Titles()) do
        local list = benefits[title.name] or {}
        --a title with a single fixed benefit (Angler, Scarred) keeps its rules
        --text in `effect`; its feature is Hidden plumbing, so nothing above
        --listed it. A choice title's effect only introduces the options.
        if #list == 0 and not hasChoice[title.name] then
            local effect = nil
            pcall(function() effect = Clean((string.gsub(title:try_get("effect") or "", "\v", "\n"))) end)
            if effect ~= nil and effect ~= "" then
                list = { { text = effect } }
            end
        end
        d.titles[#d.titles+1] = {
            id = title.id,
            name = title.name,
            echelon = tonumber(title.echelon) or 1,
            flavor = Clean(title.description),
            deed = Clean(title.prerequisite),
            benefits = list,
        }
    end
    table.sort(d.titles, function(a, b) return a.name < b.name end)
end

--Level, XP and banked Victories (C2-C6). XP per Level comes from the game's
--xpperlevel setting (16 by default; Draw Steel also has half and double pace).
function Sections.progress(d, tok, p)
    local level = p:CharacterLevel()
    local per = tonumber(dmhub.GetSettingValue("xpperlevel") or 16) or 16
    if per <= 0 then
        per = 16
    end
    local xp = tonumber(p:try_get("xp", 0)) or 0
    local into = xp - (level - 1) * per
    local victories = p:GetVictories() or 0
    local max = level >= 10

    local progress = {
        level = level,
        nextLevel = cond(max, nil, level + 1),
        xp = xp,
        xpIntoLevel = into,
        xpPerLevel = per,
        victories = victories,
        --a respite turns every banked Victory into 1 XP
        xpAtRespite = victories,
        maxLevel = max,
        readyToLevel = (not max) and into >= per,
        respiteWouldLevel = (not max) and into < per and into + victories >= per,
        epic = nil,
    }

    --Level 10: the bar becomes the class's epic resource, which each respite
    --grows by the XP gained.
    if max then
        local epicid = CharacterResource.epicResourceId
        local resources = dmhub.GetTable(CharacterResource.tableName) or {}
        local info = resources[epicid]
        local value = 0
        pcall(function()
            local total = p:GetResources()[epicid] or 0
            local used = p:GetResourceUsage(epicid, info and info.usageLimit) or 0
            value = math.max(0, total - used)
        end)
        progress.epic = {
            name = p:GetEpicResourceName(),
            value = value,
            gainAtRespite = victories,
            iconid = info ~= nil and info:try_get("iconid") or nil,
        }
    end

    d.progress = progress
end

--Stamina and Recoveries. Dead is at the negative of the Winded value.
function Sections.vitals(d, tok, p)
    local max = p:MaxHitpoints()
    local cur = p:CurrentHitpoints()
    local winded = math.floor(max / 2)
    local state = "healthy"
    local dead = false
    pcall(function() dead = p:IsDead() end)
    if dead then
        state = "dead"
    elseif cur <= 0 then
        state = "dying"
    elseif cur <= winded then
        state = "winded"
    end
    d.stamina = {
        current = cur,
        max = max,
        temp = p:TemporaryHitpoints() or 0,
        winded = winded,
        deadAt = -winded,
        state = state,
    }

    local recoveryid = CharacterResource.recoveryResourceId
    local info = (dmhub.GetTable(CharacterResource.tableName) or {})[recoveryid]
    local maxRecoveries = p:GetResources()[recoveryid] or 0
    local used = p:GetResourceUsage(recoveryid, info and info.usageLimit) or 0
    d.recoveries = {
        current = math.max(0, maxRecoveries - used),
        max = maxRecoveries,
        value = p:RecoveryAmount(),
    }
end

--The heroic resource (the class's own icon, name on hover) and surges.
function Sections.resource(d, tok, p)
    local iconid = nil
    pcall(function()
        local classInfo = p:GetClass()
        if classInfo ~= nil then
            iconid = classInfo:try_get("heroicResourceIcon")
        end
    end)
    d.resource = {
        name = p:GetHeroicResourceName(),
        value = p:GetHeroicOrMaliceResources() or 0,
        iconid = iconid,
    }
    d.surges = p:GetAvailableSurges() or 0
    --each surge spent adds damage equal to the Hero's highest characteristic
    local highest = 0
    for _,attrid in ipairs(CHARACTERISTIC_IDS) do
        pcall(function() highest = math.max(highest, p:GetAttribute(attrid):Modifier()) end)
    end
    d.surgeDamage = highest
end

--The five characteristics, each with its base and sources.
function Sections.characteristics(d, tok, p)
    d.characteristics = {}
    for _,attrid in ipairs(CHARACTERISTIC_IDS) do
        local info = creature.attributesInfo[attrid]
        local base = p:GetBaseAttribute(attrid).baseValue
        local entry = Sources(base, p:DescribeModifications(attrid, base))
        entry.id = attrid
        entry.name = info and info.description or attrid
        entry.value = p:GetAttribute(attrid):Modifier()
        --modifiers can add up past the hero cap; say why the score is lower
        local capped = false
        pcall(function() capped = p:HeroCharacteristicIsCapped(attrid, p:CalculateAttribute(attrid, base)) end)
        if capped then
            entry.cappedAt = creature.heroCharacteristicMax
        end
        d.characteristics[#d.characteristics+1] = entry
    end
end

--Size, Speed, Disengage, Stability and the Stamina/Recovery numbers, as the
--effective values with their sources (the stat hovers, C4).
function Sections.stats(d, tok, p)
    local stats = {}

    --from the properties: a character that is not on a map reports a default
    --size on its token
    local sizeBase = p:GetBaseCreatureSizeNumber()
    local sizeMods = p:DescribeModifications("creatureSize", sizeBase)
    stats.size = Sources(sizeBase, sizeMods)
    local sizeNumber = sizeBase
    if #sizeMods > 0 and sizeMods[#sizeMods].current ~= nil then
        sizeNumber = sizeMods[#sizeMods].current
    end
    stats.size.value = creature.sizes[sizeNumber] or p:GetBaseCreatureSize() or tok.creatureSize

    local speedBase = p:GetBaseSpeed("speed")
    stats.speed = Sources(speedBase, p:DescribeSpeedModifications())
    stats.speed.value = p:WalkingSpeed()

    local disengageAttr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
    stats.disengage = Sources(nil, nil)
    if disengageAttr ~= nil then
        stats.disengage = Sources(disengageAttr:CalculateBaseValue(p), p:DescribeModificationsToNamedCustomAttribute("disengagespeed"))
        stats.disengage.value = p:GetCustomAttribute(disengageAttr)
    end

    local stabilityBase = p:BaseForcedMoveResistance()
    stats.stability = Sources(stabilityBase, p:DescribeModifications("forcedmoveresistance", stabilityBase))
    stats.stability.value = p:Stability()

    local staminaBase = p:BaseHitpoints()
    stats.maxStamina = Sources(staminaBase, p:DescribeModifications("hitpoints", staminaBase))
    stats.maxStamina.value = p:MaxHitpoints()

    stats.recoveries = Sources(nil, p:DescribeResourceModifications(CharacterResource.recoveryResourceId))
    stats.recoveries.value = p:GetResources()[CharacterResource.recoveryResourceId] or 0

    local recoveryBase = math.floor(p:MaxHitpoints() / 3)
    stats.recoveryValue = Sources(recoveryBase, p:DescribeModifications("recoveryvalue", recoveryBase))
    stats.recoveryValue.value = p:RecoveryAmount()

    d.stats = stats

    --movement types in the book's form "Speed 6 (fly)": the non-walk modes
    --the Hero has at walking speed or better (everyone climbs at half speed).
    local walking = p:WalkingSpeed()
    local movement = {}
    for _,info in ipairs(creature.movementTypeInfo) do
        if info.id ~= "walk" then
            local speed = 0
            pcall(function() speed = p:GetSpeed(info.id) end)
            if speed > 0 and speed >= walking then
                movement[#movement+1] = string.lower(info.name)
            end
        end
    end
    table.sort(movement)
    d.movement = movement

    d.potency = {
        weak = p:CalculatePotencyValue("Weak"),
        average = p:CalculatePotencyValue("Average"),
        strong = p:CalculatePotencyValue("Strong"),
    }
    d.wealth = p:CalculateNamedCustomAttribute("Wealth")
    d.renown = p:CalculateNamedCustomAttribute("Renown")
end

--Skills by group, languages, immunities and weaknesses: the words row.
function Sections.words(d, tok, p)
    local byGroup = {}
    for _,skill in ipairs(Skill.SkillsInfo) do
        if p:ProficientInSkill(skill) then
            --a plain read: Skill's type default ("crafting") covers the skills
            --whose data leaves the category unset
            local cat = skill.category
            local list = byGroup[cat] or {}
            byGroup[cat] = list
            list[#list+1] = skill.name
        end
    end
    d.skills = {}
    for _,g in ipairs(Skill.categories) do
        local list = byGroup[g.id]
        if list ~= nil then
            table.sort(list)
            d.skills[#d.skills+1] = { id = g.id, name = g.text, skills = list }
        end
    end

    d.languages = {}
    local languagesTable = dmhub.GetTable("languages") or {}
    for langid,_ in pairs(p:LanguagesKnown()) do
        local lang = languagesTable[langid]
        if lang ~= nil then
            d.languages[#d.languages+1] = lang.name
        end
    end
    table.sort(d.languages)

    d.immunities = {}
    d.weaknesses = {}
    for _,e in ipairs(p:ResistanceEntries()) do
        local dr = e.entry:try_get("dr", 0)
        local text = TacPanel.CleanResistanceText(e.text) .. " " .. math.abs(dr)
        if dr < 0 then
            d.weaknesses[#d.weaknesses+1] = text
        else
            d.immunities[#d.immunities+1] = text
        end
    end
    local conditionText = p:ConditionImmunityDescription()
    if conditionText ~= nil and conditionText ~= "" then
        d.immunities[#d.immunities+1] = TacPanel.CleanResistanceText(conditionText)
    end
end

--Kit bonuses always list in this order, one kit or two.
local KIT_BONUS_ORDER = { "Stamina", "Speed", "Stability", "Disengage", "Melee distance", "Ranged distance", "Area", "Melee damage", "Ranged damage" }

--One kit's bonuses for the Hero's echelon (Stamina scales with echelon).
---@param kit Kit
---@param echelon number
---@return table[] { {label, value} }
local function KitBonuses(kit, echelon)
    local result = {}
    local function Add(label, value)
        if value ~= nil and value ~= 0 then
            result[#result+1] = { label = label, value = Signed(value) }
        end
    end
    Add("Stamina", (kit:try_get("health", 0) or 0) * echelon)
    Add("Speed", kit:try_get("speed", 0))
    Add("Stability", kit:try_get("stability", 0))
    Add("Disengage", kit:try_get("disengage", 0))
    Add("Melee distance", kit:try_get("reach", 0))
    Add("Ranged distance", kit:try_get("range", 0))
    Add("Area", kit:try_get("area", 0))
    for _,dtype in ipairs({ "melee", "ranged" }) do
        local tiers = kit:DamageBonuses()[dtype]
        if tiers ~= nil then
            local parts = {}
            local any = false
            for i = 1,3 do
                local v = tiers[i] or 0
                any = any or v ~= 0
                parts[#parts+1] = Signed(v)
            end
            if any then
                result[#result+1] = { label = cond(dtype == "melee", "Melee damage", "Ranged damage"), value = table.concat(parts, "/") }
            end
        end
    end
    return result
end

---@param kit Kit
---@return table { armor = string[], weapons = string[] }
local function KitGear(kit)
    local armor = {}
    local a = kit:try_get("armor")
    if type(a) == "string" and a ~= "" and string.lower(a) ~= "none" then
        armor[#armor+1] = a
    end
    return { armor = armor, weapons = SortedKeys(kit:try_get("weapons", {})) }
end

--The kit, or the class's kit-equivalent (K1-K5). A Tactician's two kits read
--as one: each bonus is the better of the two with its source, and the melee
--damage choice (a respite activity) only says which kit it comes from.
function Sections.kit(d, tok, p, ctx)
    local echelon = p:Echelon()
    local kitTable = dmhub.GetTable(Kit.tableName) or {}
    local result = { kind = "none", entries = {} }

    if p:CanHaveKits() then
        local kit1 = kitTable[p:try_get("kitid") or ""]
        local kit2 = nil
        if p:GetNumberOfKits() > 1 then
            kit2 = kitTable[p:try_get("kitid2") or ""]
        end

        if kit1 ~= nil and kit2 ~= nil then
            local b1 = KitBonuses(kit1, echelon)
            local b2 = KitBonuses(kit2, echelon)
            local function Find(list, label)
                for _,b in ipairs(list) do
                    if b.label == label then
                        return b.value
                    end
                end
                return nil
            end
            local labels = {}
            local seen = {}
            for _,label in ipairs(KIT_BONUS_ORDER) do
                if Find(b1, label) ~= nil or Find(b2, label) ~= nil then
                    seen[label] = true
                    labels[#labels+1] = label
                end
            end
            for _,list in ipairs({ b1, b2 }) do
                for _,b in ipairs(list) do
                    if not seen[b.label] then
                        seen[b.label] = true
                        labels[#labels+1] = b.label
                    end
                end
            end
            local bonuses = {}
            local meleeFrom = nil
            for _,label in ipairs(labels) do
                local v1, v2 = Find(b1, label), Find(b2, label)
                local useFirst
                if label == "Melee damage" or label == "Ranged damage" then
                    local dtype = cond(label == "Melee damage", "melee", "ranged")
                    useFirst = v2 == nil or (v1 ~= nil and Kit.DamageBonusSelected(p, dtype, kit1, kit2))
                    if v1 ~= nil and v2 ~= nil and dtype == "melee" then
                        meleeFrom = cond(useFirst, kit1.name, kit2.name)
                    end
                else
                    useFirst = v2 == nil or (v1 ~= nil and (tonumber(v1) or 0) >= (tonumber(v2) or 0))
                end
                bonuses[#bonuses+1] = {
                    label = label,
                    value = cond(useFirst, v1, v2),
                    from = cond(useFirst, kit1.name, kit2.name),
                    other = cond(useFirst, v2, v1),
                    otherFrom = cond(useFirst, kit2.name, kit1.name),
                }
            end
            local g1, g2 = KitGear(kit1), KitGear(kit2)
            local armor, weapons = {}, {}
            for _,list in ipairs({ g1.armor, g2.armor }) do for _,x in ipairs(list) do armor[#armor+1] = x end end
            for _,list in ipairs({ g1.weapons, g2.weapons }) do for _,x in ipairs(list) do weapons[#weapons+1] = x end end
            result.kind = "kit"
            result.combined = true
            result.meleeFrom = meleeFrom
            result.entries[1] = {
                header = "Kit",
                name = kit1.name .. " + " .. kit2.name,
                gear = { armor = armor, weapons = weapons },
                bonuses = bonuses,
            }
        elseif kit1 ~= nil or kit2 ~= nil then
            local kit = kit1 or kit2
            ---@cast kit -nil
            result.kind = "kit"
            result.entries[1] = {
                header = "Kit",
                name = kit.name,
                gear = KitGear(kit),
                bonuses = KitBonuses(kit, echelon),
            }
        end
    end

    --classes without a kit: their features tagged "Kit Equivalent" in the data
    --(the Prayer, Ward, Enchantment and Augmentation choices, the Summoner's
    --Kit). A choice shows its pick ("None chosen" when empty); a plain feature
    --shows itself. The header is the rules name, the slot's last word made
    --singular ("Conduit Ward" -> Ward, "Prayers" -> Prayer, K1).
    if result.kind == "none" then
        for _,e in ipairs(ctx.index.features) do
            local tagged = false
            pcall(function() tagged = (e.feature:try_get("tags") or {})["Kit Equivalent"] == true end)
            if tagged and type(e.name) == "string" then
                local pick = (e.chosen or {})[1]
                if pick == nil and not IsChoice(e) then
                    pick = e.feature
                end
                local text = nil
                if pick ~= nil then
                    pcall(function() text = Clean(pick:GetDescription()) end)
                end
                local header = string.match(e.name, "(%S+)%s*$") or e.name
                if string.match(header, "[^s]s$") then
                    header = string.sub(header, 1, -2)
                end
                result.kind = "equivalent"
                result.entries[#result.entries+1] = {
                    header = header,
                    name = pick ~= nil and pick.name or nil,
                    text = text,
                    choice = e.name,
                }
            end
        end
    end

    d.kit = result
    ctx.kitGear = nil
    if result.kind == "kit" then
        ctx.kitGear = result.entries[1].gear
    end
    --the Conduit's Prayer of Soldier's Skill lets a Hero without a kit use
    --light armor and light weapons (its name carries a curly apostrophe)
    for _,e in ipairs(result.entries) do
        if result.kind == "equivalent" and type(e.name) == "string" and string.find(e.name, "Soldier", 1, true) then
            ctx.kitGear = { armor = { "Light" }, weapons = { "Light" } }
        end
    end
    --the gear the No benefit tooltips name (nil = no kit)
    d.kitGear = ctx.kitGear
    --the kit read finished, so a nil kitGear really means no kit (see treasures)
    ctx.kitRead = true
end

--Why a weapon or armor treasure gives no benefit, or nil when it does (R5, N8).
---@param keywords table
---@param gear table|nil the kit's gear, nil without a kit
---@return string|nil reason "nokit", "armor" or "weapon"
local function NoBenefitReason(keywords, gear)
    local weaponKeywords, armorKeywords = GearKeywords()
    local weaponNeeds = nil
    local armorNeeds = nil
    for kw,_ in pairs(keywords) do
        if weaponKeywords[kw] ~= nil then
            weaponNeeds = weaponNeeds or {}
            weaponNeeds[#weaponNeeds+1] = weaponKeywords[kw]
        end
        if armorKeywords[kw] ~= nil then
            armorNeeds = armorNeeds or {}
            armorNeeds[#armorNeeds+1] = armorKeywords[kw]
        end
    end
    if weaponNeeds == nil and armorNeeds == nil then
        return nil
    end
    if gear == nil then
        return "nokit"
    end
    local function Has(list, x)
        for _,v in ipairs(list) do
            if v == x then
                return true
            end
        end
        return false
    end
    if armorNeeds ~= nil then
        for _,a in ipairs(armorNeeds) do
            if Has(gear.armor, a) then
                return nil
            end
        end
        return "armor"
    end
    ---@cast weaponNeeds -nil
    for _,w in ipairs(weaponNeeds) do
        if Has(gear.weapons, w) then
            return nil
        end
    end
    return "weapon"
end

--Treasures grouped Leveled / Trinkets / Consumables, each with its slot,
--equip state and any No benefit reason (R1-R7).
function Sections.treasures(d, tok, p, ctx)
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    local groups = { leveled = {}, trinket = {}, consumable = {}, other = {} }

    local function Add(itemid, equipped, slot, quantity)
        local item = gearTable[itemid]
        if item == nil then
            return
        end
        local kind = "other"
        if EquipmentCategory.IsLeveledTreasure(item) then
            kind = "leveled"
        elseif EquipmentCategory.IsTrinket(item) or EquipmentCategory.IsArtifact(item) then
            kind = "trinket"
        elseif EquipmentCategory.IsConsumable(item) then
            kind = "consumable"
        end
        local keywords = item:try_get("keywords", {})
        --the slot: the first registered item keyword (Neck, Ring, Heavy Armor...);
        --material words like Magic and Psionic are not registered
        local body = nil
        for _,kw in ipairs(SortedKeys(keywords)) do
            if GameSystem.itemKeywords[kw] then
                body = kw
                break
            end
        end
        local echelon = nil
        pcall(function() echelon = tonumber(item:try_get("echelon")) end)
        local entry = {
            itemid = itemid,
            name = item.name,
            kind = kind,
            keywords = SortedKeys(keywords),
            body = body,
            slot = slot,
            equipped = equipped,
            equippable = EquipmentCategory.IsEquippable(item),
            quantity = quantity or 1,
            echelon = echelon,
            description = Clean(item:try_get("description")),
            --if the kit section failed, the kit is unknown: claim nothing
            noBenefit = ctx.kitRead and NoBenefitReason(keywords, ctx.kitGear) or nil,
            item = item,
        }
        local list = groups[kind]
        list[#list+1] = entry
    end

    local seen = {}
    for slot,itemid in pairs(p:Equipment()) do
        if type(itemid) == "string" and not seen[itemid] then
            seen[itemid] = true
            Add(itemid, true, slot, 1)
        end
    end
    for itemid,entry in pairs(p:try_get("inventory", {})) do
        if (entry.quantity or 0) > 0 then
            Add(itemid, false, nil, entry.quantity)
        end
    end
    for _,list in pairs(groups) do
        table.sort(list, function(a, b) return a.name < b.name end)
    end

    --ancestry items ("other") are not the sheet's to move, so they never count
    local toEquip = 0
    for _,list in ipairs({ groups.leveled, groups.trinket }) do
        for _,it in ipairs(list) do
            if it.equippable and not it.equipped and it.kind ~= "consumable" then
                toEquip = toEquip + 1
            end
        end
    end

    --items that are none of the three (an ancestry item such as a Dwarf's
    --Runic Carving) list with the trinkets; their kind stays "other"
    for _,it in ipairs(groups.other) do
        groups.trinket[#groups.trinket+1] = it
    end
    table.sort(groups.trinket, function(a, b) return a.name < b.name end)

    local leveledEquipped = 0
    for _,it in ipairs(groups.leveled) do
        if it.equipped then
            leveledEquipped = leveledEquipped + 1
        end
    end

    d.treasures = {
        leveled = groups.leveled,
        trinkets = groups.trinket,
        consumables = groups.consumable,
        leveledCarried = #groups.leveled,
        leveledEquipped = leveledEquipped,
        --equippable treasure not yet worn; C3 narrows this to items won in
        --EotW once the City's provenance is wired in
        toEquip = toEquip,
    }
end

--- equipping treasure ------------------------------------------------------------

--At most this many leveled treasures equipped at once (James 2026-10-10, an
--interim stand-in for the book's carry-three rule; see the brief).
EotwHeroSheet.LEVELED_EQUIP_CAP = 3

--Draw Steel's equipment slots (creature.EquipmentSlots): leveled1-5 take
--leveled treasures and artifacts, trinket1-10 take trinkets.
local SLOT_COUNTS = { leveled = 5, trinket = 10 }

---@param item any a tbl_Gear row
---@return string|nil slotType "leveled", "trinket", or nil when the sheet cannot equip it
local function SlotTypeFor(item)
    if EquipmentCategory.IsLeveledTreasure(item) or EquipmentCategory.IsArtifact(item) then
        return "leveled"
    elseif EquipmentCategory.IsTrinket(item) then
        return "trinket"
    end
    return nil
end

---@param p creature
---@return number
local function LeveledEquipped(p)
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    local count = 0
    for slot,itemid in pairs(p:Equipment()) do
        local item = gearTable[itemid]
        if string.find(slot, "^leveled") and item ~= nil and EquipmentCategory.IsLeveledTreasure(item) then
            count = count + 1
        end
    end
    return count
end

--- Where the sheet would equip an item, or why it cannot.
--- @param tok CharacterToken
--- @param itemid string
--- @return string|nil slot the free equipment slot
--- @return string|nil reason "none" (none left in the inventory), "cap" (LEVELED_EQUIP_CAP leveled treasures already equipped), "full" or "noslot"
function EotwHeroSheet.EquipSlot(tok, itemid)
    local p = tok.properties
    local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
    if p == nil or item == nil then
        return nil, "noslot"
    end
    --a second click before the sheet re-reads would otherwise equip a copy the Hero does not have
    if (p:GetItemQuantity(itemid) or 0) < 1 then
        return nil, "none"
    end
    local slotType = SlotTypeFor(item)
    if slotType == nil then
        return nil, "noslot"
    end
    if EquipmentCategory.IsLeveledTreasure(item) and LeveledEquipped(p) >= EotwHeroSheet.LEVELED_EQUIP_CAP then
        return nil, "cap"
    end
    local equip = p:Equipment()
    for i = 1, SLOT_COUNTS[slotType] do
        local slot = slotType .. i
        if equip[slot] == nil then
            return slot, nil
        end
    end
    return nil, "full"
end

--- Equips one of an item from the Hero's inventory (uploaded, undoable).
--- @param tok CharacterToken
--- @param itemid string
--- @return boolean ok
--- @return string|nil reason see EquipSlot
function EotwHeroSheet.Equip(tok, itemid)
    local slot, reason = EotwHeroSheet.EquipSlot(tok, itemid)
    if slot == nil then
        return false, reason
    end
    tok:ModifyProperties{
        description = "Equip treasure",
        execute = function()
            local p = tok.properties
            p:SetItemQuantity(itemid, p:GetItemQuantity(itemid) - 1)
            p:Equipment()[slot] = itemid
        end,
    }
    return true, nil
end

--- Unequips the item in an equipment slot back into the inventory.
--- @param tok CharacterToken
--- @param slot string
function EotwHeroSheet.Unequip(tok, slot)
    tok:ModifyProperties{
        description = "Unequip treasure",
        execute = function()
            tok.properties:Unequip(slot)
        end,
    }
end

--The stats an equip preview compares (N3), in the stats band's words.
---@param p creature
---@return table[] { {label, value} }
local function PreviewSnapshot(p)
    local result = {}
    local function Put(label, fn)
        local ok, v = pcall(fn)
        if ok and type(v) == "number" then
            result[#result+1] = { label = label, value = v }
        end
    end
    Put("Stamina", function() return p:MaxHitpoints() end)
    Put("Speed", function() return p:WalkingSpeed() end)
    Put("Disengage", function()
        local attr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
        return attr ~= nil and p:GetCustomAttribute(attr) or nil
    end)
    Put("Stability", function() return p:Stability() end)
    for _,attrid in ipairs(CHARACTERISTIC_IDS) do
        local info = creature.attributesInfo[attrid]
        Put(info and info.description or attrid, function() return p:GetAttribute(attrid):Modifier() end)
    end
    return result
end

--- What equipping (or unequipping) an item would change, for its button's
--- tooltip. The change is tried on the Hero in memory and undone in the same
--- call; nothing is uploaded.
--- @param tok CharacterToken
--- @param itemid string
--- @param slot string|nil the item's slot when equipped (to preview Unequip)
--- @return table[] changes { {label, from, to} }
function EotwHeroSheet.EquipPreview(tok, itemid, slot)
    local p = tok.properties
    local equip = p:Equipment()
    local trySlot = slot
    if trySlot == nil then
        trySlot = EotwHeroSheet.EquipSlot(tok, itemid)
    end
    if trySlot == nil then
        return {}
    end
    local before = PreviewSnapshot(p)
    local old = equip[trySlot]
    local after = {}
    pcall(function()
        equip[trySlot] = cond(slot == nil, itemid, nil)
        p:Invalidate()
        after = PreviewSnapshot(p)
    end)
    equip[trySlot] = old
    pcall(function() p:Invalidate() end)

    local changes = {}
    for i,b in ipairs(before) do
        local a = after[i]
        if a ~= nil and a.label == b.label and a.value ~= b.value then
            changes[#changes+1] = { label = b.label, from = b.value, to = a.value }
        end
    end
    return changes
end

--- spending a Recovery (C8) --------------------------------------------------------

--- Whether the Hero can spend a Recovery right now: one left, and below their
--- Stamina maximum (the sheet also limits it to the owner, in town).
--- @param tok CharacterToken
--- @return boolean
function EotwHeroSheet.CanSpendRecovery(tok)
    local ok = false
    pcall(function()
        local p = tok.properties
        local id = CharacterResource.recoveryResourceId
        local info = (dmhub.GetTable(CharacterResource.tableName) or {})[id]
        local left = (p:GetResources()[id] or 0) - (p:GetResourceUsage(id, info and info.usageLimit) or 0)
        ok = left > 0 and p:CurrentHitpoints() < p:MaxHitpoints()
    end)
    return ok
end

--- Spends one Recovery: regains the Recovery value in Stamina (uploaded, undoable),
--- the same as the character panel's Use Recovery. Returns true if it did.
--- @param tok CharacterToken
--- @return boolean
function EotwHeroSheet.SpendRecovery(tok)
    if not EotwHeroSheet.CanSpendRecovery(tok) then
        return false
    end
    tok:ModifyProperties{
        description = "Use Recovery",
        execute = function()
            local p = tok.properties
            local id = CharacterResource.recoveryResourceId
            local info = (dmhub.GetTable(CharacterResource.tableName) or {})[id]
            p:Heal(p:RecoveryAmount(), "Use Recovery")
            p:ConsumeResource(id, info and info.usageLimit or "long", 1, "Used Recovery")
        end,
    }
    return true
end

--- abilities ------------------------------------------------------------------

--The row tags for an ability (A4: the action type, with "No action" in place
--of "Free"; the cost: Signature, or "{n} {Resource}").
---@param ability ActivatedAbility
---@param resourceName string
---@return string actionTag
---@return string|nil costTag
local function AbilityTags(ability, resourceName)
    local resTable = dmhub.GetTable(CharacterResource.tableName) or {}
    local actionName = nil
    pcall(function()
        local rid = ability:ActionResource()
        if rid ~= nil and resTable[rid] ~= nil then
            actionName = resTable[rid].name
        end
    end)
    local cat = ability:try_get("categorization")
    local actionTag
    if cat == "Trigger" then
        actionTag = "Triggered action"
    elseif actionName == nil or actionName == "" or actionName == "Free" then
        actionTag = "No action"
    else
        actionTag = string.upper(string.sub(actionName, 1, 1)) .. string.lower(string.sub(actionName, 2))
    end

    local costTag = nil
    pcall(function()
        if ability:has_key("resourceCost") and resTable[ability.resourceCost] ~= nil then
            local n = tonumber(ability:try_get("resourceNumber", 1)) or 1
            if n > 0 then
                costTag = string.format("%d %s", n, resourceName)
            end
        end
    end)
    if costTag == nil and cat == "Signature Ability" then
        costTag = "Signature"
    elseif costTag == nil and cat == "Basic Attack" then
        costTag = "Free strike"
    end
    return actionTag, costTag
end

---@param actionTag string
---@return string groupid
local function AbilityGroup(actionTag)
    local t = string.lower(actionTag)
    if string.find(t, "trigger", 1, true) then
        return "triggered"
    end
    if string.find(t, "main action", 1, true) then
        return "main"
    end
    if string.find(t, "maneuver", 1, true) then
        return "maneuver"
    end
    return "other"
end

--Abilities per the tagging plan (docs/feature-metadata-incremental/
--hero-tagging-plan.md): an ability whose source feature is tagged Ability or
--Trigger is an ability card; one whose source is a visible prose feature or a
--Hidden one stays out (the feature shows instead, or nothing); Core Feature
--actions (Judgment, Mark) and kit signature abilities, which have no source
--feature, show. Every Hero's global abilities are grouped as Free strikes and
--Standard actions.
function Sections.abilities(d, tok, p, ctx)
    --ability -> the feature that grants it, from every indexed feature's modifiers
    local byGuid, byName, byMod = {}, {}, {}
    local function Scan(feature)
        if feature == nil then
            return
        end
        pcall(function()
            for _,m in ipairs(feature:try_get("modifiers", {})) do
                byMod[m] = feature
                local guid = m:try_get("guid")
                if guid ~= nil then
                    byMod[guid] = feature
                end
                local a = m:try_get("activatedAbility")
                if a ~= nil then
                    byGuid[a.guid] = feature
                    byName[a.name] = feature
                end
            end
        end)
    end
    for _,e in ipairs(ctx.index.features) do
        Scan(e.feature)
        for _,c in ipairs(e.chosen or {}) do
            Scan(c)
        end
    end

    local resourceName = (d.resource and d.resource.name) or p:GetHeroicResourceName()
    local groups = {}
    for _,g in ipairs(ABILITY_GROUPS) do
        groups[g.id] = { id = g.id, name = g.name, items = {} }
    end
    local seenNames = {}

    local function Hidden(ability)
        return ability:try_get("hidden") == true or ability:try_get("categorization") == "Hidden"
    end

    --whether something granted by `source` shows as an ability card
    local function Shows(source)
        if source == nil then
            return true
        end
        local kind = "normal"
        pcall(function() kind = source:DisplayKind() end)
        local core = false
        pcall(function() core = (source:try_get("tags") or {})["Core Feature"] == true end)
        return kind == "ability" or kind == "trigger" or (kind == "normal" and core)
    end

    local own = p:GetActivatedAbilities{ bindCaster = true, characterSheet = true, excludeGlobal = true }
    for _,ability in ipairs(own) do
        local source = byGuid[ability.guid] or byName[ability.name]
        local show = (not Hidden(ability)) and Shows(source)
        if show and not seenNames[ability.name] then
            seenNames[ability.name] = true
            local actionTag, costTag = AbilityTags(ability, resourceName)
            local groupid = AbilityGroup(actionTag)
            if ability:try_get("categorization") == "Basic Attack" then
                groupid = "freestrike"
            end
            local list = groups[groupid].items
            list[#list+1] = {
                name = ability.name,
                actionTag = actionTag,
                costTag = costTag,
                category = ability:try_get("categorization"),
                source = source ~= nil and source.name or nil,
                ability = ability,
            }
        end
    end

    --triggered actions shown in the trigger drawer, from the Hero's own
    --modifiers (the global Opportunity Attack is every Hero's)
    local triggers = {}
    for _,entry in ipairs(p:GetActiveModifiers()) do
        if not entry._global then
            local before = #triggers
            pcall(function() entry.mod:AccumulateTriggeredActionDisplay(entry, p, triggers) end)
            local source = byMod[entry.mod]
            if source == nil then
                pcall(function() source = byMod[entry.mod.guid] end)
            end
            for i = before + 1, #triggers do
                --a trigger card from a visible feature still shows (the drawer is
                --where the codex puts it); only Hidden plumbing stays out
                local kind = "normal"
                if source ~= nil then
                    pcall(function() kind = source:DisplayKind() end)
                end
                triggers[i] = { display = triggers[i], show = kind ~= "hidden", source = source }
            end
        end
    end
    for _,tt in ipairs(triggers) do
        local t = tt.display
        if t.name ~= nil and tt.show and not seenNames[t.name] then
            seenNames[t.name] = true
            local list = groups.triggered.items
            list[#list+1] = {
                name = t.name,
                actionTag = cond(t.type == "free", "Free triggered action", "Triggered action"),
                costTag = cond(t.cost ~= nil and t.cost ~= "", t.cost, nil),
                category = "Triggered Action",
                source = tt.source ~= nil and tt.source.name or nil,
                trigger = t,
            }
        end
    end

    --every Hero's abilities: whatever is in the full list and not the Hero's own
    local ownNames = {}
    for _,ability in ipairs(own) do
        ownNames[ability.name] = true
    end
    for _,ability in ipairs(p:GetActivatedAbilities{ bindCaster = true, characterSheet = true }) do
        if not ownNames[ability.name] and not Hidden(ability) and not seenNames[ability.name] then
            seenNames[ability.name] = true
            local actionTag, costTag = AbilityTags(ability, resourceName)
            local groupid = cond(ability:try_get("categorization") == "Basic Attack", "freestrike", "standard")
            local list = groups[groupid].items
            list[#list+1] = {
                name = ability.name,
                actionTag = actionTag,
                costTag = costTag,
                category = ability:try_get("categorization"),
                ability = ability,
            }
        end
    end

    d.abilities = {}
    for _,g in ipairs(ABILITY_GROUPS) do
        if #groups[g.id].items > 0 then
            d.abilities[#d.abilities+1] = groups[g.id]
        end
    end
end

--- features -------------------------------------------------------------------

--A walker over the features a Hero actually has (the sheet's own copy, so it
--does not depend on the tac panel's curation). Collect(feature, bucket, accept,
--out) explodes one feature into its LEAVES: a CharacterFeatureList opens into
--its features, except a "<X> Domain" list for a domain the Hero does not own; a
--CharacterFeatureChoice resolves to the options picked (choices within choices
--included; an unmade choice yields nothing); every other feature is a leaf,
--kept when accept(leaf, bucket) says so. IsDomainScaffolding(name) names the
--domain bundles and markers that are structure, not features.
---@param creature creature
---@return table walker
local function NewLeafWalker(creature)
    local ownedDomains = {}
    pcall(function()
        for _,dom in ipairs(creature:GetDomains() or {}) do
            local nm = (type(dom) == "table") and (dom.name or dom.id) or dom
            if nm ~= nil then ownedDomains[tostring(nm)] = true end
        end
    end)
    local hasDomains = next(ownedDomains) ~= nil
    local levelChoices = creature:GetLevelChoices() or {}

    local function IsUnownedDomainList(name)
        if not hasDomains or type(name) ~= "string" then return false end
        local dom = name:match("^(.-) Domains?$")
        if dom == nil or dom == "" then return false end
        return not ownedDomains[dom]
    end

    local walker = {}

    function walker.IsDomainScaffolding(name)
        if type(name) ~= "string" then return false end
        if name:match("^.- Domains?$") then return true end
        return ownedDomains[name] == true
    end

    local function Walk(feature, out, depth, bucketId, accept)
        if feature == nil or depth > 6 then return end
        local tn = nil
        pcall(function() tn = feature.typeName end)
        if tn == "CharacterFeatureList" then
            local listName = nil
            pcall(function() listName = feature:try_get("name") end)
            if IsUnownedDomainList(listName) then return end
            local kids = nil
            pcall(function() kids = feature:try_get("features", {}) end)
            for _,sub in ipairs(kids or {}) do
                Walk(sub, out, depth + 1, bucketId, accept)
            end
        elseif tn == "CharacterFeatureChoice" then
            local guid = nil
            pcall(function() guid = feature.guid end)
            local made = (guid ~= nil and levelChoices[guid]) or {}
            if #made == 0 then return end
            local options = nil
            pcall(function() options = feature:GetOptions(levelChoices) end)
            if type(options) ~= "table" then return end
            local byGuid = {}
            for _,o in ipairs(options) do
                local g = nil
                pcall(function() g = o.guid end)
                if g ~= nil then byGuid[g] = o end
            end
            for _,id in ipairs(made) do
                if byGuid[id] ~= nil then
                    Walk(byGuid[id], out, depth + 1, bucketId, accept)
                end
            end
        elseif accept(feature, bucketId) then
            out[#out+1] = feature
        end
    end

    ---@param feature any
    ---@param bucketId string|nil
    ---@param accept fun(leaf: any, bucketId: string|nil): boolean
    ---@param out table
    function walker.Collect(feature, bucketId, accept, out)
        Walk(feature, out, 0, bucketId, accept)
    end

    return walker
end

--Whether a leaf feature shows in the Features list. The display-kind tags
--decide first (Ability and Trigger features show as ability cards, Hidden ones
--nowhere). Then what the sheet shows elsewhere stays out: the kit's own stats
--(the Kit card), characteristic raises (the tiles), a resource with no text,
--and skill or language grants (the words row) unless a pillar tag marks the
--grant as saying more (Telepathic Speech).
---@param feature any
---@return boolean
local function ShowsAsFeature(feature)
    local kind = "normal"
    pcall(function() kind = feature:DisplayKind() end)
    if kind ~= "normal" then
        return false
    end
    local choiceBucket = FeatureCategoriser.ChoiceBucket(feature)
    if choiceBucket == "skill" or choiceBucket == "language" then
        return false
    end
    local mods = {}
    pcall(function() mods = feature:try_get("modifiers", {}) end)
    local allResources = #mods > 0
    for _,m in ipairs(mods) do
        local behavior = nil
        pcall(function() behavior = m.behavior end)
        if behavior == "kitmodifyability" then
            return false
        end
        allResources = allResources and behavior == "resource"
    end
    if FeatureCategoriser.FeatureIsOnlyCharacteristics(feature) then
        return false
    end
    if allResources then
        local text = nil
        pcall(function() text = Clean(feature:GetDescription()) end)
        if text == nil or text == "" then
            return false
        end
    end
    if FeatureCategoriser.FeatureGrantsSkillOrLanguage(feature) then
        for _,t in ipairs(FeatureTags(feature)) do
            if IsPillar(t) then
                return true
            end
        end
        return false
    end
    return true
end

--Features by section (F1-F7). Each index entry is walked down to the features
--the Hero really has (NewLeafWalker above: lists opened, choices -
--and choices within choices - resolved to the options picked, other domains
--pruned); a pick shows as its own feature, "Chosen for {choice}".
function Sections.features(d, tok, p, ctx)
    local sections = {}
    for _,s in ipairs(FEATURE_SECTIONS) do
        sections[s.id] = { id = s.id, name = s.name, items = {} }
    end
    local seen = {}
    local total = 0

    local function Add(sectionid, feature, name, chosenFor)
        if feature == nil or name == nil then
            return
        end
        local text = nil
        pcall(function() text = Clean(feature:GetDescription()) end)
        local key = name .. "|" .. (text or "")
        if seen[key] then
            return
        end
        seen[key] = true
        local tags = FeatureTags(feature)
        local pillars = {}
        local core = false
        for _,t in ipairs(tags) do
            if IsPillar(t) then
                pillars[#pillars+1] = t
            elseif t == "Core Feature" then
                core = true
            end
        end
        local section = sections[cond(core, "core", sectionid)] or sections.class
        section.items[#section.items+1] = {
            guid = feature:try_get("guid"),
            name = name,
            text = text,
            pillars = pillars,
            chosenFor = chosenFor,
            feature = feature,
        }
        total = total + 1
    end

    local walker = NewLeafWalker(p)
    for _,e in ipairs(ctx.index.features) do
        if not FEATURE_SKIP_BUCKETS[e.bucket or "other"] then
            local choice = IsChoice(e)
            local leaves = {}
            if choice then
                for _,c in ipairs(e.chosen or {}) do
                    walker.Collect(c, e.bucket, ShowsAsFeature, leaves)
                end
            else
                walker.Collect(e.feature, e.bucket, ShowsAsFeature, leaves)
            end
            for _,leaf in ipairs(leaves) do
                local name = nil
                pcall(function() name = leaf.name end)
                --a title's entry is named for the title; its leaf is the benefit
                if e.bucket == "title" then
                    name = e.name
                end
                if not walker.IsDomainScaffolding(name) then
                    Add(e.bucket, leaf, name, cond(choice and name ~= e.name, e.name, nil))
                end
            end
        end
    end

    --the Level 10 feature that grants the epic resource (the card's hover on
    --the epic resource's name): whichever feature carries a resource modifier
    --for the epic resource, so it holds for every class
    d.epicFeature = nil
    for _,e in ipairs(ctx.index.features) do
        local found = false
        pcall(function()
            for _,m in ipairs(e.feature:try_get("modifiers", {})) do
                if m:try_get("behavior") == "resource" and m:try_get("resourceType") == CharacterResource.epicResourceId then
                    found = true
                end
            end
        end)
        if found and d.epicFeature == nil then
            local text = nil
            pcall(function() text = Clean(e.feature:GetDescription()) end)
            d.epicFeature = { name = e.feature.name, text = text, feature = e.feature }
        end
    end

    d.features = { sections = {}, total = total }
    for _,s in ipairs(FEATURE_SECTIONS) do
        if #sections[s.id].items > 0 then
            d.features.sections[#d.features.sections+1] = sections[s.id]
        end
    end
end

--Sections in the order they run: kit before treasures (No benefit reads the
--kit's gear), resource before abilities (cost tags name the resource).
local SECTION_ORDER = {
    "identity", "titles", "progress", "vitals", "resource", "characteristics",
    "stats", "words", "kit", "treasures", "abilities", "features",
}

--The sections that read the feature index (FeatureCategoriser.BuildIndex), the
--costly part of a read.
local INDEX_SECTIONS = { titles = true, kit = true, abilities = true, features = true }

--Errors already sent to the debug console. The sheet re-reads on every
--character change, so each distinct error is logged once a session.
local g_loggedErrors = {}

--- Reads everything the EotW hero sheet shows for one Hero into one table.
--- Pass the Hero's token (a map token in game or a lobby character in town).
--- Returns nil when the Hero has no properties yet (still loading). Sections
--- that fail are left out and named in data.errors as "{section}: {error}".
--- `only` reads just the named sections (e.g. {"vitals", "resource"}), for a
--- cheap live refresh; the feature index is built only when one needs it.
--- @param tok CharacterToken|nil
--- @param only? string[]
--- @return table|nil
function EotwHeroSheet.Data(tok, only)
    if tok == nil then
        return nil
    end
    local p = nil
    pcall(function() p = tok.properties end)
    if p == nil then
        return nil
    end

    local wanted = nil
    if only ~= nil then
        wanted = {}
        for _,name in ipairs(only) do
            wanted[name] = true
        end
    end

    local d = { charid = tok.charid, errors = {} }
    local ctx = { index = { features = {} } }
    local needsIndex = true
    if wanted ~= nil then
        needsIndex = false
        for name in pairs(INDEX_SECTIONS) do
            needsIndex = needsIndex or wanted[name] == true
        end
    end
    if needsIndex then
        local ok, err = pcall(function() ctx.index = FeatureCategoriser.BuildIndex(p) end)
        if not ok then
            d.errors[#d.errors+1] = "index: " .. tostring(err)
        end
    end

    for _,name in ipairs(SECTION_ORDER) do
        if wanted == nil or wanted[name] then
            local okSection, errSection = pcall(Sections[name], d, tok, p, ctx)
            if not okSection then
                d.errors[#d.errors+1] = name .. ": " .. tostring(errSection)
            end
        end
    end
    for _,err in ipairs(d.errors) do
        if not g_loggedErrors[err] then
            g_loggedErrors[err] = true
            dmhub.Error(string.format("EotW hero sheet: %s", err))
        end
    end
    return d
end

--- The Data table with every object reference removed, for dumps and diffs.
--- @param data table
--- @return table
function EotwHeroSheet.PlainData(data)
    local skip = { ability = true, trigger = true, feature = true, item = true }
    local function Copy(v)
        if type(v) ~= "table" then
            return v
        end
        local out = {}
        for k,x in pairs(v) do
            if not skip[k] then
                local t = type(x)
                if t == "table" then
                    if getmetatable(x) == nil then
                        out[k] = Copy(x)
                    end
                elseif t ~= "function" and t ~= "userdata" then
                    out[k] = x
                end
            end
        end
        return out
    end
    return Copy(data)
end
