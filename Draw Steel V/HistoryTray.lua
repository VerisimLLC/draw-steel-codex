local mod = dmhub.GetModLoading()

--The History tray: a table item that shows a map's History as rounds and turns,
--newest at the bottom. Older rounds and turns fold away, so opening it builds a few
--rows even after a long fight. The target design is the prototype named in
--docs/action-log-design/BUILD-PLAN.md.
--
--Each refresh works out the list of rows from the entries, then keeps every row whose
--signature is unchanged and builds only what is new. A new action builds one row.

local TRAY_WIDTH = 410
local TRAY_HEIGHT = 520
local TRAY_HEIGHT_ALL = 914
local HEAD_HEIGHT = 36

--Rows built at first; scrolling to the top adds this many more each time.
local ROWS_CHUNK = 40

--Turns of the newest round that stay apart from the "Turns a-b" fold.
local NEWEST_TURNS = 4

--Target faces on a fold line before "+N".
local FOLD_FACES = 5

--Targets on an action before the last cell becomes "+N".
local TARGET_CELLS = 4

local ITEM_KIND = "history"
local ITEM_KEY = "tray"

--The Codex's fonts have these two; Lua source stays ASCII (REVIEW.md, font check).
local DOT = " \194\183 "
local EN_DASH = "\226\128\147"

--Room kept beside an action's title for the longest of these words.
local ACTION_WORDS_WIDTH = 92

--Room kept at the end of a line for its number, "120 to 135" at the longest.
local LINE_NUMBER_WIDTH = 70

local ACTION_WORDS = {
    main = "Main action",
    maneuver = "Maneuver",
    freestrike = "Free strike",
    triggered = "Triggered action",
}

local function Styles()
    return {
        {
            selectors = {"historyTray"},
            bgcolor = "@bg",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"label"},
            fontSize = 13,
            color = "@fg",
        },
        {
            selectors = {"label", "historyTitle"},
            fontSize = 13,
            bold = true,
            uppercase = true,
            color = "@fgStrong",
        },
        {
            selectors = {"label", "historyMuted"},
            fontSize = 11,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyName"},
            fontSize = 14,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = {"label", "historySmallCaps"},
            fontSize = 11,
            uppercase = true,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyTier"},
            fontSize = 11,
            bold = true,
            color = "@fg",
            bgcolor = "clear",
            borderColor = "@fgMuted",
        },
        {
            selectors = {"label", "historyButton"},
            fontSize = 12,
            color = "@fgMuted",
            bgcolor = "clear",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"label", "historyButton", "hover"},
            color = "@fgStrong",
            borderColor = "@fgMuted",
        },
        {
            selectors = {"label", "historyCellName"},
            fontSize = 12,
            color = "@fg",
        },
        {
            selectors = {"label", "historyCaption"},
            fontSize = 11,
            bold = true,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyHurt"},
            bold = true,
            color = "@danger",
        },
        {
            selectors = {"label", "historyHealed"},
            bold = true,
            color = "@success",
        },
        {
            selectors = {"label", "historyPlainNumber"},
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = {"historyFold"},
            bgcolor = "clear",
        },
        {
            selectors = {"historyFold", "hover"},
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = {"historyCaret"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"historySeam"},
            bgcolor = "@border",
            opacity = 0.35,
        },
        {
            selectors = {"historyHero"},
            borderColor = "@fg",
        },
        {
            selectors = {"historyFoe"},
            borderColor = "@danger",
        },
    }
end

local function ShownName(who)
    if who.secret and not dmhub.isDM then
        return "Unknown creature"
    end
    return who.name
end

--A round portrait from a snapshot, with a ring that says which side it is on.
local function Face(who, size)
    local rect = who.rect
    return gui.Panel{
        classes = {cond(who.hero, "historyHero", "historyFoe")},
        width = size,
        height = size,
        halign = "left",
        valign = "center",
        bgimage = who.img,
        bgcolor = "white",
        cornerRadius = size / 2,
        borderWidth = 2,
        imageRect = rect ~= nil and {x1 = rect[1], y1 = rect[2], x2 = rect[3], y2 = rect[4]} or nil,
    }
