--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_support_assessment_test.lua
--Exercises the bestiary AI support assessment (Monster AI/MonsterAISupport.lua)
--with stub monsters and registrations: each entry status, the band Malice
--weighting, triggers, minions, and the level rules.
local function try_get(self, key, default)
    if self[key] == nil then return default end
    return self[key]
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

dmhub = {
    GetModLoading = function() return {} end,
    Time = function() return 0 end,
}
gui = { ImplementationStatus = { WontImplement = 0, Unimplemented = 1, Bronze = 2, Silver = 3, Gold = 4 } }
CharacterResource = {
    actionResourceId = "action",
    maneuverResourceId = "maneuver",
    freeManeuverResourceId = "freemaneuver",
    triggerResourceId = "trigger",
}

local function MonsterTypeOf(token) return token.properties:try_get("monster_type", "") end
MonsterAI = {
    moves = {},
    villainActions = {},
    maliceAbilities = {},
    prompts = {},
    triggerHandlersByGuid = {},
    triggerHandlersByMonsterAbility = {},
    triggerHandlersByAbility = {},
    triggerHandlersByMonsterText = {},
    triggerHandlersByText = {},
}
function MonsterAI.MoveMatchesMonster(token, move)
    if move.monsters == nil then return true end
    for _, name in ipairs(move.monsters) do
        if name == MonsterTypeOf(token) then return true end
    end
    return false
end
function MonsterAI.MaliceAbilityMatchesMonster(token, registration)
    if registration.monsterGroups ~= nil then
        return registration.monsterGroups[1] == "Goblin"
    end
    return MonsterAI.MoveMatchesMonster(token, registration)
end
function MonsterAI.IsMinionSignatureAbility(ability)
    --fixture abilities are plain tables with a resource field, not ActivatedAbility.
    return ability.categorization == "Signature Ability" and (ability --[[@as table]]).resource == "action"
end
--the generic AI takes abilities flagged synth; "automate" ones only once
--the Gold check is skipped.
function MonsterAI:GetSynthesizedAbilityProfile(token, ability, options)
    if ability.synth then
        return { confidence = 0.99, reason = "Strike keyword" }
    end
    if ability.automate then
        if options ~= nil and options.ignoreImplementation then
            return { confidence = 0.97, reason = "damage behavior" }
        end
        return nil, "is not fully automated"
    end
    return nil, "uses unsupported target type self"
end

local function Ability(args)
    args.try_get = try_get
    args.resource = args.resource or "action"
    args.implementation = args.implementation or 4
    args.ActionResource = function(self) return self.resource end
    return args
end
local function Modifier(args)
    args.try_get = try_get
    return args
