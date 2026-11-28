local mod = dmhub.GetModLoading()

--[[
    Styles for the Block Editor: sizes, the chrome's rules (from theme tokens)
    and the blocks' rules (fixed colours from the Block groups; plan section 13).

    Two kinds of colour live here, on purpose:
      * Chrome (window, columns, tabs, slots) uses @tokens and theme classes,
        so a colour scheme recolours it.
      * Blocks, the book card's paper and ink, and text on blocks are FIXED:
        a block's colour says what kind of block it is, so no scheme changes
        it (ledger 2026-11-25).
]]

--- @class BEStyles
BEStyles = {}

--Prefix for the fixed block colours. Plain hexes already match the web
--prototype in the app; "srgb:" converted them a second time and washed them out.
BEStyles.COLOR_PREFIX = ""

BEStyles.SIZES = {
    -- The editor window
    WINDOW_WIDTH = 1320,
    WINDOW_HEIGHT = 860,
    WINDOW_MAX_WIDTH = "96%",
    WINDOW_MAX_HEIGHT = "94%",
    WINDOW_PAD = 10,

    -- Columns: the detail column takes what the other two leave
    SHELF_WIDTH = 250,
    SIDE_WIDTH = 330,
    COLUMN_GAP = 8,
    COLUMN_PAD = 8,

    -- Blocks. "sp" scales with the Font Size setting; "em" also with the font.
    BLOCK_FONT_SIZE = 15,
    BLOCK_HPAD = 8,
    BLOCK_VPAD = 6,
    BLOCK_RADIUS = 5,
    BLOCK_GAP = 4,
    GLYPH = "14sp",
    GLYPH_GAP = 8,
    --Room the block text leaves for the glyph (14sp at 140% plus the gap).
    --A fixed offset, because "available" text gets no width while an
    --auto-height block measures itself and wraps one letter per line.
    BLOCK_TEXT_INSET = 30,

    -- Drop slots between blocks: hidden, hinted during a drag, open under the pointer
    SLOT_REST = 2,
    SLOT_HINT = 12,
    SLOT_OPEN = "2.3em",
    SLOT_MARGIN = 3,

    -- The ring round a selected block
    SELECTED_RING = 2,

    -- The editor window, laid out as docs/block-editor/lua-preview/ability.html
    EDITOR_WIDTH = 1480,
    EDITOR_HEIGHT = 900,
    EDITOR_SHELF_WIDTH = 250,
    EDITOR_SIDE_WIDTH = 330,
    WORD_FONT = 16,          -- a block's sentence
    WORD_GAP = 4,            -- the space between two words
    GRIP = 16,
    GEAR = 16,
    --Room a sentence leaves for the grip, glyph and gear beside it. A fixed
    --offset, for the same reason as BLOCK_TEXT_INSET.
    SENTENCE_INSET = 74,
    TAG_INSET = 46,          -- and for a "Text" tag
    TIER_LABEL = 88,
    SHELF_ROW = 32,
    SLIVER_REST = 2,
    SLIVER_HINT = 12,
    SLIVER_OPEN = 34,
}

--Colours that never follow the theme (without COLOR_PREFIX; see BEStyles.Fixed).
BEStyles.FIXED = {
    BLOCK_TEXT = "#ffffff",
    BLOCK_EDGE = "#00000059",
    NO_FIT_EDGE = "#ffffffcc",
    -- The book-style ability card
    PAPER = "#fdfcf8",
    INK = "#141414",
    -- The fill behind a changeable word, for <mark=...> in a sentence label.
    -- <mark> draws OVER the text, so these stay translucent.
    WORD_REST = "#00000055",
    WORD_HOVER = "#ffffff70",
    CHIP = "#14141438",
    -- A clickable word in the editor: a dark inset of the block's own colour,
    -- white with dark text under the pointer or while its menu is open.
    WORD_FILL = "#0000004d",
    WORD_FILL_HOT = "#ffffff",
    WORD_TEXT_HOT = "#111111",
    ASIDE_TEXT = "#ffffffc7",
    CHIP_EDGE = "#ffffff59",
    TAG_EDGE = "#ffffff8c",
    GRIP_REST = "#ffffff8c",
    ROW_RULE = "#00000047",
    CARD_HOVER = "#8c6a2426",
    SLIVER_HINT_FILL = "#ffffff12",
    SLIVER_OPEN_FILL = "#ffffff26",
}

--How much brighter a block is under the pointer (0-1, towards white).
local HOVER_LIGHTEN = 0.08

--- A fixed colour as the engine should read it.
--- @param hex string "#rrggbb" or "#rrggbbaa"
--- @return string
function BEStyles.Fixed(hex)
    return BEStyles.COLOR_PREFIX .. hex
end

--- A hex colour moved towards white, for a block's hover state. An inline
--- bgcolor would beat a hover rule, so hover colours are worked out up front.
--- @param hex string "#rrggbb"
--- @param amount number 0 (unchanged) to 1 (white)
--- @return string "#rrggbb"
function BEStyles._lighten(hex, amount)
    local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)")
    if r == nil then
        return hex
    end
    local function Channel(text)
        local value = tonumber(text, 16) or 0
        return math.floor(value + (255 - value) * amount + 0.5)
    end
    return string.format("#%02x%02x%02x", Channel(r), Channel(g), Channel(b))
