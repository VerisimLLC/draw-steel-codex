local mod = dmhub.GetModLoading()

--Encounter of the Week hero builder: the main game's Hero Builder
--(Draw Steel Character Builder/HeroBuilder.lua) run over the town, on a
--lobby-game character, with EotW's rules:
--its own build engine (EotwBuild: Gold complications, one complication,
--treasure on the pick, writes not undoable), Finish only for a complete Hero,
--Save and Close, a single-step mode and locked steps. The Builder looks and
--works as in the main game, in the Hero sheet's theme.
--
--This file is the Builder's host in the town: which Hero it shows, how a
--change is saved, when it repaints, and where it is laid out.
--
--Entry point: EotwBuilder.Open{host, token, onFinish, onClose}.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The hero builder and hero sheet".

local T = UIText.T

EotwBuilder = {}

--How often (s) the Builder's blocks check whether the Hero changed (a write
--here repaints at once; this catches the rest, such as the City's sync).
local BLOCK_CHECK = 0.25

--args:
--  host      the panel to mount on (the town screen)
--  token     the lobby character being built
--  title     optional heading (default "Create Your Hero")
--  step      optional step to open on (default: the first incomplete one)
--  only      optional step id: show only that step (no stepper choice, no
--            Back / Fill / Next), e.g. "appearance" for Change Appearance
--  lockedSteps optional set of step ids ({ancestry = true}) whose main pick
--            is fixed once made: the page shows only the chosen card. A
--            rebuild locks Ancestry and Class; Create locks nothing.
--  subtitle  optional line after the Hero's name (default "Level 1 hero for Blackbottom")
--  levelUp   optional; any non-nil value (EotwRoster.LevelUpHero passes true)
--            opens the Builder's Level up page, with Level up's words on the
--            close button. The pages shown are the Levels still waiting, and it
--            counts as finished once none wait.
--  onFinish  function(token) when the player finishes a complete hero
--  onClose   function(token) when the player closes without finishing
---@param args table
---@return Panel
function EotwBuilder.Open(args)
    local charid = args.token.charid
    --- @type Panel
    local root
    --- @type Panel
    local inner
    --- @type nil|Panel
    local builder = nil
    --the Appearance surface the Appearance step borrows, built on first use.
    --- @type nil|HeroAppearanceView
    local appearance = nil
    --shows (insets) or hides (nil) Review's EotW sheet; set below.
    --- @type fun(insets: nil|{top: number, bottom: number})
    local Review

    local function Tok()
        return dmhub.GetCharacterById(charid)
    end

    --the blocks that repaint when the Hero changes: {panel, spec, signature}.
    --- @type {panel: Panel, spec: HeroSheetBlockSpec, signature: any}[]
    local blocks = {}

    --- Repaint every block whose Hero has changed since it last painted.
    local function CheckBlocks()
        local tok = Tok()
        if tok == nil then
            return
        end
        for _, block in ipairs(blocks) do
            if block.panel.valid then
                local ok, signature = pcall(block.spec.signature, tok)
                if ok and signature ~= block.signature then
                    block.signature = signature
                    local painted, err = pcall(block.spec.refresh, block.panel, tok)
                    if not painted then
                        dmhub.Error("EotW builder: a block failed to repaint: " .. tostring(err))
                    end
                end
            end
        end
    end

    --- The Builder's host in the town (HeroBuilderHost).
    --- @type HeroBuilderHost
    local host = {
        token = Tok,
        --the town only opens the builder on the player's own Hero.
        canWrite = function()
            return Tok() ~= nil
        end,
        save = function(saveArgs)
            local tok = Tok()
            if tok == nil then
                return false
            end
            tok:ModifyProperties{
                description = saveArgs.description,
                undoable = false,
                execute = function()
                    saveArgs.execute(tok.properties, tok)
                    --a treasure picked here goes straight into the Hero's gear.
                    EotwBuild.SyncTreasureGrants(tok)
                end,
            }
            return true
        end,
        saveAppearance = function(mutate)
            local tok = Tok()
            if tok == nil then
                return false
            end
            local snapshot = tok:PrepareUploadAppearance()
            mutate(tok)
            tok:UploadAppearance(snapshot)
            tok:RefreshAppearanceLocally()
            return true
        end,
        changed = function()
            CheckBlocks()
        end,
        block = function(panelArgs, spec)
            local panel = gui.Panel(panelArgs)
            blocks[#blocks+1] = {panel = panel, spec = spec, signature = nil}
            return panel
        end,
        drawn = function(panel)
            local tok = Tok()
            if tok == nil then
                return
            end
            for _, block in ipairs(blocks) do
                if block.panel == panel then
                    local ok, signature = pcall(block.spec.signature, tok)
                    if ok then
                        block.signature = signature
                    end
                end
            end
        end,
        --the sheet's own Appearance surface, built here: its
        --writes and repaints find the Hero through the sheet's guest.
        lendAppearance = function()
            if appearance == nil or not appearance.body.valid then
                appearance = HeroSheetAppearance.Create()
            end
            appearance.body.selfStyle.height = "100%"
            HeroSheetRefresh.Lend({appearance.body, appearance.column})
            return appearance
        end,
        returnAppearance = function()
            HeroSheetRefresh.Lend(nil)
        end,
        engine = EotwBuild,
    }

    local function Close(finished)
        local tok = Tok()
        Review(nil)
        HeroSheetRefresh.Lend(nil)
        HeroSheet.SetGuest(nil)
        HeroSheetWindow.SetPopupLayer(nil)
        if root ~= nil and root.valid then
            --Finish already played its own sound, so only a plain close sounds here.
            if not finished then
                audio.FireSoundEvent("UI.WindowClose")
            end
            root:DestroySelf()
        end
        if finished then
            if args.onFinish ~= nil and tok ~= nil then
                args.onFinish(tok)
            end
        elseif args.onClose ~= nil and tok ~= nil then
            args.onClose(tok)
        end
    end

    --- @type HeroBuilderEotw
    local eotw = {
        title = args.title or T("builder.header.title"),
        --Level up's title row names the Hero and the Level already.
        subtitle = cond(args.levelUp ~= nil, nil, args.subtitle or T("builder.header.subtitle")),
        only = args.only,
        lockedSteps = args.lockedSteps,
        closeWords = function(complete)
            local words = cond(complete, T("builder.header.finish_button"), T("builder.header.save_close_button"))
            --the draft / finish wording does not fit a single-step edit
            if args.only ~= nil then
                return words, nil
            end
            if args.levelUp ~= nil then
                return words, cond(complete, T("builder.levelup.finish_tooltip"), T("builder.levelup.save_close_tooltip"))
            end
            return words, cond(complete, T("builder.header.finish_tooltip"), T("builder.header.save_close_tooltip"))
        end,
        close = Close,
        stillToDo = function(steps)
            return T("builder.footer.still_to_do", { steps = table.concat(steps, ", ") })
        end,
        reviewBanner = function(hero)
            return T("builder.review.banner", { hero = hero })
        end,
    }

    --Review: the EotW sheet itself, read only, between the
    --Builder's banner and footer. Placed in screen units (the Builder's are
    --divided by the zoom).
    local reviewHolder = gui.Panel{
        classes = { "collapsed" },
        floating = true,
        width = "100%",
        height = 100,
        valign = "top",
    }
    local reviewOpen = false
    Review = function(insets)
        if insets == nil then
            if reviewOpen then
                reviewOpen = false
                EotwHeroSheet.Close()
            end
            reviewHolder:SetClass("collapsed", true)
            return
        end
        local zoom = HeroSheetWindow.Zoom()
        reviewHolder.selfStyle.tmargin = insets.top * zoom
        reviewHolder.selfStyle.height = math.max(1, root.renderedHeight - (insets.top + insets.bottom) * zoom)
        reviewHolder:SetClass("collapsed", false)
        if not reviewOpen then
            reviewOpen = true
            EotwHeroSheet.Show{ token = Tok(), host = reviewHolder, review = true, context = "town" }
        end
    end

    --- Lay the Builder out for the town screen's size at Font Size, as the
    --- Hero sheet window does: the layout is the screen divided by the zoom.
    local laidOut = nil
    local function Layout()
        if root == nil or not root.valid or builder == nil then
            return
        end
        local screenWidth = root.renderedWidth
        local screenHeight = root.renderedHeight
        if screenWidth <= 0 or screenHeight <= 0 then
            return
        end
        local zoom = HeroSheetWindow.Zoom()
        local key = string.format("%d|%d|%s", math.floor(screenWidth), math.floor(screenHeight), tostring(zoom))
        if key == laidOut then
            return
        end
        laidOut = key
        inner.selfStyle.uiscale = zoom
        inner.selfStyle.width = screenWidth / zoom
        inner.selfStyle.height = screenHeight / zoom
        builder:FireEventTree("heroBuilderLayout", screenWidth / zoom, screenHeight / zoom)
    end

    inner = gui.Panel{
        width = 1920,
        height = 1080,
        halign = "left",
        valign = "top",
        pivot = {x = 0, y = 1},
    }

    --last in the root, so it draws over the Builder; it has no image, so it
    --takes no clicks itself.
    local popupLayer = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
    }

    root = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        styles = HeroSheetTheme.RootStyles(),
        captureEscape = true,
        --above the Guild dialog and the town under it.
        escapePriority = 5,
        escape = function()
            --Esc first closes Review's pinned card, then clears a selected skill
            --row, then closes.
            if EotwHeroSheet.ClosePin() then
                return
            end
            if builder ~= nil and builder.valid and builder.data.escape() then
                return
            end
            HeroBuilder.ClosePinned()
            Close(false)
        end,
        --HeroSheetTheme.ApplyBackdrop reads this: the Builder gets its own
        --backdrop, as in the Hero sheet window.
        data = {builder = true},
        create = function(element)
            HeroSheetTheme.ApplyBackdrop(element)
            HeroSheetTheme.Track(element, function(panel)
                panel.styles = HeroSheetTheme.RootStyles()
                HeroSheetTheme.ApplyBackdrop(panel)
            end)
        end,
        thinkTime = BLOCK_CHECK,
        think = function(element)
            Layout()
            CheckBlocks()
        end,
        destroy = function(element)
            HeroSheet.SetGuest(nil)
            HeroSheetWindow.SetPopupLayer(nil)
        end,
        inner,
        --the Appearance surface's blocks redraw when the Hero changes.
        HeroSheetRefresh.Monitor(args.token),
        reviewHolder,
        popupLayer,
    }
    --the sheet's pop-ups and windows (Choose art, Change frame...) open
    --above the Builder: the app's dialog layer is under it in the town.
    HeroSheetWindow.SetPopupLayer(popupLayer)

    --the sheet's parts (the Appearance surface, its writes) serve this Hero.
    HeroSheet.SetGuest(charid)

    builder = HeroBuilder.Create{
        host = host,
        eotw = eotw,
        levelUp = args.levelUp ~= nil,
        review = function(insets)
            Review(insets)
        end,
        --Level up leaves after its last Finish: finished once no Level waits.
        back = function()
            local tok = Tok()
            local finished = args.levelUp ~= nil and tok ~= nil
                and #EotwBuild.hero.LevelsWaiting(tok.properties --[[@as character]]) == 0
            Close(finished)
        end,
    }
    inner:AddChild(builder)

    args.host:AddChild(root)
    audio.FireSoundEvent("UI.WindowOpen")

    dmhub.Schedule(0.05, function()
        if mod.unloaded or root == nil or not root.valid or builder == nil then
            return
        end
        Layout()
        local at = nil
        if args.step ~= nil then
            at = {step = args.step}
        end
        builder:FireEventTree("heroBuilderOpen", at)
        CheckBlocks()
    end)
    return root
end
