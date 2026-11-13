local mod = dmhub.GetModLoading()

--- The Rearrange Campaigns screen and the saved campaign order it writes.
--- @class CampaignRearrange: GameType
--- @field new fun(o?: table): CampaignRearrange
CampaignRearrange = RegisterGameType("CampaignRearrange")

local PER_PAGE = 4
local CARD_WIDTH = 300
local ART_HEIGHT = 169
local GAP_WIDTH = 24
local ROW_MARGIN = 16
local HEADER_MARGIN = 16
local FOOTER_MARGIN = 20
local ROW_WIDTH = PER_PAGE * CARD_WIDTH + (PER_PAGE + 1) * GAP_WIDTH
local FALLBACK_ART = "panels/backgrounds/delian-tomb-bg.png"

local ARROW_UP_ICON = "phosphor/arrow-fat-up-thin.png"
local ARROW_DOWN_ICON = "phosphor/arrow-fat-down-thin.png"

local g_directorOrderSetting = setting{
    id = "campaignorder:director",
    storage = "account",
    default = "",
}

local g_playerOrderSetting = setting{
    id = "campaignorder:player",
    storage = "account",
    default = "",
}

local g_extras = {
    {
        selectors = {"panel", "rearrangeGap"},
        bgcolor = "clear",
    },
    {
        selectors = {"rearrangeCard", "moved"},
        border = 3,
        borderColor = "@accent",
    },
    {
        selectors = {"iconButton", "disabled"},
        opacity = 0.3,
    },
    {
        selectors = {"panel", "rearrangeSortIcon"},
        bgcolor = "@fg",
    },
    {
        selectors = {"panel", "rearrangeSortIcon", "parent:hover"},
        bgcolor = "@fgInverse",
    },
}

--- @param directorMode boolean
local function OrderSetting(directorMode)
    if directorMode then
        return g_directorOrderSetting
    end
    return g_playerOrderSetting
end

