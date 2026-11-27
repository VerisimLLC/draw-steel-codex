local mod = dmhub.GetModLoading()

--[[
    Block Editor proofs: a developer-only window (/blockproofs) that checks,
    in the app, the five things the editor's design depends on before blocks
    are built on them (plan section 7, phase 0):

      1. Drag      a ghost takes over a shelf drag; the drop slot comes from the pointer
      2. Sentence  one label with many link words, hover and menus, at 80-140% text
      3. Blocks    fixed colours with glyphs, hover and selected, in every scheme
      4. Card      the book-style ability card's fonts and tier marks
      5. Count     how long N blocks take to build, and how many panels they are

    Each proof says on screen what to look for. This file is throwaway: the
    real panels (Stack, BlockPanel, SidePanel) replace it from phase 1.
]]

local T = UIText.T

--- @class BEProofs
BEProofs = {}

--The class on the proofs window; the drag ghost is parented to it.
local ROOT_CLASS = "beProofsRoot"

--- A small button in a proof's row of controls.
--- @param text string
--- @param click fun(element: Panel)
--- @return Panel
local function _control(text, click)
    return gui.Button{
        classes = {"sizeS"},
        width = "auto",
        hpad = 10,
        rmargin = 6,
        bmargin = 6,
        text = text,
        click = click,
    }
end

--- A wrapping row of controls.
--- @param children Panel[]
--- @return Panel
local function _controlRow(children)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        children = children,
    }
end

--- A panel's top edge in screen space (y runs up; positionInScreenSpace is
--- the panel's centre).
--- @param panel Panel
--- @return number
local function _top(panel)
    return panel.positionInScreenSpace.y + panel.renderedHeight / 2
end

----------------------------------------------------------------------------
-- 1. Drag
-- The engine finds drop targets under the DRAGGED PANEL, so a shelf row that
-- stays put never reaches a slot: it hands its drag to a floating ghost. The
-- landing slot comes from the pointer against block midpoints measured once.
----------------------------------------------------------------------------

local DRAG = {
    VIEW_HEIGHT = 250,      -- the stack's viewport: short, so six blocks already scroll
    START_BLOCKS = 6,
    TICK = 0.03,            -- how often the ghost re-checks the slot and scrolls
    SETTLE = 0.1,           -- seconds to let the dashed slots lay out before measuring
    HYSTERESIS = 6,         -- pixels past a midpoint before the slot changes
    EDGE = 30,              -- auto-scroll starts this close to the viewport's top or bottom
    SCROLL_STEP = 9,        -- pixels scrolled per tick at the edge
    GRAB_X = 14,            -- where on the ghost the pointer holds it
    GHOST_HALF_HEIGHT = 16,
}

--- A drag under way in the Drag proof.
--- @class BEProofDrag
--- @field blockId string the block being dragged from the shelf
--- @field ghost Panel the floating copy that carries the drag
--- @field started number dmhub.Time() when the drag began
--- @field mids nil|number[] each stack block's midpoint, down from the first slot's top, measured with every slot dashed
--- @field slotTops nil|number[] each slot's top edge in the same units; index 1 is the slot above the first block
--- @field hintHeight number a dashed slot's height when measured
--- @field slot nil|integer the slot the block would land in: 0 (above the first block) to #blocks; nil when outside the stack
--- @field engineOver boolean whether the engine reports the ghost over the stack (its own drag-target test)

