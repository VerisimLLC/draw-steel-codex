local mod = dmhub.GetModLoading()

--The hero build engine: the steps of building a Hero and the rules behind
--each pick, with no UI. The Encounter of the Week builder, the main game's
--Builder, Level up and the Hero sheet's Skills and Languages windows share it.
--
--A hero is built in steps: Ancestry, Culture, Career, Class, Skills &
--Languages, Complication, Appearance. For each step the engine can
--  * list the base options (which ancestry, which career, ...);
--  * list the step's choice rows and say which are filled (Status);
--  * write a pick (SetAncestry, Choose, ...);
--  * fill whatever is still empty with defaults or random picks (Fill,
--    PlanFill / ApplyFill).
--Status is read from the character on every call; only Build.Cached lets
--one repaint share a build of the rows.
--
--The rules come from the main builder's data layer: its feature cache, which
--turns a Hero's features into choice rows, and its choice adapters.
--
--Each game mode makes its own engine with HeroBuild.Create(options): EotW
--offers only fully automated complications and one at most; the main game
--offers every complication and allows several. HeroBuild.main is the main
--game's. Two layers per engine:
--  * hero functions (engine.hero.*) take the character properties and
--    mutate them directly: run them inside a save (HeroSheetWrite.Save in
--    the main game), or on an in-memory copy for testing;
--  * token functions (engine.SetAncestry, engine.Choose, ...) wrap the hero
--    functions in token:ModifyProperties (EotW's builder uses these).

HeroBuild = rawget(_G, "HeroBuild") or {}

--- An ancestry name as it is said: "Elf, High" (how ancestries are listed)
--- reads "High Elf".
--- @param name nil|string
--- @return string
function HeroBuild.SaidName(name)
    if type(name) ~= "string" then
        return ""
    end
    local first, rest = string.match(name, "^(.-),%s*(.+)$")
    if first ~= nil then
        return rest .. " " .. first
    end
    return name
end

--The builder's words live in EotW's UI text table, which loads before this
--file.
local T = UIText.T

---@class HeroBuildOptions
---@field complicationOffered nil|fun(hero: character, item: CharacterComplication): boolean whether the Complication step offers this one (prerequisites are checked as well)
---@field maxComplications nil|integer more complications than this make the extras stale; nil for no limit
---@field undoable nil|boolean whether the token functions' writes are undoable (default true)
---@field treasureOnPick nil|boolean a Grant Treasure pick hands the item over at once and can be changed (EotW); otherwise it is claimed from the character sheet
---@field equipGiven nil|fun(token: CharacterToken, itemid: string) wears a treasure handed over on its pick
---@field nativeLanguagePooled nil|boolean the culture's language is chosen on Skills & Languages with every other language (the main game); otherwise it stays on the Culture step (EotW)
---@field mainFill nil|boolean Fill as the main game's Builder does: the book's Quick Build choices first, then a skill the Hero has an edge with; it never writes "no complication" and removes a complication no longer offered. EotW fills at random apart from its own rules.

--- Make a build engine for a game mode.
--- @param options HeroBuildOptions
--- @return HeroBuildEngine
function HeroBuild.Create(options)
    ---@class HeroBuildEngine
    local Build = {}

    --How many complications a Hero may hold in this game mode; nil for no limit.
    Build.maxComplications = options.maxComplications

    --The steps in order. `base` is the label of the step's main pick.
    Build.STEPS = {
        { id = "ancestry", title = T("builder.steps.ancestry.title"), base = T("builder.steps.ancestry.base") },
        { id = "culture", title = T("builder.steps.culture.title") },
        { id = "career", title = T("builder.steps.career.title"), base = T("builder.steps.career.base") },
        { id = "class", title = T("builder.steps.class.title"), base = T("builder.steps.class.base") },
        --every skill and language choice from the other steps, made in one
        --place (see "Skills & Languages" below)
        { id = "skills", title = T("builder.steps.skills.title") },
        { id = "complication", title = T("builder.steps.complication.title"), base = T("builder.steps.complication.base") },
        { id = "appearance", title = T("builder.steps.appearance.title") },
    }

    --stepid -> step entry.
    Build.STEP_BY_ID = {}
    for _,step in ipairs(Build.STEPS) do
        Build.STEP_BY_ID[step.id] = step
    end

    --Hand-picked defaults Fill prefers over a random pick. An entry whose
    --option is not currently offered is ignored, so a stale entry is harmless.
    --  choices[choiceGuid] = { optionId, ... } in order of preference;
    --  classes[classid] = { array = <index into baseCharacteristics.arrays>,
    --                       kit = <kit id> }.
    Build.DEFAULTS = {
        choices = {},
        classes = {},
    }

    --Marks a hero whose player chose to take no complication, so the step
    --counts as done. Cleared when a complication is chosen. (Named when
    --this was EotW's alone; kept so existing Heroes keep their state.)
    Build.NO_COMPLICATION_FIELD = "eotwNoComplication"

    --Where the Skills & Languages step gathers skill and language choices
    --from, in the order it lists them. Besides the steps: the kit's
    --features, titles, and every other choice a Hero can hold (perks,
    --templates, features added by hand), which a Hero past Level 1 has.
    Build.POOL_SOURCE_STEPS = { "ancestry", "culture", "career", "class", "complication", "kit", "titles", "other" }

    --The pool sources that are not steps, by id: their titles.
    local EXTRA_POOL_SOURCES = {
        kit = { id = "kit", title = T("builder.skills.pool.kit") },
        titles = { id = "titles", title = T("builder.skills.pool.titles") },
        other = { id = "other", title = T("builder.skills.pool.other") },
    }

    --A step or extra pool source by id.
    ---@param id string
    ---@return nil|{id: string, title: string}
    local function SourceInfo(id)
        return Build.STEP_BY_ID[id] or EXTRA_POOL_SOURCES[id]
    end

    --The choice types the Skills & Languages step takes over, by kind.
    local POOL_KINDS = {
        CharacterSkillChoice = "skill",
        CharacterLanguageChoice = "language",
    }

    --The culture's language choice, the hero's native language: it stays on
    --the Culture step unless the engine pools it (options.nativeLanguagePooled).
    Build.NATIVE_LANGUAGE_GUID = "cultureLanguageChoice"

    --Whether a choice is one the Skills & Languages step makes, and which kind.
    ---@param feature table
    ---@return string|nil kind "skill" or "language"
    local function PoolKind(feature)
        local kind = POOL_KINDS[feature.typeName]
        if kind == nil or (feature.guid == Build.NATIVE_LANGUAGE_GUID and not options.nativeLanguagePooled) then
            return nil
        end
        return kind
    end

    --The options the book's Quick Build takes for a choice, as a set of
    --option ids: the choice's `recommended` list, seeded from the book's
    --"(Quick Build: X)" notes. Empty for any other choice.
    ---@param feature table the choice
    ---@return table<string, boolean>
    function Build.QuickBuildIds(feature)
        local result = {}
        local list = nil
        pcall(function() list = feature:try_get("recommended") end)
        if type(list) == "table" then
            for key,value in pairs(list) do
                --an array of ids, but tolerate a set
                local id = cond(type(key) == "number", value, key)
                if type(id) == "string" and value ~= false then
                    result[id] = true
                end
            end
        end
        return result
    end

    --Fill picks one option at a time and rebuilds the rows after each, so
    --choices revealed by a pick are filled too. This bounds that loop.
    local MAX_FILL_PICKS = 60

    local function Visible(tableName)
        return dmhub.GetTableVisible(tableName) or {}
    end

    --The placeholder portrait a new character token starts with. It does not
    --count as the player having chosen a portrait.
    Build.DEFAULT_PORTRAIT = "DEFAULT_MONSTER_AVATAR"

    --Whether a token portrait is a real choice (not empty, not the placeholder).
    ---@param portrait any
    ---@return boolean
    function Build.PortraitIsSet(portrait)
        return type(portrait) == "string" and portrait ~= "" and portrait ~= Build.DEFAULT_PORTRAIT
    end

    --A random element of an array, or nil when it is empty.
    local function RandomOf(list)
        if #list == 0 then
            return nil
        end
        return list[math.random(1, #list)]
    end

    --------------------------------------------------------------------------
    --Complications: which ones the step offers (EotW: only "gold" ones).
    --------------------------------------------------------------------------

    --The automation tier of a complication: the lowest `implementation` among
    --its features, skipping Narrative (0) parts, the way a monster's tier is
    --worked out. An unset tier counts as 1 (Not Automated). A complication
    --that is all narrative has tier 0.
    ---@param item CharacterComplication
    ---@return integer
    function Build.ComplicationTier(item)
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
    function Build.ComplicationIsGold(item)
        return Build.ComplicationTier(item) == gui.ImplementationStatus.Gold
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

    --Whether this engine's game mode offers the complication at all.
    ---@param hero character
    ---@param item CharacterComplication
    ---@return boolean
    local function ComplicationOffered(hero, item)
        if options.complicationOffered == nil then
            return true
        end
        return options.complicationOffered(hero, item)
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
    function Build.CultureAggregates()
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
    function Build.AncestryCultureId(race)
        if race == nil then
            return nil
        end
        local raceName = string.lower(HeroBuild.SaidName(race.name))
        for _,entry in ipairs(Build.CultureAggregates()) do
            if string.lower(entry.name) == raceName then
                return entry.id
            end
        end
        return nil
    end

    --Marks a culture the builder filled in from the ancestry rather than one
    --the player chose. The step then reads "Optional" instead of "Done"; any
    --change the player makes to the culture clears it.
    Build.AUTO_CULTURE_FIELD = "eotwAutoCulture"

    --The options for a step's main pick, as {id, name, item} sorted by name.
    --Culture returns the typical cultures; Appearance has none.
    ---@param hero character
    ---@param stepid string
    ---@return {id: string, name: string, item: table}[]
    function Build.BaseOptions(hero, stepid)
        if stepid == "ancestry" then
            return SortedByName(Visible(Race.tableName))
        elseif stepid == "culture" then
            return Build.CultureAggregates()
        elseif stepid == "career" then
            return SortedByName(Visible(Background.tableName))
        elseif stepid == "class" then
            return SortedByName(Visible(Class.tableName))
        elseif stepid == "complication" then
            return SortedByName(Visible(CharacterComplication.tableName), function(item)
                return ComplicationOffered(hero, item) and ComplicationPrereqMet(hero, item)
            end)
        end
        return {}
    end

    --------------------------------------------------------------------------
    --Reading the hero.
    --------------------------------------------------------------------------

    --The hero functions: each takes the character properties.
    ---@class HeroBuildHero
    Build.hero = {}

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
    function Build.hero.Ancestry(hero)
        local id = hero:try_get("raceid")
        return id and Visible(Race.tableName)[id] or nil
    end

    ---@param hero character
    ---@return table|nil career
    function Build.hero.Career(hero)
        local id = hero:try_get("backgroundid")
        return id and Visible(Background.tableName)[id] or nil
    end

    ---@param hero character
    ---@return Class|nil
    function Build.hero.Class(hero)
        return hero:GetClass()
    end

    --The complication ids the hero holds (EotW allows one; the main game
    --several).
    ---@param hero character
    ---@return string[]
    function Build.hero.ComplicationIds(hero)
        local result = {}
        for id,_ in pairs(hero:try_get("complications", {})) do
            result[#result+1] = id
        end
        table.sort(result)
        return result
    end

    ---@param hero character
    ---@return boolean
    function Build.hero.ChoseNoComplication(hero)
        return hero:try_get(Build.NO_COMPLICATION_FIELD, false) == true
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
            local race = Build.hero.Ancestry(hero)
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
            local career = Build.hero.Career(hero)
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
            for _,id in ipairs(Build.hero.ComplicationIds(hero)) do
                local item = items[id]
                if item ~= nil then
                    item:FillFeatureDetails(levelChoices, out, hero)
                end
            end

        --The pool sources that are not steps: a Hero's skill and
        --language choices from the kit, titles and everything else.
        elseif stepid == "kit" then
            local kit = hero:Kit()
            if kit ~= nil then
                local ok, err = pcall(function() kit:FillFeatureDetails(hero, levelChoices, out) end)
                if not ok then
                    dmhub.Error(string.format("HeroBuild: kit features failed: %s", tostring(err)))
                end
            end

        elseif stepid == "titles" then
            for _,title in ipairs(hero:Titles()) do
                title:FillFeatureDetails(levelChoices, out)
            end

        elseif stepid == "other" then
            for _,entry in ipairs(hero:GetBuilderChoiceFeatures()) do
                out[#out+1] = entry
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

    --Puts each choice that a pick brought (a purchased trait's own choice,
    --such as Prismatic Scales' damage type) straight after the choice holding
    --that pick. The cache sorts by Level, choice type and name alone, so a
    --brought choice could land above its parent ("Prismatic Scales" sorts
    --before "Purchased Dragon Knight Traits"). Rows keep their order otherwise.
    ---@param hero character
    ---@param rows HeroBuildRow[]
    ---@return HeroBuildRow[]
    local function NestUnderParents(hero, rows)
        local levelChoices = hero:GetLevelChoices() or {}
        --the characteristics and kit rows share their class's id, so an id
        --two rows hold takes no part in the nesting.
        local seen = {}
        for _,row in ipairs(rows) do
            local guid = row.wrapper:GetGuid()
            seen[guid] = (seen[guid] or 0) + 1
        end
        local inRows = {}
        for guid,count in pairs(seen) do
            if count == 1 then
                inRows[guid] = true
            end
        end
        --each brought choice's nearest parent: of the rows whose picks bring
        --it, the one that brings the fewest (a parent's own parent brings
        --everything its child does, and more).
        local parentOf = {}
        local broughtCount = {}
        for _,row in ipairs(rows) do
            local guid = row.wrapper:GetGuid()
            if inRows[guid] and levelChoices[guid] ~= nil then
                local brought = {}
                --pcall: not every choice type has FillFeaturesRecursive.
                pcall(function()
                    local feature = row.wrapper:GetFeature()
                    local descendants = {}
                    feature:FillFeaturesRecursive(levelChoices, descendants)
                    for _,descendant in ipairs(descendants) do
                        local id = descendant ~= feature and descendant:try_get("guid") or nil
                        if id ~= nil and id ~= guid and inRows[id] then
                            brought[#brought+1] = id
                        end
                    end
                end)
                broughtCount[guid] = #brought
                for _,id in ipairs(brought) do
                    local current = parentOf[id]
                    if current == nil or #brought < broughtCount[current] then
                        parentOf[id] = guid
                    end
                end
            end
        end
        if next(parentOf) == nil then
            return rows
        end
        local children = {}
        for _,row in ipairs(rows) do
            local parent = inRows[row.wrapper:GetGuid()] and parentOf[row.wrapper:GetGuid()] or nil
            if parent ~= nil then
                children[parent] = children[parent] or {}
                table.insert(children[parent], row)
            end
        end
        local result = {}
        --placed by row, not by id (two rows can share an id).
        local placed = {}
        local function Place(row)
            if placed[row] then
                return
            end
            placed[row] = true
            result[#result+1] = row
            local guid = row.wrapper:GetGuid()
            if inRows[guid] then
                for _,child in ipairs(children[guid] or {}) do
                    Place(child)
                end
            end
        end
        for _,row in ipairs(rows) do
            local guid = row.wrapper:GetGuid()
            if not inRows[guid] or parentOf[guid] == nil then
                Place(row)
            end
        end
        --a row whose parent never placed it (a loop in odd data) still shows.
        for _,row in ipairs(rows) do
            Place(row)
        end
        return result
    end

    --Kit equivalents chosen more than once (the Summoner's Ward with its Kit
    --Improvements' "one additional ward", a Conduit's further Prayer) are
    --separate choices whose options are copies with their own ids, so the
    --builder's own duplicate check misses them. A row of such a choice may
    --not pick an option another row of the same name holds (matched by
    --name); its own pick stays, so an older duplicate can still be swapped.
    ---@param rows HeroBuildRow[]
    local function ExcludeHeldKitEquivalents(rows)
        --- @type table<string, HeroBuildRow[]>
        local groups = {}
        for _,row in ipairs(rows) do
            local tagged = false
            pcall(function() tagged = (row.wrapper:GetFeature():try_get("tags") or {})["Kit Equivalent"] == true end)
            if tagged then
                local name = row.wrapper:GetName() or ""
                local list = groups[name]
                if list == nil then
                    list = {}
                    groups[name] = list
                end
                list[#list+1] = row
            end
        end
        for _,list in pairs(groups) do
            if #list > 1 then
                --the option names each row holds
                local held = {}
                for i,row in ipairs(list) do
                    held[i] = {}
                    local keyed = row.wrapper:GetOptionsKeyed()
                    for _,id in ipairs(row.wrapper:GetSelected()) do
                        local option = keyed[id]
                        if option ~= nil then
                            held[i][option:GetName()] = true
                        end
                    end
                end
                for i,row in ipairs(list) do
                    local others = {}
                    for j,names in ipairs(held) do
                        if j ~= i then
                            for name,_ in pairs(names) do
                                others[name] = true
                            end
                        end
                    end
                    local kept = {}
                    local keptKeyed = {}
                    for _,option in ipairs(row.wrapper:GetChoices()) do
                        local name = option:GetName()
                        if not others[name] or held[i][name] then
                            kept[#kept+1] = option
                            keptKeyed[option:GetGuid()] = option
                        end
                    end
                    row.wrapper.choices = kept
                    row.wrapper.choicesKeyed = keptKeyed
                end
            end
        end
    end

    --One choice row of a step: the builder's wrapper for the choice, the cache
    --it came from, and the row's id (the choice guid, or "characteristics" /
    --"kit" for those two class rows).
    ---@class HeroBuildRow
    ---@field wrapper CBFeatureWrapper
    ---@field cache CBFeatureCache
    ---@field id string
    ---@field source? string on the skills step: the step the choice comes from
    ---@field owner? string the item that grants the choice, where its data does not say (a complication's)

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
    ---@return HeroBuildRow[]
    local function BuildRows(hero, stepid, includePools)
        if stepid == "skills" then
            local result = {}
            for _,source in ipairs(Build.POOL_SOURCE_STEPS) do
                for _,row in ipairs(Build.hero.Wrappers(hero, source, true)) do
                    if PoolKind(row.wrapper:GetFeature()) ~= nil then
                        --a copy: the source step's own rows may be shared (Cached).
                        result[#result+1] = { wrapper = row.wrapper, cache = row.cache, id = row.id, owner = row.owner, source = source }
                    end
                end
            end
            return result
        end
        local step = SourceInfo(stepid)
        local title = step and step.title or stepid
        local details, separate = StepFeatureDetails(hero, stepid)
        --a complication's features name no complication (their source says
        --only "Feat"), so its choices carry the complication's name.
        local owners = {}
        if stepid == "complication" then
            for _,entry in ipairs(details) do
                if entry.feat ~= nil and entry.feature ~= nil then
                    owners[entry.feature.guid] = entry.feat.name
                end
            end
        end

        local function Collect(cache, rowid, into)
            for _,entry in ipairs(cache:GetSortedFeatures()) do
                local wrapper = cache:GetFeature(entry.guid)
                if wrapper ~= nil and not wrapper:SuppressStatus() and (includePools or PoolKind(wrapper:GetFeature()) == nil) then
                    into[#into+1] = { wrapper = wrapper, cache = cache, id = rowid or wrapper:GetGuid(), owner = owners[wrapper:GetGuid()] }
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
        local rows = NestUnderParents(hero, result)
        ExcludeHeldKitEquivalents(rows)
        return rows
    end

    --Inside Build.Cached: each step's rows built once per hero, by step and
    --whether pools are included. nil outside it.
    local g_rowsMemo = nil
    --Above 0 while a write runs (any Build.hero function not known to only
    --read): rows are built fresh, since the write changes what they show.
    local g_writing = 0

    --- Run fn with each step's rows built at most once. Building a step's
    --- rows builds every option of every choice, which is slow on a high-Level
    --- Hero, and one repaint asks for the same step several times (status, the
    --- Skills step's sources, the page's options). Only for work that reads:
    --- writes inside it build fresh and clear what was kept.
    ---@param fn function
    ---@return any ...
    function Build.Cached(fn, ...)
        if g_rowsMemo ~= nil then
            return fn(...)
        end
        g_rowsMemo = setmetatable({}, { __mode = "k" })
        local result = table.pack(pcall(fn, ...))
        g_rowsMemo = nil
        if not result[1] then
            error(result[2], 0)
        end
        return table.unpack(result, 2, result.n)
    end

    function Build.hero.Wrappers(hero, stepid, includePools)
        if g_rowsMemo == nil or g_writing > 0 then
            return BuildRows(hero, stepid, includePools)
        end
        local byHero = g_rowsMemo[hero]
        if byHero == nil then
            byHero = {}
            g_rowsMemo[hero] = byHero
        end
        local key = stepid .. (includePools and "+pools" or "")
        local rows = byHero[key]
        if rows == nil then
            rows = BuildRows(hero, stepid, includePools)
            byHero[key] = rows
        end
        return rows
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
    --  complete:  nothing more is owed (all picked, or nothing left to pick);
    --  exhausted: complete only because no option is left to pick;
    --  remaining: picks (or points) still owed;
    --  stale:     picked ids that are no longer offered (an earlier step
    --             changed); they count as not picked.
    ---@param hero character
    ---@param row HeroBuildRow
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
            --the Level the choice comes at (a class's levels), 0 when it has none.
            level = tonumber(wrapper:try_get("level")) or 0,
        }
    end

    --The base row of a step, or nil for a step without one.
    ---@param token table|nil the character token; Appearance needs it
    ---@param hero character
    ---@param stepid string
    ---@return table[] rows
    local function BaseRows(token, hero, stepid)
        if stepid == "ancestry" then
            local race = Build.hero.Ancestry(hero)
            return {{ guid = "base", name = "Ancestry", base = true, complete = race ~= nil, remaining = race and 0 or 1, selectedNames = { race and race.name or nil }, stale = {} }}
        elseif stepid == "career" then
            local career = Build.hero.Career(hero)
            return {{ guid = "base", name = "Career", base = true, complete = career ~= nil, remaining = career and 0 or 1, selectedNames = { career and career.name or nil }, stale = {} }}
        elseif stepid == "class" then
            local classItem = hero:GetClass()
            return {{ guid = "base", name = "Class", base = true, complete = classItem ~= nil, remaining = classItem and 0 or 1, selectedNames = { classItem and classItem.name or nil }, stale = {} }}
        elseif stepid == "complication" then
            local ids = Build.hero.ComplicationIds(hero)
            local items = Visible(CharacterComplication.tableName) --[[@as table<string, CharacterComplication>]]
            local names = {}
            local stale = {}
            for index,id in ipairs(ids) do
                local item = items[id]
                names[#names+1] = item and item.name or id
                --stale: no longer offered (gone, or not one this game mode
                --offers), or past the game mode's limit (EotW allows one).
                if item == nil or not ComplicationOffered(hero, item) or (options.maxComplications ~= nil and index > options.maxComplications) then
                    stale[#stale+1] = id
                end
            end
            if #ids == 0 then
                names[#names+1] = "No Complication"
            end
            --No complication is the default: the step is complete from the
            --start, so it never blocks Finish. `optional` (no complication
            --taken) tells the screen to say "Optional" rather than "Done".
            local complete = #stale == 0
            return {{ guid = "base", name = "Complication", base = true, complete = complete, optional = #ids == 0, remaining = complete and 0 or 1, selectedNames = names, stale = stale }}
        elseif stepid == "appearance" then
            local name = token and token.name or nil
            local portrait = token and token.portrait or nil
            local hasName = type(name) == "string" and trim(name) ~= ""
            local hasPortrait = Build.PortraitIsSet(portrait)
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
    function Build.hero.StepStatus(token, hero, stepid)
        local step = Build.STEP_BY_ID[stepid]
        local rows = BaseRows(token, hero, stepid)

        for _,row in ipairs(Build.hero.Wrappers(hero, stepid)) do
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
            result.optional = result.complete and hero:try_get(Build.AUTO_CULTURE_FIELD, false) == true
        end

        return result
    end

    --Draw Steel's highest Level (the Builder's Level picker offers 1 to 10).
    local MAX_LEVEL = 10

    --Picks the Hero holds for class choices above their Level. Lowering
    --the Level keeps them, and they apply again when the Hero reaches that
    --Level, so the screen lists them where they can be removed. One entry per
    --choice with picks, lowest Level first:
    --  { level, guid, name, picks = {{id, name}...} }
    --A pick whose option cannot be found is named after its choice.
    ---@param hero character
    ---@return {level: integer, guid: string, name: string, picks: {id: string, name: string}[]}[]
    function Build.hero.KeptPicks(hero)
        local classItem = hero:GetClass()
        if classItem == nil then
            return {}
        end
        local levelChoices = hero:GetLevelChoices() or {}
        local extraLevelInfo = hero:ExtraLevelInfo()
        local now, all = {}, {}
        for i,entry in ipairs(hero:GetClassesAndSubClasses()) do
            entry.class:FillFeatureDetailsForLevel(levelChoices, entry.level, extraLevelInfo, i ~= 1, now)
            entry.class:FillFeatureDetailsForLevel(levelChoices, MAX_LEVEL, extraLevelInfo, i ~= 1, all)
        end
        local current = {}
        for _,detail in ipairs(now) do
            local guid = detail.feature:try_get("guid")
            if guid ~= nil then
                current[guid] = true
            end
        end
        local above = {}
        for _,detail in ipairs(all) do
            local guid = detail.feature:try_get("guid")
            local list = guid ~= nil and levelChoices[guid] or nil
            if guid ~= nil and not current[guid] and type(list) == "table" and #list > 0 then
                above[#above+1] = detail
            end
        end
        if #above == 0 then
            return {}
        end
        --the options' names, from a cache of only these choices.
        local cache = CBFeatureCache.CreateNew(hero, "class", "Class", above)
        local result = {}
        for _,detail in ipairs(above) do
            local guid = detail.feature.guid
            local wrapper = cache:GetFeature(guid)
            local name = wrapper ~= nil and wrapper:GetName() or detail.feature:try_get("name", "")
            local keyed = wrapper ~= nil and wrapper:GetOptionsKeyed() or {}
            local picks = {}
            for _,id in ipairs(levelChoices[guid]) do
                if not IsBlankId(id) then
                    local option = keyed[id]
                    picks[#picks+1] = { id = id, name = option ~= nil and option:GetName() or name }
                end
            end
            if #picks > 0 then
                result[#result+1] = { level = (detail.levels or {})[1] or MAX_LEVEL, guid = guid, name = name, picks = picks }
            end
        end
        table.sort(result, function(left, right)
            if left.level ~= right.level then
                return left.level < right.level
            end
            return left.name < right.name
        end)
        return result
    end

    --Slow start's rungs: the four encounters a slow start's 1st Level
    --is spread over (extraLevelInfo.encounter 1-4).
    Build.RUNGS = {"First Encounter", "Second Encounter", "Third Encounter", "Fourth Encounter"}

    --The slow-start rung a Hero is on (1-4), or nil off the slow start: a
    --rung counts only at the 1st Level.
    ---@param hero character
    ---@return nil|integer
    function Build.hero.Rung(hero)
        local rung = hero:ExtraLevelInfo().encounter
        if type(rung) ~= "number" or hero:CharacterLevel() ~= 1 then
            return nil
        end
        return rung
    end

    --How far through the slow start a Hero is, as a Level up page key
    --(Build.PageKey): their rung, or 5 once they have the whole 1st Level.
    ---@param hero character
    ---@return integer
    function Build.hero.SlowStartStep(hero)
        return Build.hero.Rung(hero) or 5
    end

    --Level up's pages, in order: the slow start's 2nd to 4th rungs
    --are pages 2 to 4, the rest of the 1st Level page 5, and each Level from
    --the 2nd is page Level + 4. The 1st rung is the Builder's own.
    ---@param level integer
    ---@param rung nil|integer
    ---@return integer
    function Build.PageKey(level, rung)
        if level >= 2 then
            return level + 4
        end
        return rung or 5
    end

    --The page each class feature of the 1st Level first comes on: the rung
    --(1-4) that first holds it, else 5 (only the whole 1st Level has it).
    --By feature guid. The build data says only "Level 1" for all of them,
    --and the whole 1st Level can list a rung's feature again under another
    --guid: the engine takes it as the same feature (its CharacterUniqueID).
    ---@param hero character
    ---@return table<string, integer>
    function Build.hero.FirstLevelPages(hero)
        local levelChoices = hero:GetLevelChoices() or {}
        local result = {}
        local byUnique = {}
        for key = 1, 5 do
            local extra = {encounter = cond(key <= 4, key, nil)}
            local details = {}
            for i,entry in ipairs(hero:GetClassesAndSubClasses()) do
                entry.class:FillFeatureDetailsForLevel(levelChoices, 1, extra, i ~= 1, details)
            end
            for _,detail in ipairs(details) do
                local feature = detail.feature
                local unique = feature:CharacterUniqueID()
                if byUnique[unique] == nil then
                    byUnique[unique] = key
                end
                local guid = feature:try_get("guid")
                if guid ~= nil and result[guid] == nil then
                    result[guid] = byUnique[unique]
                end
            end
        end
        return result
    end

    --Whether a feature reads as one in the Builder and Level up. Bookkeeping
    --stays out: a Hidden display kind, kit tweaks, characteristics only, or
    --resources only with no words (a class's Recoveries). Abilities and
    --triggered actions show: the sheet's Features list leaves those to its
    --ability cards, but the Builder has no other place for them.
    ---@param feature any
    ---@param withCharacteristics nil|boolean Level up's You gain: a Characteristic Increase is that Level's main gain, so it shows there even when its data marks it Hidden
    ---@return boolean
    function Build.FeatureShown(feature, withCharacteristics)
        local mods = {}
        pcall(function() mods = feature:try_get("modifiers") or {} end)
        if withCharacteristics then
            for _,modifier in ipairs(mods) do
                local behavior = nil
                pcall(function() behavior = modifier:try_get("behavior") end)
                if behavior == "attribute" then
                    return true
                end
            end
        end
        local kind = "normal"
        pcall(function() kind = feature:DisplayKind() end)
        if kind == "hidden" then
            return false
        elseif kind ~= "normal" then
            return true
        end
        local allResources = #mods > 0
        for _,modifier in ipairs(mods) do
            local behavior = nil
            pcall(function() behavior = modifier:try_get("behavior") end)
            if behavior == "kitmodifyability" then
                return false
            end
            allResources = allResources and behavior == "resource"
        end
        local categoriser = rawget(_G, "FeatureCategoriser")
        if not withCharacteristics and categoriser ~= nil and categoriser.FeatureIsOnlyCharacteristics ~= nil then
            local ok, only = pcall(categoriser.FeatureIsOnlyCharacteristics, feature)
            if ok and only then
                return false
            end
        end
        if allResources then
            local text = nil
            pcall(function() text = feature:GetDescription() end)
            if type(text) ~= "string" or trim(text) == "" then
                return false
            end
        end
        return true
    end

    ---@class HeroBuildPageFeature
    ---@field feature any
    ---@field key integer the Level up page it first comes on (Build.PageKey)
    ---@field index integer 1 for the class, more for its subclasses
    ---@field class any the class or subclass granting it

    --What a Level's pages bring without a choice (Level up's You gain): the
    --class's and subclass's shown features, each on the page it first comes
    --on, read with no picks applied. A feature for a path the Hero did not
    --take (a domain they did not pick) is left out.
    ---@param hero character
    ---@param level integer
    ---@param firstLevel nil|table<string, integer> FirstLevelPages, for the 1st Level; worked out when nil
    ---@return HeroBuildPageFeature[]
    function Build.hero.PageFeatures(hero, level, firstLevel)
        local result = {}
        local extra = hero:ExtraLevelInfo()
        --the slow start's pages hold what each rung adds: read the whole 1st
        --Level and place each feature on the page it first comes on.
        if level == 1 then
            firstLevel = firstLevel or Build.hero.FirstLevelPages(hero)
            extra = {}
        end
        for i,entry in ipairs(hero:GetClassesAndSubClasses()) do
            local details = {}
            entry.class:FillFeatureDetailsForLevel({}, level, extra, i ~= 1, details)
            for _,detail in ipairs(details) do
                local feature = detail.feature
                local key = nil
                if firstLevel ~= nil then
                    key = firstLevel[feature:try_get("guid") or ""]
                else
                    for _,rowLevel in ipairs(detail.levels or {}) do
                        if rowLevel == level then
                            key = Build.PageKey(level, nil)
                        end
                    end
                end
                local isChoice = true
                pcall(function() isChoice = feature.IsDerivedFrom("CharacterChoice") end)
                pcall(function()
                    for _,prerequisite in ipairs(feature:try_get("prerequisites") or {}) do
                        if not prerequisite:Met(hero) then
                            key = nil
                        end
                    end
                end)
                local name = feature:try_get("name")
                if key ~= nil and not isChoice and type(name) == "string" and name ~= "" and Build.FeatureShown(feature, true) then
                    result[#result+1] = {feature = feature, key = key, index = i, class = entry.class}
                end
            end
        end
        return result
    end

    --Each class row's Level up page, by position: a row joins its own page,
    --and a row nested under a later page's choice stays with it. Rows of no
    --Level stay with the row before.
    ---@param levels (integer|nil)[] each row's own Level, by position
    ---@param guids (string|nil)[] each row's choice guid, by position
    ---@param firstLevel nil|table<string, integer> FirstLevelPages; nil puts every 1st-Level row on page 5
    ---@param count integer how many rows
    ---@return integer[]
    function Build.PageGroups(levels, guids, firstLevel, count)
        local groups = {}
        local group = 1
        for i = 1, count do
            local level = tonumber(levels[i]) or 0
            local key = nil
            if level >= 2 then
                key = level + 4
            elseif level == 1 then
                key = 5
                if firstLevel ~= nil then
                    key = firstLevel[guids[i] or ""]
                end
            end
            if key ~= nil then
                group = math.max(group, key)
            end
            groups[i] = group
        end
        return groups
    end

    --- Level up's rows: the class step's choices in step order, with
    --- the skill and language choices the Builder leaves to Skills & Languages
    --- (a Level's skill at 4, 7 and 10, a perk's language), so a Level's page
    --- counts and offers them. Each is a RowStatus; `pool` is "skill" or
    --- "language" on those, nil on the rest. No base row.
    ---@param hero character
    ---@return table[]
    function Build.hero.LevelRows(hero)
        local result = {}
        for _,row in ipairs(Build.hero.Wrappers(hero, "class", true)) do
            local status = RowStatus(hero, row)
            status.pool = PoolKind(row.wrapper:GetFeature())
            result[#result+1] = status
        end
        return result
    end

    --- Which Level up page each of the Hero's skill and language choices is
    --- on, by choice guid: the pages Build.PageGroups gives LevelRows.
    ---@param hero character
    ---@return table<string, integer>
    function Build.hero.PoolPages(hero)
        local rows = Build.hero.LevelRows(hero)
        local own, guids = {}, {}
        for i,row in ipairs(rows) do
            own[i] = row.level
            guids[i] = row.guid
        end
        local firstLevel = nil
        if hero:try_get("rungSeen") ~= nil then
            firstLevel = Build.hero.FirstLevelPages(hero)
        end
        local result = {}
        for i,group in ipairs(Build.PageGroups(own, guids, firstLevel, #rows)) do
            if rows[i].pool ~= nil then
                result[rows[i].guid] = group
            end
        end
        return result
    end

    ---@class HeroBuildPage
    ---@field level integer the Level (1 for the slow start's pages)
    ---@field rung nil|integer the slow-start rung (2-4); nil for a Level's page
    ---@field key integer the page's place in order (Build.PageKey)
    ---@field left integer picks still open
    ---@field choices integer how many choices

    --The pages Level up shows: every Level above the last one
    --the Hero finished there (Rest notes it), choices or not, and any Level
    --from the 2nd with a choice still open. levelUpSeen is nil for a Hero who
    --has not reached a Level by a respite since: every Level they have counts
    --as seen. The slow start's pages come first, the same way, for a Hero
    --with a rungSeen note (the Director moved them up a rung). Lowest first.
    ---@param hero character
    ---@return HeroBuildPage[]
    function Build.hero.LevelsWaiting(hero)
        local rows = Build.hero.LevelRows(hero)
        local top = hero:CharacterLevel()
        local seen = hero:try_get("levelUpSeen")
        local rungSeen = hero:try_get("rungSeen")
        local own = {}
        local guids = {}
        local list = {}
        for _,row in ipairs(rows) do
            list[#list+1] = row
            own[#list] = row.level
            guids[#list] = row.guid
        end
        local firstLevel = nil
        if rungSeen ~= nil then
            firstLevel = Build.hero.FirstLevelPages(hero)
        end
        local groups = Build.PageGroups(own, guids, firstLevel, #list)
        local left = {}
        local choices = {}
        for i,row in ipairs(list) do
            local page = groups[i]
            choices[page] = (choices[page] or 0) + 1
            if not row.complete then
                left[page] = (left[page] or 0) + math.max(1, row.remaining or 1)
            end
        end
        local result = {}
        if rungSeen ~= nil then
            --a slow-start page with no choice and nothing gained is skipped:
            --some classes' rungs add nothing.
            local gains = nil
            local function HasGains(key)
                if gains == nil then
                    gains = {}
                    for _,entry in ipairs(Build.hero.PageFeatures(hero, 1, firstLevel)) do
                        gains[entry.key] = true
                    end
                end
                return gains[key] == true
            end
            for key = 2, Build.hero.SlowStartStep(hero) do
                if (left[key] or 0) > 0 or (key > rungSeen and ((choices[key] or 0) > 0 or HasGains(key))) then
                    result[#result+1] = { level = 1, rung = cond(key <= 4, key, nil), key = key, left = left[key] or 0, choices = choices[key] or 0 }
                end
            end
        end
        for level = 2, top do
            local key = level + 4
            if (seen ~= nil and level > seen) or (left[key] or 0) > 0 then
                result[#result+1] = { level = level, key = key, left = left[key] or 0, choices = choices[key] or 0 }
            end
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
    function Build.hero.ClearStepChoices(hero, stepid)
        local levelChoices = hero:GetLevelChoices() or {}
        for _,row in ipairs(Build.hero.Wrappers(hero, stepid, true)) do
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
    function Build.hero.HasDependentPicks(hero, stepid)
        for _,row in ipairs(Build.hero.Wrappers(hero, stepid, true)) do
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
    function Build.hero.SetAncestry(hero, raceid)
        if hero:try_get("raceid") == raceid then
            return
        end
        Build.hero.ClearStepChoices(hero, "ancestry")
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
        local auto = hero:try_get(Build.AUTO_CULTURE_FIELD, false) == true
        if untouched or auto then
            local cultureid = Build.AncestryCultureId(Build.hero.Ancestry(hero))
            if cultureid ~= nil then
                Build.hero.SetCultureAggregate(hero, cultureid, true)
            elseif auto then
                Build.hero.ClearStepChoices(hero, "culture")
                hero[Build.AUTO_CULTURE_FIELD] = false
                hero:Invalidate()
            end
        end
    end

    ---@param hero character
    ---@param careerid string
    function Build.hero.SetCareer(hero, careerid)
        if hero:try_get("backgroundid") == careerid then
            return
        end
        Build.hero.ClearStepChoices(hero, "career")
        hero.backgroundid = careerid
        hero:Invalidate()
    end

    --Set the class, at the Hero's current Level (Level 1 for a new Hero; EotW
    --Heroes are always Level 1). Clears the old class's picks, kit and
    --characteristics.
    ---@param hero character
    ---@param classid string
    function Build.hero.SetClass(hero, classid)
        local current = hero:GetClass()
        if current ~= nil and current.id == classid then
            return
        end
        local level = 1
        local classes = hero:try_get("classes")
        if type(classes) == "table" and classes[1] ~= nil and type(classes[1].level) == "number" then
            level = classes[1].level
        end
        Build.hero.ClearStepChoices(hero, "class")
        hero.classes = { { classid = classid, level = level } }
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
    function Build.hero.SetCultureAggregate(hero, cultureid, auto)
        local item = Visible(Culture.tableName)[cultureid] --[[@as Culture|nil]]
        if item == nil then
            return
        end
        hero[Build.AUTO_CULTURE_FIELD] = auto == true
        Build.hero.ClearStepChoices(hero, "culture")
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
    function Build.hero.SetCultureAspect(hero, category, aspectid)
        hero[Build.AUTO_CULTURE_FIELD] = false
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
    function Build.hero.SetComplication(hero, complicationid)
        local ids = Build.hero.ComplicationIds(hero)
        local unchanged = (complicationid == nil and #ids == 0) or (#ids == 1 and ids[1] == complicationid)
        if not unchanged then
            Build.hero.ClearStepChoices(hero, "complication")
            hero.complications = {}
            if complicationid ~= nil then
                hero.complications[complicationid] = true
            end
        end
        hero[Build.NO_COMPLICATION_FIELD] = (complicationid == nil)
        hero:Invalidate()
    end

    --Add or remove one complication, keeping the others (the main game allows
    --several). Removing one drops its picks.
    ---@param hero character
    ---@param complicationid string
    function Build.hero.ToggleComplication(hero, complicationid)
        local complications = hero:get_or_add("complications", {})
        if not complications[complicationid] and options.maxComplications == 1 then
            --a game mode with one complication (EotW): the new pick replaces it.
            Build.hero.SetComplication(hero, complicationid)
            return
        end
        if complications[complicationid] then
            local items = Visible(CharacterComplication.tableName) --[[@as table<string, CharacterComplication>]]
            local item = items[complicationid]
            if item ~= nil then
                local levelChoices = hero:GetLevelChoices() or {}
                local details = {}
                item:FillFeatureDetails(levelChoices, details, hero)
                for _,entry in ipairs(details) do
                    local feature = entry.feature
                    if feature ~= nil and feature.IsDerivedFrom("CharacterChoice") then
                        levelChoices[feature.guid] = nil
                    end
                end
            end
            complications[complicationid] = nil
        else
            complications[complicationid] = true
            hero[Build.NO_COMPLICATION_FIELD] = false
        end
        hero:Invalidate()
    end

    --Undo the complication step entirely: no complication and no "none" pick.
    ---@param hero character
    function Build.hero.ClearComplication(hero)
        Build.hero.ClearStepChoices(hero, "complication")
        hero.complications = {}
        hero[Build.NO_COMPLICATION_FIELD] = false
        hero:Invalidate()
    end

    --Take characteristic array `arrayIndex` of the hero's class. `build` maps
    --each unlocked characteristic id to its slot in the array; without it the
    --slots go in attribute order, highest value first.
    ---@param hero character
    ---@param arrayIndex integer
    ---@param build table<string, integer>|nil
    function Build.hero.SetCharacteristics(hero, arrayIndex, build)
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
        for _,row in ipairs(Build.hero.Wrappers(hero, stepid)) do
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
    function Build.hero.Choose(hero, stepid, rowid, optionId)
        if stepid == "culture" then
            hero[Build.AUTO_CULTURE_FIELD] = false
        end
        local wrapper = FindWrapper(hero, stepid, rowid)
        if wrapper == nil then
            return false
        end
        local feature = wrapper:GetFeature()
        if feature.typeName == "CharacterAspectChoice" then
            Build.hero.SetCultureAspect(hero, wrapper:GetGuid(), optionId)
            return true
        end
        local option = FindOption(wrapper, optionId)
        if option == nil then
            return false
        end
        if feature.typeName == "CharacterCharacteristicChoice" then
            Build.hero.SetCharacteristics(hero, option:GetOption().arrayIndex, nil)
            return true
        end

        --A one-pick row: drop the old pick first so its own sub-choices go too.
        if wrapper:GetNumChoices() == 1 then
            local dropped = false
            for _,id in ipairs(wrapper:GetSelected()) do
                if not IsBlankId(id) and id ~= optionId then
                    --the first drop uses the wrapper in hand; after a drop it
                    --is out of date, so a further one finds the row again.
                    Build.hero.Unchoose(hero, stepid, rowid, id, cond(dropped, nil, wrapper))
                    dropped = true
                end
            end
            --after a drop the rows are built again (the old pick's own
            --choices are gone); an empty row's wrapper is still current.
            if dropped then
                wrapper = FindWrapper(hero, stepid, rowid)
                if wrapper == nil then
                    return false
                end
                option = FindOption(wrapper, optionId)
                if option == nil then
                    return false
                end
            end
        end

        wrapper:SaveSelection(hero, option)
        hero:Invalidate()
        return true
    end

    local WrapperOptions

    --One choice row's options, for display:
    --  options = { {id, name, selected, available, cost, option}... } where
    --    available: it can be picked now (offered, not taken by another row,
    --               affordable); a selected option is always shown,
    --    option:    the builder's option wrapper (GetDescription, Panel);
    --  info = { name, description, numChoices, remaining, costsPoints,
    --           pointsName, typeName }.
    --Returns nil when the row does not exist.
    ---@param hero character
    ---@param stepid string
    ---@param rowid string
    ---@return table[]|nil options
    ---@return table|nil info
    function Build.hero.RowOptions(hero, stepid, rowid)
        local wrapper = FindWrapper(hero, stepid, rowid)
        if wrapper == nil then
            return nil, nil
        end
        return WrapperOptions(wrapper)
    end

    --Every choice row's options on a step, by row id, from one build of the
    --step's choices. RowOptions builds the whole step to answer for one row,
    --so a screen showing every row of a step asks this instead.
    --The same build gives the step's skill and language choices (made on the
    --Skills & Languages step), for a page that lists what the step grants.
    ---@param hero character
    ---@param stepid string
    ---@return table<string, {options: table[], info: table}> rows
    ---@return {guid: string, kind: string, feature: table, capacity: integer, selected: string[], owner: nil|string}[] pools
    function Build.hero.AllRowOptions(hero, stepid)
        local result = {}
        local pools = {}
        --the Level each row falls in: a skill choice nested under a perk
        --stays with the perk's Level.
        local group = 1
        for _,row in ipairs(Build.hero.Wrappers(hero, stepid, true)) do
            local wrapper = row.wrapper
            group = math.max(group, tonumber(wrapper:try_get("level")) or 1)
            local kind = PoolKind(wrapper:GetFeature())
            if kind ~= nil then
                local selected = {}
                for _,id in ipairs(wrapper:GetSelected()) do
                    if not IsBlankId(id) then
                        selected[#selected+1] = id
                    end
                end
                pools[#pools+1] = {
                    guid = wrapper:GetGuid(),
                    kind = kind,
                    feature = wrapper:GetFeature(),
                    capacity = wrapper:GetNumChoices(),
                    selected = selected,
                    owner = row.owner,
                    level = group,
                }
            else
                local rowOptions, info = WrapperOptions(wrapper)
                result[row.id] = { options = rowOptions, info = info }
            end
        end
        return result, pools
    end

    --One choice row's options from its wrapper (see RowOptions).
    ---@param wrapper CBFeatureWrapper
    ---@return table[] options
    ---@return table info
    WrapperOptions = function(wrapper)
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
        --EotW gives a grant treasure on the pick (SyncTreasureGrants), so drop
        --the old builder's "then claim it" wording.
        if options.treasureOnPick and feature.typeName == "CharacterTreasureGrantChoice" then
            local prompt = (feature --[[@as CharacterTreasureGrantChoice]]):try_get("prompt")
            if prompt ~= nil then
                description = T("builder.choice.treasure_grant_prompt", { prompt = prompt })
            end
        end
        return result, {
            name = wrapper:GetName(),
            description = description,
            numChoices = wrapper:GetNumChoices(),
            remaining = math.max(0, wrapper:GetNumChoices() - wrapper:GetSelectedValue()),
            costsPoints = wrapper:CostsPoints(),
            pointsName = wrapper:GetPointsName(),
            typeName = feature.typeName,
            --option id -> true for the book's Quick Build pick (starred on screen)
            quickBuild = Build.QuickBuildIds(feature),
        }
    end

    --Remove one pick from a choice row, including an id that is no longer
    --offered (a stale pick).
    ---@param hero character
    ---@param stepid string
    ---@param rowid string
    ---@param optionId string
    ---@param current? CBFeatureWrapper the row's wrapper when the caller has one built from the hero as it is now (saves building the step again)
    function Build.hero.Unchoose(hero, stepid, rowid, optionId, current)
        if stepid == "culture" then
            hero[Build.AUTO_CULTURE_FIELD] = false
        end
        local wrapper = current or FindWrapper(hero, stepid, rowid)
        if wrapper == nil then
            return
        end
        local feature = wrapper:GetFeature()
        local choiceGuid = wrapper:GetGuid()
        if feature.typeName == "CharacterAspectChoice" then
            Build.hero.SetCultureAspect(hero, choiceGuid, "")
            return
        end
        if options.treasureOnPick and feature.typeName == "CharacterTreasureGrantChoice" then
            --The grant's own RemoveSelection keeps a claimed pick locked. EotW
            --lets the player change it: SyncTreasureGrants takes the old item back.
            local grants = hero:try_get("treasureGrants")
            local state = grants ~= nil and grants[choiceGuid] or nil
            if type(state) == "table" then
                if state.claimed and state.eotwGiven == nil then
                    state.eotwGiven = state.itemid
                end
                state.itemid = nil
                state.claimed = false
            end
            hero:Invalidate()
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

    --Remove a pick held for a choice above the Hero's Level (a KeptPicks
    --entry). The choice is not a row at this Level, so Unchoose cannot find it.
    ---@param hero character
    ---@param choiceGuid string
    ---@param optionId string
    function Build.hero.DropKept(hero, choiceGuid, optionId)
        local levelChoices = hero:GetLevelChoices() or {}
        local list = levelChoices[choiceGuid]
        if type(list) ~= "table" then
            return
        end
        for i = #list, 1, -1 do
            if list[i] == optionId then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            levelChoices[choiceGuid] = nil
        end
        hero:Invalidate()
    end

    --Whether Level up's Finish for this Level has anything to note: false
    --for a Hero with no levelUpSeen (every Level counts as seen).
    ---@param hero character
    ---@param level integer
    ---@return boolean
    function Build.hero.LevelUnseen(hero, level)
        local seen = hero:try_get("levelUpSeen")
        return seen ~= nil and seen < level
    end

    --Level up's Finish Level N: the Levels up to N have been seen.
    ---@param hero character
    ---@param level integer
    function Build.hero.FinishLevel(hero, level)
        if Build.hero.LevelUnseen(hero, level) then
            hero.levelUpSeen = level
        end
    end

    --Build at Level sets the Level in the Builder, which shows every Level
    --already, so Level up has none left to show for the Hero.
    ---@param hero character
    ---@param level integer
    function Build.hero.MarkLevelsSeen(hero, level)
        if hero:try_get("levelUpSeen") ~= nil then
            hero.levelUpSeen = level
        end
    end

    --Level up's Finish on a slow-start page: the slow start has been
    --seen up to that page (its Build.PageKey).
    ---@param hero character
    ---@param key integer
    function Build.hero.FinishRung(hero, key)
        local seen = hero:try_get("rungSeen")
        if seen ~= nil and seen < key then
            hero.rungSeen = key
        end
    end

    --The Builder's Slow start and Build at Level show the whole slow start,
    --so Level up has no rung left to show. A Hero on a rung gets the note
    --here, so a later move up a rung opens Level up.
    ---@param hero character
    function Build.hero.MarkRungsSeen(hero)
        if hero:try_get("rungSeen") ~= nil or Build.hero.Rung(hero) ~= nil then
            hero.rungSeen = Build.hero.SlowStartStep(hero)
        end
    end

    --The card's Move to <rung> (the Director's, for one Hero): up one rung
    --as /slowstartlevel moves the map's Heroes, and off the slow start from
    --the 4th. The rung left is noted, so Level up shows the new page.
    ---@param hero character
    function Build.hero.NextRung(hero)
        local before = Build.hero.SlowStartStep(hero)
        local info = hero:ExtraLevelInfo()
        local rung = (tonumber(info.encounter) or 4) + 1
        info.encounter = cond(rung <= 4, rung, nil)
        hero.extraLevelInfo = info
        if hero:try_get("rungSeen") == nil and Build.hero.SlowStartStep(hero) > before then
            hero.rungSeen = before
        end
    end

    --The Level a manual Level up takes the Hero to, or nil: none
    --past the 10th, without a class, or on a slow-start rung (the Director
    --moves the slow start).
    ---@param hero character
    ---@return nil|integer
    function Build.hero.ManualLevel(hero)
        local level = hero:CharacterLevel()
        if hero:GetClass() == nil or level >= MAX_LEVEL or Build.hero.Rung(hero) ~= nil then
            return nil
        end
        return level + 1
    end

    --Write the Hero's Level as Build at Level does: the Level override, and
    --each class at that Level.
    ---@param hero character
    ---@param level integer
    function Build.hero.SetLevel(hero, level)
        hero.levelOverride = level
        for _,classInfo in ipairs(hero:try_get("classes", {})) do
            classInfo.level = level
        end
    end

    --Run fn with the Hero at a Level, then put their Level back. A manual
    --Level up writes its picks this way: made at the Level they are for,
    --they are kept above the Hero's own until Finish raises it.
    ---@param hero character
    ---@param level integer
    ---@param fn fun()
    function Build.hero.AtLevel(hero, level, fn)
        local override = hero:try_get("levelOverride")
        local levels = {}
        for i,classInfo in ipairs(hero:try_get("classes", {})) do
            levels[i] = classInfo.level
        end
        Build.hero.SetLevel(hero, level)
        hero:Invalidate()
        local ok, err = pcall(fn)
        hero.levelOverride = override
        for i,classInfo in ipairs(hero:try_get("classes", {})) do
            classInfo.level = levels[i]
        end
        hero:Invalidate()
        if not ok then
            error(err, 0)
        end
    end

    --Cancel on a manual Level up: drop the picks kept for that Level.
    ---@param hero character
    ---@param level integer
    function Build.hero.DropKeptForLevel(hero, level)
        for _,choice in ipairs(Build.hero.KeptPicks(hero)) do
            if choice.level == level then
                for _,pick in ipairs(choice.picks) do
                    Build.hero.DropKept(hero, choice.guid, pick.id)
                end
            end
        end
    end

    --------------------------------------------------------------------------
    --Treasure grants (EotW: options.treasureOnPick). A complication benefit
    --like Secret Twin's "a 1st-echelon
    --trinket of your choice" is a Grant Treasure modifier, and its row records
    --the pick in hero.treasureGrants[modifier guid]. The old builder hands the
    --item over with a separate Claim button; EotW has none, so this keeps the
    --hero holding exactly the treasure picked: given on a pick, taken back when
    --the pick or the complication changes. state.eotwGiven is the item handed
    --over. Manifest-mode grants (Artifact Bonded) only record the pick.
    --------------------------------------------------------------------------

    --The modifier guids of the hero's claim-mode grants, as a set.
    ---@param hero character
    ---@return table<string, boolean>
    local function LiveTreasureGrants(hero)
        local result = {}
        for _,stepid in ipairs(Build.POOL_SOURCE_STEPS) do
            for _,row in ipairs(Build.hero.Wrappers(hero, stepid, true)) do
                local feature = row.wrapper:GetFeature()
                if feature.typeName == "CharacterTreasureGrantChoice" then
                    local modifier = (feature --[[@as CharacterTreasureGrantChoice]]).modifier
                    if modifier:try_get("treasureDelivery", "claim") ~= "manifest" then
                        result[modifier.guid] = true
                    end
                end
            end
        end
        return result
    end

    --Whether the hero has the item in the pack or in an equipment slot.
    ---@param hero character
    ---@param itemid string
    ---@return boolean
    local function HoldsItem(hero, itemid)
        if hero:GetItemQuantity(itemid) > 0 then
            return true
        end
        for _,equipped in pairs(hero:Equipment()) do
            if equipped == itemid then
                return true
            end
        end
        return false
    end

    --Give each picked grant treasure and take back any the hero no longer owns
    --by their build. Every token write runs it (see Modify), and so does
    --joining the roster. With a token, a given treasure is worn at once while
    --there is a free slot, as all EotW treasure is.
    ---@param hero character
    ---@param token CharacterToken|nil
    function Build.hero.SyncTreasureGrants(hero, token)
        local grants = hero:try_get("treasureGrants")
        if grants == nil then
            return
        end
        local live = LiveTreasureGrants(hero)
        for guid,state in pairs(grants) do
            if type(state) == "table" then
                --claimed elsewhere (the full sheet, a pregen): now managed here
                if state.claimed and state.eotwGiven == nil then
                    state.eotwGiven = state.itemid
                end
                local want = live[guid] and state.itemid or nil
                if state.eotwGiven ~= nil and state.eotwGiven ~= want then
                    if HoldsItem(hero, state.eotwGiven) then
                        hero:GiveItem(state.eotwGiven, -1)
                    end
                    state.eotwGiven = nil
                    state.claimed = false
                end
                if not live[guid] then
                    grants[guid] = nil
                elseif want ~= nil and not state.claimed then
                    hero:GiveItem(want, 1)
                    state.claimed = true
                    state.eotwGiven = want
                    local equipGiven = options.equipGiven
                    if token ~= nil and equipGiven ~= nil then
                        pcall(equipGiven, token, want)
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------
    --Fill: complete a step with defaults and random picks.
    --
    --Fill can keep a log of what it changes, so a screen can show the
    --changes before making them (the Builder's Fill in the rest):
    --PlanFill runs Fill on a copy of the hero and returns the log, and
    --ApplyFill makes the same changes on the real hero inside one save.
    --------------------------------------------------------------------------

    --- One change Fill made, as PlanFill reports it and ApplyFill makes it again.
    ---@class HeroBuildFillEntry
    ---@field step string the step it shows under
    ---@field op string "ancestry", "culture", "career" or "class" (a main pick); "array" (characteristics); "choose"; "unchoose" (a stale pick); "pool" (a skill or language); "uncomplicate" (a stale complication); "follows" (brought by another change: shown, not made again)
    ---@field id nil|string the pick's id
    ---@field row nil|string the choice row's id ("choose", "unchoose")
    ---@field index nil|integer the characteristic array's place in the class's arrays ("array")
    ---@field kind nil|string "skill" or "language" ("pool")
    ---@field pool nil|string Level up: the skill or language choice it fills ("pool"), so it is placed there and not in an earlier Level's
    ---@field label nil|string the choice's name, as its row is named
    ---@field level nil|integer the Level the choice comes at (0 when it has none)
    ---@field page nil|integer Level up: the page it is on (Build.PageGroups)
    ---@field name nil|string the pick's name; nil for a stale pick nothing names any more
    ---@field quickBuild nil|boolean the book's Quick Build pick
    ---@field removes nil|boolean it takes a pick away (no longer offered)

    --The option Fill prefers among `pool`, or nil: the book's Quick Build
    --pick (the main game), else Build.DEFAULTS. The second value says
    --whether it is the Quick Build's.
    ---@param wrapper CBFeatureWrapper
    ---@param pool CBOptionWrapper[]
    ---@return CBOptionWrapper|nil
    ---@return boolean quickBuild
    local function PreferredOption(wrapper, pool)
        if options.mainFill then
            local quick = Build.QuickBuildIds(wrapper:GetFeature())
            for _,option in ipairs(pool) do
                if quick[option:GetGuid()] then
                    return option, true
                end
            end
        end
        local preferred = Build.DEFAULTS.choices[wrapper:GetGuid()]
        if preferred == nil then
            return nil, false
        end
        for _,id in ipairs(preferred) do
            for _,option in ipairs(pool) do
                if option:GetGuid() == id then
                    return option, false
                end
            end
        end
        return nil, false
    end

    --The culture Fill takes: one named after the hero's ancestry (a Dwarf
    --gets the Dwarf culture), otherwise a random typical culture.
    ---@param hero character
    ---@return string|nil cultureid
    local function DefaultCulture(hero)
        local cultureid = Build.AncestryCultureId(Build.hero.Ancestry(hero))
        if cultureid ~= nil then
            return cultureid
        end
        local entry = RandomOf(Build.CultureAggregates())
        return entry and entry.id or nil
    end

    --The name of the hero's typical culture, or nil (none yet, or one built
    --from aspects).
    ---@param hero character
    ---@return string|nil
    local function CultureName(hero)
        local culture = OwnCulture(hero)
        local id = culture ~= nil and culture:try_get("aggregate") or nil
        if type(id) ~= "string" or id == "" then
            return nil
        end
        local item = Visible(Culture.tableName)[id]
        return item and item.name or nil
    end

    --Make the step's main pick if it is missing. Returns a description of
    --what was picked, or nil; with a log, each change goes into it too.
    ---@param hero character
    ---@param stepid string
    ---@param log nil|HeroBuildFillEntry[]
    ---@return string|nil
    local function FillBase(hero, stepid, log)
        ---@param entry table
        local function Log(entry)
            if log ~= nil then
                entry.step = entry.step or stepid
                log[#log+1] = entry
            end
        end
        if stepid == "ancestry" and Build.hero.Ancestry(hero) == nil then
            local entry = RandomOf(Build.BaseOptions(hero, "ancestry"))
            if entry ~= nil then
                local culture = CultureName(hero)
                Build.hero.SetAncestry(hero, entry.id)
                Log{op = "ancestry", id = entry.id, name = entry.name}
                --the culture follows a new ancestry; it shows with the culture.
                local after = CultureName(hero)
                if after ~= nil and after ~= culture then
                    Log{op = "follows", step = "culture", name = after}
                end
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
                    Build.hero.SetCultureAggregate(hero, cultureid)
                    local item = Visible(Culture.tableName)[cultureid]
                    local name = item and item.name or cultureid
                    Log{op = "culture", id = cultureid, name = name}
                    return "Culture -> " .. name
                end
            end
        elseif stepid == "career" and Build.hero.Career(hero) == nil then
            local entry = RandomOf(Build.BaseOptions(hero, "career"))
            if entry ~= nil then
                Build.hero.SetCareer(hero, entry.id)
                Log{op = "career", id = entry.id, name = entry.name}
                return "Career -> " .. entry.name
            end
        elseif stepid == "class" and hero:GetClass() == nil then
            local entry = RandomOf(Build.BaseOptions(hero, "class"))
            if entry ~= nil then
                Build.hero.SetClass(hero, entry.id)
                Log{op = "class", id = entry.id, name = entry.name}
                return "Class -> " .. entry.name
            end
        elseif stepid == "complication" then
            if options.mainFill then
                --The main game writes no "none" (the step reads Optional
                --without a complication) and removes one no longer offered.
                local stale = BaseRows(nil, hero, "complication")[1].stale
                local items = dmhub.GetTable(CharacterComplication.tableName) or {}
                for _,id in ipairs(stale) do
                    Build.hero.ToggleComplication(hero, id)
                    local item = items[id]
                    Log{op = "uncomplicate", id = id, name = item and item.name or nil, removes = true}
                end
                if #stale > 0 then
                    return string.format("Complication -> removed %d no longer offered", #stale)
                end
                return nil
            end
            --Fill never adds a complication (each has a drawback); it settles
            --on none unless the player already chose one.
            if #Build.hero.ComplicationIds(hero) == 0 and not Build.hero.ChoseNoComplication(hero) then
                Build.hero.SetComplication(hero, nil)
                return "Complication -> none"
            end
        end
        return nil
    end
    Build.hero.FillBase = FillBase

    --Fill one row of a step with one pick. Returns a description, or nil when
    --nothing could be picked, and the change as a log entry (without its step).
    ---@param hero character
    ---@param row HeroBuildRow
    ---@return string|nil description
    ---@return nil|HeroBuildFillEntry entry
    local function FillOnePick(hero, row)
        local wrapper = row.wrapper
        local feature = wrapper:GetFeature()
        local label = wrapper:GetName()
        local level = tonumber(wrapper:try_get("level")) or 0

        --Characteristics: the class's default array, else a random one.
        if feature.typeName == "CharacterCharacteristicChoice" then
            local classItem = hero:GetClass()
            if classItem == nil then
                return nil, nil
            end
            local arrays = classItem.baseCharacteristics.arrays or {}
            if #arrays == 0 then
                return nil, nil
            end
            local defaults = Build.DEFAULTS.classes[classItem.id] or {}
            local index = defaults.array
            if index == nil or arrays[index] == nil then
                index = math.random(1, #arrays)
            end
            --the array's name as its card reads, before the write rebuilds the options
            local name = nil
            for _,option in ipairs(wrapper:GetOptions()) do
                local arrayIndex = nil
                pcall(function() arrayIndex = option:GetOption().arrayIndex end)
                if arrayIndex == index then
                    name = option:GetName()
                end
            end
            Build.hero.SetCharacteristics(hero, index, nil)
            return string.format("Characteristics -> array %d", index), {op = "array", index = index, label = label, level = level, name = name}
        end

        local pool = FreeChoices(wrapper)
        if #pool == 0 then
            return nil, nil
        end

        local option, quickBuild = PreferredOption(wrapper, pool)
        if option == nil and feature.typeName == "CharacterKitChoice" then
            local classItem = hero:GetClass()
            local defaults = classItem and Build.DEFAULTS.classes[classItem.id] or {}
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
            return nil, nil
        end

        if feature.typeName == "CharacterAspectChoice" then
            Build.hero.SetCultureAspect(hero, wrapper:GetGuid(), option:GetGuid())
        else
            wrapper:SaveSelection(hero, option)
            hero:Invalidate()
        end
        return string.format("%s -> %s", label or "?", option:GetName()), {op = "choose", row = row.id, id = option:GetGuid(), label = label, level = level, name = option:GetName(), quickBuild = quickBuild}
    end

    --The rows in the order Fill visits them: parent choices first (see
    --ParentRank), then the rest in display order.
    ---@param rows HeroBuildRow[]
    ---@return HeroBuildRow[]
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
    --picks made, as "Row -> Option" strings; with a log, each change goes
    --into it too (see HeroBuildFillEntry).
    ---@param hero character
    ---@param stepid string
    ---@param log nil|HeroBuildFillEntry[]
    ---@param pages nil|table<integer, boolean> Level up: fill only the class rows on these pages (Build.PageGroups keys), never the main pick
    ---@return string[]
    function Build.hero.Fill(hero, stepid, log, pages)
        if stepid == "skills" then
            local picks = Build.hero.FillPools(hero, "skill", log)
            for _,pick in ipairs(Build.hero.FillPools(hero, "language", log)) do
                picks[#picks+1] = pick
            end
            return picks
        end
        local picks = {}
        ---@param entry nil|table
        local function Log(entry)
            if log ~= nil and entry ~= nil then
                entry.step = stepid
                log[#log+1] = entry
            end
        end

        --the slow start's pages, for a Hero Level up shows them to.
        local firstLevel = nil
        if pages ~= nil and hero:try_get("rungSeen") ~= nil then
            firstLevel = Build.hero.FirstLevelPages(hero)
        end
        --the rows Level up may fill: those on the asked pages. The rows are
        --built again after each pick, so this is asked each time.
        ---@param rows table[] Wrappers rows, in step order
        ---@return nil|table<string, integer> each allowed row's page; nil when every row may be filled
        local function Allowed(rows)
            if pages == nil then
                return nil
            end
            local own = {}
            local guids = {}
            for i,row in ipairs(rows) do
                own[i] = tonumber(row.wrapper:try_get("level"))
                guids[i] = row.id
            end
            local allowed = {}
            for i,group in ipairs(Build.PageGroups(own, guids, firstLevel, #rows)) do
                if pages[group] then
                    allowed[rows[i].id] = group
                end
            end
            return allowed
        end

        if pages == nil then
            local basePick = FillBase(hero, stepid, log)
            if basePick ~= nil then
                picks[#picks+1] = basePick
            end
        end

        --Remove stale picks so their rows can be filled again.
        local rows = Build.hero.Wrappers(hero, stepid)
        local allowed = Allowed(rows)
        local removed = false
        for _,row in ipairs(rows) do
            local wrapper = row.wrapper
            local optionsKeyed = wrapper:GetOptionsKeyed()
            for _,id in ipairs(wrapper:GetSelected()) do
                if (allowed == nil or allowed[row.id]) and not IsBlankId(id) and optionsKeyed[id] == nil then
                    Build.hero.Unchoose(hero, stepid, row.id, id)
                    removed = true
                    picks[#picks+1] = string.format("%s -> removed a pick no longer offered", wrapper:GetName() or "?")
                    Log{op = "unchoose", row = row.id, id = id, label = wrapper:GetName(), level = tonumber(wrapper:try_get("level")) or 0, removes = true}
                end
            end
        end

        --One pick at a time, rebuilding the rows after each, so a pick that
        --reveals new choices (a subclass, an ability with options) gets those
        --filled too. A row that refuses a pick is not tried again.
        local stuck = {}
        ---@type nil|{rowid: string, before: number, description: string, entry: nil|table}
        local pending = nil
        ---@type nil|HeroBuildRow[]
        local current = rows
        if removed then
            current = nil
        end
        for pass = 1, MAX_FILL_PICKS + 1 do
            current = current or Build.hero.Wrappers(hero, stepid)
            if pending ~= nil then
                --Progress means the row gained a pick, or went away. It is read
                --from this pass's rows: building them is Fill's slow part.
                local after = nil
                for _,row in ipairs(current) do
                    if row.id == pending.rowid then
                        after = row.wrapper
                        break
                    end
                end
                if after == nil or after:GetSelectedValue() > pending.before then
                    picks[#picks+1] = pending.description
                    Log(pending.entry)
                else
                    stuck[pending.rowid] = true
                end
                pending = nil
            end
            if pass > MAX_FILL_PICKS then
                break
            end
            local open = Allowed(current)
            for _,row in ipairs(FillOrder(current)) do
                local rowid = row.id
                if not stuck[rowid] and (open == nil or open[rowid]) and not RowStatus(hero, row).complete then
                    local before = row.wrapper:GetSelectedValue()
                    local description, entry = FillOnePick(hero, row)
                    if description ~= nil then
                        --Level up names each choice under its page's pill.
                        if entry ~= nil and open ~= nil then
                            entry.page = open[rowid]
                        end
                        pending = {rowid = rowid, before = before, description = description, entry = entry}
                        break
                    end
                    stuck[rowid] = true
                end
            end
            if pending == nil then
                break
            end
            current = nil
        end

        --Level up: the pages' skill and language choices too, after the
        --class picks that may bring them; earlier Levels' open ones stay open.
        if pages ~= nil and stepid == "class" then
            local only = {}
            for guid,key in pairs(Build.hero.PoolPages(hero)) do
                if pages[key] then
                    only[guid] = key
                end
            end
            if next(only) ~= nil then
                for _,kind in ipairs({"skill", "language"}) do
                    for _,pick in ipairs(Build.hero.FillPools(hero, kind, log, only)) do
                        picks[#picks+1] = pick
                    end
                end
            end
        end

        return picks
    end

    --What Fill would do to these steps, without doing it: Fill runs on a copy
    --of the hero and records each change. Returns the changes in order, and
    --the copy as Fill leaves it (the Builder names the rows from it).
    ---@param hero character
    ---@param stepids string[]
    ---@param pages nil|table<integer, boolean> Level up: only the class rows on these pages (see Fill)
    ---@return HeroBuildFillEntry[] entries
    ---@return character copy
    function Build.hero.PlanFill(hero, stepids, pages)
        local copy = DeepCopy(hero) --[[@as character]]
        local log = {}
        for _,stepid in ipairs(stepids) do
            Build.hero.Fill(copy, stepid, log, pages)
        end
        return log, copy
    end

    --Defined with Skills & Languages below; ApplyFill places pool picks too.
    local MatchPools, CurrentPicks, StorePoolPicks

    --Make PlanFill's changes on the hero. Run it inside one save, so one Undo
    --puts them all back. Each change finds its row and option again by id,
    --so one that no longer fits is skipped. Returns how many choices were
    --filled, removals not counted.
    ---@param hero character
    ---@param entries HeroBuildFillEntry[]
    ---@return integer
    function Build.hero.ApplyFill(hero, entries)
        local filled = 0
        --each kind's pools, kept across a run of skill or language picks (a
        --pick changes only the pools' picks, kept in step below); any other
        --kind of pick can change the pools, so it drops them.
        local poolsByKind = {}
        for _,entry in ipairs(entries) do
            local op = entry.op
            local done = true
            if op ~= "pool" then
                poolsByKind = {}
            end
            if op == "ancestry" then
                Build.hero.SetAncestry(hero, entry.id)
            elseif op == "culture" then
                Build.hero.SetCultureAggregate(hero, entry.id)
            elseif op == "career" then
                Build.hero.SetCareer(hero, entry.id)
            elseif op == "class" then
                Build.hero.SetClass(hero, entry.id)
            elseif op == "array" then
                Build.hero.SetCharacteristics(hero, entry.index, nil)
            elseif op == "choose" then
                done = Build.hero.Choose(hero, entry.step, entry.row, entry.id)
            elseif op == "unchoose" then
                Build.hero.Unchoose(hero, entry.step, entry.row, entry.id)
            elseif op == "pool" then
                local pools = poolsByKind[entry.kind]
                if pools == nil then
                    pools = Build.hero.Pools(hero, entry.kind)
                    poolsByKind[entry.kind] = pools
                end
                local items, prefer = CurrentPicks(pools)
                local held = false
                for _,pool in ipairs(pools) do
                    for _,id in ipairs(pool.selected) do
                        if id == entry.id then
                            held = true
                        end
                    end
                end
                done = false
                local target = nil
                for _,pool in ipairs(pools) do
                    if pool.guid == entry.pool then
                        target = pool
                    end
                end
                if not held and target ~= nil then
                    if #target.selected < target.capacity and target.allowed[entry.id] then
                        target.selected[#target.selected+1] = entry.id
                        hero:GetLevelChoices()[target.guid] = target.selected
                        hero:Invalidate()
                        done = true
                    end
                elseif not held and entry.pool == nil then
                    --as TogglePoolPick then SetPoolPicks, on the kept pools.
                    items[#items+1] = entry.id
                    local placed = MatchPools(pools, items, prefer)
                    if placed ~= nil then
                        StorePoolPicks(hero, pools, items, placed)
                        hero:Invalidate()
                        done = true
                    end
                end
            elseif op == "uncomplicate" then
                if hero:try_get("complications", {})[entry.id] then
                    Build.hero.ToggleComplication(hero, entry.id)
                end
            end
            if done and not entry.removes then
                filled = filled + 1
            end
        end
        return filled
    end

    --------------------------------------------------------------------------
    --Skills & Languages: every skill (or language) choice from every step is a
    --"pool": a number of picks, each from an allowed set. The player picks
    --skills, not pools: a matching (augmenting paths, as in bipartite
    --matching) decides which pool each pick fills, so a pick that fits two
    --pools never blocks a later one that only fits one of them. A skill is
    --offered when the picks so far plus that skill can still all be placed.
    --------------------------------------------------------------------------

    --The pools of one kind: { {rowid, guid, source, name, description,
    --capacity, allowed = {id = true}, selected = {id...}, wrapper,
    --quickBuild = {id = true}}... }
    ---@param hero character
    ---@param kind string "skill" or "language"
    ---@return table[]
    function Build.hero.Pools(hero, kind)
        local visibleSkills = kind == "skill" and (Skill.SkillsById or {}) or nil
        local pools = {}
        for _,row in ipairs(Build.hero.Wrappers(hero, "skills")) do
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
                    owner = row.owner,
                    name = wrapper:GetName(),
                    description = description,
                    capacity = wrapper:GetNumChoices(),
                    allowed = allowed,
                    selected = selected,
                    wrapper = wrapper,
                    quickBuild = Build.QuickBuildIds(wrapper:GetFeature()),
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
    function MatchPools(pools, items, prefer)
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
    function CurrentPicks(pools)
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

    --Store each pool's share of the picks as that pool's picks, and keep the
    --pools' `selected` in step. `placed` maps each pick to its pool's index,
    --as MatchPools returns it.
    ---@param hero character
    ---@param pools table[]
    ---@param items string[]
    ---@param placed table<string, integer>
    function StorePoolPicks(hero, pools, items, placed)
        local levelChoices = hero:GetLevelChoices()
        local byPool = {}
        for _,id in ipairs(items) do
            local poolIndex = placed[id]
            local list = byPool[poolIndex] or {}
            list[#list+1] = id
            byPool[poolIndex] = list
        end
        for i,pool in ipairs(pools) do
            levelChoices[pool.guid] = byPool[i] or {}
            pool.selected = byPool[i] or {}
        end
    end

    --Every skill (or language) as {id, item}: skills in the game's skill
    --order, languages sorted by name. The screen and Fill walk the same order,
    --so the same random rolls pick the same ones.
    --The name to show for a skill or language: languages follow the Plain
    --Language Names setting.
    ---@param kind string "skill" or "language"
    ---@param item table
    ---@return string
    local function ItemName(kind, item)
        if kind == "language" then
            return (item --[[@as Language]]):DisplayName()
        end
        return item.name
    end

    ---@param kind string "skill" or "language"
    ---@return {id: string, item: table}[]
    local function AllOfKind(kind)
        local result = {}
        if kind == "skill" then
            for _,item in ipairs(Skill.SkillsInfo or {}) do
                result[#result+1] = { id = item.id, item = item }
            end
        else
            for id,item in pairs(dmhub.GetTableVisible(Language.tableName) or {}) do
                result[#result+1] = { id = id, item = item }
            end
            table.sort(result, function(left, right) return ItemName(kind, left.item) < ItemName(kind, right.item) end)
        end
        return result
    end

    --The picks with one more added: what MatchPools is asked to test whether
    --that one still fits.
    ---@param items string[]
    ---@param id string
    ---@return string[]
    local function WithPick(items, id)
        local result = {}
        for _,other in ipairs(items) do
            result[#result+1] = other
        end
        result[#result+1] = id
        return result
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
            --a pooled native language is one of the pools' picks, not known apart from them.
            local native = not options.nativeLanguagePooled and (hero:GetLevelChoices() or {})[Build.NATIVE_LANGUAGE_GUID] or nil
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
                if subtype == kind and (source == nil or not poolGuids[source]) and source ~= Build.NATIVE_LANGUAGE_GUID then
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
                    local name = mod:try_get("name") or T("builder.skills.special_fallback")
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
                item = Build.hero.Ancestry(hero)
            elseif stepid == "career" then
                item = Build.hero.Career(hero)
            elseif stepid == "class" then
                item = hero:GetClass()
            elseif stepid == "complication" then
                local ids = Build.hero.ComplicationIds(hero)
                item = ids[1] and Visible(CharacterComplication.tableName)[ids[1]] or nil
            elseif stepid == "culture" then
                local culture = hero:try_get("culture")
                local aggregate = culture and culture:try_get("aggregate") or nil
                item = aggregate and aggregate ~= "" and Visible(Culture.tableName)[aggregate] or nil
            end
            return item and item.name or nil
        end
        local result = {}
        for _,stepid in ipairs(Build.POOL_SOURCE_STEPS) do
            local grants = Build.hero.StepGrants(hero, stepid)
            local name = ItemName(stepid)
            local stepName = string.lower(SourceInfo(stepid).title)
            local phrase = T("builder.skills.source.step", { step = stepName })
            if name ~= nil then
                phrase = T("builder.skills.source.step_item", { step = stepName, item = name })
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
    function Build.hero.SetPoolPicks(hero, kind, items)
        local pools = Build.hero.Pools(hero, kind)
        local _, prefer = CurrentPicks(pools)
        local assignment = MatchPools(pools, items, prefer)
        if assignment == nil then
            return false
        end
        StorePoolPicks(hero, pools, items, assignment)
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
    function Build.hero.PoolTable(hero, kind)
        local pools = Build.hero.Pools(hero, kind)
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

        local entries = {}
        local native = nil
        for _,row in ipairs(AllOfKind(kind)) do
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
                if MatchPools(pools, WithPick(items, id), prefer) ~= nil then
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
                source = T("builder.skills.source.culture")
            elseif state == "fixed" then
                source = sources[id]
            end
            entries[#entries+1] = {
                id = id,
                name = ItemName(kind, item),
                --plain read: try_get skips the "crafting" type default, which most
                --crafting skills rely on rather than storing it
                category = kind == "skill" and item.category or nil,
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
    function Build.hero.TogglePoolPick(hero, kind, id)
        local pools = Build.hero.Pools(hero, kind)
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
        return Build.hero.SetPoolPicks(hero, kind, result)
    end

    --Fill every pool of a kind: add offerable picks until no pool has room or
    --nothing more fits. The main game takes a Quick Build pick first, then a
    --skill the Hero has an edge with; otherwise the picks are random.
    --Returns "Name" strings for the picks made; with a log, each goes into it.
    ---@param hero character
    ---@param kind string
    ---@param log nil|HeroBuildFillEntry[]
    ---@param only nil|table<string, integer> Level up: fill only these choices (guid to Level up page); every other keeps the picks it has
    ---@return string[]
    function Build.hero.FillPools(hero, kind, log, only)
        local picks = {}
        --the pools, what the Hero knows outright and their edged skills are
        --worked out once: a pick changes none of them.
        local pools = Build.hero.Pools(hero, kind)
        --Level up fills only its page's choices: the others leave the
        --matching (so their picks never move) and their picks count as taken.
        local taken = {}
        if only ~= nil then
            local kept = {}
            for _,pool in ipairs(pools) do
                if only[pool.guid] ~= nil then
                    kept[#kept+1] = pool
                else
                    for _,id in ipairs(pool.selected) do
                        taken[id] = true
                    end
                end
            end
            pools = kept
        end
        local fixed = FixedKnown(hero, kind, pools)
        local benefits = kind == "skill" and SkillBenefits(hero) or {}
        local source = AllOfKind(kind)
        local changed = false
        for _ = 1, MAX_FILL_PICKS do
            local items, prefer = CurrentPicks(pools)
            local picked = {}
            for _,id in ipairs(items) do
                picked[id] = true
            end
            local assignment = MatchPools(pools, items, prefer) or {}
            local used = {}
            for _,poolIndex in pairs(assignment) do
                used[poolIndex] = (used[poolIndex] or 0) + 1
            end
            local room = false
            --the Quick Build picks of the pools that still have room
            local quick = {}
            for i,pool in ipairs(pools) do
                if pool.capacity - (used[i] or 0) > 0 then
                    room = true
                    for id,_ in pairs(pool.quickBuild) do
                        quick[id] = true
                    end
                end
            end
            if not room then
                break
            end
            local candidates, quickOnes, edged = {}, {}, {}
            for _,row in ipairs(source) do
                local id = row.id
                if fixed[id] == nil and not picked[id] and not taken[id] then
                    if MatchPools(pools, WithPick(items, id), prefer) ~= nil then
                        local candidate = { id = id, name = ItemName(kind, row.item), special = benefits[id] }
                        candidates[#candidates+1] = candidate
                        if quick[id] then
                            quickOnes[#quickOnes+1] = candidate
                        elseif candidate.special ~= nil then
                            edged[#edged+1] = candidate
                        end
                    end
                end
            end
            local entry = nil
            local quickBuild = false
            if options.mainFill then
                entry = RandomOf(quickOnes)
                quickBuild = entry ~= nil
                entry = entry or RandomOf(edged)
            end
            entry = entry or RandomOf(candidates)
            if entry == nil then
                break
            end
            --the pick placed with the others, as SetPoolPicks does.
            local withPick = WithPick(items, entry.id)
            local placed = MatchPools(pools, withPick, prefer)
            if placed == nil then
                break
            end
            StorePoolPicks(hero, pools, withPick, placed)
            changed = true
            picks[#picks+1] = string.format("%s -> %s", cond(kind == "skill", "Skill", "Language"), entry.name)
            if log ~= nil then
                local logged = {step = "skills", op = "pool", kind = kind, id = entry.id, name = entry.name, quickBuild = quickBuild}
                if only ~= nil then
                    local target = pools[placed[entry.id]]
                    logged.pool = target.guid
                    logged.page = only[target.guid]
                end
                log[#log+1] = logged
            end
        end
        if changed then
            hero:Invalidate()
        end
        return picks
    end

    --What a step grants in skills and languages, for the info box on its page:
    --  { fixed = {"Sneak (skill)"...}, pools = {{name, description, kind}...} }
    --fixed = granted outright; pools = choices made on the Skills & Languages
    --step. The culture's native language is a row of its own and not listed,
    --unless the engine pools it.
    ---@param hero character
    ---@param stepid string
    ---@return table
    function Build.hero.StepGrants(hero, stepid)
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
                    result.pools[#result.pools+1] = { name = feature:try_get("name") or T("builder.grants.choice_fallback"), description = description, kind = kind }
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
                                    result.fixed[#result.fixed+1] = T("builder.grants.fixed_skill", { name = skills[id].name })
                                    result.fixedIds[id] = true
                                elseif subtype == "language" and languages[id] ~= nil then
                                    result.fixed[#result.fixed+1] = T("builder.grants.fixed_language", { name = languages[id]:DisplayName() })
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
            undoable = options.undoable ~= false,
            execute = function()
                local hero = token.properties --[[@as character]]
                result = fn(hero)
                if options.treasureOnPick then
                    Build.hero.SyncTreasureGrants(hero, token)
                end
            end,
        }
        return result
    end

    --Give the hero their picked grant treasure (see SyncTreasureGrants). Call
    --it INSIDE the caller's own token:ModifyProperties.
    ---@param token CharacterToken
    function Build.SyncTreasureGrants(token)
        Build.hero.SyncTreasureGrants(token.properties --[[@as character]], token)
    end

    ---@param token CharacterToken
    ---@param stepid string
    ---@return table
    function Build.StepStatus(token, stepid)
        return Build.hero.StepStatus(token, token.properties --[[@as character]], stepid)
    end

    --The Levels Level up has a page for (Build.hero.LevelsWaiting): what the
    --sheet's Finish Level N asks before it opens Level up or the Builder.
    ---@param token CharacterToken
    ---@return {level: integer, left: integer, choices: integer}[]
    function Build.LevelsWaiting(token)
        return Build.hero.LevelsWaiting(token.properties --[[@as character]])
    end

    --The status of the whole build:
    --  { complete, steps = {stepStatus...}, incomplete = {stepid...} }
    --`complete` is what Finish needs: every step complete.
    ---@param token CharacterToken
    ---@return table
    function Build.Status(token)
        local steps = {}
        local incomplete = {}
        for _,step in ipairs(Build.STEPS) do
            local status = Build.StepStatus(token, step.id)
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
    function Build.SetAncestry(token, raceid)
        Modify(token, "Choose ancestry", function(hero) Build.hero.SetAncestry(hero, raceid) end)
    end

    ---@param token CharacterToken
    ---@param careerid string
    function Build.SetCareer(token, careerid)
        Modify(token, "Choose career", function(hero) Build.hero.SetCareer(hero, careerid) end)
    end

    ---@param token CharacterToken
    ---@param classid string
    function Build.SetClass(token, classid)
        Modify(token, "Choose class", function(hero) Build.hero.SetClass(hero, classid) end)
    end

    ---@param token CharacterToken
    ---@param cultureid string
    function Build.SetCultureAggregate(token, cultureid)
        Modify(token, "Choose culture", function(hero) Build.hero.SetCultureAggregate(hero, cultureid, false) end)
    end

    ---@param token CharacterToken
    ---@param category string
    ---@param aspectid string
    function Build.SetCultureAspect(token, category, aspectid)
        Modify(token, "Choose culture aspect", function(hero) Build.hero.SetCultureAspect(hero, category, aspectid) end)
    end

    --complicationid nil means "no complication", which completes the step.
    ---@param token CharacterToken
    ---@param complicationid string|nil
    function Build.SetComplication(token, complicationid)
        Modify(token, "Choose complication", function(hero) Build.hero.SetComplication(hero, complicationid) end)
    end

    ---@param token CharacterToken
    function Build.ClearComplication(token)
        Modify(token, "Clear complication", function(hero) Build.hero.ClearComplication(hero) end)
    end

    ---@param token CharacterToken
    ---@param arrayIndex integer
    ---@param build table<string, integer>|nil
    function Build.SetCharacteristics(token, arrayIndex, build)
        Modify(token, "Choose characteristics", function(hero) Build.hero.SetCharacteristics(hero, arrayIndex, build) end)
    end

    ---@param token CharacterToken
    ---@param stepid string
    ---@param rowid string
    ---@param optionId string
    ---@return boolean saved
    function Build.Choose(token, stepid, rowid, optionId)
        return Modify(token, "Make a choice", function(hero) return Build.hero.Choose(hero, stepid, rowid, optionId) end) == true
    end

    ---@param token CharacterToken
    ---@param stepid string
    ---@param rowid string
    ---@param optionId string
    function Build.Unchoose(token, stepid, rowid, optionId)
        Modify(token, "Remove a choice", function(hero) Build.hero.Unchoose(hero, stepid, rowid, optionId) end)
    end

    ---@param token CharacterToken
    ---@param kind string "skill" or "language"
    ---@return table
    function Build.PoolTable(token, kind)
        return Build.hero.PoolTable(token.properties --[[@as character]], kind)
    end

    ---@param token CharacterToken
    ---@param kind string
    ---@param id string
    ---@return boolean changed
    function Build.TogglePoolPick(token, kind, id)
        return Modify(token, "Choose a skill or language", function(hero) return Build.hero.TogglePoolPick(hero, kind, id) end) == true
    end

    ---@param token CharacterToken
    ---@param stepid string
    ---@return table
    function Build.StepGrants(token, stepid)
        return Build.hero.StepGrants(token.properties --[[@as character]], stepid)
    end

    ---@param token CharacterToken
    ---@param stepid string
    ---@return boolean
    function Build.HasDependentPicks(token, stepid)
        return Build.hero.HasDependentPicks(token.properties --[[@as character]], stepid)
    end

    --The picture the builder last set (the class's or ancestry's default art),
    --so it only ever replaces its own picture: any other portrait is the
    --player's. true is the older mark, which did not keep the picture; false or
    --nil: the player picked one, or a Hero from before the mark.
    Build.AUTO_PORTRAIT_FIELD = "eotwAutoPortrait"

    --Set the hero's portrait. auto: the builder is applying a default, not the
    --player choosing. The separate off-token portrait (the hero card's art, set
    --from the full character sheet) is cleared so the card shows this one too.
    ---@param token CharacterToken
    ---@param imageid string
    ---@param auto? boolean
    function Build.SetPortrait(token, imageid, auto)
        token.portrait = imageid
        token.offTokenPortrait = ""
        token:UploadAppearance()
        local hero = token.properties --[[@as character]]
        local mark = auto == true and imageid or false
        if hero:try_get(Build.AUTO_PORTRAIT_FIELD) ~= mark then
            Modify(token, "Portrait", function(h) h[Build.AUTO_PORTRAIT_FIELD] = mark end)
        end
    end

    --Portraits already checked against every class's and ancestry's art (for
    --the older true mark): true when one of them uses it.
    local isDefaultArt = {}

    --The class's art (the ancestry's before a class) when the Hero's portrait
    --should follow it, else nil. It follows while the portrait is unset or is
    --still the picture the builder set. Any other picture is the player's,
    --however it was picked, and a Hero with no mark is never changed.
    ---@param token CharacterToken
    ---@return nil|string
    function Build.FollowedPortrait(token)
        local hero = token.properties --[[@as character]]
        local classItem = hero:GetClass()
        local race = Build.hero.Ancestry(hero)
        local art = ""
        if classItem ~= nil then
            art = classItem:try_get("portraitid", "")
        elseif race ~= nil then
            art = race:try_get("portraitid", "")
        end
        local current = token.portrait
        if art == "" or current == art then
            return nil
        end
        if not Build.PortraitIsSet(current) then
            return art
        end
        local mark = hero:try_get(Build.AUTO_PORTRAIT_FIELD)
        if mark == current then
            return art
        end
        if mark ~= true then
            return nil
        end
        --the older mark kept no picture: follow only while the portrait is
        --still some class's or ancestry's art, not one the player chose since.
        if isDefaultArt[current] == nil then
            isDefaultArt[current] = false
            for _,tableName in ipairs({ Class.tableName, Race.tableName }) do
                for _,item in pairs(Visible(tableName)) do
                    if item:try_get("portraitid", "") == current then
                        isDefaultArt[current] = true
                    end
                end
            end
        end
        return isDefaultArt[current] and art or nil
    end

    ---@param token CharacterToken
    ---@param stepid string
    ---@param rowid string
    ---@return table[]|nil options
    ---@return table|nil info
    function Build.RowOptions(token, stepid, rowid)
        return Build.hero.RowOptions(token.properties --[[@as character]], stepid, rowid)
    end

    ---@param token CharacterToken
    ---@param stepid string
    ---@return table<string, {options: table[], info: table}> rows
    ---@return {guid: string, kind: string, feature: table, capacity: integer, selected: string[], owner: nil|string, level: integer}[] pools
    function Build.AllRowOptions(token, stepid)
        return Build.hero.AllRowOptions(token.properties --[[@as character]], stepid)
    end

    --Whether nothing at all has been chosen yet: no main pick on any step, no
    --name and no portrait. A builder closed in this state leaves no draft.
    ---@param token CharacterToken
    ---@return boolean
    function Build.IsUnstarted(token)
        local hero = token.properties --[[@as character]]
        if Build.hero.Ancestry(hero) ~= nil or Build.hero.Career(hero) ~= nil or hero:GetClass() ~= nil then
            return false
        end
        if #Build.hero.ComplicationIds(hero) > 0 or Build.hero.ChoseNoComplication(hero) then
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
        return not Build.PortraitIsSet(token.portrait)
    end

    --A name from the ancestry's name generator, or nil when it has none.
    ---@param hero character
    ---@return string|nil
    function Build.GenerateName(hero)
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

    --The hero functions that only read. Every other one counts as a write
    --while it runs (see Build.Cached), so a new function is safe by default.
    local READERS = {
        Ancestry = true, Career = true, Class = true, ComplicationIds = true, ChoseNoComplication = true,
        Wrappers = true, StepStatus = true, KeptPicks = true, Rung = true, SlowStartStep = true,
        FirstLevelPages = true, PageFeatures = true, LevelsWaiting = true, HasDependentPicks = true,
        RowOptions = true, AllRowOptions = true, LevelUnseen = true, Pools = true, PoolTable = true,
        StepGrants = true, LevelRows = true, PoolPages = true, ManualLevel = true,
    }
    for name, fn in pairs(Build.hero) do
        if not READERS[name] and type(fn) == "function" then
            Build.hero[name] = function(...)
                g_writing = g_writing + 1
                local result = table.pack(pcall(fn, ...))
                g_writing = g_writing - 1
                if g_rowsMemo ~= nil then
                    g_rowsMemo = setmetatable({}, { __mode = "k" })
                end
                if not result[1] then
                    error(result[2], 0)
                end
                return table.unpack(result, 2, result.n)
            end
        end
    end

    return Build
end

--The main game's engine: every complication its prerequisites allow, as
--many as the player takes, writes undoable.
HeroBuild.main = HeroBuild.Create{
    undoable = true,
    nativeLanguagePooled = true,
    mainFill = true,
}

--A respite can raise the Level; note the Level the Hero was at (levelUpSeen)
--so Level up shows each new one, even one with nothing to choose. A Hero who
--already has a note keeps it.

--On a reload of only this file, wrap the original Rest again, not this wrapper.
local g_baseRest = creature.Rest
if g_baseRest == rawget(_G, "g_heroBuildRestWrapper") then
    g_baseRest = rawget(_G, "g_heroBuildBaseRest")
end
rawset(_G, "g_heroBuildBaseRest", g_baseRest)
function creature:Rest(restType, keepOngoingEffects, keepLevel)
    local before = self:CharacterLevel()
    g_baseRest(self, restType, keepOngoingEffects, keepLevel)
    if self:CharacterLevel() > before and self:try_get("levelUpSeen") == nil then
        self.levelUpSeen = before
    end
end
rawset(_G, "g_heroBuildRestWrapper", creature.Rest)
