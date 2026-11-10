local mod = dmhub.GetModLoading()

--The Skills & Languages component: a Hero's skill or language choices as
--rows (Your choices) beside every skill or language as a chip. The Hero
--sheet's Skills and Languages windows and the Builder's Skills & Languages
--step use it.
--
--It works on a draft: Read takes the Hero as it is, clicks change only the
--draft, and Apply writes the draft back (inside one save). The rules for
--which choice a pick fills come from the build engine (HeroBuild, in
--Draw Steel V/HeroBuildPools.lua): its pools are the grant rows.
--
--  * A grant row is one skill or language choice (a career's skill...).
--    Clicking a skill grant row selects it: the chips then show only what
--    it offers. Language grants take any language, so they do not.
--  * Skills and languages added by hand have rows of their own, saved as
--    the older Skills dialog saves them: a skill as a custom feature, a
--    language in innateLanguages.
--  * A skill granted twice outright gets an open row for a replacement,
--    saved as a "Duplicate Skill" feature, as the older dialog does.

local T = UIText.T

HeroSkillsLanguages = rawget(_G, "HeroSkillsLanguages") or {}

--The names the older Skills dialog (Draw Steel V/SkillsDialog.lua) gives
--the features a hand-added skill is saved as: the Features list shows them.
local HAND_FEATURE = "New Skill"
local DUPLICATE_FEATURE = "Duplicate Skill"

--The words a feature's source ends in ("Warden Career Feature"), and the
--step each names in a row's title.
local SOURCE_KINDS = {
    Ancestry = "Ancestry",
    Race = "Ancestry",
    Culture = "Culture",
    Career = "Career",
    Background = "Career",
    Class = "Class",
    Kit = "Kit",
    Title = "Title",
    Perk = "Perk",
    Complication = "Complication",
}

--The order the band's Skills card names where skills come from.
local KIND_ORDER = {"Ancestry", "Culture", "Career", "Class", "Subclass", "Complication", "Kit", "Title", "Perk"}

--What rows and the band's cards call each step (the kinds above, and
--Everyone for the rules' own).
local KIND_WORDS = {
    Ancestry = T("heroskills.kind.ancestry"),
    Culture = T("heroskills.kind.culture"),
    Career = T("heroskills.kind.career"),
    Class = T("heroskills.kind.class"),
    Subclass = T("heroskills.kind.subclass"),
    Complication = T("heroskills.kind.complication"),
    Kit = T("heroskills.kind.kit"),
    Title = T("heroskills.kind.title"),
    Perk = T("heroskills.kind.perk"),
    Everyone = T("heroskills.kind.everyone"),
}

--- A kind's words; anything else (an item's name) as it is.
--- @param kind string
--- @return string
local function KindWord(kind)
    return KIND_WORDS[kind] or kind
end

local NUMBER_WORDS = {
    T("heroskills.number.one"),
    T("heroskills.number.two"),
    T("heroskills.number.three"),
    T("heroskills.number.four"),
    T("heroskills.number.five"),
    T("heroskills.number.six"),
}

