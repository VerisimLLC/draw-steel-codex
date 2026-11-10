local mod = dmhub.GetModLoading()

--Hero sheet: the redesigned sheet for Hero tokens. It is a window on the
--table (the documents layer that map, scene and journal windows share), not
--the engine's full-screen sheet harness, so map input keeps working while it
--is open. Every route that opens a sheet goes through token:ShowSheet into
--the classic sheet's harness, which hands Heroes here. Every other token
--keeps the classic character sheet.
--
--This file routes and builds the content; the window itself is
--HeroSheetWindow.lua, and the tabs live in their own HeroSheet*.lua files.

--- @class HeroSheetState
--- @field tokenid string The open Hero's token id.
--- @field tab string The open tab: one of HeroSheet.tabs' ids, or a tab another mod registered.
--- @field viewOnly boolean Party Member Controls is View: show everything, never write or roll.
--- @field pane nil|string Character tab pane to land on ("Features" for the deep link).
--- @field featuresFilter nil|string Text the Features list opens filtered by.
--- @field editing nil|boolean Edit mode is on: the Character tab frames what can be edited.
--- @field returnTab nil|string The tab the Builder was opened from: Back to the sheet returns to it.
--- @field levelUp nil|boolean The Builder tab shows Level up, not the Builder.
--- @field guest nil|boolean A Hero served with no sheet open (HeroSheet.SetGuest).
--- @field levelUpManual nil|boolean Level up opened on the manual path: the next Level's page.
--- @field richstatusid any The "Viewing Character Sheet" presence entry (the engine stub types Push and Pop differently).

HeroSheet = rawget(_G, "HeroSheet") or {}

--The tabs other mods build (Builder, Inventory, Downtime, Appearance), looked
--up when a tab is first shown, so this file does not depend on their mods
--loading first.
--- @param name string
--- @return any
local function TabModule(name)
    return rawget(_G, name)
end