--- @return Panel
local function _dragProof()
    --- @type string[] the stack's blocks, top to bottom
    local m_blocks = {}
    for i, decl in ipairs(Block.All("block")) do
        if i > DRAG.START_BLOCKS then
            break
        end
        m_blocks[#m_blocks + 1] = decl.id
    end

    --- @type Panel the stack's scrolling viewport, and the engine's drag target
    local m_stack
    --- @type Panel[] slot panels; index 1 is the slot above the first block
    local m_slots = {}
    --- @type Panel[] block panels, top to bottom
    local m_blockPanels = {}
    --- @type Panel
    local m_status
    --- @type nil|BEProofDrag
    local m_drag = nil

    --- Builds the stack's children from m_blocks: slot, block, slot, ... slot.
    --- A real stack edits its panels in place; a proof can rebuild.
    local function Rebuild()
        local children = {}
        m_slots = {}
        m_blockPanels = {}
        local function AddSlot()
            local slot = gui.Panel{
                classes = {"beSlot"},
                interactable = false,
                gui.Label{
                    classes = {"beSlotLabel"},
                    text = T("blockeditor.proofs.drag.drop_here"),
                    interactable = false,
                },
            }
            m_slots[#m_slots + 1] = slot
            children[#children + 1] = slot
        end
        AddSlot()
        for _, blockId in ipairs(m_blocks) do
            local decl = Block.GetBlock(blockId)
            if decl ~= nil then
                local panel = BEStyles.BlockPanel{
                    group = decl.group,
                    text = Block.SentenceText(decl),
                }
                m_blockPanels[#m_blockPanels + 1] = panel
                children[#children + 1] = panel
                AddSlot()
            end
        end
        m_stack.children = children
    end

    --- Shows which slot is open (or none), and the dashed hint on the rest.
    --- @param hint boolean whether a drag is under way
    --- @param open nil|integer the slot to open, 0-based
    local function PaintSlots(hint, open)
        for i, slot in ipairs(m_slots) do
            if slot.valid then
                slot:SetClass("beSlotHint", hint)
                slot:SetClass("beSlotOpen", open ~= nil and i == open + 1)
            end
        end
    end

    --- @param drag nil|BEProofDrag
    --- @param pointerY nil|number
    local function PaintStatus(drag, pointerY)
        if drag == nil then
            m_status.text = T("blockeditor.proofs.drag.status_idle", { count = #m_blocks })
            return
        end
        m_status.text = T("blockeditor.proofs.drag.status", {
            slot = drag.slot ~= nil and tostring(drag.slot) or "-",
            engine = drag.engineOver and T("blockeditor.proofs.yes") or T("blockeditor.proofs.no"),
            y = pointerY ~= nil and string.format("%d", math.floor(pointerY)) or "-",
        })
    end

    --- Measures the blocks once the dashed slots have laid out and before any
    --- slot opens, so later ticks compare the pointer with a layout that
    --- does not move.
    --- @param drag BEProofDrag
    local function Measure(drag)
        local ref = _top(m_slots[1])
        local mids, slotTops = {}, {}
        for i, panel in ipairs(m_blockPanels) do
            mids[i] = ref - panel.positionInScreenSpace.y
        end
        for i, slot in ipairs(m_slots) do
            slotTops[i] = ref - _top(slot)
        end
        drag.mids = mids
        drag.slotTops = slotTops
        drag.hintHeight = m_slots[1].renderedHeight
    end

    --- The slot for a pointer height, with hysteresis: the slot only changes
    --- once the pointer is HYSTERESIS pixels past the next block's midpoint.
    --- @param drag BEProofDrag
    --- @param y number the pointer, down from the first slot's top, in the measured layout
    --- @return integer
    local function SlotAt(drag, y)
        local mids = drag.mids or {}
        local slot = drag.slot
        if slot == nil then
            slot = 0
            for i, mid in ipairs(mids) do
                if y > mid then
                    slot = i
                end
            end
            return slot
        end
        while slot < #mids and y > mids[slot + 1] + DRAG.HYSTERESIS do
            slot = slot + 1
        end
        while slot > 0 and y < mids[slot] - DRAG.HYSTERESIS do
            slot = slot - 1
        end
        return slot
    end

    --- One step of a drag: scroll if the pointer is near an edge, then pick
    --- the slot under it. Runs from the ghost's think and its dragging event.
    --- @param ghost Panel
    local function Tick(ghost)
        local drag = m_drag
        if drag == nil or mod.unloaded or not ghost.valid or not m_stack.valid then
            return
        end
        if drag.mids == nil then
            if dmhub.Time() - drag.started < DRAG.SETTLE then
                return
            end
            Measure(drag)
        end
        local slotTops = drag.slotTops or {}

        --the ghost is held near its left edge, so its centre height and its
        --left edge are where the pointer is.
        local ghostPos = ghost.positionInScreenSpace
        local pointerX = ghostPos.x - ghost.renderedWidth / 2 + DRAG.GRAB_X
        local pointerY = ghostPos.y

        local stackPos = m_stack.positionInScreenSpace
        local viewTop = _top(m_stack)
        local viewBottom = viewTop - m_stack.renderedHeight
        local inside = pointerY <= viewTop + DRAG.EDGE and pointerY >= viewBottom - DRAG.EDGE
            and math.abs(pointerX - stackPos.x) <= m_stack.renderedWidth / 2

        if not inside then
            if drag.slot ~= nil then
                drag.slot = nil
                PaintSlots(true, nil)
            end
            PaintStatus(drag, nil)
            return
        end

        --auto-scroll: vscrollPosition runs 1 (top) to 0 (bottom).
        local last = m_slots[#m_slots]
        local scrollable = (_top(m_slots[1]) - (_top(last) - last.renderedHeight)) - m_stack.renderedHeight
        if scrollable > 1 then
            local step = DRAG.SCROLL_STEP / scrollable
            if pointerY > viewTop - DRAG.EDGE then
                m_stack.vscrollPosition = math.min(1, m_stack.vscrollPosition + step)
            elseif pointerY < viewBottom + DRAG.EDGE then
                m_stack.vscrollPosition = math.max(0, m_stack.vscrollPosition - step)
            end
        end

        --the pointer in the measured layout: an open slot is taller than it
        --was when measured, so take its extra height back out below it.
        local y = _top(m_slots[1]) - pointerY
        if drag.slot ~= nil then
            local openPanel = m_slots[drag.slot + 1]
            local openTop = slotTops[drag.slot + 1] or 0
            local extra = math.max(0, openPanel.renderedHeight - drag.hintHeight)
            if y > openTop + drag.hintHeight + extra then
                y = y - extra
            elseif y > openTop then
                y = openTop
            end
        end

        local slot = SlotAt(drag, y)
        if slot ~= drag.slot then
            drag.slot = slot
            PaintSlots(true, slot)
        end
        PaintStatus(drag, y)
    end

    --- The drag ended: put the block in the open slot, if there is one.
    --- @param ghost Panel
    local function Drop(ghost)
        local drag = m_drag
        m_drag = nil
        if ghost.valid then
            --not destroyed inside its own drag event: hidden now, removed a moment later.
            ghost.thinkTime = nil
            ghost:SetClass("collapsed", true)
            ghost:ScheduleEvent("removeGhost", 0.05)
        end
        if drag ~= nil and drag.slot ~= nil then
            table.insert(m_blocks, drag.slot + 1, drag.blockId)
            Rebuild()
        else
            PaintSlots(false, nil)
        end
        PaintStatus(nil, nil)
    end

    --- A shelf row's drag began: make the ghost at the pointer and hand the
    --- drag to it.
    --- @param row Panel the shelf row
    --- @param blockId string
    local function BeginDrag(row, blockId)
        local root = row:FindParentWithClass(ROOT_CLASS)
        local decl = Block.GetBlock(blockId)
        if root == nil or decl == nil then
            return
        end
        --a ghost left over from a drag that never reported its end.
        if m_drag ~= nil and m_drag.ghost.valid then
            m_drag.ghost:DestroySelf()
        end
        m_drag = nil

        --the pointer in the window's own units, from its top-left corner
        --(mousePoint runs 0-1 from the row's bottom-left).
        local rowPos = row.positionInScreenSpace
        local rootPos = root.positionInScreenSpace
        local mouse = row.mousePoint
        local pointerX = (rowPos.x - row.renderedWidth / 2 + mouse.x * row.renderedWidth) - (rootPos.x - root.renderedWidth / 2)
        local pointerY = _top(root) - (rowPos.y - row.renderedHeight / 2 + mouse.y * row.renderedHeight)

        --- @type Panel
        local ghost
        ghost = BEStyles.BlockPanel{
            group = decl.group,
            text = decl.label,
            classes = {"beGhost"},
            textClasses = {"beGhostText"},
            floating = true,
            halign = "left",
            valign = "top",
            x = math.floor(pointerX - DRAG.GRAB_X),
            y = math.floor(pointerY - DRAG.GHOST_HALF_HEIGHT),
            draggable = true,
            dragMove = true,
            --stays a child of the window (it is the last one, so on top), which
            --keeps the window's style rules: they give it its block colour.
            dragInPlace = true,
            --the engine's own target test: the stack as a whole, never a sliver.
            canDragOnto = function(element, target)
                return target:HasClass("beDropArea")
            end,
            thinkTime = DRAG.TICK,
            think = function(element)
                Tick(element)
            end,
            dragging = function(element, target)
                if m_drag ~= nil then
                    m_drag.engineOver = target ~= nil
                end
                Tick(element)
            end,
            drag = function(element, target)
                Drop(element)
            end,
            removeGhost = function(element)
                element:DestroySelf()
            end,
        }

        m_drag = {
            blockId = blockId,
            ghost = ghost,
            started = dmhub.Time(),
            mids = nil,
            slotTops = nil,
            hintHeight = 0,
            slot = nil,
            engineOver = false,
        }
        root:AddChild(ghost)
        ghost:SetAsLastSibling()
        PaintSlots(true, nil)
        row:transferDragTo(ghost)
    end

    local shelfRows = {}
    for _, decl in ipairs(Block.All("block")) do
        --- @cast decl BlockDecl
        shelfRows[#shelfRows + 1] = BEStyles.BlockPanel{
            group = decl.group,
            text = decl.label,
            bmargin = BEStyles.SIZES.BLOCK_GAP,
            data = { block = decl.id },
            draggable = true,
            --the row stays put; the ghost made in beginDrag is what moves.
            dragMove = false,
            dragThreshold = 6,
            beginDrag = function(element)
                BeginDrag(element, element.data.block)
            end,
        }
    end

    m_stack = gui.Panel{
        classes = {"beDropArea"},
        width = "100%",
        height = DRAG.VIEW_HEIGHT,
        flow = "vertical",
        vscroll = true,
        pad = 6,
        borderBox = true,
        dragTarget = true,
    }
    Rebuild()

    m_status = gui.Label{
        classes = {"beNote"},
        tmargin = 8,
        text = T("blockeditor.proofs.drag.status_idle", { count = #m_blocks }),
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.proofs.drag.check"),
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = "100% available",
                height = "auto",
                flow = "vertical",
                rmargin = 16,
                gui.Label{ classes = {"beHeading"}, text = T("blockeditor.proofs.drag.stack") },
                m_stack,
                m_status,
            },
            gui.Panel{
                width = BEStyles.SIZES.SHELF_WIDTH,
                height = "auto",
                flow = "vertical",
                gui.Label{ classes = {"beHeading"}, text = T("blockeditor.proofs.drag.shelf") },
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    children = shelfRows,
                },
            },
        },
    }
end

----------------------------------------------------------------------------
-- 2. Sentence
-- One label; each changeable word is a <link> with a <mark> fill. Hovering
-- swaps the text for one where that word's fill differs (same characters, so
-- nothing moves). Press needs a faint background: glyphs are not a raycast surface.
----------------------------------------------------------------------------

local SENTENCE = {
    FONT_PERCENTS = { 80, 90, 100, 110, 120, 130, 140 },
    WIDTHS = { 320, 520, "100%" },
    NUMBERS = { 1, 2, 3, 5, 10 },
}

--- @return Panel
local function _sentenceProof()
    --every registered block, each with its own slot values: enough sentences
    --for well over six link words and several wrapped lines.
    --- @type BlockInstance[]
    local m_instances = {}
    for _, decl in ipairs(Block.All("block")) do
        local instance = Block.Instantiate(decl.id)
        if instance ~= nil then
            m_instances[#m_instances + 1] = instance
        end
    end
    local firstDecl = m_instances[1] ~= nil and Block.GetBlock(m_instances[1].block) or nil

    --- The label's text, with one word (a link id) shown as hovered.
    --- A link id is "<instance index>:<slot id>".
    --- @param hovered nil|string
    --- @return string
    local function Markup(hovered)
        local FIXED = BEStyles.FIXED
        local sentences = {}
        for i, instance in ipairs(m_instances) do
            local decl = Block.GetBlock(instance.block)
            if decl ~= nil then
                local parts = {}
                for _, run in ipairs(Block.Sentence(decl, instance.values)) do
                    if run.slot ~= nil then
                        local id = string.format("%d:%s", i, run.slot)
                        local fill = id == hovered and FIXED.WORD_HOVER or FIXED.WORD_REST
                        parts[#parts + 1] = string.format("<link=%s><mark=%s><u>%s</u></mark></link>", id, fill, run.text)
                    else
                        parts[#parts + 1] = run.text
                    end
                end
                sentences[#sentences + 1] = table.concat(parts)
            end
        end
        return table.concat(sentences, " ")
    end

    --- The values a slot's menu offers: {value, text} pairs.
    --- @param slot BlockSlot
    --- @return {value: any, text: string}[]
    local function Choices(slot)
        local result = {}
        if slot.kind == "choice" then
            for _, option in ipairs(slot.options or {}) do
                result[#result + 1] = { value = option.id, text = option.text }
            end
        elseif slot.kind == "number" then
            for _, n in ipairs(SENTENCE.NUMBERS) do
                result[#result + 1] = { value = n, text = tostring(n) }
            end
        elseif slot.kind == "stat" then
            for _, stat in ipairs(Block.All("stat")) do
                result[#result + 1] = { value = stat.id, text = stat.words }
            end
        elseif slot.kind == "test" then
            for _, test in ipairs(Block.All("test")) do
                result[#result + 1] = { value = test.id, text = test.prose }
            end
        end
        return result
    end

    --- Opens the menu for a word at the pointer.
    --- @param label Label
    --- @param link string
    local function OpenMenu(label, link)
        local index, slotId = string.match(link, "^(%d+):(.+)$")
        local instance = m_instances[tonumber(index) or 0]
        local decl = instance ~= nil and Block.GetBlock(instance.block) or nil
        local slot = decl ~= nil and decl.slots ~= nil and decl.slots[slotId] or nil
        if instance == nil or slot == nil then
            return
        end

        --- @type ContextMenuEntry[]
        local entries = {}
        for _, choice in ipairs(Choices(slot)) do
            entries[#entries + 1] = {
                text = choice.text,
                check = instance.values[slotId] == choice.value,
                click = function()
                    instance.values[slotId] = choice.value
                    label.text = Markup(nil)
                end,
            }
        end
        if #entries == 0 then
            --a text slot: in the editor this is a small input popup at the word.
            entries[1] = { text = T("blockeditor.proofs.sentence.no_choices"), disabled = true }
        end

        label.popupsInheritStyles = true
        label.popupPositioning = "mouse"
        label.popup = gui.ContextMenu{
            entries = entries,
            click = function()
                label.popup = nil
            end,
        }
    end

    --- @type Label
    local m_label
    m_label = gui.Label{
        classes = {"beBlockText"},
        width = "100%",
        links = true,
        --the raycast backing; see the note above.
        bgimage = "panels/square.png",
        bgcolor = "#00000001",
        text = Markup(nil),
        hoverLink = function(element, link)
            element.text = Markup(link)
        end,
        dehoverLink = function(element, link)
            element.text = Markup(nil)
        end,
        press = function(element)
            local link = element.linkHovered
            if link ~= nil and link ~= "" then
                OpenMenu(element, link)
            end
        end,
    }

    --- @type Panel
    local m_block
    m_block = gui.Panel{
        classes = {"beBlock", firstDecl ~= nil and BEStyles.GroupClass(firstDecl.group) or nil},
        width = SENTENCE.WIDTHS[2],
        m_label,
    }

    --- @type Panel
    local m_sizeNote
    m_sizeNote = gui.Label{
        classes = {"beNote"},
        text = T("blockeditor.proofs.sentence.size", { percent = 100 }),
    }

    local fontButtons = {}
    for _, percent in ipairs(SENTENCE.FONT_PERCENTS) do
        fontButtons[#fontButtons + 1] = _control(string.format("%d%%", percent), function(element)
            --a computed size with no fixed set of variants, so selfStyle.
            m_label.selfStyle.fontSize = BEStyles.SIZES.BLOCK_FONT_SIZE * percent / 100
            m_sizeNote.text = T("blockeditor.proofs.sentence.size", { percent = percent })
        end)
    end
    local widthButtons = {}
    for _, width in ipairs(SENTENCE.WIDTHS) do
        widthButtons[#widthButtons + 1] = _control(T("blockeditor.proofs.sentence.width", { width = tostring(width) }), function(element)
            m_block.selfStyle.width = width
        end)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.proofs.sentence.check"),
        },
        _controlRow(fontButtons),
        _controlRow(widthButtons),
        m_sizeNote,
        m_block,
    }
end

----------------------------------------------------------------------------
-- 3. Blocks
-- One block per colour group: a literal colour and a precomputed hover colour
-- in style rules (an inline bgcolor would beat hover), "selected" as a ring.
-- Switching the colour scheme must change nothing about the blocks.
----------------------------------------------------------------------------

local BLOCKS = {
    WIDTH = 300,
}

--- @return Panel
local function _blocksProof()
    --the scheme the user had, put back when the proofs close.
    local originalScheme = ThemeEngine.GetActiveColorScheme()

    local blocks = {}
    for _, group in ipairs(Block.All("group")) do
        --- @cast group BlockGroup
        blocks[#blocks + 1] = BEStyles.BlockPanel{
            group = group.id,
            text = string.format("%s  %s", group.text, group.color),
            width = BLOCKS.WIDTH,
            rmargin = 8,
            bmargin = 8,
            press = function(element)
                element:SetClass("selected", not element:HasClass("selected"))
            end,
            setNoFit = function(element, value)
                element:SetClass("beNoFit", value)
            end,
        }
    end

    --- @type Panel
    local m_blocks
    m_blocks = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        data = { noFit = false },
        children = blocks,
    }

    local schemes = ThemeEngine.ListColorSchemes()
    table.sort(schemes, function(a, b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
    local controls = {}
    for _, scheme in ipairs(schemes) do
        controls[#controls + 1] = _control(tostring(scheme.name or scheme.id), function(element)
            ThemeEngine.SetActiveColorScheme(scheme.id)
        end)
    end
    controls[#controls + 1] = _control(T("blockeditor.proofs.blocks.no_fit"), function(element)
        m_blocks.data.noFit = not m_blocks.data.noFit
        m_blocks:FireEventTree("setNoFit", m_blocks.data.noFit)
    end)

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        destroy = function(element)
            ThemeEngine.SetActiveColorScheme(originalScheme)
        end,
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.proofs.blocks.check"),
        },
        _controlRow(controls),
        m_blocks,
    }
end

----------------------------------------------------------------------------
-- 4. Card
-- The book's layout on fixed paper and ink: the Book font, tier marks from the
-- DrawSteelGlyphs font ("!", "@", "#" are tiers 1-3) and a <mark> chip.
-- Modelled on ui-mockup/lua-preview/ability.html.
----------------------------------------------------------------------------

local CARD = {
    WIDTH = 340,
    FONT = "Book",
    GLYPH_FONT = "DrawSteelGlyphs",
    TIER_GLYPHS = { "!", "@", "#" },
    MARK = 10,
    TIER_GLYPH_WIDTH = 46,
}

--- One line of card text in the book font.
--- @param args table gui.Label fields
--- @return Panel
local function _cardText(args)
    args.classes = {"beCardText"}
    --inline, as the codex's other Book labels: MergeStyles checks font names
    --against the theme's list and would swap an unknown one for the default.
    args.fontFace = CARD.FONT
    args.width = args.width or "100%"
    return gui.Label(args)
end

--- @return Panel
local function _cardProof()
    local chip = string.format("<mark=%s><b> %s </b></mark>", BEStyles.FIXED.CHIP, T("blockeditor.proofs.card.chip"))

    local marks = {}
    for i = 1, 3 do
        marks[i] = gui.Panel{
            classes = {"beCardMark"},
            bgimage = "phosphor/diamond.png",
            width = CARD.MARK,
            height = CARD.MARK,
            bmargin = 2,
        }
    end

    local tierTexts = {
        T("blockeditor.proofs.card.tier1", { chip = chip }),
        T("blockeditor.proofs.card.tier2", { chip = chip }),
        T("blockeditor.proofs.card.tier3", { chip = chip }),
    }
    local tiers = {}
    for i, glyph in ipairs(CARD.TIER_GLYPHS) do
        tiers[i] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 3,
            gui.Label{
                classes = {"beCardText"},
                fontFace = CARD.GLYPH_FONT,
                fontSize = 26,
                width = CARD.TIER_GLYPH_WIDTH,
                height = "auto",
                valign = "center",
                text = glyph,
            },
            _cardText{
                width = "100% available",
                valign = "center",
                text = tierTexts[i],
            },
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.proofs.card.check"),
        },
        gui.Panel{
            classes = {"beCard"},
            width = CARD.WIDTH,

            --the ruled header: diamond marks, name, flavour, keywords and action.
            gui.Panel{
                classes = {"beCardRule"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bgimage = true,
                bgcolor = "clear",
                vpad = 6,
                borderBox = true,
                bmargin = 6,
                gui.Panel{
                    width = CARD.MARK,
                    height = "auto",
                    flow = "vertical",
                    rmargin = 8,
                    tmargin = 4,
                    children = marks,
                },
                gui.Panel{
                    width = "100% available",
                    height = "auto",
                    flow = "vertical",
                    _cardText{ fontSize = 18, bold = true, text = T("blockeditor.proofs.card.name") },
                    --Labels have no italic property; rich-text tags do it.
                    _cardText{ text = "<i>" .. T("blockeditor.proofs.card.flavor") .. "</i>" },
                    gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        tmargin = 2,
                        _cardText{ width = "auto", bold = true, halign = "left", text = T("blockeditor.proofs.card.keywords") },
                        _cardText{ width = "auto", bold = true, halign = "right", text = T("blockeditor.proofs.card.action") },
                    },
                    gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        _cardText{ width = "auto", halign = "left", text = T("blockeditor.proofs.card.distance") },
                        _cardText{ width = "auto", halign = "right", text = T("blockeditor.proofs.card.target") },
                    },
                },
            },

            _cardText{ bold = true, text = T("blockeditor.proofs.card.roll") },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = tiers,
            },
            _cardText{ tmargin = 6, text = T("blockeditor.proofs.card.effect") },
        },
    }
end

----------------------------------------------------------------------------
-- 5. Count
-- A block is about six panels, so a large record is a few hundred. Blocks are
-- direct children of the scroll panel, which is all hideObjectsOutOfScroll skips.
----------------------------------------------------------------------------

local COUNT = {
    SIZES = { 20, 100, 300 },
    VIEW_HEIGHT = 380,
    ICON = "14sp",
}

--- @return Panel
local function _countProof()
    local decls = Block.All("block")

    --- @type Panel
    local m_list
    m_list = gui.Panel{
        classes = {"beDropArea"},
        width = "100%",
        height = COUNT.VIEW_HEIGHT,
        flow = "vertical",
        vscroll = true,
        hideObjectsOutOfScroll = true,
        pad = 6,
        borderBox = true,
    }

    --- @type Panel
    local m_result
    m_result = gui.Label{
        classes = {"beNote"},
        text = T("blockeditor.proofs.count.idle"),
    }

    --- Builds `count` blocks and reports the time and the panel count.
    --- @param count integer
    local function Build(count)
        if #decls == 0 then
            return
        end
        local watch = dmhub.Stopwatch()
        local panels = 0
        local children = {}
        for i = 1, count do
            --- @type BlockDecl
            local decl = decls[(i - 1) % #decls + 1]
            local glyph = BEStyles.Glyph(decl.group)
            local row = {}
            row[#row + 1] = gui.Panel{
                classes = {"beGlyph"},
                bgimage = "phosphor/dots-three-vertical-bold.png",
                interactable = false,
            }
            if glyph ~= nil then
                row[#row + 1] = glyph
                panels = panels + 1
            end
            row[#row + 1] = gui.Label{
                classes = {"beBlockText"},
                text = string.format("%d. %s", i, Block.SentenceText(decl)),
                interactable = false,
            }
            row[#row + 1] = gui.Panel{
                classes = {"beGlyph"},
                bgimage = "phosphor/gear-six-fill.png",
                rmargin = 0,
            }
            children[#children + 1] = gui.Panel{
                classes = {"beBlock", BEStyles.GroupClass(decl.group)},
                children = row,
            }
            children[#children + 1] = gui.Panel{
                classes = {"beSlot"},
                interactable = false,
            }
            --the block, its grip, sentence and menu, and the slot under it.
            panels = panels + 5
        end
        m_list.children = children
        m_result.text = T("blockeditor.proofs.count.result", {
            blocks = count,
            panels = panels,
            ms = string.format("%.1f", watch.milliseconds),
        })
    end

    local controls = {}
    for _, count in ipairs(COUNT.SIZES) do
        controls[#controls + 1] = _control(T("blockeditor.proofs.count.build", { count = count }), function(element)
            Build(count)
        end)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.proofs.count.check"),
        },
        _controlRow(controls),
        m_result,
        m_list,
    }
end

----------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------

--- The proofs, in tab order: each tab's title and what builds it.
--- @type {id: string, title: string, build: fun(): Panel}[]
local PROOFS = {
    { id = "drag", title = T("blockeditor.proofs.tab.drag"), build = _dragProof },
    { id = "sentence", title = T("blockeditor.proofs.tab.sentence"), build = _sentenceProof },
    { id = "blocks", title = T("blockeditor.proofs.tab.blocks"), build = _blocksProof },
    { id = "card", title = T("blockeditor.proofs.tab.card"), build = _cardProof },
    { id = "count", title = T("blockeditor.proofs.tab.count"), build = _countProof },
}

--- Opens the proofs window, as a modal.
--- @return Panel
function BEProofs.Open()
    Block.Gather()

    local SIZES = BEStyles.SIZES
    --- @type table|nil the theme subscription, dropped when the window closes
    local themeSub = nil

    local tabs = {}
    local sections = {}
    for i, proof in ipairs(PROOFS) do
        tabs[i] = gui.Label{
            classes = {"tab", cond(i == 1, "selected")},
            text = proof.title,
            data = { proof = proof.id },
            press = function(element)
                local root = element:FindParentWithClass(ROOT_CLASS)
                if root ~= nil then
                    root:FireEventTree("showProof", element.data.proof)
                end
            end,
            showProof = function(element, proofId)
                element:SetClass("selected", element.data.proof == proofId)
            end,
        }
        sections[i] = gui.Panel{
            classes = {cond(i ~= 1, "collapsed")},
            width = "100%",
            height = "auto",
            --top: a vertical list centres each row in its share of spare height.
            valign = "top",
            flow = "vertical",
            data = { proof = proof.id, built = false },
            --each proof is built the first time it is shown.
            showProof = function(element, proofId)
                local shown = element.data.proof == proofId
                element:SetClass("collapsed", not shown)
                if shown and not element.data.built then
                    element.data.built = true
                    element.children = { proof.build() }
                end
                --only this panel's children are a proof: nothing below needs the event.
                element:HaltEventPropagation()
            end,
        }
    end

    --- @type Panel
    local root
    root = gui.Panel{
        classes = {"framedPanel", ROOT_CLASS},
        styles = ThemeEngine.MergeStyles(BEStyles.GetStyles()),
        width = SIZES.WINDOW_WIDTH,
        height = SIZES.WINDOW_HEIGHT,
        maxWidth = SIZES.WINDOW_MAX_WIDTH,
        maxHeight = SIZES.WINDOW_MAX_HEIGHT,
        halign = "center",
        valign = "center",
        flow = "vertical",
        pad = SIZES.WINDOW_PAD,
        borderBox = true,

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            gui.CloseModal()
        end,

        create = function(element)
            themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(BEStyles.GetStyles())
                end
            end)
            element:FireEventTree("showProof", PROOFS[1].id)
        end,
        destroy = function(element)
            if themeSub ~= nil then
                themeSub:Deregister()
                themeSub = nil
            end
        end,

        gui.Panel{
            classes = {"beTitleBar"},
            gui.Label{
                classes = {"sizeXl", "bold"},
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 16,
                text = T("blockeditor.proofs.title"),
            },
            gui.Panel{
                classes = {"tabBar"},
                halign = "left",
                valign = "center",
                children = tabs,
            },
            gui.Button{
                classes = {"closeButton", "sizeS"},
                halign = "right",
                valign = "center",
                click = function(element)
                    gui.CloseModal()
                end,
            },
        },
        gui.Panel{
            classes = {"beColumn"},
            width = "100%",
            height = "100% available",
            gui.Panel{
                classes = {"beScroll"},
                vscroll = true,
                children = sections,
            },
        },
    }

    gui.ShowModal(root)
    return root
end

Commands.RegisterMacro{
    name = "blockproofs",
    summary = "open the Block Editor proofs (developers)",
    doc = "Usage: /blockproofs\nOpens the Block Editor's phase 0 proofs: the drag ghost and drop slots, a sentence of link words, the fixed block colours, the book-style card and the panel count. Developer mode only.",
    command = function(str)
        if not BlockEditor._isDeveloper() then
            dmhub.Log("The Block Editor is in development: turn on developer mode to open its proofs.")
            return
        end
        BEProofs.Open()
    end,
}
