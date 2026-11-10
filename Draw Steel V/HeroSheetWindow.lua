local mod = dmhub.GetModLoading()

--The Hero sheet's window: the frame HeroSheet.lua puts the sheet in. A
--window on the table's documents layer, which map, scene and journal windows
--share, so a press brings it to the front and the map stays playable around
--it. Modes:
--  restored: moves by its title bar, resizes from every edge, never below
--      760 x 560; its size and spot are kept per user, per game.
--  maximized: covers the whole screen, rails and action bar included, as
--      the classic character sheet does: it moves to the main dialog layer,
--      above the HUD.
--  minimized: hidden, flown into the Hero's card on the table
--      (Tabletop.MinimizeToCard); the card's sheet button brings it back.
--  popped out: in its own OS window (Panel:MoveToNativeWindow).
--  full screen: the lobby's Edit Hero, where there is no table.
--  Builder: the Builder shows in place of the sheet, covering the screen as
--      maximized does, at its designed size (no resize, no drag); leaving it
--      puts the window back in the mode it had. Popped out, the Builder
--      stays in the OS window.
--For similar windows see JournalPDFViewer.lua (restored / maximized / popped
--out) and DialogResize.lua (the resize handles).

HeroSheetWindow = rawget(_G, "HeroSheetWindow") or {}

HeroSheetWindow.MIN_WIDTH = 760
HeroSheetWindow.MIN_HEIGHT = 560

--the map windows' titlebar height (Tabletop.lua): the sheet's title bar
--and its controls match theirs.
local TITLE_HEIGHT = 30

--Layout tiers, by the layout width in sheet units: Wide from 1450,
--Medium from 1100, Narrow below. A change needs the width to pass the
--boundary by half the buffer, so resizing near one does not flip back and
--forth.
HeroSheetWindow.TIER_WIDE = 1450
HeroSheetWindow.TIER_MEDIUM = 1100
local TIER_BUFFER = 40

--Below this content height (the 100% Font Size floor, under the title bar)
--the content scrolls instead of squashing.
local MIN_CONTENT_HEIGHT = HeroSheetWindow.MIN_HEIGHT - TITLE_HEIGHT

--- How much the window's inside is zoomed. With the icon rail on, the engine
--- holds font magnification at 1, so the sheet zooms by Font Size as the
--- rail's windows do; with it off the engine already magnifies every font,
--- so zooming too would double-scale.
--- @return number
function HeroSheetWindow.Zoom()
    if dmhub.GetSettingValue("iconrail") == true then
        return (dmhub.GetSettingValue("fontsize") or 100) * 0.01
    end
    return 1
end

--The Font Size that picks the tier: the layout is the window divided by it
--in both rail modes, so a large font moves to a narrower tier either way.
--- @return number
local function TierScale()
    local scale = (dmhub.GetSettingValue("fontsize") or 100) * 0.01
    if type(scale) ~= "number" or scale <= 0 then
        return 1
    end
    return scale
end

--- The tier for a layout width, given the tier now showing (for the buffer).
--- @param width number layout width in sheet units
--- @param current nil|string "wide", "medium" or "narrow"
--- @return string
function HeroSheetWindow.PickTier(width, current)
    local half = TIER_BUFFER / 2
    local wideAt = HeroSheetWindow.TIER_WIDE
    local mediumAt = HeroSheetWindow.TIER_MEDIUM
    if current == "wide" then
        wideAt = wideAt - half
    elseif current ~= nil then
        wideAt = wideAt + half
    end
    if current == "narrow" then
        mediumAt = mediumAt + half
    elseif current ~= nil then
        mediumAt = mediumAt - half
    end
    if width >= wideAt then
        return "wide"
    elseif width >= mediumAt then
        return "medium"
    end
    return "narrow"
end

--The restored window's last spot and size, with the layer size it was
--measured against: {x, y, w, h, lw, lh} in documents-layer units.
local g_geometrySetting = setting{
    id = "herosheet:windowrect",
    description = "Where the Hero sheet window was last left.",
    storage = "pergamepreference",
    default = {},
}

--A Builder Finish plays its own lock-in sound; the Builder leaving just
--after it stays quiet, so the press is one sound.
local g_quietUntil = 0

--- Keep the window sound of the Builder leaving quiet for a moment (a Finish).
function HeroSheetWindow.QuietWindowSound()
    g_quietUntil = dmhub.Time() + 0.5
end

--A layer a host puts above itself for the sheet's pop-ups and windows
--(HeroSheetWindow.SetPopupLayer): the EotW town's Builder sits above the
--app's dialog layer, so its windows would open behind it.
--- @type nil|Panel
local g_popupLayer = nil

