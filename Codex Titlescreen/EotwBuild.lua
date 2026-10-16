local mod = dmhub.GetModLoading()

--Encounter of the Week hero builder: the step engine. No UI lives here.
--
--A hero is built in six steps, in this order: Ancestry, Culture, Career,
--Class, Complication, Appearance. For each step this file can
--  * list the base options (which ancestry, which career, ...);
--  * list the step's choice rows and say which are filled (Status);
--  * write a pick (SetAncestry, Choose, ...);
--  * fill whatever is still empty with defaults or random picks (Fill).
--
--Status is always computed fresh from the character, never cached, so it
--cannot drift from what the character really holds.
--
--The rules come from the existing character builder's data layer
--(Draw Steel Character Builder: CBFeatureCache / CBFeatureWrapper and the
--synthetic Character*Choice adapters). Only its UI is not used.
--
--Two layers:
--  * hero functions (EotwBuild.hero.*) take the character properties and
--    mutate them directly. Run them inside token:ModifyProperties, or on an
--    in-memory copy for testing;
--  * token functions (EotwBuild.SetAncestry, EotwBuild.Fill, ...) take the
--    character token and wrap the hero functions in ModifyProperties.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The hero builder and hero sheet".

EotwBuild = {}

--The steps in order. `base` is the label of the step's main pick.
EotwBuild.STEPS = {
    { id = "ancestry", title = "Ancestry", base = "Ancestry" },
    { id = "culture", title = "Culture" },
    { id = "career", title = "Career", base = "Career" },
    { id = "class", title = "Class", base = "Class" },
    --every skill and language choice from the other steps, made in one
    --place (see "Skills & Languages" below)
    { id = "skills", title = "Skills & Languages" },
    { id = "complication", title = "Complication", base = "Complication" },
    { id = "appearance", title = "Appearance" },
}

--stepid -> step entry.
EotwBuild.STEP_BY_ID = {}
for _,step in ipairs(EotwBuild.STEPS) do
    EotwBuild.STEP_BY_ID[step.id] = step
end

--Hand-picked defaults Fill prefers over a random pick. An entry whose
--option is not currently offered is ignored, so a stale entry is harmless.
--  choices[choiceGuid] = { optionId, ... } in order of preference;
--  classes[classid] = { array = <index into baseCharacteristics.arrays>,
--                       kit = <kit id> }.
EotwBuild.DEFAULTS = {
    choices = {},
    classes = {},
}

--Marks a hero whose player chose to take no complication, so the step
--counts as done. Cleared when a complication is chosen.
EotwBuild.NO_COMPLICATION_FIELD = "eotwNoComplication"

--The steps whose skill and language choices the Skills & Languages step
--gathers, in the order it lists them.
EotwBuild.POOL_SOURCE_STEPS = { "ancestry", "culture", "career", "class", "complication" }

--The choice types the Skills & Languages step takes over, by kind.
local POOL_KINDS = {
    CharacterSkillChoice = "skill",
    CharacterLanguageChoice = "language",
}

--The culture's language choice stays on the Culture step: it is the
--hero's native language.
EotwBuild.NATIVE_LANGUAGE_GUID = "cultureLanguageChoice"

--Whether a choice is one the Skills & Languages step makes, and which kind.
---@param feature table
---@return string|nil kind "skill" or "language"
local function PoolKind(feature)
    local kind = POOL_KINDS[feature.typeName]
    if kind == nil or feature.guid == EotwBuild.NATIVE_LANGUAGE_GUID then
        return nil
    end
    return kind
end

--Fill picks one option at a time and rebuilds the rows after each, so
--choices revealed by a pick are filled too. This bounds that loop.
local MAX_FILL_PICKS = 60

local function Visible(tableName)
    return dmhub.GetTableVisible(tableName) or {}
end

--The placeholder portrait a new character token starts with. It does not
--count as the player having chosen a portrait.
EotwBuild.DEFAULT_PORTRAIT = "DEFAULT_MONSTER_AVATAR"

--Whether a token portrait is a real choice (not empty, not the placeholder).
---@param portrait any
---@return boolean
function EotwBuild.PortraitIsSet(portrait)
    return type(portrait) == "string" and portrait ~= "" and portrait ~= EotwBuild.DEFAULT_PORTRAIT
end