--- @param directorMode boolean
--- @return string[]
local function ReadSavedIds(directorMode)
    local ids = {}
    local stored = OrderSetting(directorMode):Get()
    if type(stored) ~= "string" then
        return ids
    end
    for id in string.gmatch(stored, "[^,]+") do
        ids[#ids + 1] = id
    end
    return ids
end

--- The ids of games, ordered by ids first (skipping any no longer present), then the rest in engine order.
--- @param ids string[]
--- @param games LuaGameInfo[]
--- @return string[]
local function MergeOrder(ids, games)
    local present = {}
    for _, game in ipairs(games) do
        present[game.gameid] = true
    end
    local result = {}
    local placed = {}
    for _, id in ipairs(ids) do
        if present[id] and not placed[id] then
            result[#result + 1] = id
            placed[id] = true
        end
    end
    for _, game in ipairs(games) do
        if not placed[game.gameid] then
            result[#result + 1] = game.gameid
            placed[game.gameid] = true
        end
    end
    return result
end

--- @param a string[]
--- @param b string[]
--- @return boolean
local function SameOrder(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

--- @param ids string[]
--- @return string[]
local function CopyIds(ids)
    local result = {}
    for i, id in ipairs(ids) do
        result[i] = id
    end
    return result
end

--- Case-insensitive name key with digit runs zero-padded, so "Session 2" sorts before "Session 10".
--- @param game LuaGameInfo
--- @return string
local function NameKey(game)
    local key = string.gsub(string.lower(tostring(game.description or "")), "%d+", function(digits)
        return string.rep("0", 12 - #digits) .. digits
    end)
    return key
end

--- The games shown in the Director view (owned) or the Player view (not owned), in engine order.
--- @param directorMode boolean
--- @return LuaGameInfo[]
function CampaignRearrange.ViewGames(directorMode)
    local result = {}
    for _, game in ipairs(lobby.games or {}) do
        if (game.owner == dmhub.loginUserid) == directorMode then
            result[#result + 1] = game
        end
    end
    return result
end

--- The view's games in the saved order; games the order does not name follow in engine order. Never writes.
--- @param games LuaGameInfo[]
--- @param directorMode boolean
--- @return LuaGameInfo[]
function CampaignRearrange.OrderGames(games, directorMode)
    local byId = {}
    for _, game in ipairs(games) do
        byId[game.gameid] = game
    end
    local result = {}
    for _, id in ipairs(MergeOrder(ReadSavedIds(directorMode), games)) do
        result[#result + 1] = byId[id]
    end
    return result
end

--- Total time played as HH:MM.
--- @param seconds number|nil
--- @return string
function CampaignRearrange.FormatTimePlayed(seconds)
    local minutes = math.floor((seconds or 0) / 60)
    local hours = math.floor(minutes / 60)
    return string.format("%02d:%02d", hours, minutes - hours * 60)
end

--- @class CampaignRearrangeShowArgs
--- @field parent Panel the full-screen surface the screen is added to
--- @field directorMode boolean which view's campaigns to arrange
--- @field saved fun() called after a Save writes the new order

--- Open the full-screen Rearrange Campaigns screen for one view.
--- @param args CampaignRearrangeShowArgs
function CampaignRearrange.Show(args)
    local directorMode = args.directorMode

    ---@type LuaGameInfo[]
    local m_gameList = {}
    ---@type table<string, LuaGameInfo>
    local m_gamesById = {}
    ---@type table<string, number>
    local m_engineIndex = {}

    local m_baseline = {}
    local m_draft = {}
    local m_undo = {}
    local m_moved = nil
    local m_dragging = false
    local m_nameAscending = true
    local m_timeDescending = true

    local m_rows = {}

    local screen
    local header
    local board
    local footer
    local confirm
    local saveButton
    local undoButton
    local nameSortIcon
    local timeSortIcon
    local nameSortButton
    local timeSortButton

    local function ReadGames()
        m_gameList = CampaignRearrange.ViewGames(directorMode)
        m_gamesById = {}
        m_engineIndex = {}
        for i, game in ipairs(m_gameList) do
            m_gamesById[game.gameid] = game
            m_engineIndex[game.gameid] = i
        end
    end

    local function IsDirty()
        return not SameOrder(m_draft, m_baseline)
    end

    local function RefreshSortButtons()
        if m_nameAscending then
            nameSortIcon.bgimage = ARROW_UP_ICON
        else
            nameSortIcon.bgimage = ARROW_DOWN_ICON
        end
        if m_timeDescending then
            timeSortIcon.bgimage = ARROW_DOWN_ICON
        else
            timeSortIcon.bgimage = ARROW_UP_ICON
        end
    end

    --- A hover handler showing text() as the tooltip; nil text shows none. Assigning .tooltip pops it up at once, so only do it on hover.
    --- @param text fun(): string|nil
    --- @return fun(element: Panel)
    local function HoverTooltip(text)
        return function(element)
            local value = text()
            if value ~= nil then
                gui.Tooltip(value)(element)
            end
        end
    end

    local CreateRow

    local function Changed()
        local numRows = math.ceil(#m_draft / PER_PAGE)
        while #m_rows < numRows do
            local row = CreateRow(#m_rows + 1)
            m_rows[#m_rows + 1] = row
            board:AddChild(row)
        end
        screen:FireEventTree("bindRearrange")

        saveButton:SetClass("disabled", not IsDirty())
        undoButton:SetClass("disabled", #m_undo == 0)
        RefreshSortButtons()
    end

    local function PushUndo()
        m_undo[#m_undo + 1] = CopyIds(m_draft)
    end

    --- @param from number
    --- @param to number
    --- @return boolean
    local function Move(from, to)
        if to == from or to < 1 or to > #m_draft or m_draft[from] == nil then
            return false
        end
        PushUndo()
        local id = table.remove(m_draft, from)
        table.insert(m_draft, to, id)
        return true
    end

    --- Keep the row holding a position inside the board's viewport.
    --- @param position number
    local function ScrollIntoView(position)
        local rowIndex = math.ceil(position / PER_PAGE)
        local viewport = board.renderedHeight
        local content = 0
        local rowTop = 0
        local rowBottom = 0
        for r, row in ipairs(m_rows) do
            if not row:HasClass("collapsed") then
                local height = row.renderedHeight + ROW_MARGIN
                if r == rowIndex then
                    rowTop = content
                    rowBottom = content + height
                end
                content = content + height
            end
        end
        local range = content - viewport
        if range <= 0 then
            return
        end
        local offset = (1 - board.vscrollPosition) * range
        if rowTop < offset then
            offset = rowTop
        elseif rowBottom > offset + viewport then
            offset = rowBottom - viewport
        else
            return
        end
        board.vscrollPosition = 1 - math.max(0, math.min(range, offset)) / range
    end

    --- @param from number
    --- @param to number
    local function ArrowMove(from, to)
        if Move(from, to) then
            m_moved = m_draft[to]
            Changed()
            ScrollIntoView(to)
        end
    end

    --- @param compare fun(a: string, b: string): boolean
    local function SortDraft(compare)
        PushUndo()
        m_moved = nil
        table.sort(m_draft, compare)
        Changed()
    end

    local function SortByName()
        local ascending = m_nameAscending
        SortDraft(function(a, b)
            local keyA = NameKey(m_gamesById[a])
            local keyB = NameKey(m_gamesById[b])
            if keyA ~= keyB then
                if ascending then
                    return keyA < keyB
                end
                return keyA > keyB
            end
            return m_engineIndex[a] < m_engineIndex[b]
        end)
        m_nameAscending = not m_nameAscending
        m_timeDescending = true
        RefreshSortButtons()
    end

    local function SortByTimePlayed()
        local descending = m_timeDescending
        SortDraft(function(a, b)
            local timeA = m_gamesById[a].timePlayed or 0
            local timeB = m_gamesById[b].timePlayed or 0
            if timeA ~= timeB then
                if descending then
                    return timeA > timeB
                end
                return timeA < timeB
            end
            local keyA = NameKey(m_gamesById[a])
            local keyB = NameKey(m_gamesById[b])
            if keyA ~= keyB then
                return keyA < keyB
            end
            return m_engineIndex[a] < m_engineIndex[b]
        end)
        m_timeDescending = not m_timeDescending
        m_nameAscending = true
        RefreshSortButtons()
    end

    local function Undo()
        if #m_undo == 0 then
            return
        end
        m_draft = table.remove(m_undo)
        m_moved = nil
        Changed()
    end

    local function Close()
        if screen ~= nil and screen.valid then
            screen:DestroySelf()
        end
    end

    local function Save()
        if not IsDirty() then
            return
        end
        OrderSetting(directorMode):Set(table.concat(m_draft, ","))
        Close()
        args.saved()
    end

    local function RequestClose()
        if IsDirty() then
            confirm:SetClass("collapsed", false)
        else
            Close()
        end
    end

    --- One campaign card, bound to whatever campaign sits at its position in the draft.
    --- @param position number
    --- @return Panel
    local function CreateCard(position)
        local art
        local nameLabel
        local timeLabel

        local function ArrowButton(icon, tooltip, isBlocked, target)
            return gui.Button{
                icon = icon,
                classes = {"sizeL"},
                tooltip = tooltip,
                hmargin = 2,
                bindRearrange = function(element)
                    element:SetClass("disabled", m_draft[position] ~= nil and isBlocked())
                end,
                press = function(element)
                    if m_draft[position] ~= nil and not isBlocked() then
                        ArrowMove(position, target())
                    end
                end,
            }
        end

        art = gui.Panel{
            classes = {"image"},
            bgimage = FALLBACK_ART,
            width = "100%",
            height = ART_HEIGHT,
        }

        nameLabel = gui.Label{
            classes = {"sizeM", "bold"},
            width = "100%-12",
            height = "auto",
            halign = "center",
            tmargin = 4,
            textWrap = false,
            textOverflow = "ellipsis",
            text = "",
            hover = function(element)
                gui.Tooltip(element.text)(element)
            end,
        }

        timeLabel = gui.Label{
            classes = {"fgMuted", "number"},
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 6,
            text = "",
        }

        return gui.Panel{
            classes = {"rearrangeCard", "bordered"},
            width = CARD_WIDTH,
            height = "auto",
            valign = "top",
            flow = "vertical",
            draggable = true,

            bindRearrange = function(element)
                local id = m_draft[position]
                local game = id and m_gamesById[id]
                element:SetClass("collapsed", game == nil)
                if game == nil then
                    return
                end
                local name = tostring(game.description or "")
                art.bgimage = game.coverart or FALLBACK_ART
                nameLabel.text = name
                timeLabel.text = CampaignRearrange.FormatTimePlayed(game.timePlayed)
                element:SetClass("moved", id == m_moved)
            end,

            canDragOnto = function(element, target)
                if target == nil or not target:HasClass("rearrangeGap") then
                    return false
                end
                local insertAt = target.data.insertAt
                return insertAt ~= position and insertAt ~= position + 1
            end,

            beginDrag = function(element)
                element.selfStyle.scale = 0.5
            end,

            dragging = function(element, target)
                m_dragging = true
            end,

            drag = function(element, target)
                m_dragging = false
                element.selfStyle.scale = 1
                if target == nil or not target:HasClass("rearrangeGap") then
                    return
                end
                local insertAt = target.data.insertAt
                if insertAt == position or insertAt == position + 1 then
                    return
                end
                local to = insertAt
                if position < insertAt then
                    to = insertAt - 1
                end
                if Move(position, to) then
                    m_moved = nil
                    Changed()
                end
            end,

            art,

            gui.Panel{
                classes = {"bgAlt"},
                width = "100%",
                height = "auto",
                flow = "vertical",

                nameLabel,

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 4,

                    timeLabel,

                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        valign = "center",
                        flow = "horizontal",
                        rmargin = 4,

                        ArrowButton("phosphor/arrow-fat-left-light.png", "Move left",
                            function() return position <= 1 end,
                            function() return position - 1 end),
                        ArrowButton("phosphor/arrow-fat-up-light.png", "Move up a page",
                            function() return position <= PER_PAGE end,
                            function() return position - PER_PAGE end),
                        ArrowButton("phosphor/arrow-fat-down-light.png", "Move down a page",
                            function() return math.ceil(position / PER_PAGE) >= math.ceil(#m_draft / PER_PAGE) end,
                            function() return math.min(position + PER_PAGE, #m_draft) end),
                        ArrowButton("phosphor/arrow-fat-right-light.png", "Move right",
                            function() return position >= #m_draft end,
                            function() return position + 1 end),
                    },
                },
            },
        }
    end

    --- A drop gap; dropping there puts the card at position insertAt.
    --- @param rowIndex number
    --- @param gapIndex number 0..PER_PAGE, left to right
    --- @return Panel
    local function CreateGap(rowIndex, gapIndex)
        local insertAt = (rowIndex - 1) * PER_PAGE + gapIndex + 1
        return gui.Panel{
            classes = {"rearrangeGap"},
            bgimage = true,
            dragTarget = true,
            width = GAP_WIDTH,
            height = ART_HEIGHT,
            valign = "top",
            data = {
                insertAt = insertAt,
            },
            bindRearrange = function(element)
                local numRows = math.ceil(#m_draft / PER_PAGE)
                local cardsInRow = math.min(PER_PAGE, #m_draft - (rowIndex - 1) * PER_PAGE)
                local visible = rowIndex <= numRows and gapIndex <= cardsInRow and (gapIndex < PER_PAGE or rowIndex == numRows)
                element:SetClass("collapsed", not visible)
            end,
        }
    end

    --- One page of the board: a "Page N" label over gap, card, gap, card, ...
    --- @param rowIndex number
    --- @return Panel
    CreateRow = function(rowIndex)
        local cells = {
            width = "auto",
            height = "auto",
            halign = "left",
            flow = "horizontal",
        }
        cells[#cells + 1] = CreateGap(rowIndex, 0)
        for slot = 1, PER_PAGE do
            cells[#cells + 1] = CreateCard((rowIndex - 1) * PER_PAGE + slot)
            cells[#cells + 1] = CreateGap(rowIndex, slot)
        end

        return gui.Panel{
            width = ROW_WIDTH,
            height = "auto",
            halign = "center",
            bmargin = ROW_MARGIN,
            flow = "vertical",

            bindRearrange = function(element)
                element:SetClass("collapsed", rowIndex > math.ceil(#m_draft / PER_PAGE))
            end,

            gui.Label{
                classes = {"sizeL", "bold"},
                text = string.format("Page %d", rowIndex),
                width = "auto",
                height = "auto",
                halign = "left",
                lmargin = GAP_WIDTH,
                bmargin = 4,
            },

            gui.Panel(cells),
        }
    end

    nameSortIcon = gui.Panel{
        classes = {"rearrangeSortIcon"},
        bgimage = ARROW_UP_ICON,
        floating = true,
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
        x = 12,
    }

    timeSortIcon = gui.Panel{
        classes = {"rearrangeSortIcon"},
        bgimage = ARROW_DOWN_ICON,
        floating = true,
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
        x = 12,
    }

    nameSortButton = gui.Button{
        classes = {"sizeL"},
        text = "Name",
        textAlignment = "center",
        lpad = 36,
        hmargin = 8,
        hover = HoverTooltip(function()
            if m_nameAscending then
                return "Sort by name, A to Z"
            end
            return "Sort by name, Z to A"
        end),
        press = function(element)
            SortByName()
        end,
        nameSortIcon,
    }

    timeSortButton = gui.Button{
        classes = {"sizeL"},
        text = "Time Played",
        textAlignment = "center",
        lpad = 36,
        hmargin = 8,
        hover = HoverTooltip(function()
            if m_timeDescending then
                return "Sort by time played, most first"
            end
            return "Sort by time played, least first"
        end),
        press = function(element)
            SortByTimePlayed()
        end,
        timeSortIcon,
    }

    undoButton = gui.Button{
        classes = {"sizeL"},
        text = "Undo",
        halign = "left",
        hover = HoverTooltip(function()
            if #m_undo == 0 then
                return "Nothing to undo"
            end
            return nil
        end),
        press = function(element)
            Undo()
        end,
    }

    saveButton = gui.Button{
        classes = {"sizeL"},
        text = "Save",
        halign = "right",
        lmargin = 12,
        hover = HoverTooltip(function()
            if not IsDirty() then
                return "No changes"
            end
            return nil
        end),
        press = function(element)
            Save()
        end,
    }

    board = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        vscroll = true,
    }

    confirm = gui.Panel{
        classes = {"transparent", "collapsed"},
        bgimage = true,
        floating = true,
        width = "100%",
        height = "100%",

        gui.Panel{
            classes = {"modalDialog"},
            width = 600,
            height = "auto",
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label{
                classes = {"modalTitle"},
                text = "Discard changes?",
                width = "100%",
                height = "auto",
                tmargin = 20,
            },

            gui.Label{
                classes = {"modalMessage"},
                text = "Your new campaign order has not been saved.",
                width = "100%",
                height = "auto",
                vmargin = 16,
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                flow = "horizontal",
                bmargin = 20,

                gui.Button{
                    classes = {"sizeL"},
                    text = "Keep Editing",
                    hmargin = 8,
                    press = function(element)
                        confirm:SetClass("collapsed", true)
                    end,
                },

                gui.Button{
                    classes = {"sizeL"},
                    text = "Discard",
                    hmargin = 8,
                    press = function(element)
                        Close()
                    end,
                },
            },
        },
    }

    local title = "Rearrange Campaigns - Player"
    if directorMode then
        title = "Rearrange Campaigns - Director"
    end

    header = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = HEADER_MARGIN,

        gui.Label{
            classes = {"dialogTitle"},
            text = title,
            width = "100%",
            height = "auto",
        },

        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            tmargin = 12,

            nameSortButton,
            timeSortButton,
        },
    }

    footer = gui.Panel{
        width = ROW_WIDTH,
        height = "auto",
        halign = "center",
        flow = "horizontal",
        vmargin = FOOTER_MARGIN,

        undoButton,

        gui.Button{
            classes = {"sizeL"},
            text = "Cancel",
            halign = "right",
            press = function(element)
                RequestClose()
            end,
        },

        saveButton,
    }

    --- The part of the parent's height the title bar leaves visible.
    --- @return number
    local function VisibleHeight()
        return args.parent.renderedHeight * dmhub.screenHeightBelowTitlebar / dmhub.screenHeight
    end

    screen = gui.Panel{
        classes = {"framedPanel", "toplevel", "noBorder"},
        styles = ThemeEngine.MergeStyles(g_extras),
        floating = true,
        width = "100%",
        height = VisibleHeight(),
        valign = "top",
        flow = "vertical",
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,

        screenResized = function(element)
            element.selfStyle.height = VisibleHeight()
        end,

        create = function(element)
            ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(g_extras)
                end
            end)
        end,

        escape = function(element)
            if m_dragging then
                m_dragging = false
                return
            end
            if not confirm:HasClass("collapsed") then
                confirm:SetClass("collapsed", true)
                return
            end
            RequestClose()
        end,

        --the lobby changed under us (a campaign joined, deleted or left elsewhere).
        refreshLobby = function(element)
            ReadGames()
            m_baseline = MergeOrder(m_baseline, m_gameList)
            m_draft = MergeOrder(m_draft, m_gameList)
            for i, snapshot in ipairs(m_undo) do
                m_undo[i] = MergeOrder(snapshot, m_gameList)
            end
            Changed()
        end,

        header,
        board,
        footer,
        confirm,
    }

    ReadGames()
    m_baseline = MergeOrder(ReadSavedIds(directorMode), m_gameList)
    m_draft = CopyIds(m_baseline)

    args.parent:AddChild(screen)
    Changed()
end
