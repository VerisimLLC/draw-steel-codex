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
    if numbered then
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
