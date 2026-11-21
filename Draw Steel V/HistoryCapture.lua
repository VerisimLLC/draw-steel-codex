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
--- @field unseen? "token"|"hidden" Players could not see it on the map: "token", a token the Director hid from players; "hidden", a Director's creature while Hidden with Hidden Creatures are Invisible on. ForPlayers cuts it from what they read.
--- @field tier? integer On a target: the tier of the roll against it.
--- @field roll? {edges: number, banes: number, total: number, sources: HistoryEdgeSource[]|nil} On a target: its own roll, when edges or banes against it alone changed the total.
--- @field sources? HistoryEdgeSource[] On a target without a roll of its own: what applied to its roll, when that differs from the roll's sources (empty when nothing did). Absent means the same as the roll's.
--- @field turnid? string On a turn owner: the initiative id, which identifies the turn.
--- @field group? integer On a turn owner: how many creatures share this turn.
--- @field minions? boolean On a turn owner: true when the group is minions.
--- @field byminions? integer On a target of a squad's strike: how many of its minions hit it (W10).
--- @field taken? number On a target: damage that landed, soaked included.
--- @field healed? number On a target: Stamina regained.
--- @field soaked? number On a target: how much of the damage temporary Stamina took.
--- @field types? table<string, number> On a target: damage by type, typed damage only.
--- @field immunity? {damagetype: string, amount: number} On a target: what immunity took off, or weakness added (negative).
--- @field parts? HistoryDamagePart[] On a target: what made its damage besides the tier, in the order it applied.
--- @field pool? {before: number, after: number} On a target: temporary Stamina that grew.
--- @field mk? string On a target with a pool: its Monster Knowledge key for the Stamina cut (see HistoryEntry.mk).
--- @field conds? {name: string, icon: string|nil, duration: string|nil, iscondition: boolean|nil, secret: boolean|nil, renewed: boolean|nil, ref: string|nil, cid: string|nil}[] On a target: conditions and effects it started, or renewed while it still had them; secret ones are hidden from players. ref is an ongoing effect's instance id and cid a condition's id, so History can tell whether it is still on (Active).
--- @field ended? string[] On a target: names of what it ended.
--- @field endedhidden? table<string, boolean> On a target: names in ended that players may not see.
--- @field endedconds? table<string, boolean> On a target: which of those names are conditions.
--- @field immune? string[] On a target: conditions that its immunity stopped.
--- @field resisted? boolean|string On a target: it resisted a potency test. A string names the condition it escaped.
--- @field resistedeffect? string On a target that resisted: the ongoing effect it escaped (Can't Hide), when no condition was named.
--- @field potency? HistoryPotency[] On a target: each potency test it faced (6.6a, Y8, Y9, L26).
--- @field state? string On a target: "winded", "dying" or "killed" if this did that.
--- @field recovered? string On a target: "winded" or "dying" if this ended that.
--- @field squad? string On a minion: the name of its squad.
--- @field moved? {kind: string, distance: number, fell: number, collision: number, walls: number, falldamage: number|nil, fallseparate: boolean|nil, collidedobject: boolean|nil, collidedwith: HistoryCreature|nil, path: table|nil, requested: number|nil, stability: number|nil, ignored: boolean|nil, stopped: boolean|nil, immune: boolean|nil} On a target: how another creature moved it. The path is for the side view. requested/stability: the push before stability and what stability took off; stopped: stability left nothing to move; immune: it is immune to forced movement (stopped is set too).
--- @field landedon? boolean On a target: a creature fell on it.
--- @field opposed? {attacker: number, defender: number} On a target: the totals of an opposed power roll against it. The ability's user wins only on a higher total.

--- Something besides the tier itself that made a target's damage (2.3b).
--- @class HistoryDamagePart
--- @field kind "kit"|"modifier"|"surge"
--- @field amount number The damage it added; negative when it took damage away.
--- @field damagetype? string The type it added to; nil for untyped.
--- @field name? string A kit's name, or a modifier's as the roll dialog's badge showed it.
--- @field who? HistoryCreature On a trigger: whose trigger it is.
--- @field count? integer On surges: how many were spent.
--- @field each? number On surges: the damage each dealt (the highest characteristic).
--- @field characteristic? string On surges: that characteristic's name.
--- @field free? integer On surges: how many a modifier granted for this strike only.
--- @field freefrom? {name: string, hover: string|nil}[] On surges: the modifiers that granted them (plain names on rows from before hovers).
--- @field gained? integer On surges: how many a modifier gave to keep ("you gain 1 surge").
--- @field gainedfrom? {name: string, hover: string|nil}[] On surges: the modifiers that gave those.
--- @field hovertext? string On a modifier, until History stores it: the roll dialog's hover text.
--- @field hover? string On a modifier: id of that hover text in the map's History (History.HoverText).

--- Something that added or took away edges or banes, as the roll dialog named it.
--- @class HistoryEdgeSource
--- @field name string The modifier's name, spoiler markup kept; "" when set by hand.
--- @field edges? integer Edges it added.
--- @field banes? integer Banes it added.
--- @field removedEdges? integer Edges it took away.
--- @field removedBanes? integer Banes it took away.
--- @field ignore? boolean It ignores every edge or bane ("Ignored by"), rather than removing one ("Removed by").
--- @field tiers? integer Tiers it moved the roll (Tier Up +1, Tier Down -1).
--- @field autosuccess? boolean It made the roll Tier 3.
--- @field autofailure? boolean It made the roll Tier 1.
--- @field nottierthree? boolean It kept the roll from Tier 3.
--- @field nottierone? boolean It kept the roll off Tier 1.
--- @field bonus? integer A flat number it added to the roll (negative when it took some off).
--- @field who? HistoryCreature Whose it is: a trigger's owner, or a target whose own modifier took edges or banes away.
--- @field hand? boolean Set with the roll dialog's edge and bane buttons.
--- @field hovertext? string Until History stores it: the roll dialog's hover text for the modifier.
--- @field hover? string Id of that hover text in the map's History (History.HoverText).

--Why players can't see a token on the map right now, or nil when they can. Heroes and
--creatures players control are always seen; Hidden alone hides nothing (the rules let players
--know a Hidden creature is there), only with the Hidden Creatures are Invisible setting.
local function UnseenByPlayers(token)
    if token.invisibleToPlayers then
        return "token"
    end
    if token.playerControlled then
        return nil
    end
    local ok, hidden = pcall(function()
        local props = token.properties
        return creature.HiddenCreaturesInvisible() and not props:IsHero() and props:IsHidden()
    end)
    return (ok and hidden == true) and "hidden" or nil
end

--- The creature a token shows now, as plain data for an entry.
--- @param token CharacterToken
--- @return HistoryCreature
function History.Creature(token)
    local name = token.name
    if name == nil or name == "" then
        name = token.description
    end
    local img = token.portrait
    local rect = token.portraitRect
    --a popout token's portrait is a cut-out figure whose token crop lands on empty space;
    --its face is the off-token portrait, cropped square, as the character sheet draws it.
    if token.popoutPortrait then
        img = token.offTokenPortrait
        rect = token:GetPortraitRectForAspect(1, img)
    end
    local props = token.properties
    return {
        id = token.charid,
        name = name,
        img = img,
        rect = rect ~= nil and {rect.x1, rect.y1, rect.x2, rect.y2} or nil,
        hero = token.playerControlled or (props ~= nil and props:IsHero()),
        secret = token.namePrivate or nil,
        unseen = UnseenByPlayers(token),
        squad = (props ~= nil and props.minion) and props:MinionSquad() or nil,
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

--- Adds the encounter, round and turn to an entry; out of combat, the game mode instead
--- (Respite), left off for Exploration so older entries read the same.
--- @param entry HistoryEntry
function History.AddCombatFacts(entry)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        local mode = q ~= nil and q:GameModeId() or "exploration"
        if mode ~= "exploration" and mode ~= "combat" then
            entry.mode = mode
        end
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

--The row each cast wrote, kept after it ends: minion deaths are confirmed long after
--the hit, and must still find the action that killed them.
local g_rowOfCast = setmetatable({}, {__mode = "k"})

--A cast with no row of its own that runs inside one with a row. Anything it sets off
--names this cast, so the row answers to its id too.
--It also keeps the ability on the row: a strike nested in a custom invoke takes the kit's
--bonus on its own copy as it is cast, so the row's Tier line reads the kit from there.
local function JoinParentRow(options, ability)
    local symbols = options.symbols
    if symbols == nil or symbols.cast == nil or symbols.castid == nil then
        return
    end
    local parent = g_byCast[symbols.cast]
    if parent ~= nil then
        parent.entry.aliases = parent.entry.aliases or {}
        table.insert(parent.entry.aliases, symbols.castid)
        parent.invoked = parent.invoked or {}
        table.insert(parent.invoked, ability)
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
        g_rowOfCast[cast] = entry.id
    end
    return state
end

--Pushed creatures on their way down, by charid. The fall lands a moment after the push,
--often once its cast has ended, so the push leaves here what the landing needs to find.
local g_falling = {}
local FALL_WINDOW_MS = 10000

local function Falling(token)
    local falling = g_falling[token.charid]
    if falling ~= nil and dmhub.serverTimeMilliseconds - falling.t < FALL_WINDOW_MS then
        return falling
    end
    return nil
end

--The creature whose fall set off this trigger, if one did. The engine fires "fallenon" only
--on creatures in the landing square, so being landed on is never guessed from the damage,
--which is called Fall Damage either way. A creature that simply fell only gets "fall".
local function FallerOf(ability, casterToken, options)
    if ability.typeName ~= "TriggeredAbility" then
        return nil
    end
    if ability.trigger == "fall" then
        return casterToken
    end
    local symbols = options.symbols
    if ability.trigger == "fallenon" and symbols ~= nil and symbols.fallingcreature ~= nil then
        return dmhub.LookupToken(symbols.fallingcreature)
    end
    return nil
end

--True for an ability that makes a power roll.
local function RollsPower(ability)
    for _, behavior in ipairs(ability.behaviors or {}) do
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            return true
        end
    end
    return false
end

--A trigger's place against its action's roll (T15): "before" or "after", nil when the
--action makes no roll. The action's cast carries its total once the dice have landed.
local function RollTiming(causeid)
    if causeid == nil then
        return nil
    end
    for _, state in pairs(g_casts) do
        if state.entry ~= nil and state.entry.id == causeid then
            if not state.rolls or state.cast == nil then
                return nil
            end
            return state.cast:try_get("total") ~= nil and "after" or "before"
        end
    end
    return nil
end

--Set below, beside OnResource: hands a spend made just before this cast to its row.
local ClaimUpfrontSpend

--An Opportunity Attack still running, by its owner's charid. The free strike it starts
--is the row that matters, so it takes the cause and the Opportunity Attack writes none.
--- @type table<string, table>
local g_provoking = {}

local function CastBegan(ability, casterToken, targets, options)
    if not History.Enabled() or options.dismiss then
        return
    end

    --what a fall does belongs to the push that caused it, so it goes on that row.
    local faller = FallerOf(ability, casterToken, options)
    local falling = faller ~= nil and Falling(faller) or nil
    if falling ~= nil and falling.row ~= nil then
        g_casts[options] = {
            entry = falling.row.entry,
            seen = falling.row.seen,
            landingOn = falling.row,
            landedOn = ability.trigger == "fallenon" and casterToken.charid or nil,
        }
        return
    end

    local symbols = options.symbols
    --a step written into the ability that invoked it (a Custom Ability invoke) is part of that
    --ability's row, whatever card it shows: its targets, rolls and results go there.
    local partOf = ability:try_get("_tmp_partOfAbility")
    local outer = symbols ~= nil and symbols.cast ~= nil and g_byCast[symbols.cast] or nil
    if partOf ~= nil and outer ~= nil and not outer.finished then
        JoinParentRow(options, ability)
        return
    end

    --a card from an earlier cast means this one shares it (an invoked ability).
    local card = options.chatMessage
    local sharesCard = card ~= nil and (symbols == nil or card.castid ~= symbols.castid)
    local automatic = ability.typeName == "TriggeredAbility" and not ability:ShowChatMessageOnCast()
    if sharesCard or (not automatic and not ability:ShowChatMessageOnCast()) then
        JoinParentRow(options, ability)
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
            when = RollTiming(symbols ~= nil and symbols.causecastid or nil),
            landedby = faller ~= nil and faller ~= casterToken and History.Creature(faller) or nil,
            targets = {},
        }, targets, options)
        state.automatic = true
        state.actorToken = dmhub.GetCharacterById(ActivatedAbility.GetLogActorId(casterToken, options)) or casterToken
        return
    end

    local actor = dmhub.GetCharacterById(ActivatedAbility.GetLogActorId(casterToken, options)) or casterToken
    --the stat block's slot, "Villain Action 1"; "none" or missing for any other ability.
    local villainAction = ability:try_get("villainAction")
    if villainAction == "none" or villainAction == "" then
        villainAction = nil
    end
    local state = BeginCastState({
        id = symbols ~= nil and symbols.castid or nil,
        t = dmhub.serverTimeMilliseconds,
        kind = "action",
        map = casterToken.mapid,
        actor = History.Creature(actor),
        --a real ability used as part of another action (Running Cacophony's Agonizing Harmony)
        --sits under that action's row.
        cause = outer ~= nil and not outer.finished and outer.entry.id or nil,
        ability = {
            --a written-in step with no outer row here reads as the ability it belongs to.
            name = partOf or ability.name,
            icon = ability:try_get("iconid"),
            action = ActionKind(ability),
            area = ability:IsTargetTypeAOE(ability.targetType) or nil,
            villainaction = villainAction,
        },
        --whoever is rolling is on this client; nil means the Director.
        player = not dmhub.isDM and dmhub.GetDisplayName(dmhub.userid) or nil,
        targets = {},
    }, targets, options)
    if state.entry.cause ~= nil and outer ~= nil then
        outer.hasNested = true
    end
    History.AddCombatFacts(state.entry)
    ClaimUpfrontSpend(state, casterToken, ability.name)
    --L33: a free strike for moving away keeps who moved away.
    if ability.typeName == "TriggeredAbility" and ability.trigger == "leaveadjacent" then
        local mover = symbols ~= nil and symbols.movingcreature or nil
        local moverToken = mover ~= nil and dmhub.LookupToken(mover) or nil
        if moverToken ~= nil then
            state.entry.provoker = History.Creature(moverToken)
            g_provoking[actor.charid] = state
        end
    else
        --the free strike an Opportunity Attack started: one row for both (James 2026-11-21).
        local provoking = g_provoking[actor.charid]
        if provoking ~= nil and not provoking.finished then
            g_provoking[actor.charid] = nil
            provoking.noRow = true
            state.entry.provoker = provoking.entry.provoker
            --what the triggered action cost travels with it.
            state.entry.costs = provoking.entry.costs
        end
    end
    --Y11: a triggered action's own row says what set it off, in its Trigger line's words.
    if ability.typeName == "TriggeredAbility" then
        pcall(function()
            local display = casterToken.properties:GetTriggeredActionInfo(ability.name)
            local text = display ~= nil and display:try_get("trigger") or nil
            if type(text) == "string" and text ~= "" then
                state.entry.ability.triggertext = text
            end
        end)
    end
    --its triggers say whether they came before or after the dice (RollTiming).
    state.rolls = RollsPower(ability)

    --snapshot now: a target may be gone by the time the cast ends.
    for _, target in ipairs(targets) do
        AddTarget(state.entry, state.seen, target.token)
    end
    --a squad's strike pairs each minion with the creature it struck (targetPairs, which
    --the roll also counts for Extra Attackers): how many minions hit each target (W10).
    local squadStrike = false
    pcall(function() squadStrike = ability:UsesSquadStrike(casterToken) end)
    local targetPairs = symbols ~= nil and symbols.targetPairs or nil
    if squadStrike and targetPairs ~= nil then
        for _, pair in ipairs(targetPairs) do
            local who = state.seen[pair.b]
            if who ~= nil then
                who.byminions = (who.byminions or 0) + 1
            end
        end
    end
    if ability.targetType == "self" and #targets == 0 then
        AddTarget(state.entry, state.seen, casterToken)
    end
