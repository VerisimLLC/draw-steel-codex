local mod = dmhub.GetModLoading()

--How much of a monster's kit the Monster AI will actually use, worked out
--from a bestiary entry with no token and no combat. It reads the loaded
--registries (moves, villain actions, Malice, trigger handlers) and asks the
--generic AI (GetSynthesizedAbilityProfile) about every ability nothing
--hand-written claims. The Encounter of the Week bestiary assessment
--(EncounterOfTheWeek/EncounterMonsterAssessment.lua) turns this into a
--verdict. Keep it in step with the registries: a new registration kind the
--AI runs must be counted here too, or monsters using it will read as
--unsupported.

--- How one kit entry fares with the AI.
---   tailored    - hand-written AI for this monster (or its band)
---   generic     - a hand-written move every monster shares (Grab, Knockback...)
---   squad       - a minion's signature, used as a squad strike
---   synthesized - the generic AI uses it, planned from its targeting data
---   automatic   - a mandatory trigger: it fires by itself, no decision needed
---   narrative   - role play only: there is nothing for the AI to do
---   unused      - the AI never uses it
MonsterAI.supportStatus = {
    tailored = "tailored",
    generic = "generic",
    squad = "squad",
    synthesized = "synthesized",
    automatic = "automatic",
    narrative = "narrative",
    unused = "unused",
}

--- Overall AI levels, weakest first. rank indexes this list.
MonsterAI.supportLevels = { "Minimal", "Basic", "Capable", "Tailored" }

--Weights for the coverage figure: how much each kind of kit entry matters
--to how the monster plays.
local g_kindWeights = {
    ["Signature Ability"] = 3,
    ["Villain Action"] = 3,
    ["Heroic Ability"] = 2,
    ["Main Action"] = 2,
    --shared by the whole band and spent one per turn, so a band's Malice
    --list counts this much in total, split between its entries.
    ["Malice"] = 2,
    ["Maneuver"] = 1,
    ["Other Ability"] = 1,
    ["Triggered Action"] = 1,
}

--Coverage needed for each level (see AssessSupport for the other conditions).
MonsterAI.supportTailoredCoverage = 0.9
MonsterAI.supportCapableCoverage = 0.6

--- @class MonsterAISupportEntry
--- @field name string
--- @field kind string One of the g_kindWeights keys.
--- @field weight number 0 for entries that do not count (automatic triggers).
--- @field status string A MonsterAI.supportStatus value.
--- @field usable boolean
--- @field reason string Plain-language explanation of the status.
--- @field implementation number Automation level (gui.ImplementationStatus).
--- @field move? string The registration id that handles it.
--- @field source? string "file.lua:line" of the hand-written handler.
--- @field confidence? number Generic AI confidence.
--- @field automationOnly? boolean Generic AI would use it once fully automated.
--- @field disabled? boolean Its move is switched off in the Monster AI panel.

--- @class MonsterAISupportRegistration
--- @field kind string "Move", "Villain Action", "Malice", "Trigger" or "Prompt".
--- @field id string
--- @field description string
--- @field abilities string[]
--- @field source? string

--- @class MonsterAISupportStale
--- @field kind string
--- @field id string
--- @field missing string The ability or trigger name the monster lacks.

