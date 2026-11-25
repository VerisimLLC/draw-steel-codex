local mod = dmhub.GetModLoading()

--The card's words are in HistoryText.lua.
local T = UIText.T

local Int = History.Int

--The detail card: what a row in the History tray did, one click from that row. This file
--holds what the card says and draws it; the tray decides where it sits. The sentences
--are worked out from the entry when the card opens, so none of this runs during play.

--- One line of What happened.
--- @class HistoryStoryRow
--- @field who HistoryCreature[] Who it is about. The first one's face shows.
--- @field words? string What happened, following the name: " took 5 damage."
--- @field text? string The whole sentence, when it is more than a name and words.
--- @field amount? number What landed: negative for damage, positive for healing.
--- @field ended? boolean It takes an Ended tag.

--The card's width beside the tray, and its padding either side of the words.
History.CARD_WIDTH = 384
local CARD_PAD = 14

--The tail's square: turned 45 degrees it points about 11 px out, across the 12 px gap.
local TAIL_SIZE = 16

--A What happened row's face, and the gap between it and the sentence.
local STORY_FACE = 24
local STORY_GAP = 9

--Room kept at the end of a story row for its number.
local STORY_NUMBER_WIDTH = 44

--Room kept beside a sentence for an Ended tag.
local ENDED_TAG_WIDTH = 60

--The single guillemet is in the Codex's fonts; Lua source must stay ASCII, so it is
--written as its UTF-8 bytes.
local BACK_TEXT = "\226\128\185 " .. T("history.card.back")

--The section heading's words, for the rule that runs on from them.
local WHAT_HAPPENED_WIDTH = 104
local THE_NUMBERS_WIDTH = 88
local WHY_WIDTH = 28

--A Why line's text sits this far in from its rule on the left.
local WHY_INDENT = 12

--The receipt's number column, on the right of every line.
local VALUE_WIDTH = 56

--No phrase for EoE: the Codex also stores "no timer" as EoE, so a fall's Prone would read
--as lasting the whole encounter when it ends on standing up.
local DURATION_PHRASES = {
    ["save ends"] = T("history.story.duration.save_ends"),
    EoT = T("history.story.duration.eot"),
}

