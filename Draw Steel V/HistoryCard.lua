local mod = dmhub.GetModLoading()

--The detail card: what a row in the History tray did, one click from that row. This file
--holds what the card says and draws it; the tray decides where it sits. The sentences
--are the wordings in docs/action-log-design/COPY.md (N2 and the L lines), worked out from
--the entry when the card opens, so none of this runs during play.

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

--The coloured edge down the card's left side, which ties it to the selected row.

local STORY_FACE = 24
local STORY_GAP = 9

--Room kept at the end of a story row for its number.
local STORY_NUMBER_WIDTH = 44

--Room kept beside a sentence for an Ended tag.
local ENDED_TAG_WIDTH = 60

--The single guillemet is in the Codex's fonts (L34); Lua source stays ASCII.
local BACK_TEXT = "\226\128\185 Back"

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
    ["save ends"] = " (save ends)",
    EoT = " until the end of its turn",
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
    return string.format("%s %s %s", table.concat(most, ", "), last or "and", words[#words])
end

local function Squares(count)
    return string.format("%d %s", count, cond(count == 1, "square", "squares"))
end

--The type of damage that is all one type, else nil.
local function SingleType(who)
    local only = next(who.types or {})
    if only == nil or next(who.types, only) ~= nil or who.types[only] < who.taken then
        return nil
    end
    return only
end

--"took 5 damage" (W1), "took 5 fire damage" (W2) or "took 8 damage: 4 fire and 4 cold"
--(W3). True second means the words end on a list, so nothing can follow them with "and".
local function DamageWords(who)
    local only = SingleType(who)
    if only ~= nil then
        return string.format("took %d %s damage", who.taken, only), false
    end
    if who.types == nil or next(who.types) == nil then
        return string.format("took %d damage", who.taken), false
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
        parts[i] = string.format("%d %s", who.types[name], name)
    end
    if typed < who.taken then
        parts[#parts + 1] = string.format("%d untyped", who.taken - typed)
    end
    return string.format("took %d damage: %s", who.taken, JoinWords(parts)), true
end

--- True when an area ability hit a creature on its user's side (W11, T13).
--- @param entry HistoryEntry
--- @param who HistoryCreature
--- @return boolean
function History.IsAllyHit(entry, who)
    local actor = entry.actor
    return actor ~= nil and entry.ability ~= nil and entry.ability.area == true
        and (who.taken or 0) > 0 and who.id ~= actor.id and who.hero == actor.hero
end

--What moved it. A push, a fall or both: the fall reads "it fell" (W15, D9).
--afterDamage: it follows a colon, so it needs no "was".
local function MovedWords(moved, afterDamage)
    local verb = History.MOVED_VERBS[string.gsub(moved.kind, "vertical_", "")] or "moved"
    if moved.distance <= 0 then
        return string.format("fell %s", Squares(moved.fell))
    end
    local words = string.format("%s %s", verb, Squares(moved.distance))
    if moved.fell > 0 then
        words = string.format("%s, it fell %s", words, Squares(moved.fell))
    end
    return afterDamage and words or ("was " .. words)
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
        splitLead = split
        if who.soaked ~= nil then
            words = string.format("%s, %d of it to temporary Stamina", words, who.soaked)
        end
        if isAlly then
            words = "was caught in the area and " .. words
        end
        verbs[1] = words
    end
    if (who.healed or 0) > 0 then
        verbs[#verbs + 1] = string.format("regained %d Stamina", who.healed)
    end

    local moved = who.moved
    if moved ~= nil then
        if moved.distance > 0 and moved.fell > 0 and #verbs == 1 and (who.taken or 0) > 0 and not splitLead then
            verbs[1] = string.format("%s: %s", verbs[1], MovedWords(moved, true))
            splitLead = true
        else
            verbs[#verbs + 1] = MovedWords(moved, false)
        end
    end
    if who.landedon then
        verbs[#verbs + 1] = "was landed on"
    end

    local adjectives = {}
    if who.state == "winded" or who.state == "dying" then
        adjectives[1] = "now " .. who.state
    end
    for _, condition in ipairs(who.conds or {}) do
        local duration = DURATION_PHRASES[condition.duration] or ""
        if condition.iscondition then
            adjectives[#adjectives + 1] = string.lower(condition.name) .. duration
        else
            verbs[#verbs + 1] = string.format("gained %s%s", condition.name, duration)
        end
    end
    if #adjectives > 0 then
        verbs[#verbs + 1] = "is " .. JoinWords(adjectives)
    end
    if who.state == "killed" then
        verbs[#verbs + 1] = "was killed"
    end
    if type(who.resisted) == "string" then
        verbs[#verbs + 1] = string.format("resisted being %s", who.resisted)
    elseif who.resisted then
        verbs[#verbs + 1] = "resisted"
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
            notes[#notes + 1] = name .. " ended"
        end
    end
    if #noLonger > 0 then
        verbs[#verbs + 1] = "is no longer " .. JoinWords(noLonger, "or")
    end
    if who.pool ~= nil then
        notes[#notes + 1] = string.format("temporary Stamina went from %d to %d", who.pool.before, who.pool.after)
    end

    local words = nil
    if #verbs == 0 then
        if #notes > 0 then
            words = string.format("'s %s.", JoinWords(notes))
        end
    elseif splitLead then
        words = string.format(" %s.", table.remove(verbs, 1))
        if #verbs > 0 then
            words = string.format("%s It %s.", words, JoinWords(verbs))
        end
        if #notes > 0 then
            words = string.format("%s %s.", words, string.upper_first(JoinWords(notes)))
        end
    else
        for _, note in ipairs(notes) do
            verbs[#verbs + 1] = note
        end
        words = string.format(" %s.", JoinWords(verbs))
    end

    if who.immune ~= nil then
        local immune = JoinWords(who.immune, "or")
        if words == nil then
            words = string.format(" was not %s.", immune)
        else
            words = string.format("%s It was not %s.", words, immune)
        end
    end
    if words ~= nil and isAlly then
        words = ", an ally," .. words
    end
    return words
end

--"Goblin 1-4" when names differ only by a run of numbers (L30), else a list (L29).
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
        if numbers[#numbers] - numbers[1] == #numbers - 1 then
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
    return GroupNames(row.who) .. " each" .. row.words
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

--Adds a creature's row, or joins a row with the same result (L29). Words that start with
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
        if kid.family == "minions" then
            local death = deaths[kid.name]
            if death == nil then
                death = {killed = 0, total = 0, left = 0, who = kid.who}
                deaths[kid.name] = death
            end
            death.killed = death.killed + kid.killed
            death.total = math.max(death.total, kid.killed + kid.left)
            death.left = kid.left
        end
    end
    return deaths
end

--"1 of 4 minions killed" or "the squad is destroyed" (W9).
local function DeathWords(death)
    if death.left <= 0 then
        return "the squad is destroyed"
    end
    return string.format("%d of %d minions killed", death.killed, death.total)
end

--A squad reads as one creature: what it took together, then who that killed (W9). What
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
        name = "Unknown creature"
    end
    local text = nil
    if whole.taken > 0 then
        local words, split = DamageWords(whole)
        text = string.format("%s %s", name, words)
        if death ~= nil and split then
            text = string.format("%s. %s", text, string.upper_first(DeathWords(death)))
        elseif death ~= nil then
            text = string.format("%s: %s", text, DeathWords(death))
        end
        text = text .. "."
    elseif death ~= nil then
        text = string.format("%s %s.", name, DeathWords(death))
    end

    if isShared and shared ~= nil and string.sub(shared, 1, 1) == " " then
        if text ~= nil then
            text = string.format("%s The squad%s", text, shared)
        else
            text = string.format("The squad%s", shared)
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

--What a nested trigger did (W13), or a resource it changed (W14, D5).
local function AddKid(rows, kid)
    if kid.family == "resource" then
        local verb = cond(kid.amount > 0, "gained", "spent")
        rows[#rows + 1] = {
            who = {kid.who},
            text = string.format("%s %s %s.", History.ShownName(kid.who), verb,
                History.ResourceWords(math.abs(kid.amount), kid.name)),
        }
        return
    end
    if kid.kind ~= "trigger" then
        return
    end

    local owner = kid.ability.name
    if kid.actor ~= nil then
        owner = string.format("%s's %s", History.ShownName(kid.actor), kid.ability.name)
    end
    for _, who in ipairs(kid.targets) do
        local name = History.ShownName(who)
        if OnlyDamage(who) and (who.types == nil or SingleType(who) ~= nil) then
            local damagetype = SingleType(who)
            rows[#rows + 1] = {
                who = {who},
                text = string.format("%s then hit %s for %d %sdamage.", owner, name, who.taken,
                    damagetype ~= nil and (damagetype .. " ") or ""),
                amount = -who.taken,
            }
        else
            local words = Predicate(who)
            if words ~= nil then
                rows[#rows + 1] = {
                    who = {who},
                    text = string.format("%s: %s%s", owner, name, words),
                    amount = LandedAmount(who),
                }
            end
        end
    end
end

--- What happened, one row per creature, the result first (COPY N2).
--- @param entry HistoryEntry An action, or the closing line of an encounter.
--- @param kids? HistoryEntry[] What is nested under it.
--- @return HistoryStoryRow[]
function History.Story(entry, kids)
    local rows = {}
    if entry.family == "encounterend" then
        for _, item in ipairs(entry.ended or {}) do
            rows[#rows + 1] = {
                who = {item.who},
                text = string.format("%s %s", History.ShownName(item.who), JoinWords(item.names)),
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

    --a trigger can finish off a squad this action never touched (L22).
    for name, death in pairs(deaths) do
        rows[#rows + 1] = {
            who = death.who ~= nil and {death.who} or {},
            text = string.format("%s %s.", name, DeathWords(death)),
        }
    end
    for _, kid in ipairs(kids) do
        AddKid(rows, kid)
    end

    if #rows == 0 and entry.actor ~= nil then
        rows[1] = {
            who = {entry.actor},
            text = string.format("%s used %s.", History.ShownName(entry.actor), entry.ability.name),
        }
    end
    return rows
end

--"Main action - Round 2, turn 13" (C1), whichever parts this entry has.
local function MetaWords(entry)
    local parts = {}
    local action = entry.ability ~= nil and History.ACTION_WORDS[entry.ability.action] or nil
    if action ~= nil then
        parts[1] = action
    end
    if entry.round ~= nil and entry.turn ~= nil then
        parts[#parts + 1] = string.format("Round %d, turn %d", entry.round, entry.turn)
    elseif entry.round ~= nil then
        parts[#parts + 1] = string.format("Round %d", entry.round)
    end
    return table.concat(parts, History.DOT)
end

--"Rolled by Ana - 8:33 pm" (C6). Only an action has someone behind it.
local function FooterWords(entry)
    if entry.kind ~= "action" then
        return nil
    end
    local time = string.lower(dmhub.FormatTimestamp(entry.t, "h:mm tt"))
    if entry.player == nil then
        return "Director" .. History.DOT .. time
    end
    if entry.roll ~= nil then
        return string.format("Rolled by %s%s%s", entry.player, History.DOT, time)
    end
    return entry.player .. History.DOT .. time
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

    local title = "Encounter ended"
    if entry.actor ~= nil then
        children[#children + 1] = History.Face(entry.actor, 30)
        titleWidth = titleWidth - 39
        title = History.ShownName(entry.actor) .. History.DOT .. entry.ability.name
    end
    children[#children + 1] = gui.Panel{
        flow = "vertical",
        width = titleWidth,
        height = "auto",
        lmargin = entry.actor ~= nil and 9 or 0,
        halign = "left",
        valign = "center",
        gui.Label{
            classes = {"historyCardTitle"},
            text = title,
            width = "100%",
            height = "auto",
            textAlignment = "left",
        },
        gui.Label{
            classes = {"historyCardMeta"},
            text = MetaWords(entry),
            width = "100%",
            height = "auto",
            textAlignment = "left",
        },
    }
    children[#children + 1] = gui.Panel{
        classes = {"historyCardClose"},
        bgimage = "window-chrome/chrome-close.png",
        width = 12,
        height = 12,
        hmargin = 5,
        halign = "right",
        valign = "center",
        linger = gui.Tooltip{text = "Close the detail", fontSize = 13},
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

local function StoryRow(row, width)
    local textWidth = width
    if row.amount ~= nil then
        textWidth = textWidth - STORY_NUMBER_WIDTH
    end

    local left = {}
    if row.who[1] ~= nil then
        local face = History.Face(row.who[1], STORY_FACE)
        face.selfStyle.valign = "top"
        left[1] = face
        textWidth = textWidth - STORY_FACE - STORY_GAP
    end
    left[#left + 1] = gui.Label{
        classes = {"historyStory"},
        text = History.StoryText(row),
        width = row.ended and "auto" or textWidth,
        maxWidth = row.ended and (textWidth - ENDED_TAG_WIDTH) or nil,
        height = "auto",
        lmargin = #left > 0 and STORY_GAP or 0,
        halign = "left",
        valign = "top",
        textAlignment = "left",
    }
    if row.ended then
        left[#left + 1] = History.Tag("historyEndedTag", "Ended")
    end

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

--The numbers (2.2): the prototype's receipt. One fact per line, every number in one column
--on the right, each total under a line, in the order things resolved: the roll, then each
--target, then triggers and costs. Wordings are COPY.md C3, C4 and Z1-Z7.

--A signed number. A plain "-": the bold font has no minus sign.
local function Signed(value)
    if value < 0 then
        return string.format("-%d", -value)
    end
    return string.format("+%d", value)
end

--Edges and banes as the rules net them: up to two of each count, then they cancel one for
--one (Heroes book; GetRollModFromEdgesAndBanes agrees). Nil when there are none.
--- @return {label: string, value: string, side: string|nil, count: integer, note: string|nil, aside: string|nil}|nil
local function NetEdges(edges, banes)
    edges, banes = edges or 0, banes or 0
    if edges == 0 and banes == 0 then
        return nil
    end
    local e, b = math.min(edges, 2), math.min(banes, 2)
    local net
    if b == 0 then
        net = e == 1 and {label = "Edge", value = "+2", side = "edge", count = 1}
            or {label = "Double edge", value = "+1 tier", side = "edge", count = 2}
    elseif e == 0 then
        net = b == 1 and {label = "Bane", value = "-2", side = "bane", count = 1}
            or {label = "Double bane", value = "-1 tier", side = "bane", count = 2}
    elseif e > b then
        net = {label = "Edge", value = "+2", side = "edge", count = 1}
    elseif e < b then
        net = {label = "Bane", value = "-2", side = "bane", count = 1}
    else
        net = {label = "Cancelled out", value = "0", count = 0}
    end

    if e == 2 and b == 1 then
        net.note = "A maximum of two edges count (a double edge); with one bane, the roll is made with one edge."
    elseif b == 2 and e == 1 then
        net.note = "A maximum of two banes count (a double bane); with one edge, the roll is made with one bane."
    elseif e > 0 and e == b then
        net.note = "Edges and banes cancel out: the roll is made without either."
    elseif edges > 2 then
        net.note = "A maximum of two edges count (a double edge)."
    elseif banes > 2 then
        net.note = "A maximum of two banes count (a double bane)."
    end

    if edges + banes > 1 then
        local parts = {}
        if edges > 0 then
            parts[#parts + 1] = string.format("%d %s", edges, edges == 1 and "edge" or "edges")
        end
        if banes > 0 then
            parts[#parts + 1] = string.format("%d %s", banes, banes == 1 and "bane" or "banes")
        end
        net.aside = "(" .. table.concat(parts, ", ") .. ")"
    end
    return net
end

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
--- @param args {label: string|nil, lead: Panel[]|nil, aside: string|nil, badge: integer|nil, value: string|nil, valueClass: string|nil, labelClass: string|nil, total: boolean|nil, struck: boolean|nil}
local function ReceiptLine(width, args)
    local left = {}
    for _, panel in ipairs(args.lead or {}) do
        left[#left + 1] = panel
    end
    if args.label ~= nil then
        local classes = {"historyReceipt"}
        classes[#classes + 1] = args.labelClass
        classes[#classes + 1] = args.struck and "historyStruck" or nil
        left[#left + 1] = gui.Label{
            classes = classes,
            text = args.label,
            width = "auto",
            maxWidth = width - VALUE_WIDTH - 8,
            height = "auto",
            halign = "left",
            valign = "center",
        }
    end
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
        local face = History.Face(who, 18)
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

--What a tier modifier did, for its value in The numbers (Z8); nil for a source that only
--gave or took edges and banes.
--- @param source HistoryEdgeSource
--- @return string|nil
local function TierValue(source)
    if source.autosuccess then
        return "Tier 3"
    elseif source.autofailure then
        return "Tier 1"
    elseif (source.tiers or 0) ~= 0 then
        local count = math.abs(source.tiers)
        return string.format("%s%d %s", source.tiers > 0 and "+" or "-", count, count == 1 and "tier" or "tiers")
    elseif source.nottierthree then
        return "not Tier 3"
    elseif source.nottierone then
        return "not Tier 1"
    end
    return nil
end

--A source as the roll dialog named it: "Prone", "Reactor 1's Test 5", "Set by hand".
--- @param source HistoryEdgeSource
--- @return string
local function SourceText(source)
    if source.hand then
        return "Set by hand"
    end
    local text = SpoilerName(source.name)
    if source.who ~= nil then
        text = string.format("%s's %s", History.ShownName(source.who), text)
    end
    return text
end

--"Ignored by Twisted" (C5r): what took a side's edges or banes away. Several removers
--share one reason.
--- @param sources HistoryEdgeSource[]
--- @param side "edge"|"bane"
--- @return string|nil
local function RemovedReason(sources, side)
    local field = side == "edge" and "removedEdges" or "removedBanes"
    local parts = {}
    for _, source in ipairs(sources) do
        if (source[field] or 0) > 0 then
            parts[#parts + 1] = string.format(source.ignore and "ignored by %s" or "removed by %s", SourceText(source))
        end
    end
    if #parts == 0 then
        return nil
    end
    local reason = table.concat(parts, ", ")
    return string.upper(string.sub(reason, 1, 1)) .. string.sub(reason, 2)
end

--One thing that changed the roll's edges or banes, under the line it changed (C5): its
--arrows, its owner's face, and its name as the roll dialog showed it.
--- @param source HistoryEdgeSource
--- @param side "edge"|"bane"
--- @param struck? boolean Everything it gave was taken away: crossed out, the reason is on the line above.
--- @param remover? boolean The line for a source that took one of several away ("Removed by", C5r).
local function SourceLine(width, source, side, struck, remover)
    local children = {}
    if remover then
        --no arrows, so the words line up with the names above.
        children[1] = gui.Panel{width = 14, height = 14, rmargin = 5, halign = "left", valign = "center", interactable = false}
    else
        children[1] = Chevrons(side, math.min((side == "edge" and source.edges or source.banes) or 0, 2))
    end
    if source.who ~= nil and not source.hand then
        local face = History.Face(source.who, 18)
        face.selfStyle.rmargin = 6
        face.selfStyle.halign = "left"
        children[#children + 1] = face
    end
    local text = SourceText(source)
    if remover then
        text = string.format(source.ignore and "Ignored by %s" or "Removed by %s", text)
    end
    children[#children + 1] = gui.Label{
        classes = {remover and "historyReceiptAside" or "historyReceiptSource", struck and "historyStruck" or nil},
        text = text,
        width = "auto",
        maxWidth = width - SOURCE_INDENT - 48,
        height = "auto",
        halign = "left",
        valign = "center",
    }
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

--A side that lost every edge or bane keeps its line (C5i), crossed out with what it would
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
        label = label .. " for this target"
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

--The net edge or bane line, what gave it each edge and bane (edges first), then the rule
--note. A side that was ignored entirely gets its own line, edges before the net line and
--banes after it.
--- @param sources HistoryEdgeSource[]|nil
local function AddEdgeLines(rows, width, edges, banes, forTarget, sources)
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
    if net ~= nil then
        local label = net.label
        if forTarget and net.side ~= nil then
            label = label .. " for this target"
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

    --Z8: each tier modifier after the edges and banes, a trigger's with its owner's face.
    for _, source in ipairs(sources) do
        local value = TierValue(source)
        if value ~= nil then
            local lead = nil
            if source.who ~= nil and not source.hand then
                local face = History.Face(source.who, 18)
                face.selfStyle.rmargin = 6
                face.selfStyle.halign = "left"
                lead = {face}
            end
            rows[#rows + 1] = ReceiptLine(width, {lead = lead, label = SourceText(source), value = value})
        end
    end
end

--"Damage immunity 2", "Fire immunity 3", "Fire weakness 3" (Z5).
local function ResistWords(immunity)
    local typeWord = immunity.damagetype == "damage" and "Damage"
        or (string.upper(string.sub(immunity.damagetype, 1, 1)) .. string.sub(immunity.damagetype, 2))
    if immunity.amount > 0 then
        return string.format("%s immunity %d", typeWord, immunity.amount)
    end
    return string.format("%s weakness %d", typeWord, -immunity.amount)
end

--One thing besides the tier that made a target's damage (COPY.md Round 10): a kit (K1), a
--roll dialog modifier named as its badge (K2, a trigger's owner with a face) or surges
--(C3s, behind the roll dialog's surge bolt).
--- @param part HistoryDamagePart
local function DamagePartLine(width, part)
    if part.kind == "kit" then
        return ReceiptLine(width, {label = string.format("%s kit", part.name or ""), value = Signed(part.amount)})
    end
    if part.kind == "surge" then
        local count = part.count or 0
        local aside = nil
        if part.characteristic ~= nil then
            aside = string.format(count == 1 and "(%s %d)" or "(%s %d each)", part.characteristic, part.each or 0)
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
            label = count == 1 and "Spent 1 surge" or string.format("Spent %d surges", count),
            aside = aside,
            value = Signed(part.amount),
        })
    end
    local lead = nil
    local text = SpoilerName(part.name or "")
    if part.who ~= nil then
        local face = History.Face(part.who, 18)
        face.selfStyle.rmargin = 6
        face.selfStyle.halign = "left"
        lead = {face}
        text = string.format("%s's %s", History.ShownName(part.who), text)
    end
    return ReceiptLine(width, {lead = lead, label = text, value = Signed(part.amount)})
end

--One target's sum: its own roll if it had one, what the tier dealt, what changed it, and
--what landed. count > 1 for numbered creatures that all got the same.
local function AddTargetLines(rows, width, entry, who, count)
    if who.roll ~= nil then
        AddEdgeLines(rows, width, who.roll.edges, who.roll.banes, true, who.roll.sources)
        rows[#rows + 1] = ReceiptLine(width, {label = "Their roll", badge = who.tier, value = tostring(who.roll.total), total = true})
    end
    --what dealt it: the tier against this target, or the ability when nothing was rolled.
    local source = (who.tier ~= nil and who.tier > 0) and string.format("Tier %d", who.tier) or entry.ability.name

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

        --the kit, modifiers and surges come off the line of the type they added to (2.3b),
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

        local first = true
        local function Dealt(label, raw)
            rows[#rows + 1] = ReceiptLine(width, {label = label, value = first and tostring(raw) or Signed(raw)})
            first = false
        end
        for _, name in ipairs(typeNames) do
            Dealt(string.format("%s: %s", source, name), base[name])
        end
        if base.untyped ~= nil then
            Dealt(source, base.untyped)
        end
        for _, part in ipairs(parts) do
            rows[#rows + 1] = DamagePartLine(width, part)
        end
        if changed ~= 0 then
            rows[#rows + 1] = ReceiptLine(width, {label = ResistWords(immunity), value = Signed(-changed)})
        end
        rows[#rows + 1] = ReceiptLine(width, {
            label = count > 1 and "Taken, each" or "Taken",
            value = tostring(taken),
            valueClass = "historyHurt",
            total = true,
        })
    end

    local healed = who.healed or 0
    if healed > 0 then
        rows[#rows + 1] = ReceiptLine(width, {label = source, value = tostring(healed)})
        rows[#rows + 1] = ReceiptLine(width, {label = "Regained", value = tostring(healed), valueClass = "historyHealed", total = true})
    end
end

--Targets with the same numbers share one sum ("Goblin 1-4", "Taken, each").
local function ReceiptKey(who)
    if (who.taken or 0) == 0 and (who.healed or 0) == 0 and who.roll == nil then
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
            names[#names + 1] = string.format("%s%s/%d/%d/%d/%d/%s", source.name, source.who ~= nil and source.who.id or "",
                source.edges or 0, source.banes or 0, source.removedEdges or 0, source.removedBanes or 0, TierValue(source) or "")
        end
        roll = string.format("%d/%d/%d/%s", who.roll.edges or 0, who.roll.banes or 0, who.roll.total, table.concat(names, ","))
    end
    local parts = {}
    for _, part in ipairs(who.parts or {}) do
        parts[#parts + 1] = string.format("%s/%s/%s/%d/%s", part.kind, part.name or "", part.who ~= nil and part.who.id or "",
            part.amount, part.damagetype or "")
    end
    return string.format("%s|%d|%d|%s|%s|%s|%s", tostring(who.tier), who.taken or 0, who.healed or 0, table.concat(types, ","), immunity, roll,
        table.concat(parts, ","))
end

--- The receipt's rows for an action entry; empty when it has nothing to add up.
--- @param entry HistoryEntry
--- @param kids HistoryEntry[]|nil
--- @param width number
--- @return Panel[]
local function NumbersRows(entry, kids, width)
    local rows = {}
    local targets = entry.targets or {}

    local roll = entry.roll
    if roll ~= nil then
        rows[#rows + 1] = SubHead("Power roll", width)
        if roll.natural ~= nil and roll.low ~= nil and roll.high ~= nil then
            rows[#rows + 1] = ReceiptLine(width, {lead = {Die(roll.low), Die(roll.high)}, value = tostring(roll.natural)})
            if roll.characteristic ~= nil then
                rows[#rows + 1] = ReceiptLine(width, {label = roll.characteristic.name, value = Signed(roll.characteristic.value)})
            end
            if roll.bonus ~= nil then
                rows[#rows + 1] = ReceiptLine(width, {label = "Bonus", value = Signed(roll.bonus)})
            end
        end
        AddEdgeLines(rows, width, roll.edges, roll.banes, false, roll.sources)
        --the tier of the roll itself: a target with edges or banes of its own got another.
        local tier = roll.tier
        for _, who in ipairs(targets) do
            if who.roll == nil and who.tier ~= nil then
                tier = who.tier
                break
            end
        end
        rows[#rows + 1] = ReceiptLine(width, {label = "Total", badge = tier, value = tostring(roll.total), total = true})
    end

    local groups = {}
    local byKey = {}
    for _, who in ipairs(targets) do
        local key = ReceiptKey(who)
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
        AddTargetLines(rows, width, entry, group[1], #group)
    end

    local triggered = {}
    for _, kid in ipairs(kids or {}) do
        if kid.kind == "trigger" and kid.actor ~= nil then
            local net = 0
            for _, who in ipairs(kid.targets or {}) do
                net = net - (who.taken or 0) + (who.healed or 0)
            end
            if net ~= 0 then
                local face = History.Face(kid.actor, 18)
                face.selfStyle.rmargin = 6
                face.selfStyle.halign = "left"
                triggered[#triggered + 1] = ReceiptLine(width, {
                    lead = {face},
                    label = History.ShownName(kid.actor) .. History.DOT .. kid.ability.name,
                    value = Signed(net),
                    valueClass = cond(net < 0, "historyHurt", "historyHealed"),
                })
            end
        end
    end
    if #triggered > 0 then
        rows[#rows + 1] = SubHead("Triggered", width)
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
            rows[#rows + 1] = ReceiptNote(width, "Cost: " .. History.ResourceWords(entry.costs[name].amount, name), "historyReceiptMore")
        end
    end
    return rows
end

--- One line of the card's Why (COPY.md R1, Round 11): a bold lead, then one plain sentence.
--- @class HistoryWhyRow
--- @field lead string|nil
--- @field text string
--- @field who HistoryCreature|nil A face before the lead: the owner of a modifier.
--- @field plain boolean|nil G6, muted, with no lead.

--Conditions whose name doesn't follow "cannot be" (G5).
local CONDITION_PHRASES = {prone = "knocked prone"}

--A trigger name longer than this is taken for its rule text, not a name (G7a).
local TRIGGER_NAME_MAX = 40

--What one trigger nested under an action did, in What happened's words ("Human Talent took
--1 damage.", "Lv2 Human Null gained 1 Discipline."). Nil when it did nothing to show.
--- @param kid HistoryEntry
--- @return string|nil
local function TriggerEffect(kid)
    if kid.family == "resource" then
        return string.format("%s %s %s.", History.ShownName(kid.who), (kid.amount or 0) > 0 and "gained" or "spent",
            History.ResourceWords(math.abs(kid.amount or 0), kid.name))
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

--What the tier modifiers on a roll add up to, as the roll reads them; skip leaves one out.
--- @param sources HistoryEdgeSource[]
--- @param skip? HistoryEdgeSource
local function TierMods(sources, skip)
    local mods = {tiers = 0}
    for _, source in ipairs(sources) do
        if source ~= skip then
            mods.tiers = mods.tiers + (source.tiers or 0)
            mods.autosuccess = mods.autosuccess or source.autosuccess
            mods.autofailure = mods.autofailure or source.autofailure
            mods.nottierthree = mods.nottierthree or source.nottierthree
            mods.nottierone = mods.nottierone or source.nottierone
        end
    end
    return mods
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
        return "a double " .. side
    end
    return side == "edge" and "an edge" or "a bane"
end

--- G9-G11: what each side of a roll did to its tier, recomputed without it (COPY.md Round
--- 13). Nothing when the recomputed tier doesn't match the recorded one, since something
--- History didn't record set it.
--- @param rows HistoryWhyRow[]
--- @param roll {total: number, edges: number|nil, banes: number|nil, sources: HistoryEdgeSource[]|nil}
--- @param tier integer The tier the roll came to.
--- @param natural integer The dice, for the natural 19 or 20 rule.
--- @param against string|nil On a target's own roll (G9t): its name. Its lines then cover only
--- the sources the main roll didn't have (mainSources).
--- @param mainSources HistoryEdgeSource[]|nil
local function AddRollLines(rows, roll, tier, natural, against, mainSources)
    local sources = roll.sources or {}
    local edges, banes = roll.edges or 0, roll.banes or 0
    local base = roll.total - ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(edges, banes)
    local mods = TierMods(sources)
    if TierOf(base, natural, edges, banes, mods) ~= tier then
        return
    end

    local subject = against ~= nil and "that roll" or "the roll"
    --G10 names the target on its own roll, where "that roll" would have nothing to point at.
    local theRoll = against ~= nil and ("the roll against " .. against) or "the roll"
    local onTarget = against ~= nil and (" against " .. against) or ""
    local function Ending(without)
        if without ~= tier then
            return string.format(", which moved %s from Tier %d to Tier %d.", subject, without, tier)
        end
        return string.format("; %s stayed at Tier %d.", subject, tier)
    end
    --on a target's own roll, a source the main roll also had is the main roll's to explain.
    local function Shown(list)
        if mainSources == nil then
            return list
        end
        local result = {}
        for _, source in ipairs(list) do
            local shared = false
            for _, other in ipairs(mainSources) do
                if other.name == source.name and other.hand == source.hand
                    and (other.who and other.who.id) == (source.who and source.who.id) then
                    shared = true
                end
            end
            if not shared then
                result[#result + 1] = source
            end
        end
        return result
    end
    local function Lead(list)
        local names = {}
        for i, source in ipairs(list) do
            names[i] = SourceText(source)
        end
        return JoinWords(names), #list == 1 and not list[1].hand and list[1].who or nil
    end

    for _, side in ipairs({"edge", "bane"}) do
        local addField = side == "edge" and "edges" or "banes"
        local removedField = side == "edge" and "removedEdges" or "removedBanes"
        local count = side == "edge" and edges or banes
        local function TierWith(n)
            if side == "edge" then
                return TierOf(base, natural, n, banes, mods)
            end
            return TierOf(base, natural, edges, n, mods)
        end
        local adders, removers = {}, {}
        local added, removed = 0, 0
        for _, source in ipairs(sources) do
            if (source[addField] or 0) > 0 then
                adders[#adders + 1] = source
                added = added + source[addField]
            end
            if (source[removedField] or 0) > 0 then
                removers[#removers + 1] = source
                removed = removed + source[removedField]
            end
        end

        --G9 / G9t: what its own edges or banes did, net of anything removed.
        local shown = Shown(adders)
        local gave = 0
        for _, source in ipairs(shown) do
            gave = gave + source[addField]
        end
        if #shown == #adders then
            gave = added - removed
        end
        if gave > 0 and #shown > 0 then
            local lead, who = Lead(shown)
            rows[#rows + 1] = {lead = lead, who = who, text = string.format("%s gave %s%s%s", #shown > 1 and "They" or "It",
                EdgeNoun(side, gave), onTarget, Ending(TierWith(math.max(0, count - gave))))}
        end

        --G9r: what ignored or removed them.
        shown = Shown(removers)
        if removed > 0 and #shown > 0 then
            local ignored = true
            for _, source in ipairs(shown) do
                ignored = ignored and source.ignore == true
            end
            local lead, who = Lead(shown)
            rows[#rows + 1] = {lead = lead, who = who, text = string.format("%s %s %s%s%s", #shown > 1 and "They" or "It",
                ignored and "ignored" or "removed", EdgeNoun(side, removed), onTarget, Ending(TierWith(count + removed)))}
        end
    end

    --G10: each tier modifier, recomputed without it.
    for _, source in ipairs(Shown(sources)) do
        if TierValue(source) ~= nil then
            local without = TierOf(base, natural, edges, banes, TierMods(sources, source))
            local text
            if without == tier then
                local did = string.format("It made %s Tier %d", theRoll, tier)
                if (source.tiers or 0) > 0 then
                    did = "It raised " .. theRoll .. " a tier"
                elseif (source.tiers or 0) < 0 then
                    did = "It lowered " .. theRoll .. " a tier"
                elseif source.nottierthree then
                    did = "It kept " .. theRoll .. " from Tier 3"
                elseif source.nottierone then
                    did = "It lifted " .. theRoll .. " off Tier 1"
                end
                text = string.format("%s; %s stayed at Tier %d.", did, subject, tier)
            elseif source.autosuccess or source.autofailure then
                text = string.format("It made %s Tier %d instead of Tier %d.", theRoll, tier, without)
            elseif (source.tiers or 0) > 0 then
                text = string.format("It raised %s a tier, from Tier %d to Tier %d.", theRoll, without, tier)
            elseif (source.tiers or 0) < 0 then
                text = string.format("It lowered %s a tier, from Tier %d to Tier %d.", theRoll, without, tier)
            elseif source.nottierthree then
                text = string.format("It kept %s from Tier 3: Tier %d instead.", theRoll, tier)
            else
                text = string.format("It lifted %s off Tier 1: Tier %d instead.", theRoll, tier)
            end
            local lead, who = Lead({source})
            rows[#rows + 1] = {lead = lead, who = who, text = text}
        end
    end

    --G11: a natural 19 or 20 is always Tier 3.
    if against == nil and natural >= 19 then
        local without = TierOf(base, 0, edges, banes, mods)
        if without ~= tier then
            rows[#rows + 1] = {
                lead = "Natural " .. natural,
                text = string.format("A natural 19 or 20 is always Tier 3, so the roll is Tier 3 instead of Tier %d.", without),
            }
        end
    end
end

--- Why an action came out as it did, from what the entry recorded: an area that hit an
--- ally, damage modifiers, surges, immunity, condition immunity (COPY.md Round 11), then
--- the triggers it set off and the notes its author typed (Round 12). A line that several
--- targets share is written once, naming them all. G6 when nothing changed it. No gui, so
--- other views can use the same words.
--- @param entry HistoryEntry
--- @param kids? HistoryEntry[] What is nested under it.
--- @return HistoryWhyRow[]
function History.Why(entry, kids)
    local rows = {}
    if entry.kind ~= "action" then
        return rows
    end
    local targets = entry.targets or {}
    local several = #targets > 1

    --each line is built once its targets are known; make gets their names (L29, L30).
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
    local function TypeWord(damagetype)
        return damagetype ~= nil and (damagetype .. " ") or ""
    end

    --G9-G11 first: the roll, then each target's own roll. The roll's tier is that of a
    --target with no roll of its own, as in The numbers.
    local roll = entry.roll
    if roll ~= nil then
        local tier = roll.tier
        for _, who in ipairs(targets) do
            if who.roll == nil and who.tier ~= nil then
                tier = who.tier
                break
            end
        end
        local natural = roll.natural or 0
        if tier ~= nil then
            AddRollLines(rows, roll, tier, natural, nil, nil)
        end
        for _, who in ipairs(targets) do
            if who.roll ~= nil and who.tier ~= nil then
                AddRollLines(rows, who.roll, who.tier, natural, History.ShownName(who), roll.sources or {})
            end
        end
    end

    --G4: an area ability that hit one of its user's side.
    for _, who in ipairs(targets) do
        if History.IsAllyHit(entry, who) then
            Add("area", function()
                return {lead = "Area ability", text = "It hits every creature in the area, allies included."}
            end, who)
            break
        end
    end

    --G3: what one of the roll dialog's modifiers added to a target's damage.
    local function AddModifier(part, who)
        local key = string.format("modifier|%s|%s|%d|%s", part.name or "", part.who ~= nil and part.who.id or "",
            part.amount, part.damagetype or "")
        Add(key, function(group)
            local lead = SpoilerName(part.name or "")
            if part.who ~= nil then
                lead = string.format("%s's %s", History.ShownName(part.who), lead)
            end
            local to = several and (" to " .. GroupNames(group)) or ""
            local text = string.format("It dealt %d extra %sdamage%s.", part.amount, TypeWord(part.damagetype), to)
            if part.amount < 0 then
                text = string.format("It took %d off the %sdamage%s.", -part.amount, TypeWord(part.damagetype), to)
            end
            return {lead = lead, who = part.who, text = text}
        end, who)
    end

    --G2: the surges spent on a target.
    local function AddSurges(part, who)
        local key = string.format("surge|%d|%d|%s|%s", part.count or 0, part.each or 0, part.damagetype or "", part.characteristic or "")
        Add(key, function(group)
            local count = part.count or 0
            local to = several and (" to " .. GroupNames(group)) or ""
            local text = string.format("%s %d extra %sdamage%s", count == 1 and "It dealt" or "Each dealt",
                part.each or 0, TypeWord(part.damagetype), to)
            if part.characteristic ~= nil and entry.actor ~= nil then
                text = string.format("%s (%s's highest characteristic, %s %d)", text, History.ShownName(entry.actor),
                    part.characteristic, part.each or 0)
            end
            return {lead = count == 1 and "Spent 1 surge" or string.format("Spent %d surges", count), text = text .. "."}
        end, who)
    end

    --modifiers in one pass and surges in the next, so they keep that order across targets.
    for _, who in ipairs(targets) do
        for _, part in ipairs(who.parts or {}) do
            if part.kind == "modifier" then
                AddModifier(part, who)
            end
        end
    end
    for _, who in ipairs(targets) do
        for _, part in ipairs(who.parts or {}) do
            if part.kind == "surge" then
                AddSurges(part, who)
            end
        end
    end

    --G1: what immunity took off, or weakness added.
    for _, who in ipairs(targets) do
        local immunity = who.immunity
        if immunity ~= nil and immunity.amount ~= 0 then
            local landed = who.taken or 0
            local damagetype = nil
            if immunity.damagetype ~= "damage" and who.types ~= nil and who.types[immunity.damagetype] ~= nil then
                damagetype = immunity.damagetype
                landed = who.types[damagetype]
            else
                for _, amount in pairs(who.types or {}) do
                    landed = landed - amount
                end
            end
            local key = string.format("immunity|%s|%d|%d", immunity.damagetype, immunity.amount, landed)
            Add(key, function(group)
                return {
                    lead = ResistWords(immunity),
                    text = string.format("%s%s took %d %sdamage instead of %d.", GroupNames(group), #group > 1 and " each" or "",
                        landed, TypeWord(damagetype), landed + immunity.amount),
                }
            end, who)
        end
    end

    --G5: a condition the target's immunity stopped.
    for _, who in ipairs(targets) do
        for _, name in ipairs(who.immune or {}) do
            local condition = string.lower(name)
            Add("immune|" .. condition, function(group)
                return {
                    lead = "Immune to " .. condition,
                    text = string.format("%s cannot be %s.", GroupNames(group), CONDITION_PHRASES[condition] or condition),
                }
            end, who)
        end
    end

    for _, line in ipairs(order) do
        rows[#rows + 1] = line.make(line.who)
    end

    --G7: each trigger this action set off, named so 2.3d can show its card, and what it did.
    --A resource line from a trigger written before Round 12 has only its small text.
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
            --natural 2 ..."); that reads badly as a lead, so it says "trigger" (G7a).
            local lead = name
            if string.find(name, "[%.!?]%s*$") ~= nil or #name > TRIGGER_NAME_MAX then
                lead = "Trigger"
                name = "trigger"
            end
            rows[#rows + 1] = {
                lead = owner ~= nil and string.format("%s's %s", History.ShownName(owner), name) or lead,
                who = owner,
                text = "Triggered by this action: " .. effect,
            }
        end
        for _, message in ipairs(kid.messages or {}) do
            messages[#messages + 1] = message
        end
    end

    --G8: the notes typed on its steps and its triggers' steps, as written, each once.
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

    --G6: only when the roll and the damage are exactly what the tier says. A kit is the
    --hero's normal damage, so it doesn't count as a change.
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
        rows[1] = {plain = true, text = "Nothing changed the roll or the damage."}
    end
    return rows
end

--One Why line: its lead in bold (after a modifier owner's face) over its sentence, with a
--thin rule down the left as in the prototype.
--- @param row HistoryWhyRow
local function WhyRow(row, width)
    local inner = width - WHY_INDENT
    local children = {}
    if row.lead ~= nil then
        local lead = {}
        if row.who ~= nil then
            local face = History.Face(row.who, 18)
            face.selfStyle.rmargin = 6
            face.selfStyle.halign = "left"
            lead[1] = face
        end
        lead[#lead + 1] = gui.Label{
            classes = {"historyWhyLead"},
            text = row.lead,
            width = "auto",
            maxWidth = inner - (row.who ~= nil and 24 or 0),
            height = "auto",
            halign = "left",
            valign = "center",
        }
        children[1] = gui.Panel{
            flow = "horizontal",
            width = inner,
            height = "auto",
            halign = "left",
            children = lead,
        }
    end
    children[#children + 1] = gui.Label{
        classes = {row.plain and "historyWhyPlain" or "historyWhyText"},
        text = row.text,
        width = inner,
        height = "auto",
        halign = "left",
        textAlignment = "left",
    }
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

--- Builds the card for one row. It is rebuilt to change it: the sections have a different
--- shape for every action, and a scroll bar only works if it is there on its first frame.
--- tail is the card's edge that faces History ("left" or "right"). The tail comes back in
--- card.data.tail, not attached: the caller adds it to the card's parent BEFORE the card, so
--- the card hides its inner half, and moves it to the row. None inside the window.
--- @param args {entry: HistoryEntry, kids: HistoryEntry[]|nil, x: number, width: number, maxHeight: number, inTray: boolean, tail: "left"|"right"|nil, close: function}
--- @return Panel
function History.CreateCard(args)
    local entry = args.entry
    local width = args.width
    local inner = width - 2 * CARD_PAD

    local body = {SectionHead("What happened", WHAT_HAPPENED_WIDTH, inner)}
    for _, row in ipairs(History.Story(entry, args.kids)) do
        body[#body + 1] = StoryRow(row, inner)
    end
    local why = History.Why(entry, args.kids)
    if #why > 0 then
        body[#body + 1] = SectionHead("Why", WHY_WIDTH, inner)
        for _, row in ipairs(why) do
            body[#body + 1] = WhyRow(row, inner)
        end
    end
    if entry.kind == "action" then
        local numbers = NumbersRows(entry, args.kids, inner)
        if #numbers > 0 then
            body[#body + 1] = SectionHead("The numbers", THE_NUMBERS_WIDTH, inner)
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

        Header(entry, width, args.inTray, args.close),
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
            maxHeight = args.maxHeight - 62,
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
