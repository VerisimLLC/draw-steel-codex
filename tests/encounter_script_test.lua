--Run from the codex root with ../dependencies/lua/bin/lua.exe tests/encounter_script_test.lua
--Exercises the pure Encounter of the Week script parser against the sample
--script from EncounterOfTheWeek.md and a few edge cases.
dofile("DMHub Game Rules/TestRiders.lua")
dofile("EncounterOfTheWeek/EncounterScript.lua")

local passed = 0
local function check(condition, message)
    if not condition then
        error("FAILED: " .. tostring(message), 2)
    end
    passed = passed + 1
end

local SAMPLE = [==[
# Montage

[[scene]]

## Round 1

## Opportunity: Mysterious Cottage

A mysterious cottage lays off the path. Dare you approach?

Options: Approaching the cottage, you see a witch within, brewing some potions in her cauldron.

### Negotiate with her for some aid

|Negotiation Test: Presence (Empathize, Lie, Flirt)
|You fail at the test
|You gain one Healing Potion
|Each party member gains one Healing Potion

### Steal some potions

|Thievery Test: Agility (Climb, Disguise, Sneak)
|You lose 6 Stamina.
|You lose 6 Stamina. Each party members gains one Healing Potion.
|Each party members gains one Healing Potion

## Opportunity: Elvish Village

An Elvish Village is nestled in the forest. Approach and ask for aid?

Options: Approaching the village you ask them for aid against dangers ahead.

### Ask for Aid

|Negotiation Test: Presence (Empathize, Nature)
|You fail at the test
|A Wode Elf Sentry joins you. +2 Malice
|A Wode Elf Sentry joins you

## Threat: Dangerous Beasts

Dangerous beasts lurk in the forest, a constant threat.

Consequence: Each party member loses 5 stamina.

Options: You try to deal with the threat.

### Hunt the Beasts

|Hunting Test: Might or Agility (Endurance, Track)
|You lose 5 stamina.
|You lose 5 stamina, the threat is vanquished.
|The threat is vanquished.

### Outsmart the Beasts


|Strategy Test: Reason (Strategy, Animal Handling)
|You fail at the test.
|+2 malice, the threat is vanquished.
|The threat is vanquished.


# Encounter

[[encounter]]
]==]

