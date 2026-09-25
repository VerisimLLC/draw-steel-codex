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
                if o.roll ~= nil then
                    for t in ipairs(o.roll.tiers) do
                        CollectZones(o.roll.effects[t])
                    end
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
            else
                Row(1, "flavourUnknown", "setup %s: UNRECOGNIZED '%s'", ins.label, ins.text)
                Problem("%s: setup instruction '%s' is not understood", EncounterScript.LineLabel(parse, ins.line), ins.text)
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
                for _, o in ipairs(entry.options) do
                    counts.options = counts.options + 1
                    Row(3, "option", "%s", o.name)
                    if o.roll == nil then
                        Row(4, "flavourUnknown", "no power roll")
                    else
                        Row(4, "roll", "%s: %s", o.roll.name, o.roll.attr)
                        for _, problem in ipairs(AttrProblems(o.roll.attr)) do
                            Row(5, "flavourUnknown", "%s", problem)
                            Problem("%s: option '%s' -- %s", EncounterScript.LineLabel(parse, o.line), o.name, problem)
                        end
                        for t in ipairs(o.roll.tiers) do
                            local label = string.format("tier %d: ", t)
                            if t == 4 then
                                label = "critical: "
                            end
                            if o.roll.teasers[t] ~= nil then
                                Row(5, "note", "%steaser '%s'", label, o.roll.teasers[t])
                            end
                            RulesFor(5, label, o.roll.tiers[t])
                        end
                        for _, rider in ipairs(o.roll.riders or {}) do
                            Row(5, cond(rider.requirement.unrecognized, "flavourUnknown", "rule"),
                                "%s: %s", EncounterScript.RiderLabel(rider.effect), rider.text)
                        end
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
function EncounterScriptValidator.BuildReport(docid)
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
