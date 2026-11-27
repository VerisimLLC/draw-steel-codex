local mod = dmhub.GetModLoading()

--[[
    BESidePanel: the right column. The checks (the host's checks(model): a
    coloured dot and a sentence each) over the book-style card (the host's
    card(model)), both redrawn after every change.

    The card keeps the printed book's layout on fixed paper and ink, as the
    block colours are fixed: the ruled header with diamond marks, keywords and
    action on one line, distance and target with icons, the tier marks
    (DrawSteelGlyphs "!", "@", "#") and the characteristic as a dark chip.
]]

local T = UIText.T

--- @class BESidePanel
BESidePanel = {}

local CARD = {
    FONT = "Book",
    GLYPH_FONT = "DrawSteelGlyphs",
    TIER_GLYPHS = { "!", "@", "#" },
    TEXT_SIZE = 14,
    TITLE_SIZE = 19,
    MARK = 10,
    TIER_MARK_WIDTH = 46,
}

--- One line of card text in the book font. A card line lights under the
--- pointer, where rewording will open in phase 2.
--- @param args table gui.Label fields
--- @return Panel
local function _cardText(args)
    args.classes = args.classes or {"beCardText"}
    --inline: MergeStyles swaps a font name it does not know for the default.
    args.fontFace = CARD.FONT
    args.fontSize = args.fontSize or CARD.TEXT_SIZE
    args.width = args.width or "100%"
    return gui.Label(args)
end

--- A card line: a row that lights under the pointer.
--- @param children Panel[]
--- @param args? table extra gui.Panel fields
--- @return Panel
local function _line(children, args)
    local options = {
        classes = {"beCardLine"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        children = children,
    }
    for k, v in pairs(args or {}) do
        options[k] = v
    end
    return gui.Panel(options)
end

--- One side of a two-column card row, with its icon if it has one.
--- @param text string
--- @param icon? string a Phosphor name
--- @param bold? boolean
--- @param right boolean
--- @return Panel
local function _rowCell(text, icon, bold, right)
    local children = {}
    if icon ~= nil then
        children[#children + 1] = gui.Panel{
            classes = {"beCardIcon"},
            bgimage = "phosphor/" .. icon .. ".png",
            interactable = false,
        }
    end
    children[#children + 1] = _cardText{
        width = "auto",
        maxWidth = icon ~= nil and 120 or 150,
        textWrap = true,
        bold = bold or nil,
        text = text,
        interactable = false,
    }
    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = right and "right" or "left",
        valign = "top",
        children = children,
    }
end

