local mod = dmhub.GetModLoading()

--The Hero sheet's refresh layer. The classic character sheet rebuilds its
--whole tree on every patch to the Hero, which is slow. This sheet pushes
--instead: each part of the sheet that shows Hero data is a "block" with a
--signature, a cheap string built from just the data it shows. When the Hero
--changes, the changes are gathered into one pass per frame, every block's
--signature is taken again, and only blocks whose signature changed redraw.
--A block holding the keyboard (a field being typed in, a note editor) is
--left alone until it lets go, so a remote change never eats someone's
--typing.
--
--How a tab uses it:
--  HeroSheetRefresh.Block({...panel args...}, {
--      signature = function(token) return <string of what this shows> end,
--      refresh = function(panel, token) <redraw from the Hero> end,
--  })
--Warmers (HeroSheetRefresh.RegisterWarmer) precompute a Hero's lists when
--the pointer rests on something that opens their sheet, so the open is fast.

HeroSheetRefresh = rawget(_G, "HeroSheetRefresh") or {}

--A pass at or over this logs a PERF line with the slowest blocks.
local PERF_REPORT_MS = 50

--How often a block that held the keyboard is checked again.
local FOCUS_RETRY = 0.5

--A block waiting this long for the keyboard is logged once.
local FOCUS_WAIT_LOG = 5

--- @class HeroSheetBlockSpec
--- @field signature fun(token: CharacterToken): string what the block shows, as a string; equal strings mean nothing to redraw
--- @field refresh fun(panel: Panel, token: CharacterToken) redraws the block from the Hero
--- @field name nil|string for the PERF line
--- @field holdsKeyboard nil|fun(panel: Panel): boolean true while the block's typing happens outside its panel (a field in a pinned card, which is a popup), so it waits as a focused block does
--- @field builder nil|boolean a block of the Builder's: it redraws while the sheet's own blocks are paused under the Builder

--every live block panel and its spec. Held strongly: a panel handle that
--only this table holds would be garbage-collected while the panel is still
--on screen, and its block would stop refreshing. Blocks leave on destroy, and
--each pass sweeps out any destroyed panel left behind.
--- @type table<Panel, {spec: HeroSheetBlockSpec, signature: nil|string, waitingSince: nil|number, waitLogged: nil|boolean, stale: nil|boolean, staleForce: nil|boolean}>
local g_blocks = {}

--A sheet block that is not on screen when a pass runs (another tab's, the
--card column at Narrow) is not redrawn: building panels nobody sees was most
--of a pass's cost. It is marked stale and catches up before it is seen: a
--tab or pane switch calls CatchUpShown once it has set what shows, the
--pointer resting on a tab's button calls CatchUp for that tab, and the
--Monitor checks for any other way back on screen. The Builder's blocks too:
--a hidden Builder or Level up catches up when it opens.
local g_anyStale = false

--True while a pass or a catch-up is redrawing: a redraw that arranges its
--panes (and so asks for a catch-up) must not redraw blocks under the loop
--that is drawing them. The loop catches up once more at its end instead.
local g_busy = false

--How often the Monitor looks for a stale block back on screen by a way no
--tab or pane switch covers (those catch up at once).
local STALE_CHECK = 0.25

local g_passScheduled = false
local g_retryScheduled = false
--the scheduled pass follows a change to the Hero, so its cached values go.
local g_passInvalidate = false

--While the Builder covers the sheet, the sheet's blocks are not drawn
--on every pick: they keep their old signature and catch up when it shows.
local g_sheetPaused = false
--Sheet panels the Builder borrows (its Appearance step shows the sheet's
--Appearance surface): their blocks are not paused with the sheet's.
--- @type Panel[]
local g_lent = {}
--a forced pass (another Hero) skipped the paused blocks: force them later.
local g_forceOnResume = false

--warmers by id: fun(charid)
--- @type table<string, fun(charid: string)>
local g_warmers = {}

--- Runs after a pass that redrew a block (set by the content, which fits
--- its sizes to what the blocks now take).
--- @type nil|fun()
HeroSheetRefresh.afterRedraw = rawget(HeroSheetRefresh, "afterRedraw")

