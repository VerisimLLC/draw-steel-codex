local mod = dmhub.GetModLoading()

--Fills History at the source. Each ability cast that posts a card to the log gets an
--entry, prompted triggers included. A cast that shares its parent's card joins the
--parent's entry. An automatic trigger gets an entry only if it changed something, and
--that entry names the cast that set it off, so the tray can nest it under that row:
--the two may be written by different clients, in either order.
--
--An entry is written when the cast ends, so it holds the roll and a cancelled cast
--leaves nothing. It keeps the time the cast began, which sets its place in the list.

--- A creature as it looked at the time, so renames and deletions never rewrite History.
--- @class HistoryCreature
--- @field id string Token id.
--- @field name string
--- @field img string Portrait image id.
--- @field rect? number[] Part of the portrait to show: x1, y1, x2, y2.
--- @field hero boolean True on the heroes' side.
--- @field secret? boolean True when players may not see the name.
--- @field tier? integer On a target: the tier of the roll against it.
--- @field turnid? string On a turn owner: the initiative id, which identifies the turn.
--- @field group? integer On a turn owner: how many creatures share this turn.
--- @field minions? boolean On a turn owner: true when the group is minions.
--- @field taken? number On a target: damage that landed, soaked included.
--- @field healed? number On a target: Stamina regained.
--- @field soaked? number On a target: how much of the damage temporary Stamina took.
--- @field types? table<string, number> On a target: damage by type, typed damage only.
--- @field immunity? {damagetype: string, amount: number} On a target: what immunity took off, or weakness added (negative).
--- @field pool? {before: number, after: number} On a target: temporary Stamina that grew.

--- The creature a token shows now, as plain data for an entry.
--- @param token CharacterToken
--- @return HistoryCreature
function History.Creature(token)
    local name = token.name
    if name == nil or name == "" then
        name = token.description
    end
    local rect = token.portraitRect
    return {
        id = token.charid,
        name = name,
        img = token.portrait,
        rect = rect ~= nil and {rect.x1, rect.y1, rect.x2, rect.y2} or nil,
        hero = token.playerControlled or (token.properties ~= nil and token.properties:IsHero()),
        secret = token.namePrivate or nil,
    }
end

--Whose turn it is, for the heading the entry sits under. Nil between turns.
local function TurnOwner(q)
    local initiativeid = q.currentTurn
    if not initiativeid then
        return nil
    end
    local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid, dmhub.allTokens)
    if #tokens == 0 then
        return nil
    end
    local owner = History.Creature(tokens[1])
    owner.turnid = initiativeid
    owner.hero = q:IsEntryPlayer(initiativeid) == true
    if #tokens > 1 then
        owner.name = q:DescribeEntry(initiativeid)
        owner.group = #tokens
        owner.minions = tokens[1].properties.minion or nil
    end
    return owner
end

--- Adds the encounter, round and turn to an entry. Does nothing out of combat.
--- @param entry HistoryEntry
function History.AddCombatFacts(entry)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return
    end
    entry.encounter = q.guid
    entry.round = q.round
    entry.turn = q.turnNumber
    entry.owner = TurnOwner(q)
end

--The kind of action an ability is, as an id: the tray holds the words.
local function ActionKind(ability)
    if ability:IsTriggeredAction() or ability.typeName == "TriggeredAbility" then
        return "triggered"
    end
    if string.find(string.lower(ability.name), "free strike", 1, true) ~= nil then
        return "freestrike"
    end
    local resource = ability:ActionResource()
    if resource == CharacterResource.actionResourceId then
        return "main"
    end
    if resource == CharacterResource.maneuverResourceId or resource == CharacterResource.freeManeuverResourceId then
        return "maneuver"
    end
    return nil
end

