local mod = dmhub.GetModLoading()

--The History tray: a rail panel window that shows a map's History as rounds and turns,
--newest at the bottom. Older rounds and turns fold away, so opening it builds a few
--rows even after a long fight. The target design is the prototype named in
--docs/action-log-design/BUILD-PLAN.md.
--
--Each refresh works out the list of rows from the entries, then keeps every row whose
--signature is unchanged and builds only what is new. A new action builds one row.

--Rows are laid out for this width. The window adds EDGE_STRIP on the right, where its
--resize strip sits, so the list's scroll bar stays clear of it.
local TRAY_WIDTH = 410
local EDGE_STRIP = 8

--The bar above the list that holds Show all.
local BAR_HEIGHT = 28

--Rows built at first; scrolling to the top adds this many more each time.
local ROWS_CHUNK = 40

--Turns of the newest round that stay apart from the "Turns a-b" fold.
local NEWEST_TURNS = 4

--Target faces on a fold line before "+N".
local FOLD_FACES = 5

--Targets on an action before the last cell becomes "+N".
local TARGET_CELLS = 4

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

--Where the detail card goes. It sits beside the window, so it moves and zooms with it.
local CARD_GAP = 12
local CARD_HEIGHT = 914

--The card's tail points at its row's title line, ROW_TITLE down the row; the tail sits
--TAIL_DOWN down the card, level with the card's own title, when the card can line up.
local ROW_TITLE = 14
local TAIL_DOWN = 26

--The icon rail runs down the screen's left edge; a card can't go under it.
local RAIL_LEFT = 62

--The open tray: {face, Refresh, Select}.
local g_tray = nil

