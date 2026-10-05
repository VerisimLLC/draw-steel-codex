--Test riders: requirements that gate or modify a power-roll test.
--
--A journal power roll (and a montage test, which reuses this) may carry
--"|<Effect>: <requirement>" lines after its tiers:
--  Allow (alias Requires): only a hero who meets the requirement may take
--    the test. Everyone still sees it; others see it locked.
--  Edge / Double Edge / Bane / Double Bane: the hero rolls with that
--    modifier when they meet the requirement.
--A requirement is alternatives joined by "or" (commas work too), each
--"you are skilled in <skill>", "you speak <language>", "you are a/an
--<class or ancestry>", "you can climb" / "you can fly" (a climb or fly
--speed) or "your Wealth is 2 or higher". A bare name in a list inherits
--the previous clause's kind: "you are skilled in Magic, Alchemy or
--Psionics", "you can climb or fly".
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
function TestRiders.NormalizeName(name)
    local s = string.gsub(lower(trim(name)), "%s+", " ")
    local last, first = string.match(s, "^(.-),%s*(.+)$")
    if last ~= nil then
        s = first .. " " .. last
    end
    return s
end

--The movement modes a "you can <mode>" requirement may name.
local MOVEMENT_MODES = { climb = true, fly = true, swim = true, burrow = true, teleport = true }

--One alternative of a requirement -> kind ("skill"|"language"|"kindred"|
--"movement"|"wealth") and the normalized name, or nil when the clause has
--no recognized verb. A wealth requirement's name is its minimum, as text.
local function ParseRequirementClause(lc)
    --"you can climb" / "you have a fly speed": read before the generic
    --"you can" strip below turns the clause into a bare word.
    local mode = string.match(lc, "^you can (%a+)$") or string.match(lc, "^can (%a+)$")
        or string.match(lc, "^you have an? (%a+) speed$") or string.match(lc, "^have an? (%a+) speed$")
    if mode ~= nil and MOVEMENT_MODES[mode] then
        return "movement", mode
    end

    --"your wealth is 2+" / "wealth 2+" / "your wealth is at least 2" /
    --"wealth >= 2". ParseRequirement has already turned "2 or higher"
    --into "2+" (an "or" would otherwise split the clause in two).
    local w = lc
    w = string.gsub(w, "^you have%s+", "")
    w = string.gsub(w, "^your%s+", "")
    w = string.gsub(w, "^a%s+", "")
    local minimum = string.match(w, "^wealth is at least (%d+)$") or string.match(w, "^wealth of at least (%d+)$")
        or string.match(w, "^wealth is (%d+)%+$") or string.match(w, "^wealth of (%d+)%+$")
        or string.match(w, "^wealth (%d+)%+$") or string.match(w, "^wealth%s*>=%s*(%d+)$")
        or string.match(w, "^at least (%d+) wealth$") or string.match(w, "^(%d+)%+ wealth$")
    if minimum ~= nil then
        return "wealth", tostring(tonumber(minimum))
    end

    local s = lc
    s = string.gsub(s, "^you're%s+", "you are ")
    s = string.gsub(s, "^you have%s+", "have ")
    s = string.gsub(s, "^you can%s+", "")
    s = string.gsub(s, "^you are%s+", "")
    s = string.gsub(s, "^you%s+", "")
    s = string.gsub(s, "^the hero is%s+", "")
    s = string.gsub(s, "^is%s+", "")
    s = string.gsub(s, "^are%s+", "")
    s = string.gsub(s, "^the party is%s+", "")
    s = string.gsub(s, "^being%s+", "")
    s = trim(s)

    local function Strip(name, kind)
        name = trim(name)
        name = string.gsub(name, "^the%s+", "")
        if kind == "skill" then
            name = string.gsub(name, "%s+skill$", "")
        elseif kind == "language" then
            name = string.gsub(name, "%s+language$", "")
        end
        return TestRiders.NormalizeName(name)
    end

    local skillPatterns = { "^skilled in (.+)$", "^skilled with (.+)$", "^skilled at (.+)$", "^trained in (.+)$",
        "^have the (.+) skill$", "^have (.+) skill$", "^have the (.+)$", "^have (.+)$",
        "^skill:%s*(.+)$", "^skilled:%s*(.+)$", "^skill (.+)$" }
    for _, p in ipairs(skillPatterns) do
        local name = string.match(s, p)
        if name ~= nil then
            return "skill", Strip(name, "skill")
        end
    end

    local languagePatterns = { "^speak (.+)$", "^speaks (.+)$", "^know (.+)$", "^knows (.+)$", "^fluent in (.+)$",
        "^understand (.+)$", "^language:%s*(.+)$", "^speak:%s*(.+)$" }
    for _, p in ipairs(languagePatterns) do
        local name = string.match(s, p)
        if name ~= nil then
            return "language", Strip(name, "language")
        end
    end

    local kindredPatterns = { "^an (.+)$", "^a (.+)$", "^class:%s*(.+)$", "^ancestry:%s*(.+)$", "^kindred:%s*(.+)$",
        "^playing an (.+)$", "^playing a (.+)$", "^play an (.+)$", "^play a (.+)$" }
    for _, p in ipairs(kindredPatterns) do
        local name = string.match(s, p)
        if name ~= nil then
            return "kindred", Strip(name, "kindred")
        end
    end

    return nil
