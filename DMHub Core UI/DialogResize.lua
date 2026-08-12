local mod = dmhub.GetModLoading()

--The NE-SW diagonal cursor for the top-right/bottom-left corner handles:
--only newer engine builds register "diagonal-expand-mirror" (and expose
--dmhub.cursorIds to ask). Older builds fall back to the NW-SE
--"diagonal-expand" rather than to an unknown id, which the engine would
--silently render as the default arrow.
local g_mirrorDiagonalCursor = nil
local function MirrorDiagonalCursor()
    if g_mirrorDiagonalCursor == nil then
        g_mirrorDiagonalCursor = "diagonal-expand"
        local ids = dmhub.cursorIds
        if ids ~= nil then
            for _, id in ipairs(ids) do
                if id == "diagonal-expand-mirror" then
                    g_mirrorDiagonalCursor = "diagonal-expand-mirror"
                    break
                end
            end
        end
    end
    return g_mirrorDiagonalCursor
end

--All-sides window resizer: an invisible overlay hosting drag handles on
--every edge and corner of a floating window. A generalization of
--gui.DialogResizePanel below (right/bottom/corner only), which stays
--as-is for its existing callers. The contract matches it: add the
--returned panel as a child of the window (the window must anchor
--halign left / valign top with numeric x/y and selfStyle width/height),
--and external size changes must be announced with
--FireEventTree("resize", caller, {deltax=, deltay=}) carrying SIZE
--deltas so the handles stay glued to their edges (the panel window
--shade does this via SetWindowHeight).
--
--Dragging a left/top handle keeps the opposite edge fixed: the window's
--x/y moves while it resizes. The overlay must be the window's LAST child
--(sibling order is z-order) so the handles sit above window content that
--reaches the border; the handles straddle the border biased outward so
--the strip they occlude inside the window (scrollbars, header) stays
--slim.
--
--doc: the document whose _tmp_location remembers the window placement.
--options:
--  resizeWidth / resizeHeight: false locks that axis (default true).
--      Both false returns an inert overlay so child indexing and the
--      resize-event contract hold regardless.
--  minWidth/maxWidth/minHeight/maxHeight: window-size clamps applied
--      while dragging (nil = unbounded above a small hard floor).
--  onResized(dialog, moved): called when a resize drag completes.
--      moved is true when the drag changed the window's x/y (left/top
--      handles), for callers that track window position (icon rail pins).
--  onResizing(dialog): called every frame DURING a resize drag whose
--      width changed, before layout runs. For live re-fitting (tab-chip
--      compaction); keep it cheap, and don't persist anything from it --
--      onResized still fires once on release for that.
function gui.WindowResizePanel(doc, dialogWidth, dialogHeight, options)
    options = options or {}
    local resizeWidth = options.resizeWidth ~= false
    local resizeHeight = options.resizeHeight ~= false

    local EDGE = 10        --edge strip thickness...
    local EDGE_OUT = 7     --...of which this much overhangs the border
    local CORNER = 18      --corner square size...
    local CORNER_OUT = 12  --...likewise
    local edgeIn = EDGE - EDGE_OUT
    local cornerIn = CORNER - CORNER_OUT

    local parentPanel

    local GetDialog = function()
        return parentPanel.parent
    end

    local function ClampWidth(w)
        if w < 60 then w = 60 end
        if options.minWidth ~= nil and w < options.minWidth then w = options.minWidth end
        if options.maxWidth ~= nil and w > options.maxWidth then w = options.maxWidth end
        return w
    end

    local function ClampHeight(h)
        if h < 40 then h = 40 end
        if options.minHeight ~= nil and h < options.minHeight then h = options.minHeight end
        if options.maxHeight ~= nil and h > options.maxHeight then h = options.maxHeight end
        return h
    end

    --the window's current size: selfStyle is authoritative (construction
    --and every resize write it), renderedWidth is the fallback if a
    --caller ever styles the window with a non-numeric size.
    local function CurrentSize(dialog)
        local w = dialog.selfStyle.width
        if type(w) ~= "number" then
            w = dialog.renderedWidth
        end
        local h = dialog.selfStyle.height
        if type(h) ~= "number" then
            h = dialog.renderedHeight
        end
        return w, h
    end

    local function FinishDrag(element)
        local dialog = GetDialog()
        local beginState = element.data.beginState
        element.data.beginState = nil
        if dialog == nil or not dialog.valid or beginState == nil then
            return
        end
        local w, h = CurrentSize(dialog)
        --size deltas re-seat every handle (including this one -- its own
        --field position was never touched during the drag).
        parentPanel:FireEventTree("resize", element, {deltax = w - beginState.width, deltay = h - beginState.height})
        --a left/top-edge drag moves the window as it resizes, which counts
        --as the user placing it (see PresentDocument's anchor handling).
        --A right/bottom resize leaves it wherever its opener put it, so it
        --must NOT claim a position -- carry any earlier claim forward.
        local moved = dialog.x ~= beginState.x or dialog.y ~= beginState.y
        local prevLoc = doc:try_get("_tmp_location")
        doc._tmp_location = {
            x = dialog.x,
            y = dialog.y,
            width = w,
            height = h,
            moved = moved or (prevLoc ~= nil and prevLoc.moved == true),
            screenx = dmhub.screenDimensionsBelowTitlebar.x,
            screeny = dmhub.screenDimensionsBelowTitlebar.y,
        }
        if options.onResized ~= nil then
            options.onResized(dialog, moved)
        end
    end

    --params: x/y (initial field position), width/height (may be percent
    --strings), cursor, edges = {left/right/top/bottom} (which window
    --edges the handle drags), trackRight/trackBottom (position follows
    --that edge when the window resizes).
    local function CreateHandle(params)
        local edges = params.edges
        return gui.Panel{
            styles = {
                {
                    width = params.width,
                    height = params.height,
                    halign = "left",
                    valign = "top",
                }
            },
            x = params.x,
            y = params.y,
            floating = true,
            swallowPress = true,
            bgimage = true,
            bgcolor = "clear",
            hoverCursor = params.cursor,
            draggable = true,
            data = {
                homeX = params.x,
                homeY = params.y,
            },

            beginDrag = function(element)
                local dialog = GetDialog()
                if dialog == nil or not dialog.valid then
                    return
                end
                dialog:SetAsLastSibling()
                local w, h = CurrentSize(dialog)
                element.data.beginState = {
                    x = dialog.x,
                    y = dialog.y,
                    width = w,
                    height = h,
                    --for right/bottom edges the window origin is fixed, so
                    --absolute math holds: size = drag position + this offset.
                    grabOffsetX = w - element.data.homeX,
                    grabOffsetY = h - element.data.homeY,
                }
            end,

            dragging = function(element)
                local dialog = GetDialog()
                local beginState = element.data.beginState
                if dialog == nil or not dialog.valid or beginState == nil then
                    return
                end
                local w, h = CurrentSize(dialog)
                if edges.left then
                    --xdrag is measured in the window's own frame, which
                    --this drag MOVES; the shift therefore self-corrects
                    --to zero as the window follows the mouse, making the
                    --incremental update stable (and rubber-banding
                    --naturally when the width clamps).
                    local shift = element.xdrag - element.data.homeX
                    local newWidth = ClampWidth(w - shift)
                    dialog.x = dialog.x + (w - newWidth)
                    dialog.selfStyle.width = newWidth
                elseif edges.right then
                    dialog.selfStyle.width = ClampWidth(element.xdrag + beginState.grabOffsetX)
                end
                if edges.top then
                    local shift = element.ydrag - element.data.homeY
                    local newHeight = ClampHeight(h - shift)
                    dialog.y = dialog.y + (h - newHeight)
                    dialog.selfStyle.height = newHeight
                elseif edges.bottom then
                    dialog.selfStyle.height = ClampHeight(element.ydrag + beginState.grabOffsetY)
                end
                --live re-fit: a width change mid-drag lets the caller
                --compact its chrome NOW, in the same frame, rather than
                --wrapping until the drag releases.
                if options.onResizing ~= nil and dialog.selfStyle.width ~= w then
                    options.onResizing(dialog)
                end
            end,

            drag = FinishDrag,

            resize = function(element, callingElement, delta)
                if delta == nil then
                    return
                end
                if params.trackRight then
                    element.data.homeX = element.data.homeX + (delta.deltax or 0)
                    element.x = element.data.homeX
                end
                if params.trackBottom then
                    element.data.homeY = element.data.homeY + (delta.deltay or 0)
                    element.y = element.data.homeY
                end
            end,
        }
    end

    local handles = {}

    if resizeWidth and resizeHeight then
        --edge strips run between the corner squares.
        local edgeSpan = string.format("100%%-%d", cornerIn * 2)
        handles[#handles + 1] = CreateHandle{
            x = cornerIn, y = -EDGE_OUT, width = edgeSpan, height = EDGE,
            cursor = "vertical-expand", edges = {top = true},
        }
        handles[#handles + 1] = CreateHandle{
            x = cornerIn, y = dialogHeight - edgeIn, width = edgeSpan, height = EDGE,
            cursor = "vertical-expand", edges = {bottom = true}, trackBottom = true,
        }
        handles[#handles + 1] = CreateHandle{
            x = -EDGE_OUT, y = cornerIn, width = EDGE, height = edgeSpan,
            cursor = "horizontal-expand", edges = {left = true},
        }
        handles[#handles + 1] = CreateHandle{
            x = dialogWidth - edgeIn, y = cornerIn, width = EDGE, height = edgeSpan,
            cursor = "horizontal-expand", edges = {right = true}, trackRight = true,
        }
        handles[#handles + 1] = CreateHandle{
            x = -CORNER_OUT, y = -CORNER_OUT, width = CORNER, height = CORNER,
            cursor = "diagonal-expand", edges = {left = true, top = true},
        }
        handles[#handles + 1] = CreateHandle{
            x = dialogWidth - cornerIn, y = -CORNER_OUT, width = CORNER, height = CORNER,
            cursor = MirrorDiagonalCursor(), edges = {right = true, top = true}, trackRight = true,
        }
        handles[#handles + 1] = CreateHandle{
            x = -CORNER_OUT, y = dialogHeight - cornerIn, width = CORNER, height = CORNER,
            cursor = MirrorDiagonalCursor(), edges = {left = true, bottom = true}, trackBottom = true,
        }
        handles[#handles + 1] = CreateHandle{
            x = dialogWidth - cornerIn, y = dialogHeight - cornerIn, width = CORNER, height = CORNER,
            cursor = "diagonal-expand", edges = {right = true, bottom = true}, trackRight = true, trackBottom = true,
        }
    elseif resizeWidth then
        handles[#handles + 1] = CreateHandle{
            x = -EDGE_OUT, y = 0, width = EDGE, height = "100%",
            cursor = "horizontal-expand", edges = {left = true},
        }
        handles[#handles + 1] = CreateHandle{
            x = dialogWidth - edgeIn, y = 0, width = EDGE, height = "100%",
            cursor = "horizontal-expand", edges = {right = true}, trackRight = true,
        }
    elseif resizeHeight then
        handles[#handles + 1] = CreateHandle{
            x = 0, y = -EDGE_OUT, width = "100%", height = EDGE,
            cursor = "vertical-expand", edges = {top = true},
        }
        handles[#handles + 1] = CreateHandle{
            x = 0, y = dialogHeight - edgeIn, width = "100%", height = EDGE,
            cursor = "vertical-expand", edges = {bottom = true}, trackBottom = true,
        }
    end

    parentPanel = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        children = handles,
    }

    return parentPanel