end

--True if anything shows a change on one of an entry's creatures.
local function WhoChanged(who)
    return (who.taken or 0) > 0 or (who.healed or 0) > 0 or who.pool ~= nil
        or (who.immunity ~= nil and who.immunity.amount ~= 0)
        or who.conds ~= nil or who.ended ~= nil or who.state ~= nil or who.moved ~= nil
end

--True if anything on the entry shows a change. More families join this as they land.
local function ChangedTheTable(entry)
    for _, who in ipairs(entry.targets) do
        if WhoChanged(who) then
            return true
        end
    end
    return false
end

local function WriteTrigger(state)
    local entry = state.entry
    --a note is what a silent trigger has to say for itself, so it earns the row too.
    if not ChangedTheTable(entry) and not state.noted then
        return
    end
    local actor = state.actorToken
    if actor ~= nil and actor.valid then
        entry.actor = History.Creature(actor)
    end
    History.AddCombatFacts(entry)
    History.Write(entry)
end

--The characteristic a power roll adds, by name and value: of those its formula names
--("Might or Agility", "Highest Characteristic"), the one the value came from. Nil for a
--flat roll such as "2d10 + 3".
--- @return string|nil name
--- @return number|nil value
local function RollCharacteristic(ability, caster)
    for _, behavior in ipairs(ability.behaviors or {}) do
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            local value = behavior:GetRollCharacteristicValue(caster)
            if value == nil then
                return nil, nil
            end
            local formula = string.lower(behavior:try_get("roll", ""))
            local anyOne = string.find(formula, "highest", 1, true) ~= nil
            for _, attrid in ipairs(creature.attributeIds) do
                local name = creature.attributesInfo[attrid].description
                if (anyOne or string.find(formula, string.lower(name), 1, true) ~= nil)
                    and caster:AttributeMod(attrid) == value then
                    return name, value
                end
            end
            return nil, value
        end
    end
    return nil, nil
end