--The tabs the Hero sheet draws itself, in strip order. Their ids are
--the classic sheet's registered tab ids, so token:ShowSheet(tabid) callers
--keep working.
--Registered tabs with any other id (other mods') are hosted as they are.
HeroSheet.tabs = {
    { id = "CharacterSheet", text = "Character" },
    { id = "Inventory", text = "Inventory" },
    { id = "Downtime", text = "Downtime" },
    { id = "Appearance", text = "Appearance" },
    { id = "Builder", text = "Builder" },
}

local g_ownTabs = {}
for _,tab in ipairs(HeroSheet.tabs) do
    g_ownTabs[tab.id] = tab
end

--Tab ids callers pass that are not tabs of their own.
local g_tabAliases = {
    --the Features sub-tab of the classic sheet's Character tab.
    Features = "CharacterSheet",
}

--The open window and its state live in a global so a Lua reload (F4) can
--find the previous generation's window, remove it and reopen the same Hero.
--- builderAt is where the next Builder opening lands (OpenBuilderAt), used once;
--- levelUpNext makes the next Builder opening Level up (OpenLevelUp), used once:
--- "manual" for the next Level's page.
--- warmTab readies a tab ahead of a click (the content sets it; WarmTab).
--- lendAppearance / returnAppearance lend the Appearance surface to the
--- Builder's Appearance step and take it back (the content sets them).
--- guest is the Hero served with no sheet open (SetGuest).
--- @type {window: nil|Panel, state: nil|HeroSheetState, guest: nil|HeroSheetState, contentTabs: nil|string, builderAt: nil|{step: string, section: nil|string}, levelUpNext: nil|boolean|string, warmTab: nil|fun(tabid: string), lendAppearance: nil|(fun(): nil|HeroAppearanceView), returnAppearance: nil|fun()}
g_heroSheetLive = rawget(_G, "g_heroSheetLive") or { window = nil, state = nil }
local g_live = g_heroSheetLive

--- True while the Builder's Review shows the sheet's Character tab:
--- the open tab is still the Builder, but the sheet draws as on Character.
--- @return boolean
local function Reviewing()
    local window = g_live.window
    return window ~= nil and window.valid and window.data.review ~= nil
end

--The window lives on the documents layer. In the lobby (title screen) that
--layer has no table under it, so the window fills it.
--- @return boolean
local function HasLayer()
    --GameHud.instance is false while the HUD rebuilds after a reload (F4).
    local hud = GameHud ~= nil and GameHud.instance or nil
    return dmhub.inGame and type(hud) == "table"
        and hud.documentsPanel ~= nil and hud.documentsPanel.valid
end

--- True when this token's sheet opens in the Hero sheet window.
--- @param token nil|CharacterToken
--- @return boolean
function HeroSheet.Routes(token)
    if token == nil then
        return false
    end
    local isHero = false
    pcall(function() isHero = token.valid and token.properties ~= nil and token.properties:IsHero() end)
    if not isHero then
        return false
    end
    --a game mode with its own Hero sheet (EotW) keeps it: callers that get
    --false open the classic route, which hands the token to that mode.
    local hud = rawget(_G, "GameHud")
    if hud ~= nil and hud.CustomInterfaceOwnsSheet ~= nil and hud.CustomInterfaceOwnsSheet(token) then
        return false
    end
    return true
end

--- True while the window shows this Hero (any Hero when charid is nil),
--- minimized or not.
--- @param charid nil|string
--- @return boolean
function HeroSheet.IsShowing(charid)
    local state = g_live.state
    if state == nil or g_live.window == nil or not g_live.window.valid then
        return false
    end
    return charid == nil or state.tokenid == charid
end

--- The open Hero's state, or nil when the window is closed. While no sheet
--- is open, a guest Hero (SetGuest) is served instead.
--- @return nil|HeroSheetState
function HeroSheet.State()
    return g_live.state or g_live.guest
end

--- Serve a Hero to the sheet's parts with no sheet open: the EotW
--- town's Builder lends the Appearance surface, whose writes and repaints
--- find their Hero here. nil ends it. The town never has a sheet open.
--- @param tokenid nil|string
function HeroSheet.SetGuest(tokenid)
    if tokenid == nil then
        g_live.guest = nil
        return
    end
    g_live.guest = {tokenid = tokenid, viewOnly = false, tab = "Builder", guest = true}
end

--- The pointer rests on a tab's button: ready that tab ahead of the click
--- (what changed while it was hidden is drawn now, not on the click).
--- @param tabid string
function HeroSheet.WarmTab(tabid)
    local warm = g_live.warmTab
    if g_live.state == nil or g_live.state.tab == tabid or warm == nil then
        return
    end
    warm(tabid)
end

--The open Hero's token, looked up by id each time: a reconnect can replace
--the token's properties, so nothing holds on to a token or creature. By
--character id, so a Hero on another map is found too.
--- @return nil|CharacterToken
function HeroSheet.Token()
    local state = HeroSheet.State()
    if state == nil then
        return nil
    end
    return dmhub.GetCharacterById(state.tokenid) or dmhub.GetTokenById(state.tokenid)
end

--- Edit mode is on and the Hero can be written (view only never edits).
--- @return boolean
function HeroSheet.Editing()
    local state = HeroSheet.State()
    return state ~= nil and state.editing == true and HeroSheetWrite.CanWrite()
end

--- Call after a save that changed the live Hero: redraws now rather than
--- waiting for the server to send the change back.
function HeroSheet.Saved()
    local token = HeroSheet.Token()
    if token ~= nil and token.properties ~= nil then
        token.properties:Invalidate()
    end
    HeroSheetRefresh.Changed()
end

--Registered tabs from other mods that a Hero shows. Their panel() builds
--inside this window and gets the same events the classic sheet sends.
--- @param creature creature
--- @return table[]
local function ForeignTabs(creature)
    local result = {}
    for _,tab in ipairs(CharSheet.TabOptions or {}) do
        if g_ownTabs[tab.id] == nil and tab.panel ~= nil then
            local visible = true
            if tab.visible ~= nil then
                local ok, isVisible = pcall(tab.visible, creature)
                visible = ok and isVisible ~= false
            end
            if visible then
                result[#result+1] = tab
            end
        end
    end
    return result
end

--- @param tabid nil|string
--- @return string
local function ResolveTab(tabid)
    if tabid == nil or tabid == "" then
        return "CharacterSheet"
    end
    return g_tabAliases[tabid] or tabid
end

--- @param tabid string
--- @return string
local function TabText(tabid)
    local own = g_ownTabs[tabid]
    if own ~= nil then
        return own.text
    end
    for _,tab in ipairs(CharSheet.TabOptions or {}) do
        if tab.id == tabid then
            return tab.text or tabid
        end
    end
    return tabid
end

--Title bar text: the Hero's name and the tab, or "View only" in place of
--the tab for a view-only Hero. The separator is a middle dot.
--- @return string
local function TitleText()
    local token = HeroSheet.Token()
    local state = g_live.state
    local name = "Hero"
    if token ~= nil and type(token.name) == "string" and token.name ~= "" then
        name = token.name
    end
    if state ~= nil and state.viewOnly then
        return name .. " \u{00B7} View only"
    end
    return name .. " \u{00B7} " .. TabText(state ~= nil and state.tab or "CharacterSheet")
end

--- The window's layout tier now ("wide", "medium" or "narrow"); "wide" when
--- the window is not built.
--- @return string
function HeroSheet.Tier()
    local window = g_live.window
    if window ~= nil and window.valid and window.data.tier ~= nil then
        return window.data.tier
    end
    return "wide"
end

--- @return boolean
local function IsFrontmost()
    return HeroSheetWindow.IsFrontmost(g_live.window)
end

--- The Builder's frame showing: Level up's or the Builder's own.
--- @param window Panel
--- @return nil|Panel
local function ActiveBuilder(window)
    local state = g_live.state
    local panel = cond(state ~= nil and state.levelUp == true, window.data.levelUpPanel, window.data.builderPanel)
    if panel ~= nil and panel.valid then
        return panel
    end
    return nil
end

--The Builder shows in the window in place of the sheet: it is built the
--first time it opens and kept with the window. While it shows, the sheet's
--own blocks stop redrawing. Level up is the Builder's frame for the Levels
--waiting, a panel of its own.
--- @param window Panel
--- @param on boolean
local function ShowBuilder(window, on)
    local state = g_live.state
    if on and state ~= nil and state.levelUp == true then
        local panel = window.data.levelUpPanel
        if panel == nil or not panel.valid then
            panel = TabModule("HeroBuilder").Create{
                levelUp = true,
                back = function()
                    HeroSheet.BackToSheet()
                end,
            }
            window.data.levelUpPanel = panel
        end
        HeroSheetRefresh.PauseSheet(true)
        window.data.setBuilder(panel)
        panel:FireEventTree("heroBuilderOpen", {manual = state.levelUpManual == true})
        return
    end
    if on then
        local panel = window.data.builderPanel
        if panel == nil or not panel.valid then
            panel = TabModule("HeroBuilder").Create{
                back = function()
                    HeroSheet.BackToSheet()
                end,
                --Review: the sheet's Character tab, live, between the
                --Builder's stepper and footer; nil goes back to the steps.
                review = function(review)
                    local liveWindow = g_live.window
                    --the Builder also paints while the sheet shows (its blocks
                    --keep up); only a Builder on screen may show Review. Level
                    --up is a Builder too, kept beside this one: a pick there
                    --repaints this hidden one, which must not show its Review.
                    local live = g_live.state
                    if liveWindow == nil or not liveWindow.valid or not liveWindow.data.builder or (live ~= nil and live.levelUp) then
                        return
                    end
                    local entering = review ~= nil and liveWindow.data.review == nil
                    if review == nil and liveWindow.data.review ~= nil then
                        HeroSheetRefresh.PauseSheet(true)
                    end
                    liveWindow.data.setReview(review)
                    --the sheet catches up and shows its Character tab (a
                    --"Builder" tab event while reviewing shows it too).
                    if entering then
                        HeroSheetRefresh.PauseSheet(false)
                        liveWindow:FireEventTree("heroSheetTab", "CharacterSheet")
                        HeroSheetRefresh.CatchUpShown()
                    end
                end,
            }
            window.data.builderPanel = panel
        end
        HeroSheetRefresh.PauseSheet(true)
        window.data.setBuilder(panel)
        --a deep link's step and choice, or nil for the first step with
        --something left.
        local at = g_live.builderAt
        g_live.builderAt = nil
        panel:FireEventTree("heroBuilderOpen", at)
    else
        --the Builder's Appearance step gives the surface back first.
        HeroSheet.ReturnAppearance()
        if window.data.builder then
            window.data.setBuilder(nil)
        end
        --also after a close or a new window, which leave the Builder without this.
        HeroSheetRefresh.PauseSheet(false)
    end
end

--- @param tabid string
local function SelectTab(tabid)
    local window = g_live.window
    local state = g_live.state
    if state == nil or window == nil or not window.valid then
        return
    end
    --a view-only Hero has no Builder (its button is hidden too).
    if tabid == "Builder" and state.viewOnly then
        tabid = "CharacterSheet"
    end
    if tabid == "Builder" and state.tab ~= "Builder" then
        state.returnTab = state.tab
    end
    --Level up opens through HeroSheet.OpenLevelUp; any other way in is the Builder.
    state.levelUp = tabid == "Builder" and g_live.levelUpNext ~= nil
    state.levelUpManual = state.levelUp and g_live.levelUpNext == "manual"
    g_live.levelUpNext = nil
    state.tab = tabid
    state.editing = false
    ShowBuilder(window, tabid == "Builder")
    window:FireEventTree("heroSheetTab", tabid)
    window:FireEventTree("heroSheetEdit", false)
    window:FireEventTree("heroSheetTitle")
    --what changed while the tab's parts were hidden, drawn before the frame shows them.
    HeroSheetRefresh.CatchUpShown()
end

--- Open the Builder on a step, scrolled to one of its choices: the deep
--- links, such as the kit card's Change in Builder ("class", "kit").
--- With a token, opens that Hero's sheet on it (the Respite's kit link).
--- @param stepid string a Builder step id
--- @param sectionKey nil|string the choice's section on that step
--- @param token nil|CharacterToken the Hero to open; nil: the open sheet's
--- @return boolean false when the Hero sheet does not take the Hero (the classic sheet is set)
function HeroSheet.OpenBuilderAt(stepid, sectionKey, token)
    if token ~= nil then
        g_live.builderAt = {step = stepid, section = sectionKey}
        local opened = HeroSheet.Open(token, "Builder")
        --a sheet that did not open on the Builder must not land there later.
        g_live.builderAt = nil
        return opened
    end
    if g_live.state == nil then
        return false
    end
    g_live.builderAt = {step = stepid, section = sectionKey}
    SelectTab("Builder")
    return true
end

--- Open Level up: a page for each Level waiting, when one is
--- (HeroBuild.main.LevelsWaiting); otherwise the Builder, on its first step
--- with something left. The card's Finish Level N opens it. manual: the
--- card's Level up, which with nothing waiting opens the next Level's page,
--- the Level rising only on its Finish.
--- @param manual nil|boolean
function HeroSheet.OpenLevelUp(manual)
    local token = HeroSheet.Token()
    if g_live.state == nil or token == nil then
        return
    end
    local waiting = {}
    pcall(function() waiting = HeroBuild.main.LevelsWaiting(token) end)
    g_live.levelUpNext = nil
    if #waiting > 0 then
        g_live.levelUpNext = true
    elseif manual == true and HeroBuild.main.hero.ManualLevel(token.properties --[[@as character]]) ~= nil then
        g_live.levelUpNext = "manual"
    end
    SelectTab("Builder")
end

--- Leave the Builder for the sheet, on the tab it was opened from.
function HeroSheet.BackToSheet()
    local state = g_live.state
    if state == nil or state.tab ~= "Builder" then
        return
    end
    local tab = state.returnTab
    if tab == nil or tab == "Builder" then
        tab = "CharacterSheet"
    end
    SelectTab(tab)
end

--Edit mode: on for the Character tab until Done, a tab switch or a
--Hero switch.
--- @param editing boolean
local function SetEditing(editing)
    local state = g_live.state
    local window = g_live.window
    if state == nil or window == nil or not window.valid then
        return
    end
    if state.viewOnly or state.tab ~= "CharacterSheet" then
        editing = false
    end
    state.editing = editing
    window:FireEventTree("heroSheetEdit", editing)
end

--The card column's width in each tier (sheet units). Narrow has no column:
--the card becomes a banner under the top bar.
local CARD_COLUMN_WIDTH = {wide = 384, medium = 320}
local COLUMN_GAP = 12
local CONTENT_PAD = 12
--the gap between the top bar and the tab's body.
local BODY_GAP = 8

--- The Appearance tab as the sheet lends it out (HeroSheetAppearance builds it).
--- @class HeroAppearanceView
--- @field column Panel
--- @field body Panel
--- @field state {subtab: string} the open sub-tab
--- @field show fun(id: string) opens a sub-tab ("look", "description", "effects", "summons")
--- @field editName fun() starts typing the name on the card (the Builder footer's Name link)
--- @field revealArt fun(): nil|Panel opens Look, scrolls 1 Choose the art into view and returns its plate to flash

--- The Appearance surface for the Builder's Appearance step: the
--- sheet's own, built if needed, lent until ReturnAppearance. Nil while
--- the sheet's content is not built.
--- @return nil|HeroAppearanceView
function HeroSheet.LendAppearance()
    if g_live.lendAppearance == nil then
        return nil
    end
    return g_live.lendAppearance()
end

--- The Builder is done with the Appearance surface: the sheet takes it back.
function HeroSheet.ReturnAppearance()
    if g_live.returnAppearance ~= nil then
        g_live.returnAppearance()
    end
end

--- The card column's width in a tier, in sheet units (nil for Narrow).
--- @param tier string
--- @return nil|number
function HeroSheet.CardColumnWidth(tier)
    return CARD_COLUMN_WIDTH[tier]
end

--The tabs the top bar offers: the window's own, then tabs other mods
--registered for this Hero.
--- @param creature nil|creature
--- @return {id: string, text: string}[]
local function VisibleTabs(creature)
    local tabs = {}
    for _,tab in ipairs(HeroSheet.tabs) do
        tabs[#tabs+1] = tab
    end
    if creature ~= nil then
        for _,tab in ipairs(ForeignTabs(creature)) do
            tabs[#tabs+1] = {id = tab.id, text = tab.text or tab.id}
        end
    end
    return tabs
end

--The tab ids a Hero's sheet shows, as one string: a Hero switch keeps the
--built content only when the new Hero shows the same tabs.
--- @param creature nil|creature
--- @return string
local function TabsKey(creature)
    local ids = {}
    for _,tab in ipairs(VisibleTabs(creature)) do
        ids[#ids+1] = tab.id
    end
    return table.concat(ids, "|")
end

--The window's content: the card column on the left (on every tab), and on
--the right the top bar over the open tab. A tab another mod registered is
--built in the body the first time it is shown.
--- @return Panel
local function BuildContent()
    local token = HeroSheet.Token()
    local creature = token ~= nil and token.properties or nil
    local tabs = VisibleTabs(creature)
    g_live.contentTabs = TabsKey(creature)

    --a registered tab's panel, built the first time it is shown.
    --- @type table<string, Panel>
    local foreignPanels = {}
    --the Inventory tab, built the first time it is shown, and the
    --last layout it missed while it did not exist yet.
    --- @type nil|Panel
    local inventory = nil
    --the Downtime tab, built the first time it is shown, as the Inventory.
    --- @type nil|Panel
    local downtime = nil
    --the Appearance tab: its body here and its art column in the card
    --column, built together the first time the tab shows (EnsureAppearance,
    --set once the card column exists).
    --- @type nil|HeroAppearanceView
    local appearance = nil
    --- Where the Appearance tab's art column shows (set up with the column).
    --- @type nil|fun(tabid: string)
    local SyncAppearanceHost
    --- @type fun()
    local EnsureAppearance
    --true while the Builder's Appearance step shows the surface: the
    --sheet's tab and tier handlers leave its panels alone.
    local lent = false
    --- @type nil|{width: number, height: number}
    local lastLayout = nil

    --the Character tab: the stats band over the lists. At Narrow the band
    --moves into the lists' Stats pane and the kit card and Treasures into
    --their Gear pane; the characteristics stay under the
    --banner. The panes scroll once their content is taller than they are.
    local stats, statsTiles = HeroSheetStats.Create()
    local statsInner = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        tmargin = 8,
    }
    local statsPane = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%-36",
        flow = "vertical",
        statsInner,
    }
    local gearInner = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        tmargin = 8,
    }
    local gearPane = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%-36",
        flow = "vertical",
        gearInner,
    }
    local lists = HeroSheetLists.Create{statsPane = statsPane, gearPane = gearPane}
    --where the band sits at Wide and Medium, and the banner at Narrow.
    local statsSlot = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        stats,
    }
    local bannerSlot = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    --Narrow's characteristics, on a plate of their own: they sit between the
    --banner and the lists, where the frosted window would show through.
    local charsSlot = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 8,
        pad = 6,
        borderBox = true,
        statsTiles,
    }
    --- Narrow shows the characteristics on the Character tab only, as the
    --- band shows them on it at Wide and Medium.
    --- @param tierNow string
    local function SyncChars(tierNow)
        local state = HeroSheet.State()
        local onCharacter = state == nil or state.tab == "CharacterSheet" or Reviewing()
        charsSlot:SetClass("collapsed", not (tierNow == "narrow" and onCharacter))
    end

    --a fixed 100-unit panel that tells how big a sheet unit is on screen.
    local unitProbe = gui.Panel{
        floating = true,
        interactable = false,
        width = 1,
        height = 100,
    }

    local body
    --- @type Panel
    local topBar
    --- @type Panel
    local right
    --- @type Panel
    local row
    --- @type Panel
    local neededBar

    --The tab's sizes, worked out here: the row under the needed bar, the
    --tab's body under the top bar, the lists under the band. Never "100%
    --available": the engine re-lays out such a panel's whole subtree every
    --frame. The lists keep a minimum height; a window too short for both
    --scrolls the tab. Sizes are measured two drawn frames after layout; a
    --change that moves what is measured fits again.
    local tabFitGen = 0
    --- @type table<string, any>
    local fitted = {}
    local function FitTab()
        tabFitGen = tabFitGen + 1
        local gen = tabFitGen
        HeroSheetWindow.AfterLayout(function()
            if gen ~= tabFitGen or not body.valid then
                return
            end
            local perUnit = unitProbe.renderedHeight / 100
            if perUnit <= 0 then
                return
            end
            local changed = false
            --- @param panel Panel
            --- @param key string
            --- @param value any
            local function Set(panel, key, value)
                if fitted[key] ~= value then
                    fitted[key] = value
                    panel.selfStyle.height = value
                    changed = true
                end
            end
            local need = 0
            if not neededBar:HasClass("collapsed") then
                need = math.ceil(neededBar.renderedHeight / perUnit)
            end
            Set(row, "row", cond(need > 0, string.format("100%%-%d", need), "100%"))
            local bar = math.ceil(topBar.renderedHeight / perUnit) + BODY_GAP
            Set(body, "body", string.format("100%%-%d", bar))
            --the tab shown is under its floor: the whole tab scrolls.
            local short = false
            if not lists:HasClass("collapsed") then
                --what sits over the lists: the band, or at Narrow the banner
                --and the characteristics.
                local over = stats.renderedHeight / perUnit
                if HeroSheet.Tier() == "narrow" then
                    over = (bannerSlot.renderedHeight + charsSlot.renderedHeight) / perUnit
                    --Narrow's panes scroll once their content is taller.
                    for _, pair in ipairs({{statsPane, statsInner}, {gearPane, gearInner}}) do
                        local pane, inner = pair[1], pair[2]
                        if not pane:HasClass("collapsed") and pane.renderedHeight > 0 and not pane.vscroll
                            and inner.renderedHeight > pane.renderedHeight + 0.5 then
                            pane.vscroll = true
                        end
                    end
                end
                local room = right.renderedHeight / perUnit - bar - over - HeroSheetLists.TOP_MARGIN
                short = room < HeroSheetLists.MIN_HEIGHT
                Set(lists, "lists", cond(short, HeroSheetLists.MIN_HEIGHT, math.floor(room) - 1))
            end
            --the Inventory and Downtime take what Narrow's banner leaves, or
            --the whole body; never under the lists' floor, which a large Font
            --Size can reach at Narrow.
            --(not the Appearance body while the Builder has it: it fills the Builder's slot.)
            for key, panel in pairs({inventory = inventory, downtime = downtime, appearance = appearance ~= nil and not lent and appearance.body or nil}) do
                if panel.valid and not panel:HasClass("collapsed") then
                    local over = 0
                    if HeroSheet.Tier() == "narrow" then
                        over = math.ceil(bannerSlot.renderedHeight / perUnit) + 8
                    end
                    local room = right.renderedHeight / perUnit - bar - over
                    if room < HeroSheetLists.MIN_HEIGHT then
                        short = true
                        Set(panel, key, HeroSheetLists.MIN_HEIGHT)
                    else
                        Set(panel, key, cond(over > 0, string.format("100%%-%d", over), "100%"))
                    end
                end
            end
            --off on a tab that fits: a scroll would hold its content low.
            if (body.vscroll == true) ~= short then
                body.vscroll = short
            end
            --what was measured moves with what was set: measure again.
            if changed then
                FitTab()
            end
        end)
    end
    HeroSheetRefresh.afterRedraw = FitTab

    --the card column's parts that show on one tab only (Downtime's project
    --rolls), set when the column is built below.
    --- @type table<string, Panel>
    local cardTabParts = {}
    --- The panels a tab shows, whose blocks went stale while it was hidden.
    --- @param tabid string
    --- @return Panel[]
    local function TabRoots(tabid)
        local roots = {}
        if tabid == "CharacterSheet" then
            roots = {stats, charsSlot, lists}
        elseif tabid == "Inventory" and inventory ~= nil and inventory.valid then
            roots = {inventory}
        elseif tabid == "Downtime" and downtime ~= nil and downtime.valid then
            roots = {downtime}
        elseif tabid == "Appearance" and appearance ~= nil and appearance.body.valid then
            roots = {appearance.body, appearance.column}
        end
        local part = cardTabParts[tabid]
        if part ~= nil and part.valid then
            roots[#roots+1] = part
        end
        return roots
    end
    --the pointer rests on a tab's button: its blocks catch up ahead of the click.
    g_live.warmTab = function(tabid)
        HeroSheetRefresh.CatchUp(TabRoots(tabid))
    end

    body = gui.Panel{
        width = "100%",
        height = "100%-80",
        flow = "vertical",
        tmargin = BODY_GAP,
        heroSheetLayout = function(element, width, height)
            lastLayout = {width = width, height = height}
            FitTab()
        end,
        heroSheetEdit = function(element)
            FitTab()
        end,
        heroSheetTier = function(element)
            FitTab()
        end,
        --another Hero in the kept content: other mods' tabs show the new Hero.
        heroSheetHero = function(element, newToken)
            for _,tabPanel in pairs(foreignPanels) do
                if tabPanel.valid then
                    local info = { token = newToken }
                    tabPanel:FireEventTree("refreshToken", info)
                    tabPanel:FireEventTree("refreshAppearance", info)
                end
            end
            FitTab()
        end,
        heroSheetTab = function(element, tabid)
            --the Builder's Review shows the Character tab under it.
            if tabid == "Builder" and Reviewing() then
                tabid = "CharacterSheet"
            end
            stats:SetClass("collapsed", tabid ~= "CharacterSheet")
            charsSlot:SetClass("collapsed", tabid ~= "CharacterSheet" or HeroSheet.Tier() ~= "narrow")
            if tabid == "Inventory" then
                --cleaned as the classic sheet's inventory grid cleans on open,
                --then built once.
                TabModule("HeroSheetInventory").Sanitize(HeroSheet.Token())
                if inventory == nil or not inventory.valid then
                    inventory = TabModule("HeroSheetInventory").Create()
                    element:AddChild(inventory)
                    if lastLayout ~= nil then
                        inventory:FireEventTree("heroSheetLayout", lastLayout.width, lastLayout.height)
                    end
                end
            end
            if inventory ~= nil and inventory.valid then
                inventory:SetClass("collapsed", tabid ~= "Inventory")
            end
            if tabid == "Downtime" and (downtime == nil or not downtime.valid) then
                downtime = TabModule("HeroSheetDowntime").Create()
                element:AddChild(downtime)
                if lastLayout ~= nil then
                    downtime:FireEventTree("heroSheetLayout", lastLayout.width, lastLayout.height)
                end
            end
            if downtime ~= nil and downtime.valid then
                downtime:SetClass("collapsed", tabid ~= "Downtime")
            end
            if tabid == "Appearance" then
                EnsureAppearance()
            end
            if appearance ~= nil and appearance.body.valid and not lent then
                appearance.body:SetClass("collapsed", tabid ~= "Appearance")
            end
            if SyncAppearanceHost ~= nil then
                SyncAppearanceHost(tabid)
            end
            lists:SetClass("collapsed", tabid ~= "CharacterSheet")
            FitTab()
            for id,tabPanel in pairs(foreignPanels) do
                if tabPanel.valid then
                    tabPanel:SetClass("collapsed", id ~= tabid)
                    tabPanel:FireEventTree("charsheetActivate", id == tabid)
                end
            end
            if g_ownTabs[tabid] ~= nil or foreignPanels[tabid] ~= nil then
                return
            end
            for _,tab in ipairs(CharSheet.TabOptions or {}) do
                if tab.id == tabid and tab.panel ~= nil then
                    local ok, tabPanel = pcall(tab.panel)
                    if ok and tabPanel ~= nil then
                        foreignPanels[tabid] = tabPanel
                        element:AddChild(tabPanel)
                        local info = { token = HeroSheet.Token() }
                        tabPanel:FireEventTree("refreshToken", info)
                        tabPanel:FireEventTree("refreshAppearance", info)
                        tabPanel:FireEventTree("charsheetActivate", true)
                    else
                        dmhub.Error(string.format("Hero sheet: tab %s failed to build: %s", tabid, tostring(tabPanel)))
                    end
                end
            end
        end,
        unitProbe,
        bannerSlot,
        charsSlot,
        statsSlot,
        lists,
    }

    topBar = HeroSheetTopBar.Create{
        tabs = function()
            return tabs
        end,
        selectTab = function(tabid)
            SelectTab(tabid)
        end,
        setEditing = SetEditing,
    }

    --the needed bar shows while the sheet covers more than half the table:
    --maximized, or a restored window over half the layer. It runs the
    --window's full width under the title bar. Showing or hiding it changes the card column's height, so the Treasures
    --block refits (refit is FitTreasures, set below).
    local refit = nil
    neededBar = HeroSheetTopBar.NeededBar{
        shownChanged = function()
            if refit ~= nil then
                refit()
            end
            FitTab()
        end,
        covers = function()
            local window = g_live.window
            if window == nil or not window.valid then
                return false
            end
            local data = window.data
            if data.minimized or data.closed or data.poppedOut then
                return false
            end
            if data.maximized or data.fullscreen then
                return true
            end
            local layer = GameHud.instance ~= nil and GameHud.instance.documentsPanel or nil
            if layer == nil or not layer.valid or layer.renderedWidth <= 0 or layer.renderedHeight <= 0 then
                return false
            end
            return (window.renderedWidth * window.renderedHeight) / (layer.renderedWidth * layer.renderedHeight) > 0.5
        end,
        canMinimize = function()
            local window = g_live.window
            return window ~= nil and window.valid and not window.data.fullscreen
                and not window.data.poppedOut and Tabletop.IsActive()
        end,
        minimize = function()
            local window = g_live.window
            if window ~= nil and window.valid then
                window.data.minimize()
            end
        end,
    }

    --the right column takes what the card column leaves (set by tier below).
    right = gui.Panel{
        width = string.format("100%%-%d", CARD_COLUMN_WIDTH.wide + COLUMN_GAP),
        height = "100%",
        flow = "vertical",
        topBar,
        body,
    }

    local tier = nil
    local left
    local card
    local kit
    local treasures
    --the party stash: the Inventory tab's block in Treasures' place.
    local stash
    --Project rolls: the Downtime tab's block under the card.
    local rolls

    --The Treasures block fills the column under the card and the kit, never
    --shorter than its floor; a shorter column scrolls instead. Sizes are
    --measured after layout, so this runs once layout is done.
    local treasuresFitGen = 0
    local function FitTreasures()
        treasuresFitGen = treasuresFitGen + 1
        local gen = treasuresFitGen
        HeroSheetWindow.AfterLayout(function()
            if gen ~= treasuresFitGen or left == nil or not left.valid or not treasures.valid then
                return
            end
            --at Narrow, Treasures sits in the Gear pane, which scrolls: its floor
            --and a little more.
            if tier == "narrow" then
                local height = HeroSheetCard.TREASURES_MIN_HEIGHT + 160
                if treasures.selfStyle.height ~= height then
                    treasures.selfStyle.height = height
                end
                return
            end
            local cardUnits = HeroSheetCard.CardHeight(tier or "wide")
            if cardUnits == nil or card.renderedHeight <= 0 then
                return
            end
            --screen pixels per sheet unit, from the card's known height.
            local perUnit = card.renderedHeight / cardUnits
            --less the kit's and the block's top margins (12 each), and 12
            --more: the column's scroll content measures that much taller than
            --its children and margins, so without it the column would scroll
            --a little even when everything fits.
            local room = left.renderedHeight / perUnit - cardUnits - kit.renderedHeight / perUnit - 36
            local height = math.max(HeroSheetCard.TREASURES_MIN_HEIGHT, math.floor(room))
            if treasures.selfStyle.height ~= height then
                treasures.selfStyle.height = height
            end
            --the stash takes the same room on the Inventory tab.
            if stash ~= nil and stash.valid and stash.selfStyle.height ~= height then
                stash.selfStyle.height = height
            end
            --Project rolls too: the Downtime tab hides the kit, whose room it takes.
            if rolls ~= nil and rolls.valid then
                local rollsHeight = height
                if kit:HasClass("collapsed") then
                    rollsHeight = math.max(HeroSheetCard.TREASURES_MIN_HEIGHT, math.floor(room + kit.renderedHeight / perUnit + 12))
                end
                if rolls.selfStyle.height ~= rollsHeight then
                    rolls.selfStyle.height = rollsHeight
                end
            end
        end)
    end

    --what the card column's parts open.
    --- @type HeroSheetCardArgs
    local cardArgs = {
        --Finish Level N and the level line: Level up, or the Builder when
        --only a 1st-Level choice is left; the Level up button: the next
        --Level's page (manual).
        levelUp = function(manual)
            HeroSheet.OpenLevelUp(manual)
        end,
        --the kit card's Change in Builder opens on the kit itself.
        changeKit = function()
            HeroSheet.OpenBuilderAt("class", "kit")
        end,
        --the Titles window (HeroSheetTitles.lua).
        openTitles = (rawget(_G, "HeroSheetWindows") or {}).OpenTitles,
        openAppearance = function()
            SelectTab("Appearance")
        end,
        openInventory = function()
            SelectTab("Inventory")
        end,
        columnChanged = FitTreasures,
    }

    card = HeroSheetCard.Create(cardArgs)
    kit = HeroSheetCard.Kit(cardArgs)
    treasures = HeroSheetCard.Treasures(cardArgs)
    stash = TabModule("HeroSheetInventoryActions").StashPanel()
    rolls = TabModule("HeroSheetDowntime").RollsPanel()
    cardTabParts.Downtime = rolls

    --the card column: the Hero's card on every tab. The card scrolls with
    --the column when the window is short.
    left = gui.Panel{
        width = CARD_COLUMN_WIDTH.wide,
        height = "100%",
        flow = "vertical",
        vscroll = true,
        rmargin = COLUMN_GAP,
        --the Inventory tab lists the treasures itself (its column is the
        --card, the kit and the stash). Downtime's column is the card and
        --Project rolls.
        heroSheetTab = function(element, tabid)
            --Appearance's column is its big art and what sits under it:
            --the card, kit and Treasures step aside, and the column never scrolls.
            local onAppearance = tabid == "Appearance" and tier ~= "narrow"
            treasures:SetClass("collapsed", tabid == "Inventory" or tabid == "Downtime" or onAppearance)
            kit:SetClass("collapsed", (tabid == "Downtime" and tier ~= "narrow") or onAppearance)
            if SyncAppearanceHost ~= nil then
                SyncAppearanceHost(tabid)
            end
            if (element.vscroll == true) == onAppearance then
                element.vscroll = not onAppearance
            end
            FitTreasures()
        end,
        card,
        kit,
        treasures,
        stash,
        rolls,
    }

    refit = FitTreasures

    --The card, or the Appearance tab's art column in its place: the column
    --at Wide and Medium, and at Narrow the Appearance tab's banner in the
    --card's slot; other tabs keep the card. Run by the
    --card column and by the body, since a collapsed column misses tab events.
    SyncAppearanceHost = function(tabid)
        local onAppearance = tabid == "Appearance" and tier ~= "narrow"
        local artBanner = tabid == "Appearance" and tier == "narrow"
        card:SetClass("collapsed", onAppearance or artBanner)
        if appearance == nil or not appearance.column.valid or lent then
            return
        end
        local home = cond(artBanner, bannerSlot, left)
        if appearance.column.parent ~= home then
            appearance.column:Unparent()
            home:AddChild(appearance.column)
        end
        appearance.column:SetClass("collapsed", not (onAppearance or artBanner))
        appearance.column:FireEventTree("heroAppearanceBanner", artBanner)
    end

    EnsureAppearance = function()
        if appearance ~= nil and appearance.body.valid then
            return
        end
        appearance = TabModule("HeroSheetAppearance").Create()
        body:AddChild(appearance.body)
        left:AddChild(appearance.column)
        if lastLayout ~= nil then
            appearance.body:FireEventTree("heroSheetLayout", lastLayout.width, lastLayout.height)
            appearance.column:FireEventTree("heroSheetLayout", lastLayout.width, lastLayout.height)
        end
        if tier ~= nil then
            appearance.body:FireEventTree("heroSheetTier", tier)
            appearance.column:FireEventTree("heroSheetTier", tier)
        end
        local state = HeroSheet.State()
        if state ~= nil and SyncAppearanceHost ~= nil then
            SyncAppearanceHost(state.tab)
        end
    end

    --The Builder's Appearance step borrows the surface: built here if
    --it is not yet, then the Builder places its panels in its own frame.
    g_live.lendAppearance = function()
        EnsureAppearance()
        if appearance == nil or not appearance.body.valid then
            return nil
        end
        if not lent then
            appearance.body.selfStyle.height = "100%"
        end
        lent = true
        HeroSheetRefresh.Lend({appearance.body, appearance.column})
        return appearance
    end
    --...and gives it back: the body to the tab's place, the column to the
    --card column (or Narrow's banner), laid out for the sheet again.
    g_live.returnAppearance = function()
        if not lent then
            return
        end
        lent = false
        HeroSheetRefresh.Lend(nil)
        if appearance == nil or not appearance.body.valid then
            return
        end
        local state = HeroSheet.State()
        local tabid = state ~= nil and state.tab or "CharacterSheet"
        if appearance.body.parent ~= body then
            appearance.body:Unparent()
            body:AddChild(appearance.body)
        end
        --FitTab sizes it again: a percent height reads back from selfStyle
        --as the number 1, so a saved copy would come back 1 unit tall.
        fitted.appearance = nil
        FitTab()
        appearance.body:SetClass("collapsed", tabid ~= "Appearance")
        local host = {builder = false, shown = false}
        appearance.column:FireEventTree("heroAppearanceHost", host)
        appearance.body:FireEventTree("heroAppearanceHost", host)
        SyncAppearanceHost(tabid)
        if lastLayout ~= nil then
            appearance.body:FireEventTree("heroSheetLayout", lastLayout.width, lastLayout.height)
            appearance.column:FireEventTree("heroSheetLayout", lastLayout.width, lastLayout.height)
        end
        if tier ~= nil then
            appearance.body:FireEventTree("heroSheetTier", tier)
            appearance.column:FireEventTree("heroSheetTier", tier)
        end
    end

    --the card column and the right column under the needed bar (its height
    --is set by FitTab).
    --Moves the card, the kit card, Treasures and the band to where a tier has
    --them: the same panels, never second copies. A panel leaves its
    --parent before it joins another (otherwise it is listed in both).
    --- @param newTier string
    local function Place(newTier)
        --- @param panel Panel
        --- @param into Panel
        local function Move(panel, into)
            if panel.parent ~= into then
                panel:Unparent()
                into:AddChild(panel)
            end
        end
        if newTier == "narrow" then
            Move(card, bannerSlot)
            Move(kit, gearInner)
            Move(treasures, gearInner)
            Move(stats, statsInner)
        else
            if card.parent ~= left then
                card:Unparent()
                kit:Unparent()
                treasures:Unparent()
                --the stash stays in the column at Narrow (hidden there), so it
                --comes out and goes back last to keep the column's order.
                stash:Unparent()
                rolls:Unparent()
                left:AddChild(card)
                left:AddChild(kit)
                left:AddChild(treasures)
                left:AddChild(stash)
                left:AddChild(rolls)
            end
            Move(stats, statsSlot)
        end
        bannerSlot:SetClass("collapsed", newTier ~= "narrow")
        SyncChars(newTier)
        --the column's parts on the Appearance tab follow the tier too.
        local state = HeroSheet.State()
        if state ~= nil then
            left:FireEvent("heroSheetTab", state.tab)
        end
    end

    row = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        pad = CONTENT_PAD,
        borderBox = true,
        heroSheetTier = function(element, newTier)
            tier = newTier
            Place(newTier)
            local width = CARD_COLUMN_WIDTH[newTier]
            left:SetClass("collapsed", width == nil)
            if width ~= nil then
                left.selfStyle.width = width
            end
            --the right column takes what the card column leaves.
            right.selfStyle.width = cond(width ~= nil, string.format("100%%-%d", (width or 0) + COLUMN_GAP), "100%")
        end,
        --the top bar arranges itself by the width of the column it sits in.
        heroSheetLayout = function(element, width, height)
            local column = width - 2 * CONTENT_PAD
            local cardWidth = CARD_COLUMN_WIDTH[tier or "wide"]
            if cardWidth ~= nil then
                column = column - cardWidth - COLUMN_GAP
            end
            topBar:FireEvent("heroSheetBarWidth", column)
            FitTreasures()
        end,
        left,
        right,
    }

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        neededBar,
        row,
        HeroSheetRefresh.Monitor(token),
        --the title bar names the Hero: a rename, here or on another
        --client, retitles the window.
        HeroSheetRefresh.Block({
            floating = true,
            interactable = false,
            width = 1,
            height = 1,
        }, {
            name = "window title",
            signature = function(token)
                return tostring(token.name)
            end,
            refresh = function(panel, token)
                local window = g_live.window
                if window ~= nil and window.valid then
                    window:FireEventTree("heroSheetTitle")
                end
            end,
        }),
    }