end

function gui.DialogResizePanel(self, dialogWidth, dialogHeight)

    local parentPanel

    local GetDialog = function()
        return parentPanel.parent
    end

    --handle on right
    local rightHandle = gui.Panel {
        styles = {
            {
                width = 8,
                height = "100%-32",
                valign = "top",
                halign = "left",
            }
        },
        x = dialogWidth - 8,
        y = 0,
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = "horizontal-expand",
        dragBounds = { x1 = 100, y1 = -1200, x2 = 1500, y2 = -100 },
        draggable = true,
        beginDrag = function(element)
            element.data.beginPos = {
                x = element.x,
                y = element.y,
            }
        end,
        drag = function(element)
            local dialog = GetDialog()
            element.x = element.xdrag
            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }
            parentPanel:FireEventTree("resize", element, {deltax = element.x - element.data.beginPos.x})
        end,
        dragging = function(element)
            local dialog = GetDialog()
            dialog.selfStyle.width = element.xdrag + 8
        end,

        resize = function(element, callingElement, delta)
            if callingElement == element then
                return
            end

            element.x = element.x + (delta.deltax or 0)
        end,
    }

    --handle on bottom
    local bottomHandle = gui.Panel {
        styles = {
            {
                width = "100%-32",
                height = 8,
                valign = "top",
                halign = "left",
            }
        },
        x = 0,
        y = dialogHeight - 8,
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = "vertical-expand",
        dragBounds = { x1 = 100, y1 = -1200, x2 = 1500, y2 = -100 },
        draggable = true,
        beginDrag = function(element)
            element.data.beginPos = {
                x = element.x,
                y = element.y,
            }
        end,
        drag = function(element)
            local dialog = GetDialog()
            element.y = element.ydrag
            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }
            parentPanel:FireEventTree("resize", element, {deltay = element.y - element.data.beginPos.y})
        end,
        dragging = function(element)
            local dialog = GetDialog()
            dialog.selfStyle.height = element.ydrag + 8
        end,

        resize = function(element, callingElement, delta)
            if callingElement == element then
                return
            end

            element.y = element.y + (delta.deltay or 0)
        end,
    }

    --handle in bottom right
    local bottomRightHandle = gui.Panel {
        styles = {
            {
                width = 32,
                height = 32,
                valign = "top",
                halign = "left",
            }
        },
        x = dialogWidth - 32,
        y = dialogHeight - 32,
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = "diagonal-expand",
        dragBounds = { x1 = 100, y1 = -1200, x2 = 1500, y2 = -100 },
        draggable = true,
        beginDrag = function(element)
            element.data.beginPos = {
                x = element.x,
                y = element.y,
            }
        end,
        drag = function(element)
            local dialog = GetDialog()
            element.x = element.xdrag
            element.y = element.ydrag
            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }
            parentPanel:FireEventTree("resize", element, {deltax = element.x - element.data.beginPos.x, deltay = element.y - element.data.beginPos.y})
        end,
        dragging = function(element)
            local dialog = GetDialog()
            dialog.selfStyle.width = element.xdrag + 32
            dialog.selfStyle.height = element.ydrag + 32
        end,
        resize = function(element, callingElement, delta)
            if callingElement == element then
                return
            end

            element.x = element.x + (delta.deltax or 0)
            element.y = element.y + (delta.deltay or 0)
        end,
    }

    parentPanel = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        rightHandle,
        bottomHandle,
        bottomRightHandle,
    }

    return parentPanel

end
