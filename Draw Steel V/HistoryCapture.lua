local mod = dmhub.GetModLoading()

--Fills History at the source. For now, family F1 of the build plan: one entry for
--each ability cast that posts a card to the log, prompted triggers included. A cast
--that shares its parent's card (an invoked ability), a hidden one and an automatic
--trigger make no row of their own here; automatic triggers come in chunk 1.2.
--
--The entry is written when the cast ends, so it holds the roll and a cancelled cast
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

local function CastBegan(ability, casterToken, targets, options)
    if not History.Enabled() then
        return
    end
    if options.dismiss or options.chatMessage ~= nil or not ability:ShowChatMessageOnCast() then
        return
    end

    local actor = dmhub.GetCharacterById(ActivatedAbility.GetLogActorId(casterToken, options)) or casterToken
    local entry = {
        id = options.symbols ~= nil and options.symbols.castid or nil,
        t = dmhub.serverTimeMilliseconds,
        kind = "action",
        map = casterToken.mapid,
        actor = History.Creature(actor),
        ability = {name = ability.name, icon = ability:try_get("iconid"), action = ActionKind(ability)},
        targets = {},
    }
    History.AddCombatFacts(entry)

    --snapshot now: a target may be gone by the time the cast ends.
    local seen = {}
    for _, target in ipairs(targets) do
        AddTarget(entry, seen, target.token)
    end
    if ability.targetType == "self" and #targets == 0 then
        AddTarget(entry, seen, casterToken)
    end
    g_casts[options] = {entry = entry, seen = seen}
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
    if options.abort then
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

ActivatedAbility.RegisterCastObserver("history", {began = CastBegan, finished = CastFinished})
