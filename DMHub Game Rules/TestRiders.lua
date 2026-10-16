--Test riders: requirements that gate or modify a power-roll test.
--
--A journal power roll (and a montage test, which reuses this) may carry
--"|<Effect>: <requirement>" lines after its tiers:
--  Allow (aliases Requires, Secret, Only): only a hero who meets the
--    requirement may take the test. The journal shows it locked to everyone
--    else; an Encounter of the Week montage hides it from them entirely (a
--    "secret option").
--  Edge / Double Edge / Bane / Double Bane: the hero rolls with that
--    modifier when they meet the requirement.
--A requirement is alternatives joined by "or" (commas work too). Authors
--write INTENT ("you can teleport"), and this file works out which heroes
--qualify, from every source that grants it (a teleport speed, Black Ash
--Teleport, Practical Magic...). The full vocabulary is documented in
--EncounterOfTheWeek/KNACKS_REFERENCE.md; in short:
--  you are skilled in <skill> / you speak <language> /
--  you are a <class, subclass, ancestry or career> /
--  you can <capability> (TestRiders.CAPABILITIES: teleport, fly, climb,
--    speak with animals, sense the supernatural, ...) /
--  you have <anything by name> / you have the <X> perk|complication|
--    ability|trait|kit|title|domain / you were a <career> /
--  you were raised in <culture or culture aspect> / you worship <deity> /
--  you carry <item> / you are immune to <damage type> / you have <type>
--    weakness / you cannot be <condition> / you are tiny|small|large /
--  your <Wealth|Renown|Level|Victories|Might|Agility|Reason|Intuition|
--    Presence|Size> is N or higher (or "or lower").
--A bare name in a list inherits the previous clause's kind: "you are
--skilled in Magic, Alchemy or Psionics", "you can climb or fly".
--A rider limited to one round of a montage puts it in its label:
--"|Edge (Round 1): you can climb or fly" only counts while the montage is
--in round 1 (facts.round); anywhere else it is never met.
--
--Everything above the "engine" marker is PURE Lua (no engine globals at
--load or call time) so the grammar runs under the bundled lua.exe and is
--unit-tested by tests/encounter_script_test.lua. The engine half reads a
--hero's facts off a creature and turns applied riders into roll-dialog
--modifier chips.

TestRiders = rawget(_G, "TestRiders") or {}

local function trim(s)
    return (string.gsub(s or "", "^%s+", ""):gsub("%s+$", ""))
end

local function lower(s)
    return string.lower(s or "")
end

--cond() is an engine global; give the pure module its own when missing.
if rawget(_G, "cond") == nil then
    cond = function(c, a, b)
        if c then
            return a
        end
        return b
    end
end

local RIDER_EFFECTS = {
    allow = "allow", allowed = "allow", require = "allow", requires = "allow", required = "allow",
    secret = "allow", only = "allow",
    edge = "edge", ["double edge"] = "doubleedge",
    bane = "bane", ["double bane"] = "doublebane",
}

local RIDER_LABELS = {
    allow = "Requires", edge = "Edge", doubleedge = "Double Edge", bane = "Bane", doublebane = "Double Bane",
}

--The edges (positive) or banes (negative) a rider effect grants.
local RIDER_BOONS = { edge = 1, doubleedge = 2, bane = -1, doublebane = -2 }

--round: the montage round a rider is limited to (nil = any time).
function TestRiders.Label(effect, round)
    local label = RIDER_LABELS[effect] or effect
    if round ~= nil then
        label = string.format("%s (Round %d)", label, round)
    end
    return label
end

function TestRiders.Boons(effect)
    return RIDER_BOONS[effect] or 0
end

--"Edge: You speak Caelian" -> "edge", "You speak Caelian". Nil when the
--line is not a rider (so a tier line that happens to contain a colon is
--left alone: only the known effect words qualify). Accepts the text with
--or without its leading '|'. A third result is the round the rider is
--limited to: "Edge (Round 1): ..." -> 1, otherwise nil.
function TestRiders.ParseRiderLine(text)
    text = trim(text)
    text = string.gsub(text, "^|", "")
    local label, rest = string.match(text, "^([%a %d%(%)]-)%s*:%s*(.*)$")
    if label == nil then
        return nil
    end
    local round = nil
    local bare, roundText = string.match(label, "^(.-)%s*%(%s*[rR][oO][uU][nN][dD]%s+(%d+)%s*%)%s*$")
    if bare ~= nil then
        label = bare
        round = tonumber(roundText)
    end
    local key = string.gsub(lower(trim(label)), "%s+", " ")
    local effect = RIDER_EFFECTS[key]
    if effect == nil then
        return nil
    end
    return effect, trim(rest), round
end

--Names are compared lower-cased, single-spaced, and with a compendium
--"Elf, High" turned into "high elf" so an author can write it either way.
--Curly apostrophes are folded to plain ones ("Put Your Back Into It!" and
--"I've Got You!" are spelled both ways in the data).
function TestRiders.NormalizeName(name)
    local s = string.gsub(lower(trim(name)), "%s+", " ")
    s = string.gsub(s, "\226\128\153", "'")
    local last, first = string.match(s, "^(.-),%s*(.+)$")
    if last ~= nil then
        s = first .. " " .. last
    end
    return s
end

