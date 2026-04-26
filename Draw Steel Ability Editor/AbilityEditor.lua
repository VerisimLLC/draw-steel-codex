local mod = dmhub.GetModLoading()

-- Opt-out toggle. The sectioned Ability Editor is the default; this lets a
-- user fall back to the classic editor if they hit a regression.
setting{
    id = "classicAbilityEditor",
    description = "Use classic ability editor",
    editor = "check",
    default = false,
    storage = "preference",
    section = "game",
}

-- Use rawget because the DMHub Lua env errors on reads of uninitialized globals.
AbilityEditor = rawget(_G, "AbilityEditor") or {}
AbilityEditor._recentBehaviors = AbilityEditor._recentBehaviors or {}
AbilityEditor._recentModifiers = AbilityEditor._recentModifiers or {}

function AbilityEditor._trackRecentBehavior(typeId)
    local list = AbilityEditor._recentBehaviors
    for i = #list, 1, -1 do
        if list[i] == typeId then table.remove(list, i) end
    end
    table.insert(list, 1, typeId)
    while #list > 5 do table.remove(list) end
end

function AbilityEditor._trackRecentModifier(typeId)
    local list = AbilityEditor._recentModifiers
    for i = #list, 1, -1 do
        if list[i] == typeId then table.remove(list, i) end
    end
    table.insert(list, 1, typeId)
    while #list > 5 do table.remove(list) end
end

--[[
    ============================================================================
    Layout constants
    ============================================================================
    The compendium dialog (ActivatedAbilityEditor.lua) is resized to fill the
    screen when the sectioned editor is active. We claim 100% of that area
    with a three-column body under a title strip.
]]
local LAYOUT = {
    TITLE_HEIGHT = 44,

    NAV_WIDTH = 220,
    -- Ability tooltip cards render at ~400px native (see CreateAbilityTooltip
    -- in DMHub Compendium/ActivatedAbilityEditor.lua:34). Give the preview
    -- enough room for that plus padding, so description text wraps to the
    -- card's natural width rather than being squeezed.
    PREVIEW_WIDTH = 440,
    -- Detail column fills whatever remains between nav and preview.

    NAV_BUTTON_HEIGHT = 42,
    NAV_BUTTON_VMARGIN = 6,

    COL_VPAD = 16,
    COL_HPAD = 16,
}

local COLORS = {
    BG = "#080B09",
    PANEL_BG = "#10110F",
    GOLD = "#966D4B",
    GOLD_BRIGHT = "#F1D3A5",
    GOLD_DIM = "#E9B86F",
    CREAM = "#BC9B7B",
    CREAM_BRIGHT = "#DFCFC0",
    GRAY = "#666663",
}

-- Expose colors for other files in the module.
AbilityEditor.COLORS = COLORS

-- The ordered section list. Section IDs are stable; labels can change later
-- without breaking state.
local SECTIONS = {
    { id = "overview",     label = "Overview" },
    { id = "costAndAction", label = "Cost & Action" },
    { id = "targeting",    label = "Targeting" },
    { id = "effects",      label = "Effects" },
    { id = "presentation", label = "Presentation" },
}

-- Expose for other files in the module to reference.
AbilityEditor.SECTIONS = SECTIONS

