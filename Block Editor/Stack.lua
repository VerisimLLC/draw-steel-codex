local mod = dmhub.GetModLoading()

--[[
    BEStack: a list of placed blocks with a drop sliver before, between and
    after them, and the drag that fills those slivers.

    A stack keeps one panel per block (by uid) and only builds panels for
    blocks it has not seen; "refreshStack" re-orders them and hands each its
    current instance.

    Dragging (from a shelf row, or a block's grip):
      * The engine finds drop targets under the DRAGGED panel, so the source
        stays put and hands its drag to a small floating ghost
        (transferDragTo), as proven in Proofs.lua.
      * Every sliver of the matching kind ("step" or "tier") turns into a
        dashed slot; the others stay 2px. The one nearest the pointer, in the
        column under it, opens to "Drop here".
      * Letting go inserts the block there as one undo step.
]]

local T = UIText.T

--- @class BEStack
BEStack = {}

local DRAG = {
    TICK = 0.03,
    REACH = 28,          -- how far (px) from a slot the pointer may be and still open it
    STICK = 10,          -- an open slot keeps the drop until the pointer is this far outside it
    EDGE = 36,           -- auto-scroll starts this close to the detail column's top or bottom
    SCROLL_STEP = 0.015, -- vscrollPosition per tick at the edge
    GRAB_X = 14,
    GHOST_HALF_HEIGHT = 16,
}

--- A drag under way.
--- @class BEDrag
--- @field source {blockId: string, moveUid?: string}
--- @field fits string[] the kinds of list the block may go in
--- @field ghost Panel
--- @field slivers Panel[] the slivers it may drop on
--- @field open Panel|nil the sliver that is open
--- @field controller Panel

--- @type BEDrag|nil
local g_drag = nil
--- When the last drag ended, so the click that ends a drag adds nothing.
local g_dragEnded = -1

--- A panel's rectangle in screen space (y runs up; positions are centres).
--- @param panel Panel
--- @return number left, number right, number bottom, number top
local function _rect(panel)
    local pos = panel.positionInScreenSpace
    local halfW, halfH = panel.renderedWidth / 2, panel.renderedHeight / 2
    return pos.x - halfW, pos.x + halfW, pos.y - halfH, pos.y + halfH
end

--- Whether a block may go in a list of a kind.
--- @param fits string[]
--- @param kind string
--- @return boolean
local function _fitsKind(fits, kind)
    if #fits == 0 then
        return true
    end
    for _, candidate in ipairs(fits) do
        if candidate == kind then
            return true
        end
    end
    return false
end

--- Whether a drag that just ended should swallow the click that follows it.
--- @return boolean
function BEStack.JustDragged()
    return dmhub.Time() - g_dragEnded < 0.25
end

--- One sliver: 2px at rest; a dashed slot while a block that fits is dragged.
--- @param ref BEListRef
--- @param index integer where a block dropped here goes (1 = first)
--- @param kind string
--- @param full boolean the list holds as many blocks as it may (BlockBody.max): nothing drops here
--- @return Panel
local function _sliver(ref, index, kind, full)
    return gui.Panel{
        classes = {"beSliver"},
        interactable = false,
        data = { ref = ref, index = index, kind = kind, full = full },
        dragHint = function(element, fits)
            element:SetClass("beSliverHint", fits ~= nil and not element.data.full and _fitsKind(fits, element.data.kind))
            if fits == nil then
                element:SetClass("beSliverOpen", false)
            end
        end,
        collectSlivers = function(element, list, fits)
            if not element.data.full and _fitsKind(fits, element.data.kind) then
                list[#list + 1] = element
            end
        end,
        gui.Label{
            classes = {"beSliverLabel"},
            text = T("blockeditor.drop_here"),
            interactable = false,
        },
    }
end

--- Builds a stack. The caller sends it "refreshStack" with its list.
--- @param args {ref: BEListRef, fits: string, max?: integer, classes?: string[], width?: string|number}
--- @return Panel
function BEStack.Create(args)
    local ref = args.ref
    local kind = args.fits
    local max = args.max
    --- @type table<string, Panel> block panels by uid
    local panels = {}
    local classes = {"beStack"}
    if args.classes == nil and args.width == nil then
        args.width = "100%"
    end
    for _, class in ipairs(args.classes or {}) do
        classes[#classes + 1] = class
    end

    return gui.Panel{
        classes = classes,
        --inline only when given: an inline width beats the classes' own widths.
        width = args.width,
        height = "auto",
        flow = "vertical",
        valign = "top",
        data = { ref = ref },

        --- Puts the stack's panels in the list's order, building new ones.
        --- @param list BlockInstance[]
        refreshStack = function(element, list)
            local full = max ~= nil and #(list or {}) >= max
            local children = { _sliver(ref, 1, kind, full) }
            local seen = {}
            for index, instance in ipairs(list or {}) do
                local uid = instance.uid
                if uid ~= nil then
                    seen[uid] = true
                    --- @type Panel|nil
                    local panel = panels[uid]
                    if panel == nil or not panel.valid then
                        panel = BEBlockPanel.Create(instance)
                        panels[uid] = panel
                    else
                        panel:FireEvent("refreshBlock", instance)
                    end
                    if panel ~= nil then
                        children[#children + 1] = panel
                        children[#children + 1] = _sliver(ref, index + 1, kind, full)
                    end
                end
            end
            for uid, panel in pairs(panels) do
                if not seen[uid] then
                    panels[uid] = nil
                end
            end
            element.children = children
        end,
    }
end

--- Opens one sliver (or none) and closes the rest.
--- @param drag BEDrag
--- @param sliver Panel|nil
local function _open(drag, sliver)
    if drag.open == sliver then
        return
    end
    if drag.open ~= nil and drag.open.valid then
        drag.open:SetClass("beSliverOpen", false)
    end
    drag.open = sliver
    if sliver ~= nil then
        sliver:SetClass("beSliverOpen", true)
    end
end

--- One step of a drag: scroll near the detail column's edges, then open the
--- sliver nearest the pointer in the column under it.
local function _tick()
    local drag = g_drag
    if drag == nil or mod.unloaded or not drag.ghost.valid then
        return
    end
    local ghost = drag.ghost
    local ghostPos = ghost.positionInScreenSpace
    local pointerX = ghostPos.x - ghost.renderedWidth / 2 + DRAG.GRAB_X
    local pointerY = ghostPos.y

    --auto-scroll the detail column: vscrollPosition runs 1 (top) to 0 (bottom).
    local detail = drag.controller:Get("beDetailScroll")
    if detail ~= nil and detail.valid then
        local left, right, bottom, top = _rect(detail)
        if pointerX >= left and pointerX <= right then
            if pointerY > top - DRAG.EDGE and pointerY <= top + DRAG.EDGE then
                detail.vscrollPosition = math.min(1, detail.vscrollPosition + DRAG.SCROLL_STEP)
            elseif pointerY < bottom + DRAG.EDGE and pointerY >= bottom - DRAG.EDGE then
                detail.vscrollPosition = math.max(0, detail.vscrollPosition - DRAG.SCROLL_STEP)
            end
        end
    end

    --the open sliver keeps the drop while the pointer stays near it, so the
    --layout shifting as it opens cannot make it flicker.
    if drag.open ~= nil and drag.open.valid then
        local left, right, bottom, top = _rect(drag.open)
        if pointerX >= left and pointerX <= right and pointerY >= bottom - DRAG.STICK and pointerY <= top + DRAG.STICK then
            return
        end
    end

    local best, bestDistance = nil, DRAG.REACH
    for _, sliver in ipairs(drag.slivers) do
        if sliver.valid then
            local left, right, bottom, top = _rect(sliver)
            if pointerX >= left and pointerX <= right then
                local distance = 0
                if pointerY > top then
                    distance = pointerY - top
                elseif pointerY < bottom then
                    distance = bottom - pointerY
                end
                if distance < bestDistance then
                    best, bestDistance = sliver, distance
                end
            end
        end
    end
    _open(drag, best)
end

--- The drag ended: insert the block at the open sliver, if there is one.
--- @param ghost Panel
local function _drop(ghost)
    local drag = g_drag
    g_drag = nil
    g_dragEnded = dmhub.Time()
    if ghost.valid then
        --not destroyed inside its own drag event: hidden now, removed a moment later.
        ghost.thinkTime = nil
        ghost:SetClass("collapsed", true)
        ghost:ScheduleEvent("removeGhost", 0.05)
    end
    if drag == nil then
        return
    end
    local controller = drag.controller
    local target = drag.open
    if controller.valid then
        controller:FireEventTree("dragHint", nil)
    end
    if target == nil or not target.valid or not controller.valid then
        return
    end

    local ref = target.data.ref
    local index = target.data.index
    local source = drag.source
    local decl = Block.GetBlock(source.blockId)
    if decl == nil then
        return
    end
    local description = source.moveUid ~= nil and T("blockeditor.change.move", { block = decl.label }) or T("blockeditor.change.add", { block = decl.label })
    local placedUid = nil
    controller:FireEvent("editorChange", description, function(state)
        --- @cast state BEState
        local model = state:Model()
        if model == nil then
            return
        end
        local instance
        if source.moveUid ~= nil then
            --moving down its own list: the gap it leaves shifts the target up one.
            local _, oldList, oldIndex = BEState.FindInstance(model, source.moveUid)
            local newList = BEState.GetList(model, ref)
            if oldList ~= nil and oldList == newList and oldIndex ~= nil and oldIndex < index then
                index = index - 1
            end
            instance = BEState.Remove(model, source.moveUid)
        else
            instance = Block.Instantiate(source.blockId)
        end
        if instance ~= nil then
            BEState.Insert(model, ref, index, instance)
            placedUid = instance.uid
        end
    end)
    if placedUid ~= nil then
        controller:FireEventTree("flashBlock", placedUid)
    end
end

--- Starts a drag from a shelf row or a block's grip: makes the ghost at the
--- pointer and hands it the drag.
--- @param row Panel the panel the drag began on
--- @param source {blockId: string, moveUid?: string}
function BEStack.BeginDrag(row, source)
    local controller = BlockEditor._getController(row)
    local decl = Block.GetBlock(source.blockId)
    if controller == nil or decl == nil then
        return
    end
    --a ghost left over from a drag that never reported its end.
    if g_drag ~= nil and g_drag.ghost.valid then
        g_drag.ghost:DestroySelf()
    end
    g_drag = nil

    --the pointer in the window's own units, from its top-left corner
    --(mousePoint runs 0-1 from the row's bottom-left).
    local rowPos = row.positionInScreenSpace
    local rootPos = controller.positionInScreenSpace
    local mouse = row.mousePoint
    local pointerX = (rowPos.x - row.renderedWidth / 2 + mouse.x * row.renderedWidth) - (rootPos.x - controller.renderedWidth / 2)
    local pointerY = (rootPos.y + controller.renderedHeight / 2) - (rowPos.y - row.renderedHeight / 2 + mouse.y * row.renderedHeight)

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
        --stays a child of the window, which keeps the window's style rules.
        dragInPlace = true,
        canDragOnto = function(element, target)
            return target:HasClass("beDropArea")
        end,
        thinkTime = DRAG.TICK,
        think = function(element)
            _tick()
        end,
        dragging = function(element, target)
            _tick()
        end,
        drag = function(element, target)
            _drop(element)
        end,
        removeGhost = function(element)
            element:DestroySelf()
        end,
    }

    local fits = decl.fits or {}
    local slivers = {}
    controller:FireEventTree("collectSlivers", slivers, fits)
    --a block never drops into its own bodies.
    if source.moveUid ~= nil then
        local own = {}
        for _, sliver in ipairs(slivers) do
            if sliver.data.ref.owner ~= source.moveUid then
                own[#own + 1] = sliver
            end
        end
        slivers = own
    end

    g_drag = {
        source = source,
        fits = fits,
        ghost = ghost,
        slivers = slivers,
        open = nil,
        controller = controller,
    }
    controller:AddChild(ghost)
    ghost:SetAsLastSibling()
    controller:FireEventTree("dragHint", fits)
    row:transferDragTo(ghost)
end

--- Adds a block at the end of the first list it fits, for a click on the shelf
--- (every drag has a click path).
--- @param element Panel inside the editor
--- @param blockId string
function BEStack.Append(element, blockId)
    local decl = Block.GetBlock(blockId)
    if decl == nil then
        return
    end
    local fits = decl.fits or {}
    local placedUid = nil
    BlockEditor._fireControllerEvent(element, "editorChange", T("blockeditor.change.add", { block = decl.label }), function(state)
        --- @cast state BEState
        local model = state:Model()
        if model == nil then
            return
        end
        local instance = Block.Instantiate(blockId)
        if instance == nil then
            return
        end
        --a block for one of the page's own lists: the first section it fits.
        local host = BlockEditor._getHost(element)
        local sections = host ~= nil and host.decl ~= nil and host.decl.sections or {}
        for _, section in ipairs(sections) do
            if section.stack ~= nil and _fitsKind(fits, section.fits or "") then
                local ref = { field = section.stack }
                BEState.Insert(model, ref, #(BEState.GetList(model, ref) or {}) + 1, instance)
                placedUid = instance.uid
                return
            end
        end
        --a block for an inner list: the first body of that kind with room, in order.
        local function Search(list, field)
            for _, placed in ipairs(list) do
                local placedDecl = Block.GetBlock(placed.block)
                for _, body in ipairs(placedDecl ~= nil and placedDecl.bodies or {}) do
                    if _fitsKind(fits, body.fits) then
                        local ref = { field = field, owner = placed.uid, body = body.id }
                        local target = BEState.GetList(model, ref) or {}
                        if body.max == nil or #target < body.max then
                            BEState.Insert(model, ref, #target + 1, instance)
                            return true
                        end
                    end
                end
                for _, inner in pairs(placed.bodies or {}) do
                    if Search(inner, field) then
                        return true
                    end
                end
            end
            return false
        end
        for _, section in ipairs(sections) do
            if section.stack ~= nil and Search(model[section.stack] or {}, section.stack) then
                placedUid = instance.uid
                return
            end
        end
    end)
    if placedUid ~= nil then
        --the controller passes it down the tree (see MainPanel's flashRequest).
        BlockEditor._fireControllerEvent(element, "flashRequest", placedUid)
    end
end