--- Pop-ups and sheet windows open in this layer while it is set (nil: the
--- app's dialog layer again).
--- @param layer nil|Panel
function HeroSheetWindow.SetPopupLayer(layer)
    g_popupLayer = layer
end

--Where a maximized or full-screen sheet goes: the main dialog layer, above
--the action bar and icon rails (the classic sheet and EotW's live there too).
--- @return nil|Panel
local function CoverLayer()
    if g_popupLayer ~= nil and g_popupLayer.valid then
        return g_popupLayer
    end
    local hud = GameHud.instance
    if not hud then
        return nil
    end
    local layer = hud:try_get("mainDialogPanel")
    if layer == nil or not layer.valid then
        return nil
    end
    return layer
end

--- True when the window is showing and nothing else in its layer was
--- pressed more recently: activationOrder counts presses on raiseOnPress
--- windows and on the live map, so a click on the map takes it away.
--- @param window nil|Panel
--- @return boolean
function HeroSheetWindow.IsFrontmost(window)
    if window == nil or not window.valid or window.parent == nil or window.data.minimized then
        return false
    end
    local mine = window.activationOrder
    for _,sibling in ipairs(window.parent.children) do
        if sibling ~= window and sibling.valid and sibling.activationOrder > mine then
            return false
        end
    end
    return true
end

--A window or pop-up root's styles. The documents layer's selector-less rule
--sizes every panel under it 100% x 100%: the engine defaults go back first,
--as the PDF viewer does, so a root lays out the same in any layer; then the
--theme with the sheet's rules (HeroSheetTheme); then the frame.
--- @return table
local function WindowStyles()
    return {
            {
                {
                    valign = "center",
                    halign = "center",
                    bgcolor = "clear",
                    width = 100,
                    height = 100,
                },
            },
        HeroSheetTheme.RootStyles(),
        --the frame of a map window (Tabletop.lua's tabletopWindow): square
        --corners, a dark edge, the table's shadow, lifted while dragged.
        {
            {
                selectors = {"heroSheetWindow"},
                cornerRadius = 0,
                borderWidth = 2,
                borderColor = "#00000099",
                boxShadow = Tabletop.shadows.rest,
            },
            {
                selectors = {"heroSheetWindow", "dragging"},
                boxShadow = Tabletop.shadows.lifted,
                transitionTime = 0.15,
            },
            --maximized, it covers the screen: nothing to cast a shadow on.
            {
                selectors = {"heroSheetWindow", "heroSheetMaximized"},
                boxShadow = false,
            },
        },
    }
end

--What a maximized sheet fills: the whole screen below the title bar.
--- @return {x: number, y: number, w: number, h: number}
local function MaximizedRect()
    local w, h = Tabletop.LayerSize()
    return {x = 0, y = 0, w = w, h = h}
end

--Where the restored window goes: where it was last left (kept inside the
--table), else a window sized for the Medium layout in the middle.
--- @return {x: number, y: number, w: number, h: number}
local function RestoredRect()
    local lw, lh = Tabletop.LayerSize()
    local saved = g_geometrySetting:Get()
    local w, h, x, y
    if type(saved) == "table" and type(saved.w) == "number" and type(saved.h) == "number" then
        w, h, x, y = saved.w, saved.h, saved.x or 0, saved.y or 0
    else
        w = math.min(1300, lw - 160)
        h = math.min(900, lh - 80)
        x = math.floor((lw - w) / 2)
        y = math.floor((lh - h) / 2)
    end
    w = math.max(HeroSheetWindow.MIN_WIDTH, math.min(w, lw))
    h = math.max(HeroSheetWindow.MIN_HEIGHT, math.min(h, lh))
    --enough of it stays on the table to grab again.
    x = math.max(120 - w, math.min(x, lw - 120))
    y = math.max(0, math.min(y, lh - TITLE_HEIGHT))
    return {x = x, y = y, w = w, h = h}
end

--The colours of the stand-in that flies between the sheet and its card
--(Tabletop.MinimizeToCard / RestoreFromCard): the solid backdrop and the
--title bar's plate, so it reads as this window and not as a picture.
--- @return HeroSheetGhostLook
local function GhostLook()
    local palette = HeroSheetTheme.Palette()
    local plateAlpha = cond(HeroSheetTheme.SeeThrough(), HeroSheetTheme.PLATE_SEE, 1)
    return {
        bg = HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(palette.bg, 1), HeroSheetTheme.BACKDROP_SOLID),
        bar = HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(palette.plate, 1), plateAlpha),
        barHeight = TITLE_HEIGHT * HeroSheetWindow.Zoom(),
    }
end

local COVER_FADE_SECONDS = 0.14

--A sheet back from its card arrives under a copy of the stand-in's last frame,
--which fades away: the blank window clears to the sheet instead of popping in.
--It also hides the first layout. Opacity does not pass to children, so the
--bar fades on its own.
--- @param window Panel
--- @param look HeroSheetGhostLook
local function FadeInCover(window, look)
    local start = dmhub.Time()
    local bar = gui.Panel{
        floating = true,
        interactable = false,
        valign = "top",
        width = "100%",
        height = look.barHeight,
        bgimage = "panels/square.png",
        bgcolor = look.bar,
    }
    window:AddChild(gui.Panel{
        floating = true,
        interactable = false,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = look.bg,
        children = {bar},
        thinkTime = 0.01,
        think = function(element)
            local t = math.min(1, (dmhub.Time() - start) / COVER_FADE_SECONDS)
            element.selfStyle.opacity = 1 - t
            bar.selfStyle.opacity = 1 - t
            if t >= 1 then
                element:DestroySelf()
            end
        end,
    })
end

--- @param window Panel
local function RememberGeometry(window)
    local w = window.selfStyle.width
    local h = window.selfStyle.height
    if type(w) ~= "number" or type(h) ~= "number" then
        return
    end
    local lw, lh = Tabletop.LayerSize()
    g_geometrySetting:Set{x = window.x, y = window.y, w = w, h = h, lw = lw, lh = lh}
end

--A title-bar control, drawn as map windows draw theirs (a full-height
--hover zone, 36 wide, around a small glyph), with its tooltip.
--- @param args {icon: string, tooltip: string|(fun(): string), click: fun(element: Panel), danger: nil|boolean}
--- @return Panel
local function ChromeButton(args)
    local tooltip = args.tooltip
    return Tabletop.WindowControl{
        icon = args.icon,
        danger = args.danger,
        hover = function(element)
            local text = tooltip
            if type(text) == "function" then
                text = text()
            end
            gui.Tooltip(text)(element)
        end,
        click = args.click,
    }
end

--- @class HeroSheetWindowArgs
--- @field charid string
--- @field content Panel
--- @field title fun(): string
--- @field subtitle nil|fun(): string muted words after the title ("Changes save as you go.")
--- @field onEscape nil|fun(): boolean runs on Esc before the window closes; true means it used the key
--- @field fullscreen nil|boolean
--- @field maximized nil|boolean
--- @field onClose fun()
--- @field onPopIn fun()

--- Build the window around the sheet's content.
--- args:
---   charid: the Hero shown (the card it minimizes into).
---   content: the panel under the title bar.
---   title: fun(): string, the title bar text (refreshed by "heroSheetTitle").
---   fullscreen: true in the lobby (close only, no table).
---   maximized: open maximized (as the Windows menu does); else restored.
---   onClose: fun() when the user closes it (title bar x or the OS window).
---   onPopIn: fun() when "Return to the app" asks for the window back.
--- The returned window's data holds the controls: place(), minimize(),
--- restore(), setMaximized(bool), popOut(), setBuilder(panel or nil),
--- setReview(nil or {top, bottom}: the sheet between the Builder's stepper
--- and footer), and the mode flags maximized, minimized, poppedOut,
--- fullscreen, builder, review.
--- @param args HeroSheetWindowArgs
--- @return Panel
function HeroSheetWindow.Create(args)
    local window
    local resizeOverlay = nil

    local function RemoveResizeOverlay()
        if resizeOverlay ~= nil and resizeOverlay.valid then
            resizeOverlay:DestroySelf()
        end
        resizeOverlay = nil
    end

    --The window's inside (title bar and content) at the layout size, zoomed
    --back up to fill the window; built below.
    local inner
    local holder
    --holds the Builder (setBuilder) beside the sheet's holder; one shows.
    local builderHost
    --the panel under the title bar; setContent swaps it (another Hero).
    local content = args.content
    --a resize drag shows the skeleton in the content's place (built below).
    --- @type fun()
    local StartSkeleton
    --- @type fun()
    local EndSkeleton

    --Lays the inside out for the window's current size and Font Size: the
    --layout is the window divided by the zoom, the tier comes from the layout
    --width, and the content keeps at least its floor height (then scrolls).
    --A tier change sets the inside's tier class and fires heroSheetTier
    --(tabs restyle for it, never rebuild); every layout fires heroSheetLayout.
    local function Reflow()
        if window == nil or not window.valid then
            return
        end
        local w = window.selfStyle.width
        local h = window.selfStyle.height
        if type(w) ~= "number" then
            w = window.renderedWidth
        end
        if type(h) ~= "number" then
            h = window.renderedHeight
        end
        local zoom = HeroSheetWindow.Zoom()
        local layoutW = w / zoom
        local layoutH = h / zoom
        inner.selfStyle.pivot = {x = 0, y = 1}
        inner.selfStyle.uiscale = zoom
        inner.selfStyle.width = layoutW
        inner.selfStyle.height = layoutH
        local data = window.data
        --- Lays the sheet out at a height: its tier from the window's width.
        --- @param contentH number
        local function LayoutSheet(contentH)
            --pinned to the top: a vscroll child taller than its holder would
            --otherwise centre and push its top out of view.
            content.selfStyle.valign = "top"
            content.selfStyle.height = contentH

            local tier = HeroSheetWindow.PickTier(w / TierScale(), data.tier)
            if tier ~= data.tier then
                data.tier = tier
                inner:SetClass("heroSheetWide", tier == "wide")
                inner:SetClass("heroSheetMedium", tier == "medium")
                inner:SetClass("heroSheetNarrow", tier == "narrow")
                inner:FireEventTree("heroSheetTier", tier)
            end
            inner:FireEventTree("heroSheetLayout", layoutW, contentH)
        end
        if data.builder then
            --the Builder lays itself out for the whole window; the hidden
            --sheet keeps its tier and sizes until it shows again.
            local builderH = layoutH - TITLE_HEIGHT
            builderHost.selfStyle.height = builderH
            builderHost:FireEventTree("heroBuilderLayout", layoutW, builderH)
            --Review: the sheet itself fills the Builder's middle, under
            --its stepper and over its footer. It floats there, drawn over the
            --Builder (it is the inside's last child), so it takes the pointer.
            local review = data.review
            if review ~= nil then
                local sheetH = math.max(1, builderH - review.top - review.bottom)
                holder.floating = true
                holder.selfStyle.valign = "top"
                holder.selfStyle.tmargin = TITLE_HEIGHT + review.top
                holder.selfStyle.height = sheetH
                LayoutSheet(math.max(MIN_CONTENT_HEIGHT, sheetH))
            end
            return
        end
        LayoutSheet(math.max(MIN_CONTENT_HEIGHT, layoutH - TITLE_HEIGHT))
    end

    --Puts the window where its mode says, sized for it.
    local function Place()
        local data = window.data
        RemoveResizeOverlay()
        if data.poppedOut then
            return
        end
        local restored = not (data.fullscreen or data.maximized or data.builder)
        local layer = Tabletop.DocumentsLayer()
        if not restored then
            layer = CoverLayer() or layer
        end
        if layer ~= nil and window.parent ~= layer then
            if window.parent ~= nil then
                window:Unparent()
            end
            layer:AddChild(window)
        end
        --maximized, it sits under everything else on the main dialog layer
        --(the panels menu, settings and editors open there) and a click does
        --not raise it; restored, it raises like the table's other windows.
        if window.raiseOnPress ~= restored then
            window.raiseOnPress = restored
        end
        if not restored and layer ~= nil then
            window:SetAsFirstSibling()
        end
        local rect
        if restored then
            rect = RestoredRect()
        else
            rect = MaximizedRect()
        end
        window.x = rect.x
        window.y = rect.y
        window.selfStyle.width = rect.w
        window.selfStyle.height = rect.h
        if restored then
            --the handles are built for one size and follow it by events, so
            --a fresh overlay goes on each time the window is restored.
            --WindowResizePanel saves the window's placement on a document;
            --the sheet keeps its own (RememberGeometry), so this stand-in
            --just absorbs the writes.
            resizeOverlay = gui.WindowResizePanel({
                try_get = function(self, key)
                    return rawget(self, key)
                end,
            }, rect.w, rect.h, {
                minWidth = HeroSheetWindow.MIN_WIDTH,
                minHeight = HeroSheetWindow.MIN_HEIGHT,
                --the content waits under the skeleton for the whole drag and
                --lays out once on release.
                onResizeBegin = function(dialog)
                    StartSkeleton()
                end,
                onResizing = function(dialog)
                    StartSkeleton()
                end,
                onResized = function(dialog)
                    EndSkeleton()
                    Reflow()
                    --what changed while the content was collapsed shows now.
                    HeroSheetRefresh.CatchUpShown()
                    RememberGeometry(window)
                end,
            })
            --last child: the handles sit over the content at the border.
            window:AddChild(resizeOverlay)
        end
        window.dragMove = restored
        --Restored, it lies on the table, so the Director's Screen draws over
        --it; maximized, it covers the table, as a maximized journal does.
        window:SetClass("tabletopItem", restored)
        window:SetClass("heroSheetMaximized", not restored)
        local hidden = data.minimized == true or data.closed == true
        window:SetClass("collapsed", hidden)
        if hidden then
            window.captureEscape = false
        end
        window:FireEventTree("heroSheetWindowMode", data)
        Reflow()
    end

    --Closing keeps the window built and hidden, so reopening is quick; a
    --minimized one first lets its card go.
    local function Hide()
        local data = window.data
        --the window leaving makes the app's window sound.
        if not data.closed then
            audio.FireSoundEvent("UI.WindowClose")
        end
        if data.minimized then
            Tabletop.RestoreFromCard(data.charid, nil, function() end)
            data.minimized = false
        end
        if gui.ChildHasFocus(window) then
            gui.SetFocus(nil)
        end
        --a closed Builder reopens as the sheet: the open picks the tab again.
        if data.builder then
            data.builder = false
            holder:SetClass("collapsed", false)
            builderHost:SetClass("collapsed", true)
            HeroSheetTheme.ApplyBackdrop(window)
        end
        data.closed = true
        Place()
    end

    --Opens a kept window again, restored (or maximized when asked), on top.
    --- @param maximized boolean
    local function Reopen(maximized)
        local data = window.data
        audio.FireSoundEvent("UI.WindowOpen")
        data.closed = false
        data.maximized = maximized
        data.fullscreen = dmhub.isLobbyGame
        Place()
        HeroSheetWindow.BringToFront(window)
    end

    --Swaps the panel under the title bar, e.g. for another Hero.
    --- @param panel Panel
    local function SetContent(panel)
        content = panel
        holder.children = {panel}
        Reflow()
    end

    --Shows the Builder in place of the sheet (a panel), or the sheet again
    --(nil). The Builder panel stays in its host while hidden, so the next
    --open is quick; the window's own mode (maximized or not) is untouched.
    --- @param panel nil|Panel
    local function SetBuilder(panel)
        local data = window.data
        local on = panel ~= nil
        local swapped = false
        --the Builder and Level up are kept side by side, one shown: a
        --panel left out of children is destroyed. Any other child is a panel
        --a reload left behind, and goes.
        if on then
            local keep = {}
            local has = false
            local stale = false
            for _, child in ipairs(builderHost.children) do
                if child == panel or child == data.builderPanel or child == data.levelUpPanel then
                    keep[#keep+1] = child
                    has = has or child == panel
                else
                    stale = true
                end
            end
            if not has then
                keep[#keep+1] = panel
            end
            if stale or not has then
                builderHost.children = keep
                swapped = true
            end
            for _, child in ipairs(keep) do
                child:SetClass("collapsed", child ~= panel)
            end
        end
        if data.builder == on then
            --a new Builder panel (after a reload) is laid out at once.
            if swapped then
                Reflow()
            end
            return
        end
        data.builder = on
        --the Builder (or Level up) covering the screen sounds like a window
        --opening or closing (quiet just after a Finish: g_quietUntil).
        if dmhub.Time() >= g_quietUntil then
            audio.FireSoundEvent(cond(on, "UI.WindowOpen", "UI.WindowClose"))
        end
        if gui.ChildHasFocus(window) then
            gui.SetFocus(nil)
        end
        --leaving the Builder ends its Review: the sheet takes the window again.
        if not on and data.review ~= nil then
            data.review = nil
            holder.floating = false
            holder.selfStyle.tmargin = 0
            holder.selfStyle.height = string.format("100%%-%d", TITLE_HEIGHT)
        end
        holder:SetClass("collapsed", on)
        builderHost:SetClass("collapsed", not on)
        --the Builder's backdrop is a darker shade.
        HeroSheetTheme.ApplyBackdrop(window)
        Place()
        --popped out, Place leaves the OS window as it is.
        if data.poppedOut then
            window:FireEventTree("heroSheetWindowMode", data)
            Reflow()
        end
        HeroSheetWindow.BringToFront(window)
    end

    --- The Builder's Review: the sheet itself shows between the
    --- Builder's stepper and footer, `top` and `bottom` Builder units from its
    --- edges; nil puts the Builder's own page back.
    --- @param review nil|{top: number, bottom: number}
    local function SetReview(review)
        local data = window.data
        local old = data.review
        if old == nil and review == nil then
            return
        end
        if old ~= nil and review ~= nil and old.top == review.top and old.bottom == review.bottom then
            return
        end
        data.review = review
        if review ~= nil then
            holder:SetAsLastSibling()
        else
            holder.floating = false
            holder.selfStyle.tmargin = 0
            holder.selfStyle.height = string.format("100%%-%d", TITLE_HEIGHT)
        end
        holder:SetClass("collapsed", review == nil and data.builder == true)
        Reflow()
    end

    local function SetMaximized(maximized)
        local data = window.data
        if data.minimized or data.poppedOut or data.fullscreen or data.builder then
            return
        end
        data.maximized = maximized
        Place()
        HeroSheetWindow.BringToFront(window)
    end

    local function Minimize()
        local data = window.data
        if data.minimized or data.poppedOut or data.fullscreen then
            return
        end
        local from = Tabletop.PanelRect(window)
        if from == nil or not Tabletop.MinimizeToCard(window.data.charid, from, {
            still = function()
                return window ~= nil and window.valid and window.data.minimized == true
            end,
            --the card left the table while it held the sheet: the sheet closes.
            onTakenOff = function()
                if window ~= nil and window.valid and window.data.minimized then
                    args.onClose()
                end
            end,
            look = GhostLook(),
        }) then
            return
        end
        if gui.ChildHasFocus(window) then
            gui.SetFocus(nil)
        end
        audio.FireSoundEvent("UI.WindowClose")
        data.minimized = true
        Place()
    end

    local function Restore()
        local data = window.data
        if not data.minimized then
            HeroSheetWindow.BringToFront(window)
            return
        end
        local to
        if data.maximized or data.builder then
            to = MaximizedRect()
        else
            to = RestoredRect()
        end
        local look = GhostLook()
        Tabletop.RestoreFromCard(window.data.charid, to, function()
            if window == nil or not window.valid or not data.minimized then
                return
            end
            audio.FireSoundEvent("UI.WindowOpen")
            data.minimized = false
            Place()
            HeroSheetWindow.BringToFront(window)
            FadeInCover(window, look)
        end, look)
    end

    local function PopOut()
        local data = window.data
        if data.poppedOut or data.minimized then
            return
        end
        RemoveResizeOverlay()
        data.poppedOut = true
        window.x = 0
        window.y = 0
        window:FireEventTree("heroSheetWindowMode", data)
        --Dialogs opened from inside the popped-out sheet open in its OS
        --window, not back in the app.
        data.nativeWindowRoot = true
        window:MoveToNativeWindow{
            scaling = 0.9,
            resizeable = true,
            title = args.title(),
        }
    end

    --The title bar's controls, in the map windows' order with Pop out first,
    --where rail windows put it: Pop out (or Return to the app once popped
    --out), minimize, maximize / restore, close.
    local popOutButton = ChromeButton{
        icon = "drawsteel/Icons_Nav_MaxWindow.png",
        tooltip = "Pop out into its own window",
        click = function(element)
            PopOut()
        end,
    }
    --popped out, this takes the sheet back into the app on its tab.
    local popInButton = ChromeButton{
        icon = "drawsteel/Icons_Nav_MinWindow.png",
        tooltip = "Return to the app",
        click = function(element)
            args.onPopIn()
        end,
    }
    local minimizeButton = ChromeButton{
        icon = "window-chrome/chrome-minimize.png",
        tooltip = "Minimize to the card",
        click = function(element)
            Minimize()
        end,
    }
    local maximizeButton = ChromeButton{
        icon = "window-chrome/chrome-maximize.png",
        tooltip = function()
            return cond(window.data.maximized, "Restore", "Maximize")
        end,
        click = function(element)
            SetMaximized(not window.data.maximized)
        end,
    }
    local closeButton = ChromeButton{
        icon = "window-chrome/chrome-close.png",
        danger = true,
        tooltip = "Close",
        click = function(element)
            args.onClose()
        end,
    }

    --title bar: the Hero and tab, then the controls. A drag on it moves the
    --restored window (the window takes the drag).
    local titleBar = gui.Panel{
        --a plate, so the title stays readable over any table.
        classes = {"heroSheetTitleBar", "heroSheetPlate"},
        --the caption controls' colours (map windows' rules), on top of the
        --window's theme; read again on a scheme change.
        styles = Tabletop.CaptionStyles(),
        width = "100%",
        height = TITLE_HEIGHT,
        flow = "horizontal",
        --its colour comes from the heroSheetPlate rule (an inline bgcolor
        --would override it).
        bgimage = "panels/square.png",
        create = function(element)
            HeroSheetTheme.Track(element, function(panel)
                panel.styles = Tabletop.CaptionStyles()
            end)
        end,
        --the Builder is full screen at its designed size: no pop out or
        --maximize, only minimize and close.
        heroSheetWindowMode = function(element, data)
            popOutButton:SetClass("collapsed", data.poppedOut or data.fullscreen or data.builder)
            popInButton:SetClass("collapsed", not data.poppedOut)
            minimizeButton:SetClass("collapsed", data.fullscreen or data.poppedOut or not Tabletop.IsActive())
            maximizeButton:SetClass("collapsed", data.fullscreen or data.poppedOut or data.builder)
            maximizeButton:FireEventTree("setIcon", cond(data.maximized, "window-chrome/chrome-restore.png", "window-chrome/chrome-maximize.png"))
        end,

        --a map window's name: 14, bold, the strong text colour. It leaves the
        --buttons their room by a cap, never by "100% available": the engine
        --restyles such a part every frame.
        gui.Label{
            classes = {"heroSheetTitle"},
            width = "auto",
            maxWidth = "100%-200",
            height = "100%",
            hmargin = 8,
            halign = "left",
            fontSize = 14,
            bold = true,
            textAlignment = "left",
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
            create = function(element)
                element.text = args.title()
            end,
            heroSheetTitle = function(element)
                element.text = args.title()
            end,
        },
        --muted words after the title (the Builder's
        --"Changes save as you go."); collapsed when there are none.
        gui.Label{
            classes = {"heroSheetMuted", "collapsed"},
            width = "auto",
            height = "100%",
            rmargin = 8,
            halign = "left",
            fontSize = 12,
            textAlignment = "left",
            textWrap = false,
            interactable = false,
            heroSheetTitle = function(element)
                local text = args.subtitle ~= nil and args.subtitle() or ""
                element.text = text
                element:SetClass("collapsed", text == "")
            end,
        },

        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "100%",
            halign = "right",
            popOutButton,
            popInButton,
            minimizeButton,
            maximizeButton,
            closeButton,
        },
    }

    --holds the content, scrolling when the window is shorter than its
    --floor. A drag starting here goes nowhere, so the window does not move.
    holder = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", TITLE_HEIGHT),
        vscroll = true,
        draggable = true,
        dragMove = false,
        args.content,
    }

    --The skeleton a resize drag shows in the content's place: the sheet's
    --blocks as bare plates, laid out for the tier the new width takes.
    --Resizing the content itself restyles every panel in it every frame and
    --stutters, so the content waits, collapsed, and lays out once on release.
    --Built the first time a drag starts and kept.
    --- @class HeroSheetSkeleton
    --- @field panel Panel
    --- @field card Panel
    --- @field main Panel
    --- @field top Panel
    --- @field stats Panel
    --- @field lists Panel
    --- @field listB Panel
    --- @field side Panel
    --- @field banner Panel
    --- @field active nil|boolean a drag is showing it
    --- @field holderWasCollapsed nil|boolean
    --- @field tier nil|string what it is laid out for
    --- @field tab nil|string
    --- @field w nil|number the window size it was last fitted to
    --- @field h nil|number

    --- @type nil|HeroSheetSkeleton
    local skeleton = nil
    --- @type fun()
    local FitSkeleton

    --- A bare plate in the sheet's own look.
    --- @param args table panel fields
    --- @return Panel
    local function SkeletonPlate(args)
        args.classes = {"heroSheetPlate"}
        args.bgimage = "panels/square.png"
        args.border = 1
        args.cornerRadius = 12
        args.interactable = false
        return gui.Panel(args)
    end

    local function BuildSkeleton()
        local card = gui.Panel{
            width = 320,
            height = "100%",
            flow = "vertical",
            rmargin = 12,
            interactable = false,
            SkeletonPlate{width = "100%", height = "55%", bmargin = 12},
            SkeletonPlate{width = "100%", height = "15%", bmargin = 12},
            SkeletonPlate{width = "100%", height = "30%-24"},
        }
        local top = SkeletonPlate{width = "100%", height = 72, bmargin = 8}
        --Narrow's Hero card, over the column (the card column's at Wide and Medium).
        local banner = SkeletonPlate{width = "100%", height = 280, bmargin = 8}
        --Character's stats band (Narrow: the characteristics row).
        local stats = SkeletonPlate{width = "100%", height = "28%", bmargin = 8}
        local listB = SkeletonPlate{width = "52%-6", height = "100%", lmargin = 12}
        --Inventory's item pane and Downtime's detail, beside their list.
        local side = SkeletonPlate{width = "42%-6", height = "100%", lmargin = 12}
        local lists = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "horizontal",
            interactable = false,
            SkeletonPlate{width = "48%-6", height = "100%"},
            listB,
            side,
        }
        local main = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            interactable = false,
            top,
            banner,
            stats,
            lists,
        }
        local panel = gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = string.format("100%%-%d", TITLE_HEIGHT),
            hpad = 12,
            vpad = 12,
            borderBox = true,
            flow = "horizontal",
            interactable = false,
            --follows the window every frame while it shows (a height-only
            --drag reports no width change). Collapsed, it does not think.
            thinkTime = 0.01,
            think = function(element)
                FitSkeleton()
            end,
            card,
            main,
        }
        skeleton = {panel = panel, card = card, main = main, top = top, stats = stats, lists = lists, listB = listB, side = side, banner = banner}
        inner:AddChild(panel)
    end

    --- Lays the skeleton out for a tier and the open tab; only on a change.
    --- @param tier string
    local function ArrangeSkeleton(tier)
        local skel = skeleton
        if skel == nil then
            return
        end
        local state = HeroSheet.State()
        local tab = state ~= nil and state.tab or "CharacterSheet"
        if tab ~= "Inventory" and tab ~= "Downtime" and tab ~= "Appearance" then
            tab = "CharacterSheet"
        end
        if tier == skel.tier and tab == skel.tab then
            return
        end
        skel.tier = tier
        skel.tab = tab
        local narrow = tier == "narrow"
        local cardWidth = HeroSheet.CardColumnWidth(tier)
        skel.card:SetClass("collapsed", cardWidth == nil)
        if cardWidth ~= nil then
            skel.card.selfStyle.width = cardWidth
            skel.main.selfStyle.width = string.format("100%%-%d", cardWidth + 12)
        else
            skel.main.selfStyle.width = "100%"
        end
        local character = tab == "CharacterSheet"
        --Narrow has no card column: the Hero card heads the Character tab.
        local banner = narrow and character
        skel.banner:SetClass("collapsed", not banner)
        skel.stats:SetClass("collapsed", not character)
        --the top bar is one row at Wide, its tabs on a second row below it.
        local topH = cond(tier == "wide", 72, 120)
        skel.top.selfStyle.height = topH
        --Character's stats band: about 28% of the column at Wide, 38% at
        --Medium (it wraps to more rows); at Narrow the characteristics row
        --under the card.
        local statsPct = 0
        local fixed = topH + 8
        if banner then
            skel.stats.selfStyle.height = 60
            fixed = fixed + 288 + 68
        elseif character then
            statsPct = cond(tier == "wide", 28, 38)
            skel.stats.selfStyle.height = string.format("%d%%", statsPct)
            fixed = fixed + 8
        end
        --the lists take what the plates above them leave.
        skel.lists.selfStyle.height = string.format("%d%%-%d", 100 - statsPct, fixed)
        --Inventory and Downtime: the list, and its pane beside it but at Narrow.
        skel.listB:SetClass("collapsed", not character or tier ~= "wide")
        skel.side:SetClass("collapsed", character or narrow)
        skel.side.selfStyle.width = cond(tab == "Downtime", "64%-6", cond(tab == "Appearance", "50%-6", "42%-6"))
        --Appearance's column is one tall plate: the big art.
        local cardPlates = skel.card.children
        for i, plate in ipairs(cardPlates) do
            plate:SetClass("collapsed", tab == "Appearance" and i > 1)
        end
        if cardPlates[1] ~= nil then
            cardPlates[1].selfStyle.height = cond(tab == "Appearance", "100%", "55%")
        end
        local first = skel.lists.children[1]
        if first ~= nil then
            local width = "100%"
            if character and tier == "wide" then
                width = "48%-6"
            elseif not character and not narrow then
                width = cond(tab == "Downtime", "36%-6", cond(tab == "Appearance", "50%-6", "58%-6"))
            end
            first.selfStyle.width = width
        end
    end

    --- The skeleton at the window's size now: the inside sized as Reflow
    --- sizes it (only the title bar and the plates lay out), the tier from
    --- the width, with the tier buffer.
    FitSkeleton = function()
        local skel = skeleton
        if skel == nil or not skel.active or window == nil or not window.valid then
            return
        end
        local w = window.selfStyle.width
        local h = window.selfStyle.height
        if type(w) ~= "number" then
            w = window.renderedWidth
        end
        if type(h) ~= "number" then
            h = window.renderedHeight
        end
        if w == skel.w and h == skel.h then
            return
        end
        skel.w = w
        skel.h = h
        local zoom = HeroSheetWindow.Zoom()
        inner.selfStyle.width = w / zoom
        inner.selfStyle.height = h / zoom
        ArrangeSkeleton(HeroSheetWindow.PickTier(w / TierScale(), skel.tier or window.data.tier))
    end

    --A resize drag starts: the content collapses under the skeleton. The
    --Builder lays itself out for the whole window and is left as it is.
    StartSkeleton = function()
        if window == nil or not window.valid or window.data.builder then
            return
        end
        if skeleton == nil then
            BuildSkeleton()
        end
        local skel = skeleton
        if skel == nil or skel.active then
            return
        end
        skel.active = true
        skel.holderWasCollapsed = holder:HasClass("collapsed")
        holder:SetClass("collapsed", true)
        skel.panel:SetClass("collapsed", false)
        --laid out afresh for this drag: the tab may have changed since the last.
        skel.tier = nil
        skel.tab = nil
        skel.w = nil
        skel.h = nil
        FitSkeleton()
    end

    --The drag ends: the content shows again (the caller re-flows it).
    EndSkeleton = function()
        local skel = skeleton
        if skel == nil or not skel.active then
            return
        end
        skel.active = false
        skel.panel:SetClass("collapsed", true)
        holder:SetClass("collapsed", skel.holderWasCollapsed == true)
    end

    --the Builder's place (setBuilder); its height is set by Reflow. Like
    --the holder, a drag starting on it does not move the window.
    builderHost = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = 600,
        valign = "top",
        draggable = true,
        dragMove = false,
    }

    inner = gui.Panel{
        classes = {"heroSheetInner"},
        halign = "left",
        valign = "top",
        flow = "vertical",
        width = "100%",
        height = "100%",
        titleBar,
        holder,
        builderHost,
    }

    window = gui.Panel{
        classes = {"heroSheetWindow"},
        styles = WindowStyles(),
        bgimage = "panels/square.png",
        halign = "left",
        valign = "top",
        flow = "vertical",
        raiseOnPress = true,
        swallowPress = true,
        --the window moves by its title bar: the content below takes any drag
        --that starts on it (see the holder), so only the title bar is left.
        draggable = true,
        dragMove = false,
        --Stays in its layer while dragged, as map windows do: lifted over the
        --UI, the whole sheet restyles on every frame of the drag and stutters.
        dragInPlace = true,
        drag = function(element)
            local data = element.data
            if data.maximized or data.minimized or data.poppedOut or data.fullscreen or data.builder then
                return
            end
            local lw, lh = Tabletop.LayerSize()
            local w = element.renderedWidth
            --keep enough of it on the table to grab again.
            element.x = math.max(120 - w, math.min(element.xdrag, lw - 120))
            element.y = math.max(0, math.min(element.ydrag, lh - TITLE_HEIGHT))
            RememberGeometry(element)
        end,
        data = {
            maximized = args.maximized == true,
            minimized = false,
            poppedOut = false,
            fullscreen = args.fullscreen == true,
            builder = false,
            --- @type nil|{top: number, bottom: number}
            review = nil,
            charid = args.charid,
            closed = false,
            minimize = Minimize,
            restore = Restore,
            setMaximized = SetMaximized,
            popOut = PopOut,
            setBuilder = SetBuilder,
            setReview = SetReview,
        },

        --the native-window canvas reports the popped-out window's size.
        resize = function(element, w, h)
            if element.data.poppedOut then
                element.selfStyle.width = w
                element.selfStyle.height = h
                Reflow()
            end
        end,

        --Font Size or the icon rail changed: zoom and tier follow at once;
        --Transparent UI changed: the backdrop frosts or goes solid.
        multimonitor = {"fontsize", "iconrail", "graphics:uiblur"},
        monitor = function(element)
            --plates change with Transparent UI too, so the rules are rebuilt.
            element.styles = WindowStyles()
            HeroSheetTheme.ApplyBackdrop(element)
            Reflow()
        end,

        --the user closed the popped-out OS window.
        nativeWindowClosed = function(element)
            args.onClose()
        end,

        --Escape closes the sheet only when nothing inside
        --is open (pop-ups, menus and fields take it first: they sit at higher
        --priorities) and the sheet was the last thing pressed. The watcher
        --below turns captureEscape off once the map or another window is
        --pressed, so a targeting cast or a selection gets its Escape back;
        --map tools always outrank it.
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_CHARACTER_SHEET,
        escape = function(element)
            if args.onEscape ~= nil and args.onEscape() then
                return
            end
            args.onClose()
        end,

        inner,

        --keeps captureEscape on while the sheet holds Escape (see escape
        --above). Stops with the window: a collapsed (minimized) panel does
        --not think.
        gui.Panel{
            floating = true,
            interactable = false,
            width = 1,
            height = 1,
            thinkTime = 0.1,
            think = function(element)
                local data = window.data
                local holds = data.poppedOut or data.maximized or data.fullscreen or data.builder
                    or HeroSheetWindow.IsFrontmost(window)
                if window.captureEscape ~= holds then
                    window.captureEscape = holds
                end
            end,
        },
    }

    --the backdrop frosts (or goes solid) now and whenever the scheme changes.
    HeroSheetTheme.ApplyBackdrop(window)
    HeroSheetTheme.Track(window, function(panel)
        panel.styles = WindowStyles()
        HeroSheetTheme.ApplyBackdrop(panel)
    end)

    window.data.place = Place
    window.data.hide = Hide
    window.data.reopen = Reopen
    window.data.setContent = SetContent
    return window