--"a", "a and b", "a, b and c".
local function JoinWords(words, last)
    if #words <= 1 then
        return words[1] or ""
    end
    local most = {}
    for i = 1, #words - 1 do
        most[i] = words[i]
    end
    return string.format("%s %s %s", table.concat(most, ", "), last or T("history.join.and"), words[#words])
end

local function Squares(count)
    return UIText.Plural("history.story.squares", count, {count = Int(count)})
end

--The type of damage that is all one type, else nil.
local function SingleType(who)
    local only = next(who.types or {})
    if only == nil or next(who.types, only) ~= nil or who.types[only] < who.taken then
        return nil
    end
    return only
end

--"took 5 damage", "took 5 fire damage" or "took 8 damage: 4 fire and 4 cold". True
--second means the words end on a list, so nothing can follow them with "and".
local function DamageWords(who)
    local only = SingleType(who)
    if only ~= nil then
        return T("history.story.took_typed_damage", {amount = Int(who.taken), type = only}), false
    end
    if who.types == nil or next(who.types) == nil then
        return T("history.story.took_damage", {amount = Int(who.taken)}), false
    end

    local names = {}
    local typed = 0
    for name, amount in pairs(who.types) do
        names[#names + 1] = name
        typed = typed + amount
    end
    table.sort(names)
    local parts = {}
    for i, name in ipairs(names) do
        parts[i] = T("history.story.damage_part", {amount = Int(who.types[name]), type = name})
    end
    if typed < who.taken then
        parts[#parts + 1] = T("history.story.damage_part_untyped", {amount = Int(who.taken - typed)})
    end
    return T("history.story.took_damage_parts", {amount = Int(who.taken), parts = JoinWords(parts)}), true
end

--- True when an area ability hit a creature on its user's side.
--- @param entry HistoryEntry
--- @param who HistoryCreature
--- @return boolean
function History.IsAllyHit(entry, who)
    local actor = entry.actor
    return actor ~= nil and entry.ability ~= nil and entry.ability.area == true
        and (who.taken or 0) > 0 and who.id ~= actor.id and who.hero == actor.hero
end

--What moved it. A push, a fall or both: the fall reads "it fell".
--afterDamage: it follows a colon, so it needs no "was".
--Stability and walls broken go with the push they changed.
local function MovedWords(moved, afterDamage)
    local kind = string.gsub(moved.kind, "vertical_", "")
    if moved.immune then
        return T("history.story.moved.immune")
    end
    if moved.stopped then
        return T("history.story.moved.held_ground", {stability = Int(moved.stability), kind = kind})
    end
    local verb = History.MOVED_VERBS[kind] or T("history.moved_verb.moved")
    if moved.distance <= 0 and moved.fell <= 0 then
        --blocked before it moved a square.
        local words = T("history.story.moved.blocked")
        if (moved.stability or 0) > 0 then
            words = T("history.story.moved.with_stability", {words = words, stability = Int(moved.stability)})
        end
        return words
    end
    if moved.distance <= 0 then
        return T("history.story.moved.fell", {squares = Squares(moved.fell)})
    end
    local words = T("history.story.moved.distance", {verb = verb, squares = Squares(moved.distance)})
    if (moved.stability or 0) > 0 and (moved.requested or 0) > moved.distance then
        words = T("history.story.moved.distance_of", {verb = verb, distance = Int(moved.distance), requested = Int(moved.requested), stability = Int(moved.stability)})
    end
    local walls = moved.walls or 0
    if walls > 0 then
        words = T("history.story.moved.breaking", {words = words, walls = UIText.Plural("history.story.moved.walls", walls, {count = Int(walls)})})
    end
    if moved.fell > 0 then
        words = T("history.story.moved.then_fell", {words = words, squares = Squares(moved.fell)})
    end
    return afterDamage and words or T("history.story.moved.was", {words = words})
end

--Everything that happened to one creature, as what follows its name. Nil if nothing did.
--Starts with a space, or with "'s" or "," when the words can't be shared by a group.
--- @param who HistoryCreature
--- @param isAlly? boolean
--- @return string|nil
local function Predicate(who, isAlly)
    --each of these reads straight after the creature's name.
    local verbs = {}
    --each of these has a subject of its own.
    local notes = {}
    --the first verb ends on a list, so the rest start a sentence of their own.
    local splitLead = false

    if (who.taken or 0) > 0 then
        local words, split = DamageWords(who)
        --struck by a squad: "took 6 damage from 2 minions".
        if (who.byminions or 0) > 0 and not split then
            words = T("history.story.from_minions", {words = words, minions = UIText.Plural("history.story.minions", who.byminions, {count = Int(who.byminions)})})
        end
        splitLead = split
        if who.soaked ~= nil then
            words = T("history.story.soaked", {words = words, soaked = Int(who.soaked)})
        end
        if isAlly then
            words = T("history.story.caught_in_area", {words = words})
        end
        verbs[1] = words
    end
    if (who.healed or 0) > 0 then
        verbs[#verbs + 1] = T("history.story.regained", {amount = Int(who.healed)})
    end

    local moved = who.moved
    if moved ~= nil then
        if moved.distance > 0 and moved.fell > 0 and #verbs == 1 and (who.taken or 0) > 0 and not splitLead then
            verbs[1] = T("history.story.damage_then_moved", {damage = verbs[1], moved = MovedWords(moved, true)})
            splitLead = true
        else
            verbs[#verbs + 1] = MovedWords(moved, false)
        end
    end
    if who.landedon then
        verbs[#verbs + 1] = T("history.story.landed_on")
    end

    local adjectives = {}
    if who.state == "winded" or who.state == "dying" then
        adjectives[1] = T("history.story.now_state", {state = who.state})
    end
    for _, condition in ipairs(who.conds or {}) do
        local duration = DURATION_PHRASES[condition.duration] or ""
        if condition.renewed then
            --it still had it, so the ability only renewed it.
            notes[#notes + 1] = T("history.story.renewed", {name = condition.name})
        elseif condition.iscondition then
            adjectives[#adjectives + 1] = string.lower(condition.name) .. duration
        else
            verbs[#verbs + 1] = T("history.story.gained_effect", {name = condition.name, duration = duration})
        end
    end
    if #adjectives > 0 then
        verbs[#verbs + 1] = T("history.story.is", {conditions = JoinWords(adjectives)})
    end
    if who.state == "killed" then
        verbs[#verbs + 1] = T("history.story.killed")
    end
    if type(who.resisted) == "string" then
        verbs[#verbs + 1] = T("history.story.resisted_being", {conditions = who.resisted})
    elseif who.resisted and who.resistedeffect ~= nil then
        --an ongoing effect, not a condition: "resisted Can't Hide".
        verbs[#verbs + 1] = T("history.story.resisted_effect", {effect = who.resistedeffect})
    elseif who.resisted then
        verbs[#verbs + 1] = T("history.story.resisted")
    end

    local noLonger = {}
    if who.recovered ~= nil then
        noLonger[1] = who.recovered
    end
    local endedConditions = who.endedconds or {}
    for _, name in ipairs(who.ended or {}) do
        if endedConditions[name] then
            noLonger[#noLonger + 1] = string.lower(name)
        else
            notes[#notes + 1] = T("history.story.effect_ended", {name = name})
        end
    end
    if #noLonger > 0 then
        verbs[#verbs + 1] = T("history.story.no_longer", {states = JoinWords(noLonger, T("history.join.or"))})
    end
    if who.pool ~= nil then
        notes[#notes + 1] = T("history.story.temporary_stamina", {before = Int(who.pool.before), after = Int(who.pool.after)})
    end

    local words = nil
    if #verbs == 0 then
        if #notes > 0 then
            words = T("history.story.predicate.notes_only", {notes = JoinWords(notes)})
        end
    elseif splitLead then
        words = T("history.story.predicate.verbs", {verbs = table.remove(verbs, 1)})
        if #verbs > 0 then
            words = T("history.story.predicate.then_it", {words = words, verbs = JoinWords(verbs)})
        end
        if #notes > 0 then
            words = T("history.story.predicate.then_notes", {words = words, notes = string.upper_first(JoinWords(notes))})
        end
    else
        for _, note in ipairs(notes) do
            verbs[#verbs + 1] = note
        end
        words = T("history.story.predicate.verbs", {verbs = JoinWords(verbs)})
    end

    if who.immune ~= nil then
        local immune = JoinWords(who.immune, T("history.join.or"))
        if words == nil then
            words = T("history.story.predicate.immune", {conditions = immune})
        else
            words = T("history.story.predicate.then_immune", {words = words, conditions = immune})
        end
    end
    if words ~= nil and isAlly then
        words = T("history.story.predicate.ally", {words = words})
    end
    return words
end

--"Goblin 1-4" when names differ only by a run of numbers, else a list.
local function GroupNames(group)
    local base = nil
    local numbers = {}
    local numbered = true
    for i, who in ipairs(group) do
        local stem, number = string.match(History.ShownName(who), "^(.-)%s+(%d+)$")
        if stem == nil or (base ~= nil and stem ~= base) then
            numbered = false
            break
        end
        base = stem
        numbers[i] = tonumber(number)
    end
    if numbered and #group > 1 then
        table.sort(numbers)
        --a run only: 1, 1, 3 spans as far as 1-3 but is not it.
        local run = true
        for i = 2, #numbers do
            run = run and numbers[i] == numbers[i - 1] + 1
        end
        if run then
            return string.format("%s %d-%d", base, numbers[1], numbers[#numbers])
        end
    end
    local names = {}
    for i, who in ipairs(group) do
        names[i] = History.ShownName(who)
    end
    return JoinWords(names)
end

--- The sentence for one row of What happened.
--- @param row HistoryStoryRow
--- @return string
function History.StoryText(row)
    if row.text ~= nil then
        return row.text
    end
    if #row.who == 1 then
        return History.ShownName(row.who[1]) .. row.words
    end
    return T("history.story.each", {names = GroupNames(row.who), words = row.words})
end

--The amount a row's number shows.
local function LandedAmount(who)
    if (who.taken or 0) > 0 then
        return -who.taken
    end
    if (who.healed or 0) > 0 then
        return who.healed
    end
    return nil
end

--Adds a creature's row, or joins a row with the same result. Words that start with

--anything but a space can't take "each", so they stay alone.
local function AddCreature(rows, sameResult, who, isAlly)
    local words = Predicate(who, isAlly)
    if words == nil then
        return
    end
    local row = sameResult[words]
    if row ~= nil then
        row.who[#row.who + 1] = who
        return
    end
    row = {who = {who}, words = words, amount = LandedAmount(who)}
    rows[#rows + 1] = row
    if string.sub(words, 1, 1) == " " then
        sameResult[words] = row
    end
end

--Minion deaths by squad, added up across the batches that confirmed them.
local function SquadDeaths(kids)
    local deaths = {}
    for _, kid in ipairs(kids) do
        if kid.family == "minions" and kid.name ~= nil then
            local death = deaths[kid.name]
            if death == nil then
                death = {killed = 0, total = 0, left = 0, who = kid.who}
                deaths[kid.name] = death
            end
            local killed, left = kid.killed or 0, kid.left or 0
            death.killed = death.killed + killed
            death.total = math.max(death.total, killed + left)
            death.left = left
        end
    end
    return deaths
end

--"1 of 4 minions killed" or "the squad is destroyed".
local function DeathWords(death)
    if death.left <= 0 then
        return T("history.story.squad_destroyed")
    end
    return T("history.story.minions_killed", {killed = Int(death.killed), total = Int(death.total)})
end

--A squad reads as one creature: what it took together, then who that killed. What
--happened to its members besides reads as the squad's when it is the same for them all.
local function AddSquad(rows, sameResult, name, members, death)
    local whole = {taken = 0, types = {}}
    for _, who in ipairs(members) do
        whole.taken = whole.taken + (who.taken or 0)
        for damagetype, amount in pairs(who.types or {}) do
            whole.types[damagetype] = (whole.types[damagetype] or 0) + amount
        end
    end

    local shared = nil
    local isShared = true
    local others = {}
    for i, who in ipairs(members) do
        local other = table.shallow_copy(who)
        other.taken = nil
        other.types = nil
        other.soaked = nil
        if other.state == "killed" then
            other.state = nil
        end
        others[i] = other
        local words = Predicate(other)
        if i == 1 then
            shared = words
        elseif words ~= shared then
            isShared = false
        end
    end

    if members[1].secret and not dmhub.isDM then
        name = T("history.unknown_creature")
    end
    local text = nil
    if whole.taken > 0 then
        local words, split = DamageWords(whole)
        text = T("history.story.squad.took", {name = name, words = words})
        if death ~= nil and split then
            text = T("history.story.squad.then_deaths", {words = text, deaths = string.upper_first(DeathWords(death))})
        elseif death ~= nil then
            text = T("history.story.squad.deaths", {words = text, deaths = DeathWords(death)})
        end
        text = T("history.story.squad.end", {words = text})
    elseif death ~= nil then
        text = T("history.story.squad.only_deaths", {name = name, deaths = DeathWords(death)})
    end

    if isShared and shared ~= nil and string.sub(shared, 1, 1) == " " then
        if text ~= nil then
            text = T("history.story.squad.then_shared", {words = text, shared = shared})
        else
            text = T("history.story.squad.shared", {shared = shared})
        end
    end
    if text ~= nil then
        rows[#rows + 1] = {
            who = {members[1]},
            text = text,
            amount = whole.taken > 0 and -whole.taken or nil,
        }
    end
    if not isShared then
        for _, other in ipairs(others) do
            AddCreature(rows, sameResult, other)
        end
    end
end

--True when a target took damage and nothing else happened to it.
local function OnlyDamage(who)
    return (who.taken or 0) > 0 and (who.healed or 0) <= 0 and who.moved == nil and who.conds == nil
        and who.ended == nil and who.state == nil and who.recovered == nil and who.pool == nil
        and who.immune == nil and not who.resisted and not who.landedon
end

--What a nested trigger did, or a resource it changed.
local function AddKid(rows, kid)
    if kid.family == "resource" then
        local amount = kid.amount or 0
        local verb = cond(amount > 0, T("history.story.resource.gained"), T("history.story.resource.spent"))
        rows[#rows + 1] = {
            who = {kid.who},
            text = T("history.story.resource", {name = History.ShownName(kid.who), verb = verb,
                resource = History.ResourceWords(math.abs(amount), kid.name)}),
        }
        return
    end
    --an entry from an earlier build may lack its ability: nothing to name, so no row.
    if (kid.kind ~= "trigger" and kid.kind ~= "action") or kid.ability == nil then
        return
    end

    local owner = kid.ability.name
    if kid.actor ~= nil then
        owner = T("history.possessive", {owner = History.ShownName(kid.actor), name = kid.ability.name})
    end
    for _, who in ipairs(kid.targets or {}) do
        local name = History.ShownName(who)
        if OnlyDamage(who) and (who.types == nil or SingleType(who) ~= nil) then
            local damagetype = SingleType(who)
            rows[#rows + 1] = {
                who = {who},
                text = damagetype ~= nil and T("history.story.trigger_hit_typed", {ability = owner, name = name, amount = Int(who.taken), type = damagetype})
                    or T("history.story.trigger_hit", {ability = owner, name = name, amount = Int(who.taken)}),
                amount = -who.taken,
            }
        else
            local words = Predicate(who)
            if words ~= nil then
                rows[#rows + 1] = {
                    who = {who},
                    text = T("history.story.trigger_did", {ability = owner, name = name, words = words}),
                    amount = LandedAmount(who),
                }
            end
        end
    end
end

--- Whether this viewer may read the totals of an opposed power roll against one target: the
--- Director always, a player only when both the user's roll and that target's reached them
--- unhidden (a GM-only roll's line never arrives; a Dice Tower roll arrives without its result).
--- @param kids HistoryEntry[]|nil The entries nested under the action.
--- @param actor HistoryCreature|nil The ability's user.
--- @param target HistoryCreature The target the totals are for.
--- @return boolean
function History.OpposedTotalsShown(kids, actor, target)
    if dmhub.isDM then
        return true
    end
    if actor == nil then
        return false
    end
    local actorSeen, targetSeen = false, false
    for _, kid in ipairs(kids or {}) do
        if kid.family == "test" and kid.cause ~= nil and kid.total ~= nil and not kid.secretroll and kid.who ~= nil then
            if kid.who.id == actor.id then
                actorSeen = true
            elseif kid.who.id == target.id then
                targetSeen = true
            end
        end
    end
    return actorSeen and targetSeen
end

--- What happened, one row per creature, the result first.
--- @param entry HistoryEntry An action, or the closing line of an encounter.
--- @param kids? HistoryEntry[] What is nested under it.
--- @return HistoryStoryRow[]
function History.Story(entry, kids)
    local rows = {}
    --a negotiation argument: what the Hero said, then the stage's cue for how it landed.
    if entry.family == "negotiation" then
        if (entry.text or "") ~= "" then
            rows[#rows + 1] = {who = entry.who ~= nil and {entry.who} or {}, text = T("history.story.argument_said", {text = entry.text})}
        end
        if (entry.cue or "") ~= "" then
            rows[#rows + 1] = {who = {}, text = entry.cue}
        end
        return rows
    end
    if entry.family == "encounterend" then
        for _, item in ipairs(entry.ended or {}) do
            rows[#rows + 1] = {
                who = {item.who},
                text = T("history.story.encounter_ended", {name = History.ShownName(item.who), names = JoinWords(item.names)}),
                ended = true,
            }
        end
        return rows
    end

    kids = kids or {}
    local deaths = SquadDeaths(kids)
    local squads = {}
    for _, who in ipairs(entry.targets or {}) do
        if who.squad ~= nil then
            squads[who.squad] = squads[who.squad] or {}
            table.insert(squads[who.squad], who)
        end
    end

    local sameResult = {}
    for _, who in ipairs(entry.targets or {}) do
        local members = who.squad ~= nil and squads[who.squad] or nil
        if members == nil then
            AddCreature(rows, sameResult, who, History.IsAllyHit(entry, who))
        elseif members[1] == who then
            AddSquad(rows, sameResult, who.squad, members, deaths[who.squad])
            deaths[who.squad] = nil
        end
    end

    --a trigger can finish off a squad this action never touched. By name, so the rows
    --keep their order from one build of the card to the next.
    local squadNames = {}
    for name in pairs(deaths) do
        squadNames[#squadNames + 1] = name
    end
    table.sort(squadNames)
    for _, squadName in ipairs(squadNames) do
        local name, death = squadName, deaths[squadName]
        --a squad whose name players may not see, as AddSquad shows it.
        if death.who ~= nil and death.who.secret and not dmhub.isDM then
            name = T("history.unknown_creature")
        end
        rows[#rows + 1] = {
            who = death.who ~= nil and {death.who} or {},
            text = T("history.story.squad.only_deaths", {name = name, deaths = DeathWords(death)}),
        }
    end
    --what the action gave its user: "Baiqadrazaar gained 6 surges."
    if entry.gains ~= nil and entry.actor ~= nil then
        local names = {}
        for name in pairs(entry.gains) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            rows[#rows + 1] = {who = {entry.actor}, text = T("history.story.resource", {name = History.ShownName(entry.actor),
                verb = T("history.story.resource.gained"), resource = History.ResourceWords(entry.gains[name].amount, name)})}
        end
    end
    for _, kid in ipairs(kids) do
        AddKid(rows, kid)
    end

    --an opposed power roll: how the user's total compared with each target's.
    for _, who in ipairs(entry.targets or {}) do
        local opposed = who.opposed
        if opposed ~= nil and entry.actor ~= nil then
            local showTotals = History.OpposedTotalsShown(kids, entry.actor, who)
            local user, target = History.ShownName(entry.actor), History.ShownName(who)
            local text
            if opposed.attacker == opposed.defender then
                text = showTotals and T("history.story.opposed.tie_totals", {user = user, target = target, total = Int(opposed.attacker)})
                    or T("history.story.opposed.tie", {user = user, target = target})
            else
                local outcome = opposed.attacker > opposed.defender and T("history.story.opposed.succeeded") or T("history.story.opposed.failed")
                text = showTotals and T("history.story.opposed.result_totals", {user = user, total = Int(opposed.attacker), target = target, against = Int(opposed.defender), outcome = outcome})
                    or T("history.story.opposed.result", {user = user, outcome = outcome, target = target})
            end
            rows[#rows + 1] = {who = {entry.actor}, text = text}
        end
    end

    if #rows == 0 and entry.actor ~= nil then
        rows[1] = {
            who = {entry.actor},
            text = T("history.story.used", {name = History.ShownName(entry.actor), ability = entry.ability.name}),
        }
    end
    return rows
end

--"Main action - Round 2, turn 13", whichever parts this entry has.
local function MetaWords(entry)
    local parts = {}
    local action = entry.ability ~= nil and History.ACTION_WORDS[entry.ability.action] or nil
    if action ~= nil then
        parts[1] = action
    end
    if entry.round ~= nil and entry.turn ~= nil then
        parts[#parts + 1] = T("history.card.round_turn", {round = Int(entry.round), turn = Int(entry.turn)})
    elseif entry.round ~= nil then
        parts[#parts + 1] = T("history.round", {round = Int(entry.round)})
    end
    return table.concat(parts, History.DOT)
end

--"Rolled by Ana - 8:33 pm". Only an action has someone behind it.
local function FooterWords(entry)
    if entry.kind ~= "action" then
        return nil
    end
    local time = string.lower(dmhub.FormatTimestamp(entry.t, "h:mm tt"))
    if entry.player == nil then
        return T("history.director") .. History.DOT .. time
    end
    if entry.roll ~= nil then
        return T("history.card.rolled_by", {player = entry.player}) .. History.DOT .. time
    end
    return entry.player .. History.DOT .. time
end

--Hover links in the card's text. A name is wrapped in <link=hN>; g_links[N] says
--what its hover shows, so the same thing named twice shares one id.
local g_links = {}
local g_linkIds = {}
--The map whose History the card being built reads, for modifier hover texts. Set by the
--builders below before they name anything.
local g_linkMap = nil
--Which side of a name the big cards (ability, trigger) open on: away from the History
--window, where the card has room. Nil inside the window. Set by History.CreateCard.
--- @type nil|"left"|"right"
local g_cardSide = nil

--- @param text string What the card shows.
--- @param key string Identifies what the hover shows.
--- @param payload table What the hover shows: {kind = "modifier"|"trigger", ...}.
--- @return string
local function HoverLink(text, key, payload)
    local id = g_linkIds[key]
    if id == nil then
        g_links[#g_links + 1] = payload
        id = "h" .. tostring(#g_links)
        g_linkIds[key] = id
    end
    return string.format("<link=%s>%s</link>", id, text)
end

--A modifier's name, hovering to the roll dialog's text recorded at the roll. Entries saved
--before hover texts were recorded have none, so their names stay plain.

--- @param text string
--- @param name string The modifier's name as recorded, spoiler markup kept.
--- @param hover string|nil
--- @return string
local function ModifierLink(text, name, hover)
    if hover == nil or g_linkMap == nil then
        return text
    end
    return HoverLink(text, string.format("m|%s|%s|%s", g_linkMap, hover, name), {kind = "modifier", map = g_linkMap, hover = hover, name = name})
end

--- The rules text of an automatic trigger: its own description, else the description of the
--- feature it comes from, else its modifier's. Nil when the content has none of these.
--- @param creature creature The trigger's owner.
--- @param ability table The triggered ability.
--- @param modifier table|nil The modifier that grants it.
--- @return string|nil
local function AutomaticTriggerText(creature, ability, modifier)
    local function NonBlank(value)
        if type(value) ~= "string" or string.find(value, "%S") == nil then
            return nil
        end
        return trim(value)
    end
    local text = NonBlank(ability:try_get("description"))
    if text == nil and modifier ~= nil then
        local guid = modifier:try_get("sourceguid")
        if guid ~= nil then
            for _, feature in ipairs(creature:GetFeatures() or {}) do
                if feature.guid == guid then
                    text = NonBlank(feature:try_get("description"))
                    break
                end
            end
        end
        text = text or NonBlank(modifier:try_get("description"))
    end
    if text ~= nil then
        --StringInterpolateGoblinScript returns nil only when given nil, so text stays a string.
        text = StringInterpolateGoblinScript(text, creature) --[[@as string]]
    end
    return text
end

--- The card for a creature's trigger as it is now, or nil when it can't be found. A
--- triggered action shows the card its owner's panel shows; an automatic one, its rules text
--- (AutomaticTriggerText), or its ability card when the content has no text for it.
--- @param ownerid string Token id.
--- @param name string
--- @param side nil|"left"|"right" Which side of the name the card opens on.
--- @return nil|fun(): Panel|nil
local function TriggerCard(ownerid, name, side)
    local token = dmhub.GetTokenById(ownerid)
    if token == nil or token.properties == nil then
        return nil
    end
    local display = token.properties:GetTriggeredActionInfo(name)
    if display ~= nil then
        return function()
            return gui.TooltipFrame(display:Render{token = token}, {halign = side or "right", valign = "center"})
        end
    end
    for _, triggered in ipairs(token.properties:GetTriggeredAbilities()) do
        local ability = triggered.ability
        if ability ~= nil and ability.name == name then
            return function()
                local text = AutomaticTriggerText(token.properties, ability, triggered.modifier)
                if text ~= nil then
                    return CreateTooltipPanel{
                        text = string.format("<b>%s</b>\n%s", ability.name, text),
                        maxWidth = 600,
                        halign = side or "right",
                        valign = "center",
                    }
                end
                return CreateAbilityTooltip(ability, {token = token, width = 480, halign = side})
            end
        end
    end
    return nil
end

--- The card of an ability a creature has now, by name, or nil when it can't be found (the
--- creature is gone or no longer has it). Falls back to its triggers.
--- @param ownerid string Token id.
--- @param name string
--- @param side nil|"left"|"right" Which side of the name the card opens on.
--- @return nil|fun(): Panel|nil
local function AbilityCard(ownerid, name, side)
    local token = dmhub.GetTokenById(ownerid)
    if token == nil or token.properties == nil then
        return nil
    end
    for _, ability in ipairs(token.properties:GetActivatedAbilities{bindCaster = true}) do
        if ability.name == name then
            return function()
                return CreateAbilityTooltip(ability, {token = token, width = 480, halign = side})
            end
        end
    end
    --a monster's trigger cards are for the Director only, as in TriggerLink below.
    if not dmhub.isDM and not (token.playerControlled or token.properties:IsHero()) then
        return nil
    end
    return TriggerCard(ownerid, name, side)
end

--A trigger's name, hovering to its card. A monster's card is for the Director only.
--- @param text string
--- @param owner HistoryCreature|nil
--- @param name string The trigger's name.
--- @return string
local function TriggerLink(text, owner, name)
    if owner == nil or (not owner.hero and not dmhub.isDM) or TriggerCard(owner.id, name, g_cardSide) == nil then
        return text
    end
    return HoverLink(text, string.format("t|%s|%s|%s", owner.id, name, g_cardSide or ""), {kind = "trigger", owner = owner.id, name = name, side = g_cardSide})
end

--The hover for one link: the recorded text, with spoilers as the roll dialog shows them,
--or a trigger's card.
--- @param element Panel
--- @param link string
local function ShowLink(element, link)
    local payload = g_links[tonumber(string.sub(link, 2)) or 0]
    if payload == nil then
        return
    end
    if payload.kind == "modifier" then
        local text = History.HoverText(payload.map, payload.hover)
        if text == nil then
            return
        end
        local name = payload.name
        if PowerRollSpoilers.HasSpoiler(name) then
            local revealed = PowerRollSpoilers.IsRevealed(PowerRollSpoilers.Key(name), PowerRollSpoilers.DefaultRevealed(name))
            if dmhub.isDM or revealed then
                text = PowerRollSpoilers.Format(text, revealed)
            else
                --as the dialog: players see only the redacted name, as the summary's own
                --colour tags would show through the bar.
                text = PowerRollSpoilers.Format(name, false)
            end
        end
        gui.Tooltip{text = text, maxWidth = 600}(element)
    else
        local find = payload.kind == "ability" and AbilityCard or TriggerCard
        local card = find(payload.owner, payload.name, payload.side)
        if card ~= nil then
            element.tooltip = card()
        end
    end
end

--How long the pointer rests on a name before its hover opens, so sweeping the pointer
--across the card doesn't flash cards open.
local HOVER_DELAY = 0.4

--- Label arguments with hovers for the links in their text: the hovered name is
--- underlined at once and shows its hover after HOVER_DELAY. Other labels pass through.
--- @param args table Arguments for gui.Label.
--- @return table args
local function Linked(args)
    --while searching, what matched is marked here too.
    args.text = History.SearchMark(args.text)
    local text = args.text
    if type(text) ~= "string" or string.find(text, "<link=", 1, true) == nil then
        return args
    end
    --the link waiting for its delay; nil once the pointer leaves it. Each hover counts, so
    --only the newest hover's delay opens a card: two quick hovers would otherwise open two.
    local pending = nil
    local hovers = 0
    args.links = true
    args.hoverLink = function(element, link)
        element.text = (string.gsub(text, "<link=" .. link .. ">(.-)</link>", "<link=" .. link .. "><u>%1</u></link>", 1))
        pending = link
        hovers = hovers + 1
        element:ScheduleEvent("historyHoverDwell", HOVER_DELAY, hovers)
    end
    args.historyHoverDwell = function(element, count)
        if count == hovers and pending ~= nil and element.linkHovered == pending then
            ShowLink(element, pending)
        end
    end
    args.dehoverLink = function(element, link)
        pending = nil
        element.text = text
        element.tooltip = nil
    end
    return args
end

--- Whether the local user may see the card of an ability this creature used. A hero's,
--- always. A monster's, as the Action Log shows players nothing of it: only with Monster Info
--- on and that ability revealed (using it reveals it). The Director sees every card.
--- @param actor HistoryCreature
--- @param name string
--- @return boolean
local function PlayersMaySeeAbility(actor, name)
    if dmhub.isDM then
        return true
    end
    if actor.secret then
        return false
    end
    if actor.hero then
        return true
    end
    if not MonsterKnowledge.Enabled() then
        return false
    end
    local token = dmhub.GetTokenById(actor.id)
    local key = token ~= nil and MonsterKnowledge.KeyForToken(token) or nil
    if key == nil then
        return false
    end
    --a trait (what made it immune, say) is learned as a feature, an action as an ability.
    return MonsterKnowledge.IsRevealed(key, MonsterKnowledge.EntryKey("ability", name))
        or MonsterKnowledge.IsRevealed(key, MonsterKnowledge.EntryKey("feature", name))
end

local function Header(entry, width, inTray, close)
    local children = {}
    local titleWidth = width - 12 - 8 - 22
    if inTray then
        children[1] = gui.Label{
            classes = {"historyButton"},
            bgimage = "panels/square.png",
            text = BACK_TEXT,
            width = "auto",
            height = 22,
            hpad = 8,
            borderBox = true,
            borderWidth = 1,
            cornerRadius = 4,
            halign = "left",
            valign = "center",
            rmargin = 8,
            textAlignment = "center",
            click = close,
        }
        titleWidth = titleWidth - 66
    end

    local title = T("history.card.title.encounter_ended")
    --a test or Dice panel line: who rolled, and what ("Gordon - Might test", "Gordon - Dice").
    local roller = entry.who
    if entry.family == "test" or entry.family == "dice" or entry.family == "table" then
        local name = roller ~= nil and History.ShownName(roller) or entry.roller or T("history.director")
        local what = entry.family == "test" and entry.name or T("history.card.title.dice")
        if entry.family == "table" then
            --"Gordon - Prayer Table"; a project event the Director rolled, "Director - Seek the Lost Sword event".
            what = entry.project ~= nil and T("history.project_event", {project = entry.project}) or entry.name or T("history.table")
        end
        title = name .. History.DOT .. what
        if roller ~= nil then
            children[#children + 1] = History.Face(roller, 30, true)
            titleWidth = titleWidth - 39
        end
    elseif entry.family == "negotiation" then
        title = (roller ~= nil and History.ShownName(roller) or T("history.a_hero")) .. History.DOT .. T("history.card.title.argument")
        if roller ~= nil then
            children[#children + 1] = History.Face(roller, 30, true)
            titleWidth = titleWidth - 39
        end
    elseif entry.actor ~= nil then
        children[#children + 1] = History.Face(entry.actor, 30, true)
        titleWidth = titleWidth - 39
        --the ability's name is bracketed and hovers to its card, as names do in the Why; only
        --when the card can be found, and not for a creature whose name players may not see.
        local name = entry.ability.name
        local actor = entry.actor
        if PlayersMaySeeAbility(actor, name) and AbilityCard(actor.id, name, g_cardSide) ~= nil then
            name = HoverLink("[" .. name .. "]", string.format("a|%s|%s|%s", actor.id, name, g_cardSide or ""),
                {kind = "ability", owner = actor.id, name = name, side = g_cardSide})
        end
        title = History.ShownName(actor) .. History.DOT .. name
    end
    local meta = gui.Label{
        classes = {"historyCardMeta"},
        text = MetaWords(entry),
        width = "100%",
        height = "auto",
        textAlignment = "left",
    }
    --a villain action or a reverted row carries its tag beside the round and
    --turn, as its row does.
    local villainAction = entry.ability ~= nil and entry.ability.villainaction or nil
    if villainAction ~= nil or entry.reverted ~= nil then
        meta.selfStyle.width = "auto"
        meta.selfStyle.halign = "left"
        local parts = {meta}
        if villainAction ~= nil then
            parts[#parts + 1] = History.Tag("historyVillainTag", T("history.tag.villain_action"))
        end
        if entry.reverted ~= nil then
            parts[#parts + 1] = History.Tag("historyRevertedTag", T("history.tag.reverted"))
        end
        meta = gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            halign = "left",
            children = parts,
        }
    end
    children[#children + 1] = gui.Panel{
        flow = "vertical",
        width = titleWidth,
        height = "auto",
        lmargin = (entry.actor ~= nil or (roller ~= nil and (entry.family == "test" or entry.family == "dice" or entry.family == "table"))) and 9 or 0,
        halign = "left",
        valign = "center",
        gui.Label(Linked{
            classes = {"historyCardTitle"},
            text = title,
            width = "100%",
            height = "auto",
            textAlignment = "left",
        }),
        meta,
    }
    children[#children + 1] = gui.Panel{
        classes = {"historyCardClose"},
        bgimage = "window-chrome/chrome-close.png",
        width = 12,
        height = 12,
        hmargin = 5,
        halign = "right",
        valign = "center",
        linger = gui.Tooltip{text = T("history.card.close_tooltip"), fontSize = 13},
        click = close,
    }

    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        lpad = 12,
        rpad = 8,
        tpad = 10,
        bpad = 9,
        borderBox = true,
        children = children,
    }
end

local function SectionHead(text, textWidth, width)
    return gui.Panel{
        flow = "horizontal",
        width = width,
        height = "auto",
        tmargin = 12,
        bmargin = 6,
        gui.Label{
            classes = {"historySmallCaps"},
            text = text,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        },
        gui.Panel{
            classes = {"historySeam"},
            bgimage = "panels/square.png",
            width = width - textWidth - 8,
            height = 1,
            lmargin = 8,
            halign = "left",
            valign = "center",
        },
    }
end

--The side view: a button on a movement row. Hovering it draws the recorded move on
--the map (the arrow, and a faded ghost on the square it started from) and shows the move
--side-on, as the drag tooltip does. Older engine builds have no dmhub.CreatePath, and
--then there is no button.

local SIDE_VIEW_ICON = "phosphor/arrow-elbow-right-down-bold.png"
--The side view is drawn at most this wide, as the drag tooltip's.
local SIDE_VIEW_MAX_WIDTH = 340
--pcall's first result only says the read did not raise; the second is the answer.
local g_pathsRead, g_pathsFound = pcall(function() return dmhub.CreatePath ~= nil end)
local g_canDrawPaths = g_pathsRead and g_pathsFound == true

--- The squares a creature was moved through, start first, as dmhub.CreatePath takes them,
--- or nil. History saves them as plain {x, y, floor, altitude} lists.
--- @param moved table|nil
--- @return nil|{x: integer, y: integer, floor: integer, altitude: integer, fall: boolean|nil}[] steps
--- @return boolean fell The move ended in a fall.
local function MovedSteps(moved)
    local path = moved ~= nil and moved.path or nil
    if type(path) ~= "table" or #path < 2 then
        return nil, false
    end
    local steps = {}
    for i, step in ipairs(path) do
        steps[i] = {x = step[1], y = step[2], floor = step[3], altitude = step[4]}
    end
    --A fall is saved with its landing as a last step straight down. Dropping it ends the path in
    --the air, as the targeting preview's does, so the side view draws the push and then the drop
    --instead of one diagonal line to the landing.
    local last, previous = steps[#steps], steps[#steps - 1]
    if #steps > 2 and last.x == previous.x and last.y == previous.y and last.floor == previous.floor
        and (previous.altitude or 0) - (last.altitude or 0) > 1 then
        steps[#steps] = nil
        return steps, true
    end
    --A fall to a lower floor keeps its landing, with those steps marked as a fall, so the side
    --view draws the drop through the floors.
    local fell = false
    for i = #steps, 2, -1 do
        local step, above = steps[i], steps[i - 1]
        if step.floor == steps[1].floor or step.x ~= above.x or step.y ~= above.y then
            break
        end
        step.fall = true
        fell = true
    end
    return steps, fell
end

--- A creature whose recorded move the side view can draw.
--- @class HistoryMover
--- @field id string The creature's charid.
--- @field token CharacterToken Draws the arrow: the creature's token, or its corpse once it has died.
--- @field dead CharacterToken|nil The dead creature, when token is its corpse.
--- @field steps table[] The squares it was moved through, start first (see MovedSteps).
--- @field fell boolean The move ended in a fall.
--- @field moved table The move as History saved it.

--- A creature as it is on the map now: its own token, or its corpse once it has died (the
--- corpse keeps the creature, so it can be raised). nil when neither is on the map or this
--- user can't see it: drawing it would give a hidden one away.
--- @param charid string
--- @return CharacterToken|nil token
--- @return CharacterToken|nil dead The dead creature, when token is its corpse.
local function LiveToken(charid)
    local token = dmhub.GetTokenById(charid)
    local dead = nil
    if token == nil or not token.valid then
        dead = dmhub.GetCharacterById(charid)
        token = dead ~= nil and dead:FindCorpse() or nil --[[@as CharacterToken|nil]]
    end
    if token == nil or not token.valid or not token.canSee then
        return nil, nil
    end
    return token, dead
end

--- A moved creature as it is on the map now (see LiveToken), or nil.
--- @param charid string
--- @param steps table[]
--- @param fell boolean
--- @param moved table
--- @return HistoryMover|nil
local function LiveMover(charid, steps, fell, moved)
    local token, dead = LiveToken(charid)
    if token == nil then
        return nil
    end
    return {id = charid, token = token, dead = dead, steps = steps, fell = fell, moved = moved}
end

--- The squares the side view draws other creatures on, as "x,y,floor" keys: those the mover
--- covered at each step, and one square past either end along the path (the engine's
--- MovementCrossSection does the same). A fall's steps below the start floor are left out.
--- @param steps table[] From MovedSteps.
--- @param size integer The mover's size in squares.
--- @return table<string, boolean>
local function SideViewSquares(steps, size)
    local squares = {}
    local function Cover(x, y, floor)
        for dx = 0, size - 1 do
            for dy = 0, size - 1 do
                squares[string.format("%d,%d,%d", x + dx, y + dy, floor)] = true
            end
        end
    end
    local last = #steps
    while last > 1 and steps[last].fall do
        last = last - 1
    end
    for i = 1, last do
        Cover(steps[i].x, steps[i].y, steps[i].floor)
    end
    if last >= 2 then
        local first, second = steps[1], steps[2]
        Cover(2 * first.x - second.x, 2 * first.y - second.y, first.floor)
        local final, before = steps[last], steps[last - 1]
        Cover(2 * final.x - before.x, 2 * final.y - before.y, final.floor)
    end
    return squares
end

--- How many squares wide a creature is. tileSize reads 1 for a dead creature (it has no token),
--- so this reads the size itself: "1M" is 1 square, "2" is 2.
--- @param token CharacterToken
--- @return integer
local function SquaresWide(token)
    return math.max(1, tonumber(string.match(token.creatureSize or "", "^%d+")) or 1)
end

--- The creatures the side view draws for a recorded move, at the squares they stood on then.
--- One that has moved or died since also gets a ghost on the map there, so the map
--- matches the side view (a dead one needs it to be drawn at all); ghosts go in shown, to be
--- destroyed. nil for moves saved before History kept the creatures around them.
--- @param mover HistoryMover
--- @param shown LuaMultiObjectReference[]
--- @return nil|{token: CharacterToken, x: integer, y: integer, floor: integer, altitude: integer}[]
local function OthersThen(mover, shown)
    local moved = mover.moved
    if moved.near == nil then
        return nil
    end
    local squares = SideViewSquares(mover.steps, SquaresWide(mover.dead or mover.token))
    local forPlayers = not dmhub.isDM
    local others = {}
    for _, near in ipairs(moved.near) do
        local charid, x, y, floor, altitude, unseen = near[1], near[2], near[3], near[4], near[5], near[6]
        local token, dead = nil, nil
        if not (forPlayers and unseen) then
            token, dead = LiveToken(charid)
        end
        local drawn = false
        if token ~= nil then
            local size = SquaresWide(dead or token)
            for dx = 0, size - 1 do
                for dy = 0, size - 1 do
                    drawn = drawn or squares[string.format("%d,%d,%d", x + dx, y + dy, floor)] == true
                end
            end
        end
        if drawn and token ~= nil then
            local loc = token.loc
            local movedSince = dead ~= nil or loc.x ~= x or loc.y ~= y or loc.floor ~= floor or loc.altitude ~= altitude
            if movedSince then
                local ghost = (dead or token):CreateGhost(core.Loc{x = x, y = y, floorIndex = floor}:WithAltitude(altitude))
                if ghost ~= nil then
                    shown[#shown + 1] = ghost
                end
            end
            others[#others + 1] = {token = dead or token, x = x, y = y, floor = floor, altitude = altitude}
        end
    end
    return others
end

--- The creatures in a row whose move can be drawn, with their tokens. Only on the map shown.
--- @param row HistoryStoryRow
--- @param mapid string|nil
--- @return HistoryMover[]
local function RowMovers(row, mapid)
    local movers = {}
    if not g_canDrawPaths or mapid == nil or mapid ~= game.currentMapId then
        return movers
    end
    for _, who in ipairs(row.who or {}) do
        local steps, fell = MovedSteps(who.moved)
        local mover = steps ~= nil and LiveMover(who.id, steps, fell, who.moved) or nil
        if mover ~= nil then
            movers[#movers + 1] = mover
        end
    end
    return movers
end

--- Draws each mover's recorded move on the map. Returns the markers and ghosts to destroy,
--- and the first mover's path for the side view.
--- @param movers HistoryMover[]
--- @return LuaMultiObjectReference[] shown
--- @return LuaPath|nil firstPath
local function ShowMoves(movers)
    local shown = {}
    local firstPath = nil
    for i, mover in ipairs(movers) do
        local path = dmhub.CreatePath(mover.steps, {forced = true})
        if path ~= nil then
            --nil targetLoc: options.path is drawn as given, with no pathfinding.
            ---@diagnostic disable-next-line: param-type-mismatch
            local arrow = mover.token:MarkMovementArrow(nil, {path = path, separate = true})
            if arrow ~= nil and arrow.marker ~= nil then
                shown[#shown + 1] = arrow.marker
            end
            --the path's own first step keeps the altitude it started at (a ledge, a flight).
            --a dead creature's ghost is drawn from the creature itself; on engines without
            --that, from its corpse (whose picture is blank, so no ghost shows).
            local ghost = mover.dead ~= nil and mover.dead:CreateGhost(path.steps[1]) or nil
            if ghost == nil then
                ghost = mover.token:CreateGhost(path.steps[1])
            end
            if ghost ~= nil then
                shown[#shown + 1] = ghost
            end
            if i == 1 then
                firstPath = path
            end
        end
    end
    return shown, firstPath
end

--- The side-view button for a row about creatures that were moved, or nil.
--- @param row HistoryStoryRow
--- @param mapid string|nil
--- @return Panel|nil
local function SideViewButton(row, mapid)
    local movers = RowMovers(row, mapid)
    if #movers == 0 then
        return nil
    end
    local side = g_cardSide or "right"
    --what the hover put on the map, destroyed when it ends.
    --- @type LuaMultiObjectReference[]
    local shown = {}
    local sectioned = false
    local function Clear()
        for _, item in ipairs(shown) do
            item:Destroy()
        end
        if #shown > 0 or sectioned then
            dmhub.ClearMovementCrossSection()
        end
        shown = {}
        sectioned = false
    end
    return gui.Panel{
        classes = {"historySideView"},
        bgimage = SIDE_VIEW_ICON,
        width = 14,
        height = 14,
        lmargin = 6,
        tmargin = 4,
        valign = "top",
        hover = function(element)
            Clear()
            --the card outlives its tokens: one may have died, been raised or gone, or the
            --map changed, since it was built. Look each up again.
            local live = {}
            if mapid == game.currentMapId then
                for _, mover in ipairs(movers) do
                    local now = LiveMover(mover.id, mover.steps, mover.fell, mover.moved)
                    if now ~= nil then
                        live[#live + 1] = now
                    end
                end
            end
            if #live == 0 then
                return
            end
            local path
            shown, path = ShowMoves(live)
            local mover = live[1]
            --the damage the collision dealt it. Moves saved before History kept that show the
            --squares left, plus 2 for an object (a wall counts).
            local collision = mover.moved.collisiondamage
            if collision == nil then
                collision = mover.moved.collision or 0
                if collision > 0 and (mover.moved.collidedobject or mover.moved.collidedwith == nil) then
                    collision = collision + 2
                end
            end
            --the damage the fall did, as the live preview's badge shows it.
            local fall = mover.moved.falldamage or 0
            local others = OthersThen(mover, shown)
            local function Section(token)
                return dmhub.SetMovementCrossSection{
                    token = token,
                    path = path,
                    collisionDamage = collision > 0 and collision or nil,
                    fallDamage = fall > 0 and fall or nil,
                    others = others,
                    --whether it could fly then, judged by whether it fell: a creature that has
                    --since gained flight is still drawn falling.
                    canFly = not mover.fell,
                }
            end
            local view = nil
            if path ~= nil then
                --a dead creature draws as itself where the engine can (from its ghost above),
                --else as its corpse.
                view = mover.dead ~= nil and Section(mover.dead) or nil
                if view == nil then
                    view = Section(mover.token)
                end
            end
            sectioned = view ~= nil
            --framed as the drag tooltip frames it; the bare name only when the
            --engine can't draw this move side-on (it crosses floors).
            local contents
            if view ~= nil then
                local scale = math.min(1, SIDE_VIEW_MAX_WIDTH / view.width)
                contents = gui.Panel{
                    bgimage = view.image,
                    bgcolor = "white",
                    width = view.width * scale,
                    height = view.height * scale,
                }
            else
                contents = gui.Label{
                    text = T("history.card.side_view"),
                    fontSize = 14,
                    width = "auto",
                    height = "auto",
                }
            end
            element.tooltip = gui.TooltipFrame(contents, {interactable = false, halign = side, valign = "center"})
        end,
        dehover = function(element)
            Clear()
            element.tooltip = nil
        end,
        destroy = function(element)
            Clear()
        end,
    }
end

--- @param row HistoryStoryRow
--- @param width number
--- @param mapid? string The entry's map, for the side-view button (only the full card has it).
local function StoryRow(row, width, mapid)
    local textWidth = width
    local sideView = SideViewButton(row, mapid)
    if sideView ~= nil then
        textWidth = textWidth - 20
    end
    if row.amount ~= nil then
        textWidth = textWidth - STORY_NUMBER_WIDTH
    end

    local left = {}
    if row.who[1] ~= nil then
        local face = History.Face(row.who[1], STORY_FACE, mapid ~= nil)
        face.selfStyle.valign = "top"
        left[1] = face
        textWidth = textWidth - STORY_FACE - STORY_GAP
    end
    --what is still on gets Active, always, so "slowed" answers why you are slowed now.
    --a grouped row is Active while any of its creatures still has it.
    local active = nil
    if not row.ended then
        for _, who in ipairs(row.who) do
            active = active or History.ActiveStart(who)
        end
    end
    local tagged = row.ended or active ~= nil
    left[#left + 1] = gui.Label{
        classes = {"historyStory"},
        text = History.SearchMark(History.StoryText(row)),
        width = tagged and "auto" or textWidth,
        maxWidth = tagged and (textWidth - ENDED_TAG_WIDTH) or nil,
        height = "auto",
        lmargin = #left > 0 and STORY_GAP or 0,
        halign = "left",
        valign = "top",
        textAlignment = "left",
    }
    if row.ended then
        left[#left + 1] = History.Tag("historyEndedTag", T("history.tag.ended"))
    elseif active ~= nil then
        local tag = History.ActiveTag(active.icon)
        tag.selfStyle.valign = "top"
        tag.selfStyle.tmargin = 3
        left[#left + 1] = tag
    end
    left[#left + 1] = sideView

    local children = {
        gui.Panel{
            flow = "horizontal",
            width = width - (row.amount ~= nil and STORY_NUMBER_WIDTH or 0),
            height = "auto",
            halign = "left",
            valign = "top",
            children = left,
        },
    }
    if row.amount ~= nil then
        local number = History.Amount(math.abs(row.amount), row.amount > 0, 17)
        number.selfStyle.halign = "right"
        number.selfStyle.valign = "top"
        number.selfStyle.rmargin = 0
        children[2] = number
    end
    return gui.Panel{
        flow = "none",
        width = width,
        height = "auto",
        vpad = 3,
        borderBox = true,
        children = children,
    }
end

--The numbers: a receipt. One fact per line, every number in one column on the right,
--each total under a line, in the order things resolved: the roll, then each target, then
--triggers and costs.

--A signed number. A plain "-": the bold font has no minus sign.
local function Signed(value)
    if value < 0 then
        return string.format("-%d", -value)
    end
    return string.format("+%d", value)
end

--Edges and banes as the rules net them: up to two of each count, then they cancel one for
--one, as the Heroes book says. Nil when there are none.
--- @return {label: string, value: string, side: string|nil, count: integer, note: string|nil, aside: string|nil}|nil
local function NetEdges(edges, banes)
    --also History.NetEdges below, so the row's glance chip nets them the same way.
    edges, banes = edges or 0, banes or 0
    if edges == 0 and banes == 0 then
        return nil
    end
    local countedEdges, countedBanes = math.min(edges, 2), math.min(banes, 2)
    local net
    if countedBanes == 0 then
        net = countedEdges == 1 and {label = T("history.numbers.edge"), value = "+2", side = "edge", count = 1}
            or {label = T("history.numbers.double_edge"), value = T("history.numbers.plus_tier"), side = "edge", count = 2}
    elseif countedEdges == 0 then
        net = countedBanes == 1 and {label = T("history.numbers.bane"), value = "-2", side = "bane", count = 1}
            or {label = T("history.numbers.double_bane"), value = T("history.numbers.minus_tier"), side = "bane", count = 2}
    elseif countedEdges > countedBanes then
        net = {label = T("history.numbers.edge"), value = "+2", side = "edge", count = 1}
    elseif countedEdges < countedBanes then
        net = {label = T("history.numbers.bane"), value = "-2", side = "bane", count = 1}
    else
        net = {label = T("history.numbers.cancelled_out"), value = "0", count = 0}
    end

    if countedEdges == 2 and countedBanes == 1 then
        net.note = T("history.numbers.note.two_edges_one_bane")
    elseif countedBanes == 2 and countedEdges == 1 then
        net.note = T("history.numbers.note.two_banes_one_edge")
    elseif countedEdges > 0 and countedEdges == countedBanes then

        net.note = T("history.numbers.note.cancel_out")
    elseif edges > 2 then
        net.note = T("history.numbers.note.max_edges")
    elseif banes > 2 then
        net.note = T("history.numbers.note.max_banes")
    end

    if edges + banes > 1 then
        local parts = {}
        if edges > 0 then
            parts[#parts + 1] = UIText.Plural("history.numbers.edges", edges, {count = Int(edges)})
        end
        if banes > 0 then
            parts[#parts + 1] = UIText.Plural("history.numbers.banes", banes, {count = Int(banes)})
        end
        net.aside = "(" .. table.concat(parts, ", ") .. ")"
    end
    return net
end
History.NetEdges = NetEdges

--The roll dialog's arrows: the image points down (a bane) and is flipped for an edge; a
--double stacks two.
local function Chevrons(side, count)
    local arrows = {}
    for i = 1, count do
        arrows[i] = gui.Panel{
            classes = {cond(side == "edge", "historyEdgeIcon", "historyBaneIcon")},
            bgimage = "drawsteel/Icons_Nav_CollapseArrow.png",
            width = 14,
            height = 14,
            scale = side == "edge" and {x = 1, y = -1} or nil,
            y = count == 2 and cond(i == 1, 2, -2) or 0,
            interactable = false,
        }
    end
    return gui.Panel{
        flow = "none",
        width = 14,
        height = 14,
        rmargin = 5,
        halign = "left",
        valign = "center",
        children = arrows,
    }
end
History.Chevrons = Chevrons

local function Die(face)
    return gui.Label{
        classes = {"historyDie"},
        bgimage = "panels/square.png",
        text = tostring(face),
        width = 24,
        height = 20,
        rmargin = 4,
        borderWidth = 1,
        cornerRadius = 4,
        borderBox = true,
        halign = "left",
        valign = "center",
        textAlignment = "center",
    }
end

--One line of the receipt. lead is panels before the label (dice, arrows, a face); a total
--sits under a line; struck crosses out the label and value of something that did not count.
--- @param args {label: string|nil, lead: Panel[]|nil, aside: string|nil, eye: Panel|nil, badge: integer|nil, value: string|nil, valueClass: string|nil, labelClass: string|nil, total: boolean|nil, struck: boolean|nil}
local function ReceiptLine(width, args)
    local left = {}
    for _, panel in ipairs(args.lead or {}) do
        left[#left + 1] = panel
    end
    if args.label ~= nil then
        local classes = {"historyReceipt"}
        classes[#classes + 1] = args.labelClass
        classes[#classes + 1] = args.struck and "historyStruck" or nil
        left[#left + 1] = gui.Label(Linked{
            classes = classes,
            text = args.label,
            width = "auto",
            maxWidth = width - VALUE_WIDTH - 8,
            height = "auto",
            halign = "left",
            valign = "center",
        })
    end
    left[#left + 1] = args.eye
    if args.aside ~= nil then
        left[#left + 1] = gui.Label{
            classes = {"historyReceiptAside"},
            text = args.aside,
            width = "auto",
            height = "auto",
            lmargin = 5,
            halign = "left",
            valign = "center",
        }
    end
    if args.badge ~= nil and args.badge > 0 then
        left[#left + 1] = History.TierBadge(args.badge)
    end

    local children = {
        gui.Panel{
            flow = "horizontal",
            wrap = true,
            width = width - VALUE_WIDTH - 8,
            height = "auto",
            halign = "left",
            valign = "center",
            children = left,
        },
    }
    if args.value ~= nil then
        local classes = {"historyReceiptValue"}
        classes[#classes + 1] = args.valueClass
        classes[#classes + 1] = args.struck and "historyStruck" or nil
        children[2] = gui.Label{
            classes = classes,
            text = args.value,
            width = VALUE_WIDTH,
            height = "auto",
            halign = "right",
            valign = "center",
            textAlignment = "right",
        }
    end
    local row = gui.Panel{
        flow = "none",
        width = width,
        height = "auto",
        vpad = 2,
        borderBox = true,
        children = children,
    }
    if not args.total then
        return row
    end
    return gui.Panel{
        flow = "vertical",
        width = width,
        height = "auto",
        tmargin = 3,
        gui.Panel{
            classes = {"historyReceiptRule"},
            bgimage = "panels/square.png",
            width = width,
            height = 1,
            bmargin = 2,
        },
        row,
    }
end

--A rule note sits indented under its line; a cost (historyReceiptMore) starts at the edge.
local function ReceiptNote(width, text, class)
    local indent = class == nil and 16 or 0
    return gui.Label{
        classes = {class or "historyReceiptNote"},
        text = text,
        width = width - indent,
        height = "auto",
        lmargin = indent,
        tmargin = class == nil and 0 or 4,
        bmargin = 3,
        halign = "left",
        textAlignment = "left",
    }
end

--A heading inside the numbers: Power roll, a target (with its face) or Triggered.
local function SubHead(text, width, who)
    local children = {}
    if who ~= nil then
        local face = History.Face(who, 20, true)
        face.selfStyle.rmargin = 6
        face.selfStyle.halign = "left"
        children[1] = face
    end
    children[#children + 1] = gui.Label{
        classes = {"historySmallCaps"},
        text = text,
        width = "auto",
        maxWidth = width - 40,
        height = "auto",
        halign = "left",
        valign = "center",
    }
    return gui.Panel{
        flow = "horizontal",
        width = width,
        height = "auto",
        tmargin = 8,
        bmargin = 3,
        children = children,
    }
end

--A source's name as the roll dialog shows it: a spoilered name stays a redaction bar for
--players until the Director reveals it there.
local function SpoilerName(name)
    if not PowerRollSpoilers.HasSpoiler(name) then
        return name
    end
    return PowerRollSpoilers.Format(name, PowerRollSpoilers.IsRevealed(PowerRollSpoilers.Key(name), PowerRollSpoilers.DefaultRevealed(name)))
end

local SOURCE_INDENT = 16

--What a tier modifier did, for its value in The numbers; nil for a source that only
--gave or took edges and banes.
--- @param source HistoryEdgeSource
--- @return string|nil
local function TierValue(source)
    if source.autosuccess then
        return T("history.tier", {tier = 3})
    elseif source.autofailure then
        return T("history.tier", {tier = 1})
    elseif (source.tiers or 0) ~= 0 then
        --"or 0" only tells the type checker tiers is set: the test above already proved it.
        local count = math.abs(source.tiers or 0)
        return UIText.Plural("history.numbers.tiers", count, {sign = source.tiers > 0 and "+" or "-", count = Int(count)})
    elseif source.nottierthree then
        return T("history.numbers.not_tier", {tier = 3})
    elseif source.nottierone then
        return T("history.numbers.not_tier", {tier = 1})
    end
    return nil
end

--A rule's or ability's name inside the Why, in square brackets so a name like "Target is
--Restrained" reads as one thing in the sentence around it, and, as in many games, as
--something that can be hovered.
--- @param name string
--- @return string
local function WhyName(name)
    return "[" .. name .. "]"
end

--A source as the roll dialog named it: "Prone", "Reactor 1's Test 5", "Set by hand".
--- @param source HistoryEdgeSource
--- @param why? boolean For a Why sentence: the name in brackets, its owner plain.
--- @return string
local function SourceText(source, why)
    if source.hand then
        return T("history.set_by_hand")
    end
    local sourceName = source.name or ""
    local text = SpoilerName(sourceName)
    if why then
        text = WhyName(text)
    end
    text = ModifierLink(text, sourceName, source.hover)
    if source.who ~= nil then
        text = T("history.possessive", {owner = History.ShownName(source.who), name = text})
    end
    return text
end

--"Ignored by Twisted": what took a side's edges or banes away. Several removers
--share one reason.
--- @param sources HistoryEdgeSource[]
--- @param side "edge"|"bane"
--- @return string|nil
local function RemovedReason(sources, side)
    local field = side == "edge" and "removedEdges" or "removedBanes"
    local parts = {}
    for _, source in ipairs(sources) do
        if (source[field] or 0) > 0 then
            parts[#parts + 1] = source.ignore and T("history.numbers.ignored_by", {source = SourceText(source)})
                or T("history.numbers.removed_by", {source = SourceText(source)})
        end
    end
    if #parts == 0 then
        return nil
    end
    local reason = table.concat(parts, ", ")
    return string.upper(string.sub(reason, 1, 1)) .. string.sub(reason, 2)
end

--The Director's mark on a modifier players see only as a redaction bar: an eye with
--"Hidden from players". Nil for everyone else, and once the Director has revealed it.
--- @param name string The modifier's name as recorded, spoiler markup kept.
--- @return Panel|nil
local function SpoilerEye(name)
    if not dmhub.isDM or not PowerRollSpoilers.HasSpoiler(name) then
        return nil
    end
    if PowerRollSpoilers.IsRevealed(PowerRollSpoilers.Key(name), PowerRollSpoilers.DefaultRevealed(name)) then
        return nil
    end
    return gui.VisibilityPanel{
        visible = false,
        width = 14,
        height = 14,
        lmargin = 5,
        halign = "left",
        valign = "center",
        linger = gui.Tooltip(T("history.hidden_from_players")),
    }
end

--One thing that changed the roll's edges or banes, under the line it changed: its
--arrows, its owner's face, and its name as the roll dialog showed it.
--- @param source HistoryEdgeSource
--- @param side "edge"|"bane"
--- @param struck? boolean Everything it gave was taken away: crossed out, the reason is on the line above.
--- @param remover? boolean The line for a source that took one of several away ("Removed by").
local function SourceLine(width, source, side, struck, remover)
    local children = {}
    if remover then
        --no arrows, so the words line up with the names above.
        children[1] = gui.Panel{width = 14, height = 14, rmargin = 5, halign = "left", valign = "center", interactable = false}
    else
        children[1] = Chevrons(side, math.min((side == "edge" and source.edges or source.banes) or 0, 2))
    end
    if source.who ~= nil and not source.hand then
        local face = History.Face(source.who, 20, true)
        face.selfStyle.rmargin = 6
        face.selfStyle.halign = "left"
        children[#children + 1] = face
    end
    local text = SourceText(source)
    if remover then
        text = source.ignore and T("history.numbers.ignored_by_line", {source = text}) or T("history.numbers.removed_by_line", {source = text})
    end
    children[#children + 1] = gui.Label(Linked{
        classes = {remover and "historyReceiptAside" or "historyReceiptSource", struck and "historyStruck" or nil},
        text = text,
        width = "auto",
        maxWidth = width - SOURCE_INDENT - 48,
        height = "auto",
        halign = "left",
        valign = "center",
    })
    children[#children + 1] = SpoilerEye(source.name or "")
    return gui.Panel{
        flow = "horizontal",
        width = width - SOURCE_INDENT,
        height = "auto",
        lmargin = SOURCE_INDENT,
        vpad = 1,
        borderBox = true,
        halign = "left",
        children = children,
    }
end

--What gave one side its edges or banes (set by hand last). When the side lost them all,
--each is crossed out and the side's line gives the reason; when it lost only some, nobody
--knows which, so the remover gets its own line instead.
--- @param sources HistoryEdgeSource[]
--- @param side "edge"|"bane"
--- @param struck? boolean The side lost everything.
local function AddSideSources(rows, width, sources, side, struck)
    local field = side == "edge" and "edges" or "banes"
    for pass = 1, 2 do
        for _, source in ipairs(sources) do
            if (source[field] or 0) > 0 and (source.hand == true) == (pass == 2) then
                rows[#rows + 1] = SourceLine(width, source, side, struck)
            end
        end
    end
    if struck then
        return
    end
    local removedField = side == "edge" and "removedEdges" or "removedBanes"
    for _, source in ipairs(sources) do
        if (source[removedField] or 0) > 0 then
            rows[#rows + 1] = SourceLine(width, source, side, nil, true)
        end
    end
end

--A side that lost every edge or bane keeps its line, crossed out with what it would
--have been worth and the reason beside it, so the player sees the edge they lost.
--- @param side "edge"|"bane"
--- @param removed integer How many edges or banes were taken away.
--- @param sources HistoryEdgeSource[]
local function AddStruckLine(rows, width, side, removed, forTarget, sources)
    local lost = NetEdges(side == "edge" and removed or 0, side == "bane" and removed or 0)
    if lost == nil then
        return
    end
    local label = lost.label
    if forTarget then
        label = T("history.numbers.for_this_target", {label = label})
    end
    rows[#rows + 1] = ReceiptLine(width, {
        lead = {Chevrons(side, lost.count)},
        label = label,
        labelClass = side == "edge" and "historyEdgeText" or "historyBaneText",
        aside = RemovedReason(sources, side),
        value = lost.value,
        struck = true,
    })
    AddSideSources(rows, width, sources, side, true)
end

--Each tier modifier and flat bonus, after the edges and banes, a trigger's with its
--owner's face.
--- @param sources HistoryEdgeSource[]
local function AddTierSourceLines(rows, width, sources)
    for _, source in ipairs(sources) do
        local values = {}
        values[#values + 1] = TierValue(source)
        if (source.bonus or 0) ~= 0 then
            values[#values + 1] = Signed(source.bonus)
        end
        for _, value in ipairs(values) do
            local lead = nil
            if source.who ~= nil and not source.hand then
                local face = History.Face(source.who, 20, true)
                face.selfStyle.rmargin = 6
                face.selfStyle.halign = "left"
                lead = {face}
            end
            rows[#rows + 1] = ReceiptLine(width, {lead = lead, label = SourceText(source), eye = SpoilerEye(source.name or ""), value = value})
        end
    end
end

--The net edge or bane line, what gave it each edge and bane (edges first), then the rule
--note. A side that was ignored entirely gets its own line, edges before the net line and
--banes after it.
--- @param sources HistoryEdgeSource[]|nil
--- @param flat? boolean The roll has no tiers (an opposed power roll): a double edge or bane is +4 or -4.
local function AddEdgeLines(rows, width, edges, banes, forTarget, sources, flat)
    edges, banes = edges or 0, banes or 0
    sources = sources or {}
    local removedEdges, removedBanes = 0, 0
    for _, source in ipairs(sources) do
        removedEdges = removedEdges + (source.removedEdges or 0)
        removedBanes = removedBanes + (source.removedBanes or 0)
    end
    if edges == 0 and removedEdges > 0 then
        AddStruckLine(rows, width, "edge", removedEdges, forTarget, sources)
    end
    local net = NetEdges(edges, banes)
    if flat and net ~= nil and net.count == 2 then
        net.value = net.side == "edge" and "+4" or "-4"
    end
    if net ~= nil then
        local label = net.label
        if forTarget and net.side ~= nil then
            label = T("history.numbers.for_this_target", {label = label})
        end
        rows[#rows + 1] = ReceiptLine(width, {
            lead = net.side ~= nil and {Chevrons(net.side, net.count)} or nil,
            label = label,
            labelClass = net.side == "edge" and "historyEdgeText" or net.side == "bane" and "historyBaneText" or nil,
            aside = net.aside,
            value = net.value,
        })
        if edges > 0 then
            AddSideSources(rows, width, sources, "edge")
        end
        if banes > 0 then
            AddSideSources(rows, width, sources, "bane")
        end
    end
    if banes == 0 and removedBanes > 0 then
        AddStruckLine(rows, width, "bane", removedBanes, forTarget, sources)
    end
    if net ~= nil and net.note ~= nil then
        rows[#rows + 1] = ReceiptNote(width, net.note)
    end

    AddTierSourceLines(rows, width, sources)
end

--"Damage immunity 2", "Fire immunity 3", "Fire weakness 3".
local function ResistWords(immunity)
    local typeWord = immunity.damagetype == "damage" and T("history.numbers.damage_word")
        or (string.upper(string.sub(immunity.damagetype, 1, 1)) .. string.sub(immunity.damagetype, 2))
    if immunity.amount > 0 then
        return T("history.numbers.immunity", {type = typeWord, amount = Int(immunity.amount)})
    end
    return T("history.numbers.weakness", {type = typeWord, amount = Int(-immunity.amount)})
end

--One thing besides the tier that made a target's damage: a kit, a roll dialog modifier
--named as its badge (a trigger's with its owner's face) or surges (shown with the roll
--dialog's surge bolt).
--- @param part HistoryDamagePart
local function DamagePartLine(width, part)
    if part.kind == "kit" then
        return ReceiptLine(width, {label = T("history.numbers.kit", {name = part.name or ""}), value = Signed(part.amount)})
    end
    if part.kind == "surge" then
        local count = part.count or 0
        local aside = nil
        if part.characteristic ~= nil then
            local values = {characteristic = part.characteristic, amount = Int(part.each or 0)}
            aside = count == 1 and T("history.numbers.surge_characteristic", values) or T("history.numbers.surge_characteristic_each", values)
        end
        return ReceiptLine(width, {
            lead = {gui.Panel{
                classes = {"historySurgeIcon"},
                bgimage = "game-icons/surge.png",
                width = 14,
                height = 14,
                rmargin = 5,
                halign = "left",
                valign = "center",
                interactable = false,
            }},
            label = UIText.Plural("history.numbers.spent_surges", count, {count = Int(count)}),
            aside = aside,
            value = Signed(part.amount),
        })
    end
    local lead = nil
    local text = ModifierLink(SpoilerName(part.name or ""), part.name or "", part.hover)
    if part.who ~= nil then
        local face = History.Face(part.who, 20, true)
        face.selfStyle.rmargin = 6
        face.selfStyle.halign = "left"
        lead = {face}
        text = T("history.possessive", {owner = History.ShownName(part.who), name = text})
    end
    return ReceiptLine(width, {lead = lead, label = text, eye = SpoilerEye(part.name or ""), value = Signed(part.amount)})
end

--- Splits each target's roll sources into what applied to every target and its own. A
--- target without a list of its own had the roll's (entries saved before targets kept one).
--- @param roll {sources: HistoryEdgeSource[]|nil}
--- @param targets HistoryCreature[] The targets to compare.
--- @return table<HistoryCreature, HistoryEdgeSource[]> shared
--- @return table<HistoryCreature, HistoryEdgeSource[]> own
local function SplitSources(roll, targets)
    local function Sources(who)
        return (who.roll ~= nil and who.roll.sources) or who.sources or roll.sources or {}
    end
    --each source as many times as the target with fewest has it.
    --- @type table<string, integer>|nil
    local common = nil
    for _, who in ipairs(targets) do
        local counts = {}
        for _, source in ipairs(Sources(who)) do
            local key = History.SourceKey(source)
            counts[key] = (counts[key] or 0) + 1
        end
        if common == nil then
            common = counts
        else
            for key, count in pairs(common) do
                common[key] = math.min(count, counts[key] or 0)
            end
        end
    end
    local shared, own = {}, {}
    for _, who in ipairs(targets) do
        local left = {}
        for key, count in pairs(common or {}) do
            left[key] = count
        end
        shared[who], own[who] = {}, {}
        for _, source in ipairs(Sources(who)) do
            local key = History.SourceKey(source)
            if (left[key] or 0) > 0 then
                left[key] = left[key] - 1
                table.insert(shared[who], source)
            else
                table.insert(own[who], source)
            end
        end
    end
    return shared, own
end

--What gave this target, alone, edges or banes the roll's line doesn't name: a line per side
--that it changed, with no number (the roll's line has the count), and its sources under it.
--- @param sources HistoryEdgeSource[]
local function AddOwnSources(rows, width, sources)
    for _, side in ipairs({"edge", "bane"}) do
        local field = side == "edge" and "edges" or "banes"
        local removedField = side == "edge" and "removedEdges" or "removedBanes"
        local any = false
        for _, source in ipairs(sources) do
            any = any or (source[field] or 0) > 0 or (source[removedField] or 0) > 0
        end
        if any then
            rows[#rows + 1] = ReceiptLine(width, {
                lead = {Chevrons(side, 1)},
                label = T("history.numbers.for_this_target", {label = side == "edge" and T("history.numbers.edge") or T("history.numbers.bane")}),
                labelClass = side == "edge" and "historyEdgeText" or "historyBaneText",
                value = "",
            })
            AddSideSources(rows, width, sources, side)
        end
    end
    AddTierSourceLines(rows, width, sources)
end

--One target's sum: its own roll if it had one, what the tier dealt, what changed it, and
--what landed. count > 1 for numbered creatures that all got the same.
--- @param own? HistoryEdgeSource[] Roll sources that applied to this target alone.
local function AddTargetLines(rows, width, entry, who, count, own)
    if who.roll ~= nil then
        AddEdgeLines(rows, width, who.roll.edges, who.roll.banes, true, who.roll.sources)
        rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.their_roll"), badge = who.tier, value = tostring(who.roll.total), total = true})
    elseif own ~= nil and #own > 0 then
        AddOwnSources(rows, width, own)
    end
    --what dealt it: the tier against this target, or the ability when nothing was rolled.
    local source = (who.tier ~= nil and who.tier > 0) and T("history.tier", {tier = Int(who.tier)}) or entry.ability.name

    local taken = who.taken or 0
    if taken > 0 then
        local immunity = who.immunity
        local changed = immunity ~= nil and immunity.amount or 0
        local typeNames = {}
        for name in pairs(who.types or {}) do
            typeNames[#typeNames + 1] = name
        end
        table.sort(typeNames)

        --what each damage line dealt before immunity, by type ("untyped" for the rest).
        local dealt = {}
        local typed = 0
        for _, name in ipairs(typeNames) do
            local landed = who.types[name]
            typed = typed + landed
            dealt[name] = landed + ((immunity ~= nil and immunity.damagetype == name) and changed or 0)
        end
        if taken > typed or #typeNames == 0 then
            local typedImmunity = immunity ~= nil and who.types ~= nil and who.types[immunity.damagetype] ~= nil
            dealt.untyped = taken - typed + (typedImmunity and 0 or changed)
        end

        --the kit, modifiers and surges come off the line of the type they added to,

        --leaving the tier's own damage. If they don't fit the lines, the line stays whole.
        local parts = who.parts or {}
        local base = {}
        for name, amount in pairs(dealt) do
            base[name] = amount
        end
        for _, part in ipairs(parts) do
            local key = part.damagetype or "untyped"
            if base[key] == nil then
                base = dealt
                parts = {}
                break
            end
            base[key] = base[key] - part.amount
        end
        for _, amount in pairs(base) do
            if amount < 0 then
                base = dealt
                parts = {}
                break
            end
        end
        --a fall, and a creature landing on this one, each get a line of their own: neither is
        --the tier's damage (Knockback deals none). Both are counted before immunity, as base is.
        local moved = who.moved
        local fall = 0
        if moved ~= nil and not moved.fallseparate then
            fall = moved.fallraw or moved.falldamage or 0
        end
        local landed = who.landeddamage or 0
        if fall > 0 and (base.untyped or 0) >= fall then
            base.untyped = base.untyped - fall
        else
            fall = 0
        end
        if landed > 0 and (base.untyped or 0) >= landed then
            base.untyped = base.untyped - landed
        else
            landed = 0
        end

        local first = true
        local function Dealt(label, raw)
            rows[#rows + 1] = ReceiptLine(width, {label = label, value = first and tostring(raw) or Signed(raw)})
            first = false
        end
        --a type the tier itself dealt none of (all of it came from a modifier, say) gets no
        --"Tier 3: lightning 0" line; the modifier's own line below carries it.
        local lines = {}
        for _, name in ipairs(typeNames) do
            lines[#lines + 1] = {label = T("history.numbers.dealt_type", {source = source, type = name}), amount = base[name]}
        end
        if base.untyped ~= nil then
            --entries from before the landing damage was recorded: a landed-on creature with no
            --roll took its damage from the faller.
            local oldLanded = who.landedon and who.landeddamage == nil and who.tier == nil
            lines[#lines + 1] = {label = oldLanded and T("history.numbers.landed_on") or source, amount = base.untyped}
        end
        if fall > 0 then
            lines[#lines + 1] = {label = T("history.numbers.fall"), amount = fall}
        end
        if landed > 0 then
            lines[#lines + 1] = {label = T("history.numbers.landed_on"), amount = landed}
        end
        local shown = 0
        for _, line in ipairs(lines) do
            if line.amount ~= 0 then
                Dealt(line.label, line.amount)
                shown = shown + 1
            end
        end
        if shown == 0 and #lines > 0 then
            Dealt(lines[1].label, lines[1].amount)
        end
        for _, part in ipairs(parts) do
            rows[#rows + 1] = DamagePartLine(width, part)
        end
        if changed ~= 0 then
            rows[#rows + 1] = ReceiptLine(width, {label = ResistWords(immunity), value = Signed(-changed)})
        end
        rows[#rows + 1] = ReceiptLine(width, {
            label = count > 1 and T("history.numbers.taken_each") or T("history.numbers.taken"),
            value = tostring(taken),
            valueClass = "historyHurt",
            total = true,
        })
    end

    local healed = who.healed or 0
    if healed > 0 then
        rows[#rows + 1] = ReceiptLine(width, {label = source, value = tostring(healed)})
        rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.regained"), value = tostring(healed), valueClass = "historyHealed", total = true})
    end

    --a push that stability shortened or stopped, or that ignored it.
    local moved = who.moved
    if moved ~= nil and moved.requested ~= nil and ((moved.stability or 0) > 0 or moved.ignored) then
        local kind = string.upper_first(string.gsub(moved.kind, "_", " "))
        rows[#rows + 1] = ReceiptLine(width, {label = kind, value = tostring(moved.requested)})
        if moved.ignored then
            rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.stability_ignored"), value = ""})
        else
            rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.stability"), value = Signed(-moved.stability)})
        end
        rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.moved"), value = tostring(moved.distance), total = true})
    end
end

--Targets with the same numbers share one sum ("Goblin 1-4", "Taken, each").
--- @param own? HistoryEdgeSource[] Roll sources that applied to this target alone.
local function ReceiptKey(who, own)
    own = own or {}
    local moved = who.moved
    local stability = ""
    if moved ~= nil and moved.requested ~= nil and ((moved.stability or 0) > 0 or moved.ignored) then
        stability = string.format("%s/%d/%d/%d/%s", moved.kind, moved.requested, moved.stability or 0, moved.distance, tostring(moved.ignored))
    end
    --the fall and landing amounts get lines of their own, so a faller and the creature it
    --landed on must not share a sum.
    if moved ~= nil and (moved.falldamage or 0) > 0 then
        stability = stability .. string.format("/fall%d/%d/%s", moved.falldamage, moved.fallraw or 0, tostring(moved.fallseparate))
    end
    if who.landedon then
        stability = stability .. string.format("/landed%d", who.landeddamage or 0)
    end
    if (who.taken or 0) == 0 and (who.healed or 0) == 0 and who.roll == nil and stability == "" and #own == 0 then
        return nil
    end
    local types = {}
    for name, amount in pairs(who.types or {}) do
        types[#types + 1] = name .. amount
    end
    table.sort(types)
    local immunity = who.immunity ~= nil and (who.immunity.damagetype .. who.immunity.amount) or ""
    local roll = ""
    if who.roll ~= nil then
        local names = {}
        for _, source in ipairs(who.roll.sources or {}) do
            names[#names + 1] = string.format("%s%s/%d/%d/%d/%d/%s/%d", source.name, source.who ~= nil and source.who.id or "",
                source.edges or 0, source.banes or 0, source.removedEdges or 0, source.removedBanes or 0, TierValue(source) or "",
                source.bonus or 0)
        end
        roll = string.format("%d/%d/%d/%s", who.roll.edges or 0, who.roll.banes or 0, who.roll.total, table.concat(names, ","))
    end
    local ownKeys = {}
    for _, source in ipairs(own) do
        ownKeys[#ownKeys + 1] = History.SourceKey(source)
    end
    roll = roll .. "/" .. table.concat(ownKeys, ",")
    local parts = {}
    for _, part in ipairs(who.parts or {}) do
        parts[#parts + 1] = string.format("%s/%s/%s/%d/%s", part.kind, part.name or "", part.who ~= nil and part.who.id or "",
            part.amount, part.damagetype or "")
    end
    return string.format("%s|%d|%d|%s|%s|%s|%s|%s", tostring(who.tier), who.taken or 0, who.healed or 0, table.concat(types, ","), immunity, roll,
        table.concat(parts, ","), stability)
end

--"Rolled in secret." for a roll hidden from players. The Director's copy carries an eye that
--shows the roll's numbers to players, or hides them again.
--- @param entry HistoryEntry
--- @param width number
--- @return Panel
local function SecretRollRow(entry, width)
    local children = {}
    --a test or dice line keeps who may see it in privacy; an action, on its roll.
    local roll = entry.privacy or entry.roll
    --the eye is the Director's: a player who rolled GM only sees their roll, not the eye.
    --It writes the entry back, so a viewer holding the players' cut-down copy of the
    --entry would erase the roll for everyone.
    if roll ~= nil and roll.hidden and dmhub.isDM then
        children[1] = gui.VisibilityPanel{
            visible = roll.revealed == true,
            width = 14,
            height = 14,
            rmargin = 6,
            halign = "left",
            valign = "center",
            click = function(element)
                roll.revealed = (not roll.revealed) or nil
                --flip it on the stored entry, so nothing another client set since is lost
                --and an entry deleted or culled meanwhile is not brought back.
                local stored = History.Stored(entry)
                if stored ~= nil then
                    local storedRoll = stored.privacy or stored.roll
                    if storedRoll ~= nil then
                        storedRoll.revealed = roll.revealed
                        History.RewriteQuietly(stored)
                    end
                end
                element:FireEvent("visible", roll.revealed == true)
            end,
            linger = function(element)
                gui.Tooltip(roll.revealed and T("history.visible_to_everyone") or T("history.hidden_from_players"))(element)
            end,
        }
    end
    children[#children + 1] = gui.Label{
        classes = {"historyReceiptAside"},
        text = T("history.numbers.rolled_in_secret_note"),
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
    }
    return gui.Panel{
        flow = "horizontal",
        width = width,
        height = "auto",
        vpad = 2,
        borderBox = true,
        halign = "left",
        children = children,
    }
end

--What an overridden roll's card says in place of explaining its tier.
--- @param roll table A roll with overridden = {by, dicetier}.
--- @return string
local function OverrideWords(roll)
    return T("history.numbers.overridden", {name = roll.overridden.by or T("history.director"), tier = Int(roll.tier),
        dicetier = Int(roll.overridden.dicetier)})
end

--A roll on a table: its dice, any bonus, the total, then the row it landed on in full and,
--when the result was overridden, the roll dialog's message saying who changed it.
local function AddTableLines(rows, width, entry)
    if entry.dice ~= nil and #entry.dice > 0 then
        local lead = {}
        local sum = 0
        for _, face in ipairs(entry.dice) do
            lead[#lead + 1] = Die(face)
            sum = sum + face
        end
        rows[#rows + 1] = ReceiptLine(width, {lead = lead, value = tostring(sum)})
        if entry.total ~= nil and entry.total ~= sum then
            rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.bonus"), value = Signed(entry.total - sum)})
        end
    end
    if entry.total ~= nil then
        rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.total"), value = tostring(entry.total), total = true})
    end
    if entry.result ~= nil then
        rows[#rows + 1] = SubHead(T("history.numbers.result"), width)
        rows[#rows + 1] = ReceiptNote(width, entry.result)
    end
    if entry.overridden ~= nil then
        rows[#rows + 1] = ReceiptNote(width, entry.overridden, "historyReceiptMore")
    end
end

--- The receipt's rows for an action entry; empty when it has nothing to add up.
--- @param entry HistoryEntry
--- @param kids HistoryEntry[]|nil
--- @param width number
--- @return Panel[]
local function NumbersRows(entry, kids, width)
    g_linkMap = entry.map
    local rows = {}
    local targets = entry.targets or {}

    --a roll hidden from players: they get this line instead of its numbers; the
    --Director gets it above the numbers, with the eye that shows them to players. Once
    --shown to everyone, only the Director keeps the line, for the eye that hides it again.
    local hidden = entry.privacy or entry.roll
    if entry.secretroll or (hidden ~= nil and hidden.hidden and (dmhub.isDM or not hidden.revealed)) then
        rows[#rows + 1] = SecretRollRow(entry, width)
    end

    local roll = entry.roll
    --targets that rolled with the main roll but owed its edges to different things: the
    --Power roll lines name what applied to all of them, each target's sum its own.
    local rollSources = roll ~= nil and roll.sources or nil
    --- @type table<HistoryCreature, HistoryEdgeSource[]>
    local ownOf = {}
    if roll ~= nil then
        local plain, differs = {}, false
        for _, who in ipairs(targets) do
            if who.roll == nil and who.tier ~= nil then
                plain[#plain + 1] = who
                differs = differs or who.sources ~= nil
            end
        end
        if differs then
            local sharedOf
            sharedOf, ownOf = SplitSources(roll, plain)
            rollSources = sharedOf[plain[1]]
        end
    end
    --each side of an opposed power roll, under its roller's name: the same lines a test
    --line's own card shows. A roll players may not see keeps only its heading.
    for _, kid in ipairs(kids or {}) do
        if kid.family == "test" and kid.cause ~= nil then
            local name = kid.who ~= nil and History.ShownName(kid.who) or T("history.director")
            rows[#rows + 1] = SubHead(name .. History.DOT .. (kid.name or T("history.numbers.roll")), width, kid.who)
            if kid.roll ~= nil and not kid.secretroll then
                for _, line in ipairs(NumbersRows(kid, nil, width)) do
                    rows[#rows + 1] = line
                end
            else
                rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.rolled_in_secret"), value = ""})
            end
        end
    end
    if roll ~= nil then
        --a nested roll sits under its roller's heading already.
        if entry.cause == nil or entry.family ~= "test" then
            rows[#rows + 1] = SubHead(T("history.numbers.power_roll"), width)
        end
        if roll.natural ~= nil and roll.low ~= nil and roll.high ~= nil then
            rows[#rows + 1] = ReceiptLine(width, {lead = {Die(roll.low), Die(roll.high)}, value = tostring(roll.natural)})
            --a monster's stat block gives its roll a flat number, not a characteristic, so its
            --characteristic goes into Bonus. An action keeps its roller in actor; a test line, in who.
            local roller = entry.actor
            if roller == nil and entry.family == "test" then
                roller = entry.who
            end
            local monster = roller ~= nil and not roller.hero
            if roll.characteristic ~= nil and not monster then
                rows[#rows + 1] = ReceiptLine(width, {label = roll.characteristic.name, value = Signed(roll.characteristic.value)})
            end
            --a bonus a modifier gave has its own line under the edges; this is the rest.
            local bonus = roll.bonus or 0
            if monster and roll.characteristic ~= nil then
                bonus = bonus + roll.characteristic.value
            end
            for _, source in ipairs(roll.sources or {}) do
                bonus = bonus - (source.bonus or 0)
            end
            if bonus ~= 0 then
                rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.bonus"), value = Signed(bonus)})
            end
        end
        AddEdgeLines(rows, width, roll.edges, roll.banes, false, rollSources, entry.family == "test" and entry.cause ~= nil)
        --the tier of the roll itself: a target with edges or banes of its own got another.
        local tier = roll.tier
        for _, who in ipairs(targets) do
            if who.roll == nil and who.tier ~= nil then
                tier = who.tier
                break
            end
        end
        --an opposed roll is compared with the other side's total: it has no tier.
        --- @type number|nil
        local badge = tier
        if entry.family == "test" and entry.cause ~= nil then
            badge = nil
        end
        rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.total"), badge = badge, value = tostring(roll.total), total = true})
        --a test's card has no Why, so its numbers say who set the tier.
        if entry.family == "test" and roll.overridden ~= nil then
            rows[#rows + 1] = ReceiptNote(width, OverrideWords(roll), "historyReceiptMore")
        end
    end

    --a table the ability rolled on, under its roller's name, as the table line's own card has it.
    for _, kid in ipairs(kids or {}) do
        if kid.family == "table" then
            local name = kid.who ~= nil and History.ShownName(kid.who) or kid.roller or T("history.director")
            rows[#rows + 1] = SubHead(name .. History.DOT .. (kid.name or T("history.table")), width, kid.who)
            AddTableLines(rows, width, kid)
        end
    end

    if entry.family == "table" then
        rows[#rows + 1] = SubHead(T("history.numbers.dice"), width)
        AddTableLines(rows, width, entry)
    end

    --a Dice panel roll: each die, its edges and banes, and what the total adds past them.
    if entry.family == "dice" and entry.dice ~= nil then
        rows[#rows + 1] = SubHead(T("history.numbers.dice"), width)
        local lead = {}
        local sum = 0
        for _, face in ipairs(entry.dice) do
            lead[#lead + 1] = Die(face)
            sum = sum + face
        end
        rows[#rows + 1] = ReceiptLine(width, {lead = lead, value = tostring(sum)})
        AddEdgeLines(rows, width, entry.edges, entry.banes, false, nil)
        local edgeBonus = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(entry.edges or 0, entry.banes or 0)
        local bonus = entry.total - sum - edgeBonus
        if bonus ~= 0 then
            rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.bonus"), value = Signed(bonus)})
        end
        rows[#rows + 1] = ReceiptLine(width, {label = T("history.numbers.total"), badge = entry.tier, value = tostring(entry.total), total = true})
    end

    local groups = {}
    local byKey = {}
    for _, who in ipairs(targets) do
        local key = ReceiptKey(who, ownOf[who])
        if key ~= nil then
            if byKey[key] == nil then
                byKey[key] = {}
                groups[#groups + 1] = byKey[key]
            end
            table.insert(byKey[key], who)
        end
    end
    for _, group in ipairs(groups) do
        rows[#rows + 1] = SubHead(GroupNames(group), width, group[1])
        AddTargetLines(rows, width, entry, group[1], #group, ownOf[group[1]])
    end

    local triggered = {}
    for _, kid in ipairs(kids or {}) do
        if (kid.kind == "trigger" or kid.kind == "action") and kid.actor ~= nil then
            local net = 0
            for _, who in ipairs(kid.targets or {}) do
                net = net - (who.taken or 0) + (who.healed or 0)
            end
            if net ~= 0 then
                local face = History.Face(kid.actor, 20, true)
                face.selfStyle.rmargin = 6
                face.selfStyle.halign = "left"
                triggered[#triggered + 1] = ReceiptLine(width, {
                    lead = {face},
                    label = History.ShownName(kid.actor) .. (kid.ability ~= nil and (History.DOT .. kid.ability.name) or ""),
                    value = Signed(net),
                    valueClass = cond(net < 0, "historyHurt", "historyHealed"),
                })
            end
        end
    end
    if #triggered > 0 then
        rows[#rows + 1] = SubHead(T("history.numbers.triggered"), width)
        for _, row in ipairs(triggered) do
            rows[#rows + 1] = row
        end
    end

    if entry.costs ~= nil then
        local names = {}
        for name in pairs(entry.costs) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            rows[#rows + 1] = ReceiptNote(width, T("history.numbers.cost", {cost = History.ResourceWords(entry.costs[name].amount, name)}), "historyReceiptMore")
        end
    end
    return rows
end

--- One line of the card's Why: a bold lead, then one plain sentence.
--- @class HistoryWhyRow
--- @field lead string|nil
--- @field text string
--- @field who HistoryCreature|nil A face before the lead: the owner of a modifier.
--- @field plain boolean|nil The line saying nothing changed the result: muted, with no lead.
--- @field movers HistoryCreature[]|nil Whose recorded move the lead's side view button shows.

--Conditions whose name doesn't follow "cannot be".
local CONDITION_PHRASES = {prone = T("history.why.condition_phrase.prone")}

--How many surges came from one place, starting a sentence: "Two were gained from...".
local SURGE_NUMBERS = {T("history.why.surge_number.1"), T("history.why.surge_number.2"), T("history.why.surge_number.3"),
    T("history.why.surge_number.4"), T("history.why.surge_number.5")}

--How many minions died, in words: "killed two".
local MINION_WORDS = {T("history.why.minion_number.1"), T("history.why.minion_number.2"), T("history.why.minion_number.3"),
    T("history.why.minion_number.4"), T("history.why.minion_number.5"), T("history.why.minion_number.6"),
    T("history.why.minion_number.7"), T("history.why.minion_number.8"), T("history.why.minion_number.9"),
    T("history.why.minion_number.10")}

--A trigger name longer than this is taken for its rule text, not a name.

local TRIGGER_NAME_MAX = 40

--What one trigger nested under an action did, in What happened's words ("Human Talent took
--1 damage.", "Lv2 Human Null gained 1 Discipline."). Nil when it did nothing to show.
--- @param kid HistoryEntry
--- @return string|nil
local function TriggerEffect(kid)
    if kid.family == "resource" then
        return T("history.story.resource", {name = History.ShownName(kid.who),
            verb = (kid.amount or 0) > 0 and T("history.story.resource.gained") or T("history.story.resource.spent"),
            resource = History.ResourceWords(math.abs(kid.amount or 0), kid.name)})
    end
    local sentences = {}
    for _, who in ipairs(kid.targets or {}) do
        local words = Predicate(who)
        if words ~= nil then
            sentences[#sentences + 1] = History.ShownName(who) .. words
        end
    end
    return #sentences > 0 and table.concat(sentences, " ") or nil
end

--The tier a power roll comes to with these edges, banes and tier modifiers, by the roll's
--own rules. base is its total without the edge or bane bonus.
local function TierOf(base, natural, edges, banes, mods)
    return RollUtils.DiceResultToTier{
        total = base + ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(edges, banes),
        naturalRoll = natural,
        boons = edges,
        banes = banes,
        tiers = mods.tiers,
        autosuccess = mods.autosuccess,
        autofailure = mods.autofailure,
        nottierthree = mods.nottierthree,
        nottierone = mods.nottierone,
    }
end

--"an edge", "a double edge", "a bane", "a double bane".
local function EdgeNoun(side, count)
    if count >= 2 then
        return side == "edge" and T("history.why.a_double_edge") or T("history.why.a_double_bane")
    end
    return side == "edge" and T("history.why.an_edge") or T("history.why.a_bane")
end

--- One thing that can move a power roll's tier. Everything that gave
--- edges is one part, so the line names them together; likewise banes, and what took edges
--- or banes away. A tier modifier, a flat bonus and a natural 19 or 20 are a part each.
--- @class HistoryTierPart
--- @field kind "edges"|"banes"|"noedges"|"nobanes"|"tier"|"bonus"|"natural"
--- @field up boolean It pushes the tier up.
--- @field sources HistoryEdgeSource[]

--Which way a tier modifier pushes, read in TierValue's order so it matches The numbers.
--- @param source HistoryEdgeSource
local function TierModUp(source)
    if source.autosuccess then
        return true
    elseif source.autofailure then
        return false
    elseif (source.tiers or 0) ~= 0 then
        return source.tiers > 0
    end
    return not source.nottierthree
end

--- The parts of a roll that could have moved its tier, in the order its line names them.
--- @param sources HistoryEdgeSource[]
--- @param natural integer
--- @return HistoryTierPart[]
local function TierParts(sources, natural)
    local kinds = {"edges", "banes", "noedges", "nobanes"}
    local fields = {edges = "edges", banes = "banes", noedges = "removedEdges", nobanes = "removedBanes"}
    local groups = {}
    for _, kind in ipairs(kinds) do
        groups[kind] = {kind = kind, up = kind == "edges" or kind == "nobanes", sources = {}}
    end
    local others = {}
    for _, source in ipairs(sources) do
        for _, kind in ipairs(kinds) do
            if (source[fields[kind]] or 0) > 0 then
                table.insert(groups[kind].sources, source)
            end
        end
        if TierValue(source) ~= nil then
            others[#others + 1] = {kind = "tier", up = TierModUp(source), sources = {source}}
        end
        if (source.bonus or 0) ~= 0 then
            others[#others + 1] = {kind = "bonus", up = source.bonus > 0, sources = {source}}
        end
    end
    local parts = {}
    for _, kind in ipairs(kinds) do
        if #groups[kind].sources > 0 then
            parts[#parts + 1] = groups[kind]
        end
    end
    for _, part in ipairs(others) do
        parts[#parts + 1] = part
    end
    if natural >= 19 then
        parts[#parts + 1] = {kind = "natural", up = true, sources = {}}
    end
    return parts
end

--- The tier a roll comes to with only some of its parts. A part left out is taken back off
--- what the roll recorded, so whatever no part accounts for (a characteristic, an edge the
--- ability always has) stays in.
--- @param roll {total: number, edges: number|nil, banes: number|nil}
--- @param natural integer
--- @param parts HistoryTierPart[]
--- @param include fun(part: HistoryTierPart): boolean
--- @return integer
local function TierWith(roll, natural, parts, include)
    local edges, banes = roll.edges or 0, roll.banes or 0
    local base = roll.total - ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(edges, banes)
    local mods = {tiers = 0}
    local dice = natural
    for _, part in ipairs(parts) do
        local on = include(part)
        if part.kind == "natural" and not on then
            --an 18 is the same dice without the natural 19 or 20 rule.
            dice = math.min(natural, 18)
        end
        for _, source in ipairs(part.sources) do
            if part.kind == "tier" then
                if on then
                    mods.tiers = mods.tiers + (source.tiers or 0)
                    mods.autosuccess = mods.autosuccess or source.autosuccess
                    mods.autofailure = mods.autofailure or source.autofailure
                    mods.nottierthree = mods.nottierthree or source.nottierthree
                    mods.nottierone = mods.nottierone or source.nottierone
                end
            elseif not on then
                if part.kind == "edges" then
                    edges = edges - (source.edges or 0)
                elseif part.kind == "banes" then
                    banes = banes - (source.banes or 0)
                elseif part.kind == "noedges" then
                    edges = edges + (source.removedEdges or 0)
                elseif part.kind == "nobanes" then
                    banes = banes + (source.removedBanes or 0)
                elseif part.kind == "bonus" then
                    base = base - (source.bonus or 0)
                end
            end
        end
    end
    return TierOf(base, dice, math.max(0, edges), math.max(0, banes), mods)
end

--A rule that sets the tier outright: with one on its side, nothing else there mattered.
--- @param part HistoryTierPart
local function SetsTier(part)
    if part.kind == "natural" then
        return true
    end
    local source = part.sources[1]
    return part.kind == "tier" and (source.autosuccess == true or source.autofailure == true)
end

--- What one part did, as clauses of the tier line: "Prone gave an edge", "Twisted ignored
--- it", "Mark raised it a tier".
--- @param part HistoryTierPart
--- @param parts HistoryTierPart[] All of the roll's parts, to count what a remover took from.
--- @param mentioned boolean The edges or banes it took away were named earlier in the line, so "it" points at them.
--- @param earlier? {edge: integer, bane: integer} On a target's line: the edges and banes the roll's own line had, so a remover of those says "the double edge".
--- @return string[]
local function PartClauses(part, parts, mentioned, earlier)
    local side = (part.kind == "edges" or part.kind == "noedges") and "edge" or "bane"
    local gaveField = side == "edge" and "edges" or "banes"
    if part.kind == "edges" or part.kind == "banes" then
        local names, named, hand = {}, 0, 0
        for _, source in ipairs(part.sources) do
            if source.hand then
                hand = hand + (source[gaveField] or 0)
            else
                names[#names + 1] = SourceText(source, true)
                named = named + (source[gaveField] or 0)
            end
        end
        local clauses = {}
        if #names > 0 then
            clauses[1] = T("history.why.gave", {names = JoinWords(names), what = EdgeNoun(side, named)})
        end
        if hand > 0 then
            clauses[#clauses + 1] = T("history.why.set_by_hand", {what = (#names > 0 and hand == 1) and T("history.why.another") or EdgeNoun(side, hand)})
        end
        return clauses
    end

    if part.kind == "noedges" or part.kind == "nobanes" then
        local field = side == "edge" and "removedEdges" or "removedBanes"
        local names, removed, ignored = {}, 0, true
        for _, source in ipairs(part.sources) do
            names[#names + 1] = SourceText(source, true)
            removed = removed + (source[field] or 0)
            ignored = ignored and source.ignore == true
        end
        local what = EdgeNoun(side, removed)
        if mentioned then
            local given = 0
            for _, other in ipairs(parts) do
                if other.kind == gaveField then
                    for _, source in ipairs(other.sources) do
                        given = given + (source[gaveField] or 0)
                    end
                end
            end
            what = removed >= given and T("history.why.removed.it") or removed == 1 and T("history.why.removed.one") or T("history.why.removed.two")
        elseif earlier ~= nil and earlier[side] > 0 then
            local had = earlier[side]
            if removed >= had then
                if side == "edge" then
                    what = had >= 2 and T("history.why.the_double_edge") or T("history.why.the_edge")
                else
                    what = had >= 2 and T("history.why.the_double_bane") or T("history.why.the_bane")
                end
            elseif side == "edge" then
                what = removed == 1 and T("history.why.one_edge") or T("history.why.two_edges")
            else
                what = removed == 1 and T("history.why.one_bane") or T("history.why.two_banes")
            end
        end
        return {T("history.why.removed", {names = JoinWords(names),
            verb = ignored and T("history.why.removed.verb_ignored") or T("history.why.removed.verb_removed"), what = what})}
    end

    local source = part.sources[1]
    if part.kind == "tier" then
        local did = T("history.why.tier.kept_off_1")
        if source.autosuccess then
            did = T("history.why.tier.made_3")
        elseif source.autofailure then
            did = T("history.why.tier.made_1")
        elseif (source.tiers or 0) ~= 0 then
            --"or 0" only tells the type checker tiers is set. The count is passed as it is:
            --the old count .. " tiers" wrote it as tostring does.
            local count = math.abs(source.tiers or 0)
            local tiers = UIText.Plural("history.why.tier.tiers", count, {count = count})
            did = source.tiers > 0 and T("history.why.tier.raised", {tiers = tiers}) or T("history.why.tier.lowered", {tiers = tiers})
        elseif source.nottierthree then
            did = T("history.why.tier.kept_from_3")
        end
        return {T("history.why.tier", {source = SourceText(source, true), did = did})}
    end
    if part.kind == "bonus" then
        local bonus = source.bonus or 0
        local values = {source = SourceText(source, true), amount = Int(math.abs(bonus))}
        return {bonus > 0 and T("history.why.bonus_added", values) or T("history.why.bonus_took", values)}
    end
    return {T("history.why.natural")}
end

--A Why sentence starts with a capital; one that opens on a [Name] capitalises inside it.
--- @param text string
--- @return string
local function Capitalise(text)
    local tag = string.match(text, "^%[") or ""
    return tag .. string.upper(string.sub(text, #tag + 1, #tag + 1)) .. string.sub(text, #tag + 2)
end

--"a", "a, and b", "a, b, and c": the clauses hold "and" of their own, so the comma keeps
--them apart.
--- @param clauses string[]
local function JoinClauses(clauses)
    if #clauses <= 1 then
        return clauses[1] or ""
    end
    local most = {}
    for i = 1, #clauses - 1 do
        most[i] = clauses[i]
    end
    return T("history.why.join_clauses", {most = table.concat(most, ", "), last = clauses[#clauses]})
end

--- Which of a roll's parts a tier line may name (TierStory).
--- @class HistoryTierStoryOpts
--- @field parts? HistoryTierPart[] All the roll's parts; default those of roll.sources.
--- @field named? fun(part: HistoryTierPart): boolean The parts this line may name.
--- @field always? fun(part: HistoryTierPart): boolean Parts that stay on under the line, never named.
--- @field movedOnly? boolean No line unless the named parts moved the tier.

--- @class HistoryTierStory
--- @field tier integer
--- @field qualifier string ", up from Tier 2", ", down from Tier 3", ", not Tier 3" or "".
--- @field text string

--- A roll's tier line: where the roll landed and what got it there, worked
--- out for all its parts together. "From" is the tier the dice and characteristic gave alone.
--- It names the parts on the side the tier moved, and the other side only when that changed
--- where it landed ("but Twisted ignored it"). Nil when nothing moved or held the tier, and
--- when the recorded parts don't come to the tier the roll got, since something History
--- didn't record set it.
---
--- A line can name only some of the roll's parts (opts.named) over others that stay on
--- underneath (opts.always): a target's line names what applied to it alone over what
--- applied to every target, so its "from" is the roll's own line.
--- @param roll {total: number, edges: number|nil, banes: number|nil, sources: HistoryEdgeSource[]|nil}
--- @param tier integer The tier the roll came to.
--- @param natural integer The dice, for the natural 19 or 20 rule.
--- @param opts? HistoryTierStoryOpts Default: every part of roll.sources, all named.
--- @return HistoryTierStory|nil
local function TierStory(roll, tier, natural, opts)
    local all = opts ~= nil and opts.parts or TierParts(roll.sources or {}, natural)
    local named = opts ~= nil and opts.named or function() return true end
    local always = opts ~= nil and opts.always or function() return false end
    local parts = {}
    --the edges and banes left on underneath, for a remover that took them ("the double edge").
    local earlier = nil
    for _, part in ipairs(all) do
        if named(part) then
            parts[#parts + 1] = part
        elseif always(part) and (part.kind == "edges" or part.kind == "banes") then
            earlier = earlier or {edge = 0, bane = 0}
            local side = part.kind == "edges" and "edge" or "bane"
            for _, source in ipairs(part.sources) do
                earlier[side] = earlier[side] + (source[part.kind] or 0)
            end
        end
    end
    if #parts == 0 then
        return nil
    end
    local function With(include)
        return TierWith(roll, natural, all, function(part)
            return always(part) or (named(part) and include(part))
        end)
    end
    if With(function() return true end) ~= tier then
        return nil
    end
    local plain = With(function() return false end)
    if opts ~= nil and opts.movedOnly and tier == plain then
        return nil
    end
    local function Up(part) return part.up end
    local function Down(part) return not part.up end

    local toward, against, qualifier, held
    if tier ~= plain then
        toward = tier > plain and Up or Down
        against = tier > plain and Down or Up
        qualifier = tier > plain and T("history.why.qualifier.up_from_tier", {tier = Int(plain)})
            or T("history.why.qualifier.down_from_tier", {tier = Int(plain)})
        held = With(toward) ~= tier
    else
        --nothing moved it, but one side would have alone: say what held it.
        local up, down = With(Up), With(Down)
        if up == tier and down == tier then
            return nil
        end
        held = true
        if up ~= tier then
            toward, against = Up, Down
            qualifier = down == tier and T("history.why.qualifier.not_tier", {tier = Int(up)}) or ""
        else
            toward, against = Down, Up
            qualifier = T("history.why.qualifier.not_tier", {tier = Int(down)})
        end
    end

    --The parts of one side the line names. With filter, only those that did something
    --against the other side (an edge Twisted ignored did nothing), unless only several
    --together did. A rule that sets the tier outright is named alone.
    local function Side(test, other, filter)
        local list = {}
        for _, part in ipairs(parts) do
            if test(part) then
                list[#list + 1] = part
            end
        end
        if filter then
            local without = With(other)
            local kept, keep = {}, {}
            for _, part in ipairs(list) do
                if With(function(candidate) return candidate == part or other(candidate) end) ~= without then
                    kept[#kept + 1] = part
                    keep[part] = true
                end
            end
            if #kept > 0 and With(function(candidate) return keep[candidate] == true or other(candidate) end) == tier then
                list = kept
            end
        end
        local setters = {}
        for _, part in ipairs(list) do
            if SetsTier(part) then
                setters[#setters + 1] = part
            end
        end
        return #setters > 0 and setters or list
    end

    --when it held, the side that would have moved it is named whole: that is the point.
    local first = Side(toward, against, tier ~= plain)
    local named = {}
    local clauses = {}
    for _, part in ipairs(first) do
        named[part.kind] = true
        for _, clause in ipairs(PartClauses(part, parts, false, earlier)) do
            clauses[#clauses + 1] = clause
        end
    end
    if #clauses == 0 then
        return nil
    end
    local text = JoinClauses(clauses)
    text = Capitalise(text)

    if held then
        --what took edges or banes away comes first, so its "it" sits next to them.
        local others = Side(against, toward, true)
        local ordered = {}
        for pass = 1, 2 do
            for _, part in ipairs(others) do
                if (part.kind == "noedges" or part.kind == "nobanes") == (pass == 1) then
                    ordered[#ordered + 1] = part
                end
            end
        end
        local but = {}
        for _, part in ipairs(ordered) do
            local mentioned = (part.kind == "noedges" and named.edges) or (part.kind == "nobanes" and named.banes) or false
            for _, clause in ipairs(PartClauses(part, parts, mentioned, earlier)) do
                but[#but + 1] = clause
            end
        end
        if #but > 0 then
            text = T("history.why.but", {words = text, but = JoinClauses(but)})
        end
    end
    return {tier = tier, qualifier = qualifier, text = T("history.why.sentence_end", {words = text})}
end

--- An action's tier lines. The roll's line names only what applied

--- to every target. A target gets a line only when something that applied to it alone changed
--- its tier, and that line names only those things, "from" the roll's line. A modifier that
--- wasn't on, or didn't reach a target, is never in that target's lists, so it is never named.
--- A target whose recorded parts don't come to its tier gets no line.
--- @param roll {total: number, edges: number|nil, banes: number|nil, tier: number|nil, natural: number|nil, sources: HistoryEdgeSource[]|nil}
--- @param targets HistoryCreature[]
--- @return HistoryTierStory|nil main
--- @return {who: HistoryCreature, story: HistoryTierStory}[] lines
local function TierLines(roll, targets)
    local natural = roll.natural or 0
    local rolled = {}
    for _, who in ipairs(targets) do
        if who.tier ~= nil then
            rolled[#rolled + 1] = who
        end
    end
    if #rolled == 0 then
        return roll.tier ~= nil and TierStory(roll, roll.tier, natural) or nil, {}
    end

    --each target's parts, split into the shared ones and its own.
    local sharedOf, ownOf = SplitSources(roll, rolled)
    local plans = {}
    for _, who in ipairs(rolled) do
        local shared, own = sharedOf[who], ownOf[who]
        local parts = TierParts(shared, natural)
        local isShared = {}
        for _, part in ipairs(parts) do
            isShared[part] = true
        end
        for _, part in ipairs(TierParts(own, 0)) do
            parts[#parts + 1] = part
        end
        local counts = who.roll or roll
        if TierWith(counts, natural, parts, function() return true end) == who.tier then
            plans[#plans + 1] = {who = who, counts = counts, parts = parts, shared = isShared}
        end
    end
    if #plans == 0 then
        return nil, {}
    end

    local first = plans[1]
    local function SharedOf(plan)
        return function(part) return plan.shared[part] == true end
    end
    local rollTier = TierWith(first.counts, natural, first.parts, SharedOf(first))
    local main = TierStory(first.counts, rollTier, natural, {parts = first.parts, named = SharedOf(first)})
    local lines = {}
    for _, plan in ipairs(plans) do
        local shared = SharedOf(plan)
        local story = TierStory(plan.counts, plan.who.tier, natural, {
            parts = plan.parts,
            named = function(part) return not shared(part) end,
            always = shared,
            movedOnly = true,
        })
        if story ~= nil then
            lines[#lines + 1] = {who = plan.who, story = story}
        end
    end
    return main, lines
end

--- One thing besides the tier and kit that changed a target's damage.
--- @class HistoryDamageBit
--- @field key string Equal keys are the same thing doing the same, so targets can share it.
--- @field amount number What it did: positive added damage, negative took it off.
--- @field order integer Modifiers, then surges, then weakness or immunity.
--- @field clause string Its words in the damage line: "[Empyrean Boon] added 10 holy".
--- @field after? string A sentence of its own after the line: where free or gained surges came from.

--Surge source names joined, for a damage line's grouping key (plain names on older rows).
--- @param sources (string|{name: string})[]|nil
--- @return string
local function SourceNames(sources)
    local names = {}
    for i, source in ipairs(sources or {}) do
        names[i] = type(source) == "table" and source.name or tostring(source)
    end
    return table.concat(names, ",")
end

--- "One was gained from [Trained Assassin]...": how many of the surges spent on a target
--- came from these modifiers, and which they were. Nil when none did.
--- @param fromThese integer How many of the surges came from these modifiers.
--- @param count integer All the surges spent on the target.
--- @param names (string|{name: string, hover: string|nil})[]|nil
--- @param tail string Added before the full stop.
--- @return string|nil
local function SurgeOrigin(fromThese, count, names, tail)
    if fromThese <= 0 then
        return nil
    end
    local from = {}
    for _, source in ipairs(names or {}) do
        --rows from before hovers kept plain names.
        local name, hover
        if type(source) == "table" then
            name, hover = source.name, source.hover
        else
            name = source --[[@as string]]
        end
        from[#from + 1] = ModifierLink(WhyName(SpoilerName(name)), name, hover)
    end
    local source = #from > 0 and JoinClauses(from) or T("history.why.surges.a_modifier")
    local subject
    if fromThese == count then
        subject = count == 1 and T("history.why.surges.it_was") or T("history.why.surges.they_were")
    else
        local number = SURGE_NUMBERS[fromThese] or tostring(fromThese)
        subject = fromThese == 1 and T("history.why.surges.number_was", {number = number}) or T("history.why.surges.number_were", {number = number})
    end
    return T("history.why.surges.gained_from", {subject = subject, source = source, tail = tail})
end

--- What changed one target's damage besides its tier and kit. A kit is the hero's normal
--- damage, so it stays in the "from" number and is never named.
--- @param who HistoryCreature
--- @param actor HistoryCreature|nil Whose highest characteristic the surges used.
--- @return HistoryDamageBit[]
local function DamageBits(who, actor)
    local bits = {}
    for _, part in ipairs(who.parts or {}) do
        local amount = part.amount or 0
        local typed = part.damagetype ~= nil and (" " .. part.damagetype) or ""
        if part.kind == "modifier" and amount ~= 0 then
            local name = ModifierLink(WhyName(SpoilerName(part.name or "")), part.name or "", part.hover)
            if part.who ~= nil then
                name = T("history.possessive", {owner = History.ShownName(part.who), name = name})
            end
            bits[#bits + 1] = {
                key = string.format("modifier|%s|%s|%d|%s", part.name or "", part.who ~= nil and part.who.id or "", amount, part.damagetype or ""),
                amount = amount,
                order = 1,
                clause = amount > 0 and T("history.why.damage.added", {name = name, amount = Int(amount), type = typed})
                    or T("history.why.damage.took_off", {name = name, amount = Int(-amount)}),
            }
        elseif part.kind == "surge" and amount ~= 0 then
            local count = part.count or 0
            local clause = count == 1 and T("history.why.damage.surge_added", {amount = Int(part.each or 0), type = typed})
                or T("history.why.damage.surges_added", {count = Int(count), amount = Int(part.each or 0), type = typed})
            if part.characteristic ~= nil and actor ~= nil then
                clause = T("history.why.damage.surge_characteristic", {words = clause, name = History.ShownName(actor),
                    characteristic = part.characteristic, amount = Int(part.each or 0)})
            end
            --where some of the surges came from.
            local free = part.free or 0
            local after = SurgeOrigin(free, count, part.freefrom, T("history.why.surges.free_tail"))
            local gained = SurgeOrigin(math.min(part.gained or 0, count - free), count, part.gainedfrom, "")
            if gained ~= nil then
                after = after ~= nil and (after .. " " .. gained) or gained
            end
            bits[#bits + 1] = {
                key = string.format("surge|%d|%d|%s|%s|%d|%s|%d|%s", count, part.each or 0, part.damagetype or "", part.characteristic or "",
                    free, SourceNames(part.freefrom), part.gained or 0, SourceNames(part.gainedfrom)),
                amount = amount,
                order = 2,
                clause = clause,
                after = after,
            }
        end
    end
    --immunity records what it took off; weakness is the same with a negative amount.
    local immunity = who.immunity
    if immunity ~= nil and immunity.amount ~= 0 then
        local words = string.lower(ResistWords(immunity))
        bits[#bits + 1] = {
            key = string.format("immunity|%s|%d", immunity.damagetype, immunity.amount),
            amount = -immunity.amount,
            order = 3,
            clause = immunity.amount > 0 and T("history.why.damage.took_off", {name = words, amount = Int(immunity.amount)})
                or T("history.why.damage.added", {name = words, amount = Int(-immunity.amount), type = ""}),
        }
    end
    return bits
end

--- One damage sentence: what added, then ", but" what took off, each group in the bits'
--- order (modifiers, then surges, then weakness or immunity).
--- @param bits HistoryDamageBit[]
--- @return string
local function DamageText(bits)
    local sorted = {}
    for i, bit in ipairs(bits) do
        sorted[i] = {bit = bit, index = i}
    end
    table.sort(sorted, function(left, right)
        if left.bit.order ~= right.bit.order then
            return left.bit.order < right.bit.order
        end
        return left.index < right.index
    end)
    local up, down = {}, {}
    for _, item in ipairs(sorted) do
        local list = item.bit.amount > 0 and up or down
        list[#list + 1] = item.bit.clause
    end
    local text = #up > 0 and JoinClauses(up) or JoinClauses(down)
    if #up > 0 and #down > 0 then
        text = T("history.why.but", {words = text, but = JoinClauses(down)})
    end
    text = T("history.why.sentence_end", {words = Capitalise(text)})
    for _, item in ipairs(sorted) do
        if item.bit.after ~= nil then
            text = text .. " " .. item.bit.after
        end
    end
    return text
end

--", up from 15", ", down from 20", or nothing when the parts cancelled out.
--- @param total number
--- @param from number
--- @return string
local function DamageQualifier(total, from)
    if total > from then
        return T("history.why.qualifier.up_from", {amount = Int(from)})
    elseif total < from then
        return T("history.why.qualifier.down_from", {amount = Int(from)})
    end
    return ""
end

--- @class HistoryDamageLine
--- @field who HistoryCreature
--- @field total number The damage it took.
--- @field qualifier string
--- @field text string

--- An action's damage lines, shaped like its tier lines. The shared line
--- names what changed the damage of every target that took some: "19 damage, up from 15"
--- when they all started from the same tier damage, "12 extra damage" when their tiers
--- differed. A target gets a line only for what applied to it alone, "from" what the shared
--- line gave it. When tiers differ and the shared parts took damage away, there is no shared
--- line and each target's line names everything, from its tier damage.
--- @param targets HistoryCreature[]
--- @param actor HistoryCreature|nil
--- @return {lead: string, text: string}|nil shared
--- @return HistoryDamageLine[] lines
local function DamageLines(targets, actor)
    local dealt = {}
    for _, who in ipairs(targets) do
        local bits = DamageBits(who, actor)
        if (who.taken or 0) > 0 or #bits > 0 then
            --the tier's damage, kit included: what it took with the named parts taken back off.
            local base = who.taken or 0
            for _, bit in ipairs(bits) do
                base = base - bit.amount
            end
            dealt[#dealt + 1] = {who = who, bits = bits, base = base, shared = {}, own = {}}
        end
    end
    if #dealt == 0 then
        return nil, {}
    end

    --what every target had: each bit as many times as the target with fewest has it.
    --- @type table<string, integer>|nil
    local common = nil
    for _, item in ipairs(dealt) do
        local counts = {}
        for _, bit in ipairs(item.bits) do
            counts[bit.key] = (counts[bit.key] or 0) + 1
        end
        if common == nil then
            common = counts
        else
            for key, count in pairs(common) do
                common[key] = math.min(count, counts[key] or 0)
            end
        end
    end
    local sameBase = true
    for _, item in ipairs(dealt) do
        local left = {}
        for key, count in pairs(common or {}) do
            left[key] = count
        end
        for _, bit in ipairs(item.bits) do
            if (left[bit.key] or 0) > 0 then
                left[bit.key] = left[bit.key] - 1
                item.shared[#item.shared + 1] = bit
            else
                item.own[#item.own + 1] = bit
            end
        end
        sameBase = sameBase and item.base == dealt[1].base
    end

    local sharedBits = dealt[1].shared
    local sharedSum = 0
    for _, bit in ipairs(sharedBits) do
        sharedSum = sharedSum + bit.amount
    end
    local shared = nil
    if #sharedBits > 0 then
        if sameBase then
            local total = dealt[1].base + sharedSum
            shared = {lead = T("history.why.lead.damage", {amount = Int(total), qualifier = DamageQualifier(total, dealt[1].base)}), text = DamageText(sharedBits)}
        elseif sharedSum > 0 then
            shared = {lead = T("history.why.lead.extra_damage", {amount = Int(sharedSum)}), text = DamageText(sharedBits)}
        else
            for _, item in ipairs(dealt) do
                for _, bit in ipairs(item.shared) do
                    item.own[#item.own + 1] = bit
                end
            end
        end
    end

    local lines = {}
    for _, item in ipairs(dealt) do
        if #item.own > 0 then
            local from = item.base + (shared ~= nil and sharedSum or 0)
            local total = item.who.taken or 0
            lines[#lines + 1] = {who = item.who, total = total, qualifier = DamageQualifier(total, from), text = DamageText(item.own)}
        end
    end
    return shared, lines
end

--- Why an action came out as it did, from what the entry recorded: the tier line, an area
--- that hit an ally, damage modifiers, surges, immunity, condition immunity, then the
--- triggers it set off and the notes its author typed. A line that several targets share is
--- written once, naming them all. When nothing changed the result, one plain line says so.
--- No gui, so other views can use the same words.

--- @param entry HistoryEntry
--- @param kids? HistoryEntry[] What is nested under it.
--- @return HistoryWhyRow[]
function History.Why(entry, kids)
    local rows = {}
    g_linkMap = entry.map
    if entry.kind ~= "action" then
        return rows
    end
    local targets = entry.targets or {}

    --each line is built once all its targets are known, so make can name them together
    --("Goblin 1-4").
    local order = {}
    local byKey = {}
    local function Add(key, make, who)
        local line = byKey[key]
        if line == nil then
            line = {make = make, who = {}}
            byKey[key] = line
            order[#order + 1] = line
        end
        line.who[#line.who + 1] = who
    end

    --a triggered action says first what set it off, in its own Trigger line's words. A
    --monster's rules are the Director's, as its trigger card is.
    local triggerText = entry.ability ~= nil and entry.ability.triggertext or nil
    if entry.provoker ~= nil and entry.actor ~= nil then
        --a free strike for moving away says so in the rules' words instead.
        rows[#rows + 1] = {
            lead = T("history.why.lead.moved_away"),
            text = T("history.why.moved_away", {name = History.ShownName(entry.provoker), striker = History.ShownName(entry.actor)}),
        }
    elseif triggerText ~= nil and (dmhub.isDM or (entry.actor ~= nil and entry.actor.hero)) then
        local name = entry.ability.name
        rows[#rows + 1] = {lead = TriggerLink(WhyName(name), entry.actor, name), text = T("history.why.trigger_text", {text = triggerText})}
    end

    --The tier lines first: the roll's, then each target that something
    --of its own moved; targets whose lines read the same share one.
    local roll = entry.roll
    if roll ~= nil and roll.overridden ~= nil then
        --the dice did not decide the tier, so the parts that moved it explain nothing.
        rows[#rows + 1] = {text = OverrideWords(roll)}
    elseif roll ~= nil then
        local main, lines = TierLines(roll, targets)
        if main ~= nil then
            rows[#rows + 1] = {lead = T("history.why.lead.tier", {tier = Int(main.tier), qualifier = main.qualifier}), text = main.text}
        end
        for _, line in ipairs(lines) do
            local story = line.story
            Add(string.format("tier|%d|%s|%s", story.tier, story.qualifier, story.text), function(group)
                return {lead = T("history.why.lead.tier_against", {tier = Int(story.tier), names = GroupNames(group), qualifier = story.qualifier}), text = story.text}
            end, line.who)
        end
    end

    --an area ability that hit one of its user's side.
    for _, who in ipairs(targets) do
        if History.IsAllyHit(entry, who) then
            Add("area", function()
                return {lead = T("history.why.lead.area"), text = T("history.why.area")}
            end, who)
            break
        end
    end

    --The damage lines: one sum for what every target that took damage shared, then
    --each target's own parts; targets whose lines read the same share one.
    local damage, damageLines = DamageLines(targets, entry.actor)
    if damage ~= nil then
        Add("damage|shared", function()
            return damage
        end, nil)
    end
    for _, line in ipairs(damageLines) do
        Add(string.format("damage|%d|%s|%s", line.total, line.qualifier, line.text), function(group)
            return {lead = T("history.why.lead.damage_to", {amount = Int(line.total), names = GroupNames(group), qualifier = line.qualifier}), text = line.text}
        end, line.who)
    end

    --a condition the target's immunity stopped.
    for _, who in ipairs(targets) do
        for _, name in ipairs(who.immune or {}) do
            local condition = string.lower(name)
            --the feature that made it immune, named as players could already see it.
            local source = who.immunefrom ~= nil and who.immunefrom[condition] or nil
            if source ~= nil and not PlayersMaySeeAbility(who, source) then
                source = nil
            end
            Add("immune|" .. condition .. "|" .. (source or ""), function(group)
                if source ~= nil then
                    return {
                        lead = WhyName(source),
                        text = #group > 1 and T("history.why.immune_from.other", {names = GroupNames(group), condition = condition})
                            or T("history.why.immune_from.one", {names = GroupNames(group), condition = condition}),
                    }
                end
                return {
                    lead = T("history.why.lead.immune_to", {condition = condition}),
                    text = T("history.why.cannot_be", {names = GroupNames(group), condition = CONDITION_PHRASES[condition] or condition}),
                }
            end, who)
        end
    end

    --what a fall or a collision added to a forced move.
    for _, who in ipairs(targets) do
        local moved = who.moved
        if moved ~= nil then
            local name = History.ShownName(who)
            local fall = moved.falldamage or 0
            if fall > 0 then
                local taken = who.taken or 0
                local total, without = taken, taken - fall
                if moved.fallseparate then
                    total, without = taken + fall, taken
                end
                local squares = moved.fell or 0
                --when the fall is all the damage, comparing it with 0 says nothing.
                local text = without > 0
                    and T("history.why.fall", {amount = Int(fall), total = Int(total), without = Int(without)})
                    or T("history.why.fall_only", {amount = Int(fall)})
                local canShow = g_canDrawPaths and MovedSteps(moved) ~= nil
                if canShow then
                    text = T("history.why.fall_side_view", {words = text})
                end
                Add("fall|" .. who.id, function()
                    return {
                        lead = UIText.Plural("history.why.lead.fell", squares, {count = Int(squares)}),
                        text = text,
                        movers = canShow and {who} or nil,
                    }
                end, who)
            end
            local left = moved.collision or 0
            if left > 0 and (moved.collidedobject or moved.collidedwith ~= nil) then
                local kind = string.lower(string.gsub(moved.kind or "push", "_", " "))
                local squares = UIText.Plural("history.story.squares", left, {count = Int(left)})
                --what the pushed creature's damage reduction took off, on moves saved since History kept it.
                local reduction = moved.collisionreduction or 0
                local reduced = reduction > 0 and (" " .. T("history.why.collision_reduced", {amount = Int(reduction)})) or ""
                Add("collision|" .. who.id, function()
                    if moved.collidedobject or moved.collidedwith == nil then
                        local text
                        if (moved.pushbonus or 0) > 0 and moved.pusher ~= nil then
                            text = T("history.why.hit_object_bonus", {name = name, squares = squares, kind = kind, amount = Int(left),
                                bonus = Int(moved.pushbonus), pusher = History.ShownName(moved.pusher)})
                        else
                            text = T("history.why.hit_object", {name = name, squares = squares, kind = kind, amount = Int(left)})
                        end
                        return {
                            lead = T("history.why.lead.hit_object"),
                            text = text .. reduced,
                        }
                    end
                    local other = History.ShownName(moved.collidedwith)
                    return {
                        lead = T("history.why.lead.hit_creature", {other = other}),
                        text = T("history.why.hit_creature", {name = name, squares = squares, kind = kind, other = other, amount = Int(left)}) .. reduced,
                    }
                end, who)
            end
        end
    end

    --how many minions the damage killed, and why that many.
    for _, kid in ipairs(kids or {}) do
        if kid.family == "minions" and (kid.killed or 0) > 0 and kid.each ~= nil and (kid.damage or 0) > 0 then
            local killed = kid.killed
            local count = killed == 1 and T("history.why.minion_number.1") or (MINION_WORDS[killed] or tostring(killed))
            local known = dmhub.isDM
            if not known and kid.mk ~= nil then
                local knowledge = MonsterKnowledge.StaminaKnowledge(kid.mk, nil)
                known = knowledge.visible and knowledge.tier >= 3
            end
            local text
            if known then
                text = T("history.why.minions_known", {stamina = Int(kid.each), amount = Int(kid.damage), count = count})
            else
                text = killed == 1 and T("history.why.minions_unknown.one", {amount = Int(kid.damage), number = count})
                    or T("history.why.minions_unknown.other", {amount = Int(kid.damage), number = count})
            end
            Add("minions|" .. tostring(kid.id), function()
                return {lead = T("history.why.lead.minions"), text = text}
            end, nil)
        end
    end

    --each potency test, and why it went the way it did. Targets with the same
    --test and outcome share a line.
    for _, who in ipairs(targets) do
        --a condition the target is immune to never landed, whatever the potency did: the
        --immunity line above ("cannot be frightened") says why, so the test gets no line.
        local immuneTo = {}
        for _, name in ipairs(who.immune or {}) do
            immuneTo[string.lower(name)] = true
        end
        for _, test in ipairs(who.potency or {}) do
            if test.what ~= nil and immuneTo[test.what] then
                goto nextTest
            end
            --bare: the phrase without its "being", for the lead players see.
            local phrase, bare = nil, nil
            if test.what ~= nil then
                bare = CONDITION_PHRASES[test.what] or test.what
                phrase = T("history.why.potency.being", {condition = bare})
            elseif test.effect ~= nil then
                phrase = test.effect
                bare = (string.gsub(test.effect, "^being ", ""))
            end
            local hidden = test.mk ~= nil and not dmhub.isDM
                and not MonsterKnowledge.IsRevealed(test.mk, MonsterKnowledge.EntryKey("attr", test.attrid))
            local key = table.concat({"potency", test.letter, tostring(test.gate), tostring(test.resisted), phrase or "",
                hidden and "hidden" or tostring(test.value), tostring(test.surges or "")}, "|")
            Add(key, function(group)
                local names = GroupNames(group)
                local potency = string.format("%s<%d", test.letter, test.gate)
                if hidden then
                    --players don't know the monster's characteristic, only how it went.
                    local lead = bare ~= nil and bare or T("history.why.lead.potency")
                    lead = string.upper(string.sub(lead, 1, 1)) .. string.sub(lead, 2)
                    --the sentence still names who resisted, as the rest of the card does.
                    return {lead = lead, text = test.resisted and T("history.why.potency.hidden_resisted", {names = names})
                        or T("history.why.potency.hidden_not_resisted", {names = names})}
                end
                if test.surges ~= nil and (test.raised or 0) > 0 then
                    --surges raised the potency.
                    local from = string.format("%s<%d", test.letter, test.gate - test.raised)
                    local text
                    if test.resisted then
                        text = T("history.why.potency.raised_resisted", {from = from, potency = potency, names = names})
                    elseif phrase ~= nil then
                        text = T("history.why.potency.raised_not_resisted_what", {from = from, potency = potency, names = names, what = phrase})
                    else
                        text = T("history.why.potency.raised_not_resisted", {from = from, potency = potency, names = names})
                    end
                    return {lead = UIText.Plural("history.why.lead.potency_raised", test.surges, {count = Int(test.surges)}), text = text}
                end
                --the target's characteristic against the potency.
                local text
                if test.resisted then
                    text = T("history.why.potency.resisted", {potency = potency, names = names})
                elseif phrase ~= nil then
                    text = T("history.why.potency.not_resisted_what", {potency = potency, names = names, what = phrase})
                else
                    text = T("history.why.potency.not_resisted", {potency = potency, names = names})
                end
                return {lead = string.format("%s %d", test.attr, test.value), text = text}
            end, who)
            ::nextTest::
        end
    end

    for _, line in ipairs(order) do
        rows[#rows + 1] = line.make(line.who)
    end

    --each trigger this action set off, named so its card shows on hover, and what it did.
    --A resource line saved by an older build has only its small text to name it by.
    local messages = {}
    for _, message in ipairs(entry.messages or {}) do
        messages[#messages + 1] = message
    end
    for _, kid in ipairs(kids or {}) do
        local owner, name = nil, nil
        if kid.kind == "trigger" and kid.ability ~= nil then
            owner, name = kid.actor, kid.ability.name
        elseif kid.family == "resource" and kid.cause ~= nil then
            owner, name = kid.triggerby or kid.who, kid.trigger or kid.causetext
        end
        local effect = name ~= nil and TriggerEffect(kid) or nil
        if name ~= nil and effect ~= nil then
            --some content names a trigger with its whole rule ("Whenever a creature rolls a
            --natural 2 ..."); that reads badly as a lead, so it says "trigger".
            --That plain "trigger" hovers too: that is where its rule shows.
            local triggerName = name
            local lead = TriggerLink(WhyName(name), owner, triggerName)
            if string.find(name, "[%.!?]%s*$") ~= nil or #name > TRIGGER_NAME_MAX then
                lead = TriggerLink(T("history.why.trigger_word_lead"), owner, triggerName)
                name = TriggerLink(T("history.why.trigger_word"), owner, triggerName)
            else
                name = lead
            end
            rows[#rows + 1] = {
                lead = owner ~= nil and T("history.possessive", {owner = History.ShownName(owner), name = name}) or lead,
                who = owner,
                text = T("history.why.triggered_by", {effect = effect}),
            }
        end
        for _, message in ipairs(kid.messages or {}) do
            messages[#messages + 1] = message
        end
    end

    --the notes typed on its steps and its triggers' steps, as written, each once.
    local shown = {}
    for _, message in ipairs(messages) do
        if not shown[message] then
            shown[message] = true
            rows[#rows + 1] = {text = message}
        end
    end
    if #rows > 0 then
        return rows
    end

    --"Nothing changed" only when the roll and the damage are exactly what the tier says.
    --A kit is the hero's normal damage, so it doesn't count as a change.

    --a player doesn't know what changed a roll hidden from them.
    if entry.secretroll then
        return rows
    end
    local acted = roll ~= nil
    local changed = roll ~= nil and ((roll.edges or 0) > 0 or (roll.banes or 0) > 0 or (roll.sources ~= nil and #roll.sources > 0))
    for _, who in ipairs(targets) do
        acted = acted or (who.taken or 0) > 0
        changed = changed or who.roll ~= nil
        for _, part in ipairs(who.parts or {}) do
            changed = changed or part.kind ~= "kit"
        end
    end
    if acted and not changed then
        rows[1] = {plain = true, text = T("history.why.nothing_changed")}
    end
    return rows
end

--One Why line: its lead in bold (after a modifier owner's face) over its sentence, with a
--thin rule down the left.
--- @param row HistoryWhyRow
local function WhyRow(row, width)
    local inner = width - WHY_INDENT
    local children = {}
    if row.lead ~= nil then
        local lead = {}
        if row.who ~= nil then
            local face = History.Face(row.who, 20, true)
            face.selfStyle.rmargin = 6
            face.selfStyle.halign = "left"
            lead[1] = face
        end
        lead[#lead + 1] = gui.Label(Linked{
            classes = {"historyWhyLead"},
            text = row.lead,
            width = "auto",
            maxWidth = inner - (row.who ~= nil and 24 or 0),
            height = "auto",
            halign = "left",
            valign = "center",
        })
        --the move's side view, the same button the creature's What happened line has.

        if row.movers ~= nil then
            lead[#lead + 1] = SideViewButton({who = row.movers}, g_linkMap)
        end
        children[1] = gui.Panel{
            flow = "horizontal",
            width = inner,
            height = "auto",
            halign = "left",
            children = lead,
        }
    end
    children[#children + 1] = gui.Label(Linked{
        classes = {row.plain and "historyWhyPlain" or "historyWhyText"},
        text = row.text,
        width = inner,
        height = "auto",
        halign = "left",
        textAlignment = "left",
    })
    return gui.Panel{
        classes = {"historyWhy", row.plain and "historyWhyQuiet" or nil},
        bgimage = "panels/square.png",
        border = {x1 = 2, y1 = 0, x2 = 0, y2 = 0},
        flow = "vertical",
        width = width,
        height = "auto",
        lpad = WHY_INDENT - 2,
        tpad = 2,
        bpad = 4,
        bmargin = 6,
        borderBox = true,
        halign = "left",
        children = children,
    }
end

--- One row of the Sidebar Preview: what an action or line did, for the chat bubble beside
--- the History button. An action has a header over up to two of its sentences and "and 3
--- more"; a line is its sentence alone. Your creatures' sentences carry the gold edge, as
--- in the hover card.
--- @param args {title: string|nil, rows: {row: table, mine: boolean}[], width: number}
--- @return Panel[]
function History.CreateBubbleContents(args)
    local shown = math.min(#args.rows, 2)
    local body = {}
    if args.title ~= nil then
        --the chat bubble's name style, so it reads like a message's sender.
        body[#body + 1] = gui.Label{
            classes = {"chatBubbleNick"},
            text = args.title,
            interactable = false,
        }
    end
    for i = 1, shown do
        local item = args.rows[i]
        body[#body + 1] = gui.Panel{
            flow = "horizontal",
            width = args.width,
            height = "auto",
            tmargin = 2,
            gui.Panel{
                classes = {cond(item.mine, "historyActiveFrame", nil)},
                bgimage = "panels/square.png",
                bgcolor = cond(item.mine, nil, "#00000000"),
                width = 3,
                height = STORY_FACE,
                valign = "top",
                tmargin = 3,
                rmargin = 6,
            },
            StoryRow(item.row, args.width - 9),
        }
    end
    if #args.rows > shown then
        body[#body + 1] = gui.Label{
            classes = {"historyCardMeta"},
            text = T("history.bubble.and_more", {count = Int(#args.rows - shown)}),
            width = args.width,
            height = "auto",
            tmargin = 2,
            textAlignment = "left",
        }
    end
    --History's own styles for the story rows; the bubble's (chatBubbleNick) still reach in.
    return {
        gui.Panel{
            styles = ThemeEngine.MergeStyles(History.Styles()),
            flow = "vertical",
            width = "auto",
            height = "auto",
            interactable = false,
            children = body,
        },
    }
end

--- The rail button's hover card: what happened since you last looked, in the

--- detail card's frame and rows. Rows about your own creatures carry a gold edge.
--- @param args {rows: {row: table, mine: boolean}[], more: integer, width: number}
--- @return Panel
function History.CreateSinceCard(args)
    local inner = args.width - 2 * CARD_PAD
    local body = {}
    for _, item in ipairs(args.rows) do
        --the edge is a fixed height: "100%" of an auto-height row grows to fill the screen.
        body[#body + 1] = gui.Panel{
            flow = "horizontal",
            width = inner,
            height = "auto",
            gui.Panel{
                classes = {cond(item.mine, "historyActiveFrame", nil)},
                bgimage = "panels/square.png",
                bgcolor = cond(item.mine, nil, "#00000000"),
                width = 3,
                height = STORY_FACE,
                valign = "top",
                tmargin = 3,
                rmargin = 6,
            },
            StoryRow(item.row, inner - 9),
        }
    end
    if args.more > 0 then
        body[#body + 1] = gui.Label{
            classes = {"historyCardMeta"},
            text = UIText.Plural("history.since.more_turns", args.more, {count = Int(args.more)}),
            width = inner,
            height = "auto",
            tmargin = 6,
            textAlignment = "left",
        }
    end
    body[#body + 1] = gui.Label{
        classes = {"historyCardMeta"},
        text = T("history.since.click_to_open"),
        width = inner,
        height = "auto",
        tmargin = 8,
        textAlignment = "left",
    }

    return gui.Panel{
        classes = {"historyCardFrame"},
        styles = ThemeEngine.MergeStyles(History.Styles()),
        bgimage = true,
        blurBackground = true,
        flow = "vertical",
        width = args.width,
        height = "auto",
        interactable = false,
        gui.Label{
            classes = {"historyCardTitle"},
            text = T("history.since.title"),
            width = "100%",
            height = "auto",
            lpad = CARD_PAD,
            tpad = 10,
            bpad = 9,
            borderBox = true,
            textAlignment = "left",
        },
        gui.Panel{
            classes = {"historySeam"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
        },
        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            hpad = CARD_PAD,
            tpad = 8,
            bpad = 12,
            borderBox = true,
            children = body,
        },
    }
end

--- Builds the card for one row. It is rebuilt to change it: the sections have a different
--- shape for every action, and a scroll bar only works if it is there on its first frame.
--- tail is the card's edge that faces History ("left" or "right"). The tail comes back in
--- card.data.tail, not attached: the caller adds it to the card's parent BEFORE the card, so
--- the card hides its inner half, and moves it to the row. None inside the window.
--- @param args {entry: HistoryEntry, kids: HistoryEntry[]|nil, x: number, width: number, maxHeight: number, inTray: boolean, tail: "left"|"right"|nil, close: function}
--- @return Panel
function History.CreateCard(args)
    local entry = args.entry
    g_cardSide = (args.tail == "left" and "right") or (args.tail == "right" and "left") or nil
    local width = args.width
    local inner = width - 2 * CARD_PAD

    --a test or Dice panel line's card is only its numbers: the line already says what happened.
    local rolled = entry.family == "test" or entry.family == "dice" or entry.family == "table"
    local body = {}
    if not rolled then
        body[1] = SectionHead(T("history.card.section.what_happened"), WHAT_HAPPENED_WIDTH, inner)
        for _, row in ipairs(History.Story(entry, args.kids)) do
            body[#body + 1] = StoryRow(row, inner, entry.map)
        end
        local why = History.Why(entry, args.kids)
        if #why > 0 then
            body[#body + 1] = SectionHead(T("history.card.section.why"), WHY_WIDTH, inner)
            for _, row in ipairs(why) do
                body[#body + 1] = WhyRow(row, inner)
            end
        end
    end
    if entry.kind == "action" or rolled then
        local numbers = NumbersRows(entry, args.kids, inner)
        if #numbers > 0 then
            body[#body + 1] = SectionHead(T("history.card.section.the_numbers"), THE_NUMBERS_WIDTH, inner)
            for _, row in ipairs(numbers) do
                body[#body + 1] = row
            end
        end
    end
    local footer = FooterWords(entry)
    if footer ~= nil then
        body[#body + 1] = gui.Label{
            classes = {"historyCardMeta"},
            text = footer,
            width = inner,
            height = "auto",
            tmargin = 10,
            textAlignment = "left",
        }
    end

    --- @type Panel|nil
    local tail = nil
    if args.tail ~= nil then
        --a square turned 45 degrees, centred on the card's edge: the half outside is the point.
        tail = gui.Panel{
            classes = {"historyCardTail"},
            bgimage = "panels/square.png",
            floating = true,
            width = TAIL_SIZE,
            height = TAIL_SIZE,
            rotate = 45,
            halign = "left",
            valign = "top",
            x = cond(args.tail == "left", args.x, args.x + width) - TAIL_SIZE / 2,
            interactable = false,
        }
    end

    local header = Header(entry, width, args.inTray, args.close)

    return gui.Panel{
        classes = {"historyCardFrame", cond(args.inTray, "historyCardSolid", nil)},
        bgimage = true,
        --beside the window, Transparent UI shows the map through it as through the rail
        --windows; over the list it is solid, or the rows would show through.
        blurBackground = not args.inTray,
        floating = true,
        flow = "vertical",
        x = args.x,
        width = width,
        height = cond(args.inTray, args.maxHeight, "auto"),
        halign = "left",
        valign = "top",
        data = {tail = tail},

        header,
        gui.Panel{
            classes = {"historySeam"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
        },
        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            --a one-line header's height to start; a title that wraps makes the header taller,
            --so once it is laid out the body gets what is really left.
            maxHeight = args.maxHeight - 62,
            create = function(element)
                gui.AfterLayout(function()
                    if element.valid and header.valid and (header.renderedHeight or 0) > 0 then
                        element.selfStyle.maxHeight = args.maxHeight - header.renderedHeight - 1
                    end
                end)
            end,
            vscroll = true,
            gui.Panel{
                flow = "vertical",
                width = "100%",
                height = "auto",
                hpad = CARD_PAD,
                bpad = 12,
                borderBox = true,
                children = body,
            },
        },
    }
end
