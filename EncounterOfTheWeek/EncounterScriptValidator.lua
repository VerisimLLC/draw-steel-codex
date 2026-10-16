--Encounter of the Week: the script validator, a dev-only panel.
--
--Reads a week's journal document through the SAME parser the runtime uses
--(EncounterScript.Parse) and lays the result out: every beat, round, entry
--and test, with each outcome line marked up to show which clauses the
--effect grammar recognized as rules and which fell through as flavour.
--Nothing here re-implements a rule. A clause lights up because
--EncounterScript.ParseEffects returned a mechanical effect for it -- the
--same call EncounterMontage.ApplyEffects makes when the tier lands -- and
--each rule's plain-English line is EncounterScript.DescribeEffect, the one
--the "/eotwscript" dump uses. So the panel cannot drift from the runtime.
--
--On top of the parser's own warnings it runs the checks a pure module
--cannot: every item, monster, object asset and zone keyword a script names
--is looked up in the live tables (the same FindGear / FindMonster /
--FindObjectAsset / FindKeyword the runtime uses), and every power roll's
--"Attr (Skills)" goes through EncounterScript.ParseAttr to catch the two
--silent authoring traps -- a characteristic that matched nothing, and a
--skill name that is not one of Skill.skillsDropdownOptions.

local mod = dmhub.GetModLoading()

EncounterScriptValidator = {}

EncounterScriptValidator.panelName = "Encounter Script"

local RULE_COLOR = "#7fd97f"
local PROBLEM_COLOR = "#e88a8a"
--amber, not red: an unmatched clause is usually deliberate flavour, and
--only sometimes a rule with a typo in it.
local UNMATCHED_COLOR = "#d8a25a"
local FLAVOUR_COLOR = "#9a9a9a"

local function lower(s)
    return string.lower(s or "")
end

local function trim(s)
    return (string.gsub(s or "", "^%s+", ""):gsub("%s+$", ""))
end

--- the documents to choose from ---------------------------------------------