end

--- Put a built window up, in the mode its data says (Place picks its layer).
--- @param window Panel
function HeroSheetWindow.Show(window)
    window.data.place()
    HeroSheetWindow.BringToFront(window)
end

--- Bring the window forward: a popped-out one's OS window to the top; a
--- restored one over the table's other windows; a maximized or full-screen
--- one only as far as the bottom of the main dialog layer, so the panels
--- menu, settings, editors and dialogs opened there stay above it while it
--- still covers the table.
--- @param window nil|Panel
function HeroSheetWindow.BringToFront(window)
    if window == nil or not window.valid then
        return
    end
    local data = window.data
    if data.poppedOut then
        --a popped-out window has no siblings to reorder (the engine throws);
        --raise its OS window instead.
        window:RaiseNativeWindow()
    elseif data.maximized or data.fullscreen or data.builder then
        window:SetAsFirstSibling()
    else
        window:SetAsLastSibling()
    end
end

----------------------------------------------------------------------
--Pop-ups: every window opened from the sheet, the
--Builder or Level up follows Font Size as the sheet does. It is sized from
--the screen, not the sheet window: it zooms by Font Size, is capped to the
--screen (its body scrolls when taller), and sits centred or beside an
--anchor, pulled back inside the screen. It goes in the cover layer, so it
--is over the sheet whether the sheet is restored or maximized.