--[[
    ============================================================================
    Shared styles
    ============================================================================
    Inline the subset of CBStyles conventions we need rather than depending on
    CBStyles.GetStyles(), which wires character-builder-specific width math.
    Colors and fonts match Character Builder so the editor feels consistent.
]]
local function _editorStyles()
    return {
        -- SourceReference:Editor (DMHub Utils/SourceReference.lua) relies on
        -- classic formPanel/formLabel/formDropdown/formInput class styles to
        -- render with sensible widths. Without these the Source row
        -- collapses to ~0 height and the dropdown is invisible. Styles.Form
        -- is the shared engine-side style pack defined in
        -- DMHub Titlescreen/Styles.lua:1177.
        Styles.Form,

        gui.Style{
            selectors = {"nae-root"},
            fontFace = "Berling",
            fontSize = 14,
            color = COLORS.CREAM,
            bold = false,
        },
        -- Overrides for Styles.Form descendants (used by SourceReference:Editor).
        -- The base Form style pack sets formLabel/formDropdown/formInput to
        -- halign = "right" and formLabel minWidth = 140, which stacks them
        -- flush against the detail column's right edge and leaves a big
        -- dead-space gap on the left. Overriding halign alone didn't move
        -- them (likely because the formPanel is width = "100%" and
        -- horizontal flow doesn't re-anchor children via halign once they
        -- have intrinsic width). The working recipe is to make the
        -- formPanel width = "auto" + halign = "left" so the whole row
        -- shrinks to fit and sits on the left; then the formLabel
        -- minWidth = 140 still reserves space but the row as a whole no
        -- longer spans the column.
        gui.Style{
            selectors = {"formPanel"},
            width = "auto",
            halign = "left",
            priority = 5,
        },
        gui.Style{
            selectors = {"formLabel"},
            halign = "left",
            minWidth = 0,
            priority = 5,
        },
        gui.Style{
            selectors = {"formDropdown"},
            halign = "left",
            priority = 5,
        },
        gui.Style{
            selectors = {"formInput"},
            halign = "left",
            priority = 5,
        },
        gui.Style{
            selectors = {"formValue"},
            halign = "left",
            priority = 5,
        },
        -- Nav column
        gui.Style{
            selectors = {"nae-nav-col"},
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-nav-button"},
            width = LAYOUT.NAV_WIDTH - 24,
            height = LAYOUT.NAV_BUTTON_HEIGHT,
            halign = "center",
            -- Stack tight to the top of the nav column. Without an explicit
            -- per-child valign, DMHub's flow layout distributes children
            -- across the 100%-height parent, producing uneven gaps.
            valign = "top",
            vmargin = LAYOUT.NAV_BUTTON_VMARGIN,
            hpad = 12,
            textAlignment = "left",
            fontSize = 18,
            bold = false,
            color = COLORS.CREAM,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 3,
            borderBox = true,
        },
        gui.Style{
            selectors = {"nae-nav-button", "hover"},
            bgcolor = COLORS.GOLD_DIM,
            color = COLORS.BG,
        },
        gui.Style{
            selectors = {"nae-nav-button", "selected"},
            bgcolor = COLORS.GOLD_DIM,
            color = COLORS.BG,
            bold = true,
            borderColor = COLORS.CREAM_BRIGHT,
        },
        -- Detail column
        gui.Style{
            selectors = {"nae-detail-col"},
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-section-content"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
        },
        -- Use `collapsed` (not `hidden`) so the inactive section panels take
        -- zero space in the detail column's vertical flow. `hidden` only
        -- suppresses rendering and leaves the layout slot, which stacks
        -- section headings down the page as you click through nav buttons.
        gui.Style{
            selectors = {"nae-section-content", "inactive"},
            collapsed = 1,
        },
        gui.Style{
            selectors = {"nae-section-heading"},
            width = "100%",
            height = "auto",
            fontSize = 24,
            bold = true,
            color = COLORS.GOLD_BRIGHT,
            textAlignment = "left",
            bmargin = 4,
            bgimage = "panels/square.png",
            border = {y1 = 0, y2 = 2, x1 = 0, x2 = 0},
            borderColor = COLORS.GOLD,
            bgcolor = "clear",
            vpad = 4,
        },
        gui.Style{
            selectors = {"nae-section-placeholder"},
            width = "100%",
            height = "auto",
            fontSize = 14,
            italics = true,
            color = COLORS.GRAY,
            textAlignment = "left",
            vmargin = 16,
        },
        -- Form rows: stacked label + control. Works well in the narrow ~440px
        -- detail column without wrapping label text the way a horizontal
        -- label + input row would.
        gui.Style{
            selectors = {"nae-field-row"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            vmargin = 8,
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-field-label"},
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            bmargin = 4,
        },
        -- Inline variant: label + small control sit on the same row. Used
        -- for compact fields like Display Order where stacking label above
        -- a 3-digit input wastes vertical space.
        gui.Style{
            selectors = {"nae-field-row-inline"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            vmargin = 8,
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-field-label-inline"},
            width = "auto",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            valign = "center",
            rmargin = 10,
        },
        gui.Style{
            selectors = {"nae-field-input"},
            width = "100%",
            height = 28,
            fontSize = 14,
            color = COLORS.CREAM_BRIGHT,
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 2,
            hpad = 6,
            vpad = 2,
            borderBox = true,
            textAlignment = "left",
        },
        gui.Style{
            selectors = {"nae-field-textarea"},
            priority = 3,
            width = "100%",
            height = "auto",
            minHeight = 60,
            fontSize = 14,
            color = COLORS.CREAM_BRIGHT,
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 2,
            hpad = 6,
            vpad = 4,
            borderBox = true,
            textAlignment = "topleft",
        },
        -- Field dropdowns (Category, Villain Action, Keywords add) size to a
        -- fixed width rather than filling the whole row. 100% would stretch
        -- them past the column edge (the dropdown's internal chevron + text
        -- rendering doesn't respect tight right-edges well). 280 is close to
        -- Styles.Form's formDropdown default (240) and feels balanced in the
        -- ~400px detail column.
        gui.Style{
            selectors = {"nae-field-dropdown"},
            width = 280,
            height = 30,
            halign = "left",
            fontSize = 14,
            color = COLORS.CREAM_BRIGHT,
        },
        -- Skin the default `dropdown` element (gui.Dropdown's auto-class) so
        -- the dropdown body and chevron match the gold/cream palette. These
        -- apply to every dropdown inside the editor, not just field rows.
        -- "priority = 3" edges past `gui.Dropdown`'s defaults from core styles.
        -- No width here: the cascade lets `nae-field-dropdown` (100%) size our
        -- own field dropdowns, and lets Styles.Form's `formDropdown` (240px)
        -- size the Source row's inline dropdown. Setting width=100% here was
        -- overriding formDropdown and causing the Source dropdown to overflow
        -- its row.
        gui.Style{
            selectors = {"dropdown"},
            priority = 3,
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 3,
            hpad = 8,
            vpad = 2,
            borderBox = true,
            fontSize = 14,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            halign = "left",
            height = 30,
        },
        gui.Style{
            selectors = {"dropdown", "hover"},
            priority = 4,
            borderColor = COLORS.GOLD_DIM,
            -- Override engine default that sets bgcolor = white on hover.
            bgcolor = COLORS.PANEL_BG,
        },
        -- The engine sets dropdownLabel color = "black" and dropdownTriangle
        -- bgcolor = "black" on parent:hover (Styles.lua:295,309). Override
        -- both so text stays readable against our dark hover background.
        gui.Style{
            selectors = {"dropdownLabel", "parent:hover"},
            priority = 4,
            color = COLORS.CREAM_BRIGHT,
        },
        gui.Style{
            selectors = {"dropdownTriangle", "parent:hover"},
            priority = 4,
            bgcolor = COLORS.GOLD,
        },
        gui.Style{
            selectors = {"dropdown", "open"},
            priority = 3,
            borderColor = COLORS.CREAM_BRIGHT,
            color = COLORS.CREAM_BRIGHT,
        },
        -- Dropdown item list + rows.
        gui.Style{
            selectors = {"dropdown-list"},
            priority = 3,
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            borderBox = true,
        },
        gui.Style{
            selectors = {"dropdown-item"},
            priority = 3,
            bgcolor = "clear",
            color = COLORS.CREAM_BRIGHT,
            fontSize = 14,
            hpad = 8,
            vpad = 4,
            borderBox = true,
        },
        gui.Style{
            selectors = {"dropdown-item", "hover"},
            priority = 4,
            bgcolor = COLORS.GOLD,
            color = COLORS.BG,
        },
        -- Input element skin (applies to all gui.Input inside the editor).
        gui.Style{
            selectors = {"input"},
            priority = 3,
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 2,
            hpad = 6,
            vpad = 2,
            borderBox = true,
            fontSize = 14,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
        },
        gui.Style{
            selectors = {"input", "hover"},
            priority = 3,
            borderColor = COLORS.GOLD_DIM,
        },
        gui.Style{
            selectors = {"input", "focus"},
            priority = 3,
            borderColor = COLORS.CREAM_BRIGHT,
        },
        -- Themed `button` style (gui.Button's auto-class). Matches the
        -- gold-on-dark palette used for dropdowns and inputs. Applies to
        -- every gui.Button inside the editor's subtree -- in particular the
        -- "Open" button next to the Source row (rendered by
        -- SourceReference:Editor in DMHub Utils/SourceReference.lua:100).
        -- Does NOT reach the compendium dialog's Close button, which lives
        -- outside our subtree (that one needs a base-code tweak and is
        -- tracked for the merge PR).
        gui.Style{
            selectors = {"button"},
            priority = 3,
            width = "auto",
            height = "auto",
            minWidth = 72,
            minHeight = 26,
            hpad = 12,
            vpad = 4,
            hmargin = 4,
            vmargin = 2,
            borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 3,
            fontSize = 14,
            fontWeight = "bold",
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "center",
        },
        gui.Style{
            selectors = {"button", "hover"},
            priority = 3,
            bgcolor = COLORS.GOLD_DIM,
            borderColor = COLORS.CREAM_BRIGHT,
            color = COLORS.BG,
            transitionTime = 0.1,
        },
        gui.Style{
            selectors = {"button", "press"},
            priority = 3,
            bgcolor = COLORS.GOLD,
            color = COLORS.BG,
            brightness = 0.85,
        },
        gui.Style{
            selectors = {"button", "disabled"},
            priority = 3,
            bgcolor = COLORS.PANEL_BG,
            borderColor = COLORS.GRAY,
            color = COLORS.GRAY,
        },
        gui.Style{
            selectors = {"nae-field-hint"},
            width = "100%",
            height = "auto",
            fontSize = 12,
            italics = true,
            color = COLORS.GRAY,
            textAlignment = "left",
            tmargin = 2,
        },
        -- Container for sub-fields of a parent toggle or dropdown (the
        -- Channel Resource sub-cluster, the Persistence sub-cluster).
        -- We used to left-indent this by 16px to signal the hierarchy,
        -- but that produced a compounding drift where each subgroup's
        -- children visually drifted right of the top-level fields. The
        -- revealed/collapsed animation + the parent toggle above are
        -- already enough to signal the grouping; fields stay flush-left
        -- with the section's other labels for consistent scanning.
        gui.Style{
            selectors = {"nae-field-subgroup"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            bgcolor = "clear",
        },
        -- Checkbox used for top-level toggles (Strain, Persistence, and the
        -- Persistence-mode-contingent "Target Must Be In Range" check).
        -- The engine default `checkbox` style (DMHub Titlescreen/Styles.lua:753)
        -- is height = 30 with an 18pt label, which renders much larger than
        -- our 14pt body text and dominates its row. Override at priority 3
        -- to shrink the whole widget back to body-text scale and recolor the
        -- box/mark to the gold-on-dark palette. These selectors apply to
        -- every gui.Check inside the editor subtree.
        gui.Style{
            selectors = {"checkbox"},
            priority = 3,
            height = 24,
            width = "auto",
            halign = "left",
            valign = "center",
        },
        gui.Style{
            selectors = {"checkbox-label"},
            priority = 3,
            fontSize = 14,
            color = COLORS.CREAM_BRIGHT,
            halign = "left",
            valign = "center",
            bold = true,
        },
        gui.Style{
            selectors = {"check-background"},
            priority = 3,
            borderColor = COLORS.GOLD,
            borderWidth = 1,
            bgcolor = COLORS.PANEL_BG,
        },
        gui.Style{
            selectors = {"check-mark"},
            priority = 3,
            bgcolor = COLORS.GOLD_BRIGHT,
        },
        -- Reserved hook class on our Strain/Persistence/Target-in-range
        -- checkboxes; kept so we can target those three specifically later
        -- without touching every checkbox in the subtree.
        gui.Style{
            selectors = {"nae-toggle-check"},
            valign = "center",
        },
        -- "More options" CollapseArrow row (Targeting section foldout).
        -- Text + chevron together, centered in column.
        gui.Style{
            selectors = {"nae-more-options-row"},
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            valign = "center",
            tmargin = 12,
            bmargin = 4,
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-more-options-label"},
            width = "auto",
            height = "auto",
            fontSize = 13,
            bold = true,
            color = COLORS.CREAM,
            textAlignment = "left",
            valign = "center",
        },
        gui.Style{
            selectors = {"nae-more-options-chevron"},
            height = 12,
            width = 24,
            valign = "center",
            lmargin = 6,
            bgimage = "panels/hud/down-arrow.png",
            bgcolor = COLORS.GOLD_BRIGHT,
            transitionTime = 0.15,
        },
        gui.Style{
            selectors = {"nae-more-options-chevron", "nae-collapsed"},
            scale = {x = 1, y = -1},
        },
        gui.Style{
            selectors = {"nae-more-options-chevron", "hover"},
            bgcolor = COLORS.CREAM_BRIGHT,
        },
        -- Filter list entries (Ability Filters / Reasoned Filters).
        gui.Style{
            selectors = {"nae-filter-heading"},
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.GOLD_DIM,
            textAlignment = "left",
            tmargin = 8,
            bmargin = 4,
        },
        gui.Style{
            selectors = {"nae-filter-entry"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgcolor = "clear",
            bmargin = 6,
        },
        gui.Style{
            selectors = {"nae-filter-formula-row"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-keyword-chip"},
            width = "auto",
            height = 22,
            flow = "horizontal",
            halign = "left",
            valign = "center",
            hpad = 8,
            vpad = 0,
            rmargin = 6,
            bmargin = 4,
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 11,
            borderBox = true,
        },
        gui.Style{
            selectors = {"nae-keyword-chip-label"},
            width = "auto",
            height = "auto",
            fontSize = 12,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            rmargin = 4,
        },
        -- Preview column. Always visible; fixed width from LAYOUT.PREVIEW_WIDTH.
        gui.Style{
            selectors = {"nae-preview-col"},
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-preview-body"},
            width = "100%",
            height = "100%",
        },
        gui.Style{
            selectors = {"nae-preview-heading"},
            height = "auto",
            fontSize = 16,
            bold = true,
            color = COLORS.GOLD_BRIGHT,
            textAlignment = "left",
            bmargin = 4,
        },
        -- Title strip
        gui.Style{
            selectors = {"nae-title-strip"},
            width = "100%",
            height = LAYOUT.TITLE_HEIGHT,
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-title-label"},
            width = "auto",
            height = "auto",
            fontSize = 22,
            bold = true,
            color = COLORS.GOLD_BRIGHT,
            textAlignment = "left",
            hmargin = 4,
        },
        gui.Style{
            selectors = {"nae-subtitle-label"},
            width = "auto",
            height = "auto",
            fontSize = 14,
            italics = true,
            color = COLORS.CREAM,
            textAlignment = "left",
            hmargin = 12,
        },
        -- Detail col width is set once at construction time (the preview
        -- column is always visible, no collapse handling needed).

        -- ================================================================
        -- Effects section: behavior list
        -- ================================================================
        gui.Style{
            selectors = {"nae-behavior-item"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-behavior-header"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = COLORS.PANEL_BG,
            border = {y1 = 0, y2 = 1, x1 = 0, x2 = 0},
            borderColor = COLORS.GOLD,
            hpad = 8,
            vpad = 6,
            borderBox = true,
        },
        gui.Style{
            selectors = {"nae-behavior-summary"},
            width = "auto",
            height = "auto",
            fontSize = 16,
            bold = true,
            color = COLORS.GOLD_BRIGHT,
            halign = "left",
            valign = "center",
            textAlignment = "left",
        },
        gui.Style{
            selectors = {"nae-behavior-controls"},
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-behavior-copy-btn"},
            priority = 3,
            width = "auto",
            height = "auto",
            fontSize = 11,
            bold = true,
            color = COLORS.CREAM,
            valign = "center",
            rmargin = 8,
            hpad = 6,
            vpad = 2,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 2,
            bgimage = "panels/square.png",
            bgcolor = COLORS.PANEL_BG,
            borderBox = true,
        },
        gui.Style{
            selectors = {"nae-behavior-copy-btn", "hover"},
            priority = 3,
            bgcolor = COLORS.GOLD_DIM,
            color = COLORS.BG,
            borderColor = COLORS.CREAM_BRIGHT,
        },
        gui.Style{
            selectors = {"nae-behavior-copy-btn", "press"},
            priority = 3,
            bgcolor = COLORS.GOLD,
            color = COLORS.BG,
        },
        gui.Style{
            selectors = {"nae-behavior-arrow"},
            width = 24,
            height = 12,
            valign = "center",
            bgimage = "panels/hud/down-arrow.png",
            bgcolor = COLORS.GOLD_BRIGHT,
            lmargin = 4,
            transitionTime = 0.15,
        },
        gui.Style{
            selectors = {"nae-behavior-arrow", "nae-up"},
            scale = {x = 1, y = -1},
        },
        gui.Style{
            selectors = {"nae-behavior-arrow", "disabled"},
            bgcolor = COLORS.GRAY,
        },
        gui.Style{
            selectors = {"nae-behavior-arrow", "hover"},
            bgcolor = COLORS.CREAM_BRIGHT,
        },
        -- Disabled arrows should not brighten on hover.
        gui.Style{
            selectors = {"nae-behavior-arrow", "disabled", "hover"},
            bgcolor = COLORS.GRAY,
        },
        gui.Style{
            selectors = {"nae-behavior-content"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            bgcolor = "clear",
            hpad = 8,
            vpad = 4,
        },
        gui.Style{
            selectors = {"nae-behavior-divider"},
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = COLORS.GOLD .. "66",
            vmargin = 8,
        },
        gui.Style{
            selectors = {"nae-behavior-add-row"},
            width = "auto",
            height = "auto",
            halign = "left",
            tmargin = 12,
        },
        -- Fixed bottom bar for Effects section. Sits below the scroll area
        -- inside detailCol. Collapsed for all other sections.
        gui.Style{
            selectors = {"nae-effects-bottom-bar"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "center",
            valign = "bottom",
            bgcolor = "clear",
            tmargin = 4,
            hpad = LAYOUT.COL_HPAD,
            borderBox = true,
        },
        -- Pill container for mode/tier/strain selections.
        gui.Style{
            selectors = {"nae-behavior-pills"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            halign = "left",
            valign = "top",
            hpad = 8,
            vpad = 4,
            bgcolor = "clear",
        },
        -- Pill label base style -- themed version of g_modalPanelStyles.
        gui.Style{
            selectors = {"nae-pill-label"},
            priority = 3,
            borderWidth = 2,
            halign = "left",
            bgimage = "panels/square.png",
            borderColor = COLORS.PANEL_BG,
            bgcolor = COLORS.PANEL_BG,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            width = "auto",
            height = "auto",
            fontSize = 14,
            textAlignment = "left",
            hpad = 10,
            vpad = 3,
        },
        gui.Style{
            selectors = {"nae-pill-label", "selected"},
            priority = 3,
            color = COLORS.BG,
            bgcolor = COLORS.GOLD_DIM,
            transitionTime = 0.2,
        },
        gui.Style{
            selectors = {"nae-pill-label", "selected", "disabled"},
            priority = 3,
            bgcolor = "#ff4444",
        },
        gui.Style{
            selectors = {"nae-pill-label", "hover"},
            priority = 3,
            brightness = 1.5,
            borderColor = COLORS.GOLD,
            transitionTime = 0.2,
        },
        -- Override the delete-item-button's internal styles (priority 10 in
        -- Gui.lua) to match the gold palette. Priority 11 to beat them.
        gui.Style{
            selectors = {"delete-item-button"},
            priority = 11,
            bgcolor = COLORS.CREAM,
        },
        gui.Style{
            selectors = {"delete-item-button", "hover"},
            priority = 11,
            bgcolor = "#ff4444",
        },

        -- ================================================================
        -- Presentation section: icon + VFX
        -- ================================================================

        -- Sub-heading labels within the Presentation section ("Icon",
        -- "Visual Effects"). Smaller than the section heading, gold-dim
        -- to separate from the GOLD_BRIGHT section title.
        gui.Style{
            selectors = {"nae-sub-heading"},
            width = "100%",
            height = "auto",
            fontSize = 16,
            bold = true,
            color = COLORS.GOLD_DIM,
            textAlignment = "left",
            tmargin = 4,
            bmargin = 4,
        },
        -- Thin divider between Icon and VFX groups.
        gui.Style{
            selectors = {"nae-presentation-divider"},
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = COLORS.GOLD .. "66",
            tmargin = 12,
            bmargin = 8,
        },
        -- Horizontal row holding the icon editor swatch + color picker.
        gui.Style{
            selectors = {"nae-icon-row"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            vmargin = 4,
            bgcolor = "clear",
        },
        -- Slider row: label left, slider right, on a single line.
        gui.Style{
            selectors = {"nae-slider-row"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            vmargin = 4,
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"nae-slider-label"},
            width = 90,
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            valign = "center",
        },
        -- Theme the slider track/handle to the gold palette. Priority 3
        -- to override engine defaults (Styles.lua:313).
        gui.Style{
            selectors = {"sliderHandleBorder"},
            priority = 3,
            borderColor = COLORS.GOLD,
            bgcolor = COLORS.PANEL_BG,
        },
        gui.Style{
            selectors = {"sliderHandleInner"},
            priority = 3,
            bgcolor = COLORS.GOLD_BRIGHT,
        },
        gui.Style{
            selectors = {"slider"},
            priority = 3,
            height = 28,
        },
        -- The slider's editable value label (e.g. "100%"). Override
        -- fontSize at priority 3 so it matches body text regardless
        -- of any inherited or CharacterSheet-scoped sliderLabel style.
        gui.Style{
            selectors = {"sliderLabel"},
            priority = 3,
            fontSize = 14,
            color = COLORS.CREAM_BRIGHT,
        },
    }
end

--[[
    ============================================================================
    Shared widget styles (exported)
    ============================================================================
    A subset of _editorStyles() covering the generic DMHub widget selectors
    (formPanel, dropdown, input, button, checkbox, delete-item-button,
    sliderLabel) plus their Styles.Form dependency. Palette-parameterized via
    the optional `colors` argument (defaults to this module's COLORS table).

    Intended for other Draw Steel editor surfaces -- feature panel, modifier
    picker, future compendium editors -- so they inherit the same gold/cream
    chrome without duplicating the rule list. Call and splice into your
    panel's `styles = {...}` array.

    Returns a fresh table on each call so callers can safely mutate or append.
]]
local function _sharedWidgetStyles(colors)
    local c = colors or COLORS
    return {
        -- SourceReference:Editor and other shared utilities rely on the base
        -- Styles.Form class pack. Include it before overriding its descendants.
        Styles.Form,
        -- Left-anchor Styles.Form descendants (base pack right-aligns them).
        gui.Style{ selectors = {"formPanel"}, width = "auto", halign = "left", priority = 5 },
        gui.Style{ selectors = {"formLabel"}, halign = "left", minWidth = 0, priority = 5 },
        gui.Style{ selectors = {"formDropdown"}, halign = "left", priority = 5 },
        gui.Style{ selectors = {"formInput"}, halign = "left", priority = 5 },
        gui.Style{ selectors = {"formValue"}, halign = "left", priority = 5 },
        -- Dropdown skin. halign = "left" catches standalone dropdowns
        -- (e.g. Modify Abilities' "Add Attribute", KeywordSelector's
        -- "Add Keyword") that sit as direct children of vertical-flow
        -- content panels. Without it they have width < 100% and no
        -- halign hint, so the engine centers them. Dropdowns inside
        -- formPanel (horizontal flow) aren't affected by halign in the
        -- same way, so this doesn't break multi-input rows like Modify
        -- Power Roll's Replace in Table.
        gui.Style{
            selectors = {"dropdown"},
            priority = 3,
            halign = "left",
            bgcolor = c.PANEL_BG,
            borderWidth = 1,
            borderColor = c.GOLD,
            cornerRadius = 2,
            hpad = 6,
            vpad = 2,
            borderBox = true,
            fontFace = "Berling",
            fontSize = 14,
            color = c.CREAM_BRIGHT,
            textAlignment = "left",
        },
        gui.Style{
            selectors = {"dropdown", "hover"},
            priority = 4,
            borderColor = c.GOLD_DIM,
            bgcolor = c.PANEL_BG,
        },
        gui.Style{
            selectors = {"dropdownLabel", "parent:hover"},
            priority = 4,
            color = c.CREAM_BRIGHT,
        },
        gui.Style{
            selectors = {"dropdownTriangle", "parent:hover"},
            priority = 4,
            bgcolor = c.GOLD,
        },
        gui.Style{
            selectors = {"dropdown", "open"},
            priority = 3,
            borderColor = c.CREAM_BRIGHT,
            color = c.CREAM_BRIGHT,
        },
        gui.Style{
            selectors = {"dropdown-list"},
            priority = 3,
            bgcolor = c.PANEL_BG,
            borderWidth = 1,
            borderColor = c.GOLD,
            cornerRadius = 2,
        },
        gui.Style{
            selectors = {"dropdown-item"},
            priority = 3,
            bgcolor = "clear",
            color = c.CREAM_BRIGHT,
            fontFace = "Berling",
            fontSize = 14,
            hpad = 6,
            vpad = 2,
        },
        gui.Style{
            selectors = {"dropdown-item", "hover"},
            priority = 4,
            bgcolor = c.GOLD,
            color = c.BG,
        },
        -- Input skin.
        gui.Style{
            selectors = {"input"},
            priority = 3,
            bgcolor = c.PANEL_BG,
            borderWidth = 1,
            borderColor = c.GOLD,
            cornerRadius = 2,
            hpad = 6,
            vpad = 2,
            borderBox = true,
            fontFace = "Berling",
            fontSize = 14,
            color = c.CREAM_BRIGHT,
            textAlignment = "left",
        },
        gui.Style{ selectors = {"input", "hover"}, priority = 3, borderColor = c.GOLD_DIM },
        gui.Style{ selectors = {"input", "focus"}, priority = 3, borderColor = c.CREAM_BRIGHT },
        -- Button skin.
        gui.Style{
            selectors = {"button"},
            priority = 3,
            width = "auto",
            height = "auto",
            minWidth = 72,
            minHeight = 26,
            hpad = 12,
            vpad = 4,
            hmargin = 4,
            vmargin = 2,
            borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = c.PANEL_BG,
            borderWidth = 1,
            borderColor = c.GOLD,
            cornerRadius = 3,
            fontSize = 14,
            fontWeight = "bold",
            color = c.CREAM_BRIGHT,
            textAlignment = "center",
        },
        gui.Style{
            selectors = {"button", "hover"},
            priority = 3,
            bgcolor = c.GOLD_DIM,
            borderColor = c.CREAM_BRIGHT,
            color = c.BG,
            transitionTime = 0.1,
        },
        gui.Style{
            selectors = {"button", "press"},
            priority = 3,
            bgcolor = c.GOLD,
            color = c.BG,
            brightness = 0.85,
        },
        gui.Style{
            selectors = {"button", "disabled"},
            priority = 3,
            bgcolor = c.PANEL_BG,
            borderColor = c.GRAY,
            color = c.GRAY,
        },
        -- Checkbox skin (engine default is height 30 / 18pt, too tall for body text).
        gui.Style{
            selectors = {"checkbox"},
            priority = 3,
            height = 24,
            width = "auto",
            halign = "left",
            valign = "center",
        },
        gui.Style{
            selectors = {"checkbox-label"},
            priority = 3,
            fontSize = 14,
            color = c.CREAM_BRIGHT,
            halign = "left",
            valign = "center",
            bold = true,
        },
        gui.Style{
            selectors = {"check-background"},
            priority = 3,
            borderColor = c.GOLD,
            borderWidth = 1,
            bgcolor = c.PANEL_BG,
        },
        gui.Style{ selectors = {"check-mark"}, priority = 3, bgcolor = c.GOLD_BRIGHT },
        -- delete-item-button uses priority 10 internal styles, so beat at 11.
        gui.Style{ selectors = {"delete-item-button"}, priority = 11, bgcolor = c.CREAM },
        gui.Style{ selectors = {"delete-item-button", "hover"}, priority = 11, bgcolor = "#ff4444" },
        -- Slider label.
        gui.Style{
            selectors = {"sliderLabel"},
            priority = 3,
            fontSize = 14,
            color = c.CREAM_BRIGHT,
        },
    }
end

AbilityEditor.GetSharedWidgetStyles = _sharedWidgetStyles

--[[
    ============================================================================
    Shared form styles (exported)
    ============================================================================
    Mirrors _sharedWidgetStyles() but carries the stacked-label form row
    pattern (label above, control below) plus the field-label typography. Call
    this alongside GetSharedWidgetStyles in any editor that wants the DS
    form standard in one helper.

    Adopters use `classes = {"ds-field-row"}` for a row and
    `classes = {"ds-field-label"}` for its label. The inline variant
    ("ds-field-row-inline" + "ds-field-label-inline") reserves for compact
    fields like 3-digit numbers where stacking wastes vertical space.

    The "ds-" prefix is deliberate: we want a DS-wide name that's unambiguous
    in contexts (like the feature panel) where older "formPanel"/"formLabel"
    classes may still be in play.
]]
local function _sharedFormStyles(colors)
    local c = colors or COLORS
    return {
        gui.Style{
            selectors = {"ds-field-row"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            vmargin = 8,
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"ds-field-label"},
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = c.CREAM_BRIGHT,
            textAlignment = "left",
            bmargin = 4,
        },
        -- Inline rows: width = "auto" so the row shrinks to label + widget
        -- and anchors left. Using "100%" (the ability editor's
        -- nae-field-row-inline convention) produces a huge gap in wider
        -- containers like the feature panel's 900px content column
        -- because children with their own halign float to opposite ends
        -- of the wide row instead of packing tight.
        gui.Style{
            selectors = {"ds-field-row-inline"},
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            vmargin = 8,
            bgcolor = "clear",
        },
        gui.Style{
            selectors = {"ds-field-label-inline"},
            width = "auto",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = c.CREAM_BRIGHT,
            textAlignment = "left",
            valign = "center",
            rmargin = 10,
        },
        -- Field-level input/textarea/dropdown classes: match the ability
        -- editor's nae-field-* widths so labels and controls read as the
        -- same component family across editors.
        gui.Style{
            selectors = {"ds-field-input"},
            priority = 4,
            width = "100%",
            height = 28,
            halign = "left",
            hpad = 6,
            vpad = 2,
            borderBox = true,
            fontSize = 14,
            textAlignment = "left",
        },
        -- Compact variant for short single-line fields (Name / Source).
        -- Narrower than the full-width ds-field-input so the row doesn't
        -- span the whole popup for a 20-char value.
        gui.Style{
            selectors = {"ds-field-input", "ds-field-input-compact"},
            priority = 5,
            width = 420,
        },
        gui.Style{
            selectors = {"ds-field-textarea"},
            priority = 4,
            width = "100%",
            height = "auto",
            minHeight = 60,
            halign = "left",
            hpad = 6,
            vpad = 4,
            borderBox = true,
            fontSize = 14,
            textAlignment = "topleft",
        },
        gui.Style{
            selectors = {"ds-field-dropdown"},
            priority = 4,
            width = 280,
            height = 30,
            halign = "left",
            fontSize = 14,
        },
        gui.Style{
            selectors = {"ds-field-hint"},
            width = "100%",
            height = "auto",
            fontSize = 12,
            italics = true,
            color = c.GRAY,
            textAlignment = "left",
            tmargin = 2,
        },
    }
end

AbilityEditor.GetSharedFormStyles = _sharedFormStyles

--[[
    ============================================================================
    Themed dialog styles (exported)
    ============================================================================
    The "themed dialog" is the complete DS chrome pack: gold/cream palette
    outer frame, widget skin, form row pattern, compact nested-editor chrome.
    Splice it into the OUTERMOST dialog panel's `styles = {...}` list and
    every descendant inherits the theme -- no per-panel theming needed.

    Why this exists vs. combining GetSharedWidgetStyles + GetSharedFormStyles
    inline at each call site: the frame itself (framedPanel + prettyButton)
    and the compact sizing for nested editors (modifierEditorPanel,
    descendant formPanel/formLabel) were duplicated across call sites, and
    the framedPanel had a subtle bug -- base Styles.Panel applies
    dialogGradient (near-black) which can't be cleared by `gradient = nil`
    in a Lua style table (nil-valued keys are absent, so the base rule
    wins). This helper overrides with a flat gradient in our palette, so
    the frame's surface is truly c.BG top-to-bottom.
]]
local function _themedDialogStyles(colors)
    local c = colors or COLORS
    local styles = {}

    -- Compose widget + form packs first.
    for _, rule in ipairs(_sharedWidgetStyles(c)) do
        styles[#styles+1] = rule
    end
    for _, rule in ipairs(_sharedFormStyles(c)) do
        styles[#styles+1] = rule
    end

    -- Flat white gradient. The engine MULTIPLIES bgcolor by the gradient's
    -- color at each pixel. Base Styles.Panel's framedPanel rule sets
    -- gradient to dialogGradient (near-black #000000 -> #060606); any
    -- bgcolor multiplied by that produces near-black. Supplying a flat
    -- white gradient lets bgcolor paint as-is (bgcolor * white = bgcolor).
    local flatGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 1},
        stops = {
            {position = 0, color = "#ffffff"},
            {position = 1, color = "#ffffff"},
        },
    }

    -- Outer frame.
    styles[#styles+1] = gui.Style{
        selectors = {"framedPanel"},
        priority = 3,
        bgimage = "panels/square.png",
        bgcolor = c.BG,
        borderColor = c.GOLD,
        borderWidth = 2,
        gradient = flatGradient,
    }

    -- PrettyButton (Confirm/Cancel and similar).
    styles[#styles+1] = gui.Style{
        selectors = {"label", "button", "prettyButton"},
        priority = 3,
        bgcolor = c.PANEL_BG,
        bgimage = "panels/square.png",
        color = c.CREAM_BRIGHT,
        borderColor = c.GOLD,
        borderWidth = 2,
        cornerRadius = 4,
        fontFace = "Berling",
        fontSize = 20,
        fontWeight = "bold",
        hmargin = 8,
        vmargin = 8,
        textAlignment = "center",
    }
    styles[#styles+1] = gui.Style{
        selectors = {"label", "button", "prettyButton", "hover"},
        priority = 3,
        bgcolor = c.GOLD_DIM,
        color = c.BG,
        borderColor = c.CREAM_BRIGHT,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"label", "button", "prettyButton", "press"},
        priority = 3,
        bgcolor = c.GOLD,
        color = c.BG,
        brightness = 0.85,
    }

    -- Inner content surface: transparent so the frame's themed surface
    -- shows through uninterrupted. Content-panel keeps its role as the
    -- scroll viewport; callers should wrap their children in a
    -- height="auto" inner panel so rows pack at the top instead of being
    -- distributed across the viewport height. See CharacterFeature's
    -- EditorPanel inner wrapper (pattern copied from the Create New
    -- Ability modal at AbilityEditorTemplates.lua:1436-1453).
    styles[#styles+1] = gui.Style{
        selectors = {"content-panel"},
        priority = 6,
        bgcolor = "clear",
        valign = "top",
        hpad = 16,
        vpad = 12,
        borderBox = true,
    }

    -- Nested modifier / behavior editor panels: themed card chrome.
    -- (Kept for callers that still use the classic modifierEditorPanel
    -- class; new callers should use the nae-behavior-* classes below.)
    styles[#styles+1] = gui.Style{
        selectors = {"modifierEditorPanel"},
        priority = 6,
        bgcolor = c.PANEL_BG,
        borderColor = c.GOLD,
        borderWidth = 1,
        pad = 6,
        vmargin = 6,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"modifierHeadingLabel"},
        priority = 6,
        fontSize = 16,
        bold = true,
        color = c.GOLD_BRIGHT,
        height = "auto",
        bmargin = 4,
    }

    -- Shared nae-behavior-* chrome for modifier / behavior list items.
    -- Mirrors the ability editor's effects section so feature panel
    -- modifiers visually match ability editor behaviors.
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-item"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-header"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = c.PANEL_BG,
        border = {y1 = 0, y2 = 1, x1 = 0, x2 = 0},
        borderColor = c.GOLD,
        hpad = 8,
        vpad = 6,
        borderBox = true,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-summary"},
        width = "auto",
        height = "auto",
        fontSize = 16,
        bold = true,
        color = c.GOLD_BRIGHT,
        halign = "left",
        valign = "center",
        textAlignment = "left",
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-controls"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        bgcolor = "clear",
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-copy-btn"},
        priority = 3,
        width = "auto",
        height = "auto",
        fontSize = 11,
        bold = true,
        color = c.CREAM,
        valign = "center",
        rmargin = 8,
        hpad = 6,
        vpad = 2,
        borderWidth = 1,
        borderColor = c.GOLD,
        cornerRadius = 2,
        bgimage = "panels/square.png",
        bgcolor = c.PANEL_BG,
        borderBox = true,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-copy-btn", "hover"},
        priority = 3,
        bgcolor = c.GOLD_DIM,
        color = c.BG,
        borderColor = c.CREAM_BRIGHT,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-copy-btn", "press"},
        priority = 3,
        bgcolor = c.GOLD,
        color = c.BG,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-arrow"},
        width = 24,
        height = 12,
        valign = "center",
        bgimage = "panels/hud/down-arrow.png",
        bgcolor = c.GOLD_BRIGHT,
        lmargin = 4,
        transitionTime = 0.15,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-arrow", "nae-up"},
        scale = {x = 1, y = -1},
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-arrow", "disabled"},
        bgcolor = c.GRAY,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-arrow", "hover"},
        bgcolor = c.CREAM_BRIGHT,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-arrow", "disabled", "hover"},
        bgcolor = c.GRAY,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-content"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        hpad = 8,
        vpad = 4,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"nae-behavior-divider"},
        width = "100%",
        height = 1,
        bgimage = "panels/square.png",
        bgcolor = c.GOLD .. "66",
        vmargin = 4,
    }

    -- Stacked-label form pattern for modifier sub-editor rows: label on
    -- its own line above the control, matching the outer feature panel's
    -- Name / Source / Description fields. Rows that want multiple inputs
    -- side-by-side (Modify Power Roll's "Replace in Table" / "New Text"
    -- pair, damage-type swaps, etc.) opt in with the `formPanel-inline`
    -- class, which restores the legacy horizontal layout + a fixed-width
    -- label column. Parent-class selectors target the label and widgets
    -- inside inline rows so the opt-in is a single class flip on the
    -- parent -- children don't need to know.
    styles[#styles+1] = gui.Style{
        selectors = {"formPanel"},
        priority = 7,
        flow = "vertical",
        width = "100%",
        height = "auto",
        minHeight = 0,
        halign = "left",
        valign = "top",
        pad = 0,
        vmargin = 8,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"formPanel-inline"},
        priority = 8,
        flow = "horizontal",
        width = "auto",
        halign = "left",
        valign = "center",
        vmargin = 4,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"formLabel"},
        priority = 7,
        width = "100%",
        halign = "left",
        valign = "top",
        fontSize = 14,
        bold = true,
        color = c.CREAM_BRIGHT,
        textAlignment = "left",
        hmargin = 0,   -- base Styles.Form sets hmargin = 8, which indents
                        -- the stacked-mode label text 8px to the right of
                        -- the input frame below. Zero it so the label
                        -- lines up with the input's visible left edge.
        bmargin = 4,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"formLabel", "parent:formPanel-inline"},
        priority = 8,
        width = 140,
        valign = "center",
        bmargin = 0,
    }
    -- formInput is the classic class most modifier sub-editors attach to
    -- their gui.Input. Themed version gets DS chrome + left halign so the
    -- input doesn't center in whatever container the modifier emitted.
    styles[#styles+1] = gui.Style{
        selectors = {"formInput"},
        priority = 7,
        halign = "left",
        bgcolor = c.PANEL_BG,
        borderColor = c.GOLD,
        borderWidth = 1,
        cornerRadius = 2,
        color = c.CREAM_BRIGHT,
        fontSize = 14,
        height = 26,
        hpad = 6,
        vpad = 2,
        borderBox = true,
        textAlignment = "left",
    }

    -- Alignment fix 1: callers of gui.GoblinScriptInput typically pass
    -- `classes = "formInput"`, which brings a 6px hpad on the outer
    -- wrapper Panel. That hpad reserves layout space on the left, so
    -- the inner (visible) Input's frame sits 6px to the right of a
    -- plain gui.Input's frame in the row above, AND the condition-box
    -- edge doesn't line up with the Macro-input-box edge in the same
    -- column. The outer wrapper has no bgimage so its border doesn't
    -- render anyway -- only the hpad has visible effect on layout.
    --
    -- Fix: zero hpad on the outer wrapper (tagged `goblinscript-outer`
    -- from the widget itself in DMHub Core Panels/GoblinScriptEditor.lua)
    -- so the inner Input sits flush-left with plain Inputs. Leave the
    -- inner `goblinscript-inner-input` alone so it keeps its default
    -- 6px hpad -- that's the gap between the visible box border and
    -- the editable text, matching what plain Inputs show.
    styles[#styles+1] = gui.Style{
        selectors = {"goblinscript-outer"},
        priority = 8,
        hpad = 0,
    }

    -- Alignment fix 2: the engine base pack gives dropdownLabel a
    -- built-in 6px hmargin + fontSize 18 (DMHub Titlescreen/Styles.lua:284).
    -- Inside a themed dialog the dropdown's chosen-text then sits 6px
    -- right of the input text below it, and renders visibly larger.
    -- Align with input body by zeroing the hmargin and dropping the
    -- fontSize to match formInput's 14.
    styles[#styles+1] = gui.Style{
        selectors = {"dropdownLabel"},
        priority = 8,
        hmargin = 0,
        fontSize = 14,
        fontFace = "Berling",
        color = c.CREAM_BRIGHT,
    }

    -- gui.Table theming. The engine's Styles.Table pack paints rows in
    -- neutral grays (#222 / #444) and white labels -- jarring inside the
    -- DS gold/cream frame. Override at priority 8 so the theme wins
    -- wherever `Styles.Table` is spliced alongside these styles. Applies
    -- to every gui.Table rendered under a themed dialog (power roll tier
    -- table, rollable tables, etc.). Row bg alternates between PANEL_BG
    -- and a slightly-lighter offset to keep the stripe subtle; a thin
    -- gold hairline separates rows. Labels pick up CREAM_BRIGHT; inputs
    -- nested in rows still use the formInput theming.
    styles[#styles+1] = gui.Style{
        selectors = {"row"},
        priority = 8,
        width = "auto",
        height = "auto",
        bgimage = "panels/square.png",
        border = {y1 = 0, y2 = 1, x1 = 0, x2 = 0},
        borderColor = c.GOLD .. "55",
    }
    styles[#styles+1] = gui.Style{
        selectors = {"row", "oddRow"},
        priority = 8,
        bgcolor = c.PANEL_BG,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"row", "evenRow"},
        priority = 8,
        bgcolor = c.BG,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"row", "highlight"},
        priority = 8,
        bgcolor = c.GOLD_DIM,
    }
    styles[#styles+1] = gui.Style{
        selectors = {"row", "label"},
        priority = 8,
        pad = 8,
        fontSize = 16,
        color = c.CREAM_BRIGHT,
        width = "auto",
        height = "auto",
    }

    return styles
end

AbilityEditor.GetThemedDialogStyles = _themedDialogStyles

--[[
    ============================================================================
    Themed confirmation dialog (exported)
    ============================================================================
    Drop-in replacement for gui.ModalMessage when the caller wants the DS
    gold-on-dark chrome instead of the engine-wide default. Used by the
    feature panel's modifier delete flow so the confirm dialog matches
    the surrounding editor. The engine-wide ModalMessage is deliberately
    not themed -- it's used by ~20+ unrelated panels and changing its
    style risks regressions outside this PR's scope.

    options:
      title        string   Heading displayed at the top.
      message      string   Body message.
      confirmText  string   Label for the confirm button (default "Confirm").
      cancelText   string   Label for the cancel button  (default "Cancel").
      onConfirm    function Fired when confirm is pressed.
      onCancel     function Fired when cancel is pressed (optional).
      colors       table    Palette override (defaults to AbilityEditor.COLORS).
]]
function AbilityEditor.ShowThemedConfirm(options)
    local c = options.colors or COLORS
    local title = options.title or "Confirm"
    local message = options.message or ""
    local confirmText = options.confirmText or "Confirm"
    local cancelText = options.cancelText or "Cancel"

    local flatWhiteGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 1},
        stops = {
            {position = 0, color = "#ffffff"},
            {position = 1, color = "#ffffff"},
        },
    }

    local dialogPanel
    local function close()
        if dialogPanel ~= nil and dialogPanel.valid then
            gui.CloseModal()
        end
    end

    local dialogStyles = {Styles.Panel, Styles.Default}
    for _, rule in ipairs(_themedDialogStyles(c)) do
        dialogStyles[#dialogStyles+1] = rule
    end

    dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        floating = true,
        flow = "vertical",
        width = 480,
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = c.BG,
        gradient = flatWhiteGradient,
        borderWidth = 2,
        borderColor = c.GOLD,
        cornerRadius = 6,
        hpad = 24,
        vpad = 20,
        borderBox = true,
        styles = dialogStyles,

        children = {
            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 18,
                bold = true,
                color = c.GOLD_BRIGHT,
                textAlignment = "left",
                bmargin = 12,
                text = title,
            },
            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 14,
                color = c.CREAM_BRIGHT,
                textAlignment = "left",
                bmargin = 20,
                text = message,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",

                gui.Button{
                    text = cancelText,
                    fontSize = 14,
                    width = 120,
                    height = 32,
                    rmargin = 8,
                    escapeActivates = true,
                    escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                    click = function()
                        close()
                        if options.onCancel ~= nil then options.onCancel() end
                    end,
                },
                gui.Button{
                    text = confirmText,
                    fontSize = 14,
                    width = 120,
                    height = 32,
                    click = function()
                        close()
                        if options.onConfirm ~= nil then options.onConfirm() end
                    end,
                },
            },
        },
    }

    gui.ShowModal(dialogPanel)
end

--[[
    ============================================================================
    Nav button factory
    ============================================================================
    A nav button's visual state is driven entirely by its "selected" class,
    which the root panel flips in the nav.selectSection callback. No rebuild
    on click per UI_BEST_PRACTICES (panels toggle state rather than re-create).
]]
local function _makeNavButton(sectionDef, onSelect)
    return gui.Label{
        classes = {"nae-nav-button"},
        id = "nav_" .. sectionDef.id,
        text = sectionDef.label,
        data = {
            sectionId = sectionDef.id,
        },
        click = function(element)
            onSelect(sectionDef.id)
        end,
    }
end

--[[
    ============================================================================
    Overview section
    ============================================================================
    Mirrors the field set scattered across the classic editor's left+right
    columns that players perceive as "identity" info. Keeping them together
    here aligns with the user's mental model ("what is this ability called,
    what category is it, what does the tooltip say"). Behaviors and costs
    live in their own sections.

    Every change handler fires `refreshAbility` (for conditional siblings
    like the Villain Action dropdown) and `refreshPreview` (so the right
    column's tooltip card reflects the edit live).
]]
local function _makeFieldRow(labelText, childElement)
    return gui.Panel{
        classes = {"nae-field-row"},
        children = {
            gui.Label{
                classes = {"nae-field-label"},
                text = labelText,
            },
            childElement,
        },
    }
end

local function _buildOverviewSection(ability, fireChange)
    local children = {}

    -- Name
    children[#children + 1] = _makeFieldRow("Name",
        gui.Input{
            classes = {"nae-field-input"},
            text = ability.name or "",
            change = function(element)
                ability.name = element.text
                fireChange()
            end,
        }
    )

    -- Category (DS has categorization like Heroic Ability / Villain Action / etc.)
    if GameSystem.hasAbilityCategorization then
        local categoryOptions = {}
        for category, _ in pairs(GameSystem.abilityCategories) do
            categoryOptions[#categoryOptions + 1] = {
                id = category,
                text = category,
            }
        end

        children[#children + 1] = _makeFieldRow("Category",
            gui.Dropdown{
                classes = {"nae-field-dropdown"},
                idChosen = ability.categorization,
                options = categoryOptions,
                sort = true,
                change = function(element)
                    ability.categorization = element.idChosen
                    fireChange()
                end,
            }
        )

        -- Villain Action sub-dropdown. Only shown when category is "Villain
        -- Action". Using `collapsed-anim` so it slides when the category
        -- changes rather than rebuilding.
        children[#children + 1] = gui.Panel{
            classes = {"nae-field-row",
                       cond(ability:try_get("categorization") == "Villain Action", nil, "collapsed-anim")},
            refreshAbility = function(element)
                element:SetClass("collapsed-anim", ability:try_get("categorization") ~= "Villain Action")
            end,
            children = {
                gui.Label{
                    classes = {"nae-field-label"},
                    text = "Villain Action",
                },
                gui.Dropdown{
                    classes = {"nae-field-dropdown"},
                    idChosen = ability:try_get("villainAction", "none"),
                    options = {
                        { id = "none", text = "None" },
                        { id = "Villain Action 1", text = "Villain Action 1" },
                        { id = "Villain Action 2", text = "Villain Action 2" },
                        { id = "Villain Action 3", text = "Villain Action 3" },
                    },
                    change = function(element)
                        ability.villainAction = element.idChosen
                        fireChange()
                    end,
                },
            },
        }
    end

    -- Keywords chip list + add dropdown.
    if GameSystem.hasAbilityKeywords then
        local keywordRow
        keywordRow = gui.Panel{
            classes = {"nae-field-row"},
            -- Rebuild chips on keyword change. We can't use the same element
            -- to also host the add-dropdown (the add dropdown itself fires
            -- change, which needs to clear its idChosen), so keep them as
            -- sibling panels.
            children = {
                gui.Label{
                    classes = {"nae-field-label"},
                    text = "Keywords",
                },
                -- Chip list -- re-renders from ability.keywords on refresh.
                gui.Panel{
                    id = "keywordChips",
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    wrap = true,
                    halign = "left",
                    valign = "top",
                    bmargin = 4,
                    bgcolor = "clear",
                    create = function(element)
                        element:FireEvent("refreshKeywords")
                    end,
                    refreshKeywords = function(element)
                        local chips = {}
                        local sortedKeys = {}
                        for keyword, _ in pairs(ability.keywords or {}) do
                            sortedKeys[#sortedKeys + 1] = keyword
                        end
                        table.sort(sortedKeys)

                        for _, keyword in ipairs(sortedKeys) do
                            local k = keyword
                            chips[#chips + 1] = gui.Panel{
                                classes = {"nae-keyword-chip"},
                                children = {
                                    gui.Label{
                                        classes = {"nae-keyword-chip-label"},
                                        text = ActivatedAbility.CanonicalKeyword(k),
                                    },
                                    gui.DeleteItemButton{
                                        width = 14,
                                        height = 14,
                                        halign = "right",
                                        valign = "center",
                                        click = function()
                                            ability:RemoveKeyword(k)
                                            fireChange()
                                        end,
                                    },
                                },
                            }
                        end

                        element.children = chips
                    end,
                },
                -- Add-keyword dropdown. Rebuilds its option list whenever
                -- keywords change so already-added entries disappear.
                gui.Dropdown{
                    id = "keywordAdd",
                    classes = {"nae-field-dropdown"},
                    sort = true,
                    hasSearch = true,
                    textOverride = "Add Keyword...",
                    idChosen = "none",
                    create = function(element)
                        local options = {}
                        for keyword, _ in pairs(GameSystem.abilityKeywords) do
                            if not ability.keywords[keyword] then
                                options[#options + 1] = {
                                    id = keyword,
                                    text = keyword,
                                }
                            end
                        end
                        element.options = options
                        element:SetClass("collapsed", #options == 0)
                    end,
                    refreshKeywords = function(element)
                        element:FireEvent("create")
                    end,
                    change = function(element)
                        if element.idChosen ~= "none" then
                            ability:AddKeyword(element.idChosen)
                            element.idChosen = "none"
                            fireChange()
                        end
                    end,
                },
            },
        }
        children[#children + 1] = keywordRow
    end

    -- Flavor Text
    children[#children + 1] = _makeFieldRow("Flavor Text",
        gui.Input{
            classes = {"nae-field-textarea"},
            placeholderText = "Italicized narrative (not mechanics)...",
            multiline = true,
            characterLimit = 2000,
            text = ability:try_get("flavor", ""),
            change = function(element)
                ability.flavor = element.text
                fireChange()
            end,
        }
    )

    -- Effect Before Power Roll (preDescription)
    children[#children + 1] = _makeFieldRow("Effect Before Power Roll",
        gui.Input{
            classes = {"nae-field-textarea"},
            placeholderText = "Effect text shown before the power roll tiers...",
            multiline = true,
            characterLimit = 2000,
            text = ability:try_get("preDescription", ""),
            change = function(element)
                ability.preDescription = element.text
                fireChange()
            end,
        }
    )

    -- Effect After Power Roll (description)
    children[#children + 1] = _makeFieldRow("Effect After Power Roll",
        gui.Input{
            classes = {"nae-field-textarea"},
            placeholderText = "Effect text shown after the power roll tiers...",
            multiline = true,
            characterLimit = 2000,
            text = ability:try_get("description", ""),
            change = function(element)
                ability.description = element.text
                fireChange()
            end,
        }
    )

    -- Implementation status (0/1/2 traffic-light widget). Inline layout:
    -- the 148x32 widget is compact enough to sit to the right of its
    -- label on a single row, keeping the vertical space tight.
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row-inline"},
        children = {
            gui.Label{
                classes = {"nae-field-label-inline"},
                text = "Implementation Status",
            },
            gui.ImplementationStatusPanel{
                halign = "left",
                valign = "center",
                value = ability:try_get("implementation", 1),
                change = function(element)
                    ability.implementation = element.value
                    fireChange()
                end,
                -- The base ImplementationStatusPanel has mismatched arrow
                -- heights (left=24, right=32). Fix the right arrow to 24
                -- after construction by walking children.
                create = function(element)
                    for _, child in ipairs(element.children) do
                        if child.height == 32 then
                            child.height = 24
                        end
                    end
                end,
            },
        },
    }

    -- Implementation details: only relevant when status != 1 (fully
    -- implemented). Collapse animation so toggling status hides it smoothly.
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(ability:try_get("implementation", 1) == 1, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", ability:try_get("implementation", 1) == 1)
        end,
        refreshImplementation = function(element)
            element:SetClass("collapsed-anim", ability:try_get("implementation", 1) == 1)
        end,
        children = {
            gui.Label{
                classes = {"nae-field-label"},
                text = "Implementation Notes",
            },
            gui.Input{
                classes = {"nae-field-textarea"},
                placeholderText = "Notes on unfinished parts...",
                multiline = true,
                characterLimit = 2048,
                text = ability:try_get("implementationDetails", ""),
                change = function(element)
                    ability.implementationDetails = element.text
                    fireChange()
                end,
            },
        },
    }

    -- Source Reference. SourceReference:Editor already emits its own
    -- "Source:" label + Page sub-row inside a self-contained panel, so we
    -- drop it in as a bare field row without an outer label to avoid
    -- duplicating the heading. We still wrap in a nae-field-row so the
    -- margins line up with the rest of the form.
    local m_source = ability:try_get("sourceReference") or SourceReference.new{}
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row"},
        children = {
            m_source:Editor{
                object = ability,
                width = "100%",
                height = "auto",
                change = function(element)
                    ability.sourceReference = m_source
                    fireChange()
                end,
            },
        },
    }

    -- Display Order -- numeric, governs ability-list sort order. The input
    -- sits inline with its label (horizontal row); stacking label-above for
    -- a 3-digit integer wastes vertical space and looks odd next to the
    -- Source row above it.
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row-inline"},
        children = {
            gui.Label{
                classes = {"nae-field-label-inline"},
                text = "Display Order (lower shows first)",
            },
            gui.Input{
                classes = {"nae-field-input"},
                width = 80,
                height = 28,
                halign = "left",
                valign = "center",
                text = tostring(ability:try_get("displayOrder", 0)),
                change = function(element)
                    if tonumber(element.text) ~= nil then
                        ability.displayOrder = tonumber(element.text)
                    end
                    element.text = tostring(ability:try_get("displayOrder", 0))
                    fireChange()
                end,
            },
        },
    }

    --------------------------------------------------------------------------
    -- Modes & Variations
    --------------------------------------------------------------------------
    local modesListPanel = nil

    children[#children + 1] = _makeFieldRow("Modes",
        gui.Dropdown{
            classes = {"nae-field-dropdown"},
            idChosen = ability:try_get("multipleModes", false),
            options = {
                {id = false,        text = "No Modes"},
                {id = true,         text = "Multiple Modes"},
                {id = "variations", text = "Ability Variations"},
            },
            change = function(element)
                ability.multipleModes = element.idChosen
                if ability.multipleModes and ability:try_get("modeList") == nil then
                    ability.modeList = {}
                end
                fireChange()
                if modesListPanel ~= nil then
                    modesListPanel:FireEventTree("refreshModes")
                end
            end,
        }
    )

    -- Mode list (visible only when multipleModes is truthy)
    modesListPanel = gui.Panel{
        classes = {"nae-field-subgroup",
                   cond(ability:try_get("multipleModes"), nil, "collapsed-anim")},
        flow = "vertical",
        width = "100%",
        height = "auto",

        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not ability:try_get("multipleModes"))
        end,

        refreshModes = function(element)
            if ability:try_get("modeList") == nil then return end

            local modeChildren = {}

            -- Help text
            modeChildren[#modeChildren + 1] = gui.Label{
                classes = {"nae-field-hint"},
                text = "Behaviors in Effects can be assigned to specific modes.",
                bmargin = 8,
            }

            -- Existing mode entries
            for i, modeEntry in ipairs(ability.modeList) do
                local idx = i
                local entry = modeEntry

                -- Mode name + delete
                modeChildren[#modeChildren + 1] = gui.Panel{
                    classes = {"nae-field-row"},
                    children = {
                        gui.Label{
                            classes = {"nae-field-label"},
                            text = string.format("Mode %d", idx),
                        },
                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            halign = "left",
                            valign = "center",
                            bgcolor = "clear",
                            children = {
                                gui.Input{
                                    classes = {"nae-field-input"},
                                    width = "100%-24",
                                    text = entry.text or "",
                                    change = function(el)
                                        entry.text = el.text
                                        fireChange()
                                    end,
                                },
                                gui.DeleteItemButton{
                                    width = 14,
                                    height = 14,
                                    halign = "right",
                                    valign = "center",
                                    lmargin = 6,
                                    click = function()
                                        table.remove(ability.modeList, idx)
                                        fireChange()
                                        modesListPanel:FireEventTree("refreshModes")
                                    end,
                                },
                            },
                        },
                    },
                }

                -- Mode Details (rules text)
                modeChildren[#modeChildren + 1] = gui.Panel{
                    classes = {"nae-field-row"},
                    children = {
                        gui.Label{
                            classes = {"nae-field-label"},
                            text = "Mode Details",
                        },
                        gui.Input{
                            classes = {"nae-field-textarea"},
                            minHeight = 30,
                            characterLimit = 300,
                            placeholderText = "Enter rules details...",
                            multiline = true,
                            text = entry.rules or "",
                            change = function(el)
                                entry.rules = el.text
                                fireChange()
                            end,
                        },
                    },
                }

                -- Mode Condition (GoblinScript) -- width must be numeric
                -- for gui.GoblinScriptInput (it does width - 40 internally).
                modeChildren[#modeChildren + 1] = _makeFieldRow("Mode Condition",
                    gui.GoblinScriptInput{
                        classes = {"nae-field-input"},
                        width = 280,
                        value = entry.condition or "",
                        change = function(el)
                            entry.condition = el.value
                            fireChange()
                        end,
                        documentation = {
                            domains = ability:try_get("domains"),
                            help = "GoblinScript to determine whether this mode is available.",
                            output = "boolean",
                            examples = {
                                {
                                    script = "hitpoints >= Max Hitpoints / 2",
                                    text = "Available only if HP is above half.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature using the ability.",
                            symbols = {
                                subject = {
                                    name = "Subject",
                                    type = "creature",
                                    desc = "The creature using the ability.",
                                },
                            },
                        },
                    }
                )

                -- "Has Ability" checkbox + Edit button (variations only)
                modeChildren[#modeChildren + 1] = gui.Panel{
                    classes = {"nae-field-row",
                               cond(ability:try_get("multipleModes") == "variations", nil, "collapsed-anim")},
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",

                    refreshAbility = function(el)
                        el:SetClass("collapsed-anim", ability:try_get("multipleModes") ~= "variations")
                    end,

                    children = {
                        gui.Check{
                            classes = {"nae-toggle-check"},
                            text = "Has Ability",
                            value = entry.hasAbility or false,
                            change = function(el)
                                entry.hasAbility = el.value
                                fireChange()
                                modesListPanel:FireEventTree("refreshModes")
                            end,
                        },
                        gui.Button{
                            classes = {cond(entry.hasAbility, nil, "collapsed")},
                            text = "Edit Ability",
                            lmargin = 8,
                            refreshModes = function(el)
                                el:SetClass("collapsed", not entry.hasAbility)
                            end,
                            click = function(el)
                                if entry.variation == nil then
                                    entry.variation = ActivatedAbility.Create{
                                        name = ability.name,
                                        categorization = ability:try_get("categorization"),
                                        iconid = ability:try_get("iconid"),
                                        description = entry.rules,
                                        domains = ability:try_get("domains"),
                                    }
                                end
                                el.root:AddChild(
                                    entry.variation:ShowEditActivatedAbilityDialog{})
                            end,
                        },
                    },
                }

                -- Divider between modes
                if i < #ability.modeList then
                    modeChildren[#modeChildren + 1] = gui.Panel{
                        classes = {"nae-behavior-divider"},
                    }
                end
            end

            -- "New Mode" input
            modeChildren[#modeChildren + 1] = _makeFieldRow("New Mode",
                gui.Input{
                    classes = {"nae-field-input"},
                    text = "",
                    placeholderText = "Enter new mode name...",
                    change = function(el)
                        if el.text ~= "" then
                            ability.modeList[#ability.modeList + 1] = {
                                text = el.text,
                            }
                            el.text = ""
                            fireChange()
                            modesListPanel:FireEventTree("refreshModes")
                        end
                    end,
                }
            )

            element.children = modeChildren
        end,

        create = function(element)
            element:FireEvent("refreshModes")
        end,
    }
    children[#children + 1] = modesListPanel

    -- Bottom padding so the last field doesn't sit flush against the panel edge.
    children[#children + 1] = gui.Panel{
        width = "100%", height = 12, bgcolor = "clear",
    }

    return children
end

--[[
    ============================================================================
    Cost & Action section
    ============================================================================
    Gathers the fields that answer "what does this ability cost to use?" --
    Action resource, non-Action resource cost, channeled resources, Strain,
    and Persistence.

    Three fields from the classic editor are intentionally DROPPED here:

    1. Reaction Trigger (reactionInfo.type) -- a 5e holdover. In Draw Steel
       the underlying ActivatedAbilityReaction.types list only contains
       "None" + "Enemy moves out of reach", and the UI row is gated on
       actionResource.isreaction (only Free Triggered Action has it true).
       YAML scan across the whole compendium turns up just 2 orphaned uses
       (Summoner's Melee/Ranged Summoner Strike) and both have Main Action
       selected so the row has never actually been visible to those authors.

    2. Num. Actions (actionNumber) -- also a 5e holdover. Gated on
       actionResource.useQuantity, which no Draw Steel action resource
       has set to true. Zero YAML files set actionNumber anywhere.

    3. Attribute (attributeOverride / attributeOverrideMulti) -- gated at
       the GameSystem level by GameSystem.abilitiesHaveAttribute, which
       Draw Steel sets to false. Every DS ability serialises attributeOverride
       with the default "no_attribute" value; none have a real attribute set.

    We do NOT strip these fields from the ability object on save. If an
    imported ability has stale values they round-trip unchanged; we simply
    don't render controls for them. That keeps the editor non-destructive
    against legacy data.
]]
local function _buildCostAndActionSection(ability, fireChange)
    local children = {}

    -- characterResources is a GetTable-backed table; lookup here so the
    -- useQuantity predicates below are cheap. The table itself is fairly
    -- static at edit time; if a new resource is authored live we'll miss
    -- it until the editor reopens, which is acceptable.
    local resourceTable = dmhub.GetTable("characterResources") or {}

    local function resourceCostHasQuantity()
        local id = ability:try_get("resourceCost", "none")
        local r = resourceTable[id]
        if r == nil then return false end
        return r:try_get("useQuantity", false) == true
    end

    local function channelActive()
        return ability:try_get("channeledResource", "none") ~= "none"
    end

    local function persistenceEnabled()
        return ability:try_get("persistence", {}).enabled == true
    end

    local function persistenceMode()
        return ability:try_get("persistence", {}).mode or "recast"
    end

    -- Non-Action resources for the Resource Cost + Channel Resource
    -- dropdowns. Matches the classic editor's construction in
    -- DMHub Compendium/ActivatedAbilityEditor.lua:67 so that the option
    -- list is identical between editors.
    local resourceOptions = {}
    for k, r in pairs(resourceTable) do
        if r.grouping ~= "Actions" and not r:try_get("hidden", false) then
            resourceOptions[#resourceOptions + 1] = { id = k, text = r.name }
        end
    end
    table.sort(resourceOptions, function(a, b) return a.text < b.text end)
    table.insert(resourceOptions, 1, { id = "none", text = "None" })

    -- 1. Action
    children[#children + 1] = _makeFieldRow("Action",
        gui.Dropdown{
            classes = {"nae-field-dropdown"},
            idChosen = ability:ActionResource() or "none",
            options = CharacterResource.GetActionOptions(),
            change = function(element)
                ability.actionResourceId = element.idChosen
                fireChange()
            end,
        }
    )

    -- 2. Resource Cost
    children[#children + 1] = _makeFieldRow("Resource Cost",
        gui.Dropdown{
            classes = {"nae-field-dropdown"},
            idChosen = ability:try_get("resourceCost", "none"),
            options = resourceOptions,
            change = function(element)
                ability.resourceCost = element.idChosen
                fireChange()
            end,
        }
    )

    -- 3. Num. Resources -- only shown when the selected resource has
    -- useQuantity = true. In Draw Steel that is Malice, Heroic Resource,
    -- Surges, Project Points, and Epic Resource; Recovery + Rampage +
    -- Hero Tokens are single-use flags and hide this row.
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(resourceCostHasQuantity(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not resourceCostHasQuantity())
        end,
        children = {
            gui.Label{
                classes = {"nae-field-label"},
                text = "Num. Resources",
            },
            gui.GoblinScriptInput{
                classes = {"nae-field-input"},
                width = 240,
                halign = "left",
                value = ability:try_get("resourceNumber", "1"),
                change = function(element)
                    ability.resourceNumber = element.value
                    fireChange()
                end,
                documentation = {
                    domains = ability.domains,
                    help = "GoblinScript that determines how many of the selected resource this ability costs. Usually a flat number; can reference the chosen mode or caster symbols.",
                    output = "number",
                    examples = {
                        {
                            script = "3",
                            text = "The ability costs 3 of the selected resource.",
                        },
                        {
                            script = "Mode = 2 then 3 else 1",
                            text = "Mode 2 costs 3 resources, other modes cost 1.",
                        },
                    },
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature using the ability.",
                    symbols = {
                        mode = {
                            name = "Mode",
                            type = "number",
                            desc = "The numeric index of the chosen mode when an ability has multiple modes. Defaults to 1.",
                        },
                    },
                },
            },
        },
    }

    -- 4. Channel Resource
    children[#children + 1] = _makeFieldRow("Channel Resource",
        gui.Dropdown{
            classes = {"nae-field-dropdown"},
            idChosen = ability:try_get("channeledResource", "none"),
            options = resourceOptions,
            change = function(element)
                ability.channeledResource = element.idChosen
                fireChange()
            end,
        }
    )

    -- 5. Channel sub-cluster: Max Channel, Cost per Charge, Channel
    -- Description. All three share the same reveal predicate (channel
    -- resource selected), so they live in a single subgroup container
    -- that collapses as a unit.
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-subgroup",
                   cond(channelActive(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not channelActive())
        end,
        children = {
            -- Max Channel (blank = no limit) lives on its own row so the
            -- GoblinScript formula has room to breathe. Cost per Charge
            -- sits on the following row, flush-left with Max Channel.
            -- Explicit halign = "left" + lmargin = 0 on the row and label
            -- because the class cascade alone lets the row drift a few
            -- pixels right of the other Cost & Action labels; same fix
            -- pattern as the Cost per Charge row below.
            gui.Panel{
                classes = {"nae-field-row-inline"},
                halign = "left",
                lmargin = 0,
                children = {
                    gui.Label{
                        classes = {"nae-field-label-inline"},
                        text = "Max Channel",
                        halign = "left",
                        lmargin = 0,
                    },
                    gui.GoblinScriptInput{
                        classes = {"nae-field-input"},
                        width = 280,
                        height = 28,
                        valign = "center",
                        value = ability:try_get("maxChannel", ""),
                        change = function(element)
                            ability.maxChannel = element.value
                            fireChange()
                        end,
                        documentation = {
                            domains = ability.domains,
                            help = "Maximum amount of the channeled resource that can be committed to this ability. Leave blank for no limit.",
                            output = "number",
                            examples = {
                                {
                                    script = "3",
                                    text = "A maximum of 3 resources can be channeled.",
                                },
                                {
                                    script = "Level",
                                    text = "A number of resources equal to the caster's level.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature using the ability.",
                        },
                    },
                },
            },

            -- Cost per Charge: narrow numeric input on its own inline row,
            -- directly under Max Channel. Note: explicit halign = "left" +
            -- lmargin = 0 on the row and the label, because without them
            -- the row's content drifts ~40px right of the Max Channel
            -- label above (likely an interaction between the narrow
            -- gui.Input and the nae-field-row-inline halign cascade).
            gui.Panel{
                classes = {"nae-field-row-inline"},
                halign = "left",
                lmargin = 0,
                children = {
                    gui.Label{
                        classes = {"nae-field-label-inline"},
                        text = "Cost per Charge",
                        halign = "left",
                        lmargin = 0,
                    },
                    gui.Input{
                        classes = {"nae-field-input"},
                        width = 60,
                        height = 28,
                        valign = "center",
                        characterLimit = 2,
                        text = tostring(ability:try_get("channelIncrement", 1)),
                        change = function(element)
                            local n = tonumber(element.text) or 1
                            ability.channelIncrement = n
                            element.text = tostring(n)
                            fireChange()
                        end,
                    },
                },
            },

            -- Channel Description stays on its own row (full-width text
            -- input benefits from the stacked label-above layout).
            gui.Panel{
                classes = {"nae-field-row"},
                children = {
                    gui.Label{
                        classes = {"nae-field-label"},
                        text = "Channel Description",
                    },
                    gui.Input{
                        classes = {"nae-field-input"},
                        characterLimit = 160,
                        text = ability:try_get("channelDescription", ""),
                        placeholderText = "Describe the channeling...",
                        change = function(element)
                            ability.channelDescription = element.text
                            fireChange()
                        end,
                    },
                },
            },
        },
    }

    -- 6. Strain (bare enable checkbox). When on, each behavior in the
    -- Effects section exposes a strained/unstrained selector (via the
    -- behavior's own editor -- see MCDMActivatedAbility.lua:3090) that
    -- filters the behavior on the caster's current Strained state. The
    -- ability also deep-copies and runs the "Strained During Ability"
    -- standard ability on cast (MCDMActivatedAbility.lua:2707). This row
    -- has no sub-fields; all the authoring happens at the behavior level.
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row-inline"},
        children = {
            gui.Check{
                classes = {"nae-toggle-check"},
                text = "Strain",
                value = ability:try_get("strain", {}).enabled == true,
                change = function(element)
                    local s = ability:get_or_add("strain", {})
                    s.enabled = element.value
                    fireChange()
                end,
            },
        },
    }

    -- 7. Persistence. Top-level enable check + an indented subgroup with
    -- the cost, mode, and mode-conditional options. The Edit Recast
    -- Ability button (recast_new mode only) opens a nested ability
    -- editor via ShowEditActivatedAbilityDialog -- which re-enters
    -- ActivatedAbility:GenerateEditor so the nested editor honors the
    -- same "classicAbilityEditor" setting as the outer one.
    local persistenceSubgroup = gui.Panel{
        classes = {"nae-field-subgroup",
                   cond(persistenceEnabled(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not persistenceEnabled())
        end,
        children = {
            -- Persistent cost per turn
            gui.Panel{
                classes = {"nae-field-row-inline"},
                children = {
                    gui.Label{
                        classes = {"nae-field-label-inline"},
                        text = "Persistent",
                    },
                    gui.Input{
                        classes = {"nae-field-input"},
                        width = 60,
                        height = 28,
                        halign = "left",
                        valign = "center",
                        characterLimit = 2,
                        text = tostring(ability:try_get("persistence", {}).cost or 1),
                        change = function(element)
                            local p = ability:get_or_add("persistence", {})
                            local n = tonumber(element.text) or 1
                            p.cost = n
                            element.text = tostring(n)
                            fireChange()
                        end,
                    },
                },
            },

            -- Mode dropdown (recast / recast_maneuver / recast_target /
            -- recast_with_one_target / recast_new / none). Options come
            -- from the base ActivatedAbility.PersistenceModes global
            -- defined in ActivatedAbilityEditor.lua:1242.
            _makeFieldRow("Behavior",
                gui.Dropdown{
                    classes = {"nae-field-dropdown"},
                    idChosen = persistenceMode(),
                    options = ActivatedAbility.PersistenceModes,
                    change = function(element)
                        local p = ability:get_or_add("persistence", {})
                        p.mode = element.idChosen
                        fireChange()
                    end,
                }
            ),

            -- Target Must Be In Range: only meaningful for recast_target.
            gui.Panel{
                classes = {"nae-field-row-inline",
                           cond(persistenceMode() == "recast_target", nil, "collapsed-anim")},
                refreshAbility = function(element)
                    element:SetClass("collapsed-anim", persistenceMode() ~= "recast_target")
                end,
                children = {
                    gui.Check{
                        classes = {"nae-toggle-check"},
                        text = "Target Must Be In Range",
                        value = ability:try_get("persistence", {}).inrange == true,
                        change = function(element)
                            local p = ability:get_or_add("persistence", {})
                            p.inrange = element.value
                            fireChange()
                        end,
                    },
                },
            },

            -- Edit Recast Ability button: only for recast_new. Lazily
            -- creates the recastNewAbility object on first click, then
            -- opens it in a nested dialog.
            gui.Panel{
                classes = {"nae-field-row-inline",
                           cond(persistenceMode() == "recast_new", nil, "collapsed-anim")},
                refreshAbility = function(element)
                    element:SetClass("collapsed-anim", persistenceMode() ~= "recast_new")
                end,
                children = {
                    gui.Button{
                        text = "Edit Recast Ability",
                        click = function(element)
                            if ability:try_get("recastNewAbility") == nil then
                                ability.recastNewAbility = ActivatedAbility.Create{
                                    name = ability.name,
                                    categorization = ability.categorization,
                                    iconid = ability.iconid,
                                    domains = ability.domains,
                                }
                            end
                            element.root:AddChild(ability.recastNewAbility:ShowEditActivatedAbilityDialog{})
                        end,
                    },
                },
            },
        },
    }

    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row"},
        flow = "vertical",
        children = {
            gui.Check{
                classes = {"nae-toggle-check"},
                text = "Persistence",
                value = persistenceEnabled(),
                change = function(element)
                    local p = ability:get_or_add("persistence", {})
                    p.enabled = element.value
                    fireChange()
                end,
            },
            persistenceSubgroup,
        },
    }

    -- 8. Special Properties. Boolean flags registered via
    -- ActivatedAbility.RegisterProperty (MCDMActivatedAbility.lua:3119).
    -- The classic editor exposes these through a "Add Special Property..."
    -- SetEditor; we render them as stacked nae-toggle-check rows so they
    -- match the section's styling. Iterating registeredProperties means any
    -- future RegisterProperty call shows up automatically without touching
    -- this editor. At time of writing the list is Use as Free Strike,
    -- Use as Signature Ability, and Remain Hidden.
    local propertyChecks = {}
    for _, prop in ipairs(ActivatedAbility.registeredProperties or {}) do
        local propId = prop.id
        propertyChecks[#propertyChecks + 1] = gui.Check{
            classes = {"nae-toggle-check"},
            text = prop.name,
            value = ability:HasProperty(propId),
            change = function(element)
                local props = ability:get_or_add("properties", {})
                if element.value then
                    props[propId] = true
                else
                    props[propId] = nil
                end
                fireChange()
            end,
        }
    end

    if #propertyChecks > 0 then
        children[#children + 1] = gui.Panel{
            classes = {"nae-field-row"},
            flow = "vertical",
            children = {
                gui.Label{
                    classes = {"nae-field-label"},
                    text = "Special Properties",
                },
                gui.Panel{
                    classes = {"nae-field-subgroup"},
                    children = propertyChecks,
                },
            },
        }
    end

    return children
end

--[[
    ============================================================================
    Targeting section  (Step 3 of the vertical slice)
    ============================================================================
    Fields rendered in this section (in order):
      Target Type, Range/Length, Radius/Size/Width, Distance, Can Choose Lower
      Range, Target Count, Allow Duplicate Targeting, Proximity Targeting
      (+ Chain Proximity, Proximity Range), Affects, Can Target Self,
      Cast immediately when clicked, Targeting mode (+ Forced Movement,
      Through Creatures), Object ID, Target Filter, Range Text, Target Text.
    Behind "More options" CollapseArrow:
      Ability Filters (caster-side formula+reason pairs),
      Reasoned Filters (target-side formula+reason pairs).

    Dropped non-destructively (0 compendium usage, not in classic editor UI):
      rangeDisadvantage, rangeUsesInvoker.
]]

-- Shared documentation objects for GoblinScript fields in the Targeting
-- section.  Defined once here so _buildTargetingSection stays readable.
-- Adapted from the classic editor (ActivatedAbilityEditor.lua:2214-2685)
-- with `self` replaced by the `ability` parameter at call-time.

local function _targetFilterDocs(ability)
    return {
        domains = ability.domains,
        help = "This GoblinScript determines whether a creature in the area of effect should be affected. Evaluated once per creature -- true = affected, false = not affected. If blank, all creatures are affected.",
        output = "boolean",
        examples = {
            {
                script = "enemy",
                text = "Affect only creatures that are enemies of the caster.",
            },
            {
                script = "not enemy",
                text = "Affect only creatures that are NOT enemies of the caster (allies + self).",
            },
            {
                script = "Target Number = 2",
                text = "Affect only the second target of the ability.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "A creature in the ability's area of effect.",
        symbols = {
            caster = {
                name = "Caster",
                type = "creature",
                desc = "The creature using this ability.",
            },
            enemy = {
                name = "Enemy",
                type = "boolean",
                desc = "True if the subject is an enemy of the caster.",
            },
            target = {
                name = "Target",
                type = "creature",
                desc = "The target creature (same as the subject).",
            },
            targetnumber = {
                name = "Target Number",
                type = "number",
                desc = "1 for the first target, 2 for the second target, etc.",
            },
            numberoftargets = {
                name = "Number of Targets",
                type = "number",
                desc = "Total number of creatures this ability is targeting.",
            },
        },
    }
end

local function _abilityFilterDocs(ability)
    return {
        domains = ability.domains,
        help = "This GoblinScript determines whether the ability can be used at all. Evaluated against the caster. If the result is false, the reason text is shown to the player.",
        output = "boolean",
        examples = {
            {
                script = "Level >= 5",
                text = "The ability can only be used at level 5 or higher.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature using the ability.",
    }
end

local function _rangeDocs(ability)
    return {
        domains = ability.domains,
        help = "The range of this ability in squares. If left empty the ability has a range of 1 (melee).",
        output = "number",
        examples = {
            {
                script = "10",
                text = "The ability has a range of 10 squares.",
            },
            {
                script = "10 + level*2",
                text = "The ability has a range of 10 squares, plus 2 per caster level.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature using the ability.",
        symbols = table.union({
            ability = {
                name = "Ability",
                type = "ability",
                desc = "The ability being used.",
            },
        }, ActivatedAbility.helpCasting),
    }
end

local function _radiusDocs(ability)
    return {
        domains = ability.domains,
        help = "The radius (or size/width for other shapes) of this ability's area of effect, in squares.",
        output = "number",
        examples = {
            {
                script = "3",
                text = "A 3-square radius/size.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature using the ability.",
        symbols = table.union({
            ability = {
                name = "Ability",
                type = "ability",
                desc = "The ability being used.",
            },
        }, ActivatedAbility.helpCasting),
    }
end

local function _lineDistanceDocs(ability)
    return {
        domains = ability.domains,
        help = "The number of squares away from the caster that this line can start.",
        output = "number",
        examples = {
            {
                script = "4",
                text = "The line can start up to 4 squares from the caster.",
            },
            {
                script = "1 + level",
                text = "Distance of 1 plus 1 per caster level.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature using the ability.",
        symbols = table.union({
            ability = {
                name = "Ability",
                type = "ability",
                desc = "The ability being used.",
            },
        }, ActivatedAbility.helpCasting),
    }
end

local function _numTargetsDocs(ability)
    return {
        domains = ability.domains,
        help = "The number of targets this ability can select.",
        output = "number",
        examples = {
            {
                script = "3",
                text = "The ability targets 3 creatures.",
            },
            {
                script = "1 + 1 when level >= 5",
                text = "One target, or two when the caster reaches level 5.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature using the ability.",
        symbols = ActivatedAbility.helpCasting,
    }
end

local function _proximityRangeDocs(ability)
    return {
        domains = ability.domains,
        help = "When proximity targeting is enabled, every target after the first must be within this many squares of the first (or previous, if chain proximity is on) target.",
        output = "number",
        examples = {
            {
                script = "5",
                text = "Subsequent targets must be within 5 squares of the primary target.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature using the ability.",
    }
end

--[[
    _buildFilterList
    Builds a self-contained panel for a dynamic filter list (abilityFilters or
    reasonedFilters).  Returns a gui.Panel whose children are rebuilt on
    refreshAbility.
]]
local function _buildFilterList(ability, fireChange, fieldName, formulaLabel,
                                 reasonLabel, addButtonLabel, documentation)
    local filterPanel
    filterPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bgcolor = "clear",

        create = function(element)
            element:FireEvent("refreshAbility")
        end,

        refreshAbility = function(element)
            local filters = ability:try_get(fieldName, {})
            local rows = {}
            for i, filter in ipairs(filters) do
                rows[#rows + 1] = gui.Panel{
                    classes = {"nae-filter-entry"},
                    -- Formula row: GoblinScript input + delete button
                    gui.Panel{
                        classes = {"nae-filter-formula-row"},
                        gui.GoblinScriptInput{
                            classes = {"nae-field-input"},
                            width = 250,
                            halign = "left",
                            value = filter.formula,
                            change = function(el)
                                filter.formula = el.value
                                ability[fieldName] = filters
                                fireChange()
                            end,
                            documentation = documentation,
                        },
                        gui.DeleteItemButton{
                            halign = "right",
                            width = 14,
                            height = 14,
                            click = function(el)
                                table.remove(filters, i)
                                ability[fieldName] = filters
                                fireChange()
                            end,
                        },
                    },
                    -- Reason row
                    gui.Panel{
                        classes = {"nae-field-row"},
                        tmargin = 0,
                        bmargin = 0,
                        gui.Label{
                            classes = {"nae-field-label"},
                            text = reasonLabel,
                        },
                        gui.Input{
                            classes = {"nae-field-input"},
                            text = filter.reason or "",
                            placeholderText = "Enter reason...",
                            change = function(el)
                                filter.reason = el.text
                                ability[fieldName] = filters
                                fireChange()
                            end,
                        },
                    },
                }
            end

            -- "Add" button
            rows[#rows + 1] = gui.Panel{
                width = "auto",
                height = "auto",
                halign = "left",
                tmargin = 4,
                gui.Button{
                    text = addButtonLabel,
                    width = "auto",
                    height = "auto",
                    pad = 4,
                    press = function(el)
                        local filters = ability:get_or_add(fieldName, {})
                        filters[#filters + 1] = {
                            formula = "",
                            reason = "",
                        }
                        fireChange()
                    end,
                },
            }

            element.children = rows
        end,
    }
    return filterPanel
end

--[[
    _buildTargetingSection
    Returns a table of gui children for the Targeting section.
]]
local function _buildTargetingSection(ability, fireChange)
    local children = {}

    -- Predicates for conditional visibility.
    local radiusItems = {sphere = true, cylinder = true, line = true, cube = true}

    local function isMultiTarget()
        return ability.targetType == "target" and tonumber(ability.numTargets) ~= 1
    end
    local function isProximityVisible()
        return isMultiTarget() and ability.proximityTargeting
    end
    local function isTargetCountVisible()
        local t = ability.targetType
        return t == "target" or t == "emptyspace" or t == "anyspace"
    end
    local function isSpaceTargeting()
        local t = ability.targetType
        return t == "emptyspace" or t == "anyspace"
    end

    --------------------------------------------------------------------------
    -- 1. Target Type (always visible)
    --------------------------------------------------------------------------
    children[#children + 1] = _makeFieldRow("Target Type:",
        gui.Dropdown{
            classes = {"nae-field-dropdown"},
            options = ability:GetDisplayedTargetTypeOptions(),
            idChosen = ability:GetChosenTargetTypeInDropdown(),
            change = function(element)
                ability:SetChosenTargetTypeFromDropdown(element.idChosen)
                fireChange()
            end,
        }
    )

    --------------------------------------------------------------------------
    -- 2. Range / Length (hidden for self, map; dynamic label)
    --------------------------------------------------------------------------
    local rangeHidden = ability.targetType == "self" or ability.targetType == "map"
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row", cond(rangeHidden, "collapsed-anim", nil)},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim",
                ability.targetType == "self" or ability.targetType == "map")
        end,
        gui.Label{
            classes = {"nae-field-label"},
            text = cond(ability.targetType == "line", "Length:", "Range:"),
            refreshAbility = function(element)
                element.text = cond(ability.targetType == "line", "Length:", "Range:")
            end,
        },
        gui.GoblinScriptInput{
            classes = {"nae-field-input"},
            width = 280,
            halign = "left",
            value = ability.range,
            change = function(element)
                ability.range = element.value
                fireChange()
            end,
            documentation = _rangeDocs(ability),
        },
    }

    --------------------------------------------------------------------------
    -- 3. Radius / Size / Width (sphere, cylinder, line, cube only)
    --------------------------------------------------------------------------
    local function radiusLabel()
        if ability.targetType == "cube" then return "Size:"
        elseif ability.targetType == "line" then return "Width:"
        else return "Radius:" end
    end
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(radiusItems[ability.targetType], nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not radiusItems[ability.targetType])
        end,
        gui.Label{
            classes = {"nae-field-label"},
            text = radiusLabel(),
            refreshAbility = function(element)
                element.text = radiusLabel()
            end,
        },
        gui.GoblinScriptInput{
            classes = {"nae-field-input"},
            width = 280,
            halign = "left",
            value = ability:try_get("radius", ""),
            change = function(element)
                ability.radius = element.value
                fireChange()
            end,
            documentation = _radiusDocs(ability),
        },
    }

    --------------------------------------------------------------------------
    -- 4. Distance (line only)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(ability.targetType == "line", nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", ability.targetType ~= "line")
        end,
        gui.Label{
            classes = {"nae-field-label"},
            text = "Distance:",
        },
        gui.GoblinScriptInput{
            classes = {"nae-field-input"},
            width = 280,
            halign = "left",
            value = ability.lineDistance,
            change = function(element)
                ability.lineDistance = element.value
                fireChange()
            end,
            documentation = _lineDistanceDocs(ability),
        },
    }

    --------------------------------------------------------------------------
    -- 5. Can Choose Lower Range (line only)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Check{
        classes = {"nae-toggle-check",
                   cond(ability.targetType == "line", nil, "collapsed-anim")},
        text = "Can Choose Lower Range",
        value = ability.canChooseLowerRange,
        change = function(element)
            ability.canChooseLowerRange = element.value
            fireChange()
        end,
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", ability.targetType ~= "line")
        end,
    }

    --------------------------------------------------------------------------
    -- 6. Target Count (target, emptyspace, anyspace)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(isTargetCountVisible(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not isTargetCountVisible())
        end,
        gui.Label{
            classes = {"nae-field-label"},
            text = "Target Count:",
        },
        gui.GoblinScriptInput{
            classes = {"nae-field-input"},
            width = 280,
            halign = "left",
            value = ability.numTargets,
            change = function(element)
                ability.numTargets = element.value
                fireChange()
            end,
            documentation = _numTargetsDocs(ability),
        },
    }

    --------------------------------------------------------------------------
    -- 7. Allow Duplicate Targeting (target + multi)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Check{
        classes = {"nae-toggle-check",
                   cond(isMultiTarget(), nil, "collapsed-anim")},
        text = "Allow Duplicate Targeting",
        value = ability.repeatTargets,
        change = function(element)
            ability.repeatTargets = element.value
            fireChange()
        end,
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not isMultiTarget())
        end,
    }

    --------------------------------------------------------------------------
    -- 8. Proximity Targeting (target + multi)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Check{
        classes = {"nae-toggle-check",
                   cond(isMultiTarget(), nil, "collapsed-anim")},
        text = "Proximity Targeting",
        value = ability.proximityTargeting,
        change = function(element)
            ability.proximityTargeting = element.value
            fireChange()
        end,
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not isMultiTarget())
        end,
        linger = function(element)
            return gui.Tooltip("If checked, every target after the first must be within a certain proximity of the first target.")(element)
        end,
    }

    -- 8a. Chain Proximity (proximity on + multi)
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-subgroup",
                   cond(isProximityVisible(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not isProximityVisible())
        end,
        gui.Check{
            classes = {"nae-toggle-check"},
            text = "Chain Proximity",
            value = ability:try_get("proximityChain", false),
            change = function(element)
                ability.proximityChain = element.value
                fireChange()
            end,
            linger = function(element)
                return gui.Tooltip("If checked, each target must be in proximity of the previous target, not the first.")(element)
            end,
        },
        -- 8b. Proximity range
        gui.Panel{
            classes = {"nae-field-row"},
            gui.Label{
                classes = {"nae-field-label"},
                text = "Proximity:",
            },
            gui.GoblinScriptInput{
                classes = {"nae-field-input"},
                width = 280,
                halign = "left",
                value = ability.proximityRange,
                change = function(element)
                    ability.proximityRange = element.value
                    fireChange()
                end,
                documentation = _proximityRangeDocs(ability),
            },
        },
    }

    --------------------------------------------------------------------------
    -- 9. Affects (AOE types only)
    --------------------------------------------------------------------------
    local function affectsIdChosen()
        if ability.objectTarget then return "all_and_objects"
        elseif ability.targetAllegiance == "ally" then return "ally"
        elseif ability.targetAllegiance == "enemy" then return "enemy"
        else return "all" end
    end
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(ability:IsTargetTypeAOE(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not ability:IsTargetTypeAOE())
        end,
        gui.Label{
            classes = {"nae-field-label"},
            text = "Affects:",
        },
        gui.Dropdown{
            classes = {"nae-field-dropdown"},
            options = {
                { id = "all",             text = "Creatures" },
                { id = "all_and_objects", text = "Creatures and Objects" },
                { id = "ally",           text = "Allied Creatures" },
                { id = "enemy",          text = "Enemy Creatures" },
            },
            idChosen = affectsIdChosen(),
            change = function(element)
                if element.idChosen == "all" then
                    ability.objectTarget = false
                    ability.targetAllegiance = nil
                elseif element.idChosen == "all_and_objects" then
                    ability.objectTarget = true
                    ability.targetAllegiance = nil
                elseif element.idChosen == "ally" then
                    ability.objectTarget = false
                    ability.targetAllegiance = "ally"
                elseif element.idChosen == "enemy" then
                    ability.objectTarget = false
                    ability.targetAllegiance = "enemy"
                else
                    ability.objectTarget = false
                    ability.targetAllegiance = nil
                end
                fireChange()
            end,
        },
    }

    --------------------------------------------------------------------------
    -- 10. Can Target Self (hidden when targetType is self)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Check{
        classes = {"nae-toggle-check",
                   cond(ability.targetType ~= "self", nil, "collapsed-anim")},
        text = "Can Target Self",
        value = ability.selfTarget,
        change = function(element)
            ability.selfTarget = element.value
            fireChange()
        end,
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", ability.targetType == "self")
        end,
    }

    --------------------------------------------------------------------------
    -- 11. Cast immediately when clicked (self only)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Check{
        classes = {"nae-toggle-check",
                   cond(ability.targetType == "self", nil, "collapsed-anim")},
        text = "Cast immediately when clicked",
        value = ability.castImmediately,
        change = function(element)
            ability.castImmediately = element.value
            fireChange()
        end,
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", ability.targetType ~= "self")
        end,
    }

    --------------------------------------------------------------------------
    -- 12. Targeting mode (emptyspace / anyspace only)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(isSpaceTargeting(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not isSpaceTargeting())
        end,
        gui.Label{
            classes = {"nae-field-label"},
            text = "Targeting:",
        },
        gui.Dropdown{
            classes = {"nae-field-dropdown"},
            options = {
                { id = "direct",                      text = "Direct" },
                { id = "pathfind",                    text = "Pathfinding" },
                { id = "straightpath",                text = "Direct Path" },
                { id = "straightpathignorecreatures", text = "Direct Path, Ignoring Creatures" },
                { id = "straightline",                text = "Forced Movement" },
                { id = "vacated",                     text = "Vacated Space" },
                { id = "contiguous",                  text = "Connected Spaces" },
                { id = "contiguous_wall",             text = "Wall" },
            },
            idChosen = ability:try_get("targeting", "direct"),
            change = function(element)
                ability.targeting = element.idChosen
                fireChange()
            end,
        },
    }

    -- 12a + 12b. Forced Movement subgroup (targeting == straightline)
    local function isForcedMovement()
        return isSpaceTargeting() and ability:try_get("targeting", "direct") == "straightline"
    end
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-subgroup",
                   cond(isForcedMovement(), nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not isForcedMovement())
        end,

        _makeFieldRow("Forced Movement:",
            gui.Dropdown{
                classes = {"nae-field-dropdown"},
                options = ActivatedAbility.ForcedMovementTypes,
                idChosen = ability:try_get("forcedMovement", "slide"),
                change = function(element)
                    ability.forcedMovement = element.idChosen
                    fireChange()
                end,
            }
        ),

        gui.Check{
            classes = {"nae-toggle-check"},
            text = "Through Creatures",
            value = ability:try_get("forcedMovementThroughCreatures", false),
            change = function(element)
                ability.forcedMovementThroughCreatures = element.value
                fireChange()
            end,
        },
    }

    --------------------------------------------------------------------------
    -- 13. Object ID (areatemplate only)
    --------------------------------------------------------------------------
    children[#children + 1] = gui.Panel{
        classes = {"nae-field-row",
                   cond(ability.targetType == "areatemplate", nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", ability.targetType ~= "areatemplate")
        end,
        gui.Label{
            classes = {"nae-field-label"},
            text = "Object ID:",
        },
        gui.Input{
            classes = {"nae-field-input"},
            text = ability:try_get("areaTemplateObjectId", ""),
            placeholderText = "Enter Object ID...",
            change = function(element)
                ability.areaTemplateObjectId = element.text
                fireChange()
            end,
        },
    }

    --------------------------------------------------------------------------
    -- 14. Target Filter (always visible -- 343 compendium uses)
    --------------------------------------------------------------------------
    children[#children + 1] = _makeFieldRow("Target Filter:",
        gui.GoblinScriptInput{
            classes = {"nae-field-input"},
            width = 280,
            halign = "left",
            value = ability.targetFilter,
            change = function(element)
                ability.targetFilter = element.value
                fireChange()
            end,
            documentation = _targetFilterDocs(ability),
        }
    )

    --------------------------------------------------------------------------
    -- 15. Range Text (always visible, dynamic placeholder)
    --------------------------------------------------------------------------
    children[#children + 1] = _makeFieldRow("Range Text:",
        gui.Input{
            classes = {"nae-field-input"},
            text = ability:try_get("rangeTextOverride", ""),
            placeholderText = ability:DescribeRange(),
            change = function(element)
                ability.rangeTextOverride = element.text
                fireChange()
            end,
            refreshAbility = function(element)
                element.placeholderText = ability:DescribeRange()
            end,
        }
    )

    --------------------------------------------------------------------------
    -- 16. Target Text (always visible, dynamic placeholder)
    --------------------------------------------------------------------------
    children[#children + 1] = _makeFieldRow("Target Text:",
        gui.Input{
            classes = {"nae-field-input"},
            text = ability:try_get("targetTextOverride", ""),
            placeholderText = ability:DescribeTarget(),
            change = function(element)
                ability.targetTextOverride = element.text
                fireChange()
            end,
            refreshAbility = function(element)
                element.placeholderText = ability:DescribeTarget()
            end,
        }
    )

    --------------------------------------------------------------------------
    -- "More options" CollapseArrow
    --------------------------------------------------------------------------
    local moreOptionsContent
    moreOptionsContent = gui.Panel{
        classes = {"nae-field-subgroup", "collapsed-anim"},
        flow = "vertical",
        width = "100%",
        height = "auto",

        -- Ability Filters (caster-side)
        gui.Label{
            classes = {"nae-filter-heading"},
            text = "Ability Filters",
        },
        _buildFilterList(ability, fireChange, "abilityFilters",
                          "Filter:", "Reason:", "Add Ability Filter",
                          _abilityFilterDocs(ability)),

        -- Spacer
        gui.Panel{ width = "100%", height = 8, bgcolor = "clear" },

        -- Reasoned Filters (target-side)
        gui.Label{
            classes = {"nae-filter-heading"},
            text = "Reasoned Filters",
        },
        _buildFilterList(ability, fireChange, "reasonedFilters",
                          "Formula:", "Reason:", "Add Reasoned Filter",
                          _targetFilterDocs(ability)),
    }

    local moreOptionsChevron
    moreOptionsChevron = gui.Panel{
        classes = {"nae-more-options-chevron", "nae-collapsed"},
    }
    children[#children + 1] = gui.Panel{
        classes = {"nae-more-options-row"},
        press = function(element)
            local wasCollapsed = moreOptionsContent:HasClass("collapsed-anim")
            moreOptionsContent:SetClass("collapsed-anim", not wasCollapsed)
            moreOptionsChevron:SetClass("nae-collapsed", not wasCollapsed)
        end,
        gui.Label{
            classes = {"nae-more-options-label"},
            text = "More options",
        },
        moreOptionsChevron,
    }

    children[#children + 1] = moreOptionsContent

    return children
end

--[[
    ============================================================================
    Effects section
    ============================================================================
    The behavior list is the core of every ability. Each behavior is a typed
    object (Damage, Heal, Forced Movement, etc.) with its own per-type editor
    fields. This section renders the existing behavior list with inline
    editors, reorder/delete controls, and an "Add Behavior" button that opens
    the search-first behavior picker modal.
]]

-- Change guard key: only rebuild the behavior list panel when the list
-- itself has changed (add/remove/reorder), not on unrelated field edits.
local function _behaviorListKey(ability)
    local parts = {}
    for _, b in ipairs(ability.behaviors or {}) do
        parts[#parts + 1] = b:try_get("guid", b.typeName or "?")
    end
    return #parts .. ":" .. table.concat(parts, ",")
end

-- Mode/tier/strain pill panel for a single behavior.
-- Reuses the same logic as the classic CreateEditor (ActivatedAbilityEditor.lua:4282-4509)
-- but themed with gold/cream pill labels.
local function _makeBehaviorPillPanel(ability, behavior, fireChange)
    -- Mode pills: visible when ability.multipleModes is true
    local modePanel = gui.Panel{
        classes = {"nae-behavior-pills", "collapsed"},
        data = {cacheKey = nil},

        -- Self-initialize on create. On re-open of the editor, the behavior
        -- list is built via behaviorList.create's FireEvent (single element),
        -- which does not cascade to children, so pills would stay collapsed
        -- until the next tree-wide fireChange. Fire our own refreshAbility
        -- here so pills populate immediately. Matches the pattern used by
        -- the behavior contentPanel below.
        create = function(element) element:FireEvent("refreshAbility") end,

        refreshAbility = function(element)
            local shown = ability.multipleModes == true
            element:SetClass("collapsed", not shown)
            if not shown then return end

            local key = {
                modeList = DeepCopy(ability:try_get("modeList", {})),
                modesSelected = DeepCopy(behavior:try_get("modesSelected", {})),
            }
            if dmhub.DeepEqual(key, element.data.cacheKey) then return end
            element.data.cacheKey = DeepCopy(key)

            local children = {}
            children[#children + 1] = gui.Label{
                classes = {"nae-pill-label",
                           cond(#behavior:try_get("modesSelected", {}) == 0, "selected")},
                text = "All Modes",
                press = function()
                    behavior.modesSelected = nil
                    fireChange()
                end,
            }
            children[#children + 1] = gui.Label{
                classes = {"nae-pill-label", "disabled",
                           cond(table.contains(behavior:try_get("modesSelected", {}), -1), "selected")},
                text = "Disabled",
                press = function()
                    behavior.modesSelected = {-1}
                    fireChange()
                end,
            }
            for mi, mode in ipairs(ability:try_get("modeList", {})) do
                local modeIndex = mi
                children[#children + 1] = gui.Label{
                    classes = {"nae-pill-label",
                               cond(table.contains(behavior:try_get("modesSelected", {}), modeIndex), "selected")},
                    text = mode.text,
                    press = function()
                        if not behavior:has_key("modesSelected") then
                            behavior.modesSelected = {}
                        end
                        table.remove_value(behavior.modesSelected, -1)
                        if table.contains(behavior.modesSelected, modeIndex) then
                            table.remove_value(behavior.modesSelected, modeIndex)
                        else
                            behavior.modesSelected[#behavior.modesSelected + 1] = modeIndex
                        end
                        fireChange()
                    end,
                }
            end
            element.children = children
        end,
    }

    -- Tier pills: visible when a PowerRoll behavior appears before this one
    local tierPanel = gui.Panel{
        classes = {"nae-behavior-pills", "collapsed"},
        data = {cacheKey = nil},

        create = function(element) element:FireEvent("refreshAbility") end,

        refreshAbility = function(element)
            local hasPowerRollBefore = false
            for _, b in ipairs(ability.behaviors) do
                if b == behavior then break end
                if b.typeName == "ActivatedAbilityPowerRollBehavior" then
                    hasPowerRollBefore = true
                    break
                end
            end

            element:SetClass("collapsed", not hasPowerRollBefore)
            if not hasPowerRollBefore then return end

            local key = {tiersSelected = DeepCopy(behavior:try_get("tiersSelected", {}))}
            if dmhub.DeepEqual(key, element.data.cacheKey) then return end
            element.data.cacheKey = DeepCopy(key)

            local children = {}
            children[#children + 1] = gui.Label{
                classes = {"nae-pill-label",
                           cond(#behavior:try_get("tiersSelected", {}) == 0, "selected")},
                text = "All Tiers",
                press = function()
                    behavior.tiersSelected = nil
                    fireChange()
                end,
            }
            children[#children + 1] = gui.Label{
                classes = {"nae-pill-label", "disabled",
                           cond(table.contains(behavior:try_get("tiersSelected", {}), -1), "selected")},
                text = "Disabled",
                press = function()
                    behavior.tiersSelected = {-1}
                    fireChange()
                end,
            }
            for ti = 1, 3 do
                local tierIndex = ti
                children[#children + 1] = gui.Label{
                    classes = {"nae-pill-label",
                               cond(table.contains(behavior:try_get("tiersSelected", {}), tierIndex), "selected")},
                    text = "Tier " .. tierIndex,
                    press = function()
                        if not behavior:has_key("tiersSelected") then
                            behavior.tiersSelected = {}
                        end
                        table.remove_value(behavior.tiersSelected, -1)
                        if table.contains(behavior.tiersSelected, tierIndex) then
                            table.remove_value(behavior.tiersSelected, tierIndex)
                        else
                            behavior.tiersSelected[#behavior.tiersSelected + 1] = tierIndex
                        end
                        fireChange()
                    end,
                }
            end
            element.children = children
        end,
    }

    -- Strain pills: visible when the ability uses strain
    local strainPanel = gui.Panel{
        classes = {"nae-behavior-pills", "collapsed"},
        data = {cacheKey = nil},

        create = function(element) element:FireEvent("refreshAbility") end,

        refreshAbility = function(element)
            local hasStrain = ability:IsStrain()
            element:SetClass("collapsed", not hasStrain)
            if not hasStrain then return end

            local key = {strainSelection = behavior:try_get("strainSelection")}
            if dmhub.DeepEqual(key, element.data.cacheKey) then return end
            element.data.cacheKey = DeepCopy(key)

            local children = {}
            children[#children + 1] = gui.Label{
                classes = {"nae-pill-label",
                           cond(behavior:try_get("strainSelection") == nil, "selected")},
                text = "Always",
                press = function()
                    behavior.strainSelection = nil
                    fireChange()
                end,
            }
            children[#children + 1] = gui.Label{
                classes = {"nae-pill-label",
                           cond(behavior:try_get("strainSelection") == "unstrained", "selected")},
                text = "Unstrained",
                press = function()
                    behavior.strainSelection = "unstrained"
                    fireChange()
                end,
            }
            children[#children + 1] = gui.Label{
                classes = {"nae-pill-label",
                           cond(behavior:try_get("strainSelection") == "strained", "selected")},
                text = "Strained",
                press = function()
                    behavior.strainSelection = "strained"
                    fireChange()
                end,
            }
            element.children = children
        end,
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bgcolor = "clear",
        children = {modePanel, tierPanel, strainPanel},
    }
end

-- Post-process EditorItems panels to fix layout issues caused by base-code
-- inline sizing that our style cascade cannot override (inline constructor
-- properties win over CSS styles for width/height -- see NOTES.md).
--
-- Walks the flat items list and:
-- 1. Fixes "Edit Effect" button: removes fixed width/height so the button
--    auto-sizes around its text (inline hpad compresses the 120px content).
-- 2. Fixes "Edit Ability" PrettyButton in Invoke Ability: moves it from a
--    standalone row into the preceding Type formPanel for inline layout.
local function _fixEditorItemsLayout(items)
    local typeFormPanelIndex = nil
    local editAbilityIndex = nil

    for i, panel in ipairs(items) do
        -- Walk immediate children looking for buttons with specific text.
        -- gui.Button / gui.PrettyButton are Labels with class "button".
        if panel.text == "Edit Effect" then
            -- Fix 1: auto-size the Edit Effect button.
            panel.width = "auto"
            panel.height = "auto"
            panel.minWidth = 100
            panel.minHeight = 28
        elseif panel.text == "Edit Ability" then
            -- This is the standalone PrettyButton for Invoke Ability.
            editAbilityIndex = i
        end

        -- Look inside formPanels for the Type dropdown row and for
        -- "Edit Effect" buttons nested as children.
        local children = panel.children
        if children ~= nil then
            for _, child in ipairs(children) do
                -- Check for the Type label in a formPanel.
                if child.text == "Type:" then
                    typeFormPanelIndex = i
                end
                -- Check for "Edit Effect" buttons nested inside formPanels.
                if child.text == "Edit Effect" then
                    child.width = "auto"
                    child.height = "auto"
                    child.minWidth = 100
                    child.minHeight = 28
                end
            end
        end
    end

    -- Fix 2: place "Edit Ability" next to the Type dropdown. We cannot
    -- append to an already-constructed panel's children array (the engine
    -- tracks parent-child relationships internally). Instead, remove both
    -- from the items list and wrap them in a new horizontal row panel.
    if typeFormPanelIndex ~= nil and editAbilityIndex ~= nil then
        -- Remove edit button first (always after typeFormPanel in base code,
        -- but handle the reverse case defensively).
        local editBtn = table.remove(items, editAbilityIndex)
        editBtn.width = "auto"
        editBtn.height = "auto"
        editBtn.minWidth = 100
        editBtn.minHeight = 28

        local adjustedIdx = typeFormPanelIndex
        if editAbilityIndex < typeFormPanelIndex then
            adjustedIdx = adjustedIdx - 1
        end

        local typePanel = table.remove(items, adjustedIdx)
        local row = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
            children = {typePanel, editBtn},
        }
        table.insert(items, adjustedIdx, row)
    end
end

-- Per-behavior panel: header + pills + inline editor items.
local function _makeBehaviorPanel(ability, behavior, index, totalCount, fireChange)
    local summaryLabel = gui.Label{
        classes = {"nae-behavior-summary"},
        text = behavior.summary or "Behavior",
    }

    local copyBtn = gui.Label{
        classes = {"nae-behavior-copy-btn"},
        text = "Copy",
        press = function()
            dmhub.CopyToInternalClipboard(behavior)
        end,
    }

    local upArrow = gui.Panel{
        classes = {"nae-behavior-arrow", "nae-up", cond(index <= 1, "disabled")},
        press = function()
            if index > 1 then
                local temp = ability.behaviors[index - 1]
                ability.behaviors[index - 1] = ability.behaviors[index]
                ability.behaviors[index] = temp
                fireChange()
            end
        end,
    }

    local downArrow = gui.Panel{
        classes = {"nae-behavior-arrow", cond(index >= totalCount, "disabled")},
        press = function()
            if index < totalCount then
                local temp = ability.behaviors[index + 1]
                ability.behaviors[index + 1] = ability.behaviors[index]
                ability.behaviors[index] = temp
                fireChange()
            end
        end,
    }

    local deleteBtn = gui.DeleteItemButton{
        width = 14,
        height = 14,
        valign = "center",
        lmargin = 8,
        click = function()
            table.remove(ability.behaviors, index)
            fireChange()
        end,
    }

    local header = gui.Panel{
        classes = {"nae-behavior-header"},
        children = {
            summaryLabel,
            gui.Panel{
                classes = {"nae-behavior-controls"},
                floating = true,
                children = {copyBtn, upArrow, downArrow, deleteBtn},
            },
        },
    }

    local pillPanel = _makeBehaviorPillPanel(ability, behavior, fireChange)

    local contentPanel = gui.Panel{
        classes = {"nae-behavior-content"},
        data = {parentAbility = ability},

        create = function(element)
            element:FireEvent("refreshBehavior")
        end,

        refreshBehavior = function(element)
            local items = behavior:EditorItems(element)
            _fixEditorItemsLayout(items)
            element.children = items
        end,
    }

    return gui.Panel{
        classes = {"nae-behavior-item"},
        children = {header, pillPanel, contentPanel},
    }
end

local function _buildEffectsSection(ability, fireChange)
    local children = {}

    -- Behavior list container -- rebuilt via dynamic children when the list
    -- changes (add/remove/reorder). Change-guarded to avoid unnecessary
    -- rebuilds on unrelated field edits.
    local behaviorList
    behaviorList = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bgcolor = "clear",
        halign = "left",
        valign = "top",
        data = {lastKey = nil},

        create = function(element)
            element:FireEvent("refreshAbility")
        end,

        refreshAbility = function(element)
            local currentKey = _behaviorListKey(ability)
            if element.data.lastKey == currentKey then return end
            element.data.lastKey = currentKey

            local rows = {}
            local behaviors = ability.behaviors or {}
            for i, behavior in ipairs(behaviors) do
                rows[#rows + 1] = _makeBehaviorPanel(ability, behavior, i, #behaviors, fireChange)
                if i < #behaviors then
                    rows[#rows + 1] = gui.Panel{classes = {"nae-behavior-divider"}}
                end
            end
            element.children = rows
        end,
    }
    children[#children + 1] = behaviorList

    -- Add/Paste buttons live in the fixed bottom bar (effectsBottomBar)
    -- inside the detail column, outside the scroll area. See
    -- AbilityEditor.GenerateEditor for the bar construction.

    return children
end

--[[
    ============================================================================
    Presentation section
    ============================================================================
    Icon customization (custom image, background color, gradient, hue,
    saturation, brightness) and VFX selection (Cast, Impact, Projectile).
]]
local function _buildPresentationSection(ability, fireChange)
    local children = {}

    -- ----------------------------------------------------------------
    -- Icon sub-heading
    -- ----------------------------------------------------------------
    children[#children + 1] = gui.Label{
        classes = {"nae-sub-heading"},
        text = "Icon",
    }

    -- The icon editor widget needs a forward-declared reference so
    -- sliders/gradient/colorPicker can fire its 'create' event to
    -- refresh the preview styling (hue/sat/brightness/gradient).
    local iconEditor = nil

    -- Refresh icon display styles. Called after any display property
    -- changes to update the icon editor's preview rendering.
    local function refreshIconDisplay()
        if iconEditor == nil then return end
        iconEditor:FireEvent("create")
    end

    iconEditor = gui.IconEditor{
        library = "abilities",
        bgcolor = ability.display["bgcolor"] or "#ffffffff",
        width = 64,
        height = 64,
        halign = "left",
        gradientMapping = true,
        value = ability.iconid,
        change = function(element)
            ability.iconid = element.value
            fireChange()
        end,
        create = function(element)
            element.selfStyle.hueshift = ability.display["hueshift"]
            element.selfStyle.saturation = ability.display["saturation"]
            element.selfStyle.brightness = ability.display["brightness"]
            element.selfStyle.gradient = DisplayGradients.GetGradient(
                ability:try_get("iconGradient") or "none"
            )
        end,
    }

    local iconColorPicker = gui.ColorPicker{
        value = ability.display["bgcolor"] or "#ffffffff",
        width = 24,
        height = 24,
        halign = "left",
        valign = "center",
        lmargin = 12,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        confirm = function(element)
            iconEditor.selfStyle.bgcolor = element.value
            ability.display["bgcolor"] = element.value
            fireChange()
        end,
        change = function(element)
            iconEditor.selfStyle.bgcolor = element.value
        end,
    }

    -- Icon + color picker on a single row (only visible when custom icon on).
    local iconRow = gui.Panel{
        classes = {"nae-icon-row",
                   cond(not ability.hasCustomIcon, "collapsed-anim")},
        children = {iconEditor, iconColorPicker},
    }
    children[#children + 1] = iconRow

    -- Read-only preview of the keyword-derived icon (visible when custom
    -- icon is off). Shows ability:GetIcon() which resolves to a
    -- keyword-based or category-based icon.
    local keywordIconPreview = gui.Panel{
        width = 48,
        height = 48,
        halign = "left",
        bgimage = ability:GetIcon(),
        bgcolor = COLORS.CREAM,
        classes = {cond(ability.hasCustomIcon, "collapsed-anim")},
        refreshAbility = function(element)
            element.bgimage = ability:GetIcon()
        end,
    }
    children[#children + 1] = keywordIconPreview

    -- ----------------------------------------------------------------
    -- Custom Icon toggle + conditional controls
    -- ----------------------------------------------------------------
    local customIconControls = nil

    local customIconCheck = gui.Check{
        classes = {"nae-toggle-check"},
        text = "Custom Icon",
        value = ability.hasCustomIcon,
        change = function(element)
            ability.hasCustomIcon = element.value
            customIconControls:SetClass("collapsed-anim", not element.value)
            iconRow:SetClass("collapsed-anim", not element.value)
            keywordIconPreview:SetClass("collapsed-anim", element.value)
            fireChange()
        end,
    }
    children[#children + 1] = customIconCheck

    -- Slider factory (themed for the new editor).
    local function makeDisplaySlider(label, attr, minVal, maxVal)
        return gui.Panel{
            classes = {"nae-slider-row"},
            children = {
                gui.Label{
                    classes = {"nae-slider-label"},
                    text = label,
                },
                gui.Slider{
                    height = 28,
                    width = 180,
                    fontSize = 12,
                    color = COLORS.CREAM_BRIGHT,
                    sliderWidth = 130,
                    labelWidth = 45,
                    value = ability.display[attr],
                    minValue = minVal,
                    maxValue = maxVal,
                    formatFunction = function(num)
                        return string.format("%d%%", round(num * 100))
                    end,
                    deformatFunction = function(num)
                        return num * 0.01
                    end,
                    events = {
                        change = function(element)
                            ability.display = DeepCopy(ability.display)
                            ability.display[attr] = element.value
                            refreshIconDisplay()
                            fireChange()
                        end,
                        confirm = function(element)
                            ability.display = DeepCopy(ability.display)
                            ability.display[attr] = element.value
                            refreshIconDisplay()
                            fireChange()
                        end,
                    },
                },
            },
        }
    end

    customIconControls = gui.Panel{
        classes = {cond(not ability.hasCustomIcon, "collapsed-anim")},
        flow = "vertical",
        height = "auto",
        width = "100%",
        halign = "left",
        bgcolor = "clear",
        children = {
            -- Gradient dropdown
            _makeFieldRow("Gradient", gui.Dropdown{
                classes = {"nae-field-dropdown"},
                options = DisplayGradients.GetOptions(),
                idChosen = ability:try_get("iconGradient", "none"),
                change = function(element)
                    ability.iconGradient = element.idChosen
                    refreshIconDisplay()
                    fireChange()
                end,
            }),
            -- Hue / Saturation / Brightness sliders
            makeDisplaySlider("Hue", "hueshift", 0, 1),
            makeDisplaySlider("Saturation", "saturation", 0, 2),
            makeDisplaySlider("Brightness", "brightness", 0, 2),
        },
    }
    children[#children + 1] = customIconControls

    -- ----------------------------------------------------------------
    -- Divider
    -- ----------------------------------------------------------------
    children[#children + 1] = gui.Panel{
        classes = {"nae-presentation-divider"},
    }

    -- ----------------------------------------------------------------
    -- Visual Effects sub-heading
    -- ----------------------------------------------------------------
    children[#children + 1] = gui.Label{
        classes = {"nae-sub-heading"},
        text = "Visual Effects",
    }

    -- Build the VFX options from the emoji table (spellcasting emojis).
    local vfxOptions = {
        { id = "none", text = "(None)" },
    }
    for _, emoji in pairs(assets.emojiTable) do
        if emoji.emojiType == "Spellcasting" then
            vfxOptions[#vfxOptions + 1] = {
                id = emoji.description,
                text = emoji.description,
            }
        end
    end

    -- Cast Effect dropdown.
    children[#children + 1] = _makeFieldRow("Cast Effect", gui.Dropdown{
        classes = {"nae-field-dropdown"},
        options = vfxOptions,
        sort = true,
        idChosen = ability:try_get("castingEmote", "none"),
        change = function(element)
            if element.idChosen == "none" then
                ability.castingEmote = nil
            else
                ability.castingEmote = element.idChosen
            end
            fireChange()
        end,
    })

    -- Impact Effect dropdown.
    children[#children + 1] = _makeFieldRow("Impact Effect", gui.Dropdown{
        classes = {"nae-field-dropdown"},
        options = vfxOptions,
        sort = true,
        idChosen = ability:try_get("impactEmote", "none"),
        change = function(element)
            if element.idChosen == "none" then
                ability.impactEmote = nil
            else
                ability.impactEmote = element.idChosen
            end
            fireChange()
        end,
    })

    -- Projectile dropdown (loaded from asset folder).
    children[#children + 1] = _makeFieldRow("Projectile", gui.Dropdown{
        classes = {"nae-field-dropdown"},
        create = function(element)
            local options = {
                { id = "none", text = "(None)" },
            }
            local projectileFolderId = "14d073f8-d00a-4ab4-b184-0545124c9940"
            local objectProjectilesFolder = assets:GetObjectNode(projectileFolderId)
            for _, projectileObject in ipairs(objectProjectilesFolder.children) do
                if not projectileObject.isfolder then
                    options[#options + 1] = {
                        id = projectileObject.id,
                        text = projectileObject.description,
                    }
                end
            end
            element.options = options
            element.idChosen = ability.projectileObject
        end,
        change = function(element)
            ability.projectileObject = element.idChosen
            fireChange()
        end,
    })

    return children
end

--[[
    ============================================================================
    Section content dispatcher
    ============================================================================
    Each section is a single vertical panel with a heading + body.
]]

-- Section builders keyed by section ID. Used by _makeSectionContent for
-- lazy construction: sections are only built when first selected.
local SECTION_BUILDERS = {
    overview = _buildOverviewSection,
    costAndAction = _buildCostAndActionSection,
    targeting = _buildTargetingSection,
    effects = _buildEffectsSection,
    presentation = _buildPresentationSection,
}

local function _makeSectionContent(sectionDef, ability, fireChange)
    -- Lazy construction: the section starts with just a heading. The full
    -- content is built on first activation (when selectSection removes the
    -- "inactive" class). This avoids building all 5 sections upfront,
    -- which was the main source of editor open lag.
    local built = false

    local panel
    panel = gui.Panel{
        classes = {"nae-section-content", "inactive"},
        id = "section_" .. sectionDef.id,
        data = {
            sectionId = sectionDef.id,
            -- Called by selectSection when this section becomes active.
            ensureBuilt = function()
                if built then return end
                built = true
                local body = {}
                body[#body + 1] = gui.Label{
                    classes = {"nae-section-heading"},
                    text = sectionDef.label,
                }
                local builder = SECTION_BUILDERS[sectionDef.id]
                if builder ~= nil then
                    local sectionChildren = builder(ability, fireChange)
                    for _, child in ipairs(sectionChildren) do
                        body[#body + 1] = child
                    end
                end
                panel.children = body
            end,
        },
    }
    return panel
end

--[[
    ============================================================================
    Live preview
    ============================================================================
    Reuses CreateAbilityTooltip (DMHub Compendium/ActivatedAbilityEditor.lua:4),
    which renders the same card players see on hover. The preview rebuilds its
    content when the root panel fires "refreshPreview" -- field editors fire
    this through their shared fireChange() helper.

    The preview column is always visible; the editor runs as a full-screen
    modal so the detail column has enough room even with the preview mounted.

    Polling: behaviors' EditorItems are shared base code and have no hook
    into the editor's fireChange helper, so typing in fields like a power-
    roll tier text updates the ability's data but never triggers a preview
    rebuild. We use a thinkTime-based poll on previewSlot to schedule a
    refresh every 250ms. The existing debounce in _schedulePreviewRefresh
    coalesces this with keystroke-driven refreshes so we don't double-run.
]]
local function _makePreview(ability, schedulePreviewRefresh)
    local previewSlot
    previewSlot = gui.Panel{
        id = "previewSlot",
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
        bgcolor = "clear",

        thinkTime = 0.25,
        think = function(element)
            if schedulePreviewRefresh ~= nil then
                schedulePreviewRefresh()
            end
        end,

        refreshPreview = function(element)
            -- Wrap the tooltip card in a width-constrained container so the
            -- card can't push past the preview column (and therefore past
            -- the dialog's gold border). CreateAbilityTooltip chooses its
            -- own internal width; wrapping with width = 100% + clipping
            -- keeps it polite without forcing a re-layout.
            --
            -- Post-processing: the base tooltip code (MCDMActivatedAbility.lua)
            -- omits halign="left" on some container panels (range row, etc.),
            -- causing them to center inside the card. We walk the tree and
            -- set halign="left" only on CONTAINER panels (those with children).
            -- Leaf elements (labels, icons) are left alone so they keep their
            -- own halign (e.g. "Main Action" stays halign="right").
            local function fixTooltipAlignment(panel)
                if panel == nil then return end
                local ok, children = pcall(function() return panel.children end)
                if not ok or children == nil or #children == 0 then return end
                for _, child in ipairs(children) do
                    local cOk, grandchildren = pcall(function() return child.children end)
                    if cOk and grandchildren ~= nil and #grandchildren > 0 then
                        pcall(function() child.halign = "left" end)
                    end
                    fixTooltipAlignment(child)
                end
            end
            local ok, cardOrErr = pcall(CreateAbilityTooltip, ability, {
                halign = "left",
                valign = "top",
            })
            if ok and cardOrErr ~= nil then
                fixTooltipAlignment(cardOrErr)
                element.children = {
                    gui.Panel{
                        width = "100%",
                        height = "auto",
                        halign = "left",
                        valign = "top",
                        flow = "vertical",
                        clip = true,
                        bgcolor = "clear",
                        children = { cardOrErr },
                    },
                }
            else
                element.children = {
                    gui.Label{
                        width = "100%",
                        height = "auto",
                        fontSize = 13,
                        italics = true,
                        color = COLORS.GRAY,
                        text = "(no preview available for this ability)",
                    },
                }
            end
        end,
    }

    -- Wrap the preview slot in a vertical scroller so tall cards (long
    -- descriptions, many power roll tiers) don't push the column past the
    -- dialog's bottom edge.
    local scrollArea = gui.Panel{
        classes = {"nae-preview-body"},
        id = "previewScroll",
        vscroll = true,
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        children = { previewSlot },
    }

    local headingLabel = gui.Label{
        classes = {"nae-preview-heading"},
        text = "Preview",
        width = "100%",
        halign = "left",
        valign = "top",
    }

    local colPanel = gui.Panel{
        classes = {"nae-preview-col"},
        id = "previewCol",
        width = LAYOUT.PREVIEW_WIDTH,
        height = "100%",
        flow = "vertical",
        valign = "top",
        hpad = 4,
        vpad = LAYOUT.COL_VPAD,
        borderBox = true,
        children = {
            headingLabel,
            scrollArea,
        },
    }
    -- Return both the column panel and the preview slot so the caller
    -- can fire refreshPreview directly (avoiding a tree-wide walk).
    return colPanel, previewSlot
end

--[[
    ============================================================================
    Root editor
    ============================================================================
]]
function AbilityEditor.GenerateEditor(ability)
    local sectionContents = {}
    local navButtons = {}

    -- Forward-declare so nav button click handlers can close over it.
    local rootPanel
    local previewCol
    local detailCol
    local detailScroll = nil
    local effectsBottomBar = nil
    local previewSlot = nil

    -- Debounce state for preview rebuilds. Coalesces rapid edits (e.g.
    -- keystrokes in a text field) into a single tooltip rebuild per 150ms
    -- window. The preview is always visible now, so every debounced flush
    -- fires the refresh unconditionally.
    local _previewDirty = false
    local _previewTimerActive = false

    local function _schedulePreviewRefresh()
        _previewDirty = true
        if _previewTimerActive then return end
        _previewTimerActive = true
        dmhub.Schedule(0.15, function()
            if mod.unloaded then return end
            _previewTimerActive = false
            if not _previewDirty then return end
            _previewDirty = false
            if previewSlot ~= nil then
                previewSlot:FireEvent("refreshPreview")
            end
        end)
    end

    -- Shared change helper. refreshAbility is tree-wide because many
    -- panels across all sections listen to it. refreshKeywords and
    -- refreshImplementation are scoped to the Overview section subtree
    -- (the only section with handlers for those events). refreshPreview
    -- is debounced and fires directly on the preview slot panel.
    local function fireChange()
        if rootPanel == nil then return end
        rootPanel:FireEventTree("refreshAbility")
        -- Scoped: only Overview has keyword/implementation handlers.
        local overviewPanel = sectionContents[1]
        if overviewPanel ~= nil then
            overviewPanel:FireEventTree("refreshKeywords")
            overviewPanel:FireEventTree("refreshImplementation")
        end
        _schedulePreviewRefresh()
    end

    local function selectSection(sectionId)
        if rootPanel == nil then return end
        rootPanel.data.selectedSectionId = sectionId

        for _, btn in ipairs(navButtons) do
            btn:SetClass("selected", btn.data.sectionId == sectionId)
        end
        for _, content in ipairs(sectionContents) do
            local isActive = content.data.sectionId == sectionId
            content:SetClass("inactive", not isActive)
            -- Lazy build: construct section content on first activation.
            if isActive and content.data.ensureBuilt then
                content.data.ensureBuilt()
            end
        end

        -- The Effects section gets a fixed bottom bar (Add/Paste buttons);
        -- other sections hide it and reclaim the space. The preview column
        -- stays visible in every section.
        if sectionId == "effects" then
            if effectsBottomBar ~= nil then
                effectsBottomBar:SetClass("nae-not-effects", false)
                effectsBottomBar:SetClass("collapsed", false)
                detailScroll.height = "100%-42"
            end
        else
            if effectsBottomBar ~= nil then
                effectsBottomBar:SetClass("nae-not-effects", true)
                effectsBottomBar:SetClass("collapsed", true)
                detailScroll.height = "100%"
            end
        end
    end

    for _, sectionDef in ipairs(SECTIONS) do
        navButtons[#navButtons + 1] = _makeNavButton(sectionDef, selectSection)
        sectionContents[#sectionContents + 1] = _makeSectionContent(sectionDef, ability, fireChange)
    end

    local navCol = gui.Panel{
        classes = {"nae-nav-col"},
        id = "navCol",
        width = LAYOUT.NAV_WIDTH,
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        hpad = LAYOUT.COL_HPAD,
        vpad = LAYOUT.COL_VPAD,
        borderBox = true,
        children = navButtons,
    }

    -- The Effects section needs a fixed bottom bar (Add/Paste buttons)
    -- that stays visible regardless of scroll position. To achieve this,
    -- the detail column is a non-scrolling vertical container with two
    -- children: a scroll area (for section content) and a bottom bar.
    -- The bottom bar is collapsed for all sections except Effects.
    detailScroll = gui.Panel{
        id = "detailScroll",
        width = "100%",
        -- Leave room for the fixed bottom bar (38px) when it's visible.
        -- selectSection sets the class to shrink the scroll area.
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        vscroll = true,
        -- Padding lives here (not on detailCol) so the scrollbar sits
        -- inside the padded area rather than overlapping content.
        hpad = LAYOUT.COL_HPAD,
        vpad = LAYOUT.COL_VPAD,
        borderBox = true,
        children = sectionContents,
    }

    -- Helper: check if the internal clipboard holds a behavior.
    local function _clipboardHasBehavior()
        local item = dmhub.GetInternalClipboard()
        if item == nil then return false end
        local tn = item.typeName or ""
        return string.starts_with(tn, "ActivatedAbility") and string.ends_with(tn, "Behavior")
    end

    -- Helper: paste the clipboard behavior into the ability.
    local function _pasteBehavior()
        local item = dmhub.GetInternalClipboard()
        if item == nil then return end
        local tn = item.typeName or ""
        if not (string.starts_with(tn, "ActivatedAbility") and string.ends_with(tn, "Behavior")) then
            return
        end
        local copy = DeepCopy(item)
        copy.guid = dmhub.GenerateGuid()
        ability.behaviors[#ability.behaviors + 1] = copy
        fireChange()
    end

    local pasteButton = nil
    pasteButton = gui.Button{
        text = "Paste Behavior",
        width = 160,
        height = 34,
        halign = "center",
        classes = {cond(not _clipboardHasBehavior(), "collapsed-anim")},
        press = function()
            _pasteBehavior()
        end,
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not _clipboardHasBehavior())
        end,
        -- Fires when the internal clipboard changes (e.g. user copies a
        -- behavior while this editor is open). Keeps the button's visibility
        -- in sync without requiring the editor to be closed and reopened.
        internalClipboardChanged = function(element)
            element:SetClass("collapsed-anim", not _clipboardHasBehavior())
        end,
    }

    effectsBottomBar = gui.Panel{
        id = "effectsBottomBar",
        classes = {"nae-effects-bottom-bar", "collapsed"},
        flow = "horizontal",
        children = {
            gui.Button{
                text = "+ Add Behavior",
                width = 160,
                height = 34,
                halign = "center",
                press = function()
                    AbilityEditor.OpenBehaviorPicker(ability, function(typeId)
                        local typeEntry = ActivatedAbility.TypesById[typeId]
                        if typeEntry and typeEntry.createBehavior then
                            ability.behaviors[#ability.behaviors + 1] = typeEntry.createBehavior()
                            AbilityEditor._trackRecentBehavior(typeId)
                            fireChange()
                        end
                    end)
                end,
            },
            pasteButton,
        },

        refreshAbility = function(element)
            local hideMono = #(ability.behaviors or {}) == 1
                and ability.behaviors[1] ~= nil
                and ability.behaviors[1].mono == true
            element:SetClass("collapsed", element:HasClass("nae-not-effects") or hideMono)
        end,
    }

    detailCol = gui.Panel{
        classes = {"nae-detail-col"},
        id = "detailCol",
        -- Fills the remaining width between nav (fixed) and preview (fixed).
        -- 8px border budget matches the nav + preview + border allowance.
        width = string.format("100%%-%d", LAYOUT.NAV_WIDTH + LAYOUT.PREVIEW_WIDTH + 8),
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        -- Padding moved to detailScroll so the scrollbar sits inside the
        -- padded area. The bottom bar gets its own horizontal padding.
        borderBox = true,
        children = {detailScroll, effectsBottomBar},
    }

    previewCol, previewSlot = _makePreview(ability, _schedulePreviewRefresh)

    local bodyRow = gui.Panel{
        id = "bodyRow",
        width = "100%",
        height = string.format("100%%-%d", LAYOUT.TITLE_HEIGHT + 12),
        flow = "horizontal",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        borderBox = true,
        children = {
            navCol,
            detailCol,
            previewCol,
        },
    }

    local titleStrip = gui.Panel{
        classes = {"nae-title-strip"},
        children = {
            gui.Label{
                classes = {"nae-title-label"},
                text = ability.name or "(unnamed ability)",
                refreshAbility = function(element)
                    element.text = ability.name or "(unnamed ability)"
                end,
            },
            gui.Label{
                classes = {"nae-subtitle-label"},
                text = "Ability Editor",
            },
        },
    }

    rootPanel = gui.Panel{
        classes = {"nae-root"},
        id = "abilityEditorRoot",
        styles = _editorStyles(),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
        borderBox = true,
        -- No root-level padding: the outer compendium dialog already pads
        -- around us, and any root hpad here would subtract from the inner
        -- area that nav+detail+preview column widths are computed against.
        hpad = 0,
        vpad = 0,
        bgcolor = COLORS.BG,
        bgimage = "panels/square.png",
        borderWidth = 2,
        borderColor = COLORS.GOLD,
        cornerRadius = 6,
        data = {
            ability = ability,
            selectedSectionId = SECTIONS[1].id,
        },
        children = {
            titleStrip,
            gui.MCDMDivider{
                layout = "line",
                width = "100%",
                bmargin = 6,
            },
            bodyRow,
        },
    }

    -- Initial selection + initial preview render.
    selectSection(SECTIONS[1].id)
    if previewSlot ~= nil then
        previewSlot:FireEvent("refreshPreview")
    end

    -- Entry modal: show on first edit of a newly created ability. The flag
    -- is set by the patched ActivatedAbility.Create and is transient (_tmp_
    -- prefix = not serialized). Clearing it here prevents the modal from
    -- re-appearing if GenerateEditor is called again on the same object.
    if ability:try_get("_tmp_isNewAbility", false) then
        ability._tmp_isNewAbility = false
        -- Rebuild callback: after applying a template/duplicate, the editor
        -- panels need to be reconstructed because dropdowns and inputs bake
        -- their initial values at creation time. We replace rootPanel in its
        -- parent (the mainFormPanel from ShowEditActivatedAbilityDialog).
        local function rebuildEditor()
            local parent = rootPanel.parent
            if parent ~= nil then
                parent.children = {
                    AbilityEditor.GenerateEditor(ability),
                }
            end
        end
        -- Schedule the modal to appear after the panel is attached to the
        -- tree (ShowModal needs the root to exist).
        dmhub.Schedule(0, function()
            if mod.unloaded then return end
            AbilityEditor.ShowEntryModal(ability, rootPanel, rebuildEditor)
        end)
    end

    return rootPanel
end
