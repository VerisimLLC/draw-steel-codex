local mod = dmhub.GetModLoading()

--The History tray: a rail panel window that shows a map's History as rounds and turns,
--newest at the bottom. Older rounds and turns fold away, so opening it builds a few
--rows even after a long fight.
--
--Each refresh works out the list of rows from the entries, then keeps every row whose
--signature is unchanged and builds only what is new. A new action builds one row.

--The window's width range, and its width when it first opens. The window adds
--EDGE_STRIP on the right, where its resize strip sits, so the scroll bar stays clear of it.
local TRAY_MIN_WIDTH = 320
local TRAY_MAX_WIDTH = 600
local TRAY_DEFAULT_WIDTH = 410
local EDGE_STRIP = 8

--The width rows are laid out for: the open window's, once a resize has settled. Rows
--shorten names by estimated text widths, so a new width rebuilds them.
local g_trayWidth = TRAY_DEFAULT_WIDTH

--The bar above the list that holds search and the "my hero" faces.
local BAR_HEIGHT = 28
local SEARCH_GAP = 8

--Rows built at first; scrolling up adds this many more each time. Building only a few
--more than fit keeps a long fight quick to open. Tall windows get more (fillView).
local ROWS_CHUNK = 12

--Turns of the newest round that stay apart from the "Turns a-b" fold.
local NEWEST_TURNS = 4

--Target faces on a fold line before "+N".
local FOLD_FACES = 5

--Targets on an action before the last cell becomes "+N".
local TARGET_CELLS = 4

--The Codex's fonts have these two characters; they are byte escapes because Lua source
--must stay ASCII.
local DOT = " \194\183 "
local EN_DASH = "\226\128\147"

--Room kept beside an action's title for the longest of these words.
local ACTION_WORDS_WIDTH = 92

--Room kept at the end of a line for its number, "120 to 135" at the longest.
local LINE_NUMBER_WIDTH = 70
--Room beside a line's number for its Undo button.
local UNDO_WIDTH = 50

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

