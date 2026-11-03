local mod = dmhub.GetModLoading()

--The Hero sheet's Features list: the Features tab beside Abilities at Wide,
--the Features pane at Medium. The Core feature leads as a card, then a group
--per origin ("Class - Tactician - Vanguard"), each feature a card with its
--pillar tags, its text cut short behind Show more, and View ability for the
--abilities it grants. Pillar chips and a search filter the list; groups then
--read "3 of 11".
--
--Choices are made in the list: an unmade one has its own card with a Choose
--plate and the options (always); a made one can be changed from its card in
--Edit mode. Edit mode also brings the bar (New feature, Paste feature,
--Show hidden features). Each card has a "..." menu, as an ability row does:
--Copy and Share to chat, and in Edit mode Edit and Delete on a custom feature.
--The Hero sheet has no creature templates: only retainers and monsters use
--them, and those keep the old sheet. The shared feature editor opens through
--the editor bridge (HeroSheetWrite.Bridge).
--
--The features come from the shared read of the Hero (HeroSheetRefresh.Read,
--the same leaves and "Chosen for" lines as the EotW sheet), with the custom
--and other features the EotW sheet leaves out. Cards are kept in pools and
--painted for each Hero; nothing is rebuilt on a switch.

HeroSheetFeatures = rawget(_G, "HeroSheetFeatures") or {}

--A feature's text longer than this starts cut short behind Show more (the
--EotW sheet's limit, about three lines in the Wide column).
local FOLD_CHARS = 300

--The pillar filter chips after All. They always show, even when no feature
--has that tag.
local PILLARS = {"Combat", "Exploration", "Negotiation", "Respite"}

local DOT = " \u{00B7} "

--The old sheet's per-player Show hidden features switch, shared so both
--sheets agree.
local SHOW_HIDDEN_SETTING = "featuretags:showall"

--The tags that keep a feature out of the list, as its card names them when
--Show hidden features is on.
local HIDDEN_KINDS = {hidden = "Hidden", ability = "Ability", trigger = "Trigger"}

--The index's buckets the list never shows: skills and languages have the
--band and their windows, conditions and effects the character panel,
--treasures the card.
local SKIP_BUCKETS = {skill = true, language = true, condition = true, effect = true, treasure = true}

--The groups after the Core feature, in order. A group with `join` names its
--origins in its header: "Class - Tactician - Vanguard", "Culture -
--Secluded, Bureaucratic, Martial".
--Room a card's title line sets aside beside the name, in sheet units: the
--Core feature pill, the Custom or Hidden pill, a gap, and for each pillar tag
--its pill's padding and margin on top of its text.
local CORE_PILL_ROOM = 110
local SMALL_PILL_ROOM = 70
local NAME_GAP = 10
local TAG_PILL_PADDING = 19

local SECTIONS = {
    {id = "class", label = "Class", join = DOT},
    {id = "kit", label = "Kit", join = DOT},
    {id = "ancestry", label = "Ancestry", join = DOT},
    {id = "title", label = "Titles"},
    {id = "career", label = "Career", join = DOT},
    {id = "culture", label = "Culture", join = ", "},
    {id = "complication", label = "Complication", join = DOT},
    {id = "perk", label = "Perks"},
    {id = "other", label = "Other"},
    {id = "custom", label = "Custom"},
}

--- @class HeroFeatureAbility
--- @field name string
--- @field ability nil|ActivatedAbility
--- @field trigger nil|any a triggered ability, drawn with its own Render

--- @class HeroFeatureChoice
--- @field slot any the choice feature (a CharacterChoice)
--- @field guid string the slot's guid: its picks are levelChoices[guid]
--- @field index integer which pick this is
--- @field perk boolean a perk slot ("Choose a perk", the "<perk> chosen." toast)
--- @field unspent integer picks (or points) still to choose; 0 for a made pick

--- @class HeroFeatureItem
--- @field key string the feature's guid (or name), for its Show more state
--- @field name string
--- @field sub nil|string the muted line: "Chosen for X", a title's benefit, a class feature's Level
--- @field text string
--- @field pillars string[]
--- @field core boolean
--- @field custom boolean
--- @field abilities HeroFeatureAbility[]
--- @field search string name, line and text, lowercased, for the search
--- @field feature any the feature itself (custom ones are edited, copied and deleted from it)
--- @field hiddenKind nil|string "Hidden", "Ability" or "Trigger": shown only with Show hidden features
--- @field choice nil|HeroFeatureChoice an unmade pick (its card offers the options) or, on a chosen feature, the pick Edit mode can change
--- @field grants any[] modifiers with their own controls on the card (Grant Treasure)
--- @field claim nil|integer its Grant Treasure picks still to claim (set by Add)
--- @field growing nil|HeroFeatureGrowRow[] a growing resource table's rows (Growing Ferocity)
--- @field titleChoose nil|string a held title whose benefit is still to choose: its id (the plate opens the Titles window there)

--- @class HeroFeatureGrowRow
--- @field resources number the resource it needs
--- @field level integer the Level it comes at
--- @field locked boolean above the Hero's Level: behind Show more
--- @field text string its short words, filled in for the Hero
--- @field tooltip nil|string its whole rule

--- @class HeroFeatureSection
--- @field id string
--- @field header string
--- @field items HeroFeatureItem[]
--- @field need integer picks still to choose in it ("2 to choose")
--- @field claim integer treasures still to claim in it ("1 to claim")

--- @class HeroFeatureModel
--- @field core HeroFeatureItem[]
--- @field sections table<string, HeroFeatureSection>

--- @return boolean
local function ShowHidden()
    return dmhub.GetSettingValue(SHOW_HIDDEN_SETTING) == true
end

----------------------------------------------------------------------
--Reading the Hero.

--Codex text carries markup the cards do not draw: tags, **bold** and
--*italics*.
--- @param text any
--- @return string
local function Clean(text)
    if text == nil then
        return ""
    end
    text = tostring(text)
    text = string.gsub(text, "<[^>]*>", "")
    text = string.gsub(text, "%*%*(.-)%*%*", "%1")
    text = string.gsub(text, "%*([^%*\n]-)%*", "%1")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

--- @param feature any
--- @return string
local function Description(feature)
    local text = ""
    pcall(function() text = Clean(feature:GetDescription()) end)
    if text == "" then
        pcall(function() text = Clean(feature:try_get("description")) end)
    end
    return text
end

--Whether a tag is a game-mode pillar (Combat, Exploration...), from the
--registered feature tags.
--- @param tag string
--- @return boolean
local function IsPillar(tag)
    for _, featureTag in ipairs(GameSystem.featureTags or {}) do
        if featureTag.name == tag then
            return featureTag.gameMode == true
        end
    end
    return false
end