--- "A, B and C" (or "A, B or C").
--- @param list string[]
--- @param last string " and " or " or "
--- @return string
local function JoinList(list, last)
    if #list <= 1 then
        return list[1] or ""
    end
    return table.concat(list, ", ", 1, #list - 1) .. last .. list[#list]
end

--- "A" or "An" for the word that follows.
--- @param word string
--- @return string
local function Article(word)
    if string.find(string.lower(word), "^[aeiou]") then
        return T("heroskills.article.an")
    end
    return T("heroskills.article.a")
end

--- @param n integer
--- @return string
local function NumberWord(n)
    return NUMBER_WORDS[n] or tostring(n)
end

--- Split a feature's source text into the item's name and the step it
--- belongs to: "Warden Career Feature" gives "Warden", "Career". A source
--- that names no step ("Character", "Item") gives the text and nil.
--- @param source any
--- @return nil|string name
--- @return nil|string kind
local function ParseSource(source)
    if type(source) ~= "string" or source == "" then
        return nil, nil
    end
    local text = string.gsub(source, " Feature$", "")
    local name, word = string.match(text, "^(.-)%s+(%a+)$")
    if name ~= nil and name ~= "" and SOURCE_KINDS[word] ~= nil then
        return name, SOURCE_KINDS[word]
    end
    return text, nil
end

--- What a grant row comes from: the item and its step, as the choice's
--- source text names them, or else the complication the build engine names
--- (a complication's choices say only "Feat"). The culture's own language
--- choice is the Culture's.
--- @param feature table the choice
--- @param owner nil|string the complication granting it, from the engine's pool
--- @param engine nil|HeroBuildEngine the build rules the row was read with; nil for the main game's
--- @return nil|string name
--- @return nil|string step
local function RowSource(feature, owner, engine)
    local guid, source = nil, nil
    pcall(function()
        guid = feature:try_get("guid")
        source = feature:try_get("source")
    end)
    if guid == (engine or HeroBuild.main).NATIVE_LANGUAGE_GUID then
        return KindWord("Culture"), "Culture"
    end
    local name, step = ParseSource(source)
    if step == nil and owner ~= nil then
        return owner, SOURCE_KINDS.Complication
    end
    return name, step
end

--- @param modifier CharacterModifier
--- @param key string
--- @return any
local function ModField(modifier, key)
    local value = nil
    pcall(function() value = modifier:try_get(key) end)
    return value
end

--- Where an outright grant comes from, as its source names it: the item
--- ("Warden", "Tactician"), Everyone for the rules' own (Caelian), or the
--- modifier's name when the source names no item ("Item", "Character").
--- @param modifier CharacterModifier
--- @return string name
--- @return nil|string kind the step, for the band's cards
local function GrantSource(modifier)
    local source = ModField(modifier, "source")
    if type(source) == "string" and string.find(source, "Global Rule", 1, true) ~= nil then
        return T("heroskills.kind.everyone"), "Everyone"
    end
    local name, kind = ParseSource(source)
    if kind ~= nil and name ~= nil then
        return name, kind
    end
    local modName = ModField(modifier, "name")
    if type(modName) == "string" and modName ~= "" then
        return modName, nil
    end
    return name or T("heroskills.source.unknown"), nil
end

----------------------------------------------------------------------
--Reading a Hero.

--- @class HeroSkillsRow
--- @field key string "g1", "h2"...: names the row while the window is open
--- @field title string "Career: Warden", "Added by hand"
--- @field item string what a skill held by this row is "from" ("Warden")
--- @field kind nil|string the step the row comes from ("Career"), for the band's cards
--- @field line string the line under the title ("An exploration skill")
--- @field capacity integer how many it takes
--- @field allowed nil|table<string, boolean> a grant's options; nil takes anything
--- @field picks string[] the ids it holds now
--- @field grant boolean a choice from the build (else added by hand)
--- @field guid nil|string a grant: its choice guid; a hand skill: its feature's guid
--- @field orig string[] a grant's picks as read
--- @field dup nil|boolean a replacement for a skill granted twice
--- @field level nil|integer a grant: the class Level it comes at (0 when none)

--- @class HeroSkillsEntry
--- @field id string
--- @field name string
--- @field group nil|string a skill's group id ("crafting")
--- @field speakers nil|string a language's speakers
--- @field inWorld nil|string a language's in-world name, set only while Plain Language Names shows another name
--- @field tooltip nil|string a language's hover text naming it in-world
--- @field dead nil|boolean a dead language

--- @class HeroSkillsMark
--- @field suffix nil|string the effect on the chip ("edge", "tier 3")
--- @field lines string[] its hover, one line per feature

--- @class HeroSkillsDraft
--- @field kind string "skill" or "language"
--- @field grants HeroSkillsRow[]
--- @field hand HeroSkillsRow[] added by hand, and the open Duplicate skill rows
--- @field known table<string, string> id -> where it comes from, for what the Hero has outright (the first source)
--- @field knownAll table<string, string[]> id -> every place it comes from ("Warden", "Fury")
--- @field knownKind table<string, string> id -> the step it comes from ("Ancestry", "Everyone"), for the band's cards
--- @field duplicates string[] a skill's name once for every extra outright grant of it
--- @field entries HeroSkillsEntry[] every skill or language, in chip order
--- @field marks table<string, HeroSkillsMark>
--- @field quickBuild table<string, boolean> the ids some grant row's Quick Build takes
--- @field handOrig table<string, string> a hand row's feature guid (skills) or language id -> the id it held
--- @field sel nil|string the selected row's key
--- @field query string the languages' search text
--- @field nextKey integer

--- The skill a hand-added feature gives, or nil when the feature is not
--- one: a custom feature with one skill proficiency and nothing else, as
--- the older Manage Skill Selections and this window make them. A custom
--- feature with more in it is left alone and its skill counts as known.
--- @param feature CharacterFeature
--- @return nil|string
local function HandSkillId(feature)
    local mods = feature:try_get("modifiers", {})
    if #mods ~= 1 then
        return nil
    end
    local modifier = mods[1]
    local ok, behavior = pcall(function() return modifier.behavior end)
    if not ok or behavior ~= "proficiency" or ModField(modifier, "subtype") ~= "skill" then
        return nil
    end
    local found = nil
    for id, on in pairs(ModField(modifier, "skills") or {}) do
        if on then
            if found ~= nil then
                return nil
            end
            found = id
        end
    end
    if found == nil or Skill.SkillsById[found] == nil then
        return nil
    end
    return found
end

--- The line under a grant row's title, from the choice's data: "An
--- exploration skill", "Two skills", "Music, Perform or a crafting skill".
--- @param feature table the choice
--- @param kind string
--- @param capacity integer
--- @return string
local function GrantLine(feature, kind, capacity)
    if kind == "language" then
        if capacity <= 1 then
            return T("heroskills.grant.a_language")
        end
        return T("heroskills.grant.n_languages", {number = NumberWord(capacity)})
    end
    local categories = {}
    pcall(function() categories = feature:try_get("categories", {}) end)
    local groups = {}
    for _, category in ipairs(Skill.categories) do
        if categories[category.id] then
            groups[#groups+1] = string.lower(category.text)
        end
    end
    local individual = {}
    pcall(function() individual = feature:try_get("individualSkills", {}) end)
    local named = {}
    for id, on in pairs(individual or {}) do
        local skill = Skill.SkillsById[id]
        if on and skill ~= nil then
            named[#named+1] = skill.name
        end
    end
    table.sort(named)
    local anything = #groups == #Skill.categories or (#groups == 0 and #named == 0)
    if capacity > 1 then
        if anything or #named > 0 then
            return T("heroskills.grant.n_skills", {number = NumberWord(capacity)})
        end
        return T("heroskills.grant.n_group_skills", {number = NumberWord(capacity), groups = JoinList(groups, T("heroskills.list.or"))})
    end
    if anything then
        return T("heroskills.grant.a_skill")
    end
    if #named == 0 then
        local phrase = JoinList(groups, T("heroskills.list.or"))
        return T("heroskills.grant.a_group_skill", {article = Article(phrase), groups = phrase})
    end
    if #groups == 0 then
        return JoinList(named, T("heroskills.list.or"))
    end
    local phrase = JoinList(groups, T("heroskills.list.or"))
    local list = {}
    for _, skillName in ipairs(named) do
        list[#list+1] = skillName
    end
    list[#list+1] = T("heroskills.grant.a_group_skill", {article = string.lower(Article(phrase)), groups = phrase})
    return JoinList(list, T("heroskills.list.or"))
end

--- A grant row's words for a skill or language choice, as Your choices
--- shows them: what it comes from ("Farmer") and what it takes ("Two
--- exploration skills"). The Builder's pages say what a step grants with them.
--- @param feature table the choice
--- @param kind string "skill" or "language"
--- @param capacity integer how many it takes
--- @param owner nil|string the complication granting it, from the engine's pool
--- @return string item
--- @return string line
function HeroSkillsLanguages.GrantWords(feature, kind, capacity, owner)
    local name = RowSource(feature, owner)
    if name == nil then
        pcall(function() name = feature:try_get("name") end)
    end
    return name or T("heroskills.row.choice"), GrantLine(feature, kind, capacity)
end

--- The skills powers single out: an edge on Flirt, a tier 3 on Lie.
--- @param hero character
--- @return table<string, HeroSkillsMark>
local function SkillMarks(hero)
    local marks = {}
    local behaviorClass = rawget(_G, "ActivatedAbilityPowerRollBehavior")
    local types = behaviorClass ~= nil and behaviorClass.s_modificationTypesById or {}
    --the hover names the effect in a sentence for these three.
    local SENTENCES = {edge = T("heroskills.mark.edge"), double_edge = T("heroskills.mark.double_edge"), bane = T("heroskills.mark.bane")}
    for _, entry in ipairs(hero:GetActiveModifiers()) do
        local modifier = entry.mod
        local ok, behavior = pcall(function() return modifier.behavior end)
        local skills = ok and behavior == "power" and ModField(modifier, "skills") or nil
        if type(skills) == "table" then
            local name = ModField(modifier, "name") or T("heroskills.mark.a_feature")
            local modtype = ModField(modifier, "modtype")
            local info = types[modtype or ""]
            local effect = nil
            if info ~= nil and not info.hideText and modtype ~= "none" and type(info.text) == "string" then
                effect = string.lower(info.text)
            end
            local line
            if SENTENCES[modtype or ""] ~= nil then
                line = T("heroskills.mark.gives", {feature = name, effect = SENTENCES[modtype]})
            else
                local rules = ModField(modifier, "description")
                if type(rules) == "string" and rules ~= "" then
                    line = string.format("%s: %s", name, rules)
                else
                    line = name
                end
            end
            for key, value in pairs(skills) do
                --an array of ids here, but tolerate a set
                local id = cond(type(key) == "number", value, key)
                if type(id) == "string" and Skill.SkillsById[id] ~= nil and value ~= false then
                    local mark = marks[id] or {suffix = nil, lines = {}}
                    marks[id] = mark
                    mark.suffix = mark.suffix or effect
                    mark.lines[#mark.lines+1] = line
                end
            end
        end
    end
    return marks
end

--- Read a Hero's skills or languages into a draft for the component.
--- Slow (it runs the build engine's pools): read once when a window opens,
--- not every frame.
--- @param hero character
--- @param kind string "skill" or "language"
--- @param only nil|table<string, any> Level up: keep only these grant rows (by choice guid); every other row's picks then count as known, and there are no hand rows
--- @param engine nil|HeroBuildEngine the build rules (the Builder host's); nil for the main game's
--- @return HeroSkillsDraft
function HeroSkillsLanguages.Read(hero, kind, only, engine)
    local build = engine or HeroBuild.main
    --- @type HeroSkillsDraft
    local draft = {
        kind = kind,
        grants = {},
        hand = {},
        known = {},
        knownAll = {},
        knownKind = {},
        duplicates = {},
        entries = {},
        marks = {},
        quickBuild = {},
        handOrig = {},
        sel = nil,
        query = "",
        nextKey = 1,
    }
    local function Key(prefix)
        draft.nextKey = draft.nextKey + 1
        return prefix .. tostring(draft.nextKey)
    end

    local mainClass = hero:GetClass()
    local mainClassId = mainClass ~= nil and mainClass.id or nil

    --the grant rows: the build engine's pools of this kind.
    local poolGuids = {}
    for _, pool in ipairs(build.hero.Pools(hero, kind)) do
        local feature = pool.wrapper:GetFeature()
        local name, step = RowSource(feature, pool.owner, build)
        if step == "Class" and feature:try_get("classid") ~= nil and feature:try_get("classid") ~= mainClassId then
            step = "Subclass"
        end
        local item = name or pool.name or T("heroskills.row.choice")
        local title = item
        --"Culture", not "Culture: Culture".
        local stepWord = step ~= nil and KindWord(step) or nil
        if stepWord ~= nil and stepWord ~= item then
            title = string.format("%s: %s", stepWord, item)
        end
        local picks = {}
        for _, id in ipairs(pool.selected) do
            picks[#picks+1] = id
        end
        local orig = {}
        for _, id in ipairs(picks) do
            orig[#orig+1] = id
        end
        poolGuids[pool.guid] = true
        --Level up's block stars only its own choices' Quick Build picks.
        if only == nil or only[pool.guid] ~= nil then
            for id, _ in pairs(pool.quickBuild or {}) do
                draft.quickBuild[id] = true
            end
        end
        draft.grants[#draft.grants+1] = {
            key = Key("g"),
            title = title,
            item = item,
            kind = step,
            line = GrantLine(feature, kind, pool.capacity),
            capacity = pool.capacity,
            allowed = pool.allowed,
            picks = picks,
            grant = true,
            guid = pool.guid,
            orig = orig,
            level = tonumber(pool.wrapper:try_get("level")) or 0,
        }
    end

    --the rows added by hand.
    local handGuids = {}
    if kind == "skill" then
        for _, feature in ipairs(hero:try_get("characterFeatures", {})) do
            local id = HandSkillId(feature)
            if id ~= nil then
                handGuids[feature.guid] = true
                draft.handOrig[feature.guid] = id
                draft.hand[#draft.hand+1] = {
                    key = Key("h"),
                    title = T("heroskills.row.added_by_hand"),
                    item = T("heroskills.row.added_by_hand"),
                    line = T("heroskills.row.custom_feature"),
                    capacity = 1,
                    picks = {id},
                    grant = false,
                    guid = feature.guid,
                    orig = {id},
                    dup = feature.name == DUPLICATE_FEATURE,
                }
            end
        end
    else
        local languages = dmhub.GetTableVisible(Language.tableName) or {}
        local ids = {}
        for id, on in pairs(hero:try_get("innateLanguages", {})) do
            if on and languages[id] ~= nil then
                ids[#ids+1] = id
            end
        end
        table.sort(ids, function(left, right) return languages[left]:DisplayName() < languages[right]:DisplayName() end)
        for _, id in ipairs(ids) do
            draft.handOrig[id] = id
            draft.hand[#draft.hand+1] = {
                key = Key("h"),
                title = T("heroskills.row.added_by_hand"),
                item = T("heroskills.row.added_by_hand"),
                line = T("heroskills.row.custom_feature"),
                capacity = 1,
                picks = {id},
                grant = false,
                orig = {id},
            }
        end
    end

    --what the Hero has outright: proficiencies that are not a grant row's
    --picks or a hand row's, and for languages the culture's own.
    local grantsOf = {}
    for _, entry in ipairs(hero:GetActiveModifiers()) do
        local modifier = entry.mod
        local ok, behavior = pcall(function() return modifier.behavior end)
        if ok and behavior == "proficiency" and ModField(modifier, "subtype") == kind then
            local sourceguid = ModField(modifier, "sourceguid")
            if sourceguid == nil or (not poolGuids[sourceguid] and not handGuids[sourceguid]) then
                local name, step
                if sourceguid == build.NATIVE_LANGUAGE_GUID then
                    name, step = KindWord("Culture"), "Culture"
                else
                    name, step = GrantSource(modifier)
                end
                local ids = ModField(modifier, "skills") or {}
                local all = kind == "skill" and Skill.SkillsById or (dmhub.GetTableVisible(Language.tableName) or {})
                local list = {}
                if ids.all then
                    for id, _ in pairs(all) do
                        list[#list+1] = id
                    end
                else
                    for id, on in pairs(ids) do
                        if on and all[id] ~= nil then
                            list[#list+1] = id
                        end
                    end
                end
                for _, id in ipairs(list) do
                    if draft.known[id] == nil then
                        draft.known[id] = name
                        draft.knownKind[id] = step or name
                    end
                    --every source, so a skill granted twice shows why
                    --("Nature (Warden, Fury)") beside its Duplicate skill row.
                    local names = draft.knownAll[id] or {}
                    draft.knownAll[id] = names
                    local seen = false
                    for _, existing in ipairs(names) do
                        if existing == name then
                            seen = true
                        end
                    end
                    if not seen then
                        names[#names+1] = name
                    end
                    local by = grantsOf[id] or {}
                    grantsOf[id] = by
                    by[sourceguid or name] = true
                end
            end
        end
    end

    if kind == "skill" then
        --a skill granted outright twice: one replacement each extra time
        --(a "Duplicate Skill" row).
        for id, by in pairs(grantsOf) do
            local grantCount = 0
            for _ in pairs(by) do
                grantCount = grantCount + 1
            end
            for _ = 2, grantCount do
                draft.duplicates[#draft.duplicates+1] = Skill.SkillsById[id].name
            end
        end
        table.sort(draft.duplicates)
        local saved = 0
        for _, row in ipairs(draft.hand) do
            if row.dup then
                saved = saved + 1
            end
        end
        for _ = saved + 1, #draft.duplicates do
            draft.hand[#draft.hand+1] = {
                key = Key("h"),
                title = T("heroskills.row.duplicate_skill"),
                item = T("heroskills.row.duplicate_skill"),
                line = "",
                capacity = 1,
                picks = {},
                grant = false,
                orig = {},
                dup = true,
            }
        end

        for _, skill in ipairs(Skill.SkillsInfo) do
            --a plain read: Skill's type default ("crafting") covers the
            --skills whose data leaves the category unset
            draft.entries[#draft.entries+1] = {id = skill.id, name = skill.name, group = skill.category}
        end
        draft.marks = SkillMarks(hero)
    else
        local list = {}
        for id, item in pairs(dmhub.GetTableVisible(Language.tableName) or {}) do
            local speakers = item:try_get("speakers")
            if type(speakers) ~= "string" or speakers == "" then
                speakers = nil
            end
            local inWorld = nil
            if item:DisplayName() ~= item.name then
                inWorld = item.name
            end
            list[#list+1] = {id = id, name = item:DisplayName(), speakers = speakers, inWorld = inWorld, tooltip = item:DisplayTooltip(), dead = item:try_get("dead", false) == true}
        end
        table.sort(list, function(left, right) return left.name < right.name end)
        draft.entries = list
    end
    HeroSkillsLanguages.LabelDuplicates(draft)

    --Level up's block: the other rows' picks are what the Hero knows already.
    if only ~= nil then
        local function Known(id, name)
            if draft.known[id] == nil then
                draft.known[id] = name
                draft.knownKind[id] = name
            end
            local names = draft.knownAll[id] or {}
            draft.knownAll[id] = names
            names[#names+1] = name
        end
        local kept = {}
        for _, row in ipairs(draft.grants) do
            if only[row.guid] ~= nil then
                kept[#kept+1] = row
            else
                for _, id in ipairs(row.picks) do
                    Known(id, row.title)
                end
            end
        end
        for _, row in ipairs(draft.hand) do
            for _, id in ipairs(row.picks) do
                Known(id, row.title)
            end
        end
        draft.grants = kept
        draft.hand = {}
        draft.handOrig = {}
        draft.duplicates = {}
    end

    --Two rows with the same title get their Level added, e.g.
    --"Class: Skills (Level 4)", so they can be told apart.
    local count = {}
    for _, row in ipairs(draft.grants) do
        count[row.title] = (count[row.title] or 0) + 1
    end
    for _, row in ipairs(draft.grants) do
        if count[row.title] > 1 and (row.level or 0) > 0 then
            row.title = T("heroskills.row.title_with_level", {title = row.title, level = string.format("%d", row.level)})
        end
    end
    return draft
end

--- Give the Duplicate skill rows their titles: the i-th names the i-th
--- skill granted twice. A saved replacement left over once the duplicate
--- has gone reads as an ordinary hand-added skill.
--- @param draft HeroSkillsDraft
function HeroSkillsLanguages.LabelDuplicates(draft)
    local i = 0
    for _, row in ipairs(draft.hand) do
        if row.dup then
            i = i + 1
            local name = draft.duplicates[i]
            if name ~= nil then
                row.title = T("heroskills.row.duplicate_skill")
                row.item = T("heroskills.row.duplicate_skill")
                row.line = T("heroskills.row.duplicate_line", {skill = name})
            else
                row.title = T("heroskills.row.added_by_hand")
                row.item = T("heroskills.row.added_by_hand")
                row.line = T("heroskills.row.custom_feature")
            end
        end
    end
end

----------------------------------------------------------------------
--The draft's rules: who holds what, what a click does. No UI here, so the
--Builder can use the same rules with its own saving.

--- @param draft HeroSkillsDraft
--- @param key nil|string
--- @return nil|HeroSkillsRow
function HeroSkillsLanguages.RowByKey(draft, key)
    if key == nil then
        return nil
    end
    for _, row in ipairs(draft.grants) do
        if row.key == key then
            return row
        end
    end
    for _, row in ipairs(draft.hand) do
        if row.key == key then
            return row
        end
    end
    return nil
end

--- The first row holding this skill or language.
--- @param draft HeroSkillsDraft
--- @param id string
--- @return nil|HeroSkillsRow
function HeroSkillsLanguages.Holder(draft, id)
    for _, list in ipairs({draft.grants, draft.hand}) do
        for _, row in ipairs(list) do
            for _, pick in ipairs(row.picks) do
                if pick == id then
                    return row
                end
            end
        end
    end
    return nil
end

--- @param row HeroSkillsRow
--- @param id string
--- @return boolean
local function Offers(row, id)
    return row.allowed == nil or row.allowed[id] == true
end

--- The first row with room that takes this one: grants first, then an
--- open Duplicate skill row. What a click with no row selected fills.
--- @param draft HeroSkillsDraft
--- @param id string
--- @return nil|HeroSkillsRow
function HeroSkillsLanguages.OpenRowFor(draft, id)
    for _, row in ipairs(draft.grants) do
        if #row.picks < row.capacity and Offers(row, id) then
            return row
        end
    end
    for _, row in ipairs(draft.hand) do
        if row.dup and #row.picks == 0 then
            return row
        end
    end
    return nil
end

--- @param row HeroSkillsRow
--- @param id string
local function Drop(row, id)
    for i, pick in ipairs(row.picks) do
        if pick == id then
            table.remove(row.picks, i)
            return
        end
    end
end

--- Whether a row can be selected: skill grants and hand rows (language
--- grants take any language, so selecting one would filter nothing).
--- @param draft HeroSkillsDraft
--- @param row HeroSkillsRow
--- @return boolean
function HeroSkillsLanguages.Selectable(draft, row)
    return not row.grant or draft.kind == "skill"
end

--- Remove a hand row the player added in this window and left empty.
--- @param draft HeroSkillsDraft
--- @param row nil|HeroSkillsRow
local function DropIfEmpty(draft, row)
    if row == nil or row.grant or row.dup or #row.picks > 0 then
        return
    end
    for i, other in ipairs(draft.hand) do
        if other == row then
            table.remove(draft.hand, i)
            return
        end
    end
end

--- Clear the selection. Returns whether a row was selected.
--- @param draft HeroSkillsDraft
--- @return boolean
function HeroSkillsLanguages.Deselect(draft)
    if draft.sel == nil then
        return false
    end
    local row = HeroSkillsLanguages.RowByKey(draft, draft.sel)
    draft.sel = nil
    DropIfEmpty(draft, row)
    return true
end

--- Click on a row: select it, or clear it when it is selected already.
--- @param draft HeroSkillsDraft
--- @param key string
function HeroSkillsLanguages.Select(draft, key)
    local was = draft.sel
    HeroSkillsLanguages.Deselect(draft)
    if was ~= key and HeroSkillsLanguages.RowByKey(draft, key) ~= nil then
        draft.sel = key
    end
end

--- "Add a skill" / "Add a language": a new hand row, selected for picking.
--- @param draft HeroSkillsDraft
function HeroSkillsLanguages.AddHand(draft)
    HeroSkillsLanguages.Deselect(draft)
    draft.nextKey = draft.nextKey + 1
    local key = "h" .. tostring(draft.nextKey)
    draft.hand[#draft.hand+1] = {
        key = key,
        title = T("heroskills.row.added_by_hand"),
        item = T("heroskills.row.added_by_hand"),
        line = T("heroskills.row.custom_feature"),
        capacity = 1,
        picks = {},
        grant = false,
        orig = {},
    }
    draft.sel = key
end

--- The x on a hand row. A Duplicate skill row stays, open again: the
--- duplicate is still there to replace.
--- @param draft HeroSkillsDraft
--- @param key string
function HeroSkillsLanguages.RemoveHand(draft, key)
    draft.sel = nil
    local dupIndex = 0
    for i, row in ipairs(draft.hand) do
        if row.dup then
            dupIndex = dupIndex + 1
        end
        if row.key == key then
            if row.dup and dupIndex <= #draft.duplicates then
                row.picks = {}
            else
                table.remove(draft.hand, i)
            end
            break
        end
    end
    HeroSkillsLanguages.LabelDuplicates(draft)
end

--- @alias HeroSkillsChipState "known"|"picked"|"locked"|"unavailable"|"open"

--- What a chip shows: its state, and the hover that says why.
--- @param draft HeroSkillsDraft
--- @param entry HeroSkillsEntry
--- @return HeroSkillsChipState state
--- @return nil|string why
function HeroSkillsLanguages.ChipState(draft, entry)
    local id = entry.id
    local holder = HeroSkillsLanguages.Holder(draft, id)
    local sel = HeroSkillsLanguages.RowByKey(draft, draft.sel)
    local knownWhy = nil
    if draft.known[id] ~= nil then
        knownWhy = T("heroskills.chip.known_from", {sources = JoinList(draft.knownAll[id] or {draft.known[id]}, T("heroskills.list.and"))})
    end
    --a pick the Hero also has outright (an old duplicate) still shows picked,
    --so a click can drop it.
    if holder ~= nil and (sel == nil or holder == sel) then
        return "picked", knownWhy
    end
    if knownWhy ~= nil then
        return "known", knownWhy
    end
    if sel == nil then
        if HeroSkillsLanguages.OpenRowFor(draft, id) == nil then
            --the group's line: "No open Lore choice".
            if draft.kind == "skill" then
                local group = Skill.categoriesById[entry.group or ""]
                return "unavailable", T("heroskills.chip.no_open_choice", {group = group ~= nil and group.text or T("heroskills.chip.no_open_group")})
            end
            return "unavailable", T("heroskills.chip.no_open_language")
        end
        return "open", nil
    end
    if holder == sel then
        return "picked", nil
    end
    if holder ~= nil then
        return "locked", T("heroskills.chip.known_from", {sources = holder.title})
    end
    if not Offers(sel, id) then
        return "unavailable", T("heroskills.chip.not_offered", {row = sel.title})
    end
    if sel.capacity > 1 and #sel.picks >= sel.capacity then
        return "unavailable", T("heroskills.chip.row_full", {row = sel.title})
    end
    return "open", nil
end

--- A click on a chip. Returns whether the draft changed.
--- @param draft HeroSkillsDraft
--- @param entry HeroSkillsEntry
--- @return boolean
function HeroSkillsLanguages.ClickChip(draft, entry)
    local state = HeroSkillsLanguages.ChipState(draft, entry)
    if state == "known" or state == "locked" or state == "unavailable" then
        return false
    end
    local id = entry.id
    local holder = HeroSkillsLanguages.Holder(draft, id)
    local sel = HeroSkillsLanguages.RowByKey(draft, draft.sel)
    if sel == nil then
        --as in the Builder: a picked one drops, another fills the first open
        --row it fits.
        if holder ~= nil then
            Drop(holder, id)
            if not holder.grant and not holder.dup then
                DropIfEmpty(draft, holder)
            end
            return true
        end
        local row = HeroSkillsLanguages.OpenRowFor(draft, id)
        if row == nil then
            return false
        end
        row.picks[#row.picks+1] = id
        return true
    end
    if holder == sel then
        Drop(sel, id)
        return true
    end
    if #sel.picks < sel.capacity then
        sel.picks[#sel.picks+1] = id
    else
        --a one-pick row swaps in one click.
        sel.picks = {id}
    end
    return true
end

--- What a row says at its right: "1 left", "Done", or "Also from <item>"
--- when a pick is known some other way too. Hand rows with a pick show an x
--- instead (status nil).
--- @param draft HeroSkillsDraft
--- @param row HeroSkillsRow
--- @return nil|string text
--- @return nil|string tone "go", "ok" or "warn"
function HeroSkillsLanguages.RowStatus(draft, row)
    local left = row.capacity - #row.picks
    if left > 0 then
        return T("heroskills.status.left", {count = string.format("%d", left)}), "go"
    end
    if not row.grant then
        return nil, nil
    end
    for _, id in ipairs(row.picks) do
        if draft.known[id] ~= nil then
            return T("heroskills.status.also_from", {sources = JoinList(draft.knownAll[id] or {draft.known[id]}, T("heroskills.list.and"))}), "warn"
        end
        local holder = HeroSkillsLanguages.Holder(draft, id)
        if holder ~= nil and holder ~= row then
            return T("heroskills.status.also_from", {sources = holder.item}), "warn"
        end
    end
    return T("heroskills.status.done"), "ok"
end

--- The "Known already" line, or nil when there is nothing.
--- @param draft HeroSkillsDraft
--- @return nil|string
function HeroSkillsLanguages.KnownLine(draft)
    local parts = {}
    for _, entry in ipairs(draft.entries) do
        local sources = draft.knownAll[entry.id]
        if sources ~= nil and #sources > 0 then
            parts[#parts+1] = {name = entry.name, text = string.format("%s (%s)", entry.name, table.concat(sources, ", "))}
        end
    end
    if #parts == 0 then
        return nil
    end
    table.sort(parts, function(left, right) return left.name < right.name end)
    local texts = {}
    for _, part in ipairs(parts) do
        texts[#texts+1] = part.text
    end
    return T("heroskills.known.line", {list = table.concat(texts, ", ")})
end

--- Whether the draft differs from the Hero as read.
--- @param draft HeroSkillsDraft
--- @return boolean
function HeroSkillsLanguages.Changed(draft)
    for _, row in ipairs(draft.grants) do
        if not dmhub.DeepEqual(row.picks, row.orig) then
            return true
        end
    end
    local seen = {}
    for _, row in ipairs(draft.hand) do
        if #row.picks > 0 then
            if draft.kind == "language" then
                if draft.handOrig[row.picks[1]] == nil then
                    return true
                end
                seen[row.picks[1]] = true
            elseif row.guid == nil or draft.handOrig[row.guid] ~= row.picks[1] then
                return true
            end
        end
        --a saved row that was emptied counts as unseen, so its removal saves.
        if row.guid ~= nil and #row.picks > 0 then
            seen[row.guid] = true
        end
    end
    for key, _ in pairs(draft.handOrig) do
        if not seen[key] then
            return true
        end
    end
    return false
end

--- After Apply has saved the draft (the Builder saves as you go): what it
--- wrote becomes the draft's starting point, so the next Apply writes only
--- the next change (Apply writes what differs from the start).
--- @param draft HeroSkillsDraft
function HeroSkillsLanguages.Rebaseline(draft)
    for _, row in ipairs(draft.grants) do
        local orig = {}
        for _, id in ipairs(row.picks) do
            orig[#orig+1] = id
        end
        row.orig = orig
    end
    local handOrig = {}
    for _, row in ipairs(draft.hand) do
        local id = row.picks[1]
        if id ~= nil then
            if draft.kind == "language" then
                handOrig[id] = id
            elseif row.guid ~= nil then
                handOrig[row.guid] = id
            end
        end
    end
    draft.handOrig = handOrig
end

--- A new hand-added skill, made as the older Manage Skill Selections makes it.
--- @param id string
--- @param duplicateOf nil|string the skill granted twice it replaces
--- @return CharacterFeature
local function NewHandFeature(id, duplicateOf)
    local skill = Skill.SkillsById[id]
    local name = cond(duplicateOf ~= nil, DUPLICATE_FEATURE, HAND_FEATURE)
    local feature = CharacterFeature.Create{
        name = name,
        description = string.format("You have the %s skill.", skill ~= nil and skill.name or "unknown"),
        source = "Character Feature",
    }
    local guid = feature.guid
    feature.domains = {["CharacterFeature:" .. guid] = true}
    local description = "Choose a new skill."
    if duplicateOf ~= nil then
        description = string.format("Duplicated %s skill - select an alternative.", duplicateOf)
    end
    feature.modifiers = {
        CharacterModifier.new{
            guid = dmhub.GenerateGuid(),
            name = name,
            description = description,
            subtype = "skill",
            behavior = "proficiency",
            proficiency = "proficient",
            source = "Character Feature",
            sourceguid = guid,
            domains = {["CharacterFeature:" .. guid] = true},
            equate = false,
            skills = {[id] = true},
        },
    }
    return feature
end

--- Write the draft into the Hero: run inside a save (HeroSheetWrite.Save),
--- on the live Hero. Only what changed is written.
--- @param hero character
--- @param draft HeroSkillsDraft
function HeroSkillsLanguages.Apply(hero, draft)
    local levelChoices = hero:GetLevelChoices()
    for _, row in ipairs(draft.grants) do
        if not dmhub.DeepEqual(row.picks, row.orig) then
            local picks = {}
            for _, id in ipairs(row.picks) do
                picks[#picks+1] = id
            end
            levelChoices[row.guid] = picks
        end
    end

    if draft.kind == "language" then
        local innate = hero:get_or_add("innateLanguages", {})
        local keep = {}
        for _, row in ipairs(draft.hand) do
            if #row.picks > 0 then
                keep[row.picks[1]] = true
            end
        end
        for id, _ in pairs(draft.handOrig) do
            if not keep[id] then
                innate[id] = nil
            end
        end
        for id, _ in pairs(keep) do
            if not innate[id] then
                innate[id] = true
            end
        end
    else
        local features = hero:get_or_add("characterFeatures", {})
        local byGuid = {}
        for _, feature in ipairs(features) do
            byGuid[feature.guid] = feature
        end
        local keep = {}
        local dupIndex = 0
        for _, row in ipairs(draft.hand) do
            if row.dup then
                dupIndex = dupIndex + 1
            end
            local id = row.picks[1]
            local existing = row.guid ~= nil and byGuid[row.guid] or nil
            if existing ~= nil and id ~= nil then
                keep[row.guid] = true
                if draft.handOrig[row.guid] ~= id then
                    local skill = Skill.SkillsById[id]
                    existing.modifiers[1].skills = {[id] = true}
                    existing.description = string.format("You have the %s skill.", skill ~= nil and skill.name or "unknown")
                end
            elseif existing == nil and id ~= nil then
                --a Duplicate skill row whose duplicate has gone has no skill
                --name, so its note reads "Duplicated a skill".
                local feature = NewHandFeature(id, row.dup and (draft.duplicates[dupIndex] or "a") or nil)
                features[#features+1] = feature
                --the row now holds that feature (Rebaseline reads it).
                row.guid = feature.guid
            end
        end
        for i = #features, 1, -1 do
            local guid = features[i].guid
            if draft.handOrig[guid] ~= nil and not keep[guid] then
                table.remove(features, i)
            end
        end
    end
    hero:Invalidate()
end

----------------------------------------------------------------------
--The band's hover cards: where each skill and language comes from, without
--the window's rows.

--- The Skills card's foot: the steps and features the skills come from,
--- and the skills added by hand ("From career and class." / "Climb added
--- by hand."). Either may be nil.
--- @param hero character
--- @return nil|string from
--- @return nil|string byHand
function HeroSkillsLanguages.SkillSources(hero)
    local draft = HeroSkillsLanguages.Read(hero, "skill")
    local kinds = {}
    local names = {}
    local seenName = {}
    local function Add(kind, name)
        if kind ~= nil then
            kinds[kind] = true
        elseif name ~= nil and not seenName[name] then
            seenName[name] = true
            names[#names+1] = name
        end
    end
    for _, row in ipairs(draft.grants) do
        if #row.picks > 0 then
            Add(row.kind, row.item)
        end
    end
    for id, _ in pairs(draft.known) do
        local kind = draft.knownKind[id]
        if SOURCE_KINDS[kind] ~= nil or kind == "Subclass" then
            Add(kind, nil)
        else
            Add(nil, draft.known[id])
        end
    end
    local parts = {}
    for _, kind in ipairs(KIND_ORDER) do
        --a subclass's skills read as the class's.
        if kinds[kind] and not (kind == "Subclass" and kinds.Class) then
            parts[#parts+1] = string.lower(KindWord(cond(kind == "Subclass", "Class", kind)))
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        parts[#parts+1] = name
    end
    local from = nil
    if #parts > 0 then
        from = T("heroskills.card.from", {sources = JoinList(parts, T("heroskills.list.and"))})
    end
    local hand = {}
    for _, row in ipairs(draft.hand) do
        local skill = row.picks[1] ~= nil and Skill.SkillsById[row.picks[1]] or nil
        if skill ~= nil then
            hand[#hand+1] = skill.name
        end
    end
    table.sort(hand)
    local byHand = nil
    if #hand > 0 then
        byHand = T("heroskills.card.by_hand", {skills = JoinList(hand, T("heroskills.list.and"))})
    end
    return from, byHand
end

--- The Languages card's rows: each language the Hero knows with where it
--- comes from (Everyone, Ancestry, Career, Added by hand...), by name.
--- @param hero character
--- @return {label: string, value: string, inWorld: nil|string}[]
function HeroSkillsLanguages.LanguageSources(hero)
    local draft = HeroSkillsLanguages.Read(hero, "language")
    local source = {}
    for id, _ in pairs(draft.known) do
        source[id] = draft.knownKind[id]
    end
    for _, row in ipairs(draft.grants) do
        for _, id in ipairs(row.picks) do
            source[id] = source[id] or row.kind or row.item
        end
    end
    for _, row in ipairs(draft.hand) do
        for _, id in ipairs(row.picks) do
            source[id] = source[id] or T("heroskills.row.added_by_hand")
        end
    end
    local rows = {}
    for _, entry in ipairs(draft.entries) do
        if source[entry.id] ~= nil then
            rows[#rows+1] = {label = entry.name, value = KindWord(source[entry.id]), inWorld = entry.inWorld}
        end
    end
    return rows
end

----------------------------------------------------------------------
--The panel: Your choices on the left, the chips on the right. Built once;
--a click changes the draft and the panel restyles its chips in place and
--rebuilds only the short row list.

--Below this width the two columns stack.
local STACK_BELOW = 760
local COLUMN_HPAD = 20
local COLUMN_VPAD = 14
--a row's status column: "Done", "1 left" or the x, and the wider one a row
--takes from its values for "Also from Berserker".
local STATUS_WIDTH = 56
local STATUS_WIDE = 150

--- @class HeroSkillsPanelArgs
--- @field draft HeroSkillsDraft
--- @field width number the panel's width in sheet units
--- @field height nil|number its height; nil sizes it to its content (the Builder's page, which scrolls itself)
--- @field onChange nil|fun(draft: HeroSkillsDraft) after every change to the draft
--- @field parts nil|boolean the Builder's arrangement: no columns and no Add row; the control hands the parts back (control.parts) for the Builder to place under its own headings
--- @field rowWidth nil|number in parts mode, the rows' own width: the Builder's picks pane, where each row stacks its picks under its title and state
--- @field stars nil|boolean a chip the book's Quick Build takes ends in a star (the Builder)
--- @field slice nil|boolean build the chips across the next frames instead of now (the Builder, where building them all at once is a visible stall)
--- @field onBuilt nil|fun() with slice, after the last chip is built

--- @class HeroSkillsParts
--- @field rows Panel Your choices: the grant rows, changed in place
--- @field known Panel the "Known already" line (collapsed when there is nothing)
--- @field chips Panel the chips by group (skills) or in one wrap (languages), the selected row's filter line first
--- @field search nil|Panel the languages' search field, for the heading's right end

--- @class HeroSkillsPanelControl
--- @field ClearSelection fun(): boolean clears a selected row; false when none was
--- @field parts nil|HeroSkillsParts in parts mode, the panels to place
--- @field SetDraft fun(draft: HeroSkillsDraft): boolean shows a new reading of the Hero in the built panels; false when its entries differ (build anew)

--- A small capitals label in the label colour ("YOUR CHOICES").
--- @param text string
--- @param args nil|table
--- @return Panel
local function Caps(text, args)
    local fields = {
        classes = {"heroSheetCardLabel"},
        text = string.upper(text),
        fontSize = 11.5,
        bold = true,
        width = "auto",
        height = "auto",
        halign = "left",
        textWrap = false,
    }
    for key, value in pairs(args or {}) do
        fields[key] = value
    end
    return gui.Label(fields)
end

--The Builder's "Show Dead Languages" checkbox, remembered per user (off by
--default). Off hides the dead languages' chips, except one the Hero holds.
--Only the Builder (parts mode) has the checkbox, so only it filters.
local g_showDeadSetting = setting{
    id = "heroskills:showdeadlanguages",
    default = false,
    storage = "preference",
}

--Chips built across frames (Panel with args.slice): one queue for every
--panel, in the order the panels were made, so the Skills chips fill in
--before the Languages under them. Each frame builds chips until the budget
--is spent, so the frame stays quick however many wait.
local SLICE_BUDGET_MS = 6
--- @type (fun(): boolean)[] a step builds one chip and says whether its panel is done
local g_sliceQueue = {}
local g_sliceRunning = false

--- @param step fun(): boolean
local function QueueSlice(step)
    g_sliceQueue[#g_sliceQueue+1] = step
    if g_sliceRunning then
        return
    end
    g_sliceRunning = true
    dmhub.Coroutine(function()
        while #g_sliceQueue > 0 do
            if mod.unloaded then
                return
            end
            local stopwatch = dmhub.Stopwatch()
            repeat
                local ok, done = pcall(g_sliceQueue[1])
                if not ok then
                    dmhub.Error("Hero skills: a chip failed to build: " .. tostring(done))
                end
                if not ok or done then
                    table.remove(g_sliceQueue, 1)
                end
            until #g_sliceQueue == 0 or stopwatch.milliseconds >= SLICE_BUDGET_MS
            coroutine.yield()
        end
        g_sliceRunning = false
    end)
end

--- Build the component for a draft. Returns the panel and its control.
--- @param args HeroSkillsPanelArgs
--- @return Panel
--- @return HeroSkillsPanelControl
function HeroSkillsLanguages.Panel(args)
    local draft = args.draft
    local isSkill = draft.kind == "skill"
    local stacked = args.width < STACK_BELOW
    local columnWidth = cond(stacked, args.width, math.floor(args.width / 2))
    local rowWidth = columnWidth - 2 * COLUMN_HPAD
    --the Builder gives the chips its page's whole width and the rows the
    --picks pane's, where a row's picks go under its title and state.
    local paneRows = args.parts == true and args.rowWidth ~= nil
    if args.parts then
        stacked = true
        columnWidth = args.width
        rowWidth = args.rowWidth or args.width
    end

    local Refresh
    local function Changed()
        Refresh()
        if args.onChange ~= nil then
            args.onChange(draft)
        end
    end

    --- @param text string
    --- @return Panel
    local function Pill(text)
        return gui.Label{
            classes = {"heroSklPill"},
            bgimage = "panels/square.png",
            cornerRadius = 10,
            text = text,
            fontSize = 12.5,
            bold = true,
            width = "auto",
            height = "auto",
            hpad = 9,
            vpad = 1,
            borderBox = true,
            rmargin = 5,
            vmargin = 2,
            halign = "left",
            valign = "center",
            textWrap = false,
            interactable = false,
        }
    end

    local nameOf = {}
    for _, entry in ipairs(draft.entries) do
        nameOf[entry.id] = entry.name
    end

    --The title and the picks share what the status leaves 1.2 : 1, the same
    --in every row so the picks line up.
    local rowInner = rowWidth - 22
    local titleWidth = math.floor((rowInner - STATUS_WIDTH - 20) * 1.2 / 2.2)
    if paneRows then
        titleWidth = rowInner - STATUS_WIDTH - 10
    end

    --- @class HeroSkillsRowView
    --- @field panel Panel
    --- @field update fun(row: HeroSkillsRow)

    --- One row of Your choices, made once and then changed in place: a click
    --- updates its picks, status and selection rather than building it anew
    --- (rebuilding every row made each click slow to show).
    --- @param first HeroSkillsRow
    --- @return HeroSkillsRowView
    local function RowView(first)
        local current = first
        local titleLabel = gui.Label{
            classes = {"heroSheetCardStrong"},
            text = first.title,
            fontSize = 13.5,
            bold = true,
            width = titleWidth,
            height = "auto",
            textWrap = true,
            interactable = false,
        }
        local lineLabel = gui.Label{
            classes = {"heroSheetCardLab"},
            text = first.line,
            fontSize = 12.5,
            width = titleWidth,
            height = "auto",
            textWrap = true,
            interactable = false,
        }
        local values = gui.Panel{
            width = cond(paneRows, rowInner, rowInner - STATUS_WIDTH - 20 - titleWidth),
            height = "auto",
            flow = "horizontal",
            wrap = true,
            valign = "center",
            rmargin = cond(paneRows, 0, 10),
            tmargin = cond(paneRows, 4, 0),
            interactable = false,
        }
        local statusLabel = gui.Label{
            classes = {"heroSheetCardSuccess"},
            text = "",
            fontSize = 12.5,
            width = STATUS_WIDTH,
            height = "auto",
            textAlignment = "right",
            textWrap = true,
            valign = "center",
            interactable = false,
        }
        local xButton = gui.Panel{
            classes = {"heroSheetXButton", "hoverable", "collapsed"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 5,
            width = HeroSheetWindow.TargetSize(28),
            height = HeroSheetWindow.TargetSize(28),
            halign = "right",
            valign = "center",
            click = function()
                HeroSkillsLanguages.RemoveHand(draft, current.key)
                Changed()
            end,
            gui.Panel{
                classes = {"heroSheetXIcon"},
                bgimage = "phosphor/x-bold.png",
                width = 11,
                height = 11,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
        local statusBox = gui.Panel{
            width = STATUS_WIDTH,
            height = "auto",
            valign = "center",
            flow = "horizontal",
            statusLabel,
            xButton,
        }
        --selected: a light bar down the left edge. A floating bar cannot take
        --an auto-height row's height, so it is sized once the row has laid out.
        local bar = gui.Panel{
            classes = {"heroSklRowBar", "collapsed"},
            bgimage = "panels/square.png",
            floating = true,
            width = 3,
            height = 1,
            halign = "left",
            valign = "center",
            x = -9,
            cornerRadius = 1,
            interactable = false,
        }
        local titleColumn = gui.Panel{
            width = titleWidth,
            height = "auto",
            flow = "vertical",
            valign = cond(paneRows, "top", "center"),
            rmargin = 10,
            interactable = false,
            titleLabel,
            lineLabel,
        }
        --in the pane a row is its title and state, its picks under them.
        local rowChildren = {titleColumn, values, statusBox, bar}
        if paneRows then
            statusBox.selfStyle.valign = "top"
            rowChildren = {
                gui.Panel{width = "100%", height = "auto", flow = "horizontal", interactable = false, titleColumn, statusBox},
                values,
                bar,
            }
        end
        local panel
        panel = gui.Panel{
            classes = {"heroSklRow", cond(HeroSkillsLanguages.Selectable(draft, first), "hoverable", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            hpad = 10,
            vpad = 7,
            borderBox = true,
            tmargin = 6,
            flow = cond(paneRows, "vertical", "horizontal"),
            click = function()
                if HeroSkillsLanguages.Selectable(draft, current) then
                    HeroSkillsLanguages.Select(draft, current.key)
                    Changed()
                end
            end,
            children = rowChildren,
        }
        --what was drawn last, so an update touches only what changed.
        local shown = {}
        local function SizeBar()
            HeroSheetWindow.AfterLayout(function()
                if not panel.valid or not bar.valid or panel.renderedWidth <= 0 then
                    return
                end
                local scale = panel.renderedWidth / rowWidth
                bar.selfStyle.height = math.max(1, panel.renderedHeight / scale - 12)
            end)
        end
        --- @param row HeroSkillsRow
        local function Update(row)
            current = row
            if row.title ~= shown.title then
                titleLabel.text = row.title
                shown.title = row.title
            end
            if row.line ~= shown.line then
                lineLabel.text = row.line
                lineLabel:SetClass("collapsed", row.line == "")
                shown.line = row.line
            end
            local picks = table.concat(row.picks, "|")
            local heightMayChange = false
            if picks ~= shown.picks then
                local list = {}
                for _, id in ipairs(row.picks) do
                    list[#list+1] = Pill(nameOf[id] or "?")
                end
                if #list == 0 then
                    list[1] = gui.Label{
                        classes = {"heroSheetCardSub"},
                        text = T("heroskills.row.not_chosen"),
                        fontSize = 13.5,
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        textWrap = false,
                        interactable = false,
                    }
                end
                values.children = list
                shown.picks = picks
                heightMayChange = true
            end
            local status, tone = HeroSkillsLanguages.RowStatus(draft, row)
            local statusKey = tostring(status) .. "|" .. tostring(tone)
            if statusKey ~= shown.status then
                local width = cond(tone == "warn", STATUS_WIDE, STATUS_WIDTH)
                statusBox.selfStyle.width = width
                statusLabel.selfStyle.width = width
                if paneRows then
                    titleColumn.selfStyle.width = rowInner - width - 10
                else
                    values.selfStyle.width = rowInner - width - 20 - titleWidth
                end
                statusLabel:SetClass("collapsed", status == nil)
                xButton:SetClass("collapsed", status ~= nil)
                if status ~= nil then
                    statusLabel.text = status
                    statusLabel:SetClass("heroSheetCardInfo", tone == "go")
                    statusLabel:SetClass("heroSheetCardWarning", tone == "warn")
                    statusLabel:SetClass("heroSheetCardSuccess", tone == "ok")
                    statusLabel:SetClass("heroSklStatusStrong", tone ~= "ok")
                end
                shown.status = statusKey
                heightMayChange = true
            end
            local selected = draft.sel == row.key
            if selected ~= shown.selected then
                panel:SetClass("heroSklRowSelected", selected)
                bar:SetClass("collapsed", not selected)
                shown.selected = selected
                heightMayChange = selected
            end
            if selected and heightMayChange then
                SizeBar()
            end
        end
        Update(first)
        return {panel = panel, update = Update}
    end

    --- @type table<string, HeroSkillsRowView>
    local rowViews = {}
    --- @type string[]
    local rowOrder = {}

    local rowsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local knownText = HeroSkillsLanguages.KnownLine(draft)
    local knownLabel = gui.Label{
        classes = {"heroSheetCardLab", cond(knownText == nil, "collapsed", nil)},
        text = knownText or "",
        fontSize = 12.5,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 10,
    }

    --Add a skill / Add a language (the sheet's windows; the Builder has none).
    --- @type nil|Panel
    local addButton = nil
    if not args.parts then
        addButton = gui.Panel{
            classes = {"heroSklAdd", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = HeroSheetWindow.TargetSize(34),
            hpad = 12,
            borderBox = true,
            tmargin = 10,
            flow = "horizontal",
            click = function()
                HeroSkillsLanguages.AddHand(draft)
                Changed()
            end,
            gui.Panel{
                classes = {"heroSklAddIcon"},
                bgimage = "phosphor/plus-bold.png",
                width = 13,
                height = 13,
                rmargin = 8,
                halign = "left",
                valign = "center",
                interactable = false,
            },
            gui.Label{
                classes = {"heroSheetCardText"},
                text = cond(isSkill, T("heroskills.add.skill"), T("heroskills.add.language")),
                fontSize = 14,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
    end

    --"Choices for <row>" with Show all, over the chips while a row is selected.
    local filterText = gui.Label{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 13,
        width = rowWidth - 20 - 90,
        height = "auto",
        valign = "center",
        textWrap = true,
        interactable = false,
    }
    local filterLine = gui.Panel{
        classes = {"heroSklFilter", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "100%",
        height = "auto",
        lpad = 12,
        rpad = 8,
        vpad = 6,
        borderBox = true,
        tmargin = 10,
        bmargin = 4,
        flow = "horizontal",
        filterText,
        gui.Panel{
            classes = {"heroSheetSmallButton", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = "auto",
            height = HeroSheetWindow.TargetSize(26),
            hpad = 10,
            borderBox = true,
            halign = "right",
            valign = "center",
            click = function()
                HeroSkillsLanguages.Deselect(draft)
                Changed()
            end,
            gui.Label{
                classes = {"heroSheetCardText"},
                text = T("heroskills.filter.show_all"),
                fontSize = 12.5,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        },
    }

    --The chips, made once: a refresh restyles them.
    --- @class HeroSkillsChipView
    --- @field panel Panel
    --- @field entry HeroSkillsEntry
    --- @field panels Panel[] the chip and its labels: each takes the state's class
    --- @field star nil|Panel the Quick Build star, dark on a picked chip
    --- @field state nil|string
    --- @field tip nil|string
    --- @field hidden nil|boolean
    --- @field shape string what it shows around its name (ChipShape)
    --- @field wrap nil|Panel the wrap it sits in

    --- @type HeroSkillsChipView[]
    local chips = {}

    --- What a chip shows around its name (the labels it is built with): a
    --- new reading of the Hero builds again only the chips whose shape changed.
    --- @param entry HeroSkillsEntry
    --- @return string
    local function ChipShape(entry)
        local mark = draft.marks[entry.id]
        local known = draft.known[entry.id] ~= nil
        local speakers = ""
        if entry.speakers ~= nil and not known then
            speakers = entry.speakers
        end
        local suffix = ""
        if mark ~= nil and mark.suffix ~= nil then
            suffix = mark.suffix
        end
        local star = args.stars == true and draft.quickBuild[entry.id] and true or false
        return table.concat({speakers, suffix, tostring(known), tostring(star), tostring(entry.dead == true)}, "|")
    end

    --- @param entry HeroSkillsEntry
    --- @return HeroSkillsChipView
    local function MakeChip(entry)
        local mark = draft.marks[entry.id]
        local known = draft.known[entry.id] ~= nil
        local labels = {}
        --the chip's record, made once the panel exists (the hover reads it).
        --- @type HeroSkillsChipView
        local view
        --the name sits over a bold copy of itself, so a chip keeps its width
        --when it turns bold on being picked.
        local nameLabel = gui.Label{
            classes = {"heroSklChipText", cond(entry.dead == true, "heroSklDead", nil)},
            text = entry.name,
            fontSize = 13.5,
            italics = entry.dead == true,
            floating = true,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            textWrap = false,
            interactable = false,
        }
        labels[#labels+1] = nameLabel
        local children = {
            gui.Panel{
                width = "auto",
                height = "auto",
                valign = "center",
                interactable = false,
                gui.Label{
                    classes = {"heroSklSizer"},
                    text = entry.name,
                    fontSize = 13.5,
                    bold = true,
                    italics = entry.dead == true,
                    width = "auto",
                    height = "auto",
                    textWrap = false,
                    interactable = false,
                },
                nameLabel,
            },
        }
        local function Small(text, class, lmargin)
            local label = gui.Label{
                classes = {class},
                text = text,
                fontSize = 11.5,
                width = "auto",
                height = "auto",
                lmargin = lmargin,
                valign = "center",
                textWrap = false,
                interactable = false,
            }
            labels[#labels+1] = label
            children[#children+1] = label
        end
        --a known language reads "Caelian known", without its speakers. With
        --plain names the plain name already says who speaks it, so the small
        --text gives the in-world name instead ("Goblin Szetch").
        if entry.inWorld ~= nil and not known then
            Small(entry.inWorld, "heroSklChipSpeakers", 5)
        elseif entry.speakers ~= nil and not known then
            Small(entry.speakers, "heroSklChipSpeakers", 5)
        end
        if mark ~= nil and mark.suffix ~= nil then
            Small("\u{00B7} " .. mark.suffix, "heroSklChipMark", 4)
        end
        if known then
            Small(T("heroskills.chip.known"), "heroSklChipMark", 5)
        end
        --the book's Quick Build pick; its colour follows the chip's state.
        local star = nil
        if args.stars and draft.quickBuild[entry.id] then
            star = gui.Panel{
                bgimage = "phosphor/star-fill.png",
                bgcolor = HeroSheetTheme.Palette().cardLabel,
                width = 12,
                height = 12,
                lmargin = 5,
                valign = "center",
                interactable = false,
            }
            children[#children+1] = star
        end
        if entry.dead then
            --in labels so it takes the chip's state (dark on a picked chip).
            local deadTag = gui.Label{
                classes = {"heroSklDeadTag"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 6,
                text = T("heroskills.chip.dead"),
                fontSize = 10.5,
                width = "auto",
                height = "auto",
                hpad = 5,
                borderBox = true,
                lmargin = 5,
                valign = "center",
                textWrap = false,
                interactable = false,
            }
            labels[#labels+1] = deadTag
            children[#children+1] = deadTag
        end
        local panel
        panel = gui.Panel{
            classes = {"heroSklChip", "heroSklOption", "hoverable", cond(entry.dead == true, "heroSklDead", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "auto",
            height = HeroSheetWindow.TargetSize(30),
            hpad = 10,
            borderBox = true,
            rmargin = 6,
            bmargin = 6,
            halign = "left",
            flow = "horizontal",
            --the view's entry and mark, not the build's: a new reading of
            --the Hero (SetDraft) swaps them without building the chip again.
            hover = function(element)
                local lines = {}
                if view.entry.tooltip ~= nil then
                    lines[#lines+1] = view.entry.tooltip
                end
                if view.tip ~= nil then
                    lines[#lines+1] = view.tip
                end
                local shownMark = draft.marks[view.entry.id]
                for _, line in ipairs(shownMark ~= nil and shownMark.lines or {}) do
                    lines[#lines+1] = line
                end
                if star ~= nil then
                    lines[#lines+1] = T("heroskills.chip.quick_build")
                end
                if #lines > 0 then
                    gui.Tooltip(table.concat(lines, "\n"))(element)
                end
            end,
            click = function()
                if HeroSkillsLanguages.ClickChip(draft, view.entry) then
                    Changed()
                end
            end,
            children = children,
        }
        local panels = {panel}
        for _, label in ipairs(labels) do
            panels[#panels+1] = label
        end
        view = {panel = panel, entry = entry, panels = panels, star = star, state = nil, tip = nil, hidden = nil, shape = ChipShape(entry), wrap = nil}
        return view
    end

    --The chip area: skills by group, each with its "No open <group> choice"
    --line; languages in one wrap with a search field in the heading.
    local chipArea = {}
    --- @type {label: Panel, group: string, hidden: nil|boolean}[]
    local groupLines = {}
    local searchInput = nil
    --in parts mode, the search with its checkbox (parts.search)
    local searchPart = nil
    --With args.slice the chips are not built here: each wrap is made empty
    --and its chips queued (in the order they show) for the frames after, a
    --few ms of them a frame (the queue is QueueSlice, above).
    --- @type {entry: HeroSkillsEntry, wrap: Panel}[]
    local pending = {}
    --- A wrap of chips, built now or queued.
    --- @param entries HeroSkillsEntry[]
    --- @return Panel
    local function ChipWrap(entries)
        local built = {}
        if not args.slice then
            for _, entry in ipairs(entries) do
                local view = MakeChip(entry)
                chips[#chips+1] = view
                built[#built+1] = view.panel
            end
        end
        local wrapPanel = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 8,
            children = built,
        }
        if args.slice then
            for _, entry in ipairs(entries) do
                pending[#pending+1] = {entry = entry, wrap = wrapPanel}
            end
        else
            for i = #chips - #built + 1, #chips do
                chips[i].wrap = wrapPanel
            end
        end
        return wrapPanel
    end
    if isSkill then
        if not args.parts then
            chipArea[#chipArea+1] = Caps(T("heroskills.heading.skills"))
        end
        chipArea[#chipArea+1] = filterLine
        for _, category in ipairs(Skill.categories) do
            local wrap = {}
            for _, entry in ipairs(draft.entries) do
                if entry.group == category.id then
                    wrap[#wrap+1] = entry
                end
            end
            if #wrap > 0 then
                chipArea[#chipArea+1] = Caps(category.text, {tmargin = 12})
                local line = gui.Label{
                    classes = {"heroSheetCardLab", "collapsed"},
                    text = T("heroskills.chip.no_open_choice", {group = category.text}),
                    fontSize = 12.5,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    tmargin = 2,
                    textWrap = false,
                }
                groupLines[#groupLines+1] = {label = line, group = category.id}
                chipArea[#chipArea+1] = line
                chipArea[#chipArea+1] = ChipWrap(wrap)
            end
        end
    else
        searchInput = gui.SearchInput{
            placeholderText = T("heroskills.search.placeholder"),
            text = draft.query,
            --the rest of the heading's line
            width = cond(args.parts, 210, rowWidth - 90),
            height = HeroSheetWindow.TargetSize(28),
            borderBox = true,
            halign = "right",
            valign = "center",
            hover = gui.Tooltip(T("heroskills.search.tooltip")),
            edit = function(element)
                draft.query = element.text or ""
                Refresh()
            end,
        }
        --the Builder puts the search on its own heading's line, with the
        --Show Dead Languages checkbox before it.
        if args.parts then
            searchPart = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                gui.Check{
                    text = T("heroskills.search.show_dead"),
                    value = g_showDeadSetting:Get() == true,
                    tooltip = T("heroskills.search.show_dead_tooltip"),
                    width = "auto",
                    height = HeroSheetWindow.TargetSize(28),
                    minWidth = 0,
                    fontSize = 12.5,
                    rmargin = 12,
                    valign = "center",
                    change = function(element)
                        g_showDeadSetting:Set(element.value == true)
                        Refresh()
                    end,
                },
                searchInput,
            }
        else
            chipArea[#chipArea+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                Caps(T("heroskills.heading.languages"), {valign = "center"}),
                searchInput,
            }
        end
        chipArea[#chipArea+1] = filterLine
        chipArea[#chipArea+1] = ChipWrap(draft.entries)
    end

    --- A search match on a language's name or speakers (the Builder's search
    --- syntax).
    --- @param entry HeroSkillsEntry
    --- @return boolean
    local function Matches(entry)
        local query = draft.query or ""
        if query == "" then
            return true
        end
        --A leading ! or - means "without": match without the sign, then keep
        --only the languages that did not match.
        local negative = string.find(query, "^[!%-]") ~= nil
        if negative then
            query = string.sub(query, 2)
            if query == "" then
                return true
            end
        end
        local builder = rawget(_G, "CharacterBuilder")
        local function Test(text)
            if text == nil then
                return false
            end
            if builder ~= nil and builder._matchesFilter ~= nil then
                local ok, result = pcall(builder._matchesFilter, query, text)
                if ok then
                    return result == true
                end
            end
            return string.find(string.lower(text), string.lower(query), 1, true) ~= nil
        end
        local hit = Test(entry.name) or Test(entry.speakers) or Test(entry.inWorld)
        if negative then
            return not hit
        end
        return hit
    end

    local STATE_CLASSES = {
        known = "heroSklKnown",
        picked = "heroSklPicked",
        locked = "heroSklLocked",
        unavailable = "heroSklUnav",
    }

    --- A chip's state, tooltip and (languages) search match, restyled only
    --- where they changed.
    --- @param chip HeroSkillsChipView
    --- @return string state
    local function PaintChip(chip)
        local state, why = HeroSkillsLanguages.ChipState(draft, chip.entry)
        if state ~= chip.state then
            --only the old state's class and the new one's change.
            local old = STATE_CLASSES[chip.state or ""]
            local new = STATE_CLASSES[state]
            for _, panel in ipairs(chip.panels) do
                if old ~= nil then
                    panel:SetClass(old, false)
                end
                if new ~= nil then
                    panel:SetClass(new, true)
                end
            end
            if chip.star ~= nil then
                local palette = HeroSheetTheme.Palette()
                chip.star.selfStyle.bgcolor = cond(state == "picked", palette.bg, palette.cardLabel)
            end
            chip.state = state
        end
        chip.tip = why
        if not isSkill then
            local hide = not Matches(chip.entry)
            --a dead language hides while the checkbox is off, unless the Hero holds it.
            if args.parts and chip.entry.dead == true and g_showDeadSetting:Get() ~= true
                and state ~= "picked" and state ~= "locked" and state ~= "known" then
                hide = true
            end
            if hide ~= chip.hidden then
                chip.panel:SetClass("collapsed", hide)
                chip.hidden = hide
            end
        end
        return state
    end

    Refresh = function()
        --the rows: each updated in place; the list is set again only when a
        --row comes or goes (Add a skill, an x).
        local wanted = {}
        for _, row in ipairs(draft.grants) do
            wanted[#wanted+1] = row
        end
        for _, row in ipairs(draft.hand) do
            wanted[#wanted+1] = row
        end
        local relist = #wanted ~= #rowOrder
        local keep = {}
        for i, row in ipairs(wanted) do
            keep[row.key] = true
            if rowOrder[i] ~= row.key then
                relist = true
            end
            local view = rowViews[row.key]
            if view == nil then
                view = RowView(row)
                rowViews[row.key] = view
            else
                view.update(row)
            end
        end
        if relist then
            local panels = {}
            rowOrder = {}
            for _, row in ipairs(wanted) do
                panels[#panels+1] = rowViews[row.key].panel
                rowOrder[#rowOrder+1] = row.key
            end
            for key, _ in pairs(rowViews) do
                if not keep[key] then
                    rowViews[key] = nil
                end
            end
            rowsPanel.children = panels
        end

        local sel = HeroSkillsLanguages.RowByKey(draft, draft.sel)
        filterLine:SetClass("collapsed", sel == nil)
        if sel ~= nil then
            filterText.text = T("heroskills.filter.choices_for", {row = sel.title})
        end

        --a group with nothing to pick says so, unless a row is selected;
        --not while its chips are still being built (it cannot tell yet).
        local groupOpen = {}
        for _, chip in ipairs(chips) do
            local state = PaintChip(chip)
            if state == "picked" or state == "open" then
                groupOpen[chip.entry.group or ""] = true
            end
        end
        for _, line in ipairs(groupLines) do
            local hide = sel ~= nil or groupOpen[line.group] == true or #pending > 0
            if hide ~= line.hidden then
                line.label:SetClass("collapsed", hide)
                line.hidden = hide
            end
        end
    end

    --- Show a new reading of the Hero (a pick on another step, another
    --- client's change) in the panels already built: a chip whose shape is
    --- unchanged only restyles, one whose shape changed is built again in its
    --- place, the rows update in place. False when the entries themselves
    --- differ, so the caller builds anew.
    --- @param newDraft HeroSkillsDraft
    --- @return boolean
    local function SetDraft(newDraft)
        local old, new = draft.entries, newDraft.entries
        if #old ~= #new then
            return false
        end
        for i, newEntry in ipairs(new) do
            local oldEntry = old[i]
            if oldEntry.id ~= newEntry.id or oldEntry.name ~= newEntry.name or oldEntry.group ~= newEntry.group
                or oldEntry.speakers ~= newEntry.speakers or oldEntry.inWorld ~= newEntry.inWorld
                or (oldEntry.dead == true) ~= (newEntry.dead == true) then
                return false
            end
        end
        --what the user was doing carries over: the language search, a selected row.
        newDraft.query = draft.query
        if draft.sel ~= nil and HeroSkillsLanguages.RowByKey(newDraft, draft.sel) ~= nil then
            newDraft.sel = draft.sel
        end
        --- @type table<string, HeroSkillsEntry>
        local byId = {}
        for _, newEntry in ipairs(new) do
            byId[newEntry.id] = newEntry
        end
        draft = newDraft
        for _, item in ipairs(pending) do
            item.entry = byId[item.entry.id] or item.entry
        end
        for i, chip in ipairs(chips) do
            local entry = byId[chip.entry.id] or chip.entry
            chip.entry = entry
            if ChipShape(entry) ~= chip.shape then
                local view = MakeChip(entry)
                local wrapPanel = chip.wrap
                view.wrap = wrapPanel
                if wrapPanel ~= nil and wrapPanel.valid then
                    local kids = wrapPanel.children
                    for index, child in ipairs(kids) do
                        if rawequal(child, chip.panel) then
                            kids[index] = view.panel
                            break
                        end
                    end
                    wrapPanel.children = kids
                end
                if chip.panel.valid then
                    chip.panel:DestroySelf()
                end
                chips[i] = view
            end
        end
        local knownText = HeroSkillsLanguages.KnownLine(draft)
        knownLabel.text = knownText or ""
        knownLabel:SetClass("collapsed", knownText == nil)
        Refresh()
        return true
    end

    --The chips left to build, a chip a step on the shared queue; the group
    --lines and the caller follow once the last is in.
    if args.slice and #pending > 0 then
        QueueSlice(function()
            local item = pending[1]
            if item == nil then
                return true
            end
            if not item.wrap.valid then
                pending = {}
                return true
            end
            table.remove(pending, 1)
            local view = MakeChip(item.entry)
            view.wrap = item.wrap
            chips[#chips+1] = view
            item.wrap:AddChild(view.panel)
            PaintChip(view)
            if #pending > 0 then
                return false
            end
            Refresh()
            if args.onBuilt ~= nil then
                args.onBuilt()
            end
            return true
        end)
    end

    --- @param children Panel[]
    --- @param width number
    --- @param border number|table the faint rule between the columns (left edge, or top when stacked)
    --- @return Panel
    local function Column(children, width, border)
        return gui.Panel{
            classes = {"heroSklColumn"},
            bgimage = "panels/square.png",
            border = border,
            width = width,
            height = cond(stacked or args.height == nil, "auto", args.height),
            hpad = COLUMN_HPAD,
            vpad = COLUMN_VPAD,
            borderBox = true,
            --scrolls only once its content is taller (FitScroll): a scrolling
            --panel is slow to lay out for every panel inside it, which made
            --the window slow to show.
            vscroll = false,
            flow = "vertical",
            valign = "top",
            --a click on empty space clears a selected row.
            click = function()
                if HeroSkillsLanguages.Deselect(draft) then
                    Changed()
                end
            end,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                --a scrolling column centres short content otherwise.
                valign = "top",
                children = children,
            },
        }
    end

    --The Builder places the parts itself: its one Your choices list for
    --skills and languages, then the chips under its own headings.
    if args.parts then
        local chipsPanel = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            --a click on empty space clears a selected row.
            bgimage = "panels/square.png",
            bgcolor = "clear",
            click = function()
                if HeroSkillsLanguages.Deselect(draft) then
                    Changed()
                end
            end,
            children = chipArea,
        }
        Refresh()
        --- @type HeroSkillsPanelControl
        local partsControl = {
            ClearSelection = function()
                if HeroSkillsLanguages.Deselect(draft) then
                    Changed()
                    return true
                end
                return false
            end,
            parts = {rows = rowsPanel, known = knownLabel, chips = chipsPanel, search = searchPart},
            SetDraft = SetDraft,
        }
        return rowsPanel, partsControl
    end

    local left = Column({
        Caps(T("heroskills.heading.your_choices")),
        rowsPanel,
        knownLabel,
        addButton,
    }, columnWidth, 0)
    --stacked, the rule runs along the top (the border's y2 edge).
    local right = Column(chipArea, columnWidth, cond(stacked, {x1 = 0, y1 = 0, x2 = 0, y2 = 1}, {x1 = 1, y1 = 0, x2 = 0, y2 = 0}))

    local root
    if stacked then
        root = gui.Panel{
            width = args.width,
            height = args.height or "auto",
            vscroll = false,
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                valign = "top",
                left,
                right,
            },
        }
    else
        root = gui.Panel{
            width = args.width,
            height = args.height or "auto",
            flow = "horizontal",
            left,
            right,
        }
    end
    --Turn scrolling on for a column (or the stacked whole) whose content has
    --grown taller than it, after layout. Once on it stays on.
    local function FitScroll()
        --sized to its content (no height), it never needs to scroll.
        if args.height == nil then
            return
        end
        HeroSheetWindow.AfterLayout(function()
            local scrollers = cond(stacked, {root}, {left, right})
            for _, panel in ipairs(scrollers) do
                --the window may have closed in the two frames waited.
                if panel.valid then
                    local content = panel.children[1]
                    if content ~= nil and content.valid and not panel.vscroll then
                        local room = panel.renderedHeight
                        if not stacked then
                            local scale = panel.renderedWidth / columnWidth
                            room = room - 2 * COLUMN_VPAD * scale
                        end
                        if content.renderedHeight > room + 0.5 then
                            panel.vscroll = true
                        end
                    end
                end
            end
        end)
    end
    local refreshRows = Refresh
    Refresh = function()
        refreshRows()
        FitScroll()
    end
    Refresh()

    --- @type HeroSkillsPanelControl
    local control = {
        ClearSelection = function()
            if HeroSkillsLanguages.Deselect(draft) then
                Changed()
                return true
            end
            return false
        end,
        SetDraft = SetDraft,
    }
    return root, control
end