--- the sample script --------------------------------------------------------
local parse = EncounterScript.Parse(SAMPLE)
check(#parse.warnings == 0, "sample parses with no warnings: " .. table.concat(parse.warnings, " | "))
check(#parse.beats == 2, "two beats")
check(parse.beats[1].kind == "montage", "first beat is the montage")
check(parse.beats[2].kind == "encounter", "second beat is the encounter")
check(parse.beats[2].encounterTag == "encounter", "encounter beat carries its island tag")
check(parse.hasEncounterTag, "encounter tag seen")

local montage = parse.beats[1]
check(montage.sceneTag == "scene", "scene tag captured")
check(#montage.rounds == 1 and montage.rounds[1].number == 1, "one explicit round")
check(EncounterScript.RoundCount(montage) == 1, "round count 1")
local entries = montage.rounds[1].entries
check(#entries == 3, "three entries in round 1")

local cottage = entries[1]
check(cottage.kind == "opportunity" and cottage.name == "Mysterious Cottage", "cottage entry")
check(cottage.id == "r1-opportunity-mysterious-cottage", "stable entry id: " .. cottage.id)
check(cottage.description == "A mysterious cottage lays off the path. Dare you approach?", "cottage description")
check(cottage.approach == "Approaching the cottage, you see a witch within, brewing some potions in her cauldron.", "cottage approach text")
check(cottage.consequence == nil, "opportunities have no consequence")
check(#cottage.options == 2, "two cottage options")

local negotiate = cottage.options[1]
check(negotiate.name == "Negotiate with her for some aid", "option name")
check(negotiate.roll ~= nil, "option has a roll")
check(negotiate.roll.name == "Negotiation Test", "roll name")
check(negotiate.roll.attr == "Presence (Empathize, Lie, Flirt)", "roll attr")
check(#negotiate.roll.tiers == 3, "three tiers")
check(negotiate.roll.effects[1][1].kind == "narrative" and not negotiate.roll.effects[1][1].unrecognized, "fail clause is recognized narrative")
local t2 = negotiate.roll.effects[2]
check(#t2 == 1 and t2[1].kind == "item" and t2[1].target == "self" and t2[1].qty == 1 and t2[1].name == "Healing Potion", "tier 2: you gain one Healing Potion")
local t3 = negotiate.roll.effects[3]
check(#t3 == 1 and t3[1].kind == "item" and t3[1].target == "party" and t3[1].qty == 1 and t3[1].name == "Healing Potion", "tier 3: each party member gains one Healing Potion")

local steal = cottage.options[2]
local s2 = steal.roll.effects[2]
check(#s2 == 2, "tier 2 of steal has two clauses")
check(s2[1].kind == "stamina" and s2[1].target == "self" and s2[1].qty == 6, "you lose 6 stamina")
check(s2[2].kind == "item" and s2[2].target == "party" and s2[2].name == "Healing Potion", "party members gains (plural) handled")

local village = entries[2]
local aid = village.options[1]
local a2 = aid.roll.effects[2]
check(#a2 == 2 and a2[1].kind == "ally" and a2[1].name == "Wode Elf Sentry", "ally clause keeps its spelling: " .. tostring(a2[1].name))
check(a2[2].kind == "malice" and a2[2].qty == 2, "+2 Malice")
check(#aid.roll.effects[3] == 1 and aid.roll.effects[3][1].kind == "ally", "tier 3 ally only")

local beasts = entries[3]
check(beasts.kind == "threat", "threat entry")
check(beasts.consequence ~= nil and beasts.consequence.text == "Each party member loses 5 stamina.", "consequence text")
check(#beasts.consequence.effects == 1 and beasts.consequence.effects[1].kind == "stamina" and beasts.consequence.effects[1].target == "party" and beasts.consequence.effects[1].qty == 5, "consequence effect")
check(beasts.approach == "You try to deal with the threat.", "threat approach")
local hunt = beasts.options[1]
check(hunt.roll.attr == "Might or Agility (Endurance, Track)", "hunt attr")
local h2 = hunt.roll.effects[2]
check(#h2 == 2 and h2[1].kind == "stamina" and h2[1].qty == 5 and h2[2].kind == "vanquish", "lose 5, vanquished")
check(#hunt.roll.effects[3] == 1 and hunt.roll.effects[3][1].kind == "vanquish", "tier 3 vanquished")
local outsmart = beasts.options[2]
check(outsmart.roll ~= nil, "blank lines before the roll block are fine")
local o2 = outsmart.roll.effects[2]
check(#o2 == 2 and o2[1].kind == "malice" and o2[1].qty == 2 and o2[2].kind == "vanquish", "+2 malice, vanquished")

--- helpers -------------------------------------------------------------------
check(EncounterScript.FindEntry(montage, "r1-threat-dangerous-beasts") == beasts, "FindEntry")
check(#EncounterScript.EntriesForRound(montage, 1) == 3, "entries for round 1")
check(#EncounterScript.EntriesForRound(montage, 5) == 3, "entries persist into later rounds")
local items, monsters = EncounterScript.ReferencedNames(parse)
check(items["Healing Potion"] and monsters["Wode Elf Sentry"], "referenced names")
check(EncounterScript.ParseQuantity("three") == 3 and EncounterScript.ParseQuantity("12") == 12 and EncounterScript.ParseQuantity("an") == 1 and EncounterScript.ParseQuantity("lots") == nil, "quantities")

--ParseAttr with injected tables
local attributesInfo = {
    mgt = { description = "Might" }, agl = { description = "Agility" }, rea = { description = "Reason" },
    inu = { description = "Intuition" }, prs = { description = "Presence" },
}
local skillOptions = {
    { id = "empathize", text = "Empathize" }, { id = "lie", text = "Lie" }, { id = "flirt", text = "Flirt" },
    { id = "track", text = "Track" }, { id = "endurance", text = "Endurance" }, { id = "nature", text = "Nature" },
}
local chars, skills = EncounterScript.ParseAttr("Might or Agility (Endurance, Track)", attributesInfo, skillOptions)
check(chars.mgt and chars.agl and not chars.prs, "two characteristics")
table.sort(skills)
check(#skills == 2 and skills[1] == "endurance" and skills[2] == "track", "two skills")
chars, skills = EncounterScript.ParseAttr("Presence (Empathize, Lie, Flirt)", attributesInfo, skillOptions)
check(chars.prs and #skills == 3, "presence + three skills")

--Describe runs
local text = EncounterScript.Describe(parse)
check(string.find(text, "beat 1: Montage", 1, true) ~= nil, "describe")

--- edge cases ----------------------------------------------------------------
--no beats + island = implicit encounter
local implicit = EncounterScript.Parse("Some notes\n\n[[encounter]]\n")
check(#implicit.beats == 1 and implicit.beats[1].kind == "encounter" and implicit.beats[1].implicit, "implicit encounter beat")
check(#implicit.warnings == 0, "implicit encounter has no warnings")

--no island, no beats = nothing
local nothing = EncounterScript.Parse("Just prose.")
check(#nothing.beats == 0, "no beats")

--no round heading = implicit round 1; four-tier roll; unknown clause warns
local edge = EncounterScript.Parse([[
# Montage

Some intro prose.

## Threat: Rockfall

Rocks.

### Dodge

|Dodge Test: Agility (Jump)
|You lose 3 stamina and drop your torch
|You lose 1 stamina
|The threat is vanquished
|The threat is vanquished, you gain two Healing Potion
]])
check(#edge.beats == 1, "edge: one beat")
local eb = edge.beats[1]
check(eb.intro == "Some intro prose.", "intro captured")
check(#eb.rounds == 1 and eb.rounds[1].implicit and eb.rounds[1].number == 1, "implicit round")
local rock = eb.rounds[1].entries[1]
check(rock.id == "r1-threat-rockfall", "rock id")
check(#rock.options[1].roll.tiers == 4, "four tiers")
check(rock.options[1].roll.effects[4][2].kind == "item" and rock.options[1].roll.effects[4][2].qty == 2, "critical tier item x2")
check(rock.options[1].roll.effects[1][1].unrecognized == true, "unknown clause flagged")
local sawUnrecognized, sawNoConsequence = false, false
for _, w in ipairs(edge.warnings) do
    if string.find(w, "unrecognized effect", 1, true) then sawUnrecognized = true end
    if string.find(w, "has no Consequence", 1, true) then sawNoConsequence = true end
end
check(sawUnrecognized and sawNoConsequence, "warnings for unknown clause and missing consequence")

--initiative clauses: tier lines and a Consequence: line
local init = EncounterScript.Parse([[
# Montage

## Threat: Scouts

Enemy scouts watch the road.

Consequence: You begin the encounter surprised.

### Ambush them

|Stealth Test: Agility (Sneak)
|You lose initiative.
|You win the initiative
|You surprise the enemy, +1 malice
]])
local scouts = init.beats[1].rounds[1].entries[1]
check(scouts.consequence.effects[1].kind == "initiative" and scouts.consequence.effects[1].outcome == "surprised", "consequence: surprised")
local ie = scouts.options[1].roll.effects
check(ie[1][1].kind == "initiative" and ie[1][1].outcome == "lose", "tier 1: lose initiative")
check(ie[2][1].kind == "initiative" and ie[2][1].outcome == "win", "tier 2: win initiative")
check(ie[3][1].kind == "initiative" and ie[3][1].outcome == "surprise" and ie[3][2].kind == "malice", "tier 3: surprise the enemy + malice")
check(#init.warnings == 0, "initiative clauses are recognized: " .. table.concat(init.warnings, "; "))
check(EncounterScript.ParseInitiativeClause("you start the next encounter surprised") == "surprised", "start the next encounter surprised")
check(EncounterScript.ParseInitiativeClause("the party begins the encounter surprised") == "surprised", "the party begins surprised")
check(EncounterScript.ParseInitiativeClause("you are surprised") == "surprised", "you are surprised")
check(EncounterScript.ParseInitiativeClause("you surprise the enemies") == "surprise", "surprise the enemies")
check(EncounterScript.ParseInitiativeClause("the enemy is surprised") == "surprise", "the enemy is surprised")
check(EncounterScript.ParseInitiativeClause("you lose the initiative") == "lose", "lose the initiative")
check(EncounterScript.ParseInitiativeClause("you lose 5 stamina") == nil, "stamina is not initiative")
check(string.find(EncounterScript.DescribeEffect(ie[3][1]), "surprise the enemy", 1, true) ~= nil, "describe initiative")

--unknown beat kind, stray headings
local stray = EncounterScript.Parse("# Narration\n\nhello\n\n## Opportunity: X\n\n### Y\n")
check(stray.beats[1].kind == "unknown", "unknown beat kind")
check(#stray.warnings >= 3, "warnings for unknown beat and stray headings: " .. #stray.warnings)

--multiple rounds: entries introduced in round 2 are not available in round 1
local rounds = EncounterScript.Parse([[
# Montage
## Round 1
## Opportunity: A
### a
|T: Might
|x
|y
|z
## Round 2
## Threat: B
Consequence: +1 malice
### b
|T: Might
|x
|y
|z
]])
local mb = rounds.beats[1]
check(EncounterScript.RoundCount(mb) == 2, "two rounds")
check(#EncounterScript.EntriesForRound(mb, 1) == 1 and #EncounterScript.EntriesForRound(mb, 2) == 2, "round-2 entry appears from round 2")
check(mb.rounds[2].entries[1].consequence.effects[1].kind == "malice", "consequence malice")

--boon clauses: heal, temporary stamina, surges, recovery value, hero tokens.
--Every one of these has to beat the generic "you gain <qty> <item>" rule.
local boons = EncounterScript.Parse([[
# Montage
## Opportunity: Camp
### Cook a hearty meal
|Cooking Test: Reason
|You fail at the test.
|You heal 6 stamina. Your Recovery Value is increased by 2.
|Each party member heals 6 stamina. Each party member's Recovery Value is increased by 2.
### Receive a blessing
|Blessing Test: Presence
|You gain 5 temporary stamina.
|At the start of the next combat, you gain 2 surges.
|At the start of the next combat you gain 3 surges. +1 hero token.
]])
check(#boons.warnings == 0, "boon clauses are recognized: " .. table.concat(boons.warnings, "; "))
local meal = boons.beats[1].rounds[1].entries[1].options[1].roll.effects
check(meal[2][1].kind == "heal" and meal[2][1].target == "self" and meal[2][1].qty == 6, "you heal 6 stamina")
check(meal[2][2].kind == "recovery" and meal[2][2].target == "self" and meal[2][2].qty == 2, "recovery value +2")
check(meal[3][1].kind == "heal" and meal[3][1].target == "party", "each party member heals")
check(meal[3][2].kind == "recovery" and meal[3][2].target == "party", "each party member's recovery value")
local blessing = boons.beats[1].rounds[1].entries[1].options[2].roll.effects
check(blessing[1][1].kind == "temphp" and blessing[1][1].qty == 5, "5 temporary stamina, not an item")
check(blessing[2][1].kind == "narrative" and not blessing[2][1].unrecognized, "'at the start of the next combat' is recognized")
check(blessing[2][2].kind == "surges" and blessing[2][2].qty == 2, "2 surges after the comma")
check(blessing[3][1].kind == "surges" and blessing[3][1].qty == 3, "3 surges with the lead-in attached")
check(blessing[3][2].kind == "herotoken" and blessing[3][2].qty == 1, "+1 hero token")
--"you lose a recovery": the recovery is gone, with no healing for it
local lost = EncounterScript.ParseEffects(
    "You lose a recovery. You lose two recoveries. Each party member loses a recovery. Each party member loses two recoveries")
check(lost[1].kind == "loserecovery" and lost[1].target == "self" and lost[1].qty == 1, "you lose a recovery")
check(lost[2].kind == "loserecovery" and lost[2].target == "self" and lost[2].qty == 2, "you lose two recoveries")
check(lost[3].kind == "loserecovery" and lost[3].target == "party" and lost[3].qty == 1, "each party member loses a recovery")
check(lost[4].kind == "loserecovery" and lost[4].target == "party" and lost[4].qty == 2, "each party member loses two recoveries")
check(EncounterScript.ParseEffects("You lose 3 recoveries")[1].qty == 3, "digits work for a recovery loss")
check(EncounterScript.DescribeEffect(lost[2]) == "the hero loses 2 recoveries", "recovery loss is described with the irregular plural")
check(EncounterScript.DescribeEffect(lost[3]) == "every hero loses 1 recovery", "party recovery loss description")
--losing stamina and losing recoveries stay apart
check(EncounterScript.ParseEffects("You lose 6 stamina")[1].kind == "stamina", "losing stamina is not a recovery loss")
--the Recovery Value boon is still its own effect
check(EncounterScript.ParseEffects("Your Recovery Value is increased by 2")[1].kind == "recovery", "recovery value boon is not a loss")

--the generic item rule still wins for anything that is not a boon
local item = EncounterScript.Parse("# Montage\n## Opportunity: X\n### y\n|T: Might\n|You gain one Healing Potion\n|You gain 2 Rations\n|You regain 3 stamina\n")
local ie2 = item.beats[1].rounds[1].entries[1].options[1].roll.effects
check(ie2[1][1].kind == "item" and ie2[1][1].name == "Healing Potion", "healing potion is still an item")
check(ie2[2][1].kind == "item" and ie2[2][1].qty == 2 and ie2[2][1].name == "Rations", "rations are still an item")
check(ie2[3][1].kind == "heal" and ie2[3][1].qty == 3, "regain stamina is a heal")
--"you cannot be surprised" must NOT fall into the "^you .*surprised$"
--initiative rule, which would make it mean its own opposite.
local immune = EncounterScript.ParseEffects("+2 hero tokens. You cannot be surprised.")
check(immune[1].kind == "herotoken" and immune[1].qty == 2, "+2 hero tokens (plural)")
check(immune[2].kind == "nosurprise", "you cannot be surprised is immunity, not 'begins surprised'")
check(EncounterScript.ParseEffects("The party cannot be surprised")[1].kind == "nosurprise", "the party cannot be surprised")
check(EncounterScript.ParseEffects("Each party member cannot be surprised")[1].kind == "nosurprise", "each party member cannot be surprised")
check(EncounterScript.ParseEffects("You can't be surprised")[1].kind == "nosurprise", "you can't be surprised")
check(EncounterScript.ParseEffects("You are immune to surprise")[1].kind == "nosurprise", "you are immune to surprise")
local stillSurprised = EncounterScript.ParseEffects("You are surprised")
check(stillSurprised[1].kind == "initiative" and stillSurprised[1].outcome == "surprised", "'you are surprised' still means surprised")
check(string.find(EncounterScript.DescribeEffect(immune[2]), "cannot be surprised", 1, true) ~= nil, "describe surprise immunity")
--a "surprised" outcome announced while the party is already warded
--has to say both halves: the monsters go first, but nobody is
--Surprised. Without the second half the line contradicted the
--immunity the party had just been told it had.
check(EncounterScript.DescribeInitiativeOutcome("surprised") == "The heroes will begin the encounter surprised", "surprised, unwarded")
local warded = EncounterScript.DescribeInitiativeOutcome("surprised", true)
check(string.find(warded, "lose initiative", 1, true) ~= nil, "surprised under immunity still loses initiative")
check(string.find(warded, "cannot be surprised", 1, true) ~= nil, "surprised under immunity says so")
check(EncounterScript.DescribeInitiativeOutcome("surprise", true) == "The heroes will surprise the enemy", "immunity does not touch surprising the enemy")
--"you know the stamina of goblins": monster intelligence reveal by keyword
local know = EncounterScript.ParseEffects("You know the Stamina of Goblins.")
check(know[1].kind == "knowstamina" and know[1].keyword == "goblin", "you know the stamina of goblins -> goblin")
check(EncounterScript.ParseEffects("The party knows the stamina of the goblins")[1].keyword == "goblin", "the party knows ... the goblins")
check(EncounterScript.ParseEffects("Each party member knows the Stamina of every Goblin")[1].keyword == "goblin", "each party member ... every goblin")
check(EncounterScript.ParseEffects("You learn the stamina of all undead")[1].keyword == "undead", "learn ... all undead (no plural strip on -d)")
check(EncounterScript.ParseEffects("You know the stamina of Boss")[1].keyword == "boss", "double-s keyword keeps its s (exact)")
check(EncounterScript.ParseEffects("You know the stamina of the goblin warband")[1].kind == "narrative", "multi-word keyword is narrative")
check(EncounterScript.DescribeEffect(know[1]) == "The party knows the Stamina of Goblins", "describe know stamina")
--"you vanquish the threat" is the active spelling of "the threat is vanquished"
check(EncounterScript.ParseEffects("You vanquish the threat.")[1].kind == "vanquish", "you vanquish the threat")
check(EncounterScript.ParseEffects("You fail to vanquish the threat.")[1].kind == "narrative", "failing to vanquish is narrative")
check(not EncounterScript.ParseEffects("You fail to vanquish the threat.")[1].unrecognized, "failing to vanquish is recognized")

--- narrative beats ----------------------------------------------------------

local NARRATIVE = [==[
# Narrative

[[scene]]

The party sets out at dawn.

## The Crossroads

The road forks at a weathered shrine.

Choose together: Which way do you go?

### Take the high road

The long way, but the safer one.

|+1 hero token

### Take the low road

|+2 malice
|You gain one Healing Potion

## The Shrine

[[scene:shrine]]

Each of you may leave an offering.

Choose individually:

### Offer a coin

|You gain 1 Healing Potion

### Walk on

## A Quiet Mile

Nothing happens for a while.

# Encounter

[[encounter]]
]==]

local nar = EncounterScript.Parse(NARRATIVE)
check(#nar.beats == 2, "narrative script has two beats")
check(nar.beats[1].kind == "narrative", "beat 1 is a narrative")
check(nar.beats[2].kind == "encounter", "beat 2 is the encounter")
check(nar.beats[1].sceneTag == "scene", "narrative beat scene tag")
check(nar.beats[1].intro == "The party sets out at dawn.", "narrative intro")
check(#nar.beats[1].sections == 3, "three sections")

local sec1 = nar.beats[1].sections[1]
check(sec1.name == "The Crossroads", "section 1 name")
check(sec1.id == "s1-the-crossroads", "section 1 id")
check(sec1.mode == "together" and sec1.modeExplicit, "section 1 is an agreed choice")
check(sec1.prompt == "Which way do you go?", "section 1 prompt")
check(sec1.text == "The road forks at a weathered shrine.", "section 1 text")
check(#sec1.options == 2, "section 1 has two options")
check(sec1.options[1].name == "Take the high road", "option 1 name")
check(sec1.options[1].text == "The long way, but the safer one.", "option 1 description")
check(#sec1.options[1].effects == 1 and sec1.options[1].effects[1].kind == "herotoken", "option 1 grants a hero token")
check(sec1.options[1].effects[1].qty == 1, "option 1 grants one hero token")
check(#sec1.options[2].effects == 2, "option 2 has two effect lines")
check(sec1.options[2].effects[1].kind == "malice" and sec1.options[2].effects[1].qty == 2, "option 2 adds malice")
check(sec1.options[2].effects[2].kind == "item" and sec1.options[2].effects[2].name == "Healing Potion", "option 2 grants a potion")

local sec2 = nar.beats[1].sections[2]
check(sec2.mode == "individual" and sec2.modeExplicit, "section 2 is an individual choice")
check(sec2.sceneTag == "scene:shrine", "section 2 has its own scene")
check(nar.beats[1].sceneTag == "scene", "a section scene does not overwrite the beat's")
check(sec2.prompt == "", "section 2 has no prompt text")
check(#sec2.options == 2 and #sec2.options[2].effects == 0, "a bare option has no effects")

local sec3 = nar.beats[1].sections[3]
check(sec3.implicitOption and #sec3.options == 1, "a section with no options gets an implicit one")
check(sec3.options[1].name == "Proceed" and sec3.options[1].implicit, "the implicit option is Proceed")
check(sec3.mode == "together", "sections default to choosing together")

--an options block with no marker warns but still parses as "together"
local unmarked = EncounterScript.Parse("# Narrative\n## X\ntext\n### a\n### b\n")
check(unmarked.beats[1].sections[1].mode == "together", "unmarked multi-option section defaults to together")
check(not unmarked.beats[1].sections[1].modeExplicit, "unmarked section is not explicit")
local warned = false
for _, w in ipairs(unmarked.warnings) do
    if string.find(w, "Choose together", 1, true) ~= nil then
        warned = true
    end
end
check(warned, "unmarked multi-option section warns")

--alternate spellings of the two markers
local spellings = {
    ["Choose as a group:"] = "together",
    ["The party must agree:"] = "together",
    ["Decide together:"] = "together",
    ["Choose individually:"] = "individual",
    ["Each hero chooses:"] = "individual",
    ["Choose separately:"] = "individual",
    ["Each of you decides:"] = "individual",
}
for marker, mode in pairs(spellings) do
    local parse = EncounterScript.Parse("# Narrative\n## X\n" .. marker .. "\n### a\n### b\n")
    check(parse.beats[1].sections[1].mode == mode, marker .. " -> " .. mode)
end

--a bare "Options:" sets the prompt without changing the mode
local bare = EncounterScript.Parse("# Narrative\n## X\nOptions: pick one\n### a\n|+1 hero token\n### b\n")
check(bare.beats[1].sections[1].prompt == "pick one", "Options: sets the prompt")
check(not bare.beats[1].sections[1].modeExplicit, "Options: does not set the mode")

--the initiative and boon clauses work in a narrative option too
local boon = EncounterScript.Parse("# Narrative\n## X\nChoose together:\n### a\n|Each party member gains 5 temporary stamina. You win initiative.\n")
local beffects = boon.beats[1].sections[1].options[1].effects
check(beffects[1].kind == "temphp" and beffects[1].target == "party", "narrative party temp stamina")
check(beffects[2].kind == "initiative" and beffects[2].outcome == "win", "narrative initiative clause")

--an orphaned "|" line in a narrative warns instead of being read as a roll
local orphan = EncounterScript.Parse("# Narrative\n## X\n|+1 hero token\n")
check(#orphan.beats[1].sections[1].options == 1, "orphan effect line leaves the implicit option")
local orphanWarned = false
for _, w in ipairs(orphan.warnings) do
    if string.find(w, "### option", 1, true) ~= nil then
        orphanWarned = true
    end
end
check(orphanWarned, "orphan effect line warns")

--narrative names are collected for validation
local items, monsters = EncounterScript.ReferencedNames(nar)
check(items["Healing Potion"], "narrative item names are referenced")
check(next(monsters) == nil, "no monsters in the narrative sample")

--describe dumps sections
local described = EncounterScript.Describe(nar)
check(string.find(described, "section: The Crossroads", 1, true) ~= nil, "describe lists sections")
check(string.find(described, "the party gains 1 hero token", 1, true) ~= nil, "describe lists narrative effects")

--"teaser => full text" tier lines: players see the teaser until the tier
--lands; only the full text is parsed for effects.
local teased = EncounterScript.Parse([[
# Montage

## Opportunity: Hunter's Camp

An abandoned camp.

### Track the Goblins

|Tracking Test: Intuition (Track, Nature, Alertness)
|You fail at the test.
|A little wisdom => You learn some of the hunter's wisdom; +1 hero token.
|A wealth of wisdom=>+1 hero token. You know the Stamina of Goblins => really.
|=> A critical with an empty teaser, +2 hero tokens
]])
local track = teased.beats[1].rounds[1].entries[1].options[1].roll
check(track.teasers[1] == nil and track.tiers[1] == "You fail at the test.", "tier 1: no teaser")
check(track.teasers[2] == "A little wisdom", "tier 2 teaser")
check(track.tiers[2] == "You learn some of the hunter's wisdom; +1 hero token.", "tier 2 full text")
check(track.effects[2][2].kind == "herotoken" and track.effects[2][2].qty == 1, "tier 2 effects parsed from the full text only")
check(track.teasers[3] == "A wealth of wisdom", "tier 3 teaser, no spaces around =>")
check(track.tiers[3] == "+1 hero token. You know the Stamina of Goblins => really.", "first => splits; later ones are text")
check(track.teasers[4] == nil and track.tiers[4] == "A critical with an empty teaser, +2 hero tokens", "empty teaser dropped")
check(track.effects[4][2].kind == "herotoken" and track.effects[4][2].qty == 2, "tier 4 effects")
local sawEmptyTeaser = false
for _, w in ipairs(teased.warnings) do
    if string.find(w, "empty teaser", 1, true) then sawEmptyTeaser = true end
end
check(sawEmptyTeaser, "empty teaser warned")
check(EncounterScript.TierDisplayText(track, 2, false) == "A little wisdom", "display: teaser before landing")
check(EncounterScript.TierDisplayText(track, 2, true) == track.tiers[2], "display: full text once landed")
check(EncounterScript.TierDisplayText(track, 1, false) == track.tiers[1], "display: no teaser = full text")
check(EncounterScript.TierDisplayText({ tiers = { "a", "b", "c" } }, 2, false) == "b", "display: roll with no teasers table")
local t0, f0 = EncounterScript.SplitTeaser("plain line")
check(t0 == nil and f0 == "plain line", "SplitTeaser: no =>")

--the option card hides the skill list; only the characteristic(s) show
check(EncounterScript.AttrWithoutSkills("Presence (Empathize, Lie, Flirt, Persuade)") == "Presence", "skills stripped")
check(EncounterScript.AttrWithoutSkills("Might or Agility (Endurance, Track)") == "Might or Agility", "two characteristics kept")
check(EncounterScript.AttrWithoutSkills("Reason") == "Reason", "no skills = unchanged")

--- highlighting the recognized rules in a tier line -------------------------

--the clause offsets point at the clause inside the untouched line
local spans = EncounterScript.ParseEffectSpans("You slip past them! You gain 2 surges, and nothing else")
check(#spans == 3, "three clauses")
check(spans[1].effect.kind == "narrative" and spans[1].effect.unrecognized, "flavour is unrecognized")
check(spans[2].effect.kind == "surges", "the mechanical clause parses")
local line = "You slip past them! You gain 2 surges, and nothing else"
check(string.sub(line, spans[2].from, spans[2].to) == "You gain 2 surges", "span offsets bracket the clause exactly")
check(string.sub(line, spans[3].from, spans[3].to) == "and nothing else", "the trailing clause needs no terminator")

--only the mechanical clauses are wrapped; punctuation and flavour are left alone
local marked = EncounterScript.MarkupRules(line, "<b>", "</b>")
check(marked == "You slip past them! <b>You gain 2 surges</b>, and nothing else", "markup wraps only the recognized clause")
check(EncounterScript.MarkupRules("You fail at the test.", "<b>", "</b>") == "You fail at the test.", "recognized flavour is not marked")
check(EncounterScript.MarkupRules("Nothing here matches", "<b>", "</b>") == "Nothing here matches", "unrecognized text is not marked")
check(EncounterScript.MarkupRules("You gain 2 surges", nil, nil) == "You gain 2 surges", "no tags = text unchanged")
check(EncounterScript.MarkupRules(nil, "<b>", "</b>") == "", "nil text is empty")
local two = EncounterScript.MarkupRules("You lose 6 Stamina. Each party member gains one Healing Potion.", "[", "]")
check(two == "[You lose 6 Stamina]. [Each party member gains one Healing Potion].", "every mechanical clause is marked")
check(EncounterScript.EffectIsMechanical(spans[2].effect) and not EncounterScript.EffectIsMechanical(spans[1].effect), "EffectIsMechanical")

--montage parsing is untouched by the narrative branch
check(EncounterScript.SectionCount(nar.beats[1]) == 3, "SectionCount")
check(EncounterScript.FindSection(nar.beats[1], "s2-the-shrine") == sec2, "FindSection")

--- riders: requirements that gate or modify a test ------------------------

local RIDERS = table.concat({
    "# Montage", "## Round 1", "## Opportunity: Cottage", "Options: x", "### Consult her on the arcane",
    "|Arcana Test: Reason (Magic, Alchemy)", "|You fail.", "|You gain one Healing Potion", "|Each party member gains one Healing Potion",
    "|Allow: You are skilled in Magic, Alchemy or Psionics, or you are an Elementalist",
    "|Edge: You speak Caelian", "|Double Bane: You are a Dwarf", "|Requires: frobnicate", "|Edge:",
    "### Plain", "|Plain Test: Might", "|a", "|b", "|c", "|d", "|Edge: you are a Polder",
    "# Encounter", "[[encounter]]" }, "\n")
local rp = EncounterScript.Parse(RIDERS)
local arcane = rp.beats[1].rounds[1].entries[1].options[1].roll
check(#arcane.tiers == 3 and #arcane.riders == 4, "riders are not tiers: 3 tiers, 4 riders")
check(arcane.riders[1].effect == "allow" and arcane.riders[2].effect == "edge" and arcane.riders[3].effect == "doublebane" and arcane.riders[4].effect == "allow", "rider effects, Requires = Allow")
local alts = arcane.riders[1].requirement.alternatives
check(#alts == 4 and alts[1].kind == "skill" and alts[1].name == "magic" and alts[2].name == "alchemy" and alts[3].name == "psionics", "comma list inherits the skill kind")
check(alts[4].kind == "kindred" and alts[4].name == "elementalist", "', or you are an X' is a kindred clause")
check(arcane.riders[2].requirement.alternatives[1].kind == "language" and arcane.riders[2].requirement.alternatives[1].name == "caelian", "you speak X")
check(arcane.riders[4].requirement.unrecognized and arcane.riders[4].requirement.alternatives[1].kind == "unknown", "unknown clause flagged")
local sawUnknown, sawEmpty = false, false
for _, w in ipairs(rp.warnings) do
    if string.find(w, "frobnicate", 1, true) then sawUnknown = true end
    if string.find(w, "no requirement", 1, true) then sawEmpty = true end
end
check(sawUnknown and sawEmpty, "unknown and empty riders warn")
local plain = rp.beats[1].rounds[1].entries[1].options[2].roll
check(#plain.tiers == 4 and #plain.riders == 1, "a rider after a 4th tier still parses")

check(EncounterScript.NormalizeName("Elf, High") == "high elf", "compendium 'Elf, High' normalizes to 'high elf'")
check(EncounterScript.ParseRiderLine("You succeed: something") == nil, "a tier line with a colon is not a rider")

local mage = { skill = { magic = true }, language = { caelian = true }, kindred = { ["high elf"] = true } }
local v = EncounterScript.EvaluateRiders(arcane.riders, mage)
check(v.gated and not v.allowed, "the unknown Requires line is never met, so the roll is locked")
check(v.unlockedBy == "You are skilled in Magic" and v.boons == 1 and v.banes == 0 and #v.applied == 1, "edge applied with its reason")
local v2 = EncounterScript.EvaluateRiders({ arcane.riders[1], arcane.riders[2], arcane.riders[3] }, mage)
check(v2.allowed and v2.unlockedBy == "You are skilled in Magic" and #v2.unmet == 1, "allowed once the bad line is gone; the Dwarf bane is unmet")
local dwarf = EncounterScript.EvaluateRiders({ arcane.riders[1], arcane.riders[3] }, { skill = {}, language = {}, kindred = { dwarf = true } })
check(not dwarf.allowed and dwarf.banes == 2 and dwarf.boons == 0, "a Dwarf with no magic: locked, double bane")
local elementalist = EncounterScript.EvaluateRiders({ arcane.riders[1] }, { kindred = { elementalist = true } })
check(elementalist.allowed and elementalist.unlockedBy == "you are an Elementalist", "an Elementalist unlocks by class")
local free = EncounterScript.EvaluateRiders({}, {})
check(free.allowed and not free.gated and free.boons == 0, "no riders = allowed")
check(EncounterScript.RequirementMet(EncounterScript.ParseRequirement("you are an Elf"), { kindred = { ["high elf"] = true } }), "a fact ending in the wanted name counts")
check(not EncounterScript.RequirementMet(EncounterScript.ParseRequirement("you are skilled in Magic"), { skill = { magician = true } }), "no substring match")
check(EncounterScript.RiderLabel("doubleedge") == "Double Edge" and EncounterScript.RiderBoons("doublebane") == -2, "labels and boons")

--the sample script has no riders and parses exactly as before
check(#negotiate.roll.riders == 0, "a roll without riders has an empty riders list")

--- traps: encounter setup instructions + zone reveals ----------------------

local TRAPS = table.concat({
    "# Montage", "## Round 1", "## Opportunity: Watchtower", "Options: x", "### Scout ahead",
    "|Scouting Test: Intuition (Alertness)", "|You fail.", "|You spot some tracks.", "|Reveal Traps during the next combat.",
    "# Encounter", "Some notes for the author.",
    "Trap: Place 4 Snare Trap objects in Trap zones and delete other Trap zones.",
    "Pit: Place one Pit object in the Pit zones",
    "Rubble: Place two Rubble Pile objects in Rubble zones and remove the remaining Rubble zones.",
    "Bogus: Do something else entirely.",
    "[[encounter]]" }, "\n")
local tp = EncounterScript.Parse(TRAPS)
local enc = tp.beats[2]
check(enc.kind == "encounter" and #enc.setup == 4, "four setup instructions under # Encounter")
local trap = enc.setup[1]
check(trap.kind == "placeobjects" and trap.label == "Trap" and trap.qty == 4 and trap.object == "Snare Trap" and trap.zone == "trap" and trap.deleteOthers, "Trap: place 4 Snare Trap objects ... and delete other Trap zones")
check(enc.setup[2].kind == "placeobjects" and enc.setup[2].qty == 1 and enc.setup[2].object == "Pit" and enc.setup[2].zone == "pit" and not enc.setup[2].deleteOthers, "Place one Pit object in the Pit zones (no delete)")
check(enc.setup[3].kind == "placeobjects" and enc.setup[3].qty == 2 and enc.setup[3].object == "Rubble Pile" and enc.setup[3].zone == "rubble" and enc.setup[3].deleteOthers, "remove the remaining X zones = delete")
check(enc.setup[4].kind == "unknown" and enc.setup[4].label == "Bogus", "an unknown instruction is kept as unknown")
local sawBogus = false
for _, w in ipairs(tp.warnings) do
    if string.find(w, "Bogus", 1, true) then sawBogus = true end
end
check(sawBogus, "an unknown setup instruction warns")
check(EncounterScript.ParseSetupInstruction("Place 4 Snare Trap objects in Trap zones and delete other Pit zones") == nil, "delete clause naming a different zone is rejected")
check(EncounterScript.ParseSetupInstruction("Place lots of things") == nil, "no quantity = not an instruction")
local reveal = tp.beats[1].rounds[1].entries[1].options[1].roll.effects[3]
check(reveal[1].kind == "revealzones" and reveal[1].zone == "trap", "Reveal Traps during the next combat -> trap")
check(EncounterScript.ParseEffects("Reveal the trap zones")[1].zone == "trap", "reveal the trap zones")
check(EncounterScript.ParseEffects("Reveal traps")[1].zone == "trap", "reveal traps")
check(EncounterScript.ParseEffects("The traps are revealed during the next encounter")[1].zone == "trap", "the traps are revealed ...")
check(EncounterScript.ParseEffects("Reveal all Pits in the next combat")[1].zone == "pit", "reveal all pits in the next combat")
check(EncounterScript.ParseEffects("Reveal the secret passage")[1].kind == "narrative", "a multi-word reveal is narrative")
check(EncounterScript.DescribeEffect(reveal[1]) == "The Traps will be revealed during the next combat", "describe reveal")
check(EncounterScript.EffectIsMechanical(reveal[1]), "reveal is mechanical")
check(string.find(EncounterScript.Describe(tp), "setup Trap: place 4 x 'Snare Trap' in trap zones, delete the other trap zones", 1, true) ~= nil, "dump lists setup")
check(#EncounterScript.Parse("[[encounter]]").beats[1].setup == 0, "implicit encounter has an empty setup list")

--- party-size scaling and "(Required)" ------------------------------------

local SCALING = [==[
# Montage

The party crosses the moor.

## Round 1
3-5 Players: -1 Opportunity, -1 Threat
3 Players: -1 Threat

## Opportunity: Hunter's Camp (Required)

### Search it
|Search: Might
|You lose 1 stamina
|You gain a Rope
|You gain two Ropes

## Opportunity: Standing Stones

### Read them
|Read: Reason
|You fail the test
|You gain 1 hero token
|You gain 2 hero tokens

## Threat: Mire

Consequence: You lose 2 stamina

### Wade
|Wade: Might
|You lose 1 stamina
|You gain a Rope
|You gain two Ropes

## Threat: Fog

Consequence: You lose the initiative

### Wait
|Wait: Reason
|You fail the test
|You gain 1 hero token
|You gain 2 hero tokens

## Round 2
6+ Heroes: -1 Opportunity

## Opportunity: Ford

### Cross
|Cross: Agility
|You fail the test
|You gain 1 hero token
|You gain 2 hero tokens
]==]

local sp = EncounterScript.Parse(SCALING)
local sb = sp.beats[1]
check(#sb.rounds[1].scaling == 2, "two party-size directives on round 1")
check(sb.intro == "The party crosses the moor.", "a directive is not montage intro prose")
check(sb.rounds[1].entries[1].required and sb.rounds[1].entries[1].name == "Hunter's Camp", "(Required) sets the flag and leaves the name")
check(sb.rounds[1].entries[2].required == false, "an untagged entry is not required")

local rem = EncounterScript.ScalingRemovals(sb.rounds[1], 3)
check(rem.opportunity == 1 and rem.threat == 2, "matching directives stack for a party of 3")
check(EncounterScript.ScalingRemovals(sb.rounds[1], 5).threat == 1, "only the range directive covers a party of 5")
check(next(EncounterScript.ScalingRemovals(sb.rounds[1], 6)) == nil, "a party of 6 is outside 3-5")
check(EncounterScript.ScalingRemovals(sb.rounds[2], 99).opportunity == 1, "6+ is open-ended")

--a deterministic draw: always the first of the pool
local first = function(n) return 1 end
local removed = EncounterScript.ChooseRemovedEntries(sb, 3, first)
check(removed["r1-opportunity-hunter-s-camp"] == nil, "(Required) is never drawn")
check(removed["r1-opportunity-standing-stones"] == true, "the removable opportunity is drawn instead")
check(removed["r1-threat-mire"] and removed["r1-threat-fog"], "two threats asked for, two threats drawn")
check(removed["r2-opportunity-ford"] == nil, "a round-1 directive does not reach round 2")
check(EncounterScript.ChooseRemovedEntries(sb, 7, first)["r2-opportunity-ford"] == true, "a round-2 directive draws from round 2")
check(next(EncounterScript.ChooseRemovedEntries(sb, 2, first)) == nil, "a party outside every range loses nothing")
check(EncounterScript.HasScaling(sb) and EncounterScript.RoundHasScaling(sb, 2), "HasScaling / RoundHasScaling")
check(not EncounterScript.HasScaling(EncounterScript.Parse(SAMPLE).beats[1]), "a montage with no directives has no scaling")

check(EncounterScript.ParseScalingDirective("4+ Players: -1 Threat").max == nil, "N+ is open-ended")
check(EncounterScript.ParseScalingDirective("3 Players: -2 Opportunities").removals.opportunity == 2, "plural kind")
check(EncounterScript.ParseScalingDirective("3-5 players: -one opportunity").removals.opportunity == 1, "a spelled-out quantity")
check(EncounterScript.ParseScalingDirective("3-5 Players: +1 Opportunity") == nil, "a directive never ADDS")
check(EncounterScript.ParseScalingDirective("5-3 Players: -1 Threat") == nil, "a backwards range is rejected")
check(EncounterScript.ParseScalingDirective("Options: approach the fire") == nil, "an Options: paragraph is not a directive")
check(EncounterScript.IsScalingDirectiveLine("3-5 Players: nonsense") and EncounterScript.ParseScalingDirective("3-5 Players: nonsense") == nil, "a malformed directive is recognized and rejected")

local overdraw = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "3 Players: -2 Threats", "",
    "## Threat: Mire", "", "Consequence: You lose 2 stamina", "",
    "### Wade", "|Wade: Might", "|You lose 1 stamina", "|You gain a Rope", "|You gain two Ropes" }, "\n"))
local sawOverdraw = false
for _, w in ipairs(overdraw.warnings) do
    if string.find(w, "introduces only 1", 1, true) then sawOverdraw = true end
end
check(sawOverdraw, "asking for more than the round has warns")
check(EncounterScript.ChooseRemovedEntries(overdraw.beats[1], 3, first)["r1-threat-mire"] == true, "and drops everything it can")
check(string.find(EncounterScript.Describe(sp), "scaling: 3-5 players -> -1 opportunity, -1 threat", 1, true) ~= nil, "dump lists the directives")
check(string.find(EncounterScript.Describe(sp), "Hunter's Camp (required)", 1, true) ~= nil, "dump marks required entries")

--- locked entries and "Unlock <name>" -------------------------------------

local LOCKED = table.concat({
    "# Montage", "",
    "## Round 1", "",
    "## Opportunity: Capture the Goblin", "",
    "A goblin scout blunders into you.", "",
    "### Grab it", "",
    "|Grab Test: Might (Grapple)",
    "|You fail at the test",
    "|You gain a Rope. {Unlock Interrogate the Goblin}",
    "|You gain a Rope, {Unlock Interrogate the Goblin}, and it squeals!", "",
    "## Opportunity: Interrogate the Goblin (Locked)", "",
    "The goblin, trussed up, eyes you sullenly.", "",
    "### Question it", "",
    "|Interrogation Test: Presence (Interrogate)",
    "|You fail at the test",
    "|+1 malice",
    "|You gain two Healing Potions. {Unlock the Pact}", "",
    "## Round 2", "",
    "## Threat: The Pact (Required, Locked)", "",
    "Consequence: Each party member loses 3 stamina", "",
    "### Break it", "",
    "|Ritual Test: Reason (Magic)",
    "|You fail at the test",
    "|The threat is vanquished",
    "|The threat is vanquished",
}, string.char(10))

local lk = EncounterScript.Parse(LOCKED)
local lkb = lk.beats[1]
local capture = lkb.rounds[1].entries[1]
local interrogate = lkb.rounds[1].entries[2]
local pact = lkb.rounds[2].entries[1]
check(interrogate.name == "Interrogate the Goblin" and interrogate.locked == true, "(Locked) sets the flag and leaves the name")
check(capture.locked == false, "an untagged entry is not locked")
check(pact.name == "The Pact" and pact.locked == true and pact.required == true, "(Required, Locked) sets both and leaves the name")

local unlockEffects = capture.options[1].roll.effects[2]
check(#unlockEffects == 2, "'You gain a Rope. {Unlock ...}' is two clauses")
check(unlockEffects[1].kind == "item" and unlockEffects[1].hidden == nil, "the visible clause is not hidden")
check(unlockEffects[2].kind == "unlock" and unlockEffects[2].hidden == true, "the braced clause is an unlock, hidden")
check(unlockEffects[2].name == "Interrogate the Goblin", "the unlock keeps the name as written")
check(unlockEffects[2].key == EncounterScript.MatchKey(interrogate.name), "the unlock key matches the locked entry")
check(EncounterScript.TierDisplayText(capture.options[1].roll, 2, true) == "You gain a Rope.", "a hidden clause is not shown")
check(EncounterScript.TierDisplayText(capture.options[1].roll, 3, true) == "You gain a Rope, and it squeals!", "a hidden clause mid-line leaves no stranded comma")
check(string.find(EncounterScript.MarkupRules(capture.options[1].roll.tiers[2], "<b>", "</b>"), "{", 1, true) == nil, "markup never shows a brace")
for _, w in ipairs(lk.warnings) do
    check(string.find(w, "Locked", 1, true) == nil and string.find(w, "unlock", 1, true) == nil,
        "a well-formed locked montage raises no lock warnings (got: " .. w .. ")")
end

check(EncounterScript.MatchKey("  The   Old Mill.  ") == "old mill", "the entry key drops 'the', case, spacing and punctuation")
check(EncounterScript.ParseUnlockClause("Unlocks the Old Mill") == "the Old Mill", "'Unlocks <name>' is an unlock")
check(EncounterScript.ParseUnlockClause("you unlock The Old Mill") == "The Old Mill", "'you unlock <name>' is an unlock")
check(EncounterScript.ParseUnlockClause("the party unlocks The Old Mill") == "The Old Mill", "'the party unlocks <name>' is an unlock")
check(EncounterScript.ParseUnlockClause("You unlock") == nil, "'You unlock' with no name is not an unlock")
check(EncounterScript.ParseUnlockClause("You gain a Rope") == nil, "an ordinary clause is not an unlock")

check(EncounterScript.VisibleText("You gain a Rope") == "You gain a Rope", "an unbraced line is untouched")
check(EncounterScript.VisibleText("{Unlock the Old Mill}") == "", "a wholly hidden line shows nothing")
check(EncounterScript.VisibleText("{Unlock the Old Mill}. You gain a Rope") == "You gain a Rope", "a leading hidden clause leaves no stranded separator")
check(EncounterScript.VisibleText("You gain a Rope. {Unlock the Old Mill") == "You gain a Rope.", "an unterminated brace hides the rest of the line")
local unterminated = EncounterScript.ParseEffects("You gain a Rope. {Unlock the Old Mill")
check(#unterminated == 2 and unterminated[2].kind == "unlock" and unterminated[2].hidden == true, "and still applies what is inside it")

--the draw never touches a locked entry, so an "Unlock" outcome cannot
--point at a card that was quietly removed.
local lockScaled = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "3 Players: -1 Opportunity", "",
    "## Opportunity: Interrogate the Goblin (Locked)", "",
    "### Question it", "|Ask: Presence", "|You fail at the test", "|+1 malice", "|+2 malice", "",
    "## Opportunity: Mysterious Cottage", "",
    "### Knock", "|Knock: Presence", "|You fail at the test", "|+1 malice", "|+2 malice",
}, string.char(10)))
local lockDrawn = EncounterScript.ChooseRemovedEntries(lockScaled.beats[1], 3, first)
check(lockDrawn["r1-opportunity-interrogate-the-goblin"] == nil, "(Locked) is never drawn by a party-size directive")
check(lockDrawn["r1-opportunity-mysterious-cottage"] == true, "the unlocked entry is the one that goes")
check(string.find(EncounterScript.Describe(lk), "Interrogate the Goblin (locked)", 1, true) ~= nil, "dump marks locked entries")
check(string.find(EncounterScript.Describe(lk), "The Pact (required) (locked)", 1, true) ~= nil, "dump marks both tags")

local badUnlock = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "",
    "## Opportunity: Capture the Goblin", "",
    "### Grab it", "|Grab: Might", "|You fail at the test", "|+1 malice", "|{Unlock Nobody At All}",
}, string.char(10)))
local sawBadUnlock, sawOrphanLock = false, false
for _, w in ipairs(badUnlock.warnings) do
    if string.find(w, "names no '(Locked)'", 1, true) then sawBadUnlock = true end
end
check(sawBadUnlock, "an unlock that names nothing warns")
local orphanLock = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "",
    "## Opportunity: Interrogate the Goblin (Locked)", "",
    "### Question it", "|Ask: Presence", "|You fail at the test", "|+1 malice", "|+2 malice",
}, string.char(10)))
for _, w in ipairs(orphanLock.warnings) do
    if string.find(w, "is (Locked) but nothing unlocks it", 1, true) then sawOrphanLock = true end
end
check(sawOrphanLock, "a locked entry nothing unlocks warns")

--- standing edges and banes: "Edge on <option>" -----------------------------

local function ModOf(text)
    return EncounterScript.ParseEffects(text)[1]
end
check(ModOf("Edge on Capture Them").kind == "testmod", "'Edge on X' is a test modifier")
check(ModOf("Edge on Capture Them").effect == "edge", "and carries the rider effect")
check(ModOf("Edge on Capture Them").name == "Capture Them", "and the option name as written")
check(ModOf("Edge on Capture Them").key == EncounterScript.MatchKey("capture them"), "and its match key")
check(ModOf("Double Edge on Capture Them").effect == "doubleedge", "'Double Edge on X'")
check(ModOf("Bane on Capture Them").effect == "bane", "'Bane on X'")
check(ModOf("Double Bane on Capture Them").effect == "doublebane", "'Double Bane on X'")
check(ModOf("you gain an edge on Capture Them").effect == "edge", "'you gain an edge on X'")
check(ModOf("The party has a bane on Capture Them").effect == "bane", "'the party has a bane on X'")
check(ModOf("Each party member gains a double edge on Capture Them").effect == "doubleedge", "'each party member gains ...'")
check(ModOf("you gain an edge on Capture Them").name == "Capture Them", "a lead-in does not eat the name")
check(ModOf("You gain a Rope").kind == "item", "an ordinary grant is still an item")
check(ModOf("Edge on").kind == "narrative", "'Edge on' with no name is not a modifier")
check(ModOf("You have the edge").kind == "narrative", "flavour about an edge is not a modifier")
check(EncounterScript.DescribeTestMod("edge", "Capture Them") == "The party has an edge on Capture Them", "the applied line reads naturally")
check(EncounterScript.DescribeTestMod("bane", "Capture Them") == "The party has a bane on Capture Them", "and picks the right article")
check(EncounterScript.DescribeTestMod("doubleedge", "Capture Them") == "The party has a double edge on Capture Them", "and for a double edge")

local MODDED = table.concat({
    "# Montage", "",
    "## Round 1", "",
    "## Opportunity: Goblin Scouts", "",
    "### Spot Them", "",
    "|Watch Test: Intuition (Alertness)",
    "|You fail at the test",
    "|+1 malice. {Edge on Capture Them}",
    "|{Double Edge on Capture Them}", "",
    "## Opportunity: Capture the Goblin", "",
    "### Capture Them", "",
    "|Hunting Test: Agility or Intuition (Track, Alertness)",
    "|You scare them off",
    "|You capture them with a consequence",
    "|You capture them",
}, string.char(10))

local mod = EncounterScript.Parse(MODDED)
local spot = mod.beats[1].rounds[1].entries[1].options[1]
check(spot.roll.effects[2][2].kind == "testmod" and spot.roll.effects[2][2].hidden == true, "a braced modifier is hidden like any clause")
check(EncounterScript.TierDisplayText(spot.roll, 2, true) == "+1 malice.", "and is not shown")
check(EncounterScript.TierDisplayText(spot.roll, 3, true) == "", "a wholly hidden tier shows nothing")
for _, w in ipairs(mod.warnings) do
    check(string.find(w, "### option", 1, true) == nil, "a modifier naming a real option raises no warning (got: " .. w .. ")")
end

local badMod = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "",
    "## Opportunity: Goblin Scouts", "",
    "### Spot Them", "|Watch: Intuition", "|You fail at the test", "|+1 malice", "|Edge on Nothing At All",
}, string.char(10)))
local sawBadMod = false
for _, w in ipairs(badMod.warnings) do
    if string.find(w, "names no '### option'", 1, true) then sawBadMod = true end
end
check(sawBadMod, "a modifier that names no option warns")

--- "a fair roll": taking back an unfavourable initiative --------------------

local function KindOf(text)
    return EncounterScript.ParseEffects(text)[1].kind
end
for _, text in ipairs({
    "The encounter begins with a fair roll",
    "The encounter begins with a fair roll for initiative",
    "Combat starts with a fair roll",
    "A fair roll for initiative",
    "Initiative is rolled normally",
    "You roll for initiative normally",
    "The party rolls for initiative",
    "You are no longer surprised",
    "The party is no longer surprised",
    "You begin the encounter on even footing",
    "You start the next encounter on even terms",
}) do
    check(KindOf(text) == "fairinitiative", "'" .. text .. "' is a fair roll")
end
--the clauses it must NOT swallow: they read as their own opposite under
--the "^you .*surprised$" rules it is matched in front of.
check(KindOf("You cannot be surprised") == "nosurprise", "surprise immunity is untouched")
check(KindOf("You are not surprised") == "nosurprise", "and its 'are not' spelling")
check(EncounterScript.ParseEffects("You begin the encounter surprised")[1].outcome == "surprised", "being surprised is untouched")
check(EncounterScript.ParseEffects("You surprise the enemy")[1].outcome == "surprise", "surprising the enemy is untouched")
check(EncounterScript.ParseEffects("You win initiative")[1].outcome == "win", "winning initiative is untouched")
check(EncounterScript.ParseEffects("You lose the initiative")[1].outcome == "lose", "losing initiative is untouched")
check(KindOf("A fair roll of the dice was all it took") == "narrative", "prose about a fair roll is not the clause")
check(EncounterScript.DescribeEffect(EncounterScript.ParseEffects("The encounter begins with a fair roll")[1])
    == "The encounter begins with a fair roll for initiative", "the dump describes it")

--- "(Temporary)" entries ---------------------------------------------------

local TEMPORARY = table.concat({
    "# Montage", "",
    "## Round 1", "",
    "## Threat: Goblin Scouts (Temporary)", "",
    "They will raise the alarm if you let them go.", "",
    "Consequence: Each party member loses 3 stamina", "",
    "### Run Them Down", "",
    "|Chase Test: Might (Endurance)",
    "|You fail at the test",
    "|The threat is vanquished",
    "|The threat is vanquished", "",
    "## Opportunity: A Moment's Rest (Required, Temporary)", "",
    "### Breathe", "",
    "|Rest Test: Might (Endurance)",
    "|You fail at the test",
    "|You heal 3 stamina",
    "|You heal 6 stamina", "",
    "## Threat: The Long Road", "",
    "Consequence: Each party member loses 1 stamina", "",
    "### Walk It", "",
    "|Travel Test: Might (Endurance)",
    "|You fail at the test",
    "|The threat is vanquished",
    "|The threat is vanquished",
}, string.char(10))

local tmp = EncounterScript.Parse(TEMPORARY)
local scouts = tmp.beats[1].rounds[1].entries[1]
local rest = tmp.beats[1].rounds[1].entries[2]
local road = tmp.beats[1].rounds[1].entries[3]
check(scouts.temporary == true and scouts.name == "Goblin Scouts", "(Temporary) sets the flag and leaves the name")
check(rest.temporary == true and rest.required == true and rest.name == "A Moment's Rest", "(Required, Temporary) sets both")
check(rest.locked == false, "and leaves the tag it was not given alone")
check(road.temporary == false, "an untagged entry is not temporary")
check(#tmp.warnings == 0, "a well-formed temporary montage parses clean")
check(string.find(EncounterScript.Describe(tmp), "Goblin Scouts (temporary)", 1, true) ~= nil, "dump marks temporary entries")
check(string.find(EncounterScript.Describe(tmp), "A Moment's Rest (required) (temporary)", 1, true) ~= nil, "dump marks both tags")

--every combination of the three tags, in any order, off one heading
local combos = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "",
    "## Threat: The Pact (Temporary, Locked, Required)", "",
    "Consequence: You lose 1 stamina", "",
    "### Break It", "|Ritual: Reason", "|You fail at the test", "|The threat is vanquished", "|The threat is vanquished",
}, string.char(10)))
local pact = combos.beats[1].rounds[1].entries[1]
check(pact.name == "The Pact", "three tags in one parenthesis all come off the name")
check(pact.temporary and pact.locked and pact.required, "and all three are set")

local notATag = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "",
    "## Opportunity: The Cottage (Abandoned)", "",
    "### Knock", "|Knock: Presence", "|You fail at the test", "|+1 malice", "|+2 malice",
}, string.char(10)))
check(notATag.beats[1].rounds[1].entries[1].name == "The Cottage (Abandoned)", "a parenthesis that is not a tag stays in the name")


--- feature unlocks: "Unlock: Intelligence" in a narrative beat --------------

local intel = EncounterScript.Parse(table.concat({
    "# Narrative", "",
    "Unlock: Intelligence", "",
    "## The Briefing", "",
    "You study the ground.", "",
    "### Press on", "",
    "|+1 Intelligence", "",
    "## The Scouting", "",
    "Unlock: intelligence", "",
    "### Look closer", "",
    "|You gain two intelligence",
}, string.char(10)))
local nbeat = intel.beats[1]
check(#intel.warnings == 0, "a narrative beat with an Unlock: line parses clean: " .. table.concat(intel.warnings, "; "))
check(#(nbeat.unlocks or {}) == 1, "an Unlock: line above the first section is the beat's")
check(nbeat.unlocks[1].feature == "intelligence", "and names the feature by key")
check(nbeat.unlocks[1].name == "Intelligence", "with the feature's own spelling, not the author's")
check(#(nbeat.sections[1].unlocks or {}) == 0, "a beat-level unlock is not also the first section's")
check(#(nbeat.sections[2].unlocks or {}) == 1, "an Unlock: line inside a section is that section's")
check(nbeat.sections[1].text == "You study the ground.", "the Unlock: line is not left in the prose")
check(EncounterScript.UnlockedFeatures(intel).intelligence == true, "UnlockedFeatures reports it")

local effect1 = nbeat.sections[1].options[1].effects[1]
check(effect1.kind == "intelligence" and effect1.qty == 1, "'+1 Intelligence' is an intelligence clause")
local effect2 = nbeat.sections[2].options[1].effects[1]
check(effect2.kind == "intelligence" and effect2.qty == 2, "'You gain two intelligence' is too")
check(EncounterScript.EffectIsMechanical(effect1), "and it is mechanical, so a display lights it up")
check(string.find(EncounterScript.DescribeEffect(effect2), "2 Intelligence", 1, true) ~= nil,
    "described in plain English: " .. EncounterScript.DescribeEffect(effect2))
check(string.find(EncounterScript.Describe(intel), "unlocks feature: Intelligence", 1, true) ~= nil,
    "the dump names the feature")

for _, spelling in ipairs({ "+3 intelligence", "3 Intelligence", "gain +3 intelligence",
                            "The party gains 3 Intelligence", "Each party member gains 3 intelligence" }) do
    local one = EncounterScript.ParseEffects(spelling)[1]
    check(one.kind == "intelligence" and one.qty == 3, "spelling '" .. spelling .. "' is an intelligence clause")
end

--an unknown feature name, and an Unlock: written where it cannot work
local badFeature = EncounterScript.Parse(table.concat({
    "# Narrative", "", "Unlock: Telepathy", "", "## A Section", "", "Text.",
}, string.char(10)))
check(#badFeature.warnings == 1 and string.find(badFeature.warnings[1], "Telepathy", 1, true) ~= nil,
    "an unknown feature name warns")
check(#(badFeature.beats[1].unlocks or {}) == 0, "and unlocks nothing")

local inOption = EncounterScript.Parse(table.concat({
    "# Narrative", "", "## A Section", "", "### An Option", "", "Unlock: Intelligence", "",
}, string.char(10)))
check(#inOption.warnings == 1 and string.find(inOption.warnings[1], "under the option", 1, true) ~= nil,
    "an Unlock: under an option warns")
check(EncounterScript.UnlockedFeatures(inOption).intelligence == nil, "and does not unlock the feature")

local inMontage = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "", "## Opportunity: The Cottage", "", "Unlock: Intelligence", "",
    "### Knock", "|Knock: Presence", "|You fail at the test", "|+1 malice", "|+2 malice",
}, string.char(10)))
check(#inMontage.warnings == 1 and string.find(inMontage.warnings[1], "narrative beat", 1, true) ~= nil,
    "an Unlock: in a montage entry warns")

--Intelligence earned in a script that never unlocks the feature
local orphan = EncounterScript.Parse(table.concat({
    "# Montage", "", "## Round 1", "", "## Opportunity: The Cottage", "",
    "### Knock", "|Knock: Presence", "|You fail at the test", "|+1 Intelligence", "|+2 Intelligence",
}, string.char(10)))
check(#orphan.warnings == 1 and string.find(orphan.warnings[1], "nothing unlocks Intelligence", 1, true) ~= nil,
    "an intelligence clause with no unlock warns: " .. table.concat(orphan.warnings, "; "))

--- scenes -------------------------------------------------------------------------

local SCENE = table.concat({
    "# Montage",
    "",
    "## Round 1",
    "",
    "## Opportunity: Mysterious Cottage",
    "",
    "A mysterious cottage lays off the path. Dare you approach?",
    "",
    "---",
    "",
    "PC approaches the cottage...",
    "",
    "PC: I see a Witch within! What is she brewing?",
    "",
    "Witch (Hag) enters",
    "",
    "Witch: (in Hyrallic) Oh now ancient spirits, bless this brew I make.",
    "",
    "if PC speaks Hyrallic then",
    "    PC: She brews potion of healing, perhaps she is friendly?",
    "else",
    "    PC: I wonder of what she speaks? Is she wicked?",
    "end",
    "",
    "If you listen closely, you hear bubbling.",
    "",
    "Beware: the path is steep.",
    "",
    "### Negotiate with her for some aid",
    "",
    "PC: Good morrow! Might you offer us some aid?",
    "",
    "|Negotiation Test: Presence (Empathize, Lie, Flirt, Persuade)",
    "|You fail at the test => The witch is unimpressed.",
    "|You gain a small boon => You gain one Healing Potion",
    "|You gain a large boon => Each party member gains one Healing Potion",
    "",
    "if tier1 then",
    "    Witch: Begone, lest I turn you into a toad!",
    "elseif tier2 then",
    "    Witch: Very well take this and begone.",
    "else",
    "    Witch: Here take some potions for you and also your friends.",
    "    Witch exits",
    "end",
    "",
    "### Steal some potions",
    "",
    "|Thievery Test: Agility (Sneak)",
    "|You lose 6 Stamina.",
    "|You lose 6 Stamina. Each party member gains one Healing Potion.",
    "|Each party member gains one Healing Potion",
    "",
    "if PC chose Steal some potions and not tier1 then",
    "    PC: Got them!",
    "end",
}, string.char(10))

local sceneParse = EncounterScript.Parse(SCENE)
local sceneWarnings = {}
for _, w in ipairs(sceneParse.warnings) do
    --flavour text in a tier is the tier grammar's business, not the scene's
    if string.find(w, "unrecognized effect", 1, true) == nil then
        sceneWarnings[#sceneWarnings + 1] = w
    end
end
check(#sceneWarnings == 0, "the scene sample parses clean: " .. table.concat(sceneWarnings, "; "))
local cottage = EncounterScript.MontageEntries(sceneParse.beats[1])[1]
check(cottage.scripted == true, "--- marks the entry scripted")
check(cottage.description == "A mysterious cottage lays off the path. Dare you approach?", "the card text stops at ---")
check(cottage.actors["witch"] ~= nil and cottage.actors["witch"].monster == "Hag", "the witch is an actor played by the Hag")
check(#cottage.scene == 7, "the intro has 7 top-level steps, got " .. #cottage.scene)
check(cottage.scene[1].kind == "narrate" and cottage.scene[1].text == "PC approaches the cottage...", "narration")
check(cottage.scene[2].kind == "say" and cottage.scene[2].speaker == "PC", "PC speech")
check(cottage.scene[3].kind == "enter" and cottage.scene[3].name == "Witch", "an entrance")
check(cottage.scene[4].kind == "say" and cottage.scene[4].lang == "Hyrallic"
    and cottage.scene[4].text == "Oh now ancient spirits, bless this brew I make.", "a language tag is lifted off the line")
check(cottage.scene[5].kind == "if" and cottage.scene[5].elseSteps ~= nil, "an if/else block")
check(cottage.scene[6].kind == "narrate", "narration that starts with 'If' is not a branch")
check(cottage.scene[7].kind == "narrate", "'Beware:' is not a speaker")
local negotiate = cottage.options[1]
check(negotiate.text == "" and #negotiate.preScene == 1 and negotiate.preScene[1].kind == "say", "the option's line above the roll is its pre-roll scene")
check(negotiate.roll ~= nil and #negotiate.roll.tiers == 3, "the roll still parses under a pre-roll scene")
check(#negotiate.postScene == 1 and #negotiate.postScene[1].branches == 2, "the if/elseif/else after the roll is the outcome scene")

--flattening for one hero
local function Env(facts, tier, chose)
    return {
        tier = tier,
        actors = cottage.actors,
        test = function(atom)
            if atom.op == "speaks" then return facts.speaks == string.lower(atom.name) end
            if atom.op == "chose" then return chose ~= nil and string.lower(atom.name) == string.lower(chose) end
            return false
        end,
    }
end
local cast = {}
local intro = EncounterScript.FlattenScene(cottage.scene, Env({ speaks = "hyrallic" }), cast)
check(#intro == 6, "six lines play in the intro, got " .. #intro)
check(#intro[2].cast == 0 and #intro[3].cast == 1 and intro[3].cast[1].name == "Witch", "the witch is on stage from her first line")
check(string.find(intro[4].text, "potion of healing", 1, true) ~= nil, "the Hyrallic speaker gets the friendly branch")
check(#cast == 1, "the witch is still on stage when the intro ends")
local intro2 = EncounterScript.FlattenScene(cottage.scene, Env({}), {})
check(string.find(intro2[4].text, "Is she wicked", 1, true) ~= nil, "a hero without Hyrallic gets the else branch")
local out1 = EncounterScript.FlattenScene(negotiate.postScene, Env({}, 1), { { name = "Witch", monster = "Hag" } })
check(#out1 == 1 and string.find(out1[1].text, "toad", 1, true) ~= nil, "tier 1 outcome line")
local castAfter = { { name = "Witch", monster = "Hag" } }
local out3 = EncounterScript.FlattenScene(negotiate.postScene, Env({}, 4), castAfter)
check(#out3 == 1 and string.find(out3[1].text, "potions", 1, true) ~= nil and #castAfter == 0, "a critical takes the else branch, and the witch exits")
local steal = cottage.options[2]
check(#EncounterScript.FlattenScene(steal.postScene, Env({}, 2, "Steal some potions"), {}) == 1, "PC chose X and not tier1")
check(#EncounterScript.FlattenScene(steal.postScene, Env({}, 1, "Steal some potions"), {}) == 0, "not tier1 fails on tier 1")

--speech before an entrance brings the speaker on
local early = EncounterScript.Parse(table.concat({
    "# Montage", "## Opportunity: Shrine", "---", "Voice: Who goes there?", "Voice (Hag) enters",
    "### Pray", "|Prayer: Presence", "|a", "|b", "|c",
}, string.char(10)))
local shrine = EncounterScript.MontageEntries(early.beats[1])[1]
local earlyLines = EncounterScript.FlattenScene(shrine.scene, { actors = shrine.actors, test = function() return false end }, {})
check(#earlyLines == 1 and earlyLines[1].kind == "say" and #earlyLines[1].cast == 1 and earlyLines[1].cast[1].monster == "Hag",
    "a speaker is brought on stage by their first line")

--emotes: a stage direction or a tag on a speaker, landing on the next line
local emoteParse = EncounterScript.Parse(table.concat({
    "# Montage", "## Opportunity: Hut", "---",
    "Witch (Hag) enters", "Witch is alarmed", "PC is alert", "Witch: Who goes there?",
    "Witch (scared): Please, spare me!", "The forest is alert.", "Witch is sleepy",
    "### Knock", "|Knock: Presence", "|a", "|b", "|c",
}, string.char(10)))
local hut = EncounterScript.MontageEntries(emoteParse.beats[1])[1]
check(hut.scene[2].kind == "emote" and hut.scene[2].name == "Witch" and hut.scene[2].emote == "alarmed", "'Witch is alarmed' is an emote")
check(hut.scene[3].kind == "emote" and hut.scene[3].name == "PC" and hut.scene[3].emote == "alert", "'PC is alert' is an emote")
check(hut.scene[5].kind == "say" and hut.scene[5].speaker == "Witch" and hut.scene[5].emote == "scared"
    and hut.scene[5].text == "Please, spare me!", "'Witch (scared): ...' is speech with an emote")
check(hut.scene[6].kind == "narrate", "'The forest is alert.' names no character: narration")
check(hut.scene[7].kind == "narrate", "an unknown emote word is narration")
local emoteLines = EncounterScript.FlattenScene(hut.scene, { actors = hut.actors, test = function() return false end }, {})
check(#emoteLines == 4, "emote directions are not lines of their own, got " .. #emoteLines)
check(emoteLines[1].emotes ~= nil and #emoteLines[1].emotes == 2 and emoteLines[1].emotes[1].emote == "alarmed"
    and emoteLines[1].emotes[2].name == "PC", "both emotes land on the next line")
check(emoteLines[2].emotes ~= nil and emoteLines[2].emotes[1].name == "Witch" and emoteLines[2].emotes[1].emote == "scared",
    "a speaker's own emote lands on their line")
check(emoteLines[3].emotes == nil, "a line with no emote carries none")

--delves: a "# Delve:" section of obstacles, a chest table and scenes,
--entered by an option's "Delve: <Name>" line
local DELVE = table.concat({
    "# Montage", "## Round 1",
    "## Opportunity: Forbidden Tomb", "A tomb.", "---", "PC reads the door.",
    "### Enter the tomb", "PC: In we go.", "Delve: Forbidden Tomb",
    "# Delve: Forbidden Tomb", "Chest: every 1-2 obstacles",
    "## Obstacle: The Restless Dead", "Bones stir.", "---", "Skeleton (Soulwight) enters", "Skeleton: Leave!",
    "### Fight them", "|Combat Test: Might or Agility", "|You lose two recoveries. The undead are destroyed.", "|You lose a recovery.", "|The undead are destroyed.",
    "## Obstacle: A Pit", "A pit.",
    "### Jump it", "|Jump Test: Agility", "|You lose a recovery.", "|You lose a recovery.", "|Nothing.",
    "## Chest", "PC pries open a chest.",
    "|Treasure: 1d6", "|1-2: You gain one Healing Potion", "|3: You gain one Black Ash Dart", "|4-6: You gain one Buzz Balm",
    "## Continue", "PC: Deeper, or back?",
    "## Forced Out", "PC staggers out.",
}, string.char(10))
local delveParse = EncounterScript.Parse(DELVE)
local delveWarns = {}
for _, w in ipairs(delveParse.warnings) do
    if string.find(w, "unrecognized effect", 1, true) == nil then delveWarns[#delveWarns + 1] = w end
end
check(#delveWarns == 0, "the delve sample parses clean: " .. table.concat(delveWarns, "; "))
check(#delveParse.beats == 1, "a delve is not a beat")
local tomb = EncounterScript.FindDelve(delveParse, "forbidden tomb")
check(tomb ~= nil and tomb.name == "Forbidden Tomb", "FindDelve by name, any case")
check(tomb.chestEvery[1] == 1 and tomb.chestEvery[2] == 2, "Chest: every 1-2 obstacles")
check(#tomb.obstacles == 2 and tomb.obstacles[1].id == "d-forbidden-tomb-the-restless-dead", "obstacles with ids")
check(tomb.obstacles[1].scripted and #tomb.obstacles[1].scene == 2 and tomb.obstacles[1].actors["skeleton"] ~= nil, "an obstacle's scene and cast")
check(#tomb.obstacles[1].options == 1 and #tomb.obstacles[1].options[1].roll.tiers == 3, "an obstacle's test")
check(tomb.obstacles[2].scripted == nil and tomb.obstacles[2].description == "A pit.", "an unscripted obstacle keeps its card text")
local chestSec = tomb.sections.chest
check(chestSec ~= nil and chestSec.scene ~= nil and #chestSec.scene == 1, "the chest scene")
check(chestSec.table ~= nil and chestSec.table.dice == "1d6" and #chestSec.table.rows == 3, "the chest table")
check(EncounterScript.ChestRow(chestSec.table, 2).text == "You gain one Healing Potion", "row 1-2")
check(EncounterScript.ChestRow(chestSec.table, 5).effects[1].kind == "item", "row 4-6 grants an item")
check(tomb.sections.continue ~= nil and tomb.sections.forced ~= nil and tomb.sections.leave == nil, "named sections")
local tombEntry = EncounterScript.MontageEntries(delveParse.beats[1])[1]
check(tombEntry.options[1].delve == "Forbidden Tomb" and tombEntry.options[1].roll == nil, "the option enters the delve")
check(#tombEntry.options[1].preScene == 1, "'Delve:' is not a scene line")
local noDelve = EncounterScript.Parse(table.concat({
    "# Montage", "## Opportunity: Hole", "### Go in", "Delve: Nowhere",
}, string.char(10)))
check(string.find(table.concat(noDelve.warnings, "; "), "there is no '# Delve: Nowhere'", 1, true) ~= nil, "a missing delve warns")

--authoring mistakes warn
local bad = EncounterScript.Parse(table.concat({
    "# Montage", "## Opportunity: Shrine", "---",
    "if tier2 then", "It glows.", "end", "else", "if PC speaks Caelian then", "Hello.",
    "### Pray", "PC chose Dance", "|Prayer: Presence", "|a", "|b", "|c",
    "if PC chose Dance then", "x", "end",
}, string.char(10)))
local warnText = table.concat(bad.warnings, "; ")
check(string.find(warnText, "only known in the lines below", 1, true) ~= nil, "a tier test before the roll warns")
check(string.find(warnText, "'else' has no 'if'", 1, true) ~= nil, "a stray else warns")
check(string.find(warnText, "never closed", 1, true) ~= nil, "an unclosed if warns")
check(string.find(warnText, "names no '### option'", 1, true) ~= nil, "PC chose <unknown option> warns")

--conditions
local tree, problems = EncounterScript.ParseCondition("not (PC is Polder or PC has Magic) and crit then")
check(#problems == 0 and tree.op == "and" and tree.a.op == "not" and tree.a.a.op == "or" and tree.b.op == "tier" and tree.b.tier == 4,
    "not / parentheses / or / and / crit")

--garbling
local g1 = EncounterScript.Garble("Oh now, ancient spirits!", "Hyrallic")
check(g1 ~= "Oh now, ancient spirits!" and #g1 == #"Oh now, ancient spirits!" and string.sub(g1, 3, 3) == " "
    and string.sub(g1, -1) == "!", "garbled text keeps its shape: " .. g1)
check(EncounterScript.Garble("Oh now, ancient spirits!", "Hyrallic") == g1, "garbling is deterministic")
check(EncounterScript.SubstitutePC("PC sees PC's reflection in PCB", "Shadow") == "Shadow sees Shadow's reflection in PCB", "PC substitution")

--an unscripted entry is unchanged: option prose is still its description
local plain = EncounterScript.MontageEntries(EncounterScript.Parse(SAMPLE).beats[1])[1]
check(plain.scripted == nil and plain.scene == nil, "an entry without --- has no scene")

--sub-documents: a line that is only a link splices that document in
do
    local NL = string.char(10)
    local docs = {
        cottage = { id = "cottage", name = "Mysterious Cottage", text = table.concat({
            "## Opportunity: Mysterious Cottage", "", "A cottage.", "",
            "### Knock", "|Test: Presence", "|a", "|b", "|c", "",
            "[:Cottage Extras]",
        }, NL) },
        extras = { id = "extras", name = "Cottage Extras", text = table.concat({
            "### Peek", "|Peek Test: Agility", "|a", "|b", "|c", "|oops: nothing",
        }, NL) },
        loop = { id = "loop", name = "Loop", text = "[Loop](document:Loop)" },
    }
    local byName = { ["mysterious cottage"] = docs.cottage, ["cottage extras"] = docs.extras, ["loop"] = docs.loop }
    local function resolve(target)
        local key = string.lower(target):gsub("^document:", "")
        if byName[key] ~= nil then
            return byName[key]
        end
        if key == "goblin" then
            return nil, nil --a monster: a link, not a document
        end
        return nil, "names no journal document"
    end

    check(EncounterScript.IncludeTarget("[:Cottage]") == "Cottage", "embed form")
    check(EncounterScript.IncludeTarget("  [Go there](document:Cottage)  ") == "document:Cottage", "full link form")
    check(EncounterScript.IncludeTarget("[Cottage]") == "Cottage", "shorthand form")
    check(EncounterScript.IncludeTarget("[[scene]]") == nil, "a rich tag is not a link")
    check(EncounterScript.IncludeTarget("[x]") == nil and EncounterScript.IncludeTarget("[ ]") == nil, "checkboxes are not links")
    check(EncounterScript.IncludeTarget("![map](img.png)") == nil, "an image is not a link")
    check(EncounterScript.IncludeTarget("See [Cottage] for more.") == nil, "a link inside a sentence is only a link")

    local root = { id = "root", name = "Encounter", text = table.concat({
        "# Montage", "", "[[scene]]", "", "## Round 1", "",
        "[The cottage](document:Mysterious Cottage)",
        "[Goblin]",
        "[Nowhere]",
        "[:Loop]",
        "", "# Encounter", "", "[[encounter]]",
    }, NL) }
    local expansion = EncounterScript.ExpandIncludes(root, resolve)
    local parse = EncounterScript.ParseExpanded(expansion, "root")
    local entries = EncounterScript.MontageEntries(parse.beats[1])
    check(#parse.beats == 2 and #entries == 1 and entries[1].name == "Mysterious Cottage", "the linked entry is spliced into the round")
    check(#entries[1].options == 2 and entries[1].options[2].name == "Peek", "a nested embed splices too")
    check(parse.included.cottage ~= nil and parse.included.extras ~= nil and parse.included.loop ~= nil, "included lists every spliced document")
    check(string.find(expansion.text, "[Goblin]", 1, true) ~= nil, "a link to a non-document stays as text")
    local warnText = table.concat(parse.warnings, "; ")
    check(string.find(warnText, "line 9: 'Nowhere' names no journal document", 1, true) ~= nil, "an unresolved link warns with its line: " .. warnText)
    check(string.find(warnText, "'Loop' line 1: 'Loop' includes itself", 1, true) ~= nil, "a cycle warns and stops")
    check(string.find(warnText, "'Cottage Extras' line 6:", 1, true) ~= nil, "a parser warning names the sub-document and its own line")
    local peek = entries[1].options[2]
    check(EncounterScript.LineLabel(parse, peek.line) == "'Cottage Extras' line 1", "LineLabel maps an expanded line home")
    check(EncounterScript.LineLabel(parse, parse.beats[1].sceneLine) == "line 3" and parse.beats[1].sceneTag == "scene", "sceneLine records the tag's line")

    --the journal's repeated-tag keys
    local tagged = table.concat({ "[[scene]]", "x", "[[scene]] and [[scene]]", "[[scene]]" }, NL)
    check(EncounterScript.AnnotationKey(tagged, "scene", 1) == "scene", "first tag")
    check(EncounterScript.AnnotationKey(tagged, "scene", 3) == "scene-1", "second tag")
    check(EncounterScript.AnnotationKey(tagged, "scene", 4) == "scene-3", "a line after a line with two tags")
end

print(string.format("encounter_script_test: %d checks passed", passed))