--Every markdown journal document, so a week can be checked before its map
--is the one you are standing on. The current map's script (whatever
--EncounterMontage.FindMapScript would pick) is marked, and is what the
--panel opens on.
local function DocumentOptions()
    local found = {}
    local docs = dmhub.GetTable("documents") or {}
    local currentId = nil
    pcall(function() currentId = EncounterMontage.FindMapScript(true).docid end)
    for docid, doc in unhidden_pairs(docs) do
        if doc.typeName == "MarkdownDocument" then
            local name = doc.description
            if type(name) ~= "string" or trim(name) == "" then
                name = "(untitled)"
            end
            found[#found + 1] = {
                id = docid,
                text = cond(docid == currentId, name .. "  [this map]", name),
                sortKey = lower(name),
                current = docid == currentId,
            }
        end
    end
    --this map's script first, then by name.
    table.sort(found, function(a, b)
        if a.current ~= b.current then
            return a.current
        end
        if a.sortKey ~= b.sortKey then
            return a.sortKey < b.sortKey
        end
        return a.id < b.id
    end)
    --the dropdown gets id/text only; the sort keys are ours.
    local options = {}
    for _, f in ipairs(found) do
        options[#options + 1] = { id = f.id, text = f.text }
    end
    return options, currentId
end

--The map a document is filed under, or nil: its sub-document links resolve
--against that map's journal first, as they do at runtime.
local function DocumentMap(doc)
    for _, map in ipairs(game.maps or {}) do
        if CustomDocument.IsDocInAccessibleRoot(doc, { [map.id] = true }) then
            return map.id
        end
    end
    return nil
end

--The document as the runtime reads it: sub-documents spliced in, parsed.
local function LoadDocument(docid)
    local doc = (dmhub.GetTable("documents") or {})[docid]
    if doc == nil then
        return nil
    end
    local script = EncounterMontage.LoadScript(docid, DocumentMap(doc))
    return script ~= nil and script.parse or nil
end

--- the checks the pure parser cannot make -----------------------------------

--Every name a script hands to the engine, with whether the engine can find
--it. Returns a list of { ok, text }.
local function NameChecks(parse)
    local out = {}
    local function Check(ok, fmt, ...)
        out[#out + 1] = { ok = ok, text = string.format(fmt, ...) }
    end

    local items, monsters = {}, {}
    pcall(function() items, monsters = EncounterScript.ReferencedNames(parse) end)
    local names = {}
    for name in pairs(items or {}) do
        names[#names + 1] = { kind = "item", name = name }
    end
    for name in pairs(monsters or {}) do
        names[#names + 1] = { kind = "monster", name = name }
    end

    --zones and objects are named by the encounter beat's setup lines and by
    --any "reveal <zone>" clause; neither is in ReferencedNames, which only
    --walks the effects the montage grants.
    local zones = {}
    local function CollectZones(effects)
        for _, effect in ipairs(effects or {}) do
            if effect.kind == "revealzones" and effect.zone ~= nil then
                zones[effect.zone] = true
            end
        end
    end
    for _, beat in ipairs(parse.beats or {}) do
        for _, ins in ipairs(beat.setup or {}) do
            if ins.kind == "placeobjects" then
                names[#names + 1] = { kind = "object", name = ins.object }
                zones[ins.zone] = true
            end
        end
        for _, r in ipairs(beat.reinforcements or {}) do
            if r.zone ~= nil then
                zones[r.zone] = true
            end
        end
        for _, section in ipairs(EncounterScript.NarrativeSections(beat)) do
            for _, o in ipairs(section.options) do
                CollectZones(o.effects)
            end
        end
        for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
            if entry.consequence ~= nil then
                CollectZones(entry.consequence.effects)
            end
            for _, o in ipairs(entry.options) do
                for _, effects in ipairs(EncounterScript.OptionEffectLists(o)) do
                    CollectZones(effects)
                end
            end
        end
    end
    for zone in pairs(zones) do
        names[#names + 1] = { kind = "zone", name = zone }
    end

    table.sort(names, function(a, b)
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        return lower(a.name) < lower(b.name)
    end)

    for _, n in ipairs(names) do
        local id = nil
        if n.kind == "item" then
            pcall(function() id = EncounterMontage.FindGear(n.name) end)
        elseif n.kind == "monster" then
            pcall(function() id = EncounterMontage.FindMonster(n.name) end)
        elseif n.kind == "object" then
            pcall(function() id = EncounterZones.FindObjectAsset(n.name) end)
        elseif n.kind == "zone" then
            pcall(function() id = EncounterZones.FindKeyword(n.name) end)
        end
        Check(id ~= nil, "%s '%s': %s", n.kind, n.name, cond(id ~= nil, "found", "NOT FOUND"))
    end
    return out
end

--A power roll's "Presence (Empathize, Lie, Flirt)" put through the SAME
--EncounterScript.ParseAttr the roll dialog uses. Returns a list of problem
--strings: no characteristic at all (the test has nothing to roll), and any
--name in the parentheses that matched no Skill.skillsDropdownOptions entry
--(it contributes nothing, silently -- the trap the design doc warns about).
local function AttrProblems(attr)
    local problems = {}
    local characteristics, skills = nil, nil
    local ok = pcall(function()
        characteristics, skills = EncounterScript.ParseAttr(attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    end)
    if not ok then
        return problems
    end
    if next(characteristics or {}) == nil then
        problems[#problems + 1] = string.format("'%s' names no characteristic; the test has nothing to roll", attr)
    end
    local inside = string.match(attr or "", "%((.*)%)")
    for token in string.gmatch(inside or "", "[^,]+") do
        token = trim(token)
        if token ~= "" then
            local matched = false
            for _, skillInfo in ipairs(Skill.skillsDropdownOptions or {}) do
                local name = skillInfo.text
                if type(name) == "string" and name ~= "" and string.find(lower(token), lower(name), 1, true) ~= nil then
                    matched = true
                    break
                end
            end
            if not matched then
                problems[#problems + 1] = string.format("'%s' is not a skill name; it adds nothing to the roll", token)
            end
        end
    end
    return problems
end

--- the report ----------------------------------------------------------------

--One row of the report: { depth, text, class }. `class` picks the colour
--(see the styles below); the text may carry rich-text colour tags of its
--own, which is how a tier line highlights the clauses that are rules.
local function Report(parse)
    local rows = {}
    local counts = { beats = 0, entries = 0, options = 0, rules = 0, flavour = 0 }
    local problems = {}

    local function Row(depth, class, fmt, ...)
        rows[#rows + 1] = { depth = depth, class = class, text = string.format(fmt, ...) }
    end
    local function Problem(fmt, ...)
        problems[#problems + 1] = string.format(fmt, ...)
    end

    --A tier or Consequence: line -- what the players read, with every
    --recognized clause lit -- then one line per effect saying what the
    --engine will actually do with it.
    local function RulesFor(depth, label, text)
        local shown = EncounterScript.MarkupRules(text, "<color=" .. RULE_COLOR .. ">", "</color>")
        Row(depth, "tier", "%s%s", label, shown)
        for _, effect in ipairs(EncounterScript.ParseEffects(text)) do
            local described = EncounterScript.DescribeEffect(effect)
            if EncounterScript.EffectIsMechanical(effect) then
                counts.rules = counts.rules + 1
                Row(depth + 1, "rule", "%s%s", cond(effect.hidden, "(hidden) ", ""), described)
            else
                counts.flavour = counts.flavour + 1
                Row(depth + 1, cond(effect.unrecognized, "flavourUnknown", "flavour"), "%s", described)
            end
        end
    end

    local function Tags(entry)
        local tags = {}
        if entry.required then tags[#tags + 1] = "Required" end
        if entry.locked then tags[#tags + 1] = "Locked" end
        if entry.temporary then tags[#tags + 1] = "Temporary" end
        if #tags == 0 then
            return ""
        end
        return string.format("  (%s)", table.concat(tags, ", "))
    end

    for bi, beat in ipairs(parse.beats or {}) do
        counts.beats = counts.beats + 1
        Row(0, "beat", "Beat %d: %s  [%s]%s", bi, beat.title or "", beat.kind,
            cond(beat.implicit, "  (implicit)", ""))
        if beat.sceneTag ~= nil then
            Row(1, "note", "scene: [[%s]]", beat.sceneTag)
        end
        if beat.intro ~= nil and trim(beat.intro) ~= "" then
            Row(1, "note", "intro: %s", beat.intro)
        end
        for _, u in ipairs(beat.unlocks or {}) do
            Row(1, "rule", "unlocks the %s feature when this beat opens", u.name)
        end

        for _, ins in ipairs(beat.setup or {}) do
            if ins.kind == "placeobjects" then
                Row(1, "rule", "setup %s: place %d x '%s' in %s zones%s", ins.label, ins.qty, ins.object, ins.zone,
                    cond(ins.deleteOthers, ", delete the other " .. ins.zone .. " zones", ""))
            elseif ins.kind == "bystanders" then
                Row(1, "rule", "setup %s: bystanders (no initiative): %s", ins.label, table.concat(ins.names or {}, ", "))
            elseif ins.kind == "victory" then
                Row(1, "rule", "%s: %s", ins.label, EncounterScript.DescribeVictory(ins) or "?")
            else
                Row(1, "flavourUnknown", "setup %s: UNRECOGNIZED '%s'", ins.label, ins.text)
                Problem("%s: setup instruction '%s' is not understood", EncounterScript.LineLabel(parse, ins.line), ins.text)
            end
        end

        for _, r in ipairs(beat.reinforcements or {}) do
            Row(1, "entry", "Reinforcements: %s", r.name)
            Row(2, "rule", "arrive: %s", r.schedule ~= nil and EncounterScript.DescribeSchedule(r.schedule) or "NEVER (no Arrive: line)")
            Row(2, "rule", "enter: %s", r.zone ~= nil and (r.zone .. " zone") or "the islands' saved positions")
            if #r.islands > 1 then
                Row(2, "note", "%d [[encounter]] islands take turns, one per arrival", #r.islands)
            else
                Row(2, "note", "%d [[encounter]] island", #r.islands)
            end
            for _, shout in ipairs(r.shouts or {}) do
                Row(2, "flavour", "shout: \"%s\"", shout)
            end
        end

        for _, section in ipairs(EncounterScript.NarrativeSections(beat)) do
            Row(1, "entry", "Section: %s  (%s)", section.name, section.mode)
            for _, u in ipairs(section.unlocks or {}) do
                Row(2, "rule", "unlocks the %s feature when this section arrives", u.name)
            end
            for _, o in ipairs(section.options) do
                counts.options = counts.options + 1
                Row(2, "option", "%s%s", o.name, cond(o.implicit, "  (implicit)", ""))
                if #o.effects > 0 then
                    RulesFor(3, "", o.text)
                end
            end
        end

        for _, round in ipairs(beat.rounds or {}) do
            Row(1, "round", "Round %d%s", round.number, cond(round.implicit, "  (implicit)", ""))
            for _, d in ipairs(round.scaling or {}) do
                Row(2, "rule", "scaling: %s", d.text)
            end
            for _, entry in ipairs(round.entries) do
                counts.entries = counts.entries + 1
                Row(2, "entry", "%s: %s%s", cond(entry.kind == "threat", "Threat", "Opportunity"),
                    entry.name, Tags(entry))
                if entry.consequence ~= nil then
                    RulesFor(3, "Consequence: ", entry.consequence.text)
                end
                --one version of an option: its roll or its free rules, and
                --its riders.
                local function VersionRows(o, v, depth)
                    for _, rider in ipairs(v.riders or {}) do
                        Row(depth, cond(rider.requirement.unrecognized, "flavourUnknown", "rule"),
                            "%s: %s", cond(rider.effect == "allow", "Secret (only for)", EncounterScript.RiderLabel(rider.effect, rider.round)), rider.text)
                    end
                    if v.roll ~= nil then
                        Row(depth, "roll", "%s: %s", v.roll.name, v.roll.attr)
                        for _, problem in ipairs(AttrProblems(v.roll.attr)) do
                            Row(depth + 1, "flavourUnknown", "%s", problem)
                            Problem("%s: option '%s' -- %s", EncounterScript.LineLabel(parse, o.line), o.name, problem)
                        end
                        for t in ipairs(v.roll.tiers) do
                            local label = string.format("tier %d: ", t)
                            if t == 4 then
                                label = cond(v.roll.critAuto, "critical (automatic): ", "critical: ")
                            end
                            if v.roll.teasers[t] ~= nil then
                                Row(depth + 1, "note", "%steaser '%s'", label, v.roll.teasers[t])
                            end
                            RulesFor(depth + 1, label, v.roll.tiers[t])
                        end
                        for _, rider in ipairs(v.roll.riders or {}) do
                            Row(depth + 1, cond(rider.requirement.unrecognized, "flavourUnknown", "rule"),
                                "%s: %s", cond(rider.effect == "allow", "Secret (only for)", EncounterScript.RiderLabel(rider.effect, rider.round)), rider.text)
                        end
                    elseif v.free ~= nil then
                        RulesFor(depth, "no roll: ", v.free.text)
                    elseif o.delve ~= nil and v == o then
                        Row(depth, "note", "enters the delve '%s'", o.delve)
                    else
                        Row(depth, "flavourUnknown", "no power roll and no rules")
                    end
                end
                for _, o in ipairs(entry.options) do
                    counts.options = counts.options + 1
                    Row(3, "option", "%s%s", o.name, cond(EncounterScript.OptionIsSecret(o), "  (SECRET)", ""))
                    VersionRows(o, o, 4)
                    for _, k in ipairs(o.knacks or {}) do
                        Row(4, cond(k.requirement.unrecognized, "flavourUnknown", "knack"), "Knack -- if %s:", k.requirementText)
                        VersionRows(o, k, 5)
                    end
                end
            end
        end
    end

    --Flavour prose in a tier line is normal and the parser warns about
    --every clause of it, so those warnings are kept apart: 48 of the 50 a
    --real week raised were prose, and they buried the two that mattered.
    --They are still listed, because a typo'd rule looks exactly like them.
    local textOnly = {}
    for _, w in ipairs(parse.warnings or {}) do
        if string.find(w, "unrecognized effect", 1, true) ~= nil
            or string.find(w, "unrecognized consequence", 1, true) ~= nil then
            textOnly[#textOnly + 1] = w
        else
            Problem("%s", w)
        end
    end
    return rows, problems, counts, textOnly
end

--- knack coverage ------------------------------------------------------------
--
--The standard (KNACKS_REFERENCE.md): every test carries a knack or two (an
--edge rider, a knack version), every opportunity a secret option or knack,
--and every hero of a party meets several across the montage. A party is
--picked in the panel; in an authoring game that is the week's pregens,
--which make a good breadth test -- but nothing here knows them by name.

--Every hook an option offers, as { kind = "edge"|"secret"|"knack"|"bane",
--requirement, text }.
local function OptionHooks(o)
    local hooks = {}
    local function AddRiders(riders)
        for _, r in ipairs(riders or {}) do
            if r.effect == "allow" then
                hooks[#hooks + 1] = { kind = "secret", requirement = r.requirement, text = r.text, round = r.round }
            elseif r.effect == "bane" or r.effect == "doublebane" then
                hooks[#hooks + 1] = { kind = "bane", requirement = r.requirement, text = r.text, round = r.round }
            else
                hooks[#hooks + 1] = { kind = "edge", requirement = r.requirement, text = r.text, round = r.round }
            end
        end
    end
    AddRiders(o.riders)
    AddRiders((o.roll or {}).riders)
    for _, k in ipairs(o.knacks or {}) do
        if EncounterScript.KnackUsable(k) then
            hooks[#hooks + 1] = { kind = "knack", requirement = k.requirement, text = k.requirementText }
        end
    end
    return hooks
end

--Which party each character is in: charid -> partyid.
local function PartyOfCharacters()
    local result = {}
    for partyid, _ in pairs(dmhub.GetTable(Party.tableName) or {}) do
        for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
            result[charid] = partyid
        end
    end
    return result
end

--The heroes of one party (or every hero in the game for "all").
local function PartyHeroes(partyid)
    local heroes = {}
    local partyOf = PartyOfCharacters()
    for charid, tok in pairs(dmhub.GetAllCharacters() or {}) do
        local isHero = false
        pcall(function() isHero = tok.properties ~= nil and tok.properties:IsHero() end)
        local inParty = partyid == "all" or partyOf[charid] == partyid
        if isHero and inParty then
            local name = tok.name
            if type(name) ~= "string" or name == "" then
                name = "(unnamed)"
                pcall(function()
                    local props = tok.properties --[[@as character]]
                    local race = props:Race()
                    local classes = props:GetClassesAndSubClasses()
                    name = string.format("%s %s", race ~= nil and race.name or "?", classes[1] ~= nil and classes[1].class.name or "?")
                end)
            end
            heroes[#heroes + 1] = { charid = charid, name = name, token = tok }
        end
    end
    table.sort(heroes, function(a, b) return a.name < b.name end)
    return heroes
end

--The parties with heroes in them, for the coverage picker.
local function PartyOptions()
    local counts = {}
    local partyOf = PartyOfCharacters()
    for charid, tok in pairs(dmhub.GetAllCharacters() or {}) do
        local isHero = false
        pcall(function() isHero = tok.properties ~= nil and tok.properties:IsHero() end)
        local partyid = partyOf[charid]
        if isHero and partyid ~= nil then
            counts[partyid] = (counts[partyid] or 0) + 1
        end
    end
    local options = {}
    local parties = dmhub.GetTable(Party.tableName) or {}
    local best, bestCount = "all", 0
    for partyid, n in pairs(counts) do
        local name = parties[partyid] ~= nil and parties[partyid].name or partyid
        options[#options + 1] = { id = partyid, text = string.format("%s (%d heroes)", tostring(name), n) }
        if n > bestCount then
            best, bestCount = partyid, n
        end
    end
    table.sort(options, function(a, b) return a.text < b.text end)
    table.insert(options, 1, { id = "all", text = "All heroes in the game" })
    return options, best
end

--Coverage rows for a parse against a party: { depth, class, text }.
function EncounterScriptValidator.KnackCoverage(parse, partyid)
    local rows = {}
    local function Row(depth, class, fmt, ...)
        rows[#rows + 1] = { depth = depth, class = class, text = string.format(fmt, ...) }
    end
    local heroes = PartyHeroes(partyid or "all")
    local facts = {}
    for _, hero in ipairs(heroes) do
        local f = {}
        pcall(function() f = TestRiders.CreatureFacts(hero.token.properties) end)
        facts[hero.charid] = f
    end
    local function Met(requirement, f, round)
        local ok = false
        pcall(function()
            local copy = {}
            for k, v in pairs(f) do
                copy[k] = v
            end
            copy.round = round
            ok = EncounterScript.RequirementMet(requirement, copy) == true
        end)
        return ok
    end

    local testsTotal, testsBare = 0, {}
    local oppTotal, oppBare = 0, {}
    local threatTotal, threatWith = 0, 0
    local byRequirement = {}
    local hookTotal = 0
    local perHero = {}
    for _, hero in ipairs(heroes) do
        perHero[hero.charid] = { count = 0, where = {} }
    end

    local function Visit(label, entry, round)
        local entryHooks = 0
        local entrySecrets = 0
        for _, o in ipairs(entry.options or {}) do
            local hooks = OptionHooks(o)
            if o.roll ~= nil then
                testsTotal = testsTotal + 1
                local n = 0
                for _, h in ipairs(hooks) do
                    if h.kind ~= "bane" then
                        n = n + 1
                    end
                end
                if n == 0 then
                    testsBare[#testsBare + 1] = string.format("%s -- %s", label, o.name)
                end
            end
            for _, h in ipairs(hooks) do
                if h.kind ~= "bane" then
                    entryHooks = entryHooks + 1
                    hookTotal = hookTotal + 1
                    local key = string.lower(h.text or "")
                    byRequirement[key] = (byRequirement[key] or 0) + 1
                end
                if h.kind == "secret" or h.kind == "knack" then
                    entrySecrets = entrySecrets + 1
                end
                for _, hero in ipairs(heroes) do
                    if h.kind ~= "bane" and Met(h.requirement, facts[hero.charid], h.round or round) then
                        local ph = perHero[hero.charid]
                        ph.count = ph.count + 1
                        ph.where[label] = true
                    end
                end
            end
        end
        if entry.kind == "opportunity" then
            oppTotal = oppTotal + 1
            if entrySecrets == 0 then
                oppBare[#oppBare + 1] = label
            end
        elseif entry.kind == "threat" then
            threatTotal = threatTotal + 1
            if entrySecrets > 0 then
                threatWith = threatWith + 1
            end
        end
    end

    for _, beat in ipairs(parse.beats or {}) do
        for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
            Visit(entry.name, entry, entry.round)
        end
    end
    for _, delve in pairs(parse.delves or {}) do
        for _, ob in ipairs(delve.obstacles or {}) do
            Visit(string.format("%s: %s", delve.name, ob.name), ob, nil)
        end
    end

    Row(0, cond(#testsBare == 0, "ok", "problem"), "Tests with a knack: %d of %d (standard: every test)", testsTotal - #testsBare, testsTotal)
    for _, t in ipairs(testsBare) do
        Row(1, "flavourUnknown", "no knack: %s", t)
    end
    Row(0, cond(#oppBare == 0, "ok", "problem"), "Opportunities with a secret option or knack: %d of %d (standard: most)", oppTotal - #oppBare, oppTotal)
    for _, e in ipairs(oppBare) do
        Row(1, "flavourUnknown", "none: %s", e)
    end
    Row(0, "note", "Threats with a secret option or knack: %d of %d (standard: some)", threatWith, threatTotal)

    --one requirement carrying too much of the montage (5 Zaliac edges)
    local heavy = {}
    for req, n in pairs(byRequirement) do
        if hookTotal >= 8 and n / hookTotal > 0.15 then
            heavy[#heavy + 1] = string.format("'%s' x%d", req, n)
        end
    end
    table.sort(heavy)
    if #heavy > 0 then
        Row(0, "flavourUnknown", "Leaning on one knack (over 15%% of %d hooks): %s", hookTotal, table.concat(heavy, ", "))
    end

    Row(0, "note", "Heroes (%d) -- knacks each meets (standard: 3 or more)", #heroes)
    for _, hero in ipairs(heroes) do
        local ph = perHero[hero.charid]
        local where = {}
        for name in pairs(ph.where) do
            where[#where + 1] = name
        end
        table.sort(where)
        Row(1, cond(ph.count >= 3, "ok", "problem"), "%s: %d  %s", hero.name, ph.count, table.concat(where, ", "))
    end
    return rows
end

--- the panel -----------------------------------------------------------------

--Plain style tables, the way the stage declares its own, so they can go
--through ThemeEngine.MergeStyles with everything else.
local function Styles()
    return {
        { selectors = {"eotwValRow"}, fontSize = 14, color = "#d0d0d0", width = "100%",
            height = "auto", textAlignment = "left", halign = "left", bmargin = 1 },
        { selectors = {"eotwValRow", "beat"}, fontSize = 18, bold = true, color = "#ffffff", tmargin = 10 },
        { selectors = {"eotwValRow", "round"}, fontSize = 16, bold = true, color = "#cfcfe8", tmargin = 6 },
        { selectors = {"eotwValRow", "entry"}, fontSize = 15, bold = true, color = "#e8d9b0", tmargin = 4 },
        { selectors = {"eotwValRow", "option"}, fontSize = 14, bold = true, color = "#c8c8c8" },
        { selectors = {"eotwValRow", "roll"}, italics = true, color = "#a8c4e0" },
        { selectors = {"eotwValRow", "tier"}, color = "#c0c0c0" },
        { selectors = {"eotwValRow", "rule"}, color = RULE_COLOR },
        { selectors = {"eotwValRow", "knack"}, color = "#d9b3ff", bold = true },
        { selectors = {"eotwValRow", "flavour"}, color = FLAVOUR_COLOR, italics = true },
        { selectors = {"eotwValRow", "flavourUnknown"}, color = UNMATCHED_COLOR },
        { selectors = {"eotwValRow", "note"}, color = FLAVOUR_COLOR, italics = true },
        { selectors = {"eotwValRow", "problem"}, color = PROBLEM_COLOR },
        { selectors = {"eotwValRow", "ok"}, color = RULE_COLOR },
        { selectors = {"eotwValSummary"}, fontSize = 15, bold = true, color = "#ffffff",
            width = "100%", height = "auto", textAlignment = "left", vmargin = 6 },
    }
end

local function RowLabel(row)
    --the indent has to come OUT of the width: a "100%" label with a left
    --margin overflows the panel by exactly that margin and clips its own
    --right-hand words.
    local indent = 14 * (row.depth or 0)
    return gui.Label{
        classes = {"eotwValRow", row.class},
        lmargin = indent,
        width = string.format("100%%-%d", indent + 4),
        text = row.text,
        interactable = false,
    }
end

--Build the report body for one document id. Returns the list of children.
local g_coverageParty = nil

function EncounterScriptValidator.BuildReport(docid, partyid)
    local children = {}
    local parse = LoadDocument(docid)
    if parse == nil then
        children[#children + 1] = gui.Label{ classes = {"eotwValSummary"}, text = "No such document." }
        return children
    end

    local rows, problems, counts, textOnly = Report(parse)
    local checks = NameChecks(parse)
    for _, check in ipairs(checks) do
        if not check.ok then
            problems[#problems + 1] = check.text
        end
    end

    children[#children + 1] = gui.Label{
        classes = {"eotwValSummary"},
        text = string.format("%d beats, %d entries, %d options -- %d rules matched, %d text-only clauses -- %s",
            counts.beats, counts.entries, counts.options, counts.rules, counts.flavour,
            cond(#problems == 0, "no problems", string.format("%d PROBLEMS", #problems))),
    }
    --the sub-documents this one pulled in, so a link that silently stayed
    --prose (a typo'd name warns; a link to a monster does not) is visible.
    local included = {}
    for _, info in pairs(parse.included or {}) do
        included[#included + 1] = tostring(info.name or info.id)
    end
    if #included > 0 then
        table.sort(included)
        children[#children + 1] = RowLabel{ depth = 0, class = "note",
            text = string.format("includes %d sub-document%s: %s", #included, cond(#included == 1, "", "s"), table.concat(included, ", ")) }
    end

    if not parse.hasEncounterTag then
        children[#children + 1] = RowLabel{ depth = 0, class = "problem",
            text = "no [[encounter]] island: this document spawns no combat" }
    end

    if #problems > 0 then
        children[#children + 1] = gui.Label{ classes = {"eotwValSummary"}, text = "Problems" }
        for _, p in ipairs(problems) do
            children[#children + 1] = RowLabel{ depth = 1, class = "problem", text = p }
        end
    end

    --prose the grammar did not match: expected, but this is also where a
    --typo'd rule ends up, so it is worth a read.
    if #textOnly > 0 then
        children[#children + 1] = gui.Label{ classes = {"eotwValSummary"},
            text = string.format("Text-only clauses (%d) -- no rule matched; check for a typo'd rule among them", #textOnly) }
        for _, w in ipairs(textOnly) do
            children[#children + 1] = RowLabel{ depth = 1, class = "flavourUnknown", text = w }
        end
    end

    --knack coverage against the chosen party (KNACKS_REFERENCE.md).
    local partyOptions, bestParty = PartyOptions()
    if g_coverageParty == nil then
        g_coverageParty = partyid or bestParty
    end
    children[#children + 1] = gui.Label{ classes = {"eotwValSummary"}, text = "Knack coverage" }
    children[#children + 1] = gui.Dropdown{
        options = partyOptions,
        idChosen = g_coverageParty,
        width = 360,
        height = 26,
        halign = "left",
        change = function(element)
            ---@cast element Dropdown
            g_coverageParty = element.idChosen
            if EncounterScriptValidator.rebuild ~= nil then
                EncounterScriptValidator.rebuild()
            end
        end,
    }
    local okCoverage, coverage = pcall(EncounterScriptValidator.KnackCoverage, parse, g_coverageParty)
    if okCoverage then
        for _, row in ipairs(coverage) do
            children[#children + 1] = RowLabel(row)
        end
    else
        children[#children + 1] = RowLabel{ depth = 1, class = "problem", text = "coverage failed: " .. tostring(coverage) }
    end

    children[#children + 1] = gui.Label{ classes = {"eotwValSummary"}, text = "Script" }
    for _, row in ipairs(rows) do
        children[#children + 1] = RowLabel(row)
    end
    --the name lookups in full, passes included: "found" is as worth seeing
    --as "NOT FOUND" when an author is wondering why nothing was granted.
    if #checks > 0 then
        children[#children + 1] = gui.Label{ classes = {"eotwValSummary"}, text = "Names" }
        for _, check in ipairs(checks) do
            children[#children + 1] = RowLabel{ depth = 1, class = cond(check.ok, "ok", "problem"), text = check.text }
        end
    end
    return children
end

--- the panel -----------------------------------------------------------------

--The whole tool: a document picker, a re-check button, and the report. It
--re-reads the document every time, so the loop is edit the journal, hit
--Re-check, read the problems.
function EncounterScriptValidator.CreatePanel()
    local options, currentId = DocumentOptions()
    local chosen = currentId
    if chosen == nil and options[1] ~= nil then
        chosen = options[1].id
    end

    local body = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local function Rebuild()
        local ok, children = pcall(EncounterScriptValidator.BuildReport, chosen)
        EncounterScriptValidator.rebuild = Rebuild
        if not ok then
            children = { gui.Label{
                classes = {"eotwValSummary"},
                text = string.format("Validation failed: %s", tostring(children)),
            } }
        end
        body.children = children
    end

    local picker = gui.Dropdown{
        options = options,
        idChosen = chosen,
        width = "100%-90",
        height = 30,
        halign = "left",
        change = function(element)
            ---@cast element Dropdown
            chosen = element.idChosen
            Rebuild()
        end,
    }

    Rebuild()

    return gui.Panel{
        styles = ThemeEngine.MergeStyles(Styles()),
        width = "100%",
        height = "auto",
        flow = "vertical",

        gui.Panel{
            width = "100%",
            height = 34,
            flow = "horizontal",
            valign = "top",

            picker,
            gui.Button{
                text = "Re-check",
                width = 86,
                height = 30,
                halign = "right",
                click = function()
                    --the journal may have been edited since the last look,
                    --and the parse the runtime caches with it.
                    pcall(function() EncounterMontage.FindMapScript(true) end)
                    picker.options = DocumentOptions()
                    Rebuild()
                end,
            },
        },

        body,
    }
end

DockablePanel.Register{
    name = EncounterScriptValidator.panelName,
    icon = "phosphor/notebook.png",
    devonly = true,
    folder = "Development Tools",
    minHeight = 300,
    minWidth = 460,
    vscroll = true,
    content = function()
        return EncounterScriptValidator.CreatePanel()
    end,
}

--"/eotwvalidate": the same tool from chat, for when the Panels menu is a
--few clicks too many.
pcall(function()
    Commands.RegisterMacro{
        name = "eotwvalidate",
        summary = "open the Encounter of the Week script validator",
        doc = "Usage: /eotwvalidate\nOpens the Encounter Script panel: parses a week's journal document with the runtime parser and reports its beats, the clauses it recognized as rules, and every problem (parser warnings, unresolved item/monster/object/zone names, bad characteristics or skill names).",
        command = function()
            DockablePanel.ShowPanelByName(EncounterScriptValidator.panelName)
        end,
    }
end)