--A random element of an array, or nil when it is empty.
local function RandomOf(list)
    if #list == 0 then
        return nil
    end
    return list[math.random(1, #list)]
end

--------------------------------------------------------------------------
--Complications: only "gold" ones are offered.
--------------------------------------------------------------------------

--The automation tier of a complication: the lowest `implementation` among
--its features, skipping Narrative (0) parts, the way a monster's tier is
--worked out. An unset tier counts as 1 (Not Automated). A complication
--that is all narrative has tier 0.
---@param item CharacterComplication
---@return integer
function EotwBuild.ComplicationTier(item)
    local result = nil
    for _,feature in ipairs(item:GetClassLevel().features or {}) do
        local tier = feature:try_get("implementation", 1)
        if tier ~= 0 and (result == nil or tier < result) then
            result = tier
        end
    end
    return result or 0
end

---@param item CharacterComplication
---@return boolean
function EotwBuild.ComplicationIsGold(item)
    return EotwBuild.ComplicationTier(item) == gui.ImplementationStatus.Gold
end

---@param hero character
---@param item CharacterComplication
---@return boolean
local function ComplicationPrereqMet(hero, item)
    local prereq = item:try_get("prerequisite")
    if type(prereq) ~= "string" or trim(prereq) == "" then
        return true
    end
    return GoblinScriptTrue(ExecuteGoblinScript(prereq, hero:LookupSymbol(), 0, string.format("Complication %s prerequisite", item.name)))
end

--------------------------------------------------------------------------
--Base options: the main pick of each step.
--------------------------------------------------------------------------

local function SortedByName(t, filter)
    local result = {}
    for id,item in pairs(t) do
        if filter == nil or filter(item) then
            result[#result+1] = { id = id, name = item.name, item = item }
        end
    end
    table.sort(result, function(a,b) return a.name < b.name end)
    return result
end

--The typical (aggregate) cultures, sorted by group then name.
---@return {id: string, name: string, group: string, item: Culture}[]
function EotwBuild.CultureAggregates()
    local result = {}
    for id,item in pairs(Visible(Culture.tableName)) do
        local group = item:try_get("group")
        if group ~= nil then
            result[#result+1] = { id = id, name = item.name, group = group, item = item }
        end
    end
    table.sort(result, function(a,b)
        if a.group ~= b.group then
            return a.group < b.group
        end
        return a.name < b.name
    end)
    return result
end

--The typical culture named after an ancestry (a Dwarf's is "Dwarf"), or
--nil (a Revenant has none). Ancestries are listed as "Elf, High"; their
--cultures as "High Elf".
---@param race table|nil
---@return string|nil cultureid
function EotwBuild.AncestryCultureId(race)
    if race == nil then
        return nil
    end
    local raceName = string.lower(race.name)
    local first, rest = string.match(raceName, "^(.-),%s*(.+)$")
    if first ~= nil then
        raceName = rest .. " " .. first
    end
    for _,entry in ipairs(EotwBuild.CultureAggregates()) do
        if string.lower(entry.name) == raceName then
            return entry.id
        end
    end
    return nil
end

--Marks a culture the builder filled in from the ancestry rather than one
--the player chose. The step then reads "Optional" instead of "Done"; any
--change the player makes to the culture clears it.
EotwBuild.AUTO_CULTURE_FIELD = "eotwAutoCulture"

--The options for a step's main pick, as {id, name, item} sorted by name.
--Culture returns the typical cultures; Appearance has none.
---@param hero character
---@param stepid string
---@return {id: string, name: string, item: table}[]
function EotwBuild.BaseOptions(hero, stepid)
    if stepid == "ancestry" then
        return SortedByName(Visible(Race.tableName))
    elseif stepid == "culture" then
        return EotwBuild.CultureAggregates()
    elseif stepid == "career" then
        return SortedByName(Visible(Background.tableName))
    elseif stepid == "class" then
        return SortedByName(Visible(Class.tableName))
    elseif stepid == "complication" then
        return SortedByName(Visible(CharacterComplication.tableName), function(item)
            return EotwBuild.ComplicationIsGold(item) and ComplicationPrereqMet(hero, item)
        end)
    end
    return {}
end

--------------------------------------------------------------------------
--Reading the hero.
--------------------------------------------------------------------------

EotwBuild.hero = {}

--The hero's own culture, or nil while it still uses the type default.
---@param hero character
---@return Culture|nil
local function OwnCulture(hero)
    return hero:try_get("culture")
end

--The hero's own culture, created on first write. The type default is
--shared by every creature and must never be written to.
---@param hero character
---@return Culture
local function EnsureCulture(hero)
    local culture = OwnCulture(hero)
    if culture == nil then
        culture = Culture.CreateNew()
        hero.culture = culture
    end
    return culture
end

---@param hero character
---@return table|nil race
function EotwBuild.hero.Ancestry(hero)
    local id = hero:try_get("raceid")
    return id and Visible(Race.tableName)[id] or nil
end

---@param hero character
---@return table|nil career
function EotwBuild.hero.Career(hero)
    local id = hero:try_get("backgroundid")
    return id and Visible(Background.tableName)[id] or nil
end

---@param hero character
---@return Class|nil
function EotwBuild.hero.Class(hero)
    return hero:GetClass()
end

--The complication ids the hero holds (EotW allows at most one).
---@param hero character
---@return string[]
function EotwBuild.hero.ComplicationIds(hero)
    local result = {}
    for id,_ in pairs(hero:try_get("complications", {})) do
        result[#result+1] = id
    end
    table.sort(result)
    return result
end

---@param hero character
---@return boolean
function EotwBuild.hero.ChoseNoComplication(hero)
    return hero:try_get(EotwBuild.NO_COMPLICATION_FIELD, false) == true
end

--The feature details ({feature = ...} entries) behind a step's choice rows.
--`separate` holds choices that must get a feature cache of their own, as
--{id = <row id>, feature = ...}: the builder's characteristic and kit
--adapters both use the class id as their guid, so one cache would merge
--them into a single row.
---@param hero character
---@param stepid string
---@return table[] details
---@return {id: string, feature: CharacterChoice}[] separate
local function StepFeatureDetails(hero, stepid)
    local levelChoices = hero:GetLevelChoices() or {}
    local out = {}
    local separate = {}

    if stepid == "ancestry" then
        local race = EotwBuild.hero.Ancestry(hero)
        if race ~= nil then
            race:FillFeatureDetails(hero:CharacterLevel(), levelChoices, out)
        end

    elseif stepid == "culture" then
        --The three aspects are always rows. The language and aspect skill
        --rows come from the culture itself (the type default before any
        --pick, which still offers the language).
        for _,entry in ipairs(CharacterAspectChoice.CreateAll()) do
            out[#out+1] = entry
        end
        hero:GetCulture():FillFeatureDetails(levelChoices, out)

    elseif stepid == "career" then
        local career = EotwBuild.hero.Career(hero)
        if career ~= nil then
            career:FillFeatureDetails(levelChoices, out)
            --The inciting incident is a roll table on the career, made to
            --look like a choice by the builder's adapter.
            for _,characteristic in ipairs(career:try_get("characteristics", {})) do
                local feature = CharacterIncidentChoice.CreateNew(characteristic)
                if feature ~= nil then
                    out[#out+1] = { feature = feature, background = career }
                end
            end
        end

    elseif stepid == "class" then
        local classItem = hero:GetClass()
        if classItem ~= nil then
            separate[#separate+1] = { id = "characteristics", feature = CharacterCharacteristicChoice.CreateNew(classItem) }
            local extraLevelInfo = hero:ExtraLevelInfo()
            for i,entry in ipairs(hero:GetClassesAndSubClasses()) do
                entry.class:FillFeatureDetailsForLevel(levelChoices, entry.level, extraLevelInfo, i ~= 1, out)
            end
            local kit = CharacterKitChoice.CreateNew(hero)
            if kit ~= nil then
                separate[#separate+1] = { id = "kit", feature = kit }
            end
        end

    elseif stepid == "complication" then
        local items = Visible(CharacterComplication.tableName) --[[@as table<string, CharacterComplication>]]
        for _,id in ipairs(EotwBuild.hero.ComplicationIds(hero)) do
            local item = items[id]
            if item ~= nil then
                item:FillFeatureDetails(levelChoices, out, hero)
            end
        end
    end

    return out, separate
end

--Choices that decide which other choices exist come first, both on screen
--and when Fill picks: a Conduit's deity decides which domains (subclass
--choices) are offered, so the deity is 1, subclasses 2, the rest 3.
local PARENT_RANKS = {
    CharacterDeityChoice = 1,
    CharacterAncestryInheritanceChoice = 1,
    CharacterSubclassChoice = 2,
}

---@param wrapper CBFeatureWrapper
---@return integer
local function ParentRank(wrapper)
    return PARENT_RANKS[wrapper:GetFeature().typeName] or 3
end

--One choice row of a step: the builder's wrapper for the choice, the cache
--it came from, and the row's id (the choice guid, or "characteristics" /
--"kit" for those two class rows).
---@class EotwBuildRow
---@field wrapper CBFeatureWrapper
---@field cache CBFeatureCache
---@field id string
---@field source? string on the skills step: the step the choice comes from

--The step's choice rows in display order. Rows whose status the builder
--suppresses are left out. Parent choices come first (deity, then
--subclass), then characteristics and kit, then the rest.
--Skill and language choices belong to the Skills & Languages step: other
--steps leave them out unless includePools is set (clearing a step's picks
--needs them). The skills step lists every step's, each row tagged with
--the step it came from (row.source).
---@param hero character
---@param stepid string
---@param includePools boolean|nil
---@return EotwBuildRow[]
function EotwBuild.hero.Wrappers(hero, stepid, includePools)
    if stepid == "skills" then
        local result = {}
        for _,source in ipairs(EotwBuild.POOL_SOURCE_STEPS) do
            for _,row in ipairs(EotwBuild.hero.Wrappers(hero, source, true)) do
                if PoolKind(row.wrapper:GetFeature()) ~= nil then
                    row.source = source
                    result[#result+1] = row
                end
            end
        end
        return result
    end
    local step = EotwBuild.STEP_BY_ID[stepid]
    local title = step and step.title or stepid
    local details, separate = StepFeatureDetails(hero, stepid)

    local function Collect(cache, rowid, into)
        for _,entry in ipairs(cache:GetSortedFeatures()) do
            local wrapper = cache:GetFeature(entry.guid)
            if wrapper ~= nil and not wrapper:SuppressStatus() and (includePools or PoolKind(wrapper:GetFeature()) == nil) then
                into[#into+1] = { wrapper = wrapper, cache = cache, id = rowid or wrapper:GetGuid() }
            end
        end
    end

    local main = {}
    Collect(CBFeatureCache.CreateNew(hero, stepid, title, details), nil, main)

    local result = {}
    for rank = 1, 2 do
        for _,row in ipairs(main) do
            if ParentRank(row.wrapper) == rank then
                result[#result+1] = row
            end
        end
    end
    for _,entry in ipairs(separate) do
        Collect(CBFeatureCache.CreateNew(hero, entry.id, title, {{ feature = entry.feature }}), entry.id, result)
    end
    for _,row in ipairs(main) do
        if ParentRank(row.wrapper) == 3 then
            result[#result+1] = row
        end
    end
    return result
end

--True when an id in a choice's selected list stands for "nothing" (the
--culture adapters report an unset aspect as "").
local function IsBlankId(id)
    return id == nil or id == ""
end

--The options of a wrapper that are still free to pick: offered, not
--already picked, and affordable from what is left of a points budget.
---@param wrapper CBFeatureWrapper
---@return CBOptionWrapper[]
local function FreeChoices(wrapper)
    local remaining = wrapper:GetNumChoices() - wrapper:GetSelectedValue()
    local picked = {}
    for _,id in ipairs(wrapper:GetSelected()) do
        picked[id] = true
    end
    local result = {}
    for _,option in ipairs(wrapper:GetChoices()) do
        if not option:GetSelected() and not picked[option:GetGuid()] and option:GetPointsCost() <= remaining then
            result[#result+1] = option
        end
    end
    return result
end

--The status of one choice row.
--  complete   -- nothing more is owed (all picked, or nothing left to pick);
--  exhausted  -- complete only because no option is left to pick;
--  remaining  -- picks (or points) still owed;
--  stale      -- picked ids that are no longer offered (an earlier step
--                changed); they count as not picked.
---@param hero character
---@param row EotwBuildRow
---@return table
local function RowStatus(hero, row)
    local wrapper = row.wrapper
    local numChoices = wrapper:GetNumChoices()
    local selectedValue = wrapper:GetSelectedValue()

    local stale = {}
    local optionsKeyed = wrapper:GetOptionsKeyed()
    for _,id in ipairs(wrapper:GetSelected()) do
        if not IsBlankId(id) and optionsKeyed[id] == nil then
            stale[#stale+1] = id
        end
    end

    --An inciting incident chosen elsewhere may live only in the hero's
    --notes, not in levelChoices.
    local feature = wrapper:GetFeature()
    if feature.typeName == "CharacterIncidentChoice" and selectedValue < numChoices then
        local notes = hero:GetNotesForTable(feature.guid)
        if notes ~= nil and #notes > 0 then
            selectedValue = numChoices
        end
    end

    local remaining = math.max(0, numChoices - selectedValue)
    local exhausted = false
    if remaining > 0 and not wrapper:IsUnbounded() and #FreeChoices(wrapper) == 0 then
        exhausted = true
    end

    return {
        guid = row.id,
        name = wrapper:GetName(),
        category = wrapper:GetCategory(),
        numChoices = numChoices,
        remaining = remaining,
        selectedNames = wrapper:GetSelectedNames(),
        complete = remaining == 0 or exhausted or wrapper:IsUnbounded(),
        exhausted = exhausted,
        stale = stale,
        nested = row.cache:IsNestedFeature(wrapper:GetGuid()),
    }
end

--The base row of a step, or nil for a step without one.
---@param token table|nil the character token; Appearance needs it
---@param hero character
---@param stepid string
---@return table[] rows
local function BaseRows(token, hero, stepid)
    if stepid == "ancestry" then
        local race = EotwBuild.hero.Ancestry(hero)
        return {{ guid = "base", name = "Ancestry", base = true, complete = race ~= nil, remaining = race and 0 or 1, selectedNames = { race and race.name or nil }, stale = {} }}
    elseif stepid == "career" then
        local career = EotwBuild.hero.Career(hero)
        return {{ guid = "base", name = "Career", base = true, complete = career ~= nil, remaining = career and 0 or 1, selectedNames = { career and career.name or nil }, stale = {} }}
    elseif stepid == "class" then
        local classItem = hero:GetClass()
        return {{ guid = "base", name = "Class", base = true, complete = classItem ~= nil, remaining = classItem and 0 or 1, selectedNames = { classItem and classItem.name or nil }, stale = {} }}
    elseif stepid == "complication" then
        local ids = EotwBuild.hero.ComplicationIds(hero)
        local items = Visible(CharacterComplication.tableName) --[[@as table<string, CharacterComplication>]]
        local names = {}
        local stale = {}
        for _,id in ipairs(ids) do
            local item = items[id]
            names[#names+1] = item and item.name or id
            --Only one gold complication is allowed in EotW.
            if item == nil or not EotwBuild.ComplicationIsGold(item) or #ids > 1 then
                stale[#stale+1] = id
            end
        end
        if #ids == 0 then
            names[#names+1] = "No Complication"
        end
        --No complication is the default: the step is complete from the
        --start, so it never blocks Finish. `optional` (no complication
        --taken) tells the screen to say "Optional" rather than "Done".
        local complete = #ids == 0 or (#ids == 1 and #stale == 0)
        return {{ guid = "base", name = "Complication", base = true, complete = complete, optional = #ids == 0, remaining = complete and 0 or 1, selectedNames = names, stale = stale }}
    elseif stepid == "appearance" then
        local name = token and token.name or nil
        local portrait = token and token.portrait or nil
        local hasName = type(name) == "string" and trim(name) ~= ""
        local hasPortrait = EotwBuild.PortraitIsSet(portrait)
        return {
            { guid = "name", name = "Name", base = true, complete = hasName, remaining = hasName and 0 or 1, selectedNames = { hasName and name or nil }, stale = {} },
            { guid = "portrait", name = "Portrait", base = true, complete = hasPortrait, remaining = hasPortrait and 0 or 1, selectedNames = {}, stale = {} },
        }
    end
    return {}
end

--The status of one step:
--  { id, title, complete, filled, total, rows = {row...}, stale, optional }
--where each row is { guid, name, complete, remaining, selectedNames, stale,
--base?, nested?, exhausted? }. `filled`/`total` count rows. A step is
--complete when every row is.
---@param token table|nil the character token (only Appearance reads it)
---@param hero character
---@param stepid string
---@return table
function EotwBuild.hero.StepStatus(token, hero, stepid)
    local step = EotwBuild.STEP_BY_ID[stepid]
    local rows = BaseRows(token, hero, stepid)

    for _,row in ipairs(EotwBuild.hero.Wrappers(hero, stepid)) do
        rows[#rows+1] = RowStatus(hero, row)
    end

    local filled = 0
    local stale = false
    for _,row in ipairs(rows) do
        if row.complete then
            filled = filled + 1
        end
        if #row.stale > 0 then
            stale = true
        end
    end

    local result = {
        id = stepid,
        title = step and step.title or stepid,
        rows = rows,
        filled = filled,
        total = #rows,
        complete = filled == #rows,
        stale = stale,
        --an optional step the player has not touched (Complication)
        optional = rows[1] ~= nil and rows[1].optional == true,
    }
    if stepid == "culture" then
        result.optional = result.complete and hero:try_get(EotwBuild.AUTO_CULTURE_FIELD, false) == true
    end

    return result
end

--------------------------------------------------------------------------
--Writing the hero. Every function here mutates hero directly; the token
--functions further down run them inside ModifyProperties.
--------------------------------------------------------------------------

--Remove every pick a step's rows hold: used before the step's main pick
--changes, so the old ancestry's (or class's, ...) picks do not linger.
---@param hero character
---@param stepid string
function EotwBuild.hero.ClearStepChoices(hero, stepid)
    local levelChoices = hero:GetLevelChoices() or {}
    for _,row in ipairs(EotwBuild.hero.Wrappers(hero, stepid, true)) do
        local wrapper = row.wrapper
        local feature = wrapper:GetFeature()
        local guid = wrapper:GetGuid()
        if feature.typeName == "CharacterIncidentChoice" then
            hero:RemoveNotesForTable(guid)
        end
        levelChoices[guid] = nil
    end

    if stepid == "class" then
        hero.kitid = nil
        hero.kitid2 = nil
        hero.attributeBuild = {}
        levelChoices["kitBonusChoices"] = nil
        levelChoices["companionBonusChoices"] = nil
        for _,attrid in ipairs(creature.attributeIds) do
            hero:GetBaseAttribute(attrid).baseValue = 0
        end
    elseif stepid == "culture" then
        local culture = OwnCulture(hero)
        if culture ~= nil then
            for k,_ in pairs(culture.aspects) do
                culture.aspects[k] = ""
            end
            culture.aggregate = ""
        end
        levelChoices.cultureLanguageChoice = nil
    end
end

--Whether a step holds any picks beyond its main pick (what the UI asks to
--confirm before changing that main pick).
---@param hero character
---@param stepid string
---@return boolean
function EotwBuild.hero.HasDependentPicks(hero, stepid)
    for _,row in ipairs(EotwBuild.hero.Wrappers(hero, stepid, true)) do
        for _,id in ipairs(row.wrapper:GetSelected()) do
            if not IsBlankId(id) then
                return true
            end
        end
    end
    return false
end

--Set the ancestry. If the player has not made the culture their own, the
--culture follows: it becomes the new ancestry's own culture (flagged as
--automatic), or is cleared when the ancestry has none.
---@param hero character
---@param raceid string
function EotwBuild.hero.SetAncestry(hero, raceid)
    if hero:try_get("raceid") == raceid then
        return
    end
    EotwBuild.hero.ClearStepChoices(hero, "ancestry")
    hero.raceid = raceid
    hero.subraceid = nil
    hero:Invalidate()

    local culture = hero:try_get("culture")
    local untouched = true
    if culture ~= nil then
        for _,v in pairs(culture.aspects) do
            if v ~= "" then
                untouched = false
            end
        end
    end
    local auto = hero:try_get(EotwBuild.AUTO_CULTURE_FIELD, false) == true
    if untouched or auto then
        local cultureid = EotwBuild.AncestryCultureId(EotwBuild.hero.Ancestry(hero))
        if cultureid ~= nil then
            EotwBuild.hero.SetCultureAggregate(hero, cultureid, true)
        elseif auto then
            EotwBuild.hero.ClearStepChoices(hero, "culture")
            hero[EotwBuild.AUTO_CULTURE_FIELD] = false
            hero:Invalidate()
        end
    end
end

---@param hero character
---@param careerid string
function EotwBuild.hero.SetCareer(hero, careerid)
    if hero:try_get("backgroundid") == careerid then
        return
    end
    EotwBuild.hero.ClearStepChoices(hero, "career")
    hero.backgroundid = careerid
    hero:Invalidate()
end

--Set the class at level 1 (EotW heroes start at level 1; level-up is not
--built yet). Clears the old class's picks, kit and characteristics.
---@param hero character
---@param classid string
function EotwBuild.hero.SetClass(hero, classid)
    local current = hero:GetClass()
    if current ~= nil and current.id == classid then
        return
    end
    EotwBuild.hero.ClearStepChoices(hero, "class")
    hero.classes = { { classid = classid, level = 1 } }
    local classItem = Visible(Class.tableName)[classid] --[[@as Class|nil]]
    if classItem ~= nil then
        --Locked characteristics (e.g. a Fury's Might) apply straight away.
        classItem:CalculateBaseAttributes(hero)
    end
    hero:Invalidate()
end

--Take a typical culture: its three aspects and its language. auto = the
--builder chose it (from the ancestry), not the player.
---@param hero character
---@param cultureid string
---@param auto boolean|nil
function EotwBuild.hero.SetCultureAggregate(hero, cultureid, auto)
    local item = Visible(Culture.tableName)[cultureid] --[[@as Culture|nil]]
    if item == nil then
        return
    end
    hero[EotwBuild.AUTO_CULTURE_FIELD] = auto == true
    EotwBuild.hero.ClearStepChoices(hero, "culture")
    local culture = EnsureCulture(hero)
    culture.aspects = DeepCopy(item.aspects)
    culture.aggregate = cultureid
    local languageid = item:try_get("languageid")
    if type(languageid) == "string" and languageid ~= "" then
        local levelChoices = hero:GetLevelChoices()
        levelChoices.cultureLanguageChoice = { languageid }
    end
    hero:Invalidate()
end

--Set (or, with "", clear) one culture aspect. The aspect's old picks go.
--Setting an aspect by hand means the culture is no longer a typical one.
---@param hero character
---@param category string environment / organization / upbringing
---@param aspectid string
function EotwBuild.hero.SetCultureAspect(hero, category, aspectid)
    hero[EotwBuild.AUTO_CULTURE_FIELD] = false
    local culture = EnsureCulture(hero)
    if culture.aspects[category] == aspectid then
        return
    end
    local oldid = culture.aspects[category]
    if type(oldid) == "string" and oldid ~= "" then
        --Drop the picks the old aspect's features hold.
        local old = Visible(CultureAspect.tableName)[oldid] --[[@as CultureAspect|nil]]
        if old ~= nil then
            local levelChoices = hero:GetLevelChoices() or {}
            local details = {}
            old:FillFeatureDetails(levelChoices, details)
            for _,entry in ipairs(details) do
                local feature = entry.feature
                if feature ~= nil and feature.IsDerivedFrom("CharacterChoice") then
                    levelChoices[feature.guid] = nil
                end
            end
        end
    end
    culture.aspects[category] = aspectid
    culture.aggregate = ""
    hero:Invalidate()
end

--Set the hero's one complication, or none at all (complicationid nil).
--Choosing none is a real choice and completes the step.
---@param hero character
---@param complicationid string|nil
function EotwBuild.hero.SetComplication(hero, complicationid)
    local ids = EotwBuild.hero.ComplicationIds(hero)
    local unchanged = (complicationid == nil and #ids == 0) or (#ids == 1 and ids[1] == complicationid)
    if not unchanged then
        EotwBuild.hero.ClearStepChoices(hero, "complication")
        hero.complications = {}
        if complicationid ~= nil then
            hero.complications[complicationid] = true
        end
    end
    hero[EotwBuild.NO_COMPLICATION_FIELD] = (complicationid == nil)
    hero:Invalidate()
end

--Undo the complication step entirely: no complication and no "none" pick.
---@param hero character
function EotwBuild.hero.ClearComplication(hero)
    EotwBuild.hero.ClearStepChoices(hero, "complication")
    hero.complications = {}
    hero[EotwBuild.NO_COMPLICATION_FIELD] = false
    hero:Invalidate()
end

--Take characteristic array `arrayIndex` of the hero's class. `build` maps
--each unlocked characteristic id to its slot in the array; without it the
--slots go in attribute order, highest value first.
---@param hero character
---@param arrayIndex integer
---@param build table<string, integer>|nil
function EotwBuild.hero.SetCharacteristics(hero, arrayIndex, build)
    local classItem = hero:GetClass()
    if classItem == nil then
        return
    end
    local baseChars = classItem.baseCharacteristics
    local array = baseChars.arrays[arrayIndex]
    if array == nil then
        return
    end

    --Slot indexes sorted so the highest value goes first.
    local slots = {}
    for i = 1, #array do
        slots[i] = i
    end
    table.sort(slots, function(a,b)
        if array[a] ~= array[b] then
            return array[a] > array[b]
        end
        return a < b
    end)

    local attributeBuild = { array = arrayIndex }
    local nextSlot = 1
    for _,attrid in ipairs(creature.attributeIds) do
        if baseChars[attrid] == nil then
            if build ~= nil and build[attrid] ~= nil then
                attributeBuild[attrid] = build[attrid]
            else
                attributeBuild[attrid] = slots[nextSlot]
                nextSlot = nextSlot + 1
            end
        end
    end
    hero.attributeBuild = attributeBuild
    classItem:CalculateBaseAttributes(hero)
    hero:Invalidate()
end

--The wrapper for one row of a step (by row id), or nil.
---@param hero character
---@param stepid string
---@param rowid string
---@return CBFeatureWrapper|nil
local function FindWrapper(hero, stepid, rowid)
    for _,row in ipairs(EotwBuild.hero.Wrappers(hero, stepid)) do
        if row.id == rowid then
            return row.wrapper
        end
    end
    return nil
end

---@param wrapper CBFeatureWrapper
---@param optionId string
---@return CBOptionWrapper|nil
local function FindOption(wrapper, optionId)
    local option = wrapper:GetChoice(optionId)
    if option ~= nil then
        return option
    end
    return wrapper:GetOption(optionId)
end

--Pick one option in a choice row (rows are named by the row id that
--Status reports). A row that takes a single pick swaps its current pick
--for this one. Prefer SetCharacteristics for the characteristics row: its
--option ids are regenerated on every rebuild, so an id from an older
--Status may no longer match.
---@param hero character
---@param stepid string
---@param rowid string
---@param optionId string
---@return boolean saved
function EotwBuild.hero.Choose(hero, stepid, rowid, optionId)
    if stepid == "culture" then
        hero[EotwBuild.AUTO_CULTURE_FIELD] = false
    end
    local wrapper = FindWrapper(hero, stepid, rowid)
    if wrapper == nil then
        return false
    end
    local feature = wrapper:GetFeature()
    if feature.typeName == "CharacterAspectChoice" then
        EotwBuild.hero.SetCultureAspect(hero, wrapper:GetGuid(), optionId)
        return true
    end
    local option = FindOption(wrapper, optionId)
    if option == nil then
        return false
    end
    if feature.typeName == "CharacterCharacteristicChoice" then
        EotwBuild.hero.SetCharacteristics(hero, option:GetOption().arrayIndex, nil)
        return true
    end

    --A one-pick row: drop the old pick first so its own sub-choices go too.
    if wrapper:GetNumChoices() == 1 then
        for _,id in ipairs(wrapper:GetSelected()) do
            if not IsBlankId(id) and id ~= optionId then
                EotwBuild.hero.Unchoose(hero, stepid, rowid, id)
            end
        end
        wrapper = FindWrapper(hero, stepid, rowid)
        if wrapper == nil then
            return false
        end
        option = FindOption(wrapper, optionId)
        if option == nil then
            return false
        end
    end

    wrapper:SaveSelection(hero, option)
    hero:Invalidate()
    return true
end

--One choice row's options, for display:
--  options = { {id, name, selected, available, cost, option}... } where
--    available -- it can be picked now (offered, not taken by another row,
--                 affordable); a selected option is always shown,
--    option    -- the builder's CBOptionWrapper (GetDescription, Panel);
--  info = { name, description, numChoices, remaining, costsPoints,
--           pointsName, typeName }.
--Returns nil when the row does not exist.
---@param hero character
---@param stepid string
---@param rowid string
---@return table[]|nil options
---@return table|nil info
function EotwBuild.hero.RowOptions(hero, stepid, rowid)
    local wrapper = FindWrapper(hero, stepid, rowid)
    if wrapper == nil then
        return nil, nil
    end
    local selected = {}
    for _,id in ipairs(wrapper:GetSelected()) do
        if not IsBlankId(id) then
            selected[id] = true
        end
    end
    local free = {}
    for _,option in ipairs(FreeChoices(wrapper)) do
        free[option:GetGuid()] = true
    end
    --a one-pick row swaps its pick (Choose does that), so any option it
    --still offers is available even with the pick spent.
    if wrapper:GetNumChoices() == 1 then
        for id,_ in pairs(wrapper:GetChoicesKeyed()) do
            free[id] = true
        end
    end
    local result = {}
    for _,option in ipairs(wrapper:GetOptions()) do
        local id = option:GetGuid()
        local hidden = false
        pcall(function() hidden = option:GetOption().hidden == true end)
        if selected[id] or not hidden then
            result[#result+1] = {
                id = id,
                name = option:GetName(),
                selected = selected[id] == true,
                available = selected[id] == true or free[id] == true,
                cost = option:GetPointsCost(),
                option = option,
            }
        end
    end
    local feature = wrapper:GetFeature()
    local description = nil
    pcall(function() description = wrapper:GetDescription() end)
    return result, {
        name = wrapper:GetName(),
        description = description,
        numChoices = wrapper:GetNumChoices(),
        remaining = math.max(0, wrapper:GetNumChoices() - wrapper:GetSelectedValue()),
        costsPoints = wrapper:CostsPoints(),
        pointsName = wrapper:GetPointsName(),
        typeName = feature.typeName,
    }
end

--Remove one pick from a choice row, including an id that is no longer
--offered (a stale pick).
---@param hero character
---@param stepid string
---@param rowid string
---@param optionId string
function EotwBuild.hero.Unchoose(hero, stepid, rowid, optionId)
    if stepid == "culture" then
        hero[EotwBuild.AUTO_CULTURE_FIELD] = false
    end
    local wrapper = FindWrapper(hero, stepid, rowid)
    if wrapper == nil then
        return
    end
    local feature = wrapper:GetFeature()
    local choiceGuid = wrapper:GetGuid()
    if feature.typeName == "CharacterAspectChoice" then
        EotwBuild.hero.SetCultureAspect(hero, choiceGuid, "")
        return
    end

    local option = FindOption(wrapper, optionId)
    if option ~= nil then
        wrapper:RemoveSelection(hero, option)
    else
        --Stale: the option is gone, so remove the raw id. Adapters that
        --store picks outside levelChoices take a stand-in option.
        local stub = { guid = optionId, id = optionId }
        local removed = false
        local removeFn = CharacterBuilder._hasFn(feature, "RemoveSelection")
        if removeFn ~= nil then
            removed = removeFn(feature, hero, stub) == true
        end
        if not removed then
            local levelChoices = hero:GetLevelChoices() or {}
            local list = levelChoices[choiceGuid]
            if list ~= nil then
                for i = #list, 1, -1 do
                    if list[i] == optionId then
                        table.remove(list, i)
                    end
                end
            end
        end
    end
    hero:Invalidate()
end

--------------------------------------------------------------------------
--Fill: complete a step with defaults and random picks.
--------------------------------------------------------------------------

--The preferred option among `pool`, from EotwBuild.DEFAULTS, else nil.
---@param choiceGuid string
---@param pool CBOptionWrapper[]
---@return CBOptionWrapper|nil
local function PreferredOption(choiceGuid, pool)
    local preferred = EotwBuild.DEFAULTS.choices[choiceGuid]
    if preferred == nil then
        return nil
    end
    for _,id in ipairs(preferred) do
        for _,option in ipairs(pool) do
            if option:GetGuid() == id then
                return option
            end
        end
    end
    return nil
end

--The culture Fill takes: one named after the hero's ancestry (a Dwarf
--gets the Dwarf culture), otherwise a random typical culture.
---@param hero character
---@return string|nil cultureid
local function DefaultCulture(hero)
    local cultureid = EotwBuild.AncestryCultureId(EotwBuild.hero.Ancestry(hero))
    if cultureid ~= nil then
        return cultureid
    end
    local entry = RandomOf(EotwBuild.CultureAggregates())
    return entry and entry.id or nil
end

--Make the step's main pick if it is missing. Returns a description of
--what was picked, or nil.
---@param hero character
---@param stepid string
---@return string|nil
local function FillBase(hero, stepid)
    if stepid == "ancestry" and EotwBuild.hero.Ancestry(hero) == nil then
        local entry = RandomOf(EotwBuild.BaseOptions(hero, "ancestry"))
        if entry ~= nil then
            EotwBuild.hero.SetAncestry(hero, entry.id)
            return "Ancestry -> " .. entry.name
        end
    elseif stepid == "culture" then
        local culture = OwnCulture(hero)
        local anySet = false
        if culture ~= nil then
            for _,v in pairs(culture.aspects) do
                if v ~= "" then
                    anySet = true
                end
            end
        end
        --A culture the player started by hand is finished row by row instead.
        if not anySet then
            local cultureid = DefaultCulture(hero)
            if cultureid ~= nil then
                EotwBuild.hero.SetCultureAggregate(hero, cultureid)
                local item = Visible(Culture.tableName)[cultureid]
                return "Culture -> " .. (item and item.name or cultureid)
            end
        end
    elseif stepid == "career" and EotwBuild.hero.Career(hero) == nil then
        local entry = RandomOf(EotwBuild.BaseOptions(hero, "career"))
        if entry ~= nil then
            EotwBuild.hero.SetCareer(hero, entry.id)
            return "Career -> " .. entry.name
        end
    elseif stepid == "class" and hero:GetClass() == nil then
        local entry = RandomOf(EotwBuild.BaseOptions(hero, "class"))
        if entry ~= nil then
            EotwBuild.hero.SetClass(hero, entry.id)
            return "Class -> " .. entry.name
        end
    elseif stepid == "complication" then
        --Fill never adds a complication (each has a drawback); it settles
        --on none unless the player already chose one.
        if #EotwBuild.hero.ComplicationIds(hero) == 0 and not EotwBuild.hero.ChoseNoComplication(hero) then
            EotwBuild.hero.SetComplication(hero, nil)
            return "Complication -> none"
        end
    end
    return nil
end

--Fill one row of a step with one pick. Returns a description, or nil when
--nothing could be picked.
---@param hero character
---@param wrapper CBFeatureWrapper
---@return string|nil
local function FillOnePick(hero, wrapper)
    local feature = wrapper:GetFeature()

    --Characteristics: the class's default array, else a random one.
    if feature.typeName == "CharacterCharacteristicChoice" then
        local classItem = hero:GetClass()
        if classItem == nil then
            return nil
        end
        local arrays = classItem.baseCharacteristics.arrays or {}
        if #arrays == 0 then
            return nil
        end
        local defaults = EotwBuild.DEFAULTS.classes[classItem.id] or {}
        local index = defaults.array
        if index == nil or arrays[index] == nil then
            index = math.random(1, #arrays)
        end
        EotwBuild.hero.SetCharacteristics(hero, index, nil)
        return string.format("Characteristics -> array %d", index)
    end

    local pool = FreeChoices(wrapper)
    if #pool == 0 then
        return nil
    end

    local option = PreferredOption(wrapper:GetGuid(), pool)
    if option == nil and feature.typeName == "CharacterKitChoice" then
        local classItem = hero:GetClass()
        local defaults = classItem and EotwBuild.DEFAULTS.classes[classItem.id] or {}
        if defaults.kit ~= nil then
            for _,candidate in ipairs(pool) do
                if candidate:GetGuid() == defaults.kit then
                    option = candidate
                end
            end
        end
    end
    if option == nil then
        option = RandomOf(pool)
    end
    if option == nil then
        return nil
    end

    if feature.typeName == "CharacterAspectChoice" then
        EotwBuild.hero.SetCultureAspect(hero, wrapper:GetGuid(), option:GetGuid())
    else
        wrapper:SaveSelection(hero, option)
        hero:Invalidate()
    end
    return string.format("%s -> %s", wrapper:GetName() or "?", option:GetName())
end

--The rows in the order Fill visits them: parent choices first (see
--ParentRank), then the rest in display order.
---@param rows EotwBuildRow[]
---@return EotwBuildRow[]
local function FillOrder(rows)
    local result = {}
    for rank = 1, 3 do
        for _,row in ipairs(rows) do
            if ParentRank(row.wrapper) == rank then
                result[#result+1] = row
            end
        end
    end
    return result
end

--Fill every empty pick of one step and leave the player's picks alone.
--Stale picks (no longer offered) are removed first. Returns the list of
--picks made, as "Row -> Option" strings.
---@param hero character
---@param stepid string
---@return string[]
function EotwBuild.hero.Fill(hero, stepid)
    if stepid == "skills" then
        local picks = EotwBuild.hero.FillPools(hero, "skill")
        for _,pick in ipairs(EotwBuild.hero.FillPools(hero, "language")) do
            picks[#picks+1] = pick
        end
        return picks
    end
    local picks = {}

    local basePick = FillBase(hero, stepid)
    if basePick ~= nil then
        picks[#picks+1] = basePick
    end

    --Remove stale picks so their rows can be filled again.
    for _,row in ipairs(EotwBuild.hero.Wrappers(hero, stepid)) do
        local wrapper = row.wrapper
        local optionsKeyed = wrapper:GetOptionsKeyed()
        for _,id in ipairs(wrapper:GetSelected()) do
            if not IsBlankId(id) and optionsKeyed[id] == nil then
                EotwBuild.hero.Unchoose(hero, stepid, row.id, id)
                picks[#picks+1] = string.format("%s -> removed a pick no longer offered", wrapper:GetName() or "?")
            end
        end
    end

    --One pick at a time, rebuilding the rows after each, so a pick that
    --reveals new choices (a subclass, an ability with options) gets those
    --filled too. A row that refuses a pick is not tried again.
    local stuck = {}
    for _ = 1, MAX_FILL_PICKS do
        local picked = false
        for _,row in ipairs(FillOrder(EotwBuild.hero.Wrappers(hero, stepid))) do
            local rowid = row.id
            if not stuck[rowid] and not RowStatus(hero, row).complete then
                local before = row.wrapper:GetSelectedValue()
                local description = FillOnePick(hero, row.wrapper)
                --Progress means the row gained a pick, or went away.
                local after = FindWrapper(hero, stepid, rowid)
                if description ~= nil and (after == nil or after:GetSelectedValue() > before) then
                    picks[#picks+1] = description
                    picked = true
                    break
                end
                stuck[rowid] = true
            end
        end
        if not picked then
            break
        end
    end

    return picks
end

--------------------------------------------------------------------------
--Skills & Languages: every skill (or language) choice from every step is a
--"pool" -- a number of picks, each from an allowed set. The player picks
--skills, not pools: a matching (augmenting paths, as in bipartite
--matching) decides which pool each pick fills, so a pick that fits two
--pools never blocks a later one that only fits one of them. A skill is
--offered when the picks so far plus that skill can still all be placed.
--------------------------------------------------------------------------

--The pools of one kind: { {rowid, guid, source, name, description,
--capacity, allowed = {id = true}, selected = {id...}, wrapper}... }
---@param hero character
---@param kind string "skill" or "language"
---@return table[]
function EotwBuild.hero.Pools(hero, kind)
    local visibleSkills = kind == "skill" and (Skill.SkillsById or {}) or nil
    local pools = {}
    for _,row in ipairs(EotwBuild.hero.Wrappers(hero, "skills")) do
        local wrapper = row.wrapper
        if PoolKind(wrapper:GetFeature()) == kind then
            local allowed = {}
            for _,option in ipairs(wrapper:GetOptions()) do
                local id = option:GetGuid()
                if visibleSkills == nil or visibleSkills[id] ~= nil then
                    allowed[id] = true
                end
            end
            local selected = {}
            for _,id in ipairs(wrapper:GetSelected()) do
                if not IsBlankId(id) then
                    selected[#selected+1] = id
                end
            end
            local description = nil
            pcall(function() description = wrapper:GetDescription() end)
            pools[#pools+1] = {
                rowid = row.id,
                guid = wrapper:GetGuid(),
                source = row.source,
                name = wrapper:GetName(),
                description = description,
                capacity = wrapper:GetNumChoices(),
                allowed = allowed,
                selected = selected,
                wrapper = wrapper,
            }
        end
    end
    return pools
end

--Place every item in a pool slot, or return nil when they cannot all fit.
--`prefer` maps an item to the pool it is in now, tried first, so adding a
--pick moves as few existing picks as possible.
--Returns { item = poolIndex }.
---@param pools table[]
---@param items string[]
---@param prefer table<string, integer>|nil
---@return table<string, integer>|nil
local function MatchPools(pools, items, prefer)
    local slotPool = {}
    for i,pool in ipairs(pools) do
        for _ = 1, pool.capacity do
            slotPool[#slotPool+1] = i
        end
    end
    local slotItem = {}
    local Place
    Place = function(id, visited)
        local candidates = {}
        for slot,poolIndex in ipairs(slotPool) do
            if pools[poolIndex].allowed[id] then
                candidates[#candidates+1] = slot
            end
        end
        local preferred = prefer and prefer[id] or nil
        table.sort(candidates, function(a, b)
            local pa = slotPool[a] == preferred
            local pb = slotPool[b] == preferred
            if pa ~= pb then
                return pa
            end
            return a < b
        end)
        for _,slot in ipairs(candidates) do
            if not visited[slot] then
                visited[slot] = true
                if slotItem[slot] == nil or Place(slotItem[slot], visited) then
                    slotItem[slot] = id
                    return true
                end
            end
        end
        return false
    end
    for _,id in ipairs(items) do
        if not Place(id, {}) then
            return nil
        end
    end
    local assignment = {}
    for slot,id in pairs(slotItem) do
        assignment[id] = slotPool[slot]
    end
    return assignment
end

--Everything picked across the pools, in pool order, and where each is now.
local function CurrentPicks(pools)
    local items = {}
    local prefer = {}
    for i,pool in ipairs(pools) do
        for _,id in ipairs(pool.selected) do
            if pool.allowed[id] and prefer[id] == nil then
                items[#items+1] = id
                prefer[id] = i
            end
        end
    end
    return items, prefer
end

--What the hero knows of a kind WITHOUT these pools' picks: the fixed
--grants (proficiency modifiers whose source is not one of the pools), and
--for languages the native one (the culture's choice) and innate ones.
--Returns { id = "fixed" | "native" }.
---@param hero character
---@param kind string
---@param pools table[]
---@return table<string, string>
local function FixedKnown(hero, kind, pools)
    local poolGuids = {}
    for _,pool in ipairs(pools) do
        poolGuids[pool.guid] = true
    end
    local result = {}
    if kind == "language" then
        local native = (hero:GetLevelChoices() or {})[EotwBuild.NATIVE_LANGUAGE_GUID]
        for _,id in ipairs(native or {}) do
            if not IsBlankId(id) then
                result[id] = "native"
            end
        end
        for id,_ in pairs(hero:try_get("innateLanguages", {})) do
            result[id] = result[id] or "fixed"
        end
    end
    local all = kind == "skill" and (Skill.SkillsById or {}) or (dmhub.GetTableVisible(Language.tableName) or {})
    for _,entry in ipairs(hero:GetActiveModifiers()) do
        local mod = entry.mod
        local ok, behavior = pcall(function() return mod.behavior end)
        if ok and behavior == "proficiency" then
            local subtype = mod:try_get("subtype")
            local source = mod:try_get("sourceguid")
            if subtype == kind and (source == nil or not poolGuids[source]) and source ~= EotwBuild.NATIVE_LANGUAGE_GUID then
                local ids = mod:try_get("skills", {})
                if ids.all then
                    for id,_ in pairs(all) do
                        result[id] = result[id] or "fixed"
                    end
                else
                    for id,on in pairs(ids) do
                        if on then
                            result[id] = result[id] or "fixed"
                        end
                    end
                end
            end
        end
    end
    return result
end

--Skills the hero's abilities single out (an edge, a +2, ...): active
--"power" modifiers that name skills. Returns { skillid = {name...} }.
---@param hero character
---@return table<string, string[]>
local function SkillBenefits(hero)
    local result = {}
    for _,entry in ipairs(hero:GetActiveModifiers()) do
        local mod = entry.mod
        local ok, behavior = pcall(function() return mod.behavior end)
        if ok and behavior == "power" then
            local skills = mod:try_get("skills")
            if type(skills) == "table" then
                local name = mod:try_get("name") or "A special ability"
                for k,v in pairs(skills) do
                    --an array of ids here, but tolerate a set
                    local id = cond(type(k) == "number", v, k)
                    if type(id) == "string" then
                        local list = result[id] or {}
                        list[#list+1] = name
                        result[id] = list
                    end
                end
            end
        end
    end
    return result
end

--Where each outright-granted skill or language comes from, as a phrase:
--"your career (Agent)". { id = phrase }.
---@param hero character
---@return table<string, string>
local function GrantSources(hero)
    local function ItemName(stepid)
        local item = nil
        if stepid == "ancestry" then
            item = EotwBuild.hero.Ancestry(hero)
        elseif stepid == "career" then
            item = EotwBuild.hero.Career(hero)
        elseif stepid == "class" then
            item = hero:GetClass()
        elseif stepid == "complication" then
            local ids = EotwBuild.hero.ComplicationIds(hero)
            item = ids[1] and Visible(CharacterComplication.tableName)[ids[1]] or nil
        elseif stepid == "culture" then
            local culture = hero:try_get("culture")
            local aggregate = culture and culture:try_get("aggregate") or nil
            item = aggregate and aggregate ~= "" and Visible(Culture.tableName)[aggregate] or nil
        end
        return item and item.name or nil
    end
    local result = {}
    for _,stepid in ipairs(EotwBuild.POOL_SOURCE_STEPS) do
        local grants = EotwBuild.hero.StepGrants(hero, stepid)
        local name = ItemName(stepid)
        local phrase = string.format("your %s", string.lower(EotwBuild.STEP_BY_ID[stepid].title))
        if name ~= nil then
            phrase = string.format("%s (%s)", phrase, name)
        end
        for id,_ in pairs(grants.fixedIds) do
            result[id] = result[id] or phrase
        end
    end
    return result
end

--Write a set of picks into the pools: match them (keeping each pick where
--it is when it can stay), then store each pool's share as its picks.
--Returns false when the picks cannot all be placed.
---@param hero character
---@param kind string
---@param items string[]
---@return boolean
function EotwBuild.hero.SetPoolPicks(hero, kind, items)
    local pools = EotwBuild.hero.Pools(hero, kind)
    local _, prefer = CurrentPicks(pools)
    local assignment = MatchPools(pools, items, prefer)
    if assignment == nil then
        return false
    end
    local levelChoices = hero:GetLevelChoices()
    local byPool = {}
    for _,id in ipairs(items) do
        local poolIndex = assignment[id]
        local list = byPool[poolIndex] or {}
        list[#list+1] = id
        byPool[poolIndex] = list
    end
    for i,pool in ipairs(pools) do
        levelChoices[pool.guid] = byPool[i] or {}
    end
    hero:Invalidate()
    return true
end

--The whole Skills & Languages picture for one kind, for the screen:
--  { pools = {pool + remaining}, entries = {entry...}, native = id|nil }
--entry = { id, name, category, description, state, source, dead, speakers, special, pools }
--  state: "native" | "fixed" | "selected" | "selectable" | "unavailable"
--  special: names of abilities that single the skill out (skills only)
--  pools: names of the pools it could fill
---@param hero character
---@param kind string
---@return table
function EotwBuild.hero.PoolTable(hero, kind)
    local pools = EotwBuild.hero.Pools(hero, kind)
    local items, prefer = CurrentPicks(pools)
    local picked = {}
    for _,id in ipairs(items) do
        picked[id] = true
    end
    local fixed = FixedKnown(hero, kind, pools)
    local sources = GrantSources(hero)
    local benefits = kind == "skill" and SkillBenefits(hero) or {}

    --each pool's remaining count under the current placement
    local assignment = MatchPools(pools, items, prefer) or {}
    local used = {}
    for _,poolIndex in pairs(assignment) do
        used[poolIndex] = (used[poolIndex] or 0) + 1
    end
    for i,pool in ipairs(pools) do
        pool.remaining = math.max(0, pool.capacity - (used[i] or 0))
    end

    --{id, item} for every skill or language, sorted by name
    local source = {}
    if kind == "skill" then
        for _,item in ipairs(Skill.SkillsInfo or {}) do
            source[#source+1] = { id = item.id, item = item }
        end
    else
        for id,item in pairs(dmhub.GetTableVisible(Language.tableName) or {}) do
            source[#source+1] = { id = id, item = item }
        end
        table.sort(source, function(a, b) return a.item.name < b.item.name end)
    end

    local entries = {}
    local native = nil
    for _,row in ipairs(source) do
        local id = row.id
        local item = row.item
        local state
        if fixed[id] == "native" then
            state = "native"
            native = id
        elseif fixed[id] ~= nil then
            state = "fixed"
        elseif picked[id] then
            state = "selected"
        else
            local trial = {}
            for _,other in ipairs(items) do
                trial[#trial+1] = other
            end
            trial[#trial+1] = id
            if MatchPools(pools, trial, prefer) ~= nil then
                state = "selectable"
            else
                state = "unavailable"
            end
        end
        local poolNames = {}
        for _,pool in ipairs(pools) do
            if pool.allowed[id] then
                poolNames[#poolNames+1] = pool.name
            end
        end
        local description = nil
        pcall(function() description = item:try_get("description") end)
        local speakers = kind == "language" and item:try_get("speakers") or nil
        if type(speakers) ~= "string" or speakers == "" then
            speakers = nil
        end
        local source = nil
        if state == "native" then
            source = "your culture"
        elseif state == "fixed" then
            source = sources[id]
        end
        entries[#entries+1] = {
            id = id,
            name = item.name,
            category = item:try_get("category"),
            description = description,
            state = state,
            --for a native or fixed one: where it comes from, or nil
            source = source,
            --a dead language: read, not spoken
            dead = kind == "language" and item:try_get("dead", false) == true,
            --a language: who speaks it (e.g. "Goblins, Radenwights"), or nil
            speakers = speakers,
            special = benefits[id],
            pools = poolNames,
        }
    end
    return { pools = pools, entries = entries, native = native }
end

--Pick or unpick one skill (or language). A pick that cannot be placed in
--any pool alongside the others is refused. Returns whether anything changed.
---@param hero character
---@param kind string
---@param id string
---@return boolean
function EotwBuild.hero.TogglePoolPick(hero, kind, id)
    local pools = EotwBuild.hero.Pools(hero, kind)
    local items = CurrentPicks(pools)
    local result = {}
    local had = false
    for _,other in ipairs(items) do
        if other == id then
            had = true
        else
            result[#result+1] = other
        end
    end
    if not had then
        result[#result+1] = id
    end
    return EotwBuild.hero.SetPoolPicks(hero, kind, result)
end

--Fill every pool of a kind: add random offerable picks until no pool has
--room or nothing more fits. Returns "Name" strings for the picks made.
---@param hero character
---@param kind string
---@return string[]
function EotwBuild.hero.FillPools(hero, kind)
    local picks = {}
    for _ = 1, MAX_FILL_PICKS do
        local view = EotwBuild.hero.PoolTable(hero, kind)
        local room = false
        for _,pool in ipairs(view.pools) do
            if pool.remaining > 0 then
                room = true
            end
        end
        if not room then
            break
        end
        local candidates = {}
        for _,entry in ipairs(view.entries) do
            if entry.state == "selectable" then
                candidates[#candidates+1] = entry
            end
        end
        local entry = RandomOf(candidates)
        if entry == nil then
            break
        end
        EotwBuild.hero.TogglePoolPick(hero, kind, entry.id)
        picks[#picks+1] = string.format("%s -> %s", cond(kind == "skill", "Skill", "Language"), entry.name)
    end
    return picks
end

--What a step grants in skills and languages, for the info box on its page:
--  { fixed = {"Sneak (skill)"...}, pools = {{name, description, kind}...} }
--fixed = granted outright; pools = choices made on the Skills & Languages
--step. The culture's native language is a row of its own and not listed.
---@param hero character
---@param stepid string
---@return table
function EotwBuild.hero.StepGrants(hero, stepid)
    --fixedIds: id -> true for each skill/language granted outright
    local result = { fixed = {}, fixedIds = {}, pools = {} }
    local details = StepFeatureDetails(hero, stepid)
    local choiceGuids = {}
    for _,entry in ipairs(details) do
        local feature = entry.feature
        if feature ~= nil and feature.IsDerivedFrom("CharacterChoice") then
            choiceGuids[feature.guid] = true
            local kind = PoolKind(feature)
            if kind ~= nil then
                local description = nil
                pcall(function() description = feature:GetDescription() end)
                result.pools[#result.pools+1] = { name = feature:try_get("name") or "Choice", description = description, kind = kind }
            end
        end
    end
    local skills = Skill.SkillsById or {}
    local languages = dmhub.GetTableVisible(Language.tableName) or {}
    for _,entry in ipairs(details) do
        local feature = entry.feature
        if feature ~= nil and not feature.IsDerivedFrom("CharacterChoice") then
            for _,mod in ipairs(feature:try_get("modifiers", {})) do
                local ok, behavior = pcall(function() return mod.behavior end)
                local source = ok and mod:try_get("sourceguid") or nil
                if ok and behavior == "proficiency" and (source == nil or not choiceGuids[source]) then
                    local subtype = mod:try_get("subtype")
                    for id,on in pairs(mod:try_get("skills", {})) do
                        if on then
                            if subtype == "skill" and skills[id] ~= nil then
                                result.fixed[#result.fixed+1] = string.format("%s (skill)", skills[id].name)
                                result.fixedIds[id] = true
                            elseif subtype == "language" and languages[id] ~= nil then
                                result.fixed[#result.fixed+1] = string.format("%s (language)", languages[id].name)
                                result.fixedIds[id] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

--------------------------------------------------------------------------
--Token functions: what the builder screen calls. Each write runs the hero
--function inside token:ModifyProperties, so only the diff is uploaded.
--------------------------------------------------------------------------

--Run fn(hero) inside ModifyProperties and return its result.
---@param token CharacterToken
---@param description string
---@param fn fun(hero: character): any
---@return any
local function Modify(token, description, fn)
    local result = nil
    token:ModifyProperties{
        description = description,
        undoable = false,
        execute = function()
            local hero = token.properties --[[@as character]]
            result = fn(hero)
        end,
    }
    return result
end

---@param token CharacterToken
---@param stepid string
---@return table
function EotwBuild.StepStatus(token, stepid)
    return EotwBuild.hero.StepStatus(token, token.properties --[[@as character]], stepid)
end

--The status of the whole build:
--  { complete, steps = {stepStatus...}, incomplete = {stepid...} }
--`complete` is what Finish needs: every step complete.
---@param token CharacterToken
---@return table
function EotwBuild.Status(token)
    local steps = {}
    local incomplete = {}
    for _,step in ipairs(EotwBuild.STEPS) do
        local status = EotwBuild.StepStatus(token, step.id)
        steps[#steps+1] = status
        if not status.complete then
            incomplete[#incomplete+1] = step.id
        end
    end
    return {
        complete = #incomplete == 0,
        steps = steps,
        incomplete = incomplete,
    }
end

---@param token CharacterToken
---@param raceid string
function EotwBuild.SetAncestry(token, raceid)
    Modify(token, "Choose ancestry", function(hero) EotwBuild.hero.SetAncestry(hero, raceid) end)
end

---@param token CharacterToken
---@param careerid string
function EotwBuild.SetCareer(token, careerid)
    Modify(token, "Choose career", function(hero) EotwBuild.hero.SetCareer(hero, careerid) end)
end

---@param token CharacterToken
---@param classid string
function EotwBuild.SetClass(token, classid)
    Modify(token, "Choose class", function(hero) EotwBuild.hero.SetClass(hero, classid) end)
end

---@param token CharacterToken
---@param cultureid string
function EotwBuild.SetCultureAggregate(token, cultureid)
    Modify(token, "Choose culture", function(hero) EotwBuild.hero.SetCultureAggregate(hero, cultureid, false) end)
end

---@param token CharacterToken
---@param category string
---@param aspectid string
function EotwBuild.SetCultureAspect(token, category, aspectid)
    Modify(token, "Choose culture aspect", function(hero) EotwBuild.hero.SetCultureAspect(hero, category, aspectid) end)
end

--complicationid nil means "no complication", which completes the step.
---@param token CharacterToken
---@param complicationid string|nil
function EotwBuild.SetComplication(token, complicationid)
    Modify(token, "Choose complication", function(hero) EotwBuild.hero.SetComplication(hero, complicationid) end)
end

---@param token CharacterToken
function EotwBuild.ClearComplication(token)
    Modify(token, "Clear complication", function(hero) EotwBuild.hero.ClearComplication(hero) end)
end

---@param token CharacterToken
---@param arrayIndex integer
---@param build table<string, integer>|nil
function EotwBuild.SetCharacteristics(token, arrayIndex, build)
    Modify(token, "Choose characteristics", function(hero) EotwBuild.hero.SetCharacteristics(hero, arrayIndex, build) end)
end

---@param token CharacterToken
---@param stepid string
---@param rowid string
---@param optionId string
---@return boolean saved
function EotwBuild.Choose(token, stepid, rowid, optionId)
    return Modify(token, "Make a choice", function(hero) return EotwBuild.hero.Choose(hero, stepid, rowid, optionId) end) == true
end

---@param token CharacterToken
---@param stepid string
---@param rowid string
---@param optionId string
function EotwBuild.Unchoose(token, stepid, rowid, optionId)
    Modify(token, "Remove a choice", function(hero) EotwBuild.hero.Unchoose(hero, stepid, rowid, optionId) end)
end

---@param token CharacterToken
---@param kind string "skill" or "language"
---@return table
function EotwBuild.PoolTable(token, kind)
    return EotwBuild.hero.PoolTable(token.properties --[[@as character]], kind)
end

---@param token CharacterToken
---@param kind string
---@param id string
---@return boolean changed
function EotwBuild.TogglePoolPick(token, kind, id)
    return Modify(token, "Choose a skill or language", function(hero) return EotwBuild.hero.TogglePoolPick(hero, kind, id) end) == true
end

---@param token CharacterToken
---@param stepid string
---@return table
function EotwBuild.StepGrants(token, stepid)
    return EotwBuild.hero.StepGrants(token.properties --[[@as character]], stepid)
end

---@param token CharacterToken
---@param stepid string
---@return boolean
function EotwBuild.HasDependentPicks(token, stepid)
    return EotwBuild.hero.HasDependentPicks(token.properties --[[@as character]], stepid)
end

---@param token CharacterToken
---@param name string
function EotwBuild.SetName(token, name)
    token.name = name
    token:UploadAppearance()
end

--Marks a portrait the builder chose (the class's or ancestry's default art)
--rather than one the player picked. Only an auto portrait follows a class
--change; nil means a hero from before the flag existed.
EotwBuild.AUTO_PORTRAIT_FIELD = "eotwAutoPortrait"

--Set the hero's portrait. auto: the builder is applying a default, not the
--player choosing. The separate off-token portrait (the hero card's art, set
--from the full character sheet) is cleared so the card shows this one too.
---@param token CharacterToken
---@param imageid string
---@param auto? boolean
function EotwBuild.SetPortrait(token, imageid, auto)
    token.portrait = imageid
    token.offTokenPortrait = ""
    token:UploadAppearance()
    local hero = token.properties --[[@as character]]
    if hero:try_get(EotwBuild.AUTO_PORTRAIT_FIELD) ~= (auto == true) then
        Modify(token, "Portrait", function(h) h[EotwBuild.AUTO_PORTRAIT_FIELD] = auto == true end)
    end
end

---@param token CharacterToken
---@param stepid string
---@param rowid string
---@return table[]|nil options
---@return table|nil info
function EotwBuild.RowOptions(token, stepid, rowid)
    return EotwBuild.hero.RowOptions(token.properties --[[@as character]], stepid, rowid)
end

--Whether nothing at all has been chosen yet: no main pick on any step, no
--name and no portrait. A builder closed in this state leaves no draft.
---@param token CharacterToken
---@return boolean
function EotwBuild.IsUnstarted(token)
    local hero = token.properties --[[@as character]]
    if EotwBuild.hero.Ancestry(hero) ~= nil or EotwBuild.hero.Career(hero) ~= nil or hero:GetClass() ~= nil then
        return false
    end
    if #EotwBuild.hero.ComplicationIds(hero) > 0 or EotwBuild.hero.ChoseNoComplication(hero) then
        return false
    end
    local culture = hero:try_get("culture")
    if culture ~= nil then
        for _,v in pairs(culture.aspects) do
            if v ~= "" then
                return false
            end
        end
    end
    local name = token.name
    if type(name) == "string" and trim(name) ~= "" then
        return false
    end
    return not EotwBuild.PortraitIsSet(token.portrait)
end

--Keep a hero's portrait on the default art until the player picks
--something else: the class's art, or the ancestry's before a class is
--chosen. A portrait that is unset or that the builder set (AUTO_PORTRAIT_FIELD)
--follows the current choice. A player's pick never does, even when it is a
--class's or ancestry's art: the Avatar library holds that art too.
---@param token CharacterToken
function EotwBuild.SyncDefaultPortrait(token)
    local hero = token.properties --[[@as character]]
    local classItem = hero:GetClass()
    local race = EotwBuild.hero.Ancestry(hero)
    local art = ""
    if classItem ~= nil then
        art = classItem:try_get("portraitid", "")
    elseif race ~= nil then
        art = race:try_get("portraitid", "")
    end
    local current = token.portrait
    if art == "" or current == art then
        return
    end
    local isDefault = not EotwBuild.PortraitIsSet(current)
    local auto = hero:try_get(EotwBuild.AUTO_PORTRAIT_FIELD)
    if auto ~= nil then
        isDefault = isDefault or auto == true
    elseif not isDefault then
        --A hero from before the flag: guess from the art itself.
        for _,tableName in ipairs({ Class.tableName, Race.tableName }) do
            for _,item in pairs(dmhub.GetTableVisible(tableName) or {}) do
                if item:try_get("portraitid", "") == current then
                    isDefault = true
                    break
                end
            end
        end
    end
    if isDefault then
        EotwBuild.SetPortrait(token, art, true)
    end
end

--A name from the ancestry's name generator, or nil when it has none.
---@param hero character
---@return string|nil
function EotwBuild.GenerateName(hero)
    local name = nil
    pcall(function()
        local generator = hero:GetNameGeneratorTable()
        if generator == nil or #generator.rows == 0 then
            return
        end
        local result
        if generator:IsChoice() then
            result = generator:Roll(math.random(1, #generator.rows))
        else
            result = generator:Roll()
        end
        name = result:JoinString(" ")
    end)
    if type(name) == "string" and trim(name) ~= "" then
        return name
    end
    return nil
end

--Fill the Appearance step: a generated name and the class portrait, each
--only when missing.
---@param token CharacterToken
---@return string[]
local function FillAppearance(token)
    local picks = {}
    local hero = token.properties --[[@as character]]
    local changed = false

    local name = token.name
    if type(name) ~= "string" or trim(name) == "" then
        local generated = EotwBuild.GenerateName(hero)
        if generated == nil then
            local race = EotwBuild.hero.Ancestry(hero)
            local classItem = hero:GetClass()
            generated = string.format("%s %s", race and race.name or "Nameless", classItem and classItem.name or "Hero")
        end
        token.name = generated
        picks[#picks+1] = "Name -> " .. generated
        changed = true
    end

    if not EotwBuild.PortraitIsSet(token.portrait) then
        local classItem = hero:GetClass()
        local classPortrait = classItem and classItem:try_get("portraitid", "") or ""
        if classPortrait ~= "" then
            EotwBuild.SetPortrait(token, classPortrait, true)
            picks[#picks+1] = "Portrait -> class art"
        end
    end

    if changed then
        token:UploadAppearance()
    end
    return picks
end

--"Fill in the rest" for one step: fills only what is empty, never
--replaces a pick the player made, and removes stale picks. Returns the
--picks made as "Row -> Option" strings.
---@param token CharacterToken
---@param stepid string
---@return string[]
function EotwBuild.Fill(token, stepid)
    if stepid == "appearance" then
        return FillAppearance(token)
    end
    return Modify(token, "Fill in the rest", function(hero) return EotwBuild.hero.Fill(hero, stepid) end) or {}
end

--Fill every step in order, completing the hero (the builder's second
--Fill in the Rest click, "For All Tabs?").
---@param token CharacterToken
---@return string[]
function EotwBuild.FillAll(token)
    local picks = {}
    for _,step in ipairs(EotwBuild.STEPS) do
        for _,pick in ipairs(EotwBuild.Fill(token, step.id)) do
            picks[#picks+1] = step.title .. ": " .. pick
        end
    end
    return picks
end