--Space kept between a pop-up and the screen's edge, in screen units.
local POPUP_MARGIN = 16

--- The smallest a target may be drawn in a pop-up's own units so it is still
--- 24 units on screen when Font Size is below 100%. Always a whole number,
--- so callers can format it with %d.
--- @param size nil|number the target's design size (default 24)
--- @return number
function HeroSheetWindow.TargetSize(size)
    size = size or 24
    local zoom = HeroSheetWindow.Zoom()
    if zoom < 1 then
        return math.ceil(math.max(size, 24 / zoom))
    end
    return size
end

--- Runs fn once this frame's layout is done, when sizes are right, and lays
--- out what fn changes before the frame is drawn: a fit never shows a frame
--- of the unfitted layout.
--- @param fn fun()
function HeroSheetWindow.AfterLayout(fn)
    gui.AfterLayout(function()
        if mod.unloaded then
            return
        end
        fn()
    end)
end

--- The `rendered` handler of a panel that fits itself on `think` from its own
--- size (a column count, pairing, a crop): when its size changes, its think
--- also runs once layout is done, so the fit is drawn with the new size
--- rather than a frame, or a think interval, later.
--- @param element Panel
function HeroSheetWindow.ThinkOnResize(element)
    HeroSheetWindow.AfterLayout(function()
        if element.valid then
            element:FireEvent("think")
        end
    end)