--One read of the open Hero, shared by every block (the EotW sheet's model:
--read the Hero once, and every part shows that table). A read is costly on a
--high-Level Hero, so it is kept until something it could depend on
--changes: our own save or a patch to the Hero (the gen), any game data from
--the cloud (other characters and objects, since an ally's aura can change
--this Hero's numbers; initiative; shared settings such as the XP pace), or
--the compendium. A tab switch, an Edit toggle or a resize then reuses it.
local g_readGen = 0
--- @class HeroSheetRead
--- @field charid nil|string
--- @field props any the properties object read (the engine can swap it)
--- @field gen number
--- @field seq number dmhub.gameContentUpdateSeq when read
--- @field tables number dmhub.tablesUpdateId when read
--- @field json nil|string the Hero's properties as JSON when read, to tell an echo of our own save from a change
--- @field tokenSig nil|string the token fields the sheet shows, when read
--- @field d nil|table
--- @type HeroSheetRead
local g_read = {charid = nil, props = nil, gen = -1, seq = -1, tables = -1, d = nil}

--Time spent reading during the current pass, for its PERF line.
local g_passReadMs = 0

--- The token's own fields the sheet shows or that move its numbers (its
--- place on the map, for auras), which live outside its properties.
--- @param token CharacterToken
--- @return string
local function TokenSig(token)
    local parts = {}
    for _, field in ipairs({"name", "namePrivate", "ownerId", "partyId", "portrait", "portraitFrame", "loc", "floorid"}) do
        local value = nil
        pcall(function() value = token[field] end)
        parts[#parts+1] = tostring(value)
    end
    local card = ""
    pcall(function() card = CardPortraitSignature(token) end)
    parts[#parts+1] = card
    return table.concat(parts, "|")
end

--- The open Hero as the EotW reader reads it (every section, one feature
--- index), shared by every block until something changes (above). Building
--- the index is much of a read, so blocks never read for themselves.
--- The feature index the reader built rides along as `data.index`, for the
--- parts that need more than the reader keeps.
--- @param token CharacterToken
--- @return nil|table
function HeroSheetRefresh.Read(token)
    --the kept read still holds for this token.
    if g_read.d ~= nil and g_read.charid == token.charid and rawequal(g_read.props, token.properties)
        and g_read.gen == g_readGen and g_read.seq == dmhub.gameContentUpdateSeq
        and g_read.tables == dmhub.tablesUpdateId then
        return g_read.d
    end
    local sw = dmhub.Stopwatch()
    --taken before the read so a change landing during it reads again.
    local stamp = {
        charid = token.charid,
        props = token.properties,
        gen = g_readGen,
        seq = dmhub.gameContentUpdateSeq,
        tables = dmhub.tablesUpdateId,
        json = dmhub.ToJson(token.properties),
        tokenSig = TokenSig(token),
    }
    local data = nil
    --the reader builds the index inside and keeps only what its sections
    --need; catching it for the read's length means it is built once.
    local index = nil
    local build = FeatureCategoriser.BuildIndex
    FeatureCategoriser.BuildIndex = function(creature)
        local result = build(creature)
        index = result
        return result
    end
    pcall(function() data = EotwHeroSheet.Data(token) end)
    FeatureCategoriser.BuildIndex = build
    if data ~= nil then
        data.index = index
    end
    --a failed read (nil) is never kept: the next asker tries again.
    stamp.d = data
    g_read = stamp --[[@as HeroSheetRead]]
    g_passReadMs = g_passReadMs + sw.milliseconds
    return data
end

--- The Hero changed (a save, a patch): the next read reads it again.
function HeroSheetRefresh.Stale()
    g_readGen = g_readGen + 1
end

--Until this time (dmhub.Time) a patch may be the cloud sending back one of
--our own saves, which the sheet has already drawn.
local ECHO_WINDOW = 3
local g_echoUntil = -1

--- A save was just sent: its echo from the cloud is expected shortly.
function HeroSheetRefresh.ExpectEcho()
    g_echoUntil = dmhub.Time() + ECHO_WINDOW
end

--- A patch to the Hero arrived (the Monitor): true when it is the echo of
--- our own save, changing nothing the kept read was taken from. The read is
--- then kept, as if read after the patch. Anything else reads again.
--- @param token CharacterToken
--- @return boolean
local function EchoOfRead(token)
    if dmhub.Time() > g_echoUntil then
        return false
    end
    if g_read.d == nil or g_read.charid ~= token.charid or not rawequal(g_read.props, token.properties)
        or g_read.gen ~= g_readGen or g_read.tables ~= dmhub.tablesUpdateId then
        return false
    end
    if g_read.json ~= dmhub.ToJson(token.properties) or g_read.tokenSig ~= TokenSig(token) then
        return false
    end
    g_read.seq = dmhub.gameContentUpdateSeq
    return true
end

--- A panel that redraws itself only when the data it shows changes. Pass the
--- panel's own args and the block's spec; the block draws once when created.
--- @param panelArgs table
--- @param spec HeroSheetBlockSpec
--- @return Panel
function HeroSheetRefresh.Block(panelArgs, spec)
    local create = panelArgs.create
    local destroy = panelArgs.destroy
    --a destroyed panel's userdata errors on any read, even .valid, so the
    --block leaves the list as it goes rather than waiting to be collected.
    panelArgs.destroy = function(element)
        g_blocks[element] = nil
        if destroy ~= nil then
            destroy(element)
        end
    end
    panelArgs.create = function(element)
        g_blocks[element] = {spec = spec, signature = nil}
        local token = HeroSheet.Token()
        if token ~= nil then
            local ok, sig = pcall(spec.signature, token)
            if ok then
                g_blocks[element].signature = sig
            end
            spec.refresh(element, token)
        end
        if create ~= nil then
            create(element)
        end
    end
    return gui.Panel(panelArgs)
end

--- @class HeroSheetKeptSpec
--- @field name string for the PERF line
--- @field signature fun(token: CharacterToken): string as a block's
--- @field shape fun(token: CharacterToken): string what fixes the block's panels (the tier, Edit mode, a count); anything else is repainted in place
--- @field build fun(holder: Panel, token: CharacterToken): nil|fun(token: CharacterToken) builds the shape's panels as the holder's children and returns the painter that shows a Hero in them (nil: nothing to show)
--- @field holdsKeyboard nil|fun(panel: Panel): boolean as a block's

--- A block built once for each shape it shows and repainted in place after
--- that, the EotW sheet's way: another Hero or a change paints new values
--- into the panels already there. Each shape's panels are built into their
--- own holder the first time, and kept: a Hero of another shape shows that
--- holder and collapses the rest, so switching back and forth never builds.
--- Building panels is most of a redraw's cost (the Lua, then the engine's
--- layout); a collapsed holder costs nothing. Fire
--- "heroSheetRepaint" on the panel after an event that can change the shape.
--- @param panelArgs table its flow is the holders' flow too
--- @param spec HeroSheetKeptSpec
--- @return Panel
function HeroSheetRefresh.KeptBlock(panelArgs, spec)
    --- @type table<string, {holder: Panel, paint: fun(token: CharacterToken)}>
    local built = {}
    --- @type nil|{holder: Panel, paint: fun(token: CharacterToken)}
    local shown = nil
    --- @param panel Panel
    --- @param token CharacterToken
    local function Draw(panel, token)
        local shape = spec.shape(token)
        local entry = built[shape]
        if entry == nil then
            local holder = gui.Panel{
                width = "100%",
                height = "auto",
                flow = panelArgs.flow or "vertical",
            }
            local paint = spec.build(holder, token)
            if paint ~= nil then
                entry = {holder = holder, paint = paint}
                built[shape] = entry
                panel:AddChild(holder)
            end
        end
        if shown ~= entry then
            if shown ~= nil then
                shown.holder:SetClass("collapsed", true)
            end
            if entry ~= nil then
                entry.holder:SetClass("collapsed", false)
            end
            shown = entry
        end
        if entry ~= nil then
            entry.paint(token)
        end
    end
    panelArgs.heroSheetRepaint = function(element)
        local token = HeroSheet.Token()
        if token ~= nil then
            Draw(element, token)
        end
    end
    return HeroSheetRefresh.Block(panelArgs, {
        name = spec.name,
        --the shape too: an event that changes it (a tier change while the
        --sheet is closed, with no Hero shown) can miss the block, and the
        --next refresh pass then shows the right holder.
        signature = function(token)
            return spec.signature(token) .. "\n" .. spec.shape(token)
        end,
        holdsKeyboard = spec.holdsKeyboard,
        refresh = Draw,
    })
end

--- @class HeroSheetPassTally
--- @field checked integer
--- @field redrawn integer
--- @field sheetRedrawn integer the sheet's own blocks redrawn (not the Builder's): the sheet refits
--- @field waiting integer
--- @field hidden integer
--- @field costly string[] blocks that took 5 ms or more: "name signature+redraw"