--- capability vocabulary -------------------------------------------------------
--
--A capability is an INTENT an author can test for ("you can teleport")
--without knowing every rule that grants it. Each entry says how a hero
--qualifies:
--  movement = "fly"   a speed of that mode (facts.movement)
--  tag = "teleport"   an ability whose behaviours do it (facts.abilityTag,
--                     read off the hero's abilities by CreatureFacts)
--  immunity = "cold"  any immunity to that damage type
--  sources = { ... }  names the hero has. A plain name matches any trait,
--                     ability, perk, complication, kit or item of that name; a
--                     "kind:name" source matches only that kind of fact
--                     ("kindred:green" = the Green elementalist subclass,
--                     "language:mindspeech", "perk:monster whisperer").
--phrases are what follows "you can" (the key is always one of them).
--Other mods add to this with TestRiders.RegisterCapability.
TestRiders.CAPABILITIES = {}
local g_capabilityByPhrase = {}

--Register (or replace) one capability. `cap` = { key, phrases, describe,
--movement, tag, immunity, sources }.
function TestRiders.RegisterCapability(cap)
    cap.phrases = cap.phrases or {}
    local found = false
    for _, p in ipairs(cap.phrases) do
        if p == cap.key then
            found = true
        end
    end
    if not found then
        table.insert(cap.phrases, 1, cap.key)
    end
    local slot = #TestRiders.CAPABILITIES + 1
    for i, existing in ipairs(TestRiders.CAPABILITIES) do
        if existing.key == cap.key then
            slot = i
            break
        end
    end
    TestRiders.CAPABILITIES[slot] = cap
    for _, p in ipairs(cap.phrases) do
        g_capabilityByPhrase[TestRiders.NormalizeName(p)] = cap
    end
end

--The capability a "you can <phrase>" names, or nil.
function TestRiders.FindCapability(phrase)
    local p = TestRiders.NormalizeName(phrase or "")
    p = string.gsub(p, "[%.!]+$", "")
    return g_capabilityByPhrase[p]
end

for _, cap in ipairs({
    { key = "teleport", describe = "a teleport speed, or an ability that teleports you (Black Ash Teleport, Practical Magic)",
        movement = "teleport", tag = "teleport" },
    { key = "fly", describe = "a fly speed (Devil or Dragon Knight Wings), or a Stormwight's crow form",
        movement = "fly", sources = { "wings", "kit:corven" } },
    { key = "climb", describe = "a climb speed equal to your speed (Sewer Folk, a Stormwight's rat form); not the half-speed climb everyone has",
        movement = "climb", sources = { "kit:raden", "complication:sewer folk" } },
    { key = "swim", describe = "a swim speed equal to your speed (Waterborn, Sewer Folk)",
        movement = "swim", sources = { "complication:waterborn", "complication:sewer folk" } },
    { key = "burrow", describe = "a burrow speed", movement = "burrow" },
    { key = "speak with animals", phrases = { "talk to animals", "talk with animals", "speak to animals", "understand animals", "speak with plants", "talk to plants" },
        describe = "Green elementalist (It Is the Soul Which Hears), Stormwight (Aspect of the Wild), Raised by Beasts, Voice of the Wild",
        sources = { "it is the soul which hears", "aspect of the wild", "kindred:green", "kindred:stormwight", "complication:raised by beasts", "perk:voice of the wild" } },
    { key = "handle monsters", phrases = { "calm monsters", "soothe beasts", "handle beasts" },
        describe = "Monster Whisperer (Handle Animals on nonsapient monsters), or anyone who can speak with animals",
        sources = { "perk:monster whisperer", "it is the soul which hears", "aspect of the wild", "complication:raised by beasts" } },
    { key = "talk to the dead", phrases = { "speak with the dead", "speak to the dead", "commune with the dead", "talk to spirits", "speak with spirits" },
        describe = "Grave Speech (Death domain), Dead Men Tell All Tales (Circle of Graves), Medium, Bereaved",
        sources = { "grave speech", "dead men tell all tales", "complication:medium", "complication:bereaved", "contact spirits" } },
    { key = "sense the supernatural", phrases = { "detect the supernatural", "sense magic", "detect magic", "sense undead", "sense the unnatural" },
        describe = "Human Detect the Supernatural, Void elementalist (A Beyonding of Vision), a Dwarf's Detection rune, Heart of Nature, Creature Sense",
        sources = { "detect the supernatural", "a beyonding of vision", "runic carving", "heart of nature", "perk:creature sense", "soulsense" } },
    { key = "use telepathy", phrases = { "read minds", "read thoughts", "speak telepathically", "speak mind to mind", "send thoughts" },
        describe = "Mindspeech (the Talent), a Dwarf's Voice rune, Psychic Whisper, Prisoner of the Synlirii",
        sources = { "language:mindspeech", "telepathic speech", "runic carving", "perk:psychic whisper", "complication:prisoner of the synlirii", "kindred:telepathy" } },
    { key = "shape stone", phrases = { "shape earth", "reshape stone", "move earth", "work stone" },
        describe = "Dwarf Stone Singer, Earth elementalist (Motivate Earth), the Grounded complication",
        sources = { "stone singer", "motivate earth", "kindred:earth", "complication:grounded" } },
    { key = "make light", phrases = { "make a light", "create light", "shed light", "light the way" },
        describe = "a Dwarf's Light rune, a Fire elementalist, a Sun domain, Arcane Trick",
        sources = { "runic carving", "kindred:fire", "kindred:sun domain", "kindred:sun", "perk:arcane trick" } },
    { key = "make fire", phrases = { "start a fire", "conjure fire", "burn things", "set things alight" },
        describe = "a Fire elementalist (Return to Formlessness), Dragon Breath",
        sources = { "return to formlessness", "kindred:fire" } },
    --keys and phrases never contain the word "or": a requirement splits on it.
    { key = "melt objects", phrases = { "burn objects", "destroy objects", "melt metal", "melt stone" },
        describe = "a Fire elementalist (Return to Formlessness)",
        sources = { "return to formlessness" } },
    { key = "see in the dark", phrases = { "see in darkness", "see without light" },
        describe = "Devil Hellsight",
        sources = { "hellsight" } },
    { key = "see the invisible", phrases = { "see invisible creatures", "see through illusions", "see through walls" },
        describe = "Void elementalist (A Beyonding of Vision), Time Raider Beyondsight",
        sources = { "a beyonding of vision", "beyondsight" } },
    { key = "shapeshift", phrases = { "change shape", "turn into an animal", "become an animal" },
        describe = "Stormwight (Aspect of the Wild), the Animal Form complication",
        sources = { "aspect of the wild", "kindred:stormwight", "complication:animal form" } },
    { key = "go unnoticed", phrases = { "pass unseen", "hide in plain sight", "blend in", "be forgotten", "become a shadow" },
        describe = "Wode Elf Glamor, Polder Shadowmeld, a Shadow, Forgettable Face, Master of Disguise, Camouflage Hunter, I'm No Threat, Smoke Bomb",
        sources = { "wode elf glamor", "shadowmeld", "kindred:shadow", "perk:forgettable face", "perk:master of disguise", "perk:camouflage hunter", "i'm no threat", "smoke bomb", "complication:silent sentinel" } },
    { key = "disguise yourself", phrases = { "wear a disguise", "change your face", "look like someone else" },
        describe = "Forgettable Face, Master of Disguise, I'm No Threat, Stolen Face",
        sources = { "perk:forgettable face", "perk:master of disguise", "i'm no threat", "complication:stolen face" } },
    { key = "move things with your mind", phrases = { "use telekinesis", "move objects with your mind", "move things from afar" },
        describe = "Invisible Force, a Telekinesis talent",
        sources = { "perk:invisible force", "kindred:telekinesis", "minor telekinesis" } },
    { key = "work minor magic", phrases = { "cast a cantrip", "do a magic trick", "use magic" },
        describe = "Arcane Trick, an Elementalist (Practical Magic)",
        sources = { "perk:arcane trick", "practical magic", "kindred:elementalist" } },
    { key = "perform a blessing", phrases = { "bless", "bless someone", "perform a ritual", "perform a blessing" },
        describe = "Ritualist, a Conduit, a Censor",
        sources = { "perk:ritualist", "kindred:conduit", "kindred:censor" } },
    { key = "heal others", phrases = { "heal", "heal an ally", "tend wounds" },
        describe = "a Conduit (Healing Grace), a Censor (My Life for Yours)",
        sources = { "healing grace", "my life for yours", "kindred:conduit" } },
    { key = "endure the cold", phrases = { "endure cold", "resist cold", "brave the cold", "ignore the cold" },
        describe = "any cold immunity (Revenant, Frostheart, Wyrmplate), Wilds Explorer",
        immunity = "cold", sources = { "perk:wilds explorer" } },
    { key = "endure heat", phrases = { "endure fire", "resist heat", "resist fire", "brave the heat", "walk through fire" },
        describe = "any fire immunity (Fire and Chaos, Wyrmplate), Wilds Explorer",
        immunity = "fire", sources = { "perk:wilds explorer" } },
    { key = "endure poison", phrases = { "resist poison", "shrug off poison", "endure disease" },
        describe = "any poison immunity (Revenant, Primordial Sickness, Wyrmplate)",
        immunity = "poison" },
    { key = "brave the wilds", phrases = { "brave the elements", "endure the weather", "cross rough terrain" },
        describe = "Wilds Explorer, Danger Sense, Forest Walk, Nimblestep",
        sources = { "perk:wilds explorer", "perk:danger sense", "forest walk", "nimblestep" } },
    { key = "breathe underwater", phrases = { "breathe water", "go without air", "survive without breathing" },
        describe = "Waterborn, a Revenant (Tough But Withered)",
        sources = { "complication:waterborn", "tough but withered" } },
    { key = "sense danger", phrases = { "sense an ambush", "sense traps", "feel danger coming" },
        describe = "Danger Sense, High Senses, Foresight, Doomsight",
        sources = { "perk:danger sense", "high senses", "foresight", "doomsight" } },
    { key = "lift great weights", phrases = { "lift heavy things", "carry great loads", "break things apart" },
        describe = "Hakaan (Big!, All Is a Feather), a Berserker (Primordial Strength), Brawny",
        sources = { "all is a feather", "big!", "kindred:hakaan", "kindred:berserker", "perk:brawny" } },
    { key = "leap great distances", phrases = { "jump far", "make great leaps", "leap" },
        describe = "a Fury (Mighty Leaps), Lightning Leap, Friend Catapult",
        sources = { "mighty leaps", "lightning leap", "kindred:fury" } },
    { key = "fall safely", phrases = { "survive a fall", "land safely" },
        describe = "Memonek Fall Lightly, I've Got You!, a fly speed",
        movement = "fly", sources = { "fall lightly", "perk:i've got you!", "wings" } },
    { key = "decipher writing", phrases = { "read any language", "read unknown languages", "decipher languages", "read maps", "decipher codes" },
        describe = "Linguist, Memonek Systematic Mind, Knowledge domain (Blessing of Comprehension)",
        sources = { "perk:linguist", "systematic mind", "blessing of comprehension", "kindred:knowledge" } },
    { key = "change the weather", phrases = { "control the weather", "command the weather" },
        describe = "Storm domain (Blessing of Fortunate Weather)",
        sources = { "blessing of fortunate weather", "kindred:storm" } },
    { key = "create objects", phrases = { "make objects from nothing", "conjure tools" },
        describe = "Creation domain (Hands of the Maker), Improvisation Creation",
        sources = { "hands of the maker", "perk:improvisation creation" } },
    { key = "disarm traps", phrases = { "jam traps", "gum up traps" },
        describe = "Gum Up the Works",
        sources = { "perk:gum up the works" } },
    { key = "escape bonds", phrases = { "slip free", "escape restraints" },
        describe = "Slipped Lead",
        sources = { "perk:slipped lead" } },
}) do
    TestRiders.RegisterCapability(cap)
end

--Damage types an "immune to X" / "X weakness" clause may name.
local DAMAGE_TYPES = { acid = true, cold = true, corruption = true, fire = true, holy = true, lightning = true,
    poison = true, psychic = true, sonic = true }

--Sources that make a hero impossible to surprise (a "you cannot be
--surprised" requirement), on top of a real condition immunity.
local NEVER_SURPRISED = { "perk:danger sense", "primordial cunning", "unphased" }

--Draw Steel sizes in order, so "small" and "1L or larger" compare.
TestRiders.SIZE_ORDER = { ["1t"] = 1, ["1s"] = 2, ["1m"] = 3, ["1l"] = 4, ["2"] = 5, ["3"] = 6, ["4"] = 7, ["5"] = 8 }

--Numeric facts a threshold clause may name -> the facts.stat key.
local STAT_NAMES = {
    wealth = "wealth", renown = "renown", reputation = "renown", level = "level",
    victories = "victories", victory = "victories",
    might = "might", agility = "agility", reason = "reason", intuition = "intuition", presence = "presence",
    size = "size",
}

--A threshold value: a number, or for size a size name ("1L").
local function ParseStatValue(stat, text)
    text = lower(trim(text))
    if stat == "size" then
        return TestRiders.SIZE_ORDER[text]
    end
    return tonumber(text)
end

--- requirements ------------------------------------------------------------------

--"your wealth is 2+" / "renown 3+" / "you are level 2+" / "3+ victories" /
--"your size is 1l-" (ParseRequirement folds "or higher" to + and "or
--lower" to -) -> stat, min, max. Nil when the clause is no threshold.
local function ParseThreshold(lc)
    local w = lc
    w = string.gsub(w, "^you have%s+", "")
    w = string.gsub(w, "^you are%s+", "")
    w = string.gsub(w, "^your%s+", "")
    w = string.gsub(w, "^have%s+", "")
    w = string.gsub(w, "^a%s+", "")
    local name, value, dir = nil, nil, nil
    local patterns = {
        "^(%a+) is at least (%w+)()$", "^(%a+) of at least (%w+)()$",
        "^(%a+) is (%w+)([%+%-])$", "^(%a+) of (%w+)([%+%-])$", "^(%a+) (%w+)([%+%-])$",
        "^(%a+)%s*>=%s*(%w+)()$",
    }
    for _, p in ipairs(patterns) do
        local a, b, c = string.match(w, p)
        if a ~= nil and STAT_NAMES[a] ~= nil then
            name, value, dir = a, b, c
            break
        end
    end
    if name == nil then
        --"at least 3 victories", "3+ victories", "2- size"
        local b, a = string.match(w, "^at least (%w+) (%a+)$")
        local c = nil
        if b == nil then
            b, c, a = string.match(w, "^(%w+)([%+%-]) (%a+)$")
        end
        if a ~= nil and STAT_NAMES[a] ~= nil then
            name, value, dir = a, b, c
        end
    end
    if name == nil then
        return nil
    end
    local stat = STAT_NAMES[name]
    local n = ParseStatValue(stat, value)
    if n == nil then
        return nil
    end
    if dir == "-" then
        return stat, nil, n
    end
    return stat, n, nil
end

local SIZE_WORDS = {
    tiny = { max = 1 }, small = { max = 2 }, ["medium-sized"] = { min = 3, max = 3 },
    large = { min = 4 }, big = { min = 4 }, huge = { min = 5 },
}

--One alternative of a requirement -> an alternative record
--{ kind, name, [min], [max] } (text is added by the caller), or nil when
--the clause has no recognized form. Kinds: skill, language, kindred,
--capability, has, perk, complication, ability, trait, kit, title, domain,
--career, culture, deity, item, immunity, weakness, conditionimmunity, stat.
local function ParseRequirementClause(lc)
    lc = string.gsub(lc, "[%.!]+$", "")
    lc = trim(lc)

    --"you cannot be surprised" / "you can't be frightened": a condition
    --immunity. Read before "you can".
    local condition = string.match(lc, "^you cannot be (.+)$") or string.match(lc, "^you can't be (.+)$")
        or string.match(lc, "^you can not be (.+)$") or string.match(lc, "^cannot be (.+)$") or string.match(lc, "^can't be (.+)$")
        or string.match(lc, "^you are immune to the (.+) condition$") or string.match(lc, "^immune to the (.+) condition$")
    if condition ~= nil then
        return { kind = "conditionimmunity", name = TestRiders.NormalizeName(condition) }
    end

    --"you can teleport" / "you have a fly speed" / "you are able to read
    --minds": a capability. "you can use X" that is not a capability phrase
    --names an ability.
    local phrase = string.match(lc, "^you can (.+)$") or string.match(lc, "^can (.+)$")
        or string.match(lc, "^you are able to (.+)$") or string.match(lc, "^able to (.+)$")
    local mode = string.match(lc, "^you have an? (%a+) speed$") or string.match(lc, "^have an? (%a+) speed$")
    if mode ~= nil then
        phrase = mode
    end
    if phrase ~= nil then
        local cap = TestRiders.FindCapability(phrase)
        if cap ~= nil then
            return { kind = "capability", name = cap.key }
        end
        local used = string.match(phrase, "^use the (.+) ability$") or string.match(phrase, "^use (.+)$")
        if used ~= nil then
            return { kind = "ability", name = TestRiders.NormalizeName(used) }
        end
        return { kind = "unknowncapability", name = TestRiders.NormalizeName(phrase) }
    end

    --thresholds: wealth, renown, level, victories, characteristics, size.
    local stat, min, max = ParseThreshold(lc)
    if stat ~= nil then
        return { kind = "stat", name = stat, min = min, max = max }
    end

    local s = lc
    s = string.gsub(s, "^you're%s+", "you are ")
    s = string.gsub(s, "^you have%s+", "have ")
    s = string.gsub(s, "^you were%s+", "were ")
    s = string.gsub(s, "^you%s+", "")
    s = string.gsub(s, "^the hero is%s+", "are ")
    s = string.gsub(s, "^the party is%s+", "are ")
    s = trim(s)
    local bareAre = string.match(s, "^are (.+)$") or string.match(s, "^is (.+)$") or string.match(s, "^being (.+)$")

    --"you are small" / "you are large"
    if bareAre ~= nil and SIZE_WORDS[bareAre] ~= nil then
        local w = SIZE_WORDS[bareAre]
        return { kind = "stat", name = "size", min = w.min, max = w.max }
    end

    --"you are immune to fire" / "you have fire immunity" / "you are weak to fire"
    local dmg = (bareAre ~= nil and string.match(bareAre, "^immune to (%a+)$"))
        or string.match(s, "^have (%a+) immunity$") or string.match(s, "^have immunity to (%a+)$")
        or string.match(s, "^immunity:%s*(%a+)$")
    if dmg ~= nil and DAMAGE_TYPES[dmg] then
        return { kind = "immunity", name = dmg }
    end
    if dmg ~= nil then
        --"you are immune to frightened"
        return { kind = "conditionimmunity", name = TestRiders.NormalizeName(dmg) }
    end
    local weak = (bareAre ~= nil and (string.match(bareAre, "^weak to (%a+)$") or string.match(bareAre, "^vulnerable to (%a+)$")))
        or string.match(s, "^have (%a+) weakness$") or string.match(s, "^have a weakness to (%a+)$")
        or string.match(s, "^weakness:%s*(%a+)$")
    if weak ~= nil and DAMAGE_TYPES[weak] then
        return { kind = "weakness", name = weak }
    end

    local function Strip(name)
        name = trim(name)
        name = string.gsub(name, "^the%s+", "")
        name = string.gsub(name, "^an?%s+", "")
        return TestRiders.NormalizeName(name)
    end

    --typed names: "you have the Lucky Dog perk", "you worship Grole",
    --"you were a Farmer", "you carry a Healing Potion" ...
    local typed = {
        { "perk", { "^have the (.+) perk$", "^have (.+) perk$", "^perk:%s*(.+)$" } },
        { "complication", { "^have the (.+) complication$", "^have (.+) complication$", "^complication:%s*(.+)$" } },
        { "ability", { "^have the (.+) ability$", "^have (.+) ability$", "^ability:%s*(.+)$", "^know the (.+) ability$" } },
        { "trait", { "^have the (.+) trait$", "^have the (.+) feature$", "^have (.+) trait$", "^trait:%s*(.+)$", "^feature:%s*(.+)$" } },
        { "kit", { "^have the (.+) kit$", "^use the (.+) kit$", "^wear the (.+) kit$", "^your kit is (.+)$", "^kit:%s*(.+)$" } },
        { "title", { "^have the (.+) title$", "^hold the (.+) title$", "^title:%s*(.+)$" } },
        { "domain", { "^have the (.+) domain$", "^serve the (.+) domain$", "^your domain is (.+)$", "^domain:%s*(.+)$" } },
        { "deity", { "^worship (.+)$", "^your deity is (.+)$", "^serve (.+)$", "^deity:%s*(.+)$" } },
        { "career", { "^were an? (.+)$", "^your career is (.+)$", "^have the (.+) career$", "^career:%s*(.+)$" } },
        { "culture", { "^were raised in an? (.+) culture$", "^were raised in (.+)$", "^were raised among (.+)$", "^were raised on (.+)$",
            "^were raised by (.+)$", "^come from an? (.+) culture$", "^your culture is (.+)$", "^culture:%s*(.+)$" } },
        { "item", { "^carry (.+)$", "^are carrying (.+)$", "^have (.+) in your pack$", "^item:%s*(.+)$" } },
    }
    for _, entry in ipairs(typed) do
        for _, p in ipairs(entry[2]) do
            local name = string.match(s, p)
            if name ~= nil then
                local n = Strip(name)
                if entry[1] == "culture" then
                    n = string.gsub(n, "%s+culture$", "")
                elseif entry[1] == "domain" then
                    n = string.gsub(n, "%s+domain$", "")
                end
                return { kind = entry[1], name = n }
            end
        end
    end

    local skillPatterns = { "^are skilled in (.+)$", "^are skilled with (.+)$", "^are skilled at (.+)$", "^are trained in (.+)$",
        "^skilled in (.+)$", "^skilled with (.+)$", "^skilled at (.+)$", "^trained in (.+)$",
        "^have the (.+) skill$", "^have (.+) skill$", "^skill:%s*(.+)$", "^skilled:%s*(.+)$", "^skill (.+)$" }
    for _, p in ipairs(skillPatterns) do
        local name = string.match(s, p)
        if name ~= nil then
            return { kind = "skill", name = string.gsub(Strip(name), "%s+skill$", "") }
        end
    end

    local languagePatterns = { "^speak (.+)$", "^speaks (.+)$", "^know (.+)$", "^knows (.+)$", "^are fluent in (.+)$", "^fluent in (.+)$",
        "^understand (.+)$", "^language:%s*(.+)$", "^speak:%s*(.+)$" }
    for _, p in ipairs(languagePatterns) do
        local name = string.match(s, p)
        if name ~= nil then
            return { kind = "language", name = string.gsub(Strip(name), "%s+language$", "") }
        end
    end

    --"you have X": anything the hero has by that name -- a skill, trait,
    --ability, perk, complication, kit, title or item.
    local had = string.match(s, "^have the (.+)$") or string.match(s, "^have (.+)$")
    if had ~= nil then
        return { kind = "has", name = Strip(had) }
    end

    local kindredPatterns = { "^are an (.+)$", "^are a (.+)$", "^an (.+)$", "^a (.+)$", "^class:%s*(.+)$", "^ancestry:%s*(.+)$", "^kindred:%s*(.+)$",
        "^are playing an (.+)$", "^are playing a (.+)$", "^playing an (.+)$", "^playing a (.+)$", "^play an (.+)$", "^play a (.+)$" }
    for _, p in ipairs(kindredPatterns) do
        local name = string.match(s, p)
        if name ~= nil then
            return { kind = "kindred", name = Strip(name) }
        end
    end

    return nil
end

--How an alternative reads written out in full, for a bare name that
--inherited its kind ("..., Alchemy or Psionics" -> "you are skilled in
--Psionics"). Nil when the kind has no bare-name form.
local BARE_FORMS = {
    skill = "you are skilled in %s", language = "you speak %s", capability = "you can %s",
    perk = "you have the %s perk", complication = "you have the %s complication", ability = "you have %s",
    trait = "you have %s", kit = "your kit is %s", title = "you hold the %s title", domain = "you serve the %s domain",
    deity = "you worship %s", career = "you were a %s", culture = "you were raised in %s", item = "you carry %s",
    has = "you have %s", immunity = "you are immune to %s", weakness = "you have %s weakness",
    conditionimmunity = "you cannot be %s",
}

--"You are skilled in Magic, Alchemy or Psionics, or you are an Elementalist"
--  -> { text, alternatives = { { kind, name, text, [min], [max] }, ... },
--       unrecognized = bool }
--kind "unknown" is a clause the grammar could not place (never met); kind
--"unknowncapability" is a "you can <x>" whose x is not in the vocabulary
--(also never met; the parser warns with the known phrases).
function TestRiders.ParseRequirement(text)
    local req = { text = trim(text), alternatives = {}, unrecognized = false }
    --"2 or higher" is one threshold, not two alternatives: fold it to "2+"
    --(and "1 or lower" to "1-") before "or" is read as the separator.
    local work = string.gsub(req.text, "(%d+[%a]?)%s+[oO][rR]%s+(%a+)", function(n, word)
        word = lower(word)
        if word == "higher" or word == "more" or word == "greater" or word == "larger" or word == "bigger" or word == "above" or word == "better" then
            return n .. "+"
        elseif word == "lower" or word == "less" or word == "fewer" or word == "smaller" or word == "below" then
            return n .. "-"
        end
        return nil
    end)
    --commas and semicolons are alternatives too; "or" is the separator
    work = " " .. string.gsub(work, "[,;]", " or ") .. " "
    work = string.gsub(work, "%s+[oO][rR]%s+", "\1")
    local last = nil
    for part in string.gmatch(work, "[^\1]+") do
        --", or you are ..." leaves a stray "or" at the head of the part
        local clause = trim((string.gsub(trim(part), "^[oO][rR]%s+", "")))
        if clause ~= "" then
            local lc = lower(clause)
            local alt = ParseRequirementClause(lc)
            if alt == nil and last ~= nil then
                --a bare name in a list: "Magic, Alchemy or Psionics". Spell
                --the clause out so "Unlocked: you are skilled in Psionics"
                --reads as a sentence.
                local bare = trim((string.gsub(clause, "^[tT]he%s+", "")))
                local bareName = TestRiders.NormalizeName(bare)
                local kind = last.kind
                if kind == "capability" or kind == "unknowncapability" then
                    local cap = TestRiders.FindCapability(bare)
                    if cap ~= nil then
                        alt = { kind = "capability", name = cap.key }
                    else
                        alt = { kind = "unknowncapability", name = bareName }
                    end
                    clause = "you can " .. bare
                elseif kind == "kindred" then
                    alt = { kind = "kindred", name = bareName }
                    clause = cond(string.find(lower(bare), "^[aeiou]") ~= nil, "you are an ", "you are a ") .. bare
                elseif BARE_FORMS[kind] ~= nil then
                    alt = { kind = kind, name = bareName }
                    clause = string.format(BARE_FORMS[kind], bare)
                end
            end
            if alt == nil then
                alt = { kind = "unknown", name = TestRiders.NormalizeName(lc) }
            end
            if alt.kind == "unknown" or alt.kind == "unknowncapability" then
                req.unrecognized = true
            end
            alt.text = clause
            req.alternatives[#req.alternatives + 1] = alt
            last = alt
        end
    end
    return req
end

--Parse one rider line into a rider record, or nil when the line is not a
--rider: { effect, text, requirement }. The caller adds its own line index.
function TestRiders.ParseRider(line)
    local effect, requirementText, round = TestRiders.ParseRiderLine(line)
    if effect == nil then
        return nil
    end
    return { effect = effect, text = requirementText, requirement = TestRiders.ParseRequirement(requirementText), round = round }
end

--The problems with a parsed requirement, as warning strings (nothing when
--every alternative is understood).
function TestRiders.RequirementProblems(req)
    local problems = {}
    for _, alt in ipairs((req or {}).alternatives or {}) do
        if alt.kind == "unknowncapability" then
            local phrases = {}
            for _, cap in ipairs(TestRiders.CAPABILITIES) do
                phrases[#phrases + 1] = cap.key
            end
            problems[#problems + 1] = string.format("'%s': '%s' is not a known capability (known: %s); never met",
                alt.text, alt.name, table.concat(phrases, ", "))
        elseif alt.kind == "unknown" then
            problems[#problems + 1] = string.format("requirement '%s' not understood (see KNACKS_REFERENCE.md: 'you can teleport', 'you speak X', 'you are a X', 'you have the X perk', 'your Wealth is 2 or higher' ...); never met", alt.text)
        end
    end
    return problems
end

--- facts ---------------------------------------------------------------------------
--
--What a hero is, for requirements: sets of normalized names, plus numbers.
--  skill, language, kindred (class, subclass, ancestry, career), movement
--  (climb/fly/swim/burrow/teleport speeds), trait (class/ancestry/kit/
--  career/culture/complication features), ability (activated abilities),
--  perk, complication, career, culture (name + aspects), kit, title, deity,
--  domain, item (carried or equipped), conditionimmunity
--  abilityTag = { teleport = "Black Ash Teleport" } -- what abilities do
--  immunity / weakness = { fire = 5 } -- by damage type
--  stat = { wealth, renown, level, victories, might, agility, reason,
--           intuition, presence, size (TestRiders.SIZE_ORDER) }
--CompleteFacts adds the derived sets: capability = { teleport = "Black Ash
--Teleport" } (the source that granted it) and named (everything the hero
--has by name, for "you have X").

local SET_KINDS = { "skill", "language", "kindred", "movement", "trait", "ability", "perk", "complication", "career",
    "culture", "kit", "title", "deity", "domain", "item", "conditionimmunity" }

--Find a fact by name in a set, tolerating a compendium "Elf, High" style
--suffix match ("high elf" meets "elf") and a trailing plural "s".
local function SetHas(set, name)
    if type(set) ~= "table" or name == nil or name == "" then
        return nil
    end
    if set[name] then
        return name
    end
    local singular = string.match(name, "^(.-)s$")
    if singular ~= nil and singular ~= "" and set[singular] then
        return singular
    end
    for factName, _ in pairs(set) do
        if string.sub(factName, -(#name + 1)) == " " .. name then
            return factName
        end
    end
    return nil
end

--A "kind:name" or plain source against the facts -> the matched name.
--Items count: some traits are carried (the Dwarf's "Dwarf Runic Carving").
local NAMED_KINDS = { "trait", "ability", "perk", "complication", "kit", "item" }
local function SourceMet(facts, source)
    local kind, name = string.match(source, "^(%a+):(.+)$")
    if kind ~= nil then
        local found = SetHas(facts[kind], TestRiders.NormalizeName(name))
        return found
    end
    local n = TestRiders.NormalizeName(source)
    for _, k in ipairs(NAMED_KINDS) do
        local found = SetHas(facts[k], n)
        if found then
            return found
        end
    end
    return nil
end

--Capitalize a normalized name for display ("black ash teleport" ->
--"Black Ash Teleport").
local function Display(name)
    name = string.gsub(name or "", "^signature trait:%s*", "")
    return (string.gsub(name, "(%a)([%w']*)", function(a, b) return string.upper(a) .. b end))
end

--Fill in the derived facts (capability, named) and normalize old-style
--fields (facts.wealth). Safe to call more than once.
function TestRiders.CompleteFacts(facts)
    facts = facts or {}
    if facts._complete then
        return facts
    end
    for _, k in ipairs(SET_KINDS) do
        facts[k] = facts[k] or {}
    end
    facts.immunity = facts.immunity or {}
    facts.weakness = facts.weakness or {}
    facts.abilityTag = facts.abilityTag or {}
    facts.stat = facts.stat or {}
    if facts.wealth ~= nil and facts.stat.wealth == nil then
        facts.stat.wealth = tonumber(facts.wealth)
    end

    local capability = facts.capability or {}
    for _, cap in ipairs(TestRiders.CAPABILITIES) do
        if capability[cap.key] == nil then
            local why = nil
            if cap.movement ~= nil and facts.movement[cap.movement] then
                why = string.format("%s speed", cap.movement)
            end
            if why == nil and cap.tag ~= nil and facts.abilityTag[cap.tag] ~= nil then
                local source = facts.abilityTag[cap.tag]
                why = cond(type(source) == "string", source, cap.tag)
            end
            if why == nil and cap.immunity ~= nil and (tonumber(facts.immunity[cap.immunity]) or 0) > 0 then
                why = string.format("%s immunity", cap.immunity)
            end
            if why == nil then
                for _, source in ipairs(cap.sources or {}) do
                    local found = SourceMet(facts, source)
                    if found ~= nil then
                        why = Display(found)
                        break
                    end
                end
            end
            if why ~= nil then
                capability[cap.key] = why
            end
        end
    end
    facts.capability = capability

    --"you cannot be surprised" is met by the features that say so.
    if not facts.conditionimmunity.surprised then
        for _, source in ipairs(NEVER_SURPRISED) do
            if SourceMet(facts, source) ~= nil then
                facts.conditionimmunity.surprised = true
                break
            end
        end
    end

    local named = {}
    for _, k in ipairs({ "skill", "trait", "ability", "perk", "complication", "kit", "title", "item", "career", "deity", "domain" }) do
        for name, _ in pairs(facts[k]) do
            named[name] = true
        end
    end
    facts.named = named
    facts._complete = true
    return facts
end

--Does a fact set satisfy a requirement? Returns met, and the text of the
--alternative that met it (with the source in brackets for a capability:
--"you can teleport (Black Ash Teleport)"). A fact that ENDS with the
--wanted name also counts ("high elf" meets "you are an Elf").
function TestRiders.RequirementMet(req, facts)
    facts = TestRiders.CompleteFacts(facts)
    for _, alt in ipairs(req.alternatives or {}) do
        local kind = alt.kind
        if kind == "stat" then
            local value = tonumber(facts.stat[alt.name])
            if value ~= nil and (alt.min == nil or value >= alt.min) and (alt.max == nil or value <= alt.max) then
                return true, alt.text
            end
        elseif kind == "capability" then
            local why = facts.capability[alt.name]
            if why ~= nil then
                if type(why) == "string" and why ~= "" then
                    return true, string.format("%s (%s)", alt.text, why)
                end
                return true, alt.text
            end
        elseif kind == "immunity" or kind == "weakness" then
            if (tonumber(facts[kind][alt.name]) or 0) > 0 then
                return true, alt.text
            end
        elseif kind == "has" then
            if SetHas(facts.named, alt.name) ~= nil then
                return true, alt.text
            end
        elseif kind == "ability" or kind == "trait" then
            --an ability is often granted by a trait of the same name, and
            --the other way round: either set will do.
            if SetHas(facts.ability, alt.name) ~= nil or SetHas(facts.trait, alt.name) ~= nil then
                return true, alt.text
            end
        elseif kind == "domain" then
            if SetHas(facts.domain, alt.name) ~= nil or SetHas(facts.kindred, alt.name .. " domain") ~= nil then
                return true, alt.text
            end
        elseif kind == "culture" then
            if SetHas(facts.culture, alt.name) ~= nil then
                return true, alt.text
            end
        elseif type(facts[kind]) == "table" and alt.name ~= "" then
            if SetHas(facts[kind], alt.name) ~= nil then
                return true, alt.text
            end
        end
    end
    return false, nil
end

--Weigh a roll's riders against one hero's facts:
--  { allowed = bool, gated = bool (an Allow rider exists),
--    unlockedBy = text (the first Allow clause met) | nil,
--    boons = n, banes = n, applied = { { rider, why }, ... },
--    unlocked = { { rider, why }, ... } (the Allow riders that were met),
--    unmet = { rider, ... } }
--Every Allow line must be met (several AND together; "or" goes inside
--one line). A roll with no riders is allowed with nothing applied.
function TestRiders.Evaluate(riders, facts)
    local result = { allowed = true, gated = false, unlockedBy = nil, boons = 0, banes = 0, applied = {}, unlocked = {}, unmet = {} }
    for _, rider in ipairs(riders or {}) do
        local met, why = TestRiders.RequirementMet(rider.requirement, facts)
        --a rider limited to one montage round is never met outside it.
        if rider.round ~= nil and tonumber((facts or {}).round) ~= rider.round then
            met, why = false, nil
        end
        if rider.effect == "allow" then
            result.gated = true
            if met then
                result.unlockedBy = result.unlockedBy or why
                result.unlocked[#result.unlocked + 1] = { rider = rider, why = why }
            else
                result.allowed = false
                result.unmet[#result.unmet + 1] = rider
            end
        elseif met then
            local boons = TestRiders.Boons(rider.effect)
            if boons > 0 then
                result.boons = result.boons + boons
            else
                result.banes = result.banes - boons
            end
            result.applied[#result.applied + 1] = { rider = rider, why = why }
        else
            result.unmet[#result.unmet + 1] = rider
        end
    end
    return result
end

--The Allow requirements a hero does not meet, joined for a refusal message.
function TestRiders.DescribeUnmet(verdict)
    local parts = {}
    for _, rider in ipairs((verdict or {}).unmet or {}) do
        if rider.effect == "allow" then
            parts[#parts + 1] = rider.text
        end
    end
    return table.concat(parts, "; ")
end

--How each rider fell for a hero, for a display: one row per rider,
--{ rider, label, text, state } where state is nil (no verdict), "locked"
--/ "unlocked" for Allow riders, "met" (an edge applies), "hurt" (a bane
--applies) or "unmet". A met rider's text is the clause that met it
--("you are skilled in Psionics"); otherwise the requirement as written.
function TestRiders.DescribeRows(riders, verdict)
    local whyByRider, unmetByRider = {}, {}
    for _, a in ipairs((verdict or {}).applied or {}) do
        whyByRider[a.rider] = a.why
    end
    for _, a in ipairs((verdict or {}).unlocked or {}) do
        whyByRider[a.rider] = a.why
    end
    for _, rider in ipairs((verdict or {}).unmet or {}) do
        unmetByRider[rider] = true
    end
    local rows = {}
    for _, rider in ipairs(riders or {}) do
        local label = TestRiders.Label(rider.effect, rider.round)
        local text = rider.text
        local state = nil
        if verdict ~= nil then
            if rider.effect == "allow" then
                if unmetByRider[rider] then
                    state = "locked"
                else
                    state = "unlocked"
                    label = "Unlocked"
                    text = whyByRider[rider] or text
                end
            elseif whyByRider[rider] ~= nil then
                state = cond(TestRiders.Boons(rider.effect) > 0, "met", "hurt")
                text = whyByRider[rider]
            else
                state = "unmet"
            end
        end
        rows[#rows + 1] = { rider = rider, label = label, text = text, state = state }
    end
    return rows
end

--- engine -------------------------------------------------------------------
--Nothing below runs under the bare interpreter.

--Does this ability (or anything it invokes) move its user by teleport?
--Hero teleports are abilities, not speeds: Black Ash Teleport, Practical
--Magic's teleport, Heart of the Beast. A RelocateCreature behaviour moves
--by teleport unless it says otherwise (its movementType default).
local function AbilityTeleports(ability, depth)
    if ability == nil or (depth or 0) > 4 then
        return false
    end
    local found = false
    pcall(function()
        for _, b in ipairs(ability.behaviors or {}) do
            local typeName = b.typeName
            if typeName == "ActivatedAbilityRelocateCreatureBehavior" then
                local movementType = "teleport"
                pcall(function() movementType = b.movementType end)
                if movementType == nil or movementType == "teleport" then
                    found = true
                    return
                end
            elseif typeName == "ActivatedAbilityInvokeAbilityBehavior" then
                local custom = nil
                pcall(function() custom = b:try_get("customAbility") end)
                if custom ~= nil and AbilityTeleports(custom, (depth or 0) + 1) then
                    found = true
                    return
                end
            end
        end
    end)
    return found
end

--What a hero is, for rider requirements (see "facts" above), every name
--normalized the way the parser does. "climb" means a climb speed at least
--the creature's walking speed (creature:IsClimber), so the climbing every
--hero can do at half speed does not count. The caller adds `round` when
--there is one (the montage). Every read is guarded: a monster, a half-built
--hero or a missing table simply contributes nothing.
function TestRiders.CreatureFacts(c)
    local facts = {}
    for _, k in ipairs(SET_KINDS) do
        facts[k] = {}
    end
    facts.immunity, facts.weakness, facts.abilityTag, facts.stat = {}, {}, {}, {}
    if c == nil then
        return TestRiders.CompleteFacts(facts)
    end
    local function Add(kind, name)
        if type(name) == "string" and name ~= "" then
            facts[kind][TestRiders.NormalizeName(name)] = true
        end
    end

    pcall(function()
        if c:IsClimber() then
            facts.movement.climb = true
        end
    end)
    for _, mode in ipairs({ "fly", "swim", "burrow" }) do
        pcall(function()
            if c:GetSpeed(mode) > 0 then
                facts.movement[mode] = true
            end
        end)
    end
    pcall(function()
        if c:CanTeleport() then
            facts.movement.teleport = true
        end
    end)

    --numbers
    pcall(function() facts.stat.wealth = c:CalculateNamedCustomAttribute("Wealth") end)
    pcall(function() facts.stat.renown = c:CalculateNamedCustomAttribute("Renown") end)
    pcall(function() facts.stat.level = c:CharacterLevel() end)
    pcall(function() facts.stat.victories = c:GetVictories() end)
    pcall(function()
        for id, info in pairs(creature.attributesInfo or {}) do
            local key = lower(info.description or "")
            if STAT_NAMES[key] ~= nil then
                local attr = c:GetAttribute(id)
                if attr ~= nil then
                    facts.stat[key] = attr:Modifier()
                end
            end
        end
    end)
    pcall(function()
        local n = c:GetCalculatedCreatureSizeAsNumber()
        local name = creature.sizes ~= nil and creature.sizes[n] or nil
        facts.stat.size = TestRiders.SIZE_ORDER[lower(name or "")] or n
    end)
    facts.wealth = facts.stat.wealth

    pcall(function()
        for _, skillInfo in unhidden_pairs(dmhub.GetTable(Skill.tableName) or {}) do
            if c:ProficientInSkill(skillInfo) then
                Add("skill", skillInfo.name)
            end
        end
    end)
    pcall(function()
        local languages = dmhub.GetTable(Language.tableName) or {}
        for langid, _ in pairs(c:LanguagesKnown()) do
            local lang = languages[langid]
            if lang ~= nil then
                Add("language", lang.name)
            end
        end
    end)
    pcall(function()
        for _, entry in ipairs(c:GetClassesAndSubClasses()) do
            Add("kindred", entry.class.name)
        end
    end)
    pcall(function()
        local race = c:Race()
        if race ~= nil then
            Add("kindred", race.name)
        end
    end)
    pcall(function()
        local subrace = c:Subrace()
        if subrace ~= nil then
            Add("kindred", subrace.name)
        end
    end)
    pcall(function()
        local career = c:Background()
        if career ~= nil then
            Add("career", career.name)
            --"you are a Farmer" reads as naturally as "you were a Farmer".
            Add("kindred", career.name)
        end
    end)
    pcall(function()
        local culture = c:GetCulture()
        if culture ~= nil then
            pcall(function() Add("culture", culture.name) end)
            local aspectsTable = dmhub.GetTable(CultureAspect.tableName) or {}
            for _, aspectid in pairs(culture.aspects or {}) do
                local aspect = aspectsTable[aspectid]
                if aspect ~= nil then
                    Add("culture", aspect.name)
                end
            end
        end
    end)
    pcall(function()
        for _, complication in ipairs(c:Complications()) do
            Add("complication", complication.name)
        end
    end)
    pcall(function()
        local kitTable = dmhub.GetTable(Kit.tableName) or {}
        for _, key in ipairs({ "kitid", "kitid2" }) do
            local kitid = c:try_get(key)
            if kitid ~= nil and kitTable[kitid] ~= nil then
                Add("kit", kitTable[kitid].name)
            end
        end
    end)
    pcall(function()
        for _, title in ipairs(c:Titles()) do
            Add("title", title.name)
        end
    end)
    --traits: every feature the hero has (class, ancestry, career, culture,
    --kit, complication), flattened.
    pcall(function()
        for _, feature in ipairs(c:GetClassFeatures() or {}) do
            pcall(function() Add("trait", feature.name) end)
        end
    end)
    --perks, the deity and the deity's domains are CHOICES: walk the live
    --choice features and look their picks up (a stale career choice guid
    --can linger in levelChoices, so the raw table is not trusted).
    pcall(function()
        local levelChoices = c:GetLevelChoices() or {}
        local featTable = dmhub.GetTable(CharacterFeat.tableName) or {}
        local deityTable = dmhub.GetTable(Deity.tableName) or {}
        local domainTable = dmhub.GetTable(DeityDomain.tableName) or {}
        for _, info in ipairs(c:GetClassFeaturesAndChoicesWithDetails() or {}) do
            local feature = info.feature
            local guid = feature ~= nil and feature.guid or nil
            for _, pick in ipairs((guid ~= nil and levelChoices[guid]) or {}) do
                if type(pick) == "string" then
                    if featTable[pick] ~= nil then
                        Add("perk", featTable[pick].name)
                    elseif deityTable[pick] ~= nil then
                        Add("deity", deityTable[pick].name)
                    elseif domainTable[pick] ~= nil then
                        Add("domain", domainTable[pick].name)
                    end
                end
            end
        end
    end)
    --subclass domains ("Life Domain") count as domains too.
    for name, _ in pairs(facts.kindred) do
        local domain = string.match(name, "^(.-) domain$")
        if domain ~= nil then
            facts.domain[domain] = true
        end
    end
    --abilities, and what they do.
    pcall(function()
        for _, ability in ipairs(c:GetActivatedAbilities({ excludeGlobal = true }) or {}) do
            local name = nil
            pcall(function() name = ability.name end)
            if type(name) == "string" and name ~= "" then
                Add("ability", name)
                if facts.abilityTag.teleport == nil and AbilityTeleports(ability, 0) then
                    facts.abilityTag.teleport = name
                end
            end
        end
    end)
    --carried and equipped items.
    pcall(function()
        local gear = dmhub.GetTable("tbl_Gear") or {}
        for itemid, entry in pairs(c:try_get("inventory", {})) do
            local qty = type(entry) == "table" and tonumber(entry.quantity) or 0
            if (qty or 0) > 0 and gear[itemid] ~= nil then
                Add("item", gear[itemid].name)
            end
        end
        for _, itemid in pairs(c:Equipment() or {}) do
            if type(itemid) == "string" and gear[itemid] ~= nil then
                Add("item", gear[itemid].name)
            end
        end
    end)
    --immunities and weaknesses by damage type.
    pcall(function()
        for _, item in ipairs(c:ResistanceEntries() or {}) do
            local entry = item.entry
            local damageType = lower(entry:try_get("damageType", "all"))
            local dr = tonumber(entry:try_get("dr", 0)) or 0
            if dr >= 0 then
                facts.immunity[damageType] = math.max(facts.immunity[damageType] or 0, dr)
            else
                facts.weakness[damageType] = math.max(facts.weakness[damageType] or 0, -dr)
            end
        end
    end)
    pcall(function()
        local conditions = dmhub.GetTable(CharacterCondition.tableName) or {}
        for condid, _ in pairs(c:GetConditionImmunities() or {}) do
            local cond = conditions[condid]
            Add("conditionimmunity", cond ~= nil and cond.name or tostring(condid))
        end
    end)
    return TestRiders.CompleteFacts(facts)
end

--A creature's verdict on a roll's riders, or nil when there are none.
function TestRiders.VerdictFor(c, riders)
    if riders == nil or #riders == 0 then
        return nil
    end
    local verdict = nil
    local ok, err = pcall(function()
        verdict = TestRiders.Evaluate(riders, TestRiders.CreatureFacts(c))
    end)
    if not ok then
        printf("TestRiders: verdict failed: %s", tostring(err))
        return nil
    end
    return verdict
end

--The rider effects the hero earned ("Edge: you speak Caelian"), as chips
--for the roll dialog: one synthetic "power" modifier per applied rider,
--pre-ticked with the requirement it met as its justification, so the
--roll text picks up "+ 1 edge" / "+ 1 bane" exactly as an equipped
--modifier would (CharacterModifier:ApplyToRoll -> ModifyPowerRolls).
--Appends to `modifiers` (a GetModifiersForPowerRoll list) and returns it.
local RIDER_MODTYPES = { edge = "edge", doubleedge = "double_edge", bane = "bane", doublebane = "double_bane" }
function TestRiders.AppendModifiers(modifiers, verdict, rollType)
    modifiers = modifiers or {}
    if verdict == nil then
        return modifiers
    end
    for _, applied in ipairs(verdict.applied or {}) do
        local modtype = RIDER_MODTYPES[applied.rider.effect]
        if modtype ~= nil then
            local label = TestRiders.Label(applied.rider.effect, applied.rider.round)
            local ok, err = pcall(function()
                local m = CharacterModifier.new{
                    guid = dmhub.GenerateGuid(),
                    name = string.format("%s: %s", label, applied.why),
                    description = string.format("%s on this test because %s.", label, applied.why),
                    behavior = "power",
                    domains = {},
                }
                CharacterModifier.TypeInfo.power.init(m)
                m.rollType = rollType or "test_power_roll"
                m.modtype = modtype
                m.activationCondition = true
                modifiers[#modifiers + 1] = {
                    modifier = m,
                    context = {},
                    hint = { result = true, justification = { applied.why } },
                }
            end)
            if not ok then
                printf("TestRiders: could not build rider modifier: %s", tostring(err))
            end
        end
    end
    return modifiers
end