end

--- A short message at the bottom of the screen, as the app's other toasts.
--- @param text string
function HeroSheetWindow.Toast(text)
    local toast = rawget(_G, "ViewsToast")
    if toast ~= nil then
        toast(text)
    end
end

--- A plain-text body for a small sheet window.
--- @param text string
--- @return Panel
function HeroSheetWindow.DialogText(text)
    return gui.Label{
        classes = {"heroSheetCardText"},
        text = text,
        fontSize = 14,
        width = "100%",
        height = "auto",
        textWrap = true,
    }
end

--- The layer the sheet's pop-ups go in, over the sheet however it shows.
--- Its x / y are Tabletop.PanelRect's units (a drag chip uses it).
--- @return nil|Panel
function HeroSheetWindow.PopupLayer()
    return CoverLayer() or Tabletop.DocumentsLayer()
end

--- @class HeroSheetPopupArgs
--- @field content Panel built at its design size, in sheet units
--- @field width number design width in sheet units
--- @field height number design height in sheet units: the frame's height before the screen caps it; content taller than the frame scrolls
--- @field anchor nil|Panel opens beside this panel (right of it, else left) instead of centred
--- @field below nil|boolean with anchor: opens under it instead, left edges lined up (a popover from a pill)
--- @field alignRight nil|boolean with below: right edges lined up instead, so a menu from a button at a window's right edge stays inside the window
--- @field onClose nil|fun() called once when the pop-up goes
--- @field dismissOutside nil|boolean a click outside closes it (default: true when anchored)
--- @field modal nil|boolean dims everything behind it, which takes no clicks until it closes
--- @field onEscape nil|fun(): boolean runs on Esc before the pop-up closes; true keeps it open (it used the key, e.g. to clear a selection)

