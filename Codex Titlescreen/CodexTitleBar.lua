local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local g_devInventorySetting = setting{
    id = "dev:storepreview",
    default = true,
    storage = "preference",
}

g_devInventorySetting:Set(true)

-- Open the shop/inventory screen. The screen needs a host panel that has a
-- .data.dialog (for sizing) and that it can be parented to. On the
-- titlescreen/lobby that host is CodexTitlescreenRoot; once in a real game
-- the titlescreen is gone, so we host it on the game hud's dedicated
-- fullscreen shopPanel instead.
local function OpenShopScreen(inventory)
    if dmhub.inGame and not dmhub.isLobbyGame and GameHud.instance and GameHud.instance.shopPanel then
        local host = GameHud.instance.shopPanel
        host:AddChild(CreateShopScreen{ titlescreen = host, inventory = inventory })
    elseif CodexTitlescreenRoot ~= nil and CodexTitlescreenRoot.valid then
        CodexTitlescreenRoot:AddChild(CreateShopScreen{ titlescreen = CodexTitlescreenRoot, inventory = inventory })
    end
end

-- Shop/Inventory menu entries, gated behind the dev:storepreview setting.
-- Returned for both the main-menu Codex menu and the in-game Codex menu so
-- the options are reachable everywhere in the app.
local function GetStoreMenuItems()
    if not g_devInventorySetting:Get() then
        return {}
    end

    return {
        {
            text = "Shop",
            icon = "icons/icon_shopping/shopping-cart.png",
            click = function()
                OpenShopScreen(false)
            end,
        },
        {
            text = "Inventory",
            icon = "ui-icons/gift-icon.png",
            click = function()
                OpenShopScreen(true)
            end,
        },
    }
end

--------------------------------------------------------------------------------
--Bug ticket state (Report Feedback > Your Tickets).
--
--Submitting a bug report also opens a ticket at /Tickets/{userid}/{reportId}
--in the cloud: the user-visible conversation where developers respond. This
--module-level state caches the local user's tickets so the title bar can show
--a new-content marker when a developer has responded to a ticket the user has
--not viewed yet (ticket.lastDevMessageAt > ticket.userSeenAt).
--
--The C# bridge (dmhub.GetMyTickets and friends) may not exist on older builds,
--so access goes through pcall and the feature quietly disappears without it.
--------------------------------------------------------------------------------

local g_ticketsState = {
    tickets = nil,     --map of reportId -> ticket record; nil before any fetch.
    hasUnseen = false, --true when any ticket has an unviewed developer response.
}

--marker panels (created by CreateCodexMenuItem for menus with newContentCheck)
--that receive a "refreshAlert" event whenever the ticket state changes.
local g_menuAlertPanels = {}

--Tickets the user has viewed this session: reportId -> seen-through timestamp.
--MarkTicketSeen's server write is fire-and-forget, so a fetch that lands
--before it would resurrect the marker for a ticket the user just read; this
--floor makes locally-viewed always win over stale server data.
local g_localTicketSeenFloor = {}

local function TicketBridgeAvailable()
    local ok, fn = pcall(function() return dmhub.GetMyTickets end)
    return ok and fn ~= nil
end

--Closing/reopening a ticket from the client arrived after the ticket dialog
--itself, so it gets its own probe: on an older engine the button is simply
--absent rather than erroring on click.
local function TicketStatusBridgeAvailable()
    local ok, fn = pcall(function() return dmhub.SetTicketStatus end)
    return ok and fn ~= nil
end

--Merged title bar: the engine strips the native Windows caption so this bar
--sits flush with the top of the window, and the bar supplies dragging plus
--the minimize / maximize / close buttons (LuaInterfaceWindowChrome.cs). On
--engines without the bridge, or non-Windows platforms, the feature is
--simply absent.
local g_windowChromeAvailable = nil
local function WindowChromeBridgeAvailable()
    if g_windowChromeAvailable == nil then
        local ok, avail = pcall(function() return dmhub.mergedTitleBarAvailable end)
        g_windowChromeAvailable = (ok and avail == true)
    end
    return g_windowChromeAvailable
end

local function MergedTitleBarActive()
    return WindowChromeBridgeAvailable() and dmhub.GetSettingValue("mergedtitlebar") == true
end

local function ApplyMergedTitleBar()
    if WindowChromeBridgeAvailable() then
        dmhub.SetMergedTitleBar(dmhub.GetSettingValue("mergedtitlebar") == true)
    end
end

setting{
    id = "mergedtitlebar",
    description = "Merge window title bar",
    storage = "preference",
    editor = "check",
    default = true,
    onchange = function()
        ApplyMergedTitleBar()
    end,
}

--apply the stored preference at module load (and re-apply on reloads --
--SetMergedTitleBar is idempotent).
ApplyMergedTitleBar()

--Window-transition guard: window geometry changes (maximize / restore, and
--the boot-time merge convergence) take the engine a few frames to re-layout,
--and the DWM transition animation happily showcases the bar mid-layout. While
--the guard is active the bar's CONTENTS are hidden (the flat surface strip
--stays, so the bar reads as an empty native caption) and are revealed only
--once the screen resolution has held still for a run of samples.
local g_menuBarPanel = nil
local g_transitionToken = 0
local g_transitionActive = false

--Keeps the bar inside its own width; defined further down, but the transition
--guard below runs it while the bar is hidden so a resize is already absorbed
--by the time the bar is revealed.
local BarFitApply

--The maximize/restore window control. Held separately from the bar tree
--because the stage-2 hit regions report it to the engine as the native
--HTMAXBUTTON zone (Windows 11 Snap Layouts flyout), after which its mouse
--interaction is relayed back through the windowMaxButtonState /
--windowMaxButtonClick global events rather than normal gui events.
local m_maximizeControl = nil

local function StartWindowTransitionGuard(stableSamples, timeout, reason)
    local bar = g_menuBarPanel
    if bar == nil or not bar.valid or not MergedTitleBarActive() then
        return
    end

    stableSamples = stableSamples or 6
    timeout = timeout or 2.5

    g_transitionToken = g_transitionToken + 1
    local token = g_transitionToken

    if not g_transitionActive then
        g_transitionActive = true
        bar:SetClassTree("windowTransition", true)
    end

    local dims = dmhub.screenDimensions
    local lastW, lastH = dims.x, dims.y
    local stable = 0
    local started = dmhub.Time()

    local function poll()
        if mod.unloaded or token ~= g_transitionToken then
            return
        end
        if not bar.valid then
            g_transitionActive = false
            return
        end

        local d = dmhub.screenDimensions
        if d.x == lastW and d.y == lastH then
            stable = stable + 1
        else
            stable = 0
            lastW = d.x
            lastH = d.y
        end

        --Re-fit while still hidden. The collapse ladder moves one step per
        --pass, so running it on the poll cadence lets a big resize settle
        --into its final layout before the bar comes back into view.
        BarFitApply()

        --reveal once the resolution has held still, or on a hard timeout so
        --the bar can never be lost to a stuck transition. The dead-man
        --heartbeat is unaffected: hiding is opacity only, thinks keep running.
        if stable >= stableSamples or dmhub.Time() - started > timeout then
            g_transitionActive = false
            bar:SetClassTree("windowTransition", false)
            return
        end

        dmhub.Schedule(0.05, poll)
    end

    dmhub.Schedule(0.05, poll)
end

----------------------------------------------------------------------
-- Narrow-bar fit.
--
-- The whole title bar is ONE horizontal flow, and the engine abandons
-- alignment the moment a horizontal flow overfills: SheetPanel's
-- LayoutChildrenInternal packs EVERY child from the left once nothing is
-- left over (`if(available <= 0f) numLeft = childPanels.Count`). So an
-- overfull bar walks its right-hand cluster -- the minimize / maximize /
-- close buttons -- straight off the right edge of the screen. Nothing
-- ellipsizes or clips on its own to stop that.
--
-- So the bar keeps itself inside its own width. Space is handed back in a
-- fixed order, least-missed first: the search box narrows, then the map
-- name, then the menu strip's padding. If shrinking is not enough the
-- collapse ladder below takes whole elements away in the same spirit.
-- The window buttons are never in either list.
----------------------------------------------------------------------

--Bar units held back from the budget. The engine's flow also charges each
--child's horizontal MARGINS, which are not part of any panel's
--renderedWidth, so a plain width sum reads UNDER the true demand -- the
--hidden presentation bar alone carries a 32-unit rmargin. Measured at 32
--on an in-game bar; 44 leaves a little slack.
local BAR_FIT_RESERVE = 44

--Coming back out of a shrink needs more room than staying in it, or a bar
--sitting exactly on a boundary flips between two layouts every tick.
local BAR_FIT_HYSTERESIS = 24

--Floors for the elements that shrink rather than vanish. The search floor
--still shows a few characters of a query; the map-name floor still shows
--enough of a map's name to recognise it (both ellipsize past that).
local BAR_FIT_SEARCH_MIN = 132
local BAR_FIT_MAPNAME_MIN = 84
local BAR_FIT_MAPNAME_FULL = 380

--Menu strip: {menuItem} ships hpad 8 and {menuLabel} hmargin 4, so each
--item can give back 2*(8-2) of padding and each label 2*(4-1) of margin
--without touching the type size.
local BAR_FIT_MENU_HPAD, BAR_FIT_MENU_HPAD_MIN = 8, 2
local BAR_FIT_MENU_MARGIN, BAR_FIT_MENU_MARGIN_MIN = 4, 1

--Defined with the search bar further down; the fit pass needs the box's
--natural width, which tracks the dock-scale setting.
local SearchBoxWidth