--- @return HeroSheetPassTally
local function NewTally()
    return {checked = 0, redrawn = 0, sheetRedrawn = 0, waiting = 0, hidden = 0, costly = {}}
end

--- The live blocks as a list, to walk while redraws may add new ones.
--- @return {panel: Panel, entry: table}[]
local function BlockList()
    local list = {}
    for panel, entry in pairs(g_blocks) do
        list[#list+1] = {panel = panel, entry = entry}
    end
    return list
end

--- Whether a block's panel shows this frame: nothing above it is collapsed
--- (another tab, a shut pane, the card column at Narrow). Read from the
--- classes, which a tab switch changes at once, not .enabled, which follows a
--- frame later. A panel hidden another way counts as shown, so it is drawn as
--- before rather than left stale.
--- @param panel Panel
--- @return boolean
local function Shown(panel)
    local node = panel
    for _ = 1, 64 do
        if node == nil then
            return true
        end
        if node:HasClass("collapsed") then
            return false
        end
        node = node.parent
    end
    return true
end

--- Whether a block waits for the sheet to show again: a sheet block while
--- the Builder covers the sheet, unless the Builder has borrowed its panel.
--- @param panel Panel
--- @param entry table
--- @return boolean
local function Paused(panel, entry)
    if not g_sheetPaused or entry.spec.builder then
        return false
    end
    local node = panel
    for _ = 1, 64 do
        if node == nil then
            return true
        end
        for _, root in ipairs(g_lent) do
            if rawequal(node, root) then
                return false
            end
        end
        node = node.parent
    end
    return true
end

--- Take a block's signature again and redraw it if what it shows changed
--- (always when forced, or when it went stale under a forced pass). A block
--- holding the keyboard waits.
--- @param panel Panel
--- @param entry table
--- @param token CharacterToken
--- @param force nil|boolean
--- @param sw any the pass's stopwatch
--- @param tally HeroSheetPassTally
local function CheckBlock(panel, entry, token, force, sw, tally)
    force = force or entry.staleForce == true
    tally.checked = tally.checked + 1
    local sigStart = sw.milliseconds
    local ok, result = pcall(entry.spec.signature, token)
    local sigMs = sw.milliseconds - sigStart
    local drawMs = 0
    --- @type nil|string
    local sig = nil
    if ok then
        sig = result
    end
    if force or sig == nil or sig ~= entry.signature then
        local holds = entry.spec.holdsKeyboard
        if gui.ChildHasFocus(panel) or (holds ~= nil and holds(panel)) then
            tally.waiting = tally.waiting + 1
            --a block kept waiting this long is worth a line in the log.
            entry.waitingSince = entry.waitingSince or dmhub.Time()
            if not entry.waitLogged and dmhub.Time() - entry.waitingSince > FOCUS_WAIT_LOG then
                entry.waitLogged = true
                print(string.format("HEROSHEET:: block %s has waited %.0f s for the keyboard to let go", tostring(entry.spec.name), dmhub.Time() - entry.waitingSince))
            end
        else
            entry.waitingSince = nil
            entry.waitLogged = nil
            local before = sw.milliseconds
            --one failing block must not stop the others redrawing.
            local okDraw, err = pcall(entry.spec.refresh, panel, token)
            if okDraw then
                entry.signature = sig
            else
                dmhub.Error(string.format("HEROSHEET:: block %s failed to redraw: %s", tostring(entry.spec.name), tostring(err)))
            end
            entry.stale = nil
            entry.staleForce = nil
            tally.redrawn = tally.redrawn + 1
            if not entry.spec.builder then
                tally.sheetRedrawn = tally.sheetRedrawn + 1
            end
            drawMs = sw.milliseconds - before
        end
    else
        entry.stale = nil
        entry.staleForce = nil
    end
    if sigMs + drawMs >= 5 then
        tally.costly[#tally.costly+1] = string.format("%s %.0f+%.0f", tostring(entry.spec.name), sigMs, drawMs)
    end
end

--- What was redrawn may have changed height (the band): the content fits again.
--- @param tally HeroSheetPassTally
local function AfterRedraw(tally)
    if tally.sheetRedrawn > 0 and HeroSheetRefresh.afterRedraw ~= nil then
        pcall(HeroSheetRefresh.afterRedraw)
    end
end

--- Whether any block is still stale (after a catch-up redrew some).
local function NoteStale()
    g_anyStale = false
    for _, entry in pairs(g_blocks) do
        if entry.stale then
            g_anyStale = true
            return
        end
    end
end

--One pass over every block: redraw those whose signature changed. Blocks
--holding the keyboard wait; a retry checks them again soon. Blocks off
--screen go stale instead.
--- The read is not taken here: blocks read as they are checked, so a pass
--- with nothing on screen (the sheet closed or minimized) reads nothing.
--- @param force nil|boolean redraw every block (a different Hero)
local function Pass(force)
    g_passScheduled = false
    local token = HeroSheet.Token()
    if token == nil or token.properties == nil then
        return
    end
    --values the Hero caches (named attributes such as Wealth) would read
    --stale after a change: the classic sheet invalidates on every refresh too.
    --A recheck (nothing changed) keeps them.
    if g_passInvalidate then
        g_passInvalidate = false
        token.properties:Invalidate()
    end
    local sw = dmhub.Stopwatch()
    g_passReadMs = 0
    local tally = NewTally()
    local dead = {}
    local wasBusy = g_busy
    g_busy = true
    --an error must not leave g_busy set, which would stop every catch-up.
    local ok, err = pcall(function()
        --walked from a copy: a redraw can build new blocks, which join
        --g_blocks, and Lua's pairs is undefined when a key is added mid-walk.
        for _, item in ipairs(BlockList()) do
            local panel, entry = item.panel, item.entry
            local okValid, valid = pcall(function() return panel.valid end)
            if not okValid or not valid then
                dead[#dead+1] = panel
            elseif Paused(panel, entry) then
                if force then
                    g_forceOnResume = true
                end
            elseif not Shown(panel) then
                entry.stale = true
                if force then
                    entry.staleForce = true
                end
                g_anyStale = true
                tally.hidden = tally.hidden + 1
            else
                CheckBlock(panel, entry, token, force, sw, tally)
            end
        end
    end)
    g_busy = wasBusy
    if not ok then
        dmhub.Error(string.format("HEROSHEET:: refresh pass failed: %s", tostring(err)))
    end
    for _, panel in ipairs(dead) do
        g_blocks[panel] = nil
    end
    AfterRedraw(tally)
    --a redraw above may have shown a pane whose block was passed over as hidden.
    if g_anyStale and not g_busy then
        HeroSheetRefresh.CatchUpShown()
    end
    local ms = sw.milliseconds
    if ms >= PERF_REPORT_MS then
        print(string.format("PERF:: HeroSheet refresh %.0f ms: read %.0f, %d blocks checked, %d redrawn, %d hidden left stale; signature+redraw: %s",
            ms, g_passReadMs, tally.checked, tally.redrawn, tally.hidden, table.concat(tally.costly, ", ")))
    end
    local waiting = tally.waiting
    if waiting > 0 and not g_retryScheduled then
        g_retryScheduled = true
        dmhub.Schedule(FOCUS_RETRY, function()
            g_retryScheduled = false
            if not mod.unloaded then
                Pass(false)
            end
        end)
    end
end

--- A block's panel was just drawn by its own code (the Builder painting as it
--- opens): take its signature now, so a catch-up does not draw it again.
--- @param panel Panel
function HeroSheetRefresh.Drawn(panel)
    local entry = g_blocks[panel]
    local token = HeroSheet.Token()
    if entry == nil or token == nil then
        return
    end
    local ok, sig = pcall(entry.spec.signature, token)
    if ok then
        entry.signature = sig
        entry.stale = nil
        entry.staleForce = nil
    end
end

--- One pass at the end of the frame, however many asks arrive.
local function SchedulePass()
    if g_passScheduled then
        return
    end
    g_passScheduled = true
    dmhub.Schedule(0.01, function()
        if mod.unloaded then
            return
        end
        Pass(false)
    end)
end

--- The Hero changed (a remote patch, a save, a rules change): read it again
--- and redraw what changed, once, at the end of the frame.
function HeroSheetRefresh.Changed()
    HeroSheetRefresh.Stale()
    g_passInvalidate = true
    SchedulePass()
end

--- Something a block shows besides the Hero's data changed (a status worked
--- out, the theme, the Builder closing, a shared document): check every
--- block's signature against the kept read, without reading the Hero again.
--- Use Changed instead whenever the Hero itself may have changed.
function HeroSheetRefresh.Recheck()
    SchedulePass()
end

--- Redraw every block now: the window shows a different Hero.
function HeroSheetRefresh.RefreshAll()
    g_passInvalidate = true
    Pass(true)
end

--- The window now shows a different Hero: every block is out of date, and
--- each redraws in full as it shows (the tab switch that follows catches up
--- what shows at once). Nothing on another tab is drawn for the new Hero.
function HeroSheetRefresh.SwitchedHero()
    local token = HeroSheet.Token()
    if token ~= nil and token.properties ~= nil then
        token.properties:Invalidate()
    end
    HeroSheetRefresh.Stale()
    for panel, entry in pairs(g_blocks) do
        local okValid, valid = pcall(function() return panel.valid end)
        if okValid and valid then
            entry.stale = true
            entry.staleForce = true
        end
    end
    if g_sheetPaused then
        g_forceOnResume = true
    end
    g_anyStale = true
end

--- True when the panel shows once one of the roots does: it is that root or
--- inside it, with nothing collapsed between (a pane of the tab that stays
--- shut). Classes, not .enabled: a collapse takes effect only next frame.
--- @param panel Panel
--- @param roots Panel[]
--- @return boolean
local function Under(panel, roots)
    local node = panel
    for _ = 1, 64 do
        if node == nil then
            return false
        end
        for _, root in ipairs(roots) do
            if rawequal(node, root) then
                return true
            end
        end
        if node:HasClass("collapsed") then
            return false
        end
        node = node.parent
    end
    return false
end

--- Check the stale blocks that pass the test, redrawing what changed.
--- @param label string for the PERF line
--- @param wanted fun(panel: Panel): boolean
local function CatchUpWhere(label, wanted)
    if not g_anyStale or g_busy then
        return
    end
    local token = HeroSheet.Token()
    if token == nil or token.properties == nil then
        return
    end
    local sw = dmhub.Stopwatch()
    local tally = NewTally()
    g_busy = true
    --an error must not leave g_busy set, which would stop every catch-up.
    local ok, err = pcall(function()
        --from a copy, as in Pass: a redraw can add blocks.
        for _, item in ipairs(BlockList()) do
            local panel, entry = item.panel, item.entry
            if entry.stale then
                local okValid, valid = pcall(function() return panel.valid end)
                if okValid and valid and not Paused(panel, entry) and wanted(panel) then
                    CheckBlock(panel, entry, token, false, sw, tally)
                end
            end
        end
    end)
    g_busy = false
    if not ok then
        dmhub.Error(string.format("HEROSHEET:: %s failed: %s", label, tostring(err)))
    end
    NoteStale()
    AfterRedraw(tally)
    local ms = sw.milliseconds
    if ms >= PERF_REPORT_MS then
        print(string.format("PERF:: HeroSheet %s %.0f ms: %d blocks checked, %d redrawn; signature+redraw: %s",
            label, ms, tally.checked, tally.redrawn, table.concat(tally.costly, ", ")))
    end
end

--- Bring the stale blocks inside these panels up to date now, ahead of
--- their showing: the pointer resting on a tab's button.
--- @param roots Panel[]
function HeroSheetRefresh.CatchUp(roots)
    if #roots == 0 then
        return
    end
    CatchUpWhere("warm", function(panel)
        return Under(panel, roots)
    end)
end

--- Bring up to date the stale blocks that show this frame. Call it after a
--- change of what shows (a tab or pane switch has set its classes) and
--- before the frame draws, so nothing stale is seen; the Monitor also calls
--- it for any way back on screen nothing else covers.
function HeroSheetRefresh.CatchUpShown()
    CatchUpWhere("catch-up", Shown)
end

--- Pause the sheet's own blocks while the Builder covers the sheet:
--- a pick then redraws only the Builder's blocks. Resuming redraws what
--- changed meanwhile (every block, if the Hero was switched).
--- @param paused boolean
function HeroSheetRefresh.PauseSheet(paused)
    if g_sheetPaused == paused then
        return
    end
    g_sheetPaused = paused
    if not paused then
        local force = g_forceOnResume
        g_forceOnResume = false
        if force then
            Pass(true)
        else
            --the Builder's saves already read the Hero again.
            HeroSheetRefresh.Recheck()
        end
    end
end

--- The Builder borrows these sheet panels (nil: gives them back): their
--- blocks keep redrawing while the sheet's own are paused under the Builder.
--- @param roots nil|Panel[]
function HeroSheetRefresh.Lend(roots)
    g_lent = roots or {}
    if #g_lent > 0 then
        HeroSheetRefresh.Recheck()
    end
end

--- A hidden panel that watches the Hero in the cloud and reports changes:
--- the write layer's close check resets, and changed blocks redraw.
--- @param token nil|CharacterToken
--- @return Panel
function HeroSheetRefresh.Monitor(token)
    return gui.Panel{
        floating = true,
        interactable = false,
        width = 1,
        height = 1,
        monitorGame = token ~= nil and token.monitorPath or nil,
        refreshGame = function(element)
            --the cloud sending back our own save: already drawn.
            local token = HeroSheet.Token()
            if token ~= nil and token.properties ~= nil and EchoOfRead(token) then
                return
            end
            HeroSheetWrite.Rebaseline()
            HeroSheetRefresh.Changed()
        end,
        --the kept content shows another Hero: watch that one instead.
        heroSheetHero = function(element, newToken)
            element.monitorGame = newToken.monitorPath
        end,
        --a stale block back on screen by a way no tab switch covers. Costs
        --a flag test while nothing is stale.
        thinkTime = STALE_CHECK,
        think = function(element)
            if g_anyStale then
                HeroSheetRefresh.CatchUpShown()
            end
        end,
        --the card column comes back out of Narrow: once every part has taken
        --the new tier, its blocks catch up.
        heroSheetTier = function(element)
            if g_anyStale then
                dmhub.Schedule(0.01, function()
                    if not mod.unloaded then
                        HeroSheetRefresh.CatchUpShown()
                    end
                end)
            end
        end,
    }
end

--- Register work that makes a Hero's sheet open faster (cached lists...),
--- run when the pointer rests on a way into that sheet. Same id replaces.
--- @param id string
--- @param fn fun(charid: string)
function HeroSheetRefresh.RegisterWarmer(id, fn)
    g_warmers[id] = fn
end

--- Run the warmers for a Hero (the card's sheet button and the switcher call
--- this on hover). Cheap when already warm: each warmer caches.
--- @param charid string
function HeroSheetRefresh.Warm(charid)
    for id, fn in pairs(g_warmers) do
        local ok, err = pcall(fn, charid)
        if not ok then
            dmhub.Error(string.format("Hero sheet warmer %s failed: %s", id, tostring(err)))
        end
    end
end