local function AddTarget(entry, seen, token)
    if token ~= nil and token.valid and seen[token.charid] == nil then
        local target = History.Creature(token)
        seen[token.charid] = target
        entry.targets[#entry.targets + 1] = target
    end
end

--Entries of casts still resolving, by the cast's options table. Weak, so a cast that
--dies without finishing leaves nothing behind.
local g_casts = setmetatable({}, {__mode = "k"})

--The same states by ActivatedAbilityCast: what a damage or heal can see of its cast.
--An invoked ability shares its parent's cast, so its results join the parent's row.
local g_byCast = setmetatable({}, {__mode = "k"})

--A cast with no row of its own that runs inside one with a row. Anything it sets off
--names this cast, so the row answers to its id too.
local function JoinParentRow(options)
    local symbols = options.symbols
    if symbols == nil or symbols.cast == nil or symbols.castid == nil then
        return
    end
    local parent = g_byCast[symbols.cast]
    if parent ~= nil then
        parent.entry.aliases = parent.entry.aliases or {}
        table.insert(parent.entry.aliases, symbols.castid)
    end
end

local function BeginCastState(entry, targets, options)
    local state = {entry = entry, seen = {}}
    g_casts[options] = state
    local cast = options.symbols ~= nil and options.symbols.cast or nil
    if cast ~= nil then
        --a cast with its own row takes over a shared cast until it ends.
        state.cast = cast
        state.parent = g_byCast[cast]
        g_byCast[cast] = state
    end
    return state
end

local function CastBegan(ability, casterToken, targets, options)
    if not History.Enabled() or options.dismiss then
        return
    end

    --a card from an earlier cast means this one shares it (an invoked ability).
    local card = options.chatMessage
    local symbols = options.symbols
    local sharesCard = card ~= nil and (symbols == nil or card.castid ~= symbols.castid)
    local automatic = ability.typeName == "TriggeredAbility" and not ability:ShowChatMessageOnCast()
    if sharesCard or (not automatic and not ability:ShowChatMessageOnCast()) then
        JoinParentRow(options)
        return
    end

    if automatic then
        --most automatic triggers change nothing: this stays cheap until one does.
        local state = BeginCastState({
            id = symbols ~= nil and symbols.castid or nil,
            t = dmhub.serverTimeMilliseconds,
            kind = "trigger",
            map = casterToken.mapid,
            cause = symbols ~= nil and symbols.causecastid or nil,
            ability = {
                name = ability.name,
                free = ability:ActionResource() == CharacterResource.freeTriggeredActionResourceId or nil,
            },
            targets = {},
        }, targets, options)
        state.automatic = true
        state.actorToken = dmhub.GetCharacterById(ActivatedAbility.GetLogActorId(casterToken, options)) or casterToken
        return
    end

    local actor = dmhub.GetCharacterById(ActivatedAbility.GetLogActorId(casterToken, options)) or casterToken
    local state = BeginCastState({
        id = symbols ~= nil and symbols.castid or nil,
        t = dmhub.serverTimeMilliseconds,
        kind = "action",
        map = casterToken.mapid,
        actor = History.Creature(actor),
        ability = {name = ability.name, icon = ability:try_get("iconid"), action = ActionKind(ability)},
        targets = {},
    }, targets, options)
    History.AddCombatFacts(state.entry)

    --snapshot now: a target may be gone by the time the cast ends.
    for _, target in ipairs(targets) do
        AddTarget(state.entry, state.seen, target.token)
    end
    if ability.targetType == "self" and #targets == 0 then
        AddTarget(state.entry, state.seen, casterToken)
    end
end

--True if anything on the entry shows a change. More families join this as they land.
local function ChangedTheTable(entry)
    for _, who in ipairs(entry.targets) do
        if (who.taken or 0) > 0 or (who.healed or 0) > 0 or who.pool ~= nil
            or (who.immunity ~= nil and who.immunity.amount ~= 0) then
            return true
        end
    end
    return false
end

local function WriteTrigger(state)
    local entry = state.entry
    if not ChangedTheTable(entry) then
        return
    end
    local actor = state.actorToken
    if actor ~= nil and actor.valid then
        entry.actor = History.Creature(actor)
    end
    History.AddCombatFacts(entry)
    History.Write(entry)
end

local function AddRoll(entry, cast)
    local total = cast:try_get("total")
    if total == nil then
        return
    end
    entry.roll = {
        total = total,
        low = cast:try_get("lowRoll"),
        high = cast:try_get("highRoll"),
        edges = cast.boonsApplied,
        banes = cast.banesApplied,
        tier = cast.tier,
    }
end

local function CastFinished(ability, casterToken, options)
    local state = g_casts[options]
    if state == nil then
        return
    end
    g_casts[options] = nil
    state.finished = true
    if state.cast ~= nil then
        g_byCast[state.cast] = state.parent
    end
    if options.abort then
        return
    end

    if state.automatic then
        WriteTrigger(state)
        return
    end

    local entry = state.entry
    local seen = state.seen
    --targets can join while a cast resolves (Chain Reaction): the card keeps the list.
    if options.chatMessage ~= nil then
        for _, tokenid in ipairs(options.chatMessage.targetids) do
            AddTarget(entry, seen, dmhub.GetCharacterById(tokenid))
        end
    end

    local cast = options.symbols ~= nil and options.symbols.cast or nil
    if cast ~= nil then
        AddRoll(entry, cast)
        for tokenid, tier in pairs(cast:try_get("tokenToTier", {})) do
            if seen[tokenid] ~= nil then
                seen[tokenid].tier = tier
            end
        end
    end
    History.Write(entry)
end

--The row a result belongs to: the running cast's own, else one it shares through its
--cast (an invoked ability), else the row of the cast the hit names. Nil outside any.
local function OpenCast(cast)
    local running = ActivatedAbility.CurrentCastInfo()
    if running ~= nil and running.options ~= nil then
        local state = g_casts[running.options]
        if state ~= nil then
            return state
        end
        local symbols = running.options.symbols
        if cast == nil and symbols ~= nil then
            cast = symbols.cast
        end
    end
    return cast ~= nil and g_byCast[cast] or nil
end

--What to call the cause of a line: the note if it has one, else the running ability.
local function Cause(note)
    if note ~= nil and note ~= "" then
        return note
    end
    local running = ActivatedAbility.CurrentCastInfo()
    if running ~= nil and running.ability ~= nil then
        return running.ability.name
    end
    return nil
end

--The target's place on a cast's row, added if the cast did not aim at it.
local function RowTarget(state, token)
    AddTarget(state.entry, state.seen, token)
    return state.seen[token.charid]
end

local function WriteLine(token, family, facts)
    local entry = {kind = "line", family = family, map = token.mapid, who = History.Creature(token)}
    for key, value in pairs(facts) do
        entry[key] = value
    end
    History.AddCombatFacts(entry)
    History.Write(entry)
end

--Damage types worth naming. These three are how it was dealt, shown as movement in 1.6.
local function TypeWord(damagetype)
    if damagetype == nil or damagetype == "" or damagetype == "untyped"
        or damagetype == "push" or damagetype == "collide" or damagetype == "fall" then
        return nil
    end
    return string.lower(damagetype)
end

local function OnDamage(creature, info)
    if not History.Enabled() then
        return
    end
    local changed = info.raw - info.landed
    if info.landed <= 0 and changed <= 0 then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end

    local soaked = info.landed - info.lost
    local damagetype = TypeWord(info.damagetype)
    local state = OpenCast(info.cast)
    if state == nil then
        if info.landed > 0 then
            local cause = Cause(info.source)
            if info.startofturn and cause ~= nil then
                cause = "Start of turn: " .. cause
            end
            WriteLine(token, "damage", {
                taken = info.landed,
                soaked = soaked > 0 and soaked or nil,
                damagetype = damagetype,
                causetext = cause,
            })
        end
        return
    end

    local target = RowTarget(state, token)
    if target == nil then
        return
    end
    target.taken = (target.taken or 0) + info.landed
    if soaked > 0 then
        target.soaked = (target.soaked or 0) + soaked
    end
    if damagetype ~= nil and info.landed > 0 then
        target.types = target.types or {}
        target.types[damagetype] = (target.types[damagetype] or 0) + info.landed
    end
    if changed ~= 0 then
        target.immunity = target.immunity or {damagetype = damagetype or "damage", amount = 0}
        target.immunity.amount = target.immunity.amount + changed
    end
end

local function OnHeal(creature, regained, note)
    if not History.Enabled() then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    local state = OpenCast(nil)
    if state == nil then
        WriteLine(token, "heal", {healed = regained, causetext = Cause(note)})
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.healed = (target.healed or 0) + regained
    end
end

local function OnTemporaryStamina(creature, before, after, note)
    if not History.Enabled() then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    local state = OpenCast(nil)
    if state == nil then
        WriteLine(token, "temporarystamina", {before = before, after = after, causetext = Cause(note)})
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.pool = {before = target.pool ~= nil and target.pool.before or before, after = after}
    end
end

GameSystem.RegisterPlayObserver("history", {
    began = CastBegan,
    finished = CastFinished,
    damage = OnDamage,
    heal = OnHeal,
    temporarystamina = OnTemporaryStamina,
})
