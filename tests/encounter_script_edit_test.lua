--Run from the codex root with
--  ../dependencies/lua/bin/lua.exe tests/encounter_script_edit_test.lua [corpus/manifest.lua]
--Exercises EncounterScriptEdit (lossless script edits for the montage
--builder) and the line fields the parser records for it. The optional
--argument is a manifest of real journal documents ({id, name, folder,
--hidden, file} rows, files beside it): every one must split and join back
--byte for byte, and every roll in every script must survive being
--rewritten by the writers.
--The parser's words come from UIText and its text files, which call
--dmhub.GetModLoading() and report problems with dmhub.Error: stub those
--when running outside the app, so a missing id prints.
if dmhub == nil then
    dmhub = {
        GetModLoading = function() return {} end,
        Error = function(message) print(message) end,
    }
end
dofile("DMHub Utils/UIText.lua")
dofile("EncounterOfTheWeek/EncounterText.lua")
dofile("EncounterOfTheWeek/EncounterAuthoringText.lua")
dofile("DMHub Game Rules/TestRiders.lua")
dofile("EncounterOfTheWeek/EncounterScript.lua")
dofile("EncounterOfTheWeek/EncounterScriptEdit.lua")

local E = EncounterScriptEdit
local passed = 0
local function check(condition, message)
    if not condition then
        error("FAILED: " .. tostring(message), 2)
    end
    passed = passed + 1
end

--- Split / Join / Replace ---------------------------------------------------