--The ability's kit damage bonuses, read from the notes kits leave on an ability ("Includes
--+1 reach, +2/+5/+7 damage from Panther kit", MCDMKit.lua). A kit adds to the first damage
--in the tier, so that damage's type is the kit's (nil for untyped).
--- @return {name: string, bonuses: number[], damagetypes: table<integer, string>}[]
local function KitBonuses(ability)
    local result = {}
    local tiers = nil
    for _, behavior in ipairs(ability.behaviors or {}) do
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            tiers = behavior.tiers
            break
        end
    end
    for _, note in ipairs(ability:try_get("modificationLog", {})) do
        local name = string.match(note, "from (.+) kit$")
        if name ~= nil then
            local bonuses = {0, 0, 0}
            for a, b, c in string.gmatch(note, "%+(%d+)/%+(%d+)/%+(%d+) damage") do
                bonuses[1] = bonuses[1] + tonumber(a)
                bonuses[2] = bonuses[2] + tonumber(b)
                bonuses[3] = bonuses[3] + tonumber(c)
            end
            if bonuses[1] + bonuses[2] + bonuses[3] > 0 then
                local damagetypes = {}
                for i = 1, 3 do
                    --the same match MCDMKit uses ("13 + M fire damage"); the type is the last
                    --word, unless that is a characteristic letter (M, A, R, I, P).
                    local match = tiers ~= nil and tiers[i] ~= nil and regex.MatchGroups(tiers[i], "\\d+(?<words> [ A-Za-z,+]+)? damage") or nil
                    local words = match ~= nil and type(match.words) == "string" and string.lower(match.words) or ""
                    local last = string.match(words, "(%a+)[^%a]*$")
                    damagetypes[i] = (last ~= nil and #last > 1) and last or nil
                end
                result[#result + 1] = {name = name, bonuses = bonuses, damagetypes = damagetypes}
            end
        end
    end
    return result
end

--The name of the characteristic that gives this value, first in sheet order on a tie.
local function CharacteristicNamed(caster, value)
    if caster == nil then
        return nil
    end
    for _, attrid in ipairs(creature.attributeIds) do
        if caster:AttributeMod(attrid) == value then
            return creature.attributesInfo[attrid].description
        end
    end
    return nil
end

--The modifiers a roll's surges came from, each with the roll dialog's hover text (stored
--and replaced by an id when the entry is written), or nil when none were named.
--- @param record {sources: string[], hovers: table<integer, string>|nil}
--- @return {name: string, hovertext: string|nil}[]|nil
local function SurgeSources(record)
    if #record.sources == 0 then
        return nil
    end
    local list = {}
    for i, name in ipairs(record.sources) do
        list[i] = {name = name, hovertext = record.hovers ~= nil and record.hovers[i] or nil}
    end
    return list
end

--What made each damaged target's damage besides the tier (2.3b): the kit, the roll dialog's
--damage modifiers, then surges, each with the type it added to. The card takes them off
--the Tier line. A target whose immunity stopped it all still gets them, so its line can say
--what made the damage that immunity took off.
--- invoked: abilities cast inside this one that shared its row (JoinParentRow); a kit
--- bonus one of them took at cast, and the row's own ability did not, counts as the row's.
local function AddDamageParts(entry, cast, ability, caster, invoked)
    local kits = KitBonuses(ability)
    local haveKit = {}
    for _, kit in ipairs(kits) do
        haveKit[kit.name] = true
    end
    for _, sub in ipairs(invoked or {}) do
        for _, kit in ipairs(KitBonuses(sub)) do
            if not haveKit[kit.name] then
                haveKit[kit.name] = true
                kits[#kits + 1] = kit
            end
        end
    end
    local targetDamage = cast:try_get("targetDamageSources", {})
    local targetSurges = cast:try_get("targetSurges", {})
    local freeSurges = cast:try_get("targetFreeSurges", {})
    local gainedSurges = cast:try_get("targetGainedSurges", {})
    for _, who in ipairs(entry.targets) do
        local tier = who.tier
        if tier ~= nil and tier > 0 and who.taken ~= nil then
            --- @type HistoryDamagePart[]
            local parts = {}
            for _, kit in ipairs(kits) do
                if kit.bonuses[tier] ~= 0 then
                    parts[#parts + 1] = {kind = "kit", name = kit.name, amount = kit.bonuses[tier], damagetype = kit.damagetypes[tier]}
                end
            end
            --a modifier that only changes the damage's type ("deals psychic damage") adds as much
            --of one type as it takes off untyped. That is no change in amount, so it is no part:
            --the other untyped parts take its type instead (A Champion's Cry, James 2026-11-21).
            local convertTo = nil
            for _, source in ipairs(targetDamage[who.id] or {}) do
                local byType = source.tiers[tier] or {}
                local sum, typed = 0, nil
                for typeName, amount in pairs(byType) do
                    sum = sum + amount
                    if amount > 0 and typeName ~= "untyped" then
                        typed = typeName
                    end
                end
                local converts = sum == 0 and typed ~= nil and (byType.untyped or 0) < 0
                if converts then
                    convertTo = typed
                end
                local typeNames = {}
                for typeName in pairs(byType) do
                    typeNames[#typeNames + 1] = typeName
                end
                table.sort(typeNames)
                if converts then
                    typeNames = {}
                end
                local owner = source.charid ~= nil and dmhub.GetCharacterById(source.charid) or nil
                for _, typeName in ipairs(typeNames) do
                    parts[#parts + 1] = {
                        kind = "modifier",
                        name = source.name,
                        who = owner ~= nil and History.Creature(owner) or nil,
                        amount = byType[typeName],
                        damagetype = typeName ~= "untyped" and typeName or nil,
                        hovertext = source.hovertext,
                    }
                end
            end
            local surges = targetSurges[who.id]
            if surges ~= nil then
                --surges a modifier granted for this strike only (Y5b): how many, and from what.
                local free = freeSurges[who.id]
                local gained = gainedSurges[who.id]
                parts[#parts + 1] = {
                    kind = "surge",
                    count = surges.count,
                    each = surges.each,
                    characteristic = CharacteristicNamed(caster, surges.each),
                    amount = surges.count * surges.each,
                    damagetype = surges.damagetype,
                    free = free ~= nil and math.min(free.count, surges.count) or nil,
                    freefrom = free ~= nil and SurgeSources(free) or nil,
                    gained = gained ~= nil and math.min(gained.count, surges.count) or nil,
                    gainedfrom = gained ~= nil and SurgeSources(gained) or nil,
                }
            end
            if convertTo ~= nil then
                for _, part in ipairs(parts) do
                    if part.damagetype == nil then
                        part.damagetype = convertTo
                    end
                end
            end
            if #parts > 0 then
                who.parts = parts
            end
        end
    end
end

local function AddRoll(entry, cast, ability, caster)
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
        hidden = cast:try_get("hiddenRoll"),
    }
    --a tier chosen after the dice landed (5.2e): who chose it and what the dice gave.
    local diceTier = cast:try_get("diceTier")
    if diceTier ~= nil then
        entry.roll.overridden = {by = cast:try_get("overrideBy"), dicetier = diceTier}
    end
    --what the dice add up to and what is added to them, for the receipt (2.2). The rest of
    --the total past the dice, the characteristic and an edge or bane is a flat bonus.
    local natural = cast:try_get("naturalRoll")
    if natural ~= nil and caster ~= nil then
        local name, value = RollCharacteristic(ability, caster)
        local edgeBonus = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(entry.roll.edges or 0, entry.roll.banes or 0)
        entry.roll.natural = natural
        if name ~= nil then
            entry.roll.characteristic = {name = name, value = value}
        end
        local bonus = total - natural - edgeBonus - (name ~= nil and value or 0)
        if bonus ~= 0 then
            entry.roll.bonus = bonus
        end
    end
end

--Triggered actions used from the roll dialog (L107): one per trigger and the creature that
--used it, with what it did to each target, the damage it changed or the edges and banes
--it gave. The tray gives each its own trigger row, tagged During the roll.
local function AddRollTriggers(entry, cast)
    local damage = cast:try_get("targetDamageSources", {})
    local sources = cast:try_get("targetSources", {})
    local found = {}
    local list = {}
    local function Target(name, charid, who)
        local key = name .. "|" .. tostring(charid)
        local item = found[key]
        if item == nil then
            local owner = charid ~= nil and dmhub.GetCharacterById(charid) or nil
            item = {name = name, who = owner ~= nil and History.Creature(owner) or nil, targets = {}, byid = {}}
            found[key] = item
            list[#list + 1] = item
        end
        local target = item.byid[who.id]
        if target == nil then
            --who it was, not what the action did to it: the action's own row says that.
            target = {id = who.id, name = who.name, img = who.img, rect = who.rect, hero = who.hero, secret = who.secret, unseen = who.unseen}
            item.byid[who.id] = target
            item.targets[#item.targets + 1] = target
        end
        return target
    end
    for _, who in ipairs(entry.targets) do
        for _, source in ipairs(damage[who.id] or {}) do
            if source.trigger and who.tier ~= nil and who.tier > 0 then
                local delta = 0
                for _, amount in pairs(source.tiers[who.tier] or {}) do
                    delta = delta + amount
                end
                if delta ~= 0 then
                    local target = Target(source.name or "", source.charid, who)
                    target.delta = (target.delta or 0) + delta
                end
            end
        end
        for _, source in ipairs(sources[who.id] or {}) do
            if source.trigger then
                local target = Target(source.name or "", source.charid, who)
                target.edges = source.edges
                target.banes = source.banes
                target.tiers = source.tiers
            end
        end
    end
    for _, item in ipairs(list) do
        item.byid = nil
    end
    if #list > 0 then
        entry.rolltriggers = list
    end
end

--The roll dialog's sources for one target (2.3a), with each owner as it looks now.
--- @return HistoryEdgeSource[]
local function EdgeSources(sources)
    local result = {}
    for _, source in ipairs(sources) do
        local owner = source.charid ~= nil and dmhub.GetCharacterById(source.charid) or nil
        result[#result + 1] = {
            name = source.name or "",
            edges = source.edges,
            banes = source.banes,
            removedEdges = source.removedEdges,
            removedBanes = source.removedBanes,
            ignore = source.ignore,
            tiers = source.tiers,
            autosuccess = source.autosuccess,
            autofailure = source.autofailure,
            nottierthree = source.nottierthree,
            nottierone = source.nottierone,
            bonus = source.bonus,
            who = owner ~= nil and History.Creature(owner) or nil,
            hand = source.hand,
            hovertext = source.hovertext,
        }
    end
    return result
end

--Two source lists with the same key name the same things doing the same to the roll.
--- @param sources HistoryEdgeSource[]
--- @return string
local function SourcesKey(sources)
    local keys = {}
    for _, source in ipairs(sources) do
        keys[#keys + 1] = History.SourceKey(source)
    end
    table.sort(keys)
    return table.concat(keys, ";")
end

local function CastFinished(ability, casterToken, options)
    local state = g_casts[options]
    if state == nil then
        return
    end
    g_casts[options] = nil
    if state.landingOn ~= nil then
        --only set here, so a creature the fall changed nothing on stays off the row.
        local landedOn = state.landedOn ~= nil and state.seen[state.landedOn] or nil
        if landedOn ~= nil then
            landedOn.landedon = true
        end
        if state.landingOn.finished then
            History.Rewrite(state.entry)
        end
        return
    end
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
    if state.noRow then
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
    --the roll's details are extras: if working them out fails, the row is still written.
    local ok, err = true, nil
    if cast ~= nil then ok, err = pcall(function()
        AddRoll(entry, cast, ability, casterToken ~= nil and casterToken.valid and casterToken.properties or nil)
        for tokenid, tier in pairs(cast:try_get("tokenToTier", {})) do
            if seen[tokenid] ~= nil then
                seen[tokenid].tier = tier
            end
        end
        local targetSources = cast:try_get("targetSources", {})
        for tokenid, roll in pairs(cast:try_get("targetRolls", {})) do
            if seen[tokenid] ~= nil then
                local sources = targetSources[tokenid]
                seen[tokenid].roll = {edges = roll.edges, banes = roll.banes, total = roll.total,
                    sources = sources ~= nil and EdgeSources(sources) or nil}
            end
        end
        --the roll's own sources are a target's with no roll of its own, as its tier is. Two
        --such targets can owe the same edges to different things; the first one's show.
        if entry.roll ~= nil then
            for _, who in ipairs(entry.targets) do
                if who.roll == nil and targetSources[who.id] ~= nil then
                    entry.roll.sources = EdgeSources(targetSources[who.id])
                    break
                end
            end
            --a target can owe the same edge count to different things (Prone on one, Restrained
            --on another), so it keeps its own list whenever that differs; the card names what
            --applied to every target once, and each target's own parts on its line (Round 16).
            local shared = SourcesKey(entry.roll.sources or {})
            for _, who in ipairs(entry.targets) do
                if who.roll == nil and who.tier ~= nil then
                    local own = EdgeSources(targetSources[who.id] or {})
                    if SourcesKey(own) ~= shared then
                        who.sources = own
                    end
                end
            end
        end
        AddDamageParts(entry, cast, ability, casterToken ~= nil and casterToken.valid and casterToken.properties or nil, state.invoked)
        AddRollTriggers(entry, cast)
    end) end
    if not ok then
        print("History:: roll details failed:", err)
    end
    --an ability aimed at its user only to run its steps (Get In Get Out) lists that user as a
    --target; once the steps' targets, or the abilities it used, are on the row, an untouched
    --user is just noise.
    if (#entry.targets > 1 or state.hasNested) and entry.actor ~= nil then
        local kept = {}
        for _, who in ipairs(entry.targets) do
            if who.id ~= entry.actor.id or WhoChanged(who) then
                kept[#kept + 1] = who
            end
        end
        if #kept > 0 or state.hasNested then
            entry.targets = kept
        end
    end
    History.Write(entry)
    --the user's own card folds into the row it became (S5, 6.5d).
    History.FoldIn(entry)
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
    --outside the cast's coroutine, e.g. surges spent when the roll dialog's Roll is clicked.
    if cast == nil then
        cast = GameSystem.ScopedCast()
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

--A change made by hand (GameSystem.HandEdit) says who made it under its line (L87), and
--a player's marks the Director's badge gold (byplayer). Returns facts, for WriteLine.
local function NoteHand(facts)
    if GameSystem.IsHandEdit() then
        facts.causetext = dmhub.isDM and "Director" or dmhub.userDisplayName
        facts.byplayer = not dmhub.isDM or nil
    end
    return facts
end

--The cast a change belongs to, or nil. A hand edit belongs to none, even mid-cast.
local function CastFor(cast)
    if GameSystem.IsHandEdit() then
        return nil
    end
    return OpenCast(cast)
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
    return entry
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
    local state = CastFor(info.cast)
    --a fall that lands after its push's cast ended still belongs to that push's move (Y7).
    local falling = state == nil and info.damagetype == "fall" and Falling(token) or nil
    if falling ~= nil and info.landed > 0 then
        falling.moved.falldamage = (falling.moved.falldamage or 0) + info.landed
        falling.moved.fallseparate = true
        if falling.row == nil or falling.row.finished then
            History.Rewrite(falling.entry)
        end
    end
    if state == nil then
        if info.landed > 0 then
            local cause = Cause(info.source)
            if info.startofturn and cause ~= nil then
                cause = "Start of turn: " .. cause
            end
            WriteLine(token, "damage", NoteHand{
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
    --Y7: a fall's damage, kept with the move so the Why can say what the fall added.
    if info.damagetype == "fall" and target.moved ~= nil and info.landed > 0 then
        target.moved.falldamage = (target.moved.falldamage or 0) + info.landed
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

--A Recovery heals first and spends second, both inside one click. The heal's line waits
--here so the spend can join it as its cause, one row in place of two.
local g_recoveryHeal = nil
local RECOVERY_WINDOW_MS = 1000

--Heroes in the middle of a respite, with what they had when it began (L53). Weak keys:
--a creature that never finishes resting is forgotten with it.
local g_resting = setmetatable({}, {__mode = "k"})

--What a respite can change on a Hero.
local function RespiteFacts(props)
    local used = props:GetResourceUsage(CharacterResource.recoveryResourceId, "long") or 0
    local max = props:GetResources()[CharacterResource.recoveryResourceId] or 0
    --A Level set by hand can leave the stored XP below what that Level implies; the rest
    --counts from the Level's own XP then (creature:Rest), so the line does too.
    local level = props:CharacterLevel()
    local perLevel = toint(dmhub.GetSettingValue("xpperlevel") or 16)
    if perLevel == 0 then
        perLevel = 16
    end
    return {
        stamina = props:CurrentHitpoints(),
        recoveries = max - used,
        xp = math.max(props:try_get("xp", 0), (level - 1) * perLevel),
        level = level,
    }
end

local function OnResting(creature)
    if History.Enabled() and creature:IsHero() then
        g_resting[creature] = RespiteFacts(creature)
    end
end

--The respite is over: one line per Hero saying only what changed (L53, L54), and one more
--when it raised their Level (L55).
local function OnRested(creature)
    local before = g_resting[creature]
    g_resting[creature] = nil
    local token = dmhub.LookupToken(creature)
    if before == nil or token == nil or not History.Enabled() then
        return
    end
    local after = RespiteFacts(creature)
    local parts = {}
    for _, fact in ipairs({{"stamina", "Stamina"}, {"recoveries", "Recoveries"}, {"xp", "XP"}}) do
        local was, now = before[fact[1]], after[fact[1]]
        if was ~= now then
            parts[#parts + 1] = string.format("%s %d to %d", fact[2], was, now)
        end
    end
    --stamped a millisecond apart, so the Level line always sorts after the respite's.
    local now = dmhub.serverTimeMilliseconds
    WriteLine(token, "respite", {t = now, causetext = #parts > 0 and table.concat(parts, History.DOT) or "Respite"})
    if after.level > before.level then
        WriteLine(token, "levelup", {t = now + 1, level = after.level, causetext = "Respite"})
    end
end

local function OnHeal(creature, regained, note, recovered)
    if not History.Enabled() then
        return
    end
    --a respite's healing is part of its own line (L53).
    if g_resting[creature] ~= nil then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    local state = CastFor(nil)
    if state == nil then
        local entry = WriteLine(token, "heal", NoteHand{healed = regained, recovered = recovered, causetext = Cause(note)})
        if note == "Use Recovery" then
            g_recoveryHeal = {entry = entry, charid = token.charid, t = dmhub.serverTimeMilliseconds}
        end
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.healed = (target.healed or 0) + regained
        target.recovered = recovered or target.recovered
    end
end

--Winded, dying and killed: a caption on the row that caused it, a line when nothing did.
local function OnThreshold(creature, thresholdState, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil then
        return
    end
    local state = OpenCast(info.cast)
    if state == nil then
        WriteLine(token, "threshold", {state = thresholdState, causetext = Cause(info.source)})
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.state = thresholdState
    end
end

--A step names another creature as the one acting (Iron Grip: the grabber deals the damage
--a grabbed creature takes for escaping), as the old Action Log's card did.
local function OnActorCredited(creature, info)
    local token = dmhub.LookupToken(creature)
    local state = OpenCast(info.cast)
    if not History.Enabled() or token == nil or state == nil then
        return
    end
    state.actorToken = token
    state.entry.actor = History.Creature(token)
end

local function OnForcedMove(creature, info)
    local token = dmhub.LookupToken(creature)
    --a push that went nowhere is still worth a line when stability stopped it (L98), it was
    --blocked by a collision, or stability shortened it first (L105); a fall always is.
    local wentNowhere = info.distance <= 0 and not info.falling and not info.stopped
        and (info.collision or 0) <= 0 and info.stability == nil
    if not History.Enabled() or token == nil or wentNowhere then
        return
    end
    local moved = {
        kind = info.kind,
        distance = info.distance,
        fell = 0,
        collision = info.collision,
        walls = info.walls,
        path = info.path,
    }
    --what a collision hit (L108, L109): an object, or the first creature it ran into.
    if (info.collision or 0) > 0 then
        moved.collidedobject = info.collidewithobject or nil
        local other = info.collidedwith ~= nil and info.collidedwith[1] or nil
        if other ~= nil and other.valid and not info.collidewithobject then
            moved.collidedwith = History.Creature(other)
        end
    end
    --what stability did (6.5): stopped comes straight from the setup, the rest with the move.
    --An immune target was never moved at all: that is all its line says.
    local stability = info.stopped and info or info.stability
    if info.immune then
        moved.stopped = true
        moved.immune = true
    elseif stability ~= nil then
        moved.requested = stability.requested
        moved.stability = stability.stability
        moved.ignored = stability.ignored or nil
        moved.stopped = info.stopped or nil
    end
    local state = OpenCast(info.cast)
    if state == nil then
        local entry = WriteLine(token, "moved", {moved = moved, causetext = Cause(nil)})
        if info.falling then
            g_falling[token.charid] = {moved = moved, entry = entry, t = dmhub.serverTimeMilliseconds}
        end
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.moved = moved
        if info.falling then
            g_falling[token.charid] = {moved = moved, entry = state.entry, row = state, t = dmhub.serverTimeMilliseconds}
        end
    end
end

--The landing: the only place the real distance is known, floors included.
--An ability teleported a creature other than its user: the move goes on that target, as a
--push would. A creature's own teleport writes nothing, like any move of its own.
--info: {distance, cast}.
local function OnTeleported(creature, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil then
        return
    end
    local state = OpenCast(info.cast)
    if state == nil then
        return
    end
    local actor = state.entry.actor
    if actor ~= nil and actor.id == token.charid then
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.moved = {kind = "teleport", distance = info.distance, fell = 0, collision = 0, walls = 0}
    end
end

--An opposed power roll finished against this creature. info: {attacker, defender, cast}.
local function OnOpposed(creature, info)
    local token = dmhub.LookupToken(creature)
    local state = OpenCast(info.cast)
    if not History.Enabled() or token == nil or state == nil then
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.opposed = {attacker = info.attacker, defender = info.defender}
    end
end

local function OnFell(creature, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil then
        return
    end
    local falling = Falling(token)
    if falling == nil then
        return
    end
    if falling.landed then
        --it already landed from the push, so this is a new fall the push did not cause.
        g_falling[token.charid] = nil
        return
    end
    falling.landed = true
    falling.moved.fell = info.distance
    if falling.row == nil or falling.row.finished then
        History.Rewrite(falling.entry)
    end
end

--Confirmed minion deaths come after the hit, once the Director clicks the skulls. So this
--is an entry of its own naming the row it belongs to, which the tray puts together.
local function OnMinionsDied(creature, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil then
        return
    end
    WriteLine(token, "minions", {
        name = info.squad,
        killed = info.killed,
        left = info.left,
        cause = info.cast ~= nil and g_rowOfCast[info.cast] or nil,
        --Y13: a minion's own Stamina, and the damage that killed them.
        each = info.each,
        damage = info.damage,
        mk = MonsterKnowledge.KeyForToken(token),
    })
end

--What a Stamina line keeps so players see its numbers only when the token's Stamina bar would
--show them the number: the monster's Monster Knowledge key, "" for a creature Monster Info
--can't learn about, nil for a Hero (always shown).
local function StaminaGateKey(token)
    local hero = token.playerControlled
    if not hero then
        local ok, result = pcall(function() return token.properties:IsHero() end)
        hero = ok and result == true
    end
    if hero then
        return nil
    end
    return MonsterKnowledge.KeyForToken(token) or ""
end

local function OnTemporaryStamina(creature, before, after, note)
    if not History.Enabled() then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    local state = CastFor(nil)
    if state == nil then
        WriteLine(token, "temporarystamina", NoteHand{before = before, after = after, causetext = Cause(note),
            mk = StaminaGateKey(token)})
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.pool = {before = target.pool ~= nil and target.pool.before or before, after = after}
        target.mk = StaminaGateKey(token)
    end
end

--The words a duration shows as, in the rules' own short forms.
local DURATION_WORDS = {
    save = "save ends",
    save_ends = "save ends",
    eot = "EoT",
    end_of_next_turn = "EoT",
    eoe = "EoE",
}

--The name and icon History shows for a condition or an effect. Nil for one it leaves
--out: effects hidden from everyone, and markers that only track rules. secret marks an
--effect hidden from enemies on a creature off the heroes' side: players don't see it (2.4).
--- @param token CharacterToken|nil Whose effect it is.
local function EffectFacts(item, token)
    if item.conditionid ~= nil then
        local info = GetTableCached(CharacterCondition.tableName)[item.conditionid]
        if info == nil then
            return nil
        end
        return {name = info.name, icon = info.iconid, iscondition = true, cid = item.conditionid}
    end
    local info = GetTableCached(CharacterOngoingEffect.tableName)[item.ongoingeffectid]
    if info == nil or not info.statusEffect or info.hiddenFromHistory then
        return nil
    end
    local secret = info.hiddenFromEnemies and token ~= nil and not History.Creature(token).hero
    return {name = info.name, icon = info.iconid, iscondition = info.condition ~= "none" or nil, secret = secret or nil}
end

local function OnEffectStarted(creature, info)
    if not History.Enabled() then
        return
    end
    local token = dmhub.LookupToken(creature)
    local facts = EffectFacts(info, token)
    if facts == nil or token == nil then
        return
    end
    facts.duration = DURATION_WORDS[info.duration]
    facts.renewed = info.renewed
    facts.ref = info.instanceid

    local state = CastFor(nil)
    if state == nil then
        --a renewal outside any cast is upkeep (an aura re-applying what it gives every
        --move), not something anyone did, so only casts record one (L39).
        if not info.renewed then
            facts.causetext = Cause(info.source)
            WriteLine(token, "condition", NoteHand(facts))
        end
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.conds = target.conds or {}
        --an ability applying the same effect twice to one target reads once.
        for _, existing in ipairs(target.conds) do
            if existing.name == facts.name then
                return
            end
        end
        target.conds[#target.conds + 1] = facts
    end
end

--Lines waiting to go up this frame, by creature and cause, so effects that end
--together are one line (L8).
local g_endedFrame = nil
local g_endedLines = {}

--- @param hidden table<string, boolean>|nil Names players may not see.
local function WriteEnded(token, names, causetext, hidden)
    local frame = dmhub.FrameCount()
    if g_endedFrame ~= frame then
        g_endedFrame = frame
        g_endedLines = {}
    end
    local key = token.charid .. "|" .. (causetext or "")
    local entry = g_endedLines[key]
    if entry ~= nil then
        for _, name in ipairs(names) do
            entry.names[#entry.names + 1] = name
            if hidden ~= nil and hidden[name] then
                entry.hidden = entry.hidden or {}
                entry.hidden[name] = true
            end
        end
        return
    end
    g_endedLines[key] = WriteLine(token, "ended", {names = names, causetext = causetext, hidden = hidden,
        byplayer = GameSystem.IsHandEdit() and not dmhub.isDM or nil})
end

--The closing line of each encounter, while its creatures report what ended (L17).
local g_closing = {}

local function ClosingEntry(token)
    local q = dmhub.initiativeQueue
    if q == nil then
        return nil
    end
    local key = q.guid .. token.mapid
    if g_closing[key] == nil then
        g_closing[key] = {
            kind = "line",
            family = "encounterend",
            map = token.mapid,
            encounter = q.guid,
            round = q.round,
            turn = q.turnNumber,
            causetext = string.format("Round %d", q.round),
            ended = {},
        }
        History.Write(g_closing[key])
    end
    return g_closing[key]
end

--What a resource is called on a line, and which chip colour it takes on a row.
local function ResourceFacts(creature, key)
    if key == CharacterResource.heroicResourceId then
        return creature:GetHeroicResourceName(), "historyChipHeroic"
    end
    if key == CharacterResource.surgeResourceId then
        return "surges", "historyChipSurge"
    end
    local info = dmhub.GetTable(CharacterResource.tableName)[key]
    return info ~= nil and info.name or "resource", nil
end

--- The icon of a Hero's heroic resource (their class's), or nil when it has none.
--- @param creature creature
--- @return string|nil
function History.HeroicIcon(creature)
    local iconid = nil
    pcall(function()
        --only a character has a class; on anything else this errors and the pcall gives nil.
        local classInfo = (creature --[[@as character]]):GetClass()
        if classInfo ~= nil then
            iconid = classInfo:try_get("heroicResourceIcon")
        end
    end)
    if iconid == "" then
        return nil
    end
    return iconid
end

--A spend on a row reads as its icon and the number (T12). A heroic resource keeps its
--class's icon on the cost, so the row still shows it if the Hero changes class.
local function AddCost(state, name, amount, style, icon)
    local entry = state.entry
    entry.costs = entry.costs or {}
    local cost = entry.costs[name] or {amount = 0, style = style, icon = icon}
    cost.amount = cost.amount + amount
    entry.costs[name] = cost
end

--A triggered ability pays its cost just before its cast begins (TriggeredAbility
--ExecuteTriggerCast), when no row is open yet. Such a spend, named after the ability,
--waits a moment here for that row; unclaimed, it becomes a line as before.
local UPFRONT_WAIT_SECONDS = 0.5
--- @type table<table, {charid: string, name: string, amount: number, style: string|nil, icon: string|nil, note: string}>
local g_upfront = {}

ClaimUpfrontSpend = function(state, casterToken, abilityName)
    for key, pending in pairs(g_upfront) do
        if pending.charid == casterToken.charid and pending.note == abilityName then
            g_upfront[key] = nil
            AddCost(state, pending.name, pending.amount, pending.style, pending.icon)
        end
    end
end

local function OnResource(creature, key, before, after, refreshType, note)
    if not History.Enabled() or note == "Undo" or note == "Redo" then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    local name, style = ResourceFacts(creature, key)
    local change = after - before
    --L110: a creature that may go below 0 (a Talent's Clarity) is strained while it is.
    if key == CharacterResource.heroicResourceId and (before < 0) ~= (after < 0) then
        local canGoNegative = false
        pcall(function() canGoNegative = creature:AllowNegativeResources() > 0 end)
        if canGoNegative then
            WriteLine(token, "strained", {strained = after < 0, causetext = string.format("%s %d", name, after)})
        end
    end
    local state = CastFor(nil)
    --the Recovery behind the heal just written: it becomes that row's cause (L3).
    local healed = g_recoveryHeal
    g_recoveryHeal = nil
    if state == nil and key == CharacterResource.recoveryResourceId and change < 0 and healed ~= nil
        and healed.charid == token.charid and dmhub.serverTimeMilliseconds - healed.t < RECOVERY_WINDOW_MS then
        local entry = healed.entry
        entry.causetext = "Used a Recovery"
        entry.amount = change
        entry.resourceid = key
        entry.refreshtype = refreshType
        History.Rewrite(entry)
        return
    end
    local icon = key == CharacterResource.heroicResourceId and History.HeroicIcon(creature) or nil
    if state ~= nil and not state.automatic and change < 0 then
        AddCost(state, name, -change, style, icon)
        return
    end
    --what the action gave its own user (Counterstrategy's surges) is part of its result:
    --it goes on the row, not a line of its own. Others' gains stay lines.
    local actor = state ~= nil and state.entry.actor or nil
    if state ~= nil and not state.automatic and change > 0 and actor ~= nil and actor.id == token.charid then
        local entry = state.entry
        entry.gains = entry.gains or {}
        local gain = entry.gains[name] or {amount = 0, style = style, icon = icon}
        gain.amount = gain.amount + change
        entry.gains[name] = gain
        return
    end
    if state == nil and change < 0 and note ~= nil and note ~= "" and not GameSystem.IsHandEdit() then
        local pending = {charid = token.charid, name = name, amount = -change, style = style, icon = icon, note = note}
        g_upfront[pending] = pending
        dmhub.Schedule(UPFRONT_WAIT_SECONDS, function()
            if mod.unloaded or g_upfront[pending] == nil then
                return
            end
            g_upfront[pending] = nil
            if not token.valid then
                return
            end
            WriteLine(token, "resource", {name = name, amount = change, resourceid = key,
                refreshtype = refreshType, causetext = note})
        end)
        return
    end
    --gains are lines, with Undo. Inside an automatic trigger the line names the trigger
    --and its cause, so the tray can still nest it (T15).
    WriteLine(token, "resource", NoteHand{
        name = name,
        amount = change,
        resourceid = key,
        refreshtype = refreshType,
        causetext = Cause(note),
        cause = state ~= nil and state.automatic and state.entry.cause or nil,
        trigger = state ~= nil and state.automatic and state.entry.ability.name or nil,
        triggerby = state ~= nil and state.automatic and state.actorToken ~= nil and History.Creature(state.actorToken) or nil,
    })
end

--A note an ability's author typed on one of its steps (REVIEW.md decision 5): kept on the
--running cast's row for the card's Why, as written, unless it only repeats the ability's
--name. Outside a cast there is no row to keep it on.
local function OnTypedMessage(text)
    if not History.Enabled() or type(text) ~= "string" then
        return
    end
    text = trim(text)
    local state = text ~= "" and OpenCast(nil) or nil
    if state == nil then
        return
    end
    local entry = state.entry
    if entry.ability ~= nil and string.lower(text) == string.lower(entry.ability.name or "") then
        return
    end
    entry.messages = entry.messages or {}
    for _, message in ipairs(entry.messages) do
        if message == text then
            return
        end
    end
    entry.messages[#entry.messages + 1] = text
end

--A note card (an Action Log Note step, a modifier's bonus note): inside a cast it joins the
--row's Why as "{title}: {detail}" (just the detail when the title only repeats the ability's
--name); outside one it is a line, "{Creature} {title}" over the detail.
local function OnNote(creature, title, detail)
    if not History.Enabled() then
        return
    end
    title = trim(tostring(title or ""))
    detail = trim(tostring(detail or ""))
    if title == "" and detail == "" then
        return
    end
    local state = OpenCast(nil)
    if state ~= nil then
        local abilityName = state.entry.ability ~= nil and state.entry.ability.name or ""
        local text = detail
        if title ~= "" and string.lower(title) ~= string.lower(abilityName) then
            text = detail ~= "" and (title .. ": " .. detail) or title
        end
        state.noted = true
        OnTypedMessage(text)
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    WriteLine(token, "note", {
        name = title ~= "" and title or detail,
        causetext = title ~= "" and detail ~= "" and detail or nil,
    })
end

--- Puts a resource line, or a heal with its Recovery, back the way it was. Whoever controls
--- the creature can do this.
--- @param entry HistoryEntry
function History.UndoResource(entry)
    local token = entry.who ~= nil and dmhub.GetCharacterById(entry.who.id) or nil
    if token == nil or entry.resourceid == nil or entry.undone or entry.reverted ~= nil then
        return
    end
    --not on the undo stack: Ctrl+Z would put the resource back while the line still read Undone.
    token:ModifyProperties{
        description = "Undo Resource",
        undoable = false,
        execute = function()
            --a heal with its Recovery: the Stamina goes back too, set straight so no damage line follows.
            if entry.family == "heal" then
                local props = token.properties
                props:SetCurrentHitpoints(props:CurrentHitpoints() - entry.healed, "Undo")
            end
            if entry.amount > 0 then
                token.properties:ConsumeResource(entry.resourceid, entry.refreshtype, entry.amount, "Undo")
            else
                token.properties:RefreshResource(entry.resourceid, entry.refreshtype, -entry.amount, "Undo")
            end
        end,
    }
    entry.undone = true
    History.Rewrite(entry)
end

--Malice is shown to the Director only, except a spend, which is on its row for all (gap 4).
local function OnMalice(before, after, note)
    local running = ActivatedAbility.CurrentCastInfo()
    local caster = running ~= nil and running.casterToken or nil
    local state = OpenCast(nil)
    local spentOnRow = state ~= nil and not state.automatic and after < before
    if spentOnRow then
        AddCost(state, "Malice", before - after, "historyChipMalice")
    end

    local byHand = note == nil or note == "Manually set"
    local token = caster ~= nil and caster.valid and caster or nil
    local entry = NoteHand{
        kind = "line",
        family = "malice",
        map = token ~= nil and token.mapid or game.currentMapId,
        who = token ~= nil and History.Creature(token) or nil,
        before = before,
        after = after,
        causetext = byHand and "Set by hand" or note,
        --the round heading shows these; only a trait or a hand edit earns a line.
        quiet = spentOnRow or (token == nil and not byHand) or nil,
    }
    History.AddCombatFacts(entry)
    History.Write(entry)
end

local function OnGlobalResource(resourceid, before, after, note)
    if not History.Enabled() then
        return
    end
    if resourceid == CharacterResource.maliceResourceId then
        OnMalice(before, after, note)
        return
    end
    local info = dmhub.GetTable(CharacterResource.tableName)[resourceid]
    if info == nil or info.name ~= "Hero Tokens" then
        return
    end
    local entry = NoteHand{
        kind = "line",
        family = "globalresource",
        map = game.currentMapId,
        name = info.name,
        before = before,
        after = after,
        causetext = Cause(note),
    }
    History.AddCombatFacts(entry)
    History.Write(entry)
end

--The first line of a combat: who goes first, and the Draw Steel die if one was rolled (T10).
--info: {queue, mapid, heroesFirst, rolled}, from the one client that starts the combat.
local function OnCombatBegan(info)
    local q = info.queue
    if not History.Enabled() or q == nil or info.mapid == nil then
        return
    end
    local entry = {
        kind = "line",
        family = "drawsteel",
        map = info.mapid,
        encounter = q.guid,
        round = q.round,
        turn = q.turnNumber,
        heroesFirst = info.heroesFirst,
        rolled = info.rolled,
    }
    History.Write(entry)
end

--Downtime projects (5.1g). info comes from DTProject:_notePoints, on every roll or hand
--adjustment that changes a project's points. Only what changes the table is written: a
--milestone reached (L73) and a project completed (L74). The rolls and adjustments stay
--where they are already kept, on the project and in the Respite's record (James,
--2026-11-19). A player's project says a milestone was reached, so this line may too; the
--milestone still to come is never named.
local function OnDowntime(info)
    if not History.Enabled() or not (info.milestone or info.completed) then
        return
    end
    local project = info.project ~= nil and info.project ~= "" and info.project or "A project"
    local owner = info.ownerid ~= nil and dmhub.GetCharacterById(info.ownerid) or nil
    local function Write(entry)
        entry.kind = "line"
        entry.family = "downtime"
        entry.map = game.currentMapId
        entry.name = project
        History.AddCombatFacts(entry)
        History.Write(entry)
    end
    if info.milestone then
        Write{sub = "milestone", causetext = "The Director rolls a project event"}
    end
    if info.completed then
        Write{
            sub = "completed",
            causetext = string.format("%s%sproject points %d of %d", owner ~= nil and owner.name or "A Hero", History.DOT, info.after, info.goal),
        }
    end
end

--"Interest 2 to 3", or nil when it did not move.
local function MeterWords(label, meter)
    if meter == nil or meter.before == meter.after then
        return nil
    end
    return string.format("%s %d to %d", label, meter.before, meter.after)
end

--Negotiation (5.1f, L62-L68). info comes from NegotiationRun.Note. Each line keeps two
--cause texts: the Director's, with the numbers, and the players', where interest reads as
--its band and patience is left out unless the Director was showing the numbers (info.raw).
local function OnNegotiation(info)
    if not History.Enabled() then
        return
    end
    local npc = info.npc or "the NPC"
    local interest = MeterWords("Interest", info.interest)
    local patience = MeterWords("Patience", info.patience)
    local band = nil
    if info.bands ~= nil and info.bands.before ~= info.bands.after then
        band = string.format("%s to %s", info.bands.before, info.bands.after)
    end
    --what follows the lead on each cause line: full has the numbers, shown has the band.
    local function Causes(lead, withPatience)
        local full, shown = {lead}, {lead}
        full[#full + 1] = interest
        shown[#shown + 1] = band
        if withPatience then
            full[#full + 1] = patience
        end
        return table.concat(full, History.DOT), table.concat(shown, History.DOT)
    end

    local entry = {kind = "line", family = "negotiation", sub = info.kind, map = game.currentMapId, name = npc, raw = info.raw}
    local token = info.heroid ~= nil and info.heroid ~= "" and dmhub.GetCharacterById(info.heroid) or nil
    if token ~= nil then
        entry.who = History.Creature(token)
    end

    if info.kind == "began" then
        entry.causetext = string.format("Interest %d%sPatience %d", info.interest.after, History.DOT, info.patience.after)
        entry.playercause = info.bands.after
    elseif info.kind == "argument" then
        entry.total = info.total
        entry.text = info.text
        entry.cue = info.cue
        entry.causetext, entry.playercause = Causes(string.format("Argument%sTier %d", History.DOT, info.tier or 0), true)
    elseif info.kind == "pitfall" then
        entry.trait = info.trait
        local full, shown = {}, {}
        full[#full + 1] = interest
        full[#full + 1] = patience
        shown[#shown + 1] = band
        entry.causetext = #full > 0 and table.concat(full, History.DOT) or nil
        entry.playercause = #shown > 0 and table.concat(shown, History.DOT) or nil
    elseif info.kind == "read" then
        entry.total = info.total
        local lead = string.format("Read %s%sTier %d%s%s", npc, History.DOT, info.tier or 0, History.DOT,
            info.learned and "Learned something" or "Learned nothing")
        entry.playercause = lead
        entry.causetext = patience ~= nil and (lead .. History.DOT .. patience) or lead
    elseif info.kind == "reveal" then
        entry.trait = info.trait
        entry.causetext = info.traitKind == "pitfall" and "Pitfall" or "Motivation"
        entry.playercause = entry.causetext
    elseif info.kind == "adjust" then
        --the Director's own correction: players get no line (L67).
        entry.directoronly = true
        entry.causetext = "Director"
        entry.which = info.which
        entry.before = info.which == "interest" and info.interest.before or info.patience.before
        entry.after = info.which == "interest" and info.interest.after or info.patience.after
    elseif info.kind == "ended" then
        entry.causetext = info.offer ~= nil and info.offer ~= "" and ("Final offer: " .. info.offer) or "No deal"
        entry.playercause = entry.causetext
    else
        return
    end
    History.AddCombatFacts(entry)
    History.Write(entry)
end

local function Count(n, one, many)
    return string.format("%d %s", n, n == 1 and one or many)
end

--Montages (5.1e, L58-L61). info.kind: "test" (an Encounter of the Week test), "threat" (one
--whose consequence landed), "ended", or "counter" (the Director moved a journal montage's
--successes or failures). Written by the host, or the Director who moved the counter.
local function OnMontage(info)
    if not History.Enabled() then
        return
    end
    local map = game.currentMapId
    if info.kind == "test" then
        local token = info.heroid ~= nil and dmhub.GetCharacterById(info.heroid) or nil
        if token == nil then
            return
        end
        --a roster Hero may stand on no map, or another: the line belongs to the map shown.
        WriteLine(token, "montagetest", {
            map = map,
            total = info.total,
            tier = info.tier,
            causetext = string.format("%s: %s%sTier %d", info.entry or "", info.option or "", History.DOT, math.min(info.tier, 3)),
        })
        return
    end
    local entry = {kind = "line", map = map}
    if info.kind == "threat" then
        entry.family = "montagethreat"
        entry.name = info.name
        local applied = {}
        for _, text in ipairs(info.applied or {}) do
            applied[#applied + 1] = tostring(text)
        end
        entry.causetext = #applied > 0 and table.concat(applied, History.DOT) or nil
    elseif info.kind == "ended" and info.tests == 0 and (info.unvanquished or 0) == 0 then
        --a beat nobody rolled in and no threat touched (a "Proceed"): nothing to sum up.
        return
    elseif info.kind == "ended" then
        entry.family = "montageend"
        entry.causetext = table.concat({
            Count(info.successes or 0, "success", "successes"),
            Count(info.failures or 0, "failure", "failures"),
            Count(info.unvanquished or 0, "threat not vanquished", "threats not vanquished"),
        }, History.DOT)
    elseif info.kind == "counter" then
        entry.family = "montagecounter"
        entry.name = info.name
        entry.counter = info.counter
        entry.before = info.before
        entry.after = info.after
        entry.limit = info.limit
        entry.causetext = "Montage"
    else
        return
    end
    History.AddCombatFacts(entry)
    History.Write(entry)
end

local function OnEncounterEnded(creature)
    local token = dmhub.LookupToken(creature)
    if History.Enabled() and token ~= nil then
        ClosingEntry(token)
    end
end

local function OnEffectsEnded(creature, ended, cause)
    if not History.Enabled() then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    local names = {}
    local conditions = {}
    --names players may not see, kept beside each list of names as `hidden`.
    local hidden = nil
    for _, item in ipairs(ended) do
        local facts = EffectFacts(item, token)
        if facts ~= nil then
            names[#names + 1] = facts.name
            conditions[facts.name] = facts.iscondition
            if facts.secret then
                hidden = hidden or {}
                hidden[facts.name] = true
            end
        end
    end
    --the save's own line already says it ended.
    if #names == 0 or cause == "saved" then
        return
    end

    if cause == "endofencounter" then
        local closing = ClosingEntry(token)
        if closing ~= nil then
            closing.ended[#closing.ended + 1] = {who = History.Creature(token), names = names, hidden = hidden}
        end
        return
    end

    local causetext = cause
    if cause == "endturn" then
        causetext = "End of turn"
    elseif cause == "endround" then
        causetext = "End of round"
    elseif cause == "dying" then
        causetext = History.Creature(token).name .. " is dying"
    elseif cause == "rest" then
        causetext = "Respite began"
    end

    if causetext == nil and GameSystem.IsHandEdit() then
        causetext = NoteHand({}).causetext
    end
    if causetext == nil then
        local state = OpenCast(nil)
        if state ~= nil then
            local target = RowTarget(state, token)
            if target ~= nil then
                target.ended = target.ended or {}
                target.endedconds = target.endedconds or {}
                for _, name in ipairs(names) do
                    target.ended[#target.ended + 1] = name
                    target.endedconds[name] = conditions[name]
                    if hidden ~= nil and hidden[name] then
                        target.endedhidden = target.endedhidden or {}
                        target.endedhidden[name] = true
                    end
                end
            end
            return
        end
        causetext = Cause(nil)
    end
    WriteEnded(token, names, causetext, hidden)
end

local function OnConditionImmune(creature, conditionid)
    local facts = EffectFacts{conditionid = conditionid}
    local state = History.Enabled() and OpenCast(nil) or nil
    local token = dmhub.LookupToken(creature)
    if facts == nil or state == nil or token == nil then
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.immune = target.immune or {}
        target.immune[#target.immune + 1] = string.lower(facts.name)
    end
end

--The condition a potency's rule text was about to apply, if it names one.
--- The conditions a rule text names, in the order it names them, as "weakened and slowed";
--- nil when it names none.
--- @param text string|nil
--- @return string|nil
local function ConditionsIn(text)
    if text == nil then
        return nil
    end
    text = string.lower(text)
    local found = {}
    for _, info in unhidden_pairs(GetTableCached(CharacterCondition.tableName)) do
        local name = string.lower(info.name)
        local at = string.find(text, name, 1, true)
        if at ~= nil then
            found[#found + 1] = {name = name, at = at}
        end
    end
    if #found == 0 then
        return nil
    end
    table.sort(found, function(a, b)
        return a.at < b.at
    end)
    local names = {}
    for i, item in ipairs(found) do
        names[i] = item.name
    end
    if #names == 1 then
        return names[1]
    end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

--- The ongoing effect a rule text names, as the effect is named ("Can't Hide"); nil when it
--- names none. The longest whole-word match wins, so a short name inside another can't.
--- @param text string|nil
--- @return string|nil
local function EffectIn(text)
    if text == nil then
        return nil
    end
    --the rules code strips apostrophes before the potency check ("cant hide"), so both
    --sides drop them.
    text = " " .. string.gsub(string.lower(text), "'", "") .. " "
    local best = nil
    for _, info in unhidden_pairs(GetTableCached(CharacterOngoingEffect.tableName)) do
        local name = info.name
        if type(name) == "string" and #name >= 4 and (best == nil or #name > #best) then
            local bare = string.gsub(string.lower(name), "'", "")
            local at = string.find(text, bare, 1, true)
            if at ~= nil then
                local before = string.sub(text, at - 1, at - 1)
                local after = string.sub(text, at + #bare, at + #bare)
                if not string.match(before, "%w") and not string.match(after, "%w") then
                    best = name
                end
            end
        end
    end
    return best
end

--- @param creature creature
--- @param ruleText string|nil What the potency gates, as written after it.
--- @param stoppedText string|nil Text after a "#" stop marker: when the gated part is
--- applied by another behavior, the condition is named here instead.
local function OnResisted(creature, ruleText, stoppedText)
    local state = History.Enabled() and OpenCast(nil) or nil
    local token = dmhub.LookupToken(creature)
    if state == nil or token == nil then
        return
    end
    local target = RowTarget(state, token)
    if target ~= nil then
        target.resisted = ConditionsIn(ruleText) or ConditionsIn(stoppedText) or true
        if target.resisted == true then
            target.resistedeffect = EffectIn(ruleText) or EffectIn(stoppedText)
        end
    end
end

--- One potency test a target faced (6.6a).
--- @class HistoryPotency
--- @field letter string M, A, R, I or P, as the stat block writes it.
--- @field attr string The characteristic's name ("Reason").
--- @field attrid string For Monster Knowledge: whether players may see the monster's value.
--- @field value number The target's characteristic.
--- @field gate number The potency it was tested against, after anything raised it.
--- @field resisted boolean
--- @field what? string The condition it gated ("slowed"), or nil.
--- @field effect? string The ongoing effect it gated ("Can't Hide") when no condition.
--- @field raised? number How much the roll's modifiers raised the potency.
--- @field surges? number Surges spent to raise it, when surges did all of the raising.
--- @field mk? string The target's Monster Knowledge key, when it is a monster.

--- Every potency test (resisted or not), kept on the target's place in the row so the Why
--- can say what was tested and why it went the way it did.
--- @param creature creature
--- @param info {attrid: string, letter: string, value: number, gate: number, resisted: boolean, text: string|nil, stopped: string|nil}
local function OnPotency(creature, info)
    local state = History.Enabled() and OpenCast(nil) or nil
    local token = dmhub.LookupToken(creature)
    if state == nil or token == nil then
        return
    end
    local target = RowTarget(state, token)
    if target == nil then
        return
    end
    local attrInfo = creature.attributesInfo[info.attrid]
    --- @type HistoryPotency
    local test = {
        letter = info.letter,
        attr = attrInfo ~= nil and attrInfo.description or info.letter,
        attrid = info.attrid,
        value = info.value,
        gate = info.gate,
        resisted = info.resisted,
        what = ConditionsIn(info.text) or ConditionsIn(info.stopped),
    }
    if test.what == nil then
        test.effect = EffectIn(info.text) or EffectIn(info.stopped)
    end
    local sources = state.cast ~= nil and state.cast:try_get("targetPotencySources", {})[token.charid] or nil
    if sources ~= nil then
        local raised, surges, allSurges = 0, 0, true
        for _, source in ipairs(sources) do
            raised = raised + (source.potency or 0)
            if source.surges ~= nil then
                surges = surges + source.surges
            else
                allSurges = false
            end
        end
        if raised ~= 0 then
            test.raised = raised
            test.surges = allSurges and surges > 0 and surges or nil
        end
    end
    if not creature:IsHero() then
        test.mk = MonsterKnowledge.KeyForToken(token)
    end
    target.potency = target.potency or {}
    table.insert(target.potency, test)
end

--L111: the Director made a creature a squad's captain (DrawSteelMinion.SetSquadCaptain).
--- @param creature creature
--- @param info {squad: string}
local function OnCaptain(creature, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil then
        return
    end
    WriteLine(token, "captain", {squad = info.squad, causetext = dmhub.isDM and "Director" or dmhub.userDisplayName})
end

--A save is a roll the table watched, so it earns a line whether it passed or not. The
--line says everything, so the cast that made the roll gets no row of its own.
local function OnSaved(creature, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil then
        return
    end
    local state = g_casts[info.options]
    if state ~= nil then
        state.noRow = true
    end
    local rolled = string.format("rolled %d (%d or more ends it)", info.total, info.target)
    --a save rolled out of players' sight keeps its outcome, which they saw, but not its number.
    local privacy = RollUtils.RollPrivacy(info.rollInfo, info.details)
    if privacy ~= nil and info.atturnend then
        privacy.cause = "End of turn"
    end
    WriteLine(token, "save", {
        name = info.name,
        passed = info.passed,
        privacy = privacy,
        causetext = info.atturnend and ("End of turn: " .. rolled) or string.upper_first(rolled),
    })
end

--A test rolled outside an ability: the character panel, Hero sheet, a journal, or one the
--Director requested (L44). It keeps its roll in an action's shape, so its card can show it.
local function OnTested(creature, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil or info.total == nil then
        return
    end
    local roll = {
        total = info.total,
        edges = info.edges,
        banes = info.banes,
        tier = info.tier,
        natural = info.natural,
        characteristic = info.characteristic,
        sources = info.sources ~= nil and EdgeSources(info.sources) or nil,
        overridden = info.overridden,
    }
    if #info.dice == 2 then
        roll.low = math.min(info.dice[1], info.dice[2])
        roll.high = math.max(info.dice[1], info.dice[2])
    end
    if info.natural ~= nil then
        local edgeBonus = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(info.edges or 0, info.banes or 0)
        if info.cause ~= nil then
            --an opposed power roll has no tiers: every edge or bane that counts is 2.
            edgeBonus = 2 * math.min(info.edges or 0, 2) - 2 * math.min(info.banes or 0, 2)
        end
        local value = info.characteristic ~= nil and info.characteristic.value or 0
        local bonus = info.total - info.natural - edgeBonus - value
        roll.bonus = bonus ~= 0 and bonus or nil
    end
    local privacy = info.privacy
    if privacy ~= nil then
        --what a player who may not see the result reads under the line (L79).
        privacy.cause = info.name
    end
    WriteLine(token, "test", {
        name = info.name,
        total = info.total,
        roll = roll,
        privacy = privacy,
        --a roll an ability asked for (an opposed power roll) goes under that ability's row;
        --its total is compared with the other side's, so it has no tier of its own.
        cause = info.cause,
        causetext = (info.cause ~= nil and info.name or string.format("%s%sTier %d", info.name, History.DOT, info.tier))
            .. (info.overridden ~= nil and (History.DOT .. "Overridden") or ""),
    })
end

--A Dice panel roll (L45). It is named for the character the roller is acting as (selected,
--else their own); with none, the player, or "Director" for the Director.
local function OnDiceRoll(rollInfo, kind)
    if not History.Enabled() or rollInfo.total == nil then
        return
    end
    local token = dmhub.currentToken
    local text = type(rollInfo.rollStr) == "string" and trim(rollInfo.rollStr) or ""
    local faces = {}
    for _, roll in ipairs(rollInfo.rolls or {}) do
        if roll.dropped ~= true then
            faces[#faces + 1] = roll.result
        end
    end
    --the Power Roll tile is two d10s, so it has a tier; other dice don't.
    local tier = kind == "power" and RollUtils.DiceResultToTier(rollInfo) or nil
    local cause = text ~= "" and text or nil
    if tier ~= nil then
        cause = string.format("%s%sTier %d", cause or "2d10", History.DOT, tier)
    end
    local entry = {
        kind = "line",
        family = "dice",
        map = (token ~= nil and token.mapid) or game.currentMapId,
        total = rollInfo.total,
        dice = faces,
        tier = tier,
        edges = rollInfo.boons,
        banes = rollInfo.banes,
        causetext = cause,
    }
    --the Dice panel offers Visible or GM only, never the Dice Tower.
    local privacy = RollUtils.RollPrivacy(rollInfo, nil)
    if privacy ~= nil then
        privacy.cause = text ~= "" and text or nil
        entry.privacy = privacy
    end
    if token ~= nil then
        entry.who = History.Creature(token)
    else
        entry.roller = dmhub.isDM and "Director" or rollInfo.playerName
    end
    History.AddCombatFacts(entry)
    History.Write(entry)
end

--A table's result is cut to this many characters under its line; the card has all of it.
local TABLE_RESULT_SHOWN = 60

--A roll on a table (L76-L78): a journal's table, a Director's request, an ability's (under
--its row) or a project event the Director rolled (L77). info: see RollOnTableProperties.NotifyRolled.
local function OnTableRolled(roller, info)
    if not History.Enabled() then
        return
    end
    local result = info.result
    if result ~= nil and #result > TABLE_RESULT_SHOWN then
        result = string.sub(result, 1, TABLE_RESULT_SHOWN - 3) .. "..."
    end
    local cause = info.project ~= nil and (info.project .. " event") or info.table
    if result ~= nil then
        cause = cause .. History.DOT .. result
    end
    if info.overridden ~= nil then
        cause = cause .. History.DOT .. "Overridden"
    end
    local token = roller ~= nil and dmhub.LookupToken(roller) or nil
    local entry = {
        kind = "line",
        family = "table",
        map = (token ~= nil and token.mapid) or game.currentMapId,
        name = info.table,
        project = info.project,
        total = info.rolled,
        dice = info.dice,
        result = info.result,
        overridden = info.overridden,
        cause = info.cause,
        causetext = cause,
    }
    --a roll out of players' sight: they may read which table it was, not what it gave (L79).
    local privacy = RollUtils.RollPrivacy(info.rollInfo, info.details)
    if privacy ~= nil then
        privacy.cause = info.project ~= nil and (info.project .. " event") or info.table
        entry.privacy = privacy
    end
    --the Director rolls a project's event for the Hero, so the line is the Director's.
    if token ~= nil and info.project == nil then
        entry.who = History.Creature(token)
    else
        entry.roller = dmhub.isDM and "Director" or dmhub.userDisplayName
    end
    History.AddCombatFacts(entry)
    History.Write(entry)
end

--A Director's or player's macro gave a Hero something (L82-L85). info: {kind, before, after}
--for victories, renown and wealth; {kind, name, quantity} for an item; {kind, name} for a title.
local function OnAwarded(creature, info)
    local token = dmhub.LookupToken(creature)
    if not History.Enabled() or token == nil then
        return
    end
    WriteLine(token, "award", {
        sub = info.kind,
        name = info.name,
        quantity = info.quantity,
        before = info.before,
        after = info.after,
        causetext = dmhub.isDM and "Director" or dmhub.userDisplayName,
    })
end

--Stamina set to a number rather than dealt or healed (L88): a sheet field, the Stamina
--bar's number, or a Set Stamina step outside any action row.
local function OnStaminaSet(creature, before, after, note)
    if not History.Enabled() then
        return
    end
    local token = dmhub.LookupToken(creature)
    if token == nil then
        return
    end
    WriteLine(token, "staminaset", NoteHand{before = before, after = after, causetext = Cause(note),
        mk = StaminaGateKey(token)})
end

--A wave of reinforcements arrived (L89): one line naming the wave, with who came under it,
--counted by name. If any arrival was hidden from players as it landed, players get no line
--until the Director reveals it.
local function OnWaveDeployed(info)
    if not History.Enabled() then
        return
    end
    local arrivals = {}
    local byName = {}
    local hidden = false
    local map = nil
    for _, token in ipairs(info.tokens) do
        if token.valid then
            map = map or token.mapid
            local who = History.Creature(token)
            --tokens are numbered ("Goblin Sniper 2"), so arrivals count by stat block; a
            --creature whose name players may not see counts apart from one they may.
            local kind = token.properties:try_get("monster_type")
            if type(kind) ~= "string" or kind == "" then
                kind = who.name
            end
            local key = (who.secret and "?" or "") .. kind
            local group = byName[key]
            if group == nil then
                group = {who = who, name = kind, count = 0}
                byName[key] = group
                arrivals[#arrivals + 1] = group
            end
            group.count = group.count + 1
            if token.invisibleToPlayers or token.properties:IsHidden() then
                hidden = true
            end
        end
    end
    if #arrivals == 0 then
        return
    end
    local entry = {
        kind = "line",
        family = "reinforcements",
        map = map or game.currentMapId,
        name = info.name or "Reinforcements",
        arrivals = arrivals,
        hiddenfromplayers = hidden or nil,
    }
    History.AddCombatFacts(entry)
    History.Write(entry)
end

--The current map's reveal lines for one spoilered modifier (L94).
local function RevealEntries(key)
    local mapid = game.currentMapId
    local found = {}
    for _, k in ipairs(History.Keys(mapid)) do
        local e = History.Entry(mapid, k)
        if e ~= nil and e.family == "reveal" and e.spoilerkey == key then
            found[#found + 1] = e
        end
    end
    return found
end

--The Director revealed a spoilered modifier (L94): who it belongs to, its name and what it
--does. Revealing it again after hiding it shows the same line again, not another one.
--info: {key, name, description, tokenid}.
local function OnSpoilerRevealed(info)
    if not History.Enabled() or #RevealEntries(info.key) > 0 then
        return
    end
    local token = (info.tokenid ~= nil and info.tokenid ~= "") and dmhub.GetCharacterById(info.tokenid) or nil
    local description = PowerRollSpoilers.Strip(info.description or "")
    local entry = {
        kind = "line",
        family = "reveal",
        map = token ~= nil and token.mapid or game.currentMapId,
        who = token ~= nil and History.Creature(token) or nil,
        name = PowerRollSpoilers.Strip(info.name or ""),
        causetext = description ~= "" and description or nil,
        spoilerkey = info.key,
    }
    History.AddCombatFacts(entry)
    History.Write(entry)
end

--The Director's eye on a revealed modifier: its line follows it, so hiding the modifier
--again hides the line from players (the Director keeps it, with the eye-off icon).
local function OnSpoilerVisibility(key, revealed)
    if not History.Enabled() then
        return
    end
    local change = {}
    for _, e in ipairs(RevealEntries(key)) do
        if (e.hiddenfromplayers == true) == revealed then
            change[#change + 1] = e
        end
    end
    if #change > 0 then
        History.SetHiddenFromPlayers(change, not revealed)
    end
end

--Revert Turn or Turn Rewind restored the board (L39, L40). History is not part of the
--checkpoint, so nothing is erased: what came after it is marked Reverted, under one
--"Turn reverted" line. info: {since, turnkey, turn}: turnkey for Turn Rewind, turn (the
--encounter, round and turn undone) for Revert Turn.
--What History held when each Turn Rewind point was recorded, by the point. Weak keys: the
--points are Turn Rewind's own tables and go when it drops them.
local g_heldAtPoint = setmetatable({}, {__mode = "k"})

local function OnRewindPoint(point)
    if not History.Enabled() or game.currentMapId == nil then
        return
    end
    g_heldAtPoint[point] = {mapid = game.currentMapId, keys = History.HeldKeys(game.currentMapId)}
end

local function OnTurnReverted(info)
    if not History.Enabled() or info.since == nil then
        return
    end
    local mapid = game.currentMapId
    --Turn Rewind: what came after the point is what History didn't hold yet (not the stamps,
    --which a client whose clock runs behind writes early).
    local heldAt = info.point ~= nil and g_heldAtPoint[info.point] or nil
    local held = heldAt ~= nil and heldAt.mapid == mapid and heldAt.keys or nil
    local line = {
        kind = "line",
        family = "reverted",
        map = mapid,
        causetext = dmhub.isDM and "By the Director" or ("By " .. dmhub.userDisplayName),
        wholeturn = info.turn ~= nil or nil,
    }
    History.AddCombatFacts(line)
    History.SetReverted(mapid, info.since, info.turnkey or dmhub.GenerateGuid(), line, info.turn, held)
end

local PERSISTENCE_WORDS = {
    chose = "Chose to stop",
    targetsgone = "All its targets are dead",
}

local function OnPersistenceEnded(creature, abilityName, reason)
    local token = dmhub.LookupToken(creature)
    if History.Enabled() and token ~= nil then
        local causetext = PERSISTENCE_WORDS[reason] or Cause(nil)
        --L16: Persistent Magic stops it at 5 times Reason damage in one turn.
        if reason == "damage" then
            local reasonScore = creature:AttributeMod("rea")
            causetext = string.format("Took %d damage in one turn, 5 times Reason %d",
                creature:try_get("damageTakenThisTurn", 0), reasonScore)
        end
        WriteLine(token, "persistence", {
            name = abilityName,
            causetext = causetext,
        })
    end
end

local function HasLapsedEffect(props)
    for _, instance in ipairs(props:try_get("ongoingEffects", {})) do
        if instance.typeName == "CharacterOngoingEffectInstance" and instance:Expired() then
            return true
        end
    end
    return false
end

--Timers and concentration lapse with no one removing anything: the game just stops
--counting them. At each turn end this clears them, which is how they get reported.
local function OnTurnEnded(creature)
    if not History.Enabled() then
        return
    end
    for _, token in ipairs(dmhub.allTokens) do
        local props = token.properties
        if props ~= nil and HasLapsedEffect(props) then
            token:ModifyProperties{
                description = "Clear lapsed effects",
                undoable = false,
                execute = function()
                    props:EndingEffects("endturn", function()
                        props.ongoingEffects = props:ActiveOngoingEffects(true)
                    end)
                end,
            }
        end
    end
end

GameSystem.RegisterPlayObserver("history", {
    began = CastBegan,
    finished = CastFinished,
    damage = OnDamage,
    heal = OnHeal,
    threshold = OnThreshold,
    forcedmove = OnForcedMove,
    teleported = OnTeleported,
    opposed = OnOpposed,
    fell = OnFell,
    minionsdied = OnMinionsDied,
    temporarystamina = OnTemporaryStamina,
    staminaset = OnStaminaSet,
    wavedeployed = OnWaveDeployed,
    spoilerrevealed = OnSpoilerRevealed,
    spoilervisibility = OnSpoilerVisibility,
    turnreverted = OnTurnReverted,
    resource = OnResource,
    globalresource = OnGlobalResource,
    effectstarted = OnEffectStarted,
    effectsended = OnEffectsEnded,
    conditionimmune = OnConditionImmune,
    resisted = OnResisted,
    potency = OnPotency,
    captain = OnCaptain,
    saved = OnSaved,
    tested = OnTested,
    diceroll = OnDiceRoll,
    tablerolled = OnTableRolled,
    awarded = OnAwarded,
    persistenceended = OnPersistenceEnded,
    combatbegan = OnCombatBegan,
    montage = OnMontage,
    negotiation = OnNegotiation,
    downtime = OnDowntime,
    resting = OnResting,
    rested = OnRested,
    encounterended = OnEncounterEnded,
    turnended = OnTurnEnded,
    typedmessage = OnTypedMessage,
    note = OnNote,
    actorcredited = OnActorCredited,
    rewindpoint = OnRewindPoint,
})