--- A tier's text: words and characteristic chips in a wrapping row.
--- @param parts (string|{chip: string})[]
--- @return Panel
local function _tierText(parts)
    local children = {}
    for _, part in ipairs(parts) do
        if type(part) == "table" then
            children[#children + 1] = gui.Panel{
                classes = {"beCardChip"},
                halign = "left",
                lmargin = 4,
                gui.Label{
                    classes = {"beCardText"},
                    fontFace = CARD.FONT,
                    fontSize = 11,
                    bold = true,
                    color = BEStyles.Fixed(BEStyles.FIXED.PAPER),
                    width = "auto",
                    text = part.chip,
                    interactable = false,
                },
            }
        else
            for spaces, word in string.gmatch(part, "(%s*)(%S+)") do
                children[#children + 1] = _cardText{
                    width = "auto",
                    halign = "left",
                    lmargin = (spaces ~= "" and #children > 0) and 4 or 0,
                    text = word,
                    interactable = false,
                }
            end
        end
    end
    return gui.Panel{
        width = "100%-" .. (CARD.TIER_MARK_WIDTH + 4),
        height = "auto",
        flow = "horizontal",
        wrap = true,
        valign = "center",
        children = children,
    }
end

--- The card for a host's description of the record.
--- @param card BlockCard
--- @return Panel
function BESidePanel.Card(card)
    local ink = BEStyles.Fixed(BEStyles.FIXED.INK)

    local marks = {}
    for i, icon in ipairs({ "diamond-fill", "diamond", "diamond-fill" }) do
        marks[i] = gui.Panel{
            classes = {"beCardMark"},
            bgimage = "phosphor/" .. icon .. ".png",
            width = CARD.MARK,
            height = CARD.MARK,
            tmargin = i == 1 and 6 or 1,
            interactable = false,
        }
    end

    local headerLines = {
        _line({ _cardText{ fontSize = CARD.TITLE_SIZE, bold = true, text = card.title } }),
    }
    if card.flavor ~= nil and card.flavor ~= "" then
        headerLines[#headerLines + 1] = _line({ _cardText{ text = "<i>" .. card.flavor .. "</i>" } }, {
            border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
            borderColor = ink,
            bpad = 3,
            bmargin = 2,
        })
    end
    for _, row in ipairs(card.rows or {}) do
        headerLines[#headerLines + 1] = _line({
            _rowCell(row.left, row.leftIcon, row.bold, false),
            _rowCell(row.right, row.rightIcon, row.bold, true),
        }, { tmargin = 2 })
    end

    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            bmargin = 10,
            gui.Panel{
                width = 14,
                height = "auto",
                flow = "vertical",
                valign = "top",
                children = marks,
            },
            gui.Panel{
                width = "100%-20",
                height = "auto",
                flow = "vertical",
                halign = "right",
                valign = "top",
                lpad = 6,
                borderBox = true,
                bgimage = true,
                bgcolor = "clear",
                border = {x1 = 1, x2 = 0, y1 = 0, y2 = 0},
                borderColor = ink,
                children = headerLines,
            },
        },
    }
    if card.roll ~= nil then
        children[#children + 1] = _line({ _cardText{ bold = true, text = card.roll } }, { bmargin = 3 })
        for i, tier in ipairs(card.tiers or {}) do
            children[#children + 1] = _line({
                gui.Label{
                    classes = {"beCardText"},
                    fontFace = CARD.GLYPH_FONT,
                    fontSize = 26,
                    width = CARD.TIER_MARK_WIDTH,
                    height = "auto",
                    valign = "center",
                    text = CARD.TIER_GLYPHS[i] or "",
                    interactable = false,
                },
                _tierText(tier.parts or {}),
            }, { tmargin = 3 })
        end
    end
    if card.effect ~= nil then
        children[#children + 1] = _line({
            _cardText{ text = string.format("<b>%s</b> %s", card.effect.label, card.effect.text) },
        }, { tmargin = 8 })
    end

    return gui.Panel{
        classes = {"beCard"},
        lpad = 14,
        rpad = 16,
        valign = "top",
        children = children,
    }
end

--- One check: a coloured dot and a sentence.
--- @param check BlockCheck
--- @return Panel
local function _issue(check)
    return gui.Panel{
        classes = {"beIssue"},
        gui.Panel{ classes = {"beIssueDot", check.severity}, interactable = false },
        gui.Label{ classes = {"beIssueText"}, text = check.text, interactable = false },
    }
end

--- Builds the side column for a host.
--- @param host BlockHost
--- @return Panel
function BESidePanel.Create(host)
    return gui.Panel{
        classes = {"beSideColumn"},
        vscroll = true,
        [BlockEditor.REFRESH_EVENT] = function(element, state)
            --- @cast state BEState
            local model = state:Model()
            if model == nil then
                return
            end
            local record = state.sources[model.id]
            local children = {}
            if host.checks ~= nil then
                local ok, checks = pcall(host.checks, model, record)
                checks = ok and checks or {}
                local unsaveable = BERecordCache.CountUnsaveable(model.blocks)
                if unsaveable > 0 then
                    table.insert(checks, 1, { severity = "danger", text = T("blockeditor.check.unsaveable", { count = unsaveable }) })
                end
                local header, rule = BEStyles.SectionHeader{
                    title = T("blockeditor.side.checks"),
                    count = tostring(#checks),
                }
                header.selfStyle.tmargin = 0
                children[#children + 1] = header
                children[#children + 1] = rule
                for _, check in ipairs(checks) do
                    children[#children + 1] = _issue(check)
                end
            end
            if host.card ~= nil then
                local ok, card = pcall(host.card, model, record)
                if ok and type(card) == "table" then
                    children[#children + 1] = gui.Panel{
                        width = "100%",
                        height = "auto",
                        valign = "top",
                        tmargin = 12,
                        BESidePanel.Card(card),
                    }
                    children[#children + 1] = gui.Label{
                        classes = {"beCardHint"},
                        text = T("blockeditor.card_hint"),
                        interactable = false,
                    }
                elseif not ok then
                    dmhub.Error("BlockEditor: the host's card failed: " .. tostring(card))
                end
            end
            element.children = children
        end,
    }
end