--- @param feature any
--- @return string[]
local function Pillars(feature)
    local result = {}
    pcall(function()
        for tag, on in pairs(feature:try_get("tags") or {}) do
            if on and IsPillar(tag) then
                result[#result+1] = tag
            end
        end
    end)
    table.sort(result)
    return result
end

--A class feature's muted line: "Level 5, upgraded at levels 7, 9".
--- @param levels nil|integer[]
--- @return string
local function LevelLine(levels)
    if levels == nil or levels[1] == nil then
        return ""
    end
    local text = string.format("Level %d", math.max(1, levels[1]))
    if #levels > 1 then
        text = string.format("%s, upgraded at level%s %d", text, cond(#levels > 2, "s", ""), levels[2])
        for i = 3, #levels do
            text = string.format("%s, %d", text, levels[i])
        end
    end
    return text
end

--The abilities a feature grants, found as the old sheet finds them: its
--modifiers that carry an ability.
--- @param feature any
--- @return HeroFeatureAbility[]
local function GrantedAbilities(feature)
    local result = {}
    pcall(function()
        for _, modifier in ipairs(feature:try_get("modifiers", {})) do
            local behavior = modifier.behavior
            if behavior == "activated" then
                local ability = rawget(modifier, "activatedAbility")
                if ability ~= nil then
                    result[#result+1] = {name = ability.name, ability = ability}
                end
            elseif behavior == "triggerdisplay" or behavior == "routine" then
                local ability = rawget(modifier, "ability")
                if ability ~= nil then
                    result[#result+1] = {name = ability.name or "", trigger = ability}
                end
            end
        end
    end)
    return result
end

--A feature's modifiers that bring their own controls to its card (their
--CreateSheetPanel, as the old sheet draws them: Grant Treasure's pick and Claim).
--- @param feature any
--- @return any[]
local function Grants(feature)
    local result = {}
    pcall(function()
        for _, modifier in ipairs(feature:try_get("modifiers", {})) do
            local info = CharacterModifier.TypeInfo[modifier.behavior]
            if info ~= nil and info.createSheetPanel ~= nil then
                result[#result+1] = modifier
            end
        end
    end)
    return result
end

--How many of a choice slot's picks are still to make (the old sheet's rule). For a
--slot that costs points, NumChoices is the points budget, so it counts the
--points spent; a slot that can offer nothing more counts as made.
--- @param slot any
--- @param creature creature
--- @return integer
local function Unspent(slot, creature)
    local unspent = 0
    pcall(function()
        local num = slot:NumChoices(creature)
        if num == nil or num <= 0 then
            return
        end
        local made = creature:GetLevelChoices()[slot.guid] or {}
        if slot:try_get("costsPoints") then
            local options = slot:GetOptions(creature:GetLevelChoices()) or {}
            local spent = 0
            for _, id in ipairs(made) do
                for _, opt in ipairs(options) do
                    if opt.guid == id then
                        spent = spent + (rawget(opt, "pointsCost") or 1)
                        break
                    end
                end
            end
            unspent = math.max(0, num - spent)
        else
            unspent = math.max(0, num - #made)
        end
        if unspent > 0 then
            local nextOptions = slot:Choices(#made + 1, made, creature)
            if nextOptions == nil or #nextOptions == 0 then
                unspent = 0
            end
        end
    end)
    return unspent
end

--- @param name string
--- @param sub nil|string
--- @param text string
--- @return string
local function SearchText(name, sub, text)
    return string.lower(name .. " " .. (sub or "") .. " " .. text)
end

--The model made from the sheet's shared read, kept while that read is the
--same, so the block's signature and its paint share one.
--- @type {read: nil|table, model: HeroFeatureModel}
local g_model = {read = nil, model = {core = {}, sections = {}}}

--- Run one part of the Features list's read; a part that fails is logged
--- and left out, so one bad entry cannot empty the whole list.
--- @param label string what the part reads, for the log
--- @param fn fun()
local function Try(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        print(string.format("HEROSHEET:: Features list: reading %s failed: %s", label, tostring(err)))
    end
end

--- What the steps of Read share. Read fills the first fields; the steps
--- fill the rest as they go, so they run in a set order.
--- @class HeroFeatureReadContext
--- @field read nil|table the shared read of the Hero (HeroSheetRefresh.Read)
--- @field creature creature
--- @field model HeroFeatureModel the list being built
--- @field levelChoices table the Hero's picks, by choice slot guid
--- @field index nil|table the read's feature index: every feature and the entry it came from
--- @field groups table the index's entries by bucket ("title", "other", "custom"...)
--- @field entryByGuid table<string, table> an index entry by its feature's guid, or a leaf chosen in it (IndexEntries)
--- @field byName table<string, HeroFeatureItem> the first card for each name (filled by Add)
--- @field titled table<string, boolean> titles that have a card (AddReaderItems, AddTitles)
--- @field complicationChoices table<string, boolean> choice slots a complication card holds (AddComplications)
--- @field Add fun(sectionId: string, item: HeroFeatureItem) puts a card in its section

--- @param entry table an index entry
--- @return string
local function OwnText(entry)
    local text = ""
    pcall(function() text = Clean(entry.origin:try_get("description")) end)
    return text
end

--The pick a chosen feature came from, so Edit mode can change it.
--- @param ctx HeroFeatureReadContext
--- @param entry nil|table the slot's index entry
--- @param leafGuid nil|string
--- @return nil|HeroFeatureChoice
local function PickOf(ctx, entry, leafGuid)
    if entry == nil or leafGuid == nil or entry.chosen == nil or #entry.chosen == 0 then
        return nil
    end
    local slotGuid = nil
    pcall(function() slotGuid = entry.feature.guid end)
    if slotGuid == nil then
        return nil
    end
    for i, id in ipairs(ctx.levelChoices[slotGuid] or {}) do
        if id == leafGuid then
            return {slot = entry.feature, guid = slotGuid, index = i, perk = entry.bucket == "perk", unspent = 0}
        end
    end
    return nil
end

--Indexes the read's entries by guid, and names each group's origins in its
--header ("Class - Tactician - Vanguard").
--- @param ctx HeroFeatureReadContext
local function IndexEntries(ctx)
    local entryByGuid = ctx.entryByGuid
    --each bucket's origins, first seen first.
    local origins = {}
    for _, entry in ipairs((ctx.index ~= nil and ctx.index.features) or {}) do
        local guid = nil
        pcall(function() guid = entry.feature.guid end)
        if guid ~= nil then
            entryByGuid[guid] = entry
        end
        for _, chosenLeaf in ipairs(entry.chosen or {}) do
            local leafGuid = nil
            pcall(function() leafGuid = chosenLeaf.guid end)
            if leafGuid ~= nil and entryByGuid[leafGuid] == nil then
                entryByGuid[leafGuid] = entry
            end
        end
        local bucket = entry.bucket or "other"
        local name = entry.originName
        if type(name) == "string" and name ~= "" then
            local list = origins[bucket]
            if list == nil then
                list = {seen = {}}
                origins[bucket] = list
            end
            if not list.seen[name] then
                list.seen[name] = true
                list[#list+1] = cond(bucket == "ancestry", HeroBuild.SaidName(name), name)
            end
        end
    end
    --a culture's entries name no origin: its aspects do, in the rules'
    --order (environment, organization, upbringing).
    pcall(function()
        local culture = ctx.creature:GetCulture()
        local aspects = dmhub.GetTable(CultureAspect.tableName) or {}
        local list = {}
        for _, cat in ipairs(CultureAspect.categories) do
            local aspect = aspects[(culture.aspects or {})[cat.id] or ""]
            if aspect ~= nil then
                list[#list+1] = aspect.name
            end
        end
        if #list > 0 then
            origins.culture = list
        end
    end)
    for _, sectionDef in ipairs(SECTIONS) do
        local list = origins[sectionDef.id]
        if sectionDef.join ~= nil and list ~= nil and #list > 0 then
            ctx.model.sections[sectionDef.id].header = sectionDef.label .. DOT .. table.concat(list, sectionDef.join)
        end
    end
end

--The features the shared read lists, the same leaves and "Chosen for" lines
--as the EotW sheet. Needs IndexEntries.
--- @param ctx HeroFeatureReadContext
local function AddReaderItems(ctx)
    local read = ctx.read
    for _, section in ipairs((read ~= nil and read.features ~= nil and read.features.sections) or {}) do
        --a complication is one card of its own words (AddComplications).
        if not SKIP_BUCKETS[section.id] and section.id ~= "complication" then
            for _, listed in ipairs(section.items) do
                local entry = ctx.entryByGuid[listed.guid or ""]
                local subs = {}
                local text = Clean(listed.text)
                if section.id == "title" then
                    --named for the title, its benefit in the line, the
                    --title's own text before the benefit's.
                    ctx.titled[listed.name] = true
                    local benefit = nil
                    pcall(function() benefit = listed.feature.name end)
                    if benefit ~= nil and benefit ~= listed.name then
                        subs[#subs+1] = benefit
                    end
                    if entry ~= nil then
                        local own = OwnText(entry)
                        if own ~= "" then
                            text = cond(text ~= "", own .. "\n\n" .. text, own)
                        end
                    end
                elseif listed.chosenFor ~= nil then
                    subs[#subs+1] = "Chosen for " .. (string.match(listed.chosenFor, "^%s*(.-)%s*$") or listed.chosenFor)
                end
                if section.id == "class" and entry ~= nil then
                    local line = LevelLine(entry.levels)
                    if line ~= "" then
                        subs[#subs+1] = line
                    end
                end
                ctx.Add(section.id, {
                    key = tostring(listed.guid or listed.name),
                    name = listed.name or "",
                    sub = cond(#subs > 0, table.concat(subs, DOT), nil),
                    text = text,
                    pillars = listed.pillars or {},
                    core = section.id == "core",
                    custom = false,
                    abilities = GrantedAbilities(listed.feature),
                    search = "",
                    feature = listed.feature,
                    choice = cond(section.id ~= "title", PickOf(ctx, entry, listed.guid), nil),
                    grants = Grants(listed.feature),
                })
            end
        end
    end
end

--Growing resource tables (the Fury's Growing Ferocity, the Null's Masteries)
--are class core rules, so each is a Core card, named without its class
--("Growing Ferocity") with the class on the muted line.
--- @param ctx HeroFeatureReadContext
local function AddGrowingTables(ctx)
    local creature = ctx.creature
    local level = creature:CharacterLevel()
    for i, growTable in ipairs(creature:GetGrowingResourcesTables()) do
        local tableName = growTable:try_get("name") or ""
        local owner = (string.gsub(growTable:try_get("source") or "", "%s+%a+ Feature$", ""))
        local title = tableName
        if owner ~= "" and string.sub(tableName, 1, #owner + 1) == owner .. " " then
            title = string.sub(tableName, #owner + 2)
        end
        local rows = {}
        local words = {}
        for _, entry in ipairs(growTable:try_get("progression") or {}) do
            local text = ""
            pcall(function() text = StringInterpolateGoblinScript(entry.description or "", creature) or "" end)
            rows[#rows+1] = {
                resources = tonumber(entry.resources) or 0,
                level = tonumber(entry.level) or 0,
                locked = (tonumber(entry.level) or 0) > level,
                text = Clean(text),
                tooltip = entry.tooltip,
            }
            words[#words+1] = text
        end
        --- @type HeroFeatureItem
        local item = {
            key = "growing:" .. tostring(growTable:try_get("guid") or i),
            name = title ~= "" and title or "Growing Resource",
            sub = cond(owner ~= "", owner, nil),
            text = Clean(growTable:try_get("description")),
            pillars = {"Combat"},
            core = true,
            custom = false,
            abilities = {},
            search = "",
            feature = growTable,
            grants = {},
            growing = rows,
        }
        ctx.Add("class", item)
        item.search = item.search .. " " .. string.lower(table.concat(words, " "))
    end
end

--Held titles the shared read did not list. A title whose benefit is not
--chosen yet shows its own text and the Choose a benefit plate, which opens
--the Titles window on it. Needs AddReaderItems (ctx.titled).
--- @param ctx HeroFeatureReadContext
local function AddTitles(ctx)
    local heldTitles = {}
    Try("titles", function()
        for _, title in ipairs(ctx.creature:Titles()) do
            heldTitles[title.name] = title
        end
    end)
    --- @param name string
    --- @return nil|string the title's id when its benefit choice has no pick
    local function TitleToChoose(name)
        local title = heldTitles[name]
        if title == nil then
            return nil
        end
        local info = title:try_get("modifierInfo")
        for _, feature in ipairs((info ~= nil and info.features) or {}) do
            if feature.typeName == "CharacterFeatureChoice" then
                local picks = ctx.levelChoices[feature.guid]
                if type(picks) ~= "table" or picks[1] == nil then
                    return title.id
                end
            end
        end
        return nil
    end
    for _, entry in ipairs((ctx.groups.title ~= nil and ctx.groups.title.items) or {}) do
        if entry.name ~= nil and not ctx.titled[entry.name] then
            ctx.titled[entry.name] = true
            ctx.Add("title", {
                titleChoose = TitleToChoose(entry.name),
                key = tostring(entry.guid or entry.name),
                name = entry.name,
                sub = nil,
                text = OwnText(entry),
                pillars = {},
                core = false,
                custom = false,
                abilities = {},
                search = "",
                feature = entry.feature,
                grants = {},
            })
        end
    end
end

--Complications: one card each, its own Benefit and Drawback words. Its
--features only carry them out (repeating the words, or tagged Hidden), so
--they lend the card their abilities, grants and pillars, its option picks
--("Chosen: Fire Damage") and one choice to make or change. Skill and
--language picks stay in their windows. Fills ctx.complicationChoices.
--- @param ctx HeroFeatureReadContext
local function AddComplications(ctx)
    local creature = ctx.creature
    local index = ctx.index
    local items = dmhub.GetTableVisible(CharacterComplication.tableName) or {}
    local ids = {}
    for id, _ in pairs(creature:try_get("complications", {})) do
        ids[#ids+1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local complication = items[id]
        if complication ~= nil then
            local abilities, grants, chosen = {}, {}, {}
            local pillarSet = {}
            local choice = nil
            local walked = {}
            local function Walk(feature)
                local guid = nil
                pcall(function() guid = feature.guid end)
                if guid ~= nil then
                    if walked[guid] then
                        return
                    end
                    walked[guid] = true
                end
                for _, ability in ipairs(GrantedAbilities(feature)) do
                    abilities[#abilities+1] = ability
                end
                for _, modifier in ipairs(Grants(feature)) do
                    grants[#grants+1] = modifier
                end
                for _, pillar in ipairs(Pillars(feature)) do
                    pillarSet[pillar] = true
                end
                pcall(function()
                    for _, sub in ipairs(feature:try_get("features") or {}) do
                        Walk(sub)
                    end
                end)
            end
            for _, entry in ipairs((index ~= nil and index.features) or {}) do
                local originId = nil
                pcall(function() originId = entry.origin.id end)
                --a skill, language or perk slot (all bucketed under the
                --complication) keeps its own window or card.
                if originId == id and FeatureCategoriser.ChoiceBucket(entry.feature) == nil then
                    local isChoice = false
                    pcall(function() isChoice = entry.feature.IsDerivedFrom("CharacterChoice") end)
                    if isChoice then
                        for _, leaf in ipairs(entry.chosen or {}) do
                            local name = nil
                            pcall(function() name = leaf.name end)
                            if type(name) == "string" and name ~= "" then
                                chosen[#chosen+1] = name
                            end
                            Walk(leaf)
                        end
                        local guid = nil
                        pcall(function() guid = entry.feature.guid end)
                        if guid ~= nil then
                            local unspent = Unspent(entry.feature, creature)
                            local made = ctx.levelChoices[guid] or {}
                            --an unmade choice first; else the first made one, for Edit mode.
                            if choice == nil or (choice.unspent == 0 and unspent > 0) then
                                choice = {slot = entry.feature, guid = guid, index = cond(unspent > 0, #made + 1, 1), perk = false, unspent = unspent}
                            end
                        end
                    else
                        Walk(entry.feature)
                    end
                end
            end
            if choice ~= nil then
                ctx.complicationChoices[choice.guid] = true
            end
            local benefit = Clean(complication:try_get("benefit"))
            local drawback = Clean(complication:try_get("drawback"))
            local parts = {}
            if drawback == "" then
                if benefit ~= "" then
                    parts[1] = "<b>Benefit and Drawback.</b> " .. benefit
                end
            else
                if benefit ~= "" then
                    parts[#parts+1] = "<b>Benefit.</b> " .. benefit
                end
                parts[#parts+1] = "<b>Drawback.</b> " .. drawback
            end
            local pillars = {}
            for pillar, _ in pairs(pillarSet) do
                pillars[#pillars+1] = pillar
            end
            table.sort(pillars)
            ctx.Add("complication", {
                key = "complication:" .. id,
                name = complication.name or "Complication",
                sub = cond(#chosen > 0, "Chosen: " .. table.concat(chosen, ", "), nil),
                text = table.concat(parts, "\n\n"),
                pillars = pillars,
                core = false,
                custom = false,
                abilities = abilities,
                search = "",
                feature = complication,
                choice = choice,
                grants = grants,
            })
        end
    end
end

--Custom and "other" features: the EotW sheet does not list these, so they
--are added here.
--- @param ctx HeroFeatureReadContext
local function AddOtherAndCustom(ctx)
    for _, bucket in ipairs({"other", "custom"}) do
        for _, entry in ipairs((ctx.groups[bucket] ~= nil and ctx.groups[bucket].items) or {}) do
            if entry.displayKind == nil or entry.displayKind == "normal" then
                local leaves = entry.chosen
                if leaves == nil or #leaves == 0 then
                    local typeName = nil
                    pcall(function() typeName = entry.feature.typeName end)
                    --an unmade choice gets its own card (AddUnmadeChoices).
                    leaves = cond(type(typeName) == "string" and string.find(typeName, "Choice", 1, true) ~= nil, {}, {entry.feature})
                end
                for _, leaf in ipairs(leaves) do
                    local name = nil
                    pcall(function() name = leaf.name end)
                    local guid = nil
                    pcall(function() guid = leaf.guid end)
                    ctx.Add(bucket, {
                        key = tostring(guid or name),
                        name = name or "Feature",
                        sub = nil,
                        text = Description(leaf),
                        pillars = Pillars(leaf),
                        core = false,
                        custom = bucket == "custom",
                        abilities = GrantedAbilities(leaf),
                        search = "",
                        feature = leaf,
                        choice = PickOf(ctx, entry, guid),
                        grants = Grants(leaf),
                    })
                end
            end
        end
    end
end

--Chosen perks: a perk slot's pick is a perk from the perks table, which the
--shared read does not open. Each shows as its own card (the old sheet names
--the row after the perk too), changeable in Edit mode. A perk that already
--has a card (a career's perk) gains its line instead: needs every step before.
--- @param ctx HeroFeatureReadContext
local function AddPerks(ctx)
    local perks = dmhub.GetTable(CharacterFeat.tableName) or {}
    for _, entry in ipairs((ctx.index ~= nil and ctx.index.features) or {}) do
        local typeName, guid = nil, nil
        pcall(function() typeName = entry.feature.typeName end)
        pcall(function() guid = entry.feature.guid end)
        if typeName == "CharacterFeatChoice" and guid ~= nil and not SKIP_BUCKETS[entry.bucket or "other"] then
            for i, id in ipairs(ctx.levelChoices[guid] or {}) do
                local perk = perks[id]
                local line = LevelLine(entry.levels)
                local chosenFor = "Chosen for " .. (entry.name or "Perk") .. cond(line ~= "", DOT .. line, "")
                local listed = perk ~= nil and ctx.byName[perk.name] or nil
                if listed ~= nil and listed.choice == nil then
                    listed.sub = cond(listed.sub ~= nil, tostring(listed.sub) .. DOT .. chosenFor, chosenFor)
                    listed.search = SearchText(listed.name, listed.sub, listed.text)
                    listed.choice = {slot = entry.feature, guid = guid, index = i, perk = true, unspent = 0}
                elseif perk ~= nil then
                    local abilities = {}
                    pcall(function()
                        for _, feature in ipairs(perk:GetClassLevel().features) do
                            for _, ability in ipairs(GrantedAbilities(feature)) do
                                abilities[#abilities+1] = ability
                            end
                        end
                    end)
                    ctx.Add(entry.bucket or "perk", {
                        key = "perk:" .. tostring(id),
                        name = perk.name or "Perk",
                        sub = chosenFor,
                        text = Clean(perk:try_get("description")),
                        pillars = Pillars(perk),
                        core = false,
                        custom = false,
                        abilities = abilities,
                        search = "",
                        feature = perk,
                        choice = {slot = entry.feature, guid = guid, index = i, perk = true, unspent = 0},
                        grants = {},
                    })
                end
            end
        end
    end
end

--Unmade choices: the slot's own card, with its options. Skills and
--languages are chosen in their windows, a title's benefit in the Titles
--window. Needs AddComplications (ctx.complicationChoices).
--- @param ctx HeroFeatureReadContext
local function AddUnmadeChoices(ctx)
    for _, entry in ipairs((ctx.index ~= nil and ctx.index.features) or {}) do
        local bucket = entry.bucket or "other"
        local slotGuid = nil
        pcall(function() slotGuid = entry.feature.guid end)
        if entry.kind == "build" and not SKIP_BUCKETS[bucket] and bucket ~= "title" and not ctx.complicationChoices[slotGuid or ""] then
            local unspent = Unspent(entry.feature, ctx.creature)
            if unspent > 0 then
                local guid = slotGuid
                local made = ctx.levelChoices[guid or ""] or {}
                local line = cond(bucket == "class", LevelLine(entry.levels), "")
                ctx.Add(bucket, {
                    --HasMenu reads this prefix: an unmade choice's card has no menu.
                    key = "choice:" .. tostring(guid),
                    name = entry.name or "Choice",
                    sub = cond(line ~= "", line, nil),
                    text = Description(entry.feature),
                    pillars = {},
                    core = false,
                    custom = false,
                    abilities = {},
                    search = "",
                    feature = entry.feature,
                    choice = {slot = entry.feature, guid = guid or "", index = #made + 1, perk = bucket == "perk", unspent = unspent},
                    grants = {},
                })
            end
        end
    end
end

--Show hidden features (Edit mode): what its tags keep out of the list,
--named by the tag.
--- @param ctx HeroFeatureReadContext
local function AddHidden(ctx)
    for _, entry in ipairs((ctx.index ~= nil and ctx.index.features) or {}) do
        local bucket = entry.bucket or "other"
        local kind = HIDDEN_KINDS[entry.displayKind or "normal"]
        if kind ~= nil and not SKIP_BUCKETS[bucket] then
            local guid = nil
            pcall(function() guid = entry.feature.guid end)
            ctx.Add(bucket, {
                key = "hidden:" .. tostring(guid or entry.name),
                name = entry.name or "Feature",
                sub = nil,
                text = Description(entry.feature),
                pillars = Pillars(entry.feature),
                core = false,
                custom = bucket == "custom",
                abilities = GrantedAbilities(entry.feature),
                search = "",
                feature = entry.feature,
                hiddenKind = kind,
                grants = {},
            })
        end
    end
end

--- The Hero's features, grouped for the list.
--- @param token CharacterToken
--- @return HeroFeatureModel
local function Read(token)
    local read = HeroSheetRefresh.Read(token)
    if read ~= nil and g_model.read == read then
        return g_model.model
    end
    local creature = token.properties
    --- @type HeroFeatureModel
    local model = {core = {}, sections = {}}
    for _, sectionDef in ipairs(SECTIONS) do
        model.sections[sectionDef.id] = {id = sectionDef.id, header = sectionDef.label, items = {}, need = 0, claim = 0}
    end
    local levelChoices = {}
    pcall(function() levelChoices = creature:GetLevelChoices() or {} end)
    local index = read ~= nil and read.index or nil

    --A Grant Treasure pick still to claim (claim delivery only: a manifest
    --grant has no Claim).
    local treasureGrants = {}
    pcall(function() treasureGrants = creature:try_get("treasureGrants") or {} end)
    --- @param grants any[]
    --- @return integer
    local function Unclaimed(grants)
        local unclaimed = 0
        for _, modifier in ipairs(grants) do
            local delivery, state = "claim", nil
            pcall(function()
                delivery = modifier:try_get("treasureDelivery", "claim")
                state = treasureGrants[modifier.guid]
            end)
            if delivery == "claim" and not (type(state) == "table" and state.claimed == true) then
                unclaimed = unclaimed + 1
            end
        end
        return unclaimed
    end

    --- @type HeroFeatureReadContext
    local ctx
    ctx = {
        read = read,
        creature = creature,
        model = model,
        levelChoices = levelChoices,
        index = index,
        groups = (index ~= nil and index.groups) or {},
        entryByGuid = {},
        byName = {},
        titled = {},
        complicationChoices = {},
        Add = function(sectionId, item)
            item.search = SearchText(item.name, item.sub, item.text)
            item.claim = Unclaimed(item.grants)
            if ctx.byName[item.name] == nil then
                ctx.byName[item.name] = item
            end
            if item.core then
                model.core[#model.core+1] = item
                return
            end
            local section = model.sections[sectionId] or model.sections.other
            section.items[#section.items+1] = item
            if item.choice ~= nil then
                section.need = section.need + item.choice.unspent
            end
            if item.titleChoose ~= nil then
                section.need = section.need + 1
            end
            section.claim = section.claim + item.claim
        end,
    }

    --The order matters: each step's comment names the earlier steps it needs.
    IndexEntries(ctx)
    AddReaderItems(ctx)
    Try("growing tables", function() AddGrowingTables(ctx) end)
    AddTitles(ctx)
    Try("complications", function() AddComplications(ctx) end)
    AddOtherAndCustom(ctx)
    AddPerks(ctx)
    AddUnmadeChoices(ctx)
    AddHidden(ctx)

    g_model = {read = read, model = model}
    return model
end

--What the list shows, as a string: equal strings mean nothing to paint.
--- @param token CharacterToken
--- @return string
local function Signature(token)
    local model = Read(token)
    local parts = {tostring(HeroSheetWrite.CanWrite())}
    --a grant's controls change with its claim.
    pcall(function() parts[#parts+1] = dmhub.ToJson(token.properties:try_get("treasureGrants") or {}) end)
    --a growing table's lit rows follow the resource, this turn's highest, and combat.
    if #model.core > 0 then
        pcall(function()
            local hero = token.properties
            local queue = dmhub.initiativeQueue
            parts[#parts+1] = string.format("%s|%s|%s", tostring(hero:GetProgressionResource()),
                tostring(hero:GetProgressionResourceHighWaterMark()), tostring(queue ~= nil and not queue.hidden))
        end)
    end
    --- @param item HeroFeatureItem
    local function Put(item)
        if item.growing ~= nil then
            for _, row in ipairs(item.growing) do
                parts[#parts+1] = string.format("%s|%s|%s", tostring(row.resources), tostring(row.locked), row.text)
            end
        end
        local choice = item.choice
        parts[#parts+1] = string.format("%s|%s|%s|%s|%s|%d|%s|%s|%s", item.name, tostring(item.sub), table.concat(item.pillars, ","),
            item.text, tostring(item.custom), #item.abilities, tostring(item.hiddenKind),
            choice ~= nil and string.format("%s:%d:%d", choice.guid, choice.index, choice.unspent) or "", tostring(item.titleChoose))
    end
    for _, item in ipairs(model.core) do
        Put(item)
    end
    for _, sectionDef in ipairs(SECTIONS) do
        local section = model.sections[sectionDef.id]
        parts[#parts+1] = section.header
        for _, item in ipairs(section.items) do
            Put(item)
        end
    end
    return table.concat(parts, "\n")
end

----------------------------------------------------------------------
--Changing the Hero.

--A choice made in a card: one undo step. A perk says so in a toast.
--- @param choice HeroFeatureChoice
--- @param id string the option's id ("none" clears the pick)
--- @param text string the option's name
local function Choose(choice, id, text)
    local value = cond(id == "none", nil, id)
    local saved = HeroSheetWrite.Save{
        description = cond(choice.perk, "Choose a perk", "Make a choice"),
        execute = function(props)
            local levelChoices = props:GetLevelChoices()
            local picks = levelChoices[choice.guid] or {}
            picks[choice.index] = value
            levelChoices[choice.guid] = picks
        end,
    }
    if saved then
        HeroSheet.Saved()
        if choice.perk and value ~= nil and choice.unspent > 0 then
            HeroSheetWindow.Toast(string.format("%s chosen.", text))
        end
    end
end

--Where the shared feature and ability editors open: the main dialog layer,
--above the sheet whether it is docked or maximized.
--- @param fallback Panel
--- @return Panel
local function DialogLayer(fallback)
    local hud = GameHud.instance
    if hud then
        local layer = hud:try_get("mainDialogPanel")
        if layer ~= nil and layer.valid then
            return layer
        end
    end
    return fallback.root
end

--Calls done once the shared feature editor has closed (it destroys itself on
--Confirm or Cancel and tells nobody). A destroyed panel errors on any read,
--so it is checked under pcall.
--- @param editor Panel
--- @param layer Panel
--- @param done fun()
local function WhenClosed(editor, layer, done)
    layer:AddChild(gui.Panel{
        floating = true,
        interactable = false,
        width = 1,
        height = 1,
        thinkTime = 0.2,
        think = function(element)
            local open = false
            pcall(function() open = editor.valid end)
            if not open then
                element:DestroySelf()
                done()
            end
        end,
    })
end

--The shared feature editor on a custom feature, through the editor
--bridge: it changes the Hero in place, and closing it saves that as one undo
--step. A new feature is added first so the editor has it; Cancel takes it out.
--- @param from Panel
--- @param featureOf nil|fun(props: creature): nil|any the feature to edit; nil makes a new one
--- @param description string
local function OpenFeatureEditor(from, featureOf, description)
    local isNew = featureOf == nil
    HeroSheetWrite.Bridge{
        description = description,
        fields = {"characterFeatures"},
        open = function(props, done)
            local feature = nil
            if featureOf ~= nil then
                feature = featureOf(props)
                if feature == nil then
                    --deleted meanwhile (another client, or an undo): nothing
                    --to edit, and nothing to save.
                    return
                end
            end
            if isNew then
                feature = CharacterFeature.Create{}
                local list = props:try_get("characterFeatures", {})
                list[#list+1] = feature
                props.characterFeatures = list
            end
            local editor = feature:PopupEditor{
                cancel = function(cancelled)
                    if not isNew then
                        return
                    end
                    local list = props:try_get("characterFeatures", {})
                    for i = #list, 1, -1 do
                        if list[i] == cancelled then
                            table.remove(list, i)
                        end
                    end
                    props.characterFeatures = list
                end,
            }
            local layer = DialogLayer(from)
            layer:AddChild(editor)
            WhenClosed(editor, layer, function()
                done()
                HeroSheet.Saved()
            end)
        end,
    }
end

--- The copied feature or ability, if the clipboard holds one.
--- @return any
local function ClipboardFeature()
    local item = dmhub.GetInternalClipboard()
    if item ~= nil and (item.typeName == "CharacterFeature" or item.typeName == "ActivatedAbility") then
        return item
    end
    return nil
end

--Adds a copy of the copied feature, or a feature granting the copied
--ability (as the old sheet's Paste Feature). A copy is a new feature: fresh guids.
local function PasteFeature()
    local item = ClipboardFeature()
    if item == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local feature
    if item.typeName == "CharacterFeature" then
        feature = DeepCopy(item)
        DeepReplaceGuids(feature)
    else
        local ability = DeepCopy(item)
        DeepReplaceGuids(ability)
        feature = CharacterFeature.Create{
            name = ability.name,
            modifiers = {
                CharacterModifier.new{
                    guid = dmhub.GenerateGuid(),
                    name = ability.name,
                    description = "",
                    behavior = "activated",
                    activatedAbility = ability,
                },
            },
        }
    end
    HeroSheetWrite.Save{
        description = "Paste feature",
        execute = function(props)
            local list = props:try_get("characterFeatures", {})
            list[#list+1] = feature
            props.characterFeatures = list
        end,
    }
    HeroSheet.Saved()
end

--Delete asks first; undo puts it back.
--- @param item HeroFeatureItem
local function DeleteFeature(item)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    local token = HeroSheet.Token()
    local guid = nil
    pcall(function() guid = item.feature.guid end)
    HeroSheetWindow.ShowDialog{
        title = string.format("Delete %s?", item.name),
        width = 520,
        bodyHeight = 22,
        body = HeroSheetWindow.DialogText(string.format("It leaves %s, with everything it grants.", token ~= nil and token.name or "this Hero")),
        saveText = "Delete",
        onSave = function()
            HeroSheetWrite.Save{
                description = "Delete feature",
                execute = function(props)
                    local list = props:try_get("characterFeatures", {})
                    for i = #list, 1, -1 do
                        if list[i] == item.feature or (guid ~= nil and list[i]:try_get("guid") == guid) then
                            table.remove(list, i)
                        end
                    end
                    props.characterFeatures = list
                end,
            }
            HeroSheet.Saved()
        end,
    }
end

----------------------------------------------------------------------
--The card's menu.

--- What Copy copies: the feature the Hero holds, which is the compendium's
--- own definition (every modifier comes with it); a perk's is the perk's one
--- feature. nil when Paste feature could not take it (a choice, a perk of
--- several features).
--- @param item HeroFeatureItem
--- @return nil|CharacterFeature
local function CopyableFeature(item)
    local feature = item.feature
    if feature == nil then
        return nil
    end
    local typeName = nil
    pcall(function() typeName = feature.typeName end)
    if typeName == "CharacterFeat" then
        --a perk: its one feature, read without making a modifierInfo it lacks.
        local info = feature:try_get("modifierInfo")
        local only = nil
        local count = 0
        for _, subFeature in ipairs((info ~= nil and info.features) or {}) do
            if subFeature.typeName == "CharacterFeature" then
                only = subFeature
                count = count + 1
            end
        end
        return cond(count == 1, only, nil)
    end
    if typeName ~= "CharacterFeature" then
        return nil
    end
    return feature --[[@as CharacterFeature]]
end

--A feature shared to chat: its name and text as its card shows them. Chat
--draws a shared object with the object's own Render, which features lack.
--- @class HeroSheetSharedFeature: GameType
--- @field new fun(o?: table): HeroSheetSharedFeature
--- @field name string
--- @field text string
HeroSheetSharedFeature = RegisterGameType("HeroSheetSharedFeature")
HeroSheetSharedFeature.name = ""
HeroSheetSharedFeature.text = ""

--- Chat's card for a shared feature.
--- @param options nil|table chat's options (its width)
--- @param params nil|table
--- @return Panel
function HeroSheetSharedFeature:Render(options, params)
    local width = options ~= nil and options.width or 340
    return gui.Panel{
        width = width,
        height = "auto",
        flow = "vertical",
        gui.Label{
            text = self.name,
            fontSize = 17,
            bold = true,
            width = "100%",
            height = "auto",
            textWrap = true,
        },
        gui.Label{
            text = self.text,
            fontSize = 14,
            width = "100%",
            height = "auto",
            textWrap = true,
            tmargin = 4,
        },
    }
end

--- Whether a card has the "..." menu: not on a choice still to make, and
--- not for a view-only Hero (as the ability rows).
--- @param item HeroFeatureItem
--- @return boolean
local function HasMenu(item)
    --an unmade choice's own card (key "choice:<guid>", set in
    --AddUnmadeChoices) has no menu; a complication with an unmade pick does.
    return HeroSheetWrite.CanWrite() and string.sub(item.key, 1, 7) ~= "choice:"
end

--- The card's menu, beside its "...": Copy and Share to chat; in Edit mode,
--- Edit and Delete on a custom feature. The ability rows' words.
--- @param anchor Panel
--- @param item HeroFeatureItem
--- @param from Panel where the feature editor opens from
local function FeatureMenu(anchor, item, from)
    local entries = {}
    local source = CopyableFeature(item)
    if source ~= nil then
        entries[#entries+1] = {text = "Copy", click = function()
            dmhub.CopyToInternalClipboard(source)
            HeroSheetWindow.Toast(string.format("Copied %s.", item.name))
        end}
    end
    entries[#entries+1] = {text = "Share to chat", click = function()
        local token = HeroSheet.Token()
        chat.ShareObjectInfo(nil, nil, {
            charid = token ~= nil and token.charid or nil,
            ability = HeroSheetSharedFeature.new{name = item.name, text = item.text},
        })
    end}
    if HeroSheet.Editing() and item.custom and item.hiddenKind == nil then
        local guid = nil
        pcall(function() guid = item.feature.guid end)
        entries[#entries+1] = "-"
        entries[#entries+1] = {text = "Edit", click = function()
            OpenFeatureEditor(from, function(props)
                for _, feature in ipairs(props:try_get("characterFeatures", {})) do
                    if feature == item.feature or (guid ~= nil and feature:try_get("guid") == guid) then
                        return feature
                    end
                end
                return nil
            end, "Edit feature")
        end}
        entries[#entries+1] = {text = "Delete", danger = true, click = function()
            DeleteFeature(item)
        end}
    end
    HeroSheetLists.ShowMenu(anchor, entries)
end

----------------------------------------------------------------------
--Cards.

--A small bordered pill on a card's title line (a pillar tag, Core feature).
--- @param text string
--- @param classes nil|string[] the pill's own classes (default heroSheetFeatTag)
--- @return Panel pill
--- @return Panel label
local function Pill(text, classes)
    local label = gui.Label{
        classes = {"heroSheetCardSub"},
        text = text,
        fontSize = 11.5,
        width = "auto",
        height = "auto",
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    local pill = gui.Panel{
        classes = classes or {"heroSheetFeatTag"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 9,
        width = "auto",
        height = 18,
        hpad = 7,
        borderBox = true,
        lmargin = 5,
        valign = "center",
        interactable = false,
        label,
    }
    return pill, label
end

--A text link's label fields, under a card's text (Show more, View ability).
--- @param text string
--- @param class string heroSheetFeatLink (warm) or heroSheetFeatLinkLight
--- @param args table more label fields (click, data...)
--- @return table
local function LinkArgs(text, class, args)
    args.classes = {class, "hoverable"}
    args.text = text
    args.fontSize = 13
    args.underline = true
    args.width = "auto"
    args.height = HeroSheetWindow.TargetSize(22)
    args.rmargin = 14
    args.valign = "center"
    args.textWrap = false
    return args
end

--One choice's options as a dropdown (the old sheet's per-pick dropdown, restyled).
--- @param choice HeroFeatureChoice
--- @return nil|Panel
local function ChoiceDropdown(choice)
    local token = HeroSheet.Token()
    if token == nil then
        return nil
    end
    local options, chosen = nil, "none"
    pcall(function()
        local made = token.properties:GetLevelChoices()[choice.guid] or {}
        options = choice.slot:Choices(choice.index, made, token.properties)
        chosen = made[choice.index] or "none"
    end)
    if options == nil or #options == 0 then
        return nil
    end
    return gui.Dropdown{
        classes = {"heroSheetField"},
        width = 240,
        height = HeroSheetWindow.TargetSize(28),
        halign = "left",
        valign = "center",
        textDefault = cond(choice.perk, "Choose a perk", "Choose..."),
        sort = true,
        hasSearch = #options > 12,
        options = options,
        idChosen = chosen,
        change = function(element)
            ---@cast element Dropdown
            local id = tostring(element.idChosen or "none")
            local text = ""
            for _, option in ipairs(options or {}) do
                if option.id == id then
                    text = option.text or ""
                end
            end
            Choose(choice, id, text)
        end,
    }
end

--- @class HeroFeatureCard
--- @field panel Panel
--- @field paint fun(item: HeroFeatureItem)
--- @field item nil|HeroFeatureItem

--One feature card: the name, Core feature, the pillar tags at the right (and
--Custom), the muted line, the text cut short behind Show more, View ability
--(the granted ability's own card on hover, pinned on click), the choice it
--offers, a grant's controls, and the "..." menu. Made once and painted for
--each feature.
--- @param expanded table<string, boolean> the features showing their whole text, by key
--- @param from Panel where the shared editors open from
--- @return HeroFeatureCard
local function NewCard(expanded, from)
    --- @type HeroFeatureCard
    local card
    local name = gui.Label{
        classes = {"heroSheetCardStrong"},
        fontSize = 16,
        bold = true,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = true,
        interactable = false,
    }
    local corePill = Pill("Core feature")
    corePill:SetClass("collapsed", true)
    corePill.selfStyle.lmargin = 8
    corePill.selfStyle.halign = "left"
    local hiddenPill, hiddenLabel = Pill("Hidden")
    hiddenPill:SetClass("collapsed", true)
    local customPill = gui.Panel{
        classes = {"heroSheetCustomPill", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 9,
        width = "auto",
        height = 18,
        hpad = 7,
        borderBox = true,
        lmargin = 5,
        valign = "center",
        interactable = false,
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "CUSTOM",
            fontSize = 11,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
        },
    }
    local tags = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "top",
        tmargin = 2,
        hiddenPill,
        customPill,
    }
    --- @type {pill: Panel, label: Panel}[]
    local tagPills = {}
    local sub = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        fontSize = 13,
        italics = true,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 1,
        interactable = false,
    }
    local text = gui.Label{
        classes = {"heroSheetCardText"},
        fontSize = 14,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 6,
        interactable = false,
    }

    --a growing resource table's rows (Growing Ferocity), under the text.
    local growHolder = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 6,
    }
    --- @type fun(item: HeroFeatureItem)
    local PaintGrowing

    --- @param item HeroFeatureItem
    --- @return boolean long the text is cut short, or growing rows wait behind Show more
    local function IsLong(item)
        if #item.text > FOLD_CHARS then
            return true
        end
        for _, row in ipairs(item.growing or {}) do
            if row.locked then
                return true
            end
        end
        return false
    end
    --- @param item HeroFeatureItem
    local function ShowText(item)
        if #item.text > FOLD_CHARS and not expanded[item.key] then
            local cut = string.sub(item.text, 1, FOLD_CHARS)
            cut = string.match(cut, "^(.*)%s") or cut
            text.text = cut .. "..."
        else
            text.text = item.text
        end
        text:SetClass("collapsed", item.text == "")
    end

    local more
    more = gui.Label(LinkArgs("Show more", "heroSheetFeatLink", {
        click = function(element)
            local item = card.item
            if item == nil then
                return
            end
            expanded[item.key] = not expanded[item.key] or nil
            ShowText(item)
            PaintGrowing(item)
            more.text = cond(expanded[item.key], "Show less", "Show more")
        end,
    }))
    local view = gui.Label(HeroSheetTheme.HoverCard(LinkArgs("View ability", "heroSheetFeatLinkLight", {data = {}}), function(pinned, close, element)
        local item = card.item
        local cards = {}
        for _, ability in ipairs((item ~= nil and item.abilities) or {}) do
            cards[#cards+1] = HeroSheetLists.AbilityCard(ability)
        end
        local stack = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            children = cards,
        }
        return HeroSheetTheme.CardFrame(stack, pinned, close, item ~= nil and #item.abilities > 0 and item.abilities[1].ability ~= nil)
    end))
    local links = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        tmargin = 4,
        more,
        view,
    }

    --the choice (a plate and its options) and a grant's controls: made again
    --each paint, since few cards have them.
    local choiceRow = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        tmargin = 8,
    }
    local grantHolder = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 8,
    }
    --the card's "...": at its top right, shown while the card
    --is hovered and always in Edit mode, as an ability row's.
    local keb = gui.Panel{
        classes = {"heroSheetKeb", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 5,
        floating = true,
        width = HeroSheetWindow.TargetSize(24),
        height = HeroSheetWindow.TargetSize(24),
        halign = "right",
        valign = "top",
        click = function(element)
            local item = card.item
            if item ~= nil then
                FeatureMenu(element, item, from)
            end
        end,
        gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = "phosphor/dots-three-bold.png",
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }

    local panel = gui.Panel{
        classes = {"heroSheetFeatCard"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 14,
        vpad = 10,
        borderBox = true,
        tmargin = 7,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            name,
            corePill,
            tags,
        },
        sub,
        text,
        growHolder,
        links,
        choiceRow,
        grantHolder,
        keb,
    }

    --The choice in the card: an unmade one always (its plate and options), a
    --made one in Edit mode (its options, the pick shown).
    --- @param item HeroFeatureItem
    local function PaintChoice(item)
        --a title's benefit is chosen in the Titles window: the plate opens it there.
        if item.titleChoose ~= nil and HeroSheetWrite.CanWrite() then
            local titleid = item.titleChoose
            choiceRow.children = {
                gui.Panel{
                    classes = {"heroSheetChoicePlate", "hoverable"},
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 12,
                    width = "auto",
                    height = 24,
                    hpad = 9,
                    borderBox = true,
                    halign = "left",
                    valign = "center",
                    click = function()
                        local windows = rawget(_G, "HeroSheetWindows")
                        if windows ~= nil and windows.OpenTitles ~= nil then
                            windows.OpenTitles(titleid)
                        end
                    end,
                    gui.Label{
                        classes = {"heroSheetCardInfo"},
                        text = "Choose a benefit",
                        fontSize = 12,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        textWrap = false,
                        interactable = false,
                    },
                },
            }
            choiceRow:SetClass("collapsed", false)
            return
        end
        local choice = item.choice
        local editing = HeroSheet.Editing()
        local unmade = choice ~= nil and choice.unspent > 0
        if choice == nil or not (unmade or editing) or not HeroSheetWrite.CanWrite() then
            choiceRow:SetClass("collapsed", true)
            if #choiceRow.children > 0 then
                choiceRow.children = {}
            end
            return
        end
        local children = {}
        if unmade then
            local plate = cond(choice.perk, "Choose a perk", cond(choice.unspent == 1, "Choose one", string.format("%d to choose", choice.unspent)))
            children[#children+1] = gui.Panel{
                classes = {"heroSheetChoicePlate"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 12,
                width = "auto",
                height = 24,
                hpad = 9,
                borderBox = true,
                rmargin = 8,
                halign = "left",
                valign = "center",
                gui.Label{
                    classes = {"heroSheetCardInfo"},
                    text = plate,
                    fontSize = 12,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    textWrap = false,
                },
            }
        end
        local dropdown = ChoiceDropdown(choice)
        if dropdown ~= nil then
            children[#children+1] = dropdown
        end
        choiceRow.children = children
        choiceRow:SetClass("collapsed", #children == 0)
    end

    --A grant's controls (drawn by the modifier), only for a Hero that can be written.
    --Through the editor bridge: Claim's changes are saved as one undo step.
    --- @param item HeroFeatureItem
    local function PaintGrants(item)
        if #item.grants == 0 or not HeroSheetWrite.CanWrite() then
            grantHolder:SetClass("collapsed", true)
            if #grantHolder.children > 0 then
                grantHolder.children = {}
            end
            return
        end
        local children = {}
        --a treasure still to claim says so, as an unmade choice does.
        if (item.claim or 0) > 0 then
            children[#children+1] = gui.Panel{
                classes = {"heroSheetChoicePlate"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 12,
                width = "auto",
                height = 24,
                hpad = 9,
                borderBox = true,
                bmargin = 6,
                halign = "left",
                gui.Label{
                    classes = {"heroSheetCardInfo"},
                    text = "Treasure to claim",
                    fontSize = 12,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    textWrap = false,
                },
            }
        end
        for _, modifier in ipairs(item.grants) do
            HeroSheetWrite.Bridge{
                description = "Claim treasure",
                fields = {"treasureGrants", "inventory"},
                open = function(props, done)
                    local ok, panel = pcall(function()
                        return modifier:CreateSheetPanel(props, {
                            refresh = function()
                                done()
                                HeroSheet.Saved()
                            end,
                            --the sheet's own controls, as its choice and Equip
                            style = {
                                label = {classes = {"heroSheetCardSub"}, fontSize = 13},
                                dropdown = {classes = {"heroSheetField"}, height = HeroSheetWindow.TargetSize(28), vmargin = 4},
                                button = function(text, click)
                                    return gui.Label{
                                        classes = {"heroSheetSmallButton", "hoverable"},
                                        text = text,
                                        bgimage = "panels/square.png",
                                        border = 1,
                                        cornerRadius = 6,
                                        width = "auto",
                                        height = 26,
                                        hpad = 9,
                                        borderBox = true,
                                        fontSize = 12.5,
                                        textWrap = false,
                                        halign = "left",
                                        textAlignment = "center",
                                        tmargin = 4,
                                        click = function(element)
                                            click()
                                        end,
                                    }
                                end,
                            },
                        })
                    end)
                    if ok and panel ~= nil then
                        children[#children+1] = panel
                    end
                end,
            }
        end
        grantHolder.children = children
        grantHolder:SetClass("collapsed", #children == 0)
    end

    --A growing resource table's rows: the resource each needs and its
    --words, the whole rule on hover. In combat the rows the Hero has now are
    --lit, and one passed this turn but no longer held has a dashed border
    --(its benefit lasts the turn, as the old sheet's "expiring").
    --Rows above the Hero's Level wait behind Show more, muted, with their Level.
    --- @param item HeroFeatureItem
    PaintGrowing = function(item)
        local rows = item.growing
        if rows == nil or #rows == 0 then
            growHolder:SetClass("collapsed", true)
            if #growHolder.children > 0 then
                growHolder.children = {}
            end
            return
        end
        local current, high, fighting = 0, 0, false
        pcall(function()
            local hero = HeroSheet.Token().properties
            current = hero:GetProgressionResource() or 0
            high = hero:GetProgressionResourceHighWaterMark() or 0
            local queue = dmhub.initiativeQueue
            fighting = queue ~= nil and not queue.hidden
        end)
        --an expiring row: a dashed border in the theme's own colour, like the
        --sheet's other dashed outlines; its words look like a plain row's.
        local cardBorder = HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(HeroSheetTheme.Palette().rawFg, 1), 0.5)
        local children = {}
        for _, row in ipairs(rows) do
            if not row.locked or expanded[item.key] then
                local lit = fighting and not row.locked and row.resources <= current
                --passed this turn and still held for it: the lit plate, faded
                --(grey is for rows above the Level, which it would read as).
                local expiring = fighting and not row.locked and not lit and row.resources <= high
                local muted = row.locked
                local plate = lit or expiring
                local args = {
                    classes = {cond(lit, "heroSheetChoicePlate", nil)},
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    hpad = 8,
                    vpad = 3,
                    borderBox = true,
                    tmargin = 2,
                    linger = function(element)
                        if type(row.tooltip) == "string" and row.tooltip ~= "" then
                            gui.Tooltip(row.tooltip)(element)
                        end
                    end,
                    gui.Label{
                        classes = {cond(lit, "heroSheetCardInfo", cond(muted, "heroSheetCardSub", "heroSheetCardStrong"))},
                        text = tostring(row.resources),
                        fontSize = 14,
                        bold = true,
                        width = 26,
                        height = "auto",
                        halign = "left",
                        valign = "top",
                        textWrap = false,
                        interactable = false,
                    },
                    gui.Label{
                        classes = {cond(lit, "heroSheetCardInfo", cond(muted, "heroSheetCardSub", "heroSheetCardText"))},
                        text = row.text,
                        fontSize = 13.5,
                        width = cond(row.locked, "100%-96", "100%-30"),
                        height = "auto",
                        halign = "left",
                        textWrap = true,
                        interactable = false,
                    },
                }
                if plate then
                    args.bgimage = "panels/square.png"
                    args.border = 1
                    args.cornerRadius = 6
                end
                if expiring then
                    args.bgcolor = "clear"
                    args.borderColor = cardBorder
                    args.borderStyle = "dashed"
                end
                if row.locked then
                    args[#args+1] = gui.Label{
                        classes = {"heroSheetCardSub"},
                        text = string.format("Level %d", row.level),
                        fontSize = 12,
                        floating = true,
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        valign = "top",
                        textWrap = false,
                        interactable = false,
                    }
                end
                children[#children+1] = gui.Panel(args)
            end
        end
        growHolder.children = children
        growHolder:SetClass("collapsed", #children == 0)
    end

    --- @param item HeroFeatureItem
    local function Paint(item)
        local previous = card.item
        card.item = item
        if previous ~= nil and previous.key ~= item.key then
            view.tooltip = nil
            if view.popup ~= nil then
                view.popup = nil
            end
        end
        panel:SetClass("heroSheetFeatCore", item.core)
        panel:SetClass("heroSheetFeatCustom", item.custom)
        panel:SetClass("heroSheetFeatHidden", item.hiddenKind ~= nil)
        name.text = item.name
        corePill:SetClass("collapsed", not item.core)
        hiddenPill:SetClass("collapsed", item.hiddenKind == nil)
        hiddenLabel.text = item.hiddenKind or ""
        for i, tag in ipairs(item.pillars) do
            local tagPill = tagPills[i]
            if tagPill == nil then
                local pill, label = Pill(tag)
                tagPill = {pill = pill, label = label}
                tagPills[i] = tagPill
                tags:AddChild(pill)
                customPill:SetAsLastSibling()
            end
            tagPill.label.text = tag
            tagPill.pill:SetClass("collapsed", false)
        end
        for i = #item.pillars + 1, #tagPills do
            tagPills[i].pill:SetClass("collapsed", true)
        end
        customPill:SetClass("collapsed", not item.custom)
        --the "..." sits at the top right: the tags keep clear of it.
        local menu = HasMenu(item)
        local kebRoom = cond(menu, HeroSheetWindow.TargetSize(24) + 6, 0)
        keb:SetClass("heroSheetKebOff", not menu)
        keb:SetClass("heroSheetEditOn", HeroSheet.Editing())
        tags.selfStyle.rmargin = kebRoom
        --the name takes what the tags leave, wrapping when it is long.
        local tagRoom = cond(item.core, CORE_PILL_ROOM, 0) + cond(item.custom, SMALL_PILL_ROOM, 0)
            + cond(item.hiddenKind ~= nil, SMALL_PILL_ROOM, 0) + NAME_GAP + kebRoom
        for _, tag in ipairs(item.pillars) do
            tagRoom = tagRoom + HeroSheetTheme.TextWidth(tag, 11.5) + TAG_PILL_PADDING
        end
        name.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(tagRoom))
        sub.text = item.sub or ""
        sub:SetClass("collapsed", item.sub == nil)
        ShowText(item)
        local long = IsLong(item)
        more:SetClass("collapsed", not long)
        more.text = cond(expanded[item.key], "Show less", "Show more")
        view:SetClass("collapsed", #item.abilities == 0)
        links:SetClass("collapsed", not long and #item.abilities == 0)
        PaintGrowing(item)
        PaintChoice(item)
        PaintGrants(item)
    end

    card = {panel = panel, paint = Paint, item = nil}
    return card
end

----------------------------------------------------------------------
--Groups.

--- @class HeroFeatureGroup
--- @field panel Panel
--- @field paint fun(section: HeroFeatureSection)
--- @field filter fun(matches: (fun(item: HeroFeatureItem): boolean), filtered: boolean, first: boolean): integer
--- @field repaint fun() paint the cards again (Edit mode came or went)

--A foldable group: its origin and count over its cards, and how many
--picks wait in it ("2 to choose"). Folds are remembered with the Abilities
--list's ("f:<group>"). Cards are made as needed and kept; a folded group
--makes none until opened.
--- @param id string
--- @param expanded table<string, boolean>
--- @param from Panel where the shared editors open from
--- @param grew fun() the list got taller (an opened group): it may need to scroll
--- @return HeroFeatureGroup
local function NewGroup(id, expanded, from, grew)
    local key = "f:" .. id
    local folded = HeroSheetLists.IsFolded(key)
    --- @type HeroFeatureCard[]
    local cards = {}
    --- @type HeroFeatureItem[]
    local items = {}
    --- @type table<HeroFeatureItem, boolean>
    local hiddenByFilter = {}

    local body = gui.Panel{
        classes = {cond(folded, "collapsed", nil)},
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    local caret = gui.Panel{
        classes = {"heroSheetMutedIcon"},
        bgimage = "phosphor/caret-down-fill.png",
        width = 10,
        height = 10,
        rmargin = 8,
        halign = "left",
        valign = "center",
        rotate = cond(folded, 90, 0),
        interactable = false,
    }
    local label = gui.Label{
        classes = {"heroSheetCardLabel"},
        fontSize = 12,
        bold = true,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    local count = gui.Label{
        classes = {"heroSheetCardSub"},
        fontSize = 13,
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    local need = gui.Label{
        classes = {"heroSheetCardInfo", "collapsed"},
        fontSize = 11.5,
        bold = true,
        width = "auto",
        height = "auto",
        lmargin = 10,
        halign = "left",
        valign = "center",
        textWrap = false,
        interactable = false,
    }

    --Paints the cards from the items; a folded group waits until opened.
    local function Fill()
        if folded then
            return
        end
        for i, item in ipairs(items) do
            local card = cards[i]
            if card == nil then
                card = NewCard(expanded, from)
                cards[i] = card
                body:AddChild(card.panel)
            end
            card.paint(item)
            card.panel:SetClass("collapsed", hiddenByFilter[item] == true)
        end
        for i = #items + 1, #cards do
            cards[i].panel:SetClass("collapsed", true)
            cards[i].item = nil
        end
    end

    local header = gui.Panel{
        classes = {"hoverable"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%",
        height = HeroSheetWindow.TargetSize(24),
        flow = "horizontal",
        click = function(element)
            folded = not folded
            HeroSheetLists.SetFolded(key, folded)
            body:SetClass("collapsed", folded)
            caret.selfStyle.rotate = cond(folded, 90, 0)
            if not folded then
                Fill()
                grew()
            end
        end,
        caret,
        label,
        count,
        need,
    }
    local panel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 14,
        header,
        body,
    }

    return {
        panel = panel,
        paint = function(section)
            items = section.items
            label.text = string.upper(section.header)
            local owed = {}
            if section.need > 0 then
                owed[#owed+1] = string.format("%d to choose", section.need)
            end
            if section.claim > 0 then
                owed[#owed+1] = string.format("%d to claim", section.claim)
            end
            need.text = table.concat(owed, DOT)
            need:SetClass("collapsed", #owed == 0)
        end,
        filter = function(matches, filtered, first)
            hiddenByFilter = {}
            local shown, total = 0, 0
            for _, item in ipairs(items) do
                local listed = item.hiddenKind == nil or (HeroSheet.Editing() and ShowHidden())
                if listed then
                    total = total + 1
                end
                if listed and matches(item) then
                    shown = shown + 1
                else
                    hiddenByFilter[item] = true
                end
            end
            panel:SetClass("collapsed", shown == 0)
            panel.selfStyle.tmargin = cond(first, 10, 14)
            count.text = cond(filtered, string.format("%d of %d", shown, total), tostring(total))
            Fill()
            return shown
        end,
        repaint = function()
            Fill()
        end,
    }
end

----------------------------------------------------------------------
--The list.

--A button in the Features Edit bar: its words, an icon before them if
--it has one. A dimmed one does nothing and says why on hover.
--- @param icon nil|string
--- @param text string
--- @param click fun(element: Panel)
--- @param tooltip nil|fun(): nil|string what the button would do now, or why it cannot
--- @return Panel
local function BarButton(icon, text, click, tooltip)
    local children = {}
    if icon ~= nil then
        children[#children+1] = gui.Panel{
            classes = {"heroSheetButtonIcon"},
            bgimage = icon,
            width = 12,
            height = 12,
            rmargin = 6,
            valign = "center",
            interactable = false,
        }
    end
    children[#children+1] = gui.Label{
        classes = {"heroSheetButtonLabel"},
        text = text,
        width = "auto",
        height = "auto",
        fontSize = 12.5,
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    return gui.Panel{
        classes = {"heroSheetButton", "heroSheetSolid", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = HeroSheetWindow.TargetSize(26),
        hpad = 9,
        borderBox = true,
        rmargin = 6,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        linger = function(element)
            local words = tooltip ~= nil and tooltip() or nil
            if words ~= nil then
                gui.Tooltip(words)(element)
            end
        end,
        click = function(element)
            click(element)
        end,
        children = children,
    }
end
--the Abilities' and Notes' Edit bars use the same buttons.
HeroSheetFeatures.BarButton = BarButton

--- @class HeroFeaturesPane
--- @field filters Panel the pillar chips and the search, placed by the lists' frame
--- @field bar Panel Edit mode's buttons (New feature, Paste feature, Show hidden features)
--- @field body Panel the list, scrolling once it is taller than its room
--- @field route fun(text: nil|string) open filtered by this text (the search's way in)
--- @field fit fun() the room changed: scroll if the list no longer fits
--- @field setEditing fun(editing: boolean)

--- The Features list for the lists' frame (HeroSheetLists.Create places its
--- filters, Edit bar and body). The list is a HeroSheetRefresh block: it
--- paints when what it shows changes.
--- @return HeroFeaturesPane
function HeroSheetFeatures.Create()
    local filter = {chip = "all", query = ""}
    --- @type table<string, boolean>
    local expanded = {}
    --- @type fun()
    local ApplyFilter
    --- @type fun()
    local FitScroll
    --- @type Panel
    local list

    --the chips: All and the pillars, one picked at a time.
    --- @type table<string, Panel>
    local chips = {}
    local filterChildren = {}
    for _, id in ipairs({"all", PILLARS[1], PILLARS[2], PILLARS[3], PILLARS[4]}) do
        local chip = gui.Panel{
            classes = {"heroSklChip", "hoverable", cond(id == "all", "heroSklPicked", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 14,
            width = "auto",
            height = HeroSheetWindow.TargetSize(28),
            hpad = 10,
            borderBox = true,
            rmargin = 6,
            valign = "center",
            click = function(element)
                filter.chip = id
                for otherId, otherChip in pairs(chips) do
                    otherChip:SetClassTree("heroSklPicked", otherId == id)
                end
                ApplyFilter()
            end,
            gui.Label{
                classes = {"heroSklChipText", cond(id == "all", "heroSklPicked", nil)},
                text = cond(id == "all", "All", id),
                fontSize = 12.5,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        chips[id] = chip
        filterChildren[#filterChildren+1] = chip
    end
    local search = gui.SearchInput{
        placeholderText = "Filter features",
        text = "",
        width = 150,
        height = HeroSheetWindow.TargetSize(28),
        borderBox = true,
        valign = "center",
        hover = gui.Tooltip("Type to filter. ! or - leaves a word out, > matches the start, < the end."),
        edit = function(element)
            filter.query = element.text or ""
            ApplyFilter()
        end,
    }
    filterChildren[#filterChildren+1] = search
    local filters = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        children = filterChildren,
    }

    --Edit mode's bar: New feature, Paste feature and the eye (Show hidden
    --features). Paste is dimmed while nothing it can paste is copied; the
    --clipboard can change anywhere in the app, so it is checked while the bar shows.
    local pasteButton = BarButton("phosphor/copy.png", "Paste feature", function(element)
        PasteFeature()
    end, function()
        local copied = ClipboardFeature()
        if copied == nil then
            return "Nothing to paste. Copy a feature or an ability first."
        end
        local token = HeroSheet.Token()
        return string.format("Adds a copy of %s to %s.", copied.name or "it", token ~= nil and token.name or "this Hero")
    end)
    local function SyncPaste()
        --opacity is not inherited: the icon and words dim with the frame.
        pasteButton:SetClassTree("heroSheetDisabled", ClipboardFeature() == nil)
    end
    local eye
    eye = gui.Panel{
        classes = {"heroSheetIconButton", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = HeroSheetWindow.TargetSize(26),
        height = HeroSheetWindow.TargetSize(26),
        halign = "left",
        valign = "center",
        linger = function(element)
            gui.Tooltip("Show hidden features")(element)
        end,
        click = function(element)
            dmhub.SetSettingValue(SHOW_HIDDEN_SETTING, not ShowHidden())
            eye:SetClassTree("selected", ShowHidden())
            eye.children[1].bgimage = cond(ShowHidden(), "phosphor/eye-light.png", "phosphor/eye-closed-light.png")
            ApplyFilter()
        end,
        gui.Panel{
            classes = {"heroSheetIconButtonIcon"},
            bgimage = cond(ShowHidden(), "phosphor/eye-light.png", "phosphor/eye-closed-light.png"),
            width = 15,
            height = 15,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    local bar = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 8,
        thinkTime = 0.5,
        think = function(element)
            SyncPaste()
        end,
        BarButton("phosphor/plus-bold.png", "New feature", function(element)
            OpenFeatureEditor(element, nil, "New feature")
        end),
        pasteButton,
        eye,
    }

    --- @type HeroFeatureCard[]
    local coreCards = {}
    local coreHolder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    --- @type HeroFeatureItem[]
    local coreItems = {}
    --- @type table<string, HeroFeatureGroup>
    local groups = {}
    local groupPanels = {coreHolder}
    for _, sectionDef in ipairs(SECTIONS) do
        local group = NewGroup(sectionDef.id, expanded, bar, function() FitScroll() end)
        groups[sectionDef.id] = group
        groupPanels[#groupPanels+1] = group.panel
    end
    local nothing = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "No features match. Clear the filters to see them all.",
        fontSize = 14,
        width = "100%",
        height = "auto",
        textAlignment = "center",
        textWrap = true,
        tmargin = 24,
    }
    groupPanels[#groupPanels+1] = nothing
    --a Growing Ferocity card lights its rows in combat: combat starting or
    --ending and a new turn change the initiative, not the Hero, so check
    --the blocks again then (as Downtime's watchers do).
    groupPanels[#groupPanels+1] = gui.Panel{
        width = 0,
        height = 0,
        floating = true,
        interactable = false,
        create = function(element)
            dmhub.Schedule(0.2, function()
                if not mod.unloaded and element.valid then
                    element.monitorGame = "/initiativeQueue"
                end
            end)
        end,
        refreshGame = function(element)
            HeroSheetRefresh.Recheck()
        end,
    }

    --- @param item HeroFeatureItem
    --- @return boolean
    local function Matches(item)
        if filter.chip ~= "all" then
            local has = false
            for _, pillar in ipairs(item.pillars) do
                if pillar == filter.chip then
                    has = true
                end
            end
            if not has then
                return false
            end
        end
        local query = filter.query
        if query == nil or query == "" then
            return true
        end
        local ok, result = pcall(function() return Search.MatchesText(item.search, Search.Normalize(query)) end)
        if ok then
            return result == true
        end
        return string.find(item.search, string.lower(query), 1, true) ~= nil
    end

    ApplyFilter = function()
        local filtered = filter.chip ~= "all" or (filter.query or "") ~= ""
        local shown = 0
        for i, item in ipairs(coreItems) do
            local card = coreCards[i]
            if card ~= nil then
                local on = Matches(item)
                card.panel:SetClass("collapsed", not on)
                if on then
                    shown = shown + 1
                end
            end
        end
        local first = shown == 0
        for _, sectionDef in ipairs(SECTIONS) do
            local shownInGroup = groups[sectionDef.id].filter(Matches, filtered, first)
            if shownInGroup > 0 then
                first = false
            end
            shown = shown + shownInGroup
        end
        nothing:SetClass("collapsed", not (filtered and shown == 0))
        FitScroll()
    end

    list = HeroSheetRefresh.Block({
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bmargin = 14,
        --another Hero starts with every text cut short again.
        heroSheetHero = function(element)
            for key in pairs(expanded) do
                expanded[key] = nil
            end
        end,
        children = groupPanels,
    }, {
        name = "features",
        signature = Signature,
        refresh = function(panel, token)
            local model = Read(token)
            coreItems = model.core
            for i, item in ipairs(coreItems) do
                local card = coreCards[i]
                if card == nil then
                    card = NewCard(expanded, bar)
                    coreCards[i] = card
                    coreHolder:AddChild(card.panel)
                end
                card.paint(item)
            end
            for i = #coreItems + 1, #coreCards do
                coreCards[i].panel:SetClass("collapsed", true)
                coreCards[i].item = nil
            end
            for _, sectionDef in ipairs(SECTIONS) do
                groups[sectionDef.id].paint(model.sections[sectionDef.id])
            end
            ApplyFilter()
        end,
    })

    --scrolls once its content is taller: panels made inside a scrolling
    --panel lay out far more slowly, so the cards are made first.
    --its height is set by the lists' frame (what the filters leave).
    local body = gui.Panel{
        width = "100%",
        height = "100%-6",
        flow = "vertical",
        tmargin = 6,
        list,
    }
    FitScroll = function()
        HeroSheetWindow.AfterLayout(function()
            if body.valid and not body.vscroll and list.renderedHeight > body.renderedHeight + 0.5 then
                body.vscroll = true
                --the engine then skips cards well outside the view, so the tab shows and
                --scrolls faster. Set only once the scroll view exists: before that the engine errors.
                body.hideObjectsOutOfScroll = true
            end
        end)
    end

    return {
        filters = filters,
        bar = bar,
        body = body,
        route = function(text)
            filter.chip = "all"
            for chipId, chip in pairs(chips) do
                chip:SetClassTree("heroSklPicked", chipId == "all")
            end
            --through the field's edit handler, which also shows its clear X.
            search.text = text or ""
            search:FireEvent("edit")
        end,
        fit = function()
            FitScroll()
        end,
        setEditing = function(editing)
            if editing then
                SyncPaste()
                eye:SetClassTree("selected", ShowHidden())
            end
            for i, item in ipairs(coreItems) do
                if coreCards[i] ~= nil then
                    coreCards[i].paint(item)
                end
            end
            for _, sectionDef in ipairs(SECTIONS) do
                groups[sectionDef.id].repaint()
            end
            ApplyFilter()
        end,
    }
end