end

--Removes the window without ending the session's sheet (pop-in, Hero
--switch, reload): no characterSheetClosed, no presence change. A card that
--holds the minimized window lets it go.
local function DropWindow()
    --typed changes still waiting save before their window goes.
    HeroSheetWrite.Flush()
    local window = g_live.window
    g_live.window = nil
    if window ~= nil and window.valid then
        window.data.dropping = true
        if window.data.minimized and window.data.charid ~= nil then
            Tabletop.RestoreFromCard(window.data.charid, nil, function() end)
        end
        window:DestroySelf()
    end
end

--Ends the open state and hides the window, kept built so the next open is
--quick (a popped-out one goes: its OS window closes). Fires
--characterSheetClosed, as the harness does when it closes: the lobby's Edit
--Hero and the new character tracking wait on it.
function HeroSheet.Close()
    local state = g_live.state
    --save what is pending and check nothing went unsent, while the Hero is
    --still the open one.
    HeroSheetWrite.OnLeave()
    g_live.state = nil
    --a closed Builder reopens as the sheet (HeroSheetWindow's Hide).
    HeroSheetRefresh.PauseSheet(false)
    local window = g_live.window
    if window ~= nil and window.valid and not window.data.poppedOut then
        window.data.hide()
    else
        --hide makes the window sound itself; a popped-out sheet just goes.
        if state ~= nil then
            audio.FireSoundEvent("UI.WindowClose")
        end
        DropWindow()
    end
    if state ~= nil then
        dmhub.PopUserRichStatus(state.richstatusid)
        dmhub.FireGlobalEvent("characterSheetClosed")
    end
end

--Popped out, "Return to the app" brings the sheet back on the table, on the
--same Hero and tab.
local function PopIn()
    local state = g_live.state
    if state == nil then
        return
    end
    DropWindow()
    local token = HeroSheet.Token()
    if token == nil then
        HeroSheet.Close()
        return
    end
    --the OS window closes with the panel; build the new one next frame.
    dmhub.Schedule(0.1, function()
        if mod.unloaded or g_live.state ~= state then
            return
        end
        HeroSheet.Open(token, state.tab)
    end)
end

--- @param charid string
--- @param options nil|{maximized: nil|boolean}
--- @return Panel
local function BuildWindow(charid, options)
    local window
    window = HeroSheetWindow.Create{
        charid = charid,
        content = BuildContent(),
        title = TitleText,
        --the Builder's title bar says how its picks save.
        subtitle = function()
            local state = g_live.state
            if state ~= nil and state.tab == "Builder" then
                return "Changes save as you go."
            end
            return ""
        end,
        --Esc in the Builder goes back to the sheet; it closes the sheet itself.
        onEscape = function()
            local state = g_live.state
            if state ~= nil and state.tab == "Builder" then
                --the Builder may use it first (to clear a selected skill row).
                local panel = window ~= nil and window.valid and ActiveBuilder(window) or nil
                if panel ~= nil and panel.valid and panel.data.escape ~= nil and panel.data.escape() then
                    return true
                end
                HeroSheet.BackToSheet()
                return true
            end
            return false
        end,
        fullscreen = dmhub.isLobbyGame,
        maximized = options ~= nil and options.maximized == true,
        onClose = function()
            --the panel's own destroy (pop-in, switch) is not the user closing it.
            if window ~= nil and window.valid and window.data.dropping then
                return
            end
            HeroSheet.Close()
        end,
        onPopIn = PopIn,
    }
    window.data.charid = charid
    return window
end

--- Open a Hero's sheet in the window, on a tab. One Hero window per player:
--- another Hero switches it in place. Returns false when the token is not
--- routed here (not a Hero, or no documents layer), so the caller opens the
--- classic character sheet instead.
--- @param token CharacterToken
--- @param tabid nil|string The classic sheet's tab ids: CharacterSheet, Inventory, Downtime, Appearance, Builder; "Features" lands on the Character tab's Features.
--- @param options nil|{filter: nil|string, maximized: nil|boolean}
--- @return boolean
function HeroSheet.Open(token, tabid, options)
    if not HeroSheet.Routes(token) or not HasLayer() then
        return false
    end

    --Party Member Controls: none does not open, view opens the Character
    --tab read-only.
    local access = CharacterPanel.TokenAccessLevel(token)
    if access == "none" then
        HeroSheetWindow.Toast("Only your Director can open other Heroes' sheets.")
        --true: handled (the toast says why), so the caller does not fall
        --back to the classic sheet.
        return true
    end

    local viewOnly = access == "view"
    local tab = ResolveTab(tabid)
    --a tab another mod shows for some Heroes only: one without it opens on Character.
    local shown = false
    for _,visible in ipairs(VisibleTabs(token.properties)) do
        if visible.id == tab then
            shown = true
            break
        end
    end
    if not shown then
        tab = "CharacterSheet"
    end
    if viewOnly then
        tab = "CharacterSheet"
    end

    local previous = g_live.state
    local switching = previous ~= nil and previous.tokenid ~= token.charid
    if switching then
        HeroSheetWrite.OnLeave()
    end
    --the Builder opened over the same Hero's sheet returns to its tab.
    local returnTab = nil
    if tab == "Builder" and previous ~= nil and not switching then
        returnTab = cond(previous.tab == "Builder", previous.returnTab, previous.tab)
    end
    local state = {
        tokenid = token.charid,
        tab = tab,
        returnTab = returnTab,
        viewOnly = viewOnly,
        pane = (tabid == "Features") and "Features" or nil,
        featuresFilter = options ~= nil and options.filter or nil,
    }
    state.richstatusid = dmhub.PushUserRichStatus("Viewing Character Sheet", previous ~= nil and previous.richstatusid or nil)
    g_live.state = state

    local maximized = options ~= nil and options.maximized == true
    local window = g_live.window
    if window == nil or not window.valid then
        window = BuildWindow(token.charid, options)
        g_live.window = window
        HeroSheetWindow.Show(window)
        audio.FireSoundEvent("UI.WindowOpen")
    else
        --the kept window: another Hero switches in place (the window stays
        --where it is, its blocks redraw); the same Hero catches up on any
        --change made while it was closed.
        --A switch keeps the built content and repaints it for the new Hero
        --(the EotW sheet's way): parts that hold the old Hero let go on
        --heroSheetHero, then every block redraws. Only a Hero with other
        --tabs (another mod's) needs the content built again; its new blocks
        --draw themselves as they are made.
        if window.data.charid ~= token.charid then
            window.data.charid = token.charid
            if g_live.contentTabs == TabsKey(token.properties) then
                window:FireEventTree("heroSheetHero", token)
                --drawn for the new Hero as they show: SelectTab below
                --catches up the tab it opens on, the rest when shown.
                HeroSheetRefresh.SwitchedHero()
            else
                window.data.setContent(BuildContent())
            end
        else
            HeroSheetRefresh.Changed()
        end
        if window.data.closed then
            window.data.reopen(maximized)
        elseif window.data.minimized then
            window.data.restore()
        else
            HeroSheetWindow.BringToFront(window)
        end
    end
    if switching or previous == nil then
        HeroSheetWrite.Rebaseline()
    end
    SelectTab(tab)
    return true
end

--- The harness's show handler hands a Hero here (CharacterSheetFramework.lua).
--- Returns true when the window took it; the harness then hides and is
--- closed, so dmhub.inCharacterSheet goes false and map input keeps working.
--- @param token CharacterToken
--- @param tabid nil|string
--- @return boolean
function HeroSheet.OpenFromHarness(token, tabid)
    if not HeroSheet.Routes(token) then
        return false
    end

    local handled
    local state = g_live.state
    local window = g_live.window
    --The C key (and any route with no tab, or the tab already open) toggles:
    --a minimized or covered window comes to the front, a front one closes.
    if state ~= nil and window ~= nil and HeroSheet.IsShowing(token.charid)
            and (tabid == nil or ResolveTab(tabid) == state.tab) then
        if window.data.minimized then
            window.data.restore()
        elseif IsFrontmost() then
            HeroSheet.Close()
        else
            HeroSheetWindow.BringToFront(window)
        end
        handled = true
    else
        handled = HeroSheet.Open(token, tabid)
    end
    if not handled then
        return false
    end

    --Close the harness next frame. Closing it fires characterSheetClosed,
    --which would tell the lobby's Edit Hero and the new-character tracking
    --that the sheet already closed; the window fires it when it really does.
    --Handlers run newest first and true swallows the event, so one
    --registered just before the close sees it first.
    --This is not reliable: the harness hides itself as soon as its panel
    --collapses (its Update), often before this runs at high frame rates,
    --and fires the event unswallowed. Listeners must therefore ignore
    --characterSheetClosed while HeroSheet.IsShowing(their Hero) (VQJFWPK4).
    dmhub.Schedule(0.01, function()
        if mod.unloaded or not dmhub.inCharacterSheet then
            return
        end
        local swallowed = false
        local handler = dmhub.RegisterEventHandler("characterSheetClosed", function()
            if swallowed then
                return false
            end
            swallowed = true
            return true
        end)
        dmhub.CloseCharacterSheet()
        dmhub.DeregisterEventHandler(handler)
    end)
    return true
end

--- The Hero sheet button on a Hero's table card (Tabletop.CardHeroSheetButton):
--- restores the sheet minimized into the card, brings a covered one to the
--- front, minimizes a front one back into the card, or opens it.
--- @param charid string
function HeroSheet.CardButton(charid)
    HeroSheetRefresh.Warm(charid)
    local window = g_live.window
    if HeroSheet.IsShowing(charid) and window ~= nil then
        if window.data.minimized then
            window.data.restore()
        elseif IsFrontmost() then
            window.data.minimize()
        else
            HeroSheetWindow.BringToFront(window)
        end
        return
    end
    local token = dmhub.GetCharacterById(charid)
    if token ~= nil then
        HeroSheet.Open(token)
    end
end

--- Warm a Hero's sheet before it opens (the pointer rests on a way into it).
--- @param charid string
function HeroSheet.Warm(charid)
    HeroSheetRefresh.Warm(charid)
end

--- True when the harness should skip building this token's sheet: the
--- window shows it instead (saves the classic sheet's full refresh on
--- every open).
--- @param token nil|CharacterToken
--- @return boolean
function HeroSheet.OwnsSheet(token)
    return HeroSheet.Routes(token) and HasLayer()
end

--The Windows menu: the open sheet is one
--row like any open window (checked unless minimized; picking it brings it
--back), and a "Hero sheets" folder lists every Hero this user controls,
--picking one opening its sheet maximized.
local tabletop = rawget(_G, "Tabletop")
if tabletop ~= nil and tabletop.RegisterWindowsMenuSource ~= nil then
    tabletop.RegisterWindowsMenuSource("herosheet", function()
        local rows = {}
        local window = g_live.window
        local token = HeroSheet.Token()
        if g_live.state ~= nil and window ~= nil and window.valid and token ~= nil then
            rows[#rows+1] = {
                text = (token.name or "Hero") .. " \u{00B7} Hero sheet",
                open = not window.data.minimized,
                sortKey = "1",
                activate = function()
                    local liveWindow = g_live.window
                    if liveWindow ~= nil and liveWindow.valid then
                        if liveWindow.data.minimized then
                            liveWindow.data.restore()
                        else
                            HeroSheetWindow.BringToFront(liveWindow)
                        end
                    end
                end,
            }
        end
        local heroes = {}
        local seen = {}
        for _, partyid in ipairs(GetAllParties()) do
            for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
                local hero = dmhub.GetCharacterById(charid)
                if not seen[charid] and hero ~= nil and hero.canControl and HeroSheet.Routes(hero) then
                    seen[charid] = true
                    heroes[#heroes+1] = {
                        text = hero.name or "Hero",
                        click = function()
                            local live = dmhub.GetCharacterById(charid)
                            if live ~= nil then
                                HeroSheet.Open(live, nil, {maximized = true})
                            end
                        end,
                    }
                end
            end
        end
        table.sort(heroes, function(left, right) return string.lower(left.text) < string.lower(right.text) end)
        if #heroes > 0 then
            rows[#rows+1] = {
                text = "Hero sheets",
                sortKey = "2",
                submenu = heroes,
            }
        end
        return rows
    end)
end

--Ctrl+Tab: the open (or minimized) sheet is one card among the windows.
local switcher = rawget(_G, "WindowSwitcher")
if switcher ~= nil and switcher.RegisterSource ~= nil then
    switcher.RegisterSource("herosheet", function()
        local window = g_live.window
        local token = HeroSheet.Token()
        if g_live.state == nil or window == nil or not window.valid or token == nil then
            return {}
        end
        local charid = token.charid
        return {{
            key = "herosheet",
            kind = "herosheet",
            name = token.name or "Hero",
            panel = window,
            --the Hero's card art, cropped as the hero card crops it, at the
            --card's shape in the middle of the picture. A look with its own
            --card framing shows that framing instead.
            thumb = function(width, height)
                local aspect = EotwHeroCard.CARD_WIDTH / EotwHeroCard.CARD_HEIGHT
                return gui.Panel{
                    interactable = false,
                    bgimage = "panels/square.png",
                    bgcolor = "#1d1915ff",
                    width = math.floor(height * aspect),
                    height = height,
                    halign = "center",
                    valign = "center",
                    data = {},
                    create = function(element)
                        local live = dmhub.GetCharacterById(charid)
                        if live ~= nil then
                            EotwHeroCard.ApplyPortrait(element, live, aspect)
                        end
                    end,
                }
            end,
            icon = "phosphor/file-text.png",
            detail = "Hero sheet",
            minimized = window.data.minimized == true,
            maximized = window.data.maximized == true,
            activate = function()
                local liveWindow = g_live.window
                if liveWindow == nil or not liveWindow.valid then
                    return
                end
                if liveWindow.data.minimized then
                    liveWindow.data.restore()
                else
                    HeroSheetWindow.BringToFront(liveWindow)
                end
            end,
        }}
    end)
end

--A reload (F4) runs this file again: the old window's closures belong to the
--old code, so remove it and reopen the same Hero on the same tab.
local g_oldWindow = g_live.window
if g_oldWindow ~= nil then
    local reopen = g_live.state
    local old = g_oldWindow
    g_live.window = nil
    g_live.state = nil
    if old.valid then
        old.data.dropping = true
        if old.data.minimized and old.data.charid ~= nil then
            Tabletop.RestoreFromCard(old.data.charid, nil, function() end)
        end
        old:DestroySelf()
    end
    if reopen ~= nil then
        dmhub.PopUserRichStatus(reopen.richstatusid)
        --the HUD may still be rebuilding: try again for a few seconds.
        local tries = 0
        local function Reopen()
            if mod.unloaded then
                return
            end
            tries = tries + 1
            if not HasLayer() then
                if tries < 50 then
                    dmhub.Schedule(0.1, Reopen)
                end
                return
            end
            local token = dmhub.GetCharacterById(reopen.tokenid)
            if token ~= nil then
                HeroSheet.Open(token, reopen.tab)
            end
        end
        dmhub.Schedule(0.1, Reopen)
    end
end