end

local function Caret(down)
    return gui.Panel{
        classes = {"historyCaret"},
        width = 10,
        height = 10,
        halign = "left",
        valign = "center",
        rmargin = 7,
        bgimage = cond(down, "phosphor/caret-down-fill.png", "phosphor/caret-right-fill.png"),
    }
end

local function TierBadge(tier)
    return gui.Label{
        classes = {"historyTier"},
        bgimage = "panels/square.png",
        text = string.format("Tier %d", tier),
        width = "auto",
        height = 16,
        hpad = 6,
        borderBox = true,
        borderWidth = 1,
        cornerRadius = 8,
        halign = "left",
        valign = "center",
        lmargin = 5,
        textAlignment = "center",
    }
end

--A number that landed. Bold numbers use a plain "-": the bold font has no minus sign.
local function Amount(value, healed, size)
    return gui.Label{
        classes = {cond(healed, "historyHealed", "historyHurt")},
        text = string.format(cond(healed, "+%d", "-%d"), value),
        fontSize = size,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        rmargin = 3,
    }
end

--The faces on a fold line, each with what it took and regained. Damage and healing stay
--apart, so 9 taken and 8 healed never reads as -1 (fix B1).
local function MiniFaces(tally)
    local children = {}
    for i, row in ipairs(tally) do
        if i > FOLD_FACES then
            children[#children + 1] = gui.Label{
                classes = {"historyMuted"},
                text = string.format("+%d", #tally - FOLD_FACES),
                width = "auto",
                height = 20,
                valign = "center",
                textAlignment = "left",
            }
            break
        end
        local face = Face(row.who, 20)
        face.selfStyle.rmargin = 3
        children[#children + 1] = face
        if row.taken > 0 then
            children[#children + 1] = Amount(row.taken, false, 13)
        end
        if row.healed > 0 then
            children[#children + 1] = Amount(row.healed, true, 13)
        end
        children[#children].selfStyle.rmargin = 8
    end
    return gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = 20,
        halign = "left",
        valign = "center",
        lmargin = 4,
        children = children,
    }
end

--The small lines under a target (T14).
local function Captions(who)
    local list = {}
    if who.types ~= nil then
        local names = {}
        for name in pairs(who.types) do
            names[#names + 1] = name
        end
        table.sort(names)
        if #names == 1 then
            list[1] = string.upper_first(names[1])
        else
            local parts = {}
            for i, name in ipairs(names) do
                parts[i] = string.format("%d %s", who.types[name], name)
            end
            list[1] = table.concat(parts, ", ")
        end
    end
    local immunity = who.immunity
    if immunity ~= nil and immunity.amount > 0 then
        list[#list + 1] = string.format("%s immunity -%d", string.upper_first(immunity.damagetype), immunity.amount)
    elseif immunity ~= nil and immunity.amount < 0 then
        list[#list + 1] = string.format("%s weakness +%d", string.upper_first(immunity.damagetype), -immunity.amount)
    end
    if who.soaked ~= nil then
        list[#list + 1] = string.format("%d soaked by temporary Stamina", who.soaked)
    end
    if who.pool ~= nil then
        list[#list + 1] = string.format("temporary Stamina %d to %d", who.pool.before, who.pool.after)
    end
    return list
end

local function TargetCell(who, width, showTier)
    local textWidth = width - 45
    local top = {}
    if (who.taken or 0) > 0 then
        top[#top + 1] = Amount(who.taken, false, 16)
    end
    if (who.healed or 0) > 0 then
        top[#top + 1] = Amount(who.healed, true, 16)
    end
    top[#top + 1] = gui.Label{
        classes = {"historyCellName"},
        text = ShownName(who),
        width = textWidth - #top * 34,
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 3,
        textWrap = false,
        textAlignment = "left",
    }

    local below = {}
    if showTier and who.tier ~= nil then
        below[1] = gui.Label{
            classes = {"historyTier"},
            bgimage = "panels/square.png",
            text = string.format("Tier %d", who.tier),
            width = "auto",
            height = 15,
            hpad = 4,
            borderBox = true,
            borderWidth = 1,
            cornerRadius = 7,
            halign = "left",
            valign = "center",
            rmargin = 6,
            textAlignment = "center",
        }
    end
    for _, text in ipairs(Captions(who)) do
        below[#below + 1] = gui.Label{
            classes = {"historyCaption"},
            text = text,
            width = "auto",
            maxWidth = textWidth,
            height = "auto",
            halign = "left",
            valign = "center",
            rmargin = 8,
            textAlignment = "left",
        }
    end

    return gui.Panel{
        flow = "horizontal",
        width = width,
        height = "auto",
        halign = "left",
        vmargin = 2,
        Face(who, 36),
        gui.Panel{
            flow = "vertical",
            width = textWidth,
            height = "auto",
            lmargin = 9,
            halign = "left",
            valign = "center",
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                children = top,
            },
            gui.Panel{
                flow = "horizontal",
                wrap = true,
                width = "100%",
                height = "auto",
                children = below,
            },
        },
    }
end

--Past four targets, three cells and "+N" with the rest named beside it (B6).
local function MoreCell(rest, width)
    local names = {}
    for i, who in ipairs(rest) do
        names[i] = ShownName(who)
    end
    return gui.Panel{
        flow = "horizontal",
        width = width,
        height = "auto",
        halign = "left",
        vmargin = 2,
        gui.Label{
            classes = {"historyName"},
            text = string.format("+%d", #rest),
            width = 36,
            height = 36,
            halign = "left",
            valign = "center",
            textAlignment = "center",
        },
        gui.Label{
            classes = {"historyMuted"},
            text = table.concat(names, ", "),
            width = width - 45,
            height = "auto",
            lmargin = 9,
            halign = "left",
            valign = "center",
            textAlignment = "left",
        },
    }
end

--A tier on the action when every target got the same one; on the cells when not.
local function SharedTier(entry)
    local shared = nil
    for _, who in ipairs(entry.targets) do
        if who.tier == nil then
            return nil, false
        end
        if shared ~= nil and shared ~= who.tier then
            return nil, true
        end
        shared = who.tier
    end
    return shared, false
end

local function BuildAction(item)
    local entry = item.entry
    local tier, tierPerTarget = SharedTier(entry)
    if tier == nil and not tierPerTarget and entry.roll ~= nil and entry.roll.tier ~= 0 then
        tier = entry.roll.tier
    end

    local titleChildren = {}
    if item.showActor then
        titleChildren[#titleChildren + 1] = Face(entry.actor, 22)
        titleChildren[#titleChildren + 1] = gui.Label{
            classes = {"historyName"},
            text = ShownName(entry.actor) .. DOT,
            width = "auto",
            height = "auto",
            lmargin = 5,
            halign = "left",
            valign = "center",
        }
    end
    titleChildren[#titleChildren + 1] = gui.Label{
        text = entry.ability.name,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
    }
    if tier ~= nil then
        titleChildren[#titleChildren + 1] = TierBadge(tier)
    end

    local action = ACTION_WORDS[entry.ability.action]

    local inner = TRAY_WIDTH - 52 - 12
    local targets = entry.targets
    local cells = {}
    if #targets == 1 then
        cells[1] = TargetCell(targets[1], inner, tierPerTarget)
    else
        local cellWidth = math.floor((inner - 10) / 2)
        local shown = cond(#targets > TARGET_CELLS, TARGET_CELLS - 1, #targets)
        for i = 1, shown do
            cells[#cells + 1] = TargetCell(targets[i], cellWidth, tierPerTarget)
        end
        if #targets > shown then
            local rest = {}
            for i = shown + 1, #targets do
                rest[#rest + 1] = targets[i]
            end
            cells[#cells + 1] = MoreCell(rest, cellWidth)
        end
    end

    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        lpad = 52,
        rpad = 12,
        tpad = 4,
        bpad = 9,
        borderBox = true,
        gui.Panel{
            flow = "none",
            width = "100%",
            height = "auto",
            bmargin = 4,
            gui.Panel{
                flow = "horizontal",
                wrap = true,
                width = inner - ACTION_WORDS_WIDTH,
                height = "auto",
                halign = "left",
                valign = "center",
                children = titleChildren,
            },
            action ~= nil and gui.Label{
                classes = {"historyMuted"},
                text = action,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
            } or nil,
        },
        gui.Panel{
            flow = "horizontal",
            wrap = true,
            width = "100%",
            height = "auto",
            children = cells,
        },
    }
end

--A result with no action behind it (L1-L4): who, what, and the cause under it.
local function LineWords(entry)
    local name = string.format("<b>%s</b>", ShownName(entry.who))
    if entry.family == "damage" then
        local kind = entry.damagetype ~= nil and (entry.damagetype .. " ") or ""
        return string.format("%s took %d %sdamage", name, entry.taken, kind)
    elseif entry.family == "heal" then
        return string.format("%s regained %d Stamina", name, entry.healed)
    end
    return name .. " temporary Stamina"
end

local function LineNumber(entry)
    if entry.family == "damage" then
        return Amount(entry.taken, false, 14)
    elseif entry.family == "heal" then
        return Amount(entry.healed, true, 14)
    end
    return gui.Label{
        classes = {"historyPlainNumber"},
        text = string.format("%d to %d", entry.before, entry.after),
        fontSize = 14,
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
    }
end

local function BuildLine(item)
    local entry = item.entry
    local cause = entry.cause
    if entry.soaked ~= nil then
        local soaked = string.format("%d soaked by temporary Stamina", entry.soaked)
        cause = cause ~= nil and (cause .. DOT .. soaked) or soaked
    end

    local words = {
        gui.Label{
            text = LineWords(entry),
            width = "100%",
            height = "auto",
            textAlignment = "left",
        },
    }
    if cause ~= nil then
        words[2] = gui.Label{
            classes = {"historyMuted"},
            text = cause,
            width = "100%",
            height = "auto",
            textAlignment = "left",
        }
    end

    local number = LineNumber(entry)
    number.selfStyle.halign = "right"
    return gui.Panel{
        flow = "none",
        width = "100%",
        height = "auto",
        lpad = 52,
        rpad = 12,
        vpad = 4,
        borderBox = true,
        gui.Panel{
            flow = "horizontal",
            width = TRAY_WIDTH - 52 - 12 - LINE_NUMBER_WIDTH,
            height = "auto",
            halign = "left",
            valign = "center",
            Face(entry.who, 18),
            gui.Panel{
                flow = "vertical",
                width = TRAY_WIDTH - 52 - 12 - LINE_NUMBER_WIDTH - 26,
                height = "auto",
                lmargin = 8,
                halign = "left",
                valign = "center",
                children = words,
            },
        },
        number,
    }
end

local function BuildRoundHead(item)
    local title = {}
    if item.toggle ~= nil then
        title[1] = Caret(true)
    end
    title[#title + 1] = gui.Label{
        classes = {"historyTitle"},
        text = item.text,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
    }
    return gui.Panel{
        classes = {cond(item.toggle ~= nil, "historyFold", "historyStill")},
        bgimage = "panels/square.png",
        flow = "vertical",
        width = "100%",
        height = "auto",
        click = item.toggle,
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 30,
            hpad = 12,
            borderBox = true,
            valign = "center",
            children = title,
        },
        gui.Panel{
            classes = {"historySeam"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
        },
    }
end

local function BuildRoundFold(item)
    return gui.Panel{
        classes = {"historyFold"},
        bgimage = "panels/square.png",
        flow = "vertical",
        width = "100%",
        height = "auto",
        click = item.toggle,
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 32,
            hpad = 12,
            borderBox = true,
            Caret(false),
            gui.Label{
                classes = {"historyTitle"},
                text = item.text,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            MiniFaces(item.tally),
        },
        gui.Panel{
            classes = {"historySeam"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
        },
    }
end

local function BuildGroupFold(item)
    return gui.Panel{
        classes = {"historyFold"},
        bgimage = "panels/square.png",
        flow = "horizontal",
        width = "100%",
        height = 30,
        hpad = 12,
        borderBox = true,
        click = item.toggle,
        Caret(false),
        gui.Label{
            classes = {"historyMuted"},
            text = item.text,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        },
        MiniFaces(item.tally),
    }
end

local function BuildTurnFold(item)
    return gui.Panel{
        classes = {"historyFold"},
        bgimage = "panels/square.png",
        flow = "horizontal",
        width = "100%",
        height = 36,
        hpad = 12,
        borderBox = true,
        click = item.toggle,
        Caret(false),
        gui.Label{
            classes = {"historyMuted"},
            text = tostring(item.number),
            width = 26,
            height = "auto",
            halign = "left",
            valign = "center",
            rmargin = 7,
            textAlignment = "right",
        },
        Face(item.owner, 26),
        MiniFaces(item.tally),
    }
end

local function TurnSideText(item)
    local owner = item.owner
    local text = string.format("Turn %d%s%s", item.number, DOT, cond(owner.hero, "Hero turn", "Enemy turn"))
    if owner.minions and owner.group ~= nil then
        text = text .. DOT .. string.format("%d minions", owner.group)
    end
    return text
end

local function BuildTurnHead(item)
    return gui.Panel{
        classes = {"historyFold"},
        bgimage = "panels/square.png",
        flow = "horizontal",
        width = "100%",
        height = "auto",
        lpad = 12,
        rpad = 12,
        tpad = 9,
        bpad = 3,
        borderBox = true,
        click = item.toggle,
        Caret(true),
        Face(item.owner, 30),
        gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            lmargin = 7,
            halign = "left",
            valign = "center",
            gui.Label{
                classes = {"historyName"},
                text = ShownName(item.owner),
                width = "auto",
                height = "auto",
                halign = "left",
            },
            gui.Label{
                classes = {"historySmallCaps"},
                text = TurnSideText(item),
                width = "auto",
                height = "auto",
                halign = "left",
            },
        },
    }
end

local g_builders = {
    roundhead = BuildRoundHead,
    roundfold = BuildRoundFold,
    groupfold = BuildGroupFold,
    turnfold = BuildTurnFold,
    turnhead = BuildTurnHead,
    action = BuildAction,
    line = BuildLine,
}

--What the user has opened or closed by hand, by section or turn id. A section or turn
--with no entry here follows the default: only the newest stays open.
local g_open = {}
local g_showAll = false

local g_tray = nil

local function Toggle(id, isOpen)
    return function()
        g_open[id] = not isOpen
        if g_tray ~= nil then
            g_tray.Refresh()
        end
    end
end

--What each creature took and regained across some entries, for a fold line.
local function Tally(entries)
    local list = {}
    local byId = {}
    local function Add(who, taken, healed)
        if (taken or 0) <= 0 and (healed or 0) <= 0 then
            return
        end
        local row = byId[who.id]
        if row == nil then
            row = {who = who, taken = 0, healed = 0}
            byId[who.id] = row
            list[#list + 1] = row
        end
        row.taken = row.taken + (taken or 0)
        row.healed = row.healed + (healed or 0)
    end
    for _, entry in ipairs(entries) do
        if entry.kind == "line" then
            Add(entry.who, entry.taken, entry.healed)
        else
            for _, who in ipairs(entry.targets or {}) do
                Add(who, who.taken, who.healed)
            end
        end
    end
    return list
end

local function TallySignature(tally)
    local parts = {}
    for i, row in ipairs(tally) do
        parts[i] = string.format("%s:%d:%d", row.who.id, row.taken, row.healed)
    end
    return table.concat(parts, ",")
end

--Groups entries, oldest first, into sections (a round, or a stretch out of combat)
--holding turns holding entries. Out of combat has no round, so an encounter between
--two stretches keeps them apart, and each takes its id from its first entry.
local function BuildSections(mapid)
    local sections = {}
    local section = nil
    local turn = nil
    for _, key in ipairs(History.Keys(mapid)) do
        local entry = History.Entry(mapid, key)
        if entry ~= nil then
            local groupid = "out"
            if entry.encounter ~= nil then
                groupid = string.format("%s-%d", entry.encounter, entry.round)
            end
            if section == nil or section.groupid ~= groupid then
                section = {
                    groupid = groupid,
                    id = groupid == "out" and ("out-" .. key) or groupid,
                    round = entry.round,
                    turns = {},
                    entries = {},
                }
                sections[#sections + 1] = section
                turn = nil
            end
            local number = entry.turn or 0
            if turn == nil or turn.number ~= number then
                turn = {id = string.format("%s-%d", section.id, number), number = number, entries = {}, keys = {}}
                section.turns[#section.turns + 1] = turn
            end
            turn.owner = turn.owner or entry.owner
            turn.entries[#turn.entries + 1] = entry
            turn.keys[#turn.keys + 1] = key
            section.entries[#section.entries + 1] = entry
        end
    end
    return sections
end

local function SectionTitle(section)
    if section.round == nil then
        return "Out of combat"
    end
    return string.format("Round %d", section.round)
end

local function AddTurnRows(items, turn, isNewest)
    local isOpen = g_open[turn.id]
    if isOpen == nil then
        isOpen = g_showAll or isNewest
    end
    local toggle = Toggle(turn.id, isOpen)
    if turn.owner ~= nil then
        if not isOpen then
            local tally = Tally(turn.entries)
            items[#items + 1] = {
                kind = "turnfold",
                key = "fold-" .. turn.id,
                sig = turn.owner.id .. TallySignature(tally),
                number = turn.number,
                owner = turn.owner,
                tally = tally,
                toggle = toggle,
            }
            return
        end
        items[#items + 1] = {
            kind = "turnhead",
            key = "head-" .. turn.id,
            sig = turn.owner.id,
            number = turn.number,
            owner = turn.owner,
            toggle = toggle,
        }
    end
    for i, entry in ipairs(turn.entries) do
        if entry.kind == "line" then
            items[#items + 1] = {kind = "line", key = turn.keys[i], sig = entry, entry = entry}
        else
            items[#items + 1] = {
                kind = "action",
                key = turn.keys[i],
                sig = entry,
                entry = entry,
                showActor = turn.owner == nil or entry.actor.id ~= turn.owner.id,
            }
        end
    end
end

local function AddSectionRows(items, section, isNewest)
    local isOpen = g_open[section.id]
    if isOpen == nil then
        isOpen = g_showAll or isNewest
    end
    local title = SectionTitle(section)
    if not isOpen then
        local tally = Tally(section.entries)
        items[#items + 1] = {
            kind = "roundfold",
            key = "fold-" .. section.id,
            sig = title .. TallySignature(tally),
            text = title,
            tally = tally,
            toggle = Toggle(section.id, isOpen),
        }
        return
    end

    --the newest section stays open, so it has nothing to fold to.
    items[#items + 1] = {
        kind = "roundhead",
        key = "head-" .. section.id,
        sig = title,
        text = title,
        toggle = (not isNewest or g_open[section.id] == false) and Toggle(section.id, isOpen) or nil,
    }

    local turns = section.turns
    local first = 1
    local groupid = "group-" .. section.id
    if isNewest and not g_showAll and g_open[groupid] ~= true and #turns > NEWEST_TURNS then
        local firstNumber, lastNumber = nil, nil
        local entries = {}
        first = #turns - NEWEST_TURNS + 1
        for i = 1, first - 1 do
            firstNumber = firstNumber or turns[i].number
            lastNumber = turns[i].number
            for _, entry in ipairs(turns[i].entries) do
                entries[#entries + 1] = entry
            end
        end
        local tally = Tally(entries)
        items[#items + 1] = {
            kind = "groupfold",
            key = groupid,
            sig = string.format("%d-%d", firstNumber, lastNumber) .. TallySignature(tally),
            text = string.format("Turns %d%s%d", firstNumber, EN_DASH, lastNumber),
            tally = tally,
            toggle = Toggle(groupid, false),
        }
    end
    for i = first, #turns do
        AddTurnRows(items, turns[i], isNewest and i == #turns)
    end
end

local function BuildItems(mapid)
    local items = {}
    local sections = BuildSections(mapid)
    for i, section in ipairs(sections) do
        AddSectionRows(items, section, i == #sections)
    end
    return items
end

local function CreateFace()
    local rowsWanted = ROWS_CHUNK
    local hasOlder = false
    local loadingOlder = false
    local anchor = nil
    local anchorTries = 0
    local mapid = game.currentMapId

    --Built rows by item key: {panel, sig}.
    local rows = {}

    local rowsPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "bottom",
    }

    local face
    local list

    local function Refresh()
        if face == nil or not face.valid then
            return
        end
        local stick = list.vscrollPosition <= 0.02
        local items = BuildItems(mapid)
        local first = math.max(1, #items - rowsWanted + 1)
        hasOlder = first > 1

        local children = {}
        local kept = {}
        for i = first, #items do
            local item = items[i]
            local row = rows[item.key]
            if row == nil or row.sig ~= item.sig or not row.panel.valid then
                row = {panel = g_builders[item.kind](item), sig = item.sig}
            end
            kept[item.key] = row
            children[#children + 1] = row.panel
        end
        rows = kept
        rowsPanel.children = children
        if stick and not loadingOlder then
            list:ScheduleEvent("toBottom", 0.02)
        end
    end

    list = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = TRAY_HEIGHT - HEAD_HEIGHT - 6,
        vscroll = true,
        rowsPanel,

        toBottom = function(element)
            element.vscrollPosition = 0
        end,

        --at the top with more to show: build the next rows and hold the view still.
        scroll = function(element)
            if hasOlder and not loadingOlder and element.vscrollPosition >= 0.98 then
                loadingOlder = true
                anchor = rowsPanel.children[1]
                anchorTries = 0
                rowsWanted = rowsWanted + ROWS_CHUNK
                Refresh()
                element:ScheduleEvent("anchorOlder", 0.05)
            end
        end,

        --vscrollPosition is 1 at the top and 0 at the bottom. Layout of the new rows
        --takes a few frames, so this runs until the height stops changing.
        anchorOlder = function(element)
            anchorTries = anchorTries + 1
            local windowHeight = element.renderedHeight or 0
            local contentHeight = rowsPanel.renderedHeight or 0
            local range = contentHeight - windowHeight
            if anchor ~= nil and anchor.valid and range > 0 then
                local offset = 0
                for _, row in ipairs(rowsPanel.children) do
                    if row == anchor then
                        break
                    end
                    offset = offset + (row.renderedHeight or 0)
                end
                element.vscrollPosition = 1 - math.min(offset, range) / range
            end
            if anchorTries >= 6 then
                anchor = nil
                loadingOlder = false
            else
                element:ScheduleEvent("anchorOlder", 0.05)
            end
        end,
    }

    local showAllButton
    showAllButton = gui.Label{
        classes = {"historyButton"},
        bgimage = "panels/square.png",
        text = cond(g_showAll, "Show less", "Show all"),
        width = "auto",
        height = 22,
        hpad = 8,
        borderBox = true,
        borderWidth = 1,
        cornerRadius = 4,
        halign = "right",
        valign = "center",
        textAlignment = "center",
        click = function(element)
            g_showAll = not g_showAll
            g_open = {}
            element.text = cond(g_showAll, "Show less", "Show all")
            list.selfStyle.height = cond(g_showAll, TRAY_HEIGHT_ALL, TRAY_HEIGHT) - HEAD_HEIGHT - 6
            face.selfStyle.height = cond(g_showAll, TRAY_HEIGHT_ALL, TRAY_HEIGHT)
            Tabletop.ResizeItem(ITEM_KIND, ITEM_KEY)
            rowsWanted = ROWS_CHUNK
            Refresh()
            list:ScheduleEvent("toBottom", 0.05)
        end,
    }

    face = gui.Panel{
        classes = {"historyTray"},
        styles = ThemeEngine.MergeStyles(Styles()),
        bgimage = "panels/square.png",
        flow = "vertical",
        width = TRAY_WIDTH,
        height = cond(g_showAll, TRAY_HEIGHT_ALL, TRAY_HEIGHT),
        halign = "left",
        valign = "top",
        borderWidth = 1,
        cornerRadius = 6,

        monitorGame = History.DocPath(mapid),
        refreshGame = Refresh,

        --the tray shows the map you are on; following the last clicked map is chunk 6.1.
        thinkTime = 1,
        think = function(element)
            if game.currentMapId ~= mapid then
                mapid = game.currentMapId
                g_open = {}
                rowsWanted = ROWS_CHUNK
                element.monitorGame = History.DocPath(mapid)
                Refresh()
            end
        end,

        destroy = function()
            if g_tray ~= nil and g_tray.face == face then
                g_tray = nil
            end
        end,

        gui.Panel{
            flow = "none",
            width = "100%",
            height = HEAD_HEIGHT,
            hpad = 12,
            borderBox = true,
            gui.Label{
                classes = {"historyTitle"},
                text = "History",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            showAllButton,
        },
        gui.Panel{
            classes = {"historySeam"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
        },
        list,
    }

    g_tray = {face = face, Refresh = Refresh}
    list.vscrollPosition = 0
    Refresh()
    return face
end

ThemeEngine.OnThemeChanged(mod, function()
    if g_tray ~= nil and g_tray.face.valid then
        g_tray.face.styles = ThemeEngine.MergeStyles(Styles())
    end
end)

Tabletop.itemKinds = Tabletop.itemKinds or {}
Tabletop.itemKinds[ITEM_KIND] = {
    available = History.Enabled,
    exists = function(key)
        return true
    end,
    name = function(key)
        return "History"
    end,
    size = function(key)
        return TRAY_WIDTH, cond(g_showAll, TRAY_HEIGHT_ALL, TRAY_HEIGHT)
    end,
    face = function(key)
        return CreateFace()
    end,
    cornerRadius = 6,
    --beside the rail, where it opens in the prototype.
    place = function(layerWidth, layerHeight)
        return 62, 110
    end,
}

DockablePanel.Register{
    name = "History",
    icon = "phosphor/clock-counter-clockwise-bold.png",
    available = History.Enabled,
    launch = function()
        if Tabletop.HasItem(ITEM_KIND, ITEM_KEY) then
            Tabletop.CloseItem(ITEM_KIND, ITEM_KEY)
        else
            Tabletop.OpenItem(ITEM_KIND, ITEM_KEY)
        end
    end,
}

--Puts the rail button directly below Chat, once. The switch-over (chunk 6.4) gives
--everyone this through the built-in Views; until then only games with History on need it.
local function PlaceRailButton()
    if History.Enabled() then
        PanelDocument.RailPlaceBelow("history", "chat")
    end
end

History.OnEnabledChanged = PlaceRailButton
dmhub.RegisterEventHandler("EnterGame", function()
    if not mod.unloaded then
        PlaceRailButton()
    end
end)