--The open tray: {face, Refresh, Select, SetSearch, ShowEntry, ShowMap, MapId}.
local g_tray = nil
--A row to show once the window is built: the Sidebar Preview's click opens History on it.
--- @type string|nil
local g_showOnOpen = nil
--That row's map, which can be one the user is not on.
--- @type string|nil
local g_showMapOnOpen = nil

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
        --a round under a Combat heading: quieter than the heading it sits in.
        {
            selectors = {"label", "historyRoundTitle"},
            fontSize = 11,
            bold = true,
            uppercase = true,
            color = "@fgMuted",
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
            selectors = {"label", "historyTier", "historyTierOverridden"},
            color = "@warning",
            borderColor = "@warning",
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
        --the map switcher in the title row, drawn like the tray's other buttons.
        {
            selectors = {"historyMapSwitcher"},
            bgcolor = "clear",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"historyMapSwitcher", "hover"},
            borderColor = "@fgMuted",
        },
        {
            selectors = {"label", "historyMapName"},
            fontSize = 12,
            color = "@fg",
        },
        {
            selectors = {"historyMapIcon"},
            bgcolor = "@fgMuted",
        },
        --floats over the rows, so it needs a fill of its own.
        {
            selectors = {"label", "historyNewBelow"},
            bgcolor = "@bgRaised",
            color = "@fg",
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
        --a turn pip still to use is filled, like the action bar's; a used one greys out.
        {
            selectors = {"label", "historyChip", "historyPip"},
            color = "@bg",
            bgcolor = "@fg",
            borderColor = "@fg",
        },
        {
            selectors = {"label", "historyChip", "historyPip", "historyPipUsed"},
            color = "@fgMuted",
            bgcolor = "clear",
            borderColor = "@borderSolid",
            opacity = 0.6,
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
        --a row the fold animation's stand-in is flying to, hidden until it lands.
        {
            selectors = {"historyFoldHidden"},
            opacity = 0,
        },
        --and fades in under the stand-in as it fades out (the fold's last quarter).
        {
            selectors = {"historyFoldReveal"},
            opacity = 1,
            transitionTime = 0.22,
            easing = "easeInOutSine",
        },
        --a spend on an action's row: the resource's icon and the number, in its chip's colour.
        {
            selectors = {"label", "historyCost"},
            fontSize = 12,
            bold = true,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyCost", "historyChipHeroic"},
            color = "@info",
        },
        {
            selectors = {"label", "historyCost", "historyChipSurge"},
            color = "@warning",
        },
        {
            selectors = {"label", "historyCost", "historyChipMalice"},
            color = "@danger",
        },
        {
            selectors = {"historyCostIcon"},
            bgcolor = "white",
        },
        {
            selectors = {"historyCostIcon", "historyChipSurge"},
            bgcolor = "@warning",
        },
        {
            selectors = {"historyCostIcon", "historyChipMalice"},
            bgcolor = "@danger",
        },
        {
            selectors = {"label", "historyUndone"},
            color = "@fgMuted",
        },
        --a row Revert Turn or Turn Rewind undid: every panel in it fades and its
        --words are struck through, all but its Reverted tag.
        {
            selectors = {"historyFaded"},
            opacity = 0.45,
        },
        {
            selectors = {"label", "historyFaded"},
            strikethrough = true,
        },
        {
            selectors = {"label", "historyRevertedTag"},
            fontSize = 11,
            bold = true,
            uppercase = true,
            color = "@fgMuted",
            bgcolor = "clear",
            borderColor = "@fgMuted",
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
        --a villain action: outlined in the Malice chip's red, apart from a filled Failure.
        {
            selectors = {"label", "historyVillainTag"},
            fontSize = 11,
            bold = true,
            uppercase = true,
            color = "@danger",
            bgcolor = "clear",
            borderColor = "@danger",
        },
        {
            selectors = {"label", "historySuccessTag"},
            fontSize = 11,
            bold = true,
            uppercase = true,
            color = "@bg",
            bgcolor = "@success",
        },
        {
            selectors = {"label", "historyFailureTag"},
            fontSize = 11,
            bold = true,
            uppercase = true,
            color = "@bg",
            bgcolor = "@danger",
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
            selectors = {"historyActiveFrame"},
            bgcolor = "@warning",
        },
        {
            selectors = {"historyNewLine"},
            bgcolor = "@warning",
        },
        {
            selectors = {"label", "historyNewText"},
            fontSize = 11,
            bold = true,
            color = "@warning",
        },
        {
            selectors = {"historyActiveIcon"},
            bgcolor = "@bg",
        },
        {
            selectors = {"historyBadge"},
            bgcolor = "@bg",
            borderColor = "@borderSolid",
        },
        --the search bar, its chips and its suggestions.
        {
            selectors = {"label", "historySearchCount"},
            fontSize = 11,
            color = "@fgMuted",
        },
        {
            selectors = {"historySearchChip"},
            bgcolor = "@borderSolid",
        },
        {
            selectors = {"label", "historySearchChipText"},
            fontSize = 12,
            color = "@fgStrong",
        },
        {
            selectors = {"historySearchX"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"historySearchX", "hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"historySuggestions"},
            bgcolor = "@bg",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"label", "historySuggestGroup"},
            fontSize = 11,
            uppercase = true,
            color = "@fgMuted",
        },
        {
            selectors = {"historySuggestRow"},
            bgcolor = "clear",
        },
        {
            selectors = {"historySuggestRow", "hover"},
            bgcolor = "@borderSolid",
        },
        {
            selectors = {"historySuggestRow", "searchfocus"},
            bgcolor = "@borderSolid",
        },
        {
            selectors = {"label", "historySuggestText"},
            fontSize = 13,
            color = "@fg",
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
        {
            selectors = {"historySideView"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"historySideView", "hover"},
            bgcolor = "@fgStrong",
        },
        --solid on purpose: with Transparent UI, a see-through fill shows the table behind
        --the window rather than a lighter row.
        {
            selectors = {"historyFold", "historySelected"},
            bgcolor = "@bgRaised",
        },
        --@border is white at 16% in the default theme: the seam under a round heading
        --comes to 12%, the line between rows to 5%.
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
        --the same frame as the rail windows, so the card matches History; its blurred
        --backdrop is set on the panel.
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
        --The numbers (the receipt in the card).
        {
            selectors = {"label", "historyReceipt"},
            fontSize = 14,
            color = "@fg",
        },
        {
            selectors = {"label", "historyReceiptValue"},
            fontSize = 14,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = {"label", "historyReceiptValue", "historyHurt"},
            color = "@danger",
        },
        {
            selectors = {"label", "historyReceiptValue", "historyHealed"},
            color = "@success",
        },
        {
            selectors = {"label", "historyReceiptAside"},
            fontSize = 13,
            color = "@fgMuted",
        },
        {
            --a source line: dimmer than the receipt's lines, brighter than its notes.
            selectors = {"label", "historyReceiptSource"},
            fontSize = 13,
            color = "@fg",
            opacity = 0.8,
        },
        {
            --a Why line: a rule down its left, a bold lead, a plain sentence.
            selectors = {"historyWhy"},
            bgcolor = "clear",
            borderColor = "@fgMuted",
        },
        {
            selectors = {"historyWhy", "historyWhyQuiet"},
            borderColor = "@border",
        },
        {
            selectors = {"label", "historyWhyLead"},
            fontSize = 14,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = {"label", "historyWhyText"},
            fontSize = 14,
            color = "@fg",
        },
        {
            selectors = {"label", "historyWhyPlain"},
            fontSize = 14,
            italics = true,
            color = "@fgMuted",
        },
        {
            --the roll dialog's surge bolt, in front of "Spent 2 surges".
            selectors = {"historySurgeIcon"},
            bgcolor = "@fg",
        },
        {
            --an edge or bane that did not count, crossed out; its value drops out of the column.
            selectors = {"label", "historyStruck"},
            strikethrough = true,
        },
        {
            selectors = {"label", "historyReceiptValue", "historyStruck"},
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyReceiptNote"},
            fontSize = 12,
            italics = true,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "historyReceiptMore"},
            fontSize = 12,
            color = "@fg",
        },
        {
            selectors = {"historyReceiptRule"},
            bgcolor = "@border",
        },
        {
            selectors = {"label", "historyDie"},
            fontSize = 12,
            bold = true,
            color = "@fgStrong",
            bgcolor = "@bgRaised",
            borderColor = "@borderSolid",
        },
        {
            selectors = {"historyEdgeIcon"},
            bgcolor = "@success",
        },
        {
            selectors = {"historyBaneIcon"},
            bgcolor = "@danger",
        },
        {
            selectors = {"label", "historyEdgeText"},
            color = "@success",
        },
        {
            selectors = {"label", "historyBaneText"},
            color = "@danger",
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
        --a "my hero" face beside search while its filter is the search: the amber of the
        --names the search highlights (the default theme's accent is the hero ring's colour).
        {
            selectors = {"historyMyHeroOn"},
            priority = 5,
            borderColor = "@warning",
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

--The face under the pointer, if any. Only one tooltip shows at a time, so a row holds
--back its own "Open the detail" while a face is showing its name.
--- @type Panel|nil
local g_faceHovered = nil

--When the Director last chose from a row's menu. The same click goes on to the row under
--the menu, which must not open its card.
local g_menuChosenAt = -1

--The creature's token, if it is on the map shown and this user can see it there. History
--must not point at a creature the user could not find by looking.
--- @param who HistoryCreature
--- @return CharacterToken|nil
local function TokenInSight(who)
    local token = dmhub.GetTokenById(who.id)
    if token ~= nil and token.valid and token.canSee then
        return token
    end
    return nil
end

--The token wearing the "locate" ring for a hovered face, if any. One at a time.
--- @type string|nil
local g_ringedTokenId = nil

--Puts the amber "locate" ring (styled in TokenUI.lua, shared with the action bar) on one
--token, or takes it off with nil. The engine's own pulse is too brief to see.
--- @param token CharacterToken|nil
local function RingToken(token)
    local tokenid = token ~= nil and token.charid or nil
    if tokenid == g_ringedTokenId then
        return
    end
    if g_ringedTokenId ~= nil then
        local old = dmhub.GetTokenById(g_ringedTokenId)
        if old ~= nil and old.valid and old.bottomsheet ~= nil and old.bottomsheet.valid then
            old.bottomsheet:SetClassTree("locate", false)
        end
    end
    g_ringedTokenId = nil
    if token ~= nil and token.bottomsheet ~= nil and token.bottomsheet.valid then
        token.bottomsheet:SetClassTree("locate", true)
        g_ringedTokenId = tokenid
    end
end

--A round portrait from a snapshot, with a ring that says which side it is on. Hovering
--it names the creature at once (on fold lines and trigger results the face is all there
--is) and rings its token on the map for as long as the pointer stays.
--- @param who HistoryCreature
--- @param size number
--- @param centres boolean|nil A click centres the map on the creature (the detail card's
--- faces; in the list a click belongs to the row, which opens its card).
--- @param button {tip: (fun(): string), click: fun()}|nil Makes the face a button: tip is
--- its hover text in place of the name (asked on each hover, so it can change), click its press.
--- @return Panel
local function Face(who, size, centres, button)
    local rect = who.rect
    local name = gui.Tooltip{text = ShownName(who), fontSize = 13}
    --- @param element Panel
    local function ShowTip(element)
        local tip = name
        if button ~= nil then
            tip = gui.Tooltip{text = button.tip(), fontSize = 13}
        end
        if tip ~= nil then
            tip(element)
        end
    end
    local click = nil
    if button ~= nil then
        --the press changes what the next press does, so say so without a re-hover.
        click = function(element)
            button.click()
            if g_faceHovered == element and element.valid then
                ShowTip(element)
            end
        end
    elseif centres then
        click = function(element)
            local token = TokenInSight(who)
            if token ~= nil then
                dmhub.CenterOnToken(token.charid)
            end
        end
    end
    return gui.Panel{
        hover = function(element)
            g_faceHovered = element
            ShowTip(element)
            RingToken(TokenInSight(who))
        end,
        click = click,
        dehover = function(element)
            if g_faceHovered == element then
                g_faceHovered = nil
                RingToken(nil)
            end
        end,
        --a row rebuilt under the pointer is destroyed without a dehover.
        destroy = function(element)
            if g_faceHovered == element then
                g_faceHovered = nil
                RingToken(nil)
            end
        end,
        classes = {cond(who.hero, "historyHero", "historyFoe")},
        width = size,
        height = size,
        halign = "left",
        valign = "center",
        bgimage = who.img,
        bgcolor = "white",
        cornerRadius = size / 2,
        --a 2 px ring takes a fifth of a small face, so those get 1 px.
        borderWidth = size < 26 and 1 or 2,
        imageRect = rect ~= nil and {x1 = rect[1], y1 = rect[2], x2 = rect[3], y2 = rect[4]} or nil,
    }
end

History.Face = Face

--Small marks beside a name. Ended is the partner of Active: one for what stopped, one
--for what is still on.
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
        borderWidth = cond(style == "historyEndedTag" or style == "historyVillainTag" or style == "historyRevertedTag", 1, 0),
        lmargin = 5,
        halign = "left",
        valign = "center",
        textAlignment = "center",
    }
end

--Active with the icon of what is still on, so a cell with two badges says which.
--- @param icon string|nil
--- @return Panel
local function ActiveTag(icon)
    if icon == nil then
        return Tag("historyActiveTag", "Active")
    end
    return gui.Panel{
        classes = {"historyActiveFrame"},
        bgimage = "panels/square.png",
        flow = "horizontal",
        width = "auto",
        height = 14,
        lpad = 1,
        rpad = 4,
        borderBox = true,
        cornerRadius = 3,
        lmargin = 5,
        halign = "left",
        valign = "center",
        gui.Panel{
            classes = {"historyActiveIcon"},
            bgimage = "panels/square.png",
            width = 12,
            height = 12,
            cornerRadius = 6,
            rmargin = 2,
            valign = "center",
            gui.Panel{
                bgimage = icon,
                bgcolor = "white",
                width = 10,
                height = 10,
                halign = "center",
                valign = "center",
            },
        },
        gui.Label{
            classes = {"historyActiveTag"},
            text = "Active",
            width = "auto",
            height = "auto",
            valign = "center",
            bgcolor = "clear",
        },
    }
end

History.ActiveTag = ActiveTag

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

--- The tier pill. overridden: someone chose this tier after the dice landed; it is
--- drawn in the warning colour and says so on hover, and the card says who and what the
--- dice gave.
--- @param tier integer
--- @param overridden boolean|nil
--- @return Panel
local function TierBadge(tier, overridden)
    return gui.Label{
        classes = {"historyTier", overridden and "historyTierOverridden" or nil},
        --like a face, it holds back the row's own "Open the detail" while it shows its word.
        hover = overridden and function(element)
            g_faceHovered = element
            gui.Tooltip{text = "Overridden", fontSize = 13}(element)
        end or nil,
        dehover = overridden and function(element)
            if g_faceHovered == element then
                g_faceHovered = nil
            end
        end or nil,
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
History.TierBadge = TierBadge

--The engine can't measure text before layout, so one-line rows estimate it per character.
--Generous: a row never wraps, a long name just shortens a little sooner.
local function TextWidth(text, perChar)
    return math.ceil(#text * perChar)
end

--The faces on a fold line, each with what it took and regained. Damage and healing stay
--apart, so 9 taken and 8 healed never reads as -1. room: the width left on the
--line; faces that don't fit, or past FOLD_FACES, become "+N".
local function MiniFaces(tally, room)
    local children = {}
    local used = 4
    --faces that share a portrait (four goblins) get a number each, in the order they
    --appear, so the line reads without a hover.
    local byImage = {}
    for _, row in ipairs(tally) do
        local img = row.who.img or ""
        byImage[img] = (byImage[img] or 0) + 1
    end
    local numbered = {}
    for i, row in ipairs(tally) do
        local width = 23 + 8
        for _, amount in ipairs({row.taken, row.healed}) do
            if amount > 0 then
                width = width + TextWidth(tostring(amount), 8) + 8 + 3
            end
        end
        --room for a "+N" after this face, unless it is the last.
        local after = i < #tally and 28 or 0
        if i > FOLD_FACES or used + width + after > room then
            children[#children + 1] = gui.Label{
                classes = {"historyMuted"},
                text = string.format("+%d", #tally - i + 1),
                width = "auto",
                height = 20,
                valign = "center",
                textAlignment = "left",
            }
            break
        end
        used = used + width
        --the line's own hover names everyone (FoldHover), so the faces take no hover.
        local face = Face(row.who, 20)
        local img = row.who.img or ""
        if byImage[img] > 1 then
            numbered[img] = (numbered[img] or 0) + 1
            face.flow = "none"
            face:AddChild(gui.Label{
                classes = {"historyTriggerNumber"},
                bgimage = "panels/square.png",
                floating = true,
                text = tostring(numbered[img]),
                fontSize = 8,
                width = 11,
                height = 11,
                cornerRadius = 5,
                halign = "right",
                valign = "bottom",
                x = 3,
                y = 3,
                textAlignment = "center",
            })
        end
        face:MakeNonInteractiveRecursive()
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

--The hover on a folded line: every creature its faces stand for, one line each with
--the name and what it took and regained, since the line only has room for some of them.
--- @param title string The fold line's own words, as the card's heading.
--- @return nil|fun(element: Panel)
local function FoldHover(title, tally)
    if tally == nil or #tally == 0 then
        return nil
    end
    return function(element)
        --a face shows its own name; the Director's menu must not be covered.
        if (g_faceHovered ~= nil and g_faceHovered.valid) or element.popup ~= nil then
            return
        end
        --sized from its longest line: an auto-width card with a full-width seam stretches
        --across the screen.
        local width = TextWidth(title, 8) + 24
        local lines = {}
        for _, row in ipairs(tally) do
            local lineWidth = 20 + 6 + math.min(170, TextWidth(ShownName(row.who), 8)) + 8 + 24
            for _, amount in ipairs({row.taken, row.healed}) do
                if amount > 0 then
                    lineWidth = lineWidth + TextWidth(tostring(amount), 8) + 8 + 3
                end
            end
            width = math.max(width, lineWidth)
            local cells = {
                Face(row.who, 20),
                gui.Label{
                    classes = {"historyName"},
                    text = ShownName(row.who),
                    width = "auto",
                    maxWidth = 170,
                    height = "auto",
                    lmargin = 6,
                    rmargin = 8,
                    textWrap = false,
                    textOverflow = "ellipsis",
                    halign = "left",
                    valign = "center",
                },
            }
            if row.taken > 0 then
                cells[#cells + 1] = Amount(row.taken, false, 13)
            end
            if row.healed > 0 then
                cells[#cells + 1] = Amount(row.healed, true, 13)
            end
            lines[#lines + 1] = gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "left",
                vmargin = 2,
                children = cells,
            }
        end
        local card = gui.Panel{
            classes = {"historyCardFrame"},
            styles = ThemeEngine.MergeStyles(Styles()),
            bgimage = true,
            blurBackground = true,
            flow = "vertical",
            width = width,
            height = "auto",
            interactable = false,
            gui.Label{
                classes = {"historyCardTitle"},
                text = title,
                width = "100%",
                height = "auto",
                hpad = 12,
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
                hpad = 12,
                tpad = 8,
                bpad = 10,
                borderBox = true,
                children = lines,
            },
        }
        --beside the line on the right, as the detail card opens; on the left when the
        --screen's edge is too close. distancesToScreenEdge.z is the room to the right.
        local right = element.distancesToScreenEdge.z >= width + 2 * CARD_GAP
        card.selfStyle.halign = right and "right" or "left"
        card.selfStyle.valign = "center"
        card.x = right and CARD_GAP or -CARD_GAP
        element.tooltip = card
        card:MakeNonInteractiveRecursive()
    end
end

--The caption a state shows as, with the style that marks it.
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

local MOVED_VERBS = {push = "pushed", pull = "pulled", slide = "slid", teleport = "teleported"}
History.MOVED_VERBS = MOVED_VERBS

--"Push 3", then after dots what stability took off, walls broken and a fall:
--"Push 2 . Stability 1 . Broke 1 wall . fell 4" (dots are DOT). vertical_push reads "Vertical push".
local function MovedWords(moved)
    local kind = string.upper_first(string.gsub(moved.kind, "_", " "))
    local words
    if moved.stopped then
        words = string.format("%s stopped", kind)
    elseif moved.distance <= 0 and moved.fell <= 0 then
        --blocked before it moved a square.
        words = string.format("%s blocked", kind)
    elseif moved.distance <= 0 then
        return string.format("Fell %d", moved.fell)
    else
        words = string.format("%s %d", kind, moved.distance)
    end
    if (moved.stability or 0) > 0 then
        words = words .. DOT .. string.format("Stability %d", moved.stability)
    end
    local walls = moved.walls or 0
    if walls > 0 then
        words = words .. DOT .. string.format("Broke %d %s", walls, walls == 1 and "wall" or "walls")
    end
    if moved.fell > 0 then
        words = words .. DOT .. string.format("fell %d", moved.fell)
    end
    return words
end

--The small lines under a target. ended marks one that takes an Ended tag.
--minions: confirmed minion deaths that belong on this cell.
--allyHit: an area ability caught a creature on its user's side.
local function Captions(who, minions, allyHit)
    local list = {}
    local function Add(text, ended, style)
        list[#list + 1] = {text = text, ended = ended, style = style}
    end
    if allyHit then
        Add("Ally hit")
    end
    --struck by a squad: how many of its minions hit this target.
    if (who.byminions or 0) > 0 and (who.taken or 0) > 0 then
        Add(string.format("%d %s", who.byminions, who.byminions == 1 and "minion" or "minions"))
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
--the creature took from the action, so it agrees with the detail card.
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
        text = History.SearchMark(ShownName(who)),
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
            text = History.SearchMark(caption.text),
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
    local active = History.ActiveStart(who)
    if active ~= nil then
        local tag = ActiveTag(active.icon)
        tag.selfStyle.lmargin = 0
        below[#below + 1] = tag
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

--Past four targets, three cells and "+N" with the rest named beside it.
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

--What makes a row open the card: the tooltip and the click. The tooltip waits for
--the pointer to rest, because it would otherwise cover the next row on every pass.
local function OpensCard(item)
    return {
        linger = function(element)
            --a face shows its own hover; the Director's menu must not be covered.
            if (g_faceHovered ~= nil and g_faceHovered.valid) or element.popup ~= nil then
                return
            end
            gui.Tooltip{text = "Open the detail", fontSize = 13}(element)
        end,
        click = function(element)
            element.tooltip = nil
            if dmhub.Time() - g_menuChosenAt < 0.3 then
                return
            end
            if g_tray ~= nil then
                g_tray.Select(item)
            end
        end,
    }
end

--The Director's right-click on a row: hide it from players or show it again,
--delete it, or clear the map's History. sources: the entries the row stands for, with
--everything nested under them. Nil (no menu) for players.
--- @param sources HistoryEntry[]|nil
--- @return nil|fun(element: Panel)
local function DirectorMenu(sources)
    if not dmhub.isDM or sources == nil or #sources == 0 then
        return nil
    end
    return function(element)
        local mapid = sources[1].map
        local hidden = sources[1].hiddenfromplayers == true
        --the row's "Open the detail" hover would sit on top of the menu.
        element.tooltip = nil
        element.popup = gui.ContextMenu{
            entries = {
                {
                    text = hidden and "Reveal to players" or "Hide from players",
                    click = function()
                        g_menuChosenAt = dmhub.Time()
                        element.popup = nil
                        History.SetHiddenFromPlayers(sources, not hidden)
                    end,
                },
                {
                    text = "Delete entry",
                    click = function()
                        g_menuChosenAt = dmhub.Time()
                        element.popup = nil
                        History.Delete(mapid, sources)
                    end,
                },
                {
                    text = "Clear History",
                    click = function()
                        g_menuChosenAt = dmhub.Time()
                        element.popup = nil
                        DTConfirmationDialog.ShowModal("Clear History?",
                            "This removes every entry on this map for everyone. It can't be undone.",
                            "Clear History", "Cancel", function() History.Clear(mapid) end)
                    end,
                },
            },
        }
    end
end

--The Director's eye-off beside a row hidden from players.
local function HiddenEye()
    return gui.VisibilityPanel{
        visible = false,
        width = 14,
        height = 14,
        lmargin = 5,
        halign = "left",
        valign = "center",
        linger = gui.Tooltip("Hidden from players"),
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

--Room for a trigger row: the action's text column, less the row's own left pad.
local function TriggerRowWidth()
    return g_trayWidth - 52 - 12 - 9
end

--The hairline above an action or a folded turn.
local function Rule()
    return gui.Panel{
        classes = {"historyRule"},
        bgimage = "panels/square.png",
        width = "100%",
        height = 1,
    }
end

--One side's roll under the action that asked for it: face, "Gordon rolled 14", then the
--test's name, muted. The same words as the line a test gets on its own.
local function RollRow(entry)
    --- @type Panel[]
    local children = {}
    local name = ""
    if entry.who ~= nil then
        children[1] = Face(entry.who, 20)
        name = string.format("<b>%s</b> ", ShownName(entry.who))
    end
    --a Dice Tower roll: players saw it happen, not what it came to.
    local words = "rolled in secret"
    if not entry.secretroll and entry.total ~= nil then
        words = string.format("rolled %d", entry.total)
    end
    children[#children + 1] = gui.Label{
        classes = {"historyTriggerResult"},
        text = History.SearchMark(name .. words),
        width = "auto",
        height = "auto",
        lmargin = 6,
        textWrap = false,
        halign = "left",
        valign = "center",
    }
    if entry.causetext ~= nil then
        children[#children + 1] = gui.Label{
            classes = {"historyMuted"},
            text = entry.causetext,
            width = "auto",
            height = "auto",
            lmargin = 6,
            textWrap = false,
            halign = "left",
            valign = "center",
        }
    end
    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        vmargin = 1,
        rightClick = DirectorMenu({entry}),
        children = children,
    }
end

--How an opposed power roll came out against one target: "Succeeded - 14 against 9".
--showTotals: this viewer may read the totals. named: several targets, so say which.
local function OpposedRow(who, showTotals, named)
    local opposed = who.opposed
    local words = "Tied"
    local class = "historyTriggerResult"
    if opposed.attacker > opposed.defender then
        words = "Succeeded"
    elseif opposed.attacker < opposed.defender then
        words = "Failed"
    end
    if showTotals then
        words = words .. DOT .. string.format("%d against %d", opposed.attacker, opposed.defender)
    end
    --- @type Panel[]
    local children = {}
    if named then
        children[1] = Face(who, 20)
    end
    children[#children + 1] = gui.Label{
        classes = {class},
        text = words,
        width = "auto",
        height = "auto",
        lmargin = named and 6 or 0,
        textWrap = false,
        halign = "left",
        valign = "center",
    }
    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        vmargin = 1,
        children = children,
    }
end

--A trigger nested under an action, on one line: number, owner, Triggered or Free,
--"{Owner} . {trigger}", then after a caret what it did. The name shortens with "..." so the
--result stays in view; hovering the name shows it whole, and the card has the full sentence.
--entry.result is a change to the owner itself, such as "Clarity +1".
--- @param rowActor HistoryCreature|nil Who took the action the line sits under.
local function TriggerRow(index, entry, rowActor)
    --free first, then where it fell against the action's roll. An ability used as part
    --of the action says what kind of action it is, if it is one.
    local tagText = "Triggered"
    if entry.kind == "action" then
        tagText = ACTION_WORDS[entry.ability.action or ""] or ""
    elseif entry.ability.free then
        tagText = "Free"
    elseif entry.when == "before" then
        tagText = "Before the roll"
    elseif entry.when == "during" then
        tagText = "During the roll"
    elseif entry.when == "after" then
        tagText = "After the roll"
    end
    local used = 15 + 6 + (tagText ~= "" and (TextWidth(tagText, 7.5) + 5) or 0)
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
    if tagText ~= "" then
        children[#children + 1] = gui.Label{
            classes = {"historySmallCaps"},
            text = tagText,
            width = "auto",
            height = "auto",
            lmargin = 6,
            halign = "left",
            valign = "center",
        }
    end

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
        --a trigger used from the roll dialog: what it changed, not what was dealt.
        local net = (who.edges ~= nil or who.banes ~= nil) and History.NetEdges(who.edges, who.banes) or nil
        if net ~= nil then
            effects[#effects + 1] = net.label
        end
        if (who.tiers or 0) ~= 0 then
            effects[#effects + 1] = string.format("%+d %s", who.tiers, math.abs(who.tiers) == 1 and "tier" or "tiers")
        end
        if (who.delta or 0) ~= 0 then
            effects[#effects + 1] = string.format("%+d", who.delta)
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

    --an ability the action's own user used as part of it needs no name before it.
    local sameUser = entry.kind == "action" and entry.actor ~= nil and rowActor ~= nil and entry.actor.id == rowActor.id
    local name = ((entry.actor ~= nil and not sameUser) and (ShownName(entry.actor) .. DOT) or "") .. entry.ability.name
    children[#children + 1] = gui.Label{
        classes = {"historyTriggerText"},
        text = name,
        width = "auto",
        maxWidth = math.max(60, TriggerRowWidth() - used - resultWidth - 4),
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
        --a dialog trigger is part of its action's entry, with nothing of its own to hide or delete.
        rightClick = (not entry.fromdialog) and DirectorMenu({entry.source or entry}) or nil,
        children = children,
    }
end

--A small outlined word beside an action's name: a cost (Malice, surges) or a glance chip.
local function Chip(text, style)
    return gui.Label{
        classes = {"historyChip", style},
        bgimage = "panels/square.png",
        text = text,
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

--Masks tinted to the cost's colour; a heroic resource uses its class's own art.
local COST_ICONS = {
    historyChipSurge = "game-icons/surge.png",
    historyChipMalice = "panels/malice.png",
}

--A spend beside an action's name: its icon and the number; a gain is signed ("+6"). A
--resource with no icon (one without art, or a heroic resource on a row from before icons
--were kept) stays a chip.
--- @param entry HistoryEntry
--- @param name string
--- @param cost {amount: number, style: string, icon: string|nil}
--- @param gained? boolean
local function Cost(entry, name, cost, gained)
    --- @type string|nil
    local icon = COST_ICONS[cost.style] or cost.icon
    if icon == nil and cost.style == "historyChipHeroic" and entry.actor ~= nil then
        local token = dmhub.GetCharacterById(entry.actor.id)
        if token ~= nil and token.properties ~= nil then
            icon = History.HeroicIcon(token.properties)
        end
    end
    if icon == nil then
        return Chip((gained and "+" or "") .. ResourceWords(cost.amount, name), cost.style)
    end
    return gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = 16,
        lmargin = 6,
        halign = "left",
        valign = "center",
        children = {
            gui.Panel{
                classes = {"historyCostIcon", cost.style},
                bgimage = icon,
                width = 14,
                height = 14,
                rmargin = 2,
                valign = "center",
                interactable = false,
            },
            gui.Label{
                classes = {"historyCost", cost.style},
                text = gained and string.format("+%d", cost.amount) or tostring(cost.amount),
                width = "auto",
                height = "auto",
                valign = "center",
            },
        },
    }
end

--What shaped the roll, readable without opening the card: the net edges or banes as the
--roll dialog's chevrons (one or two, up for an edge), counted the same way as the card's
--numbers, and a critical (a natural 19 or 20). Edges and banes that cancel show nothing.
local function GlanceChips(roll)
    local chips = {}
    if roll == nil then
        return chips
    end
    local net = History.NetEdges(roll.edges, roll.banes)
    if net ~= nil and net.side ~= nil then
        local chevrons = History.Chevrons(net.side, net.count)
        chevrons.selfStyle.lmargin = 5
        chevrons.selfStyle.rmargin = 0
        chips[#chips + 1] = chevrons
    end
    if (roll.natural or 0) >= 19 then
        chips[#chips + 1] = Chip("Critical")
    end
    return chips
end

local function BuildAction(item)
    local entry = item.entry
    local tier, tierPerTarget = SharedTier(entry)
    if tier == nil and not tierPerTarget and entry.roll ~= nil and entry.roll.tier ~= 0 then
        tier = entry.roll.tier
    end

    local titleChildren = {}
    --the face stands beside the words, so words that wrap stay clear of it.
    local actorFace = nil
    if item.showActor then
        actorFace = Face(entry.actor, 22)
        titleChildren[#titleChildren + 1] = gui.Label{
            classes = {"historyName"},
            text = History.SearchMark(ShownName(entry.actor)) .. DOT,
            width = "auto",
            height = "auto",
            lmargin = 5,
            halign = "left",
            valign = "center",
        }
    end
    titleChildren[#titleChildren + 1] = gui.Label{
        text = History.SearchMark(entry.ability.name),
        width = "auto",
        height = "auto",
        lmargin = item.showActor and 4 or 0, --auto width drops the space after the dot.
        halign = "left",
        valign = "center",
    }
    if entry.ability.villainaction ~= nil then
        titleChildren[#titleChildren + 1] = Tag("historyVillainTag", "Villain Action")
    end
    if tier ~= nil then
        titleChildren[#titleChildren + 1] = TierBadge(tier, entry.roll ~= nil and entry.roll.overridden ~= nil)
    end
    for _, chip in ipairs(GlanceChips(entry.roll)) do
        titleChildren[#titleChildren + 1] = chip
    end
    if entry.reverted ~= nil then
        titleChildren[#titleChildren + 1] = Tag("historyRevertedTag", "Reverted")
    end
    if dmhub.isDM and entry.hiddenfromplayers then
        titleChildren[#titleChildren + 1] = HiddenEye()
    end
    for _, list in ipairs({{costs = entry.costs}, {costs = entry.gains, gained = true}}) do
        if list.costs ~= nil then
            local names = {}
            for name in pairs(list.costs) do
                names[#names + 1] = name
            end
            table.sort(names)
            for _, name in ipairs(names) do
                titleChildren[#titleChildren + 1] = Cost(entry, name, list.costs[name], list.gained)
            end
        end
    end

    local action = ACTION_WORDS[entry.ability.action]

    --what nested triggers added to each creature this action hit, and the confirmed
    --minion deaths, which go on the first cell of their squad.
    local extra = {}
    local triggers = {}
    local minions = {}
    --rolls the ability asked for: each side of an opposed power roll, and rolls on a table.
    local rolls = {}
    local tableRolls = {}
    for _, kid in ipairs(item.triggers or {}) do
        --a triggered action, or a real ability used as part of this one (Agonizing Harmony in
        --Running Cacophony): both read as a numbered line under the action.
        if kid.kind == "trigger" or kid.kind == "action" then
            triggers[#triggers + 1] = kid
            for _, who in ipairs(kid.targets) do
                extra[who.id] = (extra[who.id] or 0) + (who.taken or 0)
            end
        elseif kid.family == "test" then
            rolls[#rolls + 1] = kid
        elseif kid.family == "table" then
            tableRolls[#tableRolls + 1] = kid
        elseif kid.family == "resource" then
            triggers[#triggers + 1] = {
                source = kid,
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

    local inner = g_trayWidth - 52 - 12
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

    --in the order they came: before the roll, used from its dialog, then the rest.
    local ordered = {}
    for _, kid in ipairs(triggers) do
        if kid.when == "before" then
            ordered[#ordered + 1] = kid
        end
    end
    for _, used in ipairs(entry.rolltriggers or {}) do
        ordered[#ordered + 1] = {kind = "trigger", when = "during", fromdialog = true, ability = {name = used.name}, actor = used.who, targets = used.targets}
    end
    for _, kid in ipairs(triggers) do
        if kid.when ~= "before" then
            ordered[#ordered + 1] = kid
        end
    end
    local triggerRows = {}
    for i, kid in ipairs(ordered) do
        triggerRows[i] = TriggerRow(i, kid, entry.actor)
    end
    --an opposed power roll reads as its outcome; the card has each side's dice. A row from
    --before the outcome was recorded keeps its two rolls.
    local outcomes = 0
    for _, who in ipairs(targets) do
        if who.opposed ~= nil then
            outcomes = outcomes + 1
            local showTotals = History.OpposedTotalsShown(item.triggers, entry.actor, who)
            triggerRows[#triggerRows + 1] = OpposedRow(who, showTotals, #targets > 1)
        end
    end
    if outcomes == 0 then
        for _, kid in ipairs(rolls) do
            triggerRows[#triggerRows + 1] = RollRow(kid)
        end
    end
    for _, kid in ipairs(tableRolls) do
        triggerRows[#triggerRows + 1] = RollRow(kid)
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
        rightClick = DirectorMenu(item.sources),
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
                    width = inner - ACTION_WORDS_WIDTH,
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    children = {
                        actorFace or gui.Panel{width = 0, height = 0},
                        gui.Panel{
                            flow = "horizontal",
                            wrap = true,
                            width = inner - ACTION_WORDS_WIDTH - (actorFace ~= nil and 22 or 0),
                            height = "auto",
                            halign = "left",
                            valign = "center",
                            children = titleChildren,
                        },
                    },
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

--A result with no action behind it: who, what, and the cause under it.
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
        if entry.renewed then
            return string.format("%s's %s was renewed", name, entry.name)
        elseif entry.iscondition then
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
    elseif family == "test" or family == "dice" or family == "table" then
        if entry.who == nil and entry.roller ~= nil then
            name = string.format("<b>%s</b>", entry.roller)
        end
        --a Dice Tower roll: players saw it happen, not what it came to.
        if entry.secretroll then
            return string.format("%s rolled in secret", name)
        end
        return string.format("%s rolled %d", name, entry.total)
    elseif family == "save" then
        return string.format("%s %s %s", name, cond(entry.passed, "saved against", "failed a save against"), entry.name)
    elseif family == "persistence" then
        return string.format("%s stopped maintaining %s", name, entry.name)
    elseif family == "strained" then
        --a Talent's heroic resource went below 0, or back.
        return string.format(entry.strained and "%s is strained" or "%s is no longer strained", name)
    elseif family == "note" then
        --a note card posted outside any action: "{Creature} {title}", the detail under it.
        return string.format("%s %s", name, entry.name or "")
    elseif family == "captain" then
        --the Director gave a squad its captain.
        return string.format("%s is now %s's captain", name, entry.squad or "the squad")
    elseif family == "encounterend" then
        return "<b>Encounter ended</b>"
    elseif family == "downtime" then
        local project = string.format("<b>%s</b>", entry.name or "A project")
        if entry.sub == "completed" then
            return project .. " completed"
        end
        return project .. " reached a milestone"
    elseif family == "negotiation" then
        local npc = string.format("<b>%s</b>", entry.name or "the NPC")
        if entry.sub == "began" then
            return "Negotiation with " .. npc
        elseif entry.sub == "ended" then
            return string.format("Negotiation with %s ended", npc)
        elseif entry.sub == "pitfall" then
            return string.format("%s hit a pitfall: %s", name, entry.trait or "")
        elseif entry.sub == "reveal" then
            return string.format("%s %s revealed", npc, entry.trait or "")
        elseif entry.sub == "adjust" then
            return string.format("%s %s %d to %d", npc, entry.which or "interest", entry.before or 0, entry.after or 0)
        end
        return string.format("%s rolled %d", name, entry.total or 0)
    elseif family == "montagetest" then
        return string.format("%s rolled %d", name, entry.total)
    elseif family == "montagethreat" then
        return string.format("<b>%s</b> was not vanquished", entry.name or "A threat")
    elseif family == "montageend" then
        return "<b>Montage ended</b>"
    elseif family == "montagecounter" then
        return string.format("<b>%s</b> %s %d to %d of %d", entry.name or "Montage", entry.counter, entry.before, entry.after, entry.limit)
    elseif family == "reveal" then
        --"Basilisk Soft Underbelly revealed"; a modifier with no creature behind it names itself.
        if entry.who == nil then
            return string.format("<b>%s</b> revealed", entry.name or "")
        end
        return string.format("%s %s revealed", name, entry.name or "")
    elseif family == "reverted" then
        return "<b>Turn reverted</b>"
    elseif family == "reinforcements" then
        return string.format("<b>%s</b> arrived", entry.name or "Reinforcements")
    elseif family == "staminaset" then
        return string.format("%s Stamina %d to %d", name, entry.before, entry.after)
    elseif family == "award" then
        local sub = entry.sub
        if sub == "victories" then
            local gained = entry.after - entry.before
            return string.format("%s gained %d %s", name, gained, cond(gained == 1, "Victory", "Victories"))
        elseif sub == "item" then
            local count = (entry.quantity or 1) > 1 and string.format(" x%d", entry.quantity) or ""
            return string.format("%s received %s%s", name, entry.name or "an item", count)
        elseif sub == "title" then
            return string.format("%s earned the title %s", name, entry.name or "")
        end
        return string.format("%s %s %d to %d", name, cond(sub == "renown", "Renown", "Wealth"), entry.before, entry.after)
    elseif family == "respite" then
        return name .. " took a respite"
    elseif family == "levelup" then
        return string.format("%s reached Level %d", name, entry.level)
    elseif family == "drawsteel" then
        local words = "<b>Draw Steel!</b>" .. DOT .. cond(entry.heroesFirst, "Heroes go first", "Enemies go first")
        if entry.rolled ~= nil then
            words = words .. string.format(" (rolled %d)", entry.rolled)
        end
        return words
    elseif family == "threshold" then
        if entry.state == "killed" then
            return name .. " was killed"
        end
        return string.format("%s is %s", name, entry.state)
    elseif family == "minions" then
        return string.format("<b>%s</b> %d of %d minions killed", entry.name, entry.killed, entry.killed + entry.left)
    elseif family == "moved" then
        local moved = entry.moved
        if moved.immune then
            return string.format("%s is immune to forced movement", name)
        end
        if moved.stopped then
            return string.format("%s held its ground: stability %d stopped the %s", name, moved.stability,
                (string.gsub(moved.kind, "vertical_", "")))
        end
        local verb = MOVED_VERBS[string.gsub(moved.kind, "vertical_", "")] or "moved"
        local words = string.format("%s was %s %d %s", name, verb, moved.distance, cond(moved.distance == 1, "square", "squares"))
        if moved.distance <= 0 and moved.fell <= 0 then
            words = string.format("%s was blocked and didn't move", name)
            if (moved.stability or 0) > 0 then
                words = words .. string.format(" (stability %d)", moved.stability)
            end
        elseif (moved.stability or 0) > 0 and (moved.requested or 0) > moved.distance then
            words = string.format("%s was %s %d of %d squares (stability %d)", name, verb, moved.distance, moved.requested, moved.stability)
        end
        local walls = moved.walls or 0
        if walls > 0 then
            words = words .. string.format(", breaking through %s", walls == 1 and "a wall" or string.format("%d walls", walls))
        end
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
        local number = Amount(entry.healed, true, 14)
        if entry.undone then
            number:SetClass("historyHealed", false)
            number:SetClass("historyUndone", true)
        end
        return number
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

--Which entries open a detail card: actions, an encounter's closing line with something to
--list, and test, Dice panel or table rolls. Every other line already says all there is.
local function HasCard(entry)
    return entry.kind == "action" or (entry.family == "encounterend" and #(entry.ended or {}) > 0)
        or entry.family == "test" or entry.family == "dice" or entry.family == "table"
        or (entry.family == "negotiation" and entry.sub == "argument" and (entry.text or "") ~= "")
end

--The start of a combat: the old log's swords and lettering as a landmark to scroll
--back to, with who goes first under them. LineWords has the same facts as one sentence.
local function BuildDrawSteel(entry)
    local words = cond(entry.heroesFirst, "Heroes go first", "Enemies go first")
    if entry.rolled ~= nil then
        words = words .. string.format(" (rolled %d)", entry.rolled)
    end
    local function Sword(flipped)
        return gui.Panel{
            bgimage = "panels/initiative/drawsteel-sword.png",
            bgcolor = "white",
            width = 44,
            height = 22,
            valign = "center",
            scale = flipped and {x = -1, y = 1} or nil,
        }
    end
    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        vpad = 8,
        borderBox = true,
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
            Sword(false),
            gui.Panel{
                bgimage = "panels/initiative/drawsteel-text.png",
                bgcolor = "white",
                width = 144,
                height = 20,
                hmargin = 6,
                valign = "center",
            },
            Sword(true),
        },
        gui.Label{
            classes = {"historyLineText"},
            text = History.SearchMark(words),
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 4,
            textAlignment = "center",
        },
    }
end

local function BuildLine(item)
    local entry = item.entry
    if entry.family == "drawsteel" then
        return BuildDrawSteel(entry)
    end
    local cause = entry.causetext
    --a wave's arrivals, named as this viewer knows them: "Goblin Sniper x3 - Goblin Assassin".
    if entry.family == "reinforcements" then
        local parts = {}
        for _, group in ipairs(entry.arrivals or {}) do
            local shown = ShownName({name = group.name or group.who.name, secret = group.who.secret})
            parts[#parts + 1] = shown .. (group.count > 1 and string.format(" x%d", group.count) or "")
        end
        cause = table.concat(parts, DOT)
    end
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
    --a heal with its Recovery keeps its number and has Undo beside it.
    local both = number ~= nil and entry.resourceid ~= nil
    local rowWidth = g_trayWidth - 52 - 12 - cond(leaveRoom, LINE_NUMBER_WIDTH, 0) - cond(both, UNDO_WIDTH, 0)
    local textWidth = rowWidth - 28
    local tag = nil
    if entry.family == "ended" then
        tag = Tag("historyEndedTag", "Ended")
    elseif entry.family == "save" and not entry.passed then
        tag = Tag("historyActiveTag", "Active")
    elseif entry.family == "montagetest" and entry.tier ~= nil and entry.tier >= 3 then
        tag = Tag("historySuccessTag", "Success")
    elseif entry.family == "montagetest" and entry.tier == 1 then
        tag = Tag("historyFailureTag", "Failure")
    elseif entry.family == "condition" and entry.who ~= nil then
        --a lone trigger's line carries the target's own start (AddLoneTrigger).
        local start = entry.start or entry
        if History.IsActive(entry.who.id, start) then
            tag = ActiveTag(start.icon)
        end
    end

    --opacity does not reach a panel's children, so an undone line fades by its text colour.
    --- @type Panel[]
    local top = {
        gui.Label{
            classes = {cond(entry.undone, "historyUndone", "historyLineText")},
            text = History.SearchMark(LineWords(entry)),
            width = "auto",
            maxWidth = textWidth,
            height = "auto",
            halign = "left",
            valign = "center",
            textAlignment = "left",
        },
    }
    top[2] = tag
    if entry.reverted ~= nil then
        top[#top + 1] = Tag("historyRevertedTag", "Reverted")
    end
    --an effect hidden from enemies: players don't get this line, or these names.
    if dmhub.isDM and (entry.secret or entry.hiddenfromplayers or (entry.hidden ~= nil and next(entry.hidden) ~= nil)) then
        top[#top + 1] = HiddenEye()
    end

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
        row[1] = Face(entry.who, 20)
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
        number.selfStyle.rmargin = cond(both, UNDO_WIDTH, 3)
        children[2] = number
    end

    --a resource line can be put back by whoever controls the creature; not once its turn
    --was reverted, which already put it back.
    local undoable = entry.resourceid ~= nil and not entry.undone and entry.reverted == nil and entry.who ~= nil
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

    --the closing line of an encounter lists what ended on its card.
    --a test or Dice panel roll opens its numbers.
    local hasCard = HasCard(entry)
    local opens = hasCard and OpensCard(item) or nil
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
        rightClick = DirectorMenu(item.sources),
        children = children,
    }
end

--How far in a round under a Combat heading starts.
local SUB_INDENT = 28

local function BuildRoundHead(item)
    local title = {}
    if item.toggle ~= nil then
        title[1] = Caret(true)
    end
    title[#title + 1] = gui.Label{
        classes = {item.sub and "historyRoundTitle" or "historyTitle"},
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
            lpad = item.sub and SUB_INDENT or 12,
            rpad = 12,
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
        linger = FoldHover(item.text, item.tally),
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 32,
            --a round under a Combat heading sits one step in.
            lpad = item.sub and SUB_INDENT or 12,
            rpad = 12,
            borderBox = true,
            Caret(false),
            gui.Label{
                classes = {item.sub and "historyRoundTitle" or "historyTitle"},
                text = item.text,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            MiniFaces(item.tally, g_trayWidth - (item.sub and SUB_INDENT or 12) - 12 - 17 - TextWidth(item.text, item.sub and 7.5 or 9)),
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
        linger = FoldHover(item.text, item.tally),
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
            MiniFaces(item.tally, g_trayWidth - 24 - 17 - TextWidth(item.text, 7)),
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
        linger = FoldHover(string.format("Turn %d", item.number), item.tally),
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
            --the turn number's column (33), the owner's face, and room for a Reverted tag.
            MiniFaces(item.tally, g_trayWidth - 24 - 17 - 33 - 26 - (item.reverted and 70 or 0)),
            item.reverted and Tag("historyRevertedTag", "Reverted") or nil,
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

--Main, Maneuver and Move on the turn being played: filled while there to use, greyed once
--used, as the action bar shows them. Read from the creature live, twice a second; hidden
--once the turn has passed.
local PIPS = {
    {text = "Main", used = function(props) return (props:GetResourceUsage(CharacterResource.actionResourceId, "turn") or 0) >= 1 end},
    {text = "Maneuver", used = function(props) return (props:GetResourceUsage(CharacterResource.maneuverResourceId, "turn") or 0) >= 1 end},
    {text = "Move", used = function(props) return props:DistanceMovedThisTurn() > 0 end},
}

local function TurnPips(item)
    local live = item.live
    local labels = {}
    for i, pip in ipairs(PIPS) do
        labels[i] = Chip(pip.text, "historyPip")
    end
    local shown = ""
    --the pips collapse while the turn is not on; the check sits on this outer panel because
    --a collapsed panel stops thinking.
    local row = gui.Panel{
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        children = labels,
    }
    return gui.Panel{
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        row,
        thinkTime = 0.5,
        think = function(element)
            local queue = dmhub.initiativeQueue
            local state = "off"
            if queue ~= nil and not queue.hidden and queue.guid == live.encounter and queue.round == live.round
                and queue.turnNumber == item.number and queue.currentTurn == item.owner.turnid then
                local tokens = InitiativeQueue.GetTokensForInitiativeId(queue.currentTurn, dmhub.allTokens)
                local props = tokens[1] ~= nil and tokens[1].properties or nil
                if props ~= nil then
                    state = ""
                    for _, pip in ipairs(PIPS) do
                        local ok, used = pcall(pip.used, props)
                        state = state .. ((ok and used) and "1" or "0")
                    end
                end
            end
            if state == shown then
                return
            end
            shown = state
            row:SetClass("collapsed", state == "off")
            for i, label in ipairs(labels) do
                label:SetClass("historyPipUsed", string.sub(state, i, i) == "1")
            end
        end,
    }
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
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "left",
                children = {
                    gui.Label{
                        classes = {"historyName"},
                        text = ShownName(item.owner),
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        valign = "center",
                    },
                    item.reverted and Tag("historyRevertedTag", "Reverted") or nil,
                },
            },
            gui.Label{
                classes = {"historySmallCaps"},
                text = TurnSideText(item),
                width = "auto",
                height = "auto",
                halign = "left",
            },
        },
        item.live ~= nil and TurnPips(item) or nil,
    }
end

--"New since you last looked": where the turns you have not seen start.
local function BuildNewMarker(item)
    local function Rule()
        return gui.Panel{
            classes = {"historyNewLine"},
            bgimage = "panels/square.png",
            width = 40,
            height = 1,
            valign = "center",
        }
    end
    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = 22,
        hpad = 12,
        borderBox = true,
        Rule(),
        gui.Label{
            classes = {"historyNewText"},
            text = "New since you last looked",
            width = "auto",
            height = "auto",
            hmargin = 8,
            valign = "center",
        },
        Rule(),
    }
end

local g_builders = {
    newmarker = BuildNewMarker,
    roundhead = BuildRoundHead,
    roundfold = BuildRoundFold,
    groupfold = BuildGroupFold,
    turnfold = BuildTurnFold,
    turnhead = BuildTurnHead,
    action = BuildAction,
    line = BuildLine,
}

--A row from its builder. A reverted one fades whole: opacity does not reach a
--panel's children, so every panel in it takes the class, except its Reverted tag.
local function BuildRow(item)
    local panel = g_builders[item.kind](item)
    local reverted = item.reverted
    if item.kind == "action" or item.kind == "line" then
        reverted = item.entry.reverted ~= nil
    end
    if reverted then
        for _, child in ipairs(panel.children) do
            child:SetClassTree("historyFaded", true)
        end
        for _, tag in ipairs(panel:GetChildrenWithClassRecursive("historyRevertedTag")) do
            tag:SetClass("historyFaded", false)
        end
    end
    return panel
end

--What the user has opened or closed by hand, by section or turn id. A section or turn
--with no entry here follows the default: only the newest stays open.
local g_open = {}

--The section or turn just opened or closed by hand. Its heading must stay built: opening an
--older combat adds rows under it, which would push it out of the rows built from the bottom.
--- @type string|nil
local g_toggled = nil

local function Toggle(id, isOpen)
    return function()
        g_open[id] = not isOpen
        g_toggled = id
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
        --what a revert undid never happened: it stays out of the fold's totals.
        if entry.reverted ~= nil then
            return
        end
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
--triggers, and up past an ability nested in another action (Prism's picks) to the row
--that action is on. Nil when nothing it came from has a row: it stands alone in its turn.
local function RootAction(entry, rowsById)
    local root = nil
    local parent = rowsById[entry.cause]
    for _ = 1, 8 do
        if parent == nil then
            break
        end
        if parent.kind == "action" then
            root = parent
        elseif parent.kind ~= "trigger" then
            break
        end
        parent = rowsById[parent.cause]
    end
    return root
end

--Search. Chips come from suggestions, or from opening History on a token; chips and
--typed words must all match. A match filters the tray in place, under its round and
--turn, and the words that matched are marked in the tray and the card.
--- @class HistorySearchChip
--- @field kind "creature"|"type"|"ability"|"condition"|"other"
--- @field key string A creature's token id; a type chip's type, lower case; or the ability's, condition's or other word's name.
--- @field name string What the chip says.
--- @field who? HistoryCreature A creature chip's face.
--- @field icon? string A condition chip's icon.
--- @field type? string The type a creature suggestion was found by, shown after its name.

--The outcome words and the stems that find them.
local OTHER_WORDS = {
    {name = "Killed", stem = "kill"},
    {name = "Winded", stem = "winded"},
    {name = "Triggered", stem = "trigger"},
    {name = "Surges", stem = "surge"},
    {name = "Malice", stem = "malice"},
    {name = "Pushed", stem = "push"},
    {name = "Fell", stem = "fell"},
    {name = "Immunity", stem = "immun"},
    {name = "Resisted", stem = "resist"},
    {name = "Critical", stem = "critical"},
}
local OTHER_STEMS = {}
for _, other in ipairs(OTHER_WORDS) do
    OTHER_STEMS[other.name] = other.stem
end

--What the search holds, kept while the tray closes and opens.
local g_search = {
    --- @type HistorySearchChip[]
    chips = {},
    text = "",
}

--- The typed words, lower case, and the turn number in "turn 15", or nil.
--- @return string[] words, integer|nil turn
local function SearchWords()
    local text = string.lower(g_search.text or "")
    local turn = nil
    local number = string.match(text, "turn%s+(%d+)")
    if number ~= nil then
        turn = tonumber(number)
        text = string.gsub(text, "turn%s+%d+", " ")
    end
    local words = {}
    for word in string.gmatch(text, "%S+") do
        words[#words + 1] = word
    end
    return words, turn
end

--- @return boolean
local function Searching()
    return #g_search.chips > 0 or string.find(g_search.text or "", "%S") ~= nil
end

local function Plain(text)
    return string.lower((string.gsub(text or "", "<[^>]*>", "")))
end

--Every creature a row is about: who acted, who it hit, whose trigger, who a line is about.
local function EachCreature(entry, kids, fn)
    local function Add(who)
        if who ~= nil and who.id ~= nil and (not who.secret or dmhub.isDM) then
            fn(who)
        end
    end
    local function AddEntry(record)
        Add(record.actor)
        Add(record.who)
        Add(record.triggerby)
        for _, who in ipairs(record.targets or {}) do
            Add(who)
        end
        if type(record.ended) == "table" and record.family == "encounterend" then
            for _, item in ipairs(record.ended) do
                Add(item.who)
            end
        end
    end
    AddEntry(entry)
    for _, kid in ipairs(kids or {}) do
        AddEntry(kid)
    end
end

--What kind of creature each token is, for type search: a hero's class; for the Director
--also a monster's organisation, role, keywords and monster name. Read from the token on
--the map, so a creature no longer there has none. Cleared on each search pass.
--- @type table<string, string[]>
local g_types = {}

local function ClearTypes()
    g_types = {}
end

--- @param id string A token id.
--- @return string[] types As the game writes them, e.g. "Summoner", "Undead".
local function CreatureTypes(id)
    local kept = g_types[id]
    if kept ~= nil then
        return kept
    end
    local types = {}
    local seen = {}
    local function Add(text)
        if type(text) == "string" and text ~= "" and not seen[string.lower(text)] then
            seen[string.lower(text)] = true
            types[#types + 1] = text
        end
    end
    local token = dmhub.GetTokenById(id)
    local props = token ~= nil and token.properties or nil
    if props ~= nil then
        if props:IsHero() then
            local class = (props --[[@as character]]):GetClass()
            if class ~= nil then
                Add(class.name)
            end
        elseif dmhub.isDM then
            --role holds organisation and role together, e.g. "Minion Defender".
            for word in string.gmatch(tostring(props:try_get("role", "")), "%S+") do
                Add(word)
            end
            for keyword, on in pairs(props:try_get("keywords", {})) do
                if on then
                    Add(keyword)
                end
            end
            Add(props:try_get("monster_type"))
        end
    end
    g_types[id] = types
    return types
end

--- The first of a creature's types that holds the typed text, or nil.
--- @param id string
--- @param typed string Lower case.
--- @return string|nil
local function TypeFound(id, typed)
    for _, text in ipairs(CreatureTypes(id)) do
        if string.find(string.lower(text), typed, 1, true) ~= nil then
            return text
        end
    end
    return nil
end

--- Whether a creature is of this type (lower case, whole).
--- @param id string
--- @param key string
--- @return boolean
local function IsOfType(id, key)
    for _, text in ipairs(CreatureTypes(id)) do
        if string.lower(text) == key then
            return true
        end
    end
    return false
end

--Everything a row says, lower case, for typed words and outcome chips: the card's own
--sentences, so a row matches on what the card shows. Kept per entry; nested triggers are
--counted in, as they arrive later.
--- @type table<table, {count: integer, text: string}>
local g_rowText = setmetatable({}, {__mode = "k"})

local function RowText(entry, kids)
    kids = kids or {}
    local kept = g_rowText[entry]
    if kept ~= nil and kept.count == #kids then
        return kept.text
    end
    local parts = {}
    local function Add(text)
        if text ~= nil and text ~= "" then
            parts[#parts + 1] = Plain(text)
        end
    end
    EachCreature(entry, kids, function(who)
        Add(ShownName(who))
    end)
    if entry.kind == "line" then
        Add(LineWords(entry))
        Add(entry.causetext)
        Add(entry.trigger)
        if entry.trigger ~= nil then
            Add("triggered")
        end
        if entry.family == "malice" then
            Add("malice")
        end
    else
        if entry.ability ~= nil then
            Add(entry.ability.name)
        end
        if entry.kind == "trigger" then
            Add("triggered")
        end
        for _, row in ipairs(History.Story(entry, kids)) do
            Add(History.StoryText(row))
        end
        for _, kid in ipairs(kids) do
            if kid.kind == "trigger" then
                Add("triggered")
                Add(kid.ability.name)
            elseif kid.kind == "action" and kid.ability ~= nil then
                Add(kid.ability.name)
            end
        end
        for name in pairs(entry.costs or {}) do
            Add(name)
        end
        for name in pairs(entry.gains or {}) do
            Add(name)
        end
        local roll = entry.roll
        if roll ~= nil then
            if roll.natural ~= nil and roll.natural >= 19 then
                Add("critical")
            end
            for _, source in ipairs(roll.sources or {}) do
                if dmhub.isDM or not PowerRollSpoilers.HasSpoiler(source.name) then
                    Add(source.name)
                end
            end
        end
        for _, who in ipairs(entry.targets or {}) do
            for _, part in ipairs(who.parts or {}) do
                Add(part.kind == "surge" and "surges" or part.name)
            end
            if who.immunity ~= nil then
                Add(who.immunity.amount > 0 and "immunity" or "weakness")
            end
            if who.immune ~= nil then
                Add("immune")
            end
            if who.moved ~= nil and (who.moved.fell or 0) > 0 then
                Add("fell")
            end
        end
    end
    local text = table.concat(parts, " | ")
    g_rowText[entry] = {count = #kids, text = text}
    return text
end

--Whether a row started a condition on one of these creatures (or one of them gave it).
local function GaveOrGot(entry, kids, name, ids)
    local wanted = string.lower(name)
    local function Has(who)
        for _, start in ipairs(who.conds or {}) do
            if string.lower(start.name) == wanted then
                return true
            end
        end
        return false
    end
    local function Check(record)
        if record.kind == "line" then
            return record.who ~= nil and ids[record.who.id] and string.find(Plain(LineWords(record)), wanted, 1, true) ~= nil
        end
        local actorIn = record.actor ~= nil and ids[record.actor.id]
        for _, who in ipairs(record.targets or {}) do
            if Has(who) and (ids[who.id] or actorIn) then
                return true
            end
        end
        return false
    end
    if Check(entry) then
        return true
    end
    for _, kid in ipairs(kids or {}) do
        if Check(kid) then
            return true
        end
    end
    return false
end

--- Whether a row matches these chips and words. With a creature chip, a condition chip
--- means that creature got (or gave) the condition.
--- @param entry HistoryEntry
--- @param kids HistoryEntry[]|nil
--- @param chips HistorySearchChip[]
--- @param words string[]
--- @param turn integer|nil
--- @return boolean
local function RowMatches(entry, kids, chips, words, turn)
    if turn ~= nil and entry.turn ~= turn then
        return false
    end
    local text = RowText(entry, kids)
    local creatures = nil
    for _, chip in ipairs(chips) do
        if chip.kind == "creature" then
            creatures = creatures or {}
            creatures[chip.key] = true
        elseif chip.kind == "type" then
            --a type chip stands for every creature of that type in this row.
            creatures = creatures or {}
            EachCreature(entry, kids, function(who)
                if IsOfType(who.id, chip.key) then
                    creatures[who.id] = true
                end
            end)
        end
    end
    for _, chip in ipairs(chips) do
        if chip.kind == "creature" then
            local found = false
            EachCreature(entry, kids, function(who)
                if who.id == chip.key then
                    found = true
                end
            end)
            if not found then
                return false
            end
        elseif chip.kind == "type" then
            local found = false
            EachCreature(entry, kids, function(who)
                if IsOfType(who.id, chip.key) then
                    found = true
                end
            end)
            if not found then
                return false
            end
        elseif chip.kind == "ability" then
            local found = entry.ability ~= nil and entry.ability.name == chip.key
            for _, kid in ipairs(kids or {}) do
                if kid.ability ~= nil and kid.ability.name == chip.key then
                    found = true
                end
            end
            if not found then
                return false
            end
        elseif chip.kind == "condition" then
            if creatures ~= nil then
                if not GaveOrGot(entry, kids, chip.key, creatures) then
                    return false
                end
            elseif string.find(text, string.lower(chip.key), 1, true) == nil then
                return false
            end
        elseif string.find(text, OTHER_STEMS[chip.key] or string.lower(chip.key), 1, true) == nil then
            return false
        end
    end
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) == nil then
            return false
        end
    end
    return true
end

--What to mark: the typed words and what the chips name, lower case.
local function MarkTerms()
    local words = SearchWords()
    local terms = {}
    for _, word in ipairs(words) do
        terms[#terms + 1] = word
    end
    for _, chip in ipairs(g_search.chips) do
        if chip.kind == "other" then
            terms[#terms + 1] = OTHER_STEMS[chip.key]
        elseif chip.kind == "type" then
            --a type is not written on the row, so there is nothing to mark.
        else
            terms[#terms + 1] = string.lower(chip.name)
        end
    end
    return terms
end

--The marks' colour: the Active tag's, faint enough to read through.
local function MarkColour()
    local warning = ThemeEngine.ResolveTokens("@warning")
    if type(warning) ~= "string" or string.sub(warning, 1, 1) ~= "#" then
        warning = "#E9C868"
    end
    return string.sub(warning, 1, 7) .. "55"
end

--- The text with what the search matched marked, outside its markup. Unchanged while
--- nothing is searched. The tray's rows and the card both draw through this.
--- @param text string
--- @return string
function History.SearchMark(text)
    if type(text) ~= "string" or not Searching() then
        return text
    end
    local terms = MarkTerms()
    if #terms == 0 then
        return text
    end
    local open = string.format("<mark=%s>", MarkColour())
    local out = {}
    --tags pass through untouched; only the words between them are marked.
    local pos = 1
    while pos <= #text do
        local tagStart, tagEnd = string.find(text, "<[^>]*>", pos)
        local stop = tagStart ~= nil and tagStart - 1 or #text
        local chunk = string.sub(text, pos, stop)
        local lower = string.lower(chunk)
        local i = 1
        while i <= #chunk do
            local best, bestEnd = nil, nil
            for _, term in ipairs(terms) do
                local matchStart, matchEnd = string.find(lower, term, i, true)
                if matchStart ~= nil and (best == nil or matchStart < best or (matchStart == best and matchEnd > bestEnd)) then
                    best, bestEnd = matchStart, matchEnd
                end
            end
            if best == nil then
                out[#out + 1] = string.sub(chunk, i)
                break
            end
            out[#out + 1] = string.sub(chunk, i, best - 1)
            out[#out + 1] = open .. string.sub(chunk, best, bestEnd) .. "</mark>"
            i = bestEnd + 1
        end
        if tagStart == nil then
            break
        end
        out[#out + 1] = string.sub(text, tagStart, tagEnd)
        pos = tagEnd + 1
    end
    return table.concat(out)
end

--Groups entries, oldest first, into sections (a round, or a stretch in one game mode out
--of combat) holding turns holding entries. Out of combat has no round, so an encounter or
--a change of mode between two stretches keeps them apart, and each takes its id from its
--first entry.
--Also returns what is nested under each action, by the action's id.
local function BuildSections(mapid)
    local keys = History.Keys(mapid)
    local rowsById = {}
    History.ClearStarts()
    for _, key in ipairs(keys) do
        local entry = History.Entry(mapid, key)
        if entry ~= nil then
            --in time order, so the newest start of each condition wins (Active).
            if entry.family == "condition" and entry.who ~= nil then
                History.NoteStart(entry.who.id, entry --[[@as HistoryStart]])
            end
            for _, who in ipairs(entry.targets or {}) do
                for _, start in ipairs(who.conds or {}) do
                    History.NoteStart(who.id, start)
                end
            end
            rowsById[entry.id] = entry
            for _, alias in ipairs(entry.aliases or {}) do
                rowsById[alias] = entry
            end
        end
    end

    local sections = {}
    local sectionIds = {}
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
        --a Malice line a player may not see never reaches here: History.Entry leaves it out.
        elseif entry ~= nil then
            local outside = entry.encounter == nil
            local groupid = "out-" .. (entry.mode or "exploration")
            if not outside then
                groupid = string.format("%s-%d", entry.encounter, entry.round)
            end
            if section == nil or section.groupid ~= groupid then
                --a combat broken by a line from outside it picks up again with the same round:
                --its id gets a count, since rows and folds are told apart by id.
                local id = outside and ("out-" .. key) or groupid
                local seen = sectionIds[id] or 0
                sectionIds[id] = seen + 1
                if seen > 0 then
                    id = string.format("%s-%d", id, seen)
                end
                section = {
                    groupid = groupid,
                    id = id,
                    round = entry.round,
                    mode = outside and (entry.mode or "exploration") or nil,
                    encounter = not outside and entry.encounter or nil,
                    turns = {},
                    entries = {},
                }
                sections[#sections + 1] = section
                turn = nil
            end
            --a reverted Malice change did not happen, so the heading's range leaves it out.
            if entry.family == "malice" and entry.reverted == nil then
                section.maliceBefore = section.maliceBefore or entry.before
                section.maliceAfter = entry.after
            end
            if not entry.quiet then
                local number = entry.turn or 0
                --after Revert Turn's line the turn is played again with the same number:
                --that is a turn of its own, under its own heading.
                if turn == nil or turn.number ~= number or turn.closed then
                    local id = string.format("%s-%d", section.id, number)
                    section.turnIds = section.turnIds or {}
                    local seen = section.turnIds[id] or 0
                    section.turnIds[id] = seen + 1
                    if seen > 0 then
                        id = string.format("%s-%d", id, seen)
                    end
                    turn = {id = id, number = number, entries = {}, keys = {}}
                    section.turns[#section.turns + 1] = turn
                end
                turn.owner = turn.owner or entry.owner
                turn.entries[#turn.entries + 1] = entry
                turn.keys[#turn.keys + 1] = key
                section.entries[#section.entries + 1] = entry
                if entry.family == "reverted" and entry.wholeturn then
                    turn.closed = true
                end
            end
        end
    end
    return sections, nested
end

--Out of combat, the heading is the game mode's name as the Initiative bar shows it.
local function SectionTitle(section)
    if section.round == nil then
        local info = InitiativeQueue.GameModesById[section.mode or "exploration"] or InitiativeQueue.GameModesById["exploration"]
        return info ~= nil and info.text or "Exploration"
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
local function AddLoneTrigger(items, entry, key, kids)
    local causetext = entry.ability.name
    if entry.landedby ~= nil then
        causetext = string.format("Landed on by %s", ShownName(entry.landedby))
    end
    --each line the trigger becomes stands for the trigger and what is nested under it.
    local sources = {entry}
    for _, kid in ipairs(kids or {}) do
        sources[#sources + 1] = kid
    end
    for i, who in ipairs(entry.targets) do
        local base = {kind = "line", who = who, causetext = causetext, hiddenfromplayers = entry.hiddenfromplayers, reverted = entry.reverted}
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
                renewed = condition.renewed,
                icon = condition.icon,
                start = condition,
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
            for field, value in pairs(base) do
                part[field] = value
            end
            items[#items + 1] = {
                kind = "line",
                key = string.format("%s-%d-%d", key, i, j),
                sig = entry,
                entry = part,
                sources = sources,
            }
        end
    end
end

--While searching, everything that matched shows unfolded.
local g_searchOpen = false

--The newest entry key this user had seen when History opened, or nil. Turns with
--anything newer open unfolded, under the "New since you last looked" marker.
--- @type string|nil
local g_since = nil
--What this user had seen on the shown map when the rail opened History: kept from before the
--rail marks it seen, until the window reads it. false when they had never looked.
--- @type string|false|nil
local g_sinceAtOpen = nil
--The action bar's row, and where its strip last was on the screen, in screen pixels.
--- @type Panel|nil
local g_barRow = nil
--- @type {top: number, left: number, right: number}|nil
local g_barStrip = nil

--Whether the marker went in during this build (it goes before the first new turn only).
local g_markerPlaced = false

--Nothing moves under the reader: when new rows arrive while the pointer is on History or
--a card is open, every turn and round stays as open as it was, and the turns shown on their
--own stay out of the "Turns 1-4" fold. g_lastOpen / g_lastFoldTo are the last build's state.
local g_frozen = false
--- @type table<string, boolean>
local g_lastOpen = {}
--- @type table<string, boolean>
local g_nowOpen = {}
--- @type table<string, integer>
local g_lastFoldTo = {}
--- @type table<string, integer>
local g_nowFoldTo = {}

--- Whether a turn holds anything newer than what this user had seen.
local function TurnIsNew(turn)
    local last = turn.keys[#turn.keys]
    return g_since ~= nil and last ~= nil and last > g_since
end

local function AddTurnRows(items, turn, isNewest, nested)
    local isNew = not g_searchOpen and TurnIsNew(turn)
    local isOpen = g_open[turn.id]
    if isOpen == nil or g_searchOpen then
        isOpen = g_searchOpen or isNewest or isNew or (g_frozen and g_lastOpen[turn.id] == true)
    end
    if isOpen then
        g_nowOpen[turn.id] = true
    end
    if isNew and not g_markerPlaced then
        g_markerPlaced = true
        items[#items + 1] = {kind = "newmarker", key = "newmarker", sig = "newmarker"}
    end
    local toggle = Toggle(turn.id, isOpen)
    --a turn whose every row was reverted has its heading struck through too.
    local reverted = false
    for _, entry in ipairs(turn.entries) do
        if entry.family ~= "reverted" then
            if entry.reverted == nil then
                reverted = false
                break
            end
            reverted = true
        end
    end
    if turn.owner ~= nil then
        if not isOpen then
            local tally = Tally(turn.entries, nested)
            items[#items + 1] = {
                kind = "turnfold",
                key = "fold-" .. turn.id,
                sig = turn.owner.id .. TallySignature(tally) .. tostring(reverted),
                number = turn.number,
                owner = turn.owner,
                tally = tally,
                toggle = toggle,
                reverted = reverted,
            }
            return
        end
        local first = turn.entries[1]
        items[#items + 1] = {
            kind = "turnhead",
            key = "head-" .. turn.id,
            sig = turn.owner.id .. tostring(reverted) .. tostring(isNewest),
            number = turn.number,
            owner = turn.owner,
            toggle = toggle,
            reverted = reverted,
            --the newest turn may be the one being played: its heading shows the pips.
            live = isNewest and first ~= nil and {encounter = first.encounter, round = first.round} or nil,
        }
    end
    for i, entry in ipairs(turn.entries) do
        local last = items[#items]
        if entry.kind == "line" and entry.family == "ended" and last ~= nil and last.kind == "line"
            and last.entry.family == "ended" and last.entry.who.id == entry.who.id
            and last.entry.causetext == entry.causetext and last.entry.reverted == entry.reverted then
            --ended a moment apart, for the same reason: one line.
            local names = table.shallow_copy(last.entry.names)
            for _, name in ipairs(entry.names) do
                names[#names + 1] = name
            end
            --the names players may not see, from both lines, so the Director's eye still shows.
            local hidden = nil
            for _, part in ipairs({last.entry, entry}) do
                for name in pairs(part.hidden or {}) do
                    hidden = hidden or {}
                    hidden[name] = true
                end
            end
            last.entry = {family = "ended", kind = "line", who = entry.who, causetext = entry.causetext, names = names,
                hiddenfromplayers = last.entry.hiddenfromplayers, reverted = entry.reverted, hidden = hidden}
            --a copy: a lone trigger's lines share one sources list, and only this line grows.
            last.sources = table.shallow_copy(last.sources)
            last.sources[#last.sources + 1] = entry
            --each source is a new table whenever it is rewritten (a revert, a hide), so the
            --merged line rebuilds when any of them changes.
            local sig = {}
            for _, source in ipairs(last.sources) do
                sig[#sig + 1] = tostring(source)
            end
            last.sig = table.concat(sig, ",")
        elseif entry.kind == "line" then
            items[#items + 1] = {kind = "line", key = turn.keys[i], sig = entry, entry = entry, sources = {entry}}
        elseif entry.kind == "trigger" then
            AddLoneTrigger(items, entry, turn.keys[i], nested[entry.id])
        else
            local triggers = nested[entry.id]
            local sig = entry
            if triggers ~= nil then
                --each nested entry by its table, which is new whenever it is rewritten (a hide,
                --a reveal), so the row and its card rebuild then too.
                local ids = {tostring(entry)}
                for _, kid in ipairs(triggers) do
                    ids[#ids + 1] = tostring(kid)
                end
                sig = table.concat(ids, ",")
            end
            local sources = {entry}
            for _, kid in ipairs(triggers or {}) do
                sources[#sources + 1] = kid
            end
            items[#items + 1] = {
                kind = "action",
                key = turn.keys[i],
                sig = sig,
                entry = entry,
                sources = sources,
                triggers = triggers,
                showActor = turn.owner == nil or entry.actor.id ~= turn.owner.id,
            }
        end
    end
end

--- A section's rows: its heading or fold line, then its turns. sub: a round inside a
--- Combat heading, drawn one step in. open: open unless closed by hand (a combat's only round).
local function AddSectionRows(items, section, isNewest, nested, sub, open)
    --the first turn this user has not seen, if the section has one.
    local firstNew = nil
    if not g_searchOpen then
        for i, turn in ipairs(section.turns) do
            if TurnIsNew(turn) then
                firstNew = i
                break
            end
        end
    end
    local isOpen = g_open[section.id]
    if isOpen == nil or g_searchOpen then
        isOpen = g_searchOpen or isNewest or open or firstNew ~= nil or (g_frozen and g_lastOpen[section.id] == true)
    end
    if isOpen then
        g_nowOpen[section.id] = true
    end
    local title = SectionTitle(section)
    if not isOpen then
        local tally = Tally(section.entries, nested)
        items[#items + 1] = {
            kind = "roundfold",
            key = "fold-" .. section.id,
            sig = title .. TallySignature(tally) .. (sub and "sub" or ""),
            text = title,
            tally = tally,
            sub = sub,
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
        sig = title .. (right or "") .. (sub and "sub" or ""),
        text = title,
        right = right,
        sub = sub,
        toggle = (not g_searchOpen and (not isNewest or g_open[section.id] == false)) and Toggle(section.id, isOpen) or nil,
    }

    local turns = section.turns
    local first = 1
    local groupid = "group-" .. section.id
    --the turns before the newest few fold into one line; with new turns, everything before
    --the first new turn does.
    local foldTo = nil
    if not g_searchOpen and g_open[groupid] ~= true then
        if firstNew ~= nil and firstNew > 1 then
            foldTo = firstNew
        elseif isNewest and #turns > NEWEST_TURNS then
            foldTo = #turns - NEWEST_TURNS + 1
        end
        --frozen: no turn that was on show joins the fold.
        if g_frozen then
            local last = g_lastFoldTo[groupid]
            foldTo = (last ~= nil and foldTo ~= nil) and math.min(foldTo, last) or nil
        end
    end
    if foldTo ~= nil then
        g_nowFoldTo[groupid] = foldTo
        local firstNumber, lastNumber = nil, nil
        local entries = {}
        first = foldTo
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

--A combat's rounds, sections[first] to sections[last], under one Combat heading. An older
--combat folds to "Combat - Rounds 1-3", like a round; the newest, or one with turns this
--user has not seen, stays open.
local function AddCombatRows(items, sections, first, last, isNewest, nested)
    local id = "combat-" .. sections[first].id
    --its rounds: the sections between first and last that belong to this combat. A round
    --that picks up again after a skipped section joins the one before it.
    local rounds = {}
    for i = first, last do
        local section = sections[i]
        local prev = rounds[#rounds]
        if section.encounter ~= sections[first].encounter then
            --a skipped section: no rows.
        elseif prev ~= nil and prev.round == section.round then
            for _, turn in ipairs(section.turns) do
                local tail = prev.turns[#prev.turns]
                if tail ~= nil and tail.number == turn.number then
                    for index, entry in ipairs(turn.entries) do
                        tail.entries[#tail.entries + 1] = entry
                        tail.keys[#tail.keys + 1] = turn.keys[index]
                    end
                else
                    prev.turns[#prev.turns + 1] = turn
                end
            end
            for _, entry in ipairs(section.entries) do
                prev.entries[#prev.entries + 1] = entry
            end
            if section.maliceAfter ~= nil then
                prev.maliceBefore = prev.maliceBefore or section.maliceBefore
                prev.maliceAfter = section.maliceAfter
            end
        else
            rounds[#rounds + 1] = section
        end
    end
    local hasNew = false
    if not g_searchOpen then
        for _, round in ipairs(rounds) do
            for _, turn in ipairs(round.turns) do
                hasNew = hasNew or TurnIsNew(turn)
            end
        end
    end
    local isOpen = g_open[id]
    if isOpen == nil or g_searchOpen then
        isOpen = g_searchOpen or isNewest or hasNew or (g_frozen and g_lastOpen[id] == true)
    end
    if not isOpen then
        local entries = {}
        for _, round in ipairs(rounds) do
            for _, entry in ipairs(round.entries) do
                entries[#entries + 1] = entry
            end
        end
        local firstRound, lastRound = sections[first].round, sections[last].round
        local text = "Combat" .. DOT .. (firstRound == lastRound and string.format("Round %d", firstRound) or string.format("Rounds %d%s%d", firstRound, EN_DASH, lastRound))
        local tally = Tally(entries, nested)
        items[#items + 1] = {
            kind = "roundfold",
            key = "fold-" .. id,
            sig = text .. TallySignature(tally),
            text = text,
            tally = tally,
            toggle = Toggle(id, isOpen),
        }
        return
    end
    g_nowOpen[id] = true
    items[#items + 1] = {
        kind = "roundhead",
        key = "head-" .. id,
        sig = "Combat",
        text = "Combat",
        toggle = (not g_searchOpen and (not isNewest or g_open[id] == false)) and Toggle(id, isOpen) or nil,
    }
    for i, round in ipairs(rounds) do
        AddSectionRows(items, round, isNewest and i == #rounds, nested, true, #rounds == 1)
    end
end

--What the search is, as text, so a row built for another search redraws its marks.
local g_searchKey = ""

local function UpdateSearchKey()
    local parts = {string.lower(g_search.text or "")}
    for _, chip in ipairs(g_search.chips) do
        parts[#parts + 1] = chip.kind .. ":" .. chip.key
    end
    g_searchKey = Searching() and table.concat(parts, ",") or ""
end

--Which of a row's starts are still on, so its Active tags redraw when one ends.
local function ActiveSignature(item)
    local entry = item.entry
    if entry == nil then
        return ""
    end
    local bits = {}
    if entry.family == "condition" and entry.who ~= nil then
        bits[1] = History.IsActive(entry.who.id, entry.start or entry) and "1" or "0"
    end
    for _, who in ipairs(entry.targets or {}) do
        if who.conds ~= nil then
            bits[#bits + 1] = History.ActiveStart(who) ~= nil and "1" or "0"
        end
    end
    for _, kid in ipairs(item.triggers or {}) do
        for _, who in ipairs(kid.targets or {}) do
            if who.conds ~= nil then
                bits[#bits + 1] = History.ActiveStart(who) ~= nil and "1" or "0"
            end
        end
    end
    return table.concat(bits)
end

--Keeps only the rows that match the search, and the turns and sections that hold them.
--- @return table[] sections, integer count
local function SearchSections(sections, nested)
    local words, turnNumber = SearchWords()
    local chips = g_search.chips
    local kept = {}
    local count = 0
    for _, section in ipairs(sections) do
        local turns = {}
        for _, turn in ipairs(section.turns) do
            local entries, keys = {}, {}
            for i, entry in ipairs(turn.entries) do
                if RowMatches(entry, nested[entry.id], chips, words, turnNumber) then
                    entries[#entries + 1] = entry
                    keys[#keys + 1] = turn.keys[i]
                end
            end
            if #entries > 0 then
                count = count + #entries
                turns[#turns + 1] = {id = turn.id, number = turn.number, owner = turn.owner, entries = entries, keys = keys}
            end
        end
        if #turns > 0 then
            local copy = table.shallow_copy(section)
            copy.turns = turns
            kept[#kept + 1] = copy
        end
    end
    return kept, count
end

--- The rows to show, and how many rows matched while searching (nil when not searching).
--- @return table[] items, integer|nil matches
--- @param frozen boolean|nil New rows arrived while someone is reading: keep what is open.
local function BuildItems(mapid, frozen)
    local items = {}
    ClearTypes()
    g_markerPlaced = false
    g_frozen = frozen == true
    g_nowOpen = {}
    g_nowFoldTo = {}
    local sections, nested = BuildSections(mapid)
    local matches = nil
    g_searchOpen = Searching()
    if g_searchOpen then
        sections, matches = SearchSections(sections, nested)
    end
    --a section with no rows holds only a Director's quiet Malice line: it is not shown, and a
    --combat reads on across it (combat's end resets Malice just before "Encounter ended").
    local lastShown = #sections
    while lastShown > 1 and #sections[lastShown].turns == 0 do
        lastShown = lastShown - 1
    end
    local i = 1
    while i <= #sections do
        local encounter = sections[i].encounter
        if encounter == nil then
            if #sections[i].turns > 0 then
                AddSectionRows(items, sections[i], i >= lastShown, nested)
            end
            i = i + 1
        else
            local last = i
            local j = i + 1
            while j <= #sections and (sections[j].encounter == encounter or (sections[j].encounter == nil and #sections[j].turns == 0)) do
                if sections[j].encounter == encounter then
                    last = j
                end
                j = j + 1
            end
            AddCombatRows(items, sections, i, last, last >= lastShown, nested)
            i = last + 1
        end
    end
    --a search opens everything, which is not what to keep once it ends.
    if not g_searchOpen then
        g_lastOpen = g_nowOpen
        g_lastFoldTo = g_nowFoldTo
    end
    g_searchOpen = false
    g_frozen = false
    return items, matches
end

--Room for the chips under the search field, while there is a search.
local CHIP_ROW_HEIGHT = 26
--The maps whose fights this user can follow: all of them for the Director; for a player
--the ones shared with them, and the one they are on.
local function VisibleMaps()
    local ids = {}
    for _, map in ipairs(game.maps) do
        if dmhub.isDM or map.playerViewable or map.id == game.currentMapId then
            ids[#ids + 1] = map.id
        end
    end
    --what happened with no map at all, once there is any.
    if #History.Keys(History.NO_MAP) > 0 then
        ids[#ids + 1] = History.NO_MAP
    end
    return ids
end

--A map's name in the switcher; the game-wide record is the Table.
local function MapLabel(mapid)
    if mapid == History.NO_MAP then
        return "Table"
    end
    return Tabletop.MapName(mapid)
end


--What the search is called in the "Nothing matches" message: the chips, then the typed words.
local function SearchLabel()
    local parts = {}
    for _, chip in ipairs(g_search.chips) do
        parts[#parts + 1] = chip.name
    end
    local text = string.match(g_search.text or "", "^%s*(.-)%s*$")
    if text ~= "" then
        parts[#parts + 1] = text
    end
    return table.concat(parts, " + ")
end

--The message in place of the rows when nothing matches; text, when given, says the map has
--nothing at all yet.
--- @param text string|nil
local function SearchEmpty(text)
    return gui.Label{
        classes = {"historyMuted"},
        text = text or string.format("Nothing matches \"%s\".", SearchLabel()),
        width = "100%-24",
        height = "auto",
        halign = "left",
        valign = "bottom",
        hmargin = 12,
        vmargin = 16,
        italics = true,
        textAlignment = "left",
    }
end

--Every row and what is nested under it, for suggestions and their counts.
--- @return {entry: HistoryEntry, kids: HistoryEntry[]|nil}[]
local function AllRows(mapid)
    local sections, nested = BuildSections(mapid)
    local list = {}
    for _, section in ipairs(sections) do
        for _, turn in ipairs(section.turns) do
            for _, entry in ipairs(turn.entries) do
                list[#list + 1] = {entry = entry, kids = nested[entry.id]}
            end
        end
    end
    return list
end

--How well a name fits what was typed: starts with it, a word starts with it, or neither.
local function FitScore(name, typed)
    local lower = string.lower(name)
    if string.sub(lower, 1, #typed) == typed then
        return 0
    end
    if string.find(" " .. string.gsub(lower, "[^%w ]", " "), " " .. typed, 1, true) ~= nil then
        return 1
    end
    return 2
end

--Suggestions while typing: creatures, abilities, conditions and the outcome words that
--appear in History, best fits first, four a group, each with how many rows it would find.
--- @param mapid string
--- @param typed string Lower case.
--- @return {title: string, items: {chip: HistorySearchChip, count: integer}[]}[]
local function Suggestions(mapid, typed)
    if typed == "" then
        return {}
    end
    ClearTypes()
    local rows = AllRows(mapid)
    local seen = {}
    local candidates = {creature = {}, ability = {}, condition = {}, other = {}}
    --creatures found by type, by the type as written, for the All {type} row.
    --- @type table<string, table<string, boolean>>
    local typeMembers = {}
    local function Offer(chip)
        local id = chip.kind .. ":" .. chip.key
        if seen[id] then
            return
        end
        if string.find(string.lower(chip.name), typed, 1, true) == nil then
            if chip.kind ~= "creature" then
                return
            end
            chip.type = TypeFound(chip.key, typed)
            if chip.type == nil then
                return
            end
            typeMembers[chip.type] = typeMembers[chip.type] or {}
            typeMembers[chip.type][chip.key] = true
        end
        seen[id] = true
        for _, existing in ipairs(g_search.chips) do
            if existing.kind == chip.kind and existing.key == chip.key then
                return
            end
        end
        table.insert(candidates[chip.kind], chip)
    end
    local function OfferStarts(who)
        for _, start in ipairs(who.conds or {}) do
            Offer({kind = "condition", key = start.name, name = start.name, icon = start.icon})
        end
    end
    for _, row in ipairs(rows) do
        EachCreature(row.entry, row.kids, function(who)
            Offer({kind = "creature", key = who.id, name = ShownName(who), who = who})
        end)
        for _, record in ipairs({row.entry, table.unpack(row.kids or {})}) do
            if record.ability ~= nil and record.ability.name ~= nil and record.ability.name ~= "" then
                Offer({kind = "ability", key = record.ability.name, name = record.ability.name})
            end
            if record.family == "condition" and record.name ~= nil then
                Offer({kind = "condition", key = record.name, name = record.name, icon = record.icon})
            end
            for _, who in ipairs(record.targets or {}) do
                OfferStarts(who)
            end
        end
    end
    for _, other in ipairs(OTHER_WORDS) do
        Offer({kind = "other", key = other.name, name = other.name})
    end
    --two or more creatures of one type: offer them all as one chip, ahead of the rest.
    local typeChips = {}
    for text, members in pairs(typeMembers) do
        local key = string.lower(text)
        local taken = false
        for _, existing in ipairs(g_search.chips) do
            if existing.kind == "type" and existing.key == key then
                taken = true
            end
        end
        local memberCount = 0
        for _ in pairs(members) do
            memberCount = memberCount + 1
        end
        if memberCount >= 2 and not taken then
            typeChips[#typeChips + 1] = {kind = "type", key = key, name = text}
        end
    end
    table.sort(typeChips, function(first, second)
        return first.name < second.name
    end)
    for i = #typeChips, 1, -1 do
        table.insert(candidates.creature, 1, typeChips[i])
    end

    local _, turn = SearchWords()
    local groups = {}
    local order = {{"creature", "Creatures"}, {"ability", "Abilities"}, {"condition", "Conditions"}, {"other", "Other"}}
    for index, kind in ipairs(order) do
        local items = {}
        for _, chip in ipairs(candidates[kind[1]]) do
            local chips = table.shallow_copy(g_search.chips)
            chips[#chips + 1] = chip
            local count = 0
            for _, row in ipairs(rows) do
                --the typed text becomes the chip, so it doesn't count against it.
                if RowMatches(row.entry, row.kids, chips, {}, turn) then
                    count = count + 1
                end
            end
            if count > 0 then
                --All {type} rows lead, then names that fit, then creatures found by type.
                local score = FitScore(chip.name, typed)
                if chip.type ~= nil then
                    score = 3 + FitScore(chip.type, typed)
                elseif chip.kind == "type" then
                    score = -1
                end
                items[#items + 1] = {chip = chip, count = count, score = score}
            end
        end
        table.sort(items, function(first, second)
            if first.score ~= second.score then
                return first.score < second.score
            end
            return first.chip.name < second.chip.name
        end)
        while #items > 4 do
            table.remove(items)
        end
        if #items > 0 then
            groups[#groups + 1] = {title = kind[2], items = items, best = math.max(0, items[1].score) * 10 + index}
        end
    end
    table.sort(groups, function(first, second)
        return first.best < second.best
    end)
    return groups
end


--A chip's small picture: a creature's face or a condition's icon.
local function ChipPicture(chip, size)
    if chip.who ~= nil then
        local face = Face(chip.who, size)
        face.selfStyle.borderWidth = 1
        return face
    end
    if chip.icon ~= nil then
        return gui.Panel{
            bgimage = chip.icon,
            bgcolor = "white",
            width = size,
            height = size,
            valign = "center",
        }
    end
    return nil
end

--A small x that clears something, with its tooltip.
local function SearchX(tooltip, size, fn)
    return gui.Panel{
        classes = {"historySearchX"},
        bgimage = "phosphor/x-bold.png",
        width = size,
        height = size,
        lmargin = 4,
        valign = "center",
        linger = gui.Tooltip(tooltip),
        click = fn,
    }
end

--"My hero" faces beside search: one press filters History to a hero you control.
local MY_HERO_SIZE = 22
local MY_HERO_GAP = 4
local MY_HERO_MAX = 3

--The heroes this player controls on the map shown, in a steady order. A Director gets
--none: every monster is theirs to run, and search already covers picking one.
--- @return HistoryCreature[]
local function MyHeroes()
    local heroes = {}
    if dmhub.isDM then
        return heroes
    end
    for _, token in ipairs(dmhub.GetTokens{playerControlled = true}) do
        local props = token.properties
        if token.valid and token.canControlAsUser and props ~= nil and props:IsHero() then
            heroes[#heroes + 1] = History.Creature(token)
        end
    end
    table.sort(heroes, function(first, second)
        return first.id < second.id
    end)
    while #heroes > MY_HERO_MAX do
        heroes[#heroes] = nil
    end
    return heroes
end

local function CreateFace()
    local rowsWanted = ROWS_CHUNK
    local hasOlder = false
    local loadingOlder = false
    local anchor = nil
    local anchorTries = 0
    --how far below the top of the list the view was when older rows were asked for.
    local anchorDelta = 0
    local anchorHeight = 0
    --fillView's last measured list height, and how often it has looked.
    local fillHeight = -1
    local fillTries = 0
    --the frame of the last rebuild.
    local builtFrame = 0
    local face
    local list
    --true until the first build: History opens on "New since you last looked" when the
    --new rows don't all fit, so the first one is in view.
    local openAtMarker = true
    local markerTries = 0
    --The last build's items, and the row ShowEntry is bringing into view.
    --- @type table[]
    local builtItems = {}
    --- @type string|nil
    local showKey = nil
    local showTries = 0
    --The newest entry key the last build showed: a game refresh is not always a new row.
    --- @type string|nil
    local builtNewest = nil

    --Held while scrolled up: the row at the top of the view and how far into it the
    --view starts, so a rebuild puts it back where it was.
    --- @type Panel|nil
    local holdPanel = nil
    local holdDelta = 0
    local holdTries = 0
    --Row keys the reader has had in view at the bottom, and how many rows came in since.
    --- @type table<string, boolean>
    local seenKeys = {}
    local newBelow = 0
    --True once the view has left the default (see UpdateLatest).
    local away = false
    --the reader scrolled to the top of a list that scrolls, and older rows were built.
    local loadedOlder = false
    --- @type Panel|nil
    local newBelowButton = nil
    local rowsPanel

    --One pill at the list's foot takes you to the newest row. It counts the rows that
    --came in below the view, and reads "Latest" when there are none but the view is away.
    local function UpdateNewBelow()
        if newBelowButton == nil or not newBelowButton.valid then
            return
        end
        newBelowButton:SetClass("hidden", newBelow == 0 and not away)
        if newBelow > 0 then
            newBelowButton.text = string.format("%d new below", newBelow)
        elseif away then
            newBelowButton.text = "Latest"
        end
    end

    --Notes the row at the top of the view before a rebuild.
    local function CaptureAnchor()
        holdPanel = nil
        if list == nil or not list.valid or rowsPanel == nil then
            return
        end
        local windowHeight = list.renderedHeight or 0
        local contentHeight = rowsPanel.renderedHeight or 0
        local range = contentHeight - windowHeight
        if range <= 0 then
            return
        end
        local top = (1 - list.vscrollPosition) * range
        local rowTop = 0
        for _, row in ipairs(rowsPanel.children) do
            local rowHeight = row.renderedHeight or 0
            if rowTop + rowHeight > top then
                holdPanel = row
                holdDelta = top - rowTop
                return
            end
            rowTop = rowTop + rowHeight
        end
    end

    --The view is at the end of the list, or within half a row of it. On a long list a small
    --fraction of the scroll range is many pixels, enough to count a row in view as "new below".
    local function AtBottom()
        local range = (rowsPanel.renderedHeight or 0) - (list.renderedHeight or 0)
        return list.vscrollPosition <= 0.02 or list.vscrollPosition * range <= 24
    end

    --Latest shows only once the view has left the default: scrolled up, older rows
    --loaded, or a round or turn opened or closed by hand.
    local function UpdateLatest()
        if list == nil or not list.valid then
            return
        end
        --a list too short to scroll reports a position that means nothing, and fills its
        --own spare room with older rows: neither is the reader moving away.
        local scrollable = rowsPanel ~= nil and (rowsPanel.renderedHeight or 0) - (list.renderedHeight or 0) > 1
        away = (scrollable and (not AtBottom() or loadedOlder)) or next(g_open) ~= nil
        UpdateNewBelow()
    end
    --The map History shows: the one last clicked, held while someone reads; the
    --switcher or a preview row from another map can show another until the next click.
    local mapid = g_showMapOnOpen or History.CurrentMap()
    --the map last clicked, as last seen: a change to it is a new click to follow.
    local followed = History.CurrentMap()
    g_showMapOnOpen = nil
    --what was seen before this opening: kept by the rail's mark if that came first. The
    --rail's mark is for the map you are on, so opening on another map shows no marker.
    if mapid ~= History.CurrentMap() then
        g_since = nil
    elseif g_sinceAtOpen ~= nil then
        g_since = g_sinceAtOpen or nil
    else
        g_since = History.LastLooked(mapid)
    end
    g_sinceAtOpen = nil

    --Built rows by item key: {panel, sig}.
    local rows = {}

    rowsPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "bottom",
    }


    --The row whose card is open, the card, and where it was put.
    --- @type {key: string, sig: any, item: table}|nil
    local selected = nil
    --- @type Panel|nil
    local card = nil
    --- @type {x: number, width: number, maxHeight: number, inTray: boolean, reserve: number|nil}|nil
    local cardPlace = nil

    --The action bar is drawn over rail windows and takes the clicks there, so the card
    --treats its strip as the foot of the screen: always, so nothing moves when a token is
    --selected. Returns how far the strip reaches up from the foot of the layer, in layer
    --units, for a card between left and right (layer units); 0 when the card is beside it.
    local function BarReserve(layer, left, right)
        local hud = GameHud.instance
        local bar = hud and hud.actionBarPanel or nil
        if bar ~= nil and bar.valid then
            if g_barRow == nil or not g_barRow.valid then
                g_barRow = bar:GetChildrenWithClassRecursive("actionBar")[1]
            end
            --measured while the bar shows; kept for when it is hidden, when it has no place.
            if g_barRow ~= nil and g_barRow.valid and (g_barRow.renderedHeight or 0) > 0 then
                local edges = g_barRow.distancesToScreenEdge
                if edges.w > 0 and edges.w < dmhub.screenHeight then
                    g_barStrip = {top = edges.w, left = edges.x, right = dmhub.screenWidth - edges.z}
                end
            end
        end
        local layerEdges = layer.distancesToScreenEdge
        local screenHeight = dmhub.screenHeight - layerEdges.w - layerEdges.y
        local screenWidth = dmhub.screenWidth - layerEdges.x - layerEdges.z
        if screenHeight <= 0 or screenWidth <= 0 then
            return 0
        end
        --screen pixels to layer units, each way.
        local ky = layer.renderedHeight / screenHeight
        local kx = layer.renderedWidth / screenWidth
        --until the bar has been seen once: its usual place, the middle of the foot.
        local strip = g_barStrip or {top = dmhub.screenHeight - 60, left = dmhub.screenWidth * 0.22, right = dmhub.screenWidth * 0.78}
        local barLeft = (strip.left - layerEdges.x) * kx
        local barRight = (strip.right - layerEdges.x) * kx
        if right <= barLeft or left >= barRight then
            return 0
        end
        return math.max(0, (dmhub.screenHeight - layerEdges.y - strip.top) * ky)
    end

    --Where the rail window sits on the screen layer, in layer units, with the top of this
    --face (below the window's header). Nil in a popped-out window: it has no room beside it.
    --- @return {x: number, top: number, w: number, scale: number, layer: Panel, layerWidth: number, layerHeight: number}|nil
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
            layer = layer,
            layerWidth = layer.renderedWidth - RailRightColumnWidth(),
            layerHeight = layer.renderedHeight,
        }
    end

    --Beside the window on the side with room, else over the list with a way back.
    local function CardPlace()
        local rect = WindowRect()
        if rect ~= nil then
            local needed = (History.CARD_WIDTH + CARD_GAP) * rect.scale
            local cardX = nil
            if rect.x + rect.w + needed <= rect.layerWidth then
                cardX = face.renderedWidth + CARD_GAP
            elseif rect.x - needed >= RAIL_LEFT then
                cardX = -(History.CARD_WIDTH + CARD_GAP)
            end
            if cardX ~= nil then
                --the card slides up or down to stay on the screen, so the screen's height bounds
                --it: less the action bar's strip when the card stands over it.
                local left = rect.x + cardX * rect.scale
                local reserve = BarReserve(rect.layer, left, left + History.CARD_WIDTH * rect.scale)
                local room = math.floor((rect.layerHeight - reserve - 2 * CARD_GAP) / rect.scale)
                return {x = cardX, width = History.CARD_WIDTH, maxHeight = math.min(room, CARD_HEIGHT), inTray = false, reserve = reserve}
            end
        end
        return {x = 0, width = g_trayWidth, maxHeight = face.renderedHeight, inTray = true}
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
        local toFaceUnits = face.renderedHeight / faceScreenHeight
        local rowTop = (row.panel.distancesToScreenEdge.w - faceEdges.w) * toFaceUnits
        local listTop = (list.distancesToScreenEdge.w - faceEdges.w) * toFaceUnits
        local listBottom = listTop + list.renderedHeight
        local target = rowTop + ROW_TITLE

        --as close to level as the screen allows; a row scrolled out of sight holds the card
        --at the edge of the list rather than leaving it beside nothing.
        local inSight = target >= listTop and target <= listBottom
        local level = math.max(listTop, math.min(target, listBottom))
        local cardHeight = card.renderedHeight
        local minY = CARD_GAP - rect.top / rect.scale
        local maxY = (rect.layerHeight - (cardPlace.reserve or 0) - rect.top) / rect.scale - CARD_GAP - cardHeight
        local cardY = math.max(minY, math.min(level - TAIL_DOWN, maxY))
        card.y = cardY

        --no tail when its row is out of sight, or the card couldn't reach it.
        local tailCenter = target - cardY
        local shown = inSight and tailCenter >= 14 and tailCenter <= cardHeight - 14
        tail:SetClass("collapsed", not shown)
        tail.y = cardY + tailCenter - tail.renderedHeight / 2
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

    --- @param fromGame boolean|nil New rows from the shared document, not the user's own click.
    local function Refresh(fromGame)
        if face == nil or not face.valid then
            return
        end
        local stick = AtBottom()
        --someone reading: the pointer on History, or a card open. mousePoint runs 0-1 inside
        --the panel and past that range outside it (not (0,0), whatever the stub says).
        local point = face.mousePoint
        local pointerIn = point ~= nil and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1
        local reading = selected ~= nil or pointerIn
        if not stick then
            CaptureAnchor()
        end
        --caught up: a new row while the reader sits at the bottom ends "New since you last
        --looked"; with History open, what arrives now is being watched.
        local keys = History.Keys(mapid)
        local newest = keys[#keys]
        if fromGame and stick and not openAtMarker and builtNewest ~= nil and newest ~= nil and newest > builtNewest then
            g_since = nil
        end
        builtNewest = newest
        local items, matches = BuildItems(mapid, fromGame == true and reading)
        builtItems = items
        local first = math.max(1, #items - rowsWanted + 1)
        --opening on new turns: build back far enough to include the marker.
        local markerShown = false
        if openAtMarker then
            for i, item in ipairs(items) do
                if item.kind == "newmarker" then
                    markerShown = true
                    if i < first then
                        first = i
                        rowsWanted = #items - i + 1
                    end
                end
            end
        end
        if g_toggled ~= nil then
            for i, item in ipairs(items) do
                if (item.key == "head-" .. g_toggled or item.key == "fold-" .. g_toggled) and i < first then
                    first = i
                    rowsWanted = #items - i + 1
                end
            end
            g_toggled = nil
        end
        hasOlder = first > 1
        face:FireEventTree("searchResults", matches)

        --a row redraws when what is still on changes (Active) or the search does (marks).
        --Only rows on show need it: making the string costs, and a long fight has hundreds.
        local function Sign(item)
            if not item.signed then
                item.signed = true
                local active = ActiveSignature(item)
                if active ~= "" or g_searchKey ~= "" then
                    item.sig = string.format("%s|%s|%s", tostring(item.sig), active, g_searchKey)
                end
            end
        end

        --an entry rewritten quietly keeps its row and card; it only takes the new signature.
        local quiet = History.quiet
        local quietSeen = false
        local function IsQuiet(item)
            local id = item.entry ~= nil and item.entry.id or nil
            if id ~= nil and quiet[id] then
                quietSeen = true
                return true
            end
            return false
        end

        local children = {}
        local kept = {}
        for i = first, #items do
            local item = items[i]
            Sign(item)
            local row = rows[item.key]
            if row ~= nil and row.sig ~= item.sig and row.panel.valid and IsQuiet(item) then
                row.sig = item.sig
            end
            if row == nil or row.sig ~= item.sig or not row.panel.valid then
                row = {panel = BuildRow(item), sig = item.sig}
            end
            kept[item.key] = row
            children[#children + 1] = row.panel
            row.panel:SetClass("historySelected", selected ~= nil and selected.key == item.key)
        end
        rows = kept
        --a tall window: build further back until the list scrolls, so scrolling to the top
        --can load the rest.
        fillTries = 0
        fillHeight = -1
        list:ScheduleEvent("fillView", 0.05)
        builtFrame = dmhub.FrameCount()
        if matches == 0 then
            children = {SearchEmpty()}
        elseif #items == 0 then
            children = {SearchEmpty("Nothing has happened on this map yet.")}
        end
        rowsPanel.children = children
        if stick and not loadingOlder then
            list:ScheduleEvent("toBottom", 0.02)
        elseif not loadingOlder and not openAtMarker and holdPanel ~= nil then
            --scrolled up: the row at the top of the view stays where it is.
            holdTries = 0
            list:ScheduleEvent("holdAnchor", 0.02)
        end

        --"{n} new below": rows that came in since the reader was last at the bottom.
        if stick then
            seenKeys = {}
            for _, item in ipairs(items) do
                seenKeys[item.key] = true
            end
            newBelow = 0
        else
            newBelow = 0
            for _, item in ipairs(items) do
                if item.entry ~= nil and not seenKeys[item.key] then
                    newBelow = newBelow + 1
                end
            end
        end
        UpdateNewBelow()
        if openAtMarker then
            openAtMarker = false
            if markerShown then
                markerTries = 0
                list:ScheduleEvent("toMarker", 0.05)
            end
        end
        UpdateLatest()

        --a trigger landing after the row closed changes what the open card says.
        if selected ~= nil then
            local found = false
            for _, item in ipairs(items) do
                if item.key == selected.key then
                    found = true
                    Sign(item)
                    if item.sig ~= selected.sig then
                        selected.sig = item.sig
                        selected.item = item
                        if not IsQuiet(item) then
                            ShowCard(item)
                        end
                    end
                    break
                end
            end
            --its entry was deleted, or the search no longer finds it: the card goes with the row.
            if not found then
                Select(nil)
            end
        end
        if quietSeen then
            History.quiet = {}
        end
    end

    list = gui.Panel{
        flow = "vertical",
        width = string.format("100%%-%d", EDGE_STRIP),
        height = string.format("100%%-%d", BAR_HEIGHT + (Searching() and CHIP_ROW_HEIGHT or 0)),
        halign = "left",
        vscroll = true,
        rowsPanel,

        toBottom = function(element)
            element.vscrollPosition = 0
            UpdateLatest()
            newBelow = 0
            seenKeys = {}
            for key in pairs(rows) do
                seenKeys[key] = true
            end
            UpdateNewBelow()
        end,

        --puts the held row back at the top of the view. Layout takes a few frames.
        holdAnchor = function(element)
            holdTries = holdTries + 1
            local windowHeight = element.renderedHeight or 0
            local contentHeight = rowsPanel.renderedHeight or 0
            local range = contentHeight - windowHeight
            if holdPanel ~= nil and holdPanel.valid and range > 0 then
                local rowTop = nil
                local offset = 0
                for _, row in ipairs(rowsPanel.children) do
                    if row == holdPanel then
                        rowTop = offset
                        break
                    end
                    offset = offset + (row.renderedHeight or 0)
                end
                if rowTop ~= nil then
                    element.vscrollPosition = 1 - math.max(0, math.min(rowTop + holdDelta, range)) / range
                end
            end
            if holdTries < 4 then
                element:ScheduleEvent("holdAnchor", 0.03)
            end
        end,

        --brings ShowEntry's row to the top of the view, then opens its card. Layout takes a
        --few frames, so it retries; the card opens on the last try, once the row is placed.
        toEntry = function(element)
            showTries = showTries + 1
            local row = showKey ~= nil and rows[showKey] or nil
            local windowHeight = element.renderedHeight or 0
            local contentHeight = rowsPanel.renderedHeight or 0
            local range = contentHeight - windowHeight
            if row ~= nil and row.panel.valid and range > 0 then
                local offset = 0
                for _, child in ipairs(rowsPanel.children) do
                    if child == row.panel then
                        break
                    end
                    offset = offset + (child.renderedHeight or 0)
                end
                element.vscrollPosition = 1 - math.min(offset, range) / range
            end
            if showTries < 5 then
                element:ScheduleEvent("toEntry", 0.05)
                return
            end
            for _, item in ipairs(builtItems) do
                if item.key == showKey and item.entry ~= nil then
                    --a plain line has no card: scrolling to it is all there is to show.
                    if HasCard(item.entry) and (selected == nil or selected.key ~= item.key) then
                        Select(item)
                    end
                    break
                end
            end
            showKey = nil
            UpdateLatest()
        end,

        --puts the new-rows marker at the top when what follows it is taller than the list;
        --otherwise the bottom already shows it. Layout takes a few frames, so it retries.
        toMarker = function(element)
            markerTries = markerTries + 1
            local marker = rows["newmarker"]
            local windowHeight = element.renderedHeight or 0
            local contentHeight = rowsPanel.renderedHeight or 0
            local range = contentHeight - windowHeight
            if marker ~= nil and marker.panel.valid and range > 0 then
                local offset = 0
                for _, row in ipairs(rowsPanel.children) do
                    if row == marker.panel then
                        break
                    end
                    offset = offset + (row.renderedHeight or 0)
                end
                if contentHeight - offset > windowHeight then
                    element.vscrollPosition = 1 - math.min(offset, range) / range
                end
            end
            if markerTries < 6 then
                element:ScheduleEvent("toMarker", 0.05)
            else
                UpdateLatest()
            end
        end,

        --the rows built don't reach a quarter of a view above the bottom one: build more now,
        --so there is always room to scroll up into (and so to load more).
        --Layout takes a few frames, so it waits until the height stops changing.
        fillView = function(element)
            local contentHeight = rowsPanel.renderedHeight or 0
            fillTries = fillTries + 1
            if contentHeight ~= fillHeight and fillTries < 8 then
                fillHeight = contentHeight
                element:ScheduleEvent("fillView", 0.05)
                return
            end
            local windowHeight = element.renderedHeight or 0
            if hasOlder and not loadingOlder and windowHeight > 0 and contentHeight < windowHeight * 1.25 then
                rowsWanted = rowsWanted + ROWS_CHUNK
                Refresh()
            end
        end,

        --at the top with more to show: build the next rows and hold the view still.
        scroll = function(element)
            AlignCard()
            UpdateLatest()
            --back at the bottom: everything is seen.
            if newBelow > 0 and AtBottom() then
                newBelow = 0
                seenKeys = {}
                for key in pairs(rows) do
                    seenKeys[key] = true
                end
                UpdateNewBelow()
            end
            --load while still half a view from the top, so the rows are there before they
            --scroll into sight.
            local range = (rowsPanel.renderedHeight or 0) - (element.renderedHeight or 0)
            local fromTop = (1 - element.vscrollPosition) * math.max(range, 0)
            --a rebuild moves the view for a few frames before it is put back: only the
            --reader's own scrolling loads more.
            local settling = dmhub.FrameCount() - builtFrame < 10
            if hasOlder and not loadingOlder and not settling and range > 0 and fromTop < (element.renderedHeight or 0) * 0.5 then
                loadingOlder = true
                anchor = rowsPanel.children[1]
                anchorTries = 0
                anchorDelta = fromTop
                if (rowsPanel.renderedHeight or 0) - (element.renderedHeight or 0) > 1 then
                    loadedOlder = true
                end
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
            --settled: stop, so a reader still scrolling isn't pulled back.
            local settled = anchorTries > 1 and contentHeight == anchorHeight
            anchorHeight = contentHeight
            if not settled and anchor ~= nil and anchor.valid and range > 0 then
                local offset = 0
                for _, row in ipairs(rowsPanel.children) do
                    if row == anchor then
                        break
                    end
                    offset = offset + (row.renderedHeight or 0)
                end
                element.vscrollPosition = 1 - math.min(offset + anchorDelta, range) / range
            end
            if settled or anchorTries >= 6 then
                anchor = nil
                loadingOlder = false
            else
                element:ScheduleEvent("anchorOlder", 0.05)
            end
        end,
    }

    --Search: the field in the bar above the list, and its chips and match count on a row
    --under it.
    local searchInput
    local chipRow
    local heroRow

    --The suggestion rows the arrows walk, and the one they're on (0 = none yet).
    --- @type Panel[]
    local suggestRows = {}
    local cursor = 0

    local function ListHeight()
        local extra = Searching() and CHIP_ROW_HEIGHT or 0
        return string.format("100%%-%d", BAR_HEIGHT + extra)
    end

    --The search changed: redraw the chips, filter the rows, start at the newest.
    local function ApplySearch()
        UpdateSearchKey()
        Select(nil)
        rowsWanted = ROWS_CHUNK
        loadedOlder = false
        chipRow:FireEvent("rebuild")
        chipRow:SetClass("collapsed", not Searching())
        heroRow:FireEvent("searchChanged")
        list.selfStyle.height = ListHeight()
        Refresh()
        list:ScheduleEvent("toBottom", 0.05)
    end

    local function CloseSuggestions()
        suggestRows = {}
        cursor = 0
        if searchInput ~= nil and searchInput.valid then
            searchInput.popup = nil
        end
    end

    local function AddChip(chip)
        g_search.chips[#g_search.chips + 1] = chip
        g_search.text = ""
        searchInput.textNoNotify = ""
        CloseSuggestions()
        ApplySearch()
    end

    local function MoveCursor(delta)
        if #suggestRows == 0 then
            return
        end
        if suggestRows[cursor] ~= nil and suggestRows[cursor].valid then
            suggestRows[cursor]:SetClass("searchfocus", false)
        end
        cursor = cursor + delta
        if cursor < 1 then
            cursor = #suggestRows
        elseif cursor > #suggestRows then
            cursor = 1
        end
        suggestRows[cursor]:SetClass("searchfocus", true)
    end

    local function ShowSuggestions()
        CloseSuggestions()
        local typed = string.lower(string.match(g_search.text or "", "^%s*(.-)%s*$"))
        local groups = Suggestions(mapid, typed)
        if #groups == 0 then
            return
        end
        local children = {}
        for _, group in ipairs(groups) do
            children[#children + 1] = gui.Label{
                classes = {"historySuggestGroup"},
                text = group.title,
                width = "100%",
                height = "auto",
                hpad = 10,
                tmargin = 4,
                borderBox = true,
            }
            for _, item in ipairs(group.items) do
                local chip = item.chip
                local picture = ChipPicture(chip, 18)
                local row = gui.Panel{
                    classes = {"historySuggestRow"},
                    bgimage = "panels/square.png",
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    hpad = 10,
                    vpad = 3,
                    borderBox = true,
                    press = function()
                        AddChip(chip)
                    end,
                    picture,
                    gui.Label{
                        classes = {"historySuggestText"},
                        text = chip.kind == "type" and string.format("All %s", chip.name) or chip.name,
                        width = "auto",
                        height = "auto",
                        lmargin = picture ~= nil and 8 or 0,
                        valign = "center",
                    },
                    --what a creature was found by, when it was not its name.
                    chip.type ~= nil and gui.Label{
                        classes = {"historySearchCount"},
                        text = chip.type,
                        width = "auto",
                        height = "auto",
                        lmargin = 6,
                        valign = "center",
                    } or nil,
                    gui.Label{
                        classes = {"historySearchCount"},
                        text = tostring(item.count),
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        valign = "center",
                    },
                }
                children[#children + 1] = row
                suggestRows[#suggestRows + 1] = row
            end
        end
        --Enter takes the top suggestion until the arrows pick another, so mark it.
        cursor = 1
        suggestRows[1]:SetClass("searchfocus", true)
        searchInput.popupPositioning = "panel"
        searchInput.popup = gui.Panel{
            classes = {"historySuggestions"},
            styles = ThemeEngine.MergeStyles(Styles()),
            bgimage = "panels/square.png",
            flow = "vertical",
            --grows downward from under the field.
            pivot = {x = 0.5, y = 1},
            width = searchInput.renderedWidth > 0 and searchInput.renderedWidth or 280,
            height = "auto",
            maxHeight = 320,
            vscroll = true,
            vpad = 4,
            borderBox = true,
            borderWidth = 1,
            cornerRadius = 5,
            halign = "center",
            valign = "bottom",
            children = children,
        }
    end

    searchInput = gui.SearchInput{
        placeholderText = "Search creatures, abilities, conditions",
        text = g_search.text,
        width = g_trayWidth - 12 - 12,
        --the theme's hpad 24 must sit inside the width, not on top of it.
        borderBox = true,
        height = 22,
        halign = "left",
        valign = "center",
        lmargin = 12,
        editlag = 0.15,
        edit = function(element)
            if element.text == g_search.text then
                return
            end
            g_search.text = element.text
            ApplySearch()
            if element.hasInputFocus then
                ShowSuggestions()
            end
        end,
        --the same search, for text that arrives without an edit event.
        change = function(element)
            if element.text ~= g_search.text then
                g_search.text = element.text
                ApplySearch()
            end
        end,
        uparrow = function(element)
            MoveCursor(-1)
        end,
        downarrow = function(element)
            MoveCursor(1)
        end,
        submit = function(element)
            local row = suggestRows[math.max(cursor, 1)]
            if row ~= nil and row.valid then
                row:FireEvent("press")
            end
        end,
        --Escape, or a click away: close the suggestions but keep the search. A click on a
        --suggestion also leaves the field, so wait until its press has landed.
        deselect = function(element)
            element:ScheduleEvent("historyCloseSuggest", 0.2)
        end,
        historyCloseSuggest = function(element)
            if not element.hasInputFocus then
                CloseSuggestions()
            end
        end,
    }

    chipRow = gui.Panel{
        classes = {cond(Searching(), nil, "collapsed")},
        flow = "horizontal",
        width = string.format("100%%-%d", EDGE_STRIP),
        height = CHIP_ROW_HEIGHT,
        hpad = 12,
        borderBox = true,
        halign = "left",
        rebuild = function(element)
            local children = {}
            for i, chip in ipairs(g_search.chips) do
                local picture = ChipPicture(chip, 16)
                children[#children + 1] = gui.Panel{
                    classes = {"historySearchChip"},
                    bgimage = "panels/square.png",
                    flow = "horizontal",
                    width = "auto",
                    height = 20,
                    lpad = 3,
                    rpad = 4,
                    borderBox = true,
                    cornerRadius = 10,
                    rmargin = 4,
                    valign = "center",
                    picture,
                    gui.Label{
                        classes = {"historySearchChipText"},
                        text = chip.name,
                        width = "auto",
                        height = "auto",
                        lmargin = picture ~= nil and 4 or 2,
                        valign = "center",
                    },
                    SearchX(string.format("Remove %s", chip.name), 9, function()
                        table.remove(g_search.chips, i)
                        ApplySearch()
                    end),
                }
            end
            children[#children + 1] = gui.Label{
                classes = {"historySearchCount"},
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                searchResults = function(label, matches)
                    if matches ~= nil and matches > 0 then
                        label.text = matches == 1 and "1 match" or string.format("%d matches", matches)
                    else
                        label.text = ""
                    end
                end,
            }
            if #g_search.chips > 0 then
                children[#children + 1] = SearchX("Clear the search", 10, function()
                    g_search.chips = {}
                    g_search.text = ""
                    searchInput.textNoNotify = ""
                    ApplySearch()
                end)
            end
            element.children = children
        end,
    }
    chipRow:FireEvent("rebuild")
    UpdateSearchKey()

    --True while the search is exactly this hero's chip, which is what a face press sets.
    --- @param who HistoryCreature
    local function HeroFilterOn(who)
        local chips = g_search.chips
        return #chips == 1 and chips[1].kind == "creature" and chips[1].key == who.id and g_search.text == ""
    end

    --A face's ring width is set on the panel itself, so the on look thickens it there.
    --- @param panel Panel
    --- @param who HistoryCreature
    local function MarkHero(panel, who)
        local on = HeroFilterOn(who)
        panel:SetClass("historyMyHeroOn", on)
        panel.selfStyle.borderWidth = on and 2 or 1
    end

    --The "my hero" faces, right of search. Rebuilt only when the heroes change;
    --the search field gives up the width they take.
    local heroSig = nil
    --- @type HistoryCreature[]
    local shownHeroes = {}
    heroRow = gui.Panel{
        --the accent ring follows the search: a chip removed by its x turns the face off.
        searchChanged = function(element)
            for i, child in ipairs(element.children) do
                local who = shownHeroes[i]
                if who ~= nil then
                    MarkHero(child, who)
                end
            end
        end,
        flow = "horizontal",
        width = "auto",
        height = MY_HERO_SIZE,
        halign = "right",
        valign = "center",
        heroes = function(element)
            local heroes = MyHeroes()
            --the search field beside the faces takes the rest of the width.
            local sig = tostring(g_trayWidth) .. ":"
            for _, who in ipairs(heroes) do
                sig = string.format("%s%s|%s|%s;", sig, who.id, tostring(who.name), tostring(who.img))
            end
            if sig == heroSig then
                return
            end
            heroSig = sig
            local children = {}
            for _, who in ipairs(heroes) do
                local heroFace = Face(who, MY_HERO_SIZE, false, {
                    tip = function()
                        if HeroFilterOn(who) then
                            return "Show everything"
                        end
                        return string.format("Show only %s", ShownName(who))
                    end,
                    click = function()
                        if HeroFilterOn(who) then
                            g_search.chips = {}
                        else
                            g_search.chips = {{kind = "creature", key = who.id, name = ShownName(who), who = who}}
                        end
                        g_search.text = ""
                        searchInput.textNoNotify = ""
                        CloseSuggestions()
                        ApplySearch()
                    end,
                })
                heroFace.selfStyle.lmargin = MY_HERO_GAP
                MarkHero(heroFace, who)
                children[#children + 1] = heroFace
            end
            shownHeroes = heroes
            element.children = children
            local taken = #heroes * (MY_HERO_SIZE + MY_HERO_GAP)
            if taken > 0 then
                taken = taken + SEARCH_GAP - MY_HERO_GAP
            end
            searchInput.selfStyle.width = g_trayWidth - 12 - 12 - taken
        end,
    }
    heroRow:FireEvent("heroes")

    --"{n} new below" or "Latest": floats over the list's foot (see UpdateNewBelow).
    newBelowButton = gui.Label{
        classes = {"historyButton", "historyNewBelow", "hidden"},
        bgimage = "panels/square.png",
        text = "",
        floating = true,
        width = "auto",
        height = 22,
        hpad = 10,
        borderBox = true,
        borderWidth = 1,
        cornerRadius = 11,
        halign = "center",
        valign = "bottom",
        y = -10,
        textAlignment = "center",
        click = function(element)
            if newBelow > 0 then
                list:FireEvent("toBottom")
                return
            end
            --Latest: back to the default folds, scrolled to the newest row.
            g_open = {}
            rowsWanted = ROWS_CHUNK
            loadedOlder = false
            --at the bottom first: a rebuild while scrolled up holds the row at the top of
            --the view in place, which would undo the jump.
            list.vscrollPosition = 0
            Refresh()
            KeepCardPlaced()
            list:ScheduleEvent("toBottom", 0.05)
        end,
    }

    --Shows another map's History: the view starts fresh there, as it does on opening.
    --- @param id string
    local function ShowMap(id)
        if id == mapid then
            return
        end
        mapid = id
        g_since = nil
        g_open = {}
        rowsWanted = ROWS_CHUNK
        loadedOlder = false
        Select(nil)
        face.monitorGame = History.DocPath(mapid)
        Refresh()
    end

    --someone reading: the pointer on History, or a card open. History holds its map then,
    --so a click on another map window does not swap the rows out from under them.
    local function Reading()
        local point = face.mousePoint
        return selected ~= nil or (point ~= nil and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1)
    end

    --Lays the rows out again for the window's width, once a resize has stopped. Rows
    --shorten names by estimated widths, so they are rebuilt, but once, not every frame of a
    --drag. No 320-600 clamp here: a window Chat owns can be narrower or wider.
    local resizeToken = 0
    local function ApplyWidth()
        local width = math.floor((face.renderedWidth or 0) - EDGE_STRIP)
        if width < 200 or width == g_trayWidth then
            return
        end
        g_trayWidth = width
        rows = {}
        heroRow:FireEvent("heroes")
        Refresh()
        if selected ~= nil then
            ShowCard(selected.item)
        end
    end

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
        refreshGame = function()
            Refresh(true)
        end,

        --follows the map last clicked (pressing a map window makes it the current map),
        --once no one is reading; until then the click waits.
        thinkTime = 1,
        think = function(element)
            if History.CurrentMap() ~= followed and not Reading() then
                followed = History.CurrentMap()
                ShowMap(followed)
            end
            heroRow:FireEvent("heroes")
            KeepCardPlaced()
            AlignCard()
        end,

        alignCard = function(element)
            AlignCard()
        end,

        rendered = function(element)
            resizeToken = resizeToken + 1
            local token = resizeToken
            dmhub.Schedule(0.25, function()
                if token == resizeToken and not mod.unloaded and element.valid then
                    ApplyWidth()
                end
            end)
        end,

        destroy = function()
            if g_tray ~= nil and g_tray.face == face then
                g_tray = nil
            end
            --closing History ends a search: reopening shows the default view, not an old
            --filter hiding new rows.
            g_since = nil
            g_search.chips = {}
            g_search.text = ""
            g_open = {}
        end,

        --the window's own header names the panel, so this bar holds search and the faces.
        gui.Panel{
            flow = "none",
            width = string.format("100%%-%d", EDGE_STRIP),
            height = BAR_HEIGHT,
            halign = "left",
            rpad = 12,
            borderBox = true,
            searchInput,
            heroRow,
        },
        chipRow,
        list,
        newBelowButton,
    }

    --SetSearch: g_search was changed from outside (History.OpenFor); show it.
    local function SetSearch()
        searchInput.textNoNotify = g_search.text
        CloseSuggestions()
        ApplySearch()
    end

    --Opens on one row: the Sidebar Preview's click. Stops the opening's own scroll
    --to the marker, which would otherwise pull the view back.
    --- @param key string The row's entry key.
    local function ShowEntry(key)
        showKey = key
        showTries = 0
        markerTries = 99
        list:ScheduleEvent("toEntry", 0.1)
    end

    g_tray = {face = face, Refresh = Refresh, Select = Select, SetSearch = SetSearch, ShowEntry = ShowEntry, ShowMap = ShowMap,
        MapId = function() return mapid end,
        --the row built for an entry key, once the list has it (the fold's landing spot).
        RowPanel = function(key)
            local row = rows[key]
            return row ~= nil and row.panel.valid and row.panel or nil
        end,
        List = function() return list end}
    list.vscrollPosition = 0
    Refresh()
    if g_showOnOpen ~= nil then
        ShowEntry(g_showOnOpen)
        g_showOnOpen = nil
    end
    return face
end

--- Shows one row of a map's History with its card open, once the window is up. The row's
--- map can be one the user is not on: History shows it until the next map click.
--- @param mapid string
--- @param key string The row's entry key.
function History.ShowEntry(mapid, key)
    if g_tray ~= nil and g_tray.face.valid then
        g_tray.ShowMap(mapid)
        g_tray.ShowEntry(key)
    else
        g_showMapOnOpen = mapid
        g_showOnOpen = key
    end
end

--The fold: when your own action ends, a small stand-in for its row (your face, the first
--target's, what they took) flies from the ability card to the new row, or to the rail
--button while History is closed. Nothing is built while idle.
--How long the flight takes: long enough to follow by eye.
local FOLD_SECONDS = 0.9

--From this far through the flight the copy fades out over the real row.
local FOLD_FADE_FROM = 0.75

--Opacity is not inherited by children, so fading a panel means fading every panel in it.
--- @param panel Panel
--- @param opacity number
local function SetTreeOpacity(panel, opacity)
    panel.selfStyle.opacity = opacity
    for _, child in ipairs(panel.children) do
        SetTreeOpacity(child, opacity)
    end
end

--Ease in-out cubic, the same curve as the map windows' minimise.
local function EaseInOut(progress)
    if progress < 0.5 then
        return 4 * progress * progress * progress
    end
    return 1 - ((-2 * progress + 2) ^ 3) / 2
end

--- Flies the stand-in for a row this client just wrote. Does nothing without an ability card
--- on screen, with Reduce Motion on, or for a row on a map History isn't showing.
--- @param entry HistoryEntry
function History.FoldIn(entry)
    --a player's copy is cut the way their row will be.
    local shown = History.ForViewer(entry)
    if shown == nil or shown.kind ~= "action" or shown.actor == nil or ThemeEngine.GetAccessibility().reduceMotion then
        return
    end
    entry = shown
    local hud = GameHud.instance
    local card = hud ~= nil and rawget(hud, "abilityDisplayPanel") or nil
    local layer = Tabletop.ButtonLayer()
    if card == nil or not card.valid or (card.renderedWidth or 0) <= 0 or layer == nil or not layer.valid then
        return
    end
    local cardRect = Tabletop.PanelRect(card)
    if cardRect == nil then
        return
    end
    local tray = g_tray
    local open = tray ~= nil and tray.face.valid
    if tray ~= nil and open and tray.MapId() ~= entry.map then
        return
    end
    local railButton = nil
    if not open then
        local _, _, button = PanelDocument.FindRailButton("history")
        railButton = button
        if railButton == nil or not railButton.valid then
            return
        end
    end
    local key = History.KeyOf(entry)

    --a copy of the row it becomes, built by the list's own row builder.
    local width = g_trayWidth
    local row = BuildAction({kind = "action", key = key, entry = entry, sources = {entry}, triggers = {}, showActor = true})

    local start = dmhub.Time()
    local from = {x = cardRect.x + (cardRect.w - width) / 2, y = cardRect.y + cardRect.h / 3}
    --the card frame's themed fill needs the theme's tokens, which the table layer lacks.
    --- @type Panel|nil
    local hiddenRow = nil
    local revealed = false
    local ghost
    ghost = gui.Panel{
        --the solid frame History's cards use over the list: square, no shadow below it.
        classes = {"historyCardFrame", "historyCardSolid"},
        styles = ThemeEngine.MergeStyles(Styles()),
        bgimage = true,
        floating = true,
        interactable = false,
        flow = "vertical",
        width = width,
        height = "auto",
        halign = "left",
        valign = "top",
        x = from.x,
        y = from.y,
        thinkTime = 0.01,
        children = {row},
        --however it goes (a reload, the table torn down), the real row must not stay hidden.
        destroy = function()
            if hiddenRow ~= nil and hiddenRow.valid then
                hiddenRow:SetClassTree("historyFoldHidden", false)
            end
        end,
        think = function(element)
            local progress = math.min(1, (dmhub.Time() - start) / FOLD_SECONDS)
            --aim where the row is now: the list adds it a frame or two after the write.
            local target = nil
            if open then
                if g_tray ~= nil and g_tray.face.valid then
                    local list = g_tray.List()
                    local rect = list.valid and Tabletop.PanelRect(list) or nil
                    local row = g_tray.RowPanel(key)
                    target = row ~= nil and Tabletop.PanelRect(row) or nil
                    --the real row stays hidden until the stand-in lands on it, so one row settles in.
                    --opacity is not inherited, so the whole row tree takes the class.
                    if row ~= nil and row ~= hiddenRow and not revealed then
                        if hiddenRow ~= nil and hiddenRow.valid then
                            hiddenRow:SetClassTree("historyFoldHidden", false)
                        end
                        hiddenRow = row
                        row:SetClassTree("historyFoldHidden", true)
                    end
                    --a row scrolled out of view (or not built yet): the list's bottom edge.
                    if rect ~= nil and (target == nil or target.y + 20 > rect.y + rect.h or target.y < rect.y) then
                        target = {x = rect.x, y = rect.y + rect.h - 30, w = rect.w, h = 30}
                    end
                end
            elseif railButton ~= nil and railButton.valid then
                target = Tabletop.PanelRect(railButton)
            end
            if target == nil or progress >= 1 then
                element:DestroySelf()
                return
            end
            --the last stretch cross-fades: the real row shows and the copy fades over it.
            local fade = math.max(0, (progress - FOLD_FADE_FROM) / (1 - FOLD_FADE_FROM))
            if fade > 0 and hiddenRow ~= nil and hiddenRow.valid then
                local shown = hiddenRow
                shown:SetClassTree("historyFoldReveal", true)
                shown:SetClassTree("historyFoldHidden", false)
                hiddenRow = nil
                --once faded in, the row goes back to its own styles (a used pip is dimmer).
                dmhub.Schedule(0.4, function()
                    if shown.valid then
                        shown:SetClassTree("historyFoldReveal", false)
                    end
                end)
            end
            revealed = revealed or fade > 0
            if fade > 0 then
                SetTreeOpacity(element, 1 - fade)
            end
            --it arrives by FOLD_FADE_FROM and fades in place, lined up with the row.
            local eased = EaseInOut(math.min(1, progress / FOLD_FADE_FROM))
            local ghostWidth, ghostHeight = element.renderedWidth or 0, element.renderedHeight or 0
            if ghostWidth <= 0 or ghostHeight <= 0 then
                return
            end
            --it shrinks to what it lands on: the row's width, from the row's top-left, when
            --History is open; a third of itself, centred, into the rail button.
            local endScale = open and math.min(1, target.w / ghostWidth) or 0.35
            local scale = 1 + (endScale - 1) * eased
            local toX, toY = target.x, target.y
            if not open then
                toX = target.x + target.w / 2 - ghostWidth * endScale / 2
                toY = target.y + target.h / 2 - ghostHeight * endScale / 2
            end
            local drawnX = from.x + (toX - from.x) * eased
            local drawnY = from.y + (toY - from.y) * eased
            --scale works from the panel's centre, so move the panel to keep that top-left.
            element.selfStyle.scale = scale
            element.x = drawnX - ghostWidth * (1 - scale) / 2
            element.y = drawnY - ghostHeight * (1 - scale) / 2
        end,
    }
    layer:AddChild(ghost)
    --interactable = false covers the frame only: the row inside would still take clicks
    --meant for the map under its flight.
    ghost:MakeNonInteractiveRecursive()
end

--The map switcher's width in the title row, when it shows.
local SWITCHER_WIDTH = 170

--- The map switcher in History's title row: the shown map's name, cut short when long,
--- with a menu of every map in combat. It takes no room until two or more of the maps this
--- user can see are in combat. Each rail window showing History builds its own.
--- @return Panel
function History.MapSwitcher()
    local sig = nil

    --the maps to offer and the one on show (the map you are on while History is building).
    local function Maps()
        local ids = {}
        for _, id in ipairs(VisibleMaps()) do
            if id == History.NO_MAP or Tabletop.MapInCombat(id) then
                ids[#ids + 1] = id
            end
        end
        local shown = History.CurrentMap()
        if g_tray ~= nil and g_tray.face.valid then
            shown = g_tray.MapId()
        end
        return ids, shown
    end

    local nameLabel = gui.Label{
        classes = {"historyMapName"},
        text = "",
        width = SWITCHER_WIDTH - 44,
        height = "auto",
        lmargin = 5,
        textWrap = false,
        textOverflow = "ellipsis",
        valign = "center",
    }

    local button = gui.Panel{
        classes = {"historyMapSwitcher", "collapsed"},
        bgimage = "panels/square.png",
        flow = "horizontal",
        width = SWITCHER_WIDTH,
        height = 22,
        hpad = 6,
        borderBox = true,
        borderWidth = 1,
        cornerRadius = 4,
        valign = "center",
        hover = function(element)
            gui.Tooltip{text = "Display history for another map", fontSize = 13}(element)
        end,
        click = function(element)
            local ids, shown = Maps()
            local entries = {}
            for _, id in ipairs(ids) do
                entries[#entries + 1] = {
                    text = MapLabel(id),
                    check = id == shown,
                    click = function()
                        element.popup = nil
                        if g_tray ~= nil and g_tray.face.valid then
                            g_tray.ShowMap(id)
                        end
                    end,
                }
            end
            element.tooltip = nil
            element.popup = gui.ContextMenu{entries = entries}
        end,
        gui.Panel{
            classes = {"historyMapIcon"},
            bgimage = "phosphor/map-trifold.png",
            width = 14,
            height = 14,
            valign = "center",
        },
        nameLabel,
        gui.Panel{
            classes = {"historyMapIcon"},
            bgimage = "phosphor/caret-down-fill.png",
            width = 10,
            height = 10,
            halign = "right",
            valign = "center",
        },
    }

    --The holder never collapses (a collapsed panel stops thinking); it shrinks to nothing
    --instead, and tells the title row so the tab chip gets the room back.
    return gui.Panel{
        styles = ThemeEngine.MergeStyles(Styles()),
        width = 0,
        height = 22,
        valign = "center",
        thinkTime = 1,
        create = function(element)
            element:FireEvent("think")
        end,
        think = function(element)
            local ids, shown = Maps()
            local now = table.concat(ids, "|") .. "/" .. tostring(shown)
            if now == sig then
                return
            end
            sig = now
            local show = #ids >= 2
            nameLabel.text = MapLabel(shown)
            if button:HasClass("collapsed") == show then
                button:SetClass("collapsed", not show)
                element.selfStyle.width = show and SWITCHER_WIDTH or 0
                element:FireEventOnParents("syncHeaderControl")
            end
        end,
        button,
    }
end

--The tray's styles, for History panels built outside the window (the rail's hover card).
History.Styles = Styles

ThemeEngine.OnThemeChanged(mod, function()
    if g_tray ~= nil and g_tray.face.valid then
        g_tray.face.styles = ThemeEngine.MergeStyles(Styles())
    end
end)

--- Opens History on one creature, from the token radial and hero cards. The search
--- becomes just that creature's chip, replacing any search there was, and the window
--- opens or comes to the front.
--- @param token CharacterToken
function History.OpenFor(token)
    --open first: closing clears the search, so it is set only once the window is up.
    DockablePanel.ShowPanelByName("History")
    local who = History.Creature(token)
    g_search.chips = {{kind = "creature", key = who.id, name = ShownName(who), who = who}}
    g_search.text = ""
    if g_tray ~= nil and g_tray.face.valid then
        g_tray.SetSearch()
    end
end

--Notifications. While History is closed its rail button counts the turns
--you have not seen: a grey count, or a gold diamond when one of them did something to a
--creature you control. Hovering the button shows what happened; opening clears it.

--Notifications on or off, per user.
setting{
    id = "history:notifications",
    description = "History notifications",
    editor = "check",
    default = true,
    storage = "preference",
    section = "general",
}

--The newest entry key this user has seen, per game and map. Kept on their own machine
--(a preference), so looking at History writes nothing anyone else has to load.
setting{
    id = "history:lastlooked",
    default = {},
    storage = "preference",
}

--- The newest entry key this user has seen on a map, or nil before they ever looked.
--- @param mapid string
--- @return string|nil
function History.LastLooked(mapid)
    local all = dmhub.GetSettingValue("history:lastlooked")
    local game = type(all) == "table" and all[dmhub.gameid] or nil
    return type(game) == "table" and game[mapid] or nil
end

--- Records the newest entry key seen on these maps, writing only when something changed.
--- @param marks table<string, string> Keys by map id.
local function SetLooked(marks)
    local all = dmhub.GetSettingValue("history:lastlooked")
    all = type(all) == "table" and table.shallow_copy(all) or {}
    local game = type(all[dmhub.gameid]) == "table" and table.shallow_copy(all[dmhub.gameid]) or {}
    local changed = false
    for mapid, key in pairs(marks) do
        if game[mapid] ~= key then
            game[mapid] = key
            changed = true
        end
    end
    if changed then
        all[dmhub.gameid] = game
        dmhub.SetSettingValue("history:lastlooked", all)
    end
end

--Whether a creature is this user's own: a player's controlled heroes; for the Director, the
--monsters (they played those turns themselves, so they saw them).
local function Mine(who)
    if who == nil then
        return false
    end
    if dmhub.isDM then
        return not who.hero
    end
    local token = dmhub.GetTokenById(who.id)
    return token ~= nil and token.canControl
end

--- @class HistoryUnseen
--- @field turns integer Turns not seen, the user's own excluded (out of combat: entries).
--- @field gold boolean A player: one of them did something to a creature they control.
--- @field lines {row: table, mine: boolean, turn: string}[] What happened, oldest first, as History.Story rows.

--Worked out at most every 0.4 s: the rail asks twice a second and the hover card asks too.
--- @type HistoryUnseen|nil
local g_unseen = nil
local g_unseenAt = -1

--- The index of the newest combat's first entry among keys[first..], when that combat began
--- after keys[first] (so something unseen came before it); nil otherwise. Entries this user
--- may not read are skipped when finding what came before.
--- @param mapid string
--- @param keys string[]
--- @param first integer
--- @return integer|nil
local function CombatStart(mapid, keys, first)
    for i = #keys, first + 1, -1 do
        local entry = History.Entry(mapid, keys[i])
        if entry ~= nil and entry.encounter ~= nil then
            for j = i - 1, first, -1 do
                local before = History.Entry(mapid, keys[j])
                if before ~= nil then
                    if before.encounter ~= entry.encounter then
                        return i
                    end
                    break
                end
            end
        end
    end
    return nil
end

--- What this user has not seen yet, across the maps they can follow.
--- @return HistoryUnseen
local function Unseen()
    local now = dmhub.Time()
    if g_unseen ~= nil and now - g_unseenAt < 0.4 then
        return g_unseen
    end
    --- @type HistoryUnseen
    local result = {turns = 0, gold = false, lines = {}}
    g_unseen = result
    g_unseenAt = now
    if not History.Enabled() or not dmhub.GetSettingValue("history:notifications") then
        return result
    end
    local turns = {}
    local baselines = {}
    for _, mapid in ipairs(VisibleMaps()) do
        local keys = History.Keys(mapid)
        local last = History.LastLooked(mapid)
        if last == nil then
            --never looked: what is there already is not news.
            if #keys > 0 then
                baselines[mapid] = keys[#keys]
            end
        else
            local first = #keys + 1
            while first > 1 and keys[first - 1] > last do
                first = first - 1
            end
            --a combat that began since: what came before it counts as seen.
            local start = CombatStart(mapid, keys, first)
            if start ~= nil then
                baselines[mapid] = keys[start - 1]
                first = start
            end
            for i = first, #keys do
                local entry = History.Entry(mapid, keys[i])
                --a quiet Malice line counts in its round heading only: there is no line to look at.
                if entry ~= nil and not entry.quiet then
                    local turnKey, owner
                    if entry.round ~= nil and entry.turn ~= nil then
                        turnKey = string.format("%s|%s|%s|%s", mapid, tostring(entry.encounter), entry.round, entry.turn)
                        owner = entry.owner
                    else
                        turnKey = mapid .. "|" .. keys[i]
                        owner = entry.actor or entry.who
                    end
                    if not Mine(owner) then
                        turns[turnKey] = true
                        local actorMine = Mine(entry.actor)
                        local function Add(row, mine)
                            result.lines[#result.lines + 1] = {row = row, mine = mine, turn = turnKey}
                        end
                        --a player's hand edit is what the Director's gold is for.
                        if dmhub.isDM and entry.byplayer then
                            result.gold = true
                        end
                        if entry.kind == "line" then
                            local mine = not dmhub.isDM and Mine(entry.who)
                            local words = LineWords(entry)
                            if words ~= nil and words ~= "" then
                                Add({who = {entry.who}, text = words}, mine)
                            end
                            if mine then
                                result.gold = true
                            end
                        else
                            for _, row in ipairs(History.Story(entry, {})) do
                                local mine = false
                                if not dmhub.isDM and not actorMine then
                                    for _, who in ipairs(row.who or {}) do
                                        if Mine(who) then
                                            mine = true
                                        end
                                    end
                                end
                                Add(row, mine)
                                if mine then
                                    result.gold = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if next(baselines) ~= nil then
        SetLooked(baselines)
    end
    for _ in pairs(turns) do
        result.turns = result.turns + 1
    end
    return result
end

--- Marks everything on the maps this user can follow as seen. The rail calls it while
--- History is on screen.
local function MarkAllLooked()
    --the rail marks History seen as it opens it, which can be before the window is built;
    --keep what was seen before for the window's "New since you last looked".
    if (g_tray == nil or not g_tray.face.valid) and g_sinceAtOpen == nil then
        g_sinceAtOpen = History.LastLooked(game.currentMapId) or false
    end
    local marks = {}
    for _, mapid in ipairs(VisibleMaps()) do
        local keys = History.Keys(mapid)
        if #keys > 0 then
            marks[mapid] = keys[#keys]
        end
    end
    SetLooked(marks)
    g_unseen = nil
end

--A theme colour as #rrggbb for the rail badge, which takes plain colours.
local function BadgeColour(token, fallback)
    local colour = ThemeEngine.ResolveTokens(token)
    if type(colour) ~= "string" or string.sub(colour, 1, 1) ~= "#" then
        return fallback
    end
    return string.sub(colour, 1, 7)
end

--How many lines the hover card shows before "and N more turns".
local PREVIEW_LINES = 3
--The hover card's width, and how far it stands off the rail button to clear its name label.
local PREVIEW_WIDTH = 320
local PREVIEW_CLEAR_LABEL = 80
--Seconds the pointer rests on the button before the card shows (the same as the detail hovers).
local PREVIEW_DELAY = 0.4

--- The rail button's hover card: what happened since you last looked, your
--- creatures first, while History is closed.
--- @param element Panel The rail button.
--- @param placement {halign: string, valign: string, inStrip: boolean|nil}
function History.ShowSincePreview(element, placement)
    --a short wait, so a pointer passing over the button on its way elsewhere shows nothing.
    dmhub.Schedule(PREVIEW_DELAY, function()
        if mod.unloaded or not element.valid or not element:HasClass("hover") then
            return
        end
        --the hover card takes over from the Sidebar Preview's bubble.
        PanelDocument.FadeRailBubble("history")
        if g_tray ~= nil and g_tray.face.valid then
            return
        end
        local unseen = Unseen()
        --nothing new: the plain name label, as on every other rail button.
        if unseen.turns == 0 then
            return
        end
        History.ShowSinceCard(element, placement, unseen)
    end)
end

--- Puts the hover card on the rail button (see History.ShowSincePreview).
--- @param element Panel
--- @param placement {halign: string, valign: string, inStrip: boolean|nil}|nil
--- @param unseen HistoryUnseen
function History.ShowSinceCard(element, placement, unseen)
    local shown = {}
    for _, line in ipairs(unseen.lines) do
        if line.mine and #shown < PREVIEW_LINES then
            shown[#shown + 1] = line
        end
    end
    for _, line in ipairs(unseen.lines) do
        if not line.mine and #shown < PREVIEW_LINES then
            shown[#shown + 1] = line
        end
    end
    local more = unseen.turns
    local counted = {}
    for _, line in ipairs(shown) do
        if not counted[line.turn] then
            counted[line.turn] = true
            more = more - 1
        end
    end
    local card = History.CreateSinceCard{
        rows = shown,
        more = math.max(0, more),
        width = PREVIEW_WIDTH,
    }
    if placement ~= nil and placement.inStrip then
        --on a group's strip: below the member, clear of the strip and the rail.
        card.selfStyle.halign = "center"
        card.selfStyle.valign = "bottom"
    else
        --out from the rail like the detail card from the window, past the button's name label.
        local right = placement == nil or placement.halign ~= "left"
        card.selfStyle.halign = right and "right" or "left"
        card.selfStyle.valign = "center"
        card.x = right and PREVIEW_CLEAR_LABEL or -PREVIEW_CLEAR_LABEL
    end
    element.tooltip = card
    card:MakeNonInteractiveRecursive()
end

History.Notify = {
    CreateFace = CreateFace,
    Unseen = Unseen,
    MarkAllLooked = MarkAllLooked,
    --grey count, or a gold diamond when something happened to your own creatures.
    BadgeStyle = function()
        if Unseen().gold then
            return {color = BadgeColour("@warning", "#E9C868"), shape = "diamond"}
        end
        return {color = BadgeColour("@fgMuted", "#9A9A9A")}
    end,
}

--Sidebar Preview. While History is closed, each new entry from someone
--else's turn shows beside the History button in the chat bubble; clicking a row opens
--History on it. It marks nothing seen: the badge keeps counting until History opens.

--Sidebar Preview on or off, per user.
setting{
    id = "history:sidebarpreview",
    description = "History Sidebar Preview",
    help = "Briefly shows actions from other turns beside the History button while History is closed.",
    editor = "check",
    default = true,
    storage = "preference",
    section = "general",
}

--How often the preview looks for new entries, in seconds.
local BUBBLE_TICK = 0.5
--A bubble row's width: the chat bubble's width less its padding.
local BUBBLE_ROW_WIDTH = 276
--The newest entry key looked at, by map. The first look only sets it: what is already
--there when you join is not news.
--- @type table<string, string|nil>
local g_bubbleNewest = {}
--New keys held for one tick, by map, so an action's triggers land in its row.
--- @type table<string, string[]>
local g_bubblePending = {}

--- The bubble rows for a batch of new entries on a map, oldest first. Entries caused by an
--- action in the batch go into its row; ones caused by an earlier action are left out.
--- @param mapid string
--- @param keys string[] Sorted.
--- @return {contents: Panel[], click: function}[]
local function BubbleRows(mapid, keys)
    local batch = {}
    local byId = {}
    for _, key in ipairs(keys) do
        local entry = History.Entry(mapid, key)
        if entry ~= nil then
            batch[#batch + 1] = {key = key, entry = entry}
            byId[entry.id] = entry
            for _, alias in ipairs(entry.aliases or {}) do
                byId[alias] = entry
            end
        end
    end
    local kids = {}
    for _, item in ipairs(batch) do
        local entry = item.entry
        if entry.cause ~= nil then
            local root = RootAction(entry, byId)
            if root ~= nil then
                kids[root.id] = kids[root.id] or {}
                table.insert(kids[root.id], entry)
            end
        end
    end

    local wantedRows = {}
    for _, item in ipairs(batch) do
        local entry = item.entry
        local owner
        if entry.round ~= nil and entry.turn ~= nil then
            owner = entry.owner
        else
            owner = entry.actor or entry.who
        end
        --(a Malice line a player may not see is already left out by History.Entry)
        local wanted = entry.cause == nil and not Mine(owner)
        local args = nil
        if wanted and entry.kind == "line" then
            local words = LineWords(entry)
            if words ~= nil and words ~= "" then
                args = {rows = {{row = {who = {entry.who}, text = words}, mine = not dmhub.isDM and Mine(entry.who)}}}
            end
        elseif wanted and entry.kind == "action" and entry.actor ~= nil and entry.ability ~= nil then
            local actorMine = Mine(entry.actor)
            local story = {}
            for _, row in ipairs(History.Story(entry, kids[entry.id] or {})) do
                local mine = false
                if not dmhub.isDM and not actorMine then
                    for _, who in ipairs(row.who or {}) do
                        if Mine(who) then
                            mine = true
                        end
                    end
                end
                story[#story + 1] = {row = row, mine = mine}
            end
            args = {title = History.ShownName(entry.actor) .. History.DOT .. entry.ability.name, rows = story}
        end
        if args ~= nil then
            wantedRows[#wantedRows + 1] = {args = args, key = item.key}
        end
    end
    --the bubble keeps only its newest few rows; building the rest would show a big batch
    --(an award to every Hero) at full size for a moment, then leave its panels unattached.
    local rows = {}
    for i = math.max(1, #wantedRows - PanelDocument.CHAT_BUBBLE_MAX_ROWS + 1), #wantedRows do
        local args = wantedRows[i].args
        local key = wantedRows[i].key
        args.width = BUBBLE_ROW_WIDTH
        rows[#rows + 1] = {
            contents = History.CreateBubbleContents(args),
            click = function()
                History.ShowEntry(mapid, key)
            end,
        }
    end
    return rows
end

--Looks for new entries every BUBBLE_TICK. New keys wait one quiet tick, then show together.
local function BubbleTick()
    if mod.unloaded then
        return
    end
    dmhub.Schedule(BUBBLE_TICK, BubbleTick)
    --no History button to hang a preview off for someone on the old Action Log.
    if History.UsingOldLog() then
        g_bubbleNewest = {}
        g_bubblePending = {}
        return
    end
    local show = dmhub.GetSettingValue("history:sidebarpreview") and not PanelDocument.PanelInFront("history", "History")
    for _, mapid in ipairs(VisibleMaps()) do
        local keys = History.Keys(mapid)
        local newest = keys[#keys]
        local last = g_bubbleNewest[mapid]
        g_bubbleNewest[mapid] = newest
        local pending = g_bubblePending[mapid]
        if last ~= nil and newest ~= nil and newest > last then
            pending = pending or {}
            for i = #keys, 1, -1 do
                if keys[i] <= last then
                    break
                end
                pending[#pending + 1] = keys[i]
            end
            g_bubblePending[mapid] = pending
        elseif pending ~= nil then
            g_bubblePending[mapid] = nil
            table.sort(pending)
            if show then
                local rows = BubbleRows(mapid, pending)
                if #rows > 0 then
                    PanelDocument.ShowRailBubble{key = "history", panelName = "History", rows = rows}
                end
            end
        end
    end
end
dmhub.Schedule(BUBBLE_TICK, BubbleTick)

--A rail panel like Chat, so it gets the rail windows' frame, pin, pop out and Font Size zoom.
DockablePanel.Register{
    name = "History",
    icon = "phosphor/clock-counter-clockwise-bold.png",
    --hidden for a user who chose the old Action Log (History.UsingOldLog).
    available = function()
        return not History.UsingOldLog()
    end,
    --a dock saved with the old Action Log shows History in its place.
    standsInFor = "Action Log",
    vscroll = false,
    minHeight = 200,
    defaultWidth = TRAY_DEFAULT_WIDTH + EDGE_STRIP,
    minWidth = TRAY_MIN_WIDTH + EDGE_STRIP,
    maxWidth = TRAY_MAX_WIDTH + EDGE_STRIP,
    --looked up when called, like the hooks below: after a reload the window and the rail's
    --"seen" mark must come from the same copy of this file, or "New since you last looked" is lost.
    content = function()
        return History.Notify.CreateFace()
    end,
    --the rail button's badge and hover card. The rail keeps these functions, so each
    --looks up History.Notify when called: a reloaded HistoryTray takes effect at once.
    hasNewContent = function()
        return History.Notify.Unseen().turns > 0
    end,
    newContentCount = function()
        return History.Notify.Unseen().turns
    end,
    newContentStyle = function()
        return History.Notify.BadgeStyle()
    end,
    markContentSeen = function()
        History.Notify.MarkAllLooked()
    end,
    --looked up on each hover, so a reloaded HistoryTray's card is the one shown.
    railHover = function(element, placement)
        History.ShowSincePreview(element, placement)
    end,
    --the map switcher in the window's title row.
    headerControl = function()
        return History.MapSwitcher()
    end,
}

--Puts the log this user sees (History, or the old Action Log if they chose it) directly
--below Chat, once; a button already on their rail stays where they put it.
local function PlaceRailButton()
    if History.UsingOldLog() then
        --the rail draws the old log in History's slot (its standsInFor), so a stored layout
        --keeps History's key and matches its View; only a layout with no History gets one.
        local layout = dmhub.GetSettingValue("iconraillayout") or {}
        if layout["history"] == nil then
            PanelDocument.RailPlaceBelow("action log", "chat")
        end
    --a layout from before History: History takes the old log's slot, else goes below Chat.
    elseif not PanelDocument.RailSwapPanel("action log", "history") then
        PanelDocument.RailPlaceBelow("history", "chat")
    end
end

--"Use Old Action Log" changed: swap the buttons now, not at the next reload.
local function LogChoiceChanged()
    PlaceRailButton()
    PanelDocument.RebuildRails()
end

History.OnEnabledChanged = LogChoiceChanged
--after a game's first-entry View and any View applied later, whose templates place History
--but never the old Action Log.
PanelDocument.OnRailLayoutApplied("history", function()
    if not mod.unloaded then
        PlaceRailButton()
    end
end)