--- Open a pop-up that follows Font Size. Returns the frame; close it with
--- HeroSheetWindow.ClosePopup(frame).
--- @param args HeroSheetPopupArgs
--- @return nil|Panel
function HeroSheetWindow.ShowPopup(args)
    local layer = CoverLayer() or Tabletop.DocumentsLayer()
    if layer == nil then
        return nil
    end

    local frame
    local backdrop = nil
    --pinned to the top from the start: a scrolling body centres content and
    --hides its top until it lays out again.
    args.content.selfStyle.valign = "top"
    local body = gui.Panel{
        width = "100%",
        height = "100%",
        valign = "top",
        vscroll = false,
        args.content,
    }

    --Sizes and places the frame for the current Font Size: design size times
    --the zoom, capped to the screen, then centred or set beside the anchor.
    local function Layout()
        if frame == nil or not frame.valid then
            return
        end
        local zoom = HeroSheetWindow.Zoom()
        local lw, lh = Tabletop.LayerSize()
        local w = math.min(args.width * zoom, lw - 2 * POPUP_MARGIN)
        local h = math.min(args.height * zoom, lh - 2 * POPUP_MARGIN)
        local x = (lw - w) / 2
        local y = (lh - h) / 2
        local anchor = args.anchor
        if anchor ~= nil and anchor.valid then
            local anchorRect = Tabletop.PanelRect(anchor)
            if anchorRect ~= nil and args.below then
                x = cond(args.alignRight, anchorRect.x + anchorRect.w - w, anchorRect.x)
                y = anchorRect.y + anchorRect.h + 6
            elseif anchorRect ~= nil then
                x = anchorRect.x + anchorRect.w + 8
                if x + w > lw - POPUP_MARGIN then
                    x = anchorRect.x - w - 8
                end
                y = anchorRect.y
            end
        end
        x = math.max(POPUP_MARGIN, math.min(x, lw - w - POPUP_MARGIN))
        y = math.max(POPUP_MARGIN, math.min(y, lh - h - POPUP_MARGIN))
        frame.x = math.floor(x)
        frame.y = math.floor(y)
        --the frame's own units are sheet units: the zoom brings them to w x h.
        frame.selfStyle.pivot = {x = 0, y = 1}
        frame.selfStyle.uiscale = zoom
        frame.selfStyle.width = w / zoom
        frame.selfStyle.height = h / zoom
        --the body scrolls only when the screen caps the frame below its
        --design height.
        body.vscroll = h < args.height * zoom - 0.5
    end

    frame = gui.Panel{
        --a solid tint, never frosted: one frosted surface per window.
        classes = {"heroSheetPopup", "framedPanel"},
        styles = WindowStyles(),
        bgimage = "panels/square.png",
        halign = "left",
        valign = "top",
        swallowPress = true,
        data = {
            onClose = args.onClose,
        },
        multimonitor = {"fontsize", "iconrail"},
        monitor = function(element)
            Layout()
        end,
        --a pop-up is a nested surface: Escape closes it before the sheet.
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            if args.onEscape ~= nil and args.onEscape() then
                return
            end
            element:DestroySelf()
        end,
        destroy = function(element)
            if backdrop ~= nil and backdrop.valid then
                backdrop:DestroySelf()
            end
            backdrop = nil
            local onClose = element.data.onClose
            element.data.onClose = nil
            if onClose ~= nil then
                onClose()
            end
        end,
        body,
    }
    --a click anywhere outside closes an anchored pop-up (a popover); a modal
    --one dims what is behind it instead and keeps it from being clicked.
    local dismissOutside = args.dismissOutside
    if dismissOutside == nil then
        dismissOutside = args.anchor ~= nil
    end
    if dismissOutside or args.modal then
        backdrop = gui.Panel{
            bgimage = "panels/square.png",
            --a 62% scrim as designed: the engine blends in linear light, so it
            --takes about 86% here to look as dark.
            bgcolor = cond(args.modal, "#000000db", "clear"),
            halign = "left",
            valign = "top",
            width = "100%",
            height = "100%",
            press = function(element)
                if not args.modal then
                    HeroSheetWindow.ClosePopup(frame)
                end
            end,
        }
        layer:AddChild(backdrop)
    end
    layer:AddChild(frame)
    HeroSheetTheme.Track(frame, function(panel)
        panel.styles = WindowStyles()
    end)
    Layout()
    frame:SetAsLastSibling()
    return frame
