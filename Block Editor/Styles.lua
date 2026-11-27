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

--The design's hexes are sRGB (from the web prototype); fixed colours carry this
--prefix, as the Cream palette does in DMHub Titlescreen/Styles.lua. Set it to ""
--if the Blocks proof shows the palette wrong against the prototype.
BEStyles.COLOR_PREFIX = "srgb:"

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

    -- Drop slots between blocks: hidden, hinted during a drag, open under the pointer
    SLOT_REST = 2,
    SLOT_HINT = 12,
    SLOT_OPEN = "2.3em",
    SLOT_MARGIN = 3,

    -- The ring round a selected block
    SELECTED_RING = 2,
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
}

--How much brighter a block is under the pointer (0-1, towards white).
local HOVER_LIGHTEN = 0.14

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
            vscroll = true,
        },
        {
            selectors = {"label", "beHeading"},
            width = "100%",
            height = "auto",
            fontSize = 16,
            bold = true,
            color = "@fgStrong",
            bmargin = 4,
        },
        {
            selectors = {"label", "beNote"},
            width = "100%",
            height = "auto",
            fontSize = 13,
            color = "@fgMuted",
            textWrap = true,
            bmargin = 6,
        },
        {
            selectors = {"label", "beGroupHeading"},
            width = "100%",
            height = "auto",
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
            hpad = SIZES.BLOCK_HPAD,
            vpad = SIZES.BLOCK_VPAD,
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
            width = "100% available",
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