end

--"You are skilled in Magic, Alchemy or Psionics, or you are an Elementalist"
--  -> { text, alternatives = { { kind, name, text }, ... }, unrecognized = bool }
--kind is "skill", "language", "kindred" (class, subclass or ancestry) or
--"unknown" for a clause the grammar could not place (never met).
function TestRiders.ParseRequirement(text)
    local req = { text = trim(text), alternatives = {}, unrecognized = false }
    --"2 or higher" is one threshold, not two alternatives: fold it to "2+"
    --before "or" is read as the separator.
    local work = string.gsub(req.text, "(%d+)%s+[oO][rR]%s+%a+", function(n) return n .. "+" end)
    --commas and semicolons are alternatives too; "or" is the separator
    work = " " .. string.gsub(work, "[,;]", " or ") .. " "
    work = string.gsub(work, "%s+[oO][rR]%s+", "\1")
    local lastKind = nil
    for part in string.gmatch(work, "[^\1]+") do
        --", or you are ..." leaves a stray "or" at the head of the part
        local clause = trim((string.gsub(trim(part), "^[oO][rR]%s+", "")))
        if clause ~= "" then
            local lc = lower(clause)
            local kind, name = ParseRequirementClause(lc)
            if kind == nil and lastKind ~= nil then
                --a bare name in a list: "Magic, Alchemy or Psionics". Spell
                --the clause out so "Unlocked: you are skilled in Psionics"
                --reads as a sentence.
                kind, name = lastKind, TestRiders.NormalizeName((string.gsub(lc, "^the%s+", "")))
                local bare = trim((string.gsub(clause, "^[tT]he%s+", "")))
                if kind == "skill" then
                    clause = "you are skilled in " .. bare
                elseif kind == "language" then
                    clause = "you speak " .. bare
                elseif kind == "kindred" then
                    clause = cond(string.find(lower(bare), "^[aeiou]") ~= nil, "you are an ", "you are a ") .. bare
                elseif kind == "movement" then
                    if MOVEMENT_MODES[name] then
                        clause = "you can " .. bare
                    else
                        kind = nil
                    end
                else
                    --a wealth threshold has no bare-name form.
                    kind = nil
                end
            end
            if kind == nil then
                kind, name = "unknown", TestRiders.NormalizeName(lc)
                req.unrecognized = true
            end
            req.alternatives[#req.alternatives + 1] = { kind = kind, name = name, text = clause }
            lastKind = kind
        end
    end
    return req
end

--Parse one rider line into a rider record, or nil when the line is not a
--rider: { effect, text, requirement }. The caller adds its own line index.
function TestRiders.ParseRider(line)
    local effect, requirementText = TestRiders.ParseRiderLine(line)
    if effect == nil then
        return nil
    end
    local _, _, round = TestRiders.ParseRiderLine(line)
    return { effect = effect, text = requirementText, requirement = TestRiders.ParseRequirement(requirementText), round = round }
end

--Does a fact set satisfy a requirement? facts = { skill = { [name] = true },
--language = {...}, kindred = {...}, movement = {...}, wealth = n,
--round = n }, every name normalized. Returns met, and the text of the
--alternative that met it. A fact that ENDS with the wanted name also
--counts ("high elf" meets "you are an Elf").
function TestRiders.RequirementMet(req, facts)
    facts = facts or {}
    for _, alt in ipairs(req.alternatives or {}) do
        local set = facts[alt.kind]
        if alt.kind == "wealth" then
            local wealth = tonumber(facts.wealth)
            if wealth ~= nil and wealth >= (tonumber(alt.name) or math.huge) then
                return true, alt.text
            end
        elseif type(set) == "table" and alt.name ~= "" then
            if set[alt.name] then
                return true, alt.text
            end
            for factName, _ in pairs(set) do
                if string.sub(factName, -(#alt.name + 1)) == " " .. alt.name then
                    return true, alt.text
                end
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

--What a hero is, for rider requirements: { skill = { ["magic"] = true },
--language = { ["caelian"] = true }, kindred = { ["elementalist"] = true,
--["high elf"] = true }, movement = { ["climb"] = true }, wealth = 2 },
--every name normalized the way the parser does. Kindred is the class, its
--subclass(es) and the ancestry (with any subrace). "climb" means a climb
--speed at least the creature's walking speed (creature:IsClimber), so the
--climbing every hero can do at half speed does not count. The caller adds
--`round` when there is one (the montage).
function TestRiders.CreatureFacts(c)
    local facts = { skill = {}, language = {}, kindred = {}, movement = {} }
    if c == nil then
        return facts
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
    pcall(function()
        facts.wealth = c:CalculateNamedCustomAttribute("Wealth")
    end)
    local function Add(kind, name)
        if type(name) == "string" and name ~= "" then
            facts[kind][TestRiders.NormalizeName(name)] = true
        end
    end

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
    return facts
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