end
local function Monster(args)
    local props = {
        monster_type = args.type,
        minion = args.minion,
        innateActivatedAbilities = args.abilities or {},
        characterFeatures = args.features or {},
        try_get = try_get,
    }
    function props:GetActivatedAbilities()
        local result = {}
        for _, ability in ipairs(self.innateActivatedAbilities) do result[#result + 1] = ability end
        for _, name in ipairs({ "Grab", "Knockback", "Melee Free Strike" }) do
            result[#result + 1] = Ability{ name = name, categorization = "Common Ability" }
        end
        return result
    end
    function props:MonsterGroup()
        return args.group
    end
    return props
end

local chunk = assert(io.open("Monster AI/MonsterAISupport.lua", "r")):read("*a")
assert(load(chunk, "MonsterAISupport.lua"))()

local status = MonsterAI.supportStatus
local function EntryNamed(result, name)
    for _, entry in ipairs(result.entries) do
        if entry.name == name then return entry end
    end
end

--registrations
MonsterAI.moves["Spear Charge"] = { id = "Spear Charge", monsters = { "Goblin Warrior" }, abilities = { "Spear Charge" }, registeredAt = "MonsterAIGoblins.lua:10" }
MonsterAI.moves["Renamed"] = { id = "Renamed", monsters = { "Goblin Warrior" }, abilities = { "Old Name" } }
MonsterAI.moves["Knockback"] = { id = "Knockback", abilities = { "Knockback" } }
MonsterAI.villainActions["Kill!"] = { id = "Kill!", monsters = { "Goblin Warrior" }, abilities = { "Kill!" } }
MonsterAI.maliceAbilities["Goblin Mode"] = { id = "Goblin Mode", monsterGroups = { "Goblin" }, abilities = { "Goblin Mode" } }
MonsterAI.triggerHandlersByMonsterText["Goblin Warrior:Skitter"] = { id = "Skitter", monsters = { "Goblin Warrior" } }

local goblinGroup = {
    try_get = try_get,
    maliceAbilities = {
        Ability{ name = "Goblin Mode", categorization = "Malice" },
        Ability{ name = "Tiny Stabs", categorization = "Malice" },
        Ability{ name = "Lore", categorization = "Malice", implementation = 0 },
    },
}

local function TriggerFeature(name, mandatory)
    return Modifier{
        name = name,
        implementation = 4,
        modifiers = {
            Modifier{ behavior = "triggerdisplay", ability = Modifier{ name = name, trigger = "It takes damage." } },
            Modifier{ behavior = "trigger", triggeredAbility = Modifier{ name = "Inner " .. name, mandatory = mandatory, guid = name .. "-guid" } },
        },
    }
end

local warrior = MonsterAI.AssessSupport(Monster{
    type = "Goblin Warrior",
    group = goblinGroup,
    abilities = {
        Ability{ name = "Spear Charge", categorization = "Signature Ability" },
        Ability{ name = "Stab", categorization = "Heroic Ability", synth = true },
        Ability{ name = "Hide", categorization = "Maneuver", resource = "maneuver" },
        Ability{ name = "Blast", categorization = "Heroic Ability", automate = true, implementation = 2 },
        Ability{ name = "Kill!", categorization = "Villain Action", villainAction = "Villain Action 3" },
        Ability{ name = "Knockback", categorization = "Common Ability", resource = "maneuver" },
    },
    features = {
        TriggerFeature("Skitter", false),
        TriggerFeature("Bloodlust", true),
        TriggerFeature("Retort", false),
        --a trait that grants an ability (a signature carried this way).
        Modifier{ name = "Granted", modifiers = { Modifier{ behavior = "activated", activatedAbility = Ability{ name = "Granted Bite", categorization = "Signature Ability", synth = true } } } },
    },
})

check(EntryNamed(warrior, "Spear Charge").status == status.tailored, "own move claims its ability")
check(EntryNamed(warrior, "Spear Charge").source == "MonsterAIGoblins.lua:10", "source is the registration call site")
check(EntryNamed(warrior, "Stab").status == status.synthesized, "generic AI picks up a fully automated attack")
check(EntryNamed(warrior, "Hide").status == status.unused and EntryNamed(warrior, "Hide").kind == "Maneuver", "self maneuver is never used")
check(EntryNamed(warrior, "Blast").automationOnly == true, "blocked only by automation is flagged")
check(EntryNamed(warrior, "Knockback").status == status.generic, "shared moves count as generic")
check(EntryNamed(warrior, "Kill!").status == status.tailored, "registered villain action in slot 3")
check(EntryNamed(warrior, "Goblin Mode").status == status.tailored, "band Malice registration")
check(EntryNamed(warrior, "Tiny Stabs").status == status.unused, "unregistered Malice is never spent")
check(EntryNamed(warrior, "Lore").status == status.narrative and EntryNamed(warrior, "Lore").weight == 0, "narrative Malice is neutral")
check(math.abs(EntryNamed(warrior, "Goblin Mode").weight - 1) < 1e-9, "band Malice splits a weight of 2")
check(EntryNamed(warrior, "Skitter").status == status.tailored, "trigger handler found by display name")
check(EntryNamed(warrior, "Bloodlust").status == status.automatic and EntryNamed(warrior, "Bloodlust").weight == 0, "mandatory trigger is automatic")
check(EntryNamed(warrior, "Retort").status == status.unused, "optional trigger with no handler")
check(EntryNamed(warrior, "Granted Bite").status == status.synthesized, "trait-granted abilities are part of the kit")
check(warrior.unhandledTriggers == 1, "one unhandled trigger")
check(#warrior.stale == 1 and warrior.stale[1].missing == "Old Name", "stale registration reported")
check(warrior.handWritten, "hand-written AI found")
check(warrior.signatureUsable, "signature usable")
--one unhandled trigger keeps it below Tailored.
check(warrior.level == "Capable", "level is Capable, got " .. warrior.level)

--minion: the squad strike is its AI; other abilities are not used.
local minion = MonsterAI.AssessSupport(Monster{
    type = "Goblin Spinecleaver",
    minion = true,
    group = goblinGroup,
    abilities = {
        Ability{ name = "Axe", categorization = "Signature Ability" },
        Ability{ name = "Duck", categorization = "Maneuver", resource = "maneuver", synth = true },
    },
})
check(EntryNamed(minion, "Axe").status == status.squad, "minion signature is a squad strike")
check(EntryNamed(minion, "Duck").status == status.unused, "minions only use their signature")
check(minion.handWritten, "squad AI counts as hand-written")

--signature the AI cannot use: Minimal.
local stuck = MonsterAI.AssessSupport(Monster{
    type = "Odd Thing",
    abilities = { Ability{ name = "Weird", categorization = "Signature Ability" } },
})
check(stuck.level == "Minimal" and not stuck.signatureUsable, "unusable signature is Minimal")

--fully covered by the generic AI alone: capped at Capable.
local generic = MonsterAI.AssessSupport(Monster{
    type = "Plain Brute",
    abilities = { Ability{ name = "Smash", categorization = "Signature Ability", synth = true } },
})
check(generic.coverage == 1 and generic.level == "Capable", "generic-only AI tops out at Capable")

--everything hand-written and handled: Tailored.
MonsterAI.moves["Claw"] = { id = "Claw", monsters = { "Ghoul" }, abilities = { "Claw" } }
local ghoul = MonsterAI.AssessSupport(Monster{
    type = "Ghoul",
    abilities = { Ability{ name = "Claw", categorization = "Signature Ability" } },
})
check(ghoul.level == "Tailored", "fully hand-written is Tailored")

print(string.format("ai_support_assessment_test: %d checks passed", checks))