end

--- The width a pop-up of this design width gets, in sheet units: the screen
--- caps it (Font Size zooms the design). A window that rearranges itself
--- when narrow measures with this before it builds.
--- @param width number design width in sheet units
--- @return number
function HeroSheetWindow.DialogWidth(width)
    local zoom = HeroSheetWindow.Zoom()
    local lw = Tabletop.LayerSize()
    return math.min(width * zoom, lw - 2 * POPUP_MARGIN) / zoom
end

--- Close a pop-up opened with ShowPopup (its onClose runs once).
--- @param frame nil|Panel
function HeroSheetWindow.ClosePopup(frame)
    if frame ~= nil and frame.valid then
        frame:DestroySelf()
    end
end

--- @class HeroSheetDialogArgs
--- @field title string the window's name, shown in capitals in its header
--- @field subtitle nil|string muted after the name: whose window it is (the Hero's name)
--- @field flush nil|boolean the body fills the window edge to edge (it brings its own padding, e.g. columns that scroll)
--- @field onEscape nil|fun(): boolean Esc runs this first; true keeps the window open
--- @field body Panel the content, laid out inside the window's side padding
--- @field width number design width in sheet units (a small window is 520)
--- @field bodyHeight number the content's design height in sheet units
--- @field onSave nil|fun(): nil|boolean a window that commits a change gets Cancel and Save; return false to keep it open
--- @field saveText nil|string Save's words for a window that commits something else (a confirm's "Delete")
--- @field onCancel nil|fun() runs on Cancel, Esc, or the window closing any other way before Save
--- @field onDone nil|fun() a window that saves as you go gets Done instead
--- @field note nil|string muted words before the footer's buttons ("Saved as you type.")
--- @field footerLeft nil|Panel at the footer's left, apart from the buttons (a note's Delete)