--- @class MonsterAISupportAssessment
--- @field monsterType string
--- @field minion boolean
--- @field entries MonsterAISupportEntry[]
--- @field registrations MonsterAISupportRegistration[]
--- @field stale MonsterAISupportStale[]
--- @field handWritten boolean Hand-written AI targets this monster type (band Malice alone does not count; a minion's squad strike does).
--- @field signatureUsable boolean
--- @field villainActionsHandled boolean
--- @field unhandledTriggers integer
--- @field coverage number 0-1, weighted.
--- @field level string A MonsterAI.supportLevels value.
--- @field rank integer Index of level in MonsterAI.supportLevels.

--"file.lua:line" for a registration callback. Chunk names look like
--"Monster AI : MonsterAIGoblins".
local function SourceOf(fn)
    if type(fn) ~= "function" then
        return nil
    end
    local info = debug.getinfo(fn, "S")
    if info == nil then
        return nil
    end
    local file = string.match(info.source or "", ":%s*(.-)%s*$") or info.short_src or "?"
    return string.format("%s.lua:%d", file, info.linedefined or 0)
end

--registeredAt is the Register* call site (MonsterAI.lua stamps it); the
--callbacks' own definitions are a fallback, though for shared generators
--(GenerateStandardStrikeScoreFunction) they point at the generator.
local function RegistrationSource(registration)
    return registration.registeredAt or SourceOf(registration.score)
        or SourceOf(registration.handler) or SourceOf(registration.execute)
end

local function ListsMonsterType(registration, monsterType)
    for _, name in ipairs(registration.monsters or {}) do
        if name == monsterType then
            return true
        end
    end
    return false
end

--The generic AI's reasons for passing an ability over
--(GetSynthesizedAbilityProfile), put for an encounter author.
local g_plainReasons = {
    { "^uses unsupported target type self$", "it only targets itself, and the generic AI only uses attacks" },
    { "^uses unsupported target type emptyspace$", "it targets an empty space, which the generic AI can't plan" },
    { "^uses unsupported target type (.+)$", "the generic AI can't plan its %1 targeting" },
    { "^requires a cast%-time choice$", "it needs a choice made while casting" },
    { "^requires choosing invocation order$", "it needs a choice made while casting (which part to resolve first)" },
    { "^selects an invoked ability dynamically$", "it needs a choice made while casting (which ability to use)" },
    { "^has no AI prompt handler for (.+)$", "it asks for a choice (%1) the AI has no handler for" },
    { "^has no confidently harmful effect$", "the generic AI only uses abilities that clearly harm enemies" },
    { "^has no automated behaviors$", "it has no automated effects" },
    { "^is a (.+)$", "the generic AI doesn't use %1 abilities" },
}

local function PlainReason(why)
    why = tostring(why or "is not supported")
    for _, entry in ipairs(g_plainReasons) do
        local plain, count = string.gsub(why, entry[1], entry[2])
        if count > 0 then
            return plain
        end
    end
    return "it " .. why
end

--- @param ability ActivatedAbility
--- @return string
local function AbilityKind(ability)
    local cat = ability.categorization
    if cat == "Signature Ability" or cat == "Heroic Ability" then
        return cat
    end
    local resource = ability:ActionResource()
    if resource == CharacterResource.maneuverResourceId or resource == CharacterResource.freeManeuverResourceId then
        return "Maneuver"
    elseif resource == CharacterResource.actionResourceId then
        return "Main Action"
    end
    return "Other Ability"
end

local function IsTriggeredAbility(ability)
    local cat = ability.categorization
    return cat == "Trigger" or cat == "Triggered Ability"
        or ability:ActionResource() == CharacterResource.triggerResourceId
end

local function IsVillainAction(ability)
    return ability:try_get("villainAction") ~= nil or ability.categorization == "Villain Action"
end

local function IsMalice(ability)
    return ability.categorization == "Malice" or ability.categorization == "Malice Ability"
end

--The monster's own abilities: its innate list plus any its traits grant
--("activated" modifiers -- some monsters carry their signature this way).
--Standard abilities every creature has are left out.
--- @return ActivatedAbility[]
local function OwnAbilities(props)
    local result = {}
    local seen = {}
    local function Add(ability)
        if ability ~= nil and not seen[ability.name] then
            seen[ability.name] = true
            result[#result + 1] = ability
        end
    end
    for _, ability in ipairs(props:try_get("innateActivatedAbilities", {})) do
        Add(ability)
    end
    for _, feature in ipairs(props:try_get("characterFeatures", {})) do
        for _, modifier in ipairs(feature:try_get("modifiers", {})) do
            if modifier:try_get("behavior") == "activated" then
                Add(modifier:try_get("activatedAbility"))
            end
        end
    end
    return result
end

--Gather the monster's own triggered actions from its traits. A trait usually
--carries a display entry (what the stat block prints) beside the modifier
--that actually fires; when a trait has a single display entry, everything it
--fires is folded into it, since the names often differ.
--Returns a list of {name, names, guids, text, displayed, hasTrigger,
--allMandatory, implementation}.
local function CollectTriggers(props)
    local result = {}
    local byName = {}

    local function EntryFor(name)
        local key = string.lower(name or "")
        local entry = byName[key]
        if entry == nil then
            entry = {
                name = name,
                names = {},
                guids = {},
                displayed = false,
                hasTrigger = false,
                allMandatory = true,
                implementation = gui.ImplementationStatus.Unimplemented,
            }
            byName[key] = entry
            result[#result + 1] = entry
        end
        return entry
    end

    for _, feature in ipairs(props:try_get("characterFeatures", {})) do
        local displays = {}
        local fired = {}
        for _, modifier in ipairs(feature:try_get("modifiers", {})) do
            local behavior = modifier:try_get("behavior")
            if behavior == "triggerdisplay" then
                local display = modifier:try_get("ability")
                if display ~= nil then
                    displays[#displays + 1] = display
                end
            elseif behavior == "trigger" then
                local triggered = modifier:try_get("triggeredAbility")
                if triggered ~= nil then
                    local mandatory = triggered:try_get("mandatory", true)
                    fired[#fired + 1] = {
                        name = triggered.name,
                        guid = triggered:try_get("guid"),
                        mandatory = mandatory == true or mandatory == "local",
                    }
                end
            elseif behavior == "powertabletrigger" then
                fired[#fired + 1] = {
                    name = modifier.name,
                    guid = modifier:try_get("guid"),
                    mandatory = modifier:try_get("type") == "passive",
                }
            end
        end

        local implementation = feature:try_get("implementation", gui.ImplementationStatus.Unimplemented)
        for _, display in ipairs(displays) do
            local entry = EntryFor(display.name)
            entry.displayed = true
            entry.text = display:try_get("trigger")
            entry.implementation = implementation
            entry.names[#entry.names + 1] = display.name
        end

        for _, info in ipairs(fired) do
            --one display in the trait: whatever fires belongs to it.
            local entry = (#displays == 1) and EntryFor(displays[1].name) or EntryFor(info.name)
            if #displays ~= 1 then
                entry.implementation = implementation
            end
            entry.hasTrigger = true
            entry.names[#entry.names + 1] = info.name
            if info.guid ~= nil then
                entry.guids[#entry.guids + 1] = info.guid
            end
            if not info.mandatory then
                entry.allMandatory = false
            end
        end
    end

    --a trait's mandatory machinery with nothing printed is not a triggered
    --action the reader would recognize, so it is not listed.
    local filtered = {}
    for _, entry in ipairs(result) do
        if entry.displayed or (entry.hasTrigger and not entry.allMandatory) then
            filtered[#filtered + 1] = entry
        end
    end
    return filtered
end

--The registered trigger handler for one of the monster's triggers, using
--FindTriggerHandler's lookup order: guid, monster-qualified ability name,
--ability name, monster-qualified trigger text, trigger text.
local function FindTriggerHandlerFor(fakeToken, monsterType, triggerEntry)
    local ai = MonsterAI
    local function Matching(handler)
        if handler ~= nil and ai.MoveMatchesMonster(fakeToken, handler, true) then
            return handler
        end
    end

    for _, guid in ipairs(triggerEntry.guids) do
        local handler = Matching(ai.triggerHandlersByGuid[guid])
        if handler ~= nil then
            return handler
        end
    end

    local names = {}
    for _, name in ipairs(triggerEntry.names) do
        names[#names + 1] = name
    end
    if triggerEntry.text ~= nil then
        names[#names + 1] = triggerEntry.text
    end

    for _, name in ipairs(names) do
        local handler = Matching(ai.triggerHandlersByMonsterAbility[monsterType .. ":" .. name])
            or Matching(ai.triggerHandlersByAbility[name])
            or Matching(ai.triggerHandlersByMonsterText[monsterType .. ":" .. name])
            or Matching(ai.triggerHandlersByText[name])
        if handler ~= nil then
            return handler
        end
    end
    return nil
end

--- Assess a monster's AI support from its properties (a bestiary entry's
--- properties work: no token is needed).
--- @param props creature
--- @return MonsterAISupportAssessment
function MonsterAI.AssessSupport(props)
    local ai = MonsterAI
    local status = ai.supportStatus
    local monsterType = props:try_get("monster_type", "")
    local minion = props:try_get("minion", false) == true

    --the matchers only read token.properties (and token.valid), so a
    --stand-in table is all a bestiary entry needs.
    ---@diagnostic disable-next-line: missing-fields
    local fakeToken = { properties = props, valid = true } --[[@as CharacterToken]]

    --every ability name the creature has, standard ones included, since a
    --move only runs when all of its abilities are present.
    local present = {}
    local allAbilities = {}
    pcall(function() allAbilities = props:GetActivatedAbilities() end)
    for _, ability in ipairs(allAbilities) do
        present[ability.name] = true
    end

    ---@type MonsterAISupportAssessment
    local result = {
        monsterType = monsterType,
        minion = minion,
        entries = {},
        registrations = {},
        stale = {},
        handWritten = false,
        signatureUsable = false,
        villainActionsHandled = true,
        unhandledTriggers = 0,
        coverage = 0,
        level = "Minimal",
        rank = 1,
    }

    local registrationsSeen = {}
    local function NoteRegistration(kind, registration)
        if registrationsSeen[registration] then
            return
        end
        registrationsSeen[registration] = true
        if kind ~= "Malice" then
            result.handWritten = true
        end
        result.registrations[#result.registrations + 1] = {
            kind = kind,
            id = registration.id or "?",
            description = registration.description or "",
            abilities = registration.abilities or {},
            source = RegistrationSource(registration),
        }
    end

    local function AddEntry(entry)
        entry.weight = entry.weight or g_kindWeights[entry.kind] or 1
        --Narrative entries have nothing to automate or decide: neutral, as
        --they are in the automation status.
        if entry.status == status.unused and entry.implementation == gui.ImplementationStatus.WontImplement then
            entry.status = status.narrative
            entry.reason = "Narrative only: there is nothing for the AI to do."
            entry.weight = 0
        end
        result.entries[#result.entries + 1] = entry
        return entry
    end

    --moves claiming each ability, split into this monster's own and generic.
    local tailoredMoveFor = {}
    local genericMoveFor = {}
    for _, move in pairs(ai.moves) do
        local own = ListsMonsterType(move, monsterType)
        if own or move.monsters == nil then
            local allPresent = #(move.abilities or {}) > 0
            local missing = nil
            for _, name in ipairs(move.abilities or {}) do
                if not present[name] then
                    allPresent = false
                    missing = missing or name
                end
            end
            if allPresent then
                for _, name in ipairs(move.abilities) do
                    if own then
                        tailoredMoveFor[name] = tailoredMoveFor[name] or move
                    else
                        genericMoveFor[name] = genericMoveFor[name] or move
                    end
                end
            elseif own and missing ~= nil then
                result.stale[#result.stale + 1] = { kind = "Move", id = move.id or "?", missing = missing }
            end
        end
    end

    local villainFor = {}
    for _, action in pairs(ai.villainActions) do
        if ListsMonsterType(action, monsterType) then
            local name = (action.abilities or {})[1]
            if name ~= nil and present[name] then
                villainFor[name] = action
            elseif name ~= nil then
                result.stale[#result.stale + 1] = { kind = "Villain Action", id = action.id or "?", missing = name }
            end
        end
    end

    local maliceFor = {}
    for _, registration in pairs(ai.maliceAbilities) do
        local name = (registration.abilities or {})[1]
        if name ~= nil and ai.MaliceAbilityMatchesMonster(fakeToken, registration, true) then
            maliceFor[name] = registration
        end
    end

    local function ImplementationOf(item)
        local value = nil
        pcall(function() value = item:try_get("implementation", gui.ImplementationStatus.Unimplemented) end)
        return tonumber(value) or gui.ImplementationStatus.Unimplemented
    end

    --Malice is the band's (the monster group's) plus any of the monster's own.
    local maliceNames = {}
    local function AddMalice(item)
        if maliceNames[item.name] then
            return
        end
        maliceNames[item.name] = true
        local registration = maliceFor[item.name]
        local entry = {
            name = item.name,
            kind = "Malice",
            implementation = ImplementationOf(item),
        }
        if registration ~= nil then
            local banded = registration.monsters ~= nil or registration.monsterGroups ~= nil
            if banded then
                NoteRegistration("Malice", registration)
            end
            entry.status = banded and status.tailored or status.generic
            entry.usable = true
            entry.move = registration.id
            entry.source = RegistrationSource(registration)
            entry.reason = "Spent at the start of a monster turn when it scores well."
        else
            entry.status = status.unused
            entry.usable = false
            entry.reason = "No Malice AI is registered for it, so it is never spent."
        end
        AddEntry(entry)
    end

    local triggerAbilities = {}

    --triggered actions from the traits. A trait's triggered action can also
    --grant an ability of the same name; the trigger entry stands for both.
    local triggers = CollectTriggers(props)
    local traitTriggerNames = {}
    for _, trigger in ipairs(triggers) do
        for _, name in ipairs(trigger.names) do
            traitTriggerNames[string.lower(name)] = true
        end
    end

    for _, ability in ipairs(OwnAbilities(props)) do
        local implementation = ImplementationOf(ability)
        if IsVillainAction(ability) then
            local registration = villainFor[ability.name]
            local slot = ability:try_get("villainAction")
            local entry = {
                name = ability.name,
                kind = "Villain Action",
                implementation = implementation,
            }
            if registration == nil then
                entry.status = status.unused
                entry.usable = false
                entry.reason = "No villain-action AI is registered for it, so it is never used."
            elseif slot ~= "Villain Action 1" and slot ~= "Villain Action 2" and slot ~= "Villain Action 3" then
                entry.status = status.unused
                entry.usable = false
                entry.reason = "It is not tagged Villain Action 1-3, and the AI only uses those (in rounds 1-3)."
            else
                NoteRegistration("Villain Action", registration)
                entry.status = status.tailored
                entry.usable = true
                entry.move = registration.id
                entry.source = RegistrationSource(registration)
                entry.reason = string.format("Hand-written AI uses it as %s.", slot)
            end
            if not entry.usable then
                result.villainActionsHandled = false
            end
            AddEntry(entry)
        elseif IsMalice(ability) then
            AddMalice(ability)
        elseif traitTriggerNames[string.lower(ability.name)] then
            --listed with the triggered actions below.
        elseif IsTriggeredAbility(ability) then
            triggerAbilities[#triggerAbilities + 1] = ability
        else
            local entry = {
                name = ability.name,
                kind = AbilityKind(ability),
                implementation = implementation,
            }
            local tailored = tailoredMoveFor[ability.name]
            local generic = genericMoveFor[ability.name]
            if minion then
                if ai.IsMinionSignatureAbility(ability) then
                    --the squad strike is purpose-built AI for every minion.
                    result.handWritten = true
                    entry.status = status.squad
                    entry.usable = true
                    entry.reason = "The squad moves together and strikes with it."
                else
                    entry.status = status.unused
                    entry.usable = false
                    entry.reason = "Minions only use their signature ability, as a squad strike."
                end
            elseif tailored ~= nil then
                NoteRegistration("Move", tailored)
                entry.status = status.tailored
                entry.usable = true
                entry.move = tailored.id
                entry.source = RegistrationSource(tailored)
                entry.disabled = tailored.disabledForMonsters ~= nil and tailored.disabledForMonsters[monsterType] == true
                entry.reason = string.format("Hand-written AI (move \"%s\").", tailored.id or "?")
            elseif generic ~= nil then
                entry.status = status.generic
                entry.usable = true
                entry.move = generic.id
                entry.source = RegistrationSource(generic)
                entry.reason = string.format("Shared AI move \"%s\".", generic.id or "?")
            else
                local profile, why = ai:GetSynthesizedAbilityProfile(fakeToken, ability)
                if profile ~= nil then
                    entry.status = status.synthesized
                    entry.usable = true
                    entry.confidence = profile.confidence
                    entry.reason = string.format("Generic AI (%s, %d%% confidence).", profile.reason or "harmful effect", math.floor(profile.confidence * 100 + 0.5))
                else
                    entry.status = status.unused
                    entry.usable = false
                    local plain = PlainReason(why)
                    entry.reason = string.upper(string.sub(plain, 1, 1)) .. string.sub(plain, 2) .. "."
                    if why == "is not fully automated" then
                        entry.automationOnly = ai:GetSynthesizedAbilityProfile(fakeToken, ability, { ignoreImplementation = true }) ~= nil
                        if entry.automationOnly then
                            entry.reason = "The generic AI would use it once it is fully automated."
                        end
                    end
                end
            end
            AddEntry(entry)
        end
    end

    local group = nil
    pcall(function() group = props:MonsterGroup() end)
    if group ~= nil then
        for _, malice in ipairs(group:try_get("maliceAbilities", {})) do
            AddMalice(malice)
        end
    end

    --plus any trigger-costed abilities of its own.
    for _, ability in ipairs(triggerAbilities) do
        triggers[#triggers + 1] = {
            name = ability.name,
            names = { ability.name },
            guids = { ability:try_get("guid") },
            displayed = true,
            hasTrigger = true,
            allMandatory = false,
            implementation = ImplementationOf(ability),
        }
    end

    local triggerNames = {}
    for _, trigger in ipairs(triggers) do
        for _, name in ipairs(trigger.names) do
            triggerNames[name] = true
        end
        if trigger.text ~= nil then
            triggerNames[trigger.text] = true
        end

        local entry = {
            name = trigger.name,
            kind = "Triggered Action",
            implementation = trigger.implementation,
        }
        local handler = FindTriggerHandlerFor(fakeToken, monsterType, trigger)
        if handler ~= nil then
            if handler.monsters ~= nil or #(handler.abilityGuids or {}) > 0 then
                NoteRegistration("Trigger", handler)
            end
            entry.status = status.tailored
            entry.usable = true
            entry.move = handler.id
            entry.source = RegistrationSource(handler)
            entry.reason = "Hand-written AI decides when to take it."
        elseif not trigger.hasTrigger then
            entry.status = status.unused
            entry.usable = false
            entry.reason = "Not automated: nothing fires, so it never happens."
        elseif trigger.allMandatory then
            entry.status = status.automatic
            entry.usable = true
            entry.weight = 0
            entry.reason = "Fires by itself; no decision is needed."
        else
            entry.status = status.unused
            entry.usable = false
            entry.reason = "No AI handler: the AI never takes this optional trigger."
            result.unhandledTriggers = result.unhandledTriggers + 1
        end
        AddEntry(entry)
    end

    --trigger handlers written for this monster that match nothing it has.
    local prefix = monsterType .. ":"
    for _, registry in ipairs({ ai.triggerHandlersByMonsterAbility, ai.triggerHandlersByMonsterText }) do
        for key, handler in pairs(registry) do
            if monsterType ~= "" and string.sub(key, 1, #prefix) == prefix then
                local name = string.sub(key, #prefix + 1)
                if not triggerNames[name] and not present[name] then
                    result.stale[#result.stale + 1] = { kind = "Trigger", id = handler.id or "?", missing = name }
                end
            end
        end
    end

    --prompt handlers written specifically for this monster.
    for key, prompt in pairs(ai.prompts) do
        if monsterType ~= "" and string.sub(key, 1, #prefix) == prefix then
            NoteRegistration("Prompt", prompt)
        end
    end

    --split the band's Malice weight between its (non-narrative) entries.
    local maliceCount = 0
    for _, entry in ipairs(result.entries) do
        if entry.kind == "Malice" and entry.weight > 0 then
            maliceCount = maliceCount + 1
        end
    end
    for _, entry in ipairs(result.entries) do
        if entry.kind == "Malice" and entry.weight > 0 then
            entry.weight = g_kindWeights["Malice"] / maliceCount
        end
    end

    --the verdict on the AI side alone.
    local total, covered = 0, 0
    local hasSignature, hasMainAction, mainActionUsable = false, false, false
    for _, entry in ipairs(result.entries) do
        total = total + entry.weight
        if entry.usable then
            covered = covered + entry.weight
        end
        if entry.kind == "Signature Ability" then
            hasSignature = true
            if entry.usable then
                result.signatureUsable = true
            end
        elseif entry.kind == "Main Action" or entry.kind == "Heroic Ability" then
            hasMainAction = true
            if entry.usable then
                mainActionUsable = true
            end
        end
    end
    if not hasSignature and hasMainAction then
        result.signatureUsable = mainActionUsable
    end
    result.coverage = total > 0 and covered / total or 0

    local rank = 1
    if result.signatureUsable then
        rank = 2
        if result.coverage >= ai.supportCapableCoverage and result.villainActionsHandled then
            rank = 3
            if result.handWritten and result.unhandledTriggers == 0
                and result.coverage >= ai.supportTailoredCoverage then
                rank = 4
            end
        end
    end
    result.rank = rank
    result.level = ai.supportLevels[rank]

    return result
end

--Recent assessments by monster id, so a bestiary search can rate every
--monster without redoing the work on each keystroke. A Lua reload re-runs
--this file and starts it empty; callers that know a monster changed (its
--bestiary row refreshing) call InvalidateSupport, and the time limit catches
--the rest.
local g_supportMemo = {}
local g_supportMemoSeconds = 60

--- AssessSupport for a bestiary entry, remembered for a few seconds.
--- @param monsterid string
--- @return MonsterAISupportAssessment|nil
function MonsterAI.AssessBestiarySupport(monsterid)
    local now = dmhub.Time()
    local cached = g_supportMemo[monsterid]
    if cached ~= nil and now - cached.time < g_supportMemoSeconds then
        return cached.result
    end

    local asset = assets.monsters[monsterid]
    if asset == nil or asset.properties == nil then
        return nil
    end
    local props = asset.properties
    local isMonster = false
    pcall(function() isMonster = props:IsMonster() end)
    if not isMonster then
        return nil
    end

    local ok, result = pcall(MonsterAI.AssessSupport, props)
    if not ok then
        print(string.format("AISUPPORT:: assessment failed for %s: %s", tostring(monsterid), tostring(result)))
        return nil
    end
    g_supportMemo[monsterid] = { time = now, result = result }
    return result
end

--- Forget a remembered assessment (or all of them when monsterid is nil).
--- @param monsterid? string
function MonsterAI.InvalidateSupport(monsterid)
    if monsterid == nil then
        g_supportMemo = {}
    else
        g_supportMemo[monsterid] = nil
    end
end