end

--- The class that gives a panel a group's colour (with "beBlock").
--- @param groupId string
--- @return string
function BEStyles.GroupClass(groupId)
    return "beGroup-" .. groupId
end

--- @class BEBlockColor
--- @field color string the group's colour, "#rrggbb"
--- @field hover string its colour under the pointer
--- @field glyph nil|string the Phosphor icon name, if the group has one

--- The colour table both editors read: one entry per Block group, by group
--- id. Built from Block.All("group") each call, so groups from later mods count.
--- @return table<string, BEBlockColor>
function BEStyles.BlockColors()
    local result = {}
    for _, group in ipairs(Block.All("group")) do
        --- @cast group BlockGroup
        result[group.id] = {
            color = group.color,
            hover = BEStyles._lighten(group.color, HOVER_LIGHTEN),
            glyph = group.glyph,
        }
    end
    return result
end

--- The chrome: everything that follows the colour scheme.
--- @return table[]
local function _chromeStyles()
    local SIZES = BEStyles.SIZES
    return {
        {
            selectors = {"beTitleBar"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = SIZES.COLUMN_GAP,
        },
        {
            selectors = {"beSectionStrip"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            bmargin = SIZES.COLUMN_GAP,
        },
        {
            selectors = {"beColumn"},
            height = "100%",
            flow = "vertical",
            bgimage = true,
            bgcolor = "@bgAlt",
            border = 1,
            borderColor = "@border",
            cornerRadius = 6,
            pad = SIZES.COLUMN_PAD,
            borderBox = true,
        },
        {
            selectors = {"beScroll"},
            width = "100%",
            height = "100% available",
            flow = "vertical",
        },
        {
            selectors = {"label", "beHeading"},
            width = "100%",
            height = "auto",
            valign = "top",
            fontSize = 16,
            bold = true,
            color = "@fgStrong",
            bmargin = 4,
        },
        {
            selectors = {"label", "beNote"},
            width = "100%",
            height = "auto",
            valign = "top",
            fontSize = 13,
            color = "@fgMuted",
            textWrap = true,
            bmargin = 6,
        },
        {
            selectors = {"label", "beGroupHeading"},
            width = "100%",
            height = "auto",
            valign = "top",
            fontSize = 12,
            color = "@fgMuted",
            tmargin = 8,
            bmargin = 2,
        },

        -- Drop slots. Rest: a 2px sliver (a zero-height panel cannot be found).
        {
            selectors = {"beSlot"},
            width = "100%",
            height = SIZES.SLOT_REST,
            vmargin = SIZES.SLOT_MARGIN,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 4,
            flow = "none",
        },
        -- While something is dragged every slot shows as a dashed hint.
        {
            selectors = {"beSlot", "beSlotHint"},
            height = SIZES.SLOT_HINT,
            border = 1,
            borderStyle = "dashed",
            borderColor = "@fgMuted",
        },
        -- The slot the block would land in opens to the size of a block.
        {
            selectors = {"beSlot", "beSlotOpen"},
            fontSize = SIZES.BLOCK_FONT_SIZE,
            height = SIZES.SLOT_OPEN,
            border = 2,
            borderStyle = "solid",
            borderColor = "@accentHover",
            bgcolor = "@bg",
            priority = 10,
        },
        {
            selectors = {"label", "beSlotLabel"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            fontSize = 13,
            bold = true,
            color = "@fgStrong",
            collapsed = 1,
        },
        {
            selectors = {"label", "beSlotLabel", "parent:beSlotOpen"},
            collapsed = 0,
        },

        -- A list that takes drops. The engine adds drag-target classes to it
        -- (DefaultStyles paints those accent at priority 5); these keep its
        -- own look and only edge it while the dragged block is over it.
        {
            selectors = {"beDropArea"},
            bgimage = true,
            bgcolor = "@bg",
            border = 1,
            borderColor = "@border",
            cornerRadius = 6,
        },
        {
            selectors = {"beDropArea", "drag-target"},
            bgcolor = "@bg",
            borderColor = "@border",
            priority = 10,
        },
        {
            selectors = {"beDropArea", "drag-target-hover"},
            bgcolor = "@bg",
            borderWidth = 1,
            borderColor = "@accent",
            priority = 10,
        },
    }
end

--- The editor's chrome, following the mockup: window, title bar, section
--- strip, columns, section headers, add rows, slivers, shelf and checks.
--- @return table[]
local function _editorChromeStyles()
    local SIZES = BEStyles.SIZES
    local FIXED = BEStyles.FIXED
    local Fixed = BEStyles.Fixed
    return {
        {
            selectors = {"beWindow"},
            bgimage = true,
            bgcolor = "@bg",
            border = 1,
            borderColor = "@borderSolid",
            cornerRadius = 10,
            flow = "vertical",
        },
        --inside another editor (the ability editor's Simple tab): no frame of its own.
        {
            selectors = {"beEmbedded"},
            bgcolor = "clear",
            flow = "vertical",
        },
        --the line under the title bar about other people's changes.
        {
            selectors = {"beNotice"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = true,
            bgcolor = "@bg",
            border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
            borderColor = "@warning",
            hpad = 14,
            vpad = 6,
            borderBox = true,
        },
        {
            selectors = {"label", "beNoticeText"},
            width = "auto",
            height = "auto",
            maxWidth = 900,
            valign = "center",
            halign = "left",
            fontSize = 15,
            color = "@warning",
            textWrap = true,
            rmargin = 16,
        },
        {
            selectors = {"beNoticeChoice"},
            valign = "center",
            halign = "left",
            rmargin = 8,
        },
        {
            selectors = {"beEditorTitleBar"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = true,
            gradient = "@barTrack",
            border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
            borderColor = "@borderSolid",
            lpad = 14,
            rpad = 14,
            tpad = 10,
            borderBox = true,
        },
        --a later rule, so its padding wins over the title bar's.
        {
            selectors = {"beEditorTitleBar", "beEmbeddedBar"},
            tpad = 4,
            bpad = 4,
        },
        {
            selectors = {"label", "beEditorTitle"},
            width = "auto",
            height = "auto",
            valign = "bottom",
            fontSize = 22,
            bold = true,
            color = "@fgStrong",
            bmargin = 10,
            rmargin = 18,
        },
        {
            selectors = {"label", "beToolLabel"},
            width = "auto",
            height = "auto",
            valign = "center",
            fontFace = "@input",
            fontSize = 13,
            color = "@fgMuted",
            rmargin = 8,
        },

        -- The section strip: a row of section names under the title bar.
        {
            selectors = {"beStrip"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = true,
            bgcolor = "clear",
            border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
            borderColor = "@borderSolid",
        },
        {
            selectors = {"beNavRow"},
            halign = "left",
            width = "auto",
            height = 34,
            flow = "horizontal",
            hpad = 12,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            border = {x1 = 0, x2 = 0, y1 = 3, y2 = 0},
            borderColor = "clear",
        },
        {
            selectors = {"beNavRow", "hover"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"beNavRow", "selected"},
            bgcolor = "@bgAlt",
            borderColor = "@accent",
        },
        {
            selectors = {"label", "beNavText"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 16,
            color = "@fg",
        },
        {
            selectors = {"label", "beNavText", "parent:selected"},
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = {"label", "beCount"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontFace = "@input",
            fontSize = 11,
            color = "@fgMuted",
            lmargin = 8,
        },

        -- The three columns.
        {
            selectors = {"beColumns"},
            width = "100%",
            height = "100% available",
            flow = "horizontal",
        },
        {
            selectors = {"beDetail"},
            height = "100%",
            flow = "vertical",
            bgimage = true,
            gradient = "@surfaceRadial",
            lpad = 18,
            rpad = 18,
            tpad = 6,
            bpad = 30,
            borderBox = true,
        },
        {
            selectors = {"beShelfColumn"},
            width = SIZES.EDITOR_SHELF_WIDTH,
            height = "100%",
            flow = "vertical",
            bgimage = true,
            bgcolor = "@bg",
            border = {x1 = 1, x2 = 0, y1 = 0, y2 = 0},
            borderColor = "@borderSolid",
        },
        {
            selectors = {"beSideColumn"},
            width = SIZES.EDITOR_SIDE_WIDTH,
            height = "100%",
            flow = "vertical",
            bgimage = true,
            bgcolor = "@bg",
            border = {x1 = 1, x2 = 0, y1 = 0, y2 = 0},
            borderColor = "@borderSolid",
            pad = 12,
            borderBox = true,
        },

        -- "This is [an ability | a triggered ability]"
        {
            selectors = {"beIsRow"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 12,
            bmargin = 2,
        },
        {
            selectors = {"label", "beIsLabel"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 15,
            color = "@fg",
            rmargin = 10,
        },

        -- Section headers: caret, small uppercase title, count, and a rule under.
        {
            selectors = {"beSecHead"},
            width = "100%",
            height = 30,
            flow = "horizontal",
            valign = "top",
            tmargin = 14,
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = {"beSecHeadShelf"},
            tmargin = 6,
        },
        {
            selectors = {"beCaret"},
            halign = "left",
            width = 12,
            height = 12,
            valign = "center",
            rmargin = 8,
            bgimage = "phosphor/caret-down-fill.png",
            bgcolor = "@fg",
        },
        {
            selectors = {"label", "beSecTitle"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontFace = "@input",
            fontSize = 13,
            bold = true,
            uppercase = true,
            color = "@fg",
        },
        {
            selectors = {"label", "beSecTitle", "parent:hover"},
            color = "@fgStrong",
        },
        {
            selectors = {"label", "beSecOptional"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontFace = "@input",
            fontSize = 11,
            color = "@fgMuted",
            lmargin = 6,
        },
        {
            selectors = {"label", "beSecCount"},
            lmargin = 6,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            fontFace = "@input",
            fontSize = 11,
            color = "@fgMuted",
        },
        {
            selectors = {"beSecRule"},
            width = "100%",
            height = 1,
            valign = "top",
            bmargin = 4,
            bgimage = true,
            bgcolor = "@border",
        },

        -- The italic line under a header group, and the add rows.
        {
            selectors = {"label", "beSummary"},
            width = "100%-20",
            height = "auto",
            valign = "top",
            halign = "left",
            lmargin = 10,
            tmargin = 4,
            fontSize = 13,
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = {"beAddReq"},
            width = "auto",
            height = 28,
            flow = "horizontal",
            halign = "left",
            valign = "top",
            hpad = 10,
            borderBox = true,
            tmargin = 4,
            bgimage = true,
            bgcolor = "clear",
            border = 1,
            borderStyle = "dashed",
            borderColor = "@borderSolid",
            cornerRadius = 5,
        },
        {
            selectors = {"beAddReq", "hover"},
            borderColor = "@fgMuted",
        },
        {
            selectors = {"beAddRow"},
            width = "100%",
            height = 30,
            flow = "horizontal",
            valign = "top",
            hpad = 8,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 5,
        },
        {
            selectors = {"beAddRow", "hover"},
            bgcolor = "@bgAlt",
        },
        -- The add row at the end of a list inside a block: shorter, and quiet until hovered.
        {
            selectors = {"beAddRow", "beAddRowInner"},
            height = 24,
            opacity = 0.7,
        },
        {
            selectors = {"beAddRow", "beAddRowInner", "hover"},
            opacity = 1,
        },
        {
            selectors = {"beAddIcon"},
            halign = "left",
            width = 12,
            height = 12,
            valign = "center",
            rmargin = 8,
            bgimage = "phosphor/plus-bold.png",
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"beAddIcon", "parent:hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"label", "beAddText"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 15,
            color = "@fgMuted",
        },
        {
            selectors = {"label", "beAddText", "beAddReqText"},
            fontSize = 14,
        },
        {
            selectors = {"label", "beAddText", "parent:hover"},
            color = "@fgStrong",
        },

        -- "Start from:" and its pills.
        {
            selectors = {"beStartRow"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            valign = "top",
            vmargin = 6,
        },
        {
            selectors = {"label", "beStartLabel"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 14,
            color = "@fgMuted",
            rmargin = 6,
        },
        {
            selectors = {"label", "bePill"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontFace = "@input",
            fontSize = 13,
            color = "@fg",
            hpad = 10,
            vpad = 3,
            rmargin = 6,
            bgimage = true,
            bgcolor = "@bg",
            border = 1,
            borderColor = "@borderSolid",
            cornerRadius = 12,
        },
        {
            selectors = {"label", "bePill", "hover"},
            bgcolor = "@bgAlt",
            color = "@fgStrong",
        },

        -- Drop slivers: 2px at rest; during a drag the ones the block fits are
        -- dashed slots, and the one under the pointer opens to "Drop here".
        {
            selectors = {"beSliver"},
            width = "100%",
            height = SIZES.SLIVER_REST,
            valign = "top",
            vmargin = 3,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 4,
            flow = "none",
        },
        {
            selectors = {"beSliver", "beSliverHint"},
            height = SIZES.SLIVER_HINT,
            vmargin = 4,
            bgcolor = Fixed(FIXED.SLIVER_HINT_FILL),
            border = 1,
            borderStyle = "dashed",
            borderColor = "@fgMuted",
        },
        {
            selectors = {"beSliver", "beSliverOpen"},
            height = SIZES.SLIVER_OPEN,
            bgcolor = Fixed(FIXED.SLIVER_OPEN_FILL),
            border = 2,
            borderStyle = "solid",
            borderColor = "@accentHover",
            priority = 10,
        },
        {
            selectors = {"label", "beSliverLabel"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            fontFace = "@input",
            fontSize = 13,
            bold = true,
            color = "@fgStrong",
            collapsed = 1,
        },
        {
            selectors = {"label", "beSliverLabel", "parent:beSliverOpen"},
            collapsed = 0,
        },

        -- The shelf: search, sections, rows.
        {
            selectors = {"beShelfSearch"},
            width = "100%-24",
            height = 30,
            halign = "center",
            valign = "top",
            vmargin = 12,
        },
        {
            selectors = {"beShelfList"},
            width = "100%",
            height = "100% available",
            flow = "vertical",
            valign = "top",
            bpad = 8,
            borderBox = true,
        },
        {
            selectors = {"beShelfHead"},
            width = "100%-24",
            halign = "center",
            valign = "top",
        },

        -- The editor's menus inherit these rules: their entries sit left, as
        -- in the mockup (the shared menu leaves a label centred in its row).
        {
            selectors = {"label", "contextMenuLabel"},
            halign = "left",
            lmargin = 6,
        },

        -- The checks.
        {
            selectors = {"beIssue"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            vpad = 4,
        },
        {
            selectors = {"beIssueDot"},
            halign = "left",
            width = 8,
            height = 8,
            valign = "top",
            tmargin = 6,
            rmargin = 8,
            bgimage = true,
            cornerRadius = 4,
        },
        {
            selectors = {"beIssueDot", "success"},
            bgcolor = "@success",
        },
        {
            selectors = {"beIssueDot", "warning"},
            bgcolor = "@warning",
        },
        {
            selectors = {"beIssueDot", "danger"},
            bgcolor = "@danger",
        },
        {
            selectors = {"label", "beIssueText"},
            halign = "left",
            width = "100%-16",
            height = "auto",
            fontSize = 14,
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = {"label", "beCardHint"},
            width = "100%",
            height = "auto",
            valign = "top",
            tmargin = 12,
            fontFace = "@input",
            fontSize = 13,
            color = "@fgMuted",
            textWrap = true,
        },

        -- The amount picker (Slots.lua): a title, what the slot is now, a
        -- search, then one row per kind of amount with its example.
        {
            selectors = {"beAmountPicker"},
            width = 380,
            height = "auto",
            flow = "vertical",
            pad = 10,
            borderBox = true,
        },
        {
            selectors = {"label", "beAmountTitle"},
            width = "100%",
            height = "auto",
            fontSize = 16,
            bold = true,
            color = "@fgStrong",
            bmargin = 4,
        },
        {
            selectors = {"label", "beAmountNow"},
            width = "100%",
            height = "auto",
            fontFace = "@input",
            fontSize = 13,
            color = "@fgMuted",
            bmargin = 6,
            textWrap = true,
        },
        {
            selectors = {"beAmountSearch"},
            width = "100%",
            bmargin = 6,
        },
        {
            selectors = {"beAmountList"},
            width = "100%",
            height = "auto",
            flow = "vertical",
        },
        {
            selectors = {"beAmountRow"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 8,
            vpad = 5,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 4,
        },
        {
            selectors = {"beAmountRow", "hover"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"label", "beAmountName"},
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = "@fg",
        },
        {
            selectors = {"label", "beAmountExample"},
            width = "100%",
            height = "auto",
            fontFace = "@input",
            fontSize = 13,
            color = "@fgMuted",
            textWrap = true,
        },
    }
end

--- The editor's blocks, words and card: fixed colours, the same in every scheme.
--- @return table[]
local function _editorBlockStyles()
    local SIZES = BEStyles.SIZES
    local FIXED = BEStyles.FIXED
    local Fixed = BEStyles.Fixed
    return {
        -- A block's head row (grip, glyph, sentence, gear) and its bodies.
        {
            selectors = {"beBlockHead"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
        },
        {
            selectors = {"beGrip"},
            halign = "left",
            width = SIZES.GRIP,
            height = SIZES.GRIP,
            valign = "top",
            tmargin = 3,
            rmargin = 8,
            bgimage = "phosphor/dots-six-vertical-bold.png",
            bgcolor = Fixed(FIXED.GRIP_REST),
            priority = 10,
        },
        {
            selectors = {"beGrip", "parent:hover"},
            bgcolor = "white",
            priority = 10,
        },
        {
            selectors = {"beGear"},
            width = SIZES.GEAR,
            height = SIZES.GEAR,
            halign = "right",
            valign = "top",
            tmargin = 3,
            bgimage = "phosphor/dots-three-bold.png",
            bgcolor = Fixed(FIXED.GRIP_REST),
            priority = 10,
        },
        {
            selectors = {"beGear", "hover"},
            bgcolor = "white",
            priority = 11,
        },
        {
            selectors = {"beGlyph", "beBlockGlyph"},
            halign = "left",
            valign = "top",
            tmargin = 4,
            priority = 11,
        },
        {
            selectors = {"label", "beTag"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "top",
            tmargin = 2,
            rmargin = 8,
            fontFace = "@input",
            fontSize = 10,
            bold = true,
            uppercase = true,
            color = Fixed(FIXED.BLOCK_TEXT),
            hpad = 5,
            vpad = 2,
            bgimage = true,
            bgcolor = "clear",
            border = 1,
            borderColor = Fixed(FIXED.TAG_EDGE),
            cornerRadius = 3,
            priority = 10,
        },

        -- The sentence: a wrapping row of word labels.
        {
            selectors = {"beSentence"},
            halign = "left",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            valign = "top",
            priority = 10,
        },
        {
            selectors = {"label", "beWordText"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = SIZES.WORD_FONT,
            color = Fixed(FIXED.BLOCK_TEXT),
            vmargin = 2,
            priority = 10,
        },
        {
            selectors = {"label", "beWordAside"},
            fontSize = 14,
            color = Fixed(FIXED.ASIDE_TEXT),
            priority = 11,
        },
        {
            selectors = {"label", "beWord"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = SIZES.WORD_FONT,
            color = Fixed(FIXED.BLOCK_TEXT),
            vmargin = 1,
            bgimage = true,
            bgcolor = Fixed(FIXED.WORD_FILL),
            cornerRadius = 3,
            priority = 10,
        },
        {
            selectors = {"label", "beWordFormula"},
            fontFace = "Courier",
            fontSize = 14,
            priority = 11,
        },
        -- The small "fx" beside an amount: quieter than the words it follows (its text is italic).
        {
            selectors = {"label", "beWordFx"},
            fontSize = 12,
            opacity = 0.75,
            priority = 11,
        },
        {
            selectors = {"label", "beWordEmpty"},
            opacity = 0.6,
            priority = 11,
        },
        {
            selectors = {"label", "beWord", "beWordHot"},
            bgcolor = Fixed(FIXED.WORD_FILL_HOT),
            color = Fixed(FIXED.WORD_TEXT_HOT),
            priority = 12,
        },
        -- A word being typed over where it sits: the hot word's colours, so the
        -- box reads as the word itself turned editable.
        {
            selectors = {"input", "beWordInput"},
            halign = "left",
            valign = "center",
            --the words' own face (labels use @label, inputs default to @input).
            fontFace = "@label",
            fontSize = SIZES.WORD_FONT,
            color = Fixed(FIXED.WORD_TEXT_HOT),
            bgimage = true,
            bgcolor = Fixed(FIXED.WORD_FILL_HOT),
            cornerRadius = 3,
            vmargin = 1,
            hpad = 4,
            borderBox = true,
            priority = 12,
        },
        {
            selectors = {"input", "beWordInputFormula"},
            fontFace = "Courier",
            fontSize = 14,
            priority = 13,
        },

        -- Keyword chips, with an X that shows under the pointer.
        {
            selectors = {"beChip"},
            halign = "left",
            width = "auto",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            rmargin = 4,
            vmargin = 2,
            hpad = 6,
            vpad = 1,
            borderBox = true,
            bgimage = true,
            bgcolor = Fixed(FIXED.WORD_FILL),
            border = 1,
            borderColor = Fixed(FIXED.CHIP_EDGE),
            cornerRadius = 5,
            priority = 10,
        },
        {
            selectors = {"label", "beChipText"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontFace = "@input",
            fontSize = 13,
            color = Fixed(FIXED.BLOCK_TEXT),
            priority = 10,
        },
        {
            selectors = {"beChipX"},
            halign = "left",
            width = 12,
            height = 12,
            valign = "center",
            lmargin = 4,
            bgimage = "phosphor/x-bold.png",
            bgcolor = "white",
            opacity = 0,
            priority = 10,
        },
        {
            selectors = {"beChipX", "parent:hover"},
            opacity = 1,
            priority = 10,
        },

        -- A block's bodies: tier rows (a label beside an inner list) or an
        -- inset list on the window's own colour.
        {
            selectors = {"beTierRow"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 6,
        },
        {
            selectors = {"beTierLabel"},
            halign = "left",
            width = SIZES.TIER_LABEL,
            height = "auto",
            flow = "vertical",
            valign = "top",
            lpad = 6,
            tpad = 9,
            rmargin = 8,
            borderBox = true,
        },
        {
            selectors = {"label", "beTierName"},
            halign = "left",
            width = "100%",
            height = "auto",
            fontFace = "@input",
            fontSize = 13,
            bold = true,
            color = Fixed(FIXED.BLOCK_TEXT),
            textWrap = true,
            priority = 10,
        },
        {
            selectors = {"label", "beTierSub"},
            halign = "left",
            width = "100%",
            height = "auto",
            fontFace = "@input",
            fontSize = 11,
            color = Fixed(FIXED.ASIDE_TEXT),
            priority = 10,
        },
        {
            selectors = {"beInner"},
            height = "auto",
            flow = "vertical",
            valign = "top",
            hpad = 8,
            vpad = 2,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 4,
        },
        {
            selectors = {"beInner", "beInset"},
            width = "100%-14",
            halign = "right",
            tmargin = 6,
        },
        {
            selectors = {"beInner", "beTierInner"},
            width = "100%-" .. (SIZES.TIER_LABEL + 8),
            halign = "left",
        },

        -- The fixed header group: one colour, rows split by a hairline.
        {
            selectors = {"beHeaderGroup"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
            bgimage = true,
            border = 1,
            borderColor = Fixed(FIXED.BLOCK_EDGE),
            cornerRadius = SIZES.BLOCK_RADIUS,
            priority = 10,
        },
        {
            selectors = {"beHeaderRow"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            hpad = 10,
            vpad = 7,
            borderBox = true,
        },
        {
            selectors = {"beHeaderRule"},
            width = "100%",
            height = 1,
            valign = "top",
            bgimage = true,
            bgcolor = Fixed(FIXED.ROW_RULE),
            priority = 10,
        },

        -- A shelf row: a small block in the colour of the block it adds.
        {
            selectors = {"beShelfRow"},
            width = "100%-24",
            height = SIZES.SHELF_ROW,
            halign = "center",
            valign = "top",
            vmargin = 4,
            flow = "horizontal",
            lpad = 8,
            rpad = 10,
            borderBox = true,
            bgimage = true,
            border = 1,
            borderColor = Fixed(FIXED.BLOCK_EDGE),
            cornerRadius = SIZES.BLOCK_RADIUS,
            priority = 10,
        },
        {
            selectors = {"beGrip", "beShelfGrip"},
            valign = "center",
            tmargin = 0,
            priority = 11,
        },
        {
            selectors = {"beGlyph", "beShelfGlyph"},
            halign = "left",
            valign = "center",
            tmargin = 0,
            priority = 11,
        },
        {
            selectors = {"label", "beShelfName"},
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 15,
            color = Fixed(FIXED.BLOCK_TEXT),
            priority = 10,
        },

        -- The book card's lines (the card panel itself is beCard).
        {
            selectors = {"beCardLine"},
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 3,
            priority = 10,
        },
        {
            selectors = {"beCardLine", "hover"},
            bgcolor = Fixed(FIXED.CARD_HOVER),
            priority = 10,
        },
        {
            selectors = {"beCardChip"},
            width = "auto",
            height = "auto",
            valign = "center",
            hpad = 4,
            vpad = 1,
            bgimage = true,
            bgcolor = Fixed(FIXED.INK),
            cornerRadius = 2,
            priority = 10,
        },
        {
            selectors = {"beCardIcon"},
            halign = "left",
            width = 17,
            height = 17,
            valign = "center",
            rmargin = 6,
            bgcolor = Fixed(FIXED.INK),
            priority = 10,
        },
    }
end

--- The blocks and the book card: fixed colours, the same in every scheme.
--- @return table[]
local function _blockStyles()
    local SIZES = BEStyles.SIZES
    local FIXED = BEStyles.FIXED
    local Fixed = BEStyles.Fixed

    local styles = {
        {
            selectors = {"beBlock"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = true,
            bgcolor = Fixed("#5b564e"),
            border = 1,
            borderColor = Fixed(FIXED.BLOCK_EDGE),
            cornerRadius = SIZES.BLOCK_RADIUS,
            tpad = 8,
            bpad = 8,
            lpad = 8,
            rpad = 10,
            borderBox = true,
            priority = 10,
        },
        -- Selected: a ring outside the block, so it does not fight the colour.
        {
            selectors = {"beBlock", "selected"},
            boxShadow = {x = 0, y = 0, blur = 0, spread = SIZES.SELECTED_RING, color = "@fgStrong"},
            priority = 10,
        },
        -- A shelf block that cannot go in the chosen list keeps its colour and
        -- shows a dashed outline.
        {
            selectors = {"beBlock", "beNoFit"},
            borderStyle = "dashed",
            borderColor = Fixed(FIXED.NO_FIT_EDGE),
            priority = 10,
        },
        -- The copy of a block that follows the pointer during a drag.
        {
            selectors = {"beBlock", "beGhost"},
            width = "auto",
            boxShadow = {x = 0, y = 6, blur = 16, color = "#000000a0"},
            priority = 10,
        },
        {
            selectors = {"label", "beBlockText"},
            width = "100%-" .. SIZES.BLOCK_TEXT_INSET,
            height = "auto",
            valign = "center",
            fontSize = SIZES.BLOCK_FONT_SIZE,
            color = Fixed(FIXED.BLOCK_TEXT),
            textWrap = true,
            priority = 10,
        },
        -- On the ghost the text sets the width, not the other way round.
        {
            selectors = {"label", "beBlockText", "beGhostText"},
            width = "auto",
            textWrap = false,
            priority = 10,
        },
        -- White, so the Phosphor mask draws white on every block colour.
        {
            selectors = {"beGlyph"},
            width = SIZES.GLYPH,
            height = SIZES.GLYPH,
            valign = "center",
            rmargin = SIZES.GLYPH_GAP,
            bgcolor = "white",
            priority = 10,
        },

        -- The book-style ability card: fixed paper and ink.
        {
            selectors = {"beCard"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgimage = true,
            bgcolor = Fixed(FIXED.PAPER),
            cornerRadius = 4,
            pad = 14,
            borderBox = true,
            priority = 10,
        },
        {
            selectors = {"beCardRule"},
            border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
            borderColor = Fixed(FIXED.INK),
            priority = 10,
        },
        {
            selectors = {"label", "beCardText"},
            height = "auto",
            fontSize = 14,
            color = Fixed(FIXED.INK),
            textWrap = true,
            priority = 10,
        },
        {
            selectors = {"beCardMark"},
            bgcolor = Fixed(FIXED.INK),
            priority = 10,
        },
    }

    -- One rule pair per group: the literal colour, and its hover colour.
    for groupId, entry in pairs(BEStyles.BlockColors()) do
        local groupClass = BEStyles.GroupClass(groupId)
        styles[#styles + 1] = {
            selectors = {"beBlock", groupClass},
            bgcolor = Fixed(entry.color),
            priority = 10,
        }
        styles[#styles + 1] = {
            selectors = {"beBlock", groupClass, "hover"},
            bgcolor = Fixed(entry.hover),
            priority = 10,
        }
        styles[#styles + 1] = {
            selectors = {"beShelfRow", groupClass},
            bgcolor = Fixed(entry.color),
            priority = 10,
        }
        styles[#styles + 1] = {
            selectors = {"beShelfRow", groupClass, "hover"},
            bgcolor = Fixed(entry.hover),
            priority = 10,
        }
        styles[#styles + 1] = {
            selectors = {"beHeaderGroup", groupClass},
            bgcolor = Fixed(entry.color),
            priority = 10,
        }
    end

    return styles
end

--- Every rule the editor adds to the theme. Use it with ThemeEngine.MergeStyles
--- on the window root, and again when the theme changes:
---     styles = ThemeEngine.MergeStyles(BEStyles.GetStyles())
--- @return table[]
function BEStyles.GetStyles()
    local styles = _chromeStyles()
    for _, rule in ipairs(_blockStyles()) do
        styles[#styles + 1] = rule
    end
    for _, rule in ipairs(_editorChromeStyles()) do
        styles[#styles + 1] = rule
    end
    for _, rule in ipairs(_editorBlockStyles()) do
        styles[#styles + 1] = rule
    end
    return styles
end

--- A copy of a gui args table one level deep. Not DeepCopy: args may hold
--- panels and handlers, which must stay the same objects.
--- @param args? table
--- @return table
local function _shallowCopy(args)
    local result = {}
    for k, v in pairs(args or {}) do
        result[k] = v
    end
    return result
end

--- A group's glyph: a small white Phosphor mask, drawn on every block and
--- shelf row so colour is never the only cue. Returns nil for a group with no
--- glyph (header lines), which a children list skips.
--- @param groupId string
--- @param args? table extra gui.Panel fields (margins, alignment)
--- @return Panel|nil
function BEStyles.Glyph(groupId, args)
    local group = Block.GetGroup(groupId)
    if group == nil or group.glyph == nil then
        return nil
    end
    local options = _shallowCopy(args)
    options.classes = {"beGlyph"}
    options.bgimage = "phosphor/" .. group.glyph .. ".png"
    options.interactable = false
    return gui.Panel(options)
end

--- A plain block: its group's colour and glyph, and one line of text. This is
--- the phase 0 stand-in for BlockPanel.lua (grip, link words, menu), used by
--- the empty editor's shelf and the proofs.
--- @param args table gui.Panel fields, plus: group (a Block group id), text (string), textClasses (string[], extra classes for the label)
--- @return Panel
function BEStyles.BlockPanel(args)
    local options = _shallowCopy(args)
    local groupId = options.group
    local text = options.text or ""
    local textClasses = options.textClasses or {}
    options.group = nil
    options.text = nil
    options.textClasses = nil

    local classes = {"beBlock", BEStyles.GroupClass(groupId)}
    for _, class in ipairs(options.classes or {}) do
        classes[#classes + 1] = class
    end
    options.classes = classes
    --Inline, not in the beBlock rule (the rule's valign did not apply): a
    --vertical list centres each row in an equal share of the spare height.
    options.valign = options.valign or "top"

    local labelClasses = {"beBlockText"}
    for _, class in ipairs(textClasses) do
        labelClasses[#labelClasses + 1] = class
    end

    local children = {}
    local glyph = BEStyles.Glyph(groupId)
    if glyph ~= nil then
        children[#children + 1] = glyph
    end
    children[#children + 1] = gui.Label{
        classes = labelClasses,
        text = text,
        interactable = false,
    }
    options.children = children
    return gui.Panel(options)
end

--- A section header as the mockup draws it: a caret, a small uppercase title,
--- an optional "optional" tag and a count on the right, with a rule under it.
--- Returns the header and its rule as two panels, for a vertical list.
--- @param args {title: string, count?: string, optional?: string, shelf?: boolean, press?: fun(element: Panel), countFn?: (fun(state: BEState): string), data?: table}
--- @return Panel header, Panel rule
function BEStyles.SectionHeader(args)
    local children = {
        gui.Panel{ classes = {"beCaret"}, interactable = false },
        gui.Label{ classes = {"beSecTitle"}, text = args.title, interactable = false },
    }
    if args.optional ~= nil then
        children[#children + 1] = gui.Label{ classes = {"beSecOptional"}, text = args.optional, interactable = false }
    end
    if args.count ~= nil or args.countFn ~= nil then
        local countFn = args.countFn
        children[#children + 1] = gui.Label{
            classes = {"beSecCount"},
            text = args.count or "",
            interactable = false,
            --a count that follows the record, such as "3 steps".
            [BlockEditor.REFRESH_EVENT] = countFn ~= nil and function(element, state)
                element.text = countFn(state)
            end or nil,
        }
    end
    local header = gui.Panel{
        classes = {"beSecHead", args.shelf and "beSecHeadShelf" or nil, args.shelf and "beShelfHead" or nil},
        press = args.press,
        data = args.data or {},
        children = children,
    }
    local rule = gui.Panel{
        classes = {"beSecRule", args.shelf and "beShelfHead" or nil},
        interactable = false,
    }
    return header, rule
end