--The header (top gap, its name, bottom gap) and the body's padding, in
--sheet units: with the footer they give the window's height.
local DIALOG_HEAD = 16 + 26 + 12
local DIALOG_BODY_PAD = 14

--- Open a sheet window over the sheet: its
--- name in a header, the content, then Cancel and Save (or Done). Everything
--- behind it dims and waits until it closes. Returns the frame (close it with
--- ClosePopup).
--- @param args HeroSheetDialogArgs
--- @return nil|Panel
function HeroSheetWindow.ShowDialog(args)
    local frame
    --Save or Done closed it: anything else counts as Cancel.
    local finished = false
    local onSave = nil
    if args.onSave ~= nil then
        onSave = function()
            if args.onSave() ~= false then
                finished = true
                HeroSheetWindow.ClosePopup(frame)
            end
        end
    end
    local buttons = HeroSheetTheme.WindowButtons{
        onSave = onSave,
        saveText = args.saveText,
        note = args.note,
        onCancel = function()
            HeroSheetWindow.ClosePopup(frame)
        end,
        onDone = function()
            finished = true
            if args.onDone ~= nil then
                args.onDone()
            end
            HeroSheetWindow.ClosePopup(frame)
        end,
    }
    local function Rule(class)
        return gui.Panel{
            classes = {class},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
        }
    end
    local footHeight = 12 + HeroSheetWindow.TargetSize(36) + 12
    local footChildren = {buttons}
    if args.footerLeft ~= nil then
        table.insert(footChildren, 1, args.footerLeft)
    end
    local bodyPad = cond(args.flush, 0, DIALOG_BODY_PAD)
    local head = {
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = args.title,
            uppercase = true,
            fontSize = 20,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
    }
    if args.subtitle ~= nil then
        head[#head+1] = gui.Label{
            classes = {"heroSheetCardSub"},
            text = args.subtitle,
            fontSize = 14,
            width = "auto",
            height = "auto",
            lmargin = 12,
            halign = "left",
            valign = "center",
            textWrap = false,
        }
    end
    --a window is at least as wide as its name in the header (shown in
    --capitals, 20 bold) and its subtitle, so a long item name never spills.
    local headWidth = HeroSheetTheme.TextWidth(string.upper(args.title), 20) * 1.12 + 40
    if args.subtitle ~= nil then
        headWidth = headWidth + 12 + HeroSheetTheme.TextWidth(args.subtitle, 14)
    end
    frame = HeroSheetWindow.ShowPopup{
        width = math.max(args.width, math.ceil(headWidth)),
        height = DIALOG_HEAD + 1 + args.bodyHeight + 2 * bodyPad + 1 + footHeight,
        modal = true,
        dismissOutside = false,
        onEscape = args.onEscape,
        onClose = function()
            --a sheet window closing makes the window sound; small pop-ups
            --stay silent.
            audio.FireSoundEvent("UI.WindowClose")
            if not finished and args.onCancel ~= nil then
                args.onCancel()
            end
        end,
        content = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = 26,
                hpad = 20,
                borderBox = true,
                tmargin = 16,
                bmargin = 12,
                flow = "horizontal",
                children = head,
            },
            Rule("heroSheetDialogRule"),
            gui.Panel{
                width = "100%",
                height = args.bodyHeight + 2 * bodyPad,
                hpad = cond(args.flush, 0, 20),
                vpad = bodyPad,
                borderBox = true,
                flow = "vertical",
                args.body,
            },
            Rule("heroSheetFooterRule"),
            gui.Panel{
                width = "100%",
                height = footHeight,
                hpad = 20,
                borderBox = true,
                flow = "none",
                children = footChildren,
            },
        },
    }
    if frame ~= nil then
        audio.FireSoundEvent("UI.WindowOpen")
    end
    return frame
end