for _, text in ipairs({ "", "a", "a\n", "a\nb", "a\n\nb\n", "a\vb\nc", "x\r\ny\rz\n", "\n\n", "# T\v\v|x\n" }) do
    local s = E.Split(text)
    check(E.Join(s) == text, "split/join identity: " .. string.format("%q", text))
    check(#s.lines == #EncounterScript.SplitLines(text), "line count matches the parser: " .. string.format("%q", text))
end

check(E.Replace("a\nb\nc", 2, 2, { "B" }) == "a\nB\nc", "replace a middle line")
check(E.Replace("a\nb\nc", 3, 3, { "C" }) == "a\nb\nC", "replace the last line keeps no final newline")
check(E.Replace("a\nb\nc\n", 3, 3, { "C", "D" }) == "a\nb\nC\nD\n", "replace with two lines")
check(E.Replace("a\nb\nc", 2, 1, { "x" }) == "a\nx\nb\nc", "insert before line 2")
check(E.Replace("a\nb", 3, 2, { "c" }) == "a\nb\nc", "append after the final line")
check(E.Replace("a\nb\nc", 2, 2, {}) == "a\nc", "delete a line")
check(E.Replace("a\vb\nc", 1, 1, { "A" }) == "A\vb\nc", "a soft break after a replaced line is kept")

local applied = E.Apply({ d = "1\n2\n3\n4" }, { E.Patch("d", 1, 1, { "one" }), E.Patch("d", 3, 4, { "three" }) })
check(applied.d == "one\n2\nthree", "two patches on one document, bottom-up")

--- parser line fields, across a sub-document ------------------------------------

local MASTER = table.concat({
    "# Montage",                         -- 1
    "",                                  -- 2
    "The road is dark.",                 -- 3
    "",                                  -- 4
    "## Round 1",                        -- 5
    "4 Players: -1 Opportunity",         -- 6
    "",                                  -- 7
    "[Cottage]",                         -- 8
    "",                                  -- 9
    "## Threat: Scouts (Temporary)",     -- 10
    "",                                  -- 11
    "Two goblins watch.",                -- 12
    "",                                  -- 13
    "Consequence: You begin the encounter surprised", -- 14
    "",                                  -- 15
    "### Ambush them",                   -- 16
    "",                                  -- 17
    "|Ambush Test: Agility (Sneak, Hide)", -- 18
    "|They escape",                      -- 19
    "|The threat is vanquished",         -- 20
    "|The threat is vanquished. You surprise the enemy", -- 21
    "|Edge: you can fly",                -- 22
    "",                                  -- 23
    "## Opportunity: Shrine",            -- 24
    "",                                  -- 25
    "### Pray",                          -- 26
    "",                                  -- 27
    "|+1 hero token",                    -- 28
    "|Allow: you are a Dwarf",           -- 29
    "",
    "# Encounter",
    "",
    "[[encounter]]",
    "",
}, "\n")

local COTTAGE = table.concat({
    "## Opportunity: Cottage",           -- 1
    "",                                  -- 2
    "A cottage sits off the path.",      -- 3
    "Smoke curls from it.",              -- 4
    "",                                  -- 5
    "### Knock",                         -- 6
    "",                                  -- 7
    "|Knock Test: Presence (Persuade, Lie)", -- 8
    "|tier one => The door stays shut",  -- 9
    "|You gain 1 Healing Potion",        -- 10
    "|Each party member gains 1 Healing Potion", -- 11
    "|Edge (Round 1): you speak Hyrallic", -- 12
    "",                                  -- 13
    "#### If you can teleport",          -- 14
    "",                                  -- 15
    "|You slip inside. You gain 2 Healing Potions", -- 16
}, "\n")

local function Workspace(texts)
    local byName = { Cottage = "cottage" }
    local names = { master = "Encounter", cottage = "Cottage" }
    local expansion = EncounterScript.ExpandIncludes({ id = "master", name = "Encounter", text = texts.master }, function(target)
        local id = byName[target]
        if id == nil then
            return nil, "names no document"
        end
        return { id = id, name = names[id], text = texts[id] }
    end)
    return EncounterScript.ParseExpanded(expansion, "master")
end

local texts = { master = MASTER, cottage = COTTAGE }
local parse = Workspace(texts)
local beat = parse.beats[1]
local entries = beat.rounds[1].entries
local cottage, scouts, shrine = entries[1], entries[2], entries[3]
check(cottage.name == "Cottage" and scouts.name == "Scouts" and shrine.name == "Shrine", "three entries parsed")

local function At(line)
    local docid, l = E.Source(parse, line)
    return docid .. ":" .. tostring(l)
end
check(At(cottage.line) == "cottage:1", "an included entry's heading maps to its sub-document")
check(At(scouts.line) == "master:10", "a master entry maps to the master")
local knock = cottage.options[1]
check(At(knock.roll.line) == "cottage:8", "roll header line")
check(At(knock.roll.tierLines[1]) == "cottage:9" and At(knock.roll.tierLines[3]) == "cottage:11", "tier lines")
check(knock.roll.tierLines[4] == nil and knock.roll.critAuto, "an automatic critical has no line")
check(At(knock.roll.lastLine) == "cottage:12", "the roll block ends at its rider")
check(At(knock.knacks[1].line) == "cottage:14", "knack heading line")
check(At(knock.knacks[1].free.lines[1]) == "cottage:16", "free rule line of a knack")
check(#cottage.descriptionLines == 1 and At(cottage.descriptionLines[1][1]) == "cottage:3" and At(cottage.descriptionLines[1][2]) == "cottage:4", "description span")
check(scouts.consequence ~= nil and At(scouts.consequence.lines[1]) == "master:14", "consequence span")
check(At(beat.introLines[1][1]) == "master:3", "beat intro span")
check(At(beat.rounds[1].scaling[1].line) == "master:6", "scaling line")

--- edit operations ---------------------------------------------------------------

local function Edit(patches, why)
    check(patches ~= nil, "edit refused: " .. tostring(why))
    local changed = E.Apply(texts, patches)
    local out = {}
    for k, v in pairs(texts) do
        out[k] = changed[k] or v
    end
    return out, Workspace(out)
end

--set a tier: only that line changes.
local t2, p2 = Edit(E.SetTier(parse, knock.roll, 2, "a small boon", "You gain 2 Healing Potions"))
check(t2.master == MASTER, "the master is untouched by a sub-document edit")
check(select(2, string.gsub(t2.cottage, "\n", "")) == select(2, string.gsub(COTTAGE, "\n", "")), "line count unchanged")
local r2 = p2.beats[1].rounds[1].entries[1].options[1].roll
check(r2.tiers[2] == "You gain 2 Healing Potions" and r2.teasers[2] == "a small boon", "tier 2 rewritten with its teaser")
check(r2.tiers[1] == "The door stays shut" and r2.teasers[1] == "tier one", "tier 1 untouched")

--write a critical, then clear it again.
local t3, p3 = Edit(E.SetTier(parse, knock.roll, 4, nil, "You gain 3 Healing Potions"))
local r3 = p3.beats[1].rounds[1].entries[1].options[1].roll
check(not r3.critAuto and r3.tiers[4] == "You gain 3 Healing Potions", "a written critical")
check(#r3.riders == 1, "the rider is still read after a new critical line")
texts, parse = t3, p3
local t4, p4 = Edit(E.ClearCritical(parse, r3))
check(t4.cottage == COTTAGE, "clearing the critical restores the document exactly")
texts, parse = { master = MASTER, cottage = COTTAGE }, Workspace({ master = MASTER, cottage = COTTAGE })
cottage, scouts, shrine = parse.beats[1].rounds[1].entries[1], parse.beats[1].rounds[1].entries[2], parse.beats[1].rounds[1].entries[3]
knock = cottage.options[1]

--riders: add, change, remove.
local t5, p5 = Edit(E.AddRider(parse, texts, knock, "bane", nil, "you have fire weakness"))
local riders5 = p5.beats[1].rounds[1].entries[1].options[1].roll.riders
check(#riders5 == 2 and riders5[2].effect == "bane", "a bane rider added inside the roll block")
local t6, p6 = Edit(E.SetRider(parse, knock.roll.riders[1], "doubleedge", nil, "you speak Hyrallic"))
local rider6 = p6.beats[1].rounds[1].entries[1].options[1].roll.riders[1]
check(rider6.effect == "doubleedge" and rider6.round == nil, "a rider rewritten")
local t7, p7 = Edit(E.RemoveRider(parse, knock.roll.riders[1]))
check(#p7.beats[1].rounds[1].entries[1].options[1].roll.riders == 0, "a rider removed")
local pray = shrine.options[1]
local t8, p8 = Edit(E.AddRider(parse, texts, pray, "allow", nil, "you are a Human"))
check(#p8.beats[1].rounds[1].entries[3].options[1].riders == 2, "an Allow rider added after a free option's rules")

--heading tags.
local t9, p9 = Edit(E.SetEntryHeading(parse, scouts, { required = true, temporary = false }))
local s9 = p9.beats[1].rounds[1].entries[2]
check(s9.required and not s9.temporary and s9.name == "Scouts", "heading retagged")

--description: replace, and add one where there was none.
local t10, p10 = Edit(E.SetDescription(parse, texts, cottage, "A crooked cottage.\n\nNobody answers."))
check(p10.beats[1].rounds[1].entries[1].description == "A crooked cottage.\n\nNobody answers.", "description replaced")
local t11, p11 = Edit(E.SetDescription(parse, texts, shrine, "A mossy shrine."))
local sh11 = p11.beats[1].rounds[1].entries[3]
check(sh11.description == "A mossy shrine." and #sh11.options == 1, "description added above the options")
check(E.SetDescription(parse, texts, shrine, "### not prose") == nil, "prose that would become a heading is refused")

--consequence: rewrite, remove, add.
local t12, p12 = Edit(E.SetConsequence(parse, texts, scouts, "You lose initiative"))
check(p12.beats[1].rounds[1].entries[2].consequence.text == "You lose initiative", "consequence rewritten")
local t13, p13 = Edit(E.SetConsequence(parse, texts, scouts, ""))
check(p13.beats[1].rounds[1].entries[2].consequence == nil, "consequence removed")
texts, parse = t13, p13
local t14, p14 = Edit(E.SetConsequence(parse, texts, p13.beats[1].rounds[1].entries[2], "Each party member loses 3 stamina"))
local s14 = p14.beats[1].rounds[1].entries[2]
check(s14.consequence ~= nil and s14.consequence.effects[1].kind == "stamina", "consequence added (before the options, where it is read)")
check(#s14.options == 1 and s14.options[1].text == "", "the option is not touched")
texts, parse = { master = MASTER, cottage = COTTAGE }, Workspace({ master = MASTER, cottage = COTTAGE })
cottage, scouts, shrine = parse.beats[1].rounds[1].entries[1], parse.beats[1].rounds[1].entries[2], parse.beats[1].rounds[1].entries[3]
knock = cottage.options[1]

--rules: replace a roll block from the writers.
local t15, p15 = Edit(E.SetRules(parse, texts, knock, E.RollLines({
    name = "Charm Test", characteristics = { "Presence" }, skills = { "Flirt" },
    tiers = { { text = "Nothing" }, { text = "+1 hero token" }, { teaser = "big", text = "+2 hero tokens" } },
    riders = { { effect = "edge", text = "you speak Caelian" } },
})))
local r15 = p15.beats[1].rounds[1].entries[1].options[1]
check(r15.roll.name == "Charm Test" and r15.roll.attr == "Presence (Flirt)" and r15.roll.teasers[3] == "big", "roll block replaced")
check(#r15.roll.riders == 1 and #r15.knacks == 1, "riders read and the knack kept")

--whole elements: append an option, delete one, delete an entry.
local block = E.OptionBlock("Peek in", "PC creeps to the window.", { "|You gain 1 Healing Potion" })
local t16, p16 = Edit(E.InsertAfterElement(parse, texts, knock.line, 3, block))
local c16 = p16.beats[1].rounds[1].entries[1]
check(#c16.options == 2 and c16.options[2].name == "Peek in" and c16.options[2].free ~= nil, "option appended")
check(#c16.options[1].knacks == 1, "the first option keeps its knack")
local t17, p17 = Edit(E.DeleteElement(parse, texts, knock.line, 3))
check(#p17.beats[1].rounds[1].entries[1].options == 0, "option deleted")
local t18, p18 = Edit(E.DeleteElement(parse, texts, scouts.line, 2))
local e18 = p18.beats[1].rounds[1].entries
check(#e18 == 2 and e18[1].name == "Cottage" and e18[2].name == "Shrine", "entry deleted")
check(#p18.warnings == #parse.warnings - 1, "deleting an entry takes its own warning with it and adds none")
local copy = E.ElementLines(parse, texts, scouts.line, 2)
check(copy[1] == "## Threat: Scouts (Temporary)" and copy[#copy] == "|Edge: you can fly", "element lines")

--prose fields, whole-element replacement, and the root anchor of an included line.
local t19, p19 = Edit(E.SetProse(parse, texts, parse.beats[1].introLines, parse.beats[1].line, "A cold night.\n\nWolves howl."))
check(p19.beats[1].intro == "A cold night.\n\nWolves howl.", "beat intro replaced")
local t20, p20 = Edit(E.SetProse(parse, texts, knock.textLines, knock.line, "PC raps on the door."))
check(p20.beats[1].rounds[1].entries[1].options[1].text == "PC raps on the door.", "option prose added under its heading")
local t21, p21 = Edit(E.ReplaceElement(parse, texts, shrine.line, 2, "## Opportunity: Altar\n\n### Pray\n\n|+2 hero tokens\n"))
local e21 = p21.beats[1].rounds[1].entries
check(e21[3].name == "Altar" and e21[3].options[1].free.effects[1].qty == 2, "an entry replaced as text")
check(E.RootLine(parse, cottage.line) == 8, "an included entry anchors on its include line")
check(E.RootLine(parse, scouts.line) == 10, "a root entry anchors on itself")

--- writers read back ----------------------------------------------------------------

local function ParseOne(lines)
    local text = "# Montage\n\n" .. table.concat(lines, "\n") .. "\n"
    return EncounterScript.Parse(text).beats[1].rounds[1].entries[1]
end
local entryBlock = E.EntryBlock({
    kind = "threat", name = "The Tolling", required = true, locked = true,
    description = "The bell tolls.", consequence = "You begin the encounter surprised",
    options = { E.OptionBlock("Muffle it", "", E.RollLines({ name = "Muffle Test", attr = "Might or Agility (Lift, Climb)",
        tiers = { { text = "You lose 3 stamina" }, { text = "The threat is vanquished" }, { text = "The threat is vanquished" }, { text = "+1 hero token" } } })) },
})
local tolling = ParseOne(entryBlock)
check(tolling.kind == "threat" and tolling.name == "The Tolling" and tolling.required and tolling.locked and not tolling.temporary, "entry block heading")
check(tolling.description == "The bell tolls." and tolling.consequence ~= nil, "entry block body")
check(tolling.options[1].roll.attr == "Might or Agility (Lift, Climb)" and not tolling.options[1].roll.critAuto, "entry block roll")

local d = EncounterScript.ParseScalingDirective(E.ScalingLine({ min = 4, max = 5, removals = { opportunity = 2, threat = 1 } }))
check(d ~= nil and d.min == 4 and d.max == 5 and d.removals.opportunity == 2 and d.removals.threat == 1, "scaling line round trip")
local d2 = EncounterScript.ParseScalingDirective(E.ScalingLine({ min = 5, removals = { opportunity = 1 } }))
check(d2 ~= nil and d2.min == 5 and d2.max == nil, "open-ended scaling line")
check(E.RollHeaderLine("Odd: Name", "Reason") == "|Odd Name: Reason", "a colon is dropped from a roll name")
check(E.TierLine(nil, "a | b") == "|a / b", "a bar in tier text cannot end the tier")

local tableEntry = ParseOne({ "## Opportunity: Tinkerer", "", "### Browse", "", "|You roll on Wares", "",
    table.unpack(E.TableLines({ name = "Wares", dice = "1d6", rows = { { lo = 1, hi = 2, text = "You gain 1 Healing Potion" }, { lo = 3, hi = 6, text = "+1 hero token" } } })) })
local wares = (tableEntry.tables or {})[EncounterScript.MatchKey("Wares")]
check(wares ~= nil and #wares.rows == 2 and wares.rows[2].lo == 3 and wares.rows[2].hi == 6, "table lines round trip")
check(not wares.mystery, "a plain table is not a mystery")

local hoardLines = E.TableLines({ name = "Hoard", dice = "1d3", mystery = true, rows = { { lo = 1, hi = 3, text = "You gain 1 Healing Potion" } } })
check(hoardLines[1] == "|Hoard: 1d3 (Mystery)", "a mystery table's header keeps its tag")
local hoardEntry = ParseOne({ "## Opportunity: Statues", "", "### Search", "", "|You roll on Hoard", "", table.unpack(hoardLines) })
local hoard = (hoardEntry.tables or {})[EncounterScript.MatchKey("Hoard")]
check(hoard ~= nil and hoard.mystery == true and hoard.dice == "1d3" and #hoard.rows == 1, "mystery table lines round trip")
check(E.TableHeaderValue("2d6", false) == "2d6" and E.TableHeaderValue("2d6", true) == "2d6 (Mystery)", "table header value")

--- scene step forms ------------------------------------------------------------------

local ACTORS = { witch = { name = "Witch", monster = "Hag" } }
local function StepRoundTrip(line, expect)
    local form = E.ReadSceneStep(line, ACTORS)
    for k, v in pairs(expect) do
        check(form[k] == v, string.format("ReadSceneStep %q: %s = %s, got %s", line, k, tostring(v), tostring(form[k])))
    end
    local again = E.ReadSceneStep(E.SceneStepLine(form), ACTORS)
    for k, v in pairs(form) do
        check(again[k] == v, string.format("SceneStepLine round trip %q: %s", line, k))
    end
    return form
end
StepRoundTrip("PC looks around.", { kind = "narrate", text = "PC looks around." })
StepRoundTrip("Beware: the path is steep.", { kind = "narrate" })
StepRoundTrip("PC: Hello there!", { kind = "say", speaker = "PC", text = "Hello there!", offstage = false })
StepRoundTrip("Witch (scared): (in Hyrallic) Spare me!", { kind = "say", speaker = "Witch", emote = "scared", lang = "Hyrallic", text = "Spare me!" })
StepRoundTrip("??? (offstage): Who goes there?", { kind = "say", speaker = "???", offstage = true })
StepRoundTrip("Witch (Hag) enters", { kind = "enter", name = "Witch", monster = "Hag" })
StepRoundTrip("Goblin enters", { kind = "enter", name = "Goblin", monster = "Goblin" })
StepRoundTrip("Witch exits", { kind = "exit", name = "Witch" })
StepRoundTrip("Witch is alarmed", { kind = "emote", name = "Witch", emote = "alarmed" })
StepRoundTrip("if PC speaks Caelian then", { kind = "if", cond = "PC speaks Caelian" })
StepRoundTrip("elseif tier2 then", { kind = "elseif", cond = "tier2" })
StepRoundTrip("else", { kind = "else" })
StepRoundTrip("end", { kind = "end" })
check(E.SceneStepLine({ kind = "enter", name = "Xochi", monster = "Goblin Sniper" }) == "Xochi (Goblin Sniper) enters", "enter line with a portrait")
check(E.SceneStepLine({ kind = "say", speaker = "Witch", offstage = true, emote = "scared", text = "Hi" }) == "Witch (offstage): Hi", "an off-stage voice drops the emote")
check(E.SceneStepLine({ kind = "say", speaker = "PC", text = "a\nb | c" }) == "PC: a b / c", "speech is one line")
for _, e in ipairs(E.SceneEmotes()) do
    check(EncounterScript.SCENE_EMOTES[e], "SceneEmotes lists the parser's emotes")
end

local blockLines = { "PC: a", "if tier1 then", "  PC: b", "  if PC speaks X then", "    PC: c", "  end", "elseif tier2 then", "  PC: d", "else", "  PC: e", "end", "PC: f" }
check(E.SceneBlockEnd(blockLines, 2) == 11, "SceneBlockEnd skips a nested block")
check(E.SceneBlockEnd(blockLines, 4) == 6, "SceneBlockEnd of the nested block")
check(E.SceneBranchEnd(blockLines, 2) == 6, "SceneBranchEnd: the if branch runs to the elseif")
check(E.SceneBranchEnd(blockLines, 7) == 8, "SceneBranchEnd: the elseif branch")
check(E.SceneBranchEnd(blockLines, 9) == 10, "SceneBranchEnd: the else branch")
check(E.SceneBlockEnd({ "if tier1 then", "PC: a" }, 1) == nil, "an unclosed block has no end")

--- condition forms ---------------------------------------------------------------------

local function CondRoundTrip(text, expectRows)
    local rows = E.ReadCondition(text)
    check(rows ~= nil and #rows == #expectRows, "ReadCondition row count: " .. text)
    ---@cast rows -nil
    for i, want in ipairs(expectRows) do
        for k, v in pairs(want) do
            check(rows[i][k] == v, string.format("ReadCondition %q row %d: %s = %s, got %s", text, i, k, tostring(v), tostring(rows[i][k])))
        end
    end
    --the written text means the same to the parser.
    local written = E.ConditionText(rows)
    local _, problems = EncounterScript.ParseCondition(written)
    check(#problems == 0, "ConditionText parses clean: " .. written)
    local again = E.ReadCondition(written)
    ---@cast again -nil
    for i, row in ipairs(rows) do
        check(again[i].kind == row.kind and again[i].value == row.value and (again[i].negate == true) == (row.negate == true)
            and again[i].join == row.join, string.format("condition round trip %q row %d", text, i))
    end
    return rows
end
CondRoundTrip("PC speaks Caelian then", { { kind = "speaks", value = "Caelian" } })
CondRoundTrip("PC does not speak Caelian", { { kind = "speaks", value = "Caelian", negate = true } })
CondRoundTrip("PC is a Dwarf and not PC is skilled in Sneak", { { kind = "kindred", value = "Dwarf" }, { kind = "skilled", value = "Sneak", negate = true, join = "and" } })
CondRoundTrip("PC is an Elementalist or PC was a Farmer", { { kind = "kindred", value = "Elementalist" }, { kind = "career", value = "Farmer", join = "or" } })
CondRoundTrip("PC has the Lucky Dog perk", { { kind = "perk", value = "Lucky Dog" } })
CondRoundTrip("PC has a lantern", { { kind = "has", value = "a lantern" } })
CondRoundTrip("PC can fly", { { kind = "can", value = "fly" } })
CondRoundTrip("PC is small", { { kind = "is", value = "small" } })
CondRoundTrip("PC chose Steal some potions and not tier1", { { kind = "chose", value = "Steal some potions" }, { kind = "tier", value = "1", negate = true, join = "and" } })
CondRoundTrip("tier 2 or crit", { { kind = "tier", value = "2" }, { kind = "tier", value = "4", join = "or" } })
CondRoundTrip("PC worships Grole", { { kind = "custom", value = "PC worships Grole" } })
check(E.ReadCondition("(PC can fly or PC can climb) and tier3") == nil, "parentheses stay text")
check(E.ReadCondition("PC can fly and") == nil, "a dangling join stays text")
check(E.ConditionText({ { kind = "career", value = "Artisan" } }) == "PC was an Artisan", "an before a vowel")

--- the clause catalogue and outcome forms -------------------------------------------

--every catalogue kind, with every value its picker offers, writes a clause
--that parses back to the same kind and values.
local EFFECT_FIELDS = { "target", "qty", "dice", "outcome", "keyword", "zone", "object", "effect", "damageType" }
local VARIANTS = {
    target = { "self", "party" }, qty = { 1, 2, 5 }, outcome = { "win", "lose", "surprise", "surprised" },
    effect = { "edge", "doubleedge", "bane", "doublebane" }, damageType = EncounterScript.DAMAGE_TYPES,
}
local catalogueChecks = 0
for _, c in ipairs(EncounterScript.CLAUSES) do
    check(EncounterScript.ClauseInfo(c.kind) == c, "ClauseInfo: " .. c.kind)
    ---@type table<string, any>
    local base = { kind = c.kind }
    for k, v in pairs(c.defaults) do base[k] = v end
    if base.name == "" then base.name = "Capture Them" end
    local tries = { base }
    for field, values in pairs(VARIANTS) do
        if base[field] ~= nil then
            for _, v in ipairs(values) do
                local e = {}
                for k, x in pairs(base) do e[k] = x end
                e[field] = v
                tries[#tries + 1] = e
            end
        end
    end
    if c.kind == "loserecovery" then
        tries[#tries + 1] = { kind = "loserecovery", target = "party", dice = "1d3", qty = 3 }
    end
    for _, e in ipairs(tries) do
        local text = EncounterScript.ClauseText(e)
        local back = EncounterScript.ParseEffects(text)
        check(#back == 1 and back[1].kind == c.kind, string.format("catalogue %s: %q parses back as %s", c.kind, tostring(text), tostring(back[1] and back[1].kind)))
        for _, f in ipairs(EFFECT_FIELDS) do
            if e[f] ~= nil and not (f == "qty" and e.dice ~= nil) then
                check(tostring(back[1][f]) == tostring(e[f]), string.format("catalogue %s %q: %s", c.kind, text, f))
            end
        end
        if e.name ~= nil and c.kind ~= "item" then
            check(back[1].name == e.name, string.format("catalogue %s %q: name", c.kind, text))
        end
        catalogueChecks = catalogueChecks + 1
    end
end
check(catalogueChecks > 60, "the catalogue was exercised")
check(EncounterScript.ParseEffects(EncounterScript.ClauseText({ kind = "item", qty = 3, name = "Healing Potion" }))[1].name == "Healing Potions",
    "three of an item are written in the plural (FindGear drops the s)")

local function SameEffects(a, b, label)
    check(#a.effects == #b.effects, label .. ": effect count")
    for i, x in ipairs(a.effects) do
        local y = b.effects[i]
        for _, f in ipairs({ "kind", "target", "qty", "dice", "name", "outcome", "keyword", "zone", "object", "effect", "damageType" }) do
            check(tostring(x[f]) == tostring(y[f]), string.format("%s: effect %d %s", label, i, f))
        end
        check(x.hidden == y.hidden, string.format("%s: effect %d hidden", label, i))
    end
    --the free text may gain a full stop: it separates it from the effects.
    local function Bare(t) return (string.gsub(t, "[%.,;!%?]$", "")) end
    check(Bare(a.text) == Bare(b.text), label .. ": text " .. string.format("%q vs %q", a.text, b.text))
end
for _, line in ipairs({
    "You make off with some potions! Each party member gains one Healing Potion",
    "You gain a Rope. {Unlock the Old Mill}",
    "The witch is unimpressed.",
    "You lose 6 Stamina. Each party member gains one Healing Potion.",
    "Nothing comes of it",
    "The threat is vanquished. +1 hero token",
    "Bones everywhere, and a chill. You lose a recovery. {The party has an edge on Capture Them}, you shiver",
    "+2 Malice",
    "",
}) do
    local o = E.ReadOutcome(line)
    local written = E.OutcomeText(o)
    SameEffects(o, E.ReadOutcome(written), "outcome round trip " .. string.format("%q", line))
end
check(E.OutcomeText(E.ReadOutcome("You make off with some potions! Each party member gains one Healing Potion"))
    == "You make off with some potions! Each party member gains one Healing Potion", "an untouched line is written back as it was")
check(E.OutcomeText(E.ReadOutcome("You gain a Rope. {Unlock the Old Mill}")) == "You gain a Rope. {Unlock the Old Mill}", "a hidden clause keeps its braces")
local edited = E.ReadOutcome("The goblin flees. You gain 1 Healing Potion")
edited.effects[1].qty, edited.effects[1].text = 2, nil
edited.effects[#edited.effects + 1] = { kind = "herotoken", qty = 1 }
check(E.OutcomeText(edited) == "The goblin flees. You gain 2 Healing Potions. +1 hero token", "an edited effect is rewritten, a new one appended: " .. E.OutcomeText(edited))
check(E.OutcomeText({ text = "No full stop", effects = { { kind = "malice", qty = 1 } } }) == "No full stop. +1 Malice", "free text gets a full stop before the effects")
--untouched lines from the real scripts come back byte for byte.
for _, line in ipairs({
    "Impressed, she shares a trick of the trade. You gain two Healing Potions.",
    "She recognizes a kindred spirit and trades secrets late into the night. Each party member gains one Healing Potion. At the start of the next combat, you gain 1 surge.",
    "The old song moves them. A Wode Elf Sentry joins you.",
    "It seems ready to talk... You gain 1 Rope?! Wow.",
    "You capture it! It seems ready to talk... {Unlock Talk to the Goblin. Edge on Interrogate the Goblin. Bane on Befriend the Goblin}",
    "+1 Intelligence. {Unlock Talk to the Goblin. Edge on Befriend the Goblin}.",
    "Bones everywhere, and a chill. You lose a recovery. {The party has an edge on Capture Them}, you shiver",
}) do
    check(E.OutcomeText(E.ReadOutcome(line)) == line, "untouched outcome is identical: " .. E.OutcomeText(E.ReadOutcome(line)))
end
local glued = E.ReadOutcome("Late at night. +1 hero token. At the start of the next combat, you gain 1 surge.")
check(glued.text == "Late at night." and glued.effects[2].prefix == "At the start of the next combat, ", "flavour between effects stays glued to the next one")
local appended = E.ReadOutcome("You lose a recovery, you shiver")
appended.effects[#appended.effects + 1] = { kind = "herotoken", qty = 1 }
check(E.OutcomeText(appended) == "You lose a recovery, you shiver. +1 hero token", "a trailing phrase stays with its effect: " .. E.OutcomeText(appended))
check(E.OutcomeText({ text = "", effects = { { kind = "unlock", name = "The Mill", hidden = true } } }) == "{Unlock The Mill}", "effects alone")

--- the script builder: setup, reinforcements, narratives, tags ----------------------

for _, ins in ipairs({
    { kind = "placeobjects", label = "Trap", qty = 4, object = "Snare Trap", zone = "trap", deleteOthers = true },
    { kind = "placeobjects", label = "Pit", qty = 1, object = "Pit", zone = "pit", deleteOthers = false },
}) do
    local line = E.SetupLine(ins)
    local label, rest = string.match(line, "^([%a][%a '%-]*):%s*(.*)$")
    local back = EncounterScript.ParseSetupInstruction(rest)
    check(label == ins.label and back ~= nil and back.kind == "placeobjects" and back.qty == ins.qty and back.object == ins.object
        and back.zone == ins.zone and back.deleteOthers == ins.deleteOthers, "setup line round trip: " .. line)
end
local byLine = E.SetupLine({ kind = "bystanders", label = "Bystanders", names = { "Civilian", "Old Tam" } })
local by = EncounterScript.ParseSetupInstruction(string.match(byLine, ":%s*(.*)$"))
check(by ~= nil and by.kind == "bystanders" and #by.names == 2 and by.names[2] == "Old Tam", "bystander line round trip: " .. byLine)
local v1 = EncounterScript.ParseVictoryInstruction(string.match(E.SetupLine({ kind = "victory" }), ":%s*(.*)$"))
check(v1 ~= nil and v1.who == nil, "victory over every enemy round trip")
local v2 = EncounterScript.ParseVictoryInstruction(string.match(E.SetupLine({ kind = "victory", who = "dwarf", whoText = "Dwarf" }), ":%s*(.*)$"))
check(v2 ~= nil and v2.who == "dwarf", "victory over every Dwarf round trip")

for _, sched in ipairs({
    { rounds = { [3] = true } }, { rounds = { [2] = true, [4] = true, [6] = true } },
    { every = 1, from = 2 }, { every = 2, from = 3, to = 7 }, { every = 3, from = 1 },
}) do
    local line = E.ArriveLine(sched)
    local back = EncounterScript.ParseReinforcementSchedule(string.match(line, "^Arrive:%s*(.*)$"))
    check(back ~= nil, "arrive line parses: " .. line)
    ---@cast back -nil
    for r = 1, 10 do
        check(EncounterScript.ScheduleIncludes(back, r) == EncounterScript.ScheduleIncludes(sched, r), string.format("arrive round trip %q round %d", line, r))
    end
end
check(EncounterScript.ParseReinforcementZone(string.match(E.EnterLine("stairs"), ":%s*(.*)$")) == "Stairs", "enter line round trip")
check(EncounterScript.ParseShout(string.match(E.ShoutLine('For the "Hand"!'), ":%s*(.*)$")) == "For the 'Hand'!", "shout line round trip")

--new beats and sections parse clean, and a mode line sets the mode.
local starter = {}
for _, block in ipairs({ E.NarrativeBeatBlock(), E.MontageBeatBlock(), E.EncounterBeatBlock(), E.StoryBlock("Town Gate", "Goblins!") }) do
    for _, l in ipairs(block) do starter[#starter + 1] = l end
    starter[#starter + 1] = ""
end
local starterParse = EncounterScript.Parse(table.concat(starter, "\n"))
check(#starterParse.beats == 3 and starterParse.beats[1].kind == "narrative" and starterParse.beats[2].kind == "montage"
    and starterParse.beats[3].kind == "encounter" and starterParse.story.towngate ~= nil, "starter beats parse")
local narr = starterParse.beats[1]
check(#narr.sections == 1 and narr.sections[1].modeExplicit and #narr.sections[1].options == 2
    and narr.sections[1].options[1].ruleLines ~= nil and #narr.sections[1].options[1].effects == 1, "starter narrative section, options and rule lines")
local individual = EncounterScript.Parse("# Narrative\n## S\n" .. E.NarrativeModeLine("individual", "Pick one") .. "\n### A\n### B")
check(individual.beats[1].sections[1].mode == "individual" and individual.beats[1].sections[1].prompt == "Pick one", "mode line round trip")
local sectionParse = EncounterScript.Parse("# Narrative\n" .. table.concat(E.NarrativeSectionBlock("Camp"), "\n"))
check(#sectionParse.beats[1].sections == 1 and #sectionParse.beats[1].sections[1].options == 2, "new section block")
local rfParse = EncounterScript.Parse("# Encounter\n[[encounter]]\n" .. table.concat(E.ReinforcementBlock("Gunners"), "\n"))
local rf = rfParse.beats[1].reinforcements[1]
check(rf ~= nil and rf.name == "Gunners" and rf.schedule ~= nil and #rf.islands == 1 and rf.scheduleLine == 5, "new reinforcement block")
local rf2 = EncounterScript.Parse("# Encounter\n## Reinforcements: X\nArrive: round 2\nEnter: the Stairs zone\nShout: \"Hi\"\nThey come.\n[[encounter]]").beats[1].reinforcements[1]
check(rf2.scheduleLine == 3 and rf2.zoneLine == 4 and rf2.shoutLines[1].line == 5 and rf2.noteLines[1] == 6, "reinforcement line fields")
local unlockParse = EncounterScript.Parse("# Narrative\n" .. E.UnlockLine("Intelligence") .. "\n## S\n### A")
check(unlockParse.beats[1].unlocks ~= nil and unlockParse.beats[1].unlocks[1].feature == "intelligence", "unlock line")

--tags keep their data through swaps, deletes and inserts.
local tagLines = { "# A", "[[scene]]", "", "# B", "[[scene]]", "[[encounter]]", "", "# C" }
local occ = E.TagOccurrences(tagLines)
check(#occ == 3 and occ[1].key == "scene" and occ[2].key == "scene-1" and occ[3].key == "encounter", "tag keys follow the journal")
local swapped, swapMap = E.SwapBlocks(tagLines, 1, 2, 4, 6)
check(swapped[1] == "# B" and swapped[4] == "" and swapped[5] == "# A" and swapped[8] == "# C", "swap keeps the gap between blocks")
local remap, gone = E.RekeyTags(tagLines, swapped, swapMap)
check(remap["scene"] == "scene-1" and remap["scene-1"] == "scene" and remap["encounter"] == "encounter" and #gone == 0, "a swap swaps the keys")
check(E.RekeyChanges(remap, gone), "a swap changes keys")
local delPatch = E.Patch("d", 1, 3, {})
local afterDelete = E.Split(E.Replace(table.concat(tagLines, "\n"), 1, 3, {})).lines
remap, gone = E.RekeyTags(tagLines, afterDelete, E.PatchLineMap(#tagLines, { delPatch }))
check(remap["scene-1"] == "scene" and #gone == 1 and gone[1] == "scene", "deleting the first scene moves the second onto its key")
local insPatch = E.Patch("d", 1, 0, { "# New", "[[scene]]" })
local afterInsert = E.Split(E.Replace(table.concat(tagLines, "\n"), 1, 0, { "# New", "[[scene]]" })).lines
remap, gone = E.RekeyTags(tagLines, afterInsert, E.PatchLineMap(#tagLines, { insPatch }))
check(remap["scene"] == "scene-1" and remap["scene-1"] == "scene-2" and #gone == 0, "a new tag above shifts the old ones' keys")
remap, gone = E.RekeyTags(tagLines, tagLines, E.PatchLineMap(#tagLines, {}))
check(not E.RekeyChanges(remap, gone), "no edit, no change")
--a block moved as delete + insert keeps its tag.
local moveLines = { "# A", "[[scene:Night]]", "# B", "[[scene]]" }
local moved = { "# B", "[[scene]]", "# A", "[[scene:Night]]" }
remap = E.RekeyTags(moveLines, moved, { [1] = nil, [2] = nil, [3] = 1, [4] = 2 })
check(remap["scene:Night"] == "scene:Night" and remap["scene"] == "scene", "a moved named tag keeps its key")

--- the corpus -----------------------------------------------------------------------

local manifestPath = arg ~= nil and arg[1] or nil
if manifestPath ~= nil then
    local dir = string.match(manifestPath, "^(.*)[/\\]") or "."
    local docs = dofile(manifestPath)
    local textOf, byFolder = {}, {}
    for _, doc in ipairs(docs) do
        local f = assert(io.open(dir .. "/" .. doc.file, "rb"))
        local text = f:read("a")
        f:close()
        textOf[doc.id] = text
        check(E.Join(E.Split(text)) == text, "corpus split/join: " .. doc.name)
        check(#E.Split(text).lines == #EncounterScript.SplitLines(text), "corpus line count: " .. doc.name)
        if not doc.hidden then
            byFolder[doc.folder] = byFolder[doc.folder] or {}
            table.insert(byFolder[doc.folder], doc)
        end
    end

    local scripts, rolls, headings = 0, 0, 0
    for _, folderDocs in pairs(byFolder) do
        local byKey = {}
        for _, doc in ipairs(folderDocs) do
            byKey[string.lower(doc.name)] = doc
        end
        --the runtime's EncounterMontage.ResolveScriptInclude, by name within the map folder.
        local function Resolve(target)
            local key = string.lower(target)
            key = string.match(key, "^document:(.+)$") or key
            local doc = byKey[key]
            if doc == nil then
                return nil, nil
            end
            return { id = doc.id, name = doc.name, text = textOf[doc.id] }
        end
        for _, doc in ipairs(folderDocs) do
            local text = textOf[doc.id]
            if string.find(text, "# Montage", 1, true) ~= nil then
                scripts = scripts + 1
                local expansion = EncounterScript.ExpandIncludes({ id = doc.id, name = doc.name, text = text }, Resolve)
                local p = EncounterScript.ParseExpanded(expansion, doc.id)
                local docTexts = { [doc.id] = text }
                for id in pairs(p.included or {}) do
                    docTexts[id] = textOf[id]
                end
                local function LineAt(line)
                    local docid, l = E.Source(p, line)
                    return E.Split(docTexts[docid]).lines[l]
                end
                local function Entries()
                    local list = {}
                    for _, b in ipairs(p.beats) do
                        for _, e in ipairs(EncounterScript.MontageEntries(b)) do
                            list[#list + 1] = e
                        end
                    end
                    for _, dv in pairs(p.delves) do
                        for _, e in ipairs(dv.obstacles) do
                            list[#list + 1] = e
                        end
                    end
                    return list
                end
                for _, e in ipairs(Entries()) do
                    headings = headings + 1
                    check(E.HeadingLevel(LineAt(e.line)) == 2, "entry heading maps to a ## line: " .. e.name)
                    if e.kind ~= "obstacle" then
                        --the heading writer reads back to the same entry.
                        local again = ParseOne({ E.EntryHeadingLine(e), "", "### X", "", "|+1 hero token" })
                        check(again.name == e.name and again.kind == e.kind and again.required == e.required
                            and again.locked == e.locked and again.temporary == e.temporary, "entry heading survives: " .. e.name)
                    end
                    for _, o in ipairs(e.options) do
                        check(E.HeadingLevel(LineAt(o.line)) == 3, "option heading maps to a ### line: " .. o.name)
                        local holders = { o }
                        for _, k in ipairs(o.knacks or {}) do
                            check(E.HeadingLevel(LineAt(k.line)) == 4, "knack heading maps to a #### line: " .. k.requirementText)
                            holders[#holders + 1] = k
                        end
                        for _, h in ipairs(holders) do
                            if h.roll ~= nil then
                                rolls = rolls + 1
                                --rewrite the block from what was parsed; it must read back the same.
                                local tiers = {}
                                local written = #h.roll.tierLines
                                for t = 1, written do
                                    tiers[t] = { teaser = h.roll.teasers[t], text = h.roll.tiers[t] }
                                end
                                local riders = {}
                                for _, r in ipairs(h.roll.riders) do
                                    riders[#riders + 1] = { effect = r.effect, round = r.round, text = r.text }
                                end
                                local patches = assert(E.SetRules(p, docTexts, h, E.RollLines({ name = h.roll.name, attr = h.roll.attr, tiers = tiers, riders = riders })))
                                local changed = E.Apply(docTexts, patches)
                                local docid = patches[1].docid
                                local newTexts = {}
                                for id, tx in pairs(docTexts) do
                                    newTexts[id] = changed[id] or tx
                                end
                                local exp2 = EncounterScript.ExpandIncludes({ id = doc.id, name = doc.name, text = newTexts[doc.id] }, function(target)
                                    local r = Resolve(target)
                                    if r ~= nil then
                                        r.text = newTexts[r.id] or r.text
                                    end
                                    return r
                                end)
                                local p2 = EncounterScript.ParseExpanded(exp2, doc.id)
                                check(#p2.warnings == #p.warnings, "no new warnings rewriting " .. h.roll.name .. " in " .. tostring(docid))
                                --find the same roll again by its header line.
                                local found = nil
                                local function Visit(x)
                                    if x.roll ~= nil and x.roll.line == h.roll.line then
                                        found = x.roll
                                    end
                                end
                                for _, b in ipairs(p2.beats) do
                                    for _, e2 in ipairs(EncounterScript.MontageEntries(b)) do
                                        for _, o2 in ipairs(e2.options) do
                                            Visit(o2)
                                            for _, k2 in ipairs(o2.knacks or {}) do Visit(k2) end
                                        end
                                    end
                                end
                                for _, dv in pairs(p2.delves) do
                                    for _, e2 in ipairs(dv.obstacles) do
                                        for _, o2 in ipairs(e2.options) do
                                            Visit(o2)
                                            for _, k2 in ipairs(o2.knacks or {}) do Visit(k2) end
                                        end
                                    end
                                end
                                check(found ~= nil, "rewritten roll found again: " .. h.roll.name)
                                ---@cast found -nil
                                check(found.name == h.roll.name and found.attr == h.roll.attr and found.critAuto == h.roll.critAuto, "roll header survives: " .. h.roll.name)
                                for t = 1, 4 do
                                    check(found.tiers[t] == h.roll.tiers[t] and found.teasers[t] == h.roll.teasers[t], string.format("tier %d survives: %s", t, h.roll.name))
                                end
                                check(#found.riders == #h.roll.riders, "riders survive: " .. h.roll.name)
                                for ri, r in ipairs(found.riders) do
                                    check(r.effect == h.roll.riders[ri].effect and r.text == h.roll.riders[ri].text and r.round == h.roll.riders[ri].round, "rider survives: " .. h.roll.name)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    check(scripts > 0, "the corpus holds at least one script")
    print(string.format("corpus: %d documents, %d scripts, %d entries, %d rolls rewritten", #docs, scripts, headings, rolls))
end

print(string.format("encounter_script_edit_test: %d checks passed", passed))