local function Styles()
    return {
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
            selectors = {"label", "historyCaption", "historyWinded"},
            color = "@warning",
        },
        {
            selectors = {"label", "historyCaption", "historyDying"},
            color = "@danger",
        },
        {
            selectors = {"label", "historyCaption", "historyGood"},
            color = "@success",
        },
        {
            selectors = {"label", "historyCaption", "historyDead"},
            color = "@bg",
            bgcolor = "@danger",
        },
        {
            selectors = {"label", "historyChip"},
            fontSize = 11,
            bold = true,
            color = "@fgMuted",
            bgcolor = "clear",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"label", "historyChip", "historyChipHeroic"},
            color = "@info",
            borderColor = "@info",
        },
        {
            selectors = {"label", "historyChip", "historyChipSurge"},
            color = "@warning",
            borderColor = "@warning",
        },
        {
            selectors = {"label", "historyChip", "historyChipMalice"},
            color = "@danger",
            borderColor = "@danger",
        },
        {
            selectors = {"label", "historyUndone"},
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyLineButton"},
            fontSize = 11,
            color = "@fgMuted",
            bgcolor = "clear",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"label", "historyLineButton", "hover"},
            color = "@fgStrong",
            borderColor = "@fgMuted",
        },
        {
            selectors = {"label", "historyEndedTag"},
            fontSize = 11,
            bold = true,
            uppercase = true,
            color = "@fgMuted",
            bgcolor = "clear",
            borderColor = "@fgMuted",
        },
        {
            selectors = {"label", "historyActiveTag"},
            fontSize = 11,
            bold = true,
            uppercase = true,
            color = "@bg",
            bgcolor = "@warning",
        },
        {
            selectors = {"historyBadge"},
            bgcolor = "@bg",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"label", "historyTriggerText"},
            fontSize = 12,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyTriggerResult"},
            fontSize = 12,
            color = "@fg",
        },
        {
            selectors = {"label", "historyTriggerNumber"},
            fontSize = 11,
            bold = true,
            color = "@fg",
            bgcolor = "@bgAlt",
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
        --solid on purpose: with Transparent UI, a see-through fill shows the table behind
        --the window rather than a lighter row.
        {
            selectors = {"historyFold", "historySelected"},
            bgcolor = "@bgRaised",
        },
        --@border is white at 16% in the default theme: the seam under a round heading
        --comes to 12%, the line between rows to 5%, as in the prototype.
        {
            selectors = {"historySeam"},
            bgcolor = "@border",
            opacity = 0.75,
        },
        {
            selectors = {"historyRule"},
            bgcolor = "@border",
            opacity = 0.31,
        },
        {
            selectors = {"historyChevron"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"historyChevron", "parent:hover"},
            bgcolor = "@fg",
        },
        --the rail windows' frame (framedPanel in DocumentWindowStyles), so the card
        --matches History; its blurred backdrop is set on the panel.
        {
            selectors = {"historyCardFrame"},
            bgcolor = "white",
            gradient = "@surfaceLinear",
            cornerRadius = 10,
            opacity = 0.98,
            borderWidth = 0,
            boxShadow = Tabletop.shadows.rest,
        },
        {
            selectors = {"historyCardFrame", "historyCardSolid"},
            opacity = 1,
            cornerRadius = 0,
            boxShadow = false,
        },
        {
            selectors = {"historyCardTail"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"historyCardClose"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"historyCardClose", "hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"label", "historyCardTitle"},
            fontSize = 16,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = {"label", "historyCardMeta"},
            fontSize = 12,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyStory"},
            fontSize = 15,
            color = "@fgStrong",
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

--The detail card is in its own file and speaks and draws the way the tray does.
History.ShownName = ShownName
History.DOT = DOT
History.ACTION_WORDS = ACTION_WORDS

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

History.Face = Face

--Small marks beside a name. Ended is the partner of Active: one for what stopped, one
--for what is still on (L7, L10).
local function Tag(style, text)
    return gui.Label{
        classes = {style},
        bgimage = "panels/square.png",
        text = text,
        width = "auto",
        height = 14,
        hpad = 4,
        borderBox = true,
        cornerRadius = 3,
        borderWidth = cond(style == "historyEndedTag", 1, 0),
        lmargin = 5,
        halign = "left",
        valign = "center",
        textAlignment = "center",
    }
end

--The condition's icon in a small dark circle on the face's top corner.
local function ConditionBadge(condition, index)
    return gui.Panel{
        classes = {"historyBadge"},
        floating = true,
        bgimage = "panels/square.png",
        width = 17,
        height = 17,
        cornerRadius = 8,
        borderWidth = 1,
        halign = cond(index == 1, "right", "left"),
        valign = "top",
        x = cond(index == 1, 5, -5),
        y = -4,
        gui.Panel{
            bgimage = condition.icon,
            bgcolor = "white",
            width = 13,
            height = 13,
            halign = "center",
            valign = "center",
        },
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

History.Tag = Tag
History.Amount = Amount

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

--The caption a state shows as (T14), with the style that marks it.
local STATE_CAPTIONS = {
    winded = {text = "Winded", style = "historyWinded"},
    dying = {text = "Dying", style = "historyDying"},
    killed = {text = "Killed", style = "historyDead"},
}

--What minion deaths read as. The whole squad gone says so.
local function MinionWords(entry)
    if entry.left <= 0 then
        return "Squad destroyed"
    end
    return string.format("%d of %d killed", entry.killed, entry.killed + entry.left)
end

local MOVED_VERBS = {push = "pushed", pull = "pulled", slide = "slid"}
History.MOVED_VERBS = MOVED_VERBS

--"Push 3", with "fell 4" after a dot when it fell too (T14). vertical_push reads "Vertical push".
local function MovedWords(moved)
    local kind = string.upper_first(string.gsub(moved.kind, "_", " "))
    if moved.distance <= 0 then
        return string.format("Fell %d", moved.fell)
    end
    local words = string.format("%s %d", kind, moved.distance)
    if moved.fell > 0 then
        words = words .. DOT .. string.format("fell %d", moved.fell)
    end
    return words
end

--The small lines under a target (T14). ended marks one that takes an Ended tag.
--minions: confirmed minion deaths that belong on this cell.
--allyHit: an area ability caught a creature on its user's side (T13).
local function Captions(who, minions, allyHit)
    local list = {}
    local function Add(text, ended, style)
        list[#list + 1] = {text = text, ended = ended, style = style}
    end
    if allyHit then
        Add("Ally hit")
    end
    if who.state ~= nil then
        Add(STATE_CAPTIONS[who.state].text, nil, STATE_CAPTIONS[who.state].style)
    end
    for _, entry in ipairs(minions or {}) do
        Add(MinionWords(entry), nil, "historyDead")
    end
    if who.moved ~= nil then
        Add(MovedWords(who.moved))
    end
    if who.landedon then
        Add("Landed on")
    end
    if who.recovered ~= nil then
        Add(string.format("No longer %s", who.recovered), nil, "historyGood")
    end
    if who.types ~= nil then
        local names = {}
        for name in pairs(who.types) do
            names[#names + 1] = name
        end
        table.sort(names)
        if #names == 1 then
            Add(string.upper_first(names[1]))
        else
            local parts = {}
            for i, name in ipairs(names) do
                parts[i] = string.format("%d %s", who.types[name], name)
            end
            Add(table.concat(parts, ", "))
        end
    end
    local immunity = who.immunity
    if immunity ~= nil and immunity.amount > 0 then
        Add(string.format("%s immunity -%d", string.upper_first(immunity.damagetype), immunity.amount))
    elseif immunity ~= nil and immunity.amount < 0 then
        Add(string.format("%s weakness +%d", string.upper_first(immunity.damagetype), -immunity.amount))
    end
    if who.soaked ~= nil then
        Add(string.format("%d soaked by temporary Stamina", who.soaked))
    end
    if who.pool ~= nil then
        Add(string.format("temporary Stamina %d to %d", who.pool.before, who.pool.after))
    end
    for _, condition in ipairs(who.conds or {}) do
        if condition.icon == nil then
            Add(condition.name)
        end
    end
    if who.resisted then
        Add("Resisted")
    end
    for _, name in ipairs(who.immune or {}) do
        Add(string.format("Immune to %s", name))
    end
    for _, name in ipairs(who.ended or {}) do
        Add(name, true)
    end
    return list
end

--extraTaken: what triggers nested under this action added. A face shows everything
--the creature took from the action, so it agrees with the detail (fix B1).
--minions: confirmed minion deaths to show on this cell.
--allyHit: see Captions.
local function TargetCell(who, width, showTier, extraTaken, minions, allyHit)
    local textWidth = width - 45
    local top = {}
    if (who.taken or 0) > 0 then
        top[#top + 1] = Amount(who.taken + (extraTaken or 0), false, 16)
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
        lmargin = #top > 0 and 3 or 0,
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
    for _, caption in ipairs(Captions(who, minions, allyHit)) do
        below[#below + 1] = gui.Label{
            classes = {"historyCaption", caption.style},
            bgimage = cond(caption.style == "historyDead", "panels/square.png", nil),
            cornerRadius = 3,
            text = caption.text,
            width = "auto",
            maxWidth = textWidth,
            height = "auto",
            hpad = cond(caption.style == "historyDead", 3, 0),
            borderBox = true,
            halign = "left",
            valign = "center",
            rmargin = cond(caption.ended, 0, 8),
            textAlignment = "left",
        }
        if caption.ended then
            local tag = Tag("historyEndedTag", "Ended")
            tag.selfStyle.rmargin = 8
            below[#below + 1] = tag
        end
    end

    local face = Face(who, 36)
    face.flow = "none"
    for i, condition in ipairs(who.conds or {}) do
        if i <= 2 and condition.icon ~= nil then
            face:AddChild(ConditionBadge(condition, i))
        end
    end

    return gui.Panel{
        flow = "horizontal",
        width = width,
        height = "auto",
        halign = "left",
        vmargin = 2,
        face,
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

--"2 surges", but "1 surge". Every other resource name reads the same at any amount.
local function ResourceWords(amount, name)
    if amount == 1 and name == "surges" then
        return "1 surge"
    end
    return string.format("%d %s", amount, name)
end
History.ResourceWords = ResourceWords

--What makes a row open the card: the tooltip and the click (T19). The tooltip waits for
--the pointer to rest, because it would otherwise cover the next row on every pass.
local function OpensCard(item)
    return {
        linger = gui.Tooltip{text = "Open the detail", fontSize = 13},
        click = function(element)
            element.tooltip = nil
            if g_tray ~= nil then
                g_tray.Select(item)
            end
        end,
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

--The engine can't measure text before layout, so one-line rows estimate it per character.
--Generous: a row never wraps, a long name just shortens a little sooner.
local function TextWidth(text, perChar)
    return math.ceil(#text * perChar)
end

--Room for a trigger row: the action's text column, less the row's own left pad.
local TRIGGER_ROW_WIDTH = TRAY_WIDTH - 52 - 12 - 9

--The hairline above an action or a folded turn (the prototype's row separator).
local function Rule()
    return gui.Panel{
        classes = {"historyRule"},
        bgimage = "panels/square.png",
        width = "100%",
        height = 1,
    }
end

--A trigger nested under an action (T15), on one line: number, owner, Triggered or Free,
--"{Owner} . {trigger}", then after a caret what it did. The name shortens with "..." so the
--result stays in view; hovering the name shows it whole, and the card has the full sentence.
--entry.result is a change to the owner itself, such as "Clarity +1".
local function TriggerRow(index, entry)
    local tagText = cond(entry.ability.free, "Free", "Triggered")
    local used = 15 + 6 + TextWidth(tagText, 7.5) + 5
    --- @type Panel[]
    local children = {
        gui.Label{
            classes = {"historyTriggerNumber"},
            bgimage = "panels/square.png",
            text = tostring(index),
            width = 15,
            height = 15,
            cornerRadius = 7,
            halign = "left",
            valign = "center",
            textAlignment = "center",
        },
    }
    if entry.actor ~= nil then
        local face = Face(entry.actor, 20)
        face.selfStyle.lmargin = 6
        children[#children + 1] = face
        used = used + 26
    end
    children[#children + 1] = gui.Label{
        classes = {"historySmallCaps"},
        text = tagText,
        width = "auto",
        height = "auto",
        lmargin = 6,
        halign = "left",
        valign = "center",
    }

    --what it did, each part after a caret; resultWidth is their estimated width.
    local results = {}
    local resultWidth = 0
    local function AddCaret()
        results[#results + 1] = gui.Panel{
            classes = {"historyCaret"},
            bgimage = "phosphor/caret-right-bold.png",
            width = 9,
            height = 9,
            lmargin = 6,
            halign = "left",
            valign = "center",
        }
        resultWidth = resultWidth + 15
    end
    local function AddWords(text)
        results[#results + 1] = gui.Label{
            classes = {"historyTriggerResult"},
            text = text,
            width = "auto",
            height = "auto",
            lmargin = 4,
            textWrap = false,
            halign = "left",
            valign = "center",
        }
        resultWidth = resultWidth + 4 + TextWidth(text, 6.5)
    end
    local function AddAmount(value, healed)
        local amount = Amount(value, healed, 13)
        amount.selfStyle.lmargin = 3
        results[#results + 1] = amount
        resultWidth = resultWidth + 3 + TextWidth(tostring(value), 8) + 8
    end
    if entry.result ~= nil then
        AddCaret()
        AddWords(entry.result)
    end
    for _, who in ipairs(entry.targets) do
        local effects = {}
        for _, condition in ipairs(who.conds or {}) do
            effects[#effects + 1] = condition.name
        end
        for _, name in ipairs(who.ended or {}) do
            effects[#effects + 1] = name .. " ended"
        end
        if who.state ~= nil then
            effects[#effects + 1] = STATE_CAPTIONS[who.state].text
        end
        if who.moved ~= nil then
            effects[#effects + 1] = MovedWords(who.moved)
        end
        local taken, healed = who.taken or 0, who.healed or 0
        if taken > 0 or healed > 0 or #effects > 0 then
            AddCaret()
            local face = Face(who, 20)
            face.selfStyle.lmargin = 4
            results[#results + 1] = face
            resultWidth = resultWidth + 24
            if taken > 0 then
                AddAmount(taken, false)
            end
            if healed > 0 then
                AddAmount(healed, true)
            end
            if #effects > 0 then
                AddWords(table.concat(effects, ", "))
            end
        end
    end

    local name = (entry.actor ~= nil and (ShownName(entry.actor) .. DOT) or "") .. entry.ability.name
    children[#children + 1] = gui.Label{
        classes = {"historyTriggerText"},
        text = name,
        width = "auto",
        maxWidth = math.max(60, TRIGGER_ROW_WIDTH - used - resultWidth - 4),
        height = "auto",
        lmargin = 5,
        textWrap = false,
        textOverflow = "ellipsis",
        halign = "left",
        valign = "center",
        linger = gui.Tooltip{text = name, fontSize = 13},
    }
    for _, panel in ipairs(results) do
        children[#children + 1] = panel
    end
    --wrap only as a last resort, for results too wide for any line.
    return gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = "100%",
        height = "auto",
        lpad = 9,
        vmargin = 2,
        borderBox = true,
        children = children,
    }
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
        lmargin = item.showActor and 4 or 0, --auto width drops the space after the dot.
        halign = "left",
        valign = "center",
    }
    if tier ~= nil then
        titleChildren[#titleChildren + 1] = TierBadge(tier)
    end
    if entry.costs ~= nil then
        local names = {}
        for name in pairs(entry.costs) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local cost = entry.costs[name]
            titleChildren[#titleChildren + 1] = gui.Label{
                classes = {"historyChip", cost.style},
                bgimage = "panels/square.png",
                text = ResourceWords(cost.amount, name),
                width = "auto",
                height = 16,
                hpad = 6,
                borderBox = true,
                borderWidth = 1,
                cornerRadius = 8,
                lmargin = 5,
                halign = "left",
                valign = "center",
                textAlignment = "center",
            }
        end
    end

    local action = ACTION_WORDS[entry.ability.action]

    --what nested triggers added to each creature this action hit, and the confirmed
    --minion deaths, which go on the first cell of their squad.
    local extra = {}
    local triggers = {}
    local minions = {}
    for _, kid in ipairs(item.triggers or {}) do
        if kid.kind == "trigger" then
            triggers[#triggers + 1] = kid
            for _, who in ipairs(kid.targets) do
                extra[who.id] = (extra[who.id] or 0) + (who.taken or 0)
            end
        elseif kid.family == "resource" then
            triggers[#triggers + 1] = {
                actor = kid.who,
                ability = {name = kid.causetext or ""},
                result = string.format("%s %+d", kid.name, kid.amount),
                targets = {},
            }
        else
            for _, who in ipairs(entry.targets) do
                if who.squad == kid.name then
                    minions[who.id] = minions[who.id] or {}
                    table.insert(minions[who.id], kid)
                    break
                end
            end
        end
    end

    local inner = TRAY_WIDTH - 52 - 12
    local targets = entry.targets
    local cells = {}
    local function Cell(who, width)
        return TargetCell(who, width, tierPerTarget, extra[who.id], minions[who.id], History.IsAllyHit(entry, who))
    end
    if #targets == 1 then
        cells[1] = Cell(targets[1], inner)
    else
        local cellWidth = math.floor((inner - 10) / 2)
        local shown = cond(#targets > TARGET_CELLS, TARGET_CELLS - 1, #targets)
        for i = 1, shown do
            cells[#cells + 1] = Cell(targets[i], cellWidth)
        end
        if #targets > shown then
            local rest = {}
            for i = shown + 1, #targets do
                rest[#rest + 1] = targets[i]
            end
            cells[#cells + 1] = MoreCell(rest, cellWidth)
        end
    end

    local triggerRows = {}
    for i, kid in ipairs(triggers) do
        triggerRows[i] = TriggerRow(i, kid)
    end

    local opens = OpensCard(item)
    return gui.Panel{
        classes = {"historyFold"},
        bgimage = "panels/square.png",
        flow = "vertical",
        width = "100%",
        height = "auto",
        linger = opens.linger,
        click = opens.click,
        Rule(),
        gui.Panel{
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
                    rmargin = 14,
                    halign = "right",
                    valign = "center",
                } or nil,
                gui.Panel{
                    classes = {"historyChevron"},
                    bgimage = "phosphor/caret-right-bold.png",
                    width = 10,
                    height = 10,
                    halign = "right",
                    valign = "center",
                },
            },
            gui.Panel{
                flow = "horizontal",
                wrap = true,
                width = "100%",
                height = "auto",
                children = cells,
            },
            gui.Panel{
                flow = "vertical",
                width = "100%",
                height = "auto",
                tmargin = 3,
                children = triggerRows,
            },
        },
    }
end

--A result with no action behind it (L1-L24): who, what, and the cause under it.
local function LineWords(entry)
    local name = entry.who ~= nil and string.format("<b>%s</b>", ShownName(entry.who)) or ""
    local family = entry.family
    if family == "damage" then
        local kind = entry.damagetype ~= nil and (entry.damagetype .. " ") or ""
        return string.format("%s took %d %sdamage", name, entry.taken, kind)
    elseif family == "heal" then
        return string.format("%s regained %d Stamina", name, entry.healed)
    elseif family == "condition" then
        local duration = entry.duration ~= nil and string.format(" (%s)", entry.duration) or ""
        if entry.iscondition then
            return string.format("%s is %s%s", name, string.lower(entry.name), duration)
        end
        return string.format("%s %s%s", name, entry.name, duration)
    elseif family == "ended" then
        local names = entry.names
        if #names == 1 then
            return string.format("%s %s", name, names[1])
        end
        local most = {}
        for i = 1, #names - 1 do
            most[i] = names[i]
        end
        return string.format("%s %s and %s", name, table.concat(most, ", "), names[#names])
    elseif family == "save" then
        return string.format("%s %s %s", name, cond(entry.passed, "saved against", "failed a save against"), entry.name)
    elseif family == "persistence" then
        return string.format("%s stopped maintaining %s", name, entry.name)
    elseif family == "encounterend" then
        return "<b>Encounter ended</b>"
    elseif family == "threshold" then
        if entry.state == "killed" then
            return name .. " was killed"
        end
        return string.format("%s is %s", name, entry.state)
    elseif family == "minions" then
        return string.format("<b>%s</b> %d of %d minions killed", entry.name, entry.killed, entry.killed + entry.left)
    elseif family == "moved" then
        local moved = entry.moved
        local verb = MOVED_VERBS[string.gsub(moved.kind, "vertical_", "")] or "moved"
        local words = string.format("%s was %s %d %s", name, verb, moved.distance, cond(moved.distance == 1, "square", "squares"))
        if moved.fell > 0 then
            words = words .. string.format(", it fell %d %s", moved.fell, cond(moved.fell == 1, "square", "squares"))
        end
        return words
    elseif family == "resource" then
        return string.format("%s %s %s", name, cond(entry.amount > 0, "gained", "spent"), ResourceWords(math.abs(entry.amount), entry.name))
    elseif family == "malice" then
        if entry.who == nil then
            return "<b>Director</b> Malice"
        end
        return name .. " Malice"
    elseif family == "globalresource" then
        return string.format("<b>%s</b>", entry.name)
    end
    return name .. " temporary Stamina"
end

--The number at the end of a line. Nil for lines about something else.
local function LineNumber(entry)
    if entry.family == "damage" then
        return Amount(entry.taken, false, 14)
    elseif entry.family == "heal" then
        return Amount(entry.healed, true, 14)
    elseif entry.family == "temporarystamina" or entry.family == "malice" or entry.family == "globalresource" then
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
    return nil
end

local function BuildLine(item)
    local entry = item.entry
    local cause = entry.causetext
    if entry.recovered ~= nil then
        local recovered = string.format("No longer %s", entry.recovered)
        cause = cause ~= nil and (cause .. DOT .. recovered) or recovered
    end
    if entry.soaked ~= nil then
        local soaked = string.format("%d soaked by temporary Stamina", entry.soaked)
        cause = cause ~= nil and (cause .. DOT .. soaked) or soaked
    end

    --a line with no number can use the room kept for one.
    local number = LineNumber(entry)
    local leaveRoom = number ~= nil or entry.family == "resource"
    local rowWidth = TRAY_WIDTH - 52 - 12 - cond(leaveRoom, LINE_NUMBER_WIDTH, 0)
    local textWidth = rowWidth - 26
    local tag = nil
    if entry.family == "ended" then
        tag = Tag("historyEndedTag", "Ended")
    elseif entry.family == "save" and not entry.passed then
        tag = Tag("historyActiveTag", "Active")
    end

    --opacity does not reach a panel's children, so an undone line fades by its text colour.
    local top = {
        gui.Label{
            classes = {cond(entry.undone, "historyUndone", "historyLineText")},
            text = LineWords(entry),
            width = "auto",
            maxWidth = textWidth,
            height = "auto",
            halign = "left",
            valign = "center",
            textAlignment = "left",
        },
    }
    top[2] = tag

    local words = {
        gui.Panel{
            flow = "horizontal",
            wrap = true,
            width = "100%",
            height = "auto",
            children = top,
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

    local row = {}
    if entry.who ~= nil then
        row[1] = Face(entry.who, 18)
    end
    row[#row + 1] = gui.Panel{
        flow = "vertical",
        width = textWidth,
        height = "auto",
        lmargin = cond(entry.who ~= nil, 8, 0),
        halign = "left",
        valign = "center",
        children = words,
    }

    local children = {
        gui.Panel{
            flow = "horizontal",
            width = rowWidth,
            height = "auto",
            halign = "left",
            valign = "center",
            children = row,
        },
    }
    if number ~= nil then
        number.selfStyle.halign = "right"
        children[2] = number
    end

    --a resource line can be put back by whoever controls the creature (L42).
    local undoable = entry.family == "resource" and not entry.undone and entry.who ~= nil
    if undoable then
        local token = dmhub.GetCharacterById(entry.who.id)
        undoable = token ~= nil and token.canControl
    end
    if undoable then
        children[#children + 1] = gui.Label{
            classes = {"historyLineButton"},
            bgimage = "panels/square.png",
            text = "Undo",
            width = "auto",
            height = 18,
            hpad = 6,
            borderBox = true,
            borderWidth = 1,
            cornerRadius = 4,
            halign = "right",
            valign = "center",
            textAlignment = "center",
            click = function(element)
                History.UndoResource(entry)
            end,
        }
    end

    --the closing line of an encounter lists what ended on its card (L17).
    local opens = entry.family == "encounterend" and #(entry.ended or {}) > 0 and OpensCard(item) or nil
    return gui.Panel{
        classes = {"historyFold"},
        bgimage = "panels/square.png",
        flow = "none",
        width = "100%",
        height = "auto",
        lpad = 52,
        rpad = 12,
        vpad = 4,
        borderBox = true,
        linger = opens ~= nil and opens.linger or nil,
        click = opens ~= nil and opens.click or nil,
        children = children,
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
    local head = {
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "100%",
            halign = "left",
            children = title,
        },
    }
    if item.right ~= nil then
        head[2] = gui.Label{
            classes = {"historyMuted"},
            text = item.right,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
        }
    end
    return gui.Panel{
        classes = {cond(item.toggle ~= nil, "historyFold", "historyStill")},
        bgimage = "panels/square.png",
        flow = "vertical",
        width = "100%",
        height = "auto",
        click = item.toggle,
        gui.Panel{
            flow = "none",
            width = "100%",
            height = 30,
            hpad = 12,
            borderBox = true,
            valign = "center",
            children = head,
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
        flow = "vertical",
        width = "100%",
        height = "auto",
        click = item.toggle,
        Rule(),
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 29,
            hpad = 12,
            borderBox = true,
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
        },
    }
end

local function BuildTurnFold(item)
    return gui.Panel{
        classes = {"historyFold"},
        bgimage = "panels/square.png",
        flow = "vertical",
        width = "100%",
        height = "auto",
        click = item.toggle,
        Rule(),
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 35,
            hpad = 12,
            borderBox = true,
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
        },
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

local function Toggle(id, isOpen)
    return function()
        g_open[id] = not isOpen
        if g_tray ~= nil then
            g_tray.Refresh()
        end
    end
end

--What each creature took and regained across some entries, for a fold line.
local function Tally(entries, nested)
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
    local function AddEntry(entry)
        if entry.kind == "line" then
            Add(entry.who, entry.taken, entry.healed)
        else
            for _, who in ipairs(entry.targets or {}) do
                Add(who, who.taken, who.healed)
            end
        end
    end
    for _, entry in ipairs(entries) do
        AddEntry(entry)
        for _, kid in ipairs(nested[entry.id] or {}) do
            AddEntry(kid)
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

--The action a trigger or a minion death hangs from, following triggers set off by
--triggers. Nil when nothing it came from has a row: it stands alone in its turn.
local function RootAction(entry, rowsById)
    local parent = rowsById[entry.cause]
    for _ = 1, 8 do
        if parent == nil or parent.kind ~= "trigger" then
            break
        end
        parent = rowsById[parent.cause]
    end
    if parent ~= nil and parent.kind == "action" then
        return parent
    end
    return nil
end

--Groups entries, oldest first, into sections (a round, or a stretch out of combat)
--holding turns holding entries. Out of combat has no round, so an encounter between
--two stretches keeps them apart, and each takes its id from its first entry.
--Also returns what is nested under each action, by the action's id.
local function BuildSections(mapid)
    local keys = History.Keys(mapid)
    local rowsById = {}
    for _, key in ipairs(keys) do
        local entry = History.Entry(mapid, key)
        if entry ~= nil then
            rowsById[entry.id] = entry
            for _, alias in ipairs(entry.aliases or {}) do
                rowsById[alias] = entry
            end
        end
    end

    local sections = {}
    local nested = {}
    local section = nil
    local turn = nil
    for _, key in ipairs(keys) do
        local entry = History.Entry(mapid, key)
        local root = nil
        if entry ~= nil and entry.cause ~= nil then
            root = RootAction(entry, rowsById)
        end
        if root ~= nil then
            nested[root.id] = nested[root.id] or {}
            table.insert(nested[root.id], entry)
        elseif entry ~= nil and (entry.family ~= "malice" or dmhub.isDM) then
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
            if entry.family == "malice" then
                section.maliceBefore = section.maliceBefore or entry.before
                section.maliceAfter = entry.after
            end
            if not entry.quiet then
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
    end
    return sections, nested
end

local function SectionTitle(section)
    if section.round == nil then
        return "Out of combat"
    end
    return string.format("Round %d", section.round)
end

--The damage type of a target hit by one type only, else nil.
local function OnlyType(who)
    local only = next(who.types or {})
    if only ~= nil and next(who.types, only) == nil then
        return only
    end
    return nil
end

--A trigger with no action to nest under reads as lines naming the feature, one for
--each thing it did. These are the same words as any other line.
local function AddLoneTrigger(items, entry, key)
    local causetext = entry.ability.name
    if entry.landedby ~= nil then
        causetext = string.format("Landed on by %s", ShownName(entry.landedby))
    end
    for i, who in ipairs(entry.targets) do
        local base = {kind = "line", who = who, causetext = causetext}
        local parts = {}
        if (who.taken or 0) > 0 then
            parts[#parts + 1] = {family = "damage", taken = who.taken, soaked = who.soaked, damagetype = OnlyType(who)}
        end
        if (who.healed or 0) > 0 then
            parts[#parts + 1] = {family = "heal", healed = who.healed}
        end
        if who.pool ~= nil then
            parts[#parts + 1] = {family = "temporarystamina", before = who.pool.before, after = who.pool.after}
        end
        for _, condition in ipairs(who.conds or {}) do
            parts[#parts + 1] = {
                family = "condition",
                name = condition.name,
                iscondition = condition.iscondition,
                duration = condition.duration,
            }
        end
        if who.ended ~= nil then
            parts[#parts + 1] = {family = "ended", names = who.ended}
        end
        if who.state ~= nil then
            parts[#parts + 1] = {family = "threshold", state = who.state}
        end
        if who.moved ~= nil then
            parts[#parts + 1] = {family = "moved", moved = who.moved}
        end
        for j, part in ipairs(parts) do
            for k, v in pairs(base) do
                part[k] = v
            end
            items[#items + 1] = {
                kind = "line",
                key = string.format("%s-%d-%d", key, i, j),
                sig = entry,
                entry = part,
            }
        end
    end
end

local function AddTurnRows(items, turn, isNewest, nested)
    local isOpen = g_open[turn.id]
    if isOpen == nil then
        isOpen = g_showAll or isNewest
    end
    local toggle = Toggle(turn.id, isOpen)
    if turn.owner ~= nil then
        if not isOpen then
            local tally = Tally(turn.entries, nested)
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
        local last = items[#items]
        if entry.kind == "line" and entry.family == "ended" and last ~= nil and last.kind == "line"
            and last.entry.family == "ended" and last.entry.who.id == entry.who.id
            and last.entry.causetext == entry.causetext then
            --ended a moment apart, for the same reason: one line (L8).
            local names = table.shallow_copy(last.entry.names)
            for _, name in ipairs(entry.names) do
                names[#names + 1] = name
            end
            last.entry = {family = "ended", kind = "line", who = entry.who, causetext = entry.causetext, names = names}
            last.sig = table.concat(names, ",")
        elseif entry.kind == "line" then
            items[#items + 1] = {kind = "line", key = turn.keys[i], sig = entry, entry = entry}
        elseif entry.kind == "trigger" then
            AddLoneTrigger(items, entry, turn.keys[i])
        else
            local triggers = nested[entry.id]
            local sig = entry
            if triggers ~= nil then
                local ids = {tostring(entry)}
                for _, kid in ipairs(triggers) do
                    ids[#ids + 1] = kid.id
                end
                sig = table.concat(ids, ",")
            end
            items[#items + 1] = {
                kind = "action",
                key = turn.keys[i],
                sig = sig,
                entry = entry,
                triggers = triggers,
                showActor = turn.owner == nil or entry.actor.id ~= turn.owner.id,
            }
        end
    end
end

local function AddSectionRows(items, section, isNewest, nested)
    local isOpen = g_open[section.id]
    if isOpen == nil then
        isOpen = g_showAll or isNewest
    end
    local title = SectionTitle(section)
    if not isOpen then
        local tally = Tally(section.entries, nested)
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

    local right = nil
    if section.maliceAfter ~= nil then
        right = string.format("Malice %d to %d", section.maliceBefore, section.maliceAfter)
    end

    --the newest section stays open, so it has nothing to fold to.
    items[#items + 1] = {
        kind = "roundhead",
        key = "head-" .. section.id,
        sig = title .. (right or ""),
        text = title,
        right = right,
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
        local tally = Tally(entries, nested)
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
        AddTurnRows(items, turns[i], isNewest and i == #turns, nested)
    end
end

local function BuildItems(mapid)
    local items = {}
    local sections, nested = BuildSections(mapid)
    for i, section in ipairs(sections) do
        AddSectionRows(items, section, i == #sections, nested)
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

    --The row whose card is open, the card, and where it was put.
    --- @type {key: string, sig: any, item: table}|nil
    local selected = nil
    --- @type Panel|nil
    local card = nil
    --- @type {x: number, width: number, maxHeight: number, inTray: boolean}|nil
    local cardPlace = nil

    --Where the rail window sits on the screen layer, in layer units, with the top of this
    --face (below the window's header). Nil in a popped-out window: it has no room beside it.
    --- @return {x: number, top: number, w: number, scale: number, layerWidth: number, layerHeight: number}|nil
    local function WindowRect()
        local dialog = face:FindParentWithClass("panelDocumentWindow")
        local hud = GameHud.instance
        if PanelDocument.IsPoppedOut("history") or dialog == nil or not hud or hud.documentsPanel == nil or not hud.documentsPanel.valid then
            return nil
        end
        local layer = hud.documentsPanel
        local scale = dialog.data.windowScale or 1
        return {
            x = dialog.x,
            top = dialog.y + (dialog.renderedHeight - face.renderedHeight) * scale,
            w = dialog.renderedWidth * scale,
            scale = scale,
            layerWidth = layer.renderedWidth - RailRightColumnWidth(),
            layerHeight = layer.renderedHeight,
        }
    end

    --Beside the window on the side with room, else over the list with a way back (B7).
    local function CardPlace()
        local rect = WindowRect()
        if rect ~= nil then
            local needed = (History.CARD_WIDTH + CARD_GAP) * rect.scale
            local x = nil
            if rect.x + rect.w + needed <= rect.layerWidth then
                x = face.renderedWidth + CARD_GAP
            elseif rect.x - needed >= RAIL_LEFT then
                x = -(History.CARD_WIDTH + CARD_GAP)
            end
            if x ~= nil then
                --the card slides up or down to stay on the screen, so the screen's height bounds it.
                local room = math.floor((rect.layerHeight - 2 * CARD_GAP) / rect.scale)
                return {x = x, width = History.CARD_WIDTH, maxHeight = math.min(room, CARD_HEIGHT), inTray = false}
            end
        end
        return {x = 0, width = TRAY_WIDTH, maxHeight = face.renderedHeight, inTray = true}
    end

    local Select

    local function DropCard()
        if card ~= nil and card.valid then
            local tail = card.data.tail
            if tail ~= nil and tail.valid then
                tail:DestroySelf()
            end
            card:DestroySelf()
        end
        card = nil
    end

    local function ShowCard(item)
        DropCard()
        local place = CardPlace()
        cardPlace = place
        card = History.CreateCard{
            entry = item.entry,
            kids = item.triggers,
            x = place.x,
            width = place.width,
            maxHeight = place.maxHeight,
            inTray = place.inTray,
            tail = not place.inTray and cond(place.x > 0, "left", "right") or nil,
            close = function()
                Select(nil)
            end,
        }
        --the tail goes in first, so the card covers its inner half.
        if card.data.tail ~= nil then
            face:AddChild(card.data.tail)
        end
        face:AddChild(card)
        --line it up once it has a height (layout takes a frame or two).
        face:ScheduleEvent("alignCard", 0.03)
        face:ScheduleEvent("alignCard", 0.15)
    end

    --Lines the card up with its row and points the tail at it. Runs when the card opens,
    --when the list scrolls and once a second; the row's place comes from its distance
    --to the screen's edges (x left, y bottom, z right, w top, in screen pixels).
    local function AlignCard()
        if card == nil or not card.valid or cardPlace == nil or cardPlace.inTray or selected == nil then
            return
        end
        local row = rows[selected.key]
        local rect = WindowRect()
        local tail = card.data.tail
        if row == nil or not row.panel.valid or rect == nil or tail == nil or not tail.valid then
            return
        end
        local faceEdges = face.distancesToScreenEdge
        local faceScreenHeight = dmhub.screenHeight - faceEdges.w - faceEdges.y
        if faceScreenHeight <= 0 then
            return
        end
        --screen pixels to this face's own units.
        local k = face.renderedHeight / faceScreenHeight
        local rowTop = (row.panel.distancesToScreenEdge.w - faceEdges.w) * k
        local listTop = (list.distancesToScreenEdge.w - faceEdges.w) * k
        local listBottom = listTop + list.renderedHeight
        local target = rowTop + ROW_TITLE

        --as close to level as the screen allows; a row scrolled out of sight holds the card
        --at the edge of the list rather than leaving it beside nothing.
        local inSight = target >= listTop and target <= listBottom
        local level = math.max(listTop, math.min(target, listBottom))
        local cardHeight = card.renderedHeight
        local minY = CARD_GAP - rect.top / rect.scale
        local maxY = (rect.layerHeight - rect.top) / rect.scale - CARD_GAP - cardHeight
        local y = math.max(minY, math.min(level - TAIL_DOWN, maxY))
        card.y = y

        --no tail when its row is out of sight, or the card couldn't reach it.
        local tailCenter = target - y
        local shown = inSight and tailCenter >= 14 and tailCenter <= cardHeight - 14
        tail:SetClass("collapsed", not shown)
        tail.y = y + tailCenter - tail.renderedHeight / 2
    end

    --The tray moved or changed height, or the table did: the card may need a new place.
    local function KeepCardPlaced()
        if selected ~= nil and cardPlace ~= nil then
            local place = CardPlace()
            if place.x ~= cardPlace.x or place.maxHeight ~= cardPlace.maxHeight then
                ShowCard(selected.item)
            end
        end
    end

    local function MarkRow(key, isSelected)
        local row = rows[key]
        if row ~= nil and row.panel.valid then
            row.panel:SetClass("historySelected", isSelected)
        end
    end

    --Opens a row's card, one at a time. The open row closes it again, and so does nil.
    Select = function(item)
        local wasOpen = selected ~= nil and item ~= nil and selected.key == item.key
        if selected ~= nil then
            MarkRow(selected.key, false)
        end
        DropCard()
        selected = nil
        if item ~= nil and not wasOpen then
            selected = {key = item.key, sig = item.sig, item = item}
            MarkRow(item.key, true)
            ShowCard(item)
        end
    end

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
            row.panel:SetClass("historySelected", selected ~= nil and selected.key == item.key)
        end
        rows = kept
        rowsPanel.children = children
        if stick and not loadingOlder then
            list:ScheduleEvent("toBottom", 0.02)
        end

        --a trigger landing after the row closed changes what the open card says.
        if selected ~= nil then
            for _, item in ipairs(items) do
                if item.key == selected.key then
                    if item.sig ~= selected.sig then
                        selected.sig = item.sig
                        selected.item = item
                        ShowCard(item)
                    end
                    break
                end
            end
        end
    end

    list = gui.Panel{
        flow = "vertical",
        width = TRAY_WIDTH,
        height = string.format("100%%-%d", BAR_HEIGHT),
        halign = "left",
        vscroll = true,
        rowsPanel,

        toBottom = function(element)
            element.vscrollPosition = 0
        end,

        --at the top with more to show: build the next rows and hold the view still.
        scroll = function(element)
            AlignCard()
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
            rowsWanted = ROWS_CHUNK
            Refresh()
            KeepCardPlaced()
            list:ScheduleEvent("toBottom", 0.05)
        end,
    }

    --No background of its own: the rail window's frame shows through.
    face = gui.Panel{
        classes = {"historyTray"},
        styles = ThemeEngine.MergeStyles(Styles()),
        flow = "vertical",
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",

        monitorGame = History.DocPath(mapid),
        refreshGame = Refresh,

        --the tray shows the map you are on; following the last clicked map is chunk 6.1.
        thinkTime = 1,
        think = function(element)
            if game.currentMapId ~= mapid then
                mapid = game.currentMapId
                g_open = {}
                rowsWanted = ROWS_CHUNK
                Select(nil)
                element.monitorGame = History.DocPath(mapid)
                Refresh()
            end
            KeepCardPlaced()
            AlignCard()
        end,

        alignCard = function(element)
            AlignCard()
        end,

        destroy = function()
            if g_tray ~= nil and g_tray.face == face then
                g_tray = nil
            end
        end,

        --the window's own header names the panel, so this bar only holds Show all.
        gui.Panel{
            flow = "none",
            width = TRAY_WIDTH,
            height = BAR_HEIGHT,
            halign = "left",
            rpad = 12,
            borderBox = true,
            showAllButton,
        },
        list,
    }

    g_tray = {face = face, Refresh = Refresh, Select = Select}
    list.vscrollPosition = 0
    Refresh()
    return face
end

ThemeEngine.OnThemeChanged(mod, function()
    if g_tray ~= nil and g_tray.face.valid then
        g_tray.face.styles = ThemeEngine.MergeStyles(Styles())
    end
end)

--A rail panel like Chat, so it gets the rail windows' frame, pin, pop out and Font Size zoom.
DockablePanel.Register{
    name = "History",
    icon = "phosphor/clock-counter-clockwise-bold.png",
    available = History.Enabled,
    vscroll = false,
    minHeight = 200,
    --the rows are laid out for one width; narrow windows are chunk 6.3.
    defaultWidth = TRAY_WIDTH + EDGE_STRIP,
    minWidth = TRAY_WIDTH + EDGE_STRIP,
    maxWidth = TRAY_WIDTH + EDGE_STRIP,
    resizableWidth = false,
    content = function()
        return CreateFace()
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