--Panels the fit pass drives, registered by the factories that build them.
--Every entry is optional -- the title-screen bar builds a different subset
--than an in-game one -- and each is re-validated before use.
local g_barFit = {
    panels = {},        --name -> Panel; the shrink stages and the ladder both
                        --look their subjects up here
    naturals = {},      --key -> last width seen while visible
    depth = 0,          --how many collapse-ladder steps are applied
    withheld = 0,       --bar units the previous pass was saving
    menusDropped = {},  --panel id -> true for menu items the ladder dropped

    --Last values pushed out, so a pass only writes when something actually
    --changed. These are memos rather than reads of selfStyle because reading
    --a style property that was never explicitly set raises ("Error indexing
    --userdata") -- menu-item hpad and label hmargin both come from class
    --styles, so neither can be read back.
    appliedMapName = nil,
    appliedMenuHpad = nil,
    appliedMenuMargin = nil,
}

--The collapse ladder, most expendable first: the map info, then the search
--box, then the status readouts, and only then the menu strip. "menus" is the
--last resort and expands into one step per menu item, dropped from the RIGHT
--of the strip so the Codex menu -- and with it Settings and Quit -- is the
--final survivor.
--
--The search box still SHRINKS first (stage 1 of the fit pass), but the whole
--map cluster is taken away before the box itself is: the search gets used
--constantly, while the map name survives on the cluster's tooltip and the
--full Maps panel.
--
--No step may be an ANCESTOR of another: both would be credited with the same
--pixels when the pass reconstructs the bar's natural demand. That is why the
--map cluster is represented by its two children (the name and the terrain
--chip) rather than by the cluster itself.
local BAR_FIT_LADDER = {
    "mapName", "mapChip", "search",
    "initiative", "devGame", "connectivity", "audio",
    "menus",
}

--Returns the panel, so an element declared inline in a child list can be
--registered without being pulled out into a local first.
local function BarFitRegister(name, panel)
    g_barFit.panels[name] = panel
    return panel
end

--The menu strip, in left-to-right order. Read off the bar rather than
--registered by the factories, because the factories do not run in bar order
--(Adventure Documents is built well before the Codex/Game/Tools items it sits
--after). Direct children only: the map cluster also wears "menuItem", but it
--lives inside the status bar, not on the bar itself.
local function BarFitMenuItems(bar)
    local items = {}
    for _,child in ipairs(bar.children) do
        if child.valid and child:HasClass("menuItem") then
            items[#items+1] = child
        end
    end
    return items
end

--The ladder flattened into concrete steps, so applying it and costing a
--restore both index the same list. Keys are stable per element (panel ids)
--because the remembered natural widths are looked up by key.
local function BarFitSteps(menuItems)
    local steps = {}
    for _,name in ipairs(BAR_FIT_LADDER) do
        if name ~= "menus" then
            steps[#steps+1] = {key = name, panel = g_barFit.panels[name]}
        else
            --Only menu items that are actually on screen have anything to
            --give, so items the bar has hidden for its own reasons (the
            --main-menu-only Codex entry while in game, Developer outside dev
            --mode) are skipped rather than burning a ladder step on a
            --zero-width panel. Items THIS pass hid still count, or the step
            --list would shuffle underneath the depth counter.
            local live = {}
            for _,item in ipairs(menuItems) do
                if item.valid and (item.enabled or item:HasClass("barFitHidden")) then
                    live[#live+1] = item
                end
            end
            --live[1] is never dropped: it keeps the Codex menu, and with it
            --Settings and Quit to Desktop, reachable at any window width.
            for i = #live, 2, -1 do
                steps[#steps+1] = {key = "menu:" .. tostring(live[i].id), panel = live[i], isMenu = true}
            end
        end
    end
    return steps
end

--True once the fit pass has dropped this menu item. The two menu items that
--own their own selfStyle.collapsed (Developer, keyed to dev mode, and
--Adventure Documents, keyed to the tracked document list) consult this from
--their own visibility code -- a selfStyle write beats any class rule, so the
--ladder cannot collapse them from the outside.
local function BarFitMenuDropped(element)
    if element == nil or not element.valid then
        return false
    end
    return g_barFit.menusDropped[element.id] == true
end

--Total width the bar's flow is currently asking for. Floating children (the
--drag surface) sit outside the flow, and a panel the engine has taken out of
--layout reports enabled == false.
local function BarFitMeasure(bar)
    local total = 0
    for _,child in ipairs(bar.children) do
        if child.valid and child.enabled
                and child.id ~= "titleBarDragSurface" then
            total = total + child.renderedWidth
        end
    end
    return total
end

--Remember how wide each ladder step is while it is still visible, so the pass
--knows what putting it back would cost.
local function BarFitLatchNaturals(steps)
    for _,step in ipairs(steps) do
        local panel = step.panel
        if panel ~= nil and panel.valid and panel.enabled and panel.renderedWidth > 0 then
            g_barFit.naturals[step.key] = panel.renderedWidth
        end
    end
end

--What a ladder step costs to put back, at NATURAL size.
local function BarFitStepNatural(step)
    --No latched width means the bar has never had this element on screen for
    --reasons of its own -- the search box on the title screen, the status
    --readouts with Show Status Bar off. Releasing the ladder would not bring
    --it back, so it must not be credited with space it never occupied.
    if g_barFit.naturals[step.key] == nil then
        return 0
    end
    --The two elements the shrink stages also drive get authoritative naturals:
    --their latched width is whatever they had been squeezed down to just
    --before being collapsed, which would under-report the cost of a restore
    --and make the ladder bounce back out too eagerly.
    if step.key == "search" then
        return SearchBoxWidth()
    elseif step.key == "mapName" then
        return BAR_FIT_MAPNAME_FULL
    end
    return g_barFit.naturals[step.key]
end

local function BarFitApplyLadder(steps, depth)
    local dropped = {}
    for i,step in ipairs(steps) do
        local on = (i <= depth)
        if step.panel ~= nil and step.panel.valid then
            step.panel:SetClass("barFitHidden", on)
            if on and step.isMenu then
                dropped[step.panel.id] = true
            end
        end
    end
    --read by the menu items that own their own selfStyle.collapsed
    g_barFit.menusDropped = dropped
end

--The fit pass. Called from the bar's think and from the window-transition
--guard, so a bar that was hidden through a resize is already correct when it
--is revealed. (Assigns the forward declaration up beside g_menuBarPanel.)
function BarFitApply()
    local bar = g_menuBarPanel
    if bar == nil or not bar.valid then
        return
    end

    local barWidth = bar.renderedWidth
    if barWidth == nil or barWidth <= 0 then
        return
    end

    local items = BarFitMenuItems(bar)
    local steps = BarFitSteps(items)
    BarFitLatchNaturals(steps)

    --clamped because the step list is rebuilt each pass and can get shorter
    --(a menu item the bar hid for its own reasons drops out of it)
    local depth = math.min(g_barFit.depth, #steps)

    --What the flow WOULD ask for with nothing shrunk and nothing collapsed.
    --The measurement already has the previous pass's savings applied, so both
    --kinds of saving are added back: that makes the budget an absolute figure
    --instead of a delta on itself, which is what lets the pass re-expand
    --rather than chase its own tail.
    local ladderSaved = 0
    for i = 1, depth do
        ladderSaved = ladderSaved + BarFitStepNatural(steps[i])
    end

    local demand = BarFitMeasure(bar) + g_barFit.withheld + ladderSaved

    --Total units that have to be given back, then what is still owed once the
    --collapse ladder's existing steps are credited.
    local owed = demand + BAR_FIT_RESERVE - barWidth
    local remaining = owed - ladderSaved

    --Each shrink stage below is gated on the element actually being laid out
    --(`enabled`), which rules out two different double-counts: an element the
    --LADDER collapsed is already credited in full by ladderSaved, and an
    --element the bar hides for its own reasons -- the search box on the title
    --screen, the whole status bar with Show Status Bar off -- occupies no
    --space to give back in the first place.
    local withheld = 0

    --Stage 1: the search box narrows first. It is the widest thing on the bar
    --that nobody is reading while they resize a window.
    local searchBar = g_barFit.panels.search
    if searchBar ~= nil and searchBar.valid and searchBar.enabled then
        local full = SearchBoxWidth()
        local target = full
        if remaining > 0 then
            target = math.max(BAR_FIT_SEARCH_MIN, full - remaining)
        end
        --this pass is the ONLY writer of the box's width (its own think used
        --to set it from SearchBoxWidth and would fight the squeeze)
        if searchBar.data.appliedSearchWidth ~= target then
            searchBar.data.appliedSearchWidth = target
            searchBar.selfStyle.width = target
        end
        withheld = withheld + (full - target)
        remaining = remaining - (full - target)
    end

    --Stage 2: then the map name, which ellipsizes as it narrows (the full
    --string stays available on the cluster's tooltip).
    local mapNameLabel = g_barFit.panels.mapName
    if mapNameLabel ~= nil and mapNameLabel.valid and mapNameLabel.enabled then
        local target = BAR_FIT_MAPNAME_FULL
        if remaining > 0 then
            target = math.max(BAR_FIT_MAPNAME_MIN, BAR_FIT_MAPNAME_FULL - remaining)
        end
        if g_barFit.appliedMapName ~= target then
            g_barFit.appliedMapName = target
            mapNameLabel.selfStyle.width = target
        end
        withheld = withheld + (BAR_FIT_MAPNAME_FULL - target)
        remaining = remaining - (BAR_FIT_MAPNAME_FULL - target)
    end

    --Stage 3: then the menu strip tightens. Padding and label margins only --
    --the type size is left alone, and the squeeze is spread evenly across the
    --items rather than flattening the leftmost ones first, so the strip stays
    --evenly spaced. Only items actually on screen can give anything back.
    local live = 0
    for _,item in ipairs(items) do
        if item.valid and item.enabled then
            live = live + 1
        end
    end
    local perItem = 2*(BAR_FIT_MENU_HPAD - BAR_FIT_MENU_HPAD_MIN)
        + 2*(BAR_FIT_MENU_MARGIN - BAR_FIT_MENU_MARGIN_MIN)
    if live > 0 then
        local share = 0
        if remaining > 0 then
            share = math.min(1, remaining / (live * perItem))
        end
        local hpad = math.floor(BAR_FIT_MENU_HPAD - share*(BAR_FIT_MENU_HPAD - BAR_FIT_MENU_HPAD_MIN) + 0.5)
        local margin = math.floor(BAR_FIT_MENU_MARGIN - share*(BAR_FIT_MENU_MARGIN - BAR_FIT_MENU_MARGIN_MIN) + 0.5)
        if hpad ~= g_barFit.appliedMenuHpad or margin ~= g_barFit.appliedMenuMargin then
            g_barFit.appliedMenuHpad = hpad
            g_barFit.appliedMenuMargin = margin
            for _,item in ipairs(items) do
                if item.valid then
                    item.selfStyle.hpad = hpad
                    item:FireEventTree("barFitMenuMargin", margin)
                end
            end
        end
        local given = live * (2*(BAR_FIT_MENU_HPAD - hpad) + 2*(BAR_FIT_MENU_MARGIN - margin))
        withheld = withheld + given
        remaining = remaining - given
    end

    g_barFit.withheld = withheld

    --Stage 4: still over budget with everything shrunk, so start taking whole
    --elements away, one step per pass -- that converges in a few ticks and
    --keeps the movement legible. Coming back out has to pay the step's own
    --width plus the hysteresis margin, so a bar sitting on a step boundary
    --does not flap between two layouts.
    if remaining > 0 then
        depth = math.min(depth + 1, #steps)
    elseif depth > 0 then
        local cost = BarFitStepNatural(steps[depth])
        if remaining + cost + BAR_FIT_HYSTERESIS <= 0 then
            depth = depth - 1
        end
    end

    if depth ~= g_barFit.depth then
        g_barFit.depth = depth
        BarFitApplyLadder(steps, depth)
    end
end

--Stage-2 hit regions: report the bar's REAL layout to the engine so the
--native caption hit-test uses exact rects instead of the engine's crude
--built-in constants. Exclusions are the bar's direct children (menu
--clusters, presentation/status bars, the right-side search + window-button
--cluster); the gaps between them become native caption -- drag, Aero snap
--and double-click-to-maximize all handled by Windows. The maximize control
--is reported separately so the engine can map it to HTMAXBUTTON, which is
--what makes the Snap Layouts flyout appear on hover. The engine snapshots
--the rects at call time, so this re-sends on the bar's think cadence to
--track layout changes; pcall-gated so an engine without the bridge (or
--running the legacy strip mode, where the engine ignores regions anyway)
--stays safe.
local function UpdateTitleBarHitRegions()
    local bar = g_menuBarPanel
    if bar == nil or not bar.valid or not MergedTitleBarActive() then
        return
    end
    pcall(function()
        if dmhub.titleBarChromeMode ~= "nccalcsize" then
            return
        end
        local exclusions = {}
        for _,child in ipairs(bar.children) do
            --skip the drag surface (it IS the draggable emptiness);
            --hidden/collapsed children are not interactive so they must
            --not eat caption either.
            if child.valid and child.id ~= "titleBarDragSurface"
                    and not child:HasClass("collapsed") and not child:HasClass("hidden") then
                exclusions[#exclusions+1] = child
            end
        end
        --while fullscreen the maximize control is disabled, so don't hand
        --it to the engine as the native HTMAXBUTTON zone (no Snap Layouts
        --flyout, no native click relay); the area stays inside the window
        --button cluster's exclusion so the gui's gated click handles it.
        local maxControl = nil
        if m_maximizeControl ~= nil and m_maximizeControl.valid
                and dmhub.GetSettingValue("fullscreen") ~= true then
            maxControl = m_maximizeControl
        end
        dmhub.SetTitleBarHitRegions{
            bar = bar,
            exclusions = exclusions,
            maximizeButton = maxControl,
        }
    end)
end

--A native-style caption control: a full-bar-height hover ZONE with a
--centered glyph. The zone -- not the glyph -- takes the hover fill and
--the click, matching how the real Windows caption buttons behave (zone
--styles: titleBarStyleExtras in CreateTopBar).
local function CreateWindowControl(args)
    return gui.Panel{
        classes = {"windowControl", cond(args.danger, "windowControlDanger")},
        bgimage = true,
        width = 42,
        height = "100%",
        valign = "center",
        data = { maximized = nil },
        calculateVisibility = args.calculateVisibility,
        click = args.click,

        gui.Panel{
            classes = {"windowControlIcon", cond(args.danger, "windowControlIconDanger")},
            bgimage = args.icon,
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            interactable = false,
            setIcon = function(element, icon)
                element.bgimage = icon
            end,
        },
    }
end

--Flips the "fullscreen" user setting; the engine's per-frame enforcer
--(GameHarness) applies it, exactly like Alt+Enter. Same choreography as
--the maximize button: hide the bar contents first, resize a beat later,
--so the hide is on screen before the mode change's mis-laid-out settle
--frames are. Used by the Fullscreen checkbox in the Codex menus.
local function ToggleFullscreen()
    StartWindowTransitionGuard(nil, nil, "fullscreen menu item")
    dmhub.Schedule(0.05, function()
        if not mod.unloaded then
            dmhub.SetSettingValue("fullscreen",
                not (dmhub.GetSettingValue("fullscreen") == true))
        end
    end)
end

local function TicketHasUnseenResponse(t)
    if type(t) ~= "table" then
        return false
    end
    local lastDev = t.lastDevMessageAt
    if lastDev == nil then
        return false
    end
    local seen = t.userSeenAt
    if t.reportId ~= nil then
        local floor = g_localTicketSeenFloor[t.reportId]
        if floor ~= nil and (seen == nil or floor > seen) then
            seen = floor
        end
    end
    return seen == nil or lastDev > seen
end

local function RefreshTicketAlerts()
    local unseen = 0
    if g_ticketsState.tickets ~= nil then
        for _,t in pairs(g_ticketsState.tickets) do
            if TicketHasUnseenResponse(t) then
                unseen = unseen + 1
            end
        end
    end
    g_ticketsState.hasUnseen = (unseen > 0)

    --notify the markers, pruning any belonging to a destroyed title bar.
    local live = {}
    for _,panel in ipairs(g_menuAlertPanels) do
        if panel.valid then
            live[#live+1] = panel
            panel:FireEvent("refreshAlert")
        end
    end
    g_menuAlertPanels = live

    --TICKETS:: diagnostic; runs only on fetch/view so it is cheap, and makes
    --a stuck or missing menu marker diagnosable straight from the console log.
    print(string.format("TICKETS:: alerts refreshed: unseen=%d markerPanels=%d", unseen, #live))
end

--Fetches the user's tickets from the cloud, refreshes the marker state, then
--calls callback(tickets, error) if given. Without the C# ticket bridge this
--reports no tickets and no error.
local function FetchTickets(callback)
    if not TicketBridgeAvailable() then
        if callback ~= nil then
            callback(nil, nil)
        end
        return
    end
    dmhub.GetMyTickets(function(tickets, error)
        if error == nil then
            g_ticketsState.tickets = tickets or {}
            RefreshTicketAlerts()
        end
        if callback ~= nil then
            callback(tickets, error)
        end
    end)
end

--The engine fires "ticketAlert" when the account monitor (which already
--streams /users/{userid}) sees the tickets dashboard bump the ticketAlert
--field -- i.e. a developer just responded to one of our tickets. Refetch so
--the Report Feedback marker appears immediately, with no polling.
dmhub.RegisterEventHandler("ticketAlert", function()
    FetchTickets()
end)

--The title bar's Codex / Game / Tools menus list "windows": panels the
--user summons by name rather than docks alongside other panels. BOTH
--registries feed them now that panels like Maps, the Measuring Tool and
--the Compendium are ordinary dockable panels.
--
--A dockable panel opts in by declaring `menu` in its registration
--("codex", "game" or "tools"), which is also what sorts it into the right
--one -- without that it belongs to the Panels menu only, which is what
--the ~40 regular dock panels want. The launchable panels that remain (the
--transient dialogs) keep their original contract, where no `menu` at all
--meant the Codex menu.
local function WindowMenuItems(menuName)
    local result = {}

    for _,item in ipairs(DockablePanel.GetMenuItems()) do
        if item.menu == menuName then
            result[#result+1] = item
        end
    end

    for _,item in ipairs(LaunchablePanel.GetMenuItems()) do
        if (item.menu or "codex") == menuName and item.text ~= "Development Tools" then
            result[#result+1] = item
        end
    end

    return result
end

local function CreateCodexMenuItem(args)
    local iconPanel

    local m_mainmenu = args.mainmenu
    args.mainmenu = nil

    local name = args.name
    args.name = nil
    local menuItems = args.menuItems
    args.menuItems = nil

    --optional: a function returning true when this menu should show the
    --new-content marker dot beside its name (e.g. an unviewed ticket
    --response). The marker re-evaluates on the "refreshAlert" event, fired
    --by RefreshTicketAlerts whenever ticket state changes.
    local newContentCheck = args.newContentCheck
    args.newContentCheck = nil

    local alertPanel = nil
    if newContentCheck ~= nil then
        --visibility is toggled with the "collapsed" CLASS, not selfStyle:
        --selfStyle writes from an async callback only mark styles dirty and
        --were not repainting until a hover re-applied styles; SetClass is the
        --documented reliable show/hide idiom (UI_BEST_PRACTICES.md).
        alertPanel = gui.NewContentAlert{
            x = 8,
            y = 2,
            valign = "top",
            classes = {cond(newContentCheck(), nil, "collapsed")},
            refreshAlert = function(element)
                element:SetClass("collapsed", not newContentCheck())
            end,
        }
        g_menuAlertPanels[#g_menuAlertPanels+1] = alertPanel
    end

    if args.icon then
        iconPanel = gui.Panel{
            classes = {"menuItemIcon"},
            width = 24,
            height = 24,
            bgimage = args.icon,
            valign = "center",
            interactable = false,
            seticon = function(element, icon)
                element.bgimage = icon
            end,
        }
        args.icon = nil
    end

    local CollectMenuItems
    CollectMenuItems = function(menuItems, result)
        for _,item in ipairs(menuItems) do
            if item.submenu then
                CollectMenuItems(item.submenu, result)
            else
                result[#result+1] = item
            end
        end
    end

    --mainmenu = true shows the item only on the main menu; mainmenu = "always"
    --shows it both on the main menu and in-game; otherwise in-game only.
    local visibilityClass
    if m_mainmenu == "always" then
        visibilityClass = nil
    elseif m_mainmenu then
        visibilityClass = "mainmenuOnly"
    else
        visibilityClass = "ingameOnly"
    end

	local resultPanel = {

        classes = {"menuItem", visibilityClass},
		popupPositioning = 'panel',

        width = "auto",
        height = "100%",
        flow = "horizontal",

        iconPanel,

        gui.Label{
            classes = {"menuLabel"},
            text = name,
            setname = function(element, newname)
                name = newname
                element.text = newname
            end,
            interactable = false,

            --the narrow-bar fit pass tightens the strip by trimming each
            --label's side margins (see BarFitApply stage 3). Written
            --unconditionally: the pass only fires this when the value
            --changed, and hmargin comes from {menuLabel} so it cannot be
            --read back to compare against.
            barFitMenuMargin = function(element, margin)
                element.selfStyle.hmargin = margin
            end,

            --floating marker dot pinned to the label's top-right corner.
            alertPanel,
        },

        collectMenuItems = function(element, result)
            CollectMenuItems(menuItems(), result)
        end,

        hover = function(element)
            --see if a sibling menu is shown.
            for _,sibling in ipairs(element.parent.children) do
                if sibling ~= element and sibling.popup ~= nil then
                    sibling.popup = nil
                    sibling:SetClass("menuOpen", false)
                    element:FireEvent("press")
                    return
                end
            end
        end,

		press = function(element)

           	if element.popup ~= nil then
				element.popup = nil
				element:SetClass("menuOpen", false)
				return
			end

			local menuItems = menuItems()

			element.popup = gui.Panel{
				width = "auto",
				height = "auto",
				halign = "right",
				valign = "bottom",
				gui.ContextMenu{
					width = 300,
					x = -element.renderedWidth,
					entries = menuItems,
					click = function()
						element.popup = nil
						element:SetClass("menuOpen", false)
					end,
				}
			}
			--the plate holds while the dropdown is open (Venla
			--2026-08-24, VS Code menu behavior): menuOpen carries the
			--same raised fill as hover, cleared on every close path --
			--including click-outside, via the closePopup event below.
			element:SetClass("menuOpen", true)

		end,

		closePopup = function(element)
			element:SetClass("menuOpen", false)
		end,
	}

    for k,v in pairs(args) do
        resultPanel[k] = v
    end

	return gui.Panel(resultPanel)

end


local function CreatePresentationBar()
    local resultPanel

    resultPanel = gui.Panel{
        data = {
            presentations = {}

        },
        width = "auto",
        height = 32,
        rmargin = 32,
        halign = "right",
        flow = "horizontal",

        selfStyle = {
            hidden = 1,
        },

        refreshPresentation = function(element)
            local presentationInfo = nil
            for k,v in pairs(element.data.presentations) do
                presentationInfo = v
                break
            end

            print("PRESENTATION:: REFRESH", presentationInfo ~= nil)

            if presentationInfo == nil then
                element.selfStyle.hidden = 1
            else
                element.selfStyle.hidden = 0
                element.children = {
                    gui.Label{
                        fontSize = 16,
                        color = Styles.textColor,
                        width = "auto",
                        height = "auto",
                        text = presentationInfo.text,
                        valign = "center",
                        hmargin = 4,
                    },
                    gui.EnumeratedSliderControl{
                        valign = "center",
                        width = 210,
                        options = presentationInfo.options,
                        value = presentationInfo.value,
                        change = function(element)
                            presentationInfo.onchange(element.value)
                        end,
                    }
                }
            end
        end,
    }

    return resultPanel
end

local g_showStatusBarSetting = setting{
    id = "showstatusbar",
    description = "Show status bar",
    editor = "check",
    default = true,
    storage = "preference",
    section = "General",
}

----------------------------------------------------------------------
-- Connectivity status panel
-- Replaces the old "Synced seq:N" label and its "DO Message History"
-- modal (retired 2026-08-08): a wifi glyph shows OUR connection to the
-- game server, then one portrait per player shows THEIR connectivity.
-- Clicking the panel opens the Heroes panel -- which is deliberately
-- hidden from the Panels/rail menus now; this is the way in. Player
-- portraits click to ping instead.
----------------------------------------------------------------------

local STATUS_COLOR_ONLINE = "#58b060"
local STATUS_COLOR_LAGGING = "#d8b23a"
local STATUS_COLOR_OFFLINE = "#7a7a7a"

--the syncing animation, in display order.
local g_syncFrames = {
    "phosphor/wifi-none.png",
    "phosphor/wifi-low.png",
    "phosphor/wifi-medium.png",
    "phosphor/wifi-high.png",
}

--Session-info classification, matching the Heroes panel's thresholds:
--pings write ~12s apart, so >60s since last contact means several
--misses (connection trouble), >=140s or loggedOut means gone.
local function ClassifyUserStatus(info)
    if info == nil or info.loggedOut or info.timeSinceLastContact >= 140 then
        return "offline"
    end
    if info.timeSinceLastContact > 60 then
        return "lagging"
    end
    return "online"
end

--All the character ids this player controls directly (ownerId ==
--userid). Party-shared tokens (ownerId == 'PARTY') are deliberately
--not counted as anyone's.
local function CharacterIdsOwnedBy(userid)
    local result = {}
    local partyType = rawget(_G, "Party")
    if partyType == nil then
        return result
    end
    local parties = dmhub.GetTable(partyType.tableName) or {}
    for partyid, _ in unhidden_pairs(parties) do
        for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.ownerId == userid then
                result[#result + 1] = charid
            end
        end
    end
    return result
end

--One player's entry: their main character's portrait (grouping card
--behind it when they control more than one), a connectivity dot in the
--corner, a status tooltip, click to ping.
local function CreatePlayerStatusIcon(userid, charid, extraCount)
    local token = nil
    if charid ~= nil then
        token = dmhub.GetCharacterById(charid)
    end

    local children = {}

    --multiple characters: a card behind the portrait reads as a stack.
    if extraCount > 0 then
        children[#children + 1] = gui.Panel{
            floating = true,
            halign = "center",
            valign = "center",
            x = 4,
            y = -4,
            width = 22,
            height = 22,
            bgimage = "panels/square.png",
            bgcolor = "#3a3a3a",
            borderWidth = 1,
            borderColor = "#9a9a9a",
            cornerRadius = 3,
        }
    end

    if token ~= nil then
        children[#children + 1] = gui.CreateTokenImage(token, {
            width = 26,
            height = 26,
            halign = "center",
            valign = "center",
            --portrait greys out when the player is gone, the same cue
            --the Heroes panel uses.
            updateStatus = function(element, info)
                element.selfStyle.saturation = cond(ClassifyUserStatus(info) == "offline", 0, 1)
            end,
        })
    else
        --a player with no character yet still shows, as a plain user
        --glyph, so their connectivity is visible.
        children[#children + 1] = gui.Panel{
            width = 20,
            height = 20,
            halign = "center",
            valign = "center",
            bgimage = "phosphor/user-fill.png",
            bgcolor = "#c0c0c0",
            updateStatus = function(element, info)
                element.selfStyle.saturation = cond(ClassifyUserStatus(info) == "offline", 0, 1)
            end,
        }
    end

    --connectivity dot: a dark backing circle so the color reads on any
    --portrait, then the status color.
    children[#children + 1] = gui.Panel{
        floating = true,
        width = 11,
        height = 11,
        halign = "right",
        valign = "bottom",
        x = 2,
        y = 0,
        bgimage = "game-icons/plain-circle.png",
        bgcolor = "#202020",
        gui.Panel{
            width = 8,
            height = 8,
            halign = "center",
            valign = "center",
            bgimage = "game-icons/plain-circle.png",
            bgcolor = STATUS_COLOR_OFFLINE,
            updateStatus = function(element, info)
                local status = ClassifyUserStatus(info)
                local color = STATUS_COLOR_OFFLINE
                if status == "online" then
                    color = STATUS_COLOR_ONLINE
                elseif status == "lagging" then
                    color = STATUS_COLOR_LAGGING
                end
                element.selfStyle.bgcolor = color
            end,
        },
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = 30,
        height = 30,
        halign = "left",
        valign = "center",
        rmargin = 2,
        bgimage = true,
        bgcolor = "clear",
        data = { userid = userid, info = nil, pingTime = nil },

        updateStatus = function(element, info)
            element.data.info = info
        end,

        linger = function(element)
            local info = element.data.info or dmhub.GetSessionInfo(userid)
            local lines = {}
            lines[#lines + 1] = (info ~= nil and info.displayName) or "Player"
            if token ~= nil then
                if extraCount > 0 then
                    lines[#lines + 1] = string.format("Playing %s (+%d more)", token.name or "a character", extraCount)
                else
                    lines[#lines + 1] = string.format("Playing %s", token.name or "a character")
                end
            end
            local status = ClassifyUserStatus(info)
            if status == "offline" then
                lines[#lines + 1] = "Offline"
            elseif status == "lagging" then
                lines[#lines + 1] = string.format("Connection trouble -- last seen %d seconds ago", math.floor(info.timeSinceLastContact))
            elseif info ~= nil and info.ping ~= nil then
                lines[#lines + 1] = string.format("Online -- ping %dms", math.floor(info.ping * 1000))
            else
                lines[#lines + 1] = "Online"
            end
            --no ping invitation for someone who is not there.
            if status ~= "offline" then
                lines[#lines + 1] = "Click to ping"
            end
            gui.Tooltip(table.concat(lines, "\n"))(element)
        end,

        click = function(element)
            --pinging an offline player would just time out; do nothing.
            local info = element.data.info or dmhub.GetSessionInfo(userid)
            if ClassifyUserStatus(info) == "offline" then
                return
            end
            local t = dmhub.Time()
            if element.data.pingTime ~= nil and (t - element.data.pingTime) < 10 then
                return
            end
            element.data.pingTime = t
            gui.Tooltip("Pinging...")(element)
            dmhub.PingUser(userid, function()
                if not element.valid then
                    return
                end
                local started = element.data.pingTime
                if started == nil then
                    return
                end
                element.data.pingTime = nil
                local info = element.data.info
                local name = (info ~= nil and info.displayName) or "Player"
                gui.Tooltip(string.format("%s responded in %dms", name, math.floor((dmhub.Time() - started) * 1000)))(element)
            end)
        end,

        children = children,
    }
    return resultPanel
end

local function CreateConnectivityPanel()
    local m_wifiIcon

    m_wifiIcon = gui.Panel{
        width = 22,
        height = 22,
        halign = "left",
        valign = "center",
        rmargin = 6,
        bgimage = "phosphor/wifi-high-fill.png",
        bgcolor = "#c8c8c8",
        data = { frame = 0 },
        linger = function(element)
            local lines = {}
            if dmhub.gameServerConnected == false then
                lines[#lines + 1] = "Disconnected from the game server -- reconnecting..."
            elseif dmhub.undoState.undoPending or dmhub.pendingWriteCount > 0 then
                lines[#lines + 1] = string.format("Syncing (%d writes pending)", dmhub.pendingWriteCount)
            else
                lines[#lines + 1] = "Synced with the game server"
            end
            local seq = dmhub.durableObjectSeq
            if seq ~= nil and seq > 0 then
                lines[#lines + 1] = string.format("Server message seq: %d", seq)
            end
            lines[#lines + 1] = "Click to open the Heroes panel"
            gui.Tooltip(table.concat(lines, "\n"))(element)
        end,
    }

    local playersRow = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        halign = "left",
        valign = "center",
        data = { cache = {} },

        monitorGame = "/usersToSessions",

        --the session doc only changes while users are alive and pinging;
        --a user going SILENT changes nothing, so poll too or the dot
        --stays green forever after a drop.
        thinkTime = 5,
        think = function(element)
            element:FireEvent("refreshGame")
        end,
        create = function(element)
            element:FireEvent("refreshGame")
        end,

        refreshGame = function(element)
            if (not dmhub.inGame) or dmhub.isLobbyGame then
                return
            end
            local newCache = {}
            local children = {}
            for _, userid in ipairs(dmhub.users or {}) do
                local info = dmhub.GetSessionInfo(userid)
                if info ~= nil and not info.dm then
                    local owned = CharacterIdsOwnedBy(userid)
                    local mainid = info.primaryCharacter or owned[1]
                    local extraCount = 0
                    for _, cid in ipairs(owned) do
                        if cid ~= mainid then
                            extraCount = extraCount + 1
                        end
                    end
                    --icons are cached per (user, main character, count):
                    --any of those changing rebuilds that one icon.
                    local key = string.format("%s|%s|%d", userid, tostring(mainid), extraCount)
                    local icon = element.data.cache[key]
                    if icon == nil or not icon.valid then
                        icon = CreatePlayerStatusIcon(userid, mainid, extraCount)
                    end
                    newCache[key] = icon
                    children[#children + 1] = icon
                    icon:FireEventTree("updateStatus", info)
                end
            end
            element.data.cache = newCache
            element.children = children
        end,
    }

    --The COLLAPSING wrapper is separate from the thinking root, and the
    --root must never collapse itself: a collapsed panel's think does not
    --run, so the first collapse would be permanent -- nothing would be
    --left alive to un-collapse it. (Hit live 2026-08-08: the panel
    --collapsed during a reload window where inGame read false and never
    --came back. Same trap the icon rail documents; same fix.)
    local contentPanel = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        halign = "left",
        valign = "center",
        m_wifiIcon,
        playersRow,
    }

    local resultPanel
    resultPanel = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        halign = "left",
        valign = "center",
        rmargin = 12,
        bgimage = true,
        bgcolor = "clear",

        --the panel is the door to the Heroes panel, which is not a
        --dockable panel any more: it lives in a temporary popout hung
        --beneath this panel, dismissed like any popup (click away).
        --Player icons eat their own clicks to ping. Same popup rig as
        --the audio indicator's popover.
        click = function(element)
            if element.popup ~= nil then
                element.popup = nil
                return
            end
            local factory = rawget(_G, "CreateHeroesPanelPopoutContent")
            if factory == nil then
                return
            end
            element.popupsInheritStyles = true
            element.popup = gui.Panel{
                --heroesPopout: content inside reaches this wrapper by
                --class to dismiss the popout (the local-game promote
                --flow closes it before showing its modal).
                classes = {"bordered", "bg", "heroesPopout"},
                width = 440,
                height = 480,
                pad = 8,
                borderBox = true,
                halign = "left",
                valign = "bottom",
                closePopout = function()
                    if element ~= nil and element.valid then
                        element.popup = nil
                    end
                end,
                factory(),
            }
        end,

        multimonitor = {"showstatusbar"},
        monitor = function(element)
            contentPanel:SetClass("collapsed", not g_showStatusBarSetting:Get())
        end,
        thinkTime = 0.5,
        think = function(element)
            if (not dmhub.inGame) or dmhub.isLobbyGame then
                contentPanel:SetClass("collapsed", true)
                return
            end
            contentPanel:SetClass("collapsed", not g_showStatusBarSetting:Get())

            --nil = engine build without the bridge; treat as connected.
            local connected = dmhub.gameServerConnected ~= false
            local syncing = dmhub.undoState.undoPending or dmhub.pendingWriteCount > 0

            if not connected then
                m_wifiIcon.data.frame = 0
                m_wifiIcon.bgimage = "phosphor/wifi-x-duotone.png"
                m_wifiIcon.selfStyle.bgcolor = "#e04545"
                element.thinkTime = 0.5
            elseif syncing then
                --quick alternation through the bar heights while writes
                --are in flight.
                local frame = (m_wifiIcon.data.frame % #g_syncFrames) + 1
                m_wifiIcon.data.frame = frame
                m_wifiIcon.bgimage = g_syncFrames[frame]
                m_wifiIcon.selfStyle.bgcolor = "#c8c8c8"
                element.thinkTime = 0.12
            else
                m_wifiIcon.data.frame = 0
                m_wifiIcon.bgimage = "phosphor/wifi-high-fill.png"
                m_wifiIcon.selfStyle.bgcolor = "#c8c8c8"
                element.thinkTime = 0.5
            end
        end,

        contentPanel,
    }
    return resultPanel
end

----------------------------------------------------------------------
-- Initiative / game-mode status ("Exploration", "Round 3", ...).
--
-- The panel itself is built by the initiative bar (MCDMInitiativeBar) --
-- its click menu and the combat-settings gear beside it need that file's
-- helpers -- but it is DISPLAYED here, in the status bar left of the map
-- name, instead of floating over the top of the map. The title bar is
-- created once at Lua load and outlives any single GameHud, so each new
-- hud re-mounts a fresh panel through MountInitiativeStatusPanel().
----------------------------------------------------------------------

local g_initiativeStatusContainer = nil

--rawget: reading a never-assigned global raises in this runtime, so the usual
--`X = X or {}` idiom cannot be used here.
if rawget(_G, "CodexTitleBar") == nil then
    CodexTitleBar = {}
end

local function CreateInitiativeStatusHost()
    g_initiativeStatusContainer = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        rmargin = 16,
        multimonitor = {"showstatusbar"},
        create = function(element)
            element:SetClass("collapsed", not g_showStatusBarSetting:Get())
        end,
        monitor = function(element)
            element:SetClass("collapsed", not g_showStatusBarSetting:Get())
        end,
    }
    return g_initiativeStatusContainer
end

--Called by GameHud.CreateInitiativeBar. Pass nil to clear.
function CodexTitleBar.MountInitiativeStatusPanel(panel)
    if g_initiativeStatusContainer == nil or (not g_initiativeStatusContainer.valid) then
        return
    end

    if panel == nil then
        g_initiativeStatusContainer.children = {}
    else
        g_initiativeStatusContainer.children = {panel}
    end
end

----------------------------------------------------------------------
-- Hovered-tile terrain indicator.
--
-- A small square chip in the status bar, just left of the map name,
-- styled like the Map Markup panel's zone swatches: solid fill for
-- plain ground / open air, diagonal stripes for special terrain (the
-- same stripe treatment the map overlay itself uses for zones). One
-- characteristic is shown at a time -- the most important one covering
-- the tile under the mouse. Everything lives on one table to keep the
-- file's local count down.
----------------------------------------------------------------------

local g_tileIndicator = {
    gradients = {},

    --The priority ladder: lower tier = more important. Physical hazards
    --(no floor at all, then damage) outrank movement modifiers (water,
    --difficult), which outrank vision zones (darkness, sunlight,
    --concealing), which outrank informational surfaces. "zone" is any
    --other environmental-keyword zone, striped in the keyword's own
    --color; "ground" is the no-features fallback.
    kinds = {
        void       = { tier = 1,  name = "Open Air (no floor)", color = "#000000", stripes = false },
        damaging   = { tier = 2,  name = "Damaging Terrain",    color = "#cc3333", stripes = true },
        water      = { tier = 3,  name = "Water",               color = "#3373d9", stripes = true },
        difficult  = { tier = 4,  name = "Difficult Terrain",   color = "#8c5926", stripes = true },
        darkness   = { tier = 5,  name = "Darkness",            color = "#4b2a6b", stripes = true },
        sunlight   = { tier = 6,  name = "Sunlight",            color = "#e2c433", stripes = true },
        concealing = { tier = 7,  name = "Concealing",          color = "#4d594d", stripes = true },
        climbable  = { tier = 8,  name = "Climbable",           color = "#2e8b8b", stripes = true },
        stairs     = { tier = 9,  name = "Stairs",              color = "#8a8a8a", stripes = true },
        zone       = { tier = 10, name = "Zone",                color = "#888888", stripes = true },
        ground     = { tier = 11, name = "Ground",              color = "#3a8f3a", stripes = false },
    },
}

--The same diagonal-stripe recipe as the Map Markup zone swatches
--(m_zoneStripes.Gradient): a linear gradient one stripe period long
--along a diagonal vector, hard flip between the color and its
--transparent twin, repeating. The gradient MULTIPLIES the panel's own
--color, so striped chips set bgcolor white. color must be "#rrggbb".
--angle defaults to 45 degrees; the overlay menu passes each zone type's
--own map angle so its swatch stripes the way the map does.
function g_tileIndicator.StripeGradient(color, angle)
    angle = angle or (math.pi * 0.25)
    local key = color .. "/" .. tostring(angle)
    local cached = g_tileIndicator.gradients[key]
    if cached ~= nil then
        return cached
    end

    local period = 0.28
    local result = gui.Gradient{
        type = "linear",
        point_a = {x = 0.5, y = 0.5},
        point_b = {
            x = 0.5 + math.cos(angle) * period,
            y = 0.5 + math.sin(angle) * period,
        },
        ["repeat"] = true,
        stops = {
            {position = 0.00, color = color .. "ff"},
            {position = 0.48, color = color .. "ff"},
            {position = 0.52, color = color .. "00"},
            {position = 1.00, color = color .. "00"},
        },
    }
    g_tileIndicator.gradients[key] = result
    return result
end

--Vertical band test mirroring EnvironmentalKeyword.lua's per-square Loc
--symbols: nil height = unlimited; otherwise a creature standing at
--refAltitude must fall inside [altitude, altitude + height].
function g_tileIndicator.BandCovers(instance, refAltitude)
    local height = instance:GetHeight()
    if height == nil then
        return true
    end
    local base = instance:GetAltitude() or 0
    return refAltitude >= base and refAltitude <= base + height
end

--An environmental keyword's display color, normalized to "#rrggbb" or
--nil. display.bgcolor may be a Color USERDATA (the compendium color
--picker's storage idiom) whose .tostring property is the real hex
--string; white means "unset". Same normalization as the Map Markup
--panel's KeywordColor.
function g_tileIndicator.KeywordColor(kw)
    local color = nil
    pcall(function()
        local display = kw:try_get("display")
        if display ~= nil then
            color = display.bgcolor
        end
    end)

    if type(color) == "userdata" then
        local ok, str = pcall(function() return color.tostring end)
        if ok and type(str) == "string" then
            color = str
        else
            color = nil
        end
    end
    if type(color) == "string" and string.len(color) == 9 then
        color = string.sub(color, 1, 7)
    end
    if type(color) ~= "string" or string.len(color) ~= 7
        or string.sub(color, 1, 1) ~= "#" or string.lower(color) == "#ffffff" then
        return nil
    end
    return color
end

--Classifies the tile under the mouse. Returns a .kinds entry plus
--optional color/name overrides (used by the generic "zone" kind, which
--stripes in the covering keyword's own color and names itself after it).
--The hovered loc is derived the same way the engine's dmhub.status
--string derives it: mouse world point snapped to the tile grid, on the
--currently selected floor; rules == nil is exactly the status string's
--"(void)" -- no terrain here, a creature would fall to the floor below.
function g_tileIndicator.Classify()
    local kinds = g_tileIndicator.kinds

    local pt = dmhub.GetMouseWorldPoint()
    if pt == nil then
        return kinds.void, nil, nil
    end

    local loc = core.Loc{
        x = math.floor(pt.x + 0.5),
        y = math.floor(pt.y + 0.5),
        floorIndex = game.currentFloorIndex,
    }

    --Non-DM viewers only get information about tiles currently inside their
    --vision; an unseen tile reads as void (solid black) - no information.
    --IsLocInVision returns true outright for DM vision, and on engine builds
    --without the bridge the pcall leaves visible true (no filtering).
    local visible = true
    pcall(function()
        visible = dmhub.IsLocInVision(loc)
    end)
    if visible == false then
        return kinds.void, nil, "Not visible"
    end

    local rules = dmhub.GetTileRulesAtLoc(loc)
    if rules == nil or rules.hole then
        return kinds.void, nil, nil
    end

    local best = nil
    local bestColor = nil
    local bestName = nil
    local function Consider(kind, colorOverride, nameOverride)
        if kind ~= nil and (best == nil or kind.tier < best.tier) then
            best = kind
            bestColor = colorOverride
            bestName = nameOverride
        end
    end

    --Merged tile rules cover both tile art flags and apply-to-all auras
    --(markup zones), so water/difficult/concealing zones land here too.
    if rules.water then
        Consider(kinds.water)
    end
    if rules.difficultTerrain then
        Consider(kinds.difficult)
    end
    if rules.concealment then
        Consider(kinds.concealing)
    end
    if rules.stairs then
        Consider(kinds.stairs)
    end
    if rules.climbHeight > 0 then
        Consider(kinds.climbable)
    end

    --Auras covering the square: damage-on-move / hazard-roll auras, the
    --named light-level keywords, climbable zones, and any other
    --environmental-keyword zone. Same footprint + ground-altitude band
    --test as EnvironmentalKeyword.lua's per-square symbols.
    local auras = game.GetAurasAtLoc(loc.xyfloorOnly)
    if auras ~= nil then
        local refAltitude = loc.withGroundAltitude.altitude
        local keywordsTable = dmhub.GetTable("environmentalKeywords") or {}
        for _,aura in ipairs(auras) do
            local instance = aura.auraInstance
            --squares on an aura's adjacent extension (includeAdjacent) are
            --next to the area, not in it: no chip for them.
            if instance ~= nil and not EnvironmentalKeyword.AuraLocOnlyAdjacent(aura, loc.xyfloorOnly) then
                --tolerate aura instances that do not implement the full
                --AuraInstance interface: skip them, not error the tick.
                pcall(function()
                    if not g_tileIndicator.BandCovers(instance, refAltitude) then
                        return
                    end

                    local auraDef = instance:try_get("aura")
                    if auraDef == nil then
                        return
                    end

                    --"does damage in some way": per-tile movement damage
                    --or an on-enter hazard power roll.
                    if instance:GetDamageInfo() ~= nil
                        or auraDef:try_get("powerRollEnabled", false) then
                        Consider(kinds.damaging)
                    end

                    if instance:GetClimbable() ~= nil then
                        Consider(kinds.climbable)
                    end

                    local keywordid = auraDef:try_get("environmentalKeywordId")
                    if keywordid ~= nil then
                        local kw = keywordsTable[keywordid]
                        if kw ~= nil then
                            local name = string.lower(kw.name or "")
                            if name == "darkness" or name == "dark" then
                                Consider(kinds.darkness)
                            elseif name == "sunlight" or name == "daylight" then
                                Consider(kinds.sunlight)
                            else
                                Consider(kinds.zone,
                                    g_tileIndicator.KeywordColor(kw),
                                    kw.name)
                            end
                        end
                    end
                end)
            end
        end
    end

    if best == nil then
        best = kinds.ground
    end
    return best, bestColor, bestName
end

--------------------------------------------------------------------
-- The map overlay menu, opened by clicking the chip. One checkbox
-- per overlay layer (walls / elevation / terrain features) plus one
-- per zone type present on the map, with Show All / Hide All. All
-- state lives in per-user settings, so it works for players and
-- directors alike; players are only offered player-visible zone
-- types (MapMarkup.GetZoneTypesOnMap filters for them).
--------------------------------------------------------------------

--The shown-zone-types preference (';'-joined keyword ids) as a set. Zone
--types default hidden, so this records opt-INs, same as the built-ins below.
function g_tileIndicator.ShownZoneSet()
    local result = {}
    local str = tostring(dmhub.GetSettingValue("mapoverlay:shownzones") or "")
    for id in string.gmatch(str, "[^;]+") do
        result[id] = true
    end
    return result
end

function g_tileIndicator.WriteShownZoneSet(set)
    local ids = {}
    for id,_ in pairs(set) do
        ids[#ids+1] = id
    end
    table.sort(ids)
    dmhub.SetSettingValue("mapoverlay:shownzones", table.concat(ids, ";"))
end

--The four built-in terrain rule types, styled to match the engine's
--overlay stripes exactly (TileHeightOverlay ZoneWater/Difficult/
--Concealment/Climbable colors and alternating angles).
g_tileIndicator.BUILTINS = {
    { id = "water",       name = "Water",       color = "#3373d9", angle = math.pi * 0.25 },
    { id = "difficult",   name = "Difficult",   color = "#8c5926", angle = math.pi * 0.75 },
    { id = "concealment", name = "Concealment", color = "#333333", angle = math.pi * 0.25 },
    { id = "climbable",   name = "Climbable",   color = "#66cc66", angle = math.pi * 0.75 },
}

--The shown-built-ins preference (';'-joined ids from BUILTINS) as a set.
--Built-ins default hidden, so this records opt-INs (same shape as
--ShownZoneSet; separate settings because the id spaces differ).
function g_tileIndicator.ShownBuiltinSet()
    local result = {}
    local str = tostring(dmhub.GetSettingValue("mapoverlay:shownbuiltins") or "")
    for id in string.gmatch(str, "[^;]+") do
        result[id] = true
    end
    return result
end

function g_tileIndicator.WriteShownBuiltinSet(set)
    local ids = {}
    for id,_ in pairs(set) do
        ids[#ids+1] = id
    end
    table.sort(ids)
    dmhub.SetSettingValue("mapoverlay:shownbuiltins", table.concat(ids, ";"))
end

--Built-in terrain rule types present on the map's TERRAIN TILES themselves.
--The bridge excludes every aura contribution, so a rule that only exists
--because a defined zone grants it does not produce an entry - the zone
--type's own row is its control. {} on engine builds without the bridge.
function g_tileIndicator.BuiltinTypesOnMap()
    local flags = nil
    pcall(function()
        flags = dmhub.GetBuiltinTerrainTypesOnMap()
    end)
    if flags == nil then
        return {}
    end

    local result = {}
    for _,entry in ipairs(g_tileIndicator.BUILTINS) do
        local present = false
        if entry.id == "water" then
            present = flags.water
        elseif entry.id == "difficult" then
            present = flags.difficultTerrain
        elseif entry.id == "concealment" then
            present = flags.concealment
        else
            present = flags.climbable
        end
        if present then
            result[#result+1] = entry
        end
    end
    return result
end

--Zone types present on the current map, or {} when the Map Markup
--module is absent (lobby) or predates the API.
function g_tileIndicator.ZoneTypesOnMap()
    local markup = rawget(_G, "MapMarkup")
    if markup == nil or markup.GetZoneTypesOnMap == nil then
        return {}
    end
    local ok, types = pcall(markup.GetZoneTypesOnMap)
    if ok and type(types) == "table" then
        return types
    end
    return {}
end

--Markup holes present on the current map ({color, angleRadians}), or nil.
--Holes get an opt-IN row like the built-ins (reserved id "hole" in
--mapoverlay:shownbuiltins, which the engine ignores): the actual cut in the
--map always shows, the stripes are an inspection aid that defaults off
--outside the Map Markup panel. DM-only by construction (the markup side
--returns nil for players).
function g_tileIndicator.HoleTypeOnMap()
    local markup = rawget(_G, "MapMarkup")
    if markup == nil or markup.GetHoleTypeOnMap == nil then
        return nil
    end
    local ok, info = pcall(markup.GetHoleTypeOnMap)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

function g_tileIndicator.CreateOverlayMenu()
    local checkStyle = {
        width = "100%",
        height = 24,
        fontSize = 14,
        hpad = 0,
    }

    --a checkbox bound to a boolean mapoverlay:* setting; monitor keeps
    --it in sync with the Settings screen and the Show/Hide All buttons.
    local function SettingCheck(settingid, text, tooltip)
        return gui.Check{
            value = dmhub.GetSettingValue(settingid) and true or false,
            text = text,
            halign = "left",
            hover = gui.Tooltip(tooltip),
            style = checkStyle,
            monitor = settingid,
            events = {
                monitor = function(element)
                    element.value = dmhub.GetSettingValue(settingid) and true or false
                end,
                change = function(element)
                    dmhub.SetSettingValue(settingid, element.value)
                end,
            },
        }
    end

    --one row per zone type: a stripe swatch in the type's map color and
    --angle, and a checkbox driving its entry in mapoverlay:shownzones
    --(zone types default hidden; checked = opted in).
    local function ZoneRow(zoneType)
        local gradient = nil
        local bg = zoneType.color or "#888888"
        if type(zoneType.color) == "string" and string.len(zoneType.color) == 7 then
            gradient = g_tileIndicator.StripeGradient(zoneType.color, zoneType.angleRadians)
            bg = "white"
        end

        return gui.Panel{
            width = "100%",
            height = 24,
            flow = "horizontal",

            gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimage = true,
                bgcolor = bg,
                gradient = gradient,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Check{
                value = g_tileIndicator.ShownZoneSet()[zoneType.keywordid] ~= nil,
                text = zoneType.name,
                halign = "left",
                lmargin = 6,
                style = checkStyle,
                monitor = "mapoverlay:shownzones",
                events = {
                    monitor = function(element)
                        element.value = g_tileIndicator.ShownZoneSet()[zoneType.keywordid] ~= nil
                    end,
                    change = function(element)
                        local set = g_tileIndicator.ShownZoneSet()
                        if element.value then
                            set[zoneType.keywordid] = true
                        else
                            set[zoneType.keywordid] = nil
                        end
                        g_tileIndicator.WriteShownZoneSet(set)
                    end,
                },
            },
        }
    end

    --one row per built-in terrain rule type present on the map's terrain
    --tiles: same swatch+check shape as a zone row, driving the type's entry
    --in mapoverlay:shownbuiltins (built-ins default hidden).
    local function BuiltinRow(builtin)
        return gui.Panel{
            width = "100%",
            height = 24,
            flow = "horizontal",

            gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimage = true,
                bgcolor = "white",
                gradient = g_tileIndicator.StripeGradient(builtin.color, builtin.angle),
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Check{
                value = g_tileIndicator.ShownBuiltinSet()[builtin.id] ~= nil,
                text = builtin.name,
                halign = "left",
                lmargin = 6,
                style = checkStyle,
                monitor = "mapoverlay:shownbuiltins",
                events = {
                    monitor = function(element)
                        element.value = g_tileIndicator.ShownBuiltinSet()[builtin.id] ~= nil
                    end,
                    change = function(element)
                        local set = g_tileIndicator.ShownBuiltinSet()
                        if element.value then
                            set[builtin.id] = true
                        else
                            set[builtin.id] = nil
                        end
                        g_tileIndicator.WriteShownBuiltinSet(set)
                    end,
                },
            },
        }
    end

    local zoneTypes = g_tileIndicator.ZoneTypesOnMap()
    local builtinTypes = g_tileIndicator.BuiltinTypesOnMap()
    local holeType = g_tileIndicator.HoleTypeOnMap()

    local children = {}

    children[#children+1] = gui.Label{
        classes = {"bold"},
        text = "Map Overlay",
        width = "100%",
        height = "auto",
        bmargin = 4,
    }

    --Show All / Hide All: every layer plus every listed zone type at once.
    children[#children+1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        bmargin = 4,

        gui.Button{
            text = "Show All",
            width = "48%",
            height = 22,
            fontSize = 13,
            halign = "left",
            click = function(element)
                dmhub.SetSettingValue("mapoverlay:walls", true)
                dmhub.SetSettingValue("mapoverlay:elevation", true)
                local zset = g_tileIndicator.ShownZoneSet()
                for _,zoneType in ipairs(g_tileIndicator.ZoneTypesOnMap()) do
                    zset[zoneType.keywordid] = true
                end
                g_tileIndicator.WriteShownZoneSet(zset)
                local set = g_tileIndicator.ShownBuiltinSet()
                for _,builtin in ipairs(g_tileIndicator.BuiltinTypesOnMap()) do
                    set[builtin.id] = true
                end
                if g_tileIndicator.HoleTypeOnMap() ~= nil then
                    set["hole"] = true
                end
                g_tileIndicator.WriteShownBuiltinSet(set)
            end,
        },

        gui.Button{
            text = "Hide All",
            width = "48%",
            height = 22,
            fontSize = 13,
            halign = "right",
            click = function(element)
                dmhub.SetSettingValue("mapoverlay:walls", false)
                dmhub.SetSettingValue("mapoverlay:elevation", false)
                dmhub.SetSettingValue("mapoverlay:shownbuiltins", "")
                dmhub.SetSettingValue("mapoverlay:shownzones", "")
            end,
        },
    }

    children[#children+1] = SettingCheck("mapoverlay:walls", "Walls",
        "Wall lines colored by the cover they grant: black for full cover, greys for partial.")
    children[#children+1] = SettingCheck("mapoverlay:elevation", "Elevation",
        "Contour lines where tile elevation changes, with a height number in each region.")

    --The terrain list: the defined zone types on the map, then the built-in
    --terrain rule types the map's TILES carry on their own (a rule only
    --derived from a defined zone gets no row - the zone's row is its
    --control).
    if #zoneTypes > 0 or #builtinTypes > 0 or holeType ~= nil then
        children[#children+1] = gui.Label{
            classes = {"fgMuted", "sizeXs"},
            text = "Terrain on This Map",
            width = "100%",
            height = "auto",
            vmargin = 4,
        }
        for _,zoneType in ipairs(zoneTypes) do
            children[#children+1] = ZoneRow(zoneType)
        end
        for _,builtin in ipairs(builtinTypes) do
            children[#children+1] = BuiltinRow(builtin)
        end
        --markup holes: same opt-in storage as the built-ins. The row only
        --toggles the STRIPES over the holes; the actual cut always shows.
        if holeType ~= nil then
            children[#children+1] = BuiltinRow({
                id = "hole",
                name = "Hole",
                color = holeType.color,
                angle = holeType.angleRadians,
            })
        end
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        children = children,
    }
end

--Opens (or dismisses) the map overlay menu beneath `element` -- the status
--cluster plate the chip and the map name share. Same popup rig as the
--player-status cluster's Heroes popout: click toggles, click-away dismisses.
--Does nothing outside a real game, which is also when the plate stops
--advertising itself as clickable.
function g_tileIndicator.ShowOverlayMenu(element)
    if element.popup ~= nil then
        element.popup = nil
        return
    end
    if (not dmhub.inGame) or dmhub.isLobbyGame then
        return
    end
    element.popupsInheritStyles = true
    element.popup = gui.Panel{
        classes = {"bordered", "bg"},
        width = 280,
        height = "auto",
        pad = 12,
        borderBox = true,
        halign = "left",
        valign = "bottom",
        flow = "vertical",
        g_tileIndicator.CreateOverlayMenu(),
    }
end

--The chip itself. Paints fully clear (no fill, no border) outside a
--game rather than collapsing: a collapsed panel's think does not run,
--so a self-collapse would be permanent (same trap the player-status
--cluster documents above). It is interactable = false: the click that
--opens the map overlay menu, and the tooltip, both live on the status
--cluster plate it shares with the map name label (see CreateStatusBar),
--so hovering either half lights the whole plate.
function g_tileIndicator.CreatePanel()
    local function Clear(element)
        element.data.key = nil
        element.data.name = nil
        element.selfStyle.gradient = nil
        element.selfStyle.bgcolor = "clear"
        element.selfStyle.borderWidth = 0
    end

    return gui.Panel{
        width = 18,
        height = 18,
        valign = "center",
        rmargin = 8,
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 0,
        borderColor = "@border",
        interactable = false,

        data = { key = nil, name = nil },

        multimonitor = {"showstatusbar"},
        monitor = function(element)
            element.thinkTime = cond(g_showStatusBarSetting:Get(), 0.1, nil)
            Clear(element)
        end,
        thinkTime = cond(g_showStatusBarSetting:Get(), 0.1, nil),
        think = function(element)
            if (not dmhub.inGame) or dmhub.isLobbyGame then
                if element.data.key ~= nil then
                    Clear(element)
                end
                return
            end

            local kind, colorOverride, nameOverride = g_tileIndicator.Classify()
            local color = colorOverride or kind.color
            local key = (nameOverride or kind.name) .. "|" .. color
            if key == element.data.key then
                return
            end

            element.data.key = key
            element.data.name = nameOverride or kind.name
            element.selfStyle.borderWidth = 1
            if kind.stripes then
                element.selfStyle.bgcolor = "white"
                element.selfStyle.gradient = g_tileIndicator.StripeGradient(color)
            else
                element.selfStyle.gradient = nil
                element.selfStyle.bgcolor = color
            end
        end,
    }
end

local function CreateStatusBar()
    local resultPanel

    --The hovered-tile chip and the map-name label are two halves of one
    --control: both describe the current map, and clicking either opens the
    --map overlay menu. They share a "menuItem" plate (see m_mapCluster
    --below), which only advertises itself while that menu can actually open.
    local m_tileChip
    local m_mapNameLabel
    local m_mapCluster

    local function MapClusterAvailable()
        return g_showStatusBarSetting:Get() and dmhub.inGame and (not dmhub.isLobbyGame)
    end

    local function RefreshMapClusterAffordance()
        if m_mapCluster ~= nil and m_mapCluster.valid then
            m_mapCluster:SetClass("menuItem", MapClusterAvailable())
        end
    end

    -- Hovered-tile terrain chip: a zone-swatch-style square
    -- characterizing the tile under the mouse (see g_tileIndicator).
    m_tileChip = g_tileIndicator.CreatePanel()

    -- Map name + engine status. Long map descriptions used to eat the bar,
    -- so the box is capped (narrower than the old 420) and the text
    -- ellipsizes rather than wrapping or shrinking away to nothing;
    -- hovering shows the untruncated string (on the cluster's tooltip).
    -- On a narrow bar the fit pass (BarFitApply) narrows this width further,
    -- so BAR_FIT_MAPNAME_FULL must stay in step with the width below.
    m_mapNameLabel = gui.Label{
        --menuLabel is what flips the text to @bg when the plate fills on
        --hover. It carries a 16px font for the main menu strip; this cluster
        --runs at the default 14, so match the neighbours explicitly.
        classes = {"menuLabel"},
        fontSize = 14,
        minFontSize = 10,
        width = 380,
        height = "100%",
        hmargin = 0,
        textAlignment = "left",
        textWrap = false,
        textOverflow = "ellipsis",
        interactable = false,
        text = "",
        data = { fullText = "" },
        multimonitor = {"showstatusbar"},
        monitor = function(element)
            element.thinkTime = cond(g_showStatusBarSetting:Get(), 0.1, nil)
            element.data.fullText = ""
            element.text = ""
            RefreshMapClusterAffordance()
        end,
        thinkTime = cond(g_showStatusBarSetting:Get(), 0.1, nil),
        think = function(element)
            RefreshMapClusterAffordance()
            if (not dmhub.inGame) or dmhub.isLobbyGame then
                element.data.fullText = ""
                element.text = ""
                return
            end
            local text = string.format("%s %s", game.currentMap.description, dmhub.status)
            element.data.fullText = text
            element.text = text
        end,
    }

    --The shared plate. Structure follows the title bar's other menu items
    --(and the initiative readout): the fill and the click live on the
    --wrapper, both children are interactable = false so the hover lands
    --here rather than on a half. hpad is inline rather than left to the
    --menuItem style so the cluster does not shift sideways on the frames
    --where the class is dropped.
    m_mapCluster = gui.Panel{
        classes = {cond(MapClusterAvailable(), "menuItem")},
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        hpad = 8,

        linger = function(element)
            local lines = {}
            local mapText = m_mapNameLabel.data.fullText
            if mapText ~= nil and mapText ~= "" then
                lines[#lines+1] = mapText
            end
            local tileName = m_tileChip.data.name
            if tileName ~= nil then
                lines[#lines+1] = string.format("Tile under cursor: %s", tileName)
            end
            if #lines == 0 then
                return
            end
            lines[#lines+1] = "Click to choose which map overlays are shown."
            gui.Tooltip(table.concat(lines, "\n"))(element)
        end,

        click = function(element)
            g_tileIndicator.ShowOverlayMenu(element)
        end,

        m_tileChip,
        m_mapNameLabel,
    }

    --First to go on a narrow bar: the label narrows (stage 2 of the fit
    --pass) and then the whole cluster collapses -- name first, terrain chip
    --after -- before anything else is dropped, so the search box outlives
    --the map info entirely.
    BarFitRegister("mapName", m_mapNameLabel)
    BarFitRegister("mapChip", m_tileChip)

    local m_initiativeHost = CreateInitiativeStatusHost()
    BarFitRegister("initiative", m_initiativeHost)

    -- While a CommandBuilder session is active, a floating recorder dialog
    -- shows the steps; this zero-size host is just its mount point.
    local m_commandBuilderHost = CommandBuilder.CreateDialogHost()

    resultPanel = gui.Panel{
        flow = "horizontal",
        height = "100%",
        -- Was a fixed 600. The initiative/game-mode readout now shares this
        -- cluster, so the bar sizes to whatever its labels actually need
        -- instead of overrunning a hardcoded budget.
        width = "auto",
        halign = "right",

        rightClick = function(element)
            local menuItems = {
                {
                    text = "Show Status Bar",
                    check = g_showStatusBarSetting:Get(),
                    click = function()
                        g_showStatusBarSetting:Set(not g_showStatusBarSetting:Get())
                        element.popup = nil
                    end,
                },
            }

            element.popup = gui.ContextMenu{
                entries = menuItems,
            }
        end,

        -- Dev-only note: when this game is loading its assets from a local
        -- directory (the "local assets" developer feature -- a custom data
        -- directory that replaces the game's cloud assets), flag it here so it
        -- is obvious at a glance that this is a dev game. Hovering shows the
        -- source directory; clicking opens Settings -> Editing, where the
        -- "Local Assets (Developer)" section configures the directories (and
        -- can reveal them in the OS file browser). Empty (zero-width) for every
        -- normal game. LocalAssetsStatus is read-and-compared-to-nil so an
        -- older engine build (before the bridge exists) simply shows nothing.
        BarFitRegister("devGame", gui.Label{
            minFontSize = 10,
            bold = true,
            color = "#f0a030",
            width = "auto",
            height = "100%",
            valign = "center",
            rmargin = 10,
            text = "",
            data = { dir = nil },
            linger = function(element)
                local dir = element.data.dir
                if dir == nil or dir == "" then
                    return
                end
                gui.Tooltip(string.format("Dev game: assets are loading from a local directory --\n%s\n\nClick to open the Local Assets settings.", dir))(element)
            end,
            click = function(element)
                local dir = element.data.dir
                if dir ~= nil and dir ~= "" then
                    dmhub.ShowPlayerSettings{tab = "Editing"}
                end
            end,
            multimonitor = {"showstatusbar"},
            monitor = function(element)
                element.thinkTime = cond(g_showStatusBarSetting:Get(), 1, nil)
                element.data.dir = nil
                element.text = ""
            end,
            thinkTime = cond(g_showStatusBarSetting:Get(), 1, nil),
            think = function(element)
                if (not dmhub.inGame) or dmhub.isLobbyGame or dmhub.LocalAssetsStatus == nil then
                    element.data.dir = nil
                    element.text = ""
                    return
                end
                local status = dmhub.LocalAssetsStatus()
                if status ~= nil and status.active and status.directory ~= nil and status.directory ~= "" then
                    element.data.dir = status.directory
                    element.text = "Dev Game"
                else
                    element.data.dir = nil
                    element.text = ""
                end
            end,
        }),

        BarFitRegister("connectivity", CreateConnectivityPanel()),

        -- Host for the initiative/game-mode panel; empty (and therefore
        -- zero-width) until a game hud mounts one. Collapsing on the
        -- showstatusbar preference is done here rather than in the mounted
        -- panel so the initiative bar does not have to know about this
        -- setting.
        m_initiativeHost,

        -- Hovered-tile terrain chip + map name/engine status, sharing one
        -- clickable plate that opens the map overlay menu.
        m_mapCluster,

        -- Zero-size mount point that opens the command-builder recorder
        -- dialog when a session begins.
        m_commandBuilderHost,
    }

    return resultPanel
end

-- Label a placed token by kind so its result row reads Hero / NPC / Monster
-- (the leading icon is the token's own portrait, but the text label still
-- splits it the way the unplaced providers do).
-- These rows are all PLACED tokens, so the kind carries an "(on Map)" suffix --
-- it tells a deployed creature apart from the same kind of UNPLACED one (the
-- partyCharacters provider, plain "Hero"/"NPC") when both can share the "In
-- this Campaign" bucket.
local function TokenKindLabel(token)
    local props = token.properties
    if props ~= nil then
        local ok, isMonster = pcall(function() return props:IsMonster() end)
        if ok and isMonster then
            return "Monster (on Map)"
        end
    end
    if token.playerControlled then
        return "Hero (on Map)"
    end
    return "NPC (on Map)"
end

-- Global-search provider: tokens on the current map(s). Full provider (bespoke
-- data, custom activate): clicking selects the token and centres the camera on
-- it. Players only see tokens not hidden from them. Each result carries the
-- live token so the row can render its portrait as the leading icon - a visual
-- cue that this creature is placed on the map (vs the flat Character/Bestiary
-- icon shown for unplaced heroes/monsters).
Search.RegisterProvider{
    id = "tokens",
    bucket = "ingame",
    enumerate = function(needle)
        -- Director-only: token search leads to selection/placement, which are
        -- director actions. A player searching their own party members was
        -- offered a placement prompt they cannot fulfil, so campaign token
        -- search is gated to the DM (matching the unplaced-character provider).
        if (not dmhub.inGame) or (not dmhub.isDM) then
            return {}
        end
        local results = {}
        for _,token in ipairs(dmhub.allTokens) do
            local name = token.name
            if type(name) == "string" and Search.MatchesText(name, needle) then
                local capturedId = token.id
                results[#results+1] = {
                    name = name,
                    score = Search.Score(name, needle),
                    typeLabel = TokenKindLabel(token),
                    token = token,
                    actionLabel = "Center on token",
                    -- Lets the "On this map" context group dedupe this token out
                    -- of the bucket while it is pinned there (same key the
                    -- map-view provider stamps).
                    dedupKey = "token:" .. capturedId,
                    activate = function()
                        dmhub.SelectToken(capturedId)
                        dmhub.CenterOnToken(capturedId)
                    end,
                }
            end
        end
        return results
    end,
}

-- The search box used to be exactly as wide as the right dock below it
-- (364 * dockscale). It is now deliberately narrower by this fraction so the
-- status labels sharing the bar (map name, initiative mode) get the space back;
-- the box still tracks the dock scale, it just sits inset from the dock edge.
local g_searchWidthFraction = 0.9

--assigns the forward declaration up by the fit controller, which needs the
--box's natural width to know how much narrowing it has left to give
function SearchBoxWidth()
    return math.floor(364 * g_searchWidthFraction * DockablePanel.EffectiveDockScale())
end

local function CreateSearchBar()
    local resultPanel

    --the seamless-popup dressing (the connector strip below the bar and
    --the bar's squared-off bottom corners) must track whether a POPUP is
    --actually up, not focus -- a focused empty bar with no recents has
    --no popup and must stay a plain closed pill (Venla 2026-08-21).
    --Called from the paths that assign/clear the popup, from the popups'
    --own destroy (so an engine outside-click dismissal retracts the
    --dressing IMMEDIATELY -- the think tick alone left it flickering for
    --up to 0.2s), plus the think tick as a catch-all.
    local function SyncPopupOpenState()
        if resultPanel == nil or not resultPanel.valid then
            return
        end
        local hasPopup = resultPanel.popup ~= nil
        if hasPopup ~= resultPanel.data.hadPopup then
            resultPanel.data.hadPopup = hasPopup
            resultPanel:SetClass("searchPopupOpen", hasPopup)
            resultPanel:FireEventTree("searchPopupChanged", hasPopup)
        end
    end

    --destroy handler shared by the popups: when a popup is torn down and
    --nothing replaced it, retract the dressing right away. The
    --popup-still-set guard keeps per-keystroke popup REPLACEMENT from
    --blinking the connector (the old popup's destroy can fire after the
    --new one is already assigned).
    local function OnSearchPopupDestroyed()
        if resultPanel ~= nil and resultPanel.valid and resultPanel.popup == nil then
            SyncPopupOpenState()
        end
    end

    -- Per-doc heading search lives in JournalPDFViewer.lua (SearchPDFHeadings,
    -- shared with the "In this document" context provider). This wrapper maps
    -- its {page, heading, score} matches onto result rows: the HEADING is the
    -- row's main line, "doc, page N" the subhead. The 0.1 dampening of every
    -- match after the first is global-ranking glue (one PDF must not flood the
    -- flat list); it stays here rather than in the shared search.
    local searchPDF = function(docid, doc, search)
        local matches = SearchPDFHeadings(doc, search)
        if type(matches) ~= "table" then
            return "pending"
        end

        local rows = {}
        for i,m in ipairs(matches) do
            local capturedPage = m.page
            rows[#rows+1] = {
                name = m.heading,
                subLabel = string.format("%s, page %d", doc.description, m.page),
                score = cond(i == 1, m.score, m.score * 0.1),
                actionLabel = string.format("Go to page %d", m.page),
                click = function()
                    OpenPDFDocument(doc, capturedPage)
                end,
            }
        end
        return rows
    end

    local scoreMatch = function(text, search)
        text = string.lower(text)
        search = string.lower(search)

        if text == search then
            return 100
        elseif string.starts_with(text, search) then
            return 75
        elseif string.find(text, search, 1, true) ~= nil then
            return 50
        end

        return 0
    end

    -- The 4 intent buckets the flat result list is grouped into. Stable ids
    -- come from Search.Buckets; the labels + order live here (the search UI
    -- owns the display strings).
    local SEARCH_BUCKETS = {
        { id = "compendium", label = "Compendium" },
        { id = "rulebooks", label = "Rulebooks" },
        { id = "ingame", label = "In this Campaign" },
        { id = "apptools", label = "App & tools" },
    }
    -- Per-bucket render budget: how many rows show before "See all N", and the
    -- most we keep in memory per bucket (the rest deep-link to the surface).
    local SEARCH_BUCKET_SHOWN = 5
    local SEARCH_BUCKET_STORE = 50

    -- Map a CustomDocument.SearchLinks result type onto a bucket.
    local function BucketForLinkType(linkType)
        if linkType == "PDF Document" or linkType == "PDF Fragment" then
            return "rulebooks"
        end
        if linkType == "Document" or linkType == "Map" then
            return "ingame"
        end
        -- Markdown-table prefixes (item:, title:, ...) and prefix suggestions
        -- are compendium content.
        return "compendium"
    end

    -- Session-local list of recently activated results, newest first. Shown
    -- as a "Recent" group when the search box is focused while empty - an
    -- empty-state that gets a returning user back to what they were working
    -- with. In-memory only (activation closures cannot be persisted).
    local m_recentResults = {}
    local RECENT_STORE = 20

    local function RecordRecentResult(result)
        local key = (result.name or result.text or "") .. "\1" .. (result.typeLabel or "")
        for i,r in ipairs(m_recentResults) do
            if ((r.name or r.text or "") .. "\1" .. (r.typeLabel or "")) == key then
                table.remove(m_recentResults, i)
                break
            end
        end
        table.insert(m_recentResults, 1, result)
        while #m_recentResults > RECENT_STORE do
            table.remove(m_recentResults)
        end
    end

    -- Per-type leading icons for the result rows. App icons (Icon_App_*) are
    -- full-colour, so they render untinted (bgcolor "white" in the style) -
    -- an INLINE bgcolor of a theme token is NOT resolved by the theme engine,
    -- so a tinted icon would paint invisible.
    local SEARCH_ICON_MONSTER    = "icons/standard/Icon_App_Bestiary.png"
    local SEARCH_ICON_CHARACTER  = "icons/standard/Icon_App_Character.png"
    local SEARCH_ICON_MAP        = "icons/standard/Icon_App_MapSettings.png"
    local SEARCH_ICON_JOURNAL    = "icons/standard/Icon_App_Journal.png"
    local SEARCH_ICON_ENCOUNTER  = "icons/standard/Icon_App_EncounterCreator.png"
    local SEARCH_ICON_SETTINGS   = "panels/hud/gear.png"
    -- The Compendium has no Icon_App_* glyph; reuse the icon that prepends the
    -- Compendium link in the Codex title-bar menu (its LaunchablePanel icon).
    local SEARCH_ICON_COMPENDIUM = "game-icons/bookmarklet.png"

    local SEARCH_ICON_BY_TYPELABEL = {
        ["monster"]   = SEARCH_ICON_MONSTER,
        ["companion"] = SEARCH_ICON_MONSTER,
        ["hero"]      = SEARCH_ICON_CHARACTER,
        ["npc"]       = SEARCH_ICON_CHARACTER,
        ["map"]       = SEARCH_ICON_MAP,
        ["encounter"] = SEARCH_ICON_ENCOUNTER,
    }

    -- Map a result to its leading icon. Providers may set result.icon to
    -- override; otherwise map from typeLabel (most specific) then bucket.
    local function iconForResult(result)
        if result.icon ~= nil then
            return result.icon
        end

        local typeLabel = result.typeLabel
        if typeLabel ~= nil then
            local t = string.lower(typeLabel)
            local byType = SEARCH_ICON_BY_TYPELABEL[t]
            if byType ~= nil then
                return byType
            end
            -- Document / PDF Document / PDF Fragment -> journal.
            if t == "document" or string.find(t, "pdf", 1, true) ~= nil then
                return SEARCH_ICON_JOURNAL
            end
        end

        local bucket = result.bucket
        if bucket == "rulebooks" then
            return SEARCH_ICON_JOURNAL
        elseif bucket == "apptools" then
            return SEARCH_ICON_SETTINGS
        elseif bucket == "ingame" then
            -- tokens / maps / journals / encounters are caught above by
            -- typeLabel; the remainder (creature features) are capabilities
            -- that live on a creature.
            return SEARCH_ICON_CHARACTER
        end

        -- Compendium content (conditions, classes, ...) and anything else.
        return SEARCH_ICON_COMPENDIUM
    end

    -- The ordered action list for a result, primary first. Three sources, in
    -- priority order: an explicit result.actions list (the modern form), a
    -- legacy result.menuItems() function (its first entry is the primary), or a
    -- single synthesised action from result.click/activate labelled by
    -- result.actionLabel (default "Open"). The first action always mirrors what
    -- pressing the row does, so the primary chip and the row press agree.
    local function BuildResultActions(result)
        if type(result.actions) == "table" and #result.actions > 0 then
            return result.actions
        end
        if result.menuItems ~= nil then
            local ok, items = pcall(result.menuItems)
            if ok and type(items) == "table" and #items > 0 then
                return items
            end
        end
        local primaryClick = result.click or result.activate
        if primaryClick ~= nil then
            return { { text = result.actionLabel or "Open", click = primaryClick } }
        end
        return {}
    end

    -- One result row: a leading per-type icon, then a highlighted name
    -- (provider results) or preformatted text (legacy handlers), plus an
    -- optional muted type/source label on the right. Beneath the name sit an
    -- optional context line (e.g. "Signature Ability", "Level 1 Horde", or a
    -- PDF's "doc, page N") and a row of action chips that spell out what each
    -- click does (primary first, then secondaries spaced apart). Pressing the
    -- row runs the primary action; pressing a chip runs that action. Both
    -- dismiss the popup. `opts.noActions` suppresses the chip row (used by the
    -- pinned context group, which stays deliberately clean).
    local function CreateResultRow(result, needle, opts)
        opts = opts or {}
        -- A placed token renders its own portrait (Hero/retainer/NPC/monster
        -- already on the map); everything else gets a flat per-type glyph. If
        -- the token went invalid since enumeration, fall back to the glyph.
        local iconPanel
        if result.token ~= nil and result.token.valid then
            iconPanel = gui.CreateTokenImage(result.token, {
                width = 20,
                height = 20,
                halign = "left",
                valign = "center",
                rmargin = 8,
                interactable = false,
            })
        elseif result.bubbleIcon ~= nil then
            -- Map note: render the bubble's own numbered pin (dark disc, light
            -- border) as the leading icon, matching the on-map marker and the
            -- documents panel's pin so a note reads as a note at a glance.
            iconPanel = gui.Label{
                classes = {"searchResultBubble"},
                text = result.bubbleIcon,
                interactable = false,
            }
        else
            iconPanel = gui.Panel{
                classes = {"searchResultIcon"},
                bgimage = iconForResult(result),
                interactable = false,
            }
        end

        local nameLabel = gui.Label{
            classes = {"searchResultName"},
            text = result.name ~= nil and Search.Highlight(result.name, needle) or (result.text or ""),
        }

        -- Run a result action: record it as recent, dismiss the popup, clear
        -- the query (deselect no longer does this while the pointer is on the
        -- popup), then invoke the action. Shared by the row press and the chips
        -- so they dismiss identically.
        local function activate(clickFn)
            RecordRecentResult(result)
            -- clearing the text fires edit("") - don't let that pop the
            -- recents group right after navigating away.
            resultPanel.data.skipRecentsOnce = true
            resultPanel.popup = nil
            resultPanel.text = ""
            if clickFn ~= nil then
                clickFn()
            end
        end

        -- Name + optional context line + optional action chips, stacked. The
        -- context line (result.subLabel) stays on its OWN line rather than
        -- merged onto the right-hand type chip: Draw Steel villain/signature
        -- ability names are full sentences, so merging would clip the majority
        -- of monster-ability rows at the search box width.
        local blockChildren = { nameLabel }

        if result.subLabel ~= nil then
            blockChildren[#blockChildren+1] = gui.Label{
                classes = {"searchResultSub"},
                text = result.subLabel,
            }
        end

        -- Secondary action buttons are collected here and placed in the RIGHT
        -- column (under the type chip); the primary hint stays under the name.
        local secondaryButtons = {}
        if not opts.noActions then
            local actions = BuildResultActions(result)
            if #actions > 0 then
                -- Primary action: a muted hint ("> Open in Compendium") under
                -- the name spelling out what pressing the ROW does. Descriptive,
                -- not a button -- the row press performs it -- so single-action
                -- rows get just this line and no button at all.
                blockChildren[#blockChildren+1] = gui.Panel{
                    classes = {"searchActionLine"},
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    gui.Panel{ classes = {"searchHintArrow"} },
                    gui.Label{ classes = {"searchHintText"}, text = actions[1].text },
                }

                -- Secondary actions: small outlined buttons. swallowPress stops
                -- the press from also reaching the row (a press hits a panel AND
                -- all its parents by default), so a button runs ONLY its own
                -- action, never the row's primary as well.
                for i=2,#actions do
                    local capturedClick = actions[i].click
                    secondaryButtons[#secondaryButtons+1] = gui.Label{
                        classes = {"searchResultChip"},
                        text = actions[i].text,
                        swallowPress = true,
                        press = function(element)
                            activate(capturedClick)
                        end,
                    }
                end
            end
        end

        local nameBlock
        if #blockChildren == 1 then
            nameBlock = nameLabel
        else
            nameBlock = gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                children = blockChildren,
            }
        end

        -- RIGHT column: the muted type chip on top, then any secondary action
        -- buttons stacked beneath it (e.g. a monster ability's "Place on Map"
        -- sits under the monster name). Omitted when there is neither.
        local rightBlock = nil
        local rightChildren = {}
        if result.typeLabel ~= nil then
            rightChildren[#rightChildren+1] = gui.Label{
                classes = {"searchResultType"},
                text = result.typeLabel,
            }
        end
        for _,btn in ipairs(secondaryButtons) do
            rightChildren[#rightChildren+1] = btn
        end
        if #rightChildren > 0 then
            rightBlock = gui.Panel{
                classes = {"searchResultRight"},
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "top",
                children = rightChildren,
            }
        end

        local rowChildren = { iconPanel, nameBlock }
        if rightBlock ~= nil then
            rowChildren[#rowChildren+1] = rightBlock
        end

        return gui.Panel{
            classes = {"searchResultRow"},
            flow = "horizontal",
            press = function()
                activate(result.click or result.activate)
            end,
            children = rowChildren,
        }
    end

    -- Build the grouped results popup. `expanded` is a per-bucket flag set;
    -- pressing "See all" flips a bucket open and rebuilds in place. Only the
    -- shown rows are rendered (the lazy render budget).
    --
    -- Keyboard navigation: the search input forwards uparrow / downarrow /
    -- activateSelection (Enter) here via FireEventTree (same idiom as the
    -- GoblinScript autocomplete popup). A cursor walks every navigable entry
    -- (result rows AND "See all" labels, so expansion is keyboard-reachable);
    -- the selected entry carries the "searchfocus" class. Enter with no
    -- selection activates the first result.
    local function CreateGroupedPopup(grouped, needle, expanded, searchingLabel, context)
        local children = {}
        local navRows = {}

        local function AppendGroup(label, list, expandKey, noActions)
            children[#children+1] = gui.Label{
                classes = {"searchGroupHeading"},
                text = string.format("<b>%s</b> (%d)", label, #list),
            }
            local shown = expanded[expandKey] and #list or math.min(#list, SEARCH_BUCKET_SHOWN)
            for i=1,shown do
                local row = CreateResultRow(list[i], needle, {noActions = noActions})
                children[#children+1] = row
                navRows[#navRows+1] = {panel = row, event = "press"}
            end
            if (not expanded[expandKey]) and #list > SEARCH_BUCKET_SHOWN then
                local seeAll = gui.Label{
                    classes = {"searchSeeAll"},
                    text = string.format("See all %d", #list),
                    -- The historical "expands then disappears" bug was NOT
                    -- this handler: the input's deselect fired on the real
                    -- mousedown, cleared the text, and the resulting
                    -- edit("") dismissed the rebuilt popup ~editlag later.
                    -- deselect now keeps the query when the pointer is on
                    -- the popup, so the expansion survives.
                    click = function()
                        expanded[expandKey] = true
                        resultPanel.popup = CreateGroupedPopup(grouped, needle, expanded, searchingLabel, context)
                    end,
                }
                children[#children+1] = seeAll
                navRows[#navRows+1] = {panel = seeAll, event = "click"}
            end
        end

        -- Context group ("In this document" / "On this map" / ...): pinned
        -- ABOVE the intent buckets, additive - never replaces global reach.
        if context ~= nil and #context.results > 0 then
            -- Context rows render their action hint like every other row. The
            -- noActions hook remains for any future group that wants to opt out.
            AppendGroup(context.label, context.results, "context", context.noActions)
        end

        for _,bucket in ipairs(SEARCH_BUCKETS) do
            local list = grouped[bucket.id]
            if list ~= nil and #list > 0 then
                AppendGroup(bucket.label, list, bucket.id)
            end
        end

        if searchingLabel ~= nil then
            children[#children+1] = gui.Label{
                classes = {"searchSeeAll"},
                text = "Searching for more results...",
            }
        end

        local m_cursor = 0
        local popupPanel

        local function MoveCursor(delta)
            if #navRows == 0 then
                return
            end
            local newCursor = m_cursor + delta
            if newCursor < 1 then
                newCursor = #navRows
            elseif newCursor > #navRows then
                newCursor = 1
            end
            local old = navRows[m_cursor]
            if old ~= nil and old.panel.valid then
                old.panel:SetClass("searchfocus", false)
            end
            m_cursor = newCursor
            local row = navRows[m_cursor]
            if row.panel.valid then
                row.panel:SetClass("searchfocus", true)
            end
            -- Keep the selection in view (vscrollPosition: 1 = top, 0 =
            -- bottom). Approximate by cursor fraction; exact row offsets are
            -- not exposed, and the popup only scrolls once a bucket expands.
            if #navRows > 1 then
                popupPanel.vscrollPosition = 1 - (m_cursor - 1) / (#navRows - 1)
            end
        end

        --the filled, scrolling body. Its searchResultsPanel fill/corners
        --live HERE, not on the popup root: the root's first 4px are a
        --transparent notch (see below).
        popupPanel = gui.Panel{
            classes = {"searchResultsPanel"},
            flow = "vertical",
            width = "100%",
            height = "auto",
            vscroll = true,
            children = children,

            uparrow = function(element)
                MoveCursor(-1)
            end,
            downarrow = function(element)
                MoveCursor(1)
            end,
            activateSelection = function(element)
                local row = navRows[math.max(m_cursor, 1)]
                if row ~= nil and row.panel.valid then
                    row.panel:FireEvent(row.event)
                end
            end,
        }

        return gui.Panel{
            destroy = OnSearchPopupDestroyed,
            --top-center pivot: the engine places a popup ONCE, against
            --its rect at placement time, and an auto-height popup that
            --finishes layout afterwards grows around its pivot -- with
            --the default center pivot a SHORT popup's top edge crept up
            --over the search bar and clipped its text (Venla
            --2026-08-21). Anchored at the top, growth extends downward
            --only, so the placed top edge (flush under the bar) holds
            --for every result count.
            pivot = {x = 0.5, y = 1},
            flow = "vertical",
            -- Exactly the search box's width -- the popup must never be
            -- wider or narrower than the box above it (Venla 2026-08-21;
            -- this replaces the old max(368, dock width) rule, trading the
            -- no-wrap floor for alignment). Rebuilt fresh per search, so a
            -- value computed at construction stays current.
            width = SearchBoxWidth(),
            height = "auto",
            halign = "center",
            valign = "bottom",
            --transparent notch: the engine PLACES the popup's top edge
            --~6px INSIDE the bar (measured 2026-08-21; the shared fill
            --hid the overlap, but the opaque fill painted over glyph
            --descenders -- g, y, p -- which reach the bar's last rows).
            --10px of transparency puts the fill's top just below the
            --bar's box; the bar itself and its connector strip show
            --through with the same fill, so the join still reads
            --seamless.
            gui.Panel{ width = 1, height = 10 },
            popupPanel,
        }
    end

    -- Empty-state: focusing the search box with no query shows the recently
    -- activated results as a "Recent" group - same popup machinery, so it
    -- gets the cap-5/"See all" idiom and keyboard navigation for free.
    local function ShowRecentResults()
        if #m_recentResults == 0 then
            return false
        end
        resultPanel.data.searchSignature = nil
        resultPanel.data.searchStatus = nil
        resultPanel.data.isNoResultsPopup = false
        resultPanel.popupsInheritStyles = true
        resultPanel.popup = CreateGroupedPopup({}, "", {}, nil, {label = "Recent", results = m_recentResults})
        return true
    end

    local executeSearch = function(text)
        if TopBar.HasCustomSearch() then
            return TopBar.ExecuteCustomSearch(text)
        end

        local status = true --search is good and complete.
        text = string.trim(string.lower(text))
        --Broadcast the live query so echo surfaces (the tac-panel Features
        --glow) can respond in place. Published on every keystroke including
        --the empty/clear case so the glow turns off when the query is cleared.
        Search.SetGlobalQuery(text)
        if text == "" then
            local skip = resultPanel.data.skipRecentsOnce
            resultPanel.data.skipRecentsOnce = false
            if (not skip) and resultPanel.hasInputFocus and ShowRecentResults() then
                return status
            end
            resultPanel.popup = nil
            return status
        end

        local menuItems = {}
        resultPanel.parent:FireEventTree("collectMenuItems", menuItems)

        local results = {}
        for _,item in ipairs(menuItems) do
            if string.find(string.lower(item.text), text, 1, true) ~= nil then
                local itemCopy = DeepCopy(item)
                itemCopy.score = scoreMatch(itemCopy.text, text)
                itemCopy.bucket = "apptools"
                itemCopy.actionLabel = "Open"
                results[#results+1] = itemCopy
            end
        end

        --search keybindings.
        for key,bind in pairs(Keybinds.GetBindings()) do
            if string.find(string.lower(bind.name), text, 1, true) ~= nil then
                local itemCopy = DeepCopy(bind)
                itemCopy.score = scoreMatch(itemCopy.name, text)
                itemCopy.text = string.format("<b>%s</b> (Shortcut)", itemCopy.name)
                itemCopy.bucket = "apptools"
                itemCopy.actionLabel = "Edit in Settings"
                itemCopy.click = function()
                    dmhub.ShowPlayerSettings{search = itemCopy.name}
                end
                results[#results+1] = itemCopy
            end
        end

        --search settings.
        for key,settingInfo in pairs(Settings) do
            if settingInfo.section ~= nil and string.find(string.lower(settingInfo.description), text, 1, true) ~= nil and (dmhub.isDM or (settingInfo.classes or {})[1] ~= "dmonly") then
                local itemCopy = DeepCopy(settingInfo)
                itemCopy.score = scoreMatch(itemCopy.description, text)
                itemCopy.text = string.format("<b>%s</b> (Setting)", itemCopy.description)
                itemCopy.bucket = "apptools"
                itemCopy.actionLabel = "Open in Settings"
                itemCopy.click = function()
                    dmhub.ShowPlayerSettings{search = itemCopy.description}
                end

                results[#results+1] = itemCopy
            end
        end

        local links = CustomDocument.SearchLinks(text)
        for _,link in ipairs(links) do
            -- Compendium content (markdown-table entries like items/titles, and
            -- monsters) is owned by the dedicated compendium-content / monsters
            -- search providers, which give richer actions ("Open in Compendium",
            -- "Place on Map" / "Edit Monster") and DM-gating. SearchLinks emits
            -- these only for the document link picker; skip them here so the
            -- title-bar search shows no dead duplicate rows (and does not leak
            -- monster names to players). Prefix suggestions ("Search items...")
            -- and rulebook / journal / map links are kept.
            if BucketForLinkType(link.type) == "compendium" and not link.isPrefix then
                goto continue
            end
            link.score = scoreMatch(link.name, text)
            -- Render name + a muted type-label chip (like tokens), instead of
            -- baking "(Map)"/"(Document)" into the text -- so maps/journals tag
            -- consistently with the rest of the grouped results.
            link.typeLabel = link.type
            link.bucket = BucketForLinkType(link.type)
            -- Primary-action copy by link kind (rulebooks, journals, maps); a
            -- prefix suggestion ("Search items...") narrows the query, and any
            -- other markdown-table entry opens its content.
            if link.isPrefix then
                link.actionLabel = "Search this category"
            elseif link.type == "PDF Document" or link.type == "PDF Fragment" then
                link.actionLabel = "Open rulebook"
            elseif link.type == "Document" then
                link.actionLabel = "Open journal"
            elseif link.type == "Map" then
                link.actionLabel = "Go to map"
            else
                link.actionLabel = "Open"
            end
            -- A map note's backing document also surfaces here as a "Document".
            -- Key it by title so that, when the note is pinned in "On this map",
            -- this journal twin is deduped out of the bucket. (When the map
            -- context is suppressed the key is unowned, so the document still
            -- shows -- the note stays reachable.)
            if link.type == "Document" then
                link.dedupKey = "mapdoc:" .. string.lower(link.name or "")
            end
            link.click = function()
                CustomDocument.OpenContent(CustomDocument.ResolveLink(link.link))
            end
            results[#results+1] = link
            ::continue::
        end

        for k,doc in pairs(assets.pdfDocumentsTable) do
            if not doc.hidden then

                local pdfresults = searchPDF(k, doc, text)
                if type(pdfresults) == "table" then
                    for _,r in ipairs(pdfresults) do
                        r.bucket = "rulebooks"
                        results[#results+1] = r
                    end
                else
                    status = false --search should be repeated.
                end
            end
        end

        -- Registered global-search providers (compendium content, tokens, ...).
        -- They share the chunk-1 matcher and carry their own bucket + activate.
        local needle = Search.Normalize(text)
        for _,r in ipairs(Search.CollectProviderResults(needle)) do
            results[#results+1] = r
        end

        -- Context-sensitive search: when an artifact (PDF viewer, ...) is
        -- open it contributes its own scoped group, pinned above the
        -- buckets. A pending context (async per-doc search) repeats the
        -- search the same way the global PDF path does.
        local context = Search.CollectContextResults(needle)
        if context ~= nil and context.pending then
            status = false
        end

        -- Option A dedupe: an item already shown in the active context group
        -- (a placed token, a map note) should not ALSO repeat in the intent
        -- buckets below. Providers stamp a dedupKey on comparable results; the
        -- context group is the home, the bucket is the fallback. When no
        -- context is active ownedKeys is empty, so nothing is suppressed and
        -- global reach is preserved.
        local ownedKeys = {}
        if context ~= nil then
            for _,r in ipairs(context.results) do
                if r.dedupKey ~= nil then
                    ownedKeys[r.dedupKey] = true
                end
            end
        end

        -- Group the flat results into the intent buckets, ranked by score, and
        -- cap each bucket to the render/store budget.
        table.stable_sort(results, function(a,b) return (a.score or 0) > (b.score or 0) end)

        local grouped = {}
        for _,r in ipairs(results) do
            if r.dedupKey == nil or not ownedKeys[r.dedupKey] then
                local b = r.bucket or "apptools"
                local list = grouped[b]
                if list == nil then
                    list = {}
                    grouped[b] = list
                end
                if #list < SEARCH_BUCKET_STORE then
                    list[#list+1] = r
                end
            end
        end

        if #results == 0 and (context == nil or #context.results == 0) then
            resultPanel.data.searchSignature = nil
            resultPanel.data.searchStatus = nil
            if resultPanel.popup == nil or not resultPanel.data.isNoResultsPopup then
                resultPanel.data.isNoResultsPopup = true
                --same chrome and width as the grouped results popup, so the
                --empty state reads as the same surface and sits below the
                --box like the results do (the old bare black label sat on
                --top of the input itself). popupsInheritStyles is what
                --delivers the searchResultsPanel/searchEmptyState rules to
                --the re-rooted popup -- without it the label renders with
                --default label styling, huge and unframed.
                resultPanel.popupsInheritStyles = true
                resultPanel.popup = gui.Panel{
                    destroy = OnSearchPopupDestroyed,
                    --top-center pivot + 10px descender notch, same
                    --structure as the grouped popup (see
                    --CreateGroupedPopup for the full rationale).
                    pivot = {x = 0.5, y = 1},
                    flow = "vertical",
                    width = SearchBoxWidth(),
                    height = "auto",
                    halign = "center",
                    valign = "bottom",
                    gui.Panel{ width = 1, height = 10 },
                    gui.Panel{
                        classes = {"searchResultsPanel"},
                        flow = "vertical",
                        width = "100%",
                        height = "auto",
                        gui.Label{
                            classes = {"searchEmptyState"},
                            text = "",
                            settext = function(element, newtext)
                                element.text = newtext
                            end,
                        },
                    },
                }
            end

            resultPanel.popup:FireEventTree("settext", cond(status, "No Search Results", "Searching..."))
            if status then
                track("search_titlebar", {
                    query = text,
                    hasResults = false,
                    resultCount = 0,
                    deduplicate = 0.5,
                    dailyLimit = 50,
                })
            end
            return status
        end

        -- Flicker guard: re-fire of the same query (e.g. the async PDF
        -- repeat-search) rebuilds nothing if the visible result set is
        -- unchanged. The signature is the ordered names across the context
        -- group + all buckets, so an expanded "See all" state survives an
        -- identical repeat.
        local sigParts = {}
        if context ~= nil then
            for _,r in ipairs(context.results) do
                sigParts[#sigParts+1] = r.name or r.text or ""
            end
        end
        for _,bucket in ipairs(SEARCH_BUCKETS) do
            local list = grouped[bucket.id]
            if list ~= nil then
                for _,r in ipairs(list) do
                    sigParts[#sigParts+1] = r.name or r.text or ""
                end
            end
        end
        local signature = table.concat(sigParts, "\1")

        if resultPanel.popup ~= nil
            and resultPanel.data.searchStatus == status
            and resultPanel.data.searchSignature == signature then
            --no need to invalidate menu.
            return status
        end

        resultPanel.data.searchStatus = status
        resultPanel.data.searchSignature = signature
        resultPanel.data.isNoResultsPopup = false

        resultPanel.popupsInheritStyles = true
        resultPanel.popup = CreateGroupedPopup(grouped, needle, {}, cond(status, nil, true), context)

        if status then
            track("search_titlebar", {
                query = text,
                hasResults = #results > 0,
                resultCount = #results,
                deduplicate = 0.5,
                dailyLimit = 50,
            })
        end

        return status
    end

    resultPanel = gui.SearchInput{
        bgimage = true,
        -- Tracks the right dock's rendered width (364 * dockscale, default 1.0)
        -- so the box lines up with the dock below it at any scale (HB1), less
        -- the 10% narrowing (g_searchWidthFraction) that buys back bar space for
        -- the status labels to its left. Kept live by the think handler below.
        -- borderBox is load-bearing: gui.SearchInput ships hpad=24 WITHOUT
        -- borderBox, so the rendered box would otherwise be 48px wider than the
        -- declared width and overhang the dock (James field report, 2026-07-03).
        borderBox = true,
        width = SearchBoxWidth(),
        height = 20,
        halign = "right",
        --breathing room against the window edge: without it the pill's
        --border (and the popup centered under it) sat on the last pixel
        --of the screen (Venla 2026-08-21).
        rmargin = 8,
        valign = "center",
        --no pad override: the canonical searchInput padding (room for
        --the magnifier) comes from the component/style (Control Zoo
        --pass 2026-08-20; the old pad=2 left the text under the icon).
        popupPositioning = "panel",
        placeholderText = cond(dmhub.GetCommandBinding("find"), string.format("Search (%s)...", dmhub.GetCommandBinding("find") or ""), "Search..."),
        inputEvents = { "find" },
        -- Trailing debounce: coalesce keystrokes so a fast typist does not run
        -- the provider sweep (all ~574 monsters etc.) on every key. Kept at
        -- 0.1s -- 0.2s felt laggy; the typed text always updates instantly and
        -- only the result computation waits this long.
        editlag = 0.1,
        edit = function(element)
            local status = executeSearch(element.text)
            if not status then
                element:FireEvent("repeatSearch")
            end
            SyncPopupOpenState()
        end,
        change = function(element)
            --element:FireEvent("edit")
        end,
        find = function(element)
            element.hasFocus = true
            if string.trim(element.text or "") == "" then
                ShowRecentResults()
            end
            SyncPopupOpenState()
        end,
        -- Click-to-focus on the empty box shows the recents. The engine has
        -- no input-gained-focus event (deselect has no symmetric select), so
        -- watch for the rising edge of hasInputFocus on a light think.
        thinkTime = 0.2,
        think = function(element)
            -- The box's WIDTH is not set here: the bar's fit pass owns it
            -- (BarFitApply), because on a narrow window the box is the first
            -- thing asked to give space back. The fit pass re-reads
            -- SearchBoxWidth() every tick, so a mid-session change to the
            -- dock-scale slider (HB1) is still followed without a reload.
            local focused = element.hasInputFocus
            if focused and (not element.data.hadInputFocus)
                and element.popup == nil
                and string.trim(element.text or "") == "" then
                ShowRecentResults()
            end
            element.data.hadInputFocus = focused
            SyncPopupOpenState()
        end,
        -- Keyboard navigation of the results popup: arrows move the selection,
        -- Enter activates it (or the first result when nothing is selected).
        -- Same forward-to-popup idiom as the GoblinScript autocomplete.
        uparrow = function(element)
            if element.popup ~= nil then
                element.popup:FireEventTree("uparrow")
            end
        end,
        downarrow = function(element)
            if element.popup ~= nil then
                element.popup:FireEventTree("downarrow")
            end
        end,
        submit = function(element)
            if element.popup ~= nil then
                element.popup:FireEventTree("activateSelection")
            end
        end,
        deselect = function(element)
            -- A real click inside the results popup also blurs this input
            -- (deselect fires on the mousedown). Clearing the text here makes
            -- the engine fire edit("") after editlag, which runs
            -- executeSearch("") and dismisses the popup right after the row's
            -- click lands -- "See all" would briefly expand then vanish.
            -- Only treat the blur as a dismissal when the pointer is OUTSIDE
            -- the popup (mousePoint is normalized 0..1 inside a panel). The
            -- engine already closes the popup itself on outside clicks.
            local popup = element.popup
            if popup ~= nil and popup.valid then
                local mp = popup.mousePoint
                if mp ~= nil and mp.x >= 0 and mp.x <= 1 and mp.y >= 0 and mp.y <= 1 then
                    return
                end
            end
            element.text = ""
        end,
        repeatSearch = function(element)
            if element.data.repeatingSearch then
                return
            end

            element.data.repeatingSearch = true
            element:ScheduleEvent("dorepeatSearch", 0.2)
        end,
        dorepeatSearch = function(element)
            element.data.repeatingSearch = false
            element:FireEvent("edit")
        end,
    }

    --seamless popup connector (Venla 2026-08-21): while a results popup
    --is up (searchPopupChanged, from SyncPopupOpenState), this strip
    --extends the field's fill down over the gap the engine leaves above
    --the popup (popup roots ignore y offsets, so the FIELD carries the
    --bridge). Same fill as field and popup, so the three read as one
    --stretched shape. AddChild, NOT a positional child in the
    --constructor -- a positional option would overwrite
    --gui.SearchInput's own magnifier child. Floating children anchor to
    --the CONTENT box (inside hpad 24), hence the +48 to reach the full
    --pill width.
    resultPanel:AddChild(gui.Panel{
        classes = {"searchPopupBridge", "hidden"},
        floating = true,
        interactable = false,
        halign = "center",
        valign = "bottom",
        width = "100%+48",
        height = 14,
        --17, not 14: panel children render ABOVE the input's own text,
        --and at 14 the strip's top row overlapped the glyph descender
        --zone and clipped g/y/p tails (live-debugged 2026-08-21 -- the
        --popup fill was innocent). 3px lower clears the text; the
        --strip still overlaps the popup fill below, so the join stays
        --seamless.
        y = 17,
        searchPopupChanged = function(element, hasPopup)
            element:SetClass("hidden", not hasPopup)
        end,
    })

    --first in line to give space back on a narrow bar
    BarFitRegister("search", resultPanel)

    return resultPanel
end

--H-BAR: global audio indicator glyph, left of the search box. Three states
--(muted / playing / idle) polled on a light think; a press opens a compact
--mixer popover built from Audio.lua's exported fader factories so the top
--bar, dock, and Studio Mixer share ONE fader implementation. If Audio.lua's
--export is not loaded (should not happen given load order, but this is a
--cross-module read) the glyph simply does not open a popup.
local function CreateAudioIndicator()
    local resultPanel

    --Safe read of the "localmuted" setting. It is registered by a game mod
    --(AudioMain.lua), so at the title screen and during the mid-Lua-reload
    --teardown window the id does not exist -- GetSettingValue on a missing id
    --both logs "Could not find setting" and throws a native NRE (seen once
    --per boot, 2026-07-03). HasSetting is the non-logging existence probe.
    local function IsLocalMuted()
        return dmhub.HasSetting("localmuted") and dmhub.GetSettingValue("localmuted") == true
    end

    local function ComputeState()
        --The engine audio system (and the GameController backing audio.muted)
        --is not initialized during the title screen / early game load, where
        --this think already runs. MERELY TOUCHING audio.muted or
        --audio.currentlyPlaying there raises a native NullReference that the
        --engine logs/reports even when Lua pcall catches it (player-window
        --error dialog, 2026-07-03) -- so gate on the Audio.lua export, which
        --only exists once the game's audio mods are loaded, and do not call
        --into audio.* at all before then. The pcall stays as a second line of
        --defense for reload teardown windows.
        if rawget(_G, "g_drawSteelAudioBar") == nil then
            return "idle"
        end
        local ok, state = pcall(function()
            if audio.muted or IsLocalMuted() then
                return "muted"
            end
            for _,_ in pairs(audio.currentlyPlaying) do
                return "playing"
            end
            return "idle"
        end)
        if not ok then
            return "idle"
        end
        return state
    end

    --Muted from this client's perspective: its own local mute, or the game-wide
    --mute. Used for glyph/toggle display state; which layer the TOGGLE writes is
    --role-branched at the press site.
    local function IsClientMuted()
        return audio.muted or IsLocalMuted()
    end

    local function BuildPopover()
        local bar = rawget(_G, "g_drawSteelAudioBar")
        if bar == nil then
            return nil
        end

        -- Now-playing line is a snapshot at open time -- this is a transient
        -- popover (same accepted pattern as the Studio's bindings popover),
        -- not a live-refreshing panel.
        local nowPlayingName = bar.PrimaryPlayingName()

        --Muted-cause line (DJ delegation decision 4): the popover top tier is
        --now PERSONAL for every role, so when the glyph shows muted the cause
        --may be either layer - name it. Snapshot popover, but both mute
        --toggles below refresh this line on press so it never contradicts an
        --action taken inside the popover itself.
        local mutedCauseLine
        local function RefreshMutedCause()
            if audio.muted then
                mutedCauseLine.text = "The table is muted for everyone."
                mutedCauseLine:SetClass("collapsed", false)
            elseif IsLocalMuted() then
                mutedCauseLine.text = "Your personal mute is on."
                mutedCauseLine:SetClass("collapsed", false)
            else
                mutedCauseLine:SetClass("collapsed", true)
            end
        end
        mutedCauseLine = gui.Label{
            classes = {"sizeXxs", "fgMuted", "collapsed"},
            width = "100%",
            height = "auto",
            textWrap = true,
        }

        --Personal tier (DJ delegation decision 4): EVERY role, including the
        --Director, gets the personal master + personal mute here - reflex
        --control keeps reflex semantics for every human. The game-wide mute
        --moved into the broadcast block below as a labeled control (PR-note
        --obligation: this repurposes the DM's trained mute-glyph behavior).
        local muteToggle = gui.Panel{
            bgcolor = "white",
            width = 16,
            height = 16,
            valign = "center",
            hmargin = 4,
            press = function(element)
                dmhub.SetSettingValue("localmuted", not IsLocalMuted())
                -- The bar glyph self-heals on its 0.5s think, but this copy
                -- lives in a snapshot popover -- swap it now or it reads
                -- stale until the popover is reopened.
                element:SetClass("muted", IsClientMuted())
                RefreshMutedCause()
            end,
            linger = function(element)
                gui.Tooltip("Mute (only you)")(element)
            end,
            styles = {
                { bgimage = "ui-icons/ph-speaker-high-fill.png" },
                { selectors = {"muted"}, bgimage = "ui-icons/ph-speaker-slash-fill.png" },
                { selectors = {"hover"}, brightness = 2 },
            },
            create = function(element)
                element:SetClass("muted", IsClientMuted())
            end,
        }
        muteToggle:SetClass("muted", IsClientMuted())

        -- Mute rides the RIGHT end of the Master row (its own row read as
        -- orphaned chrome -- James field report, 2026-07-03). Master keeps the
        -- left slot so its slider stays column-aligned with the Levels sliders
        -- below; MakeFaderRow hardcodes width 100%, so the fader row is
        -- narrowed post-construction to make room for the toggle.
        --Personal per-user master for every role - the same "volume" setting
        --as Settings->Audio's Master Volume. (The game-wide master lives in
        --the dock/Studio/Settings; it is no longer in this popover.)
        local masterSlider
        if bar.MakePersonalFader == nil then
            --Fallback for a stale export during partial reloads.
            masterSlider = bar.MakeMasterFader()
        else
            masterSlider = bar.MakePersonalFader("volume")
        end
        local masterFaderRow = bar.MakeFaderRow("Master", masterSlider, false)
        masterFaderRow.selfStyle.width = "100%-26"
        local masterRow = gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 22,
            valign = "center",
            masterFaderRow,
            muteToggle,
        }

        local children = {
            -- "Now Playing" header (bold, pinned white -- the popover bg is
            -- known-dark in every scheme) with the track title on its own
            -- line beneath, mirroring the Studio's Now Playing card.
            gui.Label{
                classes = {"sizeXs", "bold"},
                color = "#ffffff",
                width = "100%",
                height = "auto",
                text = "Now Playing",
            },
            gui.Label{
                classes = {"sizeXs", cond(nowPlayingName == nil, "fgMuted", nil)},
                width = "100%",
                height = "auto",
                textWrap = false,
                textOverflow = "ellipsis",
                text = nowPlayingName or "Nothing playing",
            },
            masterRow,
            mutedCauseLine,
            --Personal-tier caption for EVERY role now (decision 4): the tier
            --above is personal regardless of who you are; the broadcast block
            --below is what plays to the table.
            gui.Label{
                classes = {"sizeXxs", "fgMuted"},
                width = "100%",
                height = "auto",
                textWrap = true,
                text = "These change your mix only.",
            },
        }
        RefreshMutedCause()

        --Broadcast tier: Director or DJ only (DJ delegation decision 4). All
        --game-wide controls live here, including the game-wide mute as a
        --labeled control (promoted from the old master-row glyph tooltip).
        if bar.CanControlAudio ~= nil and bar.CanControlAudio() then
            children[#children+1] = gui.Label{
                classes = {"sizeXs", "fgMuted"},
                width = "100%",
                height = "auto",
                text = "Levels",
                tmargin = 4,
            }
            children[#children+1] = bar.MakeFaderRow("Music", bar.MakeBroadcastFader("music"), false)
            children[#children+1] = bar.MakeFaderRow("Ambience", bar.MakeBroadcastFader("ambience"), false)
            children[#children+1] = bar.MakeFaderRow("Effects", bar.MakeBroadcastFader("effects"), false)
            children[#children+1] = bar.MakeFaderRow("UI Sounds", bar.MakeBroadcastFader("uisounds"), false)
            children[#children+1] = bar.MakeFaderRow("Anthem", bar.MakeBroadcastFader("anthem"), false)

            local gameMuteToggle = gui.Panel{
                bgcolor = "white",
                width = 16,
                height = 16,
                valign = "center",
                hmargin = 4,
                press = function(element)
                    audio.muted = not audio.muted
                    audio.UploadMuted()
                    element:SetClass("muted", audio.muted)
                    muteToggle:SetClass("muted", IsClientMuted())
                    RefreshMutedCause()
                end,
                styles = {
                    { bgimage = "ui-icons/ph-speaker-high-fill.png" },
                    { selectors = {"muted"}, bgimage = "ui-icons/ph-speaker-slash-fill.png" },
                    { selectors = {"hover"}, brightness = 2 },
                },
                create = function(element)
                    element:SetClass("muted", audio.muted)
                end,
            }
            children[#children+1] = gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 22,
                valign = "center",
                tmargin = 4,
                gui.Label{
                    classes = {"sizeXs"},
                    text = "Mute for everyone",
                    width = "100%-26",
                    height = "auto",
                    valign = "center",
                },
                gameMuteToggle,
            }

            children[#children+1] = gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                tmargin = 4,
                gui.Button{
                    classes = {"sizeXs"},
                    text = "Stop all audio",
                    width = "auto",
                    height = 22,
                    hpad = 8,
                    borderBox = true,
                    hmargin = 3,
                    linger = function(element)
                        gui.Tooltip("Stop all audio. Also cancels auto game-mode music.")(element)
                    end,
                    press = function()
                        bar.StopAll()
                        resultPanel.popup = nil
                    end,
                },
                gui.Button{
                    classes = {"sizeXs"},
                    text = "Open Audio Studio",
                    width = "auto",
                    height = 22,
                    hpad = 8,
                    borderBox = true,
                    hmargin = 3,
                    press = function()
                        resultPanel.popup = nil
                        LaunchablePanel.LaunchPanelByName("Audio Studio")
                    end,
                },
            }
        end

        return gui.Panel{
            classes = {"bordered", "bg"},
            flow = "vertical",
            width = 340,
            height = "auto",
            pad = 8,
            borderBox = true,
            halign = "right",
            valign = "bottom",
            children = children,
        }
    end

    resultPanel = gui.Panel{
        classes = {"audioIndicator"},
        width = 18,
        height = 18,
        valign = "center",
        hmargin = 6,
        bgcolor = "white",
        bgimage = "ui-icons/ph-speaker-high-fill.png",

        linger = function(element)
            gui.Tooltip("Audio controls")(element)
        end,

        press = function(element)
            element.popupsInheritStyles = true
            element.popup = BuildPopover()
        end,

        -- Run the state logic once at construction too: without this the
        -- glyph renders its constructor defaults (volume icon, full opacity)
        -- for up to one think period even when muted/idle at build time.
        create = function(element)
            element:FireEvent("think")
        end,

        thinkTime = 0.5,
        think = function(element)
            local state = ComputeState()
            if element.data.audioIndicatorState == state then
                return
            end
            element.data.audioIndicatorState = state

            if state == "muted" then
                element.bgimage = "ui-icons/ph-speaker-slash-fill.png"
                element.selfStyle.opacity = 1
            elseif state == "playing" then
                element.bgimage = "ui-icons/ph-speaker-high-fill.png"
                element.selfStyle.opacity = 1
            else
                element.bgimage = "ui-icons/ph-speaker-none-fill.png"
                element.selfStyle.opacity = 0.4
            end
        end,
    }

    return resultPanel
end

local g_adventureDocumentsBar

local g_presentationBar

local g_searchBar

--- @type string[]
local g_searchStack = {}

--- @type table<string, table>
local g_searchHandlers = {}

TopBar = {}


--- @param documentids {string}
TopBar.SetAdventureDocuments = function(info, documentids)
    if g_adventureDocumentsBar ~= nil and g_adventureDocumentsBar.valid then
        if info then
            g_adventureDocumentsBar:FireEventTree("setname", info.name or "Adventure Documents")
            g_adventureDocumentsBar:FireEventTree("seticon", info.icon)
        end
        g_adventureDocumentsBar:FireEventTree("documents", documentids)
    end
end

--- @param info {id: string}
TopBar.SetPresentationInfo = function(info)
    if g_presentationBar == nil  or (not g_presentationBar.valid) then
        return
    end

    g_presentationBar.data.presentations[info.id] = info
    g_presentationBar:FireEventTree("refreshPresentation")
end

--- @param id string
TopBar.ClearPresentationInfo = function(id)
    if g_presentationBar == nil  or (not g_presentationBar.valid) then
        return
    end

    g_presentationBar.data.presentations[id] = nil
    g_presentationBar:FireEventTree("refreshPresentation")
end

TopBar.FocusSearchBar = function()
    if g_searchBar ~= nil and g_searchBar.valid then
        g_searchBar.hasFocus = true
    end
end

TopBar.HasCustomSearch = function()
    return #g_searchStack > 0
end

TopBar.ExecuteCustomSearch = function(text)
    if #g_searchStack == 0 then
        return true
    end

    local guid = g_searchStack[#g_searchStack]
    local handler = g_searchHandlers[guid]
    if handler == nil then
        return true
    end

    return handler(text)
end

TopBar.InstallSearchHandler = function(searchHandler)
    local guid = dmhub.GenerateGuid()
    print("SearchHandler: Install", guid)

    g_searchHandlers[guid] = searchHandler
    g_searchStack[#g_searchStack+1] = guid

    if g_searchBar ~= nil and g_searchBar.valid then
        g_searchBar:SetClassTree("searchoverride", true)
        print("SearchHandler: Set class")
    end

    return guid
end

TopBar.UninstallSearchHandler = function(guid)
    if guid == nil then
        return
    end
    print("SearchHandler: Uninstall", guid)
    g_searchHandlers[guid] = nil

    for i=#g_searchStack,1,-1 do
        if g_searchStack[i] == guid then
            table.remove(g_searchStack, i)
            break
        end
    end

    if #g_searchStack == 0 then
        if g_searchBar ~= nil and g_searchBar.valid then
            g_searchBar:SetClassTree("searchoverride", false)
        end
    end
end 

local function CreateTopBar()
	local dmControlsPanel = nil
	local layersPanel = nil

    --fetch the user's bug tickets once at startup so the Report Feedback
    --marker can appear without the menu ever being opened.
    FetchTickets()

    local m_inGame = nil
    local m_searchBar = CreateSearchBar()
    local m_audioIndicator = CreateAudioIndicator()
    local m_presentationBar = CreatePresentationBar()

    --last of the non-menu elements the narrow-bar ladder gives up
    BarFitRegister("audio", m_audioIndicator)

    g_searchBar = m_searchBar
    g_presentationBar = m_presentationBar


    local m_documents
    --Generic until the tracked documents say which adventure this is; GameHud's
    --adventure-documents manager fires "setname"/"seticon" with the real
    --identity. An icon must be set here for CreateCodexMenuItem to build the
    --icon panel at all -- that panel owns the "seticon" handler.
    local m_adventureDocumentsBar = CreateCodexMenuItem{
        icon = "phosphor/book-open.png",
        name = "Adventure Documents",
        create = function(element)
            element.selfStyle.collapsed = 1
        end,
        --Re-asserted on the bar's think (calculateVisibility is broadcast from
        --there) rather than only when the document list changes: this item
        --owns its selfStyle.collapsed, and a selfStyle write beats the fit
        --ladder's class rule, so a narrow bar could not collapse it from the
        --outside. Without the re-assert the ladder would skip straight past
        --this item and drop the menus to its left instead.
        calculateVisibility = function(element)
            element.selfStyle.collapsed = (m_documents == nil) or (#m_documents == 0)
                or (not dmhub.isDM) or BarFitMenuDropped(element)
        end,
        menuItems = function()
            local result = {}
            local documentsTable = dmhub.GetTable(CustomDocument.tableName) or {}
            for _,docid in ipairs(m_documents or {}) do
                local doc = documentsTable[docid]
                if doc ~= nil then
                    result[#result+1] = {
                        text = doc.name,
                        click = function()
                            doc:ShowDocument()
                        end,
                    }
                end
            end
            return result
        end,
        documents = function(element, documentids)
            m_documents = documentids
            --applied straight away so the item appears without waiting for a
            --think tick; calculateVisibility above keeps it right after that
            element:FireEvent("calculateVisibility")
        end,
    }

    g_adventureDocumentsBar = m_adventureDocumentsBar

    local g_bugReportLink = "https://discord.gg/x2yEdNFmUB"

    --Shows the feedback dialog for a report begun with dmhub.BeginBugReport.
    --The report already holds a screenshot captured before the dialog appeared.
    --feedbackType is "bug", "feature" or "feedback"; the log file is only
    --offered on bug reports.
    local function CreateBugReportDialog(report, feedbackType)
        local kinds = {
            bug = {
                title = "Report a Bug",
                intro = "Describe the bug below and submit it directly to the Codex developers. Please make a separate report for each bug.",
                placeholder = "Describe the bug: what happened, and what you expected to happen instead. If you can, include exact steps to reproduce it.",
                thanks = "Your bug report has been submitted. Thank you!",
                --shown alongside thanks when the ticket bridge exists: a bug
                --report also opens a ticket the user can follow up on.
                ticketInfo = "A ticket has been opened for your report. You can find it under Feedback > Your Tickets, where you can add details at any time. When a developer responds, a marker will appear on that menu.",
            },
            feature = {
                title = "Request a Feature",
                intro = "Describe the feature you would like below and it will be submitted directly to the Codex developers.",
                placeholder = "Describe the feature you would like, and the problem it would solve for you.",
                thanks = "Your feature request has been submitted. Thank you!",
            },
            feedback = {
                title = "Send Feedback",
                intro = "Share your feedback below and it will be submitted directly to the Codex developers.",
                placeholder = "Tell us what you think: what is working well, and what could be better?",
                thanks = "Your feedback has been submitted. Thank you!",
            },
        }

        local kindInfo = kinds[feedbackType]
        if kindInfo == nil then
            feedbackType = "bug"
            kindInfo = kinds.bug
        end

        local isBugReport = (feedbackType == "bug")

        local m_dialog = nil
        local m_titlescreenModal = nil
        local m_attachments = {}
        local m_submitting = false
        local m_submitted = false
        --The ticket id assigned to this report, captured once Submit completes.
        --Surfaced to the user in statusLabel and copyable by clicking it.
        local m_reportid = nil

        local m_includeLog = isBugReport
        local m_includeScreenshot = false
        local m_allowGameEntry = true
        local m_contactOnDiscord = true
        local m_mood = nil

        --the dialog is hosted in the gamehud modal stack in-game, or as a
        --floating panel on the titlescreen root otherwise.
        local function CloseDialog()
            if m_titlescreenModal ~= nil then
                if m_titlescreenModal.valid then
                    m_titlescreenModal:DestroySelf()
                end
            elseif m_dialog ~= nil and m_dialog.valid then
                m_dialog:FireEvent("close")
            end
        end

        local descriptionInput = gui.Input{
            width = 880,
            height = 150,
            fontSize = 16,
            multiline = true,
            characterLimit = 10000,
            textAlignment = "topleft",
            halign = "left",
            tmargin = 4,
            placeholderText = kindInfo.placeholder,
        }

        local screenshotSection = nil
        if report.screenshotImage ~= nil then
            local aspect = 9 / 16
            if report.screenshotWidth > 0 then
                aspect = report.screenshotHeight / report.screenshotWidth
            end

            screenshotSection = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                tmargin = 8,

                gui.Panel{
                    classes = {"bordered"},
                    bgimage = report.screenshotImage,
                    bgcolor = "white",
                    width = 280,
                    height = math.floor(280 * aspect),
                    halign = "left",
                    valign = "center",
                },

                gui.Check{
                    text = "Include this screenshot of your screen",
                    value = m_includeScreenshot,
                    halign = "left",
                    valign = "center",
                    lmargin = 16,
                    change = function(element)
                        m_includeScreenshot = element.value
                    end,
                },
            }
        end

        --the log file is only relevant to bug reports.
        local logCheck = nil
        if isBugReport then
            logCheck = gui.Check{
                text = "Include my log file (recommended)",
                tooltip = "Your log file helps developers diagnose the problem. If a log from your previous session exists (for example after a crash and restart), it is included too. Logs contain a small amount of personal data, such as your system username, and are compressed before uploading.",
                value = m_includeLog,
                halign = "left",
                tmargin = 12,
                change = function(element)
                    m_includeLog = element.value
                end,
            }
        end

        local gameEntryCheck = gui.Check{
            text = "Allow Codex developers to enter my game if needed",
            value = m_allowGameEntry,
            halign = "left",
            tmargin = cond(isBugReport, 4, 12),
            change = function(element)
                m_allowGameEntry = element.value
            end,
        }

        --Discord follow-up: if the Discord desktop client is running we know the
        --user's Discord handle and can offer to contact them about the report.
        --Otherwise explain that we cannot follow up.
        local discordSection
        if report.discordUsername ~= nil then
            discordSection = gui.Check{
                text = "Contact me on Discord (" .. report.discordUsername .. ") to follow up on this report",
                tooltip = "If checked, your Discord username is included with the report so a Codex developer can reach out to you about it. Leave unchecked to keep your Discord username private.",
                value = m_contactOnDiscord,
                halign = "left",
                tmargin = 12,
                change = function(element)
                    m_contactOnDiscord = element.value
                end,
            }
        else
            discordSection = gui.Label{
                fontSize = 15,
                width = 880,
                height = "auto",
                textWrap = true,
                halign = "left",
                tmargin = 12,
                text = "Discord isn't linked, so we won't be able to follow up with you about this report. Run the Discord app alongside Codex if you would like us to be able to reach out.",
            }
        end

        local m_attachmentsList = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
        }

        local function RefreshAttachments()
            local children = {}
            for i,path in ipairs(m_attachments) do
                local index = i
                local fileName = path
                for j = #path, 1, -1 do
                    local c = path:sub(j, j)
                    if c == "/" or c == "\\" then
                        fileName = path:sub(j + 1)
                        break
                    end
                end

                children[#children + 1] = gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    vmargin = 2,

                    gui.Label{
                        fontSize = 15,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        text = fileName,
                    },

                    gui.Button{
                        classes = {"sizeXs"},
                        text = "Remove",
                        valign = "center",
                        lmargin = 12,
                        width = 60,
                        click = function(element)
                            if m_submitting or m_submitted then
                                return
                            end
                            table.remove(m_attachments, index)
                            RefreshAttachments()
                        end,
                    },
                }
            end

            m_attachmentsList.children = children
        end

        local attachButton = gui.Button{
            classes = {"sizeM"},
            text = "Attach File...",
            halign = "left",
            tmargin = 12,
            click = function(element)
                if m_submitting or m_submitted then
                    return
                end
                dmhub.OpenFileDialog{
                    id = "bugreportattachment",
                    prompt = "Choose files to attach to your bug report",
                    extensions = {},
                    multiFiles = true,
                    openFiles = function(paths)
                        for _,path in ipairs(paths) do
                            local alreadyAdded = false
                            for _,existing in ipairs(m_attachments) do
                                if existing == path then
                                    alreadyAdded = true
                                end
                            end
                            if not alreadyAdded then
                                m_attachments[#m_attachments + 1] = path
                            end
                        end
                        RefreshAttachments()
                    end,
                }
            end,
        }

        local statusLabel = gui.Label{
            fontSize = 16,
            width = "100%",
            height = "auto",
            halign = "left",
            textWrap = true,
            tmargin = 8,
            text = "",

            --After submitting, this label shows the ticket id; clicking copies
            --it to the clipboard so the user can quote it back to us. No-ops
            --until a report has actually been submitted (m_reportid is nil).
            click = function(element)
                if m_reportid ~= nil and m_reportid ~= "" then
                    gui.Tooltip{ text = "Copied to Clipboard", valign = "top", borderWidth = 0 }(element)
                    dmhub.CopyToClipboard(m_reportid)
                end
            end,
        }

        local submitButton

        submitButton = gui.Button{
            classes = {"sizeL"},
            text = "Submit Report",
            halign = "right",
            hmargin = 8,
            click = function(element)
                if m_submitting or m_submitted then
                    return
                end

                local description = descriptionInput.text
                if description == nil or description == "" then
                    statusLabel.text = "Please enter a description before submitting."
                    return
                end

                m_submitting = true
                statusLabel.text = "Submitting..."

                report:Submit{
                    description = description,
                    type = feedbackType,
                    includeLog = m_includeLog,
                    includeScreenshot = m_includeScreenshot,
                    allowGameEntry = m_allowGameEntry,
                    contactOnDiscord = m_contactOnDiscord,
                    mood = m_mood,
                    attachments = m_attachments,
                    progress = function(ratio)
                        if statusLabel.valid and not m_submitted then
                            statusLabel.text = string.format("Submitting... %d%%", math.floor(ratio * 100 + 0.5))
                        end
                    end,
                    complete = function(reportid)
                        m_submitting = false
                        m_submitted = true
                        m_reportid = reportid
                        if statusLabel.valid then
                            local text = kindInfo.thanks
                            if kindInfo.ticketInfo ~= nil and TicketBridgeAvailable() then
                                text = text .. "\n\n" .. kindInfo.ticketInfo
                            end
                            if reportid ~= nil and reportid ~= "" then
                                text = text .. string.format("\n\nYour ticket ID is %s (click to copy).", reportid)
                            end
                            statusLabel.text = text
                            submitButton:SetClass("hidden", true)
                        end

                        --pick up the freshly created ticket so Your Tickets
                        --and the menu marker reflect it immediately.
                        FetchTickets()
                    end,
                    error = function(message)
                        m_submitting = false
                        if statusLabel.valid then
                            statusLabel.text = "Could not submit: " .. message
                        end
                    end,
                }
            end,
        }

        --Standard X close button pinned to the dialog's top-right corner. It
        --doubles as the cancel action: cancels the in-flight report (unless it
        --already submitted) and closes the dialog. Attached to the dialog frame
        --below (in-game modal / titlescreen panel / fallback modal).
        local closeButton = gui.Button{
            classes = {"closeButton"},
            floating = true,
            halign = "right",
            valign = "top",
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                if not m_submitted then
                    report:Cancel()
                end
                CloseDialog()
            end,
        }

        --Optional mood picker: five Fluent emoji (angry -> delighted) so the
        --user can convey how they feel; stored on the report as `mood`. The art
        --lives at Assets/UIImages/emotes/<mood>.png (run import-ui-images.ps1 +
        --build for these to resolve).
        local m_moodButtons = {}
        local function RefreshMoodSelection()
            for _,entry in ipairs(m_moodButtons) do
                entry.panel:SetClass("selected", entry.id == m_mood)
            end
        end

        local moodOrder = {
            { id = "angry", label = "Angry" },
            { id = "frustrated", label = "Frustrated" },
            { id = "sad", label = "Sad" },
            { id = "happy", label = "Happy" },
            { id = "delighted", label = "Delighted" },
        }

        local moodButtonPanels = {}
        for _,opt in ipairs(moodOrder) do
            local optid = opt.id
            local btn = gui.Panel{
                classes = {"moodButton"},
                bgimage = "emotes/" .. optid .. ".png",
                bgcolor = "white",
                --raw gui.Panel does not auto-wrap a string tooltip the way
                --gui.Check/Button do, so attach the lazy hover handler directly
                --(a bare `tooltip = string` eagerly creates an orphan panel).
                hover = gui.Tooltip(opt.label),
                press = function(element)
                    m_mood = cond(m_mood == optid, nil, optid)
                    RefreshMoodSelection()
                end,
            }
            m_moodButtons[#m_moodButtons + 1] = { panel = btn, id = optid }
            moodButtonPanels[#moodButtonPanels + 1] = btn
        end

        local moodPickerSection = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "left",
            vmargin = 4,

            styles = {
                { selectors = {"moodButton"}, width = 44, height = 44, hmargin = 6, valign = "center", bgcolor = "white", opacity = 0.5 },
                { selectors = {"moodButton", "hover"}, opacity = 0.85 },
                { selectors = {"moodButton", "selected"}, opacity = 1.0, scale = 1.15 },
            },

            gui.Label{
                fontSize = 15,
                width = "auto",
                height = "auto",
                halign = "left",
                text = "How are you feeling? (optional)",
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                tmargin = 4,
                children = moodButtonPanels,
            },
        }

        --assemble the form children explicitly; screenshotSection may be nil and
        --a nil hole in a positional children list would truncate it.
        local formChildren = {
            gui.Label{
                width = 880,
                height = "auto",
                fontSize = 15,
                textWrap = true,
                halign = "left",
                vmargin = 4,
                text = kindInfo.intro,
            },

            moodPickerSection,

            descriptionInput,
        }

        if logCheck ~= nil then
            formChildren[#formChildren + 1] = logCheck
        end

        formChildren[#formChildren + 1] = gameEntryCheck
        formChildren[#formChildren + 1] = discordSection

        if screenshotSection ~= nil then
            formChildren[#formChildren + 1] = screenshotSection
        end

        formChildren[#formChildren + 1] = attachButton
        formChildren[#formChildren + 1] = m_attachmentsList

        --sized so the whole form is visible without scrolling (the tallest
        --variant is a bug report with a screenshot section); vscroll remains
        --as a safety net for long attachment lists. Below the scroll region
        --the body reserves ~140 of slack so the post-submit status text
        --(thanks + ticket info + ticket id, ~6 wrapped lines) plus the
        --bottom button bar always fit inside the frame instead of pushing
        --the bar out of the bottom of the dialog.
        local bodyPanel = gui.Panel{
                width = 940,
                height = 830,
                flow = "vertical",
                halign = "center",

                gui.Panel{
                    width = "100%",
                    height = 640,
                    vscroll = true,
                    flow = "vertical",
                    halign = "center",

                    children = formChildren,
                },

                statusLabel,

                --Single bottom bar: Open Discord pinned to the bottom-left
                --corner, Submit Report pinned to the bottom-right corner.
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    valign = "bottom",
                    tmargin = 12,

                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "left",
                        valign = "center",

                        gui.Label{
                            fontSize = 14,
                            width = "auto",
                            height = "auto",
                            valign = "center",
                            text = "You can also discuss bugs with us on the Draw Steel Codex Discord:",
                        },

                        gui.Button{
                            classes = {"sizeS"},
                            text = "Open Discord",
                            valign = "center",
                            lmargin = 8,
                            width = 180,
                            click = function(element)
                                dmhub.OpenURL(g_bugReportLink)
                            end,
                        },
                    },

                    submitButton,
                },
        }

        local function ShowInGamehudModal()
            local gh = rawget(_G, "gamehud")
            if gh == nil then
                report:Cancel()
                return
            end

            m_dialog = gh:ModalDialog{
                title = kindInfo.title,

                --ModalDialog's frame defaults to 768 tall; the 830-tall body
                --plus the title and ModalDialog's (empty) 60-tall button
                --strip needs the same 960 the titlescreen host uses, or the
                --body overflows out of the frame.
                width = 1024,
                height = 960,

                --we build our own buttons inside the body so Submit can stay open
                --while the report uploads.
                buttons = {},

                bodyPanel,
            }
            m_dialog:AddChild(closeButton)
        end

        --Host selection. In a real game the gamehud modal stack owns the dialog.
        --
        --On the titlescreen we normally host on the titlescreen root, like the
        --other titlescreen dialogs -- but NOT while a character sheet is open.
        --EditHero sets "titlescreenHidden" on the root, and the root's style
        --rule hides every direct child of it, so a report parented there is
        --invisible (the reported bug: the sheet appears "over" the report).
        --The titlescreen has to get out of the way like that because the
        --character sheet's canvas swallows all pointer input even though it
        --renders below the titlescreen -- a visible titlescreen over an open
        --sheet would be dead UI. The gamehud modal layer lives in the sheet's
        --own canvas and sorts above it, so that is the only host that keeps
        --the report on top while a sheet is up.
        local root = rawget(_G, "CodexTitlescreenRoot")
        local canHostOnTitlescreen = root ~= nil and root.valid
            and not root:HasClass("titlescreenHidden")

        if (dmhub.inGame and not dmhub.isLobbyGame) or (not canHostOnTitlescreen) then
            ShowInGamehudModal()
        else
            --Floating framed panel on the titlescreen root. The panel owns its
            --own theme cascade, mirroring the frame gamehud:ModalDialog builds.
            m_titlescreenModal = gui.Panel{
                classes = {"framedPanel"},
                floating = true,
                width = 1024,
                height = 960,
                halign = "center",
                valign = "center",
                styles = ThemeEngine.GetStyles(),

                gui.Panel{
                    width = "100%-32",
                    height = "100%-32",
                    flow = "vertical",
                    halign = "center",
                    valign = "top",

                    gui.Label{
                        classes = {"dialogTitle"},
                        text = kindInfo.title,
                    },

                    bodyPanel,
                },
            }
            root:AddChild(m_titlescreenModal)
            m_titlescreenModal:AddChild(closeButton)
        end
    end

    --F3 (bound to the "bugreport" command in InputController.ResetBinds) opens the
    --Report a Bug dialog directly, skipping the Report Feedback menu. Registered
    --here inside CreateTopBar so the handler closes over the CreateBugReportDialog
    --local above; CreateTopBar runs once at load, so this registers once.
    Commands.RegisterMacro{
        name = "bugreport",
        summary = "report a bug",
        doc = "Opens the Report a Bug dialog.",
        command = function()
            dmhub.BeginBugReport(function(report)
                CreateBugReportDialog(report, "bug")
            end)
        end,
    }

    --Tickets dialog (Report Feedback > Your Tickets): lists the user's bug
    --tickets, open and closed, and shows the conversation on each ticket so
    --the user can read developer responses and add messages of their own.
    --Opening a ticket marks it seen, clearing the "developer responded"
    --marker on the Report Feedback menu.
    local function CreateTicketsDialog()
        local m_dialog = nil
        local m_titlescreenModal = nil

        local m_tickets = {}      --sorted array of ticket records.
        local m_page = "loading"  --"loading", "error", "list" or "detail".
        local m_errorMessage = nil
        local m_selected = nil    --reportId of the ticket shown in detail view.
        local m_sending = false
        local m_localMessageCounter = 0

        local function CloseDialog()
            if m_titlescreenModal ~= nil then
                if m_titlescreenModal.valid then
                    m_titlescreenModal:DestroySelf()
                end
            elseif m_dialog ~= nil and m_dialog.valid then
                m_dialog:FireEvent("close")
            end
        end

        --forward declared; assigned below and captured by the page builders.
        local contentPanel
        local RefreshPage
        local OpenDetail

        local function SortedTickets()
            local result = {}
            for _,t in pairs(g_ticketsState.tickets or {}) do
                if type(t) == "table" then
                    result[#result+1] = t
                end
            end
            table.sort(result, function(a, b)
                return (a.updatedAt or a.createdAt or 0) > (b.updatedAt or b.createdAt or 0)
            end)
            return result
        end

        local function TicketById(reportId)
            for _,t in ipairs(m_tickets) do
                if t.reportId == reportId then
                    return t
                end
            end
            return nil
        end

        local function FormatDay(ms)
            if type(ms) ~= "number" then
                return ""
            end
            return os.date("%b %d, %Y", math.floor(ms / 1000))
        end

        local function FormatTime(ms)
            if type(ms) ~= "number" then
                return ""
            end
            return os.date("%b %d, %Y %H:%M", math.floor(ms / 1000))
        end

        --messages arrive as a map keyed by chronologically sortable strings;
        --sort by timestamp with the key as a tiebreak.
        local function SortedMessages(ticket)
            local result = {}
            for key,msg in pairs(ticket.messages or {}) do
                if type(msg) == "table" then
                    result[#result+1] = { key = key, msg = msg }
                end
            end
            table.sort(result, function(a, b)
                local ta = a.msg.timestamp or 0
                local tb = b.msg.timestamp or 0
                if ta == tb then
                    return a.key < b.key
                end
                return ta < tb
            end)
            return result
        end

        local function BuildMessagePage(text)
            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Label{
                    fontSize = 18,
                    width = 700,
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    textAlignment = "center",
                    textWrap = true,
                    text = text,
                },
            }
        end

        local function StatusChip(ticket)
            local closed = (ticket.status == "closed")
            return gui.Label{
                fontSize = 13,
                bold = true,
                width = 70,
                height = "auto",
                valign = "center",
                textAlignment = "center",
                color = cond(closed, "#999999", "#86c06c"),
                text = cond(closed, "CLOSED", "OPEN"),
            }
        end

        local function BuildListPage()
            if #m_tickets == 0 then
                return BuildMessagePage("You have not filed any bug reports yet.\n\nWhen you report a bug from the Feedback menu, a ticket is opened here where the developers can follow up with you.")
            end

            local rows = {}
            for _,t in ipairs(m_tickets) do
                local ticket = t
                local unseen = TicketHasUnseenResponse(ticket)

                local markerPanel = nil
                if unseen then
                    markerPanel = gui.NewContentAlert{
                        floating = false,
                        x = 0,
                        halign = "center",
                        valign = "center",
                    }
                end

                rows[#rows+1] = gui.Panel{
                    classes = {"ticketRow"},
                    bgimage = "panels/square.png",
                    width = "100%",
                    height = "auto",
                    valign = "top",
                    flow = "horizontal",
                    borderBox = true,
                    pad = 6,
                    vmargin = 2,

                    press = function(element)
                        OpenDetail(ticket.reportId)
                    end,

                    --fixed-width marker slot so titles align whether or not
                    --the unseen-response dot is present.
                    gui.Panel{
                        width = 16,
                        height = 20,
                        halign = "left",
                        valign = "center",
                        interactable = false,
                        markerPanel,
                    },

                    StatusChip(ticket),

                    gui.Label{
                        fontSize = 16,
                        width = 500,
                        height = "auto",
                        halign = "left",
                        valign = "center",
                        lmargin = 8,
                        textWrap = true,
                        interactable = false,
                        text = ticket.title or "(no title)",
                    },

                    gui.Label{
                        fontSize = 14,
                        color = "#aaaaaa",
                        width = 110,
                        height = "auto",
                        halign = "right",
                        valign = "center",
                        interactable = false,
                        text = ticket.reportId or "",
                    },

                    gui.Label{
                        fontSize = 14,
                        color = "#aaaaaa",
                        width = 130,
                        height = "auto",
                        halign = "right",
                        valign = "center",
                        textAlignment = "right",
                        interactable = false,
                        text = FormatDay(ticket.updatedAt or ticket.createdAt),
                    },
                }
            end

            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Label{
                    fontSize = 15,
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    textWrap = true,
                    vmargin = 4,
                    text = "Your bug report tickets. Click a ticket to read developer responses and add more information.",
                },

                gui.Panel{
                    width = "100%",
                    height = 660,
                    vscroll = true,
                    flow = "vertical",
                    children = rows,
                },
            }
        end

        local function BuildDetailPage()
            local ticket = TicketById(m_selected)
            if ticket == nil then
                return BuildMessagePage("This ticket could not be found.")
            end

            local messagePanels = {}
            for _,entry in ipairs(SortedMessages(ticket)) do
                local msg = entry.msg
                local fromDev = (msg.from == "dev")
                local who = "You"
                if fromDev then
                    who = "Codex Team"
                    if type(msg.name) == "string" and msg.name ~= "" then
                        who = string.format("Codex Team (%s)", msg.name)
                    end
                end

                messagePanels[#messagePanels+1] = gui.Panel{
                    width = "100%-16",
                    height = "auto",
                    flow = "vertical",
                    halign = "left",
                    valign = "top",
                    vmargin = 6,

                    gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",

                        gui.Label{
                            fontSize = 14,
                            bold = true,
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            color = cond(fromDev, "#86b4e0", "#d0c3a5"),
                            text = who,
                        },

                        gui.Label{
                            fontSize = 12,
                            width = "auto",
                            height = "auto",
                            halign = "right",
                            color = "#999999",
                            text = FormatTime(msg.timestamp),
                        },
                    },

                    gui.Label{
                        fontSize = 15,
                        width = "100%",
                        height = "auto",
                        halign = "left",
                        tmargin = 2,
                        textWrap = true,
                        text = msg.text or "",
                    },
                }
            end

            local replyInput = gui.Input{
                width = "100%",
                height = 80,
                fontSize = 15,
                multiline = true,
                characterLimit = 10000,
                textAlignment = "topleft",
                halign = "left",
                tmargin = 8,
                placeholderText = "Add a message to this ticket...",
            }

            local sendStatus = gui.Label{
                fontSize = 14,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                text = "",
            }

            local sendButton = gui.Button{
                classes = {"sizeM"},
                text = "Send",
                halign = "right",
                valign = "center",
                click = function(element)
                    if m_sending then
                        return
                    end
                    local text = replyInput.text
                    if text == nil or text == "" then
                        sendStatus.text = "Enter a message first."
                        return
                    end

                    m_sending = true
                    sendStatus.text = "Sending..."

                    local ok = pcall(function()
                        dmhub.AddTicketMessage{
                            reportId = ticket.reportId,
                            text = text,
                            complete = function()
                                m_sending = false
                                --record the message locally so the thread
                                --updates without waiting for a refetch.
                                m_localMessageCounter = m_localMessageCounter + 1
                                ticket.messages = ticket.messages or {}
                                ticket.messages[string.format("zlocal%04d", m_localMessageCounter)] = {
                                    from = "user",
                                    text = text,
                                    timestamp = os.time() * 1000,
                                }
                                ticket.updatedAt = os.time() * 1000
                                RefreshPage()
                            end,
                            error = function(message)
                                m_sending = false
                                if sendStatus.valid then
                                    sendStatus.text = "Could not send: " .. message
                                end
                            end,
                        }
                    end)

                    if not ok then
                        m_sending = false
                        sendStatus.text = "Could not send the message."
                    end
                end,
            }

            local closed = (ticket.status == "closed")

            local closedNotice = nil
            if closed then
                local noticeText = "This ticket has been closed by the developers. You can still add a message if you have more information."
                if ticket.closedBy == "user" then
                    noticeText = "You closed this ticket. You can reopen it if the problem comes back, or add a message with more information."
                end
                closedNotice = gui.Label{
                    fontSize = 14,
                    color = "#999999",
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    tmargin = 6,
                    textWrap = true,
                    text = noticeText,
                }
            end

            --The reporter can resolve their own ticket -- they worked it out,
            --it was their own setup, it stopped happening -- and reopen it if
            --the problem comes back. Both directions go through the same
            --bridge call, which stamps closedBy so the team dashboard can tell
            --a reporter-resolved ticket from a developer-resolved one.
            local statusButton = nil
            if TicketStatusBridgeAvailable() then
                statusButton = gui.Button{
                    classes = {"sizeM"},
                    text = cond(closed, "Reopen Ticket", "Close Ticket"),
                    width = 160,
                    halign = "right",
                    valign = "center",
                    rmargin = 8,
                    hover = gui.Tooltip(cond(closed,
                        "Reopen this ticket if the problem is still happening.",
                        "Close this ticket if you no longer need help with it. You can reopen it later.")),
                    click = function(element)
                        if m_sending then
                            return
                        end

                        local newStatus = cond(closed, "open", "closed")

                        m_sending = true
                        sendStatus.text = cond(closed, "Reopening...", "Closing...")

                        local ok = pcall(function()
                            dmhub.SetTicketStatus{
                                reportId = ticket.reportId,
                                status = newStatus,
                                complete = function()
                                    m_sending = false
                                    --mirror the server write locally: these
                                    --records are the same tables the list page
                                    --and the alert state read, so the chip and
                                    --notice update without a refetch.
                                    ticket.status = newStatus
                                    ticket.closedBy = cond(newStatus == "closed", "user", nil)
                                    ticket.updatedAt = os.time() * 1000
                                    RefreshPage()
                                end,
                                error = function(message)
                                    m_sending = false
                                    if sendStatus.valid then
                                        sendStatus.text = "Could not update the ticket: " .. message
                                    end
                                end,
                            }
                        end)

                        if not ok then
                            m_sending = false
                            sendStatus.text = "Could not update the ticket."
                        end
                    end,
                }
            end

            --explicit list: statusButton is nil on older engines, and a nil
            --positional child would swallow the Send button after it.
            local buttons = {}
            if statusButton ~= nil then
                buttons[#buttons+1] = statusButton
            end
            buttons[#buttons+1] = sendButton

            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",

                    gui.Button{
                        classes = {"sizeS"},
                        text = "Back",
                        width = 90,
                        halign = "left",
                        valign = "center",
                        click = function(element)
                            m_page = "list"
                            m_selected = nil
                            RefreshPage()
                        end,
                    },

                    gui.Label{
                        fontSize = 20,
                        width = 540,
                        height = "auto",
                        halign = "left",
                        valign = "center",
                        lmargin = 12,
                        textWrap = true,
                        text = ticket.title or "(no title)",
                    },

                    StatusChip(ticket),

                    gui.Label{
                        fontSize = 14,
                        color = "#aaaaaa",
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        valign = "center",
                        text = ticket.reportId or "",
                        hover = gui.Tooltip("Click to copy the ticket ID"),
                        click = function(element)
                            if ticket.reportId ~= nil then
                                gui.Tooltip{ text = "Copied to Clipboard", valign = "top", borderWidth = 0 }(element)
                                dmhub.CopyToClipboard(ticket.reportId)
                            end
                        end,
                    },
                },

                gui.Panel{
                    classes = {"bordered"},
                    width = "100%",
                    height = 440,
                    vscroll = true,
                    flow = "vertical",
                    tmargin = 8,
                    borderBox = true,
                    pad = 8,
                    children = messagePanels,
                },

                closedNotice,

                replyInput,

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    tmargin = 6,

                    sendStatus,

                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "right",
                        valign = "center",
                        children = buttons,
                    },
                },
            }
        end

        OpenDetail = function(reportId)
            m_selected = reportId
            m_page = "detail"

            local ticket = TicketById(reportId)
            if ticket ~= nil then
                --viewing the ticket clears the developer-responded marker;
                --tell the server, and raise the local seen floor so a fetch
                --racing the (fire-and-forget) server write cannot resurrect
                --the marker for a ticket the user just read.
                pcall(function() dmhub.MarkTicketSeen(reportId) end)
                g_localTicketSeenFloor[reportId] = (ticket.lastDevMessageAt or 0) + 1
                RefreshTicketAlerts()
            end

            RefreshPage()
        end

        RefreshPage = function()
            if contentPanel == nil or not contentPanel.valid then
                return
            end

            local page
            if m_page == "loading" then
                page = BuildMessagePage("Loading your tickets...")
            elseif m_page == "error" then
                page = BuildMessagePage(m_errorMessage or "Could not load your tickets.")
            elseif m_page == "detail" then
                page = BuildDetailPage()
            else
                page = BuildListPage()
            end

            contentPanel.children = { page }
        end

        contentPanel = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",

            styles = {
                { selectors = {"ticketRow"}, bgcolor = "#00000000", transitionTime = 0.1 },
                { selectors = {"ticketRow", "hover"}, bgcolor = "#ffffff26" },
            },
        }

        local bodyPanel = gui.Panel{
            width = 940,
            height = 740,
            flow = "vertical",
            halign = "center",

            contentPanel,
        }

        local closeButton = gui.Button{
            classes = {"closeButton"},
            floating = true,
            halign = "right",
            valign = "top",
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                CloseDialog()
            end,
        }

        if dmhub.inGame and not dmhub.isLobbyGame then
            m_dialog = gamehud:ModalDialog{
                title = "Your Tickets",
                --same 900-tall frame as the bug dialog; the default 768 is too
                --short for the 740-tall body plus title and button strip.
                width = 1024,
                height = 900,
                buttons = {},
                bodyPanel,
            }
            m_dialog:AddChild(closeButton)
        else
            --titlescreen host, mirroring the bug report dialog above.
            local root = rawget(_G, "CodexTitlescreenRoot")
            if root ~= nil and root.valid then
                m_titlescreenModal = gui.Panel{
                    classes = {"framedPanel"},
                    floating = true,
                    width = 1024,
                    height = 900,
                    halign = "center",
                    valign = "center",
                    styles = ThemeEngine.GetStyles(),

                    gui.Panel{
                        width = "100%-32",
                        height = "100%-32",
                        flow = "vertical",
                        halign = "center",
                        valign = "top",

                        gui.Label{
                            classes = {"dialogTitle"},
                            text = "Your Tickets",
                        },

                        bodyPanel,
                    },
                }
                root:AddChild(m_titlescreenModal)
                m_titlescreenModal:AddChild(closeButton)
            else
                local gh = rawget(_G, "gamehud")
                if gh ~= nil then
                    m_dialog = gh:ModalDialog{
                        title = "Your Tickets",
                        width = 1024,
                        height = 900,
                        buttons = {},
                        bodyPanel,
                    }
                    m_dialog:AddChild(closeButton)
                end
            end
        end

        RefreshPage()

        FetchTickets(function(tickets, error)
            if error ~= nil then
                m_page = "error"
                m_errorMessage = "Could not load your tickets: " .. error
            else
                m_tickets = SortedTickets()
                m_page = "list"
            end
            RefreshPage()
        end)
    end

    --Survey dialog (Report Feedback > Survey): reads the survey definition
    --from the cloud (/survey) along with the user's previous response
    --(/surveyFeedback/<userid>), then walks the user through the questions
    --one page at a time in a wizard and uploads the answers with
    --dmhub.SubmitSurveyResponse. A user who already responded is thanked and
    --offered the chance to change their answers, which arrive prefilled from
    --their previous response.
    local function CreateSurveyDialog()
        local m_dialog = nil
        local m_titlescreenModal = nil

        local m_survey = nil     --survey definition table from the cloud.
        local m_response = nil   --the user's previous response record, if any.
        local m_answers = {}     --working answers, keyed by question id.
        local m_page = "loading" --"loading", "error", "intro", "finished", or a question index.
        local m_errorMessage = nil
        local m_submitting = false

        local function CloseDialog()
            if m_titlescreenModal ~= nil then
                if m_titlescreenModal.valid then
                    m_titlescreenModal:DestroySelf()
                end
            elseif m_dialog ~= nil and m_dialog.valid then
                m_dialog:FireEvent("close")
            end
        end

        --forward declared; assigned below and captured by the page builder closures.
        local contentPanel
        local RefreshPage

        --gui.Input only delivers its text reliably when read directly, so any
        --page holding an input registers a commit function here that pulls the
        --input's text into m_answers; navigation calls it before leaving the page.
        local m_commitPageInput = nil
        local function CommitPageInput()
            if m_commitPageInput ~= nil then
                m_commitPageInput()
            end
        end

        local function HasAnswer(q)
            local a = m_answers[q.id]
            if a == nil then
                return false
            end
            if q.type == "text" then
                return a ~= ""
            end
            if q.type == "multiselect" then
                if type(a) ~= "table" then
                    return false
                end
                if a.other ~= nil and a.other ~= "" then
                    return true
                end
                if type(a.selected) == "table" then
                    for _,v in pairs(a.selected) do
                        if v then
                            return true
                        end
                    end
                end
                return false
            end
            return true
        end

        --page builders.
        local function BuildMessagePage(text)
            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Label{
                    fontSize = 18,
                    width = 700,
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    textAlignment = "center",
                    textWrap = true,
                    text = text,
                },
            }
        end

        local function BuildIntroPage()
            local alreadyCompleted = (m_response ~= nil)

            local message
            if alreadyCompleted then
                message = m_survey.completedMessage or "You have already completed this survey - thank you! You can review and change your answers at any time."
            else
                message = m_survey.intro or "We would love to hear about your experience with the Codex."
            end

            local startText = "Start Survey"
            if alreadyCompleted then
                startText = "Change My Answers"
            end

            local nquestions = 0
            if type(m_survey.questions) == "table" then
                nquestions = #m_survey.questions
            end

            local children = {
                gui.Label{
                    fontSize = 30,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    text = m_survey.title or "Codex Survey",
                },

                gui.Label{
                    fontSize = 17,
                    width = 640,
                    height = "auto",
                    halign = "center",
                    textAlignment = "center",
                    textWrap = true,
                    tmargin = 20,
                    text = message,
                },

                gui.Label{
                    fontSize = 14,
                    color = "#aaaaaa",
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    tmargin = 14,
                    text = string.format("%d questions - takes a few minutes", nquestions),
                },

                gui.Button{
                    classes = {"sizeL"},
                    text = startText,
                    halign = "center",
                    tmargin = 32,
                    click = function(element)
                        m_page = 1
                        RefreshPage()
                    end,
                },
            }

            if alreadyCompleted then
                children[#children + 1] = gui.Button{
                    classes = {"sizeM"},
                    text = "Close",
                    halign = "center",
                    tmargin = 10,
                    click = function(element)
                        CloseDialog()
                    end,
                }
            end

            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    valign = "center",
                    children = children,
                },
            }
        end

        local function BuildFinishedPage()
            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    valign = "center",

                    gui.Label{
                        fontSize = 30,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        text = "Thank You!",
                    },

                    gui.Label{
                        fontSize = 17,
                        width = 640,
                        height = "auto",
                        halign = "center",
                        textAlignment = "center",
                        textWrap = true,
                        tmargin = 20,
                        text = m_survey.thanks or "Thank you for completing the survey!",
                    },

                    gui.Button{
                        classes = {"sizeL"},
                        text = "Close",
                        halign = "center",
                        tmargin = 32,
                        click = function(element)
                            CloseDialog()
                        end,
                    },
                },
            }
        end

        --builds the interactive answer control for one question. Every control
        --is a centered column so the page reads as a single balanced block.
        local function BuildQuestionControl(q)
            local qid = q.id

            if q.type == "text" then
                local input = gui.Input{
                    width = 700,
                    height = 220,
                    fontSize = 16,
                    multiline = true,
                    characterLimit = 5000,
                    textAlignment = "topleft",
                    halign = "center",
                    tmargin = 28,
                    placeholderText = q.placeholder or "Type your answer here...",
                    text = m_answers[qid] or "",
                }
                m_commitPageInput = function()
                    if input.valid then
                        m_answers[qid] = input.text
                    end
                end
                return input
            end

            if q.type == "rating" then
                local labels = q.labels or {"1", "2", "3", "4", "5"}
                local m_buttons = {}
                local caption

                local function RefreshSelection()
                    for _,entry in ipairs(m_buttons) do
                        entry.panel:SetClassTree("selected", m_answers[qid] == entry.value)
                    end
                    if caption ~= nil and caption.valid then
                        local value = m_answers[qid]
                        if value ~= nil and labels[value] ~= nil then
                            caption.text = labels[value]
                        else
                            caption.text = ""
                        end
                    end
                end

                local buttonPanels = {}
                for i,_ in ipairs(labels) do
                    local value = i
                    local btn = gui.Panel{
                        classes = {"ratingButton"},
                        bgimage = true,
                        press = function(element)
                            m_answers[qid] = value
                            RefreshSelection()
                        end,

                        gui.Label{
                            fontSize = 26,
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            valign = "center",
                            interactable = false,
                            text = tostring(i),
                        },
                    }
                    m_buttons[#m_buttons + 1] = { panel = btn, value = value }
                    buttonPanels[#buttonPanels + 1] = btn
                end

                --the low/high captions anchor the scale under its endpoints;
                --the width matches the button row (N buttons at 64 + 2x5 margin).
                local scaleWidth = #labels * 74

                caption = gui.Label{
                    fontSize = 16,
                    width = 700,
                    height = 24,
                    halign = "center",
                    textAlignment = "center",
                    tmargin = 10,
                    text = "",
                }

                --optional free-text comments accompanying the rating, stored
                --alongside the numeric answer as <questionid>_comments.
                local commentsInput = gui.Input{
                    width = 700,
                    height = 90,
                    fontSize = 15,
                    multiline = true,
                    characterLimit = 2000,
                    textAlignment = "topleft",
                    halign = "center",
                    tmargin = 20,
                    placeholderText = "Comments (optional)...",
                    text = m_answers[qid .. "_comments"] or "",
                }
                m_commitPageInput = function()
                    if commentsInput.valid then
                        local text = commentsInput.text
                        if text == nil or text == "" then
                            m_answers[qid .. "_comments"] = nil
                        else
                            m_answers[qid .. "_comments"] = text
                        end
                    end
                end

                local result = gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    tmargin = 28,

                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",
                        children = buttonPanels,
                    },

                    gui.Panel{
                        width = scaleWidth,
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",
                        tmargin = 6,

                        gui.Label{
                            fontSize = 13,
                            color = "#999999",
                            width = "50%",
                            height = "auto",
                            halign = "left",
                            textAlignment = "left",
                            text = labels[1],
                        },

                        gui.Label{
                            fontSize = 13,
                            color = "#999999",
                            width = "50%",
                            height = "auto",
                            halign = "right",
                            textAlignment = "right",
                            text = labels[#labels],
                        },
                    },

                    caption,

                    commentsInput,
                }

                RefreshSelection()
                return result
            end

            --select and multiselect: one row per option, each with a radio or
            --checkbox indicator. select keeps exactly one row active;
            --multiselect toggles rows independently.
            local multi = (q.type == "multiselect")
            local m_rows = {}

            --multiselect questions may cap how many options can be chosen via
            --q.maxSelections; nil/0 means unlimited. When the cap is reached the
            --remaining options grey out and further presses are ignored.
            local maxSel = nil
            if multi then
                maxSel = tonumber(q.maxSelections)
                if maxSel ~= nil and maxSel <= 0 then
                    maxSel = nil
                end
            end

            --forward declared; created below only when a cap is in effect.
            local hintLabel = nil

            local function CountSelected()
                local a = m_answers[qid]
                if type(a) ~= "table" or type(a.selected) ~= "table" then
                    return 0
                end
                local n = 0
                for _,v in pairs(a.selected) do
                    if v then
                        n = n + 1
                    end
                end
                return n
            end

            local function IsOptionSelected(optid)
                if multi then
                    local a = m_answers[qid]
                    return type(a) == "table" and type(a.selected) == "table" and a.selected[optid] == true
                else
                    return m_answers[qid] == optid
                end
            end

            local function RefreshSelection()
                local atLimit = (maxSel ~= nil and CountSelected() >= maxSel)
                for _,entry in ipairs(m_rows) do
                    local selected = IsOptionSelected(entry.id)
                    entry.panel:SetClassTree("selected", selected)
                    --once the cap is reached, grey out the options that are not
                    --already chosen so it is clear they cannot be added without
                    --deselecting one first. Selected rows stay live to toggle off.
                    entry.panel:SetClass("disabledOption", atLimit and not selected)
                end
                if hintLabel ~= nil and hintLabel.valid then
                    hintLabel.text = string.format("Select up to %d", maxSel)
                end
            end

            local function ToggleOption(optid)
                if multi then
                    local a = m_answers[qid]
                    if type(a) ~= "table" then
                        a = {}
                        m_answers[qid] = a
                    end
                    if type(a.selected) ~= "table" then
                        a.selected = {}
                    end
                    if a.selected[optid] then
                        a.selected[optid] = nil
                    elseif maxSel == nil or CountSelected() < maxSel then
                        a.selected[optid] = true
                    end
                    --at the cap, presses on unselected options are ignored.
                else
                    if m_answers[qid] == optid then
                        m_answers[qid] = nil
                    else
                        m_answers[qid] = optid
                    end
                end
                RefreshSelection()
            end

            local indicatorClass = "surveyRadio"
            if multi then
                indicatorClass = "surveyCheckBox"
            end

            local rowPanels = {}
            for _,option in ipairs(q.options or {}) do
                local optid = option.id
                local row = gui.Panel{
                    classes = {"surveyOption"},
                    bgimage = true,
                    press = function(element)
                        ToggleOption(optid)
                    end,

                    gui.Panel{
                        classes = {indicatorClass},
                        bgimage = true,
                        interactable = false,

                        gui.Panel{
                            classes = {indicatorClass .. "Fill"},
                            bgimage = true,
                            interactable = false,
                        },
                    },

                    gui.Label{
                        fontSize = 16,
                        width = "100%-38",
                        height = "auto",
                        halign = "left",
                        lmargin = 12,
                        valign = "center",
                        interactable = false,
                        textWrap = true,
                        text = option.text or optid,
                    },
                }
                m_rows[#m_rows + 1] = { panel = row, id = optid }
                rowPanels[#rowPanels + 1] = row
            end

            local children = {}

            --when a cap is in effect, a small note above the options tells the
            --user how many they may pick.
            if maxSel ~= nil then
                hintLabel = gui.Label{
                    fontSize = 13,
                    color = "#999999",
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    bmargin = 10,
                    text = string.format("Select up to %d", maxSel),
                }
                children[#children + 1] = hintLabel
            end

            children[#children + 1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                halign = "center",
                children = rowPanels,
            }

            if q.allowOther then
                local otherText = ""
                local a = m_answers[qid]
                if multi then
                    if type(a) == "table" and type(a.other) == "string" then
                        otherText = a.other
                    end
                else
                    local other = m_answers[qid .. "_other"]
                    if type(other) == "string" then
                        otherText = other
                    end
                end

                local otherInput = gui.Input{
                    width = 700,
                    height = 30,
                    fontSize = 16,
                    halign = "center",
                    tmargin = 12,
                    placeholderText = "Other (tell us more)...",
                    text = otherText,
                }
                m_commitPageInput = function()
                    if not otherInput.valid then
                        return
                    end
                    local text = otherInput.text
                    if text == "" then
                        text = nil
                    end
                    if multi then
                        local answer = m_answers[qid]
                        if type(answer) ~= "table" then
                            answer = {}
                            m_answers[qid] = answer
                        end
                        answer.other = text
                    else
                        m_answers[qid .. "_other"] = text
                    end
                end

                children[#children + 1] = otherInput
            end

            local result = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                halign = "center",
                tmargin = 24,
                children = children,
            }

            RefreshSelection()
            return result
        end

        --A prompt too long for one line otherwise wraps wherever it runs out
        --of room, orphaning a couple of words on the second line. Break long
        --prompts explicitly at the word nearest the middle so the two lines
        --come out roughly even. Prompts short enough for one line (the 760px
        --label fits around 72 characters at this size) are left alone.
        local function BalancePromptText(text)
            if text == nil or #text <= 72 then
                return text
            end
            local mid = math.floor(#text / 2)
            local best = nil
            for i = 1, #text do
                if text:sub(i, i) == " " then
                    if best == nil or math.abs(i - mid) < math.abs(best - mid) then
                        best = i
                    end
                end
            end
            if best == nil then
                return text
            end
            return text:sub(1, best - 1) .. "\n" .. text:sub(best + 1)
        end

        local function BuildQuestionPage(index)
            local questions = m_survey.questions
            local q = questions[index]
            local nquestions = #questions
            local isLast = (index >= nquestions)

            local statusLabel = gui.Label{
                fontSize = 15,
                width = 700,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = true,
                bmargin = 8,
                text = "",
            }

            local function TryLeavePage(destination)
                CommitPageInput()
                if destination > index and q.required and not HasAnswer(q) then
                    statusLabel.text = "Please answer this question before continuing."
                    return
                end
                if destination < 1 then
                    m_page = "intro"
                else
                    m_page = destination
                end
                RefreshPage()
            end

            local function Submit()
                CommitPageInput()
                if q.required and not HasAnswer(q) then
                    statusLabel.text = "Please answer this question before continuing."
                    return
                end
                if m_submitting then
                    return
                end
                m_submitting = true
                statusLabel.text = "Submitting..."
                dmhub.SubmitSurveyResponse{
                    surveyId = m_survey.id,
                    answers = m_answers,
                    complete = function()
                        m_submitting = false
                        if contentPanel ~= nil and contentPanel.valid then
                            m_page = "finished"
                            RefreshPage()
                        end
                    end,
                    error = function(message)
                        m_submitting = false
                        if statusLabel.valid then
                            statusLabel.text = "Could not submit: " .. message
                        end
                    end,
                }
            end

            local nextText = "Next"
            if isLast then
                nextText = "Submit"
            end

            --the question block: prompt (plus an Optional note) and the answer
            --control, gathered into one column centered in the page.
            local questionChildren = {
                gui.Label{
                    fontSize = 22,
                    bold = true,
                    width = 760,
                    height = "auto",
                    halign = "center",
                    textAlignment = "center",
                    textWrap = true,
                    text = BalancePromptText(q.prompt or ""),
                },
            }

            if not q.required then
                questionChildren[#questionChildren + 1] = gui.Label{
                    fontSize = 13,
                    color = "#999999",
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    tmargin = 6,
                    text = "Optional",
                }
            end

            questionChildren[#questionChildren + 1] = BuildQuestionControl(q)

            return gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",

                --header pinned to the top: position in the survey plus a
                --progress bar that fills as the user advances. Offset down so
                --it clears the host dialog's "Survey" title (the dialogTitle
                --label, ~29px, is pinned to the same top edge) instead of
                --overlapping it.
                gui.Panel{
                    floating = true,
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    valign = "top",
                    tmargin = 44,

                    gui.Label{
                        fontSize = 13,
                        color = "#aaaaaa",
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        text = string.upper(string.format("Question %d of %d", index, nquestions)),
                    },

                    gui.Panel{
                        width = 700,
                        height = 6,
                        halign = "center",
                        tmargin = 10,
                        bgimage = true,
                        bgcolor = "#ffffff22",
                        cornerRadius = 3,

                        gui.Panel{
                            width = string.format("%d%%", math.floor(100 * index / nquestions)),
                            height = "100%",
                            halign = "left",
                            bgimage = true,
                            bgcolor = "#8899eeff",
                            cornerRadius = 3,
                        },
                    },
                },

                --the question itself, centered in the page.
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "center",
                    valign = "center",
                    children = questionChildren,
                },

                --navigation pinned to the bottom of the page, aligned with the
                --content column.
                gui.Panel{
                    floating = true,
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    valign = "bottom",

                    statusLabel,

                    gui.Panel{
                        width = 700,
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",

                        gui.Button{
                            classes = {"sizeM"},
                            text = "Back",
                            halign = "left",
                            click = function(element)
                                TryLeavePage(index - 1)
                            end,
                        },

                        gui.Button{
                            classes = {"sizeM"},
                            text = nextText,
                            halign = "right",
                            click = function(element)
                                if isLast then
                                    Submit()
                                else
                                    TryLeavePage(index + 1)
                                end
                            end,
                        },
                    },
                },
            }
        end

        contentPanel = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
        }

        RefreshPage = function()
            m_commitPageInput = nil
            local page
            if m_page == "loading" then
                page = BuildMessagePage("Loading...")
            elseif m_page == "error" then
                page = BuildMessagePage(m_errorMessage or "The survey could not be loaded. Please try again later.")
            elseif m_page == "intro" then
                page = BuildIntroPage()
            elseif m_page == "finished" then
                page = BuildFinishedPage()
            else
                page = BuildQuestionPage(m_page)
            end
            contentPanel.children = { page }
        end

        --fetch the survey definition and the user's previous response in
        --parallel; move off the loading page when both have arrived.
        local m_surveyLoaded = false
        local m_responseLoaded = false
        local function CheckLoadingComplete()
            if not (m_surveyLoaded and m_responseLoaded) then
                return
            end
            if contentPanel == nil or not contentPanel.valid then
                return
            end
            if m_survey == nil or type(m_survey.questions) ~= "table" or #m_survey.questions == 0 then
                m_page = "error"
                if m_errorMessage == nil then
                    m_errorMessage = "No survey is available right now. Please check back later."
                end
            else
                --prefill from the previous answers so the user can revise them.
                if m_response ~= nil and type(m_response.answers) == "table" then
                    for k,v in pairs(m_response.answers) do
                        m_answers[k] = v
                    end
                end
                m_page = "intro"
            end
            RefreshPage()
        end

        dmhub.GetSurvey(function(survey, err)
            m_surveyLoaded = true
            m_survey = survey
            if err ~= nil then
                m_errorMessage = "Could not load the survey: " .. err
            end
            CheckLoadingComplete()
        end)

        dmhub.GetSurveyResponse(function(response, err)
            --a response fetch error is not fatal; treat it as no previous response.
            m_responseLoaded = true
            m_response = response
            CheckLoadingComplete()
        end)

        local closeButton = gui.Button{
            classes = {"closeButton"},
            floating = true,
            halign = "right",
            valign = "top",
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                CloseDialog()
            end,
        }

        local bodyPanel = gui.Panel{
            width = 940,
            --tall enough for the longest question (features: 9 options + an
            --Other field) to sit centered without the option list colliding
            --with the floating Back/Next footer. This also drops the footer
            --into the room that was previously empty below it.
            height = 690,
            flow = "vertical",
            halign = "center",

            styles = {
                { selectors = {"surveyOption"}, width = 700, height = "auto", flow = "horizontal", bgcolor = "#00000066", border = 1, borderColor = "#888888", cornerRadius = 6, pad = 10, borderBox = true, halign = "center", vmargin = 3 },
                { selectors = {"surveyOption", "hover"}, bgcolor = "#2a2a2aaa", borderColor = "#cccccc" },
                { selectors = {"surveyOption", "selected"}, bgcolor = "#38386e99", borderColor = "#8899ee" },
                { selectors = {"surveyOption", "disabledOption"}, bgcolor = "#00000033", borderColor = "#555555", opacity = 0.45 },
                { selectors = {"surveyOption", "disabledOption", "hover"}, bgcolor = "#00000033", borderColor = "#555555" },
                { selectors = {"surveyCheckBox"}, width = 20, height = 20, valign = "center", bgcolor = "clear", border = 1, borderColor = "#aaaaaa", cornerRadius = 3 },
                { selectors = {"surveyRadio"}, width = 20, height = 20, valign = "center", bgcolor = "clear", border = 1, borderColor = "#aaaaaa", cornerRadius = 10 },
                { selectors = {"surveyCheckBoxFill"}, width = 12, height = 12, halign = "center", valign = "center", bgcolor = "#aabbff", cornerRadius = 2, opacity = 0 },
                { selectors = {"surveyRadioFill"}, width = 12, height = 12, halign = "center", valign = "center", bgcolor = "#aabbff", cornerRadius = 6, opacity = 0 },
                { selectors = {"surveyCheckBoxFill", "selected"}, opacity = 1 },
                { selectors = {"surveyRadioFill", "selected"}, opacity = 1 },
                { selectors = {"ratingButton"}, width = 64, height = 64, bgcolor = "#00000066", border = 1, borderColor = "#888888", cornerRadius = 6, hmargin = 5 },
                { selectors = {"ratingButton", "hover"}, bgcolor = "#2a2a2aaa", borderColor = "#cccccc" },
                { selectors = {"ratingButton", "selected"}, bgcolor = "#38386e99", borderColor = "#8899ee" },
            },

            contentPanel,
        }

        if dmhub.inGame and not dmhub.isLobbyGame then
            m_dialog = gamehud:ModalDialog{
                title = "Survey",
                buttons = {},
                bodyPanel,
            }
            m_dialog:AddChild(closeButton)
        else
            --On the titlescreen there is no gamehud modal stack, so host the
            --dialog as a floating framed panel on the titlescreen root, like
            --the bug report dialog above.
            local root = rawget(_G, "CodexTitlescreenRoot")
            if root ~= nil and root.valid then
                m_titlescreenModal = gui.Panel{
                    classes = {"framedPanel"},
                    floating = true,
                    width = 1024,
                    height = 768,
                    halign = "center",
                    valign = "center",
                    styles = ThemeEngine.GetStyles(),

                    gui.Panel{
                        width = "100%-32",
                        height = "100%-32",
                        flow = "vertical",
                        halign = "center",
                        valign = "top",

                        gui.Label{
                            classes = {"dialogTitle"},
                            text = "Survey",
                        },

                        bodyPanel,
                    },
                }
                root:AddChild(m_titlescreenModal)
                m_titlescreenModal:AddChild(closeButton)
            else
                --fallback: no titlescreen root available; use the gamehud modal.
                local gh = rawget(_G, "gamehud")
                if gh ~= nil then
                    m_dialog = gh:ModalDialog{
                        title = "Survey",
                        buttons = {},
                        bodyPanel,
                    }
                    m_dialog:AddChild(closeButton)
                end
            end
        end

        RefreshPage()
    end

    local menuBar = gui.Panel{
        id = "menuBarPanel",
        classes = {"titleBarSurface"},
        width = "100%",
        height = 32,
        floating = true,
        valign = "top",
        bgimage = true,
        flow = "horizontal",

        styles = {
            {
                selectors = {"mainmenuOnly", "ingame"},
                collapsed = 1,
            },
            {
                selectors = {"ingameOnly", "~ingame"},
                collapsed = 1,
            },
            --window-transition guard: hide the ENTIRE bar -- contents and
            --the root's flat strip alike -- so nothing of the title bar
            --renders while the window geometry is still settling (the strip
            --used to stay painted, and its 1-2 mis-laid-out frames read as
            --the bar flickering down into the window on restore).
            {
                selectors = {"windowTransition"},
                opacity = 0,
            },
        },

        data = { lastScreenDims = nil },

        create = function(element)
            g_menuBarPanel = element
            --boot: the merge convergence resizes the client several times in
            --the first moments; hold the bar contents hidden until settled.
            StartWindowTransitionGuard(12, 6, "boot")
        end,

        destroy = function(element)
            g_adventureDocumentsBar = nil
            --a dead bar must not leave stale hit regions behind: without the
            --clear, drags and clicks would keep hitting rects for a layout
            --that no longer exists until the bar is rebuilt.
            pcall(function() dmhub.SetTitleBarHitRegions(nil) end)
        end,

        thinkTime = 0.2,
        think = function(element)
            if (dmhub.inGame and not dmhub.isLobbyGame) ~= m_inGame then
                m_inGame = (dmhub.inGame and not dmhub.isLobbyGame)
                element:SetClassTree("ingame", m_inGame)
            end
            element:FireEventTree("calculateVisibility")

            --dead-man heartbeat: while merged, the engine's watchdog restores
            --the native caption if this bar stops running (a Lua error would
            --otherwise leave the window with no drag surface and no close
            --button). pcall: an engine with the chrome bridge but not the
            --watchdog yet must not error the bar's think.
            if MergedTitleBarActive() then
                pcall(function() dmhub.WindowChromeHeartbeat() end)

                --reactive guard: geometry changes we did not initiate (edge
                --snap, Win+arrow, external restores) also settle over several
                --frames; catch them on the think cadence and hide until stable.
                local d = dmhub.screenDimensions
                local prev = element.data.lastScreenDims
                if prev ~= nil and (d.x ~= prev.x or d.y ~= prev.y) and not g_transitionActive then
                    StartWindowTransitionGuard(nil, nil, "external resize")
                end
                element.data.lastScreenDims = {x = d.x, y = d.y}

                --keep the engine's native hit-test in sync with the bar's
                --real layout (rects are snapshotted engine-side at call time).
                UpdateTitleBarHitRegions()
            end

            --keep the bar inside its width, whatever the window is doing.
            --Runs in every mode, not just merged: an overfull flow loses its
            --right-hand cluster off the screen edge either way.
            BarFitApply()
        end,

        --Merged title bar: empty bar surface acts as the native caption.
        --This drag surface sits BEHIND every other child (first child =
        --bottom of the draw order), NOT as a press handler on the bar root:
        --press events bubble to ANCESTORS only, so a press on a click-only
        --child (the window buttons, the map cluster, ...) used to find the
        --root's press handler, start the native modal window-drag loop, and
        --have the mouse release swallowed by it -- the child's click never
        --fired. As a sibling underneath, the surface only receives presses
        --that land on genuinely empty bar space.
        --
        --Press starts a native window drag (snap-to-edge included); a second
        --press within the double-click window toggles maximize instead (the
        --engine has no doubleClick event, so it is hand-rolled).
        gui.Panel{
            --the id is load-bearing: UpdateTitleBarHitRegions skips this
            --child by id when reporting the bar's interactive exclusions
            --(the drag surface IS the draggable emptiness, not an exclusion).
            id = "titleBarDragSurface",
            floating = true,
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "clear",
            data = { lastBarPress = nil },
            press = function(element)
                if not MergedTitleBarActive() then
                    return
                end
                local now = dmhub.Time()
                if element.data.lastBarPress ~= nil and now - element.data.lastBarPress < 0.4 then
                    element.data.lastBarPress = nil
                    --hide the bar contents FIRST and resize a beat later, so
                    --the hide is on screen before the resize's mis-laid-out
                    --settle frames are.
                    StartWindowTransitionGuard(nil, nil, "double-press toggle")
                    dmhub.Schedule(0.05, function()
                        if not mod.unloaded then
                            dmhub.ToggleMaximizeWindow()
                        end
                    end)
                else
                    element.data.lastBarPress = now
                    --no native drag while maximized: dragging a maximized
                    --window makes Windows drag-restore it mid-loop, which
                    --Unity fights -- the window ends up unzoomed at a
                    --corrupt oversized rect (reproduced 2026-08-23:
                    --1936x1119 hanging off every screen edge). While
                    --maximized the bar restores via double-press or the
                    --restore button only.
                    if not dmhub.windowMaximized then
                        local before = dmhub.screenDimensions
                        dmhub.BeginWindowDrag()
                        --BeginWindowDrag blocks through the whole native drag.
                        --If it ended in an edge-snap the window was resized
                        --while the engine was frozen; guard the settle frames.
                        --The size check is deferred a beat because the engine
                        --only reports the new dimensions on the next frame.
                        dmhub.Schedule(0.1, function()
                            if mod.unloaded then
                                return
                            end
                            local after = dmhub.screenDimensions
                            if after.x ~= before.x or after.y ~= before.y then
                                StartWindowTransitionGuard(nil, nil, "drag snap resize")
                            end
                        end)
                    end
                end
            end,
        },

        CreateCodexMenuItem{
            name = "Codex",
            icon = "ui-icons/codex-logo.png",
            mainmenu = true,
            menuItems = function()
                local items = {
                    {
                        text = "Settings",
                        icon = "panels/hud/gear.png",
                        click = function()
                            dmhub.ShowPlayerSettings()
                        end,
                    },
                    --checkbox row: the check mirrors the "fullscreen"
                    --setting; clicking toggles it (replaces the old
                    --window-button fullscreen control).
                    {
                        text = "Fullscreen",
                        icon = "phosphor/arrows-out-simple-fill.png",
                        check = dmhub.GetSettingValue("fullscreen") == true,
                        click = function()
                            ToggleFullscreen()
                        end,
                    },
                }

                for _,storeItem in ipairs(GetStoreMenuItems()) do
                    items[#items+1] = storeItem
                end

                items[#items+1] = {
                    text = "Quit to Desktop",
                    icon = "game-icons/power-button.png",
                    click = function()
                        dmhub.QuitApplication()
                    end,
                }

                return items
            end,
        },

        CreateCodexMenuItem{
            name = "Codex",
            icon = "ui-icons/codex-logo.png",
            menuItems = function()
			    local items = WindowMenuItems("codex")
                local storeItems = GetStoreMenuItems()
                for i=#storeItems,1,-1 do
                    table.insert(items, 1, storeItems[i])
                end
                --same Fullscreen checkbox as the main-menu Codex menu.
                items[#items+1] = {
                    text = "Fullscreen",
                    icon = "phosphor/arrows-out-simple-fill.png",
                    check = dmhub.GetSettingValue("fullscreen") == true,
                    click = function()
                        ToggleFullscreen()
                    end,
                }
                return items
            end,
        },

        CreateCodexMenuItem{
            name = "Game",
            menuItems = function()
			    return WindowMenuItems("game")
            end,
        },

        CreateCodexMenuItem{
            name = "Tools",
            menuItems = function()
			    return WindowMenuItems("tools")
            end,
        },

        CreateCodexMenuItem{
            name = "Panels",
            menuItems = function()
                local dockablePanels = DockablePanel.GetMenuItems()
                --a dockable panel that declared `menu` is listed in that
                --title-bar menu (Codex/Game/Tools) instead of here --
                --listing it in both would just be clutter.
                dockablePanels = table.filter(dockablePanels, function(item) return item.text ~= "Development Tools" and item.menu == nil end)

                --folder submenus (Map Editing) are a different kind of row
                --than the panel toggles; giving them their own group makes
                --the context menu insert a divider before them.
                for _,p in ipairs(dockablePanels) do
                    if p.submenu ~= nil then
                        p.group = "folder"
                    end
                end

                local locked = dmhub.GetSettingValue("uilocked")
                local railMode = rawget(_G, "RailModeActive") ~= nil and RailModeActive()

                --rail mode has no Lock Panels row (see below), so it must not
                --honour the lock either -- a user who locked in dock mode and
                --then switched would find every row disabled with nothing left
                --to unlock it. Locking is a dock concept; the rail ignores it.
                if locked and not railMode then
                    for _,p in ipairs(gui.FlattenContextMenuItems(dockablePanels)) do
                        p.disabled = true
                    end
                end

                --In rail mode the rows keep their DEFAULT click: it routes
                --through the rail's open handler, which toggles the panel's
                --rail window and adds a rail shortcut on first open. A
                --shortcut already on the rail is never removed from here
                --(David, 2026-08-08) -- removal lives on the rail's own
                --context menu and rearrange trash. Only the check needs
                --overriding: the default tracks the DOCK instance, which is
                --slid away in rail mode, so light the row while the panel
                --is shown anywhere on the rail surface instead.
                if railMode then
                    for _,p in ipairs(gui.FlattenContextMenuItems(dockablePanels)) do
                        local panelName = p.text
                        if panelName ~= nil and p.submenu == nil then
                            p.check = PanelDocument.IsPanelShown(string.lower(panelName))
                        end
                    end
                end

                --Dock/lock rows are dock-mode only: in rail mode the docks are
                --slid off screen and the rail owns placement, so toggling a
                --dock or resetting the dock layout does nothing visible, and
                --the lock has no meaning (David, 2026-08-08).
                if not railMode then
                    --icons so the dock rows align with the panel rows below,
                    --which all carry check gutter + icon + text.
                    table.insert(dockablePanels, 1, {
                        text = "Left Dock",
                        icon = "phosphor/sidebar-simple.png",
                        check = not dmhub.GetSettingValue("leftdockoffscreen"),
                        group = "panel",

                        click = function()
                            dmhub.SetSettingValue("leftdockoffscreen", not dmhub.GetSettingValue("leftdockoffscreen"))
                        end,
                    })

                    table.insert(dockablePanels, 1, {
                        text = "Right Dock",
                        icon = "phosphor/sidebar-simple.png",
                        check = not dmhub.GetSettingValue("rightdockoffscreen"),
                        group = "panel",

                        click = function()
                            dmhub.SetSettingValue("rightdockoffscreen", not dmhub.GetSettingValue("rightdockoffscreen"))
                        end,
                    })

                    table.insert(dockablePanels, 1, {
                        text = "Reset Panels",
                        icon = "icons/icon_tool/icon_power.png",
                        group = "panel",

                        click = function()
                            dmhub.ResetSetting(GetDockablePanelsSetting())
                            InitDockablePanels()
                        end,
                    })

                    table.insert(dockablePanels, 1, {
                        text = cond(locked, "Unlock Panels", "Lock Panels"),
                        icon = cond(locked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png"),
                        check = locked,
                        group = "panel",
                        click = function()
                            dmhub.SetSettingValue("uilocked", not locked)
                        end,
                    })
                end

                --Workspace Views: the Panels menu is the ONLY switcher
                --UI (Lisa+David review 2026-07-19 removed the rail chip),
                --so it carries the full verb set: switch, save, save-as,
                --reset, manage. Only in rail mode (A6).
                if rawget(_G, "ViewsListForUser") ~= nil and railMode then
                    local active = ViewsActiveId()
                    local drift = ViewsIsDrifted()
                    local viewItems = {}
                    --no "View: " prefix on the rows now that the submenu row
                    --above them already says Views.
                    viewItems[#viewItems + 1] = {
                        text = "Custom",
                        check = active == nil,
                        group = "views",
                        click = function()
                            ViewsSwitchTo(nil)
                        end,
                    }
                    for _, v in ipairs(ViewsListForUser()) do
                        local vid = v.id
                        local text = v.name
                        if vid == active and drift then
                            text = text .. "  (unsaved changes)"
                        end
                        --a newer stock layout has shipped than the one
                        --this user's copy was built from; switching to
                        --it raises the take-it/keep-mine prompt.
                        if v.updated then
                            text = text .. "  (updated)"
                        end
                        viewItems[#viewItems + 1] = {
                            text = text,
                            check = vid == active,
                            group = "views",
                            click = function()
                                local skipped = ViewsSwitchTo(vid)
                                if rawget(_G, "ViewsPostApplyNotices") ~= nil then
                                    ViewsPostApplyNotices(vid, skipped)
                                end
                            end,
                        }
                    end
                    if active ~= nil and drift then
                        viewItems[#viewItems + 1] = {
                            text = "Save view",
                            group = "views",
                            click = function()
                                if ViewsSave() and rawget(_G, "ViewsToast") ~= nil then
                                    ViewsToast("View updated", function()
                                        ViewsUndoSave()
                                    end)
                                end
                            end,
                        }
                    end
                    viewItems[#viewItems + 1] = {
                        text = "Save as new view...",
                        group = "views",
                        click = function()
                            if rawget(_G, "ViewsSaveAsDialog") ~= nil then
                                ViewsSaveAsDialog()
                            end
                        end,
                    }
                    if active ~= nil then
                        viewItems[#viewItems + 1] = {
                            text = "Reset view to saved",
                            group = "views",
                            click = function()
                                ViewsResetToSaved()
                            end,
                        }
                    end
                    viewItems[#viewItems + 1] = {
                        text = "Manage views...",
                        group = "views",
                        click = function()
                            if rawget(_G, "ViewsManageDialog") ~= nil then
                                ViewsManageDialog()
                            end
                        end,
                    }
                    --one "Views" folder row rather than five-plus rows inline:
                    --the switcher is the least-used half of this menu and was
                    --pushing the panel toggles off the top.
                    table.insert(dockablePanels, 1, {
                        id = "FolderViews",
                        text = "Views",
                        group = "views",
                        submenu = viewItems,
                    })
                end

                return dockablePanels
            end,
        },

        m_adventureDocumentsBar,

        CreateCodexMenuItem{
            name = "Developer",
            calculateVisibility = function(element)
                --BarFitMenuDropped: same reason as Adventure Documents above
                --- this item owns its selfStyle.collapsed, so the narrow-bar
                --ladder cannot collapse it with a class and is honoured here.
                element.selfStyle.collapsed = cond(devmode() and not BarFitMenuDropped(element), 0, 1)
            end,
            menuItems = function()
                if not devmode() then
                    return {}
                end
                --pillage the "Development Tools" folders from our menu items.
                local menuItems = {}
                for i,items in ipairs({DockablePanel.GetMenuItems(), LaunchablePanel.GetMenuItems()}) do
                    for j,item in ipairs(items) do
                        if item.submenu and item.text == "Development Tools" then
                            for _,entry in ipairs(item.submenu) do
                                menuItems[#menuItems+1] = entry
                            end
                        end
                    end
                end
                return menuItems
            end,
        },

        CreateCodexMenuItem{
            name = "Feedback",
            mainmenu = "always",
            --marker dot beside the menu name when a developer has responded
            --to one of the user's tickets and they have not viewed it yet.
            newContentCheck = function()
                return g_ticketsState.hasUnseen
            end,
            menuItems = function()
                --opportunistically refresh ticket state whenever the menu is
                --opened, so the markers stay current.
                FetchTickets()

                --each entry captures the screenshot before the dialog appears,
                --then shows the dialog for that kind of feedback.
                local function FeedbackMenuItem(text, feedbackType)
                    return {
                        text = text,
                        click = function()
                            dmhub.BeginBugReport(function(report)
                                CreateBugReportDialog(report, feedbackType)
                            end)
                        end,
                    }
                end

                local items = {
                    FeedbackMenuItem("Bug Report", "bug"),
                    FeedbackMenuItem("Feature Request", "feature"),
                    FeedbackMenuItem("General Feedback", "feedback"),
                }

                --Your Tickets needs the C# ticket bridge; hide it on builds
                --that predate it.
                if TicketBridgeAvailable() then
                    items[#items+1] = {
                        text = "Your Tickets",
                        hasNewContent = function()
                            return g_ticketsState.hasUnseen
                        end,
                        click = function()
                            CreateTicketsDialog()
                        end,
                    }
                end

                items[#items+1] = {
                    text = "Survey",
                    click = function()
                        CreateSurveyDialog()
                    end,
                }

                return items
            end,
        },

        m_presentationBar,
        CreateStatusBar(),
        -- Glyph + search travel as ONE right-aligned cluster: the search box
        -- floats right and its width tracks the dock scale, so a sibling at a
        -- flow position drifts away from it as the box narrows. Wrapping both
        -- keeps the glyph pressed against the box's left edge at any scale
        -- (James field report, 2026-07-03).
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "100%",
            halign = "right",
            m_audioIndicator,
            m_searchBar,

            -- Window controls for the merged title bar: minimize /
            -- maximize-restore / close, drawn by us but driving the native
            -- window (the classic three cannot be kept system-drawn once
            -- the caption is stripped). Collapsed whenever the merged bar
            -- is off or unsupported; visibility rides the menuBar think's
            -- calculateVisibility broadcast.
            gui.Panel{
                classes = {"windowButtons", "collapsed"},
                flow = "horizontal",
                width = "auto",
                height = "100%",
                valign = "center",
                lmargin = 8,
                calculateVisibility = function(element)
                    element:SetClass("collapsed", not MergedTitleBarActive())
                end,

                --window-chrome/*: the Windows caption glyph shapes (codicon
                --geometry), served from StreamingAssets by the engine's
                --GetWindowChromeIcon. Each control is a full-bar-height
                --hover ZONE like the native caption buttons -- adjacent
                --42px strips whose whole surface fills on hover (faint
                --light for minimize/maximize, the Windows red for close;
                --styles live in titleBarStyleExtras below). Presses find no
                --handler here and no ancestor has one, so the drag surface
                --(a sibling underneath) never steals the click.
                --(Fullscreen is no longer a window control here -- it lives
                --in the Codex menus as a checkbox row, see ToggleFullscreen.)
                CreateWindowControl{
                    icon = "window-chrome/chrome-minimize.png",
                    click = function()
                        dmhub.MinimizeWindow()
                    end,
                },
                --assigned to the file-local so UpdateTitleBarHitRegions can
                --report it as the engine's HTMAXBUTTON zone; the click below
                --still fires on engines/modes without the stage-2 regions
                --(there the control is ordinary gui), while under the regions
                --the engine relays clicks via windowMaxButtonClick instead.
                (function()
                    m_maximizeControl = CreateWindowControl{
                        icon = "window-chrome/chrome-maximize.png",
                        --swap square (maximize) and overlapping-squares
                        --(restore) as the window state changes, polled on the
                        --same broadcast that drives the cluster's visibility.
                        --Reading the property on a pre-bridge engine would
                        --raise, so gate first.
                        calculateVisibility = function(element)
                            --while fullscreen the enforcer owns the window
                            --geometry, so maximize/restore is meaningless:
                            --gray the control out (style below) and let the
                            --click gate ignore presses.
                            local fullscreen = dmhub.GetSettingValue("fullscreen") == true
                            if fullscreen ~= element.data.fullscreenDisabled then
                                element.data.fullscreenDisabled = fullscreen
                                element:SetClass("windowControlDisabled", fullscreen)
                            end
                            if not WindowChromeBridgeAvailable() then
                                return
                            end
                            local maximized = dmhub.windowMaximized
                            if maximized ~= element.data.maximized then
                                element.data.maximized = maximized
                                element:FireEventTree("setIcon", cond(maximized, "window-chrome/chrome-restore.png", "window-chrome/chrome-maximize.png"))
                            end
                        end,
                        click = function()
                            --disabled while fullscreen; minimize/close stay live.
                            if dmhub.GetSettingValue("fullscreen") == true then
                                return
                            end
                            --hide the bar contents FIRST and resize a beat later,
                            --so the hide is on screen before the resize's
                            --mis-laid-out settle frames are.
                            StartWindowTransitionGuard(nil, nil, "maximize button")
                            dmhub.Schedule(0.05, function()
                                if not mod.unloaded then
                                    dmhub.ToggleMaximizeWindow()
                                end
                            end)
                        end,
                    }
                    return m_maximizeControl
                end)(),
                CreateWindowControl{
                    danger = true,
                    icon = "window-chrome/chrome-close.png",
                    click = function()
                        dmhub.CloseWindow()
                    end,
                },
            },
        },
    }

    local titleBarStyleExtras = {
        -- Narrow-bar fit: the collapse ladder's own way of taking an element
        -- out of the flow. Deliberately NOT the "collapsed" class -- several
        -- of these elements drive that themselves (the initiative host tracks
        -- the Show Status Bar setting, the menu items track dev mode and
        -- in-game state), and two writers on one class fight. A separate
        -- class means the ladder and the element's own visibility rules
        -- simply both get a veto.
        {
            selectors = {"barFitHidden"},
            collapsed = 1,
        },

        -- Title-bar bar surface paints flat @bg -- the same color the DWM
        -- caption used before the merged title bar replaced it
        -- (WindowTitleBarTheme.cs hardcodes that caption to the default
        -- scheme's bg #0A0A0B). Was the @barTrack gradient; flattened by
        -- request 2026-08-23 so the merged bar reads as window chrome.
        {
            selectors = {"titleBarSurface"},
            bgimage = true,
            bgcolor = "@bg",
        },

        -- Window controls (CreateWindowControl): full-height caption-button
        -- hover zones. Faint light fill for minimize/maximize, the Windows
        -- red for close; the close glyph flips to pure white over the red
        -- (@fg parchment would look dirty there). Danger rules come after
        -- the generic ones so they win the cascade.
        {
            selectors = {"windowControl"},
            bgcolor = "clear",
        },
        {
            selectors = {"windowControl", "hover"},
            bgcolor = "#ffffff1f",
        },
        {
            selectors = {"windowControl", "press"},
            bgcolor = "#ffffff33",
        },
        {
            selectors = {"windowControlDanger", "hover"},
            bgcolor = "#c42b1c",
        },
        {
            selectors = {"windowControlDanger", "press"},
            bgcolor = "#b3271a",
        },
        {
            selectors = {"windowControlIcon"},
            --neutral light grey rather than the theme's parchment @fg:
            --window chrome should read as OS furniture, not app content
            --(Venla 2026-08-23). Close still flips to white over the red.
            bgcolor = "#d4d4d4",
        },
        {
            selectors = {"windowControlIconDanger", "parent:hover"},
            bgcolor = "#ffffff",
        },
        -- Disabled state (maximize while fullscreen): no hover/press fill
        -- and a faded glyph. After the hover/press rules so it wins the
        -- cascade at equal specificity.
        {
            selectors = {"windowControl", "windowControlDisabled"},
            bgcolor = "clear",
        },
        {
            selectors = {"windowControlIcon", "parent:windowControlDisabled"},
            opacity = 0.35,
        },

        -- Title-bar search field visibility. (Its LOOK is the canonical
        -- searchInput rule in DefaultStyles now -- this surface's old
        -- thin-frame variant was promoted to the app-wide default,
        -- Control Zoo decision 2026-08-20.)
        {
            selectors = {"searchInput", "~ingame", "~searchoverride"},
            hidden = 1,
        },

        -- Audio indicator glyph (H-BAR): same in-game-only visibility as the
        -- search box, driven by the same "ingame" class SetClassTree'd onto
        -- an ancestor (menuBar's think, below). No searchoverride exemption
        -- -- the glyph has no main-menu equivalent to preserve.
        {
            selectors = {"audioIndicator", "~ingame"},
            hidden = 1,
        },

        -- Grouped global-search results popup: the search bar's own
        -- focused fill, stretched downward (Venla 2026-08-21) -- no
        -- frame, no separate panel color, square top corners so it
        -- continues the bar's silhouette; only the bottom keeps the
        -- pill rounding. x1=TL, y1=TR, x2=BR, y2=BL.
        {
            selectors = {"searchResultsPanel"},
            --vpad only, NO horizontal padding: row highlights span the
            --popup's full width (Venla 2026-08-21), so rows reach the
            --edges and carry their text inset as their own lpad/rpad.
            vpad = 6,
            maxHeight = 600,
            borderBox = true,
            bgimage = true,
            bgcolor = "#2E2E33",
            cornerRadius = {x1 = 0, y1 = 0, x2 = 7, y2 = 7},
        },
        {
            -- While the search's results popup is actually up (class
            -- toggled by SyncPopupOpenState), the field's bottom
            -- corners square off so the popup below continues the
            -- shape without corner notches. Keyed to the popup, NOT
            -- focus: a focused empty bar has no popup and must stay a
            -- plain closed pill.
            selectors = {"searchInput", "searchPopupOpen"},
            cornerRadius = {x1 = 7, y1 = 7, x2 = 0, y2 = 0},
        },
        {
            -- The connector strip a focused search bar drops below
            -- itself to meet the popup (the engine positions popup
            -- roots a few px lower and ignores y offsets on them, so
            -- the FIELD bridges the gap). Same fill as bar + popup, so
            -- the overlap is invisible and the three read as one shape.
            selectors = {"searchPopupBridge"},
            bgimage = true,
            bgcolor = "#2E2E33",
        },
        {
            selectors = {"searchGroupHeading"},
            --hmargin 12, matching the old 6 popup pad + 6 margin now
            --that the popup itself has no horizontal padding.
            width = "100%-24",
            height = "auto",
            halign = "left",
            color = "@accent",
            fontSize = 13,
            tmargin = 6,
            bmargin = 2,
            hmargin = 12,
        },
        {
            selectors = {"searchResultRow"},
            --full width so the hover/keyboard highlight runs edge to
            --edge of the popup; the text inset lives in the row's OWN
            --padding instead of margins. rpad 28, not symmetric: the
            --engine scrollbar overlays the popup's right edge, and the
            --right-aligned type labels must stay clear of it (Venla
            --2026-08-21).
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "center",
            bgimage = true,
            bgcolor = "clear",
            vpad = 4,
            lpad = 16,
            rpad = 28,
            borderBox = true,
        },
        --row highlights lift ABOVE the popup's #2E2E33 ground (@bgAlt
        --is darker than it now and read as dark stripes).
        {
            selectors = {"searchResultRow", "hover"},
            bgcolor = "#3B3B42",
        },
        {
            selectors = {"searchResultRow", "searchfocus"},
            bgcolor = "#3B3B42",
        },
        {
            selectors = {"searchSeeAll", "searchfocus"},
            bgimage = true,
            bgcolor = "#3B3B42",
        },
        {
            -- Empty-state line ("No Search Results" / "Searching...")
            -- shown alone inside the searchResultsPanel frame.
            selectors = {"searchEmptyState"},
            width = "100%",
            height = "auto",
            textAlignment = "center",
            color = "@fgMuted",
            fontSize = 13,
            vmargin = 6,
        },
        {
            -- 20px to line up with the placed-token portraits (CreateTokenImage
            -- at 20) so the name column starts at the same x on every row.
            selectors = {"searchResultIcon"},
            width = 20,
            height = 20,
            halign = "left",
            valign = "center",
            rmargin = 8,
            bgcolor = "white",
        },
        {
            -- Map-note pin: a small dark disc with the bubble's number/glyph,
            -- echoing the on-map info-bubble marker. Same 20px box as the other
            -- leading icons so the name column lines up.
            selectors = {"searchResultBubble"},
            width = 20,
            height = 20,
            halign = "left",
            valign = "center",
            rmargin = 8,
            bgimage = "panels/square.png",
            bgcolor = "black",
            cornerRadius = "50% height",
            borderWidth = 1,
            borderColor = "@fg",
            color = "@fg",
            fontSize = 11,
            textAlignment = "center",
        },
        {
            selectors = {"searchResultName"},
            width = "auto",
            --hard cap, not "available": rows flow horizontally with an
            --auto-width name block, so an uncapped long name pushes the
            --right-hand type/chips column past the row edge and it
            --clips mid-word (Venla 2026-08-21). Fixed cap, not an
            --available-based width -- see the Control Zoo mock's note
            --on the hover-restyle flicker loop. BOTH columns are
            --capped (the right one overflowed too on long monster
            --names as type labels); capped labels wrap instead of
            --clipping. 150 + the right column's 95 + icon and margins
            --fills the current popup width.
            maxWidth = 150,
            height = "auto",
            halign = "left",
            valign = "center",
            color = "@fg",
            fontSize = 16,
        },
        {
            selectors = {"searchResultType"},
            width = "auto",
            --the right column's cap (see searchResultName): long type
            --labels -- e.g. a monster name on an ability row -- wrap
            --within it instead of running off the row edge.
            maxWidth = 95,
            height = "auto",
            halign = "right",
            valign = "center",
            color = "@fgMuted",
            fontSize = 12,
            lmargin = 8,
        },
        {
            selectors = {"searchResultSub"},
            width = "auto",
            --same cap rationale as searchResultName: the sub line also
            --widens the name block and pushes the right column out.
            maxWidth = 150,
            height = "auto",
            halign = "left",
            color = "@fgMuted",
            fontSize = 12,
        },
        {
            -- The primary-action hint line under the name: a muted lead-in
            -- arrow + text describing what pressing the row does.
            selectors = {"searchActionLine"},
            tmargin = 4,
            valign = "center",
        },
        {
            -- Right column: the type chip plus any secondary action buttons,
            -- stacked. lmargin keeps it off the name when the row is narrow.
            selectors = {"searchResultRight"},
            lmargin = 8,
        },
        {
            -- Small right-pointing lead-in arrow, tinted to match the muted
            -- hint text so it reads as "this happens on click".
            selectors = {"searchHintArrow"},
            width = 11,
            height = 11,
            valign = "center",
            rmargin = 5,
            bgimage = "icons/icon_arrow/icon_arrow_28.png",
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"searchHintText"},
            width = "auto",
            --cap like searchResultName (minus the lead-in arrow), so a
            --long action hint cannot widen the name block either.
            maxWidth = 134,
            height = "auto",
            valign = "center",
            color = "@fgMuted",
            fontSize = 12,
        },
        {
            -- Secondary action: small outlined button in the right column,
            -- right-aligned under the type chip; tmargin separates it from the
            -- chip above (and from sibling buttons when there is more than one).
            selectors = {"searchResultChip"},
            width = "auto",
            --same right-column cap as searchResultType.
            maxWidth = 95,
            height = "auto",
            halign = "right",
            valign = "center",
            color = "@fg",
            fontSize = 11,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            borderWidth = 1,
            borderColor = "@fgMuted",
            cornerRadius = 4,
            pad = 3,
            hpad = 8,
            borderBox = true,
            tmargin = 5,
        },
        {
            selectors = {"searchResultChip", "hover"},
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            color = "@accentHover",
        },
        {
            selectors = {"searchSeeAll"},
            --full width with row-matching pads, so its searchfocus
            --highlight also runs edge to edge (see searchResultRow).
            width = "100%",
            height = "auto",
            halign = "left",
            color = "@accentHover",
            fontSize = 13,
            vpad = 4,
            lpad = 16,
            rpad = 28,
            borderBox = true,
        },
    }

    -- Expose the REAL global-search bar to dev surfaces (the Control
    -- Zoo hosts it for styling work on the results popup). The popup
    -- inherits its searchResult* rules from the HOST's cascade
    -- (popupsInheritStyles), so a foreign host must merge
    -- TopBar.SearchBarStyles() into its own sheet -- and must
    -- SetClassTree("ingame", true) on its wrapper, or the sheet's
    -- {searchInput, ~ingame} rule hides the bar.
    TopBar.CreateSearchBar = CreateSearchBar
    TopBar.SearchBarStyles = function()
        return titleBarStyleExtras
    end

    -- Tree-wide invalidation pulse for theme repaints. Reassigning .styles
    -- updates the rule array but doesn't mark descendants dirty, so without
    -- a forced re-cascade the bar keeps painting the previous scheme until
    -- something (e.g. hover) churns a pseudo-class. Toggling a no-op class
    -- across the subtree marks every descendant dirty. The class itself is
    -- not referenced by any rule -- only the flip matters.
    local themeRefreshTick = false

	local topBarPanel = gui.Panel{
        id = "topBar",
		width = dmhub.titleBarContainer.width,
		height = dmhub.titleBarContainer.height,
		flow = "horizontal",

        screenResized = function (element)
            element.selfStyle.width = dmhub.titleBarContainer.width
            element.selfStyle.height = dmhub.titleBarContainer.height
        end,

        thinkTime = 0.5,
        think = function(element)
            if element.selfStyle.width ~= dmhub.titleBarContainer.width then
                element.selfStyle.width = dmhub.titleBarContainer.width
            end

            if element.selfStyle.height ~= dmhub.titleBarContainer.height then
                element.selfStyle.height = dmhub.titleBarContainer.height
            end
        end,

        styles = ThemeEngine.MergeStyles(titleBarStyleExtras),

		--dmControlsPanel,
		--layersPanel,
        menuBar,
	}

    -- Force a re-cascade once the engine signals the game is fully loaded
    -- (and therefore every mod's color schemes are registered). The cascade
    -- computed at construction time may resolve before custom-scheme mods
    -- have finished registering, leaving the bar painted with the wrong
    -- scheme until something else invalidates the tree.
    dmhub.RegisterEventHandler("EnterGame", function()
        if topBarPanel and topBarPanel.valid then
            topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
            themeRefreshTick = not themeRefreshTick
            topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
        end
    end)

    -- Subscribe to theme changes so the bar repaints live when the user
    -- switches scheme via Settings instead of waiting for the next reload.
    ThemeEngine.OnThemeChanged(mod, function()
        if topBarPanel and topBarPanel.valid then
            topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
            themeRefreshTick = not themeRefreshTick
            topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
        end
    end)

	return topBarPanel
end

dmhub.titleBarContainer.sheet = CreateTopBar()

--HTMAXBUTTON relay: while the stage-2 hit regions are registered, the
--maximize control is a native non-client zone -- the gui never receives
--mouse events over it -- so the engine relays its interaction here. The
--events are argless; state is read from dmhub.windowMaxButtonState. Both
--handlers survive bar rebuilds (they resolve m_maximizeControl at fire
--time) and go quiet after a mod reload via the mod.unloaded guard.
dmhub.RegisterEventHandler("windowMaxButtonState", function()
    if mod.unloaded then
        return
    end
    local control = m_maximizeControl
    if control == nil or not control.valid then
        return
    end
    --disabled while fullscreen: no hover/press feedback on the dead control.
    if dmhub.GetSettingValue("fullscreen") == true then
        control:SetClass("hover", false)
        control:SetClass("press", false)
        return
    end
    local state = "none"
    pcall(function() state = dmhub.windowMaxButtonState end)
    control:SetClass("hover", state == "hover" or state == "pressed")
    control:SetClass("press", state == "pressed")
end)

dmhub.RegisterEventHandler("windowMaxButtonClick", function()
    if mod.unloaded then
        return
    end
    --disabled while fullscreen. Swallow the click (return true) so the
    --engine's no-listener fallback doesn't toggle the window itself.
    if dmhub.GetSettingValue("fullscreen") == true then
        return true
    end
    --same flow as the control's gui click handler: hide the bar contents
    --FIRST and resize a beat later, so the hide is on screen before the
    --resize's mis-laid-out settle frames are.
    StartWindowTransitionGuard(nil, nil, "maximize button")
    dmhub.Schedule(0.05, function()
        if not mod.unloaded then
            dmhub.ToggleMaximizeWindow()
        end
    end)

    --Swallow the event. The engine's relay treats a NON-swallowed click as
    --"no Lua listener" and toggles the window itself so the button can never
    --go dead (LuaInterfaceWindowChrome, the ConsumeMaxButtonClick relay) --
    --and FireGlobalEvent reports "swallowed" only when a handler returns
    --true, not merely when one is registered. Since the toggle above is
    --SCHEDULED rather than immediate, returning nothing let the engine
    --fallback maximize right away and this handler restore 0.05s later: one
    --click maximized the window and then animated it straight back down
    --(observed 2026-08-23). The early mod.unloaded return deliberately stays
    --falsy so the fallback still works once this handler is dead.
    return true
end)